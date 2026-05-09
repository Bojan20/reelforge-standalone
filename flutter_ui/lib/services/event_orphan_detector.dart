// FLUX_MASTER_TODO 0.5 B.3 — Orphan Event Detector
//
// Runtime sweep (DEV only) that detects events registered in EventRegistry
// but never triggered during the current session. Surfaces as a sorted list
// in the HELIX Monitor debug panel after each spin batch.
//
// "Orphan" = registered stage + audio event exists, triggerCount == 0.
// This catches: typos in event names, dead config, feature audio never reached.

import 'package:flutter/foundation.dart';
import 'event_registry.dart';
import 'stage_coverage_service.dart';

/// A single orphan finding.
class OrphanEntry {
  final String stage;       // e.g. "REEL_SPIN_LOOP"
  final String eventId;     // e.g. "audio_REEL_SPIN_LOOP"
  final DateTime firstSeen; // when the stage was registered

  const OrphanEntry({
    required this.stage,
    required this.eventId,
    required this.firstSeen,
  });
}

class EventOrphanDetectorService extends ChangeNotifier {
  static final EventOrphanDetectorService instance =
      EventOrphanDetectorService._();
  EventOrphanDetectorService._();

  // ── State ───────────────────────────────────────────────────────────────────
  int _spinsSinceReset = 0;
  DateTime _sessionStart = DateTime.now();
  List<OrphanEntry> _orphans = [];
  bool _enabled = kDebugMode; // auto-off in release builds

  // ── Public API ──────────────────────────────────────────────────────────────

  bool get isEnabled => _enabled;
  int get spinsSinceReset => _spinsSinceReset;
  DateTime get sessionStart => _sessionStart;

  /// Orphan list — sorted by stage name.
  List<OrphanEntry> get orphans => List.unmodifiable(_orphans);

  /// Total registered stages.
  int get registeredCount =>
      EventRegistry.instance.registeredStages.length;

  /// Count of orphans as percentage of registered.
  double get orphanRatio =>
      registeredCount == 0 ? 0 : _orphans.length / registeredCount;

  void setEnabled(bool value) {
    _enabled = value;
    notifyListeners();
  }

  /// Call after each spin completes — bumps counter and re-sweeps if threshold met.
  void onSpinCompleted() {
    if (!_enabled) return;
    _spinsSinceReset++;
    // Sweep on every spin so the panel always shows fresh data.
    _sweep();
  }

  /// Force an immediate sweep (call from UI on demand).
  void forceSweep() {
    _sweep();
    notifyListeners();
  }

  /// Reset counters + re-sweep.
  void reset() {
    _spinsSinceReset = 0;
    _sessionStart = DateTime.now();
    _sweep();
    notifyListeners();
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  void _sweep() {
    final coverage = StageCoverageService.instance.coverage;
    final registered = EventRegistry.instance.registeredStages.toSet();

    final List<OrphanEntry> found = [];

    for (final stage in registered) {
      final entry = coverage[stage];
      final triggerCount = entry?.triggerCount ?? 0;

      if (triggerCount == 0) {
        // Orphan: registered, never fired
        final audioEvent = EventRegistry.instance.getEventForStage(stage);
        found.add(OrphanEntry(
          stage: stage,
          eventId: audioEvent?.id ?? stage,
          firstSeen: entry?.lastTriggered ?? _sessionStart,
        ));
      }
    }

    found.sort((a, b) => a.stage.compareTo(b.stage));
    _orphans = found;
    notifyListeners();
  }
}
