/**
 * ReelForge Focus Management
 *
 * Utilities for managing keyboard focus:
 * - Focus trap for modals/drawers
 * - Focus restoration
 * - Skip links
 * - Focus indicators
 */

import { useEffect, useRef, useCallback, type RefObject } from 'react';

// ============ Focus Trap ============

const FOCUSABLE_SELECTORS = [
  'button:not([disabled])',
  'input:not([disabled])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  'a[href]',
  '[tabindex]:not([tabindex="-1"])',
  '[contenteditable="true"]',
].join(', ');

/**
 * Get all focusable elements within a container.
 */
export function getFocusableElements(container: HTMLElement): HTMLElement[] {
  return Array.from(container.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTORS)).filter(
    (el) => el.offsetParent !== null // Exclude hidden elements
  );
}

/**
 * Focus trap that keeps focus within a container.
 */
export function createFocusTrap(container: HTMLElement): {
  activate: () => void;
  deactivate: () => void;
} {
  let previouslyFocused: HTMLElement | null = null;

  const handleKeyDown = (e: KeyboardEvent) => {
    if (e.key !== 'Tab') return;

    const focusable = getFocusableElements(container);
    if (focusable.length === 0) return;

    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    const active = document.activeElement as HTMLElement;

    if (e.shiftKey) {
      // Shift+Tab: go backwards
      if (active === first || !container.contains(active)) {
        e.preventDefault();
        last.focus();
      }
    } else {
      // Tab: go forwards
      if (active === last || !container.contains(active)) {
        e.preventDefault();
        first.focus();
      }
    }
  };

  return {
    activate() {
      previouslyFocused = document.activeElement as HTMLElement;
      container.addEventListener('keydown', handleKeyDown);

      // Focus first focusable or container itself
      const focusable = getFocusableElements(container);
      if (focusable.length > 0) {
        focusable[0].focus();
      } else {
        container.setAttribute('tabindex', '-1');
        container.focus();
      }
    },
    deactivate() {
      container.removeEventListener('keydown', handleKeyDown);
      previouslyFocused?.focus();
    },
  };
}

// ============ React Hooks ============

/**
 * Hook that traps focus within a container when active.
 */
export function useFocusTrap<T extends HTMLElement>(
  active: boolean
): RefObject<T | null> {
  const containerRef = useRef<T>(null);
  const trapRef = useRef<ReturnType<typeof createFocusTrap> | null>(null);

  useEffect(() => {
    if (!containerRef.current) return;

    if (active) {
      trapRef.current = createFocusTrap(containerRef.current);
      trapRef.current.activate();
    }

    return () => {
      trapRef.current?.deactivate();
      trapRef.current = null;
    };
  }, [active]);

  return containerRef;
}

/**
 * Hook that restores focus to previous element when component unmounts.
 */
export function useFocusRestore(): void {
  const previousRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    previousRef.current = document.activeElement as HTMLElement;

    return () => {
      previousRef.current?.focus();
    };
  }, []);
}

/**
 * Hook that focuses an element on mount.
 */
export function useAutoFocus<T extends HTMLElement>(
  shouldFocus = true
): RefObject<T | null> {
  const ref = useRef<T>(null);

  useEffect(() => {
    if (shouldFocus && ref.current) {
      // Small delay to ensure element is fully rendered
      requestAnimationFrame(() => {
        ref.current?.focus();
      });
    }
  }, [shouldFocus]);

  return ref;
}

/**
 * Hook for managing focus within a list (arrow key navigation).
 */
export function useRovingFocus<T extends HTMLElement>(
  itemCount: number,
  options: {
    orientation?: 'horizontal' | 'vertical' | 'both';
    loop?: boolean;
    onSelect?: (index: number) => void;
  } = {}
): {
  containerProps: {
    onKeyDown: (e: React.KeyboardEvent) => void;
    role: string;
  };
  getItemProps: (index: number) => {
    tabIndex: number;
    ref: (el: T | null) => void;
    onFocus: () => void;
  };
  focusedIndex: number;
  setFocusedIndex: (index: number) => void;
} {
  const { orientation = 'vertical', loop = true, onSelect } = options;
  const itemRefs = useRef<Map<number, T>>(new Map());
  const focusedIndexRef = useRef(0);

  const setFocusedIndex = useCallback((index: number) => {
    focusedIndexRef.current = index;
    const el = itemRefs.current.get(index);
    el?.focus();
  }, []);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      const current = focusedIndexRef.current;
      let next = current;

      const isVertical = orientation === 'vertical' || orientation === 'both';
      const isHorizontal = orientation === 'horizontal' || orientation === 'both';

      switch (e.key) {
        case 'ArrowDown':
          if (isVertical) {
            e.preventDefault();
            next = current + 1;
          }
          break;
        case 'ArrowUp':
          if (isVertical) {
            e.preventDefault();
            next = current - 1;
          }
          break;
        case 'ArrowRight':
          if (isHorizontal) {
            e.preventDefault();
            next = current + 1;
          }
          break;
        case 'ArrowLeft':
          if (isHorizontal) {
            e.preventDefault();
            next = current - 1;
          }
          break;
        case 'Home':
          e.preventDefault();
          next = 0;
          break;
        case 'End':
          e.preventDefault();
          next = itemCount - 1;
          break;
        case 'Enter':
        case ' ':
          e.preventDefault();
          onSelect?.(current);
          return;
        default:
          return;
      }

      // Handle bounds
      if (loop) {
        if (next < 0) next = itemCount - 1;
        if (next >= itemCount) next = 0;
      } else {
        next = Math.max(0, Math.min(itemCount - 1, next));
      }

      if (next !== current) {
        setFocusedIndex(next);
      }
    },
    [itemCount, orientation, loop, onSelect, setFocusedIndex]
  );

  const getItemProps = useCallback(
    (index: number) => ({
      tabIndex: index === focusedIndexRef.current ? 0 : -1,
      ref: (el: T | null) => {
        if (el) {
          itemRefs.current.set(index, el);
        } else {
          itemRefs.current.delete(index);
        }
      },
      onFocus: () => {
        focusedIndexRef.current = index;
      },
    }),
    []
  );

  return {
    containerProps: {
      onKeyDown: handleKeyDown,
      role: 'listbox',
    },
    getItemProps,
    focusedIndex: focusedIndexRef.current,
    setFocusedIndex,
  };
}

// ============ Focus Visibility ============

let hadKeyboardEvent = false;
let isInitialized = false;

/**
 * Initialize focus-visible polyfill behavior.
 * Shows focus ring only for keyboard navigation.
 */
export function initFocusVisible(): void {
  if (isInitialized) return;
  isInitialized = true;

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Tab' || e.key === 'Escape') {
      hadKeyboardEvent = true;
    }
  });

  document.addEventListener('mousedown', () => {
    hadKeyboardEvent = false;
  });

  document.addEventListener(
    'focus',
    (e) => {
      const target = e.target as HTMLElement;
      if (hadKeyboardEvent && target.matches?.(':focus')) {
        target.classList.add('rf-focus-visible');
      }
    },
    true
  );

  document.addEventListener(
    'blur',
    (e) => {
      const target = e.target as HTMLElement;
      target.classList.remove('rf-focus-visible');
    },
    true
  );
}

// ============ Skip Link ============

/**
 * Create a skip link for accessibility.
 * Call this in main.tsx to add skip-to-main functionality.
 */
export function createSkipLink(targetId: string, label = 'Skip to main content'): void {
  const link = document.createElement('a');
  link.href = `#${targetId}`;
  link.className = 'rf-skip-link';
  link.textContent = label;

  link.addEventListener('click', (e) => {
    e.preventDefault();
    const target = document.getElementById(targetId);
    if (target) {
      target.setAttribute('tabindex', '-1');
      target.focus();
      target.removeAttribute('tabindex');
    }
  });

  document.body.insertBefore(link, document.body.firstChild);
}

// Auto-initialize focus visible
if (typeof document !== 'undefined') {
  initFocusVisible();
}
