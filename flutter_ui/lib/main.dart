// ReelForge DAW - Flutter Frontend
//
// Professional digital audio workstation with:
// - Cubase-inspired multi-zone layout
// - GPU-accelerated waveforms and spectrum
// - 120fps smooth animations
// - Rust audio engine via flutter_rust_bridge

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/reelforge_theme.dart';
import 'screens/engine_connected_layout.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/eq_test_screen.dart';
import 'providers/engine_provider.dart';
import 'providers/timeline_playback_provider.dart';
import 'providers/mixer_dsp_provider.dart';
import 'providers/meter_provider.dart';
import 'providers/mixer_provider.dart';
import 'providers/editor_mode_provider.dart';
import 'providers/global_shortcuts_provider.dart' show GlobalShortcutsProvider, ShortcutAction;
import 'providers/project_history_provider.dart';
import 'providers/auto_save_provider.dart';
import 'providers/audio_export_provider.dart';
import 'providers/session_persistence_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReelForgeApp());
}

class ReelForgeApp extends StatelessWidget {
  const ReelForgeApp({super.key});

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

        // Audio export
        ChangeNotifierProvider(create: (_) => AudioExportProvider()),

        // Session persistence
        ChangeNotifierProvider(create: (_) => SessionPersistenceProvider()),
      ],
      child: MaterialApp(
        title: 'ReelForge',
        debugShowCheckedModeBanner: false,
        theme: ReelForgeTheme.darkTheme,
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

enum _AppState { splash, welcome, main }

class _AppInitializerState extends State<_AppInitializer> {
  _AppState _appState = _AppState.splash;
  String? _error;
  String _loadingMessage = 'Starting...';
  String? _projectName;

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

      // Phase 4: Show welcome screen
      _updateLoading('Ready');
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        setState(() => _appState = _AppState.welcome);
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

      case _AppState.welcome:
        return WelcomeScreen(
          onNewProject: _handleNewProject,
          onOpenProject: _handleOpenProject,
          onSkip: () => _handleNewProject('Untitled Project'),
        );

      case _AppState.main:
        return EngineConnectedLayout(
          projectName: _projectName,
        );
    }
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
