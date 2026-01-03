/**
 * ReelForge Drawer
 *
 * Drawer/sidebar component:
 * - Left, right, top, bottom positions
 * - Overlay backdrop
 * - Slide animation
 * - Close on escape/overlay click
 *
 * @module drawer/Drawer
 */

import { useEffect, useCallback } from 'react';
import { createPortal } from 'react-dom';
import './Drawer.css';

// ============ Types ============

export type DrawerPlacement = 'left' | 'right' | 'top' | 'bottom';
export type DrawerSize = 'small' | 'medium' | 'large' | 'full';

export interface DrawerProps {
  /** Open state */
  open: boolean;
  /** On close callback */
  onClose: () => void;
  /** Placement */
  placement?: DrawerPlacement;
  /** Size */
  size?: DrawerSize;
  /** Custom width/height (overrides size) */
  customSize?: number | string;
  /** Title */
  title?: React.ReactNode;
  /** Show close button */
  showClose?: boolean;
  /** Close on overlay click */
  closeOnOverlay?: boolean;
  /** Close on escape */
  closeOnEscape?: boolean;
  /** Show overlay */
  overlay?: boolean;
  /** Footer content */
  footer?: React.ReactNode;
  /** Children content */
  children: React.ReactNode;
  /** Custom class */
  className?: string;
}

// ============ Size Map ============

const SIZES: Record<DrawerPlacement, Record<DrawerSize, string>> = {
  left: { small: '280px', medium: '380px', large: '520px', full: '100%' },
  right: { small: '280px', medium: '380px', large: '520px', full: '100%' },
  top: { small: '200px', medium: '300px', large: '400px', full: '100%' },
  bottom: { small: '200px', medium: '300px', large: '400px', full: '100%' },
};

// ============ Component ============

export function Drawer({
  open,
  onClose,
  placement = 'right',
  size = 'medium',
  customSize,
  title,
  showClose = true,
  closeOnOverlay = true,
  closeOnEscape = true,
  overlay = true,
  footer,
  children,
  className = '',
}: DrawerProps) {
  // Handle escape key
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (e.key === 'Escape' && closeOnEscape) {
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

  const sizeValue = customSize
    ? typeof customSize === 'number'
      ? `${customSize}px`
      : customSize
    : SIZES[placement][size];

  const drawerStyle: React.CSSProperties = {};
  if (placement === 'left' || placement === 'right') {
    drawerStyle.width = sizeValue;
  } else {
    drawerStyle.height = sizeValue;
  }

  const drawer = (
    <div className="drawer-container">
      {/* Overlay */}
      {overlay && (
        <div
          className="drawer__overlay"
          onClick={closeOnOverlay ? onClose : undefined}
          aria-hidden="true"
        />
      )}

      {/* Drawer panel */}
      <div
        className={`drawer drawer--${placement} ${className}`}
        style={drawerStyle}
        role="dialog"
        aria-modal="true"
      >
        {/* Header */}
        {(title || showClose) && (
          <div className="drawer__header">
            {title && <div className="drawer__title">{title}</div>}
            {showClose && (
              <button
                type="button"
                className="drawer__close"
                onClick={onClose}
                aria-label="Close"
              >
                ×
              </button>
            )}
          </div>
        )}

        {/* Body */}
        <div className="drawer__body">{children}</div>

        {/* Footer */}
        {footer && <div className="drawer__footer">{footer}</div>}
      </div>
    </div>
  );

  return createPortal(drawer, document.body);
}

export default Drawer;
