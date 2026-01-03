/**
 * ReelForge M9.2 VanEQ DSP Instance
 *
 * AudioWorklet-based 6-band parametric equalizer DSP implementation.
 * Uses the vaneq-processor worklet for coefficient calculation and filtering.
 *
 * Signal flow (when worklet ready, not bypassed):
 *   inputGain → workletNode → wetGain → outputGain
 *                                ↑
 *   inputGain → bypassGain ──────┘ (mixed, but bypassGain = 0)
 *
 * Signal flow (when bypassed OR worklet not ready):
 *   inputGain → bypassGain → outputGain (bypass path active)
 *
 * Click-free bypass using 10ms gain ramps on wetGain and bypassGain.
 *
 * @module plugin/vaneqDSP
 */

import type { PluginDSPInstance } from './PluginDefinition';
import { unflattenVanEqParams } from './vaneqTypes';
import { ensureModuleLoaded } from './workletHost';
import { BYPASS_RAMP_SEC, BUFFER_SIZES } from '../core/audioConstants';
import { rfDebug } from '../core/dspMetrics';

// AudioWorklet URL - uses public folder for direct serving
// The worklet file is in public/worklets/ which Vite serves at /worklets/
const vaneqProcessorUrl = '/worklets/vaneq-processor.js';

/** Bypass ramp time in seconds (from audioConstants) */
const BYPASS_RAMP_TIME = BYPASS_RAMP_SEC;

/** Number of samples for equal-power crossfade curve */
const CROSSFADE_CURVE_SAMPLES = 64;

/**
 * Pre-calculated equal-power crossfade curves.
 *
 * Equal-power law: wet² + dry² = 1 at all points during crossfade.
 * This maintains constant perceived loudness (no bump/dip in the middle).
 *
 * FADE_IN:  sin(t * π/2) goes 0→1 (starts at 0, ends at 1)
 * FADE_OUT: cos(t * π/2) goes 1→0 (starts at 1, ends at 0)
 *
 * Verification at t=0.5 (midpoint):
 *   sin(0.5 * π/2) = sin(π/4) = 0.707
 *   cos(0.5 * π/2) = cos(π/4) = 0.707
 *   0.707² + 0.707² = 0.5 + 0.5 = 1.0 ✓
 */
const CROSSFADE_FADE_IN = new Float32Array(CROSSFADE_CURVE_SAMPLES);  // 0→1
const CROSSFADE_FADE_OUT = new Float32Array(CROSSFADE_CURVE_SAMPLES); // 1→0
for (let i = 0; i < CROSSFADE_CURVE_SAMPLES; i++) {
  const t = i / (CROSSFADE_CURVE_SAMPLES - 1);
  CROSSFADE_FADE_IN[i] = Math.sin(t * Math.PI / 2);
  CROSSFADE_FADE_OUT[i] = Math.cos(t * Math.PI / 2);
}

// Verify endpoints are exact (important for null test)
// Debug: FADE_IN[0]=0, FADE_IN[end]=1, FADE_OUT[0]=1, FADE_OUT[end]=0

// Legacy aliases for existing code
const CROSSFADE_WET_CURVE = CROSSFADE_FADE_IN;
const CROSSFADE_DRY_CURVE = CROSSFADE_FADE_OUT;

/** FFT size for analyzer (from audioConstants BUFFER_SIZES) */
const FFT_SIZE = BUFFER_SIZES.LARGE;

/** Meter update interval in ms (~30Hz) */
const METER_INTERVAL_MS = 33;

/** Meter data for remote analyzer display */
export interface VanEqMeterData {
  insertId: string;
  rmsL: number;
  rmsR: number;
  peakL: number;
  peakR: number;
  fftBins: Float32Array;
  sampleRate: number;
}

/** Meter callback type */
export type MeterCallback = (data: VanEqMeterData) => void;

/**
 * Validate that a param ID is a known VanEQ parameter.
 * Logs a warning if unknown - helps catch UI/DSP param ID mismatches.
 */
function assertKnownParam(paramId: string): void {
  const isKnown =
    paramId === 'outputGainDb' ||
    paramId === 'soloedBand' ||
    /^band[0-7]_(freqHz|gainDb|q|type|enabled)$/.test(paramId);

  if (!isKnown) {
    console.warn('[VanEqDSP] UNKNOWN PARAM ID:', paramId, '- check UI param naming');
  }
}

/**
 * VanEQ DSP instance implementing PluginDSPInstance.
 *
 * Note: This class requires async initialization.
 * Use VanEqDSP.create() factory method, not the constructor.
 */
export class VanEqDSP implements PluginDSPInstance {
  private readonly ctx: AudioContext;
  private readonly inputGain: GainNode;
  private readonly outputGain: GainNode;
  private readonly bypassGain: GainNode;
  private readonly wetGain: GainNode;
  private workletNode: AudioWorkletNode | null = null;
  private bypassed = false;
  private disposed = false;

  /** Pending params to apply once worklet is ready */
  private pendingParams: Record<string, number | string> | null = null;

  /** Idle state from worklet (no signal detected) */
  private _isIdle = true;
  private idleListeners: Set<(isIdle: boolean) => void> = new Set();

  /** Analyser for remote metering */
  private analyser: AnalyserNode | null = null;
  private meterCallback: MeterCallback | null = null;
  private meterInterval: ReturnType<typeof setInterval> | null = null;
  private fftBuffer: Float32Array<ArrayBuffer> | null = null;
  private _insertId: string | null = null;

  /** Hash of last applied params to prevent spam */
  private lastApplyHash = '';

  /** Enable verbose debug logging (set true only when debugging) */
  private debugLogs = false;

  /** Unique instance ID for debugging multi-instance issues */
  private readonly instanceId: number;
  private static instanceCounter = 0;


  /**
   * Private constructor. Use VanEqDSP.create() instead.
   */
  private constructor(ctx: AudioContext) {
    this.ctx = ctx;
    this.instanceId = ++VanEqDSP.instanceCounter;

    // Create gain nodes for routing
    this.inputGain = ctx.createGain();
    this.outputGain = ctx.createGain();
    this.bypassGain = ctx.createGain();
    this.wetGain = ctx.createGain();

    // CRITICAL: Start with bypass path ACTIVE (gain = 1) so signal passes through
    // immediately before worklet is ready. Once worklet is ready, we crossfade.
    this.bypassGain.gain.value = 1;
    this.wetGain.gain.value = 0; // Wet path silent until worklet ready

    // Connect bypass path (always connected, gain controls mixing)
    this.inputGain.connect(this.bypassGain);
    this.bypassGain.connect(this.outputGain);

    // Wet path output (worklet will be connected later)
    this.wetGain.connect(this.outputGain);

    rfDebug('VanEqDSP', `Instance #${this.instanceId} created`);
  }

  /**
   * Factory method to create a VanEqDSP instance.
   * Handles async worklet loading.
   *
   * @param ctx - The AudioContext
   * @returns Promise resolving to initialized VanEqDSP instance
   */
  static async create(ctx: AudioContext): Promise<VanEqDSP> {
    const instance = new VanEqDSP(ctx);
    await instance.initWorklet();
    return instance;
  }

  /**
   * Create a synchronous placeholder instance for the framework.
   * The worklet will be initialized asynchronously.
   * This matches the PluginDefinition.createDSP signature.
   */
  static createSync(ctx: AudioContext): VanEqDSP {
    const instance = new VanEqDSP(ctx);
    // Start worklet initialization in background
    instance.initWorklet().catch((err) => {
      console.error('[VanEqDSP] Failed to initialize worklet:', err);
    });
    return instance;
  }

  /**
   * Initialize the AudioWorklet node.
   */
  private async initWorklet(): Promise<void> {
    if (this.disposed) return;

    try {
      // Use Vite-imported worklet URL - works in both dev and prod
      const moduleUrl = vaneqProcessorUrl;

      // Ensure module is loaded (cached per context)
      await ensureModuleLoaded(this.ctx, moduleUrl);

      if (this.disposed) return;

      // Create the worklet node
      this.workletNode = new AudioWorkletNode(this.ctx, 'vaneq-processor', {
        numberOfInputs: 1,
        numberOfOutputs: 1,
        outputChannelCount: [2],
      });

      // Listen for messages from worklet (idle state)
      this.workletNode.port.onmessage = (event) => {
        if (event.data.type === 'idle') {
          this._isIdle = event.data.isIdle;
          // Notify all listeners
          this.idleListeners.forEach((listener) => listener(this._isIdle));
        }
      };

      // Connect worklet to wet gain (inputGain → worklet → wetGain → outputGain)
      this.inputGain.connect(this.workletNode);
      this.workletNode.connect(this.wetGain);

      rfDebug('VanEqDSP', 'Worklet loaded and connected');

      // Apply any pending params that arrived before worklet was ready
      if (this.pendingParams) {
        this.applyParams(this.pendingParams);
        this.pendingParams = null;
      }

      // Crossfade from bypass to wet path (unless already bypassed)
      if (!this.bypassed) {
        const now = this.ctx.currentTime;

        // Cancel any scheduled changes and set current values
        this.bypassGain.gain.cancelScheduledValues(now);
        this.wetGain.gain.cancelScheduledValues(now);
        this.bypassGain.gain.setValueAtTime(this.bypassGain.gain.value, now);
        this.wetGain.gain.setValueAtTime(this.wetGain.gain.value, now);

        // Equal-power crossfade: bypass→0 (cos), wet→1 (sin)
        this.bypassGain.gain.setValueCurveAtTime(CROSSFADE_DRY_CURVE, now, BYPASS_RAMP_TIME);
        this.wetGain.gain.setValueCurveAtTime(CROSSFADE_WET_CURVE, now, BYPASS_RAMP_TIME);

        rfDebug('VanEqDSP', 'Crossfading to wet path (worklet ready)');
      }
    } catch (err) {
      console.error('[VanEqDSP] Worklet initialization failed:', err);
      // Fallback: bypass path is already active, just log the error
      // Signal continues to flow through bypassGain → outputGain
    }
  }

  /**
   * Connect the plugin output to a destination node.
   */
  connect(destination: AudioNode): void {
    this.outputGain.connect(destination);
  }

  /**
   * Disconnect all outputs.
   */
  disconnect(): void {
    this.outputGain.disconnect();
  }

  /**
   * Dispose of all audio nodes and release resources.
   */
  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;

    // Stop metering
    this.stopMetering();

    try {
      this.inputGain.disconnect();
      this.bypassGain.disconnect();
      this.wetGain.disconnect();
      this.outputGain.disconnect();
      if (this.workletNode) {
        this.workletNode.disconnect();
        this.workletNode = null;
      }
      if (this.analyser) {
        this.analyser.disconnect();
        this.analyser = null;
      }
    } catch {
      // Ignore disconnection errors during disposal
    }
  }

  /**
   * Set bypass state with equal-power crossfade.
   * Uses sin/cos curves to maintain constant power during transition.
   *
   * @param bypassed - Whether to bypass the processing
   */
  setBypass(bypassed: boolean): void {
    if (this.bypassed === bypassed) {
      return;
    }
    this.bypassed = bypassed;

    const now = this.ctx.currentTime;

    // Cancel any scheduled changes
    this.bypassGain.gain.cancelScheduledValues(now);
    this.wetGain.gain.cancelScheduledValues(now);

    // Set current values immediately to avoid jumps
    this.bypassGain.gain.setValueAtTime(this.bypassGain.gain.value, now);
    this.wetGain.gain.setValueAtTime(this.wetGain.gain.value, now);

    if (bypassed) {
      // Crossfade: wet→0 (fade out), bypass→1 (fade in)
      // Use equal-power: wet follows cos curve (1→0), bypass follows sin curve (0→1)
      this.wetGain.gain.setValueCurveAtTime(CROSSFADE_DRY_CURVE, now, BYPASS_RAMP_TIME);
      this.bypassGain.gain.setValueCurveAtTime(CROSSFADE_WET_CURVE, now, BYPASS_RAMP_TIME);
    } else {
      // Crossfade: bypass→0 (fade out), wet→1 (fade in)
      // Only if worklet is ready
      if (this.workletNode) {
        this.bypassGain.gain.setValueCurveAtTime(CROSSFADE_DRY_CURVE, now, BYPASS_RAMP_TIME);
        this.wetGain.gain.setValueCurveAtTime(CROSSFADE_WET_CURVE, now, BYPASS_RAMP_TIME);
      }
      // If worklet not ready, stay on bypass path (bypass gains stay as-is)
    }
  }

  /**
   * Apply parameter values to the DSP nodes.
   * Sends update message to the worklet processor.
   * If worklet not ready yet, queues params to apply once initialized.
   *
   * @param params - Flat key-value map of parameter values
   */
  applyParams(params: Record<string, number | string>): void {
    // Validate all param IDs - catch UI/DSP mismatches early
    for (const paramId of Object.keys(params)) {
      assertKnownParam(paramId);
    }

    // SPAM PREVENTION: Skip if params haven't changed
    const hash = JSON.stringify(params);
    if (hash === this.lastApplyHash) {
      return; // Nothing new - skip worklet traffic and logging
    }
    this.lastApplyHash = hash;

    // [PARAM_RX] Log only when debugLogs enabled (reduce console spam)
    if (this.debugLogs) {
      const bandSummary = [];
      const enabledStatus = [];
      for (let i = 0; i < 8; i++) {
        const enabled = params[`band${i}_enabled`];
        const freq = params[`band${i}_freqHz`];
        const gain = params[`band${i}_gainDb`];
        const q = params[`band${i}_q`];
        const type = params[`band${i}_type`];
        enabledStatus.push(`B${i}:${enabled}`);
        if (enabled === 1) {
          const freqStr = typeof freq === 'number' ? freq.toFixed(0) : '?';
          const gainStr = typeof gain === 'number' ? gain.toFixed(1) : '?';
          const qStr = typeof q === 'number' ? q.toFixed(2) : '?';
          bandSummary.push(`B${i}(${freqStr}Hz,${gainStr}dB,Q${qStr},T${type ?? '?'})`);
        }
      }
      console.log(`[PARAM_RX] applyParams: workletReady=${!!this.workletNode} outputGain=${params.outputGainDb ?? 0}dB enabledStatus=[${enabledStatus.join(',')}] enabledBands=[${bandSummary.join(', ') || 'none'}]`);
    }

    if (!this.workletNode) {
      // Worklet not ready yet - queue latest params for later
      // Only keep latest params (no need to replay history)
      if (this.debugLogs) {
        console.log('[VanEqDSP] Worklet not ready, queuing params');
      }
      this.pendingParams = params;
      return;
    }

    // Unflatten params to structured format
    const structured = unflattenVanEqParams(params);

    // Log only when debugLogs enabled
    if (this.debugLogs) {
      const enabledBands = structured.bands
        .map((b, i) => b.enabled ? `band${i}(${b.freqHz}Hz,${b.gainDb}dB)` : null)
        .filter(Boolean);
      console.log(`[VanEqDSP] Sending to worklet: enabledBands=[${enabledBands.join(', ')}] outputGain=${structured.outputGainDb}dB`);
    }

    // Apply output gain on the AudioNode (NOT in worklet)
    // This ensures outputGain works even when bypassed
    const targetGain = Math.pow(10, structured.outputGainDb / 20);
    const now = this.ctx.currentTime;
    this.outputGain.gain.cancelScheduledValues(now);
    this.outputGain.gain.setValueAtTime(this.outputGain.gain.value, now);
    this.outputGain.gain.linearRampToValueAtTime(targetGain, now + 0.01); // 10ms smooth

    // Extract soloedBand if present (-1 = none, 0-7 = band index)
    const soloedBand = typeof params.soloedBand === 'number' ? params.soloedBand : -1;

    // Send to worklet (outputGain = 0 since we handle it on AudioNode now)
    this.workletNode.port.postMessage({
      type: 'update',
      bands: structured.bands,
      outputGain: 0, // Always 0dB in worklet, real gain on AudioNode
      soloedBand, // -1 = no solo, 0-7 = solo that band
    });
  }

  /**
   * Get the latency introduced by this plugin in samples.
   * VanEQ has zero latency (no lookahead).
   */
  getLatencySamples(): number {
    return 0;
  }

  /**
   * Get the input node for connecting from the previous stage.
   */
  getInputNode(): AudioNode {
    return this.inputGain;
  }

  /**
   * Get the output node for connecting to the next stage.
   */
  getOutputNode(): AudioNode {
    return this.outputGain;
  }

  /**
   * Check if the worklet is ready.
   */
  isReady(): boolean {
    return this.workletNode !== null;
  }

  /**
   * Reset filter state to clear DC offset and artifacts.
   * Call when audio stops or on project switch.
   */
  reset(): void {
    if (this.workletNode) {
      this.workletNode.port.postMessage({ type: 'reset' });
    }
  }

  /**
   * Set bypass state (PluginDSPInstance interface extension).
   * For VanEQ, setBypass is the same method.
   */
  setBypassed(bypassed: boolean): void {
    this.setBypass(bypassed);
  }

  /**
   * Get current idle state.
   * Idle means no signal above -120dBFS for ~200ms.
   */
  get isIdle(): boolean {
    return this._isIdle;
  }

  /**
   * Subscribe to idle state changes.
   * @param listener - Callback when idle state changes
   * @returns Unsubscribe function
   */
  onIdleChange(listener: (isIdle: boolean) => void): () => void {
    this.idleListeners.add(listener);
    return () => {
      this.idleListeners.delete(listener);
    };
  }

  /**
   * Set the insert ID for meter data identification.
   * Called by the host when associating this DSP with an insert.
   */
  setInsertId(insertId: string): void {
    console.debug(`[VanEqDSP #${this.instanceId}] setInsertId:`, insertId);
    this._insertId = insertId;
  }

  /**
   * Start remote metering for plugin window analyzer.
   * Creates an AnalyserNode and periodically calls the callback with meter data.
   *
   * IMPORTANT: Analyzer taps the POST-DSP signal (wetGain output), not the final mix.
   * This shows the actual EQ curve effect on the signal.
   *
   * @param callback - Called at ~30Hz with meter data
   */
  startMetering(callback: MeterCallback): void {
    console.debug(`[VanEqDSP #${this.instanceId}] startMetering called, insertId=${this._insertId}`);

    if (this.meterCallback) {
      console.debug(`[VanEqDSP #${this.instanceId}] Stopping existing metering first`);
      this.stopMetering();
    }

    // Create analyser node if needed
    if (!this.analyser) {
      this.analyser = this.ctx.createAnalyser();
      this.analyser.fftSize = FFT_SIZE;
      this.analyser.smoothingTimeConstant = 0.8;
      // Lower min decibels to catch quiet signals
      this.analyser.minDecibels = -100;
      this.analyser.maxDecibels = 0;

      // TAP THE OUTPUT (final signal after EQ or bypass)
      // This ensures analyzer works even when worklet is loading (bypass path active)
      // Shows the actual output regardless of wet/dry mixing state
      this.outputGain.connect(this.analyser);
      console.debug(`[VanEqDSP #${this.instanceId}] Created analyser, connected to outputGain`);
    }

    this.fftBuffer = new Float32Array(this.analyser.frequencyBinCount);
    this.meterCallback = callback;

    console.debug(`[VanEqDSP #${this.instanceId}] Started metering interval for ${this._insertId}`);

    // Start meter polling
    this.meterInterval = setInterval(() => {
      this.updateMeter();
    }, METER_INTERVAL_MS);
  }

  /**
   * Stop remote metering.
   */
  stopMetering(): void {
    if (this.meterInterval) {
      clearInterval(this.meterInterval);
      this.meterInterval = null;
    }
    this.meterCallback = null;
  }

  /**
   * Internal: Update meter and call callback.
   *
   * Includes noise gate: when signal is below -90dB, FFT is zeroed to prevent
   * displaying floating-point noise as visible spectrum.
   */
  private updateMeter(): void {
    if (!this.meterCallback || !this.analyser || !this.fftBuffer || !this._insertId) {
      // Only log occasionally to avoid spam
      if (Math.random() < 0.01) {
        console.debug('[VanEqDSP] updateMeter skipped:', {
          hasCallback: !!this.meterCallback,
          hasAnalyser: !!this.analyser,
          hasBuffer: !!this.fftBuffer,
          hasInsertId: !!this._insertId,
        });
      }
      return;
    }

    // Get FFT data in dB
    this.analyser.getFloatFrequencyData(this.fftBuffer);

    // NOISE GATE: Check if there's actual signal above noise floor
    // If peak is below -90dB, we're just seeing floating-point noise
    const NOISE_FLOOR_DB = -90;
    let peak = -Infinity;
    let sumSquares = 0;

    for (let i = 0; i < this.fftBuffer.length; i++) {
      if (this.fftBuffer[i] > peak) {
        peak = this.fftBuffer[i];
      }
      // Accumulate for RMS calculation
      const linear = Math.pow(10, this.fftBuffer[i] / 20);
      sumSquares += linear * linear;
    }

    // Calculate RMS from FFT data (before gating, for logging)
    const rms = Math.sqrt(sumSquares / this.fftBuffer.length);
    const rmsDb = 20 * Math.log10(Math.max(rms, 1e-10));

    // If peak is below noise floor, zero the FFT buffer
    // This eliminates the "sum" (noise) display when no audio is playing
    if (peak < NOISE_FLOOR_DB) {
      this.fftBuffer.fill(-100); // Fill with silence level
      this.meterCallback({
        insertId: this._insertId,
        rmsL: -100,
        rmsR: -100,
        peakL: -100,
        peakR: -100,
        fftBins: this.fftBuffer,
        sampleRate: this.ctx.sampleRate,
      });
      return;
    }

    this.meterCallback({
      insertId: this._insertId,
      rmsL: rmsDb,
      rmsR: rmsDb, // Mono approximation for now
      peakL: peak,
      peakR: peak, // Mono approximation for now
      fftBins: this.fftBuffer,
      sampleRate: this.ctx.sampleRate,
    });
  }

}

/**
 * Factory function for PluginDefinition.createDSP.
 * Returns a synchronous instance that initializes asynchronously.
 */
export function createVanEqDSP(ctx: AudioContext): PluginDSPInstance {
  return VanEqDSP.createSync(ctx);
}
