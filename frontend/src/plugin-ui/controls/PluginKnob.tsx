/**
 * Plugin Knob Component
 *
 * DAW-grade rotary control with:
 * - Pointer capture for reliable drag
 * - Shift for fine control
 * - Double-click to reset
 * - Mouse wheel support
 * - Arc visualization
 *
 * @module plugin-ui/controls/PluginKnob
 */

import { useRef, useState, useCallback, useEffect, memo } from 'react';
import { usePluginTheme } from '../usePluginTheme';
import './PluginKnob.css';

// ============ Types ============

export interface PluginKnobProps {
  /** Current value */
  value: number;
  /** Minimum value */
  min: number;
  /** Maximum value */
  max: number;
  /** Default value (for reset) */
  defaultValue?: number;
  /** Step size */
  step?: number;
  /** Fine step (with shift) */
  fineStep?: number;
  /** Label text */
  label?: string;
  /** Unit suffix */
  unit?: string;
  /** Decimal places for display */
  decimals?: number;
  /** Value changed callback */
  onChange: (value: number) => void;
  /** Drag started callback */
  onDragStart?: () => void;
  /** Drag ended callback */
  onDragEnd?: () => void;
  /** Size in pixels */
  size?: number;
  /** Disabled state */
  disabled?: boolean;
  /** Show value below */
  showValue?: boolean;
  /** Custom value formatter */
  formatValue?: (value: number) => string;
  /** Custom class */
  className?: string;
  /** Bipolar mode (center at 0) */
  bipolar?: boolean;
}

// ============ Constants ============

const DEFAULT_SIZE = 48;
const START_ANGLE = (225 * Math.PI) / 180;
const END_ANGLE = (-45 * Math.PI) / 180;
const SWEEP = END_ANGLE - START_ANGLE;

// ============ Utilities ============

const clamp = (v: number, min: number, max: number) => Math.min(max, Math.max(min, v));

function polarToCartesian(cx: number, cy: number, r: number, angle: number) {
  return {
    x: cx + r * Math.cos(angle),
    y: cy + r * Math.sin(angle),
  };
}

// ============ Component ============

function PluginKnobInner({
  value,
  min,
  max,
  defaultValue,
  step = 1,
  fineStep,
  label,
  unit = '',
  decimals = 1,
  onChange,
  onDragStart,
  onDragEnd,
  size = DEFAULT_SIZE,
  disabled = false,
  showValue = true,
  formatValue,
  className,
  bipolar = false,
}: PluginKnobProps) {
  const theme = usePluginTheme();
  const [isDragging, setIsDragging] = useState(false);
  const dragRef = useRef<{ startY: number; startValue: number } | null>(null);
  const rafRef = useRef<number | null>(null);
  const pendingRef = useRef<number | null>(null);

  // Normalized value (0-1)
  const normalized = (value - min) / (max - min);
  const angle = START_ANGLE + normalized * SWEEP;

  // Arc geometry
  const cx = size / 2;
  const cy = size / 2;
  const r = size * 0.4;
  const rInner = size * 0.28;

  const start = polarToCartesian(cx, cy, r, START_ANGLE);
  const end = polarToCartesian(cx, cy, r, END_ANGLE);
  const current = polarToCartesian(cx, cy, r, angle);

  // Track path (full arc)
  const trackPath = `M ${start.x} ${start.y} A ${r} ${r} 0 1 1 ${end.x} ${end.y}`;

  // Value arc
  const largeArc = normalized > 0.5 ? 1 : 0;
  const valuePath = bipolar
    ? normalized >= 0.5
      ? `M ${cx} ${cy - r} A ${r} ${r} 0 ${normalized > 0.75 ? 1 : 0} 1 ${current.x} ${current.y}`
      : `M ${current.x} ${current.y} A ${r} ${r} 0 ${normalized < 0.25 ? 1 : 0} 1 ${cx} ${cy - r}`
    : `M ${start.x} ${start.y} A ${r} ${r} 0 ${largeArc} 1 ${current.x} ${current.y}`;

  // Needle endpoint
  const needleLen = r - 6;
  const needle = polarToCartesian(cx, cy, needleLen, angle);

  // Format display value
  const displayValue = formatValue
    ? formatValue(value)
    : `${value.toFixed(decimals)}${unit}`;

  // Schedule change with RAF throttle
  const scheduleChange = useCallback((newValue: number) => {
    pendingRef.current = newValue;
    if (rafRef.current) return;
    rafRef.current = requestAnimationFrame(() => {
      if (pendingRef.current !== null) {
        onChange(pendingRef.current);
        pendingRef.current = null;
      }
      rafRef.current = null;
    });
  }, [onChange]);

  // Pointer handlers
  const handlePointerDown = useCallback((e: React.PointerEvent) => {
    if (disabled) return;
    e.preventDefault();

    const target = e.currentTarget as HTMLElement;
    target.setPointerCapture(e.pointerId);

    setIsDragging(true);
    dragRef.current = { startY: e.clientY, startValue: value };
    onDragStart?.();
  }, [disabled, value, onDragStart]);

  const handlePointerMove = useCallback((e: React.PointerEvent) => {
    if (!dragRef.current) return;

    const deltaY = dragRef.current.startY - e.clientY;
    const isFine = e.shiftKey;
    const effectiveStep = isFine ? (fineStep ?? step * 0.1) : step;

    // Sensitivity: pixels per full range
    const sensitivity = isFine ? 400 : 150;
    const range = max - min;
    const deltaValue = (deltaY / sensitivity) * range;

    let newValue = dragRef.current.startValue + deltaValue;
    newValue = clamp(newValue, min, max);

    // Round to step
    const steps = Math.round((newValue - min) / effectiveStep);
    newValue = min + steps * effectiveStep;
    newValue = clamp(newValue, min, max);

    scheduleChange(newValue);
  }, [min, max, step, fineStep, scheduleChange]);

  const handlePointerUp = useCallback((e: React.PointerEvent) => {
    const target = e.currentTarget as HTMLElement;
    target.releasePointerCapture(e.pointerId);

    setIsDragging(false);
    dragRef.current = null;
    onDragEnd?.();
  }, [onDragEnd]);

  const handleDoubleClick = useCallback(() => {
    if (disabled) return;
    const resetValue = defaultValue ?? ((min + max) / 2);
    onChange(resetValue);
  }, [disabled, defaultValue, min, max, onChange]);

  const handleWheel = useCallback((e: React.WheelEvent) => {
    if (disabled) return;
    e.preventDefault();

    const isFine = e.shiftKey;
    const effectiveStep = isFine ? (fineStep ?? step * 0.1) : step;
    const direction = e.deltaY > 0 ? -1 : 1;

    let newValue = value + direction * effectiveStep;
    newValue = clamp(newValue, min, max);
    onChange(newValue);
  }, [disabled, value, min, max, step, fineStep, onChange]);

  // Cleanup
  useEffect(() => {
    return () => {
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
    };
  }, []);

  return (
    <div
      className={`plugin-knob ${disabled ? 'disabled' : ''} ${isDragging ? 'dragging' : ''} ${className ?? ''}`}
      style={{ width: size }}
    >
      <div
        className="plugin-knob__hit-area"
        style={{ width: size, height: size, touchAction: 'none' }}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        onDoubleClick={handleDoubleClick}
        onWheel={handleWheel}
        role="slider"
        aria-valuemin={min}
        aria-valuemax={max}
        aria-valuenow={value}
        aria-label={label}
        tabIndex={disabled ? -1 : 0}
      >
        <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
          {/* Track */}
          <path
            d={trackPath}
            fill="none"
            stroke={theme.knobTrack}
            strokeWidth={3}
            strokeLinecap="round"
          />

          {/* Value arc */}
          {normalized > 0.001 && (
            <path
              d={valuePath}
              fill="none"
              stroke={theme.knobFill}
              strokeWidth={3}
              strokeLinecap="round"
            />
          )}

          {/* Inner cap */}
          <circle
            cx={cx}
            cy={cy}
            r={rInner}
            fill={theme.bgControl}
            stroke={theme.border}
            strokeWidth={1}
          />

          {/* Needle */}
          <line
            x1={cx}
            y1={cy}
            x2={needle.x}
            y2={needle.y}
            stroke={theme.knobIndicator}
            strokeWidth={2}
            strokeLinecap="round"
          />

          {/* Center dot */}
          <circle cx={cx} cy={cy} r={2} fill={theme.knobIndicator} />
        </svg>
      </div>

      {label && (
        <div className="plugin-knob__label" style={{ color: theme.textSecondary }}>
          {label}
        </div>
      )}

      {showValue && (
        <div className="plugin-knob__value" style={{ color: theme.textPrimary }}>
          {displayValue}
        </div>
      )}
    </div>
  );
}

export const PluginKnob = memo(PluginKnobInner);
export default PluginKnob;
