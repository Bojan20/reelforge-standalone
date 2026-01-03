/**
 * ReelForge Ducking Manager
 *
 * Automatic volume ducking (sidechain-style) for slot games.
 * When high-priority audio plays, automatically reduces volume of lower-priority buses.
 *
 * Use cases:
 * - Win SFX plays → music ducks
 * - Voice announcement → everything else ducks
 * - Big win celebration → ambience ducks completely
 *
 * Features:
 * - Priority-based ducking
 * - Configurable attack/release
 * - Multiple simultaneous duckers
 * - Smooth Web Audio transitions
 */

import type { BusId } from './types';

export interface DuckingRule {
  id: string;
  /** Source bus that triggers ducking when active */
  sourceBus: BusId;
  /** Target bus(es) to duck */
  targetBuses: BusId[];
  /** How much to reduce volume (0 = full duck, 1 = no duck) */
  duckAmount: number;
  /** Attack time in ms (how fast to duck) */
  attackMs: number;
  /** Release time in ms (how fast to recover) */
  releaseMs: number;
  /** Hold time before release starts (ms) */
  holdMs?: number;
  /** Priority (higher = ducks lower priority rules) */
  priority: number;
  /** Whether this rule is enabled */
  enabled: boolean;
}

// Default ducking rules for slots
export const DEFAULT_DUCKING_RULES: DuckingRule[] = [
  {
    id: 'sfx_ducks_music',
    sourceBus: 'sfx',
    targetBuses: ['music'],
    duckAmount: 0.4,  // Duck to 40%
    attackMs: 50,
    releaseMs: 300,
    holdMs: 100,
    priority: 1,
    enabled: true,
  },
  {
    id: 'voice_ducks_all',
    sourceBus: 'voice',
    targetBuses: ['music', 'sfx', 'ambience'],
    duckAmount: 0.3,  // Duck to 30%
    attackMs: 30,
    releaseMs: 500,
    holdMs: 200,
    priority: 2,
    enabled: true,
  },
  {
    id: 'sfx_ducks_ambience',
    sourceBus: 'sfx',
    targetBuses: ['ambience'],
    duckAmount: 0.2,  // Duck to 20%
    attackMs: 20,
    releaseMs: 400,
    priority: 1,
    enabled: true,
  },
];

interface ActiveDuck {
  ruleId: string;
  targetBus: BusId;
  startTime: number;
  currentLevel: number;  // Current duck level (1 = no duck, 0 = full duck)
  targetLevel: number;
  phase: 'attack' | 'hold' | 'release' | 'idle';
}

interface BusActivity {
  busId: BusId;
  isActive: boolean;
  lastActiveTime: number;
  activeCount: number;  // Number of sounds currently playing
}

type GetBusGainCallback = (bus: BusId) => GainNode | null;

export class DuckingManager {
  private audioContext: AudioContext;
  private rules: Map<string, DuckingRule> = new Map();
  private activeDucks: Map<string, ActiveDuck> = new Map();  // key: ruleId:targetBus
  private busActivity: Map<BusId, BusActivity> = new Map();
  private getBusGain: GetBusGainCallback;
  private originalVolumes: Map<BusId, number> = new Map();
  private animationFrame: number | null = null;
  private isRunning: boolean = false;

  constructor(
    audioContext: AudioContext,
    getBusGain: GetBusGainCallback,
    initialRules?: DuckingRule[]
  ) {
    this.audioContext = audioContext;
    this.getBusGain = getBusGain;

    // Initialize bus activity tracking
    const busIds: BusId[] = ['music', 'sfx', 'ambience', 'voice', 'master'];
    busIds.forEach(busId => {
      this.busActivity.set(busId, {
        busId,
        isActive: false,
        lastActiveTime: 0,
        activeCount: 0,
      });
      this.originalVolumes.set(busId, 1.0);
    });

    // Load default rules
    DEFAULT_DUCKING_RULES.forEach(rule => this.rules.set(rule.id, rule));

    // Add custom rules
    if (initialRules) {
      initialRules.forEach(rule => this.rules.set(rule.id, rule));
    }
  }

  /**
   * Start the ducking system
   */
  start(): void {
    if (this.isRunning) return;
    this.isRunning = true;
    this.runDuckingLoop();
  }

  /**
   * Stop the ducking system
   */
  stop(): void {
    this.isRunning = false;
    if (this.animationFrame) {
      cancelAnimationFrame(this.animationFrame);
      this.animationFrame = null;
    }
    // Restore all volumes
    this.restoreAllVolumes();
  }

  /**
   * Register a ducking rule
   */
  registerRule(rule: DuckingRule): void {
    this.rules.set(rule.id, rule);
  }

  /**
   * Remove a ducking rule
   */
  removeRule(ruleId: string): boolean {
    return this.rules.delete(ruleId);
  }

  /**
   * Enable/disable a rule
   */
  setRuleEnabled(ruleId: string, enabled: boolean): void {
    const rule = this.rules.get(ruleId);
    if (rule) {
      rule.enabled = enabled;
    }
  }

  /**
   * Notify that a sound started playing on a bus
   */
  notifySoundStart(busId: BusId): void {
    const activity = this.busActivity.get(busId);
    if (activity) {
      activity.activeCount++;
      activity.isActive = true;
      activity.lastActiveTime = performance.now();
    }
  }

  /**
   * Notify that a sound stopped playing on a bus
   */
  notifySoundStop(busId: BusId): void {
    const activity = this.busActivity.get(busId);
    if (activity) {
      activity.activeCount = Math.max(0, activity.activeCount - 1);
      if (activity.activeCount === 0) {
        activity.isActive = false;
      }
    }
  }

  /**
   * Store original volume for a bus
   */
  setOriginalVolume(busId: BusId, volume: number): void {
    this.originalVolumes.set(busId, volume);
  }

  /**
   * Main ducking loop
   */
  private runDuckingLoop(): void {
    const processFrame = () => {
      if (!this.isRunning) return;

      const now = performance.now();

      // Process each enabled rule
      this.rules.forEach(rule => {
        if (!rule.enabled) return;

        const sourceActivity = this.busActivity.get(rule.sourceBus);
        const sourceIsActive = sourceActivity?.isActive ?? false;

        // Process each target bus
        rule.targetBuses.forEach(targetBus => {
          const duckKey = `${rule.id}:${targetBus}`;
          let duck = this.activeDucks.get(duckKey);

          if (sourceIsActive) {
            // Source is active - should be ducking
            if (!duck) {
              // Start new duck
              duck = {
                ruleId: rule.id,
                targetBus,
                startTime: now,
                currentLevel: 1.0,
                targetLevel: rule.duckAmount,
                phase: 'attack',
              };
              this.activeDucks.set(duckKey, duck);
            } else if (duck.phase === 'release' || duck.phase === 'idle') {
              // Re-trigger attack
              duck.phase = 'attack';
              duck.startTime = now;
              duck.targetLevel = rule.duckAmount;
            }
          } else {
            // Source inactive
            if (duck && duck.phase !== 'release' && duck.phase !== 'idle') {
              // Start release
              duck.phase = 'hold';
              duck.startTime = now;
            }
          }

          // Process duck phases
          if (duck) {
            this.processDuck(duck, rule, now);
          }
        });
      });

      this.animationFrame = requestAnimationFrame(processFrame);
    };

    this.animationFrame = requestAnimationFrame(processFrame);
  }

  /**
   * Process duck state machine
   */
  private processDuck(duck: ActiveDuck, rule: DuckingRule, now: number): void {
    const elapsed = now - duck.startTime;

    switch (duck.phase) {
      case 'attack': {
        const progress = Math.min(1, elapsed / rule.attackMs);
        duck.currentLevel = 1 - (1 - duck.targetLevel) * progress;

        if (progress >= 1) {
          duck.currentLevel = duck.targetLevel;
        }
        break;
      }

      case 'hold': {
        const holdMs = rule.holdMs ?? 0;
        if (elapsed >= holdMs) {
          duck.phase = 'release';
          duck.startTime = now;
        }
        break;
      }

      case 'release': {
        const progress = Math.min(1, elapsed / rule.releaseMs);
        duck.currentLevel = duck.targetLevel + (1 - duck.targetLevel) * progress;

        if (progress >= 1) {
          duck.currentLevel = 1.0;
          duck.phase = 'idle';
        }
        break;
      }

      case 'idle':
        // Clean up if fully released
        if (duck.currentLevel >= 0.999) {
          this.activeDucks.delete(`${rule.id}:${duck.targetBus}`);
        }
        break;
    }

    // Apply duck level to bus
    this.applyDuckLevel(duck.targetBus);
  }

  /**
   * Apply combined duck level to a bus
   */
  private applyDuckLevel(busId: BusId): void {
    // Find minimum duck level from all active ducks targeting this bus
    let minLevel = 1.0;

    this.activeDucks.forEach(duck => {
      if (duck.targetBus === busId && duck.currentLevel < minLevel) {
        minLevel = duck.currentLevel;
      }
    });

    // Apply to gain node
    const gainNode = this.getBusGain(busId);
    if (gainNode) {
      const originalVolume = this.originalVolumes.get(busId) ?? 1.0;
      const duckedVolume = originalVolume * minLevel;

      // Use setValueAtTime for smooth updates
      const now = this.audioContext.currentTime;
      gainNode.gain.setValueAtTime(duckedVolume, now);
    }
  }

  /**
   * Restore all buses to original volumes
   */
  private restoreAllVolumes(): void {
    this.originalVolumes.forEach((volume, busId) => {
      const gainNode = this.getBusGain(busId);
      if (gainNode) {
        gainNode.gain.value = volume;
      }
    });
    this.activeDucks.clear();
  }

  /**
   * Get current duck level for a bus
   */
  getDuckLevel(busId: BusId): number {
    let minLevel = 1.0;

    this.activeDucks.forEach(duck => {
      if (duck.targetBus === busId && duck.currentLevel < minLevel) {
        minLevel = duck.currentLevel;
      }
    });

    return minLevel;
  }

  /**
   * Get all rules
   */
  getRules(): DuckingRule[] {
    return Array.from(this.rules.values());
  }

  /**
   * Dispose and cleanup
   */
  dispose(): void {
    this.stop();
    this.rules.clear();
    this.activeDucks.clear();
    this.busActivity.clear();
  }
}
