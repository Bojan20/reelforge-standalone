/**
 * ReelForge ClickOutside
 *
 * Detect clicks outside element:
 * - useClickOutside hook
 * - ClickOutside wrapper component
 * - Multiple refs support
 * - Touch events support
 *
 * @module click-outside/ClickOutside
 */

import { useRef, useEffect, useCallback } from 'react';

// ============ Types ============

export interface ClickOutsideProps {
  /** Children to wrap */
  children: React.ReactNode;
  /** Callback when clicked outside */
  onClickOutside: (event: MouseEvent | TouchEvent) => void;
  /** Is active */
  active?: boolean;
  /** Ignore elements with these selectors */
  ignoreSelectors?: string[];
  /** Additional refs to consider as "inside" */
  insideRefs?: React.RefObject<HTMLElement>[];
  /** Listen to mousedown instead of click */
  mouseEvent?: 'click' | 'mousedown' | 'mouseup';
  /** Listen to touch events */
  touchEvent?: 'touchstart' | 'touchend' | false;
  /** Custom class */
  className?: string;
}

export interface UseClickOutsideOptions {
  /** Callback when clicked outside */
  onClickOutside: (event: MouseEvent | TouchEvent) => void;
  /** Is active */
  active?: boolean;
  /** Ignore elements with these selectors */
  ignoreSelectors?: string[];
  /** Additional refs to consider as "inside" */
  insideRefs?: React.RefObject<HTMLElement>[];
  /** Mouse event type */
  mouseEvent?: 'click' | 'mousedown' | 'mouseup';
  /** Touch event type or false to disable */
  touchEvent?: 'touchstart' | 'touchend' | false;
}

// ============ Hook ============

export function useClickOutside<T extends HTMLElement = HTMLElement>({
  onClickOutside,
  active = true,
  ignoreSelectors = [],
  insideRefs = [],
  mouseEvent = 'mousedown',
  touchEvent = 'touchstart',
}: UseClickOutsideOptions) {
  const ref = useRef<T>(null);

  const handleEvent = useCallback(
    (event: MouseEvent | TouchEvent) => {
      const target = event.target as Node;

      // Check if click is inside main ref
      if (ref.current?.contains(target)) {
        return;
      }

      // Check additional inside refs
      for (const insideRef of insideRefs) {
        if (insideRef.current?.contains(target)) {
          return;
        }
      }

      // Check ignored selectors
      if (target instanceof Element) {
        for (const selector of ignoreSelectors) {
          if (target.closest(selector)) {
            return;
          }
        }
      }

      onClickOutside(event);
    },
    [onClickOutside, ignoreSelectors, insideRefs]
  );

  useEffect(() => {
    if (!active) return;

    document.addEventListener(mouseEvent, handleEvent);
    if (touchEvent) {
      document.addEventListener(touchEvent, handleEvent);
    }

    return () => {
      document.removeEventListener(mouseEvent, handleEvent);
      if (touchEvent) {
        document.removeEventListener(touchEvent, handleEvent);
      }
    };
  }, [active, mouseEvent, touchEvent, handleEvent]);

  return ref;
}

// ============ Component ============

export function ClickOutside({
  children,
  onClickOutside,
  active = true,
  ignoreSelectors = [],
  insideRefs = [],
  mouseEvent = 'mousedown',
  touchEvent = 'touchstart',
  className = '',
}: ClickOutsideProps) {
  const ref = useClickOutside<HTMLDivElement>({
    onClickOutside,
    active,
    ignoreSelectors,
    insideRefs,
    mouseEvent,
    touchEvent,
  });

  return (
    <div ref={ref} className={`click-outside ${className}`}>
      {children}
    </div>
  );
}

// ============ useClickAway (Alias) ============

export const useClickAway = useClickOutside;

// ============ useOnClickOutside (Alias with different API) ============

export function useOnClickOutside<T extends HTMLElement = HTMLElement>(
  ref: React.RefObject<T>,
  handler: (event: MouseEvent | TouchEvent) => void,
  active = true
) {
  useEffect(() => {
    if (!active) return;

    const handleEvent = (event: MouseEvent | TouchEvent) => {
      if (ref.current?.contains(event.target as Node)) {
        return;
      }
      handler(event);
    };

    document.addEventListener('mousedown', handleEvent);
    document.addEventListener('touchstart', handleEvent);

    return () => {
      document.removeEventListener('mousedown', handleEvent);
      document.removeEventListener('touchstart', handleEvent);
    };
  }, [ref, handler, active]);
}

export default ClickOutside;
