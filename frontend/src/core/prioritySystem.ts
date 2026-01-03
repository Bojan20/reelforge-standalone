/**
 * Priority System
 *
 * Advanced priority-based sound management for slot games.
 * Ensures critical sounds always play while managing resource limits.
 *
 * Features:
 * - Priority levels with preemption
 * - Voice stealing based on priority
 * - Priority boosting (temporary priority increase)
 * - Priority decay over time
 * - Bus-level priority management
 */

import type { BusId } from './types';

// ============ TYPES ============

export type PriorityLevel = 'critical' | 'high' | 'medium' | 'low' | 'ambient';

export interface PriorityConfig {
  /** Priority level */
  level: PriorityLevel;
  /** Numeric priority (0-100, higher = more important) */
  value: number;
  /** Can preempt lower priority sounds */
  canPreempt: boolean;
  /** Can be preempted by higher priority */
  canBePreempted: boolean;
  /** Fade out time when preempted (ms) */
  preemptFadeMs?: number;
  /** Priority boost amount (temporary increase) */
  boostAmount?: number;
  /** Boost duration (ms) */
  boostDurationMs?: number;
  /** Priority decay rate per second */
  decayRate?: number;
}

export interface PrioritizedSound {
  /** Unique ID */
  id: string;
  /** Sound asset ID */
  assetId: string;
  /** Bus */
  bus: BusId;
  /** Priority config */
  priority: PriorityConfig;
  /** Current effective priority (with boosts/decay) */
  effectivePriority: number;
  /** Start time */
  startTime: number;
  /** Is currently boosted */
  isBoosted: boolean;
  /** Boost end time */
  boostEndTime?: number;
  /** Voice ID if playing */
  voiceId?: string;
  /** Volume */
  volume: number;
}

export interface BusPriorityLimit {
  /** Bus ID */
  bus: BusId;
  /** Max concurrent sounds */
  maxSounds: number;
  /** Reserved slots for critical priority */
  criticalReserved?: number;
  /** Reserved slots for high priority */
  highReserved?: number;
}

// ============ PRIORITY PRESETS ============

export const PRIORITY_LEVELS: Record<PriorityLevel, number> = {
  critical: 100,
  high: 75,
  medium: 50,
  low: 25,
  ambient: 10,
};

export const DEFAULT_PRIORITY_CONFIGS: Record<string, PriorityConfig> = {
  // Critical - always plays, never preempted
  win_announcement: {
    level: 'critical',
    value: 100,
    canPreempt: true,
    canBePreempted: false,
    preemptFadeMs: 50,
  },
  feature_trigger: {
    level: 'critical',
    value: 95,
    canPreempt: true,
    canBePreempted: false,
    preemptFadeMs: 100,
  },

  // High - important gameplay sounds
  reel_stop: {
    level: 'high',
    value: 80,
    canPreempt: true,
    canBePreempted: true,
    preemptFadeMs: 50,
  },
  button_click: {
    level: 'high',
    value: 75,
    canPreempt: false,
    canBePreempted: true,
    preemptFadeMs: 0,
  },
  spin_start: {
    level: 'high',
    value: 70,
    canPreempt: true,
    canBePreempted: true,
    preemptFadeMs: 100,
  },

  // Medium - standard sounds
  coin_land: {
    level: 'medium',
    value: 50,
    canPreempt: false,
    canBePreempted: true,
    preemptFadeMs: 100,
    decayRate: 5, // Priority decays over time
  },
  symbol_highlight: {
    level: 'medium',
    value: 45,
    canPreempt: false,
    canBePreempted: true,
    preemptFadeMs: 50,
  },

  // Low - non-essential sounds
  ui_hover: {
    level: 'low',
    value: 25,
    canPreempt: false,
    canBePreempted: true,
    preemptFadeMs: 0,
  },
  ambient_detail: {
    level: 'low',
    value: 20,
    canPreempt: false,
    canBePreempted: true,
    preemptFadeMs: 200,
    decayRate: 10,
  },

  // Ambient - background sounds
  background_loop: {
    level: 'ambient',
    value: 10,
    canPreempt: false,
    canBePreempted: true,
    preemptFadeMs: 500,
  },
};

export const DEFAULT_BUS_LIMITS: BusPriorityLimit[] = [
  { bus: 'sfx', maxSounds: 16, criticalReserved: 2, highReserved: 4 },
  { bus: 'music', maxSounds: 4, criticalReserved: 1 },
  { bus: 'voice', maxSounds: 2, criticalReserved: 1 },
  { bus: 'ambience', maxSounds: 8, highReserved: 2 },
];

// ============ PRIORITY MANAGER ============

export class PriorityManager {
  private configs: Map<string, PriorityConfig> = new Map();
  private activeSounds: Map<string, PrioritizedSound> = new Map();
  private busLimits: Map<BusId, BusPriorityLimit> = new Map();
  private updateInterval: number | null = null;
  private preemptCallback: (soundId: string, fadeMs: number) => void;
  private playCallback: (assetId: string, bus: BusId, volume: number) => string | null;

  constructor(
    preemptCallback: (soundId: string, fadeMs: number) => void,
    playCallback: (assetId: string, bus: BusId, volume: number) => string | null,
    configs?: Record<string, PriorityConfig>,
    busLimits?: BusPriorityLimit[]
  ) {
    this.preemptCallback = preemptCallback;
    this.playCallback = playCallback;

    // Register default configs
    Object.entries(DEFAULT_PRIORITY_CONFIGS).forEach(([key, config]) => {
      this.configs.set(key, config);
    });

    // Register custom configs
    if (configs) {
      Object.entries(configs).forEach(([key, config]) => {
        this.configs.set(key, config);
      });
    }

    // Register bus limits
    DEFAULT_BUS_LIMITS.forEach(limit => {
      this.busLimits.set(limit.bus, limit);
    });

    if (busLimits) {
      busLimits.forEach(limit => {
        this.busLimits.set(limit.bus, limit);
      });
    }

    // Start update loop for priority decay
    this.startUpdateLoop();
  }

  /**
   * Request to play a sound with priority
   */
  requestPlay(
    assetId: string,
    bus: BusId,
    volume: number,
    priorityKey?: string
  ): { allowed: boolean; soundId: string | null; preempted: string[] } {
    const config = this.configs.get(priorityKey ?? assetId) ?? this.getDefaultConfig();
    const soundId = `${assetId}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

    const sound: PrioritizedSound = {
      id: soundId,
      assetId,
      bus,
      priority: config,
      effectivePriority: config.value,
      startTime: performance.now(),
      isBoosted: false,
      volume,
    };

    const result = this.canPlay(sound);

    if (result.allowed) {
      // Preempt sounds if needed
      result.preempted.forEach(preemptedId => {
        const preempted = this.activeSounds.get(preemptedId);
        if (preempted) {
          this.preemptCallback(preemptedId, preempted.priority.preemptFadeMs ?? 100);
          this.activeSounds.delete(preemptedId);
        }
      });

      // Play the sound
      const voiceId = this.playCallback(assetId, bus, volume);
      sound.voiceId = voiceId ?? undefined;
      this.activeSounds.set(soundId, sound);
    }

    return {
      allowed: result.allowed,
      soundId: result.allowed ? soundId : null,
      preempted: result.preempted,
    };
  }

  /**
   * Check if a sound can play
   */
  private canPlay(sound: PrioritizedSound): { allowed: boolean; preempted: string[] } {
    const busLimit = this.busLimits.get(sound.bus);
    const busSounds = this.getSoundsOnBus(sound.bus);
    const preempted: string[] = [];

    // No limit configured - allow
    if (!busLimit) {
      return { allowed: true, preempted: [] };
    }

    // Check reserved slots
    const criticalReserved = busLimit.criticalReserved ?? 0;
    const highReserved = busLimit.highReserved ?? 0;

    const criticalCount = busSounds.filter(s => s.priority.level === 'critical').length;
    const highCount = busSounds.filter(s => s.priority.level === 'high').length;

    // Critical sounds always have their reserved slots
    if (sound.priority.level === 'critical') {
      if (criticalCount < criticalReserved) {
        return { allowed: true, preempted: [] };
      }
    }

    // High sounds get their reserved slots after critical
    if (sound.priority.level === 'high') {
      if (highCount < highReserved && criticalCount <= criticalReserved) {
        return { allowed: true, preempted: [] };
      }
    }

    // Check if under limit
    if (busSounds.length < busLimit.maxSounds) {
      return { allowed: true, preempted: [] };
    }

    // At limit - try to preempt
    if (!sound.priority.canPreempt) {
      return { allowed: false, preempted: [] };
    }

    // Find preemptable sounds (lower priority, can be preempted)
    const preemptable = busSounds
      .filter(s =>
        s.priority.canBePreempted &&
        s.effectivePriority < sound.effectivePriority
      )
      .sort((a, b) => a.effectivePriority - b.effectivePriority);

    if (preemptable.length === 0) {
      return { allowed: false, preempted: [] };
    }

    // Preempt the lowest priority sound
    preempted.push(preemptable[0].id);
    return { allowed: true, preempted };
  }

  /**
   * Get sounds on a specific bus
   */
  private getSoundsOnBus(bus: BusId): PrioritizedSound[] {
    return Array.from(this.activeSounds.values()).filter(s => s.bus === bus);
  }

  /**
   * Get default priority config
   */
  private getDefaultConfig(): PriorityConfig {
    return {
      level: 'medium',
      value: 50,
      canPreempt: false,
      canBePreempted: true,
      preemptFadeMs: 100,
    };
  }

  /**
   * Boost a sound's priority temporarily
   */
  boostPriority(soundId: string, amount?: number, durationMs?: number): boolean {
    const sound = this.activeSounds.get(soundId);
    if (!sound) return false;

    const boostAmount = amount ?? sound.priority.boostAmount ?? 20;
    const duration = durationMs ?? sound.priority.boostDurationMs ?? 1000;

    sound.isBoosted = true;
    sound.effectivePriority = Math.min(100, sound.priority.value + boostAmount);
    sound.boostEndTime = performance.now() + duration;

    return true;
  }

  /**
   * Mark a sound as ended
   */
  soundEnded(soundId: string): void {
    this.activeSounds.delete(soundId);
  }

  /**
   * Start update loop for priority decay and boost expiration
   */
  private startUpdateLoop(): void {
    const update = () => {
      const now = performance.now();

      this.activeSounds.forEach((sound, _id) => {
        // Handle boost expiration
        if (sound.isBoosted && sound.boostEndTime && now >= sound.boostEndTime) {
          sound.isBoosted = false;
          sound.effectivePriority = sound.priority.value;
          sound.boostEndTime = undefined;
        }

        // Handle priority decay
        if (sound.priority.decayRate && !sound.isBoosted) {
          const elapsed = (now - sound.startTime) / 1000;
          const decay = elapsed * sound.priority.decayRate;
          sound.effectivePriority = Math.max(0, sound.priority.value - decay);
        }
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
   * Register a priority config
   */
  registerConfig(key: string, config: PriorityConfig): void {
    this.configs.set(key, config);
  }

  /**
   * Set bus limit
   */
  setBusLimit(limit: BusPriorityLimit): void {
    this.busLimits.set(limit.bus, limit);
  }

  /**
   * Get active sound count
   */
  getActiveSoundCount(bus?: BusId): number {
    if (bus) {
      return this.getSoundsOnBus(bus).length;
    }
    return this.activeSounds.size;
  }

  /**
   * Get all active sounds
   */
  getActiveSounds(): PrioritizedSound[] {
    return Array.from(this.activeSounds.values());
  }

  /**
   * Get priority configs
   */
  getConfigs(): Record<string, PriorityConfig> {
    const result: Record<string, PriorityConfig> = {};
    this.configs.forEach((config, key) => {
      result[key] = config;
    });
    return result;
  }

  /**
   * Clear all active sounds
   */
  clear(): void {
    this.activeSounds.clear();
  }

  /**
   * Dispose manager
   */
  dispose(): void {
    this.stopUpdateLoop();
    this.activeSounds.clear();
    this.configs.clear();
    this.busLimits.clear();
  }
}
