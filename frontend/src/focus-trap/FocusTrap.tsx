/**
 * ReelForge FocusTrap
 *
 * Trap focus within container:
 * - Tab cycling
 * - Auto focus first element
 * - Restore focus on unmount
 * - Escape to close
 *
 * @module focus-trap/FocusTrap
 */

import { useRef, useEffect, useCallback } from 'react';

// ============ Types ============

export interface FocusTrapProps {
  /** Children to trap focus within */
  children: React.ReactNode;
  /** Is trap active */
  active?: boolean;
  /** Auto focus first element */
  autoFocus?: boolean;
  /** Restore focus on deactivate */
  restoreFocus?: boolean;
  /** Callback when escape pressed */
  onEscape?: () => void;
  /** Allow focus outside (for nested traps) */
  allowOutsideClick?: boolean;
  /** Initial focus element selector */
  initialFocus?: string;
  /** Return focus element selector */
  returnFocus?: string | HTMLElement | null;
  /** Custom class */
  className?: string;
}

export interface UseFocusTrapOptions {
  /** Is trap active */
  active?: boolean;
  /** Auto focus first element */
  autoFocus?: boolean;
  /** Restore focus on deactivate */
  restoreFocus?: boolean;
  /** Callback when escape pressed */
  onEscape?: () => void;
  /** Initial focus selector */
  initialFocus?: string;
}

// ============ Focusable Selectors ============

const FOCUSABLE_SELECTORS = [
  'a[href]',
  'area[href]',
  'input:not([disabled]):not([type="hidden"])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  'button:not([disabled])',
  'iframe',
  'object',
  'embed',
  '[contenteditable]',
  '[tabindex]:not([tabindex="-1"])',
].join(',');

// ============ Hook ============

export function useFocusTrap({
  active = true,
  autoFocus = true,
  restoreFocus = true,
  onEscape,
  initialFocus,
}: UseFocusTrapOptions = {}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(null);

  // Get focusable elements
  const getFocusableElements = useCallback(() => {
    if (!containerRef.current) return [];
    return Array.from(
      containerRef.current.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTORS)
    ).filter((el) => el.offsetParent !== null); // Filter hidden elements
  }, []);

  // Handle tab key
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (!active) return;

      // Escape key
      if (e.key === 'Escape' && onEscape) {
        e.preventDefault();
        onEscape();
        return;
      }

      // Tab key
      if (e.key !== 'Tab') return;

      const focusableElements = getFocusableElements();
      if (focusableElements.length === 0) return;

      const firstElement = focusableElements[0];
      const lastElement = focusableElements[focusableElements.length - 1];
      const activeElement = document.activeElement;

      // Shift + Tab on first element -> go to last
      if (e.shiftKey && activeElement === firstElement) {
        e.preventDefault();
        lastElement.focus();
        return;
      }

      // Tab on last element -> go to first
      if (!e.shiftKey && activeElement === lastElement) {
        e.preventDefault();
        firstElement.focus();
        return;
      }

      // If focus is outside container, bring it back
      if (!containerRef.current?.contains(activeElement)) {
        e.preventDefault();
        firstElement.focus();
      }
    },
    [active, onEscape, getFocusableElements]
  );

  // Setup trap
  useEffect(() => {
    if (!active) return;

    // Store previous focus
    previousFocusRef.current = document.activeElement as HTMLElement;

    // Auto focus
    if (autoFocus) {
      const focusableElements = getFocusableElements();

      if (initialFocus && containerRef.current) {
        const initial = containerRef.current.querySelector<HTMLElement>(initialFocus);
        if (initial) {
          initial.focus();
        } else if (focusableElements.length > 0) {
          focusableElements[0].focus();
        }
      } else if (focusableElements.length > 0) {
        focusableElements[0].focus();
      }
    }

    // Add event listener
    document.addEventListener('keydown', handleKeyDown);

    return () => {
      document.removeEventListener('keydown', handleKeyDown);

      // Restore focus
      if (restoreFocus && previousFocusRef.current) {
        previousFocusRef.current.focus();
      }
    };
  }, [active, autoFocus, restoreFocus, initialFocus, handleKeyDown, getFocusableElements]);

  return { containerRef, getFocusableElements };
}

// ============ Component ============

export function FocusTrap({
  children,
  active = true,
  autoFocus = true,
  restoreFocus = true,
  onEscape,
  allowOutsideClick = false,
  initialFocus,
  className = '',
}: FocusTrapProps) {
  const { containerRef } = useFocusTrap({
    active,
    autoFocus,
    restoreFocus,
    onEscape,
    initialFocus,
  });

  // Handle click outside
  useEffect(() => {
    if (!active || allowOutsideClick) return;

    const handleClick = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        e.stopPropagation();
        // Return focus to container
        const focusable = containerRef.current.querySelector<HTMLElement>(FOCUSABLE_SELECTORS);
        if (focusable) focusable.focus();
      }
    };

    document.addEventListener('mousedown', handleClick, true);
    return () => document.removeEventListener('mousedown', handleClick, true);
  }, [active, allowOutsideClick]);

  return (
    <div ref={containerRef} className={`focus-trap ${className}`}>
      {children}
    </div>
  );
}

// ============ FocusScope ============

export interface FocusScopeProps {
  /** Children */
  children: React.ReactNode;
  /** Contain focus within scope */
  contain?: boolean;
  /** Restore focus when scope unmounts */
  restoreFocus?: boolean;
  /** Auto focus first element */
  autoFocus?: boolean;
}

export function FocusScope({
  children,
  contain = false,
  restoreFocus = true,
  autoFocus = false,
}: FocusScopeProps) {
  const scopeRef = useRef<HTMLDivElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    previousFocusRef.current = document.activeElement as HTMLElement;

    if (autoFocus && scopeRef.current) {
      const focusable = scopeRef.current.querySelector<HTMLElement>(FOCUSABLE_SELECTORS);
      if (focusable) focusable.focus();
    }

    return () => {
      if (restoreFocus && previousFocusRef.current) {
        previousFocusRef.current.focus();
      }
    };
  }, [autoFocus, restoreFocus]);

  if (contain) {
    return (
      <FocusTrap active={true} autoFocus={autoFocus} restoreFocus={restoreFocus}>
        {children}
      </FocusTrap>
    );
  }

  return (
    <div ref={scopeRef} className="focus-scope">
      {children}
    </div>
  );
}

export default FocusTrap;
