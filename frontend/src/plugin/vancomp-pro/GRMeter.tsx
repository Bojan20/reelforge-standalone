/**
 * ReelForge VanComp Pro - Gain Reduction Meter
 *
 * Central visualization showing GR trace, I/O meters, and threshold line.
 *
 * @module plugin/vancomp-pro/GRMeter
 */

import { useRef, useEffect, useCallback } from 'react';
import type { ProSuiteTheme } from '../pro-suite/theme';

interface GRMeterProps {
  threshold: number;
  ratio: number;
  knee: number;
  inputLevel: number;  // 0-1 normalized
  outputLevel: number; // 0-1 normalized
  grAmount: number;    // dB of gain reduction (negative)
  grHistory: number[]; // History of GR values for trace
  theme: ProSuiteTheme;
  width: number;
  height: number;
  /** Whether signal is idle (no signal detected) */
  isIdle?: boolean;
}

// dB scale constants
const MIN_DB = -60;
const MAX_DB = 6;
const DB_RANGE = MAX_DB - MIN_DB;

/**
 * Convert normalized level (0-1) to dB.
 */
function levelToDb(level: number): number {
  if (level <= 0) return MIN_DB;
  return Math.max(MIN_DB, Math.min(MAX_DB, 20 * Math.log10(level)));
}

/**
 * Convert dB to Y position.
 */
function dbToY(db: number, height: number): number {
  const normalized = (MAX_DB - db) / DB_RANGE;
  return normalized * height;
}

/**
 * Convert GR (negative dB) to width percentage.
 */
function grToWidth(gr: number): number {
  // gr is negative, so we negate it
  return Math.min(100, Math.max(0, -gr * 2)); // 50dB max displayed as 100%
}

export function GRMeter({
  threshold,
  ratio,
  knee,
  inputLevel,
  outputLevel,
  grAmount,
  grHistory,
  theme,
  width,
  height,
  isIdle = false,
}: GRMeterProps) {
  // When idle, show flat meters at -∞
  const effectiveInputLevel = isIdle ? 0 : inputLevel;
  const effectiveOutputLevel = isIdle ? 0 : outputLevel;
  const effectiveGrAmount = isIdle ? 0 : grAmount;
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animationRef = useRef<number>(0);

  // Draw the visualization
  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const w = width * dpr;
    const h = height * dpr;

    // Set canvas size
    canvas.width = w;
    canvas.height = h;
    ctx.scale(dpr, dpr);

    // Clear background
    ctx.fillStyle = theme.bgGraph;
    ctx.fillRect(0, 0, width, height);

    // Draw grid lines
    ctx.strokeStyle = theme.gridLine;
    ctx.lineWidth = 1;

    // Horizontal dB lines
    const dbSteps = [-48, -36, -24, -12, -6, 0];
    for (const db of dbSteps) {
      const y = dbToY(db, height);
      ctx.beginPath();
      ctx.moveTo(60, y);
      ctx.lineTo(width - 60, y);
      ctx.stroke();

      // Labels
      ctx.fillStyle = theme.textMuted;
      ctx.font = '9px -apple-system, sans-serif';
      ctx.textAlign = 'right';
      ctx.fillText(`${db}`, 55, y + 3);
    }

    // Draw threshold line
    const threshY = dbToY(threshold, height);
    ctx.strokeStyle = theme.accentPrimary;
    ctx.lineWidth = 2;
    ctx.setLineDash([6, 4]);
    ctx.beginPath();
    ctx.moveTo(60, threshY);
    ctx.lineTo(width - 60, threshY);
    ctx.stroke();
    ctx.setLineDash([]);

    // Draw threshold label
    ctx.fillStyle = theme.accentPrimary;
    ctx.font = 'bold 10px -apple-system, sans-serif';
    ctx.textAlign = 'left';
    ctx.fillText('THR', width - 55, threshY + 4);

    // Draw GR trace (skip if idle)
    if (!isIdle && grHistory.length > 1) {
      const traceWidth = width - 120;
      const stepX = traceWidth / (grHistory.length - 1);

      ctx.strokeStyle = theme.grColor;
      ctx.lineWidth = 2;
      ctx.beginPath();

      for (let i = 0; i < grHistory.length; i++) {
        const x = 60 + i * stepX;
        // GR is negative, map to height from threshold
        const grDb = Math.abs(grHistory[i]);
        const y = threshY + (grDb / 60) * (height - threshY);

        if (i === 0) {
          ctx.moveTo(x, Math.min(y, height - 5));
        } else {
          ctx.lineTo(x, Math.min(y, height - 5));
        }
      }
      ctx.stroke();

      // Fill under trace
      ctx.lineTo(60 + (grHistory.length - 1) * stepX, threshY);
      ctx.lineTo(60, threshY);
      ctx.closePath();
      ctx.fillStyle = `${theme.grColor}20`;
      ctx.fill();
    }

    // Draw current GR bar at bottom
    const grBarHeight = 20;
    const grBarY = height - grBarHeight - 10;
    const grWidth = grToWidth(effectiveGrAmount);

    // GR bar background
    ctx.fillStyle = theme.meterBg;
    ctx.fillRect(60, grBarY, width - 120, grBarHeight);

    // GR bar fill
    const grGradient = ctx.createLinearGradient(60, 0, 60 + (width - 120), 0);
    grGradient.addColorStop(0, theme.grColor);
    grGradient.addColorStop(1, theme.grColorBright);
    ctx.fillStyle = grGradient;
    ctx.fillRect(60, grBarY, (width - 120) * (grWidth / 100), grBarHeight);

    // GR value label
    ctx.fillStyle = theme.textPrimary;
    ctx.font = 'bold 11px SF Mono, Monaco, monospace';
    ctx.textAlign = 'center';
    ctx.fillText(`GR: ${isIdle ? '-∞' : effectiveGrAmount.toFixed(1)} dB`, width / 2, grBarY + 14);

    // Draw I/O meters on sides
    const meterWidth = 14;
    const meterMargin = 20;
    const meterHeight = height - 60;

    // Input meter (left)
    drawMeter(ctx, meterMargin, 20, meterWidth, meterHeight, effectiveInputLevel, theme, 'IN');

    // Output meter (right)
    drawMeter(ctx, width - meterMargin - meterWidth, 20, meterWidth, meterHeight, effectiveOutputLevel, theme, 'OUT');

  }, [width, height, threshold, ratio, knee, effectiveInputLevel, effectiveOutputLevel, effectiveGrAmount, grHistory, theme, isIdle]);

  // Animation loop
  useEffect(() => {
    const animate = () => {
      draw();
      animationRef.current = requestAnimationFrame(animate);
    };
    animate();

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [draw]);

  return (
    <canvas
      ref={canvasRef}
      style={{
        width: `${width}px`,
        height: `${height}px`,
      }}
    />
  );
}

/**
 * Draw a vertical meter.
 */
function drawMeter(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  width: number,
  height: number,
  level: number,
  theme: ProSuiteTheme,
  label: string
) {
  // Background
  ctx.fillStyle = theme.meterBg;
  ctx.fillRect(x, y, width, height);

  // Level fill
  const levelDb = levelToDb(level);
  const fillHeight = Math.max(0, ((levelDb - MIN_DB) / DB_RANGE) * height);

  // Gradient based on level
  const gradient = ctx.createLinearGradient(0, y + height, 0, y);
  gradient.addColorStop(0, theme.meterGreen);
  gradient.addColorStop(0.6, theme.meterGreen);
  gradient.addColorStop(0.8, theme.meterYellow);
  gradient.addColorStop(1, theme.meterRed);

  ctx.fillStyle = gradient;
  ctx.fillRect(x, y + height - fillHeight, width, fillHeight);

  // Border
  ctx.strokeStyle = theme.gridLine;
  ctx.lineWidth = 1;
  ctx.strokeRect(x, y, width, height);

  // Label
  ctx.fillStyle = theme.textMuted;
  ctx.font = '8px -apple-system, sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText(label, x + width / 2, y + height + 12);
}
