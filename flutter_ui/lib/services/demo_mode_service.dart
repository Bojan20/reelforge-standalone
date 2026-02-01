/// Demo Mode Service
///
/// Provides automatic spin sequence playback for SlotLab:
/// - Continuous auto-spin with configurable intervals
/// - Scripted demo sequences with forced outcomes
/// - Pause/resume/stop controls
/// - Loop configuration
/// - Statistics tracking
///
/// Created: 2026-01-30 (P4.17)

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../providers/slot_lab/slot_lab_coordinator.dart';
import '../src/rust/native_ffi.dart' show ForcedOutcome;

// ═══════════════════════════════════════════════════════════════════════════
// DEMO MODE STATE
// ═══════════════════════════════════════════════════════════════════════════

/// Demo mode playback state
enum DemoModeState {
  idle('Idle'),
  playing('Playing'),
  paused('Paused'),
  waiting('Waiting');

  const DemoModeState(this.label);
  final String label;
}

// ═══════════════════════════════════════════════════════════════════════════
// DEMO SEQUENCE STEP
// ═══════════════════════════════════════════════════════════════════════════

/// A single step in a demo sequence
class DemoSequenceStep {
  final ForcedOutcome? forcedOutcome;
  final Duration delayBefore;
  final Duration delayAfter;
  final String? description;

  const DemoSequenceStep({
    this.forcedOutcome,
    this.delayBefore = Duration.zero,
    this.delayAfter = const Duration(milliseconds: 2000),
    this.description,
  });

  factory DemoSequenceStep.random({
    Duration delayAfter = const Duration(milliseconds: 2000),
    String? description,
  }) {
    return DemoSequenceStep(
      forcedOutcome: null,
      delayAfter: delayAfter,
      description: description ?? 'Random spin',
    );
  }

  factory DemoSequenceStep.forced(
    ForcedOutcome outcome, {
    Duration delayAfter = const Duration(milliseconds: 3000),
    String? description,
  }) {
    return DemoSequenceStep(
      forcedOutcome: outcome,
      delayAfter: delayAfter,
      description: description ?? outcome.name,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DEMO SEQUENCE
// ═══════════════════════════════════════════════════════════════════════════

/// A complete demo sequence
class DemoSequence {
  final String name;
  final String description;
  final List<DemoSequenceStep> steps;
  final bool loop;
  final int maxLoops;

  const DemoSequence({
    required this.name,
    required this.steps,
    this.description = '',
    this.loop = true,
    this.maxLoops = 0, // 0 = infinite
  });

  int get totalSteps => steps.length;

  Duration get estimatedDuration {
    var total = Duration.zero;
    for (final step in steps) {
      total += step.delayBefore + step.delayAfter;
    }
    // Add estimated spin time per step
    total += Duration(milliseconds: steps.length * 3000);
    return total;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DEMO CONFIG
// ═══════════════════════════════════════════════════════════════════════════

/// Demo mode configuration
class DemoModeConfig {
  final Duration defaultSpinInterval;
  final Duration minSpinInterval;
  final Duration maxSpinInterval;
  final bool showUIOverlay;
  final bool soundEnabled;
  final bool autoResumeAfterWin;
  final Duration bigWinPauseDuration;

  const DemoModeConfig({
    this.defaultSpinInterval = const Duration(milliseconds: 3000),
    this.minSpinInterval = const Duration(milliseconds: 1500),
    this.maxSpinInterval = const Duration(milliseconds: 10000),
    this.showUIOverlay = true,
    this.soundEnabled = true,
    this.autoResumeAfterWin = true,
    this.bigWinPauseDuration = const Duration(milliseconds: 5000),
  });

  DemoModeConfig copyWith({
    Duration? defaultSpinInterval,
    Duration? minSpinInterval,
    Duration? maxSpinInterval,
    bool? showUIOverlay,
    bool? soundEnabled,
    bool? autoResumeAfterWin,
    Duration? bigWinPauseDuration,
  }) {
    return DemoModeConfig(
      defaultSpinInterval: defaultSpinInterval ?? this.defaultSpinInterval,
      minSpinInterval: minSpinInterval ?? this.minSpinInterval,
      maxSpinInterval: maxSpinInterval ?? this.maxSpinInterval,
      showUIOverlay: showUIOverlay ?? this.showUIOverlay,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      autoResumeAfterWin: autoResumeAfterWin ?? this.autoResumeAfterWin,
      bigWinPauseDuration: bigWinPauseDuration ?? this.bigWinPauseDuration,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DEMO STATISTICS
// ═══════════════════════════════════════════════════════════════════════════

/// Statistics from demo mode playback
class DemoStatistics {
  int totalSpins = 0;
  int wins = 0;
  int bigWins = 0;
  int bonusTriggers = 0;
  double totalWinAmount = 0.0;
  double totalBetAmount = 0.0;
  Duration totalPlayTime = Duration.zero;
  DateTime? startTime;
  DateTime? lastSpinTime;

  double get winRate => totalSpins > 0 ? wins / totalSpins * 100 : 0;
  double get rtp => totalBetAmount > 0 ? totalWinAmount / totalBetAmount * 100 : 0;
  double get avgWin => wins > 0 ? totalWinAmount / wins : 0;

  void reset() {
    totalSpins = 0;
    wins = 0;
    bigWins = 0;
    bonusTriggers = 0;
    totalWinAmount = 0.0;
    totalBetAmount = 0.0;
    totalPlayTime = Duration.zero;
    startTime = null;
    lastSpinTime = null;
  }

  void recordSpin({
    required double betAmount,
    required double winAmount,
    required bool isWin,
    required bool isBigWin,
    required bool isBonusTrigger,
  }) {
    totalSpins++;
    totalBetAmount += betAmount;
    totalWinAmount += winAmount;
    if (isWin) wins++;
    if (isBigWin) bigWins++;
    if (isBonusTrigger) bonusTriggers++;
    lastSpinTime = DateTime.now();

    if (startTime != null) {
      totalPlayTime = DateTime.now().difference(startTime!);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'totalSpins': totalSpins,
      'wins': wins,
      'bigWins': bigWins,
      'bonusTriggers': bonusTriggers,
      'totalWinAmount': totalWinAmount,
      'totalBetAmount': totalBetAmount,
      'winRate': winRate,
      'rtp': rtp,
      'avgWin': avgWin,
      'totalPlayTimeSeconds': totalPlayTime.inSeconds,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BUILT-IN SEQUENCES
// ═══════════════════════════════════════════════════════════════════════════

/// Built-in demo sequences
class BuiltInDemoSequences {
  /// Quick showcase - mix of wins
  static DemoSequence quickShowcase() {
    return DemoSequence(
      name: 'Quick Showcase',
      description: 'A quick tour of different win types',
      steps: [
        DemoSequenceStep.forced(ForcedOutcome.smallWin, description: 'Small Win'),
        DemoSequenceStep.random(),
        DemoSequenceStep.forced(ForcedOutcome.bigWin, description: 'Big Win'),
        DemoSequenceStep.random(),
        DemoSequenceStep.forced(ForcedOutcome.freeSpins, description: 'Free Spins'),
        DemoSequenceStep.random(),
        DemoSequenceStep.forced(ForcedOutcome.megaWin, description: 'Mega Win'),
      ],
      loop: true,
    );
  }

  /// Big wins showcase
  static DemoSequence bigWinsShowcase() {
    return DemoSequence(
      name: 'Big Wins',
      description: 'Showcase of big win tiers',
      steps: [
        DemoSequenceStep.forced(ForcedOutcome.bigWin, delayAfter: const Duration(milliseconds: 4000)),
        DemoSequenceStep.random(),
        DemoSequenceStep.forced(ForcedOutcome.megaWin, delayAfter: const Duration(milliseconds: 5000)),
        DemoSequenceStep.random(),
        DemoSequenceStep.forced(ForcedOutcome.epicWin, delayAfter: const Duration(milliseconds: 6000)),
        DemoSequenceStep.random(),
        DemoSequenceStep.forced(ForcedOutcome.ultraWin, delayAfter: const Duration(milliseconds: 8000)),
      ],
      loop: true,
    );
  }

  /// Features showcase
  static DemoSequence featuresShowcase() {
    return DemoSequence(
      name: 'Features',
      description: 'Showcase of bonus features',
      steps: [
        DemoSequenceStep.random(),
        DemoSequenceStep.random(),
        DemoSequenceStep.forced(ForcedOutcome.freeSpins, delayAfter: const Duration(milliseconds: 5000)),
        DemoSequenceStep.random(),
        DemoSequenceStep.forced(ForcedOutcome.cascade, delayAfter: const Duration(milliseconds: 4000)),
        DemoSequenceStep.random(),
        DemoSequenceStep.forced(ForcedOutcome.jackpotGrand, delayAfter: const Duration(milliseconds: 10000)),
      ],
      loop: true,
    );
  }

  /// Continuous random spins
  static DemoSequence continuousRandom() {
    return DemoSequence(
      name: 'Continuous Random',
      description: 'Continuous random spins',
      steps: List.generate(
        10,
        (i) => DemoSequenceStep.random(delayAfter: const Duration(milliseconds: 2500)),
      ),
      loop: true,
    );
  }

  /// All built-in sequences
  static List<DemoSequence> all() {
    return [
      quickShowcase(),
      bigWinsShowcase(),
      featuresShowcase(),
      continuousRandom(),
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DEMO MODE SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing demo mode auto-play
class DemoModeService extends ChangeNotifier {
  DemoModeService._();
  static final instance = DemoModeService._();

  // State
  DemoModeState _state = DemoModeState.idle;
  DemoModeConfig _config = const DemoModeConfig();
  DemoSequence? _currentSequence;
  int _currentStepIndex = 0;
  int _currentLoop = 0;
  final DemoStatistics _statistics = DemoStatistics();

  // Timers
  Timer? _spinTimer;
  Timer? _waitTimer;

  // Provider reference
  SlotLabProvider? _slotLabProvider;

  // Getters
  DemoModeState get state => _state;
  DemoModeConfig get config => _config;
  DemoSequence? get currentSequence => _currentSequence;
  int get currentStepIndex => _currentStepIndex;
  int get currentLoop => _currentLoop;
  DemoStatistics get statistics => _statistics;
  bool get isPlaying => _state == DemoModeState.playing || _state == DemoModeState.waiting;
  bool get isPaused => _state == DemoModeState.paused;

  DemoSequenceStep? get currentStep {
    if (_currentSequence == null || _currentStepIndex >= _currentSequence!.steps.length) {
      return null;
    }
    return _currentSequence!.steps[_currentStepIndex];
  }

  /// Initialize with provider
  void init(SlotLabProvider provider) {
    _slotLabProvider = provider;
    _slotLabProvider!.addListener(_onProviderChanged);
  }

  /// Update configuration
  void setConfig(DemoModeConfig config) {
    _config = config;
    notifyListeners();
  }

  /// Start continuous auto-spin (random)
  void startAutoSpin({Duration? interval}) {
    if (_slotLabProvider == null) return;

    _currentSequence = null;
    _currentStepIndex = 0;
    _currentLoop = 0;
    _statistics.reset();
    _statistics.startTime = DateTime.now();

    _state = DemoModeState.playing;
    notifyListeners();

    _scheduleNextSpin(interval ?? _config.defaultSpinInterval);
    debugPrint('[DemoMode] Started auto-spin');
  }

  /// Start a demo sequence
  void startSequence(DemoSequence sequence) {
    if (_slotLabProvider == null) return;

    _currentSequence = sequence;
    _currentStepIndex = 0;
    _currentLoop = 0;
    _statistics.reset();
    _statistics.startTime = DateTime.now();

    _state = DemoModeState.playing;
    notifyListeners();

    _executeCurrentStep();
    debugPrint('[DemoMode] Started sequence: ${sequence.name}');
  }

  /// Pause demo mode
  void pause() {
    if (_state != DemoModeState.playing && _state != DemoModeState.waiting) return;

    _cancelTimers();
    _state = DemoModeState.paused;
    notifyListeners();
    debugPrint('[DemoMode] Paused');
  }

  /// Resume demo mode
  void resume() {
    if (_state != DemoModeState.paused) return;

    _state = DemoModeState.playing;
    notifyListeners();

    if (_currentSequence != null) {
      _executeCurrentStep();
    } else {
      _scheduleNextSpin(_config.defaultSpinInterval);
    }
    debugPrint('[DemoMode] Resumed');
  }

  /// Stop demo mode
  void stop() {
    _cancelTimers();
    _state = DemoModeState.idle;
    _currentSequence = null;
    _currentStepIndex = 0;
    _currentLoop = 0;
    notifyListeners();
    debugPrint('[DemoMode] Stopped');
  }

  /// Reset statistics
  void resetStatistics() {
    _statistics.reset();
    notifyListeners();
  }

  /// Dispose
  @override
  void dispose() {
    _cancelTimers();
    _slotLabProvider?.removeListener(_onProviderChanged);
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIVATE METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void _cancelTimers() {
    _spinTimer?.cancel();
    _spinTimer = null;
    _waitTimer?.cancel();
    _waitTimer = null;
  }

  void _onProviderChanged() {
    // Check if spin completed
    if (_state == DemoModeState.waiting && _slotLabProvider != null) {
      if (!_slotLabProvider!.isPlayingStages) {
        _onSpinComplete();
      }
    }
  }

  void _scheduleNextSpin(Duration delay) {
    _cancelTimers();
    _spinTimer = Timer(delay, _executeSpin);
  }

  void _executeSpin() {
    if (_state != DemoModeState.playing || _slotLabProvider == null) return;

    // Check for forced outcome
    ForcedOutcome? forcedOutcome;
    if (_currentSequence != null && currentStep != null) {
      forcedOutcome = currentStep!.forcedOutcome;
    }

    // Execute spin
    if (forcedOutcome != null) {
      _slotLabProvider!.spinForced(forcedOutcome);
    } else {
      _slotLabProvider!.spin();
    }

    _state = DemoModeState.waiting;
    notifyListeners();
  }

  void _executeCurrentStep() {
    if (_state != DemoModeState.playing || _currentSequence == null) return;

    final step = currentStep;
    if (step == null) {
      // Sequence complete
      _onSequenceComplete();
      return;
    }

    // Apply delay before spin
    if (step.delayBefore.inMilliseconds > 0) {
      _waitTimer = Timer(step.delayBefore, _executeSpin);
    } else {
      _executeSpin();
    }
  }

  void _onSpinComplete() {
    if (_slotLabProvider == null) return;

    // Record statistics
    final result = _slotLabProvider!.lastResult;
    if (result != null) {
      final betAmount = _slotLabProvider!.betAmount;
      final winAmount = result.totalWin;
      final isWin = winAmount > 0;
      final isBigWin = betAmount > 0 && winAmount / betAmount >= 20;
      final isBonusTrigger = result.featureTriggered;

      _statistics.recordSpin(
        betAmount: betAmount,
        winAmount: winAmount,
        isWin: isWin,
        isBigWin: isBigWin,
        isBonusTrigger: isBonusTrigger,
      );

      // Extended pause for big wins
      Duration nextDelay;
      if (isBigWin && _config.autoResumeAfterWin) {
        nextDelay = _config.bigWinPauseDuration;
      } else if (_currentSequence != null && currentStep != null) {
        nextDelay = currentStep!.delayAfter;
      } else {
        nextDelay = _config.defaultSpinInterval;
      }

      // Advance sequence
      if (_currentSequence != null) {
        _currentStepIndex++;
        if (_currentStepIndex >= _currentSequence!.steps.length) {
          _onSequenceLoopComplete();
        } else {
          _state = DemoModeState.playing;
          notifyListeners();
          _scheduleNextSpin(nextDelay);
        }
      } else {
        _state = DemoModeState.playing;
        notifyListeners();
        _scheduleNextSpin(nextDelay);
      }
    } else {
      // No result, just continue
      _state = DemoModeState.playing;
      notifyListeners();
      _scheduleNextSpin(_config.defaultSpinInterval);
    }
  }

  void _onSequenceLoopComplete() {
    if (_currentSequence == null) return;

    _currentLoop++;
    _currentStepIndex = 0;

    // Check if should continue looping
    if (_currentSequence!.loop) {
      if (_currentSequence!.maxLoops > 0 && _currentLoop >= _currentSequence!.maxLoops) {
        _onSequenceComplete();
      } else {
        _state = DemoModeState.playing;
        notifyListeners();
        _executeCurrentStep();
      }
    } else {
      _onSequenceComplete();
    }
  }

  void _onSequenceComplete() {
    debugPrint('[DemoMode] Sequence complete: ${_currentSequence?.name}');
    _state = DemoModeState.idle;
    _currentSequence = null;
    _currentStepIndex = 0;
    notifyListeners();
  }
}
