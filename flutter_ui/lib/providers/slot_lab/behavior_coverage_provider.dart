/// Behavior Coverage Provider — SlotLab Middleware §17
///
/// Extends stage coverage tracking to include behavior node assignment.
/// Tracks which behavior node triggered each stage, calculates per-behavior
/// coverage percentage, and provides cross-reference display data.
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §17

import 'package:flutter/foundation.dart';

/// Coverage entry linking behavior node to stage
class BehaviorCoverageEntry {
  final String behaviorNodeId;
  final String stageName;
  final int triggerCount;
  final DateTime? lastTriggered;
  final BehaviorCoverageStatus status;

  const BehaviorCoverageEntry({
    required this.behaviorNodeId,
    required this.stageName,
    this.triggerCount = 0,
    this.lastTriggered,
    this.status = BehaviorCoverageStatus.untested,
  });

  BehaviorCoverageEntry copyWith({
    int? triggerCount,
    DateTime? lastTriggered,
    BehaviorCoverageStatus? status,
  }) => BehaviorCoverageEntry(
    behaviorNodeId: behaviorNodeId,
    stageName: stageName,
    triggerCount: triggerCount ?? this.triggerCount,
    lastTriggered: lastTriggered ?? this.lastTriggered,
    status: status ?? this.status,
  );
}

enum BehaviorCoverageStatus { untested, tested, verified }

/// Per-behavior coverage statistics
class BehaviorCoverageStats {
  final String behaviorNodeId;
  final int totalStages;
  final int testedStages;
  final int verifiedStages;

  const BehaviorCoverageStats({
    required this.behaviorNodeId,
    this.totalStages = 0,
    this.testedStages = 0,
    this.verifiedStages = 0,
  });

  int get untestedStages => totalStages - testedStages - verifiedStages;
  double get coveragePercent => totalStages > 0 ? (testedStages + verifiedStages) / totalStages : 0.0;
}

class BehaviorCoverageProvider extends ChangeNotifier {
  /// Coverage entries: key = "$behaviorNodeId::$stageName"
  final Map<String, BehaviorCoverageEntry> _entries = {};

  /// Expected stage count per behavior node
  final Map<String, int> _expectedStages = {};

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, BehaviorCoverageEntry> get entries => Map.unmodifiable(_entries);

  /// Get all entries for a behavior node
  List<BehaviorCoverageEntry> getEntriesForNode(String nodeId) =>
      _entries.values.where((e) => e.behaviorNodeId == nodeId).toList();

  /// Get all entries for a stage
  List<BehaviorCoverageEntry> getEntriesForStage(String stageName) =>
      _entries.values.where((e) => e.stageName == stageName).toList();

  /// Get coverage stats for a specific behavior node
  BehaviorCoverageStats getNodeStats(String nodeId) {
    final nodeEntries = getEntriesForNode(nodeId);
    return BehaviorCoverageStats(
      behaviorNodeId: nodeId,
      totalStages: _expectedStages[nodeId] ?? nodeEntries.length,
      testedStages: nodeEntries.where((e) => e.status == BehaviorCoverageStatus.tested).length,
      verifiedStages: nodeEntries.where((e) => e.status == BehaviorCoverageStatus.verified).length,
    );
  }

  /// Overall coverage percent
  double get overallCoverage {
    if (_entries.isEmpty) return 0.0;
    final tested = _entries.values.where(
      (e) => e.status != BehaviorCoverageStatus.untested,
    ).length;
    return tested / _entries.length;
  }

  /// Get all unique behavior node IDs
  Set<String> get trackedBehaviorNodes =>
      _entries.values.map((e) => e.behaviorNodeId).toSet();

  // ═══════════════════════════════════════════════════════════════════════════
  // RECORDING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register expected stages for a behavior node
  void registerExpectedStages(String nodeId, int count) {
    _expectedStages[nodeId] = count;
  }

  /// Record a trigger event
  void recordTrigger(String behaviorNodeId, String stageName) {
    final key = '$behaviorNodeId::$stageName';
    final existing = _entries[key];

    if (existing != null) {
      _entries[key] = existing.copyWith(
        triggerCount: existing.triggerCount + 1,
        lastTriggered: DateTime.now(),
        status: existing.status == BehaviorCoverageStatus.untested
            ? BehaviorCoverageStatus.tested
            : existing.status,
      );
    } else {
      _entries[key] = BehaviorCoverageEntry(
        behaviorNodeId: behaviorNodeId,
        stageName: stageName,
        triggerCount: 1,
        lastTriggered: DateTime.now(),
        status: BehaviorCoverageStatus.tested,
      );
    }
    notifyListeners();
  }

  /// Mark a behavior-stage pair as verified
  void markVerified(String behaviorNodeId, String stageName) {
    final key = '$behaviorNodeId::$stageName';
    final existing = _entries[key];
    if (existing != null) {
      _entries[key] = existing.copyWith(status: BehaviorCoverageStatus.verified);
      notifyListeners();
    }
  }

  /// Mark a behavior-stage pair as untested
  void markUntested(String behaviorNodeId, String stageName) {
    final key = '$behaviorNodeId::$stageName';
    final existing = _entries[key];
    if (existing != null) {
      _entries[key] = existing.copyWith(
        status: BehaviorCoverageStatus.untested,
        triggerCount: 0,
      );
      notifyListeners();
    }
  }

  /// Reset all coverage data
  void reset() {
    _entries.clear();
    notifyListeners();
  }

  /// Clear entries for a specific behavior node
  void clearNode(String nodeId) {
    _entries.removeWhere((_, e) => e.behaviorNodeId == nodeId);
    notifyListeners();
  }
}
