/**
 * VanEQ Pro - Animation Hook
 *
 * React hook for GSAP animations with automatic cleanup.
 * Provides smooth, FabFilter-style micro-interactions.
 */

import { useRef, useCallback, useEffect } from 'react';
import gsap from 'gsap';
import {
  animateBandNode,
  animateBandSelect,
  animateBandDeselect,
  bandNodeHoverIn,
  bandNodeHoverOut,
  bandNodePress,
  bandNodeRelease,
  knobHoverIn,
  knobHoverOut,
  buttonPress,
  buttonRelease,
  showTooltip,
  hideTooltip,
  killAllAnimations,
  SPRING_CONFIG,
} from './animations';

// ============ Types ============

interface BandNodeRefs {
  [bandId: number]: HTMLElement | null;
}

interface AnimationState {
  selectedBand: number | null;
  hoveredBand: number | null;
  pressedBand: number | null;
}

// ============ Hook ============

export function useVanEQAnimations() {
  // Track refs for band nodes
  const bandNodesRef = useRef<BandNodeRefs>({});
  const animationStateRef = useRef<AnimationState>({
    selectedBand: null,
    hoveredBand: null,
    pressedBand: null,
  });
  const containerRef = useRef<HTMLElement | null>(null);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (containerRef.current) {
        killAllAnimations(containerRef.current);
      }
    };
  }, []);

  // ============ Band Node Registration ============

  const registerBandNode = useCallback((bandId: number, element: HTMLElement | null) => {
    bandNodesRef.current[bandId] = element;
  }, []);

  const registerContainer = useCallback((element: HTMLElement | null) => {
    containerRef.current = element;
  }, []);

  // ============ Band Node Animations ============

  const moveBandNode = useCallback((bandId: number, x: number, y: number, immediate = false) => {
    const element = bandNodesRef.current[bandId];
    animateBandNode(element, x, y, { immediate });
  }, []);

  const selectBand = useCallback((bandId: number) => {
    const state = animationStateRef.current;

    // Deselect previous
    if (state.selectedBand !== null && state.selectedBand !== bandId) {
      const prevElement = bandNodesRef.current[state.selectedBand];
      animateBandDeselect(prevElement);
    }

    // Select new
    const element = bandNodesRef.current[bandId];
    animateBandSelect(element);
    state.selectedBand = bandId;
  }, []);

  const hoverBand = useCallback((bandId: number | null) => {
    const state = animationStateRef.current;

    // Unhover previous
    if (state.hoveredBand !== null && state.hoveredBand !== bandId) {
      const prevElement = bandNodesRef.current[state.hoveredBand];
      bandNodeHoverOut(prevElement);
    }

    // Hover new
    if (bandId !== null) {
      const element = bandNodesRef.current[bandId];
      bandNodeHoverIn(element);
    }

    state.hoveredBand = bandId;
  }, []);

  const pressBand = useCallback((bandId: number) => {
    const state = animationStateRef.current;
    const element = bandNodesRef.current[bandId];
    bandNodePress(element);
    state.pressedBand = bandId;
  }, []);

  const releaseBand = useCallback(() => {
    const state = animationStateRef.current;
    if (state.pressedBand !== null) {
      const element = bandNodesRef.current[state.pressedBand];
      bandNodeRelease(element);
      state.pressedBand = null;
    }
  }, []);

  // ============ Knob Animations ============

  const hoverKnob = useCallback((container: HTMLElement | null, isHovering: boolean) => {
    if (isHovering) {
      knobHoverIn(container);
    } else {
      knobHoverOut(container);
    }
  }, []);

  // ============ Button Animations ============

  const pressButton = useCallback((element: HTMLElement | null) => {
    buttonPress(element);
  }, []);

  const releaseButton = useCallback((element: HTMLElement | null) => {
    buttonRelease(element);
  }, []);

  // ============ Tooltip Animations ============

  const showBandTooltip = useCallback((bandId: number) => {
    const bandNode = bandNodesRef.current[bandId];
    if (!bandNode) return;

    const tooltip = bandNode.querySelector('.band-tooltip') as HTMLElement;
    showTooltip(tooltip);
  }, []);

  const hideBandTooltip = useCallback((bandId: number) => {
    const bandNode = bandNodesRef.current[bandId];
    if (!bandNode) return;

    const tooltip = bandNode.querySelector('.band-tooltip') as HTMLElement;
    hideTooltip(tooltip);
  }, []);

  // ============ Momentum Drag ============

  /**
   * Track velocity for momentum-based animations.
   */
  const velocityTracker = useRef<{
    lastX: number;
    lastY: number;
    lastTime: number;
    velocityX: number;
    velocityY: number;
  }>({
    lastX: 0,
    lastY: 0,
    lastTime: 0,
    velocityX: 0,
    velocityY: 0,
  });

  const trackDragVelocity = useCallback((x: number, y: number) => {
    const now = performance.now();
    const tracker = velocityTracker.current;

    if (tracker.lastTime > 0) {
      const dt = (now - tracker.lastTime) / 1000;
      if (dt > 0 && dt < 0.1) {
        tracker.velocityX = (x - tracker.lastX) / dt;
        tracker.velocityY = (y - tracker.lastY) / dt;
      }
    }

    tracker.lastX = x;
    tracker.lastY = y;
    tracker.lastTime = now;
  }, []);

  const getDragVelocity = useCallback(() => {
    return { ...velocityTracker.current };
  }, []);

  const resetDragVelocity = useCallback(() => {
    velocityTracker.current = {
      lastX: 0,
      lastY: 0,
      lastTime: 0,
      velocityX: 0,
      velocityY: 0,
    };
  }, []);

  // ============ Pulse Animation ============

  const pulseBand = useCallback((bandId: number) => {
    const element = bandNodesRef.current[bandId];
    if (!element) return;

    const core = element.querySelector('.band-node-core') as HTMLElement;
    if (!core) return;

    gsap.timeline()
      .to(core, {
        scale: 1.3,
        boxShadow: '0 0 30px var(--band-node-glow)',
        duration: 0.15,
        ease: 'power2.out',
      })
      .to(core, {
        scale: 1,
        boxShadow: '0 0 20px var(--band-node-glow)',
        duration: 0.4,
        ease: 'elastic.out(1, 0.4)',
      });
  }, []);

  // ============ Shake Animation (for errors/limits) ============

  const shakeBand = useCallback((bandId: number) => {
    const element = bandNodesRef.current[bandId];
    if (!element) return;

    gsap.timeline()
      .to(element, { x: -5, duration: 0.05 })
      .to(element, { x: 5, duration: 0.05 })
      .to(element, { x: -3, duration: 0.05 })
      .to(element, { x: 3, duration: 0.05 })
      .to(element, { x: 0, duration: 0.05 });
  }, []);

  // ============ Glow Animation ============

  const glowBand = useCallback((bandId: number, intensity: number = 1) => {
    const element = bandNodesRef.current[bandId];
    if (!element) return;

    const core = element.querySelector('.band-node-core') as HTMLElement;
    if (!core) return;

    const glowSize = 20 + intensity * 20;

    gsap.to(core, {
      boxShadow: `0 0 ${glowSize}px var(--band-node-glow)`,
      duration: 0.2,
      ease: 'power2.out',
    });
  }, []);

  const resetBandGlow = useCallback((bandId: number) => {
    const element = bandNodesRef.current[bandId];
    if (!element) return;

    const core = element.querySelector('.band-node-core') as HTMLElement;
    if (!core) return;

    gsap.to(core, {
      boxShadow: '0 0 20px var(--band-node-glow)',
      duration: 0.3,
      ease: 'power2.out',
    });
  }, []);

  return {
    // Registration
    registerBandNode,
    registerContainer,

    // Band animations
    moveBandNode,
    selectBand,
    hoverBand,
    pressBand,
    releaseBand,
    pulseBand,
    shakeBand,
    glowBand,
    resetBandGlow,

    // Knob animations
    hoverKnob,

    // Button animations
    pressButton,
    releaseButton,

    // Tooltip animations
    showBandTooltip,
    hideBandTooltip,

    // Momentum tracking
    trackDragVelocity,
    getDragVelocity,
    resetDragVelocity,

    // Config export
    SPRING_CONFIG,
  };
}

export default useVanEQAnimations;
