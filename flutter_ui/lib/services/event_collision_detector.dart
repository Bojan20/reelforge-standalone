/// Event Collision Detector Service
///
/// Detects and reports potential audio conflicts:
/// - Overlapping events on same bus
/// - Polyphony violations (voice count > limit)
/// - Ducking conflicts (multiple duckers active)
/// - Stage timing collisions
///
/// P2-16: Medium priority — QA tool for audio designers

import 'dart:collection';
import '../models/middleware_models.dart';
import '../models/slot_audio_events.dart';

/// Collision type
enum CollisionType {
  /// Multiple events playing on same bus simultaneously
  busOverlap,

  /// Voice count exceeds polyphony limit
  polyphonyViolation,

  /// Multiple ducking rules active simultaneously
  duckingConflict,

  /// Stage events triggered too close together (< minimum spacing)
  stageTiming,

  /// Priority conflict (high-priority event blocked by lower priority)
  priorityBlocking,
}

/// Collision severity
enum CollisionSeverity {
  /// Warning — may cause issues
  warning,

  /// Error — will cause audible problems
  error,

  /// Critical — system failure likely
  critical,
}

/// Detected collision
class EventCollision {
  final CollisionType type;
  final CollisionSeverity severity;
  final String description;
  final List<String> involvedEventIds;
  final double timestampMs;
  final String? suggestedFix;

  const EventCollision({
    required this.type,
    required this.severity,
    required this.description,
    required this.involvedEventIds,
    required this.timestampMs,
    this.suggestedFix,
  });

  @override
  String toString() => '[$severity] $description at ${timestampMs}ms';
}

/// Collision detection configuration
class CollisionConfig {
  /// Maximum voices per bus before warning
  final int maxVoicesPerBus;

  /// Minimum spacing between stage events (ms)
  final double minStageSpacingMs;

  /// Whether to check ducking conflicts
  final bool checkDuckingConflicts;

  /// Whether to check priority blocking
  final bool checkPriorityBlocking;

  const CollisionConfig({
    this.maxVoicesPerBus = 8,
    this.minStageSpacingMs = 50.0,
    this.checkDuckingConflicts = true,
    this.checkPriorityBlocking = true,
  });

  static const CollisionConfig standard = CollisionConfig();

  static const CollisionConfig strict = CollisionConfig(
    maxVoicesPerBus: 4,
    minStageSpacingMs: 100.0,
  );

  static const CollisionConfig relaxed = CollisionConfig(
    maxVoicesPerBus: 16,
    minStageSpacingMs: 20.0,
  );
}

/// Event playback timeline entry
class TimelineEntry {
  final String eventId;
  final double startMs;
  final double durationMs;
  final int busId;
  final int priority;
  final String? stage;

  const TimelineEntry({
    required this.eventId,
    required this.startMs,
    required this.durationMs,
    required this.busId,
    required this.priority,
    this.stage,
  });

  double get endMs => startMs + durationMs;

  bool overlaps(TimelineEntry other) {
    return startMs < other.endMs && other.startMs < endMs;
  }
}

/// Event Collision Detector
class EventCollisionDetector {
  final CollisionConfig config;

  /// Active timeline (event ID → entry)
  final Map<String, TimelineEntry> _timeline = {};

  /// Detected collisions
  final List<EventCollision> _collisions = [];

  EventCollisionDetector({this.config = CollisionConfig.standard});

  /// Add event to timeline for collision detection
  void addEvent({
    required String eventId,
    required double startMs,
    required double durationMs,
    required int busId,
    int priority = 50,
    String? stage,
  }) {
    final entry = TimelineEntry(
      eventId: eventId,
      startMs: startMs,
      durationMs: durationMs,
      busId: busId,
      priority: priority,
      stage: stage,
    );

    _timeline[eventId] = entry;
    _detectCollisions(entry);
  }

  /// Remove event from timeline
  void removeEvent(String eventId) {
    _timeline.remove(eventId);
  }

  /// Clear all events and collisions
  void clear() {
    _timeline.clear();
    _collisions.clear();
  }

  /// Get all detected collisions
  List<EventCollision> get collisions => List.unmodifiable(_collisions);

  /// Get collisions for specific event
  List<EventCollision> getCollisionsForEvent(String eventId) {
    return _collisions
        .where((c) => c.involvedEventIds.contains(eventId))
        .toList();
  }

  /// Get collisions by type
  List<EventCollision> getCollisionsByType(CollisionType type) {
    return _collisions.where((c) => c.type == type).toList();
  }

  /// Get collisions by severity
  List<EventCollision> getCollisionsBySeverity(CollisionSeverity severity) {
    return _collisions.where((c) => c.severity == severity).toList();
  }

  /// Check if event would cause collision (without adding to timeline)
  List<EventCollision> checkEvent({
    required String eventId,
    required double startMs,
    required double durationMs,
    required int busId,
    int priority = 50,
    String? stage,
  }) {
    final entry = TimelineEntry(
      eventId: eventId,
      startMs: startMs,
      durationMs: durationMs,
      busId: busId,
      priority: priority,
      stage: stage,
    );

    final tempCollisions = <EventCollision>[];
    _detectCollisionsInto(entry, tempCollisions);
    return tempCollisions;
  }

  /// Detect collisions for new entry
  void _detectCollisions(TimelineEntry entry) {
    _detectCollisionsInto(entry, _collisions);
  }

  void _detectCollisionsInto(TimelineEntry entry, List<EventCollision> target) {
    // 1. Bus overlap check
    _checkBusOverlap(entry, target);

    // 2. Stage timing check
    if (entry.stage != null) {
      _checkStageTiming(entry, target);
    }

    // 3. Priority blocking check
    if (config.checkPriorityBlocking) {
      _checkPriorityBlocking(entry, target);
    }
  }

  /// Check for bus overlap (multiple events on same bus)
  void _checkBusOverlap(TimelineEntry entry, List<EventCollision> target) {
    final overlapping = _timeline.values
        .where((e) => e.eventId != entry.eventId &&
                      e.busId == entry.busId &&
                      e.overlaps(entry))
        .toList();

    if (overlapping.isEmpty) return;

    // Count total voices on bus during overlap
    final voiceCount = overlapping.length + 1;

    if (voiceCount > config.maxVoicesPerBus) {
      target.add(EventCollision(
        type: CollisionType.busOverlap,
        severity: voiceCount > config.maxVoicesPerBus * 1.5
            ? CollisionSeverity.error
            : CollisionSeverity.warning,
        description: 'Bus $entry.busId has $voiceCount voices (max: ${config.maxVoicesPerBus})',
        involvedEventIds: [entry.eventId, ...overlapping.map((e) => e.eventId)],
        timestampMs: entry.startMs,
        suggestedFix: 'Reduce voice count or increase max voices per bus',
      ));
    }
  }

  /// Check for stage timing issues (events too close together)
  void _checkStageTiming(TimelineEntry entry, List<EventCollision> target) {
    final stage = entry.stage!;

    final closeEvents = _timeline.values
        .where((e) => e.eventId != entry.eventId &&
                      e.stage == stage &&
                      (e.startMs - entry.startMs).abs() < config.minStageSpacingMs)
        .toList();

    for (final other in closeEvents) {
      final spacing = (other.startMs - entry.startMs).abs();
      target.add(EventCollision(
        type: CollisionType.stageTiming,
        severity: spacing < config.minStageSpacingMs / 2
            ? CollisionSeverity.error
            : CollisionSeverity.warning,
        description: 'Stage "$stage" events ${spacing.toStringAsFixed(1)}ms apart (min: ${config.minStageSpacingMs}ms)',
        involvedEventIds: [entry.eventId, other.eventId],
        timestampMs: entry.startMs,
        suggestedFix: 'Increase spacing between stage events or use voice pooling',
      ));
    }
  }

  /// Check for priority blocking (low priority blocking high priority)
  void _checkPriorityBlocking(TimelineEntry entry, List<EventCollision> target) {
    final blocked = _timeline.values
        .where((e) => e.eventId != entry.eventId &&
                      e.busId == entry.busId &&
                      e.overlaps(entry) &&
                      e.priority < entry.priority) // Lower priority blocks higher
        .toList();

    for (final blocker in blocked) {
      target.add(EventCollision(
        type: CollisionType.priorityBlocking,
        severity: CollisionSeverity.warning,
        description: 'Event "${blocker.eventId}" (priority ${blocker.priority}) may block "${entry.eventId}" (priority ${entry.priority})',
        involvedEventIds: [entry.eventId, blocker.eventId],
        timestampMs: entry.startMs,
        suggestedFix: 'Adjust priorities or use voice stealing',
      ));
    }
  }

  /// Generate collision report
  String generateReport() {
    if (_collisions.isEmpty) {
      return 'No collisions detected (${_timeline.length} events checked)';
    }

    final sb = StringBuffer();
    sb.writeln('=== Event Collision Report ===');
    sb.writeln('Total events: ${_timeline.length}');
    sb.writeln('Total collisions: ${_collisions.length}');
    sb.writeln('');

    // Group by severity
    final bySeverity = <CollisionSeverity, List<EventCollision>>{};
    for (final collision in _collisions) {
      bySeverity.putIfAbsent(collision.severity, () => []).add(collision);
    }

    for (final severity in [CollisionSeverity.critical, CollisionSeverity.error, CollisionSeverity.warning]) {
      final collisions = bySeverity[severity] ?? [];
      if (collisions.isEmpty) continue;

      sb.writeln('${severity.name.toUpperCase()}: ${collisions.length}');
      for (final collision in collisions) {
        sb.writeln('  • $collision');
        if (collision.suggestedFix != null) {
          sb.writeln('    → ${collision.suggestedFix}');
        }
      }
      sb.writeln('');
    }

    return sb.toString();
  }

  /// Export collisions to JSON
  Map<String, dynamic> toJson() {
    return {
      'totalEvents': _timeline.length,
      'totalCollisions': _collisions.length,
      'collisions': _collisions.map((c) => {
        'type': c.type.name,
        'severity': c.severity.name,
        'description': c.description,
        'involvedEventIds': c.involvedEventIds,
        'timestampMs': c.timestampMs,
        'suggestedFix': c.suggestedFix,
      }).toList(),
      'config': {
        'maxVoicesPerBus': config.maxVoicesPerBus,
        'minStageSpacingMs': config.minStageSpacingMs,
      },
    };
  }
}
