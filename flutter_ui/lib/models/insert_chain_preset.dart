/// Insert Chain Preset Model (P10.1.13)
///
/// DSP insert chain presets (like Logic's Channel Strip presets):
/// - Ordered list of processors with parameters
/// - Category organization (vocal, master, mix, creative)
/// - Chain-level bypass and gain
///
/// Enables saving/loading complete DSP chains.
library;

import '../providers/dsp_chain_provider.dart';

/// Schema version for forward compatibility
const int kInsertChainPresetSchemaVersion = 1;

/// File extension for insert chain presets
const String kInsertChainPresetExtension = '.ffxchain';

// ═══════════════════════════════════════════════════════════════════════════
// INSERT CHAIN PRESET CATEGORY
// ═══════════════════════════════════════════════════════════════════════════

/// Category for insert chain presets
enum InsertChainCategory {
  vocal('Vocal', 'Voice processing chains'),
  master('Master', 'Mastering chains'),
  mix('Mix', 'Mixing and bus chains'),
  creative('Creative', 'Sound design and FX'),
  instrument('Instrument', 'Instrument processing'),
  utility('Utility', 'Utility chains'),
  custom('Custom', 'User-defined chains');

  final String label;
  final String description;
  const InsertChainCategory(this.label, this.description);
}

// ═══════════════════════════════════════════════════════════════════════════
// PROCESSOR CONFIG
// ═══════════════════════════════════════════════════════════════════════════

/// Single processor configuration in the chain
class ChainProcessorConfig {
  final DspNodeType type;
  final String? customName;
  final bool bypass;
  final double wetDry; // 0.0 - 1.0
  final double inputGain; // dB
  final double outputGain; // dB
  final Map<String, dynamic> params;

  const ChainProcessorConfig({
    required this.type,
    this.customName,
    this.bypass = false,
    this.wetDry = 1.0,
    this.inputGain = 0.0,
    this.outputGain = 0.0,
    this.params = const {},
  });

  String get displayName => customName ?? type.fullName;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'customName': customName,
        'bypass': bypass,
        'wetDry': wetDry,
        'inputGain': inputGain,
        'outputGain': outputGain,
        'params': params,
      };

  factory ChainProcessorConfig.fromJson(Map<String, dynamic> json) {
    return ChainProcessorConfig(
      type: DspNodeType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => DspNodeType.eq,
      ),
      customName: json['customName'] as String?,
      bypass: json['bypass'] as bool? ?? false,
      wetDry: (json['wetDry'] as num?)?.toDouble() ?? 1.0,
      inputGain: (json['inputGain'] as num?)?.toDouble() ?? 0.0,
      outputGain: (json['outputGain'] as num?)?.toDouble() ?? 0.0,
      params: json['params'] as Map<String, dynamic>? ?? {},
    );
  }

  ChainProcessorConfig copyWith({
    DspNodeType? type,
    String? customName,
    bool? bypass,
    double? wetDry,
    double? inputGain,
    double? outputGain,
    Map<String, dynamic>? params,
  }) {
    return ChainProcessorConfig(
      type: type ?? this.type,
      customName: customName ?? this.customName,
      bypass: bypass ?? this.bypass,
      wetDry: wetDry ?? this.wetDry,
      inputGain: inputGain ?? this.inputGain,
      outputGain: outputGain ?? this.outputGain,
      params: params ?? this.params,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INSERT CHAIN PRESET
// ═══════════════════════════════════════════════════════════════════════════

/// Complete insert chain preset
class InsertChainPreset {
  final int schemaVersion;
  final String id;
  final String name;
  final String? description;
  final InsertChainCategory category;
  final DateTime createdAt;
  final DateTime? modifiedAt;

  // Chain configuration
  final List<ChainProcessorConfig> processors;
  final bool chainBypass;
  final double chainInputGain; // dB
  final double chainOutputGain; // dB

  const InsertChainPreset({
    this.schemaVersion = kInsertChainPresetSchemaVersion,
    required this.id,
    required this.name,
    this.description,
    this.category = InsertChainCategory.custom,
    required this.createdAt,
    this.modifiedAt,
    this.processors = const [],
    this.chainBypass = false,
    this.chainInputGain = 0.0,
    this.chainOutputGain = 0.0,
  });

  /// Number of processors in chain
  int get processorCount => processors.length;

  /// Check if chain is empty
  bool get isEmpty => processors.isEmpty;

  /// Get processors by type
  List<ChainProcessorConfig> getProcessorsByType(DspNodeType type) {
    return processors.where((p) => p.type == type).toList();
  }

  /// Check if chain contains processor type
  bool hasProcessorType(DspNodeType type) {
    return processors.any((p) => p.type == type);
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'description': description,
        'category': category.name,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt?.toIso8601String(),
        'processors': processors.map((p) => p.toJson()).toList(),
        'chainBypass': chainBypass,
        'chainInputGain': chainInputGain,
        'chainOutputGain': chainOutputGain,
      };

  factory InsertChainPreset.fromJson(Map<String, dynamic> json) {
    return InsertChainPreset(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled',
      description: json['description'] as String?,
      category: InsertChainCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => InsertChainCategory.custom,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.tryParse(json['modifiedAt'] as String)
          : null,
      processors: (json['processors'] as List<dynamic>?)
              ?.map((p) => ChainProcessorConfig.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      chainBypass: json['chainBypass'] as bool? ?? false,
      chainInputGain: (json['chainInputGain'] as num?)?.toDouble() ?? 0.0,
      chainOutputGain: (json['chainOutputGain'] as num?)?.toDouble() ?? 0.0,
    );
  }

  InsertChainPreset copyWith({
    int? schemaVersion,
    String? id,
    String? name,
    String? description,
    InsertChainCategory? category,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<ChainProcessorConfig>? processors,
    bool? chainBypass,
    double? chainInputGain,
    double? chainOutputGain,
  }) {
    return InsertChainPreset(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      processors: processors ?? this.processors,
      chainBypass: chainBypass ?? this.chainBypass,
      chainInputGain: chainInputGain ?? this.chainInputGain,
      chainOutputGain: chainOutputGain ?? this.chainOutputGain,
    );
  }

  /// Generate unique ID
  static String generateId() => 'chain_${DateTime.now().millisecondsSinceEpoch}';
}
