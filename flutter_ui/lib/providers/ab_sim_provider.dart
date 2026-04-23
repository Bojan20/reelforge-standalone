import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// A/B Testing Analytics™ Provider — Batch Simulation Engine.
///
/// Bridges rf-ab-sim Rust crate to Flutter UI via FFI.
/// Manages simulation lifecycle: start, poll progress, get results, cancel.
///
/// Register as GetIt singleton.
class AbSimProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  int _activeTaskId = 0;
  double _progress = 0.0;
  bool _isRunning = false;
  Map<String, dynamic>? _lastResult;
  Timer? _pollTimer;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  int get activeTaskId => _activeTaskId;
  double get progress => _progress;
  bool get isRunning => _isRunning;
  Map<String, dynamic>? get lastResult => _lastResult;

  /// Has a completed result available?
  bool get hasResult => _lastResult != null && _lastResult!['status'] != 'running';

  // ═══════════════════════════════════════════════════════════════════════════
  // CONSTRUCTOR
  // ═══════════════════════════════════════════════════════════════════════════

  AbSimProvider({NativeFFI? ffi}) : _ffi = ffi ?? NativeFFI.instance;

  // ═══════════════════════════════════════════════════════════════════════════
  // SIMULATION CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start a new A/B simulation.
  /// [config] — BatchSimConfig as Map (variants, iterations, etc.).
  /// Returns task ID, or 0 on failure.
  int startSimulation(Map<String, dynamic> config) {
    // Cancel any existing simulation
    if (_isRunning) {
      cancel();
    }

    final taskId = _ffi.abSimStart(jsonEncode(config));
    if (taskId > 0) {
      _activeTaskId = taskId;
      _isRunning = true;
      _progress = 0.0;
      _lastResult = null;
      _startPolling();
      notifyListeners();
    }
    return taskId;
  }

  /// Cancel the active simulation.
  void cancel() {
    if (_activeTaskId > 0) {
      _ffi.abSimCancel(_activeTaskId);
    }
    _stopPolling();
    _isRunning = false;
    notifyListeners();
  }

  /// Force-poll current result (for manual refresh).
  Map<String, dynamic>? pollResult() {
    if (_activeTaskId <= 0) return null;

    _progress = _ffi.abSimProgress(_activeTaskId);

    final json = _ffi.abSimResult(_activeTaskId);
    if (json != null) {
      _lastResult = jsonDecode(json) as Map<String, dynamic>;
      if (_lastResult!['status'] != 'running') {
        _isRunning = false;
        _stopPolling();
      }
      notifyListeners();
      return _lastResult;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POLLING
  // ═══════════════════════════════════════════════════════════════════════════

  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      pollResult();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _stopPolling();
    if (_isRunning && _activeTaskId > 0) {
      _ffi.abSimCancel(_activeTaskId);
    }
    super.dispose();
  }
}
