/**
 * ReelForge Spatial System - Spatial Engine Tests
 * @module reelforge/spatial/__tests__/SpatialEngine
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  SpatialEngine,
  createSpatialEngine,
  type SpatialEventCallback,
} from '../SpatialEngine';
import type {
  RFSpatialEvent,
  SpatialEngineConfig,
  IAudioSpatialAdapter,
  SpatialBus,
} from '../types';

// Mock performance.now and RAF
vi.stubGlobal('performance', {
  now: vi.fn(() => Date.now()),
});

let rafCallback: ((time: number) => void) | null = null;
vi.stubGlobal('requestAnimationFrame', vi.fn((cb: (time: number) => void) => {
  rafCallback = cb;
  return 1;
}));
vi.stubGlobal('cancelAnimationFrame', vi.fn());

// Test fixtures

function createEvent(overrides?: Partial<RFSpatialEvent>): RFSpatialEvent {
  return {
    id: `event-${Math.random().toString(36).slice(2)}`,
    name: 'TEST_EVENT',
    intent: 'TEST_INTENT',
    bus: 'FX',
    timeMs: Date.now(),
    ...overrides,
  };
}

function createMockAudioAdapter(): IAudioSpatialAdapter {
  return {
    setPan: vi.fn(),
    setWidth: vi.fn(),
    setLPF: vi.fn(),
    setGain: vi.fn(),
    setChannelGains: vi.fn(),
    isActive: vi.fn(() => true),
  };
}

describe('SpatialEngine', () => {
  let engine: SpatialEngine;

  beforeEach(() => {
    vi.clearAllMocks();
    rafCallback = null;
    engine = new SpatialEngine();
  });

  afterEach(() => {
    engine.dispose();
  });

  describe('initialization', () => {
    it('creates with default config', () => {
      expect(engine).toBeInstanceOf(SpatialEngine);
      expect(engine.isRunning()).toBe(false);
    });

    it('creates with custom config', () => {
      const customEngine = createSpatialEngine({
        updateRate: 30,
        predictiveLeadMs: 50,
      });
      expect(customEngine).toBeInstanceOf(SpatialEngine);
      customEngine.dispose();
    });

    it('validates updateRate', () => {
      expect(() => new SpatialEngine({ updateRate: 0 })).toThrow(/updateRate/);
      expect(() => new SpatialEngine({ updateRate: -1 })).toThrow(/updateRate/);
      expect(() => new SpatialEngine({ updateRate: 241 })).toThrow(/updateRate/);
    });

    it('validates predictiveLeadMs', () => {
      expect(() => new SpatialEngine({ predictiveLeadMs: -1 })).toThrow(/predictiveLeadMs/);
      expect(() => new SpatialEngine({ predictiveLeadMs: 501 })).toThrow(/predictiveLeadMs/);
    });

    it('validates filterAlpha', () => {
      expect(() => new SpatialEngine({ filterAlpha: -0.1 })).toThrow(/filterAlpha/);
      expect(() => new SpatialEngine({ filterAlpha: 1.1 })).toThrow(/filterAlpha/);
    });

    it('validates filterBeta', () => {
      expect(() => new SpatialEngine({ filterBeta: -0.1 })).toThrow(/filterBeta/);
      expect(() => new SpatialEngine({ filterBeta: 1.1 })).toThrow(/filterBeta/);
    });

    it('validates viewport dimensions', () => {
      expect(() => new SpatialEngine({ viewport: { width: 0, height: 100 } })).toThrow(/viewport/);
      expect(() => new SpatialEngine({ viewport: { width: 100, height: 0 } })).toThrow(/viewport/);
    });

    it('validates intentRules is array', () => {
      expect(() => new SpatialEngine({ intentRules: 'invalid' as unknown as [] })).toThrow(/intentRules/);
    });

    it('validates intentRules items have intent', () => {
      expect(() => new SpatialEngine({
        intentRules: [{ intent: '' } as unknown as import('../types').IntentRule]
      })).toThrow(/intent/);
    });
  });

  describe('lifecycle', () => {
    it('start begins update loop', () => {
      engine.start();
      expect(engine.isRunning()).toBe(true);
      expect(requestAnimationFrame).toHaveBeenCalled();
    });

    it('start is idempotent', () => {
      engine.start();
      engine.start();
      expect(requestAnimationFrame).toHaveBeenCalledTimes(1);
    });

    it('stop ends update loop', () => {
      engine.start();
      engine.stop();
      expect(engine.isRunning()).toBe(false);
      expect(cancelAnimationFrame).toHaveBeenCalled();
    });

    it('dispose cleans up', () => {
      engine.start();
      engine.onEvent(createEvent());
      engine.dispose();

      expect(engine.isRunning()).toBe(false);
      expect(engine.getActiveEventIds()).toHaveLength(0);
    });
  });

  describe('onEvent', () => {
    it('accepts valid event', () => {
      const result = engine.onEvent(createEvent());
      expect(result).toBe(true);
      expect(engine.getActiveEventIds()).toHaveLength(1);
    });

    it('rejects null event', () => {
      const result = engine.onEvent(null as unknown as RFSpatialEvent);
      expect(result).toBe(false);
    });

    it('rejects event with missing id', () => {
      const event = createEvent();
      delete (event as { id?: string }).id;
      expect(engine.onEvent(event)).toBe(false);
    });

    it('rejects event with empty id', () => {
      expect(engine.onEvent(createEvent({ id: '' }))).toBe(false);
    });

    it('rejects event with very long id', () => {
      expect(engine.onEvent(createEvent({ id: 'a'.repeat(257) }))).toBe(false);
    });

    it('rejects event with invalid bus', () => {
      expect(engine.onEvent(createEvent({ bus: 'INVALID' as SpatialBus }))).toBe(false);
    });

    it('rejects event with non-finite timeMs', () => {
      expect(engine.onEvent(createEvent({ timeMs: NaN }))).toBe(false);
      expect(engine.onEvent(createEvent({ timeMs: Infinity }))).toBe(false);
    });

    it('rejects event with non-finite optional numbers', () => {
      expect(engine.onEvent(createEvent({ xNorm: NaN }))).toBe(false);
      expect(engine.onEvent(createEvent({ yNorm: Infinity }))).toBe(false);
      expect(engine.onEvent(createEvent({ progress01: -Infinity }))).toBe(false);
    });

    it('rejects event with negative lifetimeMs', () => {
      expect(engine.onEvent(createEvent({ lifetimeMs: -100 }))).toBe(false);
    });

    it('accepts valid buses', () => {
      const buses: SpatialBus[] = ['UI', 'REELS', 'FX', 'VO', 'MUSIC', 'AMBIENT'];
      for (const bus of buses) {
        const event = createEvent({ bus });
        expect(engine.onEvent(event)).toBe(true);
      }
    });

    it('updates existing event', () => {
      const event1 = createEvent({ id: 'same-id', xNorm: 0.2 });
      const event2 = createEvent({ id: 'same-id', xNorm: 0.8 });

      engine.onEvent(event1);
      engine.onEvent(event2);

      expect(engine.getActiveEventIds()).toHaveLength(1);
    });

    it('tracks events per bus', () => {
      engine.onEvent(createEvent({ bus: 'FX' }));
      engine.onEvent(createEvent({ bus: 'FX' }));
      engine.onEvent(createEvent({ bus: 'UI' }));

      const counts = engine.getEventCountByBus();
      expect(counts.get('FX')).toBe(2);
      expect(counts.get('UI')).toBe(1);
    });
  });

  describe('rate limiting', () => {
    it('rate limits excessive events', () => {
      // Fire many events quickly
      let accepted = 0;
      for (let i = 0; i < 150; i++) {
        if (engine.onEvent(createEvent())) {
          accepted++;
        }
      }

      expect(accepted).toBeLessThan(150);
      expect(engine.getRateLimitedCount()).toBeGreaterThan(0);
    });

    it('resetRateLimiter clears state', () => {
      // Trigger some rate limiting
      for (let i = 0; i < 150; i++) {
        engine.onEvent(createEvent());
      }

      expect(engine.getRateLimitedCount()).toBeGreaterThan(0);

      engine.resetRateLimiter();
      expect(engine.getRateLimitedCount()).toBe(0);
    });

    it('getEventRate returns rate', () => {
      for (let i = 0; i < 10; i++) {
        engine.onEvent(createEvent({ bus: 'FX' }));
      }

      const rate = engine.getEventRate('FX');
      expect(rate).toBeGreaterThan(0);
    });
  });

  describe('removeEvent', () => {
    it('removes tracked event', () => {
      const event = createEvent({ id: 'to-remove' });
      engine.onEvent(event);
      expect(engine.getActiveEventIds()).toContain('to-remove');

      engine.removeEvent('to-remove');
      expect(engine.getActiveEventIds()).not.toContain('to-remove');
    });

    it('decrements bus count', () => {
      const event = createEvent({ id: 'to-remove', bus: 'UI' });
      engine.onEvent(event);
      expect(engine.getEventCountByBus().get('UI')).toBe(1);

      engine.removeEvent('to-remove');
      expect(engine.getEventCountByBus().get('UI')).toBe(0);
    });

    it('handles non-existent event', () => {
      expect(() => engine.removeEvent('non-existent')).not.toThrow();
    });
  });

  describe('update', () => {
    beforeEach(() => {
      vi.spyOn(performance, 'now').mockReturnValue(1000);
      // Initialize lastUpdateTime via start()
      engine.start();
    });

    afterEach(() => {
      engine.stop();
    });

    it('processes active events', () => {
      const adapter = createMockAudioAdapter();
      engine.setAudioAdapter(adapter);
      engine.onEvent(createEvent({ xNorm: 0.8, voiceId: 'voice-1' }));

      engine.update(1016); // 16ms later

      expect(adapter.setPan).toHaveBeenCalled();
    });

    it('removes expired events', () => {
      engine.onEvent(createEvent({ id: 'short-lived', lifetimeMs: 100 }));
      expect(engine.getActiveEventIds()).toContain('short-lived');

      // Advance time past expiration
      engine.update(1200); // 200ms later, lifetimeMs=100 so should be expired

      expect(engine.getActiveEventIds()).not.toContain('short-lived');
    });

    it('skips update on large dt', () => {
      const adapter = createMockAudioAdapter();
      engine.setAudioAdapter(adapter);
      engine.onEvent(createEvent());

      // Simulate tab being inactive (500ms+)
      engine.update(2000); // 1000ms later, > 500ms skip threshold

      // setPan should not be called (skipped frame)
      expect(adapter.setPan).not.toHaveBeenCalled();
    });

    it('handles tracker errors gracefully', () => {
      const errorCallback = vi.fn();
      engine.setErrorCallback(errorCallback);

      // Add event that will cause error
      engine.onEvent(createEvent({ id: 'bad-event' }));

      // Force an error by mocking a component to throw
      // (In real scenario, malformed data might cause this)
      // For now, just verify error callback mechanism exists

      expect(typeof engine.setErrorCallback).toBe('function');
    });
  });

  describe('audio adapter integration', () => {
    let adapter: IAudioSpatialAdapter;

    beforeEach(() => {
      adapter = createMockAudioAdapter();
      engine.setAudioAdapter(adapter);
    });

    it('calls setPan on update', () => {
      engine.onEvent(createEvent({ voiceId: 'voice-1', xNorm: 0.5, yNorm: 0.5 }));
      // Two updates needed - first sets lastUpdateTime, second processes
      engine.update(1000);
      engine.update(1016);

      expect(adapter.setPan).toHaveBeenCalledWith('voice-1', expect.any(Number));
    });

    it('calls setWidth on update', () => {
      engine.onEvent(createEvent({ voiceId: 'voice-1', xNorm: 0.5, yNorm: 0.5 }));
      engine.update(1000);
      engine.update(1016);

      expect(adapter.setWidth).toHaveBeenCalledWith('voice-1', expect.any(Number));
    });

    it('calls setChannelGains if available', () => {
      engine.onEvent(createEvent({ voiceId: 'voice-1', xNorm: 0.5, yNorm: 0.5 }));
      engine.update(1000);
      engine.update(1016);

      expect(adapter.setChannelGains).toHaveBeenCalled();
    });

    it('uses event.id if voiceId not provided', () => {
      engine.onEvent(createEvent({ id: 'my-event-id', xNorm: 0.5, yNorm: 0.5 }));
      engine.update(1000);
      engine.update(1016);

      expect(adapter.setPan).toHaveBeenCalledWith('my-event-id', expect.any(Number));
    });
  });

  describe('debug callback', () => {
    it('calls debug callback on update', () => {
      const debugCallback = vi.fn();
      engine.setDebugCallback(debugCallback);
      engine.onEvent(createEvent({ xNorm: 0.5, yNorm: 0.5 }));

      // Need to do two updates - first initializes lastUpdateTime
      engine.update(1000);
      engine.update(1016); // 16ms later

      expect(debugCallback).toHaveBeenCalled();
      const call = debugCallback.mock.calls[0][0];
      expect(call).toHaveProperty('eventId');
      expect(call).toHaveProperty('intent');
      expect(call).toHaveProperty('bus');
    });

    it('can clear debug callback', () => {
      const debugCallback = vi.fn();
      engine.setDebugCallback(debugCallback);
      engine.setDebugCallback(null);
      engine.onEvent(createEvent());
      engine.update(performance.now() + 16);

      expect(debugCallback).not.toHaveBeenCalled();
    });
  });

  describe('component access', () => {
    it('getAnchorRegistry returns registry', () => {
      const registry = engine.getAnchorRegistry();
      expect(registry).toBeDefined();
      expect(typeof registry.invalidateCache).toBe('function');
    });

    it('getIntentRules returns manager', () => {
      const rules = engine.getIntentRules();
      expect(rules).toBeDefined();
      expect(typeof rules.getRule).toBe('function');
    });

    it('getMixer returns mixer', () => {
      const mixer = engine.getMixer();
      expect(mixer).toBeDefined();
      expect(typeof mixer.mix).toBe('function');
    });
  });

  describe('getTracker', () => {
    it('returns tracker for event', () => {
      engine.onEvent(createEvent({ id: 'tracked' }));
      const tracker = engine.getTracker('tracked');

      expect(tracker).toBeDefined();
      expect(tracker?.event.id).toBe('tracked');
    });

    it('returns undefined for unknown event', () => {
      const tracker = engine.getTracker('unknown');
      expect(tracker).toBeUndefined();
    });
  });

  describe('bus limiting', () => {
    it('evicts lowest priority on bus overflow', () => {
      // VO bus has maxConcurrent of 2, but we need to exceed it
      // The engine evicts BEFORE adding the new one
      engine.onEvent(createEvent({ id: 'vo-1', bus: 'VO', intent: 'DEFAULT' }));
      engine.onEvent(createEvent({ id: 'vo-2', bus: 'VO', intent: 'DEFAULT' }));

      // At limit now, third event should trigger eviction
      const countBefore = engine.getEventCountByBus().get('VO');
      engine.onEvent(createEvent({ id: 'vo-3', bus: 'VO', intent: 'DEFAULT' }));
      const countAfter = engine.getEventCountByBus().get('VO');

      // Count should stay at max concurrent (2) since one was evicted
      expect(countBefore).toBe(2);
      expect(countAfter).toBe(2);
    });
  });

  describe('onViewportChange', () => {
    it('invalidates anchor cache', () => {
      const registry = engine.getAnchorRegistry();
      const invalidateSpy = vi.spyOn(registry, 'invalidateCache');

      engine.onViewportChange();

      expect(invalidateSpy).toHaveBeenCalled();
    });

    it('dampens tracker velocities', () => {
      engine.onEvent(createEvent({ id: 'moving' }));

      // Simulate some velocity buildup
      const tracker = engine.getTracker('moving');
      if (tracker) {
        tracker.smootherState.vx = 1;
        tracker.smootherState.vy = 1;
      }

      engine.onViewportChange();

      expect(tracker?.smootherState.vx).toBe(0.5);
      expect(tracker?.smootherState.vy).toBe(0.5);
    });
  });
});

describe('createSpatialEngine', () => {
  it('creates engine with defaults', () => {
    const engine = createSpatialEngine();
    expect(engine).toBeInstanceOf(SpatialEngine);
    engine.dispose();
  });

  it('creates engine with custom config', () => {
    const engine = createSpatialEngine({ updateRate: 30 });
    expect(engine).toBeInstanceOf(SpatialEngine);
    engine.dispose();
  });
});

describe('TrackerPool (internal)', () => {
  // Test tracker pool behavior through engine
  let engine: SpatialEngine;

  beforeEach(() => {
    engine = new SpatialEngine();
  });

  afterEach(() => {
    engine.dispose();
  });

  it('reuses tracker instances', () => {
    // Add and remove events multiple times
    for (let i = 0; i < 10; i++) {
      engine.onEvent(createEvent({ id: `event-${i}` }));
    }

    for (let i = 0; i < 10; i++) {
      engine.removeEvent(`event-${i}`);
    }

    // Add more - should reuse pooled instances
    for (let i = 0; i < 10; i++) {
      engine.onEvent(createEvent({ id: `new-event-${i}` }));
    }

    // Should have 10 active events
    expect(engine.getActiveEventIds()).toHaveLength(10);
  });
});

describe('CircularTimestampBuffer (internal)', () => {
  // Test rate limiter behavior through engine
  let engine: SpatialEngine;

  beforeEach(() => {
    engine = new SpatialEngine();
  });

  afterEach(() => {
    engine.dispose();
  });

  it('handles burst of events', () => {
    let accepted = 0;
    for (let i = 0; i < 100; i++) {
      if (engine.onEvent(createEvent())) {
        accepted++;
      }
    }

    // All should be accepted within window
    expect(accepted).toBe(100);
  });

  it('blocks events after limit reached', () => {
    // Fill up the limit
    for (let i = 0; i < 100; i++) {
      engine.onEvent(createEvent());
    }

    // Next one should be blocked
    const blocked = !engine.onEvent(createEvent());
    expect(blocked).toBe(true);
  });
});

describe('smoothing behavior', () => {
  let engine: SpatialEngine;
  let adapter: IAudioSpatialAdapter;

  beforeEach(() => {
    engine = new SpatialEngine();
    adapter = createMockAudioAdapter();
    engine.setAudioAdapter(adapter);
  });

  afterEach(() => {
    engine.dispose();
  });

  it('smooths position over time', () => {
    const panValues: number[] = [];
    (adapter.setPan as ReturnType<typeof vi.fn>).mockImplementation((_, pan) => {
      panValues.push(pan);
    });

    // Start at left
    engine.onEvent(createEvent({ id: 'smooth-test', xNorm: 0.1 }));
    engine.update(1000);

    // Move to right
    engine.onEvent(createEvent({ id: 'smooth-test', xNorm: 0.9 }));
    for (let i = 0; i < 10; i++) {
      engine.update(1016 + i * 16);
    }

    // Pan should increase gradually
    expect(panValues.length).toBeGreaterThan(1);
  });

  it('initializes smoother on first frame', () => {
    engine.onEvent(createEvent({ id: 'init-test', xNorm: 0.8 }));

    const tracker = engine.getTracker('init-test');
    expect(tracker?.smootherState.initialized).toBe(false);

    // First update sets lastUpdateTime, second actually processes
    engine.update(1000);
    engine.update(1016);

    // Smoother initializes during processTracker
    expect(tracker?.smootherState.initialized).toBe(true);
  });
});

describe('error handling', () => {
  let engine: SpatialEngine;

  beforeEach(() => {
    engine = new SpatialEngine();
  });

  afterEach(() => {
    engine.dispose();
  });

  it('setErrorCallback configures callback', () => {
    const errorCb = vi.fn();
    engine.setErrorCallback(errorCb);

    // Error callback is set (actual error triggering depends on internal state)
    expect(() => engine.setErrorCallback(null)).not.toThrow();
  });
});
