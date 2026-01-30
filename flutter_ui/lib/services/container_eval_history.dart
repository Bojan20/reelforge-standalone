/// Container Evaluation History Tracking
///
/// P2-17: Tracks container evaluations for QA and debugging.
/// Exports history to CSV/JSON for analysis.

import 'dart:convert';

/// Container evaluation history entry
class ContainerEvalHistoryEntry {
  /// Timestamp (ms since epoch)
  final int timestampMs;

  /// Container type ('blend', 'random', 'sequence')
  final String containerType;

  /// Container ID
  final int containerId;

  /// Container name (for readability)
  final String? containerName;

  /// Evaluation result (depends on type)
  /// - Blend: Map of childId to volume
  /// - Random: selected childId
  /// - Sequence: step index
  final dynamic result;

  /// Context data (RTPC values, game state, etc.)
  final Map<String, dynamic>? context;

  const ContainerEvalHistoryEntry({
    required this.timestampMs,
    required this.containerType,
    required this.containerId,
    this.containerName,
    required this.result,
    this.context,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'timestampMs': timestampMs,
    'containerType': containerType,
    'containerId': containerId,
    'containerName': containerName,
    'result': result,
    'context': context,
  };

  /// Convert to CSV row
  String toCsvRow() {
    final resultStr = result is Map
        ? (result as Map).entries.map((e) => '${e.key}:${e.value}').join(';')
        : result.toString();

    final contextStr = context != null
        ? context!.entries.map((e) => '${e.key}=${e.value}').join(';')
        : '';

    return '$timestampMs,$containerType,$containerId,$containerName,$resultStr,$contextStr';
  }

  @override
  String toString() => '[$containerType $containerId] at $timestampMs: $result';
}

/// Container evaluation history manager
class ContainerEvalHistory {
  final List<ContainerEvalHistoryEntry> _entries = [];
  bool _tracking = false;
  int _maxSize = 1000;

  /// Start tracking evaluations
  void startTracking({int maxSize = 1000}) {
    _tracking = true;
    _maxSize = maxSize;
  }

  /// Stop tracking evaluations
  void stopTracking() {
    _tracking = false;
  }

  /// Check if tracking is enabled
  bool get isTracking => _tracking;

  /// Get maximum history size
  int get maxSize => _maxSize;

  /// Record an evaluation
  void record(ContainerEvalHistoryEntry entry) {
    if (!_tracking) return;

    _entries.add(entry);

    // Trim to max size (keep most recent)
    if (_entries.length > _maxSize) {
      _entries.removeRange(0, _entries.length - _maxSize);
    }
  }

  /// Clear all history
  void clear() {
    _entries.clear();
  }

  /// Get all entries
  List<ContainerEvalHistoryEntry> get entries => List.unmodifiable(_entries);

  /// Get entries count
  int get count => _entries.length;

  /// Get entries for specific container
  List<ContainerEvalHistoryEntry> getEntriesForContainer(int containerId) {
    return _entries.where((e) => e.containerId == containerId).toList();
  }

  /// Get entries by type
  List<ContainerEvalHistoryEntry> getEntriesByType(String type) {
    return _entries.where((e) => e.containerType == type).toList();
  }

  /// Get entries in time range
  List<ContainerEvalHistoryEntry> getEntriesInRange(int startMs, int endMs) {
    return _entries
        .where((e) => e.timestampMs >= startMs && e.timestampMs <= endMs)
        .toList();
  }

  /// Export to JSON
  String exportToJson({bool pretty = false}) {
    final data = {
      'tracking': _tracking,
      'maxSize': _maxSize,
      'count': _entries.length,
      'entries': _entries.map((e) => e.toJson()).toList(),
    };

    return pretty
        ? const JsonEncoder.withIndent('  ').convert(data)
        : jsonEncode(data);
  }

  /// Export to CSV
  String exportToCsv() {
    final sb = StringBuffer();

    // Header
    sb.writeln('TimestampMs,ContainerType,ContainerId,ContainerName,Result,Context');

    // Rows
    for (final entry in _entries) {
      sb.writeln(entry.toCsvRow());
    }

    return sb.toString();
  }

  /// Generate statistics report
  String generateReport() {
    if (_entries.isEmpty) {
      return 'No evaluations recorded (tracking: ${_tracking ? 'ON' : 'OFF'})';
    }

    final sb = StringBuffer();
    sb.writeln('=== Container Evaluation History Report ===');
    sb.writeln('Tracking: ${_tracking ? 'ON' : 'OFF'}');
    sb.writeln('Total evaluations: ${_entries.length}');
    sb.writeln('Max size: $_maxSize');
    sb.writeln('');

    // Group by container type
    final byType = <String, int>{};
    for (final entry in _entries) {
      byType[entry.containerType] = (byType[entry.containerType] ?? 0) + 1;
    }

    sb.writeln('By Type:');
    for (final type in byType.keys) {
      sb.writeln('  $type: ${byType[type]}');
    }
    sb.writeln('');

    // Group by container ID
    final byId = <int, int>{};
    for (final entry in _entries) {
      byId[entry.containerId] = (byId[entry.containerId] ?? 0) + 1;
    }

    sb.writeln('By Container (top 10):');
    final sortedIds = byId.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sortedIds.take(10)) {
      sb.writeln('  Container ${entry.key}: ${entry.value} evaluations');
    }
    sb.writeln('');

    // Time range
    if (_entries.isNotEmpty) {
      final firstMs = _entries.first.timestampMs;
      final lastMs = _entries.last.timestampMs;
      final durationMs = lastMs - firstMs;
      sb.writeln('Time Range:');
      sb.writeln('  First: ${DateTime.fromMillisecondsSinceEpoch(firstMs)}');
      sb.writeln('  Last: ${DateTime.fromMillisecondsSinceEpoch(lastMs)}');
      sb.writeln('  Duration: ${(durationMs / 1000).toStringAsFixed(1)}s');
      sb.writeln('  Rate: ${(_entries.length / (durationMs / 1000)).toStringAsFixed(1)} evals/sec');
    }

    return sb.toString();
  }
}

/// Global singleton instance
final containerEvalHistory = ContainerEvalHistory();
