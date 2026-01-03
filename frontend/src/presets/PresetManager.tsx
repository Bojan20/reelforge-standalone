/**
 * ReelForge Preset Manager
 *
 * Plugin preset management UI:
 * - Save/load presets
 * - Category organization
 * - Favorites
 * - A/B comparison
 * - Import/export
 *
 * @module presets/PresetManager
 */

import { useState, useCallback, useMemo } from 'react';
import './PresetManager.css';

// ============ Types ============

export interface PresetParameter {
  id: string;
  value: number;
}

export interface Preset {
  id: string;
  name: string;
  pluginId: string;
  category: string;
  author: string;
  description?: string;
  tags: string[];
  parameters: PresetParameter[];
  isFavorite: boolean;
  isFactory: boolean;
  createdAt: number;
  modifiedAt: number;
}

export interface PresetCategory {
  id: string;
  name: string;
  color: string;
  count: number;
}

export interface PresetManagerProps {
  /** Plugin ID */
  pluginId: string;
  /** Plugin name */
  pluginName: string;
  /** Available presets */
  presets: Preset[];
  /** Categories */
  categories: PresetCategory[];
  /** Currently loaded preset ID */
  currentPresetId?: string;
  /** On preset load */
  onLoad: (preset: Preset) => void;
  /** On preset save */
  onSave: (name: string, category: string) => void;
  /** On preset save as */
  onSaveAs: (preset: Preset, name: string, category: string) => void;
  /** On preset delete */
  onDelete: (presetId: string) => void;
  /** On preset rename */
  onRename: (presetId: string, newName: string) => void;
  /** On favorite toggle */
  onFavoriteToggle: (presetId: string) => void;
  /** On export */
  onExport?: (presetIds: string[]) => void;
  /** On import */
  onImport?: () => void;
  /** On close */
  onClose?: () => void;
}

// ============ Component ============

export function PresetManager({
  pluginId: _pluginId,
  pluginName,
  presets,
  categories,
  currentPresetId,
  onLoad,
  onSave,
  onSaveAs: _onSaveAs,
  onDelete,
  onRename,
  onFavoriteToggle,
  onExport,
  onImport,
  onClose,
}: PresetManagerProps) {
  const [search, setSearch] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [showFavorites, setShowFavorites] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [savePresetName, setSavePresetName] = useState('');
  const [saveCategory, setSaveCategory] = useState('');
  const [editingPresetId, setEditingPresetId] = useState<string | null>(null);
  const [editName, setEditName] = useState('');

  // Filter presets
  const filteredPresets = useMemo(() => {
    let result = presets;

    // Category filter
    if (selectedCategory) {
      result = result.filter((p) => p.category === selectedCategory);
    }

    // Favorites filter
    if (showFavorites) {
      result = result.filter((p) => p.isFavorite);
    }

    // Search filter
    if (search) {
      const lowerSearch = search.toLowerCase();
      result = result.filter(
        (p) =>
          p.name.toLowerCase().includes(lowerSearch) ||
          p.author.toLowerCase().includes(lowerSearch) ||
          p.tags.some((t) => t.toLowerCase().includes(lowerSearch))
      );
    }

    // Sort: favorites first, then by name
    return result.sort((a, b) => {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      return a.name.localeCompare(b.name);
    });
  }, [presets, selectedCategory, showFavorites, search]);

  // Group by category for display
  const groupedPresets = useMemo(() => {
    if (selectedCategory) {
      return { [selectedCategory]: filteredPresets };
    }

    const groups: Record<string, Preset[]> = {};
    for (const preset of filteredPresets) {
      if (!groups[preset.category]) {
        groups[preset.category] = [];
      }
      groups[preset.category].push(preset);
    }
    return groups;
  }, [filteredPresets, selectedCategory]);

  // Handle save
  const handleSave = useCallback(() => {
    if (savePresetName.trim()) {
      onSave(savePresetName.trim(), saveCategory || 'User');
      setIsSaving(false);
      setSavePresetName('');
      setSaveCategory('');
    }
  }, [savePresetName, saveCategory, onSave]);

  // Handle rename
  const handleRename = useCallback(
    (presetId: string) => {
      if (editName.trim()) {
        onRename(presetId, editName.trim());
        setEditingPresetId(null);
        setEditName('');
      }
    },
    [editName, onRename]
  );

  // Handle preset click
  const handlePresetClick = useCallback(
    (preset: Preset) => {
      if (editingPresetId === preset.id) return;
      onLoad(preset);
    },
    [editingPresetId, onLoad]
  );

  // Handle preset double-click (rename)
  const handlePresetDoubleClick = useCallback((preset: Preset) => {
    if (preset.isFactory) return;
    setEditingPresetId(preset.id);
    setEditName(preset.name);
  }, []);

  // Handle export selected
  const handleExportAll = useCallback(() => {
    if (onExport) {
      onExport(filteredPresets.map((p) => p.id));
    }
  }, [filteredPresets, onExport]);

  return (
    <div className="preset-manager">
      {/* Header */}
      <div className="preset-manager__header">
        <h2>{pluginName} Presets</h2>
        {onClose && (
          <button className="preset-manager__close" onClick={onClose}>
            ×
          </button>
        )}
      </div>

      {/* Toolbar */}
      <div className="preset-manager__toolbar">
        <input
          type="text"
          className="preset-manager__search"
          placeholder="Search presets..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <button
          className={`preset-manager__btn ${showFavorites ? 'active' : ''}`}
          onClick={() => setShowFavorites(!showFavorites)}
          title="Show favorites"
        >
          ★
        </button>
        {onImport && (
          <button
            className="preset-manager__btn"
            onClick={onImport}
            title="Import presets"
          >
            ↓
          </button>
        )}
        {onExport && (
          <button
            className="preset-manager__btn"
            onClick={handleExportAll}
            title="Export presets"
          >
            ↑
          </button>
        )}
      </div>

      {/* Main Content */}
      <div className="preset-manager__content">
        {/* Categories */}
        <div className="preset-manager__categories">
          <button
            className={`preset-manager__category ${!selectedCategory ? 'active' : ''}`}
            onClick={() => setSelectedCategory(null)}
          >
            All
            <span className="preset-manager__category-count">
              {presets.length}
            </span>
          </button>
          {categories.map((cat) => (
            <button
              key={cat.id}
              className={`preset-manager__category ${
                selectedCategory === cat.id ? 'active' : ''
              }`}
              onClick={() => setSelectedCategory(cat.id)}
            >
              <span
                className="preset-manager__category-color"
                style={{ backgroundColor: cat.color }}
              />
              {cat.name}
              <span className="preset-manager__category-count">{cat.count}</span>
            </button>
          ))}
        </div>

        {/* Preset List */}
        <div className="preset-manager__list">
          {Object.entries(groupedPresets).map(([category, categoryPresets]) => (
            <div key={category} className="preset-manager__group">
              {!selectedCategory && (
                <div className="preset-manager__group-header">{category}</div>
              )}
              {categoryPresets.map((preset) => (
                <div
                  key={preset.id}
                  className={`preset-manager__preset ${
                    currentPresetId === preset.id ? 'active' : ''
                  } ${preset.isFactory ? 'factory' : ''}`}
                  onClick={() => handlePresetClick(preset)}
                  onDoubleClick={() => handlePresetDoubleClick(preset)}
                >
                  {editingPresetId === preset.id ? (
                    <input
                      type="text"
                      className="preset-manager__edit-input"
                      value={editName}
                      onChange={(e) => setEditName(e.target.value)}
                      onBlur={() => handleRename(preset.id)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') handleRename(preset.id);
                        if (e.key === 'Escape') setEditingPresetId(null);
                      }}
                      autoFocus
                      onClick={(e) => e.stopPropagation()}
                    />
                  ) : (
                    <>
                      <span className="preset-manager__preset-name">
                        {preset.name}
                      </span>
                      {preset.author && (
                        <span className="preset-manager__preset-author">
                          {preset.author}
                        </span>
                      )}
                    </>
                  )}
                  <div className="preset-manager__preset-actions">
                    <button
                      className={`preset-manager__preset-btn ${
                        preset.isFavorite ? 'favorite' : ''
                      }`}
                      onClick={(e) => {
                        e.stopPropagation();
                        onFavoriteToggle(preset.id);
                      }}
                      title="Toggle favorite"
                    >
                      {preset.isFavorite ? '★' : '☆'}
                    </button>
                    {!preset.isFactory && (
                      <button
                        className="preset-manager__preset-btn"
                        onClick={(e) => {
                          e.stopPropagation();
                          if (confirm(`Delete "${preset.name}"?`)) {
                            onDelete(preset.id);
                          }
                        }}
                        title="Delete preset"
                      >
                        ×
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          ))}

          {filteredPresets.length === 0 && (
            <div className="preset-manager__empty">
              No presets found
            </div>
          )}
        </div>
      </div>

      {/* Footer / Save */}
      <div className="preset-manager__footer">
        {isSaving ? (
          <div className="preset-manager__save-form">
            <input
              type="text"
              placeholder="Preset name"
              value={savePresetName}
              onChange={(e) => setSavePresetName(e.target.value)}
              autoFocus
            />
            <select
              value={saveCategory}
              onChange={(e) => setSaveCategory(e.target.value)}
            >
              <option value="">Category...</option>
              {categories.map((cat) => (
                <option key={cat.id} value={cat.id}>
                  {cat.name}
                </option>
              ))}
              <option value="User">User</option>
            </select>
            <button
              className="preset-manager__btn primary"
              onClick={handleSave}
              disabled={!savePresetName.trim()}
            >
              Save
            </button>
            <button
              className="preset-manager__btn"
              onClick={() => setIsSaving(false)}
            >
              Cancel
            </button>
          </div>
        ) : (
          <button
            className="preset-manager__btn primary"
            onClick={() => setIsSaving(true)}
          >
            Save Preset
          </button>
        )}
      </div>
    </div>
  );
}

export default PresetManager;
