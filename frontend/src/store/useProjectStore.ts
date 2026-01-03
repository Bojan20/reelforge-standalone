/**
 * ReelForge Project Store React Hook
 *
 * React bindings for the project store with
 * optimized re-renders via selectors.
 *
 * @module store/useProjectStore
 */

import { useSyncExternalStore, useCallback, useMemo, useRef } from 'react';
import {
  getProjectStore,
  type ProjectState,
  type TrackState,
  type ClipState,
  type MarkerState,
} from './projectStore';

// ============ Stable Selectors ============
// Pre-defined selectors to avoid inline function instability

const selectTracks = (s: ProjectState) => s.tracks;
const selectSelectedTrackIds = (s: ProjectState) => s.selectedTrackIds;
const selectSelectedClipIds = (s: ProjectState) => s.selectedClipIds;
const selectMarkers = (s: ProjectState) => s.markers;
const selectTransport = (s: ProjectState) => s.transport;
const selectMetadata = (s: ProjectState) => s.metadata;
const selectMasterVolume = (s: ProjectState) => s.masterVolume;
const selectZoom = (s: ProjectState) => s.zoom;
const selectScrollPosition = (s: ProjectState) => s.scrollPosition;

// ============ Main Hook ============

/**
 * Subscribe to the entire project state.
 * Use selectors for better performance.
 */
export function useProjectStore(): ProjectState {
  const store = getProjectStore();

  return useSyncExternalStore(
    store.subscribe.bind(store),
    store.getState.bind(store),
    store.getState.bind(store)
  );
}

/**
 * Subscribe to a selected part of the state.
 * IMPORTANT: Pass a stable selector reference (not an inline function)
 * to avoid infinite re-render loops.
 */
export function useProjectSelector<T>(selector: (state: ProjectState) => T): T {
  const store = getProjectStore();

  // Use ref to stabilize the selector
  const selectorRef = useRef(selector);
  selectorRef.current = selector;

  const getSnapshot = useCallback(
    () => selectorRef.current(store.getState()),
    [store]
  );

  return useSyncExternalStore(
    store.subscribe.bind(store),
    getSnapshot,
    getSnapshot
  );
}

// ============ Specialized Hooks ============

/**
 * Transport state and controls.
 */
export function useTransport() {
  const store = getProjectStore();
  const transport = useProjectSelector(selectTransport);

  const actions = useMemo(
    () => ({
      play: () => store.setPlaying(true),
      pause: () => store.setPlaying(false),
      stop: () => {
        store.setPlaying(false);
        store.setCurrentTime(0);
      },
      togglePlay: () => store.setPlaying(!store.getState().transport.isPlaying),
      record: () => store.setRecording(true),
      stopRecording: () => store.setRecording(false),
      seek: (time: number) => store.setCurrentTime(time),
      setTempo: (tempo: number) => store.setTempo(tempo),
      setLoop: (enabled: boolean, start?: number, end?: number) =>
        store.setLoop(enabled, start, end),
      toggleMetronome: () =>
        store.setMetronome(!store.getState().transport.metronomeEnabled),
    }),
    [store]
  );

  return { ...transport, ...actions };
}

/**
 * Track list and actions.
 */
export function useTracks() {
  const store = getProjectStore();
  const tracks = useProjectSelector(selectTracks);
  const selectedTrackIds = useProjectSelector(selectSelectedTrackIds);

  const actions = useMemo(
    () => ({
      addTrack: (
        track: Omit<TrackState, 'clips' | 'inserts' | 'sends'>
      ) => store.addTrack(track),
      removeTrack: (id: string) => store.removeTrack(id),
      updateTrack: (id: string, updates: Partial<TrackState>) =>
        store.updateTrack(id, updates),
      setVolume: (id: string, volume: number) => store.setTrackVolume(id, volume),
      setPan: (id: string, pan: number) => store.setTrackPan(id, pan),
      setMute: (id: string, muted: boolean) => store.setTrackMute(id, muted),
      setSolo: (id: string, solo: boolean) => store.setTrackSolo(id, solo),
      setArmed: (id: string, armed: boolean) => store.setTrackArmed(id, armed),
      select: (id: string, additive?: boolean) => store.selectTrack(id, additive),
    }),
    [store]
  );

  return { tracks, selectedTrackIds, ...actions };
}

/**
 * Single track with full data.
 */
export function useTrack(trackId: string) {
  const store = getProjectStore();
  const track = useProjectSelector((s) =>
    s.tracks.find((t) => t.id === trackId)
  );
  const isSelected = useProjectSelector((s) =>
    s.selectedTrackIds.includes(trackId)
  );

  const actions = useMemo(
    () => ({
      setVolume: (volume: number) => store.setTrackVolume(trackId, volume),
      setPan: (pan: number) => store.setTrackPan(trackId, pan),
      setMute: (muted: boolean) => store.setTrackMute(trackId, muted),
      setSolo: (solo: boolean) => store.setTrackSolo(trackId, solo),
      setArmed: (armed: boolean) => store.setTrackArmed(trackId, armed),
      update: (updates: Partial<TrackState>) =>
        store.updateTrack(trackId, updates),
      remove: () => store.removeTrack(trackId),
      select: (additive?: boolean) => store.selectTrack(trackId, additive),
      addClip: (clip: ClipState) => store.addClip(trackId, clip),
    }),
    [store, trackId]
  );

  return { track, isSelected, ...actions };
}

/**
 * Clips management.
 */
export function useClips(trackId?: string) {
  const store = getProjectStore();

  // Use cached allClips for stable reference
  const allClips = useSyncExternalStore(
    store.subscribe.bind(store),
    () => store.getAllClips(),
    () => store.getAllClips()
  );

  // Filter by trackId if provided (memo'd to avoid unnecessary recalcs)
  const clips = useMemo(
    () => (trackId ? allClips.filter((c) => c.trackId === trackId) : allClips),
    [allClips, trackId]
  );

  const selectedClipIds = useProjectSelector(selectSelectedClipIds);

  const actions = useMemo(
    () => ({
      addClip: (tid: string, clip: ClipState) => store.addClip(tid, clip),
      removeClip: (tid: string, clipId: string) => store.removeClip(tid, clipId),
      updateClip: (tid: string, clipId: string, updates: Partial<ClipState>) =>
        store.updateClip(tid, clipId, updates),
      moveClip: (
        fromTrackId: string,
        clipId: string,
        toTrackId: string,
        newStartTime: number
      ) => store.moveClip(fromTrackId, clipId, toTrackId, newStartTime),
      selectClip: (clipId: string, additive?: boolean) =>
        store.selectClip(clipId, additive),
    }),
    [store]
  );

  return { clips, selectedClipIds, ...actions };
}

/**
 * Markers management.
 */
export function useMarkers() {
  const store = getProjectStore();
  const markers = useProjectSelector(selectMarkers);

  const actions = useMemo(
    () => ({
      addMarker: (marker: MarkerState) => store.addMarker(marker),
      removeMarker: (id: string) => store.removeMarker(id),
      updateMarker: (id: string, updates: Partial<MarkerState>) =>
        store.updateMarker(id, updates),
    }),
    [store]
  );

  return { markers, ...actions };
}

/**
 * Undo/Redo functionality.
 */
export function useHistory() {
  const store = getProjectStore();

  // Force re-render on history change
  const state = useProjectStore();

  return useMemo(
    () => ({
      canUndo: store.canUndo(),
      canRedo: store.canRedo(),
      undo: () => store.undo(),
      redo: () => store.redo(),
      description: store.getHistoryDescription(),
    }),
    [store, state] // eslint-disable-line react-hooks/exhaustive-deps
  );
}

/**
 * Project metadata and actions.
 */
export function useProject() {
  const store = getProjectStore();
  const metadata = useProjectSelector(selectMetadata);
  const masterVolume = useProjectSelector(selectMasterVolume);

  const actions = useMemo(
    () => ({
      newProject: (name?: string) => store.newProject(name),
      setName: (name: string) => store.setProjectName(name),
      setMasterVolume: (volume: number) => store.setMasterVolume(volume),
      save: () => store.toJSON(),
      load: (json: string) => store.fromJSON(json),
    }),
    [store]
  );

  return { metadata, masterVolume, ...actions };
}

/**
 * View state (zoom, scroll).
 */
export function useView() {
  const store = getProjectStore();
  const zoom = useProjectSelector(selectZoom);
  const scrollPosition = useProjectSelector(selectScrollPosition);

  const actions = useMemo(
    () => ({
      setZoom: (z: number) => store.setZoom(z),
      zoomIn: () => store.setZoom(store.getState().zoom * 1.2),
      zoomOut: () => store.setZoom(store.getState().zoom / 1.2),
      setScrollPosition: (pos: number) => store.setScrollPosition(pos),
    }),
    [store]
  );

  return { zoom, scrollPosition, ...actions };
}

/**
 * Selection state and actions.
 */
export function useSelection() {
  const store = getProjectStore();
  const selectedTrackIds = useProjectSelector(selectSelectedTrackIds);
  const selectedClipIds = useProjectSelector(selectSelectedClipIds);

  const actions = useMemo(
    () => ({
      selectTrack: (id: string, additive?: boolean) =>
        store.selectTrack(id, additive),
      selectClip: (id: string, additive?: boolean) =>
        store.selectClip(id, additive),
      clearSelection: () => store.clearSelection(),
    }),
    [store]
  );

  return { selectedTrackIds, selectedClipIds, ...actions };
}

export default useProjectStore;
