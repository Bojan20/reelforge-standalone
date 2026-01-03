/**
 * ReelForge Pro Suite - Top Bar Component
 *
 * Shared top toolbar for VanEQ, VanComp, VanLimit Pro plugins.
 * Features: A/B comparison, Undo/Redo, Quality/Mode selector, Theme selector.
 *
 * @module plugin/pro-suite/TopBar
 */

import { useCallback } from 'react';
import type { ProSuiteTheme, ThemeMode } from './theme';

// ============ Types ============

export interface TopBarProps {
  // Plugin identity
  pluginName: string;

  // A/B Comparison
  abState: 'A' | 'B';
  onABToggle: () => void;
  onABCopy: () => void;

  // Undo/Redo
  canUndo: boolean;
  canRedo: boolean;
  onUndo: () => void;
  onRedo: () => void;

  // Quality/Mode (optional - for compressor/limiter)
  qualityMode?: string;
  qualityOptions?: string[];
  onQualityChange?: (mode: string) => void;

  // Analyzer (optional)
  showAnalyzer?: boolean;
  onAnalyzerToggle?: () => void;

  // Theme
  themeMode: ThemeMode;
  onThemeModeChange: (mode: ThemeMode) => void;

  // Bypass
  bypassed: boolean;
  onBypassToggle: () => void;

  theme: ProSuiteTheme;
  readOnly?: boolean;
}

// ============ Icon Button Component ============

interface IconButtonProps {
  icon: string;
  label: string;
  onClick: () => void;
  disabled?: boolean;
  active?: boolean;
  theme: ProSuiteTheme;
}

function IconButton({ icon, label, onClick, disabled = false, active = false, theme }: IconButtonProps) {
  return (
    <button
      className={`vp-icon-btn ${active ? 'active' : ''}`}
      onClick={onClick}
      disabled={disabled}
      title={label}
      style={{
        backgroundColor: active ? theme.buttonBgActive : theme.buttonBg,
        color: disabled ? theme.textMuted : theme.buttonText,
        opacity: disabled ? 0.5 : 1,
      }}
    >
      {icon}
    </button>
  );
}

// ============ Top Bar Component ============

export function TopBar({
  pluginName,
  abState,
  onABToggle,
  onABCopy,
  canUndo,
  canRedo,
  onUndo,
  onRedo,
  qualityMode,
  qualityOptions,
  onQualityChange,
  showAnalyzer,
  onAnalyzerToggle,
  themeMode,
  onThemeModeChange,
  bypassed,
  onBypassToggle,
  theme,
  readOnly = false,
}: TopBarProps) {
  const handleThemeCycle = useCallback(() => {
    const modes: ThemeMode[] = ['auto', 'dark', 'light'];
    const currentIndex = modes.indexOf(themeMode);
    const nextIndex = (currentIndex + 1) % modes.length;
    onThemeModeChange(modes[nextIndex]);
  }, [themeMode, onThemeModeChange]);

  const getThemeIcon = () => {
    switch (themeMode) {
      case 'dark': return '🌙';
      case 'light': return '☀️';
      default: return '🔄';
    }
  };

  const getThemeLabel = () => {
    switch (themeMode) {
      case 'dark': return 'Dark theme';
      case 'light': return 'Light theme';
      default: return 'Auto theme (follows system)';
    }
  };

  return (
    <div className="vp-top-bar" style={{ backgroundColor: theme.bgSecondary }}>
      {/* Left section: A/B Comparison */}
      <div className="vp-top-section">
        <div className="vp-ab-group">
          <button
            className={`vp-ab-btn ${abState === 'A' ? 'active' : ''}`}
            onClick={onABToggle}
            disabled={readOnly}
            style={{
              backgroundColor: abState === 'A' ? theme.accentPrimary : theme.buttonBg,
              color: abState === 'A' ? '#fff' : theme.textSecondary,
            }}
          >
            A
          </button>
          <button
            className={`vp-ab-btn ${abState === 'B' ? 'active' : ''}`}
            onClick={onABToggle}
            disabled={readOnly}
            style={{
              backgroundColor: abState === 'B' ? theme.accentPrimary : theme.buttonBg,
              color: abState === 'B' ? '#fff' : theme.textSecondary,
            }}
          >
            B
          </button>
          <button
            className="vp-ab-copy-btn"
            onClick={onABCopy}
            disabled={readOnly}
            title="Copy current to other slot"
            style={{
              backgroundColor: theme.buttonBg,
              color: theme.textSecondary,
            }}
          >
            →
          </button>
        </div>

        {/* Undo/Redo */}
        <div className="vp-history-group">
          <IconButton
            icon="↶"
            label="Undo (Ctrl+Z)"
            onClick={onUndo}
            disabled={!canUndo || readOnly}
            theme={theme}
          />
          <IconButton
            icon="↷"
            label="Redo (Ctrl+Y)"
            onClick={onRedo}
            disabled={!canRedo || readOnly}
            theme={theme}
          />
        </div>

        {/* Quality/Mode selector (optional) */}
        {qualityMode && qualityOptions && onQualityChange && (
          <div className="vp-quality-group">
            <select
              className="vp-quality-select"
              value={qualityMode}
              onChange={(e) => onQualityChange(e.target.value)}
              disabled={readOnly}
              style={{
                backgroundColor: theme.inputBg,
                color: theme.textPrimary,
                borderColor: theme.inputBorder,
              }}
            >
              {qualityOptions.map((opt) => (
                <option key={opt} value={opt}>{opt}</option>
              ))}
            </select>
          </div>
        )}
      </div>

      {/* Center: Title */}
      <div className="vp-top-title" style={{ color: theme.textPrimary }}>
        {pluginName}
      </div>

      {/* Right section: Options */}
      <div className="vp-top-section">
        {/* Analyzer toggle (optional) */}
        {onAnalyzerToggle && (
          <IconButton
            icon="📊"
            label={showAnalyzer ? 'Hide Analyzer' : 'Show Analyzer'}
            onClick={onAnalyzerToggle}
            active={showAnalyzer}
            theme={theme}
          />
        )}

        {/* Theme toggle */}
        <IconButton
          icon={getThemeIcon()}
          label={getThemeLabel()}
          onClick={handleThemeCycle}
          theme={theme}
        />

        {/* Bypass */}
        <button
          className={`vp-bypass-btn ${bypassed ? 'bypassed' : ''}`}
          onClick={onBypassToggle}
          disabled={readOnly}
          style={{
            backgroundColor: bypassed ? theme.statusBypassed : theme.statusActive,
            color: '#fff',
          }}
        >
          {bypassed ? 'OFF' : 'ON'}
        </button>
      </div>
    </div>
  );
}
