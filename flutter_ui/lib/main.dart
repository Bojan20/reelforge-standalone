/// ReelForge DAW - Flutter Frontend
///
/// Professional digital audio workstation with:
/// - Cubase-inspired multi-zone layout
/// - GPU-accelerated waveforms and spectrum
/// - 120fps smooth animations
/// - Rust audio engine via flutter_rust_bridge

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/reelforge_theme.dart';
import 'screens/main_layout.dart';
import 'screens/engine_connected_layout.dart';
import 'providers/engine_provider.dart';
import 'providers/timeline_playback_provider.dart';
import 'providers/mixer_dsp_provider.dart';
import 'providers/meter_provider.dart';
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
        home: const _AppInitializer(),
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

class _AppInitializerState extends State<_AppInitializer> {
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    try {
      // Initialize Rust engine first
      final engine = context.read<EngineProvider>();
      await engine.initialize();

      // Initialize providers that need setup
      final shortcuts = context.read<GlobalShortcutsProvider>();
      final history = context.read<ProjectHistoryProvider>();
      final meters = context.read<MeterProvider>();

      // Wire up keyboard shortcuts to engine actions
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

      // Start metering when engine starts playing
      engine.addListener(() {
        meters.setPlaying(engine.transport.isPlaying);
      });

      if (mounted) {
        setState(() => _initialized = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: ReelForgeTheme.bgDeepest,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: ReelForgeTheme.errorRed, size: 48),
              const SizedBox(height: 16),
              Text('Failed to initialize', style: ReelForgeTheme.h2),
              const SizedBox(height: 8),
              Text(_error!, style: ReelForgeTheme.body),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _initialized = false;
                  });
                  _initializeApp();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_initialized) {
      return Scaffold(
        backgroundColor: ReelForgeTheme.bgDeepest,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(ReelForgeTheme.accentBlue),
                ),
              ),
              const SizedBox(height: 24),
              Text('ReelForge', style: ReelForgeTheme.h1),
              const SizedBox(height: 8),
              Text('Loading...', style: ReelForgeTheme.body),
            ],
          ),
        ),
      );
    }

    return const EngineConnectedLayout();
  }
}
