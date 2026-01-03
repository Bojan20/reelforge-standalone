/**
 * ReelForge Popover
 *
 * Popover component:
 * - Positioned relative to trigger
 * - Multiple placements
 * - Arrow indicator
 * - Click/hover triggers
 *
 * @module popover/Popover
 */

import { useState, useRef, useEffect, useCallback } from 'react';
import { createPortal } from 'react-dom';
import './Popover.css';

// ============ Types ============

export type PopoverPlacement =
  | 'top'
  | 'top-start'
  | 'top-end'
  | 'bottom'
  | 'bottom-start'
  | 'bottom-end'
  | 'left'
  | 'left-start'
  | 'left-end'
  | 'right'
  | 'right-start'
  | 'right-end';

export type PopoverTrigger = 'click' | 'hover' | 'focus' | 'manual';

export interface PopoverProps {
  /** Popover content */
  content: React.ReactNode;
  /** Trigger element */
  children: React.ReactElement;
  /** Placement */
  placement?: PopoverPlacement;
  /** Trigger type */
  trigger?: PopoverTrigger;
  /** Controlled open state */
  open?: boolean;
  /** On open change */
  onOpenChange?: (open: boolean) => void;
  /** Show arrow */
  arrow?: boolean;
  /** Offset from trigger (px) */
  offset?: number;
  /** Delay before showing (ms) */
  showDelay?: number;
  /** Delay before hiding (ms) */
  hideDelay?: number;
  /** Disabled */
  disabled?: boolean;
  /** Custom class for content */
  className?: string;
}

// ============ Position Calculator ============

interface Position {
  top: number;
  left: number;
  arrowTop?: number;
  arrowLeft?: number;
  arrowRotation?: number;
}

function calculatePosition(
  triggerRect: DOMRect,
  contentRect: DOMRect,
  placement: PopoverPlacement,
  offset: number
): Position {
  const gap = offset;
  let top = 0;
  let left = 0;
  let arrowTop: number | undefined;
  let arrowLeft: number | undefined;
  let arrowRotation = 0;

  const [side, align = 'center'] = placement.split('-') as [string, string?];

  // Calculate base position
  switch (side) {
    case 'top':
      top = triggerRect.top - contentRect.height - gap;
      arrowRotation = 180;
      break;
    case 'bottom':
      top = triggerRect.bottom + gap;
      arrowRotation = 0;
      break;
    case 'left':
      left = triggerRect.left - contentRect.width - gap;
      arrowRotation = 90;
      break;
    case 'right':
      left = triggerRect.right + gap;
      arrowRotation = -90;
      break;
  }

  // Alignment
  if (side === 'top' || side === 'bottom') {
    switch (align) {
      case 'start':
        left = triggerRect.left;
        arrowLeft = Math.min(24, triggerRect.width / 2);
        break;
      case 'end':
        left = triggerRect.right - contentRect.width;
        arrowLeft = contentRect.width - Math.min(24, triggerRect.width / 2);
        break;
      default:
        left = triggerRect.left + triggerRect.width / 2 - contentRect.width / 2;
        arrowLeft = contentRect.width / 2;
    }
    arrowTop = side === 'top' ? contentRect.height : 0;
  } else {
    switch (align) {
      case 'start':
        top = triggerRect.top;
        arrowTop = Math.min(16, triggerRect.height / 2);
        break;
      case 'end':
        top = triggerRect.bottom - contentRect.height;
        arrowTop = contentRect.height - Math.min(16, triggerRect.height / 2);
        break;
      default:
        top = triggerRect.top + triggerRect.height / 2 - contentRect.height / 2;
        arrowTop = contentRect.height / 2;
    }
    arrowLeft = side === 'left' ? contentRect.width : 0;
  }

  // Add scroll offset
  top += window.scrollY;
  left += window.scrollX;

  return { top, left, arrowTop, arrowLeft, arrowRotation };
}

// ============ Component ============

export function Popover({
  content,
  children,
  placement = 'bottom',
  trigger = 'click',
  open: controlledOpen,
  onOpenChange,
  arrow = true,
  offset = 8,
  showDelay = 0,
  hideDelay = 100,
  disabled = false,
  className = '',
}: PopoverProps) {
  const [internalOpen, setInternalOpen] = useState(false);
  const [position, setPosition] = useState<Position>({ top: 0, left: 0 });

  const triggerRef = useRef<HTMLElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const showTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const hideTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const isControlled = controlledOpen !== undefined;
  const isOpen = isControlled ? controlledOpen : internalOpen;

  const setOpen = useCallback(
    (value: boolean) => {
      if (!isControlled) {
        setInternalOpen(value);
      }
      onOpenChange?.(value);
    },
    [isControlled, onOpenChange]
  );

  const show = useCallback(() => {
    if (disabled) return;
    if (hideTimeoutRef.current) clearTimeout(hideTimeoutRef.current);
    showTimeoutRef.current = setTimeout(() => setOpen(true), showDelay);
  }, [disabled, showDelay, setOpen]);

  const hide = useCallback(() => {
    if (showTimeoutRef.current) clearTimeout(showTimeoutRef.current);
    hideTimeoutRef.current = setTimeout(() => setOpen(false), hideDelay);
  }, [hideDelay, setOpen]);

  const toggle = useCallback(() => {
    if (isOpen) {
      hide();
    } else {
      show();
    }
  }, [isOpen, show, hide]);

  // Update position
  useEffect(() => {
    if (!isOpen || !triggerRef.current || !contentRef.current) return;

    const updatePosition = () => {
      const triggerRect = triggerRef.current!.getBoundingClientRect();
      const contentRect = contentRef.current!.getBoundingClientRect();
      setPosition(calculatePosition(triggerRect, contentRect, placement, offset));
    };

    updatePosition();

    window.addEventListener('scroll', updatePosition, true);
    window.addEventListener('resize', updatePosition);

    return () => {
      window.removeEventListener('scroll', updatePosition, true);
      window.removeEventListener('resize', updatePosition);
    };
  }, [isOpen, placement, offset]);

  // Click outside
  useEffect(() => {
    if (!isOpen || trigger !== 'click') return;

    const handleClickOutside = (e: MouseEvent) => {
      if (
        triggerRef.current &&
        !triggerRef.current.contains(e.target as Node) &&
        contentRef.current &&
        !contentRef.current.contains(e.target as Node)
      ) {
        setOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [isOpen, trigger, setOpen]);

  // Cleanup timeouts
  useEffect(() => {
    return () => {
      if (showTimeoutRef.current) clearTimeout(showTimeoutRef.current);
      if (hideTimeoutRef.current) clearTimeout(hideTimeoutRef.current);
    };
  }, []);

  // Clone trigger with ref and events
  const triggerProps: Record<string, unknown> = {
    ref: triggerRef,
  };

  if (trigger === 'click') {
    triggerProps.onClick = toggle;
  } else if (trigger === 'hover') {
    triggerProps.onMouseEnter = () => show();
    triggerProps.onMouseLeave = () => hide();
  } else if (trigger === 'focus') {
    triggerProps.onFocus = () => show();
    triggerProps.onBlur = () => hide();
  }

  const triggerElement = (
    <span className="popover-trigger" {...triggerProps}>
      {children}
    </span>
  );

  const popoverContent = isOpen
    ? createPortal(
        <div
          ref={contentRef}
          className={`popover popover--${placement.split('-')[0]} ${className}`}
          style={{ top: position.top, left: position.left }}
          onMouseEnter={trigger === 'hover' ? show : undefined}
          onMouseLeave={trigger === 'hover' ? hide : undefined}
        >
          <div className="popover__content">{content}</div>
          {arrow && (
            <div
              className="popover__arrow"
              style={{
                top: position.arrowTop,
                left: position.arrowLeft,
                transform: `translate(-50%, -50%) rotate(${position.arrowRotation}deg)`,
              }}
            />
          )}
        </div>,
        document.body
      )
    : null;

  return (
    <>
      {triggerElement}
      {popoverContent}
    </>
  );
}

export default Popover;
