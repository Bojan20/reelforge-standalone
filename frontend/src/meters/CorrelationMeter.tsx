/**
 * ReelForge Correlation Meter
 *
 * Stereo correlation/phase meter:
 * - Shows phase relationship between L/R
 * - -1 (out of phase) to +1 (mono/in phase)
 * - Peak hold
 *
 * @module meters/CorrelationMeter
 */

import { useRef, useEffect } from 'react';
import './CorrelationMeter.css';

// ============ Types ============

export interface CorrelationMeterProps {
  /** Correlation value (-1 to +1) */
  correlation: number;
  /** Peak correlation (for hold) */
  peakCorrelation?: number;
  /** Orientation */
  orientation?: 'horizontal' | 'vertical';
  /** Width */
  width?: number;
  /** Height */
  height?: number;
  /** Show labels */
  showLabels?: boolean;
}

// ============ Component ============

export function CorrelationMeter({
  correlation,
  peakCorrelation,
  orientation = 'horizontal',
  width = 200,
  height = 24,
  showLabels = true,
}: CorrelationMeterProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  // Draw meter
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const w = canvas.width;
    const h = canvas.height;
    const isHorizontal = orientation === 'horizontal';

    // Clear
    ctx.fillStyle = '#1a1a1a';
    ctx.fillRect(0, 0, w, h);

    // Draw scale marks
    ctx.fillStyle = '#2a2a2a';
    const marks = [-1, -0.5, 0, 0.5, 1];
    for (const mark of marks) {
      const pos = (mark + 1) / 2; // Convert -1..1 to 0..1
      if (isHorizontal) {
        ctx.fillRect(pos * w - 0.5, 0, 1, h);
      } else {
        ctx.fillRect(0, (1 - pos) * h - 0.5, w, 1);
      }
    }

    // Center line (0)
    ctx.fillStyle = '#444';
    if (isHorizontal) {
      ctx.fillRect(w / 2 - 1, 0, 2, h);
    } else {
      ctx.fillRect(0, h / 2 - 1, w, 2);
    }

    // Clamp correlation
    const clampedCorr = Math.max(-1, Math.min(1, correlation));
    const corrPos = (clampedCorr + 1) / 2;

    // Draw correlation bar
    // Color based on value: green near +1, yellow at 0, red at -1
    let barColor: string;
    if (clampedCorr > 0.5) {
      barColor = '#51cf66'; // Green
    } else if (clampedCorr > 0) {
      barColor = '#ffd43b'; // Yellow
    } else if (clampedCorr > -0.5) {
      barColor = '#ff922b'; // Orange
    } else {
      barColor = '#ff6b6b'; // Red
    }

    ctx.fillStyle = barColor;

    if (isHorizontal) {
      // Draw from center
      const centerX = w / 2;
      const barX = corrPos * w;
      const barWidth = Math.abs(barX - centerX);

      if (clampedCorr >= 0) {
        ctx.fillRect(centerX, 4, barWidth, h - 8);
      } else {
        ctx.fillRect(barX, 4, barWidth, h - 8);
      }

      // Current position marker
      ctx.fillStyle = '#fff';
      ctx.fillRect(barX - 2, 2, 4, h - 4);
    } else {
      // Vertical
      const centerY = h / 2;
      const barY = (1 - corrPos) * h;
      const barHeight = Math.abs(barY - centerY);

      if (clampedCorr >= 0) {
        ctx.fillRect(4, barY, w - 8, barHeight);
      } else {
        ctx.fillRect(4, centerY, w - 8, barHeight);
      }

      // Current position marker
      ctx.fillStyle = '#fff';
      ctx.fillRect(2, barY - 2, w - 4, 4);
    }

    // Peak hold
    if (peakCorrelation !== undefined) {
      const peakPos = (Math.max(-1, Math.min(1, peakCorrelation)) + 1) / 2;
      ctx.fillStyle = '#888';

      if (isHorizontal) {
        ctx.fillRect(peakPos * w - 1, 0, 2, h);
      } else {
        ctx.fillRect(0, (1 - peakPos) * h - 1, w, 2);
      }
    }
  }, [correlation, peakCorrelation, orientation]);

  const isHorizontal = orientation === 'horizontal';

  return (
    <div
      className={`correlation-meter correlation-meter--${orientation}`}
      style={{ width, height }}
    >
      {showLabels && (
        <div className="correlation-meter__labels">
          <span className="correlation-meter__label correlation-meter__label--left">
            {isHorizontal ? '-1' : '+1'}
          </span>
          <span className="correlation-meter__label correlation-meter__label--center">
            0
          </span>
          <span className="correlation-meter__label correlation-meter__label--right">
            {isHorizontal ? '+1' : '-1'}
          </span>
        </div>
      )}
      <canvas
        ref={canvasRef}
        width={isHorizontal ? width : height}
        height={isHorizontal ? height - (showLabels ? 14 : 0) : width}
        className="correlation-meter__canvas"
      />
    </div>
  );
}

export default CorrelationMeter;
