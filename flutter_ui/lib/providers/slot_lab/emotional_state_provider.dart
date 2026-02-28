/// Emotional State Engine — SlotLab Middleware §9
///
/// Parallel emotional machine that evaluates alongside Priority Engine.
/// Tracks 8 emotional states and derives intensity from gameplay inputs.
/// Output modifies orchestration parameters for narrative audio flow.
///
/// Deterministic only — no randomness.
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §9

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

// =============================================================================
// EMOTIONAL STATES (8)
// =============================================================================

enum EmotionalState {
  /// Default/idle — baseline mix
  neutral,
  /// Consecutive small wins, cascade start — subtle energy lift
  build,
  /// Near-win symbols, anticipation reels — width expansion, HF shimmer
  tension,
  /// 2/3 scatter symbols landed — maximum anticipation audio
  nearWin,
  /// Win evaluated, feature triggered — impact transient, width burst
  release,
  /// Big/Mega win, jackpot reveal — maximum escalation
  peak,
  /// Post-win, rollup complete — warm tail, gentle reverb
  afterglow,
  /// Return to base, post-feature — gradual normalization
  recovery,
}

extension EmotionalStateExtension on EmotionalState {
  String get displayName {
    switch (this) {
      case EmotionalState.neutral: return 'Neutral';
      case EmotionalState.build: return 'Build';
      case EmotionalState.tension: return 'Tension';
      case EmotionalState.nearWin: return 'Near Win';
      case EmotionalState.release: return 'Release';
      case EmotionalState.peak: return 'Peak';
      case EmotionalState.afterglow: return 'Afterglow';
      case EmotionalState.recovery: return 'Recovery';
    }
  }

  /// Color for UI visualization (ARGB hex)
  int get colorValue {
    switch (this) {
      case EmotionalState.neutral: return 0xFF666680;
      case EmotionalState.build: return 0xFF4488CC;
      case EmotionalState.tension: return 0xFFDD8822;
      case EmotionalState.nearWin: return 0xFFFF6633;
      case EmotionalState.release: return 0xFF44CC44;
      case EmotionalState.peak: return 0xFFFFCC00;
      case EmotionalState.afterglow: return 0xFFFFEECC;
      case EmotionalState.recovery: return 0xFF6688BB;
    }
  }

  /// Base decay time in seconds
  double get baseDecayTime {
    switch (this) {
      case EmotionalState.neutral: return 0.0;
      case EmotionalState.build: return 5.0;
      case EmotionalState.tension: return 4.0;
      case EmotionalState.nearWin: return 3.0;
      case EmotionalState.release: return 2.0;
      case EmotionalState.peak: return 8.0;
      case EmotionalState.afterglow: return 6.0;
      case EmotionalState.recovery: return 10.0;
    }
  }
}

// =============================================================================
// EMOTIONAL OUTPUT
// =============================================================================

/// Output of the emotional state engine — consumed by orchestration
class EmotionalOutput {
  /// Current emotional state
  final EmotionalState state;

  /// Intensity (0.0-1.0)
  final double intensity;

  /// Tension level (0.0-1.0)
  final double tension;

  /// Seconds until decay to neutral
  final double decayTimer;

  /// Modifier for orchestration escalation
  final double escalationBias;

  /// Stereo width modifier (1.0 = neutral, >1.0 = wider)
  final double stereoWidthMod;

  /// High-frequency shimmer amount (0.0-1.0)
  final double hfShimmer;

  /// Reverb wetness modifier (1.0 = neutral)
  final double reverbMod;

  const EmotionalOutput({
    this.state = EmotionalState.neutral,
    this.intensity = 0.0,
    this.tension = 0.0,
    this.decayTimer = 0.0,
    this.escalationBias = 0.0,
    this.stereoWidthMod = 1.0,
    this.hfShimmer = 0.0,
    this.reverbMod = 1.0,
  });
}

// =============================================================================
// SPIN MEMORY (last 5 spins)
// =============================================================================

class SpinMemory {
  final double winAmount;
  final int cascadeDepth;
  final double multiplier;
  final bool isFeatureTriggered;
  final bool isScatterLanded;
  final DateTime timestamp;

  const SpinMemory({
    required this.winAmount,
    this.cascadeDepth = 0,
    this.multiplier = 1.0,
    this.isFeatureTriggered = false,
    this.isScatterLanded = false,
    required this.timestamp,
  });
}

// =============================================================================
// EMOTIONAL STATE PROVIDER
// =============================================================================

class EmotionalStateProvider extends ChangeNotifier {
  // Current state
  EmotionalState _state = EmotionalState.neutral;
  double _intensity = 0.0;
  double _tension = 0.0;
  double _decayTimer = 0.0;
  double _escalationBias = 0.0;

  // Derivation inputs (§9.2)
  int _cascadeDepth = 0;
  double _multiplierStack = 1.0;
  int _consecutiveLossCount = 0;
  int _consecutiveSmallWins = 0;
  double _timeSinceLastBigWin = 0.0; // seconds
  double _rtpDeviation = 0.0;
  double _volatilityIndex = 0.5;
  double _sessionDuration = 0.0; // seconds

  // Memory buffer (last 5 spins)
  final List<SpinMemory> _spinHistory = [];
  static const int _maxMemory = 5;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  EmotionalState get state => _state;
  double get intensity => _intensity;
  double get tension => _tension;
  double get decayTimer => _decayTimer;
  double get escalationBias => _escalationBias;
  int get cascadeDepth => _cascadeDepth;
  int get consecutiveLossCount => _consecutiveLossCount;
  List<SpinMemory> get spinHistory => List.unmodifiable(_spinHistory);

  /// Get full emotional output for orchestration engine
  EmotionalOutput get output => EmotionalOutput(
    state: _state,
    intensity: _intensity,
    tension: _tension,
    decayTimer: _decayTimer,
    escalationBias: _escalationBias,
    stereoWidthMod: _calcStereoWidthMod(),
    hfShimmer: _calcHfShimmer(),
    reverbMod: _calcReverbMod(),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT HANDLERS (called by middleware pipeline)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Called when a spin starts
  void onSpinStart() {
    if (_state == EmotionalState.neutral || _state == EmotionalState.recovery) {
      // Stay neutral/recovery
    }
  }

  /// Called when a spin result is evaluated
  void onSpinResult({
    required double winAmount,
    required double betAmount,
    int cascadeDepth = 0,
    double multiplier = 1.0,
    bool isFeatureTriggered = false,
    bool isScatterLanded = false,
  }) {
    // Record in memory
    _spinHistory.add(SpinMemory(
      winAmount: winAmount,
      cascadeDepth: cascadeDepth,
      multiplier: multiplier,
      isFeatureTriggered: isFeatureTriggered,
      isScatterLanded: isScatterLanded,
      timestamp: DateTime.now(),
    ));
    if (_spinHistory.length > _maxMemory) {
      _spinHistory.removeAt(0);
    }

    // Update derivation inputs
    _cascadeDepth = cascadeDepth;
    _multiplierStack = multiplier;

    if (winAmount <= 0) {
      _consecutiveLossCount++;
      _consecutiveSmallWins = 0;
    } else {
      _consecutiveLossCount = 0;
      if (winAmount < betAmount * 10) {
        _consecutiveSmallWins++;
      } else {
        _consecutiveSmallWins = 0;
      }
    }

    // Determine new emotional state
    final winMultiplier = betAmount > 0 ? winAmount / betAmount : 0.0;
    _deriveState(winMultiplier, isFeatureTriggered);
  }

  /// Called during anticipation (scatter landing)
  void onAnticipation(int scatterCount) {
    if (scatterCount >= 2) {
      _transitionTo(EmotionalState.nearWin, intensity: 0.9);
    } else {
      _transitionTo(EmotionalState.tension, intensity: 0.6);
    }
  }

  /// Called when cascade starts
  void onCascadeStart() {
    if (_state.index < EmotionalState.build.index) {
      _transitionTo(EmotionalState.build, intensity: 0.5);
    }
    _cascadeDepth++;
    _intensity = (_intensity + 0.1).clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Called when cascade step occurs
  void onCascadeStep(int stepNumber) {
    _cascadeDepth = stepNumber;
    _intensity = (0.5 + stepNumber * 0.1).clamp(0.0, 1.0);
    if (stepNumber >= 3) {
      _transitionTo(EmotionalState.tension, intensity: _intensity);
    }
  }

  /// Called when big win is triggered
  void onBigWin(int tier) {
    _transitionTo(EmotionalState.peak, intensity: (0.7 + tier * 0.06).clamp(0.0, 1.0));
    _timeSinceLastBigWin = 0.0;
  }

  /// Called when win presentation ends
  void onWinPresentationEnd() {
    _transitionTo(EmotionalState.afterglow, intensity: _intensity * 0.7);
  }

  /// Called when feature ends
  void onFeatureEnd() {
    _transitionTo(EmotionalState.recovery, intensity: 0.5);
  }

  /// Called each frame/tick to update decay
  void tick(double deltaSeconds) {
    _sessionDuration += deltaSeconds;
    _timeSinceLastBigWin += deltaSeconds;

    if (_decayTimer > 0) {
      _decayTimer -= deltaSeconds;
      if (_decayTimer <= 0) {
        _decayTimer = 0;
        _decayState();
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  void setVolatilityIndex(double value) {
    _volatilityIndex = value.clamp(0.0, 1.0);
  }

  void setRtpDeviation(double value) {
    _rtpDeviation = value;
  }

  void reset() {
    _state = EmotionalState.neutral;
    _intensity = 0.0;
    _tension = 0.0;
    _decayTimer = 0.0;
    _escalationBias = 0.0;
    _cascadeDepth = 0;
    _multiplierStack = 1.0;
    _consecutiveLossCount = 0;
    _consecutiveSmallWins = 0;
    _timeSinceLastBigWin = 0.0;
    _sessionDuration = 0.0;
    _spinHistory.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL DERIVATION
  // ═══════════════════════════════════════════════════════════════════════════

  void _deriveState(double winMultiplier, bool featureTriggered) {
    if (winMultiplier >= 20.0) {
      _transitionTo(EmotionalState.peak, intensity: math.min(1.0, 0.7 + winMultiplier / 100.0));
    } else if (featureTriggered) {
      _transitionTo(EmotionalState.release, intensity: 0.8);
    } else if (winMultiplier >= 5.0) {
      _transitionTo(EmotionalState.release, intensity: 0.6 + winMultiplier / 50.0);
    } else if (winMultiplier > 0 && _consecutiveSmallWins >= 2) {
      _transitionTo(EmotionalState.build, intensity: 0.4 + _consecutiveSmallWins * 0.1);
    } else if (winMultiplier > 0) {
      // Small win — stay or move to neutral
      if (_state == EmotionalState.build || _state == EmotionalState.tension) {
        // Stay in current elevated state
      } else {
        _transitionTo(EmotionalState.neutral, intensity: 0.2);
      }
    } else {
      // Loss
      if (_consecutiveLossCount >= 5) {
        _transitionTo(EmotionalState.recovery, intensity: 0.3);
      } else if (_state == EmotionalState.afterglow) {
        _transitionTo(EmotionalState.recovery, intensity: 0.4);
      }
    }
  }

  void _transitionTo(EmotionalState newState, {required double intensity}) {
    _state = newState;
    _intensity = intensity.clamp(0.0, 1.0);
    _tension = _calcTension();
    _decayTimer = newState.baseDecayTime;
    _escalationBias = _calcEscalationBias();
    notifyListeners();
  }

  void _decayState() {
    switch (_state) {
      case EmotionalState.peak:
        _transitionTo(EmotionalState.afterglow, intensity: _intensity * 0.6);
      case EmotionalState.release:
        _transitionTo(EmotionalState.afterglow, intensity: _intensity * 0.5);
      case EmotionalState.afterglow:
        _transitionTo(EmotionalState.recovery, intensity: 0.3);
      case EmotionalState.build:
      case EmotionalState.tension:
      case EmotionalState.nearWin:
        _transitionTo(EmotionalState.neutral, intensity: 0.0);
      case EmotionalState.recovery:
        _transitionTo(EmotionalState.neutral, intensity: 0.0);
      case EmotionalState.neutral:
        break;
    }
  }

  double _calcTension() {
    switch (_state) {
      case EmotionalState.neutral: return 0.0;
      case EmotionalState.build: return 0.2 + _intensity * 0.3;
      case EmotionalState.tension: return 0.5 + _intensity * 0.3;
      case EmotionalState.nearWin: return 0.8 + _intensity * 0.2;
      case EmotionalState.release: return 0.3;
      case EmotionalState.peak: return 0.9;
      case EmotionalState.afterglow: return 0.1;
      case EmotionalState.recovery: return 0.05;
    }
  }

  double _calcEscalationBias() {
    double bias = 0.0;
    bias += _intensity * 0.4;
    bias += _cascadeDepth * 0.05;
    bias += (_multiplierStack - 1.0) * 0.1;
    bias += _volatilityIndex * 0.2;
    return bias.clamp(-1.0, 1.0);
  }

  double _calcStereoWidthMod() {
    switch (_state) {
      case EmotionalState.tension:
      case EmotionalState.nearWin:
        return 1.0 + _intensity * 0.4; // Up to 1.4x width
      case EmotionalState.release:
        return 1.0 + _intensity * 0.6; // Width burst up to 1.6x
      case EmotionalState.peak:
        return 1.0 + _intensity * 0.8; // Maximum width
      default:
        return 1.0;
    }
  }

  double _calcHfShimmer() {
    switch (_state) {
      case EmotionalState.tension: return _intensity * 0.5;
      case EmotionalState.nearWin: return _intensity * 0.7;
      case EmotionalState.peak: return _intensity * 0.3;
      default: return 0.0;
    }
  }

  double _calcReverbMod() {
    switch (_state) {
      case EmotionalState.afterglow: return 1.0 + _intensity * 0.5; // More reverb
      case EmotionalState.peak: return 0.8; // Slightly drier for clarity
      default: return 1.0;
    }
  }
}
