import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// 8 DPM event types.
enum DpmEventType {
  jackpotGrand,
  winBig,
  featureEnter,
  cascadeStep,
  reelStop,
  background,
  ui,
  system;

  String get displayName {
    switch (this) {
      case DpmEventType.jackpotGrand:
        return 'Jackpot Grand';
      case DpmEventType.winBig:
        return 'Win Big';
      case DpmEventType.featureEnter:
        return 'Feature Enter';
      case DpmEventType.cascadeStep:
        return 'Cascade Step';
      case DpmEventType.reelStop:
        return 'Reel Stop';
      case DpmEventType.background:
        return 'Background';
      case DpmEventType.ui:
        return 'UI';
      case DpmEventType.system:
        return 'System';
    }
  }
}

/// 7 emotional states.
enum DpmEmotionalState {
  neutral,
  anticipation,
  excitement,
  tension,
  relief,
  frustration,
  euphoria;

  String get displayName {
    switch (this) {
      case DpmEmotionalState.neutral:
        return 'Neutral';
      case DpmEmotionalState.anticipation:
        return 'Anticipation';
      case DpmEmotionalState.excitement:
        return 'Excitement';
      case DpmEmotionalState.tension:
        return 'Tension';
      case DpmEmotionalState.relief:
        return 'Relief';
      case DpmEmotionalState.frustration:
        return 'Frustration';
      case DpmEmotionalState.euphoria:
        return 'Euphoria';
    }
  }
}

/// DPM Provider — manages Dynamic Priority Matrix state from Dart side.
class DpmProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // ─── Cached state ───
  DpmEmotionalState _emotionalState = DpmEmotionalState.neutral;
  int _retained = 0;
  int _attenuated = 0;
  int _suppressed = 0;
  int _ducked = 0;
  bool _jackpotOverride = false;

  DpmProvider(this._ffi);

  // ─── Getters ───
  DpmEmotionalState get emotionalState => _emotionalState;
  int get retained => _retained;
  int get attenuated => _attenuated;
  int get suppressed => _suppressed;
  int get ducked => _ducked;
  bool get jackpotOverride => _jackpotOverride;

  /// Set emotional state.
  void setEmotionalState(DpmEmotionalState state) {
    _ffi.dpmSetEmotionalState(state.index);
    _emotionalState = state;
    notifyListeners();
  }

  /// Compute priority for a single event type.
  double computePriority(DpmEventType eventType, {double contextModifier = 1.0}) {
    return _ffi.dpmComputePriority(eventType.index, contextModifier);
  }

  /// Refresh DPM state from engine.
  void refreshFromEngine() {
    _refreshState();
    notifyListeners();
  }

  void _refreshState() {
    final stateIdx = _ffi.dpmGetEmotionalState();
    if (stateIdx < DpmEmotionalState.values.length) {
      _emotionalState = DpmEmotionalState.values[stateIdx];
    }
    _retained = _ffi.dpmRetainedCount();
    _attenuated = _ffi.dpmAttenuatedCount();
    _suppressed = _ffi.dpmSuppressedCount();
    _ducked = _ffi.dpmDuckedCount();
    _jackpotOverride = _ffi.dpmIsJackpotOverride();
  }

  /// Get survival action for a voice (0=Retain, 1=Attenuate, 2=Suppress, 3=Duck).
  int getVoiceSurvivalAction(int voiceId) {
    return _ffi.dpmVoiceSurvivalAction(voiceId);
  }

  /// Get base weight for an event type.
  double getEventBaseWeight(DpmEventType eventType) {
    return _ffi.dpmEventBaseWeight(eventType.index);
  }

  // ─── Bake outputs ───
  String? getEventWeightsJson() => _ffi.dpmEventWeightsJson();
  String? getProfileModifiersJson() => _ffi.dpmProfileModifiersJson();
  String? getContextRulesJson() => _ffi.dpmContextRulesJson();
  String? getPriorityMatrixJson() => _ffi.dpmPriorityMatrixJson();
}
