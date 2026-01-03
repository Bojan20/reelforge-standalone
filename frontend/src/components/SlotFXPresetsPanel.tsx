/**
 * Slot FX Presets Panel
 *
 * Preset browser and manager for slot audio:
 * - Category filtering
 * - Tag-based search
 * - Preset preview
 * - Quick apply
 * - Custom preset creation
 */

import React, { useState, memo, useCallback, useMemo } from 'react';
import {
  slotFXPresets,
  type FXChainPreset,
  type PresetCategory,
  type PresetTag,
} from '../core/slotFXPresets';
import './SlotFXPresetsPanel.css';

// ============ TYPES ============

interface SlotFXPresetsPanelProps {
  onPresetSelect?: (preset: FXChainPreset) => void;
  onPresetApply?: (preset: FXChainPreset, targetBus: string) => void;
}

// ============ CONSTANTS ============

const CATEGORY_CONFIG: Record<PresetCategory, { label: string; icon: string; color: string }> = {
  wins: { label: 'Wins', icon: '🏆', color: '#eab308' },
  spins: { label: 'Spins', icon: '🎰', color: '#22c55e' },
  bonus: { label: 'Bonus', icon: '⭐', color: '#f59e0b' },
  jackpot: { label: 'Jackpot', icon: '💎', color: '#ef4444' },
  ui: { label: 'UI', icon: '🖱️', color: '#6b7280' },
  music: { label: 'Music', icon: '🎵', color: '#3b82f6' },
  ambience: { label: 'Ambience', icon: '🌙', color: '#06b6d4' },
  voice: { label: 'Voice', icon: '🎤', color: '#8b5cf6' },
  master: { label: 'Master', icon: '🎛️', color: '#f43f5e' },
};

const TAG_COLORS: Record<PresetTag, string> = {
  punch: '#ef4444',
  bright: '#eab308',
  warm: '#f97316',
  subtle: '#6b7280',
  aggressive: '#dc2626',
  clean: '#22c55e',
  vintage: '#a16207',
  modern: '#3b82f6',
  big: '#8b5cf6',
  tight: '#14b8a6',
  wide: '#6366f1',
  narrow: '#64748b',
  fast: '#f43f5e',
  slow: '#0ea5e9',
};

// ============ MAIN COMPONENT ============

const SlotFXPresetsPanel: React.FC<SlotFXPresetsPanelProps> = memo(({
  onPresetSelect,
  onPresetApply,
}) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<PresetCategory | 'all'>('all');
  const [selectedTags, setSelectedTags] = useState<PresetTag[]>([]);
  const [selectedPreset, setSelectedPreset] = useState<FXChainPreset | null>(null);
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');

  // Get category counts
  const categoryCounts = useMemo(() => slotFXPresets.getCategoryCounts(), []);

  // Filter presets
  const filteredPresets = useMemo(() => {
    let presets = slotFXPresets.getAllPresets();

    // Category filter
    if (selectedCategory !== 'all') {
      presets = presets.filter(p => p.category === selectedCategory);
    }

    // Tag filter
    if (selectedTags.length > 0) {
      presets = presets.filter(p =>
        selectedTags.every(tag => p.tags.includes(tag))
      );
    }

    // Search filter
    if (searchQuery) {
      presets = slotFXPresets.search(searchQuery);
    }

    return presets;
  }, [selectedCategory, selectedTags, searchQuery]);

  // Toggle tag
  const toggleTag = useCallback((tag: PresetTag) => {
    setSelectedTags(prev =>
      prev.includes(tag)
        ? prev.filter(t => t !== tag)
        : [...prev, tag]
    );
  }, []);

  // Select preset
  const handlePresetSelect = useCallback((preset: FXChainPreset) => {
    setSelectedPreset(preset);
    onPresetSelect?.(preset);
  }, [onPresetSelect]);

  // Apply preset
  const handleApply = useCallback((preset: FXChainPreset) => {
    onPresetApply?.(preset, 'sfx'); // Default to SFX bus
  }, [onPresetApply]);

  // Get all unique tags from filtered presets
  const availableTags = useMemo(() => {
    const tags = new Set<PresetTag>();
    filteredPresets.forEach(p => p.tags.forEach(t => tags.add(t)));
    return Array.from(tags).sort();
  }, [filteredPresets]);

  return (
    <div className="fx-presets-panel">
      {/* Header */}
      <div className="fx-header">
        <div className="fx-title">
          <span className="fx-icon">🎨</span>
          <h3>Slot FX Presets</h3>
          <span className="preset-count">{filteredPresets.length} presets</span>
        </div>

        <div className="header-actions">
          <input
            type="text"
            className="search-input"
            placeholder="Search presets..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />

          <div className="view-toggle">
            <button
              className={viewMode === 'grid' ? 'active' : ''}
              onClick={() => setViewMode('grid')}
            >
              ▦
            </button>
            <button
              className={viewMode === 'list' ? 'active' : ''}
              onClick={() => setViewMode('list')}
            >
              ☰
            </button>
          </div>
        </div>
      </div>

      {/* Category Tabs */}
      <div className="category-tabs">
        <button
          className={`category-tab ${selectedCategory === 'all' ? 'active' : ''}`}
          onClick={() => setSelectedCategory('all')}
        >
          <span className="cat-icon">📦</span>
          <span className="cat-label">All</span>
          <span className="cat-count">{slotFXPresets.getAllPresets().length}</span>
        </button>

        {(Object.keys(CATEGORY_CONFIG) as PresetCategory[]).map(cat => (
          <button
            key={cat}
            className={`category-tab ${selectedCategory === cat ? 'active' : ''}`}
            style={{ '--cat-color': CATEGORY_CONFIG[cat].color } as React.CSSProperties}
            onClick={() => setSelectedCategory(cat)}
          >
            <span className="cat-icon">{CATEGORY_CONFIG[cat].icon}</span>
            <span className="cat-label">{CATEGORY_CONFIG[cat].label}</span>
            <span className="cat-count">{categoryCounts[cat]}</span>
          </button>
        ))}
      </div>

      {/* Tag Filters */}
      <div className="tag-filters">
        <span className="tag-label">Tags:</span>
        {availableTags.map(tag => (
          <button
            key={tag}
            className={`tag-btn ${selectedTags.includes(tag) ? 'active' : ''}`}
            style={{ '--tag-color': TAG_COLORS[tag] } as React.CSSProperties}
            onClick={() => toggleTag(tag)}
          >
            {tag}
          </button>
        ))}
        {selectedTags.length > 0 && (
          <button className="clear-tags" onClick={() => setSelectedTags([])}>
            Clear
          </button>
        )}
      </div>

      {/* Presets Grid/List */}
      <div className={`presets-container ${viewMode}`}>
        {filteredPresets.length === 0 ? (
          <div className="empty-state">
            <span className="empty-icon">🔍</span>
            <p>No presets match your filters</p>
          </div>
        ) : (
          filteredPresets.map(preset => (
            <PresetCard
              key={preset.id}
              preset={preset}
              isSelected={selectedPreset?.id === preset.id}
              viewMode={viewMode}
              onSelect={() => handlePresetSelect(preset)}
              onApply={() => handleApply(preset)}
            />
          ))
        )}
      </div>

      {/* Preset Details */}
      {selectedPreset && (
        <PresetDetails
          preset={selectedPreset}
          onApply={() => handleApply(selectedPreset)}
          onClose={() => setSelectedPreset(null)}
        />
      )}
    </div>
  );
});

SlotFXPresetsPanel.displayName = 'SlotFXPresetsPanel';
export default SlotFXPresetsPanel;

// ============ PRESET CARD ============

interface PresetCardProps {
  preset: FXChainPreset;
  isSelected: boolean;
  viewMode: 'grid' | 'list';
  onSelect: () => void;
  onApply: () => void;
}

const PresetCard = memo<PresetCardProps>(({
  preset,
  isSelected,
  viewMode,
  onSelect,
  onApply,
}) => {
  const catConfig = CATEGORY_CONFIG[preset.category];

  return (
    <div
      className={`preset-card ${viewMode} ${isSelected ? 'selected' : ''}`}
      onClick={onSelect}
    >
      <div className="preset-header">
        <span
          className="preset-category-badge"
          style={{ backgroundColor: `${catConfig.color}20`, color: catConfig.color }}
        >
          {catConfig.icon} {catConfig.label}
        </span>
      </div>

      <div className="preset-name">{preset.name}</div>
      <div className="preset-description">{preset.description}</div>

      <div className="preset-tags">
        {preset.tags.slice(0, 3).map(tag => (
          <span
            key={tag}
            className="preset-tag"
            style={{ color: TAG_COLORS[tag] }}
          >
            {tag}
          </span>
        ))}
      </div>

      <div className="preset-features">
        {preset.eq && <span className="feature-badge">EQ</span>}
        {preset.compressor && <span className="feature-badge">Comp</span>}
        {preset.reverb && <span className="feature-badge">Reverb</span>}
        {preset.delay && <span className="feature-badge">Delay</span>}
        {preset.sidechain && <span className="feature-badge">SC</span>}
      </div>

      <div className="preset-actions">
        <button
          className="apply-btn"
          onClick={(e) => { e.stopPropagation(); onApply(); }}
        >
          Apply
        </button>
      </div>
    </div>
  );
});

PresetCard.displayName = 'PresetCard';

// ============ PRESET DETAILS ============

interface PresetDetailsProps {
  preset: FXChainPreset;
  onApply: () => void;
  onClose: () => void;
}

const PresetDetails = memo<PresetDetailsProps>(({
  preset,
  onApply,
  onClose,
}) => {
  return (
    <div className="preset-details">
      <div className="details-header">
        <h4>{preset.name}</h4>
        <button className="close-btn" onClick={onClose}>×</button>
      </div>

      <div className="details-content">
        <p className="details-description">{preset.description}</p>

        <div className="details-meta">
          <span>Category: {CATEGORY_CONFIG[preset.category].label}</span>
          <span>Author: {preset.author}</span>
          <span>Version: {preset.version}</span>
        </div>

        {/* EQ Preview */}
        {preset.eq && (
          <div className="effect-preview">
            <h5>EQ ({preset.eq.bands.length} bands)</h5>
            <div className="eq-bands">
              {preset.eq.bands.map((band, i) => (
                <div key={i} className="eq-band">
                  <span className="band-type">{band.type}</span>
                  <span className="band-freq">{band.frequency}Hz</span>
                  <span className="band-gain">{band.gain > 0 ? '+' : ''}{band.gain}dB</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Compressor Preview */}
        {preset.compressor && (
          <div className="effect-preview">
            <h5>Compressor</h5>
            <div className="comp-params">
              <span>Threshold: {preset.compressor.threshold}dB</span>
              <span>Ratio: {preset.compressor.ratio}:1</span>
              <span>Attack: {preset.compressor.attack}ms</span>
              <span>Release: {preset.compressor.release}ms</span>
            </div>
          </div>
        )}

        {/* Reverb Preview */}
        {preset.reverb && (
          <div className="effect-preview">
            <h5>Reverb ({preset.reverb.type})</h5>
            <div className="reverb-params">
              <span>Decay: {preset.reverb.decay}s</span>
              <span>Mix: {(preset.reverb.mix * 100).toFixed(0)}%</span>
              <span>Damping: {(preset.reverb.damping * 100).toFixed(0)}%</span>
            </div>
          </div>
        )}

        {/* Delay Preview */}
        {preset.delay && (
          <div className="effect-preview">
            <h5>Delay</h5>
            <div className="delay-params">
              <span>Time: {preset.delay.time}ms</span>
              <span>Feedback: {(preset.delay.feedback * 100).toFixed(0)}%</span>
              <span>Mix: {(preset.delay.mix * 100).toFixed(0)}%</span>
              {preset.delay.pingPong && <span>Ping-Pong</span>}
            </div>
          </div>
        )}

        {/* Additional */}
        <div className="effect-preview additional">
          {preset.stereoWidth !== undefined && (
            <span>Stereo: {(preset.stereoWidth * 100).toFixed(0)}%</span>
          )}
          {preset.saturate !== undefined && (
            <span>Saturation: {(preset.saturate * 100).toFixed(0)}%</span>
          )}
          {preset.outputGain !== undefined && (
            <span>Output: {preset.outputGain > 0 ? '+' : ''}{preset.outputGain}dB</span>
          )}
        </div>
      </div>

      <div className="details-actions">
        <button className="apply-btn large" onClick={onApply}>
          Apply Preset
        </button>
      </div>
    </div>
  );
});

PresetDetails.displayName = 'PresetDetails';
