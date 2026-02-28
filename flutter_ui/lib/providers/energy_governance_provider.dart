import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// 5 energy domains tracked by GEG.
enum EnergyDomain {
  dynamic,
  transient,
  spatial,
  harmonic,
  temporal;

  String get displayName {
    switch (this) {
      case EnergyDomain.dynamic:
        return 'Dynamic';
      case EnergyDomain.transient:
        return 'Transient';
      case EnergyDomain.spatial:
        return 'Spatial';
      case EnergyDomain.harmonic:
        return 'Harmonic';
      case EnergyDomain.temporal:
        return 'Temporal';
    }
  }
}

/// 9 slot profiles.
enum GegSlotProfile {
  highVolatility,
  mediumVolatility,
  lowVolatility,
  cascadeHeavy,
  featureHeavy,
  jackpotFocused,
  classic3Reel,
  clusterPay,
  megawaysStyle;

  String get displayName {
    switch (this) {
      case GegSlotProfile.highVolatility:
        return 'High Volatility';
      case GegSlotProfile.mediumVolatility:
        return 'Medium Volatility';
      case GegSlotProfile.lowVolatility:
        return 'Low Volatility';
      case GegSlotProfile.cascadeHeavy:
        return 'Cascade Heavy';
      case GegSlotProfile.featureHeavy:
        return 'Feature Heavy';
      case GegSlotProfile.jackpotFocused:
        return 'Jackpot Focused';
      case GegSlotProfile.classic3Reel:
        return 'Classic 3-Reel';
      case GegSlotProfile.clusterPay:
        return 'Cluster Pay';
      case GegSlotProfile.megawaysStyle:
        return 'Megaways Style';
    }
  }
}

/// 6 escalation curve types.
enum GegCurveType {
  linear,
  logarithmic,
  exponential,
  cappedExponential,
  step,
  sCurve;

  String get displayName {
    switch (this) {
      case GegCurveType.linear:
        return 'Linear';
      case GegCurveType.logarithmic:
        return 'Logarithmic';
      case GegCurveType.exponential:
        return 'Exponential';
      case GegCurveType.cappedExponential:
        return 'Capped Exp';
      case GegCurveType.step:
        return 'Step';
      case GegCurveType.sCurve:
        return 'S-Curve';
    }
  }
}

/// Energy Governance Provider — manages GEG state from Dart side.
class EnergyGovernanceProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // ─── Cached state ───
  GegSlotProfile _activeProfile = GegSlotProfile.mediumVolatility;
  GegCurveType _activeCurve = GegCurveType.sCurve;
  List<double> _domainCaps = [0.5, 0.5, 0.5, 0.5, 0.5];
  double _overallCap = 0.5;
  double _sessionMemorySM = 1.0;
  int _totalSpins = 0;
  int _lossStreak = 0;
  bool _featureStormActive = false;
  bool _jackpotCompressionActive = false;
  int _voiceBudgetMax = 40;
  double _voiceBudgetRatio = 0.7;

  EnergyGovernanceProvider(this._ffi);

  // ─── Getters ───
  GegSlotProfile get activeProfile => _activeProfile;
  GegCurveType get activeCurve => _activeCurve;
  List<double> get domainCaps => _domainCaps;
  double get overallCap => _overallCap;
  double get sessionMemorySM => _sessionMemorySM;
  int get totalSpins => _totalSpins;
  int get lossStreak => _lossStreak;
  bool get featureStormActive => _featureStormActive;
  bool get jackpotCompressionActive => _jackpotCompressionActive;
  int get voiceBudgetMax => _voiceBudgetMax;
  double get voiceBudgetRatio => _voiceBudgetRatio;

  /// Get cap for a specific domain.
  double domainCap(EnergyDomain domain) {
    return _domainCaps[domain.index];
  }

  // ─── Actions ───

  /// Set active slot profile.
  void setProfile(GegSlotProfile profile) {
    _ffi.gegSetProfile(profile.index);
    _activeProfile = profile;
    _refreshState();
    notifyListeners();
  }

  /// Set escalation curve.
  void setCurve(GegCurveType curve) {
    _ffi.gegSetCurve(curve.index);
    _activeCurve = curve;
    notifyListeners();
  }

  /// Record a spin result.
  void recordSpin({
    required double winMultiplier,
    bool isFeature = false,
    bool isJackpot = false,
  }) {
    _ffi.gegRecordSpin(winMultiplier, isFeature, isJackpot);
    _refreshState();
    notifyListeners();
  }

  /// Reset session memory.
  void resetSession() {
    _ffi.gegResetSession();
    _refreshState();
    notifyListeners();
  }

  /// Refresh all cached state from engine.
  void refreshFromEngine() {
    _refreshState();
    notifyListeners();
  }

  void _refreshState() {
    final profileIdx = _ffi.gegGetProfile();
    if (profileIdx < 9) {
      _activeProfile = GegSlotProfile.values[profileIdx];
    }

    final curveIdx = _ffi.gegGetCurve();
    if (curveIdx < 6) {
      _activeCurve = GegCurveType.values[curveIdx];
    }

    final caps = _ffi.gegAllDomainCaps();
    if (caps != null) {
      _domainCaps = caps;
    }

    _overallCap = _ffi.gegOverallCap();
    _sessionMemorySM = _ffi.gegGetSessionMemory();
    _totalSpins = _ffi.gegGetTotalSpins();
    _lossStreak = _ffi.gegGetLossStreak();
    _featureStormActive = _ffi.gegIsFeatureStorm();
    _jackpotCompressionActive = _ffi.gegIsJackpotCompression();
    _voiceBudgetMax = _ffi.gegVoiceBudgetMax();
    _voiceBudgetRatio = _ffi.gegVoiceBudgetRatio();
  }

  /// Get energy config JSON for bake output.
  String? getEnergyConfigJson() => _ffi.gegEnergyConfigJson();

  /// Get slot profile JSON for bake output.
  String? getSlotProfileJson() => _ffi.gegSlotProfileJson();
}
