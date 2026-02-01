// ============================================================================
// FluxForge Studio — Feature Builder Preset Model
// ============================================================================
// P13.0.5: Feature preset model for saving/loading configurations
// Presets store the complete state of all blocks for quick recall.
// ============================================================================

import 'dart:convert';

/// A saved preset containing the configuration of all feature blocks.
///
/// Presets can be:
/// - Built-in: Shipped with FluxForge (e.g., "Classic 5x3", "Megaways")
/// - User: Created by the user
/// - Imported: Loaded from external files
class FeaturePreset {
  /// Unique identifier for this preset.
  final String id;

  /// Human-readable name.
  final String name;

  /// Optional description.
  final String? description;

  /// Category for organizing presets.
  final PresetCategory category;

  /// Schema version for migration support.
  final String schemaVersion;

  /// When this preset was created.
  final DateTime createdAt;

  /// When this preset was last modified.
  final DateTime modifiedAt;

  /// The author of this preset (for shared presets).
  final String? author;

  /// Tags for filtering and search.
  final List<String> tags;

  /// Block configurations: {blockId: {isEnabled, options}}.
  final Map<String, BlockPresetData> blocks;

  /// Optional thumbnail image (base64 encoded).
  final String? thumbnailBase64;

  /// Whether this is a built-in preset (cannot be modified/deleted).
  final bool isBuiltIn;

  /// Whether this preset is marked as favorite.
  final bool isFavorite;

  /// Usage count for sorting by popularity.
  final int usageCount;

  FeaturePreset({
    required this.id,
    required this.name,
    this.description,
    required this.category,
    this.schemaVersion = '1.0.0',
    DateTime? createdAt,
    DateTime? modifiedAt,
    this.author,
    this.tags = const [],
    required this.blocks,
    this.thumbnailBase64,
    this.isBuiltIn = false,
    this.isFavorite = false,
    this.usageCount = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now();

  /// Create a copy with optionally modified properties.
  FeaturePreset copyWith({
    String? id,
    String? name,
    String? description,
    PresetCategory? category,
    String? schemaVersion,
    DateTime? createdAt,
    DateTime? modifiedAt,
    String? author,
    List<String>? tags,
    Map<String, BlockPresetData>? blocks,
    String? thumbnailBase64,
    bool? isBuiltIn,
    bool? isFavorite,
    int? usageCount,
  }) =>
      FeaturePreset(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        category: category ?? this.category,
        schemaVersion: schemaVersion ?? this.schemaVersion,
        createdAt: createdAt ?? this.createdAt,
        modifiedAt: modifiedAt ?? DateTime.now(),
        author: author ?? this.author,
        tags: tags ?? this.tags,
        blocks: blocks ?? this.blocks,
        thumbnailBase64: thumbnailBase64 ?? this.thumbnailBase64,
        isBuiltIn: isBuiltIn ?? this.isBuiltIn,
        isFavorite: isFavorite ?? this.isFavorite,
        usageCount: usageCount ?? this.usageCount,
      );

  /// Increment usage count and update modification time.
  FeaturePreset recordUsage() => copyWith(
        usageCount: usageCount + 1,
        modifiedAt: DateTime.now(),
      );

  /// Toggle favorite status.
  FeaturePreset toggleFavorite() => copyWith(isFavorite: !isFavorite);

  /// Get enabled block IDs.
  List<String> get enabledBlockIds =>
      blocks.entries.where((e) => e.value.isEnabled).map((e) => e.key).toList();

  /// Get the number of enabled blocks.
  int get enabledBlockCount => enabledBlockIds.length;

  /// Check if a specific block is enabled.
  bool isBlockEnabled(String blockId) => blocks[blockId]?.isEnabled ?? false;

  /// Get block options for a specific block.
  Map<String, dynamic>? getBlockOptions(String blockId) =>
      blocks[blockId]?.options;

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        'category': category.name,
        'schemaVersion': schemaVersion,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        if (author != null) 'author': author,
        'tags': tags,
        'blocks': blocks.map((k, v) => MapEntry(k, v.toJson())),
        if (thumbnailBase64 != null) 'thumbnailBase64': thumbnailBase64,
        'isBuiltIn': isBuiltIn,
        'isFavorite': isFavorite,
        'usageCount': usageCount,
      };

  /// Serialize to JSON string (for file export).
  String toJsonString({bool pretty = false}) {
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    return encoder.convert(toJson());
  }

  /// Deserialize from JSON.
  factory FeaturePreset.fromJson(Map<String, dynamic> json) => FeaturePreset(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        category: PresetCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => PresetCategory.custom,
        ),
        schemaVersion: json['schemaVersion'] as String? ?? '1.0.0',
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : null,
        modifiedAt: json['modifiedAt'] != null
            ? DateTime.parse(json['modifiedAt'] as String)
            : null,
        author: json['author'] as String?,
        tags: (json['tags'] as List?)?.cast<String>() ?? [],
        blocks: (json['blocks'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, BlockPresetData.fromJson(v as Map<String, dynamic>)),
        ),
        thumbnailBase64: json['thumbnailBase64'] as String?,
        isBuiltIn: json['isBuiltIn'] as bool? ?? false,
        isFavorite: json['isFavorite'] as bool? ?? false,
        usageCount: json['usageCount'] as int? ?? 0,
      );

  /// Deserialize from JSON string (for file import).
  factory FeaturePreset.fromJsonString(String jsonString) =>
      FeaturePreset.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

  @override
  String toString() => 'FeaturePreset($name, ${enabledBlockCount} blocks)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FeaturePreset && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Data for a single block within a preset.
class BlockPresetData {
  /// Whether the block is enabled.
  final bool isEnabled;

  /// Option values: {optionId: value}.
  final Map<String, dynamic> options;

  const BlockPresetData({
    required this.isEnabled,
    this.options = const {},
  });

  Map<String, dynamic> toJson() => {
        'isEnabled': isEnabled,
        'options': options,
      };

  factory BlockPresetData.fromJson(Map<String, dynamic> json) => BlockPresetData(
        isEnabled: json['isEnabled'] as bool? ?? false,
        options: Map<String, dynamic>.from(json['options'] as Map? ?? {}),
      );

  BlockPresetData copyWith({
    bool? isEnabled,
    Map<String, dynamic>? options,
  }) =>
      BlockPresetData(
        isEnabled: isEnabled ?? this.isEnabled,
        options: options ?? this.options,
      );
}

/// Categories for organizing presets.
enum PresetCategory {
  /// Classic slot configurations (3x3, 5x3 with lines).
  classic,

  /// Modern video slot configurations.
  video,

  /// Megaways-style configurations.
  megaways,

  /// Cluster pays configurations.
  cluster,

  /// Hold & Win / Lightning Link style.
  holdWin,

  /// Jackpot-focused configurations.
  jackpot,

  /// User-created custom presets.
  custom,

  /// Test/debug configurations.
  test,
}

/// Extension for [PresetCategory] display properties.
extension PresetCategoryExtension on PresetCategory {
  /// Human-readable display name.
  String get displayName {
    switch (this) {
      case PresetCategory.classic:
        return 'Classic';
      case PresetCategory.video:
        return 'Video Slots';
      case PresetCategory.megaways:
        return 'Megaways';
      case PresetCategory.cluster:
        return 'Cluster Pays';
      case PresetCategory.holdWin:
        return 'Hold & Win';
      case PresetCategory.jackpot:
        return 'Jackpot';
      case PresetCategory.custom:
        return 'Custom';
      case PresetCategory.test:
        return 'Test';
    }
  }

  /// Icon name for the category.
  String get iconName {
    switch (this) {
      case PresetCategory.classic:
        return 'casino';
      case PresetCategory.video:
        return 'videogame_asset';
      case PresetCategory.megaways:
        return 'grid_view';
      case PresetCategory.cluster:
        return 'bubble_chart';
      case PresetCategory.holdWin:
        return 'lock';
      case PresetCategory.jackpot:
        return 'emoji_events';
      case PresetCategory.custom:
        return 'person';
      case PresetCategory.test:
        return 'science';
    }
  }

  /// Whether presets in this category are built-in.
  bool get isBuiltInCategory {
    switch (this) {
      case PresetCategory.custom:
      case PresetCategory.test:
        return false;
      default:
        return true;
    }
  }
}

// ============================================================================
// Preset Metadata (for listing without loading full preset)
// ============================================================================

/// Lightweight metadata for a preset (for listing/filtering).
class PresetMetadata {
  final String id;
  final String name;
  final PresetCategory category;
  final int enabledBlockCount;
  final bool isBuiltIn;
  final bool isFavorite;
  final int usageCount;
  final DateTime modifiedAt;
  final List<String> tags;

  const PresetMetadata({
    required this.id,
    required this.name,
    required this.category,
    required this.enabledBlockCount,
    required this.isBuiltIn,
    required this.isFavorite,
    required this.usageCount,
    required this.modifiedAt,
    required this.tags,
  });

  factory PresetMetadata.fromPreset(FeaturePreset preset) => PresetMetadata(
        id: preset.id,
        name: preset.name,
        category: preset.category,
        enabledBlockCount: preset.enabledBlockCount,
        isBuiltIn: preset.isBuiltIn,
        isFavorite: preset.isFavorite,
        usageCount: preset.usageCount,
        modifiedAt: preset.modifiedAt,
        tags: preset.tags,
      );
}

// ============================================================================
// Preset Comparison
// ============================================================================

/// Result of comparing two presets.
class PresetDiff {
  /// Blocks that are enabled in A but not in B.
  final List<String> addedBlocks;

  /// Blocks that are enabled in B but not in A.
  final List<String> removedBlocks;

  /// Blocks that have different option values.
  final Map<String, OptionDiff> changedOptions;

  const PresetDiff({
    this.addedBlocks = const [],
    this.removedBlocks = const [],
    this.changedOptions = const {},
  });

  /// Whether the presets are identical.
  bool get isEmpty =>
      addedBlocks.isEmpty && removedBlocks.isEmpty && changedOptions.isEmpty;

  /// Compare two presets.
  factory PresetDiff.compare(FeaturePreset a, FeaturePreset b) {
    final addedBlocks = <String>[];
    final removedBlocks = <String>[];
    final changedOptions = <String, OptionDiff>{};

    // Find added/removed blocks
    final aEnabled = a.enabledBlockIds.toSet();
    final bEnabled = b.enabledBlockIds.toSet();
    addedBlocks.addAll(aEnabled.difference(bEnabled));
    removedBlocks.addAll(bEnabled.difference(aEnabled));

    // Find changed options in common blocks
    for (final blockId in aEnabled.intersection(bEnabled)) {
      final aOptions = a.getBlockOptions(blockId) ?? {};
      final bOptions = b.getBlockOptions(blockId) ?? {};

      final diffs = <String, List<dynamic>>{}; // optionId: [oldValue, newValue]

      final allKeys = {...aOptions.keys, ...bOptions.keys};
      for (final key in allKeys) {
        final aVal = aOptions[key];
        final bVal = bOptions[key];
        if (aVal != bVal) {
          diffs[key] = [aVal, bVal];
        }
      }

      if (diffs.isNotEmpty) {
        changedOptions[blockId] = OptionDiff(diffs);
      }
    }

    return PresetDiff(
      addedBlocks: addedBlocks,
      removedBlocks: removedBlocks,
      changedOptions: changedOptions,
    );
  }
}

/// Differences in options for a single block.
class OptionDiff {
  /// Map of optionId to [oldValue, newValue].
  final Map<String, List<dynamic>> changes;

  const OptionDiff(this.changes);

  int get changeCount => changes.length;
}
