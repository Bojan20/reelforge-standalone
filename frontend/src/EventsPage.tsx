import { useState, useRef, useMemo, useEffect, useCallback, useDeferredValue } from "react";
import "./EventsPage.css";
import DetachableMixer from "./DetachableMixer";
import EngineTab from "./EngineTab";
import { AudioContextManager } from "./core/AudioContextManager";
import { EngineClient, type EngineStatus, type EngineLogEntry, type IncomingMessage } from "./core/engineClient";
import type {
  ReelForgeProject,
  AudioFileObject,
  PlayCommand,
  StopCommand,
  FadeCommand,
  PauseCommand,
  ExecuteCommand,
  Command,
  TemplateJSON,
  CommandType,
  SoundUsage,
  BusId,
  AudioSpriteItem,
} from "./core/types";
import { templateJsonToProject, projectToTemplateJson } from "./core/templateAdapter";
import { saveAudioFileToDB, loadAudioFilesFromDB } from "./core/persistence";
import { AudioEngine, type AudioEngineState } from "./core/audioEngine";
import { useProjectHistory } from "./hooks/useProjectHistory";
import { useRuntimeCore, LATENCY_UPDATE_INTERVAL_MS } from "./hooks/useRuntimeCore";
import { useDetachablePanel } from "./hooks/useDetachablePanel";
import { useEventActions } from "./hooks/useEventActions";
import { useDragDrop } from "./hooks/useDragDrop";
import { useCommandActions } from "./hooks/useCommandActions";
import { usePlaybackControls } from "./hooks/usePlaybackControls";
import { validateProject, ensureProjectBuses } from "./core/validateProject";
import { useMixer } from "./store";
import {
  type LatencyStats,
  type AdapterCommand,
  type BusId as BackendBusId
} from "./runtimeStub";
import {
  type NativeAdapterCommand
} from "./core/nativeRuntimeCore";
import ProjectHeader from "./components/ProjectHeader";
import { usePreviewExecutor, type ExecutableCommand } from "./hooks/usePreviewExecutor";
import { MasterInsertProvider } from "./core/MasterInsertContext";
import { BusInsertProvider } from "./core/BusInsertContext";
import { AssetInsertProvider } from "./core/AssetInsertContext";
import DiagnosticsHUD from "./components/DiagnosticsHUD";
import { ValidationDialog, type ValidationDialogData } from "./components/ValidationDialog";
import { useProject } from "./project/ProjectContext";
import { ShortcutsPanel } from "./shortcuts/ShortcutsPanel";
import { useShortcutManager, DEFAULT_SHORTCUTS } from "./shortcuts/useKeyboardShortcuts";
import { HistoryPanel } from "./history/HistoryPanel";
import { useErrorToasts, ErrorToastContainer } from "./components/RFErrorBanner";
import { AudioLoopUploader } from "./components/AudioLoopUploader";
import { FileBrowser, type FileNode } from "./browser/FileBrowser";
import { TransportBar } from "./transport/TransportBar";
import { WaveformDisplay, generateWaveformPeaks } from "./audio/WaveformDisplay";
import { Arrangement, useArrangement, type Track as ArrangementTrack, type Clip as ArrangementClip } from "./arrangement/Arrangement";

function formatDecimal(value: number | undefined | null, decimals: number = 2): string {
  if (value === undefined || value === null) return "";
  return Number(value).toLocaleString('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
    useGrouping: false
  });
}

export default function EventsPage() {
  const { setProject: setMixerProject } = useMixer();
  const { project: projectFile } = useProject();
  const [project, setProject] = useState<ReelForgeProject | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [selectedEventId, setSelectedEventId] = useState<string | null>(null);
  const [selectedCommandIndex, setSelectedCommandIndex] = useState<number | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [soundSearchQuery, setSoundSearchQuery] = useState("");

  // Deferred values for smoother search - prevents UI jank on large lists
  const deferredSearchQuery = useDeferredValue(searchQuery);
  const deferredSoundSearchQuery = useDeferredValue(soundSearchQuery);
  const [eventTab, setEventTab] = useState<"all" | "used">("all");
  const [viewMode, setViewMode] = useState<"events" | "sounds" | "engine" | "browser" | "loops" | "timeline" | "presets">(() => {
    const saved = localStorage.getItem('reelforge-view-mode');
    if (saved === 'events' || saved === 'sounds' || saved === 'engine' || saved === 'browser' || saved === 'loops' || saved === 'timeline' || saved === 'presets') {
      return saved;
    }
    return "events";
  });
  const [selectedSoundId, setSelectedSoundId] = useState<string | null>(null);
  const [waveformData, setWaveformData] = useState<Float32Array | null>(null);
  const [isLoadingWaveform, setIsLoadingWaveform] = useState(false);

  const [audioFiles, setAudioFiles] = useState<AudioFileObject[]>([]);

  // DAW Timeline state
  const [dawTempo, setDawTempo] = useState(120);
  const [dawPlayhead, setDawPlayhead] = useState(0);
  const [dawLoopEnabled, setDawLoopEnabled] = useState(false);
  const [dawLoopStart, _setDawLoopStart] = useState(0);
  const [dawLoopEnd, _setDawLoopEnd] = useState(16);
  void _setDawLoopStart; void _setDawLoopEnd; // Will be used for loop region dragging
  const [dawMetronome, setDawMetronome] = useState(false);
  const [dawTimeSignature] = useState<[number, number]>([4, 4]);

  // Demo tracks for DAW
  const demoTracks: ArrangementTrack[] = useMemo(() => [
    { id: 'track-1', name: 'Music', type: 'audio', color: '#4a9eff', height: 80 },
    { id: 'track-2', name: 'SFX', type: 'audio', color: '#51cf66', height: 80 },
    { id: 'track-3', name: 'Voice', type: 'audio', color: '#ffd43b', height: 80 },
    { id: 'track-4', name: 'Ambience', type: 'audio', color: '#be4bdb', height: 80 },
  ], []);

  const demoClips: ArrangementClip[] = useMemo(() => [
    { id: 'clip-1', trackId: 'track-1', start: 0, duration: 8, name: 'Intro Music', color: '#4a9eff' },
    { id: 'clip-2', trackId: 'track-1', start: 8, duration: 16, name: 'Main Theme', color: '#4a9eff' },
    { id: 'clip-3', trackId: 'track-2', start: 4, duration: 2, name: 'Impact SFX', color: '#51cf66' },
    { id: 'clip-4', trackId: 'track-2', start: 12, duration: 4, name: 'Whoosh', color: '#51cf66' },
    { id: 'clip-5', trackId: 'track-3', start: 2, duration: 6, name: 'Narrator VO', color: '#ffd43b' },
    { id: 'clip-6', trackId: 'track-4', start: 0, duration: 24, name: 'Forest Ambience', color: '#be4bdb' },
  ], []);

  const arrangement = useArrangement(demoTracks, demoClips);

  const { saveToHistory, undo, redo, canUndo, canRedo, reset: resetHistory } = useProjectHistory();

  // NOTE: draggedCommandIndex, draggedEventId moved to useDragDrop hook
  const [isDragOver, setIsDragOver] = useState(false);

  const [draftVolume, setDraftVolume] = useState<string | null>(null);
  const [draftPan, setDraftPan] = useState<string | null>(null);
  const [inspectorAnimationClass, setInspectorAnimationClass] = useState<string>('');

  // Command Inspector panel (detachable)
  const {
    isOpen: isInspectorOpen,
    setIsOpen: setIsInspectorOpen,
    isDetached: isInspectorDetached,
    setIsDetached: setIsInspectorDetached,
    position: detachedInspectorPosition,
    size: detachedInspectorSize,
    isDragging: isDraggingInspector,
    startDrag: startInspectorDrag,
    startResize: startInspectorResize,
  } = useDetachablePanel({
    initialPosition: { x: 100, y: 100 },
    initialSize: { width: 350, height: 600 },
    minSize: { width: 280, height: 300 },
    initialOpen: false,
  });

  // Sound Inspector panel (detachable)
  const {
    isOpen: isSoundInspectorOpen,
    setIsOpen: setIsSoundInspectorOpen,
    isDetached: isSoundInspectorDetached,
    setIsDetached: setIsSoundInspectorDetached,
    position: detachedSoundInspectorPosition,
    size: detachedSoundInspectorSize,
    startDrag: startSoundInspectorDrag,
    startResize: startSoundInspectorResize,
  } = useDetachablePanel({
    initialPosition: { x: 150, y: 150 },
    initialSize: { width: 320, height: 500 },
    minSize: { width: 280, height: 300 },
    initialOpen: true,
  });
  const [volumeSliderOpen, setVolumeSliderOpen] = useState<number | null>(null);
  const [panSliderOpen, setPanSliderOpen] = useState<number | string | null>(null);
  const [tableVolumeDraft, setTableVolumeDraft] = useState<{ [key: number]: string }>({});
  const [tablePanDraft, setTablePanDraft] = useState<{ [key: number]: string }>({});
  const volumeClickTimer = useRef<{ [key: number]: ReturnType<typeof setTimeout> | null }>({});

  const [engineStatus, setEngineStatus] = useState<EngineStatus>('disconnected');
  const [engineLogs, setEngineLogs] = useState<EngineLogEntry[]>([]);
  const [engineUrl, setEngineUrl] = useState('ws://localhost:7777');

  // NOTE: RuntimeStub/NativeCore state moved to useRuntimeCore hook

  const engineClientRef = useRef<EngineClient | null>(null);

  const audioRef = useRef<HTMLAudioElement | null>(null);
  const audioSourceRef = useRef<AudioBufferSourceNode | null>(null);
  const gainNodeRef = useRef<GainNode | null>(null);
  const panNodeRef = useRef<StereoPannerNode | null>(null);
  const eventAudioRefsMap = useRef<Map<string, HTMLAudioElement[]>>(new Map());
  const soundAudioMap = useRef<Map<string, { audio: HTMLAudioElement; gainNode?: GainNode; source?: AudioBufferSourceNode; panNode?: StereoPannerNode; eventId?: string; instanceKey?: string }[]>>(new Map());
  const busGainsRef = useRef<Record<string, GainNode> | null>(null);

  // Audio context - use shared singleton for MasterInsertDSP
  const audioContext = useMemo(() => AudioContextManager.getContext(), []);
  const masterGain = useMemo(() => {
    const gain = audioContext.createGain();
    gain.gain.value = 1;
    return gain;
  }, [audioContext]);

  // Keep refs for backward compatibility with existing code
  const audioContextRef = useRef<AudioContext | null>(audioContext);
  const masterGainRef = useRef<GainNode | null>(masterGain);
  audioContextRef.current = audioContext;
  masterGainRef.current = masterGain;
  const [commandTypeSettings, setCommandTypeSettings] = useState<Map<string, Record<CommandType, Partial<Command>>>>(new Map());
  const [isPlaying, setIsPlaying] = useState(false);
  const [playingEvents, setPlayingEvents] = useState<Set<string>>(new Set());
  const [currentPlayingSound, setCurrentPlayingSound] = useState<string>("");
  const [validationDialog, setValidationDialog] = useState<ValidationDialogData | null>(null);

  const fileInputRef = useRef<HTMLInputElement>(null);
  const audioFilesInputRef = useRef<HTMLInputElement>(null);
  const audioFolderInputRef = useRef<HTMLInputElement>(null);
  const detachedWindowRef = useRef<Window | null>(null);
  const detachedInspectorWindowRef = useRef<Window | null>(null);

  // Refs for detached inspector to access current values
  const projectRef = useRef(project);
  const selectedEventIdRef = useRef(selectedEventId);
  const selectedCommandIndexRef = useRef(selectedCommandIndex);
  const viewModeRef = useRef(viewMode);
  const audioFilesRef = useRef(audioFiles);
  const currentPlayingSoundRef = useRef(currentPlayingSound);
  const isPlayingRef = useRef(isPlaying);
  const playingEventsRef = useRef(playingEvents);

  const [isMixerDetached, setIsMixerDetached] = useState(false);
  const [isMixerPinned, setIsMixerPinned] = useState(false);
  const [mixerButtonActive, setMixerButtonActive] = useState(false);

  // Stop audio callback for event actions
  const stopAudioPlayback = useCallback(() => {
    if (audioRef.current) {
      audioRef.current.pause();
      audioRef.current.currentTime = 0;
      audioRef.current = null;
    }
    if (audioSourceRef.current) {
      try {
        audioSourceRef.current.stop();
      } catch {
        // Ignore if already stopped
      }
      audioSourceRef.current = null;
    }
    // NOTE: Don't close audioContext - it's now shared via useMemo and MasterInsertDSP
    setIsPlaying(false);
    setCurrentPlayingSound("");
  }, []);

  // Event CRUD actions
  const {
    handleAddEvent,
    handleRenameEvent,
    handleDeleteEvent,
    selectedEvent,
  } = useEventActions({
    project,
    selectedEventId,
    setProject,
    setSelectedEventId,
    setSelectedCommandIndex,
    saveToHistory,
    onStopAudio: stopAudioPlayback,
  });

  // Drag and drop for events and commands
  const {
    draggedCommandIndex,
    draggedEventId,
    handleCommandDragStart,
    handleDragOver,
    handleDrop,
    handleDragEnd,
    handleEventDragStart,
    handleEventDragOver,
    handleEventDrop,
    handleEventDragEnd,
  } = useDragDrop({
    project,
    selectedEventId,
    selectedCommandIndex,
    setProject,
    setSelectedCommandIndex,
    saveToHistory,
    volumeSliderOpen,
    panSliderOpen,
  });

  // Command CRUD actions
  const {
    handleAddCommand,
    handleDeleteCommand,
    handleDuplicateCommand,
    selectedCommand,
  } = useCommandActions({
    project,
    selectedEventId,
    selectedEvent,
    selectedCommandIndex,
    setProject,
    setSelectedCommandIndex,
    saveToHistory,
  });

  // Panel visibility state
  const [isDiagnosticsHUDVisible, setIsDiagnosticsHUDVisible] = useState(false);
  const [isShortcutsPanelVisible, setIsShortcutsPanelVisible] = useState(false);
  const [isHistoryPanelVisible, setIsHistoryPanelVisible] = useState(false);

  // Error toast system
  const errorToasts = useErrorToasts();

  // File browser state
  const [browserRoots] = useState<FileNode[]>([
    {
      id: 'project-sounds',
      name: 'Project Sounds',
      path: '/project/sounds',
      type: 'folder',
      isExpanded: true,
      children: audioFiles.map(f => ({
        id: String(f.id),
        name: f.name,
        path: String(f.id),
        type: 'audio' as const,
        duration: f.duration,
      })),
    },
  ]);

  // Shortcut manager for ShortcutsPanel
  const shortcutManager = useShortcutManager();

  // Register default shortcuts
  useEffect(() => {
    // Add default shortcuts with dummy actions (visual reference only)
    for (const shortcut of DEFAULT_SHORTCUTS) {
      shortcutManager.register({
        ...shortcut,
        action: () => {}, // Actions are handled in handleKeyDown
      });
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const audioEngineState: AudioEngineState = {
    audioContextRef,
    audioSourceRef,
    gainNodeRef,
    panNodeRef,
    audioRef,
    eventAudioRefsMap,
    soundAudioMap,
    busGainsRef,
    masterGainRef,
  };

  const audioEngine = useMemo(
    () => new AudioEngine(audioFiles, audioEngineState, setIsPlaying, setCurrentPlayingSound, setPlayingEvents),
    [audioFiles]
  );

  // RuntimeCore hook - manages RuntimeStub and Native RuntimeCore
  const {
    runtimeStubRef,
    audioBackendRef,
    latencyStats,
    perEventStats,
    setLatencyStats,
    setPerEventStats,
    nativeCoreRef,
    useNativeCore,
    setUseNativeCore,
    nativeCoreAvailable,
    nativeCoreError,
    setNativeCoreError,
    nativeLatencySplit,
    setNativeLatencySplit,
    latencyUpdateThrottleRef,
    handleToggleNativeCore,
    handleReloadCore,
    handleClearStats,
    handleDeterminismCheck,
    convertNativeCommands,
  } = useRuntimeCore({ audioEngine, audioFiles });

  // Playback controls
  const {
    handlePlaySound,
    handlePlayEvent,
    handleStopEvent,
    handleStopAllEvents,
  } = usePlaybackControls({
    audioEngine,
    project,
    selectedEvent,
    currentPlayingSound,
    isPlaying,
    engineClientRef,
    engineStatus,
  });

  // M7.1: Preview executor for unified command execution with preview sync
  const [lastCommandInfo, setLastCommandInfo] = useState<{ type: string; bus?: string; timestamp: number } | null>(null);

  // Convert NativeAdapterCommand to ExecutableCommand
  const nativeToExecutable = useCallback((cmd: NativeAdapterCommand): ExecutableCommand => {
    switch (cmd.type) {
      case 'Play':
        return { type: 'Play', assetId: cmd.assetId, bus: cmd.bus, gain: cmd.gain, loop: cmd.loop };
      case 'Stop':
        return { type: 'Stop', voiceId: cmd.voiceId };
      case 'StopAll':
        return { type: 'StopAll' };
      case 'SetBusGain':
        return { type: 'SetBusGain', bus: cmd.bus, gain: cmd.gain };
    }
  }, []);

  const previewExecutor = usePreviewExecutor({
    audioExecutor: audioBackendRef.current ? {
      execute: (cmd: ExecutableCommand) => {
        // Update last command for debug
        setLastCommandInfo({ type: cmd.type, bus: cmd.bus, timestamp: Date.now() });
        // Execute via audio backend - build type-specific command
        if (audioBackendRef.current) {
          let adapterCmd: AdapterCommand;
          switch (cmd.type) {
            case 'Play':
              adapterCmd = {
                type: 'Play',
                assetId: cmd.assetId || '',
                bus: (cmd.bus?.toUpperCase() || 'SFX') as BackendBusId,
                gain: cmd.gain ?? 1,
                loop: cmd.loop ?? false,
              };
              break;
            case 'Stop':
              adapterCmd = { type: 'Stop', voiceId: cmd.voiceId || '' };
              break;
            case 'StopAll':
              adapterCmd = { type: 'StopAll' };
              break;
            case 'SetBusGain':
              adapterCmd = {
                type: 'SetBusGain',
                bus: (cmd.bus?.toUpperCase() || 'SFX') as BackendBusId,
                gain: cmd.gain ?? 1,
              };
              break;
            case 'Fade':
              // Fade maps to SetBusGain with target volume
              adapterCmd = {
                type: 'SetBusGain',
                bus: (cmd.bus?.toUpperCase() || 'SFX') as BackendBusId,
                gain: cmd.targetVolume ?? 1,
              };
              break;
            case 'Pause':
              // Pause maps to StopAll for overall, or Stop for specific
              adapterCmd = cmd.overall
                ? { type: 'StopAll' }
                : { type: 'Stop', voiceId: cmd.voiceId || '' };
              break;
            default:
              // Fallback - should never happen
              adapterCmd = { type: 'StopAll' };
          }
          audioBackendRef.current.execute([adapterCmd]);
        }
      }
    } : null,
    logCommands: false,
  });

  // M7.1: Local flood handler using preview executor
  const handleLocalFlood = useCallback((count: number, eventName: string) => {
    if (!nativeCoreRef.current) {
      console.warn('[LocalFlood] No native core available');
      return;
    }

    const core = nativeCoreRef.current;
    for (let i = 0; i < count; i++) {
      const commands = core.submitEvent({ name: eventName });
      if (commands) {
        const execCmds = commands.map(nativeToExecutable);
        previewExecutor.executeCommands(execCmds);
      }
    }
    console.log(`[LocalFlood] Sent ${count} ${eventName} events`);
  }, [previewExecutor, nativeToExecutable]);

  // NOTE: RuntimeStub/NativeCore initialization moved to useRuntimeCore hook

  const handleResetOnModifierClick = (e: React.MouseEvent, callback: () => void) => {
    if (e.altKey || e.ctrlKey || e.metaKey) {
      e.preventDefault();
      e.stopPropagation();
      callback();
    }
  };

  // Update refs whenever values change
  useEffect(() => {
    projectRef.current = project;
    selectedEventIdRef.current = selectedEventId;
    selectedCommandIndexRef.current = selectedCommandIndex;
    viewModeRef.current = viewMode;
    audioFilesRef.current = audioFiles;
    currentPlayingSoundRef.current = currentPlayingSound;
    isPlayingRef.current = isPlaying;
    playingEventsRef.current = playingEvents;
  }, [project, selectedEventId, selectedCommandIndex, viewMode, audioFiles, currentPlayingSound, isPlaying, playingEvents]);

  useEffect(() => {
    audioEngine.updateAudioFiles(audioFiles);
  }, [audioFiles, audioEngine]);

  useEffect(() => {
    setMixerProject(project);
  }, [project, setMixerProject]);

  useEffect(() => {
    setDraftVolume(null);
    setDraftPan(null);
  }, [selectedCommandIndex]);

  // Load waveform when sound is selected
  useEffect(() => {
    if (!selectedSoundId) {
      setWaveformData(null);
      return;
    }

    const audioFile = audioFiles.find(af => af.name === selectedSoundId);
    if (!audioFile?.url) {
      setWaveformData(null);
      return;
    }

    let cancelled = false;
    setIsLoadingWaveform(true);

    // Decode audio from URL and generate waveform using shared context
    (async () => {
      try {
        const response = await fetch(audioFile.url);
        const arrayBuffer = await response.arrayBuffer();
        // Use shared AudioContext - don't close it!
        const sharedCtx = AudioContextManager.getContext();
        const audioBuffer = await sharedCtx.decodeAudioData(arrayBuffer);

        if (!cancelled) {
          const peaks = generateWaveformPeaks(audioBuffer, 500);
          setWaveformData(peaks);
        }
        // Note: shared context is managed by AudioContextManager, don't close
      } catch {
        if (!cancelled) {
          setWaveformData(null);
        }
      } finally {
        if (!cancelled) {
          setIsLoadingWaveform(false);
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [selectedSoundId, audioFiles]);

  useEffect(() => {
    const handleEngineMessage = (msg: IncomingMessage) => {
      if (msg.type === 'GameEventFired') {
        const recvTime = performance.now();

        if (!project) {
          return;
        }

        const event = project.events.find(e => e.eventName === msg.eventName);
        if (!event) {
          return;
        }

        setSelectedEventId(event.id);
        setViewMode('events');

        // Route through Native RuntimeCore if enabled, otherwise use JS RuntimeStub
        const nativeCore = nativeCoreRef.current;
        const backend = audioBackendRef.current;

        if (nativeCore?.isEnabled() && backend) {
          // === NATIVE CORE PATH (uses same backend.execute() as stub) ===
          try {
            const nativeCommands = nativeCore.submitEvent({
              name: msg.eventName,
              seq: msg.seq,
              engineTimeMs: msg.engineTimeMs
            });

            const coreTime = performance.now();
            const coreMs = coreTime - recvTime;

            if (nativeCommands && nativeCommands.length > 0) {
              // Convert native commands to backend format and execute through same path as stub
              const adapterCommands = convertNativeCommands(nativeCommands);
              backend.execute(adapterCommands);

              const execTime = performance.now();
              const execMs = execTime - coreTime;
              const totalMs = execTime - recvTime;

              // Update split latency metrics (throttled to ~15Hz)
              const throttle = latencyUpdateThrottleRef.current;
              if (execTime - throttle.lastUpdate >= LATENCY_UPDATE_INTERVAL_MS) {
                throttle.lastUpdate = execTime;
                setNativeLatencySplit(prev => ({
                  coreMs: prev ? (prev.coreMs * prev.count + coreMs) / (prev.count + 1) : coreMs,
                  execMs: prev ? (prev.execMs * prev.count + execMs) / (prev.count + 1) : execMs,
                  totalMs: prev ? (prev.totalMs * prev.count + totalMs) / (prev.count + 1) : totalMs,
                  count: (prev?.count ?? 0) + 1
                }));
              }

              console.log(`[NativeCore] ${msg.eventName} → ${nativeCommands.length} cmds | core=${coreMs.toFixed(2)}ms exec=${execMs.toFixed(2)}ms total=${totalMs.toFixed(2)}ms`);
            }
          } catch (err) {
            // === HARD-FAIL POLICY: auto-disable native mode on error ===
            const errorMsg = err instanceof Error ? err.message : String(err);
            console.error(`[NativeCore] NATIVE_CORE_DISABLED: ${errorMsg}`);
            setNativeCoreError(errorMsg);
            setUseNativeCore(false);
            nativeCore.disable();

            // Fall through to stub path for this event
            if (runtimeStubRef.current) {
              runtimeStubRef.current.triggerEventByName(msg.eventName, recvTime, msg.seq);
            }
            return;
          }
        } else if (runtimeStubRef.current) {
          // === JS RUNTIMESTUB PATH ===
          const stub = runtimeStubRef.current;
          const result = stub.triggerEventByName(msg.eventName, recvTime, msg.seq);

          // If result is null, event was deduped (duplicate seq)
          if (result === null) {
            console.log(`[RuntimeStub] Duplicate ignored: ${msg.eventName} (seq=${msg.seq})`);
            return; // Don't update stats or play audio for duplicates
          }

          // Throttled UI update for latency stats (~15Hz to avoid thrashing during stress tests)
          const throttle = latencyUpdateThrottleRef.current;
          const now = performance.now();

          if (now - throttle.lastUpdate >= LATENCY_UPDATE_INTERVAL_MS) {
            // Immediate update if enough time has passed
            throttle.lastUpdate = now;
            const overall = stub.getOverallStats();
            setLatencyStats(overall);

            const eventStats: Record<string, LatencyStats> = {};
            const uniqueEvents = new Set(overall.measurements.map(m => m.event));
            for (const eventName of uniqueEvents) {
              eventStats[eventName] = stub.getEventStats(eventName);
            }
            setPerEventStats(eventStats);
          } else if (!throttle.pending) {
            // Schedule a deferred update
            throttle.pending = true;
            throttle.rafId = requestAnimationFrame(() => {
              throttle.pending = false;
              throttle.lastUpdate = performance.now();

              const currentStub = runtimeStubRef.current;
              if (currentStub) {
                const overall = currentStub.getOverallStats();
                setLatencyStats(overall);

                const eventStats: Record<string, LatencyStats> = {};
                const uniqueEvents = new Set(overall.measurements.map(m => m.event));
                for (const eventName of uniqueEvents) {
                  eventStats[eventName] = currentStub.getEventStats(eventName);
                }
                setPerEventStats(eventStats);
              }
            });
          }

          // Also play via existing AudioEngine for visual/UI feedback
          setTimeout(() => {
            audioEngine.playEvent(event, project);
          }, 100);
        }
      }
    };

    if (!engineClientRef.current) {
      engineClientRef.current = new EngineClient(
        handleEngineMessage,
        setEngineStatus,
        (entry) => setEngineLogs((prev) => [...prev.slice(-199), entry])
      );
    }

    return () => {
      // Don't disconnect on unmount, keep connection alive
    };
  }, [project, audioEngine, convertNativeCommands]);

  useEffect(() => {
    const loadData = async () => {
      const savedProject = localStorage.getItem('reelforge-project');
      const savedSelectedEventId = localStorage.getItem('reelforge-selected-event');

      if (savedProject) {
        try {
          const parsedProject = JSON.parse(savedProject);
          const projectWithBuses = ensureProjectBuses(parsedProject);
          setProject(projectWithBuses);
          saveToHistory(projectWithBuses);
          localStorage.setItem('reelforge-project', JSON.stringify(projectWithBuses));
        } catch (err) {
          console.error("Failed to load saved project:", err);
        }
      }

      try {
        const loadedAudioFiles = await loadAudioFilesFromDB();
        if (loadedAudioFiles.length > 0) {
          setAudioFiles(loadedAudioFiles);
        }
      } catch (err) {
        console.error("Failed to load audio files from IndexedDB:", err);
      }

      if (savedSelectedEventId) {
        setSelectedEventId(savedSelectedEventId);
      }

      setIsLoading(false);
    };

    loadData();
  }, []);

  useEffect(() => {
    if (project) {
      localStorage.setItem('reelforge-project', JSON.stringify(project));

      // Initialize bus volumes from project (only valid buses)
      const validBusIds: BusId[] = ['master', 'music', 'sfx', 'ambience', 'voice'];
      project.buses.forEach(bus => {
        if (validBusIds.includes(bus.id)) {
          const effectiveVolume = bus.muted ? 0 : bus.volume;
          audioEngine.setBusVolume(bus.id, effectiveVolume);
        }
      });
    }
  }, [project, audioEngine]);

  useEffect(() => {
    if (audioFiles.length > 0) {
      const saveFiles = async () => {
        try {
          for (const audioFile of audioFiles) {
            await saveAudioFileToDB(audioFile);
          }
        } catch (err) {
          console.error("Failed to save audio files to IndexedDB:", err);
        }
      };
      saveFiles();
    }
  }, [audioFiles]);

  useEffect(() => {
    if (selectedEventId) {
      localStorage.setItem('reelforge-selected-event', selectedEventId);
    }
  }, [selectedEventId]);

  useEffect(() => {
    localStorage.setItem('reelforge-view-mode', viewMode);
  }, [viewMode]);

  const handleUndo = () => {
    const previousProject = undo();
    if (previousProject) {
      setProject(previousProject);
    }
  };

  const handleRedo = () => {
    const nextProject = redo();
    if (nextProject) {
      setProject(nextProject);
    }
  };

  const handleExportTemplate = () => {
    if (!project) return;

    const issues = validateProject(project, audioFiles);
    const errors = issues.filter(i => i.type === 'error');
    const warnings = issues.filter(i => i.type === 'warning');

    if (errors.length > 0) {
      setValidationDialog({ errors, warnings, allowExport: false });
      return;
    }

    if (warnings.length > 0) {
      setValidationDialog({ errors, warnings, allowExport: true });
      return;
    }

    // No issues - export directly
    exportTemplateJson(project);
  };

  const handleBusChange = (busId: BusId, volume: number, muted?: boolean) => {
    if (!project) return;

    const updated = {
      ...project,
      buses: project.buses.map(b =>
        b.id === busId ? { ...b, volume, muted } : b
      )
    };
    setProject(updated);
    saveToHistory(updated);

    const effectiveVolume = muted ? 0 : volume;
    audioEngine.setBusVolume(busId, effectiveVolume);
  };

  const exportTemplateJson = (proj: ReelForgeProject) => {
    const templateJson = projectToTemplateJson(proj);
    const blob = new Blob([JSON.stringify(templateJson, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${proj.name}_Template.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleImportTemplate = () => {
    fileInputRef.current?.click();
  };

  const handleTemplateFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (evt) => {
      try {
        const raw = JSON.parse(evt.target?.result as string) as TemplateJSON;
        const proj = templateJsonToProject(raw);
        setProject(proj);
        resetHistory();
        saveToHistory(proj);
        if (proj.events.length > 0) {
          setSelectedEventId(proj.events[0].id);
        }
      } catch (err) {
        alert("Failed to import template: " + (err as Error).message);
      }
    };
    reader.readAsText(file);
  };

  const handleJsonDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(true);
  };

  const handleJsonDragLeave = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(false);
  };

  const handleJsonDrop = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(false);

    const file = e.dataTransfer.files?.[0];
    if (!file) return;

    if (!file.name.endsWith('.json')) {
      alert('Please drop a JSON file');
      return;
    }

    const reader = new FileReader();
    reader.onload = (evt) => {
      try {
        const raw = JSON.parse(evt.target?.result as string) as TemplateJSON;
        const proj = templateJsonToProject(raw);
        setProject(proj);
        resetHistory();
        saveToHistory(proj);
        if (proj.events.length > 0) {
          setSelectedEventId(proj.events[0].id);
        }
      } catch (err) {
        alert("Failed to import JSON: " + (err as Error).message);
      }
    };
    reader.readAsText(file);
  };

  const handleImportAudioFiles = () => {
    audioFilesInputRef.current?.click();
  };

  const handleAudioFilesChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;

    const audioFileObjects = Array.from(files)
      .filter(file => file.type.startsWith('audio/') || file.name.match(/\.(mp3|wav|ogg|m4a|aac)$/i))
      .map((file, index) => ({
        id: Date.now() + index,
        name: file.name,
        file: file,
        url: URL.createObjectURL(file),
        duration: 0,
        size: (file.size / 1024 / 1024).toFixed(2) + ' MB'
      }));

    setAudioFiles(prev => [...prev, ...audioFileObjects]);

    audioFileObjects.forEach(audioFile => {
      const audio = new Audio(audioFile.url);
      audio.addEventListener('loadedmetadata', () => {
        setAudioFiles(prev => prev.map(f =>
          f.id === audioFile.id ? { ...f, duration: audio.duration } : f
        ));
      });
    });
  };

  // Analyze sounds from JSON and import matching WAV files
  const handleAnalyzeAndImportSounds = () => {
    audioFolderInputRef.current?.click();
  };

  const handleAudioFolderChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (!files || files.length === 0 || !project) return;

    // Get all sound IDs from spriteItems (these have s_ prefix like s_BankRollEndAnim)
    const soundIdsFromJson = project.spriteItems.map(item => item.id);

    // Create a map of sound names without s_ prefix to their full IDs
    const soundNameMap = new Map<string, string>();
    soundIdsFromJson.forEach(id => {
      // Remove s_ prefix if present
      const nameWithoutPrefix = id.startsWith('s_') ? id.substring(2) : id;
      soundNameMap.set(nameWithoutPrefix.toLowerCase(), id);
    });

    // Filter audio files and match them to sound IDs
    const matchedFiles: Array<{
      file: File;
      soundId: string;
      fileName: string;
    }> = [];

    const unmatchedFiles: string[] = [];

    Array.from(files)
      .filter(file => file.type.startsWith('audio/') || file.name.match(/\.(mp3|wav|ogg|m4a|aac)$/i))
      .forEach(file => {
        // Get filename without extension
        const fileNameWithoutExt = file.name.replace(/\.[^/.]+$/, '').toLowerCase();

        // Try to find matching sound ID
        const matchedSoundId = soundNameMap.get(fileNameWithoutExt);

        if (matchedSoundId) {
          matchedFiles.push({
            file,
            soundId: matchedSoundId,
            fileName: file.name
          });
        } else {
          unmatchedFiles.push(file.name);
        }
      });

    if (matchedFiles.length === 0) {
      alert(`No matching sounds found.\n\nExpected filenames like: ${Array.from(soundNameMap.keys()).slice(0, 5).join('.wav, ')}.wav\n\nFound files: ${Array.from(files).slice(0, 5).map(f => f.name).join(', ')}`);
      return;
    }

    // Import matched files as audio files
    const audioFileObjects = matchedFiles.map((matched, index) => ({
      id: Date.now() + index,
      name: matched.fileName,
      file: matched.file,
      url: URL.createObjectURL(matched.file),
      duration: 0,
      size: (matched.file.size / 1024 / 1024).toFixed(2) + ' MB',
      soundId: matched.soundId // Store the matched sound ID
    }));

    setAudioFiles(prev => [...prev, ...audioFileObjects]);

    // Load durations
    audioFileObjects.forEach(audioFile => {
      const audio = new Audio(audioFile.url);
      audio.addEventListener('loadedmetadata', () => {
        setAudioFiles(prev => prev.map(f =>
          f.id === audioFile.id ? { ...f, duration: audio.duration } : f
        ));
      });
    });

    // Create a mapping from JSON sound IDs (s_xxx) to WAV filenames
    // Map both the matched soundId AND the s_ prefixed version of the filename
    const jsonIdToWavName = new Map<string, string>();
    matchedFiles.forEach(matched => {
      // matched.soundId is already the s_ prefixed ID from spriteItems
      jsonIdToWavName.set(matched.soundId, matched.fileName);
    });

    // Also create mapping directly from WAV filenames to handle commands
    // that reference sounds by s_ + filename pattern
    audioFileObjects.forEach(af => {
      const fileNameWithoutExt = af.name.replace(/\.[^/.]+$/, '');
      const sPrefixedId = 's_' + fileNameWithoutExt;
      if (!jsonIdToWavName.has(sPrefixedId)) {
        jsonIdToWavName.set(sPrefixedId, af.name);
      }
    });

    // Update spriteItems with the imported audio URLs
    const updatedSpriteItems = project.spriteItems.map(item => {
      const matchedAudio = audioFileObjects.find(af => af.soundId === item.id);
      if (matchedAudio) {
        return {
          ...item,
          soundId: matchedAudio.url, // Update soundId to the blob URL for playback
          originalSoundId: item.soundId, // Keep original for reference
          wavFileName: matchedAudio.name // Store WAV filename for display
        };
      }
      return item;
    });

    // Update commands in events to use WAV filenames instead of s_ prefixed IDs
    const updatedEvents = project.events.map(event => ({
      ...event,
      commands: event.commands.map(cmd => {
        if (cmd.type === 'Play' || cmd.type === 'Stop' || cmd.type === 'Fade' || cmd.type === 'Pause') {
          const playCmd = cmd as PlayCommand;
          const wavFileName = jsonIdToWavName.get(playCmd.soundId);
          if (wavFileName) {
            return {
              ...cmd,
              soundId: wavFileName
            };
          }
        }
        return cmd;
      })
    }));

    const updatedProject = {
      ...project,
      spriteItems: updatedSpriteItems as any,
      events: updatedEvents
    };

    setProject(updatedProject);
    saveToHistory(updatedProject);

    // Show summary
    const summary = `Imported ${matchedFiles.length} sounds.\n\n` +
      (unmatchedFiles.length > 0 ? `Unmatched files (${unmatchedFiles.length}):\n${unmatchedFiles.slice(0, 10).join('\n')}${unmatchedFiles.length > 10 ? '\n...' : ''}` : 'All files matched!');

    alert(summary);

    // Reset input
    e.target.value = '';
  };

  // NOTE: handleRenameEvent, handleDeleteEvent, handleAddEvent moved to useEventActions hook
  // NOTE: selectedCommand moved to useCommandActions hook

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement;
      const isInput = target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.tagName === 'SELECT';

      // Ctrl+D: Toggle Diagnostics HUD
      if ((e.ctrlKey || e.metaKey) && e.key === 'd') {
        e.preventDefault();
        setIsDiagnosticsHUDVisible(prev => !prev);
        return;
      }

      // Ctrl+/ or ?: Toggle Shortcuts Panel
      if (e.key === '?' || ((e.ctrlKey || e.metaKey) && e.key === '/')) {
        e.preventDefault();
        setIsShortcutsPanelVisible(prev => !prev);
        return;
      }

      // Ctrl+H: Toggle History Panel
      if ((e.ctrlKey || e.metaKey) && e.key === 'h') {
        e.preventDefault();
        setIsHistoryPanelVisible(prev => !prev);
        return;
      }

      // Ctrl+Z: Undo
      if ((e.ctrlKey || e.metaKey) && e.key === 'z' && !e.shiftKey) {
        e.preventDefault();
        handleUndo();
        return;
      }

      // Ctrl+Shift+Z or Ctrl+Y: Redo
      if ((e.ctrlKey || e.metaKey) && (e.key === 'y' || (e.key === 'z' && e.shiftKey))) {
        e.preventDefault();
        handleRedo();
        return;
      }

      // Space: Play/Stop (only when not in input)
      if (e.code === 'Space' && !e.repeat && !isInput) {
        e.preventDefault();
        if (selectedEvent && project) {
          if (playingEvents.has(selectedEvent.id)) {
            handleStopAllEvents();
          } else {
            handlePlayEvent();
          }
        }
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [playingEvents, selectedEvent, project, handleUndo, handleRedo]);

  // NOTE: handleAddCommand, handleDeleteCommand, handleDuplicateCommand moved to useCommandActions hook

  // NOTE: handleDragStart, handleDragOver, handleDrop, handleDragEnd,
  // handleEventDragStart, handleEventDragOver, handleEventDrop, handleEventDragEnd
  // moved to useDragDrop hook

  const handleUpdateCommand = (commandIndex: number, updates: Partial<Command>) => {
    if (!project || !selectedEventId) return;

    const selectedEvent = project.events.find((evt) => evt.id === selectedEventId);
    if (!selectedEvent) return;

    const currentCommand = selectedEvent.commands[commandIndex];
    const commandKey = `${selectedEventId}-${commandIndex}`;

    const updatedProject = {
      ...project,
      events: project.events.map((evt) =>
        evt.id === selectedEventId
          ? {
              ...evt,
              commands: evt.commands.map((c, idx) => {
                if (idx !== commandIndex) return c;

                if (updates.type && updates.type !== c.type) {
                  const currentSettings = commandTypeSettings.get(commandKey) || {} as Record<CommandType, Partial<Command>>;

                  // Save current type settings before switching
                  currentSettings[c.type] = { ...c };

                  const existingSoundId = 'soundId' in c ? c.soundId : "";

                  let newCommand: Command;

                  // Check if we have saved settings for the new type
                  if (currentSettings[updates.type]) {
                    newCommand = { ...currentSettings[updates.type], type: updates.type } as Command;
                    if (!('soundId' in newCommand) || !(newCommand as PlayCommand | StopCommand | FadeCommand | PauseCommand).soundId) {
                      (newCommand as PlayCommand | StopCommand | FadeCommand | PauseCommand).soundId = existingSoundId;
                    }
                  } else {
                    // Create new command with defaults
                    const existingVolume = (c as PlayCommand).volume ?? 1;
                    const existingLoop = (c as PlayCommand).loop ?? false;
                    const existingDelay = 'delay' in c ? c.delay : undefined;
                    const existingFadeIn = (c as PlayCommand).fadeIn;
                    const existingFadeOut = (c as StopCommand).fadeOut;
                    const existingDuration = (c as FadeCommand).duration;
                    const existingTargetVolume = (c as FadeCommand).targetVolume;

                    if (updates.type === "Play") {
                      newCommand = {
                        type: "Play",
                        soundId: existingSoundId,
                        volume: existingVolume,
                        loop: existingLoop,
                        delay: existingDelay,
                        fadeIn: existingFadeIn,
                      } as PlayCommand;
                    } else if (updates.type === "Stop") {
                      newCommand = {
                        type: "Stop",
                        soundId: existingSoundId,
                        delay: existingDelay,
                        fadeOut: existingFadeOut,
                      } as StopCommand;
                    } else if (updates.type === "Fade") {
                      newCommand = {
                        type: "Fade",
                        soundId: existingSoundId,
                        targetVolume: existingTargetVolume ?? 0,
                        duration: existingDuration ?? 0,
                        delay: existingDelay,
                      } as FadeCommand;
                    } else if (updates.type === "Pause") {
                      newCommand = {
                        type: "Pause",
                        soundId: existingSoundId,
                        delay: existingDelay,
                      } as PauseCommand;
                    } else {
                      newCommand = {
                        type: "Execute",
                        eventId: "",
                      } as ExecuteCommand;
                    }
                  }

                  // Update settings map with saved current type
                  setCommandTypeSettings(new Map(commandTypeSettings.set(commandKey, currentSettings)));

                  return newCommand;
                }

                const updatedCommand = { ...c, ...updates } as Command;

                // Save updated settings for current type
                const currentSettings = commandTypeSettings.get(commandKey) || {} as Record<CommandType, Partial<Command>>;
                currentSettings[c.type] = { ...updatedCommand };
                setCommandTypeSettings(new Map(commandTypeSettings.set(commandKey, currentSettings)));

                if (currentCommand.type === "Play" && 'volume' in updates && updates.volume !== undefined) {
                  const playCmd = currentCommand as PlayCommand;
                  const soundId = playCmd.soundId;

                  if (soundId && soundAudioMap.current.has(soundId)) {
                    const audioObjects = soundAudioMap.current.get(soundId) || [];
                    audioObjects.forEach(({ audio, gainNode }) => {
                      if (gainNode) {
                        gainNode.gain.value = (updates as Partial<PlayCommand>).volume as number;
                      } else {
                        audio.volume = (updates as Partial<PlayCommand>).volume as number;
                      }
                    });
                  }
                }

                if (currentCommand.type === "Fade" && 'targetVolume' in updates && updates.targetVolume !== undefined) {
                  const fadeCmd = currentCommand as FadeCommand;
                  const soundId = fadeCmd.soundId;

                  if (soundId && soundAudioMap.current.has(soundId)) {
                    const audioObjects = soundAudioMap.current.get(soundId) || [];
                    audioObjects.forEach(({ audio, gainNode }) => {
                      if (gainNode) {
                        gainNode.gain.value = (updates as Partial<FadeCommand>).targetVolume as number;
                      } else {
                        audio.volume = (updates as Partial<FadeCommand>).targetVolume as number;
                      }
                    });
                  }
                }

                return updatedCommand;
              }),
            }
          : evt
      ),
    };
    setProject(updatedProject);
    saveToHistory(updatedProject);

    // DO NOT send data back to detached inspector - it causes slider resets
    // Detached inspector uses local cachedData that is updated immediately
  };

  // NOTE: handlePlaySound, handlePlayEvent, handleStopEvent, handleStopAllEvents
  // moved to usePlaybackControls hook

  const handleDetachInspector = () => {
    if (isInspectorDetached) {
      // Re-attach inspector
      setIsInspectorDetached(false);
      setIsInspectorOpen(true);
      return;
    }

    // Detach inspector
    setInspectorAnimationClass('inspector-detaching');
    setTimeout(() => {
      setIsInspectorDetached(true);
      setIsInspectorOpen(false);
      setInspectorAnimationClass('');
    }, 350);
  };

  // Inspector drag handler - wraps hook's startDrag with input/button check
  const handleInspectorMouseDown = (e: React.MouseEvent) => {
    const tag = (e.target as HTMLElement).tagName;
    if (tag === 'INPUT' || tag === 'SELECT' || tag === 'BUTTON') {
      return;
    }
    startInspectorDrag(e);
  };

  // Inspector resize handler - uses hook's startResize directly
  const handleResizeMouseDown = startInspectorResize;

  // Sound Inspector drag handler - wraps hook's startDrag with input/button check
  const handleSoundInspectorMouseDown = (e: React.MouseEvent) => {
    const tag = (e.target as HTMLElement).tagName;
    if (tag === 'INPUT' || tag === 'SELECT' || tag === 'BUTTON') {
      return;
    }
    startSoundInspectorDrag(e);
  };

  // Sound Inspector resize handler - uses hook's startResize directly
  const handleSoundInspectorResizeMouseDown = startSoundInspectorResize;

  // NOTE: Drag/resize useEffects moved to useDetachablePanel hook

  useEffect(() => {
    const handleMessage = (event: MessageEvent) => {
      console.log('[Main Window] Received message:', event.data);

      // Handle inspector closed
      if (event.data.type === 'inspector-closed') {
        setIsInspectorDetached(false);
        detachedInspectorWindowRef.current = null;
        return;
      }

      // Handle request for inspector data
      if (event.data.type === 'request-inspector-data') {
        console.log('[Main Window] Request received, checking refs...');
        console.log('[Main Window] detachedInspectorWindowRef:', detachedInspectorWindowRef.current);
        console.log('[Main Window] projectRef:', projectRef.current);
        console.log('[Main Window] selectedEventIdRef:', selectedEventIdRef.current);
        console.log('[Main Window] selectedCommandIndexRef:', selectedCommandIndexRef.current);

        if (!detachedInspectorWindowRef.current || detachedInspectorWindowRef.current.closed) {
          console.log('[Main Window] Detached window not available');
          return;
        }

        const currentProject = projectRef.current;
        const currentSelectedEventId = selectedEventIdRef.current;
        const currentSelectedCommandIndex = selectedCommandIndexRef.current;

        const currentSelectedEvent = currentProject?.events.find((e) => e.id === currentSelectedEventId);
        const currentSelectedCommand = currentSelectedEvent && currentSelectedCommandIndex !== null
          ? currentSelectedEvent.commands[currentSelectedCommandIndex]
          : null;

        const data = {
          selectedCommand: currentSelectedCommand,
          selectedCommandIndex: currentSelectedCommandIndex,
          selectedEvent: currentSelectedEvent,
          viewMode: viewModeRef.current,
          project: currentProject,
          audioFiles: audioFilesRef.current,
          currentPlayingSound: currentPlayingSoundRef.current,
          isPlaying: isPlayingRef.current,
          playingEvents: playingEventsRef.current
        };

        console.log('[Main Window] Sending inspector data via postMessage:', data);
        detachedInspectorWindowRef.current.postMessage({
          type: 'inspector-data',
          payload: data
        }, '*');
        return;
      }

      // Handle command update request
      if (event.data.type === 'inspector-update-command') {
        const { index, updates } = event.data.payload;
        console.log('[Main Window] Received update command request:', { index, updates });
        handleUpdateCommand(index, updates);
        return;
      }

      // Handle play sound request
      if (event.data.type === 'inspector-play-sound') {
        const { soundId, volume, loop } = event.data.payload;
        console.log('[Main Window] Received play sound request:', { soundId, volume, loop });
        handlePlaySound(soundId, volume, loop);
        return;
      }

      // Handle stop all audio request
      if (event.data.type === 'inspector-stop-all') {
        console.log('[Main Window] Received stop all request');
        handleStopAllEvents();
        return;
      }
    };

    window.addEventListener('message', handleMessage);
    return () => window.removeEventListener('message', handleMessage);
  }, []);

  // Calculate sound usages - based on audioFiles (WAV files)
  const soundUsages = useMemo((): SoundUsage[] => {
    if (!project) return [];

    const soundMap = new Map<string, SoundUsage>();

    // Create entries for each audio file
    audioFiles.forEach(audioFile => {
      soundMap.set(audioFile.name, {
        soundId: audioFile.name,
        spriteIds: [],
        eventNames: [],
        hasFile: true,
      });
    });

    // Collect which events use each sound
    project.events.forEach(event => {
      event.commands.forEach(cmd => {
        if (cmd.type === "Play" || cmd.type === "Stop" || cmd.type === "Fade" || cmd.type === "Pause") {
          const playCmd = cmd as PlayCommand;
          const cmdSoundId = playCmd.soundId;

          if (!cmdSoundId) return;

          // If this sound exists in our audioFiles, update its event list
          if (soundMap.has(cmdSoundId)) {
            const usage = soundMap.get(cmdSoundId)!;
            if (!usage.eventNames.includes(event.eventName)) {
              usage.eventNames.push(event.eventName);
            }
          }
        }
      });
    });

    return Array.from(soundMap.values());
  }, [project, audioFiles]);

  const filteredSounds = soundUsages.filter(sound =>
    sound.soundId.toLowerCase().includes(deferredSoundSearchQuery.toLowerCase())
  );

  const filteredEvents = project?.events.filter((e) => {
    const matchesSearch = e.eventName.toLowerCase().includes(deferredSearchQuery.toLowerCase());

    if (eventTab === "all") {
      return matchesSearch;
    } else {
      const hasImportedAudioFiles = e.commands.some(cmd => {
        if (cmd.type === "Play") {
          const playCmd = cmd as PlayCommand;
          return playCmd.soundId && audioFiles.some(af => af.name === playCmd.soundId);
        }
        return false;
      });
      return matchesSearch && hasImportedAudioFiles;
    }
  }) || [];

  if (isLoading) {
    return (
      <div className="events-page">
        <div className="empty-state" style={{ opacity: 0 }}>
        </div>
      </div>
    );
  }

  if (!project) {
    return (
      <div className="events-page">
        <div
          className="empty-state"
          onDragOver={handleJsonDragOver}
          onDragLeave={handleJsonDragLeave}
          onDrop={handleJsonDrop}
          style={{
            border: isDragOver ? '2px dashed #4CAF50' : '2px dashed transparent',
            backgroundColor: isDragOver ? 'rgba(76, 175, 80, 0.1)' : 'transparent',
            transition: 'all 0.2s ease'
          }}
        >
          <h2>No Project Loaded</h2>
          <p>{isDragOver ? '📥 Drop JSON file here' : 'Import your JSON template to get started or use Open Project above'}</p>
          <div style={{ display: 'flex', gap: '12px', justifyContent: 'center', flexWrap: 'wrap' }}>
            <button className="btn-primary" onClick={handleImportTemplate} title="Legacy template format (not project save)">
              📄 Import JSON Template
            </button>
          </div>
          <input
            ref={fileInputRef}
            type="file"
            accept=".json"
            style={{ display: "none" }}
            onChange={handleTemplateFileChange}
          />
        </div>
      </div>
    );
  }

  return (
    <MasterInsertProvider
      audioContext={audioContext}
      masterGain={masterGain}
      initialChain={projectFile?.studio?.masterInsertChain}
    >
    <BusInsertProvider
      audioContextRef={audioContextRef}
      busGainsRef={busGainsRef as React.MutableRefObject<Record<import('./core/types').BusId, GainNode> | null>}
      masterGainRef={masterGainRef}
      initialChains={projectFile?.studio?.busInsertChains}
      initialBusPdcEnabled={projectFile?.studio?.busPdcEnabled}
    >
    <AssetInsertProvider
      audioContextRef={audioContextRef}
      initialChains={projectFile?.studio?.assetInsertChains}
    >
    <div className="events-page">
      {/* Error Toast Container */}
      <ErrorToastContainer
        toasts={errorToasts.toasts}
        onDismiss={errorToasts.dismissToast}
      />

      {/* Diagnostics HUD */}
      <DiagnosticsHUD
        visible={isDiagnosticsHUDVisible}
        onToggle={() => setIsDiagnosticsHUDVisible(prev => !prev)}
        exportContext={{
          projectName: projectFile?.name ?? null,
          viewMode,
          audioContext: audioContextRef.current,
        }}
      />

      {/* Shortcuts Panel Overlay */}
      {isShortcutsPanelVisible && (
        <div
          style={{
            position: 'fixed',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundColor: 'rgba(0,0,0,0.7)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 9999,
          }}
          onClick={() => setIsShortcutsPanelVisible(false)}
        >
          <div onClick={(e) => e.stopPropagation()}>
            <ShortcutsPanel
              manager={shortcutManager}
              onClose={() => setIsShortcutsPanelVisible(false)}
            />
          </div>
        </div>
      )}

      {/* History Panel Sidebar */}
      {isHistoryPanelVisible && (
        <div
          style={{
            position: 'fixed',
            top: 60,
            right: 0,
            width: 280,
            height: 'calc(100vh - 60px)',
            backgroundColor: '#1a1a1a',
            borderLeft: '1px solid #333',
            zIndex: 100,
            display: 'flex',
            flexDirection: 'column',
          }}
        >
          <HistoryPanel
            past={[]}
            future={[]}
            currentIndex={-1}
            canUndo={canUndo}
            canRedo={canRedo}
            onUndo={handleUndo}
            onRedo={handleRedo}
            onJumpTo={() => {}}
            onClose={() => setIsHistoryPanelVisible(false)}
          />
        </div>
      )}

      {/* M7.0: Project Header */}
      <ProjectHeader />
      <div className="main-layout">
        {/* Events Panel - hidden for fullscreen views like timeline */}
        {viewMode !== 'timeline' && (<>
        <div className="events-panel">
          <div className="panel-header" style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '8px 12px' }}>
            {/* View Mode Tabs */}
            <div style={{
              display: 'flex',
              gap: '4px',
              flex: 1,
              minWidth: 0
            }}>
              <button
                onClick={() => {
                  setViewMode("events");
                  setSelectedSoundId(null);
                }}
                style={{
                  flex: 1,
                  padding: '6px 8px',
                  backgroundColor: 'transparent',
                  color: viewMode === "events" ? '#fff' : '#666',
                  border: 'none',
                  borderBottom: viewMode === "events" ? '2px solid #fff' : '2px solid transparent',
                  borderRadius: 0,
                  cursor: 'pointer',
                  fontSize: '11px',
                  fontWeight: 600,
                  transition: 'all 0.2s',
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis'
                }}
              >
                EVENTS
              </button>
              <button
                onClick={() => {
                  setViewMode("sounds");
                  setSelectedEventId(null);
                  setSelectedCommandIndex(null);
                }}
                style={{
                  flex: 1,
                  padding: '6px 8px',
                  backgroundColor: 'transparent',
                  color: viewMode === "sounds" ? '#fff' : '#666',
                  border: 'none',
                  borderBottom: viewMode === "sounds" ? '2px solid #fff' : '2px solid transparent',
                  borderRadius: 0,
                  cursor: 'pointer',
                  fontSize: '11px',
                  fontWeight: 600,
                  transition: 'all 0.2s',
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis'
                }}
              >
                SOUNDS
              </button>
              <button
                onClick={() => {
                  setViewMode("engine");
                  setSelectedEventId(null);
                  setSelectedCommandIndex(null);
                  setSelectedSoundId(null);
                }}
                style={{
                  flex: 1,
                  padding: '6px 8px',
                  backgroundColor: 'transparent',
                  color: viewMode === "engine" ? '#fff' : '#666',
                  border: 'none',
                  borderBottom: viewMode === "engine" ? '2px solid #fff' : '2px solid transparent',
                  borderRadius: 0,
                  cursor: 'pointer',
                  fontSize: '11px',
                  fontWeight: 600,
                  transition: 'all 0.2s',
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis'
                }}
              >
                ENGINE
              </button>
              <button
                onClick={() => {
                  setViewMode("browser");
                  setSelectedEventId(null);
                  setSelectedCommandIndex(null);
                  setSelectedSoundId(null);
                }}
                style={{
                  flex: 1,
                  padding: '6px 8px',
                  backgroundColor: 'transparent',
                  color: viewMode === "browser" ? '#fff' : '#666',
                  border: 'none',
                  borderBottom: viewMode === "browser" ? '2px solid #fff' : '2px solid transparent',
                  borderRadius: 0,
                  cursor: 'pointer',
                  fontSize: '11px',
                  fontWeight: 600,
                  transition: 'all 0.2s',
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis'
                }}
              >
                BROWSER
              </button>
              <button
                onClick={() => {
                  setViewMode("loops");
                  setSelectedEventId(null);
                  setSelectedCommandIndex(null);
                  setSelectedSoundId(null);
                }}
                style={{
                  flex: 1,
                  padding: '6px 8px',
                  backgroundColor: 'transparent',
                  color: viewMode === "loops" ? '#fff' : '#666',
                  border: 'none',
                  borderBottom: viewMode === "loops" ? '2px solid #fff' : '2px solid transparent',
                  borderRadius: 0,
                  cursor: 'pointer',
                  fontSize: '11px',
                  fontWeight: 600,
                  transition: 'all 0.2s',
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis'
                }}
              >
                LOOPS
              </button>
              <button
                onClick={() => {
                  setViewMode("timeline");
                  setSelectedEventId(null);
                  setSelectedCommandIndex(null);
                  setSelectedSoundId(null);
                }}
                style={{
                  flex: 1,
                  padding: '6px 8px',
                  backgroundColor: 'transparent',
                  color: '#666',
                  border: 'none',
                  borderBottom: '2px solid transparent',
                  borderRadius: 0,
                  cursor: 'pointer',
                  fontSize: '11px',
                  fontWeight: 600,
                  transition: 'all 0.2s',
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis'
                }}
              >
                TIMELINE
              </button>
              <button
                onClick={() => {
                  setViewMode("presets");
                  setSelectedEventId(null);
                  setSelectedCommandIndex(null);
                  setSelectedSoundId(null);
                }}
                style={{
                  flex: 1,
                  padding: '6px 8px',
                  backgroundColor: 'transparent',
                  color: viewMode === "presets" ? '#fff' : '#666',
                  border: 'none',
                  borderBottom: viewMode === "presets" ? '2px solid #fff' : '2px solid transparent',
                  borderRadius: 0,
                  cursor: 'pointer',
                  fontSize: '11px',
                  fontWeight: 600,
                  transition: 'all 0.2s',
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis'
                }}
              >
                PRESETS
              </button>
              {/* Diagnostics Toggle */}
              <button
                onClick={() => setIsDiagnosticsHUDVisible(prev => !prev)}
                title="Toggle Diagnostics HUD (Ctrl+D)"
                style={{
                  padding: '6px 10px',
                  backgroundColor: isDiagnosticsHUDVisible ? '#16a34a' : 'transparent',
                  color: isDiagnosticsHUDVisible ? '#fff' : '#666',
                  border: 'none',
                  borderBottom: '2px solid transparent',
                  borderRadius: 0,
                  cursor: 'pointer',
                  fontSize: '11px',
                  fontWeight: 600,
                  transition: 'all 0.2s',
                  marginLeft: 'auto'
                }}
              >
                📊 DIAG
              </button>
              {/* Shortcuts Toggle */}
              <button
                onClick={() => setIsShortcutsPanelVisible(prev => !prev)}
                title="Keyboard Shortcuts (Ctrl+/ or ?)"
                style={{
                  padding: '6px 10px',
                  backgroundColor: isShortcutsPanelVisible ? '#2563eb' : 'transparent',
                  color: isShortcutsPanelVisible ? '#fff' : '#666',
                  border: 'none',
                  borderBottom: '2px solid transparent',
                  borderRadius: 0,
                  cursor: 'pointer',
                  fontSize: '11px',
                  fontWeight: 600,
                  transition: 'all 0.2s'
                }}
              >
                ⌨️
              </button>
              {/* History Toggle */}
              <button
                onClick={() => setIsHistoryPanelVisible(prev => !prev)}
                title="History Panel (Ctrl+H)"
                style={{
                  padding: '6px 10px',
                  backgroundColor: isHistoryPanelVisible ? '#7c3aed' : 'transparent',
                  color: isHistoryPanelVisible ? '#fff' : '#666',
                  border: 'none',
                  borderBottom: '2px solid transparent',
                  borderRadius: 0,
                  cursor: 'pointer',
                  fontSize: '11px',
                  fontWeight: 600,
                  transition: 'all 0.2s'
                }}
              >
                📜
              </button>
            </div>
          </div>

          {viewMode === 'events' && (
            <>
              <div className="events-actions">
            <button className="btn-add" onClick={handleAddEvent}>
              <span>➕</span>
              <span>Add Event</span>
            </button>
            <button className="btn-import" onClick={handleImportTemplate} title="Legacy template format (not project save)">
              <span>📥</span>
              <span>Import Template</span>
            </button>
            <button
              className="btn-export"
              onClick={handleExportTemplate}
              title="Legacy template format (not project save)"
            >
              <span>📤</span>
              <span>Export Template</span>
            </button>
            <button
              className="btn-undo"
              onClick={handleUndo}
              disabled={!canUndo}
              title="Undo"
            >
              ↶
            </button>
            <button
              className="btn-redo"
              onClick={handleRedo}
              disabled={!canRedo}
              title="Redo"
            >
              ↷
            </button>
          </div>

          <button className="btn-import-audio" onClick={handleImportAudioFiles}>
            <span>🎵</span>
            <span>Import Audio Files</span>
          </button>

          <div className="event-tabs" style={{
            display: 'flex',
            gap: '4px',
            padding: '8px 12px',
            borderBottom: '1px solid #333',
            backgroundColor: '#1f1f1f'
          }}>
            <button
              onClick={() => setEventTab("all")}
              style={{
                flex: 1,
                padding: '8px 12px',
                backgroundColor: eventTab === "all" ? '#37373d' : 'transparent',
                color: eventTab === "all" ? '#d4d4d4' : '#9d9d9d',
                border: eventTab === "all" ? '1px solid #4e4e52' : '1px solid transparent',
                borderRadius: '4px',
                cursor: 'pointer',
                fontSize: '11px',
                fontWeight: 600,
                transition: 'all 0.2s'
              }}
            >
              ALL EVENTS
            </button>
            <button
              onClick={() => setEventTab("used")}
              style={{
                flex: 1,
                padding: '8px 12px',
                backgroundColor: eventTab === "used" ? '#37373d' : 'transparent',
                color: eventTab === "used" ? '#d4d4d4' : '#9d9d9d',
                border: eventTab === "used" ? '1px solid #4e4e52' : '1px solid transparent',
                borderRadius: '4px',
                cursor: 'pointer',
                fontSize: '11px',
                fontWeight: 600,
                transition: 'all 0.2s'
              }}
            >
              WITH SOUNDS
            </button>
          </div>

          <input
            type="text"
            className="search-input"
            placeholder="Search events..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />

          <div className="event-modify-buttons">
            <button
              className="btn-rename"
              onClick={handleRenameEvent}
              disabled={!selectedEventId}
            >
              Rename
            </button>
            <button
              className="btn-delete-event"
              onClick={handleDeleteEvent}
              disabled={!selectedEventId}
            >
              Delete
            </button>
          </div>

          <div className="events-list">
            {filteredEvents.map((evt) => (
              <div
                key={evt.id}
                className={`event-item ${selectedEventId === evt.id ? "selected" : ""}`}
                onClick={() => {
                  setSelectedEventId(evt.id);
                  setSelectedCommandIndex(null);
                }}
                draggable
                onDragStart={(e) => handleEventDragStart(e, evt.id)}
                onDragOver={handleEventDragOver}
                onDrop={(e) => handleEventDrop(e, evt.id)}
                onDragEnd={handleEventDragEnd}
                style={{
                  cursor: 'move',
                  opacity: draggedEventId === evt.id ? 0.5 : 1,
                  whiteSpace: 'normal',
                  overflowWrap: 'anywhere',
                }}
              >
                {evt.eventName}
              </div>
            ))}
          </div>

            </>
          )}

          {viewMode === 'sounds' && (
            <>
              {/* Sounds Mode */}
              <input
                type="text"
                className="search-input"
                placeholder="Search sounds..."
                value={soundSearchQuery}
                onChange={(e) => setSoundSearchQuery(e.target.value)}
                onFocus={(e) => e.target.select()}
              />

              <div style={{
                display: 'flex',
                flex: 1,
                overflow: 'hidden'
              }}>
                {/* Sound cards grid */}
                <div style={{
                  display: 'grid',
                  gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))',
                  gridAutoRows: 'min-content',
                  gap: '8px',
                  padding: '12px',
                  overflowY: 'auto',
                  flex: 1
                }}>
                  {filteredSounds.length === 0 ? (
                    <div style={{
                      gridColumn: '1 / -1',
                      padding: '40px 16px',
                      textAlign: 'center',
                      color: '#666',
                      fontSize: '12px'
                    }}>
                      <div style={{ marginBottom: '12px', fontSize: '32px' }}>🎵</div>
                      <div style={{ fontSize: '14px', color: '#888' }}>No sounds loaded</div>
                      <div style={{ marginTop: '8px', fontSize: '11px', color: '#555' }}>
                        Click "Import & Match Sounds" to load audio files
                      </div>
                    </div>
                  ) : (
                    [...filteredSounds].sort((a, b) => a.soundId.localeCompare(b.soundId)).map((sound) => {
                      const displayName = sound.soundId.replace(/\.[^/.]+$/, '');
                      const extension = sound.soundId.match(/\.[^/.]+$/)?.[0]?.replace('.', '').toUpperCase() || '';
                      const audioFile = audioFiles.find(af => af.name === sound.soundId);

                      return (
                        <div
                          key={sound.soundId}
                          onClick={() => {
                            if (selectedSoundId === sound.soundId) {
                              // Second click on same sound - close panel
                              setIsSoundInspectorOpen(false);
                              setSelectedSoundId(null);
                            } else {
                              // First click - select sound and open panel
                              setSelectedSoundId(sound.soundId);
                              if (!isSoundInspectorOpen) {
                                setIsSoundInspectorOpen(true);
                              }
                            }
                          }}
                          style={{
                            cursor: 'pointer',
                            padding: '12px',
                            backgroundColor: selectedSoundId === sound.soundId ? '#2563eb' : '#252525',
                            borderRadius: '8px',
                            border: selectedSoundId === sound.soundId ? '1px solid #3b82f6' : '1px solid #333',
                            transition: 'all 0.15s ease',
                            display: 'flex',
                            flexDirection: 'column',
                            gap: '8px',
                          }}
                          onMouseEnter={(e) => {
                            if (selectedSoundId !== sound.soundId) {
                              e.currentTarget.style.backgroundColor = '#2a2a2a';
                              e.currentTarget.style.borderColor = '#444';
                            }
                          }}
                          onMouseLeave={(e) => {
                            if (selectedSoundId !== sound.soundId) {
                              e.currentTarget.style.backgroundColor = '#252525';
                              e.currentTarget.style.borderColor = '#333';
                            }
                          }}
                        >
                          <div style={{
                            display: 'flex',
                            alignItems: 'flex-start',
                            justifyContent: 'space-between',
                            gap: '8px'
                          }}>
                            <div style={{
                              fontSize: '12px',
                              fontWeight: 600,
                              color: selectedSoundId === sound.soundId ? '#fff' : '#e0e0e0',
                              wordBreak: 'break-word',
                              lineHeight: '1.3'
                            }}>
                              {displayName}
                            </div>
                            <span style={{
                              padding: '2px 6px',
                              borderRadius: '4px',
                              fontSize: '9px',
                              fontWeight: 700,
                              backgroundColor: selectedSoundId === sound.soundId ? 'rgba(255,255,255,0.2)' : '#333',
                              color: selectedSoundId === sound.soundId ? '#fff' : '#888',
                              flexShrink: 0
                            }}>
                              {extension}
                            </span>
                          </div>

                          <div style={{
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'space-between',
                            gap: '8px'
                          }}>
                            <div style={{
                              fontSize: '10px',
                              color: selectedSoundId === sound.soundId ? 'rgba(255,255,255,0.7)' : '#666',
                              display: 'flex',
                              gap: '8px'
                            }}>
                              <span>{audioFile?.duration ? `${Math.round(audioFile.duration * 1000)}ms` : '—'}</span>
                              <span>{audioFile?.size || '—'}</span>
                            </div>
                            {sound.eventNames.length > 0 && (
                              <span style={{
                                padding: '2px 6px',
                                borderRadius: '4px',
                                fontSize: '9px',
                                fontWeight: 600,
                                backgroundColor: selectedSoundId === sound.soundId ? 'rgba(255,255,255,0.2)' : '#1d4ed8',
                                color: '#fff',
                              }}>
                                {sound.eventNames.length} {sound.eventNames.length === 1 ? 'event' : 'events'}
                              </span>
                            )}
                          </div>
                        </div>
                      );
                    })
                  )}
                </div>
              </div>
            </>
          )}

          {viewMode === 'engine' && (
            <div style={{
              flex: 1,
              display: 'flex',
              flexDirection: 'column',
              overflow: 'hidden',
              padding: '16px'
            }}>
              <EngineTab
                engineClient={engineClientRef.current}
                engineStatus={engineStatus}
                engineLogs={engineLogs}
                engineUrl={engineUrl}
                onUrlChange={setEngineUrl}
                latencyStats={latencyStats}
                perEventStats={perEventStats}
                onClearStats={handleClearStats}
                runtimeStub={runtimeStubRef.current}
                useNativeCore={useNativeCore}
                onToggleNativeCore={handleToggleNativeCore}
                nativeCoreAvailable={nativeCoreAvailable}
                nativeCoreError={nativeCoreError}
                nativeLatencySplit={nativeLatencySplit}
                onRunDeterminismCheck={handleDeterminismCheck}
                getCoreStats={() => nativeCoreRef.current?.getStats() ?? null}
                useProjectRoutes={true}
                nativeCore={nativeCoreRef.current}
                onReloadCore={handleReloadCore}
                onLocalFlood={handleLocalFlood}
                lastCommand={lastCommandInfo}
              />
            </div>
          )}

          {viewMode === 'browser' && (
            <div style={{
              flex: 1,
              display: 'flex',
              flexDirection: 'column',
              overflow: 'hidden',
              padding: '16px'
            }}>
              <h2 style={{ margin: '0 0 16px 0', fontSize: '14px', color: '#888', textTransform: 'uppercase', letterSpacing: '1px' }}>
                File Browser
              </h2>
              <FileBrowser
                roots={browserRoots}
                onSelect={(file) => {
                  if (file.type === 'audio') {
                    setSelectedSoundId(file.id);
                  }
                }}
                onOpen={(file) => {
                  if (file.type === 'audio') {
                    handlePlaySound(file.id);
                  }
                }}
              />
            </div>
          )}

          {viewMode === 'loops' && (
            <div style={{
              flex: 1,
              display: 'flex',
              flexDirection: 'column',
              overflow: 'hidden',
              padding: '16px'
            }}>
              <h2 style={{ margin: '0 0 16px 0', fontSize: '14px', color: '#888', textTransform: 'uppercase', letterSpacing: '1px' }}>
                Loop Analyzer
              </h2>
              <AudioLoopUploader />
            </div>
          )}

          {viewMode === 'presets' && (
            <div style={{
              flex: 1,
              display: 'flex',
              flexDirection: 'column',
              overflow: 'hidden',
              padding: '16px'
            }}>
              <h2 style={{ margin: '0 0 16px 0', fontSize: '14px', color: '#888', textTransform: 'uppercase', letterSpacing: '1px' }}>
                Preset Manager
              </h2>
              <div style={{
                flex: 1,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor: '#0d0d0d',
                borderRadius: '8px',
                color: '#666',
                fontSize: '14px',
              }}>
                <div style={{ textAlign: 'center' }}>
                  <div style={{ fontSize: '48px', marginBottom: '16px' }}>🎛️</div>
                  <div>Plugin presets will appear here</div>
                  <div style={{ fontSize: '12px', color: '#444', marginTop: '8px' }}>
                    Select a plugin insert to manage its presets
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>

        <div className="sound-status" style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: '12px',
          padding: '8px 16px'
        }}>
          <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
            <button
              onClick={handlePlayEvent}
              disabled={!selectedEvent || selectedEvent.commands.length === 0 || (selectedEvent && playingEvents.has(selectedEvent.id)) || isPlaying}
              style={{
                padding: '6px 12px',
                backgroundColor: selectedEvent && playingEvents.has(selectedEvent.id)
                  ? '#2a2a2a'
                  : selectedEvent && selectedEvent.commands.length > 0 && !isPlaying
                  ? '#16a34a'
                  : '#2a2a2a',
                color: selectedEvent && selectedEvent.commands.length > 0 && !playingEvents.has(selectedEvent.id) && !isPlaying ? '#fff' : '#6d6d6d',
                border: '1px solid #3a3a3a',
                borderRadius: '4px',
                cursor: selectedEvent && selectedEvent.commands.length > 0 && !playingEvents.has(selectedEvent.id) && !isPlaying ? 'pointer' : 'not-allowed',
                fontSize: '11px',
                fontWeight: 500,
                transition: 'all 0.15s',
                display: 'flex',
                alignItems: 'center',
                gap: '4px',
                opacity: selectedEvent && selectedEvent.commands.length > 0 && !playingEvents.has(selectedEvent.id) && !isPlaying ? 1 : 0.5
              }}
            >
              <span style={{ fontSize: '11px' }}>▶</span>
              <span>Play</span>
            </button>
            <button
              onClick={handleStopEvent}
              disabled={!selectedEvent || !playingEvents.has(selectedEvent.id)}
              style={{
                padding: '6px 12px',
                backgroundColor: selectedEvent && playingEvents.has(selectedEvent.id) ? '#dc2626' : '#2a2a2a',
                color: selectedEvent && playingEvents.has(selectedEvent.id) ? '#fff' : '#6d6d6d',
                border: '1px solid #3a3a3a',
                borderRadius: '4px',
                cursor: selectedEvent && playingEvents.has(selectedEvent.id) ? 'pointer' : 'not-allowed',
                fontSize: '11px',
                fontWeight: 500,
                transition: 'all 0.15s',
                display: 'flex',
                alignItems: 'center',
                gap: '4px',
                opacity: selectedEvent && playingEvents.has(selectedEvent.id) ? 1 : 0.5
              }}
            >
              <span style={{ fontSize: '11px' }}>⏹</span>
              <span>Stop</span>
            </button>
            <button
              onClick={handleStopAllEvents}
              disabled={!selectedEvent || !playingEvents.has(selectedEvent.id)}
              style={{
                padding: '6px 12px',
                backgroundColor: selectedEvent && playingEvents.has(selectedEvent.id) ? '#ea580c' : '#2a2a2a',
                color: selectedEvent && playingEvents.has(selectedEvent.id) ? '#fff' : '#6d6d6d',
                border: '1px solid #3a3a3a',
                borderRadius: '4px',
                cursor: selectedEvent && playingEvents.has(selectedEvent.id) ? 'pointer' : 'not-allowed',
                fontSize: '11px',
                fontWeight: 500,
                transition: 'all 0.15s',
                display: 'flex',
                alignItems: 'center',
                gap: '4px',
                opacity: selectedEvent && playingEvents.has(selectedEvent.id) ? 1 : 0.5
              }}
            >
              <span style={{ fontSize: '11px' }}>⏹</span>
              <span>Stop All</span>
            </button>
            <div style={{
              width: '1px',
              height: '24px',
              backgroundColor: '#3a3a3a',
              margin: '0 4px'
            }} />
            <button
              onClick={() => {
                if (!selectedEvent || !engineClientRef.current) return;
                engineClientRef.current.triggerEvent(selectedEvent.eventName);
              }}
              disabled={!selectedEvent || engineStatus !== 'connected'}
              style={{
                padding: '6px 12px',
                backgroundColor: engineStatus === 'connected' && selectedEvent ? '#4a7afe' : '#2a2a2a',
                color: engineStatus === 'connected' && selectedEvent ? '#fff' : '#6d6d6d',
                border: '1px solid #3a3a3a',
                borderRadius: '4px',
                cursor: engineStatus === 'connected' && selectedEvent ? 'pointer' : 'not-allowed',
                fontSize: '11px',
                fontWeight: 500,
                transition: 'all 0.15s',
                display: 'flex',
                alignItems: 'center',
                gap: '4px',
                opacity: engineStatus === 'connected' && selectedEvent ? 1 : 0.5
              }}
              title={engineStatus !== 'connected' ? 'Connect to engine first' : 'Send event to connected engine'}
            >
              <span style={{ fontSize: '11px' }}>📡</span>
              <span>Send to Engine</span>
            </button>
          </div>
          <div style={{ flex: 1, textAlign: 'center' }}>
            {playingEvents.size > 0
              ? `Playing ${playingEvents.size} event${playingEvents.size > 1 ? 's' : ''}: ${Array.from(playingEvents).join(', ')}`
              : currentPlayingSound || "No sound playing"}
          </div>
          <input
            ref={fileInputRef}
            type="file"
            accept=".json"
            style={{ display: "none" }}
            onChange={handleTemplateFileChange}
          />
          <input
            ref={audioFilesInputRef}
            type="file"
            accept="audio/*,.mp3,.wav,.ogg,.m4a,.aac"
            multiple
            {...({ webkitdirectory: "", directory: "" } as any)}
            style={{ display: "none" }}
            onChange={handleAudioFilesChange}
          />
          <input
            ref={audioFolderInputRef}
            type="file"
            accept="audio/*,.mp3,.wav,.ogg,.m4a,.aac"
            multiple
            {...({ webkitdirectory: "", directory: "" } as any)}
            style={{ display: "none" }}
            onChange={handleAudioFolderChange}
          />
        </div>
        </>)}

        {/* Commands Panel - hidden for fullscreen views like timeline */}
        {viewMode !== 'engine' && viewMode !== 'timeline' && (
        <div className="commands-panel">
          <div className="panel-header">
            <h3 style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              {viewMode === 'sounds' ? (
                <>
                  <span>SOUNDS</span>
                  <button
                    onClick={handleAnalyzeAndImportSounds}
                    style={{
                      padding: '6px 14px',
                      background: 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)',
                      color: '#fff',
                      border: '1px solid #b45309',
                      borderRadius: '4px',
                      cursor: 'pointer',
                      fontSize: '12px',
                      fontWeight: 600,
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      gap: '6px',
                      transition: 'all 0.2s cubic-bezier(0.4, 0, 0.2, 1)',
                      boxShadow: '0 1px 3px rgba(0, 0, 0, 0.3)',
                      letterSpacing: '0.3px'
                    }}
                    onMouseEnter={(e) => {
                      e.currentTarget.style.transform = 'translateY(-1px)';
                      e.currentTarget.style.background = 'linear-gradient(135deg, #fbbf24 0%, #f59e0b 100%)';
                      e.currentTarget.style.boxShadow = '0 2px 6px rgba(0, 0, 0, 0.4)';
                    }}
                    onMouseLeave={(e) => {
                      e.currentTarget.style.transform = 'translateY(0)';
                      e.currentTarget.style.background = 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)';
                      e.currentTarget.style.boxShadow = '0 1px 3px rgba(0, 0, 0, 0.3)';
                    }}
                    title="Import audio files from folder and match with JSON events"
                  >
                    <span style={{ fontSize: '14px', lineHeight: '1' }}>🔍</span>
                    <span>Import & Match Sounds</span>
                  </button>
                  <span style={{
                    fontSize: '12px',
                    color: '#e0e0e0',
                    marginLeft: '12px',
                    padding: '4px 10px',
                    backgroundColor: '#333',
                    borderRadius: '4px',
                    fontWeight: 600
                  }}>
                    {audioFiles.length} loaded
                  </span>
                </>
              ) : (
                <>
                  COMMANDS FOR
                  <span style={{
                    backgroundColor: '#0e7ac4',
                    color: '#fff',
                    padding: '4px 12px',
                    borderRadius: '6px',
                    fontSize: '13px',
                    fontWeight: 600,
                    letterSpacing: '0.3px',
                    textTransform: 'none'
                  }}>
                    {selectedEvent?.eventName || "..."}
                  </span>
                  <button
                    onClick={handleAddCommand}
                    style={{
                      padding: '6px 14px',
                      background: 'linear-gradient(135deg, #4a5568 0%, #2d3748 100%)',
                      color: '#fff',
                      border: '1px solid #1a202c',
                      borderRadius: '4px',
                      cursor: 'pointer',
                      fontSize: '12px',
                      fontWeight: 600,
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      gap: '6px',
                      transition: 'all 0.2s cubic-bezier(0.4, 0, 0.2, 1)',
                      boxShadow: '0 1px 3px rgba(0, 0, 0, 0.3)',
                      letterSpacing: '0.3px'
                    }}
                    onMouseEnter={(e) => {
                      e.currentTarget.style.transform = 'translateY(-1px)';
                      e.currentTarget.style.background = 'linear-gradient(135deg, #5a6678 0%, #3d4758 100%)';
                      e.currentTarget.style.boxShadow = '0 2px 6px rgba(0, 0, 0, 0.4)';
                    }}
                    onMouseLeave={(e) => {
                      e.currentTarget.style.transform = 'translateY(0)';
                      e.currentTarget.style.background = 'linear-gradient(135deg, #4a5568 0%, #2d3748 100%)';
                      e.currentTarget.style.boxShadow = '0 1px 3px rgba(0, 0, 0, 0.3)';
                    }}
                  >
                    <span style={{ fontSize: '14px', lineHeight: '1' }}>+</span>
                    <span>Add Command</span>
                  </button>
                  <button
                    onClick={() => {
                      if (selectedEvent && selectedEvent.commands.length > 0) {
                        if (window.confirm(`Delete all ${selectedEvent.commands.length} commands from "${selectedEvent.eventName}"?`)) {
                          setProject(prev => {
                            if (!prev) return prev;
                            return {
                              ...prev,
                              events: prev.events.map(evt =>
                                evt.id === selectedEvent.id
                                  ? { ...evt, commands: [] }
                                  : evt
                              )
                            };
                          });
                          setSelectedCommandIndex(null);
                        }
                      }
                    }}
                    disabled={!selectedEvent || selectedEvent.commands.length === 0}
                    style={{
                      padding: '6px 14px',
                      background: selectedEvent && selectedEvent.commands.length > 0
                        ? 'linear-gradient(135deg, #dc2626 0%, #991b1b 100%)'
                        : '#2a2a2a',
                      color: selectedEvent && selectedEvent.commands.length > 0 ? '#fff' : '#666',
                      border: '1px solid #1a202c',
                      borderRadius: '4px',
                      cursor: selectedEvent && selectedEvent.commands.length > 0 ? 'pointer' : 'not-allowed',
                      fontSize: '12px',
                      fontWeight: 600,
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      gap: '6px',
                      transition: 'all 0.2s cubic-bezier(0.4, 0, 0.2, 1)',
                      boxShadow: selectedEvent && selectedEvent.commands.length > 0 ? '0 1px 3px rgba(0, 0, 0, 0.3)' : 'none',
                      letterSpacing: '0.3px',
                      opacity: selectedEvent && selectedEvent.commands.length > 0 ? 1 : 0.5
                    }}
                    onMouseEnter={(e) => {
                      if (selectedEvent && selectedEvent.commands.length > 0) {
                        e.currentTarget.style.transform = 'translateY(-1px)';
                        e.currentTarget.style.background = 'linear-gradient(135deg, #ef4444 0%, #b91c1c 100%)';
                        e.currentTarget.style.boxShadow = '0 2px 6px rgba(0, 0, 0, 0.4)';
                      }
                    }}
                    onMouseLeave={(e) => {
                      if (selectedEvent && selectedEvent.commands.length > 0) {
                        e.currentTarget.style.transform = 'translateY(0)';
                        e.currentTarget.style.background = 'linear-gradient(135deg, #dc2626 0%, #991b1b 100%)';
                        e.currentTarget.style.boxShadow = '0 1px 3px rgba(0, 0, 0, 0.3)';
                      }
                    }}
                  >
                    <span style={{ fontSize: '12px', lineHeight: '1' }}>×</span>
                    <span>Clear All</span>
                  </button>
                </>
              )}
            </h3>
            <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
              {viewMode === 'events' && isInspectorOpen && (
                <button
                  onClick={handleDetachInspector}
                  style={{
                    padding: '6px 12px',
                    backgroundColor: isInspectorDetached ? '#f59e0b' : '#2a2a2a',
                    color: '#fff',
                    border: '1px solid #3a3a3a',
                    borderRadius: '6px',
                    cursor: 'pointer',
                    fontSize: '12px',
                    fontWeight: 600,
                    transition: 'all 0.2s ease',
                    display: 'flex',
                    alignItems: 'center',
                    gap: '6px'
                  }}
                  title={isInspectorDetached ? 'Attach Inspector' : 'Detach Inspector'}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.backgroundColor = isInspectorDetached ? '#f59e0b' : '#3a3a3a';
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.backgroundColor = isInspectorDetached ? '#f59e0b' : '#2a2a2a';
                  }}
                >
                  <span>{isInspectorDetached ? '📌' : '🔗'}</span>
                  <span>{isInspectorDetached ? 'Attach' : 'Detach'}</span>
                </button>
              )}
              {isMixerDetached && isMixerPinned && (
                <button
                  onClick={() => {
                    if (detachedWindowRef.current && !detachedWindowRef.current.closed) {
                      detachedWindowRef.current.focus();
                      setMixerButtonActive(true);
                      setTimeout(() => setMixerButtonActive(false), 300);
                    }
                  }}
                  className={`btn-add-command ${mixerButtonActive ? 'mixer-button-active' : ''}`}
                  title="Click to bring mixer window to front"
                >
                  <span>📌</span>
                  <span>Mixer Pinned</span>
                </button>
              )}
            </div>
          </div>

          <div className="commands-table-wrapper">
            {viewMode === 'events' && selectedEvent && selectedEvent.commands.length > 0 ? (
              <table className="commands-table">
                <thead>
                  <tr>
                    <th>#</th>
                    <th>COMMAND</th>
                    <th>SOUND</th>
                    <th>VOLUME</th>
                    <th>PAN</th>
                    <th>FADE DUR</th>
                    <th>DELAY</th>
                    <th>LOOP</th>
                    <th>OVERLAP</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {selectedEvent.commands.map((cmd, idx) => {
                    return (
                      <tr
                        key={cmd.id || `cmd-${idx}`}
                        className={`cmd-${cmd.type.toLowerCase()} ${selectedCommandIndex === idx ? "selected" : ""}`}
                        onClick={() => setSelectedCommandIndex(idx)}
                        draggable
                        onDragStart={(e) => handleCommandDragStart(e, idx)}
                        onDragOver={handleDragOver}
                        onDrop={(e) => handleDrop(e, idx)}
                        onDragEnd={handleDragEnd}
                        style={{
                          cursor: 'move',
                          opacity: draggedCommandIndex === idx ? 0.5 : 1,
                        }}
                      >
                        <td>{idx + 1}</td>
                        <td>
                          <select
                            value={cmd.type}
                            onChange={(e) => {
                              e.stopPropagation();
                              handleUpdateCommand(idx, { type: e.target.value as CommandType });
                            }}
                            onClick={(e) => e.stopPropagation()}
                            style={{
                              padding: '6px 10px',
                              backgroundColor: '#2a2a2a',
                              color: '#fff',
                              border: '1px solid #3a3a3a',
                              borderRadius: '4px',
                              fontSize: '12px',
                              width: '100%',
                              textAlign: 'center',
                              height: '30px'
                            }}
                          >
                            <option value="Play">Play</option>
                            <option value="Stop">Stop</option>
                            <option value="Fade">Fade</option>
                            <option value="Pause">Pause</option>
                            <option value="Execute">Execute</option>
                          </select>
                        </td>
                        <td>
                          {cmd.type === "Execute" ? (
                            <select
                              value={(cmd as ExecuteCommand).eventId || ""}
                              onChange={(e) => {
                                e.stopPropagation();
                                handleUpdateCommand(idx, { eventId: e.target.value });
                              }}
                              onClick={(e) => e.stopPropagation()}
                              style={{
                                padding: '6px 10px',
                                backgroundColor: '#2a2a2a',
                                color: '#fff',
                                border: '1px solid #3a3a3a',
                                borderRadius: '4px',
                                fontSize: '12px',
                                width: '100%',
                                textAlign: 'center',
                                height: '30px'
                              }}
                            >
                              <option value="">-- Select Event --</option>
                              {project.events
                                .filter(evt => evt.eventName !== selectedEvent?.eventName) // Don't allow executing itself
                                .sort((a, b) => a.eventName.localeCompare(b.eventName))
                                .map((evt) => (
                                  <option key={evt.id} value={evt.eventName}>
                                    {evt.eventName}
                                  </option>
                                ))}
                            </select>
                          ) : (cmd.type === "Play" || cmd.type === "Stop" || cmd.type === "Fade" || cmd.type === "Pause") ? (
                            <select
                              value={(cmd as PlayCommand).soundId || ""}
                              onChange={(e) => {
                                e.stopPropagation();
                                handleUpdateCommand(idx, { soundId: e.target.value });
                              }}
                              onClick={(e) => e.stopPropagation()}
                              style={{
                                padding: '6px 10px',
                                backgroundColor: '#2a2a2a',
                                color: '#fff',
                                border: '1px solid #3a3a3a',
                                borderRadius: '4px',
                                fontSize: '12px',
                                width: '100%',
                                textAlign: 'center',
                                height: '30px'
                              }}
                            >
                              <option value="">-- Select Sound --</option>
                              {audioFiles
                                .sort((a, b) => a.name.localeCompare(b.name))
                                .map((audioFile) => (
                                  <option key={audioFile.id} value={audioFile.name}>
                                    {audioFile.name}
                                  </option>
                                ))}
                            </select>
                          ) : (
                            <span>—</span>
                          )}
                        </td>
                        <td
                          style={{ position: 'relative' }}
                          onDragStart={(e) => { if (volumeSliderOpen === idx) { e.preventDefault(); e.stopPropagation(); } }}
                          onDrag={(e) => { if (volumeSliderOpen === idx) { e.preventDefault(); e.stopPropagation(); } }}
                          onDragEnd={(e) => { if (volumeSliderOpen === idx) { e.preventDefault(); e.stopPropagation(); } }}
                        >
                          {cmd.type === "Play" || cmd.type === "Fade" || cmd.type === "Stop" || cmd.type === "Pause" || cmd.type === "Execute" ? (
                            <>
                              <input
                                type="text"
                                inputMode="decimal"
                                value={tableVolumeDraft[idx] !== undefined ? tableVolumeDraft[idx] : formatDecimal(cmd.type === "Play" ? (cmd as PlayCommand).volume ?? 1 : cmd.type === "Fade" ? (cmd as FadeCommand).targetVolume ?? 0 : cmd.type === "Execute" ? (cmd as ExecuteCommand).volume ?? 1 : cmd.type === "Stop" ? (cmd as StopCommand).volume ?? 0 : (cmd as PauseCommand).volume ?? 0)}
                                onChange={(e) => {
                                  e.stopPropagation();
                                  const value = e.target.value.replace(',', '.');
                                  setTableVolumeDraft({ ...tableVolumeDraft, [idx]: value });
                                }}
                                onMouseDown={(e) => {
                                  if (e.altKey || e.ctrlKey || e.metaKey) {
                                    e.preventDefault();
                                    e.stopPropagation();
                                    const defaultValue = (cmd.type === "Play" || cmd.type === "Execute") ? 1 : 0;
                                    handleUpdateCommand(idx, cmd.type === "Play" ? { volume: defaultValue } : cmd.type === "Execute" ? { volume: defaultValue } : cmd.type === "Fade" ? { targetVolume: defaultValue } : { volume: defaultValue });
                                    const newDraft = { ...tableVolumeDraft };
                                    delete newDraft[idx];
                                    setTableVolumeDraft(newDraft);
                                  }
                                }}
                                onKeyDown={(e) => {
                                  if (e.key === 'Enter') {
                                    e.stopPropagation();
                                    const value = tableVolumeDraft[idx] !== undefined ? tableVolumeDraft[idx] : e.currentTarget.value;
                                    if (value === "") {
                                      if (cmd.type === "Play" || cmd.type === "Execute") {
                                        handleUpdateCommand(idx, { volume: undefined });
                                      } else if (cmd.type === "Fade") {
                                        handleUpdateCommand(idx, { targetVolume: 0 });
                                      } else {
                                        handleUpdateCommand(idx, { volume: 0 });
                                      }
                                    } else {
                                      const numValue = parseFloat(value.replace(',', '.'));
                                      if (!isNaN(numValue)) {
                                        const clampedValue = Math.max(0, Math.min(1, numValue));
                                        if (cmd.type === "Play" || cmd.type === "Execute") {
                                          handleUpdateCommand(idx, { volume: clampedValue });
                                        } else if (cmd.type === "Fade") {
                                          handleUpdateCommand(idx, { targetVolume: clampedValue });
                                        } else {
                                          handleUpdateCommand(idx, { volume: clampedValue });
                                        }
                                      }
                                    }
                                    const newDraft = { ...tableVolumeDraft };
                                    delete newDraft[idx];
                                    setTableVolumeDraft(newDraft);
                                    e.currentTarget.blur();
                                  } else if (e.key === 'Escape') {
                                    e.stopPropagation();
                                    const newDraft = { ...tableVolumeDraft };
                                    delete newDraft[idx];
                                    setTableVolumeDraft(newDraft);
                                    e.currentTarget.blur();
                                  }
                                }}
                                onBlur={() => {
                                  const newDraft = { ...tableVolumeDraft };
                                  delete newDraft[idx];
                                  setTableVolumeDraft(newDraft);
                                }}
                                onClick={() => {
                                  if (volumeClickTimer.current[idx]) {
                                    clearTimeout(volumeClickTimer.current[idx]!);
                                    volumeClickTimer.current[idx] = null;
                                  } else {
                                    volumeClickTimer.current[idx] = setTimeout(() => {
                                      setVolumeSliderOpen(idx);
                                      volumeClickTimer.current[idx] = null;
                                    }, 200);
                                  }
                                }}
                                onDoubleClick={(e) => {
                                  if (volumeClickTimer.current[idx]) {
                                    clearTimeout(volumeClickTimer.current[idx]!);
                                    volumeClickTimer.current[idx] = null;
                                  }
                                  setVolumeSliderOpen(null);
                                  e.currentTarget.focus();
                                  e.currentTarget.select();
                                }}
                                onFocus={(e) => {
                                  if (volumeSliderOpen !== idx) {
                                    e.target.select();
                                  }
                                }}
                                style={{
                                  padding: '6px 10px',
                                  backgroundColor: '#2a2a2a',
                                  color: '#fff',
                                  border: '1px solid #3a3a3a',
                                  borderRadius: '4px',
                                  fontSize: '12px',
                                  width: '65px',
                                  height: '30px',
                                  textAlign: 'center',
                                  cursor: 'pointer'
                                }}
                              />
                              {volumeSliderOpen === idx && (
                                <>
                                  <div
                                    style={{
                                      position: 'fixed',
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      zIndex: 9999
                                    }}
                                    onClick={() => setVolumeSliderOpen(null)}
                                  />
                                  <div
                                    draggable={false}
                                    style={{
                                      position: 'absolute',
                                      top: '50%',
                                      left: '50%',
                                      transform: 'translate(-50%, -50%)',
                                      padding: '16px',
                                      backgroundColor: '#1a1a1a',
                                      border: '1px solid #3a3a3a',
                                      borderRadius: '8px',
                                      boxShadow: '0 4px 12px rgba(0, 0, 0, 0.5)',
                                      zIndex: 10000,
                                      width: 'calc(100% - 8px)',
                                      maxWidth: '300px',
                                      minWidth: '200px'
                                    }}
                                    onClick={(e) => e.stopPropagation()}
                                    onMouseDown={(e) => e.stopPropagation()}
                                    onMouseUp={(e) => e.stopPropagation()}
                                    onMouseMove={(e) => e.stopPropagation()}
                                    onDragStart={(e) => { e.preventDefault(); e.stopPropagation(); }}
                                    onDrag={(e) => { e.preventDefault(); e.stopPropagation(); }}
                                    onDragEnd={(e) => { e.preventDefault(); e.stopPropagation(); }}
                                  >
                                    <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                        <span style={{ fontSize: '11px', color: '#888', fontWeight: 600 }}>VOLUME</span>
                                        <span style={{ fontSize: '12px', color: '#fff', fontWeight: 600 }}>{formatDecimal(cmd.type === "Play" ? (cmd as PlayCommand).volume ?? 1 : cmd.type === "Fade" ? (cmd as FadeCommand).targetVolume ?? 0 : cmd.type === "Stop" ? (cmd as StopCommand).volume ?? 0 : (cmd as PauseCommand).volume ?? 0)}</span>
                                      </div>
                                      <input
                                        type="range"
                                        draggable={false}
                                        step="0.01"
                                        min="0"
                                        max="100"
                                        value={(() => {
                                          const vol = cmd.type === "Play" ? (cmd as PlayCommand).volume ?? 1 : cmd.type === "Fade" ? (cmd as FadeCommand).targetVolume ?? 0 : cmd.type === "Stop" ? (cmd as StopCommand).volume ?? 0 : (cmd as PauseCommand).volume ?? 0;
                                          return vol === 0 ? 0 : Math.log10(vol * 9 + 1) * 100;
                                        })()}
                                        autoFocus
                                        onMouseDown={(e) => {
                                          e.stopPropagation();
                                          if (e.altKey || e.ctrlKey || e.metaKey) {
                                            e.preventDefault();
                                            const defaultValue = cmd.type === "Play" ? 1 : 0;
                                            handleUpdateCommand(idx, cmd.type === "Play" ? { volume: defaultValue } : cmd.type === "Fade" ? { targetVolume: defaultValue } : { volume: defaultValue });
                                          }
                                        }}
                                        onMouseUp={(e) => e.stopPropagation()}
                                        onMouseMove={(e) => e.stopPropagation()}
                                        onClick={(e) => e.stopPropagation()}
                                        onDragStart={(e) => { e.preventDefault(); e.stopPropagation(); }}
                                        onDrag={(e) => { e.preventDefault(); e.stopPropagation(); }}
                                        onKeyDown={(e) => {
                                          e.stopPropagation();
                                          if (e.key === 'Enter' || e.key === 'Escape') {
                                            setVolumeSliderOpen(null);
                                          }
                                        }}
                                        onBlur={() => {
                                          setVolumeSliderOpen(null);
                                        }}
                                        onChange={(e) => {
                                          e.stopPropagation();
                                          const sliderValue = parseFloat((e.target as HTMLInputElement).value);
                                          const rawVolume = sliderValue === 0 ? 0 : (Math.pow(10, sliderValue / 100) - 1) / 9;
                                          const newVolume = Math.round(rawVolume * 100) / 100;
                                          handleUpdateCommand(idx, cmd.type === "Play" ? { volume: newVolume } : cmd.type === "Fade" ? { targetVolume: newVolume } : { volume: newVolume });
                                        }}
                                        style={{ width: '100%' }}
                                      />
                                    </div>
                                  </div>
                                </>
                              )}
                            </>
                          ) : (
                            <span>—</span>
                          )}
                        </td>
                        <td
                          style={{ position: 'relative' }}
                          onDragStart={(e) => { if (panSliderOpen === idx) { e.preventDefault(); e.stopPropagation(); } }}
                          onDrag={(e) => { if (panSliderOpen === idx) { e.preventDefault(); e.stopPropagation(); } }}
                          onDragEnd={(e) => { if (panSliderOpen === idx) { e.preventDefault(); e.stopPropagation(); } }}
                        >
                          {cmd.type === "Play" || cmd.type === "Fade" || cmd.type === "Stop" || cmd.type === "Pause" ? (
                            <>
                              <input
                                type="text"
                                inputMode="decimal"
                                value={tablePanDraft[idx] !== undefined ? tablePanDraft[idx] : formatDecimal(cmd.type === "Play" ? (cmd as PlayCommand).pan ?? 0 : cmd.type === "Fade" ? (cmd as FadeCommand).pan ?? 0 : cmd.type === "Stop" ? (cmd as StopCommand).pan ?? 0 : (cmd as PauseCommand).pan ?? 0)}
                                onChange={(e) => {
                                  e.stopPropagation();
                                  const value = e.target.value.replace(',', '.');
                                  setTablePanDraft({ ...tablePanDraft, [idx]: value });
                                }}
                                onMouseDown={(e) => {
                                  if (e.altKey || e.ctrlKey || e.metaKey) {
                                    e.preventDefault();
                                    e.stopPropagation();
                                    handleUpdateCommand(idx, { pan: 0 });
                                    const newDraft = { ...tablePanDraft };
                                    delete newDraft[idx];
                                    setTablePanDraft(newDraft);
                                  }
                                }}
                                onKeyDown={(e) => {
                                  if (e.key === 'Enter') {
                                    e.stopPropagation();
                                    const value = tablePanDraft[idx] !== undefined ? tablePanDraft[idx] : e.currentTarget.value;
                                    if (value === "") {
                                      handleUpdateCommand(idx, { pan: undefined });
                                    } else {
                                      const numValue = parseFloat(value.replace(',', '.'));
                                      if (!isNaN(numValue)) {
                                        handleUpdateCommand(idx, { pan: Math.max(-1, Math.min(1, numValue)) });
                                      }
                                    }
                                    const newDraft = { ...tablePanDraft };
                                    delete newDraft[idx];
                                    setTablePanDraft(newDraft);
                                    e.currentTarget.blur();
                                  } else if (e.key === 'Escape') {
                                    e.stopPropagation();
                                    const newDraft = { ...tablePanDraft };
                                    delete newDraft[idx];
                                    setTablePanDraft(newDraft);
                                    e.currentTarget.blur();
                                  }
                                }}
                                onBlur={() => {
                                  const newDraft = { ...tablePanDraft };
                                  delete newDraft[idx];
                                  setTablePanDraft(newDraft);
                                }}
                                onClick={(e) => {
                                  e.stopPropagation();
                                  if (panSliderOpen !== idx) {
                                    setPanSliderOpen(idx);
                                  }
                                }}
                                onFocus={(e) => {
                                  if (panSliderOpen !== idx) {
                                    setTablePanDraft({ ...tablePanDraft, [idx]: e.target.value });
                                  }
                                }}
                                style={{
                                  padding: '6px 10px',
                                  backgroundColor: '#2a2a2a',
                                  color: '#fff',
                                  border: '1px solid #3a3a3a',
                                  borderRadius: '4px',
                                  fontSize: '12px',
                                  width: '65px',
                                  height: '30px',
                                  textAlign: 'center'
                                }}
                              />
                              {panSliderOpen === idx && (
                                <>
                                  <div
                                    style={{
                                      position: 'fixed',
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      zIndex: 999999
                                    }}
                                    onClick={() => setPanSliderOpen(null)}
                                  />
                                  <div
                                    draggable={false}
                                    style={{
                                      position: 'absolute',
                                      top: '50%',
                                      left: '50%',
                                      transform: 'translate(-50%, -50%)',
                                      padding: '12px',
                                      backgroundColor: '#1a1a1a',
                                      border: '1px solid #3a3a3a',
                                      borderRadius: '8px',
                                      boxShadow: '0 4px 12px rgba(0, 0, 0, 0.5)',
                                      zIndex: 1000000,
                                      width: 'calc(100% - 8px)',
                                      maxWidth: '300px',
                                      minWidth: '200px'
                                    }}
                                    onClick={(e) => e.stopPropagation()}
                                    onMouseDown={(e) => e.stopPropagation()}
                                    onMouseUp={(e) => e.stopPropagation()}
                                    onMouseMove={(e) => e.stopPropagation()}
                                    onDragStart={(e) => { e.preventDefault(); e.stopPropagation(); }}
                                    onDrag={(e) => { e.preventDefault(); e.stopPropagation(); }}
                                    onDragEnd={(e) => { e.preventDefault(); e.stopPropagation(); }}
                                  >
                                    <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                        <span style={{ fontSize: '11px', color: '#888', fontWeight: 600 }}>PAN</span>
                                        <span style={{ fontSize: '12px', color: '#fff', fontWeight: 600 }}>{formatDecimal(cmd.type === "Play" ? (cmd as PlayCommand).pan ?? 0 : cmd.type === "Fade" ? (cmd as FadeCommand).pan ?? 0 : cmd.type === "Stop" ? (cmd as StopCommand).pan ?? 0 : (cmd as PauseCommand).pan ?? 0)}</span>
                                      </div>
                                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '10px', color: '#888' }}>
                                        <span>L</span>
                                        <span>C</span>
                                        <span>R</span>
                                      </div>
                                      <input
                                        type="range"
                                        draggable={false}
                                        min="-1"
                                        max="1"
                                        step="0.01"
                                        value={cmd.type === "Play" ? (cmd as PlayCommand).pan ?? 0 : cmd.type === "Fade" ? (cmd as FadeCommand).pan ?? 0 : cmd.type === "Stop" ? (cmd as StopCommand).pan ?? 0 : (cmd as PauseCommand).pan ?? 0}
                                        autoFocus
                                        onMouseDown={(e) => {
                                          e.stopPropagation();
                                          if (e.altKey || e.ctrlKey || e.metaKey) {
                                            e.preventDefault();
                                            handleUpdateCommand(idx, { pan: 0 });
                                            const soundId = (cmd as PlayCommand).soundId;
                                            const audioObjects = soundAudioMap.current.get(soundId);
                                            if (audioObjects) {
                                              audioObjects.forEach(obj => {
                                                if (obj.panNode) {
                                                  obj.panNode.pan.value = 0;
                                                }
                                              });
                                            }
                                            setDraftPan(null);
                                          }
                                        }}
                                        onMouseUp={(e) => e.stopPropagation()}
                                        onMouseMove={(e) => e.stopPropagation()}
                                        onClick={(e) => e.stopPropagation()}
                                        onDragStart={(e) => { e.preventDefault(); e.stopPropagation(); }}
                                        onDrag={(e) => { e.preventDefault(); e.stopPropagation(); }}
                                        onChange={(e) => {
                                          e.stopPropagation();
                                          const newPan = parseFloat(e.currentTarget.value);
                                          handleUpdateCommand(idx, { pan: newPan });

                                          const soundId = (cmd as PlayCommand).soundId;
                                          const audioObjects = soundAudioMap.current.get(soundId);
                                          if (audioObjects) {
                                            audioObjects.forEach(obj => {
                                              if (obj.panNode) {
                                                obj.panNode.pan.value = newPan;
                                              }
                                            });
                                          }
                                        }}
                                        onKeyDown={(e) => {
                                          e.stopPropagation();
                                          if (e.key === 'Enter' || e.key === 'Escape') {
                                            setPanSliderOpen(null);
                                          }
                                        }}
                                        onBlur={() => {
                                          setPanSliderOpen(null);
                                        }}
                                        style={{ width: '100%' }}
                                      />
                                    </div>
                                  </div>
                                </>
                              )}
                            </>
                          ) : (
                            <span>—</span>
                          )}
                        </td>
                        <td>
                          {(cmd.type === "Fade" || cmd.type === "Stop" || cmd.type === "Pause" || cmd.type === "Execute") ? (
                            <input
                              type="text"
                              inputMode="numeric"
                              value={cmd.type === "Fade" ? (cmd as FadeCommand).duration ?? "" : cmd.type === "Execute" ? (cmd as ExecuteCommand).fadeDuration ?? "" : (cmd as StopCommand | PauseCommand).fadeOut ?? ""}
                              placeholder="0"
                              onChange={(e) => {
                                e.stopPropagation();
                                handleUpdateCommand(idx, cmd.type === "Fade" ? { duration: e.target.value === "" ? undefined : parseInt(e.target.value) || 0 } : cmd.type === "Execute" ? { fadeDuration: e.target.value === "" ? undefined : parseInt(e.target.value) || 0 } : { fadeOut: e.target.value === "" ? undefined : parseInt(e.target.value) || 0 });
                              }}
                              onMouseDown={(e) => {
                                if (e.altKey || e.ctrlKey || e.metaKey) {
                                  e.preventDefault();
                                  e.stopPropagation();
                                  handleUpdateCommand(idx, cmd.type === "Fade" ? { duration: 0 } : cmd.type === "Execute" ? { fadeDuration: 0 } : { fadeOut: 0 });
                                }
                              }}
                              onClick={(e) => e.stopPropagation()}
                              onFocus={(e) => e.target.select()}
                              onKeyDown={(e) => {
                                if (e.key === 'Enter') {
                                  e.currentTarget.blur();
                                }
                              }}
                              style={{
                                padding: '6px 10px',
                                backgroundColor: '#2a2a2a',
                                color: (cmd.type === "Fade" ? (cmd as FadeCommand).duration : cmd.type === "Execute" ? (cmd as ExecuteCommand).fadeDuration : cmd.type === "Stop" ? (cmd as StopCommand).fadeOut : (cmd as PauseCommand).fadeOut) === 0 ? '#666' : '#fff',
                                border: '1px solid #3a3a3a',
                                borderRadius: '4px',
                                fontSize: '12px',
                                width: '65px',
                                height: '30px',
                                textAlign: 'center'
                              }}
                            />
                          ) : (
                            <span>—</span>
                          )}
                        </td>
                        <td>
                          {(cmd.type === "Play" || cmd.type === "Stop" || cmd.type === "Fade" || cmd.type === "Pause" || cmd.type === "Execute") ? (
                            <input
                              type="text"
                              inputMode="numeric"
                              value={(cmd as PlayCommand | StopCommand | FadeCommand | PauseCommand | ExecuteCommand).delay ?? ""}
                              placeholder="0"
                              onChange={(e) => {
                                e.stopPropagation();
                                handleUpdateCommand(idx, { delay: e.target.value === "" ? undefined : parseInt(e.target.value) || 0 });
                              }}
                              onMouseDown={(e) => {
                                if (e.altKey || e.ctrlKey || e.metaKey) {
                                  e.preventDefault();
                                  e.stopPropagation();
                                  handleUpdateCommand(idx, { delay: 0 });
                                }
                              }}
                              onClick={(e) => e.stopPropagation()}
                              onFocus={(e) => e.target.select()}
                              onKeyDown={(e) => {
                                if (e.key === 'Enter') {
                                  e.currentTarget.blur();
                                }
                              }}
                              style={{
                                padding: '6px 10px',
                                backgroundColor: '#2a2a2a',
                                color: (cmd as PlayCommand | StopCommand | FadeCommand | PauseCommand).delay === 0 ? '#666' : '#fff',
                                border: '1px solid #3a3a3a',
                                borderRadius: '4px',
                                fontSize: '12px',
                                width: '65px',
                                height: '30px',
                                textAlign: 'center'
                              }}
                            />
                          ) : (
                            <span>—</span>
                          )}
                        </td>
                        <td>
                          {cmd.type === "Play" ? (
                            <div style={{ display: 'flex', flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: '8px' }}>
                              <input
                                type="checkbox"
                                checked={(cmd as PlayCommand).loop || false}
                                onChange={(e) => {
                                  e.stopPropagation();
                                  const newLoopValue = e.target.checked;
                                  handleUpdateCommand(idx, { loop: newLoopValue });

                                  const soundId = (cmd as PlayCommand).soundId;
                                  if (soundId) {
                                    const audioObjects = soundAudioMap.current.get(soundId);
                                    if (audioObjects) {
                                      audioObjects.forEach(obj => {
                                        if (obj.source) {
                                          obj.source.loop = newLoopValue;
                                        }
                                      });
                                    }
                                  }
                                }}
                                onClick={(e) => e.stopPropagation()}
                                style={{
                                  width: '18px',
                                  height: '18px',
                                  cursor: 'pointer'
                                }}
                              />
                              <input
                                type="text"
                                inputMode="numeric"
                                disabled={(cmd as PlayCommand).loop || false}
                                value={(cmd as PlayCommand).loopCount || ''}
                                onChange={(e) => {
                                  e.stopPropagation();
                                  const value = e.target.value;
                                  if (value === '') {
                                    handleUpdateCommand(idx, { loopCount: undefined });
                                  } else {
                                    const numValue = parseInt(value);
                                    if (!isNaN(numValue) && numValue >= 1) {
                                      handleUpdateCommand(idx, { loopCount: numValue });
                                    }
                                  }
                                }}
                                onClick={(e) => e.stopPropagation()}
                                onFocus={(e) => e.target.select()}
                                placeholder="1"
                                style={{
                                  padding: '6px 10px',
                                  backgroundColor: (cmd as PlayCommand).loop ? '#1a1a1a' : '#2a2a2a',
                                  color: (cmd as PlayCommand).loop ? '#666' : '#fff',
                                  border: '1px solid #3a3a3a',
                                  borderRadius: '4px',
                                  fontSize: '12px',
                                  width: '65px',
                                  height: '30px',
                                  textAlign: 'center',
                                  cursor: (cmd as PlayCommand).loop ? 'not-allowed' : 'text',
                                  opacity: (cmd as PlayCommand).loop ? 0.5 : 1
                                }}
                              />
                            </div>
                          ) : (
                            <span>—</span>
                          )}
                        </td>
                        <td>
                          {cmd.type === "Play" ? (
                            <div style={{ display: 'flex', flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: '8px' }}>
                              <input
                                type="checkbox"
                                checked={(cmd as PlayCommand).overlap || false}
                                onChange={(e) => {
                                  e.stopPropagation();
                                  handleUpdateCommand(idx, {
                                    overlap: e.target.checked
                                  });
                                }}
                                onClick={(e) => e.stopPropagation()}
                                style={{
                                  width: '18px',
                                  height: '18px',
                                  cursor: 'pointer'
                                }}
                              />
                            </div>
                          ) : (
                            <span>—</span>
                          )}
                        </td>
                        <td>
                          <div className="action-buttons">
                            <button
                              className="btn-play"
                              onClick={(e) => {
                                e.stopPropagation();
                                const soundId = (cmd as PlayCommand).soundId;
                                if (!soundId) return;

                                if (currentPlayingSound === soundId && isPlaying) {
                                  // Pause
                                  if (audioRef.current) {
                                    audioRef.current.pause();
                                    setIsPlaying(false);
                                  } else if (audioSourceRef.current && audioContextRef.current) {
                                    audioContextRef.current.suspend();
                                    setIsPlaying(false);
                                  }
                                } else if (currentPlayingSound === soundId && !isPlaying) {
                                  // Resume
                                  if (audioRef.current) {
                                    audioRef.current.play().then(() => {
                                      setIsPlaying(true);
                                    }).catch((err) => {
                                      console.error("Failed to resume audio:", err);
                                    });
                                  } else if (audioContextRef.current) {
                                    audioContextRef.current.resume().then(() => {
                                      setIsPlaying(true);
                                    }).catch((err) => {
                                      console.error("Failed to resume audio context:", err);
                                    });
                                  }
                                } else {
                                  // Play from start
                                  const volume = (cmd as PlayCommand).volume ?? 1;
                                  const loop = (cmd as PlayCommand).loop ?? false;
                                  const sprite = project?.spriteItems.find(s => s.soundId === soundId);
                                  const bus = (sprite?.bus as BusId) ?? 'sfx';
                                  audioEngine.playSound(soundId, volume, loop, currentPlayingSound, isPlaying, bus);
                                }
                              }}
                              disabled={playingEvents.size > 0}
                              title={currentPlayingSound === (cmd as PlayCommand).soundId && isPlaying ? "Pause" : "Play"}
                              style={{
                                padding: '2px 6px',
                                backgroundColor: currentPlayingSound === (cmd as PlayCommand).soundId && isPlaying ? '#f59e0b' : playingEvents.size > 0 ? '#2a2a2a' : '#16a34a',
                                color: playingEvents.size > 0 ? '#6d6d6d' : '#fff',
                                border: 'none',
                                borderRadius: '3px',
                                cursor: playingEvents.size > 0 ? 'not-allowed' : 'pointer',
                                fontWeight: 600,
                                fontSize: '10px',
                                marginRight: '2px',
                                minWidth: '24px',
                                height: '24px',
                                display: 'inline-flex',
                                alignItems: 'center',
                                justifyContent: 'center'
                              }}
                            >
                              {currentPlayingSound === (cmd as PlayCommand).soundId && isPlaying ? '⏸' : '▶'}
                            </button>
                            <button
                              className="btn-stop"
                              onClick={(e) => {
                                e.stopPropagation();
                                if (audioRef.current) {
                                  audioRef.current.pause();
                                  audioRef.current.currentTime = 0;
                                  audioRef.current = null;
                                }
                                if (audioSourceRef.current) {
                                  try {
                                    audioSourceRef.current.stop();
                                  } catch (err) {
                                    // Ignore if already stopped
                                  }
                                  audioSourceRef.current = null;
                                }
                                setIsPlaying(false);
                                setCurrentPlayingSound("");
                              }}
                              title="Stop"
                              style={{
                                padding: '2px 6px',
                                backgroundColor: '#dc2626',
                                color: '#fff',
                                border: 'none',
                                borderRadius: '3px',
                                cursor: 'pointer',
                                fontWeight: 600,
                                fontSize: '10px',
                                marginRight: '2px',
                                minWidth: '24px',
                                height: '24px',
                                display: 'inline-flex',
                                alignItems: 'center',
                                justifyContent: 'center'
                              }}
                            >
                              ■
                            </button>
                            <button
                              className="btn-icon-duplicate"
                              onClick={(e) => {
                                e.stopPropagation();
                                handleDuplicateCommand(idx);
                              }}
                              title="Duplicate"
                            >
                              ⧉
                            </button>
                            <button
                              className="btn-icon-delete"
                              onClick={(e) => {
                                e.stopPropagation();
                                handleDeleteCommand(idx);
                              }}
                              title="Delete"
                            >
                              ✕
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            ) : (
              <div className="empty-commands">
                <p>No commands yet.</p>
              </div>
            )}
          </div>
        </div>
        )}

        {viewMode === 'events' && !isInspectorDetached && (
          <button
            className={`inspector-toggle-btn ${inspectorAnimationClass}`}
            onClick={() => {
              setIsInspectorOpen(!isInspectorOpen);
            }}
            style={{
              position: 'fixed',
              right: isInspectorOpen ? '350px' : '0',
              bottom: '80px',
              padding: '8px 6px',
              backgroundColor: isInspectorOpen ? '#4a7afe' : '#2a2a2a',
              color: '#fff',
              border: '1px solid #3a3a3a',
              borderRight: 'none',
              borderTopLeftRadius: '6px',
              borderBottomLeftRadius: '6px',
              cursor: 'pointer',
              fontSize: '14px',
              fontWeight: 600,
              transition: 'right 0.5s cubic-bezier(0.4, 0, 0.2, 1), background-color 0.15s',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              zIndex: 1001,
              boxShadow: '-2px 0 8px rgba(0, 0, 0, 0.3)',
              writingMode: 'vertical-rl',
              textOrientation: 'mixed',
              letterSpacing: '0.5px'
            }}
            title={isInspectorOpen ? 'Close Inspector' : 'Open Inspector'}
          >
            <span style={{ fontSize: '12px', marginBottom: '3px' }}>{isInspectorOpen ? '▶' : '◀'}</span>
            <span style={{ fontSize: '8px', fontWeight: 700 }}>INSPECTOR</span>
          </button>
        )}

        {viewMode === 'events' && isInspectorDetached && (
          <div
            style={{
              position: 'fixed',
              left: detachedInspectorPosition.x + 'px',
              top: detachedInspectorPosition.y + 'px',
              width: detachedInspectorSize.width + 'px',
              height: detachedInspectorSize.height + 'px',
              backgroundColor: '#1a1a1a',
              border: '1px solid #3a3a3a',
              borderRadius: '8px',
              zIndex: 2000,
              boxShadow: '-4px 0 12px rgba(0, 0, 0, 0.5)',
              display: 'flex',
              flexDirection: 'column',
              overflow: 'hidden',
              cursor: isDraggingInspector ? 'grabbing' : 'default'
            }}
          >
            <div style={{ position: 'relative', zIndex: 1 }}>
              <div
                className="panel-header"
                onMouseDown={handleInspectorMouseDown}
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  cursor: 'grab',
                  userSelect: 'none'
                }}
              >
                <h3>COMMAND INSPECTOR</h3>
                <button
                  onClick={handleDetachInspector}
                  style={{
                    padding: '4px 8px',
                    backgroundColor: '#2a2a2a',
                    color: '#fff',
                    border: '1px solid #3a3a3a',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    fontSize: '12px',
                    fontWeight: 600,
                    transition: 'background-color 0.15s'
                  }}
                  title='Reattach Inspector'
                >
                  📌 Attach
                </button>
              </div>
            </div>

            <div style={{ flex: 1, overflow: 'auto', padding: '16px' }}>
              {selectedCommandIndex !== null && selectedCommand ? (
                <div className="inspector-content">
                  <label>
                    TYPE
                    <select
                      value={selectedCommand.type}
                      onChange={(e) =>
                        selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                          type: e.target.value as CommandType,
                        })
                      }
                    >
                      <option value="Play">Play</option>
                      <option value="Stop">Stop</option>
                      <option value="Fade">Fade</option>
                      <option value="Pause">Pause</option>
                      <option value="Execute">Execute</option>
                    </select>
                  </label>

                  {(selectedCommand.type === "Play" || selectedCommand.type === "Stop" ||
                    selectedCommand.type === "Fade" || selectedCommand.type === "Pause") && (
                    <>
                      <label>
                        SOUND
                        <div style={{ marginTop: '6px' }}>
                          <select
                            value={(selectedCommand as PlayCommand).soundId || ""}
                            onChange={(e) => {
                              if (audioRef.current) {
                                audioRef.current.pause();
                                audioRef.current.currentTime = 0;
                                audioRef.current = null;
                              }
                              if (audioSourceRef.current) {
                                try {
                                  audioSourceRef.current.stop();
                                } catch (err) {
                                  // Ignore if already stopped
                                }
                                audioSourceRef.current = null;
                              }
                              setIsPlaying(false);
                              setCurrentPlayingSound("");

                              selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, { soundId: e.target.value });
                            }}
                          >
                            <option value="">-- Select Sound --</option>
                            {audioFiles
                              .sort((a, b) => a.name.localeCompare(b.name))
                              .map((audioFile) => (
                                <option key={audioFile.id} value={audioFile.name}>
                                  {audioFile.name}
                                </option>
                              ))}
                          </select>
                        </div>
                      </label>
                    </>
                  )}

                  {selectedCommand && selectedCommand.type === "Play" && (
                    <>
                      <label>
                        VOLUME
                        <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                          <input
                            type="text"
                            inputMode="decimal"
                            value={draftVolume !== null ? draftVolume : formatDecimal((selectedCommand as PlayCommand).volume ?? 1)}
                            placeholder="1"
                            onChange={(e) => {
                              const value = e.target.value.replace(',', '.');
                              setDraftVolume(value);
                            }}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { volume: 1 });
                                  setDraftVolume(null);
                                }
                              });
                            }}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter' && selectedCommandIndex !== null) {
                                const value = draftVolume !== null ? draftVolume : e.currentTarget.value;
                                if (value === "") {
                                  handleUpdateCommand(selectedCommandIndex, { volume: undefined });
                                } else {
                                  const numValue = parseFloat(value.replace(',', '.'));
                                  if (!isNaN(numValue)) {
                                    handleUpdateCommand(selectedCommandIndex, { volume: Math.max(0, Math.min(1, numValue)) });
                                  }
                                }
                                setDraftVolume(null);
                                e.currentTarget.blur();
                              } else if (e.key === 'Escape') {
                                setDraftVolume(null);
                                e.currentTarget.blur();
                              }
                            }}
                            onBlur={() => {
                              setDraftVolume(null);
                            }}
                            onFocus={(e) => e.target.select()}
                            style={{ width: "60px" }}
                          />
                          <input
                            type="range"
                            step="0.01"
                            min="0"
                            max="100"
                            value={(() => {
                              const vol = (selectedCommand as PlayCommand).volume ?? 1;
                              return vol === 0 ? 0 : Math.log10(vol * 9 + 1) * 100;
                            })()}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { volume: 1 });
                                  if (audioRef.current && currentPlayingSound === (selectedCommand as PlayCommand).soundId) {
                                    audioRef.current.volume = 1;
                                  }
                                  if (gainNodeRef.current && currentPlayingSound === (selectedCommand as PlayCommand).soundId) {
                                    gainNodeRef.current.gain.value = 1;
                                  }
                                }
                              });
                            }}
                            onChange={(e) => {
                              const sliderValue = parseFloat(e.target.value);
                              const rawVolume = sliderValue === 0 ? 0 : (Math.pow(10, sliderValue / 100) - 1) / 9;
                              const newVolume = Math.round(rawVolume * 100) / 100;
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, {
                                  volume: newVolume,
                                });

                                if (audioRef.current && currentPlayingSound === (selectedCommand as PlayCommand).soundId) {
                                  audioRef.current.volume = newVolume;
                                }
                                if (gainNodeRef.current && currentPlayingSound === (selectedCommand as PlayCommand).soundId) {
                                  gainNodeRef.current.gain.value = newVolume;
                                }
                              }
                            }}
                            style={{ flex: 1 }}
                          />
                        </div>
                      </label>

                      <label>
                        PAN
                        <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                          <input
                            type="text"
                            inputMode="decimal"
                            value={draftPan !== null ? draftPan : formatDecimal((selectedCommand as PlayCommand).pan ?? 0)}
                            placeholder="0"
                            onChange={(e) => {
                              const value = e.target.value.replace(',', '.');
                              setDraftPan(value);
                            }}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                                  setDraftPan(null);
                                  const soundId = (selectedCommand as PlayCommand).soundId;
                                  const audioObjects = soundAudioMap.current.get(soundId);
                                  if (audioObjects) {
                                    audioObjects.forEach(obj => {
                                      if (obj.panNode) {
                                        obj.panNode.pan.value = 0;
                                      }
                                    });
                                  }
                                }
                              });
                            }}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter' && selectedCommandIndex !== null) {
                                const value = draftPan !== null ? draftPan : e.currentTarget.value;
                                if (value === "") {
                                  handleUpdateCommand(selectedCommandIndex, { pan: undefined });
                                } else {
                                  const numValue = parseFloat(value.replace(',', '.'));
                                  if (!isNaN(numValue)) {
                                    const clampedPan = Math.max(-1, Math.min(1, numValue));
                                    handleUpdateCommand(selectedCommandIndex, { pan: clampedPan });
                                    const soundId = (selectedCommand as PlayCommand).soundId;
                                    const audioObjects = soundAudioMap.current.get(soundId);
                                    if (audioObjects) {
                                      audioObjects.forEach(obj => {
                                        if (obj.panNode) {
                                          obj.panNode.pan.value = clampedPan;
                                        }
                                      });
                                    }
                                  }
                                }
                                setDraftPan(null);
                                e.currentTarget.blur();
                              } else if (e.key === 'Escape') {
                                setDraftPan(null);
                                e.currentTarget.blur();
                              }
                            }}
                            onBlur={() => {
                              setDraftPan(null);
                            }}
                            onFocus={(e) => e.target.select()}
                            style={{ width: "60px" }}
                          />
                          <input
                            type="range"
                            step="0.01"
                            min="-1"
                            max="1"
                            value={(() => { const pan = (selectedCommand as PlayCommand).pan ?? 0; return Math.max(-1, Math.min(1, pan)); })()}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                                  const soundId = (selectedCommand as PlayCommand).soundId;
                                  const audioObjects = soundAudioMap.current.get(soundId);
                                  if (audioObjects) {
                                    audioObjects.forEach(obj => {
                                      if (obj.panNode) {
                                        obj.panNode.pan.value = 0;
                                      }
                                    });
                                  }
                                }
                              });
                            }}
                            onChange={(e) => {
                              const newPan = Math.max(-1, Math.min(1, parseFloat(e.target.value)));
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, {
                                  pan: newPan,
                                });

                                const soundId = (selectedCommand as PlayCommand).soundId;
                                const audioObjects = soundAudioMap.current.get(soundId);
                                if (audioObjects) {
                                  audioObjects.forEach(obj => {
                                    if (obj.panNode) {
                                      obj.panNode.pan.value = newPan;
                                    }
                                  });
                                }
                              }
                            }}
                            style={{ flex: 1 }}
                          />
                        </div>
                      </label>

                      <label className="checkbox-label">
                        <input
                          type="checkbox"
                          checked={!!(selectedCommand as PlayCommand).loop}
                          onChange={(e) => {
                            if (selectedCommandIndex !== null) {
                              const newLoopValue = e.target.checked;
                              handleUpdateCommand(selectedCommandIndex, { loop: newLoopValue });

                              const soundId = (selectedCommand as PlayCommand).soundId;
                              if (soundId) {
                                const audioObjects = soundAudioMap.current.get(soundId);
                                if (audioObjects) {
                                  audioObjects.forEach(obj => {
                                    if (obj.source) {
                                      obj.source.loop = newLoopValue;
                                    }
                                  });
                                }
                              }
                            }
                          }}
                        />
                        LOOP INFINITELY
                      </label>

                      {!(selectedCommand as PlayCommand).loop && (
                        <label>
                          REPEAT COUNT
                          <input
                            type="number"
                            min="1"
                            max="999"
                            value={(selectedCommand as PlayCommand).loopCount ?? ""}
                            placeholder="1"
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { loopCount: 1 });
                                }
                              });
                            }}
                            onChange={(e) =>
                              selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                                loopCount: e.target.value === "" ? undefined : parseInt(e.target.value) || 1,
                              })
                            }
                            onKeyDown={(e) => {
                              if (e.key === 'Enter') {
                                e.currentTarget.blur();
                              }
                            }}
                            onFocus={(e) => e.target.select()}
                          />
                        </label>
                      )}

                      <label className="checkbox-label">
                        <input
                          type="checkbox"
                          checked={!!(selectedCommand as PlayCommand).overlap}
                          onChange={(e) =>
                            selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, { overlap: e.target.checked })
                          }
                        />
                        OVERLAP
                      </label>

                      <label>
                        DELAY (MS)
                        <input
                          type="text"
                          inputMode="numeric"
                          value={(selectedCommand as PlayCommand).delay ?? ""}
                          placeholder="0"
                          onMouseDown={(e) => {
                            handleResetOnModifierClick(e, () => {
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, { delay: 0 });
                              }
                            });
                          }}
                          onChange={(e) =>
                            selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                              delay: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                            })
                          }
                          onFocus={(e) => e.target.select()}
                        />
                      </label>
                    </>
                  )}

                  {selectedCommand && selectedCommand.type === "Stop" && (
                    <>
                      <label>
                        VOLUME
                        <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                          <input
                            type="text"
                            inputMode="decimal"
                            value={draftVolume !== null ? draftVolume : formatDecimal((selectedCommand as StopCommand).volume ?? 1)}
                            placeholder="1"
                            onChange={(e) => {
                              const value = e.target.value.replace(',', '.');
                              setDraftVolume(value);
                            }}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { volume: 1 });
                                  setDraftVolume(null);
                                }
                              });
                            }}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter' && selectedCommandIndex !== null) {
                                const value = draftVolume !== null ? draftVolume : e.currentTarget.value;
                                if (value === "") {
                                  handleUpdateCommand(selectedCommandIndex, { volume: undefined });
                                } else {
                                  const numValue = parseFloat(value.replace(',', '.'));
                                  if (!isNaN(numValue)) {
                                    handleUpdateCommand(selectedCommandIndex, { volume: Math.max(0, Math.min(1, numValue)) });
                                  }
                                }
                                setDraftVolume(null);
                                e.currentTarget.blur();
                              } else if (e.key === 'Escape') {
                                setDraftVolume(null);
                                e.currentTarget.blur();
                              }
                            }}
                            onBlur={() => {
                              setDraftVolume(null);
                            }}
                            onFocus={(e) => e.target.select()}
                            style={{ width: "60px" }}
                          />
                          <input
                            type="range"
                            step="0.01"
                            min="0"
                            max="100"
                            value={(() => {
                              const vol = (selectedCommand as StopCommand).volume ?? 1;
                              return vol === 0 ? 0 : Math.log10(vol * 9 + 1) * 100;
                            })()}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { volume: 1 });
                                }
                              });
                            }}
                            onChange={(e) => {
                              const sliderValue = parseFloat(e.target.value);
                              const rawVolume = sliderValue === 0 ? 0 : (Math.pow(10, sliderValue / 100) - 1) / 9;
                              const newVolume = Math.round(rawVolume * 100) / 100;
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, {
                                  volume: newVolume,
                                });
                              }
                            }}
                            style={{ flex: 1 }}
                          />
                        </div>
                      </label>

                      <label>
                        PAN
                        <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                          <input
                            type="text"
                            inputMode="decimal"
                            value={draftPan !== null ? draftPan : formatDecimal((selectedCommand as StopCommand).pan ?? 0)}
                            placeholder="0"
                            onChange={(e) => {
                              const value = e.target.value.replace(',', '.');
                              setDraftPan(value);
                            }}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                                  setDraftPan(null);
                                  const soundId = (selectedCommand as StopCommand).soundId;
                                  const audioObjects = soundAudioMap.current.get(soundId);
                                  if (audioObjects) {
                                    audioObjects.forEach(obj => {
                                      if (obj.panNode) {
                                        obj.panNode.pan.value = 0;
                                      }
                                    });
                                  }
                                }
                              });
                            }}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter' && selectedCommandIndex !== null) {
                                const value = draftPan !== null ? draftPan : e.currentTarget.value;
                                if (value === "") {
                                  handleUpdateCommand(selectedCommandIndex, { pan: undefined });
                                } else {
                                  const numValue = parseFloat(value.replace(',', '.'));
                                  if (!isNaN(numValue)) {
                                    const clampedPan = Math.max(-1, Math.min(1, numValue));
                                    handleUpdateCommand(selectedCommandIndex, { pan: clampedPan });
                                  }
                                }
                                setDraftPan(null);
                                e.currentTarget.blur();
                              } else if (e.key === 'Escape') {
                                setDraftPan(null);
                                e.currentTarget.blur();
                              }
                            }}
                            onBlur={() => {
                              setDraftPan(null);
                            }}
                            onFocus={(e) => e.target.select()}
                            style={{ width: "60px" }}
                          />
                          <input
                            type="range"
                            step="0.01"
                            min="-1"
                            max="1"
                            value={(() => {
                              const pan = (selectedCommand as StopCommand).pan ?? 0;
                              return Math.max(-1, Math.min(1, pan));
                            })()}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                                  const soundId = (selectedCommand as StopCommand).soundId;
                                  const audioObjects = soundAudioMap.current.get(soundId);
                                  if (audioObjects) {
                                    audioObjects.forEach(obj => {
                                      if (obj.panNode) {
                                        obj.panNode.pan.value = 0;
                                      }
                                    });
                                  }
                                }
                              });
                            }}
                            onChange={(e) => {
                              const newPan = parseFloat(e.target.value);
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, {
                                  pan: Math.max(-1, Math.min(1, newPan)),
                                });

                                const soundId = (selectedCommand as StopCommand).soundId;
                                const audioObjects = soundAudioMap.current.get(soundId);
                                if (audioObjects) {
                                  audioObjects.forEach(obj => {
                                    if (obj.panNode) {
                                      obj.panNode.pan.value = newPan;
                                    }
                                  });
                                }
                              }
                            }}
                            style={{ flex: 1 }}
                          />
                        </div>
                      </label>

                      <label>
                        FADE DURATION (MS)
                        <input
                          type="text"
                          inputMode="numeric"
                          value={(selectedCommand as StopCommand).fadeOut ?? ""}
                          placeholder="0"
                          onMouseDown={(e) => {
                            handleResetOnModifierClick(e, () => {
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, { fadeOut: 0 });
                              }
                            });
                          }}
                          onChange={(e) =>
                            selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                              fadeOut: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                            })
                          }
                          onFocus={(e) => e.target.select()}
                        />
                      </label>
                      <label>
                        DELAY (MS)
                        <input
                          type="text"
                          inputMode="numeric"
                          value={(selectedCommand as StopCommand).delay ?? ""}
                          placeholder="0"
                          onMouseDown={(e) => {
                            handleResetOnModifierClick(e, () => {
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, { delay: 0 });
                              }
                            });
                          }}
                          onChange={(e) =>
                            selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                              delay: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                            })
                          }
                          onFocus={(e) => e.target.select()}
                        />
                      </label>
                    </>
                  )}

                  {selectedCommand && selectedCommand.type === "Pause" && (
                    <>
                      <label>
                        VOLUME
                        <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                          <input
                            type="text"
                            inputMode="decimal"
                            value={draftVolume !== null ? draftVolume : formatDecimal((selectedCommand as PauseCommand).volume ?? 0)}
                            placeholder="0"
                            onChange={(e) => {
                              const value = e.target.value.replace(',', '.');
                              setDraftVolume(value);
                            }}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { volume: 0 });
                                  setDraftVolume(null);
                                }
                              });
                            }}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter' && selectedCommandIndex !== null) {
                                const value = draftVolume !== null ? draftVolume : e.currentTarget.value;
                                if (value === "") {
                                  handleUpdateCommand(selectedCommandIndex, { volume: 0 });
                                } else {
                                  const numValue = parseFloat(value.replace(',', '.'));
                                  if (!isNaN(numValue)) {
                                    handleUpdateCommand(selectedCommandIndex, { volume: Math.max(0, Math.min(1, numValue)) });
                                  }
                                }
                                setDraftVolume(null);
                                e.currentTarget.blur();
                              } else if (e.key === 'Escape') {
                                setDraftVolume(null);
                                e.currentTarget.blur();
                              }
                            }}
                            onBlur={() => {
                              setDraftVolume(null);
                            }}
                            onFocus={(e) => e.target.select()}
                            style={{ width: "60px" }}
                          />
                          <input
                            type="range"
                            step="0.01"
                            min="0"
                            max="100"
                            value={(() => {
                              const vol = (selectedCommand as PauseCommand).volume ?? 0;
                              return vol === 0 ? 0 : Math.log10(vol * 9 + 1) * 100;
                            })()}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { volume: 0 });
                                }
                              });
                            }}
                            onChange={(e) => {
                              const sliderValue = parseFloat(e.target.value);
                              const rawVolume = sliderValue === 0 ? 0 : (Math.pow(10, sliderValue / 100) - 1) / 9;
                              const newVolume = Math.round(rawVolume * 100) / 100;
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, {
                                  volume: newVolume,
                                });
                              }
                            }}
                            style={{ flex: 1 }}
                          />
                        </div>
                      </label>

                      <label>
                        PAN
                        <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                          <input
                            type="text"
                            inputMode="decimal"
                            value={draftPan !== null ? draftPan : formatDecimal((selectedCommand as PauseCommand).pan ?? 0)}
                            placeholder="0"
                            onChange={(e) => {
                              const value = e.target.value.replace(',', '.');
                              setDraftPan(value);
                            }}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                                  setDraftPan(null);
                                  const soundId = (selectedCommand as PauseCommand).soundId;
                                  const audioObjects = soundAudioMap.current.get(soundId);
                                  if (audioObjects) {
                                    audioObjects.forEach(obj => {
                                      if (obj.panNode) {
                                        obj.panNode.pan.value = 0;
                                      }
                                    });
                                  }
                                }
                              });
                            }}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter' && selectedCommandIndex !== null) {
                                const value = draftPan !== null ? draftPan : e.currentTarget.value;
                                if (value === "") {
                                  handleUpdateCommand(selectedCommandIndex, { pan: undefined });
                                } else {
                                  const numValue = parseFloat(value.replace(',', '.'));
                                  if (!isNaN(numValue)) {
                                    const clampedPan = Math.max(-1, Math.min(1, numValue));
                                    handleUpdateCommand(selectedCommandIndex, { pan: clampedPan });
                                  }
                                }
                                setDraftPan(null);
                                e.currentTarget.blur();
                              } else if (e.key === 'Escape') {
                                setDraftPan(null);
                                e.currentTarget.blur();
                              }
                            }}
                            onBlur={() => {
                              setDraftPan(null);
                            }}
                            onFocus={(e) => e.target.select()}
                            style={{ width: "60px" }}
                          />
                          <input
                            type="range"
                            step="0.01"
                            min="-1"
                            max="1"
                            value={(() => {
                              const pan = (selectedCommand as PauseCommand).pan ?? 0;
                              return Math.max(-1, Math.min(1, pan));
                            })()}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                                  const soundId = (selectedCommand as PauseCommand).soundId;
                                  const audioObjects = soundAudioMap.current.get(soundId);
                                  if (audioObjects) {
                                    audioObjects.forEach(obj => {
                                      if (obj.panNode) {
                                        obj.panNode.pan.value = 0;
                                      }
                                    });
                                  }
                                }
                              });
                            }}
                            onChange={(e) => {
                              const newPan = parseFloat(e.target.value);
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, {
                                  pan: Math.max(-1, Math.min(1, newPan)),
                                });

                                const soundId = (selectedCommand as PauseCommand).soundId;
                                const audioObjects = soundAudioMap.current.get(soundId);
                                if (audioObjects) {
                                  audioObjects.forEach(obj => {
                                    if (obj.panNode) {
                                      obj.panNode.pan.value = newPan;
                                    }
                                  });
                                }
                              }
                            }}
                            style={{ flex: 1 }}
                          />
                        </div>
                      </label>

                      <label>
                        FADE DURATION (MS)
                        <input
                          type="text"
                          inputMode="numeric"
                          value={(selectedCommand as PauseCommand).fadeOut ?? ""}
                          placeholder="0"
                          onMouseDown={(e) => {
                            handleResetOnModifierClick(e, () => {
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, { fadeOut: 0 });
                              }
                            });
                          }}
                          onChange={(e) =>
                            selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                              fadeOut: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                            })
                          }
                          onFocus={(e) => e.target.select()}
                        />
                      </label>

                      <label>
                        DELAY (MS)
                        <input
                          type="text"
                          inputMode="numeric"
                          value={(selectedCommand as PauseCommand).delay ?? ""}
                          placeholder="0"
                          onMouseDown={(e) => {
                            handleResetOnModifierClick(e, () => {
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, { delay: 0 });
                              }
                            });
                          }}
                          onChange={(e) =>
                            selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                              delay: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                            })
                          }
                          onFocus={(e) => e.target.select()}
                        />
                      </label>
                    </>
                  )}

                  {selectedCommand && selectedCommand.type === "Fade" && (
                    <>
                      <label>
                        TARGET VOLUME
                        <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                          <input
                            type="text"
                            inputMode="decimal"
                            value={draftVolume !== null ? draftVolume : formatDecimal((selectedCommand as FadeCommand).targetVolume ?? 0)}
                            placeholder="0"
                            onChange={(e) => {
                              const value = e.target.value.replace(',', '.');
                              setDraftVolume(value);
                            }}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { targetVolume: 0 });
                                  setDraftVolume(null);
                                }
                              });
                            }}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter' && selectedCommandIndex !== null) {
                                const value = draftVolume !== null ? draftVolume : e.currentTarget.value;
                                if (value === "") {
                                  handleUpdateCommand(selectedCommandIndex, { targetVolume: 0 });
                                } else {
                                  const numValue = parseFloat(value.replace(',', '.'));
                                  if (!isNaN(numValue)) {
                                    handleUpdateCommand(selectedCommandIndex, { targetVolume: Math.max(0, Math.min(1, numValue)) });
                                  }
                                }
                                setDraftVolume(null);
                                e.currentTarget.blur();
                              } else if (e.key === 'Escape') {
                                setDraftVolume(null);
                                e.currentTarget.blur();
                              }
                            }}
                            onBlur={() => {
                              setDraftVolume(null);
                            }}
                            onFocus={(e) => e.target.select()}
                            style={{ width: "60px" }}
                          />
                          <input
                            type="range"
                            step="0.01"
                            min="0"
                            max="100"
                            value={(() => {
                              const vol = (selectedCommand as FadeCommand).targetVolume ?? 0;
                              return vol === 0 ? 0 : Math.log10(vol * 9 + 1) * 100;
                            })()}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { targetVolume: 0 });
                                }
                              });
                            }}
                            onChange={(e) => {
                              const sliderValue = parseFloat(e.target.value);
                              const rawVolume = sliderValue === 0 ? 0 : (Math.pow(10, sliderValue / 100) - 1) / 9;
                              const newVolume = Math.round(rawVolume * 100) / 100;
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, {
                                  targetVolume: newVolume,
                                });
                              }
                            }}
                            style={{ flex: 1 }}
                          />
                        </div>
                      </label>

                      <label>
                        PAN
                        <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                          <input
                            type="text"
                            inputMode="decimal"
                            value={draftPan !== null ? draftPan : formatDecimal((selectedCommand as FadeCommand).pan ?? 0)}
                            placeholder="0"
                            onChange={(e) => {
                              const value = e.target.value.replace(',', '.');
                              setDraftPan(value);
                            }}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                                  setDraftPan(null);
                                  const soundId = (selectedCommand as FadeCommand).soundId;
                                  const audioObjects = soundAudioMap.current.get(soundId);
                                  if (audioObjects) {
                                    audioObjects.forEach(obj => {
                                      if (obj.panNode) {
                                        obj.panNode.pan.value = 0;
                                      }
                                    });
                                  }
                                }
                              });
                            }}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter' && selectedCommandIndex !== null) {
                                const value = draftPan !== null ? draftPan : e.currentTarget.value;
                                if (value === "") {
                                  handleUpdateCommand(selectedCommandIndex, { pan: undefined });
                                } else {
                                  const numValue = parseFloat(value.replace(',', '.'));
                                  if (!isNaN(numValue)) {
                                    const clampedPan = Math.max(-1, Math.min(1, numValue));
                                    handleUpdateCommand(selectedCommandIndex, { pan: clampedPan });
                                  }
                                }
                                setDraftPan(null);
                                e.currentTarget.blur();
                              } else if (e.key === 'Escape') {
                                setDraftPan(null);
                                e.currentTarget.blur();
                              }
                            }}
                            onBlur={() => {
                              setDraftPan(null);
                            }}
                            onFocus={(e) => e.target.select()}
                            style={{ width: "60px" }}
                          />
                          <input
                            type="range"
                            step="0.01"
                            min="-1"
                            max="1"
                            value={(() => { const pan = (selectedCommand as FadeCommand).pan ?? 0; return Math.max(-1, Math.min(1, pan)); })()}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                                  const soundId = (selectedCommand as FadeCommand).soundId;
                                  const audioObjects = soundAudioMap.current.get(soundId);
                                  if (audioObjects) {
                                    audioObjects.forEach(obj => {
                                      if (obj.panNode) {
                                        obj.panNode.pan.value = 0;
                                      }
                                    });
                                  }
                                }
                              });
                            }}
                            onChange={(e) => {
                              const newPan = parseFloat(e.target.value);
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, {
                                  pan: Math.max(-1, Math.min(1, newPan)),
                                });

                                const soundId = (selectedCommand as FadeCommand).soundId;
                                const audioObjects = soundAudioMap.current.get(soundId);
                                if (audioObjects) {
                                  audioObjects.forEach(obj => {
                                    if (obj.panNode) {
                                      obj.panNode.pan.value = newPan;
                                    }
                                  });
                                }
                              }
                            }}
                            style={{ flex: 1 }}
                          />
                        </div>
                      </label>

                      <label>
                        FADE DURATION (MS)
                        <input
                          type="text"
                          inputMode="numeric"
                          value={(selectedCommand as FadeCommand).duration ?? ""}
                          placeholder="0"
                          onMouseDown={(e) => {
                            handleResetOnModifierClick(e, () => {
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, { duration: 0 });
                              }
                            });
                          }}
                          onChange={(e) =>
                            selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                              duration: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                            })
                          }
                          onFocus={(e) => e.target.select()}
                        />
                      </label>

                      <label>
                        DELAY (MS)
                        <input
                          type="text"
                          inputMode="numeric"
                          value={(selectedCommand as FadeCommand).delay ?? ""}
                          placeholder="0"
                          onMouseDown={(e) => {
                            handleResetOnModifierClick(e, () => {
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, { delay: 0 });
                              }
                            });
                          }}
                          onChange={(e) =>
                            selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                              delay: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                            })
                          }
                          onFocus={(e) => e.target.select()}
                        />
                      </label>
                    </>
                  )}

                  {selectedCommand && selectedCommand.type === "Execute" && (
                    <>
                      <label>
                        EVENT TO EXECUTE
                        <select
                          value={(selectedCommand as ExecuteCommand).eventId || ""}
                          onChange={(e) =>
                            selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, { eventId: e.target.value })
                          }
                        >
                          <option value="">-- Select Event --</option>
                          {project?.events
                            .filter(evt => evt.eventName !== selectedEvent?.eventName) // Don't allow executing itself
                            .map((evt) => (
                              <option key={evt.id} value={evt.eventName}>
                                {evt.eventName}
                              </option>
                            ))}
                        </select>
                      </label>

                      <label>
                        VOLUME
                        <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                          <input
                            type="text"
                            inputMode="decimal"
                            value={(selectedCommand as ExecuteCommand).volume ?? ""}
                            placeholder="1"
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { volume: 1 });
                                }
                              });
                            }}
                            onChange={(e) => {
                              const value = e.target.value.replace(',', '.');
                              if (selectedCommandIndex !== null) {
                                if (value === "") {
                                  handleUpdateCommand(selectedCommandIndex, { volume: undefined });
                                } else {
                                  const numValue = parseFloat(value);
                                  if (!isNaN(numValue)) {
                                    handleUpdateCommand(selectedCommandIndex, { volume: Math.max(0, Math.min(1, numValue)) });
                                  }
                                }
                              }
                            }}
                            onFocus={(e) => e.target.select()}
                            style={{ width: "60px" }}
                          />
                          <input
                            type="range"
                            step="0.01"
                            min="0"
                            max="100"
                            value={(() => {
                              const vol = (selectedCommand as ExecuteCommand).volume ?? 1;
                              return vol === 0 ? 0 : Math.log10(vol * 9 + 1) * 100;
                            })()}
                            onMouseDown={(e) => {
                              handleResetOnModifierClick(e, () => {
                                if (selectedCommandIndex !== null) {
                                  handleUpdateCommand(selectedCommandIndex, { volume: 1 });
                                }
                              });
                            }}
                            onChange={(e) => {
                              const sliderValue = parseFloat(e.target.value);
                              const rawVolume = sliderValue === 0 ? 0 : (Math.pow(10, sliderValue / 100) - 1) / 9;
                              const newVolume = Math.round(rawVolume * 100) / 100;
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, {
                                  volume: newVolume,
                                });
                              }
                            }}
                            style={{ flex: 1 }}
                          />
                        </div>
                      </label>

                      <label>
                        FADE DURATION (MS)
                        <input
                          type="text"
                          inputMode="numeric"
                          value={(selectedCommand as ExecuteCommand).fadeDuration ?? ""}
                          placeholder="0"
                          onMouseDown={(e) => {
                            handleResetOnModifierClick(e, () => {
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, { fadeDuration: 0 });
                              }
                            });
                          }}
                          onChange={(e) =>
                            selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                              fadeDuration: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                            })
                          }
                          onFocus={(e) => e.target.select()}
                        />
                      </label>

                      <label>
                        DELAY (MS)
                        <input
                          type="text"
                          inputMode="numeric"
                          value={(selectedCommand as ExecuteCommand).delay ?? ""}
                          placeholder="0"
                          onMouseDown={(e) => {
                            handleResetOnModifierClick(e, () => {
                              if (selectedCommandIndex !== null) {
                                handleUpdateCommand(selectedCommandIndex, { delay: 0 });
                              }
                            });
                          }}
                          onChange={(e) =>
                            selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                              delay: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                            })
                          }
                          onFocus={(e) => e.target.select()}
                        />
                      </label>
                    </>
                  )}
                </div>
              ) : (
                <div style={{ color: '#666', textAlign: 'center', marginTop: '40px' }}>
                  No command selected
                </div>
              )}
            </div>

            <div
              onMouseDown={handleResizeMouseDown}
              style={{
                position: 'absolute',
                right: 0,
                bottom: 0,
                width: '20px',
                height: '20px',
                cursor: 'nwse-resize',
                zIndex: 10,
                background: 'linear-gradient(135deg, transparent 50%, #3a3a3a 50%)',
                borderBottomRightRadius: '8px'
              }}
              title="Resize"
            />
          </div>
        )}

        {/* Sound Usage Toggle Button - Shows at bottom when in sounds mode */}
        {viewMode === 'sounds' && !isSoundInspectorDetached && (
          <button
            onClick={() => setIsSoundInspectorOpen(!isSoundInspectorOpen)}
            style={{
              position: 'fixed',
              right: isSoundInspectorOpen ? '300px' : '0',
              bottom: '80px',
              padding: '8px 6px',
              backgroundColor: isSoundInspectorOpen ? '#f59e0b' : '#2a2a2a',
              color: '#fff',
              border: '1px solid #3a3a3a',
              borderRight: 'none',
              borderTopLeftRadius: '6px',
              borderBottomLeftRadius: '6px',
              cursor: 'pointer',
              fontSize: '14px',
              fontWeight: 600,
              transition: 'right 0.5s cubic-bezier(0.4, 0, 0.2, 1), background-color 0.15s',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              zIndex: 1001,
              boxShadow: '-2px 0 8px rgba(0, 0, 0, 0.3)',
              writingMode: 'vertical-rl',
              textOrientation: 'mixed',
              letterSpacing: '0.5px'
            }}
            title={isSoundInspectorOpen ? 'Close Sound Usage' : 'Open Sound Usage'}
          >
            <span style={{ fontSize: '12px', marginBottom: '3px' }}>{isSoundInspectorOpen ? '▶' : '◀'}</span>
            <span style={{ fontSize: '8px', fontWeight: 700 }}>SOUND USAGE</span>
          </button>
        )}

        {/* Sound Usage Panel - Fixed position like Inspector */}
        {viewMode === 'sounds' && !isSoundInspectorDetached && (
          <div
            style={{
              position: 'fixed',
              right: isSoundInspectorOpen ? 0 : '-300px',
              top: 0,
              bottom: 0,
              width: '300px',
              backgroundColor: '#1e1e1e',
              borderLeft: '1px solid #3a3a3a',
              zIndex: 1000,
              overflow: 'auto',
              boxShadow: isSoundInspectorOpen ? '-4px 0 12px rgba(0, 0, 0, 0.5)' : 'none',
              transition: 'right 0.5s cubic-bezier(0.4, 0, 0.2, 1)',
              display: 'flex',
              flexDirection: 'column'
            }}
          >
            {/* Panel Header */}
            <div style={{
              padding: '12px 16px',
              borderBottom: '1px solid #333',
              backgroundColor: '#252525',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between'
            }}>
              <span style={{ fontSize: '12px', fontWeight: 600, color: '#fff' }}>SOUND USAGE</span>
              <button
                onClick={() => setIsSoundInspectorDetached(true)}
                style={{
                  padding: '4px 8px',
                  backgroundColor: '#333',
                  color: '#888',
                  border: 'none',
                  borderRadius: '4px',
                  cursor: 'pointer',
                  fontSize: '11px',
                  transition: 'all 0.15s'
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.backgroundColor = '#444';
                  e.currentTarget.style.color = '#fff';
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.backgroundColor = '#333';
                  e.currentTarget.style.color = '#888';
                }}
                title="Detach Panel"
              >
                🔗 Detach
              </button>
            </div>

            {/* Panel Content */}
            {selectedSoundId ? (() => {
              const selectedSound = soundUsages.find(s => s.soundId === selectedSoundId);
              const audioFile = audioFiles.find(af => af.name === selectedSoundId);

              return (
                <div style={{ flex: 1, overflowY: 'auto', padding: '16px' }}>
                  {/* Sound Info */}
                  <div style={{ marginBottom: '20px' }}>
                    <div style={{
                      fontSize: '10px',
                      fontWeight: 600,
                      color: '#888',
                      textTransform: 'uppercase',
                      letterSpacing: '0.5px',
                      marginBottom: '8px'
                    }}>
                      Sound File
                    </div>
                    <div style={{
                      fontSize: '14px',
                      fontWeight: 600,
                      color: '#fff',
                      wordBreak: 'break-word',
                      marginBottom: '8px'
                    }}>
                      {selectedSoundId.replace(/\.[^/.]+$/, '')}
                    </div>
                    <div style={{ display: 'flex', gap: '12px', fontSize: '11px', color: '#666' }}>
                      <span>{audioFile?.duration ? `${Math.round(audioFile.duration * 1000)}ms` : '—'}</span>
                      <span>{audioFile?.size || '—'}</span>
                      <span style={{
                        padding: '2px 6px',
                        backgroundColor: '#333',
                        borderRadius: '4px',
                        fontSize: '9px',
                        fontWeight: 700
                      }}>
                        {selectedSoundId.match(/\.[^/.]+$/)?.[0]?.replace('.', '').toUpperCase() || ''}
                      </span>
                    </div>
                  </div>

                  {/* Waveform Display */}
                  <div style={{ marginBottom: '20px' }}>
                    <div style={{
                      fontSize: '10px',
                      fontWeight: 600,
                      color: '#888',
                      textTransform: 'uppercase',
                      letterSpacing: '0.5px',
                      marginBottom: '8px'
                    }}>
                      Waveform
                    </div>
                    <div style={{
                      backgroundColor: '#1a1a1a',
                      borderRadius: '6px',
                      padding: '8px',
                      border: '1px solid #333'
                    }}>
                      {isLoadingWaveform ? (
                        <div style={{
                          height: '60px',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          color: '#666',
                          fontSize: '11px'
                        }}>
                          Loading waveform...
                        </div>
                      ) : waveformData ? (
                        <WaveformDisplay
                          data={waveformData}
                          width={252}
                          height={60}
                          color="#4a9eff"
                          backgroundColor="#1a1a1a"
                          mode="mirror"
                          showGrid={false}
                        />
                      ) : (
                        <div style={{
                          height: '60px',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          color: '#555',
                          fontSize: '11px'
                        }}>
                          No waveform available
                        </div>
                      )}
                    </div>
                  </div>

                  {/* Used in Events */}
                  <div>
                    <div style={{
                      fontSize: '10px',
                      fontWeight: 600,
                      color: '#888',
                      textTransform: 'uppercase',
                      letterSpacing: '0.5px',
                      marginBottom: '8px',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between'
                    }}>
                      <span>Used in Events</span>
                      {selectedSound && selectedSound.eventNames.length > 0 && (
                        <span style={{
                          padding: '2px 8px',
                          backgroundColor: '#2563eb',
                          borderRadius: '10px',
                          fontSize: '10px',
                          fontWeight: 700,
                          color: '#fff'
                        }}>
                          {selectedSound.eventNames.length}
                        </span>
                      )}
                    </div>

                    {selectedSound && selectedSound.eventNames.length > 0 ? (
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                        {selectedSound.eventNames.map((eventName) => (
                          <div
                            key={eventName}
                            onClick={() => {
                              const event = project?.events.find(ev => ev.eventName === eventName);
                              if (event) {
                                setSelectedEventId(event.id);
                                setViewMode('events');
                                // Scroll to selected event after view change
                                setTimeout(() => {
                                  const selectedElement = document.querySelector('.event-item.selected');
                                  if (selectedElement) {
                                    selectedElement.scrollIntoView({ behavior: 'smooth', block: 'start' });
                                  }
                                }, 100);
                              }
                            }}
                            style={{
                              padding: '10px 12px',
                              backgroundColor: '#272727',
                              borderRadius: '6px',
                              fontSize: '12px',
                              color: '#e0e0e0',
                              cursor: 'pointer',
                              transition: 'all 0.15s ease',
                              display: 'flex',
                              alignItems: 'center',
                              gap: '10px',
                              border: '1px solid #333'
                            }}
                            onMouseEnter={(e) => {
                              e.currentTarget.style.backgroundColor = '#2f2f2f';
                              e.currentTarget.style.borderColor = '#3b82f6';
                            }}
                            onMouseLeave={(e) => {
                              e.currentTarget.style.backgroundColor = '#272727';
                              e.currentTarget.style.borderColor = '#333';
                            }}
                          >
                            <span style={{
                              width: '6px',
                              height: '6px',
                              borderRadius: '50%',
                              backgroundColor: '#3b82f6',
                              flexShrink: 0
                            }} />
                            <span style={{ wordBreak: 'break-word', flex: 1 }}>{eventName}</span>
                            <span style={{ fontSize: '14px', color: '#555' }}>→</span>
                          </div>
                        ))}
                      </div>
                    ) : (
                      <div style={{
                        padding: '20px',
                        textAlign: 'center',
                        color: '#555',
                        fontSize: '11px'
                      }}>
                        This sound is not used in any events
                      </div>
                    )}
                  </div>
                </div>
              );
            })() : (
              <div style={{
                flex: 1,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: '#555',
                fontSize: '12px',
                padding: '20px',
                textAlign: 'center'
              }}>
                Select a sound to view details
              </div>
            )}
          </div>
        )}

        {/* Detached Sound Inspector */}
        {viewMode === 'sounds' && isSoundInspectorDetached && (
          <div
            style={{
              position: 'fixed',
              left: detachedSoundInspectorPosition.x,
              top: detachedSoundInspectorPosition.y,
              width: detachedSoundInspectorSize.width,
              height: detachedSoundInspectorSize.height,
              backgroundColor: '#1e1e1e',
              borderRadius: '8px',
              border: '1px solid #444',
              boxShadow: '0 10px 40px rgba(0, 0, 0, 0.5)',
              display: 'flex',
              flexDirection: 'column',
              overflow: 'hidden',
              zIndex: 1000
            }}
          >
            {/* Detached Header - Draggable */}
            <div
              style={{
                padding: '10px 16px',
                borderBottom: '1px solid #333',
                backgroundColor: '#f59e0b',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                cursor: 'move'
              }}
              onMouseDown={handleSoundInspectorMouseDown}
            >
              <span style={{ fontSize: '12px', fontWeight: 600, color: '#000' }}>Sound Usage</span>
              <div style={{ display: 'flex', gap: '4px' }}>
                <button
                  onClick={() => {
                    setIsSoundInspectorDetached(false);
                    setIsSoundInspectorOpen(true);
                  }}
                  style={{
                    padding: '4px 8px',
                    backgroundColor: 'rgba(0,0,0,0.2)',
                    color: '#000',
                    border: 'none',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    fontSize: '11px'
                  }}
                  title="Attach Inspector"
                >
                  📌
                </button>
                <button
                  onClick={() => {
                    setIsSoundInspectorDetached(false);
                    setIsSoundInspectorOpen(false);
                  }}
                  style={{
                    padding: '4px 8px',
                    backgroundColor: 'rgba(0,0,0,0.2)',
                    color: '#000',
                    border: 'none',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    fontSize: '11px'
                  }}
                  title="Close Inspector"
                >
                  ×
                </button>
              </div>
            </div>

            {/* Detached Content */}
            {selectedSoundId ? (() => {
              const selectedSound = soundUsages.find(s => s.soundId === selectedSoundId);
              const audioFile = audioFiles.find(af => af.name === selectedSoundId);

              return (
                <div style={{ flex: 1, overflowY: 'auto', padding: '16px' }}>
                  {/* Sound Info */}
                  <div style={{ marginBottom: '20px' }}>
                    <div style={{
                      fontSize: '10px',
                      fontWeight: 600,
                      color: '#888',
                      textTransform: 'uppercase',
                      letterSpacing: '0.5px',
                      marginBottom: '8px'
                    }}>
                      Sound File
                    </div>
                    <div style={{
                      fontSize: '14px',
                      fontWeight: 600,
                      color: '#fff',
                      wordBreak: 'break-word',
                      marginBottom: '8px'
                    }}>
                      {selectedSoundId.replace(/\.[^/.]+$/, '')}
                    </div>
                    <div style={{ display: 'flex', gap: '12px', fontSize: '11px', color: '#666' }}>
                      <span>{audioFile?.duration ? `${Math.round(audioFile.duration * 1000)}ms` : '—'}</span>
                      <span>{audioFile?.size || '—'}</span>
                      <span style={{
                        padding: '2px 6px',
                        backgroundColor: '#333',
                        borderRadius: '4px',
                        fontSize: '9px',
                        fontWeight: 700
                      }}>
                        {selectedSoundId.match(/\.[^/.]+$/)?.[0]?.replace('.', '').toUpperCase() || ''}
                      </span>
                    </div>
                  </div>

                  {/* Waveform Display */}
                  <div style={{ marginBottom: '20px' }}>
                    <div style={{
                      fontSize: '10px',
                      fontWeight: 600,
                      color: '#888',
                      textTransform: 'uppercase',
                      letterSpacing: '0.5px',
                      marginBottom: '8px'
                    }}>
                      Waveform
                    </div>
                    <div style={{
                      backgroundColor: '#1a1a1a',
                      borderRadius: '6px',
                      padding: '8px',
                      border: '1px solid #333'
                    }}>
                      {isLoadingWaveform ? (
                        <div style={{
                          height: '60px',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          color: '#666',
                          fontSize: '11px'
                        }}>
                          Loading waveform...
                        </div>
                      ) : waveformData ? (
                        <WaveformDisplay
                          data={waveformData}
                          width={280}
                          height={60}
                          color="#4a9eff"
                          backgroundColor="#1a1a1a"
                          mode="mirror"
                          showGrid={false}
                        />
                      ) : (
                        <div style={{
                          height: '60px',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          color: '#555',
                          fontSize: '11px'
                        }}>
                          No waveform available
                        </div>
                      )}
                    </div>
                  </div>

                  {/* Used in Events */}
                  <div>
                    <div style={{
                      fontSize: '10px',
                      fontWeight: 600,
                      color: '#888',
                      textTransform: 'uppercase',
                      letterSpacing: '0.5px',
                      marginBottom: '8px',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between'
                    }}>
                      <span>Used in Events</span>
                      {selectedSound && selectedSound.eventNames.length > 0 && (
                        <span style={{
                          padding: '2px 8px',
                          backgroundColor: '#2563eb',
                          borderRadius: '10px',
                          fontSize: '10px',
                          fontWeight: 700,
                          color: '#fff'
                        }}>
                          {selectedSound.eventNames.length}
                        </span>
                      )}
                    </div>

                    {selectedSound && selectedSound.eventNames.length > 0 ? (
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                        {selectedSound.eventNames.map((eventName) => (
                          <div
                            key={eventName}
                            onClick={() => {
                              const event = project?.events.find(ev => ev.eventName === eventName);
                              if (event) {
                                setSelectedEventId(event.id);
                                setViewMode('events');
                                // Scroll to selected event after view change
                                setTimeout(() => {
                                  const selectedElement = document.querySelector('.event-item.selected');
                                  if (selectedElement) {
                                    selectedElement.scrollIntoView({ behavior: 'smooth', block: 'start' });
                                  }
                                }, 100);
                              }
                            }}
                            style={{
                              padding: '10px 12px',
                              backgroundColor: '#272727',
                              borderRadius: '6px',
                              fontSize: '12px',
                              color: '#e0e0e0',
                              cursor: 'pointer',
                              transition: 'all 0.15s ease',
                              display: 'flex',
                              alignItems: 'center',
                              gap: '10px',
                              border: '1px solid #333'
                            }}
                            onMouseEnter={(e) => {
                              e.currentTarget.style.backgroundColor = '#2f2f2f';
                              e.currentTarget.style.borderColor = '#3b82f6';
                            }}
                            onMouseLeave={(e) => {
                              e.currentTarget.style.backgroundColor = '#272727';
                              e.currentTarget.style.borderColor = '#333';
                            }}
                          >
                            <span style={{
                              width: '6px',
                              height: '6px',
                              borderRadius: '50%',
                              backgroundColor: '#3b82f6',
                              flexShrink: 0
                            }} />
                            <span style={{ wordBreak: 'break-word', flex: 1 }}>{eventName}</span>
                            <span style={{ fontSize: '14px', color: '#555' }}>→</span>
                          </div>
                        ))}
                      </div>
                    ) : (
                      <div style={{
                        padding: '20px',
                        textAlign: 'center',
                        color: '#555',
                        fontSize: '11px'
                      }}>
                        This sound is not used in any events
                      </div>
                    )}
                  </div>
                </div>
              );
            })() : (
              <div style={{
                flex: 1,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: '#555',
                fontSize: '12px',
                padding: '20px',
                textAlign: 'center'
              }}>
                Select a sound to view details
              </div>
            )}

            {/* Resize handle */}
            <div
              style={{
                position: 'absolute',
                right: 0,
                bottom: 0,
                width: '16px',
                height: '16px',
                cursor: 'se-resize',
                background: 'linear-gradient(135deg, transparent 50%, #444 50%)'
              }}
              onMouseDown={handleSoundInspectorResizeMouseDown}
            />
          </div>
        )}

        <div
          className={`inspector-panel ${inspectorAnimationClass}`}
          style={{
            position: 'fixed',
            ...(isInspectorDetached ? {
              display: 'none'
            } : {
              right: isInspectorOpen ? 0 : '-350px',
              top: 0,
              bottom: 0,
            }),
            width: '350px',
            backgroundColor: '#1a1a1a',
            borderLeft: '1px solid #3a3a3a',
            zIndex: 1000,
            overflow: 'auto',
            boxShadow: isInspectorOpen ? '-4px 0 12px rgba(0, 0, 0, 0.5)' : 'none'
          }}
        >

          <div style={{ position: 'relative', zIndex: 1 }}>
            <div
              className="panel-header"
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center'
              }}
            >
              <h3>{viewMode === 'sounds' ? 'SOUND INSPECTOR' : 'COMMAND INSPECTOR'}</h3>
              {viewMode === 'events' && isInspectorOpen && (
                <button
                  onClick={handleDetachInspector}
                  style={{
                    padding: '4px 8px',
                    backgroundColor: isInspectorDetached ? '#f59e0b' : '#2a2a2a',
                    color: '#fff',
                    border: '1px solid #3a3a3a',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    fontSize: '12px',
                    fontWeight: 600,
                    transition: 'background-color 0.15s'
                  }}
                  title={isInspectorDetached ? 'Attach Inspector' : 'Detach Inspector'}
                >
                  {isInspectorDetached ? '📌 Attach' : '📌 Detach'}
                </button>
              )}
            </div>

            {viewMode === 'sounds' && selectedSoundId ? (
              <div className="inspector-content">
                {(() => {
                  const sound = soundUsages.find(s => s.soundId === selectedSoundId);
                  if (!sound) return null;

                  return (
                    <>
                      <div style={{ marginBottom: '20px' }}>
                        <label style={{ display: 'block', marginBottom: '8px', fontSize: '11px', fontWeight: 600, color: '#888' }}>
                          SOUND ID
                        </label>
                        <div style={{
                          padding: '10px 12px',
                          backgroundColor: '#2a2a2a',
                          borderRadius: '4px',
                          fontFamily: 'monospace',
                          fontSize: '13px'
                        }}>
                          {sound.soundId}
                        </div>
                      </div>

                      <div style={{ marginBottom: '20px' }}>
                        <label style={{ display: 'block', marginBottom: '8px', fontSize: '11px', fontWeight: 600, color: '#888' }}>
                          STATUS
                        </label>
                        <div style={{
                          padding: '8px 12px',
                          borderRadius: '4px',
                          backgroundColor: sound.hasFile ? '#16a34a' : '#dc2626',
                          color: '#fff',
                          fontWeight: 600,
                          fontSize: '12px',
                          textAlign: 'center'
                        }}>
                          {sound.hasFile ? '✓ FILE IMPORTED' : '✗ FILE MISSING'}
                        </div>
                      </div>

                      <div style={{ marginBottom: '20px' }}>
                        <label style={{ display: 'block', marginBottom: '8px', fontSize: '11px', fontWeight: 600, color: '#888' }}>
                          BUS
                        </label>
                        <select
                          value={(() => {
                            if (!project) return 'sfx';
                            const sprite = project.spriteItems.find(s => s.soundId === selectedSoundId);
                            return sprite?.bus ?? 'sfx';
                          })()}
                          onChange={(e) => {
                            if (!project) return;
                            const busId = e.target.value as BusId;

                            const hasSprite = project.spriteItems.some(s => s.soundId === selectedSoundId);

                            if (!hasSprite) {
                              const newSprite: AudioSpriteItem = {
                                id: `sprite_${Date.now()}`,
                                spriteId: selectedSoundId,
                                soundId: selectedSoundId,
                                startTime: 0,
                                duration: 0,
                                tags: [],
                                bus: busId
                              };

                              const updated = {
                                ...project,
                                spriteItems: [...project.spriteItems, newSprite]
                              };
                              setProject(updated);
                              saveToHistory(updated);
                            } else {
                              const updated = {
                                ...project,
                                spriteItems: project.spriteItems.map(s =>
                                  s.soundId === selectedSoundId ? { ...s, bus: busId } : s
                                )
                              };
                              setProject(updated);
                              saveToHistory(updated);

                              const isSoundPlaying = currentPlayingSound === selectedSoundId && isPlaying;
                              const isSoundInPlayingEvent = playingEvents.size > 0;

                              if (isSoundPlaying || isSoundInPlayingEvent) {
                                audioEngine.rerouteSoundToBus(selectedSoundId, busId);
                              }
                            }
                          }}
                          style={{
                            width: '100%',
                            padding: '8px 12px',
                            backgroundColor: '#2a2a2a',
                            border: '1px solid #444',
                            borderRadius: '4px',
                            color: '#e0e0e0',
                            fontSize: '12px',
                            cursor: 'pointer'
                          }}
                        >
                          {project?.buses.map(bus => (
                            <option key={bus.id} value={bus.id}>
                              {bus.name}
                            </option>
                          ))}
                        </select>
                      </div>

                      <div style={{ marginBottom: '20px' }}>
                        <label style={{ display: 'block', marginBottom: '8px', fontSize: '11px', fontWeight: 600, color: '#888' }}>
                          BPM METADATA
                        </label>
                        {(() => {
                          const sprite = project?.spriteItems.find(s => s.soundId === selectedSoundId);
                          const hasBPM = sprite?.bpm;

                          return (
                            <div style={{
                              padding: '12px',
                              backgroundColor: '#2a2a2a',
                              borderRadius: '4px',
                            }}>
                              {hasBPM ? (
                                <>
                                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                                    <span style={{ fontSize: '11px', color: '#888' }}>BPM:</span>
                                    <span style={{ fontSize: '13px', fontWeight: 600, color: '#fff' }}>{sprite.bpm}</span>
                                  </div>
                                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                                    <span style={{ fontSize: '11px', color: '#888' }}>Beats/Bar:</span>
                                    <span style={{ fontSize: '13px', color: '#fff' }}>{sprite.beatsPerBar || 4}</span>
                                  </div>
                                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                                    <span style={{ fontSize: '11px', color: '#888' }}>Loop Bars:</span>
                                    <span style={{ fontSize: '13px', color: '#fff' }}>{sprite.loopBars || 'N/A'}</span>
                                  </div>
                                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '12px' }}>
                                    <span style={{ fontSize: '11px', color: '#888' }}>Confidence:</span>
                                    <span style={{
                                      fontSize: '13px',
                                      color: (sprite.bpmConfidence || 0) > 0.6 ? '#16a34a' : '#f59e0b'
                                    }}>
                                      {((sprite.bpmConfidence || 0) * 100).toFixed(0)}%
                                    </span>
                                  </div>
                                  <button
                                    onClick={() => {
                                      if (!project || !sprite) return;
                                      const updated = {
                                        ...project,
                                        spriteItems: project.spriteItems.map(s =>
                                          s.id === sprite.id
                                            ? { ...s, bpm: undefined, beatsPerBar: undefined, loopBars: undefined, bpmConfidence: undefined }
                                            : s
                                        )
                                      };
                                      setProject(updated);
                                      saveToHistory(updated);
                                    }}
                                    style={{
                                      width: '100%',
                                      padding: '6px',
                                      fontSize: '11px',
                                      backgroundColor: '#dc2626',
                                      color: '#fff',
                                      border: 'none',
                                      borderRadius: '3px',
                                      cursor: 'pointer',
                                    }}
                                  >
                                    Clear BPM Data
                                  </button>
                                </>
                              ) : (
                                <>
                                  <div style={{ fontSize: '12px', color: '#888', marginBottom: '12px', textAlign: 'center' }}>
                                    No BPM data available
                                  </div>
                                  <button
                                    onClick={async () => {
                                      if (!project || !sound.hasFile) return;

                                      const audioFile = audioFiles.find(f => f.name === selectedSoundId || f.name.startsWith(selectedSoundId));
                                      if (!audioFile) {
                                        alert('Audio file not found in loaded files');
                                        return;
                                      }

                                      try {
                                        const arrayBuffer = await fetch(audioFile.url).then(r => r.arrayBuffer());
                                        const { AudioContextManager } = await import('./core/AudioContextManager');
                                        const audioBuffer = await AudioContextManager.decodeAudioData(arrayBuffer);

                                        const { analyzeAndSaveBPM } = await import('./core/bpmMetadata');

                                        let sprite = project.spriteItems.find(s => s.soundId === selectedSoundId);
                                        if (!sprite) {
                                          sprite = {
                                            id: `sprite_${Date.now()}`,
                                            spriteId: selectedSoundId,
                                            soundId: selectedSoundId,
                                            startTime: 0,
                                            duration: audioBuffer.duration,
                                            tags: [],
                                          };
                                        }

                                        const result = await analyzeAndSaveBPM(audioBuffer, sprite, project, {
                                          autoSave: false,
                                          minConfidence: 0.3,
                                        });

                                        if (result.success) {
                                          const updated = {
                                            ...project,
                                            spriteItems: project.spriteItems.some(s => s.id === sprite!.id)
                                              ? project.spriteItems.map(s => s.id === sprite!.id ? result.updatedSprite : s)
                                              : [...project.spriteItems, result.updatedSprite]
                                          };
                                          setProject(updated);
                                          saveToHistory(updated);

                                          const warnings = result.warnings.length > 0
                                            ? '\n\n⚠️ Warnings:\n' + result.warnings.join('\n')
                                            : '';

                                          alert(`✅ BPM Analysis Complete!\n\nBPM: ${result.updatedSprite.bpm}\nLoop Bars: ${result.updatedSprite.loopBars}\nConfidence: ${((result.updatedSprite.bpmConfidence || 0) * 100).toFixed(0)}%${warnings}`);
                                        } else {
                                          alert('❌ BPM detection failed. Try a different audio file.');
                                        }
                                      } catch (err) {
                                        alert(`Error: ${err}`);
                                      }
                                    }}
                                    disabled={!sound.hasFile}
                                    style={{
                                      width: '100%',
                                      padding: '8px',
                                      fontSize: '12px',
                                      fontWeight: 600,
                                      backgroundColor: sound.hasFile ? '#2196F3' : '#444',
                                      color: sound.hasFile ? '#fff' : '#888',
                                      border: 'none',
                                      borderRadius: '4px',
                                      cursor: sound.hasFile ? 'pointer' : 'not-allowed',
                                    }}
                                  >
                                    🎵 Analyze BPM
                                  </button>
                                </>
                              )}
                            </div>
                          );
                        })()}
                      </div>

                      <div style={{ marginBottom: '20px' }}>
                        <label style={{ display: 'block', marginBottom: '8px', fontSize: '11px', fontWeight: 600, color: '#888' }}>
                          USED IN EVENTS ({sound.eventNames.length})
                        </label>
                        <div style={{
                          maxHeight: '150px',
                          overflowY: 'auto',
                          backgroundColor: '#2a2a2a',
                          borderRadius: '4px',
                          padding: '8px'
                        }}>
                          {sound.eventNames.length > 0 ? (
                            sound.eventNames.map((eventName) => (
                              <div
                                key={eventName}
                                style={{
                                  padding: '6px 8px',
                                  marginBottom: '4px',
                                  backgroundColor: '#333',
                                  borderRadius: '3px',
                                  fontSize: '12px',
                                  cursor: 'pointer'
                                }}
                                onClick={() => {
                                  const event = project?.events.find(e => e.eventName === eventName);
                                  if (event) {
                                    setViewMode('events');
                                    setSelectedEventId(event.id);
                                    setSelectedSoundId(null);
                                  }
                                }}
                              >
                                {eventName}
                              </div>
                            ))
                          ) : (
                            <div style={{ padding: '8px', color: '#666', fontSize: '12px' }}>
                              Not used in any events
                            </div>
                          )}
                        </div>
                      </div>

                      <div style={{ marginBottom: '20px' }}>
                        <label style={{ display: 'block', marginBottom: '8px', fontSize: '11px', fontWeight: 600, color: '#888' }}>
                          SPRITES ({sound.spriteIds.length})
                        </label>
                        <div style={{
                          maxHeight: '100px',
                          overflowY: 'auto',
                          backgroundColor: '#2a2a2a',
                          borderRadius: '4px',
                          padding: '8px'
                        }}>
                          {sound.spriteIds.length > 0 ? (
                            sound.spriteIds.map((spriteId) => (
                              <div
                                key={spriteId}
                                style={{
                                  padding: '4px 8px',
                                  marginBottom: '2px',
                                  backgroundColor: '#333',
                                  borderRadius: '3px',
                                  fontSize: '11px',
                                  fontFamily: 'monospace'
                                }}
                              >
                                {spriteId}
                              </div>
                            ))
                          ) : (
                            <div style={{ padding: '8px', color: '#666', fontSize: '12px' }}>
                              No sprites defined
                            </div>
                          )}
                        </div>
                      </div>

                      {sound.hasFile && (
                        <div style={{ marginTop: '20px', display: 'flex', gap: '8px' }}>
                          <button
                            className="btn-play"
                            onClick={() => {
                              const audioFile = audioFiles.find(af => af.name === sound.soundId);
                              if (audioFile) {
                                const sprite = project?.spriteItems.find(s => s.soundId === sound.soundId);
                                const bus = (sprite?.bus as BusId) ?? 'sfx';
                                audioEngine.playSound(sound.soundId, 1, false, currentPlayingSound, isPlaying, bus);
                              }
                            }}
                            disabled={playingEvents.size > 0}
                            style={{
                              flex: 1,
                              padding: '10px',
                              backgroundColor: playingEvents.size > 0 ? '#2a2a2a' : '#16a34a',
                              color: playingEvents.size > 0 ? '#6d6d6d' : '#fff',
                              border: 'none',
                              borderRadius: '4px',
                              cursor: playingEvents.size > 0 ? 'not-allowed' : 'pointer',
                              fontWeight: 600,
                              fontSize: '13px'
                            }}
                          >
                            ▶ Play
                          </button>
                          <button
                            className="btn-stop"
                            onClick={handleStopAllEvents}
                            style={{
                              flex: 1,
                              padding: '10px',
                              backgroundColor: '#dc2626',
                              color: '#fff',
                              border: 'none',
                              borderRadius: '4px',
                              cursor: 'pointer',
                              fontWeight: 600,
                              fontSize: '13px'
                            }}
                          >
                            ■ Stop
                          </button>
                        </div>
                      )}
                    </>
                  );
                })()}
              </div>
            ) : viewMode === 'events' && selectedCommand ? (
              <div className="inspector-content">
                <label>
                  TYPE
                  <select
                    value={selectedCommand.type}
                    onChange={(e) =>
                      selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                        type: e.target.value as CommandType,
                      })
                    }
                  >
                    <option value="Play">Play</option>
                    <option value="Stop">Stop</option>
                    <option value="Fade">Fade</option>
                    <option value="Pause">Pause</option>
                    <option value="Execute">Execute</option>
                  </select>
                </label>

              {(selectedCommand.type === "Play" || selectedCommand.type === "Stop" ||
                selectedCommand.type === "Fade" || selectedCommand.type === "Pause") && (
                <>
                  <label>
                    SOUND
                    <div style={{ marginTop: '6px' }}>
                      <input
                        type="text"
                        placeholder="Search sounds..."
                        value={soundSearchQuery}
                        onChange={(e) => setSoundSearchQuery(e.target.value)}
                        style={{ marginBottom: '6px', marginTop: 0 }}
                      />
                      <div style={{ display: 'flex', gap: '8px', alignItems: 'center', flexWrap: 'nowrap' }}>
                        <select
                          value={(selectedCommand as PlayCommand).soundId || ""}
                          onChange={(e) => {
                            if (audioRef.current) {
                              audioRef.current.pause();
                              audioRef.current.currentTime = 0;
                              audioRef.current = null;
                            }
                            if (audioSourceRef.current) {
                              try {
                                audioSourceRef.current.stop();
                              } catch (err) {
                                // Ignore if already stopped
                              }
                              audioSourceRef.current = null;
                            }
                            setIsPlaying(false);
                            setCurrentPlayingSound("");

                            selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, { soundId: e.target.value });
                            setSoundSearchQuery("");
                          }}
                          style={{ flex: '1 1 auto', minWidth: '120px' }}
                        >
                          <option value="">-- Select Sound --</option>
                          {audioFiles
                            .filter((audioFile) =>
                              audioFile.name.toLowerCase().includes(deferredSoundSearchQuery.toLowerCase())
                            )
                            .sort((a, b) => a.name.localeCompare(b.name))
                            .map((audioFile) => (
                              <option key={audioFile.id} value={audioFile.name}>
                                {audioFile.name}
                              </option>
                            ))}
                        </select>
                        {(selectedCommand as PlayCommand).soundId && (
                          <>
                            <button
                              className={`btn-icon-play ${playingEvents.size > 0 ? 'disabled' : ''}`}
                              onClick={() => {
                                const soundId = (selectedCommand as PlayCommand).soundId;
                                const volume = (selectedCommand as PlayCommand).volume ?? 1;
                                const loop = (selectedCommand as PlayCommand).loop ?? false;

                                if (currentPlayingSound === soundId && isPlaying) {
                                  // Pause
                                  if (audioRef.current) {
                                    audioRef.current.pause();
                                    setIsPlaying(false);
                                  } else if (audioSourceRef.current && audioContextRef.current) {
                                    audioContextRef.current.suspend();
                                    setIsPlaying(false);
                                  }
                                } else if (currentPlayingSound === soundId && !isPlaying) {
                                  // Resume
                                  if (audioRef.current) {
                                    audioRef.current.play().then(() => {
                                      setIsPlaying(true);
                                    }).catch((err) => {
                                      console.error("Failed to resume audio:", err);
                                    });
                                  } else if (audioContextRef.current) {
                                    audioContextRef.current.resume().then(() => {
                                      setIsPlaying(true);
                                    }).catch((err) => {
                                      console.error("Failed to resume audio context:", err);
                                    });
                                  }
                                } else {
                                  handlePlaySound(soundId, volume, loop);
                                }
                              }}
                              disabled={playingEvents.size > 0}
                              title={currentPlayingSound === (selectedCommand as PlayCommand).soundId && isPlaying ? "Pause" : "Play"}
                            >
                              {currentPlayingSound === (selectedCommand as PlayCommand).soundId && isPlaying ? '⏸' : '▶'}
                            </button>
                            <button
                              className="btn-icon-stop"
                              onClick={() => {
                                if (audioRef.current) {
                                  audioRef.current.pause();
                                  audioRef.current.currentTime = 0;
                                  audioRef.current = null;
                                }
                                if (audioSourceRef.current) {
                                  try {
                                    audioSourceRef.current.stop();
                                  } catch (e) {
                                    // Ignore if already stopped
                                  }
                                  audioSourceRef.current = null;
                                }
                                setIsPlaying(false);
                                setCurrentPlayingSound("");
                              }}
                              title="Stop"
                            >
                              ⏹
                            </button>
                          </>
                        )}
                      </div>
                    </div>
                  </label>
                </>
              )}

              {selectedCommand && selectedCommand.type === "Play" && (
                <>
                  <label>
                    VOLUME
                    <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                      <input
                        type="text"
                        inputMode="decimal"
                        value={draftVolume !== null ? draftVolume : formatDecimal((selectedCommand as PlayCommand).volume ?? 1)}
                        placeholder="1"
                        onChange={(e) => {
                          const value = e.target.value.replace(',', '.');
                          setDraftVolume(value);
                        }}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { volume: 1 });
                              setDraftVolume(null);
                            }
                          });
                        }}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' && selectedCommandIndex !== null) {
                            const value = draftVolume !== null ? draftVolume : e.currentTarget.value;
                            if (value === "") {
                              handleUpdateCommand(selectedCommandIndex, { volume: undefined });
                            } else {
                              const numValue = parseFloat(value.replace(',', '.'));
                              if (!isNaN(numValue)) {
                                handleUpdateCommand(selectedCommandIndex, { volume: Math.max(0, Math.min(1, numValue)) });
                              }
                            }
                            setDraftVolume(null);
                            e.currentTarget.blur();
                          } else if (e.key === 'Escape') {
                            setDraftVolume(null);
                            e.currentTarget.blur();
                          }
                        }}
                        onBlur={() => {
                          setDraftVolume(null);
                        }}
                        onFocus={(e) => e.target.select()}
                        style={{ width: "60px" }}
                      />
                      <input
                        type="range"
                        step="0.01"
                        min="0"
                        max="100"
                        value={(() => {
                          const vol = (selectedCommand as PlayCommand).volume ?? 1;
                          return vol === 0 ? 0 : Math.log10(vol * 9 + 1) * 100;
                        })()}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { volume: 1 });
                              if (audioRef.current && currentPlayingSound === (selectedCommand as PlayCommand).soundId) {
                                audioRef.current.volume = 1;
                              }
                              if (gainNodeRef.current && currentPlayingSound === (selectedCommand as PlayCommand).soundId) {
                                gainNodeRef.current.gain.value = 1;
                              }
                            }
                          });
                        }}
                        onChange={(e) => {
                          const sliderValue = parseFloat(e.target.value);
                          const rawVolume = sliderValue === 0 ? 0 : (Math.pow(10, sliderValue / 100) - 1) / 9;
                          const newVolume = Math.round(rawVolume * 100) / 100;
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, {
                              volume: newVolume,
                            });

                            if (audioRef.current && currentPlayingSound === (selectedCommand as PlayCommand).soundId) {
                              audioRef.current.volume = newVolume;
                            }
                            if (gainNodeRef.current && currentPlayingSound === (selectedCommand as PlayCommand).soundId) {
                              gainNodeRef.current.gain.value = newVolume;
                            }
                          }
                        }}
                        style={{ flex: 1 }}
                      />
                    </div>
                  </label>




                  <label>
                    PAN
                    <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                      <input
                        type="text"
                        inputMode="decimal"
                        value={draftPan !== null ? draftPan : formatDecimal((selectedCommand as PlayCommand).pan ?? 0)}
                        placeholder="0"
                        onChange={(e) => {
                          const value = e.target.value.replace(',', '.');
                          setDraftPan(value);
                        }}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                              setDraftPan(null);
                              const soundId = (selectedCommand as PlayCommand).soundId;
                              const audioObjects = soundAudioMap.current.get(soundId);
                              if (audioObjects) {
                                audioObjects.forEach(obj => {
                                  if (obj.panNode) {
                                    obj.panNode.pan.value = 0;
                                  }
                                });
                              }
                            }
                          });
                        }}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' && selectedCommandIndex !== null) {
                            const value = draftPan !== null ? draftPan : e.currentTarget.value;
                            if (value === "") {
                              handleUpdateCommand(selectedCommandIndex, { pan: undefined });
                            } else {
                              const numValue = parseFloat(value.replace(',', '.'));
                              if (!isNaN(numValue)) {
                                const clampedPan = Math.max(-1, Math.min(1, numValue));
                                handleUpdateCommand(selectedCommandIndex, { pan: clampedPan });
                                const soundId = (selectedCommand as PlayCommand).soundId;
                                const audioObjects = soundAudioMap.current.get(soundId);
                                if (audioObjects) {
                                  audioObjects.forEach(obj => {
                                    if (obj.panNode) {
                                      obj.panNode.pan.value = clampedPan;
                                    }
                                  });
                                }
                              }
                            }
                            setDraftPan(null);
                            e.currentTarget.blur();
                          } else if (e.key === 'Escape') {
                            setDraftPan(null);
                            e.currentTarget.blur();
                          }
                        }}
                        onBlur={() => {
                          setDraftPan(null);
                        }}
                        onFocus={(e) => e.target.select()}
                        style={{ width: "60px" }}
                      />
                      <input
                        type="range"
                        step="0.01"
                        min="-1"
                        max="1"
                        value={(() => { const pan = (selectedCommand as PlayCommand).pan ?? 0; return Math.max(-1, Math.min(1, pan)); })()}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                              const soundId = (selectedCommand as PlayCommand).soundId;
                              const audioObjects = soundAudioMap.current.get(soundId);
                              if (audioObjects) {
                                audioObjects.forEach(obj => {
                                  if (obj.panNode) {
                                    obj.panNode.pan.value = 0;
                                  }
                                });
                              }
                            }
                          });
                        }}
                        onChange={(e) => {
                          const newPan = Math.max(-1, Math.min(1, parseFloat(e.target.value)));
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, {
                              pan: newPan,
                            });

                            const soundId = (selectedCommand as PlayCommand).soundId;
                            const audioObjects = soundAudioMap.current.get(soundId);
                            if (audioObjects) {
                              audioObjects.forEach(obj => {
                                if (obj.panNode) {
                                  obj.panNode.pan.value = newPan;
                                }
                              });
                            }
                          }
                        }}
                        style={{ flex: 1 }}
                      />
                    </div>
                  </label>

                  <label className="checkbox-label">
                    <input
                      type="checkbox"
                      checked={!!(selectedCommand as PlayCommand).loop}
                      onChange={(e) => {
                        if (selectedCommandIndex !== null) {
                          const newLoopValue = e.target.checked;
                          handleUpdateCommand(selectedCommandIndex, { loop: newLoopValue });

                          const soundId = (selectedCommand as PlayCommand).soundId;
                          if (soundId) {
                            const audioObjects = soundAudioMap.current.get(soundId);
                            if (audioObjects) {
                              audioObjects.forEach(obj => {
                                if (obj.source) {
                                  obj.source.loop = newLoopValue;
                                }
                              });
                            }
                          }
                        }
                      }}
                    />
                    LOOP INFINITELY
                  </label>

                  {!(selectedCommand as PlayCommand).loop && (
                    <label>
                      REPEAT COUNT
                      <input
                        type="number"
                        min="1"
                        max="999"
                        value={(selectedCommand as PlayCommand).loopCount ?? ""}
                        placeholder="1"
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { loopCount: 1 });
                            }
                          });
                        }}
                        onChange={(e) =>
                          selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                            loopCount: e.target.value === "" ? undefined : parseInt(e.target.value) || 1,
                          })
                        }
                        onKeyDown={(e) => {
                          if (e.key === 'Enter') {
                            e.currentTarget.blur();
                          }
                        }}
                        onFocus={(e) => e.target.select()}
                      />
                    </label>
                  )}

                  <label className="checkbox-label">
                    <input
                      type="checkbox"
                      checked={!!(selectedCommand as PlayCommand).overlap}
                      onChange={(e) =>
                        selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, { overlap: e.target.checked })
                      }
                    />
                    OVERLAP
                  </label>

                  <label>
                    DELAY (MS)
                    <input
                      type="text"
                      inputMode="numeric"
                      value={(selectedCommand as PlayCommand).delay ?? ""}
                      placeholder="0"
                      onMouseDown={(e) => {
                        handleResetOnModifierClick(e, () => {
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, { delay: 0 });
                          }
                        });
                      }}
                      onChange={(e) =>
                        selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                          delay: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                        })
                      }
                      onFocus={(e) => e.target.select()}
                    />
                  </label>
                </>
              )}

              {selectedCommand && selectedCommand.type === "Stop" && (
                <>
                  <label>
                    VOLUME
                    <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                      <input
                        type="text"
                        inputMode="decimal"
                        value={draftVolume !== null ? draftVolume : formatDecimal((selectedCommand as StopCommand).volume ?? 1)}
                        placeholder="1"
                        onChange={(e) => {
                          const value = e.target.value.replace(',', '.');
                          setDraftVolume(value);
                        }}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { volume: 1 });
                              setDraftVolume(null);
                            }
                          });
                        }}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' && selectedCommandIndex !== null) {
                            const value = draftVolume !== null ? draftVolume : e.currentTarget.value;
                            if (value === "") {
                              handleUpdateCommand(selectedCommandIndex, { volume: undefined });
                            } else {
                              const numValue = parseFloat(value.replace(',', '.'));
                              if (!isNaN(numValue)) {
                                handleUpdateCommand(selectedCommandIndex, { volume: Math.max(0, Math.min(1, numValue)) });
                              }
                            }
                            setDraftVolume(null);
                            e.currentTarget.blur();
                          } else if (e.key === 'Escape') {
                            setDraftVolume(null);
                            e.currentTarget.blur();
                          }
                        }}
                        onBlur={() => {
                          setDraftVolume(null);
                        }}
                        onFocus={(e) => e.target.select()}
                        style={{ width: "60px" }}
                      />
                      <input
                        type="range"
                        step="0.01"
                        min="0"
                        max="100"
                        value={(() => {
                          const vol = (selectedCommand as StopCommand).volume ?? 1;
                          return vol === 0 ? 0 : Math.log10(vol * 9 + 1) * 100;
                        })()}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { volume: 1 });
                            }
                          });
                        }}
                        onChange={(e) => {
                          const sliderValue = parseFloat(e.target.value);
                          const rawVolume = sliderValue === 0 ? 0 : (Math.pow(10, sliderValue / 100) - 1) / 9;
                          const newVolume = Math.round(rawVolume * 100) / 100;
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, {
                              volume: newVolume,
                            });
                          }
                        }}
                        style={{ flex: 1 }}
                      />
                    </div>
                  </label>

                  <label>
                    PAN
                    <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                      <input
                        type="text"
                        inputMode="decimal"
                        value={draftPan !== null ? draftPan : formatDecimal((selectedCommand as StopCommand).pan ?? 0)}
                        placeholder="0"
                        onChange={(e) => {
                          const value = e.target.value.replace(',', '.');
                          setDraftPan(value);
                        }}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                              setDraftPan(null);
                              const soundId = (selectedCommand as StopCommand).soundId;
                              const audioObjects = soundAudioMap.current.get(soundId);
                              if (audioObjects) {
                                audioObjects.forEach(obj => {
                                  if (obj.panNode) {
                                    obj.panNode.pan.value = 0;
                                  }
                                });
                              }
                            }
                          });
                        }}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' && selectedCommandIndex !== null) {
                            const value = draftPan !== null ? draftPan : e.currentTarget.value;
                            if (value === "") {
                              handleUpdateCommand(selectedCommandIndex, { pan: undefined });
                            } else {
                              const numValue = parseFloat(value.replace(',', '.'));
                              if (!isNaN(numValue)) {
                                const clampedPan = Math.max(-1, Math.min(1, numValue));
                                handleUpdateCommand(selectedCommandIndex, { pan: clampedPan });
                              }
                            }
                            setDraftPan(null);
                            e.currentTarget.blur();
                          } else if (e.key === 'Escape') {
                            setDraftPan(null);
                            e.currentTarget.blur();
                          }
                        }}
                        onBlur={() => {
                          setDraftPan(null);
                        }}
                        onFocus={(e) => e.target.select()}
                        style={{ width: "60px" }}
                      />
                      <input
                        type="range"
                        step="0.01"
                        min="-1"
                        max="1"
                        value={(() => {
                          const pan = (selectedCommand as StopCommand).pan ?? 0;
                          return Math.max(-1, Math.min(1, pan));
                        })()}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                              const soundId = (selectedCommand as StopCommand).soundId;
                              const audioObjects = soundAudioMap.current.get(soundId);
                              if (audioObjects) {
                                audioObjects.forEach(obj => {
                                  if (obj.panNode) {
                                    obj.panNode.pan.value = 0;
                                  }
                                });
                              }
                            }
                          });
                        }}
                        onChange={(e) => {
                          const newPan = parseFloat(e.target.value);
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, {
                              pan: Math.max(-1, Math.min(1, newPan)),
                            });

                            const soundId = (selectedCommand as StopCommand).soundId;
                            const audioObjects = soundAudioMap.current.get(soundId);
                            if (audioObjects) {
                              audioObjects.forEach(obj => {
                                if (obj.panNode) {
                                  obj.panNode.pan.value = newPan;
                                }
                              });
                            }
                          }
                        }}
                        style={{ flex: 1 }}
                      />
                    </div>
                  </label>

                  <label>
                    FADE DURATION (MS)
                    <input
                      type="text"
                      inputMode="numeric"
                      value={(selectedCommand as StopCommand).fadeOut ?? ""}
                      placeholder="0"
                      onMouseDown={(e) => {
                        handleResetOnModifierClick(e, () => {
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, { fadeOut: 0 });
                          }
                        });
                      }}
                      onChange={(e) =>
                        selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                          fadeOut: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                        })
                      }
                      onFocus={(e) => e.target.select()}
                    />
                  </label>
                  <label>
                    DELAY (MS)
                    <input
                      type="text"
                      inputMode="numeric"
                      value={(selectedCommand as StopCommand).delay ?? ""}
                      placeholder="0"
                      onMouseDown={(e) => {
                        handleResetOnModifierClick(e, () => {
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, { delay: 0 });
                          }
                        });
                      }}
                      onChange={(e) =>
                        selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                          delay: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                        })
                      }
                      onFocus={(e) => e.target.select()}
                    />
                  </label>
                </>
              )}

              {selectedCommand && selectedCommand.type === "Pause" && (
                <>
                  <label>
                    VOLUME
                    <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                      <input
                        type="text"
                        inputMode="decimal"
                        value={draftVolume !== null ? draftVolume : formatDecimal((selectedCommand as PauseCommand).volume ?? 0)}
                        placeholder="0"
                        onChange={(e) => {
                          const value = e.target.value.replace(',', '.');
                          setDraftVolume(value);
                        }}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { volume: 0 });
                              setDraftVolume(null);
                            }
                          });
                        }}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' && selectedCommandIndex !== null) {
                            const value = draftVolume !== null ? draftVolume : e.currentTarget.value;
                            if (value === "") {
                              handleUpdateCommand(selectedCommandIndex, { volume: 0 });
                            } else {
                              const numValue = parseFloat(value.replace(',', '.'));
                              if (!isNaN(numValue)) {
                                handleUpdateCommand(selectedCommandIndex, { volume: Math.max(0, Math.min(1, numValue)) });
                              }
                            }
                            setDraftVolume(null);
                            e.currentTarget.blur();
                          } else if (e.key === 'Escape') {
                            setDraftVolume(null);
                            e.currentTarget.blur();
                          }
                        }}
                        onBlur={() => {
                          setDraftVolume(null);
                        }}
                        onFocus={(e) => e.target.select()}
                        style={{ width: "60px" }}
                      />
                      <input
                        type="range"
                        step="0.01"
                        min="0"
                        max="100"
                        value={(() => {
                          const vol = (selectedCommand as PauseCommand).volume ?? 0;
                          return vol === 0 ? 0 : Math.log10(vol * 9 + 1) * 100;
                        })()}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { volume: 0 });
                            }
                          });
                        }}
                        onChange={(e) => {
                          const sliderValue = parseFloat(e.target.value);
                          const rawVolume = sliderValue === 0 ? 0 : (Math.pow(10, sliderValue / 100) - 1) / 9;
                          const newVolume = Math.round(rawVolume * 100) / 100;
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, {
                              volume: newVolume,
                            });
                          }
                        }}
                        style={{ flex: 1 }}
                      />
                    </div>
                  </label>

                  <label>
                    PAN
                    <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                      <input
                        type="text"
                        inputMode="decimal"
                        value={draftPan !== null ? draftPan : formatDecimal((selectedCommand as PauseCommand).pan ?? 0)}
                        placeholder="0"
                        onChange={(e) => {
                          const value = e.target.value.replace(',', '.');
                          setDraftPan(value);
                        }}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                              setDraftPan(null);
                              const soundId = (selectedCommand as PauseCommand).soundId;
                              const audioObjects = soundAudioMap.current.get(soundId);
                              if (audioObjects) {
                                audioObjects.forEach(obj => {
                                  if (obj.panNode) {
                                    obj.panNode.pan.value = 0;
                                  }
                                });
                              }
                            }
                          });
                        }}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' && selectedCommandIndex !== null) {
                            const value = draftPan !== null ? draftPan : e.currentTarget.value;
                            if (value === "") {
                              handleUpdateCommand(selectedCommandIndex, { pan: undefined });
                            } else {
                              const numValue = parseFloat(value.replace(',', '.'));
                              if (!isNaN(numValue)) {
                                const clampedPan = Math.max(-1, Math.min(1, numValue));
                                handleUpdateCommand(selectedCommandIndex, { pan: clampedPan });
                              }
                            }
                            setDraftPan(null);
                            e.currentTarget.blur();
                          } else if (e.key === 'Escape') {
                            setDraftPan(null);
                            e.currentTarget.blur();
                          }
                        }}
                        onBlur={() => {
                          setDraftPan(null);
                        }}
                        onFocus={(e) => e.target.select()}
                        style={{ width: "60px" }}
                      />
                      <input
                        type="range"
                        step="0.01"
                        min="-1"
                        max="1"
                        value={(() => {
                          const pan = (selectedCommand as PauseCommand).pan ?? 0;
                          return Math.max(-1, Math.min(1, pan));
                        })()}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                              const soundId = (selectedCommand as PauseCommand).soundId;
                              const audioObjects = soundAudioMap.current.get(soundId);
                              if (audioObjects) {
                                audioObjects.forEach(obj => {
                                  if (obj.panNode) {
                                    obj.panNode.pan.value = 0;
                                  }
                                });
                              }
                            }
                          });
                        }}
                        onChange={(e) => {
                          const newPan = parseFloat(e.target.value);
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, {
                              pan: Math.max(-1, Math.min(1, newPan)),
                            });

                            const soundId = (selectedCommand as PauseCommand).soundId;
                            const audioObjects = soundAudioMap.current.get(soundId);
                            if (audioObjects) {
                              audioObjects.forEach(obj => {
                                if (obj.panNode) {
                                  obj.panNode.pan.value = newPan;
                                }
                              });
                            }
                          }
                        }}
                        style={{ flex: 1 }}
                      />
                    </div>
                  </label>

                  <label>
                    FADE DURATION (MS)
                    <input
                      type="text"
                      inputMode="numeric"
                      value={(selectedCommand as PauseCommand).fadeOut ?? ""}
                      placeholder="0"
                      onMouseDown={(e) => {
                        handleResetOnModifierClick(e, () => {
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, { fadeOut: 0 });
                          }
                        });
                      }}
                      onChange={(e) =>
                        selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                          fadeOut: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                        })
                      }
                      onFocus={(e) => e.target.select()}
                    />
                  </label>

                  <label>
                    DELAY (MS)
                    <input
                      type="text"
                      inputMode="numeric"
                      value={(selectedCommand as PauseCommand).delay ?? ""}
                      placeholder="0"
                      onMouseDown={(e) => {
                        handleResetOnModifierClick(e, () => {
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, { delay: 0 });
                          }
                        });
                      }}
                      onChange={(e) =>
                        selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                          delay: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                        })
                      }
                      onFocus={(e) => e.target.select()}
                    />
                  </label>
                </>
              )}

              {selectedCommand && selectedCommand.type === "Fade" && (
                <>
                  <label>
                    TARGET VOLUME
                    <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                      <input
                        type="text"
                        inputMode="decimal"
                        value={draftVolume !== null ? draftVolume : formatDecimal((selectedCommand as FadeCommand).targetVolume ?? 0)}
                        placeholder="0"
                        onChange={(e) => {
                          const value = e.target.value.replace(',', '.');
                          setDraftVolume(value);
                        }}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { targetVolume: 0 });
                              setDraftVolume(null);
                            }
                          });
                        }}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' && selectedCommandIndex !== null) {
                            const value = draftVolume !== null ? draftVolume : e.currentTarget.value;
                            if (value === "") {
                              handleUpdateCommand(selectedCommandIndex, { targetVolume: 0 });
                            } else {
                              const numValue = parseFloat(value.replace(',', '.'));
                              if (!isNaN(numValue)) {
                                handleUpdateCommand(selectedCommandIndex, { targetVolume: Math.max(0, Math.min(1, numValue)) });
                              }
                            }
                            setDraftVolume(null);
                            e.currentTarget.blur();
                          } else if (e.key === 'Escape') {
                            setDraftVolume(null);
                            e.currentTarget.blur();
                          }
                        }}
                        onBlur={() => {
                          setDraftVolume(null);
                        }}
                        onFocus={(e) => e.target.select()}
                        style={{ width: "60px" }}
                      />
                      <input
                        type="range"
                        step="0.01"
                        min="0"
                        max="100"
                        value={(() => {
                          const vol = (selectedCommand as FadeCommand).targetVolume ?? 0;
                          return vol === 0 ? 0 : Math.log10(vol * 9 + 1) * 100;
                        })()}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { targetVolume: 0 });
                            }
                          });
                        }}
                        onChange={(e) => {
                          const sliderValue = parseFloat(e.target.value);
                          const rawVolume = sliderValue === 0 ? 0 : (Math.pow(10, sliderValue / 100) - 1) / 9;
                          const newVolume = Math.round(rawVolume * 100) / 100;
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, {
                              targetVolume: newVolume,
                            });
                          }
                        }}
                        style={{ flex: 1 }}
                      />
                    </div>
                  </label>


                  <label>
                    PAN
                    <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                      <input
                        type="text"
                        inputMode="decimal"
                        value={draftPan !== null ? draftPan : formatDecimal((selectedCommand as FadeCommand).pan ?? 0)}
                        placeholder="0"
                        onChange={(e) => {
                          const value = e.target.value.replace(',', '.');
                          setDraftPan(value);
                        }}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                              setDraftPan(null);
                              const soundId = (selectedCommand as FadeCommand).soundId;
                              const audioObjects = soundAudioMap.current.get(soundId);
                              if (audioObjects) {
                                audioObjects.forEach(obj => {
                                  if (obj.panNode) {
                                    obj.panNode.pan.value = 0;
                                  }
                                });
                              }
                            }
                          });
                        }}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' && selectedCommandIndex !== null) {
                            const value = draftPan !== null ? draftPan : e.currentTarget.value;
                            if (value === "") {
                              handleUpdateCommand(selectedCommandIndex, { pan: undefined });
                            } else {
                              const numValue = parseFloat(value.replace(',', '.'));
                              if (!isNaN(numValue)) {
                                const clampedPan = Math.max(-1, Math.min(1, numValue));
                                handleUpdateCommand(selectedCommandIndex, { pan: clampedPan });
                              }
                            }
                            setDraftPan(null);
                            e.currentTarget.blur();
                          } else if (e.key === 'Escape') {
                            setDraftPan(null);
                            e.currentTarget.blur();
                          }
                        }}
                        onBlur={() => {
                          setDraftPan(null);
                        }}
                        onFocus={(e) => e.target.select()}
                        style={{ width: "60px" }}
                      />
                      <input
                        type="range"
                        step="0.01"
                        min="-1"
                        max="1"
                        value={(() => { const pan = (selectedCommand as FadeCommand).pan ?? 0; return Math.max(-1, Math.min(1, pan)); })()}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { pan: 0 });
                              const soundId = (selectedCommand as FadeCommand).soundId;
                              const audioObjects = soundAudioMap.current.get(soundId);
                              if (audioObjects) {
                                audioObjects.forEach(obj => {
                                  if (obj.panNode) {
                                    obj.panNode.pan.value = 0;
                                  }
                                });
                              }
                            }
                          });
                        }}
                        onChange={(e) => {
                          const newPan = parseFloat(e.target.value);
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, {
                              pan: Math.max(-1, Math.min(1, newPan)),
                            });

                            const soundId = (selectedCommand as FadeCommand).soundId;
                            const audioObjects = soundAudioMap.current.get(soundId);
                            if (audioObjects) {
                              audioObjects.forEach(obj => {
                                if (obj.panNode) {
                                  obj.panNode.pan.value = newPan;
                                }
                              });
                            }
                          }
                        }}
                        style={{ flex: 1 }}
                      />
                    </div>
                  </label>

                  <label>
                    FADE DURATION (MS)
                    <input
                      type="text"
                      inputMode="numeric"
                      value={(selectedCommand as FadeCommand).duration ?? ""}
                      placeholder="0"
                      onMouseDown={(e) => {
                        handleResetOnModifierClick(e, () => {
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, { duration: 0 });
                          }
                        });
                      }}
                      onChange={(e) =>
                        selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                          duration: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                        })
                      }
                      onFocus={(e) => e.target.select()}
                    />
                  </label>

                  <label>
                    DELAY (MS)
                    <input
                      type="text"
                      inputMode="numeric"
                      value={(selectedCommand as FadeCommand).delay ?? ""}
                      placeholder="0"
                      onMouseDown={(e) => {
                        handleResetOnModifierClick(e, () => {
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, { delay: 0 });
                          }
                        });
                      }}
                      onChange={(e) =>
                        selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                          delay: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                        })
                      }
                      onFocus={(e) => e.target.select()}
                    />
                  </label>
                </>
              )}

              {selectedCommand && selectedCommand.type === "Execute" && (
                <>
                  <label>
                    EVENT TO EXECUTE
                    <select
                      value={(selectedCommand as ExecuteCommand).eventId || ""}
                      onChange={(e) =>
                        selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, { eventId: e.target.value })
                      }
                    >
                      <option value="">-- Select Event --</option>
                      {project?.events
                        .filter(evt => evt.eventName !== selectedEvent?.eventName) // Don't allow executing itself
                        .map((evt) => (
                          <option key={evt.id} value={evt.eventName}>
                            {evt.eventName}
                          </option>
                        ))}
                    </select>
                  </label>

                  <label>
                    VOLUME
                    <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                      <input
                        type="text"
                        inputMode="decimal"
                        value={(selectedCommand as ExecuteCommand).volume ?? ""}
                        placeholder="1"
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { volume: 1 });
                            }
                          });
                        }}
                        onChange={(e) => {
                          const value = e.target.value.replace(',', '.');
                          if (selectedCommandIndex !== null) {
                            if (value === "") {
                              handleUpdateCommand(selectedCommandIndex, { volume: undefined });
                            } else {
                              const numValue = parseFloat(value);
                              if (!isNaN(numValue)) {
                                handleUpdateCommand(selectedCommandIndex, { volume: Math.max(0, Math.min(1, numValue)) });
                              }
                            }
                          }
                        }}
                        onFocus={(e) => e.target.select()}
                        style={{ width: "60px" }}
                      />
                      <input
                        type="range"
                        step="0.01"
                        min="0"
                        max="100"
                        value={(() => {
                          const vol = (selectedCommand as ExecuteCommand).volume ?? 1;
                          return vol === 0 ? 0 : Math.log10(vol * 9 + 1) * 100;
                        })()}
                        onMouseDown={(e) => {
                          handleResetOnModifierClick(e, () => {
                            if (selectedCommandIndex !== null) {
                              handleUpdateCommand(selectedCommandIndex, { volume: 1 });
                            }
                          });
                        }}
                        onChange={(e) => {
                          const sliderValue = parseFloat(e.target.value);
                          const rawVolume = sliderValue === 0 ? 0 : (Math.pow(10, sliderValue / 100) - 1) / 9;
                          const newVolume = Math.round(rawVolume * 100) / 100;
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, {
                              volume: newVolume,
                            });
                          }
                        }}
                        style={{ flex: 1 }}
                      />
                    </div>
                  </label>

                  <label>
                    FADE DURATION (MS)
                    <input
                      type="text"
                      inputMode="numeric"
                      value={(selectedCommand as ExecuteCommand).fadeDuration ?? ""}
                      placeholder="0"
                      onMouseDown={(e) => {
                        handleResetOnModifierClick(e, () => {
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, { fadeDuration: 0 });
                          }
                        });
                      }}
                      onChange={(e) =>
                        selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                          fadeDuration: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                        })
                      }
                      onFocus={(e) => e.target.select()}
                    />
                  </label>

                  <label>
                    DELAY (MS)
                    <input
                      type="text"
                      inputMode="numeric"
                      value={(selectedCommand as ExecuteCommand).delay ?? ""}
                      placeholder="0"
                      onMouseDown={(e) => {
                        handleResetOnModifierClick(e, () => {
                          if (selectedCommandIndex !== null) {
                            handleUpdateCommand(selectedCommandIndex, { delay: 0 });
                          }
                        });
                      }}
                      onChange={(e) =>
                        selectedCommandIndex !== null && handleUpdateCommand(selectedCommandIndex, {
                          delay: e.target.value === "" ? undefined : parseInt(e.target.value) || 0,
                        })
                      }
                      onFocus={(e) => e.target.select()}
                    />
                  </label>
                </>
              )}
            </div>
          ) : (
            <div className="empty-inspector">
              <p>{viewMode === 'sounds' ? 'No sound selected' : 'No command selected'}</p>
            </div>
          )}
        </div>
      </div>
      </div>

      {/* Validation Dialog */}
      {validationDialog && (
        <ValidationDialog
          data={validationDialog}
          project={project}
          audioFiles={audioFiles}
          onClose={() => setValidationDialog(null)}
          onProjectUpdate={(updatedProject) => {
            setProject(updatedProject);
            saveToHistory(updatedProject);
          }}
          onExport={() => {
            if (project) {
              exportTemplateJson(project);
            }
          }}
        />
      )}



      {/* DAW Timeline - Fullscreen View */}
        {viewMode === 'timeline' && (
          <div style={{
            position: 'absolute',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            display: 'flex',
            flexDirection: 'column',
            backgroundColor: '#0d0d0d',
            zIndex: 10
          }}>
            {/* Timeline Header with back button */}
            <div style={{
              height: '40px',
              backgroundColor: '#1a1a1a',
              borderBottom: '1px solid #333',
              display: 'flex',
              alignItems: 'center',
              padding: '0 12px',
              gap: '12px'
            }}>
              <button
                onClick={() => setViewMode('events')}
                style={{
                  padding: '6px 12px',
                  backgroundColor: '#333',
                  border: 'none',
                  borderRadius: '4px',
                  color: '#fff',
                  fontSize: '11px',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '6px'
                }}
              >
                ← Back
              </button>
              <span style={{ fontSize: '14px', fontWeight: 600, color: '#fff' }}>DAW Timeline</span>
              <div style={{ flex: 1 }} />
              <span style={{ fontSize: '11px', color: '#666' }}>
                {arrangement.tracks.length} tracks • {arrangement.clips.length} clips
              </span>
            </div>

            {/* Transport Bar */}
            <TransportBar
              isPlaying={isPlaying}
              isRecording={false}
              currentTime={dawPlayhead * (60 / dawTempo)}
              duration={64 * (60 / dawTempo)}
              tempo={dawTempo}
              timeSignature={dawTimeSignature}
              loopEnabled={dawLoopEnabled}
              loopStart={dawLoopStart * (60 / dawTempo)}
              loopEnd={dawLoopEnd * (60 / dawTempo)}
              metronomeEnabled={dawMetronome}
              onPlay={() => setIsPlaying(true)}
              onPause={() => setIsPlaying(false)}
              onStop={() => {
                setIsPlaying(false);
                setDawPlayhead(0);
                audioEngine.stopAllAudio();
              }}
              onRecord={() => {}}
              onRewind={() => setDawPlayhead(0)}
              onForward={() => setDawPlayhead(prev => Math.min(prev + 4, 64))}
              onTempoChange={setDawTempo}
              onLoopToggle={() => setDawLoopEnabled(prev => !prev)}
              onMetronomeToggle={() => setDawMetronome(prev => !prev)}
            />

            {/* DAW Arrangement View */}
            <div style={{ flex: 1, position: 'relative', overflow: 'hidden' }}>
              <Arrangement
                tracks={arrangement.tracks}
                clips={arrangement.clips}
                markers={arrangement.markers}
                onTracksChange={arrangement.setTracks}
                onClipsChange={arrangement.setClips}
                length={64}
                beatsPerBar={dawTimeSignature[0]}
                pixelsPerBeat={20}
                trackHeight={80}
                snap={1}
                playhead={dawPlayhead}
                loopStart={dawLoopEnabled ? dawLoopStart : undefined}
                loopEnd={dawLoopEnabled ? dawLoopEnd : undefined}
                onPlayheadChange={setDawPlayhead}
                onClipSelect={(ids) => arrangement.selectClips(ids)}
                onTrackSelect={(id) => arrangement.setSelectedTrack(id)}
                trackControlsWidth={200}
                headerHeight={40}
              />
            </div>

            {/* Toolbar */}
            <div style={{
              height: '36px',
              backgroundColor: '#1a1a1a',
              borderTop: '1px solid #333',
              display: 'flex',
              alignItems: 'center',
              padding: '0 12px',
              gap: '8px',
              fontSize: '11px',
              color: '#888'
            }}>
              <button
                onClick={() => arrangement.addTrack({ name: `Track ${arrangement.tracks.length + 1}`, type: 'audio', color: '#6366f1' })}
                style={{
                  padding: '4px 8px',
                  backgroundColor: '#2563eb',
                  border: 'none',
                  borderRadius: '4px',
                  color: '#fff',
                  fontSize: '11px',
                  cursor: 'pointer'
                }}
              >
                + Add Track
              </button>
              <span>|</span>
              <span>Tracks: {arrangement.tracks.length}</span>
              <span>Clips: {arrangement.clips.length}</span>
              {arrangement.selectedClips.length > 0 && (
                <>
                  <span>|</span>
                  <span>Selected: {arrangement.selectedClips.length}</span>
                  <button
                    onClick={arrangement.deleteSelectedClips}
                    style={{
                      padding: '4px 8px',
                      backgroundColor: '#dc2626',
                      border: 'none',
                      borderRadius: '4px',
                      color: '#fff',
                      fontSize: '11px',
                      cursor: 'pointer'
                    }}
                  >
                    Delete
                  </button>
                </>
              )}
              <div style={{ flex: 1 }} />
              <span>Snap: 1 beat</span>
              <span>|</span>
              <span>Zoom: 20px/beat</span>
            </div>
          </div>
        )}

      <DetachableMixer
        onBusChange={handleBusChange}
        onPinnedChange={setIsMixerPinned}
        onDetachedChange={setIsMixerDetached}
        detachedWindowRef={detachedWindowRef}
      />
    </div>
    </AssetInsertProvider>
    </BusInsertProvider>
    </MasterInsertProvider>
  );
}
