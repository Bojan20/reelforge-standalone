/**
 * VanEQ Pro - Micro-interactions Hook
 *
 * Adds FabFilter-style micro-interactions:
 * - Button press/release effects
 * - Hover glow animations
 * - Focus rings
 * - Value change feedback
 */

import { useEffect, useCallback, useRef } from 'react';
import gsap from 'gsap';

// ============ Configuration ============

const MICRO_CONFIG = {
  button: {
    pressScale: 0.95,
    pressDuration: 0.08,
    releaseDuration: 0.25,
    releaseEase: 'elastic.out(1, 0.5)',
  },
  hover: {
    duration: 0.2,
    glowColor: 'rgba(0, 212, 255, 0.3)',
  },
  value: {
    flashDuration: 0.15,
    flashColor: 'rgba(0, 212, 255, 0.5)',
  },
};

// ============ Types ============

interface MicroInteractionHandlers {
  onButtonPress: (element: HTMLElement) => void;
  onButtonRelease: (element: HTMLElement) => void;
  onValueChange: (element: HTMLElement) => void;
}

// ============ Hook ============

export function useMicroInteractions(containerRef: React.RefObject<HTMLElement | null>): MicroInteractionHandlers {
  const cleanupRef = useRef<(() => void)[]>([]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      cleanupRef.current.forEach(cleanup => cleanup());
    };
  }, []);

  // Setup auto-interactions for common elements
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const cleanups: (() => void)[] = [];

    // Button interactions
    const buttons = container.querySelectorAll<HTMLElement>(
      'button, .tool-btn, .mode-tab, .ab-btn, .shape-btn, .size-btn, .channel-btn, .db-range-btn'
    );

    buttons.forEach(button => {
      const handleMouseDown = () => {
        gsap.to(button, {
          scale: MICRO_CONFIG.button.pressScale,
          duration: MICRO_CONFIG.button.pressDuration,
          ease: 'power2.in',
        });
      };

      const handleMouseUp = () => {
        gsap.to(button, {
          scale: 1,
          duration: MICRO_CONFIG.button.releaseDuration,
          ease: MICRO_CONFIG.button.releaseEase,
        });
      };

      const handleMouseLeave = () => {
        gsap.to(button, {
          scale: 1,
          duration: 0.15,
          ease: 'power2.out',
        });
      };

      button.addEventListener('mousedown', handleMouseDown);
      button.addEventListener('mouseup', handleMouseUp);
      button.addEventListener('mouseleave', handleMouseLeave);

      cleanups.push(() => {
        button.removeEventListener('mousedown', handleMouseDown);
        button.removeEventListener('mouseup', handleMouseUp);
        button.removeEventListener('mouseleave', handleMouseLeave);
      });
    });

    // Knob container hover effects
    const knobs = container.querySelectorAll<HTMLElement>('.knob-container');

    knobs.forEach(knob => {
      const inner = knob.querySelector('.knob-inner') as HTMLElement;
      if (!inner) return;

      const handleMouseEnter = () => {
        gsap.to(inner, {
          boxShadow: '0 0 25px rgba(0, 212, 255, 0.5), inset 0 -3px 10px rgba(0, 0, 0, 0.4)',
          duration: MICRO_CONFIG.hover.duration,
          ease: 'power2.out',
        });
      };

      const handleMouseLeave = () => {
        gsap.to(inner, {
          boxShadow: '0 0 12px rgba(0, 212, 255, 0.2), inset 0 -3px 10px rgba(0, 0, 0, 0.4)',
          duration: MICRO_CONFIG.hover.duration,
          ease: 'power2.out',
        });
      };

      knob.addEventListener('mouseenter', handleMouseEnter);
      knob.addEventListener('mouseleave', handleMouseLeave);

      cleanups.push(() => {
        knob.removeEventListener('mouseenter', handleMouseEnter);
        knob.removeEventListener('mouseleave', handleMouseLeave);
      });
    });

    // Band pill hover effects
    const pills = container.querySelectorAll<HTMLElement>('.band-pill');

    pills.forEach(pill => {
      const handleMouseEnter = () => {
        gsap.to(pill, {
          y: -2,
          duration: 0.15,
          ease: 'power2.out',
        });
      };

      const handleMouseLeave = () => {
        gsap.to(pill, {
          y: 0,
          duration: 0.2,
          ease: 'power2.out',
        });
      };

      pill.addEventListener('mouseenter', handleMouseEnter);
      pill.addEventListener('mouseleave', handleMouseLeave);

      cleanups.push(() => {
        pill.removeEventListener('mouseenter', handleMouseEnter);
        pill.removeEventListener('mouseleave', handleMouseLeave);
      });
    });

    // Output slider hover
    const slider = container.querySelector<HTMLElement>('.slider-container');
    if (slider) {
      const thumb = slider.querySelector('.slider-thumb') as HTMLElement;
      if (thumb) {
        const handleMouseEnter = () => {
          gsap.to(thumb, {
            scale: 1.3,
            boxShadow: '0 0 10px rgba(0, 212, 255, 0.6)',
            duration: 0.15,
            ease: 'power2.out',
          });
        };

        const handleMouseLeave = () => {
          gsap.to(thumb, {
            scale: 1,
            boxShadow: '0 0 5px rgba(0, 0, 0, 0.5)',
            duration: 0.2,
            ease: 'power2.out',
          });
        };

        slider.addEventListener('mouseenter', handleMouseEnter);
        slider.addEventListener('mouseleave', handleMouseLeave);

        cleanups.push(() => {
          slider.removeEventListener('mouseenter', handleMouseEnter);
          slider.removeEventListener('mouseleave', handleMouseLeave);
        });
      }
    }

    cleanupRef.current = cleanups;

    return () => {
      cleanups.forEach(cleanup => cleanup());
    };
  }, [containerRef]);

  // Manual handlers for programmatic use
  const onButtonPress = useCallback((element: HTMLElement) => {
    gsap.to(element, {
      scale: MICRO_CONFIG.button.pressScale,
      duration: MICRO_CONFIG.button.pressDuration,
      ease: 'power2.in',
    });
  }, []);

  const onButtonRelease = useCallback((element: HTMLElement) => {
    gsap.to(element, {
      scale: 1,
      duration: MICRO_CONFIG.button.releaseDuration,
      ease: MICRO_CONFIG.button.releaseEase,
    });
  }, []);

  const onValueChange = useCallback((element: HTMLElement) => {
    // Flash effect on value change
    gsap.timeline()
      .to(element, {
        textShadow: `0 0 10px ${MICRO_CONFIG.value.flashColor}`,
        duration: MICRO_CONFIG.value.flashDuration,
        ease: 'power2.out',
      })
      .to(element, {
        textShadow: 'none',
        duration: 0.3,
        ease: 'power2.out',
      });
  }, []);

  return {
    onButtonPress,
    onButtonRelease,
    onValueChange,
  };
}

export default useMicroInteractions;
