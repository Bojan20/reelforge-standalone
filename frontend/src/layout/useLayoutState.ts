/**
 * useLayoutState - Centralized state management for LayoutDemo
 *
 * This hook extracts and manages common state used across layout components.
 * Part of the gradual refactoring of LayoutDemo into smaller components.
 *
 * @module layout/useLayoutState
 */

import { useState, useCallback, useMemo, useRef, useEffect } from 'react';

// ============ Types ============

export interface TimelineClip {
  id: string;
  trackId: string;
  name: string;
  startTime: number;
  duration: number;
  color: string;
  waveform?: number[];
  selected?: boolean;
}

export interface TimelineTrack {
  id: string;
  name: string;
  color: string;
  muted?: boolean;
  solo?: boolean;
  armed?: boolean;
}

export interface PlaybackState {
  isPlaying: boolean;
  currentTime: number;
  duration: number;
  bpm: number;
  loop: boolean;
  loopStart: number;
  loopEnd: number;
}

export interface SelectionState {
  selectedClipIds: Set<string>;
  selectedTrackIds: Set<string>;
  focusedClipId: string | null;
}

export interface ZoomState {
  timelineZoom: number;
  waveformZoom: number;
  verticalZoom: number;
}

export interface LayoutPanelState {
  leftPanelOpen: boolean;
  rightPanelOpen: boolean;
  bottomPanelOpen: boolean;
  leftPanelWidth: number;
  rightPanelWidth: number;
  bottomPanelHeight: number;
}

// ============ Default Values ============

export const DEFAULT_PLAYBACK: PlaybackState = {
  isPlaying: false,
  currentTime: 0,
  duration: 300,
  bpm: 120,
  loop: false,
  loopStart: 0,
  loopEnd: 60,
};

export const DEFAULT_ZOOM: ZoomState = {
  timelineZoom: 1,
  waveformZoom: 1,
  verticalZoom: 1,
};

export const DEFAULT_PANELS: LayoutPanelState = {
  leftPanelOpen: true,
  rightPanelOpen: true,
  bottomPanelOpen: true,
  leftPanelWidth: 280,
  rightPanelWidth: 320,
  bottomPanelHeight: 200,
};

// ============ Hook ============

export interface UseLayoutStateOptions {
  /** Session storage key for persistence */
  storageKey?: string;
  /** Default tracks */
  defaultTracks?: TimelineTrack[];
}

export function useLayoutState(options: UseLayoutStateOptions = {}) {
  const { storageKey = 'rf-layout-state' } = options;

  // Playback state
  const [playback, setPlayback] = useState<PlaybackState>(DEFAULT_PLAYBACK);
  const playbackRef = useRef(playback);
  playbackRef.current = playback;

  // Timeline clips
  const [clips, setClips] = useState<TimelineClip[]>([]);

  // Selection
  const [selection, setSelection] = useState<SelectionState>({
    selectedClipIds: new Set(),
    selectedTrackIds: new Set(),
    focusedClipId: null,
  });

  // Zoom
  const [zoom, setZoom] = useState<ZoomState>(DEFAULT_ZOOM);

  // Panel state
  const [panels, setPanels] = useState<LayoutPanelState>(DEFAULT_PANELS);

  // ===== Playback Actions =====

  const play = useCallback(() => {
    setPlayback(prev => ({ ...prev, isPlaying: true }));
  }, []);

  const pause = useCallback(() => {
    setPlayback(prev => ({ ...prev, isPlaying: false }));
  }, []);

  const stop = useCallback(() => {
    setPlayback(prev => ({ ...prev, isPlaying: false, currentTime: 0 }));
  }, []);

  const seek = useCallback((time: number) => {
    setPlayback(prev => ({
      ...prev,
      currentTime: Math.max(0, Math.min(time, prev.duration)),
    }));
  }, []);

  const toggleLoop = useCallback(() => {
    setPlayback(prev => ({ ...prev, loop: !prev.loop }));
  }, []);

  const setLoopRegion = useCallback((start: number, end: number) => {
    setPlayback(prev => ({
      ...prev,
      loopStart: Math.max(0, start),
      loopEnd: Math.min(end, prev.duration),
    }));
  }, []);

  const setBpm = useCallback((bpm: number) => {
    setPlayback(prev => ({ ...prev, bpm: Math.max(20, Math.min(bpm, 999)) }));
  }, []);

  // ===== Clip Actions =====

  const addClip = useCallback((clip: Omit<TimelineClip, 'id'>) => {
    const id = `clip_${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
    setClips(prev => [...prev, { ...clip, id }]);
    return id;
  }, []);

  const updateClip = useCallback((id: string, updates: Partial<TimelineClip>) => {
    setClips(prev => prev.map(clip =>
      clip.id === id ? { ...clip, ...updates } : clip
    ));
  }, []);

  const removeClip = useCallback((id: string) => {
    setClips(prev => prev.filter(clip => clip.id !== id));
    setSelection(prev => {
      const newSelected = new Set(prev.selectedClipIds);
      newSelected.delete(id);
      return {
        ...prev,
        selectedClipIds: newSelected,
        focusedClipId: prev.focusedClipId === id ? null : prev.focusedClipId,
      };
    });
  }, []);

  const moveClip = useCallback((id: string, startTime: number, trackId?: string) => {
    setClips(prev => prev.map(clip =>
      clip.id === id
        ? { ...clip, startTime, ...(trackId ? { trackId } : {}) }
        : clip
    ));
  }, []);

  const resizeClip = useCallback((id: string, startTime: number, duration: number) => {
    setClips(prev => prev.map(clip =>
      clip.id === id ? { ...clip, startTime, duration } : clip
    ));
  }, []);

  // ===== Selection Actions =====

  const selectClip = useCallback((id: string, addToSelection = false) => {
    setSelection(prev => {
      const newSelected = addToSelection
        ? new Set(prev.selectedClipIds)
        : new Set<string>();

      if (newSelected.has(id)) {
        newSelected.delete(id);
      } else {
        newSelected.add(id);
      }

      return {
        ...prev,
        selectedClipIds: newSelected,
        focusedClipId: id,
      };
    });
  }, []);

  const selectAllClips = useCallback(() => {
    setSelection(prev => ({
      ...prev,
      selectedClipIds: new Set(clips.map(c => c.id)),
    }));
  }, [clips]);

  const deselectAll = useCallback(() => {
    setSelection({
      selectedClipIds: new Set(),
      selectedTrackIds: new Set(),
      focusedClipId: null,
    });
  }, []);

  // ===== Zoom Actions =====

  const setTimelineZoom = useCallback((level: number) => {
    setZoom(prev => ({
      ...prev,
      timelineZoom: Math.max(0.1, Math.min(level, 10)),
    }));
  }, []);

  const zoomIn = useCallback(() => {
    setZoom(prev => ({
      ...prev,
      timelineZoom: Math.min(prev.timelineZoom * 1.2, 10),
    }));
  }, []);

  const zoomOut = useCallback(() => {
    setZoom(prev => ({
      ...prev,
      timelineZoom: Math.max(prev.timelineZoom / 1.2, 0.1),
    }));
  }, []);

  const zoomToFit = useCallback(() => {
    if (clips.length === 0) return;

    // Calculate content bounds (would use container width for actual zoom calculation)
    void clips.reduce(
      (max, clip) => Math.max(max, clip.startTime + clip.duration),
      0
    );

    // Reset to default zoom for now
    setZoom(prev => ({ ...prev, timelineZoom: 1 }));
  }, [clips]);

  // ===== Panel Actions =====

  const toggleLeftPanel = useCallback(() => {
    setPanels(prev => ({ ...prev, leftPanelOpen: !prev.leftPanelOpen }));
  }, []);

  const toggleRightPanel = useCallback(() => {
    setPanels(prev => ({ ...prev, rightPanelOpen: !prev.rightPanelOpen }));
  }, []);

  const toggleBottomPanel = useCallback(() => {
    setPanels(prev => ({ ...prev, bottomPanelOpen: !prev.bottomPanelOpen }));
  }, []);

  const setLeftPanelWidth = useCallback((width: number) => {
    setPanels(prev => ({ ...prev, leftPanelWidth: Math.max(200, Math.min(width, 600)) }));
  }, []);

  const setRightPanelWidth = useCallback((width: number) => {
    setPanels(prev => ({ ...prev, rightPanelWidth: Math.max(200, Math.min(width, 600)) }));
  }, []);

  const setBottomPanelHeight = useCallback((height: number) => {
    setPanels(prev => ({ ...prev, bottomPanelHeight: Math.max(100, Math.min(height, 500)) }));
  }, []);

  // ===== Persistence =====

  useEffect(() => {
    try {
      const saved = sessionStorage.getItem(storageKey);
      if (saved) {
        const parsed = JSON.parse(saved);
        if (parsed.panels) setPanels(parsed.panels);
        if (parsed.zoom) setZoom(parsed.zoom);
      }
    } catch {
      // Ignore parse errors
    }
  }, [storageKey]);

  useEffect(() => {
    try {
      sessionStorage.setItem(storageKey, JSON.stringify({ panels, zoom }));
    } catch {
      // Ignore storage errors
    }
  }, [storageKey, panels, zoom]);

  // ===== Derived State =====

  const selectedClips = useMemo(
    () => clips.filter(c => selection.selectedClipIds.has(c.id)),
    [clips, selection.selectedClipIds]
  );

  const focusedClip = useMemo(
    () => clips.find(c => c.id === selection.focusedClipId) ?? null,
    [clips, selection.focusedClipId]
  );

  // ===== Return =====

  return {
    // State
    playback,
    clips,
    selection,
    zoom,
    panels,

    // Derived
    selectedClips,
    focusedClip,

    // Playback actions
    play,
    pause,
    stop,
    seek,
    toggleLoop,
    setLoopRegion,
    setBpm,
    setPlayback,

    // Clip actions
    addClip,
    updateClip,
    removeClip,
    moveClip,
    resizeClip,
    setClips,

    // Selection actions
    selectClip,
    selectAllClips,
    deselectAll,

    // Zoom actions
    setTimelineZoom,
    zoomIn,
    zoomOut,
    zoomToFit,
    setZoom,

    // Panel actions
    toggleLeftPanel,
    toggleRightPanel,
    toggleBottomPanel,
    setLeftPanelWidth,
    setRightPanelWidth,
    setBottomPanelHeight,
    setPanels,
  };
}

export type LayoutStateReturn = ReturnType<typeof useLayoutState>;
