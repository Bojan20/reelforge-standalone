/**
 * ReelForge M8.3 Insert Chain Presets
 *
 * Preset system for saving and loading insert chain configurations.
 * Includes built-in starter presets and user preset storage.
 */

import type { InsertChain } from './masterInsertTypes';
import { validateMasterInsertChain } from './validateMasterInserts';
import { cloneChain } from './insertChainClipboard';
import {
  DEFAULT_VANEQ_PARAMS,
  flattenVanEqParams,
} from '../plugin/vaneqTypes';
import { getVanCompDefaultParams } from '../plugin/vancomp-pro/vancompDescriptors';
import { getVanLimitDefaultParams } from '../plugin/vanlimit-pro/vanlimitDescriptors';

// ============ Preset Types ============

/** Preset metadata */
export interface PresetMeta {
  /** Unique preset ID */
  id: string;
  /** Display name */
  name: string;
  /** Description (optional) */
  description?: string;
  /** Version for future compatibility */
  version: 1;
  /** Whether this is a built-in preset (non-deletable) */
  builtIn: boolean;
  /** Creation timestamp */
  createdAt: number;
}

/** Full preset with chain data */
export interface InsertChainPreset extends PresetMeta {
  /** The insert chain configuration */
  chain: InsertChain;
}

/** Preset storage format for localStorage */
interface PresetStorage {
  version: 1;
  presets: InsertChainPreset[];
}

// ============ Built-in Presets ============

/**
 * Built-in preset: Clean EQ
 * A neutral 6-band EQ with gentle high-frequency roll-off
 */
const PRESET_CLEAN_EQ: InsertChainPreset = {
  id: 'builtin_clean_eq',
  name: 'Clean EQ',
  description: 'Subtle low-end warmth and gentle high roll-off',
  version: 1,
  builtIn: true,
  createdAt: 0,
  chain: {
    inserts: [
      {
        id: 'preset_eq_1',
        pluginId: 'vaneq',
        enabled: true,
        params: {
          ...flattenVanEqParams(DEFAULT_VANEQ_PARAMS),
          // Low shelf warmth
          band0_freqHz: 80,
          band0_gainDb: 2,
          band0_q: 0.7,
          // Mid cut
          band2_freqHz: 2500,
          band2_gainDb: -1,
          band2_q: 1.5,
          // High shelf rolloff
          band5_freqHz: 12000,
          band5_gainDb: -2,
          band5_q: 0.7,
        },
      },
    ],
  },
};

/**
 * Built-in preset: VO Safe Limiter
 * Configured for voice-over with gentle compression and limiting
 */
const PRESET_VO_SAFE_LIMITER: InsertChainPreset = {
  id: 'builtin_vo_limiter',
  name: 'VO Safe Limiter',
  description: 'Gentle compression + brick-wall limiter for voice',
  version: 1,
  builtIn: true,
  createdAt: 0,
  chain: {
    inserts: [
      {
        id: 'preset_comp_1',
        pluginId: 'vancomp',
        enabled: true,
        params: {
          ...getVanCompDefaultParams(),
          thresholdDb: -18,
          ratio: 3,
          attackMs: 10,
          releaseMs: 150,
          kneeDb: 10,
        },
      },
      {
        id: 'preset_limiter_1',
        pluginId: 'vanlimit',
        enabled: true,
        params: {
          ...getVanLimitDefaultParams(),
          thresholdDb: -1,
          releaseMs: 50,
        },
      },
    ],
  },
};

/**
 * Built-in preset: Music Bus EQ
 * EQ curve optimized for background music
 */
const PRESET_MUSIC_BUS_EQ: InsertChainPreset = {
  id: 'builtin_music_eq',
  name: 'Music Bus EQ',
  description: 'Scooped mids for music sitting under dialogue',
  version: 1,
  builtIn: true,
  createdAt: 0,
  chain: {
    inserts: [
      {
        id: 'preset_eq_2',
        pluginId: 'vaneq',
        enabled: true,
        params: {
          ...flattenVanEqParams(DEFAULT_VANEQ_PARAMS),
          // Low shelf cut
          band0_freqHz: 120,
          band0_gainDb: -3,
          band0_q: 0.7,
          // Mid scoop
          band2_freqHz: 800,
          band2_gainDb: -4,
          band2_q: 0.8,
          // High shelf lift
          band5_freqHz: 8000,
          band5_gainDb: 1,
          band5_q: 0.7,
        },
      },
    ],
  },
};

/** All built-in presets */
const BUILT_IN_PRESETS: InsertChainPreset[] = [
  PRESET_CLEAN_EQ,
  PRESET_VO_SAFE_LIMITER,
  PRESET_MUSIC_BUS_EQ,
];

// ============ Preset Storage ============

const STORAGE_KEY = 'reelforge_insert_presets';

/**
 * Load user presets from localStorage.
 */
function loadUserPresets(): InsertChainPreset[] {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (!stored) return [];

    const data = JSON.parse(stored) as PresetStorage;
    if (data.version !== 1) return [];

    // Validate each preset
    return data.presets.filter((preset) => {
      const result = validateMasterInsertChain(preset.chain);
      return result.valid;
    });
  } catch {
    return [];
  }
}

/**
 * Save user presets to localStorage.
 */
function saveUserPresets(presets: InsertChainPreset[]): void {
  const data: PresetStorage = {
    version: 1,
    presets: presets.filter((p) => !p.builtIn),
  };
  localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
}

// ============ Preset Management ============

/** In-memory preset cache */
let userPresets: InsertChainPreset[] | null = null;

/**
 * Get all available presets (built-in + user).
 */
export function getAllPresets(): InsertChainPreset[] {
  if (userPresets === null) {
    userPresets = loadUserPresets();
  }
  return [...BUILT_IN_PRESETS, ...userPresets];
}

/**
 * Get built-in presets only.
 */
export function getBuiltInPresets(): InsertChainPreset[] {
  return [...BUILT_IN_PRESETS];
}

/**
 * Get user presets only.
 */
export function getUserPresets(): InsertChainPreset[] {
  if (userPresets === null) {
    userPresets = loadUserPresets();
  }
  return [...userPresets];
}

/**
 * Get a preset by ID.
 */
export function getPresetById(id: string): InsertChainPreset | null {
  return getAllPresets().find((p) => p.id === id) ?? null;
}

/**
 * Generate a unique preset ID.
 */
function generatePresetId(): string {
  const timestamp = Date.now();
  const random = Math.random().toString(36).substring(2, 6);
  return `preset_${timestamp}_${random}`;
}

/**
 * Save current chain as a new user preset.
 * Returns the new preset or null on validation failure.
 */
export function saveChainAsPreset(
  chain: InsertChain,
  name: string,
  description?: string
): InsertChainPreset | null {
  // Validate chain
  const result = validateMasterInsertChain(chain);
  if (!result.valid) {
    return null;
  }

  // Create preset with cloned chain (new IDs for stored version)
  const preset: InsertChainPreset = {
    id: generatePresetId(),
    name: name.trim() || 'Untitled Preset',
    description: description?.trim(),
    version: 1,
    builtIn: false,
    createdAt: Date.now(),
    chain: cloneChain(chain),
  };

  // Add to cache and persist
  if (userPresets === null) {
    userPresets = loadUserPresets();
  }
  userPresets.push(preset);
  saveUserPresets(userPresets);

  return preset;
}

/**
 * Delete a user preset by ID.
 * Returns true if deleted, false if not found or built-in.
 */
export function deletePreset(id: string): boolean {
  // Can't delete built-in presets
  if (BUILT_IN_PRESETS.some((p) => p.id === id)) {
    return false;
  }

  if (userPresets === null) {
    userPresets = loadUserPresets();
  }

  const index = userPresets.findIndex((p) => p.id === id);
  if (index === -1) return false;

  userPresets.splice(index, 1);
  saveUserPresets(userPresets);
  return true;
}

/**
 * Load a preset's chain (creates new copy with new IDs).
 * Returns null if preset not found or invalid.
 */
export function loadPresetChain(presetId: string): InsertChain | null {
  const preset = getPresetById(presetId);
  if (!preset) return null;

  // Validate before returning
  const result = validateMasterInsertChain(preset.chain);
  if (!result.valid) return null;

  // Return a fresh clone with regenerated IDs
  return cloneChain(preset.chain);
}

/**
 * Validate a preset JSON object.
 * Used when importing presets.
 */
export function validatePreset(data: unknown): InsertChainPreset | null {
  if (!data || typeof data !== 'object') return null;

  const preset = data as Partial<InsertChainPreset>;

  // Check required fields
  if (typeof preset.name !== 'string') return null;
  if (preset.version !== 1) return null;
  if (!preset.chain || typeof preset.chain !== 'object') return null;

  // Validate chain
  const result = validateMasterInsertChain(preset.chain);
  if (!result.valid) return null;

  // Build valid preset
  return {
    id: typeof preset.id === 'string' ? preset.id : generatePresetId(),
    name: preset.name.trim() || 'Untitled',
    description:
      typeof preset.description === 'string' ? preset.description : undefined,
    version: 1,
    builtIn: false,
    createdAt:
      typeof preset.createdAt === 'number' ? preset.createdAt : Date.now(),
    chain: cloneChain(preset.chain),
  };
}

/**
 * Import a preset from JSON data.
 * Returns the imported preset or null on failure.
 */
export function importPreset(data: unknown): InsertChainPreset | null {
  const preset = validatePreset(data);
  if (!preset) return null;

  // Generate new ID to avoid conflicts
  preset.id = generatePresetId();
  preset.builtIn = false;

  // Add to cache and persist
  if (userPresets === null) {
    userPresets = loadUserPresets();
  }
  userPresets.push(preset);
  saveUserPresets(userPresets);

  return preset;
}

/**
 * Clear user presets cache (forces reload from storage).
 */
export function clearPresetsCache(): void {
  userPresets = null;
}
