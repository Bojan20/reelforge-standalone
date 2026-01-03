/**
 * ReelForge Radio
 *
 * Radio button component:
 * - Single and group
 * - Horizontal/vertical layout
 * - Descriptions
 *
 * @module radio/Radio
 */

import { createContext, useContext } from 'react';
import './Radio.css';

// ============ Types ============

export interface RadioProps {
  /** Value */
  value: string;
  /** Label */
  children: React.ReactNode;
  /** Description */
  description?: React.ReactNode;
  /** Disabled */
  disabled?: boolean;
  /** Custom class */
  className?: string;
}

export interface RadioGroupProps<T = string> {
  /** Selected value */
  value: T;
  /** On change */
  onChange: (value: T) => void;
  /** Name attribute */
  name?: string;
  /** Layout direction */
  direction?: 'horizontal' | 'vertical';
  /** Disabled all */
  disabled?: boolean;
  /** Children radios */
  children: React.ReactNode;
  /** Custom class */
  className?: string;
}

// ============ Context ============

interface RadioContextValue {
  name?: string;
  value: string;
  onChange: (value: string) => void;
  disabled: boolean;
}

const RadioContext = createContext<RadioContextValue | null>(null);

// ============ Radio ============

export function Radio({
  value,
  children,
  description,
  disabled: itemDisabled = false,
  className = '',
}: RadioProps) {
  const context = useContext(RadioContext);

  if (!context) {
    throw new Error('Radio must be used within RadioGroup');
  }

  const { name, value: groupValue, onChange, disabled: groupDisabled } = context;
  const isDisabled = groupDisabled || itemDisabled;
  const isChecked = groupValue === value;

  const handleChange = () => {
    if (!isDisabled) {
      onChange(value);
    }
  };

  return (
    <label
      className={`radio ${isChecked ? 'radio--checked' : ''} ${
        isDisabled ? 'radio--disabled' : ''
      } ${className}`}
    >
      <input
        type="radio"
        name={name}
        value={value}
        checked={isChecked}
        onChange={handleChange}
        disabled={isDisabled}
        className="radio__input"
      />
      <span className="radio__indicator" />
      <span className="radio__content">
        <span className="radio__label">{children}</span>
        {description && <span className="radio__description">{description}</span>}
      </span>
    </label>
  );
}

// ============ RadioGroup ============

export function RadioGroup<T extends string = string>({
  value,
  onChange,
  name,
  direction = 'vertical',
  disabled = false,
  children,
  className = '',
}: RadioGroupProps<T>) {
  return (
    <RadioContext.Provider
      value={{
        name,
        value: value as string,
        onChange: onChange as (v: string) => void,
        disabled,
      }}
    >
      <div
        className={`radio-group radio-group--${direction} ${className}`}
        role="radiogroup"
      >
        {children}
      </div>
    </RadioContext.Provider>
  );
}

export default Radio;
