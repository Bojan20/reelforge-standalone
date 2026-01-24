/// Audio Asset Manager — Unified Audio Pool for All Modes
///
/// SINGLE SOURCE OF TRUTH for audio assets across DAW, Middleware, and Slot Lab.
/// All modes share the same assets - changes propagate automatically.
///
/// Features:
/// - Unified storage (one list for all modes)
/// - Automatic sync via ChangeNotifier
/// - Persisted expanded/collapsed folder state
/// - Unified import pipeline
/// - Folder organization by source

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// Unified audio asset representation
class UnifiedAudioAsset {
  final String id;
  final String path;
  final String name;
  final double duration;
  final int sampleRate;
  final int channels;
  final String format;
  final Float32List? waveform;
  final DateTime importedAt;
  final String folder;
  final Map<String, dynamic> metadata;

  const UnifiedAudioAsset({
    required this.id,
    required this.path,
    required this.name,
    required this.duration,
    this.sampleRate = 44100,
    this.channels = 2,
    this.format = 'wav',
    this.waveform,
    required this.importedAt,
    this.folder = 'Audio Pool',
    this.metadata = const {},
  });

  /// Create from file path with metadata from FFI
  static Future<UnifiedAudioAsset> fromPath(
    String path, {
    String? folder,
    NativeFFI? ffi,
  }) async {
    final fileName = path.split('/').last;
    final name = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final ext = fileName.contains('.')
        ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase()
        : 'wav';

    // Try to get metadata from FFI
    double duration = 0.0;
    int sampleRate = 44100;
    int channels = 2;
    Float32List? waveform;

    // FFI is available for future metadata extraction
    // Currently we just use basic file info
    if (ffi != null) {
      // Could use ffi.audioPoolImport(path) to register with engine
      debugPrint('[AudioAssetManager] FFI available for: $path');
    }

    return UnifiedAudioAsset(
      id: '${DateTime.now().millisecondsSinceEpoch}_${path.hashCode}',
      path: path,
      name: name,
      duration: duration,
      sampleRate: sampleRate,
      channels: channels,
      format: ext,
      waveform: waveform,
      importedAt: DateTime.now(),
      folder: folder ?? 'Audio Pool',
    );
  }

  /// Create from JSON (for persistence)
  factory UnifiedAudioAsset.fromJson(Map<String, dynamic> json) {
    return UnifiedAudioAsset(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      path: json['path'] as String,
      name: json['name'] as String? ?? json['path'].toString().split('/').last,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      sampleRate: json['sampleRate'] as int? ?? 44100,
      channels: json['channels'] as int? ?? 2,
      format: json['format'] as String? ?? 'wav',
      waveform: null, // Don't persist waveform
      importedAt: json['importedAt'] != null
          ? DateTime.parse(json['importedAt'] as String)
          : DateTime.now(),
      folder: json['folder'] as String? ?? 'Audio Pool',
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'name': name,
      'duration': duration,
      'sampleRate': sampleRate,
      'channels': channels,
      'format': format,
      'importedAt': importedAt.toIso8601String(),
      'folder': folder,
      'metadata': metadata,
    };
  }

  /// Copy with new values
  UnifiedAudioAsset copyWith({
    String? id,
    String? path,
    String? name,
    double? duration,
    int? sampleRate,
    int? channels,
    String? format,
    Float32List? waveform,
    DateTime? importedAt,
    String? folder,
    Map<String, dynamic>? metadata,
  }) {
    return UnifiedAudioAsset(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      duration: duration ?? this.duration,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      format: format ?? this.format,
      waveform: waveform ?? this.waveform,
      importedAt: importedAt ?? this.importedAt,
      folder: folder ?? this.folder,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Format duration as MM:SS
  String get formattedDuration {
    final minutes = (duration / 60).floor();
    final seconds = (duration % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnifiedAudioAsset &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;
}

/// Audio folder for organization
class AudioFolder {
  final String id;
  final String name;
  final String? parentId;
  final int sortOrder;

  const AudioFolder({
    required this.id,
    required this.name,
    this.parentId,
    this.sortOrder = 0,
  });

  factory AudioFolder.fromJson(Map<String, dynamic> json) {
    return AudioFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      parentId: json['parentId'] as String?,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parentId': parentId,
    'sortOrder': sortOrder,
  };
}

/// Centralized Audio Asset Manager
///
/// SINGLE SOURCE OF TRUTH for all audio assets.
/// Used by DAW, Middleware, and Slot Lab.
class AudioAssetManager extends ChangeNotifier {
  static AudioAssetManager? _instance;
  static AudioAssetManager get instance {
    _instance ??= AudioAssetManager._();
    return _instance!;
  }

  AudioAssetManager._() {
    // Default: all folders expanded
    _ensureDefaultFoldersExpanded();
  }

  /// Reset singleton (for testing)
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }

  /// Ensure all default folders are expanded on startup
  void _ensureDefaultFoldersExpanded() {
    // DAW mode folders
    _expandedFolderIds.add('audio-pool');
    _expandedFolderIds.add('tracks');
    _expandedFolderIds.add('mixconsole');
    _expandedFolderIds.add('markers');
    // Middleware mode folders
    _expandedFolderIds.add('events');
    _expandedFolderIds.add('buses');
    _expandedFolderIds.add('states');
    _expandedFolderIds.add('switches');
    _expandedFolderIds.add('audio-files');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// All audio assets (by path for quick lookup)
  final Map<String, UnifiedAudioAsset> _assets = {};

  /// Custom folders
  final Map<String, AudioFolder> _folders = {};

  /// Expanded folder IDs (persisted)
  final Set<String> _expandedFolderIds = {};

  /// Search query
  String _searchQuery = '';

  /// FFI reference for metadata/waveform
  NativeFFI? _ffi;

  /// Loading state
  bool _isLoading = false;

  /// Currently selected asset path (for action strip operations)
  String? _selectedAssetPath;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// All assets as list
  List<UnifiedAudioAsset> get assets => _assets.values.toList();

  /// All assets count
  int get assetCount => _assets.length;

  /// All folders
  List<AudioFolder> get folders => _folders.values.toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// Expanded folder IDs
  Set<String> get expandedFolderIds => Set.unmodifiable(_expandedFolderIds);

  /// Current search query
  String get searchQuery => _searchQuery;

  /// Is loading
  bool get isLoading => _isLoading;

  /// Currently selected asset path
  String? get selectedAssetPath => _selectedAssetPath;

  /// Select an asset for action strip operations
  void selectAsset(String? path) {
    if (_selectedAssetPath != path) {
      _selectedAssetPath = path;
      notifyListeners();
    }
  }

  /// Get selected asset
  UnifiedAudioAsset? get selectedAsset =>
      _selectedAssetPath != null ? _assets[_selectedAssetPath] : null;

  /// Get unique folder names from assets
  List<String> get folderNames {
    final names = _assets.values.map((a) => a.folder).toSet().toList();
    names.sort();
    return names;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize with FFI reference
  void initialize(NativeFFI ffi) {
    _ffi = ffi;
    debugPrint('[AudioAssetManager] Initialized with FFI');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QUERIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get asset by path
  UnifiedAudioAsset? getByPath(String path) => _assets[path];

  /// Get asset by ID
  UnifiedAudioAsset? getById(String id) {
    return _assets.values.firstWhere(
      (a) => a.id == id,
      orElse: () => throw StateError('Asset not found: $id'),
    );
  }

  /// Get assets in folder
  List<UnifiedAudioAsset> getByFolder(String folder) {
    return _assets.values.where((a) => a.folder == folder).toList();
  }

  /// Search assets by name
  List<UnifiedAudioAsset> search(String query) {
    if (query.isEmpty) return assets;
    final lowerQuery = query.toLowerCase();
    return _assets.values
        .where((a) => a.name.toLowerCase().contains(lowerQuery) ||
                      a.path.toLowerCase().contains(lowerQuery))
        .toList();
  }

  /// Get filtered assets (search + folder)
  List<UnifiedAudioAsset> getFiltered({String? folder, String? query}) {
    var result = _assets.values;

    if (folder != null && folder.isNotEmpty) {
      result = result.where((a) => a.folder == folder);
    }

    if (query != null && query.isNotEmpty) {
      final lowerQuery = query.toLowerCase();
      result = result.where((a) =>
        a.name.toLowerCase().contains(lowerQuery) ||
        a.path.toLowerCase().contains(lowerQuery));
    }

    return result.toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IMPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Import single file
  Future<UnifiedAudioAsset?> importFile(
    String path, {
    String folder = 'Audio Pool',
  }) async {
    // Check if already exists
    if (_assets.containsKey(path)) {
      debugPrint('[AudioAssetManager] Asset already exists: $path');
      return _assets[path];
    }

    try {
      final asset = await UnifiedAudioAsset.fromPath(
        path,
        folder: folder,
        ffi: _ffi,
      );

      _assets[path] = asset;

      // Auto-expand the folder
      _expandedFolderIds.add('folder_$folder');
      _expandedFolderIds.add('audio-pool'); // Root folder

      notifyListeners();
      debugPrint('[AudioAssetManager] Imported: ${asset.name} → $folder');
      return asset;
    } catch (e) {
      debugPrint('[AudioAssetManager] Import failed for $path: $e');
      return null;
    }
  }

  /// Import multiple files
  Future<List<UnifiedAudioAsset>> importFiles(
    List<String> paths, {
    String folder = 'Audio Pool',
  }) async {
    _isLoading = true;
    notifyListeners();

    final imported = <UnifiedAudioAsset>[];

    for (final path in paths) {
      final asset = await importFile(path, folder: folder);
      if (asset != null) {
        imported.add(asset);
      }
    }

    _isLoading = false;

    // Expand all folders after batch import
    expandAllFolders();

    notifyListeners();
    debugPrint('[AudioAssetManager] Batch import: ${imported.length}/${paths.length} files');
    return imported;
  }

  /// Add pre-created asset (for migration from other systems)
  void addAsset(UnifiedAudioAsset asset) {
    if (_assets.containsKey(asset.path)) {
      debugPrint('[AudioAssetManager] Asset already exists: ${asset.path}');
      return;
    }

    _assets[asset.path] = asset;

    // Auto-expand the folder
    _expandedFolderIds.add('folder_${asset.folder}');
    _expandedFolderIds.add('audio-pool');

    notifyListeners();
  }

  /// Add multiple pre-created assets
  void addAssets(List<UnifiedAudioAsset> assets) {
    for (final asset in assets) {
      if (!_assets.containsKey(asset.path)) {
        _assets[asset.path] = asset;
        _expandedFolderIds.add('folder_${asset.folder}');
      }
    }
    _expandedFolderIds.add('audio-pool');
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REMOVE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Remove asset by path
  void removeByPath(String path) {
    if (_assets.remove(path) != null) {
      notifyListeners();
      debugPrint('[AudioAssetManager] Removed: $path');
    }
  }

  /// Remove asset by ID
  void removeById(String id) {
    final path = _assets.entries
        .firstWhere((e) => e.value.id == id, orElse: () => throw StateError('Not found'))
        .key;
    removeByPath(path);
  }

  /// Clear all assets
  void clear() {
    _assets.clear();
    notifyListeners();
    debugPrint('[AudioAssetManager] Cleared all assets');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UPDATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Move asset to folder
  void moveToFolder(String path, String newFolder) {
    final asset = _assets[path];
    if (asset != null) {
      _assets[path] = asset.copyWith(folder: newFolder);
      _expandedFolderIds.add('folder_$newFolder');
      notifyListeners();
    }
  }

  /// Rename asset
  void renameAsset(String path, String newName) {
    final asset = _assets[path];
    if (asset != null) {
      _assets[path] = asset.copyWith(name: newName);
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FOLDER EXPANSION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if folder is expanded
  bool isFolderExpanded(String folderId) => _expandedFolderIds.contains(folderId);

  /// Toggle folder expanded state
  void toggleFolder(String folderId) {
    if (_expandedFolderIds.contains(folderId)) {
      _expandedFolderIds.remove(folderId);
    } else {
      _expandedFolderIds.add(folderId);
    }
    notifyListeners();
  }

  /// Expand folder
  void expandFolder(String folderId) {
    if (_expandedFolderIds.add(folderId)) {
      notifyListeners();
    }
  }

  /// Collapse folder
  void collapseFolder(String folderId) {
    if (_expandedFolderIds.remove(folderId)) {
      notifyListeners();
    }
  }

  /// Expand all folders
  void expandAllFolders() {
    _expandedFolderIds.add('audio-pool');
    for (final folder in folderNames) {
      _expandedFolderIds.add('folder_$folder');
    }
    notifyListeners();
    debugPrint('[AudioAssetManager] Expanded all folders');
  }

  /// Collapse all folders
  void collapseAllFolders() {
    _expandedFolderIds.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEARCH
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set search query
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Clear search
  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PERSISTENCE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'assets': _assets.values.map((a) => a.toJson()).toList(),
      'folders': _folders.values.map((f) => f.toJson()).toList(),
      'expandedFolderIds': _expandedFolderIds.toList(),
    };
  }

  /// Load from JSON
  void loadFromJson(Map<String, dynamic> json) {
    _assets.clear();
    _folders.clear();
    _expandedFolderIds.clear();

    // Load assets
    final assetsList = json['assets'] as List<dynamic>? ?? [];
    for (final assetJson in assetsList) {
      try {
        final asset = UnifiedAudioAsset.fromJson(assetJson as Map<String, dynamic>);
        _assets[asset.path] = asset;
      } catch (e) {
        debugPrint('[AudioAssetManager] Failed to load asset: $e');
      }
    }

    // Load folders
    final foldersList = json['folders'] as List<dynamic>? ?? [];
    for (final folderJson in foldersList) {
      try {
        final folder = AudioFolder.fromJson(folderJson as Map<String, dynamic>);
        _folders[folder.id] = folder;
      } catch (e) {
        debugPrint('[AudioAssetManager] Failed to load folder: $e');
      }
    }

    // Load expanded state
    final expandedList = json['expandedFolderIds'] as List<dynamic>? ?? [];
    _expandedFolderIds.addAll(expandedList.cast<String>());

    notifyListeners();
    debugPrint('[AudioAssetManager] Loaded ${_assets.length} assets, ${_folders.length} folders');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPATIBILITY - Legacy API for existing code
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all assets as simple map list (for SlotLabProvider compatibility)
  List<Map<String, dynamic>> toMapList() {
    return _assets.values.map((a) => a.toJson()).toList();
  }

  /// Add from simple map (for SlotLabProvider compatibility)
  void addFromMap(Map<String, dynamic> map) {
    final asset = UnifiedAudioAsset.fromJson(map);
    addAsset(asset);
  }

  /// Check if asset exists
  bool contains(String path) => _assets.containsKey(path);

  /// Check if asset exists (alias for contains)
  bool hasAsset(String path) => _assets.containsKey(path);

  /// Add asset from PoolAudioFile data (for reverse sync from DAW)
  void addAssetFromPoolFile({
    required String id,
    required String path,
    required String name,
    required double duration,
    required int sampleRate,
    required int channels,
    required String format,
    String folder = 'Audio Pool',
  }) {
    if (_assets.containsKey(path)) return;

    final asset = UnifiedAudioAsset(
      id: id,
      path: path,
      name: name,
      duration: duration,
      sampleRate: sampleRate,
      channels: channels,
      format: format,
      importedAt: DateTime.now(),
      folder: folder,
    );

    _assets[path] = asset;
    _expandedFolderIds.add('folder_$folder');
    _expandedFolderIds.add('audio-pool');

    // Don't call notifyListeners here to avoid infinite loop
    // The caller should handle updates
    debugPrint('[AudioAssetManager] Added from pool file: $name');
  }
}
