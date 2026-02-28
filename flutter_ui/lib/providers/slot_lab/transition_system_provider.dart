/// Transition System Provider — SlotLab Middleware §25
///
/// Manages audio transitions between gameplay states and emotional states.
/// Prevents hard cuts, overlaps, and missing exit stingers.
///
/// Features:
/// - Transition matrix (State×State → TransitionRule)
/// - 6 transition types (cut, crossfade, fade_out_fade_in, stinger_bridge, tail_overlap, beat_sync)
/// - Emotional transition rules
/// - Configurable per-rule: duration, curve, stinger, delay, ducking
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §25

import 'package:flutter/foundation.dart';
import 'state_gate_provider.dart';

// =============================================================================
// TRANSITION TYPES
// =============================================================================

enum TransitionType {
  /// Immediate stop of previous, immediate start of next
  cut,
  /// Overlap with equal-power crossfade
  crossfade,
  /// Fade previous to silence, then fade in next
  fadeOutFadeIn,
  /// Play a stinger sound that bridges the two states
  stingerBridge,
  /// Let previous tail ring out while next starts
  tailOverlap,
  /// Wait for next beat/bar boundary before transitioning (music only)
  beatSync,
}

extension TransitionTypeExtension on TransitionType {
  String get displayName {
    switch (this) {
      case TransitionType.cut: return 'Cut';
      case TransitionType.crossfade: return 'Crossfade';
      case TransitionType.fadeOutFadeIn: return 'Fade Out/In';
      case TransitionType.stingerBridge: return 'Stinger Bridge';
      case TransitionType.tailOverlap: return 'Tail Overlap';
      case TransitionType.beatSync: return 'Beat Sync';
    }
  }
}

/// Fade curve type for transitions
enum TransitionCurve {
  linear,
  equalPower,
  sCurve,
  exponential,
  logarithmic,
}

// =============================================================================
// TRANSITION RULE
// =============================================================================

class TransitionRule {
  final GameplaySubstate fromState;
  final GameplaySubstate toState;
  final TransitionType type;
  final int durationMs;
  final TransitionCurve curve;
  final String? exitStinger;
  final int entryDelayMs;
  final bool keepMusic;
  final double duckDuringTransitionDb;

  const TransitionRule({
    required this.fromState,
    required this.toState,
    required this.type,
    this.durationMs = 500,
    this.curve = TransitionCurve.equalPower,
    this.exitStinger,
    this.entryDelayMs = 0,
    this.keepMusic = true,
    this.duckDuringTransitionDb = 0.0,
  });

  TransitionRule copyWith({
    TransitionType? type,
    int? durationMs,
    TransitionCurve? curve,
    String? exitStinger,
    int? entryDelayMs,
    bool? keepMusic,
    double? duckDuringTransitionDb,
  }) {
    return TransitionRule(
      fromState: fromState,
      toState: toState,
      type: type ?? this.type,
      durationMs: durationMs ?? this.durationMs,
      curve: curve ?? this.curve,
      exitStinger: exitStinger ?? this.exitStinger,
      entryDelayMs: entryDelayMs ?? this.entryDelayMs,
      keepMusic: keepMusic ?? this.keepMusic,
      duckDuringTransitionDb: duckDuringTransitionDb ?? this.duckDuringTransitionDb,
    );
  }

  Map<String, dynamic> toJson() => {
    'from_state': fromState.name,
    'to_state': toState.name,
    'type': type.name,
    'duration_ms': durationMs,
    'curve': curve.name,
    if (exitStinger != null) 'exit_stinger': exitStinger,
    'entry_delay_ms': entryDelayMs,
    'keep_music': keepMusic,
    'duck_during_transition_db': duckDuringTransitionDb,
  };

  factory TransitionRule.fromJson(Map<String, dynamic> json) {
    return TransitionRule(
      fromState: GameplaySubstate.values.firstWhere(
        (e) => e.name == json['from_state'],
        orElse: () => GameplaySubstate.idle,
      ),
      toState: GameplaySubstate.values.firstWhere(
        (e) => e.name == json['to_state'],
        orElse: () => GameplaySubstate.idle,
      ),
      type: TransitionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TransitionType.cut,
      ),
      durationMs: json['duration_ms'] as int? ?? 500,
      curve: TransitionCurve.values.firstWhere(
        (e) => e.name == json['curve'],
        orElse: () => TransitionCurve.equalPower,
      ),
      exitStinger: json['exit_stinger'] as String?,
      entryDelayMs: json['entry_delay_ms'] as int? ?? 0,
      keepMusic: json['keep_music'] as bool? ?? true,
      duckDuringTransitionDb: (json['duck_during_transition_db'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// =============================================================================
// ACTIVE TRANSITION (runtime state)
// =============================================================================

class ActiveTransition {
  final TransitionRule rule;
  final DateTime startedAt;
  final double progress; // 0.0-1.0

  const ActiveTransition({
    required this.rule,
    required this.startedAt,
    this.progress = 0.0,
  });

  bool get isComplete => progress >= 1.0;
  int get elapsedMs => DateTime.now().difference(startedAt).inMilliseconds;
}

// =============================================================================
// PROVIDER
// =============================================================================

class TransitionSystemProvider extends ChangeNotifier {
  /// Transition matrix: (from, to) → rule
  final Map<String, TransitionRule> _matrix = {};

  /// Currently active transition (null if none)
  ActiveTransition? _activeTransition;

  /// Transition history
  final List<ActiveTransition> _history = [];

  TransitionSystemProvider() {
    _initDefaultMatrix();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  ActiveTransition? get activeTransition => _activeTransition;
  bool get isTransitioning => _activeTransition != null;
  List<ActiveTransition> get history => List.unmodifiable(_history);

  /// Get rule for a state pair
  TransitionRule? getRule(GameplaySubstate from, GameplaySubstate to) {
    return _matrix['${from.name}_${to.name}'];
  }

  /// Get all rules
  List<TransitionRule> get allRules => _matrix.values.toList();

  // ═══════════════════════════════════════════════════════════════════════════
  // TRANSITION EXECUTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start a transition between states
  ActiveTransition? startTransition(GameplaySubstate from, GameplaySubstate to) {
    final rule = getRule(from, to);
    if (rule == null) return null;

    if (rule.type == TransitionType.cut) {
      // Cut = instant, no active transition state needed
      return null;
    }

    _activeTransition = ActiveTransition(
      rule: rule,
      startedAt: DateTime.now(),
    );
    notifyListeners();
    return _activeTransition;
  }

  /// Update transition progress (call from tick/frame)
  void updateProgress(double deltaMs) {
    if (_activeTransition == null) return;

    final rule = _activeTransition!.rule;
    final elapsed = _activeTransition!.elapsedMs.toDouble();
    final progress = (elapsed / rule.durationMs).clamp(0.0, 1.0);

    _activeTransition = ActiveTransition(
      rule: rule,
      startedAt: _activeTransition!.startedAt,
      progress: progress,
    );

    if (_activeTransition!.isComplete) {
      _completeTransition();
    } else {
      notifyListeners();
    }
  }

  /// Force-complete current transition
  void completeImmediately() {
    if (_activeTransition != null) {
      _completeTransition();
    }
  }

  void _completeTransition() {
    if (_activeTransition != null) {
      _history.add(_activeTransition!);
      if (_history.length > 100) _history.removeAt(0);
    }
    _activeTransition = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RULE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set a custom transition rule
  void setRule(TransitionRule rule) {
    _matrix['${rule.fromState.name}_${rule.toState.name}'] = rule;
    notifyListeners();
  }

  /// Reset to defaults
  void resetDefaults() {
    _matrix.clear();
    _initDefaultMatrix();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DEFAULT MATRIX (from §25.1)
  // ═══════════════════════════════════════════════════════════════════════════

  void _initDefaultMatrix() {
    void add(GameplaySubstate from, GameplaySubstate to, TransitionType type, {int ms = 500, String? stinger, double duck = 0.0}) {
      _matrix['${from.name}_${to.name}'] = TransitionRule(
        fromState: from, toState: to, type: type, durationMs: ms,
        exitStinger: stinger, duckDuringTransitionDb: duck,
      );
    }

    // Idle →
    add(GameplaySubstate.idle, GameplaySubstate.spin, TransitionType.cut);
    add(GameplaySubstate.idle, GameplaySubstate.feature, TransitionType.crossfade, ms: 1000);

    // Spin →
    add(GameplaySubstate.spin, GameplaySubstate.reelStop, TransitionType.cut);

    // ReelStop →
    add(GameplaySubstate.reelStop, GameplaySubstate.idle, TransitionType.fadeOutFadeIn, ms: 500);
    add(GameplaySubstate.reelStop, GameplaySubstate.win, TransitionType.stingerBridge, stinger: 'win_stinger');
    add(GameplaySubstate.reelStop, GameplaySubstate.feature, TransitionType.crossfade, ms: 1000);
    add(GameplaySubstate.reelStop, GameplaySubstate.jackpot, TransitionType.stingerBridge, stinger: 'jackpot_stinger');
    add(GameplaySubstate.reelStop, GameplaySubstate.cascade, TransitionType.cut);

    // Win →
    add(GameplaySubstate.win, GameplaySubstate.idle, TransitionType.fadeOutFadeIn, ms: 2000);
    add(GameplaySubstate.win, GameplaySubstate.spin, TransitionType.cut);
    add(GameplaySubstate.win, GameplaySubstate.feature, TransitionType.crossfade, ms: 1000);
    add(GameplaySubstate.win, GameplaySubstate.gamble, TransitionType.crossfade, ms: 500);

    // Feature →
    add(GameplaySubstate.feature, GameplaySubstate.idle, TransitionType.crossfade, ms: 2000);
    add(GameplaySubstate.feature, GameplaySubstate.spin, TransitionType.cut);
    add(GameplaySubstate.feature, GameplaySubstate.win, TransitionType.stingerBridge, stinger: 'feature_win_stinger');

    // Jackpot →
    add(GameplaySubstate.jackpot, GameplaySubstate.idle, TransitionType.crossfade, ms: 3000);

    // Cascade →
    add(GameplaySubstate.cascade, GameplaySubstate.idle, TransitionType.fadeOutFadeIn, ms: 1000);
    add(GameplaySubstate.cascade, GameplaySubstate.reelStop, TransitionType.cut);
    add(GameplaySubstate.cascade, GameplaySubstate.win, TransitionType.stingerBridge, stinger: 'cascade_win_stinger');

    // Gamble →
    add(GameplaySubstate.gamble, GameplaySubstate.idle, TransitionType.fadeOutFadeIn, ms: 500);
    add(GameplaySubstate.gamble, GameplaySubstate.win, TransitionType.crossfade, ms: 500);
  }
}
