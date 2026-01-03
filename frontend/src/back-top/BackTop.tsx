/**
 * ReelForge BackTop
 *
 * Scroll to top button:
 * - Show on scroll
 * - Smooth scroll
 * - Custom visibility threshold
 * - Custom content
 *
 * @module back-top/BackTop
 */

import { useState, useEffect, useCallback } from 'react';
import './BackTop.css';

// ============ Types ============

export interface BackTopProps {
  /** Visibility threshold (px from top) */
  visibilityHeight?: number;
  /** Target to scroll */
  target?: () => HTMLElement | Window;
  /** Duration (ms) */
  duration?: number;
  /** On click callback */
  onClick?: () => void;
  /** Custom content */
  children?: React.ReactNode;
  /** Custom class */
  className?: string;
  /** Position */
  position?: {
    right?: number;
    bottom?: number;
    left?: number;
    top?: number;
  };
}

// ============ BackTop Component ============

export function BackTop({
  visibilityHeight = 400,
  target = () => window,
  duration = 450,
  onClick,
  children,
  className = '',
  position = { right: 24, bottom: 24 },
}: BackTopProps) {
  const [visible, setVisible] = useState(false);

  // Check scroll position
  const checkVisibility = useCallback(() => {
    const targetEl = target();
    const scrollTop =
      targetEl === window
        ? window.pageYOffset
        : (targetEl as HTMLElement).scrollTop;

    setVisible(scrollTop >= visibilityHeight);
  }, [target, visibilityHeight]);

  // Scroll to top
  const scrollToTop = useCallback(() => {
    const targetEl = target();
    const startTime = performance.now();
    const startScrollTop =
      targetEl === window
        ? window.pageYOffset
        : (targetEl as HTMLElement).scrollTop;

    const animateScroll = (currentTime: number) => {
      const elapsed = currentTime - startTime;
      const progress = Math.min(elapsed / duration, 1);

      // Ease out cubic
      const easeOut = 1 - Math.pow(1 - progress, 3);
      const scrollTop = startScrollTop * (1 - easeOut);

      if (targetEl === window) {
        window.scrollTo(0, scrollTop);
      } else {
        (targetEl as HTMLElement).scrollTop = scrollTop;
      }

      if (progress < 1) {
        requestAnimationFrame(animateScroll);
      }
    };

    requestAnimationFrame(animateScroll);
    onClick?.();
  }, [target, duration, onClick]);

  // Listen to scroll
  useEffect(() => {
    const targetEl = target();

    targetEl.addEventListener('scroll', checkVisibility, { passive: true });
    checkVisibility();

    return () => {
      targetEl.removeEventListener('scroll', checkVisibility);
    };
  }, [target, checkVisibility]);

  const positionStyle: React.CSSProperties = {
    position: 'fixed',
    ...position,
  };

  return (
    <div
      className={`back-top ${visible ? 'back-top--visible' : ''} ${className}`}
      style={positionStyle}
      onClick={scrollToTop}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => e.key === 'Enter' && scrollToTop()}
      aria-label="Scroll to top"
    >
      {children || (
        <div className="back-top__default">
          <svg viewBox="0 0 24 24" className="back-top__icon">
            <path
              fill="currentColor"
              d="M7.41 15.41L12 10.83l4.59 4.58L18 14l-6-6-6 6z"
            />
          </svg>
        </div>
      )}
    </div>
  );
}

// ============ useBackTop Hook ============

export function useBackTop(threshold = 400) {
  const [showBackTop, setShowBackTop] = useState(false);

  useEffect(() => {
    const handleScroll = () => {
      setShowBackTop(window.pageYOffset >= threshold);
    };

    window.addEventListener('scroll', handleScroll, { passive: true });
    handleScroll();

    return () => window.removeEventListener('scroll', handleScroll);
  }, [threshold]);

  const scrollToTop = useCallback(() => {
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }, []);

  return { showBackTop, scrollToTop };
}

export default BackTop;
