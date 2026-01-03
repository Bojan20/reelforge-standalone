/**
 * Plugin Picker
 *
 * Floating panel to select audio plugins for mixer insert slots.
 * Shows available plugins organized by category with search.
 * Now integrates with the plugin registry for real DSP processing.
 *
 * @module components/PluginPicker
 */

import { memo, useState, useCallback, useRef, useEffect, useMemo } from 'react';
import './PluginPicker.css';
import { getAllPluginDefinitions } from '../plugin/pluginRegistry';
import type { PluginDefinition as RegistryPluginDef } from '../plugin/PluginDefinition';

// ============ TYPES ============

// Picker category type - maps registry categories to UI categories
export type PickerCategory = 'eq' | 'dynamics' | 'modulation' | 'utility' | 'filter';

// Picker uses a simplified definition for UI purposes
export interface PluginDefinition {
  id: string;
  name: string;
  category: PickerCategory;
  icon: string;
  description?: string;
  /** Reference to the full registry definition for DSP creation */
  registryDef?: RegistryPluginDef;
}

export interface PluginPickerProps {
  /** Current insert (if editing existing) */
  currentInsert?: { id: string; name: string } | null;
  /** Target bus/channel ID */
  busId: string;
  /** Target slot index */
  slotIndex: number;
  /** Position for the popup */
  position: { x: number; y: number };
  /** Available plugins */
  plugins?: PluginDefinition[];
  /** When plugin is selected */
  onSelect: (plugin: PluginDefinition) => void;
  /** When insert is removed */
  onRemove?: () => void;
  /** When insert bypass is toggled */
  onBypassToggle?: () => void;
  /** Whether current insert is bypassed */
  isBypassed?: boolean;
  /** When picker is closed */
  onClose: () => void;
}

// ============ GET PLUGINS FROM REGISTRY ============

/**
 * Build plugin list from registry.
 * Maps PluginCategory to picker categories.
 */
function getRegistryPlugins(): PluginDefinition[] {
  const categoryMap: Record<string, PickerCategory> = {
    eq: 'eq',
    dynamics: 'dynamics',
    filter: 'filter',
    modulation: 'modulation',
    utility: 'utility',
  };

  return getAllPluginDefinitions().map((def) => ({
    id: def.id,
    name: def.displayName,
    category: categoryMap[def.category] ?? 'utility',
    icon: def.icon ?? '🔌',
    description: def.description,
    registryDef: def,
  }));
}

const CATEGORY_LABELS: Record<PickerCategory, string> = {
  eq: 'Equalizers',
  dynamics: 'Dynamics',
  filter: 'Filters',
  modulation: 'Modulation & FX',
  utility: 'Utility',
};

const CATEGORY_ORDER: PickerCategory[] = [
  'eq',
  'dynamics',
  'filter',
  'modulation',
  'utility',
];

// ============ PLUGIN PICKER ============

export const PluginPicker = memo(function PluginPicker({
  currentInsert,
  busId: _busId,
  slotIndex,
  position,
  plugins: externalPlugins,
  onSelect,
  onRemove,
  onBypassToggle,
  isBypassed = false,
  onClose,
}: PluginPickerProps) {
  void _busId; // Reserved for future use (e.g., filtering plugins per bus)
  const [search, setSearch] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<PickerCategory | 'all'>('all');
  const panelRef = useRef<HTMLDivElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);

  // Get plugins from registry (memoized)
  const registryPlugins = useMemo(() => getRegistryPlugins(), []);

  // Use external plugins if provided, otherwise use registry plugins
  const plugins = externalPlugins ?? registryPlugins;

  // Focus search on open
  useEffect(() => {
    searchRef.current?.focus();
  }, []);

  // Close on escape or click outside
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };

    const handleClickOutside = (e: MouseEvent) => {
      if (panelRef.current && !panelRef.current.contains(e.target as Node)) {
        onClose();
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    document.addEventListener('mousedown', handleClickOutside);

    return () => {
      document.removeEventListener('keydown', handleKeyDown);
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [onClose]);

  // Filter plugins
  const filteredPlugins = plugins.filter((plugin) => {
    const matchesSearch =
      search === '' ||
      plugin.name.toLowerCase().includes(search.toLowerCase()) ||
      plugin.category.toLowerCase().includes(search.toLowerCase());
    const matchesCategory = selectedCategory === 'all' || plugin.category === selectedCategory;
    return matchesSearch && matchesCategory;
  });

  // Group by category
  const groupedPlugins = CATEGORY_ORDER.reduce((acc, category) => {
    const categoryPlugins = filteredPlugins.filter((p) => p.category === category);
    if (categoryPlugins.length > 0) {
      acc[category] = categoryPlugins;
    }
    return acc;
  }, {} as Record<string, PluginDefinition[]>);

  // Handle plugin select
  const handleSelect = useCallback((plugin: PluginDefinition) => {
    onSelect(plugin);
    onClose();
  }, [onSelect, onClose]);

  // Position with boundary check
  const adjustedPosition = {
    x: Math.min(position.x, window.innerWidth - 320),
    y: Math.min(position.y, window.innerHeight - 400),
  };

  return (
    <div
      ref={panelRef}
      className="plugin-picker"
      style={{
        left: adjustedPosition.x,
        top: adjustedPosition.y,
      }}
    >
      {/* Header */}
      <div className="plugin-picker__header">
        <span className="plugin-picker__title">
          {currentInsert ? 'Edit Insert' : 'Add Insert'}
        </span>
        <span className="plugin-picker__slot">Slot {slotIndex + 1}</span>
        <button className="plugin-picker__close" onClick={onClose}>
          ×
        </button>
      </div>

      {/* Current Insert Actions */}
      {currentInsert && (
        <div className="plugin-picker__current">
          <span className="plugin-picker__current-name">{currentInsert.name}</span>
          <div className="plugin-picker__current-actions">
            <button
              className={`plugin-picker__action-btn ${isBypassed ? 'plugin-picker__action-btn--active' : ''}`}
              onClick={onBypassToggle}
              title="Bypass"
            >
              ⏸️ Bypass
            </button>
            <button
              className="plugin-picker__action-btn plugin-picker__action-btn--danger"
              onClick={onRemove}
              title="Remove"
            >
              🗑️ Remove
            </button>
          </div>
        </div>
      )}

      {/* Search */}
      <div className="plugin-picker__search">
        <input
          ref={searchRef}
          type="text"
          placeholder="Search plugins..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="plugin-picker__search-input"
        />
        {search && (
          <button
            className="plugin-picker__search-clear"
            onClick={() => setSearch('')}
          >
            ×
          </button>
        )}
      </div>

      {/* Category Filter */}
      <div className="plugin-picker__categories">
        <button
          className={`plugin-picker__category-btn ${selectedCategory === 'all' ? 'active' : ''}`}
          onClick={() => setSelectedCategory('all')}
        >
          All
        </button>
        {CATEGORY_ORDER.map((cat) => (
          <button
            key={cat}
            className={`plugin-picker__category-btn ${selectedCategory === cat ? 'active' : ''}`}
            onClick={() => setSelectedCategory(cat)}
          >
            {CATEGORY_LABELS[cat]}
          </button>
        ))}
      </div>

      {/* Plugin List */}
      <div className="plugin-picker__list">
        {Object.entries(groupedPlugins).length === 0 ? (
          <div className="plugin-picker__empty">No plugins found</div>
        ) : (
          Object.entries(groupedPlugins).map(([category, categoryPlugins]) => (
            <div key={category} className="plugin-picker__group">
              <div className="plugin-picker__group-header">
                {CATEGORY_LABELS[category as PluginDefinition['category']]}
              </div>
              {categoryPlugins.map((plugin) => (
                <div
                  key={plugin.id}
                  className="plugin-picker__item"
                  onClick={() => handleSelect(plugin)}
                >
                  <span className="plugin-picker__item-icon">{plugin.icon}</span>
                  <div className="plugin-picker__item-info">
                    <span className="plugin-picker__item-name">{plugin.name}</span>
                    {plugin.description && (
                      <span className="plugin-picker__item-desc">{plugin.description}</span>
                    )}
                  </div>
                </div>
              ))}
            </div>
          ))
        )}
      </div>
    </div>
  );
});

export default PluginPicker;
