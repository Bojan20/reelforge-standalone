/**
 * ReelForge Control Bar
 *
 * Top control bar with:
 * - Logo and menu
 * - Transport controls
 * - Tempo/Time signature
 * - Time display
 * - System meters
 *
 * @module layout/ControlBar
 */

import { memo, useCallback, useState, useRef, useEffect } from 'react';
import reelforgeLogo from '../assets/reelforge-logo.png';
import { type EditorMode, MODE_CONFIGS } from '../hooks/useEditorMode';

// ============ Types ============

export interface MenuItemConfig {
  id: string;
  label: string;
  shortcut?: string;
  disabled?: boolean;
  separator?: boolean;
}

export interface MenuCallbacks {
  // File menu
  onNewProject?: () => void;
  onOpenProject?: () => void;
  onSaveProject?: () => void;
  onSaveProjectAs?: () => void;
  onImportJSON?: () => void;
  onExportJSON?: () => void;
  onImportAudioFolder?: () => void;
  // Edit menu
  onUndo?: () => void;
  onRedo?: () => void;
  onCut?: () => void;
  onCopy?: () => void;
  onPaste?: () => void;
  onDelete?: () => void;
  onSelectAll?: () => void;
  // View menu
  onToggleLeftPanel?: () => void;
  onToggleRightPanel?: () => void;
  onToggleLowerPanel?: () => void;
  onResetLayout?: () => void;
  // Project menu
  onProjectSettings?: () => void;
  onValidateProject?: () => void;
  onBuildProject?: () => void;
}

export interface ControlBarProps {
  // Editor mode
  editorMode?: EditorMode;
  onEditorModeChange?: (mode: EditorMode) => void;
  // Transport state
  isPlaying: boolean;
  isRecording: boolean;
  // Transport disable (temporary - while fixing preview)
  transportDisabled?: boolean;
  // Transport callbacks
  onPlay: () => void;
  onStop: () => void;
  onRecord: () => void;
  onRewind: () => void;
  onForward: () => void;
  // Tempo
  tempo: number;
  onTempoChange: (tempo: number) => void;
  // Time signature
  timeSignature: [number, number];
  // Time display
  currentTime: number;
  timeDisplayMode: 'bars' | 'timecode' | 'samples';
  onTimeDisplayModeChange: () => void;
  // Loop
  loopEnabled: boolean;
  onLoopToggle: () => void;
  // Snap to grid
  snapEnabled?: boolean;
  snapValue?: number; // in beats
  onSnapToggle?: () => void;
  onSnapValueChange?: (value: number) => void;
  // Metronome
  metronomeEnabled: boolean;
  onMetronomeToggle: () => void;
  // System
  cpuUsage?: number;
  memoryUsage?: number;
  // Project
  projectName?: string;
  onSave?: () => void;
  // Zone toggles
  onToggleLeftZone?: () => void;
  onToggleRightZone?: () => void;
  onToggleLowerZone?: () => void;
  // Menu callbacks
  menuCallbacks?: MenuCallbacks;
}

// ============ Time Formatting ============

function formatBarsBeats(
  seconds: number,
  tempo: number,
  timeSignature: [number, number]
): string {
  const beatsPerSecond = tempo / 60;
  const totalBeats = seconds * beatsPerSecond;
  const beatsPerBar = timeSignature[0];

  const bars = Math.floor(totalBeats / beatsPerBar) + 1;
  const beats = Math.floor(totalBeats % beatsPerBar) + 1;
  const ticks = Math.floor((totalBeats % 1) * 480);

  return `${bars.toString().padStart(3, ' ')}.${beats}.${ticks.toString().padStart(3, '0')}`;
}

function formatTimecode(seconds: number): string {
  const hrs = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  const secs = Math.floor(seconds % 60);
  const frames = Math.floor((seconds % 1) * 30);

  return `${hrs.toString().padStart(2, '0')}:${mins
    .toString()
    .padStart(2, '0')}:${secs.toString().padStart(2, '0')}:${frames
    .toString()
    .padStart(2, '0')}`;
}

function formatSamples(seconds: number, sampleRate = 48000): string {
  return Math.floor(seconds * sampleRate).toLocaleString();
}

// ============ Component ============

export const ControlBar = memo(function ControlBar({
  editorMode = 'daw',
  onEditorModeChange,
  isPlaying,
  isRecording,
  transportDisabled = false,
  onPlay,
  onStop,
  onRecord,
  onRewind,
  onForward,
  tempo,
  onTempoChange,
  timeSignature,
  currentTime,
  timeDisplayMode,
  onTimeDisplayModeChange,
  loopEnabled,
  onLoopToggle,
  snapEnabled = true,
  snapValue = 1,
  onSnapToggle,
  onSnapValueChange,
  metronomeEnabled,
  onMetronomeToggle,
  cpuUsage = 0,
  memoryUsage = 0,
  projectName = 'Untitled',
  onSave,
  onToggleLeftZone,
  onToggleRightZone,
  onToggleLowerZone,
  menuCallbacks,
}: ControlBarProps) {
  const [openMenu, setOpenMenu] = useState<string | null>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  // Close menu on outside click
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setOpenMenu(null);
      }
    };
    if (openMenu) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [openMenu]);

  const handleMenuClick = (menuId: string) => {
    setOpenMenu(openMenu === menuId ? null : menuId);
  };

  const handleMenuItemClick = (callback?: () => void) => {
    if (callback) {
      callback();
    }
    setOpenMenu(null);
  };
  // Format time based on mode
  const formattedTime =
    timeDisplayMode === 'bars'
      ? formatBarsBeats(currentTime, tempo, timeSignature)
      : timeDisplayMode === 'timecode'
      ? formatTimecode(currentTime)
      : formatSamples(currentTime);

  const timeModeLabel =
    timeDisplayMode === 'bars' ? 'BAR' : timeDisplayMode === 'timecode' ? 'TC' : 'SMP';

  // Tempo scroll handler
  const handleTempoWheel = useCallback(
    (e: React.WheelEvent) => {
      e.preventDefault();
      const delta = e.deltaY > 0 ? -1 : 1;
      const newTempo = Math.max(20, Math.min(999, tempo + delta));
      onTempoChange(newTempo);
    },
    [tempo, onTempoChange]
  );

  // CPU/Memory bar state
  const getCpuClass = () => {
    if (cpuUsage > 80) return 'rf-meter__fill--danger';
    if (cpuUsage > 60) return 'rf-meter__fill--warning';
    return '';
  };

  return (
    <div className="rf-control-bar">
      {/* Logo */}
      <div className="rf-control-bar__logo">
        <img
          src={reelforgeLogo}
          alt="ReelForge"
          className="rf-control-bar__logo-img"
        />
        <span>ReelForge</span>
      </div>

      {/* Menu Bar */}
      <div className="rf-menu-bar" ref={menuRef}>
        {/* File Menu */}
        <div className="rf-menu-bar__item-wrapper">
          <div
            className={`rf-menu-bar__item ${openMenu === 'file' ? 'active' : ''}`}
            onClick={() => handleMenuClick('file')}
          >
            File
          </div>
          {openMenu === 'file' && (
            <div className="rf-menu-dropdown">
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onNewProject)}>
                <span>New Project</span><span className="rf-menu-dropdown__shortcut">⌘N</span>
              </div>
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onOpenProject)}>
                <span>Open Project...</span><span className="rf-menu-dropdown__shortcut">⌘O</span>
              </div>
              <div className="rf-menu-dropdown__separator" />
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onSaveProject)}>
                <span>Save</span><span className="rf-menu-dropdown__shortcut">⌘S</span>
              </div>
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onSaveProjectAs)}>
                <span>Save As...</span><span className="rf-menu-dropdown__shortcut">⇧⌘S</span>
              </div>
              <div className="rf-menu-dropdown__separator" />
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onImportJSON)}>
                <span>Import Routes JSON...</span><span className="rf-menu-dropdown__shortcut">⌘I</span>
              </div>
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onExportJSON)}>
                <span>Export Routes JSON...</span><span className="rf-menu-dropdown__shortcut">⇧⌘E</span>
              </div>
              <div className="rf-menu-dropdown__separator" />
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onImportAudioFolder)}>
                <span>Import Audio Folder...</span><span className="rf-menu-dropdown__shortcut"></span>
              </div>
            </div>
          )}
        </div>

        {/* Edit Menu */}
        <div className="rf-menu-bar__item-wrapper">
          <div
            className={`rf-menu-bar__item ${openMenu === 'edit' ? 'active' : ''}`}
            onClick={() => handleMenuClick('edit')}
          >
            Edit
          </div>
          {openMenu === 'edit' && (
            <div className="rf-menu-dropdown">
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onUndo)}>
                <span>Undo</span><span className="rf-menu-dropdown__shortcut">⌘Z</span>
              </div>
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onRedo)}>
                <span>Redo</span><span className="rf-menu-dropdown__shortcut">⇧⌘Z</span>
              </div>
              <div className="rf-menu-dropdown__separator" />
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onCut)}>
                <span>Cut</span><span className="rf-menu-dropdown__shortcut">⌘X</span>
              </div>
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onCopy)}>
                <span>Copy</span><span className="rf-menu-dropdown__shortcut">⌘C</span>
              </div>
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onPaste)}>
                <span>Paste</span><span className="rf-menu-dropdown__shortcut">⌘V</span>
              </div>
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onDelete)}>
                <span>Delete</span><span className="rf-menu-dropdown__shortcut">⌫</span>
              </div>
              <div className="rf-menu-dropdown__separator" />
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onSelectAll)}>
                <span>Select All</span><span className="rf-menu-dropdown__shortcut">⌘A</span>
              </div>
            </div>
          )}
        </div>

        {/* View Menu */}
        <div className="rf-menu-bar__item-wrapper">
          <div
            className={`rf-menu-bar__item ${openMenu === 'view' ? 'active' : ''}`}
            onClick={() => handleMenuClick('view')}
          >
            View
          </div>
          {openMenu === 'view' && (
            <div className="rf-menu-dropdown">
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onToggleLeftPanel)}>
                <span>Toggle Left Panel</span><span className="rf-menu-dropdown__shortcut">⌘L</span>
              </div>
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onToggleRightPanel)}>
                <span>Toggle Right Panel</span><span className="rf-menu-dropdown__shortcut">⌘R</span>
              </div>
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onToggleLowerPanel)}>
                <span>Toggle Lower Panel</span><span className="rf-menu-dropdown__shortcut">⌘B</span>
              </div>
              <div className="rf-menu-dropdown__separator" />
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onResetLayout)}>
                <span>Reset Layout</span><span className="rf-menu-dropdown__shortcut"></span>
              </div>
            </div>
          )}
        </div>

        {/* Project Menu */}
        <div className="rf-menu-bar__item-wrapper">
          <div
            className={`rf-menu-bar__item ${openMenu === 'project' ? 'active' : ''}`}
            onClick={() => handleMenuClick('project')}
          >
            Project
          </div>
          {openMenu === 'project' && (
            <div className="rf-menu-dropdown">
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onProjectSettings)}>
                <span>Project Settings...</span><span className="rf-menu-dropdown__shortcut">⌘,</span>
              </div>
              <div className="rf-menu-dropdown__separator" />
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onValidateProject)}>
                <span>Validate Project</span><span className="rf-menu-dropdown__shortcut">⇧⌘V</span>
              </div>
              <div className="rf-menu-dropdown__item" onClick={() => handleMenuItemClick(menuCallbacks?.onBuildProject)}>
                <span>Build Project</span><span className="rf-menu-dropdown__shortcut">⌘B</span>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Mode Switcher */}
      {onEditorModeChange && (
        <div className="rf-mode-switcher">
          {Object.values(MODE_CONFIGS).map((modeConfig) => (
            <button
              key={modeConfig.mode}
              className={`rf-mode-switcher__btn ${editorMode === modeConfig.mode ? 'active' : ''}`}
              onClick={() => onEditorModeChange(modeConfig.mode)}
              title={`${modeConfig.name} - ${modeConfig.description} (${modeConfig.shortcut})`}
              style={{
                '--mode-accent': modeConfig.accentColor,
              } as React.CSSProperties}
            >
              <span className="rf-mode-switcher__icon">{modeConfig.icon}</span>
              <span className="rf-mode-switcher__label">{modeConfig.name}</span>
            </button>
          ))}
        </div>
      )}

      {/* Transport Controls */}
      <div className="rf-transport">
        <button
          className="rf-transport__btn"
          onClick={onRewind}
          title="Rewind (,)"
        >
          ⏮
        </button>

        <button
          className="rf-transport__btn"
          onClick={onStop}
          title="Stop (.)"
        >
          ⏹
        </button>

        <button
          className={`rf-transport__btn rf-transport__btn--play ${isPlaying ? 'active' : ''}`}
          onClick={onPlay}
          disabled={transportDisabled}
          title={transportDisabled ? "Timeline playback disabled (use Preview Event)" : "Play/Pause (Space)"}
          style={{ opacity: transportDisabled ? 0.4 : 1, cursor: transportDisabled ? 'not-allowed' : 'pointer' }}
        >
          {isPlaying ? '⏸' : '▶'}
        </button>

        <button
          className={`rf-transport__btn rf-transport__btn--record ${isRecording ? 'active' : ''}`}
          onClick={onRecord}
          title="Record (R)"
        >
          ⏺
        </button>

        <button
          className="rf-transport__btn"
          onClick={onForward}
          title="Forward (/)"
        >
          ⏭
        </button>

        <div style={{ width: 1, height: 24, background: 'var(--rf-border)', margin: '0 8px' }} />

        <button
          className={`rf-transport__btn ${loopEnabled ? 'active' : ''}`}
          onClick={onLoopToggle}
          title="Loop (L)"
          style={{ fontSize: 14 }}
        >
          🔁
        </button>

        <button
          className={`rf-transport__btn ${metronomeEnabled ? 'active' : ''}`}
          onClick={onMetronomeToggle}
          title="Metronome (K)"
          style={{ fontSize: 14 }}
        >
          🎵
        </button>

        <div style={{ width: 1, height: 24, background: 'var(--rf-border)', margin: '0 8px' }} />

        {/* Snap to Grid */}
        <button
          className={`rf-transport__btn ${snapEnabled ? 'active' : ''}`}
          onClick={onSnapToggle}
          title="Snap to Grid (G)"
          style={{ fontSize: 12, fontWeight: 600 }}
        >
          ⊞
        </button>
        {snapEnabled && onSnapValueChange && (
          <select
            className="rf-transport__snap-select"
            value={snapValue}
            onChange={(e) => onSnapValueChange(parseFloat(e.target.value))}
            title="Snap Resolution"
            style={{
              background: 'var(--rf-surface)',
              border: '1px solid var(--rf-border)',
              color: 'var(--rf-text)',
              borderRadius: 4,
              padding: '2px 4px',
              fontSize: 10,
              marginLeft: 4,
              cursor: 'pointer',
            }}
          >
            <option value={0.25}>1/16</option>
            <option value={0.5}>1/8</option>
            <option value={1}>1/4</option>
            <option value={2}>1/2</option>
            <option value={4}>Bar</option>
          </select>
        )}
      </div>

      {/* Tempo */}
      <div className="rf-tempo" onWheel={handleTempoWheel} title="Scroll to adjust tempo">
        <span className="rf-tempo__value">{tempo.toFixed(1)}</span>
        <span className="rf-tempo__label">BPM</span>
      </div>

      {/* Time Signature */}
      <div className="rf-tempo">
        <span className="rf-tempo__value" style={{ minWidth: 32 }}>
          {timeSignature[0]}/{timeSignature[1]}
        </span>
      </div>

      {/* Time Display */}
      <div
        className="rf-time-display"
        onClick={onTimeDisplayModeChange}
        title="Click to change display mode"
        style={{ cursor: 'pointer' }}
      >
        <span className="rf-time-display__value">{formattedTime}</span>
        <span className="rf-time-display__mode">{timeModeLabel}</span>
      </div>

      {/* Spacer */}
      <div style={{ flex: 1 }} />

      {/* Project Name & Save */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginRight: 16 }}>
        <span style={{ fontSize: 12, color: 'var(--rf-text-secondary)' }}>{projectName}</span>
        {onSave && (
          <button
            className="rf-transport__btn"
            onClick={onSave}
            title="Save (Ctrl+S)"
            style={{ fontSize: 12 }}
          >
            💾
          </button>
        )}
      </div>

      {/* Zone Toggles */}
      <div style={{ display: 'flex', gap: 4, marginRight: 12 }}>
        {onToggleLeftZone && (
          <button
            className="rf-transport__btn"
            onClick={onToggleLeftZone}
            title="Toggle Left Zone (Ctrl+L)"
            style={{ fontSize: 12 }}
          >
            ◀
          </button>
        )}
        {onToggleLowerZone && (
          <button
            className="rf-transport__btn"
            onClick={onToggleLowerZone}
            title="Toggle Lower Zone (Ctrl+B)"
            style={{ fontSize: 12 }}
          >
            ▼
          </button>
        )}
        {onToggleRightZone && (
          <button
            className="rf-transport__btn"
            onClick={onToggleRightZone}
            title="Toggle Right Zone (Ctrl+R)"
            style={{ fontSize: 12 }}
          >
            ▶
          </button>
        )}
      </div>

      {/* System Meters */}
      <div className="rf-system-meters">
        <div className="rf-meter">
          <span className="rf-meter__label">CPU</span>
          <div className="rf-meter__bar">
            <div
              className={`rf-meter__fill ${getCpuClass()}`}
              style={{ width: `${cpuUsage}%` }}
            />
          </div>
        </div>
        <div className="rf-meter">
          <span className="rf-meter__label">MEM</span>
          <div className="rf-meter__bar">
            <div
              className="rf-meter__fill"
              style={{ width: `${memoryUsage}%` }}
            />
          </div>
        </div>
      </div>
    </div>
  );
});

export default ControlBar;
