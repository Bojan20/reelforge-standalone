/**
 * ReelForge Voice Concurrency Manager
 *
 * Wwise/Unreal-inspired voice limiting and management.
 * Prevents audio overload by limiting simultaneous instances.
 *
 * Features:
 * - Max instances per sound
 * - Kill policies (oldest, quietest, newest)
 * - Priority system
 * - Volume scaling when crowded
 * - Global voice limit
 *
 * Use cases:
 * - Coin cascade: max 8 simultaneous coins, kill oldest
 * - Win sounds: max 1, prevent overlap
 * - UI clicks: max 3, newest priority
 */

import type { BusId } from './types';

export type VoiceKillPolicy =
  | 'kill-oldest'      // Stop the oldest playing instance
  | 'kill-newest'      // Don't start new (reject)
  | 'kill-quietest'    // Stop the quietest instance
  | 'kill-lowest-priority'  // Stop lowest priority
  | 'allow-all';       // No limit (warning: can cause overload)

export interface VoiceConcurrencyRule {
  /** Sound ID or pattern (supports * wildcard) */
  soundPattern: string;
  /** Max simultaneous instances */
  maxInstances: number;
  /** What to do when limit reached */
  killPolicy: VoiceKillPolicy;
  /** Priority (higher = more important, won't be killed) */
  priority?: number;
  /** Reduce volume when crowded (0-1, lower = more reduction) */
  crowdedVolumeScale?: number;
  /** Threshold for volume scaling (e.g., 0.5 = start scaling at 50% capacity) */
  crowdedThreshold?: number;
}

export interface ActiveVoice {
  id: string;
  soundId: string;
  bus: BusId;
  priority: number;
  volume: number;
  startTime: number;
  source?: AudioBufferSourceNode;
  gainNode?: GainNode;
}

interface VoiceGroup {
  pattern: string;
  rule: VoiceConcurrencyRule;
  voices: Map<string, ActiveVoice>;
}

// Default concurrency rules for slots
export const DEFAULT_CONCURRENCY_RULES: VoiceConcurrencyRule[] = [
  {
    soundPattern: 'coin_*',
    maxInstances: 8,
    killPolicy: 'kill-oldest',
    priority: 1,
    crowdedVolumeScale: 0.7,
    crowdedThreshold: 0.5,
  },
  {
    soundPattern: 'win_big*',
    maxInstances: 1,
    killPolicy: 'kill-oldest',
    priority: 10,
  },
  {
    soundPattern: 'win_*',
    maxInstances: 3,
    killPolicy: 'kill-oldest',
    priority: 5,
    crowdedVolumeScale: 0.8,
  },
  {
    soundPattern: 'reel_*',
    maxInstances: 5,
    killPolicy: 'kill-oldest',
    priority: 2,
  },
  {
    soundPattern: 'btn_*',
    maxInstances: 2,
    killPolicy: 'kill-newest',
    priority: 1,
  },
  {
    soundPattern: 'music_*',
    maxInstances: 2,
    killPolicy: 'kill-oldest',
    priority: 3,
  },
  {
    soundPattern: '*',  // Fallback for any sound
    maxInstances: 32,
    killPolicy: 'kill-oldest',
    priority: 0,
  },
];

// Global limits
const DEFAULT_GLOBAL_VOICE_LIMIT = 64;

export class VoiceConcurrencyManager {
  private groups: Map<string, VoiceGroup> = new Map();
  private rules: VoiceConcurrencyRule[] = [];
  private allVoices: Map<string, ActiveVoice> = new Map();
  private globalLimit: number;
  private voiceIdCounter: number = 0;

  constructor(
    rules?: VoiceConcurrencyRule[],
    globalLimit: number = DEFAULT_GLOBAL_VOICE_LIMIT
  ) {
    this.globalLimit = globalLimit;
    this.rules = rules ?? [...DEFAULT_CONCURRENCY_RULES];

    // Initialize groups for each rule
    this.rules.forEach(rule => {
      this.groups.set(rule.soundPattern, {
        pattern: rule.soundPattern,
        rule,
        voices: new Map(),
      });
    });
  }

  /**
   * Request to play a sound - returns null if rejected
   */
  requestVoice(
    soundId: string,
    bus: BusId,
    baseVolume: number,
    priority?: number
  ): { voiceId: string; volumeMultiplier: number } | null {
    // Check global limit
    if (this.allVoices.size >= this.globalLimit) {
      const killed = this.killGlobalVoice();
      if (!killed) {
        console.warn(`[Concurrency] Global limit reached (${this.globalLimit}), cannot play: ${soundId}`);
        return null;
      }
    }

    // Find matching rule
    const group = this.findMatchingGroup(soundId);
    if (!group) {
      // No rule matches - use fallback
      return this.createVoice(soundId, bus, baseVolume, priority ?? 0, null);
    }

    const { rule, voices } = group;
    const voicePriority = priority ?? rule.priority ?? 0;

    // Check if at limit
    if (voices.size >= rule.maxInstances) {
      // Apply kill policy
      const killed = this.applyKillPolicy(group, voicePriority, baseVolume);
      if (!killed) {
        console.warn(`[Concurrency] Limit reached for ${rule.soundPattern}, policy rejected: ${soundId}`);
        return null;
      }
    }

    // Calculate volume multiplier for crowding
    let volumeMultiplier = 1.0;
    if (rule.crowdedVolumeScale !== undefined && rule.crowdedThreshold !== undefined) {
      const utilization = voices.size / rule.maxInstances;
      if (utilization >= rule.crowdedThreshold) {
        const crowdFactor = (utilization - rule.crowdedThreshold) / (1 - rule.crowdedThreshold);
        volumeMultiplier = 1 - (1 - rule.crowdedVolumeScale) * crowdFactor;
      }
    }

    return this.createVoice(soundId, bus, baseVolume * volumeMultiplier, voicePriority, group);
  }

  /**
   * Create and register a new voice
   */
  private createVoice(
    soundId: string,
    bus: BusId,
    volume: number,
    priority: number,
    group: VoiceGroup | null
  ): { voiceId: string; volumeMultiplier: number } {
    const voiceId = `voice_${++this.voiceIdCounter}_${Date.now()}`;

    const voice: ActiveVoice = {
      id: voiceId,
      soundId,
      bus,
      priority,
      volume,
      startTime: performance.now(),
    };

    this.allVoices.set(voiceId, voice);

    if (group) {
      group.voices.set(voiceId, voice);
    }

    return { voiceId, volumeMultiplier: volume };
  }

  /**
   * Apply kill policy to make room for new voice
   */
  private applyKillPolicy(
    group: VoiceGroup,
    newPriority: number,
    newVolume: number
  ): boolean {
    const { rule, voices } = group;

    if (voices.size === 0) return true;

    switch (rule.killPolicy) {
      case 'kill-oldest': {
        const oldest = this.findOldestVoice(voices);
        if (oldest) {
          this.killVoice(oldest.id);
          return true;
        }
        return false;
      }

      case 'kill-newest': {
        // Reject new sound
        return false;
      }

      case 'kill-quietest': {
        const quietest = this.findQuietestVoice(voices);
        if (quietest && quietest.volume < newVolume) {
          this.killVoice(quietest.id);
          return true;
        }
        return false;
      }

      case 'kill-lowest-priority': {
        const lowest = this.findLowestPriorityVoice(voices);
        if (lowest && lowest.priority < newPriority) {
          this.killVoice(lowest.id);
          return true;
        }
        return false;
      }

      case 'allow-all':
        return true;

      default:
        return false;
    }
  }

  /**
   * Kill a voice to free up global capacity
   */
  private killGlobalVoice(): boolean {
    // Kill oldest low-priority voice globally
    const voices = Array.from(this.allVoices.values());
    if (voices.length === 0) return false;

    // Sort by priority (ascending), then by start time (ascending)
    voices.sort((a, b) => {
      if (a.priority !== b.priority) {
        return a.priority - b.priority;
      }
      return a.startTime - b.startTime;
    });

    // Kill the lowest priority, oldest voice
    const candidate = voices[0];
    this.killVoice(candidate.id);
    return true;
  }

  /**
   * Find oldest voice in a group
   */
  private findOldestVoice(voices: Map<string, ActiveVoice>): ActiveVoice | undefined {
    let oldest: ActiveVoice | undefined = undefined;

    voices.forEach(voice => {
      if (!oldest || voice.startTime < oldest.startTime) {
        oldest = voice;
      }
    });

    return oldest;
  }

  /**
   * Find quietest voice in a group
   */
  private findQuietestVoice(voices: Map<string, ActiveVoice>): ActiveVoice | undefined {
    let quietest: ActiveVoice | undefined = undefined;

    voices.forEach(voice => {
      if (!quietest || voice.volume < quietest.volume) {
        quietest = voice;
      }
    });

    return quietest;
  }

  /**
   * Find lowest priority voice in a group
   */
  private findLowestPriorityVoice(voices: Map<string, ActiveVoice>): ActiveVoice | undefined {
    let lowest: ActiveVoice | undefined = undefined;

    voices.forEach(voice => {
      if (!lowest || voice.priority < lowest.priority) {
        lowest = voice;
      }
    });

    return lowest;
  }

  /**
   * Kill a specific voice
   */
  killVoice(voiceId: string): boolean {
    const voice = this.allVoices.get(voiceId);
    if (!voice) return false;

    // Stop audio
    if (voice.source) {
      try {
        voice.source.stop();
        voice.source.disconnect();
      } catch { /* ignore */ }
    }
    if (voice.gainNode) {
      voice.gainNode.disconnect();
    }

    // Remove from all tracking
    this.allVoices.delete(voiceId);

    // Remove from group
    this.groups.forEach(group => {
      group.voices.delete(voiceId);
    });

    return true;
  }

  /**
   * Register audio nodes for a voice (for cleanup)
   */
  registerVoiceNodes(
    voiceId: string,
    source: AudioBufferSourceNode,
    gainNode: GainNode
  ): void {
    const voice = this.allVoices.get(voiceId);
    if (voice) {
      voice.source = source;
      voice.gainNode = gainNode;
    }
  }

  /**
   * Mark voice as ended naturally
   */
  voiceEnded(voiceId: string): void {
    this.allVoices.delete(voiceId);

    this.groups.forEach(group => {
      group.voices.delete(voiceId);
    });
  }

  /**
   * Find matching group for a sound ID
   */
  private findMatchingGroup(soundId: string): VoiceGroup | null {
    // Check specific patterns first, fallback last
    for (const [pattern, group] of this.groups) {
      if (pattern === '*') continue;  // Skip fallback initially

      if (this.matchPattern(soundId, pattern)) {
        return group;
      }
    }

    // Return fallback if exists
    return this.groups.get('*') ?? null;
  }

  /**
   * Match sound ID against pattern (supports * wildcard)
   */
  private matchPattern(soundId: string, pattern: string): boolean {
    if (pattern === '*') return true;

    // Convert pattern to regex
    const regexPattern = pattern
      .replace(/[.+?^${}()|[\]\\]/g, '\\$&')  // Escape special chars
      .replace(/\*/g, '.*');  // * → .*

    const regex = new RegExp(`^${regexPattern}$`, 'i');
    return regex.test(soundId);
  }

  /**
   * Get current voice count
   */
  getVoiceCount(): number {
    return this.allVoices.size;
  }

  /**
   * Get voice count for a specific pattern
   */
  getPatternVoiceCount(pattern: string): number {
    const group = this.groups.get(pattern);
    return group?.voices.size ?? 0;
  }

  /**
   * Add or update a rule
   */
  addRule(rule: VoiceConcurrencyRule): void {
    // Remove existing rule for same pattern
    this.rules = this.rules.filter(r => r.soundPattern !== rule.soundPattern);
    this.rules.push(rule);

    // Update group
    this.groups.set(rule.soundPattern, {
      pattern: rule.soundPattern,
      rule,
      voices: this.groups.get(rule.soundPattern)?.voices ?? new Map(),
    });
  }

  /**
   * Get all rules
   */
  getRules(): VoiceConcurrencyRule[] {
    return [...this.rules];
  }

  /**
   * Get all active voices (for debugging)
   */
  getActiveVoices(): ActiveVoice[] {
    return Array.from(this.allVoices.values());
  }

  /**
   * Kill all voices
   */
  killAll(): void {
    this.allVoices.forEach((_, voiceId) => {
      this.killVoice(voiceId);
    });
  }

  /**
   * Dispose
   */
  dispose(): void {
    this.killAll();
    this.groups.clear();
    this.rules = [];
  }
}
