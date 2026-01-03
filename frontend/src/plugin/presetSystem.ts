/**
 * ReelForge Plugin Preset System
 *
 * Centralized preset management for all plugins:
 * - Factory presets (bundled with plugins)
 * - User presets (saved locally)
 * - A/B comparison state
 * - Import/Export functionality
 *
 * @module plugin/presetSystem
 */

import type { ParamDescriptor } from './ParamDescriptor';

// ============ Types ============

/**
 * Preset metadata and parameter values.
 */
export interface PluginPreset {
  /** Unique preset ID */
  id: string;
  /** Display name */
  name: string;
  /** Plugin ID this preset belongs to */
  pluginId: string;
  /** Plugin version this preset was created for */
  pluginVersion: string;
  /** Preset category for organization */
  category: PresetCategory;
  /** Parameter values */
  params: Record<string, number>;
  /** Creator (factory, user, imported) */
  author: 'factory' | 'user' | 'imported';
  /** Optional description */
  description?: string;
  /** Optional tags for search */
  tags?: string[];
  /** Creation timestamp */
  createdAt: number;
  /** Last modified timestamp */
  modifiedAt: number;
  /** Whether preset is marked as favorite */
  isFavorite?: boolean;
}

/**
 * Preset categories for organization.
 */
export type PresetCategory =
  | 'default'
  | 'init'
  | 'vocal'
  | 'drums'
  | 'bass'
  | 'guitar'
  | 'keys'
  | 'synth'
  | 'master'
  | 'creative'
  | 'subtle'
  | 'aggressive'
  | 'user';

/**
 * A/B comparison state.
 */
export interface ABState {
  /** State A parameters */
  stateA: Record<string, number>;
  /** State B parameters */
  stateB: Record<string, number>;
  /** Currently active state */
  activeState: 'A' | 'B';
  /** Whether A/B mode is enabled */
  enabled: boolean;
}

/**
 * Preset storage interface.
 */
export interface PresetStorage {
  /** Get all presets for a plugin */
  getPresets(pluginId: string): PluginPreset[];
  /** Save a preset */
  savePreset(preset: PluginPreset): void;
  /** Delete a preset */
  deletePreset(presetId: string): void;
  /** Update preset metadata */
  updatePreset(presetId: string, updates: Partial<PluginPreset>): void;
  /** Check if preset exists */
  hasPreset(presetId: string): boolean;
}

// ============ Factory Presets ============

/**
 * Factory presets for VanEQ Pro.
 */
const VANEQ_FACTORY_PRESETS: Omit<PluginPreset, 'id' | 'createdAt' | 'modifiedAt'>[] = [
  {
    name: 'Init',
    pluginId: 'vaneq',
    pluginVersion: '1.0.0',
    category: 'init',
    author: 'factory',
    description: 'Flat response, all bands at unity',
    params: {
      band1_type: 1, band1_freq: 80, band1_gain: 0, band1_q: 0.7, band1_on: 1,
      band2_type: 0, band2_freq: 250, band2_gain: 0, band2_q: 1.0, band2_on: 1,
      band3_type: 0, band3_freq: 1000, band3_gain: 0, band3_q: 1.0, band3_on: 1,
      band4_type: 0, band4_freq: 3000, band4_gain: 0, band4_q: 1.0, band4_on: 1,
      band5_type: 0, band5_freq: 8000, band5_gain: 0, band5_q: 1.0, band5_on: 1,
      band6_type: 2, band6_freq: 12000, band6_gain: 0, band6_q: 0.7, band6_on: 1,
      outputGain: 0,
    },
  },
  {
    name: 'Vocal Presence',
    pluginId: 'vaneq',
    pluginVersion: '1.0.0',
    category: 'vocal',
    author: 'factory',
    description: 'Enhance vocal clarity and presence',
    tags: ['vocal', 'presence', 'clarity'],
    params: {
      band1_type: 3, band1_freq: 100, band1_gain: 0, band1_q: 0.7, band1_on: 1,
      band2_type: 0, band2_freq: 300, band2_gain: -2, band2_q: 1.5, band2_on: 1,
      band3_type: 0, band3_freq: 2500, band3_gain: 3, band3_q: 1.2, band3_on: 1,
      band4_type: 0, band4_freq: 5000, band4_gain: 2, band4_q: 1.0, band4_on: 1,
      band5_type: 0, band5_freq: 8000, band5_gain: 1, band5_q: 1.0, band5_on: 0,
      band6_type: 2, band6_freq: 12000, band6_gain: 2, band6_q: 0.7, band6_on: 1,
      outputGain: 0,
    },
  },
  {
    name: 'Punchy Drums',
    pluginId: 'vaneq',
    pluginVersion: '1.0.0',
    category: 'drums',
    author: 'factory',
    description: 'Add punch and clarity to drums',
    tags: ['drums', 'punch', 'attack'],
    params: {
      band1_type: 1, band1_freq: 60, band1_gain: 3, band1_q: 0.8, band1_on: 1,
      band2_type: 0, band2_freq: 200, band2_gain: -2, band2_q: 2.0, band2_on: 1,
      band3_type: 0, band3_freq: 800, band3_gain: 1, band3_q: 1.5, band3_on: 1,
      band4_type: 0, band4_freq: 3500, band4_gain: 3, band4_q: 1.2, band4_on: 1,
      band5_type: 0, band5_freq: 8000, band5_gain: 2, band5_q: 1.0, band5_on: 1,
      band6_type: 2, band6_freq: 12000, band6_gain: 1, band6_q: 0.7, band6_on: 1,
      outputGain: 0,
    },
  },
  {
    name: 'Warm Bass',
    pluginId: 'vaneq',
    pluginVersion: '1.0.0',
    category: 'bass',
    author: 'factory',
    description: 'Warm, round bass tone',
    tags: ['bass', 'warm', 'round'],
    params: {
      band1_type: 1, band1_freq: 80, band1_gain: 4, band1_q: 0.6, band1_on: 1,
      band2_type: 0, band2_freq: 200, band2_gain: 2, band2_q: 1.0, band2_on: 1,
      band3_type: 0, band3_freq: 500, band3_gain: -1, band3_q: 1.5, band3_on: 1,
      band4_type: 0, band4_freq: 1000, band4_gain: 1, band4_q: 1.0, band4_on: 1,
      band5_type: 0, band5_freq: 3000, band5_gain: 0, band5_q: 1.0, band5_on: 0,
      band6_type: 4, band6_freq: 5000, band6_gain: 0, band6_q: 0.7, band6_on: 1,
      outputGain: -1,
    },
  },
  {
    name: 'Bright Master',
    pluginId: 'vaneq',
    pluginVersion: '1.0.0',
    category: 'master',
    author: 'factory',
    description: 'Subtle brightness for mastering',
    tags: ['master', 'bright', 'air'],
    params: {
      band1_type: 1, band1_freq: 30, band1_gain: 1, band1_q: 0.7, band1_on: 1,
      band2_type: 0, band2_freq: 120, band2_gain: 0, band2_q: 1.0, band2_on: 0,
      band3_type: 0, band3_freq: 500, band3_gain: 0, band3_q: 1.0, band3_on: 0,
      band4_type: 0, band4_freq: 3000, band4_gain: 0.5, band4_q: 1.0, band4_on: 1,
      band5_type: 0, band5_freq: 8000, band5_gain: 1, band5_q: 0.8, band5_on: 1,
      band6_type: 2, band6_freq: 14000, band6_gain: 2, band6_q: 0.5, band6_on: 1,
      outputGain: 0,
    },
  },
];

/**
 * Factory presets for VanComp Pro.
 */
const VANCOMP_FACTORY_PRESETS: Omit<PluginPreset, 'id' | 'createdAt' | 'modifiedAt'>[] = [
  {
    name: 'Init',
    pluginId: 'vancomp',
    pluginVersion: '1.0.0',
    category: 'init',
    author: 'factory',
    description: 'Default starting point',
    params: {
      threshold: -20, ratio: 4, attack: 10, release: 100,
      knee: 6, makeupGain: 0, mix: 100, scHpfFreq: 60, scHpfOn: 0,
    },
  },
  {
    name: 'Vocal Leveler',
    pluginId: 'vancomp',
    pluginVersion: '1.0.0',
    category: 'vocal',
    author: 'factory',
    description: 'Smooth vocal dynamics',
    tags: ['vocal', 'leveling', 'smooth'],
    params: {
      threshold: -18, ratio: 3, attack: 15, release: 150,
      knee: 10, makeupGain: 3, mix: 100, scHpfFreq: 100, scHpfOn: 1,
    },
  },
  {
    name: 'Drum Bus Glue',
    pluginId: 'vancomp',
    pluginVersion: '1.0.0',
    category: 'drums',
    author: 'factory',
    description: 'Glue drums together with parallel compression',
    tags: ['drums', 'glue', 'parallel'],
    params: {
      threshold: -25, ratio: 4, attack: 30, release: 200,
      knee: 6, makeupGain: 6, mix: 50, scHpfFreq: 80, scHpfOn: 1,
    },
  },
  {
    name: 'Aggressive Pump',
    pluginId: 'vancomp',
    pluginVersion: '1.0.0',
    category: 'aggressive',
    author: 'factory',
    description: 'Obvious pumping compression',
    tags: ['aggressive', 'pump', 'effect'],
    params: {
      threshold: -30, ratio: 8, attack: 5, release: 50,
      knee: 0, makeupGain: 10, mix: 100, scHpfFreq: 60, scHpfOn: 0,
    },
  },
  {
    name: 'Master Bus',
    pluginId: 'vancomp',
    pluginVersion: '1.0.0',
    category: 'master',
    author: 'factory',
    description: 'Subtle master bus compression',
    tags: ['master', 'subtle', 'glue'],
    params: {
      threshold: -12, ratio: 2, attack: 30, release: 300,
      knee: 12, makeupGain: 1, mix: 100, scHpfFreq: 60, scHpfOn: 1,
    },
  },
];

/**
 * Factory presets for VanLimit Pro.
 */
const VANLIMIT_FACTORY_PRESETS: Omit<PluginPreset, 'id' | 'createdAt' | 'modifiedAt'>[] = [
  {
    name: 'Init',
    pluginId: 'vanlimit',
    pluginVersion: '1.0.0',
    category: 'init',
    author: 'factory',
    description: 'Default limiter settings',
    params: {
      ceiling: -0.3, threshold: -6, release: 100, truePeak: 1,
    },
  },
  {
    name: 'Transparent Master',
    pluginId: 'vanlimit',
    pluginVersion: '1.0.0',
    category: 'master',
    author: 'factory',
    description: 'Clean limiting for mastering',
    tags: ['master', 'transparent', 'clean'],
    params: {
      ceiling: -0.1, threshold: -3, release: 150, truePeak: 1,
    },
  },
  {
    name: 'Loud Master',
    pluginId: 'vanlimit',
    pluginVersion: '1.0.0',
    category: 'master',
    author: 'factory',
    description: 'Push loudness for competitive levels',
    tags: ['master', 'loud', 'hot'],
    params: {
      ceiling: -0.1, threshold: -8, release: 80, truePeak: 1,
    },
  },
  {
    name: 'Streaming Ready',
    pluginId: 'vanlimit',
    pluginVersion: '1.0.0',
    category: 'master',
    author: 'factory',
    description: 'Optimized for streaming platforms (-14 LUFS)',
    tags: ['streaming', 'spotify', 'youtube'],
    params: {
      ceiling: -1.0, threshold: -4, release: 120, truePeak: 1,
    },
  },
  {
    name: 'Broadcast',
    pluginId: 'vanlimit',
    pluginVersion: '1.0.0',
    category: 'master',
    author: 'factory',
    description: 'Broadcast-safe limiting',
    tags: ['broadcast', 'tv', 'radio'],
    params: {
      ceiling: -2.0, threshold: -6, release: 150, truePeak: 1,
    },
  },
];

// ============ Preset Storage Implementation ============

const STORAGE_KEY = 'reelforge_presets';

/**
 * Local storage based preset storage.
 */
class LocalPresetStorage implements PresetStorage {
  private presets: Map<string, PluginPreset> = new Map();
  private initialized = false;

  private initialize(): void {
    if (this.initialized) return;

    // Load from localStorage
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored) {
        const parsed = JSON.parse(stored) as PluginPreset[];
        parsed.forEach((p) => this.presets.set(p.id, p));
      }
    } catch (e) {
      console.warn('[PresetSystem] Failed to load presets from storage:', e);
    }

    // Add factory presets
    this.addFactoryPresets();

    this.initialized = true;
  }

  private addFactoryPresets(): void {
    const now = Date.now();
    const allFactory = [
      ...VANEQ_FACTORY_PRESETS,
      ...VANCOMP_FACTORY_PRESETS,
      ...VANLIMIT_FACTORY_PRESETS,
    ];

    allFactory.forEach((preset, index) => {
      const id = `factory_${preset.pluginId}_${index}`;
      if (!this.presets.has(id)) {
        this.presets.set(id, {
          ...preset,
          id,
          createdAt: now,
          modifiedAt: now,
        });
      }
    });
  }

  private persist(): void {
    try {
      // Only persist user presets
      const userPresets = Array.from(this.presets.values()).filter(
        (p) => p.author !== 'factory'
      );
      localStorage.setItem(STORAGE_KEY, JSON.stringify(userPresets));
    } catch (e) {
      console.warn('[PresetSystem] Failed to persist presets:', e);
    }
  }

  getPresets(pluginId: string): PluginPreset[] {
    this.initialize();
    return Array.from(this.presets.values())
      .filter((p) => p.pluginId === pluginId)
      .sort((a, b) => {
        // Factory first, then by name
        if (a.author === 'factory' && b.author !== 'factory') return -1;
        if (a.author !== 'factory' && b.author === 'factory') return 1;
        return a.name.localeCompare(b.name);
      });
  }

  savePreset(preset: PluginPreset): void {
    this.initialize();
    this.presets.set(preset.id, preset);
    this.persist();
  }

  deletePreset(presetId: string): void {
    this.initialize();
    const preset = this.presets.get(presetId);
    if (preset?.author === 'factory') {
      console.warn('[PresetSystem] Cannot delete factory presets');
      return;
    }
    this.presets.delete(presetId);
    this.persist();
  }

  updatePreset(presetId: string, updates: Partial<PluginPreset>): void {
    this.initialize();
    const preset = this.presets.get(presetId);
    if (!preset) return;
    if (preset.author === 'factory') {
      console.warn('[PresetSystem] Cannot modify factory presets');
      return;
    }
    this.presets.set(presetId, {
      ...preset,
      ...updates,
      modifiedAt: Date.now(),
    });
    this.persist();
  }

  hasPreset(presetId: string): boolean {
    this.initialize();
    return this.presets.has(presetId);
  }
}

// ============ Singleton Instance ============

const presetStorage = new LocalPresetStorage();

// ============ Public API ============

/**
 * Get all presets for a plugin.
 */
export function getPresetsForPlugin(pluginId: string): PluginPreset[] {
  return presetStorage.getPresets(pluginId);
}

/**
 * Get factory presets only.
 */
export function getFactoryPresets(pluginId: string): PluginPreset[] {
  return presetStorage.getPresets(pluginId).filter((p) => p.author === 'factory');
}

/**
 * Get user presets only.
 */
export function getUserPresets(pluginId: string): PluginPreset[] {
  return presetStorage.getPresets(pluginId).filter((p) => p.author === 'user');
}

/**
 * Save current parameters as a new preset.
 */
export function saveAsPreset(
  pluginId: string,
  pluginVersion: string,
  name: string,
  params: Record<string, number>,
  options: {
    category?: PresetCategory;
    description?: string;
    tags?: string[];
  } = {}
): PluginPreset {
  const now = Date.now();
  const preset: PluginPreset = {
    id: `user_${pluginId}_${now}`,
    name,
    pluginId,
    pluginVersion,
    category: options.category || 'user',
    author: 'user',
    params: { ...params },
    description: options.description,
    tags: options.tags,
    createdAt: now,
    modifiedAt: now,
  };

  presetStorage.savePreset(preset);
  return preset;
}

/**
 * Update an existing user preset.
 */
export function updatePreset(
  presetId: string,
  updates: Partial<Pick<PluginPreset, 'name' | 'category' | 'description' | 'tags' | 'params' | 'isFavorite'>>
): void {
  presetStorage.updatePreset(presetId, updates);
}

/**
 * Delete a user preset.
 */
export function deletePreset(presetId: string): void {
  presetStorage.deletePreset(presetId);
}

/**
 * Toggle preset favorite status.
 */
export function toggleFavorite(presetId: string): void {
  const presets = presetStorage.getPresets('');
  const preset = presets.find((p) => p.id === presetId);
  if (preset) {
    presetStorage.updatePreset(presetId, { isFavorite: !preset.isFavorite });
  }
}

/**
 * Export preset to JSON string.
 */
export function exportPreset(preset: PluginPreset): string {
  return JSON.stringify(preset, null, 2);
}

/**
 * Import preset from JSON string.
 */
export function importPreset(json: string): PluginPreset | null {
  try {
    const parsed = JSON.parse(json) as PluginPreset;

    // Validate required fields
    if (!parsed.name || !parsed.pluginId || !parsed.params) {
      console.error('[PresetSystem] Invalid preset format');
      return null;
    }

    // Create imported preset with new ID
    const now = Date.now();
    const imported: PluginPreset = {
      ...parsed,
      id: `imported_${parsed.pluginId}_${now}`,
      author: 'imported',
      createdAt: now,
      modifiedAt: now,
    };

    presetStorage.savePreset(imported);
    return imported;
  } catch (e) {
    console.error('[PresetSystem] Failed to import preset:', e);
    return null;
  }
}

/**
 * Get default parameter values for a plugin.
 */
export function getDefaultParams(
  descriptors: ParamDescriptor[]
): Record<string, number> {
  const params: Record<string, number> = {};
  for (const desc of descriptors) {
    params[desc.id] = desc.default;
  }
  return params;
}

// ============ A/B Comparison ============

const abStates = new Map<string, ABState>();

/**
 * Get or create A/B state for an insert.
 */
export function getABState(insertId: string): ABState {
  if (!abStates.has(insertId)) {
    abStates.set(insertId, {
      stateA: {},
      stateB: {},
      activeState: 'A',
      enabled: false,
    });
  }
  return abStates.get(insertId)!;
}

/**
 * Enable A/B mode and capture current state as A.
 */
export function enableABMode(
  insertId: string,
  currentParams: Record<string, number>
): ABState {
  const state = getABState(insertId);
  state.enabled = true;
  state.stateA = { ...currentParams };
  state.stateB = { ...currentParams };
  state.activeState = 'A';
  return state;
}

/**
 * Disable A/B mode.
 */
export function disableABMode(insertId: string): void {
  const state = getABState(insertId);
  state.enabled = false;
}

/**
 * Toggle between A and B states.
 */
export function toggleABState(insertId: string): 'A' | 'B' {
  const state = getABState(insertId);
  state.activeState = state.activeState === 'A' ? 'B' : 'A';
  return state.activeState;
}

/**
 * Copy current state to the inactive slot.
 */
export function copyToInactive(
  insertId: string,
  currentParams: Record<string, number>
): void {
  const state = getABState(insertId);
  if (state.activeState === 'A') {
    state.stateB = { ...currentParams };
  } else {
    state.stateA = { ...currentParams };
  }
}

/**
 * Update the active state's parameters.
 */
export function updateActiveState(
  insertId: string,
  params: Record<string, number>
): void {
  const state = getABState(insertId);
  if (state.activeState === 'A') {
    state.stateA = { ...params };
  } else {
    state.stateB = { ...params };
  }
}

/**
 * Get parameters for the currently active state.
 */
export function getActiveParams(insertId: string): Record<string, number> {
  const state = getABState(insertId);
  return state.activeState === 'A' ? state.stateA : state.stateB;
}

/**
 * Clear A/B state for an insert.
 */
export function clearABState(insertId: string): void {
  abStates.delete(insertId);
}

// ============ Preset Categories ============

export const PRESET_CATEGORIES: { value: PresetCategory; label: string }[] = [
  { value: 'default', label: 'Default' },
  { value: 'init', label: 'Init' },
  { value: 'vocal', label: 'Vocal' },
  { value: 'drums', label: 'Drums' },
  { value: 'bass', label: 'Bass' },
  { value: 'guitar', label: 'Guitar' },
  { value: 'keys', label: 'Keys' },
  { value: 'synth', label: 'Synth' },
  { value: 'master', label: 'Master' },
  { value: 'creative', label: 'Creative' },
  { value: 'subtle', label: 'Subtle' },
  { value: 'aggressive', label: 'Aggressive' },
  { value: 'user', label: 'User' },
];
