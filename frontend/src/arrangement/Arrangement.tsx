/**
 * ReelForge Arrangement
 *
 * Track arrangement view:
 * - Multiple tracks
 * - Clip/region editing
 * - Timeline with markers
 * - Zoom/scroll
 * - Selection/drag
 * - Track controls
 *
 * @module arrangement/Arrangement
 */

import { useRef, useEffect, useCallback, useState, useMemo } from 'react';
import './Arrangement.css';

// ============ Types ============

export interface Clip {
  id: string;
  trackId: string;
  start: number;      // beats
  duration: number;   // beats
  name?: string;
  color?: string;
  muted?: boolean;
  data?: unknown;     // clip-specific data (audio, midi, etc.)
}

export interface Track {
  id: string;
  name: string;
  type: 'audio' | 'midi' | 'bus' | 'master';
  color?: string;
  height?: number;
  muted?: boolean;
  solo?: boolean;
  armed?: boolean;
  volume?: number;    // 0-1
  pan?: number;       // -1 to 1
}

export interface Marker {
  id: string;
  position: number;   // beats
  name: string;
  color?: string;
}

export interface ArrangementProps {
  /** Tracks */
  tracks: Track[];
  /** Clips */
  clips: Clip[];
  /** Markers */
  markers?: Marker[];
  /** On tracks change */
  onTracksChange?: (tracks: Track[]) => void;
  /** On clips change */
  onClipsChange?: (clips: Clip[]) => void;
  /** On markers change */
  onMarkersChange?: (markers: Marker[]) => void;
  /** Total length in beats */
  length?: number;
  /** Beats per bar */
  beatsPerBar?: number;
  /** Pixels per beat */
  pixelsPerBeat?: number;
  /** Default track height */
  trackHeight?: number;
  /** Snap to grid (beats) */
  snap?: number;
  /** Playhead position (beats) */
  playhead?: number;
  /** Loop start (beats) */
  loopStart?: number;
  /** Loop end (beats) */
  loopEnd?: number;
  /** On playhead change */
  onPlayheadChange?: (beat: number) => void;
  /** On loop change */
  onLoopChange?: (start: number, end: number) => void;
  /** On clip select */
  onClipSelect?: (clipIds: string[]) => void;
  /** On track select */
  onTrackSelect?: (trackId: string | null) => void;
  /** Track controls width */
  trackControlsWidth?: number;
  /** Header height */
  headerHeight?: number;
  /** Custom class */
  className?: string;
}

// ============ Arrangement Component ============

export function Arrangement({
  tracks,
  clips,
  markers = [],
  onTracksChange,
  onClipsChange: _onClipsChange,
  onMarkersChange: _onMarkersChange,
  length = 64,
  beatsPerBar = 4,
  pixelsPerBeat = 20,
  trackHeight = 80,
  snap = 1,
  playhead,
  loopStart,
  loopEnd,
  onPlayheadChange,
  onLoopChange: _onLoopChange,
  onClipSelect,
  onTrackSelect,
  trackControlsWidth = 200,
  headerHeight = 40,
  className = '',
}: ArrangementProps) {
  void _onMarkersChange; void _onLoopChange; // Reserved for future use
  const containerRef = useRef<HTMLDivElement>(null);
  const timelineRef = useRef<HTMLCanvasElement>(null);
  const gridRef = useRef<HTMLCanvasElement>(null);

  const [selectedClips, setSelectedClips] = useState<Set<string>>(new Set());
  const [selectedTrack, setSelectedTrack] = useState<string | null>(null);
  const [scrollLeft, setScrollLeft] = useState(0);
  const [scrollTop, setScrollTop] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const [dragMode, setDragMode] = useState<'move' | 'resize-start' | 'resize-end' | 'select'>('move');
  const [dragStartX, setDragStartX] = useState(0);
  const [dragStartClips, setDragStartClips] = useState<Map<string, { start: number; duration: number }>>(new Map());

  const gridWidth = length * pixelsPerBeat;
  const totalHeight = tracks.reduce((sum, t) => sum + (t.height || trackHeight), 0);

  // Snap value to grid
  const snapToGrid = useCallback(
    (value: number): number => {
      if (snap <= 0) return value;
      return Math.round(value / snap) * snap;
    },
    [snap]
  );

  // Convert pixel to beat
  const pixelToBeat = useCallback(
    (px: number): number => {
      return (px + scrollLeft) / pixelsPerBeat;
    },
    [scrollLeft, pixelsPerBeat]
  );

  // Get track at Y position
  const getTrackAtY = useCallback(
    (y: number): Track | null => {
      let accY = 0;
      for (const track of tracks) {
        const h = track.height || trackHeight;
        if (y >= accY && y < accY + h) {
          return track;
        }
        accY += h;
      }
      return null;
    },
    [tracks, trackHeight]
  );

  // Draw timeline
  const drawTimeline = useCallback(() => {
    const canvas = timelineRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const width = canvas.width / dpr;
    const height = canvas.height / dpr;

    ctx.clearRect(0, 0, width, height);

    // Background
    ctx.fillStyle = '#1a1a1a';
    ctx.fillRect(0, 0, width, height);

    // Beat/bar numbers
    for (let beat = 0; beat <= length; beat++) {
      const x = beat * pixelsPerBeat - scrollLeft;
      if (x < 0 || x > width) continue;

      const isBar = beat % beatsPerBar === 0;
      const barNumber = Math.floor(beat / beatsPerBar) + 1;

      if (isBar) {
        // Bar line
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.3)';
        ctx.beginPath();
        ctx.moveTo(x, height - 10);
        ctx.lineTo(x, height);
        ctx.stroke();

        // Bar number
        ctx.fillStyle = 'rgba(255, 255, 255, 0.6)';
        ctx.font = '11px system-ui';
        ctx.textAlign = 'center';
        ctx.fillText(String(barNumber), x, height - 16);
      } else {
        // Beat tick
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.15)';
        ctx.beginPath();
        ctx.moveTo(x, height - 5);
        ctx.lineTo(x, height);
        ctx.stroke();
      }
    }

    // Markers
    for (const marker of markers) {
      const x = marker.position * pixelsPerBeat - scrollLeft;
      if (x < 0 || x > width) continue;

      ctx.fillStyle = marker.color || '#f59e0b';
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x + 6, 8);
      ctx.lineTo(x, 16);
      ctx.lineTo(x - 6, 8);
      ctx.closePath();
      ctx.fill();

      ctx.fillStyle = '#fff';
      ctx.font = '9px system-ui';
      ctx.textAlign = 'left';
      ctx.fillText(marker.name, x + 8, 12);
    }

    // Loop region
    if (loopStart !== undefined && loopEnd !== undefined) {
      const lx1 = loopStart * pixelsPerBeat - scrollLeft;
      const lx2 = loopEnd * pixelsPerBeat - scrollLeft;

      ctx.fillStyle = 'rgba(99, 102, 241, 0.2)';
      ctx.fillRect(lx1, 0, lx2 - lx1, height);

      ctx.fillStyle = '#6366f1';
      ctx.fillRect(lx1, 0, 2, height);
      ctx.fillRect(lx2 - 2, 0, 2, height);
    }

    // Playhead
    if (playhead !== undefined) {
      const px = playhead * pixelsPerBeat - scrollLeft;
      if (px >= 0 && px <= width) {
        ctx.fillStyle = '#ef4444';
        ctx.beginPath();
        ctx.moveTo(px - 6, 0);
        ctx.lineTo(px + 6, 0);
        ctx.lineTo(px, 10);
        ctx.closePath();
        ctx.fill();
      }
    }
  }, [length, beatsPerBar, pixelsPerBeat, scrollLeft, markers, loopStart, loopEnd, playhead]);

  // Draw grid
  const drawGrid = useCallback(() => {
    const canvas = gridRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const width = canvas.width / dpr;
    const height = canvas.height / dpr;

    ctx.clearRect(0, 0, width, height);

    // Track backgrounds
    let y = -scrollTop;
    for (const track of tracks) {
      const h = track.height || trackHeight;

      if (y + h > 0 && y < height) {
        // Track background
        ctx.fillStyle = track.muted
          ? 'rgba(255, 255, 255, 0.02)'
          : 'rgba(255, 255, 255, 0.04)';
        ctx.fillRect(0, y, width, h);

        // Track separator
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.1)';
        ctx.beginPath();
        ctx.moveTo(0, y + h);
        ctx.lineTo(width, y + h);
        ctx.stroke();
      }

      y += h;
    }

    // Beat lines
    for (let beat = 0; beat <= length; beat++) {
      const x = beat * pixelsPerBeat - scrollLeft;
      if (x < 0 || x > width) continue;

      const isBar = beat % beatsPerBar === 0;
      ctx.strokeStyle = isBar
        ? 'rgba(255, 255, 255, 0.15)'
        : 'rgba(255, 255, 255, 0.05)';
      ctx.lineWidth = isBar ? 1 : 0.5;

      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, height);
      ctx.stroke();
    }

    // Loop region overlay
    if (loopStart !== undefined && loopEnd !== undefined) {
      const lx1 = loopStart * pixelsPerBeat - scrollLeft;
      const lx2 = loopEnd * pixelsPerBeat - scrollLeft;

      ctx.fillStyle = 'rgba(99, 102, 241, 0.08)';
      ctx.fillRect(lx1, 0, lx2 - lx1, height);
    }

    // Playhead
    if (playhead !== undefined) {
      const px = playhead * pixelsPerBeat - scrollLeft;
      if (px >= 0 && px <= width) {
        ctx.strokeStyle = '#ef4444';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(px, 0);
        ctx.lineTo(px, height);
        ctx.stroke();
      }
    }
  }, [tracks, trackHeight, length, beatsPerBar, pixelsPerBeat, scrollLeft, scrollTop, loopStart, loopEnd, playhead]);

  // Setup canvases
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const rect = container.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;

    // Timeline canvas
    if (timelineRef.current) {
      timelineRef.current.width = (rect.width - trackControlsWidth) * dpr;
      timelineRef.current.height = headerHeight * dpr;
      timelineRef.current.style.width = `${rect.width - trackControlsWidth}px`;
      timelineRef.current.style.height = `${headerHeight}px`;

      const ctx = timelineRef.current.getContext('2d');
      if (ctx) ctx.scale(dpr, dpr);
    }

    // Grid canvas
    if (gridRef.current) {
      gridRef.current.width = (rect.width - trackControlsWidth) * dpr;
      gridRef.current.height = (rect.height - headerHeight) * dpr;
      gridRef.current.style.width = `${rect.width - trackControlsWidth}px`;
      gridRef.current.style.height = `${rect.height - headerHeight}px`;

      const ctx = gridRef.current.getContext('2d');
      if (ctx) ctx.scale(dpr, dpr);
    }

    drawTimeline();
    drawGrid();
  }, [trackControlsWidth, headerHeight, drawTimeline, drawGrid]);

  // Get clip position and size
  const getClipStyle = useCallback(
    (clip: Clip): React.CSSProperties => {
      let y = 0;
      for (const track of tracks) {
        if (track.id === clip.trackId) break;
        y += track.height || trackHeight;
      }

      return {
        left: clip.start * pixelsPerBeat - scrollLeft,
        top: y - scrollTop,
        width: clip.duration * pixelsPerBeat,
        height: (tracks.find((t) => t.id === clip.trackId)?.height || trackHeight) - 4,
        backgroundColor: clip.color || '#6366f1',
        opacity: clip.muted ? 0.4 : 1,
      };
    },
    [tracks, trackHeight, pixelsPerBeat, scrollLeft, scrollTop]
  );

  // Mouse handlers
  const handleGridMouseDown = useCallback(
    (e: React.MouseEvent) => {
      const rect = (e.target as HTMLElement).getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;

      const beat = snapToGrid(pixelToBeat(x));
      const track = getTrackAtY(y + scrollTop);

      if (!track) return;

      // Check if clicking on existing clip
      const clickedClip = clips.find((clip) => {
        if (clip.trackId !== track.id) return false;
        const clipX = clip.start * pixelsPerBeat - scrollLeft;
        const clipW = clip.duration * pixelsPerBeat;
        return x >= clipX && x <= clipX + clipW;
      });

      if (clickedClip) {
        // Select clip
        let newSelection: Set<string>;
        if (e.shiftKey) {
          newSelection = new Set(selectedClips);
          if (newSelection.has(clickedClip.id)) {
            newSelection.delete(clickedClip.id);
          } else {
            newSelection.add(clickedClip.id);
          }
        } else if (!selectedClips.has(clickedClip.id)) {
          newSelection = new Set([clickedClip.id]);
        } else {
          newSelection = selectedClips;
        }
        setSelectedClips(newSelection);

        // Determine drag mode
        const clipX = clickedClip.start * pixelsPerBeat - scrollLeft;
        const clipW = clickedClip.duration * pixelsPerBeat;

        if (x - clipX < 8) {
          setDragMode('resize-start');
        } else if (clipX + clipW - x < 8) {
          setDragMode('resize-end');
        } else {
          setDragMode('move');
        }

        // Store initial clip positions for dragging
        setDragStartX(x);
        const startPositions = new Map<string, { start: number; duration: number }>();
        newSelection.forEach((clipId) => {
          const c = clips.find((cl) => cl.id === clipId);
          if (c) {
            startPositions.set(clipId, { start: c.start, duration: c.duration });
          }
        });
        setDragStartClips(startPositions);
        setIsDragging(true);
      } else {
        // Deselect and set playhead
        setSelectedClips(new Set());
        onPlayheadChange?.(beat);
      }
    },
    [clips, selectedClips, pixelsPerBeat, scrollLeft, scrollTop, snapToGrid, pixelToBeat, getTrackAtY, onPlayheadChange]
  );

  const handleGridMouseMove = useCallback(
    (e: React.MouseEvent) => {
      if (!isDragging || dragStartClips.size === 0) return;

      const rect = (e.target as HTMLElement).getBoundingClientRect();
      const x = e.clientX - rect.left;
      const deltaX = x - dragStartX;
      const deltaBeat = deltaX / pixelsPerBeat;

      const updatedClips = clips.map((clip) => {
        const startPos = dragStartClips.get(clip.id);
        if (!startPos) return clip;

        switch (dragMode) {
          case 'move': {
            const newStart = snapToGrid(startPos.start + deltaBeat);
            return { ...clip, start: Math.max(0, newStart) };
          }
          case 'resize-start': {
            const newStart = snapToGrid(startPos.start + deltaBeat);
            const maxStart = startPos.start + startPos.duration - snap;
            const clampedStart = Math.max(0, Math.min(maxStart, newStart));
            const newDuration = startPos.duration - (clampedStart - startPos.start);
            return { ...clip, start: clampedStart, duration: Math.max(snap, newDuration) };
          }
          case 'resize-end': {
            const newDuration = snapToGrid(startPos.duration + deltaBeat);
            return { ...clip, duration: Math.max(snap, newDuration) };
          }
          default:
            return clip;
        }
      });

      _onClipsChange?.(updatedClips);
    },
    [isDragging, dragStartX, dragStartClips, dragMode, clips, pixelsPerBeat, snap, snapToGrid, _onClipsChange]
  );

  const handleGridMouseUp = useCallback(() => {
    setIsDragging(false);
    setDragStartClips(new Map());
    onClipSelect?.(Array.from(selectedClips));
  }, [selectedClips, onClipSelect]);

  // Track controls
  const handleTrackMute = useCallback(
    (trackId: string) => {
      onTracksChange?.(
        tracks.map((t) => (t.id === trackId ? { ...t, muted: !t.muted } : t))
      );
    },
    [tracks, onTracksChange]
  );

  const handleTrackSolo = useCallback(
    (trackId: string) => {
      onTracksChange?.(
        tracks.map((t) => (t.id === trackId ? { ...t, solo: !t.solo } : t))
      );
    },
    [tracks, onTracksChange]
  );

  const handleTrackArm = useCallback(
    (trackId: string) => {
      onTracksChange?.(
        tracks.map((t) => (t.id === trackId ? { ...t, armed: !t.armed } : t))
      );
    },
    [tracks, onTracksChange]
  );

  const handleTrackSelect = useCallback(
    (trackId: string) => {
      setSelectedTrack(trackId);
      onTrackSelect?.(trackId);
    },
    [onTrackSelect]
  );

  // Render track controls
  const renderTrackControls = useMemo(() => {
    let y = -scrollTop;

    return tracks.map((track) => {
      const h = track.height || trackHeight;
      const top = y;
      y += h;

      if (top + h < 0 || top > 600) return null;

      return (
        <div
          key={track.id}
          className={`arrangement__track-control ${
            selectedTrack === track.id ? 'arrangement__track-control--selected' : ''
          }`}
          style={{ top, height: h }}
          onClick={() => handleTrackSelect(track.id)}
        >
          <div
            className="arrangement__track-color"
            style={{ backgroundColor: track.color || '#6366f1' }}
          />
          <div className="arrangement__track-info">
            <span className="arrangement__track-name">{track.name}</span>
            <span className="arrangement__track-type">{track.type}</span>
          </div>
          <div className="arrangement__track-buttons">
            <button
              className={`arrangement__track-btn ${track.muted ? 'arrangement__track-btn--active' : ''}`}
              onClick={(e) => {
                e.stopPropagation();
                handleTrackMute(track.id);
              }}
            >
              M
            </button>
            <button
              className={`arrangement__track-btn ${track.solo ? 'arrangement__track-btn--active arrangement__track-btn--solo' : ''}`}
              onClick={(e) => {
                e.stopPropagation();
                handleTrackSolo(track.id);
              }}
            >
              S
            </button>
            {track.type !== 'bus' && track.type !== 'master' && (
              <button
                className={`arrangement__track-btn ${track.armed ? 'arrangement__track-btn--active arrangement__track-btn--arm' : ''}`}
                onClick={(e) => {
                  e.stopPropagation();
                  handleTrackArm(track.id);
                }}
              >
                R
              </button>
            )}
          </div>
        </div>
      );
    });
  }, [tracks, trackHeight, scrollTop, selectedTrack, handleTrackSelect, handleTrackMute, handleTrackSolo, handleTrackArm]);

  // Render clips
  const renderClips = useMemo(() => {
    return clips.map((clip) => {
      const style = getClipStyle(clip);
      const isSelected = selectedClips.has(clip.id);

      // Skip if not visible
      if (
        (style.left as number) + (style.width as number) < 0 ||
        (style.left as number) > 1200 ||
        (style.top as number) + (style.height as number) < 0 ||
        (style.top as number) > 600
      ) {
        return null;
      }

      return (
        <div
          key={clip.id}
          className={`arrangement__clip ${isSelected ? 'arrangement__clip--selected' : ''} ${
            clip.muted ? 'arrangement__clip--muted' : ''
          }`}
          style={style}
        >
          <div className="arrangement__clip-header">
            <span className="arrangement__clip-name">{clip.name || 'Clip'}</span>
          </div>
          <div className="arrangement__clip-body" />
          <div className="arrangement__clip-resize arrangement__clip-resize--start" />
          <div className="arrangement__clip-resize arrangement__clip-resize--end" />
        </div>
      );
    });
  }, [clips, selectedClips, getClipStyle]);

  return (
    <div ref={containerRef} className={`arrangement ${className}`}>
      {/* Header */}
      <div className="arrangement__header" style={{ height: headerHeight }}>
        <div
          className="arrangement__header-controls"
          style={{ width: trackControlsWidth }}
        >
          <span className="arrangement__header-title">Tracks</span>
        </div>
        <div className="arrangement__header-timeline">
          <canvas ref={timelineRef} className="arrangement__timeline-canvas" />
        </div>
      </div>

      {/* Body */}
      <div className="arrangement__body">
        {/* Track controls */}
        <div
          className="arrangement__track-controls"
          style={{ width: trackControlsWidth }}
        >
          {renderTrackControls}
        </div>

        {/* Grid area */}
        <div
          className="arrangement__grid-area"
          onScroll={(e) => {
            const target = e.target as HTMLElement;
            setScrollLeft(target.scrollLeft);
            setScrollTop(target.scrollTop);
          }}
        >
          <canvas ref={gridRef} className="arrangement__grid-canvas" />
          <div
            className="arrangement__clips-layer"
            onMouseDown={handleGridMouseDown}
            onMouseMove={handleGridMouseMove}
            onMouseUp={handleGridMouseUp}
            onMouseLeave={handleGridMouseUp}
            style={{ width: gridWidth, height: totalHeight }}
          >
            {renderClips}
          </div>
        </div>
      </div>
    </div>
  );
}

// ============ useArrangement Hook ============

export function useArrangement(
  initialTracks: Track[] = [],
  initialClips: Clip[] = []
) {
  const [tracks, setTracks] = useState<Track[]>(initialTracks);
  const [clips, setClips] = useState<Clip[]>(initialClips);
  const [markers, setMarkers] = useState<Marker[]>([]);
  const [selectedClips, setSelectedClips] = useState<string[]>([]);
  const [selectedTrack, setSelectedTrack] = useState<string | null>(null);

  // Track operations
  const addTrack = useCallback((track: Omit<Track, 'id'>) => {
    const newTrack: Track = {
      ...track,
      id: `track-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
    };
    setTracks((prev) => [...prev, newTrack]);
    return newTrack.id;
  }, []);

  const removeTrack = useCallback((id: string) => {
    setTracks((prev) => prev.filter((t) => t.id !== id));
    setClips((prev) => prev.filter((c) => c.trackId !== id));
  }, []);

  const updateTrack = useCallback((id: string, updates: Partial<Track>) => {
    setTracks((prev) =>
      prev.map((t) => (t.id === id ? { ...t, ...updates } : t))
    );
  }, []);

  const reorderTracks = useCallback((fromIndex: number, toIndex: number) => {
    setTracks((prev) => {
      const result = [...prev];
      const [removed] = result.splice(fromIndex, 1);
      result.splice(toIndex, 0, removed);
      return result;
    });
  }, []);

  // Clip operations
  const addClip = useCallback((clip: Omit<Clip, 'id'>) => {
    const newClip: Clip = {
      ...clip,
      id: `clip-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
    };
    setClips((prev) => [...prev, newClip]);
    return newClip.id;
  }, []);

  const removeClip = useCallback((id: string) => {
    setClips((prev) => prev.filter((c) => c.id !== id));
    setSelectedClips((prev) => prev.filter((cid) => cid !== id));
  }, []);

  const updateClip = useCallback((id: string, updates: Partial<Clip>) => {
    setClips((prev) =>
      prev.map((c) => (c.id === id ? { ...c, ...updates } : c))
    );
  }, []);

  const duplicateClip = useCallback((id: string) => {
    const clip = clips.find((c) => c.id === id);
    if (!clip) return null;

    const newClip: Clip = {
      ...clip,
      id: `clip-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      start: clip.start + clip.duration,
    };
    setClips((prev) => [...prev, newClip]);
    return newClip.id;
  }, [clips]);

  const splitClip = useCallback((id: string, position: number) => {
    const clip = clips.find((c) => c.id === id);
    if (!clip) return null;

    if (position <= clip.start || position >= clip.start + clip.duration) {
      return null;
    }

    const leftDuration = position - clip.start;
    const rightDuration = clip.duration - leftDuration;

    // Update original clip
    updateClip(id, { duration: leftDuration });

    // Create new clip
    const newClipId = addClip({
      ...clip,
      start: position,
      duration: rightDuration,
      name: clip.name ? `${clip.name} (split)` : 'Split',
    });

    return newClipId;
  }, [clips, updateClip, addClip]);

  // Marker operations
  const addMarker = useCallback((marker: Omit<Marker, 'id'>) => {
    const newMarker: Marker = {
      ...marker,
      id: `marker-${Date.now()}`,
    };
    setMarkers((prev) => [...prev, newMarker].sort((a, b) => a.position - b.position));
    return newMarker.id;
  }, []);

  const removeMarker = useCallback((id: string) => {
    setMarkers((prev) => prev.filter((m) => m.id !== id));
  }, []);

  const updateMarker = useCallback((id: string, updates: Partial<Marker>) => {
    setMarkers((prev) =>
      prev
        .map((m) => (m.id === id ? { ...m, ...updates } : m))
        .sort((a, b) => a.position - b.position)
    );
  }, []);

  // Selection operations
  const selectClips = useCallback((ids: string[]) => {
    setSelectedClips(ids);
  }, []);

  const selectAllClipsInTrack = useCallback(
    (trackId: string) => {
      const trackClipIds = clips
        .filter((c) => c.trackId === trackId)
        .map((c) => c.id);
      setSelectedClips(trackClipIds);
    },
    [clips]
  );

  const clearSelection = useCallback(() => {
    setSelectedClips([]);
    setSelectedTrack(null);
  }, []);

  // Bulk operations
  const deleteSelectedClips = useCallback(() => {
    setClips((prev) => prev.filter((c) => !selectedClips.includes(c.id)));
    setSelectedClips([]);
  }, [selectedClips]);

  const muteSelectedClips = useCallback((muted: boolean) => {
    setClips((prev) =>
      prev.map((c) =>
        selectedClips.includes(c.id) ? { ...c, muted } : c
      )
    );
  }, [selectedClips]);

  const clear = useCallback(() => {
    setTracks([]);
    setClips([]);
    setMarkers([]);
    setSelectedClips([]);
    setSelectedTrack(null);
  }, []);

  return {
    tracks,
    setTracks,
    clips,
    setClips,
    markers,
    setMarkers,
    selectedClips,
    selectedTrack,
    setSelectedTrack,

    // Track operations
    addTrack,
    removeTrack,
    updateTrack,
    reorderTracks,

    // Clip operations
    addClip,
    removeClip,
    updateClip,
    duplicateClip,
    splitClip,

    // Marker operations
    addMarker,
    removeMarker,
    updateMarker,

    // Selection
    selectClips,
    selectAllClipsInTrack,
    clearSelection,

    // Bulk operations
    deleteSelectedClips,
    muteSelectedClips,
    clear,
  };
}

export default Arrangement;
