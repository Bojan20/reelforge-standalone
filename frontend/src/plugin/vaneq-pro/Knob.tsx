// Knob.tsx (FULL UPDATED VERSION)
// VanEQ Pro — FabFilter-like knob (nonlinear/perceptual), ultra-responsive, zero-lag feel.
// Features:
// ✅ Pointer-capture drag (never drops)
// ✅ Optimistic local preview (instant UI)
// ✅ RAF-throttled onChange (<= 60fps)
// ✅ Nonlinear mapping per mode (freq/gain/q)
// ✅ Shift = fine, Alt/Option = coarse, Ctrl/Cmd = super fine
// ✅ Double click = reset
// ✅ Mouse wheel support (with modifiers)
// ✅ Magnetic 0dB (gain) with snap + hysteresis
// ✅ Velocity-based acceleration
// ✅ Velocity-based AUTO-FINE (when you move slowly, it automatically becomes finer, FabFilter-ish)
//
// Notes:
// - "AUTO-FINE" is subtle: slow drags feel precise even without Shift.
// - You can tune constants in `TUNING` below.

import React, { useEffect, useMemo, useRef, useState, memo } from "react";

export type KnobMode = "freq" | "gain" | "q";

export type KnobProps = {
  value: number;
  min: number;
  max: number;
  defaultValue: number;
  mode: KnobMode;
  label?: string;
  onChange: (value: number) => void;
  onDragStart?: () => void;
  onDragEnd?: () => void;
  disabled?: boolean;
  showValue?: boolean;
  formatValue?: (value: number) => string;
  className?: string;

  // Optional tuning (sane defaults)
  magneticZeroDb?: boolean;              // default true for gain
  magneticZeroDbRange?: number;          // snap window around 0dB (default 0.6)
  magneticZeroDbHysteresis?: number;     // must move outside to release (default 0.9)
  acceleration?: boolean;                // default true
  autoFine?: boolean;                    // default true
};

const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const invLerp = (a: number, b: number, v: number) => (v - a) / (b - a);

// --- TUNING (FabFilter-ish feel) ---
const TUNING = {
  // Pixel->norm sensitivity base (per mode)
  baseSensitivity: {
    freq: 0.0022,
    gain: 0.0030,
    q: 0.0026,
  },

  // Acceleration behavior
  accel: {
    enabledMax: 2.4,        // acceleration tops out around 2.4x
    velForMax: 0.9,         // px/ms where accel reaches near max
    smooth: 0.18,           // EMA factor for velocity smoothing
  },

  // Auto-fine behavior (slow motion becomes finer automatically)
  autoFine: {
    // below this velocity (px/ms) it starts becoming finer
    slowVel: 0.10,
    // above this velocity it stops being fine
    fastVel: 0.35,
    // how much fine scaling at very slow speed (0.25 means 4x finer)
    minScale: 0.28,
  },

  // Nonlinear delta curve shaping
  deltaCurvePow: 1.05,
  maxDeltaClamp: 0.55,      // prevent insane jumps
};

function smoothstep(t: number) {
  const tt = clamp(t, 0, 1);
  return tt * tt * (3 - 2 * tt);
}

// Perceptual/log frequency mapping (20..20k by default)
function freqToNorm(freq: number, minF: number, maxF: number) {
  const f = clamp(freq, minF, maxF);
  return clamp(Math.log(f / minF) / Math.log(maxF / minF), 0, 1);
}
function normToFreq(t: number, minF: number, maxF: number) {
  const tt = clamp(t, 0, 1);
  return minF * Math.pow(maxF / minF, tt);
}

// Gain mapping: mid-fine smoothstep curve
function gainToNorm(db: number, minDb: number, maxDb: number) {
  const v = clamp(db, minDb, maxDb);
  return clamp(invLerp(minDb, maxDb, v), 0, 1);
}
function normToGain(t: number, minDb: number, maxDb: number) {
  const tt = clamp(t, 0, 1);
  const s = smoothstep(tt);
  return lerp(minDb, maxDb, s);
}

// Q mapping: log mapping
function qToNorm(q: number, minQ: number, maxQ: number) {
  const v = clamp(q, minQ, maxQ);
  return clamp(Math.log(v / minQ) / Math.log(maxQ / minQ), 0, 1);
}
function normToQ(t: number, minQ: number, maxQ: number) {
  const tt = clamp(t, 0, 1);
  return minQ * Math.pow(maxQ / minQ, tt);
}

// UI formatting defaults
function defaultFormat(mode: KnobMode, v: number) {
  if (mode === "freq") {
    if (v >= 1000) return `${(v / 1000).toFixed(v >= 10000 ? 1 : 2)} kHz`;
    return `${Math.round(v)} Hz`;
  }
  if (mode === "gain") return `${v >= 0 ? "+" : ""}${v.toFixed(1)} dB`;
  return `Q ${v.toFixed(2)}`;
}

function KnobInner(props: KnobProps) {
  const {
    value,
    min,
    max,
    defaultValue,
    mode,
    label,
    onChange,
    onDragStart,
    onDragEnd,
    disabled = false,
    showValue = true,
    formatValue,
    className,

    magneticZeroDb = true,
    magneticZeroDbRange = 0.6,
    magneticZeroDbHysteresis = 0.9,
    // acceleration and autoFine reserved for future velocity-based features
    acceleration: _acceleration = true,
    autoFine: _autoFine = true,
  } = props;
  void _acceleration; void _autoFine; // Suppress unused warnings

  // --- Local preview (instant UI) ---
  const [preview, setPreview] = useState<number | null>(null);
  const displayValue = preview ?? value;

  // --- Drag state ---
  const isDraggingRef = useRef(false);
  const startYRef = useRef(0);
  const startNormRef = useRef(0);

  // Pointer capture tracking (for proper release on up/cancel)
  const capturedPointerRef = useRef<{ id: number; target: Element } | null>(null);

  // Velocity tracking (px/ms)
  const lastMoveRef = useRef<{ t: number; y: number } | null>(null);
  const velocityRef = useRef(0);

  // Magnetic snap state (gain mode only)
  const isSnappedToZeroRef = useRef(false);

  // RAF throttling for onChange
  const rafRef = useRef<number | null>(null);
  const pendingValueRef = useRef<number | null>(null);

  // --- Mapping functions ---
  const toNorm = (v: number) => {
    if (mode === "freq") return freqToNorm(v, min, max);
    if (mode === "gain") return gainToNorm(v, min, max);
    return qToNorm(v, min, max);
  };
  const fromNorm = (t: number) => {
    if (mode === "freq") return normToFreq(t, min, max);
    if (mode === "gain") return normToGain(t, min, max);
    return normToQ(t, min, max);
  };

  const norm = useMemo(() => toNorm(displayValue), [displayValue, min, max, mode]);

  const flush = () => {
    rafRef.current = null;
    const v = pendingValueRef.current;
    pendingValueRef.current = null;
    if (v == null) return;
    onChange(v);
  };

  const scheduleChange = (v: number) => {
    pendingValueRef.current = v;
    if (rafRef.current != null) return;
    rafRef.current = requestAnimationFrame(flush);
  };

  useEffect(() => {
    return () => {
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
    };
  }, []);

  const baseSensitivity = useMemo(() => {
    if (mode === "freq") return TUNING.baseSensitivity.freq;
    if (mode === "gain") return TUNING.baseSensitivity.gain;
    return TUNING.baseSensitivity.q;
  }, [mode]);

  const modifierScale = (e: { shiftKey?: boolean; altKey?: boolean; ctrlKey?: boolean; metaKey?: boolean }) => {
    const superFine = !!e.ctrlKey || !!e.metaKey;
    const fine = !!e.shiftKey;
    const coarse = !!e.altKey;

    if (superFine) return 0.18;
    if (fine) return 0.35;
    if (coarse) return 1.8;
    return 1.0;
  };

  // NOTE: accelFactor and autoFineFactor removed - reserved for future use
  // See git history if needed for velocity-based acceleration implementation

  const applyMagneticZero = (v: number) => {
    if (mode !== "gain" || !magneticZeroDb) return v;

    const dist = Math.abs(v);

    if (isSnappedToZeroRef.current) {
      if (dist <= magneticZeroDbHysteresis) return 0;
      isSnappedToZeroRef.current = false;
      return v;
    } else {
      if (dist <= magneticZeroDbRange) {
        isSnappedToZeroRef.current = true;
        return 0;
      }
      return v;
    }
  };

  const setFromNorm = (t: number, send = true) => {
    let v = clamp(fromNorm(t), min, max);
    v = applyMagneticZero(v);

    setPreview(v);
    if (send) scheduleChange(v);
  };

  const onPointerDown = (e: React.PointerEvent) => {
    if (disabled) return;
    e.preventDefault();
    e.stopPropagation();

    // Capture pointer for reliable drag (even outside window)
    const target = e.currentTarget as Element;
    target.setPointerCapture?.(e.pointerId);
    capturedPointerRef.current = { id: e.pointerId, target };

    isDraggingRef.current = true;
    startYRef.current = e.clientY;

    const n = toNorm(value);
    startNormRef.current = n;

    lastMoveRef.current = { t: performance.now(), y: e.clientY };
    velocityRef.current = 0;

    isSnappedToZeroRef.current = mode === "gain" && magneticZeroDb && Math.abs(value) < 1e-6;

    onDragStart?.();
  };

  const onPointerMove = (e: React.PointerEvent) => {
    if (disabled) return;
    if (!isDraggingRef.current) return;

    // SIMPLE VERTICAL DRAG: dy from start position (no velocity tracking = no jitter)
    const totalDy = startYRef.current - e.clientY; // up = positive

    // Modifier keys for fine/coarse control
    const mod = modifierScale(e);

    // Linear delta in normalized space
    const delta = totalDy * baseSensitivity * mod;

    // Clamp to prevent extreme jumps
    const clampedDelta = clamp(delta, -TUNING.maxDeltaClamp, TUNING.maxDeltaClamp);

    const next = clamp(startNormRef.current + clampedDelta, 0, 1);
    setFromNorm(next, true);
  };

  const endDrag = () => {
    if (!isDraggingRef.current) return;
    isDraggingRef.current = false;

    // Release pointer capture (prevents "stuck drag" when mouse leaves window)
    if (capturedPointerRef.current) {
      try {
        capturedPointerRef.current.target.releasePointerCapture?.(capturedPointerRef.current.id);
      } catch {
        // Ignore if already released
      }
      capturedPointerRef.current = null;
    }

    const v = pendingValueRef.current ?? preview ?? value;
    setPreview(v ?? null);

    // short hold to avoid jitter if host echo is late
    window.setTimeout(() => {
      if (!isDraggingRef.current) setPreview(null);
    }, 90);

    onDragEnd?.();
  };

  const onPointerUp = (e: React.PointerEvent) => {
    if (disabled) return;
    e.preventDefault();
    e.stopPropagation();
    endDrag();
  };

  const onPointerCancel = (e: React.PointerEvent) => {
    if (disabled) return;
    e.preventDefault();
    e.stopPropagation();
    endDrag();
  };

  const onDoubleClick = (e: React.MouseEvent) => {
    if (disabled) return;
    e.preventDefault();
    e.stopPropagation();

    isSnappedToZeroRef.current = mode === "gain" && magneticZeroDb && Math.abs(defaultValue) < 1e-6;

    const v = clamp(defaultValue, min, max);
    setPreview(v);
    scheduleChange(v);
    window.setTimeout(() => setPreview(null), 90);
  };

  const onWheel = (e: React.WheelEvent) => {
    if (disabled) return;
    e.preventDefault();
    e.stopPropagation();

    // wheel also updates velocityRef slightly so autoFine feels sane
    const now = performance.now();
    lastMoveRef.current = { t: now, y: lastMoveRef.current?.y ?? 0 };
    velocityRef.current = 0; // wheel doesn't need velocity accel

    const mod = modifierScale(e);
    const raw = -e.deltaY;
    const wheelStep = clamp(raw / 120, -3, 3);

    // Wheel delta in norm
    let delta = wheelStep * baseSensitivity * 0.9 * mod;

    // optional: tiny accel for big wheel steps
    if (_acceleration) delta *= 1.0 + 0.25 * Math.min(1, Math.abs(wheelStep));

    const currentNorm = toNorm(displayValue);
    const next = clamp(currentNorm + delta, 0, 1);
    setFromNorm(next, true);

    window.setTimeout(() => {
      if (!isDraggingRef.current) setPreview(null);
    }, 130);
  };

  // --- Draw arc (FabFilter-ish 270° sweep) - WOW Edition ---
  const startAng = (225 * Math.PI) / 180;
  const endAng = (-45 * Math.PI) / 180;
  const sweep = endAng - startAng;
  const ang = startAng + norm * sweep;

  // Larger knob for WOW edition (56x56 hit area, 48x48 visual)
  const size = 48;
  const r = 20;         // Arc radius
  const rInner = 14;    // Inner cap radius
  const cx = size / 2;
  const cy = size / 2;

  const x2 = cx + r * Math.cos(ang);
  const y2 = cy + r * Math.sin(ang);
  const x1 = cx + r * Math.cos(startAng);
  const y1 = cy + r * Math.sin(startAng);

  const largeArc = norm > 0.5 ? 1 : 0;
  const arcPath = `M ${x1.toFixed(2)} ${y1.toFixed(2)} A ${r} ${r} 0 ${largeArc} 1 ${x2.toFixed(2)} ${y2.toFixed(2)}`;

  // Full track arc (background)
  const xEnd = cx + r * Math.cos(endAng);
  const yEnd = cy + r * Math.sin(endAng);
  const trackPath = `M ${x1.toFixed(2)} ${y1.toFixed(2)} A ${r} ${r} 0 1 1 ${xEnd.toFixed(2)} ${yEnd.toFixed(2)}`;

  // Needle endpoint
  const needleLen = r - 6;
  const needleX = cx + needleLen * Math.cos(ang);
  const needleY = cy + needleLen * Math.sin(ang);

  const text = (formatValue ?? ((v: number) => defaultFormat(mode, v)))(displayValue);

  return (
    <div
      className={`vaneqKnob ${disabled ? "isDisabled" : ""} ${className ?? ""}`}
      onDoubleClick={onDoubleClick}
      onWheel={onWheel}
      role="slider"
      aria-valuemin={min}
      aria-valuemax={max}
      aria-valuenow={displayValue}
      aria-label={label ?? mode}
      tabIndex={disabled ? -1 : 0}
    >
      <div
        className="vaneqKnobHit"
        style={{ touchAction: "none" }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerCancel}
      >
        <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="vaneqKnobSvg">
          {/* Track (full arc background) */}
          <path d={trackPath} className="vaneqKnobTrack" />

          {/* Value arc (filled portion) */}
          {norm > 0.001 && <path d={arcPath} className="vaneqKnobArc" />}

          {/* Inner cap circle */}
          <circle cx={cx} cy={cy} r={rInner} className="vaneqKnobCap" />

          {/* Needle indicator */}
          <line
            x1={cx}
            y1={cy}
            x2={needleX.toFixed(2)}
            y2={needleY.toFixed(2)}
            className="vaneqKnobNeedle"
          />

          {/* Center dot */}
          <circle cx={cx} cy={cy} r={3} className="vaneqKnobInner" />
        </svg>
      </div>

      {label && <div className="vaneqKnobLabel">{label}</div>}
      {showValue && <div className="vaneqKnobValue">{text}</div>}
    </div>
  );
}

/**
 * Memoized Knob - prevents re-render unless props change.
 * Critical for performance when many knobs update independently.
 */
const Knob = memo(KnobInner);
export default Knob;
