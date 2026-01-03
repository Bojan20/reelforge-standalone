/**
 * ReelForge Confirm Dialog
 *
 * Confirmation dialog with customizable buttons.
 *
 * @module dialogs/ConfirmDialog
 */

import { Modal } from './Modal';
import './ConfirmDialog.css';

// ============ Types ============

export type ConfirmDialogType = 'info' | 'warning' | 'danger';

export interface ConfirmDialogProps {
  /** Is open */
  isOpen: boolean;
  /** Dialog type */
  type?: ConfirmDialogType;
  /** Title */
  title: string;
  /** Message */
  message: string;
  /** Confirm button text */
  confirmText?: string;
  /** Cancel button text */
  cancelText?: string;
  /** On confirm */
  onConfirm: () => void;
  /** On cancel */
  onCancel: () => void;
  /** Show cancel button */
  showCancel?: boolean;
}

// ============ Constants ============

const TYPE_ICONS: Record<ConfirmDialogType, string> = {
  info: 'ℹ',
  warning: '⚠',
  danger: '⚠',
};

// ============ Component ============

export function ConfirmDialog({
  isOpen,
  type = 'info',
  title,
  message,
  confirmText = 'Confirm',
  cancelText = 'Cancel',
  onConfirm,
  onCancel,
  showCancel = true,
}: ConfirmDialogProps) {
  return (
    <Modal
      isOpen={isOpen}
      onClose={onCancel}
      size="small"
      showClose={false}
      closeOnBackdrop={false}
    >
      <div className={`confirm-dialog confirm-dialog--${type}`}>
        <div className="confirm-dialog__icon">{TYPE_ICONS[type]}</div>
        <div className="confirm-dialog__content">
          <h3 className="confirm-dialog__title">{title}</h3>
          <p className="confirm-dialog__message">{message}</p>
        </div>
        <div className="confirm-dialog__actions">
          {showCancel && (
            <button className="confirm-dialog__btn" onClick={onCancel}>
              {cancelText}
            </button>
          )}
          <button
            className={`confirm-dialog__btn confirm-dialog__btn--${type}`}
            onClick={onConfirm}
          >
            {confirmText}
          </button>
        </div>
      </div>
    </Modal>
  );
}

export default ConfirmDialog;
