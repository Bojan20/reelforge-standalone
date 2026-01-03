/**
 * Layout Demo Page - Production Version
 *
 * Professional DAW-style UI with REAL project data:
 * - Detachable/floating panels
 * - Timeline with waveforms
 * - Layered music editor
 * - Full mixer
 * - Command system integration
 * - Project/Event management
 *
 * Uses hooks from EventsPage for real functionality
 */

import { useState, useCallback, useMemo, useEffect, useRef } from 'react';
import {
  MainLayout,
  type TreeNode,
  type InspectorSection,
  type LowerZoneTab,
  type TabGroup,
  TextField,
  SliderField,
  SelectField,
  CheckboxField,
  MixerStrip,
  type InsertSlot,
  ConsolePanel,
  type ConsoleMessage,
  DockablePanel,
  usePanelManager,
  Timeline,
  type TimelineTrack,
  type TimelineClip,
  type Crossfade,
  LayeredMusicEditor,
  type MusicLayer,
  type BlendCurve,
  type MusicState,
  type ChannelStripData,
  createEmptyInserts,
  createEmptySends,
  ClipEditor,
  type ClipEditorClip,
} from './layout';

// Slot components
import {
  SpinCycleEditor,
  generateDemoSpinCycleConfig,
  type SpinState,
  type SpinCycleConfig,
  WinTierEditor,
  generateDemoWinTiers,
  type WinTier,
  type WinTierConfig,
  ReelStopSequencer,
  generateDemoReelConfig,
  type ReelConfig,
} from './layout/slot';

// Project integration - use RoutesConfig types for compatibility with ProjectContext
import { useProject } from './project/ProjectContext';
import type { EventRoute, RouteAction, RouteBus, RoutesConfig } from './core/routesTypes';
import { validateRoutes } from './core/validateRoutes';
import {
  isPlayAction,
  isStopAction,
  isFadeAction,
  isPauseAction,
  isSetBusGainAction,
  isStopAllAction,
  isExecuteAction,
  createDefaultPlayAction,
  createDefaultStopAction,
  createDefaultFadeAction,
  createDefaultPauseAction,
  createDefaultSetBusGainAction,
  createDefaultStopAllAction,
  createDefaultExecuteAction,
} from './core/routesTypes';

// Audio preview
// Preview executor hook available if needed for mix state tracking
// import { usePreviewExecutor, type ExecutableCommand } from './hooks/usePreviewExecutor';

// Inline number input with drag support
import { NumberInput } from './number-input/NumberInput';

// Audio asset picker with fuzzy matching
import AudioAssetPicker, { type AudioAssetOption } from './components/AudioAssetPicker';

// Validation panel
import ValidationPanel from './components/ValidationPanel';

// Audio Features panel
import AudioFeaturesPanel from './components/AudioFeaturesPanel';

// Professional Features panel
import ProFeaturesPanel from './components/ProFeaturesPanel';

// Slot Audio Studio - Revolutionary slot-focused UI
import SlotAudioStudio from './components/SlotAudioStudio';

// DSP Panels
import SidechainRouterPanel from './components/SidechainRouterPanel';
import MultibandCompressorPanel from './components/MultibandCompressorPanel';
import SlotFXPresetsPanel from './components/SlotFXPresetsPanel';

// Bus meter hook
import { useBusMeter, useSimulatedBusMeter } from './hooks/useBusMeter';

// Timeline playback - connects clips to real audio
import { useTimelinePlayback, type TimelineClipData } from './hooks/useTimelinePlayback';

// Global keyboard shortcuts for DAW
import { useGlobalShortcuts } from './hooks/useGlobalShortcuts';

// Debug logging (conditional - only in dev or when RF_DEBUG enabled)
import { rfDebug } from './core/dspMetrics';

// Audio analysis (BPM detection)
import { analyzeAudioLoop } from './core/advancedLoopAnalyzer';

// Shared AudioContext singleton
import { AudioContextManager } from './core/AudioContextManager';

// Extracted demo panels
import { DragDropLabPanel, LoadingStatesPanel } from './components/DemoPanels';

// Cubase-style Audio Import Components
import AudioBrowser, { type AudioFileInfo } from './components/AudioBrowser';
import ImportOptionsDialog, { type ImportOptions, type FileToImport } from './components/ImportOptionsDialog';
import AudioPoolPanel, { type PoolAsset } from './components/AudioPoolPanel';

// Audio buffer encoding - creates valid WAV for blob URLs
import { createAudioBlobUrl } from './utils/audioBufferToWav';
import { resampleAudioBuffer, needsSampleRateConversion, formatSampleRate, DEFAULT_PROJECT_SAMPLE_RATE } from './utils/sampleRateConversion';

// ============ Mixer Tab Component ============
// This is a separate component so it has its own render cycle for meter animation
// Parent useMemo won't block meter updates
interface MixerTabContentProps {
  busStates: BusState[];
  isPlaying: boolean;
  selectedBusId: string | null;
  onSelectBus: (id: string) => void;
  onVolumeChange: (busId: string, volume: number) => void;
  onPanChange: (busId: string, pan: number) => void;
  onMuteToggle: (busId: string) => void;
  onSoloToggle: (busId: string) => void;
  onInsertClick: (busId: string, idx: number, insert: InsertSlot | null, event?: React.MouseEvent) => void;
  onInsertBypass: (busId: string, idx: number, insert: InsertSlot) => void;
  onAudioDrop: (busId: string, item: DragItem) => void;
  /** AudioContext for real-time metering */
  audioContext: AudioContext | null;
  /** Bus gain nodes for real-time metering */
  busGains: Record<string, GainNode>;
}

function MixerTabContent({
  busStates,
  isPlaying,
  selectedBusId,
  onSelectBus,
  onVolumeChange,
  onPanChange,
  onMuteToggle,
  onSoloToggle,
  onInsertClick,
  onInsertBypass,
  onAudioDrop,
  audioContext,
  busGains,
}: MixerTabContentProps) {
  // Create meter config from actual bus gain nodes
  const meterConfig = useMemo(() => {
    return busStates.map(bus => ({
      id: bus.id,
      sourceNode: busGains[bus.id] || undefined,
    }));
  }, [busStates, busGains]);

  // Use real bus meters when we have audio nodes, otherwise simulated
  const realMeterLevels = useBusMeter(audioContext, meterConfig);

  // Fallback simulated config for when no audio is playing
  const busConfigForSimulated = useMemo(() =>
    busStates.map(b => ({ id: b.id, volume: b.volume, muted: b.muted })),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [busStates.map(b => `${b.id}:${b.volume}:${b.muted}`).join(',')]
  );
  const simulatedMeterLevels = useSimulatedBusMeter(busConfigForSimulated, isPlaying);

  // Use real meters when audio context is active, otherwise simulated
  const meterLevels = audioContext && audioContext.state === 'running' ? realMeterLevels : simulatedMeterLevels;

  return (
    <div className="rf-mixer">
      {busStates.map((bus) => {
        const meterState = meterLevels.get(bus.id);
        const meterLevel = meterState?.peak ?? 0;
        // Use RMS for right channel - smoother than random
        const meterLevelR = meterState?.rms ? meterState.rms * 1.2 : meterLevel * 0.95;
        return (
          <MixerStrip
            key={bus.id}
            id={bus.id}
            name={bus.name}
            isMaster={bus.id === 'master'}
            volume={bus.volume}
            pan={bus.pan}
            muted={bus.muted}
            soloed={bus.soloed}
            meterLevel={meterLevel}
            meterLevelR={meterLevelR}
            peakHold={meterState?.peakHold}
            inserts={bus.inserts}
            selected={selectedBusId === bus.id}
            onSelect={() => onSelectBus(bus.id)}
            onVolumeChange={(v) => onVolumeChange(bus.id, v)}
            onPanChange={bus.id !== 'master' ? (p) => onPanChange(bus.id, p) : undefined}
            onMuteToggle={() => onMuteToggle(bus.id)}
            onSoloToggle={() => onSoloToggle(bus.id)}
            onInsertClick={(idx, insert, event) => onInsertClick(bus.id, idx, insert, event)}
            onInsertBypass={(idx, insert) => onInsertBypass(bus.id, idx, insert)}
            onAudioDrop={(item) => onAudioDrop(bus.id, item)}
          />
        );
      })}
    </div>
  );
}

// Professional feature integrations
import { useUndo, UndoManager, setupUndoKeyboardShortcuts } from './core/undoSystem';
import { useEditorMode } from './hooks/useEditorMode';
import { filterTabGroupsForMode, filterTabsForMode, getDefaultTabForMode } from './layout/editorModeConfig';
import { ThemeToggle, UndoRedoButtons } from './components/ToolbarIntegrations';
import { Tooltip } from './components/Tooltip';
import { type DragItem } from './core/dragDropSystem';
import PluginPicker, { type PluginDefinition } from './components/PluginPicker';
import { useInsertSelection, type InsertSelection } from './plugin';
import { shouldOpenInWindow } from './plugin/usePluginWindow';
import { getPluginDefinition } from './plugin/pluginRegistry';
import { MasterInsertProvider } from './core/MasterInsertContext';
import { masterInsertDSP } from './core/masterInsertDSP';
import { useMasterInserts } from './store';
import { useTracks, useClips } from './store/useProjectStore';
import type { ClipState } from './store/projectStore';
import { useReelForgeStore } from './store/reelforgeStore';

// ============ Demo Data ============

// Bus insert slot type - extended to support all plugin categories
interface BusInsertSlot {
  id: string;
  name: string;
  type: 'eq' | 'comp' | 'reverb' | 'delay' | 'filter' | 'fx' | 'utility' | 'custom';
  bypassed?: boolean;
}

// Bus state type
interface BusState {
  id: string;
  name: string;
  volume: number;
  pan: number;
  muted: boolean;
  soloed: boolean;
  meterLevel: number;
  inserts: BusInsertSlot[];
  isMaster?: boolean;
}

const DEMO_BUSES: BusState[] = [
  { id: 'sfx', name: 'SFX', volume: 1, pan: 0, muted: false, soloed: false, meterLevel: 0, inserts: [] },
  { id: 'music', name: 'Music', volume: 0.8, pan: 0, muted: false, soloed: false, meterLevel: 0, inserts: [] },
  { id: 'voice', name: 'Voice', volume: 1, pan: 0, muted: false, soloed: false, meterLevel: 0, inserts: [] },
  { id: 'ambient', name: 'Ambient', volume: 0.7, pan: 0, muted: false, soloed: false, meterLevel: 0, inserts: [] },
  { id: 'master', name: 'Master', volume: 1, pan: 0, muted: false, soloed: false, meterLevel: 0, isMaster: true, inserts: [] },
];

// Color palette for auto-generated tracks
const TRACK_COLORS = [
  '#e74c3c', '#9b59b6', '#3498db', '#2ecc71', '#f39c12',
  '#1abc9c', '#e67e22', '#c0392b', '#8e44ad', '#27ae60',
];

// ============ Session Storage Keys ============
const STORAGE_KEYS = {
  SESSION: 'reelforge_session',
  AUDIO_META: 'reelforge_audio_meta',
} as const;

// Audio storage is in utils/audioStorage.ts
import { saveAudioToDB, loadAudioFromDB, clearAudioDB, type StoredAudioFile } from './utils/audioStorage';

interface SessionState {
  selectedEventName: string | null;
  selectedActionIndex: number | null;
  activeLowerTab: string;
  routes: unknown | null;
  timestamp: number;
}

interface AudioFileMeta {
  id: string;
  name: string;
  duration: number;
  waveform: number[];
  // Note: File and AudioBuffer cannot be serialized
}

// Demo panels moved to ./components/DemoPanels.tsx

// ============ Main Component ============

export interface LayoutDemoProps {
  /** Initial audio files imported from welcome screen */
  initialImportedFiles?: File[];
}

export function LayoutDemo({ initialImportedFiles }: LayoutDemoProps) {
  // Debug log removed - was causing console spam during meter animation

  // ===== PROJECT INTEGRATION =====
  const {
    workingRoutes,
    setWorkingRoutes,
    project: projectFile,
    openProject,
    saveProject,
    saveProjectAs,
    newProject,
    isDirty,
  } = useProject();

  // ===== UNDO/REDO INTEGRATION =====
  const { canUndo, canRedo, undo, redo } = useUndo();

  // ===== EDITOR MODE =====
  const { mode: editorMode, setMode: setEditorMode } = useEditorMode();

  // ===== PLUGIN WINDOW INTEGRATION =====
  const { selectInsert, setCallbacks } = useInsertSelection();

  // ===== MASTER INSERT CHAIN (Zustand) =====
  // This connects master bus inserts to the DSP chain
  const {
    addInsert: addMasterInsert,
    removeInsert: removeMasterInsert,
    toggleBypass: toggleMasterBypass,
    updateParams: updateMasterParams,
  } = useMasterInserts();

  // Initialize state from localStorage if available
  const getInitialSession = (): Partial<SessionState> => {
    try {
      const saved = localStorage.getItem(STORAGE_KEYS.SESSION);
      if (saved) {
        const parsed = JSON.parse(saved) as SessionState;
        // Check if session is less than 24 hours old
        if (Date.now() - parsed.timestamp < 24 * 60 * 60 * 1000) {
          return parsed;
        }
      }
    } catch { /* ignore */ }
    return {};
  };

  const initialSession = getInitialSession();

  const [selectedEventName, setSelectedEventName] = useState<string | null>(
    initialSession.selectedEventName ?? null
  );
  const [selectedActionIndex, setSelectedActionIndex] = useState<number | null>(
    initialSession.selectedActionIndex ?? null
  );

  // Drag and drop state for action reordering
  const [draggedActionIndex, setDraggedActionIndex] = useState<number | null>(null);
  const [dragOverIndex, setDragOverIndex] = useState<number | null>(null);

  // Multi-select state for bulk operations
  const [selectedActionIndices, setSelectedActionIndices] = useState<Set<number>>(new Set());

  // Overlap mode - when false, stop all audio before playing new event
  const [allowOverlap, setAllowOverlap] = useState(false);

  // Audio context - use shared singleton to avoid multiple context overhead
  // This ensures MasterInsertDSP gets valid objects on first render
  const audioContext = useMemo(() => {
    const ctx = AudioContextManager.getContext();
    rfDebug('Audio', 'AudioContext obtained, state:', ctx.state, 'sampleRate:', ctx.sampleRate);
    return ctx;
  }, []);

  const masterGain = useMemo(() => {
    const gain = audioContext.createGain();
    gain.gain.value = 1;
    // Connect to destination initially - MasterInsertDSP will rewire this
    gain.connect(audioContext.destination);
    rfDebug('Audio', 'masterGain connected to destination');
    return gain;
  }, [audioContext]);

  // Bus GainNodes - route through master bus for proper mixing
  // All buses feed into masterGain (except master which IS masterGain)
  // Chain: source → busGain → busPanner → masterGain → destination
  const busGains = useMemo(() => {
    const gains: Record<string, GainNode> = {};
    // Create gain nodes for each bus defined in DEMO_BUSES
    for (const bus of DEMO_BUSES) {
      if (bus.isMaster) {
        // Master bus uses the masterGain directly
        gains[bus.id] = masterGain;
      } else {
        // Other buses create their own gain and connect to master
        const busGain = audioContext.createGain();
        busGain.gain.value = bus.volume;
        busGain.connect(masterGain);
        gains[bus.id] = busGain;
        rfDebug('Audio', `Bus ${bus.id} gain created, connected to master`);
      }
    }
    return gains;
  }, [audioContext, masterGain]);

  // Bus Panners - StereoPanner for each non-master bus
  const busPanners = useMemo(() => {
    const panners: Record<string, StereoPannerNode> = {};
    for (const bus of DEMO_BUSES) {
      if (!bus.isMaster) {
        const panner = audioContext.createStereoPanner();
        panner.pan.value = bus.pan;
        // Reconnect: busGain → panner → masterGain
        const busGain = busGains[bus.id];
        if (busGain) {
          busGain.disconnect();
          busGain.connect(panner);
          panner.connect(masterGain);
        }
        panners[bus.id] = panner;
        rfDebug('Audio', `Bus ${bus.id} panner created`);
      }
    }
    return panners;
  }, [audioContext, masterGain, busGains]);

  // Keep refs for backward compatibility with existing code
  const audioContextRef = useRef<AudioContext | null>(audioContext);
  const masterGainRef = useRef<GainNode | null>(masterGain);
  const busGainsRef = useRef<Record<string, GainNode>>(busGains);
  const busPannersRef = useRef<Record<string, StereoPannerNode>>(busPanners);
  busPannersRef.current = busPanners;
  audioContextRef.current = audioContext;
  masterGainRef.current = masterGain;
  busGainsRef.current = busGains;

  // Active voice tracking - includes source AND gainNode for fade control
  interface ActiveVoice {
    source: AudioBufferSourceNode;
    gainNode: GainNode;
  }
  // Map of assetId → array of active voices (supports overlapping playback)
  const activeSourcesRef = useRef<Map<string, ActiveVoice[]>>(new Map());

  // Derived state from workingRoutes
  const routes = workingRoutes;
  const selectedEvent = routes?.events?.find(e => e.name === selectedEventName) || null;
  const selectedAction = selectedEvent && selectedActionIndex !== null
    ? selectedEvent.actions[selectedActionIndex]
    : null;

  // ===== SESSION PERSISTENCE =====

  // Restore routes from session on first load (only if no routes exist)
  const sessionRestoredRef = useRef(false);
  useEffect(() => {
    if (sessionRestoredRef.current) return;
    sessionRestoredRef.current = true;

    // If we already have routes from ProjectContext, don't override
    if (workingRoutes?.events?.length) return;

    // Try to restore routes from session
    if (initialSession.routes) {
      try {
        // Cast to RoutesConfig - session data has same structure
        const restoredRoutes = initialSession.routes as import('./core/routesTypes').RoutesConfig;
        if (restoredRoutes && restoredRoutes.events) {
          setWorkingRoutes(restoredRoutes);
          rfDebug('Session', 'Restored routes from localStorage');
        }
      } catch (err) {
        console.warn('[Session] Failed to restore routes:', err);
      }
    }
  }, [initialSession.routes, workingRoutes, setWorkingRoutes]);

  // Setup global undo/redo keyboard shortcuts (Cmd+Z, Cmd+Shift+Z)
  useEffect(() => {
    return setupUndoKeyboardShortcuts();
  }, []);

  // Warn before leaving if there are unsaved changes
  useEffect(() => {
    const handleBeforeUnload = (e: BeforeUnloadEvent) => {
      if (isDirty) {
        e.preventDefault();
        e.returnValue = 'You have unsaved changes. Are you sure you want to leave?';
        return e.returnValue;
      }
    };

    window.addEventListener('beforeunload', handleBeforeUnload);
    return () => window.removeEventListener('beforeunload', handleBeforeUnload);
  }, [isDirty]);

  // Load first event on mount (if no selection restored from session)
  useEffect(() => {
    if (routes?.events?.length && !selectedEventName) {
      setSelectedEventName(routes.events[0].name);
    }
  }, [routes, selectedEventName]);

  // ===== EVENT CRUD =====
  const handleAddEvent = useCallback(() => {
    if (!routes) return;
    const newName = prompt('Enter new event name:');
    if (!newName) return;

    const newEvent: EventRoute = { name: newName, actions: [] };
    setWorkingRoutes({
      ...routes,
      events: [...routes.events, newEvent],
    });
    setSelectedEventName(newName);
  }, [routes, setWorkingRoutes]);


  // ===== ACTION CRUD =====
  const handleAddAction = useCallback((actionType: RouteAction['type'] = 'Play') => {
    if (!routes || !selectedEventName) return;

    let newAction: RouteAction;
    switch (actionType) {
      case 'Play':
        newAction = createDefaultPlayAction(routes.defaultBus);
        break;
      case 'Stop':
        newAction = createDefaultStopAction();
        break;
      case 'Fade':
        newAction = createDefaultFadeAction();
        break;
      case 'Pause':
        newAction = createDefaultPauseAction();
        break;
      case 'SetBusGain':
        newAction = createDefaultSetBusGainAction();
        break;
      case 'StopAll':
        newAction = createDefaultStopAllAction();
        break;
      case 'Execute':
        newAction = createDefaultExecuteAction();
        break;
      default:
        newAction = createDefaultPlayAction(routes.defaultBus);
    }

    setWorkingRoutes({
      ...routes,
      events: routes.events.map(e =>
        e.name === selectedEventName
          ? { ...e, actions: [...e.actions, newAction] }
          : e
      ),
    });
    setSelectedActionIndex(selectedEvent ? selectedEvent.actions.length : 0);
  }, [routes, selectedEventName, selectedEvent, setWorkingRoutes]);

  const handleDeleteAction = useCallback((actionIndex: number) => {
    if (!routes || !selectedEventName) return;

    setWorkingRoutes({
      ...routes,
      events: routes.events.map(e =>
        e.name === selectedEventName
          ? { ...e, actions: e.actions.filter((_, i) => i !== actionIndex) }
          : e
      ),
    });
    if (selectedActionIndex === actionIndex) {
      setSelectedActionIndex(null);
    }
  }, [routes, selectedEventName, selectedActionIndex, setWorkingRoutes]);

  const handleDuplicateAction = useCallback((actionIndex: number) => {
    if (!routes || !selectedEventName || !selectedEvent) return;

    const actionToDuplicate = selectedEvent.actions[actionIndex];
    if (!actionToDuplicate) return;

    setWorkingRoutes({
      ...routes,
      events: routes.events.map(e =>
        e.name === selectedEventName
          ? {
              ...e,
              actions: [
                ...e.actions.slice(0, actionIndex + 1),
                { ...actionToDuplicate },
                ...e.actions.slice(actionIndex + 1),
              ],
            }
          : e
      ),
    });
    setSelectedActionIndex(actionIndex + 1);
  }, [routes, selectedEventName, selectedEvent, setWorkingRoutes]);

  const handleActionUpdate = useCallback((actionIndex: number, updates: Partial<RouteAction>) => {
    if (!routes || !selectedEventName) return;

    setWorkingRoutes({
      ...routes,
      events: routes.events.map(e =>
        e.name === selectedEventName
          ? {
              ...e,
              actions: e.actions.map((a, i) => {
                if (i !== actionIndex) return a;

                // If changing type, create fresh action with new type's defaults
                if (updates.type && updates.type !== a.type) {
                  switch (updates.type) {
                    case 'Play':
                      return createDefaultPlayAction(routes.defaultBus);
                    case 'Stop':
                      return createDefaultStopAction();
                    case 'StopAll':
                      return createDefaultStopAllAction();
                    case 'Fade':
                      return createDefaultFadeAction();
                    case 'Pause':
                      return createDefaultPauseAction();
                    case 'SetBusGain':
                      return createDefaultSetBusGainAction();
                    case 'Execute':
                      return createDefaultExecuteAction();
                    default:
                      return { ...a, ...updates } as RouteAction;
                  }
                }

                // Otherwise just merge updates
                return { ...a, ...updates } as RouteAction;
              }),
            }
          : e
      ),
    });
  }, [routes, selectedEventName, setWorkingRoutes]);

  // Reorder action via drag and drop
  const handleReorderAction = useCallback((fromIndex: number, toIndex: number) => {
    if (!routes || !selectedEventName || fromIndex === toIndex) return;

    setWorkingRoutes({
      ...routes,
      events: routes.events.map(e => {
        if (e.name !== selectedEventName) return e;

        const newActions = [...e.actions];
        const [movedAction] = newActions.splice(fromIndex, 1);
        newActions.splice(toIndex, 0, movedAction);

        return { ...e, actions: newActions };
      }),
    });

    // Update selection to follow the moved action
    if (selectedActionIndex === fromIndex) {
      setSelectedActionIndex(toIndex);
    } else if (selectedActionIndex !== null) {
      // Adjust selection if it was affected by the move
      if (fromIndex < selectedActionIndex && toIndex >= selectedActionIndex) {
        setSelectedActionIndex(selectedActionIndex - 1);
      } else if (fromIndex > selectedActionIndex && toIndex <= selectedActionIndex) {
        setSelectedActionIndex(selectedActionIndex + 1);
      }
    }

    rfDebug('Actions', 'Moved action from', fromIndex + 1, 'to', toIndex + 1);
  }, [routes, selectedEventName, selectedActionIndex, setWorkingRoutes]);

  // Bulk delete selected actions
  const handleBulkDeleteActions = useCallback(() => {
    if (!routes || !selectedEventName || selectedActionIndices.size === 0) return;

    setWorkingRoutes({
      ...routes,
      events: routes.events.map(e =>
        e.name === selectedEventName
          ? { ...e, actions: e.actions.filter((_, i) => !selectedActionIndices.has(i)) }
          : e
      ),
    });
    setSelectedActionIndices(new Set());
    setSelectedActionIndex(null);
    rfDebug('Actions', 'Bulk deleted', selectedActionIndices.size, 'actions');
  }, [routes, selectedEventName, selectedActionIndices, setWorkingRoutes]);

  // Handle action click with multi-select support
  const handleActionClick = useCallback((idx: number, event: React.MouseEvent) => {
    if (event.shiftKey && selectedActionIndex !== null) {
      // Shift+click: range select
      const start = Math.min(selectedActionIndex, idx);
      const end = Math.max(selectedActionIndex, idx);
      const newSelection = new Set<number>();
      for (let i = start; i <= end; i++) {
        newSelection.add(i);
      }
      setSelectedActionIndices(newSelection);
    } else if (event.ctrlKey || event.metaKey) {
      // Ctrl/Cmd+click: toggle selection
      const newSelection = new Set(selectedActionIndices);
      if (newSelection.has(idx)) {
        newSelection.delete(idx);
      } else {
        newSelection.add(idx);
      }
      setSelectedActionIndices(newSelection);
      setSelectedActionIndex(idx);
    } else {
      // Normal click: single select
      setSelectedActionIndices(new Set([idx]));
      setSelectedActionIndex(idx);
    }
  }, [selectedActionIndex, selectedActionIndices]);

  // Transport state
  const [isPlaying, setIsPlaying] = useState(false);
  const [isRecording, setIsRecording] = useState(false);
  // Track active audio voices for meter simulation
  const [activeAudioCount, setActiveAudioCount] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);
  const [tempo, setTempo] = useState(128);
  const [loopEnabled, setLoopEnabled] = useState(false); // Loop off by default, press L to set region
  const [loopRegion, setLoopRegion] = useState<{ start: number; end: number } | null>({ start: 8, end: 24 });
  const [metronomeEnabled, setMetronomeEnabled] = useState(false);
  const [timeDisplayMode, setTimeDisplayMode] = useState<'bars' | 'timecode' | 'samples'>('bars');

  // Project explorer state - now derived from real project
  const [searchQuery, setSearchQuery] = useState('');

  // Mixer state - use real buses from project
  const [selectedBusId, setSelectedBusId] = useState<string | null>(null);

  // DAW mode - selected track for Channel Strip
  const [selectedTrackId, setSelectedTrackId] = useState<string | null>(null);

  // DAW mode - selected clip(s) for Clip Editor
  const [selectedClipId, setSelectedClipId] = useState<string | null>(null);
  const [selectedClipIds, setSelectedClipIds] = useState<Set<string>>(new Set());

  // Lower zone state
  const [activeLowerTab, setActiveLowerTab] = useState(initialSession.activeLowerTab ?? 'timeline');

  // Switch to mode-appropriate tab when mode changes
  const prevModeRef = useRef(editorMode);
  useEffect(() => {
    if (prevModeRef.current !== editorMode) {
      const defaultTab = getDefaultTabForMode(editorMode);
      setActiveLowerTab(defaultTab);
      prevModeRef.current = editorMode;
    }
  }, [editorMode]);

  // Auto-save session to localStorage on changes
  useEffect(() => {
    const session: SessionState = {
      selectedEventName,
      selectedActionIndex,
      activeLowerTab,
      routes: workingRoutes,
      timestamp: Date.now(),
    };

    try {
      localStorage.setItem(STORAGE_KEYS.SESSION, JSON.stringify(session));
    } catch (err) {
      // localStorage might be full or disabled
      console.warn('[Session] Failed to save session:', err);
    }
  }, [selectedEventName, selectedActionIndex, activeLowerTab, workingRoutes]);

  // Console messages
  const [consoleMessages, setConsoleMessages] = useState<ConsoleMessage[]>([
    { id: '1', level: 'info', message: 'ReelForge initialized', timestamp: new Date() },
    { id: '2', level: 'info', message: 'Project loaded: Demo Project', timestamp: new Date() },
    { id: '3', level: 'info', message: 'Audio engine ready (48kHz, 256 samples)', timestamp: new Date() },
  ]);

  // Audio files state - imported audio with waveform data (declared first for adapters)
  interface ImportedAudioFile {
    id: string;
    name: string;
    file: File;
    url: string;
    duration: number;
    waveform: number[];
    buffer?: AudioBuffer;
    /** Offset into source audio where actual content starts (skip MP3/AAC padding) */
    sourceOffset?: number;
    /** Detected BPM (tempo) */
    bpm?: number;
    /** BPM detection confidence (0-1) */
    bpmConfidence?: number;
    /** Detected musical key (e.g., "Am", "C", "F#m") */
    key?: string;
    /** Number of bars in loop */
    loopBars?: number;
  }
  const [importedAudioFiles, setImportedAudioFiles] = useState<ImportedAudioFile[]>([]);

  // Timeline state - synced with projectStore for undo/redo support
  const { tracks: storeTracks, addTrack, removeTrack, updateTrack } = useTracks();
  const { clips: storeClips, addClip, updateClip, removeClip } = useClips();

  // Adapter: Convert TrackState → TimelineTrack for Timeline component
  const timelineTracks = useMemo((): TimelineTrack[] => {
    return storeTracks.map((track): TimelineTrack => ({
      id: track.id,
      name: track.name,
      color: track.color,
      height: 80,
      muted: track.muted,
      soloed: track.solo,
      armed: track.armed,
      locked: false,
    }));
  }, [storeTracks]);

  // Adapter: Convert ClipState → TimelineClip for Timeline component
  // Also merge waveform data and AudioBuffer from importedAudioFiles
  const timelineClips = useMemo((): TimelineClip[] => {
    return storeClips.map((clip): TimelineClip => {
      // Find audio file from imported files
      const audioFile = importedAudioFiles.find(f => f.id === clip.audioFileId);
      return {
        id: clip.id,
        trackId: clip.trackId,
        name: clip.name,
        startTime: clip.startTime,
        duration: clip.duration,
        color: clip.color,
        waveform: audioFile?.waveform,
        audioBuffer: audioFile?.buffer, // Pass AudioBuffer for Cubase-style LOD waveform
        sourceOffset: clip.offset,
        sourceDuration: clip.sourceDuration, // Pass source duration for trim constraints
        fadeIn: clip.fadeIn,
        fadeOut: clip.fadeOut,
        gain: clip.gain ?? 1,
        muted: false,
        selected: selectedClipIds.has(clip.id),
      };
    });
  }, [storeClips, importedAudioFiles, selectedClipIds]);

  // Adapter: Convert to TimelineClipData format for playback (includes AudioBuffer)
  const playbackClips = useMemo((): TimelineClipData[] => {
    const result = storeClips.map((clip): TimelineClipData => {
      const audioFile = importedAudioFiles.find(f => f.id === clip.audioFileId);
      // Find the track to get its output bus routing
      const track = storeTracks.find(t => t.id === clip.trackId);
      const playbackClip = {
        id: clip.id,
        trackId: clip.trackId,
        name: clip.name,
        startTime: clip.startTime,
        duration: clip.duration,
        audioBuffer: audioFile?.buffer,
        blobUrl: audioFile?.url,
        color: clip.color,
        // Use clip.offset which contains sourceOffset from import
        sourceOffset: clip.offset,
        // Route through track's output bus
        outputBus: (track?.outputBus as 'master' | 'music' | 'sfx' | 'ambience' | 'voice') || 'sfx',
      };
      return playbackClip;
    });
    // Debug: log when playbackClips changes
    if (result.length > 0) {
      console.log('[PlaybackClips] Updated:', result.map(c => ({
        name: c.name,
        hasBuffer: !!c.audioBuffer,
        bufferDuration: c.audioBuffer?.duration?.toFixed(2),
        clipDuration: c.duration.toFixed(2),
        outputBus: c.outputBus,
      })));
    }
    return result;
  }, [storeClips, importedAudioFiles, storeTracks]);

  const [zoom, setZoom] = useState(50);
  const [scrollOffset, setScrollOffset] = useState(0);

  // Crossfade state
  const [crossfades, setCrossfades] = useState<Crossfade[]>([]);

  // Crossfade handlers
  const handleCrossfadeCreate = useCallback((crossfade: Omit<Crossfade, 'id'>) => {
    const newCrossfade: Crossfade = {
      ...crossfade,
      id: `xfade-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
    };
    setCrossfades(prev => [...prev, newCrossfade]);
  }, []);

  const handleCrossfadeUpdate = useCallback((crossfadeId: string, duration: number) => {
    setCrossfades(prev => prev.map(xf =>
      xf.id === crossfadeId ? { ...xf, duration } : xf
    ));
  }, []);

  const handleCrossfadeDelete = useCallback((crossfadeId: string) => {
    setCrossfades(prev => prev.filter(xf => xf.id !== crossfadeId));
  }, []);

  // Clean up crossfades when clips are deleted or moved
  useEffect(() => {
    setCrossfades(prev => prev.filter(xf => {
      const clipA = storeClips.find(c => c.id === xf.clipAId);
      const clipB = storeClips.find(c => c.id === xf.clipBId);
      // Remove crossfade if either clip is missing
      if (!clipA || !clipB) return false;
      // Remove crossfade if clips no longer overlap
      const clipAEnd = clipA.startTime + clipA.duration;
      if (clipAEnd <= clipB.startTime) return false;
      return true;
    }));
  }, [storeClips]);

  // Snap to grid state
  const [snapEnabled, setSnapEnabled] = useState(true);
  const [snapValue, setSnapValue] = useState(1); // 1 beat = quarter note

  // Channel Strip data for DAW mode - based on selected track
  const channelStripData = useMemo((): ChannelStripData | null => {
    if (!selectedTrackId) return null;

    const track = storeTracks.find(t => t.id === selectedTrackId);
    if (!track) return null;

    // Convert track inserts to ChannelStrip InsertSlot format
    // Fill remaining slots with empty inserts up to 8
    const trackInserts = (track.inserts || []).map(insert => ({
      id: insert.id,
      pluginName: getPluginDefinition(insert.pluginId)?.displayName || insert.pluginId,
      bypassed: !insert.enabled,
    }));
    const emptySlots = createEmptyInserts(8 - trackInserts.length);
    const allInserts = [...trackInserts, ...emptySlots];

    return {
      id: track.id,
      name: track.name,
      type: 'audio',
      color: track.color,
      volume: track.volume ?? 0,
      pan: track.pan ?? 0,
      mute: track.muted,
      solo: track.solo,
      meterL: 0, // Would come from real-time metering
      meterR: 0,
      peakL: 0,
      peakR: 0,
      inserts: allInserts,
      sends: createEmptySends(8),
      eqEnabled: false,
      eqBands: [],
      input: 'No Input',
      output: 'Stereo Out',
    };
  }, [selectedTrackId, storeTracks]);

  // When a track is selected, set loop region to cover all clips on that track
  useEffect(() => {
    if (!selectedTrackId) return;

    // Find all clips on this track
    const trackClips = storeClips.filter(c => c.trackId === selectedTrackId);
    if (trackClips.length === 0) return;

    // Calculate track bounds (earliest start to latest end)
    const trackStart = Math.min(...trackClips.map(c => c.startTime));
    const trackEnd = Math.max(...trackClips.map(c => c.startTime + c.duration));

    // Set loop region to track bounds
    setLoopRegion({ start: trackStart, end: trackEnd });
    // Enable loop by default when selecting track
    setLoopEnabled(true);
  }, [selectedTrackId, storeClips]);

  // Channel Strip handlers
  const handleChannelVolumeChange = useCallback((channelId: string, volume: number) => {
    updateTrack(channelId, { volume });
  }, [updateTrack]);

  const handleChannelPanChange = useCallback((channelId: string, pan: number) => {
    updateTrack(channelId, { pan });
  }, [updateTrack]);

  const handleChannelMuteToggle = useCallback((channelId: string) => {
    const track = storeTracks.find(t => t.id === channelId);
    if (track) {
      updateTrack(channelId, { muted: !track.muted });
    }
  }, [storeTracks, updateTrack]);

  const handleChannelSoloToggle = useCallback((channelId: string) => {
    const track = storeTracks.find(t => t.id === channelId);
    if (track) {
      updateTrack(channelId, { solo: !track.solo });
    }
  }, [storeTracks, updateTrack]);

  // Clip Editor data for DAW mode - based on selected clip
  const clipEditorData = useMemo((): ClipEditorClip | null => {
    if (!selectedClipId) return null;

    const clip = storeClips.find(c => c.id === selectedClipId);
    if (!clip) return null;

    // Find audio file for waveform
    const audioFile = importedAudioFiles.find(f => f.id === clip.audioFileId);

    return {
      id: clip.id,
      name: clip.name,
      duration: clip.duration,
      sampleRate: audioFile?.buffer?.sampleRate ?? 48000,
      channels: audioFile?.buffer?.numberOfChannels ?? 2,
      bitDepth: 24, // Assume 24-bit
      waveform: audioFile?.waveform,
      fadeIn: clip.fadeIn ?? 0,
      fadeOut: clip.fadeOut ?? 0,
      gain: clip.gain ?? 0,
      color: clip.color,
    };
  }, [selectedClipId, storeClips, importedAudioFiles]);

  // Import dialog state (Cubase-style)
  const [importDialogOpen, setImportDialogOpen] = useState(false);
  const [filesToImport, setFilesToImport] = useState<FileToImport[]>([]);
  const [pendingImportFiles, setPendingImportFiles] = useState<File[]>([]);

  // Batch import progress state
  const [importProgress, setImportProgress] = useState<{
    isImporting: boolean;
    current: number;
    total: number;
    currentFileName: string;
    errors: string[];
  }>({ isImporting: false, current: 0, total: 0, currentFileName: '', errors: [] });

  // Audio Pool state - derived from imported files with real usage tracking
  const audioPoolAssets = useMemo((): PoolAsset[] => {
    // Count how many times each audio file is used in timeline clips
    const usageCounts = new Map<string, { count: number; clipNames: string[] }>();

    storeClips.forEach(clip => {
      if (clip.audioFileId) {
        const existing = usageCounts.get(clip.audioFileId) || { count: 0, clipNames: [] };
        existing.count++;
        existing.clipNames.push(clip.name);
        usageCounts.set(clip.audioFileId, existing);
      }
    });

    return importedAudioFiles.map((file): PoolAsset => {
      const usage = usageCounts.get(file.id) || { count: 0, clipNames: [] };
      return {
        id: file.id,
        name: file.name,
        duration: file.duration,
        sampleRate: file.buffer?.sampleRate ?? 48000,
        channels: file.buffer?.numberOfChannels ?? 2,
        format: file.name.split('.').pop()?.toUpperCase() ?? 'WAV',
        size: file.file.size,
        waveform: file.waveform,
        status: usage.count > 0 ? 'used' : 'unused',
        location: 'local',
        usageCount: usage.count,
        usedIn: usage.clipNames,
        dateAdded: new Date(),
        // BPM metadata
        bpm: file.bpm,
        bpmConfidence: file.bpmConfidence,
        loopBars: file.loopBars,
      };
    });
  }, [importedAudioFiles, storeClips]);

  // ============ Timeline Playback Integration ============
  // Connect timeline clips to real audio playback via Web Audio API
  const {
    isPlaying: playbackIsPlaying,
    currentTime: playbackCurrentTime,
    duration: playbackDuration,
    loopEnabled: playbackLoopEnabled,
    play: playbackPlay,
    pause: playbackPause,
    stop: playbackStop,
    seek: playbackSeek,
    toggleLoop: playbackToggleLoop,
    setLoopRegion: playbackSetLoopRegion,
  } = useTimelinePlayback({
    clips: playbackClips,
    duration: 32, // Default timeline duration in seconds
    updateInterval: 16, // ~60fps update
    onTimeUpdate: (time) => {
      setCurrentTime(time);
    },
    onPlaybackEnd: () => {
      setIsPlaying(false);
      setCurrentTime(0);
    },
    // Route timeline playback through bus system for mixer integration
    externalMasterGain: busGainsRef.current['master'] ?? null,
    // Pass all bus gains for per-track routing
    busGains: {
      master: busGainsRef.current['master'] ?? null,
      music: busGainsRef.current['music'] ?? null,
      sfx: busGainsRef.current['sfx'] ?? null,
      ambience: busGainsRef.current['ambience'] ?? null,
      voice: busGainsRef.current['voice'] ?? null,
    },
    // Pass crossfades for gain curve application during playback
    crossfades: crossfades.map(xf => ({
      id: xf.id,
      clipAId: xf.clipAId,
      clipBId: xf.clipBId,
      startTime: xf.startTime,
      duration: xf.duration,
      curveType: xf.curveType,
    })),
  });

  // Sync local isPlaying state with playback state
  useEffect(() => {
    setIsPlaying(playbackIsPlaying);
  }, [playbackIsPlaying]);

  // Sync loop region with playback hook
  useEffect(() => {
    if (loopRegion) {
      playbackSetLoopRegion(loopRegion.start, loopRegion.end);
    }
  }, [loopRegion, playbackSetLoopRegion]);

  // Sync loop enabled with playback hook
  useEffect(() => {
    if (loopEnabled !== playbackLoopEnabled) {
      playbackToggleLoop();
    }
  }, [loopEnabled, playbackLoopEnabled, playbackToggleLoop]);

  // Auto-scroll timeline to follow playhead during playback
  const [followPlayhead, _setFollowPlayhead] = useState(true);
  useEffect(() => {
    if (!isPlaying || !followPlayhead) return;

    // Calculate visible time range based on zoom
    // zoom is pixels per second, assume ~800px visible width
    const visibleWidth = 800;
    const visibleDuration = visibleWidth / zoom;
    const visibleStart = scrollOffset;
    const visibleEnd = scrollOffset + visibleDuration;

    // If playhead is near the right edge (within 20% of visible area), scroll
    const scrollThreshold = visibleEnd - visibleDuration * 0.2;

    if (currentTime > scrollThreshold && currentTime < 32) {
      // Scroll to keep playhead at ~30% from left
      const newOffset = Math.max(0, currentTime - visibleDuration * 0.3);
      setScrollOffset(newOffset);
    }
    // If playhead jumped back (loop), reset scroll
    else if (currentTime < visibleStart) {
      setScrollOffset(Math.max(0, currentTime - visibleDuration * 0.1));
    }
  }, [currentTime, isPlaying, followPlayhead, zoom, scrollOffset]);

  // Handle playhead change - updates both local state and playback position
  const handlePlayheadChange = useCallback((time: number) => {
    setCurrentTime(time);
    // Also seek in playback engine so play starts from here
    playbackSeek(time);
  }, [playbackSeek]);

  // Set loop region from selected clip(s) - Shift+L
  const handleSetLoopFromSelection = useCallback(() => {
    if (selectedClipIds.size === 0) return;

    // Find all selected clips and compute their combined bounds
    let minStart = Infinity;
    let maxEnd = -Infinity;

    for (const clipId of selectedClipIds) {
      const clip = storeClips.find(c => c.id === clipId);
      if (clip) {
        minStart = Math.min(minStart, clip.startTime);
        maxEnd = Math.max(maxEnd, clip.startTime + clip.duration);
      }
    }

    if (minStart !== Infinity && maxEnd !== -Infinity) {
      setLoopRegion({ start: minStart, end: maxEnd });
      setLoopEnabled(true);
      rfDebug('Timeline', `Loop set from selection: ${minStart.toFixed(2)}s - ${maxEnd.toFixed(2)}s`);
    }
  }, [selectedClipIds, storeClips]);

  // Global keyboard shortcuts for DAW operations
  useGlobalShortcuts({
    onPlayPause: () => {
      if (playbackIsPlaying) {
        playbackPause();
      } else {
        playbackPlay();
      }
    },
    onStop: playbackStop,
    onToggleLoop: () => setLoopEnabled(prev => !prev),
    onSetLoopFromSelection: handleSetLoopFromSelection,
    onGoToStart: () => playbackSeek(0),
    onGoToEnd: () => playbackSeek(playbackDuration),
    onZoomIn: () => setZoom(prev => Math.min(200, prev * 1.25)),
    onZoomOut: () => setZoom(prev => Math.max(10, prev / 1.25)),
    onZoomToFit: () => setZoom(50), // Reset to default
  });

  // Restore audio files from IndexedDB on mount
  const audioRestoredRef = useRef(false);
  useEffect(() => {
    if (audioRestoredRef.current) return;
    audioRestoredRef.current = true;

    const restoreAudio = async () => {
      try {
        const storedFiles = await loadAudioFromDB();
        if (storedFiles.length === 0) return;

        rfDebug('IndexedDB', 'Restoring', storedFiles.length, 'audio files...');

        // Use the main audioContext (already created via useMemo)
        const ctx = audioContextRef.current!;
        const restoredFiles: ImportedAudioFile[] = [];

        for (let i = 0; i < storedFiles.length; i++) {
          const stored = storedFiles[i];
          try {
            // Reconstruct AudioBuffer from stored data
            const data = new Float32Array(stored.arrayBuffer);
            const sampleRate = data[0];
            const channels = data[1];
            const length = data[2];
            const headerSize = 3;

            const audioBuffer = ctx.createBuffer(channels, length, sampleRate);
            for (let ch = 0; ch < channels; ch++) {
              const channelData = audioBuffer.getChannelData(ch);
              channelData.set(data.subarray(headerSize + ch * length, headerSize + (ch + 1) * length));
            }

            // Create valid WAV blob URL for playback (with proper WAV header)
            const url = createAudioBlobUrl(audioBuffer);
            const wavBlob = await fetch(url).then(r => r.blob());

            restoredFiles.push({
              id: stored.id,
              name: stored.name,
              file: new File([wavBlob], stored.name, { type: 'audio/wav' }),
              url,
              duration: stored.duration,
              waveform: stored.waveform,
              buffer: audioBuffer,
              sourceOffset: stored.sourceOffset ?? 0, // Restore offset for playback
            });

            // Audio files restored to pool only - user can drag them to timeline manually
            // No auto-creation of tracks/clips - timeline stays empty until user drags files
          } catch (err) {
            console.warn('[IndexedDB] Failed to restore file:', stored.name, err);
          }
        }

        // NOTE: Don't close audioContext - it's shared by the entire app!
        // audioContext.close() would break all audio routing

        if (restoredFiles.length > 0) {
          setImportedAudioFiles(restoredFiles);
          rfDebug('IndexedDB', 'Restored', restoredFiles.length, 'audio files');
        }
      } catch (err) {
        console.warn('[IndexedDB] Failed to restore audio:', err);
      }
    };

    restoreAudio();
  }, []);

  // Process initial imported files from welcome screen
  const initialFilesProcessedRef = useRef(false);
  useEffect(() => {
    if (initialFilesProcessedRef.current) return;
    if (!initialImportedFiles || initialImportedFiles.length === 0) return;
    initialFilesProcessedRef.current = true;

    const processInitialFiles = async () => {
      rfDebug('Import', 'Processing', initialImportedFiles.length, 'files from welcome screen...');

      // Use the main audioContext (already created via useMemo)
      const ctx = audioContextRef.current!;
      const loadedFiles: ImportedAudioFile[] = [];

      for (let i = 0; i < initialImportedFiles.length; i++) {
        const file = initialImportedFiles[i];
        try {
          const arrayBuffer = await file.arrayBuffer();
          let audioBuffer = await ctx.decodeAudioData(arrayBuffer);

          // Check for sample rate mismatch and resample if needed
          const projectSampleRate = DEFAULT_PROJECT_SAMPLE_RATE; // 48000 Hz
          if (needsSampleRateConversion(audioBuffer, projectSampleRate)) {
            console.log('[AudioImport] Sample rate conversion:', formatSampleRate(audioBuffer.sampleRate), '→', formatSampleRate(projectSampleRate));
            audioBuffer = await resampleAudioBuffer(audioBuffer, projectSampleRate);
          }

          // For WAV/AIFF/FLAC, don't do silence detection (no encoder padding)
          // For MP3/AAC, detect actual audio bounds to skip encoder padding
          const isLossless = file.name.toLowerCase().endsWith('.wav') ||
                            file.name.toLowerCase().endsWith('.aiff') ||
                            file.name.toLowerCase().endsWith('.flac');

          const channelData = audioBuffer.getChannelData(0);
          const sampleRate = audioBuffer.sampleRate;
          const totalSamples = channelData.length;

          let safeStart = 0;
          let safeEnd = totalSamples;

          if (!isLossless) {
            // Only detect silence for lossy formats that have encoder padding
            const threshold = 0.01;

            // Find first sample above threshold (skip leading silence)
            let firstNonSilentSample = 0;
            for (let s = 0; s < totalSamples; s++) {
              if (Math.abs(channelData[s]) > threshold) {
                firstNonSilentSample = s;
                break;
              }
            }

            // Find last sample above threshold (scan from end)
            let lastNonSilentSample = totalSamples - 1;
            for (let s = totalSamples - 1; s >= 0; s--) {
              if (Math.abs(channelData[s]) > threshold) {
                lastNonSilentSample = s;
                break;
              }
            }

            // Add small buffer (50ms) to avoid cutting off attacks/reverb tails
            const bufferSamples = Math.floor(sampleRate * 0.05);
            safeStart = Math.max(0, firstNonSilentSample - bufferSamples);
            safeEnd = Math.min(lastNonSilentSample + bufferSamples, totalSamples);
          }

          const startOffset = safeStart / sampleRate;
          const actualDuration = (safeEnd - safeStart) / sampleRate;
          const actualSamples = safeEnd - safeStart;

          const waveformSamples = Math.max(100, Math.min(1000, Math.floor(actualDuration * 50)));
          const waveform: number[] = [];
          const samplesPerPoint = Math.floor(actualSamples / waveformSamples);
          for (let j = 0; j < waveformSamples; j++) {
            const start = safeStart + j * samplesPerPoint;
            const end = Math.min(start + samplesPerPoint, safeEnd);
            let max = 0;
            for (let k = start; k < end; k++) {
              const abs = Math.abs(channelData[k]);
              if (abs > max) max = abs;
            }
            waveform.push(max);
          }

          const fileId = `audio_${Date.now()}_${i}`;
          const url = URL.createObjectURL(file);

          loadedFiles.push({
            id: fileId,
            name: file.name,
            file,
            url,
            duration: actualDuration,
            waveform,
            buffer: audioBuffer,
            sourceOffset: startOffset, // Store offset to skip leading silence
          });

          // Audio files loaded to pool only - user can drag them to timeline manually
          // No auto-creation of tracks/clips - timeline stays empty until user drags files

          setConsoleMessages(prev => [...prev, {
            id: Date.now().toString(),
            level: 'info',
            message: `Loaded: ${file.name} (${actualDuration.toFixed(1)}s, offset ${startOffset.toFixed(2)}s)`,
            timestamp: new Date(),
          }]);
        } catch (err) {
          console.error(`Failed to load ${file.name}:`, err);
          setConsoleMessages(prev => [...prev, {
            id: Date.now().toString(),
            level: 'error',
            message: `Failed to load: ${file.name}`,
            timestamp: new Date(),
          }]);
        }
      }

      // NOTE: Don't close audioContext - it's shared by the entire app!
      // audioContext.close() would break all audio routing

      if (loadedFiles.length > 0) {
        setImportedAudioFiles(loadedFiles);
        rfDebug('Import', 'Loaded', loadedFiles.length, 'audio files from welcome screen');
      }
    };

    processInitialFiles();
  }, [initialImportedFiles]);

  // Save audio file metadata to localStorage (without File/AudioBuffer which can't be serialized)
  useEffect(() => {
    if (importedAudioFiles.length === 0) return;

    const audioMeta: AudioFileMeta[] = importedAudioFiles.map(f => ({
      id: f.id,
      name: f.name,
      duration: f.duration,
      waveform: f.waveform,
    }));

    try {
      localStorage.setItem(STORAGE_KEYS.AUDIO_META, JSON.stringify(audioMeta));
    } catch (err) {
      console.warn('[Session] Failed to save audio metadata:', err);
    }
  }, [importedAudioFiles]);

  // Convert importedAudioFiles to AudioAssetOption format for picker
  const audioAssetOptions: AudioAssetOption[] = useMemo(() => {
    return importedAudioFiles.map(f => ({
      id: f.id,
      name: f.name,
      duration: f.duration,
      waveform: f.waveform,
    }));
  }, [importedAudioFiles]);

  // Available asset IDs set for validation
  const availableAssetIds = useMemo(() => {
    return new Set(importedAudioFiles.map(f => f.name));
  }, [importedAudioFiles]);

  // Layered music state - starts empty
  const [musicLayers, setMusicLayers] = useState<MusicLayer[]>([]);
  const [blendCurves, setBlendCurves] = useState<BlendCurve[]>([]);
  const [musicStates] = useState<MusicState[]>([]);
  const [currentMusicState, setCurrentMusicState] = useState('');
  const [rtpcValue, setRtpcValue] = useState(0.5);

  // Floating panels state
  const panelManager = usePanelManager(['layeredMusic', 'spectrogram', 'meters', 'spinCycle', 'winTiers', 'reelSequencer']);
  const [showLayeredMusic, setShowLayeredMusic] = useState(false);
  const [showSpectrogram, setShowSpectrogram] = useState(false);
  const [showSpinCycle, setShowSpinCycle] = useState(false);
  const [showWinTiers, setShowWinTiers] = useState(false);
  const [showReelSequencer, setShowReelSequencer] = useState(false);

  // Slot audio state
  const [spinConfig, setSpinConfig] = useState<SpinCycleConfig>(generateDemoSpinCycleConfig);
  const [currentSpinState, setCurrentSpinState] = useState<SpinState>('idle');
  const [isSlotSimulating, setIsSlotSimulating] = useState(false);
  const [winTiers, setWinTiers] = useState<WinTierConfig[]>(generateDemoWinTiers);
  const [activeTier, setActiveTier] = useState<WinTier | null>(null);
  const [reelConfigs, setReelConfigs] = useState<ReelConfig[]>(generateDemoReelConfig);
  const [sequencerTime, setSequencerTime] = useState(0);
  const [isSequencerPlaying, setIsSequencerPlaying] = useState(false);
  const slotEventIdRef = useRef(0);

  // Slot event logging helper
  const logSlotEvent = useCallback((event: string, data?: string) => {
    setConsoleMessages((prev) => [
      ...prev.slice(-49),
      {
        id: `slot-${slotEventIdRef.current++}`,
        level: 'info',
        message: `[SLOT] ${event}${data ? `: ${data}` : ''}`,
        timestamp: new Date(),
      },
    ]);
  }, []);

  // ===== AUDIO PLAYBACK =====

  /** Get AudioContext (already initialized at component mount) and resume if suspended */
  const getAudioContext = useCallback((): AudioContext => {
    // AudioContext and masterGain are already created at component initialization
    // Just resume if suspended (browser autoplay policy)
    if (audioContextRef.current!.state === 'suspended') {
      audioContextRef.current!.resume();
    }
    return audioContextRef.current!;
  }, []);

  /** Stop all currently playing audio */
  const stopAllAudio = useCallback(() => {
    let stoppedCount = 0;
    activeSourcesRef.current.forEach((voices) => {
      voices.forEach((voice) => {
        try {
          voice.source.stop();
          stoppedCount++;
        } catch { /* ignore */ }
      });
    });
    activeSourcesRef.current.clear();
    // Reset meter simulation
    setActiveAudioCount(0);
    setConsoleMessages((prev) => [
      ...prev.slice(-49),
      { id: `audio-${Date.now()}`, level: 'info', message: `[Audio] Stopped all playback (${stoppedCount} voices)`, timestamp: new Date() },
    ]);
  }, []);

  /** Stop specific asset by assetId */
  const stopAudioByAsset = useCallback((assetId: string) => {
    const voices = activeSourcesRef.current.get(assetId);
    if (!voices || voices.length === 0) {
      console.warn('[Audio] No active playback for:', assetId);
      return;
    }

    const voiceCount = voices.length;
    voices.forEach((voice) => {
      try {
        voice.source.stop();
      } catch { /* ignore */ }
    });
    activeSourcesRef.current.delete(assetId);
    // Update meter simulation
    setActiveAudioCount(prev => Math.max(0, prev - voiceCount));

    setConsoleMessages((prev) => [
      ...prev.slice(-49),
      { id: `audio-${Date.now()}`, level: 'info', message: `[Audio] Stopped: ${assetId} (${voiceCount} voices)`, timestamp: new Date() },
    ]);
  }, []);

  /** Fade asset gain over time */
  const fadeAudioAsset = useCallback((assetId: string, targetVolume: number, fadeTime: number = 0.5) => {
    const voices = activeSourcesRef.current.get(assetId);
    if (!voices || voices.length === 0) {
      console.warn('[Audio] Fade: No active playback for:', assetId);
      return;
    }

    const ctx = getAudioContext();
    const now = ctx.currentTime;

    voices.forEach((voice) => {
      try {
        // Cancel any scheduled changes and ramp to target
        voice.gainNode.gain.cancelScheduledValues(now);
        voice.gainNode.gain.setValueAtTime(voice.gainNode.gain.value, now);
        voice.gainNode.gain.linearRampToValueAtTime(targetVolume, now + fadeTime);
      } catch (e) {
        console.warn('[Audio] Fade error:', e);
      }
    });

    setConsoleMessages((prev) => [
      ...prev.slice(-49),
      { id: `audio-${Date.now()}`, level: 'info', message: `[Audio] Fade: ${assetId} → ${(targetVolume * 100).toFixed(0)}% over ${fadeTime}s`, timestamp: new Date() },
    ]);
  }, [getAudioContext]);

  // Hover preview state - separate source for short previews
  const hoverPreviewSourceRef = useRef<AudioBufferSourceNode | null>(null);
  const hoverPreviewGainRef = useRef<GainNode | null>(null);

  /** Play a short preview of audio file (first 1.5 seconds, with fade out) */
  const playHoverPreview = useCallback((assetId: string) => {
    // Stop any existing hover preview first
    if (hoverPreviewSourceRef.current) {
      try {
        hoverPreviewSourceRef.current.stop();
      } catch { /* ignore */ }
      hoverPreviewSourceRef.current = null;
    }

    const audioFile = importedAudioFiles.find((f) => f.name === assetId || f.id === assetId);
    if (!audioFile) {
      console.warn('[HoverPreview] File not found:', assetId, 'Available:', importedAudioFiles.map(f => f.name));
      return;
    }
    rfDebug('HoverPreview', 'Playing:', assetId, 'hasBuffer:', !!audioFile.buffer);

    const ctx = getAudioContext();
    // Route hover preview through SFX bus
    const previewBusGain = busGainsRef.current['sfx'] ?? masterGainRef.current!;

    const playBuffer = (buffer: AudioBuffer) => {
      const source = ctx.createBufferSource();
      source.buffer = buffer;

      const gainNode = ctx.createGain();
      gainNode.gain.value = 0.5; // Lower volume for preview

      source.connect(gainNode);
      // Route through SFX bus for proper mixing control
      gainNode.connect(previewBusGain);

      hoverPreviewSourceRef.current = source;
      hoverPreviewGainRef.current = gainNode;

      // Play only first 1.5 seconds with fade out
      const previewDuration = Math.min(1.5, buffer.duration);
      const fadeOutTime = 0.15;

      // Schedule fade out
      gainNode.gain.setValueAtTime(0.5, ctx.currentTime + previewDuration - fadeOutTime);
      gainNode.gain.linearRampToValueAtTime(0, ctx.currentTime + previewDuration);

      source.start(0, 0, previewDuration);

      source.onended = () => {
        if (hoverPreviewSourceRef.current === source) {
          hoverPreviewSourceRef.current = null;
          hoverPreviewGainRef.current = null;
        }
      };
    };

    // If buffer exists, use it directly
    if (audioFile.buffer) {
      playBuffer(audioFile.buffer);
    } else if (audioFile.url) {
      // Fallback: fetch and decode
      fetch(audioFile.url)
        .then(res => res.arrayBuffer())
        .then(buf => ctx.decodeAudioData(buf))
        .then(decodedBuffer => {
          // Cache the buffer for future use
          audioFile.buffer = decodedBuffer;
          playBuffer(decodedBuffer);
        })
        .catch(() => { /* ignore decode errors for preview */ });
    }
  }, [importedAudioFiles, getAudioContext]);

  /** Stop hover preview */
  const stopHoverPreview = useCallback(() => {
    if (hoverPreviewSourceRef.current && hoverPreviewGainRef.current) {
      const ctx = audioContextRef.current;
      if (ctx) {
        // Quick fade out to avoid click
        hoverPreviewGainRef.current.gain.setValueAtTime(
          hoverPreviewGainRef.current.gain.value,
          ctx.currentTime
        );
        hoverPreviewGainRef.current.gain.linearRampToValueAtTime(0, ctx.currentTime + 0.05);

        // Stop after fade
        setTimeout(() => {
          try {
            hoverPreviewSourceRef.current?.stop();
          } catch { /* ignore */ }
          hoverPreviewSourceRef.current = null;
          hoverPreviewGainRef.current = null;
        }, 60);
      } else {
        try {
          hoverPreviewSourceRef.current.stop();
        } catch { /* ignore */ }
        hoverPreviewSourceRef.current = null;
        hoverPreviewGainRef.current = null;
      }
    }
  }, []);

  /** Play an audio file by assetId */
  const playAudioFile = useCallback((assetId: string, options?: { gain?: number; loop?: boolean; pan?: number; bus?: string }) => {
    rfDebug('Audio', 'playAudioFile called:', assetId);

    // Try multiple matching strategies
    let audioFile = importedAudioFiles.find((f) => f.name === assetId || f.id === assetId);

    // Try without extension
    if (!audioFile) {
      const assetWithoutExt = assetId.replace(/\.[^/.]+$/, '');
      audioFile = importedAudioFiles.find((f) => {
        const nameWithoutExt = f.name.replace(/\.[^/.]+$/, '');
        return nameWithoutExt === assetWithoutExt || nameWithoutExt === assetId || f.name === assetWithoutExt;
      });
    }

    // Try case-insensitive match
    if (!audioFile) {
      const assetLower = assetId.toLowerCase();
      audioFile = importedAudioFiles.find((f) => f.name.toLowerCase().includes(assetLower));
    }

    if (!audioFile) {
      console.warn('[Audio] Asset not found:', assetId, '- Available:', importedAudioFiles.map(f => f.name));
      setConsoleMessages((prev) => [
        ...prev.slice(-49),
        { id: `audio-${Date.now()}`, level: 'warn', message: `[Audio] Asset not found: ${assetId}`, timestamp: new Date() },
      ]);
      return;
    }

    rfDebug('Audio', 'Playing:', assetId, '→', audioFile.name);

    const ctx = getAudioContext();
    const gain = options?.gain ?? 1;
    const loop = options?.loop ?? false;
    const pan = options?.pan ?? 0;
    const bus = options?.bus?.toLowerCase() ?? 'sfx'; // Default to SFX bus

    // Get the target bus gain node (fallback to master if bus not found)
    const targetBusGain = busGainsRef.current[bus] ?? busGainsRef.current['master'] ?? masterGainRef.current!;

    // If we have a decoded buffer, use it
    if (audioFile.buffer) {
      const source = ctx.createBufferSource();
      source.buffer = audioFile.buffer;
      source.loop = loop;

      const gainNode = ctx.createGain();
      gainNode.gain.value = gain;

      const panNode = ctx.createStereoPanner();
      panNode.pan.value = pan;

      source.connect(gainNode);
      gainNode.connect(panNode);
      // Route through bus gain for proper mixing control
      panNode.connect(targetBusGain);

      source.start();

      // Create voice object with source and gainNode for fade control
      const voice = { source, gainNode };

      // Add to active voices array (supports overlapping)
      const existing = activeSourcesRef.current.get(assetId) || [];
      activeSourcesRef.current.set(assetId, [...existing, voice]);
      // Update meter simulation
      setActiveAudioCount(prev => prev + 1);

      source.onended = () => {
        // Remove this specific voice from the array
        const voices = activeSourcesRef.current.get(assetId);
        if (voices) {
          const filtered = voices.filter((v) => v.source !== source);
          if (filtered.length > 0) {
            activeSourcesRef.current.set(assetId, filtered);
          } else {
            activeSourcesRef.current.delete(assetId);
          }
        }
        // Update meter simulation
        setActiveAudioCount(prev => Math.max(0, prev - 1));
      };

      setConsoleMessages((prev) => [
        ...prev.slice(-49),
        { id: `audio-${Date.now()}`, level: 'info', message: `[Audio] Playing: ${assetId} (gain: ${gain}, loop: ${loop})`, timestamp: new Date() },
      ]);
    } else {
      // Fallback: decode and play
      fetch(audioFile.url)
        .then((res) => res.arrayBuffer())
        .then((buf) => ctx.decodeAudioData(buf))
        .then((decodedBuffer) => {
          const source = ctx.createBufferSource();
          source.buffer = decodedBuffer;
          source.loop = loop;

          const gainNode = ctx.createGain();
          gainNode.gain.value = gain;

          const panNode = ctx.createStereoPanner();
          panNode.pan.value = pan;

          source.connect(gainNode);
          gainNode.connect(panNode);
          // Route through bus gain for proper mixing control
          panNode.connect(targetBusGain);

          source.start();

          // Create voice object with source and gainNode for fade control
          const voice = { source, gainNode };

          // Add to active voices array (supports overlapping)
          const existing = activeSourcesRef.current.get(assetId) || [];
          activeSourcesRef.current.set(assetId, [...existing, voice]);
          // Update meter simulation
          setActiveAudioCount(prev => prev + 1);

          source.onended = () => {
            // Remove this specific voice from the array
            const voices = activeSourcesRef.current.get(assetId);
            if (voices) {
              const filtered = voices.filter((v) => v.source !== source);
              if (filtered.length > 0) {
                activeSourcesRef.current.set(assetId, filtered);
              } else {
                activeSourcesRef.current.delete(assetId);
              }
            }
            // Update meter simulation
            setActiveAudioCount(prev => Math.max(0, prev - 1));
          };

          setConsoleMessages((prev) => [
            ...prev.slice(-49),
            { id: `audio-${Date.now()}`, level: 'info', message: `[Audio] Playing: ${assetId}`, timestamp: new Date() },
          ]);
        })
        .catch((err) => {
          console.error('[Audio] Decode error:', err);
        });
    }
  }, [importedAudioFiles, getAudioContext]);

  /** Play a test tone to verify audio routing (3 seconds) */
  const playTestTone = useCallback(() => {
    rfDebug('Audio', 'Playing test tone (3s)...');

    const ctx = getAudioContext();
    // Route test tone through SFX bus
    const testBusGain = busGainsRef.current['sfx'] ?? masterGainRef.current!;

    // Create oscillator for test tone
    const oscillator = ctx.createOscillator();
    oscillator.type = 'sine';
    oscillator.frequency.setValueAtTime(440, ctx.currentTime); // A4

    // Create gain for envelope - 3 second tone
    const gainNode = ctx.createGain();
    gainNode.gain.setValueAtTime(0.3, ctx.currentTime);
    // Hold for 2.5s then fade out
    gainNode.gain.setValueAtTime(0.3, ctx.currentTime + 2.5);
    gainNode.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 3.0);

    // Route through SFX bus for proper mixing control
    oscillator.connect(gainNode);
    gainNode.connect(testBusGain);

    oscillator.start();
    oscillator.stop(ctx.currentTime + 3.0);

    // Track for meters AND Space toggle
    const testToneId = `__test_tone_${Date.now()}`;
    const voice = { source: oscillator as unknown as AudioBufferSourceNode, gainNode };
    activeSourcesRef.current.set(testToneId, [voice]);
    setActiveAudioCount(prev => prev + 1);

    oscillator.onended = () => {
      activeSourcesRef.current.delete(testToneId);
      setActiveAudioCount(prev => Math.max(0, prev - 1));
    };

    setConsoleMessages(prev => [...prev.slice(-49), {
      id: `test-${Date.now()}`,
      level: 'info',
      message: '[Audio] Test tone 440Hz (3s) playing...',
      timestamp: new Date(),
    }]);
  }, [getAudioContext, audioContext]);

  // Preview event - play all Play actions using imported audio files
  const handlePreviewEvent = useCallback(() => {
    if (!selectedEvent) {
      console.warn('[Preview] No event selected');
      return;
    }

    // Stop all currently playing audio if overlap is not allowed
    if (!allowOverlap) {
      stopAllAudio();
    }

    rfDebug('Preview', 'Playing event:', selectedEvent.name, 'with', selectedEvent.actions.length, 'actions');

    if (selectedEvent.actions.length === 0) {
      console.warn('[Preview] Event has no actions');
      setConsoleMessages(prev => [...prev.slice(-49), {
        id: `preview-${Date.now()}`,
        level: 'warn',
        message: `Event "${selectedEvent.name}" has no actions`,
        timestamp: new Date(),
      }]);
      return;
    }

    // Process each action - handles ALL action types
    let processedCount = 0;
    for (const action of selectedEvent.actions) {
      const getAssetId = () => {
        if (isPlayAction(action) || isFadeAction(action)) return action.assetId;
        if (isStopAction(action) || isPauseAction(action)) return action.assetId;
        return null;
      };
      rfDebug('Preview', 'Processing action:', action.type, 'assetId:', getAssetId());

      // Handle delay for all action types
      const executeAction = () => {
        if (isPlayAction(action)) {
          if (!action.assetId) {
            console.warn('[Preview] Play action has no assetId');
            return;
          }
          playAudioFile(action.assetId, {
            gain: action.gain,
            loop: action.loop,
            pan: action.pan,
            bus: action.bus,
          });
        } else if (isStopAction(action)) {
          // Stop specific asset or all if no assetId
          if (action.assetId) {
            stopAudioByAsset(action.assetId);
          } else {
            stopAllAudio();
          }
        } else if (isStopAllAction(action)) {
          stopAllAudio();
        } else if (isFadeAction(action)) {
          // Fade existing playback to target volume
          if (action.assetId) {
            const fadeDuration = action.duration ?? 0.5;
            fadeAudioAsset(action.assetId, action.targetVolume ?? 1.0, fadeDuration);
          }
        } else if (isPauseAction(action)) {
          // Pause = stop (WebAudio doesn't have native pause)
          if (action.assetId) {
            stopAudioByAsset(action.assetId);
          } else {
            stopAllAudio();
          }
        } else if (isSetBusGainAction(action)) {
          const busId = action.bus?.toLowerCase() || 'sfx';
          setBusStates(prev => prev.map(b =>
            b.id === busId ? { ...b, volume: (action.gain ?? 1.0) * 100 } : b
          ));
        }
        processedCount++;
      };

      const delay = 'delay' in action ? (action.delay ?? 0) : 0;
      if (delay > 0) {
        setTimeout(executeAction, delay * 1000);
      } else {
        executeAction();
      }
    }

    setConsoleMessages(prev => [...prev.slice(-49), {
      id: `preview-${Date.now()}`,
      level: 'info',
      message: `▶ Preview: ${selectedEvent.name} (${selectedEvent.actions.length} actions)`,
      timestamp: new Date(),
    }]);
  }, [selectedEvent, playAudioFile, stopAllAudio, stopAudioByAsset, fadeAudioAsset, importedAudioFiles, allowOverlap]);

  // Preview single action - handles ALL action types
  const handlePreviewAction = useCallback((action: RouteAction) => {
    if (isPlayAction(action)) {
      playAudioFile(action.assetId, {
        gain: action.gain,
        loop: action.loop,
        pan: action.pan,
        bus: action.bus,
      });
    } else if (isStopAction(action)) {
      // Stop specific asset or all
      if (action.assetId) {
        stopAudioByAsset(action.assetId);
      } else {
        stopAllAudio();
      }
    } else if (isStopAllAction(action)) {
      stopAllAudio();
    } else if (isFadeAction(action)) {
      // Fade existing playback to target volume
      if (action.assetId) {
        const fadeDuration = action.duration ?? 0.5;
        fadeAudioAsset(action.assetId, action.targetVolume ?? 1.0, fadeDuration);
      }
    } else if (isPauseAction(action)) {
      // Pause = stop (WebAudio doesn't have native pause)
      if (action.assetId) {
        stopAudioByAsset(action.assetId);
      } else {
        stopAllAudio();
      }
    } else if (isSetBusGainAction(action)) {
      // SetBusGain - update bus state visually
      const busId = action.bus?.toLowerCase() || 'sfx';
      setBusStates(prev => prev.map(b =>
        b.id === busId ? { ...b, volume: (action.gain ?? 1.0) * 100 } : b
      ));
      setConsoleMessages(prev => [...prev.slice(-49), {
        id: `busgain-${Date.now()}`,
        level: 'info',
        message: `🔊 SetBusGain: ${action.bus} → ${action.gain?.toFixed(2) ?? 1}`,
        timestamp: new Date(),
      }]);
    } else if (isExecuteAction(action)) {
      // Execute - call another event by ID
      if (action.eventId && routes) {
        const targetEvent = routes.events.find(e => e.name === action.eventId);
        if (targetEvent) {
          setConsoleMessages(prev => [...prev.slice(-49), {
            id: `exec-${Date.now()}`,
            level: 'info',
            message: `🎬 Execute: ${action.eventId}`,
            timestamp: new Date(),
          }]);
          // Execute all actions in target event
          targetEvent.actions.forEach(a => handlePreviewAction(a));
        } else {
          setConsoleMessages(prev => [...prev.slice(-49), {
            id: `exec-err-${Date.now()}`,
            level: 'error',
            message: `❌ Execute: Event "${action.eventId}" not found`,
            timestamp: new Date(),
          }]);
        }
      }
    }
  }, [playAudioFile, stopAllAudio, stopAudioByAsset, fadeAudioAsset, routes]);

  // ===== KEYBOARD SHORTCUTS =====
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      const isMac = navigator.platform.toUpperCase().indexOf('MAC') >= 0;
      const modKey = isMac ? e.metaKey : e.ctrlKey;

      // Ctrl/Cmd + S = Save
      if (modKey && e.key === 's' && !e.shiftKey) {
        e.preventDefault();
        saveProject();
        return;
      }

      // Ctrl/Cmd + Shift + S = Save As
      if (modKey && e.key === 's' && e.shiftKey) {
        e.preventDefault();
        saveProjectAs();
        return;
      }

      // Ctrl/Cmd + O = Open
      if (modKey && e.key === 'o') {
        e.preventDefault();
        openProject();
        return;
      }

      // Ctrl/Cmd + N = New Project
      if (modKey && e.key === 'n') {
        e.preventDefault();
        newProject('New Project', '');
        return;
      }

      // SPACE = Toggle preview (only in Middleware mode - DAW mode uses Space for transport)
      if (e.code === 'Space' && !modKey && editorMode === 'middleware') {
        const target = e.target as HTMLElement;
        const isInput = target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable;
        if (!isInput) {
          e.preventDefault();
          const activeSources = activeSourcesRef.current.size;
          // Toggle: if audio is playing, stop it; otherwise play preview
          if (activeSources > 0) {
            stopAllAudio();
          } else {
            handlePreviewEvent();
          }
          return;
        }
      }

      // L = Set loop region to selected clip(s) (Cubase-style)
      if (e.key === 'l' || e.key === 'L') {
        const target = e.target as HTMLElement;
        const isInput = target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable;
        if (!isInput && selectedClipIds.size > 0) {
          e.preventDefault();
          const selectedClips = storeClips.filter(c => selectedClipIds.has(c.id));
          if (selectedClips.length > 0) {
            const minStart = Math.min(...selectedClips.map(c => c.startTime));
            const maxEnd = Math.max(...selectedClips.map(c => c.startTime + c.duration));
            setLoopRegion({ start: minStart, end: maxEnd });
            logSlotEvent('TIMELINE', `Loop set to selection: ${minStart.toFixed(2)}s - ${maxEnd.toFixed(2)}s`);
          }
          return;
        }
      }

      // Escape = Stop all audio
      if (e.key === 'Escape') {
        e.preventDefault();
        stopAllAudio();
        return;
      }

      // Arrow keys for navigation (only if not in input)
      const target = e.target as HTMLElement;
      const isInput = target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable;
      if (isInput) return;

      // ArrowUp/ArrowDown = Navigate events or actions
      if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
        e.preventDefault();
        const events = routes?.events || [];

        if (selectedActionIndex !== null && selectedEvent) {
          // Navigate actions within selected event
          const actions = selectedEvent.actions;
          if (e.key === 'ArrowUp' && selectedActionIndex > 0) {
            setSelectedActionIndex(selectedActionIndex - 1);
          } else if (e.key === 'ArrowDown' && selectedActionIndex < actions.length - 1) {
            setSelectedActionIndex(selectedActionIndex + 1);
          }
        } else {
          // Navigate events
          const currentIdx = events.findIndex(ev => ev.name === selectedEventName);
          if (e.key === 'ArrowUp' && currentIdx > 0) {
            setSelectedEventName(events[currentIdx - 1].name);
            setSelectedActionIndex(null);
          } else if (e.key === 'ArrowDown' && currentIdx < events.length - 1) {
            setSelectedEventName(events[currentIdx + 1].name);
            setSelectedActionIndex(null);
          } else if (currentIdx === -1 && events.length > 0) {
            setSelectedEventName(events[0].name);
          }
        }
        return;
      }

      // ArrowLeft = Go back to event list (deselect action)
      if (e.key === 'ArrowLeft' && selectedActionIndex !== null) {
        e.preventDefault();
        setSelectedActionIndex(null);
        return;
      }

      // ArrowRight or Enter = Select first action in event
      if ((e.key === 'ArrowRight' || e.key === 'Enter') && selectedEvent && selectedActionIndex === null) {
        e.preventDefault();
        if (selectedEvent.actions.length > 0) {
          setSelectedActionIndex(0);
        }
        return;
      }

      // Delete or Backspace = Delete selected action(s)
      if ((e.key === 'Delete' || e.key === 'Backspace')) {
        if (selectedActionIndices.size > 1) {
          // Bulk delete
          e.preventDefault();
          handleBulkDeleteActions();
          return;
        } else if (selectedActionIndex !== null) {
          // Single delete
          e.preventDefault();
          handleDeleteAction(selectedActionIndex);
          return;
        }
      }

      // Ctrl/Cmd + D = Duplicate selected action
      if (modKey && e.key === 'd' && selectedActionIndex !== null && selectedEvent) {
        e.preventDefault();
        const actionToDuplicate = selectedEvent.actions[selectedActionIndex];
        if (actionToDuplicate && workingRoutes) {
          const newAction = { ...actionToDuplicate };
          const updatedEvents = workingRoutes.events.map(ev => {
            if (ev.name === selectedEventName) {
              const newActions = [...ev.actions];
              newActions.splice(selectedActionIndex + 1, 0, newAction);
              return { ...ev, actions: newActions };
            }
            return ev;
          });
          setWorkingRoutes({ ...workingRoutes, events: updatedEvents });
          setSelectedActionIndex(selectedActionIndex + 1);
          logSlotEvent('EDIT', `Duplicated action ${selectedActionIndex + 1}`);
        }
        return;
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [saveProject, saveProjectAs, openProject, newProject, handlePreviewEvent, stopAllAudio, routes, selectedEventName, selectedEvent, selectedActionIndex, selectedActionIndices, handleDeleteAction, handleBulkDeleteActions, workingRoutes, setWorkingRoutes, logSlotEvent, editorMode, selectedClipIds, storeClips, setLoopRegion]);

  // Slot spin simulation
  const runSlotSimulation = useCallback(() => {
    if (isSlotSimulating) return;

    setIsSlotSimulating(true);
    logSlotEvent('SPIN_START', 'Simulation started');

    const sequence: { state: SpinState; delay: number }[] = [
      { state: 'spin_start', delay: 0 },
      { state: 'reels_spinning', delay: 200 },
      { state: 'reel_stop_1', delay: 800 },
      { state: 'reel_stop_2', delay: 1100 },
      { state: 'reel_stop_3', delay: 1400 },
      { state: 'reel_stop_4', delay: 1700 },
      { state: 'reel_stop_5', delay: 2000 },
      { state: 'evaluation', delay: 2200 },
    ];

    const isWin = Math.random() > 0.4;
    const winMultiplier = isWin ? Math.floor(Math.random() * 120) + 1 : 0;

    if (isWin) {
      sequence.push({ state: 'win', delay: 2400 });
    } else {
      sequence.push({ state: 'lose', delay: 2400 });
    }
    sequence.push({ state: 'idle', delay: isWin ? 5000 : 3000 });

    sequence.forEach(({ state, delay }) => {
      setTimeout(() => {
        setCurrentSpinState(state);
        logSlotEvent('STATE_CHANGE', state.toUpperCase());

        if (state === 'win' && winMultiplier > 0) {
          const tier = winTiers.find(
            (t) => winMultiplier >= t.minMultiplier && winMultiplier < t.maxMultiplier
          );
          if (tier) {
            setActiveTier(tier.tier);
            logSlotEvent('WIN_TIER', `${tier.tier.toUpperCase()} (${winMultiplier}x)`);
          }
        }

        if (state === 'idle') {
          setIsSlotSimulating(false);
          setActiveTier(null);
          logSlotEvent('SPIN_END', 'Simulation complete');
        }
      }, delay);
    });
  }, [isSlotSimulating, winTiers, logSlotEvent]);

  // Reel sequencer playback
  useEffect(() => {
    if (!isSequencerPlaying) return;

    const totalDuration = 2500;
    const startTime = Date.now() - sequencerTime;

    const interval = setInterval(() => {
      const elapsed = Date.now() - startTime;
      if (elapsed >= totalDuration) {
        setSequencerTime(0);
        setIsSequencerPlaying(false);
        logSlotEvent('SEQUENCER_STOP', 'Playback complete');
      } else {
        setSequencerTime(elapsed);
        reelConfigs.forEach((reel) => {
          if (Math.abs(elapsed - reel.stopTime) < 20) {
            logSlotEvent(`REEL_${reel.reelIndex + 1}_STOP`, `${reel.stopTime}ms`);
          }
        });
      }
    }, 16);

    return () => clearInterval(interval);
  }, [isSequencerPlaying, sequencerTime, reelConfigs, logSlotEvent]);

  // NOTE: Playback timing is now handled by useTimelinePlayback hook
  // The old interval-based simulation has been replaced with real Web Audio API playback
  // Time updates come via onTimeUpdate callback from the playback hook

  // NOTE: Meter animation is now handled by useSimulatedBusMeter hook
  // The old interval-based animation has been removed to avoid conflicts
  // busStatesWithMeters.meterLevel is updated from meterLevels.get(bus.id)?.peak

  // Handlers
  const handlePlay = useCallback(() => {
    if (isPlaying) {
      playbackPause();
    } else {
      playbackPlay();
    }
  }, [isPlaying, playbackPlay, playbackPause]);

  const handleStop = useCallback(() => {
    // Stop timeline playback (stops all scheduled clips)
    playbackStop();
    // Also stop any preview audio
    stopAllAudio();
  }, [playbackStop, stopAllAudio]);

  const handleRecord = useCallback(() => {
    setIsRecording((r) => !r);
    if (!isRecording) {
      setConsoleMessages((msgs) => [
        ...msgs,
        { id: Date.now().toString(), level: 'warn', message: 'Recording armed', timestamp: new Date() },
      ]);
    }
  }, [isRecording]);

  // Bus handlers - use local state for mixer preview
  const [busStates, setBusStates] = useState(DEMO_BUSES);

  // Plugin picker state
  const [pluginPickerState, setPluginPickerState] = useState<{
    isOpen: boolean;
    busId: string;
    slotIndex: number;
    currentInsert: { id: string; name: string; bypassed?: boolean } | null;
    position: { x: number; y: number };
  } | null>(null);

  // Track if any audio is playing for meter simulation
  const hasActiveAudio = activeAudioCount > 0;

  // NOTE: Meter animation is now handled by MixerTabContent component
  // which has its own useSimulatedBusMeter hook - this avoids useMemo caching issues

  const handleBusVolumeChange = useCallback((busId: string, newVolume: number) => {
    // Get old volume for undo
    const oldVolume = busStates.find(b => b.id === busId)?.volume ?? 1;
    const busName = busStates.find(b => b.id === busId)?.name ?? busId;
    const isMuted = busStates.find(b => b.id === busId)?.muted ?? false;

    // Helper to update DSP gain with click-free ramp
    const updateDspGain = (volume: number) => {
      const busGain = busGainsRef.current[busId];
      if (busGain && audioContextRef.current) {
        const ctx = audioContextRef.current;
        const now = ctx.currentTime;
        // Only apply gain if not muted
        const targetGain = isMuted ? 0 : volume;
        busGain.gain.cancelScheduledValues(now);
        busGain.gain.setValueAtTime(busGain.gain.value, now);
        busGain.gain.linearRampToValueAtTime(targetGain, now + 0.01);
      }
    };

    // Execute via UndoManager for undo/redo support
    UndoManager.execute({
      id: `bus-volume-${busId}-${Date.now()}`,
      timestamp: Date.now(),
      description: `Set ${busName} volume to ${Math.round(newVolume * 100)}%`,
      execute: () => {
        setBusStates((prev) => prev.map((b) => (b.id === busId ? { ...b, volume: newVolume } : b)));
        updateDspGain(newVolume);
      },
      undo: () => {
        setBusStates((prev) => prev.map((b) => (b.id === busId ? { ...b, volume: oldVolume } : b)));
        updateDspGain(oldVolume);
      },
    });
  }, [busStates]);

  const handleBusMuteToggle = useCallback((busId: string) => {
    const wasMuted = busStates.find(b => b.id === busId)?.muted ?? false;
    const busVolume = busStates.find(b => b.id === busId)?.volume ?? 1;
    const busName = busStates.find(b => b.id === busId)?.name ?? busId;

    // Helper to update DSP gain with click-free ramp
    const updateDspGain = (muted: boolean) => {
      const busGain = busGainsRef.current[busId];
      if (busGain && audioContextRef.current) {
        const ctx = audioContextRef.current;
        const now = ctx.currentTime;
        const targetGain = muted ? 0 : busVolume;
        busGain.gain.cancelScheduledValues(now);
        busGain.gain.setValueAtTime(busGain.gain.value, now);
        busGain.gain.linearRampToValueAtTime(targetGain, now + 0.01);
      }
    };

    UndoManager.execute({
      id: `bus-mute-${busId}-${Date.now()}`,
      timestamp: Date.now(),
      description: `${wasMuted ? 'Unmute' : 'Mute'} ${busName}`,
      execute: () => {
        setBusStates((prev) => prev.map((b) => (b.id === busId ? { ...b, muted: !wasMuted } : b)));
        updateDspGain(!wasMuted);
      },
      undo: () => {
        setBusStates((prev) => prev.map((b) => (b.id === busId ? { ...b, muted: wasMuted } : b)));
        updateDspGain(wasMuted);
      },
    });
  }, [busStates]);

  const handleBusSoloToggle = useCallback((busId: string) => {
    const wasSoloed = busStates.find(b => b.id === busId)?.soloed ?? false;
    const busName = busStates.find(b => b.id === busId)?.name ?? busId;

    UndoManager.execute({
      id: `bus-solo-${busId}-${Date.now()}`,
      timestamp: Date.now(),
      description: `${wasSoloed ? 'Unsolo' : 'Solo'} ${busName}`,
      execute: () => {
        setBusStates((prev) => prev.map((b) => (b.id === busId ? { ...b, soloed: !wasSoloed } : b)));
      },
      undo: () => {
        setBusStates((prev) => prev.map((b) => (b.id === busId ? { ...b, soloed: wasSoloed } : b)));
      },
    });
  }, [busStates]);

  const handleBusPanChange = useCallback((busId: string, newPan: number) => {
    const oldPan = busStates.find(b => b.id === busId)?.pan ?? 0;
    const busName = busStates.find(b => b.id === busId)?.name ?? busId;

    // Helper to update DSP panner with smooth ramp
    const updateDspPan = (pan: number) => {
      const busPanner = busPannersRef.current[busId];
      if (busPanner && audioContextRef.current) {
        const ctx = audioContextRef.current;
        const now = ctx.currentTime;
        busPanner.pan.cancelScheduledValues(now);
        busPanner.pan.setValueAtTime(busPanner.pan.value, now);
        busPanner.pan.linearRampToValueAtTime(pan, now + 0.01);
      }
    };

    UndoManager.execute({
      id: `bus-pan-${busId}-${Date.now()}`,
      timestamp: Date.now(),
      description: `Set ${busName} pan to ${newPan > 0 ? 'R' : newPan < 0 ? 'L' : 'C'}${Math.abs(Math.round(newPan * 100))}`,
      execute: () => {
        setBusStates((prev) => prev.map((b) => (b.id === busId ? { ...b, pan: newPan } : b)));
        updateDspPan(newPan);
      },
      undo: () => {
        setBusStates((prev) => prev.map((b) => (b.id === busId ? { ...b, pan: oldPan } : b)));
        updateDspPan(oldPan);
      },
    });
  }, [busStates]);

  const handleInsertClick = useCallback((busId: string, slotIndex: number, insert: { id: string; name: string; bypassed?: boolean } | null, event?: React.MouseEvent) => {
    const busName = busStates.find(b => b.id === busId)?.name ?? busId;

    // If clicking on existing insert, check if it should open in window
    if (insert && insert.id) {
      // Get pluginId from zustand store (insert.id is format "ins_timestamp_random")
      // For master bus, look in masterChain; for other buses, look in busChains
      let pluginId: string | undefined;
      if (busId === 'master') {
        const masterChain = useReelForgeStore.getState().masterChain;
        const masterInsert = masterChain.inserts.find(ins => ins.id === insert.id);
        pluginId = masterInsert?.pluginId;
      } else {
        const busChains = useReelForgeStore.getState().busChains;
        const busChain = busChains[busId as keyof typeof busChains];
        const busInsert = busChain?.inserts?.find(ins => ins.id === insert.id);
        pluginId = busInsert?.pluginId;
      }

      console.debug('[LayoutDemo] Insert clicked:', { busId, slotIndex, insertId: insert.id, pluginId });

      // Check if this plugin has an Editor (VanEQ, VanComp, VanLimit)
      const pluginDef = pluginId ? getPluginDefinition(pluginId) : null;
      if (pluginId && pluginDef?.Editor) {
        console.debug('[LayoutDemo] Opening plugin editor:', pluginId);

        // Build params from store or defaults
        let params: Record<string, number> = {};
        if (busId === 'master') {
          const masterChain = useReelForgeStore.getState().masterChain;
          const masterInsert = masterChain.inserts.find(ins => ins.id === insert.id);
          if (masterInsert) {
            params = masterInsert.params as unknown as Record<string, number>;
          }
        } else {
          const busChains = useReelForgeStore.getState().busChains;
          const busChain = busChains[busId as keyof typeof busChains];
          const busInsert = busChain?.inserts?.find(ins => ins.id === insert.id);
          if (busInsert) {
            params = busInsert.params as unknown as Record<string, number>;
          }
        }
        // Fallback to defaults if no params found
        if (Object.keys(params).length === 0) {
          pluginDef.params?.forEach((p) => {
            params[p.id] = p.default;
          });
        }

        const selection: InsertSelection = {
          scope: busId === 'master' ? 'master' : 'bus',
          insertId: insert.id,
          pluginId: pluginId as InsertSelection['pluginId'],
          params,
          bypassed: insert.bypassed ?? false,
        };

        // Create callbacks based on bus type
        let handleParamChange: (paramId: string, value: number) => void;
        let handleParamReset: (_paramId: string) => void;
        let handleBypassChange: (bypassed: boolean) => void;

        if (busId === 'master') {
          // Real callbacks for master bus using zustand store
          handleParamChange = (paramId: string, value: number) => {
            console.debug('[LayoutDemo] Master param change:', { insertId: insert.id, paramId, value });
            updateMasterParams(insert.id, { [paramId]: value } as Parameters<typeof updateMasterParams>[1]);
          };
          handleParamReset = (_paramId: string) => {
            console.debug('[LayoutDemo] Master param reset');
          };
          handleBypassChange = (_bypassed: boolean) => {
            console.debug('[LayoutDemo] Master bypass change');
            toggleMasterBypass(insert.id);
          };
        } else {
          // Dummy callbacks for non-master buses (demo only)
          handleParamChange = (paramId: string, value: number) => {
            console.debug('[LayoutDemo] Param change:', { paramId, value });
          };
          handleParamReset = (_paramId: string) => {
            console.debug('[LayoutDemo] Param reset');
          };
          handleBypassChange = () => {
            console.debug('[LayoutDemo] Bypass change');
          };
        }

        // Trigger plugin editor opening via InsertSelectionContext
        selectInsert(selection);
        setCallbacks(handleParamChange, handleParamReset, handleBypassChange);

        logSlotEvent('INSERT', `${busName} slot ${slotIndex + 1}: Opening ${insert.name}`);
        return;
      }
    }

    // Get click position for popup placement
    const position = event
      ? { x: event.clientX, y: event.clientY }
      : { x: window.innerWidth / 2 - 150, y: 200 };

    // Open plugin picker (for empty slots or non-window plugins)
    setPluginPickerState({
      isOpen: true,
      busId,
      slotIndex,
      currentInsert: insert,
      position,
    });

    logSlotEvent('INSERT', `${busName} slot ${slotIndex + 1}: ${insert ? `Editing ${insert.name}` : 'Adding insert'}`);
  }, [busStates, logSlotEvent, selectInsert, setCallbacks, updateMasterParams, toggleMasterBypass]);

  // Plugin selection handler
  const handlePluginSelect = useCallback((plugin: PluginDefinition) => {
    if (!pluginPickerState) return;

    const { busId, slotIndex } = pluginPickerState;
    const busName = busStates.find(b => b.id === busId)?.name ?? busId;

    // For MASTER bus, use zustand store (connects to DSP chain)
    // For other buses, use local state (demo only)
    if (busId === 'master') {
      console.log('[LayoutDemo] Adding master insert via zustand:', plugin.id);

      // Add insert via zustand store - this triggers DSP chain sync
      addMasterInsert(plugin.id as Parameters<typeof addMasterInsert>[0]);

      logSlotEvent('INSERT', `${busName} slot ${slotIndex + 1}: Added ${plugin.name}`);
      setPluginPickerState(null);

      // If this plugin opens in window, open it after zustand state update
      if (shouldOpenInWindow(plugin.id)) {
        console.debug('[LayoutDemo] Auto-opening plugin window after add:', plugin.id);

        // Build params from defaults
        const pluginDef = getPluginDefinition(plugin.id);
        const params: Record<string, number> = {};
        pluginDef?.params?.forEach((p) => {
          params[p.id] = p.default;
        });

        // Wait for zustand state to propagate and get the new insert ID
        setTimeout(() => {
          // Get the latest insert from zustand store (fresh read to avoid stale closure)
          const currentMasterChain = useReelForgeStore.getState().masterChain;
          const latestInsert = currentMasterChain.inserts[currentMasterChain.inserts.length - 1];
          const insertId = latestInsert?.id ?? `${plugin.id}-${Date.now()}`;

          console.log('[LayoutDemo] Opening plugin window for insert:', insertId, 'chain has', currentMasterChain.inserts.length, 'inserts');

          const selection: InsertSelection = {
            scope: 'master',
            insertId,
            pluginId: plugin.id as InsertSelection['pluginId'],
            params,
            bypassed: false,
          };

          // Real callbacks that update zustand store
          const handleParamChange = (paramId: string, value: number) => {
            console.debug('[LayoutDemo] Master param change:', { insertId, paramId, value });
            updateMasterParams(insertId, { [paramId]: value } as Parameters<typeof updateMasterParams>[1]);
          };
          const handleParamReset = (_paramId: string) => {
            console.debug('[LayoutDemo] Master param reset');
          };
          const handleBypassChange = (bypassed: boolean) => {
            console.debug('[LayoutDemo] Master bypass change:', bypassed);
            toggleMasterBypass(insertId);
          };

          selectInsert(selection);
          setCallbacks(handleParamChange, handleParamReset, handleBypassChange);
        }, 100); // Slightly longer delay to ensure zustand state is updated
      }

      // Also update local busStates for UI display
      // Get the real insert ID from zustand store (synchronous - just created above)
      const currentChain = useReelForgeStore.getState().masterChain;
      const newInsert = currentChain.inserts[currentChain.inserts.length - 1];
      const insertId = newInsert?.id ?? `${plugin.id}-${Date.now()}`;

      setBusStates((prev) =>
        prev.map((b) => {
          if (b.id !== 'master') return b;
          const newInserts = [...(b.inserts || [])];
          while (newInserts.length <= slotIndex) {
            newInserts.push({ id: '', name: '', type: 'custom' as const });
          }
          newInserts[slotIndex] = {
            id: insertId,
            name: plugin.name,
            type: plugin.category === 'eq' ? 'eq' : plugin.category === 'dynamics' ? 'comp' : 'custom',
          };
          return { ...b, inserts: newInserts };
        })
      );

      return;
    }

    // Non-master buses: use local state only (demo)
    const insertId = `${plugin.id}-${Date.now()}`;

    // Update bus inserts
    setBusStates((prev) =>
      prev.map((b) => {
        if (b.id !== busId) return b;

        const newInserts = [...(b.inserts || [])];
        // Ensure array has enough slots
        while (newInserts.length <= slotIndex) {
          newInserts.push({ id: '', name: '', type: 'custom' as const });
        }
        // Set the new plugin - map category to insert type
        const categoryToType: Record<string, BusInsertSlot['type']> = {
          eq: 'eq',
          dynamics: 'comp',
          filter: 'filter',
          modulation: 'fx',
          utility: 'utility',
        };
        newInserts[slotIndex] = {
          id: insertId,
          name: plugin.name,
          type: categoryToType[plugin.category] ?? 'custom',
        };
        return { ...b, inserts: newInserts };
      })
    );

    logSlotEvent('INSERT', `${busName} slot ${slotIndex + 1}: Added ${plugin.name}`);
    setPluginPickerState(null);

    // If this plugin opens in window, open it immediately after adding
    if (shouldOpenInWindow(plugin.id)) {
      console.debug('[LayoutDemo] Auto-opening plugin window after add:', plugin.id);

      // Build params from defaults - get from registry
      const pluginDef = getPluginDefinition(plugin.id);
      const params: Record<string, number> = {};
      pluginDef?.params?.forEach((p) => {
        params[p.id] = p.default;
      });

      const selection: InsertSelection = {
        scope: 'bus',
        insertId: insertId,
        pluginId: plugin.id as InsertSelection['pluginId'],
        params,
        bypassed: false,
      };

      // Create dummy callbacks for non-master buses
      const handleParamChange = (paramId: string, value: number) => {
        console.debug('[LayoutDemo] Param change:', { paramId, value });
      };
      const handleParamReset = (_paramId: string) => {
        console.debug('[LayoutDemo] Param reset');
      };
      const handleBypassChange = () => {
        console.debug('[LayoutDemo] Bypass change');
      };

      // Use setTimeout to ensure state update has propagated
      setTimeout(() => {
        selectInsert(selection);
        setCallbacks(handleParamChange, handleParamReset, handleBypassChange);
      }, 50);
    }
  }, [pluginPickerState, busStates, logSlotEvent, selectInsert, setCallbacks, addMasterInsert, updateMasterParams, toggleMasterBypass]);

  // Remove insert handler
  const handleInsertRemove = useCallback(() => {
    if (!pluginPickerState) return;

    const { busId, slotIndex } = pluginPickerState;
    const busName = busStates.find(b => b.id === busId)?.name ?? busId;
    const insertName = pluginPickerState.currentInsert?.name ?? 'insert';
    const insertId = pluginPickerState.currentInsert?.id;

    // For master bus, also remove from zustand store
    if (busId === 'master' && insertId) {
      console.log('[LayoutDemo] Removing master insert via zustand:', insertId);
      removeMasterInsert(insertId);
    }

    setBusStates((prev) =>
      prev.map((b) => {
        if (b.id !== busId) return b;

        const newInserts = [...(b.inserts || [])];
        // Remove the insert by setting to empty or splicing
        if (slotIndex < newInserts.length) {
          newInserts.splice(slotIndex, 1);
        }
        return { ...b, inserts: newInserts };
      })
    );

    logSlotEvent('INSERT', `${busName} slot ${slotIndex + 1}: Removed ${insertName}`);
    setPluginPickerState(null);
  }, [pluginPickerState, busStates, logSlotEvent, removeMasterInsert]);

  // Toggle insert bypass handler
  const handleInsertBypassToggle = useCallback(() => {
    if (!pluginPickerState || !pluginPickerState.currentInsert) return;

    const { busId, slotIndex } = pluginPickerState;
    const busName = busStates.find(b => b.id === busId)?.name ?? busId;

    setBusStates((prev) =>
      prev.map((b) => {
        if (b.id !== busId) return b;

        const newInserts = [...(b.inserts || [])];
        if (slotIndex < newInserts.length && newInserts[slotIndex]) {
          newInserts[slotIndex] = {
            ...newInserts[slotIndex],
            bypassed: !newInserts[slotIndex].bypassed,
          };
        }
        return { ...b, inserts: newInserts };
      })
    );

    const newBypassState = !pluginPickerState.currentInsert.bypassed;
    logSlotEvent('INSERT', `${busName} slot ${slotIndex + 1}: ${pluginPickerState.currentInsert.name} ${newBypassState ? 'bypassed' : 'enabled'}`);

    // Update picker state to reflect change
    setPluginPickerState((prev) =>
      prev ? { ...prev, currentInsert: prev.currentInsert ? { ...prev.currentInsert, bypassed: newBypassState } : null } : null
    );
  }, [pluginPickerState, busStates, logSlotEvent]);

  // Direct bypass toggle from mixer strip (without opening picker)
  const handleDirectInsertBypass = useCallback((busId: string, slotIndex: number, insert: { id: string; name: string; bypassed?: boolean }) => {
    const busName = busStates.find(b => b.id === busId)?.name ?? busId;
    const newBypassState = !insert.bypassed;

    setBusStates((prev) =>
      prev.map((b) => {
        if (b.id !== busId) return b;

        const newInserts = [...(b.inserts || [])];
        if (slotIndex < newInserts.length && newInserts[slotIndex]) {
          newInserts[slotIndex] = {
            ...newInserts[slotIndex],
            bypassed: newBypassState,
          };
        }
        return { ...b, inserts: newInserts };
      })
    );

    logSlotEvent('INSERT', `${busName} slot ${slotIndex + 1}: ${insert.name} ${newBypassState ? 'bypassed' : 'enabled'}`);
  }, [busStates, logSlotEvent]);

  // Close plugin picker
  const handlePluginPickerClose = useCallback(() => {
    setPluginPickerState(null);
  }, []);

  const handleClipSelect = useCallback((clipId: string, multiSelect?: boolean) => {
    if (multiSelect) {
      // Shift+click: add/remove from selection
      setSelectedClipIds(prev => {
        const newSet = new Set(prev);
        if (newSet.has(clipId)) {
          newSet.delete(clipId);
          // If deselecting current primary, update it
          if (selectedClipId === clipId) {
            setSelectedClipId(newSet.size > 0 ? Array.from(newSet)[0] : null);
          }
        } else {
          newSet.add(clipId);
          setSelectedClipId(clipId); // Make it primary
        }
        return newSet;
      });
    } else {
      // Regular click: single selection
      setSelectedClipId(clipId);
      setSelectedClipIds(new Set([clipId]));
    }

    logSlotEvent('TIMELINE', `Selected clip: ${clipId}`);
  }, [logSlotEvent, selectedClipId]);

  const handleTrackMuteToggle = useCallback((trackId: string) => {
    const track = storeTracks.find(t => t.id === trackId);
    if (track) {
      updateTrack(trackId, { muted: !track.muted });
    }
  }, [storeTracks, updateTrack]);

  const handleTrackSoloToggle = useCallback((trackId: string) => {
    const track = storeTracks.find(t => t.id === trackId);
    if (track) {
      updateTrack(trackId, { solo: !track.solo });
    }
  }, [storeTracks, updateTrack]);

  // Handle track color change
  const handleTrackColorChange = useCallback((trackId: string, color: string) => {
    updateTrack(trackId, { color });
  }, [updateTrack]);

  // Handle track rename (double-click)
  const handleTrackRename = useCallback((trackId: string, newName: string) => {
    updateTrack(trackId, { name: newName });
    logSlotEvent('TIMELINE', `Renamed track to "${newName}"`);
  }, [updateTrack, logSlotEvent]);

  // Handle clip rename (double-click)
  const handleClipRename = useCallback((clipId: string, newName: string) => {
    const clip = storeClips.find(c => c.id === clipId);
    if (clip) {
      updateClip(clip.trackId, clipId, { name: newName });
      logSlotEvent('TIMELINE', `Renamed clip to "${newName}"`);
    }
  }, [storeClips, updateClip, logSlotEvent]);

  // Handle track bus routing change
  const handleTrackBusChange = useCallback((trackId: string, outputBus: 'master' | 'music' | 'sfx' | 'ambience' | 'voice') => {
    updateTrack(trackId, { outputBus });
    console.log(`[DAW] Track ${trackId} routed to ${outputBus} bus`);
  }, [updateTrack]);

  // Handle clip gain change
  const handleClipGainChange = useCallback((clipId: string, gain: number) => {
    const clip = storeClips.find(c => c.id === clipId);
    if (clip) {
      updateClip(clip.trackId, clipId, { gain });
    }
  }, [storeClips, updateClip]);

  // Handle clip fade change
  const handleClipFadeChange = useCallback((clipId: string, fadeIn: number, fadeOut: number) => {
    const clip = storeClips.find(c => c.id === clipId);
    if (clip) {
      updateClip(clip.trackId, clipId, { fadeIn, fadeOut });
    }
  }, [storeClips, updateClip]);

  // Handle clip split at time
  const handleClipSplit = useCallback((clipId: string, splitTime: number) => {
    const clip = storeClips.find(c => c.id === clipId);
    if (!clip) return;

    // Calculate relative split position
    const relativeTime = splitTime - clip.startTime;
    if (relativeTime <= 0 || relativeTime >= clip.duration) return;

    // Update original clip (first part)
    updateClip(clip.trackId, clipId, {
      duration: relativeTime,
      fadeOut: 0, // Remove fade out from first part
    });

    // Create second clip
    const secondClip: ClipState = {
      id: `clip-${Date.now()}`,
      trackId: clip.trackId,
      name: `${clip.name} (2)`,
      startTime: splitTime,
      duration: clip.duration - relativeTime,
      offset: (clip.offset ?? 0) + relativeTime,
      sourceDuration: clip.sourceDuration, // Preserve original source duration
      fadeIn: 0, // No fade in on second part
      fadeOut: clip.fadeOut ?? 0,
      gain: clip.gain ?? 1,
      audioFileId: clip.audioFileId,
      color: clip.color,
    };
    addClip(clip.trackId, secondClip);
  }, [storeClips, updateClip, addClip]);

  // Handle clip duplicate
  const handleClipDuplicate = useCallback((clipId: string) => {
    const clip = storeClips.find(c => c.id === clipId);
    if (!clip) return;

    const duplicateClip: ClipState = {
      ...clip,
      id: `clip-${Date.now()}`,
      name: `${clip.name} (copy)`,
      startTime: clip.startTime + clip.duration, // Place after original
    };
    addClip(clip.trackId, duplicateClip);
  }, [storeClips, addClip]);

  // Handle clip delete (deletes all selected clips if multi-selected)
  const handleClipDelete = useCallback((clipId: string) => {
    // If the deleted clip is in selection and there are multiple, delete all selected
    if (selectedClipIds.has(clipId) && selectedClipIds.size > 1) {
      selectedClipIds.forEach(id => {
        const clip = storeClips.find(c => c.id === id);
        if (clip) {
          removeClip(clip.trackId, id);
        }
      });
      setSelectedClipIds(new Set());
      setSelectedClipId(null);
    } else {
      // Single delete
      const clip = storeClips.find(c => c.id === clipId);
      if (clip) {
        removeClip(clip.trackId, clipId);
        setSelectedClipIds(prev => {
          const newSet = new Set(prev);
          newSet.delete(clipId);
          return newSet;
        });
        if (selectedClipId === clipId) {
          setSelectedClipId(null);
        }
      }
    }
  }, [storeClips, removeClip, selectedClipIds, selectedClipId]);

  // Clipboard state for copy/paste
  const clipboardRef = useRef<ClipState | null>(null);

  // Handle clip copy
  const handleClipCopy = useCallback((clipId: string) => {
    const clip = storeClips.find(c => c.id === clipId);
    if (clip) {
      clipboardRef.current = { ...clip };
      console.log(`[DAW] Copied clip: ${clip.name}`);
    }
  }, [storeClips]);

  // Handle clip paste at playhead position
  const handleClipPaste = useCallback(() => {
    const clip = clipboardRef.current;
    if (!clip) return;

    // Find selected track or use original track
    const selectedTrack = storeTracks.find(t => t.id === selectedTrackId) || storeTracks.find(t => t.id === clip.trackId);
    if (!selectedTrack) return;

    const pastedClip: ClipState = {
      ...clip,
      id: `clip-${Date.now()}`,
      trackId: selectedTrack.id,
      startTime: currentTime, // Paste at playhead
    };
    addClip(selectedTrack.id, pastedClip);
    console.log(`[DAW] Pasted clip: ${clip.name} at ${currentTime.toFixed(2)}s`);
  }, [storeTracks, selectedTrackId, currentTime, addClip]);

  // Handle clip move (nudge)
  const handleClipMove = useCallback((clipId: string, newStartTime: number) => {
    const clip = storeClips.find(c => c.id === clipId);
    if (clip) {
      updateClip(clip.trackId, clipId, { startTime: newStartTime });
    }
  }, [storeClips, updateClip]);

  // Handle clip resize (trim edges)
  // newOffset is provided for left-edge trim (Cubase behavior)
  const handleClipResize = useCallback((clipId: string, newStartTime: number, newDuration: number, newOffset?: number) => {
    const clip = storeClips.find(c => c.id === clipId);
    if (clip) {
      const updates: Partial<ClipState> = {
        startTime: newStartTime,
        duration: newDuration,
      };
      // Only update offset if provided (left-edge trim)
      if (newOffset !== undefined) {
        updates.offset = newOffset;
      }
      updateClip(clip.trackId, clipId, updates);
    }
  }, [storeClips, updateClip]);

  // Handle audio drop on timeline track
  const handleTimelineAudioDrop = useCallback((trackId: string, time: number, audioItem: DragItem) => {
    // Find the audio file from imported files
    const audioFile = importedAudioFiles.find(f => `audio-${f.id}` === audioItem.id);
    const trackColor = storeTracks.find(t => t.id === trackId)?.color || '#4a9eff';

    console.log('[AudioDrop] Dropping audio:', {
      audioItemId: audioItem.id,
      foundFile: !!audioFile,
      fileName: audioFile?.name,
      fileDuration: audioFile?.duration,
      bufferDuration: audioFile?.buffer?.duration,
      sourceOffset: audioFile?.sourceOffset,
    });

    if (audioFile) {
      // Create new clip from dropped audio
      // CRITICAL: Use buffer.duration for accurate audio length (not audioFile.duration which may be stale)
      const actualDuration = audioFile.buffer?.duration ?? audioFile.duration;

      const newClip: ClipState = {
        id: `clip-${Date.now()}`,
        trackId,
        name: audioFile.name,
        startTime: time,
        duration: actualDuration,
        offset: 0,
        sourceDuration: actualDuration, // Immutable source duration
        fadeIn: 0,
        fadeOut: 0,
        gain: 1,
        audioFileId: audioFile.id,
        color: trackColor,
      };

      console.log('[AudioDrop] Creating clip:', {
        clipDuration: newClip.duration,
        sourceDuration: newClip.sourceDuration,
        bufferDuration: audioFile.buffer?.duration,
        waveformLength: audioFile.waveform?.length,
      });

      addClip(trackId, newClip);
      logSlotEvent('TIMELINE', `Added "${audioFile.name}" to ${trackId} at ${time.toFixed(2)}s (${audioFile.duration.toFixed(2)}s)`);
    } else {
      // Handle demo sounds from D&D Lab
      const demoDuration = 2; // Default duration for demo sounds
      const newClip: ClipState = {
        id: `clip-${Date.now()}`,
        trackId,
        name: audioItem.label,
        startTime: time,
        duration: demoDuration,
        offset: 0,
        sourceDuration: demoDuration,
        fadeIn: 0,
        fadeOut: 0,
        gain: 1,
        color: trackColor,
      };

      addClip(trackId, newClip);
      logSlotEvent('TIMELINE', `Added "${audioItem.label}" to ${trackId} at ${time.toFixed(2)}s`);
    }
  }, [importedAudioFiles, storeTracks, addClip, logSlotEvent]);

  // Handle audio drop to create a new track (when dropped on empty area or "new track" zone)
  const handleTimelineNewTrackDrop = useCallback((time: number, audioItem: DragItem) => {
    // Find the audio file from imported files
    const audioFile = importedAudioFiles.find(f => `audio-${f.id}` === audioItem.id);

    console.log('[NewTrackDrop] Creating new track:', {
      audioItemId: audioItem.id,
      foundFile: !!audioFile,
      fileName: audioFile?.name,
      fileDuration: audioFile?.duration,
      bufferDuration: audioFile?.buffer?.duration,
    });

    // Create new track with unique ID
    const trackNumber = storeTracks.length + 1;
    const newTrackId = `track-${Date.now()}`;
    const trackColor = TRACK_COLORS[(trackNumber - 1) % TRACK_COLORS.length];
    const trackName = audioFile ? audioFile.name.replace(/\.[^/.]+$/, '') : `Track ${trackNumber}`;

    // Add new track to store
    addTrack({
      id: newTrackId,
      name: trackName,
      color: trackColor,
      type: 'audio',
      volume: 1,
      pan: 0,
      muted: false,
      solo: false,
      armed: false,
    });

    // Create clip on new track
    if (audioFile) {
      // CRITICAL: Use buffer.duration for accurate audio length
      const actualDuration = audioFile.buffer?.duration ?? audioFile.duration;

      const newClip: ClipState = {
        id: `clip-${Date.now()}`,
        trackId: newTrackId,
        name: audioFile.name,
        startTime: time,
        duration: actualDuration,
        offset: 0,
        sourceDuration: actualDuration, // Immutable source duration
        fadeIn: 0,
        fadeOut: 0,
        gain: 1,
        audioFileId: audioFile.id,
        color: trackColor,
      };

      console.log('[NewTrackDrop] Created clip:', {
        clipDuration: newClip.duration,
        sourceDuration: newClip.sourceDuration,
        bufferDuration: audioFile.buffer?.duration,
        waveformLength: audioFile.waveform?.length,
      });

      addClip(newTrackId, newClip);
      logSlotEvent('TIMELINE', `Created track "${trackName}" with "${audioFile.name}" at ${time.toFixed(2)}s (${audioFile.duration.toFixed(2)}s)`);
    } else {
      // Handle demo sounds from D&D Lab
      const demoDuration = 2;
      const newClip: ClipState = {
        id: `clip-${Date.now()}`,
        trackId: newTrackId,
        name: audioItem.label,
        startTime: time,
        duration: demoDuration,
        offset: 0,
        sourceDuration: demoDuration,
        fadeIn: 0,
        fadeOut: 0,
        gain: 1,
        color: trackColor,
      };

      addClip(newTrackId, newClip);
      logSlotEvent('TIMELINE', `Created track "${trackName}" with "${audioItem.label}" at ${time.toFixed(2)}s`);
    }
  }, [importedAudioFiles, storeTracks.length, addTrack, addClip, logSlotEvent]);

  // Handle audio drop on mixer bus
  const handleMixerAudioDrop = useCallback((busId: string, audioItem: DragItem) => {
    const audioName = audioItem.label;
    // Log the audio assignment to bus
    logSlotEvent('MIXER', `Assigned "${audioName}" to bus "${busId}"`);
    // In a real implementation, this would route the audio to the bus
  }, [logSlotEvent]);

  // ========== AUDIO BROWSER HANDLERS ==========

  // Handle file selection from Audio Browser (opens import dialog)
  const handleAudioBrowserSelect = useCallback((file: AudioFileInfo) => {
    // Convert AudioFileInfo to FileToImport format
    const fileToImport: FileToImport = {
      name: file.name,
      size: file.size,
      duration: file.duration,
      sampleRate: file.sampleRate,
      channels: file.channels,
      format: file.format,
    };
    setFilesToImport([fileToImport]);
    // Store the actual File object for import
    if (file.file) {
      setPendingImportFiles([file.file]);
    }
    setImportDialogOpen(true);
    logSlotEvent('BROWSER', `Selected: ${file.name}`);
  }, [logSlotEvent]);

  // Handle import with options
  const handleImportWithOptions = useCallback(async (options: ImportOptions) => {
    rfDebug('Import', 'Import options:', options);
    setImportDialogOpen(false);

    const total = pendingImportFiles.length;
    const errors: string[] = [];

    // Initialize progress
    setImportProgress({
      isImporting: true,
      current: 0,
      total,
      currentFileName: pendingImportFiles[0]?.name ?? '',
      errors: [],
    });

    // Process pending files with progress tracking
    for (let i = 0; i < pendingImportFiles.length; i++) {
      const file = pendingImportFiles[i];

      // Update progress
      setImportProgress(prev => ({
        ...prev,
        current: i,
        currentFileName: file.name,
      }));

      try {
        const ctx = audioContextRef.current;
        if (!ctx) {
          errors.push(`${file.name}: No audio context`);
          continue;
        }

        const arrayBuffer = await file.arrayBuffer();
        let audioBuffer = await ctx.decodeAudioData(arrayBuffer);

        // Check for sample rate mismatch and resample if needed
        const projectSampleRate = DEFAULT_PROJECT_SAMPLE_RATE; // 48000 Hz
        if (needsSampleRateConversion(audioBuffer, projectSampleRate)) {
          console.log('[AudioImport] Sample rate conversion:', formatSampleRate(audioBuffer.sampleRate), '→', formatSampleRate(projectSampleRate));
          audioBuffer = await resampleAudioBuffer(audioBuffer, projectSampleRate);
        }

        // Generate waveform - Cubase-style: ~100 samples per second for smooth display
        const samples = audioBuffer.getChannelData(0);
        const waveform: number[] = [];
        // Dynamic sample count based on duration (min 200, max 10000)
        const samplesPerSecond = 100;
        const sampleCount = Math.min(10000, Math.max(200, Math.ceil(audioBuffer.duration * samplesPerSecond)));
        const blockSize = Math.floor(samples.length / sampleCount);

        // Generate exactly sampleCount points to cover entire audio
        for (let i = 0; i < sampleCount; i++) {
          const start = i * blockSize;
          const end = Math.min(start + blockSize, samples.length);
          let max = 0;
          for (let j = start; j < end; j++) {
            max = Math.max(max, Math.abs(samples[j]));
          }
          waveform.push(max);
        }

        // Analyze BPM/tempo (for loops and music files)
        let bpm: number | undefined;
        let bpmConfidence: number | undefined;
        let loopBars: number | undefined;
        try {
          // Only analyze files longer than 1 second and shorter than 5 minutes
          if (audioBuffer.duration >= 1 && audioBuffer.duration <= 300) {
            const analysis = analyzeAudioLoop(audioBuffer);
            if (analysis.bpm && analysis.confidence > 0.3) {
              bpm = Math.round(analysis.bpm);
              bpmConfidence = analysis.confidence;
              loopBars = analysis.loopBars ?? undefined;
              rfDebug('BPM', `Detected: ${bpm} BPM (${(bpmConfidence * 100).toFixed(0)}% confidence) for ${file.name}`);
            }
          }
        } catch (analysisErr) {
          // BPM analysis is optional - don't fail import
          console.warn('[BPM Analysis] Failed for', file.name, analysisErr);
        }

        // Create imported file entry
        const importedFile: ImportedAudioFile = {
          id: `audio-${Date.now()}-${Math.random().toString(36).substr(2, 5)}`,
          name: file.name,
          file,
          url: URL.createObjectURL(file),
          duration: audioBuffer.duration,
          waveform,
          buffer: audioBuffer,
          bpm,
          bpmConfidence,
          loopBars,
        };

        // DEBUG: Log import details
        console.log('[AudioImport] ✅ File imported:', {
          name: file.name,
          bufferDuration: audioBuffer.duration.toFixed(3),
          bufferSampleRate: audioBuffer.sampleRate,
          bufferLength: audioBuffer.length,
          waveformPoints: waveform.length,
          expectedWaveformPoints: sampleCount,
          storedDuration: importedFile.duration.toFixed(3),
        });

        setImportedAudioFiles(prev => [...prev, importedFile]);
        const bpmInfo = bpm ? ` [${bpm} BPM]` : '';
        logSlotEvent('IMPORT', `Imported: ${file.name} (${options.mode})${bpmInfo}`);
      } catch (err) {
        const errorMsg = `${file.name}: ${err instanceof Error ? err.message : 'Unknown error'}`;
        console.error('Failed to import:', file.name, err);
        logSlotEvent('ERROR', `Failed to import: ${file.name}`);
        errors.push(errorMsg);
      }
    }

    // Complete progress (show final state briefly before hiding)
    setImportProgress(prev => ({
      ...prev,
      current: total,
      currentFileName: 'Complete',
      errors,
    }));

    // Hide progress after a short delay
    setTimeout(() => {
      setImportProgress({ isImporting: false, current: 0, total: 0, currentFileName: '', errors: [] });
    }, errors.length > 0 ? 3000 : 1000); // Show longer if there were errors

    // Clear pending files
    setPendingImportFiles([]);
    setFilesToImport([]);
  }, [pendingImportFiles, logSlotEvent]);

  // Handle import cancel
  const handleImportCancel = useCallback(() => {
    setImportDialogOpen(false);
    setPendingImportFiles([]);
    setFilesToImport([]);
  }, []);

  // Handle Audio Pool remove
  const handlePoolRemove = useCallback((assetIds: string[]) => {
    setImportedAudioFiles(prev => prev.filter(f => !assetIds.includes(f.id)));
    logSlotEvent('POOL', `Removed ${assetIds.length} file(s)`);
  }, [logSlotEvent]);

  // Handle Audio Pool preview
  const handlePoolPreview = useCallback((asset: PoolAsset) => {
    const file = importedAudioFiles.find(f => f.id === asset.id);
    if (file) {
      playAudioFile(file.id);
      logSlotEvent('POOL', `Preview: ${asset.name}`);
    }
  }, [importedAudioFiles, playAudioFile, logSlotEvent]);

  const handleLayerChange = useCallback((layerId: string, changes: Partial<MusicLayer>) => {
    setMusicLayers((prev) =>
      prev.map((l) => (l.id === layerId ? { ...l, ...changes } : l))
    );
  }, []);

  const handleBlendCurveChange = useCallback((layerId: string, points: { x: number; y: number }[]) => {
    setBlendCurves((prev) =>
      prev.map((c) => (c.layerId === layerId ? { ...c, points } : c))
    );
  }, []);

  // Inspector sections - using RouteAction types with ALL parameters
  const inspectorSections: InspectorSection[] = useMemo(() => {
    // If we have a selected action, show action inspector
    if (selectedAction && selectedActionIndex !== null) {
      const action = selectedAction;
      const sections: InspectorSection[] = [];

      // ===== ACTION TYPE SECTION =====
      sections.push({
        id: 'action-type',
        title: 'Action',
        defaultExpanded: true,
        content: (
          <>
            <SelectField
              label="Type"
              value={action.type}
              options={[
                { value: 'Play', label: '▶ Play' },
                { value: 'Stop', label: '⏹ Stop' },
                { value: 'StopAll', label: '⏹ Stop All' },
                { value: 'Fade', label: '🔀 Fade' },
                { value: 'Pause', label: '⏸ Pause' },
                { value: 'SetBusGain', label: '🔊 Set Bus Gain' },
                { value: 'Execute', label: '🎬 Execute' },
              ]}
              onChange={(type) => handleActionUpdate(selectedActionIndex, { type: type as RouteAction['type'] })}
            />
            {/* Asset ID for Play, Fade - with audio picker */}
            {(isPlayAction(action) || isFadeAction(action)) && (
              <AudioAssetPicker
                label="Asset"
                value={action.assetId}
                audioAssets={audioAssetOptions}
                placeholder="Select audio file..."
                showMissingWarning={true}
                onChange={(assetId) => handleActionUpdate(selectedActionIndex, { assetId })}
                onPreview={(assetId) => playAudioFile(assetId)}
                onHoverPreview={playHoverPreview}
                onHoverPreviewStop={stopHoverPreview}
                hoverPreviewDelay={300}
              />
            )}
            {/* Asset ID for Stop, Pause - with audio picker (optional) */}
            {(isStopAction(action) || isPauseAction(action)) && (
              <AudioAssetPicker
                label="Asset (optional)"
                value={action.assetId || ''}
                audioAssets={audioAssetOptions}
                placeholder="All assets (leave empty)"
                showMissingWarning={false}
                onChange={(assetId) => handleActionUpdate(selectedActionIndex, { assetId: assetId || undefined })}
                onPreview={(assetId) => playAudioFile(assetId)}
                onHoverPreview={playHoverPreview}
                onHoverPreviewStop={stopHoverPreview}
                hoverPreviewDelay={300}
              />
            )}
            {/* Bus selector for Play, SetBusGain */}
            {(isPlayAction(action) || isSetBusGainAction(action)) && (
              <SelectField
                label="Bus"
                value={action.bus || routes?.defaultBus || 'SFX'}
                options={[
                  { value: 'Master', label: 'Master' },
                  { value: 'Music', label: 'Music' },
                  { value: 'SFX', label: 'SFX' },
                  { value: 'UI', label: 'UI' },
                  { value: 'VO', label: 'Voice' },
                  { value: 'Ambience', label: 'Ambience' },
                ]}
                onChange={(bus) => handleActionUpdate(selectedActionIndex, { bus: bus as RouteBus })}
              />
            )}
          </>
        ),
      });

      // ===== PLAYBACK SECTION (Play, Fade) =====
      if (isPlayAction(action) || isFadeAction(action) || isSetBusGainAction(action)) {
        sections.push({
          id: 'playback',
          title: 'Playback',
          defaultExpanded: true,
          content: (
            <>
              {/* Gain for Play, SetBusGain */}
              {(isPlayAction(action) || isSetBusGainAction(action)) && (
                <SliderField
                  label="Gain"
                  value={action.gain ?? 1}
                  min={0}
                  max={1}
                  step={0.01}
                  defaultValue={1}
                  formatValue={(v) => `${Math.round(v * 100)}%`}
                  onChange={(gain) => handleActionUpdate(selectedActionIndex, { gain })}
                />
              )}
              {/* Target Volume for Fade */}
              {isFadeAction(action) && (
                <SliderField
                  label="Target Volume"
                  value={action.targetVolume}
                  min={0}
                  max={1}
                  step={0.01}
                  defaultValue={1}
                  formatValue={(v) => `${Math.round(v * 100)}%`}
                  onChange={(targetVolume) => handleActionUpdate(selectedActionIndex, { targetVolume })}
                />
              )}
              {/* Loop for Play */}
              {isPlayAction(action) && (
                <>
                  <CheckboxField
                    label="Loop"
                    checked={action.loop ?? false}
                    onChange={(loop) => handleActionUpdate(selectedActionIndex, { loop })}
                  />
                  {action.loop && (
                    <SliderField
                      label="Loop Count"
                      value={action.loopCount ?? 0}
                      min={0}
                      max={100}
                      step={1}
                      defaultValue={0}
                      formatValue={(v) => v === 0 ? '∞' : `${v}x`}
                      onChange={(loopCount) => handleActionUpdate(selectedActionIndex, { loopCount })}
                    />
                  )}
                  <CheckboxField
                    label="Allow Overlap"
                    checked={action.overlap ?? false}
                    onChange={(overlap) => handleActionUpdate(selectedActionIndex, { overlap })}
                  />
                </>
              )}
              {/* Pan for Play, Fade - bipolar, defaults to center */}
              {(isPlayAction(action) || isFadeAction(action)) && (
                <SliderField
                  label="Pan"
                  value={action.pan ?? 0}
                  min={-1}
                  max={1}
                  step={0.01}
                  defaultValue={0}
                  formatValue={(v) => v === 0 ? 'C' : v < 0 ? `L${Math.abs(Math.round(v * 100))}` : `R${Math.round(v * 100)}`}
                  onChange={(pan) => handleActionUpdate(selectedActionIndex, { pan })}
                />
              )}
            </>
          ),
        });
      }

      // ===== PAUSE OPTIONS =====
      if (isPauseAction(action)) {
        sections.push({
          id: 'pause-options',
          title: 'Pause Options',
          defaultExpanded: true,
          content: (
            <CheckboxField
              label="Pause Overall (All Audio)"
              checked={action.overall ?? false}
              onChange={(overall) => handleActionUpdate(selectedActionIndex, { overall })}
            />
          ),
        });
      }

      // ===== TIMING SECTION =====
      const hasTimingParams = isPlayAction(action) || isStopAction(action) || isFadeAction(action) || isPauseAction(action) || isSetBusGainAction(action) || isStopAllAction(action) || isExecuteAction(action);
      if (hasTimingParams) {
        sections.push({
          id: 'timing',
          title: 'Timing',
          defaultExpanded: true,
          content: (
            <>
              {/* Delay - all types except StopAll have it */}
              {(isPlayAction(action) || isStopAction(action) || isFadeAction(action) || isPauseAction(action) || isExecuteAction(action)) && (
                <SliderField
                  label="Delay"
                  value={action.delay ?? 0}
                  min={0}
                  max={10}
                  step={0.01}
                  formatValue={(v) => `${v.toFixed(2)}s`}
                  onChange={(delay) => handleActionUpdate(selectedActionIndex, { delay })}
                />
              )}
              {/* Fade In - Play only */}
              {isPlayAction(action) && (
                <SliderField
                  label="Fade In"
                  value={action.fadeIn ?? 0}
                  min={0}
                  max={10}
                  step={0.01}
                  formatValue={(v) => `${v.toFixed(2)}s`}
                  onChange={(fadeIn) => handleActionUpdate(selectedActionIndex, { fadeIn })}
                />
              )}
              {/* Fade Out - Stop, StopAll, Pause */}
              {(isStopAction(action) || isStopAllAction(action) || isPauseAction(action)) && (
                <SliderField
                  label="Fade Out"
                  value={action.fadeOut ?? 0}
                  min={0}
                  max={10}
                  step={0.01}
                  formatValue={(v) => `${v.toFixed(2)}s`}
                  onChange={(fadeOut) => handleActionUpdate(selectedActionIndex, { fadeOut })}
                />
              )}
              {/* Duration - Fade, SetBusGain */}
              {(isFadeAction(action) || isSetBusGainAction(action)) && (
                <SliderField
                  label="Duration"
                  value={action.duration ?? 0}
                  min={0}
                  max={10}
                  step={0.01}
                  formatValue={(v) => `${v.toFixed(2)}s`}
                  onChange={(duration) => handleActionUpdate(selectedActionIndex, { duration })}
                />
              )}
              {/* Asymmetric fade durations - Fade only */}
              {isFadeAction(action) && (
                <>
                  <SliderField
                    label="Duration Up"
                    value={action.durationUp ?? 0}
                    min={0}
                    max={10}
                    step={0.01}
                    formatValue={(v) => v === 0 ? 'Auto' : `${v.toFixed(2)}s`}
                    onChange={(durationUp) => handleActionUpdate(selectedActionIndex, { durationUp })}
                  />
                  <SliderField
                    label="Duration Down"
                    value={action.durationDown ?? 0}
                    min={0}
                    max={10}
                    step={0.01}
                    formatValue={(v) => v === 0 ? 'Auto' : `${v.toFixed(2)}s`}
                    onChange={(durationDown) => handleActionUpdate(selectedActionIndex, { durationDown })}
                  />
                </>
              )}
            </>
          ),
        });
      }

      // ===== EXECUTE SECTION =====
      if (isExecuteAction(action)) {
        sections.push({
          id: 'execute-options',
          title: 'Execute Options',
          defaultExpanded: true,
          content: (
            <>
              <SelectField
                label="Event to Call"
                value={action.eventId}
                options={[
                  { value: '', label: '-- Select Event --' },
                  ...(routes?.events || []).filter(e => e.name !== selectedEventName).map(e => ({
                    value: e.name,
                    label: e.name,
                  })),
                ]}
                onChange={(eventId) => handleActionUpdate(selectedActionIndex, { eventId })}
              />
              <SliderField
                label="Volume"
                value={action.volume ?? 1}
                min={0}
                max={1}
                step={0.01}
                defaultValue={1}
                formatValue={(v) => `${Math.round(v * 100)}%`}
                onChange={(volume) => handleActionUpdate(selectedActionIndex, { volume })}
              />
              <SliderField
                label="Fade Duration"
                value={action.fadeDuration ?? 0}
                min={0}
                max={10}
                step={0.01}
                formatValue={(v) => `${v.toFixed(2)}s`}
                onChange={(fadeDuration) => handleActionUpdate(selectedActionIndex, { fadeDuration })}
              />
            </>
          ),
        });
      }

      return sections;
    }

    // If we have a selected event (but no action), show event inspector
    if (selectedEvent) {
      return [
        {
          id: 'event-general',
          title: 'Event',
          defaultExpanded: true,
          content: (
            <>
              <TextField
                label="Name"
                value={selectedEvent.name}
                onChange={() => {/* Event rename would need special handling */}}
              />
            </>
          ),
        },
        {
          id: 'event-actions',
          title: 'Actions',
          defaultExpanded: true,
          content: (
            <div style={{ fontSize: 12, color: 'var(--rf-text-secondary)' }}>
              {selectedEvent.actions.length} action{selectedEvent.actions.length !== 1 ? 's' : ''} in this event.
              <br />
              <span style={{ fontSize: 11, color: 'var(--rf-text-tertiary)' }}>
                Select an action row to edit its properties.
              </span>
            </div>
          ),
        },
      ];
    }

    // Default: no selection
    return [
      {
        id: 'no-selection',
        title: 'Inspector',
        defaultExpanded: true,
        content: (
          <div style={{ padding: 16, color: 'var(--rf-text-tertiary)', fontSize: 12 }}>
            Select an event or action to view properties.
          </div>
        ),
      },
    ];
  }, [selectedAction, selectedActionIndex, selectedEvent, handleActionUpdate]);

  // Lower zone tabs
  const lowerTabs: LowerZoneTab[] = useMemo(
    () => [
      {
        id: 'timeline',
        label: 'Timeline',
        icon: '🎬',
        content: (
          <Timeline
            tracks={timelineTracks}
            clips={timelineClips}
            markers={[]}
            playheadPosition={currentTime}
            tempo={tempo}
            timeSignature={[4, 4]}
            zoom={zoom}
            scrollOffset={scrollOffset}
            totalDuration={32}
            timeDisplayMode={timeDisplayMode}
            loopRegion={loopRegion}
            loopEnabled={loopEnabled}
            onPlayheadChange={handlePlayheadChange}
            onClipSelect={handleClipSelect}
            onZoomChange={setZoom}
            onScrollChange={setScrollOffset}
            onLoopToggle={() => setLoopEnabled(l => !l)}
            onTrackMuteToggle={handleTrackMuteToggle}
            onTrackSoloToggle={handleTrackSoloToggle}
            onTrackSelect={setSelectedTrackId}
            onLoopRegionChange={setLoopRegion}
            onAudioDrop={handleTimelineAudioDrop}
            onNewTrackDrop={handleTimelineNewTrackDrop}
            onClipGainChange={handleClipGainChange}
            onClipFadeChange={handleClipFadeChange}
            onClipResize={handleClipResize}
            onClipSplit={handleClipSplit}
            onClipDuplicate={handleClipDuplicate}
            onClipMove={handleClipMove}
            onTrackColorChange={handleTrackColorChange}
            onTrackBusChange={handleTrackBusChange}
            onTrackRename={handleTrackRename}
            onClipRename={handleClipRename}
            onClipDelete={handleClipDelete}
            onClipCopy={handleClipCopy}
            onClipPaste={handleClipPaste}
            crossfades={crossfades}
            onCrossfadeCreate={handleCrossfadeCreate}
            onCrossfadeUpdate={handleCrossfadeUpdate}
            onCrossfadeDelete={handleCrossfadeDelete}
            instanceId="lower-zone"
          />
        ),
      },
      {
        id: 'mixer',
        label: 'Mixer',
        icon: '🎚️',
        content: (
          <MixerTabContent
            busStates={busStates}
            isPlaying={hasActiveAudio}
            selectedBusId={selectedBusId}
            onSelectBus={setSelectedBusId}
            onVolumeChange={handleBusVolumeChange}
            onPanChange={handleBusPanChange}
            onMuteToggle={handleBusMuteToggle}
            onSoloToggle={handleBusSoloToggle}
            onInsertClick={handleInsertClick}
            onInsertBypass={handleDirectInsertBypass}
            onAudioDrop={handleMixerAudioDrop}
            audioContext={audioContext}
            busGains={busGains}
          />
        ),
      },
      {
        id: 'clip-editor',
        label: 'Clip Editor',
        icon: '✏️',
        content: (
          <ClipEditor
            clip={clipEditorData}
          />
        ),
      },
      {
        id: 'layers',
        label: 'Layered Music',
        icon: '🎼',
        content: (
          <LayeredMusicEditor
            layers={musicLayers}
            blendCurves={blendCurves}
            states={musicStates}
            currentStateId={currentMusicState}
            rtpcValue={rtpcValue}
            rtpcName="Intensity"
            onLayerChange={handleLayerChange}
            onBlendCurveChange={handleBlendCurveChange}
            onStateChange={setCurrentMusicState}
            onRtpcChange={setRtpcValue}
          />
        ),
      },
      {
        id: 'console',
        label: 'Console',
        icon: '📝',
        content: <ConsolePanel messages={consoleMessages} onClear={() => setConsoleMessages([])} />,
      },
      {
        id: 'validation',
        label: 'Validation',
        icon: '✓',
        content: (
          <ValidationPanel
            routes={routes}
            availableAssets={availableAssetIds}
            onNavigateToError={(error) => {
              // Navigate to the error location
              if (error.eventName) {
                setSelectedEventName(error.eventName);
                if (error.actionIndex !== undefined) {
                  setSelectedActionIndex(error.actionIndex);
                }
              } else if (error.eventIndex !== undefined && routes?.events[error.eventIndex]) {
                setSelectedEventName(routes.events[error.eventIndex].name);
                if (error.actionIndex !== undefined) {
                  setSelectedActionIndex(error.actionIndex);
                }
              }
            }}
          />
        ),
      },
      // ========== SLOT AUDIO TABS ==========
      {
        id: 'spin-cycle',
        label: 'Spin Cycle',
        icon: '🎰',
        content: (
          <SpinCycleEditor
            config={spinConfig}
            currentState={currentSpinState}
            isSimulating={isSlotSimulating}
            onConfigChange={setSpinConfig}
            onStateChange={(state) => {
              setCurrentSpinState(state);
              logSlotEvent('MANUAL_STATE', state);
            }}
            onSoundSelect={(state, soundId) => {
              logSlotEvent('SOUND_SELECT', `${state}:${soundId}`);
            }}
          />
        ),
      },
      {
        id: 'win-tiers',
        label: 'Win Tiers',
        icon: '🏆',
        content: (
          <WinTierEditor
            tiers={winTiers}
            activeTier={activeTier}
            onTierChange={setWinTiers}
            onTierSelect={(tier) => {
              setActiveTier(tier);
              logSlotEvent('TIER_SELECT', tier);
            }}
            onPreview={(tier) => {
              logSlotEvent('TIER_PREVIEW', tier);
            }}
          />
        ),
      },
      {
        id: 'reel-sequencer',
        label: 'Reel Sequencer',
        icon: '⏱️',
        content: (
          <ReelStopSequencer
            reels={reelConfigs}
            totalDuration={2500}
            currentTime={sequencerTime}
            isPlaying={isSequencerPlaying}
            onReelChange={setReelConfigs}
            onPlay={() => {
              setIsSequencerPlaying(true);
              logSlotEvent('SEQUENCER_START', 'Playback started');
            }}
            onStop={() => {
              setIsSequencerPlaying(false);
              logSlotEvent('SEQUENCER_PAUSE', 'Playback paused');
            }}
            onSeek={(time) => {
              setSequencerTime(time);
              logSlotEvent('SEQUENCER_SEEK', `${time}ms`);
            }}
          />
        ),
      },
      // ========== AUDIO FEATURES TAB ==========
      {
        id: 'audio-features',
        label: 'Audio Features',
        icon: '🎛️',
        content: (
          <AudioFeaturesPanel
            buses={busStates.map(b => ({ id: b.id as import('./core/types').BusId, name: b.name }))}
            onFeatureChange={(feature, enabled) => {
              logSlotEvent('FEATURE_TOGGLE', `${feature}: ${enabled ? 'ON' : 'OFF'}`);
            }}
          />
        ),
      },
      // ========== PRO FEATURES TAB ==========
      {
        id: 'pro-features',
        label: 'Pro Features',
        icon: '⚡',
        content: (
          <ProFeaturesPanel
            buses={busStates.map(b => ({ id: b.id as import('./core/types').BusId, name: b.name }))}
            onFeatureChange={(feature, enabled) => {
              logSlotEvent('PRO_FEATURE_TOGGLE', `${feature}: ${enabled ? 'ON' : 'OFF'}`);
            }}
          />
        ),
      },
      // ========== SLOT AUDIO STUDIO ==========
      {
        id: 'slot-studio',
        label: 'Slot Studio',
        icon: '🎧',
        content: (
          <SlotAudioStudio
            onEventSelect={(eventId) => {
              logSlotEvent('STUDIO_EVENT_SELECT', eventId);
            }}
            onPlayPreview={(eventId) => {
              logSlotEvent('STUDIO_PREVIEW', eventId);
            }}
          />
        ),
      },
      // ========== DSP PROCESSORS ==========
      {
        id: 'sidechain',
        label: 'Sidechain',
        icon: '⛓️',
        content: (
          <SidechainRouterPanel
            buses={busStates.map(b => ({ id: b.id as import('./core/types').BusId, name: b.name }))}
            onRouteChange={(routeId, route) => {
              logSlotEvent('SIDECHAIN_ROUTE', `${routeId}: ${route.name}`);
            }}
          />
        ),
      },
      {
        id: 'multiband',
        label: 'Multiband',
        icon: '📊',
        content: (
          <MultibandCompressorPanel
            onConfigChange={(config) => {
              logSlotEvent('MULTIBAND_CONFIG', `${config.bandCount} bands, ${config.bypass ? 'bypassed' : 'active'}`);
            }}
          />
        ),
      },
      {
        id: 'fx-presets',
        label: 'FX Presets',
        icon: '🎨',
        content: (
          <SlotFXPresetsPanel
            onPresetSelect={(preset) => {
              logSlotEvent('PRESET_SELECT', preset.name);
            }}
            onPresetApply={(preset, bus) => {
              logSlotEvent('PRESET_APPLY', `${preset.name} → ${bus}`);
            }}
          />
        ),
      },
      // ========== CUBASE-STYLE AUDIO IMPORT ==========
      {
        id: 'audio-browser',
        label: 'Audio Browser',
        icon: '📂',
        content: (
          <AudioBrowser
            onImport={(files) => {
              // Handle first file for now (can extend to multi-select later)
              if (files.length > 0) {
                handleAudioBrowserSelect(files[0]);
              }
            }}
            onPreviewStart={(file) => {
              logSlotEvent('BROWSER', `Preview: ${file.name}`);
            }}
            showImport={true}
          />
        ),
      },
      {
        id: 'audio-pool',
        label: 'Audio Pool',
        icon: '🗃️',
        content: (
          <AudioPoolPanel
            assets={audioPoolAssets}
            onRemove={handlePoolRemove}
            onPreview={handlePoolPreview}
            onConsolidate={() => {
              logSlotEvent('POOL', 'Consolidate all external files');
            }}
            onRemoveUnused={() => {
              logSlotEvent('POOL', 'Remove unused files');
            }}
          />
        ),
      },
      // ========== DRAG & DROP LAB ==========
      {
        id: 'drag-drop-lab',
        label: 'D&D Lab',
        icon: '✋',
        content: <DragDropLabPanel onLogEvent={logSlotEvent} />,
      },
      // ========== LOADING STATES DEMO ==========
      {
        id: 'loading-states',
        label: 'Loading',
        icon: '⏳',
        content: <LoadingStatesPanel />,
      },
    ],
    [
      busStates,
      // NOTE: busStatesWithMeters removed - MixerTabContent has its own meter hook
      hasActiveAudio, // Needed for MixerTabContent isPlaying prop (event preview only)
      selectedBusId,
      consoleMessages,
      timelineClips,
      timelineTracks,
      currentTime,
      tempo,
      zoom,
      scrollOffset,
      timeDisplayMode,
      loopRegion,
      musicLayers,
      blendCurves,
      musicStates,
      currentMusicState,
      rtpcValue,
      handleBusVolumeChange,
      handleBusPanChange,
      handleBusMuteToggle,
      handleBusSoloToggle,
      handleInsertClick,
      handleClipSelect,
      handleTrackMuteToggle,
      handleTrackSoloToggle,
      handleLayerChange,
      handleBlendCurveChange,
      // Slot dependencies
      spinConfig,
      currentSpinState,
      isSlotSimulating,
      logSlotEvent,
      winTiers,
      activeTier,
      reelConfigs,
      sequencerTime,
      isSequencerPlaying,
      // Audio Browser/Pool dependencies
      audioPoolAssets,
      handleAudioBrowserSelect,
      handlePoolRemove,
      handlePoolPreview,
    ]
  );

  // ===== TAB GROUPS - Cubase-style organization =====
  // DAW Mode: MixConsole | Clip Editor | Sampler | Media | DSP
  // Middleware Mode: Slot | Tools | DSP | Features
  const lowerTabGroups: TabGroup[] = useMemo(() => [
    // ========== DAW MODE GROUPS (Cubase-style) ==========
    // MixConsole - Full mixer (like Cubase MixConsole in Lower Zone)
    {
      id: 'mixconsole',
      label: 'MixConsole',
      icon: '🎚️',
      tabs: ['mixer'],
    },
    // Clip Editor - Detailed waveform editing (like Cubase Sample Editor)
    {
      id: 'clip-editor',
      label: 'Editor',
      icon: '✏️',
      tabs: ['clip-editor'],
    },
    // Sampler - Layered music system (like Cubase Sampler Control)
    {
      id: 'sampler',
      label: 'Sampler',
      icon: '🎹',
      tabs: ['layers'],
    },
    // Media - Audio Browser & Pool (like Cubase MediaBay)
    {
      id: 'media',
      label: 'Media',
      icon: '📂',
      tabs: ['audio-browser', 'audio-pool'],
    },
    // DSP - Professional audio processing
    {
      id: 'dsp',
      label: 'DSP',
      icon: '📊',
      tabs: ['sidechain', 'multiband', 'fx-presets'],
    },

    // ========== MIDDLEWARE MODE GROUPS ==========
    // Slot - All slot-specific audio tools
    {
      id: 'slot',
      label: 'Slot Audio',
      icon: '🎰',
      tabs: ['spin-cycle', 'win-tiers', 'reel-sequencer', 'slot-studio'],
    },
    // Features - Audio features and pro tools
    {
      id: 'features',
      label: 'Features',
      icon: '⚡',
      tabs: ['audio-features', 'pro-features'],
    },
    // Tools - Validation, console, debug
    {
      id: 'tools',
      label: 'Tools',
      icon: '🔧',
      tabs: ['validation', 'console', 'drag-drop-lab', 'loading-states'],
    },
  ], []);

  // ===== DYNAMIC PROJECT TREE - Mode-aware =====
  const projectTree: TreeNode[] = useMemo(() => {
    const tree: TreeNode[] = [];

    if (editorMode === 'daw') {
      // ========== DAW MODE: Cubase-style project browser ==========
      // Audio Pool (imported files)
      tree.push({
        id: 'audio-pool',
        type: 'folder',
        label: 'Audio Pool',
        count: importedAudioFiles.length,
        children: importedAudioFiles.map((audio) => ({
          id: `audio-${audio.id}`,
          type: 'sound' as const,
          label: audio.name,
        })),
      });

      // Tracks folder
      tree.push({
        id: 'tracks',
        type: 'folder',
        label: 'Tracks',
        count: timelineTracks.length,
        children: timelineTracks.map((track) => ({
          id: `track-${track.id}`,
          type: 'sound' as const,
          label: track.name,
        })),
      });

      // Buses / MixConsole
      tree.push({
        id: 'mixconsole',
        type: 'folder',
        label: 'MixConsole',
        count: 5,
        children: [
          { id: 'bus-master', type: 'bus' as const, label: 'Master' },
          { id: 'bus-sfx', type: 'bus' as const, label: 'SFX' },
          { id: 'bus-music', type: 'bus' as const, label: 'Music' },
          { id: 'bus-voice', type: 'bus' as const, label: 'Voice' },
          { id: 'bus-ui', type: 'bus' as const, label: 'UI' },
        ],
      });

      // Markers
      tree.push({
        id: 'markers',
        type: 'folder',
        label: 'Markers',
        count: 0,
        children: [],
      });

    } else {
      // ========== MIDDLEWARE MODE: Wwise-style event browser ==========
      // Events folder - from imported JSON routes
      if (routes?.events?.length) {
        tree.push({
          id: 'events',
          type: 'folder',
          label: 'Events',
          count: routes.events.length,
          children: routes.events.map((evt) => ({
            id: `evt-${evt.name}`,
            type: 'event' as const,
            label: evt.name,
          })),
        });
      } else {
        tree.push({
          id: 'events',
          type: 'folder',
          label: 'Events',
          count: 0,
          children: [],
        });
      }

      // Buses
      tree.push({
        id: 'buses',
        type: 'folder',
        label: 'Buses',
        count: 5,
        children: [
          { id: 'bus-master', type: 'bus' as const, label: 'Master' },
          { id: 'bus-sfx', type: 'bus' as const, label: 'SFX' },
          { id: 'bus-music', type: 'bus' as const, label: 'Music' },
          { id: 'bus-voice', type: 'bus' as const, label: 'Voice' },
          { id: 'bus-ui', type: 'bus' as const, label: 'UI' },
        ],
      });

      // Game Syncs - States
      tree.push({
        id: 'states',
        type: 'folder',
        label: 'States',
        count: 3,
        children: [
          { id: 'state-gameplay', type: 'state' as const, label: 'Gameplay' },
          { id: 'state-menu', type: 'state' as const, label: 'Menu' },
          { id: 'state-cutscene', type: 'state' as const, label: 'Cutscene' },
        ],
      });

      // Game Syncs - Switches
      tree.push({
        id: 'switches',
        type: 'folder',
        label: 'Switches',
        count: 2,
        children: [
          { id: 'switch-surface', type: 'switch' as const, label: 'Surface Type' },
          { id: 'switch-weather', type: 'switch' as const, label: 'Weather' },
        ],
      });

      // Audio Files
      tree.push({
        id: 'audio-files',
        type: 'folder',
        label: 'Audio Files',
        count: importedAudioFiles.length,
        children: importedAudioFiles.map((audio) => ({
          id: `audio-${audio.id}`,
          type: 'sound' as const,
          label: audio.name,
        })),
      });
    }

    return tree;
  }, [editorMode, routes, importedAudioFiles, timelineTracks]);

  // ===== PROJECT SELECT HANDLER =====
  const handleProjectSelect = useCallback((id: string, type: string) => {
    if (type === 'event') {
      const eventName = id.replace('evt-', '');
      setSelectedEventName(eventName);
      setSelectedActionIndex(null);
      logSlotEvent('SELECT', `Event: ${eventName}`);
    } else if (type === 'bus') {
      setSelectedBusId(id.replace('bus-', ''));
      logSlotEvent('SELECT', `Bus: ${id}`);
    }
  }, [logSlotEvent]);

  // ===== MENU HANDLERS =====
  const processImportedJSON = useCallback((file: File) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const text = e.target?.result as string;
        const parsed = JSON.parse(text);
        rfDebug('Import', 'File:', file.name, 'keys:', Object.keys(parsed));

        // Try to find events array - could be at root or nested in various formats
        let eventsArray = parsed.events;

        // Format: { routes: { events: [...] } }
        if (!eventsArray && parsed.routes?.events) {
          eventsArray = parsed.routes.events;
        }

        // Format: { routes: { data: { events: [...] } } } (ProjectFileV1 format)
        if (!eventsArray && parsed.routes?.data?.events) {
          eventsArray = parsed.routes.data.events;
        }

        // Format: { data: { events: [...] } }
        if (!eventsArray && parsed.data?.events) {
          eventsArray = parsed.data.events;
        }

        // Format: array at root (just events array directly)
        if (!eventsArray && Array.isArray(parsed)) {
          eventsArray = parsed;
        }

        // Format: { soundDefinitions: { commands: {...} } } - your existing code format
        if (!eventsArray && parsed.soundDefinitions?.commands) {
          rfDebug('Import', 'Detected soundDefinitions.commands format');
          eventsArray = [];
          const commands = parsed.soundDefinitions.commands;

          for (const [eventName, cmdDef] of Object.entries(commands)) {
            const def = cmdDef as { type?: string; assetId?: string; file?: string; bus?: string; gain?: number; loop?: boolean; actions?: RouteAction[] };
            const actions: RouteAction[] = [];

            // If it already has actions array, use it directly
            if (def.actions && Array.isArray(def.actions)) {
              actions.push(...def.actions);
            } else {
              // Convert single command to Play action
              actions.push({
                type: 'Play',
                assetId: def.assetId || def.file || eventName,
                bus: (def.bus || 'SFX') as RouteBus,
                gain: def.gain ?? 1,
                loop: def.loop ?? false,
              } as RouteAction);
            }

            eventsArray.push({
              name: eventName,
              actions,
            });
          }
          rfDebug('Import', 'Converted', eventsArray.length, 'commands to events');
        }

        // Format: { soundManifest: [...], soundDefinitions: {...} } - Sound Manifest format
        if (!eventsArray && parsed.soundDefinitions && !parsed.soundDefinitions.commands) {
          rfDebug('Import', 'Detected Sound Manifest format');
          eventsArray = [];
          const definitions = parsed.soundDefinitions;

          // Convert soundDefinitions object to events array
          for (const [eventName, definition] of Object.entries(definitions)) {
            const def = definition as Record<string, unknown>;
            const actions: RouteAction[] = [];

            // Check for sounds array
            if (def.sounds && Array.isArray(def.sounds)) {
              for (const sound of def.sounds as Array<Record<string, unknown>>) {
                actions.push({
                  type: 'Play',
                  assetId: (sound.file || sound.assetId || sound.asset || sound.id || eventName) as string,
                  bus: ((sound.bus || def.bus || 'SFX') as string) as RouteBus,
                  gain: (sound.gain as number) ?? 1,
                  loop: (sound.loop as boolean) ?? false,
                });
              }
            }
            // Check for single file/asset reference
            else if (def.file || def.assetId || def.asset || def.id || def.soundFile) {
              actions.push({
                type: 'Play',
                assetId: (def.file || def.assetId || def.asset || def.id || def.soundFile) as string,
                bus: ((def.bus || 'SFX') as string) as RouteBus,
                gain: (def.gain as number) ?? 1,
                loop: (def.loop as boolean) ?? false,
              });
            }
            // Check for files array (alternative format)
            else if (def.files && Array.isArray(def.files)) {
              for (const file of def.files as string[]) {
                actions.push({
                  type: 'Play',
                  assetId: file,
                  bus: ((def.bus || 'SFX') as string) as RouteBus,
                  gain: 1,
                });
              }
            }
            // Fallback: use eventName but warn
            else {
              console.warn(`[Import] No audio file found for "${eventName}", using eventName as assetId`);
              actions.push({
                type: 'Play',
                assetId: eventName,
                bus: ((def.bus || 'SFX') as string) as RouteBus,
                gain: (def.gain as number) ?? 1,
                loop: (def.loop as boolean) ?? false,
              });
            }

            eventsArray.push({
              name: eventName,
              actions,
            });
          }
          rfDebug('Import', 'Converted', eventsArray.length, 'sound definitions to events');
        }

        // Format: { soundManifest: [...] } - just manifest array, use as asset list
        if (!eventsArray && parsed.soundManifest && Array.isArray(parsed.soundManifest)) {
          rfDebug('Import', 'Detected soundManifest array format');
          eventsArray = parsed.soundManifest.map((item: { id?: string; name?: string; file?: string }) => ({
            name: item.id || item.name || item.file || 'Unknown',
            actions: [{
              type: 'Play' as const,
              assetId: item.file || item.id || item.name || '',
              bus: 'SFX' as RouteBus,
              gain: 1,
            }],
          }));
        }

        // Validate structure
        if (!eventsArray || !Array.isArray(eventsArray)) {
          setConsoleMessages(prev => [...prev, {
            id: Date.now().toString(),
            level: 'error',
            message: `❌ Invalid JSON: missing "events" array in ${file.name}. Keys found: ${Object.keys(parsed).join(', ')}`,
            timestamp: new Date(),
          }]);
          return;
        }

        // Build RoutesConfig
        const routesConfig: RoutesConfig = {
          routesVersion: parsed.routesVersion || 1,
          defaultBus: parsed.defaultBus || 'SFX',
          events: eventsArray,
        };

        rfDebug('Import', 'Setting workingRoutes with', routesConfig.events.length, 'events');

        // CRITICAL: Call setWorkingRoutes
        setWorkingRoutes(routesConfig);

        // Auto-select first event after import
        if (routesConfig.events.length > 0) {
          const firstName = routesConfig.events[0].name;
          setSelectedEventName(firstName);
          setSelectedActionIndex(null);
        }

        // Log to console panel
        setConsoleMessages(prev => [...prev, {
          id: Date.now().toString(),
          level: 'info',
          message: `✅ Imported ${file.name} with ${routesConfig.events.length} events`,
          timestamp: new Date(),
        }]);

        logSlotEvent('IMPORT', `Imported ${file.name} with ${routesConfig.events.length} events`);
      } catch (err) {
        setConsoleMessages(prev => [...prev, {
          id: Date.now().toString(),
          level: 'error',
          message: `❌ Failed to parse ${file.name}: ${(err as Error).message}`,
          timestamp: new Date(),
        }]);
      }
    };
    reader.onerror = () => {
      rfDebug('Import', 'FileReader error');
    };
    reader.readAsText(file);
  }, [setWorkingRoutes, logSlotEvent, setConsoleMessages]);

  const handleImportJSON = useCallback(async () => {
    // Use File System Access API if available (Chrome/Edge)
    if ('showOpenFilePicker' in window) {
      try {
        const [fileHandle] = await (window as unknown as { showOpenFilePicker: (opts: object) => Promise<FileSystemFileHandle[]> }).showOpenFilePicker({
          types: [{ description: 'JSON Files', accept: { 'application/json': ['.json'] } }],
        });
        const file = await fileHandle.getFile();
        processImportedJSON(file);
      } catch (e) {
        if ((e as Error).name !== 'AbortError') {
          console.error('Import failed:', e);
        }
      }
    } else {
      // Fallback for Firefox/Safari - use hidden input
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = '.json,application/json';
      input.onchange = (e) => {
        const file = (e.target as HTMLInputElement).files?.[0];
        if (file) {
          processImportedJSON(file);
        }
      };
      input.click();
    }
  }, [processImportedJSON]);

  const handleExportJSON = useCallback(async () => {
    if (!workingRoutes) return;
    const blob = new Blob([JSON.stringify(workingRoutes, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'runtime_routes.json';
    a.click();
    URL.revokeObjectURL(url);
    logSlotEvent('EXPORT', 'Exported runtime_routes.json');
  }, [workingRoutes, logSlotEvent]);

  // Clear all session data and start fresh
  const handleClearSession = useCallback(async () => {
    if (!confirm('Clear all session data? This will remove all events and audio files.')) return;

    // Clear localStorage
    localStorage.removeItem(STORAGE_KEYS.SESSION);
    localStorage.removeItem(STORAGE_KEYS.AUDIO_META);

    // Clear IndexedDB
    await clearAudioDB();

    // Reset state
    setWorkingRoutes({ routesVersion: 1, defaultBus: 'SFX', events: [] });
    setImportedAudioFiles([]);

    // Clear all tracks from store (this also clears clips)
    storeTracks.forEach(track => removeTrack(track.id));

    setSelectedEventName(null);
    setSelectedActionIndex(null);

    logSlotEvent('SESSION', 'Cleared all session data');
    setConsoleMessages([{
      id: Date.now().toString(),
      level: 'info',
      message: '🗑️ Session cleared. Import audio files to start fresh.',
      timestamp: new Date(),
    }]);
  }, [setWorkingRoutes, storeTracks, removeTrack, logSlotEvent]);

  // Generate waveform from AudioBuffer
  // startOffset: time in seconds to start sampling from (for skipping silence/padding)
  const generateWaveformFromBuffer = useCallback((
    buffer: AudioBuffer,
    numSamples: number = 200,
    actualDuration?: number,
    startOffset: number = 0
  ): number[] => {
    const channelData = buffer.getChannelData(0); // Use first channel
    const sampleRate = buffer.sampleRate;
    const duration = actualDuration ?? buffer.duration;
    const startSample = Math.floor(startOffset * sampleRate);
    const endSample = Math.min(startSample + Math.floor(duration * sampleRate), channelData.length);
    const actualSamples = endSample - startSample;
    const samplesPerPoint = Math.floor(actualSamples / numSamples);
    const waveform: number[] = [];

    for (let i = 0; i < numSamples; i++) {
      const start = startSample + i * samplesPerPoint;
      const end = Math.min(start + samplesPerPoint, endSample);
      let max = 0;
      for (let j = start; j < end; j++) {
        const abs = Math.abs(channelData[j]);
        if (abs > max) max = abs;
      }
      waveform.push(max);
    }

    return waveform;
  }, []);

  // Process audio files helper - shared by both import methods
  const processAudioFiles = useCallback(async (files: File[], sourceName: string) => {
    if (files.length === 0) {
      setConsoleMessages(prev => [...prev, {
        id: Date.now().toString(),
        level: 'warn',
        message: 'No audio files found in selection',
        timestamp: new Date(),
      }]);
      return;
    }

    logSlotEvent('IMPORT_AUDIO', `Loading ${files.length} audio files from ${sourceName}...`);

    // Use the main audioContext (already created via useMemo)
    const ctx = audioContextRef.current!;
    const loadedFiles: typeof importedAudioFiles = [];

    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      try {
        const arrayBuffer = await file.arrayBuffer();
        let audioBuffer = await ctx.decodeAudioData(arrayBuffer);

        // Check for sample rate mismatch and resample if needed
        const projectSampleRate = DEFAULT_PROJECT_SAMPLE_RATE; // 48000 Hz
        if (needsSampleRateConversion(audioBuffer, projectSampleRate)) {
          console.log('[AudioImport] Sample rate mismatch detected:', {
            source: formatSampleRate(audioBuffer.sampleRate),
            target: formatSampleRate(projectSampleRate),
          });
          setConsoleMessages(prev => [...prev, {
            id: Date.now().toString(),
            level: 'info',
            message: `Converting ${file.name}: ${formatSampleRate(audioBuffer.sampleRate)} → ${formatSampleRate(projectSampleRate)}`,
            timestamp: new Date(),
          }]);

          // Resample to project sample rate
          audioBuffer = await resampleAudioBuffer(audioBuffer, projectSampleRate);
        }

        // Use exact original duration - no modifications
        const startOffset = 0;
        const actualDuration = audioBuffer.duration;

        console.log('[AudioImport] Decoded audio:', {
          fileName: file.name,
          fileSize: file.size,
          bufferDuration: audioBuffer.duration,
          bufferLength: audioBuffer.length,
          sampleRate: audioBuffer.sampleRate,
          channels: audioBuffer.numberOfChannels,
          actualDuration,
        });

        // Match the primary import path: ~100 samples/sec, max 10000
        const waveformSamples = Math.min(10000, Math.max(200, Math.ceil(actualDuration * 100)));
        const waveform = generateWaveformFromBuffer(audioBuffer, waveformSamples, actualDuration, startOffset);

        const fileId = `audio_${Date.now()}_${i}`;
        const url = URL.createObjectURL(file);

        loadedFiles.push({
          id: fileId,
          name: file.name,
          file,
          url,
          duration: actualDuration,
          waveform,
          buffer: audioBuffer,
          sourceOffset: startOffset, // Store offset to skip leading silence
        });

        // Audio files are now loaded to pool only - user can drag them to timeline manually
        // No auto-creation of tracks/clips - timeline stays empty until user drags files

        setConsoleMessages(prev => [...prev, {
          id: Date.now().toString(),
          level: 'info',
          message: `Loaded: ${file.name} (${actualDuration.toFixed(1)}s)`,
          timestamp: new Date(),
        }]);
      } catch (err) {
        console.error(`Failed to load ${file.name}:`, err);
        setConsoleMessages(prev => [...prev, {
          id: Date.now().toString(),
          level: 'error',
          message: `Failed to load: ${file.name}`,
          timestamp: new Date(),
        }]);
      }
    }

    // NOTE: Don't close audioContext - it's shared by the entire app!
    // audioContext.close() would break all audio routing

    setImportedAudioFiles(loadedFiles);

    // Save to IndexedDB
    try {
      const storedFiles: StoredAudioFile[] = [];
      for (const loaded of loadedFiles) {
        if (loaded.buffer) {
          const channels = loaded.buffer.numberOfChannels;
          const length = loaded.buffer.length;
          const sampleRate = loaded.buffer.sampleRate;
          const headerSize = 3;
          const totalSize = headerSize + channels * length;
          const data = new Float32Array(totalSize);
          data[0] = sampleRate;
          data[1] = channels;
          data[2] = length;
          for (let ch = 0; ch < channels; ch++) {
            const channelData = loaded.buffer.getChannelData(ch);
            data.set(channelData, headerSize + ch * length);
          }
          storedFiles.push({
            id: loaded.id,
            name: loaded.name,
            arrayBuffer: data.buffer,
            duration: loaded.duration,
            waveform: loaded.waveform,
            sourceOffset: loaded.sourceOffset, // Preserve offset for restore
          });
        }
      }
      await saveAudioToDB(storedFiles);
      rfDebug('IndexedDB', 'Saved', storedFiles.length, 'audio files');
    } catch {
      // IndexedDB save failure is non-critical
    }

    logSlotEvent('IMPORT_AUDIO', `Loaded ${loadedFiles.length} audio files with waveforms`);

    // Auto-create events
    if (!workingRoutes?.events?.length && loadedFiles.length > 0) {
      const autoEvents: import('./core/routesTypes').EventRoute[] = loadedFiles.map(audio => ({
        name: audio.name.replace(/\.[^/.]+$/, ''),
        actions: [{
          type: 'Play' as const,
          assetId: audio.name,
          bus: 'SFX' as import('./core/routesTypes').RouteBus,
          gain: 1,
          loop: false,
        }],
      }));

      setWorkingRoutes({
        routesVersion: 1,
        defaultBus: 'SFX',
        events: autoEvents,
      });

      if (autoEvents.length > 0) {
        setSelectedEventName(autoEvents[0].name);
      }
      rfDebug('Import', 'Auto-created', autoEvents.length, 'events from audio files');
    }

    setConsoleMessages(prev => [...prev, {
      id: Date.now().toString(),
      level: 'info',
      message: `✅ Imported ${loadedFiles.length} audio files from ${sourceName}`,
      timestamp: new Date(),
    }]);
  }, [logSlotEvent, setConsoleMessages, generateWaveformFromBuffer, workingRoutes, setWorkingRoutes, addTrack, addClip]);

  const handleImportAudioFolder = useCallback(async () => {
    // Try modern File System Access API first (Chrome, Edge)
    if ('showDirectoryPicker' in window) {
      try {
        const dirHandle = await (window as unknown as { showDirectoryPicker: () => Promise<FileSystemDirectoryHandle> }).showDirectoryPicker();

        interface FileEntry { kind: string; name: string; getFile?: () => Promise<File> }
        const files: File[] = [];
        for await (const entry of (dirHandle as unknown as { values: () => AsyncIterable<FileEntry> }).values()) {
          if (entry.kind === 'file' && /\.(mp3|wav|ogg|m4a|flac)$/i.test(entry.name)) {
            const file = await entry.getFile!();
            files.push(file);
          }
        }

        await processAudioFiles(files, dirHandle.name);
      } catch (e) {
        if ((e as Error).name !== 'AbortError') {
          console.error('Import folder failed:', e);
          setConsoleMessages(prev => [...prev, {
            id: Date.now().toString(),
            level: 'error',
            message: `Import failed: ${(e as Error).message}`,
            timestamp: new Date(),
          }]);
        }
      }
    } else {
      // Fallback: use hidden file input for browsers without File System Access API
      const input = document.createElement('input');
      input.type = 'file';
      input.multiple = true;
      input.accept = '.mp3,.wav,.ogg,.m4a,.flac,audio/*';
      // Note: webkitdirectory is Chrome-only but works on some browsers
      input.setAttribute('webkitdirectory', '');
      input.setAttribute('directory', '');

      input.onchange = async () => {
        if (input.files && input.files.length > 0) {
          const audioFiles = Array.from(input.files).filter(f =>
            /\.(mp3|wav|ogg|m4a|flac)$/i.test(f.name)
          );
          await processAudioFiles(audioFiles, 'selected folder');
        }
      };

      input.click();
    }
  }, [processAudioFiles, setConsoleMessages]);

  // Control bar props
  const controlBarProps = useMemo(
    () => ({
      // Editor mode
      editorMode,
      onEditorModeChange: setEditorMode,
      // Transport
      isPlaying,
      isRecording,
      transportDisabled: false, // Transport enabled - Stop button stops all audio
      onPlay: handlePlay,
      onStop: handleStop,
      onRecord: handleRecord,
      onRewind: () => playbackSeek(Math.max(0, playbackCurrentTime - 4)),
      onForward: () => playbackSeek(Math.min(playbackDuration, playbackCurrentTime + 4)),
      tempo,
      onTempoChange: setTempo,
      timeSignature: [4, 4] as [number, number],
      currentTime,
      timeDisplayMode,
      onTimeDisplayModeChange: () =>
        setTimeDisplayMode((m) => (m === 'bars' ? 'timecode' : m === 'timecode' ? 'samples' : 'bars')),
      loopEnabled,
      onLoopToggle: () => setLoopEnabled((l) => !l),
      snapEnabled,
      snapValue,
      onSnapToggle: () => setSnapEnabled((s) => !s),
      onSnapValueChange: setSnapValue,
      metronomeEnabled,
      onMetronomeToggle: () => setMetronomeEnabled((m) => !m),
      cpuUsage: isPlaying ? Math.floor(15 + Math.random() * 10) : 8,
      memoryUsage: 42,
      projectName: `${projectFile?.name || 'ReelForge Project'}${isDirty ? ' *' : ''}`,
      // Menu callbacks
      menuCallbacks: {
        onNewProject: handleClearSession,
        onOpenProject: openProject,
        onSaveProject: () => saveProject(),
        onSaveProjectAs: saveProjectAs,
        onImportJSON: handleImportJSON,
        onExportJSON: handleExportJSON,
        onImportAudioFolder: handleImportAudioFolder,
        // Edit operations - now with real undo/redo
        onUndo: canUndo ? undo : undefined,
        onRedo: canRedo ? redo : undefined,
        onCut: () => logSlotEvent('EDIT', 'Cut'),
        onCopy: () => logSlotEvent('EDIT', 'Copy'),
        onPaste: () => logSlotEvent('EDIT', 'Paste'),
        onDelete: () => {
          if (selectedActionIndex !== null) {
            handleDeleteAction(selectedActionIndex);
          }
        },
        onSelectAll: () => logSlotEvent('EDIT', 'Select All'),
        // View operations - wired via MainLayout toggle functions
        // Project operations
        onProjectSettings: () => logSlotEvent('PROJECT', 'Open Settings'),
        onValidateProject: () => {
          if (workingRoutes) {
            const result = validateRoutes(workingRoutes, new Set());
            logSlotEvent('VALIDATE', `${result.errors.length} errors, ${result.warnings.length} warnings`);
          }
        },
        onBuildProject: () => logSlotEvent('PROJECT', 'Build Project'),
      },
    }),
    [editorMode, setEditorMode, isPlaying, isRecording, handlePlay, handleStop, handleRecord, tempo, currentTime, timeDisplayMode, loopEnabled, metronomeEnabled, projectFile, isDirty, handleClearSession, openProject, saveProject, saveProjectAs, handleImportJSON, handleExportJSON, handleImportAudioFolder, logSlotEvent, selectedActionIndex, handleDeleteAction, workingRoutes, canUndo, canRedo, undo, redo]
  );

  return (
    <MasterInsertProvider
      audioContext={audioContext}
      masterGain={masterGain}
    >
      <MainLayout
        controlBar={controlBarProps}
        projectTree={projectTree}
        selectedProjectId={selectedEventName ? `evt-${selectedEventName}` : null}
        onProjectSelect={handleProjectSelect}
        projectSearchQuery={searchQuery}
        onProjectSearchChange={setSearchQuery}
        inspectorType={selectedAction ? 'command' : selectedEvent ? 'event' : 'none'}
        inspectorName={selectedAction ? `${selectedAction.type} Action` : selectedEvent?.name || ''}
        inspectorSections={inspectorSections}
        editorMode={editorMode}
        channelStripData={channelStripData}
        onChannelVolumeChange={handleChannelVolumeChange}
        onChannelPanChange={handleChannelPanChange}
        onChannelMuteToggle={handleChannelMuteToggle}
        onChannelSoloToggle={handleChannelSoloToggle}
        lowerTabs={filterTabsForMode(lowerTabs, editorMode)}
        lowerTabGroups={filterTabGroupsForMode(lowerTabGroups, editorMode)}
        activeLowerTabId={activeLowerTab}
        onLowerTabChange={setActiveLowerTab}
      >
        {/* Center Zone Content - Mode-aware */}
        {editorMode === 'daw' ? (
          /* ========== DAW MODE: Full Timeline in Center ========== */
          <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
            {/* DAW Toolbar */}
            <div className="rf-tab-bar">
              <div className="rf-tab active">
                <span className="rf-tab__icon">🎬</span>
                <span>Project Timeline</span>
              </div>
              <div style={{ flex: 1 }} />
              {/* DAW-specific toggles */}
              <button
                className={`rf-zone-header__btn ${showLayeredMusic ? 'active' : ''}`}
                onClick={() => setShowLayeredMusic((v) => !v)}
                title="Detach Layered Music Editor"
                style={showLayeredMusic ? { background: 'var(--rf-accent-primary)', color: 'white' } : {}}
              >
                🎼
              </button>
              <button
                className={`rf-zone-header__btn ${showSpectrogram ? 'active' : ''}`}
                onClick={() => setShowSpectrogram((v) => !v)}
                title="Show Spectrogram"
                style={showSpectrogram ? { background: 'var(--rf-accent-primary)', color: 'white' } : {}}
              >
                📊
              </button>
              <div style={{ width: 1, height: 16, background: 'var(--rf-border)', margin: '0 4px' }} />
              <UndoRedoButtons compact />
              <div style={{ width: 1, height: 16, background: 'var(--rf-border)', margin: '0 4px' }} />
              <ThemeToggle showDropdown />
            </div>

            {/* Full Timeline View - Cubase-style center */}
            <div style={{ flex: 1, overflow: 'hidden' }}>
              <Timeline
                tracks={timelineTracks}
                clips={timelineClips}
                markers={[]}
                playheadPosition={currentTime}
                tempo={tempo}
                timeSignature={[4, 4]}
                zoom={zoom}
                scrollOffset={scrollOffset}
                totalDuration={32}
                timeDisplayMode={timeDisplayMode}
                loopRegion={loopRegion}
                loopEnabled={loopEnabled}
                onPlayheadChange={handlePlayheadChange}
                onClipSelect={handleClipSelect}
                onZoomChange={setZoom}
                onScrollChange={setScrollOffset}
                onLoopToggle={() => setLoopEnabled(l => !l)}
                onTrackMuteToggle={handleTrackMuteToggle}
                onTrackSoloToggle={handleTrackSoloToggle}
                onTrackSelect={setSelectedTrackId}
                onLoopRegionChange={setLoopRegion}
                onAudioDrop={handleTimelineAudioDrop}
                onNewTrackDrop={handleTimelineNewTrackDrop}
                onClipGainChange={handleClipGainChange}
                onClipFadeChange={handleClipFadeChange}
                onClipResize={handleClipResize}
                onClipSplit={handleClipSplit}
                onClipDuplicate={handleClipDuplicate}
                onClipMove={handleClipMove}
                onTrackColorChange={handleTrackColorChange}
                onTrackBusChange={handleTrackBusChange}
                onTrackRename={handleTrackRename}
                onClipRename={handleClipRename}
                onClipDelete={handleClipDelete}
                onClipCopy={handleClipCopy}
                onClipPaste={handleClipPaste}
                crossfades={crossfades}
                onCrossfadeCreate={handleCrossfadeCreate}
                onCrossfadeUpdate={handleCrossfadeUpdate}
                onCrossfadeDelete={handleCrossfadeDelete}
                instanceId="center-zone"
              />
            </div>
          </div>
        ) : (
          /* ========== MIDDLEWARE MODE: Events Editor in Center ========== */
          <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
            {/* Middleware Toolbar */}
            <div className="rf-tab-bar">
              <div className="rf-tab active">
                <span className="rf-tab__icon">🎯</span>
                <span>{selectedEvent?.name || 'Events'}</span>
              </div>
              <div style={{ flex: 1 }} />
              {/* Slot floating panel toggles */}
              <button
                className={`rf-zone-header__btn ${showSpinCycle ? 'active' : ''}`}
                onClick={() => setShowSpinCycle((v) => !v)}
                title="Detach Spin Cycle Editor"
                style={showSpinCycle ? { background: 'var(--rf-accent-primary)', color: 'white' } : {}}
              >
                🎰
              </button>
              <button
                className={`rf-zone-header__btn ${showWinTiers ? 'active' : ''}`}
                onClick={() => setShowWinTiers((v) => !v)}
                title="Detach Win Tiers Editor"
                style={showWinTiers ? { background: 'var(--rf-accent-primary)', color: 'white' } : {}}
              >
                🏆
              </button>
              <button
                className={`rf-zone-header__btn ${showReelSequencer ? 'active' : ''}`}
                onClick={() => setShowReelSequencer((v) => !v)}
                title="Detach Reel Sequencer"
                style={showReelSequencer ? { background: 'var(--rf-accent-primary)', color: 'white' } : {}}
              >
                ⏱️
              </button>
              <div style={{ width: 1, height: 16, background: 'var(--rf-border)', margin: '0 4px' }} />
              {/* Slot simulation button */}
              <Tooltip content="Run 1000 slot spins with audio" position="bottom">
                <button
                  onClick={runSlotSimulation}
                  disabled={isSlotSimulating}
                  style={{
                    padding: '4px 12px',
                    background: isSlotSimulating ? 'var(--rf-bg-3)' : 'linear-gradient(135deg, #f59e0b, #d97706)',
                    border: 'none',
                    borderRadius: 4,
                    color: 'white',
                    fontSize: 11,
                    fontWeight: 600,
                    cursor: isSlotSimulating ? 'not-allowed' : 'pointer',
                    opacity: isSlotSimulating ? 0.6 : 1,
                  }}
                >
                  {isSlotSimulating ? '⏳ Simulating...' : '▶ Run Slot Sim'}
                </button>
              </Tooltip>
              <div style={{ width: 1, height: 16, background: 'var(--rf-border)', margin: '0 4px' }} />
              <UndoRedoButtons compact />
              <div style={{ width: 1, height: 16, background: 'var(--rf-border)', margin: '0 4px' }} />
              <ThemeToggle showDropdown />
            </div>

            {/* Events Editor Content */}
          <div className="rf-editor rf-scrollbar">
            {selectedEvent ? (
              <>
                <div style={{ marginBottom: 16 }}>
                  <h2 style={{ margin: '0 0 8px', fontSize: 16, fontWeight: 600 }}>
                    Event: {selectedEvent.name}
                  </h2>
                  <p style={{ margin: 0, fontSize: 12, color: 'var(--rf-text-secondary)' }}>
                    {selectedEvent.actions.length} action(s)
                  </p>
                </div>

                {/* Actions Table - Compact responsive layout */}
                <div className="rf-commands-wrapper">
                  <table className="rf-commands-table">
                    <thead>
                      <tr>
                        <th>#</th>
                        <th>Type</th>
                        <th>Asset</th>
                        <th>Bus</th>
                        <th>Gain</th>
                        <th>Loop</th>
                        <th>Pan</th>
                        <th>Delay</th>
                        <th>Fade</th>
                        <th>Dur</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      {selectedEvent.actions.map((action, idx) => {
                        const isSelected = selectedActionIndex === idx;
                        const isMultiSelected = selectedActionIndices.has(idx);
                        const assetId = (isPlayAction(action) || isFadeAction(action)) ? action.assetId :
                                        (isStopAction(action) || isPauseAction(action)) ? action.assetId : null;
                        const eventId = isExecuteAction(action) ? action.eventId : null;
                        const isDragging = draggedActionIndex === idx;
                        const isDragOver = dragOverIndex === idx;

                        return (
                          <tr
                            key={idx}
                            className={`cmd-${action.type.toLowerCase()} ${isSelected ? 'selected' : ''} ${isMultiSelected ? 'multi-selected' : ''} ${isDragging ? 'dragging' : ''} ${isDragOver ? 'drag-over' : ''}`}
                            onClick={(e) => handleActionClick(idx, e)}
                            draggable
                            onDragStart={(e) => {
                              setDraggedActionIndex(idx);
                              e.dataTransfer.effectAllowed = 'move';
                              e.dataTransfer.setData('text/plain', String(idx));
                            }}
                            onDragEnd={() => {
                              setDraggedActionIndex(null);
                              setDragOverIndex(null);
                            }}
                            onDragOver={(e) => {
                              e.preventDefault();
                              e.dataTransfer.dropEffect = 'move';
                              if (draggedActionIndex !== null && draggedActionIndex !== idx) {
                                setDragOverIndex(idx);
                              }
                            }}
                            onDragLeave={() => {
                              setDragOverIndex(null);
                            }}
                            onDrop={(e) => {
                              e.preventDefault();
                              if (draggedActionIndex !== null && draggedActionIndex !== idx) {
                                handleReorderAction(draggedActionIndex, idx);
                              }
                              setDraggedActionIndex(null);
                              setDragOverIndex(null);
                            }}
                          >
                            <td className="col-num" style={{ cursor: 'grab' }}>⋮⋮ {idx + 1}</td>
                            {/* Type dropdown */}
                            <td className="col-type" onClick={(e) => e.stopPropagation()}>
                              <select
                                value={action.type}
                                onChange={(e) => handleActionUpdate(idx, { type: e.target.value as RouteAction['type'] })}
                                className="rf-inline-select"
                              >
                                <option value="Play">▶ Play</option>
                                <option value="Stop">⏹ Stop</option>
                                <option value="StopAll">⏹ All</option>
                                <option value="Fade">🔀 Fade</option>
                                <option value="Pause">⏸ Pause</option>
                                <option value="SetBusGain">🔊 Bus</option>
                                <option value="Execute">🎬 Exec</option>
                              </select>
                            </td>
                            {/* Asset ID - dropdown with imported files + manual input; Event ID for Execute */}
                            <td className="col-asset" onClick={(e) => e.stopPropagation()}>
                              {assetId !== null ? (
                                <select
                                  value={assetId || ''}
                                  onChange={(e) => handleActionUpdate(idx, { assetId: e.target.value || undefined })}
                                  className="rf-inline-select"
                                >
                                  <option value="">-- Select --</option>
                                  {importedAudioFiles.map(audio => (
                                    <option key={audio.id} value={audio.name}>{audio.name}</option>
                                  ))}
                                  {/* Show current value if not in list */}
                                  {assetId && !importedAudioFiles.find(a => a.name === assetId) && (
                                    <option value={assetId}>{assetId}</option>
                                  )}
                                </select>
                              ) : eventId !== null ? (
                                <select
                                  value={eventId || ''}
                                  onChange={(e) => handleActionUpdate(idx, { eventId: e.target.value || undefined })}
                                  className="rf-inline-select"
                                  style={{ color: 'var(--rf-accent-secondary)' }}
                                >
                                  <option value="">-- Event --</option>
                                  {routes?.events.filter(ev => ev.name !== selectedEvent.name).map(ev => (
                                    <option key={ev.name} value={ev.name}>{ev.name}</option>
                                  ))}
                                  {/* Show current value if not in list */}
                                  {eventId && !routes?.events.find(e => e.name === eventId) && (
                                    <option value={eventId}>{eventId}</option>
                                  )}
                                </select>
                              ) : <span className="rf-na">—</span>}
                            </td>
                            {/* Bus dropdown */}
                            <td className="col-bus" onClick={(e) => e.stopPropagation()}>
                              {(isPlayAction(action) || isSetBusGainAction(action)) ? (
                                <select
                                  value={isPlayAction(action) ? action.bus || routes?.defaultBus || 'SFX' : action.bus}
                                  onChange={(e) => handleActionUpdate(idx, { bus: e.target.value as RouteBus })}
                                  className="rf-inline-select"
                                >
                                  <option value="SFX">SFX</option>
                                  <option value="Music">Music</option>
                                  <option value="UI">UI</option>
                                  <option value="VO">VO</option>
                                  <option value="Master">Master</option>
                                </select>
                              ) : <span className="rf-na">—</span>}
                            </td>
                            {/* Gain */}
                            <td className="col-gain" onClick={(e) => e.stopPropagation()}>
                              {(isPlayAction(action) || isSetBusGainAction(action)) ? (
                                <NumberInput
                                  value={(action.gain ?? 1) * 100}
                                  onChange={(v) => handleActionUpdate(idx, { gain: v / 100 })}
                                  min={0} max={100} step={1} precision={0}
                                  units="%" size="small" showButtons={false}
                                />
                              ) : isFadeAction(action) ? (
                                <NumberInput
                                  value={action.targetVolume * 100}
                                  onChange={(v) => handleActionUpdate(idx, { targetVolume: v / 100 })}
                                  min={0} max={100} step={1} precision={0}
                                  units="%" size="small" showButtons={false}
                                />
                              ) : <span className="rf-na">—</span>}
                            </td>
                            {/* Loop - combined checkbox + count */}
                            <td className="col-loop" onClick={(e) => e.stopPropagation()}>
                              {isPlayAction(action) ? (
                                <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                                  <input
                                    type="checkbox"
                                    checked={action.loop ?? false}
                                    onChange={(e) => handleActionUpdate(idx, { loop: e.target.checked })}
                                  />
                                  {action.loop && (
                                    <span style={{ fontSize: 9, color: 'var(--rf-text-secondary)' }}>
                                      {action.loopCount === 0 ? '∞' : action.loopCount}
                                    </span>
                                  )}
                                </div>
                              ) : <span className="rf-na">—</span>}
                            </td>
                            {/* Pan */}
                            <td className="col-pan" onClick={(e) => e.stopPropagation()}>
                              {(isPlayAction(action) || isFadeAction(action)) ? (
                                <NumberInput
                                  value={Math.round((action.pan ?? 0) * 100)}
                                  onChange={(v) => handleActionUpdate(idx, { pan: v / 100 })}
                                  min={-100} max={100} step={5} precision={0}
                                  size="small" showButtons={false}
                                />
                              ) : <span className="rf-na">—</span>}
                            </td>
                            {/* Delay */}
                            <td className="col-delay" onClick={(e) => e.stopPropagation()}>
                              {(isPlayAction(action) || isStopAction(action) || isFadeAction(action) || isPauseAction(action) || isExecuteAction(action)) ? (
                                <NumberInput
                                  value={action.delay ?? 0}
                                  onChange={(v) => handleActionUpdate(idx, { delay: v })}
                                  min={0} max={60} step={0.1} precision={1}
                                  units="s" size="small" showButtons={false}
                                />
                              ) : <span className="rf-na">—</span>}
                            </td>
                            {/* Fade - shows fadeIn for Play, fadeOut for Stop/Pause */}
                            <td className="col-fade" onClick={(e) => e.stopPropagation()}>
                              {isPlayAction(action) ? (
                                <NumberInput
                                  value={action.fadeIn ?? 0}
                                  onChange={(v) => handleActionUpdate(idx, { fadeIn: v })}
                                  min={0} max={30} step={0.1} precision={1}
                                  units="s" size="small" showButtons={false}
                                />
                              ) : (isStopAction(action) || isStopAllAction(action) || isPauseAction(action)) ? (
                                <NumberInput
                                  value={action.fadeOut ?? 0}
                                  onChange={(v) => handleActionUpdate(idx, { fadeOut: v })}
                                  min={0} max={30} step={0.1} precision={1}
                                  units="s" size="small" showButtons={false}
                                />
                              ) : <span className="rf-na">—</span>}
                            </td>
                            {/* Duration */}
                            <td className="col-dur" onClick={(e) => e.stopPropagation()}>
                              {(isFadeAction(action) || isSetBusGainAction(action)) ? (
                                <NumberInput
                                  value={action.duration ?? 0}
                                  onChange={(v) => handleActionUpdate(idx, { duration: v })}
                                  min={0} max={60} step={0.1} precision={1}
                                  units="s" size="small" showButtons={false}
                                />
                              ) : <span className="rf-na">—</span>}
                            </td>
                            {/* Actions */}
                            <td className="col-actions">
                              <button
                                onClick={(e) => { e.stopPropagation(); handlePreviewAction(action); }}
                                className="rf-icon-btn" title="Play"
                                style={{ color: '#22c55e' }}
                              >▶</button>
                              <button
                                onClick={(e) => { e.stopPropagation(); handleDuplicateAction(idx); }}
                                className="rf-icon-btn" title="Duplicate"
                              >📋</button>
                              <button
                                onClick={(e) => { e.stopPropagation(); handleDeleteAction(idx); }}
                                className="rf-icon-btn" title="Delete"
                              >🗑️</button>
                            </td>
                          </tr>
                        );
                      })}
                      {selectedEvent.actions.length === 0 && (
                        <tr>
                          <td colSpan={11} style={{ textAlign: 'center', color: 'var(--rf-text-tertiary)', padding: 24 }}>
                            No actions. Click "+ Add Action" to create one.
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                </div>

                {/* Action buttons with dropdown for type selection */}
                <div style={{ marginTop: 16, display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                  <button
                    onClick={() => handleAddAction('Play')}
                    style={{
                      padding: '6px 12px',
                      background: 'var(--rf-accent-primary)',
                      border: 'none',
                      borderRadius: 4,
                      color: 'white',
                      fontSize: 11,
                      cursor: 'pointer',
                    }}
                  >▶ Play</button>
                  <button
                    onClick={() => handleAddAction('Stop')}
                    style={{
                      padding: '6px 12px',
                      background: 'var(--rf-bg-3)',
                      border: '1px solid var(--rf-border)',
                      borderRadius: 4,
                      color: 'var(--rf-text-primary)',
                      fontSize: 11,
                      cursor: 'pointer',
                    }}
                  >⏹ Stop</button>
                  <button
                    onClick={() => handleAddAction('Fade')}
                    style={{
                      padding: '6px 12px',
                      background: 'var(--rf-bg-3)',
                      border: '1px solid var(--rf-border)',
                      borderRadius: 4,
                      color: 'var(--rf-text-primary)',
                      fontSize: 11,
                      cursor: 'pointer',
                    }}
                  >🔀 Fade</button>
                  <button
                    onClick={() => handleAddAction('Pause')}
                    style={{
                      padding: '6px 12px',
                      background: 'var(--rf-bg-3)',
                      border: '1px solid var(--rf-border)',
                      borderRadius: 4,
                      color: 'var(--rf-text-primary)',
                      fontSize: 11,
                      cursor: 'pointer',
                    }}
                  >⏸ Pause</button>
                  <button
                    onClick={() => handleAddAction('SetBusGain')}
                    style={{
                      padding: '6px 12px',
                      background: 'var(--rf-bg-3)',
                      border: '1px solid var(--rf-border)',
                      borderRadius: 4,
                      color: 'var(--rf-text-primary)',
                      fontSize: 11,
                      cursor: 'pointer',
                    }}
                  >🔊 Bus Gain</button>
                  <button
                    onClick={() => handleAddAction('StopAll')}
                    style={{
                      padding: '6px 12px',
                      background: 'var(--rf-bg-3)',
                      border: '1px solid var(--rf-border)',
                      borderRadius: 4,
                      color: 'var(--rf-text-primary)',
                      fontSize: 11,
                      cursor: 'pointer',
                    }}
                  >⏹⏹ Stop All</button>
                  <button
                    onClick={() => handleAddAction('Execute')}
                    style={{
                      padding: '6px 12px',
                      background: 'var(--rf-bg-3)',
                      border: '1px solid var(--rf-border)',
                      borderRadius: 4,
                      color: 'var(--rf-text-primary)',
                      fontSize: 11,
                      cursor: 'pointer',
                    }}
                  >🎬 Execute</button>
                  <button
                    onClick={() => {
                      if (hasActiveAudio) {
                        stopAllAudio();
                        logSlotEvent('STOP', selectedEvent.name);
                      } else {
                        handlePreviewEvent();
                        logSlotEvent('PREVIEW', selectedEvent.name);
                      }
                    }}
                    style={{
                      padding: '8px 16px',
                      background: hasActiveAudio
                        ? 'linear-gradient(135deg, #ef4444, #dc2626)'
                        : 'linear-gradient(135deg, #10b981, #059669)',
                      border: 'none',
                      borderRadius: 4,
                      color: 'white',
                      fontSize: 12,
                      fontWeight: 600,
                      cursor: 'pointer',
                      transition: 'background 0.15s ease',
                    }}
                  >
                    {hasActiveAudio ? '⏹ Stop' : '▶ Preview Event'}
                  </button>
                  <button
                    onClick={playTestTone}
                    title={`Play 440Hz test tone. DSP: ${masterInsertDSP.isInitialized() ? 'OK' : 'NOT READY'}, Ctx: ${audioContext.state}`}
                    style={{
                      padding: '6px 10px',
                      background: masterInsertDSP.isInitialized() ? 'var(--rf-bg-3)' : '#ef4444',
                      border: '1px solid var(--rf-border)',
                      borderRadius: 4,
                      color: masterInsertDSP.isInitialized() ? 'var(--rf-text-secondary)' : 'white',
                      fontSize: 11,
                      cursor: 'pointer',
                    }}
                  >
                    🔊 Test Tone {!masterInsertDSP.isInitialized() && '⚠️'}
                  </button>
                  <button
                    onClick={() => setAllowOverlap(!allowOverlap)}
                    title={allowOverlap ? 'Overlap enabled - sounds will layer' : 'Overlap disabled - stops previous before playing'}
                    style={{
                      padding: '6px 10px',
                      background: allowOverlap ? 'var(--rf-accent-primary)' : 'var(--rf-bg-3)',
                      border: `1px solid ${allowOverlap ? 'var(--rf-accent-primary)' : 'var(--rf-border)'}`,
                      borderRadius: 4,
                      color: allowOverlap ? 'white' : 'var(--rf-text-secondary)',
                      fontSize: 11,
                      cursor: 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      gap: 4,
                    }}
                  >
                    {allowOverlap ? '🔊' : '🔇'} Overlap
                  </button>
                </div>
              </>
            ) : (
              <div style={{ padding: 32, textAlign: 'center', color: 'var(--rf-text-tertiary)' }}>
                <div style={{ fontSize: 48, marginBottom: 16 }}>🎧</div>
                <h3 style={{ margin: '0 0 8px', color: 'var(--rf-text-secondary)' }}>
                  {routes ? 'Select an Event' : 'No Project Loaded'}
                </h3>
                <p style={{ margin: 0, fontSize: 13 }}>
                  {routes
                    ? 'Choose an event from the Project Browser on the left to edit its actions.'
                    : 'Load a project file to begin editing.'}
                </p>
                {routes && (
                  <button
                    onClick={handleAddEvent}
                    style={{
                      marginTop: 16,
                      padding: '8px 16px',
                      background: 'var(--rf-accent-primary)',
                      border: 'none',
                      borderRadius: 4,
                      color: 'white',
                      fontSize: 12,
                      cursor: 'pointer',
                    }}
                  >
                    + Create New Event
                  </button>
                )}
              </div>
            )}
          </div>
        </div>
        )}
      </MainLayout>

      {/* Floating Panels */}
      {showLayeredMusic && (
        <DockablePanel
          id="layeredMusic"
          title="Layered Music Editor"
          icon="🎼"
          initialDocked={false}
          initialPosition={{ x: 100, y: 100 }}
          initialSize={{ width: 600, height: 450 }}
          zIndex={panelManager.getZIndex('layeredMusic')}
          onFocus={() => panelManager.bringToFront('layeredMusic')}
          onClose={() => setShowLayeredMusic(false)}
        >
          <LayeredMusicEditor
            layers={musicLayers}
            blendCurves={blendCurves}
            states={musicStates}
            currentStateId={currentMusicState}
            rtpcValue={rtpcValue}
            rtpcName="Intensity"
            onLayerChange={handleLayerChange}
            onBlendCurveChange={handleBlendCurveChange}
            onStateChange={setCurrentMusicState}
            onRtpcChange={setRtpcValue}
          />
        </DockablePanel>
      )}

      {showSpectrogram && (
        <DockablePanel
          id="spectrogram"
          title="Spectrogram"
          icon="📊"
          initialDocked={false}
          initialPosition={{ x: 150, y: 150 }}
          initialSize={{ width: 500, height: 300 }}
          zIndex={panelManager.getZIndex('spectrogram')}
          onFocus={() => panelManager.bringToFront('spectrogram')}
          onClose={() => setShowSpectrogram(false)}
        >
          <div style={{ padding: 16, height: '100%', display: 'flex', flexDirection: 'column' }}>
            <div style={{ fontSize: 11, color: 'var(--rf-text-tertiary)', marginBottom: 8 }}>
              Real-time frequency analysis
            </div>
            <div
              style={{
                flex: 1,
                background: 'linear-gradient(180deg, #1a0a2e 0%, #0a1628 50%, #0a2810 100%)',
                borderRadius: 4,
                display: 'flex',
                alignItems: 'flex-end',
                justifyContent: 'space-around',
                padding: '0 8px 8px',
              }}
            >
              {/* Fake spectrogram bars */}
              {Array.from({ length: 32 }).map((_, i) => (
                <div
                  key={i}
                  style={{
                    width: 8,
                    height: `${(isPlaying ? (Math.sin(i * 0.5 + currentTime * 4) + 1) * 30 + Math.random() * 20 : 10 + Math.random() * 5)}%`,
                    background: `linear-gradient(180deg, #ff6b6b, #ffd93d ${50 + i * 1.5}%, #6bcb77)`,
                    borderRadius: 2,
                    transition: 'height 50ms ease-out',
                  }}
                />
              ))}
            </div>
          </div>
        </DockablePanel>
      )}

      {/* ========== SLOT FLOATING PANELS ========== */}
      {showSpinCycle && (
        <DockablePanel
          id="spinCycle"
          title="Spin Cycle Editor"
          icon="🎰"
          initialDocked={false}
          initialPosition={{ x: 200, y: 80 }}
          initialSize={{ width: 700, height: 500 }}
          zIndex={panelManager.getZIndex('spinCycle')}
          onFocus={() => panelManager.bringToFront('spinCycle')}
          onClose={() => setShowSpinCycle(false)}
        >
          <SpinCycleEditor
            config={spinConfig}
            currentState={currentSpinState}
            isSimulating={isSlotSimulating}
            onConfigChange={setSpinConfig}
            onStateChange={(state) => {
              setCurrentSpinState(state);
              logSlotEvent('MANUAL_STATE', state);
            }}
            onSoundSelect={(state, soundId) => {
              logSlotEvent('SOUND_SELECT', `${state}:${soundId}`);
            }}
          />
        </DockablePanel>
      )}

      {showWinTiers && (
        <DockablePanel
          id="winTiers"
          title="Win Tiers Editor"
          icon="🏆"
          initialDocked={false}
          initialPosition={{ x: 250, y: 100 }}
          initialSize={{ width: 600, height: 550 }}
          zIndex={panelManager.getZIndex('winTiers')}
          onFocus={() => panelManager.bringToFront('winTiers')}
          onClose={() => setShowWinTiers(false)}
        >
          <WinTierEditor
            tiers={winTiers}
            activeTier={activeTier}
            onTierChange={setWinTiers}
            onTierSelect={(tier) => {
              setActiveTier(tier);
              logSlotEvent('TIER_SELECT', tier);
            }}
            onPreview={(tier) => {
              logSlotEvent('TIER_PREVIEW', tier);
            }}
          />
        </DockablePanel>
      )}

      {showReelSequencer && (
        <DockablePanel
          id="reelSequencer"
          title="Reel Stop Sequencer"
          icon="⏱️"
          initialDocked={false}
          initialPosition={{ x: 180, y: 120 }}
          initialSize={{ width: 800, height: 450 }}
          zIndex={panelManager.getZIndex('reelSequencer')}
          onFocus={() => panelManager.bringToFront('reelSequencer')}
          onClose={() => setShowReelSequencer(false)}
        >
          <ReelStopSequencer
            reels={reelConfigs}
            totalDuration={2500}
            currentTime={sequencerTime}
            isPlaying={isSequencerPlaying}
            onReelChange={setReelConfigs}
            onPlay={() => {
              setIsSequencerPlaying(true);
              logSlotEvent('SEQUENCER_START', 'Playback started');
            }}
            onStop={() => {
              setIsSequencerPlaying(false);
              logSlotEvent('SEQUENCER_PAUSE', 'Playback paused');
            }}
            onSeek={(time) => {
              setSequencerTime(time);
              logSlotEvent('SEQUENCER_SEEK', `${time}ms`);
            }}
          />
        </DockablePanel>
      )}

      {/* Plugin Picker Popup */}
      {pluginPickerState && (
        <PluginPicker
          busId={pluginPickerState.busId}
          slotIndex={pluginPickerState.slotIndex}
          currentInsert={pluginPickerState.currentInsert}
          position={pluginPickerState.position}
          isBypassed={pluginPickerState.currentInsert?.bypassed ?? false}
          onSelect={handlePluginSelect}
          onRemove={handleInsertRemove}
          onBypassToggle={handleInsertBypassToggle}
          onClose={handlePluginPickerClose}
        />
      )}

      {/* Batch Import Progress Overlay */}
      {importProgress.isImporting && (
        <div className="rf-import-progress-overlay">
          <div className="rf-import-progress">
            <div className="rf-import-progress__header">
              <span className="rf-import-progress__title">Importing Audio Files</span>
              <span className="rf-import-progress__count">
                {importProgress.current + 1} / {importProgress.total}
              </span>
            </div>
            <div className="rf-import-progress__bar-container">
              <div
                className="rf-import-progress__bar"
                style={{ width: `${((importProgress.current + 1) / importProgress.total) * 100}%` }}
              />
            </div>
            <div className="rf-import-progress__current">
              {importProgress.currentFileName === 'Complete'
                ? `✓ Imported ${importProgress.total} file${importProgress.total !== 1 ? 's' : ''}`
                : `Processing: ${importProgress.currentFileName}`
              }
            </div>
            {importProgress.errors.length > 0 && (
              <div className="rf-import-progress__errors">
                <div className="rf-import-progress__errors-title">
                  ⚠️ {importProgress.errors.length} error{importProgress.errors.length !== 1 ? 's' : ''}
                </div>
                {importProgress.errors.slice(0, 3).map((err, i) => (
                  <div key={i} className="rf-import-progress__error">{err}</div>
                ))}
                {importProgress.errors.length > 3 && (
                  <div className="rf-import-progress__error-more">
                    ...and {importProgress.errors.length - 3} more
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      )}

      {/* Cubase-style Import Options Dialog */}
      <ImportOptionsDialog
        files={filesToImport}
        projectSampleRate={48000}
        isOpen={importDialogOpen}
        onImport={handleImportWithOptions}
        onCancel={handleImportCancel}
      />
    </MasterInsertProvider>
  );
}

export default LayoutDemo;
