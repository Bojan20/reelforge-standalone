/**
 * ReelForge WASM Master Insert DSP
 *
 * High-performance DSP processor using Rust WASM kernel.
 * Provides 10-50x faster processing than Web Audio native nodes.
 *
 * This class can be used as an alternative to the native MasterInsertDSP
 * for CPU-intensive processing scenarios.
 *
 * Usage:
 * ```typescript
 * import { WasmMasterInsertDSP } from './core/dsp-wasm/WasmMasterInsertDSP';
 *
 * const dsp = new WasmMasterInsertDSP();
 * await dsp.initialize(audioContext, masterGain);
 *
 * // Configure EQ
 * dsp.setEQ([
 *   { type: 'lowshelf', frequency: 100, gain: 3, q: 0.7 },
 *   { type: 'peaking', frequency: 1000, gain: -2, q: 1.4 },
 *   { type: 'highshelf', frequency: 8000, gain: 2, q: 0.7 },
 * ]);
 *
 * // Configure compressor
 * dsp.setCompressor({
 *   thresholdDb: -18,
 *   ratio: 4,
 *   attackSec: 0.010,
 *   releaseSec: 0.100,
 *   kneeDb: 6,
 *   makeupDb: 2,
 * });
 *
 * // Configure limiter
 * dsp.setLimiter({
 *   ceilingDb: -0.3,
 *   releaseSec: 0.050,
 * });
 * ```
 */

import {
  initDspWasm,
  isDspWasmReady,
  calcLowpassCoeffs,
  calcHighpassCoeffs,
  calcPeakCoeffs,
  calcLowShelfCoeffs,
  calcHighShelfCoeffs,
  processBiquad,
  createBiquadState,
  processCompressor,
  createCompressorParams,
  createCompressorState,
  processLimiter,
  createLimiterState,
  applyGainSimd,
  calculateRmsSimd,
  calculatePeakSimd,
  type BiquadCoeffs,
  type BiquadState,
  type CompressorState,
  type LimiterState,
} from './index';
import { rfDebug } from '../dspMetrics';

/** EQ band configuration */
export interface WasmEQBand {
  type: 'lowshelf' | 'lowpass' | 'highpass' | 'peaking' | 'highshelf';
  frequency: number;
  gain: number;
  q: number;
}

/** Compressor configuration */
export interface WasmCompressorConfig {
  thresholdDb: number;
  ratio: number;
  attackSec: number;
  releaseSec: number;
  kneeDb: number;
  makeupDb: number;
}

/** Limiter configuration */
export interface WasmLimiterConfig {
  ceilingDb: number;
  releaseSec: number;
}

/** DSP chain state for a single channel */
interface ChannelState {
  eqStates: BiquadState[];
  compressorState: CompressorState;
  limiterState: LimiterState;
}

/** Metering data from DSP */
export interface WasmMeterData {
  peakL: number;
  peakR: number;
  rmsL: number;
  rmsR: number;
  gainReduction: number;
}

/**
 * WASM-based Master Insert DSP Processor
 *
 * Runs in AudioWorklet thread for real-time processing.
 * Uses SIMD-optimized Rust WASM for maximum performance.
 */
export class WasmMasterInsertDSP {
  private ctx: AudioContext | null = null;
  private workletNode: AudioWorkletNode | null = null;
  private masterGain: GainNode | null = null;
  private isConnected = false;
  private wasmReady = false;

  // DSP Configuration
  private eqBands: WasmEQBand[] = [];
  private eqCoeffs: BiquadCoeffs[] = [];
  private compressorEnabled = false;
  private compressorConfig: WasmCompressorConfig = createCompressorParams();
  private limiterEnabled = false;
  private limiterConfig: WasmLimiterConfig = { ceilingDb: -0.3, releaseSec: 0.050 };
  private inputGain = 1.0;
  private outputGain = 1.0;
  private bypass = false;

  // Channel state (for main thread ScriptProcessor fallback)
  private channelStates: ChannelState[] = [];
  private sampleRate = 48000;

  // Metering callback
  private meterCallback: ((data: WasmMeterData) => void) | null = null;

  /**
   * Initialize the WASM DSP chain.
   * Must be called before using any DSP functions.
   */
  async initialize(ctx: AudioContext, masterGain: GainNode): Promise<void> {
    if (this.isConnected) {
      rfDebug('WasmMasterInsertDSP', 'Already initialized');
      return;
    }

    this.ctx = ctx;
    this.masterGain = masterGain;
    this.sampleRate = ctx.sampleRate;

    // Initialize WASM module
    await initDspWasm();
    this.wasmReady = isDspWasmReady();

    if (!this.wasmReady) {
      throw new Error('Failed to initialize WASM DSP module');
    }

    // Initialize channel states (stereo)
    this.channelStates = [
      this.createChannelState(),
      this.createChannelState(),
    ];

    // Try to create AudioWorklet node
    try {
      await this.createWorkletNode();
    } catch (e) {
      rfDebug('WasmMasterInsertDSP', `AudioWorklet failed, using ScriptProcessor fallback: ${e}`);
      this.createScriptProcessorFallback();
    }

    this.isConnected = true;
    rfDebug('WasmMasterInsertDSP', `Initialized (sampleRate: ${this.sampleRate})`);
  }

  /**
   * Dispose and cleanup all resources.
   */
  dispose(): void {
    if (!this.isConnected) return;

    try {
      if (this.workletNode) {
        this.workletNode.disconnect();
        this.workletNode = null;
      }
      if (this.masterGain && this.ctx) {
        this.masterGain.disconnect();
        this.masterGain.connect(this.ctx.destination);
      }
    } catch {
      // Ignore
    }

    this.ctx = null;
    this.masterGain = null;
    this.channelStates = [];
    this.isConnected = false;
    this.wasmReady = false;

    rfDebug('WasmMasterInsertDSP', 'Disposed');
  }

  /**
   * Set EQ bands.
   * Recalculates biquad coefficients for the current sample rate.
   */
  setEQ(bands: WasmEQBand[]): void {
    this.eqBands = bands;
    this.eqCoeffs = bands.map((band) => this.calcBiquadCoeffs(band));

    // Ensure enough state objects for each band
    for (const state of this.channelStates) {
      while (state.eqStates.length < bands.length) {
        state.eqStates.push(createBiquadState());
      }
    }

    // Send to worklet if available
    this.sendToWorklet('set-eq', { coeffs: this.eqCoeffs });

    rfDebug('WasmMasterInsertDSP', `EQ set: ${bands.length} bands`);
  }

  /**
   * Set compressor parameters.
   */
  setCompressor(config: WasmCompressorConfig, enabled = true): void {
    this.compressorConfig = config;
    this.compressorEnabled = enabled;

    this.sendToWorklet('set-compressor', { config, enabled });

    rfDebug('WasmMasterInsertDSP', `Compressor ${enabled ? 'enabled' : 'disabled'}`);
  }

  /**
   * Set limiter parameters.
   */
  setLimiter(config: WasmLimiterConfig, enabled = true): void {
    this.limiterConfig = config;
    this.limiterEnabled = enabled;

    this.sendToWorklet('set-limiter', { config, enabled });

    rfDebug('WasmMasterInsertDSP', `Limiter ${enabled ? 'enabled' : 'disabled'}`);
  }

  /**
   * Set input gain (before processing).
   */
  setInputGain(gainDb: number): void {
    this.inputGain = Math.pow(10, gainDb / 20);
    this.sendToWorklet('set-input-gain', { gain: this.inputGain });
  }

  /**
   * Set output gain (after processing).
   */
  setOutputGain(gainDb: number): void {
    this.outputGain = Math.pow(10, gainDb / 20);
    this.sendToWorklet('set-output-gain', { gain: this.outputGain });
  }

  /**
   * Set bypass mode.
   */
  setBypass(bypass: boolean): void {
    this.bypass = bypass;
    this.sendToWorklet('set-bypass', { bypass });

    rfDebug('WasmMasterInsertDSP', `Bypass: ${bypass}`);
  }

  /**
   * Set metering callback.
   */
  onMeter(callback: (data: WasmMeterData) => void): void {
    this.meterCallback = callback;
  }

  /**
   * Reset all DSP state (clear filter history, compressor envelope, etc.)
   */
  reset(): void {
    for (const state of this.channelStates) {
      state.eqStates.forEach((s) => {
        s.z1 = 0;
        s.z2 = 0;
      });
      state.compressorState.envelope = 0;
      state.compressorState.gainReductionDb = 0;
      state.limiterState.envelope = 0;
      state.limiterState.gain = 1;
    }

    this.sendToWorklet('reset', {});

    rfDebug('WasmMasterInsertDSP', 'State reset');
  }

  /**
   * Check if WASM is ready.
   */
  isReady(): boolean {
    return this.wasmReady && this.isConnected;
  }

  /**
   * Get current sample rate.
   */
  getSampleRate(): number {
    return this.sampleRate;
  }

  /**
   * Get current EQ band configuration.
   */
  getEQBands(): WasmEQBand[] {
    return this.eqBands;
  }

  // ============ Private Methods ============

  private createChannelState(): ChannelState {
    return {
      eqStates: [],
      compressorState: createCompressorState(),
      limiterState: createLimiterState(),
    };
  }

  private calcBiquadCoeffs(band: WasmEQBand): BiquadCoeffs {
    switch (band.type) {
      case 'lowshelf':
        return calcLowShelfCoeffs(this.sampleRate, band.frequency, band.q, band.gain);
      case 'highshelf':
        return calcHighShelfCoeffs(this.sampleRate, band.frequency, band.q, band.gain);
      case 'peaking':
        return calcPeakCoeffs(this.sampleRate, band.frequency, band.q, band.gain);
      case 'lowpass':
        return calcLowpassCoeffs(this.sampleRate, band.frequency, band.q);
      case 'highpass':
        return calcHighpassCoeffs(this.sampleRate, band.frequency, band.q);
      default:
        return calcPeakCoeffs(this.sampleRate, band.frequency, band.q, band.gain);
    }
  }

  private async createWorkletNode(): Promise<void> {
    if (!this.ctx || !this.masterGain) return;

    // Register worklet processor
    const workletUrl = new URL('./wasm-dsp-processor.js', import.meta.url);
    await this.ctx.audioWorklet.addModule(workletUrl);

    // Create worklet node
    this.workletNode = new AudioWorkletNode(this.ctx, 'wasm-dsp-processor', {
      numberOfInputs: 1,
      numberOfOutputs: 1,
      outputChannelCount: [2],
    });

    // Handle messages from worklet
    this.workletNode.port.onmessage = (event) => {
      this.handleWorkletMessage(event.data);
    };

    // Wire up audio graph
    this.masterGain.disconnect();
    this.masterGain.connect(this.workletNode);
    this.workletNode.connect(this.ctx.destination);

    // Initialize WASM in worklet
    const wasmUrl = new URL('../../../crates/dsp-kernel/pkg/reelforge_dsp.js', import.meta.url);
    this.workletNode.port.postMessage({
      type: 'init-wasm',
      wasmUrl: wasmUrl.href,
    });

    rfDebug('WasmMasterInsertDSP', 'AudioWorklet created');
  }

  private createScriptProcessorFallback(): void {
    // ScriptProcessorNode fallback for browsers without AudioWorklet support
    // Note: This is deprecated but provides compatibility
    if (!this.ctx || !this.masterGain) return;

    const bufferSize = 1024;
    const scriptNode = this.ctx.createScriptProcessor(bufferSize, 2, 2);

    scriptNode.onaudioprocess = (event) => {
      if (this.bypass) {
        // Pass through
        for (let ch = 0; ch < 2; ch++) {
          const input = event.inputBuffer.getChannelData(ch);
          const output = event.outputBuffer.getChannelData(ch);
          output.set(input);
        }
        return;
      }

      this.processBuffer(event.inputBuffer, event.outputBuffer);
    };

    // Wire up audio graph
    this.masterGain.disconnect();
    this.masterGain.connect(scriptNode);
    scriptNode.connect(this.ctx.destination);

    rfDebug('WasmMasterInsertDSP', 'ScriptProcessor fallback created');
  }

  /**
   * Process audio buffer using WASM DSP (for ScriptProcessor fallback)
   */
  private processBuffer(input: AudioBuffer, output: AudioBuffer): void {
    const numChannels = Math.min(input.numberOfChannels, 2);

    for (let ch = 0; ch < numChannels; ch++) {
      const inputData = input.getChannelData(ch);
      const outputData = output.getChannelData(ch);
      const state = this.channelStates[ch];

      // Copy input to output (in-place processing)
      outputData.set(inputData);

      // Apply input gain (SIMD)
      if (this.inputGain !== 1.0) {
        applyGainSimd(outputData, this.inputGain);
      }

      // Apply EQ bands
      for (let i = 0; i < this.eqCoeffs.length; i++) {
        processBiquad(outputData, this.eqCoeffs[i], state.eqStates[i]);
      }

      // Apply compressor
      if (this.compressorEnabled) {
        processCompressor(
          outputData,
          this.compressorConfig,
          state.compressorState,
          this.sampleRate
        );
      }

      // Apply limiter
      if (this.limiterEnabled) {
        processLimiter(
          outputData,
          this.limiterConfig.ceilingDb,
          this.limiterConfig.releaseSec,
          this.sampleRate,
          state.limiterState
        );
      }

      // Apply output gain (SIMD)
      if (this.outputGain !== 1.0) {
        applyGainSimd(outputData, this.outputGain);
      }
    }

    // Calculate metering
    if (this.meterCallback && numChannels >= 2) {
      const left = output.getChannelData(0);
      const right = output.getChannelData(1);

      this.meterCallback({
        peakL: calculatePeakSimd(left),
        peakR: calculatePeakSimd(right),
        rmsL: calculateRmsSimd(left),
        rmsR: calculateRmsSimd(right),
        gainReduction: this.channelStates[0].compressorState.gainReductionDb,
      });
    }
  }

  private handleWorkletMessage(data: { type: string; [key: string]: unknown }): void {
    switch (data.type) {
      case 'wasm-ready':
        rfDebug('WasmMasterInsertDSP', 'WASM ready in worklet');
        // Send current configuration
        this.syncWorkletState();
        break;

      case 'meter':
        if (this.meterCallback) {
          this.meterCallback(data as unknown as WasmMeterData);
        }
        break;

      case 'error':
        console.error('[WasmMasterInsertDSP] Worklet error:', data.error);
        break;
    }
  }

  private sendToWorklet(type: string, data: Record<string, unknown>): void {
    if (this.workletNode) {
      this.workletNode.port.postMessage({ type, ...data });
    }
  }

  private syncWorkletState(): void {
    this.sendToWorklet('set-eq', { coeffs: this.eqCoeffs });
    this.sendToWorklet('set-compressor', {
      config: this.compressorConfig,
      enabled: this.compressorEnabled,
    });
    this.sendToWorklet('set-limiter', {
      config: this.limiterConfig,
      enabled: this.limiterEnabled,
    });
    this.sendToWorklet('set-input-gain', { gain: this.inputGain });
    this.sendToWorklet('set-output-gain', { gain: this.outputGain });
    this.sendToWorklet('set-bypass', { bypass: this.bypass });
  }
}

/**
 * Singleton instance for global use.
 */
export const wasmMasterInsertDSP = new WasmMasterInsertDSP();
