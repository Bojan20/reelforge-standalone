/// Event Profiler Provider
///
/// Extracted from MiddlewareProvider as part of Provider Decomposition.
/// Tracks audio events for profiling, debugging, and latency analysis.
///
/// Provides:
/// - Event recording (voice start/stop/steal, errors, etc.)
/// - Latency tracking (average, max)
/// - Events-per-second statistics
/// - Event export for analysis
/// - DSP load metrics from Rust engine (via FFI)
///
/// Integration: Syncs with Rust DSP profiler via NativeFFI

import 'package:flutter/foundation.dart';
import '../../models/advanced_middleware_models.dart';
import '../../src/rust/native_ffi.dart';

/// Provider for event profiling and debugging
class EventProfilerProvider extends ChangeNotifier {
  final NativeFFI? _ffi;

  /// Internal event profiler
  late EventProfiler _profiler;

  /// Max events to keep in memory
  final int maxEvents;

  /// Cached DSP load from engine
  double _dspLoad = 0.0;

  /// Cached stage breakdown from engine
  Map<String, double> _stageBreakdown = {};

  /// Overload count from engine
  int _overloadCount = 0;

  EventProfilerProvider({
    NativeFFI? ffi,
    this.maxEvents = 10000,
  }) : _ffi = ffi {
    _profiler = EventProfiler(maxEvents: maxEvents);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get profiler statistics (getter)
  ProfilerStats get stats => _profiler.getStats();

  /// Get profiler statistics (method for API compatibility)
  ProfilerStats getStats() => _profiler.getStats();

  /// Total events recorded
  int get totalEvents => _profiler.getStats().totalEvents;

  /// Current events per second
  int get eventsPerSecond => _profiler.getStats().eventsPerSecond;

  /// Peak events per second
  int get peakEventsPerSecond => _profiler.getStats().peakEventsPerSecond;

  /// Average latency in microseconds
  double get avgLatencyUs => _profiler.getStats().avgLatencyUs;

  /// Maximum latency in microseconds
  double get maxLatencyUs => _profiler.getStats().maxLatencyUs;

  /// Average latency in milliseconds
  double get avgLatencyMs => avgLatencyUs / 1000;

  /// Maximum latency in milliseconds
  double get maxLatencyMs => maxLatencyUs / 1000;

  /// Voice start count
  int get voiceStarts => _profiler.getStats().voiceStarts;

  /// Voice stop count
  int get voiceStops => _profiler.getStats().voiceStops;

  /// Voice steal count
  int get voiceSteals => _profiler.getStats().voiceSteals;

  /// Error count
  int get errors => _profiler.getStats().errors;

  // ═══════════════════════════════════════════════════════════════════════════
  // DSP PROFILER (FFI)
  // ═══════════════════════════════════════════════════════════════════════════

  /// DSP load percentage (0-100) from Rust engine
  double get dspLoad => _dspLoad;

  /// DSP stage breakdown (input, mixing, effects, metering, output percentages)
  Map<String, double> get stageBreakdown => Map.unmodifiable(_stageBreakdown);

  /// Total DSP overload count from engine
  int get overloadCount => _overloadCount;

  /// Check if FFI is available
  bool get hasFfiConnection => _ffi != null;

  /// Sync DSP profiler stats from Rust engine
  void syncFromEngine() {
    if (_ffi == null) return;

    try {
      _dspLoad = _ffi.profilerGetCurrentLoad();
      _stageBreakdown = _ffi.profilerGetStageBreakdown();
      _overloadCount = _ffi.profilerGetOverloadCount();
      notifyListeners();
    } catch (e) {
      debugPrint('[EventProfilerProvider] FFI sync error: $e');
    }
  }

  /// Get DSP load history from engine
  List<double> getDspLoadHistory({int count = 100}) {
    if (_ffi == null) return [];
    try {
      return _ffi.profilerGetLoadHistory(count: count);
    } catch (e) {
      return [];
    }
  }

  /// Get full DSP profiler stats from engine
  Map<String, dynamic>? getEngineDspStats() {
    if (_ffi == null) return null;
    try {
      return _ffi.profilerGetStats();
    } catch (e) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT RECORDING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Record a profiler event
  void record({
    required ProfilerEventType type,
    required String description,
    int? soundId,
    int? busId,
    int? voiceId,
    double? value,
    int latencyUs = 0,
  }) {
    _profiler.record(
      type: type,
      description: description,
      soundId: soundId,
      busId: busId,
      voiceId: voiceId,
      value: value,
      latencyUs: latencyUs,
    );
    // Note: We don't call notifyListeners() on every event for performance
    // UI should poll stats periodically instead
  }

  /// Record voice start event
  void recordVoiceStart({
    required String description,
    int? soundId,
    int? busId,
    int? voiceId,
    int latencyUs = 0,
  }) {
    record(
      type: ProfilerEventType.voiceStart,
      description: description,
      soundId: soundId,
      busId: busId,
      voiceId: voiceId,
      latencyUs: latencyUs,
    );
  }

  /// Record voice stop event
  void recordVoiceStop({
    required String description,
    int? soundId,
    int? voiceId,
  }) {
    record(
      type: ProfilerEventType.voiceStop,
      description: description,
      soundId: soundId,
      voiceId: voiceId,
    );
  }

  /// Record voice steal event
  void recordVoiceSteal({
    required String description,
    int? soundId,
    int? busId,
    int? voiceId,
    int latencyUs = 0,
  }) {
    record(
      type: ProfilerEventType.voiceSteal,
      description: description,
      soundId: soundId,
      busId: busId,
      voiceId: voiceId,
      latencyUs: latencyUs,
    );
  }

  /// Record error event
  void recordError({
    required String description,
    int? soundId,
    int? busId,
  }) {
    record(
      type: ProfilerEventType.error,
      description: description,
      soundId: soundId,
      busId: busId,
    );
  }

  /// Record state change event
  void recordStateChange({
    required String description,
    double? value,
  }) {
    record(
      type: ProfilerEventType.stateChange,
      description: description,
      value: value,
    );
  }

  /// Record RTPC change event
  void recordRtpcChange({
    required String description,
    double? value,
    int? busId,
  }) {
    record(
      type: ProfilerEventType.rtpcChange,
      description: description,
      value: value,
      busId: busId,
    );
  }

  /// Record bank load event
  void recordBankLoad({
    required String description,
    int latencyUs = 0,
  }) {
    record(
      type: ProfilerEventType.bankLoad,
      description: description,
      latencyUs: latencyUs,
    );
  }

  /// Record bank unload event
  void recordBankUnload({
    required String description,
  }) {
    record(
      type: ProfilerEventType.bankUnload,
      description: description,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT QUERIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get recent events
  List<ProfilerEvent> getRecentEvents({int count = 100}) {
    return _profiler.getRecentEvents(count: count);
  }

  /// Get events by type
  List<ProfilerEvent> getEventsByType(ProfilerEventType type, {int count = 100}) {
    return _profiler.getRecentEvents(count: count)
        .where((e) => e.type == type)
        .toList();
  }

  /// Get error events
  List<ProfilerEvent> getErrorEvents({int count = 100}) {
    return getEventsByType(ProfilerEventType.error, count: count);
  }

  /// Get events within time range
  List<ProfilerEvent> getEventsInRange(DateTime start, DateTime end) {
    return _profiler.getRecentEvents(count: maxEvents)
        .where((e) => e.timestamp.isAfter(start) && e.timestamp.isBefore(end))
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LATENCY ANALYSIS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get latency percentiles from recent events
  Map<String, double> getLatencyPercentiles({int count = 1000}) {
    final events = _profiler.getRecentEvents(count: count);
    if (events.isEmpty) {
      return {'p50': 0, 'p90': 0, 'p95': 0, 'p99': 0};
    }

    final latencies = events
        .where((e) => e.latencyUs > 0)
        .map((e) => e.latencyUs.toDouble())
        .toList()
      ..sort();

    if (latencies.isEmpty) {
      return {'p50': 0, 'p90': 0, 'p95': 0, 'p99': 0};
    }

    return {
      'p50': _percentile(latencies, 0.50),
      'p90': _percentile(latencies, 0.90),
      'p95': _percentile(latencies, 0.95),
      'p99': _percentile(latencies, 0.99),
    };
  }

  double _percentile(List<double> sorted, double p) {
    if (sorted.isEmpty) return 0;
    final index = (sorted.length * p).floor();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Clear all events
  void clear() {
    _profiler.clear();
    notifyListeners();
  }

  /// Reset profiler
  void reset() {
    _profiler = EventProfiler(maxEvents: maxEvents);
    notifyListeners();
  }

  /// Notify listeners (for periodic UI updates)
  void refresh() {
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export events to JSON
  List<Map<String, dynamic>> exportEventsToJson({int count = 1000}) {
    return _profiler.getRecentEvents(count: count).map((e) => {
      'eventId': e.eventId,
      'timestamp': e.timestamp.toIso8601String(),
      'type': e.type.index,
      'typeName': e.type.name,
      'description': e.description,
      'soundId': e.soundId,
      'busId': e.busId,
      'voiceId': e.voiceId,
      'value': e.value,
      'latencyUs': e.latencyUs,
    }).toList();
  }

  /// Export stats to JSON
  Map<String, dynamic> exportStatsToJson() {
    final s = stats;
    return {
      'totalEvents': s.totalEvents,
      'eventsPerSecond': s.eventsPerSecond,
      'peakEventsPerSecond': s.peakEventsPerSecond,
      'avgLatencyUs': s.avgLatencyUs,
      'maxLatencyUs': s.maxLatencyUs,
      'voiceStarts': s.voiceStarts,
      'voiceStops': s.voiceStops,
      'voiceSteals': s.voiceSteals,
      'errors': s.errors,
    };
  }

  /// Export full report to JSON
  Map<String, dynamic> exportReportToJson({int eventCount = 1000}) {
    return {
      'stats': exportStatsToJson(),
      'percentiles': getLatencyPercentiles(count: eventCount),
      'events': exportEventsToJson(count: eventCount),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CSV EXPORT (M3 Sprint - P1)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export events to CSV format
  ///
  /// Format: timestamp,eventId,type,description,soundId,busId,voiceId,latencyUs
  /// Example: 2026-01-23T12:34:56.789,1,voiceStart,SPIN_START,101,2,5,450
  String exportToCSV({int count = 1000, bool includeHeader = true}) {
    final buffer = StringBuffer();

    // Header row
    if (includeHeader) {
      buffer.writeln('timestamp,eventId,type,description,soundId,busId,voiceId,latencyUs');
    }

    // Data rows
    final events = _profiler.getRecentEvents(count: count);
    for (final event in events) {
      buffer.writeln(_eventToCSVRow(event));
    }

    return buffer.toString();
  }

  /// Convert a single event to CSV row
  String _eventToCSVRow(ProfilerEvent event) {
    // Escape description if it contains commas or quotes
    String description = event.description;
    if (description.contains(',') || description.contains('"')) {
      description = '"${description.replaceAll('"', '""')}"';
    }

    return [
      event.timestamp.toIso8601String(),
      event.eventId.toString(),
      event.type.name,
      description,
      event.soundId?.toString() ?? '',
      event.busId?.toString() ?? '',
      event.voiceId?.toString() ?? '',
      event.latencyUs.toString(),
    ].join(',');
  }

  /// Export events to CSV with custom columns
  ///
  /// [columns] specifies which columns to include in order.
  /// Available: timestamp, eventId, type, description, soundId, busId, voiceId, latencyUs, value
  String exportToCSVCustom({
    int count = 1000,
    bool includeHeader = true,
    List<String> columns = const [
      'timestamp', 'eventId', 'type', 'description',
      'soundId', 'busId', 'voiceId', 'latencyUs'
    ],
  }) {
    final buffer = StringBuffer();

    // Header row
    if (includeHeader) {
      buffer.writeln(columns.join(','));
    }

    // Data rows
    final events = _profiler.getRecentEvents(count: count);
    for (final event in events) {
      buffer.writeln(_eventToCSVRowCustom(event, columns));
    }

    return buffer.toString();
  }

  String _eventToCSVRowCustom(ProfilerEvent event, List<String> columns) {
    final values = <String>[];

    for (final col in columns) {
      switch (col) {
        case 'timestamp':
          values.add(event.timestamp.toIso8601String());
          break;
        case 'eventId':
          values.add(event.eventId.toString());
          break;
        case 'type':
          values.add(event.type.name);
          break;
        case 'description':
          String desc = event.description;
          if (desc.contains(',') || desc.contains('"')) {
            desc = '"${desc.replaceAll('"', '""')}"';
          }
          values.add(desc);
          break;
        case 'soundId':
          values.add(event.soundId?.toString() ?? '');
          break;
        case 'busId':
          values.add(event.busId?.toString() ?? '');
          break;
        case 'voiceId':
          values.add(event.voiceId?.toString() ?? '');
          break;
        case 'latencyUs':
          values.add(event.latencyUs.toString());
          break;
        case 'value':
          values.add(event.value?.toString() ?? '');
          break;
        default:
          values.add('');
      }
    }

    return values.join(',');
  }

  /// Get CSV export summary (row count, estimated file size)
  Map<String, dynamic> getCSVExportInfo({int count = 1000}) {
    final events = _profiler.getRecentEvents(count: count);
    final eventCount = events.length;

    // Estimate file size (header + avg ~100 bytes per row)
    const headerSize = 65; // "timestamp,eventId,type,..." header
    const avgRowSize = 100;
    final estimatedBytes = headerSize + (eventCount * avgRowSize);

    return {
      'eventCount': eventCount,
      'estimatedSizeBytes': estimatedBytes,
      'estimatedSizeKB': (estimatedBytes / 1024).toStringAsFixed(1),
    };
  }
}
