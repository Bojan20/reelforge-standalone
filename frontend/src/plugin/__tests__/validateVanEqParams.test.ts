/**
 * ReelForge M9.2 VanEQ Validation Tests
 */

import { describe, it, expect } from 'vitest';
import {
  validateVanEqParams,
  clampVanEqBand,
  clampVanEqParams,
  getDefaultVanEqParams,
} from '../validateVanEqParams';
import { DEFAULT_VANEQ_PARAMS, VANEQ_CONSTRAINTS } from '../vaneqTypes';

describe('validateVanEqParams', () => {
  describe('valid params', () => {
    it('should accept default params', () => {
      const result = validateVanEqParams(DEFAULT_VANEQ_PARAMS);
      expect(result.valid).toBe(true);
      expect(result.errors).toHaveLength(0);
    });

    it('should accept valid custom params', () => {
      const params = {
        outputGainDb: 6,
        bands: [
          { enabled: true, type: 'bell', freqHz: 100, gainDb: 3, q: 1 },
          { enabled: false, type: 'lowShelf', freqHz: 200, gainDb: -3, q: 0.707 },
          { enabled: true, type: 'highShelf', freqHz: 8000, gainDb: 2, q: 0.707 },
          { enabled: false, type: 'lowCut', freqHz: 80, gainDb: 0, q: 1.41 },
          { enabled: false, type: 'highCut', freqHz: 16000, gainDb: 0, q: 1 },
          { enabled: true, type: 'notch', freqHz: 1000, gainDb: 0, q: 10 },
        ],
      };
      const result = validateVanEqParams(params);
      expect(result.valid).toBe(true);
      expect(result.errors).toHaveLength(0);
    });

    it('should accept boundary values', () => {
      const params = {
        outputGainDb: VANEQ_CONSTRAINTS.outputGainDb.max,
        bands: [
          {
            enabled: true,
            type: 'bell',
            freqHz: VANEQ_CONSTRAINTS.freqHz.max,
            gainDb: VANEQ_CONSTRAINTS.gainDb.max,
            q: VANEQ_CONSTRAINTS.q.max,
          },
          {
            enabled: false,
            type: 'bell',
            freqHz: VANEQ_CONSTRAINTS.freqHz.min,
            gainDb: VANEQ_CONSTRAINTS.gainDb.min,
            q: VANEQ_CONSTRAINTS.q.min,
          },
          { enabled: false, type: 'bell', freqHz: 1000, gainDb: 0, q: 1 },
          { enabled: false, type: 'bell', freqHz: 1000, gainDb: 0, q: 1 },
          { enabled: false, type: 'bell', freqHz: 1000, gainDb: 0, q: 1 },
          { enabled: false, type: 'bell', freqHz: 1000, gainDb: 0, q: 1 },
        ],
      };
      const result = validateVanEqParams(params);
      expect(result.valid).toBe(true);
    });
  });

  describe('invalid params - top level', () => {
    it('should reject null', () => {
      const result = validateVanEqParams(null);
      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
    });

    it('should reject undefined', () => {
      const result = validateVanEqParams(undefined);
      expect(result.valid).toBe(false);
    });

    it('should reject non-object', () => {
      const result = validateVanEqParams('string');
      expect(result.valid).toBe(false);
    });

    it('should reject missing outputGainDb', () => {
      const params = { bands: DEFAULT_VANEQ_PARAMS.bands };
      const result = validateVanEqParams(params);
      expect(result.valid).toBe(false);
      expect(result.errors.some((e) => e.field === 'outputGainDb')).toBe(true);
    });

    it('should reject non-number outputGainDb', () => {
      const params = { ...DEFAULT_VANEQ_PARAMS, outputGainDb: 'loud' };
      const result = validateVanEqParams(params);
      expect(result.valid).toBe(false);
    });

    it('should reject NaN outputGainDb', () => {
      const params = { ...DEFAULT_VANEQ_PARAMS, outputGainDb: NaN };
      const result = validateVanEqParams(params);
      expect(result.valid).toBe(false);
    });

    it('should reject Infinity outputGainDb', () => {
      const params = { ...DEFAULT_VANEQ_PARAMS, outputGainDb: Infinity };
      const result = validateVanEqParams(params);
      expect(result.valid).toBe(false);
    });

    it('should reject out-of-range outputGainDb (too low)', () => {
      const params = {
        ...DEFAULT_VANEQ_PARAMS,
        outputGainDb: VANEQ_CONSTRAINTS.outputGainDb.min - 1,
      };
      const result = validateVanEqParams(params);
      expect(result.valid).toBe(false);
    });

    it('should reject out-of-range outputGainDb (too high)', () => {
      const params = {
        ...DEFAULT_VANEQ_PARAMS,
        outputGainDb: VANEQ_CONSTRAINTS.outputGainDb.max + 1,
      };
      const result = validateVanEqParams(params);
      expect(result.valid).toBe(false);
    });
  });

  describe('invalid params - bands array', () => {
    it('should reject missing bands', () => {
      const params = { outputGainDb: 0 };
      const result = validateVanEqParams(params);
      expect(result.valid).toBe(false);
    });

    it('should reject non-array bands', () => {
      const params = { outputGainDb: 0, bands: 'not an array' };
      const result = validateVanEqParams(params);
      expect(result.valid).toBe(false);
    });

    it('should reject wrong band count', () => {
      const params = {
        outputGainDb: 0,
        bands: [
          { enabled: true, type: 'bell', freqHz: 1000, gainDb: 0, q: 1 },
          { enabled: true, type: 'bell', freqHz: 1000, gainDb: 0, q: 1 },
        ],
      };
      const result = validateVanEqParams(params);
      expect(result.valid).toBe(false);
      expect(result.errors.some((e) => e.message.includes('exactly 6'))).toBe(true);
    });
  });

  describe('invalid params - band properties', () => {
    const makeParams = (bandIndex: number, bandOverride: Record<string, unknown>) => ({
      outputGainDb: 0,
      bands: DEFAULT_VANEQ_PARAMS.bands.map((b, i) =>
        i === bandIndex ? { ...b, ...bandOverride } : b
      ),
    });

    it('should reject non-boolean enabled', () => {
      const result = validateVanEqParams(makeParams(0, { enabled: 'yes' }));
      expect(result.valid).toBe(false);
      expect(result.errors.some((e) => e.field === 'bands[0].enabled')).toBe(true);
    });

    it('should reject invalid type', () => {
      const result = validateVanEqParams(makeParams(0, { type: 'invalid' }));
      expect(result.valid).toBe(false);
      expect(result.errors.some((e) => e.field === 'bands[0].type')).toBe(true);
    });

    it('should reject non-number freqHz', () => {
      const result = validateVanEqParams(makeParams(0, { freqHz: 'high' }));
      expect(result.valid).toBe(false);
    });

    it('should reject NaN freqHz', () => {
      const result = validateVanEqParams(makeParams(0, { freqHz: NaN }));
      expect(result.valid).toBe(false);
    });

    it('should reject out-of-range freqHz (too low)', () => {
      const result = validateVanEqParams(
        makeParams(0, { freqHz: VANEQ_CONSTRAINTS.freqHz.min - 1 })
      );
      expect(result.valid).toBe(false);
    });

    it('should reject out-of-range freqHz (too high)', () => {
      const result = validateVanEqParams(
        makeParams(0, { freqHz: VANEQ_CONSTRAINTS.freqHz.max + 1 })
      );
      expect(result.valid).toBe(false);
    });

    it('should reject out-of-range gainDb', () => {
      const result = validateVanEqParams(makeParams(0, { gainDb: 50 }));
      expect(result.valid).toBe(false);
    });

    it('should reject out-of-range q', () => {
      const result = validateVanEqParams(makeParams(0, { q: 0 }));
      expect(result.valid).toBe(false);
    });
  });
});

describe('clampVanEqBand', () => {
  it('should pass through valid values', () => {
    const band = { enabled: true, type: 'bell' as const, freqHz: 1000, gainDb: 3, q: 1 };
    const clamped = clampVanEqBand(band);
    expect(clamped).toEqual(band);
  });

  it('should clamp freqHz to min', () => {
    const band = { enabled: true, type: 'bell' as const, freqHz: 5, gainDb: 0, q: 1 };
    const clamped = clampVanEqBand(band);
    expect(clamped.freqHz).toBe(VANEQ_CONSTRAINTS.freqHz.min);
  });

  it('should clamp freqHz to max', () => {
    const band = { enabled: true, type: 'bell' as const, freqHz: 25000, gainDb: 0, q: 1 };
    const clamped = clampVanEqBand(band);
    expect(clamped.freqHz).toBe(VANEQ_CONSTRAINTS.freqHz.max);
  });

  it('should clamp gainDb to range', () => {
    const band = { enabled: true, type: 'bell' as const, freqHz: 1000, gainDb: 50, q: 1 };
    const clamped = clampVanEqBand(band);
    expect(clamped.gainDb).toBe(VANEQ_CONSTRAINTS.gainDb.max);
  });

  it('should clamp q to range', () => {
    const band = { enabled: true, type: 'bell' as const, freqHz: 1000, gainDb: 0, q: 0 };
    const clamped = clampVanEqBand(band);
    expect(clamped.q).toBe(VANEQ_CONSTRAINTS.q.min);
  });
});

describe('clampVanEqParams', () => {
  it('should clamp outputGainDb', () => {
    const params = { ...DEFAULT_VANEQ_PARAMS, outputGainDb: 50 };
    const clamped = clampVanEqParams(params);
    expect(clamped.outputGainDb).toBe(VANEQ_CONSTRAINTS.outputGainDb.max);
  });

  it('should clamp all bands', () => {
    const params = {
      outputGainDb: 0,
      bands: DEFAULT_VANEQ_PARAMS.bands.map((b) => ({
        ...b,
        freqHz: 50000, // Out of range
      })),
    } as typeof DEFAULT_VANEQ_PARAMS;
    const clamped = clampVanEqParams(params);
    clamped.bands.forEach((b) => {
      expect(b.freqHz).toBe(VANEQ_CONSTRAINTS.freqHz.max);
    });
  });
});

describe('getDefaultVanEqParams', () => {
  it('should return a deep clone of defaults', () => {
    const params1 = getDefaultVanEqParams();
    const params2 = getDefaultVanEqParams();
    expect(params1).toEqual(params2);
    expect(params1).not.toBe(params2);
    expect(params1.bands).not.toBe(params2.bands);
  });

  it('should return valid params', () => {
    const params = getDefaultVanEqParams();
    const result = validateVanEqParams(params);
    expect(result.valid).toBe(true);
  });
});
