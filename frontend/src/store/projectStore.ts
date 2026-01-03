/**
 * ReelForge Project Store
 *
 * Global state management for the project using a simple
 * pub/sub pattern with immutable updates.
 *
 * @module store/projectStore
 */

// ============ Types ============

export interface TrackState {
  id: string;
  name: string;
  color: string;
  type: 'audio' | 'midi' | 'bus' | 'master';
  volume: number;
  pan: number;
  muted: boolean;
  solo: boolean;
  armed: boolean;
  clips: ClipState[];
  inserts: InsertState[];
  sends: SendState[];
  /** Output bus routing */
  outputBus?: 'master' | 'music' | 'sfx' | 'ambience' | 'voice';
}

export interface ClipState {
  id: string;
  trackId: string;
  name: string;
  startTime: number;
  /** Visual duration on timeline (can be trimmed) */
  duration: number;
  /** Offset into the source audio (for left-edge trim) */
  offset: number;
  /** Original source audio duration (buffer.duration) - immutable */
  sourceDuration: number;
  fadeIn: number;
  fadeOut: number;
  gain: number;
  audioFileId?: string;
  color?: string;
}

export interface InsertState {
  id: string;
  pluginId: string;
  enabled: boolean;
  params: Record<string, number>;
}

export interface SendState {
  id: string;
  targetId: string;
  level: number;
  preFader: boolean;
}

export interface MarkerState {
  id: string;
  time: number;
  name: string;
  color?: string;
  type: 'marker' | 'loop-start' | 'loop-end' | 'region-start' | 'region-end';
}

export interface TransportState {
  isPlaying: boolean;
  isRecording: boolean;
  currentTime: number;
  loopEnabled: boolean;
  loopStart: number;
  loopEnd: number;
  tempo: number;
  timeSignature: [number, number];
  metronomeEnabled: boolean;
}

export interface ProjectMetadata {
  id: string;
  name: string;
  createdAt: number;
  modifiedAt: number;
  version: string;
  sampleRate: number;
  bitDepth: number;
}

export interface ProjectState {
  metadata: ProjectMetadata;
  transport: TransportState;
  tracks: TrackState[];
  markers: MarkerState[];
  masterVolume: number;
  selectedTrackIds: string[];
  selectedClipIds: string[];
  zoom: number;
  scrollPosition: number;
}

export interface HistoryEntry {
  state: ProjectState;
  description: string;
  timestamp: number;
}

// ============ Default State ============

function createDefaultProject(): ProjectState {
  return {
    metadata: {
      id: `project_${Date.now()}`,
      name: 'Untitled Project',
      createdAt: Date.now(),
      modifiedAt: Date.now(),
      version: '1.0.0',
      sampleRate: 48000,
      bitDepth: 24,
    },
    transport: {
      isPlaying: false,
      isRecording: false,
      currentTime: 0,
      loopEnabled: false,
      loopStart: 0,
      loopEnd: 60,
      tempo: 120,
      timeSignature: [4, 4],
      metronomeEnabled: false,
    },
    tracks: [],
    markers: [],
    masterVolume: 0,
    selectedTrackIds: [],
    selectedClipIds: [],
    zoom: 1,
    scrollPosition: 0,
  };
}

// ============ Store Implementation ============

type Listener = () => void;
type Selector<T> = (state: ProjectState) => T;

class ProjectStore {
  private state: ProjectState;
  private listeners: Set<Listener> = new Set();
  private history: HistoryEntry[] = [];
  private historyIndex = -1;
  private maxHistorySize = 100;
  private batchDepth = 0;
  private pendingNotify = false;

  // Cached derived state for stable references
  private _allClipsCache: ClipState[] = [];
  private _allClipsCacheVersion = -1;
  private _stateVersion = 0;

  constructor() {
    this.state = createDefaultProject();
    this.pushHistory('Initial state');
  }

  // ============ State Access ============

  getState(): ProjectState {
    return this.state;
  }

  /**
   * Get all clips from all tracks with stable reference.
   * Only recomputes when state changes.
   */
  getAllClips(): ClipState[] {
    if (this._allClipsCacheVersion !== this._stateVersion) {
      this._allClipsCache = this.state.tracks.flatMap((t) => t.clips);
      this._allClipsCacheVersion = this._stateVersion;
    }
    return this._allClipsCache;
  }

  select<T>(selector: Selector<T>): T {
    return selector(this.state);
  }

  // ============ Subscriptions ============

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private notify(): void {
    if (this.batchDepth > 0) {
      this.pendingNotify = true;
      return;
    }

    for (const listener of this.listeners) {
      listener();
    }
  }

  // ============ Batching ============

  batch(fn: () => void): void {
    this.batchDepth++;
    try {
      fn();
    } finally {
      this.batchDepth--;
      if (this.batchDepth === 0 && this.pendingNotify) {
        this.pendingNotify = false;
        this.notify();
      }
    }
  }

  // ============ State Updates ============

  private setState(
    updater: (state: ProjectState) => ProjectState,
    description?: string
  ): void {
    const prevState = this.state;
    this.state = updater(prevState);
    this.state.metadata.modifiedAt = Date.now();
    this._stateVersion++;

    if (description) {
      this.pushHistory(description);
    }

    this.notify();
  }

  // ============ History (Undo/Redo) ============

  private pushHistory(description: string): void {
    // Remove any redo entries
    if (this.historyIndex < this.history.length - 1) {
      this.history = this.history.slice(0, this.historyIndex + 1);
    }

    // Add new entry
    this.history.push({
      state: JSON.parse(JSON.stringify(this.state)),
      description,
      timestamp: Date.now(),
    });

    // Trim if too long
    if (this.history.length > this.maxHistorySize) {
      this.history.shift();
    } else {
      this.historyIndex++;
    }
  }

  canUndo(): boolean {
    return this.historyIndex > 0;
  }

  canRedo(): boolean {
    return this.historyIndex < this.history.length - 1;
  }

  undo(): void {
    if (!this.canUndo()) return;

    this.historyIndex--;
    this.state = JSON.parse(
      JSON.stringify(this.history[this.historyIndex].state)
    );
    this._stateVersion++;
    this.notify();
  }

  redo(): void {
    if (!this.canRedo()) return;

    this.historyIndex++;
    this.state = JSON.parse(
      JSON.stringify(this.history[this.historyIndex].state)
    );
    this._stateVersion++;
    this.notify();
  }

  getHistoryDescription(): string {
    return this.history[this.historyIndex]?.description || '';
  }

  // ============ Project Actions ============

  newProject(name?: string): void {
    this.state = createDefaultProject();
    if (name) {
      this.state.metadata.name = name;
    }
    this.history = [];
    this.historyIndex = -1;
    this._stateVersion++;
    this.pushHistory('New project');
    this.notify();
  }

  setProjectName(name: string): void {
    this.setState(
      (state) => ({
        ...state,
        metadata: { ...state.metadata, name },
      }),
      `Rename project to "${name}"`
    );
  }

  // ============ Transport Actions ============

  setPlaying(isPlaying: boolean): void {
    this.setState((state) => ({
      ...state,
      transport: { ...state.transport, isPlaying },
    }));
  }

  setRecording(isRecording: boolean): void {
    this.setState((state) => ({
      ...state,
      transport: { ...state.transport, isRecording },
    }));
  }

  setCurrentTime(currentTime: number): void {
    this.setState((state) => ({
      ...state,
      transport: { ...state.transport, currentTime },
    }));
  }

  setTempo(tempo: number): void {
    this.setState(
      (state) => ({
        ...state,
        transport: { ...state.transport, tempo },
      }),
      `Set tempo to ${tempo} BPM`
    );
  }

  setLoop(enabled: boolean, start?: number, end?: number): void {
    this.setState(
      (state) => ({
        ...state,
        transport: {
          ...state.transport,
          loopEnabled: enabled,
          loopStart: start ?? state.transport.loopStart,
          loopEnd: end ?? state.transport.loopEnd,
        },
      }),
      enabled ? 'Enable loop' : 'Disable loop'
    );
  }

  setMetronome(enabled: boolean): void {
    this.setState((state) => ({
      ...state,
      transport: { ...state.transport, metronomeEnabled: enabled },
    }));
  }

  // ============ Track Actions ============

  addTrack(track: Omit<TrackState, 'clips' | 'inserts' | 'sends'>): void {
    this.setState(
      (state) => ({
        ...state,
        tracks: [
          ...state.tracks,
          {
            ...track,
            clips: [],
            inserts: [],
            sends: [],
          },
        ],
      }),
      `Add track "${track.name}"`
    );
  }

  removeTrack(trackId: string): void {
    const track = this.state.tracks.find((t) => t.id === trackId);
    this.setState(
      (state) => ({
        ...state,
        tracks: state.tracks.filter((t) => t.id !== trackId),
        selectedTrackIds: state.selectedTrackIds.filter((id) => id !== trackId),
      }),
      `Remove track "${track?.name || trackId}"`
    );
  }

  updateTrack(trackId: string, updates: Partial<TrackState>): void {
    this.setState(
      (state) => ({
        ...state,
        tracks: state.tracks.map((t) =>
          t.id === trackId ? { ...t, ...updates } : t
        ),
      }),
      `Update track`
    );
  }

  setTrackVolume(trackId: string, volume: number): void {
    this.setState((state) => ({
      ...state,
      tracks: state.tracks.map((t) =>
        t.id === trackId ? { ...t, volume } : t
      ),
    }));
  }

  setTrackPan(trackId: string, pan: number): void {
    this.setState((state) => ({
      ...state,
      tracks: state.tracks.map((t) =>
        t.id === trackId ? { ...t, pan } : t
      ),
    }));
  }

  setTrackMute(trackId: string, muted: boolean): void {
    this.setState((state) => ({
      ...state,
      tracks: state.tracks.map((t) =>
        t.id === trackId ? { ...t, muted } : t
      ),
    }));
  }

  setTrackSolo(trackId: string, solo: boolean): void {
    this.setState((state) => ({
      ...state,
      tracks: state.tracks.map((t) =>
        t.id === trackId ? { ...t, solo } : t
      ),
    }));
  }

  setTrackArmed(trackId: string, armed: boolean): void {
    this.setState((state) => ({
      ...state,
      tracks: state.tracks.map((t) =>
        t.id === trackId ? { ...t, armed } : t
      ),
    }));
  }

  // ============ Clip Actions ============

  addClip(trackId: string, clip: ClipState): void {
    this.setState(
      (state) => ({
        ...state,
        tracks: state.tracks.map((t) =>
          t.id === trackId
            ? { ...t, clips: [...t.clips, clip] }
            : t
        ),
      }),
      `Add clip "${clip.name}"`
    );
  }

  removeClip(trackId: string, clipId: string): void {
    this.setState(
      (state) => ({
        ...state,
        tracks: state.tracks.map((t) =>
          t.id === trackId
            ? { ...t, clips: t.clips.filter((c) => c.id !== clipId) }
            : t
        ),
        selectedClipIds: state.selectedClipIds.filter((id) => id !== clipId),
      }),
      `Remove clip`
    );
  }

  updateClip(
    trackId: string,
    clipId: string,
    updates: Partial<ClipState>
  ): void {
    this.setState(
      (state) => ({
        ...state,
        tracks: state.tracks.map((t) =>
          t.id === trackId
            ? {
                ...t,
                clips: t.clips.map((c) =>
                  c.id === clipId ? { ...c, ...updates } : c
                ),
              }
            : t
        ),
      }),
      `Update clip`
    );
  }

  moveClip(
    fromTrackId: string,
    clipId: string,
    toTrackId: string,
    newStartTime: number
  ): void {
    const clip = this.state.tracks
      .find((t) => t.id === fromTrackId)
      ?.clips.find((c) => c.id === clipId);

    if (!clip) return;

    this.batch(() => {
      this.removeClip(fromTrackId, clipId);
      this.addClip(toTrackId, {
        ...clip,
        trackId: toTrackId,
        startTime: newStartTime,
      });
    });
  }

  // ============ Marker Actions ============

  addMarker(marker: MarkerState): void {
    this.setState(
      (state) => ({
        ...state,
        markers: [...state.markers, marker].sort((a, b) => a.time - b.time),
      }),
      `Add marker "${marker.name}"`
    );
  }

  removeMarker(markerId: string): void {
    this.setState(
      (state) => ({
        ...state,
        markers: state.markers.filter((m) => m.id !== markerId),
      }),
      `Remove marker`
    );
  }

  updateMarker(markerId: string, updates: Partial<MarkerState>): void {
    this.setState(
      (state) => ({
        ...state,
        markers: state.markers
          .map((m) => (m.id === markerId ? { ...m, ...updates } : m))
          .sort((a, b) => a.time - b.time),
      }),
      `Update marker`
    );
  }

  // ============ Selection Actions ============

  selectTrack(trackId: string, additive = false): void {
    this.setState((state) => ({
      ...state,
      selectedTrackIds: additive
        ? state.selectedTrackIds.includes(trackId)
          ? state.selectedTrackIds.filter((id) => id !== trackId)
          : [...state.selectedTrackIds, trackId]
        : [trackId],
    }));
  }

  selectClip(clipId: string, additive = false): void {
    this.setState((state) => ({
      ...state,
      selectedClipIds: additive
        ? state.selectedClipIds.includes(clipId)
          ? state.selectedClipIds.filter((id) => id !== clipId)
          : [...state.selectedClipIds, clipId]
        : [clipId],
    }));
  }

  clearSelection(): void {
    this.setState((state) => ({
      ...state,
      selectedTrackIds: [],
      selectedClipIds: [],
    }));
  }

  // ============ View Actions ============

  setZoom(zoom: number): void {
    this.setState((state) => ({
      ...state,
      zoom: Math.max(0.1, Math.min(10, zoom)),
    }));
  }

  setScrollPosition(position: number): void {
    this.setState((state) => ({
      ...state,
      scrollPosition: Math.max(0, position),
    }));
  }

  setMasterVolume(volume: number): void {
    this.setState((state) => ({
      ...state,
      masterVolume: volume,
    }));
  }

  // ============ Serialization ============

  toJSON(): string {
    return JSON.stringify(this.state, null, 2);
  }

  fromJSON(json: string): void {
    try {
      const parsed = JSON.parse(json);
      this.state = parsed;
      this.history = [];
      this.historyIndex = -1;
      this.pushHistory('Load project');
      this.notify();
    } catch (error) {
      console.error('Failed to parse project JSON:', error);
    }
  }
}

// ============ Singleton ============

let storeInstance: ProjectStore | null = null;

export function getProjectStore(): ProjectStore {
  if (!storeInstance) {
    storeInstance = new ProjectStore();
  }
  return storeInstance;
}

export default ProjectStore;
