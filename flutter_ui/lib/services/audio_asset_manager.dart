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
/// - **INSTANT IMPORT** — Zero-delay UI update with background waveform generation
///
/// Performance Architecture (2026-01-30):
/// - Phase 1: INSTANT — Add to pool immediately with placeholder
/// - Phase 2: BACKGROUND — Generate waveforms asynchronously
/// - Phase 3: NOTIFY — Update UI when waveform ready

import 'dart:async';
import 'dart:convert';
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

  /// Create INSTANT placeholder from file path (NO FFI blocking)
  ///
  /// This creates an asset immediately with basic file info only.
  /// Metadata and waveform are loaded asynchronously via [loadMetadataAsync].
  static UnifiedAudioAsset fromPathInstant(String path, {String? folder}) {
    final fileName = path.split('/').last;
    final name = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final ext = fileName.contains('.')
        ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase()
        : 'wav';

    return UnifiedAudioAsset(
      id: '${DateTime.now().millisecondsSinceEpoch}_${path.hashCode}',
      path: path,
      name: name,
      duration: 0.0,  // Will be populated async
      sampleRate: 44100,
      channels: 2,
      format: ext,
      waveform: null,  // Will be populated async
      importedAt: DateTime.now(),
      folder: folder ?? 'Audio Pool',
      metadata: const {'_pendingMetadata': true},  // Mark as pending
    );
  }

  /// Legacy async method — kept for compatibility but uses instant path internally
  static Future<UnifiedAudioAsset> fromPath(
    String path, {
    String? folder,
    NativeFFI? ffi,
  }) async {
    // Use instant creation — no FFI blocking in import path
    return fromPathInstant(path, folder: folder);
  }

  /// Check if asset is still pending metadata
  bool get isPendingMetadata => metadata['_pendingMetadata'] == true;

  /// Create updated asset with metadata (called from background loader)
  UnifiedAudioAsset withMetadata({
    required double duration,
    required int sampleRate,
    required int channels,
    Float32List? waveform,
  }) {
    final newMetadata = Map<String, dynamic>.from(metadata);
    newMetadata.remove('_pendingMetadata');

    return UnifiedAudioAsset(
      id: id,
      path: path,
      name: name,
      duration: duration,
      sampleRate: sampleRate,
      channels: channels,
      format: format,
      waveform: waveform,
      importedAt: importedAt,
      folder: folder,
      metadata: newMetadata,
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
  // IMPORT — INSTANT (Zero-Delay)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Queue of paths pending background metadata loading
  final List<String> _pendingMetadataQueue = [];

  /// Active background loader
  bool _isBackgroundLoading = false;

  /// Callback when asset metadata is updated (for UI refresh)
  void Function(String path)? onAssetMetadataLoaded;

  /// **INSTANT IMPORT** — Add file to pool immediately, load metadata in background
  ///
  /// This method returns INSTANTLY. The asset appears in the pool immediately
  /// with a placeholder. Metadata and waveform are loaded asynchronously.
  UnifiedAudioAsset? importFileInstant(String path, {String folder = 'Audio Pool'}) {
    // Check if already exists
    if (_assets.containsKey(path)) {
      return _assets[path];
    }

    // Create instant placeholder (NO FFI, NO blocking)
    final asset = UnifiedAudioAsset.fromPathInstant(path, folder: folder);
    _assets[path] = asset;

    // Auto-expand the folder
    _expandedFolderIds.add('folder_$folder');
    _expandedFolderIds.add('audio-pool');

    // Queue for background metadata loading
    _pendingMetadataQueue.add(path);
    _startBackgroundMetadataLoader();

    notifyListeners();
    return asset;
  }

  /// **INSTANT BATCH IMPORT** — Add all files immediately, load metadata in parallel background
  ///
  /// Returns INSTANTLY with all assets in pool. Metadata loads in background.
  List<UnifiedAudioAsset> importFilesInstant(List<String> paths, {String folder = 'Audio Pool'}) {
    final imported = <UnifiedAudioAsset>[];

    for (final path in paths) {
      if (_assets.containsKey(path)) {
        imported.add(_assets[path]!);
        continue;
      }

      final asset = UnifiedAudioAsset.fromPathInstant(path, folder: folder);
      _assets[path] = asset;
      imported.add(asset);

      _expandedFolderIds.add('folder_$folder');
      _pendingMetadataQueue.add(path);
    }

    _expandedFolderIds.add('audio-pool');
    _startBackgroundMetadataLoader();

    notifyListeners();
    return imported;
  }

  /// Start background metadata loader (parallel FFI calls)
  /// P0 PERFORMANCE: Batched notifyListeners to avoid 100+ individual UI rebuilds
  void _startBackgroundMetadataLoader() {
    if (_isBackgroundLoading || _pendingMetadataQueue.isEmpty || _ffi == null) {
      return;
    }

    _isBackgroundLoading = true;

    // P0 FIX: Process in batches and notify ONCE per batch (not per file)
    Future.microtask(() async {
      while (_pendingMetadataQueue.isNotEmpty) {
        // Take up to 10 paths for parallel processing (increased from 5)
        final batch = _pendingMetadataQueue.take(10).toList();
        _pendingMetadataQueue.removeRange(0, batch.length);

        // Process batch in PARALLEL (no notifyListeners per file)
        await Future.wait(batch.map((path) => _loadMetadataForPathSilent(path)));

        // P0 FIX: ONE notifyListeners for entire batch (was doing 1 per file!)
        notifyListeners();
      }

      _isBackgroundLoading = false;
    });
  }

  /// Load metadata for single path WITHOUT notifyListeners (for batched loading)
  Future<void> _loadMetadataForPathSilent(String path) async {
    final asset = _assets[path];
    if (asset == null || !asset.isPendingMetadata) return;

    try {
      // Get metadata from FFI (header only — fast)
      double duration = 0.0;
      int sampleRate = 44100;
      int channels = 2;

      if (_ffi != null) {
        final metadataJson = _ffi!.audioGetMetadata(path);
        if (metadataJson.isNotEmpty) {
          try {
            final metadata = jsonDecode(metadataJson);
            duration = (metadata['duration'] as num?)?.toDouble() ?? 0.0;
            sampleRate = (metadata['sample_rate'] as num?)?.toInt() ?? 44100;
            channels = (metadata['channels'] as num?)?.toInt() ?? 2;
          } catch (_) {
            // Use defaults on parse failure
          }
        }

        // Fallback duration if still 0
        if (duration <= 0.0) {
          final fallbackDuration = _ffi!.getAudioFileDuration(path);
          if (fallbackDuration > 0) {
            duration = fallbackDuration;
          }
        }
      }

      // Update asset with metadata (NO waveform here — that's separate)
      final updatedAsset = asset.withMetadata(
        duration: duration,
        sampleRate: sampleRate,
        channels: channels,
        waveform: null,  // Waveform loaded on-demand by UI
      );

      _assets[path] = updatedAsset;

      // Notify callback if set (silent — no notifyListeners here)
      onAssetMetadataLoaded?.call(path);
    } catch (e) { /* ignored */ }
  }

  /// Load metadata for single path (called in parallel from background loader)
  /// Legacy method - use _loadMetadataForPathSilent for batched operations
  Future<void> _loadMetadataForPath(String path) async {
    await _loadMetadataForPathSilent(path);
    notifyListeners();
  }

  /// Legacy async import — uses instant import internally
  Future<UnifiedAudioAsset?> importFile(
    String path, {
    String folder = 'Audio Pool',
  }) async {
    return importFileInstant(path, folder: folder);
  }

  /// Legacy async batch import — uses instant import internally
  Future<List<UnifiedAudioAsset>> importFiles(
    List<String> paths, {
    String folder = 'Audio Pool',
  }) async {
    return importFilesInstant(paths, folder: folder);
  }

  /// Add pre-created asset (for migration from other systems)
  void addAsset(UnifiedAudioAsset asset) {
    if (_assets.containsKey(asset.path)) {
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
      } catch (e) { /* ignored */ }
    }

    // Load folders
    final foldersList = json['folders'] as List<dynamic>? ?? [];
    for (final folderJson in foldersList) {
      try {
        final folder = AudioFolder.fromJson(folderJson as Map<String, dynamic>);
        _folders[folder.id] = folder;
      } catch (e) { /* ignored */ }
    }

    // Load expanded state
    final expandedList = json['expandedFolderIds'] as List<dynamic>? ?? [];
    _expandedFolderIds.addAll(expandedList.cast<String>());

    notifyListeners();
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
  }
}
