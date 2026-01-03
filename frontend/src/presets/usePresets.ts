/**
 * ReelForge Presets Hook
 *
 * State management for plugin presets:
 * - CRUD operations
 * - Storage (localStorage / IndexedDB)
 * - Import/export
 *
 * @module presets/usePresets
 */

import { useState, useCallback, useMemo, useEffect } from 'react';
import type { Preset, PresetCategory, PresetParameter } from './PresetManager';

// ============ Types ============

export interface UsePresetsOptions {
  /** Plugin ID */
  pluginId: string;
  /** Storage key prefix */
  storagePrefix?: string;
  /** Initial presets (factory) */
  factoryPresets?: Omit<Preset, 'id' | 'createdAt' | 'modifiedAt'>[];
  /** On preset change */
  onPresetChange?: (preset: Preset) => void;
}

export interface UsePresetsReturn {
  /** All presets */
  presets: Preset[];
  /** Categories */
  categories: PresetCategory[];
  /** Currently loaded preset */
  currentPreset: Preset | null;
  /** Load a preset */
  loadPreset: (preset: Preset) => void;
  /** Save current state as preset */
  savePreset: (name: string, category: string, parameters: PresetParameter[]) => Preset;
  /** Update existing preset */
  updatePreset: (presetId: string, updates: Partial<Preset>) => void;
  /** Delete preset */
  deletePreset: (presetId: string) => void;
  /** Rename preset */
  renamePreset: (presetId: string, newName: string) => void;
  /** Toggle favorite */
  toggleFavorite: (presetId: string) => void;
  /** Export presets to JSON */
  exportPresets: (presetIds: string[]) => string;
  /** Import presets from JSON */
  importPresets: (json: string) => number;
  /** Get preset by ID */
  getPreset: (presetId: string) => Preset | undefined;
  /** Compare two presets */
  comparePresets: (presetIdA: string, presetIdB: string) => PresetDiff[];
}

export interface PresetDiff {
  parameterId: string;
  valueA: number;
  valueB: number;
}

// ============ Helpers ============

function generateId(): string {
  return `preset-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

function getStorageKey(prefix: string, pluginId: string): string {
  return `${prefix}-${pluginId}`;
}

// ============ Default Categories ============

const DEFAULT_CATEGORIES: PresetCategory[] = [
  { id: 'factory', name: 'Factory', color: '#4a9eff', count: 0 },
  { id: 'user', name: 'User', color: '#51cf66', count: 0 },
  { id: 'favorites', name: 'Favorites', color: '#ffd43b', count: 0 },
];

// ============ Hook ============

export function usePresets(options: UsePresetsOptions): UsePresetsReturn {
  const {
    pluginId,
    storagePrefix = 'rf-presets',
    factoryPresets = [],
    onPresetChange,
  } = options;

  const storageKey = getStorageKey(storagePrefix, pluginId);

  // Initialize presets from storage + factory
  const [presets, setPresets] = useState<Preset[]>(() => {
    const stored = localStorage.getItem(storageKey);
    const userPresets: Preset[] = stored ? JSON.parse(stored) : [];

    // Add factory presets
    const factory: Preset[] = factoryPresets.map((p, i) => ({
      ...p,
      id: `factory-${i}`,
      isFactory: true,
      isFavorite: false,
      createdAt: 0,
      modifiedAt: 0,
    }));

    return [...factory, ...userPresets];
  });

  const [currentPreset, setCurrentPreset] = useState<Preset | null>(null);

  // Save to storage when presets change
  useEffect(() => {
    const userPresets = presets.filter((p) => !p.isFactory);
    localStorage.setItem(storageKey, JSON.stringify(userPresets));
  }, [presets, storageKey]);

  // Calculate categories with counts
  const categories = useMemo((): PresetCategory[] => {
    const counts: Record<string, number> = {};
    let favCount = 0;

    for (const preset of presets) {
      const cat = preset.category || 'user';
      counts[cat] = (counts[cat] || 0) + 1;
      if (preset.isFavorite) favCount++;
    }

    const cats: PresetCategory[] = [];

    // Add known categories
    for (const cat of DEFAULT_CATEGORIES) {
      if (cat.id === 'favorites') {
        cats.push({ ...cat, count: favCount });
      } else {
        cats.push({ ...cat, count: counts[cat.id] || 0 });
      }
    }

    // Add custom categories
    for (const [catId, count] of Object.entries(counts)) {
      if (!DEFAULT_CATEGORIES.find((c) => c.id === catId)) {
        cats.push({
          id: catId,
          name: catId.charAt(0).toUpperCase() + catId.slice(1),
          color: '#888',
          count,
        });
      }
    }

    return cats;
  }, [presets]);

  // Load preset
  const loadPreset = useCallback(
    (preset: Preset) => {
      setCurrentPreset(preset);
      onPresetChange?.(preset);
    },
    [onPresetChange]
  );

  // Save new preset
  const savePreset = useCallback(
    (name: string, category: string, parameters: PresetParameter[]): Preset => {
      const now = Date.now();
      const newPreset: Preset = {
        id: generateId(),
        name,
        pluginId,
        category,
        author: 'User',
        tags: [],
        parameters,
        isFavorite: false,
        isFactory: false,
        createdAt: now,
        modifiedAt: now,
      };

      setPresets((prev) => [...prev, newPreset]);
      setCurrentPreset(newPreset);
      return newPreset;
    },
    [pluginId]
  );

  // Update preset
  const updatePreset = useCallback((presetId: string, updates: Partial<Preset>) => {
    setPresets((prev) =>
      prev.map((p) => {
        if (p.id !== presetId || p.isFactory) return p;
        return { ...p, ...updates, modifiedAt: Date.now() };
      })
    );
  }, []);

  // Delete preset
  const deletePreset = useCallback((presetId: string) => {
    setPresets((prev) => prev.filter((p) => p.id !== presetId || p.isFactory));
    setCurrentPreset((curr) => (curr?.id === presetId ? null : curr));
  }, []);

  // Rename preset
  const renamePreset = useCallback((presetId: string, newName: string) => {
    updatePreset(presetId, { name: newName });
  }, [updatePreset]);

  // Toggle favorite
  const toggleFavorite = useCallback((presetId: string) => {
    setPresets((prev) =>
      prev.map((p) => {
        if (p.id !== presetId) return p;
        return { ...p, isFavorite: !p.isFavorite };
      })
    );
  }, []);

  // Export presets
  const exportPresets = useCallback(
    (presetIds: string[]): string => {
      const toExport = presets.filter((p) => presetIds.includes(p.id));
      return JSON.stringify(toExport, null, 2);
    },
    [presets]
  );

  // Import presets
  const importPresets = useCallback(
    (json: string): number => {
      try {
        const imported: Preset[] = JSON.parse(json);
        const now = Date.now();

        const newPresets: Preset[] = imported.map((p) => ({
          ...p,
          id: generateId(),
          isFactory: false,
          createdAt: now,
          modifiedAt: now,
        }));

        setPresets((prev) => [...prev, ...newPresets]);
        return newPresets.length;
      } catch {
        return 0;
      }
    },
    []
  );

  // Get preset by ID
  const getPreset = useCallback(
    (presetId: string): Preset | undefined => {
      return presets.find((p) => p.id === presetId);
    },
    [presets]
  );

  // Compare two presets
  const comparePresets = useCallback(
    (presetIdA: string, presetIdB: string): PresetDiff[] => {
      const presetA = getPreset(presetIdA);
      const presetB = getPreset(presetIdB);

      if (!presetA || !presetB) return [];

      const diffs: PresetDiff[] = [];
      const paramsB = new Map(presetB.parameters.map((p) => [p.id, p.value]));

      for (const paramA of presetA.parameters) {
        const valueB = paramsB.get(paramA.id);
        if (valueB !== undefined && paramA.value !== valueB) {
          diffs.push({
            parameterId: paramA.id,
            valueA: paramA.value,
            valueB,
          });
        }
      }

      return diffs;
    },
    [getPreset]
  );

  return useMemo(
    () => ({
      presets,
      categories,
      currentPreset,
      loadPreset,
      savePreset,
      updatePreset,
      deletePreset,
      renamePreset,
      toggleFavorite,
      exportPresets,
      importPresets,
      getPreset,
      comparePresets,
    }),
    [
      presets,
      categories,
      currentPreset,
      loadPreset,
      savePreset,
      updatePreset,
      deletePreset,
      renamePreset,
      toggleFavorite,
      exportPresets,
      importPresets,
      getPreset,
      comparePresets,
    ]
  );
}

export default usePresets;
