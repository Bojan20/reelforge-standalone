/**
 * ReelForge Spatial System - MotionField Tests
 * @module reelforge/spatial/__tests__/MotionField
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { MotionField, createMotionField } from '../core/MotionField';
import { AnchorRegistry } from '../adapters/AnchorRegistry';
import type { RFSpatialEvent, AnchorFrame, MotionSource } from '../types';

// Mock AnchorRegistry
function createMockRegistry(): AnchorRegistry {
  const mockFrames = new Map<string, AnchorFrame>();

  const registry = {
    getFrame: vi.fn((anchorId: string) => mockFrames.get(anchorId) ?? null),
    resolve: vi.fn(),
    registerAdapter: vi.fn(),
    unregisterAdapter: vi.fn(),
    dispose: vi.fn(),
    // Helper for tests
    setFrame: (anchorId: string, frame: AnchorFrame) => {
      mockFrames.set(anchorId, frame);
    },
    clearFrames: () => mockFrames.clear(),
  } as unknown as AnchorRegistry & {
    setFrame: (id: string, frame: AnchorFrame) => void;
    clearFrames: () => void;
  };

  return registry;
}

function createMockEvent(overrides: Partial<RFSpatialEvent> = {}): RFSpatialEvent {
  return {
    id: 'event-1',
    intent: 'TEST_EVENT',
    bus: 'FX',
    priority: 5,
    startTime: 1000,
    lifetime: 500,
    ...overrides,
  };
}

function createMockAnchorFrame(overrides: Partial<AnchorFrame> = {}): AnchorFrame {
  return {
    visible: true,
    xNorm: 0.5,
    yNorm: 0.5,
    wNorm: 0.1,
    hNorm: 0.08,
    vxNormPerS: 0,
    vyNormPerS: 0,
    confidence: 0.8,
    timestamp: 1000,
    ...overrides,
  };
}

describe('MotionField', () => {
  let motionField: MotionField;
  let mockRegistry: AnchorRegistry & {
    setFrame: (id: string, frame: AnchorFrame) => void;
    clearFrames: () => void;
  };

  beforeEach(() => {
    vi.spyOn(performance, 'now').mockReturnValue(1000);
    mockRegistry = createMockRegistry() as any;
    motionField = new MotionField(mockRegistry);
  });

  afterEach(() => {
    motionField.dispose();
    vi.restoreAllMocks();
  });

  describe('initialization', () => {
    it('creates motion field with registry', () => {
      expect(motionField).toBeInstanceOf(MotionField);
    });

    it('sets up default heuristics', () => {
      // Heuristics should provide fallback positions for common intents
      const event = createMockEvent({ intent: 'SPIN' });
      const frame = motionField.extract(event, 0.016);

      // SPIN should have a default position
      expect(frame.source).toBe('HEURISTIC');
      expect(frame.xNorm).toBeCloseTo(0.5, 1);
    });
  });

  describe('extract - explicit coordinates', () => {
    it('uses explicit coordinates when provided', () => {
      const event = createMockEvent({
        xNorm: 0.3,
        yNorm: 0.7,
      });

      const frame = motionField.extract(event, 0.016);

      expect(frame.source).toBe('EXPLICIT_COORDS');
      expect(frame.xNorm).toBe(0.3);
      expect(frame.yNorm).toBe(0.7);
      expect(frame.confidence).toBe(0.95);
    });

    it('clamps explicit coordinates to 0..1', () => {
      const event = createMockEvent({
        xNorm: 1.5,
        yNorm: -0.2,
      });

      const frame = motionField.extract(event, 0.016);

      expect(frame.xNorm).toBe(1);
      expect(frame.yNorm).toBe(0);
    });

    it('uses velocity hint when provided', () => {
      const event = createMockEvent({
        xNorm: 0.5,
        yNorm: 0.5,
        velocityHint: { vx: 2.0, vy: -1.0 },
      });

      const frame = motionField.extract(event, 0.016);

      expect(frame.vxNormPerS).toBe(2.0);
      expect(frame.vyNormPerS).toBe(-1.0);
    });

    it('calculates velocity from previous frame', () => {
      const event = createMockEvent({
        xNorm: 0.5,
        yNorm: 0.5,
      });

      // First extraction
      motionField.extract(event, 0.016);

      // Move position
      event.xNorm = 0.6;
      const frame2 = motionField.extract(event, 0.016);

      // Velocity should be (0.6 - 0.5) / 0.016 = 6.25
      expect(frame2.vxNormPerS).toBeCloseTo(6.25, 1);
    });
  });

  describe('extract - progress interpolation', () => {
    it('interpolates between start and end anchors', () => {
      mockRegistry.setFrame('start', createMockAnchorFrame({ xNorm: 0.2, yNorm: 0.3 }));
      mockRegistry.setFrame('end', createMockAnchorFrame({ xNorm: 0.8, yNorm: 0.7 }));

      const event = createMockEvent({
        startAnchorId: 'start',
        endAnchorId: 'end',
        progress01: 0.5,
      });

      const frame = motionField.extract(event, 0.016);

      expect(frame.source).toBe('PROGRESS_INTERPOLATION');
      expect(frame.xNorm).toBeCloseTo(0.5, 2);
      expect(frame.yNorm).toBeCloseTo(0.5, 2);
    });

    it('uses anchorId as start if startAnchorId not provided', () => {
      mockRegistry.setFrame('anchor', createMockAnchorFrame({ xNorm: 0.1, yNorm: 0.1 }));
      mockRegistry.setFrame('end', createMockAnchorFrame({ xNorm: 0.9, yNorm: 0.9 }));

      const event = createMockEvent({
        anchorId: 'anchor',
        endAnchorId: 'end',
        progress01: 0.25,
      });

      const frame = motionField.extract(event, 0.016);

      expect(frame.source).toBe('PROGRESS_INTERPOLATION');
      expect(frame.xNorm).toBeCloseTo(0.3, 2); // 0.1 + 0.25 * (0.9 - 0.1)
    });

    it('clamps progress to 0..1', () => {
      mockRegistry.setFrame('start', createMockAnchorFrame({ xNorm: 0.0, yNorm: 0.0 }));
      mockRegistry.setFrame('end', createMockAnchorFrame({ xNorm: 1.0, yNorm: 1.0 }));

      const event = createMockEvent({
        startAnchorId: 'start',
        endAnchorId: 'end',
        progress01: 1.5, // Over 1
      });

      const frame = motionField.extract(event, 0.016);

      expect(frame.xNorm).toBe(1);
      expect(frame.yNorm).toBe(1);
    });

    it('confidence based on anchor confidence', () => {
      mockRegistry.setFrame('start', createMockAnchorFrame({ confidence: 0.9 }));
      mockRegistry.setFrame('end', createMockAnchorFrame({ confidence: 0.5 }));

      const event = createMockEvent({
        startAnchorId: 'start',
        endAnchorId: 'end',
        progress01: 0.5,
      });

      const frame = motionField.extract(event, 0.016);

      // Confidence should be based on min(0.9, 0.5) = 0.5
      // Formula: 0.2 + 0.8 * 0.5 = 0.6
      expect(frame.confidence).toBeCloseTo(0.6, 2);
    });

    it('returns null if start anchor not found', () => {
      mockRegistry.setFrame('end', createMockAnchorFrame());

      const event = createMockEvent({
        startAnchorId: 'missing',
        endAnchorId: 'end',
        progress01: 0.5,
      });

      // Should fall back to heuristics
      const frame = motionField.extract(event, 0.016);
      expect(frame.source).toBe('HEURISTIC');
    });
  });

  describe('extract - anchor tracking', () => {
    it('tracks anchor position', () => {
      mockRegistry.setFrame('tracked', createMockAnchorFrame({
        xNorm: 0.4,
        yNorm: 0.6,
        vxNormPerS: 1.5,
        vyNormPerS: -0.5,
        confidence: 0.9,
      }));

      const event = createMockEvent({
        anchorId: 'tracked',
      });

      const frame = motionField.extract(event, 0.016);

      expect(frame.source).toBe('ANCHOR_TRACKING');
      expect(frame.xNorm).toBe(0.4);
      expect(frame.yNorm).toBe(0.6);
      expect(frame.vxNormPerS).toBe(1.5);
      expect(frame.vyNormPerS).toBe(-0.5);
    });

    it('reduces confidence slightly for anchor tracking', () => {
      mockRegistry.setFrame('tracked', createMockAnchorFrame({
        confidence: 1.0,
      }));

      const event = createMockEvent({
        anchorId: 'tracked',
      });

      const frame = motionField.extract(event, 0.016);

      // Confidence = 1.0 * 0.85 = 0.85
      expect(frame.confidence).toBeCloseTo(0.85, 2);
    });

    it('returns null if anchor not found', () => {
      const event = createMockEvent({
        anchorId: 'missing',
      });

      // Should fall back to heuristics
      const frame = motionField.extract(event, 0.016);
      expect(frame.source).toBe('HEURISTIC');
    });
  });

  describe('extract - transform harvesting (GSAP)', () => {
    it('extracts from GSAP target', () => {
      const gsapTarget = {
        _gsap: {
          x: 0.3,
          y: 0.7,
        },
      };

      motionField.registerGSAPTarget('event-1', gsapTarget);

      const event = createMockEvent({ id: 'event-1' });
      const frame = motionField.extract(event, 0.016);

      expect(frame.source).toBe('TRANSFORM_HARVEST');
      expect(frame.xNorm).toBe(0.3);
      expect(frame.yNorm).toBe(0.7);
    });

    it('clamps GSAP values to 0..1', () => {
      const gsapTarget = {
        _gsap: {
          x: 1.5,
          y: -0.2,
        },
      };

      motionField.registerGSAPTarget('event-1', gsapTarget);

      const event = createMockEvent({ id: 'event-1' });
      const frame = motionField.extract(event, 0.016);

      expect(frame.xNorm).toBe(1);
      expect(frame.yNorm).toBe(0);
    });

    it('handles garbage collected GSAP target', () => {
      // WeakRef will return undefined after GC
      const gsapTarget = {
        _gsap: { x: 0.5, y: 0.5 },
      };

      motionField.registerGSAPTarget('event-1', gsapTarget);

      // Simulate GC by clearing the target
      // Note: We can't actually force GC, but we can test the fallback
      const event = createMockEvent({ id: 'event-1' });
      const frame = motionField.extract(event, 0.016);

      // Should still work (WeakRef still valid)
      expect(frame).toBeDefined();
    });

    it('falls back if GSAP data incomplete', () => {
      const gsapTarget = {
        _gsap: {
          x: 0.5,
          // y is missing
        },
      };

      motionField.registerGSAPTarget('event-1', gsapTarget);

      const event = createMockEvent({ id: 'event-1' });
      const frame = motionField.extract(event, 0.016);

      // Should fall back to heuristics
      expect(frame.source).toBe('HEURISTIC');
    });
  });

  describe('extract - Web Animations', () => {
    it('registers web animation', () => {
      const mockAnimation = {
        effect: {
          getComputedTiming: () => ({ progress: 0.5 }),
        },
      } as Animation;

      motionField.registerWebAnimation('event-1', mockAnimation);

      // Currently returns null because position data not available from timing alone
      const event = createMockEvent({ id: 'event-1' });
      const frame = motionField.extract(event, 0.016);

      // Falls back to heuristics since we can't get position from timing
      expect(frame.source).toBe('HEURISTIC');
    });
  });

  describe('extract - heuristics', () => {
    it('uses default position for known intents', () => {
      const spinEvent = createMockEvent({ intent: 'SPIN' });
      const frame = motionField.extract(spinEvent, 0.016);

      expect(frame.source).toBe('HEURISTIC');
      expect(frame.xNorm).toBeCloseTo(0.5, 1);
      expect(frame.yNorm).toBeCloseTo(0.55, 1);
    });

    it('uses reel-specific positions', () => {
      const reel0Event = createMockEvent({ intent: 'REEL_0_STOP' });
      const reel4Event = createMockEvent({ intent: 'REEL_4_STOP' });

      const frame0 = motionField.extract(reel0Event, 0.016);
      const frame4 = motionField.extract(reel4Event, 0.016);

      // Reel 0 should be more left than reel 4
      expect(frame0.xNorm).toBeLessThan(frame4.xNorm);
    });

    it('partial matches work', () => {
      const event = createMockEvent({ intent: 'BIG_WIN_CELEBRATION' });
      const frame = motionField.extract(event, 0.016);

      // Should match BIG_WIN
      expect(frame.xNorm).toBeCloseTo(0.5, 1);
    });

    it('falls back to center for unknown intent', () => {
      const event = createMockEvent({ intent: 'COMPLETELY_UNKNOWN_XYZ' });
      const frame = motionField.extract(event, 0.016);

      expect(frame.source).toBe('HEURISTIC');
      expect(frame.xNorm).toBe(0.5);
      expect(frame.yNorm).toBe(0.5);
      expect(frame.confidence).toBe(0.25);
    });

    it('calculates velocity from previous heuristic frame', () => {
      const event = createMockEvent({ intent: 'UNKNOWN_MOVING' });

      // First extraction
      motionField.extract(event, 0.016);

      // Change heuristic default
      motionField.setHeuristicDefault('UNKNOWN_MOVING', 0.6, 0.5);

      // Second extraction with dt
      const frame2 = motionField.extract(event, 0.016);

      expect(frame2.vxNormPerS).not.toBe(0);
    });
  });

  describe('setHeuristicDefault', () => {
    it('sets custom heuristic position', () => {
      motionField.setHeuristicDefault('CUSTOM_EVENT', 0.2, 0.8);

      const event = createMockEvent({ intent: 'CUSTOM_EVENT' });
      const frame = motionField.extract(event, 0.016);

      expect(frame.xNorm).toBe(0.2);
      expect(frame.yNorm).toBe(0.8);
    });

    it('clamps values to 0..1', () => {
      motionField.setHeuristicDefault('CLAMPED', 1.5, -0.5);

      const event = createMockEvent({ intent: 'CLAMPED' });
      const frame = motionField.extract(event, 0.016);

      expect(frame.xNorm).toBe(1);
      expect(frame.yNorm).toBe(0);
    });
  });

  describe('source priority', () => {
    it('prefers explicit over progress', () => {
      mockRegistry.setFrame('start', createMockAnchorFrame({ xNorm: 0.1 }));
      mockRegistry.setFrame('end', createMockAnchorFrame({ xNorm: 0.9 }));

      const event = createMockEvent({
        xNorm: 0.3,
        yNorm: 0.7,
        startAnchorId: 'start',
        endAnchorId: 'end',
        progress01: 0.5,
      });

      const frame = motionField.extract(event, 0.016);

      expect(frame.source).toBe('EXPLICIT_COORDS');
      expect(frame.xNorm).toBe(0.3);
    });

    it('prefers progress over anchor tracking', () => {
      mockRegistry.setFrame('anchor', createMockAnchorFrame({ xNorm: 0.1, yNorm: 0.1 }));
      mockRegistry.setFrame('end', createMockAnchorFrame({ xNorm: 0.9, yNorm: 0.9 }));

      const event = createMockEvent({
        anchorId: 'anchor',
        endAnchorId: 'end',
        progress01: 0.5,
      });

      const frame = motionField.extract(event, 0.016);

      expect(frame.source).toBe('PROGRESS_INTERPOLATION');
    });

    it('prefers higher confidence source', () => {
      // Anchor tracking has confidence 0.85 * anchor.confidence
      // Transform harvest has confidence 0.7
      // With anchor confidence 0.8, anchor tracking = 0.68 < 0.7
      // So transform harvest wins in this case
      mockRegistry.setFrame('anchor', createMockAnchorFrame({
        xNorm: 0.4,
        yNorm: 0.6,
        confidence: 0.8, // 0.8 * 0.85 = 0.68 < 0.7
      }));

      const gsapTarget = { _gsap: { x: 0.1, y: 0.1 } };
      motionField.registerGSAPTarget('event-1', gsapTarget);

      const event = createMockEvent({
        id: 'event-1',
        anchorId: 'anchor',
      });

      const frame = motionField.extract(event, 0.016);

      // Transform harvest wins because 0.7 > 0.68
      expect(frame.source).toBe('TRANSFORM_HARVEST');
    });

    it('prefers anchor tracking when anchor has high confidence', () => {
      // With anchor confidence 1.0, anchor tracking = 0.85 > 0.7
      mockRegistry.setFrame('anchor', createMockAnchorFrame({
        xNorm: 0.4,
        yNorm: 0.6,
        confidence: 1.0, // 1.0 * 0.85 = 0.85 > 0.7
      }));

      const gsapTarget = { _gsap: { x: 0.1, y: 0.1 } };
      motionField.registerGSAPTarget('event-1', gsapTarget);

      const event = createMockEvent({
        id: 'event-1',
        anchorId: 'anchor',
      });

      const frame = motionField.extract(event, 0.016);

      // Anchor tracking wins because 0.85 > 0.7
      expect(frame.source).toBe('ANCHOR_TRACKING');
    });

    it('prefers transforms over heuristics', () => {
      const gsapTarget = { _gsap: { x: 0.3, y: 0.7 } };
      motionField.registerGSAPTarget('event-1', gsapTarget);

      const event = createMockEvent({ id: 'event-1', intent: 'SPIN' });
      const frame = motionField.extract(event, 0.016);

      expect(frame.source).toBe('TRANSFORM_HARVEST');
    });
  });

  describe('clearEvent', () => {
    it('clears motion data for event', () => {
      const gsapTarget = { _gsap: { x: 0.5, y: 0.5 } };
      motionField.registerGSAPTarget('event-1', gsapTarget);

      const event = createMockEvent({ id: 'event-1' });
      motionField.extract(event, 0.016);

      motionField.clearEvent('event-1');

      // After clear, should fall back to heuristics
      const frame = motionField.extract(event, 0.016);
      expect(frame.source).toBe('HEURISTIC');
    });

    it('clears previous frame', () => {
      const event = createMockEvent({
        xNorm: 0.5,
        yNorm: 0.5,
      });

      motionField.extract(event, 0.016);
      expect(motionField.getPreviousFrame('event-1')).toBeDefined();

      motionField.clearEvent('event-1');
      expect(motionField.getPreviousFrame('event-1')).toBeUndefined();
    });
  });

  describe('clear', () => {
    it('clears all motion data', () => {
      const event1 = createMockEvent({ id: 'e1', xNorm: 0.3, yNorm: 0.3 });
      const event2 = createMockEvent({ id: 'e2', xNorm: 0.7, yNorm: 0.7 });

      motionField.extract(event1, 0.016);
      motionField.extract(event2, 0.016);

      expect(motionField.getPreviousFrame('e1')).toBeDefined();
      expect(motionField.getPreviousFrame('e2')).toBeDefined();

      motionField.clear();

      expect(motionField.getPreviousFrame('e1')).toBeUndefined();
      expect(motionField.getPreviousFrame('e2')).toBeUndefined();
    });
  });

  describe('getPreviousFrame', () => {
    it('returns previous frame for event', () => {
      const event = createMockEvent({
        xNorm: 0.4,
        yNorm: 0.6,
      });

      const frame = motionField.extract(event, 0.016);
      const prev = motionField.getPreviousFrame('event-1');

      expect(prev).toEqual(frame);
    });

    it('returns undefined for unknown event', () => {
      const prev = motionField.getPreviousFrame('nonexistent');
      expect(prev).toBeUndefined();
    });
  });

  describe('dispose', () => {
    it('clears all data including heuristics', () => {
      motionField.setHeuristicDefault('CUSTOM', 0.3, 0.7);

      const event = createMockEvent({
        id: 'e1',
        xNorm: 0.5,
        yNorm: 0.5,
      });
      motionField.extract(event, 0.016);

      motionField.dispose();

      // After dispose, heuristics should also be cleared
      const customEvent = createMockEvent({ intent: 'CUSTOM' });
      const frame = motionField.extract(customEvent, 0.016);

      // Falls back to center since heuristics are cleared
      expect(frame.xNorm).toBe(0.5);
      expect(frame.yNorm).toBe(0.5);
    });
  });
});

describe('createMotionField', () => {
  it('creates motion field with registry', () => {
    const registry = createMockRegistry();
    const motionField = createMotionField(registry);

    expect(motionField).toBeInstanceOf(MotionField);

    motionField.dispose();
  });
});
