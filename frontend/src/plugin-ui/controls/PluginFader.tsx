/**
 * Plugin Fader Component
 *
 * Linear slider/fader control with:
 * - Vertical or horizontal orientation
 * - dB scale support
 * - Fine control with shift
 * - Double-click reset
 *
 * @module plugin-ui/controls/PluginFader
 */

import { useRef, useState, useCallback, memo } from 'react';
import { usePluginTheme } from '../usePluginTheme';
import './PluginFader.css';

// ============ Types ============

export interface PluginFaderProps {
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
  /** Label text */
  label?: string;
  /** Unit suffix */
  unit?: string;
  /** Decimal places */
  decimals?: number;
  /** Value changed callback */
  onChange: (value: number) => void;
  /** Orientation */
  orientation?: 'vertical' | 'horizontal';
  /** Length in pixels */
  length?: number;
  /** Thickness in pixels */
  thickness?: number;
  /** Disabled state */
  disabled?: boolean;
  /** Show value */
  showValue?: boolean;
  /** Custom value formatter */
  formatValue?: (value: number) => string;
  /** Custom class */
  className?: string;
  /** dB scale (logarithmic feel) */
  dbScale?: boolean;
}

// ============ Utilities ============

const clamp = (v: number, min: number, max: number) => Math.min(max, Math.max(min, v));

// ============ Component ============

function PluginFaderInner({
  value,
  min,
  max,
  defaultValue,
  step = 0.1,
  label,
  unit = '',
  decimals = 1,
  onChange,
  orientation = 'vertical',
  length = 100,
  thickness = 24,
  disabled = false,
  showValue = true,
  formatValue,
  className,
  dbScale = false,
}: PluginFaderProps) {
  const theme = usePluginTheme();
  const [isDragging, setIsDragging] = useState(false);
  const trackRef = useRef<HTMLDivElement>(null);

  const isVertical = orientation === 'vertical';

  // Normalized value (0-1)
  const normalized = dbScale
    ? dbToNormalized(value, min, max)
    : (value - min) / (max - min);

  // Format display value
  const displayValue = formatValue
    ? formatValue(value)
    : `${value.toFixed(decimals)}${unit}`;

  // Convert normalized to value
  const normalizedToValue = useCallback((norm: number) => {
    if (dbScale) {
      return normalizedToDb(norm, min, max);
    }
    return min + norm * (max - min);
  }, [min, max, dbScale]);

  // Pointer handlers
  const handlePointerDown = useCallback((e: React.PointerEvent) => {
    if (disabled || !trackRef.current) return;
    e.preventDefault();

    const target = e.currentTarget as HTMLElement;
    target.setPointerCapture(e.pointerId);

    setIsDragging(true);
    updateValue(e);
  }, [disabled]);

  const updateValue = useCallback((e: React.PointerEvent) => {
    if (!trackRef.current) return;

    const rect = trackRef.current.getBoundingClientRect();
    const isFine = e.shiftKey;
    const fineStep = step * 0.1;
    const effectiveStep = isFine ? fineStep : step;

    let norm: number;
    if (isVertical) {
      norm = 1 - (e.clientY - rect.top) / rect.height;
    } else {
      norm = (e.clientX - rect.left) / rect.width;
    }

    norm = clamp(norm, 0, 1);
    let newValue = normalizedToValue(norm);

    // Round to step
    const steps = Math.round((newValue - min) / effectiveStep);
    newValue = min + steps * effectiveStep;
    newValue = clamp(newValue, min, max);

    onChange(newValue);
  }, [isVertical, min, max, step, normalizedToValue, onChange]);

  const handlePointerMove = useCallback((e: React.PointerEvent) => {
    if (!isDragging) return;
    updateValue(e);
  }, [isDragging, updateValue]);

  const handlePointerUp = useCallback((e: React.PointerEvent) => {
    const target = e.currentTarget as HTMLElement;
    target.releasePointerCapture(e.pointerId);
    setIsDragging(false);
  }, []);

  const handleDoubleClick = useCallback(() => {
    if (disabled) return;
    const resetValue = defaultValue ?? 0;
    onChange(clamp(resetValue, min, max));
  }, [disabled, defaultValue, min, max, onChange]);

  // Thumb position
  const thumbPosition = normalized * 100;
  const thumbStyle = isVertical
    ? { bottom: `${thumbPosition}%` }
    : { left: `${thumbPosition}%` };

  // Fill style
  const fillStyle = isVertical
    ? { height: `${thumbPosition}%` }
    : { width: `${thumbPosition}%` };

  return (
    <div
      className={`plugin-fader plugin-fader--${orientation} ${disabled ? 'disabled' : ''} ${isDragging ? 'dragging' : ''} ${className ?? ''}`}
      style={{
        [isVertical ? 'height' : 'width']: length,
        [isVertical ? 'width' : 'height']: thickness,
      }}
    >
      {label && (
        <div className="plugin-fader__label" style={{ color: theme.textSecondary }}>
          {label}
        </div>
      )}

      <div
        ref={trackRef}
        className="plugin-fader__track"
        style={{
          background: theme.faderTrack,
          [isVertical ? 'height' : 'width']: length - (showValue ? 24 : 0) - (label ? 16 : 0),
        }}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        onDoubleClick={handleDoubleClick}
      >
        <div
          className="plugin-fader__fill"
          style={{
            background: theme.faderThumb,
            ...fillStyle,
          }}
        />
        <div
          className="plugin-fader__thumb"
          style={{
            background: theme.faderThumb,
            boxShadow: `0 0 4px ${theme.shadowMedium}`,
            ...thumbStyle,
          }}
        />
      </div>

      {showValue && (
        <div className="plugin-fader__value" style={{ color: theme.textPrimary }}>
          {displayValue}
        </div>
      )}
    </div>
  );
}

// dB scale helpers
function dbToNormalized(db: number, min: number, max: number): number {
  // Use log-like curve for dB
  const range = max - min;
  const norm = (db - min) / range;
  return Math.pow(norm, 0.5); // Square root curve
}

function normalizedToDb(norm: number, min: number, max: number): number {
  const range = max - min;
  return min + Math.pow(norm, 2) * range;
}

export const PluginFader = memo(PluginFaderInner);
export default PluginFader;
