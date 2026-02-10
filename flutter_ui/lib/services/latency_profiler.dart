/// Latency Profiler Service
///
/// P1-08: End-to-End Latency Measurement
///
/// Tracks complete latency chain from Dart trigger to audio output:
/// - Dart→FFI call overhead
/// - FFI→Engine processing time
/// - Engine→Audio thread scheduling
/// - Audio buffer latency
///
/// Target: < 5ms total latency validation
///
/// Architecture:
/// ```
/// triggerStage()
///   ↓ [Dart overhead]
/// FFI call
///   ↓ [FFI marshalling]
/// Rust engine
///   ↓ [Engine processing]
/// Audio thread
///   ↓ [Buffer latency]
/// Speaker output
/// ```

import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// Latency measurement point
enum LatencyPoint {
  /// Start: Dart trigger call
  dartTrigger,
  /// End: FFI function returns
  ffiReturn,
  /// End: Engine confirms processing
  engineProcessed,
  /// End: Audio thread scheduled
  audioScheduled,
  /// End: First sample output
  audioOutput,
}

/// Single latency measurement
class LatencyMeasurement {
  /// Measurement ID
  final String id;

  /// Stage or event name that triggered audio
  final String source;

  /// Dart trigger timestamp (microseconds)
  final int dartTriggerUs;

  /// FFI return timestamp (microseconds)
  final int? ffiReturnUs;

  /// Engine processed timestamp (microseconds)
  final int? engineProcessedUs;

  /// Audio scheduled timestamp (microseconds)
  final int? audioScheduledUs;

  /// Audio output timestamp (microseconds)
  final int? audioOutputUs;

  LatencyMeasurement({
    required this.id,
    required this.source,
    required this.dartTriggerUs,
    this.ffiReturnUs,
    this.engineProcessedUs,
    this.audioScheduledUs,
    this.audioOutputUs,
  });

  /// Total latency (Dart trigger → audio output)
  int? get totalLatencyUs {
    if (audioOutputUs == null) return null;
    return audioOutputUs! - dartTriggerUs;
  }

  /// Dart→FFI latency
  int? get dartToFfiUs {
    if (ffiReturnUs == null) return null;
    return ffiReturnUs! - dartTriggerUs;
  }

  /// FFI→Engine latency
  int? get ffiToEngineUs {
    if (engineProcessedUs == null || ffiReturnUs == null) return null;
    return engineProcessedUs! - ffiReturnUs!;
  }

  /// Engine→Audio scheduling latency
  int? get engineToScheduledUs {
    if (audioScheduledUs == null || engineProcessedUs == null) return null;
    return audioScheduledUs! - engineProcessedUs!;
  }

  /// Audio scheduled→output latency (buffer latency)
  int? get scheduledToOutputUs {
    if (audioOutputUs == null || audioScheduledUs == null) return null;
    return audioOutputUs! - audioScheduledUs!;
  }

  /// Is measurement complete?
  bool get isComplete => audioOutputUs != null;

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'dartTriggerUs': dartTriggerUs,
    'ffiReturnUs': ffiReturnUs,
    'engineProcessedUs': engineProcessedUs,
    'audioScheduledUs': audioScheduledUs,
    'audioOutputUs': audioOutputUs,
    'totalLatencyUs': totalLatencyUs,
    'dartToFfiUs': dartToFfiUs,
    'ffiToEngineUs': ffiToEngineUs,
    'engineToScheduledUs': engineToScheduledUs,
    'scheduledToOutputUs': scheduledToOutputUs,
    'isComplete': isComplete,
  };

  /// Total latency in milliseconds
  double? get totalLatencyMs => totalLatencyUs != null ? totalLatencyUs! / 1000.0 : null;

  /// Meets < 5ms target?
  bool get meetsTarget => totalLatencyMs != null && totalLatencyMs! < 5.0;
}

/// Latency statistics
class LatencyStats {
  /// Total measurements
  final int totalMeasurements;

  /// Complete measurements (with audio output timestamp)
  final int completeMeasurements;

  /// Average total latency (microseconds)
  final double avgTotalLatencyUs;

  /// Min total latency (microseconds)
  final int minTotalLatencyUs;

  /// Max total latency (microseconds)
  final int maxTotalLatencyUs;

  /// Average Dart→FFI latency
  final double avgDartToFfiUs;

  /// Average FFI→Engine latency
  final double avgFfiToEngineUs;

  /// Average Engine→Scheduled latency
  final double avgEngineToScheduledUs;

  /// Average Scheduled→Output latency (buffer latency)
  final double avgScheduledToOutputUs;

  /// Measurements meeting < 5ms target
  final int meetsTargetCount;

  /// Percentage meeting target
  final double meetsTargetPercent;

  LatencyStats({
    required this.totalMeasurements,
    required this.completeMeasurements,
    required this.avgTotalLatencyUs,
    required this.minTotalLatencyUs,
    required this.maxTotalLatencyUs,
    required this.avgDartToFfiUs,
    required this.avgFfiToEngineUs,
    required this.avgEngineToScheduledUs,
    required this.avgScheduledToOutputUs,
    required this.meetsTargetCount,
    required this.meetsTargetPercent,
  });

  /// Average total latency in milliseconds
  double get avgTotalLatencyMs => avgTotalLatencyUs / 1000.0;

  /// Min total latency in milliseconds
  double get minTotalLatencyMs => minTotalLatencyUs / 1000.0;

  /// Max total latency in milliseconds
  double get maxTotalLatencyMs => maxTotalLatencyUs / 1000.0;
}

/// Latency Profiler Service
class LatencyProfiler extends ChangeNotifier {
  // ─── Singleton ─────────────────────────────────────────────────────────────
  static LatencyProfiler? _instance;
  static LatencyProfiler get instance => _instance ??= LatencyProfiler._();

  LatencyProfiler._();

  // ─── State ─────────────────────────────────────────────────────────────────
  final NativeFFI _ffi = NativeFFI.instance;

  /// Active measurements (waiting for completion)
  final Map<String, LatencyMeasurement> _activeMeasurements = {};

  /// Completed measurements (limited history)
  final List<LatencyMeasurement> _completedMeasurements = [];

  /// Max completed measurements to keep
  static const int maxHistory = 1000;

  /// Is profiling enabled?
  bool _enabled = false;

  /// Next measurement ID
  int _nextId = 0;

  // ─── Getters ───────────────────────────────────────────────────────────────

  /// Is profiling enabled?
  bool get enabled => _enabled;

  /// Active measurement count
  int get activeMeasurementCount => _activeMeasurements.length;

  /// Completed measurement count
  int get completedMeasurementCount => _completedMeasurements.length;

  /// Get all completed measurements
  List<LatencyMeasurement> get completedMeasurements =>
      List.unmodifiable(_completedMeasurements);

  /// Get most recent N measurements
  List<LatencyMeasurement> getRecentMeasurements(int count) {
    return _completedMeasurements.reversed.take(count).toList();
  }

  // ─── Control ───────────────────────────────────────────────────────────────

  /// Enable latency profiling
  void enable() {
    if (_enabled) return;
    _enabled = true;
    notifyListeners();
  }

  /// Disable latency profiling
  void disable() {
    if (!_enabled) return;
    _enabled = false;
    notifyListeners();
  }

  /// Clear all measurements
  void clear() {
    _activeMeasurements.clear();
    _completedMeasurements.clear();
    notifyListeners();
  }

  // ─── Measurement ───────────────────────────────────────────────────────────

  /// Start a latency measurement
  ///
  /// Call this BEFORE triggering audio (e.g., before EventRegistry.triggerStage).
  /// Returns measurement ID for tracking.
  String startMeasurement(String source) {
    if (!_enabled) return '';

    final id = 'lat_${_nextId++}';
    final nowUs = DateTime.now().microsecondsSinceEpoch;

    final measurement = LatencyMeasurement(
      id: id,
      source: source,
      dartTriggerUs: nowUs,
    );

    _activeMeasurements[id] = measurement;


    return id;
  }

  /// Mark FFI return
  ///
  /// Call this AFTER FFI function returns.
  void markFfiReturn(String id) {
    if (!_enabled || id.isEmpty) return;

    final measurement = _activeMeasurements[id];
    if (measurement == null) {
      return;
    }

    final nowUs = DateTime.now().microsecondsSinceEpoch;
    _activeMeasurements[id] = LatencyMeasurement(
      id: measurement.id,
      source: measurement.source,
      dartTriggerUs: measurement.dartTriggerUs,
      ffiReturnUs: nowUs,
      engineProcessedUs: measurement.engineProcessedUs,
      audioScheduledUs: measurement.audioScheduledUs,
      audioOutputUs: measurement.audioOutputUs,
    );

    final dartToFfi = nowUs - measurement.dartTriggerUs;
  }

  /// Mark engine processed
  ///
  /// Called via FFI callback when engine confirms processing.
  void markEngineProcessed(String id, int timestampUs) {
    if (!_enabled || id.isEmpty) return;

    final measurement = _activeMeasurements[id];
    if (measurement == null) return;

    _activeMeasurements[id] = LatencyMeasurement(
      id: measurement.id,
      source: measurement.source,
      dartTriggerUs: measurement.dartTriggerUs,
      ffiReturnUs: measurement.ffiReturnUs,
      engineProcessedUs: timestampUs,
      audioScheduledUs: measurement.audioScheduledUs,
      audioOutputUs: measurement.audioOutputUs,
    );

    if (measurement.ffiReturnUs != null) {
      final ffiToEngine = timestampUs - measurement.ffiReturnUs!;
    }
  }

  /// Mark audio scheduled
  ///
  /// Called via FFI callback when audio thread schedules playback.
  void markAudioScheduled(String id, int timestampUs) {
    if (!_enabled || id.isEmpty) return;

    final measurement = _activeMeasurements[id];
    if (measurement == null) return;

    _activeMeasurements[id] = LatencyMeasurement(
      id: measurement.id,
      source: measurement.source,
      dartTriggerUs: measurement.dartTriggerUs,
      ffiReturnUs: measurement.ffiReturnUs,
      engineProcessedUs: measurement.engineProcessedUs,
      audioScheduledUs: timestampUs,
      audioOutputUs: measurement.audioOutputUs,
    );
  }

  /// Complete a measurement
  ///
  /// Called via FFI callback when first audio sample outputs.
  void completeMeasurement(String id, int audioOutputUs) {
    if (!_enabled || id.isEmpty) return;

    final measurement = _activeMeasurements.remove(id);
    if (measurement == null) return;

    final completedMeasurement = LatencyMeasurement(
      id: measurement.id,
      source: measurement.source,
      dartTriggerUs: measurement.dartTriggerUs,
      ffiReturnUs: measurement.ffiReturnUs,
      engineProcessedUs: measurement.engineProcessedUs,
      audioScheduledUs: measurement.audioScheduledUs,
      audioOutputUs: audioOutputUs,
    );

    // Add to history
    _completedMeasurements.add(completedMeasurement);
    if (_completedMeasurements.length > maxHistory) {
      _completedMeasurements.removeAt(0);
    }

    // Log results
    final totalMs = completedMeasurement.totalLatencyMs;
    final meetsTarget = completedMeasurement.meetsTarget;
    final icon = meetsTarget ? '✅' : '⚠️';

    if (completedMeasurement.dartToFfiUs != null) {
    }
    if (completedMeasurement.ffiToEngineUs != null) {
    }
    if (completedMeasurement.scheduledToOutputUs != null) {
    }

    notifyListeners();
  }

  // ─── Statistics ────────────────────────────────────────────────────────────

  /// Get latency statistics
  LatencyStats getStats() {
    final complete = _completedMeasurements.where((m) => m.isComplete).toList();

    if (complete.isEmpty) {
      return LatencyStats(
        totalMeasurements: _completedMeasurements.length,
        completeMeasurements: 0,
        avgTotalLatencyUs: 0.0,
        minTotalLatencyUs: 0,
        maxTotalLatencyUs: 0,
        avgDartToFfiUs: 0.0,
        avgFfiToEngineUs: 0.0,
        avgEngineToScheduledUs: 0.0,
        avgScheduledToOutputUs: 0.0,
        meetsTargetCount: 0,
        meetsTargetPercent: 0.0,
      );
    }

    final totalLatencies = complete.map((m) => m.totalLatencyUs!).toList();
    final avgTotal = totalLatencies.reduce((a, b) => a + b) / totalLatencies.length;
    final minTotal = totalLatencies.reduce((a, b) => a < b ? a : b);
    final maxTotal = totalLatencies.reduce((a, b) => a > b ? a : b);

    final dartToFfi = complete.where((m) => m.dartToFfiUs != null).map((m) => m.dartToFfiUs!);
    final avgDartToFfi = dartToFfi.isNotEmpty ? dartToFfi.reduce((a, b) => a + b) / dartToFfi.length : 0.0;

    final ffiToEngine = complete.where((m) => m.ffiToEngineUs != null).map((m) => m.ffiToEngineUs!);
    final avgFfiToEngine = ffiToEngine.isNotEmpty ? ffiToEngine.reduce((a, b) => a + b) / ffiToEngine.length : 0.0;

    final engineToScheduled = complete.where((m) => m.engineToScheduledUs != null).map((m) => m.engineToScheduledUs!);
    final avgEngineToScheduled = engineToScheduled.isNotEmpty ? engineToScheduled.reduce((a, b) => a + b) / engineToScheduled.length : 0.0;

    final scheduledToOutput = complete.where((m) => m.scheduledToOutputUs != null).map((m) => m.scheduledToOutputUs!);
    final avgScheduledToOutput = scheduledToOutput.isNotEmpty ? scheduledToOutput.reduce((a, b) => a + b) / scheduledToOutput.length : 0.0;

    final meetsTarget = complete.where((m) => m.meetsTarget).length;
    final meetsTargetPercent = (meetsTarget / complete.length) * 100.0;

    return LatencyStats(
      totalMeasurements: _completedMeasurements.length,
      completeMeasurements: complete.length,
      avgTotalLatencyUs: avgTotal,
      minTotalLatencyUs: minTotal,
      maxTotalLatencyUs: maxTotal,
      avgDartToFfiUs: avgDartToFfi,
      avgFfiToEngineUs: avgFfiToEngine,
      avgEngineToScheduledUs: avgEngineToScheduled,
      avgScheduledToOutputUs: avgScheduledToOutput,
      meetsTargetCount: meetsTarget,
      meetsTargetPercent: meetsTargetPercent,
    );
  }

  /// Export measurements to JSON
  String exportToJson() {
    final data = {
      'enabled': _enabled,
      'activeMeasurements': _activeMeasurements.length,
      'completedMeasurements': _completedMeasurements.length,
      'measurements': _completedMeasurements.map((m) => m.toJson()).toList(),
      'stats': {
        'avg': getStats().avgTotalLatencyMs,
        'min': getStats().minTotalLatencyMs,
        'max': getStats().maxTotalLatencyMs,
        'meetsTarget': getStats().meetsTargetPercent,
      },
    };

    return data.toString();
  }
}
