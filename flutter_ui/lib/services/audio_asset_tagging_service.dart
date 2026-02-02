/// Audio Asset Tagging Service
///
/// P12.1.9: Tag system for audio assets in SlotLab:
/// - Predefined tags (win, loss, feature, sfx, music, etc.)
/// - Custom user tags
/// - Filter assets by tags
/// - Bulk tagging operations
/// - Tag persistence
///
/// Usage:
/// ```dart
/// final service = AudioAssetTaggingService.instance;
///
/// // Add tags to asset
/// service.addTag('asset_123', AudioTag.win);
/// service.addCustomTag('asset_123', 'intro');
///
/// // Filter by tag
/// final winAssets = service.getAssetsByTag(AudioTag.win);
///
/// // Bulk operations
/// service.bulkAddTag(['asset_1', 'asset_2'], AudioTag.sfx);
/// ```

import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Predefined audio tags
enum AudioTag {
  // Game flow
  win,
  loss,
  feature,
  bigWin,
  jackpot,

  // Audio types
  sfx,
  music,
  voice,
  ambience,
  stinger,

  // Slot-specific
  spin,
  reel,
  symbol,
  cascade,
  anticipation,

  // UI/System
  ui,
  notification,
  error,

  // Quality markers
  placeholder,
  final_,  // 'final' is reserved
  wip,
}

extension AudioTagExtension on AudioTag {
  /// Display name for UI
  String get displayName {
    switch (this) {
      case AudioTag.win: return 'Win';
      case AudioTag.loss: return 'Loss';
      case AudioTag.feature: return 'Feature';
      case AudioTag.bigWin: return 'Big Win';
      case AudioTag.jackpot: return 'Jackpot';
      case AudioTag.sfx: return 'SFX';
      case AudioTag.music: return 'Music';
      case AudioTag.voice: return 'Voice';
      case AudioTag.ambience: return 'Ambience';
      case AudioTag.stinger: return 'Stinger';
      case AudioTag.spin: return 'Spin';
      case AudioTag.reel: return 'Reel';
      case AudioTag.symbol: return 'Symbol';
      case AudioTag.cascade: return 'Cascade';
      case AudioTag.anticipation: return 'Anticipation';
      case AudioTag.ui: return 'UI';
      case AudioTag.notification: return 'Notification';
      case AudioTag.error: return 'Error';
      case AudioTag.placeholder: return 'Placeholder';
      case AudioTag.final_: return 'Final';
      case AudioTag.wip: return 'WIP';
    }
  }

  /// Tag color for UI
  int get colorValue {
    switch (this) {
      case AudioTag.win: return 0xFF40FF90;       // Green
      case AudioTag.loss: return 0xFFFF4060;      // Red
      case AudioTag.feature: return 0xFFFFD700;   // Gold
      case AudioTag.bigWin: return 0xFFFF9040;    // Orange
      case AudioTag.jackpot: return 0xFF9C27B0;   // Purple
      case AudioTag.sfx: return 0xFF4A9EFF;       // Blue
      case AudioTag.music: return 0xFF40C8FF;     // Cyan
      case AudioTag.voice: return 0xFFE91E63;     // Pink
      case AudioTag.ambience: return 0xFF607D8B;  // BlueGrey
      case AudioTag.stinger: return 0xFFFFC107;   // Amber
      case AudioTag.spin: return 0xFF2196F3;      // Blue
      case AudioTag.reel: return 0xFF3F51B5;      // Indigo
      case AudioTag.symbol: return 0xFF00BCD4;    // Cyan
      case AudioTag.cascade: return 0xFFFF5722;   // DeepOrange
      case AudioTag.anticipation: return 0xFFFFEB3B; // Yellow
      case AudioTag.ui: return 0xFF9E9E9E;        // Grey
      case AudioTag.notification: return 0xFF03A9F4; // LightBlue
      case AudioTag.error: return 0xFFF44336;     // Red
      case AudioTag.placeholder: return 0xFF795548; // Brown
      case AudioTag.final_: return 0xFF4CAF50;    // Green
      case AudioTag.wip: return 0xFFFF9800;       // Orange
    }
  }

  /// Tag category
  String get category {
    switch (this) {
      case AudioTag.win:
      case AudioTag.loss:
      case AudioTag.feature:
      case AudioTag.bigWin:
      case AudioTag.jackpot:
        return 'Game Flow';
      case AudioTag.sfx:
      case AudioTag.music:
      case AudioTag.voice:
      case AudioTag.ambience:
      case AudioTag.stinger:
        return 'Audio Type';
      case AudioTag.spin:
      case AudioTag.reel:
      case AudioTag.symbol:
      case AudioTag.cascade:
      case AudioTag.anticipation:
        return 'Slot Events';
      case AudioTag.ui:
      case AudioTag.notification:
      case AudioTag.error:
        return 'UI/System';
      case AudioTag.placeholder:
      case AudioTag.final_:
      case AudioTag.wip:
        return 'Quality';
    }
  }
}

/// Single tag entry for an asset
class AssetTagEntry {
  /// Asset ID (path or unique identifier)
  final String assetId;

  /// Predefined tags
  final Set<AudioTag> tags;

  /// Custom user-defined tags
  final Set<String> customTags;

  /// Notes/comments for this asset
  final String? notes;

  const AssetTagEntry({
    required this.assetId,
    this.tags = const {},
    this.customTags = const {},
    this.notes,
  });

  AssetTagEntry copyWith({
    String? assetId,
    Set<AudioTag>? tags,
    Set<String>? customTags,
    String? notes,
  }) {
    return AssetTagEntry(
      assetId: assetId ?? this.assetId,
      tags: tags ?? this.tags,
      customTags: customTags ?? this.customTags,
      notes: notes ?? this.notes,
    );
  }

  /// Check if asset has any tags
  bool get hasTags => tags.isNotEmpty || customTags.isNotEmpty;

  /// Get all tags as strings
  List<String> get allTagNames => [
        ...tags.map((t) => t.displayName),
        ...customTags,
      ];

  factory AssetTagEntry.fromJson(Map<String, dynamic> json) {
    return AssetTagEntry(
      assetId: json['assetId'] as String,
      tags: (json['tags'] as List?)
              ?.map((t) => AudioTag.values.firstWhere(
                    (e) => e.name == t,
                    orElse: () => AudioTag.sfx,
                  ))
              .toSet() ??
          {},
      customTags:
          (json['customTags'] as List?)?.map((t) => t as String).toSet() ?? {},
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'assetId': assetId,
      'tags': tags.map((t) => t.name).toList(),
      'customTags': customTags.toList(),
      if (notes != null) 'notes': notes,
    };
  }

  @override
  String toString() => 'AssetTagEntry($assetId, tags: $tags, custom: $customTags)';
}

/// Audio Asset Tagging Service — Singleton
class AudioAssetTaggingService extends ChangeNotifier {
  // ─── Singleton ───────────────────────────────────────────────────────────────
  static AudioAssetTaggingService? _instance;
  static AudioAssetTaggingService get instance =>
      _instance ??= AudioAssetTaggingService._();

  AudioAssetTaggingService._();

  // ─── State ───────────────────────────────────────────────────────────────────
  final Map<String, AssetTagEntry> _entries = {};

  /// Get all tagged assets
  Map<String, AssetTagEntry> get entries => Map.unmodifiable(_entries);

  /// Get entry for specific asset (null if not tagged)
  AssetTagEntry? getEntry(String assetId) => _entries[assetId];

  // ═══════════════════════════════════════════════════════════════════════════
  // SINGLE ASSET OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a predefined tag to an asset
  void addTag(String assetId, AudioTag tag) {
    final existing = _entries[assetId] ??
        AssetTagEntry(assetId: assetId, tags: {}, customTags: {});
    final newTags = Set<AudioTag>.from(existing.tags)..add(tag);
    _entries[assetId] = existing.copyWith(tags: newTags);
    notifyListeners();
    debugPrint('[AudioTagging] Added tag ${tag.displayName} to $assetId');
  }

  /// Remove a predefined tag from an asset
  void removeTag(String assetId, AudioTag tag) {
    final existing = _entries[assetId];
    if (existing == null) return;

    final newTags = Set<AudioTag>.from(existing.tags)..remove(tag);
    _entries[assetId] = existing.copyWith(tags: newTags);
    _cleanupEmptyEntry(assetId);
    notifyListeners();
    debugPrint('[AudioTagging] Removed tag ${tag.displayName} from $assetId');
  }

  /// Add a custom tag to an asset
  void addCustomTag(String assetId, String tag) {
    final normalizedTag = tag.trim().toLowerCase();
    if (normalizedTag.isEmpty) return;

    final existing = _entries[assetId] ??
        AssetTagEntry(assetId: assetId, tags: {}, customTags: {});
    final newTags = Set<String>.from(existing.customTags)..add(normalizedTag);
    _entries[assetId] = existing.copyWith(customTags: newTags);
    notifyListeners();
    debugPrint('[AudioTagging] Added custom tag "$normalizedTag" to $assetId');
  }

  /// Remove a custom tag from an asset
  void removeCustomTag(String assetId, String tag) {
    final existing = _entries[assetId];
    if (existing == null) return;

    final normalizedTag = tag.trim().toLowerCase();
    final newTags = Set<String>.from(existing.customTags)..remove(normalizedTag);
    _entries[assetId] = existing.copyWith(customTags: newTags);
    _cleanupEmptyEntry(assetId);
    notifyListeners();
    debugPrint('[AudioTagging] Removed custom tag "$normalizedTag" from $assetId');
  }

  /// Set notes for an asset
  void setNotes(String assetId, String? notes) {
    final existing = _entries[assetId] ??
        AssetTagEntry(assetId: assetId, tags: {}, customTags: {});
    _entries[assetId] = existing.copyWith(notes: notes);
    _cleanupEmptyEntry(assetId);
    notifyListeners();
  }

  /// Clear all tags from an asset
  void clearTags(String assetId) {
    _entries.remove(assetId);
    notifyListeners();
    debugPrint('[AudioTagging] Cleared all tags from $assetId');
  }

  /// Check if asset has a specific tag
  bool hasTag(String assetId, AudioTag tag) {
    return _entries[assetId]?.tags.contains(tag) ?? false;
  }

  /// Check if asset has a specific custom tag
  bool hasCustomTag(String assetId, String tag) {
    return _entries[assetId]?.customTags.contains(tag.toLowerCase()) ?? false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BULK OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a tag to multiple assets
  void bulkAddTag(List<String> assetIds, AudioTag tag) {
    for (final id in assetIds) {
      final existing = _entries[id] ??
          AssetTagEntry(assetId: id, tags: {}, customTags: {});
      final newTags = Set<AudioTag>.from(existing.tags)..add(tag);
      _entries[id] = existing.copyWith(tags: newTags);
    }
    notifyListeners();
    debugPrint('[AudioTagging] Bulk added tag ${tag.displayName} to ${assetIds.length} assets');
  }

  /// Remove a tag from multiple assets
  void bulkRemoveTag(List<String> assetIds, AudioTag tag) {
    for (final id in assetIds) {
      final existing = _entries[id];
      if (existing == null) continue;

      final newTags = Set<AudioTag>.from(existing.tags)..remove(tag);
      _entries[id] = existing.copyWith(tags: newTags);
      _cleanupEmptyEntry(id);
    }
    notifyListeners();
    debugPrint('[AudioTagging] Bulk removed tag ${tag.displayName} from ${assetIds.length} assets');
  }

  /// Add a custom tag to multiple assets
  void bulkAddCustomTag(List<String> assetIds, String tag) {
    final normalizedTag = tag.trim().toLowerCase();
    if (normalizedTag.isEmpty) return;

    for (final id in assetIds) {
      final existing = _entries[id] ??
          AssetTagEntry(assetId: id, tags: {}, customTags: {});
      final newTags = Set<String>.from(existing.customTags)..add(normalizedTag);
      _entries[id] = existing.copyWith(customTags: newTags);
    }
    notifyListeners();
    debugPrint('[AudioTagging] Bulk added custom tag "$normalizedTag" to ${assetIds.length} assets');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FILTER/SEARCH
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all asset IDs with a specific tag
  List<String> getAssetsByTag(AudioTag tag) {
    return _entries.entries
        .where((e) => e.value.tags.contains(tag))
        .map((e) => e.key)
        .toList();
  }

  /// Get all asset IDs with a specific custom tag
  List<String> getAssetsByCustomTag(String tag) {
    final normalizedTag = tag.trim().toLowerCase();
    return _entries.entries
        .where((e) => e.value.customTags.contains(normalizedTag))
        .map((e) => e.key)
        .toList();
  }

  /// Get all asset IDs matching ANY of the given tags
  List<String> getAssetsByAnyTag(Set<AudioTag> tags) {
    return _entries.entries
        .where((e) => e.value.tags.intersection(tags).isNotEmpty)
        .map((e) => e.key)
        .toList();
  }

  /// Get all asset IDs matching ALL of the given tags
  List<String> getAssetsByAllTags(Set<AudioTag> tags) {
    return _entries.entries
        .where((e) => e.value.tags.containsAll(tags))
        .map((e) => e.key)
        .toList();
  }

  /// Get all unique custom tags in use
  Set<String> getAllCustomTags() {
    final tags = <String>{};
    for (final entry in _entries.values) {
      tags.addAll(entry.customTags);
    }
    return tags;
  }

  /// Get tag statistics
  Map<AudioTag, int> getTagStatistics() {
    final stats = <AudioTag, int>{};
    for (final entry in _entries.values) {
      for (final tag in entry.tags) {
        stats[tag] = (stats[tag] ?? 0) + 1;
      }
    }
    return stats;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PERSISTENCE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export all tags as JSON string
  String exportToJson() {
    final data = _entries.values.map((e) => e.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert({'tags': data});
  }

  /// Import tags from JSON string
  void importFromJson(String jsonString) {
    try {
      final data = json.decode(jsonString) as Map<String, dynamic>;
      final tags = (data['tags'] as List)
          .map((e) => AssetTagEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      _entries.clear();
      for (final entry in tags) {
        _entries[entry.assetId] = entry;
      }
      notifyListeners();
      debugPrint('[AudioTagging] Imported ${tags.length} tag entries');
    } catch (e) {
      debugPrint('[AudioTagging] Import error: $e');
    }
  }

  /// Clear all tags
  void clearAll() {
    _entries.clear();
    notifyListeners();
    debugPrint('[AudioTagging] Cleared all tags');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Remove entry if it has no tags
  void _cleanupEmptyEntry(String assetId) {
    final entry = _entries[assetId];
    if (entry == null) return;
    if (!entry.hasTags && entry.notes == null) {
      _entries.remove(assetId);
    }
  }
}
