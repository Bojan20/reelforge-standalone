/// RTPC System Provider
///
/// Extracted from MiddlewareProvider as part of P0.2 decomposition.
/// Manages Real-Time Parameter Control (RTPC) system (Wwise/FMOD-style).
///
/// RTPC allows continuous parameter control over audio properties:
/// - Global RTPC values (e.g., "Danger" level affecting music intensity)
/// - Per-object RTPC values (e.g., engine RPM per vehicle)
/// - RTPC Bindings map RTPC values to target parameters (volume, pitch, etc.)

import 'package:flutter/foundation.dart';
import '../../models/middleware_models.dart';
import '../../src/rust/native_ffi.dart';

/// Provider for managing RTPC system
class RtpcSystemProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  /// RTPC definitions
  final Map<int, RtpcDefinition> _rtpcDefs = {};

  /// Per-object RTPC values: gameObjectId → (rtpcId → value)
  final Map<int, Map<int, double>> _objectRtpcs = {};

  /// RTPC bindings (RTPC → parameter mappings)
  final Map<int, RtpcBinding> _rtpcBindings = {};

  /// Next available RTPC ID
  int _nextRtpcId = 100;

  /// Next available binding ID
  int _nextBindingId = 1;

  RtpcSystemProvider({required NativeFFI ffi}) : _ffi = ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all RTPC definitions
  Map<int, RtpcDefinition> get rtpcDefs => Map.unmodifiable(_rtpcDefs);

  /// Get all RTPC definitions as list
  List<RtpcDefinition> get rtpcDefinitions => _rtpcDefs.values.toList();

  /// Get all RTPC bindings
  Map<int, RtpcBinding> get bindings => Map.unmodifiable(_rtpcBindings);

  /// Get all RTPC bindings as list
  List<RtpcBinding> get rtpcBindings => _rtpcBindings.values.toList();

  /// Get count of RTPCs
  int get rtpcCount => _rtpcDefs.length;

  /// Get count of objects with RTPC overrides
  int get objectsWithRtpcsCount => _objectRtpcs.length;

  /// Get a specific RTPC definition
  RtpcDefinition? getRtpc(int rtpcId) => _rtpcDefs[rtpcId];

  /// Get RTPC by name
  RtpcDefinition? getRtpcByName(String name) {
    return _rtpcDefs.values.where((r) => r.name == name).firstOrNull;
  }

  /// Get a specific binding
  RtpcBinding? getBinding(int bindingId) => _rtpcBindings[bindingId];

  /// Get RTPC value (global)
  double getRtpcValue(int rtpcId) {
    return _rtpcDefs[rtpcId]?.currentValue ?? 0.0;
  }

  /// Get RTPC value for a specific game object (falls back to global)
  double getRtpcValueForObject(int gameObjectId, int rtpcId) {
    return _objectRtpcs[gameObjectId]?[rtpcId] ?? getRtpcValue(rtpcId);
  }

  /// Get all RTPC overrides for a game object
  Map<int, double>? getObjectRtpcs(int gameObjectId) {
    return _objectRtpcs[gameObjectId];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RTPC REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register an RTPC parameter
  void registerRtpc(RtpcDefinition rtpc) {
    _rtpcDefs[rtpc.id] = rtpc;

    // Update next ID if needed
    if (rtpc.id >= _nextRtpcId) {
      _nextRtpcId = rtpc.id + 1;
    }

    // Register with Rust
    _ffi.middlewareRegisterRtpc(
      rtpc.id,
      rtpc.name,
      rtpc.min,
      rtpc.max,
      rtpc.defaultValue,
    );

    notifyListeners();
  }

  /// Register RTPC from preset data
  void registerRtpcFromPreset(Map<String, dynamic> preset) {
    final rtpc = RtpcDefinition(
      id: preset['id'] as int,
      name: preset['name'] as String,
      min: (preset['min'] as num).toDouble(),
      max: (preset['max'] as num).toDouble(),
      defaultValue: (preset['default'] as num).toDouble(),
      currentValue: (preset['default'] as num).toDouble(),
    );

    registerRtpc(rtpc);
  }

  /// Unregister an RTPC
  ///
  /// Note: Rust FFI currently doesn't support unregister - RTPC remains
  /// in engine but is removed from UI tracking. IDs are never reused.
  void unregisterRtpc(int rtpcId) {
    _rtpcDefs.remove(rtpcId);
    // Remove from all objects
    for (final objectRtpcs in _objectRtpcs.values) {
      objectRtpcs.remove(rtpcId);
    }
    // Remove bindings that use this RTPC
    _rtpcBindings.removeWhere((_, binding) => binding.rtpcId == rtpcId);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RTPC VALUE CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set RTPC value globally
  void setRtpc(int rtpcId, double value, {int interpolationMs = 0}) {
    final rtpc = _rtpcDefs[rtpcId];
    if (rtpc == null) return;

    final clampedValue = rtpc.clamp(value);
    _rtpcDefs[rtpcId] = rtpc.copyWith(currentValue: clampedValue);

    // Send to Rust
    _ffi.middlewareSetRtpc(rtpcId, clampedValue, interpolationMs: interpolationMs);

    notifyListeners();
  }

  /// Set RTPC value for specific game object
  void setRtpcOnObject(int gameObjectId, int rtpcId, double value, {int interpolationMs = 0}) {
    final rtpc = _rtpcDefs[rtpcId];
    if (rtpc == null) return;

    final clampedValue = rtpc.clamp(value);
    _objectRtpcs[gameObjectId] ??= {};
    _objectRtpcs[gameObjectId]![rtpcId] = clampedValue;

    // Send to Rust
    _ffi.middlewareSetRtpcOnObject(gameObjectId, rtpcId, clampedValue, interpolationMs: interpolationMs);

    notifyListeners();
  }

  /// Reset RTPC to default value
  void resetRtpc(int rtpcId, {int interpolationMs = 100}) {
    final rtpc = _rtpcDefs[rtpcId];
    if (rtpc == null) return;

    setRtpc(rtpcId, rtpc.defaultValue, interpolationMs: interpolationMs);
  }

  /// Clear all RTPC overrides for a game object
  void clearObjectRtpcs(int gameObjectId) {
    _objectRtpcs.remove(gameObjectId);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RTPC CURVES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update RTPC curve
  void updateRtpcCurve(int rtpcId, RtpcCurve curve) {
    final rtpc = _rtpcDefs[rtpcId];
    if (rtpc == null) return;

    _rtpcDefs[rtpcId] = rtpc.copyWith(curve: curve);
    notifyListeners();
  }

  /// Add point to RTPC curve
  void addRtpcCurvePoint(int rtpcId, RtpcCurvePoint point) {
    final rtpc = _rtpcDefs[rtpcId];
    if (rtpc == null) return;

    final currentPoints = rtpc.curve?.points.toList() ?? [];
    currentPoints.add(point);
    currentPoints.sort((a, b) => a.x.compareTo(b.x));

    _rtpcDefs[rtpcId] = rtpc.copyWith(curve: RtpcCurve(points: currentPoints));
    notifyListeners();
  }

  /// Remove point from RTPC curve
  void removeRtpcCurvePoint(int rtpcId, int pointIndex) {
    final rtpc = _rtpcDefs[rtpcId];
    if (rtpc == null || rtpc.curve == null) return;

    final currentPoints = rtpc.curve!.points.toList();
    if (pointIndex >= 0 && pointIndex < currentPoints.length) {
      currentPoints.removeAt(pointIndex);
      _rtpcDefs[rtpcId] = rtpc.copyWith(curve: RtpcCurve(points: currentPoints));
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RTPC BINDINGS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create an RTPC binding
  RtpcBinding createBinding(int rtpcId, RtpcTargetParameter target, {int? busId, int? eventId}) {
    final bindingId = _nextBindingId++;

    RtpcBinding binding;
    if (busId != null) {
      binding = RtpcBinding.forBus(bindingId, rtpcId, target, busId);
    } else {
      binding = RtpcBinding.linear(bindingId, rtpcId, target);
      if (eventId != null) {
        binding = binding.copyWith(targetEventId: eventId);
      }
    }

    _rtpcBindings[bindingId] = binding;
    notifyListeners();
    return binding;
  }

  /// Update a binding's curve
  void updateBindingCurve(int bindingId, RtpcCurve curve) {
    final binding = _rtpcBindings[bindingId];
    if (binding == null) return;

    _rtpcBindings[bindingId] = binding.copyWith(curve: curve);
    notifyListeners();
  }

  /// Enable/disable a binding
  void setBindingEnabled(int bindingId, bool enabled) {
    final binding = _rtpcBindings[bindingId];
    if (binding == null) return;

    _rtpcBindings[bindingId] = binding.copyWith(enabled: enabled);
    notifyListeners();
  }

  /// Delete a binding
  void deleteBinding(int bindingId) {
    _rtpcBindings.remove(bindingId);
    notifyListeners();
  }

  /// Get all bindings for an RTPC
  List<RtpcBinding> getBindingsForRtpc(int rtpcId) {
    return _rtpcBindings.values.where((b) => b.rtpcId == rtpcId).toList();
  }

  /// Get all bindings for a target parameter type
  List<RtpcBinding> getBindingsForTarget(RtpcTargetParameter target) {
    return _rtpcBindings.values.where((b) => b.target == target).toList();
  }

  /// Get all bindings for a bus
  List<RtpcBinding> getBindingsForBus(int busId) {
    return _rtpcBindings.values.where((b) => b.targetBusId == busId).toList();
  }

  /// Evaluate all bindings for current RTPC values
  /// Returns map of (target, busId?) -> evaluated value
  Map<(RtpcTargetParameter, int?), double> evaluateAllBindings() {
    final results = <(RtpcTargetParameter, int?), double>{};

    for (final binding in _rtpcBindings.values) {
      if (!binding.enabled) continue;

      final rtpcValue = getRtpcValue(binding.rtpcId);
      final rtpcDef = _rtpcDefs[binding.rtpcId];
      if (rtpcDef == null) continue;

      // Normalize RTPC value to 0-1 for curve evaluation
      final normalized = rtpcDef.normalizedValue;
      final outputValue = binding.curve.evaluate(normalized);

      results[(binding.target, binding.targetBusId)] = outputValue;
    }

    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export RTPC definitions to JSON
  List<Map<String, dynamic>> rtpcDefsToJson() {
    return _rtpcDefs.values.map((r) => r.toJson()).toList();
  }

  /// Export RTPC bindings to JSON
  List<Map<String, dynamic>> bindingsToJson() {
    return _rtpcBindings.values.map((b) => b.toJson()).toList();
  }

  /// Export object RTPCs to JSON
  Map<String, dynamic> objectRtpcsToJson() {
    return _objectRtpcs.map(
      (k, v) => MapEntry(k.toString(), v.map((rk, rv) => MapEntry(rk.toString(), rv))),
    );
  }

  /// Import RTPC definitions from JSON
  void rtpcDefsFromJson(List<dynamic> json) {
    for (final item in json) {
      final rtpc = RtpcDefinition.fromJson(item as Map<String, dynamic>);
      registerRtpc(rtpc);
    }
  }

  /// Import RTPC bindings from JSON
  void bindingsFromJson(List<dynamic> json) {
    for (final item in json) {
      final binding = RtpcBinding.fromJson(item as Map<String, dynamic>);
      _rtpcBindings[binding.id] = binding;
      if (binding.id >= _nextBindingId) {
        _nextBindingId = binding.id + 1;
      }
    }
    notifyListeners();
  }

  /// Import object RTPCs from JSON
  void objectRtpcsFromJson(Map<String, dynamic> json) {
    for (final entry in json.entries) {
      final gameObjectId = int.parse(entry.key);
      final rtpcs = (entry.value as Map<String, dynamic>).map(
        (rk, rv) => MapEntry(int.parse(rk), (rv as num).toDouble()),
      );
      _objectRtpcs[gameObjectId] = rtpcs;
    }
  }

  /// Clear all RTPC data
  void clear() {
    _rtpcDefs.clear();
    _rtpcBindings.clear();
    _objectRtpcs.clear();
    _nextRtpcId = 100;
    _nextBindingId = 1;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _rtpcDefs.clear();
    _rtpcBindings.clear();
    _objectRtpcs.clear();
    super.dispose();
  }
}
