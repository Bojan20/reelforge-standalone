/// Unified Search Service — Cmd+F Global Search
///
/// P2.3: Provides global search functionality across all content types.
///
/// Search categories:
/// - Files (audio files, presets, projects)
/// - Events (SlotLab audio events, stages)
/// - Tracks (DAW tracks)
/// - Clips (timeline clips)
/// - Plugins (VST3/AU/CLAP)
/// - Presets (DSP presets)
/// - Parameters (EQ bands, compressor settings)
/// - Documentation (help, shortcuts)
///
/// Usage:
/// ```dart
/// final service = UnifiedSearchService.instance;
///
/// // Register a searchable provider
/// service.registerProvider(MySearchProvider());
///
/// // Search
/// final results = await service.search('reverb');
/// ```

import 'dart:async';
import 'package:flutter/foundation.dart';

import 'recent_favorites_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SEARCH RESULT TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Categories for search results
enum SearchCategory {
  file('Files', '📁'),
  event('Events', '🎵'),
  track('Tracks', '🎚️'),
  clip('Clips', '📎'),
  plugin('Plugins', '🧩'),
  preset('Presets', '💾'),
  parameter('Parameters', '🎛️'),
  stage('Stages', '⚡'),
  help('Help', '❓'),
  recent('Recent', '🕐');

  final String label;
  final String emoji;

  const SearchCategory(this.label, this.emoji);
}

/// A single search result
class SearchResult {
  final String id;
  final String title;
  final String? subtitle;
  final SearchCategory category;
  final String? iconPath;
  final double relevance; // 0.0 - 1.0
  final Map<String, dynamic>? metadata;
  final VoidCallback? onSelect;

  const SearchResult({
    required this.id,
    required this.title,
    this.subtitle,
    required this.category,
    this.iconPath,
    this.relevance = 0.5,
    this.metadata,
    this.onSelect,
  });

  /// Create with file result
  factory SearchResult.file({
    required String id,
    required String filename,
    String? path,
    String? size,
    VoidCallback? onSelect,
  }) {
    return SearchResult(
      id: id,
      title: filename,
      subtitle: path,
      category: SearchCategory.file,
      metadata: {'size': size},
      onSelect: onSelect,
    );
  }

  /// Create with event result
  factory SearchResult.event({
    required String id,
    required String eventName,
    String? stageName,
    int? layerCount,
    VoidCallback? onSelect,
  }) {
    return SearchResult(
      id: id,
      title: eventName,
      subtitle: stageName != null ? 'Stage: $stageName' : null,
      category: SearchCategory.event,
      metadata: {'layerCount': layerCount},
      onSelect: onSelect,
    );
  }

  /// Create with track result
  factory SearchResult.track({
    required String id,
    required String trackName,
    int? clipCount,
    VoidCallback? onSelect,
  }) {
    return SearchResult(
      id: id,
      title: trackName,
      subtitle: clipCount != null ? '$clipCount clips' : null,
      category: SearchCategory.track,
      onSelect: onSelect,
    );
  }

  /// Create with preset result
  factory SearchResult.preset({
    required String id,
    required String presetName,
    String? pluginName,
    VoidCallback? onSelect,
  }) {
    return SearchResult(
      id: id,
      title: presetName,
      subtitle: pluginName,
      category: SearchCategory.preset,
      onSelect: onSelect,
    );
  }

  /// Create with help result
  factory SearchResult.help({
    required String id,
    required String title,
    required String description,
    VoidCallback? onSelect,
  }) {
    return SearchResult(
      id: id,
      title: title,
      subtitle: description,
      category: SearchCategory.help,
      relevance: 0.3,
      onSelect: onSelect,
    );
  }
}

/// Grouped search results by category
class SearchResults {
  final String query;
  final List<SearchResult> results;
  final Duration searchTime;
  final bool hasMore;

  const SearchResults({
    required this.query,
    required this.results,
    required this.searchTime,
    this.hasMore = false,
  });

  /// Get results grouped by category
  Map<SearchCategory, List<SearchResult>> get byCategory {
    final grouped = <SearchCategory, List<SearchResult>>{};
    for (final result in results) {
      grouped.putIfAbsent(result.category, () => []).add(result);
    }
    return grouped;
  }

  /// Get top results across all categories
  List<SearchResult> get topResults {
    final sorted = List<SearchResult>.from(results)
      ..sort((a, b) => b.relevance.compareTo(a.relevance));
    return sorted.take(10).toList();
  }

  /// Result count
  int get count => results.length;

  /// Empty results
  static const SearchResults empty = SearchResults(
    query: '',
    results: [],
    searchTime: Duration.zero,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEARCH PROVIDER INTERFACE
// ═══════════════════════════════════════════════════════════════════════════════

/// Interface for providing searchable content
abstract class SearchProvider {
  /// Categories this provider handles
  Set<SearchCategory> get categories;

  /// Search within this provider
  Future<List<SearchResult>> search(String query, {
    Set<SearchCategory>? filterCategories,
    int maxResults,
  });

  /// Optional: Provide suggestions for empty query
  Future<List<SearchResult>> getSuggestions({int maxResults = 5}) async => [];
}

// ═══════════════════════════════════════════════════════════════════════════════
// UNIFIED SEARCH SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Global unified search service
class UnifiedSearchService extends ChangeNotifier {
  static UnifiedSearchService? _instance;
  static UnifiedSearchService get instance => _instance ??= UnifiedSearchService._();

  UnifiedSearchService._();

  final List<SearchProvider> _providers = [];
  final List<SearchResult> _recentSearches = [];
  static const int _maxRecentSearches = 20;

  // Current search state
  String _currentQuery = '';
  SearchResults? _currentResults;
  bool _isSearching = false;

  String get currentQuery => _currentQuery;
  SearchResults? get currentResults => _currentResults;
  bool get isSearching => _isSearching;
  List<SearchResult> get recentSearches => List.unmodifiable(_recentSearches);

  /// Register a search provider
  void registerProvider(SearchProvider provider) {
    _providers.add(provider);
  }

  /// Unregister a search provider
  void unregisterProvider(SearchProvider provider) {
    _providers.remove(provider);
  }

  /// Get a provider by type (for initialization after registration)
  T? getProvider<T extends SearchProvider>() {
    for (final provider in _providers) {
      if (provider is T) return provider;
    }
    return null;
  }

  /// Clear all providers
  void clearProviders() {
    _providers.clear();
  }

  /// Perform a search across all providers
  Future<SearchResults> search(
    String query, {
    Set<SearchCategory>? filterCategories,
    int maxResultsPerProvider = 10,
  }) async {
    if (query.isEmpty) {
      _currentQuery = '';
      _currentResults = SearchResults.empty;
      notifyListeners();
      return SearchResults.empty;
    }

    _currentQuery = query;
    _isSearching = true;
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    final allResults = <SearchResult>[];

    // Search all providers in parallel
    final futures = _providers.map((provider) async {
      try {
        return await provider.search(
          query,
          filterCategories: filterCategories,
          maxResults: maxResultsPerProvider,
        );
      } catch (e) {
        return <SearchResult>[];
      }
    });

    final results = await Future.wait(futures);
    for (final providerResults in results) {
      allResults.addAll(providerResults);
    }

    // Sort by relevance
    allResults.sort((a, b) => b.relevance.compareTo(a.relevance));

    stopwatch.stop();

    _currentResults = SearchResults(
      query: query,
      results: allResults,
      searchTime: stopwatch.elapsed,
      hasMore: allResults.length >= maxResultsPerProvider * _providers.length,
    );

    // P3.3: Record to search history
    recordSearch(query, allResults.length);

    _isSearching = false;
    notifyListeners();

    return _currentResults!;
  }

  /// Get suggestions (recent + provider suggestions)
  Future<List<SearchResult>> getSuggestions({int maxResults = 10}) async {
    final suggestions = <SearchResult>[];

    // Add recent searches
    for (final recent in _recentSearches.take(5)) {
      suggestions.add(SearchResult(
        id: 'recent_${recent.id}',
        title: recent.title,
        subtitle: 'Recent',
        category: SearchCategory.recent,
        relevance: 0.8,
        onSelect: recent.onSelect,
      ));
    }

    // Get provider suggestions
    for (final provider in _providers) {
      final providerSuggestions = await provider.getSuggestions(maxResults: 3);
      suggestions.addAll(providerSuggestions);
    }

    return suggestions.take(maxResults).toList();
  }

  /// Add to recent searches
  void addToRecent(SearchResult result) {
    // Remove if already exists
    _recentSearches.removeWhere((r) => r.id == result.id);

    // Add to front
    _recentSearches.insert(0, result);

    // Limit size
    while (_recentSearches.length > _maxRecentSearches) {
      _recentSearches.removeLast();
    }
  }

  /// Clear recent searches
  void clearRecent() {
    _recentSearches.clear();
    notifyListeners();
  }

  /// Clear current search
  void clearSearch() {
    _currentQuery = '';
    _currentResults = null;
    _isSearching = false;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P3.3: SEARCH HISTORY PERSISTENCE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Search history for persistence
  final List<SearchHistoryEntry> _searchHistory = [];
  static const int _maxSearchHistory = 50;

  /// Get search history
  List<SearchHistoryEntry> get searchHistory => List.unmodifiable(_searchHistory);

  /// Record a search query to history
  void recordSearch(String query, int resultCount) {
    if (query.trim().isEmpty) return;

    // Remove duplicate if exists
    _searchHistory.removeWhere((e) => e.query.toLowerCase() == query.toLowerCase());

    // Add new entry
    _searchHistory.insert(0, SearchHistoryEntry(
      query: query,
      timestamp: DateTime.now(),
      resultCount: resultCount,
    ));

    // Limit size
    while (_searchHistory.length > _maxSearchHistory) {
      _searchHistory.removeLast();
    }
  }

  /// Get recent search queries
  List<String> getRecentQueries({int maxResults = 10}) {
    return _searchHistory
        .take(maxResults)
        .map((e) => e.query)
        .toList();
  }

  /// Clear search history
  void clearSearchHistory() {
    _searchHistory.clear();
    notifyListeners();
  }

  /// Export search history as JSON for persistence
  List<Map<String, dynamic>> exportSearchHistory() {
    return _searchHistory.map((e) => e.toJson()).toList();
  }

  /// Import search history from JSON
  void importSearchHistory(List<dynamic> json) {
    _searchHistory.clear();
    for (final item in json) {
      if (item is Map<String, dynamic>) {
        _searchHistory.add(SearchHistoryEntry.fromJson(item));
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BUILT-IN SEARCH PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Help/shortcuts search provider
class HelpSearchProvider extends SearchProvider {
  final List<_HelpEntry> _entries = [
    _HelpEntry('Undo', 'Cmd+Z', 'Undo last action'),
    _HelpEntry('Redo', 'Cmd+Shift+Z', 'Redo last undone action'),
    _HelpEntry('Save', 'Cmd+S', 'Save project'),
    _HelpEntry('Save As', 'Cmd+Shift+S', 'Save project with new name'),
    _HelpEntry('New Track', 'Cmd+T', 'Create new audio track'),
    _HelpEntry('Delete', 'Delete/Backspace', 'Delete selected items'),
    _HelpEntry('Duplicate', 'Cmd+D', 'Duplicate selected items'),
    _HelpEntry('Split', 'S', 'Split clip at playhead'),
    _HelpEntry('Play/Pause', 'Space', 'Toggle playback'),
    _HelpEntry('Stop', 'Enter', 'Stop playback and return to start'),
    _HelpEntry('Loop', 'L', 'Toggle loop mode'),
    _HelpEntry('Zoom In', 'Cmd++', 'Zoom in timeline'),
    _HelpEntry('Zoom Out', 'Cmd+-', 'Zoom out timeline'),
    _HelpEntry('Zoom Fit', 'Cmd+0', 'Fit entire project in view'),
    _HelpEntry('Snap', 'N', 'Toggle snap to grid'),
    _HelpEntry('Solo', 'S (on track)', 'Solo selected track'),
    _HelpEntry('Mute', 'M (on track)', 'Mute selected track'),
    _HelpEntry('Search', 'Cmd+F', 'Open unified search'),
    _HelpEntry('Close Panel', 'Escape', 'Close current panel or dialog'),
    _HelpEntry('Spin (SlotLab)', 'Space', 'Trigger spin in SlotLab'),
    _HelpEntry('Forced Win', '1-9', 'Force specific outcome in SlotLab'),
  ];

  @override
  Set<SearchCategory> get categories => {SearchCategory.help};

  @override
  Future<List<SearchResult>> search(String query, {
    Set<SearchCategory>? filterCategories,
    int maxResults = 10,
  }) async {
    if (filterCategories != null && !filterCategories.contains(SearchCategory.help)) {
      return [];
    }

    final queryLower = query.toLowerCase();
    final results = <SearchResult>[];

    for (final entry in _entries) {
      final titleMatch = entry.title.toLowerCase().contains(queryLower);
      final shortcutMatch = entry.shortcut.toLowerCase().contains(queryLower);
      final descMatch = entry.description.toLowerCase().contains(queryLower);

      if (titleMatch || shortcutMatch || descMatch) {
        double relevance = 0.3;
        if (titleMatch) relevance += 0.4;
        if (shortcutMatch) relevance += 0.2;
        if (descMatch) relevance += 0.1;

        results.add(SearchResult.help(
          id: 'help_${entry.title.toLowerCase().replaceAll(' ', '_')}',
          title: '${entry.title} (${entry.shortcut})',
          description: entry.description,
        ));
      }
    }

    return results.take(maxResults).toList();
  }
}

class _HelpEntry {
  final String title;
  final String shortcut;
  final String description;

  _HelpEntry(this.title, this.shortcut, this.description);
}

/// Recent items search provider — searches RecentFavoritesService
class RecentSearchProvider extends SearchProvider {
  @override
  Set<SearchCategory> get categories => {
    SearchCategory.file,
    SearchCategory.event,
    SearchCategory.preset,
    SearchCategory.recent,
  };

  @override
  Future<List<SearchResult>> search(String query, {
    Set<SearchCategory>? filterCategories,
    int maxResults = 10,
  }) async {
    final service = RecentFavoritesService.instance;
    final queryLower = query.toLowerCase();
    final results = <SearchResult>[];

    // Search all recent items
    for (final item in service.getAllRecent()) {
      // Check category filter
      final itemCategory = _typeToCategory(item.type);
      if (filterCategories != null && !filterCategories.contains(itemCategory)) {
        continue;
      }

      // Match against title and subtitle
      final titleMatch = item.title.toLowerCase().contains(queryLower);
      final subtitleMatch = item.subtitle?.toLowerCase().contains(queryLower) ?? false;

      if (titleMatch || subtitleMatch) {
        double relevance = 0.4;
        if (titleMatch) relevance += 0.3;
        if (subtitleMatch) relevance += 0.1;
        if (item.isFavorite) relevance += 0.2;

        results.add(SearchResult(
          id: item.id,
          title: item.title,
          subtitle: item.subtitle,
          category: itemCategory,
          relevance: relevance.clamp(0.0, 1.0),
          metadata: {'accessCount': item.accessCount, 'isFavorite': item.isFavorite},
        ));
      }
    }

    results.sort((a, b) => b.relevance.compareTo(a.relevance));
    return results.take(maxResults).toList();
  }

  @override
  Future<List<SearchResult>> getSuggestions({int maxResults = 5}) async {
    final service = RecentFavoritesService.instance;
    final results = <SearchResult>[];

    // Add favorites first
    for (final item in service.getFavorites().take(3)) {
      results.add(SearchResult(
        id: item.id,
        title: item.title,
        subtitle: '★ Favorite',
        category: _typeToCategory(item.type),
        relevance: 0.9,
      ));
    }

    // Then most used
    for (final item in service.getMostUsed(limit: maxResults - results.length)) {
      if (!results.any((r) => r.id == item.id)) {
        results.add(SearchResult(
          id: item.id,
          title: item.title,
          subtitle: 'Used ${item.accessCount}×',
          category: _typeToCategory(item.type),
          relevance: 0.7,
        ));
      }
    }

    return results.take(maxResults).toList();
  }

  SearchCategory _typeToCategory(RecentItemType type) {
    return switch (type) {
      RecentItemType.file => SearchCategory.file,
      RecentItemType.project => SearchCategory.file,
      RecentItemType.preset => SearchCategory.preset,
      RecentItemType.event => SearchCategory.event,
      RecentItemType.plugin => SearchCategory.plugin,
      RecentItemType.folder => SearchCategory.file,
    };
  }
}

/// Event search provider — searches SlotLab composite events from MiddlewareProvider
class EventSearchProvider extends SearchProvider {
  /// Callback to get composite events from MiddlewareProvider
  /// Set this via init() before using
  List<Map<String, dynamic>> Function()? _getEventsCallback;
  VoidCallback? _onEventSelectCallback;
  String? _selectedEventIdSetter;

  /// Initialize with callbacks to access provider data
  void init({
    required List<Map<String, dynamic>> Function() getEvents,
    VoidCallback? onEventSelect,
  }) {
    _getEventsCallback = getEvents;
    _onEventSelectCallback = onEventSelect;
  }

  @override
  Set<SearchCategory> get categories => {
    SearchCategory.event,
    SearchCategory.stage,
  };

  @override
  Future<List<SearchResult>> search(String query, {
    Set<SearchCategory>? filterCategories,
    int maxResults = 10,
  }) async {
    if (_getEventsCallback == null) {
      return [];
    }

    final events = _getEventsCallback!();
    final queryLower = query.toLowerCase();
    final results = <SearchResult>[];

    for (final event in events) {
      // Extract event properties
      final eventId = event['id'] as String? ?? '';
      final eventName = event['name'] as String? ?? 'Unnamed Event';
      final stages = (event['stages'] as List<dynamic>?)?.cast<String>() ?? [];
      final layers = (event['layers'] as List<dynamic>?) ?? [];
      final containerType = event['containerType'] as String?;

      // Match against name, stages, and layers
      final nameMatch = eventName.toLowerCase().contains(queryLower);
      final stageMatch = stages.any((s) => s.toLowerCase().contains(queryLower));
      final layerMatch = layers.any((l) {
        final layerName = (l as Map<String, dynamic>?)?['audioPath'] as String? ?? '';
        return layerName.toLowerCase().contains(queryLower);
      });

      if (nameMatch || stageMatch || layerMatch) {
        // Check category filter
        final matchCategory = stageMatch ? SearchCategory.stage : SearchCategory.event;
        if (filterCategories != null && !filterCategories.contains(matchCategory)) {
          continue;
        }

        double relevance = 0.3;
        if (nameMatch) relevance += 0.4;
        if (stageMatch) relevance += 0.2;
        if (layerMatch) relevance += 0.1;

        // Build subtitle
        String? subtitle;
        if (stages.isNotEmpty) {
          subtitle = 'Stages: ${stages.take(3).join(', ')}${stages.length > 3 ? '...' : ''}';
        }
        if (containerType != null && containerType != 'none') {
          final containerLabel = containerType[0].toUpperCase() + containerType.substring(1);
          subtitle = subtitle != null
              ? '$subtitle • $containerLabel container'
              : '$containerLabel container';
        }

        results.add(SearchResult.event(
          id: eventId,
          eventName: eventName,
          stageName: subtitle,
          layerCount: layers.length,
          onSelect: _onEventSelectCallback,
        ));
      }
    }

    results.sort((a, b) => b.relevance.compareTo(a.relevance));
    return results.take(maxResults).toList();
  }

  @override
  Future<List<SearchResult>> getSuggestions({int maxResults = 5}) async {
    if (_getEventsCallback == null) return [];

    final events = _getEventsCallback!();
    final results = <SearchResult>[];

    // Return first few events as suggestions
    for (final event in events.take(maxResults)) {
      final eventId = event['id'] as String? ?? '';
      final eventName = event['name'] as String? ?? 'Unnamed Event';
      final stages = (event['stages'] as List<dynamic>?)?.cast<String>() ?? [];
      final layers = (event['layers'] as List<dynamic>?) ?? [];

      results.add(SearchResult.event(
        id: eventId,
        eventName: eventName,
        stageName: stages.isNotEmpty ? stages.first : null,
        layerCount: layers.length,
        onSelect: _onEventSelectCallback,
      ));
    }

    return results;
  }
}

/// Static content provider (for items that don't change often)
class StaticSearchProvider extends SearchProvider {
  final Set<SearchCategory> _categories;
  final List<SearchResult> _items;

  StaticSearchProvider({
    required Set<SearchCategory> categories,
    required List<SearchResult> items,
  }) : _categories = categories, _items = items;

  @override
  Set<SearchCategory> get categories => _categories;

  @override
  Future<List<SearchResult>> search(String query, {
    Set<SearchCategory>? filterCategories,
    int maxResults = 10,
  }) async {
    final queryLower = query.toLowerCase();
    final results = <SearchResult>[];

    for (final item in _items) {
      if (filterCategories != null && !filterCategories.contains(item.category)) {
        continue;
      }

      final titleMatch = item.title.toLowerCase().contains(queryLower);
      final subtitleMatch = item.subtitle?.toLowerCase().contains(queryLower) ?? false;

      if (titleMatch || subtitleMatch) {
        double relevance = item.relevance;
        if (titleMatch) relevance += 0.3;
        if (subtitleMatch) relevance += 0.1;

        results.add(SearchResult(
          id: item.id,
          title: item.title,
          subtitle: item.subtitle,
          category: item.category,
          relevance: relevance.clamp(0.0, 1.0),
          metadata: item.metadata,
          onSelect: item.onSelect,
        ));
      }
    }

    results.sort((a, b) => b.relevance.compareTo(a.relevance));
    return results.take(maxResults).toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// P2.1: FILE SEARCH PROVIDER — Audio Pool Files
// ═══════════════════════════════════════════════════════════════════════════════

/// File search provider — searches AudioAssetManager for imported audio files
class FileSearchProvider extends SearchProvider {
  /// Callback to get assets from AudioAssetManager
  List<Map<String, dynamic>> Function()? _getAssetsCallback;
  void Function(String path)? _onFileSelectCallback;

  /// Initialize with callbacks to access asset data
  void init({
    required List<Map<String, dynamic>> Function() getAssets,
    void Function(String path)? onFileSelect,
  }) {
    _getAssetsCallback = getAssets;
    _onFileSelectCallback = onFileSelect;
  }

  @override
  Set<SearchCategory> get categories => {SearchCategory.file};

  @override
  Future<List<SearchResult>> search(String query, {
    Set<SearchCategory>? filterCategories,
    int maxResults = 10,
  }) async {
    if (filterCategories != null && !filterCategories.contains(SearchCategory.file)) {
      return [];
    }

    if (_getAssetsCallback == null) {
      return [];
    }

    final assets = _getAssetsCallback!();
    final results = <SearchResult>[];

    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      final path = asset['path'] as String? ?? '';
      final folder = asset['folder'] as String? ?? '';
      final duration = asset['duration'] as double? ?? 0.0;

      // Use fuzzy matching
      final score = _fuzzyMatch(query, name) * 0.7 +
                    _fuzzyMatch(query, folder) * 0.2 +
                    _fuzzyMatch(query, path) * 0.1;

      if (score > 0.3) {
        final durationStr = _formatDuration(duration);
        results.add(SearchResult.file(
          id: 'file:$path',
          filename: name,
          path: folder.isNotEmpty ? '$folder/' : null,
          size: durationStr,
          onSelect: _onFileSelectCallback != null
              ? () => _onFileSelectCallback!(path)
              : null,
        )..copyWith(relevance: score));
      }
    }

    results.sort((a, b) => b.relevance.compareTo(a.relevance));
    return results.take(maxResults).toList();
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '${mins}:${secs.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// P2.2: TRACK SEARCH PROVIDER — Timeline Tracks
// ═══════════════════════════════════════════════════════════════════════════════

/// Track search provider — searches timeline tracks
class TrackSearchProvider extends SearchProvider {
  /// Callback to get tracks from timeline provider
  List<Map<String, dynamic>> Function()? _getTracksCallback;
  void Function(String trackId)? _onTrackSelectCallback;

  /// Initialize with callbacks
  void init({
    required List<Map<String, dynamic>> Function() getTracks,
    void Function(String trackId)? onTrackSelect,
  }) {
    _getTracksCallback = getTracks;
    _onTrackSelectCallback = onTrackSelect;
  }

  @override
  Set<SearchCategory> get categories => {SearchCategory.track};

  @override
  Future<List<SearchResult>> search(String query, {
    Set<SearchCategory>? filterCategories,
    int maxResults = 10,
  }) async {
    if (filterCategories != null && !filterCategories.contains(SearchCategory.track)) {
      return [];
    }

    if (_getTracksCallback == null) {
      return [];
    }

    final tracks = _getTracksCallback!();
    final results = <SearchResult>[];

    for (final track in tracks) {
      final id = track['id'] as String? ?? '';
      final name = track['name'] as String? ?? 'Unnamed Track';
      final clipCount = track['clipCount'] as int? ?? 0;
      final trackType = track['type'] as String? ?? 'audio';

      // Use fuzzy matching
      final score = _fuzzyMatch(query, name);

      if (score > 0.3) {
        results.add(SearchResult.track(
          id: 'track:$id',
          trackName: name,
          clipCount: clipCount,
          onSelect: _onTrackSelectCallback != null
              ? () => _onTrackSelectCallback!(id)
              : null,
        )..copyWith(relevance: score));
      }
    }

    results.sort((a, b) => b.relevance.compareTo(a.relevance));
    return results.take(maxResults).toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// P2.3: PRESET SEARCH PROVIDER — DSP Presets
// ═══════════════════════════════════════════════════════════════════════════════

/// Preset search provider — searches DSP presets
class PresetSearchProvider extends SearchProvider {
  /// Callback to get presets
  List<Map<String, dynamic>> Function()? _getPresetsCallback;
  void Function(String presetId)? _onPresetSelectCallback;

  /// Initialize with callbacks
  void init({
    required List<Map<String, dynamic>> Function() getPresets,
    void Function(String presetId)? onPresetSelect,
  }) {
    _getPresetsCallback = getPresets;
    _onPresetSelectCallback = onPresetSelect;
  }

  @override
  Set<SearchCategory> get categories => {SearchCategory.preset};

  @override
  Future<List<SearchResult>> search(String query, {
    Set<SearchCategory>? filterCategories,
    int maxResults = 10,
  }) async {
    if (filterCategories != null && !filterCategories.contains(SearchCategory.preset)) {
      return [];
    }

    if (_getPresetsCallback == null) {
      return [];
    }

    final presets = _getPresetsCallback!();
    final results = <SearchResult>[];

    for (final preset in presets) {
      final id = preset['id'] as String? ?? '';
      final name = preset['name'] as String? ?? 'Unnamed Preset';
      final pluginName = preset['pluginName'] as String?;
      final category = preset['category'] as String?;

      // Use fuzzy matching against name, plugin, and category
      final nameScore = _fuzzyMatch(query, name);
      final pluginScore = pluginName != null ? _fuzzyMatch(query, pluginName) * 0.5 : 0.0;
      final categoryScore = category != null ? _fuzzyMatch(query, category) * 0.3 : 0.0;
      final score = (nameScore + pluginScore + categoryScore).clamp(0.0, 1.0);

      if (score > 0.3) {
        results.add(SearchResult.preset(
          id: 'preset:$id',
          presetName: name,
          pluginName: pluginName ?? category,
          onSelect: _onPresetSelectCallback != null
              ? () => _onPresetSelectCallback!(id)
              : null,
        )..copyWith(relevance: score));
      }
    }

    results.sort((a, b) => b.relevance.compareTo(a.relevance));
    return results.take(maxResults).toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// P3.2: FUZZY MATCHING UTILITY
// ═══════════════════════════════════════════════════════════════════════════════

/// Fuzzy string matching score (0.0 - 1.0)
/// Supports:
/// - Exact match (1.0)
/// - Prefix match (0.9)
/// - Contains match (0.7)
/// - Subsequence match (0.5)
/// - Levenshtein distance (0.3-0.6)
double _fuzzyMatch(String query, String target) {
  if (query.isEmpty || target.isEmpty) return 0.0;

  final queryLower = query.toLowerCase();
  final targetLower = target.toLowerCase();

  // Exact match
  if (queryLower == targetLower) return 1.0;

  // Prefix match
  if (targetLower.startsWith(queryLower)) {
    return 0.9 - (0.1 * (target.length - query.length) / target.length);
  }

  // Contains match
  if (targetLower.contains(queryLower)) {
    final position = targetLower.indexOf(queryLower);
    return 0.7 - (0.1 * position / target.length);
  }

  // Subsequence match (all query chars appear in order)
  if (_isSubsequence(queryLower, targetLower)) {
    return 0.5;
  }

  // Levenshtein distance for typo tolerance
  final distance = _levenshteinDistance(queryLower, targetLower);
  final maxLen = target.length > query.length ? target.length : query.length;
  final similarity = 1.0 - (distance / maxLen);

  // Only return if similarity is reasonable (within 2-3 typos)
  if (similarity > 0.6) {
    return similarity * 0.5; // Scale down fuzzy matches
  }

  return 0.0;
}

/// Check if query is a subsequence of target
bool _isSubsequence(String query, String target) {
  int queryIdx = 0;
  for (int i = 0; i < target.length && queryIdx < query.length; i++) {
    if (target[i] == query[queryIdx]) {
      queryIdx++;
    }
  }
  return queryIdx == query.length;
}

/// Levenshtein edit distance
int _levenshteinDistance(String s1, String s2) {
  if (s1.isEmpty) return s2.length;
  if (s2.isEmpty) return s1.length;

  // Use only two rows for memory efficiency
  List<int> prev = List.generate(s2.length + 1, (i) => i);
  List<int> curr = List.filled(s2.length + 1, 0);

  for (int i = 1; i <= s1.length; i++) {
    curr[0] = i;
    for (int j = 1; j <= s2.length; j++) {
      final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
      curr[j] = [
        prev[j] + 1,      // deletion
        curr[j - 1] + 1,  // insertion
        prev[j - 1] + cost // substitution
      ].reduce((a, b) => a < b ? a : b);
    }
    final temp = prev;
    prev = curr;
    curr = temp;
  }

  return prev[s2.length];
}

// ═══════════════════════════════════════════════════════════════════════════════
// P3.3: SEARCH HISTORY
// ═══════════════════════════════════════════════════════════════════════════════

/// Search history entry
class SearchHistoryEntry {
  final String query;
  final DateTime timestamp;
  final int resultCount;

  const SearchHistoryEntry({
    required this.query,
    required this.timestamp,
    required this.resultCount,
  });

  Map<String, dynamic> toJson() => {
    'query': query,
    'timestamp': timestamp.toIso8601String(),
    'resultCount': resultCount,
  };

  factory SearchHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SearchHistoryEntry(
      query: json['query'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      resultCount: json['resultCount'] as int? ?? 0,
    );
  }
}

/// Extension for SearchResult to support copyWith
extension SearchResultCopyWith on SearchResult {
  SearchResult copyWith({
    String? id,
    String? title,
    String? subtitle,
    SearchCategory? category,
    String? iconPath,
    double? relevance,
    Map<String, dynamic>? metadata,
    VoidCallback? onSelect,
  }) {
    return SearchResult(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      category: category ?? this.category,
      iconPath: iconPath ?? this.iconPath,
      relevance: relevance ?? this.relevance,
      metadata: metadata ?? this.metadata,
      onSelect: onSelect ?? this.onSelect,
    );
  }
}
