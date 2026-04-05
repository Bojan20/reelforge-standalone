// Script Provider
//
// State management for Lua scripting system:
// - Script engine initialization
// - Script execution and output
// - Action queue processing
// - Loaded scripts management
// - Context synchronization

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// ============ Types ============

/// Script execution state
enum ScriptState {
  idle,
  running,
  success,
  error,
}

/// Script execution result
class ScriptResult {
  final bool success;
  final String? output;
  final String? error;
  final int durationMs;

  const ScriptResult({
    required this.success,
    this.output,
    this.error,
    this.durationMs = 0,
  });

  static const empty = ScriptResult(success: false);
}

/// Loaded script with metadata
class LoadedScript {
  final String name;
  final String description;
  final String? path;
  final bool isBuiltin;

  const LoadedScript({
    required this.name,
    this.description = '',
    this.path,
    this.isBuiltin = false,
  });
}

// ============ Provider ============

/// Lua scripting provider
class ScriptProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // State
  bool _isInitialized = false;
  ScriptState _state = ScriptState.idle;
  ScriptResult? _lastResult;
  List<LoadedScript> _scripts = [];
  final List<ScriptAction> _pendingActions = [];

  // Action callback
  void Function(ScriptAction action)? onAction;

  // Getters
  bool get isInitialized => _isInitialized;
  ScriptState get state => _state;
  ScriptResult? get lastResult => _lastResult;
  List<LoadedScript> get scripts => List.unmodifiable(_scripts);
  List<ScriptAction> get pendingActions => List.unmodifiable(_pendingActions);

  /// Is currently running a script
  bool get isRunning => _state == ScriptState.running;

  /// Has error from last execution
  bool get hasError => _state == ScriptState.error;

  /// Last execution was successful
  bool get wasSuccessful => _state == ScriptState.success;

  ScriptProvider({NativeFFI? ffi}) : _ffi = ffi ?? NativeFFI.instance;

  /// Initialize script engine
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    if (!_ffi.isLoaded) return false;

    final result = _ffi.scriptInit();
    if (result) {
      _isInitialized = true;
      _loadBuiltinScripts();
      notifyListeners();
    }
    return result;
  }

  /// Shutdown script engine
  void shutdown() {
    if (!_isInitialized) return;
    _ffi.scriptShutdown();
    _isInitialized = false;
    _scripts.clear();
    _pendingActions.clear();
    _state = ScriptState.idle;
    _lastResult = null;
    notifyListeners();
  }

  /// Execute Lua code
  Future<ScriptResult> execute(String code) async {
    if (!_isInitialized) {
      return const ScriptResult(
        success: false,
        error: 'Script engine not initialized',
      );
    }

    _state = ScriptState.running;
    notifyListeners();

    final success = _ffi.scriptExecute(code);

    final output = _ffi.scriptGetOutput();
    final error = _ffi.scriptGetError();
    final duration = _ffi.scriptGetDuration();

    _lastResult = ScriptResult(
      success: success,
      output: output,
      error: error,
      durationMs: duration,
    );

    _state = success ? ScriptState.success : ScriptState.error;

    // Poll and process any actions
    _pollActions();

    notifyListeners();
    return _lastResult!;
  }

  /// Execute script file
  Future<ScriptResult> executeFile(String path) async {
    if (!_isInitialized) {
      return const ScriptResult(
        success: false,
        error: 'Script engine not initialized',
      );
    }

    _state = ScriptState.running;
    notifyListeners();

    final success = _ffi.scriptExecuteFile(path);

    final output = _ffi.scriptGetOutput();
    final error = _ffi.scriptGetError();
    final duration = _ffi.scriptGetDuration();

    _lastResult = ScriptResult(
      success: success,
      output: output,
      error: error,
      durationMs: duration,
    );

    _state = success ? ScriptState.success : ScriptState.error;

    // Poll and process any actions
    _pollActions();

    notifyListeners();
    return _lastResult!;
  }

  /// Load script from file
  Future<bool> loadScript(String path) async {
    if (!_isInitialized) return false;

    final name = _ffi.scriptLoadFile(path);
    if (name != null) {
      _scripts.add(LoadedScript(
        name: name,
        path: path,
        isBuiltin: false,
      ));
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Run a loaded script by name
  Future<ScriptResult> runScript(String name) async {
    if (!_isInitialized) {
      return const ScriptResult(
        success: false,
        error: 'Script engine not initialized',
      );
    }

    _state = ScriptState.running;
    notifyListeners();

    final success = _ffi.scriptRun(name);

    final output = _ffi.scriptGetOutput();
    final error = _ffi.scriptGetError();
    final duration = _ffi.scriptGetDuration();

    _lastResult = ScriptResult(
      success: success,
      output: output,
      error: error,
      durationMs: duration,
    );

    _state = success ? ScriptState.success : ScriptState.error;

    // Poll and process any actions
    _pollActions();

    notifyListeners();
    return _lastResult!;
  }

  /// Add search path for scripts
  void addSearchPath(String path) {
    if (!_isInitialized) return;
    _ffi.scriptAddSearchPath(path);
  }

  /// Update script context (call regularly)
  void updateContext({
    required int playhead,
    required bool isPlaying,
    required bool isRecording,
    required int sampleRate,
  }) {
    if (!_isInitialized) return;
    _ffi.scriptSetContext(
      playhead: playhead,
      isPlaying: isPlaying,
      isRecording: isRecording,
      sampleRate: sampleRate,
    );
  }

  /// Set selected tracks
  void setSelectedTracks(List<int> trackIds) {
    if (!_isInitialized) return;
    _ffi.scriptSetSelectedTracks(trackIds);
  }

  /// Set selected clips
  void setSelectedClips(List<int> clipIds) {
    if (!_isInitialized) return;
    _ffi.scriptSetSelectedClips(clipIds);
  }

  /// Poll for pending actions and process them
  void _pollActions() {
    final count = _ffi.scriptPollActions();
    for (int i = 0; i < count; i++) {
      final json = _ffi.scriptGetNextAction();
      if (json != null) {
        final action = ScriptAction.fromJson(json);
        _pendingActions.add(action);

        // If callback is set, dispatch immediately
        if (onAction != null) {
          onAction!(action);
        }
      }
    }
  }

  /// Process and clear pending actions
  List<ScriptAction> consumeActions() {
    final actions = List<ScriptAction>.from(_pendingActions);
    _pendingActions.clear();
    return actions;
  }

  /// Clear last result
  void clearResult() {
    _lastResult = null;
    _state = ScriptState.idle;
    notifyListeners();
  }

  /// Refresh loaded scripts list
  void refreshScripts() {
    if (!_isInitialized) return;

    final ffiScripts = _ffi.scriptGetAllScripts();
    _scripts = [
      ..._builtinScripts,
      ...ffiScripts.map((s) => LoadedScript(
            name: s.name,
            description: s.description,
            isBuiltin: false,
          )),
    ];
    notifyListeners();
  }

  // Built-in scripts
  static const List<LoadedScript> _builtinScripts = [
    LoadedScript(
      name: 'normalize_clips',
      description: 'Normalize all selected clips',
      isBuiltin: true,
    ),
    LoadedScript(
      name: 'mute_all',
      description: 'Mute all selected tracks',
      isBuiltin: true,
    ),
    LoadedScript(
      name: 'duplicate_track',
      description: 'Duplicate selected track with clips',
      isBuiltin: true,
    ),
  ];

  void _loadBuiltinScripts() {
    _scripts = List.from(_builtinScripts);
  }

  @override
  void dispose() {
    shutdown();
    super.dispose();
  }
}

// ============ Console Widget Support ============

/// Script console history entry
class ConsoleEntry {
  final String text;
  final ConsoleEntryType type;
  final DateTime timestamp;

  const ConsoleEntry({
    required this.text,
    required this.type,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? const _DefaultDateTime();

  ConsoleEntry.input(String text)
      : this(text: '> $text', type: ConsoleEntryType.input);

  ConsoleEntry.output(String text)
      : this(text: text, type: ConsoleEntryType.output);

  ConsoleEntry.error(String text)
      : this(text: text, type: ConsoleEntryType.error);

  ConsoleEntry.info(String text)
      : this(text: text, type: ConsoleEntryType.info);
}

/// Console entry types
enum ConsoleEntryType {
  input,
  output,
  error,
  info,
}

/// Default DateTime for const constructor
class _DefaultDateTime implements DateTime {
  const _DefaultDateTime();

  @override
  dynamic noSuchMethod(Invocation invocation) => DateTime.now();
}
