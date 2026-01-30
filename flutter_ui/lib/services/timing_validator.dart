// timing_validator.dart
// Event timing validation service
// Enforces <5ms SLA for audio events

import 'dart:collection';
import 'dart:convert';

/// Timing measurement for a single event
class TimingMeasurement {
  final String eventId;
  final String stage;
  final DateTime triggerTime;
  final DateTime? audioStartTime;
  final Duration? latency;
  final bool success;
  final String? errorMessage;

  const TimingMeasurement({
    required this.eventId,
    required this.stage,
    required this.triggerTime,
    this.audioStartTime,
    this.latency,
    required this.success,
    this.errorMessage,
  });

  bool get passedSla => latency != null && latency!.inMicroseconds <= 5000;

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'stage': stage,
        'triggerTime': triggerTime.toIso8601String(),
        'audioStartTime': audioStartTime?.toIso8601String(),
        'latencyUs': latency?.inMicroseconds,
        'success': success,
        'passedSla': passedSla,
        'errorMessage': errorMessage,
      };
}

/// Validation report
class ValidationReport {
  final DateTime startTime;
  final DateTime endTime;
  final List<TimingMeasurement> measurements;
  final String sessionId;

  const ValidationReport({
    required this.startTime,
    required this.endTime,
    required this.measurements,
    required this.sessionId,
  });

  int get totalEvents => measurements.length;

  int get passedEvents => measurements.where((m) => m.passedSla).length;

  int get failedEvents => totalEvents - passedEvents;

  double get passRate => totalEvents > 0 ? (passedEvents / totalEvents) * 100 : 0.0;

  Duration get averageLatency {
    if (measurements.isEmpty) return Duration.zero;
    final validLatencies = measurements
        .where((m) => m.latency != null)
        .map((m) => m.latency!.inMicroseconds)
        .toList();
    if (validLatencies.isEmpty) return Duration.zero;
    final avg = validLatencies.reduce((a, b) => a + b) / validLatencies.length;
    return Duration(microseconds: avg.round());
  }

  Duration? get maxLatency {
    if (measurements.isEmpty) return null;
    final validLatencies = measurements
        .where((m) => m.latency != null)
        .map((m) => m.latency!.inMicroseconds)
        .toList();
    if (validLatencies.isEmpty) return null;
    return Duration(microseconds: validLatencies.reduce((a, b) => a > b ? a : b));
  }

  Duration? get minLatency {
    if (measurements.isEmpty) return null;
    final validLatencies = measurements
        .where((m) => m.latency != null)
        .map((m) => m.latency!.inMicroseconds)
        .toList();
    if (validLatencies.isEmpty) return null;
    return Duration(microseconds: validLatencies.reduce((a, b) => a < b ? a : b));
  }

  Map<String, int> get latencyDistribution {
    final distribution = <String, int>{
      '0-1ms': 0,
      '1-2ms': 0,
      '2-3ms': 0,
      '3-4ms': 0,
      '4-5ms': 0,
      '>5ms': 0,
    };

    for (final m in measurements) {
      if (m.latency == null) continue;
      final ms = m.latency!.inMicroseconds / 1000.0;

      if (ms < 1) {
        distribution['0-1ms'] = distribution['0-1ms']! + 1;
      } else if (ms < 2) {
        distribution['1-2ms'] = distribution['1-2ms']! + 1;
      } else if (ms < 3) {
        distribution['2-3ms'] = distribution['2-3ms']! + 1;
      } else if (ms < 4) {
        distribution['3-4ms'] = distribution['3-4ms']! + 1;
      } else if (ms <= 5) {
        distribution['4-5ms'] = distribution['4-5ms']! + 1;
      } else {
        distribution['>5ms'] = distribution['>5ms']! + 1;
      }
    }

    return distribution;
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'totalEvents': totalEvents,
        'passedEvents': passedEvents,
        'failedEvents': failedEvents,
        'passRate': passRate,
        'averageLatencyUs': averageLatency.inMicroseconds,
        'maxLatencyUs': maxLatency?.inMicroseconds,
        'minLatencyUs': minLatency?.inMicroseconds,
        'latencyDistribution': latencyDistribution,
        'measurements': measurements.map((m) => m.toJson()).toList(),
      };
}

/// Timing validator service
class TimingValidator {
  static final TimingValidator instance = TimingValidator._();

  TimingValidator._();

  final Queue<TimingMeasurement> _measurements = Queue();
  final Map<String, DateTime> _pendingEvents = {};
  DateTime? _sessionStart;
  String _currentSessionId = '';

  static const int maxMeasurements = 1000;
  static const Duration slaThreshold = Duration(milliseconds: 5);

  /// Start new validation session
  void startSession({String? sessionId}) {
    _sessionStart = DateTime.now();
    _currentSessionId = sessionId ?? 'session_${DateTime.now().millisecondsSinceEpoch}';
    _measurements.clear();
    _pendingEvents.clear();
  }

  /// Record event trigger
  void recordTrigger(String eventId, String stage) {
    _pendingEvents[eventId] = DateTime.now();
  }

  /// Record audio start
  void recordAudioStart(String eventId, String stage) {
    final triggerTime = _pendingEvents[eventId];
    if (triggerTime == null) {
      // Trigger not recorded, record error
      _addMeasurement(TimingMeasurement(
        eventId: eventId,
        stage: stage,
        triggerTime: DateTime.now(),
        success: false,
        errorMessage: 'Trigger time not recorded',
      ));
      return;
    }

    final audioStartTime = DateTime.now();
    final latency = audioStartTime.difference(triggerTime);

    _addMeasurement(TimingMeasurement(
      eventId: eventId,
      stage: stage,
      triggerTime: triggerTime,
      audioStartTime: audioStartTime,
      latency: latency,
      success: true,
    ));

    _pendingEvents.remove(eventId);
  }

  /// Record event failure
  void recordFailure(String eventId, String stage, String error) {
    final triggerTime = _pendingEvents[eventId] ?? DateTime.now();

    _addMeasurement(TimingMeasurement(
      eventId: eventId,
      stage: stage,
      triggerTime: triggerTime,
      success: false,
      errorMessage: error,
    ));

    _pendingEvents.remove(eventId);
  }

  /// Add measurement to queue
  void _addMeasurement(TimingMeasurement measurement) {
    _measurements.add(measurement);

    // Keep queue bounded
    while (_measurements.length > maxMeasurements) {
      _measurements.removeFirst();
    }
  }

  /// Generate validation report
  ValidationReport generateReport() {
    final endTime = DateTime.now();
    final startTime = _sessionStart ?? endTime;

    return ValidationReport(
      startTime: startTime,
      endTime: endTime,
      measurements: _measurements.toList(),
      sessionId: _currentSessionId,
    );
  }

  /// Check if current session passes SLA
  bool get passingSla {
    final measurements = _measurements.toList();
    if (measurements.isEmpty) return true;

    final passed = measurements.where((m) => m.passedSla).length;
    return passed == measurements.length;
  }

  /// Get current pass rate
  double get currentPassRate {
    final measurements = _measurements.toList();
    if (measurements.isEmpty) return 100.0;

    final passed = measurements.where((m) => m.passedSla).length;
    return (passed / measurements.length) * 100;
  }

  /// Get latest measurements
  List<TimingMeasurement> getLatestMeasurements({int count = 50}) {
    return _measurements.toList().reversed.take(count).toList();
  }

  /// Clear all measurements
  void clear() {
    _measurements.clear();
    _pendingEvents.clear();
    _sessionStart = null;
    _currentSessionId = '';
  }

  /// Get statistics summary
  Map<String, dynamic> getStatistics() {
    final measurements = _measurements.toList();

    if (measurements.isEmpty) {
      return {
        'totalEvents': 0,
        'passRate': 100.0,
        'averageLatencyUs': 0,
        'maxLatencyUs': 0,
        'minLatencyUs': 0,
      };
    }

    final validLatencies = measurements
        .where((m) => m.latency != null)
        .map((m) => m.latency!.inMicroseconds)
        .toList();

    final avg = validLatencies.isNotEmpty
        ? validLatencies.reduce((a, b) => a + b) / validLatencies.length
        : 0.0;

    final max = validLatencies.isNotEmpty
        ? validLatencies.reduce((a, b) => a > b ? a : b)
        : 0;

    final min = validLatencies.isNotEmpty
        ? validLatencies.reduce((a, b) => a < b ? a : b)
        : 0;

    final passed = measurements.where((m) => m.passedSla).length;

    return {
      'totalEvents': measurements.length,
      'passedEvents': passed,
      'failedEvents': measurements.length - passed,
      'passRate': (passed / measurements.length) * 100,
      'averageLatencyUs': avg.round(),
      'maxLatencyUs': max,
      'minLatencyUs': min,
    };
  }

  /// Export report to JSON
  String exportReportJson(ValidationReport report) {
    return const JsonEncoder.withIndent('  ').convert(report.toJson());
  }
}

/// Helper to convert microseconds to human-readable format
String formatLatency(Duration? latency) {
  if (latency == null) return 'N/A';

  final us = latency.inMicroseconds;
  if (us < 1000) {
    return '${us}μs';
  } else {
    final ms = us / 1000.0;
    return '${ms.toStringAsFixed(2)}ms';
  }
}
