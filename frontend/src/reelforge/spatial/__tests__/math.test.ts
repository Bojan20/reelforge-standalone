/**
 * ReelForge Spatial System - Math Utilities Tests
 * @module reelforge/spatial/__tests__/math
 */

import { describe, it, expect } from 'vitest';
import {
  clamp01,
  clamp,
  lerp,
  inverseLerp,
  remap,
  smoothstep,
  smootherstep,
  expDecay,
  distance,
  distanceSq,
  normalize2D,
  applyDeadzone,
  equalPowerGains,
  xNormToPan,
  panToXNorm,
  processPan,
  weightedAverage,
  weightedAverage2D,
  calculateVelocity,
  ema,
  isInViewport,
  confidenceDecay,
  combineConfidence,
  dbToLinear,
  linearToDb,
  freqToNorm,
  normToFreq,
} from '../utils/math';

describe('clamp01', () => {
  it('clamps values below 0 to 0', () => {
    expect(clamp01(-0.5)).toBe(0);
    expect(clamp01(-100)).toBe(0);
  });

  it('clamps values above 1 to 1', () => {
    expect(clamp01(1.5)).toBe(1);
    expect(clamp01(100)).toBe(1);
  });

  it('passes through values in range', () => {
    expect(clamp01(0)).toBe(0);
    expect(clamp01(0.5)).toBe(0.5);
    expect(clamp01(1)).toBe(1);
  });
});

describe('clamp', () => {
  it('clamps to arbitrary range', () => {
    expect(clamp(5, 0, 10)).toBe(5);
    expect(clamp(-5, 0, 10)).toBe(0);
    expect(clamp(15, 0, 10)).toBe(10);
  });

  it('handles negative ranges', () => {
    expect(clamp(0, -10, -5)).toBe(-5);
    expect(clamp(-7, -10, -5)).toBe(-7);
    expect(clamp(-15, -10, -5)).toBe(-10);
  });
});

describe('lerp', () => {
  it('interpolates between two values', () => {
    expect(lerp(0, 100, 0)).toBe(0);
    expect(lerp(0, 100, 0.5)).toBe(50);
    expect(lerp(0, 100, 1)).toBe(100);
  });

  it('extrapolates beyond range', () => {
    expect(lerp(0, 100, 1.5)).toBe(150);
    expect(lerp(0, 100, -0.5)).toBe(-50);
  });
});

describe('inverseLerp', () => {
  it('finds t for value between a and b', () => {
    expect(inverseLerp(0, 100, 0)).toBe(0);
    expect(inverseLerp(0, 100, 50)).toBe(0.5);
    expect(inverseLerp(0, 100, 100)).toBe(1);
  });

  it('handles edge case of equal a and b', () => {
    expect(inverseLerp(50, 50, 50)).toBe(0);
  });
});

describe('remap', () => {
  it('remaps value from one range to another', () => {
    expect(remap(5, 0, 10, 0, 100)).toBe(50);
    expect(remap(0, 0, 10, 0, 100)).toBe(0);
    expect(remap(10, 0, 10, 0, 100)).toBe(100);
  });

  it('clamps output to target range', () => {
    expect(remap(15, 0, 10, 0, 100)).toBe(100);
    expect(remap(-5, 0, 10, 0, 100)).toBe(0);
  });
});

describe('smoothstep', () => {
  it('returns 0 at edge0', () => {
    expect(smoothstep(0, 1, 0)).toBe(0);
  });

  it('returns 1 at edge1', () => {
    expect(smoothstep(0, 1, 1)).toBe(1);
  });

  it('returns smooth interpolation in between', () => {
    const mid = smoothstep(0, 1, 0.5);
    expect(mid).toBeCloseTo(0.5, 5);
  });

  it('clamps below edge0', () => {
    expect(smoothstep(0, 1, -0.5)).toBe(0);
  });

  it('clamps above edge1', () => {
    expect(smoothstep(0, 1, 1.5)).toBe(1);
  });
});

describe('smootherstep', () => {
  it('returns 0 at edge0', () => {
    expect(smootherstep(0, 1, 0)).toBe(0);
  });

  it('returns 1 at edge1', () => {
    expect(smootherstep(0, 1, 1)).toBe(1);
  });

  it('returns smooth interpolation in between', () => {
    const mid = smootherstep(0, 1, 0.5);
    expect(mid).toBeCloseTo(0.5, 5);
  });
});

describe('expDecay', () => {
  it('returns 0 at dt=0', () => {
    expect(expDecay(0, 100)).toBe(0);
  });

  it('approaches 1 as dt increases', () => {
    expect(expDecay(1000, 100)).toBeGreaterThan(0.99);
  });

  it('returns 1 for tau <= 0', () => {
    expect(expDecay(50, 0)).toBe(1);
    expect(expDecay(50, -10)).toBe(1);
  });

  it('returns ~0.632 at dt = tau (1 - 1/e)', () => {
    const result = expDecay(100, 100);
    expect(result).toBeCloseTo(1 - 1 / Math.E, 5);
  });
});

describe('distance', () => {
  it('calculates Euclidean distance', () => {
    expect(distance(0, 0, 3, 4)).toBe(5);
    expect(distance(0, 0, 0, 0)).toBe(0);
  });

  it('handles negative coordinates', () => {
    expect(distance(-1, -1, 2, 3)).toBe(5);
  });
});

describe('distanceSq', () => {
  it('calculates squared distance (no sqrt)', () => {
    expect(distanceSq(0, 0, 3, 4)).toBe(25);
  });
});

describe('normalize2D', () => {
  it('normalizes vector to unit length', () => {
    const { x, y } = normalize2D(3, 4);
    expect(x).toBeCloseTo(0.6, 5);
    expect(y).toBeCloseTo(0.8, 5);
  });

  it('returns zero vector for zero input', () => {
    const { x, y } = normalize2D(0, 0);
    expect(x).toBe(0);
    expect(y).toBe(0);
  });
});

describe('applyDeadzone', () => {
  it('snaps values within deadzone to 0', () => {
    expect(applyDeadzone(0.01, 0.05)).toBe(0);
    expect(applyDeadzone(-0.01, 0.05)).toBe(0);
  });

  it('rescales values outside deadzone', () => {
    // With deadzone 0.1, value 0.55 should map to ~0.5
    const result = applyDeadzone(0.55, 0.1);
    expect(result).toBeCloseTo(0.5, 5);
  });

  it('handles negative values', () => {
    const result = applyDeadzone(-0.55, 0.1);
    expect(result).toBeCloseTo(-0.5, 5);
  });
});

describe('equalPowerGains', () => {
  it('returns equal gains at center (pan=0)', () => {
    const { gainL, gainR } = equalPowerGains(0);
    expect(gainL).toBeCloseTo(gainR, 5);
    expect(gainL).toBeCloseTo(Math.SQRT1_2, 5); // -3dB
  });

  it('returns full left at pan=-1', () => {
    const { gainL, gainR } = equalPowerGains(-1);
    expect(gainL).toBeCloseTo(1, 5);
    expect(gainR).toBeCloseTo(0, 5);
  });

  it('returns full right at pan=+1', () => {
    const { gainL, gainR } = equalPowerGains(1);
    expect(gainL).toBeCloseTo(0, 5);
    expect(gainR).toBeCloseTo(1, 5);
  });

  it('maintains constant power (L² + R² ≈ 1)', () => {
    for (const pan of [-1, -0.5, 0, 0.5, 1]) {
      const { gainL, gainR } = equalPowerGains(pan);
      const power = gainL * gainL + gainR * gainR;
      expect(power).toBeCloseTo(1, 5);
    }
  });
});

describe('xNormToPan', () => {
  it('converts normalized X to pan', () => {
    expect(xNormToPan(0)).toBe(-1);
    expect(xNormToPan(0.5)).toBe(0);
    expect(xNormToPan(1)).toBe(1);
  });
});

describe('panToXNorm', () => {
  it('converts pan to normalized X', () => {
    expect(panToXNorm(-1)).toBe(0);
    expect(panToXNorm(0)).toBe(0.5);
    expect(panToXNorm(1)).toBe(1);
  });
});

describe('processPan', () => {
  it('applies deadzone and max limit', () => {
    // Center should stay center
    expect(processPan(0.5, 0.05, 0.9)).toBe(0);

    // Far right should be clamped to maxPan
    const result = processPan(1, 0, 0.8);
    expect(result).toBeCloseTo(0.8, 5);
  });
});

describe('weightedAverage', () => {
  it('calculates weighted average', () => {
    expect(weightedAverage([10, 20], [1, 1])).toBe(15);
    expect(weightedAverage([10, 20], [1, 3])).toBe(17.5);
  });

  it('returns 0 for empty array', () => {
    expect(weightedAverage([], [])).toBe(0);
  });

  it('throws for mismatched lengths', () => {
    expect(() => weightedAverage([1, 2], [1])).toThrow();
  });
});

describe('weightedAverage2D', () => {
  it('calculates weighted average of 2D points', () => {
    const points = [{ x: 0, y: 0 }, { x: 1, y: 1 }];
    const weights = [1, 1];
    const result = weightedAverage2D(points, weights);
    expect(result.x).toBe(0.5);
    expect(result.y).toBe(0.5);
  });

  it('returns center for empty array', () => {
    const result = weightedAverage2D([], []);
    expect(result.x).toBe(0.5);
    expect(result.y).toBe(0.5);
  });
});

describe('calculateVelocity', () => {
  it('calculates velocity from position delta', () => {
    expect(calculateVelocity(1, 0, 1)).toBe(1);
    expect(calculateVelocity(0.5, 0, 0.5)).toBe(1);
  });

  it('returns 0 for zero or negative dt', () => {
    expect(calculateVelocity(1, 0, 0)).toBe(0);
    expect(calculateVelocity(1, 0, -1)).toBe(0);
  });
});

describe('ema', () => {
  it('applies exponential moving average', () => {
    expect(ema(0, 1, 0.5)).toBe(0.5);
    expect(ema(0, 1, 1)).toBe(1);
    expect(ema(0, 1, 0)).toBe(0);
  });
});

describe('isInViewport', () => {
  it('returns true for points in viewport', () => {
    expect(isInViewport(0.5, 0.5)).toBe(true);
    expect(isInViewport(0, 0)).toBe(true);
    expect(isInViewport(1, 1)).toBe(true);
  });

  it('returns false for points outside viewport', () => {
    expect(isInViewport(-0.1, 0.5)).toBe(false);
    expect(isInViewport(0.5, 1.1)).toBe(false);
  });

  it('respects margin', () => {
    expect(isInViewport(-0.05, 0.5, 0.1)).toBe(true);
    expect(isInViewport(1.05, 0.5, 0.1)).toBe(true);
  });
});

describe('confidenceDecay', () => {
  it('returns base confidence at t=0', () => {
    expect(confidenceDecay(1, 0)).toBe(1);
  });

  it('halves confidence at half-life', () => {
    expect(confidenceDecay(1, 500, 500)).toBeCloseTo(0.5, 5);
  });

  it('approaches 0 over time', () => {
    expect(confidenceDecay(1, 5000, 500)).toBeLessThan(0.01);
  });
});

describe('combineConfidence', () => {
  it('returns 0 for empty array', () => {
    expect(combineConfidence()).toBe(0);
  });

  it('returns single value for single input', () => {
    expect(combineConfidence(0.8)).toBeCloseTo(0.8, 5);
  });

  it('combines multiple confidences (geometric mean)', () => {
    const result = combineConfidence(1, 1);
    expect(result).toBeCloseTo(1, 5);

    const result2 = combineConfidence(0.5, 0.5);
    expect(result2).toBeCloseTo(0.5, 5);
  });
});

describe('dbToLinear', () => {
  it('converts dB to linear gain', () => {
    expect(dbToLinear(0)).toBeCloseTo(1, 5);
    expect(dbToLinear(-6)).toBeCloseTo(0.5012, 3);
    expect(dbToLinear(-20)).toBeCloseTo(0.1, 5);
    expect(dbToLinear(20)).toBeCloseTo(10, 5);
  });
});

describe('linearToDb', () => {
  it('converts linear gain to dB', () => {
    expect(linearToDb(1)).toBeCloseTo(0, 5);
    expect(linearToDb(0.5)).toBeCloseTo(-6.02, 1);
    expect(linearToDb(10)).toBeCloseTo(20, 5);
  });

  it('returns -Infinity for zero or negative', () => {
    expect(linearToDb(0)).toBe(-Infinity);
    expect(linearToDb(-1)).toBe(-Infinity);
  });
});

describe('freqToNorm', () => {
  it('converts frequency to normalized 0..1 in log scale', () => {
    expect(freqToNorm(20)).toBeCloseTo(0, 5);
    expect(freqToNorm(20000)).toBeCloseTo(1, 5);
  });

  it('handles mid-range frequencies', () => {
    // ~632 Hz is geometric mean of 20 and 20000
    const midFreq = Math.sqrt(20 * 20000);
    expect(freqToNorm(midFreq)).toBeCloseTo(0.5, 5);
  });
});

describe('normToFreq', () => {
  it('converts normalized 0..1 to frequency in log scale', () => {
    expect(normToFreq(0)).toBeCloseTo(20, 5);
    expect(normToFreq(1)).toBeCloseTo(20000, 5);
  });

  it('roundtrips with freqToNorm', () => {
    for (const freq of [100, 1000, 5000, 15000]) {
      const norm = freqToNorm(freq);
      const back = normToFreq(norm);
      expect(back).toBeCloseTo(freq, 1);
    }
  });
});
