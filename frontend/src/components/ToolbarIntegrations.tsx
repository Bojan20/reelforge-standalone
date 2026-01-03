/**
 * Toolbar Integration Components
 *
 * Integrates core systems into UI:
 * - UndoRedoButtons - Undo/Redo with state
 * - ThemeToggle - Light/Dark/System switcher
 * - MasterMeter - Peak meter display
 * - ProjectStatus - Save indicator
 *
 * @module components/ToolbarIntegrations
 */

import { memo, useState, useRef, useEffect } from 'react';
import { useUndo } from '../core/undoSystem';
import { useTheme, type ThemeMode } from '../core/themeSystem';
import { useMeter, formatDb } from '../core/audioMetering';
import { ProjectPersistence } from '../core/projectPersistence';
import './ToolbarIntegrations.css';

// ============ UNDO/REDO BUTTONS ============

export interface UndoRedoButtonsProps {
  compact?: boolean;
  showLabels?: boolean;
  showCounts?: boolean;
}

export const UndoRedoButtons = memo(function UndoRedoButtons({
  compact = false,
  showLabels = false,
  showCounts = true,
}: UndoRedoButtonsProps) {
  const { canUndo, canRedo, undoDescription, redoDescription, undoCount, redoCount, undo, redo } = useUndo();

  return (
    <div className={`toolbar-undo-redo ${compact ? 'compact' : ''}`}>
      <button
        className="toolbar-btn"
        onClick={undo}
        disabled={!canUndo}
        title={undoDescription ? `Undo: ${undoDescription} (⌘Z)` : 'Nothing to undo'}
      >
        <span className="toolbar-btn__icon">↩</span>
        {showLabels && <span className="toolbar-btn__label">Undo</span>}
        {showCounts && undoCount > 0 && (
          <span className="toolbar-btn__badge">{undoCount}</span>
        )}
      </button>

      <button
        className="toolbar-btn"
        onClick={redo}
        disabled={!canRedo}
        title={redoDescription ? `Redo: ${redoDescription} (⇧⌘Z)` : 'Nothing to redo'}
      >
        <span className="toolbar-btn__icon">↪</span>
        {showLabels && <span className="toolbar-btn__label">Redo</span>}
        {showCounts && redoCount > 0 && (
          <span className="toolbar-btn__badge">{redoCount}</span>
        )}
      </button>
    </div>
  );
});

// ============ THEME TOGGLE ============

export interface ThemeToggleProps {
  showLabel?: boolean;
  showDropdown?: boolean;
}

export const ThemeToggle = memo(function ThemeToggle({
  showLabel = false,
  showDropdown = true,
}: ThemeToggleProps) {
  const { mode, resolvedMode, presets, currentPreset, setMode, setPreset, toggleMode } = useTheme();
  const [dropdownOpen, setDropdownOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close on outside click
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setDropdownOpen(false);
      }
    };
    if (dropdownOpen) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [dropdownOpen]);

  const modeIcon = resolvedMode === 'dark' ? '🌙' : '☀️';
  const modeLabel = mode === 'system' ? 'Auto' : mode === 'dark' ? 'Dark' : 'Light';

  if (!showDropdown) {
    return (
      <button
        className="toolbar-btn toolbar-theme-btn"
        onClick={toggleMode}
        title={`Theme: ${modeLabel} (click to toggle)`}
      >
        <span className="toolbar-btn__icon">{modeIcon}</span>
        {showLabel && <span className="toolbar-btn__label">{modeLabel}</span>}
      </button>
    );
  }

  return (
    <div className="toolbar-theme-dropdown" ref={dropdownRef}>
      <button
        className="toolbar-btn toolbar-theme-btn"
        onClick={() => setDropdownOpen(!dropdownOpen)}
        title="Theme Settings"
      >
        <span className="toolbar-btn__icon">{modeIcon}</span>
        {showLabel && <span className="toolbar-btn__label">{modeLabel}</span>}
        <span className="toolbar-btn__chevron">▾</span>
      </button>

      {dropdownOpen && (
        <div className="theme-dropdown">
          <div className="theme-dropdown__section">
            <div className="theme-dropdown__label">Mode</div>
            <div className="theme-dropdown__modes">
              {(['light', 'dark', 'system'] as ThemeMode[]).map((m) => (
                <button
                  key={m}
                  className={`theme-mode-btn ${mode === m ? 'active' : ''}`}
                  onClick={() => setMode(m)}
                >
                  {m === 'light' ? '☀️' : m === 'dark' ? '🌙' : '🖥️'}
                  <span>{m.charAt(0).toUpperCase() + m.slice(1)}</span>
                </button>
              ))}
            </div>
          </div>

          <div className="theme-dropdown__separator" />

          <div className="theme-dropdown__section">
            <div className="theme-dropdown__label">Preset</div>
            <div className="theme-dropdown__presets">
              {presets.map((preset) => (
                <button
                  key={preset.id}
                  className={`theme-preset-btn ${currentPreset?.id === preset.id ? 'active' : ''}`}
                  onClick={() => setPreset(preset.id)}
                  title={preset.description}
                >
                  <span
                    className="theme-preset-btn__swatch"
                    style={{ background: preset.colors.accent }}
                  />
                  <span>{preset.name}</span>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
});

// ============ MASTER METER ============

export interface MasterMeterProps {
  meterId?: string;
  width?: number;
  height?: number;
  showPeakHold?: boolean;
  showLufs?: boolean;
}

export const MasterMeter = memo(function MasterMeter({
  meterId = 'master',
  width = 120,
  height = 24,
  showPeakHold = true,
  showLufs = false,
}: MasterMeterProps) {
  const { reading } = useMeter(meterId);
  const [peakHoldL, setPeakHoldL] = useState(-Infinity);
  const [peakHoldR, setPeakHoldR] = useState(-Infinity);

  // Update peak hold
  useEffect(() => {
    if (!reading) return;

    if (reading.left.peak > peakHoldL) {
      setPeakHoldL(reading.left.peak);
    }
    if (reading.right.peak > peakHoldR) {
      setPeakHoldR(reading.right.peak);
    }
  }, [reading, peakHoldL, peakHoldR]);

  // Reset peak hold on click
  const handleClick = () => {
    setPeakHoldL(-Infinity);
    setPeakHoldR(-Infinity);
  };

  // No reading - show empty meter
  if (!reading) {
    return (
      <div
        className="master-meter master-meter--empty"
        style={{ width, height }}
        title="No audio signal"
      >
        <div className="master-meter__channel">
          <div className="master-meter__bar" />
          <span className="master-meter__label">L</span>
        </div>
        <div className="master-meter__channel">
          <div className="master-meter__bar" />
          <span className="master-meter__label">R</span>
        </div>
        <span className="master-meter__value">-∞</span>
      </div>
    );
  }

  const leftDb = reading.left.peak;
  const rightDb = reading.right.peak;
  const leftPct = dbToPercent(leftDb);
  const rightPct = dbToPercent(rightDb);
  const peakHoldLPct = dbToPercent(peakHoldL);
  const peakHoldRPct = dbToPercent(peakHoldR);

  return (
    <div
      className={`master-meter ${reading.isClipping ? 'master-meter--clipping' : ''}`}
      style={{ width, height }}
      onClick={handleClick}
      title={`Peak: ${formatDb(Math.max(leftDb, rightDb))} dB (click to reset)`}
    >
      {/* Left Channel */}
      <div className="master-meter__channel">
        <div className="master-meter__bar">
          <div
            className="master-meter__fill"
            style={{
              width: `${leftPct}%`,
              background: getMeterGradient(leftDb),
            }}
          />
          {showPeakHold && peakHoldL > -60 && (
            <div
              className="master-meter__peak-hold"
              style={{ left: `${peakHoldLPct}%` }}
            />
          )}
        </div>
        <span className="master-meter__label">L</span>
      </div>

      {/* Right Channel */}
      <div className="master-meter__channel">
        <div className="master-meter__bar">
          <div
            className="master-meter__fill"
            style={{
              width: `${rightPct}%`,
              background: getMeterGradient(rightDb),
            }}
          />
          {showPeakHold && peakHoldR > -60 && (
            <div
              className="master-meter__peak-hold"
              style={{ left: `${peakHoldRPct}%` }}
            />
          )}
        </div>
        <span className="master-meter__label">R</span>
      </div>

      {/* Peak Value */}
      <span className={`master-meter__value ${reading.isClipping ? 'clipping' : ''}`}>
        {formatDb(Math.max(leftDb, rightDb))}
      </span>

      {/* LUFS (optional) */}
      {showLufs && (
        <span className="master-meter__lufs">
          {reading.lufsShort > -Infinity ? reading.lufsShort.toFixed(1) : '-∞'}
        </span>
      )}

      {/* Clip Indicator */}
      {reading.isClipping && (
        <div className="master-meter__clip-indicator">CLIP</div>
      )}
    </div>
  );
});

// Helper: dB to percentage (0-100)
function dbToPercent(db: number, minDb = -60, maxDb = 6): number {
  if (db <= minDb) return 0;
  if (db >= maxDb) return 100;
  return ((db - minDb) / (maxDb - minDb)) * 100;
}

// Helper: Get gradient based on level
function getMeterGradient(db: number): string {
  if (db >= 0) {
    return 'linear-gradient(90deg, #22c55e 0%, #eab308 60%, #ef4444 90%)';
  }
  if (db >= -6) {
    return 'linear-gradient(90deg, #22c55e 0%, #eab308 70%, #f59e0b 100%)';
  }
  if (db >= -12) {
    return 'linear-gradient(90deg, #22c55e 0%, #22c55e 80%, #eab308 100%)';
  }
  return '#22c55e';
}

// ============ PROJECT STATUS ============

export interface ProjectStatusProps {
  projectName?: string;
  showAutoSave?: boolean;
}

export const ProjectStatus = memo(function ProjectStatus({
  projectName,
  showAutoSave = true,
}: ProjectStatusProps) {
  const [isDirty, setIsDirty] = useState(ProjectPersistence.hasDirtyChanges());
  const [lastAutoSave, setLastAutoSave] = useState<string | null>(null);

  // Poll dirty state
  useEffect(() => {
    const interval = setInterval(() => {
      setIsDirty(ProjectPersistence.hasDirtyChanges());

      // Check auto-save
      const project = ProjectPersistence.getCurrentProject();
      if (project) {
        const autoSave = ProjectPersistence.getAutoSaveForProject(project.metadata.id);
        if (autoSave) {
          setLastAutoSave(autoSave.timestamp);
        }
      }
    }, 1000);

    return () => clearInterval(interval);
  }, []);

  const displayName = projectName || ProjectPersistence.getCurrentProject()?.metadata.name || 'Untitled';

  return (
    <div className="project-status">
      <span className={`project-status__name ${isDirty ? 'dirty' : ''}`}>
        {displayName}
        {isDirty && <span className="project-status__dirty">•</span>}
      </span>

      {showAutoSave && lastAutoSave && (
        <span className="project-status__autosave" title={`Last auto-save: ${new Date(lastAutoSave).toLocaleTimeString()}`}>
          ✓
        </span>
      )}
    </div>
  );
});

// ============ INTEGRATED TOOLBAR ============

export interface IntegratedToolbarProps {
  showUndoRedo?: boolean;
  showTheme?: boolean;
  showMeter?: boolean;
  showProjectStatus?: boolean;
  projectName?: string;
  meterId?: string;
}

export const IntegratedToolbar = memo(function IntegratedToolbar({
  showUndoRedo = true,
  showTheme = true,
  showMeter = true,
  showProjectStatus = true,
  projectName,
  meterId = 'master',
}: IntegratedToolbarProps) {
  return (
    <div className="integrated-toolbar">
      {showUndoRedo && (
        <>
          <UndoRedoButtons compact />
          <div className="toolbar-divider" />
        </>
      )}

      {showProjectStatus && (
        <>
          <ProjectStatus projectName={projectName} />
          <div className="toolbar-divider" />
        </>
      )}

      {showMeter && (
        <>
          <MasterMeter meterId={meterId} />
          <div className="toolbar-divider" />
        </>
      )}

      {showTheme && (
        <ThemeToggle showDropdown />
      )}
    </div>
  );
});

export default IntegratedToolbar;
