/**
 * useTimelineState - Timeline State Hook
 *
 * Manages timeline state:
 * - Tracks (separate from clips)
 * - Clips (with trackId reference)
 * - Playback position
 * - Loop region
 * - Crossfades
 * - Zoom/scroll
 *
 * Note: TimelineTrack does NOT contain clips inline.
 * Clips are stored separately with trackId references.
 *
 * @module layout/editor/hooks/useTimelineState
 */

import { useState, useCallback, useMemo } from 'react';
import { TRACK_COLORS } from '../constants';
import type { TimelineTrack, TimelineClip, Crossfade } from '../../Timeline';

// ============ Types ============

export interface UseTimelineStateReturn {
  /** Timeline tracks */
  tracks: TimelineTrack[];
  /** Set tracks */
  setTracks: React.Dispatch<React.SetStateAction<TimelineTrack[]>>;
  /** Timeline clips */
  clips: TimelineClip[];
  /** Set clips */
  setClips: React.Dispatch<React.SetStateAction<TimelineClip[]>>;
  /** Crossfades */
  crossfades: Crossfade[];
  /** Set crossfades */
  setCrossfades: React.Dispatch<React.SetStateAction<Crossfade[]>>;
  /** Current playback position */
  currentTime: number;
  /** Set current time */
  setCurrentTime: (time: number) => void;
  /** Is playing */
  isPlaying: boolean;
  /** Set is playing */
  setIsPlaying: (playing: boolean) => void;
  /** Loop enabled */
  loopEnabled: boolean;
  /** Set loop enabled */
  setLoopEnabled: (enabled: boolean) => void;
  /** Loop start time */
  loopStart: number;
  /** Loop end time */
  loopEnd: number;
  /** Set loop region */
  setLoopRegion: (start: number, end: number) => void;
  /** Zoom level (pixels per second) */
  zoom: number;
  /** Set zoom */
  setZoom: (zoom: number) => void;
  /** Scroll position */
  scrollX: number;
  /** Set scroll position */
  setScrollX: (x: number) => void;
  /** Total duration */
  totalDuration: number;

  // Track operations
  addTrack: (name?: string) => string;
  removeTrack: (trackId: string) => void;
  renameTrack: (trackId: string, name: string) => void;
  setTrackColor: (trackId: string, color: string) => void;
  toggleTrackMute: (trackId: string) => void;
  toggleTrackSolo: (trackId: string) => void;
  setTrackOutputBus: (trackId: string, bus: 'master' | 'music' | 'sfx' | 'ambience' | 'voice') => void;
  getClipsForTrack: (trackId: string) => TimelineClip[];

  // Clip operations
  addClip: (clip: Omit<TimelineClip, 'id'>) => string;
  removeClip: (clipId: string) => void;
  updateClip: (clipId: string, updates: Partial<TimelineClip>) => void;
  moveClip: (clipId: string, newStartTime: number) => void;
  resizeClip: (clipId: string, newStartTime: number, newDuration: number) => void;
  splitClip: (clipId: string, splitTime: number) => string | null;
  duplicateClip: (clipId: string) => string | null;
  getClip: (clipId: string) => TimelineClip | undefined;

  // Crossfade operations
  addCrossfade: (crossfade: Omit<Crossfade, 'id'>) => string;
  removeCrossfade: (crossfadeId: string) => void;
  updateCrossfade: (crossfadeId: string, duration: number) => void;
}

// ============ Hook ============

let trackIdCounter = 0;
let clipIdCounter = 0;
let crossfadeIdCounter = 0;

export function useTimelineState(): UseTimelineStateReturn {
  // Tracks (without inline clips)
  const [tracks, setTracks] = useState<TimelineTrack[]>([]);

  // Clips (separate, with trackId)
  const [clips, setClips] = useState<TimelineClip[]>([]);

  // Crossfades
  const [crossfades, setCrossfades] = useState<Crossfade[]>([]);

  // Playback state
  const [currentTime, setCurrentTime] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);

  // Loop state
  const [loopEnabled, setLoopEnabled] = useState(false);
  const [loopStart, setLoopStart] = useState(0);
  const [loopEnd, setLoopEnd] = useState(10);

  // View state
  const [zoom, setZoom] = useState(100); // pixels per second
  const [scrollX, setScrollX] = useState(0);

  // Calculate total duration
  const totalDuration = useMemo(() => {
    let maxEnd = 0;
    for (const clip of clips) {
      const clipEnd = clip.startTime + clip.duration;
      if (clipEnd > maxEnd) maxEnd = clipEnd;
    }
    return Math.max(maxEnd + 10, 60); // At least 60 seconds
  }, [clips]);

  // Set loop region
  const setLoopRegion = useCallback((start: number, end: number) => {
    setLoopStart(start);
    setLoopEnd(end);
  }, []);

  // Get clips for a track
  const getClipsForTrack = useCallback((trackId: string): TimelineClip[] => {
    return clips.filter(c => c.trackId === trackId);
  }, [clips]);

  // ============ Track Operations ============

  const addTrack = useCallback((name?: string): string => {
    const id = `track-${++trackIdCounter}`;
    const colorIndex = tracks.length % TRACK_COLORS.length;
    const newTrack: TimelineTrack = {
      id,
      name: name || `Track ${tracks.length + 1}`,
      color: TRACK_COLORS[colorIndex],
      muted: false,
      soloed: false,
      outputBus: 'master',
    };
    setTracks(prev => [...prev, newTrack]);
    return id;
  }, [tracks.length]);

  const removeTrack = useCallback((trackId: string) => {
    setTracks(prev => prev.filter(t => t.id !== trackId));
    // Also remove clips for this track
    setClips(prev => prev.filter(c => c.trackId !== trackId));
  }, []);

  const renameTrack = useCallback((trackId: string, name: string) => {
    setTracks(prev => prev.map(t =>
      t.id === trackId ? { ...t, name } : t
    ));
  }, []);

  const setTrackColor = useCallback((trackId: string, color: string) => {
    setTracks(prev => prev.map(t =>
      t.id === trackId ? { ...t, color } : t
    ));
  }, []);

  const toggleTrackMute = useCallback((trackId: string) => {
    setTracks(prev => prev.map(t =>
      t.id === trackId ? { ...t, muted: !t.muted } : t
    ));
  }, []);

  const toggleTrackSolo = useCallback((trackId: string) => {
    setTracks(prev => prev.map(t =>
      t.id === trackId ? { ...t, soloed: !t.soloed } : t
    ));
  }, []);

  const setTrackOutputBus = useCallback((trackId: string, bus: 'master' | 'music' | 'sfx' | 'ambience' | 'voice') => {
    setTracks(prev => prev.map(t =>
      t.id === trackId ? { ...t, outputBus: bus } : t
    ));
  }, []);

  // ============ Clip Operations ============

  const addClip = useCallback((clipData: Omit<TimelineClip, 'id'>): string => {
    const id = `clip-${++clipIdCounter}`;
    const clip: TimelineClip = { ...clipData, id };
    setClips(prev => [...prev, clip]);
    return id;
  }, []);

  const removeClip = useCallback((clipId: string) => {
    setClips(prev => prev.filter(c => c.id !== clipId));
  }, []);

  const updateClip = useCallback((clipId: string, updates: Partial<TimelineClip>) => {
    setClips(prev => prev.map(c =>
      c.id === clipId ? { ...c, ...updates } : c
    ));
  }, []);

  const moveClip = useCallback((clipId: string, newStartTime: number) => {
    updateClip(clipId, { startTime: Math.max(0, newStartTime) });
  }, [updateClip]);

  const resizeClip = useCallback((clipId: string, newStartTime: number, newDuration: number) => {
    updateClip(clipId, {
      startTime: Math.max(0, newStartTime),
      duration: Math.max(0.1, newDuration),
    });
  }, [updateClip]);

  const splitClip = useCallback((clipId: string, splitTime: number): string | null => {
    const clip = clips.find(c => c.id === clipId);
    if (!clip) return null;

    const clipEnd = clip.startTime + clip.duration;

    // Validate split point
    if (splitTime <= clip.startTime || splitTime >= clipEnd) {
      return null;
    }

    const firstDuration = splitTime - clip.startTime;
    const secondDuration = clipEnd - splitTime;
    const secondOffset = (clip.sourceOffset || 0) + firstDuration;

    const newClipId = `clip-${++clipIdCounter}`;

    // Update first clip
    setClips(prev => {
      const updated = prev.map(c =>
        c.id === clipId ? { ...c, duration: firstDuration } : c
      );

      // Add second clip
      const secondClip: TimelineClip = {
        ...clip,
        id: newClipId,
        startTime: splitTime,
        duration: secondDuration,
        sourceOffset: secondOffset,
      };

      return [...updated, secondClip];
    });

    return newClipId;
  }, [clips]);

  const duplicateClip = useCallback((clipId: string): string | null => {
    const clip = clips.find(c => c.id === clipId);
    if (!clip) return null;

    const newClipId = `clip-${++clipIdCounter}`;
    const newClip: TimelineClip = {
      ...clip,
      id: newClipId,
      startTime: clip.startTime + clip.duration + 0.1,
    };

    setClips(prev => [...prev, newClip]);
    return newClipId;
  }, [clips]);

  const getClip = useCallback((clipId: string): TimelineClip | undefined => {
    return clips.find(c => c.id === clipId);
  }, [clips]);

  // ============ Crossfade Operations ============

  const addCrossfade = useCallback((data: Omit<Crossfade, 'id'>): string => {
    const id = `xfade-${++crossfadeIdCounter}`;
    const crossfade: Crossfade = { ...data, id };
    setCrossfades(prev => [...prev, crossfade]);
    return id;
  }, []);

  const removeCrossfade = useCallback((crossfadeId: string) => {
    setCrossfades(prev => prev.filter(x => x.id !== crossfadeId));
  }, []);

  const updateCrossfade = useCallback((crossfadeId: string, duration: number) => {
    setCrossfades(prev => prev.map(x =>
      x.id === crossfadeId ? { ...x, duration } : x
    ));
  }, []);

  return {
    tracks,
    setTracks,
    clips,
    setClips,
    crossfades,
    setCrossfades,
    currentTime,
    setCurrentTime,
    isPlaying,
    setIsPlaying,
    loopEnabled,
    setLoopEnabled,
    loopStart,
    loopEnd,
    setLoopRegion,
    zoom,
    setZoom,
    scrollX,
    setScrollX,
    totalDuration,

    addTrack,
    removeTrack,
    renameTrack,
    setTrackColor,
    toggleTrackMute,
    toggleTrackSolo,
    setTrackOutputBus,
    getClipsForTrack,

    addClip,
    removeClip,
    updateClip,
    moveClip,
    resizeClip,
    splitClip,
    duplicateClip,
    getClip,

    addCrossfade,
    removeCrossfade,
    updateCrossfade,
  };
}

export default useTimelineState;
