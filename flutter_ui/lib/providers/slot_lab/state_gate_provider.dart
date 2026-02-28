/// State Gate Provider — SlotLab Middleware §4
///
/// Validates whether engine triggers may propagate through the pipeline.
/// First structural firewall: blocks invalid triggers, prevents
/// cross-state leakage, guarantees deterministic ordering.
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §4

import 'package:flutter/foundation.dart';

/// Gameplay substates for the state gate
enum GameplaySubstate {
  idle,
  spin,
  reelStop,
  cascade,
  win,
  feature,
  jackpot,
  gamble,
}

extension GameplaySubstateExtension on GameplaySubstate {
  String get displayName {
    switch (this) {
      case GameplaySubstate.idle: return 'Idle';
      case GameplaySubstate.spin: return 'Spin';
      case GameplaySubstate.reelStop: return 'Reel Stop';
      case GameplaySubstate.cascade: return 'Cascade';
      case GameplaySubstate.win: return 'Win';
      case GameplaySubstate.feature: return 'Feature';
      case GameplaySubstate.jackpot: return 'Jackpot';
      case GameplaySubstate.gamble: return 'Gamble';
    }
  }
}

/// Result of a gate check
class GateCheckResult {
  /// Whether the trigger is allowed to pass
  final bool allowed;

  /// Reason for blocking (null if allowed)
  final String? blockReason;

  /// Which gate rule blocked it
  final GateRule? blockedBy;

  const GateCheckResult.allow() : allowed = true, blockReason = null, blockedBy = null;

  const GateCheckResult.block(this.blockReason, [this.blockedBy]) : allowed = false;
}

/// Gate rules that can block triggers
enum GateRule {
  /// Trigger is not valid in current substate
  invalidSubstate,
  /// Trigger was already executed this frame (duplicate prevention)
  duplicateExecution,
  /// Cross-state leakage prevention
  crossStateLeakage,
  /// Feature flag disabled
  featureFlagDisabled,
  /// Session fatigue threshold exceeded
  fatigueThreshold,
  /// Autoplay/turbo mode restriction
  autoplayRestriction,
}

class StateGateProvider extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Current gameplay substate
  GameplaySubstate _currentSubstate = GameplaySubstate.idle;

  /// Previous substate (for transition validation)
  GameplaySubstate _previousSubstate = GameplaySubstate.idle;

  /// Whether autoplay is active
  bool _isAutoplay = false;

  /// Whether turbo mode is active
  bool _isTurbo = false;

  /// Current volatility index (0.0-1.0)
  double _volatilityIndex = 0.5;

  /// Session fatigue index (0.0-1.0, increases over time)
  double _sessionFatigueIndex = 0.0;

  /// Feature flags (which features are enabled)
  final Map<String, bool> _featureFlags = {};

  /// Hooks executed this frame (for duplicate prevention)
  final Set<String> _executedThisFrame = {};

  /// Valid substate transitions
  static const Map<GameplaySubstate, Set<GameplaySubstate>> _validTransitions = {
    GameplaySubstate.idle: {GameplaySubstate.spin},
    GameplaySubstate.spin: {GameplaySubstate.reelStop, GameplaySubstate.cascade},
    GameplaySubstate.reelStop: {GameplaySubstate.idle, GameplaySubstate.win, GameplaySubstate.cascade, GameplaySubstate.feature, GameplaySubstate.jackpot},
    GameplaySubstate.cascade: {GameplaySubstate.reelStop, GameplaySubstate.win},
    GameplaySubstate.win: {GameplaySubstate.idle, GameplaySubstate.gamble, GameplaySubstate.feature},
    GameplaySubstate.feature: {GameplaySubstate.spin, GameplaySubstate.idle, GameplaySubstate.jackpot},
    GameplaySubstate.jackpot: {GameplaySubstate.idle, GameplaySubstate.feature},
    GameplaySubstate.gamble: {GameplaySubstate.idle, GameplaySubstate.win},
  };

  /// Hooks allowed per substate (controls what can fire when)
  static const Map<GameplaySubstate, Set<String>> _allowedHooksPerSubstate = {
    GameplaySubstate.idle: {'onSessionStart', 'onSessionEnd', 'onButtonPress', 'onButtonRelease', 'onToggleChange', 'onPopupShow', 'onPopupDismiss'},
    GameplaySubstate.spin: {'onReelStop_r1', 'onReelStop_r2', 'onReelStop_r3', 'onReelStop_r4', 'onReelStop_r5', 'onSymbolLand', 'onAnticipationStart', 'onAnticipationEnd', 'onReelNudge'},
    GameplaySubstate.reelStop: {'onSymbolLand', 'onAnticipationStart', 'onAnticipationEnd', 'onWinEvaluate_tier1', 'onWinEvaluate_tier2', 'onWinEvaluate_tier3', 'onWinEvaluate_tier4', 'onWinEvaluate_tier5', 'onCascadeStart'},
    GameplaySubstate.cascade: {'onCascadeStep', 'onCascadeEnd', 'onSymbolLand'},
    GameplaySubstate.win: {'onCountUpTick', 'onCountUpEnd', 'onWinEvaluate_tier1', 'onWinEvaluate_tier2', 'onWinEvaluate_tier3', 'onWinEvaluate_tier4', 'onWinEvaluate_tier5'},
    GameplaySubstate.feature: {'onFeatureEnter', 'onFeatureLoop', 'onFeatureExit', 'onReelStop_r1', 'onReelStop_r2', 'onReelStop_r3', 'onReelStop_r4', 'onReelStop_r5'},
    GameplaySubstate.jackpot: {'onJackpotReveal_mini', 'onJackpotReveal_major', 'onJackpotReveal_grand'},
    GameplaySubstate.gamble: {'onButtonPress', 'onButtonRelease'},
  };

  /// Gate check history (for diagnostics)
  final List<GateCheckRecord> _history = [];

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  GameplaySubstate get currentSubstate => _currentSubstate;
  GameplaySubstate get previousSubstate => _previousSubstate;
  bool get isAutoplay => _isAutoplay;
  bool get isTurbo => _isTurbo;
  double get volatilityIndex => _volatilityIndex;
  double get sessionFatigueIndex => _sessionFatigueIndex;
  Map<String, bool> get featureFlags => Map.unmodifiable(_featureFlags);
  List<GateCheckRecord> get history => List.unmodifiable(_history);

  /// Get allowed hooks for current substate
  Set<String> get allowedHooks => _allowedHooksPerSubstate[_currentSubstate] ?? {};

  // ═══════════════════════════════════════════════════════════════════════════
  // GATE CHECK (Core function)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check whether a hook is allowed to fire in current state
  GateCheckResult checkHook(String hookName) {
    // Rule 1: Duplicate execution prevention
    if (_executedThisFrame.contains(hookName)) {
      final result = GateCheckResult.block(
        'Hook "$hookName" already executed this frame',
        GateRule.duplicateExecution,
      );
      _recordCheck(hookName, result);
      return result;
    }

    // Rule 2: Substate validation
    final allowed = _allowedHooksPerSubstate[_currentSubstate];
    if (allowed != null && !allowed.contains(hookName)) {
      final result = GateCheckResult.block(
        'Hook "$hookName" not allowed in ${_currentSubstate.displayName} state',
        GateRule.invalidSubstate,
      );
      _recordCheck(hookName, result);
      return result;
    }

    // Rule 3: Feature flag check
    final featureKey = _getFeatureKeyForHook(hookName);
    if (featureKey != null && _featureFlags[featureKey] == false) {
      final result = GateCheckResult.block(
        'Feature "$featureKey" is disabled',
        GateRule.featureFlagDisabled,
      );
      _recordCheck(hookName, result);
      return result;
    }

    // Rule 4: Fatigue threshold (suppress low-priority sounds when fatigued)
    if (_sessionFatigueIndex > 0.8 && _isLowPriorityHook(hookName)) {
      final result = GateCheckResult.block(
        'Session fatigue index ${_sessionFatigueIndex.toStringAsFixed(2)} exceeds threshold for low-priority hook',
        GateRule.fatigueThreshold,
      );
      _recordCheck(hookName, result);
      return result;
    }

    // All checks passed
    _executedThisFrame.add(hookName);
    final result = const GateCheckResult.allow();
    _recordCheck(hookName, result);
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE TRANSITIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Transition to a new substate
  bool transitionTo(GameplaySubstate newState) {
    if (newState == _currentSubstate) return true;

    final validTargets = _validTransitions[_currentSubstate];
    if (validTargets == null || !validTargets.contains(newState)) {
      return false;
    }

    _previousSubstate = _currentSubstate;
    _currentSubstate = newState;
    _executedThisFrame.clear(); // Reset duplicate tracking on state change
    notifyListeners();
    return true;
  }

  /// Force transition (bypasses validation — for error recovery)
  void forceTransition(GameplaySubstate newState) {
    _previousSubstate = _currentSubstate;
    _currentSubstate = newState;
    _executedThisFrame.clear();
    notifyListeners();
  }

  /// Reset to idle
  void resetToIdle() {
    _previousSubstate = _currentSubstate;
    _currentSubstate = GameplaySubstate.idle;
    _executedThisFrame.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE SETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  void setAutoplay(bool value) {
    if (_isAutoplay == value) return;
    _isAutoplay = value;
    notifyListeners();
  }

  void setTurbo(bool value) {
    if (_isTurbo == value) return;
    _isTurbo = value;
    notifyListeners();
  }

  void setVolatilityIndex(double value) {
    _volatilityIndex = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setSessionFatigueIndex(double value) {
    _sessionFatigueIndex = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setFeatureFlag(String key, bool enabled) {
    _featureFlags[key] = enabled;
    notifyListeners();
  }

  /// Call at end of frame to reset duplicate tracking
  void endFrame() {
    _executedThisFrame.clear();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DIAGNOSTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get blocked count for diagnostics
  int get blockedCount => _history.where((r) => !r.result.allowed).length;

  /// Get passed count for diagnostics
  int get passedCount => _history.where((r) => r.result.allowed).length;

  /// Clear history
  void clearHistory() {
    _history.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL
  // ═══════════════════════════════════════════════════════════════════════════

  String? _getFeatureKeyForHook(String hookName) {
    if (hookName.startsWith('onCascade')) return 'cascade';
    if (hookName.startsWith('onJackpot')) return 'jackpot';
    if (hookName.startsWith('onFeature')) return 'feature';
    if (hookName == 'onReelNudge') return 'nudge';
    return null;
  }

  bool _isLowPriorityHook(String hookName) {
    // UI hooks and session hooks are low-priority under fatigue
    return hookName.startsWith('onButton') ||
           hookName.startsWith('onToggle') ||
           hookName.startsWith('onPopup');
  }

  void _recordCheck(String hookName, GateCheckResult result) {
    _history.add(GateCheckRecord(
      hookName: hookName,
      substate: _currentSubstate,
      result: result,
      timestamp: DateTime.now(),
    ));
    // Keep history bounded
    if (_history.length > 500) {
      _history.removeRange(0, 250);
    }
    notifyListeners();
  }
}

/// Record of a single gate check (for diagnostic view)
class GateCheckRecord {
  final String hookName;
  final GameplaySubstate substate;
  final GateCheckResult result;
  final DateTime timestamp;

  const GateCheckRecord({
    required this.hookName,
    required this.substate,
    required this.result,
    required this.timestamp,
  });
}
