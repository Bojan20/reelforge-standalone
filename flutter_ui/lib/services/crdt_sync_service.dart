// FluxForge Studio - CRDT Sync Service
// P3-13: Collaborative Projects with Conflict-free Replicated Data Types
//
// Enables real-time collaborative editing of audio projects without conflicts.
// Uses CRDTs for automatic conflict resolution in distributed systems.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// CRDT operation type
enum CrdtOperationType {
  insert,
  delete,
  update,
  move,
  setAttribute,
  removeAttribute,
}

/// CRDT data type
enum CrdtDataType {
  track,
  clip,
  region,
  marker,
  automation,
  mixer,
  plugin,
  event,
  layer,
  metadata,
}

/// Vector clock for causal ordering
class VectorClock {
  final Map<String, int> _clock;

  VectorClock([Map<String, int>? initial]) : _clock = Map.from(initial ?? {});

  factory VectorClock.fromJson(Map<String, dynamic> json) {
    return VectorClock(json.map((k, v) => MapEntry(k, v as int)));
  }

  Map<String, dynamic> toJson() => Map.from(_clock);

  int operator [](String nodeId) => _clock[nodeId] ?? 0;

  void increment(String nodeId) {
    _clock[nodeId] = (_clock[nodeId] ?? 0) + 1;
  }

  void merge(VectorClock other) {
    for (final entry in other._clock.entries) {
      _clock[entry.key] = max(_clock[entry.key] ?? 0, entry.value);
    }
  }

  bool happenedBefore(VectorClock other) {
    bool atLeastOneLess = false;
    for (final key in {..._clock.keys, ...other._clock.keys}) {
      final thisValue = _clock[key] ?? 0;
      final otherValue = other._clock[key] ?? 0;
      if (thisValue > otherValue) return false;
      if (thisValue < otherValue) atLeastOneLess = true;
    }
    return atLeastOneLess;
  }

  bool concurrent(VectorClock other) {
    return !happenedBefore(other) && !other.happenedBefore(this);
  }

  VectorClock copy() => VectorClock(Map.from(_clock));

  @override
  String toString() => 'VectorClock($_clock)';
}

/// Unique identifier for CRDT elements
class CrdtId implements Comparable<CrdtId> {
  final String nodeId;
  final int sequence;
  final int timestamp;

  const CrdtId({
    required this.nodeId,
    required this.sequence,
    required this.timestamp,
  });

  factory CrdtId.generate(String nodeId, int sequence) {
    return CrdtId(
      nodeId: nodeId,
      sequence: sequence,
      timestamp: DateTime.now().microsecondsSinceEpoch,
    );
  }

  factory CrdtId.fromJson(Map<String, dynamic> json) {
    return CrdtId(
      nodeId: json['nodeId'] as String,
      sequence: json['sequence'] as int,
      timestamp: json['timestamp'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'sequence': sequence,
        'timestamp': timestamp,
      };

  @override
  int compareTo(CrdtId other) {
    // Compare by timestamp first
    final timestampCompare = timestamp.compareTo(other.timestamp);
    if (timestampCompare != 0) return timestampCompare;

    // Then by sequence
    final sequenceCompare = sequence.compareTo(other.sequence);
    if (sequenceCompare != 0) return sequenceCompare;

    // Finally by nodeId for deterministic ordering
    return nodeId.compareTo(other.nodeId);
  }

  @override
  bool operator ==(Object other) =>
      other is CrdtId &&
      nodeId == other.nodeId &&
      sequence == other.sequence &&
      timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(nodeId, sequence, timestamp);

  @override
  String toString() => '$nodeId:$sequence@$timestamp';
}

/// CRDT operation
class CrdtOperation {
  final CrdtId id;
  final CrdtOperationType type;
  final CrdtDataType dataType;
  final String targetId;
  final String? parentId;
  final Map<String, dynamic>? data;
  final VectorClock vectorClock;
  final String authorId;
  final DateTime createdAt;
  bool isApplied;
  bool isTombstoned;

  CrdtOperation({
    required this.id,
    required this.type,
    required this.dataType,
    required this.targetId,
    this.parentId,
    this.data,
    required this.vectorClock,
    required this.authorId,
    DateTime? createdAt,
    this.isApplied = false,
    this.isTombstoned = false,
  }) : createdAt = createdAt ?? DateTime.now();

  factory CrdtOperation.fromJson(Map<String, dynamic> json) {
    return CrdtOperation(
      id: CrdtId.fromJson(json['id'] as Map<String, dynamic>),
      type: CrdtOperationType.values.byName(json['type'] as String),
      dataType: CrdtDataType.values.byName(json['dataType'] as String),
      targetId: json['targetId'] as String,
      parentId: json['parentId'] as String?,
      data: json['data'] as Map<String, dynamic>?,
      vectorClock:
          VectorClock.fromJson(json['vectorClock'] as Map<String, dynamic>),
      authorId: json['authorId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isApplied: json['isApplied'] as bool? ?? false,
      isTombstoned: json['isTombstoned'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id.toJson(),
        'type': type.name,
        'dataType': dataType.name,
        'targetId': targetId,
        'parentId': parentId,
        'data': data,
        'vectorClock': vectorClock.toJson(),
        'authorId': authorId,
        'createdAt': createdAt.toIso8601String(),
        'isApplied': isApplied,
        'isTombstoned': isTombstoned,
      };
}

/// LWW (Last-Writer-Wins) Register for simple values
class LwwRegister<T> {
  LwwRegister();

  T? _value;
  CrdtId? _lastWriteId;

  T? get value => _value;
  CrdtId? get lastWriteId => _lastWriteId;

  bool set(T newValue, CrdtId writeId) {
    if (_lastWriteId == null || writeId.compareTo(_lastWriteId!) > 0) {
      _value = newValue;
      _lastWriteId = writeId;
      return true;
    }
    return false;
  }

  void merge(LwwRegister<T> other) {
    if (other._lastWriteId != null) {
      set(other._value as T, other._lastWriteId!);
    }
  }

  Map<String, dynamic> toJson(T Function(T) valueEncoder) => {
        'value': _value != null ? valueEncoder(_value as T) : null,
        'lastWriteId': _lastWriteId?.toJson(),
      };

  factory LwwRegister.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) valueDecoder,
  ) {
    final register = LwwRegister<T>();
    if (json['value'] != null) {
      register._value = valueDecoder(json['value']);
    }
    if (json['lastWriteId'] != null) {
      register._lastWriteId =
          CrdtId.fromJson(json['lastWriteId'] as Map<String, dynamic>);
    }
    return register;
  }
}

/// G-Counter (Grow-only counter)
class GCounter {
  GCounter();

  final Map<String, int> _counts = {};

  int get value => _counts.values.fold(0, (a, b) => a + b);

  void increment(String nodeId, [int amount = 1]) {
    _counts[nodeId] = (_counts[nodeId] ?? 0) + amount;
  }

  void merge(GCounter other) {
    for (final entry in other._counts.entries) {
      _counts[entry.key] = max(_counts[entry.key] ?? 0, entry.value);
    }
  }

  Map<String, dynamic> toJson() => Map.from(_counts);

  factory GCounter.fromJson(Map<String, dynamic> json) {
    final counter = GCounter();
    counter._counts.addAll(json.map((k, v) => MapEntry(k, v as int)));
    return counter;
  }
}

/// PN-Counter (Positive-Negative counter)
class PnCounter {
  PnCounter();

  final GCounter _positive = GCounter();
  final GCounter _negative = GCounter();

  int get value => _positive.value - _negative.value;

  void increment(String nodeId, [int amount = 1]) {
    _positive.increment(nodeId, amount);
  }

  void decrement(String nodeId, [int amount = 1]) {
    _negative.increment(nodeId, amount);
  }

  void merge(PnCounter other) {
    _positive.merge(other._positive);
    _negative.merge(other._negative);
  }

  Map<String, dynamic> toJson() => {
        'positive': _positive.toJson(),
        'negative': _negative.toJson(),
      };

  factory PnCounter.fromJson(Map<String, dynamic> json) {
    final counter = PnCounter();
    if (json['positive'] != null) {
      counter._positive
          .merge(GCounter.fromJson(json['positive'] as Map<String, dynamic>));
    }
    if (json['negative'] != null) {
      counter._negative
          .merge(GCounter.fromJson(json['negative'] as Map<String, dynamic>));
    }
    return counter;
  }
}

/// OR-Set (Observed-Remove Set) for collections
class OrSet<T> {
  OrSet();

  final Map<String, Set<CrdtId>> _elements = {};
  final Set<CrdtId> _tombstones = {};

  Set<T> get values {
    final result = <T>{};
    for (final entry in _elements.entries) {
      if (entry.value.any((id) => !_tombstones.contains(id))) {
        // Decode the value from the key
        result.add(_decodeValue(entry.key));
      }
    }
    return result;
  }

  bool contains(T element) {
    final key = _encodeValue(element);
    final ids = _elements[key];
    return ids != null && ids.any((id) => !_tombstones.contains(id));
  }

  CrdtId add(T element, CrdtId id) {
    final key = _encodeValue(element);
    _elements.putIfAbsent(key, () => {}).add(id);
    return id;
  }

  void remove(T element) {
    final key = _encodeValue(element);
    final ids = _elements[key];
    if (ids != null) {
      _tombstones.addAll(ids);
    }
  }

  void merge(OrSet<T> other) {
    for (final entry in other._elements.entries) {
      _elements.putIfAbsent(entry.key, () => {}).addAll(entry.value);
    }
    _tombstones.addAll(other._tombstones);
  }

  String _encodeValue(T value) => jsonEncode(value);
  T _decodeValue(String key) => jsonDecode(key) as T;

  Map<String, dynamic> toJson() => {
        'elements': _elements.map(
          (k, v) => MapEntry(k, v.map((id) => id.toJson()).toList()),
        ),
        'tombstones': _tombstones.map((id) => id.toJson()).toList(),
      };

  factory OrSet.fromJson(Map<String, dynamic> json) {
    final set = OrSet<T>();
    final elements = json['elements'] as Map<String, dynamic>?;
    if (elements != null) {
      for (final entry in elements.entries) {
        final ids = (entry.value as List)
            .map((e) => CrdtId.fromJson(e as Map<String, dynamic>))
            .toSet();
        set._elements[entry.key] = ids;
      }
    }
    final tombstones = json['tombstones'] as List?;
    if (tombstones != null) {
      set._tombstones.addAll(
        tombstones.map((e) => CrdtId.fromJson(e as Map<String, dynamic>)),
      );
    }
    return set;
  }
}

/// CRDT Document representing a collaborative project
class CrdtDocument {
  final String id;
  final String name;
  final Map<String, LwwRegister<dynamic>> _registers = {};
  final Map<String, OrSet<String>> _sets = {};
  final Map<String, PnCounter> _counters = {};
  final List<CrdtOperation> _operationLog = [];
  VectorClock _vectorClock = VectorClock();

  CrdtDocument({required this.id, required this.name});

  VectorClock get vectorClock => _vectorClock;
  List<CrdtOperation> get operationLog => List.unmodifiable(_operationLog);

  /// Set a register value
  bool setRegister(String key, dynamic value, CrdtId writeId) {
    _registers.putIfAbsent(key, () => LwwRegister());
    return _registers[key]!.set(value, writeId);
  }

  /// Get a register value
  T? getRegister<T>(String key) {
    return _registers[key]?.value as T?;
  }

  /// Add to a set
  void addToSet(String key, String value, CrdtId id) {
    _sets.putIfAbsent(key, () => OrSet<String>());
    _sets[key]!.add(value, id);
  }

  /// Remove from a set
  void removeFromSet(String key, String value) {
    _sets[key]?.remove(value);
  }

  /// Get set values
  Set<String> getSet(String key) {
    return _sets[key]?.values ?? {};
  }

  /// Increment a counter
  void incrementCounter(String key, String nodeId, [int amount = 1]) {
    _counters.putIfAbsent(key, () => PnCounter());
    _counters[key]!.increment(nodeId, amount);
  }

  /// Decrement a counter
  void decrementCounter(String key, String nodeId, [int amount = 1]) {
    _counters.putIfAbsent(key, () => PnCounter());
    _counters[key]!.decrement(nodeId, amount);
  }

  /// Get counter value
  int getCounter(String key) {
    return _counters[key]?.value ?? 0;
  }

  /// Apply an operation
  bool applyOperation(CrdtOperation op) {
    if (op.isApplied || op.isTombstoned) return false;

    switch (op.type) {
      case CrdtOperationType.insert:
      case CrdtOperationType.update:
        if (op.data != null) {
          for (final entry in op.data!.entries) {
            setRegister('${op.dataType.name}:${op.targetId}:${entry.key}',
                entry.value, op.id);
          }
        }
        break;

      case CrdtOperationType.delete:
        // Mark as tombstoned
        setRegister(
            '${op.dataType.name}:${op.targetId}:_deleted', true, op.id);
        break;

      case CrdtOperationType.move:
        if (op.data != null) {
          final newPosition = op.data!['position'];
          if (newPosition != null) {
            setRegister('${op.dataType.name}:${op.targetId}:position',
                newPosition, op.id);
          }
        }
        break;

      case CrdtOperationType.setAttribute:
        if (op.data != null) {
          final key = op.data!['key'] as String?;
          final value = op.data!['value'];
          if (key != null) {
            setRegister(
                '${op.dataType.name}:${op.targetId}:$key', value, op.id);
          }
        }
        break;

      case CrdtOperationType.removeAttribute:
        if (op.data != null) {
          final key = op.data!['key'] as String?;
          if (key != null) {
            setRegister(
                '${op.dataType.name}:${op.targetId}:$key', null, op.id);
          }
        }
        break;
    }

    op.isApplied = true;
    _operationLog.add(op);
    _vectorClock.merge(op.vectorClock);

    return true;
  }

  /// Merge with another document
  void merge(CrdtDocument other) {
    // Merge registers
    for (final entry in other._registers.entries) {
      _registers.putIfAbsent(entry.key, () => LwwRegister());
      _registers[entry.key]!.merge(entry.value);
    }

    // Merge sets
    for (final entry in other._sets.entries) {
      _sets.putIfAbsent(entry.key, () => OrSet<String>());
      _sets[entry.key]!.merge(entry.value);
    }

    // Merge counters
    for (final entry in other._counters.entries) {
      _counters.putIfAbsent(entry.key, () => PnCounter());
      _counters[entry.key]!.merge(entry.value);
    }

    // Merge vector clocks
    _vectorClock.merge(other._vectorClock);

    // Apply any unapplied operations
    for (final op in other._operationLog) {
      if (!_operationLog.any((o) => o.id == op.id)) {
        applyOperation(op);
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'registers': _registers.map(
          (k, v) => MapEntry(k, v.toJson((val) => val)),
        ),
        'sets': _sets.map((k, v) => MapEntry(k, v.toJson())),
        'counters': _counters.map((k, v) => MapEntry(k, v.toJson())),
        'operationLog': _operationLog.map((o) => o.toJson()).toList(),
        'vectorClock': _vectorClock.toJson(),
      };

  factory CrdtDocument.fromJson(Map<String, dynamic> json) {
    final doc = CrdtDocument(
      id: json['id'] as String,
      name: json['name'] as String,
    );

    final registers = json['registers'] as Map<String, dynamic>?;
    if (registers != null) {
      for (final entry in registers.entries) {
        doc._registers[entry.key] = LwwRegister.fromJson(
          entry.value as Map<String, dynamic>,
          (val) => val,
        );
      }
    }

    final sets = json['sets'] as Map<String, dynamic>?;
    if (sets != null) {
      for (final entry in sets.entries) {
        doc._sets[entry.key] =
            OrSet.fromJson(entry.value as Map<String, dynamic>);
      }
    }

    final counters = json['counters'] as Map<String, dynamic>?;
    if (counters != null) {
      for (final entry in counters.entries) {
        doc._counters[entry.key] =
            PnCounter.fromJson(entry.value as Map<String, dynamic>);
      }
    }

    final operationLog = json['operationLog'] as List?;
    if (operationLog != null) {
      doc._operationLog.addAll(
        operationLog.map((o) => CrdtOperation.fromJson(o as Map<String, dynamic>)),
      );
    }

    if (json['vectorClock'] != null) {
      doc._vectorClock =
          VectorClock.fromJson(json['vectorClock'] as Map<String, dynamic>);
    }

    return doc;
  }
}

/// Sync status
enum CrdtSyncStatus {
  disconnected,
  connecting,
  syncing,
  synced,
  conflictResolution,
  error,
}

/// Sync conflict
class SyncConflict {
  final String id;
  final CrdtOperation localOp;
  final CrdtOperation remoteOp;
  final String description;
  final DateTime detectedAt;
  bool isResolved;
  CrdtOperation? resolution;

  SyncConflict({
    required this.id,
    required this.localOp,
    required this.remoteOp,
    required this.description,
    DateTime? detectedAt,
    this.isResolved = false,
    this.resolution,
  }) : detectedAt = detectedAt ?? DateTime.now();
}

/// CRDT Sync Service - manages collaborative project editing
class CrdtSyncService extends ChangeNotifier {
  static final CrdtSyncService _instance = CrdtSyncService._internal();
  static CrdtSyncService get instance => _instance;

  CrdtSyncService._internal();

  // State
  bool _initialized = false;
  SharedPreferences? _prefs;
  String _nodeId = '';
  int _sequenceCounter = 0;

  // Sync state
  CrdtSyncStatus _status = CrdtSyncStatus.disconnected;
  String? _currentProjectId;
  CrdtDocument? _currentDocument;
  final List<CrdtOperation> _pendingOperations = [];
  final List<SyncConflict> _conflicts = [];

  // Peer tracking
  final Map<String, DateTime> _peerLastSeen = {};
  final Map<String, VectorClock> _peerClocks = {};

  // Statistics
  int _operationsApplied = 0;
  int _operationsSent = 0;
  int _operationsReceived = 0;
  int _mergesPerformed = 0;
  int _conflictsDetected = 0;
  int _conflictsResolved = 0;

  // Stream controllers
  final _operationController = StreamController<CrdtOperation>.broadcast();
  final _syncStatusController = StreamController<CrdtSyncStatus>.broadcast();
  final _conflictController = StreamController<SyncConflict>.broadcast();

  // Getters
  bool get isInitialized => _initialized;
  String get nodeId => _nodeId;
  CrdtSyncStatus get status => _status;
  String? get currentProjectId => _currentProjectId;
  CrdtDocument? get currentDocument => _currentDocument;
  List<CrdtOperation> get pendingOperations =>
      List.unmodifiable(_pendingOperations);
  List<SyncConflict> get conflicts => List.unmodifiable(_conflicts);
  Map<String, DateTime> get peerLastSeen => Map.unmodifiable(_peerLastSeen);
  bool get isConnected => _status == CrdtSyncStatus.synced || _status == CrdtSyncStatus.syncing;
  bool get isSyncing => _status == CrdtSyncStatus.syncing;
  bool get hasConflicts => _conflicts.isNotEmpty;

  // Statistics getters
  int get operationsApplied => _operationsApplied;
  int get operationsSent => _operationsSent;
  int get operationsReceived => _operationsReceived;
  int get mergesPerformed => _mergesPerformed;
  int get conflictsDetected => _conflictsDetected;
  int get conflictsResolved => _conflictsResolved;

  // Streams
  Stream<CrdtOperation> get operationStream => _operationController.stream;
  Stream<CrdtSyncStatus> get syncStatusStream => _syncStatusController.stream;
  Stream<SyncConflict> get conflictStream => _conflictController.stream;

  /// Initialize the service
  Future<void> init() async {
    if (_initialized) return;

    _prefs = await SharedPreferences.getInstance();

    // Generate or load node ID
    _nodeId = _prefs!.getString('crdt_node_id') ?? _generateNodeId();
    await _prefs!.setString('crdt_node_id', _nodeId);

    // Load sequence counter
    _sequenceCounter = _prefs!.getInt('crdt_sequence_counter') ?? 0;

    _initialized = true;
    debugPrint('[CrdtSyncService] Initialized with nodeId: $_nodeId');
    notifyListeners();
  }

  String _generateNodeId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  CrdtId _generateId() {
    _sequenceCounter++;
    _prefs?.setInt('crdt_sequence_counter', _sequenceCounter);
    return CrdtId.generate(_nodeId, _sequenceCounter);
  }

  /// Create a new collaborative document
  CrdtDocument createDocument(String name) {
    final doc = CrdtDocument(
      id: _generateId().toString(),
      name: name,
    );

    _currentDocument = doc;
    _currentProjectId = doc.id;
    _setStatus(CrdtSyncStatus.synced);

    debugPrint('[CrdtSyncService] Created document: ${doc.id}');
    notifyListeners();
    return doc;
  }

  /// Open an existing document
  Future<CrdtDocument?> openDocument(String projectId) async {
    _currentProjectId = projectId;
    _setStatus(CrdtSyncStatus.connecting);

    // In production, this would fetch from server
    // For now, create a new document
    await Future.delayed(const Duration(milliseconds: 500));

    final doc = CrdtDocument(
      id: projectId,
      name: 'Project $projectId',
    );

    _currentDocument = doc;
    _setStatus(CrdtSyncStatus.synced);

    debugPrint('[CrdtSyncService] Opened document: $projectId');
    notifyListeners();
    return doc;
  }

  /// Close current document
  Future<void> closeDocument() async {
    if (_currentDocument != null) {
      // Save locally
      await _saveDocumentLocally(_currentDocument!);
    }

    _currentDocument = null;
    _currentProjectId = null;
    _pendingOperations.clear();
    _setStatus(CrdtSyncStatus.disconnected);

    debugPrint('[CrdtSyncService] Document closed');
    notifyListeners();
  }

  /// Create and apply an operation
  CrdtOperation createOperation({
    required CrdtOperationType type,
    required CrdtDataType dataType,
    required String targetId,
    String? parentId,
    Map<String, dynamic>? data,
  }) {
    if (_currentDocument == null) {
      throw StateError('No document open');
    }

    final id = _generateId();
    final clock = _currentDocument!.vectorClock.copy();
    clock.increment(_nodeId);

    final op = CrdtOperation(
      id: id,
      type: type,
      dataType: dataType,
      targetId: targetId,
      parentId: parentId,
      data: data,
      vectorClock: clock,
      authorId: _nodeId,
    );

    // Apply locally
    _currentDocument!.applyOperation(op);
    _operationsApplied++;

    // Queue for sync
    _pendingOperations.add(op);

    // Broadcast
    _operationController.add(op);

    debugPrint(
        '[CrdtSyncService] Created operation: ${op.type.name} on ${op.dataType.name}:${op.targetId}');
    notifyListeners();

    return op;
  }

  /// Receive an operation from remote peer
  void receiveOperation(CrdtOperation op) {
    if (_currentDocument == null) return;

    _operationsReceived++;

    // Check for conflicts
    if (_currentDocument!.vectorClock.concurrent(op.vectorClock)) {
      final localOps = _currentDocument!.operationLog.where((localOp) =>
          localOp.targetId == op.targetId &&
          localOp.dataType == op.dataType &&
          !localOp.vectorClock.happenedBefore(op.vectorClock));

      for (final localOp in localOps) {
        if (_detectConflict(localOp, op)) {
          final conflict = SyncConflict(
            id: '${localOp.id}-${op.id}',
            localOp: localOp,
            remoteOp: op,
            description: 'Concurrent modification of ${op.dataType.name}:${op.targetId}',
          );
          _conflicts.add(conflict);
          _conflictsDetected++;
          _conflictController.add(conflict);
          _setStatus(CrdtSyncStatus.conflictResolution);
        }
      }
    }

    // Apply operation (CRDTs handle conflicts automatically)
    _currentDocument!.applyOperation(op);

    // Update peer clock
    _peerClocks[op.authorId] = op.vectorClock;
    _peerLastSeen[op.authorId] = DateTime.now();

    debugPrint(
        '[CrdtSyncService] Received operation from ${op.authorId}: ${op.type.name}');
    notifyListeners();
  }

  bool _detectConflict(CrdtOperation localOp, CrdtOperation remoteOp) {
    // Same target and concurrent modifications
    if (localOp.targetId != remoteOp.targetId) return false;
    if (localOp.dataType != remoteOp.dataType) return false;

    // Delete vs update conflict
    if ((localOp.type == CrdtOperationType.delete &&
            remoteOp.type == CrdtOperationType.update) ||
        (localOp.type == CrdtOperationType.update &&
            remoteOp.type == CrdtOperationType.delete)) {
      return true;
    }

    // Same attribute modification
    if (localOp.type == CrdtOperationType.setAttribute &&
        remoteOp.type == CrdtOperationType.setAttribute) {
      final localKey = localOp.data?['key'];
      final remoteKey = remoteOp.data?['key'];
      return localKey == remoteKey;
    }

    return false;
  }

  /// Resolve a conflict manually
  void resolveConflict(String conflictId, CrdtOperation resolution) {
    final conflict = _conflicts.firstWhere(
      (c) => c.id == conflictId,
      orElse: () => throw StateError('Conflict not found'),
    );

    conflict.isResolved = true;
    conflict.resolution = resolution;
    _conflictsResolved++;

    // Apply resolution
    _currentDocument!.applyOperation(resolution);

    // Check if all conflicts resolved
    if (_conflicts.every((c) => c.isResolved)) {
      _setStatus(CrdtSyncStatus.synced);
    }

    debugPrint('[CrdtSyncService] Conflict resolved: $conflictId');
    notifyListeners();
  }

  /// Merge with a remote document
  void mergeDocument(CrdtDocument remoteDoc) {
    if (_currentDocument == null) return;

    _currentDocument!.merge(remoteDoc);
    _mergesPerformed++;

    debugPrint('[CrdtSyncService] Merged with remote document: ${remoteDoc.id}');
    notifyListeners();
  }

  /// Sync pending operations (simulate network sync)
  Future<void> syncPendingOperations() async {
    if (_pendingOperations.isEmpty) return;

    _setStatus(CrdtSyncStatus.syncing);

    try {
      // In production, this would send to server
      await Future.delayed(const Duration(milliseconds: 300));

      _operationsSent += _pendingOperations.length;
      _pendingOperations.clear();

      _setStatus(CrdtSyncStatus.synced);
      debugPrint('[CrdtSyncService] Synced ${_operationsSent} operations');
    } catch (e) {
      _setStatus(CrdtSyncStatus.error);
      debugPrint('[CrdtSyncService] Sync error: $e');
    }

    notifyListeners();
  }

  /// Get document state for specific data type
  Map<String, dynamic> getDataTypeState(CrdtDataType dataType) {
    if (_currentDocument == null) return {};

    final state = <String, dynamic>{};
    final prefix = '${dataType.name}:';

    for (final key in _currentDocument!._registers.keys) {
      if (key.startsWith(prefix)) {
        final parts = key.substring(prefix.length).split(':');
        if (parts.length >= 2) {
          final targetId = parts[0];
          final attribute = parts.sublist(1).join(':');

          state.putIfAbsent(targetId, () => <String, dynamic>{});
          (state[targetId] as Map<String, dynamic>)[attribute] =
              _currentDocument!.getRegister(key);
        }
      }
    }

    return state;
  }

  /// Get sync statistics
  Map<String, dynamic> getStatistics() => {
        'nodeId': _nodeId,
        'status': _status.name,
        'operationsApplied': _operationsApplied,
        'operationsSent': _operationsSent,
        'operationsReceived': _operationsReceived,
        'pendingOperations': _pendingOperations.length,
        'mergesPerformed': _mergesPerformed,
        'conflictsDetected': _conflictsDetected,
        'conflictsResolved': _conflictsResolved,
        'unresolvedConflicts': _conflicts.where((c) => !c.isResolved).length,
        'connectedPeers': _peerLastSeen.length,
      };

  void _setStatus(CrdtSyncStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _syncStatusController.add(newStatus);
    }
  }

  Future<void> _saveDocumentLocally(CrdtDocument doc) async {
    final json = jsonEncode(doc.toJson());
    await _prefs?.setString('crdt_doc_${doc.id}', json);
    debugPrint('[CrdtSyncService] Document saved locally: ${doc.id}');
  }

  Future<CrdtDocument?> _loadDocumentLocally(String docId) async {
    final json = _prefs?.getString('crdt_doc_$docId');
    if (json == null) return null;
    return CrdtDocument.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// Export document to JSON
  String exportDocument() {
    if (_currentDocument == null) {
      throw StateError('No document open');
    }
    return jsonEncode(_currentDocument!.toJson());
  }

  /// Import document from JSON
  CrdtDocument importDocument(String json) {
    final doc =
        CrdtDocument.fromJson(jsonDecode(json) as Map<String, dynamic>);
    _currentDocument = doc;
    _currentProjectId = doc.id;
    _setStatus(CrdtSyncStatus.synced);
    notifyListeners();
    return doc;
  }

  /// Reset statistics
  void resetStatistics() {
    _operationsApplied = 0;
    _operationsSent = 0;
    _operationsReceived = 0;
    _mergesPerformed = 0;
    _conflictsDetected = 0;
    _conflictsResolved = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _operationController.close();
    _syncStatusController.close();
    _conflictController.close();
    super.dispose();
  }
}
