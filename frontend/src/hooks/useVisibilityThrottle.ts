/**
 * Visibility-based Animation Throttle Hook
 *
 * Pauses or throttles animations when:
 * - Tab is hidden (document.hidden)
 * - Window loses focus
 *
 * Benefits:
 * - Reduces CPU usage when app is in background
 * - Saves battery on laptops/mobile
 * - Prevents unnecessary renders
 */

import { useState, useEffect, useCallback, useRef } from 'react';

export interface VisibilityState {
  /** Whether animations should run at full speed */
  isActive: boolean;
  /** Whether tab is visible */
  isVisible: boolean;
  /** Whether window has focus */
  hasFocus: boolean;
}

/**
 * Hook to track visibility and focus state for animation throttling.
 *
 * @returns VisibilityState object
 */
export function useVisibilityState(): VisibilityState {
  const [isVisible, setIsVisible] = useState(!document.hidden);
  const [hasFocus, setHasFocus] = useState(document.hasFocus());

  useEffect(() => {
    const handleVisibilityChange = () => {
      setIsVisible(!document.hidden);
    };

    const handleFocus = () => setHasFocus(true);
    const handleBlur = () => setHasFocus(false);

    document.addEventListener('visibilitychange', handleVisibilityChange);
    window.addEventListener('focus', handleFocus);
    window.addEventListener('blur', handleBlur);

    return () => {
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      window.removeEventListener('focus', handleFocus);
      window.removeEventListener('blur', handleBlur);
    };
  }, []);

  return {
    isActive: isVisible && hasFocus,
    isVisible,
    hasFocus,
  };
}

/**
 * Hook for visibility-aware animation frame loop.
 *
 * When tab is hidden or window loses focus:
 * - Animation pauses completely if pauseWhenHidden is true
 * - Animation runs at reduced rate if throttleRate is set
 *
 * @param callback - Animation callback, receives delta time in ms
 * @param options - Configuration options
 */
export function useThrottledAnimationFrame(
  callback: (deltaMs: number) => void,
  options: {
    /** Whether animation is enabled */
    enabled?: boolean;
    /** Pause completely when hidden (default: true) */
    pauseWhenHidden?: boolean;
    /** Frame rate when throttled, in fps (default: 10) */
    throttledFps?: number;
  } = {}
): void {
  const {
    enabled = true,
    pauseWhenHidden = true,
    throttledFps = 10,
  } = options;

  const { isActive, isVisible } = useVisibilityState();
  const callbackRef = useRef(callback);
  callbackRef.current = callback;

  const lastTimeRef = useRef<number>(0);
  const animationRef = useRef<number | null>(null);

  const throttleInterval = 1000 / throttledFps;

  const animate = useCallback((time: number) => {
    const delta = time - lastTimeRef.current;

    // Determine if we should run this frame
    const shouldThrottle = !isActive && !pauseWhenHidden;
    const minInterval = shouldThrottle ? throttleInterval : 0;

    if (delta >= minInterval) {
      callbackRef.current(delta);
      lastTimeRef.current = time;
    }

    animationRef.current = requestAnimationFrame(animate);
  }, [isActive, pauseWhenHidden, throttleInterval]);

  useEffect(() => {
    if (!enabled) {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
        animationRef.current = null;
      }
      return;
    }

    // Pause when hidden (if pauseWhenHidden is true)
    if (pauseWhenHidden && !isVisible) {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
        animationRef.current = null;
      }
      return;
    }

    // Start animation loop
    lastTimeRef.current = performance.now();
    animationRef.current = requestAnimationFrame(animate);

    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
        animationRef.current = null;
      }
    };
  }, [enabled, isVisible, pauseWhenHidden, animate]);
}

/**
 * Simple hook that returns whether animations should run.
 * Use this for conditional rendering or to pause animations.
 */
export function useShouldAnimate(): boolean {
  const { isActive } = useVisibilityState();
  return isActive;
}
