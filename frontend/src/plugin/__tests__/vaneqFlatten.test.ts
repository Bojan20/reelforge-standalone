/**
 * ReelForge M9.2 VanEQ Flatten/Unflatten Tests
 *
 * Tests for roundtrip conversion between VanEqParams and flat params format.
 * Critical for ensuring data integrity between UI, store, and DSP.
 */

import { describe, it, expect } from 'vitest';
import {
  flattenVanEqParams,
  unflattenVanEqParams,
  DEFAULT_VANEQ_PARAMS,
  DEFAULT_VANEQ_BANDS,
  VALID_VANEQ_BAND_TYPES,
  type VanEqParams,
} from '../vaneqTypes';

describe('flattenVanEqParams', () => {
  it('should flatten default params', () => {
    const flat = flattenVanEqParams(DEFAULT_VANEQ_PARAMS);

    expect(flat.outputGainDb).toBe(0);
    expect(flat['band0_enabled']).toBe(0);
    expect(flat['band0_freqHz']).toBe(30);
    expect(flat['band0_gainDb']).toBe(0);
    expect(flat['band0_type']).toBe(VALID_VANEQ_BAND_TYPES.indexOf('highPass'));
  });

  it('should flatten all 6 bands', () => {
    const flat = flattenVanEqParams(DEFAULT_VANEQ_PARAMS);

    for (let i = 0; i < 6; i++) {
      expect(`band${i}_enabled` in flat).toBe(true);
      expect(`band${i}_type` in flat).toBe(true);
      expect(`band${i}_freqHz` in flat).toBe(true);
      expect(`band${i}_gainDb` in flat).toBe(true);
      expect(`band${i}_q` in flat).toBe(true);
    }
  });

  it('should flatten enabled bands correctly', () => {
    const params: VanEqParams = {
      outputGainDb: 3,
      bands: [
        { enabled: true, type: 'bell', freqHz: 1000, gainDb: 6, q: 2 },
        ...DEFAULT_VANEQ_BANDS.slice(1),
      ] as VanEqParams['bands'],
    };

    const flat = flattenVanEqParams(params);

    expect(flat.outputGainDb).toBe(3);
    expect(flat['band0_enabled']).toBe(1);
    expect(flat['band0_freqHz']).toBe(1000);
    expect(flat['band0_gainDb']).toBe(6);
    expect(flat['band0_q']).toBe(2);
    expect(flat['band0_type']).toBe(VALID_VANEQ_BAND_TYPES.indexOf('bell'));
  });
});

describe('unflattenVanEqParams', () => {
  it('should unflatten to default structure with empty input', () => {
    const params = unflattenVanEqParams({});

    expect(params.outputGainDb).toBe(0);
    expect(params.bands).toHaveLength(6);
    expect(params.bands[0].enabled).toBe(false);
  });

  it('should unflatten explicit enabled=1', () => {
    const flat = {
      'band0_enabled': 1,
      'band0_freqHz': 1000,
      'band0_gainDb': 6,
      'band0_q': 2,
      'band0_type': 0, // bell
    };

    const params = unflattenVanEqParams(flat);

    expect(params.bands[0].enabled).toBe(true);
    expect(params.bands[0].freqHz).toBe(1000);
    expect(params.bands[0].gainDb).toBe(6);
    expect(params.bands[0].q).toBe(2);
  });

  it('should apply defensive fallback: gainDb !== 0 implies enabled', () => {
    const flat = {
      'band0_enabled': 0, // Explicitly disabled
      'band0_gainDb': 6,  // But has non-zero gain
    };

    const params = unflattenVanEqParams(flat);

    // DEFENSIVE: Should be enabled because gainDb !== 0
    expect(params.bands[0].enabled).toBe(true);
  });

  it('should NOT auto-enable when gainDb === 0', () => {
    const flat = {
      'band0_enabled': 0,
      'band0_gainDb': 0,
    };

    const params = unflattenVanEqParams(flat);

    expect(params.bands[0].enabled).toBe(false);
  });
});

describe('flatten/unflatten roundtrip', () => {
  it('should roundtrip default params', () => {
    const original = DEFAULT_VANEQ_PARAMS;
    const flat = flattenVanEqParams(original);
    const restored = unflattenVanEqParams(flat);

    expect(restored.outputGainDb).toBe(original.outputGainDb);
    for (let i = 0; i < 6; i++) {
      expect(restored.bands[i].enabled).toBe(original.bands[i].enabled);
      expect(restored.bands[i].type).toBe(original.bands[i].type);
      expect(restored.bands[i].freqHz).toBe(original.bands[i].freqHz);
      expect(restored.bands[i].gainDb).toBe(original.bands[i].gainDb);
      expect(restored.bands[i].q).toBe(original.bands[i].q);
    }
  });

  it('should roundtrip custom params with enabled bands', () => {
    const original: VanEqParams = {
      outputGainDb: 6,
      bands: [
        { enabled: true, type: 'bell', freqHz: 100, gainDb: 3, q: 1.5 },
        { enabled: false, type: 'lowShelf', freqHz: 200, gainDb: 0, q: 0.707 },
        { enabled: true, type: 'highShelf', freqHz: 8000, gainDb: -3, q: 0.707 },
        { enabled: false, type: 'highPass', freqHz: 60, gainDb: 0, q: 0.707 },
        { enabled: false, type: 'lowPass', freqHz: 16000, gainDb: 0, q: 0.707 },
        { enabled: true, type: 'notch', freqHz: 3000, gainDb: 0, q: 10 },
      ],
    };

    const flat = flattenVanEqParams(original);
    const restored = unflattenVanEqParams(flat);

    expect(restored.outputGainDb).toBe(original.outputGainDb);
    for (let i = 0; i < 6; i++) {
      expect(restored.bands[i].enabled).toBe(original.bands[i].enabled);
      expect(restored.bands[i].type).toBe(original.bands[i].type);
      expect(restored.bands[i].freqHz).toBe(original.bands[i].freqHz);
      expect(restored.bands[i].gainDb).toBe(original.bands[i].gainDb);
      expect(restored.bands[i].q).toBe(original.bands[i].q);
    }
  });

  it('should handle partial flat params gracefully', () => {
    // Simulate a UI update that only sends changed params
    const partial = {
      'band2_freqHz': 5000,
      'band2_gainDb': 3,
      'band2_enabled': 1,
    };

    const params = unflattenVanEqParams(partial);

    // Band 2 should have the updated values
    expect(params.bands[2].freqHz).toBe(5000);
    expect(params.bands[2].gainDb).toBe(3);
    expect(params.bands[2].enabled).toBe(true);

    // Other bands should have defaults
    expect(params.bands[0].enabled).toBe(false);
    expect(params.bands[1].enabled).toBe(false);
  });
});

describe('batch update scenario', () => {
  it('should correctly merge batch updates with enabled flag', () => {
    // Simulate the batch update scenario from VanEQProEditor
    // When user drags a band, we send: { band0_freqHz, band0_gainDb, band0_enabled: 1 }

    const currentParams = {
      outputGainDb: 0,
      'band0_enabled': 0,
      'band0_freqHz': 30,
      'band0_gainDb': 0,
      'band0_q': 0.707,
      'band0_type': 4, // highPass
    };

    // Batch update from UI (implicit enable + freq/gain change)
    const batchUpdate = {
      'band0_enabled': 1,
      'band0_freqHz': 100,
      'band0_gainDb': 3,
    };

    // Merge like the store does
    const merged = { ...currentParams, ...batchUpdate };

    const params = unflattenVanEqParams(merged);

    expect(params.bands[0].enabled).toBe(true);
    expect(params.bands[0].freqHz).toBe(100);
    expect(params.bands[0].gainDb).toBe(3);
  });

  it('should handle multiple sequential updates correctly', () => {
    // First update: user drags band 0
    let flat = {
      'band0_enabled': 1,
      'band0_freqHz': 100,
      'band0_gainDb': 3,
    };
    let params = unflattenVanEqParams(flat);
    expect(params.bands[0].enabled).toBe(true);

    // Second update: user drags band 1 (band 0 should stay enabled)
    flat = {
      ...flattenVanEqParams(params),
      'band1_enabled': 1,
      'band1_freqHz': 500,
      'band1_gainDb': -2,
    };
    params = unflattenVanEqParams(flat);

    expect(params.bands[0].enabled).toBe(true); // Still enabled from first update
    expect(params.bands[0].freqHz).toBe(100);
    expect(params.bands[1].enabled).toBe(true);
    expect(params.bands[1].freqHz).toBe(500);
  });
});
