/**
 * ReelForge Number Input
 *
 * Number input component:
 * - Step increment/decrement buttons
 * - Drag to adjust value
 * - Min/max constraints
 * - Precision control
 * - Units display
 * - Keyboard shortcuts
 *
 * @module number-input/NumberInput
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import './NumberInput.css';

// ============ Types ============

export interface NumberInputProps {
  /** Current value */
  value: number;
  /** On change */
  onChange: (value: number) => void;
  /** Minimum value */
  min?: number;
  /** Maximum value */
  max?: number;
  /** Step size */
  step?: number;
  /** Decimal precision */
  precision?: number;
  /** Units label */
  units?: string;
  /** Disabled */
  disabled?: boolean;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Show step buttons */
  showButtons?: boolean;
  /** Enable drag to adjust */
  draggable?: boolean;
  /** Custom class */
  className?: string;
  /** Placeholder */
  placeholder?: string;
  /** On change end */
  onChangeEnd?: (value: number) => void;
}

// ============ Component ============

export function NumberInput({
  value,
  onChange,
  min = -Infinity,
  max = Infinity,
  step = 1,
  precision = 2,
  units,
  disabled = false,
  size = 'medium',
  showButtons = true,
  draggable = true,
  className = '',
  placeholder,
  onChangeEnd,
}: NumberInputProps) {
  const [inputValue, setInputValue] = useState(formatValue(value, precision));
  const [isDragging, setIsDragging] = useState(false);
  const [isFocused, setIsFocused] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const dragStartRef = useRef({ y: 0, value: 0 });

  // Format value for display
  function formatValue(val: number, prec: number): string {
    if (Number.isNaN(val)) return '';
    return prec === 0 ? String(Math.round(val)) : val.toFixed(prec);
  }

  // Clamp value to min/max
  const clamp = useCallback(
    (val: number) => Math.max(min, Math.min(max, val)),
    [min, max]
  );

  // Round to step
  const roundToStep = useCallback(
    (val: number) => {
      const rounded = Math.round(val / step) * step;
      return Number(rounded.toFixed(precision));
    },
    [step, precision]
  );

  // Update input when value changes externally
  useEffect(() => {
    if (!isFocused) {
      setInputValue(formatValue(value, precision));
    }
  }, [value, precision, isFocused]);

  // Handle input change
  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const raw = e.target.value;
    setInputValue(raw);

    // Parse and validate
    const parsed = parseFloat(raw);
    if (!Number.isNaN(parsed)) {
      onChange(clamp(parsed));
    }
  };

  // Handle blur - finalize value
  const handleBlur = () => {
    setIsFocused(false);
    const parsed = parseFloat(inputValue);
    const final = Number.isNaN(parsed) ? value : clamp(roundToStep(parsed));
    setInputValue(formatValue(final, precision));
    onChange(final);
    onChangeEnd?.(final);
  };

  // Handle focus
  const handleFocus = () => {
    setIsFocused(true);
    inputRef.current?.select();
  };

  // Increment/decrement
  const increment = useCallback(
    (multiplier = 1) => {
      const newValue = clamp(roundToStep(value + step * multiplier));
      onChange(newValue);
      setInputValue(formatValue(newValue, precision));
    },
    [value, step, clamp, roundToStep, onChange, precision]
  );

  const decrement = useCallback(
    (multiplier = 1) => {
      const newValue = clamp(roundToStep(value - step * multiplier));
      onChange(newValue);
      setInputValue(formatValue(newValue, precision));
    },
    [value, step, clamp, roundToStep, onChange, precision]
  );

  // Handle keyboard
  const handleKeyDown = (e: React.KeyboardEvent) => {
    const multiplier = e.shiftKey ? 10 : 1;

    switch (e.key) {
      case 'ArrowUp':
        e.preventDefault();
        increment(multiplier);
        break;
      case 'ArrowDown':
        e.preventDefault();
        decrement(multiplier);
        break;
      case 'Enter':
        inputRef.current?.blur();
        break;
      case 'Escape':
        setInputValue(formatValue(value, precision));
        inputRef.current?.blur();
        break;
    }
  };

  // Handle drag start
  const handleMouseDown = (e: React.MouseEvent) => {
    if (!draggable || disabled || e.button !== 0) return;
    if ((e.target as HTMLElement).tagName === 'BUTTON') return;

    e.preventDefault();
    setIsDragging(true);
    dragStartRef.current = { y: e.clientY, value };

    document.body.style.cursor = 'ns-resize';
  };

  // Handle drag
  useEffect(() => {
    if (!isDragging) return;

    const handleMouseMove = (e: MouseEvent) => {
      const delta = dragStartRef.current.y - e.clientY;
      const multiplier = e.shiftKey ? 10 : 1;
      const newValue = clamp(
        roundToStep(dragStartRef.current.value + delta * step * 0.1 * multiplier)
      );
      onChange(newValue);
      setInputValue(formatValue(newValue, precision));
    };

    const handleMouseUp = () => {
      setIsDragging(false);
      document.body.style.cursor = '';
      onChangeEnd?.(value);
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);

    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDragging, step, clamp, roundToStep, onChange, precision, onChangeEnd, value]);

  return (
    <div
      className={`number-input number-input--${size} ${
        disabled ? 'number-input--disabled' : ''
      } ${isDragging ? 'number-input--dragging' : ''} ${
        isFocused ? 'number-input--focused' : ''
      } ${className}`}
      onMouseDown={handleMouseDown}
    >
      {/* Decrement button */}
      {showButtons && (
        <button
          type="button"
          className="number-input__btn number-input__btn--dec"
          onClick={() => decrement()}
          disabled={disabled || value <= min}
          tabIndex={-1}
        >
          −
        </button>
      )}

      {/* Input */}
      <input
        ref={inputRef}
        type="text"
        className="number-input__input"
        value={inputValue}
        onChange={handleInputChange}
        onFocus={handleFocus}
        onBlur={handleBlur}
        onKeyDown={handleKeyDown}
        disabled={disabled}
        placeholder={placeholder}
      />

      {/* Units */}
      {units && <span className="number-input__units">{units}</span>}

      {/* Increment button */}
      {showButtons && (
        <button
          type="button"
          className="number-input__btn number-input__btn--inc"
          onClick={() => increment()}
          disabled={disabled || value >= max}
          tabIndex={-1}
        >
          +
        </button>
      )}
    </div>
  );
}

export default NumberInput;
