// T7.1: Project History Service — Rust-backed Git-like project versioning
//
// Wraps rf-cloud-sync via FFI for content-addressed snapshot history.
// Works offline-first. Cloud transport (T7.5) is a separate layer.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data Models
// ─────────────────────────────────────────────────────────────────────────────

/// Immutable, content-addressed project snapshot
class ProjectSnapshot {
  final String id;
  final String projectData;
  final String author;
  final String message;
  final String timestamp;
  final String? parentId;
  final String shortId;
  final int dataSizeBytes;

  const ProjectSnapshot({
    required this.id,
    required this.projectData,
    required this.author,
    required this.message,
    required this.timestamp,
    this.parentId,
    required this.shortId,
    required this.dataSizeBytes,
  });

  factory ProjectSnapshot.fromJson(Map<String, dynamic> json) => ProjectSnapshot(
    id: json['id'] as String,
    projectData: json['project_data'] as String,
    author: json['author'] as String,
    message: json['message'] as String,
    timestamp: json['timestamp'] as String,
    parentId: json['parent_id'] as String?,
    shortId: json['short_id'] as String,
    dataSizeBytes: json['data_size_bytes'] as int,
  );

  bool get isRoot => parentId == null;
}

/// Lightweight snapshot summary (no project_data)
class SnapshotSummary {
  final String id;
  final String shortId;
  final String author;
  final String message;
  final String timestamp;
  final String? parentId;
  final int dataSizeBytes;

  const SnapshotSummary({
    required this.id,
    required this.shortId,
    required this.author,
    required this.message,
    required this.timestamp,
    this.parentId,
    required this.dataSizeBytes,
  });

  factory SnapshotSummary.fromJson(Map<String, dynamic> json) => SnapshotSummary(
    id: json['id'] as String,
    shortId: json['short_id'] as String,
    author: json['author'] as String,
    message: json['message'] as String,
    timestamp: json['timestamp'] as String,
    parentId: json['parent_id'] as String?,
    dataSizeBytes: json['data_size_bytes'] as int,
  );
}

/// Diff operation type
enum DiffOpType { add, remove, modify }

/// Single diff entry at a JSON path
class DiffEntry {
  final String path;
  final DiffOpType opType;
  final dynamic fromValue;
  final dynamic toValue;
  final dynamic value; // for add operations
  final dynamic oldValue; // for remove operations

  const DiffEntry({
    required this.path,
    required this.opType,
    this.fromValue,
    this.toValue,
    this.value,
    this.oldValue,
  });

  factory DiffEntry.fromJson(Map<String, dynamic> json) {
    final opMap = json['op'] as Map<String, dynamic>;
    final opTag = opMap['op'] as String;
    DiffOpType opType;
    switch (opTag) {
      case 'add':    opType = DiffOpType.add; break;
      case 'remove': opType = DiffOpType.remove; break;
      default:       opType = DiffOpType.modify;
    }
    return DiffEntry(
      path: json['path'] as String,
      opType: opType,
      fromValue: opMap['from'],
      toValue: opMap['to'],
      value: opMap['value'],
      oldValue: opMap['old_value'],
    );
  }

  String get description {
    switch (opType) {
      case DiffOpType.add:    return '+$path = $value';
      case DiffOpType.remove: return '-$path (was: $oldValue)';
      case DiffOpType.modify: return '~$path: $fromValue → $toValue';
    }
  }
}

/// Complete diff between two snapshots
class ProjectDiff {
  final String fromId;
  final String toId;
  final List<DiffEntry> changes;
  final bool isIdentical;
  final int additions;
  final int removals;
  final int modifications;

  const ProjectDiff({
    required this.fromId,
    required this.toId,
    required this.changes,
    required this.isIdentical,
    required this.additions,
    required this.removals,
    required this.modifications,
  });

  factory ProjectDiff.fromJson(Map<String, dynamic> json) => ProjectDiff(
    fromId: json['from_id'] as String,
    toId: json['to_id'] as String,
    changes: (json['changes'] as List)
        .map((e) => DiffEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    isIdentical: json['is_identical'] as bool,
    additions: json['additions'] as int,
    removals: json['removals'] as int,
    modifications: json['modifications'] as int,
  );

  String get summary => isIdentical
      ? 'No changes'
      : '+$additions  -$removals  ~$modifications';

  int get totalChanges => additions + removals + modifications;
}

// ─────────────────────────────────────────────────────────────────────────────
// ProjectHistoryService (T7.1)
// ─────────────────────────────────────────────────────────────────────────────

/// Rust-backed Git-like project version history.
///
/// Each project gets a SyncManager instance (managed by rf-cloud-sync).
/// Fully offline — no network required for commit/diff/checkout.
///
/// Usage:
/// ```dart
/// final hist = sl<ProjectHistoryService>();
/// hist.initialize(projectId: 'golden_phoenix');
///
/// // On every save:
/// await hist.commit(
///   projectJson: jsonEncode(project),
///   author: 'alice',
///   message: 'Added WIN_5 ambient layer',
/// );
///
/// // View history:
/// final log = hist.log; // newest first
///
/// // See what changed:
/// final diff = await hist.diff(fromId: log[1].id, toId: log[0].id);
///
/// // Revert:
/// final snap = await hist.checkout(snapshotId: log[2].id);
/// ```
class ProjectHistoryService extends ChangeNotifier {
  final NativeFFI _ffi;

  int _managerId = -1;
  ProjectSnapshot? _head;
  List<SnapshotSummary> _log = [];
  bool _initialized = false;
  bool _isWorking = false;

  ProjectHistoryService(this._ffi);

  bool get isInitialized => _initialized;
  bool get isWorking => _isWorking;
  ProjectSnapshot? get head => _head;
  List<SnapshotSummary> get log => List.unmodifiable(_log);
  int get snapshotCount => _log.length;
  bool get hasHistory => _log.isNotEmpty;

  /// Initialize versioning for a project. Call once per project open.
  void initialize({
    required String projectId,
    int maxHistoryDepth = 100,
  }) {
    if (_managerId > 0) {
      _ffi.cloudSyncDestroy(_managerId);
    }
    final configJson = jsonEncode({
      'max_history_depth': maxHistoryDepth,
      'verify_on_push': true,
    });
    _managerId = _ffi.cloudSyncCreate(projectId, configJson);
    _initialized = _managerId > 0;
    _head = null;
    _log = [];
    notifyListeners();
  }

  /// Commit a new project snapshot.
  ///
  /// Returns the created snapshot or null on failure.
  Future<ProjectSnapshot?> commit({
    required String projectJson,
    required String author,
    String message = 'Auto-save',
  }) async {
    if (!_initialized) return null;
    _isWorking = true;
    notifyListeners();

    try {
      final snap = await Future(() {
        final json = _ffi.cloudSyncCommit(_managerId, projectJson, author, message);
        if (json == null) return null;
        return ProjectSnapshot.fromJson(jsonDecode(json) as Map<String, dynamic>);
      });

      if (snap != null) {
        _head = snap;
        await _refreshLog();
      }
      return snap;
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }

  /// Compute diff between two snapshot IDs (or short IDs).
  Future<ProjectDiff?> diff({required String fromId, required String toId}) async {
    if (!_initialized) return null;
    return await Future(() {
      final json = _ffi.cloudSyncDiff(_managerId, fromId, toId);
      if (json == null) return null;
      return ProjectDiff.fromJson(jsonDecode(json) as Map<String, dynamic>);
    });
  }

  /// Checkout a specific snapshot (moves HEAD, history is preserved).
  Future<ProjectSnapshot?> checkout({required String snapshotId}) async {
    if (!_initialized) return null;
    _isWorking = true;
    notifyListeners();

    try {
      final snap = await Future(() {
        final json = _ffi.cloudSyncCheckout(_managerId, snapshotId);
        if (json == null) return null;
        return ProjectSnapshot.fromJson(jsonDecode(json) as Map<String, dynamic>);
      });
      if (snap != null) {
        _head = snap;
        notifyListeners();
      }
      return snap;
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }

  /// Serialize history to JSON for disk persistence.
  Future<String?> serializeHistory() async {
    if (!_initialized) return null;
    return await Future(() => _ffi.cloudSyncSerialize(_managerId));
  }

  Future<void> _refreshLog() async {
    final json = await Future(() => _ffi.cloudSyncLog(_managerId));
    if (json != null) {
      final list = jsonDecode(json) as List;
      _log = list
          .map((e) => SnapshotSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (_managerId > 0) {
      _ffi.cloudSyncDestroy(_managerId);
    }
    super.dispose();
  }
}
