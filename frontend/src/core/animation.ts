/**
 * ReelForge Animation System
 *
 * Professional animation utilities powered by GSAP.
 * Provides timeline control, spring physics, and React integration.
 */

import gsap from 'gsap';
import { useRef, useCallback, useEffect } from 'react';

// ============ Re-export GSAP for direct access ============

export { gsap };

// ============ Types ============

export interface AnimationOptions {
  duration?: number;
  delay?: number;
  ease?: string;
  onComplete?: () => void;
  onStart?: () => void;
  onUpdate?: () => void;
}

export interface TimelineOptions {
  repeat?: number;
  yoyo?: boolean;
  paused?: boolean;
  onComplete?: () => void;
}

// ============ Easing Presets (GSAP format) ============

export const easings = {
  // Standard
  linear: 'none',
  ease: 'power1.inOut',
  easeIn: 'power1.in',
  easeOut: 'power1.out',
  easeInOut: 'power1.inOut',

  // Power (cubic-like)
  power2In: 'power2.in',
  power2Out: 'power2.out',
  power2InOut: 'power2.inOut',

  // Quart (snappy)
  power3In: 'power3.in',
  power3Out: 'power3.out',
  power3InOut: 'power3.inOut',

  // Expo (dramatic)
  expoIn: 'expo.in',
  expoOut: 'expo.out',
  expoInOut: 'expo.inOut',

  // Back (overshoot)
  backIn: 'back.in(1.7)',
  backOut: 'back.out(1.7)',
  backInOut: 'back.inOut(1.7)',

  // Elastic
  elasticIn: 'elastic.in(1, 0.3)',
  elasticOut: 'elastic.out(1, 0.3)',
  elasticInOut: 'elastic.inOut(1, 0.3)',

  // Bounce
  bounceIn: 'bounce.in',
  bounceOut: 'bounce.out',
  bounceInOut: 'bounce.inOut',

  // Circ
  circIn: 'circ.in',
  circOut: 'circ.out',
  circInOut: 'circ.inOut',

  // Sine (smooth)
  sineIn: 'sine.in',
  sineOut: 'sine.out',
  sineInOut: 'sine.inOut',
} as const;

export type EasingName = keyof typeof easings;

// ============ Animation Controller ============

export class AnimationController {
  private tween: gsap.core.Tween | null = null;
  private element: HTMLElement;

  constructor(element: HTMLElement) {
    this.element = element;
  }

  /**
   * Animate to target properties.
   */
  to(properties: gsap.TweenVars, options: AnimationOptions = {}): gsap.core.Tween {
    this.kill();

    const { duration = 0.3, delay = 0, ease = easings.power2Out, onComplete, onStart, onUpdate } = options;

    this.tween = gsap.to(this.element, {
      ...properties,
      duration,
      delay,
      ease,
      onComplete,
      onStart,
      onUpdate,
    });

    return this.tween;
  }

  /**
   * Animate from properties to current state.
   */
  from(properties: gsap.TweenVars, options: AnimationOptions = {}): gsap.core.Tween {
    this.kill();

    const { duration = 0.3, delay = 0, ease = easings.power2Out, onComplete, onStart, onUpdate } = options;

    this.tween = gsap.from(this.element, {
      ...properties,
      duration,
      delay,
      ease,
      onComplete,
      onStart,
      onUpdate,
    });

    return this.tween;
  }

  /**
   * Animate from → to.
   */
  fromTo(
    fromProps: gsap.TweenVars,
    toProps: gsap.TweenVars,
    options: AnimationOptions = {}
  ): gsap.core.Tween {
    this.kill();

    const { duration = 0.3, delay = 0, ease = easings.power2Out, onComplete, onStart, onUpdate } = options;

    this.tween = gsap.fromTo(this.element, fromProps, {
      ...toProps,
      duration,
      delay,
      ease,
      onComplete,
      onStart,
      onUpdate,
    });

    return this.tween;
  }

  /**
   * Kill current animation.
   */
  kill(): void {
    this.tween?.kill();
    this.tween = null;
  }

  /**
   * Pause current animation.
   */
  pause(): void {
    this.tween?.pause();
  }

  /**
   * Resume paused animation.
   */
  play(): void {
    this.tween?.play();
  }

  /**
   * Reverse animation.
   */
  reverse(): void {
    this.tween?.reverse();
  }

  /**
   * Get current progress (0-1).
   */
  progress(): number {
    return this.tween?.progress() ?? 0;
  }
}

// ============ Timeline Builder ============

export class TimelineBuilder {
  private timeline: gsap.core.Timeline;

  constructor(options: TimelineOptions = {}) {
    this.timeline = gsap.timeline({
      repeat: options.repeat,
      yoyo: options.yoyo,
      paused: options.paused ?? false,
      onComplete: options.onComplete,
    });
  }

  /**
   * Add animation to timeline.
   */
  add(
    target: gsap.TweenTarget,
    properties: gsap.TweenVars,
    position?: gsap.Position
  ): TimelineBuilder {
    this.timeline.to(target, properties, position);
    return this;
  }

  /**
   * Add from animation.
   */
  addFrom(
    target: gsap.TweenTarget,
    properties: gsap.TweenVars,
    position?: gsap.Position
  ): TimelineBuilder {
    this.timeline.from(target, properties, position);
    return this;
  }

  /**
   * Add label for positioning.
   */
  addLabel(label: string, position?: gsap.Position): TimelineBuilder {
    this.timeline.addLabel(label, position);
    return this;
  }

  /**
   * Add pause.
   */
  addPause(position?: gsap.Position): TimelineBuilder {
    this.timeline.addPause(position);
    return this;
  }

  /**
   * Play timeline.
   */
  play(): gsap.core.Timeline {
    return this.timeline.play();
  }

  /**
   * Pause timeline.
   */
  pause(): gsap.core.Timeline {
    return this.timeline.pause();
  }

  /**
   * Reverse timeline.
   */
  reverse(): gsap.core.Timeline {
    return this.timeline.reverse();
  }

  /**
   * Kill timeline.
   */
  kill(): void {
    this.timeline.kill();
  }

  /**
   * Get underlying GSAP timeline.
   */
  getTimeline(): gsap.core.Timeline {
    return this.timeline;
  }
}

// ============ Helper Functions ============

/**
 * Create animation controller for element.
 */
export function animate(element: HTMLElement): AnimationController {
  return new AnimationController(element);
}

/**
 * Create timeline.
 */
export function timeline(options?: TimelineOptions): TimelineBuilder {
  return new TimelineBuilder(options);
}

/**
 * Fade in element.
 */
export function fadeIn(element: HTMLElement, options: AnimationOptions = {}): gsap.core.Tween {
  return gsap.from(element, {
    opacity: 0,
    duration: options.duration ?? 0.2,
    delay: options.delay ?? 0,
    ease: options.ease ?? easings.power2Out,
    onComplete: options.onComplete,
  });
}

/**
 * Fade out element.
 */
export function fadeOut(element: HTMLElement, options: AnimationOptions = {}): gsap.core.Tween {
  return gsap.to(element, {
    opacity: 0,
    duration: options.duration ?? 0.2,
    delay: options.delay ?? 0,
    ease: options.ease ?? easings.power2Out,
    onComplete: options.onComplete,
  });
}

/**
 * Scale in from center.
 */
export function scaleIn(element: HTMLElement, options: AnimationOptions = {}): gsap.core.Tween {
  return gsap.from(element, {
    scale: 0.9,
    opacity: 0,
    duration: options.duration ?? 0.25,
    delay: options.delay ?? 0,
    ease: options.ease ?? easings.backOut,
    onComplete: options.onComplete,
  });
}

/**
 * Scale out to center.
 */
export function scaleOut(element: HTMLElement, options: AnimationOptions = {}): gsap.core.Tween {
  return gsap.to(element, {
    scale: 0.9,
    opacity: 0,
    duration: options.duration ?? 0.15,
    delay: options.delay ?? 0,
    ease: options.ease ?? easings.power2In,
    onComplete: options.onComplete,
  });
}

/**
 * Slide in from direction.
 */
export function slideIn(
  element: HTMLElement,
  direction: 'up' | 'down' | 'left' | 'right' = 'up',
  options: AnimationOptions = {}
): gsap.core.Tween {
  const props: gsap.TweenVars = { opacity: 0 };

  switch (direction) {
    case 'up':
      props.y = 20;
      break;
    case 'down':
      props.y = -20;
      break;
    case 'left':
      props.x = 20;
      break;
    case 'right':
      props.x = -20;
      break;
  }

  return gsap.from(element, {
    ...props,
    duration: options.duration ?? 0.3,
    delay: options.delay ?? 0,
    ease: options.ease ?? easings.power2Out,
    onComplete: options.onComplete,
  });
}

/**
 * Slide out to direction.
 */
export function slideOut(
  element: HTMLElement,
  direction: 'up' | 'down' | 'left' | 'right' = 'up',
  options: AnimationOptions = {}
): gsap.core.Tween {
  const props: gsap.TweenVars = { opacity: 0 };

  switch (direction) {
    case 'up':
      props.y = -20;
      break;
    case 'down':
      props.y = 20;
      break;
    case 'left':
      props.x = -20;
      break;
    case 'right':
      props.x = 20;
      break;
  }

  return gsap.to(element, {
    ...props,
    duration: options.duration ?? 0.2,
    delay: options.delay ?? 0,
    ease: options.ease ?? easings.power2In,
    onComplete: options.onComplete,
  });
}

/**
 * Bounce attention animation.
 */
export function bounce(element: HTMLElement, options: AnimationOptions = {}): gsap.core.Tween {
  return gsap.to(element, {
    keyframes: [
      { scale: 1, duration: 0 },
      { scale: 1.1, duration: 0.12 },
      { scale: 0.95, duration: 0.12 },
      { scale: 1, duration: 0.16 },
    ],
    ease: easings.power2Out,
    onComplete: options.onComplete,
  });
}

/**
 * Shake attention animation.
 */
export function shake(element: HTMLElement, options: AnimationOptions = {}): gsap.core.Tween {
  return gsap.to(element, {
    keyframes: [
      { x: 0, duration: 0 },
      { x: -8, duration: 0.08 },
      { x: 8, duration: 0.08 },
      { x: -4, duration: 0.08 },
      { x: 4, duration: 0.08 },
      { x: 0, duration: 0.08 },
    ],
    ease: easings.power2Out,
    onComplete: options.onComplete,
  });
}

/**
 * Pulse animation (for loading states).
 */
export function pulse(
  element: HTMLElement,
  options: { duration?: number; repeat?: number } = {}
): gsap.core.Tween {
  return gsap.to(element, {
    opacity: 0.5,
    duration: (options.duration ?? 1) / 2,
    repeat: options.repeat ?? -1,
    yoyo: true,
    ease: easings.sineInOut,
  });
}

// ============ Stagger Utility ============

/**
 * Stagger animations across multiple elements.
 */
export function stagger(
  elements: HTMLElement[] | NodeList | string,
  properties: gsap.TweenVars,
  options: AnimationOptions & { stagger?: number | gsap.StaggerVars } = {}
): gsap.core.Tween {
  return gsap.to(elements, {
    ...properties,
    duration: options.duration ?? 0.3,
    delay: options.delay ?? 0,
    ease: options.ease ?? easings.power2Out,
    stagger: options.stagger ?? 0.05,
    onComplete: options.onComplete,
  });
}

/**
 * Stagger in (from).
 */
export function staggerIn(
  elements: HTMLElement[] | NodeList | string,
  properties: gsap.TweenVars,
  options: AnimationOptions & { stagger?: number | gsap.StaggerVars } = {}
): gsap.core.Tween {
  return gsap.from(elements, {
    ...properties,
    duration: options.duration ?? 0.3,
    delay: options.delay ?? 0,
    ease: options.ease ?? easings.power2Out,
    stagger: options.stagger ?? 0.05,
    onComplete: options.onComplete,
  });
}

// ============ Quick Set (no animation) ============

/**
 * Immediately set properties without animation.
 */
export function set(element: gsap.TweenTarget, properties: gsap.TweenVars): void {
  gsap.set(element, properties);
}

// ============ Kill All ============

/**
 * Kill all animations on target.
 */
export function killAll(target?: gsap.TweenTarget): void {
  gsap.killTweensOf(target ?? '*');
}

// ============ React Hooks ============

/**
 * Hook for animating an element with GSAP.
 */
export function useGsap<T extends HTMLElement>(): {
  ref: React.RefObject<T | null>;
  gsap: typeof gsap;
  to: (props: gsap.TweenVars, options?: AnimationOptions) => gsap.core.Tween | undefined;
  from: (props: gsap.TweenVars, options?: AnimationOptions) => gsap.core.Tween | undefined;
  timeline: (options?: TimelineOptions) => TimelineBuilder;
  fadeIn: (options?: AnimationOptions) => gsap.core.Tween | undefined;
  fadeOut: (options?: AnimationOptions) => gsap.core.Tween | undefined;
  scaleIn: (options?: AnimationOptions) => gsap.core.Tween | undefined;
  scaleOut: (options?: AnimationOptions) => gsap.core.Tween | undefined;
  bounce: (options?: AnimationOptions) => gsap.core.Tween | undefined;
  shake: (options?: AnimationOptions) => gsap.core.Tween | undefined;
  kill: () => void;
} {
  const ref = useRef<T>(null);
  const tweensRef = useRef<gsap.core.Tween[]>([]);

  const track = useCallback((tween: gsap.core.Tween) => {
    tweensRef.current.push(tween);
    return tween;
  }, []);

  const kill = useCallback(() => {
    tweensRef.current.forEach((t) => t.kill());
    tweensRef.current = [];
  }, []);

  useEffect(() => {
    return () => kill();
  }, [kill]);

  return {
    ref,
    gsap,
    to: (props, options) => {
      if (!ref.current) return;
      return track(animate(ref.current).to(props, options));
    },
    from: (props, options) => {
      if (!ref.current) return;
      return track(animate(ref.current).from(props, options));
    },
    timeline: (options) => new TimelineBuilder(options),
    fadeIn: (options) => {
      if (!ref.current) return;
      return track(fadeIn(ref.current, options));
    },
    fadeOut: (options) => {
      if (!ref.current) return;
      return track(fadeOut(ref.current, options));
    },
    scaleIn: (options) => {
      if (!ref.current) return;
      return track(scaleIn(ref.current, options));
    },
    scaleOut: (options) => {
      if (!ref.current) return;
      return track(scaleOut(ref.current, options));
    },
    bounce: (options) => {
      if (!ref.current) return;
      return track(bounce(ref.current, options));
    },
    shake: (options) => {
      if (!ref.current) return;
      return track(shake(ref.current, options));
    },
    kill,
  };
}

/**
 * Hook for entrance animation on mount.
 */
export function useEntranceAnimation<T extends HTMLElement>(
  animation: 'fadeIn' | 'scaleIn' | 'slideIn' = 'fadeIn',
  options: AnimationOptions & { direction?: 'up' | 'down' | 'left' | 'right' } = {}
): React.RefObject<T | null> {
  const ref = useRef<T>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    // Start invisible
    gsap.set(el, { opacity: 0 });

    // Animate in
    switch (animation) {
      case 'fadeIn':
        fadeIn(el, options);
        break;
      case 'scaleIn':
        scaleIn(el, options);
        break;
      case 'slideIn':
        slideIn(el, options.direction ?? 'up', options);
        break;
    }

    return () => {
      gsap.killTweensOf(el);
    };
  }, [animation, options]);

  return ref;
}

/**
 * Hook for scroll-triggered animations.
 */
export function useScrollAnimation<T extends HTMLElement>(
  animation: gsap.TweenVars,
  options: {
    trigger?: string;
    start?: string;
    end?: string;
    scrub?: boolean | number;
  } = {}
): React.RefObject<T | null> {
  const ref = useRef<T>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    // Note: For ScrollTrigger, you'd need to register the plugin
    // gsap.registerPlugin(ScrollTrigger);

    const tween = gsap.from(el, {
      ...animation,
      scrollTrigger: {
        trigger: options.trigger ?? el,
        start: options.start ?? 'top 80%',
        end: options.end ?? 'bottom 20%',
        scrub: options.scrub ?? false,
      },
    });

    return () => {
      tween.kill();
    };
  }, [animation, options]);

  return ref;
}

// ============ Legacy compatibility (useAnimation) ============

export const useAnimation = useGsap;
