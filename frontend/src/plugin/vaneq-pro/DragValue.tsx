/**
 * DragValue.tsx
 *
 * FabFilter-style draggable value display.
 * Features:
 * - Pointer capture drag (never drops)
 * - Nonlinear feel with acceleration + expo shaping
 * - Log mode for frequency, linear for gain/Q
 * - Magnetic snapping with hysteresis (0 dB)
 * - Shift = fine, Alt = ultra-fine
 * - dy computed from initial pointer-down (no incremental jitter)
 */

import React, { useEffect, useMemo, useRef, useState } from 'react';

type DragValueProps = {
  className?: string;
  label?: string;

  value: number;
  min: number;
  max: number;

  // How to interpret the drag
  mode?: 'linear' | 'log'; // log is good for frequency
  // Sensitivity: bigger = faster
  sensitivity?: number; // default per mode
  // Nonlinear feel
  accel?: number; // 0..2 typical
  expo?: number; // 1.0 linear; >1 = more "physical" acceleration feel

  // Optional snapping magnets (ex: 0 dB)
  magnets?: number[];
  magnetThreshold?: number; // in value units (ex: 0.35 dB)
  magnetHysteresis?: number; // multiplier (ex: 1.6)

  // Fine adjust modifiers
  fineMultiplier?: number; // Shift
  ultraFineMultiplier?: number; // Alt/Option

  // Callbacks
  format: (v: number) => string;
  onChange: (v: number) => void;
  onDragStart?: () => void;
  onDragEnd?: () => void;

  // Disabled state
  disabled?: boolean;
};

function clamp(v: number, min: number, max: number) {
  return Math.max(min, Math.min(max, v));
}

export const DragValue: React.FC<DragValueProps> = ({
  className,
  label,

  value,
  min,
  max,

  mode = 'linear',
  sensitivity,
  accel = 0.9,
  expo = 1.15,

  magnets = [],
  magnetThreshold = 0.35,
  magnetHysteresis = 1.6,

  fineMultiplier = 0.2,
  ultraFineMultiplier = 0.05,

  format,
  onChange,
  onDragStart,
  onDragEnd,

  disabled = false,
}) => {
  const [dragging, setDragging] = useState(false);

  const startYRef = useRef(0);
  const startValRef = useRef(0);
  const pointerIdRef = useRef<number | null>(null);
  const capturedElementRef = useRef<Element | null>(null);

  // Magnetic latch: once snapped, keep snapped until you leave a bigger range
  const magnetLatchRef = useRef<number | null>(null);

  const baseSens = useMemo(() => {
    if (typeof sensitivity === 'number') return sensitivity;
    // Defaults tuned for "FabFilter-ish" speed
    if (mode === 'log') return 0.0075; // dy → multiplicative ratio
    return (max - min) / 280; // dy → linear value
  }, [sensitivity, mode, min, max]);

  const applyMagnets = (v: number) => {
    if (!magnets.length) return v;

    const latched = magnetLatchRef.current;
    if (latched !== null) {
      const release = magnetThreshold * magnetHysteresis;
      if (Math.abs(v - latched) <= release) return latched;
      magnetLatchRef.current = null;
    }

    let best: number | null = null;
    let bestDist = Infinity;
    for (const m of magnets) {
      const d = Math.abs(v - m);
      if (d < bestDist) {
        bestDist = d;
        best = m;
      }
    }
    if (best !== null && bestDist <= magnetThreshold) {
      magnetLatchRef.current = best;
      return best;
    }
    return v;
  };

  const handlePointerDown = (e: React.PointerEvent) => {
    if (disabled) return;
    e.preventDefault();
    e.stopPropagation();

    // Capture pointer for reliable drag (even outside window)
    const el = e.currentTarget as Element;
    el.setPointerCapture(e.pointerId);
    capturedElementRef.current = el;

    pointerIdRef.current = e.pointerId;
    startYRef.current = e.clientY;
    startValRef.current = value;
    magnetLatchRef.current = null;
    setDragging(true);
    onDragStart?.();
  };

  const handlePointerMove = (e: React.PointerEvent) => {
    if (disabled) return;
    if (!dragging) return;
    if (pointerIdRef.current !== e.pointerId) return;

    const dy = startYRef.current - e.clientY; // up = positive

    let mul = 1;
    if (e.shiftKey) mul *= fineMultiplier;
    if (e.altKey) mul *= ultraFineMultiplier;

    // Nonlinear "physical" feel: larger drags accelerate smoothly
    const absDy = Math.abs(dy);
    const accelFactor = 1 + accel * Math.pow(absDy / 120, 1.0); // smooth accel
    const shaped = Math.sign(dy) * Math.pow(absDy, expo);

    let next = startValRef.current;

    if (mode === 'log') {
      // Multiplicative: ratio grows with drag distance
      const ratio = Math.exp(shaped * baseSens * mul * accelFactor);
      next = startValRef.current * ratio;
    } else {
      // Linear
      next = startValRef.current + shaped * baseSens * mul * accelFactor;
    }

    next = clamp(next, min, max);
    next = applyMagnets(next);

    onChange(next);
  };

  const endDrag = (e?: React.PointerEvent) => {
    if (e && pointerIdRef.current !== e.pointerId) return;

    // Release pointer capture (prevents "stuck drag" when mouse leaves window)
    if (capturedElementRef.current && pointerIdRef.current !== null) {
      try {
        capturedElementRef.current.releasePointerCapture(pointerIdRef.current);
      } catch {
        // Ignore if already released
      }
      capturedElementRef.current = null;
    }

    pointerIdRef.current = null;
    setDragging(false);
    magnetLatchRef.current = null;
    onDragEnd?.();
  };

  useEffect(() => {
    const onKeyUp = () => {
      // If user releases modifiers, do nothing special; keep stable.
    };
    window.addEventListener('keyup', onKeyUp);
    return () => window.removeEventListener('keyup', onKeyUp);
  }, []);

  return (
    <div
      className={`${className ?? 'dragValue'} ${dragging ? 'dragging' : ''} ${disabled ? 'disabled' : ''}`}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={endDrag}
      onPointerCancel={endDrag}
      style={{ cursor: disabled ? 'default' : 'ns-resize', userSelect: 'none', touchAction: 'none' }}
      title={disabled ? '' : 'Drag up/down. Shift=Fine, Alt=Ultra-fine.'}
    >
      {label && <span className="dragValueLabel">{label}</span>}
      <span className={`dragValueText ${dragging ? 'active' : ''}`}>{format(value)}</span>
    </div>
  );
};

export default DragValue;
