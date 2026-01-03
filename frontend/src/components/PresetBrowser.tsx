/**
 * ReelForge Preset Browser Component
 *
 * Professional preset browser with:
 * - Category filtering
 * - Search functionality
 * - Save/Rename/Delete
 * - A/B comparison controls
 * - Import/Export
 *
 * @module components/PresetBrowser
 */

import { useState, useCallback, useMemo } from 'react';
import type { PluginPreset, PresetCategory } from '../plugin/presetSystem';
import type { UsePresetsReturn } from '../plugin/usePresets';
import './PresetBrowser.css';

// ============ Types ============

export interface PresetBrowserProps {
  /** Presets hook return value */
  presets: UsePresetsReturn;
  /** Plugin display name */
  pluginName: string;
  /** Compact mode for smaller UIs */
  compact?: boolean;
  /** Show A/B controls */
  showABControls?: boolean;
  /** Custom class name */
  className?: string;
}

// ============ Constants ============

const CATEGORY_LABELS: Record<PresetCategory, string> = {
  default: 'Default',
  init: 'Init',
  vocal: 'Vocal',
  drums: 'Drums',
  bass: 'Bass',
  guitar: 'Guitar',
  keys: 'Keys',
  synth: 'Synth',
  master: 'Master',
  creative: 'Creative',
  subtle: 'Subtle',
  aggressive: 'Aggressive',
  user: 'User',
};

const CATEGORY_ICONS: Record<PresetCategory, string> = {
  default: '○',
  init: '◌',
  vocal: '🎤',
  drums: '🥁',
  bass: '🎸',
  guitar: '🎵',
  keys: '🎹',
  synth: '🔊',
  master: '🎛️',
  creative: '✨',
  subtle: '🌊',
  aggressive: '🔥',
  user: '👤',
};

// ============ Component ============

export function PresetBrowser({
  presets,
  pluginName,
  compact = false,
  showABControls = true,
  className = '',
}: PresetBrowserProps) {
  // Local state
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<PresetCategory | 'all' | 'favorites'>('all');
  const [showSaveDialog, setShowSaveDialog] = useState(false);
  const [newPresetName, setNewPresetName] = useState('');
  const [editingPresetId, setEditingPresetId] = useState<string | null>(null);
  const [editingName, setEditingName] = useState('');

  // Destructure presets
  const {
    presets: allPresets,
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
    presetCategories,
    searchPresets,
    isModified,
    abEnabled,
    abState,
    enableAB,
    disableAB,
    toggleAB,
    copyToOther,
  } = presets;

  // Filtered presets
  const filteredPresets = useMemo(() => {
    let result = allPresets;

    // Category filter
    if (selectedCategory !== 'all') {
      if (selectedCategory === 'favorites') {
        result = result.filter((p) => p.isFavorite);
      } else {
        result = result.filter((p) => p.category === selectedCategory);
      }
    }

    // Search filter
    if (searchQuery.trim()) {
      result = searchPresets(searchQuery);
      // Re-apply category filter to search results
      if (selectedCategory !== 'all') {
        if (selectedCategory === 'favorites') {
          result = result.filter((p) => p.isFavorite);
        } else {
          result = result.filter((p) => p.category === selectedCategory);
        }
      }
    }

    return result;
  }, [allPresets, selectedCategory, searchQuery, searchPresets]);

  // Current preset
  const currentPreset = useMemo(
    () => allPresets.find((p) => p.id === currentPresetId),
    [allPresets, currentPresetId]
  );

  // Handlers
  const handleSave = useCallback(() => {
    if (!newPresetName.trim()) return;
    saveCurrentAsPreset(newPresetName.trim(), { category: 'user' });
    setNewPresetName('');
    setShowSaveDialog(false);
  }, [newPresetName, saveCurrentAsPreset]);

  const handleRename = useCallback(
    (presetId: string) => {
      if (!editingName.trim()) return;
      renamePreset(presetId, editingName.trim());
      setEditingPresetId(null);
      setEditingName('');
    },
    [editingName, renamePreset]
  );

  const handleExport = useCallback(() => {
    const json = exportCurrentPreset();
    if (json) {
      const blob = new Blob([json], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${currentPreset?.name || 'preset'}.rfpreset`;
      a.click();
      URL.revokeObjectURL(url);
    }
  }, [exportCurrentPreset, currentPreset]);

  const handleImport = useCallback(() => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.rfpreset,.json';
    input.onchange = async (e) => {
      const file = (e.target as HTMLInputElement).files?.[0];
      if (!file) return;

      const text = await file.text();
      const imported = importPresetFromJson(text);
      if (imported) {
        loadPreset(imported);
      }
    };
    input.click();
  }, [importPresetFromJson, loadPreset]);

  // Render preset item
  const renderPresetItem = (preset: PluginPreset) => {
    const isSelected = preset.id === currentPresetId;
    const isEditing = editingPresetId === preset.id;
    const canEdit = preset.author === 'user' || preset.author === 'imported';

    return (
      <div
        key={preset.id}
        className={`preset-item ${isSelected ? 'preset-item--selected' : ''}`}
        onClick={() => !isEditing && loadPreset(preset)}
      >
        <div className="preset-item__icon">
          {CATEGORY_ICONS[preset.category] || '○'}
        </div>

        <div className="preset-item__content">
          {isEditing ? (
            <input
              type="text"
              value={editingName}
              onChange={(e) => setEditingName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') handleRename(preset.id);
                if (e.key === 'Escape') setEditingPresetId(null);
              }}
              onBlur={() => handleRename(preset.id)}
              autoFocus
              className="preset-item__edit-input"
              onClick={(e) => e.stopPropagation()}
            />
          ) : (
            <>
              <span className="preset-item__name">{preset.name}</span>
              {preset.description && !compact && (
                <span className="preset-item__description">
                  {preset.description}
                </span>
              )}
            </>
          )}
        </div>

        <div className="preset-item__actions">
          <button
            className={`preset-action ${preset.isFavorite ? 'preset-action--active' : ''}`}
            onClick={(e) => {
              e.stopPropagation();
              togglePresetFavorite(preset.id);
            }}
            title={preset.isFavorite ? 'Remove from favorites' : 'Add to favorites'}
          >
            {preset.isFavorite ? '★' : '☆'}
          </button>

          {canEdit && (
            <>
              <button
                className="preset-action"
                onClick={(e) => {
                  e.stopPropagation();
                  setEditingPresetId(preset.id);
                  setEditingName(preset.name);
                }}
                title="Rename"
              >
                ✎
              </button>
              <button
                className="preset-action preset-action--danger"
                onClick={(e) => {
                  e.stopPropagation();
                  if (confirm(`Delete "${preset.name}"?`)) {
                    deleteUserPreset(preset.id);
                  }
                }}
                title="Delete"
              >
                ✕
              </button>
            </>
          )}
        </div>
      </div>
    );
  };

  return (
    <div className={`preset-browser ${compact ? 'preset-browser--compact' : ''} ${className}`}>
      {/* Header */}
      <div className="preset-browser__header">
        <div className="preset-browser__title">
          <span className="preset-browser__plugin-name">{pluginName}</span>
          {currentPreset && (
            <span className="preset-browser__current">
              {currentPreset.name}
              {isModified && <span className="preset-browser__modified">*</span>}
            </span>
          )}
        </div>

        {/* A/B Controls */}
        {showABControls && (
          <div className="preset-browser__ab">
            {abEnabled ? (
              <>
                <button
                  className={`ab-button ${abState === 'A' ? 'ab-button--active' : ''}`}
                  onClick={toggleAB}
                >
                  A
                </button>
                <button
                  className={`ab-button ${abState === 'B' ? 'ab-button--active' : ''}`}
                  onClick={toggleAB}
                >
                  B
                </button>
                <button
                  className="ab-button ab-button--copy"
                  onClick={copyToOther}
                  title={`Copy to ${abState === 'A' ? 'B' : 'A'}`}
                >
                  →
                </button>
                <button
                  className="ab-button ab-button--off"
                  onClick={disableAB}
                  title="Disable A/B"
                >
                  ✕
                </button>
              </>
            ) : (
              <button
                className="ab-button ab-button--enable"
                onClick={enableAB}
                title="Enable A/B comparison"
              >
                A/B
              </button>
            )}
          </div>
        )}
      </div>

      {/* Search & Filter */}
      <div className="preset-browser__controls">
        <input
          type="text"
          placeholder="Search presets..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="preset-browser__search"
        />

        <select
          value={selectedCategory}
          onChange={(e) => setSelectedCategory(e.target.value as PresetCategory | 'all' | 'favorites')}
          className="preset-browser__category"
        >
          <option value="all">All</option>
          <option value="favorites">★ Favorites</option>
          <option value="user">User</option>
          {presetCategories
            .filter((c) => !['user', 'init'].includes(c))
            .map((cat) => (
              <option key={cat} value={cat}>
                {CATEGORY_LABELS[cat] || cat}
              </option>
            ))}
        </select>
      </div>

      {/* Preset List */}
      <div className="preset-browser__list">
        {filteredPresets.length === 0 ? (
          <div className="preset-browser__empty">No presets found</div>
        ) : (
          filteredPresets.map(renderPresetItem)
        )}
      </div>

      {/* Actions */}
      <div className="preset-browser__actions">
        <button
          className="preset-browser__btn"
          onClick={() => setShowSaveDialog(true)}
          title="Save current settings as preset"
        >
          Save
        </button>
        <button
          className="preset-browser__btn"
          onClick={resetToDefault}
          title="Reset to default"
        >
          Init
        </button>
        <button
          className="preset-browser__btn"
          onClick={handleImport}
          title="Import preset"
        >
          Import
        </button>
        <button
          className="preset-browser__btn"
          onClick={handleExport}
          disabled={!currentPresetId && !isModified}
          title="Export current preset"
        >
          Export
        </button>
      </div>

      {/* Save Dialog */}
      {showSaveDialog && (
        <div className="preset-dialog-overlay" onClick={() => setShowSaveDialog(false)}>
          <div className="preset-dialog" onClick={(e) => e.stopPropagation()}>
            <div className="preset-dialog__header">Save Preset</div>
            <input
              type="text"
              placeholder="Preset name..."
              value={newPresetName}
              onChange={(e) => setNewPresetName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') handleSave();
                if (e.key === 'Escape') setShowSaveDialog(false);
              }}
              className="preset-dialog__input"
              autoFocus
            />
            <div className="preset-dialog__actions">
              <button
                className="preset-dialog__btn preset-dialog__btn--cancel"
                onClick={() => setShowSaveDialog(false)}
              >
                Cancel
              </button>
              <button
                className="preset-dialog__btn preset-dialog__btn--save"
                onClick={handleSave}
                disabled={!newPresetName.trim()}
              >
                Save
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Stats footer */}
      {!compact && (
        <div className="preset-browser__stats">
          {factoryPresets.length} factory • {userPresets.length} user
        </div>
      )}
    </div>
  );
}

export default PresetBrowser;
