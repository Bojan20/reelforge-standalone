/**
 * ReelForge Toggle
 *
 * Toggle/switch component:
 * - On/off states
 * - Labels
 * - Icons
 * - Sizes
 * - Keyboard accessible
 *
 * @module toggle/Toggle
 */

import { useCallback } from 'react';
import './Toggle.css';

// ============ Types ============

export interface ToggleProps {
  /** Checked state */
  checked: boolean;
  /** On change */
  onChange: (checked: boolean) => void;
  /** Label */
  label?: string;
  /** Label position */
  labelPosition?: 'left' | 'right';
  /** On icon/text */
  onContent?: React.ReactNode;
  /** Off icon/text */
  offContent?: React.ReactNode;
  /** Disabled */
  disabled?: boolean;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Variant */
  variant?: 'default' | 'success' | 'warning' | 'danger';
  /** Custom class */
  className?: string;
}

// ============ Component ============

export function Toggle({
  checked,
  onChange,
  label,
  labelPosition = 'right',
  onContent,
  offContent,
  disabled = false,
  size = 'medium',
  variant = 'default',
  className = '',
}: ToggleProps) {
  const handleClick = useCallback(() => {
    if (!disabled) {
      onChange(!checked);
    }
  }, [disabled, checked, onChange]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (disabled) return;

      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        onChange(!checked);
      }
    },
    [disabled, checked, onChange]
  );

  return (
    <div
      className={`toggle toggle--${size} toggle--${variant} ${
        checked ? 'toggle--checked' : ''
      } ${disabled ? 'toggle--disabled' : ''} ${
        labelPosition === 'left' ? 'toggle--label-left' : ''
      } ${className}`}
      onClick={handleClick}
      onKeyDown={handleKeyDown}
      tabIndex={disabled ? -1 : 0}
      role="switch"
      aria-checked={checked}
      aria-disabled={disabled}
    >
      {/* Label (left) */}
      {label && labelPosition === 'left' && (
        <span className="toggle__label">{label}</span>
      )}

      {/* Track */}
      <div className="toggle__track">
        {/* Content indicators */}
        {(onContent || offContent) && (
          <>
            <span className="toggle__content toggle__content--on">
              {onContent}
            </span>
            <span className="toggle__content toggle__content--off">
              {offContent}
            </span>
          </>
        )}

        {/* Thumb */}
        <div className="toggle__thumb" />
      </div>

      {/* Label (right) */}
      {label && labelPosition === 'right' && (
        <span className="toggle__label">{label}</span>
      )}
    </div>
  );
}

// ============ Toggle Group ============

export interface ToggleGroupOption {
  value: string;
  label: string;
  icon?: React.ReactNode;
  disabled?: boolean;
}

export interface ToggleGroupProps {
  /** Options */
  options: ToggleGroupOption[];
  /** Selected value */
  value: string;
  /** On change */
  onChange: (value: string) => void;
  /** Disabled */
  disabled?: boolean;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Custom class */
  className?: string;
}

export function ToggleGroup({
  options,
  value,
  onChange,
  disabled = false,
  size = 'medium',
  className = '',
}: ToggleGroupProps) {
  return (
    <div
      className={`toggle-group toggle-group--${size} ${
        disabled ? 'toggle-group--disabled' : ''
      } ${className}`}
      role="radiogroup"
    >
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          className={`toggle-group__option ${
            value === option.value ? 'toggle-group__option--active' : ''
          } ${option.disabled ? 'toggle-group__option--disabled' : ''}`}
          onClick={() => !option.disabled && onChange(option.value)}
          disabled={disabled || option.disabled}
          role="radio"
          aria-checked={value === option.value}
        >
          {option.icon && (
            <span className="toggle-group__icon">{option.icon}</span>
          )}
          <span className="toggle-group__label">{option.label}</span>
        </button>
      ))}
    </div>
  );
}

export default Toggle;
