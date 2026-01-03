/**
 * ReelForge GPU Waveform Renderer
 *
 * WebGL-accelerated waveform visualization using PixiJS:
 * - GPU-rendered peak display
 * - LOD (Level of Detail) for zoom levels
 * - Minimap overview
 * - Selection regions
 * - Playhead cursor
 * - 60fps performance
 *
 * @module waveform/WaveformGPU
 */

import { useRef, useEffect, useCallback, useState } from 'react';
import * as PIXI from 'pixi.js';
import './Waveform.css';

// ============ Types ============

export interface WaveformGPUData {
  /** Peak data (min/max interleaved or just max) */
  peaks: Float32Array;
  /** Number of samples in original audio */
  sampleCount: number;
  /** Sample rate */
  sampleRate: number;
  /** Duration in seconds */
  duration: number;
}

export interface WaveformRegion {
  id: string;
  start: number;
  end: number;
  color?: number;
  alpha?: number;
  label?: string;
}

export interface WaveformGPUProps {
  /** Peak data */
  data?: WaveformGPUData | null;
  /** Audio buffer (alternative to peaks) */
  audioBuffer?: AudioBuffer | null;
  /** Width in pixels */
  width: number;
  /** Height in pixels */
  height: number;
  /** Zoom level (pixels per second) */
  zoom?: number;
  /** Scroll offset (seconds) */
  offset?: number;
  /** Current playhead position (seconds) */
  playhead?: number;
  /** Waveform color */
  waveColor?: number;
  /** Progress color (played portion) */
  progressColor?: number;
  /** Cursor color */
  cursorColor?: number;
  /** Background color */
  backgroundColor?: number;
  /** Grid lines */
  showGrid?: boolean;
  /** Regions */
  regions?: WaveformRegion[];
  /** Mirror waveform (stereo style) */
  mirror?: boolean;
  /** Normalize peaks to 0dB */
  normalize?: boolean;
  /** Show minimap */
  showMinimap?: boolean;
  /** Minimap height */
  minimapHeight?: number;
  /** On click (returns time in seconds) */
  onClick?: (time: number) => void;
  /** On drag selection */
  onSelection?: (start: number, end: number) => void;
  /** On scroll */
  onScroll?: (offset: number) => void;
  /** On zoom */
  onZoom?: (zoom: number) => void;
  /** Custom class */
  className?: string;
}

// ============ Constants ============

const DEFAULT_WAVE_COLOR = 0x4a9eff;
const DEFAULT_PROGRESS_COLOR = 0x7ec8ff;
const DEFAULT_CURSOR_COLOR = 0xffffff;
const DEFAULT_BG_COLOR = 0x1a1a24;
const GRID_COLOR = 0x2a2a3a;
const REGION_DEFAULT_COLOR = 0xffaa00;

const MIN_ZOOM = 10;    // 10 px/s
const MAX_ZOOM = 5000;  // 5000 px/s (detailed)
const DEFAULT_ZOOM = 100;

// LOD thresholds (pixels per peak)
const LOD_THRESHOLDS = {
  HIGH: 4,      // Full detail
  MEDIUM: 2,    // 2x downsampled
  LOW: 1,       // 4x downsampled
  OVERVIEW: 0.5 // 8x downsampled
};

// ============ Peak Extraction ============

function extractPeaksFromBuffer(
  audioBuffer: AudioBuffer,
  targetLength: number
): Float32Array {
  const channels = audioBuffer.numberOfChannels;
  const samplesPerPeak = Math.max(1, Math.floor(audioBuffer.length / targetLength));
  const actualLength = Math.ceil(audioBuffer.length / samplesPerPeak);
  const peaks = new Float32Array(actualLength * 2); // min/max pairs

  for (let i = 0; i < actualLength; i++) {
    let min = 1;
    let max = -1;
    const start = i * samplesPerPeak;
    const end = Math.min(start + samplesPerPeak, audioBuffer.length);

    for (let ch = 0; ch < channels; ch++) {
      const data = audioBuffer.getChannelData(ch);
      for (let j = start; j < end; j++) {
        const sample = data[j];
        if (sample < min) min = sample;
        if (sample > max) max = sample;
      }
    }

    peaks[i * 2] = min;
    peaks[i * 2 + 1] = max;
  }

  return peaks;
}

// ============ LOD Peak Downsampling ============

function downsamplePeaks(peaks: Float32Array, factor: number): Float32Array {
  const inputLength = peaks.length / 2;
  const outputLength = Math.ceil(inputLength / factor);
  const output = new Float32Array(outputLength * 2);

  for (let i = 0; i < outputLength; i++) {
    let min = 1;
    let max = -1;
    const start = i * factor;
    const end = Math.min(start + factor, inputLength);

    for (let j = start; j < end; j++) {
      const pMin = peaks[j * 2];
      const pMax = peaks[j * 2 + 1];
      if (pMin < min) min = pMin;
      if (pMax > max) max = pMax;
    }

    output[i * 2] = min;
    output[i * 2 + 1] = max;
  }

  return output;
}

// ============ Component ============

export function WaveformGPU({
  data,
  audioBuffer,
  width,
  height,
  zoom = DEFAULT_ZOOM,
  offset = 0,
  playhead = 0,
  waveColor = DEFAULT_WAVE_COLOR,
  progressColor = DEFAULT_PROGRESS_COLOR,
  cursorColor = DEFAULT_CURSOR_COLOR,
  backgroundColor = DEFAULT_BG_COLOR,
  showGrid = true,
  regions = [],
  mirror = true,
  normalize = true,
  showMinimap = false,
  minimapHeight = 40,
  onClick,
  onSelection,
  onScroll,
  onZoom,
  className,
}: WaveformGPUProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const appRef = useRef<PIXI.Application | null>(null);
  const graphicsRef = useRef<PIXI.Graphics | null>(null);
  const minimapGraphicsRef = useRef<PIXI.Graphics | null>(null);
  const cursorRef = useRef<PIXI.Graphics | null>(null);
  const regionsContainerRef = useRef<PIXI.Container | null>(null);

  // Peak data with LOD levels
  const [peakData, setPeakData] = useState<{
    full: Float32Array;
    medium: Float32Array;
    low: Float32Array;
    overview: Float32Array;
    duration: number;
    sampleRate: number;
  } | null>(null);

  // Mouse interaction state
  const [isDragging, setIsDragging] = useState(false);
  const [dragStart, setDragStart] = useState<number | null>(null);

  // Extract peaks from audio buffer or use provided data
  useEffect(() => {
    if (audioBuffer) {
      // Target ~4000 peaks for full detail
      const targetLength = Math.min(4000, audioBuffer.length / 100);
      const full = extractPeaksFromBuffer(audioBuffer, targetLength);
      const medium = downsamplePeaks(full, 2);
      const low = downsamplePeaks(full, 4);
      const overview = downsamplePeaks(full, 8);

      setPeakData({
        full,
        medium,
        low,
        overview,
        duration: audioBuffer.duration,
        sampleRate: audioBuffer.sampleRate,
      });
    } else if (data) {
      // Use provided peaks, create LOD versions
      const full = data.peaks;
      const medium = downsamplePeaks(full, 2);
      const low = downsamplePeaks(full, 4);
      const overview = downsamplePeaks(full, 8);

      setPeakData({
        full,
        medium,
        low,
        overview,
        duration: data.duration,
        sampleRate: data.sampleRate,
      });
    }
  }, [audioBuffer, data]);

  // Initialize PixiJS
  useEffect(() => {
    if (!containerRef.current || appRef.current) return;

    const app = new PIXI.Application();

    (async () => {
      await app.init({
        width,
        height: showMinimap ? height + minimapHeight : height,
        backgroundColor,
        antialias: true,
        resolution: window.devicePixelRatio || 1,
        autoDensity: true,
      });

      if (containerRef.current) {
        containerRef.current.appendChild(app.canvas as HTMLCanvasElement);
      }

      // Create graphics objects
      const graphics = new PIXI.Graphics();
      const minimapGraphics = new PIXI.Graphics();
      const cursor = new PIXI.Graphics();
      const regionsContainer = new PIXI.Container();

      app.stage.addChild(regionsContainer);
      app.stage.addChild(graphics);
      if (showMinimap) {
        app.stage.addChild(minimapGraphics);
      }
      app.stage.addChild(cursor);

      appRef.current = app;
      graphicsRef.current = graphics;
      minimapGraphicsRef.current = minimapGraphics;
      cursorRef.current = cursor;
      regionsContainerRef.current = regionsContainer;
    })();

    return () => {
      if (appRef.current) {
        appRef.current.destroy(true, { children: true });
        appRef.current = null;
      }
    };
  }, []);

  // Resize handler
  useEffect(() => {
    if (appRef.current) {
      const totalHeight = showMinimap ? height + minimapHeight : height;
      appRef.current.renderer.resize(width, totalHeight);
    }
  }, [width, height, showMinimap, minimapHeight]);

  // Select appropriate LOD level
  const getLODPeaks = useCallback(() => {
    if (!peakData) return null;

    const pixelsPerPeak = (zoom * peakData.duration) / (peakData.full.length / 2);

    if (pixelsPerPeak >= LOD_THRESHOLDS.HIGH) {
      return { peaks: peakData.full, factor: 1 };
    } else if (pixelsPerPeak >= LOD_THRESHOLDS.MEDIUM) {
      return { peaks: peakData.medium, factor: 2 };
    } else if (pixelsPerPeak >= LOD_THRESHOLDS.LOW) {
      return { peaks: peakData.low, factor: 4 };
    } else {
      return { peaks: peakData.overview, factor: 8 };
    }
  }, [peakData, zoom]);

  // Draw waveform
  const drawWaveform = useCallback(() => {
    const graphics = graphicsRef.current;
    const lod = getLODPeaks();
    if (!graphics || !lod || !peakData) return;

    graphics.clear();

    const { peaks } = lod;
    const peakCount = peaks.length / 2;
    const duration = peakData.duration;
    const waveformHeight = showMinimap ? height : height;

    // Calculate visible range
    const visibleStart = offset;
    const visibleEnd = offset + width / zoom;
    const startPeak = Math.max(0, Math.floor((visibleStart / duration) * peakCount));
    const endPeak = Math.min(peakCount, Math.ceil((visibleEnd / duration) * peakCount));

    // Normalize factor
    let maxPeak = 1;
    if (normalize) {
      for (let i = 0; i < peaks.length; i++) {
        const abs = Math.abs(peaks[i]);
        if (abs > maxPeak) maxPeak = abs;
      }
    }

    // Draw grid
    if (showGrid) {
      graphics.setStrokeStyle({ width: 1, color: GRID_COLOR, alpha: 0.5 });

      // Horizontal center line
      const centerY = waveformHeight / 2;
      graphics.moveTo(0, centerY);
      graphics.lineTo(width, centerY);
      graphics.stroke();

      // Time markers
      const timeStep = getTimeGridStep(zoom);
      const firstTime = Math.ceil(visibleStart / timeStep) * timeStep;
      for (let t = firstTime; t < visibleEnd; t += timeStep) {
        const x = (t - offset) * zoom;
        graphics.moveTo(x, 0);
        graphics.lineTo(x, waveformHeight);
        graphics.stroke();
      }
    }

    // Draw waveform
    const centerY = waveformHeight / 2;
    const scale = (waveformHeight / 2) * 0.9 / maxPeak;

    // Draw as filled polygon for better performance
    graphics.beginFill(waveColor, 0.8);

    // Top half (max values)
    graphics.moveTo(0, centerY);
    for (let i = startPeak; i < endPeak; i++) {
      const x = ((i / peakCount) * duration - offset) * zoom;
      const max = peaks[i * 2 + 1];
      const y = centerY - max * scale;
      graphics.lineTo(x, y);
    }

    // Bottom half (min values, reversed)
    for (let i = endPeak - 1; i >= startPeak; i--) {
      const x = ((i / peakCount) * duration - offset) * zoom;
      const min = peaks[i * 2];
      const y = mirror ? centerY - min * scale : centerY;
      graphics.lineTo(x, y);
    }

    graphics.closePath();
    graphics.endFill();

    // Draw progress overlay (played portion)
    if (playhead > offset) {
      const progressWidth = Math.min((playhead - offset) * zoom, width);
      graphics.beginFill(progressColor, 0.3);
      graphics.rect(0, 0, progressWidth, waveformHeight);
      graphics.endFill();
    }
  }, [
    getLODPeaks, peakData, offset, zoom, width, height,
    waveColor, progressColor, showGrid, mirror, normalize, playhead, showMinimap
  ]);

  // Draw minimap
  const drawMinimap = useCallback(() => {
    const graphics = minimapGraphicsRef.current;
    if (!graphics || !peakData || !showMinimap) return;

    graphics.clear();

    const peaks = peakData.overview;
    const peakCount = peaks.length / 2;
    const y = height;
    const h = minimapHeight;

    // Background
    graphics.beginFill(0x151520);
    graphics.rect(0, y, width, h);
    graphics.endFill();

    // Draw overview waveform
    const centerY = y + h / 2;
    const scale = (h / 2) * 0.8;

    graphics.beginFill(waveColor, 0.5);
    graphics.moveTo(0, centerY);

    for (let i = 0; i < peakCount; i++) {
      const x = (i / peakCount) * width;
      const max = peaks[i * 2 + 1];
      graphics.lineTo(x, centerY - max * scale);
    }

    for (let i = peakCount - 1; i >= 0; i--) {
      const x = (i / peakCount) * width;
      const min = peaks[i * 2];
      graphics.lineTo(x, centerY - min * scale);
    }

    graphics.closePath();
    graphics.endFill();

    // Draw viewport indicator
    const viewStart = (offset / peakData.duration) * width;
    const viewWidth = (width / zoom / peakData.duration) * width;

    graphics.beginFill(0xffffff, 0.2);
    graphics.rect(viewStart, y, viewWidth, h);
    graphics.endFill();

    graphics.setStrokeStyle({ width: 1, color: 0xffffff, alpha: 0.5 });
    graphics.rect(viewStart, y, viewWidth, h);
    graphics.stroke();
  }, [peakData, showMinimap, height, minimapHeight, width, waveColor, offset, zoom]);

  // Draw cursor
  const drawCursor = useCallback(() => {
    const cursor = cursorRef.current;
    if (!cursor || !peakData) return;

    cursor.clear();

    const cursorX = (playhead - offset) * zoom;
    if (cursorX >= 0 && cursorX <= width) {
      cursor.setStrokeStyle({ width: 2, color: cursorColor });
      cursor.moveTo(cursorX, 0);
      cursor.lineTo(cursorX, height);
      cursor.stroke();

      // Cursor head
      cursor.beginFill(cursorColor);
      cursor.moveTo(cursorX - 6, 0);
      cursor.lineTo(cursorX + 6, 0);
      cursor.lineTo(cursorX, 8);
      cursor.closePath();
      cursor.endFill();
    }
  }, [playhead, offset, zoom, width, height, cursorColor, peakData]);

  // Draw regions
  const drawRegions = useCallback(() => {
    const container = regionsContainerRef.current;
    if (!container || !peakData) return;

    container.removeChildren();

    for (const region of regions) {
      const startX = (region.start - offset) * zoom;
      const endX = (region.end - offset) * zoom;

      if (endX < 0 || startX > width) continue;

      const regionGraphics = new PIXI.Graphics();
      regionGraphics.beginFill(region.color ?? REGION_DEFAULT_COLOR, region.alpha ?? 0.3);
      regionGraphics.rect(
        Math.max(0, startX),
        0,
        Math.min(width, endX) - Math.max(0, startX),
        height
      );
      regionGraphics.endFill();

      container.addChild(regionGraphics);
    }
  }, [regions, offset, zoom, width, height, peakData]);

  // Render loop
  useEffect(() => {
    drawWaveform();
    drawMinimap();
    drawCursor();
    drawRegions();
  }, [drawWaveform, drawMinimap, drawCursor, drawRegions]);

  // Mouse handlers
  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    if (!peakData) return;
    const rect = (e.target as HTMLElement).getBoundingClientRect();
    const x = e.clientX - rect.left;
    const clickTime = offset + x / zoom;

    setIsDragging(true);
    setDragStart(clickTime);
  }, [offset, zoom, peakData]);

  const handleMouseMove = useCallback((_e: React.MouseEvent) => {
    if (!isDragging || dragStart === null || !peakData) return;
    // Could draw selection preview here
  }, [isDragging, dragStart, peakData]);

  const handleMouseUp = useCallback((e: React.MouseEvent) => {
    if (!peakData) return;
    const rect = (e.target as HTMLElement).getBoundingClientRect();
    const x = e.clientX - rect.left;
    const releaseTime = offset + x / zoom;

    if (isDragging && dragStart !== null) {
      const start = Math.min(dragStart, releaseTime);
      const end = Math.max(dragStart, releaseTime);

      if (Math.abs(end - start) < 0.01) {
        // Click (not drag)
        onClick?.(releaseTime);
      } else {
        // Selection
        onSelection?.(start, end);
      }
    }

    setIsDragging(false);
    setDragStart(null);
  }, [isDragging, dragStart, offset, zoom, onClick, onSelection, peakData]);

  const handleWheel = useCallback((e: React.WheelEvent) => {
    e.preventDefault();

    if (e.ctrlKey || e.metaKey) {
      // Zoom
      const factor = e.deltaY > 0 ? 0.9 : 1.1;
      const newZoom = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, zoom * factor));
      onZoom?.(newZoom);
    } else {
      // Scroll
      const delta = e.deltaX !== 0 ? e.deltaX : e.deltaY;
      const newOffset = Math.max(0, offset + delta / zoom);
      onScroll?.(newOffset);
    }
  }, [zoom, offset, onZoom, onScroll]);

  return (
    <div
      ref={containerRef}
      className={`waveform-gpu ${className ?? ''}`}
      style={{ width, height: showMinimap ? height + minimapHeight : height }}
      onMouseDown={handleMouseDown}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
      onMouseLeave={handleMouseUp}
      onWheel={handleWheel}
    />
  );
}

// ============ Utility ============

function getTimeGridStep(zoom: number): number {
  // Adaptive grid spacing based on zoom level
  const targetPixels = 100; // Target ~100px between grid lines
  const targetSeconds = targetPixels / zoom;

  // Round to nice values
  const steps = [0.001, 0.005, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30, 60];
  for (const step of steps) {
    if (step >= targetSeconds) return step;
  }
  return 60;
}

export default WaveformGPU;
