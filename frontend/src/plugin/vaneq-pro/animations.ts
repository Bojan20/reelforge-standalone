/**
 * VanEQ Pro - GSAP Animation Module
 *
 * Premium FabFilter-style animations:
 * - Spring physics for band nodes
 * - Elastic easing for knobs
 * - Momentum-based dragging
 * - Micro-interactions
 */

import gsap from 'gsap';

// ============ Configuration ============

/** Spring physics config for different elements */
export const SPRING_CONFIG = {
  // Band nodes - bouncy, responsive
  bandNode: {
    duration: 0.6,
    ease: 'elastic.out(1, 0.5)',
  },
  // Knobs - smooth, professional
  knob: {
    duration: 0.3,
    ease: 'power2.out',
  },
  // Tooltips - quick, snappy
  tooltip: {
    duration: 0.2,
    ease: 'back.out(1.5)',
  },
  // UI panels - elegant slide
  panel: {
    duration: 0.4,
    ease: 'power3.out',
  },
  // Spectrum - fluid
  spectrum: {
    duration: 0.1,
    ease: 'none',
  },
} as const;

/** Micro-interaction timings */
const MICRO = {
  hover: 0.15,
  press: 0.08,
  release: 0.25,
};

// ============ Band Node Animations ============

/**
 * Animate band node to new position with spring physics.
 */
export function animateBandNode(
  element: HTMLElement | null,
  x: number,
  y: number,
  options?: {
    immediate?: boolean;
    onComplete?: () => void;
  }
): gsap.core.Tween | null {
  if (!element) return null;

  if (options?.immediate) {
    gsap.set(element, { left: `${x}%`, top: `${y}%` });
    options.onComplete?.();
    return null;
  }

  return gsap.to(element, {
    left: `${x}%`,
    top: `${y}%`,
    ...SPRING_CONFIG.bandNode,
    onComplete: options?.onComplete,
  });
}

/**
 * Animate band node selection ring.
 */
export function animateBandSelect(element: HTMLElement | null): gsap.core.Timeline | null {
  if (!element) return null;

  const ring = element.querySelector('.band-node-ring') as HTMLElement;
  const core = element.querySelector('.band-node-core') as HTMLElement;

  if (!ring || !core) return null;

  const tl = gsap.timeline();

  // Scale up ring with elastic bounce
  tl.fromTo(ring,
    { scale: 1, opacity: 0 },
    { scale: 1.6, opacity: 1, duration: 0.4, ease: 'elastic.out(1, 0.4)' }
  );

  // Pulse core
  tl.to(core, {
    scale: 1.1,
    duration: 0.15,
    ease: 'power2.out',
  }, 0);
  tl.to(core, {
    scale: 1,
    duration: 0.3,
    ease: 'elastic.out(1, 0.5)',
  }, 0.15);

  return tl;
}

/**
 * Animate band node deselection.
 */
export function animateBandDeselect(element: HTMLElement | null): gsap.core.Tween | null {
  if (!element) return null;

  const ring = element.querySelector('.band-node-ring') as HTMLElement;
  if (!ring) return null;

  return gsap.to(ring, {
    scale: 1,
    opacity: 0,
    duration: 0.2,
    ease: 'power2.in',
  });
}

/**
 * Hover effect for band node.
 */
export function bandNodeHoverIn(element: HTMLElement | null): gsap.core.Tween | null {
  if (!element) return null;

  return gsap.to(element, {
    scale: 1.15,
    duration: MICRO.hover,
    ease: 'power2.out',
  });
}

export function bandNodeHoverOut(element: HTMLElement | null): gsap.core.Tween | null {
  if (!element) return null;

  return gsap.to(element, {
    scale: 1,
    duration: MICRO.release,
    ease: 'elastic.out(1, 0.5)',
  });
}

/**
 * Press effect for band node.
 */
export function bandNodePress(element: HTMLElement | null): gsap.core.Tween | null {
  if (!element) return null;

  return gsap.to(element, {
    scale: 0.9,
    duration: MICRO.press,
    ease: 'power2.in',
  });
}

export function bandNodeRelease(element: HTMLElement | null): gsap.core.Tween | null {
  if (!element) return null;

  return gsap.to(element, {
    scale: 1,
    duration: MICRO.release,
    ease: 'elastic.out(1.2, 0.4)',
  });
}

// ============ Knob Animations ============

/**
 * Animate knob rotation with momentum.
 */
export function animateKnobRotation(
  indicator: HTMLElement | null,
  rotation: number,
  options?: {
    immediate?: boolean;
    momentum?: number; // Extra rotation from velocity
  }
): gsap.core.Tween | null {
  if (!indicator) return null;

  const finalRotation = rotation + (options?.momentum ?? 0);

  if (options?.immediate) {
    gsap.set(indicator, { '--rotation': `${rotation}deg` });
    return null;
  }

  // If momentum, overshoot then settle
  if (options?.momentum && Math.abs(options.momentum) > 1) {
    return gsap.to(indicator, {
      '--rotation': `${finalRotation}deg`,
      duration: 0.5,
      ease: 'elastic.out(1, 0.6)',
    });
  }

  return gsap.to(indicator, {
    '--rotation': `${rotation}deg`,
    ...SPRING_CONFIG.knob,
  });
}

/**
 * Animate knob value arc.
 */
export function animateKnobArc(
  arc: HTMLElement | null,
  degrees: number
): gsap.core.Tween | null {
  if (!arc) return null;

  return gsap.to(arc, {
    '--arc-deg': `${degrees}deg`,
    duration: 0.15,
    ease: 'power2.out',
  });
}

/**
 * Knob hover glow effect.
 */
export function knobHoverIn(container: HTMLElement | null): gsap.core.Timeline | null {
  if (!container) return null;

  const inner = container.querySelector('.knob-inner') as HTMLElement;
  const bg = container.querySelector('.knob-bg') as HTMLElement;

  if (!inner) return null;

  const tl = gsap.timeline();

  tl.to(inner, {
    boxShadow: '0 0 20px rgba(0, 212, 255, 0.4), inset 0 -3px 10px rgba(0, 0, 0, 0.4)',
    duration: MICRO.hover,
    ease: 'power2.out',
  });

  if (bg) {
    tl.to(bg, {
      opacity: 0.8,
      duration: MICRO.hover,
      ease: 'power2.out',
    }, 0);
  }

  return tl;
}

export function knobHoverOut(container: HTMLElement | null): gsap.core.Timeline | null {
  if (!container) return null;

  const inner = container.querySelector('.knob-inner') as HTMLElement;
  const bg = container.querySelector('.knob-bg') as HTMLElement;

  if (!inner) return null;

  const tl = gsap.timeline();

  tl.to(inner, {
    boxShadow: '0 0 12px rgba(0, 212, 255, 0.2), inset 0 -3px 10px rgba(0, 0, 0, 0.4)',
    duration: MICRO.release,
    ease: 'power2.out',
  });

  if (bg) {
    tl.to(bg, {
      opacity: 0.6,
      duration: MICRO.release,
      ease: 'power2.out',
    }, 0);
  }

  return tl;
}

// ============ Tooltip Animations ============

/**
 * Show tooltip with spring.
 */
export function showTooltip(element: HTMLElement | null): gsap.core.Tween | null {
  if (!element) return null;

  gsap.set(element, { display: 'block' });

  return gsap.fromTo(element,
    { opacity: 0, scale: 0.8, y: 10 },
    {
      opacity: 1,
      scale: 1,
      y: 0,
      ...SPRING_CONFIG.tooltip,
    }
  );
}

/**
 * Hide tooltip.
 */
export function hideTooltip(element: HTMLElement | null): gsap.core.Tween | null {
  if (!element) return null;

  return gsap.to(element, {
    opacity: 0,
    scale: 0.9,
    y: 5,
    duration: 0.15,
    ease: 'power2.in',
    onComplete: () => {
      gsap.set(element, { display: 'none' });
    },
  });
}

// ============ UI Panel Animations ============

/**
 * Animate panel slide in.
 */
export function panelSlideIn(
  element: HTMLElement | null,
  direction: 'left' | 'right' | 'up' | 'down' = 'up'
): gsap.core.Tween | null {
  if (!element) return null;

  const offset = 30;
  const from: Record<string, number> = { opacity: 0 };

  switch (direction) {
    case 'left': from.x = offset; break;
    case 'right': from.x = -offset; break;
    case 'up': from.y = offset; break;
    case 'down': from.y = -offset; break;
  }

  return gsap.fromTo(element, from, {
    opacity: 1,
    x: 0,
    y: 0,
    ...SPRING_CONFIG.panel,
  });
}

/**
 * Animate panel slide out.
 */
export function panelSlideOut(
  element: HTMLElement | null,
  direction: 'left' | 'right' | 'up' | 'down' = 'down'
): gsap.core.Tween | null {
  if (!element) return null;

  const offset = 20;
  const to: Record<string, number> = { opacity: 0 };

  switch (direction) {
    case 'left': to.x = -offset; break;
    case 'right': to.x = offset; break;
    case 'up': to.y = -offset; break;
    case 'down': to.y = offset; break;
  }

  return gsap.to(element, {
    ...to,
    duration: 0.2,
    ease: 'power2.in',
  });
}

// ============ Button Micro-interactions ============

/**
 * Button press effect.
 */
export function buttonPress(element: HTMLElement | null): gsap.core.Timeline | null {
  if (!element) return null;

  const tl = gsap.timeline();

  tl.to(element, {
    scale: 0.95,
    duration: MICRO.press,
    ease: 'power2.in',
  });

  return tl;
}

/**
 * Button release effect.
 */
export function buttonRelease(element: HTMLElement | null): gsap.core.Tween | null {
  if (!element) return null;

  return gsap.to(element, {
    scale: 1,
    duration: MICRO.release,
    ease: 'elastic.out(1, 0.5)',
  });
}

/**
 * Button ripple effect.
 */
export function buttonRipple(
  element: HTMLElement | null,
  x: number,
  y: number,
  color: string = 'rgba(255, 255, 255, 0.3)'
): gsap.core.Timeline | null {
  if (!element) return null;

  // Create ripple element
  const ripple = document.createElement('div');
  ripple.style.cssText = `
    position: absolute;
    left: ${x}px;
    top: ${y}px;
    width: 0;
    height: 0;
    border-radius: 50%;
    background: ${color};
    transform: translate(-50%, -50%);
    pointer-events: none;
  `;

  element.style.position = 'relative';
  element.style.overflow = 'hidden';
  element.appendChild(ripple);

  const tl = gsap.timeline({
    onComplete: () => ripple.remove(),
  });

  tl.to(ripple, {
    width: 150,
    height: 150,
    opacity: 0,
    duration: 0.6,
    ease: 'power2.out',
  });

  return tl;
}

// ============ Value Change Animation ============

/**
 * Animate numeric value change with counting effect.
 */
export function animateValue(
  element: HTMLElement | null,
  from: number,
  to: number,
  options?: {
    duration?: number;
    decimals?: number;
    prefix?: string;
    suffix?: string;
  }
): gsap.core.Tween | null {
  if (!element) return null;

  const duration = options?.duration ?? 0.3;
  const decimals = options?.decimals ?? 1;
  const prefix = options?.prefix ?? '';
  const suffix = options?.suffix ?? '';

  const obj = { value: from };

  return gsap.to(obj, {
    value: to,
    duration,
    ease: 'power2.out',
    onUpdate: () => {
      const formatted = obj.value.toFixed(decimals);
      element.textContent = `${prefix}${formatted}${suffix}`;
    },
  });
}

// ============ Spectrum Animation ============

/**
 * Create smooth spectrum animation context.
 * Returns update function for RAF loop.
 */
export function createSpectrumAnimator(
  barCount: number,
  options?: {
    attack?: number;
    release?: number;
  }
): {
  update: (values: Float32Array | number[]) => Float32Array;
  getValues: () => Float32Array;
} {
  const attack = options?.attack ?? 0.3;
  const release = options?.release ?? 0.1;
  const smoothed = new Float32Array(barCount);

  return {
    update: (values: Float32Array | number[]) => {
      for (let i = 0; i < barCount; i++) {
        const target = values[i] ?? 0;
        const speed = target > smoothed[i] ? attack : release;
        smoothed[i] += (target - smoothed[i]) * speed;
      }
      return smoothed;
    },
    getValues: () => smoothed,
  };
}

// ============ Stagger Animations ============

/**
 * Stagger animate multiple elements.
 */
export function staggerIn(
  elements: HTMLElement[] | NodeListOf<HTMLElement>,
  options?: {
    stagger?: number;
    from?: 'start' | 'end' | 'center' | 'random';
  }
): gsap.core.Tween | null {
  if (!elements || elements.length === 0) return null;

  return gsap.fromTo(elements,
    { opacity: 0, y: 20, scale: 0.9 },
    {
      opacity: 1,
      y: 0,
      scale: 1,
      duration: 0.4,
      ease: 'back.out(1.5)',
      stagger: {
        amount: options?.stagger ?? 0.3,
        from: options?.from ?? 'start',
      },
    }
  );
}

export function staggerOut(
  elements: HTMLElement[] | NodeListOf<HTMLElement>,
  options?: {
    stagger?: number;
    from?: 'start' | 'end' | 'center' | 'random';
  }
): gsap.core.Tween | null {
  if (!elements || elements.length === 0) return null;

  return gsap.to(elements, {
    opacity: 0,
    y: -10,
    scale: 0.95,
    duration: 0.2,
    ease: 'power2.in',
    stagger: {
      amount: options?.stagger ?? 0.15,
      from: options?.from ?? 'end',
    },
  });
}

// ============ EQ Curve Animation ============

/**
 * Animate EQ curve morph between two states.
 */
export function morphEqCurve(
  pathElement: SVGPathElement | null,
  fromPath: string,
  toPath: string,
  duration: number = 0.4
): gsap.core.Tween | null {
  if (!pathElement) return null;

  return gsap.fromTo(pathElement,
    { attr: { d: fromPath } },
    { attr: { d: toPath }, duration, ease: 'power2.out' }
  );
}

// ============ Utility ============

/**
 * Kill all animations on element.
 */
export function killAnimations(element: HTMLElement | null): void {
  if (element) {
    gsap.killTweensOf(element);
  }
}

/**
 * Kill all animations on elements and children.
 */
export function killAllAnimations(container: HTMLElement | null): void {
  if (container) {
    gsap.killTweensOf(container);
    gsap.killTweensOf(container.querySelectorAll('*'));
  }
}
