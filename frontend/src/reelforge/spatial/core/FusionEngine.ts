/**
 * ReelForge Spatial System - Fusion Engine
 * Confidence-weighted fusion of anchor, motion, and intent data.
 *
 * @module reelforge/spatial/core
 */

import type {
  RFSpatialEvent,
  AnchorFrame,
  MotionFrame,
  IntentRule,
  SpatialTarget,
  MotionSource,
} from '../types';
import { clamp01, weightedAverage2D } from '../utils/math';

/**
 * Fusion input sources.
 */
interface FusionInputs {
  /** Anchor frame (if available) */
  anchor: AnchorFrame | null;

  /** Motion frame */
  motion: MotionFrame;

  /** Intent rule */
  rule: IntentRule;

  /** Original event */
  event: RFSpatialEvent;
}

/**
 * FusionEngine combines multiple spatial data sources into a single target.
 * Uses confidence-weighted blending with fallback chain.
 */
export class FusionEngine {
  /**
   * Fuse inputs into spatial target.
   */
  fuse(inputs: FusionInputs): SpatialTarget {
    const { anchor, motion, rule, event } = inputs;

    // Collect position sources with confidence
    const sources: Array<{
      x: number;
      y: number;
      weight: number;
      source: MotionSource;
    }> = [];

    // 1. Anchor contribution
    if (anchor && anchor.visible) {
      const weight = rule.wAnchor * anchor.confidence;
      if (weight > 0.001) {
        sources.push({
          x: anchor.xNorm,
          y: anchor.yNorm,
          weight,
          source: 'ANCHOR_TRACKING',
        });
      }
    }

    // 2. Motion contribution
    if (motion.confidence > 0) {
      const weight = rule.wMotion * motion.confidence;
      if (weight > 0.001) {
        sources.push({
          x: motion.xNorm,
          y: motion.yNorm,
          weight,
          source: motion.source,
        });
      }
    }

    // 3. Intent default contribution
    const intentPos = this.getIntentPosition(rule, event);
    const intentWeight = rule.wIntent * (1 - Math.max(anchor?.confidence ?? 0, motion.confidence) * 0.5);
    if (intentWeight > 0.001) {
      sources.push({
        x: intentPos.x,
        y: intentPos.y,
        weight: intentWeight,
        source: 'HEURISTIC',
      });
    }

    // 4. Fallback if no sources
    if (sources.length === 0) {
      sources.push({
        x: 0.5,
        y: 0.5,
        weight: 1,
        source: 'NONE',
      });
    }

    // Normalize weights
    const totalWeight = sources.reduce((sum, s) => sum + s.weight, 0);
    if (totalWeight > 0) {
      sources.forEach(s => s.weight /= totalWeight);
    }

    // Weighted blend
    const blended = weightedAverage2D(
      sources.map(s => ({ x: s.x, y: s.y })),
      sources.map(s => s.weight)
    );

    // Calculate combined confidence
    const maxSourceConfidence = Math.max(
      anchor?.confidence ?? 0,
      motion.confidence,
      0.1 // Minimum from intent
    );
    const confidence = clamp01(0.15 + 0.85 * maxSourceConfidence);

    // Collect contributing sources
    const contributingSources = sources
      .filter(s => s.weight > 0.05)
      .map(s => s.source)
      .filter((v, i, a) => a.indexOf(v) === i); // Unique

    return {
      xNorm: clamp01(blended.x),
      yNorm: clamp01(blended.y),
      width: rule.width,
      confidence,
      sources: contributingSources,
    };
  }

  /**
   * Get intent default position.
   */
  private getIntentPosition(
    rule: IntentRule,
    event: RFSpatialEvent
  ): { x: number; y: number } {
    // Use rule's intent default if set
    if (rule.intentDefaultPos) {
      return rule.intentDefaultPos;
    }

    // Use event's explicit coords if provided
    if (event.xNorm !== undefined && event.yNorm !== undefined) {
      return { x: event.xNorm, y: event.yNorm };
    }

    // Center fallback
    return { x: 0.5, y: 0.5 };
  }

  /**
   * Blend two targets (for crossfade transitions).
   */
  blend(
    target1: SpatialTarget,
    target2: SpatialTarget,
    t: number
  ): SpatialTarget {
    const blend = clamp01(t);

    return {
      xNorm: target1.xNorm + (target2.xNorm - target1.xNorm) * blend,
      yNorm: target1.yNorm + (target2.yNorm - target1.yNorm) * blend,
      width: target1.width + (target2.width - target1.width) * blend,
      confidence: Math.max(target1.confidence, target2.confidence),
      sources: [...new Set([...target1.sources, ...target2.sources])],
    };
  }

  /**
   * Apply sanity clamp to target.
   * Ensures values are within valid ranges.
   */
  sanitize(target: SpatialTarget): SpatialTarget {
    return {
      xNorm: clamp01(target.xNorm),
      yNorm: clamp01(target.yNorm),
      width: clamp01(target.width),
      confidence: clamp01(target.confidence),
      sources: target.sources,
    };
  }
}

/**
 * Default shared instance for stateless utility functions.
 * FusionEngine is stateless, so sharing a single instance is safe and efficient.
 * Eager initialization avoids lazy-init pitfalls and ensures predictable behavior.
 */
const defaultFusionEngine = new FusionEngine();

/**
 * Create a new fusion engine instance.
 * Use this when you need a dedicated instance (e.g., for testing or isolation).
 */
export function createFusionEngine(): FusionEngine {
  return new FusionEngine();
}

/**
 * Get the default shared fusion engine.
 * Prefer createFusionEngine() for dependency injection scenarios.
 */
export function getDefaultFusionEngine(): FusionEngine {
  return defaultFusionEngine;
}

/**
 * Quick fusion function (stateless utility).
 * Uses default shared instance - safe because FusionEngine is stateless.
 *
 * @param rule - Intent rule configuration
 * @param anchor - Anchor frame data (or null)
 * @param motion - Motion frame data
 * @param event - Original spatial event
 * @param engine - Optional custom FusionEngine instance (for DI/testing)
 */
export function fuseTargets(
  rule: IntentRule,
  anchor: AnchorFrame | null,
  motion: MotionFrame,
  event: RFSpatialEvent,
  engine: FusionEngine = defaultFusionEngine
): SpatialTarget {
  return engine.fuse({ anchor, motion, rule, event });
}
