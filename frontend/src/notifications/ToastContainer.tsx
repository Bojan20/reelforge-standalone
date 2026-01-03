/**
 * ReelForge Toast Container
 *
 * Container for managing and positioning toasts.
 *
 * @module notifications/ToastContainer
 */

import { Toast } from './Toast';
import type { ToastType, ToastAction } from './Toast';
import './ToastContainer.css';

// ============ Types ============

export interface ToastData {
  id: string;
  type: ToastType;
  title: string;
  message?: string;
  duration?: number;
  showProgress?: boolean;
  actions?: ToastAction[];
}

export type ToastPosition =
  | 'top-left'
  | 'top-center'
  | 'top-right'
  | 'bottom-left'
  | 'bottom-center'
  | 'bottom-right';

export interface ToastContainerProps {
  /** Active toasts */
  toasts: ToastData[];
  /** Position */
  position?: ToastPosition;
  /** On toast dismiss */
  onDismiss: (id: string) => void;
  /** Max visible toasts */
  maxVisible?: number;
}

// ============ Component ============

export function ToastContainer({
  toasts,
  position = 'bottom-right',
  onDismiss,
  maxVisible = 5,
}: ToastContainerProps) {
  // Limit visible toasts
  const visibleToasts = toasts.slice(0, maxVisible);

  // Reverse for bottom positions so newest appears at bottom
  const isBottom = position.startsWith('bottom');
  const orderedToasts = isBottom ? [...visibleToasts].reverse() : visibleToasts;

  return (
    <div className={`toast-container toast-container--${position}`}>
      {orderedToasts.map((toast, index) => (
        <Toast
          key={toast.id}
          {...toast}
          onDismiss={onDismiss}
          index={index}
        />
      ))}
    </div>
  );
}

export default ToastContainer;
