/**
 * Plugin Select Component
 *
 * @module plugin-ui/controls/PluginSelect
 */

import { memo } from 'react';
import { usePluginTheme } from '../usePluginTheme';
import './PluginSelect.css';

export interface SelectOption {
  value: string;
  label: string;
  disabled?: boolean;
}

export interface PluginSelectProps {
  /** Current value */
  value: string;
  /** Options */
  options: SelectOption[];
  /** Change handler */
  onChange: (value: string) => void;
  /** Label text */
  label?: string;
  /** Placeholder */
  placeholder?: string;
  /** Disabled state */
  disabled?: boolean;
  /** Size */
  size?: 'small' | 'medium';
  /** Full width */
  fullWidth?: boolean;
  /** Custom class */
  className?: string;
}

function PluginSelectInner({
  value,
  options,
  onChange,
  label,
  placeholder = 'Select...',
  disabled = false,
  size = 'medium',
  fullWidth = false,
  className,
}: PluginSelectProps) {
  const theme = usePluginTheme();

  const handleChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    onChange(e.target.value);
  };

  return (
    <div
      className={`plugin-select plugin-select--${size} ${fullWidth ? 'full-width' : ''} ${className ?? ''}`}
    >
      {label && (
        <label
          className="plugin-select__label"
          style={{ color: theme.textSecondary }}
        >
          {label}
        </label>
      )}
      <div className="plugin-select__wrapper">
        <select
          value={value}
          onChange={handleChange}
          disabled={disabled}
          className="plugin-select__input"
          style={{
            background: theme.bgControl,
            color: theme.textPrimary,
            borderColor: theme.border,
          }}
        >
          {placeholder && !value && (
            <option value="" disabled>
              {placeholder}
            </option>
          )}
          {options.map((opt) => (
            <option key={opt.value} value={opt.value} disabled={opt.disabled}>
              {opt.label}
            </option>
          ))}
        </select>
        <div className="plugin-select__arrow" style={{ color: theme.textSecondary }}>
          ▼
        </div>
      </div>
    </div>
  );
}

export const PluginSelect = memo(PluginSelectInner);
export default PluginSelect;
