/**
 * Theme System Tests
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';

// Mock window.matchMedia before importing ThemeManager
vi.stubGlobal('matchMedia', vi.fn().mockImplementation(query => ({
  matches: query === '(prefers-color-scheme: dark)',
  media: query,
  onchange: null,
  addListener: vi.fn(),
  removeListener: vi.fn(),
  addEventListener: vi.fn(),
  removeEventListener: vi.fn(),
  dispatchEvent: vi.fn(),
})));

import { ThemeManager } from '../themeSystem';

// Mock localStorage
const localStorageMock = (() => {
  let store: Record<string, string> = {};
  return {
    getItem: (key: string) => store[key] || null,
    setItem: (key: string, value: string) => { store[key] = value; },
    removeItem: (key: string) => { delete store[key]; },
    clear: () => { store = {}; },
  };
})();

vi.stubGlobal('localStorage', localStorageMock);

describe('ThemeManager', () => {
  beforeEach(() => {
    localStorageMock.clear();
  });

  describe('mode management', () => {
    it('should default to dark mode', () => {
      expect(ThemeManager.getMode()).toBe('dark');
      expect(ThemeManager.getEffectiveMode()).toBe('dark');
    });

    it('should set mode', () => {
      ThemeManager.setMode('light');
      expect(ThemeManager.getMode()).toBe('light');
      expect(ThemeManager.getEffectiveMode()).toBe('light');
    });

    it('should toggle mode', () => {
      ThemeManager.setMode('dark');
      ThemeManager.toggleMode();
      expect(ThemeManager.getMode()).toBe('light');

      ThemeManager.toggleMode();
      expect(ThemeManager.getMode()).toBe('dark');
    });
  });

  describe('preset management', () => {
    it('should have default presets', () => {
      const presets = ThemeManager.getPresets();
      expect(presets.length).toBeGreaterThan(0);
      expect(presets.some(p => p.id === 'reelforge-dark')).toBe(true);
      expect(presets.some(p => p.id === 'wwise')).toBe(true);
    });

    it('should set preset', () => {
      ThemeManager.setPreset('wwise');
      const state = ThemeManager.getState();
      expect(state.preset).toBe('wwise');
    });

    it('presets should have required properties', () => {
      const presets = ThemeManager.getPresets();
      for (const preset of presets) {
        expect(preset.id).toBeDefined();
        expect(preset.name).toBeDefined();
        expect(preset.mode).toBeDefined();
        expect(preset.colors).toBeDefined();
      }
    });
  });

  describe('colors', () => {
    it('should return complete color object', () => {
      const colors = ThemeManager.getColors();
      expect(colors.bg0).toBeDefined();
      expect(colors.textPrimary).toBeDefined();
      expect(colors.accentPrimary).toBeDefined();
    });

    it('should set custom colors', () => {
      ThemeManager.setCustomColor('accentPrimary', '#ff0000');
      const colors = ThemeManager.getColors();
      expect(colors.accentPrimary).toBe('#ff0000');
    });

    it('should reset custom colors', () => {
      ThemeManager.setCustomColor('accentPrimary', '#ff0000');
      ThemeManager.resetCustomColors();
      const colors = ThemeManager.getColors();
      expect(colors.accentPrimary).not.toBe('#ff0000');
    });
  });

  describe('persistence', () => {
    it('should save to localStorage', () => {
      ThemeManager.setMode('light');
      ThemeManager.setPreset('fmod');

      // Check localStorage was called
      const stored = localStorageMock.getItem('reelforge-theme');
      expect(stored).toBeTruthy();

      const parsed = JSON.parse(stored!);
      expect(parsed.mode).toBe('light');
      expect(parsed.preset).toBe('fmod');
    });
  });

  describe('subscriptions', () => {
    it('should notify on changes', () => {
      let notifyCount = 0;
      const unsubscribe = ThemeManager.subscribe(() => {
        notifyCount++;
      });

      ThemeManager.setMode('light');
      expect(notifyCount).toBe(1);

      ThemeManager.setPreset('ableton');
      expect(notifyCount).toBe(2);

      unsubscribe();
      ThemeManager.setMode('dark');
      expect(notifyCount).toBe(2);
    });
  });
});
