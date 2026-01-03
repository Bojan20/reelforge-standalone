/**
 * ReelForge Preset System Hook
 *
 * React hook for managing presets and A/B comparison in plugin editors.
 *
 * @module plugin/usePresets
 */

import { useState, useCallback, useMemo, useEffect } from 'react';
import type { ParamDescriptor } from './ParamDescriptor';
import {
  getPresetsForPlugin,
  saveAsPreset,
  deletePreset,
  updatePreset,
  toggleFavorite,
  exportPreset,
  importPreset,
  getDefaultParams,
  getABState,
  enableABMode,
  disableABMode,
  toggleABState,
  updateActiveState,
  getActiveParams,
  clearABState,
  type PluginPreset,
  type PresetCategory,
} from './presetSystem';

// ============ Types ============

export interface UsePresetsOptions {
  /** Plugin ID */
  pluginId: string;
  /** Plugin version */
  pluginVersion: string;
  /** Parameter descriptors */
  descriptors: ParamDescriptor[];
  /** Current parameter values */
  currentParams: Record<string, number>;
  /** Callback when parameters should change */
  onParamsChange: (params: Record<string, number>) => void;
  /** Insert ID for A/B state (optional) */
  insertId?: string;
}

export interface UsePresetsReturn {
  // Preset management
  presets: PluginPreset[];
  factoryPresets: PluginPreset[];
  userPresets: PluginPreset[];
  currentPresetId: string | null;
  loadPreset: (preset: PluginPreset) => void;
  saveCurrentAsPreset: (name: string, options?: {
    category?: PresetCategory;
    description?: string;
    tags?: string[];
  }) => PluginPreset;
  deleteUserPreset: (presetId: string) => void;
  renamePreset: (presetId: string, newName: string) => void;
  togglePresetFavorite: (presetId: string) => void;
  exportCurrentPreset: () => string | null;
  importPresetFromJson: (json: string) => PluginPreset | null;
  resetToDefault: () => void;
  refreshPresets: () => void;

  // A/B comparison
  abEnabled: boolean;
  abState: 'A' | 'B';
  enableAB: () => void;
  disableAB: () => void;
  toggleAB: () => void;
  copyToOther: () => void;

  // UI helpers
  isModified: boolean;
  presetCategories: PresetCategory[];
  getPresetsByCategory: (category: PresetCategory) => PluginPreset[];
  searchPresets: (query: string) => PluginPreset[];
}

// ============ Hook ============

export function usePresets({
  pluginId,
  pluginVersion,
  descriptors,
  currentParams,
  onParamsChange,
  insertId = 'default',
}: UsePresetsOptions): UsePresetsReturn {
  // State
  const [presets, setPresets] = useState<PluginPreset[]>([]);
  const [currentPresetId, setCurrentPresetId] = useState<string | null>(null);
  const [abEnabled, setAbEnabled] = useState(false);
  const [abState, setAbState] = useState<'A' | 'B'>('A');

  // Load presets on mount
  useEffect(() => {
    refreshPresets();
  }, [pluginId]);

  // Sync A/B state
  useEffect(() => {
    if (abEnabled) {
      updateActiveState(insertId, currentParams);
    }
  }, [currentParams, abEnabled, insertId]);

  // Cleanup A/B state on unmount
  useEffect(() => {
    return () => {
      clearABState(insertId);
    };
  }, [insertId]);

  // Refresh presets from storage
  const refreshPresets = useCallback(() => {
    const loaded = getPresetsForPlugin(pluginId);
    setPresets(loaded);
  }, [pluginId]);

  // Computed values
  const factoryPresets = useMemo(
    () => presets.filter((p) => p.author === 'factory'),
    [presets]
  );

  const userPresets = useMemo(
    () => presets.filter((p) => p.author === 'user' || p.author === 'imported'),
    [presets]
  );

  const defaultParams = useMemo(
    () => getDefaultParams(descriptors),
    [descriptors]
  );

  // Check if current state differs from loaded preset
  const isModified = useMemo(() => {
    if (!currentPresetId) return false;
    const preset = presets.find((p) => p.id === currentPresetId);
    if (!preset) return false;

    return Object.keys(preset.params).some(
      (key) => preset.params[key] !== currentParams[key]
    );
  }, [currentPresetId, presets, currentParams]);

  // Get unique categories from presets
  const presetCategories = useMemo(() => {
    const cats = new Set(presets.map((p) => p.category));
    return Array.from(cats);
  }, [presets]);

  // Load a preset
  const loadPreset = useCallback(
    (preset: PluginPreset) => {
      setCurrentPresetId(preset.id);
      onParamsChange(preset.params);
    },
    [onParamsChange]
  );

  // Save current as new preset
  const saveCurrentAsPreset = useCallback(
    (
      name: string,
      options?: {
        category?: PresetCategory;
        description?: string;
        tags?: string[];
      }
    ) => {
      const preset = saveAsPreset(
        pluginId,
        pluginVersion,
        name,
        currentParams,
        options
      );
      refreshPresets();
      setCurrentPresetId(preset.id);
      return preset;
    },
    [pluginId, pluginVersion, currentParams, refreshPresets]
  );

  // Delete user preset
  const deleteUserPreset = useCallback(
    (presetId: string) => {
      deletePreset(presetId);
      if (currentPresetId === presetId) {
        setCurrentPresetId(null);
      }
      refreshPresets();
    },
    [currentPresetId, refreshPresets]
  );

  // Rename preset
  const renamePreset = useCallback(
    (presetId: string, newName: string) => {
      updatePreset(presetId, { name: newName });
      refreshPresets();
    },
    [refreshPresets]
  );

  // Toggle favorite
  const togglePresetFavorite = useCallback(
    (presetId: string) => {
      toggleFavorite(presetId);
      refreshPresets();
    },
    [refreshPresets]
  );

  // Export current preset
  const exportCurrentPreset = useCallback(() => {
    if (!currentPresetId) {
      // Export as new preset
      const tempPreset: PluginPreset = {
        id: 'export',
        name: 'Exported Preset',
        pluginId,
        pluginVersion,
        category: 'user',
        author: 'user',
        params: currentParams,
        createdAt: Date.now(),
        modifiedAt: Date.now(),
      };
      return exportPreset(tempPreset);
    }
    const preset = presets.find((p) => p.id === currentPresetId);
    if (!preset) return null;
    return exportPreset(preset);
  }, [currentPresetId, presets, pluginId, pluginVersion, currentParams]);

  // Import preset from JSON
  const importPresetFromJson = useCallback(
    (json: string) => {
      const imported = importPreset(json);
      if (imported) {
        refreshPresets();
      }
      return imported;
    },
    [refreshPresets]
  );

  // Reset to default
  const resetToDefault = useCallback(() => {
    setCurrentPresetId(null);
    onParamsChange(defaultParams);
  }, [defaultParams, onParamsChange]);

  // Get presets by category
  const getPresetsByCategory = useCallback(
    (category: PresetCategory) => {
      return presets.filter((p) => p.category === category);
    },
    [presets]
  );

  // Search presets
  const searchPresets = useCallback(
    (query: string) => {
      const q = query.toLowerCase();
      return presets.filter(
        (p) =>
          p.name.toLowerCase().includes(q) ||
          p.description?.toLowerCase().includes(q) ||
          p.tags?.some((t) => t.toLowerCase().includes(q))
      );
    },
    [presets]
  );

  // ============ A/B Comparison ============

  const enableAB = useCallback(() => {
    enableABMode(insertId, currentParams);
    setAbEnabled(true);
    setAbState('A');
  }, [insertId, currentParams]);

  const disableAB = useCallback(() => {
    disableABMode(insertId);
    setAbEnabled(false);
    setAbState('A');
  }, [insertId]);

  const toggleAB = useCallback(() => {
    if (!abEnabled) return;

    const newState = toggleABState(insertId);
    setAbState(newState);

    // Load the new state's parameters
    const params = getActiveParams(insertId);
    onParamsChange(params);
  }, [abEnabled, insertId, onParamsChange]);

  const copyToOther = useCallback(() => {
    if (!abEnabled) return;

    const state = getABState(insertId);
    if (state.activeState === 'A') {
      state.stateB = { ...currentParams };
    } else {
      state.stateA = { ...currentParams };
    }
  }, [abEnabled, insertId, currentParams]);

  return {
    // Preset management
    presets,
    factoryPresets,
    userPresets,
    currentPresetId,
    loadPreset,
    saveCurrentAsPreset,
    deleteUserPreset,
    renamePreset,
    togglePresetFavorite,
    exportCurrentPreset,
    importPresetFromJson,
    resetToDefault,
    refreshPresets,

    // A/B comparison
    abEnabled,
    abState,
    enableAB,
    disableAB,
    toggleAB,
    copyToOther,

    // UI helpers
    isModified,
    presetCategories,
    getPresetsByCategory,
    searchPresets,
  };
}

export default usePresets;
