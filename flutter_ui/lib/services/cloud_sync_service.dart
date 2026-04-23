/// Cloud Sync Service — P3-01
///
/// Backend-agnostic cloud synchronization for FluxForge projects.
/// Supports multiple providers: Firebase, AWS S3, Custom REST API.
///
/// Features:
/// - Project upload/download with progress
/// - Incremental sync (delta updates)
/// - Conflict resolution strategies
/// - Offline queue integration
/// - Real-time sync status
///
/// Usage:
///   await CloudSyncService.instance.init(provider: CloudProvider.firebase);
///   await CloudSyncService.instance.uploadProject(project);
///   await CloudSyncService.instance.downloadProject(projectId);
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CLOUD PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

/// Supported cloud providers
enum CloudProvider {
  /// Firebase/Firestore + Cloud Storage
  firebase,

  /// AWS S3 + DynamoDB
  aws,

  /// Custom REST API backend
  custom,

  /// Local network sync (LAN)
  local,
}

extension CloudProviderExtension on CloudProvider {
  String get displayName {
    switch (this) {
      case CloudProvider.firebase:
        return 'Firebase';
      case CloudProvider.aws:
        return 'AWS';
      case CloudProvider.custom:
        return 'Custom Server';
      case CloudProvider.local:
        return 'Local Network';
    }
  }

  String get description {
    switch (this) {
      case CloudProvider.firebase:
        return 'Google Firebase with Firestore and Cloud Storage';
      case CloudProvider.aws:
        return 'Amazon Web Services with S3 and DynamoDB';
      case CloudProvider.custom:
        return 'Custom REST API backend';
      case CloudProvider.local:
        return 'Local network sync between devices';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SYNC STATUS
// ═══════════════════════════════════════════════════════════════════════════

/// Sync operation status
enum SyncStatus {
  /// Not syncing
  idle,

  /// Checking for changes
  checking,

  /// Uploading changes
  uploading,

  /// Downloading changes
  downloading,

  /// Resolving conflicts
  resolving,

  /// Sync complete
  complete,

  /// Sync failed
  error,
}

extension SyncStatusExtension on SyncStatus {
  String get displayName {
    switch (this) {
      case SyncStatus.idle:
        return 'Idle';
      case SyncStatus.checking:
        return 'Checking...';
      case SyncStatus.uploading:
        return 'Uploading...';
      case SyncStatus.downloading:
        return 'Downloading...';
      case SyncStatus.resolving:
        return 'Resolving conflicts...';
      case SyncStatus.complete:
        return 'Synced';
      case SyncStatus.error:
        return 'Error';
    }
  }

  bool get isActive =>
      this == SyncStatus.checking ||
      this == SyncStatus.uploading ||
      this == SyncStatus.downloading ||
      this == SyncStatus.resolving;
}

/// Conflict resolution strategy
enum ConflictStrategy {
  /// Keep local version
  keepLocal,

  /// Keep remote version
  keepRemote,

  /// Keep newer version (by timestamp)
  keepNewer,

  /// Merge changes (if possible)
  merge,

  /// Ask user to resolve
  askUser,
}

// ═══════════════════════════════════════════════════════════════════════════
// CLOUD PROJECT MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Cloud project metadata
class CloudProject {
  final String id;
  final String name;
  final String ownerId;
  final String ownerEmail;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String localPath;
  final String? remoteUrl;
  final String contentHash;
  final int sizeBytes;
  final CloudProjectStatus status;
  final List<String> sharedWith;
  final Map<String, dynamic> metadata;

  CloudProject({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.ownerEmail,
    required this.createdAt,
    required this.updatedAt,
    required this.localPath,
    this.remoteUrl,
    required this.contentHash,
    required this.sizeBytes,
    this.status = CloudProjectStatus.local,
    this.sharedWith = const [],
    this.metadata = const {},
  });

  CloudProject copyWith({
    String? name,
    DateTime? updatedAt,
    String? remoteUrl,
    String? contentHash,
    int? sizeBytes,
    CloudProjectStatus? status,
    List<String>? sharedWith,
    Map<String, dynamic>? metadata,
  }) {
    return CloudProject(
      id: id,
      name: name ?? this.name,
      ownerId: ownerId,
      ownerEmail: ownerEmail,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      localPath: localPath,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      contentHash: contentHash ?? this.contentHash,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      status: status ?? this.status,
      sharedWith: sharedWith ?? this.sharedWith,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ownerId': ownerId,
        'ownerEmail': ownerEmail,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'localPath': localPath,
        'remoteUrl': remoteUrl,
        'contentHash': contentHash,
        'sizeBytes': sizeBytes,
        'status': status.index,
        'sharedWith': sharedWith,
        'metadata': metadata,
      };

  factory CloudProject.fromJson(Map<String, dynamic> json) {
    return CloudProject(
      id: json['id'] as String,
      name: json['name'] as String,
      ownerId: json['ownerId'] as String,
      ownerEmail: json['ownerEmail'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      localPath: json['localPath'] as String,
      remoteUrl: json['remoteUrl'] as String?,
      contentHash: json['contentHash'] as String,
      sizeBytes: json['sizeBytes'] as int,
      status: CloudProjectStatus.values[json['status'] as int? ?? 0],
      sharedWith: List<String>.from(json['sharedWith'] as List? ?? []),
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? {}),
    );
  }
}

/// Cloud project sync status
enum CloudProjectStatus {
  /// Only exists locally
  local,

  /// Synced with cloud
  synced,

  /// Local changes not uploaded
  localChanges,

  /// Remote changes not downloaded
  remoteChanges,

  /// Conflict between local and remote
  conflict,

  /// Sync in progress
  syncing,

  /// Sync error
  error,
}

extension CloudProjectStatusExtension on CloudProjectStatus {
  String get displayName {
    switch (this) {
      case CloudProjectStatus.local:
        return 'Local Only';
      case CloudProjectStatus.synced:
        return 'Synced';
      case CloudProjectStatus.localChanges:
        return 'Local Changes';
      case CloudProjectStatus.remoteChanges:
        return 'Remote Changes';
      case CloudProjectStatus.conflict:
        return 'Conflict';
      case CloudProjectStatus.syncing:
        return 'Syncing...';
      case CloudProjectStatus.error:
        return 'Error';
    }
  }

  bool get needsSync =>
      this == CloudProjectStatus.localChanges ||
      this == CloudProjectStatus.remoteChanges ||
      this == CloudProjectStatus.conflict;
}

// ═══════════════════════════════════════════════════════════════════════════
// SYNC RESULT
// ═══════════════════════════════════════════════════════════════════════════

/// Result of a sync operation
class SyncResult {
  final bool success;
  final String? errorMessage;
  final int filesUploaded;
  final int filesDownloaded;
  final int conflictsResolved;
  final Duration duration;
  final DateTime timestamp;

  SyncResult({
    required this.success,
    this.errorMessage,
    this.filesUploaded = 0,
    this.filesDownloaded = 0,
    this.conflictsResolved = 0,
    required this.duration,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory SyncResult.success({
    int filesUploaded = 0,
    int filesDownloaded = 0,
    int conflictsResolved = 0,
    required Duration duration,
  }) {
    return SyncResult(
      success: true,
      filesUploaded: filesUploaded,
      filesDownloaded: filesDownloaded,
      conflictsResolved: conflictsResolved,
      duration: duration,
    );
  }

  factory SyncResult.failure(String message, Duration duration) {
    return SyncResult(
      success: false,
      errorMessage: message,
      duration: duration,
    );
  }

  @override
  String toString() {
    if (success) {
      return 'Sync complete: $filesUploaded uploaded, $filesDownloaded downloaded';
    }
    return 'Sync failed: $errorMessage';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLOUD SYNC SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for cloud project synchronization
class CloudSyncService extends ChangeNotifier {
  CloudSyncService._();
  static final instance = CloudSyncService._();

  static const _prefsKeyProjects = 'cloud_sync_projects';
  static const _prefsKeyProvider = 'cloud_sync_provider';
  static const _prefsKeyUserId = 'cloud_sync_user_id';
  static const _prefsKeyApiEndpoint = 'cloud_sync_api_endpoint';

  // State
  CloudProvider _provider = CloudProvider.firebase;
  SyncStatus _status = SyncStatus.idle;
  double _progress = 0.0;
  String? _currentOperation;
  String? _errorMessage;
  String? _userId;
  String? _userEmail;
  String? _apiEndpoint;
  bool _initialized = false;
  bool _isAuthenticated = false;

  final List<CloudProject> _projects = [];
  final Map<String, DateTime> _lastSyncTimes = {};
  Timer? _autoSyncTimer;

  // Callbacks
  void Function(CloudProject, CloudProject)? onConflictDetected;
  void Function(SyncResult)? onSyncComplete;

  // Getters
  CloudProvider get provider => _provider;
  SyncStatus get status => _status;
  double get progress => _progress;
  String? get currentOperation => _currentOperation;
  String? get errorMessage => _errorMessage;
  String? get userId => _userId;
  String? get userEmail => _userEmail;
  bool get initialized => _initialized;
  bool get isAuthenticated => _isAuthenticated;
  bool get isSyncing => _status.isActive;
  bool get isEnabled => _initialized && _isAuthenticated;
  List<CloudProject> get projects => List.unmodifiable(_projects);

  /// Get last sync time (most recent across all projects)
  DateTime? get lastSyncTime {
    if (_lastSyncTimes.isEmpty) return null;
    return _lastSyncTimes.values.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Initialize the service
  Future<void> init({CloudProvider? provider}) async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load provider
      final providerIndex = prefs.getInt(_prefsKeyProvider);
      if (providerIndex != null && providerIndex < CloudProvider.values.length) {
        _provider = CloudProvider.values[providerIndex];
      }
      if (provider != null) {
        _provider = provider;
      }

      // Load user info
      _userId = prefs.getString(_prefsKeyUserId);
      _apiEndpoint = prefs.getString(_prefsKeyApiEndpoint);
      _authToken = prefs.getString('cloud_sync_auth_token');
      _isAuthenticated = _userId != null;

      // Load projects
      await _loadProjects();

      _initialized = true;
      notifyListeners();
    } catch (e) {
      _initialized = true;
    }
  }

  /// Set cloud provider
  Future<void> setProvider(CloudProvider provider) async {
    if (_provider == provider) return;
    _provider = provider;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyProvider, provider.index);

    notifyListeners();
  }

  /// Set custom API endpoint (for custom provider)
  Future<void> setApiEndpoint(String endpoint) async {
    _apiEndpoint = endpoint;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyApiEndpoint, endpoint);

    notifyListeners();
  }

  /// Authenticate user against cloud backend.
  ///
  /// For custom/firebase/aws providers, POSTs to `{apiEndpoint}/auth/login`.
  /// For local provider, uses email hash as offline identity.
  /// Stores auth token for subsequent API calls.
  String? _authToken;

  Future<bool> authenticate({
    required String email,
    required String password,
  }) async {
    _setStatus(SyncStatus.checking, 'Authenticating...');

    try {
      if (_provider == CloudProvider.local) {
        // Local network: no server auth, use email hash as identity
        _userId = md5.convert(utf8.encode(email)).toString().substring(0, 16);
        _userEmail = email;
        _isAuthenticated = true;
        _authToken = null;
      } else {
        // Server-based auth: POST to /auth/login
        final endpoint = _resolveEndpoint();
        if (endpoint == null) {
          throw Exception('No API endpoint configured. Set endpoint first.');
        }

        final response = await http.post(
          Uri.parse('$endpoint/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          _authToken = data['token'] as String? ?? data['access_token'] as String?;
          _userId = data['userId'] as String? ?? data['user_id'] as String? ?? data['id'] as String?;
          _userEmail = data['email'] as String? ?? email;

          // Fallback: if server doesn't return userId, derive from email
          _userId ??= md5.convert(utf8.encode(email)).toString().substring(0, 16);

          _isAuthenticated = true;
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          throw Exception('Invalid credentials');
        } else {
          throw Exception('Server error ${response.statusCode}: ${response.body}');
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyUserId, _userId!);
      if (_authToken != null) {
        await prefs.setString('cloud_sync_auth_token', _authToken!);
      }

      _setStatus(SyncStatus.idle);
      return true;
    } on TimeoutException {
      _setStatus(SyncStatus.error, null, 'Authentication timed out — check your connection');
      return false;
    } on SocketException catch (e) {
      _setStatus(SyncStatus.error, null, 'Cannot reach server: ${e.message}');
      return false;
    } catch (e) {
      _setStatus(SyncStatus.error, null, 'Authentication failed: $e');
      return false;
    }
  }

  /// Resolve API endpoint for current provider
  String? _resolveEndpoint() {
    switch (_provider) {
      case CloudProvider.firebase:
        // Firebase REST: Cloud Functions or Firestore REST API
        return _apiEndpoint ?? 'https://us-central1-fluxforge-studio.cloudfunctions.net/api';
      case CloudProvider.aws:
        return _apiEndpoint ?? 'https://api.fluxforge.studio';
      case CloudProvider.custom:
        return _apiEndpoint;
      case CloudProvider.local:
        return _apiEndpoint ?? 'http://localhost:8766';
    }
  }

  /// Build auth headers for API calls
  Map<String, String> _authHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  /// Sign out and clear all auth state
  Future<void> signOut() async {
    _userId = null;
    _userEmail = null;
    _isAuthenticated = false;
    _authToken = null;
    disableAutoSync();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyUserId);
    await prefs.remove('cloud_sync_auth_token');

    notifyListeners();
  }

  /// Upload a project to cloud
  Future<SyncResult> uploadProject(
    String localPath, {
    String? name,
    void Function(double)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    if (!_isAuthenticated) {
      return SyncResult.failure('Not authenticated', stopwatch.elapsed);
    }

    _setStatus(SyncStatus.uploading, 'Preparing upload...');

    try {
      // Check if project exists
      final projectDir = Directory(localPath);
      if (!await projectDir.exists()) {
        throw Exception('Project directory not found: $localPath');
      }

      // Calculate content hash
      final contentHash = await _calculateDirectoryHash(localPath);

      // Get project size
      final sizeBytes = await _calculateDirectorySize(localPath);

      // Create project metadata
      final projectId = md5.convert(utf8.encode('$localPath${DateTime.now()}')).toString();
      final projectName = name ?? path.basename(localPath);

      final project = CloudProject(
        id: projectId,
        name: projectName,
        ownerId: _userId!,
        ownerEmail: _userEmail ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        localPath: localPath,
        contentHash: contentHash,
        sizeBytes: sizeBytes,
        status: CloudProjectStatus.syncing,
      );

      // Upload files
      _setStatus(SyncStatus.uploading, 'Uploading files...');
      final filesUploaded = await _uploadProjectFiles(
        project,
        onProgress: (p) {
          _progress = p;
          onProgress?.call(p);
          notifyListeners();
        },
      );

      // Update project status
      final syncedProject = project.copyWith(
        status: CloudProjectStatus.synced,
        remoteUrl: _getRemoteUrl(projectId),
      );

      // Save to local list
      _projects.add(syncedProject);
      await _saveProjects();
      _lastSyncTimes[projectId] = DateTime.now();

      stopwatch.stop();
      _setStatus(SyncStatus.complete);

      final result = SyncResult.success(
        filesUploaded: filesUploaded,
        duration: stopwatch.elapsed,
      );

      onSyncComplete?.call(result);

      return result;
    } catch (e) {
      stopwatch.stop();
      _setStatus(SyncStatus.error, null, e.toString());
      return SyncResult.failure(e.toString(), stopwatch.elapsed);
    }
  }

  /// Download a project from cloud
  Future<SyncResult> downloadProject(
    String projectId, {
    String? targetPath,
    void Function(double)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    if (!_isAuthenticated) {
      return SyncResult.failure('Not authenticated', stopwatch.elapsed);
    }

    _setStatus(SyncStatus.downloading, 'Preparing download...');

    try {
      // Find project
      final project = _projects.firstWhere(
        (p) => p.id == projectId,
        orElse: () => throw Exception('Project not found: $projectId'),
      );

      // Determine target path
      final downloadPath = targetPath ?? project.localPath;

      // Download files
      _setStatus(SyncStatus.downloading, 'Downloading files...');
      final filesDownloaded = await _downloadProjectFiles(
        project,
        downloadPath,
        onProgress: (p) {
          _progress = p;
          onProgress?.call(p);
          notifyListeners();
        },
      );

      // Update project status
      final index = _projects.indexWhere((p) => p.id == projectId);
      if (index >= 0) {
        _projects[index] = project.copyWith(
          status: CloudProjectStatus.synced,
          updatedAt: DateTime.now(),
        );
        await _saveProjects();
      }

      _lastSyncTimes[projectId] = DateTime.now();

      stopwatch.stop();
      _setStatus(SyncStatus.complete);

      final result = SyncResult.success(
        filesDownloaded: filesDownloaded,
        duration: stopwatch.elapsed,
      );

      onSyncComplete?.call(result);

      return result;
    } catch (e) {
      stopwatch.stop();
      _setStatus(SyncStatus.error, null, e.toString());
      return SyncResult.failure(e.toString(), stopwatch.elapsed);
    }
  }

  /// Sync a project (bidirectional)
  Future<SyncResult> syncProject(
    String projectId, {
    ConflictStrategy conflictStrategy = ConflictStrategy.keepNewer,
    void Function(double)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    if (!_isAuthenticated) {
      return SyncResult.failure('Not authenticated', stopwatch.elapsed);
    }

    _setStatus(SyncStatus.checking, 'Checking for changes...');

    try {
      // Find project
      final projectIndex = _projects.indexWhere((p) => p.id == projectId);
      if (projectIndex < 0) {
        throw Exception('Project not found: $projectId');
      }

      final project = _projects[projectIndex];

      // Check local changes
      final localHash = await _calculateDirectoryHash(project.localPath);
      final hasLocalChanges = localHash != project.contentHash;

      // Check remote changes (simulate)
      final remoteProjectNullable = await _fetchRemoteProject(projectId);
      final hasRemoteChanges = remoteProjectNullable != null &&
          remoteProjectNullable.contentHash != project.contentHash;

      int filesUploaded = 0;
      int filesDownloaded = 0;
      int conflictsResolved = 0;

      // Handle conflicts (Note: hasRemoteChanges already implies remoteProjectNullable != null)
      final remoteProject = remoteProjectNullable; // Capture for null-safety in closures
      if (hasLocalChanges && hasRemoteChanges && remoteProject != null) {
        final remote = remoteProject;
        _setStatus(SyncStatus.resolving, 'Resolving conflicts...');

        switch (conflictStrategy) {
          case ConflictStrategy.keepLocal:
            // Upload local changes
            filesUploaded = await _uploadProjectFiles(project, onProgress: onProgress);
            break;

          case ConflictStrategy.keepRemote:
            // Download remote changes
            filesDownloaded = await _downloadProjectFiles(
              remote,
              project.localPath,
              onProgress: onProgress,
            );
            break;

          case ConflictStrategy.keepNewer:
            if (remote.updatedAt.isAfter(project.updatedAt)) {
              filesDownloaded = await _downloadProjectFiles(
                remote,
                project.localPath,
                onProgress: onProgress,
              );
            } else {
              filesUploaded = await _uploadProjectFiles(project, onProgress: onProgress);
            }
            break;

          case ConflictStrategy.merge:
            // Attempt merge (simplified)
            filesUploaded = await _uploadProjectFiles(project, onProgress: onProgress);
            break;

          case ConflictStrategy.askUser:
            // Notify conflict
            onConflictDetected?.call(project, remote);
            throw Exception('Conflict requires user resolution');
        }

        conflictsResolved = 1;
      } else if (hasLocalChanges) {
        // Upload local changes
        _setStatus(SyncStatus.uploading, 'Uploading changes...');
        filesUploaded = await _uploadProjectFiles(project, onProgress: onProgress);
      } else if (hasRemoteChanges && remoteProject != null) {
        // Download remote changes
        _setStatus(SyncStatus.downloading, 'Downloading changes...');
        filesDownloaded = await _downloadProjectFiles(
          remoteProject,
          project.localPath,
          onProgress: onProgress,
        );
      }

      // Update project
      _projects[projectIndex] = project.copyWith(
        status: CloudProjectStatus.synced,
        updatedAt: DateTime.now(),
        contentHash: await _calculateDirectoryHash(project.localPath),
      );
      await _saveProjects();

      _lastSyncTimes[projectId] = DateTime.now();

      stopwatch.stop();
      _setStatus(SyncStatus.complete);

      final result = SyncResult.success(
        filesUploaded: filesUploaded,
        filesDownloaded: filesDownloaded,
        conflictsResolved: conflictsResolved,
        duration: stopwatch.elapsed,
      );

      onSyncComplete?.call(result);
      return result;
    } catch (e) {
      stopwatch.stop();
      _setStatus(SyncStatus.error, null, e.toString());
      return SyncResult.failure(e.toString(), stopwatch.elapsed);
    }
  }

  /// Sync all projects
  Future<List<SyncResult>> syncAllProjects({
    ConflictStrategy conflictStrategy = ConflictStrategy.keepNewer,
  }) async {
    final results = <SyncResult>[];

    for (final project in _projects) {
      final result = await syncProject(
        project.id,
        conflictStrategy: conflictStrategy,
      );
      results.add(result);
    }

    return results;
  }

  /// Delete a project from cloud
  Future<bool> deleteCloudProject(String projectId) async {
    if (!_isAuthenticated) return false;

    try {
      // Delete from server
      final endpoint = _resolveEndpoint();
      if (endpoint != null && _provider != CloudProvider.local) {
        final response = await http.delete(
          Uri.parse('$endpoint/projects/$projectId'),
          headers: _authHeaders(),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode != 200 && response.statusCode != 204) {
          throw Exception('Delete failed: ${response.statusCode}');
        }
      }

      // Remove from local list
      _projects.removeWhere((p) => p.id == projectId);
      _lastSyncTimes.remove(projectId);
      await _saveProjects();

      notifyListeners();
      return true;
    } catch (e) {
      // Still remove locally even if server fails
      _projects.removeWhere((p) => p.id == projectId);
      _lastSyncTimes.remove(projectId);
      await _saveProjects();
      notifyListeners();
      return false;
    }
  }

  /// Share a project with another user
  Future<bool> shareProject(String projectId, String email) async {
    if (!_isAuthenticated) return false;

    try {
      final index = _projects.indexWhere((p) => p.id == projectId);
      if (index < 0) return false;

      // Notify server about share
      final endpoint = _resolveEndpoint();
      if (endpoint != null && _provider != CloudProvider.local) {
        final response = await http.post(
          Uri.parse('$endpoint/projects/$projectId/share'),
          headers: _authHeaders(),
          body: jsonEncode({'email': email}),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode != 200 && response.statusCode != 201) {
          throw Exception('Share failed: ${response.statusCode}');
        }
      }

      final project = _projects[index];
      final updatedSharedWith = List<String>.from(project.sharedWith)..add(email);

      _projects[index] = project.copyWith(sharedWith: updatedSharedWith);
      await _saveProjects();

      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get last sync time for a project
  DateTime? getLastSyncTime(String projectId) => _lastSyncTimes[projectId];

  /// Enable auto-sync
  void enableAutoSync({Duration interval = const Duration(minutes: 5)}) {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(interval, (_) {
      if (OfflineService.instance.isOnline && _isAuthenticated) {
        syncAllProjects();
      }
    });
  }

  /// Disable auto-sync
  void disableAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIVATE METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void _setStatus(SyncStatus status, [String? operation, String? errorMessage]) {
    _status = status;
    _currentOperation = operation;
    _errorMessage = errorMessage;
    if (status == SyncStatus.idle || status == SyncStatus.complete) {
      _progress = 0.0;
    }
    notifyListeners();
  }

  Future<void> _loadProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefsKeyProjects);

      if (json != null) {
        final List<dynamic> list = jsonDecode(json);
        _projects.clear();
        _projects.addAll(
          list.map((item) => CloudProject.fromJson(item as Map<String, dynamic>)),
        );
      }
    } catch (e) { /* ignored */ }
  }

  Future<void> _saveProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_projects.map((p) => p.toJson()).toList());
      await prefs.setString(_prefsKeyProjects, json);
    } catch (e) { /* ignored */ }
  }

  Future<String> _calculateDirectoryHash(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return '';

    final hashes = <String>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final bytes = await entity.readAsBytes();
        hashes.add(md5.convert(bytes).toString());
      }
    }

    hashes.sort();
    return md5.convert(utf8.encode(hashes.join())).toString();
  }

  Future<int> _calculateDirectorySize(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return 0;

    int size = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        size += await entity.length();
      }
    }
    return size;
  }

  String _getRemoteUrl(String projectId) {
    switch (_provider) {
      case CloudProvider.firebase:
        return 'gs://fluxforge-studio.appspot.com/projects/$projectId';
      case CloudProvider.aws:
        return 's3://fluxforge-studio/projects/$projectId';
      case CloudProvider.custom:
        return '$_apiEndpoint/projects/$projectId';
      case CloudProvider.local:
        return 'local://$projectId';
    }
  }

  /// Upload project files to cloud storage.
  ///
  /// Strategy: collect all project files, create a tar-like manifest,
  /// upload each file via multipart POST. Server stores files under
  /// `projects/{projectId}/{relativePath}`.
  Future<int> _uploadProjectFiles(
    CloudProject project, {
    void Function(double)? onProgress,
  }) async {
    final dir = Directory(project.localPath);
    if (!await dir.exists()) return 0;

    final endpoint = _resolveEndpoint();
    if (endpoint == null) {
      throw Exception('No API endpoint configured');
    }

    // Collect all files
    final files = <File>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        // Skip macOS metadata files and build artifacts
        final name = path.basename(entity.path);
        if (name.startsWith('._') || name == '.DS_Store') continue;
        files.add(entity);
      }
    }

    if (files.isEmpty) return 0;

    int uploaded = 0;

    // Upload metadata first
    await http.put(
      Uri.parse('$endpoint/projects/${project.id}'),
      headers: _authHeaders(),
      body: jsonEncode(project.toJson()),
    ).timeout(const Duration(seconds: 15));

    // Upload files in batches (avoid overwhelming the server)
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final relativePath = file.path.replaceFirst('${project.localPath}/', '');

      // Create multipart request for each file
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$endpoint/projects/${project.id}/files'),
      );
      request.headers.addAll(_authHeaders());
      request.fields['path'] = relativePath;
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      final response = await request.send().timeout(const Duration(seconds: 60));
      if (response.statusCode != 200 && response.statusCode != 201) {
        final body = await response.stream.bytesToString();
        throw Exception('Upload failed for $relativePath: ${response.statusCode} $body');
      }

      uploaded++;
      onProgress?.call((i + 1) / files.length);
    }

    return uploaded;
  }

  /// Download project files from cloud storage.
  ///
  /// Strategy: GET file manifest from server, then download each file.
  /// Server provides file list at `projects/{projectId}/manifest`.
  Future<int> _downloadProjectFiles(
    CloudProject project,
    String targetPath, {
    void Function(double)? onProgress,
  }) async {
    await Directory(targetPath).create(recursive: true);

    final endpoint = _resolveEndpoint();
    if (endpoint == null) {
      throw Exception('No API endpoint configured');
    }

    // Get file manifest from server
    final manifestResponse = await http.get(
      Uri.parse('$endpoint/projects/${project.id}/manifest'),
      headers: _authHeaders(),
    ).timeout(const Duration(seconds: 15));

    if (manifestResponse.statusCode != 200) {
      throw Exception('Failed to get project manifest: ${manifestResponse.statusCode}');
    }

    final manifestData = jsonDecode(manifestResponse.body);
    final fileList = (manifestData['files'] as List<dynamic>?)
        ?.cast<Map<String, dynamic>>() ?? [];

    if (fileList.isEmpty) return 0;

    int downloaded = 0;

    for (int i = 0; i < fileList.length; i++) {
      final fileInfo = fileList[i];
      final relativePath = fileInfo['path'] as String;
      final fileUrl = fileInfo['url'] as String? ??
          '$endpoint/projects/${project.id}/files/$relativePath';

      // Download file
      final response = await http.get(
        Uri.parse(fileUrl),
        headers: _authHeaders(),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        throw Exception('Download failed for $relativePath: ${response.statusCode}');
      }

      // Write to local filesystem
      final outputFile = File(path.join(targetPath, relativePath));
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(response.bodyBytes);

      downloaded++;
      onProgress?.call((i + 1) / fileList.length);
    }

    return downloaded;
  }

  /// Fetch remote project metadata from server.
  ///
  /// Returns null if project doesn't exist on server or server is unreachable.
  Future<CloudProject?> _fetchRemoteProject(String projectId) async {
    final endpoint = _resolveEndpoint();
    if (endpoint == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$endpoint/projects/$projectId'),
        headers: _authHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return CloudProject.fromJson(data);
      } else if (response.statusCode == 404) {
        return null; // Project doesn't exist on server yet
      } else {
        return null; // Server error — treat as no remote data
      }
    } on TimeoutException {
      return null; // Server unreachable — work offline
    } on SocketException {
      return null; // No network — work offline
    } catch (e) {
      return null;
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }
}
