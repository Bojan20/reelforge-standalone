/**
 * ReelForge Theme Editor
 *
 * Visual editor for customizing theme colors.
 * Professional UI for DAW theme customization.
 *
 * @module theme/ThemeEditor
 */

import { useState, useCallback, useMemo } from 'react';
import { useThemeContext, type ThemeColors } from './ThemeProvider';
import './ThemeEditor.css';

// ============ Types ============

interface ColorGroup {
  label: string;
  colors: Array<{
    key: keyof ThemeColors;
    label: string;
    description?: string;
  }>;
}

// ============ Color Groups ============

const COLOR_GROUPS: ColorGroup[] = [
  {
    label: 'Background',
    colors: [
      { key: 'bg0', label: 'Base', description: 'Deepest background' },
      { key: 'bg1', label: 'Panel', description: 'Panel background' },
      { key: 'bg2', label: 'Elevated', description: 'Cards, dropdowns' },
      { key: 'bg3', label: 'Hover', description: 'Hover states' },
      { key: 'bg4', label: 'Active', description: 'Active/pressed states' },
    ],
  },
  {
    label: 'Border',
    colors: [
      { key: 'border', label: 'Default', description: 'Default border' },
      { key: 'borderFocus', label: 'Focus', description: 'Focus ring' },
      { key: 'borderActive', label: 'Active', description: 'Active border' },
    ],
  },
  {
    label: 'Text',
    colors: [
      { key: 'textPrimary', label: 'Primary', description: 'Main text' },
      { key: 'textSecondary', label: 'Secondary', description: 'Labels' },
      { key: 'textTertiary', label: 'Tertiary', description: 'Hints' },
      { key: 'textDisabled', label: 'Disabled', description: 'Disabled text' },
    ],
  },
  {
    label: 'Accent',
    colors: [
      { key: 'accentPrimary', label: 'Primary', description: 'Main accent' },
      { key: 'accentSuccess', label: 'Success', description: 'Success states' },
      { key: 'accentWarning', label: 'Warning', description: 'Warning states' },
      { key: 'accentError', label: 'Error', description: 'Error states' },
      { key: 'accentSelected', label: 'Selected', description: 'Selection' },
    ],
  },
  {
    label: 'Object Types',
    colors: [
      { key: 'colorEvent', label: 'Event', description: 'Audio events' },
      { key: 'colorSound', label: 'Sound', description: 'Sound objects' },
      { key: 'colorBus', label: 'Bus', description: 'Audio buses' },
      { key: 'colorState', label: 'State', description: 'State groups' },
      { key: 'colorSwitch', label: 'Switch', description: 'Switch containers' },
      { key: 'colorRtpc', label: 'RTPC', description: 'Parameters' },
      { key: 'colorMusic', label: 'Music', description: 'Music segments' },
      { key: 'colorVoice', label: 'Voice', description: 'Voices' },
    ],
  },
];

// ============ Component ============

export interface ThemeEditorProps {
  /** Compact mode */
  compact?: boolean;
  /** Show preset selector */
  showPresets?: boolean;
  /** Show mode toggle */
  showModeToggle?: boolean;
  /** Show reset button */
  showReset?: boolean;
  /** Callback on color change */
  onColorChange?: (key: keyof ThemeColors, value: string) => void;
  /** Custom class */
  className?: string;
}

export function ThemeEditor({
  compact = false,
  showPresets = true,
  showModeToggle = true,
  showReset = true,
  onColorChange,
  className,
}: ThemeEditorProps) {
  const {
    mode,
    preset,
    presets,
    colors,
    setMode,
    setPreset,
    setCustomColor,
    resetCustomColors,
    toggleMode,
    isDark,
  } = useThemeContext();

  const [expandedGroup, setExpandedGroup] = useState<string | null>(
    compact ? null : 'Accent'
  );

  // Handle color change
  const handleColorChange = useCallback(
    (key: keyof ThemeColors, value: string) => {
      setCustomColor(key, value);
      onColorChange?.(key, value);
    },
    [setCustomColor, onColorChange]
  );

  // Group presets by mode
  const groupedPresets = useMemo(() => {
    const dark = presets.filter((p) => p.mode === 'dark');
    const light = presets.filter((p) => p.mode === 'light');
    return { dark, light };
  }, [presets]);

  return (
    <div className={`theme-editor ${compact ? 'theme-editor--compact' : ''} ${className ?? ''}`}>
      {/* Header */}
      <div className="theme-editor__header">
        <h3 className="theme-editor__title">Theme</h3>
        {showModeToggle && (
          <button
            className="theme-editor__mode-toggle"
            onClick={toggleMode}
            aria-label={`Switch to ${isDark ? 'light' : 'dark'} mode`}
          >
            {isDark ? '☀️' : '🌙'}
          </button>
        )}
      </div>

      {/* Preset Selector */}
      {showPresets && (
        <div className="theme-editor__presets">
          <label className="theme-editor__label">Preset</label>
          <select
            className="theme-editor__select"
            value={preset}
            onChange={(e) => setPreset(e.target.value)}
          >
            <optgroup label="Dark">
              {groupedPresets.dark.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </optgroup>
            <optgroup label="Light">
              {groupedPresets.light.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </optgroup>
          </select>
        </div>
      )}

      {/* Mode Selector */}
      <div className="theme-editor__mode">
        <label className="theme-editor__label">Mode</label>
        <div className="theme-editor__mode-buttons">
          <button
            className={`theme-editor__mode-btn ${mode === 'dark' ? 'active' : ''}`}
            onClick={() => setMode('dark')}
          >
            Dark
          </button>
          <button
            className={`theme-editor__mode-btn ${mode === 'light' ? 'active' : ''}`}
            onClick={() => setMode('light')}
          >
            Light
          </button>
          <button
            className={`theme-editor__mode-btn ${mode === 'system' ? 'active' : ''}`}
            onClick={() => setMode('system')}
          >
            System
          </button>
        </div>
      </div>

      {/* Color Groups */}
      <div className="theme-editor__groups">
        {COLOR_GROUPS.map((group) => (
          <div key={group.label} className="theme-editor__group">
            <button
              className="theme-editor__group-header"
              onClick={() =>
                setExpandedGroup(expandedGroup === group.label ? null : group.label)
              }
            >
              <span>{group.label}</span>
              <span className="theme-editor__group-chevron">
                {expandedGroup === group.label ? '▼' : '▶'}
              </span>
            </button>

            {expandedGroup === group.label && (
              <div className="theme-editor__group-colors">
                {group.colors.map(({ key, label, description }) => (
                  <div key={key} className="theme-editor__color-row">
                    <div className="theme-editor__color-info">
                      <span className="theme-editor__color-label">{label}</span>
                      {description && (
                        <span className="theme-editor__color-desc">
                          {description}
                        </span>
                      )}
                    </div>
                    <div className="theme-editor__color-input-wrapper">
                      <input
                        type="color"
                        className="theme-editor__color-input"
                        value={colors[key]}
                        onChange={(e) => handleColorChange(key, e.target.value)}
                      />
                      <input
                        type="text"
                        className="theme-editor__color-hex"
                        value={colors[key]}
                        onChange={(e) => handleColorChange(key, e.target.value)}
                        maxLength={7}
                      />
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>

      {/* Reset Button */}
      {showReset && (
        <div className="theme-editor__actions">
          <button
            className="theme-editor__reset-btn"
            onClick={resetCustomColors}
          >
            Reset Custom Colors
          </button>
        </div>
      )}

      {/* Preview */}
      <div className="theme-editor__preview">
        <div className="theme-editor__preview-title">Preview</div>
        <div className="theme-editor__preview-content">
          <div
            className="theme-editor__preview-box"
            style={{ background: colors.bg0 }}
          >
            <div
              className="theme-editor__preview-panel"
              style={{
                background: colors.bg1,
                border: `1px solid ${colors.border}`,
              }}
            >
              <div
                className="theme-editor__preview-text"
                style={{ color: colors.textPrimary }}
              >
                Primary Text
              </div>
              <div
                className="theme-editor__preview-text-secondary"
                style={{ color: colors.textSecondary }}
              >
                Secondary Text
              </div>
              <div className="theme-editor__preview-accents">
                <span
                  style={{
                    background: colors.accentPrimary,
                    padding: '2px 8px',
                    borderRadius: '4px',
                    color: '#fff',
                  }}
                >
                  Primary
                </span>
                <span
                  style={{
                    background: colors.accentSuccess,
                    padding: '2px 8px',
                    borderRadius: '4px',
                    color: '#fff',
                  }}
                >
                  Success
                </span>
                <span
                  style={{
                    background: colors.accentWarning,
                    padding: '2px 8px',
                    borderRadius: '4px',
                    color: '#fff',
                  }}
                >
                  Warning
                </span>
                <span
                  style={{
                    background: colors.accentError,
                    padding: '2px 8px',
                    borderRadius: '4px',
                    color: '#fff',
                  }}
                >
                  Error
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default ThemeEditor;
