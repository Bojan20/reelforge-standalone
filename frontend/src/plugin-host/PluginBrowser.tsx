/**
 * ReelForge Plugin Browser
 *
 * Plugin selection and management UI:
 * - Category filtering
 * - Search
 * - Favorites
 * - Recent plugins
 *
 * @module plugin-host/PluginBrowser
 */

import { useState, useCallback, useMemo } from 'react';
import './PluginBrowser.css';

// ============ Types ============

export type PluginCategory =
  | 'all'
  | 'eq'
  | 'dynamics'
  | 'reverb'
  | 'delay'
  | 'modulation'
  | 'distortion'
  | 'filter'
  | 'utility'
  | 'instrument'
  | 'analyzer';

export interface PluginInfo {
  id: string;
  name: string;
  vendor: string;
  category: PluginCategory;
  version: string;
  isFavorite?: boolean;
  isRecent?: boolean;
  description?: string;
  tags?: string[];
}

export interface PluginBrowserProps {
  /** Available plugins */
  plugins: PluginInfo[];
  /** On plugin select */
  onSelect: (plugin: PluginInfo) => void;
  /** On favorite toggle */
  onFavoriteToggle?: (pluginId: string) => void;
  /** On close */
  onClose?: () => void;
  /** Initial category filter */
  initialCategory?: PluginCategory;
}

// ============ Category Labels ============

const CATEGORY_LABELS: Record<PluginCategory, string> = {
  all: 'All Plugins',
  eq: 'EQ',
  dynamics: 'Dynamics',
  reverb: 'Reverb',
  delay: 'Delay',
  modulation: 'Modulation',
  distortion: 'Distortion',
  filter: 'Filter',
  utility: 'Utility',
  instrument: 'Instruments',
  analyzer: 'Analyzers',
};

const CATEGORY_ORDER: PluginCategory[] = [
  'all',
  'eq',
  'dynamics',
  'reverb',
  'delay',
  'modulation',
  'distortion',
  'filter',
  'utility',
  'instrument',
  'analyzer',
];

// ============ Component ============

export function PluginBrowser({
  plugins,
  onSelect,
  onFavoriteToggle,
  onClose,
  initialCategory = 'all',
}: PluginBrowserProps) {
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState<PluginCategory>(initialCategory);
  const [showFavorites, setShowFavorites] = useState(false);
  const [showRecent, setShowRecent] = useState(false);

  // Filter plugins
  const filteredPlugins = useMemo(() => {
    let result = plugins;

    // Category filter
    if (category !== 'all') {
      result = result.filter((p) => p.category === category);
    }

    // Favorites filter
    if (showFavorites) {
      result = result.filter((p) => p.isFavorite);
    }

    // Recent filter
    if (showRecent) {
      result = result.filter((p) => p.isRecent);
    }

    // Search filter
    if (search) {
      const lowerSearch = search.toLowerCase();
      result = result.filter(
        (p) =>
          p.name.toLowerCase().includes(lowerSearch) ||
          p.vendor.toLowerCase().includes(lowerSearch) ||
          p.tags?.some((t) => t.toLowerCase().includes(lowerSearch))
      );
    }

    // Sort: favorites first, then alphabetically
    return result.sort((a, b) => {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      return a.name.localeCompare(b.name);
    });
  }, [plugins, category, showFavorites, showRecent, search]);

  // Group by vendor
  const groupedPlugins = useMemo(() => {
    const groups = new Map<string, PluginInfo[]>();

    for (const plugin of filteredPlugins) {
      if (!groups.has(plugin.vendor)) {
        groups.set(plugin.vendor, []);
      }
      groups.get(plugin.vendor)!.push(plugin);
    }

    return groups;
  }, [filteredPlugins]);

  const handleFavoriteClick = useCallback(
    (e: React.MouseEvent, pluginId: string) => {
      e.stopPropagation();
      onFavoriteToggle?.(pluginId);
    },
    [onFavoriteToggle]
  );

  return (
    <div className="plugin-browser">
      {/* Header */}
      <div className="plugin-browser__header">
        <h2>Plugins</h2>
        {onClose && (
          <button className="plugin-browser__close" onClick={onClose}>
            ×
          </button>
        )}
      </div>

      {/* Search */}
      <div className="plugin-browser__search">
        <input
          type="text"
          placeholder="Search plugins..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>

      {/* Filters */}
      <div className="plugin-browser__filters">
        <button
          className={`plugin-browser__filter ${showFavorites ? 'active' : ''}`}
          onClick={() => {
            setShowFavorites(!showFavorites);
            setShowRecent(false);
          }}
        >
          ★ Favorites
        </button>
        <button
          className={`plugin-browser__filter ${showRecent ? 'active' : ''}`}
          onClick={() => {
            setShowRecent(!showRecent);
            setShowFavorites(false);
          }}
        >
          ⏱ Recent
        </button>
      </div>

      {/* Main Content */}
      <div className="plugin-browser__main">
        {/* Categories */}
        <div className="plugin-browser__categories">
          {CATEGORY_ORDER.map((cat) => (
            <button
              key={cat}
              className={`plugin-browser__category ${
                category === cat ? 'active' : ''
              }`}
              onClick={() => setCategory(cat)}
            >
              {CATEGORY_LABELS[cat]}
              <span className="plugin-browser__category-count">
                {cat === 'all'
                  ? plugins.length
                  : plugins.filter((p) => p.category === cat).length}
              </span>
            </button>
          ))}
        </div>

        {/* Plugin List */}
        <div className="plugin-browser__list">
          {filteredPlugins.length === 0 ? (
            <div className="plugin-browser__empty">
              No plugins found
            </div>
          ) : (
            Array.from(groupedPlugins.entries()).map(([vendor, vendorPlugins]) => (
              <div key={vendor} className="plugin-browser__vendor-group">
                <div className="plugin-browser__vendor-name">{vendor}</div>
                {vendorPlugins.map((plugin) => (
                  <div
                    key={plugin.id}
                    className="plugin-browser__item"
                    onClick={() => onSelect(plugin)}
                  >
                    <div className="plugin-browser__item-info">
                      <span className="plugin-browser__item-name">
                        {plugin.name}
                      </span>
                      <span className="plugin-browser__item-version">
                        v{plugin.version}
                      </span>
                    </div>
                    <div className="plugin-browser__item-actions">
                      <button
                        className={`plugin-browser__favorite ${
                          plugin.isFavorite ? 'active' : ''
                        }`}
                        onClick={(e) => handleFavoriteClick(e, plugin.id)}
                      >
                        {plugin.isFavorite ? '★' : '☆'}
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}

export default PluginBrowser;
