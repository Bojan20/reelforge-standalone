// FluxForge Studio DAW - Flutter Frontend
//
// Professional digital audio workstation with:
// - Cubase-inspired multi-zone layout
// - GPU-accelerated waveforms and spectrum
// - 120fps smooth animations
// - Rust audio engine via flutter_rust_bridge

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/fluxforge_theme.dart';
import 'screens/engine_connected_layout.dart';
import 'screens/launcher_screen.dart';
import 'screens/daw_hub_screen.dart';
// middleware_hub_screen removed — SlotLab is unified
import 'providers/engine_provider.dart';
import 'providers/timeline_playback_provider.dart';
import 'providers/mixer_dsp_provider.dart';
import 'providers/meter_provider.dart';
import 'providers/mixer_provider.dart';
import 'providers/editor_mode_provider.dart' show EditorModeProvider, EditorMode;
import 'models/layout_models.dart' as layout;
import 'providers/global_shortcuts_provider.dart' show GlobalShortcutsProvider, ShortcutAction;
import 'providers/project_history_provider.dart';
import 'providers/auto_save_provider.dart';
import 'providers/audio_export_provider.dart';
import 'providers/session_persistence_provider.dart';
import 'providers/input_bus_provider.dart';
import 'providers/recording_provider.dart';
import 'providers/routing_provider.dart';
import 'providers/keyboard_focus_provider.dart';
import 'providers/edit_mode_pro_provider.dart';
import 'providers/smart_tool_provider.dart';
import 'providers/razor_edit_provider.dart';
import 'providers/direct_offline_processing_provider.dart';
import 'providers/modulator_provider.dart';
import 'providers/arranger_track_provider.dart';
import 'providers/chord_track_provider.dart';
import 'providers/expression_map_provider.dart';
import 'providers/macro_control_provider.dart';
import 'providers/track_versions_provider.dart';
import 'providers/clip_gain_envelope_provider.dart';
import 'providers/logical_editor_provider.dart';
import 'providers/groove_quantize_provider.dart';
import 'providers/audio_alignment_provider.dart';
import 'providers/scale_assistant_provider.dart';
import 'providers/error_provider.dart';
import 'providers/recent_projects_provider.dart';
import 'providers/plugin_provider.dart';
import 'providers/control_room_provider.dart';
import 'providers/middleware_provider.dart';
import 'providers/stage_provider.dart';
import 'providers/stage_ingest_provider.dart';
import 'providers/slot_lab/slot_lab_coordinator.dart';
import 'providers/slot_lab/slot_voice_mixer_provider.dart';
import 'providers/slot_lab/game_flow_provider.dart';
import 'providers/slot_lab_project_provider.dart';
import 'providers/ale_provider.dart';
import 'providers/soundbank_provider.dart';
import 'providers/feature_builder_provider.dart';
import 'services/audio_asset_manager.dart';
import 'services/event_registry.dart';
import 'providers/custom_event_provider.dart';
import 'providers/video_provider.dart';
import 'services/video_export_service.dart';
import 'services/video_playback_service.dart';
import 'package:media_kit/media_kit.dart';
import 'services/service_locator.dart';
import 'services/lower_zone_persistence_service.dart';
import 'services/event_sync_service.dart';
import 'services/stage_configuration_service.dart';
import 'services/workspace_preset_service.dart';
import 'services/offline_service.dart';
import 'services/localization_service.dart';
import 'services/asset_cloud_service.dart';
import 'services/crdt_sync_service.dart';
import 'services/cortex_vision_service.dart';
import 'services/cortex_eye_server.dart';
import 'services/cortex_intelligence_loop.dart';
import 'services/cortex_log_buffer.dart';
import 'providers/cortex_provider.dart';
import 'providers/rgai_ffi_provider.dart';
import 'providers/slot_spatial_provider.dart';
import 'providers/ab_sim_provider.dart';
import 'providers/slot_export_provider.dart';
import 'providers/sfx_pipeline_provider.dart';
import 'providers/selection_provider.dart';
import 'providers/selection_memory_provider.dart';
import 'utils/path_validator.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'services/feature_builder/feature_block_registry.dart';
import 'blocks/game_core_block.dart';
import 'blocks/grid_block.dart';
import 'blocks/symbol_set_block.dart';
import 'blocks/free_spins_block.dart';
import 'blocks/respin_block.dart';
import 'blocks/hold_and_win_block.dart';
import 'blocks/cascades_block.dart';
import 'blocks/collector_block.dart';
import 'blocks/win_presentation_block.dart';
import 'blocks/music_states_block.dart';
import 'blocks/anticipation_block.dart';
import 'blocks/jackpot_block.dart';
import 'blocks/multiplier_block.dart';
import 'blocks/bonus_game_block.dart';
import 'blocks/wild_features_block.dart';
import 'blocks/transitions_block.dart';
import 'blocks/gambling_block.dart';
import 'providers/warp_state_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════
  // CORTEX Log Buffer — mora biti prvi, hvata SVE što dolazi posle
  // ══════════════════════════════════════════════════════════════════════
  CortexLogBuffer.instance.init();

  // Kill orphan afplay child processes on app exit (SIGTERM/SIGINT from Cmd+Q)
  // Uses -P to only kill afplay processes that are children of this process
  final myPid = pid.toString();
  ProcessSignal.sigterm.watch().listen((_) {
    Process.runSync('pkill', ['-P', myPid, 'afplay']);
  });
  ProcessSignal.sigint.watch().listen((_) {
    Process.runSync('pkill', ['-P', myPid, 'afplay']);
  });

  // Initialize media_kit for cross-platform video playback
  MediaKit.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════════
  // P12.0.4: INITIALIZE PATH VALIDATOR SANDBOX — CRITICAL SECURITY
  // ═══════════════════════════════════════════════════════════════════════════
  // MUST be called before any file operations to prevent path traversal attacks
  final projectRoot = Directory.current.path;
  final homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  // Use ~/Library/Application Support — NOT TCC-protected (no permission dialogs).
  // ~/Documents and ~/Music trigger macOS TCC prompts at startup.
  // User-chosen paths (via NSOpenPanel) are added to sandbox dynamically.
  final additionalRoots = <String>[
    if (homeDir.isNotEmpty) p.join(homeDir, 'Library', 'Application Support', 'FluxForge Studio'),
  ];

  PathValidator.initializeSandbox(
    projectRoot: projectRoot,
    additionalRoots: additionalRoots,
  );

  // Initialize dependency injection (GetIt)
  await ServiceLocator.init();

  // Initialize Lower Zone persistence (SharedPreferences)
  await LowerZonePersistenceService.instance.init();

  // Initialize Stage Configuration Service (centralized stage definitions)
  StageConfigurationService.instance.init();

  // Initialize Workspace Preset Service (layout presets)
  await WorkspacePresetService.instance.init();

  // Initialize Selection Memory Service (SPEC-15: Cmd+1..9 layout slots)
  await sl<SelectionMemoryProvider>().init();

  // Initialize Localization Service (P3-08)
  await LocalizationService.instance.init();

  // Initialize Offline Service (P3-14)
  await OfflineService.instance.init();

  // Initialize Asset Cloud Service (P3-06)
  await AssetCloudService.instance.init();

  // Initialize CRDT Sync Service (P3-13)
  await CrdtSyncService.instance.init();

  // Initialize CORTEX Vision Service (The Eyes of the Organism)
  await CortexVisionService.instance.init();

  // Start CORTEX Eye HTTP Server (localhost:7735 — gives Claude Code eyes)
  await CortexEyeServer.instance.start();

  // P13.9.8: Initialize Feature Block Registry with all 17 blocks
  FeatureBlockRegistry.instance.initialize([
    () => GameCoreBlock(),
    () => GridBlock(),
    () => SymbolSetBlock(),
    () => FreeSpinsBlock(),
    () => RespinBlock(),
    () => HoldAndWinBlock(),
    () => CascadesBlock(),
    () => CollectorBlock(),
    () => WinPresentationBlock(),
    () => MusicStatesBlock(),
    () => AnticipationBlock(),
    () => JackpotBlock(),
    () => MultiplierBlock(),
    () => BonusGameBlock(),
    () => WildFeaturesBlock(),
    () => TransitionsBlock(),
    () => GamblingBlock(),
  ]);

  runApp(const FluxForgeApp());
}

class FluxForgeApp extends StatelessWidget {
  const FluxForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // All providers are GetIt singletons per CLAUDE.md:
        // "Provideri MORAJU biti GetIt singletoni" (FFI resource sharing)

        // Rust Engine (core audio backend)
        ChangeNotifierProvider<EngineProvider>.value(value: sl<EngineProvider>()),

        // Core playback state
        ChangeNotifierProvider<TimelinePlaybackProvider>.value(
          value: sl<TimelinePlaybackProvider>(),
        ),

        // Mixer and DSP routing
        ChangeNotifierProvider<MixerDSPProvider>.value(value: sl<MixerDSPProvider>()),

        // Real-time metering
        ChangeNotifierProvider<MeterProvider>.value(value: sl<MeterProvider>()),

        // Pro DAW Mixer state
        ChangeNotifierProvider<MixerProvider>.value(value: sl<MixerProvider>()),

        // Editor mode (DAW/Middleware)
        ChangeNotifierProvider<EditorModeProvider>.value(
          value: sl<EditorModeProvider>(),
        ),

        // Keyboard shortcuts
        ChangeNotifierProvider<GlobalShortcutsProvider>.value(
          value: sl<GlobalShortcutsProvider>(),
        ),

        // Undo/Redo history
        ChangeNotifierProvider<ProjectHistoryProvider>.value(
          value: sl<ProjectHistoryProvider>(),
        ),

        // Auto-save
        ChangeNotifierProvider<AutoSaveProvider>.value(value: sl<AutoSaveProvider>()),

        // Recent Projects
        ChangeNotifierProvider<RecentProjectsProvider>.value(
          value: sl<RecentProjectsProvider>(),
        ),

        // Audio export
        ChangeNotifierProvider<AudioExportProvider>.value(
          value: sl<AudioExportProvider>(),
        ),

        // Session persistence
        ChangeNotifierProvider<SessionPersistenceProvider>.value(
          value: sl<SessionPersistenceProvider>(),
        ),

        // Input Bus System
        ChangeNotifierProvider<InputBusProvider>.value(value: sl<InputBusProvider>()),

        // Recording System
        ChangeNotifierProvider<RecordingProvider>.value(value: sl<RecordingProvider>()),

        // Unified Routing System
        ChangeNotifierProvider<RoutingProvider>.value(value: sl<RoutingProvider>()),

        // Pro Tools-Style Keyboard Focus Mode
        ChangeNotifierProvider<KeyboardFocusProvider>.value(
          value: sl<KeyboardFocusProvider>(),
        ),

        // Pro Tools-Style Edit Modes (Shuffle/Slip/Spot/Grid)
        ChangeNotifierProvider<EditModeProProvider>.value(
          value: sl<EditModeProProvider>(),
        ),

        // Smart Tool (Context-Aware Tool Selection)
        ChangeNotifierProvider<SmartToolProvider>.value(value: sl<SmartToolProvider>()),

        // Razor Editing (Cubase-style range selection)
        ChangeNotifierProvider<RazorEditProvider>.value(value: sl<RazorEditProvider>()),

        // Direct Offline Processing
        ChangeNotifierProvider<DirectOfflineProcessingProvider>.value(
          value: sl<DirectOfflineProcessingProvider>(),
        ),

        // Parameter Modulators (LFO, Envelope Follower, Step, Random)
        ChangeNotifierProvider<ModulatorProvider>.value(value: sl<ModulatorProvider>()),

        // Arranger Track (Cubase-style section-based arrangement)
        ChangeNotifierProvider<ArrangerTrackProvider>.value(
          value: sl<ArrangerTrackProvider>(),
        ),

        // Chord Track (Cubase-style chord intelligence)
        ChangeNotifierProvider<ChordTrackProvider>.value(value: sl<ChordTrackProvider>()),

        // Expression Maps (Cubase-style MIDI articulation switching)
        ChangeNotifierProvider<ExpressionMapProvider>.value(
          value: sl<ExpressionMapProvider>(),
        ),

        // Macro Controls (Multi-parameter control knobs)
        ChangeNotifierProvider<MacroControlProvider>.value(
          value: sl<MacroControlProvider>(),
        ),

        // Track Versions (Cubase-style track playlists)
        ChangeNotifierProvider<TrackVersionsProvider>.value(
          value: sl<TrackVersionsProvider>(),
        ),

        // Clip Gain Envelope (Per-clip gain automation)
        ChangeNotifierProvider<ClipGainEnvelopeProvider>.value(
          value: sl<ClipGainEnvelopeProvider>(),
        ),

        // Logical Editor (Cubase-style batch operations)
        ChangeNotifierProvider<LogicalEditorProvider>.value(
          value: sl<LogicalEditorProvider>(),
        ),

        // Groove Quantize (Humanization and groove templates)
        ChangeNotifierProvider<GrooveQuantizeProvider>.value(
          value: sl<GrooveQuantizeProvider>(),
        ),

        // Audio Alignment (VocAlign-style alignment)
        ChangeNotifierProvider<AudioAlignmentProvider>.value(
          value: sl<AudioAlignmentProvider>(),
        ),

        // Scale Assistant (Cubase-style key/scale helper)
        ChangeNotifierProvider<ScaleAssistantProvider>.value(
          value: sl<ScaleAssistantProvider>(),
        ),

        // Warp Markers State (Phase 4-5)
        ChangeNotifierProvider<WarpStateProvider>.value(value: sl<WarpStateProvider>()),

        // Error Handling
        ChangeNotifierProvider<ErrorProvider>.value(value: sl<ErrorProvider>()),

        // Plugin Browser & Hosting
        ChangeNotifierProvider<PluginProvider>.value(value: sl<PluginProvider>()),

        // Control Room (Studio Monitoring)
        ChangeNotifierProvider<ControlRoomProvider>.value(
          value: sl<ControlRoomProvider>(),
        ),

        // Middleware (States, Switches, RTPC, Ducking, Containers, Music System)
        ChangeNotifierProvider<MiddlewareProvider>.value(
          value: sl<MiddlewareProvider>(),
        ),

        // Stage Ingest System (Legacy — uses Dart models)
        ChangeNotifierProvider<StageProvider>.value(value: sl<StageProvider>()),

        // Stage Ingest System (New — FFI-based with rf-stage/rf-ingest/rf-connector)
        ChangeNotifierProvider<StageIngestProvider>.value(
          value: sl<StageIngestProvider>(),
        ),

        // Slot Lab (Synthetic Slot Engine) — MUST use GetIt singleton, not new instance
        ChangeNotifierProvider<SlotLabProvider>.value(
          value: sl<SlotLabCoordinator>(),
        ),

        // Game Flow FSM (L3 Modular Slot Machine State Machine)
        ChangeNotifierProvider.value(value: sl<GameFlowProvider>()),

        // Slot Lab Project (V6 Layout state) — MUST use GetIt singleton, not new instance
        ChangeNotifierProvider<SlotLabProjectProvider>.value(
          value: sl<SlotLabProjectProvider>(),
        ),

        // Adaptive Layer Engine (ALE) — MUST use GetIt singleton, not new instance
        ChangeNotifierProvider<AleProvider>.value(
          value: sl<AleProvider>(),
        ),

        // SlotLab Voice Mixer — MUST use GetIt singleton, not new instance
        ChangeNotifierProvider<SlotVoiceMixerProvider>.value(
          value: sl<SlotVoiceMixerProvider>(),
        ),

        // Unified Audio Asset Manager (SINGLE SOURCE OF TRUTH)
        ChangeNotifierProvider.value(value: AudioAssetManager.instance),

        // Soundbank Building System
        ChangeNotifierProvider<SoundbankProvider>.value(
          value: sl<SoundbankProvider>(),
        ),

        // Event Registry (Stage → Audio mapping)
        ChangeNotifierProvider.value(value: EventRegistry.instance),

        // Feature Builder Provider (P13) — MUST use GetIt singleton, not new instance
        ChangeNotifierProvider<FeatureBuilderProvider>.value(
          value: sl<FeatureBuilderProvider>(),
        ),

        // Custom Event Provider (SlotLab CUSTOM tab) — GetIt singleton
        ChangeNotifierProvider<CustomEventProvider>.value(
          value: sl<CustomEventProvider>(),
        ),

        // CORTEX Reactive Nervous System — GetIt singleton
        ChangeNotifierProvider<CortexProvider>.value(
          value: sl<CortexProvider>(),
        ),

        // Video System — GetIt singletons
        ChangeNotifierProvider<VideoProvider>.value(
          value: sl<VideoProvider>(),
        ),
        ChangeNotifierProvider<VideoExportService>.value(
          value: sl<VideoExportService>(),
        ),
        ChangeNotifierProvider<VideoPlaybackService>.value(
          value: sl<VideoPlaybackService>(),
        ),

        // ═══ FFI-backed providers (real Rust engine delegates) ═══
        ChangeNotifierProvider<RgaiFfiProvider>.value(
          value: sl<RgaiFfiProvider>(),
        ),
        ChangeNotifierProvider<SlotSpatialProvider>.value(
          value: sl<SlotSpatialProvider>(),
        ),
        ChangeNotifierProvider<AbSimProvider>.value(
          value: sl<AbSimProvider>(),
        ),
        ChangeNotifierProvider<SlotExportProvider>.value(
          value: sl<SlotExportProvider>(),
        ),
        ChangeNotifierProvider<SfxPipelineProvider>.value(
          value: sl<SfxPipelineProvider>(),
        ),

        // SPEC-03/04: Selection Provider — single source of truth for adaptive UI
        ChangeNotifierProvider<SelectionProvider>.value(
          value: sl<SelectionProvider>(),
        ),

        // SPEC-15: Selection Memory Provider — layout snapshot slots (Cmd+1..9)
        ChangeNotifierProvider<SelectionMemoryProvider>.value(
          value: sl<SelectionMemoryProvider>(),
        ),
      ],
      child: RepaintBoundary(
        key: CortexVisionService.instance.rootBoundaryKey,
        child: MaterialApp(
          title: 'FluxForge Studio',
          debugShowCheckedModeBanner: false,
          theme: FluxForgeTheme.darkTheme,
          initialRoute: '/',
          routes: {
            '/': (context) => const _AppInitializer(),
          },
        ),
      ),
    );
  }
}

/// Initializes providers that need setup and shows loading state
class _AppInitializer extends StatefulWidget {
  const _AppInitializer();

  @override
  State<_AppInitializer> createState() => _AppInitializerState();
}

enum _AppState { launcher, dawHub, main, slotLab }

class _AppInitializerState extends State<_AppInitializer> {
  _AppState _appState = _AppState.launcher;
  bool _engineReady = false;
  String? _error;
  String? _projectName;
  AppMode? _selectedMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    try {
      // Phase 1: Initialize Rust engine
      final engine = context.read<EngineProvider>();
      await engine.initialize();

      // Phase 2: Initialize providers
      if (!mounted) return;
      final shortcuts = context.read<GlobalShortcutsProvider>();
      final history = context.read<ProjectHistoryProvider>();

      // Phase 2.5: Initialize plugin host
      final pluginProvider = context.read<PluginProvider>();
      await pluginProvider.init();

      // Phase 3: Wire up shortcuts
      final actions = ShortcutAction();
      actions.onPlayPause = () {
        if (engine.transport.isPlaying) {
          engine.pause();
        } else {
          engine.play();
        }
      };
      actions.onStop = () => engine.stop();
      actions.onGoToStart = () => engine.goToStart();
      actions.onUndo = () {
        engine.undo();
        history.undo();
      };
      actions.onRedo = () {
        engine.redo();
        history.redo();
      };
      shortcuts.setActions(actions);

      // Phase 3.5: Register keyboard focus handlers (Pro Tools-style commands)
      _registerKeyboardHandlers(context, engine, history);

      // Phase 4: Activate EventSyncService (EventRegistry ↔ MiddlewareProvider)
      // CRITICAL: Use global `eventRegistry` (same instance as SlotLab), NOT EventRegistry.instance
      if (mounted) {
        final middleware = context.read<MiddlewareProvider>();
        getEventSyncService(eventRegistry, middleware);
      }

      // Phase 4.5: Start CORTEX reactive event stream
      if (mounted) {
        sl<CortexProvider>().start();
      }

      // Phase 5: Register CORTEX Vision regions (The Eyes)
      final vision = CortexVisionService.instance;
      vision.registerRegion(
        name: 'timeline',
        description: 'DAW timeline with tracks, clips, and waveforms',
      );
      vision.registerRegion(
        name: 'mixer',
        description: 'Mixer panel with faders, meters, and routing',
      );
      vision.registerRegion(
        name: 'slot_lab',
        description: 'SlotLab workspace with stages and events',
      );
      vision.registerRegion(
        name: 'lower_zone',
        description: 'Lower zone panels (editor, mixer, plugins)',
      );
      vision.registerRegion(
        name: 'transport',
        description: 'Transport controls and position display',
      );

      // Start auto-observation — CORTEX watches the app every 10s
      vision.startObserving();

      // Phase 5.5: Wire CORTEX Intelligence Loop (Eyes + Brain + Hands)
      if (mounted) {
        final mixer = context.read<MixerProvider>();
        final intelligence = CortexIntelligenceLoop.instance;
        intelligence.connect(mixer);
        intelligence.start(); // 30s cycle: capture → analyze → suggest
      }

      // Phase 6: Register CortexEye navigation handler (CORTEX can navigate the app)
      CortexEyeNav.instance.onNavigate = (destination) {
        if (!mounted) return;
        switch (destination) {
          case 'slotlab':
            _handleModeSelected(AppMode.slotLab);
          case 'daw':
            _handleModeSelected(AppMode.daw);
          case 'daw_workspace':
            // Diagnostic path: enter DAW hub → create ephemeral project → enter workspace.
            // Allows CORTEX to verify the workspace renders without needing AX click access.
            _handleModeSelected(AppMode.daw);
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) _handleNewProject('_CortexEyeProbe');
            });
          case 'launcher':
            _handleBackToLauncher();
          case 'helix':
            // HELIX is a panel within SLOTLAB — navigate there first
            _handleModeSelected(AppMode.slotLab);
          default:
            debugPrint('[CortexEye] Unknown nav destination: $destination');
        }
      };

      // Phase 7: Engine ready — enable launcher buttons
      if (mounted) {
        setState(() => _engineReady = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  /// Register keyboard focus handlers for Pro Tools-style commands
  void _registerKeyboardHandlers(
    BuildContext context,
    EngineProvider engine,
    ProjectHistoryProvider history,
  ) {
    final keyboard = context.read<KeyboardFocusProvider>();
    final timeline = context.read<TimelinePlaybackProvider>();

    final razor = context.read<RazorEditProvider>();
    final editMode = context.read<EditModeProProvider>();
    final smartTool = context.read<SmartToolProvider>();
    final recording = context.read<RecordingProvider>();

    keyboard.registerHandlers({
      // Clipboard operations — RazorEditProvider
      KeyboardCommand.copy: () => razor.copySelection(),
      KeyboardCommand.cut: () => razor.cutSelection(),
      KeyboardCommand.paste: () => razor.pasteAtCursor(),

      // Edit operations — RazorEditProvider
      KeyboardCommand.duplicate: () => razor.executeAction(RazorAction.bounce),
      KeyboardCommand.separate: () => razor.splitAtSelection(),
      KeyboardCommand.joinClips: () => razor.joinClips(),
      KeyboardCommand.muteClip: () => razor.muteSelection(),

      // Undo/Redo
      KeyboardCommand.redo: () {
        engine.redo();
        history.redo();
      },

      // Transport
      KeyboardCommand.play: () {
        if (engine.transport.isPlaying) {
          engine.pause();
        } else {
          engine.play();
        }
      },
      KeyboardCommand.stop: () => engine.stop(),
      KeyboardCommand.loopPlayback: () => timeline.toggleLoop(),

      // Navigation — seek by small increments
      KeyboardCommand.nextClip: () {
        final pos = timeline.currentTime;
        timeline.seek(pos + 1.0); // Jump 1 second forward
      },
      KeyboardCommand.previousClip: () {
        final pos = timeline.currentTime;
        timeline.seek((pos - 1.0).clamp(0.0, double.infinity));
      },
      KeyboardCommand.nudgeLeft: () {
        final pos = timeline.currentTime;
        timeline.seek((pos - 0.1).clamp(0.0, double.infinity));
      },
      KeyboardCommand.nudgeRight: () {
        final pos = timeline.currentTime;
        timeline.seek(pos + 0.1);
      },

      // Tools — SmartToolProvider (Pro Tools E/T/F/Z commands)
      KeyboardCommand.editTool: () {
        smartTool.setActiveTool(TimelineEditTool.objectSelect);
      },
      KeyboardCommand.trimTool: () {
        smartTool.setActiveTool(TimelineEditTool.smart);
      },
      KeyboardCommand.fadeTool: () {
        smartTool.setActiveTool(TimelineEditTool.smart);
        smartTool.setActiveEditMode(TimelineEditMode.xFade);
      },
      KeyboardCommand.zoomTool: () {
        smartTool.setActiveTool(TimelineEditTool.zoom);
      },

      // Grid/snap — EditModeProProvider
      KeyboardCommand.gridToggle: () => editMode.toggleGrid(),
      KeyboardCommand.quantize: () => editMode.toggleTriplet(),

      // Other edit operations
      KeyboardCommand.fadeBoth: () => razor.fadeBothEnds(),
      KeyboardCommand.healSeparation: () => razor.healSeparation(),
      KeyboardCommand.insertSilence: () => razor.insertSilence(),
      KeyboardCommand.trimEndToCursor: () => razor.executeAction(RazorAction.split),
      KeyboardCommand.stripSilence: () => razor.stripSilence(),
      KeyboardCommand.renameClip: () => razor.executeAction(RazorAction.process),

      // Automation — toggle recording mode
      KeyboardCommand.toggleAutomation: () {
        // AutomationProvider not in MultiProvider tree yet — no-op
      },

      // Plugin — toggle smart tool (repurposed)
      KeyboardCommand.openPlugin: () => smartTool.toggle(),

      // Window
      KeyboardCommand.closeWindow: () {
        // Handled by platform — no-op here
      },

      // Record — RecordingProvider
      KeyboardCommand.record: () async {
        if (recording.isRecording) {
          await recording.stopRecording();
        } else {
          await recording.startRecording();
        }
      },

      // Escape (handled by KeyboardFocusProvider itself)
      KeyboardCommand.escape: null,
    });

  }

  void _retry() {
    setState(() {
      _error = null;
      _engineReady = false;
      _appState = _AppState.launcher;
    });
    _initializeApp();
  }

  void _handleModeSelected(AppMode mode) {
    setState(() {
      _selectedMode = mode;
      if (mode == AppMode.slotLab) {
        _projectName = 'SlotLab Session';
        _appState = _AppState.slotLab;
      } else {
        // DAW mode - show DAW hub
        _appState = _AppState.dawHub;
      }
    });
  }

  void _handleNewProject(String name) {
    final engine = context.read<EngineProvider>();
    engine.newProject(name);
    setState(() {
      _projectName = name;
      _appState = _AppState.main;
    });
  }

  Future<void> _handleOpenProject(String path) async {
    final engine = context.read<EngineProvider>();
    final success = await engine.loadProject(path);
    if (!success) return;
    setState(() {
      _projectName = path.split('/').last.replaceAll('.rfp', '');
      _appState = _AppState.main;
    });
  }

  void _handleBackToLauncher() {
    setState(() {
      _appState = _AppState.launcher;
      _selectedMode = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_appState) {
      case _AppState.launcher:
        return LauncherScreen(
          onModeSelected: _handleModeSelected,
          isReady: _engineReady,
          errorMessage: _error,
          onRetry: _error != null ? _retry : null,
        );

      case _AppState.dawHub:
        return DawHubScreen(
          onNewProject: _handleNewProject,
          onOpenProject: _handleOpenProject,
          onBackToLauncher: _handleBackToLauncher,
        );

      case _AppState.main:
        return _DawLayout(
          onBackToLauncher: _handleBackToLauncher,
          projectName: _projectName,
        );

      case _AppState.slotLab:
        return _SlotLabLayout(
          onBackToLauncher: _handleBackToLauncher,
          projectName: _projectName,
        );
    }
  }
}

/// SlotLab-focused layout (uses EngineConnectedLayout with slot mode)
class _SlotLabLayout extends StatefulWidget {
  final VoidCallback onBackToLauncher;
  final String? projectName;

  const _SlotLabLayout({
    required this.onBackToLauncher,
    this.projectName,
  });

  @override
  State<_SlotLabLayout> createState() => _SlotLabLayoutState();
}

class _SlotLabLayoutState extends State<_SlotLabLayout> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editorMode = context.read<EditorModeProvider>();
      editorMode.setMode(EditorMode.slot);
    });
  }

  @override
  Widget build(BuildContext context) {
    return EngineConnectedLayout(
      projectName: widget.projectName,
      onBackToLauncher: widget.onBackToLauncher,
      initialEditorMode: layout.EditorMode.slot,
    );
  }
}

/// DAW-focused layout with back to launcher button
class _DawLayout extends StatefulWidget {
  final VoidCallback onBackToLauncher;
  final String? projectName;

  const _DawLayout({
    required this.onBackToLauncher,
    this.projectName,
  });

  @override
  State<_DawLayout> createState() => _DawLayoutState();
}

class _DawLayoutState extends State<_DawLayout> {
  @override
  void initState() {
    super.initState();
    // Ensure DAW mode on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editorMode = context.read<EditorModeProvider>();
      editorMode.setMode(EditorMode.daw);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Back button is now in header (ControlBar), not overlay
    return EngineConnectedLayout(
      projectName: widget.projectName,
      onBackToLauncher: widget.onBackToLauncher,
      initialEditorMode: layout.EditorMode.daw,
    );
  }
}

