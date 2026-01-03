/**
 * RTPC - Real-Time Parameter Control
 *
 * Wwise-style parameter system for driving audio based on game state.
 * Maps game values to audio parameters with curves and smoothing.
 *
 * Use cases:
 * - Balance multiplier → music intensity
 * - Win tier → celebration volume
 * - Spin speed → reel loop pitch
 * - Feature progress → anticipation filter
 */

// BusId would be imported if filter callback needed bus context
// import type { BusId } from './types';

// ============ TYPES ============

export type RTPCTarget =
  | 'volume'
  | 'pitch'
  | 'lowpass'
  | 'highpass'
  | 'playbackRate'
  | 'pan'
  | 'reverb'
  | 'delay';

export type RTPCCurveType = 'linear' | 'exponential' | 'logarithmic' | 's-curve' | 'step';

export interface RTPCCurvePoint {
  /** Input value (game parameter) */
  x: number;
  /** Output value (audio parameter) */
  y: number;
  /** Curve type to next point */
  curve?: RTPCCurveType;
}

export interface RTPCBinding {
  /** Unique binding ID */
  id: string;
  /** Target parameter */
  target: RTPCTarget;
  /** Sound/bus to affect */
  targetId: string;
  /** Is bus or sound */
  targetType: 'sound' | 'bus';
  /** Curve points (sorted by x) */
  curve: RTPCCurvePoint[];
  /** Smoothing time in ms */
  smoothingMs?: number;
  /** Default output when RTPC is not set */
  defaultValue?: number;
}

export interface RTPCDefinition {
  /** RTPC name (e.g., 'balance_multiplier', 'win_tier') */
  name: string;
  /** Display name */
  displayName: string;
  /** Description */
  description?: string;
  /** Minimum input value */
  minValue: number;
  /** Maximum input value */
  maxValue: number;
  /** Default value */
  defaultValue: number;
  /** Bindings to audio parameters */
  bindings: RTPCBinding[];
}

export interface ActiveRTPC {
  name: string;
  currentValue: number;
  targetValue: number;
  lastUpdateTime: number;
}

// ============ RTPC MANAGER ============

export class RTPCManager {
  private definitions: Map<string, RTPCDefinition> = new Map();
  private activeRTPCs: Map<string, ActiveRTPC> = new Map();
  private updateInterval: number | null = null;

  // Callbacks for applying values
  private setVolumeCallback: (targetId: string, targetType: 'sound' | 'bus', value: number) => void;
  private setPitchCallback: (targetId: string, value: number) => void;
  private setFilterCallback: (targetId: string, type: 'lowpass' | 'highpass', value: number) => void;

  constructor(
    setVolumeCallback: (targetId: string, targetType: 'sound' | 'bus', value: number) => void,
    setPitchCallback: (targetId: string, value: number) => void,
    setFilterCallback: (targetId: string, type: 'lowpass' | 'highpass', value: number) => void,
    definitions?: RTPCDefinition[]
  ) {
    this.setVolumeCallback = setVolumeCallback;
    this.setPitchCallback = setPitchCallback;
    this.setFilterCallback = setFilterCallback;

    // Register default RTPCs
    DEFAULT_RTPC_DEFINITIONS.forEach(def => this.registerRTPC(def));

    // Register custom RTPCs
    if (definitions) {
      definitions.forEach(def => this.registerRTPC(def));
    }

    this.startUpdateLoop();
  }

  /**
   * Register an RTPC definition
   */
  registerRTPC(definition: RTPCDefinition): void {
    this.definitions.set(definition.name, definition);

    // Initialize active state
    this.activeRTPCs.set(definition.name, {
      name: definition.name,
      currentValue: definition.defaultValue,
      targetValue: definition.defaultValue,
      lastUpdateTime: performance.now(),
    });
  }

  /**
   * Set RTPC value
   */
  setRTPCValue(name: string, value: number): void {
    const definition = this.definitions.get(name);
    if (!definition) return;

    // Clamp to valid range
    const clampedValue = Math.max(definition.minValue, Math.min(definition.maxValue, value));

    const active = this.activeRTPCs.get(name);
    if (active) {
      active.targetValue = clampedValue;
      active.lastUpdateTime = performance.now();
    }
  }

  /**
   * Get current RTPC value
   */
  getRTPCValue(name: string): number | null {
    const active = this.activeRTPCs.get(name);
    return active ? active.currentValue : null;
  }

  /**
   * Evaluate curve at input value
   */
  private evaluateCurve(curve: RTPCCurvePoint[], inputValue: number): number {
    if (curve.length === 0) return 0;
    if (curve.length === 1) return curve[0].y;

    // Find surrounding points
    let leftPoint = curve[0];
    let rightPoint = curve[curve.length - 1];

    for (let i = 0; i < curve.length - 1; i++) {
      if (inputValue >= curve[i].x && inputValue <= curve[i + 1].x) {
        leftPoint = curve[i];
        rightPoint = curve[i + 1];
        break;
      }
    }

    // Clamp to curve bounds
    if (inputValue <= leftPoint.x) return leftPoint.y;
    if (inputValue >= rightPoint.x) return rightPoint.y;

    // Interpolate
    const t = (inputValue - leftPoint.x) / (rightPoint.x - leftPoint.x);
    const curveType = leftPoint.curve ?? 'linear';

    return this.interpolate(t, leftPoint.y, rightPoint.y, curveType);
  }

  /**
   * Interpolate between values based on curve type
   */
  private interpolate(t: number, start: number, end: number, curveType: RTPCCurveType): number {
    switch (curveType) {
      case 'linear':
        return start + t * (end - start);

      case 'exponential':
        return start + (Math.pow(t, 2)) * (end - start);

      case 'logarithmic':
        return start + (Math.sqrt(t)) * (end - start);

      case 's-curve':
        // Smoothstep
        const smoothT = t * t * (3 - 2 * t);
        return start + smoothT * (end - start);

      case 'step':
        return t < 0.5 ? start : end;

      default:
        return start + t * (end - start);
    }
  }

  /**
   * Apply RTPC bindings
   */
  private applyBindings(definition: RTPCDefinition, value: number): void {
    for (const binding of definition.bindings) {
      const outputValue = this.evaluateCurve(binding.curve, value);

      switch (binding.target) {
        case 'volume':
          this.setVolumeCallback(binding.targetId, binding.targetType, outputValue);
          break;

        case 'pitch':
        case 'playbackRate':
          this.setPitchCallback(binding.targetId, outputValue);
          break;

        case 'lowpass':
          this.setFilterCallback(binding.targetId, 'lowpass', outputValue);
          break;

        case 'highpass':
          this.setFilterCallback(binding.targetId, 'highpass', outputValue);
          break;

        // pan, reverb, delay would need additional callbacks
      }
    }
  }

  /**
   * Update loop for smoothing
   */
  private startUpdateLoop(): void {
    const update = () => {
      const now = performance.now();

      this.activeRTPCs.forEach((active, name) => {
        const definition = this.definitions.get(name);
        if (!definition) return;

        // Find max smoothing time from bindings
        const maxSmoothing = Math.max(
          ...definition.bindings.map(b => b.smoothingMs ?? 0),
          0
        );

        if (maxSmoothing > 0 && active.currentValue !== active.targetValue) {
          // Smooth towards target
          const elapsed = now - active.lastUpdateTime;
          const progress = Math.min(1, elapsed / maxSmoothing);

          active.currentValue = active.currentValue + (active.targetValue - active.currentValue) * progress;

          // Snap if close enough
          if (Math.abs(active.currentValue - active.targetValue) < 0.001) {
            active.currentValue = active.targetValue;
          }
        } else {
          active.currentValue = active.targetValue;
        }

        // Apply bindings with current value
        this.applyBindings(definition, active.currentValue);
      });

      this.updateInterval = requestAnimationFrame(update);
    };

    this.updateInterval = requestAnimationFrame(update);
  }

  /**
   * Stop update loop
   */
  private stopUpdateLoop(): void {
    if (this.updateInterval !== null) {
      cancelAnimationFrame(this.updateInterval);
      this.updateInterval = null;
    }
  }

  /**
   * Reset RTPC to default
   */
  resetRTPC(name: string): void {
    const definition = this.definitions.get(name);
    if (!definition) return;

    this.setRTPCValue(name, definition.defaultValue);
  }

  /**
   * Reset all RTPCs
   */
  resetAll(): void {
    this.definitions.forEach((_, name) => {
      this.resetRTPC(name);
    });
  }

  /**
   * Add binding to RTPC
   */
  addBinding(rtpcName: string, binding: RTPCBinding): boolean {
    const definition = this.definitions.get(rtpcName);
    if (!definition) return false;

    definition.bindings.push(binding);
    return true;
  }

  /**
   * Remove binding from RTPC
   */
  removeBinding(rtpcName: string, bindingId: string): boolean {
    const definition = this.definitions.get(rtpcName);
    if (!definition) return false;

    const index = definition.bindings.findIndex(b => b.id === bindingId);
    if (index === -1) return false;

    definition.bindings.splice(index, 1);
    return true;
  }

  /**
   * Get all RTPC definitions
   */
  getDefinitions(): RTPCDefinition[] {
    return Array.from(this.definitions.values());
  }

  /**
   * Get all active RTPC values
   */
  getActiveValues(): Record<string, number> {
    const result: Record<string, number> = {};
    this.activeRTPCs.forEach((active, name) => {
      result[name] = active.currentValue;
    });
    return result;
  }

  /**
   * Dispose manager
   */
  dispose(): void {
    this.stopUpdateLoop();
    this.definitions.clear();
    this.activeRTPCs.clear();
  }
}

// ============ DEFAULT RTPC DEFINITIONS ============

export const DEFAULT_RTPC_DEFINITIONS: RTPCDefinition[] = [
  {
    name: 'balance_multiplier',
    displayName: 'Balance Multiplier',
    description: 'Maps balance multiplier to music intensity',
    minValue: 1,
    maxValue: 100,
    defaultValue: 1,
    bindings: [
      {
        id: 'balance_to_music_volume',
        target: 'volume',
        targetId: 'music',
        targetType: 'bus',
        smoothingMs: 500,
        curve: [
          { x: 1, y: 0.6, curve: 'logarithmic' },
          { x: 10, y: 0.8, curve: 'linear' },
          { x: 50, y: 0.9, curve: 's-curve' },
          { x: 100, y: 1.0 },
        ],
      },
      {
        id: 'balance_to_intensity_layer',
        target: 'volume',
        targetId: 'intensity_high',
        targetType: 'sound',
        smoothingMs: 1000,
        curve: [
          { x: 1, y: 0, curve: 'exponential' },
          { x: 25, y: 0.3, curve: 'linear' },
          { x: 75, y: 0.7, curve: 's-curve' },
          { x: 100, y: 1.0 },
        ],
      },
    ],
  },
  {
    name: 'win_tier',
    displayName: 'Win Tier',
    description: 'Win size tier (0=no win, 5=jackpot)',
    minValue: 0,
    maxValue: 5,
    defaultValue: 0,
    bindings: [
      {
        id: 'win_to_sfx_volume',
        target: 'volume',
        targetId: 'sfx',
        targetType: 'bus',
        smoothingMs: 100,
        curve: [
          { x: 0, y: 0.7, curve: 'linear' },
          { x: 2, y: 0.85, curve: 'linear' },
          { x: 5, y: 1.0 },
        ],
      },
      {
        id: 'win_to_music_duck',
        target: 'volume',
        targetId: 'music',
        targetType: 'bus',
        smoothingMs: 200,
        curve: [
          { x: 0, y: 1.0, curve: 'linear' },
          { x: 3, y: 0.6, curve: 's-curve' },
          { x: 5, y: 0.4 },
        ],
      },
    ],
  },
  {
    name: 'spin_speed',
    displayName: 'Spin Speed',
    description: 'Reel spin speed (0=stopped, 1=normal, 2=turbo)',
    minValue: 0,
    maxValue: 2,
    defaultValue: 0,
    bindings: [
      {
        id: 'speed_to_reel_pitch',
        target: 'pitch',
        targetId: 'reel_loop',
        targetType: 'sound',
        smoothingMs: 50,
        curve: [
          { x: 0, y: 0, curve: 'linear' },
          { x: 1, y: 1, curve: 'exponential' },
          { x: 2, y: 1.5 },
        ],
      },
      {
        id: 'speed_to_reel_volume',
        target: 'volume',
        targetId: 'reel_loop',
        targetType: 'sound',
        smoothingMs: 100,
        curve: [
          { x: 0, y: 0, curve: 's-curve' },
          { x: 0.5, y: 0.8, curve: 'linear' },
          { x: 2, y: 1.0 },
        ],
      },
    ],
  },
  {
    name: 'anticipation_level',
    displayName: 'Anticipation Level',
    description: 'Near-win anticipation intensity',
    minValue: 0,
    maxValue: 1,
    defaultValue: 0,
    bindings: [
      {
        id: 'anticipation_to_filter',
        target: 'highpass',
        targetId: 'music',
        targetType: 'bus',
        smoothingMs: 300,
        curve: [
          { x: 0, y: 20, curve: 'exponential' },
          { x: 0.5, y: 200, curve: 'exponential' },
          { x: 1, y: 800 },
        ],
      },
      {
        id: 'anticipation_to_sfx',
        target: 'volume',
        targetId: 'anticipation_layer',
        targetType: 'sound',
        smoothingMs: 200,
        curve: [
          { x: 0, y: 0, curve: 's-curve' },
          { x: 0.3, y: 0.5, curve: 'linear' },
          { x: 1, y: 1.0 },
        ],
      },
    ],
  },
  {
    name: 'feature_progress',
    displayName: 'Feature Progress',
    description: 'Progress through bonus feature (0-1)',
    minValue: 0,
    maxValue: 1,
    defaultValue: 0,
    bindings: [
      {
        id: 'progress_to_intensity',
        target: 'volume',
        targetId: 'feature_intensity',
        targetType: 'sound',
        smoothingMs: 500,
        curve: [
          { x: 0, y: 0.5, curve: 'linear' },
          { x: 0.5, y: 0.75, curve: 's-curve' },
          { x: 1, y: 1.0 },
        ],
      },
    ],
  },
];
