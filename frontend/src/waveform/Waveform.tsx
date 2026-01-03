/**
 * ReelForge Waveform
 *
 * Audio waveform visualization:
 * - Canvas-based rendering
 * - Peak/RMS display modes
 * - Zoom/scroll support
 * - Selection/region
 * - Playhead cursor
 *
 * @module waveform/Waveform
 */

import { useRef, useEffect, useCallback, useState } from 'react';
import './Waveform.css';

// ============ Types ============

export interface WaveformData {
  peaks: Float32Array;
  length: number;
  sampleRate: number;
  duration: number;
}

export interface WaveformRegion {
  id: string;
  start: number;
  end: number;
  color?: string;
  label?: string;
}

export interface WaveformProps {
  /** Audio buffer or peaks data */
  audioBuffer?: AudioBuffer | null;
  /** Pre-computed peaks */
  peaks?: Float32Array;
  /** Duration in seconds */
  duration?: number;
  /** Zoom level (pixels per second) */
  zoom?: number;
  /** Scroll offset (seconds) */
  offset?: number;
  /** Current playhead position (seconds) */
  playhead?: number;
  /** Waveform color */
  waveColor?: string;
  /** Progress color (played portion) */
  progressColor?: string;
  /** Cursor color */
  cursorColor?: string;
  /** Background color */
  backgroundColor?: string;
  /** Regions */
  regions?: WaveformRegion[];
  /** Height */
  height?: number;
  /** Display mode */
  mode?: 'peaks' | 'bars' | 'line';
  /** Mirror waveform */
  mirror?: boolean;
  /** Normalize peaks */
  normalize?: boolean;
  /** On click (returns time in seconds) */
  onClick?: (time: number) => void;
  /** On region select */
  onRegionSelect?: (start: number, end: number) => void;
  /** On scroll */
  onScroll?: (offset: number) => void;
  /** Custom class */
  className?: string;
}

// ============ Peak Extraction ============

function extractPeaks(audioBuffer: AudioBuffer, samplesPerPixel: number): Float32Array {
  const channels = audioBuffer.numberOfChannels;
  const length = Math.ceil(audioBuffer.length / samplesPerPixel);
  const peaks = new Float32Array(length);

  for (let i = 0; i < length; i++) {
    let max = 0;
    const start = i * samplesPerPixel;
    const end = Math.min(start + samplesPerPixel, audioBuffer.length);

    for (let ch = 0; ch < channels; ch++) {
      const data = audioBuffer.getChannelData(ch);
      for (let j = start; j < end; j++) {
        const abs = Math.abs(data[j]);
        if (abs > max) max = abs;
      }
    }

    peaks[i] = max;
  }

  return peaks;
}

// ============ Waveform Component ============

export function Waveform({
  audioBuffer,
  peaks: externalPeaks,
  duration: externalDuration,
  zoom = 100,
  offset = 0,
  playhead,
  waveColor = '#6366f1',
  progressColor = '#818cf8',
  cursorColor = '#ef4444',
  backgroundColor = 'transparent',
  regions = [],
  height = 128,
  mode = 'peaks',
  mirror = true,
  normalize = true,
  onClick,
  onRegionSelect,
  onScroll,
  className = '',
}: WaveformProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [isSelecting, setIsSelecting] = useState(false);
  const [selectionStart, setSelectionStart] = useState<number | null>(null);
  const [peaks, setPeaks] = useState<Float32Array | null>(externalPeaks || null);

  const duration = externalDuration || audioBuffer?.duration || 0;
  const totalWidth = duration * zoom;

  // Extract peaks from audio buffer
  useEffect(() => {
    if (externalPeaks) {
      setPeaks(externalPeaks);
      return;
    }

    if (!audioBuffer) {
      setPeaks(null);
      return;
    }

    const samplesPerPixel = Math.max(1, Math.floor(audioBuffer.sampleRate / zoom));
    const extracted = extractPeaks(audioBuffer, samplesPerPixel);
    setPeaks(extracted);
  }, [audioBuffer, externalPeaks, zoom]);

  // Draw waveform
  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    const container = containerRef.current;
    if (!canvas || !container || !peaks) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const { width } = container.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;

    // Set canvas size
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    ctx.scale(dpr, dpr);

    // Clear
    ctx.fillStyle = backgroundColor;
    ctx.fillRect(0, 0, width, height);

    // Calculate visible range
    const startTime = offset;
    const endTime = offset + width / zoom;
    const startSample = Math.floor((startTime / duration) * peaks.length);
    const endSample = Math.ceil((endTime / duration) * peaks.length);

    // Find max for normalization
    let maxPeak = 1;
    if (normalize) {
      for (let i = startSample; i < endSample && i < peaks.length; i++) {
        if (peaks[i] > maxPeak) maxPeak = peaks[i];
      }
    }

    const centerY = height / 2;
    const halfHeight = (height / 2) * 0.9;

    // Draw regions first
    for (const region of regions) {
      const regionStartX = (region.start - offset) * zoom;
      const regionEndX = (region.end - offset) * zoom;

      if (regionEndX < 0 || regionStartX > width) continue;

      ctx.fillStyle = region.color || 'rgba(99, 102, 241, 0.2)';
      ctx.fillRect(
        Math.max(0, regionStartX),
        0,
        Math.min(width, regionEndX) - Math.max(0, regionStartX),
        height
      );
    }

    // Draw waveform
    const _samplesPerPixel = peaks.length / totalWidth;
    void _samplesPerPixel; // Reserved for future precise rendering

    ctx.beginPath();
    ctx.fillStyle = waveColor;

    if (mode === 'bars') {
      const barWidth = Math.max(1, 2);
      const gap = 1;

      for (let x = 0; x < width; x += barWidth + gap) {
        const time = offset + x / zoom;
        const sampleIndex = Math.floor((time / duration) * peaks.length);
        if (sampleIndex < 0 || sampleIndex >= peaks.length) continue;

        const peak = peaks[sampleIndex] / maxPeak;
        const barHeight = peak * halfHeight;

        if (mirror) {
          ctx.fillRect(x, centerY - barHeight, barWidth, barHeight * 2);
        } else {
          ctx.fillRect(x, height - barHeight * 2, barWidth, barHeight * 2);
        }
      }
    } else if (mode === 'line') {
      ctx.strokeStyle = waveColor;
      ctx.lineWidth = 1;
      ctx.beginPath();

      for (let x = 0; x < width; x++) {
        const time = offset + x / zoom;
        const sampleIndex = Math.floor((time / duration) * peaks.length);
        if (sampleIndex < 0 || sampleIndex >= peaks.length) continue;

        const peak = peaks[sampleIndex] / maxPeak;
        const y = centerY - peak * halfHeight;

        if (x === 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
      }

      ctx.stroke();
    } else {
      // Peaks mode (default)
      for (let x = 0; x < width; x++) {
        const time = offset + x / zoom;
        const sampleIndex = Math.floor((time / duration) * peaks.length);
        if (sampleIndex < 0 || sampleIndex >= peaks.length) continue;

        const peak = peaks[sampleIndex] / maxPeak;
        const peakHeight = peak * halfHeight;

        if (mirror) {
          ctx.fillRect(x, centerY - peakHeight, 1, peakHeight * 2);
        } else {
          ctx.fillRect(x, height - peakHeight * 2, 1, peakHeight * 2);
        }
      }
    }

    // Draw progress overlay
    if (playhead !== undefined && playhead > offset) {
      const progressX = (playhead - offset) * zoom;
      ctx.fillStyle = progressColor;
      ctx.globalAlpha = 0.3;
      ctx.fillRect(0, 0, Math.min(progressX, width), height);
      ctx.globalAlpha = 1;
    }

    // Draw playhead cursor
    if (playhead !== undefined) {
      const cursorX = (playhead - offset) * zoom;
      if (cursorX >= 0 && cursorX <= width) {
        ctx.strokeStyle = cursorColor;
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(cursorX, 0);
        ctx.lineTo(cursorX, height);
        ctx.stroke();
      }
    }
  }, [
    peaks,
    duration,
    zoom,
    offset,
    playhead,
    waveColor,
    progressColor,
    cursorColor,
    backgroundColor,
    regions,
    height,
    mode,
    mirror,
    normalize,
    totalWidth,
  ]);

  // Redraw on changes
  useEffect(() => {
    draw();
  }, [draw]);

  // Handle resize
  useEffect(() => {
    const handleResize = () => draw();
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, [draw]);

  // Mouse handlers
  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      const rect = containerRef.current?.getBoundingClientRect();
      if (!rect) return;

      const x = e.clientX - rect.left;
      const time = offset + x / zoom;

      setIsSelecting(true);
      setSelectionStart(time);
    },
    [offset, zoom]
  );

  const handleMouseUp = useCallback(
    (e: React.MouseEvent) => {
      if (!isSelecting) return;

      const rect = containerRef.current?.getBoundingClientRect();
      if (!rect) return;

      const x = e.clientX - rect.left;
      const time = offset + x / zoom;

      if (selectionStart !== null) {
        const diff = Math.abs(time - selectionStart);

        if (diff < 0.05) {
          // Click
          onClick?.(time);
        } else {
          // Selection
          onRegionSelect?.(
            Math.min(selectionStart, time),
            Math.max(selectionStart, time)
          );
        }
      }

      setIsSelecting(false);
      setSelectionStart(null);
    },
    [isSelecting, selectionStart, offset, zoom, onClick, onRegionSelect]
  );

  // Scroll handler
  const handleWheel = useCallback(
    (e: React.WheelEvent) => {
      if (e.shiftKey) {
        // Horizontal scroll
        const delta = e.deltaY / zoom;
        const newOffset = Math.max(0, Math.min(duration - 1, offset + delta));
        onScroll?.(newOffset);
      }
    },
    [zoom, offset, duration, onScroll]
  );

  return (
    <div
      ref={containerRef}
      className={`waveform ${className}`}
      style={{ height }}
      onMouseDown={handleMouseDown}
      onMouseUp={handleMouseUp}
      onWheel={handleWheel}
    >
      <canvas ref={canvasRef} className="waveform__canvas" />
    </div>
  );
}

// ============ useWaveform Hook ============

export function useWaveform(audioBuffer: AudioBuffer | null, zoom = 100) {
  const [peaks, setPeaks] = useState<Float32Array | null>(null);

  useEffect(() => {
    if (!audioBuffer) {
      setPeaks(null);
      return;
    }

    const samplesPerPixel = Math.max(1, Math.floor(audioBuffer.sampleRate / zoom));
    const extracted = extractPeaks(audioBuffer, samplesPerPixel);
    setPeaks(extracted);
  }, [audioBuffer, zoom]);

  return {
    peaks,
    duration: audioBuffer?.duration || 0,
    sampleRate: audioBuffer?.sampleRate || 44100,
  };
}

export default Waveform;
