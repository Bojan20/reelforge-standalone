/// Container Evaluation Logger
///
/// Logs all container evaluations for debugging and QA:
/// - Blend container RTPC evaluations
/// - Random container selections (with seed if deterministic)
/// - Sequence container steps
/// - Export to JSON for analysis
///
/// Keeps last 100 evaluations in memory (ring buffer)
library;

import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Type of container evaluation
enum ContainerEvaluationType {
  blend,
  random,
  sequence,
}

/// Container evaluation log entry
class ContainerEvaluationLog {
  final int id; // Unique log ID
  final DateTime timestamp;
  final ContainerEvaluationType type;
  final int containerId;
  final String containerName;
  final Map<String, dynamic> evaluation; // Type-specific data

  ContainerEvaluationLog({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.containerId,
    required this.containerName,
    required this.evaluation,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        'containerId': containerId,
        'containerName': containerName,
        'evaluation': evaluation,
      };

  factory ContainerEvaluationLog.fromJson(Map<String, dynamic> json) {
    return ContainerEvaluationLog(
      id: json['id'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: ContainerEvaluationType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => ContainerEvaluationType.blend,
      ),
      containerId: json['containerId'] as int,
      containerName: json['containerName'] as String,
      evaluation: json['evaluation'] as Map<String, dynamic>,
    );
  }

  String get summary {
    switch (type) {
      case ContainerEvaluationType.blend:
        final rtpcValue = evaluation['rtpcValue'] as double? ?? 0.0;
        final activeChildren = (evaluation['activeChildren'] as List?)?.length ?? 0;
        return 'Blend: RTPC=$rtpcValue, $activeChildren active';
      case ContainerEvaluationType.random:
        final selectedId = evaluation['selectedChildId'] as int? ?? -1;
        final isDeterministic = evaluation['isDeterministic'] as bool? ?? false;
        final seed = evaluation['seed'] as int?;
        return 'Random: child=$selectedId${isDeterministic && seed != null ? ', seed=$seed' : ''}';
      case ContainerEvaluationType.sequence:
        final stepIndex = evaluation['stepIndex'] as int? ?? 0;
        final totalSteps = evaluation['totalSteps'] as int? ?? 0;
        return 'Sequence: step $stepIndex/$totalSteps';
    }
  }
}

/// Container Evaluation Logger (Singleton)
class ContainerEvaluationLogger {
  static final ContainerEvaluationLogger _instance = ContainerEvaluationLogger._internal();
  factory ContainerEvaluationLogger() => _instance;
  ContainerEvaluationLogger._internal();

  static ContainerEvaluationLogger get instance => _instance;

  // Ring buffer for evaluations (max 100)
  static const int _maxEntries = 100;
  final Queue<ContainerEvaluationLog> _logs = Queue();
  int _nextId = 0;

  // Listeners for real-time updates
  final List<VoidCallback> _listeners = [];

  /// Add a listener for log updates
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Remove a listener
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Notify all listeners
  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Log a blend container evaluation
  void logBlendEvaluation({
    required int containerId,
    required String containerName,
    required double rtpcValue,
    required Map<int, double> activeChildren, // childId → volume
  }) {
    final log = ContainerEvaluationLog(
      id: _nextId++,
      timestamp: DateTime.now(),
      type: ContainerEvaluationType.blend,
      containerId: containerId,
      containerName: containerName,
      evaluation: {
        'rtpcValue': rtpcValue,
        'activeChildren': [
          for (final entry in activeChildren.entries)
            {
              'childId': entry.key,
              'volume': entry.value,
            },
        ],
      },
    );

    _addLog(log);
  }

  /// Log a random container evaluation
  void logRandomEvaluation({
    required int containerId,
    required String containerName,
    required int selectedChildId,
    required double selectedWeight,
    required int totalChildren,
    bool isDeterministic = false,
    int? seed,
  }) {
    final log = ContainerEvaluationLog(
      id: _nextId++,
      timestamp: DateTime.now(),
      type: ContainerEvaluationType.random,
      containerId: containerId,
      containerName: containerName,
      evaluation: {
        'selectedChildId': selectedChildId,
        'selectedWeight': selectedWeight,
        'totalChildren': totalChildren,
        'isDeterministic': isDeterministic,
        if (seed != null) 'seed': seed,
      },
    );

    _addLog(log);
  }

  /// Log a sequence container evaluation
  void logSequenceEvaluation({
    required int containerId,
    required String containerName,
    required int stepIndex,
    required int totalSteps,
    required int playedChildId,
    required double stepDurationMs,
  }) {
    final log = ContainerEvaluationLog(
      id: _nextId++,
      timestamp: DateTime.now(),
      type: ContainerEvaluationType.sequence,
      containerId: containerId,
      containerName: containerName,
      evaluation: {
        'stepIndex': stepIndex,
        'totalSteps': totalSteps,
        'playedChildId': playedChildId,
        'stepDurationMs': stepDurationMs,
      },
    );

    _addLog(log);
  }

  /// Add log to ring buffer
  void _addLog(ContainerEvaluationLog log) {
    _logs.add(log);

    // Remove oldest if exceeds max
    while (_logs.length > _maxEntries) {
      _logs.removeFirst();
    }

    _notifyListeners();

    // Debug print
    if (kDebugMode) {
      debugPrint('[ContainerEval] ${log.summary}');
    }
  }

  /// Get all logs (newest first)
  List<ContainerEvaluationLog> get logs => _logs.toList().reversed.toList();

  /// Get logs filtered by type
  List<ContainerEvaluationLog> getLogsByType(ContainerEvaluationType type) {
    return _logs.where((log) => log.type == type).toList().reversed.toList();
  }

  /// Get logs filtered by container ID
  List<ContainerEvaluationLog> getLogsByContainerId(int containerId) {
    return _logs.where((log) => log.containerId == containerId).toList().reversed.toList();
  }

  /// Get last N logs
  List<ContainerEvaluationLog> getLastN(int count) {
    final list = _logs.toList().reversed.toList();
    return list.take(count).toList();
  }

  /// Clear all logs
  void clear() {
    _logs.clear();
    _nextId = 0;
    _notifyListeners();
  }

  /// Export all logs to JSON
  String exportToJson() {
    final data = {
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'totalLogs': _logs.length,
      'logs': [
        for (final log in _logs) log.toJson(),
      ],
    };

    return jsonEncode(data);
  }

  /// Import logs from JSON (for testing/replay)
  void importFromJson(String jsonString) {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final logsList = data['logs'] as List?;

      if (logsList != null) {
        _logs.clear();
        for (final logJson in logsList) {
          final log = ContainerEvaluationLog.fromJson(logJson as Map<String, dynamic>);
          _logs.add(log);
          _nextId = log.id + 1; // Update next ID
        }

        _notifyListeners();
      }
    } catch (e) {
      debugPrint('[ContainerEvaluationLogger] Import error: $e');
    }
  }

  /// Get statistics
  ContainerEvaluationStats get stats {
    final blendCount = _logs.where((l) => l.type == ContainerEvaluationType.blend).length;
    final randomCount = _logs.where((l) => l.type == ContainerEvaluationType.random).length;
    final sequenceCount = _logs.where((l) => l.type == ContainerEvaluationType.sequence).length;

    final uniqueContainerIds = _logs.map((l) => l.containerId).toSet();

    return ContainerEvaluationStats(
      totalEvaluations: _logs.length,
      blendEvaluations: blendCount,
      randomEvaluations: randomCount,
      sequenceEvaluations: sequenceCount,
      uniqueContainers: uniqueContainerIds.length,
      oldestTimestamp: _logs.isEmpty ? null : _logs.first.timestamp,
      newestTimestamp: _logs.isEmpty ? null : _logs.last.timestamp,
    );
  }
}

/// Statistics about container evaluations
class ContainerEvaluationStats {
  final int totalEvaluations;
  final int blendEvaluations;
  final int randomEvaluations;
  final int sequenceEvaluations;
  final int uniqueContainers;
  final DateTime? oldestTimestamp;
  final DateTime? newestTimestamp;

  ContainerEvaluationStats({
    required this.totalEvaluations,
    required this.blendEvaluations,
    required this.randomEvaluations,
    required this.sequenceEvaluations,
    required this.uniqueContainers,
    this.oldestTimestamp,
    this.newestTimestamp,
  });

  Duration? get timespan {
    if (oldestTimestamp == null || newestTimestamp == null) return null;
    return newestTimestamp!.difference(oldestTimestamp!);
  }
}
