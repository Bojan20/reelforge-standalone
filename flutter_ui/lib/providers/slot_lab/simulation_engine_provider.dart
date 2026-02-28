/// Simulation Engine Provider — SlotLab Middleware §13
///
/// Provides 6 simulation modes for testing audio behavior without
/// a live engine connection. Used in Simulation view mode.
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §13

import 'package:flutter/foundation.dart';

enum SimulationMode {
  /// Step through stages manually one-by-one
  manualStep,
  /// Auto-play all stages in sequence with timing
  autoSequence,
  /// Stress test: rapid random hook firing
  stressTest,
  /// Replay a recorded session trace
  sessionReplay,
  /// Statistical: run N spins and collect analytics
  statistical,
  /// Edge case: test specific edge cases (near-miss, jackpot, etc.)
  edgeCase,
}

extension SimulationModeExtension on SimulationMode {
  String get displayName {
    switch (this) {
      case SimulationMode.manualStep: return 'Manual Step';
      case SimulationMode.autoSequence: return 'Auto Sequence';
      case SimulationMode.stressTest: return 'Stress Test';
      case SimulationMode.sessionReplay: return 'Session Replay';
      case SimulationMode.statistical: return 'Statistical';
      case SimulationMode.edgeCase: return 'Edge Case';
    }
  }

  String get description {
    switch (this) {
      case SimulationMode.manualStep: return 'Step through stages one-by-one';
      case SimulationMode.autoSequence: return 'Auto-play all stages in sequence';
      case SimulationMode.stressTest: return 'Rapid random hook firing (voice stealing test)';
      case SimulationMode.sessionReplay: return 'Replay a recorded session trace';
      case SimulationMode.statistical: return 'Run N spins and collect analytics';
      case SimulationMode.edgeCase: return 'Test specific edge cases';
    }
  }
}

/// Edge case presets
enum EdgeCasePreset {
  nearMissTriple,
  jackpotGrand,
  maxCascade,
  featureRetrigger,
  emptyResult,
  maxMultiplier,
}

/// Result of a simulation run
class SimulationResult {
  final SimulationMode mode;
  final int totalSpins;
  final int hooksFired;
  final int gateBlocks;
  final int voiceSteals;
  final double avgCoveragePercent;
  final Duration elapsed;
  final List<String> warnings;

  const SimulationResult({
    required this.mode,
    this.totalSpins = 0,
    this.hooksFired = 0,
    this.gateBlocks = 0,
    this.voiceSteals = 0,
    this.avgCoveragePercent = 0.0,
    this.elapsed = Duration.zero,
    this.warnings = const [],
  });
}

class SimulationEngineProvider extends ChangeNotifier {
  SimulationMode _mode = SimulationMode.manualStep;
  bool _isRunning = false;
  int _currentStep = 0;
  int _totalSteps = 0;
  SimulationResult? _lastResult;
  final List<SimulationResult> _history = [];

  // Statistical mode config
  int _statSpinCount = 1000;
  double _statBetAmount = 1.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  SimulationMode get mode => _mode;
  bool get isRunning => _isRunning;
  int get currentStep => _currentStep;
  int get totalSteps => _totalSteps;
  double get progress => _totalSteps > 0 ? _currentStep / _totalSteps : 0.0;
  SimulationResult? get lastResult => _lastResult;
  List<SimulationResult> get history => List.unmodifiable(_history);
  int get statSpinCount => _statSpinCount;

  // ═══════════════════════════════════════════════════════════════════════════
  // MODE CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  void setMode(SimulationMode mode) {
    if (_isRunning) return;
    _mode = mode;
    notifyListeners();
  }

  void setStatSpinCount(int count) {
    _statSpinCount = count.clamp(10, 100000);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SIMULATION EXECUTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start simulation
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _currentStep = 0;
    _totalSteps = _mode == SimulationMode.statistical ? _statSpinCount : 0;
    notifyListeners();
  }

  /// Step forward (manual mode)
  void step() {
    if (!_isRunning) return;
    _currentStep++;
    notifyListeners();
  }

  /// Stop simulation
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    _lastResult = SimulationResult(
      mode: _mode,
      totalSpins: _currentStep,
      elapsed: Duration.zero, // Tracked externally
    );
    _history.add(_lastResult!);
    if (_history.length > 50) _history.removeAt(0);
    notifyListeners();
  }

  /// Reset
  void reset() {
    _isRunning = false;
    _currentStep = 0;
    _totalSteps = 0;
    notifyListeners();
  }

  /// Record result (called by simulation runner)
  void recordResult(SimulationResult result) {
    _lastResult = result;
    _history.add(result);
    if (_history.length > 50) _history.removeAt(0);
    _isRunning = false;
    notifyListeners();
  }
}
