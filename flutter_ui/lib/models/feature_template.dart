/// Feature Template Models
///
/// Pre-built templates for common slot game features with complete
/// stage sequences, audio mappings, and default parameters.
///
/// Part of P1-12: Feature Template Library
library;

import 'dart:convert';
import 'package:flutter/material.dart';

// =============================================================================
// FEATURE TYPE
// =============================================================================

/// Common slot game feature types
enum FeatureType {
  freeSpins,
  bonusGame,
  holdAndWin,
  cascade,
  jackpot,
  multiplier,
  mystery,
  megaways,
  custom;

  String get displayName => switch (this) {
    FeatureType.freeSpins => 'Free Spins',
    FeatureType.bonusGame => 'Bonus Game',
    FeatureType.holdAndWin => 'Hold & Win',
    FeatureType.cascade => 'Cascade',
    FeatureType.jackpot => 'Jackpot',
    FeatureType.multiplier => 'Multiplier',
    FeatureType.mystery => 'Mystery',
    FeatureType.megaways => 'Megaways',
    FeatureType.custom => 'Custom',
  };

  IconData get icon => switch (this) {
    FeatureType.freeSpins => Icons.casino,
    FeatureType.bonusGame => Icons.card_giftcard,
    FeatureType.holdAndWin => Icons.lock,
    FeatureType.cascade => Icons.water_drop,
    FeatureType.jackpot => Icons.diamond,
    FeatureType.multiplier => Icons.clear_all,
    FeatureType.mystery => Icons.help_outline,
    FeatureType.megaways => Icons.grid_on,
    FeatureType.custom => Icons.edit,
  };

  Color get color => switch (this) {
    FeatureType.freeSpins => const Color(0xFF40FF90),    // Green
    FeatureType.bonusGame => const Color(0xFF9370DB),    // Purple
    FeatureType.holdAndWin => const Color(0xFFFF9040),   // Orange
    FeatureType.cascade => const Color(0xFF40C8FF),      // Cyan
    FeatureType.jackpot => const Color(0xFFFFD700),      // Gold
    FeatureType.multiplier => const Color(0xFFFF6B6B),   // Red
    FeatureType.mystery => const Color(0xFF9370DB),      // Purple
    FeatureType.megaways => const Color(0xFF4A9EFF),     // Blue
    FeatureType.custom => const Color(0xFF808080),       // Grey
  };
}

// =============================================================================
// AUDIO SLOT DEFINITION
// =============================================================================

/// Audio slot definition for a stage in the template
class AudioSlotDef {
  final String stage;
  final String label;
  final String? description;
  final bool required;
  final bool looping;
  final String? defaultBus;
  final int priority;
  final Map<String, dynamic>? defaultParams;

  const AudioSlotDef({
    required this.stage,
    required this.label,
    this.description,
    this.required = false,
    this.looping = false,
    this.defaultBus,
    this.priority = 50,
    this.defaultParams,
  });

  Map<String, dynamic> toJson() => {
    'stage': stage,
    'label': label,
    if (description != null) 'description': description,
    'required': required,
    'looping': looping,
    if (defaultBus != null) 'defaultBus': defaultBus,
    'priority': priority,
    if (defaultParams != null) 'defaultParams': defaultParams,
  };

  factory AudioSlotDef.fromJson(Map<String, dynamic> json) => AudioSlotDef(
    stage: json['stage'] as String,
    label: json['label'] as String,
    description: json['description'] as String?,
    required: json['required'] as bool? ?? false,
    looping: json['looping'] as bool? ?? false,
    defaultBus: json['defaultBus'] as String?,
    priority: json['priority'] as int? ?? 50,
    defaultParams: json['defaultParams'] as Map<String, dynamic>?,
  );
}

// =============================================================================
// FEATURE PHASE
// =============================================================================

/// A phase in the feature flow (e.g., Entry, Gameplay, Exit)
class FeaturePhase {
  final String id;
  final String name;
  final String? description;
  final List<AudioSlotDef> audioSlots;
  final int order;
  final bool canSkip;

  const FeaturePhase({
    required this.id,
    required this.name,
    this.description,
    required this.audioSlots,
    required this.order,
    this.canSkip = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'audioSlots': audioSlots.map((s) => s.toJson()).toList(),
    'order': order,
    'canSkip': canSkip,
  };

  factory FeaturePhase.fromJson(Map<String, dynamic> json) => FeaturePhase(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    audioSlots: (json['audioSlots'] as List)
        .map((s) => AudioSlotDef.fromJson(s as Map<String, dynamic>))
        .toList(),
    order: json['order'] as int,
    canSkip: json['canSkip'] as bool? ?? false,
  );
}

// =============================================================================
// PARAMETER DEFINITION
// =============================================================================

/// Parameter type
enum ParameterType { integer, float, boolean, string, list }

/// Parameter definition for template customization
class ParameterDef {
  final String id;
  final String label;
  final ParameterType type;
  final dynamic defaultValue;
  final dynamic? minValue;
  final dynamic? maxValue;
  final List<dynamic>? allowedValues;
  final String? description;
  final bool required;

  const ParameterDef({
    required this.id,
    required this.label,
    required this.type,
    required this.defaultValue,
    this.minValue,
    this.maxValue,
    this.allowedValues,
    this.description,
    this.required = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'type': type.name,
    'defaultValue': defaultValue,
    if (minValue != null) 'minValue': minValue,
    if (maxValue != null) 'maxValue': maxValue,
    if (allowedValues != null) 'allowedValues': allowedValues,
    if (description != null) 'description': description,
    'required': required,
  };

  factory ParameterDef.fromJson(Map<String, dynamic> json) => ParameterDef(
    id: json['id'] as String,
    label: json['label'] as String,
    type: ParameterType.values.firstWhere((t) => t.name == json['type']),
    defaultValue: json['defaultValue'],
    minValue: json['minValue'],
    maxValue: json['maxValue'],
    allowedValues: json['allowedValues'] as List?,
    description: json['description'] as String?,
    required: json['required'] as bool? ?? false,
  );
}

// =============================================================================
// FEATURE TEMPLATE
// =============================================================================

/// Complete feature template with phases, audio slots, and parameters
class FeatureTemplate {
  final String id;
  final String name;
  final FeatureType type;
  final String? description;
  final List<FeaturePhase> phases;
  final List<ParameterDef> parameters;
  final Map<String, dynamic>? metadata;
  final String version;
  final bool isBuiltIn;

  const FeatureTemplate({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    required this.phases,
    this.parameters = const [],
    this.metadata,
    this.version = '1.0',
    this.isBuiltIn = false,
  });

  /// Get all audio slots across all phases
  List<AudioSlotDef> get allAudioSlots {
    return phases.expand((phase) => phase.audioSlots).toList();
  }

  /// Get required audio slots
  List<AudioSlotDef> get requiredSlots {
    return allAudioSlots.where((slot) => slot.required).toList();
  }

  /// Get optional audio slots
  List<AudioSlotDef> get optionalSlots {
    return allAudioSlots.where((slot) => !slot.required).toList();
  }

  /// Get parameter by id
  ParameterDef? getParameter(String id) {
    try {
      return parameters.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get phase by id
  FeaturePhase? getPhase(String id) {
    try {
      return phases.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    if (description != null) 'description': description,
    'phases': phases.map((p) => p.toJson()).toList(),
    'parameters': parameters.map((p) => p.toJson()).toList(),
    if (metadata != null) 'metadata': metadata,
    'version': version,
    'isBuiltIn': isBuiltIn,
  };

  factory FeatureTemplate.fromJson(Map<String, dynamic> json) => FeatureTemplate(
    id: json['id'] as String,
    name: json['name'] as String,
    type: FeatureType.values.firstWhere((t) => t.name == json['type']),
    description: json['description'] as String?,
    phases: (json['phases'] as List)
        .map((p) => FeaturePhase.fromJson(p as Map<String, dynamic>))
        .toList(),
    parameters: (json['parameters'] as List? ?? [])
        .map((p) => ParameterDef.fromJson(p as Map<String, dynamic>))
        .toList(),
    metadata: json['metadata'] as Map<String, dynamic>?,
    version: json['version'] as String? ?? '1.0',
    isBuiltIn: json['isBuiltIn'] as bool? ?? false,
  );

  FeatureTemplate copyWith({
    String? id,
    String? name,
    FeatureType? type,
    String? description,
    List<FeaturePhase>? phases,
    List<ParameterDef>? parameters,
    Map<String, dynamic>? metadata,
    String? version,
    bool? isBuiltIn,
  }) => FeatureTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    description: description ?? this.description,
    phases: phases ?? this.phases,
    parameters: parameters ?? this.parameters,
    metadata: metadata ?? this.metadata,
    version: version ?? this.version,
    isBuiltIn: isBuiltIn ?? this.isBuiltIn,
  );
}

// =============================================================================
// TEMPLATE INSTANCE
// =============================================================================

/// Instantiated template with user-provided values
class FeatureTemplateInstance {
  final String id;
  final String templateId;
  final String name;
  final Map<String, dynamic> parameterValues;
  final Map<String, String> audioAssignments; // stage → audioPath
  final DateTime createdAt;
  final DateTime? modifiedAt;

  const FeatureTemplateInstance({
    required this.id,
    required this.templateId,
    required this.name,
    required this.parameterValues,
    required this.audioAssignments,
    required this.createdAt,
    this.modifiedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'templateId': templateId,
    'name': name,
    'parameterValues': parameterValues,
    'audioAssignments': audioAssignments,
    'createdAt': createdAt.toIso8601String(),
    if (modifiedAt != null) 'modifiedAt': modifiedAt!.toIso8601String(),
  };

  factory FeatureTemplateInstance.fromJson(Map<String, dynamic> json) => FeatureTemplateInstance(
    id: json['id'] as String,
    templateId: json['templateId'] as String,
    name: json['name'] as String,
    parameterValues: json['parameterValues'] as Map<String, dynamic>,
    audioAssignments: Map<String, String>.from(json['audioAssignments'] as Map),
    createdAt: DateTime.parse(json['createdAt'] as String),
    modifiedAt: json['modifiedAt'] != null
        ? DateTime.parse(json['modifiedAt'] as String)
        : null,
  );

  FeatureTemplateInstance copyWith({
    String? id,
    String? templateId,
    String? name,
    Map<String, dynamic>? parameterValues,
    Map<String, String>? audioAssignments,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) => FeatureTemplateInstance(
    id: id ?? this.id,
    templateId: templateId ?? this.templateId,
    name: name ?? this.name,
    parameterValues: parameterValues ?? this.parameterValues,
    audioAssignments: audioAssignments ?? this.audioAssignments,
    createdAt: createdAt ?? this.createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
  );
}
