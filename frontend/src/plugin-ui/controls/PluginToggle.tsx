/**
 * Plugin Toggle Component
 *
 * @module plugin-ui/controls/PluginToggle
 */

import { memo } from 'react';
import { usePluginTheme } from '../usePluginTheme';
import './PluginToggle.css';

export interface PluginToggleProps {
  /** Current state */
  checked: boolean;
  /** Change handler */
  onChange: (checked: boolean) => void;
  /** Label text */
  label?: string;
  /** Disabled state */
  disabled?: boolean;
  /** Size */
  size?: 'small' | 'medium';
  /** Custom class */
  className?: string;
}

function PluginToggleInner({
  checked,
  onChange,
  label,
  disabled = false,
  size = 'medium',
  className,
}: PluginToggleProps) {
  const theme = usePluginTheme();

  const handleClick = () => {
    if (!disabled) {
      onChange(!checked);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === ' ' || e.key === 'Enter') {
      e.preventDefault();
      handleClick();
    }
  };

  return (
    <div
      className={`plugin-toggle plugin-toggle--${size} ${checked ? 'checked' : ''} ${disabled ? 'disabled' : ''} ${className ?? ''}`}
      onClick={handleClick}
      onKeyDown={handleKeyDown}
      role="switch"
      aria-checked={checked}
      aria-label={label}
      tabIndex={disabled ? -1 : 0}
    >
      <div
        className="plugin-toggle__track"
        style={{
          background: checked ? theme.accent : theme.bgControl,
          borderColor: checked ? theme.accent : theme.border,
        }}
      >
        <div
          className="plugin-toggle__thumb"
          style={{
            background: checked ? '#ffffff' : theme.textSecondary,
          }}
        />
      </div>
      {label && (
        <span
          className="plugin-toggle__label"
          style={{ color: disabled ? theme.textDisabled : theme.textPrimary }}
        >
          {label}
        </span>
      )}
    </div>
  );
}

export const PluginToggle = memo(PluginToggleInner);
export default PluginToggle;
