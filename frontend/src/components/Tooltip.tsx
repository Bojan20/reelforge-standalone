/**
 * Tooltip Component
 *
 * Hover tooltips with:
 * - Multiple positions
 * - Keyboard shortcut display
 * - Rich content support
 * - Delay control
 *
 * @module components/Tooltip
 */

import { memo, useState, useRef, useEffect, useCallback, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import './Tooltip.css';

// ============ TYPES ============

export type TooltipPosition = 'top' | 'bottom' | 'left' | 'right';

export interface TooltipProps {
  content: ReactNode;
  children: ReactNode;
  position?: TooltipPosition;
  delay?: number;
  shortcut?: string;
  disabled?: boolean;
  maxWidth?: number;
}

// ============ TOOLTIP ============

export const Tooltip = memo(function Tooltip({
  content,
  children,
  position = 'top',
  delay = 400,
  shortcut,
  disabled = false,
  maxWidth = 250,
}: TooltipProps) {
  const [isVisible, setIsVisible] = useState(false);
  const [coords, setCoords] = useState({ x: 0, y: 0 });
  const triggerRef = useRef<HTMLDivElement>(null);
  const tooltipRef = useRef<HTMLDivElement>(null);
  const timeoutRef = useRef<number | null>(null);

  // Calculate position
  const updatePosition = useCallback(() => {
    if (!triggerRef.current || !tooltipRef.current) return;

    const triggerRect = triggerRef.current.getBoundingClientRect();
    const tooltipRect = tooltipRef.current.getBoundingClientRect();
    const gap = 8;

    let x = 0;
    let y = 0;

    switch (position) {
      case 'top':
        x = triggerRect.left + triggerRect.width / 2 - tooltipRect.width / 2;
        y = triggerRect.top - tooltipRect.height - gap;
        break;
      case 'bottom':
        x = triggerRect.left + triggerRect.width / 2 - tooltipRect.width / 2;
        y = triggerRect.bottom + gap;
        break;
      case 'left':
        x = triggerRect.left - tooltipRect.width - gap;
        y = triggerRect.top + triggerRect.height / 2 - tooltipRect.height / 2;
        break;
      case 'right':
        x = triggerRect.right + gap;
        y = triggerRect.top + triggerRect.height / 2 - tooltipRect.height / 2;
        break;
    }

    // Keep within viewport
    const padding = 8;
    x = Math.max(padding, Math.min(x, window.innerWidth - tooltipRect.width - padding));
    y = Math.max(padding, Math.min(y, window.innerHeight - tooltipRect.height - padding));

    setCoords({ x, y });
  }, [position]);

  // Show tooltip
  const handleMouseEnter = useCallback(() => {
    if (disabled) return;

    timeoutRef.current = window.setTimeout(() => {
      setIsVisible(true);
    }, delay);
  }, [delay, disabled]);

  // Hide tooltip
  const handleMouseLeave = useCallback(() => {
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
      timeoutRef.current = null;
    }
    setIsVisible(false);
  }, []);

  // Update position when visible
  useEffect(() => {
    if (isVisible) {
      // Small delay to ensure tooltip is rendered
      requestAnimationFrame(updatePosition);
    }
  }, [isVisible, updatePosition]);

  // Cleanup timeout on unmount
  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  // Keyboard shortcut formatting
  const formatShortcut = (shortcut: string): ReactNode => {
    const keys = shortcut.split('+').map(k => k.trim());
    return (
      <span className="tooltip-shortcut">
        {keys.map((key, i) => (
          <span key={i}>
            <kbd className="tooltip-key">{key}</kbd>
            {i < keys.length - 1 && <span className="tooltip-key-sep">+</span>}
          </span>
        ))}
      </span>
    );
  };

  return (
    <>
      <div
        ref={triggerRef}
        className="tooltip-trigger"
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
        onFocus={handleMouseEnter}
        onBlur={handleMouseLeave}
      >
        {children}
      </div>

      {isVisible && createPortal(
        <div
          ref={tooltipRef}
          className={`tooltip tooltip--${position}`}
          style={{
            left: coords.x,
            top: coords.y,
            maxWidth,
          }}
          role="tooltip"
        >
          <div className="tooltip-content">
            {content}
            {shortcut && formatShortcut(shortcut)}
          </div>
          <div className="tooltip-arrow" />
        </div>,
        document.body
      )}
    </>
  );
});

// ============ TOOLTIP PROVIDER ============

// Simple hook for imperative tooltip
export function useTooltip() {
  const [tooltip, setTooltip] = useState<{
    content: ReactNode;
    x: number;
    y: number;
    visible: boolean;
  }>({
    content: null,
    x: 0,
    y: 0,
    visible: false,
  });

  const show = useCallback((content: ReactNode, x: number, y: number) => {
    setTooltip({ content, x, y, visible: true });
  }, []);

  const hide = useCallback(() => {
    setTooltip(prev => ({ ...prev, visible: false }));
  }, []);

  const TooltipPortal = tooltip.visible ? createPortal(
    <div
      className="tooltip tooltip--dynamic"
      style={{ left: tooltip.x, top: tooltip.y }}
    >
      <div className="tooltip-content">{tooltip.content}</div>
    </div>,
    document.body
  ) : null;

  return { show, hide, TooltipPortal };
}

// ============ INFO TOOLTIP ============

export interface InfoTooltipProps {
  content: ReactNode;
  position?: TooltipPosition;
}

export const InfoTooltip = memo(function InfoTooltip({
  content,
  position = 'top',
}: InfoTooltipProps) {
  return (
    <Tooltip content={content} position={position}>
      <span className="info-tooltip-trigger">ⓘ</span>
    </Tooltip>
  );
});

export default Tooltip;
