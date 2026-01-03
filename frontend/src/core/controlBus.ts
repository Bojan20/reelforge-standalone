/**
 * ReelForge Control Bus (RTPC System)
 *
 * Unreal Engine-inspired parameter control system.
 * One input value controls multiple audio parameters simultaneously.
 *
 * Use cases:
 * - "excitement" → music intensity + SFX volume + reverb level
 * - "tension" → music pitch + ambience volume + anticipation layer
 * - "winMomentum" → celebration intensity + coin sound pitch
 */

import type { ControlBus, ControlBusTarget, ControlBusCurve, BusId } from './types';

// Default control buses for slot games
export const DEFAULT_CONTROL_BUSES: ControlBus[] = [
  {
    id: 'excitement',
    name: 'Excitement',
    description: 'Overall excitement level - affects music intensity and SFX boost',
    range: [0, 1],
    defaultValue: 0,
    targets: [
      { path: 'bus.music.volume', scale: -0.3, offset: 1.0 }, // 1.0 → 0.7 as excitement rises
      { path: 'bus.sfx.volume', scale: 0.3, offset: 1.0 },    // 1.0 → 1.3 as excitement rises
      { path: 'bus.ambience.volume', scale: -0.4, offset: 0.5 }, // 0.5 → 0.1 as excitement rises
    ],
    smoothingMs: 200,
  },
  {
    id: 'tension',
    name: 'Tension',
    description: 'Building anticipation - grows during dry spells',
    range: [0, 1],
    defaultValue: 0,
    targets: [
      { path: 'bus.music.volume', scale: -0.2, offset: 1.0, curve: 'exponential' },
      { path: 'bus.ambience.volume', scale: 0.3, offset: 0.3, curve: 'linear' },
    ],
    smoothingMs: 500,
  },
  {
    id: 'sessionIntensity',
    name: 'Session Intensity',
    description: 'Derived from win patterns - higher during hot streaks',
    range: [0, 1],
    defaultValue: 0.5,
    targets: [
      { path: 'bus.music.volume', scale: 0.2, offset: 0.7 },  // 0.7 → 0.9
      { path: 'bus.sfx.volume', scale: 0.1, offset: 1.0 },    // 1.0 → 1.1
    ],
    smoothingMs: 1000,
  },
];

interface TargetState {
  currentValue: number;
  targetValue: number;
  lastUpdateTime: number;
}

type ApplyValueCallback = (path: string, value: number) => void;

export class ControlBusManager {
  private buses: Map<string, ControlBus> = new Map();
  private busValues: Map<string, number> = new Map();
  private targetStates: Map<string, TargetState> = new Map();
  private applyValue: ApplyValueCallback;
  private animationFrame: number | null = null;
  private isAnimating: boolean = false;

  constructor(
    applyValue: ApplyValueCallback,
    initialBuses?: ControlBus[]
  ) {
    this.applyValue = applyValue;

    // Load default buses
    DEFAULT_CONTROL_BUSES.forEach(bus => {
      this.buses.set(bus.id, bus);
      this.busValues.set(bus.id, bus.defaultValue ?? 0);
    });

    // Add custom buses
    if (initialBuses) {
      initialBuses.forEach(bus => {
        this.buses.set(bus.id, bus);
        this.busValues.set(bus.id, bus.defaultValue ?? 0);
      });
    }
  }

  /**
   * Register a new control bus
   */
  registerBus(bus: ControlBus): void {
    this.buses.set(bus.id, bus);
    this.busValues.set(bus.id, bus.defaultValue ?? 0);
  }

  /**
   * Remove a control bus
   */
  removeBus(id: string): boolean {
    this.busValues.delete(id);
    return this.buses.delete(id);
  }

  /**
   * Get all control buses
   */
  getBuses(): ControlBus[] {
    return Array.from(this.buses.values());
  }

  /**
   * Get current value of a control bus
   */
  getValue(busId: string): number | undefined {
    return this.busValues.get(busId);
  }

  /**
   * Set control bus value - triggers all targets
   */
  setValue(busId: string, value: number): void {
    const bus = this.buses.get(busId);
    if (!bus) {
      console.warn(`[ControlBus] Bus not found: ${busId}`);
      return;
    }

    // Clamp to range
    const [min, max] = bus.range ?? [0, 1];
    const clampedValue = Math.max(min, Math.min(max, value));

    // Normalize to 0-1 for processing
    const normalizedValue = (clampedValue - min) / (max - min);

    this.busValues.set(busId, clampedValue);

    // Apply to all targets
    bus.targets.forEach(target => {
      const outputValue = this.calculateTargetValue(normalizedValue, target);

      if (bus.smoothingMs && bus.smoothingMs > 0) {
        // Smooth transition
        this.setTargetWithSmoothing(target.path, outputValue, bus.smoothingMs);
      } else {
        // Immediate application
        this.applyValue(target.path, outputValue);
      }
    });
  }

  /**
   * Set value with smoothing (for gradual changes)
   */
  private setTargetWithSmoothing(path: string, targetValue: number, _smoothingMs: number): void {
    const existing = this.targetStates.get(path);

    this.targetStates.set(path, {
      currentValue: existing?.currentValue ?? targetValue,
      targetValue,
      lastUpdateTime: performance.now(),
    });

    // Start animation if not running
    if (!this.isAnimating) {
      this.startSmoothingLoop();
    }
  }

  /**
   * Animation loop for smooth value transitions
   */
  private startSmoothingLoop(): void {
    this.isAnimating = true;

    const animate = () => {
      let hasActiveTransitions = false;

      this.targetStates.forEach((state, path) => {
        const delta = state.targetValue - state.currentValue;

        if (Math.abs(delta) < 0.001) {
          // Close enough - snap to target
          state.currentValue = state.targetValue;
          this.applyValue(path, state.targetValue);
        } else {
          // Interpolate (exponential smoothing)
          const smoothingFactor = 0.1; // Adjust for speed
          state.currentValue += delta * smoothingFactor;
          this.applyValue(path, state.currentValue);
          hasActiveTransitions = true;
        }
      });

      if (hasActiveTransitions) {
        this.animationFrame = requestAnimationFrame(animate);
      } else {
        this.isAnimating = false;
        this.animationFrame = null;
      }
    };

    this.animationFrame = requestAnimationFrame(animate);
  }

  /**
   * Calculate output value for a target based on input and curve
   */
  private calculateTargetValue(normalizedInput: number, target: ControlBusTarget): number {
    let value = normalizedInput;

    // Apply inversion
    if (target.invert) {
      value = 1 - value;
    }

    // Apply curve
    value = this.applyCurve(value, target.curve ?? 'linear');

    // Apply scale and offset
    const scale = target.scale ?? 1;
    const offset = target.offset ?? 0;
    value = value * scale + offset;

    return value;
  }

  /**
   * Apply curve function to value
   */
  private applyCurve(value: number, curve: ControlBusCurve): number {
    switch (curve) {
      case 'linear':
        return value;
      case 'exponential':
        return value * value;
      case 'logarithmic':
        return Math.sqrt(value);
      case 'scurve':
        // S-curve (smooth step)
        return value * value * (3 - 2 * value);
      default:
        return value;
    }
  }

  /**
   * Reset all control buses to default values
   */
  resetToDefaults(): void {
    this.buses.forEach((bus, id) => {
      this.setValue(id, bus.defaultValue ?? 0);
    });
  }

  /**
   * Get snapshot of all current values
   */
  captureState(): Record<string, number> {
    const state: Record<string, number> = {};
    this.busValues.forEach((value, id) => {
      state[id] = value;
    });
    return state;
  }

  /**
   * Restore from captured state
   */
  restoreState(state: Record<string, number>): void {
    Object.entries(state).forEach(([id, value]) => {
      if (this.buses.has(id)) {
        this.setValue(id, value);
      }
    });
  }

  /**
   * Dispose and cleanup
   */
  dispose(): void {
    if (this.animationFrame) {
      cancelAnimationFrame(this.animationFrame);
    }
    this.buses.clear();
    this.busValues.clear();
    this.targetStates.clear();
    this.isAnimating = false;
  }
}

/**
 * Helper to parse control bus path
 * "bus.music.volume" → { type: 'bus', busId: 'music', param: 'volume' }
 * "master.volume" → { type: 'master', param: 'volume' }
 */
export function parseControlPath(path: string): {
  type: 'bus' | 'master' | 'unknown';
  busId?: BusId;
  param: string;
} {
  const parts = path.split('.');

  if (parts[0] === 'master') {
    return { type: 'master', param: parts[1] ?? 'volume' };
  }

  if (parts[0] === 'bus' && parts.length >= 3) {
    return {
      type: 'bus',
      busId: parts[1] as BusId,
      param: parts[2],
    };
  }

  return { type: 'unknown', param: path };
}
