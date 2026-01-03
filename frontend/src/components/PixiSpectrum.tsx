/**
 * ReelForge PixiJS Spectrum Visualizer
 *
 * High-performance WebGL-based audio spectrum visualization.
 * Optimized for 60fps rendering with PixiJS.
 *
 * @module components/PixiSpectrum
 */

import { useRef, useEffect, useCallback } from 'react';
import * as PIXI from 'pixi.js';

// ============ Types ============

export type VisualizationType = 'bars' | 'line' | 'mirror' | 'circular';

export interface PixiSpectrumProps {
  /** FFT data array (0-255 values) */
  fftData: Uint8Array | number[];
  /** Width in pixels */
  width: number;
  /** Height in pixels */
  height: number;
  /** Visualization type */
  type?: VisualizationType;
  /** Primary color (hex) */
  primaryColor?: number;
  /** Secondary color for gradient (hex) */
  secondaryColor?: number;
  /** Background color (hex) */
  backgroundColor?: number;
  /** Number of bars (for bar visualization) */
  barCount?: number;
  /** Gap between bars (0-1) */
  barGap?: number;
  /** Smoothing factor (0-1, higher = more smooth) */
  smoothing?: number;
  /** Mirror horizontally */
  mirror?: boolean;
  /** Glow effect intensity (0-1) */
  glowIntensity?: number;
  /** Line thickness for line mode */
  lineWidth?: number;
  /** Whether the visualizer is active */
  active?: boolean;
}

// ============ Constants ============

const DEFAULT_PRIMARY = 0x00d4ff;
const DEFAULT_SECONDARY = 0xff00aa;
const DEFAULT_BG = 0x0d0d12;

// ============ Component ============

export function PixiSpectrum({
  fftData,
  width,
  height,
  type = 'bars',
  primaryColor = DEFAULT_PRIMARY,
  secondaryColor = DEFAULT_SECONDARY,
  backgroundColor = DEFAULT_BG,
  barCount = 64,
  barGap = 0.2,
  smoothing = 0.7,
  mirror = false,
  glowIntensity = 0.3,
  lineWidth = 2,
  active = true,
}: PixiSpectrumProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const appRef = useRef<PIXI.Application | null>(null);
  const graphicsRef = useRef<PIXI.Graphics | null>(null);
  const smoothedDataRef = useRef<number[]>([]);
  const rafRef = useRef<number>(0);

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

      // Create main graphics object
      const graphics = new PIXI.Graphics();
      app.stage.addChild(graphics);
      graphicsRef.current = graphics;

      // Initialize smoothed data
      smoothedDataRef.current = new Array(barCount).fill(0);
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

  // Update size
  useEffect(() => {
    if (appRef.current) {
      appRef.current.renderer.resize(width, height);
    }
  }, [width, height]);

  // Draw bars visualization
  const drawBars = useCallback(
    (graphics: PIXI.Graphics, data: number[]) => {
      const barWidth = (width / barCount) * (1 - barGap);
      const gap = (width / barCount) * barGap;
      const totalBarWidth = barWidth + gap;

      for (let i = 0; i < barCount; i++) {
        const value = data[i] || 0;
        const barHeight = (value / 255) * height * 0.9;

        const x = i * totalBarWidth;
        const y = height - barHeight;

        // Gradient effect via multiple rectangles
        const segments = 10;
        const segmentHeight = barHeight / segments;

        for (let j = 0; j < segments; j++) {
          const t = j / segments;
          const color = lerpColor(primaryColor, secondaryColor, t);
          const alpha = 0.4 + t * 0.6;

          graphics.rect(x, y + j * segmentHeight, barWidth, segmentHeight);
          graphics.fill({ color, alpha });
        }

        // Glow cap
        if (glowIntensity > 0 && barHeight > 5) {
          graphics.rect(x - 2, y - 2, barWidth + 4, 4);
          graphics.fill({ color: primaryColor, alpha: glowIntensity });
        }
      }
    },
    [width, height, barCount, barGap, primaryColor, secondaryColor, glowIntensity]
  );

  // Draw line visualization
  const drawLine = useCallback(
    (graphics: PIXI.Graphics, data: number[]) => {
      const points: number[] = [];
      const stepX = width / (data.length - 1);

      for (let i = 0; i < data.length; i++) {
        const value = data[i] || 0;
        const x = i * stepX;
        const y = height - (value / 255) * height * 0.9;
        points.push(x, y);
      }

      // Main line
      graphics.moveTo(points[0], points[1]);
      for (let i = 2; i < points.length; i += 2) {
        graphics.lineTo(points[i], points[i + 1]);
      }
      graphics.stroke({ width: lineWidth, color: primaryColor });

      // Fill under line
      graphics.moveTo(0, height);
      graphics.lineTo(points[0], points[1]);
      for (let i = 2; i < points.length; i += 2) {
        graphics.lineTo(points[i], points[i + 1]);
      }
      graphics.lineTo(width, height);
      graphics.closePath();
      graphics.fill({ color: primaryColor, alpha: 0.15 });

      // Glow line
      if (glowIntensity > 0) {
        graphics.moveTo(points[0], points[1]);
        for (let i = 2; i < points.length; i += 2) {
          graphics.lineTo(points[i], points[i + 1]);
        }
        graphics.stroke({
          width: lineWidth * 3,
          color: primaryColor,
          alpha: glowIntensity * 0.3,
        });
      }
    },
    [width, height, primaryColor, lineWidth, glowIntensity]
  );

  // Draw mirror visualization
  const drawMirror = useCallback(
    (graphics: PIXI.Graphics, data: number[]) => {
      const barWidth = (width / barCount) * (1 - barGap);
      const gap = (width / barCount) * barGap;
      const totalBarWidth = barWidth + gap;
      const centerY = height / 2;

      for (let i = 0; i < barCount; i++) {
        const value = data[i] || 0;
        const barHeight = (value / 255) * centerY * 0.9;

        const x = i * totalBarWidth;
        const t = i / barCount;
        const color = lerpColor(primaryColor, secondaryColor, t);

        // Top half
        graphics.rect(x, centerY - barHeight, barWidth, barHeight);
        graphics.fill({ color, alpha: 0.8 });

        // Bottom half (mirrored)
        graphics.rect(x, centerY, barWidth, barHeight);
        graphics.fill({ color, alpha: 0.6 });
      }

      // Center line
      graphics.moveTo(0, centerY);
      graphics.lineTo(width, centerY);
      graphics.stroke({ width: 1, color: primaryColor, alpha: 0.5 });
    },
    [width, height, barCount, barGap, primaryColor, secondaryColor]
  );

  // Draw circular visualization
  const drawCircular = useCallback(
    (graphics: PIXI.Graphics, data: number[]) => {
      const centerX = width / 2;
      const centerY = height / 2;
      const baseRadius = Math.min(width, height) * 0.2;
      const maxRadius = Math.min(width, height) * 0.45;

      for (let i = 0; i < barCount; i++) {
        const value = data[i] || 0;
        const angle = (i / barCount) * Math.PI * 2 - Math.PI / 2;
        const barLength = baseRadius + (value / 255) * (maxRadius - baseRadius);

        const x1 = centerX + Math.cos(angle) * baseRadius;
        const y1 = centerY + Math.sin(angle) * baseRadius;
        const x2 = centerX + Math.cos(angle) * barLength;
        const y2 = centerY + Math.sin(angle) * barLength;

        const t = i / barCount;
        const color = lerpColor(primaryColor, secondaryColor, t);

        graphics.moveTo(x1, y1);
        graphics.lineTo(x2, y2);
        graphics.stroke({ width: 2, color, alpha: 0.8 });
      }

      // Inner circle
      graphics.circle(centerX, centerY, baseRadius * 0.8);
      graphics.stroke({ width: 2, color: primaryColor, alpha: 0.3 });
    },
    [width, height, barCount, primaryColor, secondaryColor]
  );

  // Animation loop
  useEffect(() => {
    if (!active) return;

    const animate = () => {
      const graphics = graphicsRef.current;
      if (!graphics) {
        rafRef.current = requestAnimationFrame(animate);
        return;
      }

      graphics.clear();

      // Process FFT data
      const rawData = Array.from(fftData);
      const processedData = processFFTData(rawData, barCount, mirror);

      // Apply smoothing
      for (let i = 0; i < barCount; i++) {
        const target = processedData[i] || 0;
        const current = smoothedDataRef.current[i] || 0;
        smoothedDataRef.current[i] = current + (target - current) * (1 - smoothing);
      }

      const data = smoothedDataRef.current;

      // Draw based on type
      switch (type) {
        case 'bars':
          drawBars(graphics, data);
          break;
        case 'line':
          drawLine(graphics, data);
          break;
        case 'mirror':
          drawMirror(graphics, data);
          break;
        case 'circular':
          drawCircular(graphics, data);
          break;
      }

      rafRef.current = requestAnimationFrame(animate);
    };

    rafRef.current = requestAnimationFrame(animate);

    return () => {
      if (rafRef.current) {
        cancelAnimationFrame(rafRef.current);
      }
    };
  }, [
    active,
    fftData,
    type,
    smoothing,
    mirror,
    barCount,
    drawBars,
    drawLine,
    drawMirror,
    drawCircular,
  ]);

  return (
    <div
      ref={containerRef}
      style={{
        width: `${width}px`,
        height: `${height}px`,
        overflow: 'hidden',
        borderRadius: '8px',
      }}
    />
  );
}

// ============ Utilities ============

/**
 * Linear interpolation between two colors.
 */
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

/**
 * Process raw FFT data into bar-sized buckets.
 */
function processFFTData(
  rawData: number[],
  barCount: number,
  mirror: boolean
): number[] {
  const result: number[] = [];
  const dataLength = rawData.length;

  // Use logarithmic scaling for frequency bins
  for (let i = 0; i < barCount; i++) {
    const t = i / barCount;
    // Logarithmic mapping - more bars for lower frequencies
    const logT = Math.pow(t, 0.7);
    const startIndex = Math.floor(logT * dataLength);
    const endIndex = Math.min(
      Math.floor((logT + 1 / barCount) * dataLength * 1.5),
      dataLength
    );

    // Average values in range
    let sum = 0;
    let count = 0;
    for (let j = startIndex; j < endIndex; j++) {
      sum += rawData[j] || 0;
      count++;
    }

    result.push(count > 0 ? sum / count : 0);
  }

  // Apply mirror if enabled
  if (mirror) {
    const half = Math.floor(barCount / 2);
    const mirrored: number[] = [];
    for (let i = 0; i < half; i++) {
      mirrored.push(result[i]);
    }
    for (let i = half - 1; i >= 0; i--) {
      mirrored.push(result[i]);
    }
    return mirrored;
  }

  return result;
}

// ============ Preset Configurations ============

export const spectrumPresets = {
  default: {
    type: 'bars' as const,
    primaryColor: 0x00d4ff,
    secondaryColor: 0xff00aa,
    barCount: 64,
    barGap: 0.2,
    smoothing: 0.7,
    glowIntensity: 0.3,
  },
  neon: {
    type: 'bars' as const,
    primaryColor: 0x00ff88,
    secondaryColor: 0xff0088,
    barCount: 48,
    barGap: 0.3,
    smoothing: 0.6,
    glowIntensity: 0.5,
  },
  minimal: {
    type: 'line' as const,
    primaryColor: 0x6366f1,
    secondaryColor: 0x8b5cf6,
    lineWidth: 2,
    smoothing: 0.8,
    glowIntensity: 0.2,
  },
  fire: {
    type: 'bars' as const,
    primaryColor: 0xff6b00,
    secondaryColor: 0xffcc00,
    barCount: 80,
    barGap: 0.15,
    smoothing: 0.5,
    glowIntensity: 0.4,
  },
  ice: {
    type: 'mirror' as const,
    primaryColor: 0x00ccff,
    secondaryColor: 0xffffff,
    barCount: 64,
    barGap: 0.2,
    smoothing: 0.75,
    glowIntensity: 0.3,
  },
  circular: {
    type: 'circular' as const,
    primaryColor: 0xff00ff,
    secondaryColor: 0x00ffff,
    barCount: 128,
    smoothing: 0.65,
  },
} as const;

export default PixiSpectrum;
