/**
 * Plugin Button Component
 *
 * @module plugin-ui/controls/PluginButton
 */

import { memo } from 'react';
import { usePluginTheme } from '../usePluginTheme';
import './PluginButton.css';

export interface PluginButtonProps {
  /** Button label */
  children: React.ReactNode;
  /** Click handler */
  onClick?: () => void;
  /** Button variant */
  variant?: 'default' | 'primary' | 'danger' | 'ghost';
  /** Button size */
  size?: 'small' | 'medium' | 'large';
  /** Active/pressed state */
  active?: boolean;
  /** Disabled state */
  disabled?: boolean;
  /** Full width */
  fullWidth?: boolean;
  /** Custom class */
  className?: string;
  /** Button type */
  type?: 'button' | 'submit' | 'reset';
}

function PluginButtonInner({
  children,
  onClick,
  variant = 'default',
  size = 'medium',
  active = false,
  disabled = false,
  fullWidth = false,
  className,
  type = 'button',
}: PluginButtonProps) {
  const theme = usePluginTheme();

  const getBackground = () => {
    if (disabled) return theme.bgControl;
    if (active) return theme.accent;
    switch (variant) {
      case 'primary': return theme.accent;
      case 'danger': return theme.error;
      case 'ghost': return 'transparent';
      default: return theme.bgControl;
    }
  };

  const getColor = () => {
    if (disabled) return theme.textDisabled;
    if (active || variant === 'primary' || variant === 'danger') return '#ffffff';
    return theme.textPrimary;
  };

  const getBorder = () => {
    if (variant === 'ghost') return `1px solid ${theme.border}`;
    return 'none';
  };

  return (
    <button
      type={type}
      className={`plugin-button plugin-button--${variant} plugin-button--${size} ${active ? 'active' : ''} ${fullWidth ? 'full-width' : ''} ${className ?? ''}`}
      onClick={onClick}
      disabled={disabled}
      style={{
        background: getBackground(),
        color: getColor(),
        border: getBorder(),
      }}
    >
      {children}
    </button>
  );
}

export const PluginButton = memo(PluginButtonInner);
export default PluginButton;
