/**
 * Component Showcase Demo
 *
 * Demonstrates all ReelForge UI components in one page:
 * - Core Systems (Undo, Theme, Project, Shortcuts)
 * - UI Components (Mixer, Settings, Loading States)
 * - Polish (Tooltips, Drag & Drop)
 *
 * Access via: ?layout=showcase
 *
 * @module demo/ComponentShowcase
 */

import { useState, useCallback, useEffect } from 'react';

// Core systems
import { useTheme } from '../core/themeSystem';
import { useUndo, UndoManager } from '../core/undoSystem';
import { shortcuts } from '../core/keyboardShortcuts';
import { useDragState, DragDropManager, type DragItem } from '../core/dragDropSystem';

// UI Components
import {
  UndoRedoButtons,
  ThemeToggle,
  MasterMeter,
  ProjectStatus,
} from '../components/ToolbarIntegrations';
import { MixerPanel, type BusChannel } from '../components/MixerPanel';
import { SettingsPanel, type GeneralSettings, type AdvancedSettings } from '../components/SettingsPanel';
import { RecentProjectsPanel } from '../components/RecentProjectsPanel';
import {
  Spinner,
  ProgressBar,
  LoadingButton,
  SkeletonCard,
  EmptyState,
} from '../components/LoadingStates';
import { Tooltip } from '../components/Tooltip';

import './ComponentShowcase.css';

// ============ Demo Data ============

const DEMO_BUSES: BusChannel[] = [
  { id: 'master', name: 'Master', color: '#ffffff', volume: 0.85, pan: 0, muted: false, solo: false },
  { id: 'music', name: 'Music', color: '#22c55e', volume: 0.7, pan: 0, muted: false, solo: false },
  { id: 'sfx', name: 'SFX', color: '#3b82f6', volume: 0.9, pan: 0, muted: false, solo: false },
  { id: 'voice', name: 'Voice', color: '#f59e0b', volume: 0.8, pan: 0, muted: false, solo: false },
  { id: 'ambience', name: 'Ambience', color: '#a855f7', volume: 0.5, pan: 0, muted: false, solo: false },
];

const DEMO_ASSETS = [
  { id: 'spin_start', name: 'Spin Start', type: 'sfx' },
  { id: 'spin_loop', name: 'Spin Loop', type: 'sfx' },
  { id: 'reel_stop_1', name: 'Reel Stop 1', type: 'sfx' },
  { id: 'reel_stop_2', name: 'Reel Stop 2', type: 'sfx' },
  { id: 'win_small', name: 'Win Small', type: 'sfx' },
  { id: 'win_big', name: 'Win Big', type: 'music' },
  { id: 'jackpot', name: 'Jackpot', type: 'music' },
  { id: 'base_loop', name: 'Base Game Loop', type: 'music' },
  { id: 'freespin_loop', name: 'Free Spin Loop', type: 'music' },
];

const DEFAULT_GENERAL_SETTINGS: GeneralSettings = {
  projectName: 'Demo Project',
  author: 'Demo User',
  sampleRate: 48000,
  bufferSize: 512,
  autoSaveInterval: 60,
  showWelcome: true,
};

const DEFAULT_ADVANCED_SETTINGS: AdvancedSettings = {
  enableProfiling: false,
  enableDiagnostics: true,
  maxVoices: 32,
  workerThreads: 4,
  showFps: false,
};

// ============ Section Components ============

function ShowcaseSection({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="showcase-section">
      <div className="showcase-section__header">
        <h2>{title}</h2>
        {description && <p>{description}</p>}
      </div>
      <div className="showcase-section__content">{children}</div>
    </section>
  );
}

// ============ Demo Panels ============

function ThemeDemo() {
  const theme = useTheme();

  return (
    <div className="demo-card">
      <h3>Theme System</h3>
      <div className="demo-row">
        <ThemeToggle />
        <span className="demo-label">Current: {theme.effectiveMode}</span>
      </div>
      <div className="demo-row">
        <label>Preset:</label>
        <select
          value={theme.preset}
          onChange={(e) => theme.setPreset(e.target.value)}
          className="demo-select"
        >
          {theme.presets.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name}
            </option>
          ))}
        </select>
      </div>
      <div className="demo-colors">
        {(['accentPrimary', 'accentSuccess', 'accentWarning', 'accentError'] as const).map(
          (key) => (
            <div
              key={key}
              className="demo-color-swatch"
              style={{ background: theme.colors[key] }}
              title={key}
            />
          )
        )}
      </div>
    </div>
  );
}

function UndoDemo() {
  const undo = useUndo();
  const [counter, setCounter] = useState(0);

  const increment = useCallback(() => {
    const oldValue = counter;
    const newValue = counter + 1;
    UndoManager.execute({
      id: `counter-${Date.now()}`,
      timestamp: Date.now(),
      execute: () => setCounter(newValue),
      undo: () => setCounter(oldValue),
      description: `Set counter to ${newValue}`,
    });
  }, [counter]);

  return (
    <div className="demo-card">
      <h3>Undo/Redo System</h3>
      <div className="demo-row">
        <UndoRedoButtons />
      </div>
      <div className="demo-row">
        <span className="demo-counter">{counter}</span>
        <button className="demo-button" onClick={increment}>
          Increment (+1)
        </button>
      </div>
      <div className="demo-info">
        History: {undo.undoCount} | Can undo: {undo.canUndo ? 'Yes' : 'No'}
      </div>
    </div>
  );
}

function ShortcutsDemo() {
  const [lastAction, setLastAction] = useState<string>('None');

  // Register demo shortcuts via useEffect
  useEffect(() => {
    const unsub1 = shortcuts.register('playback.play', () => {
      setLastAction('Space pressed - Play/Pause');
    });
    const unsub2 = shortcuts.register('edit.undo', () => {
      setLastAction('Ctrl+Z pressed - Undo');
    });

    return () => {
      unsub1();
      unsub2();
    };
  }, []);

  // Get shortcuts count once (not reactive to avoid infinite loop)
  const shortcutCount = shortcuts.getAllShortcuts().length;

  return (
    <div className="demo-card">
      <h3>Keyboard Shortcuts</h3>
      <div className="demo-shortcuts-list">
        <div className="demo-shortcut">
          <kbd>Space</kbd> Play/Pause
        </div>
        <div className="demo-shortcut">
          <kbd>{shortcuts.formatBinding({ key: 'z', modifiers: ['meta'] })}</kbd> Undo
        </div>
        <div className="demo-shortcut">
          <kbd>{shortcuts.formatBinding({ key: 'z', modifiers: ['meta', 'shift'] })}</kbd> Redo
        </div>
        <div className="demo-shortcut">
          <kbd>{shortcuts.formatBinding({ key: 's', modifiers: ['meta'] })}</kbd> Save
        </div>
      </div>
      <div className="demo-info">
        Last action: {lastAction} | Total shortcuts: {shortcutCount}
      </div>
    </div>
  );
}

function DragDropDemo() {
  const dragState = useDragState();
  const [droppedItems, setDroppedItems] = useState<string[]>([]);

  const handleDragStart = (item: typeof DEMO_ASSETS[0]) => (e: React.MouseEvent) => {
    const dragItem: DragItem = {
      type: 'audio-asset',
      id: item.id,
      label: item.name,
      data: { assetType: item.type },
    };
    DragDropManager.startDrag(dragItem, e.nativeEvent);
  };

  useEffect(() => {
    const unsub = DragDropManager.subscribe((event) => {
      if (event.type === 'drop' && event.item) {
        setDroppedItems((prev) => [...prev.slice(-4), event.item!.label]);
      }
    });
    return unsub;
  }, []);

  return (
    <div className="demo-card demo-card--wide">
      <h3>Drag & Drop</h3>
      <div className="demo-dnd-container">
        <div className="demo-dnd-source">
          <h4>Assets (drag me)</h4>
          {DEMO_ASSETS.slice(0, 5).map((asset) => (
            <div
              key={asset.id}
              className="demo-dnd-item"
              onMouseDown={handleDragStart(asset)}
            >
              {asset.type === 'music' ? '🎵' : '🔊'} {asset.name}
            </div>
          ))}
        </div>
        <div className="demo-dnd-target">
          <h4>Drop Zone</h4>
          {droppedItems.length === 0 ? (
            <div className="demo-dnd-empty">Drop assets here</div>
          ) : (
            droppedItems.map((item, i) => (
              <div key={i} className="demo-dnd-dropped">
                ✓ {item}
              </div>
            ))
          )}
        </div>
      </div>
      <div className="demo-info">
        Dragging: {dragState.isDragging ? dragState.currentItem?.label : 'None'}
      </div>
    </div>
  );
}

function LoadingStatesDemo() {
  const [loading, setLoading] = useState(false);
  const [progress, setProgress] = useState(45);

  const simulateLoad = () => {
    setLoading(true);
    setTimeout(() => setLoading(false), 2000);
  };

  return (
    <div className="demo-card demo-card--wide">
      <h3>Loading States</h3>
      <div className="demo-loading-grid">
        <div className="demo-loading-item">
          <Spinner size="sm" />
          <span>Small</span>
        </div>
        <div className="demo-loading-item">
          <Spinner size="md" />
          <span>Medium</span>
        </div>
        <div className="demo-loading-item">
          <Spinner size="lg" />
          <span>Large</span>
        </div>
      </div>

      <div className="demo-row">
        <label>Progress: {progress}%</label>
        <input
          type="range"
          min={0}
          max={100}
          value={progress}
          onChange={(e) => setProgress(Number(e.target.value))}
        />
      </div>
      <ProgressBar value={progress} showLabel />

      <div className="demo-row" style={{ marginTop: 16 }}>
        <LoadingButton loading={loading} onClick={simulateLoad}>
          {loading ? 'Loading...' : 'Click to Load'}
        </LoadingButton>
      </div>

      <div className="demo-skeleton-row">
        <SkeletonCard />
        <SkeletonCard />
      </div>
    </div>
  );
}

function TooltipDemo() {
  return (
    <div className="demo-card">
      <h3>Tooltips</h3>
      <div className="demo-tooltip-grid">
        <Tooltip content="This is a tooltip!" position="top">
          <button className="demo-button">Hover (top)</button>
        </Tooltip>
        <Tooltip content="Bottom tooltip" position="bottom">
          <button className="demo-button">Hover (bottom)</button>
        </Tooltip>
        <Tooltip content="Play/Pause" shortcut="Space" position="top">
          <button className="demo-button">With Shortcut</button>
        </Tooltip>
        <Tooltip content="Save Project" shortcut="Ctrl+S" position="top">
          <button className="demo-button">Save</button>
        </Tooltip>
      </div>
    </div>
  );
}

function MeterDemo() {
  return (
    <div className="demo-card">
      <h3>Master Meter</h3>
      <div className="demo-meter-container">
        <MasterMeter />
      </div>
      <div className="demo-info">Simulated audio levels (not connected to real audio)</div>
    </div>
  );
}

function ProjectDemo() {
  return (
    <div className="demo-card">
      <h3>Project Status</h3>
      <ProjectStatus projectName="Demo Project" />
      <div className="demo-info" style={{ marginTop: 12 }}>
        Tracks unsaved changes and auto-save status
      </div>
    </div>
  );
}

function EmptyStateDemo() {
  return (
    <div className="demo-card demo-card--wide">
      <h3>Empty States</h3>
      <div className="demo-empty-grid">
        <EmptyState
          icon="📁"
          title="No Projects"
          description="Create a new project to get started"
          action={{ label: 'New Project', onClick: () => console.log('New project') }}
        />
        <EmptyState
          icon="🔍"
          title="No Results"
          description="Try adjusting your search filters"
        />
      </div>
    </div>
  );
}

// ============ Main Component ============

export function ComponentShowcase() {
  const [activePanel, setActivePanel] = useState<'mixer' | 'settings' | 'recent' | null>(null);
  const [buses, setBuses] = useState(DEMO_BUSES);
  const [generalSettings, setGeneralSettings] = useState(DEFAULT_GENERAL_SETTINGS);
  const [advancedSettings, setAdvancedSettings] = useState(DEFAULT_ADVANCED_SETTINGS);

  const handleVolumeChange = useCallback((busId: string, volume: number) => {
    setBuses((prev) =>
      prev.map((b) => (b.id === busId ? { ...b, volume } : b))
    );
  }, []);

  const handleMuteToggle = useCallback((busId: string) => {
    setBuses((prev) =>
      prev.map((b) => (b.id === busId ? { ...b, muted: !b.muted } : b))
    );
  }, []);

  const handleSoloToggle = useCallback((busId: string) => {
    setBuses((prev) =>
      prev.map((b) => (b.id === busId ? { ...b, solo: !b.solo } : b))
    );
  }, []);

  return (
    <div className="component-showcase">
      {/* Header */}
      <header className="showcase-header">
        <div className="showcase-header__left">
          <h1>ReelForge Component Showcase</h1>
          <span className="showcase-version">v1.0.0</span>
        </div>
        <div className="showcase-header__right">
          <ThemeToggle />
          <UndoRedoButtons />
        </div>
      </header>

      {/* Navigation */}
      <nav className="showcase-nav">
        <button
          className={`showcase-nav__btn ${activePanel === 'mixer' ? 'active' : ''}`}
          onClick={() => setActivePanel(activePanel === 'mixer' ? null : 'mixer')}
        >
          🎚️ Mixer Panel
        </button>
        <button
          className={`showcase-nav__btn ${activePanel === 'settings' ? 'active' : ''}`}
          onClick={() => setActivePanel(activePanel === 'settings' ? null : 'settings')}
        >
          ⚙️ Settings Panel
        </button>
        <button
          className={`showcase-nav__btn ${activePanel === 'recent' ? 'active' : ''}`}
          onClick={() => setActivePanel(activePanel === 'recent' ? null : 'recent')}
        >
          📂 Recent Projects
        </button>
      </nav>

      {/* Panels */}
      {activePanel === 'mixer' && (
        <div className="showcase-panel">
          <MixerPanel
            buses={buses}
            onVolumeChange={handleVolumeChange}
            onMuteToggle={handleMuteToggle}
            onSoloToggle={handleSoloToggle}
          />
        </div>
      )}

      {activePanel === 'settings' && (
        <div className="showcase-panel showcase-panel--centered">
          <SettingsPanel
            generalSettings={generalSettings}
            advancedSettings={advancedSettings}
            onGeneralChange={(changes) => setGeneralSettings((prev) => ({ ...prev, ...changes }))}
            onAdvancedChange={(changes) => setAdvancedSettings((prev) => ({ ...prev, ...changes }))}
            onClose={() => setActivePanel(null)}
          />
        </div>
      )}

      {activePanel === 'recent' && (
        <div className="showcase-panel showcase-panel--centered">
          <RecentProjectsPanel
            onNewProject={(name) => {
              console.log('New project:', name);
              setActivePanel(null);
            }}
            onOpenProject={(project) => {
              console.log('Open project:', project.metadata.name);
              setActivePanel(null);
            }}
            onImportProject={() => {
              console.log('Import project');
            }}
          />
        </div>
      )}

      {/* Main Content */}
      <main className="showcase-content">
        {/* Core Systems */}
        <ShowcaseSection
          title="Core Systems"
          description="Fundamental systems powering the editor"
        >
          <div className="showcase-grid">
            <ThemeDemo />
            <UndoDemo />
            <ShortcutsDemo />
            <ProjectDemo />
          </div>
        </ShowcaseSection>

        {/* UI Components */}
        <ShowcaseSection
          title="UI Components"
          description="Interactive components for the editor interface"
        >
          <div className="showcase-grid">
            <MeterDemo />
            <TooltipDemo />
            <DragDropDemo />
          </div>
        </ShowcaseSection>

        {/* Loading & Empty States */}
        <ShowcaseSection
          title="Loading & Empty States"
          description="Feedback components for async operations"
        >
          <div className="showcase-grid">
            <LoadingStatesDemo />
            <EmptyStateDemo />
          </div>
        </ShowcaseSection>
      </main>

      {/* Footer */}
      <footer className="showcase-footer">
        <span>ReelForge Audio Middleware Editor</span>
        <span>|</span>
        <span>Press ? for keyboard shortcuts</span>
        <span>|</span>
        <span>Built with React + TypeScript</span>
      </footer>
    </div>
  );
}

export default ComponentShowcase;
