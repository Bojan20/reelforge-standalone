/**
 * ReelForge Spatial System - Fusion Engine Tests
 * @module reelforge/spatial/__tests__/FusionEngine
 */

import { describe, it, expect, beforeEach } from 'vitest';
import {
  FusionEngine,
  createFusionEngine,
  getDefaultFusionEngine,
  fuseTargets,
} from '../core/FusionEngine';
import type {
  RFSpatialEvent,
  AnchorFrame,
  MotionFrame,
  IntentRule,
  SpatialTarget,
} from '../types';

// Test fixtures

function createBaseEvent(overrides?: Partial<RFSpatialEvent>): RFSpatialEvent {
  return {
    id: 'test-event-1',
    name: 'TEST_EVENT',
    intent: 'TEST_INTENT',
    bus: 'FX',
    timeMs: Date.now(),
    ...overrides,
  };
}

function createBaseRule(overrides?: Partial<IntentRule>): IntentRule {
  return {
    intent: 'TEST_INTENT',
    wAnchor: 0.4,
    wMotion: 0.4,
    wIntent: 0.2,
    width: 0.5,
    deadzone: 0.03,
    maxPan: 1.0,
    smoothingTauMs: 50,
    lifetimeMs: 1000,
    ...overrides,
  };
}

function createAnchorFrame(overrides?: Partial<AnchorFrame>): AnchorFrame {
  return {
    visible: true,
    xNorm: 0.5,
    yNorm: 0.5,
    wNorm: 0.1,
    hNorm: 0.1,
    vxNormPerS: 0,
    vyNormPerS: 0,
    confidence: 0.9,
    timestamp: Date.now(),
    ...overrides,
  };
}

function createMotionFrame(overrides?: Partial<MotionFrame>): MotionFrame {
  return {
    xNorm: 0.5,
    yNorm: 0.5,
    vxNormPerS: 0,
    vyNormPerS: 0,
    confidence: 0.8,
    source: 'EXPLICIT_COORDS',
    ...overrides,
  };
}

describe('FusionEngine', () => {
  let engine: FusionEngine;

  beforeEach(() => {
    engine = new FusionEngine();
  });

  describe('fuse', () => {
    it('returns SpatialTarget with required properties', () => {
      const result = engine.fuse({
        anchor: createAnchorFrame(),
        motion: createMotionFrame(),
        rule: createBaseRule(),
        event: createBaseEvent(),
      });

      expect(result).toHaveProperty('xNorm');
      expect(result).toHaveProperty('yNorm');
      expect(result).toHaveProperty('width');
      expect(result).toHaveProperty('confidence');
      expect(result).toHaveProperty('sources');
      expect(Array.isArray(result.sources)).toBe(true);
    });

    it('clamps position to 0..1 range', () => {
      const result = engine.fuse({
        anchor: createAnchorFrame({ xNorm: 1.5, yNorm: -0.5 }),
        motion: createMotionFrame({ xNorm: 1.2, yNorm: -0.3 }),
        rule: createBaseRule(),
        event: createBaseEvent(),
      });

      expect(result.xNorm).toBeGreaterThanOrEqual(0);
      expect(result.xNorm).toBeLessThanOrEqual(1);
      expect(result.yNorm).toBeGreaterThanOrEqual(0);
      expect(result.yNorm).toBeLessThanOrEqual(1);
    });

    it('uses rule width', () => {
      const result = engine.fuse({
        anchor: createAnchorFrame(),
        motion: createMotionFrame(),
        rule: createBaseRule({ width: 0.75 }),
        event: createBaseEvent(),
      });

      expect(result.width).toBe(0.75);
    });
  });

  describe('weight blending', () => {
    it('blends anchor and motion positions', () => {
      const result = engine.fuse({
        anchor: createAnchorFrame({ xNorm: 0.2, yNorm: 0.2, confidence: 1 }),
        motion: createMotionFrame({ xNorm: 0.8, yNorm: 0.8, confidence: 1 }),
        rule: createBaseRule({ wAnchor: 0.5, wMotion: 0.5, wIntent: 0 }),
        event: createBaseEvent(),
      });

      // Should be approximately between the two positions
      expect(result.xNorm).toBeGreaterThan(0.3);
      expect(result.xNorm).toBeLessThan(0.7);
    });

    it('respects anchor weight more when wAnchor is higher', () => {
      const anchorPos = { xNorm: 0.2, yNorm: 0.5 };
      const motionPos = { xNorm: 0.8, yNorm: 0.5 };

      const resultAnchorHeavy = engine.fuse({
        anchor: createAnchorFrame({ ...anchorPos, confidence: 1 }),
        motion: createMotionFrame({ ...motionPos, confidence: 1 }),
        rule: createBaseRule({ wAnchor: 0.9, wMotion: 0.1, wIntent: 0 }),
        event: createBaseEvent(),
      });

      const resultMotionHeavy = engine.fuse({
        anchor: createAnchorFrame({ ...anchorPos, confidence: 1 }),
        motion: createMotionFrame({ ...motionPos, confidence: 1 }),
        rule: createBaseRule({ wAnchor: 0.1, wMotion: 0.9, wIntent: 0 }),
        event: createBaseEvent(),
      });

      // Anchor-heavy should be closer to anchor position
      expect(resultAnchorHeavy.xNorm).toBeLessThan(resultMotionHeavy.xNorm);
    });

    it('scales weights by confidence', () => {
      const anchorPos = { xNorm: 0.2, yNorm: 0.5 };
      const motionPos = { xNorm: 0.8, yNorm: 0.5 };

      const resultHighConfAnchor = engine.fuse({
        anchor: createAnchorFrame({ ...anchorPos, confidence: 1 }),
        motion: createMotionFrame({ ...motionPos, confidence: 0.1 }),
        rule: createBaseRule({ wAnchor: 0.5, wMotion: 0.5, wIntent: 0 }),
        event: createBaseEvent(),
      });

      const resultHighConfMotion = engine.fuse({
        anchor: createAnchorFrame({ ...anchorPos, confidence: 0.1 }),
        motion: createMotionFrame({ ...motionPos, confidence: 1 }),
        rule: createBaseRule({ wAnchor: 0.5, wMotion: 0.5, wIntent: 0 }),
        event: createBaseEvent(),
      });

      // Higher confidence source should dominate
      expect(resultHighConfAnchor.xNorm).toBeLessThan(resultHighConfMotion.xNorm);
    });
  });

  describe('anchor handling', () => {
    it('ignores anchor when not visible', () => {
      const result = engine.fuse({
        anchor: createAnchorFrame({ xNorm: 0.1, visible: false, confidence: 1 }),
        motion: createMotionFrame({ xNorm: 0.9, confidence: 1 }),
        rule: createBaseRule({ wAnchor: 0.9, wMotion: 0.1, wIntent: 0 }),
        event: createBaseEvent(),
      });

      // Should use motion only since anchor is not visible
      expect(result.xNorm).toBeGreaterThan(0.5);
    });

    it('ignores anchor when null', () => {
      const result = engine.fuse({
        anchor: null,
        motion: createMotionFrame({ xNorm: 0.8, confidence: 1 }),
        rule: createBaseRule({ wAnchor: 0.9, wMotion: 0.1, wIntent: 0 }),
        event: createBaseEvent(),
      });

      // Should use motion + intent only
      expect(result.xNorm).toBeGreaterThan(0.5);
    });

    it('ignores anchor with zero confidence', () => {
      const result = engine.fuse({
        anchor: createAnchorFrame({ xNorm: 0.1, confidence: 0 }),
        motion: createMotionFrame({ xNorm: 0.9, confidence: 1 }),
        rule: createBaseRule({ wAnchor: 0.9, wMotion: 0.1, wIntent: 0 }),
        event: createBaseEvent(),
      });

      expect(result.xNorm).toBeGreaterThan(0.5);
    });
  });

  describe('motion handling', () => {
    it('ignores motion with zero confidence', () => {
      const result = engine.fuse({
        anchor: createAnchorFrame({ xNorm: 0.2, confidence: 1 }),
        motion: createMotionFrame({ xNorm: 0.9, confidence: 0 }),
        rule: createBaseRule({ wAnchor: 0.1, wMotion: 0.9, wIntent: 0 }),
        event: createBaseEvent(),
      });

      expect(result.xNorm).toBeLessThan(0.5);
    });

    it('includes motion source in sources array', () => {
      const result = engine.fuse({
        anchor: null,
        motion: createMotionFrame({ confidence: 1, source: 'EXPLICIT_COORDS' }),
        rule: createBaseRule({ wMotion: 1, wAnchor: 0, wIntent: 0 }),
        event: createBaseEvent(),
      });

      expect(result.sources).toContain('EXPLICIT_COORDS');
    });
  });

  describe('intent fallback', () => {
    it('uses intent default position when no anchor/motion', () => {
      const result = engine.fuse({
        anchor: null,
        motion: createMotionFrame({ confidence: 0 }),
        rule: createBaseRule({
          wAnchor: 0,
          wMotion: 0,
          wIntent: 1,
          intentDefaultPos: { x: 0.25, y: 0.75 },
        }),
        event: createBaseEvent(),
      });

      expect(result.xNorm).toBeCloseTo(0.25, 1);
      expect(result.yNorm).toBeCloseTo(0.75, 1);
    });

    it('uses event explicit coords when no intent default', () => {
      const result = engine.fuse({
        anchor: null,
        motion: createMotionFrame({ confidence: 0 }),
        rule: createBaseRule({
          wAnchor: 0,
          wMotion: 0,
          wIntent: 1,
        }),
        event: createBaseEvent({ xNorm: 0.3, yNorm: 0.7 }),
      });

      expect(result.xNorm).toBeCloseTo(0.3, 1);
      expect(result.yNorm).toBeCloseTo(0.7, 1);
    });

    it('uses center fallback when no data available', () => {
      const result = engine.fuse({
        anchor: null,
        motion: createMotionFrame({ confidence: 0 }),
        rule: createBaseRule({ wAnchor: 0, wMotion: 0, wIntent: 1 }),
        event: createBaseEvent(),
      });

      expect(result.xNorm).toBeCloseTo(0.5, 1);
      expect(result.yNorm).toBeCloseTo(0.5, 1);
    });
  });

  describe('confidence calculation', () => {
    it('has minimum confidence of 0.15', () => {
      const result = engine.fuse({
        anchor: null,
        motion: createMotionFrame({ confidence: 0 }),
        rule: createBaseRule(),
        event: createBaseEvent(),
      });

      expect(result.confidence).toBeGreaterThanOrEqual(0.15);
    });

    it('has maximum confidence of 1.0', () => {
      const result = engine.fuse({
        anchor: createAnchorFrame({ confidence: 1 }),
        motion: createMotionFrame({ confidence: 1 }),
        rule: createBaseRule(),
        event: createBaseEvent(),
      });

      expect(result.confidence).toBeLessThanOrEqual(1);
    });

    it('uses max of anchor/motion confidence', () => {
      const resultHighAnchor = engine.fuse({
        anchor: createAnchorFrame({ confidence: 0.9 }),
        motion: createMotionFrame({ confidence: 0.2 }),
        rule: createBaseRule(),
        event: createBaseEvent(),
      });

      const resultHighMotion = engine.fuse({
        anchor: createAnchorFrame({ confidence: 0.2 }),
        motion: createMotionFrame({ confidence: 0.9 }),
        rule: createBaseRule(),
        event: createBaseEvent(),
      });

      // Both should have similar confidence (using max)
      expect(resultHighAnchor.confidence).toBeCloseTo(resultHighMotion.confidence, 1);
    });
  });

  describe('sources tracking', () => {
    it('tracks contributing sources', () => {
      const result = engine.fuse({
        anchor: createAnchorFrame({ confidence: 0.9 }),
        motion: createMotionFrame({ confidence: 0.9, source: 'PROGRESS_INTERPOLATION' }),
        rule: createBaseRule({ wAnchor: 0.5, wMotion: 0.5, wIntent: 0 }),
        event: createBaseEvent(),
      });

      expect(result.sources).toContain('ANCHOR_TRACKING');
      expect(result.sources).toContain('PROGRESS_INTERPOLATION');
    });

    it('filters out low-weight sources', () => {
      const result = engine.fuse({
        anchor: createAnchorFrame({ confidence: 0.01 }), // Very low
        motion: createMotionFrame({ confidence: 1, source: 'EXPLICIT_COORDS' }),
        rule: createBaseRule({ wAnchor: 0.01, wMotion: 0.99, wIntent: 0 }),
        event: createBaseEvent(),
      });

      // Anchor contribution is too small, should not appear in sources
      expect(result.sources).not.toContain('ANCHOR_TRACKING');
      expect(result.sources).toContain('EXPLICIT_COORDS');
    });

    it('returns unique sources only', () => {
      const result = engine.fuse({
        anchor: null,
        motion: createMotionFrame({ confidence: 1, source: 'HEURISTIC' }),
        rule: createBaseRule({ wMotion: 0.5, wIntent: 0.5 }),
        event: createBaseEvent(),
      });

      // HEURISTIC should only appear once
      const heuristicCount = result.sources.filter(s => s === 'HEURISTIC').length;
      expect(heuristicCount).toBeLessThanOrEqual(1);
    });
  });

  describe('blend', () => {
    let target1: SpatialTarget;
    let target2: SpatialTarget;

    beforeEach(() => {
      target1 = {
        xNorm: 0.2,
        yNorm: 0.3,
        width: 0.4,
        confidence: 0.8,
        sources: ['ANCHOR_TRACKING'],
      };
      target2 = {
        xNorm: 0.8,
        yNorm: 0.7,
        width: 0.6,
        confidence: 0.9,
        sources: ['EXPLICIT_COORDS'],
      };
    });

    it('returns target1 at t=0', () => {
      const result = engine.blend(target1, target2, 0);
      expect(result.xNorm).toBe(target1.xNorm);
      expect(result.yNorm).toBe(target1.yNorm);
      expect(result.width).toBe(target1.width);
    });

    it('returns target2 at t=1', () => {
      const result = engine.blend(target1, target2, 1);
      expect(result.xNorm).toBe(target2.xNorm);
      expect(result.yNorm).toBe(target2.yNorm);
      expect(result.width).toBe(target2.width);
    });

    it('interpolates at t=0.5', () => {
      const result = engine.blend(target1, target2, 0.5);
      expect(result.xNorm).toBeCloseTo(0.5, 5);
      expect(result.yNorm).toBeCloseTo(0.5, 5);
      expect(result.width).toBeCloseTo(0.5, 5);
    });

    it('clamps t to 0..1', () => {
      const resultNeg = engine.blend(target1, target2, -0.5);
      expect(resultNeg.xNorm).toBe(target1.xNorm);

      const resultOver = engine.blend(target1, target2, 1.5);
      expect(resultOver.xNorm).toBe(target2.xNorm);
    });

    it('uses max confidence', () => {
      const result = engine.blend(target1, target2, 0.5);
      expect(result.confidence).toBe(Math.max(target1.confidence, target2.confidence));
    });

    it('merges sources', () => {
      const result = engine.blend(target1, target2, 0.5);
      expect(result.sources).toContain('ANCHOR_TRACKING');
      expect(result.sources).toContain('EXPLICIT_COORDS');
    });

    it('deduplicates sources', () => {
      target2.sources = ['ANCHOR_TRACKING', 'EXPLICIT_COORDS'];
      const result = engine.blend(target1, target2, 0.5);
      const anchorCount = result.sources.filter(s => s === 'ANCHOR_TRACKING').length;
      expect(anchorCount).toBe(1);
    });
  });

  describe('sanitize', () => {
    it('clamps all values to 0..1', () => {
      const dirty: SpatialTarget = {
        xNorm: 1.5,
        yNorm: -0.3,
        width: 2.0,
        confidence: 1.5,
        sources: ['ANCHOR_TRACKING'],
      };

      const clean = engine.sanitize(dirty);

      expect(clean.xNorm).toBe(1);
      expect(clean.yNorm).toBe(0);
      expect(clean.width).toBe(1);
      expect(clean.confidence).toBe(1);
    });

    it('preserves valid values', () => {
      const valid: SpatialTarget = {
        xNorm: 0.5,
        yNorm: 0.5,
        width: 0.5,
        confidence: 0.5,
        sources: ['EXPLICIT_COORDS'],
      };

      const clean = engine.sanitize(valid);

      expect(clean.xNorm).toBe(0.5);
      expect(clean.yNorm).toBe(0.5);
      expect(clean.width).toBe(0.5);
      expect(clean.confidence).toBe(0.5);
    });

    it('preserves sources array', () => {
      const target: SpatialTarget = {
        xNorm: 0.5,
        yNorm: 0.5,
        width: 0.5,
        confidence: 0.5,
        sources: ['ANCHOR_TRACKING', 'HEURISTIC'],
      };

      const clean = engine.sanitize(target);
      expect(clean.sources).toEqual(target.sources);
    });
  });
});

describe('factory functions', () => {
  describe('createFusionEngine', () => {
    it('creates new instance', () => {
      const engine1 = createFusionEngine();
      const engine2 = createFusionEngine();
      expect(engine1).not.toBe(engine2);
    });

    it('returns FusionEngine instance', () => {
      const engine = createFusionEngine();
      expect(engine).toBeInstanceOf(FusionEngine);
    });
  });

  describe('getDefaultFusionEngine', () => {
    it('returns same instance', () => {
      const engine1 = getDefaultFusionEngine();
      const engine2 = getDefaultFusionEngine();
      expect(engine1).toBe(engine2);
    });
  });
});

describe('fuseTargets utility', () => {
  it('fuses using default engine', () => {
    const result = fuseTargets(
      createBaseRule(),
      createAnchorFrame(),
      createMotionFrame(),
      createBaseEvent()
    );

    expect(result).toHaveProperty('xNorm');
    expect(result).toHaveProperty('yNorm');
    expect(result).toHaveProperty('confidence');
  });

  it('accepts custom engine', () => {
    const customEngine = createFusionEngine();
    const result = fuseTargets(
      createBaseRule(),
      createAnchorFrame({ xNorm: 0.3 }),
      createMotionFrame({ xNorm: 0.7 }),
      createBaseEvent(),
      customEngine
    );

    expect(result).toBeDefined();
  });

  it('handles null anchor', () => {
    const result = fuseTargets(
      createBaseRule(),
      null,
      createMotionFrame({ xNorm: 0.8, confidence: 1 }),
      createBaseEvent()
    );

    expect(result.xNorm).toBeGreaterThan(0.5);
  });
});

describe('edge cases', () => {
  let engine: FusionEngine;

  beforeEach(() => {
    engine = new FusionEngine();
  });

  it('handles all zero weights', () => {
    const result = engine.fuse({
      anchor: createAnchorFrame({ confidence: 0 }),
      motion: createMotionFrame({ confidence: 0 }),
      rule: createBaseRule({ wAnchor: 0, wMotion: 0, wIntent: 0 }),
      event: createBaseEvent(),
    });

    // Should fall back to center
    expect(result.xNorm).toBeCloseTo(0.5, 1);
    expect(result.yNorm).toBeCloseTo(0.5, 1);
  });

  it('handles very small weights', () => {
    const result = engine.fuse({
      anchor: createAnchorFrame({ xNorm: 0.9, confidence: 0.0001 }),
      motion: createMotionFrame({ xNorm: 0.1, confidence: 0.0001 }),
      rule: createBaseRule({ wAnchor: 0.0001, wMotion: 0.0001, wIntent: 0.9998 }),
      event: createBaseEvent({ xNorm: 0.5, yNorm: 0.5 }),
    });

    // Should be close to intent position
    expect(result.xNorm).toBeCloseTo(0.5, 0);
  });

  it('handles extreme position values', () => {
    const result = engine.fuse({
      anchor: createAnchorFrame({ xNorm: -1000, yNorm: 1000, confidence: 1 }),
      motion: createMotionFrame({ xNorm: 1000, yNorm: -1000, confidence: 1 }),
      rule: createBaseRule({ wAnchor: 0.5, wMotion: 0.5, wIntent: 0 }),
      event: createBaseEvent(),
    });

    // Should clamp to valid range
    expect(result.xNorm).toBeGreaterThanOrEqual(0);
    expect(result.xNorm).toBeLessThanOrEqual(1);
    expect(result.yNorm).toBeGreaterThanOrEqual(0);
    expect(result.yNorm).toBeLessThanOrEqual(1);
  });
});
