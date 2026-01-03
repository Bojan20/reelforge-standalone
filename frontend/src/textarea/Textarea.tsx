/**
 * ReelForge Textarea
 *
 * Textarea component:
 * - Auto resize
 * - Character count
 * - Min/max rows
 *
 * @module textarea/Textarea
 */

import { useRef, useEffect, useCallback } from 'react';
import './Textarea.css';

// ============ Types ============

export interface TextareaProps {
  /** Value */
  value: string;
  /** On change */
  onChange: (value: string) => void;
  /** Placeholder */
  placeholder?: string;
  /** Disabled */
  disabled?: boolean;
  /** Read only */
  readOnly?: boolean;
  /** Auto resize to content */
  autoResize?: boolean;
  /** Minimum rows */
  minRows?: number;
  /** Maximum rows */
  maxRows?: number;
  /** Max length */
  maxLength?: number;
  /** Show character count */
  showCount?: boolean;
  /** Resize handle */
  resize?: 'none' | 'vertical' | 'horizontal' | 'both';
  /** Error state */
  error?: boolean;
  /** Custom class */
  className?: string;
  /** On blur */
  onBlur?: () => void;
  /** On focus */
  onFocus?: () => void;
}

// ============ Component ============

export function Textarea({
  value,
  onChange,
  placeholder,
  disabled = false,
  readOnly = false,
  autoResize = false,
  minRows = 3,
  maxRows = 10,
  maxLength,
  showCount = false,
  resize = 'vertical',
  error = false,
  className = '',
  onBlur,
  onFocus,
}: TextareaProps) {
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const adjustHeight = useCallback(() => {
    const textarea = textareaRef.current;
    if (!textarea || !autoResize) return;

    // Reset height to calculate scroll height
    textarea.style.height = 'auto';

    const lineHeight = parseInt(getComputedStyle(textarea).lineHeight) || 20;
    const minHeight = lineHeight * minRows;
    const maxHeight = lineHeight * maxRows;

    const newHeight = Math.min(Math.max(textarea.scrollHeight, minHeight), maxHeight);
    textarea.style.height = `${newHeight}px`;
  }, [autoResize, minRows, maxRows]);

  useEffect(() => {
    adjustHeight();
  }, [value, adjustHeight]);

  const handleChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    onChange(e.target.value);
  };

  const style: React.CSSProperties = {
    resize: autoResize ? 'none' : resize,
  };

  if (!autoResize) {
    const lineHeight = 20;
    style.minHeight = `${lineHeight * minRows + 24}px`; // +24 for padding
  }

  return (
    <div className={`textarea-wrapper ${className}`}>
      <textarea
        ref={textareaRef}
        value={value}
        onChange={handleChange}
        placeholder={placeholder}
        disabled={disabled}
        readOnly={readOnly}
        maxLength={maxLength}
        className={`textarea ${error ? 'textarea--error' : ''} ${
          disabled ? 'textarea--disabled' : ''
        }`}
        style={style}
        onBlur={onBlur}
        onFocus={onFocus}
      />
      {showCount && (
        <div className="textarea__count">
          {value.length}
          {maxLength && ` / ${maxLength}`}
        </div>
      )}
    </div>
  );
}

export default Textarea;
