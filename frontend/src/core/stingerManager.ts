/**
 * Stinger Manager
 *
 * Handles musical stingers (short musical phrases) that transition
 * between game states or punctuate events.
 *
 * Features:
 * - Beat-synced triggering (wait for next beat/bar)
 * - Immediate triggering
 * - Crossfade with current music
 * - Queue system for stinger priority
 * - Tail handling (let stinger ring out)
 */

import type { BusId } from './types';

// ============ TYPES ============

export type StingerTriggerMode = 'immediate' | 'next-beat' | 'next-bar' | 'next-phrase';

export type StingerTailMode = 'cut' | 'fade' | 'ring-out';

export interface Stinger {
  /** Unique identifier */
  id: string;
  /** Display name */
  name: string;
  /** Description */
  description?: string;
  /** Sound asset ID */
  assetId: string;
  /** Bus to play on */
  bus?: BusId;
  /** Volume */
  volume?: number;
  /** How to trigger relative to music */
  triggerMode?: StingerTriggerMode;
  /** How to handle the tail */
  tailMode?: StingerTailMode;
  /** Fade out duration for tail (ms) */
  tailFadeMs?: number;
  /** Duration of the stinger (ms) - for scheduling next music */
  durationMs?: number;
  /** Crossfade into music after stinger (ms) */
  exitCrossfadeMs?: number;
  /** Priority (higher = more important) */
  priority?: number;
  /** Can interrupt other stingers */
  canInterrupt?: boolean;
  /** Tags for categorization */
  tags?: string[];
}

export interface StingerPlayOptions {
  /** Override trigger mode */
  triggerMode?: StingerTriggerMode;
  /** Override volume */
  volume?: number;
  /** Music track to resume after stinger */
  resumeMusicId?: string;
  /** Callback when stinger starts */
  onStart?: () => void;
  /** Callback when stinger ends */
  onEnd?: () => void;
}

export interface MusicBeatInfo {
  /** Current BPM */
  bpm: number;
  /** Time signature numerator (e.g., 4 for 4/4) */
  beatsPerBar: number;
  /** Current beat within the bar (0-indexed) */
  currentBeat: number;
  /** Current bar number */
  currentBar: number;
  /** Time of last beat (performance.now()) */
  lastBeatTime: number;
  /** Beats per phrase (typically 4 or 8 bars) */
  beatsPerPhrase?: number;
}

export interface StingerQueueItem {
  stinger: Stinger;
  options?: StingerPlayOptions;
  scheduledTime: number;
  priority: number;
}

// ============ STINGER MANAGER ============

export class StingerManager {
  private stingers: Map<string, Stinger> = new Map();
  private queue: StingerQueueItem[] = [];
  private currentStinger: StingerQueueItem | null = null;
  private beatInfo: MusicBeatInfo | null = null;
  private playCallback: (assetId: string, bus: BusId, volume: number) => string | null;
  private stopCallback: (voiceId: string, fadeMs?: number) => void;
  private musicDuckCallback: (duckLevel: number, fadeMs: number) => void;
  private activeVoiceId: string | null = null;
  private stingerEndTimer: number | null = null;
  private beatCheckInterval: number | null = null;

  constructor(
    playCallback: (assetId: string, bus: BusId, volume: number) => string | null,
    stopCallback: (voiceId: string, fadeMs?: number) => void,
    musicDuckCallback: (duckLevel: number, fadeMs: number) => void,
    stingers?: Stinger[]
  ) {
    this.playCallback = playCallback;
    this.stopCallback = stopCallback;
    this.musicDuckCallback = musicDuckCallback;

    // Register default stingers
    DEFAULT_STINGERS.forEach(s => this.registerStinger(s));

    // Register custom stingers
    if (stingers) {
      stingers.forEach(s => this.registerStinger(s));
    }
  }

  /**
   * Register a stinger
   */
  registerStinger(stinger: Stinger): void {
    this.stingers.set(stinger.id, stinger);
  }

  /**
   * Unregister a stinger
   */
  unregisterStinger(stingerId: string): void {
    this.stingers.delete(stingerId);
  }

  /**
   * Update beat information from music system
   */
  updateBeatInfo(info: MusicBeatInfo): void {
    this.beatInfo = info;
    this.processQueue();
  }

  /**
   * Trigger a stinger
   */
  triggerStinger(stingerId: string, options?: StingerPlayOptions): boolean {
    const stinger = this.stingers.get(stingerId);
    if (!stinger) {
      console.warn(`[STINGER] Stinger not found: ${stingerId}`);
      return false;
    }

    const triggerMode = options?.triggerMode ?? stinger.triggerMode ?? 'immediate';
    const priority = stinger.priority ?? 5;

    // Check if we can interrupt current stinger
    if (this.currentStinger) {
      const currentPriority = this.currentStinger.priority;
      if (priority <= currentPriority && !stinger.canInterrupt) {
        console.warn(`[STINGER] Cannot interrupt current stinger (priority ${currentPriority})`);
        return false;
      }
    }

    if (triggerMode === 'immediate') {
      this.playStingerNow(stinger, options);
    } else {
      this.scheduleStinger(stinger, triggerMode, options);
    }

    return true;
  }

  /**
   * Schedule stinger for beat-synced playback
   */
  private scheduleStinger(stinger: Stinger, mode: StingerTriggerMode, options?: StingerPlayOptions): void {
    const scheduledTime = this.calculateNextTriggerTime(mode);
    const priority = stinger.priority ?? 5;

    const item: StingerQueueItem = {
      stinger,
      options,
      scheduledTime,
      priority,
    };

    // Insert into queue by priority (higher priority first)
    const insertIndex = this.queue.findIndex(q => q.priority < priority);
    if (insertIndex === -1) {
      this.queue.push(item);
    } else {
      this.queue.splice(insertIndex, 0, item);
    }

    // Start beat checking if not already running
    if (!this.beatCheckInterval) {
      this.startBeatChecking();
    }
  }

  /**
   * Calculate next trigger time based on mode
   */
  private calculateNextTriggerTime(mode: StingerTriggerMode): number {
    if (!this.beatInfo) {
      // No beat info, trigger immediately
      return performance.now();
    }

    const { bpm, beatsPerBar, currentBeat, lastBeatTime, beatsPerPhrase = 16 } = this.beatInfo;
    const beatDuration = 60000 / bpm;

    switch (mode) {
      case 'next-beat': {
        // Next beat
        return lastBeatTime + beatDuration;
      }

      case 'next-bar': {
        // Next bar start
        const beatsUntilBar = beatsPerBar - currentBeat;
        return lastBeatTime + (beatsUntilBar * beatDuration);
      }

      case 'next-phrase': {
        // Next phrase start (e.g., every 4 bars)
        const beatsUntilPhrase = beatsPerPhrase - (currentBeat % beatsPerPhrase);
        return lastBeatTime + (beatsUntilPhrase * beatDuration);
      }

      default:
        return performance.now();
    }
  }

  /**
   * Start checking for scheduled stingers
   */
  private startBeatChecking(): void {
    this.beatCheckInterval = window.setInterval(() => {
      this.processQueue();
    }, 10); // Check every 10ms for precision
  }

  /**
   * Stop beat checking
   */
  private stopBeatChecking(): void {
    if (this.beatCheckInterval) {
      window.clearInterval(this.beatCheckInterval);
      this.beatCheckInterval = null;
    }
  }

  /**
   * Process the queue
   */
  private processQueue(): void {
    if (this.queue.length === 0) {
      this.stopBeatChecking();
      return;
    }

    const now = performance.now();
    const readyItems = this.queue.filter(item => item.scheduledTime <= now);

    if (readyItems.length > 0) {
      // Play highest priority ready item
      const item = readyItems[0];
      this.queue = this.queue.filter(q => q !== item);
      this.playStingerNow(item.stinger, item.options);
    }
  }

  /**
   * Play stinger immediately
   */
  private playStingerNow(stinger: Stinger, options?: StingerPlayOptions): void {
    // Stop current stinger if any
    if (this.currentStinger) {
      this.stopCurrentStinger();
    }

    const volume = options?.volume ?? stinger.volume ?? 1.0;
    const bus = stinger.bus ?? 'music';

    // Duck music
    this.musicDuckCallback(0.2, 100); // Quick duck to 20%

    // Play stinger
    this.activeVoiceId = this.playCallback(stinger.assetId, bus, volume);

    this.currentStinger = {
      stinger,
      options,
      scheduledTime: performance.now(),
      priority: stinger.priority ?? 5,
    };

    // Callback
    options?.onStart?.();

    // Schedule end
    const duration = stinger.durationMs ?? 2000; // Default 2 seconds
    this.stingerEndTimer = window.setTimeout(() => {
      this.handleStingerEnd(stinger, options);
    }, duration);
  }

  /**
   * Handle stinger end
   */
  private handleStingerEnd(stinger: Stinger, options?: StingerPlayOptions): void {
    const tailMode = stinger.tailMode ?? 'fade';

    switch (tailMode) {
      case 'cut':
        if (this.activeVoiceId) {
          this.stopCallback(this.activeVoiceId);
        }
        break;

      case 'fade':
        if (this.activeVoiceId) {
          this.stopCallback(this.activeVoiceId, stinger.tailFadeMs ?? 300);
        }
        break;

      case 'ring-out':
        // Let it play naturally
        break;
    }

    // Restore music
    const crossfade = stinger.exitCrossfadeMs ?? 500;
    this.musicDuckCallback(1.0, crossfade);

    // Callback
    options?.onEnd?.();

    // Cleanup
    this.currentStinger = null;
    this.activeVoiceId = null;
    this.stingerEndTimer = null;
  }

  /**
   * Stop current stinger
   */
  private stopCurrentStinger(): void {
    if (this.stingerEndTimer) {
      window.clearTimeout(this.stingerEndTimer);
      this.stingerEndTimer = null;
    }

    if (this.activeVoiceId) {
      this.stopCallback(this.activeVoiceId, 50); // Quick fade
      this.activeVoiceId = null;
    }

    this.currentStinger = null;
  }

  /**
   * Stop all stingers and clear queue
   */
  stopAll(): void {
    this.stopCurrentStinger();
    this.queue = [];
    this.stopBeatChecking();
    this.musicDuckCallback(1.0, 200); // Restore music
  }

  /**
   * Check if a stinger is playing
   */
  isPlaying(): boolean {
    return this.currentStinger !== null;
  }

  /**
   * Get current stinger
   */
  getCurrentStinger(): Stinger | null {
    return this.currentStinger?.stinger ?? null;
  }

  /**
   * Get queue length
   */
  getQueueLength(): number {
    return this.queue.length;
  }

  /**
   * Get all registered stingers
   */
  getStingers(): Stinger[] {
    return Array.from(this.stingers.values());
  }

  /**
   * Get stingers by tag
   */
  getStingersByTag(tag: string): Stinger[] {
    return Array.from(this.stingers.values()).filter(s => s.tags?.includes(tag));
  }

  /**
   * Dispose manager
   */
  dispose(): void {
    this.stopAll();
    this.stingers.clear();
  }
}

// ============ DEFAULT STINGERS ============

export const DEFAULT_STINGERS: Stinger[] = [
  {
    id: 'win_stinger_small',
    name: 'Small Win Stinger',
    description: 'Quick musical hit for small wins',
    assetId: 'stinger_win_small',
    bus: 'music',
    volume: 0.9,
    triggerMode: 'immediate',
    tailMode: 'fade',
    tailFadeMs: 200,
    durationMs: 800,
    exitCrossfadeMs: 300,
    priority: 5,
    tags: ['win', 'small'],
  },
  {
    id: 'win_stinger_medium',
    name: 'Medium Win Stinger',
    description: 'Fanfare for medium wins',
    assetId: 'stinger_win_medium',
    bus: 'music',
    volume: 1.0,
    triggerMode: 'next-beat',
    tailMode: 'fade',
    tailFadeMs: 400,
    durationMs: 1500,
    exitCrossfadeMs: 500,
    priority: 7,
    tags: ['win', 'medium'],
  },
  {
    id: 'win_stinger_big',
    name: 'Big Win Stinger',
    description: 'Epic fanfare for big wins',
    assetId: 'stinger_win_big',
    bus: 'music',
    volume: 1.0,
    triggerMode: 'next-bar',
    tailMode: 'ring-out',
    durationMs: 3000,
    exitCrossfadeMs: 1000,
    priority: 10,
    canInterrupt: true,
    tags: ['win', 'big'],
  },
  {
    id: 'feature_trigger',
    name: 'Feature Trigger Stinger',
    description: 'Dramatic hit for feature trigger',
    assetId: 'stinger_feature_trigger',
    bus: 'music',
    volume: 1.0,
    triggerMode: 'immediate',
    tailMode: 'ring-out',
    durationMs: 2000,
    exitCrossfadeMs: 500,
    priority: 12,
    canInterrupt: true,
    tags: ['feature', 'trigger'],
  },
  {
    id: 'freespins_retrigger',
    name: 'Free Spins Retrigger',
    description: 'Stinger for extra free spins',
    assetId: 'stinger_fs_retrigger',
    bus: 'music',
    volume: 1.0,
    triggerMode: 'next-beat',
    tailMode: 'fade',
    tailFadeMs: 300,
    durationMs: 1200,
    exitCrossfadeMs: 400,
    priority: 8,
    tags: ['freespins', 'retrigger'],
  },
  {
    id: 'multiplier_increase',
    name: 'Multiplier Increase',
    description: 'Quick hit for multiplier bumps',
    assetId: 'stinger_multiplier_up',
    bus: 'sfx',
    volume: 0.9,
    triggerMode: 'immediate',
    tailMode: 'cut',
    durationMs: 500,
    exitCrossfadeMs: 100,
    priority: 4,
    tags: ['multiplier'],
  },
  {
    id: 'anticipation_resolve',
    name: 'Anticipation Resolve',
    description: 'Resolution after near-miss',
    assetId: 'stinger_anticipation_resolve',
    bus: 'music',
    volume: 0.8,
    triggerMode: 'immediate',
    tailMode: 'fade',
    tailFadeMs: 500,
    durationMs: 1000,
    exitCrossfadeMs: 300,
    priority: 6,
    tags: ['anticipation'],
  },
  {
    id: 'transition_base_to_feature',
    name: 'Base to Feature Transition',
    description: 'Musical bridge from base game to feature',
    assetId: 'stinger_transition_feature',
    bus: 'music',
    volume: 1.0,
    triggerMode: 'next-bar',
    tailMode: 'ring-out',
    durationMs: 2500,
    exitCrossfadeMs: 800,
    priority: 11,
    canInterrupt: true,
    tags: ['transition', 'feature'],
  },
];
