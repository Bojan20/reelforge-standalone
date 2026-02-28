import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// 10 spectral roles for slot audio voices.
enum SpectralRole {
  subEnergy,
  lowBody,
  lowMidBody,
  midCore,
  highTransient,
  airLayer,
  fullSpectrum,
  noiseImpact,
  melodicTopline,
  backgroundPad;

  String get displayName {
    switch (this) {
      case SpectralRole.subEnergy:
        return 'Sub Energy';
      case SpectralRole.lowBody:
        return 'Low Body';
      case SpectralRole.lowMidBody:
        return 'Low-Mid';
      case SpectralRole.midCore:
        return 'Mid Core';
      case SpectralRole.highTransient:
        return 'High Trans';
      case SpectralRole.airLayer:
        return 'Air';
      case SpectralRole.fullSpectrum:
        return 'Full Spec';
      case SpectralRole.noiseImpact:
        return 'Noise';
      case SpectralRole.melodicTopline:
        return 'Melodic';
      case SpectralRole.backgroundPad:
        return 'Bg Pad';
    }
  }
}

/// Spectral Allocation Provider — manages SAMCL state from Dart side.
class SpectralAllocationProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // ─── Cached state ───
  double _sciAdv = 0.0;
  int _collisionCount = 0;
  int _slotShifts = 0;
  bool _aggressiveCarve = false;
  int _voiceCount = 0;
  List<int> _bandDensity = List.filled(10, 0);

  SpectralAllocationProvider(this._ffi);

  // ─── Getters ───
  double get sciAdv => _sciAdv;
  int get collisionCount => _collisionCount;
  int get slotShifts => _slotShifts;
  bool get aggressiveCarve => _aggressiveCarve;
  int get voiceCount => _voiceCount;
  List<int> get bandDensity => _bandDensity;

  /// Assign a spectral role to a voice.
  void assignRole(int voiceId, SpectralRole role, int priority, int harmonicLayers) {
    _ffi.samclAssignRole(voiceId, role.index, priority, harmonicLayers);
    notifyListeners();
  }

  /// Remove a voice from spectral tracking.
  void removeVoice(int voiceId) {
    _ffi.samclRemoveVoice(voiceId);
    notifyListeners();
  }

  /// Clear all voice assignments.
  void clearAll() {
    _ffi.samclClear();
    _refreshState();
    notifyListeners();
  }

  /// Compute spectral allocation.
  void compute() {
    _ffi.samclCompute();
    _refreshState();
    notifyListeners();
  }

  /// Refresh from engine.
  void refreshFromEngine() {
    _refreshState();
    notifyListeners();
  }

  void _refreshState() {
    _sciAdv = _ffi.samclGetSciAdv();
    _collisionCount = _ffi.samclGetCollisionCount();
    _slotShifts = _ffi.samclGetSlotShifts();
    _aggressiveCarve = _ffi.samclIsAggressiveCarve();
    _voiceCount = _ffi.samclVoiceCount();

    // Refresh band densities
    final newDensity = List<int>.filled(10, 0);
    for (int i = 0; i < 10; i++) {
      newDensity[i] = _ffi.samclBandDensity(i);
    }
    _bandDensity = newDensity;
  }

  /// Get band config JSON for bake.
  String? getBandConfigJson() => _ffi.samclBandConfigJson();

  /// Get role assignment JSON for bake.
  String? getRoleAssignmentJson() => _ffi.samclRoleAssignmentJson();

  /// Get collision rules JSON for bake.
  String? getCollisionRulesJson() => _ffi.samclCollisionRulesJson();

  /// Get shift curves JSON for bake.
  String? getShiftCurvesJson() => _ffi.samclShiftCurvesJson();
}
