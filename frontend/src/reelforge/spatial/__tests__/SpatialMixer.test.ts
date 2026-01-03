/**
 * ReelForge Spatial System - Spatial Mixer Tests
 * @module reelforge/spatial/__tests__/SpatialMixer
 */

import { describe, it, expect, beforeEach } from 'vitest';
import {
  SpatialMixer,
  createSpatialMixer,
  type SpatialMixerConfig,
} from '../mixers/SpatialMixer';
import type {
  SpatialTarget,
  SmoothedSpatial,
  IntentRule,
  SpatialBus,
  SpatialMixParams,
} from '../types';
import { DEFAULT_BUS_POLICIES } from '../types';

// Test fixtures

function createTarget(overrides?: Partial<SpatialTarget>): SpatialTarget {
  return {
    xNorm: 0.5,
    yNorm: 0.5,
    width: 0.5,
    confidence: 0.9,
    sources: ['EXPLICIT_COORDS'],
    ...overrides,
  };
}

function createSmoothed(overrides?: Partial<SmoothedSpatial>): SmoothedSpatial {
  return {
    x: 0.5,
    y: 0.5,
    predictedX: 0.5,
    predictedY: 0.5,
    vx: 0,
    vy: 0,
    ...overrides,
  };
}

function createRule(overrides?: Partial<IntentRule>): IntentRule {
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

describe('SpatialMixer', () => {
  let mixer: SpatialMixer;

  beforeEach(() => {
    mixer = new SpatialMixer();
  });

  describe('mix', () => {
    it('returns SpatialMixParams with required properties', () => {
      const result = mixer.mix(
        createTarget(),
        createSmoothed(),
        'FX',
        createRule()
      );

      expect(result).toHaveProperty('pan');
      expect(result).toHaveProperty('width');
      expect(result).toHaveProperty('gainL');
      expect(result).toHaveProperty('gainR');
    });

    it('uses predicted position for panning', () => {
      const smoothed = createSmoothed({
        x: 0.5,
        predictedX: 0.8, // Predicted to be on right
      });

      const result = mixer.mix(
        createTarget(),
        smoothed,
        'FX',
        createRule({ deadzone: 0 })
      );

      expect(result.pan).toBeGreaterThan(0); // Right pan
    });

    it('pan is center (0) when position is center (0.5)', () => {
      const result = mixer.mix(
        createTarget(),
        createSmoothed({ predictedX: 0.5 }),
        'FX',
        createRule({ deadzone: 0 })
      );

      expect(result.pan).toBeCloseTo(0, 5);
    });

    it('pan is negative when position is left', () => {
      const result = mixer.mix(
        createTarget(),
        createSmoothed({ predictedX: 0.2 }),
        'FX',
        createRule({ deadzone: 0 })
      );

      expect(result.pan).toBeLessThan(0);
    });

    it('pan is positive when position is right', () => {
      const result = mixer.mix(
        createTarget(),
        createSmoothed({ predictedX: 0.8 }),
        'FX',
        createRule({ deadzone: 0 })
      );

      expect(result.pan).toBeGreaterThan(0);
    });
  });

  describe('deadzone', () => {
    it('applies deadzone to pan', () => {
      // Small movement from center should result in 0 pan
      const result = mixer.mix(
        createTarget(),
        createSmoothed({ predictedX: 0.52 }), // Slightly right
        'FX',
        createRule({ deadzone: 0.1 })
      );

      expect(result.pan).toBe(0);
    });

    it('pans outside deadzone', () => {
      const result = mixer.mix(
        createTarget(),
        createSmoothed({ predictedX: 0.9 }), // Far right
        'FX',
        createRule({ deadzone: 0.1 })
      );

      expect(result.pan).toBeGreaterThan(0);
    });
  });

  describe('maxPan', () => {
    it('limits pan to maxPan', () => {
      const result = mixer.mix(
        createTarget(),
        createSmoothed({ predictedX: 1 }), // Far right
        'FX',
        createRule({ maxPan: 0.5, deadzone: 0 })
      );

      expect(result.pan).toBeLessThanOrEqual(0.5);
    });

    it('limits negative pan to -maxPan', () => {
      const result = mixer.mix(
        createTarget(),
        createSmoothed({ predictedX: 0 }), // Far left
        'FX',
        createRule({ maxPan: 0.5, deadzone: 0 })
      );

      expect(result.pan).toBeGreaterThanOrEqual(-0.5);
    });
  });

  describe('equal-power gains', () => {
    it('has equal gains at center pan', () => {
      const result = mixer.mix(
        createTarget(),
        createSmoothed({ predictedX: 0.5 }),
        'FX',
        createRule({ deadzone: 0 })
      );

      expect(result.gainL).toBeCloseTo(result.gainR, 5);
    });

    it('maintains constant power (L² + R² ≈ 1) at full width', () => {
      const panValues = [0, 0.25, 0.5, 0.75, 1];

      // Use UI bus which has widthMul = 1.0 (FX has 0.8)
      for (const x of panValues) {
        const result = mixer.mix(
          createTarget({ width: 1 }),
          createSmoothed({ predictedX: x }),
          'UI',
          createRule({ deadzone: 0, width: 1 })
        );

        const power = result.gainL * result.gainL + result.gainR * result.gainR;
        expect(power).toBeCloseTo(1, 1);
      }
    });

    it('full left pan: gainL ≈ 1, gainR ≈ 0', () => {
      const result = mixer.mix(
        createTarget({ width: 1 }),
        createSmoothed({ predictedX: 0 }),
        'FX',
        createRule({ deadzone: 0, maxPan: 1, width: 1 })
      );

      expect(result.gainL).toBeGreaterThan(result.gainR);
    });

    it('full right pan: gainL ≈ 0, gainR ≈ 1', () => {
      const result = mixer.mix(
        createTarget({ width: 1 }),
        createSmoothed({ predictedX: 1 }),
        'FX',
        createRule({ deadzone: 0, maxPan: 1, width: 1 })
      );

      expect(result.gainR).toBeGreaterThan(result.gainL);
    });
  });

  describe('width', () => {
    it('width=0 produces mono (equal gains)', () => {
      const result = mixer.mix(
        createTarget({ width: 0 }),
        createSmoothed({ predictedX: 0.8 }), // Panned right
        'FX',
        createRule({ width: 0, deadzone: 0 })
      );

      expect(result.gainL).toBeCloseTo(result.gainR, 5);
    });

    it('width=1 produces full stereo separation', () => {
      const result = mixer.mix(
        createTarget({ width: 1 }),
        createSmoothed({ predictedX: 0.9 }), // Panned right
        'FX',
        createRule({ width: 1, deadzone: 0 })
      );

      // Right should be louder than left
      expect(result.gainR).toBeGreaterThan(result.gainL);
    });

    it('uses effective width from rule and target', () => {
      // FX bus has widthMul 0.8, so effective width = 0.8 * 0.8 = 0.64
      const result = mixer.mix(
        createTarget({ width: 0.8 }),
        createSmoothed({ predictedX: 0.5 }),
        'FX',
        createRule({ width: 0.8 })
      );

      // Width is target.width * policy.widthMul * globalWidthMul
      expect(result.width).toBeCloseTo(0.64, 5);
    });
  });

  describe('LPF mapping', () => {
    it('returns lpfHz when yToLPF is configured', () => {
      const result = mixer.mix(
        createTarget(),
        createSmoothed({ predictedY: 0.5 }),
        'FX',
        createRule({ yToLPF: { minHz: 500, maxHz: 15000 } })
      );

      expect(result.lpfHz).toBeDefined();
      expect(result.lpfHz).toBeGreaterThan(500);
      expect(result.lpfHz).toBeLessThan(15000);
    });

    it('lpfHz is higher at top (y=0)', () => {
      const resultTop = mixer.mix(
        createTarget(),
        createSmoothed({ predictedY: 0 }),
        'FX',
        createRule({ yToLPF: { minHz: 500, maxHz: 15000 } })
      );

      const resultBottom = mixer.mix(
        createTarget(),
        createSmoothed({ predictedY: 1 }),
        'FX',
        createRule({ yToLPF: { minHz: 500, maxHz: 15000 } })
      );

      expect(resultTop.lpfHz!).toBeGreaterThan(resultBottom.lpfHz!);
    });

    it('uses bus policy yLpfRange if rule has none', () => {
      // REELS bus has yLpfRange in default policies
      const result = mixer.mix(
        createTarget(),
        createSmoothed({ predictedY: 0.5 }),
        'REELS',
        createRule() // No yToLPF
      );

      expect(result.lpfHz).toBeDefined();
    });

    it('returns undefined lpfHz when LPF is disabled', () => {
      const disabledMixer = new SpatialMixer({ enableLPF: false });
      const result = disabledMixer.mix(
        createTarget(),
        createSmoothed(),
        'FX',
        createRule({ yToLPF: { minHz: 500, maxHz: 15000 } })
      );

      expect(result.lpfHz).toBeUndefined();
    });
  });

  describe('Y-axis gain', () => {
    it('returns gainDb when yToGainDb is configured and enabled', () => {
      const gainMixer = new SpatialMixer({ enableYGain: true });
      const result = gainMixer.mix(
        createTarget(),
        createSmoothed({ predictedY: 0.5 }),
        'FX',
        createRule({ yToGainDb: { minDb: -12, maxDb: 0 } })
      );

      expect(result.gainDb).toBeDefined();
    });

    it('returns undefined gainDb when disabled', () => {
      const result = mixer.mix(
        createTarget(),
        createSmoothed(),
        'FX',
        createRule({ yToGainDb: { minDb: -12, maxDb: 0 } })
      );

      expect(result.gainDb).toBeUndefined();
    });
  });

  describe('bus policies', () => {
    it('applies bus maxPanMul', () => {
      // VO bus has maxPanMul of 0.25
      const resultVO = mixer.mix(
        createTarget(),
        createSmoothed({ predictedX: 1 }),
        'VO',
        createRule({ maxPan: 1, deadzone: 0 })
      );

      const resultFX = mixer.mix(
        createTarget(),
        createSmoothed({ predictedX: 1 }),
        'FX',
        createRule({ maxPan: 1, deadzone: 0 })
      );

      expect(Math.abs(resultVO.pan)).toBeLessThan(Math.abs(resultFX.pan));
    });

    it('applies bus widthMul', () => {
      // VO bus has widthMul of 0.2
      const resultVO = mixer.mix(
        createTarget({ width: 1 }),
        createSmoothed({ predictedX: 0.8 }),
        'VO',
        createRule({ width: 1 })
      );

      const resultFX = mixer.mix(
        createTarget({ width: 1 }),
        createSmoothed({ predictedX: 0.8 }),
        'FX',
        createRule({ width: 1 })
      );

      expect(resultVO.width).toBeLessThan(resultFX.width);
    });
  });

  describe('getPolicy', () => {
    it('returns policy for bus', () => {
      const policy = mixer.getPolicy('UI');
      expect(policy).toEqual(DEFAULT_BUS_POLICIES.UI);
    });
  });

  describe('setPolicy', () => {
    it('updates policy for bus', () => {
      mixer.setPolicy('UI', { maxPanMul: 0.5 });
      const policy = mixer.getPolicy('UI');
      expect(policy.maxPanMul).toBe(0.5);
    });

    it('preserves other policy properties', () => {
      const originalTauMul = mixer.getPolicy('UI').tauMul;
      mixer.setPolicy('UI', { maxPanMul: 0.5 });
      expect(mixer.getPolicy('UI').tauMul).toBe(originalTauMul);
    });
  });

  describe('getAdjustedSmoothingTau', () => {
    it('multiplies base tau by policy tauMul', () => {
      const baseTau = 100;
      const result = mixer.getAdjustedSmoothingTau(baseTau, 'UI');
      expect(result).toBe(baseTau * DEFAULT_BUS_POLICIES.UI.tauMul);
    });
  });

  describe('canAcceptEvent', () => {
    it('returns true when under limit', () => {
      expect(mixer.canAcceptEvent('UI', 0)).toBe(true);
      expect(mixer.canAcceptEvent('UI', 5)).toBe(true);
    });

    it('returns false when at limit', () => {
      const max = mixer.getMaxConcurrent('UI');
      expect(mixer.canAcceptEvent('UI', max)).toBe(false);
    });
  });

  describe('getMaxConcurrent', () => {
    it('returns maxConcurrent for bus', () => {
      expect(mixer.getMaxConcurrent('UI')).toBe(DEFAULT_BUS_POLICIES.UI.maxConcurrent);
      expect(mixer.getMaxConcurrent('VO')).toBe(DEFAULT_BUS_POLICIES.VO.maxConcurrent);
    });
  });

  describe('quickPan', () => {
    it('calculates pan from xNorm', () => {
      expect(mixer.quickPan(0.5, 'FX')).toBeCloseTo(0, 1);
      expect(mixer.quickPan(0, 'FX')).toBeLessThan(0);
      expect(mixer.quickPan(1, 'FX')).toBeGreaterThan(0);
    });

    it('respects bus policy', () => {
      const panVO = mixer.quickPan(1, 'VO');
      const panFX = mixer.quickPan(1, 'FX');
      expect(Math.abs(panVO)).toBeLessThan(Math.abs(panFX));
    });
  });

  describe('quickGains', () => {
    it('returns stereo gains', () => {
      const gains = mixer.quickGains(0.5, 0.5, 'FX');
      expect(gains).toHaveProperty('gainL');
      expect(gains).toHaveProperty('gainR');
    });

    it('gains sum to constant power', () => {
      const gains = mixer.quickGains(0.8, 1, 'FX');
      const power = gains.gainL * gains.gainL + gains.gainR * gains.gainR;
      expect(power).toBeCloseTo(1, 1);
    });
  });

  describe('toSimpleStereo', () => {
    it('converts mix params to left/right', () => {
      const params: SpatialMixParams = {
        pan: 0,
        width: 1,
        gainL: 0.7,
        gainR: 0.7,
      };

      const result = mixer.toSimpleStereo(params);
      expect(result.left).toBe(0.7);
      expect(result.right).toBe(0.7);
    });

    it('applies gainDb if present', () => {
      const params: SpatialMixParams = {
        pan: 0,
        width: 1,
        gainL: 1,
        gainR: 1,
        gainDb: -6, // ~0.5 linear
      };

      const result = mixer.toSimpleStereo(params);
      expect(result.left).toBeCloseTo(0.5, 1);
      expect(result.right).toBeCloseTo(0.5, 1);
    });
  });

  describe('configuration', () => {
    it('allows globalPanMul override', () => {
      const customMixer = new SpatialMixer({ globalPanMul: 0.5 });
      const result = customMixer.mix(
        createTarget(),
        createSmoothed({ predictedX: 1 }),
        'FX',
        createRule({ maxPan: 1, deadzone: 0 })
      );

      const defaultResult = mixer.mix(
        createTarget(),
        createSmoothed({ predictedX: 1 }),
        'FX',
        createRule({ maxPan: 1, deadzone: 0 })
      );

      expect(Math.abs(result.pan)).toBeLessThan(Math.abs(defaultResult.pan));
    });

    it('allows globalWidthMul override', () => {
      const customMixer = new SpatialMixer({ globalWidthMul: 0.5 });
      const result = customMixer.mix(
        createTarget({ width: 1 }),
        createSmoothed(),
        'FX',
        createRule({ width: 1 })
      );

      expect(result.width).toBeLessThan(1);
    });

    it('setConfig updates configuration', () => {
      mixer.setConfig({ globalPanMul: 0.5 });
      const config = mixer.getConfig();
      expect(config.globalPanMul).toBe(0.5);
    });

    it('getConfig returns copy', () => {
      const config1 = mixer.getConfig();
      const config2 = mixer.getConfig();
      expect(config1).not.toBe(config2);
      expect(config1).toEqual(config2);
    });
  });
});

describe('createSpatialMixer', () => {
  it('creates mixer with default config', () => {
    const mixer = createSpatialMixer();
    expect(mixer).toBeInstanceOf(SpatialMixer);
  });

  it('creates mixer with custom config', () => {
    const mixer = createSpatialMixer({ globalPanMul: 0.5 });
    expect(mixer.getConfig().globalPanMul).toBe(0.5);
  });

  it('allows bus policy overrides', () => {
    const mixer = createSpatialMixer({
      busPolicies: {
        UI: { maxPanMul: 0.3 },
      },
    });

    expect(mixer.getPolicy('UI').maxPanMul).toBe(0.3);
  });
});

describe('edge cases', () => {
  let mixer: SpatialMixer;

  beforeEach(() => {
    mixer = new SpatialMixer();
  });

  it('handles width > 1 (clamps)', () => {
    const result = mixer.mix(
      createTarget({ width: 2 }),
      createSmoothed(),
      'FX',
      createRule({ width: 2 })
    );

    expect(result.width).toBeLessThanOrEqual(1);
  });

  it('handles negative width (clamps to 0)', () => {
    const result = mixer.mix(
      createTarget({ width: -1 }),
      createSmoothed(),
      'FX',
      createRule({ width: -1 })
    );

    expect(result.width).toBeGreaterThanOrEqual(0);
  });

  it('handles positions outside 0..1', () => {
    const result = mixer.mix(
      createTarget(),
      createSmoothed({ predictedX: 1.5, predictedY: -0.5 }),
      'FX',
      createRule({ deadzone: 0 })
    );

    // Should still produce valid output
    expect(result.pan).toBeGreaterThanOrEqual(-1);
    expect(result.pan).toBeLessThanOrEqual(1);
  });
});
