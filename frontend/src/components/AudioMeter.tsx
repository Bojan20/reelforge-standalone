/**
 * ReelForge Audio Meter Component
 *
 * Professional audio level meter with:
 * - Peak and RMS display
 * - Peak hold with decay
 * - Stereo L/R metering
 * - Configurable scale (dB)
 * - Clip indicator
 *
 * Optimized for 60fps with PixiJS.
 *
 * @module components/AudioMeter
 */

import { useRef, useEffect, useCallback } from 'react';
import * as PIXI from 'pixi.js';
import type { AudioLevels } from '../hooks/useAudioAnalyzer';

// ============ Types ============

export type MeterOrientation = 'vertical' | 'horizontal';
export type MeterMode = 'peak' | 'rms' | 'both';

export interface AudioMeterProps {
  /** Audio levels from useAudioAnalyzer */
  levels: AudioLevels | null;
  /** Width in pixels */
  width: number;
  /** Height in pixels */
  height: number;
  /** Meter orientation */
  orientation?: MeterOrientation;
  /** Display mode */
  mode?: MeterMode;
  /** Show stereo channels */
  stereo?: boolean;
  /** Minimum dB value */
  minDb?: number;
  /** Maximum dB value */
  maxDb?: number;
  /** Peak hold time in ms */
  peakHoldTime?: number;
  /** Peak decay rate (dB/frame) */
  peakDecayRate?: number;
  /** Show scale markings */
  showScale?: boolean;
  /** Background color */
  backgroundColor?: number;
  /** Meter gradient colors [green, yellow, red] */
  gradientColors?: [number, number, number];
  /** Peak indicator color */
  peakColor?: number;
  /** RMS bar color */
  rmsColor?: number;
  /** Clip indicator color */
  clipColor?: number;
  /** Whether meter is active */
  active?: boolean;
}

// ============ Constants ============

const DEFAULT_BG = 0x1a1a1a;
const DEFAULT_GRADIENT: [number, number, number] = [0x00ff00, 0xffff00, 0xff0000];
const DEFAULT_PEAK_COLOR = 0xffffff;
const DEFAULT_RMS_COLOR = 0x00aaff;
const DEFAULT_CLIP_COLOR = 0xff0000;

const SCALE_MARKS = [-60, -48, -36, -24, -18, -12, -6, -3, 0, 3, 6];

// ============ Component ============

export function AudioMeter({
  levels,
  width,
  height,
  orientation = 'vertical',
  mode = 'both',
  stereo = false,
  minDb = -60,
  maxDb = 6,
  peakHoldTime = 1500,
  peakDecayRate = 0.5,
  showScale = true,
  backgroundColor = DEFAULT_BG,
  gradientColors = DEFAULT_GRADIENT,
  peakColor = DEFAULT_PEAK_COLOR,
  rmsColor = DEFAULT_RMS_COLOR,
  clipColor = DEFAULT_CLIP_COLOR,
  active = true,
}: AudioMeterProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const appRef = useRef<PIXI.Application | null>(null);
  const graphicsRef = useRef<PIXI.Graphics | null>(null);
  const rafRef = useRef<number>(0);

  // Peak hold state
  const peakHoldLRef = useRef<number>(minDb);
  const peakHoldRRef = useRef<number>(minDb);
  const peakHoldTimeRef = useRef<number>(0);
  const peakHoldTimeRRef = useRef<number>(0);
  const clipLRef = useRef<boolean>(false);
  const clipRRef = useRef<boolean>(false);
  const clipTimeRef = useRef<number>(0);

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

  // Update size
  useEffect(() => {
    if (appRef.current) {
      appRef.current.renderer.resize(width, height);
    }
  }, [width, height]);

  // Convert dB to position
  const dbToPosition = useCallback(
    (db: number): number => {
      const clamped = Math.max(minDb, Math.min(maxDb, db));
      return (clamped - minDb) / (maxDb - minDb);
    },
    [minDb, maxDb]
  );

  // Get gradient color at position
  const getGradientColor = useCallback(
    (position: number): number => {
      const [green, yellow, red] = gradientColors;

      if (position < 0.6) {
        // Green zone
        return green;
      } else if (position < 0.85) {
        // Yellow zone
        const t = (position - 0.6) / 0.25;
        return lerpColor(green, yellow, t);
      } else {
        // Red zone
        const t = (position - 0.85) / 0.15;
        return lerpColor(yellow, red, t);
      }
    },
    [gradientColors]
  );

  // Draw meter bar
  const drawMeterBar = useCallback(
    (
      graphics: PIXI.Graphics,
      x: number,
      y: number,
      barWidth: number,
      barHeight: number,
      peakDb: number,
      rmsDb: number,
      peakHoldDb: number,
      isClipping: boolean,
      isVertical: boolean
    ) => {
      const peakPos = dbToPosition(peakDb);
      const rmsPos = dbToPosition(rmsDb);
      const holdPos = dbToPosition(peakHoldDb);

      // Background
      graphics.rect(x, y, barWidth, barHeight);
      graphics.fill({ color: 0x2a2a2a });

      if (isVertical) {
        // Vertical meter (bottom to top)
        const segments = 30;
        const segmentHeight = barHeight / segments;
        const segmentGap = 1;

        for (let i = 0; i < segments; i++) {
          const segPos = i / segments;
          const segY = y + barHeight - (i + 1) * segmentHeight;

          // Determine if segment is lit
          const isPeakLit = mode !== 'rms' && segPos <= peakPos;
          const isRmsLit = mode !== 'peak' && segPos <= rmsPos;

          if (isPeakLit || isRmsLit) {
            const color = isRmsLit ? rmsColor : getGradientColor(segPos);
            const alpha = isRmsLit ? 0.7 : 1;

            graphics.rect(
              x + 1,
              segY + segmentGap,
              barWidth - 2,
              segmentHeight - segmentGap * 2
            );
            graphics.fill({ color, alpha });
          }
        }

        // Peak hold indicator
        if (mode !== 'rms') {
          const holdY = y + barHeight - holdPos * barHeight;
          graphics.rect(x + 1, holdY - 2, barWidth - 2, 3);
          graphics.fill({ color: peakColor });
        }

        // Clip indicator
        if (isClipping) {
          graphics.rect(x, y, barWidth, 4);
          graphics.fill({ color: clipColor });
        }
      } else {
        // Horizontal meter (left to right)
        const segments = 30;
        const segmentWidth = barWidth / segments;
        const segmentGap = 1;

        for (let i = 0; i < segments; i++) {
          const segPos = i / segments;
          const segX = x + i * segmentWidth;

          const isPeakLit = mode !== 'rms' && segPos <= peakPos;
          const isRmsLit = mode !== 'peak' && segPos <= rmsPos;

          if (isPeakLit || isRmsLit) {
            const color = isRmsLit ? rmsColor : getGradientColor(segPos);
            const alpha = isRmsLit ? 0.7 : 1;

            graphics.rect(
              segX + segmentGap,
              y + 1,
              segmentWidth - segmentGap * 2,
              barHeight - 2
            );
            graphics.fill({ color, alpha });
          }
        }

        // Peak hold indicator
        if (mode !== 'rms') {
          const holdX = x + holdPos * barWidth;
          graphics.rect(holdX - 1, y + 1, 3, barHeight - 2);
          graphics.fill({ color: peakColor });
        }

        // Clip indicator
        if (isClipping) {
          graphics.rect(x + barWidth - 4, y, 4, barHeight);
          graphics.fill({ color: clipColor });
        }
      }
    },
    [dbToPosition, getGradientColor, mode, peakColor, rmsColor, clipColor]
  );

  // Draw scale
  const drawScale = useCallback(
    (graphics: PIXI.Graphics, isVertical: boolean, meterWidth: number) => {
      const scaleWidth = 25;

      for (const db of SCALE_MARKS) {
        if (db < minDb || db > maxDb) continue;

        const pos = dbToPosition(db);
        // Label color for future text rendering
void (db >= 0 ? 0xff6666 : 0x888888);

        if (isVertical) {
          const y = height - pos * height;
          // Tick mark
          graphics.moveTo(meterWidth, y);
          graphics.lineTo(meterWidth + 4, y);
          graphics.stroke({ width: 1, color: 0x666666 });
        } else {
          const x = pos * (width - scaleWidth);
          // Tick mark
          graphics.moveTo(x, height - 15);
          graphics.lineTo(x, height - 11);
          graphics.stroke({ width: 1, color: 0x666666 });
        }
      }
    },
    [width, height, minDb, maxDb, dbToPosition]
  );

  // Animation loop
  useEffect(() => {
    if (!active) return;

    const animate = (timestamp: number) => {
      const graphics = graphicsRef.current;
      if (!graphics) {
        rafRef.current = requestAnimationFrame(animate);
        return;
      }

      graphics.clear();

      const isVertical = orientation === 'vertical';
      const scaleWidth = showScale ? 25 : 0;

      // Calculate meter dimensions
      let meterWidth: number;
      let meterHeight: number;
      let meterX: number;
      let meterY: number;

      if (stereo) {
        if (isVertical) {
          meterWidth = (width - scaleWidth - 4) / 2;
          meterHeight = height - 10;
          meterX = 2;
          meterY = 5;
        } else {
          meterWidth = width - scaleWidth - 10;
          meterHeight = (height - 4) / 2;
          meterX = 5;
          meterY = 2;
        }
      } else {
        if (isVertical) {
          meterWidth = width - scaleWidth - 4;
          meterHeight = height - 10;
          meterX = 2;
          meterY = 5;
        } else {
          meterWidth = width - scaleWidth - 10;
          meterHeight = height - 4;
          meterX = 5;
          meterY = 2;
        }
      }

      // Get current levels
      const peakDbL = levels?.peakDb ?? minDb;
      const rmsDbL = levels?.rmsDb ?? minDb;
      const peakL = levels?.peakL ?? levels?.peak ?? 0;
      const peakR = levels?.peakR ?? levels?.peak ?? 0;
      const peakDbR = peakR > 0 ? 20 * Math.log10(peakR) : minDb;
      const rmsDbR = rmsDbL; // Use same RMS for both if not stereo

      // Update peak hold (Left)
      if (peakDbL > peakHoldLRef.current) {
        peakHoldLRef.current = peakDbL;
        peakHoldTimeRef.current = timestamp;
      } else if (timestamp - peakHoldTimeRef.current > peakHoldTime) {
        peakHoldLRef.current = Math.max(
          minDb,
          peakHoldLRef.current - peakDecayRate
        );
      }

      // Update peak hold (Right)
      if (peakDbR > peakHoldRRef.current) {
        peakHoldRRef.current = peakDbR;
        peakHoldTimeRRef.current = timestamp;
      } else if (timestamp - peakHoldTimeRRef.current > peakHoldTime) {
        peakHoldRRef.current = Math.max(
          minDb,
          peakHoldRRef.current - peakDecayRate
        );
      }

      // Check clipping
      if (peakL >= 1.0) {
        clipLRef.current = true;
        clipTimeRef.current = timestamp;
      } else if (timestamp - clipTimeRef.current > 2000) {
        clipLRef.current = false;
      }

      if (peakR >= 1.0) {
        clipRRef.current = true;
      }

      // Draw scale
      if (showScale) {
        drawScale(graphics, isVertical, stereo ? meterWidth * 2 + 4 : meterWidth);
      }

      // Draw meter(s)
      if (stereo) {
        // Left channel
        drawMeterBar(
          graphics,
          meterX,
          meterY,
          meterWidth,
          meterHeight,
          peakDbL,
          rmsDbL,
          peakHoldLRef.current,
          clipLRef.current,
          isVertical
        );

        // Right channel
        const secondX = isVertical ? meterX + meterWidth + 2 : meterX;
        const secondY = isVertical ? meterY : meterY + meterHeight + 2;

        drawMeterBar(
          graphics,
          secondX,
          secondY,
          meterWidth,
          isVertical ? meterHeight : meterHeight,
          peakDbR,
          rmsDbR,
          peakHoldRRef.current,
          clipRRef.current,
          isVertical
        );

        // Channel labels
        // Note: Text rendering would require PIXI.Text, simplified here
      } else {
        drawMeterBar(
          graphics,
          meterX,
          meterY,
          meterWidth,
          meterHeight,
          peakDbL,
          rmsDbL,
          peakHoldLRef.current,
          clipLRef.current,
          isVertical
        );
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
    levels,
    orientation,
    stereo,
    width,
    height,
    showScale,
    minDb,
    maxDb,
    peakHoldTime,
    peakDecayRate,
    drawMeterBar,
    drawScale,
  ]);

  return (
    <div
      ref={containerRef}
      style={{
        width: `${width}px`,
        height: `${height}px`,
        overflow: 'hidden',
        borderRadius: '4px',
      }}
    />
  );
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

export const meterPresets = {
  standard: {
    minDb: -60,
    maxDb: 6,
    mode: 'both' as const,
    gradientColors: [0x00ff00, 0xffff00, 0xff0000] as [number, number, number],
  },
  broadcast: {
    minDb: -60,
    maxDb: 0,
    mode: 'peak' as const,
    gradientColors: [0x00cc66, 0xffcc00, 0xff3333] as [number, number, number],
  },
  vintage: {
    minDb: -40,
    maxDb: 3,
    mode: 'rms' as const,
    gradientColors: [0x66ff66, 0xffff66, 0xff6666] as [number, number, number],
  },
  minimal: {
    minDb: -48,
    maxDb: 0,
    mode: 'peak' as const,
    showScale: false,
    gradientColors: [0x00aaff, 0x00aaff, 0xff00aa] as [number, number, number],
  },
} as const;

export default AudioMeter;
