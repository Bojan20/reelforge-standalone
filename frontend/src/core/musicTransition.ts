/**
 * Music Transition System
 *
 * Professional music transitions between tracks with:
 * - Beat-synced transitions (wait for next beat/bar)
 * - Multiple transition types (crossfade, cut, stinger)
 * - Entry/exit cue point support
 * - Tempo matching (time-stretch)
 * - Pre-entry (start next track before exit)
 */

import type { BusId } from './types';

// ============ TYPES ============

export type TransitionType =
  | 'immediate'      // Instant cut
  | 'crossfade'      // Volume crossfade
  | 'fade-out-in'    // Fade out, then fade in
  | 'stinger'        // Play stinger during transition
  | 'musical';       // Wait for beat/bar boundary

export type TransitionSync =
  | 'immediate'      // Don't wait
  | 'next-beat'      // Wait for next beat
  | 'next-bar'       // Wait for next bar
  | 'next-marker'    // Wait for specific marker
  | 'exit-cue';      // Wait for exit cue marker

export interface TransitionRule {
  /** Rule ID */
  id: string;
  /** Source track pattern (regex or exact) */
  sourcePattern?: string;
  /** Destination track pattern */
  destPattern?: string;
  /** Transition type */
  type: TransitionType;
  /** Sync point */
  sync: TransitionSync;
  /** Fade duration in ms */
  fadeDurationMs?: number;
  /** Stinger asset ID (for stinger transition) */
  stingerId?: string;
  /** Delay before starting destination (ms) */
  destDelayMs?: number;
  /** Pre-entry: start dest before source ends (ms) */
  preEntryMs?: number;
  /** Use entry cue on destination */
  useEntryCue?: boolean;
  /** Use exit cue on source */
  useExitCue?: boolean;
}

export interface MusicTrackInfo {
  /** Track ID */
  id: string;
  /** Asset ID */
  assetId: string;
  /** BPM */
  bpm?: number;
  /** Time signature */
  timeSignature?: [number, number];
  /** Current playback time */
  currentTime: number;
  /** Voice ID if playing */
  voiceId?: string;
  /** Entry cue time */
  entryCue?: number;
  /** Exit cue time */
  exitCue?: number;
  /** Loop start */
  loopStart?: number;
  /** Loop end */
  loopEnd?: number;
}

export interface PendingTransition {
  sourceTrack: MusicTrackInfo;
  destTrack: MusicTrackInfo;
  rule: TransitionRule;
  scheduledTime: number;
  state: 'waiting' | 'transitioning' | 'complete';
}

// ============ MUSIC TRANSITION MANAGER ============

export class MusicTransitionManager {
  private rules: Map<string, TransitionRule> = new Map();
  private currentTrack: MusicTrackInfo | null = null;
  private pendingTransition: PendingTransition | null = null;
  private updateInterval: number | null = null;

  // Callbacks
  private playCallback: (assetId: string, bus: BusId, volume: number, startTime?: number) => string | null;
  private stopCallback: (voiceId: string, fadeMs?: number) => void;
  private setVolumeCallback: (voiceId: string, volume: number, fadeMs?: number) => void;
  private getPlaybackTimeCallback: (voiceId: string) => number | null;
  private onTransitionStart?: (from: MusicTrackInfo, to: MusicTrackInfo) => void;
  private onTransitionComplete?: (track: MusicTrackInfo) => void;

  constructor(
    playCallback: (assetId: string, bus: BusId, volume: number, startTime?: number) => string | null,
    stopCallback: (voiceId: string, fadeMs?: number) => void,
    setVolumeCallback: (voiceId: string, volume: number, fadeMs?: number) => void,
    getPlaybackTimeCallback: (voiceId: string) => number | null,
    onTransitionStart?: (from: MusicTrackInfo, to: MusicTrackInfo) => void,
    onTransitionComplete?: (track: MusicTrackInfo) => void
  ) {
    this.playCallback = playCallback;
    this.stopCallback = stopCallback;
    this.setVolumeCallback = setVolumeCallback;
    this.getPlaybackTimeCallback = getPlaybackTimeCallback;
    this.onTransitionStart = onTransitionStart;
    this.onTransitionComplete = onTransitionComplete;

    // Register default rules
    DEFAULT_TRANSITION_RULES.forEach(rule => this.registerRule(rule));

    this.startUpdateLoop();
  }

  /**
   * Register a transition rule
   */
  registerRule(rule: TransitionRule): void {
    this.rules.set(rule.id, rule);
  }

  /**
   * Set current playing track
   */
  setCurrentTrack(track: MusicTrackInfo): void {
    this.currentTrack = track;
  }

  /**
   * Get current track
   */
  getCurrentTrack(): MusicTrackInfo | null {
    return this.currentTrack;
  }

  /**
   * Transition to a new track
   */
  transitionTo(
    destTrack: MusicTrackInfo,
    ruleId?: string,
    immediate: boolean = false
  ): boolean {
    if (!this.currentTrack) {
      // No current track - just start playing
      const voiceId = this.playCallback(destTrack.assetId, 'music', 1, destTrack.entryCue);
      destTrack.voiceId = voiceId ?? undefined;
      this.currentTrack = destTrack;
      return true;
    }

    // Find matching rule
    const rule = ruleId
      ? this.rules.get(ruleId)
      : this.findMatchingRule(this.currentTrack, destTrack);

    if (!rule) {
      // Default to crossfade
      return this.executeCrossfade(this.currentTrack, destTrack, 1000);
    }

    if (immediate || rule.sync === 'immediate') {
      return this.executeTransition(this.currentTrack, destTrack, rule);
    }

    // Schedule transition
    const scheduledTime = this.calculateScheduledTime(this.currentTrack, rule);

    this.pendingTransition = {
      sourceTrack: this.currentTrack,
      destTrack,
      rule,
      scheduledTime,
      state: 'waiting',
    };

    return true;
  }

  /**
   * Cancel pending transition
   */
  cancelTransition(): boolean {
    if (!this.pendingTransition) return false;

    this.pendingTransition = null;
    return true;
  }

  /**
   * Find matching transition rule
   */
  private findMatchingRule(source: MusicTrackInfo, dest: MusicTrackInfo): TransitionRule | null {
    for (const rule of this.rules.values()) {
      // Check source pattern
      if (rule.sourcePattern) {
        const sourceRegex = new RegExp(rule.sourcePattern);
        if (!sourceRegex.test(source.id) && !sourceRegex.test(source.assetId)) {
          continue;
        }
      }

      // Check dest pattern
      if (rule.destPattern) {
        const destRegex = new RegExp(rule.destPattern);
        if (!destRegex.test(dest.id) && !destRegex.test(dest.assetId)) {
          continue;
        }
      }

      return rule;
    }

    return null;
  }

  /**
   * Calculate when transition should start
   */
  private calculateScheduledTime(source: MusicTrackInfo, rule: TransitionRule): number {
    const now = performance.now();

    if (!source.voiceId) return now;

    const currentTime = this.getPlaybackTimeCallback(source.voiceId) ?? source.currentTime;

    switch (rule.sync) {
      case 'immediate':
        return now;

      case 'next-beat': {
        if (!source.bpm) return now;
        const beatDuration = 60 / source.bpm;
        const currentBeat = currentTime / beatDuration;
        const nextBeat = Math.ceil(currentBeat);
        const timeToNextBeat = (nextBeat - currentBeat) * beatDuration;
        return now + timeToNextBeat * 1000;
      }

      case 'next-bar': {
        if (!source.bpm || !source.timeSignature) return now;
        const beatDuration = 60 / source.bpm;
        const beatsPerBar = source.timeSignature[0];
        const barDuration = beatDuration * beatsPerBar;
        const currentBar = currentTime / barDuration;
        const nextBar = Math.ceil(currentBar);
        const timeToNextBar = (nextBar - currentBar) * barDuration;
        return now + timeToNextBar * 1000;
      }

      case 'exit-cue': {
        if (source.exitCue === undefined) return now;
        const timeToExit = source.exitCue - currentTime;
        return now + Math.max(0, timeToExit * 1000);
      }

      default:
        return now;
    }
  }

  /**
   * Execute transition
   */
  private executeTransition(
    source: MusicTrackInfo,
    dest: MusicTrackInfo,
    rule: TransitionRule
  ): boolean {
    this.onTransitionStart?.(source, dest);

    switch (rule.type) {
      case 'immediate':
        return this.executeCut(source, dest);

      case 'crossfade':
        return this.executeCrossfade(source, dest, rule.fadeDurationMs ?? 1000);

      case 'fade-out-in':
        return this.executeFadeOutIn(source, dest, rule.fadeDurationMs ?? 500);

      case 'stinger':
        return this.executeStingerTransition(source, dest, rule);

      case 'musical':
        return this.executeMusicalTransition(source, dest, rule);

      default:
        return this.executeCrossfade(source, dest, 1000);
    }
  }

  /**
   * Immediate cut transition
   */
  private executeCut(source: MusicTrackInfo, dest: MusicTrackInfo): boolean {
    // Stop source immediately
    if (source.voiceId) {
      this.stopCallback(source.voiceId, 0);
    }

    // Start destination
    const startTime = dest.entryCue ?? 0;
    const voiceId = this.playCallback(dest.assetId, 'music', 1, startTime);
    dest.voiceId = voiceId ?? undefined;
    this.currentTrack = dest;

    this.onTransitionComplete?.(dest);
    return true;
  }

  /**
   * Crossfade transition
   */
  private executeCrossfade(
    source: MusicTrackInfo,
    dest: MusicTrackInfo,
    durationMs: number
  ): boolean {
    // Start destination at low volume
    const startTime = dest.entryCue ?? 0;
    const voiceId = this.playCallback(dest.assetId, 'music', 0, startTime);
    dest.voiceId = voiceId ?? undefined;

    // Fade in destination
    if (dest.voiceId) {
      this.setVolumeCallback(dest.voiceId, 1, durationMs);
    }

    // Fade out source
    if (source.voiceId) {
      this.setVolumeCallback(source.voiceId, 0, durationMs);

      // Stop source after fade
      setTimeout(() => {
        if (source.voiceId) {
          this.stopCallback(source.voiceId, 0);
        }
      }, durationMs);
    }

    this.currentTrack = dest;

    setTimeout(() => {
      this.onTransitionComplete?.(dest);
    }, durationMs);

    return true;
  }

  /**
   * Fade out then fade in transition
   */
  private executeFadeOutIn(
    source: MusicTrackInfo,
    dest: MusicTrackInfo,
    fadeMs: number
  ): boolean {
    // Fade out source
    if (source.voiceId) {
      this.setVolumeCallback(source.voiceId, 0, fadeMs);
    }

    // After fade out, start destination
    setTimeout(() => {
      if (source.voiceId) {
        this.stopCallback(source.voiceId, 0);
      }

      const startTime = dest.entryCue ?? 0;
      const voiceId = this.playCallback(dest.assetId, 'music', 0, startTime);
      dest.voiceId = voiceId ?? undefined;

      if (dest.voiceId) {
        this.setVolumeCallback(dest.voiceId, 1, fadeMs);
      }

      this.currentTrack = dest;

      setTimeout(() => {
        this.onTransitionComplete?.(dest);
      }, fadeMs);
    }, fadeMs);

    return true;
  }

  /**
   * Stinger transition (play stinger during transition)
   */
  private executeStingerTransition(
    source: MusicTrackInfo,
    dest: MusicTrackInfo,
    rule: TransitionRule
  ): boolean {
    if (!rule.stingerId) {
      return this.executeCrossfade(source, dest, 500);
    }

    const fadeMs = rule.fadeDurationMs ?? 200;
    const destDelay = rule.destDelayMs ?? 500;

    // Fade out source
    if (source.voiceId) {
      this.setVolumeCallback(source.voiceId, 0, fadeMs);
    }

    // Play stinger
    this.playCallback(rule.stingerId, 'music', 1);

    // Stop source after fade
    setTimeout(() => {
      if (source.voiceId) {
        this.stopCallback(source.voiceId, 0);
      }
    }, fadeMs);

    // Start destination after delay
    setTimeout(() => {
      const startTime = dest.entryCue ?? 0;
      const voiceId = this.playCallback(dest.assetId, 'music', 0, startTime);
      dest.voiceId = voiceId ?? undefined;

      if (dest.voiceId) {
        this.setVolumeCallback(dest.voiceId, 1, fadeMs);
      }

      this.currentTrack = dest;
      this.onTransitionComplete?.(dest);
    }, destDelay);

    return true;
  }

  /**
   * Musical transition (with pre-entry support)
   */
  private executeMusicalTransition(
    source: MusicTrackInfo,
    dest: MusicTrackInfo,
    rule: TransitionRule
  ): boolean {
    const fadeMs = rule.fadeDurationMs ?? 500;
    const preEntry = rule.preEntryMs ?? 0;

    if (preEntry > 0) {
      // Start destination early (pre-entry)
      const startTime = dest.entryCue ?? 0;
      const voiceId = this.playCallback(dest.assetId, 'music', 0, startTime);
      dest.voiceId = voiceId ?? undefined;

      // Fade in destination over pre-entry period
      if (dest.voiceId) {
        this.setVolumeCallback(dest.voiceId, 1, preEntry);
      }

      // Fade out source
      if (source.voiceId) {
        this.setVolumeCallback(source.voiceId, 0, preEntry);
        setTimeout(() => {
          if (source.voiceId) {
            this.stopCallback(source.voiceId, 0);
          }
        }, preEntry);
      }

      this.currentTrack = dest;
      setTimeout(() => {
        this.onTransitionComplete?.(dest);
      }, preEntry);
    } else {
      // Standard crossfade
      return this.executeCrossfade(source, dest, fadeMs);
    }

    return true;
  }

  /**
   * Update loop - check for scheduled transitions
   */
  private startUpdateLoop(): void {
    const update = () => {
      const now = performance.now();

      if (this.pendingTransition && this.pendingTransition.state === 'waiting') {
        if (now >= this.pendingTransition.scheduledTime) {
          this.pendingTransition.state = 'transitioning';
          this.executeTransition(
            this.pendingTransition.sourceTrack,
            this.pendingTransition.destTrack,
            this.pendingTransition.rule
          );
          this.pendingTransition = null;
        }
      }

      // Update current track time
      if (this.currentTrack?.voiceId) {
        const time = this.getPlaybackTimeCallback(this.currentTrack.voiceId);
        if (time !== null) {
          this.currentTrack.currentTime = time;
        }
      }

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
   * Get pending transition info
   */
  getPendingTransition(): PendingTransition | null {
    return this.pendingTransition;
  }

  /**
   * Get all rules
   */
  getRules(): TransitionRule[] {
    return Array.from(this.rules.values());
  }

  /**
   * Dispose
   */
  dispose(): void {
    this.stopUpdateLoop();

    if (this.currentTrack?.voiceId) {
      this.stopCallback(this.currentTrack.voiceId, 100);
    }

    this.rules.clear();
    this.currentTrack = null;
    this.pendingTransition = null;
  }
}

// ============ DEFAULT TRANSITION RULES ============

export const DEFAULT_TRANSITION_RULES: TransitionRule[] = [
  {
    id: 'base_to_freespins',
    sourcePattern: 'music_base',
    destPattern: 'music_freespins',
    type: 'stinger',
    sync: 'next-bar',
    stingerId: 'stinger_freespins_enter',
    fadeDurationMs: 300,
    destDelayMs: 800,
  },
  {
    id: 'freespins_to_base',
    sourcePattern: 'music_freespins',
    destPattern: 'music_base',
    type: 'crossfade',
    sync: 'exit-cue',
    fadeDurationMs: 2000,
    useExitCue: true,
    useEntryCue: true,
  },
  {
    id: 'to_bigwin',
    destPattern: 'music_bigwin',
    type: 'immediate',
    sync: 'immediate',
  },
  {
    id: 'bigwin_to_base',
    sourcePattern: 'music_bigwin',
    destPattern: 'music_base',
    type: 'crossfade',
    sync: 'immediate',
    fadeDurationMs: 1500,
  },
  {
    id: 'default_musical',
    type: 'musical',
    sync: 'next-bar',
    fadeDurationMs: 1000,
    preEntryMs: 500,
  },
];
