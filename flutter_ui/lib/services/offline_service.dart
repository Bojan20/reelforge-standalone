/// Offline Service — P3-14
///
/// Manages offline-first functionality:
/// - Connectivity monitoring
/// - Operation queue for offline actions
/// - Auto-sync when connection restored
/// - Cache management
///
/// Usage:
///   // Initialize at app startup
///   await OfflineService.instance.init();
///
///   // Check connectivity
///   if (OfflineService.instance.isOnline) { ... }
///
///   // Queue an operation for later sync
///   OfflineService.instance.queueOperation(operation);
///
///   // Listen for connectivity changes
///   OfflineService.instance.addListener(() => rebuild());
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// OPERATION TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Types of operations that can be queued offline
enum OfflineOperationType {
  /// Save project to cloud
  saveProject,

  /// Upload audio file
  uploadAudio,

  /// Sync event changes
  syncEvents,

  /// Export project
  exportProject,

  /// Analytics event
  analytics,

  /// Custom operation
  custom,
}

/// Priority for offline operations
enum OperationPriority {
  /// Critical operations (save project)
  critical,

  /// High priority (sync events)
  high,

  /// Normal priority (upload audio)
  normal,

  /// Low priority (analytics)
  low,
}

/// Offline operation model
class OfflineOperation {
  final String id;
  final OfflineOperationType type;
  final OperationPriority priority;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final int retryCount;
  final String? errorMessage;

  OfflineOperation({
    required this.id,
    required this.type,
    this.priority = OperationPriority.normal,
    required this.data,
    DateTime? createdAt,
    this.retryCount = 0,
    this.errorMessage,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Create copy with updated fields
  OfflineOperation copyWith({
    int? retryCount,
    String? errorMessage,
  }) {
    return OfflineOperation(
      id: id,
      type: type,
      priority: priority,
      data: data,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'priority': priority.index,
        'data': data,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
        'errorMessage': errorMessage,
      };

  /// Deserialize from JSON
  factory OfflineOperation.fromJson(Map<String, dynamic> json) {
    return OfflineOperation(
      id: json['id'] as String,
      type: OfflineOperationType.values[json['type'] as int],
      priority: OperationPriority.values[json['priority'] as int],
      data: Map<String, dynamic>.from(json['data'] as Map),
      createdAt: DateTime.parse(json['createdAt'] as String),
      retryCount: json['retryCount'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONNECTIVITY STATUS
// ═══════════════════════════════════════════════════════════════════════════

/// Connectivity status
enum ConnectivityStatus {
  /// Connected to network
  online,

  /// No network connection
  offline,

  /// Checking connectivity
  checking,

  /// Connection is slow/unstable
  unstable,
}

extension ConnectivityStatusExtension on ConnectivityStatus {
  String get displayName {
    switch (this) {
      case ConnectivityStatus.online:
        return 'Online';
      case ConnectivityStatus.offline:
        return 'Offline';
      case ConnectivityStatus.checking:
        return 'Checking...';
      case ConnectivityStatus.unstable:
        return 'Unstable';
    }
  }

  bool get isConnected =>
      this == ConnectivityStatus.online || this == ConnectivityStatus.unstable;
}

// ═══════════════════════════════════════════════════════════════════════════
// OFFLINE SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing offline-first functionality
class OfflineService extends ChangeNotifier {
  OfflineService._();
  static final instance = OfflineService._();

  static const _prefsKeyQueue = 'offline_queue';
  static const _maxRetries = 3;
  static const _checkInterval = Duration(seconds: 30);

  // State
  ConnectivityStatus _status = ConnectivityStatus.checking;
  final List<OfflineOperation> _queue = [];
  Timer? _connectivityTimer;
  Timer? _syncTimer;
  bool _initialized = false;
  bool _syncing = false;

  // Callbacks
  final Map<OfflineOperationType, Future<bool> Function(OfflineOperation)>
      _handlers = {};

  // Getters
  ConnectivityStatus get status => _status;
  bool get isOnline => _status.isConnected;
  bool get isOffline => _status == ConnectivityStatus.offline;
  bool get isSyncing => _syncing;
  List<OfflineOperation> get queue => List.unmodifiable(_queue);
  int get pendingCount => _queue.length;
  bool get hasPendingOperations => _queue.isNotEmpty;
  bool get initialized => _initialized;

  /// Initialize the service
  Future<void> init() async {
    if (_initialized) return;

    // Load persisted queue
    await _loadQueue();

    // Check initial connectivity
    await _checkConnectivity();

    // Start periodic connectivity checks
    _connectivityTimer = Timer.periodic(_checkInterval, (_) {
      _checkConnectivity();
    });

    _initialized = true;
    debugPrint('[OfflineService] Initialized with ${_queue.length} pending operations');
    notifyListeners();
  }

  /// Register a handler for an operation type
  void registerHandler(
    OfflineOperationType type,
    Future<bool> Function(OfflineOperation) handler,
  ) {
    _handlers[type] = handler;
    debugPrint('[OfflineService] Registered handler for $type');
  }

  /// Queue an operation for later sync
  Future<void> queueOperation(OfflineOperation operation) async {
    // Check for duplicate
    if (_queue.any((op) => op.id == operation.id)) {
      debugPrint('[OfflineService] Duplicate operation: ${operation.id}');
      return;
    }

    _queue.add(operation);

    // Sort by priority (critical first)
    _queue.sort((a, b) => a.priority.index.compareTo(b.priority.index));

    await _saveQueue();
    notifyListeners();

    debugPrint('[OfflineService] Queued: ${operation.type} (${operation.id})');

    // Try immediate sync if online
    if (isOnline) {
      _attemptSync();
    }
  }

  /// Remove an operation from the queue
  Future<void> removeOperation(String operationId) async {
    _queue.removeWhere((op) => op.id == operationId);
    await _saveQueue();
    notifyListeners();
  }

  /// Clear all operations
  Future<void> clearQueue() async {
    _queue.clear();
    await _saveQueue();
    notifyListeners();
    debugPrint('[OfflineService] Queue cleared');
  }

  /// Force connectivity check
  Future<void> checkConnectivity() async {
    await _checkConnectivity();
  }

  /// Force sync attempt
  Future<void> forceSync() async {
    if (!isOnline) {
      debugPrint('[OfflineService] Cannot sync while offline');
      return;
    }
    await _attemptSync();
  }

  /// Check network connectivity
  Future<void> _checkConnectivity() async {
    final previousStatus = _status;
    _status = ConnectivityStatus.checking;

    if (previousStatus != _status) {
      notifyListeners();
    }

    try {
      // Try to reach a known host
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));

      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        _status = ConnectivityStatus.online;
      } else {
        _status = ConnectivityStatus.offline;
      }
    } on SocketException {
      _status = ConnectivityStatus.offline;
    } on TimeoutException {
      _status = ConnectivityStatus.unstable;
    } catch (e) {
      _status = ConnectivityStatus.offline;
    }

    if (previousStatus != _status) {
      debugPrint('[OfflineService] Connectivity: $previousStatus → $_status');
      notifyListeners();

      // Attempt sync when coming online
      if (_status == ConnectivityStatus.online && hasPendingOperations) {
        _attemptSync();
      }
    }
  }

  /// Attempt to sync pending operations
  Future<void> _attemptSync() async {
    if (_syncing || !isOnline || _queue.isEmpty) return;

    _syncing = true;
    notifyListeners();

    debugPrint('[OfflineService] Starting sync (${_queue.length} pending)');

    final toRemove = <String>[];
    final toUpdate = <OfflineOperation>[];

    for (final operation in List.from(_queue)) {
      final handler = _handlers[operation.type];

      if (handler == null) {
        debugPrint('[OfflineService] No handler for ${operation.type}');
        continue;
      }

      try {
        final success = await handler(operation);

        if (success) {
          toRemove.add(operation.id);
          debugPrint('[OfflineService] ✓ Synced: ${operation.id}');
        } else {
          // Increment retry count
          final updated = operation.copyWith(
            retryCount: operation.retryCount + 1,
            errorMessage: 'Sync failed',
          );

          if (updated.retryCount >= _maxRetries) {
            toRemove.add(operation.id);
            debugPrint('[OfflineService] ✗ Max retries: ${operation.id}');
          } else {
            toUpdate.add(updated);
          }
        }
      } catch (e) {
        debugPrint('[OfflineService] Error syncing ${operation.id}: $e');

        final updated = operation.copyWith(
          retryCount: operation.retryCount + 1,
          errorMessage: e.toString(),
        );

        if (updated.retryCount >= _maxRetries) {
          toRemove.add(operation.id);
        } else {
          toUpdate.add(updated);
        }
      }
    }

    // Apply changes
    _queue.removeWhere((op) => toRemove.contains(op.id));
    for (final updated in toUpdate) {
      final index = _queue.indexWhere((op) => op.id == updated.id);
      if (index >= 0) {
        _queue[index] = updated;
      }
    }

    await _saveQueue();

    _syncing = false;
    notifyListeners();

    debugPrint('[OfflineService] Sync complete (${_queue.length} remaining)');
  }

  /// Load queue from SharedPreferences
  Future<void> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefsKeyQueue);

      if (json != null) {
        final List<dynamic> list = jsonDecode(json);
        _queue.clear();
        _queue.addAll(
          list.map((item) => OfflineOperation.fromJson(item as Map<String, dynamic>)),
        );
      }
    } catch (e) {
      debugPrint('[OfflineService] Load error: $e');
    }
  }

  /// Save queue to SharedPreferences
  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_queue.map((op) => op.toJson()).toList());
      await prefs.setString(_prefsKeyQueue, json);
    } catch (e) {
      debugPrint('[OfflineService] Save error: $e');
    }
  }

  /// Dispose timers
  @override
  void dispose() {
    _connectivityTimer?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }
}
