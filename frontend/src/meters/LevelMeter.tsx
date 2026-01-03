/**
 * ReelForge Level Meter
 *
 * Professional audio level meter with:
 * - Peak and RMS levels
 * - Peak hold
 * - Clip indicators
 * - Stereo/mono support
 * - Configurable scale
 *
 * @module meters/LevelMeter
 */

import { useRef, useEffect, useCallback } from 'react';
import './LevelMeter.css';

// ============ Types ============

export interface LevelMeterProps {
  /** Left channel level (0-1 linear, or dB if useDB) */
  levelL: number;
  /** Right channel level (0-1 linear, or dB if useDB) */
  levelR?: number;
  /** RMS level left */
  rmsL?: number;
  /** RMS level right */
  rmsR?: number;
  /** Peak hold left */
  peakHoldL?: number;
  /** Peak hold right */
  peakHoldR?: number;
  /** Is clipping left */
  clipL?: boolean;
  /** Is clipping right */
  clipR?: boolean;
  /** Orientation */
  orientation?: 'vertical' | 'horizontal';
  /** Show scale labels */
  showScale?: boolean;
  /** Show channel labels */
  showLabels?: boolean;
  /** Mono mode (single channel) */
  mono?: boolean;
  /** Width in pixels */
  width?: number;
  /** Height in pixels */
  height?: number;
  /** Min dB value */
  minDB?: number;
  /** Max dB value */
  maxDB?: number;
  /** Input is in dB (not linear) */
  useDB?: boolean;
  /** On clip indicator click (reset) */
  onClipReset?: () => void;
}

// ============ Constants ============

const DEFAULT_SCALE_MARKS = [-60, -48, -36, -24, -18, -12, -6, -3, 0, 3, 6];

const GRADIENT_STOPS = [
  { pos: 0, color: '#51cf66' },      // Green (low)
  { pos: 0.6, color: '#51cf66' },    // Green
  { pos: 0.75, color: '#ffd43b' },   // Yellow
  { pos: 0.9, color: '#ff922b' },    // Orange
  { pos: 1.0, color: '#ff6b6b' },    // Red (clip)
];

// ============ Helpers ============

function linearToDb(linear: number): number {
  if (linear <= 0) return -Infinity;
  return 20 * Math.log10(linear);
}

/** Convert dB to linear (exported for external use) */
export function dbToLinear(db: number): number {
  return Math.pow(10, db / 20);
}

function dbToPosition(db: number, minDB: number, maxDB: number): number {
  if (db <= minDB) return 0;
  if (db >= maxDB) return 1;
  return (db - minDB) / (maxDB - minDB);
}

// ============ Component ============

export function LevelMeter({
  levelL,
  levelR,
  rmsL,
  rmsR,
  peakHoldL,
  peakHoldR,
  clipL = false,
  clipR = false,
  orientation = 'vertical',
  showScale = true,
  showLabels = true,
  mono = false,
  width,
  height,
  minDB = -60,
  maxDB = 6,
  useDB = false,
  onClipReset,
}: LevelMeterProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const gradientRef = useRef<CanvasGradient | null>(null);

  // Noise gate threshold: -90dB = ~0.00003 linear
  // Values below this are treated as silence to prevent floating-point noise display
  const NOISE_FLOOR = 0.00003;
  const NOISE_FLOOR_DB = -90;

  // Apply noise gate to a value
  const applyNoiseGate = useCallback(
    (value: number): number => {
      if (useDB) {
        // Input is in dB
        return value < NOISE_FLOOR_DB ? -Infinity : value;
      } else {
        // Input is linear
        return value < NOISE_FLOOR ? 0 : value;
      }
    },
    [useDB]
  );

  // Convert to dB if needed (with noise gate)
  const getDB = useCallback(
    (value: number): number => {
      const gated = applyNoiseGate(value);
      return useDB ? gated : linearToDb(gated);
    },
    [useDB, applyNoiseGate]
  );

  // Compute positions
  const levelLPos = dbToPosition(getDB(levelL), minDB, maxDB);
  const levelRPos = mono ? levelLPos : dbToPosition(getDB(levelR ?? levelL), minDB, maxDB);
  const rmsLPos = rmsL !== undefined ? dbToPosition(getDB(rmsL), minDB, maxDB) : undefined;
  const rmsRPos = rmsR !== undefined ? dbToPosition(getDB(rmsR), minDB, maxDB) : undefined;
  const peakHoldLPos =
    peakHoldL !== undefined ? dbToPosition(getDB(peakHoldL), minDB, maxDB) : undefined;
  const peakHoldRPos =
    peakHoldR !== undefined ? dbToPosition(getDB(peakHoldR), minDB, maxDB) : undefined;

  // Draw meter
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const isVertical = orientation === 'vertical';
    const w = canvas.width;
    const h = canvas.height;

    // Clear
    ctx.clearRect(0, 0, w, h);

    // Create gradient if needed
    if (!gradientRef.current) {
      const gradient = isVertical
        ? ctx.createLinearGradient(0, h, 0, 0)
        : ctx.createLinearGradient(0, 0, w, 0);

      for (const stop of GRADIENT_STOPS) {
        gradient.addColorStop(stop.pos, stop.color);
      }
      gradientRef.current = gradient;
    }

    const meterWidth = mono ? w : w / 2 - 1;
    const meterGap = mono ? 0 : 2;

    // Draw function
    const drawChannel = (
      pos: number,
      rmsPos: number | undefined,
      peakPos: number | undefined,
      offsetX: number
    ) => {
      // Background
      ctx.fillStyle = '#1a1a1a';
      if (isVertical) {
        ctx.fillRect(offsetX, 0, meterWidth, h);
      } else {
        ctx.fillRect(0, offsetX, w, meterWidth);
      }

      // Level bar
      ctx.fillStyle = gradientRef.current!;
      if (isVertical) {
        const barHeight = pos * h;
        ctx.fillRect(offsetX, h - barHeight, meterWidth, barHeight);
      } else {
        const barWidth = pos * w;
        ctx.fillRect(0, offsetX, barWidth, meterWidth);
      }

      // RMS overlay (darker)
      if (rmsPos !== undefined) {
        ctx.fillStyle = 'rgba(0, 0, 0, 0.3)';
        if (isVertical) {
          const rmsHeight = rmsPos * h;
          const peakHeight = pos * h;
          ctx.fillRect(offsetX, h - peakHeight, meterWidth, peakHeight - rmsHeight);
        } else {
          const rmsWidth = rmsPos * w;
          const peakWidth = pos * w;
          ctx.fillRect(rmsWidth, offsetX, peakWidth - rmsWidth, meterWidth);
        }
      }

      // Peak hold line
      if (peakPos !== undefined && peakPos > 0) {
        ctx.fillStyle = peakPos >= 1 ? '#ff6b6b' : '#fff';
        if (isVertical) {
          const peakY = h - peakPos * h;
          ctx.fillRect(offsetX, peakY - 1, meterWidth, 2);
        } else {
          const peakX = peakPos * w;
          ctx.fillRect(peakX - 1, offsetX, 2, meterWidth);
        }
      }
    };

    // Draw channels
    drawChannel(levelLPos, rmsLPos, peakHoldLPos, 0);
    if (!mono) {
      drawChannel(levelRPos, rmsRPos, peakHoldRPos, meterWidth + meterGap);
    }
  }, [
    levelLPos,
    levelRPos,
    rmsLPos,
    rmsRPos,
    peakHoldLPos,
    peakHoldRPos,
    orientation,
    mono,
  ]);

  // Compute dimensions
  const isVertical = orientation === 'vertical';
  const meterWidth = width ?? (isVertical ? (mono ? 16 : 32) : 200);
  const meterHeight = height ?? (isVertical ? 200 : (mono ? 16 : 32));

  // Scale marks
  const scaleMarks = DEFAULT_SCALE_MARKS.filter((db) => db >= minDB && db <= maxDB);

  return (
    <div
      className={`level-meter level-meter--${orientation} ${mono ? 'level-meter--mono' : ''}`}
      style={{ width: meterWidth + (showScale ? 24 : 0), height: meterHeight }}
    >
      {/* Scale */}
      {showScale && (
        <div className="level-meter__scale">
          {scaleMarks.map((db) => {
            const pos = dbToPosition(db, minDB, maxDB);
            const style = isVertical
              ? { bottom: `${pos * 100}%` }
              : { left: `${pos * 100}%` };

            return (
              <span key={db} className="level-meter__scale-mark" style={style}>
                {db}
              </span>
            );
          })}
        </div>
      )}

      {/* Meter canvas */}
      <div className="level-meter__bars">
        <canvas
          ref={canvasRef}
          width={mono ? 16 : 30}
          height={meterHeight}
          className="level-meter__canvas"
        />
      </div>

      {/* Clip indicators */}
      <div className="level-meter__clips" onClick={onClipReset}>
        <div className={`level-meter__clip ${clipL ? 'active' : ''}`} />
        {!mono && <div className={`level-meter__clip ${clipR ? 'active' : ''}`} />}
      </div>

      {/* Labels */}
      {showLabels && !mono && (
        <div className="level-meter__labels">
          <span>L</span>
          <span>R</span>
        </div>
      )}
    </div>
  );
}

export default LevelMeter;
