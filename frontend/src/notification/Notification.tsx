/**
 * ReelForge Notification
 *
 * Toast notification system:
 * - Auto dismiss
 * - Stacking
 * - Actions
 * - Positions
 *
 * @module notification/Notification
 */

import { useState, useEffect, useCallback, createContext, useContext } from 'react';
import { createPortal } from 'react-dom';
import './Notification.css';

// ============ Types ============

export type NotificationType = 'info' | 'success' | 'warning' | 'error';
export type NotificationPosition =
  | 'top-left'
  | 'top-center'
  | 'top-right'
  | 'bottom-left'
  | 'bottom-center'
  | 'bottom-right';

export interface NotificationData {
  /** Unique id */
  id: string;
  /** Type */
  type: NotificationType;
  /** Title */
  title?: React.ReactNode;
  /** Message */
  message: React.ReactNode;
  /** Duration in ms (0 = no auto dismiss) */
  duration?: number;
  /** Show close button */
  closable?: boolean;
  /** Action button */
  action?: {
    label: string;
    onClick: () => void;
  };
}

export interface NotificationProps extends NotificationData {
  /** On close */
  onClose: () => void;
}

// ============ Icons ============

const ICONS: Record<NotificationType, React.ReactNode> = {
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

// ============ Single Notification ============

export function Notification({
  type,
  title,
  message,
  duration = 5000,
  closable = true,
  action,
  onClose,
}: NotificationProps) {
  const [isLeaving, setIsLeaving] = useState(false);

  useEffect(() => {
    if (duration > 0) {
      const timer = setTimeout(() => {
        handleClose();
      }, duration);
      return () => clearTimeout(timer);
    }
  }, [duration]);

  const handleClose = () => {
    setIsLeaving(true);
    setTimeout(onClose, 200);
  };

  return (
    <div
      className={`notification notification--${type} ${isLeaving ? 'notification--leaving' : ''}`}
      role="alert"
    >
      <div className="notification__icon">{ICONS[type]}</div>
      <div className="notification__content">
        {title && <div className="notification__title">{title}</div>}
        <div className="notification__message">{message}</div>
        {action && (
          <button
            type="button"
            className="notification__action"
            onClick={() => {
              action.onClick();
              handleClose();
            }}
          >
            {action.label}
          </button>
        )}
      </div>
      {closable && (
        <button
          type="button"
          className="notification__close"
          onClick={handleClose}
          aria-label="Close"
        >
          ×
        </button>
      )}
    </div>
  );
}

// ============ Notification Container ============

interface NotificationContainerProps {
  notifications: NotificationData[];
  position: NotificationPosition;
  onClose: (id: string) => void;
}

function NotificationContainer({
  notifications,
  position,
  onClose,
}: NotificationContainerProps) {
  if (notifications.length === 0) return null;

  return createPortal(
    <div className={`notification-container notification-container--${position}`}>
      {notifications.map((notification) => (
        <Notification
          key={notification.id}
          {...notification}
          onClose={() => onClose(notification.id)}
        />
      ))}
    </div>,
    document.body
  );
}

// ============ Context & Provider ============

interface NotificationContextValue {
  show: (notification: Omit<NotificationData, 'id'>) => string;
  success: (message: React.ReactNode, title?: React.ReactNode) => string;
  error: (message: React.ReactNode, title?: React.ReactNode) => string;
  warning: (message: React.ReactNode, title?: React.ReactNode) => string;
  info: (message: React.ReactNode, title?: React.ReactNode) => string;
  close: (id: string) => void;
  closeAll: () => void;
}

const NotificationContext = createContext<NotificationContextValue | null>(null);

export interface NotificationProviderProps {
  /** Position */
  position?: NotificationPosition;
  /** Max notifications shown */
  maxCount?: number;
  /** Children */
  children: React.ReactNode;
}

export function NotificationProvider({
  position = 'top-right',
  maxCount = 5,
  children,
}: NotificationProviderProps) {
  const [notifications, setNotifications] = useState<NotificationData[]>([]);

  const generateId = () => Math.random().toString(36).substring(2, 9);

  const show = useCallback(
    (notification: Omit<NotificationData, 'id'>) => {
      const id = generateId();
      setNotifications((prev) => {
        const updated = [...prev, { ...notification, id }];
        return updated.slice(-maxCount);
      });
      return id;
    },
    [maxCount]
  );

  const close = useCallback((id: string) => {
    setNotifications((prev) => prev.filter((n) => n.id !== id));
  }, []);

  const closeAll = useCallback(() => {
    setNotifications([]);
  }, []);

  const success = useCallback(
    (message: React.ReactNode, title?: React.ReactNode) =>
      show({ type: 'success', message, title }),
    [show]
  );

  const error = useCallback(
    (message: React.ReactNode, title?: React.ReactNode) =>
      show({ type: 'error', message, title }),
    [show]
  );

  const warning = useCallback(
    (message: React.ReactNode, title?: React.ReactNode) =>
      show({ type: 'warning', message, title }),
    [show]
  );

  const info = useCallback(
    (message: React.ReactNode, title?: React.ReactNode) =>
      show({ type: 'info', message, title }),
    [show]
  );

  return (
    <NotificationContext.Provider
      value={{ show, success, error, warning, info, close, closeAll }}
    >
      {children}
      <NotificationContainer
        notifications={notifications}
        position={position}
        onClose={close}
      />
    </NotificationContext.Provider>
  );
}

// ============ Hook ============

export function useNotification() {
  const context = useContext(NotificationContext);
  if (!context) {
    throw new Error('useNotification must be used within NotificationProvider');
  }
  return context;
}

export default Notification;
