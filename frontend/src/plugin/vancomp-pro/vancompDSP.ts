/**
 * ReelForge VanComp Pro - DSP Instance
 *
 * AudioWorklet-based compressor DSP implementation.
 * Uses vancomp-processor worklet for professional compression.
 *
 * Features:
 * - Soft knee compression
 * - Auto-makeup gain
 * - Parallel (NY) compression
 * - Real-time GR metering
 *
 * Signal flow (when worklet ready, not bypassed):
 *   inputGain → workletNode → wetGain → outputGain
 *
 * Signal flow (when bypassed OR worklet not ready):
 *   inputGain → bypassGain → outputGain (unity gain passthrough)
 *
 * @module plugin/vancomp-pro/vancompDSP
 */

import type { PluginDSPInstance } from '../PluginDefinition';
import { ensureModuleLoaded } from '../workletHost';
import { BYPASS_RAMP_SEC } from '../../core/audioConstants';
import { rfDebug } from '../../core/dspMetrics';

// AudioWorklet URL
const vancompProcessorUrl = '/worklets/vancomp-processor.js';

/** Bypass ramp time in seconds */
const BYPASS_RAMP_TIME = BYPASS_RAMP_SEC;

/** Equal-power crossfade curve samples */
const CROSSFADE_CURVE_SAMPLES = 64;

// Pre-calculated equal-power crossfade curves
const CROSSFADE_FADE_IN = new Float32Array(CROSSFADE_CURVE_SAMPLES);
const CROSSFADE_FADE_OUT = new Float32Array(CROSSFADE_CURVE_SAMPLES);
for (let i = 0; i < CROSSFADE_CURVE_SAMPLES; i++) {
  const t = i / (CROSSFADE_CURVE_SAMPLES - 1);
  CROSSFADE_FADE_IN[i] = Math.sin((t * Math.PI) / 2);
  CROSSFADE_FADE_OUT[i] = Math.cos((t * Math.PI) / 2);
}

/** Meter callback type */
export type VanCompMeterCallback = (data: VanCompMeterData) => void;

/** Meter data from worklet */
export interface VanCompMeterData {
  insertId: string;
  gainReduction: number; // dB
}

/**
 * VanComp Pro DSP instance implementing PluginDSPInstance.
 */
export class VanCompDSP implements PluginDSPInstance {
  private readonly ctx: AudioContext;
  private readonly inputGain: GainNode;
  private readonly outputGain: GainNode;
  private readonly bypassGain: GainNode;
  private readonly wetGain: GainNode;
  private workletNode: AudioWorkletNode | null = null;
  private bypassed = false;
  private disposed = false;

  /** Pending params to apply once worklet is ready */
  private pendingParams: Record<string, number> | null = null;

  /** Meter callback */
  private meterCallback: VanCompMeterCallback | null = null;
  private _insertId: string | null = null;

  /** Hash of last applied params to prevent spam */
  private lastApplyHash = '';

  /** Unique instance ID for debugging */
  private readonly instanceId: number;
  private static instanceCounter = 0;

  private constructor(ctx: AudioContext) {
    this.ctx = ctx;
    this.instanceId = ++VanCompDSP.instanceCounter;

    // Create gain nodes for routing
    this.inputGain = ctx.createGain();
    this.outputGain = ctx.createGain();
    this.bypassGain = ctx.createGain();
    this.wetGain = ctx.createGain();

    // Start with bypass path ACTIVE
    this.bypassGain.gain.value = 1;
    this.wetGain.gain.value = 0;

    // Connect bypass path
    this.inputGain.connect(this.bypassGain);
    this.bypassGain.connect(this.outputGain);

    // Wet path output (worklet connected later)
    this.wetGain.connect(this.outputGain);

    rfDebug('VanCompDSP', `Instance #${this.instanceId} created`);
  }

  /**
   * Create a synchronous instance for the framework.
   */
  static createSync(ctx: AudioContext): VanCompDSP {
    const instance = new VanCompDSP(ctx);
    instance.initWorklet().catch((err) => {
      console.error('[VanCompDSP] Failed to initialize worklet:', err);
    });
    return instance;
  }

  private async initWorklet(): Promise<void> {
    if (this.disposed) return;

    try {
      await ensureModuleLoaded(this.ctx, vancompProcessorUrl);

      if (this.disposed) return;

      this.workletNode = new AudioWorkletNode(this.ctx, 'vancomp-processor', {
        numberOfInputs: 1,
        numberOfOutputs: 1,
        outputChannelCount: [2],
      });

      // Listen for meter messages
      this.workletNode.port.onmessage = (event) => {
        if (event.data.type === 'meter' && this.meterCallback && this._insertId) {
          this.meterCallback({
            insertId: this._insertId,
            gainReduction: event.data.gainReduction,
          });
        }
      };

      // Connect worklet to wet gain
      this.inputGain.connect(this.workletNode);
      this.workletNode.connect(this.wetGain);

      rfDebug('VanCompDSP', 'Worklet loaded and connected');

      // Apply pending params
      if (this.pendingParams) {
        this.applyParams(this.pendingParams);
        this.pendingParams = null;
      }

      // Crossfade from bypass to wet path
      if (!this.bypassed) {
        const now = this.ctx.currentTime;
        this.bypassGain.gain.cancelScheduledValues(now);
        this.wetGain.gain.cancelScheduledValues(now);
        this.bypassGain.gain.setValueAtTime(this.bypassGain.gain.value, now);
        this.wetGain.gain.setValueAtTime(this.wetGain.gain.value, now);
        this.bypassGain.gain.setValueCurveAtTime(CROSSFADE_FADE_OUT, now, BYPASS_RAMP_TIME);
        this.wetGain.gain.setValueCurveAtTime(CROSSFADE_FADE_IN, now, BYPASS_RAMP_TIME);
      }
    } catch (err) {
      console.error('[VanCompDSP] Worklet initialization failed:', err);
    }
  }

  connect(destination: AudioNode): void {
    this.outputGain.connect(destination);
  }

  disconnect(): void {
    this.outputGain.disconnect();
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;

    try {
      this.inputGain.disconnect();
      this.bypassGain.disconnect();
      this.wetGain.disconnect();
      this.outputGain.disconnect();
      if (this.workletNode) {
        this.workletNode.disconnect();
        this.workletNode = null;
      }
    } catch {
      // Ignore
    }
  }

  setBypass(bypassed: boolean): void {
    if (this.bypassed === bypassed) return;
    this.bypassed = bypassed;

    const now = this.ctx.currentTime;
    this.bypassGain.gain.cancelScheduledValues(now);
    this.wetGain.gain.cancelScheduledValues(now);
    this.bypassGain.gain.setValueAtTime(this.bypassGain.gain.value, now);
    this.wetGain.gain.setValueAtTime(this.wetGain.gain.value, now);

    if (bypassed) {
      this.wetGain.gain.setValueCurveAtTime(CROSSFADE_FADE_OUT, now, BYPASS_RAMP_TIME);
      this.bypassGain.gain.setValueCurveAtTime(CROSSFADE_FADE_IN, now, BYPASS_RAMP_TIME);
    } else if (this.workletNode) {
      this.bypassGain.gain.setValueCurveAtTime(CROSSFADE_FADE_OUT, now, BYPASS_RAMP_TIME);
      this.wetGain.gain.setValueCurveAtTime(CROSSFADE_FADE_IN, now, BYPASS_RAMP_TIME);
    }

    // Notify worklet
    if (this.workletNode) {
      this.workletNode.port.postMessage({ type: 'bypass', bypassed });
    }
  }

  applyParams(params: Record<string, number | string>): void {
    const hash = JSON.stringify(params);
    if (hash === this.lastApplyHash) return;
    this.lastApplyHash = hash;

    if (!this.workletNode) {
      this.pendingParams = params as Record<string, number>;
      return;
    }

    // Send to worklet
    this.workletNode.port.postMessage({
      type: 'update',
      params: {
        threshold: params.threshold,
        ratio: params.ratio,
        attack: params.attack,
        release: params.release,
        knee: params.knee,
        makeup: params.makeup,
        mix: params.mix,
        autoMakeup: params.autoMakeup,
      },
    });
  }

  getLatencySamples(): number {
    // No look-ahead by default
    return 0;
  }

  getInputNode(): AudioNode {
    return this.inputGain;
  }

  getOutputNode(): AudioNode {
    return this.outputGain;
  }

  isReady(): boolean {
    return this.workletNode !== null;
  }

  reset(): void {
    if (this.workletNode) {
      this.workletNode.port.postMessage({ type: 'reset' });
    }
  }

  setBypassed(bypassed: boolean): void {
    this.setBypass(bypassed);
  }

  setInsertId(insertId: string): void {
    this._insertId = insertId;
  }

  /**
   * Start metering for GR visualization.
   */
  startMetering(callback: VanCompMeterCallback): void {
    this.meterCallback = callback;
  }

  /**
   * Stop metering.
   */
  stopMetering(): void {
    this.meterCallback = null;
  }
}

/**
 * Factory function for PluginDefinition.createDSP.
 */
export function createVanCompDSP(audioContext: AudioContext): PluginDSPInstance {
  return VanCompDSP.createSync(audioContext);
}
