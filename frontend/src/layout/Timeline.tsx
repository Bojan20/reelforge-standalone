/**
 * ReelForge Timeline
 *
 * Cubase/Pro Tools style timeline with:
 * - Time ruler (bars, timecode, samples)
 * - Waveform display
 * - Track lanes
 * - Playhead
 * - Loop region
 * - Markers
 * - Zoom/scroll
 *
 * @module layout/Timeline
 */

import { memo, useState, useCallback, useRef, useEffect, useMemo } from 'react';
import { useDropTarget, useDragState, type DropTarget, type DragItem } from '../core/dragDropSystem';

// ============ Types ============

export interface TimelineClip {
  id: string;
  trackId: string;
  name: string;
  startTime: number; // in seconds
  duration: number;
  color?: string;
  /** Waveform data (normalized 0 to 1 peaks) - used as fallback */
  waveform?: Float32Array | number[];
  /** AudioBuffer for high-resolution zoom-dependent waveform (Cubase-style LOD) */
  audioBuffer?: AudioBuffer;
  /** Reference to the source audio file ID in the pool */
  audioFileId?: string;
  /** Offset within source (for left-edge trim) */
  sourceOffset?: number;
  /** Original source audio duration (immutable) - for constraining right-edge trim */
  sourceDuration?: number;
  /** Fade in duration in seconds */
  fadeIn?: number;
  /** Fade out duration in seconds */
  fadeOut?: number;
  /** Clip gain (0-2, 1 = unity) */
  gain?: number;
  /** Is muted */
  muted?: boolean;
  /** Is selected */
  selected?: boolean;
}

export interface TimelineTrack {
  id: string;
  name: string;
  color?: string;
  height?: number;
  muted?: boolean;
  soloed?: boolean;
  armed?: boolean;
  locked?: boolean;
  /** Output bus routing */
  outputBus?: 'master' | 'music' | 'sfx' | 'ambience' | 'voice';
  /** Input monitoring enabled */
  inputMonitor?: boolean;
  /** Track frozen (bounced to audio, edits disabled) */
  frozen?: boolean;
  /** Track volume (0-1, 1 = unity) */
  volume?: number;
  /** Track pan (-1 to 1, 0 = center) */
  pan?: number;
}

export interface TimelineMarker {
  id: string;
  time: number;
  name: string;
  color?: string;
}

export interface TimelineRegion {
  id: string;
  startTime: number;
  endTime: number;
  name?: string;
  color?: string;
}

export interface Crossfade {
  id: string;
  trackId: string;
  /** First clip (fades out) */
  clipAId: string;
  /** Second clip (fades in) */
  clipBId: string;
  /** Start time of crossfade region */
  startTime: number;
  /** Duration of crossfade */
  duration: number;
  /** Crossfade curve type */
  curveType?: 'linear' | 'equal-power' | 's-curve';
}

export interface TimelineProps {
  /** Tracks */
  tracks: TimelineTrack[];
  /** Clips on tracks */
  clips: TimelineClip[];
  /** Markers */
  markers?: TimelineMarker[];
  /** Loop region */
  loopRegion?: { start: number; end: number } | null;
  /** Current playhead position in seconds */
  playheadPosition: number;
  /** Tempo in BPM */
  tempo?: number;
  /** Time signature */
  timeSignature?: [number, number];
  /** Zoom level (pixels per second) */
  zoom?: number;
  /** Scroll offset in seconds */
  scrollOffset?: number;
  /** Total duration in seconds */
  totalDuration?: number;
  /** Time display mode */
  timeDisplayMode?: 'bars' | 'timecode' | 'samples';
  /** Sample rate for samples display */
  sampleRate?: number;
  /** On playhead change */
  onPlayheadChange?: (time: number) => void;
  /** On clip select */
  onClipSelect?: (clipId: string, multiSelect?: boolean) => void;
  /** On clip move */
  onClipMove?: (clipId: string, newStartTime: number, newTrackId?: string) => void;
  /** On clip resize (trim) - newStartTime, newDuration, and optionally newOffset for left-edge trim */
  onClipResize?: (clipId: string, newStartTime: number, newDuration: number, newOffset?: number) => void;
  /** On clip slip edit - change sourceOffset without moving clip (Cmd+drag) */
  onClipSlipEdit?: (clipId: string, newSourceOffset: number) => void;
  /** On zoom change */
  onZoomChange?: (zoom: number) => void;
  /** On scroll change */
  onScrollChange?: (offset: number) => void;
  /** On loop region change */
  onLoopRegionChange?: (region: { start: number; end: number } | null) => void;
  /** Loop enabled state */
  loopEnabled?: boolean;
  /** On loop toggle (click on loop region) */
  onLoopToggle?: () => void;
  /** On track mute toggle */
  onTrackMuteToggle?: (trackId: string) => void;
  /** On track solo toggle */
  onTrackSoloToggle?: (trackId: string) => void;
  /** On track select (for channel strip) */
  onTrackSelect?: (trackId: string) => void;
  /** On audio drop - create new clip from dropped audio */
  onAudioDrop?: (trackId: string, time: number, audioItem: DragItem) => void;
  /** On audio drop to create new track - called when dropping on empty area */
  onNewTrackDrop?: (time: number, audioItem: DragItem) => void;
  /** Unique ID for this timeline instance (prevents duplicate drops when multiple Timelines exist) */
  instanceId?: string;

  // ===== DAW Features =====
  /** Snap enabled */
  snapEnabled?: boolean;
  /** Snap value in beats (0.25 = 16th, 0.5 = 8th, 1 = quarter, 4 = bar) */
  snapValue?: number;
  /** On snap toggle */
  onSnapToggle?: () => void;
  /** On snap value change */
  onSnapValueChange?: (value: number) => void;
  /** On clip split at playhead */
  onClipSplit?: (clipId: string, splitTime: number) => void;
  /** On clip duplicate */
  onClipDuplicate?: (clipId: string) => void;
  /** On clip gain change */
  onClipGainChange?: (clipId: string, gain: number) => void;
  /** On clip fade change */
  onClipFadeChange?: (clipId: string, fadeIn: number, fadeOut: number) => void;
  /** On track color change */
  onTrackColorChange?: (trackId: string, color: string) => void;
  /** Selected clip IDs */
  selectedClipIds?: string[];
  /** Time selection region */
  timeSelection?: { start: number; end: number } | null;
  /** On time selection change */
  onTimeSelectionChange?: (selection: { start: number; end: number } | null) => void;
  /** On marker click (navigation) */
  onMarkerClick?: (markerId: string) => void;
  /** On track bus routing change */
  onTrackBusChange?: (trackId: string, bus: 'master' | 'music' | 'sfx' | 'ambience' | 'voice') => void;
  /** On clip delete */
  onClipDelete?: (clipId: string) => void;
  /** On clip copy */
  onClipCopy?: (clipId: string) => void;
  /** On clip paste at playhead position */
  onClipPaste?: () => void;
  /** On track rename (double-click) */
  onTrackRename?: (trackId: string, newName: string) => void;
  /** On track arm toggle */
  onTrackArmToggle?: (trackId: string) => void;
  /** On track input monitor toggle */
  onTrackMonitorToggle?: (trackId: string) => void;
  /** On track freeze toggle */
  onTrackFreezeToggle?: (trackId: string) => void;
  /** On track lock toggle */
  onTrackLockToggle?: (trackId: string) => void;
  /** On track volume change */
  onTrackVolumeChange?: (trackId: string, volume: number) => void;
  /** On track pan change */
  onTrackPanChange?: (trackId: string, pan: number) => void;
  /** On clip rename (double-click) */
  onClipRename?: (clipId: string, newName: string) => void;
  /** Crossfades between clips */
  crossfades?: Crossfade[];
  /** On crossfade create (when clips overlap) */
  onCrossfadeCreate?: (crossfade: Omit<Crossfade, 'id'>) => void;
  /** On crossfade update (drag to adjust duration) */
  onCrossfadeUpdate?: (crossfadeId: string, duration: number) => void;
  /** On crossfade delete */
  onCrossfadeDelete?: (crossfadeId: string) => void;
}

// ============ Waveform Renderer (RMS + Peak) ============

interface WaveformProps {
  /** Pre-computed waveform peaks (fallback) */
  data?: Float32Array | number[];
  /** AudioBuffer for zoom-dependent LOD rendering (Cubase-style) */
  audioBuffer?: AudioBuffer;
  /** Source offset in seconds (for trimmed clips) */
  sourceOffset?: number;
  /** Duration to display in seconds */
  duration?: number;
  width: number;
  height: number;
  color?: string;
  opacity?: number;
  /** Show RMS (filled) + Peak (outline) like Cubase/Pro Tools */
  showRMS?: boolean;
}

/**
 * Cubase-style LOD Waveform Component
 *
 * When audioBuffer is provided, renders directly from audio samples
 * at the appropriate resolution for the current zoom level.
 * This shows more transient detail when zoomed in.
 *
 * Falls back to pre-computed waveform data if no buffer available.
 */
const Waveform = memo(function Waveform({
  data,
  audioBuffer,
  sourceOffset = 0,
  duration,
  width,
  height,
  color = '#4a9eff',
  opacity = 0.8,
  showRMS = true,
}: WaveformProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Get CSS variable colors (with fallback to prop/default)
    const computedStyle = getComputedStyle(document.documentElement);
    const waveformFill = computedStyle.getPropertyValue('--rf-waveform-fill').trim() || color;
    const waveformRms = computedStyle.getPropertyValue('--rf-waveform-rms').trim() || color;
    const waveformClip = computedStyle.getPropertyValue('--rf-waveform-clip').trim() || '#ff3366';

    // Set canvas size with device pixel ratio for crisp rendering
    const dpr = window.devicePixelRatio || 1;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.scale(dpr, dpr);

    // Clear
    ctx.clearRect(0, 0, width, height);

    const centerY = height / 2;

    // Determine data source: AudioBuffer (LOD) or pre-computed peaks
    let samples: Float32Array | number[];
    let isSigned = false; // AudioBuffer samples are signed (-1 to 1), pre-computed are unsigned (0 to 1)

    if (audioBuffer) {
      // LOD mode: Read directly from AudioBuffer at zoom-appropriate resolution
      const channelData = audioBuffer.getChannelData(0);
      const sampleRate = audioBuffer.sampleRate;

      // Calculate sample range based on sourceOffset and duration
      const startSample = Math.floor(sourceOffset * sampleRate);
      const clipDuration = duration ?? audioBuffer.duration - sourceOffset;
      const endSample = Math.min(
        channelData.length,
        Math.floor((sourceOffset + clipDuration) * sampleRate)
      );

      // For LOD: we want roughly 1-4 samples per pixel for detailed view
      // This automatically adapts to zoom level via width
      const totalSamples = endSample - startSample;
      const targetSamplesPerPixel = Math.max(1, Math.floor(totalSamples / width));

      // Downsample to width pixels
      const peaks: number[] = [];
      for (let x = 0; x < width; x++) {
        const sampleStart = startSample + Math.floor(x * totalSamples / width);
        const sampleEnd = Math.min(endSample, sampleStart + targetSamplesPerPixel);

        let min = 0;
        let max = 0;
        for (let i = sampleStart; i < sampleEnd; i++) {
          const val = channelData[i];
          if (val < min) min = val;
          if (val > max) max = val;
        }
        // Store both min and max for signed waveform display
        peaks.push(max, min);
      }

      samples = peaks;
      isSigned = true;
    } else if (data && data.length > 0) {
      // Fallback: use pre-computed peaks
      samples = data;
      isSigned = false;
    } else {
      return; // No data to render
    }

    // Render waveform
    if (isSigned) {
      // Signed samples from AudioBuffer (pairs of max, min)
      const numPixels = samples.length / 2;

      if (showRMS) {
        // RMS layer (approximate from peaks)
        ctx.fillStyle = waveformRms;
        ctx.globalAlpha = opacity * 0.9;

        for (let x = 0; x < numPixels; x++) {
          const max = samples[x * 2] as number;
          const min = samples[x * 2 + 1] as number;
          const amplitude = (Math.abs(max) + Math.abs(min)) / 2;
          const rmsApprox = amplitude * 0.707; // RMS approximation
          const rmsHeight = rmsApprox * centerY * 1.8;
          const top = centerY - rmsHeight;
          ctx.fillRect(x, top, 1, Math.max(1, rmsHeight * 2));
        }

        // Peak layer
        ctx.fillStyle = waveformFill;
        ctx.globalAlpha = opacity * 0.6;

        for (let x = 0; x < numPixels; x++) {
          const max = samples[x * 2] as number;
          const min = samples[x * 2 + 1] as number;
          const peakTop = centerY - max * centerY;
          const peakBottom = centerY - min * centerY;
          const barHeight = Math.max(1, peakBottom - peakTop);

          // Clip detection
          if (Math.abs(max) >= 0.99 || Math.abs(min) >= 0.99) {
            ctx.fillStyle = waveformClip;
          }
          ctx.fillRect(x, peakTop, 1, barHeight);
          if (Math.abs(max) >= 0.99 || Math.abs(min) >= 0.99) {
            ctx.fillStyle = waveformFill;
          }
        }
      } else {
        // Simple peak display
        ctx.fillStyle = waveformFill;
        ctx.globalAlpha = opacity;

        for (let x = 0; x < numPixels; x++) {
          const max = samples[x * 2] as number;
          const min = samples[x * 2 + 1] as number;
          const peakTop = centerY - max * centerY;
          const peakBottom = centerY - min * centerY;
          ctx.fillRect(x, peakTop, 1, Math.max(1, peakBottom - peakTop));
        }
      }
    } else {
      // Unsigned pre-computed peaks (0 to 1)
      const samplesPerPixel = Math.max(1, Math.ceil(samples.length / width));

      const peakValues: { min: number; max: number; clipped: boolean }[] = [];
      const rmsValues: number[] = [];

      for (let x = 0; x < width; x++) {
        const startSample = Math.floor(x * samplesPerPixel);
        const endSample = Math.min(startSample + samplesPerPixel, samples.length);

        let max = 0;
        let sumSquares = 0;
        let count = 0;
        let clipped = false;

        for (let i = startSample; i < endSample; i++) {
          const val = samples[i] as number;
          if (val > max) max = val;
          sumSquares += val * val;
          count++;
          if (val >= 0.99) clipped = true;
        }

        // For unsigned data, mirror around center
        peakValues.push({ min: -max, max, clipped });
        rmsValues.push(count > 0 ? Math.sqrt(sumSquares / count) : 0);
      }

      if (showRMS) {
        ctx.fillStyle = waveformRms;
        ctx.globalAlpha = opacity * 0.9;

        for (let x = 0; x < width; x++) {
          const rms = rmsValues[x];
          const rmsHeight = rms * centerY * 1.8;
          ctx.fillRect(x, centerY - rmsHeight, 1, Math.max(1, rmsHeight * 2));
        }

        ctx.fillStyle = waveformFill;
        ctx.globalAlpha = opacity * 0.5;

        for (let x = 0; x < width; x++) {
          const { max, clipped } = peakValues[x];
          const rms = rmsValues[x];
          const rmsHeight = rms * centerY * 1.8;

          if (clipped) {
            ctx.fillStyle = waveformClip;
            ctx.globalAlpha = opacity * 0.8;
          }

          if (max * centerY > rmsHeight) {
            ctx.fillRect(x, centerY - max * centerY, 1, max * centerY - rmsHeight);
            ctx.fillRect(x, centerY + rmsHeight, 1, max * centerY - rmsHeight);
          }

          if (clipped) {
            ctx.fillStyle = waveformFill;
            ctx.globalAlpha = opacity * 0.5;
          }
        }
      } else {
        ctx.fillStyle = waveformFill;
        ctx.globalAlpha = opacity;

        for (let x = 0; x < width; x++) {
          const { max, clipped } = peakValues[x];
          if (clipped) ctx.fillStyle = waveformClip;
          ctx.fillRect(x, centerY - max * centerY, 1, Math.max(1, max * centerY * 2));
          if (clipped) ctx.fillStyle = waveformFill;
        }
      }
    }
  }, [data, audioBuffer, sourceOffset, duration, width, height, color, opacity, showRMS]);

  return (
    <canvas
      ref={canvasRef}
      style={{ width, height, display: 'block' }}
    />
  );
});

// ============ Time Ruler ============

interface TimeRulerProps {
  width: number;
  zoom: number;
  scrollOffset: number;
  tempo: number;
  timeSignature: [number, number];
  timeDisplayMode: 'bars' | 'timecode' | 'samples';
  sampleRate: number;
  loopRegion?: { start: number; end: number } | null;
  loopEnabled?: boolean;
  onTimeClick?: (time: number) => void;
  onLoopToggle?: () => void;
}

const TimeRuler = memo(function TimeRuler({
  width,
  zoom,
  scrollOffset,
  tempo,
  timeSignature,
  timeDisplayMode,
  sampleRate,
  loopRegion,
  loopEnabled,
  onTimeClick,
  onLoopToggle,
}: TimeRulerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  // Calculate visible time range
  const visibleDuration = width / zoom;
  const startTime = scrollOffset;
  const endTime = scrollOffset + visibleDuration;

  // Format time based on mode
  const formatTime = useCallback((seconds: number): string => {
    if (timeDisplayMode === 'bars') {
      const beatsPerSecond = tempo / 60;
      const totalBeats = seconds * beatsPerSecond;
      const bar = Math.floor(totalBeats / timeSignature[0]) + 1;
      const beat = Math.floor(totalBeats % timeSignature[0]) + 1;
      return `${bar}.${beat}`;
    } else if (timeDisplayMode === 'timecode') {
      const mins = Math.floor(seconds / 60);
      const secs = Math.floor(seconds % 60);
      const frames = Math.floor((seconds % 1) * 30); // 30fps
      return `${mins}:${secs.toString().padStart(2, '0')}:${frames.toString().padStart(2, '0')}`;
    } else {
      return Math.floor(seconds * sampleRate).toLocaleString();
    }
  }, [timeDisplayMode, tempo, timeSignature, sampleRate]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const RULER_HEIGHT = 28;
    const dpr = window.devicePixelRatio;
    canvas.width = width * dpr;
    canvas.height = RULER_HEIGHT * dpr;
    ctx.scale(dpr, dpr);

    // Clear
    ctx.fillStyle = '#1a1a1a';
    ctx.fillRect(0, 0, width, RULER_HEIGHT);

    // Draw loop region
    if (loopRegion) {
      const loopStartX = (loopRegion.start - scrollOffset) * zoom;
      const loopEndX = (loopRegion.end - scrollOffset) * zoom;
      const loopWidth = loopEndX - loopStartX;

      // Different styling based on enabled state
      if (loopEnabled) {
        // Active loop - filled with border
        ctx.fillStyle = 'rgba(74, 158, 255, 0.35)';
        ctx.fillRect(loopStartX, 0, loopWidth, RULER_HEIGHT);
        // Top border
        ctx.fillStyle = 'rgba(74, 158, 255, 0.9)';
        ctx.fillRect(loopStartX, 0, loopWidth, 2);
        // Left/right brackets
        ctx.fillRect(loopStartX, 0, 2, RULER_HEIGHT);
        ctx.fillRect(loopEndX - 2, 0, 2, RULER_HEIGHT);
      } else {
        // Inactive loop - dimmed with dashed appearance
        ctx.fillStyle = 'rgba(100, 100, 100, 0.15)';
        ctx.fillRect(loopStartX, 0, loopWidth, RULER_HEIGHT);
        // Dim border
        ctx.fillStyle = 'rgba(100, 100, 100, 0.4)';
        ctx.fillRect(loopStartX, 0, loopWidth, 1);
      }
    }

    // Calculate tick interval based on zoom
    let tickInterval: number;
    if (timeDisplayMode === 'bars') {
      const beatsPerSecond = tempo / 60;
      const beatDuration = 1 / beatsPerSecond;
      const barDuration = beatDuration * timeSignature[0];

      if (zoom < 20) {
        tickInterval = barDuration * 4;
      } else if (zoom < 50) {
        tickInterval = barDuration;
      } else if (zoom < 150) {
        tickInterval = beatDuration;
      } else {
        tickInterval = beatDuration / 4;
      }
    } else {
      if (zoom < 10) tickInterval = 10;
      else if (zoom < 30) tickInterval = 5;
      else if (zoom < 80) tickInterval = 1;
      else if (zoom < 200) tickInterval = 0.5;
      else tickInterval = 0.1;
    }

    // Draw ticks
    ctx.fillStyle = '#666';
    ctx.font = '10px system-ui';
    ctx.textAlign = 'center';

    const firstTick = Math.floor(startTime / tickInterval) * tickInterval;

    for (let t = firstTick; t <= endTime; t += tickInterval) {
      const x = (t - scrollOffset) * zoom;
      if (x < 0 || x > width) continue;

      // Major tick
      ctx.fillStyle = '#555';
      ctx.fillRect(x, 16, 1, 8);

      // Label
      ctx.fillStyle = '#888';
      ctx.fillText(formatTime(t), x, 12);
    }

    // Border
    ctx.fillStyle = '#333';
    ctx.fillRect(0, 23, width, 1);
  }, [width, zoom, scrollOffset, tempo, timeSignature, timeDisplayMode, sampleRate, loopRegion, loopEnabled, formatTime, startTime, endTime]);

  const handleClick = useCallback((e: React.MouseEvent) => {
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect) return;
    const x = e.clientX - rect.left;
    const time = scrollOffset + x / zoom;

    // Check if click is within loop region - toggle loop
    if (loopRegion && onLoopToggle) {
      const loopStartX = (loopRegion.start - scrollOffset) * zoom;
      const loopEndX = (loopRegion.end - scrollOffset) * zoom;
      if (x >= loopStartX && x <= loopEndX) {
        onLoopToggle();
        return;
      }
    }

    // Otherwise, set playhead
    onTimeClick?.(Math.max(0, time));
  }, [scrollOffset, zoom, onTimeClick, loopRegion, onLoopToggle]);

  return (
    <canvas
      ref={canvasRef}
      style={{ width, height: 28, cursor: 'pointer' }}
      onClick={handleClick}
      title={loopRegion ? 'Click on loop region to toggle loop, or click elsewhere to set playhead' : 'Click to set playhead'}
    />
  );
});

// ============ Snap Utilities ============

export type SnapType = 'grid' | 'grid-relative' | 'events' | 'magnetic-cursor';

export interface SnapConfig {
  enabled: boolean;
  /** Snap value in beats (0.25 = 16th, 0.5 = 8th, 1 = quarter, 4 = bar) */
  value: number;
  type: SnapType;
}

/**
 * Snap time to grid based on tempo and snap value.
 * @param time Time in seconds
 * @param snapValue Snap value in beats (e.g., 1 = quarter note)
 * @param tempo Tempo in BPM
 * @returns Snapped time in seconds
 */
export function snapToGrid(time: number, snapValue: number, tempo: number): number {
  const beatsPerSecond = tempo / 60;
  const gridInterval = snapValue / beatsPerSecond; // Snap interval in seconds
  return Math.round(time / gridInterval) * gridInterval;
}

/**
 * Snap time to nearest event boundary.
 * @param time Time in seconds
 * @param clips All clips to consider
 * @param threshold Max distance in seconds to snap
 * @returns Snapped time or original if no nearby event
 */
export function snapToEvents(
  time: number,
  clips: TimelineClip[],
  threshold: number = 0.1
): number {
  let nearestTime = time;
  let nearestDistance = threshold;

  for (const clip of clips) {
    // Check clip start
    const startDist = Math.abs(clip.startTime - time);
    if (startDist < nearestDistance) {
      nearestDistance = startDist;
      nearestTime = clip.startTime;
    }

    // Check clip end
    const endTime = clip.startTime + clip.duration;
    const endDist = Math.abs(endTime - time);
    if (endDist < nearestDistance) {
      nearestDistance = endDist;
      nearestTime = endTime;
    }
  }

  return nearestTime;
}

/**
 * Apply snap based on configuration.
 * Tries event snap first (if within threshold), then grid snap.
 */
export function applySnap(
  time: number,
  snapEnabled: boolean,
  snapValue: number,
  tempo: number,
  clips: TimelineClip[] = [],
  eventSnapThreshold: number = 0.05
): number {
  if (!snapEnabled) return time;

  // First, try event snap (higher priority for small movements)
  const eventSnapped = snapToEvents(time, clips, eventSnapThreshold);
  if (eventSnapped !== time) {
    return eventSnapped;
  }

  // Fall back to grid snap
  return snapToGrid(time, snapValue, tempo);
}

// ============ Waveform Path Generation ============

/**
 * Generate SVG path string from waveform data for ghost clip preview
 */
function generateWaveformPath(
  waveform: number[] | Float32Array,
  width: number,
  height: number
): string {
  if (!waveform || waveform.length === 0) return '';

  const samples = Array.isArray(waveform) ? waveform : Array.from(waveform);
  const step = Math.max(1, Math.floor(samples.length / width));
  const midY = height / 2;

  let path = `M 0 ${midY}`;

  for (let i = 0; i < width; i++) {
    const sampleIndex = Math.min(i * step, samples.length - 1);
    const sample = Math.abs(samples[sampleIndex]);
    const y = midY - sample * midY * 0.9; // Scale to fit
    path += ` L ${i} ${y}`;
  }

  // Close the path (mirror for full waveform look)
  for (let i = width - 1; i >= 0; i--) {
    const sampleIndex = Math.min(i * step, samples.length - 1);
    const sample = Math.abs(samples[sampleIndex]);
    const y = midY + sample * midY * 0.9;
    path += ` L ${i} ${y}`;
  }

  path += ' Z';
  return path;
}

// ============ Track Colors ============

const TRACK_COLORS = [
  '#4a9eff', '#ff6b6b', '#51cf66', '#ffd43b', '#845ef7',
  '#ff922b', '#22b8cf', '#f06595', '#94d82d', '#be4bdb',
  '#339af0', '#20c997', '#fab005', '#748ffc', '#69db7c',
];

// ============ Bus Options ============

const BUS_OPTIONS = [
  { id: 'master', name: 'Master', color: '#888' },
  { id: 'music', name: 'Music', color: '#4a9eff' },
  { id: 'sfx', name: 'SFX', color: '#ff6b6b' },
  { id: 'voice', name: 'Voice', color: '#51cf66' },
  { id: 'ambience', name: 'Amb', color: '#ffd43b' },
] as const;

// ============ Track Header ============

interface TrackHeaderProps {
  track: TimelineTrack;
  height: number;
  onMuteToggle?: () => void;
  onSoloToggle?: () => void;
  onArmToggle?: () => void;
  onMonitorToggle?: () => void;
  onFreezeToggle?: () => void;
  onLockToggle?: () => void;
  onVolumeChange?: (volume: number) => void;
  onPanChange?: (pan: number) => void;
  onClick?: () => void;
  onColorChange?: (color: string) => void;
  onBusChange?: (bus: 'master' | 'music' | 'sfx' | 'ambience' | 'voice') => void;
  onRename?: (newName: string) => void;
}

const TrackHeader = memo(function TrackHeader({
  track,
  height,
  onMuteToggle,
  onSoloToggle,
  onArmToggle,
  onMonitorToggle,
  onFreezeToggle,
  onLockToggle,
  onVolumeChange,
  onPanChange,
  onClick,
  onColorChange,
  onBusChange,
  onRename,
}: TrackHeaderProps) {
  const [showColorPicker, setShowColorPicker] = useState(false);
  const [isEditing, setIsEditing] = useState(false);
  const [editName, setEditName] = useState(track.name);
  const inputRef = useRef<HTMLInputElement>(null);
  const currentBus = BUS_OPTIONS.find(b => b.id === (track.outputBus || 'master')) || BUS_OPTIONS[0];

  // Volume in dB for display
  const volumeDb = track.volume !== undefined && track.volume > 0
    ? 20 * Math.log10(track.volume)
    : -Infinity;
  const volumeDisplay = volumeDb <= -60 ? '-∞' : volumeDb.toFixed(1);

  // Pan display
  const panValue = track.pan ?? 0;
  const panDisplay = panValue === 0 ? 'C' : panValue < 0 ? `L${Math.abs(Math.round(panValue * 100))}` : `R${Math.round(panValue * 100)}`;

  // Focus input when editing starts
  useEffect(() => {
    if (isEditing && inputRef.current) {
      inputRef.current.focus();
      inputRef.current.select();
    }
  }, [isEditing]);

  const handleDoubleClick = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    setEditName(track.name);
    setIsEditing(true);
  }, [track.name]);

  const handleSubmit = useCallback(() => {
    const trimmed = editName.trim();
    if (trimmed && trimmed !== track.name) {
      onRename?.(trimmed);
    }
    setIsEditing(false);
  }, [editName, track.name, onRename]);

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      handleSubmit();
    } else if (e.key === 'Escape') {
      setIsEditing(false);
      setEditName(track.name);
    }
  }, [handleSubmit, track.name]);

  return (
    <div
      className={`rf-timeline__track-header ${track.locked ? 'rf-timeline__track-header--locked' : ''} ${track.frozen ? 'rf-timeline__track-header--frozen' : ''}`}
      style={{
        height,
        borderLeft: `3px solid ${track.color || '#4a9eff'}`,
      }}
      onClick={onClick}
      onContextMenu={(e) => {
        e.preventDefault();
        setShowColorPicker(true);
      }}
    >
      {/* Top row: Name + main controls */}
      <div className="rf-timeline__track-header-top">
        {isEditing ? (
          <input
            ref={inputRef}
            className="rf-timeline__track-name-input"
            type="text"
            value={editName}
            onChange={(e) => setEditName(e.target.value)}
            onBlur={handleSubmit}
            onKeyDown={handleKeyDown}
            onClick={(e) => e.stopPropagation()}
          />
        ) : (
          <span
            className="rf-timeline__track-name"
            onDoubleClick={handleDoubleClick}
            title="Double-click to rename"
          >
            {track.name}
          </span>
        )}

        {/* Primary Controls: M S R */}
        <div className="rf-timeline__track-controls">
          <button
            className={`rf-timeline__track-btn rf-timeline__track-btn--mute ${track.muted ? 'active' : ''}`}
            onClick={(e) => { e.stopPropagation(); onMuteToggle?.(); }}
            title="Mute (M)"
          >
            M
          </button>
          <button
            className={`rf-timeline__track-btn rf-timeline__track-btn--solo ${track.soloed ? 'active' : ''}`}
            onClick={(e) => { e.stopPropagation(); onSoloToggle?.(); }}
            title="Solo (S)"
          >
            S
          </button>
          <button
            className={`rf-timeline__track-btn rf-timeline__track-btn--arm ${track.armed ? 'active' : ''}`}
            onClick={(e) => { e.stopPropagation(); onArmToggle?.(); }}
            title="Record Arm (R)"
          >
            R
          </button>
        </div>
      </div>

      {/* Bottom row: Compact Volume/Pan + Bus indicator */}
      <div className="rf-timeline__track-header-bottom">
        {/* Compact Volume/Pan strip */}
        <div className="rf-timeline__track-fader-strip">
          <input
            type="range"
            min="0"
            max="100"
            value={Math.round((track.volume ?? 1) * 100)}
            onChange={(e) => {
              e.stopPropagation();
              onVolumeChange?.(parseInt(e.target.value) / 100);
            }}
            onClick={(e) => e.stopPropagation()}
            onDoubleClick={(e) => {
              e.stopPropagation();
              onVolumeChange?.(1); // Reset to unity
            }}
            className="rf-timeline__track-volume-slider"
            title={`Volume: ${volumeDisplay} dB (double-click to reset)`}
          />
          <span className="rf-timeline__track-fader-value">{volumeDisplay}</span>
          <input
            type="range"
            min="-100"
            max="100"
            value={Math.round(panValue * 100)}
            onChange={(e) => {
              e.stopPropagation();
              onPanChange?.(parseInt(e.target.value) / 100);
            }}
            onClick={(e) => e.stopPropagation()}
            onDoubleClick={(e) => {
              e.stopPropagation();
              onPanChange?.(0); // Reset to center
            }}
            className="rf-timeline__track-pan-slider"
            title={`Pan: ${panDisplay} (double-click to center)`}
          />
          <span className="rf-timeline__track-fader-value">{panDisplay}</span>
        </div>

        {/* Bus indicator (click to change) */}
        <button
          className="rf-timeline__track-bus-indicator"
          onClick={(e) => {
            e.stopPropagation();
            // Cycle to next bus
            const currentIndex = BUS_OPTIONS.findIndex(b => b.id === (track.outputBus || 'master'));
            const nextIndex = (currentIndex + 1) % BUS_OPTIONS.length;
            onBusChange?.(BUS_OPTIONS[nextIndex].id as 'master' | 'music' | 'sfx' | 'ambience' | 'voice');
          }}
          style={{ color: currentBus.color }}
          title={`Output: ${currentBus.name} (click to cycle)`}
        >
          {currentBus.name.substring(0, 3)}
        </button>
      </div>

      {/* Secondary controls (visible on hover via CSS) */}
      <div className="rf-timeline__track-controls-secondary">
        <button
          className={`rf-timeline__track-btn-small ${track.inputMonitor ? 'active' : ''}`}
          onClick={(e) => { e.stopPropagation(); onMonitorToggle?.(); }}
          title="Input Monitor"
        >
          I
        </button>
        <button
          className={`rf-timeline__track-btn-small rf-timeline__track-btn--freeze ${track.frozen ? 'active' : ''}`}
          onClick={(e) => { e.stopPropagation(); onFreezeToggle?.(); }}
          title={track.frozen ? 'Unfreeze Track' : 'Freeze Track'}
        >
          ❄
        </button>
        <button
          className={`rf-timeline__track-btn-small rf-timeline__track-btn--lock ${track.locked ? 'active' : ''}`}
          onClick={(e) => { e.stopPropagation(); onLockToggle?.(); }}
          title={track.locked ? 'Unlock Track' : 'Lock Track'}
        >
          🔒
        </button>
      </div>

      {/* Color Picker Popup */}
      {showColorPicker && (
        <div
          className="rf-timeline__color-picker"
          onClick={(e) => e.stopPropagation()}
          onMouseLeave={() => setShowColorPicker(false)}
        >
          {TRACK_COLORS.map((color) => (
            <button
              key={color}
              className={`rf-timeline__color-swatch ${track.color === color ? 'active' : ''}`}
              style={{ backgroundColor: color }}
              onClick={() => {
                onColorChange?.(color);
                setShowColorPicker(false);
              }}
            />
          ))}
        </div>
      )}

      {/* Frozen/Locked overlays */}
      {track.frozen && <div className="rf-timeline__track-frozen-overlay" title="Track is frozen" />}
      {track.locked && <div className="rf-timeline__track-locked-overlay" title="Track is locked" />}
    </div>
  );
});

// ============ Clip Component ============

interface ClipProps {
  clip: TimelineClip;
  zoom: number;
  scrollOffset: number;
  trackHeight: number;
  onSelect?: (multiSelect?: boolean) => void;
  /** Move clip to new start time (drag-and-drop) */
  onMove?: (newStartTime: number) => void;
  onGainChange?: (gain: number) => void;
  onFadeChange?: (fadeIn: number, fadeOut: number) => void;
  /** Resize callback with optional newOffset for left-edge trim */
  onResize?: (newStartTime: number, newDuration: number, newOffset?: number) => void;
  onRename?: (newName: string) => void;
  /** Slip edit - change sourceOffset without moving clip (Cmd+drag in Cubase) */
  onSlipEdit?: (newSourceOffset: number) => void;
  /** Snap enabled */
  snapEnabled?: boolean;
  /** Snap value in beats */
  snapValue?: number;
  /** Tempo in BPM */
  tempo?: number;
  /** All clips for event snapping */
  allClips?: TimelineClip[];
}

const Clip = memo(function Clip({
  clip,
  zoom,
  scrollOffset,
  trackHeight,
  onSelect,
  onMove,
  onGainChange,
  onFadeChange,
  onResize,
  onRename,
  onSlipEdit,
  snapEnabled = false,
  snapValue = 1,
  tempo = 120,
  allClips = [],
}: ClipProps) {
  const x = (clip.startTime - scrollOffset) * zoom;
  const width = clip.duration * zoom;
  const [isDraggingGain, setIsDraggingGain] = useState(false);
  const [isDraggingFadeIn, setIsDraggingFadeIn] = useState(false);
  const [isDraggingFadeOut, setIsDraggingFadeOut] = useState(false);
  const [isDraggingLeftEdge, setIsDraggingLeftEdge] = useState(false);
  const [isDraggingRightEdge, setIsDraggingRightEdge] = useState(false);
  const [isDraggingMove, setIsDraggingMove] = useState(false);
  const [isSlipEditing, setIsSlipEditing] = useState(false);
  const [isEditing, setIsEditing] = useState(false);
  const [editName, setEditName] = useState(clip.name);
  const clipRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const dragStartRef = useRef({ startTime: 0, duration: 0, mouseX: 0, sourceOffset: 0 });

  // Gain in dB for display
  const gainDb = clip.gain !== undefined && clip.gain > 0
    ? 20 * Math.log10(clip.gain)
    : -Infinity;
  const gainDisplay = gainDb <= -60 ? '-∞' : `${gainDb >= 0 ? '+' : ''}${gainDb.toFixed(1)}`;

  // Gain drag handler
  useEffect(() => {
    if (!isDraggingGain) return;

    const handleMouseMove = (e: MouseEvent) => {
      // Vertical drag: up = louder, down = quieter
      const rect = clipRef.current?.getBoundingClientRect();
      if (!rect) return;
      const centerY = rect.top + rect.height / 2;
      const deltaY = centerY - e.clientY;
      // Map -50..+50 pixels to 0..2 gain (quadratic for finer control near unity)
      const normalized = Math.max(-1, Math.min(1, deltaY / 50));
      const newGain = 1 + normalized; // 0..2
      onGainChange?.(Math.max(0, Math.min(2, newGain)));
    };

    const handleMouseUp = () => setIsDraggingGain(false);

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDraggingGain, onGainChange]);

  // Fade in drag handler
  useEffect(() => {
    if (!isDraggingFadeIn) return;

    const handleMouseMove = (e: MouseEvent) => {
      const rect = clipRef.current?.getBoundingClientRect();
      if (!rect) return;
      const localX = e.clientX - rect.left;
      const newFadeIn = Math.max(0, Math.min(clip.duration * 0.5, localX / zoom));
      onFadeChange?.(newFadeIn, clip.fadeOut ?? 0);
    };

    const handleMouseUp = () => setIsDraggingFadeIn(false);

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDraggingFadeIn, clip.duration, clip.fadeOut, zoom, onFadeChange]);

  // Fade out drag handler
  useEffect(() => {
    if (!isDraggingFadeOut) return;

    const handleMouseMove = (e: MouseEvent) => {
      const rect = clipRef.current?.getBoundingClientRect();
      if (!rect) return;
      const localX = rect.right - e.clientX;
      const newFadeOut = Math.max(0, Math.min(clip.duration * 0.5, localX / zoom));
      onFadeChange?.(clip.fadeIn ?? 0, newFadeOut);
    };

    const handleMouseUp = () => setIsDraggingFadeOut(false);

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDraggingFadeOut, clip.duration, clip.fadeIn, zoom, onFadeChange]);

  // Left edge drag handler (trim start)
  // Cubase behavior: trimming left edge changes startTime, duration, AND sourceOffset
  useEffect(() => {
    if (!isDraggingLeftEdge) return;

    const handleMouseMove = (e: MouseEvent) => {
      const deltaX = e.clientX - dragStartRef.current.mouseX;
      const deltaTime = deltaX / zoom;

      const origStart = dragStartRef.current.startTime;
      const origDuration = dragStartRef.current.duration;
      const origOffset = dragStartRef.current.sourceOffset;

      // Calculate raw new start time
      let rawNewStartTime = origStart + deltaTime;
      // Apply snap to start time
      const snappedStartTime = applySnap(rawNewStartTime, snapEnabled, snapValue, tempo, allClips);

      // Cubase constraint: can't reveal audio before sourceOffset=0
      // If we're extending left (snappedStartTime < origStart), we need origOffset > 0
      // The amount we can extend left is limited by current offset
      let newStartTime = snappedStartTime;
      let newOffset = origOffset;

      if (snappedStartTime < origStart) {
        // Extending left - reveal earlier audio
        const extensionAmount = origStart - snappedStartTime;
        const maxExtension = origOffset; // Can only extend by current offset amount
        const actualExtension = Math.min(extensionAmount, maxExtension);
        newStartTime = origStart - actualExtension;
        newOffset = origOffset - actualExtension;
      } else {
        // Trimming right - hide earlier audio
        const trimAmount = snappedStartTime - origStart;
        // Cubase constraint: can't trim past end of clip (must leave 0.1s min)
        const maxTrim = origDuration - 0.1;
        const actualTrim = Math.min(trimAmount, maxTrim);
        newStartTime = origStart + actualTrim;
        newOffset = origOffset + actualTrim;

        // Additional constraint: offset can't exceed sourceDuration
        if (clip.sourceDuration !== undefined) {
          const maxOffset = clip.sourceDuration - 0.1;
          if (newOffset > maxOffset) {
            newOffset = maxOffset;
            newStartTime = origStart + (newOffset - origOffset);
          }
        }
      }

      // Clamp to >= 0
      newStartTime = Math.max(0, newStartTime);
      newOffset = Math.max(0, newOffset);

      // Duration changes based on startTime change
      const newDuration = origDuration - (newStartTime - origStart);

      onResize?.(newStartTime, Math.max(0.1, newDuration), newOffset);
    };

    const handleMouseUp = () => setIsDraggingLeftEdge(false);

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDraggingLeftEdge, zoom, clip.sourceDuration, onResize, snapEnabled, snapValue, tempo, allClips]);

  // Right edge drag handler (trim end)
  // Cubase constraint: cannot extend past sourceDuration - sourceOffset
  useEffect(() => {
    if (!isDraggingRightEdge) return;

    const handleMouseMove = (e: MouseEvent) => {
      const deltaX = e.clientX - dragStartRef.current.mouseX;
      const deltaTime = deltaX / zoom;

      const origDuration = dragStartRef.current.duration;
      // Calculate raw end time, then snap it
      const rawEndTime = clip.startTime + origDuration + deltaTime;
      const snappedEndTime = applySnap(rawEndTime, snapEnabled, snapValue, tempo, allClips);
      let newDuration = Math.max(0.1, snappedEndTime - clip.startTime);

      // Cubase constraint: cannot extend past remaining source audio
      // maxDuration = sourceDuration - sourceOffset
      if (clip.sourceDuration !== undefined) {
        const sourceOffset = clip.sourceOffset ?? 0;
        const maxDuration = clip.sourceDuration - sourceOffset;
        newDuration = Math.min(newDuration, maxDuration);
      }

      onResize?.(clip.startTime, newDuration);
    };

    const handleMouseUp = () => setIsDraggingRightEdge(false);

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDraggingRightEdge, zoom, clip.startTime, clip.sourceDuration, clip.sourceOffset, onResize, snapEnabled, snapValue, tempo, allClips]);

  // Slip edit handler (Cmd+drag moves audio within clip)
  useEffect(() => {
    if (!isSlipEditing) return;

    const handleMouseMove = (e: MouseEvent) => {
      const deltaX = e.clientX - dragStartRef.current.mouseX;
      const deltaTime = deltaX / zoom;

      // Offset changes inversely to drag direction
      // Drag right = show earlier part of audio = decrease offset
      const origOffset = dragStartRef.current.sourceOffset;
      const newOffset = Math.max(0, origOffset - deltaTime);

      onSlipEdit?.(newOffset);
    };

    const handleMouseUp = () => setIsSlipEditing(false);

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isSlipEditing, zoom, onSlipEdit]);

  // Move drag handler (drag clip left/right on timeline)
  useEffect(() => {
    if (!isDraggingMove) return;

    const handleMouseMove = (e: MouseEvent) => {
      const deltaX = e.clientX - dragStartRef.current.mouseX;
      const deltaTime = deltaX / zoom;

      const origStart = dragStartRef.current.startTime;
      // Calculate raw new start time
      let rawNewStartTime = origStart + deltaTime;
      // Apply snap
      const snappedStartTime = applySnap(rawNewStartTime, snapEnabled, snapValue, tempo, allClips);
      // Clamp to >= 0
      const newStartTime = Math.max(0, snappedStartTime);

      onMove?.(newStartTime);
    };

    const handleMouseUp = () => setIsDraggingMove(false);

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDraggingMove, zoom, onMove, snapEnabled, snapValue, tempo, allClips]);

  // Focus input when editing starts
  useEffect(() => {
    if (isEditing && inputRef.current) {
      inputRef.current.focus();
      inputRef.current.select();
    }
  }, [isEditing]);

  const handleLabelDoubleClick = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    setEditName(clip.name);
    setIsEditing(true);
  }, [clip.name]);

  const handleRenameSubmit = useCallback(() => {
    const trimmed = editName.trim();
    if (trimmed && trimmed !== clip.name) {
      onRename?.(trimmed);
    }
    setIsEditing(false);
  }, [editName, clip.name, onRename]);

  const handleRenameKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      handleRenameSubmit();
    } else if (e.key === 'Escape') {
      setIsEditing(false);
      setEditName(clip.name);
    }
  }, [handleRenameSubmit, clip.name]);

  // Skip if not visible
  if (x + width < 0 || x > 2000) return null;

  return (
    <div
      ref={clipRef}
      className={`rf-timeline__clip ${clip.selected ? 'selected' : ''} ${clip.muted ? 'muted' : ''} ${isSlipEditing ? 'slip-editing' : ''} ${isDraggingMove ? 'dragging' : ''}`}
      style={{
        left: x,
        width: Math.max(4, width),
        height: trackHeight - 4,
        backgroundColor: clip.color || '#3a6ea5',
        cursor: isSlipEditing ? 'ew-resize' : undefined,
      }}
      onClick={(e) => {
        e.stopPropagation();
        onSelect?.(e.shiftKey || e.metaKey);
      }}
      onMouseDown={(e) => {
        // Cmd/Ctrl + drag = slip edit (move audio within clip)
        if ((e.metaKey || e.ctrlKey) && onSlipEdit) {
          e.preventDefault();
          e.stopPropagation();
          dragStartRef.current = {
            startTime: clip.startTime,
            duration: clip.duration,
            mouseX: e.clientX,
            sourceOffset: clip.sourceOffset ?? 0,
          };
          setIsSlipEditing(true);
        } else if (onMove && e.button === 0) {
          // Normal drag = move clip left/right
          e.preventDefault();
          dragStartRef.current = {
            startTime: clip.startTime,
            duration: clip.duration,
            mouseX: e.clientX,
            sourceOffset: clip.sourceOffset ?? 0,
          };
          setIsDraggingMove(true);
        }
      }}
      title={isSlipEditing ? 'Slip editing: drag to move audio within clip' : undefined}
    >
      {/* Waveform - Cubase-style LOD rendering */}
      {/* Uses AudioBuffer directly when available for zoom-dependent detail */}
      {(clip.audioBuffer || clip.waveform) && width > 20 && (
        <div
          className="rf-timeline__clip-waveform"
          style={{ transform: `scaleY(${clip.gain ?? 1})` }}
        >
          <Waveform
            audioBuffer={clip.audioBuffer}
            data={clip.waveform}
            sourceOffset={clip.sourceOffset ?? 0}
            duration={clip.duration}
            width={Math.max(20, width - 4)}
            height={trackHeight - 12}
            color="#fff"
            opacity={0.6}
          />
        </div>
      )}

      {/* Label */}
      {width > 40 && (
        isEditing ? (
          <input
            ref={inputRef}
            className="rf-timeline__clip-label-input"
            type="text"
            value={editName}
            onChange={(e) => setEditName(e.target.value)}
            onBlur={handleRenameSubmit}
            onKeyDown={handleRenameKeyDown}
            onClick={(e) => e.stopPropagation()}
          />
        ) : (
          <div
            className="rf-timeline__clip-label"
            onDoubleClick={handleLabelDoubleClick}
            title="Double-click to rename"
          >
            {clip.name}
          </div>
        )
      )}

      {/* Gain handle (top-center) */}
      {width > 60 && (
        <div
          className={`rf-timeline__clip-gain ${isDraggingGain ? 'active' : ''}`}
          title={`Clip Gain: ${gainDisplay} dB (drag up/down)`}
          onMouseDown={(e) => {
            e.stopPropagation();
            setIsDraggingGain(true);
          }}
          onDoubleClick={(e) => {
            e.stopPropagation();
            onGainChange?.(1); // Reset to unity
          }}
        >
          {gainDisplay}
        </div>
      )}

      {/* Fade in handle (top-left triangle) */}
      <div
        className={`rf-timeline__clip-fade-handle rf-timeline__clip-fade-handle--in ${isDraggingFadeIn ? 'active' : ''}`}
        style={{ width: Math.max(8, (clip.fadeIn ?? 0) * zoom) }}
        title="Fade In (drag to adjust)"
        onMouseDown={(e) => {
          e.stopPropagation();
          setIsDraggingFadeIn(true);
        }}
      />

      {/* Fade out handle (top-right triangle) */}
      <div
        className={`rf-timeline__clip-fade-handle rf-timeline__clip-fade-handle--out ${isDraggingFadeOut ? 'active' : ''}`}
        style={{ width: Math.max(8, (clip.fadeOut ?? 0) * zoom) }}
        title="Fade Out (drag to adjust)"
        onMouseDown={(e) => {
          e.stopPropagation();
          setIsDraggingFadeOut(true);
        }}
      />

      {/* Fade overlay visualizations */}
      {(clip.fadeIn ?? 0) > 0 && (
        <div
          className="rf-timeline__clip-fade rf-timeline__clip-fade--in"
          style={{ width: (clip.fadeIn ?? 0) * zoom }}
        />
      )}
      {(clip.fadeOut ?? 0) > 0 && (
        <div
          className="rf-timeline__clip-fade rf-timeline__clip-fade--out"
          style={{ width: (clip.fadeOut ?? 0) * zoom }}
        />
      )}

      {/* Left edge resize handle */}
      <div
        className={`rf-timeline__clip-edge rf-timeline__clip-edge--left ${isDraggingLeftEdge ? 'active' : ''}`}
        title="Drag to trim start"
        onMouseDown={(e) => {
          e.stopPropagation();
          dragStartRef.current = {
            startTime: clip.startTime,
            duration: clip.duration,
            mouseX: e.clientX,
            sourceOffset: clip.sourceOffset ?? 0,
          };
          setIsDraggingLeftEdge(true);
        }}
      />

      {/* Right edge resize handle */}
      <div
        className={`rf-timeline__clip-edge rf-timeline__clip-edge--right ${isDraggingRightEdge ? 'active' : ''}`}
        title="Drag to trim end"
        onMouseDown={(e) => {
          e.stopPropagation();
          dragStartRef.current = {
            startTime: clip.startTime,
            duration: clip.duration,
            mouseX: e.clientX,
            sourceOffset: clip.sourceOffset ?? 0,
          };
          setIsDraggingRightEdge(true);
        }}
      />
    </div>
  );
});

// ============ Grid Lines ============

interface GridLinesProps {
  width: number;
  height: number;
  zoom: number;
  scrollOffset: number;
  tempo: number;
  timeSignature: [number, number];
}

const GridLines = memo(function GridLines({
  width,
  height,
  zoom,
  scrollOffset,
  tempo,
  timeSignature,
}: GridLinesProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || width <= 0 || height <= 0) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.scale(dpr, dpr);

    // Clear
    ctx.clearRect(0, 0, width, height);

    // Calculate beat/bar durations
    const beatsPerSecond = tempo / 60;
    const beatDuration = 1 / beatsPerSecond;
    const barDuration = beatDuration * timeSignature[0];

    // Determine grid density based on zoom
    // At low zoom, show only bars; at high zoom, show 16th notes
    let majorInterval: number;
    let minorInterval: number;

    if (zoom < 15) {
      majorInterval = barDuration * 4; // 4 bars
      minorInterval = barDuration;     // 1 bar
    } else if (zoom < 40) {
      majorInterval = barDuration;     // 1 bar
      minorInterval = beatDuration;    // 1 beat
    } else if (zoom < 100) {
      majorInterval = beatDuration;    // 1 beat
      minorInterval = beatDuration / 2; // 8th note
    } else {
      majorInterval = beatDuration;    // 1 beat
      minorInterval = beatDuration / 4; // 16th note
    }

    // Visible time range
    const visibleDuration = width / zoom;
    const startTime = scrollOffset;
    const endTime = scrollOffset + visibleDuration;

    // Draw minor grid lines
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.04)';
    ctx.lineWidth = 1;
    ctx.beginPath();

    const firstMinor = Math.floor(startTime / minorInterval) * minorInterval;
    for (let t = firstMinor; t <= endTime; t += minorInterval) {
      // Skip if it's a major line
      if (Math.abs(t % majorInterval) < 0.0001) continue;

      const x = Math.round((t - scrollOffset) * zoom) + 0.5;
      if (x >= 0 && x <= width) {
        ctx.moveTo(x, 0);
        ctx.lineTo(x, height);
      }
    }
    ctx.stroke();

    // Draw major grid lines
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.12)';
    ctx.lineWidth = 1;
    ctx.beginPath();

    const firstMajor = Math.floor(startTime / majorInterval) * majorInterval;
    for (let t = firstMajor; t <= endTime; t += majorInterval) {
      const x = Math.round((t - scrollOffset) * zoom) + 0.5;
      if (x >= 0 && x <= width) {
        ctx.moveTo(x, 0);
        ctx.lineTo(x, height);
      }
    }
    ctx.stroke();

  }, [width, height, zoom, scrollOffset, tempo, timeSignature]);

  return (
    <canvas
      ref={canvasRef}
      className="rf-timeline__grid-canvas"
      style={{ width, height, position: 'absolute', left: 0, top: 0, pointerEvents: 'none' }}
    />
  );
});

// ============ Crossfade Overlay ============

interface CrossfadeOverlayProps {
  crossfade: Crossfade;
  zoom: number;
  scrollOffset: number;
  height: number;
  onUpdate?: (duration: number) => void;
  onDelete?: () => void;
}

const CrossfadeOverlay = memo(function CrossfadeOverlay({
  crossfade,
  zoom,
  scrollOffset,
  height,
  onUpdate,
  onDelete,
}: CrossfadeOverlayProps) {
  const [isDragging, setIsDragging] = useState(false);
  const [dragEdge, setDragEdge] = useState<'left' | 'right' | null>(null);
  const startXRef = useRef(0);
  const startDurationRef = useRef(0);

  const left = (crossfade.startTime - scrollOffset) * zoom;
  const width = crossfade.duration * zoom;

  // Don't render if not visible
  if (left + width < 0 || left > 2000) return null;

  const handleMouseDown = (e: React.MouseEvent, edge: 'left' | 'right') => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(true);
    setDragEdge(edge);
    startXRef.current = e.clientX;
    startDurationRef.current = crossfade.duration;
  };

  const handleMouseMove = useCallback((e: MouseEvent) => {
    if (!isDragging || !dragEdge) return;

    const deltaX = e.clientX - startXRef.current;
    const deltaTime = deltaX / zoom;

    let newDuration = startDurationRef.current;
    if (dragEdge === 'right') {
      newDuration = Math.max(0.1, startDurationRef.current + deltaTime);
    } else {
      newDuration = Math.max(0.1, startDurationRef.current - deltaTime);
    }

    onUpdate?.(newDuration);
  }, [isDragging, dragEdge, zoom, onUpdate]);

  const handleMouseUp = useCallback(() => {
    setIsDragging(false);
    setDragEdge(null);
  }, []);

  useEffect(() => {
    if (isDragging) {
      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
      return () => {
        window.removeEventListener('mousemove', handleMouseMove);
        window.removeEventListener('mouseup', handleMouseUp);
      };
    }
  }, [isDragging, handleMouseMove, handleMouseUp]);

  // Double-click to delete crossfade
  const handleDoubleClick = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    onDelete?.();
  };

  return (
    <div
      className="rf-timeline__crossfade"
      style={{
        left,
        width: Math.max(4, width),
        height: height - 4,
        top: 2,
      }}
      onDoubleClick={handleDoubleClick}
      title="Double-click to remove crossfade"
    >
      {/* Crossfade visual - X pattern */}
      <svg
        className="rf-timeline__crossfade-svg"
        viewBox="0 0 100 100"
        preserveAspectRatio="none"
      >
        {/* Fade out curve (first clip) */}
        <path
          d={crossfade.curveType === 's-curve'
            ? 'M 0,10 C 30,10 70,90 100,90'
            : crossfade.curveType === 'equal-power'
            ? 'M 0,10 Q 50,10 100,90'
            : 'M 0,10 L 100,90'}
          fill="none"
          stroke="rgba(255,100,100,0.8)"
          strokeWidth="3"
        />
        {/* Fade in curve (second clip) */}
        <path
          d={crossfade.curveType === 's-curve'
            ? 'M 0,90 C 30,90 70,10 100,10'
            : crossfade.curveType === 'equal-power'
            ? 'M 0,90 Q 50,90 100,10'
            : 'M 0,90 L 100,10'}
          fill="none"
          stroke="rgba(100,255,100,0.8)"
          strokeWidth="3"
        />
      </svg>

      {/* Resize handles */}
      <div
        className="rf-timeline__crossfade-handle rf-timeline__crossfade-handle--left"
        onMouseDown={(e) => handleMouseDown(e, 'left')}
      />
      <div
        className="rf-timeline__crossfade-handle rf-timeline__crossfade-handle--right"
        onMouseDown={(e) => handleMouseDown(e, 'right')}
      />
    </div>
  );
});

// ============ Track Lane with Drop Zone ============

interface TrackLaneProps {
  track: TimelineTrack;
  trackHeight: number;
  clips: TimelineClip[];
  crossfades?: Crossfade[];
  zoom: number;
  scrollOffset: number;
  tempo: number;
  timeSignature: [number, number];
  onClipSelect?: (clipId: string, multiSelect?: boolean) => void;
  onClipMove?: (clipId: string, newStartTime: number) => void;
  onAudioDrop?: (trackId: string, time: number, audioItem: DragItem) => void;
  onClipGainChange?: (clipId: string, gain: number) => void;
  onClipFadeChange?: (clipId: string, fadeIn: number, fadeOut: number) => void;
  onClipResize?: (clipId: string, newStartTime: number, newDuration: number, newOffset?: number) => void;
  onClipRename?: (clipId: string, newName: string) => void;
  /** Slip edit - change sourceOffset (Cmd+drag) */
  onClipSlipEdit?: (clipId: string, newSourceOffset: number) => void;
  onCrossfadeUpdate?: (crossfadeId: string, duration: number) => void;
  onCrossfadeDelete?: (crossfadeId: string) => void;
  /** Snap enabled */
  snapEnabled?: boolean;
  /** Snap value in beats */
  snapValue?: number;
  /** All clips for event snapping */
  allClips?: TimelineClip[];
}

const TrackLane = memo(function TrackLane({
  track,
  trackHeight,
  clips,
  crossfades = [],
  zoom,
  scrollOffset,
  tempo,
  timeSignature,
  onClipSelect,
  onClipMove,
  onAudioDrop,
  onClipGainChange,
  onClipFadeChange,
  onClipResize,
  onClipRename,
  onClipSlipEdit,
  onCrossfadeUpdate,
  onCrossfadeDelete,
  snapEnabled = false,
  snapValue = 1,
  allClips = [],
}: TrackLaneProps) {
  const laneRef = useRef<HTMLDivElement>(null);
  const lastMouseXRef = useRef<number>(0);
  const [laneWidth, setLaneWidth] = useState(0);
  const [ghostPosition, setGhostPosition] = useState<number | null>(null);

  // Get current drag state for ghost clip rendering
  const dragState = useDragState();
  const currentDragItem = dragState.currentItem;

  // Track mouse position for drop time calculation and ghost clip
  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      lastMouseXRef.current = e.clientX;

      // Update ghost position when dragging over this lane
      if (laneRef.current && dragState.isDragging) {
        const rect = laneRef.current.getBoundingClientRect();
        if (e.clientX >= rect.left && e.clientX <= rect.right &&
            e.clientY >= rect.top && e.clientY <= rect.bottom) {
          const x = e.clientX - rect.left;
          const rawTime = scrollOffset + x / zoom;
          const snappedTime = applySnap(rawTime, snapEnabled, snapValue, tempo, allClips);
          setGhostPosition(Math.max(0, snappedTime));
        }
      }
    };
    document.addEventListener('mousemove', handleMouseMove);
    return () => document.removeEventListener('mousemove', handleMouseMove);
  }, [dragState.isDragging, scrollOffset, zoom, snapEnabled, snapValue, tempo, allClips]);

  // Clear ghost position when drag ends
  useEffect(() => {
    if (!dragState.isDragging) {
      setGhostPosition(null);
    }
  }, [dragState.isDragging]);

  // Measure lane width for grid rendering
  useEffect(() => {
    if (!laneRef.current) return;
    const observer = new ResizeObserver((entries) => {
      const entry = entries[0];
      if (entry) {
        setLaneWidth(entry.contentRect.width);
      }
    });
    observer.observe(laneRef.current);
    return () => observer.disconnect();
  }, []);

  // Drop target configuration
  const dropTarget: DropTarget = {
    id: `track-${track.id}`,
    type: 'timeline-track',
    accepts: ['audio-asset'],
  };

  const handleDrop = useCallback((item: DragItem, _target: DropTarget) => {
    if (!laneRef.current || !onAudioDrop) return;

    // Calculate drop time from last mouse position
    const rect = laneRef.current.getBoundingClientRect();
    const x = lastMouseXRef.current - rect.left;
    const rawTime = scrollOffset + x / zoom;

    // Apply snap to grid/events
    const snappedTime = applySnap(rawTime, snapEnabled, snapValue, tempo, allClips);

    onAudioDrop(track.id, Math.max(0, snappedTime), item);
  }, [track.id, scrollOffset, zoom, onAudioDrop, snapEnabled, snapValue, tempo, allClips]);

  const { ref, isOver } = useDropTarget(dropTarget, handleDrop);

  // Combine refs
  const setRefs = useCallback((node: HTMLDivElement | null) => {
    (laneRef as React.MutableRefObject<HTMLDivElement | null>).current = node;
    if (typeof ref === 'function') {
      ref(node);
    }
  }, [ref]);

  return (
    <div
      ref={setRefs}
      className={`rf-timeline__track-lane ${isOver ? 'rf-timeline__track-lane--drop-active' : ''}`}
      style={{ height: trackHeight }}
    >
      {/* Grid lines */}
      {laneWidth > 0 && (
        <GridLines
          width={laneWidth}
          height={trackHeight}
          zoom={zoom}
          scrollOffset={scrollOffset}
          tempo={tempo}
          timeSignature={timeSignature}
        />
      )}

      {/* Ghost clip preview during drag */}
      {isOver && ghostPosition !== null && currentDragItem && (() => {
        const duration = typeof currentDragItem.data?.duration === 'number'
          ? currentDragItem.data.duration
          : 2;
        const waveform = currentDragItem.data?.waveform as number[] | Float32Array | undefined;

        return (
          <div
            className="rf-timeline__ghost-clip"
            style={{
              left: (ghostPosition - scrollOffset) * zoom,
              width: duration * zoom,
              height: trackHeight - 8,
              top: 4,
            }}
          >
            {/* Mini waveform preview */}
            {waveform && waveform.length > 0 && (
              <svg
                className="rf-timeline__ghost-waveform"
                viewBox="0 0 100 40"
                preserveAspectRatio="none"
              >
                <path
                  d={generateWaveformPath(waveform, 100, 40)}
                  fill="currentColor"
                  opacity="0.5"
                />
              </svg>
            )}
            <span className="rf-timeline__ghost-name">{currentDragItem.label}</span>
          </div>
        );
      })()}

      {/* Clips */}
      {clips.map((clip) => (
        <Clip
          key={clip.id}
          clip={clip}
          zoom={zoom}
          scrollOffset={scrollOffset}
          trackHeight={trackHeight}
          onSelect={(multi) => onClipSelect?.(clip.id, multi)}
          onMove={(newStart) => onClipMove?.(clip.id, newStart)}
          onGainChange={(gain) => onClipGainChange?.(clip.id, gain)}
          onFadeChange={(fadeIn, fadeOut) => onClipFadeChange?.(clip.id, fadeIn, fadeOut)}
          onResize={(newStart, newDur, newOffset) => onClipResize?.(clip.id, newStart, newDur, newOffset)}
          onRename={(newName) => onClipRename?.(clip.id, newName)}
          onSlipEdit={(offset) => onClipSlipEdit?.(clip.id, offset)}
          snapEnabled={snapEnabled}
          snapValue={snapValue}
          tempo={tempo}
          allClips={allClips}
        />
      ))}

      {/* Crossfades */}
      {crossfades.map((xfade) => (
        <CrossfadeOverlay
          key={xfade.id}
          crossfade={xfade}
          zoom={zoom}
          scrollOffset={scrollOffset}
          height={trackHeight}
          onUpdate={(duration) => onCrossfadeUpdate?.(xfade.id, duration)}
          onDelete={() => onCrossfadeDelete?.(xfade.id)}
        />
      ))}
    </div>
  );
});

// ============ New Track Drop Zone ============

interface NewTrackDropZoneProps {
  zoom: number;
  scrollOffset: number;
  tempo: number;
  onNewTrackDrop?: (time: number, audioItem: DragItem) => void;
  isEmpty?: boolean;
  /** Unique ID for this drop zone (prevents duplicate drops when multiple Timelines exist) */
  dropZoneId?: string;
  /** Snap enabled */
  snapEnabled?: boolean;
  /** Snap value in beats */
  snapValue?: number;
  /** All clips for event snapping */
  allClips?: TimelineClip[];
}

const NewTrackDropZone = memo(function NewTrackDropZone({
  zoom,
  scrollOffset,
  tempo,
  onNewTrackDrop,
  isEmpty = false,
  dropZoneId = 'new-track-zone',
  snapEnabled = false,
  snapValue = 1,
  allClips = [],
}: NewTrackDropZoneProps) {
  const zoneRef = useRef<HTMLDivElement>(null);
  const lastMouseXRef = useRef<number>(0);

  // Track mouse position for drop time calculation
  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      lastMouseXRef.current = e.clientX;
    };
    window.addEventListener('mousemove', handleMouseMove);
    return () => window.removeEventListener('mousemove', handleMouseMove);
  }, []);

  const dropTarget: DropTarget = {
    id: dropZoneId,
    type: 'timeline-new-track',
    accepts: ['audio-asset'],
  };

  const handleDrop = useCallback((item: DragItem, _target: DropTarget) => {
    if (!zoneRef.current || !onNewTrackDrop) return;

    // Calculate drop time from last mouse position
    const rect = zoneRef.current.getBoundingClientRect();
    const x = lastMouseXRef.current - rect.left;
    const rawTime = scrollOffset + x / zoom;

    // Apply snap to grid/events
    const snappedTime = applySnap(rawTime, snapEnabled, snapValue, tempo, allClips);

    onNewTrackDrop(Math.max(0, snappedTime), item);
  }, [scrollOffset, zoom, onNewTrackDrop, snapEnabled, snapValue, tempo, allClips]);

  const { ref, isOver } = useDropTarget(dropTarget, handleDrop);

  // Combine refs
  const setRefs = useCallback((node: HTMLDivElement | null) => {
    (zoneRef as React.MutableRefObject<HTMLDivElement | null>).current = node;
    if (typeof ref === 'function') {
      ref(node);
    }
  }, [ref]);

  return (
    <div
      ref={setRefs}
      className={`rf-timeline__new-track-zone ${isOver ? 'rf-timeline__new-track-zone--active' : ''} ${isEmpty ? 'rf-timeline__new-track-zone--empty' : ''}`}
    >
      <div className="rf-timeline__new-track-zone-content">
        {isOver ? (
          <span>Drop to create new track</span>
        ) : isEmpty ? (
          <span>Drop audio files here to create tracks</span>
        ) : (
          <span>+ Drop to add track</span>
        )}
      </div>
    </div>
  );
});

// ============ Timeline Component ============

export const Timeline = memo(function Timeline({
  tracks,
  clips,
  markers = [],
  loopRegion,
  loopEnabled = true,
  playheadPosition,
  tempo = 120,
  timeSignature = [4, 4],
  zoom = 50,
  scrollOffset = 0,
  totalDuration = 120,
  timeDisplayMode = 'bars',
  sampleRate = 48000,
  onPlayheadChange,
  onClipSelect,
  onZoomChange,
  onScrollChange,
  onLoopRegionChange,
  onLoopToggle,
  onTrackMuteToggle,
  onTrackSoloToggle,
  onTrackSelect,
  onAudioDrop,
  onNewTrackDrop,
  onClipGainChange,
  onClipFadeChange,
  onClipResize,
  onClipSlipEdit,
  onClipSplit,
  onClipDuplicate,
  onClipMove,
  onTrackColorChange,
  onMarkerClick,
  onTrackBusChange,
  onClipDelete,
  onClipCopy,
  onClipPaste,
  onTrackRename,
  onTrackArmToggle,
  onTrackMonitorToggle,
  onTrackFreezeToggle,
  onTrackLockToggle,
  onTrackVolumeChange,
  onTrackPanChange,
  onClipRename,
  crossfades = [],
  onCrossfadeCreate,
  onCrossfadeUpdate,
  onCrossfadeDelete,
  instanceId = 'default',
  // Snap settings
  snapEnabled = true,
  snapValue = 1,
}: TimelineProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [containerWidth, setContainerWidth] = useState(800);
  const [isDraggingPlayhead, setIsDraggingPlayhead] = useState(false);
  const [isDraggingLoopLeft, setIsDraggingLoopLeft] = useState(false);
  const [isDraggingLoopRight, setIsDraggingLoopRight] = useState(false);
  const trackHeight = 80; // Increased for Cubase-style two-row header

  // Measure container
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        setContainerWidth(entry.contentRect.width - 180); // minus track headers
      }
    });

    observer.observe(container);
    return () => observer.disconnect();
  }, []);

  // Playhead position in pixels
  const playheadX = useMemo(() => {
    return (playheadPosition - scrollOffset) * zoom;
  }, [playheadPosition, scrollOffset, zoom]);

  // Handle wheel for zoom/scroll
  const handleWheel = useCallback((e: React.WheelEvent) => {
    if (e.ctrlKey || e.metaKey) {
      // Zoom
      e.preventDefault();
      const delta = e.deltaY > 0 ? 0.9 : 1.1;
      const newZoom = Math.max(10, Math.min(500, zoom * delta));
      onZoomChange?.(newZoom);
    } else {
      // Scroll
      const delta = e.deltaX || e.deltaY;
      const newOffset = Math.max(0, Math.min(totalDuration - containerWidth / zoom, scrollOffset + delta / zoom));
      onScrollChange?.(newOffset);
    }
  }, [zoom, scrollOffset, totalDuration, containerWidth, onZoomChange, onScrollChange]);

  // Handle timeline click for playhead
  const handleTimelineClick = useCallback((e: React.MouseEvent) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left - 180; // minus track headers
    if (x < 0) return;
    const time = scrollOffset + x / zoom;
    onPlayheadChange?.(Math.max(0, time));
  }, [scrollOffset, zoom, onPlayheadChange]);

  // Handle playhead drag
  const handlePlayheadMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDraggingPlayhead(true);
  }, []);

  // Global mouse move/up for playhead drag
  useEffect(() => {
    if (!isDraggingPlayhead) return;

    const handleMouseMove = (e: MouseEvent) => {
      const container = containerRef.current;
      if (!container) return;
      const rect = container.getBoundingClientRect();
      const x = e.clientX - rect.left - 180; // minus track headers
      const time = scrollOffset + Math.max(0, x) / zoom;
      onPlayheadChange?.(Math.max(0, Math.min(totalDuration, time)));
    };

    const handleMouseUp = () => {
      setIsDraggingPlayhead(false);
    };

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);

    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDraggingPlayhead, scrollOffset, zoom, totalDuration, onPlayheadChange]);

  // Global mouse move/up for loop region resize
  useEffect(() => {
    if (!isDraggingLoopLeft && !isDraggingLoopRight) return;

    const handleMouseMove = (e: MouseEvent) => {
      const container = containerRef.current;
      if (!container || !loopRegion) return;
      const rect = container.getBoundingClientRect();
      const x = e.clientX - rect.left - 180;
      const time = Math.max(0, scrollOffset + x / zoom);

      if (isDraggingLoopLeft) {
        // Don't let left edge go past right edge
        const newStart = Math.min(time, loopRegion.end - 0.1);
        onLoopRegionChange?.({ start: Math.max(0, newStart), end: loopRegion.end });
      } else if (isDraggingLoopRight) {
        // Don't let right edge go past left edge
        const newEnd = Math.max(time, loopRegion.start + 0.1);
        onLoopRegionChange?.({ start: loopRegion.start, end: newEnd });
      }
    };

    const handleMouseUp = () => {
      setIsDraggingLoopLeft(false);
      setIsDraggingLoopRight(false);
    };

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);

    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDraggingLoopLeft, isDraggingLoopRight, scrollOffset, zoom, loopRegion, onLoopRegionChange]);

  // Group clips by track
  const clipsByTrack = useMemo(() => {
    const map = new Map<string, TimelineClip[]>();
    tracks.forEach((t) => map.set(t.id, []));
    clips.forEach((c) => {
      const arr = map.get(c.trackId);
      if (arr) arr.push(c);
    });
    return map;
  }, [tracks, clips]);

  // Group crossfades by track
  const crossfadesByTrack = useMemo(() => {
    const map = new Map<string, Crossfade[]>();
    tracks.forEach((t) => map.set(t.id, []));
    crossfades?.forEach((xf) => {
      const arr = map.get(xf.trackId);
      if (arr) arr.push(xf);
    });
    return map;
  }, [tracks, crossfades]);

  // Auto-detect overlapping clips and create crossfades
  useEffect(() => {
    if (!onCrossfadeCreate) return;

    // For each track, find overlapping clips
    tracks.forEach((track) => {
      const trackClips = clipsByTrack.get(track.id) || [];
      if (trackClips.length < 2) return;

      // Sort by start time
      const sorted = [...trackClips].sort((a, b) => a.startTime - b.startTime);

      for (let i = 0; i < sorted.length - 1; i++) {
        const clipA = sorted[i];
        const clipB = sorted[i + 1];

        const clipAEnd = clipA.startTime + clipA.duration;

        // Check for overlap
        if (clipAEnd > clipB.startTime) {
          const overlapStart = clipB.startTime;
          const overlapEnd = Math.min(clipAEnd, clipB.startTime + clipB.duration);
          const overlapDuration = overlapEnd - overlapStart;

          // Only create if overlap is significant (> 50ms) and crossfade doesn't exist
          if (overlapDuration > 0.05) {
            const existingXfade = crossfades?.find(
              xf => xf.clipAId === clipA.id && xf.clipBId === clipB.id
            );

            if (!existingXfade) {
              onCrossfadeCreate({
                trackId: track.id,
                clipAId: clipA.id,
                clipBId: clipB.id,
                startTime: overlapStart,
                duration: overlapDuration,
                curveType: 'equal-power',
              });
            }
          }
        }
      }
    });
  }, [tracks, clipsByTrack, crossfades, onCrossfadeCreate]);

  // Keyboard shortcuts for clip operations
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Only handle when timeline is focused
      if (!containerRef.current?.contains(document.activeElement) &&
          document.activeElement !== document.body) return;

      // Find selected clip
      const selectedClip = clips.find(c => c.selected);

      // S key - split clip at playhead
      if (e.key === 's' || e.key === 'S') {
        if (selectedClip && onClipSplit) {
          // Split at playhead position
          if (playheadPosition > selectedClip.startTime &&
              playheadPosition < selectedClip.startTime + selectedClip.duration) {
            e.preventDefault();
            onClipSplit(selectedClip.id, playheadPosition);
          }
        }
      }

      // Cmd+D / Ctrl+D - duplicate clip
      if ((e.metaKey || e.ctrlKey) && (e.key === 'd' || e.key === 'D')) {
        if (selectedClip && onClipDuplicate) {
          e.preventDefault();
          onClipDuplicate(selectedClip.id);
        }
      }

      // G key - zoom in
      if (e.key === 'g' || e.key === 'G') {
        if (onZoomChange) {
          e.preventDefault();
          onZoomChange(Math.min(500, zoom * 1.25));
        }
      }

      // H key - zoom out
      if (e.key === 'h' || e.key === 'H') {
        if (onZoomChange) {
          e.preventDefault();
          onZoomChange(Math.max(10, zoom * 0.8));
        }
      }

      // Arrow keys - nudge selected clip
      if (selectedClip && onClipMove) {
        // Calculate nudge amount based on tempo and snap
        const beatsPerSecond = tempo / 60;
        const nudgeAmount = e.shiftKey
          ? 1 / beatsPerSecond // Shift = 1 beat
          : 0.25 / beatsPerSecond; // Default = 1/4 beat (16th note)

        if (e.key === 'ArrowLeft') {
          e.preventDefault();
          const newTime = Math.max(0, selectedClip.startTime - nudgeAmount);
          onClipMove(selectedClip.id, newTime);
        }
        if (e.key === 'ArrowRight') {
          e.preventDefault();
          const newTime = selectedClip.startTime + nudgeAmount;
          onClipMove(selectedClip.id, newTime);
        }
      }

      // Delete/Backspace - delete selected clip
      if ((e.key === 'Delete' || e.key === 'Backspace') && selectedClip) {
        e.preventDefault();
        onClipDelete?.(selectedClip.id);
      }

      // Cmd+C / Ctrl+C - copy clip
      if ((e.metaKey || e.ctrlKey) && (e.key === 'c' || e.key === 'C') && selectedClip) {
        e.preventDefault();
        onClipCopy?.(selectedClip.id);
      }

      // Cmd+V / Ctrl+V - paste clip
      if ((e.metaKey || e.ctrlKey) && (e.key === 'v' || e.key === 'V')) {
        e.preventDefault();
        onClipPaste?.();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [clips, playheadPosition, zoom, tempo, onClipSplit, onClipDuplicate, onZoomChange, onClipMove, onClipDelete, onClipCopy, onClipPaste]);

  return (
    <div
      ref={containerRef}
      className="rf-timeline"
      onWheel={handleWheel}
    >
      {/* Time Ruler */}
      <div className="rf-timeline__ruler-row">
        <div className="rf-timeline__header-spacer" />
        <TimeRuler
          width={containerWidth}
          zoom={zoom}
          scrollOffset={scrollOffset}
          tempo={tempo}
          timeSignature={timeSignature}
          timeDisplayMode={timeDisplayMode}
          sampleRate={sampleRate}
          loopRegion={loopRegion}
          loopEnabled={loopEnabled}
          onTimeClick={onPlayheadChange}
          onLoopToggle={onLoopToggle}
        />
        {/* Loop Region Resize Handles - positioned over ruler only */}
        {loopRegion && (
          <div
            className={`rf-timeline__loop-region ${loopEnabled ? 'rf-timeline__loop-region--active' : ''} ${isDraggingLoopLeft || isDraggingLoopRight ? 'dragging' : ''}`}
            style={{
              position: 'absolute',
              left: 180 + (loopRegion.start - scrollOffset) * zoom,
              width: Math.max(10, (loopRegion.end - loopRegion.start) * zoom),
              top: 0,
              height: 28,
              background: 'transparent', // Canvas handles the fill
              pointerEvents: 'auto',
            }}
            onClick={(e) => {
              e.stopPropagation();
              onLoopToggle?.();
            }}
            title={`Loop: ${loopRegion.start.toFixed(1)}s - ${loopRegion.end.toFixed(1)}s (click to ${loopEnabled ? 'disable' : 'enable'})`}
          >
            {/* Left resize handle */}
            <div
              className="rf-timeline__loop-handle rf-timeline__loop-handle--left"
              onMouseDown={(e) => {
                e.preventDefault();
                e.stopPropagation();
                setIsDraggingLoopLeft(true);
              }}
              title="Drag to adjust loop start"
            />
            {/* Right resize handle */}
            <div
              className="rf-timeline__loop-handle rf-timeline__loop-handle--right"
              onMouseDown={(e) => {
                e.preventDefault();
                e.stopPropagation();
                setIsDraggingLoopRight(true);
              }}
              title="Drag to adjust loop end"
            />
          </div>
        )}
      </div>

      {/* Tracks */}
      <div className="rf-timeline__tracks" onClick={handleTimelineClick}>
        {tracks.map((track) => (
          <div key={track.id} className="rf-timeline__track-row">
            {/* Track Header */}
            <TrackHeader
              track={track}
              height={trackHeight}
              onMuteToggle={() => onTrackMuteToggle?.(track.id)}
              onSoloToggle={() => onTrackSoloToggle?.(track.id)}
              onArmToggle={() => onTrackArmToggle?.(track.id)}
              onMonitorToggle={() => onTrackMonitorToggle?.(track.id)}
              onFreezeToggle={() => onTrackFreezeToggle?.(track.id)}
              onLockToggle={() => onTrackLockToggle?.(track.id)}
              onVolumeChange={(volume) => onTrackVolumeChange?.(track.id, volume)}
              onPanChange={(pan) => onTrackPanChange?.(track.id, pan)}
              onClick={() => onTrackSelect?.(track.id)}
              onColorChange={(color) => onTrackColorChange?.(track.id, color)}
              onBusChange={(bus) => onTrackBusChange?.(track.id, bus)}
              onRename={(newName) => onTrackRename?.(track.id, newName)}
            />

            {/* Track Lane with Drop Zone */}
            <TrackLane
              track={track}
              trackHeight={trackHeight}
              clips={clipsByTrack.get(track.id) || []}
              crossfades={crossfadesByTrack.get(track.id) || []}
              zoom={zoom}
              scrollOffset={scrollOffset}
              tempo={tempo}
              timeSignature={timeSignature}
              onClipSelect={onClipSelect}
              onClipMove={onClipMove}
              onAudioDrop={onAudioDrop}
              onClipGainChange={onClipGainChange}
              onClipFadeChange={onClipFadeChange}
              onClipResize={onClipResize}
              onClipRename={onClipRename}
              onClipSlipEdit={onClipSlipEdit}
              onCrossfadeUpdate={onCrossfadeUpdate}
              onCrossfadeDelete={onCrossfadeDelete}
              snapEnabled={snapEnabled}
              snapValue={snapValue}
              allClips={clips}
            />
          </div>
        ))}

        {/* New Track Drop Zone - always visible at bottom */}
        <div className="rf-timeline__track-row rf-timeline__track-row--new">
          <div className="rf-timeline__track-header rf-timeline__track-header--new" style={{ height: tracks.length === 0 ? 100 : 40 }} />
          <NewTrackDropZone
            zoom={zoom}
            scrollOffset={scrollOffset}
            tempo={tempo}
            onNewTrackDrop={onNewTrackDrop}
            isEmpty={tracks.length === 0}
            dropZoneId={`new-track-zone-${instanceId}`}
            snapEnabled={snapEnabled}
            snapValue={snapValue}
            allClips={clips}
          />
        </div>

        {/* Playhead - draggable */}
        {playheadX >= 0 && playheadX <= containerWidth && (
          <div
            className={`rf-timeline__playhead ${isDraggingPlayhead ? 'dragging' : ''}`}
            style={{ left: 180 + playheadX, cursor: 'ew-resize' }}
            onMouseDown={handlePlayheadMouseDown}
            title="Drag to move playhead"
          />
        )}

        {/* Markers */}
        {markers.map((marker) => {
          const x = (marker.time - scrollOffset) * zoom;
          if (x < 0 || x > containerWidth) return null;
          return (
            <div
              key={marker.id}
              className="rf-timeline__marker"
              style={{ left: 180 + x, borderColor: marker.color }}
              title={`${marker.name} (click to jump, double-click to edit)`}
              onClick={(e) => {
                e.stopPropagation();
                onPlayheadChange?.(marker.time);
                onMarkerClick?.(marker.id);
              }}
            >
              <span className="rf-timeline__marker-flag">{marker.name}</span>
            </div>
          );
        })}
      </div>

      {/* Zoom indicator */}
      <div className="rf-timeline__zoom-indicator">
        {zoom.toFixed(0)}px/s
      </div>
    </div>
  );
});

// ============ Generate Demo Waveform ============

export function generateDemoWaveform(samples: number = 1000): Float32Array {
  const waveform = new Float32Array(samples);
  for (let i = 0; i < samples; i++) {
    // Generate interesting waveform shape
    const t = i / samples;
    const envelope = Math.sin(t * Math.PI); // Fade in/out
    const noise = (Math.random() - 0.5) * 0.3;
    const sine = Math.sin(t * Math.PI * 8) * 0.5;
    const burst = t > 0.2 && t < 0.4 ? Math.random() * 0.8 : 0;
    waveform[i] = (sine + noise + burst) * envelope;
  }
  return waveform;
}

export default Timeline;
