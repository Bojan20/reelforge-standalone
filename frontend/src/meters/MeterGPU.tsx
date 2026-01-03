/**
 * ReelForge GPU Meter Renderer
 *
 * Professional-grade meter with multiple standard skins:
 * - VU, PPM (EBU/DIN/BBC/Nordic), K-System, LUFS, True Peak
 * - GPU-accelerated via PixiJS
 * - Configurable attack/release ballistics
 * - Peak hold with decay
 * - Stereo or mono display
 *
 * @module meters/MeterGPU
 */

import { useRef, useEffect, useCallback, useState, useMemo } from 'react';
import * as PIXI from 'pixi.js';
import {
  type MeterStandard,
  getMeterConfig,
  dbToNormalized,
  getZoneColor,
} from './MeterTypes';

// ============ Types ============

export interface MeterGPUProps {
  /** Meter standard/skin */
  standard: MeterStandard;
  /** Current peak level (dB) - left channel */
  peakL: number;
  /** Current peak level (dB) - right channel */
  peakR?: number;
  /** Current RMS level (dB) - left channel */
  rmsL?: number;
  /** Current RMS level (dB) - right channel */
  rmsR?: number;
  /** Width in pixels */
  width?: number;
  /** Height in pixels */
  height?: number;
  /** Orientation */
  orientation?: 'vertical' | 'horizontal';
  /** Show scale labels */
  showScale?: boolean;
  /** Show peak hold indicator */
  showPeakHold?: boolean;
  /** Show RMS bar (if applicable) */
  showRMS?: boolean;
  /** Stereo mode (two bars) or mono (single bar) */
  stereo?: boolean;
  /** Background color */
  backgroundColor?: number;
  /** Segment style (continuous or LED-style) */
  segmentStyle?: 'continuous' | 'led';
  /** LED segment count (if segmentStyle is 'led') */
  ledCount?: number;
  /** Gap between LED segments */
  ledGap?: number;
  /** Custom class */
  className?: string;
}

// ============ Constants ============

const DEFAULT_WIDTH = 24;
const DEFAULT_HEIGHT = 200;
const SCALE_WIDTH = 30;
const BAR_GAP = 2;

// ============ Component ============

export function MeterGPU({
  standard,
  peakL,
  peakR,
  rmsL,
  rmsR,
  width = DEFAULT_WIDTH,
  height = DEFAULT_HEIGHT,
  orientation = 'vertical',
  showScale = true,
  showPeakHold = true,
  showRMS = true,
  stereo = true,
  backgroundColor = 0x1a1a1a,
  segmentStyle = 'continuous',
  ledCount = 24,
  ledGap = 1,
  className,
}: MeterGPUProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const appRef = useRef<PIXI.Application | null>(null);
  const barGraphicsRef = useRef<PIXI.Graphics | null>(null);
  const holdGraphicsRef = useRef<PIXI.Graphics | null>(null);
  const rmsGraphicsRef = useRef<PIXI.Graphics | null>(null);

  // Meter configuration
  const config = useMemo(() => getMeterConfig(standard), [standard]);

  // Peak hold state with decay
  const [peakHoldL, setPeakHoldL] = useState(-Infinity);
  const [peakHoldR, setPeakHoldR] = useState(-Infinity);
  const holdTimerRef = useRef<{ l: number; r: number }>({ l: 0, r: 0 });

  // Calculate dimensions
  const isVertical = orientation === 'vertical';
  const scaleSize = showScale ? SCALE_WIDTH : 0;
  const totalWidth = isVertical
    ? (stereo ? width * 2 + BAR_GAP : width) + scaleSize
    : height + scaleSize;
  const totalHeight = isVertical
    ? height
    : (stereo ? width * 2 + BAR_GAP : width);
  const barWidth = stereo ? (width - BAR_GAP) / 2 : width;

  // Initialize PixiJS
  useEffect(() => {
    if (!containerRef.current || appRef.current) return;

    const app = new PIXI.Application();

    (async () => {
      await app.init({
        width: totalWidth,
        height: totalHeight,
        backgroundColor,
        antialias: true,
        resolution: window.devicePixelRatio || 1,
        autoDensity: true,
      });

      if (containerRef.current) {
        containerRef.current.appendChild(app.canvas as HTMLCanvasElement);
      }

      const barGraphics = new PIXI.Graphics();
      const holdGraphics = new PIXI.Graphics();
      const rmsGraphics = new PIXI.Graphics();

      app.stage.addChild(barGraphics);
      app.stage.addChild(rmsGraphics);
      app.stage.addChild(holdGraphics);

      appRef.current = app;
      barGraphicsRef.current = barGraphics;
      holdGraphicsRef.current = holdGraphics;
      rmsGraphicsRef.current = rmsGraphics;
    })();

    return () => {
      if (appRef.current) {
        appRef.current.destroy(true, { children: true });
        appRef.current = null;
      }
    };
  }, []);

  // Resize
  useEffect(() => {
    if (appRef.current) {
      appRef.current.renderer.resize(totalWidth, totalHeight);
    }
  }, [totalWidth, totalHeight]);

  // Update peak hold
  useEffect(() => {
    if (!showPeakHold || config.peakHoldMs === 0) return;

    const now = Date.now();

    // Left channel
    if (peakL > peakHoldL) {
      setPeakHoldL(peakL);
      holdTimerRef.current.l = now + config.peakHoldMs;
    } else if (now > holdTimerRef.current.l) {
      // Decay
      const decay = 20 / config.releaseMs * 16.67; // ~20dB/s at 60fps
      setPeakHoldL((prev) => Math.max(config.scaleMin, prev - decay));
    }

    // Right channel
    const peakRValue = peakR ?? peakL;
    if (peakRValue > peakHoldR) {
      setPeakHoldR(peakRValue);
      holdTimerRef.current.r = now + config.peakHoldMs;
    } else if (now > holdTimerRef.current.r) {
      const decay = 20 / config.releaseMs * 16.67;
      setPeakHoldR((prev) => Math.max(config.scaleMin, prev - decay));
    }
  }, [peakL, peakR, peakHoldL, peakHoldR, config, showPeakHold]);

  // Draw meter bars
  const drawMeter = useCallback(() => {
    const barGraphics = barGraphicsRef.current;
    const holdGraphics = holdGraphicsRef.current;
    const rmsGraphics = rmsGraphicsRef.current;

    if (!barGraphics || !holdGraphics || !rmsGraphics) return;

    barGraphics.clear();
    holdGraphics.clear();
    rmsGraphics.clear();

    const barX = scaleSize;
    const peakRValue = peakR ?? peakL;
    const rmsLValue = rmsL ?? peakL - 12; // Estimate if not provided
    const rmsRValue = rmsR ?? peakRValue - 12;

    if (segmentStyle === 'led') {
      // LED-style segments
      const segmentHeight = (height - (ledCount - 1) * ledGap) / ledCount;

      for (let i = 0; i < ledCount; i++) {
        const segmentDb = config.scaleMin + (i / ledCount) * (config.scaleMax - config.scaleMin);
        const segmentTop = config.scaleMin + ((i + 1) / ledCount) * (config.scaleMax - config.scaleMin);
        const y = height - (i + 1) * (segmentHeight + ledGap) + ledGap;
        const color = getZoneColor((segmentDb + segmentTop) / 2, config);

        // Left bar
        if (peakL >= segmentDb) {
          barGraphics.beginFill(color, peakL >= segmentTop ? 1 : 0.7);
          barGraphics.rect(barX, y, barWidth, segmentHeight);
          barGraphics.endFill();
        } else {
          // Dim segment
          barGraphics.beginFill(color, 0.15);
          barGraphics.rect(barX, y, barWidth, segmentHeight);
          barGraphics.endFill();
        }

        // Right bar (if stereo)
        if (stereo) {
          const rightX = barX + barWidth + BAR_GAP;
          if (peakRValue >= segmentDb) {
            barGraphics.beginFill(color, peakRValue >= segmentTop ? 1 : 0.7);
            barGraphics.rect(rightX, y, barWidth, segmentHeight);
            barGraphics.endFill();
          } else {
            barGraphics.beginFill(color, 0.15);
            barGraphics.rect(rightX, y, barWidth, segmentHeight);
            barGraphics.endFill();
          }
        }
      }
    } else {
      // Continuous style with gradient
      const drawBar = (x: number, db: number, w: number) => {
        const normalizedLevel = dbToNormalized(db, config);
        const barHeight = normalizedLevel * height;

        // Draw colored zones
        for (const zone of config.zones) {
          const zoneStart = dbToNormalized(zone.start, config);
          const zoneEnd = dbToNormalized(zone.end, config);
          const zoneBottom = zoneStart * height;
          const zoneTop = zoneEnd * height;

          if (barHeight > zoneBottom) {
            const drawHeight = Math.min(barHeight, zoneTop) - zoneBottom;
            if (drawHeight > 0) {
              barGraphics.beginFill(zone.color, 0.9);
              barGraphics.rect(x, height - zoneBottom - drawHeight, w, drawHeight);
              barGraphics.endFill();
            }
          }
        }

        // Bar outline
        barGraphics.setStrokeStyle({ width: 1, color: 0x333333 });
        barGraphics.rect(x, 0, w, height);
        barGraphics.stroke();
      };

      drawBar(barX, peakL, barWidth);
      if (stereo) {
        drawBar(barX + barWidth + BAR_GAP, peakRValue, barWidth);
      }
    }

    // RMS indicators (darker overlay)
    if (showRMS && config.showRMS) {
      const drawRMS = (x: number, db: number, w: number) => {
        const normalizedLevel = dbToNormalized(db, config);
        const barHeight = normalizedLevel * height;

        rmsGraphics.beginFill(0xffffff, 0.25);
        rmsGraphics.rect(x + w * 0.2, height - barHeight, w * 0.6, 3);
        rmsGraphics.endFill();
      };

      drawRMS(barX, rmsLValue, barWidth);
      if (stereo) {
        drawRMS(barX + barWidth + BAR_GAP, rmsRValue, barWidth);
      }
    }

    // Peak hold indicators
    if (showPeakHold && config.peakHoldMs > 0) {
      const drawHold = (x: number, db: number, w: number) => {
        if (db <= config.scaleMin) return;
        const y = height - dbToNormalized(db, config) * height;
        const color = getZoneColor(db, config);

        holdGraphics.beginFill(color);
        holdGraphics.rect(x, y - 2, w, 3);
        holdGraphics.endFill();
      };

      drawHold(barX, peakHoldL, barWidth);
      if (stereo) {
        drawHold(barX + barWidth + BAR_GAP, peakHoldR, barWidth);
      }
    }

    // Draw scale (if visible)
    if (showScale && scaleSize > 0) {
      // Scale tick marks only (text rendering would need proper container management)
      for (const tick of config.majorTicks) {
        const y = height - dbToNormalized(tick, config) * height;
        barGraphics.setStrokeStyle({ width: 1, color: 0x444444 });
        barGraphics.moveTo(scaleSize - 4, y);
        barGraphics.lineTo(scaleSize, y);
        barGraphics.stroke();
      }
    }
  }, [
    peakL, peakR, rmsL, rmsR, peakHoldL, peakHoldR,
    config, height, barWidth, stereo, segmentStyle, ledCount, ledGap,
    showScale, scaleSize, showRMS, showPeakHold
  ]);

  // Animation loop
  useEffect(() => {
    let animationId: number;

    const animate = () => {
      drawMeter();
      animationId = requestAnimationFrame(animate);
    };

    animate();

    return () => {
      cancelAnimationFrame(animationId);
    };
  }, [drawMeter]);

  return (
    <div
      ref={containerRef}
      className={`meter-gpu meter-${standard} ${className ?? ''}`}
      style={{
        width: totalWidth,
        height: totalHeight,
        position: 'relative',
      }}
    />
  );
}

export default MeterGPU;
