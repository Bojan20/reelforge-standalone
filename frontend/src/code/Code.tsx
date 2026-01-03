/**
 * ReelForge Code
 *
 * Code display components:
 * - Inline code
 * - Code blocks
 * - Copy button
 * - Line numbers
 *
 * @module code/Code
 */

import { useState, useCallback } from 'react';
import './Code.css';

// ============ Types ============

export interface InlineCodeProps {
  /** Code content */
  children: React.ReactNode;
  /** Custom class */
  className?: string;
}

export interface CodeBlockProps {
  /** Code content */
  children: string;
  /** Language (for styling class) */
  language?: string;
  /** Show line numbers */
  lineNumbers?: boolean;
  /** Starting line number */
  startLine?: number;
  /** Show copy button */
  copyable?: boolean;
  /** Filename/title */
  filename?: string;
  /** Highlight lines (1-indexed) */
  highlightLines?: number[];
  /** Max height with scroll */
  maxHeight?: number | string;
  /** Custom class */
  className?: string;
}

// ============ Inline Code ============

export function InlineCode({ children, className = '' }: InlineCodeProps) {
  return <code className={`inline-code ${className}`}>{children}</code>;
}

// ============ Code Block ============

export function CodeBlock({
  children,
  language,
  lineNumbers = false,
  startLine = 1,
  copyable = true,
  filename,
  highlightLines = [],
  maxHeight,
  className = '',
}: CodeBlockProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(children);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback
      const textarea = document.createElement('textarea');
      textarea.value = children;
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand('copy');
      document.body.removeChild(textarea);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  }, [children]);

  const lines = children.split('\n');
  // Remove trailing empty line if present
  if (lines[lines.length - 1] === '') {
    lines.pop();
  }

  const style: React.CSSProperties = {};
  if (maxHeight) {
    style.maxHeight = typeof maxHeight === 'number' ? `${maxHeight}px` : maxHeight;
    style.overflow = 'auto';
  }

  return (
    <div className={`code-block ${className}`}>
      {/* Header */}
      {(filename || copyable) && (
        <div className="code-block__header">
          {filename && (
            <span className="code-block__filename">{filename}</span>
          )}
          {language && !filename && (
            <span className="code-block__language">{language}</span>
          )}
          <div className="code-block__spacer" />
          {copyable && (
            <button
              type="button"
              className="code-block__copy"
              onClick={handleCopy}
              aria-label="Copy code"
            >
              {copied ? (
                <svg viewBox="0 0 24 24" fill="currentColor">
                  <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z" />
                </svg>
              ) : (
                <svg viewBox="0 0 24 24" fill="currentColor">
                  <path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z" />
                </svg>
              )}
            </button>
          )}
        </div>
      )}

      {/* Code */}
      <pre
        className={`code-block__pre ${language ? `language-${language}` : ''}`}
        style={style}
      >
        <code className="code-block__code">
          {lines.map((line, index) => {
            const lineNum = startLine + index;
            const isHighlighted = highlightLines.includes(lineNum);

            return (
              <div
                key={index}
                className={`code-block__line ${isHighlighted ? 'code-block__line--highlighted' : ''}`}
              >
                {lineNumbers && (
                  <span className="code-block__line-number">{lineNum}</span>
                )}
                <span className="code-block__line-content">{line || ' '}</span>
              </div>
            );
          })}
        </code>
      </pre>
    </div>
  );
}

// ============ Pre (simple) ============

export function Pre({
  children,
  className = '',
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return <pre className={`pre ${className}`}>{children}</pre>;
}

export default CodeBlock;
