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
import 'screens/splash_screen.dart';
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
import 'providers/theme_mode_provider.dart';
import 'providers/error_provider.dart';
import 'providers/recent_projects_provider.dart';
import 'providers/plugin_provider.dart';
import 'providers/control_room_provider.dart';
import 'providers/middleware_provider.dart';
import 'providers/stage_provider.dart';
import 'providers/slot_lab_provider.dart';
import 'src/rust/native_ffi.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

        // Theme Mode (Classic/Liquid Glass toggle)
        ChangeNotifierProvider(create: (_) => ThemeModeProvider()),

        // Error Handling
        ChangeNotifierProvider(create: (_) => ErrorProvider()),

        // Plugin Browser & Hosting
        ChangeNotifierProvider(create: (_) => PluginProvider()),

        // Control Room (Studio Monitoring)
        ChangeNotifierProvider(create: (_) => ControlRoomProvider()),

        // Middleware (States, Switches, RTPC, Ducking, Containers, Music System)
        ChangeNotifierProvider(create: (_) => MiddlewareProvider(NativeFFI.instance)),

        // Stage Ingest System (Universal game engine integration)
        ChangeNotifierProvider(create: (_) => StageProvider()),

        // Slot Lab (Synthetic Slot Engine)
        ChangeNotifierProvider(create: (_) => SlotLabProvider()),
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

enum _AppState { splash, launcher, dawHub, middlewareHub, main, middleware }

class _AppInitializerState extends State<_AppInitializer> {
  _AppState _appState = _AppState.splash;
  String? _error;
  String _loadingMessage = 'Starting...';
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
      _updateLoading('Initializing audio engine...');
      final engine = context.read<EngineProvider>();
      await engine.initialize();

      // Phase 2: Initialize providers
      _updateLoading('Setting up providers...');

      if (!mounted) return;
      final shortcuts = context.read<GlobalShortcutsProvider>();
      final history = context.read<ProjectHistoryProvider>();

      // Phase 2.5: Initialize plugin host
      _updateLoading('Initializing plugin host...');
      final pluginProvider = context.read<PluginProvider>();
      await pluginProvider.init();

      // Phase 3: Wire up shortcuts
      _updateLoading('Configuring shortcuts...');
      final actions = ShortcutAction();
      actions.onPlayPause = () {
        if (engine.transport.isPlaying) {
          engine.pause();
        } else {
          engine.play();
        }
      };
      actions.onStop = () => engine.stop();
      actions.onUndo = () {
        engine.undo();
        history.undo();
      };
      actions.onRedo = () {
        engine.redo();
        history.redo();
      };
      shortcuts.setActions(actions);

      // Phase 4: Show launcher screen (mode selection)
      _updateLoading('Ready');
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        setState(() => _appState = _AppState.launcher);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  void _updateLoading(String message) {
    if (mounted) {
      setState(() => _loadingMessage = message);
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _appState = _AppState.splash;
      _loadingMessage = 'Starting...';
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
      case _AppState.splash:
        return SplashScreen(
          onComplete: () {},
          loadingMessage: _loadingMessage,
          hasError: _error != null,
          errorMessage: _error,
          onRetry: _retry,
        );

      case _AppState.launcher:
        return LauncherScreen(
          onModeSelected: _handleModeSelected,
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
