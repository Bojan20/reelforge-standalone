/**
 * ReelForge M7.1 Preview Mix State Tests
 *
 * Tests for the pure preview mix state functions.
 * Backend-agnostic - tests only the state logic.
 */

import { describe, it, expect } from 'vitest';
import {
  createInitialPreviewMixState,
  setBusGain,
  incrementVoiceCount,
  decrementVoiceCount,
  setVoiceCount,
  resetPreviewMixState,
  fullResetPreviewMixState,
  calculateEffectiveBusGain,
  calculateVoiceOutputGain,
  getTotalActiveVoices,
  getVoicesByBus,
  DUCKING_CONFIG,
} from '../previewMixState';

describe('previewMixState', () => {
  describe('createInitialPreviewMixState', () => {
    it('should create state with all buses at gain 1', () => {
      const state = createInitialPreviewMixState();

      expect(state.masterGain).toBe(1);
      expect(state.buses.music.gain).toBe(1);
      expect(state.buses.sfx.gain).toBe(1);
      expect(state.buses.voice.gain).toBe(1);
      expect(state.buses.ambience.gain).toBe(1);
    });

    it('should create state with no active voices', () => {
      const state = createInitialPreviewMixState();

      expect(state.buses.music.activeVoices).toBe(0);
      expect(state.buses.sfx.activeVoices).toBe(0);
      expect(state.buses.voice.activeVoices).toBe(0);
      expect(getTotalActiveVoices(state)).toBe(0);
    });

    it('should have ducking off by default', () => {
      const state = createInitialPreviewMixState();

      expect(state.duckingActive).toBe(false);
      expect(state.buses.music.isDucked).toBe(false);
    });
  });

  describe('gain composition', () => {
    it('should calculate output gain as playGain * busGain * masterGain', () => {
      let state = createInitialPreviewMixState();

      // Default: all gains at 1
      expect(calculateVoiceOutputGain(state, 0.5, 'sfx')).toBe(0.5);

      // Set bus gain to 0.8
      state = setBusGain(state, 'sfx', 0.8);
      expect(calculateVoiceOutputGain(state, 0.5, 'sfx')).toBeCloseTo(0.4);

      // Set master gain to 0.5
      state = setBusGain(state, 'master', 0.5);
      expect(calculateVoiceOutputGain(state, 0.5, 'sfx')).toBeCloseTo(0.2);
    });

    it('should apply ducking to music bus in gain calculation', () => {
      let state = createInitialPreviewMixState();

      // Music at full, no ducking
      expect(calculateVoiceOutputGain(state, 1, 'music')).toBe(1);

      // Activate ducking by adding VO voice
      state = incrementVoiceCount(state, 'voice');
      expect(state.duckingActive).toBe(true);

      // Music should now be ducked
      const expectedGain = 1 * DUCKING_CONFIG.DUCK_RATIO * 1; // action * duckedBus * master
      expect(calculateVoiceOutputGain(state, 1, 'music')).toBeCloseTo(expectedGain);
    });
  });

  describe('ducking', () => {
    it('should activate ducking when VO voice starts', () => {
      let state = createInitialPreviewMixState();

      expect(state.duckingActive).toBe(false);
      expect(state.buses.music.isDucked).toBe(false);

      // Start VO voice
      state = incrementVoiceCount(state, 'voice');

      expect(state.duckingActive).toBe(true);
      expect(state.buses.music.isDucked).toBe(true);
      expect(state.buses.music.gain).toBeCloseTo(DUCKING_CONFIG.DUCK_RATIO);
    });

    it('should maintain ducking while any VO is active', () => {
      let state = createInitialPreviewMixState();

      // Start 3 VO voices
      state = incrementVoiceCount(state, 'voice');
      state = incrementVoiceCount(state, 'voice');
      state = incrementVoiceCount(state, 'voice');

      expect(state.duckingActive).toBe(true);
      expect(state.buses.voice.activeVoices).toBe(3);

      // Remove 2 voices - still ducking
      state = decrementVoiceCount(state, 'voice');
      state = decrementVoiceCount(state, 'voice');

      expect(state.duckingActive).toBe(true);
      expect(state.buses.voice.activeVoices).toBe(1);
    });

    it('should release ducking when last VO stops', () => {
      let state = createInitialPreviewMixState();

      // Start and stop VO
      state = incrementVoiceCount(state, 'voice');
      expect(state.duckingActive).toBe(true);

      state = decrementVoiceCount(state, 'voice');

      expect(state.duckingActive).toBe(false);
      expect(state.buses.music.isDucked).toBe(false);
      expect(state.buses.music.gain).toBe(1);
    });

    it('should restore music to base gain when ducking ends', () => {
      let state = createInitialPreviewMixState();

      // Set music to 0.7
      state = setBusGain(state, 'music', 0.7);
      expect(state.buses.music.baseGain).toBe(0.7);

      // Start VO - music should be ducked
      state = incrementVoiceCount(state, 'voice');
      expect(state.buses.music.gain).toBeCloseTo(0.7 * DUCKING_CONFIG.DUCK_RATIO);

      // Stop VO - music should restore to base
      state = decrementVoiceCount(state, 'voice');
      expect(state.buses.music.gain).toBe(0.7);
    });

    it('should not affect other buses during ducking', () => {
      let state = createInitialPreviewMixState();

      state = incrementVoiceCount(state, 'voice');

      expect(state.buses.sfx.gain).toBe(1);
      expect(state.buses.sfx.isDucked).toBe(false);
      expect(state.buses.ambience.gain).toBe(1);
    });
  });

  describe('StopAll', () => {
    it('should clear all voice counts', () => {
      let state = createInitialPreviewMixState();

      // Add voices to multiple buses
      state = incrementVoiceCount(state, 'music');
      state = incrementVoiceCount(state, 'music');
      state = incrementVoiceCount(state, 'sfx');
      state = incrementVoiceCount(state, 'voice');
      state = incrementVoiceCount(state, 'ambience');

      expect(getTotalActiveVoices(state)).toBe(5);

      // Reset
      state = resetPreviewMixState(state);

      expect(getTotalActiveVoices(state)).toBe(0);
      expect(state.buses.music.activeVoices).toBe(0);
      expect(state.buses.sfx.activeVoices).toBe(0);
      expect(state.buses.voice.activeVoices).toBe(0);
    });

    it('should turn ducking off', () => {
      let state = createInitialPreviewMixState();

      state = incrementVoiceCount(state, 'voice');
      expect(state.duckingActive).toBe(true);

      state = resetPreviewMixState(state);

      expect(state.duckingActive).toBe(false);
    });

    it('should restore music gain to base', () => {
      let state = createInitialPreviewMixState();

      // Set music to 0.6
      state = setBusGain(state, 'music', 0.6);

      // Start VO - music ducked
      state = incrementVoiceCount(state, 'voice');
      expect(state.buses.music.gain).toBeCloseTo(0.6 * DUCKING_CONFIG.DUCK_RATIO);

      // StopAll
      state = resetPreviewMixState(state);

      expect(state.buses.music.gain).toBe(0.6);
      expect(state.buses.music.baseGain).toBe(0.6);
      expect(state.buses.music.isDucked).toBe(false);
    });

    it('should preserve bus base gains', () => {
      let state = createInitialPreviewMixState();

      state = setBusGain(state, 'music', 0.8);
      state = setBusGain(state, 'sfx', 0.6);
      state = setBusGain(state, 'master', 0.9);

      state = incrementVoiceCount(state, 'sfx');
      state = incrementVoiceCount(state, 'music');

      state = resetPreviewMixState(state);

      expect(state.buses.music.baseGain).toBe(0.8);
      expect(state.buses.sfx.baseGain).toBe(0.6);
      expect(state.masterGain).toBe(0.9);
    });
  });

  describe('SetBusGain', () => {
    it('should update bus base gain', () => {
      let state = createInitialPreviewMixState();

      state = setBusGain(state, 'music', 0.7);

      expect(state.buses.music.baseGain).toBe(0.7);
      expect(state.buses.music.gain).toBe(0.7);
    });

    it('should update master gain separately', () => {
      let state = createInitialPreviewMixState();

      state = setBusGain(state, 'master', 0.5);

      expect(state.masterGain).toBe(0.5);
    });

    it('should clamp gain to 0-1 range', () => {
      let state = createInitialPreviewMixState();

      state = setBusGain(state, 'sfx', 1.5);
      expect(state.buses.sfx.gain).toBe(1);

      state = setBusGain(state, 'sfx', -0.5);
      expect(state.buses.sfx.gain).toBe(0);
    });

    it('should recalculate effective gain when ducking is active', () => {
      let state = createInitialPreviewMixState();

      // Start VO - ducking active
      state = incrementVoiceCount(state, 'voice');
      expect(state.duckingActive).toBe(true);

      // Change music gain while ducked
      state = setBusGain(state, 'music', 0.8);

      // Base should be 0.8, effective should be ducked
      expect(state.buses.music.baseGain).toBe(0.8);
      expect(calculateEffectiveBusGain(state, 'music')).toBeCloseTo(0.8 * DUCKING_CONFIG.DUCK_RATIO);
    });
  });

  describe('voice counting', () => {
    it('should increment voice count', () => {
      let state = createInitialPreviewMixState();

      state = incrementVoiceCount(state, 'sfx');
      expect(state.buses.sfx.activeVoices).toBe(1);

      state = incrementVoiceCount(state, 'sfx');
      expect(state.buses.sfx.activeVoices).toBe(2);
    });

    it('should decrement voice count', () => {
      let state = createInitialPreviewMixState();

      state = setVoiceCount(state, 'sfx', 5);
      expect(state.buses.sfx.activeVoices).toBe(5);

      state = decrementVoiceCount(state, 'sfx');
      expect(state.buses.sfx.activeVoices).toBe(4);
    });

    it('should not go below 0', () => {
      let state = createInitialPreviewMixState();

      state = decrementVoiceCount(state, 'sfx');
      expect(state.buses.sfx.activeVoices).toBe(0);
    });

    it('should be bounded at max voices', () => {
      let state = createInitialPreviewMixState();

      // Set to max (64)
      for (let i = 0; i < 100; i++) {
        state = incrementVoiceCount(state, 'sfx');
      }

      expect(state.buses.sfx.activeVoices).toBe(64);
    });

    it('should track voices per bus independently', () => {
      let state = createInitialPreviewMixState();

      state = incrementVoiceCount(state, 'sfx');
      state = incrementVoiceCount(state, 'sfx');
      state = incrementVoiceCount(state, 'music');
      state = incrementVoiceCount(state, 'voice');

      const byBus = getVoicesByBus(state);
      expect(byBus.sfx).toBe(2);
      expect(byBus.music).toBe(1);
      expect(byBus.voice).toBe(1);
      expect(byBus.ambience).toBe(0);
    });
  });

  describe('fullResetPreviewMixState', () => {
    it('should reset everything to initial values', () => {
      let state = createInitialPreviewMixState();

      // Modify everything
      state = setBusGain(state, 'music', 0.5);
      state = setBusGain(state, 'master', 0.8);
      state = incrementVoiceCount(state, 'voice');
      state = incrementVoiceCount(state, 'sfx');

      // Full reset
      state = fullResetPreviewMixState();

      expect(state.masterGain).toBe(1);
      expect(state.buses.music.baseGain).toBe(1);
      expect(state.buses.music.gain).toBe(1);
      expect(state.duckingActive).toBe(false);
      expect(getTotalActiveVoices(state)).toBe(0);
    });
  });
});
