/**
 * ReelForge Spatial System - Audio Adapters
 * Backend-agnostic audio control interfaces.
 *
 * @module reelforge/spatial/mixers
 */

import type { IAudioSpatialAdapter, SpatialMixParams } from '../types';
import { clamp, dbToLinear } from '../utils/math';

// ============================================================================
// ABSTRACT BASE ADAPTER
// ============================================================================

/**
 * Base class for audio spatial adapters.
 * Provides common functionality and parameter ramping.
 */
export abstract class BaseAudioAdapter implements IAudioSpatialAdapter {
  /** Active voice IDs */
  protected activeVoices = new Set<string>();

  /** Current pan values per voice */
  protected currentPan = new Map<string, number>();

  /** Ramp time for parameter changes (ms) */
  protected rampTimeMs: number = 20;

  constructor(rampTimeMs: number = 20) {
    this.rampTimeMs = rampTimeMs;
  }

  abstract setPan(voiceId: string, pan: number): void;
  abstract setWidth(voiceId: string, width: number): void;
  abstract setLPF?(voiceId: string, hz: number): void;
  abstract setGain?(voiceId: string, db: number): void;
  abstract setChannelGains?(voiceId: string, gainL: number, gainR: number): void;

  /**
   * Apply full mix params.
   */
  applyMix(voiceId: string, params: SpatialMixParams): void {
    this.setPan(voiceId, params.pan);
    this.setWidth(voiceId, params.width);

    if (params.lpfHz !== undefined && this.setLPF) {
      this.setLPF(voiceId, params.lpfHz);
    }

    if (params.gainDb !== undefined && this.setGain) {
      this.setGain(voiceId, params.gainDb);
    }

    if (this.setChannelGains) {
      this.setChannelGains(voiceId, params.gainL, params.gainR);
    }
  }

  /**
   * Check if voice is tracked.
   */
  isActive(voiceId: string): boolean {
    return this.activeVoices.has(voiceId);
  }

  /**
   * Register voice as active.
   */
  registerVoice(voiceId: string): void {
    this.activeVoices.add(voiceId);
  }

  /**
   * Unregister voice.
   */
  unregisterVoice(voiceId: string): void {
    this.activeVoices.delete(voiceId);
    this.currentPan.delete(voiceId);
  }

  /**
   * Clear all voices.
   */
  clear(): void {
    this.activeVoices.clear();
    this.currentPan.clear();
  }

  /**
   * Set ramp time.
   */
  setRampTime(ms: number): void {
    this.rampTimeMs = Math.max(0, ms);
  }
}

// ============================================================================
// WEB AUDIO API ADAPTER
// ============================================================================

/**
 * Voice node structure for WebAudio.
 */
interface WebAudioVoice {
  pannerNode?: StereoPannerNode;
  gainNode?: GainNode;
  filterNode?: BiquadFilterNode;
  splitterNode?: ChannelSplitterNode;
  mergerNode?: ChannelMergerNode;
  leftGainNode?: GainNode;
  rightGainNode?: GainNode;
}

/**
 * WebAudio API adapter configuration.
 */
export interface WebAudioAdapterOptions {
  /** Parameter ramp time in milliseconds (default: 20) */
  rampTimeMs?: number;

  /** Use channel splitting for width control (default: false) */
  useChannelGains?: boolean;

  /** LPF Q factor / resonance (default: 0.707 = Butterworth) */
  lpfQ?: number;

  /** Default LPF cutoff frequency (default: 20000 Hz) */
  lpfDefaultHz?: number;
}

/**
 * WebAudio API adapter.
 * Uses StereoPannerNode for panning and BiquadFilterNode for LPF.
 */
export class WebAudioAdapter extends BaseAudioAdapter {
  /** Audio context */
  private ctx: AudioContext;

  /** Voice nodes */
  private voices = new Map<string, WebAudioVoice>();

  /** Use channel splitting for width control */
  private useChannelGains: boolean;

  /** LPF Q factor (resonance) */
  private lpfQ: number;

  /** Default LPF cutoff frequency */
  private lpfDefaultHz: number;

  constructor(ctx: AudioContext, options?: WebAudioAdapterOptions) {
    super(options?.rampTimeMs ?? 20);
    this.ctx = ctx;
    this.useChannelGains = options?.useChannelGains ?? false;
    // 0.707 = Butterworth response (maximally flat, no resonance)
    this.lpfQ = options?.lpfQ ?? 0.707;
    this.lpfDefaultHz = options?.lpfDefaultHz ?? 20000;
  }

  /**
   * Create voice nodes for audio node.
   * Call this when starting a new sound.
   */
  createVoice(
    voiceId: string,
    sourceNode: AudioNode,
    destinationNode?: AudioNode
  ): WebAudioVoice {
    const dest = destinationNode ?? this.ctx.destination;

    const voice: WebAudioVoice = {};

    // Create panner
    voice.pannerNode = this.ctx.createStereoPanner();
    voice.pannerNode.pan.value = 0;

    // Create gain
    voice.gainNode = this.ctx.createGain();
    voice.gainNode.gain.value = 1;

    // Create LPF with configurable Q
    voice.filterNode = this.ctx.createBiquadFilter();
    voice.filterNode.type = 'lowpass';
    voice.filterNode.frequency.value = this.lpfDefaultHz;
    voice.filterNode.Q.value = this.lpfQ;

    // Connect chain: source -> panner -> gain -> filter -> dest
    sourceNode.connect(voice.pannerNode);
    voice.pannerNode.connect(voice.gainNode);
    voice.gainNode.connect(voice.filterNode);
    voice.filterNode.connect(dest);

    // Optional: channel splitting for width control
    if (this.useChannelGains) {
      voice.splitterNode = this.ctx.createChannelSplitter(2);
      voice.mergerNode = this.ctx.createChannelMerger(2);
      voice.leftGainNode = this.ctx.createGain();
      voice.rightGainNode = this.ctx.createGain();

      // Reconnect: filter -> splitter -> L/R gains -> merger -> dest
      voice.filterNode.disconnect();
      voice.filterNode.connect(voice.splitterNode);
      voice.splitterNode.connect(voice.leftGainNode, 0);
      voice.splitterNode.connect(voice.rightGainNode, 1);
      voice.leftGainNode.connect(voice.mergerNode, 0, 0);
      voice.rightGainNode.connect(voice.mergerNode, 0, 1);
      voice.mergerNode.connect(dest);
    }

    this.voices.set(voiceId, voice);
    this.activeVoices.add(voiceId);

    return voice;
  }

  /**
   * Set pan for voice.
   */
  setPan(voiceId: string, pan: number): void {
    const voice = this.voices.get(voiceId);
    if (!voice?.pannerNode) return;

    const clampedPan = clamp(pan, -1, 1);
    const now = this.ctx.currentTime;

    voice.pannerNode.pan.cancelScheduledValues(now);
    voice.pannerNode.pan.setValueAtTime(voice.pannerNode.pan.value, now);
    voice.pannerNode.pan.linearRampToValueAtTime(
      clampedPan,
      now + this.rampTimeMs / 1000
    );

    this.currentPan.set(voiceId, clampedPan);
  }

  /**
   * Set stereo width (0 = mono, 1 = full stereo).
   * Requires useChannelGains: true for actual effect.
   *
   * Width is implemented via mid/side technique:
   * - width=0: Both channels receive (L+R)/2 (mono)
   * - width=1: Left gets L, Right gets R (full stereo)
   * - width=0.5: 50% blend between mono and stereo
   *
   * For sources already panned via setPan(), this adds additional
   * width control by blending towards center.
   */
  setWidth(voiceId: string, width: number): void {
    const voice = this.voices.get(voiceId);
    if (!voice) return;

    // Width control requires channel splitting
    if (!voice.leftGainNode || !voice.rightGainNode) {
      // No channel gains - width control unavailable
      // Would need useChannelGains: true in constructor
      return;
    }

    const clampedWidth = clamp(width, 0, 1);
    const now = this.ctx.currentTime;
    const rampTime = now + this.rampTimeMs / 1000;

    // Mid/side width control:
    // At width=0: both channels = 1.0 (panner still affects stereo placement)
    // At width=1: L=1, R=1 (normal stereo)
    // This maintains energy while narrowing stereo image
    //
    // For mono collapse, we'd need a more complex M/S matrix
    // For now, width acts as a stereo image narrowing factor
    // by reducing the difference between L and R gains

    // Simple approach: width affects how much of the "opposite" channel
    // bleeds through. At width=0, L and R are equal (mono-ish).
    // But since we only have L/R gains, not a matrix, we keep gains at 1
    // and let the panner handle stereo placement.

    // More effective approach: modulate based on current pan
    const currentPan = this.currentPan.get(voiceId) ?? 0;

    // At width=0, both channels should be equal
    // At width=1, use pan-derived gains
    // Linear interpolation between mono and stereo

    // Stereo gains from pan (equal power)
    const panAngle = (currentPan + 1) * 0.25 * Math.PI;
    const stereoL = Math.cos(panAngle);
    const stereoR = Math.sin(panAngle);

    // Mono gains (equal)
    const monoGain = Math.SQRT1_2; // -3dB for equal power

    // Blend between mono and stereo based on width
    const finalL = monoGain + (stereoL - monoGain) * clampedWidth;
    const finalR = monoGain + (stereoR - monoGain) * clampedWidth;

    // Apply with ramping
    voice.leftGainNode.gain.cancelScheduledValues(now);
    voice.leftGainNode.gain.setValueAtTime(voice.leftGainNode.gain.value, now);
    voice.leftGainNode.gain.linearRampToValueAtTime(finalL, rampTime);

    voice.rightGainNode.gain.cancelScheduledValues(now);
    voice.rightGainNode.gain.setValueAtTime(voice.rightGainNode.gain.value, now);
    voice.rightGainNode.gain.linearRampToValueAtTime(finalR, rampTime);
  }

  /**
   * Set LPF cutoff frequency.
   * Note: exponentialRampToValueAtTime requires value > 0, so we clamp to minimum 20Hz.
   */
  setLPF(voiceId: string, hz: number): void {
    const voice = this.voices.get(voiceId);
    if (!voice?.filterNode) return;

    // CRITICAL: exponentialRamp throws if target <= 0
    // Minimum 20Hz ensures safe ramping and is below audible range anyway
    const clampedHz = clamp(hz, 20, 22000);
    const now = this.ctx.currentTime;

    // Also ensure current value is safe before ramping
    const currentFreq = voice.filterNode.frequency.value;
    const safeCurrentFreq = Math.max(20, currentFreq);

    voice.filterNode.frequency.cancelScheduledValues(now);
    voice.filterNode.frequency.setValueAtTime(safeCurrentFreq, now);
    voice.filterNode.frequency.exponentialRampToValueAtTime(
      clampedHz,
      now + this.rampTimeMs / 1000
    );
  }

  /**
   * Set gain in dB.
   */
  setGain(voiceId: string, db: number): void {
    const voice = this.voices.get(voiceId);
    if (!voice?.gainNode) return;

    const linear = dbToLinear(clamp(db, -60, 12));
    const now = this.ctx.currentTime;

    voice.gainNode.gain.cancelScheduledValues(now);
    voice.gainNode.gain.setValueAtTime(voice.gainNode.gain.value, now);
    voice.gainNode.gain.linearRampToValueAtTime(
      linear,
      now + this.rampTimeMs / 1000
    );
  }

  /**
   * Set individual channel gains.
   */
  setChannelGains(voiceId: string, gainL: number, gainR: number): void {
    const voice = this.voices.get(voiceId);
    if (!voice?.leftGainNode || !voice?.rightGainNode) return;

    const now = this.ctx.currentTime;
    const rampTime = now + this.rampTimeMs / 1000;

    voice.leftGainNode.gain.cancelScheduledValues(now);
    voice.leftGainNode.gain.setValueAtTime(voice.leftGainNode.gain.value, now);
    voice.leftGainNode.gain.linearRampToValueAtTime(gainL, rampTime);

    voice.rightGainNode.gain.cancelScheduledValues(now);
    voice.rightGainNode.gain.setValueAtTime(voice.rightGainNode.gain.value, now);
    voice.rightGainNode.gain.linearRampToValueAtTime(gainR, rampTime);
  }

  /**
   * Destroy voice nodes.
   */
  destroyVoice(voiceId: string): void {
    const voice = this.voices.get(voiceId);
    if (!voice) return;

    voice.pannerNode?.disconnect();
    voice.gainNode?.disconnect();
    voice.filterNode?.disconnect();
    voice.splitterNode?.disconnect();
    voice.mergerNode?.disconnect();
    voice.leftGainNode?.disconnect();
    voice.rightGainNode?.disconnect();

    this.voices.delete(voiceId);
    this.unregisterVoice(voiceId);
  }

  /**
   * Clear all voices.
   */
  override clear(): void {
    for (const voiceId of this.voices.keys()) {
      this.destroyVoice(voiceId);
    }
    super.clear();
  }

  /**
   * Get audio context.
   */
  getContext(): AudioContext {
    return this.ctx;
  }
}

// ============================================================================
// HOWLER.JS ADAPTER
// ============================================================================

/**
 * Howler.js Howl interface (minimal).
 */
interface HowlInstance {
  stereo(pan: number, id?: number): void;
  volume(vol?: number, id?: number): number | void;
  playing(id?: number): boolean;
}

/**
 * Howler.js adapter with software pan ramping.
 * Since Howler.stereo() is instant, we implement our own interpolation.
 */
export class HowlerAdapter extends BaseAudioAdapter {
  /** Howl instances per voice */
  private howls = new Map<string, HowlInstance>();

  /** Sound IDs per voice */
  private soundIds = new Map<string, number>();

  /** Target pan values (for ramping) */
  private targetPan = new Map<string, number>();

  /** Ramping animation frame ID */
  private rampFrameId: number | null = null;

  /** Last ramp update time */
  private lastRampTime = 0;

  /** Pan smoothing factor per frame (lower = smoother) */
  private smoothingFactor = 0.15;

  constructor(rampTimeMs: number = 20) {
    super(rampTimeMs);
    // Calculate smoothing factor from ramp time (assuming ~60fps)
    // Smoother for longer ramp times
    this.smoothingFactor = Math.min(0.5, 16 / Math.max(1, rampTimeMs));
  }

  /**
   * Register a Howl instance for a voice.
   */
  registerHowl(voiceId: string, howl: HowlInstance, soundId?: number): void {
    this.howls.set(voiceId, howl);
    if (soundId !== undefined) {
      this.soundIds.set(voiceId, soundId);
    }
    this.activeVoices.add(voiceId);
  }

  /**
   * Set pan for voice with software ramping.
   * Uses requestAnimationFrame to interpolate towards target.
   */
  setPan(voiceId: string, pan: number): void {
    const howl = this.howls.get(voiceId);
    if (!howl) return;

    const clampedPan = clamp(pan, -1, 1);
    this.targetPan.set(voiceId, clampedPan);

    // Initialize current pan if not set
    if (!this.currentPan.has(voiceId)) {
      this.currentPan.set(voiceId, clampedPan);
      const id = this.soundIds.get(voiceId);
      howl.stereo(clampedPan, id);
      return;
    }

    // Start ramping if not already running
    this.startRamping();
  }

  /**
   * Start the pan ramping animation loop.
   */
  private startRamping(): void {
    if (this.rampFrameId !== null) return;

    this.lastRampTime = performance.now();
    this.rampFrameId = requestAnimationFrame(() => this.rampTick());
  }

  /**
   * Pan ramping tick - interpolates all voices towards their targets.
   */
  private rampTick(): void {
    const now = performance.now();
    const dtMs = now - this.lastRampTime;
    this.lastRampTime = now;

    // Time-based smoothing (adjust factor based on actual frame time)
    const frameFactor = this.smoothingFactor * (dtMs / 16);
    const factor = Math.min(1, frameFactor);

    let needsMoreRamping = false;

    for (const [voiceId, target] of this.targetPan) {
      const current = this.currentPan.get(voiceId) ?? target;
      const diff = target - current;

      // Check if close enough to snap
      if (Math.abs(diff) < 0.001) {
        this.currentPan.set(voiceId, target);
        this.applyPanToHowl(voiceId, target);
        continue;
      }

      // Interpolate
      const newPan = current + diff * factor;
      this.currentPan.set(voiceId, newPan);
      this.applyPanToHowl(voiceId, newPan);
      needsMoreRamping = true;
    }

    // Continue or stop ramping
    if (needsMoreRamping) {
      this.rampFrameId = requestAnimationFrame(() => this.rampTick());
    } else {
      this.rampFrameId = null;
    }
  }

  /**
   * Apply pan value directly to Howl instance.
   */
  private applyPanToHowl(voiceId: string, pan: number): void {
    const howl = this.howls.get(voiceId);
    if (!howl) return;

    const id = this.soundIds.get(voiceId);
    howl.stereo(pan, id);
  }

  /**
   * Set width (not directly supported by Howler).
   */
  setWidth(_voiceId: string, _width: number): void {
    // Howler doesn't support width directly
    // Could implement via Web Audio nodes if using Howler's web audio mode
  }

  /**
   * Set LPF (not directly supported by Howler).
   */
  setLPF(_voiceId: string, _hz: number): void {
    // Would need to access underlying Web Audio nodes
  }

  /**
   * Set channel gains (not directly supported by Howler).
   */
  setChannelGains(_voiceId: string, _gainL: number, _gainR: number): void {
    // Would need to access underlying Web Audio nodes
  }

  /**
   * Set gain.
   */
  setGain(voiceId: string, db: number): void {
    const howl = this.howls.get(voiceId);
    if (!howl) return;

    const id = this.soundIds.get(voiceId);
    const linear = dbToLinear(clamp(db, -60, 12));

    howl.volume(linear, id);
  }

  /**
   * Check if voice is playing.
   */
  override isActive(voiceId: string): boolean {
    const howl = this.howls.get(voiceId);
    if (!howl) return false;

    const id = this.soundIds.get(voiceId);
    return howl.playing(id);
  }

  /**
   * Unregister voice.
   */
  override unregisterVoice(voiceId: string): void {
    this.howls.delete(voiceId);
    this.soundIds.delete(voiceId);
    this.targetPan.delete(voiceId);
    super.unregisterVoice(voiceId);
  }

  /**
   * Clear all.
   */
  override clear(): void {
    // Stop ramping animation
    if (this.rampFrameId !== null) {
      cancelAnimationFrame(this.rampFrameId);
      this.rampFrameId = null;
    }
    this.howls.clear();
    this.soundIds.clear();
    this.targetPan.clear();
    super.clear();
  }

  /**
   * Stop ramping and clean up.
   * Call this when disposing the adapter.
   */
  dispose(): void {
    this.clear();
  }
}

// ============================================================================
// NULL ADAPTER (FOR TESTING)
// ============================================================================

/**
 * Null adapter that logs but doesn't play audio.
 * Useful for testing and debugging.
 */
export class NullAudioAdapter extends BaseAudioAdapter {
  /** Log level: 0=none, 1=summary, 2=verbose */
  private logLevel: number;

  /** Last values per voice (for inspection) */
  public lastValues = new Map<string, SpatialMixParams>();

  constructor(logLevel: number = 0) {
    super(0);
    this.logLevel = logLevel;
  }

  setPan(voiceId: string, pan: number): void {
    this.updateValue(voiceId, 'pan', pan);
    if (this.logLevel >= 2) {
      console.log(`[NullAudio] ${voiceId} pan: ${pan.toFixed(3)}`);
    }
  }

  setWidth(voiceId: string, width: number): void {
    this.updateValue(voiceId, 'width', width);
    if (this.logLevel >= 2) {
      console.log(`[NullAudio] ${voiceId} width: ${width.toFixed(3)}`);
    }
  }

  setLPF(voiceId: string, hz: number): void {
    this.updateValue(voiceId, 'lpfHz', hz);
    if (this.logLevel >= 2) {
      console.log(`[NullAudio] ${voiceId} LPF: ${hz.toFixed(0)} Hz`);
    }
  }

  setGain(voiceId: string, db: number): void {
    this.updateValue(voiceId, 'gainDb', db);
    if (this.logLevel >= 2) {
      console.log(`[NullAudio] ${voiceId} gain: ${db.toFixed(1)} dB`);
    }
  }

  setChannelGains(voiceId: string, gainL: number, gainR: number): void {
    this.updateValue(voiceId, 'gainL', gainL);
    this.updateValue(voiceId, 'gainR', gainR);
    if (this.logLevel >= 2) {
      console.log(`[NullAudio] ${voiceId} L/R: ${gainL.toFixed(3)} / ${gainR.toFixed(3)}`);
    }
  }

  private updateValue<K extends keyof SpatialMixParams>(
    voiceId: string,
    key: K,
    value: SpatialMixParams[K]
  ): void {
    let params = this.lastValues.get(voiceId);
    if (!params) {
      params = { pan: 0, width: 0, gainL: 1, gainR: 1 };
      this.lastValues.set(voiceId, params);
    }
    params[key] = value;
    this.activeVoices.add(voiceId);
  }

  /**
   * Get last values for voice.
   */
  getLastValues(voiceId: string): SpatialMixParams | undefined {
    return this.lastValues.get(voiceId);
  }

  override clear(): void {
    this.lastValues.clear();
    super.clear();
  }
}

// ============================================================================
// FACTORY FUNCTIONS
// ============================================================================

/**
 * Create WebAudio adapter.
 */
export function createWebAudioAdapter(
  ctx: AudioContext,
  options?: { rampTimeMs?: number; useChannelGains?: boolean }
): WebAudioAdapter {
  return new WebAudioAdapter(ctx, options);
}

/**
 * Create Howler adapter.
 */
export function createHowlerAdapter(rampTimeMs?: number): HowlerAdapter {
  return new HowlerAdapter(rampTimeMs);
}

/**
 * Create null adapter for testing.
 */
export function createNullAudioAdapter(logLevel?: number): NullAudioAdapter {
  return new NullAudioAdapter(logLevel);
}
