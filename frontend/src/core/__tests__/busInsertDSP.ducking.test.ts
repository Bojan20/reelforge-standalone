/**
 * ReelForge M8.2 Bus Insert DSP Ducking Tests
 *
 * Tests for ducking configuration and signal chain logic.
 * Note: WebAudio node operations are not tested here as they require browser APIs.
 * These tests verify the exported constants and configuration.
 */

import { describe, it, expect } from 'vitest';
import { DUCKING_CONFIG } from '../busInsertDSP';

describe('busInsertDSP - Ducking Configuration', () => {
  describe('DUCKING_CONFIG', () => {
    it('should have DUCK_RATIO of 0.35', () => {
      expect(DUCKING_CONFIG.DUCK_RATIO).toBe(0.35);
    });

    it('should have DUCKER_BUS set to voice', () => {
      expect(DUCKING_CONFIG.DUCKER_BUS).toBe('voice');
    });

    it('should have DUCKED_BUS set to music', () => {
      expect(DUCKING_CONFIG.DUCKED_BUS).toBe('music');
    });

    it('should have DUCK_IN_RAMP of 30ms', () => {
      expect(DUCKING_CONFIG.DUCK_IN_RAMP).toBe(0.03);
    });

    it('should have DUCK_OUT_RAMP of 50ms', () => {
      expect(DUCKING_CONFIG.DUCK_OUT_RAMP).toBe(0.05);
    });

    it('should duck faster than unduck (quicker response, smoother recovery)', () => {
      expect(DUCKING_CONFIG.DUCK_IN_RAMP).toBeLessThan(DUCKING_CONFIG.DUCK_OUT_RAMP);
    });

    it('should have ramp times within click-free range (10-100ms)', () => {
      // 10ms minimum to avoid clicks
      expect(DUCKING_CONFIG.DUCK_IN_RAMP).toBeGreaterThanOrEqual(0.01);
      expect(DUCKING_CONFIG.DUCK_OUT_RAMP).toBeGreaterThanOrEqual(0.01);
      // 100ms maximum to stay responsive
      expect(DUCKING_CONFIG.DUCK_IN_RAMP).toBeLessThanOrEqual(0.1);
      expect(DUCKING_CONFIG.DUCK_OUT_RAMP).toBeLessThanOrEqual(0.1);
    });
  });

  describe('Signal Chain Semantics', () => {
    it('should have consistent ducking semantics with previewMixState', () => {
      // The DUCK_RATIO should match the UI-tracked ducking ratio
      // This ensures WebAudio ducking matches UI visualization
      expect(DUCKING_CONFIG.DUCK_RATIO).toBe(0.35);
      expect(DUCKING_CONFIG.DUCKER_BUS).toBe('voice');
      expect(DUCKING_CONFIG.DUCKED_BUS).toBe('music');
    });

    it('should use insertable bus IDs for ducking (not master)', () => {
      const insertableBuses = ['music', 'sfx', 'ambience', 'voice'];
      expect(insertableBuses).toContain(DUCKING_CONFIG.DUCKER_BUS);
      expect(insertableBuses).toContain(DUCKING_CONFIG.DUCKED_BUS);
    });

    it('should not duck the master bus', () => {
      expect(DUCKING_CONFIG.DUCKED_BUS).not.toBe('master');
      expect(DUCKING_CONFIG.DUCKER_BUS).not.toBe('master');
    });
  });
});
