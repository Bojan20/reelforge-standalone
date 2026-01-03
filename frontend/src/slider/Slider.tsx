/**
 * ReelForge Slider
 *
 * Slider component:
 * - Single value and range mode
 * - Step and marks support
 * - Vertical and horizontal
 * - Keyboard navigation
 * - Custom formatting
 *
 * @module slider/Slider
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import './Slider.css';

// ============ Types ============

export interface SliderMark {
  /** Value */
  value: number;
  /** Label */
  label?: string;
}

export interface SliderProps {
  /** Current value (single) or [min, max] for range */
  value: number | [number, number];
  /** On change */
  onChange: (value: number | [number, number]) => void;
  /** Minimum value */
  min?: number;
  /** Maximum value */
  max?: number;
  /** Step size */
  step?: number;
  /** Marks */
  marks?: SliderMark[];
  /** Show marks */
  showMarks?: boolean;
  /** Orientation */
  orientation?: 'horizontal' | 'vertical';
  /** Disabled */
  disabled?: boolean;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Custom class */
  className?: string;
  /** Format tooltip value */
  formatValue?: (value: number) => string;
  /** Show tooltip */
  showTooltip?: boolean | 'always';
  /** On change end (mouse up) */
  onChangeEnd?: (value: number | [number, number]) => void;
}

// ============ Component ============

export function Slider({
  value,
  onChange,
  min = 0,
  max = 100,
  step = 1,
  marks,
  showMarks = false,
  orientation = 'horizontal',
  disabled = false,
  size = 'medium',
  className = '',
  formatValue = (v) => String(v),
  showTooltip = true,
  onChangeEnd,
}: SliderProps) {
  const isRange = Array.isArray(value);
  const [activeThumb, setActiveThumb] = useState<0 | 1 | null>(null);
  const [hoveredThumb, setHoveredThumb] = useState<0 | 1 | null>(null);
  const trackRef = useRef<HTMLDivElement>(null);

  const isVertical = orientation === 'vertical';

  // Get value as array
  const values: [number, number] = isRange ? value : [min, value];

  // Calculate percentage
  const getPercent = (val: number) => ((val - min) / (max - min)) * 100;

  // Calculate value from position
  const getValueFromPosition = useCallback(
    (clientX: number, clientY: number): number => {
      if (!trackRef.current) return min;

      const rect = trackRef.current.getBoundingClientRect();
      const position = isVertical
        ? 1 - (clientY - rect.top) / rect.height
        : (clientX - rect.left) / rect.width;

      const rawValue = min + position * (max - min);
      const steppedValue = Math.round(rawValue / step) * step;
      return Math.max(min, Math.min(max, steppedValue));
    },
    [min, max, step, isVertical]
  );

  // Handle drag
  useEffect(() => {
    if (activeThumb === null) return;

    const handleMove = (e: MouseEvent) => {
      const newValue = getValueFromPosition(e.clientX, e.clientY);

      if (isRange) {
        const newValues: [number, number] = [...values];
        newValues[activeThumb] = newValue;

        // Prevent crossing
        if (activeThumb === 0 && newValue > values[1]) {
          newValues[0] = values[1];
        } else if (activeThumb === 1 && newValue < values[0]) {
          newValues[1] = values[0];
        }

        onChange(newValues);
      } else {
        onChange(newValue);
      }
    };

    const handleUp = () => {
      setActiveThumb(null);
      if (onChangeEnd) {
        onChangeEnd(isRange ? values : values[1]);
      }
    };

    document.addEventListener('mousemove', handleMove);
    document.addEventListener('mouseup', handleUp);

    return () => {
      document.removeEventListener('mousemove', handleMove);
      document.removeEventListener('mouseup', handleUp);
    };
  }, [activeThumb, values, isRange, getValueFromPosition, onChange, onChangeEnd]);

  // Handle track click
  const handleTrackClick = useCallback(
    (e: React.MouseEvent) => {
      if (disabled) return;

      const newValue = getValueFromPosition(e.clientX, e.clientY);

      if (isRange) {
        // Find closest thumb
        const distToStart = Math.abs(newValue - values[0]);
        const distToEnd = Math.abs(newValue - values[1]);
        const thumbIndex = distToStart < distToEnd ? 0 : 1;

        const newValues: [number, number] = [...values];
        newValues[thumbIndex] = newValue;
        onChange(newValues);
      } else {
        onChange(newValue);
      }
    },
    [disabled, getValueFromPosition, isRange, values, onChange]
  );

  // Handle keyboard
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent, thumbIndex: 0 | 1) => {
      if (disabled) return;

      let delta = 0;
      switch (e.key) {
        case 'ArrowRight':
        case 'ArrowUp':
          delta = step;
          break;
        case 'ArrowLeft':
        case 'ArrowDown':
          delta = -step;
          break;
        case 'PageUp':
          delta = step * 10;
          break;
        case 'PageDown':
          delta = -step * 10;
          break;
        case 'Home':
          delta = min - values[thumbIndex];
          break;
        case 'End':
          delta = max - values[thumbIndex];
          break;
        default:
          return;
      }

      e.preventDefault();
      const newValue = Math.max(min, Math.min(max, values[thumbIndex] + delta));

      if (isRange) {
        const newValues: [number, number] = [...values];
        newValues[thumbIndex] = newValue;

        // Prevent crossing
        if (thumbIndex === 0 && newValue > values[1]) return;
        if (thumbIndex === 1 && newValue < values[0]) return;

        onChange(newValues);
      } else {
        onChange(newValue);
      }
    },
    [disabled, step, min, max, values, isRange, onChange]
  );

  // Render thumb
  const renderThumb = (index: 0 | 1) => {
    const val = values[index];
    const percent = getPercent(val);
    const isActive = activeThumb === index;
    const isHovered = hoveredThumb === index;
    const showTip = showTooltip === 'always' || ((showTooltip && (isActive || isHovered)));

    // Skip first thumb if not range
    if (!isRange && index === 0) return null;

    return (
      <div
        key={index}
        className={`slider__thumb ${isActive ? 'slider__thumb--active' : ''}`}
        style={{
          [isVertical ? 'bottom' : 'left']: `${percent}%`,
        }}
        onMouseDown={(e) => {
          e.stopPropagation();
          if (!disabled) setActiveThumb(index);
        }}
        onMouseEnter={() => setHoveredThumb(index)}
        onMouseLeave={() => setHoveredThumb(null)}
        onKeyDown={(e) => handleKeyDown(e, index)}
        tabIndex={disabled ? -1 : 0}
        role="slider"
        aria-valuemin={min}
        aria-valuemax={max}
        aria-valuenow={val}
      >
        {showTip && (
          <div className="slider__tooltip">{formatValue(val)}</div>
        )}
      </div>
    );
  };

  // Calculate fill position
  const fillStart = isRange ? getPercent(values[0]) : 0;
  const fillEnd = getPercent(isRange ? values[1] : values[1]);

  return (
    <div
      className={`slider slider--${orientation} slider--${size} ${
        disabled ? 'slider--disabled' : ''
      } ${className}`}
    >
      <div
        ref={trackRef}
        className="slider__track"
        onClick={handleTrackClick}
      >
        {/* Fill */}
        <div
          className="slider__fill"
          style={{
            [isVertical ? 'bottom' : 'left']: `${fillStart}%`,
            [isVertical ? 'height' : 'width']: `${fillEnd - fillStart}%`,
          }}
        />

        {/* Marks */}
        {showMarks && marks && marks.map((mark) => (
          <div
            key={mark.value}
            className={`slider__mark ${
              mark.value >= values[0] && mark.value <= values[1]
                ? 'slider__mark--active'
                : ''
            }`}
            style={{
              [isVertical ? 'bottom' : 'left']: `${getPercent(mark.value)}%`,
            }}
          >
            {mark.label && (
              <span className="slider__mark-label">{mark.label}</span>
            )}
          </div>
        ))}

        {/* Thumbs */}
        {renderThumb(0)}
        {renderThumb(1)}
      </div>
    </div>
  );
}

export default Slider;
