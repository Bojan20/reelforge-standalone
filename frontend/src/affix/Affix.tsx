/**
 * ReelForge Affix
 *
 * Sticky positioning component:
 * - Stick to top/bottom on scroll
 * - Target container support
 * - Offset configuration
 * - Change callbacks
 *
 * @module affix/Affix
 */

import { useState, useRef, useEffect, useCallback } from 'react';
import './Affix.css';

// ============ Types ============

export interface AffixProps {
  /** Children to make sticky */
  children: React.ReactNode;
  /** Offset from top when affixed */
  offsetTop?: number;
  /** Offset from bottom when affixed */
  offsetBottom?: number;
  /** Target container (default: window) */
  target?: () => HTMLElement | Window | null;
  /** On affix state change */
  onChange?: (affixed: boolean) => void;
  /** Custom class */
  className?: string;
}

export interface AffixState {
  affixed: boolean;
  position: 'top' | 'bottom' | null;
  style: React.CSSProperties;
}

// ============ Affix Component ============

export function Affix({
  children,
  offsetTop,
  offsetBottom,
  target = () => window,
  onChange,
  className = '',
}: AffixProps) {
  const placeholderRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);

  const [state, setState] = useState<AffixState>({
    affixed: false,
    position: null,
    style: {},
  });

  const [placeholderStyle, setPlaceholderStyle] = useState<React.CSSProperties>({});

  // Calculate affix state
  const updatePosition = useCallback(() => {
    const placeholder = placeholderRef.current;
    const content = contentRef.current;
    const targetEl = target();

    if (!placeholder || !content || !targetEl) return;

    const placeholderRect = placeholder.getBoundingClientRect();
    const contentRect = content.getBoundingClientRect();

    let targetTop = 0;
    let targetBottom = window.innerHeight;

    if (targetEl !== window && targetEl instanceof HTMLElement) {
      const targetRect = targetEl.getBoundingClientRect();
      targetTop = targetRect.top;
      targetBottom = targetRect.bottom;
    }

    let newState: AffixState = {
      affixed: false,
      position: null,
      style: {},
    };

    // Check top affix
    if (offsetTop !== undefined) {
      const shouldAffixTop = placeholderRect.top - targetTop < offsetTop;

      if (shouldAffixTop) {
        newState = {
          affixed: true,
          position: 'top',
          style: {
            position: 'fixed',
            top: targetTop + offsetTop,
            left: placeholderRect.left,
            width: placeholderRect.width,
          },
        };
      }
    }

    // Check bottom affix
    if (offsetBottom !== undefined && !newState.affixed) {
      const shouldAffixBottom =
        targetBottom - placeholderRect.bottom < offsetBottom;

      if (shouldAffixBottom) {
        newState = {
          affixed: true,
          position: 'bottom',
          style: {
            position: 'fixed',
            bottom: window.innerHeight - targetBottom + offsetBottom,
            left: placeholderRect.left,
            width: placeholderRect.width,
          },
        };
      }
    }

    // Update state if changed
    if (newState.affixed !== state.affixed) {
      onChange?.(newState.affixed);
    }

    setState(newState);

    // Update placeholder to maintain layout
    if (newState.affixed) {
      setPlaceholderStyle({
        width: contentRect.width,
        height: contentRect.height,
      });
    } else {
      setPlaceholderStyle({});
    }
  }, [offsetTop, offsetBottom, target, state.affixed, onChange]);

  // Listen to scroll and resize
  useEffect(() => {
    const targetEl = target();
    const scrollTarget = targetEl === window ? window : targetEl;

    if (!scrollTarget) return;

    const handleScroll = () => {
      requestAnimationFrame(updatePosition);
    };

    const handleResize = () => {
      updatePosition();
    };

    scrollTarget.addEventListener('scroll', handleScroll, { passive: true });
    window.addEventListener('resize', handleResize);

    // Initial check
    updatePosition();

    return () => {
      scrollTarget.removeEventListener('scroll', handleScroll);
      window.removeEventListener('resize', handleResize);
    };
  }, [target, updatePosition]);

  return (
    <>
      <div
        ref={placeholderRef}
        className="affix__placeholder"
        style={placeholderStyle}
      />
      <div
        ref={contentRef}
        className={`affix ${state.affixed ? 'affix--affixed' : ''} ${
          state.position ? `affix--${state.position}` : ''
        } ${className}`}
        style={state.style}
      >
        {children}
      </div>
    </>
  );
}

// ============ useAffix Hook ============

export interface UseAffixOptions {
  /** Offset from top */
  offsetTop?: number;
  /** Offset from bottom */
  offsetBottom?: number;
  /** Target container */
  target?: () => HTMLElement | Window | null;
}

export function useAffix({
  offsetTop,
  offsetBottom,
  target = () => window,
}: UseAffixOptions = {}) {
  const ref = useRef<HTMLElement>(null);
  const [affixed, setAffixed] = useState(false);
  const [position, setPosition] = useState<'top' | 'bottom' | null>(null);

  useEffect(() => {
    const element = ref.current;
    const targetEl = target();

    if (!element || !targetEl) return;

    const handleScroll = () => {
      const rect = element.getBoundingClientRect();

      let targetTop = 0;
      let targetBottom = window.innerHeight;

      if (targetEl !== window && targetEl instanceof HTMLElement) {
        const targetRect = targetEl.getBoundingClientRect();
        targetTop = targetRect.top;
        targetBottom = targetRect.bottom;
      }

      let newAffixed = false;
      let newPosition: 'top' | 'bottom' | null = null;

      if (offsetTop !== undefined && rect.top - targetTop < offsetTop) {
        newAffixed = true;
        newPosition = 'top';
      } else if (
        offsetBottom !== undefined &&
        targetBottom - rect.bottom < offsetBottom
      ) {
        newAffixed = true;
        newPosition = 'bottom';
      }

      setAffixed(newAffixed);
      setPosition(newPosition);
    };

    const scrollTarget = targetEl === window ? window : targetEl;

    scrollTarget.addEventListener('scroll', handleScroll, { passive: true });
    handleScroll();

    return () => {
      scrollTarget.removeEventListener('scroll', handleScroll);
    };
  }, [offsetTop, offsetBottom, target]);

  return { ref, affixed, position };
}

// ============ StickyBox Component ============

export interface StickyBoxProps {
  /** Children */
  children: React.ReactNode;
  /** Offset from top */
  offsetTop?: number;
  /** Offset from bottom */
  offsetBottom?: number;
  /** Custom class */
  className?: string;
}

export function StickyBox({
  children,
  offsetTop = 0,
  offsetBottom,
  className = '',
}: StickyBoxProps) {
  return (
    <div
      className={`sticky-box ${className}`}
      style={{
        position: 'sticky',
        top: offsetTop,
        bottom: offsetBottom,
      }}
    >
      {children}
    </div>
  );
}

export default Affix;
