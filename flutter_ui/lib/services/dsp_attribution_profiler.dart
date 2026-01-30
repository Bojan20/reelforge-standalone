/// DSP Load Attribution Profiler
///
/// P1-11: DSP Load Attribution
///
/// Tags DSP operations by stage/event and tracks CPU usage per source.
/// Helps identify which audio events consume the most processing power.
///
/// Attribution levels:
/// 1. Per-Event: Total CPU for each event instance
/// 2. Per-Stage: Aggregate CPU for all events triggered by stage
/// 3. Per-Bus: Total CPU for each audio bus
/// 4. Per-Effect: CPU usage of each DSP effect type
///
/// This helps answer:
/// - Which events are CPU-heavy?
/// - Which stages trigger expensive audio?
/// - Which buses need optimization?
/// - Which DSP effects are bottlenecks?

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// DSP operation type
enum DspOperationType {
  /// Audio file decoding
  decode,
  /// Sample rate conversion
  resample,
  /// Volume/pan processing
  mixing,
  /// EQ filtering
  eq,
  /// Dynamics processing
  dynamics,
  /// Reverb
  reverb,
  /// Delay
  delay,
  /// Other effects
  effects,
  /// Bus summing
  busSum,
  /// Metering
  metering,
}

/// DSP operation attribution
class DspAttribution {
  /// Voice ID or bus ID
  final int id;

  /// Source identifier (event name, stage name, or bus name)
  final String source;

  /// Operation type
  final DspOperationType operation;

  /// Processing time (microseconds)
  final int processingTimeUs;

  /// Timestamp
  final int timestampUs;

  /// Block size (number of samples processed)
  final int blockSize;

  /// Sample rate
  final int sampleRate;

  DspAttribution({
    required this.id,
    required this.source,
    required this.operation,
    required this.processingTimeUs,
    required this.timestampUs,
    required this.blockSize,
    required this.sampleRate,
  });

  /// Processing time in milliseconds
  double get processingTimeMs => processingTimeUs / 1000.0;

  /// CPU load percentage (relative to real-time)
  double get loadPercent {
    if (sampleRate == 0 || blockSize == 0) return 0.0;
    final availableUs = (blockSize / sampleRate) * 1_000_000.0;
    return (processingTimeUs / availableUs) * 100.0;
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'operation': operation.name,
    'processingTimeUs': processingTimeUs,
    'processingTimeMs': processingTimeMs,
    'loadPercent': loadPercent,
    'timestampUs': timestampUs,
    'blockSize': blockSize,
    'sampleRate': sampleRate,
  };
}

/// Aggregated DSP statistics for a source
class SourceDspStats {
  /// Source name (event, stage, or bus)
  final String source;

  /// Total processing time (microseconds)
  int totalProcessingTimeUs = 0;

  /// Number of operations
  int operationCount = 0;

  /// Average processing time per operation
  double avgProcessingTimeUs = 0.0;

  /// Peak processing time
  int peakProcessingTimeUs = 0;

  /// Operations by type
  final Map<DspOperationType, int> operationsByType = {};

  /// Processing time by operation type (microseconds)
  final Map<DspOperationType, int> timeByType = {};

  SourceDspStats(this.source);

  /// Record an operation
  void recordOperation(DspAttribution attr) {
    totalProcessingTimeUs += attr.processingTimeUs;
    operationCount++;

    // Update average
    avgProcessingTimeUs = totalProcessingTimeUs / operationCount;

    // Update peak
    if (attr.processingTimeUs > peakProcessingTimeUs) {
      peakProcessingTimeUs = attr.processingTimeUs;
    }

    // Update by-type counters
    operationsByType[attr.operation] = (operationsByType[attr.operation] ?? 0) + 1;
    timeByType[attr.operation] = (timeByType[attr.operation] ?? 0) + attr.processingTimeUs;
  }

  /// Total processing time in milliseconds
  double get totalProcessingTimeMs => totalProcessingTimeUs / 1000.0;

  /// Average processing time in milliseconds
  double get avgProcessingTimeMs => avgProcessingTimeUs / 1000.0;

  /// Peak processing time in milliseconds
  double get peakProcessingTimeMs => peakProcessingTimeUs / 1000.0;

  /// Get most expensive operation type
  DspOperationType? get mostExpensiveOperation {
    if (timeByType.isEmpty) return null;
    return timeByType.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }
}

/// DSP Attribution Profiler
class DspAttributionProfiler extends ChangeNotifier {
  // ─── Singleton ─────────────────────────────────────────────────────────────
  static DspAttributionProfiler? _instance;
  static DspAttributionProfiler get instance => _instance ??= DspAttributionProfiler._();

  DspAttributionProfiler._();

  // ─── State ─────────────────────────────────────────────────────────────────
  final NativeFFI _ffi = NativeFFI.instance;

  /// All DSP attributions (limited history)
  final List<DspAttribution> _attributions = [];

  /// Per-source statistics
  final Map<String, SourceDspStats> _sourceStats = {};

  /// Max attributions to keep
  static const int maxHistory = 10000;

  /// Is profiling enabled?
  bool _enabled = false;

  /// Polling timer for FFI attribution data
  Timer? _pollTimer;

  // ─── Getters ───────────────────────────────────────────────────────────────

  /// Is profiling enabled?
  bool get enabled => _enabled;

  /// Total attributions recorded
  int get totalAttributions => _attributions.length;

  /// Get all attributions
  List<DspAttribution> get attributions => List.unmodifiable(_attributions);

  /// Get recent attributions
  List<DspAttribution> getRecentAttributions(int count) {
    return _attributions.reversed.take(count).toList();
  }

  /// Get per-source statistics
  Map<String, SourceDspStats> get sourceStats => Map.unmodifiable(_sourceStats);

  /// Get top sources by total CPU time
  List<SourceDspStats> getTopSources(int count) {
    final sorted = _sourceStats.values.toList()
      ..sort((a, b) => b.totalProcessingTimeUs.compareTo(a.totalProcessingTimeUs));
    return sorted.take(count).toList();
  }

  /// Get top sources by peak CPU time
  List<SourceDspStats> getTopPeakSources(int count) {
    final sorted = _sourceStats.values.toList()
      ..sort((a, b) => b.peakProcessingTimeUs.compareTo(a.peakProcessingTimeUs));
    return sorted.take(count).toList();
  }

  /// Get statistics for a specific source
  SourceDspStats? getStatsForSource(String source) {
    return _sourceStats[source];
  }

  /// Get attributions for a specific source
  List<DspAttribution> getAttributionsForSource(String source) {
    return _attributions.where((a) => a.source == source).toList();
  }

  // ─── Control ───────────────────────────────────────────────────────────────

  /// Enable DSP attribution profiling
  void enable() {
    if (_enabled) return;
    _enabled = true;
    _startPolling();
    debugPrint('[DspAttributionProfiler] ✅ Enabled');
    notifyListeners();
  }

  /// Disable DSP attribution profiling
  void disable() {
    if (!_enabled) return;
    _enabled = false;
    _stopPolling();
    debugPrint('[DspAttributionProfiler] ⏸ Disabled');
    notifyListeners();
  }

  /// Clear all statistics
  void clear() {
    _attributions.clear();
    _sourceStats.clear();
    debugPrint('[DspAttributionProfiler] 🧹 Cleared all statistics');
    notifyListeners();
  }

  // ─── Polling ───────────────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    // Poll every 100ms for attribution data from engine
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _pollAttributionData();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _pollAttributionData() {
    // TODO: FFI function to get pending DSP attribution data
    // For now, this is a placeholder for when Rust FFI is implemented
    //
    // Expected FFI function:
    // List<DspAttribution> getDspAttributions();
    //
    // This would return all attribution data since last poll
  }

  // ─── Recording ─────────────────────────────────────────────────────────────

  /// Record a DSP operation
  ///
  /// This should be called from the audio engine (via FFI) whenever
  /// a DSP operation completes.
  void recordOperation({
    required int id,
    required String source,
    required DspOperationType operation,
    required int processingTimeUs,
    required int blockSize,
    required int sampleRate,
  }) {
    if (!_enabled) return;

    final attribution = DspAttribution(
      id: id,
      source: source,
      operation: operation,
      processingTimeUs: processingTimeUs,
      timestampUs: DateTime.now().microsecondsSinceEpoch,
      blockSize: blockSize,
      sampleRate: sampleRate,
    );

    // Add to history
    _attributions.add(attribution);
    if (_attributions.length > maxHistory) {
      _attributions.removeAt(0);
    }

    // Update source statistics
    final stats = _sourceStats.putIfAbsent(source, () => SourceDspStats(source));
    stats.recordOperation(attribution);

    // Log expensive operations (> 10% CPU)
    if (attribution.loadPercent > 10.0) {
      debugPrint('[DspAttributionProfiler] ⚠️ EXPENSIVE: '
          '$source (${operation.name}) consumed ${attribution.loadPercent.toStringAsFixed(1)}% CPU');
    }

    notifyListeners();
  }

  // ─── Analysis ──────────────────────────────────────────────────────────────

  /// Get total CPU load percentage across all sources
  double getTotalCpuLoad() {
    if (_attributions.isEmpty) return 0.0;

    // Calculate from recent attributions (last 1 second)
    final now = DateTime.now().microsecondsSinceEpoch;
    final oneSecondAgo = now - 1000000;

    final recentAttrs = _attributions.where((a) => a.timestampUs >= oneSecondAgo);
    if (recentAttrs.isEmpty) return 0.0;

    final totalTimeUs = recentAttrs.fold<int>(0, (sum, a) => sum + a.processingTimeUs);
    final totalAvailableUs = recentAttrs.fold<int>(0, (sum, a) {
      return sum + ((a.blockSize / a.sampleRate) * 1_000_000).toInt();
    });

    if (totalAvailableUs == 0) return 0.0;

    return (totalTimeUs / totalAvailableUs) * 100.0;
  }

  /// Get CPU load by operation type
  Map<DspOperationType, double> getCpuLoadByOperation() {
    final result = <DspOperationType, double>{};

    for (final stats in _sourceStats.values) {
      for (final entry in stats.timeByType.entries) {
        result[entry.key] = (result[entry.key] ?? 0.0) + entry.value / 1000.0;
      }
    }

    return result;
  }

  /// Get CPU load by bus
  Map<String, double> getCpuLoadByBus() {
    final result = <String, double>{};

    for (final entry in _sourceStats.entries) {
      if (entry.key.startsWith('bus_')) {
        result[entry.key] = entry.value.totalProcessingTimeMs;
      }
    }

    return result;
  }

  // ─── Export ────────────────────────────────────────────────────────────────

  /// Export attributions to JSON
  String exportToJson() {
    final data = {
      'enabled': _enabled,
      'totalAttributions': totalAttributions,
      'totalCpuLoad': getTotalCpuLoad(),
      'attributions': _attributions.map((a) => a.toJson()).toList(),
      'sourceStats': _sourceStats.map((key, value) => MapEntry(key, {
        'source': value.source,
        'totalTimeMs': value.totalProcessingTimeMs,
        'avgTimeMs': value.avgProcessingTimeMs,
        'peakTimeMs': value.peakProcessingTimeMs,
        'operationCount': value.operationCount,
        'mostExpensive': value.mostExpensiveOperation?.name,
      })),
      'cpuByOperation': getCpuLoadByOperation().map((k, v) => MapEntry(k.name, v)),
      'cpuByBus': getCpuLoadByBus(),
    };

    return data.toString();
  }

  /// Export to CSV
  String exportToCsv() {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('timestamp_us,id,source,operation,processing_us,processing_ms,load_percent,block_size,sample_rate');

    // Data rows
    for (final attr in _attributions) {
      buffer.writeln(
        '${attr.timestampUs},'
        '${attr.id},'
        '"${attr.source}",'
        '${attr.operation.name},'
        '${attr.processingTimeUs},'
        '${attr.processingTimeMs.toStringAsFixed(2)},'
        '${attr.loadPercent.toStringAsFixed(2)},'
        '${attr.blockSize},'
        '${attr.sampleRate}'
      );
    }

    return buffer.toString();
  }
}
