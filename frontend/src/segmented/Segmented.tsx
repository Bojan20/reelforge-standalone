/**
 * ReelForge Segmented Control
 *
 * Segmented control component:
 * - Single selection
 * - Icons and labels
 * - Animated indicator
 * - Disabled options
 *
 * @module segmented/Segmented
 */

import { useRef, useState, useEffect } from 'react';
import './Segmented.css';

// ============ Types ============

export interface SegmentedOption<T = string> {
  /** Option value */
  value: T;
  /** Display label */
  label: React.ReactNode;
  /** Icon */
  icon?: React.ReactNode;
  /** Disabled */
  disabled?: boolean;
}

export interface SegmentedProps<T = string> {
  /** Options */
  options: SegmentedOption<T>[];
  /** Selected value */
  value: T;
  /** On change */
  onChange: (value: T) => void;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Block (full width) */
  block?: boolean;
  /** Disabled */
  disabled?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Component ============

export function Segmented<T = string>({
  options,
  value,
  onChange,
  size = 'medium',
  block = false,
  disabled = false,
  className = '',
}: SegmentedProps<T>) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [indicatorStyle, setIndicatorStyle] = useState<React.CSSProperties>({});

  // Update indicator position
  useEffect(() => {
    if (!containerRef.current) return;

    const selectedIndex = options.findIndex((opt) => opt.value === value);
    if (selectedIndex === -1) return;

    const buttons = containerRef.current.querySelectorAll('.segmented__option');
    const selectedButton = buttons[selectedIndex] as HTMLElement;

    if (selectedButton) {
      setIndicatorStyle({
        width: selectedButton.offsetWidth,
        transform: `translateX(${selectedButton.offsetLeft}px)`,
      });
    }
  }, [value, options]);

  return (
    <div
      ref={containerRef}
      className={`segmented segmented--${size} ${block ? 'segmented--block' : ''} ${
        disabled ? 'segmented--disabled' : ''
      } ${className}`}
      role="radiogroup"
    >
      {/* Animated indicator */}
      <div className="segmented__indicator" style={indicatorStyle} />

      {/* Options */}
      {options.map((option) => {
        const isSelected = option.value === value;
        const isDisabled = disabled || option.disabled;

        return (
          <button
            key={String(option.value)}
            type="button"
            className={`segmented__option ${isSelected ? 'segmented__option--selected' : ''} ${
              isDisabled ? 'segmented__option--disabled' : ''
            }`}
            onClick={() => !isDisabled && onChange(option.value)}
            disabled={isDisabled}
            role="radio"
            aria-checked={isSelected}
          >
            {option.icon && <span className="segmented__icon">{option.icon}</span>}
            {option.label && <span className="segmented__label">{option.label}</span>}
          </button>
        );
      })}
    </div>
  );
}

export default Segmented;
