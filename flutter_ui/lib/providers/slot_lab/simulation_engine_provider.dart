/// Simulation Engine Provider — SlotLab Middleware §13 + PBSE
///
/// Provides 6 simulation modes for testing audio behavior without
/// a live engine connection. Integrates PBSE (Pre-Bake Simulation Engine)
/// for deterministic stress-testing before BAKE.
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §13
/// See: FLUXFORGE_MASTER_SPEC.md §8

import 'package:flutter/foundation.dart';
import '../../src/rust/native_ffi.dart';

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

/// 10 PBSE simulation domains.
enum PbseDomain {
  spinSequences,
  lossStreaks,
  winStreaks,
  cascadeChains,
  featureOverlaps,
  jackpotEscalation,
  turboCompression,
  autoplayBurst,
  longSessionDrift,
  hookBurstCollision;

  String get displayName {
    switch (this) {
      case PbseDomain.spinSequences: return 'Spin Sequences';
      case PbseDomain.lossStreaks: return 'Loss Streaks';
      case PbseDomain.winStreaks: return 'Win Streaks';
      case PbseDomain.cascadeChains: return 'Cascade Chains';
      case PbseDomain.featureOverlaps: return 'Feature Overlaps';
      case PbseDomain.jackpotEscalation: return 'Jackpot Escalation';
      case PbseDomain.turboCompression: return 'Turbo Compression';
      case PbseDomain.autoplayBurst: return 'Autoplay Burst';
      case PbseDomain.longSessionDrift: return 'Long Session Drift';
      case PbseDomain.hookBurstCollision: return 'Hook Burst/Collision';
    }
  }
}

/// PBSE domain result.
class PbseDomainResult {
  final PbseDomain domain;
  final bool passed;
  final int spinCount;
  final double peakEnergy;
  final int peakVoices;
  final double peakSci;
  final double peakFatigue;
  final double escalationSlope;
  final bool deterministic;

  const PbseDomainResult({
    required this.domain,
    required this.passed,
    required this.spinCount,
    required this.peakEnergy,
    required this.peakVoices,
    required this.peakSci,
    required this.peakFatigue,
    required this.escalationSlope,
    required this.deterministic,
  });
}

/// PBSE fatigue model result.
class PbseFatigueResult {
  final double fatigueIndex;
  final double peakFrequency;
  final double harmonicDensity;
  final double temporalDensity;
  final double recoveryFactor;
  final bool passed;
  final double threshold;

  const PbseFatigueResult({
    required this.fatigueIndex,
    required this.peakFrequency,
    required this.harmonicDensity,
    required this.temporalDensity,
    required this.recoveryFactor,
    required this.passed,
    required this.threshold,
  });
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
  final NativeFFI? _ffi;

  SimulationMode _mode = SimulationMode.manualStep;
  bool _isRunning = false;
  int _currentStep = 0;
  int _totalSteps = 0;
  SimulationResult? _lastResult;
  final List<SimulationResult> _history = [];

  // Statistical mode config
  int _statSpinCount = 1000;

  // ─── PBSE State ───
  bool _bakeUnlocked = false;
  bool? _determinismVerified;
  int _pbseTotalSpins = 0;
  List<PbseDomainResult> _domainResults = [];
  PbseFatigueResult? _fatigueResult;

  SimulationEngineProvider([this._ffi]);

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

  // ─── PBSE Getters ───
  bool get bakeUnlocked => _bakeUnlocked;
  bool? get determinismVerified => _determinismVerified;
  int get pbseTotalSpins => _pbseTotalSpins;
  List<PbseDomainResult> get domainResults => List.unmodifiable(_domainResults);
  PbseFatigueResult? get fatigueResult => _fatigueResult;
  bool get hasResults => _domainResults.isNotEmpty;
  int get passedDomainCount => _domainResults.where((d) => d.passed).length;
  int get failedDomainCount => _domainResults.where((d) => !d.passed).length;

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
  // SIMULATION EXECUTION (SlotLab modes)
  // ═══════════════════════════════════════════════════════════════════════════

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _currentStep = 0;
    _totalSteps = _mode == SimulationMode.statistical ? _statSpinCount : 0;
    notifyListeners();
  }

  void step() {
    if (!_isRunning) return;
    _currentStep++;
    notifyListeners();
  }

  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    _lastResult = SimulationResult(
      mode: _mode,
      totalSpins: _currentStep,
      elapsed: Duration.zero,
    );
    _history.add(_lastResult!);
    if (_history.length > 50) _history.removeAt(0);
    notifyListeners();
  }

  void reset() {
    _isRunning = false;
    _currentStep = 0;
    _totalSteps = 0;
    notifyListeners();
  }

  void recordResult(SimulationResult result) {
    _lastResult = result;
    _history.add(result);
    if (_history.length > 50) _history.removeAt(0);
    _isRunning = false;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PBSE (Pre-Bake Simulation Engine)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Run full PBSE simulation across all 10 domains.
  bool runPbseSimulation() {
    final ffi = _ffi;
    if (ffi == null) return false;

    _isRunning = true;
    notifyListeners();

    final passed = ffi.pbseRunFullSimulation();
    _refreshPbseState();

    _isRunning = false;
    notifyListeners();
    return passed;
  }

  /// Set PBSE validation thresholds.
  void setPbseThresholds({
    double maxEnergy = 1.0,
    int maxVoices = 40,
    double maxSci = 0.85,
    double maxFatigue = 0.9,
    double maxSlope = 5.0,
  }) {
    _ffi?.pbseSetThresholds(maxEnergy, maxVoices, maxSci, maxFatigue, maxSlope);
  }

  /// Reset PBSE state.
  void resetPbse() {
    _ffi?.pbseReset();
    _bakeUnlocked = false;
    _determinismVerified = null;
    _pbseTotalSpins = 0;
    _domainResults = [];
    _fatigueResult = null;
    notifyListeners();
  }

  /// Get simulation summary as JSON string.
  String? getPbseSummaryJson() => _ffi?.pbseSimulationSummaryJson();

  void _refreshPbseState() {
    final ffi = _ffi;
    if (ffi == null) return;

    _bakeUnlocked = ffi.pbseBakeUnlocked();
    _determinismVerified = ffi.pbseDeterminismVerified();
    _pbseTotalSpins = ffi.pbseTotalSpins();

    // Refresh domain results
    _domainResults = [];
    for (int i = 0; i < PbseDomain.values.length; i++) {
      final passed = ffi.pbseDomainPassed(i);
      if (passed == null) continue;

      _domainResults.add(PbseDomainResult(
        domain: PbseDomain.values[i],
        passed: passed,
        spinCount: ffi.pbseDomainSpinCount(i),
        peakEnergy: ffi.pbseDomainPeakEnergy(i),
        peakVoices: ffi.pbseDomainPeakVoices(i),
        peakSci: ffi.pbseDomainPeakSci(i),
        peakFatigue: ffi.pbseDomainPeakFatigue(i),
        escalationSlope: ffi.pbseDomainEscalationSlope(i),
        deterministic: ffi.pbseDomainDeterministic(i) ?? false,
      ));
    }

    // Refresh fatigue model
    final fatiguePassed = ffi.pbseFatiguePassed();
    if (fatiguePassed != null) {
      _fatigueResult = PbseFatigueResult(
        fatigueIndex: ffi.pbseFatigueIndex(),
        peakFrequency: ffi.pbseFatiguePeakFrequency(),
        harmonicDensity: ffi.pbseFatigueHarmonicDensity(),
        temporalDensity: ffi.pbseFatigueTemporalDensity(),
        recoveryFactor: ffi.pbseFatigueRecoveryFactor(),
        passed: fatiguePassed,
        threshold: ffi.pbseThresholdMaxFatigue(),
      );
    }
  }
}
