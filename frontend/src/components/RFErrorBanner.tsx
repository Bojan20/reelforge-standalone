/**
 * ReelForge M8.9 Error Banner Component
 *
 * Human-readable error display for UI surfacing.
 * Shows structured error messages without raw stack traces.
 */

import { useState, useEffect, useCallback } from 'react';
import type { RFErrorCode, RFErrorSeverity } from '../core/rfErrors';
import { getErrorDef, logRFError } from '../core/rfErrors';
import './RFErrorBanner.css';

interface RFErrorBannerProps {
  /** Error code to display */
  code: RFErrorCode | null;
  /** Optional additional details */
  details?: string;
  /** Auto-dismiss after ms (0 = manual only) */
  autoDismissMs?: number;
  /** Callback when dismissed */
  onDismiss?: () => void;
}

/**
 * Error banner component for structured RF errors.
 * Displays title, body, and hint in a dismissible banner.
 */
export function RFErrorBanner({
  code,
  details,
  autoDismissMs = 5000,
  onDismiss,
}: RFErrorBannerProps) {
  const [visible, setVisible] = useState(false);
  const [currentCode, setCurrentCode] = useState<RFErrorCode | null>(null);

  useEffect(() => {
    if (code) {
      setCurrentCode(code);
      setVisible(true);
      // Log to console for dev visibility
      logRFError(code, details);
    }
  }, [code, details]);

  // Auto-dismiss timer
  useEffect(() => {
    if (visible && autoDismissMs > 0) {
      const timer = setTimeout(() => {
        handleDismiss();
      }, autoDismissMs);
      return () => clearTimeout(timer);
    }
  }, [visible, autoDismissMs]);

  const handleDismiss = useCallback(() => {
    setVisible(false);
    onDismiss?.();
  }, [onDismiss]);

  if (!visible || !currentCode) {
    return null;
  }

  const errorDef = getErrorDef(currentCode);

  return (
    <div
      className={`rf-error-banner rf-error-banner--${errorDef.severity}`}
      role="alert"
    >
      <div className="rf-error-banner__icon">
        {getSeverityIcon(errorDef.severity)}
      </div>
      <div className="rf-error-banner__content">
        <div className="rf-error-banner__title">
          <span className="rf-error-banner__code">{currentCode}</span>
          <span className="rf-error-banner__title-text">{errorDef.title}</span>
        </div>
        <div className="rf-error-banner__body">{errorDef.body}</div>
        {errorDef.hint && (
          <div className="rf-error-banner__hint">{errorDef.hint}</div>
        )}
        {details && (
          <div className="rf-error-banner__details">{details}</div>
        )}
      </div>
      <button
        className="rf-error-banner__dismiss"
        onClick={handleDismiss}
        aria-label="Dismiss"
      >
        ✕
      </button>
    </div>
  );
}

function getSeverityIcon(severity: RFErrorSeverity): string {
  switch (severity) {
    case 'fatal':
      return '⛔';
    case 'error':
      return '❌';
    case 'warning':
      return '⚠️';
  }
}

// ============ Inline Error Display (for panels) ============

interface InlineErrorProps {
  /** Error message to display (legacy format) */
  message: string | null;
  /** Auto-clear after ms */
  autoClearMs?: number;
  /** Called when error should clear */
  onClear?: () => void;
}

/**
 * Simpler inline error for existing panels.
 * Compatible with legacy RF_ERR: string format.
 */
export function InlineError({
  message,
  autoClearMs = 3000,
  onClear,
}: InlineErrorProps) {
  useEffect(() => {
    if (message && autoClearMs > 0) {
      const timer = setTimeout(() => {
        onClear?.();
      }, autoClearMs);
      return () => clearTimeout(timer);
    }
  }, [message, autoClearMs, onClear]);

  if (!message) {
    return null;
  }

  // Extract code if present (RF_ERR: format)
  const codeMatch = message.match(/RF_ERR[_A-Z]*/);
  const code = codeMatch ? codeMatch[0] : null;

  return (
    <div className="rf-inline-error" role="alert">
      {code && <span className="rf-inline-error__code">{code}</span>}
      <span className="rf-inline-error__message">
        {message.replace(/RF_ERR[_A-Z]*:\s*/g, '')}
      </span>
    </div>
  );
}

// ============ Error Toast Hook ============

interface ErrorToast {
  id: string;
  code: RFErrorCode;
  details?: string;
  timestamp: number;
}

/**
 * Hook for managing error toasts.
 * Stacks multiple errors, auto-dismisses older ones.
 */
export function useErrorToasts(maxToasts = 3) {
  const [toasts, setToasts] = useState<ErrorToast[]>([]);

  const showError = useCallback((code: RFErrorCode, details?: string) => {
    const id = `${code}-${Date.now()}`;
    setToasts((prev) => {
      const next = [...prev, { id, code, details, timestamp: Date.now() }];
      // Limit to max toasts
      return next.slice(-maxToasts);
    });

    // Log to console
    logRFError(code, details);
  }, [maxToasts]);

  const dismissToast = useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  const clearAll = useCallback(() => {
    setToasts([]);
  }, []);

  return {
    toasts,
    showError,
    dismissToast,
    clearAll,
  };
}

// ============ Error Toast Container ============

interface ErrorToastContainerProps {
  toasts: ErrorToast[];
  onDismiss: (id: string) => void;
  autoDismissMs?: number;
}

/**
 * Container for rendering multiple error toasts.
 */
export function ErrorToastContainer({
  toasts,
  onDismiss,
  autoDismissMs = 5000,
}: ErrorToastContainerProps) {
  return (
    <div className="rf-error-toast-container">
      {toasts.map((toast) => (
        <RFErrorBanner
          key={toast.id}
          code={toast.code}
          details={toast.details}
          autoDismissMs={autoDismissMs}
          onDismiss={() => onDismiss(toast.id)}
        />
      ))}
    </div>
  );
}
