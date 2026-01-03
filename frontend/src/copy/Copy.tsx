/**
 * ReelForge Copy
 *
 * Copy to clipboard utilities:
 * - useCopy hook
 * - CopyButton component
 * - CopyToClipboard wrapper
 * - Copy feedback
 *
 * @module copy/Copy
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import './Copy.css';

// ============ Types ============

export interface UseCopyOptions {
  /** Success message duration (ms) */
  successDuration?: number;
  /** Callback on copy success */
  onSuccess?: (text: string) => void;
  /** Callback on copy error */
  onError?: (error: Error) => void;
}

export interface UseCopyResult {
  /** Copy function */
  copy: (text: string) => Promise<boolean>;
  /** Copy state */
  copied: boolean;
  /** Error if copy failed */
  error: Error | null;
  /** Reset copied state */
  reset: () => void;
}

export interface CopyButtonProps {
  /** Text to copy */
  text: string;
  /** Button label */
  label?: string;
  /** Copied label */
  copiedLabel?: string;
  /** Success duration (ms) */
  successDuration?: number;
  /** Callback on copy */
  onCopy?: (text: string) => void;
  /** Show icon */
  showIcon?: boolean;
  /** Button size */
  size?: 'small' | 'medium' | 'large';
  /** Button variant */
  variant?: 'default' | 'ghost' | 'outline';
  /** Disabled state */
  disabled?: boolean;
  /** Custom class */
  className?: string;
}

export interface CopyToClipboardProps {
  /** Text to copy */
  text: string;
  /** Children (render prop or element) */
  children:
    | React.ReactNode
    | ((props: { copy: () => void; copied: boolean }) => React.ReactNode);
  /** Callback on copy */
  onCopy?: (text: string) => void;
  /** Success duration */
  successDuration?: number;
}

// ============ Hook ============

export function useCopy({
  successDuration = 2000,
  onSuccess,
  onError,
}: UseCopyOptions = {}): UseCopyResult {
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const reset = useCallback(() => {
    setCopied(false);
    setError(null);
  }, []);

  const copy = useCallback(
    async (text: string): Promise<boolean> => {
      // Clear previous timeout
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }

      try {
        // Modern Clipboard API
        if (navigator.clipboard && navigator.clipboard.writeText) {
          await navigator.clipboard.writeText(text);
        } else {
          // Fallback for older browsers
          const textarea = document.createElement('textarea');
          textarea.value = text;
          textarea.style.position = 'fixed';
          textarea.style.left = '-9999px';
          textarea.style.top = '-9999px';
          document.body.appendChild(textarea);
          textarea.focus();
          textarea.select();

          const success = document.execCommand('copy');
          document.body.removeChild(textarea);

          if (!success) {
            throw new Error('Copy command failed');
          }
        }

        setCopied(true);
        setError(null);
        onSuccess?.(text);

        // Auto reset after duration
        timeoutRef.current = setTimeout(() => {
          setCopied(false);
        }, successDuration);

        return true;
      } catch (err) {
        const error = err instanceof Error ? err : new Error('Copy failed');
        setError(error);
        setCopied(false);
        onError?.(error);
        return false;
      }
    },
    [successDuration, onSuccess, onError]
  );

  // Cleanup timeout
  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  return { copy, copied, error, reset };
}

// ============ CopyButton Component ============

export function CopyButton({
  text,
  label = 'Copy',
  copiedLabel = 'Copied!',
  successDuration = 2000,
  onCopy,
  showIcon = true,
  size = 'medium',
  variant = 'default',
  disabled = false,
  className = '',
}: CopyButtonProps) {
  const { copy, copied } = useCopy({
    successDuration,
    onSuccess: onCopy,
  });

  const handleClick = () => {
    if (!disabled) {
      copy(text);
    }
  };

  const iconCopy = (
    <svg
      className="copy-button__icon"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
    >
      <rect x="9" y="9" width="13" height="13" rx="2" />
      <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
    </svg>
  );

  const iconCheck = (
    <svg
      className="copy-button__icon copy-button__icon--check"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
    >
      <polyline points="20 6 9 17 4 12" />
    </svg>
  );

  return (
    <button
      type="button"
      className={`copy-button copy-button--${size} copy-button--${variant} ${
        copied ? 'copy-button--copied' : ''
      } ${className}`}
      onClick={handleClick}
      disabled={disabled}
      aria-label={copied ? copiedLabel : label}
    >
      {showIcon && (copied ? iconCheck : iconCopy)}
      <span className="copy-button__label">{copied ? copiedLabel : label}</span>
    </button>
  );
}

// ============ CopyToClipboard Wrapper ============

export function CopyToClipboard({
  text,
  children,
  onCopy,
  successDuration = 2000,
}: CopyToClipboardProps) {
  const { copy, copied } = useCopy({
    successDuration,
    onSuccess: onCopy,
  });

  const handleCopy = () => copy(text);

  // Render prop pattern
  if (typeof children === 'function') {
    return <>{children({ copy: handleCopy, copied })}</>;
  }

  // Wrap children with click handler
  return (
    <span
      className="copy-to-clipboard"
      onClick={handleCopy}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          handleCopy();
        }
      }}
    >
      {children}
    </span>
  );
}

// ============ CopyText Component ============

export interface CopyTextProps {
  /** Text to display and copy */
  text: string;
  /** Truncate text */
  truncate?: boolean;
  /** Max width for truncation */
  maxWidth?: number | string;
  /** Show copy button on hover only */
  hoverOnly?: boolean;
  /** Custom class */
  className?: string;
}

export function CopyText({
  text,
  truncate = false,
  maxWidth,
  hoverOnly = true,
  className = '',
}: CopyTextProps) {
  const { copy, copied } = useCopy({ successDuration: 1500 });

  return (
    <span
      className={`copy-text ${hoverOnly ? 'copy-text--hover-only' : ''} ${
        truncate ? 'copy-text--truncate' : ''
      } ${className}`}
      style={{ maxWidth }}
    >
      <span className="copy-text__value">{text}</span>
      <button
        type="button"
        className={`copy-text__button ${copied ? 'copy-text__button--copied' : ''}`}
        onClick={() => copy(text)}
        aria-label="Copy"
      >
        {copied ? '✓' : '⧉'}
      </button>
    </span>
  );
}

export default CopyButton;
