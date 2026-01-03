/**
 * Tests for insertChainPresets.ts
 *
 * Covers preset loading, saving, validation, and built-in presets.
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import type { InsertChain, Insert } from '../masterInsertTypes';
import {
  getAllPresets,
  getBuiltInPresets,
  getUserPresets,
  getPresetById,
  saveChainAsPreset,
  deletePreset,
  loadPresetChain,
  validatePreset,
  importPreset,
  clearPresetsCache,
  type InsertChainPreset,
} from '../insertChainPresets';

// Mock localStorage
const localStorageMock = (() => {
  let store: Record<string, string> = {};
  return {
    getItem: vi.fn((key: string) => store[key] || null),
    setItem: vi.fn((key: string, value: string) => {
      store[key] = value;
    }),
    removeItem: vi.fn((key: string) => {
      delete store[key];
    }),
    clear: vi.fn(() => {
      store = {};
    }),
  };
})();

Object.defineProperty(global, 'localStorage', {
  value: localStorageMock,
});

// Sample chain for testing
const sampleChain: InsertChain = {
  inserts: [
    {
      id: 'test_eq_001',
      pluginId: 'eq',
      enabled: true,
      params: {
        bands: [
          { type: 'lowshelf', frequency: 100, gain: 2, q: 0.7 },
          { type: 'peaking', frequency: 1000, gain: 0, q: 1 },
          { type: 'highshelf', frequency: 10000, gain: -1, q: 0.7 },
        ],
      },
    },
  ],
};

describe('insertChainPresets', () => {
  beforeEach(() => {
    // Clear localStorage and preset cache before each test
    localStorageMock.clear();
    clearPresetsCache();
    vi.clearAllMocks();
  });

  describe('built-in presets', () => {
    it('should have at least 3 built-in presets', () => {
      const presets = getBuiltInPresets();
      expect(presets.length).toBeGreaterThanOrEqual(3);
    });

    it('should have "Clean EQ" preset', () => {
      const preset = getPresetById('builtin_clean_eq');
      expect(preset).not.toBeNull();
      expect(preset!.name).toBe('Clean EQ');
      expect(preset!.builtIn).toBe(true);
    });

    it('should have "VO Safe Limiter" preset', () => {
      const preset = getPresetById('builtin_vo_limiter');
      expect(preset).not.toBeNull();
      expect(preset!.name).toBe('VO Safe Limiter');
      expect(preset!.chain.inserts.length).toBe(2); // comp + limiter
    });

    it('should have "Music Bus EQ" preset', () => {
      const preset = getPresetById('builtin_music_eq');
      expect(preset).not.toBeNull();
      expect(preset!.name).toBe('Music Bus EQ');
    });

    it('built-in presets should all be marked as builtIn', () => {
      const presets = getBuiltInPresets();
      for (const preset of presets) {
        expect(preset.builtIn).toBe(true);
      }
    });
  });

  describe('getAllPresets', () => {
    it('should return built-in presets when no user presets exist', () => {
      const presets = getAllPresets();
      const builtIn = getBuiltInPresets();

      expect(presets.length).toBe(builtIn.length);
    });

    it('should combine built-in and user presets', () => {
      // Save a user preset first
      saveChainAsPreset(sampleChain, 'My Custom Preset');

      const presets = getAllPresets();
      const builtIn = getBuiltInPresets();

      expect(presets.length).toBe(builtIn.length + 1);
    });
  });

  describe('saveChainAsPreset', () => {
    it('should save valid chain as preset', () => {
      const preset = saveChainAsPreset(sampleChain, 'Test Preset');

      expect(preset).not.toBeNull();
      expect(preset!.name).toBe('Test Preset');
      expect(preset!.builtIn).toBe(false);
      expect(preset!.version).toBe(1);
      expect(preset!.id).toMatch(/^preset_\d+_[a-z0-9]+$/);
    });

    it('should save preset with description', () => {
      const preset = saveChainAsPreset(
        sampleChain,
        'Described Preset',
        'A preset with description'
      );

      expect(preset!.description).toBe('A preset with description');
    });

    it('should trim whitespace from name', () => {
      const preset = saveChainAsPreset(sampleChain, '  Trimmed Name  ');
      expect(preset!.name).toBe('Trimmed Name');
    });

    it('should use default name for empty name', () => {
      const preset = saveChainAsPreset(sampleChain, '   ');
      expect(preset!.name).toBe('Untitled Preset');
    });

    it('should clone chain with new IDs', () => {
      const preset = saveChainAsPreset(sampleChain, 'Cloned Preset');

      // The stored chain should have different IDs
      expect(preset!.chain.inserts[0].id).not.toBe(sampleChain.inserts[0].id);
    });

    it('should persist to localStorage', () => {
      saveChainAsPreset(sampleChain, 'Persisted Preset');

      expect(localStorageMock.setItem).toHaveBeenCalled();
    });

    it('should return null for invalid chain', () => {
      const invalidChain: InsertChain = {
        inserts: [
          {
            id: 'bad',
            pluginId: 'invalid' as any,
            enabled: true,
            params: {},
          } as Insert,
        ],
      };

      const preset = saveChainAsPreset(invalidChain, 'Invalid');
      expect(preset).toBeNull();
    });
  });

  describe('getUserPresets', () => {
    it('should return empty array when no user presets', () => {
      const presets = getUserPresets();
      expect(presets).toEqual([]);
    });

    it('should return saved user presets', () => {
      saveChainAsPreset(sampleChain, 'User Preset 1');
      saveChainAsPreset(sampleChain, 'User Preset 2');

      const presets = getUserPresets();
      expect(presets.length).toBe(2);
    });
  });

  describe('deletePreset', () => {
    it('should delete user preset', () => {
      const preset = saveChainAsPreset(sampleChain, 'To Delete');
      expect(getUserPresets().length).toBe(1);

      const deleted = deletePreset(preset!.id);

      expect(deleted).toBe(true);
      expect(getUserPresets().length).toBe(0);
    });

    it('should not delete built-in preset', () => {
      const deleted = deletePreset('builtin_clean_eq');

      expect(deleted).toBe(false);
      expect(getPresetById('builtin_clean_eq')).not.toBeNull();
    });

    it('should return false for non-existent preset', () => {
      const deleted = deletePreset('non_existent_preset');
      expect(deleted).toBe(false);
    });
  });

  describe('loadPresetChain', () => {
    it('should load built-in preset chain', () => {
      const chain = loadPresetChain('builtin_clean_eq');

      expect(chain).not.toBeNull();
      expect(chain!.inserts.length).toBeGreaterThan(0);
    });

    it('should load user preset chain', () => {
      const saved = saveChainAsPreset(sampleChain, 'Loadable');
      const chain = loadPresetChain(saved!.id);

      expect(chain).not.toBeNull();
      expect(chain!.inserts.length).toBe(1);
    });

    it('should return clone with new IDs', () => {
      const saved = saveChainAsPreset(sampleChain, 'Clone Test');
      const chain1 = loadPresetChain(saved!.id);
      const chain2 = loadPresetChain(saved!.id);

      // Each load should have different IDs
      expect(chain1!.inserts[0].id).not.toBe(chain2!.inserts[0].id);
    });

    it('should return null for non-existent preset', () => {
      const chain = loadPresetChain('non_existent');
      expect(chain).toBeNull();
    });
  });

  describe('validatePreset', () => {
    it('should validate correct preset object', () => {
      const data: Partial<InsertChainPreset> = {
        name: 'Valid Preset',
        version: 1,
        chain: sampleChain,
      };

      const validated = validatePreset(data);

      expect(validated).not.toBeNull();
      expect(validated!.name).toBe('Valid Preset');
      expect(validated!.builtIn).toBe(false);
    });

    it('should reject non-object input', () => {
      expect(validatePreset(null)).toBeNull();
      expect(validatePreset(undefined)).toBeNull();
      expect(validatePreset('string')).toBeNull();
      expect(validatePreset(123)).toBeNull();
    });

    it('should reject missing name', () => {
      const data = {
        version: 1,
        chain: sampleChain,
      };

      expect(validatePreset(data)).toBeNull();
    });

    it('should reject wrong version', () => {
      const data = {
        name: 'Test',
        version: 2,
        chain: sampleChain,
      };

      expect(validatePreset(data)).toBeNull();
    });

    it('should reject missing chain', () => {
      const data = {
        name: 'Test',
        version: 1,
      };

      expect(validatePreset(data)).toBeNull();
    });

    it('should reject invalid chain', () => {
      const data = {
        name: 'Test',
        version: 1,
        chain: {
          inserts: [{ pluginId: 'invalid' }],
        },
      };

      expect(validatePreset(data)).toBeNull();
    });

    it('should generate ID if not provided', () => {
      const data = {
        name: 'No ID',
        version: 1,
        chain: sampleChain,
      };

      const validated = validatePreset(data);
      expect(validated!.id).toMatch(/^preset_\d+_[a-z0-9]+$/);
    });

    it('should use provided ID if valid', () => {
      const data = {
        id: 'custom_id_123',
        name: 'With ID',
        version: 1,
        chain: sampleChain,
      };

      const validated = validatePreset(data);
      expect(validated!.id).toBe('custom_id_123');
    });
  });

  describe('importPreset', () => {
    it('should import valid preset data', () => {
      const data = {
        name: 'Imported Preset',
        version: 1,
        chain: sampleChain,
      };

      const imported = importPreset(data);

      expect(imported).not.toBeNull();
      expect(imported!.name).toBe('Imported Preset');
      expect(imported!.builtIn).toBe(false);
    });

    it('should generate new ID on import', () => {
      const data = {
        id: 'original_id',
        name: 'Imported',
        version: 1,
        chain: sampleChain,
      };

      const imported = importPreset(data);

      // Should have new ID, not the original
      expect(imported!.id).not.toBe('original_id');
      expect(imported!.id).toMatch(/^preset_\d+_[a-z0-9]+$/);
    });

    it('should add to user presets', () => {
      const data = {
        name: 'To Import',
        version: 1,
        chain: sampleChain,
      };

      importPreset(data);

      const presets = getUserPresets();
      expect(presets.length).toBe(1);
      expect(presets[0].name).toBe('To Import');
    });

    it('should return null for invalid data', () => {
      const imported = importPreset({ invalid: true });
      expect(imported).toBeNull();
    });
  });

  describe('clearPresetsCache', () => {
    it('should force reload from storage', () => {
      // Save preset
      saveChainAsPreset(sampleChain, 'Cached');

      // Clear cache
      clearPresetsCache();

      // Should reload from storage (mocked)
      const presets = getUserPresets();
      // Since localStorage is mocked and setItem was called,
      // getItem should return the data
      expect(localStorageMock.getItem).toHaveBeenCalled();
    });
  });
});
