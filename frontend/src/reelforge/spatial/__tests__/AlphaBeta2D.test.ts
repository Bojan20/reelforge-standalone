/**
 * ReelForge Spatial System - Alpha-Beta Filter Tests
 * @module reelforge/spatial/__tests__/AlphaBeta2D
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import {
  AlphaBeta2D,
  ALPHA_BETA_PRESETS,
  createAlphaBeta2D,
  createAlphaBeta2DFromPreset,
  type AlphaBetaConfig,
} from '../core/AlphaBeta2D';

describe('AlphaBeta2D', () => {
  let filter: AlphaBeta2D;

  beforeEach(() => {
    filter = new AlphaBeta2D();
  });

  describe('initialization', () => {
    it('starts uninitialized', () => {
      expect(filter.isInitialized()).toBe(false);
    });

    it('initializes on first update', () => {
      filter.update(0.5, 0.5, 0.016);
      expect(filter.isInitialized()).toBe(true);
    });

    it('initializes on reset', () => {
      filter.reset(0.3, 0.7);
      expect(filter.isInitialized()).toBe(true);
      const pos = filter.getPosition();
      expect(pos.x).toBe(0.3);
      expect(pos.y).toBe(0.7);
    });

    it('defaults to center position on parameterless reset', () => {
      filter.reset();
      const pos = filter.getPosition();
      expect(pos.x).toBe(0.5);
      expect(pos.y).toBe(0.5);
    });

    it('uses DEFAULT preset when no config provided', () => {
      const config = filter.getConfig();
      expect(config).toEqual(ALPHA_BETA_PRESETS.DEFAULT);
    });
  });

  describe('update', () => {
    beforeEach(() => {
      filter.reset(0.5, 0.5);
    });

    it('returns SmoothedSpatial with required properties', () => {
      const result = filter.update(0.6, 0.4, 0.016);

      expect(result).toHaveProperty('x');
      expect(result).toHaveProperty('y');
      expect(result).toHaveProperty('predictedX');
      expect(result).toHaveProperty('predictedY');
      expect(result).toHaveProperty('vx');
      expect(result).toHaveProperty('vy');
    });

    it('moves position towards measurement', () => {
      const initial = filter.getPosition();
      filter.update(0.8, 0.2, 0.016);
      const after = filter.getPosition();

      expect(after.x).toBeGreaterThan(initial.x);
      expect(after.y).toBeLessThan(initial.y);
    });

    it('does not overshoot measurement in single update', () => {
      filter.update(1.0, 0.0, 0.016);
      const pos = filter.getPosition();

      expect(pos.x).toBeLessThan(1.0);
      expect(pos.y).toBeGreaterThan(0.0);
    });

    it('converges to measurement over multiple updates', () => {
      const target = { x: 0.8, y: 0.2 };

      // Simulate 60 frames at 60Hz
      for (let i = 0; i < 60; i++) {
        filter.update(target.x, target.y, 1 / 60);
      }

      const pos = filter.getPosition();
      expect(pos.x).toBeCloseTo(target.x, 1);
      expect(pos.y).toBeCloseTo(target.y, 1);
    });

    it('handles zero dt gracefully', () => {
      const before = filter.getPosition();
      filter.update(0.8, 0.2, 0);
      const after = filter.getPosition();

      expect(after.x).toBe(before.x);
      expect(after.y).toBe(before.y);
    });

    it('handles negative dt gracefully', () => {
      const before = filter.getPosition();
      filter.update(0.8, 0.2, -0.016);
      const after = filter.getPosition();

      expect(after.x).toBe(before.x);
      expect(after.y).toBe(before.y);
    });
  });

  describe('velocity estimation', () => {
    beforeEach(() => {
      filter.reset(0.5, 0.5);
    });

    it('starts with zero velocity', () => {
      const vel = filter.getVelocity();
      expect(vel.vx).toBe(0);
      expect(vel.vy).toBe(0);
    });

    it('estimates velocity when target moves', () => {
      // Move target consistently to the right
      for (let i = 0; i < 10; i++) {
        filter.update(0.5 + i * 0.05, 0.5, 0.016);
      }

      const vel = filter.getVelocity();
      expect(vel.vx).toBeGreaterThan(0);
    });

    it('clamps velocity to max range', () => {
      // Create filter with high beta for fast velocity response
      const fastFilter = new AlphaBeta2D({ beta: 0.5 });
      fastFilter.reset(0, 0);

      // Extreme jump
      fastFilter.update(1, 1, 0.001);
      const vel = fastFilter.getVelocity();

      // Velocity should be clamped to ±5
      expect(Math.abs(vel.vx)).toBeLessThanOrEqual(5);
      expect(Math.abs(vel.vy)).toBeLessThanOrEqual(5);
    });

    it('dampens velocity over time', () => {
      // Build up velocity
      for (let i = 0; i < 10; i++) {
        filter.update(0.5 + i * 0.03, 0.5, 0.016);
      }

      const velBefore = filter.getVelocity();

      // Hold steady position
      for (let i = 0; i < 20; i++) {
        filter.update(0.8, 0.5, 0.016);
      }

      const velAfter = filter.getVelocity();
      expect(Math.abs(velAfter.vx)).toBeLessThan(Math.abs(velBefore.vx));
    });
  });

  describe('prediction', () => {
    beforeEach(() => {
      filter.reset(0.5, 0.5);
    });

    it('predicts ahead when velocity is positive', () => {
      // Build up rightward velocity
      for (let i = 0; i < 10; i++) {
        filter.update(0.5 + i * 0.02, 0.5, 0.016);
      }

      const predicted = filter.getPredicted();
      const current = filter.getPosition();

      expect(predicted.x).toBeGreaterThan(current.x);
    });

    it('clamps prediction to 0..1', () => {
      filter.reset(0.95, 0.95);
      // Build up rightward velocity
      for (let i = 0; i < 10; i++) {
        filter.update(0.95 + i * 0.01, 0.95, 0.016);
      }

      const predicted = filter.getPredicted();
      expect(predicted.x).toBeLessThanOrEqual(1);
      expect(predicted.y).toBeLessThanOrEqual(1);
    });

    it('prediction included in getOutput', () => {
      const output = filter.getOutput();
      expect(output.predictedX).toBeDefined();
      expect(output.predictedY).toBeDefined();
    });
  });

  describe('deadzone', () => {
    it('ignores small movements within deadzone', () => {
      const filter = new AlphaBeta2D({ deadzone: 0.01 });
      filter.reset(0.5, 0.5);

      // Small jitter within deadzone
      filter.update(0.505, 0.495, 0.016);
      const pos = filter.getPosition();

      // Should barely move due to deadzone
      expect(pos.x).toBeCloseTo(0.5, 2);
      expect(pos.y).toBeCloseTo(0.5, 2);
    });

    it('responds to movements outside deadzone', () => {
      const filter = new AlphaBeta2D({ deadzone: 0.01 });
      filter.reset(0.5, 0.5);

      // Large movement outside deadzone
      filter.update(0.6, 0.4, 0.016);
      const pos = filter.getPosition();

      expect(pos.x).toBeGreaterThan(0.5);
      expect(pos.y).toBeLessThan(0.5);
    });
  });

  describe('position clamping', () => {
    it('clamps position to 0..1 range', () => {
      filter.reset(0.95, 0.05);
      filter.update(1.5, -0.5, 0.016);

      const pos = filter.getPosition();
      expect(pos.x).toBeLessThanOrEqual(1);
      expect(pos.x).toBeGreaterThanOrEqual(0);
      expect(pos.y).toBeLessThanOrEqual(1);
      expect(pos.y).toBeGreaterThanOrEqual(0);
    });

    it('clamps reset position', () => {
      filter.reset(1.5, -0.5);
      const pos = filter.getPosition();
      expect(pos.x).toBe(1);
      expect(pos.y).toBe(0);
    });
  });

  describe('snap', () => {
    it('instantly moves to target', () => {
      filter.reset(0, 0);
      filter.snap(0.8, 0.2);

      const pos = filter.getPosition();
      expect(pos.x).toBe(0.8);
      expect(pos.y).toBe(0.2);
    });

    it('resets velocity', () => {
      // Build up velocity
      filter.reset(0.5, 0.5);
      for (let i = 0; i < 10; i++) {
        filter.update(0.5 + i * 0.02, 0.5, 0.016);
      }

      filter.snap(0.8, 0.8);
      const vel = filter.getVelocity();
      expect(vel.vx).toBe(0);
      expect(vel.vy).toBe(0);
    });

    it('clamps snap position', () => {
      filter.snap(1.5, -0.5);
      const pos = filter.getPosition();
      expect(pos.x).toBe(1);
      expect(pos.y).toBe(0);
    });
  });

  describe('nudge', () => {
    it('partially moves towards target', () => {
      filter.reset(0, 0);
      filter.nudge(1, 1, 0.5);

      const pos = filter.getPosition();
      expect(pos.x).toBe(0.5);
      expect(pos.y).toBe(0.5);
    });

    it('amount=0 does not move', () => {
      filter.reset(0.3, 0.3);
      filter.nudge(1, 1, 0);

      const pos = filter.getPosition();
      expect(pos.x).toBe(0.3);
      expect(pos.y).toBe(0.3);
    });

    it('amount=1 snaps to target', () => {
      filter.reset(0, 0);
      filter.nudge(0.8, 0.2, 1);

      const pos = filter.getPosition();
      expect(pos.x).toBe(0.8);
      expect(pos.y).toBe(0.2);
    });

    it('clamps amount to 0..1', () => {
      filter.reset(0, 0);
      filter.nudge(1, 1, 2); // amount > 1

      const pos = filter.getPosition();
      expect(pos.x).toBe(1);
      expect(pos.y).toBe(1);
    });
  });

  describe('clone', () => {
    it('creates independent copy', () => {
      filter.reset(0.3, 0.7);
      filter.update(0.4, 0.6, 0.016);

      const clone = filter.clone();

      // Modify original
      filter.update(0.8, 0.2, 0.016);

      // Clone should not change
      const clonePos = clone.getPosition();
      const origPos = filter.getPosition();

      expect(clonePos.x).not.toBe(origPos.x);
      expect(clonePos.y).not.toBe(origPos.y);
    });

    it('copies all state', () => {
      filter.reset(0.3, 0.7);
      for (let i = 0; i < 5; i++) {
        filter.update(0.4, 0.6, 0.016);
      }

      const clone = filter.clone();

      expect(clone.getPosition()).toEqual(filter.getPosition());
      expect(clone.getVelocity()).toEqual(filter.getVelocity());
      expect(clone.isInitialized()).toBe(filter.isInitialized());
      expect(clone.getConfig()).toEqual(filter.getConfig());
    });
  });

  describe('configuration', () => {
    it('allows config override', () => {
      const customConfig: Partial<AlphaBetaConfig> = {
        alpha: 0.5,
        beta: 0.01,
      };

      const filter = new AlphaBeta2D(customConfig);
      const config = filter.getConfig();

      expect(config.alpha).toBe(0.5);
      expect(config.beta).toBe(0.01);
      // Other values should be from DEFAULT preset
      expect(config.deadzone).toBe(ALPHA_BETA_PRESETS.DEFAULT.deadzone);
    });

    it('setConfig updates config', () => {
      filter.setConfig({ alpha: 0.9 });
      expect(filter.getConfig().alpha).toBe(0.9);
    });

    it('applyPreset applies full preset', () => {
      filter.applyPreset('REELS');
      expect(filter.getConfig()).toEqual(ALPHA_BETA_PRESETS.REELS);
    });

    it('applyPreset falls back to DEFAULT for unknown preset', () => {
      filter.applyPreset('UNKNOWN');
      expect(filter.getConfig()).toEqual(ALPHA_BETA_PRESETS.DEFAULT);
    });
  });
});

describe('ALPHA_BETA_PRESETS', () => {
  const requiredPresets = ['UI', 'REELS', 'FX', 'VO', 'MUSIC', 'AMBIENT', 'DEFAULT'];

  it.each(requiredPresets)('has %s preset', (presetName) => {
    expect(ALPHA_BETA_PRESETS[presetName]).toBeDefined();
  });

  it.each(requiredPresets)('%s preset has all required properties', (presetName) => {
    const preset = ALPHA_BETA_PRESETS[presetName];
    expect(preset.alpha).toBeGreaterThan(0);
    expect(preset.alpha).toBeLessThanOrEqual(1);
    expect(preset.beta).toBeGreaterThan(0);
    expect(preset.beta).toBeLessThanOrEqual(1);
    expect(preset.predictLeadSec).toBeGreaterThanOrEqual(0);
    expect(preset.deadzone).toBeGreaterThanOrEqual(0);
    expect(preset.velocityDamping).toBeGreaterThan(0);
    expect(preset.velocityDamping).toBeLessThanOrEqual(1);
  });

  it('UI preset is most responsive (highest alpha)', () => {
    const alphas = requiredPresets
      .filter(p => p !== 'DEFAULT')
      .map(p => ALPHA_BETA_PRESETS[p].alpha);

    expect(ALPHA_BETA_PRESETS.UI.alpha).toBe(Math.max(...alphas));
  });

  it('AMBIENT preset is smoothest (lowest alpha)', () => {
    const alphas = requiredPresets
      .filter(p => p !== 'DEFAULT')
      .map(p => ALPHA_BETA_PRESETS[p].alpha);

    expect(ALPHA_BETA_PRESETS.AMBIENT.alpha).toBe(Math.min(...alphas));
  });
});

describe('createAlphaBeta2D', () => {
  it('creates filter with default config', () => {
    const filter = createAlphaBeta2D();
    expect(filter).toBeInstanceOf(AlphaBeta2D);
    expect(filter.getConfig()).toEqual(ALPHA_BETA_PRESETS.DEFAULT);
  });

  it('creates filter with custom config', () => {
    const filter = createAlphaBeta2D({ alpha: 0.5 });
    expect(filter.getConfig().alpha).toBe(0.5);
  });
});

describe('createAlphaBeta2DFromPreset', () => {
  it('creates filter from preset', () => {
    const filter = createAlphaBeta2DFromPreset('REELS');
    expect(filter.getConfig()).toEqual(ALPHA_BETA_PRESETS.REELS);
  });

  it('falls back to DEFAULT for unknown preset', () => {
    const filter = createAlphaBeta2DFromPreset('NONEXISTENT');
    expect(filter.getConfig()).toEqual(ALPHA_BETA_PRESETS.DEFAULT);
  });
});

describe('timing', () => {
  it('tracks time since last update', () => {
    // Set up fake timers BEFORE creating filter
    vi.useFakeTimers();
    vi.setSystemTime(1000);

    const filter = createAlphaBeta2D();
    filter.reset(0.5, 0.5);

    const before = filter.getTimeSinceUpdate();

    // Advance time
    vi.advanceTimersByTime(100);

    const after = filter.getTimeSinceUpdate();
    expect(after - before).toBeCloseTo(100, 0);

    vi.useRealTimers();
  });
});
