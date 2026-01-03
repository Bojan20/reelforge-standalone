/**
 * ReelForge Dialog Hook
 *
 * Imperative dialog API.
 *
 * @module dialogs/useDialog
 */

import { useState, useCallback, useMemo } from 'react';
import type { ConfirmDialogType } from './ConfirmDialog';

// ============ Types ============

export interface DialogState {
  isOpen: boolean;
  type: ConfirmDialogType;
  title: string;
  message: string;
  confirmText: string;
  cancelText: string;
  showCancel: boolean;
  resolve: ((value: boolean) => void) | null;
}

export interface UseDialogReturn {
  /** Dialog state */
  state: DialogState;
  /** Show confirm dialog */
  confirm: (options: ConfirmOptions) => Promise<boolean>;
  /** Show alert dialog */
  alert: (options: AlertOptions) => Promise<void>;
  /** Handle confirm action */
  handleConfirm: () => void;
  /** Handle cancel action */
  handleCancel: () => void;
}

export interface ConfirmOptions {
  type?: ConfirmDialogType;
  title: string;
  message: string;
  confirmText?: string;
  cancelText?: string;
}

export interface AlertOptions {
  type?: ConfirmDialogType;
  title: string;
  message: string;
  buttonText?: string;
}

// ============ Hook ============

export function useDialog(): UseDialogReturn {
  const [state, setState] = useState<DialogState>({
    isOpen: false,
    type: 'info',
    title: '',
    message: '',
    confirmText: 'Confirm',
    cancelText: 'Cancel',
    showCancel: true,
    resolve: null,
  });

  // Show confirm dialog
  const confirm = useCallback((options: ConfirmOptions): Promise<boolean> => {
    return new Promise((resolve) => {
      setState({
        isOpen: true,
        type: options.type || 'info',
        title: options.title,
        message: options.message,
        confirmText: options.confirmText || 'Confirm',
        cancelText: options.cancelText || 'Cancel',
        showCancel: true,
        resolve,
      });
    });
  }, []);

  // Show alert dialog
  const alert = useCallback((options: AlertOptions): Promise<void> => {
    return new Promise((resolve) => {
      setState({
        isOpen: true,
        type: options.type || 'info',
        title: options.title,
        message: options.message,
        confirmText: options.buttonText || 'OK',
        cancelText: 'Cancel',
        showCancel: false,
        resolve: () => resolve(),
      });
    });
  }, []);

  // Handle confirm
  const handleConfirm = useCallback(() => {
    state.resolve?.(true);
    setState((prev) => ({ ...prev, isOpen: false, resolve: null }));
  }, [state.resolve]);

  // Handle cancel
  const handleCancel = useCallback(() => {
    state.resolve?.(false);
    setState((prev) => ({ ...prev, isOpen: false, resolve: null }));
  }, [state.resolve]);

  return useMemo(
    () => ({
      state,
      confirm,
      alert,
      handleConfirm,
      handleCancel,
    }),
    [state, confirm, alert, handleConfirm, handleCancel]
  );
}

export default useDialog;
