/**
 * ReelForge InputNumber
 *
 * Numeric input with controls:
 * - Increment/decrement buttons
 * - Min/max limits
 * - Step value
 * - Precision control
 * - Keyboard support
 *
 * @module input-number/InputNumber
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import './InputNumber.css';

// ============ Types ============

export interface InputNumberProps {
  /** Current value */
  value?: number | null;
  /** Default value */
  defaultValue?: number;
  /** On change */
  onChange?: (value: number | null) => void;
  /** Minimum value */
  min?: number;
  /** Maximum value */
  max?: number;
  /** Step value */
  step?: number;
  /** Decimal precision */
  precision?: number;
  /** Disabled state */
  disabled?: boolean;
  /** Read only */
  readOnly?: boolean;
  /** Placeholder */
  placeholder?: string;
  /** Size */
  size?: 'small' | 'default' | 'large';
  /** Show controls */
  controls?: boolean;
  /** Controls position */
  controlsPosition?: 'right' | 'both';
  /** Prefix */
  prefix?: React.ReactNode;
  /** Suffix */
  suffix?: React.ReactNode;
  /** Formatter */
  formatter?: (value: number | undefined) => string;
  /** Parser */
  parser?: (value: string) => number;
  /** Custom class */
  className?: string;
}

// ============ InputNumber Component ============

export function InputNumber({
  value,
  defaultValue,
  onChange,
  min = -Infinity,
  max = Infinity,
  step = 1,
  precision,
  disabled = false,
  readOnly = false,
  placeholder = '',
  size = 'default',
  controls = true,
  controlsPosition = 'right',
  prefix,
  suffix,
  formatter,
  parser,
  className = '',
}: InputNumberProps) {
  const [internalValue, setInternalValue] = useState<number | null>(
    value ?? defaultValue ?? null
  );
  const [inputValue, setInputValue] = useState<string>(() => {
    const val = value ?? defaultValue;
    if (val === undefined || val === null) return '';
    return formatter ? formatter(val) : String(val);
  });
  const [isFocused, setIsFocused] = useState(false);

  const inputRef = useRef<HTMLInputElement>(null);
  const holdTimerRef = useRef<ReturnType<typeof setInterval>>(undefined);

  // Sync with controlled value
  useEffect(() => {
    if (value !== undefined) {
      setInternalValue(value);
      if (!isFocused) {
        setInputValue(value === null ? '' : formatter ? formatter(value) : String(value));
      }
    }
  }, [value, formatter, isFocused]);

  // Get display precision
  const getDisplayPrecision = useCallback(() => {
    if (precision !== undefined) return precision;
    const stepStr = String(step);
    const decimalIndex = stepStr.indexOf('.');
    return decimalIndex >= 0 ? stepStr.length - decimalIndex - 1 : 0;
  }, [precision, step]);

  // Parse input string to number
  const parseValue = useCallback(
    (str: string): number | null => {
      if (str === '' || str === '-') return null;

      let num: number;
      if (parser) {
        num = parser(str);
      } else {
        num = parseFloat(str.replace(/[^\d.-]/g, ''));
      }

      if (isNaN(num)) return null;

      // Apply precision
      const prec = getDisplayPrecision();
      num = Number(num.toFixed(prec));

      return num;
    },
    [parser, getDisplayPrecision]
  );

  // Clamp value to min/max
  const clamp = useCallback(
    (num: number): number => {
      return Math.min(max, Math.max(min, num));
    },
    [min, max]
  );

  // Update value
  const updateValue = useCallback(
    (newValue: number | null) => {
      if (newValue !== null) {
        newValue = clamp(newValue);
        const prec = getDisplayPrecision();
        newValue = Number(newValue.toFixed(prec));
      }

      setInternalValue(newValue);
      onChange?.(newValue);

      if (!isFocused) {
        setInputValue(
          newValue === null ? '' : formatter ? formatter(newValue) : String(newValue)
        );
      }
    },
    [clamp, getDisplayPrecision, onChange, formatter, isFocused]
  );

  // Handle input change
  const handleInputChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const str = e.target.value;
      setInputValue(str);

      const parsed = parseValue(str);
      if (parsed !== null || str === '') {
        setInternalValue(parsed);
        onChange?.(parsed);
      }
    },
    [parseValue, onChange]
  );

  // Handle blur
  const handleBlur = useCallback(() => {
    setIsFocused(false);

    let val = parseValue(inputValue);
    if (val !== null) {
      val = clamp(val);
    }

    updateValue(val);
  }, [inputValue, parseValue, clamp, updateValue]);

  // Handle focus
  const handleFocus = useCallback(() => {
    setIsFocused(true);
    // Show raw number on focus
    setInputValue(internalValue === null ? '' : String(internalValue));
  }, [internalValue]);

  // Increment/Decrement
  const increment = useCallback(() => {
    const current = internalValue ?? 0;
    updateValue(current + step);
  }, [internalValue, step, updateValue]);

  const decrement = useCallback(() => {
    const current = internalValue ?? 0;
    updateValue(current - step);
  }, [internalValue, step, updateValue]);

  // Handle key down
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (readOnly) return;

      switch (e.key) {
        case 'ArrowUp':
          e.preventDefault();
          increment();
          break;
        case 'ArrowDown':
          e.preventDefault();
          decrement();
          break;
      }
    },
    [readOnly, increment, decrement]
  );

  // Handle mouse down for hold-to-repeat
  const handleMouseDown = useCallback(
    (action: () => void) => {
      if (disabled || readOnly) return;

      action();

      const startHold = () => {
        holdTimerRef.current = setInterval(action, 100);
      };

      const timeout = setTimeout(startHold, 400);

      const handleMouseUp = () => {
        clearTimeout(timeout);
        if (holdTimerRef.current) {
          clearInterval(holdTimerRef.current);
        }
        document.removeEventListener('mouseup', handleMouseUp);
        document.removeEventListener('mouseleave', handleMouseUp);
      };

      document.addEventListener('mouseup', handleMouseUp);
      document.addEventListener('mouseleave', handleMouseUp);
    },
    [disabled, readOnly]
  );

  // Check limits
  const isAtMin = internalValue !== null && internalValue <= min;
  const isAtMax = internalValue !== null && internalValue >= max;

  return (
    <div
      className={`input-number input-number--${size} ${
        controls ? `input-number--controls-${controlsPosition}` : ''
      } ${disabled ? 'input-number--disabled' : ''} ${
        isFocused ? 'input-number--focused' : ''
      } ${className}`}
    >
      {prefix && <span className="input-number__prefix">{prefix}</span>}

      {controls && controlsPosition === 'both' && (
        <button
          type="button"
          className="input-number__btn input-number__btn--minus"
          disabled={disabled || readOnly || isAtMin}
          onMouseDown={() => handleMouseDown(decrement)}
          tabIndex={-1}
        >
          −
        </button>
      )}

      <input
        ref={inputRef}
        type="text"
        className="input-number__input"
        value={inputValue}
        onChange={handleInputChange}
        onBlur={handleBlur}
        onFocus={handleFocus}
        onKeyDown={handleKeyDown}
        disabled={disabled}
        readOnly={readOnly}
        placeholder={placeholder}
      />

      {suffix && <span className="input-number__suffix">{suffix}</span>}

      {controls && controlsPosition === 'right' && (
        <div className="input-number__controls">
          <button
            type="button"
            className="input-number__control input-number__control--up"
            disabled={disabled || readOnly || isAtMax}
            onMouseDown={() => handleMouseDown(increment)}
            tabIndex={-1}
          >
            ▲
          </button>
          <button
            type="button"
            className="input-number__control input-number__control--down"
            disabled={disabled || readOnly || isAtMin}
            onMouseDown={() => handleMouseDown(decrement)}
            tabIndex={-1}
          >
            ▼
          </button>
        </div>
      )}

      {controls && controlsPosition === 'both' && (
        <button
          type="button"
          className="input-number__btn input-number__btn--plus"
          disabled={disabled || readOnly || isAtMax}
          onMouseDown={() => handleMouseDown(increment)}
          tabIndex={-1}
        >
          +
        </button>
      )}
    </div>
  );
}

export default InputNumber;
