/**
 * ReelForge Checkbox
 *
 * Checkbox component:
 * - Checked/unchecked/indeterminate
 * - Description support
 * - Group support
 *
 * @module checkbox/Checkbox
 */

import { useRef, useEffect } from 'react';
import './Checkbox.css';

// ============ Types ============

export interface CheckboxProps {
  /** Checked state */
  checked: boolean;
  /** On change */
  onChange: (checked: boolean) => void;
  /** Indeterminate state */
  indeterminate?: boolean;
  /** Label */
  children?: React.ReactNode;
  /** Description */
  description?: React.ReactNode;
  /** Disabled */
  disabled?: boolean;
  /** Custom class */
  className?: string;
}

export interface CheckboxGroupProps {
  /** Selected values */
  value: string[];
  /** On change */
  onChange: (value: string[]) => void;
  /** Direction */
  direction?: 'horizontal' | 'vertical';
  /** Disabled all */
  disabled?: boolean;
  /** Children */
  children: React.ReactNode;
  /** Custom class */
  className?: string;
}

// ============ Checkbox ============

export function Checkbox({
  checked,
  onChange,
  indeterminate = false,
  children,
  description,
  disabled = false,
  className = '',
}: CheckboxProps) {
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (inputRef.current) {
      inputRef.current.indeterminate = indeterminate;
    }
  }, [indeterminate]);

  const handleChange = () => {
    if (!disabled) {
      onChange(!checked);
    }
  };

  return (
    <label
      className={`checkbox ${checked ? 'checkbox--checked' : ''} ${
        indeterminate ? 'checkbox--indeterminate' : ''
      } ${disabled ? 'checkbox--disabled' : ''} ${className}`}
    >
      <input
        ref={inputRef}
        type="checkbox"
        checked={checked}
        onChange={handleChange}
        disabled={disabled}
        className="checkbox__input"
      />
      <span className="checkbox__indicator">
        {checked && !indeterminate && (
          <svg viewBox="0 0 24 24" fill="currentColor">
            <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z" />
          </svg>
        )}
        {indeterminate && (
          <svg viewBox="0 0 24 24" fill="currentColor">
            <path d="M19 13H5v-2h14v2z" />
          </svg>
        )}
      </span>
      {(children || description) && (
        <span className="checkbox__content">
          {children && <span className="checkbox__label">{children}</span>}
          {description && <span className="checkbox__description">{description}</span>}
        </span>
      )}
    </label>
  );
}

// ============ Checkbox Item (for group) ============

export interface CheckboxItemProps {
  /** Value */
  value: string;
  /** Label */
  children: React.ReactNode;
  /** Description */
  description?: React.ReactNode;
  /** Disabled */
  disabled?: boolean;
}

// ============ Checkbox Group ============

export function CheckboxGroup({
  direction = 'vertical',
  children,
  className = '',
}: CheckboxGroupProps) {
  return (
    <div
      className={`checkbox-group checkbox-group--${direction} ${className}`}
      role="group"
    >
      {children}
    </div>
  );
}

export default Checkbox;
