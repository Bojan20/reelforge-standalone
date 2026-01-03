/**
 * ReelForge Notifications Hook
 *
 * State management for toast notifications.
 *
 * @module notifications/useNotifications
 */

import { useState, useCallback, useMemo } from 'react';
import type { ToastType, ToastAction } from './Toast';

// ============ Types ============

export interface Notification {
  id: string;
  type: ToastType;
  title: string;
  message?: string;
  duration?: number;
  showProgress?: boolean;
  actions?: ToastAction[];
  createdAt: number;
}

export interface UseNotificationsOptions {
  /** Maximum notifications to keep in history */
  maxHistory?: number;
}

export interface UseNotificationsReturn {
  /** Active notifications */
  notifications: Notification[];
  /** Notification history */
  history: Notification[];
  /** Show info notification */
  info: (title: string, message?: string, options?: NotificationOptions) => string;
  /** Show success notification */
  success: (title: string, message?: string, options?: NotificationOptions) => string;
  /** Show warning notification */
  warning: (title: string, message?: string, options?: NotificationOptions) => string;
  /** Show error notification */
  error: (title: string, message?: string, options?: NotificationOptions) => string;
  /** Dismiss notification */
  dismiss: (id: string) => void;
  /** Dismiss all notifications */
  dismissAll: () => void;
  /** Clear history */
  clearHistory: () => void;
}

export interface NotificationOptions {
  duration?: number;
  showProgress?: boolean;
  actions?: ToastAction[];
}

// ============ Helpers ============

function generateId(): string {
  return `notif-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

// ============ Hook ============

export function useNotifications(
  options: UseNotificationsOptions = {}
): UseNotificationsReturn {
  const { maxHistory = 50 } = options;

  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [history, setHistory] = useState<Notification[]>([]);

  // Add notification
  const addNotification = useCallback(
    (
      type: ToastType,
      title: string,
      message?: string,
      opts?: NotificationOptions
    ): string => {
      const id = generateId();

      const notification: Notification = {
        id,
        type,
        title,
        message,
        duration: opts?.duration,
        showProgress: opts?.showProgress,
        actions: opts?.actions,
        createdAt: Date.now(),
      };

      setNotifications((prev) => [...prev, notification]);

      return id;
    },
    []
  );

  // Dismiss notification
  const dismiss = useCallback((id: string) => {
    setNotifications((prev) => {
      const notification = prev.find((n) => n.id === id);
      if (notification) {
        // Add to history
        setHistory((h) => {
          const newHistory = [...h, notification];
          if (newHistory.length > maxHistory) {
            return newHistory.slice(-maxHistory);
          }
          return newHistory;
        });
      }
      return prev.filter((n) => n.id !== id);
    });
  }, [maxHistory]);

  // Dismiss all
  const dismissAll = useCallback(() => {
    setNotifications((prev) => {
      // Add all to history
      setHistory((h) => {
        const newHistory = [...h, ...prev];
        if (newHistory.length > maxHistory) {
          return newHistory.slice(-maxHistory);
        }
        return newHistory;
      });
      return [];
    });
  }, [maxHistory]);

  // Clear history
  const clearHistory = useCallback(() => {
    setHistory([]);
  }, []);

  // Convenience methods
  const info = useCallback(
    (title: string, message?: string, opts?: NotificationOptions) =>
      addNotification('info', title, message, opts),
    [addNotification]
  );

  const success = useCallback(
    (title: string, message?: string, opts?: NotificationOptions) =>
      addNotification('success', title, message, opts),
    [addNotification]
  );

  const warning = useCallback(
    (title: string, message?: string, opts?: NotificationOptions) =>
      addNotification('warning', title, message, opts),
    [addNotification]
  );

  const error = useCallback(
    (title: string, message?: string, opts?: NotificationOptions) =>
      addNotification('error', title, message, opts),
    [addNotification]
  );

  return useMemo(
    () => ({
      notifications,
      history,
      info,
      success,
      warning,
      error,
      dismiss,
      dismissAll,
      clearHistory,
    }),
    [
      notifications,
      history,
      info,
      success,
      warning,
      error,
      dismiss,
      dismissAll,
      clearHistory,
    ]
  );
}

export default useNotifications;
