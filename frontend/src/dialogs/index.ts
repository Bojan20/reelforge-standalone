/**
 * ReelForge Dialogs Module
 *
 * Modal dialogs and confirmations.
 *
 * @module dialogs
 */

export { Modal } from './Modal';
export type { ModalProps } from './Modal';

export { ConfirmDialog } from './ConfirmDialog';
export type { ConfirmDialogProps, ConfirmDialogType } from './ConfirmDialog';

export { useDialog } from './useDialog';
export type {
  UseDialogReturn,
  DialogState,
  ConfirmOptions,
  AlertOptions,
} from './useDialog';
