/**
 * ReelForge Spatial System - Alpha-Beta Filter (2D)
 * Predictive smoothing with velocity estimation.
 *
 * @module reelforge/spatial/core
 */

import type { SmoothedSpatial } from '../types';
import { clamp01 } from '../utils/math';

/**
 * Alpha-Beta filter configuration.
 */
export interface AlphaBetaConfig {
  /** Position correction factor (0..1, higher = more responsive) */
  alpha: number;

  /** Velocity correction factor (0..1, higher = faster velocity adaptation) */
  beta: number;

  /** Predictive lead time in seconds */
  predictLeadSec: number;

  /** Deadzone for position changes (reduces jitter) */
  deadzone: number;

  /** Velocity damping factor (0..1, lower = more damping) */
  velocityDamping: number;
}

/**
 * Default configurations per bus type.
 */
export const ALPHA_BETA_PRESETS: Record<string, AlphaBetaConfig> = {
  UI: {
    alpha: 0.85,
    beta: 0.008,
    predictLeadSec: 0.020,
    deadzone: 0.002,
    velocityDamping: 0.98,
  },
  REELS: {
    alpha: 0.78,
    beta: 0.004,
    predictLeadSec: 0.012,
    deadzone: 0.003,
    velocityDamping: 0.95,
  },
  FX: {
    alpha: 0.82,
    beta: 0.006,
    predictLeadSec: 0.015,
    deadzone: 0.002,
    velocityDamping: 0.97,
  },
  VO: {
    alpha: 0.70,
    beta: 0.002,
    predictLeadSec: 0.008,
    deadzone: 0.005,
    velocityDamping: 0.92,
  },
  MUSIC: {
    alpha: 0.65,
    beta: 0.001,
    predictLeadSec: 0.005,
    deadzone: 0.008,
    velocityDamping: 0.90,
  },
  AMBIENT: {
    alpha: 0.55,
    beta: 0.0005,
    predictLeadSec: 0.003,
    deadzone: 0.010,
    velocityDamping: 0.88,
  },
  DEFAULT: {
    alpha: 0.80,
    beta: 0.005,
    predictLeadSec: 0.015,
    deadzone: 0.003,
    velocityDamping: 0.96,
  },
};

/**
 * Alpha-Beta filter for 2D position smoothing.
 *
 * The alpha-beta filter is a simplified form of Kalman filter that provides:
 * - Smooth position tracking without lag
 * - Velocity estimation for prediction
 * - Jitter reduction through deadzone
 *
 * Unlike Kalman, it doesn't require noise covariance matrices,
 * making it lightweight and suitable for real-time audio panning.
 */
export class AlphaBeta2D {
  /** Current smoothed X position */
  private x: number = 0.5;

  /** Current smoothed Y position */
  private y: number = 0.5;

  /** Estimated X velocity (norm/sec) */
  private vx: number = 0;

  /** Estimated Y velocity (norm/sec) */
  private vy: number = 0;

  /** Filter configuration */
  private config: AlphaBetaConfig;

  /** Has been initialized with first measurement */
  private initialized: boolean = false;

  /** Last update timestamp */
  private lastUpdateTime: number = 0;

  constructor(config?: Partial<AlphaBetaConfig>) {
    this.config = {
      ...ALPHA_BETA_PRESETS.DEFAULT,
      ...config,
    };
  }

  /**
   * Reset filter to initial state.
   */
  reset(x: number = 0.5, y: number = 0.5): void {
    this.x = clamp01(x);
    this.y = clamp01(y);
    this.vx = 0;
    this.vy = 0;
    this.initialized = true;
    this.lastUpdateTime = performance.now();
  }

  /**
   * Update filter with new measurement.
   *
   * @param measX Measured X position (0..1)
   * @param measY Measured Y position (0..1)
   * @param dtSec Time delta in seconds
   * @returns Smoothed spatial output
   */
  update(measX: number, measY: number, dtSec: number): SmoothedSpatial {
    const now = performance.now();

    // Initialize on first measurement
    if (!this.initialized) {
      this.reset(measX, measY);
      return this.getOutput();
    }

    // Guard against zero/negative dt
    if (dtSec <= 0) {
      return this.getOutput();
    }

    const { alpha, beta, deadzone, velocityDamping } = this.config;

    // === PREDICT PHASE ===
    // Predict next position based on velocity
    let predX = this.x + this.vx * dtSec;
    let predY = this.y + this.vy * dtSec;

    // === UPDATE PHASE ===
    // Calculate residual (error between prediction and measurement)
    let residualX = measX - predX;
    let residualY = measY - predY;

    // Apply deadzone to reduce jitter
    if (Math.abs(residualX) < deadzone) residualX = 0;
    if (Math.abs(residualY) < deadzone) residualY = 0;

    // Correct position
    this.x = clamp01(predX + alpha * residualX);
    this.y = clamp01(predY + alpha * residualY);

    // Correct velocity
    if (dtSec > 0) {
      this.vx = (this.vx + (beta * residualX) / dtSec) * velocityDamping;
      this.vy = (this.vy + (beta * residualY) / dtSec) * velocityDamping;
    }

    // Clamp velocity to reasonable range (prevent runaway)
    const maxVelocity = 5; // 5x screen width per second
    this.vx = Math.max(-maxVelocity, Math.min(maxVelocity, this.vx));
    this.vy = Math.max(-maxVelocity, Math.min(maxVelocity, this.vy));

    this.lastUpdateTime = now;

    return this.getOutput();
  }

  /**
   * Get current output (smoothed + predicted positions).
   */
  getOutput(): SmoothedSpatial {
    const { predictLeadSec } = this.config;

    // Calculate predicted position (with lead time)
    const predictedX = clamp01(this.x + this.vx * predictLeadSec);
    const predictedY = clamp01(this.y + this.vy * predictLeadSec);

    return {
      x: this.x,
      y: this.y,
      predictedX,
      predictedY,
      vx: this.vx,
      vy: this.vy,
    };
  }

  /**
   * Get current position.
   */
  getPosition(): { x: number; y: number } {
    return { x: this.x, y: this.y };
  }

  /**
   * Get current velocity.
   */
  getVelocity(): { vx: number; vy: number } {
    return { vx: this.vx, vy: this.vy };
  }

  /**
   * Get predicted position.
   */
  getPredicted(): { x: number; y: number } {
    const { predictLeadSec } = this.config;
    return {
      x: clamp01(this.x + this.vx * predictLeadSec),
      y: clamp01(this.y + this.vy * predictLeadSec),
    };
  }

  /**
   * Check if filter is initialized.
   */
  isInitialized(): boolean {
    return this.initialized;
  }

  /**
   * Update configuration.
   */
  setConfig(config: Partial<AlphaBetaConfig>): void {
    this.config = { ...this.config, ...config };
  }

  /**
   * Get current configuration.
   */
  getConfig(): AlphaBetaConfig {
    return { ...this.config };
  }

  /**
   * Apply preset configuration.
   */
  applyPreset(presetName: string): void {
    const preset = ALPHA_BETA_PRESETS[presetName] ?? ALPHA_BETA_PRESETS.DEFAULT;
    this.config = { ...preset };
  }

  /**
   * Get time since last update (ms).
   */
  getTimeSinceUpdate(): number {
    return performance.now() - this.lastUpdateTime;
  }

  /**
   * Nudge position towards target (for snap transitions).
   */
  nudge(targetX: number, targetY: number, amount: number): void {
    const t = clamp01(amount);
    this.x = clamp01(this.x + (targetX - this.x) * t);
    this.y = clamp01(this.y + (targetY - this.y) * t);
  }

  /**
   * Snap to position (instant, no smoothing).
   */
  snap(x: number, y: number): void {
    this.x = clamp01(x);
    this.y = clamp01(y);
    this.vx = 0;
    this.vy = 0;
  }

  /**
   * Clone filter state.
   */
  clone(): AlphaBeta2D {
    const clone = new AlphaBeta2D(this.config);
    clone.x = this.x;
    clone.y = this.y;
    clone.vx = this.vx;
    clone.vy = this.vy;
    clone.initialized = this.initialized;
    clone.lastUpdateTime = this.lastUpdateTime;
    return clone;
  }
}

/**
 * Create alpha-beta filter with optional config.
 */
export function createAlphaBeta2D(config?: Partial<AlphaBetaConfig>): AlphaBeta2D {
  return new AlphaBeta2D(config);
}

/**
 * Create alpha-beta filter from preset.
 */
export function createAlphaBeta2DFromPreset(presetName: string): AlphaBeta2D {
  const config = ALPHA_BETA_PRESETS[presetName] ?? ALPHA_BETA_PRESETS.DEFAULT;
  return new AlphaBeta2D(config);
}
