/**
 * useTimelinePlayback - Connect timeline clips to audio playback
 *
 * This hook manages timeline playback state and coordinates
 * audio playback with clip positions and transport controls.
 *
 * @module hooks/useTimelinePlayback
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import { getSharedAudioContext, ensureAudioContextResumed } from '../core/AudioContextManager';

// ============ Types ============

export type BusType = 'master' | 'music' | 'sfx' | 'ambience' | 'voice';

export interface TimelineClipData {
  id: string;
  trackId: string;
  name: string;
  startTime: number; // In seconds (position on timeline)
  duration: number;  // In seconds (visible duration)
  audioBuffer?: AudioBuffer;
  blobUrl?: string;
  color?: string;
  /** Offset into source audio where playback starts (skip MP3/AAC padding) */
  sourceOffset?: number;
  /** Output bus for this clip's track */
  outputBus?: BusType;
}

export interface PlayingClip {
  clipId: string;
  source: AudioBufferSourceNode;
  gainNode: GainNode;
  startedAt: number; // AudioContext time when started
  offset: number;    // Offset into the clip
}

export interface TimelinePlaybackState {
  isPlaying: boolean;
  isPaused: boolean;
  currentTime: number;
  duration: number;
  loopEnabled: boolean;
  loopStart: number;
  loopEnd: number;
}

export interface PlaybackCrossfade {
  id: string;
  clipAId: string;
  clipBId: string;
  startTime: number;
  duration: number;
  curveType?: 'linear' | 'equal-power' | 's-curve';
}

export interface UseTimelinePlaybackOptions {
  /** Clips to play */
  clips: TimelineClipData[];
  /** Initial duration (auto-calculated if not provided) */
  duration?: number;
  /** Auto-update interval in ms */
  updateInterval?: number;
  /** On time update callback */
  onTimeUpdate?: (time: number) => void;
  /** On playback end callback */
  onPlaybackEnd?: () => void;
  /** External master gain node to use (for mixer integration) - fallback for unrouted clips */
  externalMasterGain?: GainNode | null;
  /** Bus gain nodes for routing (key = bus id, value = GainNode) */
  busGains?: Record<BusType, GainNode | null>;
  /** Active crossfades to apply gain curves */
  crossfades?: PlaybackCrossfade[];
}

// ============ Hook ============

export function useTimelinePlayback(options: UseTimelinePlaybackOptions) {
  const {
    clips,
    duration: initialDuration,
    updateInterval = 50,
    onTimeUpdate,
    onPlaybackEnd,
    externalMasterGain,
    busGains,
    crossfades = [],
  } = options;

  // State
  const [state, setState] = useState<TimelinePlaybackState>({
    isPlaying: false,
    isPaused: false,
    currentTime: 0,
    duration: initialDuration ?? 60,
    loopEnabled: false,
    loopStart: 0,
    loopEnd: 60,
  });

  // Refs
  const playingClipsRef = useRef<Map<string, PlayingClip>>(new Map());
  const scheduledClipsRef = useRef<Set<string>>(new Set());
  const ctxRef = useRef<AudioContext | null>(null);
  const masterGainRef = useRef<GainNode | null>(null);
  const playbackStartTimeRef = useRef<number>(0);
  const playbackOffsetRef = useRef<number>(0);
  const updateIntervalRef = useRef<number | null>(null);
  const clipBuffersRef = useRef<Map<string, AudioBuffer>>(new Map());

  // Calculate duration from clips - always update based on actual clip content
  useEffect(() => {
    if (clips.length > 0) {
      const maxEnd = clips.reduce(
        (max, clip) => Math.max(max, clip.startTime + clip.duration),
        0
      );
      // Always use the larger of: calculated max or initial duration
      const newDuration = Math.max(maxEnd, initialDuration ?? 0);
      if (newDuration !== state.duration) {
        console.log('[TimelinePlayback] Duration updated:', {
          oldDuration: state.duration,
          newDuration,
          maxClipEnd: maxEnd,
          clipCount: clips.length,
        });
        setState((prev) => ({ ...prev, duration: newDuration }));
      }
    }
  }, [clips, initialDuration, state.duration]);

  // Load audio buffers for clips
  const loadClipBuffer = useCallback(async (clip: TimelineClipData): Promise<AudioBuffer | null> => {
    // Check cache
    const cached = clipBuffersRef.current.get(clip.id);
    if (cached) return cached;

    // If clip has buffer, use it
    if (clip.audioBuffer) {
      clipBuffersRef.current.set(clip.id, clip.audioBuffer);
      return clip.audioBuffer;
    }

    // If clip has blob URL, fetch and decode
    if (clip.blobUrl) {
      try {
        const ctx = ctxRef.current ?? getSharedAudioContext();
        const response = await fetch(clip.blobUrl);
        const arrayBuffer = await response.arrayBuffer();
        const audioBuffer = await ctx.decodeAudioData(arrayBuffer);
        clipBuffersRef.current.set(clip.id, audioBuffer);
        return audioBuffer;
      } catch (err) {
        console.error(`[TimelinePlayback] Failed to load buffer for ${clip.name}:`, err);
        return null;
      }
    }

    return null;
  }, []);

  // Schedule a clip for playback
  // Cubase-style: supports scheduling at precise future AudioContext time
  const scheduleClip = useCallback(async (
    clip: TimelineClipData,
    currentTime: number,
    ctx: AudioContext,
    _masterGain: GainNode, // Reserved for bus routing
    scheduleAtTime?: number // Optional: schedule to start at this AudioContext time (for seamless loops)
  ) => {
    // Generate unique key for this scheduling (allows multiple schedules for loop pre-scheduling)
    const scheduleKey = scheduleAtTime ? `${clip.id}@${scheduleAtTime.toFixed(3)}` : clip.id;

    // Don't schedule if already scheduled with same key
    if (scheduledClipsRef.current.has(scheduleKey)) return;

    // Get or load buffer
    const buffer = await loadClipBuffer(clip);
    if (!buffer) return;

    // Calculate timing
    const clipStart = clip.startTime;
    const clipEnd = clip.startTime + clip.duration;

    // Check if clip should be playing at the target time
    if (currentTime < clipStart || currentTime >= clipEnd) return;

    // Calculate offset into clip (timeline position relative to clip start)
    const timelineOffset = currentTime - clipStart;

    // Source offset (skip leading silence from MP3/AAC padding)
    const sourceOffset = clip.sourceOffset ?? 0;

    // Where to start in the buffer
    const bufferOffset = sourceOffset + timelineOffset;

    // How much audio remains in the buffer from this offset
    const bufferRemaining = buffer.duration - bufferOffset;

    // How much clip duration remains on timeline
    const clipRemaining = clip.duration - timelineOffset;

    // Play the shorter of the two (don't play beyond buffer or beyond clip end)
    const playDuration = Math.min(bufferRemaining, clipRemaining);

    // Don't play if nothing left
    if (playDuration <= 0 || bufferOffset >= buffer.duration) return;

    // Create nodes
    const source = ctx.createBufferSource();
    source.buffer = buffer;

    const gainNode = ctx.createGain();
    gainNode.gain.value = 1;

    // Connect: source -> gain -> destination
    source.connect(gainNode);
    gainNode.connect(ctx.destination);

    // Mark as scheduled
    scheduledClipsRef.current.add(scheduleKey);

    // Start playback - either immediately or at scheduled future time
    const startWhen = scheduleAtTime ?? 0;
    source.start(startWhen, bufferOffset, playDuration);

    // Track playing clip (use base clip.id for tracking, not scheduleKey)
    const playingKey = scheduleAtTime ? `${clip.id}@loop` : clip.id;
    playingClipsRef.current.set(playingKey, {
      clipId: clip.id,
      source,
      gainNode,
      startedAt: scheduleAtTime ?? ctx.currentTime,
      offset: bufferOffset,
    });

    // Handle end - clean up both keys
    source.onended = () => {
      playingClipsRef.current.delete(playingKey);
      scheduledClipsRef.current.delete(scheduleKey);
    };

    console.log(`[TimelinePlayback] ${scheduleAtTime ? 'Pre-scheduled' : 'Playing'}: ${clip.name}`, {
      bufferOffset: bufferOffset.toFixed(3),
      playDuration: playDuration.toFixed(3),
      startWhen: startWhen.toFixed(3),
    });
  }, [loadClipBuffer, busGains]);

  // Stop a specific clip
  const stopClip = useCallback((clipId: string) => {
    const playing = playingClipsRef.current.get(clipId);
    if (playing) {
      try {
        playing.source.stop();
        playing.source.disconnect();
        playing.gainNode.disconnect();
      } catch {
        // Ignore if already stopped
      }
      playingClipsRef.current.delete(clipId);
      scheduledClipsRef.current.delete(clipId);
    }
  }, []);

  // Stop all clips
  const stopAllClips = useCallback(() => {
    playingClipsRef.current.forEach((playing) => {
      try {
        playing.source.stop();
        playing.source.disconnect();
        playing.gainNode.disconnect();
      } catch {
        // Ignore
      }
    });
    playingClipsRef.current.clear();
    scheduledClipsRef.current.clear();
  }, []);

  // Ref to track if next loop iteration has been pre-scheduled
  const loopPreScheduledRef = useRef<number | null>(null);

  // Update playback - schedule clips, update time
  // Uses Cubase-style PRE-SCHEDULING: schedules next loop iteration BEFORE current one ends
  // This eliminates gaps by having audio already queued in the Web Audio scheduler
  const updatePlayback = useCallback(() => {
    if (!ctxRef.current || !masterGainRef.current) return;

    const ctx = ctxRef.current;
    const masterGain = masterGainRef.current;

    // Calculate current timeline time using high-precision audio clock
    const elapsed = ctx.currentTime - playbackStartTimeRef.current;
    let currentTime = playbackOffsetRef.current + elapsed;

    // Cubase-style seamless loop: PRE-SCHEDULE next iteration while current plays
    // Look-ahead window should be large enough to schedule before we reach loop end
    const LOOP_LOOKAHEAD = 0.1; // 100ms look-ahead for pre-scheduling

    if (state.loopEnabled) {
      const loopDuration = state.loopEnd - state.loopStart;
      const timeToLoopEnd = state.loopEnd - currentTime;

      // PRE-SCHEDULE: When approaching loop end, schedule next iteration at precise future time
      // This happens WHILE current clips are still playing - no stop required
      if (timeToLoopEnd > 0 && timeToLoopEnd <= LOOP_LOOKAHEAD && loopPreScheduledRef.current !== state.loopEnd) {
        // Calculate exact AudioContext time when loop should restart
        const loopRestartCtxTime = ctx.currentTime + timeToLoopEnd;

        console.log('[TimelinePlayback] Pre-scheduling loop restart', {
          timeToLoopEnd: timeToLoopEnd.toFixed(4),
          loopRestartCtxTime: loopRestartCtxTime.toFixed(4),
          loopStart: state.loopStart.toFixed(4),
        });

        // Pre-schedule clips to start at exact loop boundary
        for (const clip of clips) {
          const clipStart = clip.startTime;
          const clipEnd = clip.startTime + clip.duration;

          // Check if clip should play at loop start position
          if (state.loopStart >= clipStart && state.loopStart < clipEnd) {
            scheduleClip(clip, state.loopStart, ctx, masterGain, loopRestartCtxTime);
          }
        }

        // Mark as pre-scheduled to avoid duplicate scheduling
        loopPreScheduledRef.current = state.loopEnd;
      }

      // When we've passed loop end, update timing references
      // The audio is already playing from pre-scheduling - just sync the UI
      if (currentTime >= state.loopEnd) {
        const overshoot = currentTime - state.loopEnd;
        currentTime = state.loopStart + (overshoot % loopDuration);

        // Reset timing references for the new loop iteration
        playbackStartTimeRef.current = ctx.currentTime - overshoot;
        playbackOffsetRef.current = state.loopStart;

        // Clear pre-schedule flag for next iteration
        loopPreScheduledRef.current = null;

        // Clean up old clips that have finished
        // Don't stop them - they'll end naturally via onended callback
      }
    }

    // Calculate actual end time based on clips (not arbitrary duration)
    const actualEnd = clips.length > 0
      ? Math.max(...clips.map(c => c.startTime + c.duration))
      : state.duration;

    // Check for end - only stop when ALL clips have finished
    // Don't stop based on state.duration, stop based on actual content
    const hasActiveClips = playingClipsRef.current.size > 0;
    const pastAllClips = currentTime >= actualEnd;

    if (pastAllClips && !hasActiveClips && !state.loopEnabled) {
      setState((prev) => ({
        ...prev,
        isPlaying: false,
        currentTime: actualEnd,
      }));
      onPlaybackEnd?.();
      return;
    }

    // Update state
    setState((prev) => ({ ...prev, currentTime }));
    onTimeUpdate?.(currentTime);

    // Schedule any clips that should start playing
    for (const clip of clips) {
      const clipStart = clip.startTime;
      const clipEnd = clip.startTime + clip.duration;

      // If clip should be playing now and isn't scheduled yet
      if (currentTime >= clipStart && currentTime < clipEnd) {
        if (!playingClipsRef.current.has(clip.id) && !scheduledClipsRef.current.has(clip.id)) {
          scheduleClip(clip, currentTime, ctx, masterGain);
        }
      }
      // NOTE: Don't force-stop clips here!
      // Let them finish naturally via source.onended
      // This prevents cutting off audio prematurely
    }

    // Apply crossfade gain curves to playing clips
    for (const xfade of crossfades) {
      const playingA = playingClipsRef.current.get(xfade.clipAId);
      const playingB = playingClipsRef.current.get(xfade.clipBId);

      const xfadeStart = xfade.startTime;
      const xfadeEnd = xfade.startTime + xfade.duration;

      // Check if we're in the crossfade region
      if (currentTime >= xfadeStart && currentTime < xfadeEnd) {
        const progress = (currentTime - xfadeStart) / xfade.duration;

        // Calculate gain based on curve type
        let fadeOutGain: number;
        let fadeInGain: number;

        switch (xfade.curveType) {
          case 'equal-power':
            // Equal power crossfade (constant loudness)
            fadeOutGain = Math.cos(progress * Math.PI / 2);
            fadeInGain = Math.sin(progress * Math.PI / 2);
            break;
          case 's-curve':
            // S-curve (smoother transition)
            const t = progress * progress * (3 - 2 * progress);
            fadeOutGain = 1 - t;
            fadeInGain = t;
            break;
          case 'linear':
          default:
            // Linear crossfade
            fadeOutGain = 1 - progress;
            fadeInGain = progress;
            break;
        }

        // Apply gains
        if (playingA) {
          playingA.gainNode.gain.setValueAtTime(fadeOutGain, ctx.currentTime);
        }
        if (playingB) {
          playingB.gainNode.gain.setValueAtTime(fadeInGain, ctx.currentTime);
        }
      }
    }
  }, [clips, crossfades, state.loopEnabled, state.loopEnd, state.loopStart, state.duration,
      scheduleClip, stopAllClips, onTimeUpdate, onPlaybackEnd]);

  // Play
  const play = useCallback(async () => {
    try {
      await ensureAudioContextResumed();
      const ctx = getSharedAudioContext();
      ctxRef.current = ctx;

      // Use external master gain if provided (for mixer integration), otherwise create our own
      if (externalMasterGain) {
        masterGainRef.current = externalMasterGain;
      } else if (!masterGainRef.current) {
        masterGainRef.current = ctx.createGain();
        masterGainRef.current.gain.value = 1;
        masterGainRef.current.connect(ctx.destination);
      }

      // Set playback start time
      playbackStartTimeRef.current = ctx.currentTime;
      playbackOffsetRef.current = state.currentTime;

      // Reset loop pre-schedule flag
      loopPreScheduledRef.current = null;

      // Start update interval
      if (updateIntervalRef.current) {
        clearInterval(updateIntervalRef.current);
      }
      updateIntervalRef.current = window.setInterval(updatePlayback, updateInterval);

      // Initial update
      updatePlayback();

      setState((prev) => ({
        ...prev,
        isPlaying: true,
        isPaused: false,
      }));

      console.log('[TimelinePlayback] Playback started at', state.currentTime.toFixed(2), {
        ctxState: ctx.state,
        externalMasterGain: externalMasterGain ? 'provided' : 'null',
        masterGainRef: masterGainRef.current ? 'exists' : 'null',
        busGainsProvided: busGains ? Object.keys(busGains).filter(k => busGains[k as keyof typeof busGains]).join(',') : 'none',
      });
    } catch (err) {
      console.error('[TimelinePlayback] Play error:', err);
    }
  }, [state.currentTime, updatePlayback, updateInterval, externalMasterGain]);

  // Pause
  const pause = useCallback(() => {
    // Stop update interval
    if (updateIntervalRef.current) {
      clearInterval(updateIntervalRef.current);
      updateIntervalRef.current = null;
    }

    // Stop all clips
    stopAllClips();

    setState((prev) => ({
      ...prev,
      isPlaying: false,
      isPaused: true,
    }));

    console.log('[TimelinePlayback] Paused at', state.currentTime.toFixed(2));
  }, [state.currentTime, stopAllClips]);

  // Stop
  const stop = useCallback(() => {
    // Stop update interval
    if (updateIntervalRef.current) {
      clearInterval(updateIntervalRef.current);
      updateIntervalRef.current = null;
    }

    // Stop all clips
    stopAllClips();

    setState((prev) => ({
      ...prev,
      isPlaying: false,
      isPaused: false,
      currentTime: 0,
    }));

    console.log('[TimelinePlayback] Stopped');
  }, [stopAllClips]);

  // Seek
  const seek = useCallback((time: number) => {
    const clampedTime = Math.max(0, Math.min(time, state.duration));

    // If playing, restart from new position
    if (state.isPlaying) {
      stopAllClips();
      playbackStartTimeRef.current = ctxRef.current?.currentTime ?? 0;
      playbackOffsetRef.current = clampedTime;
      // Reset loop pre-schedule flag on seek
      loopPreScheduledRef.current = null;
    }

    setState((prev) => ({
      ...prev,
      currentTime: clampedTime,
    }));
  }, [state.isPlaying, state.duration, stopAllClips]);

  // Toggle loop
  const toggleLoop = useCallback(() => {
    // Reset pre-schedule flag when toggling loop
    loopPreScheduledRef.current = null;
    setState((prev) => ({ ...prev, loopEnabled: !prev.loopEnabled }));
  }, []);

  // Set loop region
  const setLoopRegion = useCallback((start: number, end: number) => {
    // Reset pre-schedule flag when loop region changes
    loopPreScheduledRef.current = null;
    setState((prev) => ({
      ...prev,
      loopStart: Math.max(0, start),
      loopEnd: Math.min(end, prev.duration),
    }));
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (updateIntervalRef.current) {
        clearInterval(updateIntervalRef.current);
      }
      stopAllClips();
      if (masterGainRef.current) {
        masterGainRef.current.disconnect();
        masterGainRef.current = null;
      }
    };
  }, [stopAllClips]);

  return {
    // State
    isPlaying: state.isPlaying,
    isPaused: state.isPaused,
    currentTime: state.currentTime,
    duration: state.duration,
    loopEnabled: state.loopEnabled,
    loopStart: state.loopStart,
    loopEnd: state.loopEnd,

    // Actions
    play,
    pause,
    stop,
    seek,
    toggleLoop,
    setLoopRegion,

    // Utility
    loadClipBuffer,
    stopClip,
  };
}

export type TimelinePlaybackReturn = ReturnType<typeof useTimelinePlayback>;
