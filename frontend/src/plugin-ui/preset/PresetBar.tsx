/**
 * Preset Bar Component
 *
 * Preset browser and A/B comparison for plugins.
 *
 * @module plugin-ui/preset/PresetBar
 */

import { memo, useState, useCallback } from 'react';
import { usePluginTheme } from '../usePluginTheme';
import './PresetBar.css';

export interface PresetBarProps {
  /** Current preset name */
  presetName: string;
  /** Preset changed callback */
  onPresetChange?: (presetId: string) => void;
  /** Save preset callback */
  onSavePreset?: () => void;
  /** A/B comparison enabled */
  showAB?: boolean;
  /** Current A/B state */
  abState?: 'A' | 'B';
  /** A/B toggle callback */
  onABToggle?: () => void;
  /** Copy A to B callback */
  onCopyAToB?: () => void;
  /** Bypass enabled */
  bypass?: boolean;
  /** Bypass toggle callback */
  onBypassToggle?: () => void;
  /** Undo callback */
  onUndo?: () => void;
  /** Redo callback */
  onRedo?: () => void;
  /** Can undo */
  canUndo?: boolean;
  /** Can redo */
  canRedo?: boolean;
  /** Custom class */
  className?: string;
}

function PresetBarInner({
  presetName,
  onPresetChange: _onPresetChange,
  onSavePreset,
  showAB = true,
  abState = 'A',
  onABToggle,
  onCopyAToB,
  bypass = false,
  onBypassToggle,
  onUndo,
  onRedo,
  canUndo = false,
  canRedo = false,
  className,
}: PresetBarProps) {
  const theme = usePluginTheme();
  // Note: showPresetMenu state is for future preset dropdown implementation
  const [_showPresetMenu, setShowPresetMenu] = useState(false);

  const handlePresetClick = useCallback(() => {
    setShowPresetMenu((prev) => !prev);
    // TODO: Implement preset dropdown menu
  }, []);

  return (
    <div
      className={`preset-bar ${className ?? ''}`}
      style={{
        background: theme.bgSecondary,
        borderColor: theme.border,
      }}
    >
      {/* Left section: Preset browser */}
      <div className="preset-bar__left">
        <button
          className="preset-bar__preset-btn"
          onClick={handlePresetClick}
          style={{
            background: theme.bgControl,
            color: theme.textPrimary,
            borderColor: theme.border,
          }}
        >
          <span className="preset-bar__preset-name">{presetName}</span>
          <span className="preset-bar__preset-arrow">▼</span>
        </button>

        {onSavePreset && (
          <button
            className="preset-bar__icon-btn"
            onClick={onSavePreset}
            title="Save Preset"
            style={{ color: theme.textSecondary }}
          >
            💾
          </button>
        )}
      </div>

      {/* Center section: A/B comparison */}
      {showAB && (
        <div className="preset-bar__center">
          <button
            className={`preset-bar__ab-btn ${abState === 'A' ? 'active' : ''}`}
            onClick={onABToggle}
            style={{
              background: abState === 'A' ? theme.accent : theme.bgControl,
              color: abState === 'A' ? '#ffffff' : theme.textSecondary,
              borderColor: theme.border,
            }}
          >
            A
          </button>
          <button
            className={`preset-bar__ab-btn ${abState === 'B' ? 'active' : ''}`}
            onClick={onABToggle}
            style={{
              background: abState === 'B' ? theme.accent : theme.bgControl,
              color: abState === 'B' ? '#ffffff' : theme.textSecondary,
              borderColor: theme.border,
            }}
          >
            B
          </button>
          {onCopyAToB && (
            <button
              className="preset-bar__icon-btn"
              onClick={onCopyAToB}
              title="Copy A → B"
              style={{ color: theme.textSecondary }}
            >
              ⇒
            </button>
          )}
        </div>
      )}

      {/* Right section: Bypass, Undo/Redo */}
      <div className="preset-bar__right">
        {onUndo && (
          <button
            className="preset-bar__icon-btn"
            onClick={onUndo}
            disabled={!canUndo}
            title="Undo"
            style={{
              color: canUndo ? theme.textSecondary : theme.textDisabled,
            }}
          >
            ↶
          </button>
        )}
        {onRedo && (
          <button
            className="preset-bar__icon-btn"
            onClick={onRedo}
            disabled={!canRedo}
            title="Redo"
            style={{
              color: canRedo ? theme.textSecondary : theme.textDisabled,
            }}
          >
            ↷
          </button>
        )}
        {onBypassToggle && (
          <button
            className={`preset-bar__bypass-btn ${bypass ? 'active' : ''}`}
            onClick={onBypassToggle}
            title="Bypass"
            style={{
              background: bypass ? theme.warning : theme.bgControl,
              color: bypass ? '#000000' : theme.textSecondary,
              borderColor: theme.border,
            }}
          >
            BYP
          </button>
        )}
      </div>
    </div>
  );
}

export const PresetBar = memo(PresetBarInner);
export default PresetBar;
