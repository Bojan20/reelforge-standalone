/**
 * ReelForge Overlay
 *
 * Overlay component:
 * - Backdrop with blur
 * - Loading overlay
 * - Click to close
 * - Portal rendering
 *
 * @module overlay/Overlay
 */

import { useEffect, useCallback } from 'react';
import { createPortal } from 'react-dom';
import './Overlay.css';

// ============ Types ============

export interface OverlayProps {
  /** Visible state */
  open: boolean;
  /** On close callback */
  onClose?: () => void;
  /** Close on click */
  closeOnClick?: boolean;
  /** Close on escape */
  closeOnEscape?: boolean;
  /** Blur background */
  blur?: boolean;
  /** Opacity (0-1) */
  opacity?: number;
  /** Z-index */
  zIndex?: number;
  /** Children content */
  children?: React.ReactNode;
  /** Custom class */
  className?: string;
}

// ============ Component ============

export function Overlay({
  open,
  onClose,
  closeOnClick = true,
  closeOnEscape = true,
  blur = false,
  opacity,
  zIndex,
  children,
  className = '',
}: OverlayProps) {
  // Handle escape key
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (e.key === 'Escape' && closeOnEscape && onClose) {
        onClose();
      }
    },
    [closeOnEscape, onClose]
  );

  useEffect(() => {
    if (open) {
      document.addEventListener('keydown', handleKeyDown);
      document.body.style.overflow = 'hidden';
    }

    return () => {
      document.removeEventListener('keydown', handleKeyDown);
      document.body.style.overflow = '';
    };
  }, [open, handleKeyDown]);

  if (!open) return null;

  const style: React.CSSProperties = {};
  if (opacity !== undefined) {
    style.backgroundColor = `rgba(0, 0, 0, ${opacity})`;
  }
  if (zIndex !== undefined) {
    style.zIndex = zIndex;
  }

  const overlay = (
    <div
      className={`overlay ${blur ? 'overlay--blur' : ''} ${className}`}
      style={style}
      onClick={closeOnClick && onClose ? onClose : undefined}
      aria-hidden="true"
    >
      {children && (
        <div className="overlay__content" onClick={(e) => e.stopPropagation()}>
          {children}
        </div>
      )}
    </div>
  );

  return createPortal(overlay, document.body);
}

// ============ Loading Overlay ============

export interface LoadingOverlayProps {
  /** Visible state */
  open: boolean;
  /** Loading text */
  text?: string;
  /** Spinner size */
  spinnerSize?: number;
  /** Blur background */
  blur?: boolean;
  /** Target element (null = fullscreen) */
  target?: 'fullscreen' | 'parent';
  /** Custom class */
  className?: string;
}

export function LoadingOverlay({
  open,
  text,
  spinnerSize = 40,
  blur = true,
  target = 'fullscreen',
  className = '',
}: LoadingOverlayProps) {
  if (!open) return null;

  const content = (
    <div
      className={`loading-overlay ${blur ? 'loading-overlay--blur' : ''} ${
        target === 'parent' ? 'loading-overlay--parent' : ''
      } ${className}`}
    >
      <div className="loading-overlay__spinner" style={{ width: spinnerSize, height: spinnerSize }}>
        <svg viewBox="0 0 50 50">
          <circle
            cx="25"
            cy="25"
            r="20"
            fill="none"
            stroke="currentColor"
            strokeWidth="4"
            strokeLinecap="round"
          />
        </svg>
      </div>
      {text && <div className="loading-overlay__text">{text}</div>}
    </div>
  );

  if (target === 'parent') {
    return content;
  }

  return createPortal(content, document.body);
}

// ============ Confirm Overlay ============

export interface ConfirmOverlayProps {
  /** Visible state */
  open: boolean;
  /** Title */
  title: string;
  /** Message */
  message: React.ReactNode;
  /** Confirm button text */
  confirmText?: string;
  /** Cancel button text */
  cancelText?: string;
  /** Confirm button variant */
  confirmVariant?: 'primary' | 'danger';
  /** On confirm */
  onConfirm: () => void;
  /** On cancel */
  onCancel: () => void;
  /** Loading state */
  loading?: boolean;
}

export function ConfirmOverlay({
  open,
  title,
  message,
  confirmText = 'Confirm',
  cancelText = 'Cancel',
  confirmVariant = 'primary',
  onConfirm,
  onCancel,
  loading = false,
}: ConfirmOverlayProps) {
  if (!open) return null;

  return (
    <Overlay open={open} onClose={onCancel} blur>
      <div className="confirm-overlay">
        <div className="confirm-overlay__title">{title}</div>
        <div className="confirm-overlay__message">{message}</div>
        <div className="confirm-overlay__actions">
          <button
            type="button"
            className="confirm-overlay__btn confirm-overlay__btn--cancel"
            onClick={onCancel}
            disabled={loading}
          >
            {cancelText}
          </button>
          <button
            type="button"
            className={`confirm-overlay__btn confirm-overlay__btn--${confirmVariant}`}
            onClick={onConfirm}
            disabled={loading}
          >
            {loading ? 'Loading...' : confirmText}
          </button>
        </div>
      </div>
    </Overlay>
  );
}

export default Overlay;
