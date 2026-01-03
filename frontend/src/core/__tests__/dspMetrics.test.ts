/**
 * ReelForge M8.8 DSP Metrics Tests
 *
 * Unit tests for the DSP metrics tracking module.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { dspMetrics, type DSPGraphType } from '../dspMetrics';

describe('dspMetrics', () => {
  beforeEach(() => {
    dspMetrics.reset();
  });

  describe('graphCreated', () => {
    it('should increment created count', () => {
      dspMetrics.graphCreated('voiceChain');
      const snapshot = dspMetrics.getSnapshot();

      expect(snapshot.totalCreated).toBe(1);
      expect(snapshot.byType.voiceChain.created).toBe(1);
    });

    it('should track multiple types', () => {
      dspMetrics.graphCreated('voiceChain');
      dspMetrics.graphCreated('voiceInsert');
      dspMetrics.graphCreated('busChain');

      const snapshot = dspMetrics.getSnapshot();
      expect(snapshot.totalCreated).toBe(3);
      expect(snapshot.byType.voiceChain.created).toBe(1);
      expect(snapshot.byType.voiceInsert.created).toBe(1);
      expect(snapshot.byType.busChain.created).toBe(1);
    });
  });

  describe('graphDisposed', () => {
    it('should increment disposed count', () => {
      dspMetrics.graphCreated('voiceChain');
      dspMetrics.graphDisposed('voiceChain');

      const snapshot = dspMetrics.getSnapshot();
      expect(snapshot.totalDisposed).toBe(1);
      expect(snapshot.byType.voiceChain.disposed).toBe(1);
    });

    it('should calculate active correctly', () => {
      dspMetrics.graphCreated('voiceChain');
      dspMetrics.graphCreated('voiceChain');
      dspMetrics.graphDisposed('voiceChain');

      const snapshot = dspMetrics.getSnapshot();
      expect(snapshot.activeGraphs).toBe(1);
      expect(snapshot.byType.voiceChain.active).toBe(1);
    });
  });

  describe('getActiveCount', () => {
    it('should return 0 initially', () => {
      expect(dspMetrics.getActiveCount()).toBe(0);
    });

    it('should track active count across types', () => {
      dspMetrics.graphCreated('voiceChain');
      dspMetrics.graphCreated('busChain');
      dspMetrics.graphCreated('masterChain');

      expect(dspMetrics.getActiveCount()).toBe(3);

      dspMetrics.graphDisposed('voiceChain');
      expect(dspMetrics.getActiveCount()).toBe(2);
    });
  });

  describe('getActiveCountByType', () => {
    it('should return 0 for unused type', () => {
      expect(dspMetrics.getActiveCountByType('masterInsert')).toBe(0);
    });

    it('should track per-type active count', () => {
      dspMetrics.graphCreated('voiceInsert');
      dspMetrics.graphCreated('voiceInsert');
      dspMetrics.graphCreated('voiceInsert');
      dspMetrics.graphDisposed('voiceInsert');

      expect(dspMetrics.getActiveCountByType('voiceInsert')).toBe(2);
    });
  });

  describe('getSnapshot', () => {
    it('should return complete snapshot', () => {
      const snapshot = dspMetrics.getSnapshot();

      expect(snapshot).toHaveProperty('timestamp');
      expect(snapshot).toHaveProperty('totalCreated');
      expect(snapshot).toHaveProperty('totalDisposed');
      expect(snapshot).toHaveProperty('activeGraphs');
      expect(snapshot).toHaveProperty('byType');
      expect(snapshot).toHaveProperty('hasAnomalies');
      expect(snapshot).toHaveProperty('peakActive');
    });

    it('should detect anomalies on double-dispose', () => {
      dspMetrics.graphCreated('voiceChain');
      dspMetrics.graphDisposed('voiceChain');
      dspMetrics.graphDisposed('voiceChain'); // Double dispose!

      const snapshot = dspMetrics.getSnapshot();
      expect(snapshot.hasAnomalies).toBe(true);
      expect(snapshot.byType.voiceChain.active).toBe(-1);
    });

    it('should track peak active', () => {
      dspMetrics.graphCreated('voiceChain');
      dspMetrics.graphCreated('voiceChain');
      dspMetrics.graphCreated('voiceChain');
      // Peak is 3

      dspMetrics.graphDisposed('voiceChain');
      dspMetrics.graphDisposed('voiceChain');
      // Active is now 1, but peak should still be 3

      const snapshot = dspMetrics.getSnapshot();
      expect(snapshot.activeGraphs).toBe(1);
      expect(snapshot.peakActive).toBe(3);
    });
  });

  describe('reset', () => {
    it('should clear all counters', () => {
      dspMetrics.graphCreated('voiceChain');
      dspMetrics.graphCreated('busChain');
      dspMetrics.graphDisposed('voiceChain');

      dspMetrics.reset();

      const snapshot = dspMetrics.getSnapshot();
      expect(snapshot.totalCreated).toBe(0);
      expect(snapshot.totalDisposed).toBe(0);
      expect(snapshot.activeGraphs).toBe(0);
      expect(snapshot.peakActive).toBe(0);
    });
  });

  describe('assertAllDisposed', () => {
    it('should not throw when all disposed', () => {
      dspMetrics.graphCreated('voiceChain');
      dspMetrics.graphDisposed('voiceChain');

      expect(() => dspMetrics.assertAllDisposed()).not.toThrow();
    });

    it('should throw when active graphs remain', () => {
      dspMetrics.graphCreated('voiceChain');

      expect(() => dspMetrics.assertAllDisposed()).toThrow(/DSP leak detected/);
    });

    it('should throw on anomalies', () => {
      dspMetrics.graphCreated('voiceChain');
      dspMetrics.graphDisposed('voiceChain');
      dspMetrics.graphDisposed('voiceChain'); // Double dispose

      // Double dispose results in -1 active, which throws leak error
      expect(() => dspMetrics.assertAllDisposed()).toThrow(/DSP leak detected/);
    });
  });
});

describe('dspMetrics flood test', () => {
  beforeEach(() => {
    dspMetrics.reset();
  });

  it('should handle Flood 2000 create/dispose cycles without leaks', () => {
    const FLOOD_COUNT = 2000;

    // Simulate 2000 voice chains being created and disposed
    for (let i = 0; i < FLOOD_COUNT; i++) {
      // Each voice chain has 2 inserts
      dspMetrics.graphCreated('voiceChain');
      dspMetrics.graphCreated('voiceInsert');
      dspMetrics.graphCreated('voiceInsert');
    }

    // Now dispose all
    for (let i = 0; i < FLOOD_COUNT; i++) {
      dspMetrics.graphDisposed('voiceInsert');
      dspMetrics.graphDisposed('voiceInsert');
      dspMetrics.graphDisposed('voiceChain');
    }

    const snapshot = dspMetrics.getSnapshot();

    // Verify counts
    expect(snapshot.totalCreated).toBe(FLOOD_COUNT * 3);
    expect(snapshot.totalDisposed).toBe(FLOOD_COUNT * 3);
    expect(snapshot.activeGraphs).toBe(0);
    expect(snapshot.hasAnomalies).toBe(false);

    // Should not throw
    dspMetrics.assertAllDisposed();
  });

  it('should handle interleaved create/dispose (realistic pattern)', () => {
    const CYCLES = 500;

    for (let cycle = 0; cycle < CYCLES; cycle++) {
      // Create 4 voices
      for (let i = 0; i < 4; i++) {
        dspMetrics.graphCreated('voiceChain');
        dspMetrics.graphCreated('voiceInsert');
      }

      // Dispose 2 voices (overlapping sounds)
      for (let i = 0; i < 2; i++) {
        dspMetrics.graphDisposed('voiceInsert');
        dspMetrics.graphDisposed('voiceChain');
      }
    }

    // At this point we have (4-2) * 500 = 1000 active
    expect(dspMetrics.getActiveCount()).toBe(1000 * 2); // chains + inserts

    // Dispose remaining
    for (let i = 0; i < 1000; i++) {
      dspMetrics.graphDisposed('voiceInsert');
      dspMetrics.graphDisposed('voiceChain');
    }

    dspMetrics.assertAllDisposed();
  });
});

describe('dspMetrics bus/master lifecycle', () => {
  beforeEach(() => {
    dspMetrics.reset();
  });

  it('should track bus chain lifecycle correctly', () => {
    // Initialize: 4 bus chains
    const BUS_COUNT = 4;
    for (let i = 0; i < BUS_COUNT; i++) {
      dspMetrics.graphCreated('busChain');
    }

    // Add some inserts
    dspMetrics.graphCreated('busInsert');
    dspMetrics.graphCreated('busInsert');
    dspMetrics.graphCreated('busInsert');

    expect(dspMetrics.getActiveCountByType('busChain')).toBe(4);
    expect(dspMetrics.getActiveCountByType('busInsert')).toBe(3);

    // Remove one insert
    dspMetrics.graphDisposed('busInsert');
    expect(dspMetrics.getActiveCountByType('busInsert')).toBe(2);

    // Dispose all on cleanup
    dspMetrics.graphDisposed('busInsert');
    dspMetrics.graphDisposed('busInsert');
    for (let i = 0; i < BUS_COUNT; i++) {
      dspMetrics.graphDisposed('busChain');
    }

    dspMetrics.assertAllDisposed();
  });

  it('should track master chain lifecycle correctly', () => {
    // Initialize master chain
    dspMetrics.graphCreated('masterChain');

    // Add/remove inserts
    dspMetrics.graphCreated('masterInsert');
    dspMetrics.graphCreated('masterInsert');
    dspMetrics.graphDisposed('masterInsert');
    dspMetrics.graphCreated('masterInsert');

    expect(dspMetrics.getActiveCountByType('masterChain')).toBe(1);
    expect(dspMetrics.getActiveCountByType('masterInsert')).toBe(2);

    // Cleanup
    dspMetrics.graphDisposed('masterInsert');
    dspMetrics.graphDisposed('masterInsert');
    dspMetrics.graphDisposed('masterChain');

    dspMetrics.assertAllDisposed();
  });
});
