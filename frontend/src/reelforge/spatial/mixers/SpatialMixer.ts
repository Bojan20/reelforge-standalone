/**
 * ReelForge Spatial System - Spatial Mixer
 * Maps normalized positions to audio parameters with bus policies.
 *
 * @module reelforge/spatial/mixers
 */

import type {
  SpatialTarget,
  SmoothedSpatial,
  SpatialMixParams,
  SpatialBus,
  BusPolicy,
  IntentRule,
} from '../types';
import { DEFAULT_BUS_POLICIES } from '../types';
import {
  clamp01,
  processPan,
  equalPowerGains,
  lerp,
  dbToLinear,
} from '../utils/math';

/**
 * Mixer configuration.
 */
export interface SpatialMixerConfig {
  /** Bus policies (override defaults) */
  busPolicies?: Partial<Record<SpatialBus, Partial<BusPolicy>>>;

  /** Global pan multiplier (for testing/debugging) */
  globalPanMul?: number;

  /** Global width multiplier */
  globalWidthMul?: number;

  /** Enable stereo width processing */
  enableWidth?: boolean;

  /** Enable LPF processing */
  enableLPF?: boolean;

  /** Enable gain from Y axis */
  enableYGain?: boolean;
}

/**
 * SpatialMixer converts spatial targets to audio parameters.
 * Handles:
 * - Equal-power stereo panning
 * - Stereo width
 * - Y-axis to LPF mapping
 * - Y-axis to gain mapping
 * - Bus-specific policies
 */
export class SpatialMixer {
  /** Bus policies */
  private policies: Record<SpatialBus, BusPolicy>;

  /** Configuration */
  private config: Required<SpatialMixerConfig>;

  constructor(config?: SpatialMixerConfig) {
    // Merge bus policies
    this.policies = { ...DEFAULT_BUS_POLICIES };
    if (config?.busPolicies) {
      for (const [bus, policy] of Object.entries(config.busPolicies)) {
        this.policies[bus as SpatialBus] = {
          ...this.policies[bus as SpatialBus],
          ...policy,
        };
      }
    }

    // Merge config
    this.config = {
      busPolicies: config?.busPolicies ?? {},
      globalPanMul: config?.globalPanMul ?? 1.0,
      globalWidthMul: config?.globalWidthMul ?? 1.0,
      enableWidth: config?.enableWidth ?? true,
      enableLPF: config?.enableLPF ?? true,
      enableYGain: config?.enableYGain ?? false,
    };
  }

  /**
   * Mix spatial target to audio parameters.
   */
  mix(
    target: SpatialTarget,
    smoothed: SmoothedSpatial,
    bus: SpatialBus,
    rule: IntentRule
  ): SpatialMixParams {
    const policy = this.policies[bus];

    // Use predicted position for panning (reduces perceived latency)
    const xPos = smoothed.predictedX;
    const yPos = smoothed.predictedY;

    // Calculate pan with deadzone and limits
    const effectiveMaxPan = rule.maxPan * policy.maxPanMul * this.config.globalPanMul;
    const pan = processPan(xPos, rule.deadzone, effectiveMaxPan);

    // Calculate width
    const effectiveWidth = this.config.enableWidth
      ? clamp01(target.width * policy.widthMul * this.config.globalWidthMul)
      : 0;

    // Calculate equal-power gains
    const { gainL, gainR } = this.calculateStereoGains(pan, effectiveWidth);

    // Optional LPF from Y position
    let lpfHz: number | undefined;
    if (this.config.enableLPF && rule.yToLPF) {
      // Top of screen (y=0) = bright, bottom (y=1) = dark
      lpfHz = lerp(rule.yToLPF.maxHz, rule.yToLPF.minHz, clamp01(yPos));
    } else if (this.config.enableLPF && policy.yLpfRange) {
      lpfHz = lerp(policy.yLpfRange.maxHz, policy.yLpfRange.minHz, clamp01(yPos));
    }

    // Optional gain from Y position
    let gainDb: number | undefined;
    if (this.config.enableYGain && rule.yToGainDb) {
      // Map Y to gain range
      gainDb = lerp(rule.yToGainDb.maxDb, rule.yToGainDb.minDb, clamp01(yPos));
    }

    return {
      pan,
      width: effectiveWidth,
      lpfHz,
      gainDb,
      gainL,
      gainR,
    };
  }

  /**
   * Calculate stereo gains with width.
   *
   * Pan: -1 (left) to +1 (right)
   * Width: 0 (mono) to 1 (full stereo)
   *
   * The algorithm:
   * 1. Calculate equal-power pan gains
   * 2. Blend towards center based on width (lower width = more mono)
   */
  private calculateStereoGains(
    pan: number,
    width: number
  ): { gainL: number; gainR: number } {
    // Base equal-power panning
    const base = equalPowerGains(pan);

    if (width >= 1) {
      // Full width - use base gains directly
      return base;
    }

    if (width <= 0) {
      // Mono - equal gain both channels
      const mono = Math.SQRT1_2; // -3dB per channel
      return { gainL: mono, gainR: mono };
    }

    // Blend between mono and full stereo
    const mono = Math.SQRT1_2;
    return {
      gainL: lerp(mono, base.gainL, width),
      gainR: lerp(mono, base.gainR, width),
    };
  }

  /**
   * Get policy for bus.
   */
  getPolicy(bus: SpatialBus): BusPolicy {
    return this.policies[bus];
  }

  /**
   * Update policy for bus.
   */
  setPolicy(bus: SpatialBus, policy: Partial<BusPolicy>): void {
    this.policies[bus] = { ...this.policies[bus], ...policy };
  }

  /**
   * Get smoothing tau adjusted by bus policy.
   */
  getAdjustedSmoothingTau(baseTauMs: number, bus: SpatialBus): number {
    const policy = this.policies[bus];
    return baseTauMs * policy.tauMul;
  }

  /**
   * Check if bus has room for more tracked events.
   */
  canAcceptEvent(bus: SpatialBus, currentCount: number): boolean {
    const policy = this.policies[bus];
    return currentCount < policy.maxConcurrent;
  }

  /**
   * Get max concurrent events for bus.
   */
  getMaxConcurrent(bus: SpatialBus): number {
    return this.policies[bus].maxConcurrent;
  }

  /**
   * Quick pan calculation (without full mix).
   */
  quickPan(xNorm: number, bus: SpatialBus, maxPan: number = 1): number {
    const policy = this.policies[bus];
    const effectiveMaxPan = maxPan * policy.maxPanMul * this.config.globalPanMul;
    return processPan(xNorm, 0.03, effectiveMaxPan);
  }

  /**
   * Quick stereo gains (without full mix).
   */
  quickGains(
    xNorm: number,
    width: number,
    bus: SpatialBus
  ): { gainL: number; gainR: number } {
    const pan = this.quickPan(xNorm, bus);
    const policy = this.policies[bus];
    const effectiveWidth = clamp01(width * policy.widthMul);
    return this.calculateStereoGains(pan, effectiveWidth);
  }

  /**
   * Convert mix params to simple L/R multipliers.
   * Useful for simple audio backends.
   */
  toSimpleStereo(params: SpatialMixParams): { left: number; right: number } {
    let left = params.gainL;
    let right = params.gainR;

    // Apply gain if present
    if (params.gainDb !== undefined) {
      const linear = dbToLinear(params.gainDb);
      left *= linear;
      right *= linear;
    }

    return { left, right };
  }

  /**
   * Update global configuration.
   */
  setConfig(config: Partial<SpatialMixerConfig>): void {
    Object.assign(this.config, config);
  }

  /**
   * Get current configuration.
   */
  getConfig(): Required<SpatialMixerConfig> {
    return { ...this.config };
  }
}

/**
 * Create spatial mixer with optional config.
 */
export function createSpatialMixer(config?: SpatialMixerConfig): SpatialMixer {
  return new SpatialMixer(config);
}
