/// Stage Resolution Tracer
///
/// P1-10: Stage→Event Resolution Trace
///
/// Provides detailed trace logging of how stages resolve to events:
/// - Stage normalization (case, trim)
/// - Fallback chain (REEL_STOP_0 → REEL_STOP)
/// - Event matching logic
/// - Why a stage did or didn't trigger audio
///
/// This helps debug:
/// - "Why didn't my stage play?"
/// - "Which event is actually playing?"
/// - "Why did it fall back to generic event?"

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Resolution step type
enum ResolutionStepType {
  /// Initial stage trigger
  trigger,
  /// Stage normalization (case, trim)
  normalization,
  /// Fallback to generic stage
  fallback,
  /// Event lookup
  lookup,
  /// Event found
  found,
  /// Event not found
  notFound,
  /// Custom event handler
  customHandler,
  /// Container delegation
  containerDelegation,
  /// Audio playback
  playback,
  /// Error
  error,
}

/// Single resolution step
class ResolutionStep {
  /// Step type
  final ResolutionStepType type;

  /// Timestamp (microseconds)
  final int timestampUs;

  /// Step description
  final String description;

  /// Associated data (optional)
  final Map<String, dynamic>? data;

  ResolutionStep({
    required this.type,
    required this.timestampUs,
    required this.description,
    this.data,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'timestampUs': timestampUs,
    'description': description,
    if (data != null) 'data': data,
  };

  /// Icon for this step type
  IconData get icon {
    switch (type) {
      case ResolutionStepType.trigger:
        return Icons.play_arrow;
      case ResolutionStepType.normalization:
        return Icons.transform;
      case ResolutionStepType.fallback:
        return Icons.arrow_back;
      case ResolutionStepType.lookup:
        return Icons.search;
      case ResolutionStepType.found:
        return Icons.check_circle;
      case ResolutionStepType.notFound:
        return Icons.cancel;
      case ResolutionStepType.customHandler:
        return Icons.extension;
      case ResolutionStepType.containerDelegation:
        return Icons.folder;
      case ResolutionStepType.playback:
        return Icons.volume_up;
      case ResolutionStepType.error:
        return Icons.error;
    }
  }

  /// Color for this step type
  Color get color {
    switch (type) {
      case ResolutionStepType.trigger:
        return Colors.blue;
      case ResolutionStepType.normalization:
        return Colors.purple;
      case ResolutionStepType.fallback:
        return Colors.orange;
      case ResolutionStepType.lookup:
        return Colors.cyan;
      case ResolutionStepType.found:
        return Colors.green;
      case ResolutionStepType.notFound:
        return Colors.red;
      case ResolutionStepType.customHandler:
        return Colors.amber;
      case ResolutionStepType.containerDelegation:
        return Colors.teal;
      case ResolutionStepType.playback:
        return Colors.green;
      case ResolutionStepType.error:
        return Colors.red;
    }
  }
}

/// Resolution trace for a single stage trigger
class ResolutionTrace {
  /// Trace ID
  final String id;

  /// Original stage name
  final String originalStage;

  /// Start timestamp
  final int startTimestampUs;

  /// End timestamp
  int? endTimestampUs;

  /// Resolution steps
  final List<ResolutionStep> steps = [];

  /// Final event ID (if resolved)
  String? resolvedEventId;

  /// Final event name (if resolved)
  String? resolvedEventName;

  /// Success or failure
  bool success = false;

  ResolutionTrace({
    required this.id,
    required this.originalStage,
    required this.startTimestampUs,
  });

  /// Add a step
  void addStep(ResolutionStep step) {
    steps.add(step);
  }

  /// Mark trace as complete
  void complete({
    String? eventId,
    String? eventName,
    bool success = false,
  }) {
    endTimestampUs = DateTime.now().microsecondsSinceEpoch;
    resolvedEventId = eventId;
    resolvedEventName = eventName;
    this.success = success;
  }

  /// Total resolution time (microseconds)
  int? get resolutionTimeUs {
    if (endTimestampUs == null) return null;
    return endTimestampUs! - startTimestampUs;
  }

  /// Total resolution time (milliseconds)
  double? get resolutionTimeMs {
    final us = resolutionTimeUs;
    return us != null ? us / 1000.0 : null;
  }

  /// Is trace complete?
  bool get isComplete => endTimestampUs != null;

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'originalStage': originalStage,
    'startTimestampUs': startTimestampUs,
    'endTimestampUs': endTimestampUs,
    'resolutionTimeUs': resolutionTimeUs,
    'resolvedEventId': resolvedEventId,
    'resolvedEventName': resolvedEventName,
    'success': success,
    'steps': steps.map((s) => s.toJson()).toList(),
  };

  /// Get summary string
  String get summary {
    if (success) {
      return 'Resolved to: $resolvedEventName';
    } else {
      return 'Failed to resolve';
    }
  }
}

/// Stage Resolution Tracer
class StageResolutionTracer extends ChangeNotifier {
  // ─── Singleton ─────────────────────────────────────────────────────────────
  static StageResolutionTracer? _instance;
  static StageResolutionTracer get instance => _instance ??= StageResolutionTracer._();

  StageResolutionTracer._();

  // ─── State ─────────────────────────────────────────────────────────────────

  /// Active traces (currently resolving)
  final Map<String, ResolutionTrace> _activeTraces = {};

  /// Completed traces (limited history)
  final List<ResolutionTrace> _completedTraces = [];

  /// Max completed traces to keep
  static const int maxHistory = 1000;

  /// Is tracing enabled?
  bool _enabled = false;

  /// Next trace ID
  int _nextId = 0;

  // ─── Getters ───────────────────────────────────────────────────────────────

  /// Is tracing enabled?
  bool get enabled => _enabled;

  /// Active trace count
  int get activeTraceCount => _activeTraces.length;

  /// Completed trace count
  int get completedTraceCount => _completedTraces.length;

  /// Get all completed traces
  List<ResolutionTrace> get completedTraces => List.unmodifiable(_completedTraces);

  /// Get recent traces
  List<ResolutionTrace> getRecentTraces(int count) {
    return _completedTraces.reversed.take(count).toList();
  }

  /// Get traces for a specific stage
  List<ResolutionTrace> getTracesForStage(String stage) {
    return _completedTraces.where((t) => t.originalStage == stage).toList();
  }

  /// Get failed traces
  List<ResolutionTrace> getFailedTraces() {
    return _completedTraces.where((t) => !t.success).toList();
  }

  // ─── Control ───────────────────────────────────────────────────────────────

  /// Enable tracing
  void enable() {
    if (_enabled) return;
    _enabled = true;
    debugPrint('[StageResolutionTracer] ✅ Enabled');
    notifyListeners();
  }

  /// Disable tracing
  void disable() {
    if (!_enabled) return;
    _enabled = false;
    debugPrint('[StageResolutionTracer] ⏸ Disabled');
    notifyListeners();
  }

  /// Clear all traces
  void clear() {
    _activeTraces.clear();
    _completedTraces.clear();
    debugPrint('[StageResolutionTracer] 🧹 Cleared all traces');
    notifyListeners();
  }

  // ─── Tracing ───────────────────────────────────────────────────────────────

  /// Start a new trace
  ///
  /// Call this when EventRegistry.triggerStage() is called.
  /// Returns trace ID for adding steps.
  String startTrace(String stage) {
    if (!_enabled) return '';

    final id = 'trace_${_nextId++}';
    final nowUs = DateTime.now().microsecondsSinceEpoch;

    final trace = ResolutionTrace(
      id: id,
      originalStage: stage,
      startTimestampUs: nowUs,
    );

    trace.addStep(ResolutionStep(
      type: ResolutionStepType.trigger,
      timestampUs: nowUs,
      description: 'Stage triggered: $stage',
    ));

    _activeTraces[id] = trace;

    debugPrint('[StageResolutionTracer] 🎬 Started trace: $stage (id=$id)');

    return id;
  }

  /// Add a step to an active trace
  void addStep(String traceId, ResolutionStepType type, String description, {Map<String, dynamic>? data}) {
    if (!_enabled || traceId.isEmpty) return;

    final trace = _activeTraces[traceId];
    if (trace == null) return;

    trace.addStep(ResolutionStep(
      type: type,
      timestampUs: DateTime.now().microsecondsSinceEpoch,
      description: description,
      data: data,
    ));
  }

  /// Complete a trace
  void completeTrace(String traceId, {String? eventId, String? eventName, bool success = false}) {
    if (!_enabled || traceId.isEmpty) return;

    final trace = _activeTraces.remove(traceId);
    if (trace == null) return;

    trace.complete(
      eventId: eventId,
      eventName: eventName,
      success: success,
    );

    // Add to history
    _completedTraces.add(trace);
    if (_completedTraces.length > maxHistory) {
      _completedTraces.removeAt(0);
    }

    // Log result
    final icon = success ? '✅' : '❌';
    final resolutionMs = trace.resolutionTimeMs?.toStringAsFixed(2) ?? '?';

    debugPrint('[StageResolutionTracer] $icon Complete: ${trace.originalStage}');
    debugPrint('  Resolution time: ${resolutionMs}ms');
    debugPrint('  Steps: ${trace.steps.length}');
    if (success) {
      debugPrint('  Resolved to: $eventName');
    } else {
      debugPrint('  Failed to resolve');
    }

    notifyListeners();
  }

  // ─── Convenience Methods ───────────────────────────────────────────────────

  /// Log stage normalization step
  void logNormalization(String traceId, String original, String normalized) {
    addStep(
      traceId,
      ResolutionStepType.normalization,
      'Normalized: "$original" → "$normalized"',
      data: {'original': original, 'normalized': normalized},
    );
  }

  /// Log fallback step
  void logFallback(String traceId, String from, String to) {
    addStep(
      traceId,
      ResolutionStepType.fallback,
      'Fallback: "$from" → "$to"',
      data: {'from': from, 'to': to},
    );
  }

  /// Log event lookup step
  void logLookup(String traceId, String stage, int eventCount) {
    addStep(
      traceId,
      ResolutionStepType.lookup,
      'Looking up event for stage: "$stage" (${eventCount} events in registry)',
      data: {'stage': stage, 'eventCount': eventCount},
    );
  }

  /// Log event found step
  void logFound(String traceId, String eventId, String eventName) {
    addStep(
      traceId,
      ResolutionStepType.found,
      'Event found: "$eventName" (id=$eventId)',
      data: {'eventId': eventId, 'eventName': eventName},
    );
  }

  /// Log event not found step
  void logNotFound(String traceId, String stage) {
    addStep(
      traceId,
      ResolutionStepType.notFound,
      'No event found for stage: "$stage"',
      data: {'stage': stage},
    );
  }

  /// Log custom handler step
  void logCustomHandler(String traceId, String handlerName) {
    addStep(
      traceId,
      ResolutionStepType.customHandler,
      'Custom handler invoked: $handlerName',
      data: {'handler': handlerName},
    );
  }

  /// Log container delegation step
  void logContainerDelegation(String traceId, String containerType, String containerId) {
    addStep(
      traceId,
      ResolutionStepType.containerDelegation,
      'Delegated to $containerType container: $containerId',
      data: {'containerType': containerType, 'containerId': containerId},
    );
  }

  /// Log playback step
  void logPlayback(String traceId, int voiceId, String audioPath) {
    addStep(
      traceId,
      ResolutionStepType.playback,
      'Audio playback started: voice=$voiceId, path=$audioPath',
      data: {'voiceId': voiceId, 'audioPath': audioPath},
    );
  }

  /// Log error step
  void logError(String traceId, String error) {
    addStep(
      traceId,
      ResolutionStepType.error,
      'Error: $error',
      data: {'error': error},
    );
  }

  // ─── Export ────────────────────────────────────────────────────────────────

  /// Export traces to JSON
  String exportToJson() {
    final data = {
      'enabled': _enabled,
      'activeTraces': _activeTraces.length,
      'completedTraces': _completedTraces.length,
      'traces': _completedTraces.map((t) => t.toJson()).toList(),
    };

    return data.toString();
  }

  /// Export to CSV
  String exportToCsv() {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('trace_id,stage,start_us,end_us,resolution_ms,success,event_id,event_name,steps');

    // Data rows
    for (final trace in _completedTraces) {
      buffer.writeln(
        '${trace.id},'
        '"${trace.originalStage}",'
        '${trace.startTimestampUs},'
        '${trace.endTimestampUs ?? ""},'
        '${trace.resolutionTimeMs?.toStringAsFixed(2) ?? ""},'
        '${trace.success ? "YES" : "NO"},'
        '"${trace.resolvedEventId ?? ""}",'
        '"${trace.resolvedEventName ?? ""}",'
        '${trace.steps.length}'
      );
    }

    return buffer.toString();
  }
}
