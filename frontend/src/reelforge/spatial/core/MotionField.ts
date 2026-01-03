/**
 * ReelForge Spatial System - Motion Field
 * Extracts motion data from multiple sources with confidence scoring.
 *
 * @module reelforge/spatial/core
 */

import type {
  RFSpatialEvent,
  MotionFrame,
  MotionSource,
} from '../types';
import { AnchorRegistry } from '../adapters/AnchorRegistry';
import { clamp01, lerp, calculateVelocity } from '../utils/math';

/**
 * GSAP animation target interface.
 */
interface GSAPTarget {
  _gsap?: {
    x?: number;
    y?: number;
  };
}

/**
 * Web Animation API Keyframe effect.
 */
interface AnimationEffectReadOnly {
  getComputedTiming(): { progress: number | null };
}

/**
 * Motion extraction result with source and confidence.
 */
interface MotionExtraction {
  frame: MotionFrame;
  source: MotionSource;
  confidence: number;
}

/**
 * MotionField extracts position/velocity from multiple sources:
 * 1. Explicit coordinates (best)
 * 2. Progress interpolation between anchors
 * 3. Anchor tracking (position changes over time)
 * 4. Transform harvesting (GSAP/Web Animations)
 * 5. Heuristics (state machine fallback)
 */
export class MotionField {
  /** Anchor registry for position lookup */
  private registry: AnchorRegistry;

  /** Previous frames per event for velocity */
  private prevFrames = new Map<string, MotionFrame>();

  /** GSAP animation targets (for transform harvesting) */
  private gsapTargets = new Map<string, WeakRef<GSAPTarget>>();

  /** Web Animation references */
  private webAnimations = new Map<string, WeakRef<Animation>>();

  /** Heuristic position defaults per intent */
  private heuristicDefaults = new Map<string, { x: number; y: number }>();

  /** Cleanup interval handle */
  private cleanupInterval: ReturnType<typeof setInterval> | null = null;

  /** Cleanup interval in ms (30 seconds) */
  private static readonly CLEANUP_INTERVAL_MS = 30_000;

  constructor(registry: AnchorRegistry) {
    this.registry = registry;
    this.setupDefaultHeuristics();
    this.startCleanupInterval();
  }

  /**
   * Start periodic cleanup of stale WeakRef entries.
   */
  private startCleanupInterval(): void {
    this.cleanupInterval = setInterval(() => {
      this.cleanupStaleRefs();
    }, MotionField.CLEANUP_INTERVAL_MS);
  }

  /**
   * Remove stale WeakRef entries from maps.
   * WeakRef.deref() returns undefined when target is GC'd.
   */
  private cleanupStaleRefs(): void {
    // Cleanup GSAP targets
    for (const [eventId, ref] of this.gsapTargets) {
      if (ref.deref() === undefined) {
        this.gsapTargets.delete(eventId);
      }
    }

    // Cleanup Web Animations
    for (const [eventId, ref] of this.webAnimations) {
      if (ref.deref() === undefined) {
        this.webAnimations.delete(eventId);
      }
    }

    // Cleanup prevFrames for events that have stale refs
    // (optional: keep frames even if animation ref is gone)
  }

  /**
   * Setup default heuristic positions for common intents.
   */
  private setupDefaultHeuristics(): void {
    // Common slot game intents
    this.heuristicDefaults.set('SPIN', { x: 0.5, y: 0.55 });
    this.heuristicDefaults.set('REEL_STOP', { x: 0.5, y: 0.55 });
    this.heuristicDefaults.set('WIN', { x: 0.5, y: 0.55 });
    this.heuristicDefaults.set('BIG_WIN', { x: 0.5, y: 0.5 });
    this.heuristicDefaults.set('MEGA_WIN', { x: 0.5, y: 0.5 });
    this.heuristicDefaults.set('COIN_FLY', { x: 0.5, y: 0.55 });
    this.heuristicDefaults.set('COIN_FLY_TO_BALANCE', { x: 0.85, y: 0.1 });
    this.heuristicDefaults.set('FREE_SPIN_TRIGGER', { x: 0.5, y: 0.45 });
    this.heuristicDefaults.set('BONUS_TRIGGER', { x: 0.5, y: 0.45 });
    this.heuristicDefaults.set('BUTTON_CLICK', { x: 0.5, y: 0.9 });
    this.heuristicDefaults.set('UI_OPEN', { x: 0.5, y: 0.5 });
    this.heuristicDefaults.set('UI_CLOSE', { x: 0.5, y: 0.5 });

    // Reel positions (5 reels typical)
    for (let i = 0; i < 5; i++) {
      const x = 0.2 + i * 0.15; // Spread across center
      this.heuristicDefaults.set(`REEL_${i}_STOP`, { x, y: 0.55 });
      this.heuristicDefaults.set(`REEL_${i}_SPIN`, { x, y: 0.55 });
    }
  }

  /**
   * Register heuristic default for intent.
   */
  setHeuristicDefault(intent: string, x: number, y: number): void {
    this.heuristicDefaults.set(intent, { x: clamp01(x), y: clamp01(y) });
  }

  /**
   * Register GSAP animation target for transform harvesting.
   */
  registerGSAPTarget(eventId: string, target: GSAPTarget): void {
    this.gsapTargets.set(eventId, new WeakRef(target));
  }

  /**
   * Register Web Animation for transform harvesting.
   */
  registerWebAnimation(eventId: string, animation: Animation): void {
    this.webAnimations.set(eventId, new WeakRef(animation));
  }

  /**
   * Extract motion from event using best available source.
   */
  extract(event: RFSpatialEvent, dtSec: number): MotionFrame {
    const extractions: MotionExtraction[] = [];
    const prev = this.prevFrames.get(event.id);

    // Level 1: Explicit coordinates (best case)
    if (event.xNorm !== undefined && event.yNorm !== undefined) {
      const frame = this.extractFromExplicit(event, dtSec, prev);
      extractions.push({
        frame,
        source: 'EXPLICIT_COORDS',
        confidence: 0.95,
      });
    }

    // Level 2: Progress interpolation
    if (
      event.progress01 !== undefined &&
      (event.startAnchorId || event.anchorId) &&
      event.endAnchorId
    ) {
      const frame = this.extractFromProgress(event, dtSec, prev);
      if (frame) {
        extractions.push({
          frame,
          source: 'PROGRESS_INTERPOLATION',
          confidence: frame.confidence,
        });
      }
    }

    // Level 3: Anchor tracking
    if (event.anchorId) {
      const frame = this.extractFromAnchor(event, dtSec, prev);
      if (frame) {
        extractions.push({
          frame,
          source: 'ANCHOR_TRACKING',
          confidence: frame.confidence,
        });
      }
    }

    // Level 4: Transform harvesting
    const transformFrame = this.extractFromTransforms(event, dtSec, prev);
    if (transformFrame) {
      extractions.push({
        frame: transformFrame,
        source: 'TRANSFORM_HARVEST',
        confidence: transformFrame.confidence,
      });
    }

    // Level 5: Heuristics (always available as fallback)
    const heuristicFrame = this.extractFromHeuristics(event, dtSec, prev);
    extractions.push({
      frame: heuristicFrame,
      source: 'HEURISTIC',
      confidence: heuristicFrame.confidence,
    });

    // Select best extraction (highest confidence)
    extractions.sort((a, b) => b.confidence - a.confidence);
    const best = extractions[0];

    // Store for next velocity calculation
    this.prevFrames.set(event.id, best.frame);

    return best.frame;
  }

  /**
   * Extract from explicit coordinates.
   */
  private extractFromExplicit(
    event: RFSpatialEvent,
    dtSec: number,
    prev?: MotionFrame
  ): MotionFrame {
    const x = clamp01(event.xNorm!);
    const y = clamp01(event.yNorm!);

    let vx = event.velocityHint?.vx ?? 0;
    let vy = event.velocityHint?.vy ?? 0;

    if (!event.velocityHint && prev && dtSec > 0) {
      vx = calculateVelocity(x, prev.xNorm, dtSec);
      vy = calculateVelocity(y, prev.yNorm, dtSec);
    }

    return {
      xNorm: x,
      yNorm: y,
      vxNormPerS: vx,
      vyNormPerS: vy,
      confidence: 0.95,
      source: 'EXPLICIT_COORDS',
    };
  }

  /**
   * Extract from progress interpolation between anchors.
   */
  private extractFromProgress(
    event: RFSpatialEvent,
    dtSec: number,
    prev?: MotionFrame
  ): MotionFrame | null {
    const startId = event.startAnchorId ?? event.anchorId;
    const endId = event.endAnchorId;

    if (!startId || !endId) return null;

    const startFrame = this.registry.getFrame(startId, dtSec);
    const endFrame = this.registry.getFrame(endId, dtSec);

    if (!startFrame || !endFrame) return null;

    const t = clamp01(event.progress01 ?? 0);

    const x = lerp(startFrame.xNorm, endFrame.xNorm, t);
    const y = lerp(startFrame.yNorm, endFrame.yNorm, t);

    let vx = 0;
    let vy = 0;
    if (prev && dtSec > 0) {
      vx = calculateVelocity(x, prev.xNorm, dtSec);
      vy = calculateVelocity(y, prev.yNorm, dtSec);
    }

    // Confidence from anchor visibility/confidence
    const conf = clamp01(
      0.2 + 0.8 * Math.min(startFrame.confidence, endFrame.confidence)
    );

    return {
      xNorm: x,
      yNorm: y,
      vxNormPerS: vx,
      vyNormPerS: vy,
      confidence: conf,
      source: 'PROGRESS_INTERPOLATION',
    };
  }

  /**
   * Extract from anchor position tracking.
   */
  private extractFromAnchor(
    event: RFSpatialEvent,
    dtSec: number,
    _prev?: MotionFrame
  ): MotionFrame | null {
    const anchorId = event.anchorId;
    if (!anchorId) return null;

    const frame = this.registry.getFrame(anchorId, dtSec);
    if (!frame) return null;

    return {
      xNorm: frame.xNorm,
      yNorm: frame.yNorm,
      vxNormPerS: frame.vxNormPerS,
      vyNormPerS: frame.vyNormPerS,
      confidence: clamp01(frame.confidence * 0.85), // Slightly lower than explicit
      source: 'ANCHOR_TRACKING',
    };
  }

  /**
   * Extract from GSAP/Web Animation transforms.
   */
  private extractFromTransforms(
    event: RFSpatialEvent,
    _dtSec: number,
    _prev?: MotionFrame
  ): MotionFrame | null {
    // Try GSAP first
    const gsapRef = this.gsapTargets.get(event.id);
    if (gsapRef) {
      const target = gsapRef.deref();
      if (target?._gsap) {
        const gsapData = target._gsap;
        if (gsapData.x !== undefined && gsapData.y !== undefined) {
          // GSAP values are typically pixels, need viewport normalization
          // This assumes _gsap contains already-normalized or we have viewport info
          // For now, return raw values (integrator should normalize)
          return {
            xNorm: clamp01(gsapData.x),
            yNorm: clamp01(gsapData.y),
            vxNormPerS: 0,
            vyNormPerS: 0,
            confidence: 0.7,
            source: 'TRANSFORM_HARVEST',
          };
        }
      }
    }

    // Try Web Animation
    const webAnimRef = this.webAnimations.get(event.id);
    if (webAnimRef) {
      const anim = webAnimRef.deref();
      if (anim && anim.effect) {
        const timing = (anim.effect as AnimationEffectReadOnly).getComputedTiming();
        if (timing.progress !== null) {
          // Use progress as motion indicator
          // Would need start/end positions from keyframes
          // For now, just return progress as partial info
          return null; // Incomplete without position data
        }
      }
    }

    return null;
  }

  /**
   * Extract from heuristics (fallback).
   */
  private extractFromHeuristics(
    event: RFSpatialEvent,
    dtSec: number,
    prev?: MotionFrame
  ): MotionFrame {
    // Check for intent-specific default
    let pos = this.heuristicDefaults.get(event.intent);

    // Try partial matches
    if (!pos) {
      for (const [key, value] of this.heuristicDefaults) {
        if (event.intent.includes(key) || key.includes(event.intent)) {
          pos = value;
          break;
        }
      }
    }

    // Ultimate fallback: center
    if (!pos) {
      pos = { x: 0.5, y: 0.5 };
    }

    let vx = 0;
    let vy = 0;
    if (prev && dtSec > 0) {
      vx = calculateVelocity(pos.x, prev.xNorm, dtSec);
      vy = calculateVelocity(pos.y, prev.yNorm, dtSec);
    }

    return {
      xNorm: pos.x,
      yNorm: pos.y,
      vxNormPerS: vx,
      vyNormPerS: vy,
      confidence: 0.25, // Low confidence for heuristics
      source: 'HEURISTIC',
    };
  }

  /**
   * Clear motion data for event.
   */
  clearEvent(eventId: string): void {
    this.prevFrames.delete(eventId);
    this.gsapTargets.delete(eventId);
    this.webAnimations.delete(eventId);
  }

  /**
   * Clear all motion data.
   */
  clear(): void {
    this.prevFrames.clear();
    this.gsapTargets.clear();
    this.webAnimations.clear();
  }

  /**
   * Get previous frame for event.
   */
  getPreviousFrame(eventId: string): MotionFrame | undefined {
    return this.prevFrames.get(eventId);
  }

  /**
   * Dispose motion field.
   */
  dispose(): void {
    // Stop cleanup interval
    if (this.cleanupInterval !== null) {
      clearInterval(this.cleanupInterval);
      this.cleanupInterval = null;
    }

    this.clear();
    this.heuristicDefaults.clear();
  }
}

/**
 * Create motion field with registry.
 */
export function createMotionField(registry: AnchorRegistry): MotionField {
  return new MotionField(registry);
}
