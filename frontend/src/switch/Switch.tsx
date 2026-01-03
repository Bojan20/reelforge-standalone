/**
 * ReelForge Switch
 *
 * Toggle switch component:
 * - On/off states
 * - Labels
 * - Loading state
 *
 * @module switch/Switch
 */

import './Switch.css';

// ============ Types ============

export interface SwitchProps {
  /** Checked state */
  checked: boolean;
  /** On change */
  onChange: (checked: boolean) => void;
  /** Label */
  label?: React.ReactNode;
  /** Label position */
  labelPosition?: 'left' | 'right';
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Disabled */
  disabled?: boolean;
  /** Loading */
  loading?: boolean;
  /** On text (inside switch) */
  onText?: string;
  /** Off text (inside switch) */
  offText?: string;
  /** Custom class */
  className?: string;
}

// ============ Component ============

export function Switch({
  checked,
  onChange,
  label,
  labelPosition = 'right',
  size = 'medium',
  disabled = false,
  loading = false,
  onText,
  offText,
  className = '',
}: SwitchProps) {
  const handleChange = () => {
    if (!disabled && !loading) {
      onChange(!checked);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      handleChange();
    }
  };

  const showText = onText || offText;

  return (
    <label
      className={`switch switch--${size} ${checked ? 'switch--checked' : ''} ${
        disabled ? 'switch--disabled' : ''
      } ${loading ? 'switch--loading' : ''} ${className}`}
    >
      {label && labelPosition === 'left' && (
        <span className="switch__label">{label}</span>
      )}

      <span
        className="switch__track"
        role="switch"
        aria-checked={checked}
        tabIndex={disabled ? -1 : 0}
        onClick={handleChange}
        onKeyDown={handleKeyDown}
      >
        {showText && (
          <span className="switch__text">
            {checked ? onText : offText}
          </span>
        )}
        <span className="switch__thumb">
          {loading && (
            <span className="switch__spinner" />
          )}
        </span>
      </span>

      {label && labelPosition === 'right' && (
        <span className="switch__label">{label}</span>
      )}

      <input
        type="checkbox"
        checked={checked}
        onChange={handleChange}
        disabled={disabled}
        className="switch__input"
      />
    </label>
  );
}

export default Switch;
