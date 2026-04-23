// ============================================================================
// P3-06: Asset Library Cloud Service — Cloud Storage for Audio Assets
// FluxForge Studio — Cloud-based audio asset management
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// ENUMS
// ============================================================================

/// Cloud storage provider
enum AssetCloudProvider {
  fluxforge, // FluxForge Cloud (default)
  aws, // Amazon S3
  gcs, // Google Cloud Storage
  azure, // Azure Blob Storage
  dropbox, // Dropbox
  custom; // Custom S3-compatible

  String get displayName {
    switch (this) {
      case AssetCloudProvider.fluxforge:
        return 'FluxForge Cloud';
      case AssetCloudProvider.aws:
        return 'Amazon S3';
      case AssetCloudProvider.gcs:
        return 'Google Cloud Storage';
      case AssetCloudProvider.azure:
        return 'Azure Blob Storage';
      case AssetCloudProvider.dropbox:
        return 'Dropbox';
      case AssetCloudProvider.custom:
        return 'Custom Storage';
    }
  }
}

/// Asset category for organization
enum AssetCategory {
  sfx,
  music,
  voiceover,
  ambience,
  foley,
  ui,
  slot,
  custom;

  String get displayName {
    switch (this) {
      case AssetCategory.sfx:
        return 'Sound Effects';
      case AssetCategory.music:
        return 'Music';
      case AssetCategory.voiceover:
        return 'Voiceover';
      case AssetCategory.ambience:
        return 'Ambience';
      case AssetCategory.foley:
        return 'Foley';
      case AssetCategory.ui:
        return 'UI Sounds';
      case AssetCategory.slot:
        return 'Slot Game Audio';
      case AssetCategory.custom:
        return 'Custom';
    }
  }

  String get emoji {
    switch (this) {
      case AssetCategory.sfx:
        return '💥';
      case AssetCategory.music:
        return '🎵';
      case AssetCategory.voiceover:
        return '🎤';
      case AssetCategory.ambience:
        return '🌊';
      case AssetCategory.foley:
        return '👣';
      case AssetCategory.ui:
        return '🖱️';
      case AssetCategory.slot:
        return '🎰';
      case AssetCategory.custom:
        return '📁';
    }
  }
}

/// Asset license type
enum AssetLicense {
  free, // Free to use
  royaltyFree, // Royalty-free (one-time purchase)
  subscription, // Subscription-based
  exclusive, // Exclusive license
  custom; // Custom licensing

  String get displayName {
    switch (this) {
      case AssetLicense.free:
        return 'Free';
      case AssetLicense.royaltyFree:
        return 'Royalty-Free';
      case AssetLicense.subscription:
        return 'Subscription';
      case AssetLicense.exclusive:
        return 'Exclusive';
      case AssetLicense.custom:
        return 'Custom';
    }
  }
}

/// Upload/download status
enum AssetTransferStatus {
  pending,
  inProgress,
  completed,
  failed,
  cancelled;
}

// ============================================================================
// MODELS
// ============================================================================

/// Cloud audio asset metadata
class CloudAsset {
  final String id;
  final String name;
  final String? description;
  final AssetCategory category;
  final List<String> tags;
  final String format; // wav, mp3, ogg, flac
  final int sizeBytes;
  final double durationSeconds;
  final int sampleRate;
  final int channels;
  final int bitDepth;
  final String cloudUrl;
  final String? thumbnailUrl;
  final String? waveformUrl;
  final String checksum;
  final String uploaderId;
  final String uploaderName;
  final DateTime uploadedAt;
  final DateTime? updatedAt;
  final AssetLicense license;
  final int downloadCount;
  final double rating;
  final int ratingCount;
  final bool isPublic;
  final List<String> collections;

  const CloudAsset({
    required this.id,
    required this.name,
    this.description,
    required this.category,
    this.tags = const [],
    required this.format,
    required this.sizeBytes,
    required this.durationSeconds,
    required this.sampleRate,
    required this.channels,
    required this.bitDepth,
    required this.cloudUrl,
    this.thumbnailUrl,
    this.waveformUrl,
    required this.checksum,
    required this.uploaderId,
    required this.uploaderName,
    required this.uploadedAt,
    this.updatedAt,
    this.license = AssetLicense.royaltyFree,
    this.downloadCount = 0,
    this.rating = 0.0,
    this.ratingCount = 0,
    this.isPublic = true,
    this.collections = const [],
  });

  factory CloudAsset.fromJson(Map<String, dynamic> json) {
    return CloudAsset(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      category: AssetCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => AssetCategory.custom,
      ),
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      format: json['format'] as String,
      sizeBytes: json['sizeBytes'] as int,
      durationSeconds: (json['durationSeconds'] as num).toDouble(),
      sampleRate: json['sampleRate'] as int,
      channels: json['channels'] as int,
      bitDepth: json['bitDepth'] as int,
      cloudUrl: json['cloudUrl'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      waveformUrl: json['waveformUrl'] as String?,
      checksum: json['checksum'] as String,
      uploaderId: json['uploaderId'] as String,
      uploaderName: json['uploaderName'] as String,
      uploadedAt: DateTime.parse(json['uploadedAt'] as String),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      license: AssetLicense.values.firstWhere(
        (l) => l.name == json['license'],
        orElse: () => AssetLicense.royaltyFree,
      ),
      downloadCount: json['downloadCount'] as int? ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: json['ratingCount'] as int? ?? 0,
      isPublic: json['isPublic'] as bool? ?? true,
      collections: (json['collections'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category.name,
        'tags': tags,
        'format': format,
        'sizeBytes': sizeBytes,
        'durationSeconds': durationSeconds,
        'sampleRate': sampleRate,
        'channels': channels,
        'bitDepth': bitDepth,
        'cloudUrl': cloudUrl,
        'thumbnailUrl': thumbnailUrl,
        'waveformUrl': waveformUrl,
        'checksum': checksum,
        'uploaderId': uploaderId,
        'uploaderName': uploaderName,
        'uploadedAt': uploadedAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'license': license.name,
        'downloadCount': downloadCount,
        'rating': rating,
        'ratingCount': ratingCount,
        'isPublic': isPublic,
        'collections': collections,
      };

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedDuration {
    final mins = (durationSeconds / 60).floor();
    final secs = (durationSeconds % 60).floor();
    final ms = ((durationSeconds % 1) * 1000).round();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }

  String get formatInfo {
    final stereoMono = channels == 1 ? 'Mono' : (channels == 2 ? 'Stereo' : '${channels}ch');
    return '${format.toUpperCase()} • $stereoMono • ${sampleRate}Hz • ${bitDepth}bit';
  }
}

/// Asset collection/folder
class AssetCollection {
  final String id;
  final String name;
  final String? description;
  final String ownerId;
  final String ownerName;
  final String? coverImageUrl;
  final int assetCount;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isPublic;
  final List<String> tags;

  const AssetCollection({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    required this.ownerName,
    this.coverImageUrl,
    this.assetCount = 0,
    required this.createdAt,
    this.updatedAt,
    this.isPublic = false,
    this.tags = const [],
  });

  factory AssetCollection.fromJson(Map<String, dynamic> json) {
    return AssetCollection(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      ownerId: json['ownerId'] as String,
      ownerName: json['ownerName'] as String,
      coverImageUrl: json['coverImageUrl'] as String?,
      assetCount: json['assetCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      isPublic: json['isPublic'] as bool? ?? false,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'ownerId': ownerId,
        'ownerName': ownerName,
        'coverImageUrl': coverImageUrl,
        'assetCount': assetCount,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'isPublic': isPublic,
        'tags': tags,
      };
}

/// Asset transfer (upload/download) tracking
class AssetTransfer {
  final String id;
  final String assetId;
  final String fileName;
  final bool isUpload;
  final int totalBytes;
  final int transferredBytes;
  final AssetTransferStatus status;
  final String? errorMessage;
  final DateTime startedAt;
  final DateTime? completedAt;

  const AssetTransfer({
    required this.id,
    required this.assetId,
    required this.fileName,
    required this.isUpload,
    required this.totalBytes,
    this.transferredBytes = 0,
    this.status = AssetTransferStatus.pending,
    this.errorMessage,
    required this.startedAt,
    this.completedAt,
  });

  double get progress => totalBytes > 0 ? transferredBytes / totalBytes : 0.0;

  AssetTransfer copyWith({
    int? transferredBytes,
    AssetTransferStatus? status,
    String? errorMessage,
    DateTime? completedAt,
  }) {
    return AssetTransfer(
      id: id,
      assetId: assetId,
      fileName: fileName,
      isUpload: isUpload,
      totalBytes: totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

/// Search filters for cloud assets
class AssetSearchFilters {
  final String? query;
  final AssetCategory? category;
  final List<String> tags;
  final AssetLicense? license;
  final double? minDuration;
  final double? maxDuration;
  final int? minSampleRate;
  final List<String> formats;
  final bool? stereoOnly;
  final String? sortBy; // name, date, rating, downloads
  final bool ascending;

  const AssetSearchFilters({
    this.query,
    this.category,
    this.tags = const [],
    this.license,
    this.minDuration,
    this.maxDuration,
    this.minSampleRate,
    this.formats = const [],
    this.stereoOnly,
    this.sortBy,
    this.ascending = false,
  });

  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{};
    if (query != null && query!.isNotEmpty) params['q'] = query;
    if (category != null) params['category'] = category!.name;
    if (tags.isNotEmpty) params['tags'] = tags.join(',');
    if (license != null) params['license'] = license!.name;
    if (minDuration != null) params['minDuration'] = minDuration;
    if (maxDuration != null) params['maxDuration'] = maxDuration;
    if (minSampleRate != null) params['minSampleRate'] = minSampleRate;
    if (formats.isNotEmpty) params['formats'] = formats.join(',');
    if (stereoOnly != null) params['stereo'] = stereoOnly;
    if (sortBy != null) params['sortBy'] = sortBy;
    params['asc'] = ascending;
    return params;
  }
}

/// Search results with pagination
class AssetSearchResults {
  final List<CloudAsset> assets;
  final int totalCount;
  final int page;
  final int pageSize;
  final bool hasMore;

  const AssetSearchResults({
    required this.assets,
    required this.totalCount,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  factory AssetSearchResults.fromJson(Map<String, dynamic> json) {
    return AssetSearchResults(
      assets: (json['assets'] as List<dynamic>)
          .map((a) => CloudAsset.fromJson(a as Map<String, dynamic>))
          .toList(),
      totalCount: json['totalCount'] as int,
      page: json['page'] as int,
      pageSize: json['pageSize'] as int,
      hasMore: json['hasMore'] as bool,
    );
  }
}

// ============================================================================
// ASSET CLOUD SERVICE
// ============================================================================

/// Cloud storage service for audio assets
class AssetCloudService extends ChangeNotifier {
  // Singleton
  static final AssetCloudService _instance = AssetCloudService._();
  static AssetCloudService get instance => _instance;
  AssetCloudService._();

  // State
  AssetCloudProvider _provider = AssetCloudProvider.fluxforge;
  bool _isAuthenticated = false;
  String? _userId;
  String? _userName;
  String? _authToken;
  String? _lastError;

  // Cache
  final Map<String, CloudAsset> _assetCache = {};
  final Map<String, AssetCollection> _collectionCache = {};
  final List<AssetTransfer> _activeTransfers = [];
  List<CloudAsset> _recentAssets = [];
  List<CloudAsset> _favoriteAssets = [];

  // Configuration
  static const String _prefsKey = 'asset_cloud_config';
  String _apiBaseUrl = 'https://api.fluxforge.io/assets';
  String _cdnBaseUrl = 'https://cdn.fluxforge.io';
  int _maxConcurrentTransfers = 3;
  String _cacheDir = '';

  // Streams
  final StreamController<AssetTransfer> _transferController =
      StreamController<AssetTransfer>.broadcast();

  // Getters
  AssetCloudProvider get provider => _provider;
  bool get isAuthenticated => _isAuthenticated;
  String? get userId => _userId;
  String? get userName => _userName;
  String? get lastError => _lastError;
  List<AssetTransfer> get activeTransfers => List.unmodifiable(_activeTransfers);
  List<CloudAsset> get recentAssets => List.unmodifiable(_recentAssets);
  List<CloudAsset> get favoriteAssets => List.unmodifiable(_favoriteAssets);
  Stream<AssetTransfer> get transferStream => _transferController.stream;

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  /// Initialize asset cloud service
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_prefsKey);

      if (configJson != null) {
        final config = jsonDecode(configJson) as Map<String, dynamic>;
        _provider = AssetCloudProvider.values.firstWhere(
          (p) => p.name == config['provider'],
          orElse: () => AssetCloudProvider.fluxforge,
        );
        _apiBaseUrl = config['apiBaseUrl'] as String? ?? _apiBaseUrl;
        _cdnBaseUrl = config['cdnBaseUrl'] as String? ?? _cdnBaseUrl;
        _authToken = config['authToken'] as String?;
        _userId = config['userId'] as String?;
        _userName = config['userName'] as String?;
        _isAuthenticated = _authToken != null;

        // Load cached favorites
        final favoritesJson = config['favorites'] as List<dynamic>?;
        if (favoritesJson != null) {
          _favoriteAssets = favoritesJson
              .map((f) => CloudAsset.fromJson(f as Map<String, dynamic>))
              .toList();
        }
      }

      // Setup cache directory
      _cacheDir = path.join(Directory.systemTemp.path, 'fluxforge_asset_cache');
      await Directory(_cacheDir).create(recursive: true);

    } catch (e) { /* ignored */ }
  }

  /// Save configuration
  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          'provider': _provider.name,
          'apiBaseUrl': _apiBaseUrl,
          'cdnBaseUrl': _cdnBaseUrl,
          'authToken': _authToken,
          'userId': _userId,
          'userName': _userName,
          'favorites': _favoriteAssets.map((f) => f.toJson()).toList(),
        }),
      );
    } catch (e) { /* ignored */ }
  }

  // ============================================================================
  // AUTHENTICATION
  // ============================================================================

  /// Build auth headers for API calls
  Map<String, String> _authHeadersAsset() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  /// Authenticate with cloud asset service
  Future<bool> authenticate({
    required String email,
    required String password,
  }) async {
    try {
      _lastError = null;

      if (_apiBaseUrl.isEmpty) {
        // Fallback: use email hash for offline/unconfigured mode
        _authToken = null;
        _userId = 'user_${email.hashCode.abs()}';
        _userName = email.split('@').first;
        _isAuthenticated = true;
      } else {
        final response = await http.post(
          Uri.parse('$_apiBaseUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          _authToken = data['token'] as String? ?? data['access_token'] as String?;
          _userId = data['userId'] as String? ?? data['user_id'] as String?;
          _userName = data['name'] as String? ?? email.split('@').first;
          _userId ??= 'user_${email.hashCode.abs()}';
          _isAuthenticated = true;
        } else {
          throw Exception('Auth failed: ${response.statusCode}');
        }
      }

      await _saveConfig();
      notifyListeners();

      return true;
    } on TimeoutException {
      _lastError = 'Authentication timed out';
      notifyListeners();
      return false;
    } on SocketException catch (e) {
      _lastError = 'Cannot reach server: ${e.message}';
      notifyListeners();
      return false;
    } catch (e) {
      _lastError = 'Authentication failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Logout from cloud service
  Future<void> logout() async {
    _authToken = null;
    _userId = null;
    _userName = null;
    _isAuthenticated = false;
    _assetCache.clear();
    _collectionCache.clear();
    _recentAssets.clear();

    await _saveConfig();
    notifyListeners();
  }

  // ============================================================================
  // ASSET SEARCH & BROWSE
  // ============================================================================

  /// Search for assets via cloud API
  Future<AssetSearchResults> searchAssets({
    AssetSearchFilters filters = const AssetSearchFilters(),
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      _lastError = null;

      if (_apiBaseUrl.isEmpty) {
        // No API configured — return empty results
        return const AssetSearchResults(
          assets: [], totalCount: 0, page: 1, pageSize: 20, hasMore: false,
        );
      }

      // Build query parameters
      final queryParams = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (filters.query != null && filters.query!.isNotEmpty) {
        queryParams['q'] = filters.query!;
      }
      if (filters.category != null) {
        queryParams['category'] = filters.category!.name;
      }

      final uri = Uri.parse('$_apiBaseUrl/assets/search').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: _authHeadersAsset())
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final assetsList = (data['assets'] as List<dynamic>?)
            ?.map((a) => CloudAsset.fromJson(a as Map<String, dynamic>))
            .toList() ?? [];

        return AssetSearchResults(
          assets: assetsList,
          totalCount: data['totalCount'] as int? ?? assetsList.length,
          page: page,
          pageSize: pageSize,
          hasMore: data['hasMore'] as bool? ?? false,
        );
      } else {
        throw Exception('Search failed: ${response.statusCode}');
      }
    } on TimeoutException {
      _lastError = 'Search timed out';
      notifyListeners();
      return const AssetSearchResults(
        assets: [], totalCount: 0, page: 1, pageSize: 20, hasMore: false,
      );
    } catch (e) {
      _lastError = 'Search failed: $e';
      notifyListeners();
      return const AssetSearchResults(
        assets: [], totalCount: 0, page: 1, pageSize: 20, hasMore: false,
      );
    }
  }

  /// Get asset by ID
  Future<CloudAsset?> getAsset(String assetId) async {
    // Check cache first
    if (_assetCache.containsKey(assetId)) {
      return _assetCache[assetId];
    }

    try {
      if (_apiBaseUrl.isEmpty) return null;

      final response = await http.get(
        Uri.parse('$_apiBaseUrl/assets/$assetId'),
        headers: _authHeadersAsset(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final asset = CloudAsset.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
        _assetCache[assetId] = asset;
        return asset;
      }
      return null;
    } catch (e) {
      _lastError = 'Failed to get asset: $e';
      return null;
    }
  }

  /// Get featured/trending assets
  Future<List<CloudAsset>> getFeaturedAssets() async {
    try {
      if (_apiBaseUrl.isEmpty) return [];

      final response = await http.get(
        Uri.parse('$_apiBaseUrl/assets/featured'),
        headers: _authHeadersAsset(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data is List) ? data : (data['assets'] as List<dynamic>? ?? []);
        return list.map((a) => CloudAsset.fromJson(a as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get assets by category
  Future<List<CloudAsset>> getAssetsByCategory(AssetCategory category) async {
    return (await searchAssets(
      filters: AssetSearchFilters(category: category),
      pageSize: 50,
    ))
        .assets;
  }

  // ============================================================================
  // COLLECTIONS
  // ============================================================================

  /// Get user's collections
  Future<List<AssetCollection>> getMyCollections() async {
    if (!_isAuthenticated) return [];

    try {
      if (_apiBaseUrl.isEmpty) return [];

      final response = await http.get(
        Uri.parse('$_apiBaseUrl/collections'),
        headers: _authHeadersAsset(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        return list.map((c) => AssetCollection.fromJson(c as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get assets in a collection
  Future<List<CloudAsset>> getCollectionAssets(String collectionId) async {
    try {
      if (_apiBaseUrl.isEmpty) return [];

      final response = await http.get(
        Uri.parse('$_apiBaseUrl/collections/$collectionId/assets'),
        headers: _authHeadersAsset(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data is List) ? data : (data['assets'] as List<dynamic>? ?? []);
        return list.map((a) => CloudAsset.fromJson(a as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Create a new collection
  Future<AssetCollection?> createCollection({
    required String name,
    String? description,
    bool isPublic = false,
  }) async {
    if (!_isAuthenticated) return null;

    try {
      AssetCollection collection;

      if (_apiBaseUrl.isNotEmpty) {
        final response = await http.post(
          Uri.parse('$_apiBaseUrl/collections'),
          headers: _authHeadersAsset(),
          body: jsonEncode({
            'name': name,
            'description': description,
            'isPublic': isPublic,
          }),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200 || response.statusCode == 201) {
          collection = AssetCollection.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
        } else {
          throw Exception('Create collection failed: ${response.statusCode}');
        }
      } else {
        collection = AssetCollection(
          id: 'col_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          description: description,
          ownerId: _userId!,
          ownerName: _userName!,
          createdAt: DateTime.now(),
          isPublic: isPublic,
        );
      }

      _collectionCache[collection.id] = collection;
      notifyListeners();
      return collection;
    } catch (e) {
      _lastError = 'Failed to create collection: $e';
      return null;
    }
  }

  /// Add asset to collection
  Future<bool> addToCollection(String assetId, String collectionId) async {
    if (!_isAuthenticated) return false;

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/collections/$collectionId/assets'),
        headers: {
          ..._authHeadersAsset(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'asset_id': assetId}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200 && response.statusCode != 201) {
        _lastError = 'Failed to add to collection: ${response.statusCode}';
        return false;
      }

      // Update local cache — reconstruct with incremented count
      final cached = _collectionCache[collectionId];
      if (cached != null) {
        _collectionCache[collectionId] = AssetCollection(
          id: cached.id,
          name: cached.name,
          description: cached.description,
          ownerId: cached.ownerId,
          ownerName: cached.ownerName,
          coverImageUrl: cached.coverImageUrl,
          assetCount: cached.assetCount + 1,
          createdAt: cached.createdAt,
          updatedAt: cached.updatedAt,
          isPublic: cached.isPublic,
          tags: cached.tags,
        );
      }

      notifyListeners();
      return true;
    } on TimeoutException {
      _lastError = 'Request timed out';
      return false;
    } on SocketException {
      _lastError = 'No network connection';
      return false;
    } catch (e) {
      _lastError = 'Failed to add to collection: $e';
      return false;
    }
  }

  // ============================================================================
  // FAVORITES
  // ============================================================================

  /// Toggle favorite status
  Future<bool> toggleFavorite(CloudAsset asset) async {
    final isFavorite = _favoriteAssets.any((f) => f.id == asset.id);

    if (isFavorite) {
      _favoriteAssets.removeWhere((f) => f.id == asset.id);
    } else {
      _favoriteAssets.add(asset);
    }

    await _saveConfig();
    notifyListeners();
    return !isFavorite;
  }

  /// Check if asset is favorited
  bool isFavorite(String assetId) {
    return _favoriteAssets.any((f) => f.id == assetId);
  }

  // ============================================================================
  // UPLOAD
  // ============================================================================

  /// Upload an audio file to cloud
  Future<CloudAsset?> uploadAsset({
    required String filePath,
    required String name,
    AssetCategory category = AssetCategory.sfx,
    String? description,
    List<String> tags = const [],
    AssetLicense license = AssetLicense.royaltyFree,
    bool isPublic = true,
    void Function(double progress)? onProgress,
  }) async {
    if (!_isAuthenticated) {
      _lastError = 'Not authenticated';
      return null;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      _lastError = 'File not found';
      return null;
    }

    final fileSize = await file.length();
    final fileName = path.basename(filePath);
    final format = path.extension(filePath).toLowerCase().replaceFirst('.', '');
    final assetId = 'asset_${DateTime.now().millisecondsSinceEpoch}';

    // Create transfer tracking
    final transfer = AssetTransfer(
      id: 'transfer_${DateTime.now().millisecondsSinceEpoch}',
      assetId: assetId,
      fileName: fileName,
      isUpload: true,
      totalBytes: fileSize,
      startedAt: DateTime.now(),
    );

    _activeTransfers.add(transfer);
    _transferController.add(transfer);
    notifyListeners();

    try {
      // Calculate checksum
      final bytes = await file.readAsBytes();
      final checksum = md5.convert(bytes).toString();

      // Upload file to server
      if (_apiBaseUrl.isNotEmpty) {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$_apiBaseUrl/assets/upload'),
        );
        request.headers.addAll(_authHeadersAsset());
        request.fields['name'] = name;
        if (description != null) request.fields['description'] = description;
        request.fields['category'] = category.name;
        request.fields['tags'] = tags.join(',');
        request.fields['license'] = license.name;
        request.fields['isPublic'] = isPublic.toString();
        request.files.add(await http.MultipartFile.fromPath('file', filePath));

        final streamedResponse = await request.send()
            .timeout(const Duration(seconds: 120));

        // Track progress via response
        final responseBytes = await streamedResponse.stream.toBytes();
        if (streamedResponse.statusCode != 200 && streamedResponse.statusCode != 201) {
          throw Exception('Upload failed: ${streamedResponse.statusCode} ${String.fromCharCodes(responseBytes)}');
        }

        // Update transfer progress
        final updatedTransfer = transfer.copyWith(
          transferredBytes: fileSize,
          status: AssetTransferStatus.inProgress,
        );
        _updateTransfer(updatedTransfer);
        onProgress?.call(1.0);
      } else {
        // No API — just mark as done (local-only mode)
        final updatedTransfer = transfer.copyWith(
          transferredBytes: fileSize,
          status: AssetTransferStatus.inProgress,
        );
        _updateTransfer(updatedTransfer);
        onProgress?.call(1.0);
      }

      // Create asset
      final asset = CloudAsset(
        id: assetId,
        name: name,
        description: description,
        category: category,
        tags: tags,
        format: format,
        sizeBytes: fileSize,
        durationSeconds: 5.0, // Would be extracted from file
        sampleRate: 44100,
        channels: 2,
        bitDepth: 24,
        cloudUrl: '$_cdnBaseUrl/assets/$assetId.$format',
        checksum: checksum,
        uploaderId: _userId!,
        uploaderName: _userName!,
        uploadedAt: DateTime.now(),
        license: license,
        isPublic: isPublic,
      );

      // Mark transfer complete
      final completedTransfer = transfer.copyWith(
        transferredBytes: fileSize,
        status: AssetTransferStatus.completed,
        completedAt: DateTime.now(),
      );
      _updateTransfer(completedTransfer);

      // Cache asset
      _assetCache[asset.id] = asset;
      _recentAssets.insert(0, asset);
      if (_recentAssets.length > 20) _recentAssets.removeLast();

      notifyListeners();
      return asset;
    } catch (e) {
      final failedTransfer = transfer.copyWith(
        status: AssetTransferStatus.failed,
        errorMessage: e.toString(),
      );
      _updateTransfer(failedTransfer);
      _lastError = 'Upload failed: $e';
      return null;
    }
  }

  // ============================================================================
  // DOWNLOAD
  // ============================================================================

  /// Download an asset to local storage
  Future<String?> downloadAsset(
    CloudAsset asset, {
    String? targetDir,
    void Function(double progress)? onProgress,
  }) async {
    targetDir ??= _cacheDir;

    final fileName = '${asset.id}.${asset.format}';
    final targetPath = path.join(targetDir, fileName);

    // Check if already cached
    if (await File(targetPath).exists()) {
      return targetPath;
    }

    // Create transfer tracking
    final transfer = AssetTransfer(
      id: 'transfer_${DateTime.now().millisecondsSinceEpoch}',
      assetId: asset.id,
      fileName: fileName,
      isUpload: false,
      totalBytes: asset.sizeBytes,
      startedAt: DateTime.now(),
    );

    _activeTransfers.add(transfer);
    _transferController.add(transfer);
    notifyListeners();

    try {
      // Download file from cloud
      if (asset.cloudUrl.isNotEmpty && !asset.cloudUrl.startsWith('mock://')) {
        final downloadUrl = asset.cloudUrl.startsWith('http')
            ? asset.cloudUrl
            : '$_cdnBaseUrl/${asset.cloudUrl}';

        final response = await http.get(
          Uri.parse(downloadUrl),
          headers: _authHeadersAsset(),
        ).timeout(const Duration(seconds: 120));

        if (response.statusCode != 200) {
          throw Exception('Download failed: ${response.statusCode}');
        }

        await File(targetPath).parent.create(recursive: true);
        await File(targetPath).writeAsBytes(response.bodyBytes);

        final updatedTransfer = transfer.copyWith(
          transferredBytes: response.bodyBytes.length,
          status: AssetTransferStatus.inProgress,
        );
        _updateTransfer(updatedTransfer);
        onProgress?.call(1.0);
      } else {
        // No real URL — create placeholder (unconfigured mode)
        await File(targetPath).create(recursive: true);
        onProgress?.call(1.0);
      }

      // Mark transfer complete
      final completedTransfer = transfer.copyWith(
        transferredBytes: asset.sizeBytes,
        status: AssetTransferStatus.completed,
        completedAt: DateTime.now(),
      );
      _updateTransfer(completedTransfer);

      notifyListeners();
      return targetPath;
    } catch (e) {
      final failedTransfer = transfer.copyWith(
        status: AssetTransferStatus.failed,
        errorMessage: e.toString(),
      );
      _updateTransfer(failedTransfer);
      _lastError = 'Download failed: $e';
      return null;
    }
  }

  /// Cancel an active transfer
  void cancelTransfer(String transferId) {
    final index = _activeTransfers.indexWhere((t) => t.id == transferId);
    if (index != -1) {
      final cancelled = _activeTransfers[index].copyWith(
        status: AssetTransferStatus.cancelled,
      );
      _activeTransfers[index] = cancelled;
      _transferController.add(cancelled);
      notifyListeners();
    }
  }

  void _updateTransfer(AssetTransfer transfer) {
    final index = _activeTransfers.indexWhere((t) => t.id == transfer.id);
    if (index != -1) {
      _activeTransfers[index] = transfer;
      _transferController.add(transfer);
      notifyListeners();
    }
  }

  // ============================================================================
  // RATING
  // ============================================================================

  /// Rate an asset
  Future<bool> rateAsset(String assetId, int rating) async {
    if (!_isAuthenticated || rating < 1 || rating > 5) return false;

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/assets/$assetId/rate'),
        headers: {
          ..._authHeadersAsset(),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'rating': rating}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200 && response.statusCode != 201) {
        _lastError = 'Failed to rate asset: ${response.statusCode}';
        return false;
      }

      // Update cached asset rating if available
      final cached = _assetCache[assetId];
      if (cached != null) {
        final newCount = cached.ratingCount + 1;
        final newRating =
            ((cached.rating * cached.ratingCount) + rating) / newCount;
        _assetCache[assetId] = CloudAsset(
          id: cached.id,
          name: cached.name,
          description: cached.description,
          category: cached.category,
          tags: cached.tags,
          format: cached.format,
          sizeBytes: cached.sizeBytes,
          durationSeconds: cached.durationSeconds,
          sampleRate: cached.sampleRate,
          channels: cached.channels,
          bitDepth: cached.bitDepth,
          cloudUrl: cached.cloudUrl,
          thumbnailUrl: cached.thumbnailUrl,
          waveformUrl: cached.waveformUrl,
          checksum: cached.checksum,
          uploaderId: cached.uploaderId,
          uploaderName: cached.uploaderName,
          uploadedAt: cached.uploadedAt,
          updatedAt: cached.updatedAt,
          license: cached.license,
          downloadCount: cached.downloadCount,
          rating: newRating,
          ratingCount: newCount,
          isPublic: cached.isPublic,
          collections: cached.collections,
        );
      }

      notifyListeners();
      return true;
    } on TimeoutException {
      _lastError = 'Request timed out';
      return false;
    } on SocketException {
      _lastError = 'No network connection';
      return false;
    } catch (e) {
      _lastError = 'Failed to rate asset: $e';
      return false;
    }
  }

  // ============================================================================
  // CONFIGURATION
  // ============================================================================

  /// Set cloud provider
  Future<void> setProvider(AssetCloudProvider provider) async {
    _provider = provider;

    // Update URLs based on provider
    switch (provider) {
      case AssetCloudProvider.fluxforge:
        _apiBaseUrl = 'https://api.fluxforge.io/assets';
        _cdnBaseUrl = 'https://cdn.fluxforge.io';
        break;
      case AssetCloudProvider.aws:
        _apiBaseUrl = 'https://s3.amazonaws.com/fluxforge-assets';
        _cdnBaseUrl = 'https://d1234567890.cloudfront.net';
        break;
      default:
        // Keep current or use custom
        break;
    }

    await _saveConfig();
    notifyListeners();
  }

  /// Set custom API URL
  Future<void> setCustomUrls({
    required String apiUrl,
    required String cdnUrl,
  }) async {
    _apiBaseUrl = apiUrl;
    _cdnBaseUrl = cdnUrl;
    await _saveConfig();
  }

  // ============================================================================
  // DISPOSE
  // ============================================================================

  @override
  void dispose() {
    _transferController.close();
    super.dispose();
  }
}
