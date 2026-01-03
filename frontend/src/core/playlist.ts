/**
 * Playlist System
 *
 * Manages ordered playback of multiple sounds with:
 * - Sequential playback with optional gaps
 * - Shuffle/random modes
 * - Loop modes (none, playlist, track)
 * - Crossfade between tracks
 * - Track weights for weighted random
 * - Callbacks for track changes
 */

import type { BusId } from './types';

// ============ TYPES ============

export type PlaylistMode = 'sequential' | 'shuffle' | 'random' | 'weighted-random';
export type PlaylistLoopMode = 'none' | 'playlist' | 'track';

export interface PlaylistTrack {
  /** Unique track ID */
  id: string;
  /** Sound asset ID */
  assetId: string;
  /** Display name */
  name?: string;
  /** Volume for this track (0-1) */
  volume?: number;
  /** Weight for weighted random (higher = more likely) */
  weight?: number;
  /** Gap after this track in ms (before next track) */
  gapMs?: number;
  /** Crossfade into next track in ms */
  crossfadeMs?: number;
  /** Skip this track */
  skip?: boolean;
  /** Custom data */
  userData?: Record<string, unknown>;
}

export interface Playlist {
  /** Unique playlist ID */
  id: string;
  /** Display name */
  name: string;
  /** Description */
  description?: string;
  /** Tracks in order */
  tracks: PlaylistTrack[];
  /** Playback mode */
  mode: PlaylistMode;
  /** Loop mode */
  loopMode: PlaylistLoopMode;
  /** Bus to play on */
  bus: BusId;
  /** Base volume */
  volume: number;
  /** Default gap between tracks in ms */
  defaultGapMs?: number;
  /** Default crossfade in ms */
  defaultCrossfadeMs?: number;
  /** Shuffle avoids immediate repeats */
  avoidRepeats?: number;
}

export interface PlaylistState {
  playlistId: string;
  isPlaying: boolean;
  isPaused: boolean;
  currentTrackIndex: number;
  currentVoiceId: string | null;
  playHistory: string[]; // Track IDs
  shuffleQueue: number[]; // Remaining indices for shuffle
  startTime: number;
  pauseTime: number | null;
}

// ============ PLAYLIST MANAGER ============

export class PlaylistManager {
  private playlists: Map<string, Playlist> = new Map();
  private states: Map<string, PlaylistState> = new Map();
  private pendingTimers: Map<string, number> = new Map();
  private rng: () => number;

  // Callbacks
  private playCallback: (assetId: string, bus: BusId, volume: number) => string | null;
  private stopCallback: (voiceId: string, fadeMs?: number) => void;
  private onTrackStart?: (playlist: Playlist, track: PlaylistTrack, index: number) => void;
  private onTrackEnd?: (playlist: Playlist, track: PlaylistTrack, index: number) => void;
  private onPlaylistEnd?: (playlist: Playlist) => void;

  constructor(
    playCallback: (assetId: string, bus: BusId, volume: number) => string | null,
    stopCallback: (voiceId: string, fadeMs?: number) => void,
    onTrackStart?: (playlist: Playlist, track: PlaylistTrack, index: number) => void,
    onTrackEnd?: (playlist: Playlist, track: PlaylistTrack, index: number) => void,
    onPlaylistEnd?: (playlist: Playlist) => void,
    seed?: number
  ) {
    this.playCallback = playCallback;
    this.stopCallback = stopCallback;
    this.onTrackStart = onTrackStart;
    this.onTrackEnd = onTrackEnd;
    this.onPlaylistEnd = onPlaylistEnd;

    // Seedable RNG
    this.rng = seed !== undefined ? this.createSeededRandom(seed) : Math.random;

    // Register defaults
    DEFAULT_PLAYLISTS.forEach(p => this.registerPlaylist(p));
  }

  /**
   * Create seeded random generator
   */
  private createSeededRandom(seed: number): () => number {
    let state = seed;
    return () => {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      return state / 0x7fffffff;
    };
  }

  /**
   * Register a playlist
   */
  registerPlaylist(playlist: Playlist): void {
    this.playlists.set(playlist.id, playlist);
  }

  /**
   * Start playing a playlist
   */
  startPlaylist(playlistId: string, startIndex: number = 0): boolean {
    const playlist = this.playlists.get(playlistId);
    if (!playlist || playlist.tracks.length === 0) return false;

    // Stop if already playing
    this.stopPlaylist(playlistId);

    // Initialize state
    const state: PlaylistState = {
      playlistId,
      isPlaying: true,
      isPaused: false,
      currentTrackIndex: -1,
      currentVoiceId: null,
      playHistory: [],
      shuffleQueue: this.createShuffleQueue(playlist),
      startTime: performance.now(),
      pauseTime: null,
    };

    this.states.set(playlistId, state);

    // Start from specified index or first valid track
    const firstIndex = startIndex >= 0 && startIndex < playlist.tracks.length
      ? startIndex
      : this.getNextTrackIndex(playlist, state);

    if (firstIndex !== -1) {
      this.playTrack(playlist, state, firstIndex);
    }

    return true;
  }

  /**
   * Stop a playlist
   */
  stopPlaylist(playlistId: string, fadeMs?: number): void {
    const state = this.states.get(playlistId);
    if (!state) return;

    // Clear pending timers
    const timer = this.pendingTimers.get(playlistId);
    if (timer) {
      clearTimeout(timer);
      this.pendingTimers.delete(playlistId);
    }

    // Stop current track
    if (state.currentVoiceId) {
      this.stopCallback(state.currentVoiceId, fadeMs);
    }

    state.isPlaying = false;
    state.currentVoiceId = null;
  }

  /**
   * Pause playlist
   */
  pausePlaylist(playlistId: string): void {
    const state = this.states.get(playlistId);
    if (!state || !state.isPlaying || state.isPaused) return;

    state.isPaused = true;
    state.pauseTime = performance.now();

    // Would need actual pause capability on the voice
    // For now, just stop the timer
    const timer = this.pendingTimers.get(playlistId);
    if (timer) {
      clearTimeout(timer);
      this.pendingTimers.delete(playlistId);
    }
  }

  /**
   * Resume playlist
   */
  resumePlaylist(playlistId: string): void {
    const state = this.states.get(playlistId);
    if (!state || !state.isPaused) return;

    state.isPaused = false;
    state.pauseTime = null;

    // Resume from current track
    // Would need actual resume capability
  }

  /**
   * Skip to next track
   */
  nextTrack(playlistId: string): boolean {
    const playlist = this.playlists.get(playlistId);
    const state = this.states.get(playlistId);
    if (!playlist || !state || !state.isPlaying) return false;

    const crossfade = playlist.tracks[state.currentTrackIndex]?.crossfadeMs ??
                      playlist.defaultCrossfadeMs ?? 0;

    return this.advanceToNextTrack(playlist, state, crossfade);
  }

  /**
   * Skip to previous track
   */
  previousTrack(playlistId: string): boolean {
    const playlist = this.playlists.get(playlistId);
    const state = this.states.get(playlistId);
    if (!playlist || !state || !state.isPlaying) return false;

    // Go back in history
    if (state.playHistory.length > 1) {
      state.playHistory.pop(); // Remove current
      const prevTrackId = state.playHistory[state.playHistory.length - 1];
      const prevIndex = playlist.tracks.findIndex(t => t.id === prevTrackId);

      if (prevIndex !== -1) {
        state.playHistory.pop(); // Will be re-added by playTrack
        this.playTrack(playlist, state, prevIndex);
        return true;
      }
    }

    return false;
  }

  /**
   * Jump to specific track
   */
  jumpToTrack(playlistId: string, trackIndex: number): boolean {
    const playlist = this.playlists.get(playlistId);
    const state = this.states.get(playlistId);
    if (!playlist || !state) return false;

    if (trackIndex < 0 || trackIndex >= playlist.tracks.length) return false;

    if (!state.isPlaying) {
      this.startPlaylist(playlistId, trackIndex);
    } else {
      this.playTrack(playlist, state, trackIndex);
    }

    return true;
  }

  /**
   * Play a specific track
   */
  private playTrack(playlist: Playlist, state: PlaylistState, trackIndex: number): void {
    const track = playlist.tracks[trackIndex];
    if (!track || track.skip) return;

    // Stop current with crossfade
    const prevTrack = playlist.tracks[state.currentTrackIndex];
    const crossfadeMs = prevTrack?.crossfadeMs ?? playlist.defaultCrossfadeMs ?? 0;

    if (state.currentVoiceId) {
      this.stopCallback(state.currentVoiceId, crossfadeMs);

      // Notify track end
      if (prevTrack) {
        this.onTrackEnd?.(playlist, prevTrack, state.currentTrackIndex);
      }
    }

    // Update state
    state.currentTrackIndex = trackIndex;
    state.playHistory.push(track.id);

    // Calculate volume
    const volume = playlist.volume * (track.volume ?? 1);

    // Play new track
    const voiceId = this.playCallback(track.assetId, playlist.bus, volume);
    state.currentVoiceId = voiceId;

    // Notify track start
    this.onTrackStart?.(playlist, track, trackIndex);

    // Schedule next track
    // Note: Would need track duration from audio system
    // For now, assume caller handles track end notification
  }

  /**
   * Called when current track ends naturally
   */
  notifyTrackEnded(playlistId: string): void {
    const playlist = this.playlists.get(playlistId);
    const state = this.states.get(playlistId);
    if (!playlist || !state || !state.isPlaying) return;

    const currentTrack = playlist.tracks[state.currentTrackIndex];

    // Notify end
    if (currentTrack) {
      this.onTrackEnd?.(playlist, currentTrack, state.currentTrackIndex);
    }

    // Handle gap before next track
    const gapMs = currentTrack?.gapMs ?? playlist.defaultGapMs ?? 0;

    if (gapMs > 0) {
      const timer = window.setTimeout(() => {
        this.pendingTimers.delete(playlistId);
        this.advanceToNextTrack(playlist, state, 0);
      }, gapMs);
      this.pendingTimers.set(playlistId, timer);
    } else {
      this.advanceToNextTrack(playlist, state, 0);
    }
  }

  /**
   * Advance to next track based on mode
   */
  private advanceToNextTrack(playlist: Playlist, state: PlaylistState, _crossfadeMs: number): boolean {
    // Stop current
    if (state.currentVoiceId) {
      this.stopCallback(state.currentVoiceId, _crossfadeMs);
      state.currentVoiceId = null;
    }

    // Handle track loop mode
    if (playlist.loopMode === 'track') {
      this.playTrack(playlist, state, state.currentTrackIndex);
      return true;
    }

    // Get next track
    const nextIndex = this.getNextTrackIndex(playlist, state);

    if (nextIndex === -1) {
      // End of playlist
      state.isPlaying = false;
      this.onPlaylistEnd?.(playlist);

      // Handle playlist loop
      if (playlist.loopMode === 'playlist') {
        state.shuffleQueue = this.createShuffleQueue(playlist);
        const firstIndex = this.getNextTrackIndex(playlist, state);
        if (firstIndex !== -1) {
          state.isPlaying = true;
          this.playTrack(playlist, state, firstIndex);
          return true;
        }
      }

      return false;
    }

    this.playTrack(playlist, state, nextIndex);
    return true;
  }

  /**
   * Get next track index based on mode
   */
  private getNextTrackIndex(playlist: Playlist, state: PlaylistState): number {
    const validTracks = playlist.tracks
      .map((t, i) => ({ track: t, index: i }))
      .filter(({ track }) => !track.skip);

    if (validTracks.length === 0) return -1;

    switch (playlist.mode) {
      case 'sequential': {
        // Find next valid track after current
        for (let i = state.currentTrackIndex + 1; i < playlist.tracks.length; i++) {
          if (!playlist.tracks[i].skip) {
            return i;
          }
        }
        return -1; // End of playlist
      }

      case 'shuffle': {
        // Use shuffle queue
        while (state.shuffleQueue.length > 0) {
          const nextIndex = state.shuffleQueue.shift()!;
          if (!playlist.tracks[nextIndex].skip) {
            return nextIndex;
          }
        }
        return -1;
      }

      case 'random': {
        // True random with optional repeat avoidance
        const avoidCount = playlist.avoidRepeats ?? 0;
        const recentTracks = state.playHistory.slice(-avoidCount);
        const available = validTracks.filter(
          ({ track }) => !recentTracks.includes(track.id)
        );

        if (available.length === 0) {
          // Fall back to any valid track
          const randomIdx = Math.floor(this.rng() * validTracks.length);
          return validTracks[randomIdx].index;
        }

        const randomIdx = Math.floor(this.rng() * available.length);
        return available[randomIdx].index;
      }

      case 'weighted-random': {
        // Weighted random selection
        const avoidCount = playlist.avoidRepeats ?? 0;
        const recentTracks = state.playHistory.slice(-avoidCount);
        const available = validTracks.filter(
          ({ track }) => !recentTracks.includes(track.id)
        );

        if (available.length === 0) {
          return validTracks[Math.floor(this.rng() * validTracks.length)].index;
        }

        const totalWeight = available.reduce(
          (sum, { track }) => sum + (track.weight ?? 1),
          0
        );

        let random = this.rng() * totalWeight;
        for (const { track, index } of available) {
          random -= track.weight ?? 1;
          if (random <= 0) {
            return index;
          }
        }

        return available[0].index;
      }

      default:
        return -1;
    }
  }

  /**
   * Create shuffle queue
   */
  private createShuffleQueue(playlist: Playlist): number[] {
    const indices = playlist.tracks
      .map((_, i) => i)
      .filter(i => !playlist.tracks[i].skip);

    // Fisher-Yates shuffle
    for (let i = indices.length - 1; i > 0; i--) {
      const j = Math.floor(this.rng() * (i + 1));
      [indices[i], indices[j]] = [indices[j], indices[i]];
    }

    return indices;
  }

  /**
   * Get playlist state
   */
  getPlaylistState(playlistId: string): PlaylistState | null {
    return this.states.get(playlistId) ?? null;
  }

  /**
   * Get current track
   */
  getCurrentTrack(playlistId: string): PlaylistTrack | null {
    const playlist = this.playlists.get(playlistId);
    const state = this.states.get(playlistId);
    if (!playlist || !state || state.currentTrackIndex < 0) return null;

    return playlist.tracks[state.currentTrackIndex] ?? null;
  }

  /**
   * Set playlist volume
   */
  setPlaylistVolume(playlistId: string, volume: number): void {
    const playlist = this.playlists.get(playlistId);
    if (playlist) {
      playlist.volume = Math.max(0, Math.min(1, volume));
    }
  }

  /**
   * Set playlist mode
   */
  setPlaylistMode(playlistId: string, mode: PlaylistMode): void {
    const playlist = this.playlists.get(playlistId);
    const state = this.states.get(playlistId);

    if (playlist) {
      playlist.mode = mode;

      // Reset shuffle queue if switching to shuffle
      if (state && mode === 'shuffle') {
        state.shuffleQueue = this.createShuffleQueue(playlist);
      }
    }
  }

  /**
   * Set loop mode
   */
  setLoopMode(playlistId: string, loopMode: PlaylistLoopMode): void {
    const playlist = this.playlists.get(playlistId);
    if (playlist) {
      playlist.loopMode = loopMode;
    }
  }

  /**
   * Add track to playlist
   */
  addTrack(playlistId: string, track: PlaylistTrack, index?: number): boolean {
    const playlist = this.playlists.get(playlistId);
    if (!playlist) return false;

    if (index !== undefined && index >= 0 && index <= playlist.tracks.length) {
      playlist.tracks.splice(index, 0, track);
    } else {
      playlist.tracks.push(track);
    }

    return true;
  }

  /**
   * Remove track from playlist
   */
  removeTrack(playlistId: string, trackId: string): boolean {
    const playlist = this.playlists.get(playlistId);
    if (!playlist) return false;

    const index = playlist.tracks.findIndex(t => t.id === trackId);
    if (index === -1) return false;

    playlist.tracks.splice(index, 1);
    return true;
  }

  /**
   * Get all playlists
   */
  getPlaylists(): Playlist[] {
    return Array.from(this.playlists.values());
  }

  /**
   * Get playlist by ID
   */
  getPlaylist(playlistId: string): Playlist | null {
    return this.playlists.get(playlistId) ?? null;
  }

  /**
   * Dispose manager
   */
  dispose(): void {
    // Stop all playlists
    this.states.forEach((_, playlistId) => {
      this.stopPlaylist(playlistId, 0);
    });

    // Clear timers
    this.pendingTimers.forEach(timer => clearTimeout(timer));
    this.pendingTimers.clear();

    this.playlists.clear();
    this.states.clear();
  }
}

// ============ DEFAULT PLAYLISTS ============

export const DEFAULT_PLAYLISTS: Playlist[] = [
  {
    id: 'base_music',
    name: 'Base Game Music',
    description: 'Background music for base game',
    tracks: [
      { id: 'base_1', assetId: 'music_base_1', name: 'Base Track 1', weight: 1 },
      { id: 'base_2', assetId: 'music_base_2', name: 'Base Track 2', weight: 1 },
      { id: 'base_3', assetId: 'music_base_3', name: 'Base Track 3', weight: 1 },
    ],
    mode: 'shuffle',
    loopMode: 'playlist',
    bus: 'music',
    volume: 0.8,
    defaultCrossfadeMs: 2000,
    avoidRepeats: 2,
  },
  {
    id: 'win_sounds',
    name: 'Win Celebration Sounds',
    description: 'Random win celebration variations',
    tracks: [
      { id: 'win_1', assetId: 'win_celebration_1', name: 'Win 1', weight: 3 },
      { id: 'win_2', assetId: 'win_celebration_2', name: 'Win 2', weight: 2 },
      { id: 'win_3', assetId: 'win_celebration_3', name: 'Win 3', weight: 1 },
    ],
    mode: 'weighted-random',
    loopMode: 'none',
    bus: 'sfx',
    volume: 1,
    avoidRepeats: 1,
  },
  {
    id: 'ambient_loops',
    name: 'Ambient Loops',
    description: 'Background ambient sounds',
    tracks: [
      { id: 'amb_1', assetId: 'ambient_1', name: 'Ambient 1', gapMs: 5000 },
      { id: 'amb_2', assetId: 'ambient_2', name: 'Ambient 2', gapMs: 8000 },
      { id: 'amb_3', assetId: 'ambient_3', name: 'Ambient 3', gapMs: 3000 },
    ],
    mode: 'random',
    loopMode: 'playlist',
    bus: 'ambience',
    volume: 0.5,
  },
];
