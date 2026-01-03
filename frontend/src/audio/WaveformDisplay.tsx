/**
 * ReelForge Waveform Display
 *
 * High-performance waveform visualization using Canvas 2D.
 * Supports:
 * - Zoomable waveform rendering
 * - Selection highlighting
 * - Playhead overlay
 * - Multiple display modes (bars, lines, filled)
 *
 * @module audio/WaveformDisplay
 */

import { useRef, useEffect, useCallback, useState } from 'react';

// ============ Types ============

export interface WaveformDisplayProps {
  /** Waveform data (normalized -1 to 1 or 0 to 1 peaks) */
  data: Float32Array | number[];
  /** Container width */
  width: number;
  /** Container height */
  height: number;
  /** Waveform color */
  color?: string;
  /** Background color */
  backgroundColor?: string;
  /** Display mode */
  mode?: 'bars' | 'line' | 'filled' | 'mirror';
  /** Zoom level (samples per pixel) */
  zoom?: number;
  /** Scroll offset (in samples) */
  offset?: number;
  /** Playhead position (0-1 normalized) */
  playhead?: number;
  /** Playhead color */
  playheadColor?: string;
  /** Selection range [start, end] (0-1 normalized) */
  selection?: [number, number] | null;
  /** Selection color */
  selectionColor?: string;
  /** Show grid lines */
  showGrid?: boolean;
  /** Grid color */
  gridColor?: string;
  /** On click callback (returns normalized position) */
  onClick?: (position: number) => void;
  /** On selection callback */
  onSelect?: (start: number, end: number) => void;
  /** Class name */
  className?: string;
}

// ============ Constants ============

const DEFAULT_COLOR = '#4a9eff';
const DEFAULT_BG_COLOR = '#1a1a1a';
const DEFAULT_PLAYHEAD_COLOR = '#00ff88';
const DEFAULT_SELECTION_COLOR = 'rgba(74, 158, 255, 0.3)';
const DEFAULT_GRID_COLOR = 'rgba(255, 255, 255, 0.1)';

// ============ Component ============

export function WaveformDisplay({
  data,
  width,
  height,
  color = DEFAULT_COLOR,
  backgroundColor = DEFAULT_BG_COLOR,
  mode = 'filled',
  zoom = 1,
  offset = 0,
  playhead,
  playheadColor = DEFAULT_PLAYHEAD_COLOR,
  selection,
  selectionColor = DEFAULT_SELECTION_COLOR,
  showGrid = false,
  gridColor = DEFAULT_GRID_COLOR,
  onClick,
  onSelect,
  className,
}: WaveformDisplayProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [isDragging, setIsDragging] = useState(false);
  const [dragStart, setDragStart] = useState(0);

  // Convert data to Float32Array if needed
  const waveformData = data instanceof Float32Array ? data : new Float32Array(data);

  // ============ Rendering ============

  const render = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.scale(dpr, dpr);

    // Clear background
    ctx.fillStyle = backgroundColor;
    ctx.fillRect(0, 0, width, height);

    // Draw grid
    if (showGrid) {
      drawGrid(ctx, width, height, gridColor);
    }

    // Draw selection
    if (selection) {
      const [selStart, selEnd] = selection;
      const x1 = selStart * width;
      const x2 = selEnd * width;
      ctx.fillStyle = selectionColor;
      ctx.fillRect(x1, 0, x2 - x1, height);
    }

    // Draw waveform
    if (waveformData.length > 0) {
      drawWaveform(ctx, waveformData, width, height, color, mode, zoom, offset);
    }

    // Draw playhead
    if (playhead !== undefined && playhead >= 0 && playhead <= 1) {
      const x = playhead * width;
      ctx.strokeStyle = playheadColor;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, height);
      ctx.stroke();
    }
  }, [
    waveformData,
    width,
    height,
    color,
    backgroundColor,
    mode,
    zoom,
    offset,
    playhead,
    playheadColor,
    selection,
    selectionColor,
    showGrid,
    gridColor,
  ]);

  // Render on changes
  useEffect(() => {
    render();
  }, [render]);

  // ============ Event Handlers ============

  const handleMouseDown = useCallback(
    (e: React.MouseEvent<HTMLCanvasElement>) => {
      const rect = canvasRef.current?.getBoundingClientRect();
      if (!rect) return;

      const x = (e.clientX - rect.left) / rect.width;
      setIsDragging(true);
      setDragStart(x);

      if (onClick && !onSelect) {
        onClick(x);
      }
    },
    [onClick, onSelect]
  );

  const handleMouseMove = useCallback(
    (e: React.MouseEvent<HTMLCanvasElement>) => {
      if (!isDragging || !onSelect) return;

      const rect = canvasRef.current?.getBoundingClientRect();
      if (!rect) return;

      const x = (e.clientX - rect.left) / rect.width;
      const start = Math.min(dragStart, x);
      const end = Math.max(dragStart, x);

      // Visual feedback during drag could be added here
      onSelect(Math.max(0, start), Math.min(1, end));
    },
    [isDragging, dragStart, onSelect]
  );

  const handleMouseUp = useCallback(
    (e: React.MouseEvent<HTMLCanvasElement>) => {
      if (!isDragging) return;

      setIsDragging(false);

      if (onSelect) {
        const rect = canvasRef.current?.getBoundingClientRect();
        if (!rect) return;

        const x = (e.clientX - rect.left) / rect.width;
        const start = Math.min(dragStart, x);
        const end = Math.max(dragStart, x);

        // Only trigger selection if dragged a minimum distance
        if (Math.abs(end - start) > 0.01) {
          onSelect(Math.max(0, start), Math.min(1, end));
        } else if (onClick) {
          onClick(x);
        }
      }
    },
    [isDragging, dragStart, onClick, onSelect]
  );

  const handleMouseLeave = useCallback(() => {
    setIsDragging(false);
  }, []);

  return (
    <canvas
      ref={canvasRef}
      className={className}
      style={{
        width,
        height,
        display: 'block',
        cursor: onClick || onSelect ? 'crosshair' : 'default',
      }}
      onMouseDown={handleMouseDown}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
      onMouseLeave={handleMouseLeave}
    />
  );
}

// ============ Drawing Functions ============

function drawGrid(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  color: string
): void {
  ctx.strokeStyle = color;
  ctx.lineWidth = 1;

  // Vertical lines (time divisions)
  const vDivisions = 10;
  for (let i = 1; i < vDivisions; i++) {
    const x = (width / vDivisions) * i;
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, height);
    ctx.stroke();
  }

  // Horizontal center line
  ctx.beginPath();
  ctx.moveTo(0, height / 2);
  ctx.lineTo(width, height / 2);
  ctx.stroke();

  // Quarter lines
  ctx.strokeStyle = color.replace('0.1', '0.05');
  ctx.beginPath();
  ctx.moveTo(0, height / 4);
  ctx.lineTo(width, height / 4);
  ctx.moveTo(0, (height * 3) / 4);
  ctx.lineTo(width, (height * 3) / 4);
  ctx.stroke();
}

function drawWaveform(
  ctx: CanvasRenderingContext2D,
  data: Float32Array,
  width: number,
  height: number,
  color: string,
  mode: 'bars' | 'line' | 'filled' | 'mirror',
  zoom: number,
  offset: number
): void {
  const samplesPerPixel = Math.max(1, Math.floor(data.length / width / zoom));
  const startSample = Math.floor(offset);
  const centerY = height / 2;

  ctx.fillStyle = color;
  ctx.strokeStyle = color;
  ctx.lineWidth = 1;

  if (mode === 'line') {
    ctx.beginPath();
    for (let x = 0; x < width; x++) {
      const sampleIndex = startSample + x * samplesPerPixel;
      if (sampleIndex >= data.length) break;

      // Get min/max for this pixel
      let min = 1;
      let max = -1;
      for (let s = 0; s < samplesPerPixel; s++) {
        const idx = sampleIndex + s;
        if (idx < data.length) {
          const val = data[idx];
          if (val < min) min = val;
          if (val > max) max = val;
        }
      }

      const avg = (min + max) / 2;
      const y = centerY - avg * centerY;

      if (x === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.stroke();
  } else if (mode === 'bars') {
    const barWidth = Math.max(1, Math.floor(width / (data.length / samplesPerPixel)));

    for (let x = 0; x < width; x += barWidth + 1) {
      const sampleIndex = startSample + Math.floor((x / width) * (data.length / zoom));
      if (sampleIndex >= data.length) break;

      // Get max amplitude for this bar
      let maxAmp = 0;
      for (let s = 0; s < samplesPerPixel; s++) {
        const idx = sampleIndex + s;
        if (idx < data.length) {
          maxAmp = Math.max(maxAmp, Math.abs(data[idx]));
        }
      }

      const barHeight = maxAmp * height;
      const y = (height - barHeight) / 2;
      ctx.fillRect(x, y, barWidth, barHeight);
    }
  } else if (mode === 'filled' || mode === 'mirror') {
    ctx.beginPath();
    ctx.moveTo(0, centerY);

    // Draw top half
    for (let x = 0; x < width; x++) {
      const sampleIndex = startSample + x * samplesPerPixel;
      if (sampleIndex >= data.length) break;

      let max = 0;
      for (let s = 0; s < samplesPerPixel; s++) {
        const idx = sampleIndex + s;
        if (idx < data.length) {
          max = Math.max(max, Math.abs(data[idx]));
        }
      }

      const y = centerY - max * centerY;
      ctx.lineTo(x, y);
    }

    // Draw bottom half (mirror)
    for (let x = width - 1; x >= 0; x--) {
      const sampleIndex = startSample + x * samplesPerPixel;
      if (sampleIndex >= data.length) continue;

      let max = 0;
      for (let s = 0; s < samplesPerPixel; s++) {
        const idx = sampleIndex + s;
        if (idx < data.length) {
          max = Math.max(max, Math.abs(data[idx]));
        }
      }

      const y = centerY + max * centerY;
      ctx.lineTo(x, y);
    }

    ctx.closePath();
    ctx.fill();

    // Add center line for mirror mode
    if (mode === 'mirror') {
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.2)';
      ctx.beginPath();
      ctx.moveTo(0, centerY);
      ctx.lineTo(width, centerY);
      ctx.stroke();
    }
  }
}

// ============ Utility Functions ============

/**
 * Generate waveform peaks from audio buffer.
 */
export function generateWaveformPeaks(
  audioBuffer: AudioBuffer,
  targetLength: number = 1000
): Float32Array {
  const channelData = audioBuffer.getChannelData(0);
  const samplesPerPeak = Math.floor(channelData.length / targetLength);
  const peaks = new Float32Array(targetLength);

  for (let i = 0; i < targetLength; i++) {
    let max = 0;
    const start = i * samplesPerPeak;
    const end = Math.min(start + samplesPerPeak, channelData.length);

    for (let j = start; j < end; j++) {
      const abs = Math.abs(channelData[j]);
      if (abs > max) max = abs;
    }

    peaks[i] = max;
  }

  return peaks;
}

/**
 * Generate stereo waveform peaks.
 */
export function generateStereoWaveformPeaks(
  audioBuffer: AudioBuffer,
  targetLength: number = 1000
): { left: Float32Array; right: Float32Array } {
  const left = generateWaveformPeaks(
    {
      getChannelData: () => audioBuffer.getChannelData(0),
    } as unknown as AudioBuffer,
    targetLength
  );

  const right =
    audioBuffer.numberOfChannels > 1
      ? generateWaveformPeaks(
          {
            getChannelData: () => audioBuffer.getChannelData(1),
          } as unknown as AudioBuffer,
          targetLength
        )
      : left;

  return { left, right };
}

/**
 * Downsample waveform for display at different zoom levels.
 */
export function downsampleWaveform(
  data: Float32Array,
  factor: number
): Float32Array {
  const newLength = Math.ceil(data.length / factor);
  const result = new Float32Array(newLength);

  for (let i = 0; i < newLength; i++) {
    let max = 0;
    const start = i * factor;
    const end = Math.min(start + factor, data.length);

    for (let j = start; j < end; j++) {
      const abs = Math.abs(data[j]);
      if (abs > max) max = abs;
    }

    result[i] = max;
  }

  return result;
}

export default WaveformDisplay;
