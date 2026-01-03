/**
 * ReelForge VanLimit Pro - Waveform Meter
 *
 * Central visualization showing waveform history, GR trace, and output meters.
 *
 * @module plugin/vanlimit-pro/WaveformMeter
 */

import { useRef, useEffect, useCallback } from 'react';
import type { ProSuiteTheme } from '../pro-suite/theme';

interface WaveformMeterProps {
  ceiling: number;
  threshold: number;
  inputHistory: number[];    // History of input peak levels (0-1)
  outputHistory: number[];   // History of output peak levels (0-1)
  grHistory: number[];       // History of GR values (negative dB)
  currentGR: number;         // Current GR amount
  outputLevel: number;       // Current output level (0-1)
  truePeak: boolean;
  theme: ProSuiteTheme;
  width: number;
  height: number;
  /** Whether signal is idle (no signal detected) */
  isIdle?: boolean;
}

// dB scale constants
const MIN_DB = -48;
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

export function WaveformMeter({
  ceiling,
  threshold,
  inputHistory,
  outputHistory,
  grHistory,
  currentGR,
  outputLevel,
  truePeak,
  theme,
  width,
  height,
  isIdle = false,
}: WaveformMeterProps) {
  // When idle, use zero levels
  const effectiveOutputLevel = isIdle ? 0 : outputLevel;
  const effectiveGR = isIdle ? 0 : currentGR;
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

    // Layout
    const meterWidth = 40;
    const grMeterWidth = 30;
    const waveformLeft = meterWidth + 20;
    const waveformRight = width - grMeterWidth - 20;
    const waveformWidth = waveformRight - waveformLeft;
    const waveformHeight = height - 40;

    // Clear background
    ctx.fillStyle = theme.bgGraph;
    ctx.fillRect(0, 0, width, height);

    // Draw waveform area background
    ctx.fillStyle = theme.meterBg;
    ctx.fillRect(waveformLeft, 20, waveformWidth, waveformHeight);

    // Draw grid lines
    ctx.strokeStyle = theme.gridLine;
    ctx.lineWidth = 1;

    const dbSteps = [-36, -24, -12, -6, -3, 0, 3];
    for (const db of dbSteps) {
      const y = 20 + dbToY(db, waveformHeight);
      ctx.beginPath();
      ctx.moveTo(waveformLeft, y);
      ctx.lineTo(waveformRight, y);
      ctx.stroke();
    }

    // Draw ceiling line
    const ceilingY = 20 + dbToY(ceiling, waveformHeight);
    ctx.strokeStyle = theme.meterRed;
    ctx.lineWidth = 2;
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    ctx.moveTo(waveformLeft, ceilingY);
    ctx.lineTo(waveformRight, ceilingY);
    ctx.stroke();
    ctx.setLineDash([]);

    // Draw threshold line
    const threshY = 20 + dbToY(threshold, waveformHeight);
    ctx.strokeStyle = theme.accentPrimary;
    ctx.lineWidth = 2;
    ctx.setLineDash([6, 4]);
    ctx.beginPath();
    ctx.moveTo(waveformLeft, threshY);
    ctx.lineTo(waveformRight, threshY);
    ctx.stroke();
    ctx.setLineDash([]);

    // Draw input waveform (filled) - skip when idle
    if (!isIdle && inputHistory.length > 1) {
      const stepX = waveformWidth / (inputHistory.length - 1);

      ctx.fillStyle = `${theme.waveformColor}30`;
      ctx.beginPath();
      ctx.moveTo(waveformLeft, 20 + waveformHeight);

      for (let i = 0; i < inputHistory.length; i++) {
        const x = waveformLeft + i * stepX;
        const db = levelToDb(inputHistory[i]);
        const y = 20 + dbToY(db, waveformHeight);
        ctx.lineTo(x, y);
      }

      ctx.lineTo(waveformRight, 20 + waveformHeight);
      ctx.closePath();
      ctx.fill();
    }

    // Draw output waveform (line) - skip when idle
    if (!isIdle && outputHistory.length > 1) {
      const stepX = waveformWidth / (outputHistory.length - 1);

      ctx.strokeStyle = theme.statusActive;
      ctx.lineWidth = 2;
      ctx.beginPath();

      for (let i = 0; i < outputHistory.length; i++) {
        const x = waveformLeft + i * stepX;
        const db = levelToDb(outputHistory[i]);
        const y = 20 + dbToY(db, waveformHeight);

        if (i === 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
      }
      ctx.stroke();
    }

    // Draw GR trace (inverted, from top) - skip when idle
    if (!isIdle && grHistory.length > 1) {
      const stepX = waveformWidth / (grHistory.length - 1);

      ctx.strokeStyle = theme.grColor;
      ctx.lineWidth = 1.5;
      ctx.beginPath();

      for (let i = 0; i < grHistory.length; i++) {
        const x = waveformLeft + i * stepX;
        // GR is negative, map to top portion
        const grDb = Math.abs(grHistory[i]);
        const y = 20 + (grDb / 24) * (waveformHeight * 0.4);

        if (i === 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
      }
      ctx.stroke();

      // Fill under GR
      ctx.lineTo(waveformRight, 20);
      ctx.lineTo(waveformLeft, 20);
      ctx.closePath();
      ctx.fillStyle = `${theme.grColor}15`;
      ctx.fill();
    }

    // Draw output meter (left side)
    drawOutputMeter(ctx, 10, 20, meterWidth - 10, waveformHeight, effectiveOutputLevel, ceiling, theme, truePeak);

    // Draw GR meter (right side)
    drawGRMeter(ctx, waveformRight + 10, 20, grMeterWidth - 10, waveformHeight, effectiveGR, theme);

    // Labels
    ctx.fillStyle = theme.textMuted;
    ctx.font = '9px -apple-system, sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('OUT', 10 + (meterWidth - 10) / 2, height - 5);
    ctx.fillText('GR', waveformRight + 10 + (grMeterWidth - 10) / 2, height - 5);

    // Current GR value
    ctx.fillStyle = theme.grColor;
    ctx.font = 'bold 12px SF Mono, Monaco, monospace';
    ctx.textAlign = 'center';
    ctx.fillText(isIdle ? '-∞ dB' : `${effectiveGR.toFixed(1)} dB`, width / 2, height - 5);

  }, [width, height, ceiling, threshold, inputHistory, outputHistory, grHistory, effectiveGR, effectiveOutputLevel, truePeak, theme, isIdle]);

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
 * Draw output meter with peak hold.
 */
function drawOutputMeter(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  width: number,
  height: number,
  level: number,
  ceiling: number,
  theme: ProSuiteTheme,
  truePeak: boolean
) {
  // Background
  ctx.fillStyle = theme.meterBg;
  ctx.fillRect(x, y, width, height);

  // Level fill
  const levelDb = levelToDb(level);
  const fillHeight = Math.max(0, ((levelDb - MIN_DB) / DB_RANGE) * height);

  // Gradient
  const gradient = ctx.createLinearGradient(0, y + height, 0, y);
  gradient.addColorStop(0, theme.meterGreen);
  gradient.addColorStop(0.5, theme.meterGreen);
  gradient.addColorStop(0.75, theme.meterYellow);
  gradient.addColorStop(0.9, theme.meterRed);
  gradient.addColorStop(1, theme.meterRed);

  ctx.fillStyle = gradient;
  ctx.fillRect(x, y + height - fillHeight, width, fillHeight);

  // Ceiling marker
  const ceilingY = y + dbToY(ceiling, height);
  ctx.strokeStyle = theme.meterRed;
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(x, ceilingY);
  ctx.lineTo(x + width, ceilingY);
  ctx.stroke();

  // Border
  ctx.strokeStyle = theme.gridLine;
  ctx.lineWidth = 1;
  ctx.strokeRect(x, y, width, height);

  // True peak indicator
  if (truePeak) {
    ctx.fillStyle = theme.textMuted;
    ctx.font = '7px -apple-system, sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('TP', x + width / 2, y - 4);
  }
}

/**
 * Draw GR meter.
 */
function drawGRMeter(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  width: number,
  height: number,
  gr: number,
  theme: ProSuiteTheme
) {
  // Background
  ctx.fillStyle = theme.meterBg;
  ctx.fillRect(x, y, width, height);

  // GR fill (from top)
  const grAbs = Math.abs(gr);
  const maxGR = 24; // Max displayed GR
  const fillHeight = Math.min(height, (grAbs / maxGR) * height);

  ctx.fillStyle = theme.grColor;
  ctx.fillRect(x, y, width, fillHeight);

  // Border
  ctx.strokeStyle = theme.gridLine;
  ctx.lineWidth = 1;
  ctx.strokeRect(x, y, width, height);
}
