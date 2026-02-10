/// Recent & Favorites Service — Quick Access Panel
///
/// P2.4: Provides quick access to recently used and favorited items.
///
/// Features:
/// - Recent files, presets, events, projects
/// - User-defined favorites
/// - Persistent storage
/// - Usage analytics
///
/// Usage:
/// ```dart
/// final service = RecentFavoritesService.instance;
///
/// // Add to recent
/// service.addRecent(RecentItem.file(path: '/path/to/file.wav'));
///
/// // Toggle favorite
/// service.toggleFavorite('file:/path/to/file.wav');
///
/// // Get recent
/// final recentFiles = service.getRecent(RecentItemType.file);
/// ```

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// RECENT ITEM TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Types of items that can be recent/favorited
enum RecentItemType {
  file('File', '📁'),
  project('Project', '📂'),
  preset('Preset', '💾'),
  event('Event', '🎵'),
  plugin('Plugin', '🧩'),
  folder('Folder', '📁');

  final String label;
  final String emoji;

  const RecentItemType(this.label, this.emoji);
}

/// A recent or favorited item
class RecentItem {
  final String id;
  final RecentItemType type;
  final String title;
  final String? subtitle;
  final String? path;
  final DateTime lastAccessed;
  final int accessCount;
  final bool isFavorite;
  final Map<String, dynamic>? metadata;

  const RecentItem({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    this.path,
    required this.lastAccessed,
    this.accessCount = 1,
    this.isFavorite = false,
    this.metadata,
  });

  /// Create file item
  factory RecentItem.file({
    required String path,
    String? title,
    String? size,
    DateTime? lastAccessed,
  }) {
    final filename = path.split('/').last;
    return RecentItem(
      id: 'file:$path',
      type: RecentItemType.file,
      title: title ?? filename,
      subtitle: path.substring(0, path.length - filename.length - 1),
      path: path,
      lastAccessed: lastAccessed ?? DateTime.now(),
      metadata: {'size': size},
    );
  }

  /// Create project item
  factory RecentItem.project({
    required String path,
    required String name,
    DateTime? lastAccessed,
  }) {
    return RecentItem(
      id: 'project:$path',
      type: RecentItemType.project,
      title: name,
      subtitle: path,
      path: path,
      lastAccessed: lastAccessed ?? DateTime.now(),
    );
  }

  /// Create preset item
  factory RecentItem.preset({
    required String presetId,
    required String name,
    String? pluginName,
    DateTime? lastAccessed,
  }) {
    return RecentItem(
      id: 'preset:$presetId',
      type: RecentItemType.preset,
      title: name,
      subtitle: pluginName,
      lastAccessed: lastAccessed ?? DateTime.now(),
      metadata: {'presetId': presetId},
    );
  }

  /// Create event item
  factory RecentItem.event({
    required String eventId,
    required String name,
    String? stageName,
    DateTime? lastAccessed,
  }) {
    return RecentItem(
      id: 'event:$eventId',
      type: RecentItemType.event,
      title: name,
      subtitle: stageName,
      lastAccessed: lastAccessed ?? DateTime.now(),
      metadata: {'eventId': eventId},
    );
  }

  /// Create with updated access
  RecentItem withAccess() {
    return RecentItem(
      id: id,
      type: type,
      title: title,
      subtitle: subtitle,
      path: path,
      lastAccessed: DateTime.now(),
      accessCount: accessCount + 1,
      isFavorite: isFavorite,
      metadata: metadata,
    );
  }

  /// Create with favorite toggle
  RecentItem withFavorite(bool favorite) {
    return RecentItem(
      id: id,
      type: type,
      title: title,
      subtitle: subtitle,
      path: path,
      lastAccessed: lastAccessed,
      accessCount: accessCount,
      isFavorite: favorite,
      metadata: metadata,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'subtitle': subtitle,
      'path': path,
      'lastAccessed': lastAccessed.toIso8601String(),
      'accessCount': accessCount,
      'isFavorite': isFavorite,
      'metadata': metadata,
    };
  }

  /// Deserialize from JSON
  factory RecentItem.fromJson(Map<String, dynamic> json) {
    return RecentItem(
      id: json['id'] as String,
      type: RecentItemType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => RecentItemType.file,
      ),
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      path: json['path'] as String?,
      lastAccessed: DateTime.parse(json['lastAccessed'] as String),
      accessCount: json['accessCount'] as int? ?? 1,
      isFavorite: json['isFavorite'] as bool? ?? false,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RECENT FAVORITES SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Service for managing recent and favorite items
class RecentFavoritesService extends ChangeNotifier {
  static RecentFavoritesService? _instance;
  static RecentFavoritesService get instance => _instance ??= RecentFavoritesService._();

  RecentFavoritesService._();

  static const String _recentKey = 'fluxforge_recent_items';
  static const String _favoritesKey = 'fluxforge_favorite_items';
  static const int _maxRecentPerType = 20;
  static const int _maxTotalRecent = 100;

  final Map<String, RecentItem> _items = {};
  bool _isLoaded = false;

  /// Load from persistent storage
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load recent items
      final recentJson = prefs.getString(_recentKey);
      if (recentJson != null) {
        final List<dynamic> recentList = jsonDecode(recentJson);
        for (final json in recentList) {
          final item = RecentItem.fromJson(json as Map<String, dynamic>);
          _items[item.id] = item;
        }
      }

      // Load favorites (merge with recent)
      final favoritesJson = prefs.getString(_favoritesKey);
      if (favoritesJson != null) {
        final List<dynamic> favoritesList = jsonDecode(favoritesJson);
        for (final json in favoritesList) {
          final item = RecentItem.fromJson(json as Map<String, dynamic>);
          if (_items.containsKey(item.id)) {
            _items[item.id] = _items[item.id]!.withFavorite(true);
          } else {
            _items[item.id] = item.withFavorite(true);
          }
        }
      }

      _isLoaded = true;
    } catch (e) { /* ignored */ }
  }

  /// Save to persistent storage
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save recent items
      final recentItems = _items.values.toList()
        ..sort((a, b) => b.lastAccessed.compareTo(a.lastAccessed));
      final recentJson = jsonEncode(recentItems.take(_maxTotalRecent).map((i) => i.toJson()).toList());
      await prefs.setString(_recentKey, recentJson);

      // Save favorites separately (for quick loading)
      final favoriteItems = _items.values.where((i) => i.isFavorite).toList();
      final favoritesJson = jsonEncode(favoriteItems.map((i) => i.toJson()).toList());
      await prefs.setString(_favoritesKey, favoritesJson);

    } catch (e) { /* ignored */ }
  }

  /// Add or update a recent item
  void addRecent(RecentItem item) {
    if (_items.containsKey(item.id)) {
      // Update existing
      final existing = _items[item.id]!;
      _items[item.id] = existing.withAccess();
    } else {
      // Add new
      _items[item.id] = item;
    }

    _pruneRecent();
    notifyListeners();
    save();
  }

  /// Remove an item
  void remove(String id) {
    _items.remove(id);
    notifyListeners();
    save();
  }

  /// Toggle favorite status
  void toggleFavorite(String id) {
    if (_items.containsKey(id)) {
      final item = _items[id]!;
      _items[id] = item.withFavorite(!item.isFavorite);
      notifyListeners();
      save();
    }
  }

  /// Set favorite status
  void setFavorite(String id, bool favorite) {
    if (_items.containsKey(id)) {
      _items[id] = _items[id]!.withFavorite(favorite);
      notifyListeners();
      save();
    }
  }

  /// Get recent items by type
  List<RecentItem> getRecent(RecentItemType type, {int? limit}) {
    final items = _items.values
        .where((i) => i.type == type)
        .toList()
      ..sort((a, b) => b.lastAccessed.compareTo(a.lastAccessed));

    return limit != null ? items.take(limit).toList() : items;
  }

  /// Get all recent items (sorted by last accessed)
  List<RecentItem> getAllRecent({int? limit}) {
    final items = _items.values.toList()
      ..sort((a, b) => b.lastAccessed.compareTo(a.lastAccessed));

    return limit != null ? items.take(limit).toList() : items;
  }

  /// Get favorite items
  List<RecentItem> getFavorites({RecentItemType? type}) {
    var items = _items.values.where((i) => i.isFavorite);

    if (type != null) {
      items = items.where((i) => i.type == type);
    }

    return items.toList()..sort((a, b) => a.title.compareTo(b.title));
  }

  /// Get most frequently accessed items
  List<RecentItem> getMostUsed({int limit = 10, RecentItemType? type}) {
    var items = _items.values;

    if (type != null) {
      items = items.where((i) => i.type == type);
    }

    final sorted = items.toList()
      ..sort((a, b) => b.accessCount.compareTo(a.accessCount));

    return sorted.take(limit).toList();
  }

  /// Check if item is favorited
  bool isFavorite(String id) {
    return _items[id]?.isFavorite ?? false;
  }

  /// Get item by ID
  RecentItem? getItem(String id) {
    return _items[id];
  }

  /// Clear all recent items (keeps favorites)
  void clearRecent() {
    final favorites = _items.entries.where((e) => e.value.isFavorite).toList();
    _items.clear();
    for (final entry in favorites) {
      _items[entry.key] = entry.value;
    }
    notifyListeners();
    save();
  }

  /// Clear everything
  void clearAll() {
    _items.clear();
    notifyListeners();
    save();
  }

  /// Get counts
  int get recentCount => _items.length;
  int get favoriteCount => _items.values.where((i) => i.isFavorite).length;

  /// Prune old items to stay within limits
  void _pruneRecent() {
    // Prune per type
    for (final type in RecentItemType.values) {
      final typeItems = _items.values
          .where((i) => i.type == type && !i.isFavorite)
          .toList()
        ..sort((a, b) => b.lastAccessed.compareTo(a.lastAccessed));

      if (typeItems.length > _maxRecentPerType) {
        for (int i = _maxRecentPerType; i < typeItems.length; i++) {
          _items.remove(typeItems[i].id);
        }
      }
    }

    // Prune total
    if (_items.length > _maxTotalRecent) {
      final sorted = _items.values
          .where((i) => !i.isFavorite)
          .toList()
        ..sort((a, b) => b.lastAccessed.compareTo(a.lastAccessed));

      for (int i = _maxTotalRecent; i < sorted.length; i++) {
        _items.remove(sorted[i].id);
      }
    }
  }
}
