/**
 * ReelForge PixiJS Waveform Visualizer
 *
 * High-performance WebGL-based audio waveform visualization.
 * Optimized for 60fps rendering with PixiJS.
 *
 * @module components/PixiWaveform
 */

import { useRef, useEffect, useCallback } from 'react';
import * as PIXI from 'pixi.js';
import gsap from 'gsap';

// ============ Types ============

export type WaveformStyle = 'fill' | 'line' | 'bars' | 'gradient';

export interface PixiWaveformProps {
  /** Waveform sample data (-1 to 1 range) */
  samples: Float32Array | number[];
  /** Width in pixels */
  width: number;
  /** Height in pixels */
  height: number;
  /** Visual style */
  style?: WaveformStyle;
  /** Primary waveform color (hex) */
  color?: number;
  /** Secondary color for gradient/fills (hex) */
  secondaryColor?: number;
  /** Background color (hex) */
  backgroundColor?: number;
  /** Playhead position (0-1) */
  playhead?: number;
  /** Playhead color (hex) */
  playheadColor?: number;
  /** Selection range [start, end] (0-1) */
  selection?: [number, number] | null;
  /** Selection color (hex) */
  selectionColor?: number;
  /** Show center line */
  showCenterLine?: boolean;
  /** Center line color */
  centerLineColor?: number;
  /** Zoom level (1 = full view) */
  zoom?: number;
  /** Scroll offset when zoomed (0-1) */
  scrollOffset?: number;
  /** Whether to animate playhead */
  animatePlayhead?: boolean;
  /** Click handler for seeking */
  onSeek?: (position: number) => void;
  /** Selection change handler */
  onSelectionChange?: (selection: [number, number] | null) => void;
}

// ============ Constants ============

const DEFAULT_COLOR = 0x00d4ff;
const DEFAULT_SECONDARY = 0x0066aa;
const DEFAULT_BG = 0x0d0d12;
const DEFAULT_PLAYHEAD = 0xff3366;
const DEFAULT_SELECTION = 0x6366f1;
const DEFAULT_CENTERLINE = 0x333340;

// ============ Component ============

export function PixiWaveform({
  samples,
  width,
  height,
  style = 'fill',
  color = DEFAULT_COLOR,
  secondaryColor = DEFAULT_SECONDARY,
  backgroundColor = DEFAULT_BG,
  playhead = 0,
  playheadColor = DEFAULT_PLAYHEAD,
  selection = null,
  selectionColor = DEFAULT_SELECTION,
  showCenterLine = true,
  centerLineColor = DEFAULT_CENTERLINE,
  zoom = 1,
  scrollOffset = 0,
  animatePlayhead = true,
  onSeek,
  onSelectionChange,
}: PixiWaveformProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const appRef = useRef<PIXI.Application | null>(null);
  const waveformGraphicsRef = useRef<PIXI.Graphics | null>(null);
  const overlayGraphicsRef = useRef<PIXI.Graphics | null>(null);
  const playheadLineRef = useRef<PIXI.Graphics | null>(null);
  const isDraggingRef = useRef(false);
  const dragStartRef = useRef(0);

  // Initialize PixiJS
  useEffect(() => {
    if (!containerRef.current) return;

    const initPixi = async () => {
      const app = new PIXI.Application();

      await app.init({
        width,
        height,
        backgroundColor,
        antialias: true,
        resolution: window.devicePixelRatio || 1,
        autoDensity: true,
      });

      containerRef.current?.appendChild(app.canvas);
      appRef.current = app;

      // Create graphics layers
      const waveformGraphics = new PIXI.Graphics();
      const overlayGraphics = new PIXI.Graphics();
      const playheadLine = new PIXI.Graphics();

      app.stage.addChild(waveformGraphics);
      app.stage.addChild(overlayGraphics);
      app.stage.addChild(playheadLine);

      waveformGraphicsRef.current = waveformGraphics;
      overlayGraphicsRef.current = overlayGraphics;
      playheadLineRef.current = playheadLine;

      // Enable interactivity
      app.stage.eventMode = 'static';
      app.stage.hitArea = new PIXI.Rectangle(0, 0, width, height);
    };

    initPixi();

    return () => {
      if (appRef.current) {
        appRef.current.destroy(true, { children: true });
        appRef.current = null;
      }
    };
  }, []);

  // Update size
  useEffect(() => {
    if (appRef.current) {
      appRef.current.renderer.resize(width, height);
      if (appRef.current.stage.hitArea) {
        (appRef.current.stage.hitArea as PIXI.Rectangle).width = width;
        (appRef.current.stage.hitArea as PIXI.Rectangle).height = height;
      }
    }
  }, [width, height]);

  // Draw waveform
  const drawWaveform = useCallback(() => {
    const graphics = waveformGraphicsRef.current;
    if (!graphics || samples.length === 0) return;

    graphics.clear();

    const centerY = height / 2;
    const samplesArray = Array.from(samples);

    // Calculate visible range based on zoom and scroll
    const totalSamples = samplesArray.length;
    const visibleSamples = Math.floor(totalSamples / zoom);
    const startSample = Math.floor(scrollOffset * (totalSamples - visibleSamples));
    const endSample = Math.min(startSample + visibleSamples, totalSamples);

    // Calculate step for drawing
    const step = Math.max(1, Math.floor(visibleSamples / width));
    const pixelsPerSample = width / visibleSamples;

    // Draw center line first
    if (showCenterLine) {
      graphics.moveTo(0, centerY);
      graphics.lineTo(width, centerY);
      graphics.stroke({ width: 1, color: centerLineColor, alpha: 0.5 });
    }

    switch (style) {
      case 'fill':
        drawFillWaveform(
          graphics,
          samplesArray,
          startSample,
          endSample,
          step,
          pixelsPerSample,
          centerY,
          height,
          color,
          secondaryColor
        );
        break;
      case 'line':
        drawLineWaveform(
          graphics,
          samplesArray,
          startSample,
          endSample,
          step,
          pixelsPerSample,
          centerY,
          height,
          color
        );
        break;
      case 'bars':
        drawBarsWaveform(
          graphics,
          samplesArray,
          startSample,
          endSample,
          step,
          pixelsPerSample,
          centerY,
          height,
          color
        );
        break;
      case 'gradient':
        drawGradientWaveform(
          graphics,
          samplesArray,
          startSample,
          endSample,
          step,
          pixelsPerSample,
          centerY,
          height,
          color,
          secondaryColor
        );
        break;
    }
  }, [
    samples,
    width,
    height,
    style,
    color,
    secondaryColor,
    showCenterLine,
    centerLineColor,
    zoom,
    scrollOffset,
  ]);

  // Draw selection overlay
  const drawOverlay = useCallback(() => {
    const graphics = overlayGraphicsRef.current;
    if (!graphics) return;

    graphics.clear();

    if (selection) {
      const [start, end] = selection;
      const x1 = start * width;
      const x2 = end * width;

      graphics.rect(x1, 0, x2 - x1, height);
      graphics.fill({ color: selectionColor, alpha: 0.2 });

      // Selection edges
      graphics.moveTo(x1, 0);
      graphics.lineTo(x1, height);
      graphics.stroke({ width: 2, color: selectionColor, alpha: 0.6 });

      graphics.moveTo(x2, 0);
      graphics.lineTo(x2, height);
      graphics.stroke({ width: 2, color: selectionColor, alpha: 0.6 });
    }
  }, [selection, width, height, selectionColor]);

  // Draw playhead
  const drawPlayhead = useCallback(() => {
    const graphics = playheadLineRef.current;
    if (!graphics) return;

    graphics.clear();

    const x = playhead * width;

    // Main line
    graphics.moveTo(x, 0);
    graphics.lineTo(x, height);
    graphics.stroke({ width: 2, color: playheadColor });

    // Glow effect
    graphics.moveTo(x, 0);
    graphics.lineTo(x, height);
    graphics.stroke({ width: 6, color: playheadColor, alpha: 0.3 });

    // Top indicator
    graphics.moveTo(x - 6, 0);
    graphics.lineTo(x + 6, 0);
    graphics.lineTo(x, 8);
    graphics.closePath();
    graphics.fill({ color: playheadColor });
  }, [playhead, width, height, playheadColor]);

  // Animate playhead with GSAP
  useEffect(() => {
    if (!animatePlayhead || !playheadLineRef.current) return;

    gsap.to(playheadLineRef.current, {
      x: 0, // Trigger redraw
      duration: 0,
      onComplete: drawPlayhead,
    });
  }, [playhead, animatePlayhead, drawPlayhead]);

  // Redraw on changes
  useEffect(() => {
    drawWaveform();
    drawOverlay();
    drawPlayhead();
  }, [drawWaveform, drawOverlay, drawPlayhead]);

  // Mouse handlers for seeking/selection
  useEffect(() => {
    const app = appRef.current;
    if (!app) return;

    const handlePointerDown = (e: PIXI.FederatedPointerEvent) => {
      const position = e.global.x / width;
      isDraggingRef.current = true;
      dragStartRef.current = position;

      if (onSeek) {
        onSeek(position);
      }
    };

    const handlePointerMove = (e: PIXI.FederatedPointerEvent) => {
      if (!isDraggingRef.current) return;

      const position = Math.max(0, Math.min(1, e.global.x / width));

      if (onSelectionChange && Math.abs(position - dragStartRef.current) > 0.01) {
        const start = Math.min(dragStartRef.current, position);
        const end = Math.max(dragStartRef.current, position);
        onSelectionChange([start, end]);
      }
    };

    const handlePointerUp = () => {
      isDraggingRef.current = false;
    };

    app.stage.on('pointerdown', handlePointerDown);
    app.stage.on('pointermove', handlePointerMove);
    app.stage.on('pointerup', handlePointerUp);
    app.stage.on('pointerupoutside', handlePointerUp);

    return () => {
      app.stage.off('pointerdown', handlePointerDown);
      app.stage.off('pointermove', handlePointerMove);
      app.stage.off('pointerup', handlePointerUp);
      app.stage.off('pointerupoutside', handlePointerUp);
    };
  }, [width, onSeek, onSelectionChange]);

  return (
    <div
      ref={containerRef}
      style={{
        width: `${width}px`,
        height: `${height}px`,
        overflow: 'hidden',
        borderRadius: '8px',
        cursor: 'crosshair',
      }}
    />
  );
}

// ============ Drawing Functions ============

function drawFillWaveform(
  graphics: PIXI.Graphics,
  samples: number[],
  start: number,
  end: number,
  step: number,
  pixelsPerSample: number,
  centerY: number,
  _height: number,
  color: number,
  secondaryColor: number
) {
  const points: { x: number; min: number; max: number }[] = [];

  for (let i = start; i < end; i += step) {
    let min = 0;
    let max = 0;

    for (let j = 0; j < step && i + j < end; j++) {
      const sample = samples[i + j] || 0;
      min = Math.min(min, sample);
      max = Math.max(max, sample);
    }

    const x = (i - start) * pixelsPerSample;
    points.push({
      x,
      min: centerY + min * centerY * 0.9,
      max: centerY - max * centerY * 0.9,
    });
  }

  if (points.length === 0) return;

  // Draw top half
  graphics.moveTo(points[0].x, centerY);
  for (const p of points) {
    graphics.lineTo(p.x, p.max);
  }
  graphics.lineTo(points[points.length - 1].x, centerY);
  graphics.closePath();
  graphics.fill({ color, alpha: 0.7 });

  // Draw bottom half
  graphics.moveTo(points[0].x, centerY);
  for (const p of points) {
    graphics.lineTo(p.x, p.min);
  }
  graphics.lineTo(points[points.length - 1].x, centerY);
  graphics.closePath();
  graphics.fill({ color: secondaryColor, alpha: 0.5 });
}

function drawLineWaveform(
  graphics: PIXI.Graphics,
  samples: number[],
  start: number,
  end: number,
  step: number,
  pixelsPerSample: number,
  centerY: number,
  _height: number,
  color: number
) {
  let first = true;

  for (let i = start; i < end; i += step) {
    let sum = 0;
    let count = 0;

    for (let j = 0; j < step && i + j < end; j++) {
      sum += samples[i + j] || 0;
      count++;
    }

    const avg = count > 0 ? sum / count : 0;
    const x = (i - start) * pixelsPerSample;
    const y = centerY - avg * centerY * 0.9;

    if (first) {
      graphics.moveTo(x, y);
      first = false;
    } else {
      graphics.lineTo(x, y);
    }
  }

  graphics.stroke({ width: 1.5, color, alpha: 0.9 });
}

function drawBarsWaveform(
  graphics: PIXI.Graphics,
  samples: number[],
  start: number,
  end: number,
  step: number,
  pixelsPerSample: number,
  centerY: number,
  _height: number,
  color: number
) {
  const barWidth = Math.max(1, pixelsPerSample * step * 0.8);

  for (let i = start; i < end; i += step) {
    let min = 0;
    let max = 0;

    for (let j = 0; j < step && i + j < end; j++) {
      const sample = samples[i + j] || 0;
      min = Math.min(min, sample);
      max = Math.max(max, sample);
    }

    const x = (i - start) * pixelsPerSample;
    const topY = centerY - max * centerY * 0.9;
    const bottomY = centerY - min * centerY * 0.9;
    const barHeight = bottomY - topY;

    graphics.rect(x, topY, barWidth, barHeight);
    graphics.fill({ color, alpha: 0.8 });
  }
}

function drawGradientWaveform(
  graphics: PIXI.Graphics,
  samples: number[],
  start: number,
  end: number,
  _step: number,
  pixelsPerSample: number,
  centerY: number,
  _height: number,
  color: number,
  secondaryColor: number
) {
  const segments = 50;
  const segmentWidth = Math.ceil((end - start) / segments);

  for (let seg = 0; seg < segments; seg++) {
    const segStart = start + seg * segmentWidth;
    const segEnd = Math.min(segStart + segmentWidth, end);

    let min = 0;
    let max = 0;

    for (let i = segStart; i < segEnd; i++) {
      const sample = samples[i] || 0;
      min = Math.min(min, sample);
      max = Math.max(max, sample);
    }

    const x = (segStart - start) * pixelsPerSample;
    const w = (segEnd - segStart) * pixelsPerSample;
    const topY = centerY - max * centerY * 0.9;
    const bottomY = centerY - min * centerY * 0.9;

    const t = seg / segments;
    const segColor = lerpColor(color, secondaryColor, t);

    graphics.rect(x, topY, w, bottomY - topY);
    graphics.fill({ color: segColor, alpha: 0.75 });
  }
}

// ============ Utilities ============

function lerpColor(color1: number, color2: number, t: number): number {
  const r1 = (color1 >> 16) & 0xff;
  const g1 = (color1 >> 8) & 0xff;
  const b1 = color1 & 0xff;

  const r2 = (color2 >> 16) & 0xff;
  const g2 = (color2 >> 8) & 0xff;
  const b2 = color2 & 0xff;

  const r = Math.round(r1 + (r2 - r1) * t);
  const g = Math.round(g1 + (g2 - g1) * t);
  const b = Math.round(b1 + (b2 - b1) * t);

  return (r << 16) | (g << 8) | b;
}

// ============ Preset Configurations ============

export const waveformPresets = {
  default: {
    style: 'fill' as const,
    color: 0x00d4ff,
    secondaryColor: 0x0066aa,
    showCenterLine: true,
  },
  minimal: {
    style: 'line' as const,
    color: 0x6366f1,
    showCenterLine: false,
  },
  bars: {
    style: 'bars' as const,
    color: 0x00ff88,
    secondaryColor: 0x008844,
    showCenterLine: true,
  },
  gradient: {
    style: 'gradient' as const,
    color: 0xff6b00,
    secondaryColor: 0x9900ff,
    showCenterLine: true,
  },
} as const;

export default PixiWaveform;
