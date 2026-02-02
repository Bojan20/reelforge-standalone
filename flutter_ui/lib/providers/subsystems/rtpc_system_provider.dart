/// RTPC System Provider
///
/// Extracted from MiddlewareProvider as part of P0.2 decomposition.
/// Manages Real-Time Parameter Control (RTPC) system (Wwise/FMOD-style).
///
/// RTPC allows continuous parameter control over audio properties:
/// - Global RTPC values (e.g., "Danger" level affecting music intensity)
/// - Per-object RTPC values (e.g., engine RPM per vehicle)
/// - RTPC Bindings map RTPC values to target parameters (volume, pitch, etc.)
///
/// P11.1.2: Extended with DSP parameter routing.
/// Enables game-driven DSP (e.g., winTier modulates filter cutoff for excitement).

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import '../../models/middleware_models.dart';
import '../../src/rust/native_ffi.dart';
import '../dsp_chain_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// P11.1.2: DSP BINDING MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Binding from RTPC to DSP processor parameter
///
/// Enables dynamic DSP control based on game state.
/// Example: winTier RTPC → filter cutoff (more excitement at higher wins)
class RtpcDspBinding {
  final int id;
  final int rtpcId;
  final RtpcTargetParameter target;
  final int trackId;           // Target track (0 = master)
  final int slotIndex;         // DSP slot in chain
  final int paramIndex;        // Parameter index in processor
  final RtpcCurve curve;       // Mapping curve
  final bool enabled;
  final String? label;         // Optional descriptive label

  const RtpcDspBinding({
    required this.id,
    required this.rtpcId,
    required this.target,
    required this.trackId,
    required this.slotIndex,
    required this.paramIndex,
    required this.curve,
    this.enabled = true,
    this.label,
  });

  RtpcDspBinding copyWith({
    int? id,
    int? rtpcId,
    RtpcTargetParameter? target,
    int? trackId,
    int? slotIndex,
    int? paramIndex,
    RtpcCurve? curve,
    bool? enabled,
    String? label,
  }) {
    return RtpcDspBinding(
      id: id ?? this.id,
      rtpcId: rtpcId ?? this.rtpcId,
      target: target ?? this.target,
      trackId: trackId ?? this.trackId,
      slotIndex: slotIndex ?? this.slotIndex,
      paramIndex: paramIndex ?? this.paramIndex,
      curve: curve ?? this.curve,
      enabled: enabled ?? this.enabled,
      label: label ?? this.label,
    );
  }

  /// Evaluate binding for given normalized RTPC value (0-1)
  double evaluate(double normalizedRtpcValue) {
    if (!enabled) return curve.evaluate(0.5); // Midpoint when disabled
    return curve.evaluate(normalizedRtpcValue);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'rtpcId': rtpcId,
    'target': target.index,
    'trackId': trackId,
    'slotIndex': slotIndex,
    'paramIndex': paramIndex,
    'curve': curve.toJson(),
    'enabled': enabled,
    'label': label,
  };

  factory RtpcDspBinding.fromJson(Map<String, dynamic> json) {
    return RtpcDspBinding(
      id: json['id'] as int,
      rtpcId: json['rtpcId'] as int,
      target: RtpcTargetParameterExtension.fromIndex(json['target'] as int),
      trackId: json['trackId'] as int? ?? 0,
      slotIndex: json['slotIndex'] as int,
      paramIndex: json['paramIndex'] as int,
      curve: RtpcCurve.fromJson(json['curve'] as Map<String, dynamic>),
      enabled: json['enabled'] as bool? ?? true,
      label: json['label'] as String?,
    );
  }
}

/// DSP parameter index mapping
///
/// Maps RtpcTargetParameter to processor-specific param indices.
/// Used by insertSetParam(trackId, slotIndex, paramIndex, value).
class DspParamMapping {
  /// Get param index for a target parameter within a processor type
  static int? getParamIndex(DspNodeType processorType, RtpcTargetParameter target) {
    switch (processorType) {
      case DspNodeType.eq:
        return _getEqParamIndex(target);
      case DspNodeType.compressor:
        return _getCompressorParamIndex(target);
      case DspNodeType.limiter:
        return _getLimiterParamIndex(target);
      case DspNodeType.gate:
        return _getGateParamIndex(target);
      case DspNodeType.reverb:
        return _getReverbParamIndex(target);
      case DspNodeType.delay:
        return _getDelayParamIndex(target);
      case DspNodeType.saturation:
        return _getSaturationParamIndex(target);
      case DspNodeType.deEsser:
        return _getDeEsserParamIndex(target);
      case DspNodeType.expander:
        return _getExpanderParamIndex(target);
    }
  }

  // EQ param indices (per-band, but global filter cutoff/resonance)
  static int? _getEqParamIndex(RtpcTargetParameter target) {
    switch (target) {
      case RtpcTargetParameter.filterCutoff:
      case RtpcTargetParameter.lowPassFilter:
        return 0; // Global high-cut frequency
      case RtpcTargetParameter.filterResonance:
        return 1; // Global Q
      case RtpcTargetParameter.highPassFilter:
        return 2; // Global low-cut frequency
      default:
        return null;
    }
  }

  // Compressor param indices
  static int? _getCompressorParamIndex(RtpcTargetParameter target) {
    switch (target) {
      case RtpcTargetParameter.compressorThreshold: return 0;
      case RtpcTargetParameter.compressorRatio: return 1;
      case RtpcTargetParameter.compressorAttack: return 2;
      case RtpcTargetParameter.compressorRelease: return 3;
      case RtpcTargetParameter.compressorKnee: return 4;
      case RtpcTargetParameter.compressorMakeup: return 5;
      default: return null;
    }
  }

  // Limiter param indices
  static int? _getLimiterParamIndex(RtpcTargetParameter target) {
    switch (target) {
      case RtpcTargetParameter.limiterCeiling: return 0;
      case RtpcTargetParameter.limiterRelease: return 1;
      default: return null;
    }
  }

  // Gate param indices
  static int? _getGateParamIndex(RtpcTargetParameter target) {
    switch (target) {
      case RtpcTargetParameter.gateThreshold: return 0;
      case RtpcTargetParameter.gateAttack: return 1;
      case RtpcTargetParameter.gateRelease: return 2;
      case RtpcTargetParameter.gateRange: return 3;
      default: return null;
    }
  }

  // Reverb param indices
  static int? _getReverbParamIndex(RtpcTargetParameter target) {
    switch (target) {
      case RtpcTargetParameter.reverbDecay: return 0;
      case RtpcTargetParameter.reverbPreDelay: return 1;
      case RtpcTargetParameter.reverbDamping: return 2;
      case RtpcTargetParameter.reverbSize: return 3;
      case RtpcTargetParameter.reverbMix: return 4;
      default: return null;
    }
  }

  // Delay param indices
  static int? _getDelayParamIndex(RtpcTargetParameter target) {
    switch (target) {
      case RtpcTargetParameter.delayTime: return 0;
      case RtpcTargetParameter.delayFeedback: return 1;
      case RtpcTargetParameter.delayHighCut: return 2;
      case RtpcTargetParameter.delayLowCut: return 3;
      case RtpcTargetParameter.delayMix: return 4;
      default: return null;
    }
  }

  // Saturation param indices
  static int? _getSaturationParamIndex(RtpcTargetParameter target) {
    switch (target) {
      case RtpcTargetParameter.saturationDrive: return 0;
      case RtpcTargetParameter.saturationMix: return 1;
      default: return null;
    }
  }

  // De-Esser param indices
  static int? _getDeEsserParamIndex(RtpcTargetParameter target) {
    switch (target) {
      case RtpcTargetParameter.deEsserFrequency: return 0;
      case RtpcTargetParameter.deEsserThreshold: return 1;
      case RtpcTargetParameter.deEsserRange: return 2;
      default: return null;
    }
  }

  // Expander param indices (similar to compressor)
  static int? _getExpanderParamIndex(RtpcTargetParameter target) {
    switch (target) {
      case RtpcTargetParameter.compressorThreshold: return 0;
      case RtpcTargetParameter.compressorRatio: return 1;
      case RtpcTargetParameter.compressorAttack: return 2;
      case RtpcTargetParameter.compressorRelease: return 3;
      case RtpcTargetParameter.compressorKnee: return 4;
      default: return null;
    }
  }

  /// Get valid targets for a processor type
  static List<RtpcTargetParameter> getValidTargets(DspNodeType processorType) {
    switch (processorType) {
      case DspNodeType.eq:
        return [
          RtpcTargetParameter.filterCutoff,
          RtpcTargetParameter.filterResonance,
          RtpcTargetParameter.lowPassFilter,
          RtpcTargetParameter.highPassFilter,
        ];
      case DspNodeType.compressor:
      case DspNodeType.expander:
        return [
          RtpcTargetParameter.compressorThreshold,
          RtpcTargetParameter.compressorRatio,
          RtpcTargetParameter.compressorAttack,
          RtpcTargetParameter.compressorRelease,
          RtpcTargetParameter.compressorMakeup,
          RtpcTargetParameter.compressorKnee,
        ];
      case DspNodeType.limiter:
        return [
          RtpcTargetParameter.limiterCeiling,
          RtpcTargetParameter.limiterRelease,
        ];
      case DspNodeType.gate:
        return [
          RtpcTargetParameter.gateThreshold,
          RtpcTargetParameter.gateAttack,
          RtpcTargetParameter.gateRelease,
          RtpcTargetParameter.gateRange,
        ];
      case DspNodeType.reverb:
        return [
          RtpcTargetParameter.reverbDecay,
          RtpcTargetParameter.reverbPreDelay,
          RtpcTargetParameter.reverbDamping,
          RtpcTargetParameter.reverbSize,
          RtpcTargetParameter.reverbMix,
        ];
      case DspNodeType.delay:
        return [
          RtpcTargetParameter.delayTime,
          RtpcTargetParameter.delayFeedback,
          RtpcTargetParameter.delayHighCut,
          RtpcTargetParameter.delayLowCut,
          RtpcTargetParameter.delayMix,
        ];
      case DspNodeType.saturation:
        return [
          RtpcTargetParameter.saturationDrive,
          RtpcTargetParameter.saturationMix,
        ];
      case DspNodeType.deEsser:
        return [
          RtpcTargetParameter.deEsserFrequency,
          RtpcTargetParameter.deEsserThreshold,
          RtpcTargetParameter.deEsserRange,
        ];
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

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

  /// P11.1.2: DSP bindings (RTPC → DSP processor parameters)
  final Map<int, RtpcDspBinding> _dspBindings = {};

  /// Next available RTPC ID
  int _nextRtpcId = 100;

  /// Next available binding ID
  int _nextBindingId = 1;

  /// P3.10: Next available macro ID
  int _nextMacroId = 1;

  /// P3.11: Next available morph ID
  int _nextMorphId = 1;

  /// P11.1.2: Next available DSP binding ID
  int _nextDspBindingId = 1;

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

  /// P11.1.2: Get all DSP bindings
  Map<int, RtpcDspBinding> get dspBindings => Map.unmodifiable(_dspBindings);

  /// P11.1.2: Get all DSP bindings as list
  List<RtpcDspBinding> get dspBindingsList => _dspBindings.values.toList();

  /// P11.1.2: Get DSP binding count
  int get dspBindingCount => _dspBindings.length;

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

    // P11.1.2: Apply DSP bindings for this RTPC
    _applyDspBindingsForRtpc(rtpcId);

    notifyListeners();
  }

  /// P11.1.2: Internal - apply all DSP bindings for a specific RTPC
  void _applyDspBindingsForRtpc(int rtpcId) {
    final rtpcDef = _rtpcDefs[rtpcId];
    if (rtpcDef == null) return;

    final normalized = rtpcDef.normalizedValue;

    for (final binding in _dspBindings.values) {
      if (binding.rtpcId != rtpcId || !binding.enabled) continue;

      final outputValue = binding.evaluate(normalized);
      _applyDspParameter(binding, outputValue);
    }
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
  // P11.1.2: RTPC → DSP BINDINGS
  // ═══════════════════════════════════════════════════════════════════════════

  /// P11.1.2: Get a specific DSP binding
  RtpcDspBinding? getDspBinding(int bindingId) => _dspBindings[bindingId];

  /// P11.1.2: Get DSP bindings for an RTPC
  List<RtpcDspBinding> getDspBindingsForRtpc(int rtpcId) {
    return _dspBindings.values.where((b) => b.rtpcId == rtpcId).toList();
  }

  /// P11.1.2: Get DSP bindings for a track
  List<RtpcDspBinding> getDspBindingsForTrack(int trackId) {
    return _dspBindings.values.where((b) => b.trackId == trackId).toList();
  }

  /// P11.1.2: Get DSP bindings for a specific slot
  List<RtpcDspBinding> getDspBindingsForSlot(int trackId, int slotIndex) {
    return _dspBindings.values.where((b) =>
      b.trackId == trackId && b.slotIndex == slotIndex
    ).toList();
  }

  /// P11.1.2: Get DSP bindings targeting a specific parameter
  List<RtpcDspBinding> getDspBindingsForTarget(RtpcTargetParameter target) {
    return _dspBindings.values.where((b) => b.target == target).toList();
  }

  /// P11.1.2: Create a DSP binding
  ///
  /// Binds an RTPC to a DSP processor parameter.
  /// Example: winTier RTPC → filter cutoff (more excitement at higher wins)
  RtpcDspBinding createDspBinding({
    required int rtpcId,
    required RtpcTargetParameter target,
    required int trackId,
    required int slotIndex,
    int? paramIndex,
    DspNodeType? processorType,
    RtpcCurve? curve,
    String? label,
  }) {
    final bindingId = _nextDspBindingId++;

    // Auto-determine param index if not provided
    int resolvedParamIndex = paramIndex ?? 0;
    if (paramIndex == null && processorType != null) {
      resolvedParamIndex = DspParamMapping.getParamIndex(processorType, target) ?? 0;
    }

    // Create default curve if not provided
    final bindingCurve = curve ?? RtpcCurve.linear(
      0.0,  // minIn
      1.0,  // maxIn
      target.defaultRange.$1,  // minOut
      target.defaultRange.$2,  // maxOut
    );

    final binding = RtpcDspBinding(
      id: bindingId,
      rtpcId: rtpcId,
      target: target,
      trackId: trackId,
      slotIndex: slotIndex,
      paramIndex: resolvedParamIndex,
      curve: bindingCurve,
      label: label ?? '${target.displayName} (Track $trackId, Slot $slotIndex)',
    );

    _dspBindings[bindingId] = binding;
    notifyListeners();
    return binding;
  }

  /// P11.1.2: Create DSP binding with preset curve shapes
  RtpcDspBinding createDspBindingWithPreset({
    required int rtpcId,
    required RtpcTargetParameter target,
    required int trackId,
    required int slotIndex,
    required DspNodeType processorType,
    required String curvePreset,
    String? label,
  }) {
    final paramIndex = DspParamMapping.getParamIndex(processorType, target) ?? 0;
    final range = target.defaultRange;

    RtpcCurve curve;
    switch (curvePreset) {
      case 'linear':
        curve = RtpcCurve.linear(0.0, 1.0, range.$1, range.$2);
      case 'linear_inverted':
        curve = RtpcCurve.linear(0.0, 1.0, range.$2, range.$1);
      case 'exponential':
        // Exponential curve: slow start, fast finish
        curve = RtpcCurve(points: [
          RtpcCurvePoint(x: 0.0, y: range.$1, shape: RtpcCurveShape.exp3),
          RtpcCurvePoint(x: 1.0, y: range.$2),
        ]);
      case 'logarithmic':
        // Logarithmic curve: fast start, slow finish
        curve = RtpcCurve(points: [
          RtpcCurvePoint(x: 0.0, y: range.$1, shape: RtpcCurveShape.log3),
          RtpcCurvePoint(x: 1.0, y: range.$2),
        ]);
      case 's_curve':
        // S-curve: smooth transitions
        curve = RtpcCurve(points: [
          RtpcCurvePoint(x: 0.0, y: range.$1, shape: RtpcCurveShape.sCurve),
          RtpcCurvePoint(x: 1.0, y: range.$2),
        ]);
      case 'threshold_50':
        // Output stays at min until RTPC reaches 0.5, then jumps to max
        curve = RtpcCurve(points: [
          RtpcCurvePoint(x: 0.0, y: range.$1, shape: RtpcCurveShape.constant),
          RtpcCurvePoint(x: 0.5, y: range.$2),
          RtpcCurvePoint(x: 1.0, y: range.$2),
        ]);
      default:
        curve = RtpcCurve.linear(0.0, 1.0, range.$1, range.$2);
    }

    return createDspBinding(
      rtpcId: rtpcId,
      target: target,
      trackId: trackId,
      slotIndex: slotIndex,
      paramIndex: paramIndex,
      curve: curve,
      label: label,
    );
  }

  /// P11.1.2: Update DSP binding curve
  void updateDspBindingCurve(int bindingId, RtpcCurve curve) {
    final binding = _dspBindings[bindingId];
    if (binding == null) return;

    _dspBindings[bindingId] = binding.copyWith(curve: curve);
    notifyListeners();
  }

  /// P11.1.2: Enable/disable DSP binding
  void setDspBindingEnabled(int bindingId, bool enabled) {
    final binding = _dspBindings[bindingId];
    if (binding == null) return;

    _dspBindings[bindingId] = binding.copyWith(enabled: enabled);
    notifyListeners();
  }

  /// P11.1.2: Delete DSP binding
  void deleteDspBinding(int bindingId) {
    _dspBindings.remove(bindingId);
    notifyListeners();
  }

  /// P11.1.2: Delete all DSP bindings for a track
  void deleteDspBindingsForTrack(int trackId) {
    _dspBindings.removeWhere((_, b) => b.trackId == trackId);
    notifyListeners();
  }

  /// P11.1.2: Delete all DSP bindings for a slot (when processor removed)
  void deleteDspBindingsForSlot(int trackId, int slotIndex) {
    _dspBindings.removeWhere((_, b) =>
      b.trackId == trackId && b.slotIndex == slotIndex
    );
    notifyListeners();
  }

  /// P11.1.2: Evaluate and apply all DSP bindings for current RTPC values
  ///
  /// This is the main method for real-time DSP modulation.
  /// Called whenever RTPC values change to update all bound DSP parameters.
  void applyAllDspBindings() {
    for (final binding in _dspBindings.values) {
      if (!binding.enabled) continue;

      final rtpcDef = _rtpcDefs[binding.rtpcId];
      if (rtpcDef == null) continue;

      // Get normalized RTPC value (0-1)
      final normalized = rtpcDef.normalizedValue;

      // Evaluate curve to get output value
      final outputValue = binding.evaluate(normalized);

      // Apply to DSP via FFI
      _applyDspParameter(binding, outputValue);
    }
  }

  /// P11.1.2: Apply a single DSP binding
  void applyDspBinding(int bindingId) {
    final binding = _dspBindings[bindingId];
    if (binding == null || !binding.enabled) return;

    final rtpcDef = _rtpcDefs[binding.rtpcId];
    if (rtpcDef == null) return;

    final normalized = rtpcDef.normalizedValue;
    final outputValue = binding.evaluate(normalized);
    _applyDspParameter(binding, outputValue);
  }

  /// P11.1.2: Internal - apply DSP parameter via FFI
  void _applyDspParameter(RtpcDspBinding binding, double value) {
    // Use insertSetParam to update the DSP processor parameter
    final result = _ffi.insertSetParam(
      binding.trackId,
      binding.slotIndex,
      binding.paramIndex,
      value,
    );

    if (result != 0) {
      debugPrint('[RtpcSystemProvider] DSP param set failed: '
          'track=${binding.trackId}, slot=${binding.slotIndex}, '
          'param=${binding.paramIndex}, value=$value');
    }
  }

  /// P11.1.2: Evaluate all DSP bindings and return results (for preview)
  Map<int, double> evaluateAllDspBindings() {
    final results = <int, double>{};

    for (final binding in _dspBindings.values) {
      if (!binding.enabled) continue;

      final rtpcDef = _rtpcDefs[binding.rtpcId];
      if (rtpcDef == null) continue;

      final normalized = rtpcDef.normalizedValue;
      results[binding.id] = binding.evaluate(normalized);
    }

    return results;
  }

  /// P11.1.2: Get DSP bindings as JSON for serialization
  List<Map<String, dynamic>> dspBindingsToJson() {
    return _dspBindings.values.map((b) => b.toJson()).toList();
  }

  /// P11.1.2: Import DSP bindings from JSON
  void dspBindingsFromJson(List<dynamic> json) {
    for (final item in json) {
      final binding = RtpcDspBinding.fromJson(item as Map<String, dynamic>);
      _dspBindings[binding.id] = binding;
      if (binding.id >= _nextDspBindingId) {
        _nextDspBindingId = binding.id + 1;
      }
    }
    notifyListeners();
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
    // P11.1.2: Extended with DSP parameter support

    // Check if this is a DSP parameter
    if (target.isDspParameter) {
      // DSP parameters are routed through DSP bindings
      // Find any DSP bindings targeting this parameter and apply
      final dspBindingsForTarget = getDspBindingsForTarget(target);
      for (final binding in dspBindingsForTarget) {
        if (!binding.enabled) continue;
        _applyDspParameter(binding, value);
      }
      return;
    }

    // Handle basic audio parameters directly
    switch (target) {
      case RtpcTargetParameter.volume:
      case RtpcTargetParameter.busVolume:
        // Apply to master volume - specific bus targeting via binding.targetBusId
        _ffi.setBusVolume(5, value); // Master bus

      case RtpcTargetParameter.pitch:
      case RtpcTargetParameter.playbackRate:
        // Pitch modulation would go to engine
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

      default:
        // Other parameters handled by DSP bindings
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
    // P11.1.2: Extended with DSP parameter support

    // Check if this is a DSP parameter
    if (target.isDspParameter) {
      // DSP parameters are routed through DSP bindings
      final dspBindingsForTarget = getDspBindingsForTarget(target);
      for (final binding in dspBindingsForTarget) {
        if (!binding.enabled) continue;
        _applyDspParameter(binding, value);
      }
      return;
    }

    // Handle basic audio parameters directly
    switch (target) {
      case RtpcTargetParameter.volume:
      case RtpcTargetParameter.busVolume:
        _ffi.setBusVolume(5, value);

      case RtpcTargetParameter.pan:
        _ffi.setBusPan(5, (value * 2.0) - 1.0);

      case RtpcTargetParameter.pitch:
      case RtpcTargetParameter.playbackRate:
      case RtpcTargetParameter.width:
      case RtpcTargetParameter.reverbSend:
      case RtpcTargetParameter.delaySend:
        // Basic audio modulation
        break;

      default:
        // Other parameters handled by DSP bindings
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
    _dspBindings.clear();  // P11.1.2
    _nextRtpcId = 100;
    _nextBindingId = 1;
    _nextMacroId = 1;
    _nextMorphId = 1;
    _nextDspBindingId = 1;  // P11.1.2
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
    _dspBindings.clear();  // P11.1.2
    super.dispose();
  }
}
