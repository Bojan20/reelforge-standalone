/**
 * ReelForge Playback Store
 *
 * Separate playback states for Timeline (DAW) and Mixer (Preview).
 * Prevents coupling between timeline playback and event/mixer preview.
 *
 * Timeline: DAW-style playback of clips on timeline
 * Mixer: Event preview, sound preview, bus metering
 *
 * @module store/playbackStore
 */

// ============ Types ============

export interface TimelinePlaybackState {
  isPlaying: boolean;
  isPaused: boolean;
  currentTime: number;
  duration: number;
  loopEnabled: boolean;
  loopStart: number;
  loopEnd: number;
}

export interface MixerPlaybackState {
  isPlaying: boolean;
  currentEventId: string | null;
  currentSoundId: string | null;
  activeVoiceCount: number;
}

export interface PlaybackStoreState {
  timeline: TimelinePlaybackState;
  mixer: MixerPlaybackState;
}

// ============ Default State ============

function createDefaultState(): PlaybackStoreState {
  return {
    timeline: {
      isPlaying: false,
      isPaused: false,
      currentTime: 0,
      duration: 60,
      loopEnabled: false,
      loopStart: 0,
      loopEnd: 60,
    },
    mixer: {
      isPlaying: false,
      currentEventId: null,
      currentSoundId: null,
      activeVoiceCount: 0,
    },
  };
}

// ============ Store Implementation ============

type Listener = () => void;

class PlaybackStore {
  private state: PlaybackStoreState;
  private listeners: Set<Listener> = new Set();

  constructor() {
    this.state = createDefaultState();
  }

  // ============ State Access ============

  getState(): PlaybackStoreState {
    return this.state;
  }

  getTimelineState(): TimelinePlaybackState {
    return this.state.timeline;
  }

  getMixerState(): MixerPlaybackState {
    return this.state.mixer;
  }

  // ============ Subscriptions ============

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private notify(): void {
    for (const listener of this.listeners) {
      listener();
    }
  }

  // ============ Timeline Actions ============

  setTimelinePlaying(isPlaying: boolean): void {
    this.state = {
      ...this.state,
      timeline: {
        ...this.state.timeline,
        isPlaying,
        isPaused: false,
      },
    };
    this.notify();
  }

  setTimelinePaused(isPaused: boolean): void {
    this.state = {
      ...this.state,
      timeline: {
        ...this.state.timeline,
        isPlaying: false,
        isPaused,
      },
    };
    this.notify();
  }

  setTimelineCurrentTime(currentTime: number): void {
    this.state = {
      ...this.state,
      timeline: {
        ...this.state.timeline,
        currentTime,
      },
    };
    this.notify();
  }

  setTimelineDuration(duration: number): void {
    this.state = {
      ...this.state,
      timeline: {
        ...this.state.timeline,
        duration,
      },
    };
    this.notify();
  }

  setTimelineLoop(enabled: boolean, start?: number, end?: number): void {
    this.state = {
      ...this.state,
      timeline: {
        ...this.state.timeline,
        loopEnabled: enabled,
        loopStart: start ?? this.state.timeline.loopStart,
        loopEnd: end ?? this.state.timeline.loopEnd,
      },
    };
    this.notify();
  }

  stopTimeline(): void {
    this.state = {
      ...this.state,
      timeline: {
        ...this.state.timeline,
        isPlaying: false,
        isPaused: false,
        currentTime: 0,
      },
    };
    this.notify();
  }

  // ============ Mixer Actions ============

  setMixerPlaying(isPlaying: boolean): void {
    this.state = {
      ...this.state,
      mixer: {
        ...this.state.mixer,
        isPlaying,
      },
    };
    this.notify();
  }

  setMixerCurrentEvent(eventId: string | null): void {
    this.state = {
      ...this.state,
      mixer: {
        ...this.state.mixer,
        currentEventId: eventId,
        isPlaying: eventId !== null,
      },
    };
    this.notify();
  }

  setMixerCurrentSound(soundId: string | null): void {
    this.state = {
      ...this.state,
      mixer: {
        ...this.state.mixer,
        currentSoundId: soundId,
        isPlaying: soundId !== null,
      },
    };
    this.notify();
  }

  setMixerActiveVoiceCount(count: number): void {
    this.state = {
      ...this.state,
      mixer: {
        ...this.state.mixer,
        activeVoiceCount: count,
        isPlaying: count > 0,
      },
    };
    this.notify();
  }

  stopMixer(): void {
    this.state = {
      ...this.state,
      mixer: {
        isPlaying: false,
        currentEventId: null,
        currentSoundId: null,
        activeVoiceCount: 0,
      },
    };
    this.notify();
  }

  // ============ Combined Actions ============

  /** Stop all playback (both timeline and mixer) */
  stopAll(): void {
    this.state = createDefaultState();
    this.notify();
  }

  /** Check if anything is playing */
  isAnythingPlaying(): boolean {
    return this.state.timeline.isPlaying || this.state.mixer.isPlaying;
  }
}

// ============ Singleton ============

let storeInstance: PlaybackStore | null = null;

export function getPlaybackStore(): PlaybackStore {
  if (!storeInstance) {
    storeInstance = new PlaybackStore();
  }
  return storeInstance;
}

export default PlaybackStore;
