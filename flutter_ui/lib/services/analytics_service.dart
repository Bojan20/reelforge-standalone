/// Analytics Service
///
/// Tracks usage metrics, performance data, and user interactions.
/// Privacy-first: all data stored locally, opt-in telemetry.
///
/// P3-07: Analytics Dashboard (~500 LOC)
library;

import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Analytics event types
enum AnalyticsEventType {
  // Session events
  sessionStart,
  sessionEnd,

  // Feature usage
  featureUsed,
  tabOpened,
  panelExpanded,
  actionTriggered,

  // Audio events
  audioImported,
  audioExported,
  audioPlayed,

  // Project events
  projectCreated,
  projectOpened,
  projectSaved,

  // Performance
  renderTime,
  ffiLatency,
  memoryUsage,

  // Errors
  errorOccurred,
  warningLogged,
}

/// Single analytics event
class AnalyticsEvent {
  final String id;
  final AnalyticsEventType type;
  final DateTime timestamp;
  final String? category;
  final String? action;
  final String? label;
  final double? value;
  final Map<String, dynamic> properties;

  AnalyticsEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    this.category,
    this.action,
    this.label,
    this.value,
    this.properties = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        if (category != null) 'category': category,
        if (action != null) 'action': action,
        if (label != null) 'label': label,
        if (value != null) 'value': value,
        if (properties.isNotEmpty) 'properties': properties,
      };

  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) => AnalyticsEvent(
        id: json['id'] as String,
        type: AnalyticsEventType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => AnalyticsEventType.featureUsed,
        ),
        timestamp: DateTime.parse(json['timestamp'] as String),
        category: json['category'] as String?,
        action: json['action'] as String?,
        label: json['label'] as String?,
        value: (json['value'] as num?)?.toDouble(),
        properties: (json['properties'] as Map<String, dynamic>?) ?? {},
      );
}

/// Session statistics
class SessionStats {
  final DateTime startTime;
  final int eventsCount;
  final int featuresUsed;
  final int errorsCount;
  final Duration activeTime;
  final Map<String, int> featureUsage;

  const SessionStats({
    required this.startTime,
    required this.eventsCount,
    required this.featuresUsed,
    required this.errorsCount,
    required this.activeTime,
    required this.featureUsage,
  });

  Map<String, dynamic> toJson() => {
        'startTime': startTime.toIso8601String(),
        'eventsCount': eventsCount,
        'featuresUsed': featuresUsed,
        'errorsCount': errorsCount,
        'activeTimeSeconds': activeTime.inSeconds,
        'featureUsage': featureUsage,
      };
}

/// Aggregated metrics
class AggregatedMetrics {
  final int totalSessions;
  final int totalEvents;
  final Duration totalActiveTime;
  final Map<String, int> featureUsageTotal;
  final Map<String, int> eventsByType;
  final List<double> performanceHistory;
  final int totalErrors;

  const AggregatedMetrics({
    required this.totalSessions,
    required this.totalEvents,
    required this.totalActiveTime,
    required this.featureUsageTotal,
    required this.eventsByType,
    required this.performanceHistory,
    required this.totalErrors,
  });

  Map<String, dynamic> toJson() => {
        'totalSessions': totalSessions,
        'totalEvents': totalEvents,
        'totalActiveTimeSeconds': totalActiveTime.inSeconds,
        'featureUsageTotal': featureUsageTotal,
        'eventsByType': eventsByType,
        'performanceHistory': performanceHistory,
        'totalErrors': totalErrors,
      };
}

/// Analytics Service
class AnalyticsService {
  AnalyticsService._();
  static final instance = AnalyticsService._();

  static const _storageKey = 'fluxforge_analytics';
  static const _maxEvents = 10000;

  final _events = <AnalyticsEvent>[];
  final _eventController = StreamController<AnalyticsEvent>.broadcast();
  DateTime? _sessionStart;
  Timer? _sessionTimer;
  Duration _activeTime = Duration.zero;
  bool _enabled = true;
  int _eventCounter = 0;

  /// Event stream
  Stream<AnalyticsEvent> get eventStream => _eventController.stream;

  /// Whether analytics is enabled
  bool get enabled => _enabled;

  /// Current session start time
  DateTime? get sessionStart => _sessionStart;

  /// Initialize analytics
  Future<void> init() async {
    await _loadFromStorage();
    startSession();
  }

  /// Enable/disable analytics
  void setEnabled(bool value) {
    _enabled = value;
    _saveToStorage();
  }

  /// Start a new session
  void startSession() {
    _sessionStart = DateTime.now();
    _activeTime = Duration.zero;

    // Track active time every 10 seconds
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _activeTime += const Duration(seconds: 10);
    });

    track(AnalyticsEventType.sessionStart);
  }

  /// End current session
  void endSession() {
    _sessionTimer?.cancel();
    track(AnalyticsEventType.sessionEnd, properties: {
      'duration_seconds': _activeTime.inSeconds,
    });
    _saveToStorage();
  }

  /// Track an event
  void track(
    AnalyticsEventType type, {
    String? category,
    String? action,
    String? label,
    double? value,
    Map<String, dynamic> properties = const {},
  }) {
    if (!_enabled) return;

    final event = AnalyticsEvent(
      id: '${DateTime.now().millisecondsSinceEpoch}_${_eventCounter++}',
      type: type,
      timestamp: DateTime.now(),
      category: category,
      action: action,
      label: label,
      value: value,
      properties: properties,
    );

    _events.add(event);
    _eventController.add(event);

    // Trim if too many events
    if (_events.length > _maxEvents) {
      _events.removeRange(0, _events.length - _maxEvents);
    }
  }

  /// Track feature usage
  void trackFeature(String featureName, {Map<String, dynamic>? properties}) {
    track(
      AnalyticsEventType.featureUsed,
      category: 'feature',
      action: featureName,
      properties: properties ?? {},
    );
  }

  /// Track tab/panel open
  void trackTabOpen(String tabName, String section) {
    track(
      AnalyticsEventType.tabOpened,
      category: 'navigation',
      action: tabName,
      label: section,
    );
  }

  /// Track audio operations
  void trackAudioOperation(String operation, {String? format, int? sizeBytes}) {
    track(
      AnalyticsEventType.audioImported,
      category: 'audio',
      action: operation,
      label: format,
      value: sizeBytes?.toDouble(),
    );
  }

  /// Track performance metrics
  void trackPerformance(String metric, double valueMs) {
    track(
      AnalyticsEventType.renderTime,
      category: 'performance',
      action: metric,
      value: valueMs,
    );
  }

  /// Track errors
  void trackError(String error, {String? stackTrace, String? context}) {
    track(
      AnalyticsEventType.errorOccurred,
      category: 'error',
      action: error,
      properties: {
        if (stackTrace != null) 'stackTrace': stackTrace,
        if (context != null) 'context': context,
      },
    );
  }

  /// Get current session stats
  SessionStats getSessionStats() {
    final sessionEvents = _sessionStart != null
        ? _events.where((e) => e.timestamp.isAfter(_sessionStart!)).toList()
        : _events;

    final featureUsage = <String, int>{};
    int errorsCount = 0;

    for (final event in sessionEvents) {
      if (event.type == AnalyticsEventType.featureUsed && event.action != null) {
        featureUsage[event.action!] = (featureUsage[event.action!] ?? 0) + 1;
      }
      if (event.type == AnalyticsEventType.errorOccurred) {
        errorsCount++;
      }
    }

    return SessionStats(
      startTime: _sessionStart ?? DateTime.now(),
      eventsCount: sessionEvents.length,
      featuresUsed: featureUsage.length,
      errorsCount: errorsCount,
      activeTime: _activeTime,
      featureUsage: featureUsage,
    );
  }

  /// Get aggregated metrics
  AggregatedMetrics getAggregatedMetrics() {
    final featureUsageTotal = <String, int>{};
    final eventsByType = <String, int>{};
    final performanceHistory = <double>[];
    int errorsCount = 0;
    int sessionsCount = 0;

    for (final event in _events) {
      // Count by type
      final typeName = event.type.name;
      eventsByType[typeName] = (eventsByType[typeName] ?? 0) + 1;

      // Feature usage
      if (event.type == AnalyticsEventType.featureUsed && event.action != null) {
        featureUsageTotal[event.action!] =
            (featureUsageTotal[event.action!] ?? 0) + 1;
      }

      // Performance
      if (event.type == AnalyticsEventType.renderTime && event.value != null) {
        performanceHistory.add(event.value!);
      }

      // Errors
      if (event.type == AnalyticsEventType.errorOccurred) {
        errorsCount++;
      }

      // Sessions
      if (event.type == AnalyticsEventType.sessionStart) {
        sessionsCount++;
      }
    }

    return AggregatedMetrics(
      totalSessions: sessionsCount,
      totalEvents: _events.length,
      totalActiveTime: _activeTime,
      featureUsageTotal: featureUsageTotal,
      eventsByType: eventsByType,
      performanceHistory: performanceHistory,
      totalErrors: errorsCount,
    );
  }

  /// Get events by time range
  List<AnalyticsEvent> getEventsByTimeRange(DateTime start, DateTime end) {
    return _events
        .where((e) => e.timestamp.isAfter(start) && e.timestamp.isBefore(end))
        .toList();
  }

  /// Get events by type
  List<AnalyticsEvent> getEventsByType(AnalyticsEventType type) {
    return _events.where((e) => e.type == type).toList();
  }

  /// Get top features
  List<MapEntry<String, int>> getTopFeatures({int limit = 10}) {
    final metrics = getAggregatedMetrics();
    final sorted = metrics.featureUsageTotal.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  /// Export all data as JSON
  String exportJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'exportedAt': DateTime.now().toIso8601String(),
      'enabled': _enabled,
      'metrics': getAggregatedMetrics().toJson(),
      'events': _events.map((e) => e.toJson()).toList(),
    });
  }

  /// Clear all analytics data
  Future<void> clearAll() async {
    _events.clear();
    _eventCounter = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  /// Load from storage
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_storageKey);
      if (data != null) {
        final json = jsonDecode(data) as Map<String, dynamic>;
        _enabled = json['enabled'] as bool? ?? true;

        final events = json['events'] as List<dynamic>?;
        if (events != null) {
          _events.addAll(
            events.map((e) => AnalyticsEvent.fromJson(e as Map<String, dynamic>)),
          );
        }
      }
    } catch (_) {
      // Ignore load errors
    }
  }

  /// Save to storage
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode({
        'enabled': _enabled,
        'events': _events.map((e) => e.toJson()).toList(),
      });
      await prefs.setString(_storageKey, data);
    } catch (_) {
      // Ignore save errors
    }
  }

  /// Dispose
  void dispose() {
    endSession();
    _eventController.close();
    _sessionTimer?.cancel();
  }
}
