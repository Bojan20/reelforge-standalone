/// Track Template Model (P10.1.10)
///
/// Complete track configuration including:
/// - Channel strip settings (volume, pan, mute, solo)
/// - Insert chain (DSP processors)
/// - Send routing (aux buses)
/// - Output routing (bus assignment)
/// - Visual settings (color, name)
///
/// Enables saving/loading complete track configurations like Logic Pro.
library;

import 'dart:ui' show Color;
import '../providers/dsp_chain_provider.dart';

/// Schema version for forward compatibility
const int kTrackTemplateSchemaVersion = 1;

/// File extension for track templates
const String kTrackTemplateExtension = '.ffxtemplate';

// ═══════════════════════════════════════════════════════════════════════════
// SEND CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// Aux send configuration for track template
class TemplateSendConfig {
  final String auxBusId;
  final double level; // 0.0 - 1.0
  final bool preFader;
  final bool enabled;

  const TemplateSendConfig({
    required this.auxBusId,
    this.level = 0.0,
    this.preFader = false,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'auxBusId': auxBusId,
        'level': level,
        'preFader': preFader,
        'enabled': enabled,
      };

  factory TemplateSendConfig.fromJson(Map<String, dynamic> json) {
    return TemplateSendConfig(
      auxBusId: json['auxBusId'] as String? ?? '',
      level: (json['level'] as num?)?.toDouble() ?? 0.0,
      preFader: json['preFader'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INSERT CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// DSP insert configuration for track template
class TemplateInsertConfig {
  final DspNodeType type;
  final bool bypass;
  final double wetDry;
  final Map<String, dynamic> params;

  const TemplateInsertConfig({
    required this.type,
    this.bypass = false,
    this.wetDry = 1.0,
    this.params = const {},
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'bypass': bypass,
        'wetDry': wetDry,
        'params': params,
      };

  factory TemplateInsertConfig.fromJson(Map<String, dynamic> json) {
    return TemplateInsertConfig(
      type: DspNodeType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => DspNodeType.eq,
      ),
      bypass: json['bypass'] as bool? ?? false,
      wetDry: (json['wetDry'] as num?)?.toDouble() ?? 1.0,
      params: json['params'] as Map<String, dynamic>? ?? {},
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL STRIP CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// Channel strip settings for track template
class TemplateChannelStrip {
  final double volume; // 0.0 - 1.5 (1.0 = 0dB)
  final double pan; // -1.0 to 1.0
  final double panRight; // For stereo dual-pan
  final bool isStereo;
  final double inputGain; // dB (-20 to +20)
  final bool phaseInverted;

  const TemplateChannelStrip({
    this.volume = 1.0,
    this.pan = 0.0,
    this.panRight = 0.0,
    this.isStereo = true,
    this.inputGain = 0.0,
    this.phaseInverted = false,
  });

  Map<String, dynamic> toJson() => {
        'volume': volume,
        'pan': pan,
        'panRight': panRight,
        'isStereo': isStereo,
        'inputGain': inputGain,
        'phaseInverted': phaseInverted,
      };

  factory TemplateChannelStrip.fromJson(Map<String, dynamic> json) {
    return TemplateChannelStrip(
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
      panRight: (json['panRight'] as num?)?.toDouble() ?? 0.0,
      isStereo: json['isStereo'] as bool? ?? true,
      inputGain: (json['inputGain'] as num?)?.toDouble() ?? 0.0,
      phaseInverted: json['phaseInverted'] as bool? ?? false,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK TEMPLATE
// ═══════════════════════════════════════════════════════════════════════════

/// Track template category
enum TrackTemplateCategory {
  vocal('Vocal', 'Voice and vocal processing'),
  drum('Drum', 'Drum and percussion'),
  bass('Bass', 'Bass instruments'),
  guitar('Guitar', 'Guitar processing'),
  fx('FX', 'Sound effects and creative'),
  music('Music', 'General music tracks'),
  synth('Synth', 'Synthesizer tracks'),
  custom('Custom', 'User-defined templates');

  final String label;
  final String description;
  const TrackTemplateCategory(this.label, this.description);
}

/// Complete track template
class TrackTemplate {
  final int schemaVersion;
  final String id;
  final String name;
  final String? description;
  final TrackTemplateCategory category;
  final DateTime createdAt;
  final DateTime? modifiedAt;

  // Channel strip
  final TemplateChannelStrip channelStrip;

  // Insert chain (ordered list of processors)
  final List<TemplateInsertConfig> inserts;

  // Send routing
  final List<TemplateSendConfig> sends;

  // Output routing
  final String outputBusId; // 'master', 'bus_sfx', etc.

  // Visual
  final int colorValue; // Color as int

  const TrackTemplate({
    this.schemaVersion = kTrackTemplateSchemaVersion,
    required this.id,
    required this.name,
    this.description,
    this.category = TrackTemplateCategory.custom,
    required this.createdAt,
    this.modifiedAt,
    this.channelStrip = const TemplateChannelStrip(),
    this.inserts = const [],
    this.sends = const [],
    this.outputBusId = 'master',
    this.colorValue = 0xFF4A9EFF,
  });

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'description': description,
        'category': category.name,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt?.toIso8601String(),
        'channelStrip': channelStrip.toJson(),
        'inserts': inserts.map((i) => i.toJson()).toList(),
        'sends': sends.map((s) => s.toJson()).toList(),
        'outputBusId': outputBusId,
        'colorValue': colorValue,
      };

  factory TrackTemplate.fromJson(Map<String, dynamic> json) {
    return TrackTemplate(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled',
      description: json['description'] as String?,
      category: TrackTemplateCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => TrackTemplateCategory.custom,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.tryParse(json['modifiedAt'] as String)
          : null,
      channelStrip: json['channelStrip'] != null
          ? TemplateChannelStrip.fromJson(json['channelStrip'] as Map<String, dynamic>)
          : const TemplateChannelStrip(),
      inserts: (json['inserts'] as List<dynamic>?)
              ?.map((i) => TemplateInsertConfig.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      sends: (json['sends'] as List<dynamic>?)
              ?.map((s) => TemplateSendConfig.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      outputBusId: json['outputBusId'] as String? ?? 'master',
      colorValue: json['colorValue'] as int? ?? 0xFF4A9EFF,
    );
  }

  TrackTemplate copyWith({
    int? schemaVersion,
    String? id,
    String? name,
    String? description,
    TrackTemplateCategory? category,
    DateTime? createdAt,
    DateTime? modifiedAt,
    TemplateChannelStrip? channelStrip,
    List<TemplateInsertConfig>? inserts,
    List<TemplateSendConfig>? sends,
    String? outputBusId,
    int? colorValue,
  }) {
    return TrackTemplate(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      channelStrip: channelStrip ?? this.channelStrip,
      inserts: inserts ?? this.inserts,
      sends: sends ?? this.sends,
      outputBusId: outputBusId ?? this.outputBusId,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  /// Generate unique ID
  static String generateId() => 'tmpl_${DateTime.now().millisecondsSinceEpoch}';
}
