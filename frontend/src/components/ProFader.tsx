/**
 * ProFader - Professional DAW-Quality Fader Component
 *
 * Features:
 * - GPU-accelerated Canvas rendering (60fps)
 * - Dual stereo meter with peak hold
 * - Clip detection with flash animation
 * - dB scale with major/minor ticks
 * - Cubase/Pro Tools style aesthetics
 * - Fine control with Shift key
 * - Double-click reset to unity
 * - Touch support
 * - Gain reduction meter overlay
 *
 * @module components/ProFader
 */

import { useRef, useEffect, useCallback, memo, useState } from 'react';

// ============ Types ============

export interface ProFaderProps {
  /** Current value in dB */
  value: number;
  /** Minimum value in dB (default: -60) */
  min?: number;
  /** Maximum value in dB (default: +12) */
  max?: number;
  /** Left channel meter (0-1 normalized) */
  meterL?: number;
  /** Right channel meter (0-1 normalized) */
  meterR?: number;
  /** Left channel peak (0-1 normalized) */
  peakL?: number;
  /** Right channel peak (0-1 normalized) */
  peakR?: number;
  /** Gain reduction in dB (for compressor/limiter display) */
  gainReduction?: number;
  /** Width in pixels (default: 60) */
  width?: number;
  /** Height in pixels (default: 200) */
  height?: number;
  /** Value changed callback */
  onChange?: (value: number) => void;
  /** Disabled state */
  disabled?: boolean;
  /** Show scale labels */
  showScale?: boolean;
  /** Fader style */
  style?: 'cubase' | 'protools' | 'logic' | 'ableton';
  /** Channel label */
  label?: string;
  /** Stereo or mono meter */
  stereo?: boolean;
}

// ============ Constants ============

const FADER_THUMB_HEIGHT = 24;
const METER_GAP = 2;
const SCALE_WIDTH = 24;
const PEAK_HOLD_TIME = 1500; // ms
const PEAK_DECAY_RATE = 0.003; // per frame

// Color constants
const COLORS = {
  // Meter gradient
  meterGreen: '#00cc33',
  meterGreenDark: '#006622',
  meterYellow: '#ffcc00',
  meterOrange: '#ff8800',
  meterRed: '#ff0033',

  // UI
  background: '#1a1a1a',
  trackBg: '#0d0d0d',
  thumbBg: '#3a3a3a',
  thumbHighlight: '#4a4a4a',
  thumbActive: '#5a5a5a',
  scale: '#666666',
  scaleText: '#888888',
  unity: '#00aaff',
  clip: '#ff0033',

  // Gain reduction
  grMeter: '#ff8800',
};

// dB scale marks
const SCALE_MARKS = [12, 6, 3, 0, -3, -6, -12, -18, -24, -36, -48, -60];
const MINOR_MARKS = [9, -9, -15, -21, -30, -42, -54];

// ============ Utility Functions ============

function dbToNormalized(db: number, min: number, max: number): number {
  return (db - min) / (max - min);
}

// normalizedToDb - kept for future use if needed
// function normalizedToDb(normalized: number, min: number, max: number): number {
//   return min + normalized * (max - min);
// }

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function formatDb(db: number): string {
  if (db <= -60) return '-∞';
  if (db >= 0) return `+${db.toFixed(1)}`;
  return db.toFixed(1);
}

// ============ Component ============

export const ProFader = memo(function ProFader({
  value,
  min = -60,
  max = 12,
  meterL = 0,
  meterR = 0,
  peakL = 0,
  peakR = 0,
  gainReduction = 0,
  width = 60,
  height = 200,
  onChange,
  disabled = false,
  showScale = true,
  style = 'cubase',
  label,
  stereo = true,
}: ProFaderProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const rafRef = useRef<number>(0);
  const draggingRef = useRef(false);
  const startYRef = useRef(0);
  const startValueRef = useRef(0);
  const shiftHeldRef = useRef(false);

  // Peak hold state
  const peakHoldLRef = useRef(0);
  const peakHoldRRef = useRef(0);
  const peakHoldTimerLRef = useRef(0);
  const peakHoldTimerRRef = useRef(0);

  // Clip state
  const [isClippingL, setIsClippingL] = useState(false);
  const [isClippingR, setIsClippingR] = useState(false);
  const clipTimerLRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const clipTimerRRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Calculate dimensions
  const scaleW = showScale ? SCALE_WIDTH : 0;
  const meterW = stereo ? (width - scaleW - METER_GAP * 2) / 2 : width - scaleW - METER_GAP;
  const faderX = scaleW;
  const faderH = height - 20; // Leave room for value display

  // Update peak hold
  useEffect(() => {
    const now = performance.now();

    // Left channel
    if (peakL > peakHoldLRef.current) {
      peakHoldLRef.current = peakL;
      peakHoldTimerLRef.current = now + PEAK_HOLD_TIME;
    } else if (now > peakHoldTimerLRef.current) {
      peakHoldLRef.current = Math.max(0, peakHoldLRef.current - PEAK_DECAY_RATE);
    }

    // Right channel
    if (peakR > peakHoldRRef.current) {
      peakHoldRRef.current = peakR;
      peakHoldTimerRRef.current = now + PEAK_HOLD_TIME;
    } else if (now > peakHoldTimerRRef.current) {
      peakHoldRRef.current = Math.max(0, peakHoldRRef.current - PEAK_DECAY_RATE);
    }

    // Clip detection
    if (peakL >= 1.0 && !isClippingL) {
      setIsClippingL(true);
      if (clipTimerLRef.current) clearTimeout(clipTimerLRef.current);
      clipTimerLRef.current = setTimeout(() => setIsClippingL(false), 2000);
    }
    if (peakR >= 1.0 && !isClippingR) {
      setIsClippingR(true);
      if (clipTimerRRef.current) clearTimeout(clipTimerRRef.current);
      clipTimerRRef.current = setTimeout(() => setIsClippingR(false), 2000);
    }
  }, [peakL, peakR, isClippingL, isClippingR]);

  // Draw function
  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;

    // Clear
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Scale for retina
    ctx.save();
    ctx.scale(dpr, dpr);

    // Background
    ctx.fillStyle = COLORS.background;
    ctx.fillRect(0, 0, width, height);

    // Draw scale (if enabled)
    if (showScale) {
      ctx.fillStyle = COLORS.scaleText;
      ctx.font = '9px system-ui, sans-serif';
      ctx.textAlign = 'right';
      ctx.textBaseline = 'middle';

      for (const mark of SCALE_MARKS) {
        const y = faderH - dbToNormalized(mark, min, max) * faderH;

        // Major tick
        ctx.fillStyle = mark === 0 ? COLORS.unity : COLORS.scale;
        ctx.fillRect(scaleW - 8, y - 0.5, 6, 1);

        // Label
        ctx.fillStyle = COLORS.scaleText;
        const text = mark === 0 ? '0' : mark > 0 ? `+${mark}` : String(mark);
        ctx.fillText(text, scaleW - 10, y);
      }

      // Minor ticks
      ctx.fillStyle = COLORS.scale;
      for (const mark of MINOR_MARKS) {
        const y = faderH - dbToNormalized(mark, min, max) * faderH;
        ctx.fillRect(scaleW - 4, y - 0.5, 3, 1);
      }
    }

    // Meter track background
    const meterX = faderX + METER_GAP;
    ctx.fillStyle = COLORS.trackBg;
    ctx.fillRect(meterX, 0, meterW, faderH);
    if (stereo) {
      ctx.fillRect(meterX + meterW + METER_GAP, 0, meterW, faderH);
    }

    // Draw meter fills with gradient
    const drawMeterFill = (x: number, level: number, peak: number, clipping: boolean) => {
      const meterHeight = level * faderH;
      const y = faderH - meterHeight;

      // Create gradient based on level
      const gradient = ctx.createLinearGradient(0, faderH, 0, 0);
      gradient.addColorStop(0, COLORS.meterGreenDark);
      gradient.addColorStop(0.6, COLORS.meterGreen);
      gradient.addColorStop(0.75, COLORS.meterYellow);
      gradient.addColorStop(0.88, COLORS.meterOrange);
      gradient.addColorStop(1, COLORS.meterRed);

      ctx.fillStyle = gradient;
      ctx.fillRect(x, y, meterW, meterHeight);

      // Peak hold indicator
      const peakY = faderH - peak * faderH;
      ctx.fillStyle = peak > 0.95 ? COLORS.meterRed : COLORS.meterYellow;
      ctx.fillRect(x, peakY - 1, meterW, 2);

      // Clip indicator
      if (clipping) {
        ctx.fillStyle = COLORS.clip;
        ctx.fillRect(x, 0, meterW, 4);
      }
    };

    // Left meter
    drawMeterFill(meterX, meterL, peakHoldLRef.current, isClippingL);

    // Right meter (if stereo)
    if (stereo) {
      drawMeterFill(meterX + meterW + METER_GAP, meterR, peakHoldRRef.current, isClippingR);
    }

    // Gain reduction overlay (orange, top-down)
    if (gainReduction < -0.1) {
      const grNorm = Math.min(1, Math.abs(gainReduction) / 20); // 20dB max GR display
      const grHeight = grNorm * faderH;
      ctx.fillStyle = 'rgba(255, 136, 0, 0.4)';
      ctx.fillRect(meterX, 0, stereo ? meterW * 2 + METER_GAP : meterW, grHeight);
    }

    // Fader thumb
    const faderNorm = dbToNormalized(value, min, max);
    const thumbY = faderH - faderNorm * faderH - FADER_THUMB_HEIGHT / 2;
    const thumbX = faderX;
    const thumbW = stereo ? meterW * 2 + METER_GAP * 2 : meterW + METER_GAP;

    // Thumb shadow
    ctx.fillStyle = 'rgba(0, 0, 0, 0.3)';
    ctx.fillRect(thumbX + 2, thumbY + 2, thumbW, FADER_THUMB_HEIGHT);

    // Thumb body (style-dependent)
    if (style === 'cubase') {
      // Cubase style - metallic gradient
      const thumbGrad = ctx.createLinearGradient(thumbX, thumbY, thumbX, thumbY + FADER_THUMB_HEIGHT);
      thumbGrad.addColorStop(0, '#5a5a5a');
      thumbGrad.addColorStop(0.3, '#4a4a4a');
      thumbGrad.addColorStop(0.5, '#3a3a3a');
      thumbGrad.addColorStop(0.7, '#4a4a4a');
      thumbGrad.addColorStop(1, '#2a2a2a');
      ctx.fillStyle = thumbGrad;
      ctx.fillRect(thumbX, thumbY, thumbW, FADER_THUMB_HEIGHT);

      // Center line
      ctx.fillStyle = draggingRef.current ? COLORS.unity : '#888888';
      ctx.fillRect(thumbX + 4, thumbY + FADER_THUMB_HEIGHT / 2 - 1, thumbW - 8, 2);
    } else if (style === 'protools') {
      // Pro Tools style - simpler with notches
      ctx.fillStyle = draggingRef.current ? '#5a5a5a' : '#3a3a3a';
      ctx.fillRect(thumbX, thumbY, thumbW, FADER_THUMB_HEIGHT);

      // Notches
      ctx.fillStyle = '#222222';
      for (let i = 0; i < 5; i++) {
        const notchY = thumbY + 4 + i * 4;
        ctx.fillRect(thumbX + 3, notchY, thumbW - 6, 1);
      }
    } else {
      // Default/Logic/Ableton - simple
      ctx.fillStyle = draggingRef.current ? '#5a5a5a' : '#3a3a3a';
      ctx.fillRect(thumbX, thumbY, thumbW, FADER_THUMB_HEIGHT);
      ctx.fillStyle = '#666666';
      ctx.fillRect(thumbX, thumbY + FADER_THUMB_HEIGHT / 2 - 1, thumbW, 2);
    }

    // Unity (0dB) line
    const unityY = faderH - dbToNormalized(0, min, max) * faderH;
    ctx.strokeStyle = COLORS.unity;
    ctx.lineWidth = 1;
    ctx.setLineDash([2, 2]);
    ctx.beginPath();
    ctx.moveTo(faderX, unityY);
    ctx.lineTo(faderX + thumbW, unityY);
    ctx.stroke();
    ctx.setLineDash([]);

    // Value display at bottom
    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 11px system-ui, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    ctx.fillText(formatDb(value) + ' dB', width / 2, faderH + 4);

    // Label (if provided)
    if (label) {
      ctx.fillStyle = '#888888';
      ctx.font = '10px system-ui, sans-serif';
      ctx.fillText(label, width / 2, height - 12);
    }

    ctx.restore();

    // Continue animation
    rafRef.current = requestAnimationFrame(draw);
  }, [
    value, min, max, meterL, meterR, peakL, peakR, gainReduction,
    width, height, showScale, style, label, stereo, isClippingL, isClippingR,
    faderH, faderX, meterW, scaleW
  ]);

  // Initialize canvas and start animation
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const dpr = window.devicePixelRatio || 1;
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;

    rafRef.current = requestAnimationFrame(draw);

    return () => {
      cancelAnimationFrame(rafRef.current);
      if (clipTimerLRef.current) clearTimeout(clipTimerLRef.current);
      if (clipTimerRRef.current) clearTimeout(clipTimerRRef.current);
    };
  }, [width, height, draw]);

  // Mouse/Touch handlers
  const handlePointerDown = useCallback((e: React.PointerEvent) => {
    if (disabled) return;

    draggingRef.current = true;
    startYRef.current = e.clientY;
    startValueRef.current = value;
    shiftHeldRef.current = e.shiftKey;

    (e.target as HTMLElement).setPointerCapture(e.pointerId);
  }, [disabled, value]);

  const handlePointerMove = useCallback((e: React.PointerEvent) => {
    if (!draggingRef.current || disabled) return;

    const deltaY = startYRef.current - e.clientY;
    const sensitivity = e.shiftKey ? 0.1 : 0.5; // Fine control with shift
    const deltaDb = (deltaY / faderH) * (max - min) * sensitivity;

    const newValue = clamp(startValueRef.current + deltaDb, min, max);
    onChange?.(newValue);
  }, [disabled, faderH, max, min, onChange]);

  const handlePointerUp = useCallback((e: React.PointerEvent) => {
    draggingRef.current = false;
    (e.target as HTMLElement).releasePointerCapture(e.pointerId);
  }, []);

  const handleDoubleClick = useCallback(() => {
    if (!disabled) {
      onChange?.(0); // Reset to unity
    }
  }, [disabled, onChange]);

  const handleWheel = useCallback((e: React.WheelEvent) => {
    if (disabled) return;
    e.preventDefault();

    const delta = e.deltaY > 0 ? -1 : 1;
    const step = e.shiftKey ? 0.1 : 1;
    const newValue = clamp(value + delta * step, min, max);
    onChange?.(newValue);
  }, [disabled, value, min, max, onChange]);

  return (
    <canvas
      ref={canvasRef}
      className="rf-pro-fader"
      style={{
        cursor: disabled ? 'not-allowed' : draggingRef.current ? 'grabbing' : 'grab',
        touchAction: 'none',
      }}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onPointerCancel={handlePointerUp}
      onDoubleClick={handleDoubleClick}
      onWheel={handleWheel}
    />
  );
});

export default ProFader;
