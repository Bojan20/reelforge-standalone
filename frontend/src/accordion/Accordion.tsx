/**
 * ReelForge Accordion
 *
 * Accordion component:
 * - Expandable/collapsible sections
 * - Single or multiple open
 * - Animated transitions
 * - Icons and badges
 * - Keyboard navigation
 *
 * @module accordion/Accordion
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import './Accordion.css';

// ============ Types ============

export interface AccordionItem {
  /** Unique ID */
  id: string;
  /** Header title */
  title: React.ReactNode;
  /** Content */
  content: React.ReactNode;
  /** Icon */
  icon?: React.ReactNode;
  /** Badge */
  badge?: React.ReactNode;
  /** Disabled */
  disabled?: boolean;
}

export interface AccordionProps {
  /** Items */
  items: AccordionItem[];
  /** Expanded item IDs */
  expanded?: string[];
  /** Default expanded IDs */
  defaultExpanded?: string[];
  /** On change */
  onChange?: (expanded: string[]) => void;
  /** Allow multiple open */
  multiple?: boolean;
  /** Collapsible (allow closing all) */
  collapsible?: boolean;
  /** Size */
  size?: 'small' | 'medium' | 'large';
  /** Variant */
  variant?: 'default' | 'bordered' | 'separated';
  /** Custom class */
  className?: string;
}

// ============ Component ============

export function Accordion({
  items,
  expanded: controlledExpanded,
  defaultExpanded = [],
  onChange,
  multiple = false,
  collapsible = true,
  size = 'medium',
  variant = 'default',
  className = '',
}: AccordionProps) {
  const [internalExpanded, setInternalExpanded] = useState<string[]>(defaultExpanded);
  const isControlled = controlledExpanded !== undefined;
  const expanded = isControlled ? controlledExpanded : internalExpanded;

  const handleToggle = useCallback(
    (id: string) => {
      let newExpanded: string[];

      if (expanded.includes(id)) {
        // Closing
        if (!collapsible && expanded.length === 1) {
          return; // Can't close last one
        }
        newExpanded = expanded.filter((e) => e !== id);
      } else {
        // Opening
        if (multiple) {
          newExpanded = [...expanded, id];
        } else {
          newExpanded = [id];
        }
      }

      if (!isControlled) {
        setInternalExpanded(newExpanded);
      }
      onChange?.(newExpanded);
    },
    [expanded, multiple, collapsible, isControlled, onChange]
  );

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent, id: string, index: number) => {
      switch (e.key) {
        case 'Enter':
        case ' ':
          e.preventDefault();
          handleToggle(id);
          break;
        case 'ArrowDown':
          e.preventDefault();
          focusItem(index + 1);
          break;
        case 'ArrowUp':
          e.preventDefault();
          focusItem(index - 1);
          break;
        case 'Home':
          e.preventDefault();
          focusItem(0);
          break;
        case 'End':
          e.preventDefault();
          focusItem(items.length - 1);
          break;
      }
    },
    [handleToggle, items.length]
  );

  const focusItem = (index: number) => {
    const wrapped = ((index % items.length) + items.length) % items.length;
    const header = document.querySelector(
      `[data-accordion-index="${wrapped}"]`
    ) as HTMLElement;
    header?.focus();
  };

  return (
    <div
      className={`accordion accordion--${size} accordion--${variant} ${className}`}
    >
      {items.map((item, index) => (
        <AccordionPanel
          key={item.id}
          item={item}
          index={index}
          isExpanded={expanded.includes(item.id)}
          onToggle={() => handleToggle(item.id)}
          onKeyDown={(e) => handleKeyDown(e, item.id, index)}
        />
      ))}
    </div>
  );
}

// ============ Panel ============

interface AccordionPanelProps {
  item: AccordionItem;
  index: number;
  isExpanded: boolean;
  onToggle: () => void;
  onKeyDown: (e: React.KeyboardEvent) => void;
}

function AccordionPanel({
  item,
  index,
  isExpanded,
  onToggle,
  onKeyDown,
}: AccordionPanelProps) {
  const contentRef = useRef<HTMLDivElement>(null);
  const [height, setHeight] = useState<number | undefined>(undefined);

  useEffect(() => {
    if (contentRef.current) {
      setHeight(contentRef.current.scrollHeight);
    }
  }, [item.content]);

  return (
    <div
      className={`accordion__panel ${
        isExpanded ? 'accordion__panel--expanded' : ''
      } ${item.disabled ? 'accordion__panel--disabled' : ''}`}
    >
      {/* Header */}
      <button
        type="button"
        className="accordion__header"
        onClick={() => !item.disabled && onToggle()}
        onKeyDown={onKeyDown}
        disabled={item.disabled}
        aria-expanded={isExpanded}
        aria-controls={`accordion-content-${item.id}`}
        data-accordion-index={index}
      >
        {item.icon && <span className="accordion__icon">{item.icon}</span>}
        <span className="accordion__title">{item.title}</span>
        {item.badge && <span className="accordion__badge">{item.badge}</span>}
        <span className="accordion__arrow">
          <svg width="12" height="12" viewBox="0 0 12 12">
            <path
              d="M2 4L6 8L10 4"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </span>
      </button>

      {/* Content */}
      <div
        id={`accordion-content-${item.id}`}
        className="accordion__content-wrapper"
        style={{
          height: isExpanded ? height : 0,
        }}
      >
        <div ref={contentRef} className="accordion__content">
          {item.content}
        </div>
      </div>
    </div>
  );
}

export default Accordion;
