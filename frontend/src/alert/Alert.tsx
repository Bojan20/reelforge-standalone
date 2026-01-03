/**
 * ReelForge Alert
 *
 * Alert component:
 * - Info, success, warning, error types
 * - Dismissible
 * - Title and description
 * - Actions
 * - Icons
 *
 * @module alert/Alert
 */

import { useState } from 'react';
import './Alert.css';

// ============ Types ============

export type AlertType = 'info' | 'success' | 'warning' | 'error';

export interface AlertProps {
  /** Alert type */
  type?: AlertType;
  /** Title */
  title?: React.ReactNode;
  /** Description/content */
  children: React.ReactNode;
  /** Custom icon */
  icon?: React.ReactNode;
  /** Show icon */
  showIcon?: boolean;
  /** Dismissible */
  closable?: boolean;
  /** On close */
  onClose?: () => void;
  /** Actions */
  actions?: React.ReactNode;
  /** Outlined style */
  outlined?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Icons ============

const ICONS: Record<AlertType, React.ReactNode> = {
  info: (
    <svg viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z" />
    </svg>
  ),
  success: (
    <svg viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z" />
    </svg>
  ),
  warning: (
    <svg viewBox="0 0 24 24" fill="currentColor">
      <path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z" />
    </svg>
  ),
  error: (
    <svg viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z" />
    </svg>
  ),
};

// ============ Component ============

export function Alert({
  type = 'info',
  title,
  children,
  icon,
  showIcon = true,
  closable = false,
  onClose,
  actions,
  outlined = false,
  className = '',
}: AlertProps) {
  const [isVisible, setIsVisible] = useState(true);

  const handleClose = () => {
    setIsVisible(false);
    onClose?.();
  };

  if (!isVisible) return null;

  return (
    <div
      className={`alert alert--${type} ${outlined ? 'alert--outlined' : ''} ${className}`}
      role="alert"
    >
      {/* Icon */}
      {showIcon && (
        <span className="alert__icon">{icon || ICONS[type]}</span>
      )}

      {/* Content */}
      <div className="alert__content">
        {title && <div className="alert__title">{title}</div>}
        <div className="alert__description">{children}</div>
        {actions && <div className="alert__actions">{actions}</div>}
      </div>

      {/* Close button */}
      {closable && (
        <button
          type="button"
          className="alert__close"
          onClick={handleClose}
          aria-label="Close"
        >
          ×
        </button>
      )}
    </div>
  );
}

export default Alert;
