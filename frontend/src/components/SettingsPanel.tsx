/**
 * Settings Panel
 *
 * Application settings with tabs:
 * - General (Project, Audio)
 * - Appearance (Theme, Colors)
 * - Shortcuts (Keyboard bindings)
 * - Advanced (Performance, Debug)
 *
 * @module components/SettingsPanel
 */

import { memo, useState } from 'react';
import { useTheme, type ThemeMode, type ThemePreset } from '../core/themeSystem';
import './SettingsPanel.css';

// ============ TYPES ============

type SettingsTab = 'general' | 'appearance' | 'shortcuts' | 'advanced';

export interface GeneralSettings {
  projectName: string;
  author: string;
  sampleRate: 44100 | 48000 | 96000;
  bufferSize: 128 | 256 | 512 | 1024 | 2048;
  autoSaveInterval: number;
  showWelcome: boolean;
}

export interface AdvancedSettings {
  enableProfiling: boolean;
  enableDiagnostics: boolean;
  maxVoices: number;
  workerThreads: number;
  showFps: boolean;
}

export interface SettingsPanelProps {
  generalSettings: GeneralSettings;
  advancedSettings: AdvancedSettings;
  onGeneralChange?: (settings: Partial<GeneralSettings>) => void;
  onAdvancedChange?: (settings: Partial<AdvancedSettings>) => void;
  onClose?: () => void;
}

// ============ SETTINGS PANEL ============

export const SettingsPanel = memo(function SettingsPanel({
  generalSettings,
  advancedSettings,
  onGeneralChange,
  onAdvancedChange,
  onClose,
}: SettingsPanelProps) {
  const [activeTab, setActiveTab] = useState<SettingsTab>('general');

  const tabs: { id: SettingsTab; label: string; icon: string }[] = [
    { id: 'general', label: 'General', icon: '⚙️' },
    { id: 'appearance', label: 'Appearance', icon: '🎨' },
    { id: 'shortcuts', label: 'Shortcuts', icon: '⌨️' },
    { id: 'advanced', label: 'Advanced', icon: '🔧' },
  ];

  return (
    <div className="settings-panel">
      {/* Header */}
      <div className="settings-header">
        <h2>Settings</h2>
        {onClose && (
          <button className="settings-close-btn" onClick={onClose}>
            ✕
          </button>
        )}
      </div>

      {/* Tabs */}
      <div className="settings-tabs">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            className={`settings-tab ${activeTab === tab.id ? 'active' : ''}`}
            onClick={() => setActiveTab(tab.id)}
          >
            <span className="settings-tab__icon">{tab.icon}</span>
            <span>{tab.label}</span>
          </button>
        ))}
      </div>

      {/* Content */}
      <div className="settings-content">
        {activeTab === 'general' && (
          <GeneralSettingsTab
            settings={generalSettings}
            onChange={onGeneralChange}
          />
        )}
        {activeTab === 'appearance' && <AppearanceSettingsTab />}
        {activeTab === 'shortcuts' && <ShortcutsSettingsTab />}
        {activeTab === 'advanced' && (
          <AdvancedSettingsTab
            settings={advancedSettings}
            onChange={onAdvancedChange}
          />
        )}
      </div>
    </div>
  );
});

// ============ GENERAL TAB ============

interface GeneralSettingsTabProps {
  settings: GeneralSettings;
  onChange?: (settings: Partial<GeneralSettings>) => void;
}

const GeneralSettingsTab = memo(function GeneralSettingsTab({
  settings,
  onChange,
}: GeneralSettingsTabProps) {
  return (
    <div className="settings-section">
      <h3>Project</h3>
      <div className="settings-group">
        <SettingRow label="Project Name">
          <input
            type="text"
            value={settings.projectName}
            onChange={(e) => onChange?.({ projectName: e.target.value })}
            className="settings-input"
          />
        </SettingRow>
        <SettingRow label="Author">
          <input
            type="text"
            value={settings.author}
            onChange={(e) => onChange?.({ author: e.target.value })}
            className="settings-input"
          />
        </SettingRow>
      </div>

      <h3>Audio</h3>
      <div className="settings-group">
        <SettingRow label="Sample Rate" description="Audio engine sample rate">
          <select
            value={settings.sampleRate}
            onChange={(e) => onChange?.({ sampleRate: Number(e.target.value) as GeneralSettings['sampleRate'] })}
            className="settings-select"
          >
            <option value={44100}>44.1 kHz</option>
            <option value={48000}>48 kHz</option>
            <option value={96000}>96 kHz</option>
          </select>
        </SettingRow>
        <SettingRow label="Buffer Size" description="Lower = less latency, higher CPU">
          <select
            value={settings.bufferSize}
            onChange={(e) => onChange?.({ bufferSize: Number(e.target.value) as GeneralSettings['bufferSize'] })}
            className="settings-select"
          >
            <option value={128}>128 samples</option>
            <option value={256}>256 samples</option>
            <option value={512}>512 samples</option>
            <option value={1024}>1024 samples</option>
            <option value={2048}>2048 samples</option>
          </select>
        </SettingRow>
      </div>

      <h3>Auto-Save</h3>
      <div className="settings-group">
        <SettingRow label="Auto-save Interval" description="How often to auto-save (seconds)">
          <input
            type="number"
            min={10}
            max={300}
            value={settings.autoSaveInterval}
            onChange={(e) => onChange?.({ autoSaveInterval: Number(e.target.value) })}
            className="settings-input settings-input--number"
          />
        </SettingRow>
        <SettingRow label="Show Welcome Screen">
          <Toggle
            checked={settings.showWelcome}
            onChange={(checked) => onChange?.({ showWelcome: checked })}
          />
        </SettingRow>
      </div>
    </div>
  );
});

// ============ APPEARANCE TAB ============

const AppearanceSettingsTab = memo(function AppearanceSettingsTab() {
  const { mode, presets, currentPreset, setMode, setPreset, resetCustomColors } = useTheme();

  return (
    <div className="settings-section">
      <h3>Theme Mode</h3>
      <div className="settings-group">
        <div className="theme-mode-selector">
          {(['light', 'dark', 'system'] as ThemeMode[]).map((m) => (
            <button
              key={m}
              className={`theme-mode-option ${mode === m ? 'active' : ''}`}
              onClick={() => setMode(m)}
            >
              <span className="theme-mode-option__icon">
                {m === 'light' ? '☀️' : m === 'dark' ? '🌙' : '🖥️'}
              </span>
              <span>{m.charAt(0).toUpperCase() + m.slice(1)}</span>
            </button>
          ))}
        </div>
      </div>

      <h3>Theme Preset</h3>
      <div className="settings-group">
        <div className="theme-presets-grid">
          {presets.map((preset) => (
            <ThemePresetCard
              key={preset.id}
              preset={preset}
              isActive={currentPreset?.id === preset.id}
              onSelect={() => setPreset(preset.id)}
            />
          ))}
        </div>
      </div>

      <h3>Custom Colors</h3>
      <div className="settings-group">
        <button className="settings-btn settings-btn--secondary" onClick={resetCustomColors}>
          Reset to Preset Colors
        </button>
      </div>
    </div>
  );
});

// Theme Preset Card
interface ThemePresetCardProps {
  preset: ThemePreset;
  isActive: boolean;
  onSelect: () => void;
}

const ThemePresetCard = memo(function ThemePresetCard({
  preset,
  isActive,
  onSelect,
}: ThemePresetCardProps) {
  return (
    <button
      className={`theme-preset-card ${isActive ? 'active' : ''}`}
      onClick={onSelect}
    >
      <div className="theme-preset-card__preview">
        <div
          className="theme-preset-card__swatch"
          style={{ background: preset.colors.background }}
        >
          <div
            className="theme-preset-card__accent"
            style={{ background: preset.colors.accent }}
          />
        </div>
      </div>
      <span className="theme-preset-card__name">{preset.name}</span>
      <span className="theme-preset-card__desc">{preset.description}</span>
    </button>
  );
});

// ============ SHORTCUTS TAB ============

const ShortcutsSettingsTab = memo(function ShortcutsSettingsTab() {
  const shortcuts = [
    { category: 'Transport', items: [
      { action: 'Play/Pause', shortcut: 'Space' },
      { action: 'Stop', shortcut: '.' },
      { action: 'Rewind', shortcut: ',' },
      { action: 'Forward', shortcut: '/' },
      { action: 'Record', shortcut: 'R' },
      { action: 'Loop', shortcut: 'L' },
    ]},
    { category: 'Edit', items: [
      { action: 'Undo', shortcut: '⌘Z' },
      { action: 'Redo', shortcut: '⇧⌘Z' },
      { action: 'Cut', shortcut: '⌘X' },
      { action: 'Copy', shortcut: '⌘C' },
      { action: 'Paste', shortcut: '⌘V' },
      { action: 'Delete', shortcut: '⌫' },
    ]},
    { category: 'View', items: [
      { action: 'Toggle Left Panel', shortcut: '⌘L' },
      { action: 'Toggle Right Panel', shortcut: '⌘R' },
      { action: 'Toggle Lower Panel', shortcut: '⌘B' },
    ]},
    { category: 'File', items: [
      { action: 'New Project', shortcut: '⌘N' },
      { action: 'Open Project', shortcut: '⌘O' },
      { action: 'Save', shortcut: '⌘S' },
      { action: 'Save As', shortcut: '⇧⌘S' },
    ]},
  ];

  return (
    <div className="settings-section">
      {shortcuts.map((category) => (
        <div key={category.category}>
          <h3>{category.category}</h3>
          <div className="shortcuts-list">
            {category.items.map((item) => (
              <div key={item.action} className="shortcut-row">
                <span className="shortcut-row__action">{item.action}</span>
                <span className="shortcut-row__key">{item.shortcut}</span>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
});

// ============ ADVANCED TAB ============

interface AdvancedSettingsTabProps {
  settings: AdvancedSettings;
  onChange?: (settings: Partial<AdvancedSettings>) => void;
}

const AdvancedSettingsTab = memo(function AdvancedSettingsTab({
  settings,
  onChange,
}: AdvancedSettingsTabProps) {
  return (
    <div className="settings-section">
      <h3>Performance</h3>
      <div className="settings-group">
        <SettingRow label="Max Voices" description="Maximum concurrent audio voices">
          <input
            type="number"
            min={16}
            max={256}
            value={settings.maxVoices}
            onChange={(e) => onChange?.({ maxVoices: Number(e.target.value) })}
            className="settings-input settings-input--number"
          />
        </SettingRow>
        <SettingRow label="Worker Threads" description="Audio processing threads">
          <input
            type="number"
            min={1}
            max={8}
            value={settings.workerThreads}
            onChange={(e) => onChange?.({ workerThreads: Number(e.target.value) })}
            className="settings-input settings-input--number"
          />
        </SettingRow>
      </div>

      <h3>Debugging</h3>
      <div className="settings-group">
        <SettingRow label="Show FPS Counter">
          <Toggle
            checked={settings.showFps}
            onChange={(checked) => onChange?.({ showFps: checked })}
          />
        </SettingRow>
        <SettingRow label="Enable Profiling" description="Track performance metrics">
          <Toggle
            checked={settings.enableProfiling}
            onChange={(checked) => onChange?.({ enableProfiling: checked })}
          />
        </SettingRow>
        <SettingRow label="Enable Diagnostics" description="Detailed audio diagnostics">
          <Toggle
            checked={settings.enableDiagnostics}
            onChange={(checked) => onChange?.({ enableDiagnostics: checked })}
          />
        </SettingRow>
      </div>
    </div>
  );
});

// ============ HELPER COMPONENTS ============

interface SettingRowProps {
  label: string;
  description?: string;
  children: React.ReactNode;
}

const SettingRow = memo(function SettingRow({
  label,
  description,
  children,
}: SettingRowProps) {
  return (
    <div className="setting-row">
      <div className="setting-row__label">
        <span>{label}</span>
        {description && <span className="setting-row__desc">{description}</span>}
      </div>
      <div className="setting-row__control">{children}</div>
    </div>
  );
});

interface ToggleProps {
  checked: boolean;
  onChange: (checked: boolean) => void;
}

const Toggle = memo(function Toggle({ checked, onChange }: ToggleProps) {
  return (
    <button
      className={`settings-toggle ${checked ? 'active' : ''}`}
      onClick={() => onChange(!checked)}
    >
      <div className="settings-toggle__track">
        <div className="settings-toggle__thumb" />
      </div>
    </button>
  );
});

export default SettingsPanel;
