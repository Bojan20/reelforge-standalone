/**
 * ReelForge Playback Store React Hooks
 *
 * React bindings for the playback store with
 * optimized re-renders via selectors.
 *
 * @module store/usePlaybackStore
 */

import { useSyncExternalStore, useCallback, useMemo } from 'react';
import {
  getPlaybackStore,
  type PlaybackStoreState,
  type TimelinePlaybackState,
  type MixerPlaybackState,
} from './playbackStore';

// ============ Main Hook ============

/**
 * Subscribe to the entire playback state.
 * Use specialized hooks for better performance.
 */
export function usePlaybackStore(): PlaybackStoreState {
  const store = getPlaybackStore();

  return useSyncExternalStore(
    store.subscribe.bind(store),
    store.getState.bind(store),
    store.getState.bind(store)
  );
}

// ============ Timeline Hooks ============

/**
 * Timeline playback state and controls.
 * Use this for DAW timeline playback.
 */
export function useTimelinePlayback() {
  const store = getPlaybackStore();

  const state = useSyncExternalStore(
    store.subscribe.bind(store),
    store.getTimelineState.bind(store),
    store.getTimelineState.bind(store)
  );

  const actions = useMemo(
    () => ({
      play: () => store.setTimelinePlaying(true),
      pause: () => store.setTimelinePaused(true),
      stop: () => store.stopTimeline(),
      togglePlay: () => {
        const current = store.getTimelineState();
        if (current.isPlaying) {
          store.setTimelinePaused(true);
        } else {
          store.setTimelinePlaying(true);
        }
      },
      seek: (time: number) => store.setTimelineCurrentTime(time),
      setDuration: (duration: number) => store.setTimelineDuration(duration),
      setLoop: (enabled: boolean, start?: number, end?: number) =>
        store.setTimelineLoop(enabled, start, end),
      toggleLoop: () => {
        const current = store.getTimelineState();
        store.setTimelineLoop(!current.loopEnabled);
      },
    }),
    [store]
  );

  return { ...state, ...actions };
}

// ============ Mixer Hooks ============

/**
 * Mixer playback state and controls.
 * Use this for event/sound preview and metering.
 */
export function useMixerPlayback() {
  const store = getPlaybackStore();

  const state = useSyncExternalStore(
    store.subscribe.bind(store),
    store.getMixerState.bind(store),
    store.getMixerState.bind(store)
  );

  const actions = useMemo(
    () => ({
      playEvent: (eventId: string) => store.setMixerCurrentEvent(eventId),
      playSound: (soundId: string) => store.setMixerCurrentSound(soundId),
      stop: () => store.stopMixer(),
      setVoiceCount: (count: number) => store.setMixerActiveVoiceCount(count),
    }),
    [store]
  );

  return { ...state, ...actions };
}

// ============ Combined Hooks ============

/**
 * Check if anything is playing (timeline or mixer).
 */
export function useIsAnythingPlaying(): boolean {
  const store = getPlaybackStore();

  return useSyncExternalStore(
    store.subscribe.bind(store),
    () => store.isAnythingPlaying(),
    () => store.isAnythingPlaying()
  );
}

/**
 * Stop all playback action.
 */
export function useStopAll() {
  const store = getPlaybackStore();

  return useCallback(() => {
    store.stopAll();
  }, [store]);
}

// ============ Exports ============

export type { TimelinePlaybackState, MixerPlaybackState, PlaybackStoreState };
