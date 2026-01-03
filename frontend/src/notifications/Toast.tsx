/**
 * ReelForge Toast Notification
 *
 * Toast notification component:
 * - Multiple types (info, success, warning, error)
 * - Auto-dismiss
 * - Manual dismiss
 * - Progress bar
 * - Actions
 *
 * @module notifications/Toast
 */

import { useEffect, useState, useCallback } from 'react';
import './Toast.css';

// ============ Types ============

export type ToastType = 'info' | 'success' | 'warning' | 'error';

export interface ToastAction {
  label: string;
  onClick: () => void;
}

export interface ToastProps {
  /** Unique ID */
  id: string;
  /** Toast type */
  type?: ToastType;
  /** Title */
  title: string;
  /** Message */
  message?: string;
  /** Auto dismiss duration (ms), 0 for no auto-dismiss */
  duration?: number;
  /** Show progress bar */
  showProgress?: boolean;
  /** Actions */
  actions?: ToastAction[];
  /** On dismiss */
  onDismiss: (id: string) => void;
  /** Position in stack */
  index?: number;
}

// ============ Constants ============

const TYPE_ICONS: Record<ToastType, string> = {
  info: 'ℹ',
  success: '✓',
  warning: '⚠',
  error: '✕',
};

const DEFAULT_DURATIONS: Record<ToastType, number> = {
  info: 4000,
  success: 3000,
  warning: 5000,
  error: 0, // No auto-dismiss for errors
};

// ============ Component ============

export function Toast({
  id,
  type = 'info',
  title,
  message,
  duration,
  showProgress = true,
  actions,
  onDismiss,
  index = 0,
}: ToastProps) {
  const [isExiting, setIsExiting] = useState(false);
  const [progress, setProgress] = useState(100);

  const actualDuration = duration ?? DEFAULT_DURATIONS[type];

  // Handle dismiss
  const handleDismiss = useCallback(() => {
    setIsExiting(true);
    setTimeout(() => {
      onDismiss(id);
    }, 200); // Match CSS animation duration
  }, [id, onDismiss]);

  // Auto-dismiss timer
  useEffect(() => {
    if (actualDuration <= 0) return;

    const startTime = Date.now();
    const endTime = startTime + actualDuration;

    const updateProgress = () => {
      const now = Date.now();
      const remaining = endTime - now;

      if (remaining <= 0) {
        handleDismiss();
        return;
      }

      setProgress((remaining / actualDuration) * 100);
      requestAnimationFrame(updateProgress);
    };

    const animationId = requestAnimationFrame(updateProgress);

    return () => {
      cancelAnimationFrame(animationId);
    };
  }, [actualDuration, handleDismiss]);

  return (
    <div
      className={`toast toast--${type} ${isExiting ? 'toast--exiting' : ''}`}
      style={{ '--toast-index': index } as React.CSSProperties}
      role="alert"
    >
      {/* Icon */}
      <div className="toast__icon">{TYPE_ICONS[type]}</div>

      {/* Content */}
      <div className="toast__content">
        <div className="toast__title">{title}</div>
        {message && <div className="toast__message">{message}</div>}

        {/* Actions */}
        {actions && actions.length > 0 && (
          <div className="toast__actions">
            {actions.map((action, i) => (
              <button
                key={i}
                className="toast__action"
                onClick={() => {
                  action.onClick();
                  handleDismiss();
                }}
              >
                {action.label}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Dismiss button */}
      <button className="toast__dismiss" onClick={handleDismiss} title="Dismiss">
        ×
      </button>

      {/* Progress bar */}
      {showProgress && actualDuration > 0 && (
        <div className="toast__progress">
          <div
            className="toast__progress-bar"
            style={{ width: `${progress}%` }}
          />
        </div>
      )}
    </div>
  );
}

export default Toast;
