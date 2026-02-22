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
import 'screens/middleware_hub_screen.dart';
import 'screens/eq_test_screen.dart';
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
import 'providers/slot_lab_project_provider.dart';
import 'providers/ale_provider.dart';
import 'providers/soundbank_provider.dart';
import 'providers/feature_builder_provider.dart';
import 'services/audio_asset_manager.dart';
import 'services/event_registry.dart';
import 'services/service_locator.dart';
import 'services/lower_zone_persistence_service.dart';
import 'services/stage_configuration_service.dart';
import 'services/workspace_preset_service.dart';
import 'services/analytics_service.dart';
import 'services/offline_service.dart';
import 'services/localization_service.dart';
import 'services/cloud_sync_service.dart';
import 'services/ai_mixing_service.dart';
import 'services/collaboration_service.dart';
import 'services/asset_cloud_service.dart';
import 'services/marketplace_service.dart';
import 'services/crdt_sync_service.dart';
import 'src/rust/native_ffi.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════════
  // P12.0.4: INITIALIZE PATH VALIDATOR SANDBOX — CRITICAL SECURITY
  // ═══════════════════════════════════════════════════════════════════════════
  // MUST be called before any file operations to prevent path traversal attacks
  final projectRoot = Directory.current.path;
  final homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  final additionalRoots = <String>[
    if (homeDir.isNotEmpty) p.join(homeDir, 'Documents', 'FluxForge Projects'),
    if (homeDir.isNotEmpty) p.join(homeDir, 'Music', 'FluxForge Audio'),
  ];

  PathValidator.initializeSandbox(
    projectRoot: projectRoot,
    additionalRoots: additionalRoots,
  );

  // Initialize dependency injection (GetIt)
  await ServiceLocator.init();

  // Initialize Analytics Service (usage tracking, P3-07)
  await AnalyticsService.instance.init();

  // Initialize Lower Zone persistence (SharedPreferences)
  await LowerZonePersistenceService.instance.init();

  // Initialize Stage Configuration Service (centralized stage definitions)
  StageConfigurationService.instance.init();

  // Initialize Workspace Preset Service (layout presets)
  await WorkspacePresetService.instance.init();

  // Initialize Localization Service (P3-08)
  await LocalizationService.instance.init();

  // Initialize Offline Service (P3-14)
  await OfflineService.instance.init();

  // Initialize Cloud Sync Service (P3-01)
  await CloudSyncService.instance.init();

  // Initialize AI Mixing Service (P3-03)
  await AiMixingService.instance.init();

  // Initialize Collaboration Service (P3-04)
  await CollaborationService.instance.init();

  // Initialize Asset Cloud Service (P3-06)
  await AssetCloudService.instance.init();

  // Initialize Marketplace Service (P3-11)
  await MarketplaceService.instance.init();

  // Initialize CRDT Sync Service (P3-13)
  await CrdtSyncService.instance.init();

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
        // Rust Engine (core audio backend)
        ChangeNotifierProvider(create: (_) => EngineProvider()),

        // Core playback state
        ChangeNotifierProvider(create: (_) => TimelinePlaybackProvider()),

        // Mixer and DSP routing
        ChangeNotifierProvider(create: (_) => MixerDSPProvider()),

        // Real-time metering
        ChangeNotifierProvider(create: (_) => MeterProvider()),

        // Pro DAW Mixer state
        ChangeNotifierProvider(create: (_) => MixerProvider()),

        // Editor mode (DAW/Middleware)
        ChangeNotifierProvider(create: (_) => EditorModeProvider()),

        // Keyboard shortcuts
        ChangeNotifierProvider(create: (_) => GlobalShortcutsProvider()),

        // Undo/Redo history
        ChangeNotifierProvider(create: (_) => ProjectHistoryProvider()),

        // Auto-save
        ChangeNotifierProvider(create: (_) => AutoSaveProvider()),

        // Recent Projects
        ChangeNotifierProvider(create: (_) => RecentProjectsProvider()),

        // Audio export
        ChangeNotifierProvider(create: (_) => AudioExportProvider()),

        // Session persistence
        ChangeNotifierProvider(create: (_) => SessionPersistenceProvider()),

        // Input Bus System
        ChangeNotifierProvider(create: (_) => InputBusProvider()),

        // Recording System
        ChangeNotifierProvider(create: (_) => RecordingProvider()),

        // Unified Routing System
        ChangeNotifierProvider(create: (_) => RoutingProvider()),

        // Pro Tools-Style Keyboard Focus Mode
        ChangeNotifierProvider(create: (_) => KeyboardFocusProvider()),

        // Pro Tools-Style Edit Modes (Shuffle/Slip/Spot/Grid)
        ChangeNotifierProvider(create: (_) => EditModeProProvider()),

        // Smart Tool (Context-Aware Tool Selection)
        ChangeNotifierProvider(create: (_) => SmartToolProvider()),

        // Razor Editing (Cubase-style range selection)
        ChangeNotifierProvider(create: (_) => RazorEditProvider()),

        // Direct Offline Processing
        ChangeNotifierProvider(create: (_) => DirectOfflineProcessingProvider()),

        // Parameter Modulators (LFO, Envelope Follower, Step, Random)
        ChangeNotifierProvider(create: (_) => ModulatorProvider()),

        // Arranger Track (Cubase-style section-based arrangement)
        ChangeNotifierProvider(create: (_) => ArrangerTrackProvider()),

        // Chord Track (Cubase-style chord intelligence)
        ChangeNotifierProvider(create: (_) => ChordTrackProvider()),

        // Expression Maps (Cubase-style MIDI articulation switching)
        ChangeNotifierProvider(create: (_) => ExpressionMapProvider()),

        // Macro Controls (Multi-parameter control knobs)
        ChangeNotifierProvider(create: (_) => MacroControlProvider()),

        // Track Versions (Cubase-style track playlists)
        ChangeNotifierProvider(create: (_) => TrackVersionsProvider()),

        // Clip Gain Envelope (Per-clip gain automation)
        ChangeNotifierProvider(create: (_) => ClipGainEnvelopeProvider()),

        // Logical Editor (Cubase-style batch operations)
        ChangeNotifierProvider(create: (_) => LogicalEditorProvider()),

        // Groove Quantize (Humanization and groove templates)
        ChangeNotifierProvider(create: (_) => GrooveQuantizeProvider()),

        // Audio Alignment (VocAlign-style alignment)
        ChangeNotifierProvider(create: (_) => AudioAlignmentProvider()),

        // Scale Assistant (Cubase-style key/scale helper)
        ChangeNotifierProvider(create: (_) => ScaleAssistantProvider()),

        // Error Handling
        ChangeNotifierProvider(create: (_) => ErrorProvider()),

        // Plugin Browser & Hosting
        ChangeNotifierProvider(create: (_) => PluginProvider()),

        // Control Room (Studio Monitoring)
        ChangeNotifierProvider(create: (_) => ControlRoomProvider()),

        // Middleware (States, Switches, RTPC, Ducking, Containers, Music System)
        ChangeNotifierProvider(create: (_) => MiddlewareProvider(NativeFFI.instance)),

        // Stage Ingest System (Legacy — uses Dart models)
        ChangeNotifierProvider(create: (_) => StageProvider()),

        // Stage Ingest System (New — FFI-based with rf-stage/rf-ingest/rf-connector)
        ChangeNotifierProvider(create: (_) => StageIngestProvider(NativeFFI.instance)),

        // Slot Lab (Synthetic Slot Engine)
        ChangeNotifierProvider(create: (_) => SlotLabProvider()),

        // Slot Lab Project (V6 Layout state)
        ChangeNotifierProvider(create: (_) => SlotLabProjectProvider()),

        // Adaptive Layer Engine (ALE)
        ChangeNotifierProvider(create: (_) => AleProvider()),

        // Unified Audio Asset Manager (SINGLE SOURCE OF TRUTH)
        ChangeNotifierProvider.value(value: AudioAssetManager.instance),

        // Soundbank Building System
        ChangeNotifierProvider(create: (_) => SoundbankProvider(NativeFFI.instance)),

        // Event Registry (Stage → Audio mapping)
        ChangeNotifierProvider.value(value: EventRegistry.instance),

        // Feature Builder Provider (P13)
        ChangeNotifierProvider(create: (_) => FeatureBuilderProvider()),
      ],
      child: MaterialApp(
        title: 'FluxForge Studio',
        debugShowCheckedModeBanner: false,
        theme: FluxForgeTheme.darkTheme,
        initialRoute: '/',
        routes: {
          '/': (context) => const _AppInitializer(),
          '/eq-test': (context) => const _EqTestRoute(),
        },
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

enum _AppState { launcher, dawHub, middlewareHub, main, middleware }

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
      actions.onGoToStart = () => engine.seek(0);
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

      // Phase 4: Engine ready — enable launcher buttons
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
      if (mode == AppMode.middleware) {
        // Middleware mode - show middleware hub
        _appState = _AppState.middlewareHub;
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

  void _handleOpenProject(String path) {
    final engine = context.read<EngineProvider>();
    engine.loadProject(path);
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

      case _AppState.middlewareHub:
        return MiddlewareHubScreen(
          onNewProject: (name) {
            // For middleware, go directly to slot lab
            setState(() {
              _projectName = name;
              _appState = _AppState.middleware;
            });
          },
          onOpenProject: (path) {
            setState(() {
              _projectName = path.split('/').last.replaceAll('.fxm', '');
              _appState = _AppState.middleware;
            });
          },
          onQuickStart: () {
            setState(() {
              _projectName = 'Sandbox';
              _appState = _AppState.middleware;
            });
          },
          onBackToLauncher: _handleBackToLauncher,
        );

      case _AppState.main:
        return _DawLayout(
          onBackToLauncher: _handleBackToLauncher,
          projectName: _projectName,
        );

      case _AppState.middleware:
        return _MiddlewareLayout(
          onBackToLauncher: _handleBackToLauncher,
          projectName: _projectName,
        );
    }
  }
}

/// Middleware-focused layout (uses EngineConnectedLayout with middleware mode)
class _MiddlewareLayout extends StatefulWidget {
  final VoidCallback onBackToLauncher;
  final String? projectName;

  const _MiddlewareLayout({
    required this.onBackToLauncher,
    this.projectName,
  });

  @override
  State<_MiddlewareLayout> createState() => _MiddlewareLayoutState();
}

class _MiddlewareLayoutState extends State<_MiddlewareLayout> {
  @override
  void initState() {
    super.initState();
    // Set editor mode to middleware on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editorMode = context.read<EditorModeProvider>();
      editorMode.setMode(EditorMode.middleware);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Back button is now in header (ControlBar), not overlay
    return EngineConnectedLayout(
      projectName: widget.projectName,
      onBackToLauncher: widget.onBackToLauncher,
      initialEditorMode: layout.EditorMode.middleware,
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

/// Route wrapper for EQ Test Screen
class _EqTestRoute extends StatelessWidget {
  const _EqTestRoute();

  @override
  Widget build(BuildContext context) {
    return const EqTestScreen();
  }
}
