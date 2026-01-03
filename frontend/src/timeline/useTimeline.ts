/**
 * ReelForge Timeline State Hook
 *
 * React hook for managing timeline state with optimized updates.
 *
 * @module timeline/useTimeline
 */

import { useState, useCallback, useMemo, useRef, useEffect } from 'react';
import {
  type TimelineState,
  type Track,
  type Clip,
  type Marker,
  type TimeRange,
  type Seconds,
  type TimelineAction,
  DEFAULT_TIMELINE_STATE,
  DEFAULT_TRACK,
  quantizeToGrid,
} from './types';

// ============ Types ============

export interface UseTimelineOptions {
  /** Initial timeline state */
  initialState?: Partial<TimelineState>;
  /** Initial tracks */
  initialTracks?: Track[];
  /** Initial markers */
  initialMarkers?: Marker[];
  /** Callback when state changes */
  onChange?: (state: TimelineState, tracks: Track[], markers: Marker[]) => void;
}

export interface UseTimelineReturn {
  // State
  state: TimelineState;
  tracks: Track[];
  markers: Marker[];

  // Playhead
  setPlayhead: (position: Seconds) => void;
  movePlayhead: (delta: Seconds) => void;

  // Zoom & Scroll
  setZoom: (pixelsPerSecond: number) => void;
  zoomIn: () => void;
  zoomOut: () => void;
  zoomToFit: () => void;
  setVisibleRange: (start: Seconds, end: Seconds) => void;
  scrollTo: (position: Seconds) => void;

  // Selection
  setSelection: (selection: TimeRange | null) => void;
  selectAll: () => void;
  clearSelection: () => void;

  // Loop
  setLoop: (enabled: boolean, start?: Seconds, end?: Seconds) => void;
  setLoopFromSelection: () => void;

  // Grid & Snap
  setSnapEnabled: (enabled: boolean) => void;
  setGridDivision: (division: number) => void;
  snapToGrid: (time: Seconds) => Seconds;

  // Tracks
  addTrack: (track: Partial<Track>) => Track;
  removeTrack: (trackId: string) => void;
  updateTrack: (trackId: string, updates: Partial<Track>) => void;
  reorderTracks: (trackIds: string[]) => void;
  getTrack: (trackId: string) => Track | undefined;
  muteTrack: (trackId: string, muted: boolean) => void;
  soloTrack: (trackId: string, solo: boolean) => void;

  // Clips
  addClip: (trackId: string, clip: Partial<Clip>) => Clip;
  removeClip: (trackId: string, clipId: string) => void;
  updateClip: (trackId: string, clipId: string, updates: Partial<Clip>) => void;
  moveClip: (trackId: string, clipId: string, newStart: Seconds, newTrackId?: string) => void;
  splitClip: (trackId: string, clipId: string, splitPoint: Seconds) => void;
  getClip: (trackId: string, clipId: string) => Clip | undefined;
  getClipsAtPosition: (position: Seconds) => Array<{ track: Track; clip: Clip }>;

  // Markers
  addMarker: (marker: Partial<Marker>) => Marker;
  removeMarker: (markerId: string) => void;
  updateMarker: (markerId: string, updates: Partial<Marker>) => void;
  getMarker: (markerId: string) => Marker | undefined;

  // Utilities
  timeToPixels: (time: Seconds) => number;
  pixelsToTime: (pixels: number) => Seconds;
  dispatch: (action: TimelineAction) => void;
}

// ============ ID Generator ============

let idCounter = 0;
function generateId(prefix: string): string {
  return `${prefix}_${Date.now()}_${++idCounter}`;
}

// ============ Hook ============

export function useTimeline(options: UseTimelineOptions = {}): UseTimelineReturn {
  const { initialState, initialTracks = [], initialMarkers = [], onChange } = options;

  // State
  const [state, setState] = useState<TimelineState>({
    ...DEFAULT_TIMELINE_STATE,
    ...initialState,
  });

  const [tracks, setTracks] = useState<Track[]>(initialTracks);
  const [markers, setMarkers] = useState<Marker[]>(initialMarkers);

  // Refs for stable callbacks
  const stateRef = useRef(state);
  const tracksRef = useRef(tracks);
  const markersRef = useRef(markers);

  stateRef.current = state;
  tracksRef.current = tracks;
  markersRef.current = markers;

  // Notify on change
  useEffect(() => {
    onChange?.(state, tracks, markers);
  }, [state, tracks, markers, onChange]);

  // ============ Playhead ============

  const setPlayhead = useCallback((position: Seconds) => {
    setState((s) => ({
      ...s,
      playheadPosition: Math.max(0, position),
    }));
  }, []);

  const movePlayhead = useCallback((delta: Seconds) => {
    setState((s) => ({
      ...s,
      playheadPosition: Math.max(0, s.playheadPosition + delta),
    }));
  }, []);

  // ============ Zoom & Scroll ============

  const setZoom = useCallback((pixelsPerSecond: number) => {
    setState((s) => {
      const clamped = Math.max(5, Math.min(1000, pixelsPerSecond));
      // Maintain center point when zooming
      const center = (s.visibleStart + s.visibleEnd) / 2;
      const newDuration = (s.visibleEnd - s.visibleStart) * (s.pixelsPerSecond / clamped);
      return {
        ...s,
        pixelsPerSecond: clamped,
        visibleStart: Math.max(0, center - newDuration / 2),
        visibleEnd: center + newDuration / 2,
      };
    });
  }, []);

  const zoomIn = useCallback(() => {
    setState((s) => {
      const newPPS = Math.min(1000, s.pixelsPerSecond * 1.5);
      const center = (s.visibleStart + s.visibleEnd) / 2;
      const newDuration = (s.visibleEnd - s.visibleStart) * (s.pixelsPerSecond / newPPS);
      return {
        ...s,
        pixelsPerSecond: newPPS,
        visibleStart: Math.max(0, center - newDuration / 2),
        visibleEnd: center + newDuration / 2,
      };
    });
  }, []);

  const zoomOut = useCallback(() => {
    setState((s) => {
      const newPPS = Math.max(5, s.pixelsPerSecond / 1.5);
      const center = (s.visibleStart + s.visibleEnd) / 2;
      const newDuration = (s.visibleEnd - s.visibleStart) * (s.pixelsPerSecond / newPPS);
      return {
        ...s,
        pixelsPerSecond: newPPS,
        visibleStart: Math.max(0, center - newDuration / 2),
        visibleEnd: center + newDuration / 2,
      };
    });
  }, []);

  const zoomToFit = useCallback(() => {
    const allClips = tracksRef.current.flatMap((t) => t.clips);
    if (allClips.length === 0) {
      setState((s) => ({
        ...s,
        visibleStart: 0,
        visibleEnd: 30,
        pixelsPerSecond: 50,
      }));
      return;
    }

    const minTime = Math.min(...allClips.map((c) => c.startTime));
    const maxTime = Math.max(...allClips.map((c) => c.startTime + c.duration));
    const padding = (maxTime - minTime) * 0.05;

    setState((s) => ({
      ...s,
      visibleStart: Math.max(0, minTime - padding),
      visibleEnd: maxTime + padding,
    }));
  }, []);

  const setVisibleRange = useCallback((start: Seconds, end: Seconds) => {
    setState((s) => ({
      ...s,
      visibleStart: Math.max(0, start),
      visibleEnd: end,
    }));
  }, []);

  const scrollTo = useCallback((position: Seconds) => {
    setState((s) => {
      const duration = s.visibleEnd - s.visibleStart;
      return {
        ...s,
        visibleStart: Math.max(0, position - duration / 2),
        visibleEnd: position + duration / 2,
      };
    });
  }, []);

  // ============ Selection ============

  const setSelection = useCallback((selection: TimeRange | null) => {
    setState((s) => ({ ...s, selection }));
  }, []);

  const selectAll = useCallback(() => {
    const allClips = tracksRef.current.flatMap((t) => t.clips);
    if (allClips.length === 0) return;

    const minTime = Math.min(...allClips.map((c) => c.startTime));
    const maxTime = Math.max(...allClips.map((c) => c.startTime + c.duration));

    setState((s) => ({
      ...s,
      selection: { start: minTime, end: maxTime },
    }));
  }, []);

  const clearSelection = useCallback(() => {
    setState((s) => ({ ...s, selection: null }));
  }, []);

  // ============ Loop ============

  const setLoop = useCallback((enabled: boolean, start?: Seconds, end?: Seconds) => {
    setState((s) => ({
      ...s,
      loopEnabled: enabled,
      loopStart: start ?? s.loopStart,
      loopEnd: end ?? s.loopEnd,
    }));
  }, []);

  const setLoopFromSelection = useCallback(() => {
    const sel = stateRef.current.selection;
    if (sel) {
      setState((s) => ({
        ...s,
        loopEnabled: true,
        loopStart: sel.start,
        loopEnd: sel.end,
      }));
    }
  }, []);

  // ============ Grid & Snap ============

  const setSnapEnabled = useCallback((enabled: boolean) => {
    setState((s) => ({ ...s, snapEnabled: enabled }));
  }, []);

  const setGridDivision = useCallback((division: number) => {
    setState((s) => ({ ...s, gridDivision: division }));
  }, []);

  const snapToGrid = useCallback((time: Seconds): Seconds => {
    const s = stateRef.current;
    if (!s.snapEnabled) return time;
    return quantizeToGrid(time, s.gridDivision, s.bpm);
  }, []);

  // ============ Tracks ============

  const addTrack = useCallback((partial: Partial<Track>): Track => {
    const track: Track = {
      ...DEFAULT_TRACK,
      id: generateId('track'),
      name: partial.name || `Track ${tracksRef.current.length + 1}`,
      order: tracksRef.current.length,
      ...partial,
    };
    setTracks((prev) => [...prev, track]);
    return track;
  }, []);

  const removeTrack = useCallback((trackId: string) => {
    setTracks((prev) => prev.filter((t) => t.id !== trackId));
  }, []);

  const updateTrack = useCallback((trackId: string, updates: Partial<Track>) => {
    setTracks((prev) =>
      prev.map((t) => (t.id === trackId ? { ...t, ...updates } : t))
    );
  }, []);

  const reorderTracks = useCallback((trackIds: string[]) => {
    setTracks((prev) => {
      const trackMap = new Map(prev.map((t) => [t.id, t]));
      return trackIds
        .map((id, index) => {
          const track = trackMap.get(id);
          return track ? { ...track, order: index } : null;
        })
        .filter(Boolean) as Track[];
    });
  }, []);

  const getTrack = useCallback((trackId: string): Track | undefined => {
    return tracksRef.current.find((t) => t.id === trackId);
  }, []);

  const muteTrack = useCallback((trackId: string, muted: boolean) => {
    updateTrack(trackId, { muted });
  }, [updateTrack]);

  const soloTrack = useCallback((trackId: string, solo: boolean) => {
    updateTrack(trackId, { solo });
  }, [updateTrack]);

  // ============ Clips ============

  const addClip = useCallback((trackId: string, partial: Partial<Clip>): Clip => {
    const clip: Clip = {
      id: generateId('clip'),
      type: 'audio',
      name: partial.name || 'Clip',
      startTime: 0,
      duration: 5,
      sourceOffset: 0,
      color: null,
      gain: 1,
      muted: false,
      selected: false,
      locked: false,
      fadeIn: 0,
      fadeOut: 0,
      fadeInCurve: 'linear',
      fadeOutCurve: 'linear',
      ...partial,
    };

    setTracks((prev) =>
      prev.map((t) =>
        t.id === trackId ? { ...t, clips: [...t.clips, clip] } : t
      )
    );

    return clip;
  }, []);

  const removeClip = useCallback((trackId: string, clipId: string) => {
    setTracks((prev) =>
      prev.map((t) =>
        t.id === trackId
          ? { ...t, clips: t.clips.filter((c) => c.id !== clipId) }
          : t
      )
    );
  }, []);

  const updateClip = useCallback(
    (trackId: string, clipId: string, updates: Partial<Clip>) => {
      setTracks((prev) =>
        prev.map((t) =>
          t.id === trackId
            ? {
                ...t,
                clips: t.clips.map((c) =>
                  c.id === clipId ? { ...c, ...updates } : c
                ),
              }
            : t
        )
      );
    },
    []
  );

  const moveClip = useCallback(
    (trackId: string, clipId: string, newStart: Seconds, newTrackId?: string) => {
      const snappedStart = snapToGrid(newStart);

      if (newTrackId && newTrackId !== trackId) {
        // Move to different track
        setTracks((prev) => {
          const sourceTrack = prev.find((t) => t.id === trackId);
          const clip = sourceTrack?.clips.find((c) => c.id === clipId);
          if (!clip) return prev;

          const movedClip = { ...clip, startTime: snappedStart };

          return prev.map((t) => {
            if (t.id === trackId) {
              return { ...t, clips: t.clips.filter((c) => c.id !== clipId) };
            }
            if (t.id === newTrackId) {
              return { ...t, clips: [...t.clips, movedClip] };
            }
            return t;
          });
        });
      } else {
        // Move within same track
        updateClip(trackId, clipId, { startTime: snappedStart });
      }
    },
    [snapToGrid, updateClip]
  );

  const splitClip = useCallback(
    (trackId: string, clipId: string, splitPoint: Seconds) => {
      setTracks((prev) =>
        prev.map((t) => {
          if (t.id !== trackId) return t;

          const clip = t.clips.find((c) => c.id === clipId);
          if (!clip) return t;

          // Check split point is within clip
          if (
            splitPoint <= clip.startTime ||
            splitPoint >= clip.startTime + clip.duration
          ) {
            return t;
          }

          const firstDuration = splitPoint - clip.startTime;
          const secondDuration = clip.duration - firstDuration;

          const firstClip: Clip = {
            ...clip,
            duration: firstDuration,
            fadeOut: 0,
          };

          const secondClip: Clip = {
            ...clip,
            id: generateId('clip'),
            name: `${clip.name} (2)`,
            startTime: splitPoint,
            duration: secondDuration,
            sourceOffset: clip.sourceOffset + firstDuration,
            fadeIn: 0,
          };

          return {
            ...t,
            clips: [
              ...t.clips.filter((c) => c.id !== clipId),
              firstClip,
              secondClip,
            ],
          };
        })
      );
    },
    []
  );

  const getClip = useCallback(
    (trackId: string, clipId: string): Clip | undefined => {
      const track = tracksRef.current.find((t) => t.id === trackId);
      return track?.clips.find((c) => c.id === clipId);
    },
    []
  );

  const getClipsAtPosition = useCallback(
    (position: Seconds): Array<{ track: Track; clip: Clip }> => {
      const result: Array<{ track: Track; clip: Clip }> = [];

      for (const track of tracksRef.current) {
        for (const clip of track.clips) {
          if (
            position >= clip.startTime &&
            position < clip.startTime + clip.duration
          ) {
            result.push({ track, clip });
          }
        }
      }

      return result;
    },
    []
  );

  // ============ Markers ============

  const addMarker = useCallback((partial: Partial<Marker>): Marker => {
    const marker: Marker = {
      id: generateId('marker'),
      type: 'marker',
      name: partial.name || 'Marker',
      position: 0,
      color: '#ffaa00',
      ...partial,
    };
    setMarkers((prev) => [...prev, marker]);
    return marker;
  }, []);

  const removeMarker = useCallback((markerId: string) => {
    setMarkers((prev) => prev.filter((m) => m.id !== markerId));
  }, []);

  const updateMarker = useCallback((markerId: string, updates: Partial<Marker>) => {
    setMarkers((prev) =>
      prev.map((m) => (m.id === markerId ? { ...m, ...updates } : m))
    );
  }, []);

  const getMarker = useCallback((markerId: string): Marker | undefined => {
    return markersRef.current.find((m) => m.id === markerId);
  }, []);

  // ============ Utilities ============

  const timeToPixels = useCallback(
    (time: Seconds): number => {
      return (time - stateRef.current.visibleStart) * stateRef.current.pixelsPerSecond;
    },
    []
  );

  const pixelsToTime = useCallback(
    (pixels: number): Seconds => {
      return pixels / stateRef.current.pixelsPerSecond + stateRef.current.visibleStart;
    },
    []
  );

  // ============ Dispatch (for complex actions) ============

  const dispatch = useCallback((action: TimelineAction) => {
    switch (action.type) {
      case 'SET_PLAYHEAD':
        setPlayhead(action.position);
        break;
      case 'SET_ZOOM':
        setZoom(action.pixelsPerSecond);
        break;
      case 'SET_VISIBLE_RANGE':
        setVisibleRange(action.start, action.end);
        break;
      case 'SET_SELECTION':
        setSelection(action.selection);
        break;
      case 'SET_LOOP':
        setLoop(action.enabled, action.start, action.end);
        break;
      case 'SET_SNAP':
        setSnapEnabled(action.enabled);
        break;
      case 'SET_GRID':
        setGridDivision(action.division);
        break;
      case 'ADD_TRACK':
        addTrack(action.track);
        break;
      case 'REMOVE_TRACK':
        removeTrack(action.trackId);
        break;
      case 'UPDATE_TRACK':
        updateTrack(action.trackId, action.updates);
        break;
      case 'REORDER_TRACKS':
        reorderTracks(action.trackIds);
        break;
      case 'ADD_CLIP':
        addClip(action.trackId, action.clip);
        break;
      case 'REMOVE_CLIP':
        removeClip(action.trackId, action.clipId);
        break;
      case 'UPDATE_CLIP':
        updateClip(action.trackId, action.clipId, action.updates);
        break;
      case 'MOVE_CLIP':
        moveClip(action.trackId, action.clipId, action.newStart, action.newTrackId);
        break;
      case 'SPLIT_CLIP':
        splitClip(action.trackId, action.clipId, action.splitPoint);
        break;
      case 'ADD_MARKER':
        addMarker(action.marker);
        break;
      case 'REMOVE_MARKER':
        removeMarker(action.markerId);
        break;
      case 'UPDATE_MARKER':
        updateMarker(action.markerId, action.updates);
        break;
    }
  }, [
    setPlayhead, setZoom, setVisibleRange, setSelection, setLoop,
    setSnapEnabled, setGridDivision, addTrack, removeTrack, updateTrack,
    reorderTracks, addClip, removeClip, updateClip, moveClip, splitClip,
    addMarker, removeMarker, updateMarker,
  ]);

  // ============ Return ============

  return useMemo(
    () => ({
      state,
      tracks,
      markers,
      setPlayhead,
      movePlayhead,
      setZoom,
      zoomIn,
      zoomOut,
      zoomToFit,
      setVisibleRange,
      scrollTo,
      setSelection,
      selectAll,
      clearSelection,
      setLoop,
      setLoopFromSelection,
      setSnapEnabled,
      setGridDivision,
      snapToGrid,
      addTrack,
      removeTrack,
      updateTrack,
      reorderTracks,
      getTrack,
      muteTrack,
      soloTrack,
      addClip,
      removeClip,
      updateClip,
      moveClip,
      splitClip,
      getClip,
      getClipsAtPosition,
      addMarker,
      removeMarker,
      updateMarker,
      getMarker,
      timeToPixels,
      pixelsToTime,
      dispatch,
    }),
    [
      state, tracks, markers, setPlayhead, movePlayhead, setZoom, zoomIn, zoomOut,
      zoomToFit, setVisibleRange, scrollTo, setSelection, selectAll, clearSelection,
      setLoop, setLoopFromSelection, setSnapEnabled, setGridDivision, snapToGrid,
      addTrack, removeTrack, updateTrack, reorderTracks, getTrack, muteTrack, soloTrack,
      addClip, removeClip, updateClip, moveClip, splitClip, getClip, getClipsAtPosition,
      addMarker, removeMarker, updateMarker, getMarker, timeToPixels, pixelsToTime, dispatch,
    ]
  );
}

export default useTimeline;
