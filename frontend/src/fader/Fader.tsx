/**
 * ReelForge Fader
 *
 * Vertical/horizontal fader control:
 * - Drag to adjust
 * - Fine control with shift
 * - Double-click to reset
 * - dB scale markings
 * - Value display
 *
 * @module fader/Fader
 */

import { useState, useCallback, useRef, useEffect, useMemo } from 'react';
import './Fader.css';

// ============ Types ============

export type FaderOrientation = 'vertical' | 'horizontal';

export interface FaderProps {
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
  /** Orientation */
  orientation?: FaderOrientation;
  /** Length in pixels */
  length?: number;
  /** Track width */
  trackWidth?: number;
  /** Handle size */
  handleSize?: number;
  /** Track color */
  trackColor?: string;
  /** Active track color */
  activeColor?: string;
  /** Handle color */
  handleColor?: string;
  /** Show value */
  showValue?: boolean;
  /** Value formatter */
  formatValue?: (value: number) => string;
  /** Show scale marks */
  showScale?: boolean;
  /** Scale marks */
  scaleMarks?: number[];
  /** Label */
  label?: string;
  /** Disabled */
  disabled?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Fader Component ============

export function Fader({
  value,
  defaultValue = 0,
  min = -60,
  max = 12,
  step = 0.1,
  onChange,
  onChangeEnd,
  orientation = 'vertical',
  length = 200,
  trackWidth = 6,
  handleSize = 24,
  trackColor = 'rgba(255, 255, 255, 0.1)',
  activeColor = '#6366f1',
  handleColor = '#3a3a3a',
  showValue = true,
  formatValue,
  showScale = true,
  scaleMarks = [12, 6, 0, -6, -12, -24, -48, -60],
  label,
  disabled = false,
  className = '',
}: FaderProps) {
  const [internalValue, setInternalValue] = useState(value ?? defaultValue);
  const [isDragging, setIsDragging] = useState(false);
  const trackRef = useRef<HTMLDivElement>(null);

  const currentValue = value ?? internalValue;
  const isVertical = orientation === 'vertical';

  // Normalize value to 0-1 range
  const normalizedValue = useMemo(() => {
    return (currentValue - min) / (max - min);
  }, [currentValue, min, max]);

  // Handle position
  const handlePosition = useMemo(() => {
    return normalizedValue * (length - handleSize);
  }, [normalizedValue, length, handleSize]);

  // Active track length
  const activeLength = useMemo(() => {
    return normalizedValue * (length - handleSize) + handleSize / 2;
  }, [normalizedValue, length, handleSize]);

  // Update value with clamping
  const updateValue = useCallback(
    (newValue: number) => {
      const stepped = Math.round(newValue / step) * step;
      const clamped = Math.max(min, Math.min(max, stepped));

      setInternalValue(clamped);
      onChange?.(clamped);
    },
    [min, max, step, onChange]
  );

  // Calculate value from position
  const positionToValue = useCallback(
    (clientX: number, clientY: number): number => {
      const track = trackRef.current;
      if (!track) return currentValue;

      const rect = track.getBoundingClientRect();
      let normalized: number;

      if (isVertical) {
        const y = clientY - rect.top - handleSize / 2;
        const available = length - handleSize;
        normalized = 1 - Math.max(0, Math.min(1, y / available));
      } else {
        const x = clientX - rect.left - handleSize / 2;
        const available = length - handleSize;
        normalized = Math.max(0, Math.min(1, x / available));
      }

      return min + normalized * (max - min);
    },
    [isVertical, length, handleSize, min, max, currentValue]
  );

  // Mouse handlers
  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      if (disabled) return;
      e.preventDefault();

      setIsDragging(true);
      const newValue = positionToValue(e.clientX, e.clientY);
      updateValue(newValue);

      document.addEventListener('mousemove', handleMouseMove);
      document.addEventListener('mouseup', handleMouseUp);
    },
    [disabled, positionToValue, updateValue]
  );

  const handleMouseMove = useCallback(
    (e: MouseEvent) => {
      const sensitivity = e.shiftKey ? 0.1 : 1;
      const newValue = positionToValue(e.clientX, e.clientY);

      if (e.shiftKey) {
        // Fine control: smaller steps
        const delta = (newValue - currentValue) * sensitivity;
        updateValue(currentValue + delta);
      } else {
        updateValue(newValue);
      }
    },
    [positionToValue, currentValue, updateValue]
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
      updateValue(currentValue + delta * multiplier * 10);
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
    : `${currentValue.toFixed(1)} dB`;

  // Scale marks
  const scaleElements = useMemo(() => {
    if (!showScale) return null;

    return scaleMarks
      .filter((mark) => mark >= min && mark <= max)
      .map((mark) => {
        const normalized = (mark - min) / (max - min);
        const position = isVertical
          ? (1 - normalized) * (length - handleSize) + handleSize / 2
          : normalized * (length - handleSize) + handleSize / 2;

        return (
          <div
            key={mark}
            className="fader__scale-mark"
            style={isVertical ? { top: position } : { left: position }}
          >
            <span className="fader__scale-label">{mark}</span>
          </div>
        );
      });
  }, [showScale, scaleMarks, min, max, isVertical, length, handleSize]);

  return (
    <div
      className={`fader fader--${orientation} ${disabled ? 'fader--disabled' : ''} ${
        isDragging ? 'fader--dragging' : ''
      } ${className}`}
    >
      {label && <div className="fader__label">{label}</div>}

      <div className="fader__container" style={isVertical ? { height: length } : { width: length }}>
        {showScale && <div className="fader__scale">{scaleElements}</div>}

        <div
          ref={trackRef}
          className="fader__track"
          style={{
            [isVertical ? 'height' : 'width']: length,
            [isVertical ? 'width' : 'height']: trackWidth,
            backgroundColor: trackColor,
          }}
          onMouseDown={handleMouseDown}
          onDoubleClick={handleDoubleClick}
          onWheel={handleWheel}
        >
          {/* Active track */}
          <div
            className="fader__active"
            style={{
              [isVertical ? 'height' : 'width']: activeLength,
              backgroundColor: activeColor,
            }}
          />

          {/* Handle */}
          <div
            className="fader__handle"
            style={{
              [isVertical ? 'bottom' : 'left']: handlePosition,
              width: isVertical ? handleSize * 1.5 : handleSize,
              height: isVertical ? handleSize : handleSize * 1.5,
              backgroundColor: handleColor,
            }}
          >
            <div className="fader__handle-grip" />
          </div>
        </div>
      </div>

      {showValue && <div className="fader__value">{displayValue}</div>}
    </div>
  );
}

// ============ useFader Hook ============

export function useFader(initialValue = 0, min = -60, max = 12) {
  const [value, setValue] = useState(initialValue);

  const reset = useCallback(() => {
    setValue(initialValue);
  }, [initialValue]);

  // Convert linear to dB
  const toDb = useCallback((linear: number) => {
    if (linear <= 0) return -Infinity;
    return 20 * Math.log10(linear);
  }, []);

  // Convert dB to linear
  const toLinear = useCallback((db: number) => {
    return Math.pow(10, db / 20);
  }, []);

  return {
    value,
    setValue,
    reset,
    toDb,
    toLinear,
    props: { value, onChange: setValue, min, max },
  };
}

export default Fader;
