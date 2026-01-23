/// Attenuation Curve Provider
///
/// Extracted from MiddlewareProvider as part of Provider Decomposition.
/// Manages slot-specific attenuation curves (Win Amount, Near Win, etc.).
///
/// Provides:
/// - Curve registration and management
/// - Curve evaluation for runtime values
/// - Per-type curve queries
/// - FFI sync with Rust engine

import 'package:flutter/foundation.dart';
import '../../models/middleware_models.dart';
import '../../src/rust/native_ffi.dart';

/// Provider for managing attenuation curves
class AttenuationCurveProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  /// Internal curve storage
  final Map<int, AttenuationCurve> _curves = {};

  /// Next available curve ID
  int _nextCurveId = 1;

  AttenuationCurveProvider({required NativeFFI ffi}) : _ffi = ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all curves
  List<AttenuationCurve> get curves => _curves.values.toList();

  /// Get all curve IDs
  List<int> get curveIds => _curves.keys.toList();

  /// Get curve count
  int get curveCount => _curves.length;

  /// Get a specific curve
  AttenuationCurve? getCurve(int curveId) => _curves[curveId];

  /// Get curve by name
  AttenuationCurve? getCurveByName(String name) {
    return _curves.values.where((c) => c.name == name).firstOrNull;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CURVE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a new attenuation curve
  AttenuationCurve addCurve({
    required String name,
    required AttenuationType type,
    double inputMin = 0.0,
    double inputMax = 1.0,
    double outputMin = 0.0,
    double outputMax = 1.0,
    RtpcCurveShape curveShape = RtpcCurveShape.linear,
    bool enabled = true,
  }) {
    final id = _nextCurveId++;

    final curve = AttenuationCurve(
      id: id,
      name: name,
      attenuationType: type,
      inputMin: inputMin,
      inputMax: inputMax,
      outputMin: outputMin,
      outputMax: outputMax,
      curveShape: curveShape,
      enabled: enabled,
    );

    _curves[id] = curve;
    _ffi.middlewareAddAttenuationCurve(curve);

    notifyListeners();
    return curve;
  }

  /// Register an existing curve
  void registerCurve(AttenuationCurve curve) {
    _curves[curve.id] = curve;
    if (curve.id >= _nextCurveId) {
      _nextCurveId = curve.id + 1;
    }
    _ffi.middlewareAddAttenuationCurve(curve);
    notifyListeners();
  }

  /// Update an existing curve
  void updateCurve(int curveId, AttenuationCurve curve) {
    if (!_curves.containsKey(curveId)) return;

    _curves[curveId] = curve;

    // Re-register with FFI
    _ffi.middlewareRemoveAttenuationCurve(curveId);
    _ffi.middlewareAddAttenuationCurve(curve);

    notifyListeners();
  }

  /// Remove a curve
  void removeCurve(int curveId) {
    if (_curves.remove(curveId) != null) {
      _ffi.middlewareRemoveAttenuationCurve(curveId);
      notifyListeners();
    }
  }

  /// Enable/disable a curve
  void setCurveEnabled(int curveId, bool enabled) {
    final curve = _curves[curveId];
    if (curve == null) return;

    _curves[curveId] = curve.copyWith(enabled: enabled);
    _ffi.middlewareSetAttenuationCurveEnabled(curveId, enabled);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CURVE QUERIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all curves of a specific type
  List<AttenuationCurve> getCurvesByType(AttenuationType type) {
    return _curves.values
        .where((c) => c.attenuationType == type && c.enabled)
        .toList();
  }

  /// Get enabled curves only
  List<AttenuationCurve> get enabledCurves {
    return _curves.values.where((c) => c.enabled).toList();
  }

  /// Check if a curve exists
  bool hasCurve(int curveId) => _curves.containsKey(curveId);

  // ═══════════════════════════════════════════════════════════════════════════
  // EVALUATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Evaluate a curve at a given input value
  double evaluateCurve(int curveId, double input) {
    final curve = _curves[curveId];
    if (curve == null) return 0.0;
    return curve.evaluate(input);
  }

  /// Evaluate all curves of a type and return max output
  double evaluateTypeMax(AttenuationType type, double input) {
    final typeCurves = getCurvesByType(type);
    if (typeCurves.isEmpty) return 0.0;

    double maxOutput = 0.0;
    for (final curve in typeCurves) {
      final output = curve.evaluate(input);
      if (output > maxOutput) {
        maxOutput = output;
      }
    }
    return maxOutput;
  }

  /// Evaluate all curves of a type and return sum of outputs
  double evaluateTypeSum(AttenuationType type, double input) {
    final typeCurves = getCurvesByType(type);
    if (typeCurves.isEmpty) return 0.0;

    double sum = 0.0;
    for (final curve in typeCurves) {
      sum += curve.evaluate(input);
    }
    return sum;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FACTORY METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a standard win amount curve
  AttenuationCurve createWinAmountCurve({
    String name = 'Win Amount',
    double inputMax = 1000.0,
  }) {
    return addCurve(
      name: name,
      type: AttenuationType.winAmount,
      inputMin: 0.0,
      inputMax: inputMax,
      outputMin: 0.0,
      outputMax: 1.0,
      curveShape: RtpcCurveShape.log3,
    );
  }

  /// Create a standard near win curve
  AttenuationCurve createNearWinCurve({
    String name = 'Near Win',
  }) {
    return addCurve(
      name: name,
      type: AttenuationType.nearWin,
      inputMin: 0.0,
      inputMax: 1.0,
      outputMin: 0.0,
      outputMax: 1.0,
      curveShape: RtpcCurveShape.sCurve,
    );
  }

  /// Create a standard combo multiplier curve
  AttenuationCurve createComboMultiplierCurve({
    String name = 'Combo Multiplier',
    double inputMax = 10.0,
  }) {
    return addCurve(
      name: name,
      type: AttenuationType.comboMultiplier,
      inputMin: 1.0,
      inputMax: inputMax,
      outputMin: 0.0,
      outputMax: 1.0,
      curveShape: RtpcCurveShape.exp1,
    );
  }

  /// Create a standard feature progress curve
  AttenuationCurve createFeatureProgressCurve({
    String name = 'Feature Progress',
  }) {
    return addCurve(
      name: name,
      type: AttenuationType.featureProgress,
      inputMin: 0.0,
      inputMax: 100.0,
      outputMin: 0.0,
      outputMax: 1.0,
      curveShape: RtpcCurveShape.linear,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export to JSON
  List<Map<String, dynamic>> toJson() {
    return _curves.values.map((c) => c.toJson()).toList();
  }

  /// Import from JSON
  void fromJson(List<dynamic> json) {
    _curves.clear();

    for (final item in json) {
      final curveJson = item as Map<String, dynamic>;
      final curve = AttenuationCurve(
        id: curveJson['id'] as int,
        name: curveJson['name'] as String,
        attenuationType: AttenuationType.values[curveJson['attenuationType'] as int? ?? 0],
        inputMin: (curveJson['inputMin'] as num?)?.toDouble() ?? 0.0,
        inputMax: (curveJson['inputMax'] as num?)?.toDouble() ?? 1.0,
        outputMin: (curveJson['outputMin'] as num?)?.toDouble() ?? 0.0,
        outputMax: (curveJson['outputMax'] as num?)?.toDouble() ?? 1.0,
        curveShape: RtpcCurveShape.values[curveJson['curveShape'] as int? ?? 0],
        enabled: curveJson['enabled'] as bool? ?? true,
      );

      _curves[curve.id] = curve;
      if (curve.id >= _nextCurveId) {
        _nextCurveId = curve.id + 1;
      }
    }

    // Sync all to FFI
    for (final curve in _curves.values) {
      _ffi.middlewareAddAttenuationCurve(curve);
    }

    notifyListeners();
  }

  /// Clear all curves
  void clear() {
    for (final curveId in _curves.keys.toList()) {
      _ffi.middlewareRemoveAttenuationCurve(curveId);
    }
    _curves.clear();
    _nextCurveId = 1;
    notifyListeners();
  }
}
