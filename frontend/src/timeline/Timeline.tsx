/**
 * ReelForge Timeline Component
 *
 * Main timeline/sequencer component with:
 * - Track lanes with clips
 * - Playhead with transport controls
 * - Time ruler with grid
 * - Zoom and scroll
 * - Markers
 *
 * @module timeline/Timeline
 */

import { useRef, useEffect, useCallback, useState } from 'react';
import * as PIXI from 'pixi.js';
import type { UseTimelineReturn } from './useTimeline';
import type { Track, Clip, Seconds } from './types';
import { formatTime, secondsToBarsBeatsTicks, formatBarsBeatsTicks } from './types';
import './Timeline.css';

// ============ Types ============

export interface TimelineProps {
  /** Timeline hook return value */
  timeline: UseTimelineReturn;
  /** Total width in pixels */
  width: number;
  /** Total height in pixels */
  height: number;
  /** Show time ruler */
  showRuler?: boolean;
  /** Show track headers */
  showHeaders?: boolean;
  /** Header width */
  headerWidth?: number;
  /** Ruler height */
  rulerHeight?: number;
  /** On clip click */
  onClipClick?: (trackId: string, clipId: string) => void;
  /** On clip double click */
  onClipDoubleClick?: (trackId: string, clipId: string) => void;
  /** On empty area click */
  onEmptyClick?: (trackId: string, time: Seconds) => void;
  /** On playhead change */
  onPlayheadChange?: (position: Seconds) => void;
}

// ============ Constants ============

// Track colors available for theming
void ['#4a9eff', '#ff6b6b', '#51cf66', '#ffd43b', '#be4bdb', '#20c997', '#ff922b', '#74c0fc'];

const GRID_COLOR = 0x333333;
const GRID_COLOR_BEAT = 0x444444;
const GRID_COLOR_BAR = 0x555555;
const PLAYHEAD_COLOR = 0xff4444;
const LOOP_COLOR = 0x4488ff;
const SELECTION_COLOR = 0x4488ff;

// ============ Component ============

export function Timeline({
  timeline,
  width,
  height,
  showRuler = true,
  showHeaders = true,
  headerWidth = 200,
  rulerHeight = 30,
  onClipClick,
  onClipDoubleClick,
  onEmptyClick,
  onPlayheadChange,
}: TimelineProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLDivElement>(null);
  const appRef = useRef<PIXI.Application | null>(null);
  const graphicsRef = useRef<PIXI.Graphics | null>(null);
  const rafRef = useRef<number>(0);

  // Drag state
  const [isDraggingPlayhead, setIsDraggingPlayhead] = useState(false);
  const [isDraggingClip, setIsDraggingClip] = useState<{
    trackId: string;
    clipId: string;
    startX: number;
    originalStart: number;
  } | null>(null);

  const { state, tracks, markers, timeToPixels, pixelsToTime, setPlayhead, moveClip } = timeline;

  // Canvas dimensions
  const canvasWidth = width - (showHeaders ? headerWidth : 0);
  const canvasHeight = height - (showRuler ? rulerHeight : 0);

  // Initialize PixiJS
  useEffect(() => {
    if (!canvasRef.current) return;

    const initPixi = async () => {
      const app = new PIXI.Application();

      await app.init({
        width: canvasWidth,
        height: canvasHeight,
        backgroundColor: 0x1a1a1a,
        antialias: true,
        resolution: window.devicePixelRatio || 1,
        autoDensity: true,
      });

      canvasRef.current?.appendChild(app.canvas);
      appRef.current = app;

      const graphics = new PIXI.Graphics();
      app.stage.addChild(graphics);
      graphicsRef.current = graphics;
    };

    initPixi();

    return () => {
      if (rafRef.current) {
        cancelAnimationFrame(rafRef.current);
      }
      if (appRef.current) {
        appRef.current.destroy(true, { children: true });
        appRef.current = null;
      }
    };
  }, []);

  // Resize
  useEffect(() => {
    if (appRef.current) {
      appRef.current.renderer.resize(canvasWidth, canvasHeight);
    }
  }, [canvasWidth, canvasHeight]);

  // Calculate track Y positions (used by drawTracks)
  void function getTrackY(index: number): number {
    let y = 0;
    for (let i = 0; i < index; i++) {
      y += tracks[i]?.height || 80;
    }
    return y;
  };

  // Draw grid
  const drawGrid = useCallback(
    (graphics: PIXI.Graphics) => {
      const { visibleStart, visibleEnd, bpm, timeSignatureNum, pixelsPerSecond } = state;
      const beatDuration = 60 / bpm;
      const barDuration = beatDuration * timeSignatureNum;

      // Determine grid density based on zoom
      let gridStep = beatDuration;
      if (pixelsPerSecond < 20) {
        gridStep = barDuration * 4;
      } else if (pixelsPerSecond < 50) {
        gridStep = barDuration;
      } else if (pixelsPerSecond < 100) {
        gridStep = beatDuration;
      } else {
        gridStep = beatDuration / 4;
      }

      // Draw grid lines
      const startBeat = Math.floor(visibleStart / gridStep) * gridStep;

      for (let t = startBeat; t <= visibleEnd; t += gridStep) {
        const x = timeToPixels(t);
        if (x < 0 || x > canvasWidth) continue;

        // Determine line type
        const isBar = Math.abs(t % barDuration) < 0.001;
        const isBeat = Math.abs(t % beatDuration) < 0.001;

        let color = GRID_COLOR;
        let alpha = 0.3;

        if (isBar) {
          color = GRID_COLOR_BAR;
          alpha = 0.6;
        } else if (isBeat) {
          color = GRID_COLOR_BEAT;
          alpha = 0.4;
        }

        graphics.moveTo(x, 0);
        graphics.lineTo(x, canvasHeight);
        graphics.stroke({ width: 1, color, alpha });
      }
    },
    [state, timeToPixels, canvasWidth, canvasHeight]
  );

  // Draw tracks and clips
  const drawTracks = useCallback(
    (graphics: PIXI.Graphics) => {
      let y = 0;

      for (const track of tracks) {
        if (!track.visible) continue;

        const trackHeight = track.height;

        // Track background
        graphics.rect(0, y, canvasWidth, trackHeight);
        graphics.fill({ color: 0x222222, alpha: 0.5 });

        // Track separator
        graphics.moveTo(0, y + trackHeight);
        graphics.lineTo(canvasWidth, y + trackHeight);
        graphics.stroke({ width: 1, color: 0x333333 });

        // Draw clips
        for (const clip of track.clips) {
          drawClip(graphics, clip, track, y);
        }

        y += trackHeight;
      }
    },
    [tracks, canvasWidth]
  );

  // Draw a single clip
  const drawClip = useCallback(
    (graphics: PIXI.Graphics, clip: Clip, track: Track, trackY: number) => {
      const x = timeToPixels(clip.startTime);
      const clipWidth = clip.duration * state.pixelsPerSecond;

      // Skip if not visible
      if (x + clipWidth < 0 || x > canvasWidth) return;

      const clipHeight = track.height - 8;
      const y = trackY + 4;

      // Clip background
      const color = clip.color
        ? parseInt(clip.color.replace('#', ''), 16)
        : parseInt(track.color.replace('#', ''), 16);

      const alpha = clip.muted ? 0.3 : clip.selected ? 0.9 : 0.7;

      graphics.roundRect(x, y, clipWidth, clipHeight, 4);
      graphics.fill({ color, alpha });

      // Selection outline
      if (clip.selected) {
        graphics.roundRect(x, y, clipWidth, clipHeight, 4);
        graphics.stroke({ width: 2, color: 0xffffff });
      }

      // Fade overlays
      if (clip.fadeIn > 0) {
        const fadeWidth = clip.fadeIn * state.pixelsPerSecond;
        graphics.moveTo(x, y);
        graphics.lineTo(x + fadeWidth, y + clipHeight);
        graphics.lineTo(x, y + clipHeight);
        graphics.closePath();
        graphics.fill({ color: 0x000000, alpha: 0.3 });
      }

      if (clip.fadeOut > 0) {
        const fadeWidth = clip.fadeOut * state.pixelsPerSecond;
        const fadeX = x + clipWidth - fadeWidth;
        graphics.moveTo(fadeX, y + clipHeight);
        graphics.lineTo(x + clipWidth, y);
        graphics.lineTo(x + clipWidth, y + clipHeight);
        graphics.closePath();
        graphics.fill({ color: 0x000000, alpha: 0.3 });
      }

      // Muted overlay
      if (clip.muted) {
        graphics.roundRect(x, y, clipWidth, clipHeight, 4);
        graphics.fill({ color: 0x000000, alpha: 0.5 });
      }
    },
    [state.pixelsPerSecond, timeToPixels, canvasWidth]
  );

  // Draw loop region
  const drawLoop = useCallback(
    (graphics: PIXI.Graphics) => {
      if (!state.loopEnabled) return;

      const x1 = timeToPixels(state.loopStart);
      const x2 = timeToPixels(state.loopEnd);

      // Loop region
      graphics.rect(x1, 0, x2 - x1, canvasHeight);
      graphics.fill({ color: LOOP_COLOR, alpha: 0.1 });

      // Loop boundaries
      graphics.moveTo(x1, 0);
      graphics.lineTo(x1, canvasHeight);
      graphics.stroke({ width: 2, color: LOOP_COLOR, alpha: 0.5 });

      graphics.moveTo(x2, 0);
      graphics.lineTo(x2, canvasHeight);
      graphics.stroke({ width: 2, color: LOOP_COLOR, alpha: 0.5 });
    },
    [state.loopEnabled, state.loopStart, state.loopEnd, timeToPixels, canvasHeight]
  );

  // Draw selection
  const drawSelection = useCallback(
    (graphics: PIXI.Graphics) => {
      if (!state.selection) return;

      const x1 = timeToPixels(state.selection.start);
      const x2 = timeToPixels(state.selection.end);

      graphics.rect(x1, 0, x2 - x1, canvasHeight);
      graphics.fill({ color: SELECTION_COLOR, alpha: 0.15 });
    },
    [state.selection, timeToPixels, canvasHeight]
  );

  // Draw markers
  const drawMarkers = useCallback(
    (graphics: PIXI.Graphics) => {
      for (const marker of markers) {
        const x = timeToPixels(marker.position);
        if (x < 0 || x > canvasWidth) continue;

        const color = parseInt(marker.color.replace('#', ''), 16);

        // Marker line
        graphics.moveTo(x, 0);
        graphics.lineTo(x, canvasHeight);
        graphics.stroke({ width: 1, color, alpha: 0.7 });

        // Marker flag
        graphics.moveTo(x, 0);
        graphics.lineTo(x + 10, 0);
        graphics.lineTo(x + 10, 8);
        graphics.lineTo(x, 12);
        graphics.closePath();
        graphics.fill({ color });
      }
    },
    [markers, timeToPixels, canvasWidth, canvasHeight]
  );

  // Draw playhead
  const drawPlayhead = useCallback(
    (graphics: PIXI.Graphics) => {
      const x = timeToPixels(state.playheadPosition);

      // Playhead line
      graphics.moveTo(x, 0);
      graphics.lineTo(x, canvasHeight);
      graphics.stroke({ width: 2, color: PLAYHEAD_COLOR });

      // Playhead head
      graphics.moveTo(x - 6, 0);
      graphics.lineTo(x + 6, 0);
      graphics.lineTo(x, 10);
      graphics.closePath();
      graphics.fill({ color: PLAYHEAD_COLOR });
    },
    [state.playheadPosition, timeToPixels, canvasHeight]
  );

  // Animation loop
  useEffect(() => {
    const draw = () => {
      const graphics = graphicsRef.current;
      if (!graphics) {
        rafRef.current = requestAnimationFrame(draw);
        return;
      }

      graphics.clear();
      drawGrid(graphics);
      drawLoop(graphics);
      drawSelection(graphics);
      drawTracks(graphics);
      drawMarkers(graphics);
      drawPlayhead(graphics);

      rafRef.current = requestAnimationFrame(draw);
    };

    rafRef.current = requestAnimationFrame(draw);

    return () => {
      if (rafRef.current) {
        cancelAnimationFrame(rafRef.current);
      }
    };
  }, [drawGrid, drawLoop, drawSelection, drawTracks, drawMarkers, drawPlayhead]);

  // Mouse handlers
  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      const rect = canvasRef.current?.getBoundingClientRect();
      if (!rect) return;

      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      const time = pixelsToTime(x);

      // Check if clicking on playhead area (top 12px)
      const playheadX = timeToPixels(state.playheadPosition);
      if (y < 12 && Math.abs(x - playheadX) < 10) {
        setIsDraggingPlayhead(true);
        return;
      }

      // Check if clicking on a clip
      let trackY = 0;
      for (const track of tracks) {
        if (!track.visible) continue;

        if (y >= trackY && y < trackY + track.height) {
          // Check clips
          for (const clip of track.clips) {
            const clipX = timeToPixels(clip.startTime);
            const clipWidth = clip.duration * state.pixelsPerSecond;

            if (x >= clipX && x <= clipX + clipWidth) {
              if (e.detail === 2) {
                onClipDoubleClick?.(track.id, clip.id);
              } else {
                onClipClick?.(track.id, clip.id);
                setIsDraggingClip({
                  trackId: track.id,
                  clipId: clip.id,
                  startX: x,
                  originalStart: clip.startTime,
                });
              }
              return;
            }
          }

          // Clicked on empty area
          onEmptyClick?.(track.id, time);
          setPlayhead(time);
          onPlayheadChange?.(time);
          return;
        }

        trackY += track.height;
      }

      // Clicked below tracks - set playhead
      setPlayhead(time);
      onPlayheadChange?.(time);
    },
    [
      pixelsToTime,
      timeToPixels,
      state.playheadPosition,
      state.pixelsPerSecond,
      tracks,
      setPlayhead,
      onClipClick,
      onClipDoubleClick,
      onEmptyClick,
      onPlayheadChange,
    ]
  );

  const handleMouseMove = useCallback(
    (e: React.MouseEvent) => {
      const rect = canvasRef.current?.getBoundingClientRect();
      if (!rect) return;

      const x = e.clientX - rect.left;
      const time = pixelsToTime(x);

      if (isDraggingPlayhead) {
        setPlayhead(time);
        onPlayheadChange?.(time);
      } else if (isDraggingClip) {
        const delta = (x - isDraggingClip.startX) / state.pixelsPerSecond;
        const newStart = Math.max(0, isDraggingClip.originalStart + delta);
        moveClip(isDraggingClip.trackId, isDraggingClip.clipId, newStart);
      }
    },
    [isDraggingPlayhead, isDraggingClip, pixelsToTime, setPlayhead, moveClip, state.pixelsPerSecond, onPlayheadChange]
  );

  const handleMouseUp = useCallback(() => {
    setIsDraggingPlayhead(false);
    setIsDraggingClip(null);
  }, []);

  // Wheel zoom
  const handleWheel = useCallback(
    (e: React.WheelEvent) => {
      if (e.ctrlKey || e.metaKey) {
        e.preventDefault();
        if (e.deltaY < 0) {
          timeline.zoomIn();
        } else {
          timeline.zoomOut();
        }
      } else {
        // Horizontal scroll
        const scrollAmount = e.deltaX || e.deltaY;
        const timeScroll = scrollAmount / state.pixelsPerSecond;
        timeline.setVisibleRange(
          state.visibleStart + timeScroll,
          state.visibleEnd + timeScroll
        );
      }
    },
    [timeline, state.pixelsPerSecond, state.visibleStart, state.visibleEnd]
  );

  // Render time ruler
  const renderRuler = () => {
    if (!showRuler) return null;

    const { visibleStart, visibleEnd, bpm, timeSignatureNum, pixelsPerSecond } = state;
    const beatDuration = 60 / bpm;
    const barDuration = beatDuration * timeSignatureNum;

    // Determine label density
    let labelStep = barDuration;
    if (pixelsPerSecond < 20) {
      labelStep = barDuration * 4;
    } else if (pixelsPerSecond > 100) {
      labelStep = beatDuration;
    }

    const labels: React.ReactElement[] = [];
    const startLabel = Math.floor(visibleStart / labelStep) * labelStep;

    for (let t = startLabel; t <= visibleEnd; t += labelStep) {
      const x = timeToPixels(t) + (showHeaders ? headerWidth : 0);
      const bbt = secondsToBarsBeatsTicks(t, bpm, timeSignatureNum);

      labels.push(
        <div
          key={t}
          className="timeline-ruler__label"
          style={{ left: `${x}px` }}
        >
          <span className="timeline-ruler__time">{formatTime(t)}</span>
          <span className="timeline-ruler__bbt">{formatBarsBeatsTicks(bbt)}</span>
        </div>
      );
    }

    return (
      <div className="timeline-ruler" style={{ height: rulerHeight }}>
        {showHeaders && (
          <div className="timeline-ruler__header" style={{ width: headerWidth }}>
            <span className="timeline-ruler__bpm">{bpm} BPM</span>
          </div>
        )}
        <div className="timeline-ruler__track">{labels}</div>
      </div>
    );
  };

  // Render track headers
  const renderHeaders = () => {
    if (!showHeaders) return null;

    return (
      <div className="timeline-headers" style={{ width: headerWidth }}>
        {tracks.map((track) => (
          <div
            key={track.id}
            className={`timeline-header ${track.muted ? 'muted' : ''} ${track.solo ? 'solo' : ''}`}
            style={{
              height: track.height,
              borderLeftColor: track.color,
            }}
          >
            <div className="timeline-header__name">{track.name}</div>
            <div className="timeline-header__controls">
              <button
                className={`timeline-header__btn ${track.muted ? 'active' : ''}`}
                onClick={() => timeline.muteTrack(track.id, !track.muted)}
                title="Mute"
              >
                M
              </button>
              <button
                className={`timeline-header__btn ${track.solo ? 'active' : ''}`}
                onClick={() => timeline.soloTrack(track.id, !track.solo)}
                title="Solo"
              >
                S
              </button>
            </div>
          </div>
        ))}
      </div>
    );
  };

  return (
    <div
      ref={containerRef}
      className="timeline"
      style={{ width, height }}
    >
      {renderRuler()}
      <div className="timeline-content">
        {renderHeaders()}
        <div
          ref={canvasRef}
          className="timeline-canvas"
          style={{ width: canvasWidth, height: canvasHeight }}
          onMouseDown={handleMouseDown}
          onMouseMove={handleMouseMove}
          onMouseUp={handleMouseUp}
          onMouseLeave={handleMouseUp}
          onWheel={handleWheel}
        />
      </div>
    </div>
  );
}

export default Timeline;
