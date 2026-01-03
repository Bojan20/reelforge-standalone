/**
 * ReelForge Knob
 *
 * Rotary knob control:
 * - Circular drag
 * - Fine control with shift
 * - Double-click to reset
 * - Arc visualization
 * - Value display
 *
 * @module knob/Knob
 */

import { useState, useCallback, useRef, useEffect, useMemo } from 'react';
import './Knob.css';

// ============ Types ============

export interface KnobProps {
  /** Current value */
  value?: number;
  /** Default value */
  defaultValue?: number;
  /** Minimum value */
  min?: number;
  /** Maximum value */
  max?: number;
  /** Step size */
  step?: number;
  /** On change */
  onChange?: (value: number) => void;
  /** On change end */
  onChangeEnd?: (value: number) => void;
  /** Size (diameter in px) */
  size?: number;
  /** Start angle (degrees, 0 = top) */
  startAngle?: number;
  /** End angle (degrees) */
  endAngle?: number;
  /** Arc color */
  arcColor?: string;
  /** Track color */
  trackColor?: string;
  /** Knob color */
  knobColor?: string;
  /** Show value */
  showValue?: boolean;
  /** Value formatter */
  formatValue?: (value: number) => string;
  /** Label */
  label?: string;
  /** Disabled */
  disabled?: boolean;
  /** Bipolar (center = zero) */
  bipolar?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Knob Component ============

export function Knob({
  value,
  defaultValue = 0,
  min = 0,
  max = 100,
  step = 1,
  onChange,
  onChangeEnd,
  size = 48,
  startAngle = -135,
  endAngle = 135,
  arcColor = '#6366f1',
  trackColor = 'rgba(255, 255, 255, 0.1)',
  knobColor = '#2a2a2a',
  showValue = true,
  formatValue,
  label,
  disabled = false,
  bipolar = false,
  className = '',
}: KnobProps) {
  const [internalValue, setInternalValue] = useState(value ?? defaultValue);
  const [isDragging, setIsDragging] = useState(false);
  const knobRef = useRef<HTMLDivElement>(null);
  const startY = useRef(0);
  const startValue = useRef(0);

  const currentValue = value ?? internalValue;

  // Normalize value to 0-1 range
  const normalizedValue = useMemo(() => {
    return (currentValue - min) / (max - min);
  }, [currentValue, min, max]);

  // Calculate rotation angle
  const rotationAngle = useMemo(() => {
    const range = endAngle - startAngle;
    return startAngle + normalizedValue * range;
  }, [normalizedValue, startAngle, endAngle]);

  // Calculate arc path
  const arcPath = useMemo(() => {
    const radius = (size - 8) / 2;
    const cx = size / 2;
    const cy = size / 2;

    const toRad = (deg: number) => (deg * Math.PI) / 180;

    // Track arc (full range)
    const trackStart = toRad(startAngle - 90);
    const trackEnd = toRad(endAngle - 90);

    // Value arc
    let valueStart: number;
    let valueEnd: number;

    if (bipolar) {
      const centerAngle = (startAngle + endAngle) / 2;
      if (currentValue >= (min + max) / 2) {
        valueStart = toRad(centerAngle - 90);
        valueEnd = toRad(rotationAngle - 90);
      } else {
        valueStart = toRad(rotationAngle - 90);
        valueEnd = toRad(centerAngle - 90);
      }
    } else {
      valueStart = toRad(startAngle - 90);
      valueEnd = toRad(rotationAngle - 90);
    }

    const polarToCart = (angle: number, r: number) => ({
      x: cx + r * Math.cos(angle),
      y: cy + r * Math.sin(angle),
    });

    const trackStartPt = polarToCart(trackStart, radius);
    const trackEndPt = polarToCart(trackEnd, radius);
    const valueStartPt = polarToCart(valueStart, radius);
    const valueEndPt = polarToCart(valueEnd, radius);

    const largeArcTrack = Math.abs(endAngle - startAngle) > 180 ? 1 : 0;
    const largeArcValue = Math.abs(valueEnd - valueStart) > Math.PI ? 1 : 0;

    return {
      track: `M ${trackStartPt.x} ${trackStartPt.y} A ${radius} ${radius} 0 ${largeArcTrack} 1 ${trackEndPt.x} ${trackEndPt.y}`,
      value: `M ${valueStartPt.x} ${valueStartPt.y} A ${radius} ${radius} 0 ${largeArcValue} 1 ${valueEndPt.x} ${valueEndPt.y}`,
    };
  }, [size, startAngle, endAngle, rotationAngle, bipolar, currentValue, min, max]);

  // Update value with clamping
  const updateValue = useCallback(
    (newValue: number) => {
      // Snap to step
      const stepped = Math.round(newValue / step) * step;
      const clamped = Math.max(min, Math.min(max, stepped));

      setInternalValue(clamped);
      onChange?.(clamped);
    },
    [min, max, step, onChange]
  );

  // Mouse handlers
  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      if (disabled) return;
      e.preventDefault();

      setIsDragging(true);
      startY.current = e.clientY;
      startValue.current = currentValue;

      document.addEventListener('mousemove', handleMouseMove);
      document.addEventListener('mouseup', handleMouseUp);
    },
    [disabled, currentValue]
  );

  const handleMouseMove = useCallback(
    (e: MouseEvent) => {
      const sensitivity = e.shiftKey ? 0.1 : 1;
      const delta = (startY.current - e.clientY) * sensitivity;
      const range = max - min;
      const valueChange = (delta / 200) * range;
      const newValue = startValue.current + valueChange;

      updateValue(newValue);
    },
    [min, max, updateValue]
  );

  const handleMouseUp = useCallback(() => {
    setIsDragging(false);
    document.removeEventListener('mousemove', handleMouseMove);
    document.removeEventListener('mouseup', handleMouseUp);
    onChangeEnd?.(currentValue);
  }, [handleMouseMove, onChangeEnd, currentValue]);

  // Double-click to reset
  const handleDoubleClick = useCallback(() => {
    if (disabled) return;
    updateValue(defaultValue);
    onChangeEnd?.(defaultValue);
  }, [disabled, defaultValue, updateValue, onChangeEnd]);

  // Wheel handler
  const handleWheel = useCallback(
    (e: React.WheelEvent) => {
      if (disabled) return;
      e.preventDefault();

      const delta = e.deltaY > 0 ? -step : step;
      const multiplier = e.shiftKey ? 0.1 : 1;
      updateValue(currentValue + delta * multiplier);
    },
    [disabled, currentValue, step, updateValue]
  );

  // Cleanup
  useEffect(() => {
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [handleMouseMove, handleMouseUp]);

  // Format display value
  const displayValue = formatValue
    ? formatValue(currentValue)
    : currentValue.toFixed(step < 1 ? 1 : 0);

  return (
    <div
      className={`knob ${disabled ? 'knob--disabled' : ''} ${
        isDragging ? 'knob--dragging' : ''
      } ${className}`}
    >
      {label && <div className="knob__label">{label}</div>}

      <div
        ref={knobRef}
        className="knob__control"
        style={{ width: size, height: size }}
        onMouseDown={handleMouseDown}
        onDoubleClick={handleDoubleClick}
        onWheel={handleWheel}
      >
        {/* SVG Arc */}
        <svg
          className="knob__arc"
          width={size}
          height={size}
          viewBox={`0 0 ${size} ${size}`}
        >
          {/* Track */}
          <path
            d={arcPath.track}
            fill="none"
            stroke={trackColor}
            strokeWidth="4"
            strokeLinecap="round"
          />
          {/* Value arc */}
          <path
            d={arcPath.value}
            fill="none"
            stroke={arcColor}
            strokeWidth="4"
            strokeLinecap="round"
          />
        </svg>

        {/* Knob body */}
        <div
          className="knob__body"
          style={{
            width: size * 0.7,
            height: size * 0.7,
            backgroundColor: knobColor,
            transform: `rotate(${rotationAngle}deg)`,
          }}
        >
          <div className="knob__indicator" />
        </div>
      </div>

      {showValue && <div className="knob__value">{displayValue}</div>}
    </div>
  );
}

// ============ useKnob Hook ============

export function useKnob(initialValue = 0, min = 0, max = 100) {
  const [value, setValue] = useState(initialValue);

  const reset = useCallback(() => {
    setValue(initialValue);
  }, [initialValue]);

  return {
    value,
    setValue,
    reset,
    props: { value, onChange: setValue, min, max },
  };
}

export default Knob;
