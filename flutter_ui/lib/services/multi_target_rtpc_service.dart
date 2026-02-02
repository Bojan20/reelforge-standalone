/// FluxForge Studio Multi-Target RTPC Service
///
/// P2-MW-4: One RTPC controls multiple targets with per-target scaling
/// - Single RTPC drives multiple parameters
/// - Per-target scaling and offset
/// - Curve remapping per target
/// - Enable/disable per target
library;

import 'package:flutter/foundation.dart';
import '../models/middleware_models.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MULTI-TARGET BINDING
// ═══════════════════════════════════════════════════════════════════════════════

/// A single target binding within a multi-target RTPC
class RtpcTargetBinding {
  final String id;
  final RtpcTargetParameter parameter;
  final String? targetObjectId; // null = global

  /// Scale factor applied to RTPC value
  final double scale;

  /// Offset added after scaling
  final double offset;

  /// Output range min (null = use parameter default)
  final double? _outputMin;

  /// Output range max (null = use parameter default)
  final double? _outputMax;

  /// Invert the output
  final bool inverted;

  /// Enable/disable this binding
  final bool enabled;

  /// Custom curve for this binding
  final RtpcCurve? curve;

  const RtpcTargetBinding({
    required this.id,
    required this.parameter,
    this.targetObjectId,
    this.scale = 1.0,
    this.offset = 0.0,
    double? outputMin,
    double? outputMax,
    this.inverted = false,
    this.enabled = true,
    this.curve,
  })  : _outputMin = outputMin,
        _outputMax = outputMax;

  /// Get output min (uses parameter default if not set)
  double get outputMin => _outputMin ?? parameter.defaultRange.$1;

  /// Get output max (uses parameter default if not set)
  double get outputMax => _outputMax ?? parameter.defaultRange.$2;

  RtpcTargetBinding copyWith({
    String? id,
    RtpcTargetParameter? parameter,
    String? targetObjectId,
    double? scale,
    double? offset,
    double? outputMin,
    double? outputMax,
    bool? inverted,
    bool? enabled,
    RtpcCurve? curve,
  }) {
    return RtpcTargetBinding(
      id: id ?? this.id,
      parameter: parameter ?? this.parameter,
      targetObjectId: targetObjectId ?? this.targetObjectId,
      scale: scale ?? this.scale,
      offset: offset ?? this.offset,
      outputMin: outputMin ?? this.outputMin,
      outputMax: outputMax ?? this.outputMax,
      inverted: inverted ?? this.inverted,
      enabled: enabled ?? this.enabled,
      curve: curve ?? this.curve,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'parameter': parameter.index,
        'targetObjectId': targetObjectId,
        'scale': scale,
        'offset': offset,
        'outputMin': outputMin,
        'outputMax': outputMax,
        'inverted': inverted,
        'enabled': enabled,
        'curve': curve?.toJson(),
      };

  factory RtpcTargetBinding.fromJson(Map<String, dynamic> json) {
    return RtpcTargetBinding(
      id: json['id'] as String? ?? '',
      parameter: RtpcTargetParameter.values[json['parameter'] as int? ?? 0],
      targetObjectId: json['targetObjectId'] as String?,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      offset: (json['offset'] as num?)?.toDouble() ?? 0.0,
      outputMin: (json['outputMin'] as num?)?.toDouble(),
      outputMax: (json['outputMax'] as num?)?.toDouble(),
      inverted: json['inverted'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? true,
      curve: json['curve'] != null
          ? RtpcCurve.fromJson(json['curve'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Multi-target RTPC configuration
class MultiTargetRtpc {
  final int rtpcId;
  final String name;
  final List<RtpcTargetBinding> targets;
  final bool enabled;

  const MultiTargetRtpc({
    required this.rtpcId,
    required this.name,
    this.targets = const [],
    this.enabled = true,
  });

  MultiTargetRtpc copyWith({
    int? rtpcId,
    String? name,
    List<RtpcTargetBinding>? targets,
    bool? enabled,
  }) {
    return MultiTargetRtpc(
      rtpcId: rtpcId ?? this.rtpcId,
      name: name ?? this.name,
      targets: targets ?? this.targets,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'rtpcId': rtpcId,
        'name': name,
        'targets': targets.map((t) => t.toJson()).toList(),
        'enabled': enabled,
      };

  factory MultiTargetRtpc.fromJson(Map<String, dynamic> json) {
    return MultiTargetRtpc(
      rtpcId: json['rtpcId'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      targets: (json['targets'] as List<dynamic>?)
              ?.map(
                  (t) => RtpcTargetBinding.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Service for multi-target RTPC evaluation
class MultiTargetRtpcService extends ChangeNotifier {
  static final MultiTargetRtpcService _instance = MultiTargetRtpcService._();
  static MultiTargetRtpcService get instance => _instance;

  MultiTargetRtpcService._();

  /// Registered multi-target RTPCs
  final Map<int, MultiTargetRtpc> _multiTargets = {};

  /// Current RTPC values (cached from middleware)
  final Map<int, double> _rtpcValues = {};

  /// Get all registered multi-target RTPCs
  List<MultiTargetRtpc> get multiTargets => _multiTargets.values.toList();

  /// Register a multi-target RTPC
  void registerMultiTarget(MultiTargetRtpc config) {
    _multiTargets[config.rtpcId] = config;
    debugPrint(
        '[MultiTargetRTPC] Registered ${config.name} with ${config.targets.length} targets');
    notifyListeners();
  }

  /// Unregister a multi-target RTPC
  void unregisterMultiTarget(int rtpcId) {
    _multiTargets.remove(rtpcId);
    notifyListeners();
  }

  /// Get multi-target config
  MultiTargetRtpc? getMultiTarget(int rtpcId) => _multiTargets[rtpcId];

  /// Update RTPC value and evaluate all targets
  void updateRtpcValue(int rtpcId, double value) {
    _rtpcValues[rtpcId] = value;

    final config = _multiTargets[rtpcId];
    if (config == null || !config.enabled) return;

    debugPrint(
        '[MultiTargetRTPC] Updated ${config.name} = ${value.toStringAsFixed(3)}');
    notifyListeners();
  }

  /// Add target to existing multi-target RTPC
  void addTarget(int rtpcId, RtpcTargetBinding target) {
    final config = _multiTargets[rtpcId];
    if (config == null) return;

    _multiTargets[rtpcId] = config.copyWith(
      targets: [...config.targets, target],
    );
    notifyListeners();
  }

  /// Remove target from multi-target RTPC
  void removeTarget(int rtpcId, String targetId) {
    final config = _multiTargets[rtpcId];
    if (config == null) return;

    _multiTargets[rtpcId] = config.copyWith(
      targets: config.targets.where((t) => t.id != targetId).toList(),
    );
    notifyListeners();
  }

  /// Update target binding
  void updateTarget(int rtpcId, RtpcTargetBinding target) {
    final config = _multiTargets[rtpcId];
    if (config == null) return;

    _multiTargets[rtpcId] = config.copyWith(
      targets: config.targets.map((t) => t.id == target.id ? target : t).toList(),
    );
    notifyListeners();
  }

  /// Evaluate all targets for a given RTPC value
  /// Returns map of target ID to evaluated value
  Map<String, double> evaluateAllTargets(int rtpcId, double normalizedValue) {
    final result = <String, double>{};
    final config = _multiTargets[rtpcId];
    if (config == null || !config.enabled) return result;

    for (final target in config.targets) {
      if (!target.enabled) continue;
      result[target.id] = evaluateTarget(target, normalizedValue);
    }

    return result;
  }

  /// Evaluate single target binding
  double evaluateTarget(RtpcTargetBinding target, double normalizedValue) {
    double value = normalizedValue;

    // Apply curve if present
    if (target.curve != null) {
      value = target.curve!.evaluate(value);
    }

    // Apply scale and offset
    value = value * target.scale + target.offset;

    // Invert if needed
    if (target.inverted) {
      value = 1.0 - value;
    }

    // Map to output range
    final output = _lerp(target.outputMin, target.outputMax, value.clamp(0.0, 1.0));

    return output.clamp(target.outputMin, target.outputMax);
  }

  /// Get current evaluated value for specific target
  double? getTargetValue(int rtpcId, String targetId) {
    final config = _multiTargets[rtpcId];
    if (config == null) return null;

    final target = config.targets.where((t) => t.id == targetId).firstOrNull;
    if (target == null) return null;

    final rtpcValue = _rtpcValues[rtpcId] ?? 0.0;
    return evaluateTarget(target, rtpcValue);
  }

  /// Get all current target values for an RTPC
  Map<String, double> getAllTargetValues(int rtpcId) {
    final rtpcValue = _rtpcValues[rtpcId] ?? 0.0;
    return evaluateAllTargets(rtpcId, rtpcValue);
  }

  /// Linear interpolation
  double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Export all configurations
  Map<String, dynamic> exportConfig() {
    return {
      'multiTargets':
          _multiTargets.values.map((m) => m.toJson()).toList(),
    };
  }

  /// Import configurations
  void importConfig(Map<String, dynamic> json) {
    _multiTargets.clear();
    final list = json['multiTargets'] as List<dynamic>?;
    if (list != null) {
      for (final item in list) {
        final config = MultiTargetRtpc.fromJson(item as Map<String, dynamic>);
        _multiTargets[config.rtpcId] = config;
      }
    }
    notifyListeners();
  }

  /// Clear all configurations
  void clear() {
    _multiTargets.clear();
    _rtpcValues.clear();
    notifyListeners();
  }
}
