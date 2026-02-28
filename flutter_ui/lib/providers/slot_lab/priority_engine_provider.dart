/// Priority Engine Provider — SlotLab Middleware §8
///
/// Resolves conflicts between simultaneous behavior nodes using
/// 6 priority classes with duck/delay/suppress resolution.
///
/// When multiple behaviors trigger at the same time, the priority engine
/// determines which plays, which gets ducked, and which gets suppressed.
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §8

import 'package:flutter/foundation.dart';
import '../../models/behavior_tree_models.dart';

// =============================================================================
// PRIORITY RESOLUTION RESULT
// =============================================================================

/// Result of resolving priority between two behaviors
class PriorityResolution {
  /// The winning behavior node ID
  final String winnerId;

  /// The losing behavior node ID
  final String loserId;

  /// What happens to the loser
  final PriorityConflictAction action;

  /// Duck amount in dB (only if action == duck)
  final double duckAmountDb;

  /// Delay amount in ms (only if action == delay)
  final int delayMs;

  const PriorityResolution({
    required this.winnerId,
    required this.loserId,
    required this.action,
    this.duckAmountDb = -6.0,
    this.delayMs = 0,
  });
}

/// An active priority context (behavior currently playing)
class ActiveBehavior {
  final String nodeId;
  final BehaviorPriorityClass priorityClass;
  final DateTime startedAt;
  final double currentGain; // dB

  const ActiveBehavior({
    required this.nodeId,
    required this.priorityClass,
    required this.startedAt,
    this.currentGain = 0.0,
  });
}

// =============================================================================
// PROVIDER
// =============================================================================

class PriorityEngineProvider extends ChangeNotifier {
  /// Currently active behaviors with their priorities
  final Map<String, ActiveBehavior> _activeBehaviors = {};

  /// Resolution log for diagnostics
  final List<PriorityResolution> _resolutionLog = [];

  /// Duck amount per priority class difference (dB)
  final Map<int, double> _duckAmounts = {
    1: -3.0,  // 1 class difference → -3 dB
    2: -6.0,  // 2 class difference → -6 dB
    3: -12.0, // 3 class difference → -12 dB
    4: -18.0, // 4+ → -18 dB
    5: -24.0,
  };

  /// Delay amounts per priority class difference (ms)
  final Map<int, int> _delayAmounts = {
    1: 50,
    2: 100,
    3: 200,
    4: 500,
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, ActiveBehavior> get activeBehaviors => Map.unmodifiable(_activeBehaviors);
  List<PriorityResolution> get resolutionLog => List.unmodifiable(_resolutionLog);

  /// Highest active priority class
  BehaviorPriorityClass? get highestActivePriority {
    if (_activeBehaviors.isEmpty) return null;
    return _activeBehaviors.values
        .map((b) => b.priorityClass)
        .reduce((a, b) => a.numericPriority > b.numericPriority ? a : b);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESOLUTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Resolve priority for a new behavior entering the mix
  /// Returns list of resolutions (actions to take on existing behaviors)
  List<PriorityResolution> resolveEntry(String nodeId, BehaviorPriorityClass priority) {
    final resolutions = <PriorityResolution>[];

    for (final existing in _activeBehaviors.entries) {
      if (existing.key == nodeId) continue;

      final existingPriority = existing.value.priorityClass;
      final diff = priority.numericPriority - existingPriority.numericPriority;

      if (diff > 0) {
        // New behavior is higher priority → affect existing
        final action = existingPriority.conflictAction;
        resolutions.add(PriorityResolution(
          winnerId: nodeId,
          loserId: existing.key,
          action: action,
          duckAmountDb: _getDuckAmount(diff.abs() ~/ 20),
          delayMs: _getDelayAmount(diff.abs() ~/ 20),
        ));
      } else if (diff < 0) {
        // Existing behavior is higher priority → affect new
        final action = priority.conflictAction;
        resolutions.add(PriorityResolution(
          winnerId: existing.key,
          loserId: nodeId,
          action: action,
          duckAmountDb: _getDuckAmount(diff.abs() ~/ 20),
          delayMs: _getDelayAmount(diff.abs() ~/ 20),
        ));
      }
      // Equal priority → no conflict resolution needed
    }

    // Register the new behavior
    _activeBehaviors[nodeId] = ActiveBehavior(
      nodeId: nodeId,
      priorityClass: priority,
      startedAt: DateTime.now(),
    );

    // Log resolutions
    _resolutionLog.addAll(resolutions);
    if (_resolutionLog.length > 200) {
      _resolutionLog.removeRange(0, 100);
    }

    if (resolutions.isNotEmpty) {
      notifyListeners();
    }

    return resolutions;
  }

  /// Remove a behavior from active pool (finished playing)
  void removeBehavior(String nodeId) {
    if (_activeBehaviors.remove(nodeId) != null) {
      notifyListeners();
    }
  }

  /// Clear all active behaviors
  void clearAll() {
    _activeBehaviors.clear();
    notifyListeners();
  }

  /// Check if a priority class would be ducked by current active behaviors
  bool wouldBeDucked(BehaviorPriorityClass priority) {
    for (final existing in _activeBehaviors.values) {
      if (existing.priorityClass.numericPriority > priority.numericPriority) {
        return true;
      }
    }
    return false;
  }

  /// Get current duck level for a behavior (based on active higher-priority behaviors)
  double getDuckLevel(String nodeId) {
    final behavior = _activeBehaviors[nodeId];
    if (behavior == null) return 0.0;

    double maxDuck = 0.0;
    for (final other in _activeBehaviors.values) {
      if (other.nodeId == nodeId) continue;
      final diff = other.priorityClass.numericPriority - behavior.priorityClass.numericPriority;
      if (diff > 0) {
        final duckDb = _getDuckAmount(diff ~/ 20);
        if (duckDb < maxDuck) maxDuck = duckDb;
      }
    }
    return maxDuck;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  double _getDuckAmount(int classDifference) {
    return _duckAmounts[classDifference.clamp(1, 5)] ?? -6.0;
  }

  int _getDelayAmount(int classDifference) {
    return _delayAmounts[classDifference.clamp(1, 4)] ?? 100;
  }

  /// Clear resolution log
  void clearLog() {
    _resolutionLog.clear();
    notifyListeners();
  }
}
