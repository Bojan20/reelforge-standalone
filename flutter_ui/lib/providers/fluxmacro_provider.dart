import 'dart:async';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// State of a FluxMacro run.
enum FluxMacroRunState {
  idle,
  running,
  completed,
  failed,
  cancelled,
}

/// Result of a FluxMacro run.
class FluxMacroRunResult {
  final bool success;
  final String gameId;
  final int seed;
  final String runHash;
  final int durationMs;
  final int qaPassed;
  final int qaFailed;
  final List<String> artifacts;
  final List<String> warnings;
  final List<String> errors;

  const FluxMacroRunResult({
    required this.success,
    required this.gameId,
    required this.seed,
    required this.runHash,
    required this.durationMs,
    required this.qaPassed,
    required this.qaFailed,
    required this.artifacts,
    required this.warnings,
    required this.errors,
  });

  factory FluxMacroRunResult.fromJson(Map<String, dynamic> json) {
    return FluxMacroRunResult(
      success: json['success'] as bool? ?? false,
      gameId: json['game_id'] as String? ?? '',
      seed: json['seed'] as int? ?? 0,
      runHash: json['run_hash'] as String? ?? '',
      durationMs: json['duration_ms'] as int? ?? 0,
      qaPassed: json['qa_passed'] as int? ?? 0,
      qaFailed: json['qa_failed'] as int? ?? 0,
      artifacts: (json['artifacts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      warnings: (json['warnings'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      errors: (json['errors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  int get qaTotal => qaPassed + qaFailed;
  String get shortHash =>
      runHash.length >= 16 ? runHash.substring(0, 16) : runHash;
}

/// Run history entry.
class FluxMacroHistoryEntry {
  final String runId;
  final String macroName;
  final String gameId;
  final bool success;
  final String timestamp;
  final int durationMs;
  final String runHash;

  const FluxMacroHistoryEntry({
    required this.runId,
    required this.macroName,
    required this.gameId,
    required this.success,
    required this.timestamp,
    required this.durationMs,
    required this.runHash,
  });

  factory FluxMacroHistoryEntry.fromJson(Map<String, dynamic> json) {
    return FluxMacroHistoryEntry(
      runId: json['run_id'] as String? ?? '',
      macroName: json['macro_name'] as String? ?? '',
      gameId: json['game_id'] as String? ?? '',
      success: json['success'] as bool? ?? false,
      timestamp: json['timestamp'] as String? ?? '',
      durationMs: json['duration_ms'] as int? ?? 0,
      runHash: json['run_hash'] as String? ?? '',
    );
  }
}

/// Step info.
class FluxMacroStepInfo {
  final String name;
  final String description;
  final int estimatedMs;

  const FluxMacroStepInfo({
    required this.name,
    required this.description,
    required this.estimatedMs,
  });

  factory FluxMacroStepInfo.fromJson(Map<String, dynamic> json) {
    return FluxMacroStepInfo(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      estimatedMs: json['estimated_ms'] as int? ?? 0,
    );
  }
}

/// Provider for the FluxMacro Deterministic Orchestration Engine.
///
/// Manages lifecycle, run execution, progress polling, cancellation,
/// and run history via FFI to the Rust rf-fluxmacro crate.
///
/// Register as GetIt singleton (Layer 7.4).
class FluxMacroProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  bool _initialized = false;
  FluxMacroRunState _runState = FluxMacroRunState.idle;
  FluxMacroRunResult? _lastResult;
  double _progress = 0.0;
  String? _currentStep;
  Timer? _progressTimer;
  List<FluxMacroStepInfo> _steps = [];
  List<FluxMacroHistoryEntry> _history = [];

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get initialized => _initialized;
  FluxMacroRunState get runState => _runState;
  FluxMacroRunResult? get lastResult => _lastResult;
  double get progress => _progress;
  String? get currentStep => _currentStep;
  bool get isRunning => _runState == FluxMacroRunState.running;
  List<FluxMacroStepInfo> get steps => _steps;
  List<FluxMacroHistoryEntry> get history => _history;
  int get stepCount => _steps.length;

  // ═══════════════════════════════════════════════════════════════════════════
  // CONSTRUCTOR
  // ═══════════════════════════════════════════════════════════════════════════

  FluxMacroProvider({NativeFFI? ffi}) : _ffi = ffi ?? NativeFFI.instance;

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize the FluxMacro engine.
  bool initialize() {
    if (_initialized) return true;

    final success = _ffi.fluxmacroInit();
    if (success) {
      _initialized = true;
      _loadSteps();
      notifyListeners();
    }
    return success;
  }

  /// Shutdown the engine and release resources.
  void shutdown() {
    if (!_initialized) return;
    _stopProgressPolling();
    _ffi.fluxmacroDestroy();
    _initialized = false;
    _runState = FluxMacroRunState.idle;
    _lastResult = null;
    _progress = 0.0;
    _currentStep = null;
    _steps = [];
    _history = [];
    notifyListeners();
  }

  @override
  void dispose() {
    shutdown();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RUN
  // ═══════════════════════════════════════════════════════════════════════════

  /// Run a macro from YAML string.
  /// Runs on a background isolate-compatible thread.
  Future<FluxMacroRunResult?> runYaml(String yaml, String workingDir) async {
    if (!_initialized || isRunning) return null;

    _runState = FluxMacroRunState.running;
    _progress = 0.0;
    _currentStep = null;
    notifyListeners();

    _startProgressPolling();

    // Run on compute (since FFI call blocks)
    final resultJson = await compute(
      _runYamlIsolate,
      _RunParams(yaml: yaml, workingDir: workingDir),
    );

    _stopProgressPolling();

    if (resultJson != null) {
      _lastResult = FluxMacroRunResult.fromJson(resultJson);
      _runState = _lastResult!.success
          ? FluxMacroRunState.completed
          : FluxMacroRunState.failed;
    } else {
      _runState = FluxMacroRunState.failed;
    }

    _progress = 1.0;
    _currentStep = null;
    notifyListeners();

    return _lastResult;
  }

  /// Run a macro from file path.
  Future<FluxMacroRunResult?> runFile(String filePath) async {
    if (!_initialized || isRunning) return null;

    _runState = FluxMacroRunState.running;
    _progress = 0.0;
    _currentStep = null;
    notifyListeners();

    _startProgressPolling();

    final resultJson = await compute(
      _runFileIsolate,
      filePath,
    );

    _stopProgressPolling();

    if (resultJson != null) {
      _lastResult = FluxMacroRunResult.fromJson(resultJson);
      _runState = _lastResult!.success
          ? FluxMacroRunState.completed
          : FluxMacroRunState.failed;
    } else {
      _runState = FluxMacroRunState.failed;
    }

    _progress = 1.0;
    _currentStep = null;
    notifyListeners();

    return _lastResult;
  }

  /// Cancel a running macro.
  void cancel() {
    if (!isRunning) return;
    _ffi.fluxmacroCancel();
    _runState = FluxMacroRunState.cancelled;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VALIDATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Validate a macro YAML without executing.
  Map<String, dynamic>? validate(String yaml) {
    if (!_initialized) return null;
    return _ffi.fluxmacroValidate(yaml);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEPS
  // ═══════════════════════════════════════════════════════════════════════════

  void _loadSteps() {
    final json = _ffi.fluxmacroListSteps();
    if (json == null) return;

    final stepsList = json['steps'] as List<dynamic>?;
    if (stepsList == null) return;

    _steps = stepsList
        .map((s) => FluxMacroStepInfo.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HISTORY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load run history for a working directory.
  void loadHistory(String workingDir) {
    final json = _ffi.fluxmacroListHistory(workingDir);
    if (json == null) return;

    final runsList = json['runs'] as List<dynamic>?;
    if (runsList == null) return;

    _history = runsList
        .map((r) => FluxMacroHistoryEntry.fromJson(r as Map<String, dynamic>))
        .toList();
    notifyListeners();
  }

  /// Get detailed info for a specific run.
  Map<String, dynamic>? getRunDetail(String workingDir, String runId) {
    return _ffi.fluxmacroGetRun(workingDir, runId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QA RESULTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get QA results from last run.
  Map<String, dynamic>? getQaResults() {
    if (!_initialized) return null;
    return _ffi.fluxmacroGetQaResults();
  }

  /// Get logs from last run.
  Map<String, dynamic>? getLogs() {
    if (!_initialized) return null;
    return _ffi.fluxmacroGetLogs();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROGRESS POLLING
  // ═══════════════════════════════════════════════════════════════════════════

  void _startProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _pollProgress(),
    );
  }

  void _stopProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _pollProgress() {
    if (!isRunning) {
      _stopProgressPolling();
      return;
    }

    final newProgress = _ffi.fluxmacroGetProgress();
    final newStep = _ffi.fluxmacroGetCurrentStep();

    if (newProgress != _progress || newStep != _currentStep) {
      _progress = newProgress;
      _currentStep = newStep;
      notifyListeners();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ISOLATE HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

class _RunParams {
  final String yaml;
  final String workingDir;
  const _RunParams({required this.yaml, required this.workingDir});
}

Map<String, dynamic>? _runYamlIsolate(_RunParams params) {
  final ffi = NativeFFI.instance;
  return ffi.fluxmacroRunYaml(params.yaml, params.workingDir);
}

Map<String, dynamic>? _runFileIsolate(String filePath) {
  final ffi = NativeFFI.instance;
  return ffi.fluxmacroRunFile(filePath);
}
