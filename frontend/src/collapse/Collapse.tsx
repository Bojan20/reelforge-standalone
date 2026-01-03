/**
 * ReelForge Collapse
 *
 * Collapsible panel:
 * - Animated expand/collapse
 * - Controlled and uncontrolled
 * - Custom trigger
 *
 * @module collapse/Collapse
 */

import { useState, useRef, useEffect } from 'react';
import './Collapse.css';

// ============ Types ============

export interface CollapseProps {
  /** Header/trigger content */
  header: React.ReactNode;
  /** Panel content */
  children: React.ReactNode;
  /** Controlled expanded state */
  expanded?: boolean;
  /** Default expanded (uncontrolled) */
  defaultExpanded?: boolean;
  /** On expand change */
  onExpandChange?: (expanded: boolean) => void;
  /** Show arrow icon */
  showArrow?: boolean;
  /** Arrow position */
  arrowPosition?: 'left' | 'right';
  /** Disabled */
  disabled?: boolean;
  /** Bordered style */
  bordered?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Component ============

export function Collapse({
  header,
  children,
  expanded: controlledExpanded,
  defaultExpanded = false,
  onExpandChange,
  showArrow = true,
  arrowPosition = 'left',
  disabled = false,
  bordered = true,
  className = '',
}: CollapseProps) {
  const [internalExpanded, setInternalExpanded] = useState(defaultExpanded);
  const [contentHeight, setContentHeight] = useState<number | 'auto'>(
    defaultExpanded ? 'auto' : 0
  );
  const contentRef = useRef<HTMLDivElement>(null);

  const isControlled = controlledExpanded !== undefined;
  const isExpanded = isControlled ? controlledExpanded : internalExpanded;

  const toggle = () => {
    if (disabled) return;

    const newValue = !isExpanded;
    if (!isControlled) {
      setInternalExpanded(newValue);
    }
    onExpandChange?.(newValue);
  };

  // Animate height
  useEffect(() => {
    if (!contentRef.current) return;

    if (isExpanded) {
      const height = contentRef.current.scrollHeight;
      setContentHeight(height);

      // After animation, set to auto for dynamic content
      const timer = setTimeout(() => {
        setContentHeight('auto');
      }, 200);
      return () => clearTimeout(timer);
    } else {
      // First set current height, then animate to 0
      const height = contentRef.current.scrollHeight;
      setContentHeight(height);
      requestAnimationFrame(() => {
        setContentHeight(0);
      });
    }
  }, [isExpanded]);

  const ArrowIcon = () => (
    <svg
      viewBox="0 0 24 24"
      fill="currentColor"
      className={`collapse__arrow ${isExpanded ? 'collapse__arrow--expanded' : ''}`}
    >
      <path d="M8.59 16.59L13.17 12 8.59 7.41 10 6l6 6-6 6-1.41-1.41z" />
    </svg>
  );

  return (
    <div
      className={`collapse ${bordered ? 'collapse--bordered' : ''} ${
        isExpanded ? 'collapse--expanded' : ''
      } ${disabled ? 'collapse--disabled' : ''} ${className}`}
    >
      <button
        type="button"
        className="collapse__header"
        onClick={toggle}
        disabled={disabled}
        aria-expanded={isExpanded}
      >
        {showArrow && arrowPosition === 'left' && <ArrowIcon />}
        <span className="collapse__header-content">{header}</span>
        {showArrow && arrowPosition === 'right' && <ArrowIcon />}
      </button>

      <div
        ref={contentRef}
        className="collapse__content"
        style={{
          height: contentHeight === 'auto' ? 'auto' : `${contentHeight}px`,
        }}
      >
        <div className="collapse__content-inner">{children}</div>
      </div>
    </div>
  );
}

// ============ Collapse Group ============

export interface CollapseGroupProps {
  /** Allow multiple open */
  multiple?: boolean;
  /** Children collapse panels */
  children: React.ReactNode;
  /** Default expanded keys (uncontrolled) */
  defaultExpandedKeys?: string[];
  /** Expanded keys (controlled) */
  expandedKeys?: string[];
  /** On expand change */
  onExpandChange?: (keys: string[]) => void;
  /** Bordered style */
  bordered?: boolean;
  /** Custom class */
  className?: string;
}

export function CollapseGroup({
  children,
  bordered = true,
  className = '',
}: CollapseGroupProps) {
  return (
    <div className={`collapse-group ${bordered ? 'collapse-group--bordered' : ''} ${className}`}>
      {children}
    </div>
  );
}

export default Collapse;
