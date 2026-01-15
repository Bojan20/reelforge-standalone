// Plugin Provider
//
// State management for plugin browser and hosting:
// - Plugin scanning and discovery
// - Plugin categorization (VST3, CLAP, AU, LV2)
// - Search and filtering
// - Favorites management
// - Recent plugins
// - Plugin loading/unloading

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// ============ Types ============

/// Plugin format types
enum PluginFormat {
  vst3,
  clap,
  audioUnit,
  lv2,
  internal,
}

/// Plugin categories
enum PluginCategory {
  effect,
  instrument,
  analyzer,
  utility,
}

/// Plugin info model
class PluginInfo {
  final String id;
  final String name;
  final String vendor;
  final PluginFormat format;
  final PluginCategory category;
  final String path;
  final bool hasEditor;
  final int version;
  final bool isFavorite;
  final DateTime? lastUsed;

  const PluginInfo({
    required this.id,
    required this.name,
    required this.vendor,
    required this.format,
    required this.category,
    required this.path,
    this.hasEditor = false,
    this.version = 1,
    this.isFavorite = false,
    this.lastUsed,
  });

  PluginInfo copyWith({
    String? id,
    String? name,
    String? vendor,
    PluginFormat? format,
    PluginCategory? category,
    String? path,
    bool? hasEditor,
    int? version,
    bool? isFavorite,
    DateTime? lastUsed,
  }) {
    return PluginInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      vendor: vendor ?? this.vendor,
      format: format ?? this.format,
      category: category ?? this.category,
      path: path ?? this.path,
      hasEditor: hasEditor ?? this.hasEditor,
      version: version ?? this.version,
      isFavorite: isFavorite ?? this.isFavorite,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }

  /// Get format display name
  String get formatName {
    switch (format) {
      case PluginFormat.vst3:
        return 'VST3';
      case PluginFormat.clap:
        return 'CLAP';
      case PluginFormat.audioUnit:
        return 'AU';
      case PluginFormat.lv2:
        return 'LV2';
      case PluginFormat.internal:
        return 'Internal';
    }
  }

  /// Get category display name
  String get categoryName {
    switch (category) {
      case PluginCategory.effect:
        return 'Effect';
      case PluginCategory.instrument:
        return 'Instrument';
      case PluginCategory.analyzer:
        return 'Analyzer';
      case PluginCategory.utility:
        return 'Utility';
    }
  }
}

/// Scan state
enum ScanState {
  idle,
  scanning,
  complete,
  error,
}

/// Plugin instance (loaded plugin)
class PluginInstance {
  final String instanceId;
  final String pluginId;
  final String name;
  final PluginFormat format;
  final int trackId;
  final int slotIndex;
  final bool hasEditor;
  bool isEditorOpen;
  int? editorWidth;
  int? editorHeight;

  PluginInstance({
    required this.instanceId,
    required this.pluginId,
    required this.name,
    required this.format,
    required this.trackId,
    required this.slotIndex,
    this.hasEditor = false,
    this.isEditorOpen = false,
    this.editorWidth,
    this.editorHeight,
  });

  PluginInstance copyWith({
    bool? isEditorOpen,
    int? editorWidth,
    int? editorHeight,
  }) {
    return PluginInstance(
      instanceId: instanceId,
      pluginId: pluginId,
      name: name,
      format: format,
      trackId: trackId,
      slotIndex: slotIndex,
      hasEditor: hasEditor,
      isEditorOpen: isEditorOpen ?? this.isEditorOpen,
      editorWidth: editorWidth ?? this.editorWidth,
      editorHeight: editorHeight ?? this.editorHeight,
    );
  }
}

// ============ Provider ============

/// Plugin browser and hosting provider
class PluginProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // State
  List<PluginInfo> _plugins = [];
  Set<String> _favorites = {};
  List<String> _recentIds = [];
  ScanState _scanState = ScanState.idle;
  double _scanProgress = 0.0;
  String? _scanError;

  // Instance management
  final Map<String, PluginInstance> _instances = {};

  // Filters
  String _searchQuery = '';
  PluginFormat? _formatFilter;
  PluginCategory? _categoryFilter;
  bool _showFavoritesOnly = false;

  // Getters
  List<PluginInfo> get allPlugins => _plugins;
  ScanState get scanState => _scanState;
  double get scanProgress => _scanProgress;
  String? get scanError => _scanError;
  String get searchQuery => _searchQuery;
  Map<String, PluginInstance> get instances => Map.unmodifiable(_instances);
  int get instanceCount => _instances.length;
  PluginFormat? get formatFilter => _formatFilter;
  PluginCategory? get categoryFilter => _categoryFilter;
  bool get showFavoritesOnly => _showFavoritesOnly;

  /// Get filtered plugins based on current filters
  List<PluginInfo> get filteredPlugins {
    var result = _plugins;

    // Apply favorites filter
    if (_showFavoritesOnly) {
      result = result.where((p) => _favorites.contains(p.id)).toList();
    }

    // Apply format filter
    if (_formatFilter != null) {
      result = result.where((p) => p.format == _formatFilter).toList();
    }

    // Apply category filter
    if (_categoryFilter != null) {
      result = result.where((p) => p.category == _categoryFilter).toList();
    }

    // Apply search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((p) {
        return p.name.toLowerCase().contains(query) ||
            p.vendor.toLowerCase().contains(query);
      }).toList();
    }

    return result;
  }

  /// Get favorite plugins
  List<PluginInfo> get favoritePlugins {
    return _plugins.where((p) => _favorites.contains(p.id)).toList();
  }

  /// Get recent plugins
  List<PluginInfo> get recentPlugins {
    final recent = <PluginInfo>[];
    for (final id in _recentIds) {
      final plugin = _plugins.firstWhere(
        (p) => p.id == id,
        orElse: () => PluginInfo(
          id: '',
          name: '',
          vendor: '',
          format: PluginFormat.vst3,
          category: PluginCategory.effect,
          path: '',
        ),
      );
      if (plugin.id.isNotEmpty) {
        recent.add(plugin);
      }
    }
    return recent;
  }

  /// Get plugins by format
  List<PluginInfo> getByFormat(PluginFormat format) {
    return _plugins.where((p) => p.format == format).toList();
  }

  /// Get plugins by category
  List<PluginInfo> getByCategory(PluginCategory category) {
    return _plugins.where((p) => p.category == category).toList();
  }

  /// Get instruments only
  List<PluginInfo> get instruments {
    return getByCategory(PluginCategory.instrument);
  }

  /// Get effects only
  List<PluginInfo> get effects {
    return getByCategory(PluginCategory.effect);
  }

  /// Plugin count by format
  Map<PluginFormat, int> get countByFormat {
    final counts = <PluginFormat, int>{};
    for (final format in PluginFormat.values) {
      counts[format] = _plugins.where((p) => p.format == format).length;
    }
    return counts;
  }

  /// Plugin count by category
  Map<PluginCategory, int> get countByCategory {
    final counts = <PluginCategory, int>{};
    for (final category in PluginCategory.values) {
      counts[category] = _plugins.where((p) => p.category == category).length;
    }
    return counts;
  }

  PluginProvider({NativeFFI? ffi}) : _ffi = ffi ?? NativeFFI.instance;

  /// Initialize provider
  Future<void> init() async {
    // Load cached plugins first (fast startup)
    await _loadCachedPlugins();
    notifyListeners();
  }

  /// Scan for all plugins
  Future<void> scanPlugins() async {
    if (_scanState == ScanState.scanning) return;

    _scanState = ScanState.scanning;
    _scanProgress = 0.0;
    _scanError = null;
    notifyListeners();

    try {
      // Start scan via FFI
      final count = _ffi.pluginScanAll();

      if (count < 0) {
        _scanState = ScanState.error;
        _scanError = 'Plugin scan failed';
        notifyListeners();
        return;
      }

      // Load discovered plugins
      await _loadPluginsFromFFI();

      _scanState = ScanState.complete;
      _scanProgress = 1.0;
      notifyListeners();

      debugPrint('[PluginProvider] Scan complete: ${_plugins.length} plugins found');
    } catch (e) {
      _scanState = ScanState.error;
      _scanError = e.toString();
      notifyListeners();
    }
  }

  /// Load plugins from FFI
  Future<void> _loadPluginsFromFFI() async {
    final plugins = <PluginInfo>[];
    final nativePlugins = _ffi.pluginGetAll();
    final total = nativePlugins.length;

    for (int i = 0; i < total; i++) {
      final info = nativePlugins[i];
      plugins.add(PluginInfo(
        id: info.id,
        name: info.name,
        vendor: info.vendor,
        format: _convertFormat(info.type),
        category: _convertCategory(info.category),
        path: info.path,
        hasEditor: info.hasEditor,
        isFavorite: _favorites.contains(info.id),
      ));
      _scanProgress = (i + 1) / total;
      if (i % 10 == 0) notifyListeners();
    }

    _plugins = plugins;
  }

  /// Load cached plugins (for fast startup)
  Future<void> _loadCachedPlugins() async {
    // In real implementation, load from local storage
    // For now, just try to load from FFI if already scanned
    final count = _ffi.pluginGetCount();
    if (count > 0) {
      await _loadPluginsFromFFI();
    }
  }

  /// Set search query
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Set format filter
  void setFormatFilter(PluginFormat? format) {
    _formatFilter = format;
    notifyListeners();
  }

  /// Set category filter
  void setCategoryFilter(PluginCategory? category) {
    _categoryFilter = category;
    notifyListeners();
  }

  /// Toggle favorites only filter
  void setShowFavoritesOnly(bool show) {
    _showFavoritesOnly = show;
    notifyListeners();
  }

  /// Clear all filters
  void clearFilters() {
    _searchQuery = '';
    _formatFilter = null;
    _categoryFilter = null;
    _showFavoritesOnly = false;
    notifyListeners();
  }

  /// Toggle favorite status
  void toggleFavorite(String pluginId) {
    if (_favorites.contains(pluginId)) {
      _favorites.remove(pluginId);
    } else {
      _favorites.add(pluginId);
    }
    notifyListeners();
  }

  /// Check if plugin is favorite
  bool isFavorite(String pluginId) {
    return _favorites.contains(pluginId);
  }

  /// Add to recent plugins
  void addToRecent(String pluginId) {
    _recentIds.remove(pluginId);
    _recentIds.insert(0, pluginId);
    // Keep only last 20
    if (_recentIds.length > 20) {
      _recentIds = _recentIds.sublist(0, 20);
    }
    notifyListeners();
  }

  /// Load plugin into slot
  Future<String?> loadPlugin(String pluginId, int trackId, int slotIndex) async {
    final instanceId = _ffi.pluginLoad(pluginId);
    if (instanceId != null) {
      addToRecent(pluginId);

      // Find plugin info
      final pluginInfo = _plugins.firstWhere(
        (p) => p.id == pluginId,
        orElse: () => PluginInfo(
          id: pluginId,
          name: 'Unknown Plugin',
          vendor: '',
          format: PluginFormat.internal,
          category: PluginCategory.effect,
          path: '',
        ),
      );

      // Create instance
      final instance = PluginInstance(
        instanceId: instanceId,
        pluginId: pluginId,
        name: pluginInfo.name,
        format: pluginInfo.format,
        trackId: trackId,
        slotIndex: slotIndex,
        hasEditor: pluginInfo.hasEditor,
      );

      _instances[instanceId] = instance;

      // Activate plugin
      _ffi.pluginActivate(instanceId);

      notifyListeners();
    }
    return instanceId;
  }

  /// Unload plugin
  Future<bool> unloadPlugin(String instanceId) async {
    final instance = _instances[instanceId];
    if (instance == null) return false;

    // Close editor if open
    if (instance.isEditorOpen) {
      closeEditor(instanceId);
    }

    // Deactivate first
    _ffi.pluginDeactivate(instanceId);

    // Unload
    final success = _ffi.pluginUnload(instanceId);
    if (success) {
      _instances.remove(instanceId);
      notifyListeners();
    }
    return success;
  }

  /// Get plugin instance by ID
  PluginInstance? getInstance(String instanceId) {
    return _instances[instanceId];
  }

  /// Get instances for a track
  List<PluginInstance> getInstancesForTrack(int trackId) {
    return _instances.values
        .where((i) => i.trackId == trackId)
        .toList()
      ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
  }

  /// Open plugin editor
  Future<bool> openEditor(String instanceId, {int parentWindow = 0}) async {
    final instance = _instances[instanceId];
    if (instance == null || !instance.hasEditor) return false;

    final success = _ffi.pluginOpenEditor(instanceId, parentWindow);
    if (success) {
      // Get editor size
      final size = _ffi.pluginEditorSize(instanceId);

      _instances[instanceId] = instance.copyWith(
        isEditorOpen: true,
        editorWidth: size?.$1,
        editorHeight: size?.$2,
      );
      notifyListeners();
    }
    return success;
  }

  /// Close plugin editor
  Future<bool> closeEditor(String instanceId) async {
    final instance = _instances[instanceId];
    if (instance == null) return false;

    final success = _ffi.pluginCloseEditor(instanceId);
    if (success) {
      _instances[instanceId] = instance.copyWith(isEditorOpen: false);
      notifyListeners();
    }
    return success;
  }

  /// Resize plugin editor
  Future<bool> resizeEditor(String instanceId, int width, int height) async {
    final instance = _instances[instanceId];
    if (instance == null || !instance.isEditorOpen) return false;

    final success = _ffi.pluginResizeEditor(instanceId, width, height);
    if (success) {
      _instances[instanceId] = instance.copyWith(
        editorWidth: width,
        editorHeight: height,
      );
      notifyListeners();
    }
    return success;
  }

  /// Get plugin parameter value
  double getPluginParam(String instanceId, int paramId) {
    return _ffi.pluginGetParam(instanceId, paramId);
  }

  /// Set plugin parameter value
  bool setPluginParam(String instanceId, int paramId, double value) {
    return _ffi.pluginSetParam(instanceId, paramId, value);
  }

  /// Get all plugin parameters
  List<NativePluginParamInfo> getPluginParams(String instanceId) {
    return _ffi.pluginGetAllParams(instanceId);
  }

  /// Save plugin preset
  Future<bool> savePluginPreset(String instanceId, String path, String name) async {
    return _ffi.pluginSavePreset(instanceId, path, name);
  }

  /// Load plugin preset
  Future<bool> loadPluginPreset(String instanceId, String path) async {
    return _ffi.pluginLoadPreset(instanceId, path);
  }

  /// Get plugin latency
  int getPluginLatency(String instanceId) {
    return _ffi.pluginGetLatency(instanceId);
  }

  // ============ INSERT CHAIN ============

  /// Load plugin into channel insert chain
  /// Returns true if command was queued successfully
  bool loadPluginToInsertChain(int channelId, String pluginId) {
    final result = _ffi.pluginInsertLoad(channelId, pluginId);
    if (result == 1) {
      // Track usage
      _recordPluginUsage(pluginId);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Remove plugin from insert chain at slot
  bool removePluginFromInsertChain(int channelId, int slotIndex) {
    return _ffi.pluginInsertRemove(channelId, slotIndex) == 1;
  }

  /// Set bypass state for insert slot
  bool setInsertBypass(int channelId, int slotIndex, bool bypass) {
    return _ffi.pluginInsertSetBypass(channelId, slotIndex, bypass) == 1;
  }

  /// Set wet/dry mix for insert slot
  bool setInsertMix(int channelId, int slotIndex, double mix) {
    return _ffi.pluginInsertSetMix(channelId, slotIndex, mix.clamp(0.0, 1.0)) == 1;
  }

  /// Get wet/dry mix for insert slot
  double getInsertMix(int channelId, int slotIndex) {
    return _ffi.pluginInsertGetMix(channelId, slotIndex);
  }

  /// Get latency for specific insert slot
  int getInsertLatency(int channelId, int slotIndex) {
    return _ffi.pluginInsertGetLatency(channelId, slotIndex);
  }

  /// Get total latency for entire insert chain
  int getInsertChainLatency(int channelId) {
    return _ffi.pluginInsertChainLatency(channelId);
  }

  /// Record plugin usage for "recent" list
  void _recordPluginUsage(String pluginId) {
    // Find plugin and mark as recently used
    final idx = _plugins.indexWhere((p) => p.id == pluginId);
    if (idx != -1) {
      final plugin = _plugins[idx];
      _plugins[idx] = plugin.copyWith(lastUsed: DateTime.now());

      // Update recent list
      _recentIds.remove(pluginId);
      _recentIds.insert(0, pluginId);
      if (_recentIds.length > 20) {
        _recentIds.removeLast();
      }
    }
  }

  /// Convert FFI format to enum
  PluginFormat _convertFormat(NativePluginType type) {
    switch (type) {
      case NativePluginType.vst3:
        return PluginFormat.vst3;
      case NativePluginType.clap:
        return PluginFormat.clap;
      case NativePluginType.audioUnit:
        return PluginFormat.audioUnit;
      case NativePluginType.lv2:
        return PluginFormat.lv2;
      case NativePluginType.internal:
        return PluginFormat.internal;
    }
  }

  /// Convert FFI category to enum
  PluginCategory _convertCategory(NativePluginCategory category) {
    switch (category) {
      case NativePluginCategory.effect:
        return PluginCategory.effect;
      case NativePluginCategory.instrument:
        return PluginCategory.instrument;
      case NativePluginCategory.analyzer:
        return PluginCategory.analyzer;
      case NativePluginCategory.utility:
      case NativePluginCategory.unknown:
        return PluginCategory.utility;
    }
  }
}

// ============ Plugin Browser Widget State ============

/// State for plugin browser dialog/panel
class PluginBrowserState {
  final String searchQuery;
  final PluginFormat? formatFilter;
  final PluginCategory? categoryFilter;
  final bool showFavoritesOnly;
  final String? selectedPluginId;
  final bool isExpanded;

  const PluginBrowserState({
    this.searchQuery = '',
    this.formatFilter,
    this.categoryFilter,
    this.showFavoritesOnly = false,
    this.selectedPluginId,
    this.isExpanded = false,
  });

  PluginBrowserState copyWith({
    String? searchQuery,
    PluginFormat? formatFilter,
    PluginCategory? categoryFilter,
    bool? showFavoritesOnly,
    String? selectedPluginId,
    bool? isExpanded,
  }) {
    return PluginBrowserState(
      searchQuery: searchQuery ?? this.searchQuery,
      formatFilter: formatFilter ?? this.formatFilter,
      categoryFilter: categoryFilter ?? this.categoryFilter,
      showFavoritesOnly: showFavoritesOnly ?? this.showFavoritesOnly,
      selectedPluginId: selectedPluginId ?? this.selectedPluginId,
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }
}
