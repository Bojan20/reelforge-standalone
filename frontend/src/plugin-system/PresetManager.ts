/**
 * ReelForge Plugin Preset Manager
 *
 * Manages plugin presets: save, load, import/export.
 * Supports factory presets and user presets.
 *
 * @module plugin-system/PresetManager
 */

import type { PluginState, PluginInstance } from './PluginRegistry';

// ============ Types ============

export interface PluginPreset {
  id: string;
  name: string;
  pluginId: string;
  pluginVersion: string;
  category?: string;
  author?: string;
  description?: string;
  tags?: string[];
  createdAt: string;
  updatedAt: string;
  isFavorite: boolean;
  isFactory: boolean;
  state: PluginState;
}

export interface PresetBank {
  id: string;
  name: string;
  pluginId: string;
  presets: PluginPreset[];
  createdAt: string;
}

export interface PresetImportResult {
  success: boolean;
  preset?: PluginPreset;
  error?: string;
}

export interface PresetExportOptions {
  includeMetadata?: boolean;
  format?: 'json' | 'base64';
}

// ============ Storage Key ============

const STORAGE_KEY_PREFIX = 'reelforge_presets_';
const FAVORITES_KEY = 'reelforge_preset_favorites';

// ============ Preset Manager ============

class PresetManagerImpl {
  private presets = new Map<string, PluginPreset>();
  private banks = new Map<string, PresetBank>();
  private favorites = new Set<string>();
  private listeners = new Set<(event: PresetEvent) => void>();

  constructor() {
    this.loadFromStorage();
  }

  // ============ Preset CRUD ============

  /**
   * Create preset from plugin instance.
   */
  createPreset(
    instance: PluginInstance,
    name: string,
    options?: {
      category?: string;
      author?: string;
      description?: string;
      tags?: string[];
    }
  ): PluginPreset {
    const state = instance.getState();
    const now = new Date().toISOString();

    const preset: PluginPreset = {
      id: `preset_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      name,
      pluginId: state.descriptorId,
      pluginVersion: state.version,
      category: options?.category,
      author: options?.author,
      description: options?.description,
      tags: options?.tags,
      createdAt: now,
      updatedAt: now,
      isFavorite: false,
      isFactory: false,
      state,
    };

    this.presets.set(preset.id, preset);
    this.saveToStorage();
    this.emit({ type: 'created', preset });

    return preset;
  }

  /**
   * Get preset by ID.
   */
  getPreset(id: string): PluginPreset | undefined {
    return this.presets.get(id);
  }

  /**
   * Get all presets for a plugin.
   */
  getPresetsForPlugin(pluginId: string): PluginPreset[] {
    return Array.from(this.presets.values())
      .filter(p => p.pluginId === pluginId)
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  /**
   * Get all presets.
   */
  getAllPresets(): PluginPreset[] {
    return Array.from(this.presets.values());
  }

  /**
   * Update preset.
   */
  updatePreset(id: string, updates: Partial<Pick<PluginPreset, 'name' | 'category' | 'description' | 'tags'>>): boolean {
    const preset = this.presets.get(id);
    if (!preset || preset.isFactory) return false;

    Object.assign(preset, updates, { updatedAt: new Date().toISOString() });
    this.saveToStorage();
    this.emit({ type: 'updated', preset });

    return true;
  }

  /**
   * Update preset state from plugin instance.
   */
  updatePresetState(id: string, instance: PluginInstance): boolean {
    const preset = this.presets.get(id);
    if (!preset || preset.isFactory) return false;

    preset.state = instance.getState();
    preset.updatedAt = new Date().toISOString();
    this.saveToStorage();
    this.emit({ type: 'updated', preset });

    return true;
  }

  /**
   * Delete preset.
   */
  deletePreset(id: string): boolean {
    const preset = this.presets.get(id);
    if (!preset || preset.isFactory) return false;

    this.presets.delete(id);
    this.favorites.delete(id);
    this.saveToStorage();
    this.emit({ type: 'deleted', presetId: id });

    return true;
  }

  /**
   * Apply preset to plugin instance.
   */
  applyPreset(id: string, instance: PluginInstance): boolean {
    const preset = this.presets.get(id);
    if (!preset) return false;

    if (preset.pluginId !== instance.descriptorId) {
      console.warn('Preset is for different plugin');
      return false;
    }

    instance.setState(preset.state);
    this.emit({ type: 'applied', preset, instanceId: instance.id });

    return true;
  }

  // ============ Favorites ============

  /**
   * Toggle favorite status.
   */
  toggleFavorite(id: string): boolean {
    const preset = this.presets.get(id);
    if (!preset) return false;

    preset.isFavorite = !preset.isFavorite;

    if (preset.isFavorite) {
      this.favorites.add(id);
    } else {
      this.favorites.delete(id);
    }

    this.saveToStorage();
    this.emit({ type: 'updated', preset });

    return preset.isFavorite;
  }

  /**
   * Get favorite presets.
   */
  getFavorites(): PluginPreset[] {
    return Array.from(this.favorites)
      .map(id => this.presets.get(id))
      .filter((p): p is PluginPreset => p !== undefined);
  }

  // ============ Categories ============

  /**
   * Get all categories for a plugin.
   */
  getCategoriesForPlugin(pluginId: string): string[] {
    const categories = new Set<string>();

    for (const preset of this.presets.values()) {
      if (preset.pluginId === pluginId && preset.category) {
        categories.add(preset.category);
      }
    }

    return Array.from(categories).sort();
  }

  /**
   * Get presets by category.
   */
  getPresetsByCategory(pluginId: string, category: string): PluginPreset[] {
    return this.getPresetsForPlugin(pluginId)
      .filter(p => p.category === category);
  }

  // ============ Search ============

  /**
   * Search presets.
   */
  searchPresets(pluginId: string, query: string): PluginPreset[] {
    const lower = query.toLowerCase();

    return this.getPresetsForPlugin(pluginId).filter(p =>
      p.name.toLowerCase().includes(lower) ||
      p.category?.toLowerCase().includes(lower) ||
      p.description?.toLowerCase().includes(lower) ||
      p.tags?.some(t => t.toLowerCase().includes(lower))
    );
  }

  // ============ Banks ============

  /**
   * Create preset bank.
   */
  createBank(name: string, pluginId: string, presetIds: string[]): PresetBank {
    const presets = presetIds
      .map(id => this.presets.get(id))
      .filter((p): p is PluginPreset => p !== undefined && p.pluginId === pluginId);

    const bank: PresetBank = {
      id: `bank_${Date.now()}`,
      name,
      pluginId,
      presets,
      createdAt: new Date().toISOString(),
    };

    this.banks.set(bank.id, bank);
    this.emit({ type: 'bankCreated', bank });

    return bank;
  }

  /**
   * Get bank.
   */
  getBank(id: string): PresetBank | undefined {
    return this.banks.get(id);
  }

  /**
   * Get banks for plugin.
   */
  getBanksForPlugin(pluginId: string): PresetBank[] {
    return Array.from(this.banks.values())
      .filter(b => b.pluginId === pluginId);
  }

  // ============ Import/Export ============

  /**
   * Export preset to JSON.
   */
  exportPreset(id: string, options?: PresetExportOptions): string | undefined {
    const preset = this.presets.get(id);
    if (!preset) return undefined;

    const exportData = options?.includeMetadata
      ? preset
      : {
          name: preset.name,
          pluginId: preset.pluginId,
          pluginVersion: preset.pluginVersion,
          state: preset.state,
        };

    const json = JSON.stringify(exportData, null, 2);

    return options?.format === 'base64'
      ? btoa(json)
      : json;
  }

  /**
   * Import preset from JSON.
   */
  importPreset(data: string, isBase64?: boolean): PresetImportResult {
    try {
      const json = isBase64 ? atob(data) : data;
      const parsed = JSON.parse(json);

      if (!parsed.name || !parsed.pluginId || !parsed.state) {
        return { success: false, error: 'Invalid preset format' };
      }

      const now = new Date().toISOString();

      const preset: PluginPreset = {
        id: `preset_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        name: parsed.name,
        pluginId: parsed.pluginId,
        pluginVersion: parsed.pluginVersion || parsed.state.version,
        category: parsed.category,
        author: parsed.author,
        description: parsed.description,
        tags: parsed.tags,
        createdAt: now,
        updatedAt: now,
        isFavorite: false,
        isFactory: false,
        state: parsed.state,
      };

      this.presets.set(preset.id, preset);
      this.saveToStorage();
      this.emit({ type: 'imported', preset });

      return { success: true, preset };
    } catch (e) {
      return { success: false, error: String(e) };
    }
  }

  /**
   * Export bank to JSON.
   */
  exportBank(id: string): string | undefined {
    const bank = this.banks.get(id);
    if (!bank) return undefined;

    return JSON.stringify(bank, null, 2);
  }

  /**
   * Import bank from JSON.
   */
  importBank(data: string): PresetBank | undefined {
    try {
      const parsed = JSON.parse(data) as PresetBank;

      if (!parsed.name || !parsed.pluginId || !parsed.presets) {
        return undefined;
      }

      // Import all presets from bank
      for (const preset of parsed.presets) {
        preset.id = `preset_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        preset.isFactory = false;
        this.presets.set(preset.id, preset);
      }

      const bank: PresetBank = {
        id: `bank_${Date.now()}`,
        name: parsed.name,
        pluginId: parsed.pluginId,
        presets: parsed.presets,
        createdAt: new Date().toISOString(),
      };

      this.banks.set(bank.id, bank);
      this.saveToStorage();

      return bank;
    } catch {
      return undefined;
    }
  }

  // ============ Factory Presets ============

  /**
   * Register factory presets for a plugin.
   */
  registerFactoryPresets(pluginId: string, presets: Array<{
    name: string;
    category?: string;
    state: PluginState;
  }>): void {
    const now = new Date().toISOString();

    for (const preset of presets) {
      const factoryPreset: PluginPreset = {
        id: `factory_${pluginId}_${preset.name.replace(/\s+/g, '_')}`,
        name: preset.name,
        pluginId,
        pluginVersion: preset.state.version,
        category: preset.category,
        author: 'ReelForge',
        createdAt: now,
        updatedAt: now,
        isFavorite: false,
        isFactory: true,
        state: preset.state,
      };

      this.presets.set(factoryPreset.id, factoryPreset);
    }

    this.emit({ type: 'factoryRegistered', pluginId, count: presets.length });
  }

  // ============ Storage ============

  private saveToStorage(): void {
    try {
      // Save user presets only (not factory)
      const userPresets = Array.from(this.presets.values())
        .filter(p => !p.isFactory);

      localStorage.setItem(
        `${STORAGE_KEY_PREFIX}user`,
        JSON.stringify(userPresets)
      );

      localStorage.setItem(
        FAVORITES_KEY,
        JSON.stringify(Array.from(this.favorites))
      );
    } catch (e) {
      console.error('Failed to save presets:', e);
    }
  }

  private loadFromStorage(): void {
    try {
      const presetsJson = localStorage.getItem(`${STORAGE_KEY_PREFIX}user`);
      if (presetsJson) {
        const presets = JSON.parse(presetsJson) as PluginPreset[];
        for (const preset of presets) {
          this.presets.set(preset.id, preset);
        }
      }

      const favoritesJson = localStorage.getItem(FAVORITES_KEY);
      if (favoritesJson) {
        const favorites = JSON.parse(favoritesJson) as string[];
        for (const id of favorites) {
          this.favorites.add(id);
        }
      }
    } catch (e) {
      console.error('Failed to load presets:', e);
    }
  }

  // ============ Events ============

  subscribe(callback: (event: PresetEvent) => void): () => void {
    this.listeners.add(callback);
    return () => this.listeners.delete(callback);
  }

  private emit(event: PresetEvent): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }

  // ============ Utilities ============

  /**
   * Get statistics.
   */
  getStats(): {
    totalPresets: number;
    userPresets: number;
    factoryPresets: number;
    favorites: number;
    banks: number;
  } {
    const all = Array.from(this.presets.values());
    return {
      totalPresets: all.length,
      userPresets: all.filter(p => !p.isFactory).length,
      factoryPresets: all.filter(p => p.isFactory).length,
      favorites: this.favorites.size,
      banks: this.banks.size,
    };
  }

  /**
   * Clear all user presets.
   */
  clearUserPresets(): void {
    for (const [id, preset] of this.presets) {
      if (!preset.isFactory) {
        this.presets.delete(id);
      }
    }
    this.favorites.clear();
    this.banks.clear();
    this.saveToStorage();
    this.emit({ type: 'cleared' });
  }
}

// ============ Event Types ============

export type PresetEvent =
  | { type: 'created'; preset: PluginPreset }
  | { type: 'updated'; preset: PluginPreset }
  | { type: 'deleted'; presetId: string }
  | { type: 'applied'; preset: PluginPreset; instanceId: string }
  | { type: 'imported'; preset: PluginPreset }
  | { type: 'bankCreated'; bank: PresetBank }
  | { type: 'factoryRegistered'; pluginId: string; count: number }
  | { type: 'cleared' };

// ============ Singleton Instance ============

export const PresetManager = new PresetManagerImpl();
