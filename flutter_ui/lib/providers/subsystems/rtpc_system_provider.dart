/// RTPC System Provider
///
/// Extracted from MiddlewareProvider as part of P0.2 decomposition.
/// Manages Real-Time Parameter Control (RTPC) system (Wwise/FMOD-style).
///
/// RTPC allows continuous parameter control over audio properties:
/// - Global RTPC values (e.g., "Danger" level affecting music intensity)
/// - Per-object RTPC values (e.g., engine RPM per vehicle)
/// - RTPC Bindings map RTPC values to target parameters (volume, pitch, etc.)

import 'dart:ui' show Color;

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

  /// P3.10: RTPC Macros - group multiple bindings under one control
  final Map<int, RtpcMacro> _rtpcMacros = {};

  /// P3.11: Preset Morphs - smooth interpolation between presets
  final Map<int, PresetMorph> _presetMorphs = {};

  /// Next available RTPC ID
  int _nextRtpcId = 100;

  /// Next available binding ID
  int _nextBindingId = 1;

  /// P3.10: Next available macro ID
  int _nextMacroId = 1;

  /// P3.11: Next available morph ID
  int _nextMorphId = 1;

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

  /// P3.10: Get all RTPC macros
  Map<int, RtpcMacro> get macros => Map.unmodifiable(_rtpcMacros);

  /// P3.10: Get all macros as list
  List<RtpcMacro> get rtpcMacros => _rtpcMacros.values.toList();

  /// P3.10: Get macro count
  int get macroCount => _rtpcMacros.length;

  /// P3.11: Get all preset morphs
  Map<int, PresetMorph> get morphs => Map.unmodifiable(_presetMorphs);

  /// P3.11: Get all morphs as list
  List<PresetMorph> get presetMorphs => _presetMorphs.values.toList();

  /// P3.11: Get morph count
  int get morphCount => _presetMorphs.length;

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
  // P3.10: RTPC MACROS
  // ═══════════════════════════════════════════════════════════════════════════

  /// P3.10: Get a specific macro
  RtpcMacro? getMacro(int macroId) => _rtpcMacros[macroId];

  /// P3.10: Get macro by name
  RtpcMacro? getMacroByName(String name) {
    return _rtpcMacros.values.where((m) => m.name == name).firstOrNull;
  }

  /// P3.10: Create a new RTPC macro
  RtpcMacro createMacro({
    required String name,
    String description = '',
    double min = 0.0,
    double max = 1.0,
    double defaultValue = 0.5,
    Color? color,
  }) {
    final macroId = _nextMacroId++;
    final macro = RtpcMacro(
      id: macroId,
      name: name,
      description: description,
      min: min,
      max: max,
      currentValue: defaultValue,
      bindings: const [],
      color: color ?? const Color(0xFF4A9EFF),
      enabled: true,
    );

    _rtpcMacros[macroId] = macro;
    notifyListeners();
    return macro;
  }

  /// P3.10: Create macro from preset
  RtpcMacro createMacroFromPreset(Map<String, dynamic> preset) {
    final macroId = _nextMacroId++;
    final bindings = (preset['bindings'] as List<dynamic>?)
        ?.map((b) => RtpcMacroBinding.fromJson(b as Map<String, dynamic>))
        .toList() ?? [];

    final macro = RtpcMacro(
      id: macroId,
      name: preset['name'] as String,
      description: preset['description'] as String? ?? '',
      min: (preset['min'] as num?)?.toDouble() ?? 0.0,
      max: (preset['max'] as num?)?.toDouble() ?? 1.0,
      currentValue: (preset['default'] as num?)?.toDouble() ?? 0.5,
      bindings: bindings,
      color: Color(preset['color'] as int? ?? 0xFF4A9EFF),
      enabled: true,
    );

    _rtpcMacros[macroId] = macro;
    notifyListeners();
    return macro;
  }

  /// P3.10: Update macro value (triggers all bound parameters)
  void setMacroValue(int macroId, double value, {int interpolationMs = 0}) {
    final macro = _rtpcMacros[macroId];
    if (macro == null || !macro.enabled) return;

    final clampedValue = value.clamp(macro.min, macro.max);
    _rtpcMacros[macroId] = macro.copyWith(currentValue: clampedValue);

    // Evaluate all bindings and apply to targets
    final results = macro.copyWith(currentValue: clampedValue).evaluate();
    for (final entry in results.entries) {
      _applyMacroBinding(entry.key, entry.value, interpolationMs);
    }

    notifyListeners();
  }

  /// P3.10: Internal - apply macro binding result to target
  void _applyMacroBinding(RtpcTargetParameter target, double value, int interpolationMs) {
    // Route to appropriate FFI based on target type
    switch (target) {
      case RtpcTargetParameter.volume:
      case RtpcTargetParameter.busVolume:
        // Apply to master volume - specific bus targeting via binding.targetBusId
        _ffi.setBusVolume(5, value); // Master bus
      case RtpcTargetParameter.pitch:
      case RtpcTargetParameter.playbackRate:
        // Pitch modulation would go to engine
        break;
      case RtpcTargetParameter.lowPassFilter:
      case RtpcTargetParameter.highPassFilter:
        // Filter cutoff modulation
        break;
      case RtpcTargetParameter.pan:
        _ffi.setBusPan(5, (value * 2.0) - 1.0); // Convert 0-1 to -1..1
      case RtpcTargetParameter.width:
        // Width modulation
        break;
      case RtpcTargetParameter.reverbSend:
      case RtpcTargetParameter.delaySend:
        // Send levels
        break;
    }
  }

  /// P3.10: Add binding to macro
  void addMacroBinding(int macroId, RtpcMacroBinding binding) {
    final macro = _rtpcMacros[macroId];
    if (macro == null) return;

    final newBindings = [...macro.bindings, binding];
    _rtpcMacros[macroId] = macro.copyWith(bindings: newBindings);
    notifyListeners();
  }

  /// P3.10: Remove binding from macro
  void removeMacroBinding(int macroId, int bindingId) {
    final macro = _rtpcMacros[macroId];
    if (macro == null) return;

    final newBindings = macro.bindings.where((b) => b.id != bindingId).toList();
    _rtpcMacros[macroId] = macro.copyWith(bindings: newBindings);
    notifyListeners();
  }

  /// P3.10: Update macro binding
  void updateMacroBinding(int macroId, int bindingId, RtpcMacroBinding updated) {
    final macro = _rtpcMacros[macroId];
    if (macro == null) return;

    final newBindings = macro.bindings.map((b) => b.id == bindingId ? updated : b).toList();
    _rtpcMacros[macroId] = macro.copyWith(bindings: newBindings);
    notifyListeners();
  }

  /// P3.10: Enable/disable macro
  void setMacroEnabled(int macroId, bool enabled) {
    final macro = _rtpcMacros[macroId];
    if (macro == null) return;

    _rtpcMacros[macroId] = macro.copyWith(enabled: enabled);
    notifyListeners();
  }

  /// P3.10: Delete macro
  void deleteMacro(int macroId) {
    _rtpcMacros.remove(macroId);
    notifyListeners();
  }

  /// P3.10: Update macro properties
  void updateMacro(int macroId, {
    String? name,
    String? description,
    double? min,
    double? max,
    Color? color,
  }) {
    final macro = _rtpcMacros[macroId];
    if (macro == null) return;

    _rtpcMacros[macroId] = macro.copyWith(
      name: name,
      description: description,
      min: min,
      max: max,
      color: color,
    );
    notifyListeners();
  }

  /// P3.10: Reset macro to default value
  void resetMacro(int macroId, {int interpolationMs = 100}) {
    final macro = _rtpcMacros[macroId];
    if (macro == null) return;

    // Default is midpoint
    final defaultValue = (macro.min + macro.max) / 2.0;
    setMacroValue(macroId, defaultValue, interpolationMs: interpolationMs);
  }

  /// P3.10: Get macros targeting a specific parameter
  List<RtpcMacro> getMacrosForTarget(RtpcTargetParameter target) {
    return _rtpcMacros.values.where((m) =>
      m.bindings.any((b) => b.target == target)
    ).toList();
  }

  /// P3.10: Evaluate all macros and return combined results
  Map<RtpcTargetParameter, double> evaluateAllMacros() {
    final results = <RtpcTargetParameter, double>{};

    for (final macro in _rtpcMacros.values) {
      if (!macro.enabled) continue;

      final macroResults = macro.evaluate();
      for (final entry in macroResults.entries) {
        // Combine multiple macros affecting same target (multiply for volume, add for others)
        if (results.containsKey(entry.key)) {
          if (entry.key == RtpcTargetParameter.volume) {
            results[entry.key] = results[entry.key]! * entry.value;
          } else {
            results[entry.key] = (results[entry.key]! + entry.value).clamp(0.0, 1.0);
          }
        } else {
          results[entry.key] = entry.value;
        }
      }
    }

    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P3.11: PRESET MORPHING
  // ═══════════════════════════════════════════════════════════════════════════

  /// P3.11: Get a specific morph
  PresetMorph? getMorph(int morphId) => _presetMorphs[morphId];

  /// P3.11: Get morph by name
  PresetMorph? getMorphByName(String name) {
    return _presetMorphs.values.where((m) => m.name == name).firstOrNull;
  }

  /// P3.11: Create a new preset morph
  PresetMorph createMorph({
    required String name,
    String description = '',
    required String presetA,
    required String presetB,
    List<MorphParameter>? parameters,
    double durationMs = 0.0,
    MorphCurve globalCurve = MorphCurve.linear,
    Color? color,
  }) {
    final morphId = _nextMorphId++;
    final morph = PresetMorph(
      id: morphId,
      name: name,
      description: description,
      presetA: presetA,
      presetB: presetB,
      parameters: parameters ?? [],
      position: 0.0,
      durationMs: durationMs,
      globalCurve: globalCurve,
      enabled: true,
      color: color ?? const Color(0xFF9C27B0),
    );

    _presetMorphs[morphId] = morph;
    notifyListeners();
    return morph;
  }

  /// P3.11: Create morph from template
  PresetMorph createMorphFromTemplate(String templateType, String name, {
    String presetA = 'Preset A',
    String presetB = 'Preset B',
  }) {
    final morphId = _nextMorphId++;

    PresetMorph morph;
    switch (templateType) {
      case 'crossfade':
        morph = PresetMorph.volumeCrossfade(morphId, name, presetA, presetB);
      case 'filter':
        morph = PresetMorph.filterSweep(morphId, name);
      case 'tension':
        morph = PresetMorph.tensionBuilder(morphId, name);
      default:
        morph = PresetMorph(
          id: morphId,
          name: name,
          presetA: presetA,
          presetB: presetB,
        );
    }

    _presetMorphs[morphId] = morph;
    notifyListeners();
    return morph;
  }

  /// P3.11: Set morph position (0.0 = preset A, 1.0 = preset B)
  void setMorphPosition(int morphId, double position) {
    final morph = _presetMorphs[morphId];
    if (morph == null || !morph.enabled) return;

    final clampedPosition = position.clamp(0.0, 1.0);
    _presetMorphs[morphId] = morph.copyWith(position: clampedPosition);

    // Evaluate and apply all parameters
    final results = morph.copyWith(position: clampedPosition).evaluate();
    for (final entry in results.entries) {
      _applyMorphParameter(entry.key, entry.value);
    }

    notifyListeners();
  }

  /// P3.11: Internal - apply morph parameter to target
  void _applyMorphParameter(RtpcTargetParameter target, double value) {
    switch (target) {
      case RtpcTargetParameter.volume:
      case RtpcTargetParameter.busVolume:
        _ffi.setBusVolume(5, value);
      case RtpcTargetParameter.pan:
        _ffi.setBusPan(5, (value * 2.0) - 1.0);
      case RtpcTargetParameter.pitch:
      case RtpcTargetParameter.playbackRate:
      case RtpcTargetParameter.lowPassFilter:
      case RtpcTargetParameter.highPassFilter:
      case RtpcTargetParameter.width:
      case RtpcTargetParameter.reverbSend:
      case RtpcTargetParameter.delaySend:
        // These would route to appropriate DSP modules
        break;
    }
  }

  /// P3.11: Add parameter to morph
  void addMorphParameter(int morphId, MorphParameter parameter) {
    final morph = _presetMorphs[morphId];
    if (morph == null) return;

    final newParams = [...morph.parameters, parameter];
    _presetMorphs[morphId] = morph.copyWith(parameters: newParams);
    notifyListeners();
  }

  /// P3.11: Remove parameter from morph
  void removeMorphParameter(int morphId, String parameterName) {
    final morph = _presetMorphs[morphId];
    if (morph == null) return;

    final newParams = morph.parameters.where((p) => p.name != parameterName).toList();
    _presetMorphs[morphId] = morph.copyWith(parameters: newParams);
    notifyListeners();
  }

  /// P3.11: Update morph parameter
  void updateMorphParameter(int morphId, String parameterName, MorphParameter updated) {
    final morph = _presetMorphs[morphId];
    if (morph == null) return;

    final newParams = morph.parameters.map((p) => p.name == parameterName ? updated : p).toList();
    _presetMorphs[morphId] = morph.copyWith(parameters: newParams);
    notifyListeners();
  }

  /// P3.11: Enable/disable morph
  void setMorphEnabled(int morphId, bool enabled) {
    final morph = _presetMorphs[morphId];
    if (morph == null) return;

    _presetMorphs[morphId] = morph.copyWith(enabled: enabled);
    notifyListeners();
  }

  /// P3.11: Delete morph
  void deleteMorph(int morphId) {
    _presetMorphs.remove(morphId);
    notifyListeners();
  }

  /// P3.11: Update morph properties
  void updateMorph(int morphId, {
    String? name,
    String? description,
    String? presetA,
    String? presetB,
    double? durationMs,
    MorphCurve? globalCurve,
    Color? color,
  }) {
    final morph = _presetMorphs[morphId];
    if (morph == null) return;

    _presetMorphs[morphId] = morph.copyWith(
      name: name,
      description: description,
      presetA: presetA,
      presetB: presetB,
      durationMs: durationMs,
      globalCurve: globalCurve,
      color: color,
    );
    notifyListeners();
  }

  /// P3.11: Morph to preset A (position = 0.0)
  void morphToPresetA(int morphId) {
    setMorphPosition(morphId, 0.0);
  }

  /// P3.11: Morph to preset B (position = 1.0)
  void morphToPresetB(int morphId) {
    setMorphPosition(morphId, 1.0);
  }

  /// P3.11: Morph to center (position = 0.5)
  void morphToCenter(int morphId) {
    setMorphPosition(morphId, 0.5);
  }

  /// P3.11: Evaluate all morphs and return combined results
  Map<RtpcTargetParameter, double> evaluateAllMorphs() {
    final results = <RtpcTargetParameter, double>{};

    for (final morph in _presetMorphs.values) {
      if (!morph.enabled) continue;

      final morphResults = morph.evaluate();
      for (final entry in morphResults.entries) {
        // Latest morph wins for same target
        results[entry.key] = entry.value;
      }
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

  /// P3.10: Export macros to JSON
  List<Map<String, dynamic>> macrosToJson() {
    return _rtpcMacros.values.map((m) => m.toJson()).toList();
  }

  /// P3.11: Export morphs to JSON
  List<Map<String, dynamic>> morphsToJson() {
    return _presetMorphs.values.map((m) => m.toJson()).toList();
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

  /// P3.10: Import macros from JSON
  void macrosFromJson(List<dynamic> json) {
    for (final item in json) {
      final macro = RtpcMacro.fromJson(item as Map<String, dynamic>);
      _rtpcMacros[macro.id] = macro;
      if (macro.id >= _nextMacroId) {
        _nextMacroId = macro.id + 1;
      }
    }
    notifyListeners();
  }

  /// P3.11: Import morphs from JSON
  void morphsFromJson(List<dynamic> json) {
    for (final item in json) {
      final morph = PresetMorph.fromJson(item as Map<String, dynamic>);
      _presetMorphs[morph.id] = morph;
      if (morph.id >= _nextMorphId) {
        _nextMorphId = morph.id + 1;
      }
    }
    notifyListeners();
  }

  /// Clear all RTPC data
  void clear() {
    _rtpcDefs.clear();
    _rtpcBindings.clear();
    _objectRtpcs.clear();
    _rtpcMacros.clear();
    _presetMorphs.clear();
    _nextRtpcId = 100;
    _nextBindingId = 1;
    _nextMacroId = 1;
    _nextMorphId = 1;
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
    _rtpcMacros.clear();
    _presetMorphs.clear();
    super.dispose();
  }
}
