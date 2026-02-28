/// Ducking System Provider
///
/// Extracted from MiddlewareProvider as part of P0.2 decomposition.
/// Manages audio ducking matrix (Wwise/FMOD-style sidechain compression).
///
/// Ducking automatically reduces volume of target buses when source buses
/// are active. Example: Music ducks when Voice is playing.

import 'package:flutter/foundation.dart';
import '../../models/middleware_models.dart';
import '../../services/ducking_service.dart';
import '../../src/rust/native_ffi.dart';

/// Provider for managing ducking rules
class DuckingSystemProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  /// Ducking rules storage
  final Map<int, DuckingRule> _duckingRules = {};

  /// Next available ducking rule ID
  int _nextDuckingRuleId = 1;

  DuckingSystemProvider({required NativeFFI ffi}) : _ffi = ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all ducking rules
  Map<int, DuckingRule> get rules => Map.unmodifiable(_duckingRules);

  /// Get all ducking rules as list
  List<DuckingRule> get duckingRules => _duckingRules.values.toList();

  /// Get count of ducking rules
  int get ruleCount => _duckingRules.length;

  /// Get a specific ducking rule
  DuckingRule? getRule(int ruleId) => _duckingRules[ruleId];

  /// Get rules by source bus
  List<DuckingRule> getRulesForSourceBus(int sourceBusId) {
    return _duckingRules.values
        .where((r) => r.sourceBusId == sourceBusId)
        .toList();
  }

  /// Get rules by target bus
  List<DuckingRule> getRulesForTargetBus(int targetBusId) {
    return _duckingRules.values
        .where((r) => r.targetBusId == targetBusId)
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DUCKING RULES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a ducking rule
  DuckingRule addRule({
    required String sourceBus,
    required int sourceBusId,
    required String targetBus,
    required int targetBusId,
    double duckAmountDb = -6.0,
    double attackMs = 50.0,
    double releaseMs = 500.0,
    double threshold = 0.01,
    DuckingCurve curve = DuckingCurve.linear,
  }) {
    final id = _nextDuckingRuleId++;

    final rule = DuckingRule(
      id: id,
      sourceBus: sourceBus,
      sourceBusId: sourceBusId,
      targetBus: targetBus,
      targetBusId: targetBusId,
      duckAmountDb: duckAmountDb,
      attackMs: attackMs,
      releaseMs: releaseMs,
      threshold: threshold,
      curve: curve,
    );

    _duckingRules[id] = rule;

    // Register with Rust
    _ffi.middlewareAddDuckingRule(rule);

    // Sync with DuckingService for Dart-side ducking
    DuckingService.instance.addRule(rule);

    notifyListeners();
    return rule;
  }

  /// Register a ducking rule (from JSON import or preset)
  void registerRule(DuckingRule rule) {
    _duckingRules[rule.id] = rule;

    // Update next ID if needed
    if (rule.id >= _nextDuckingRuleId) {
      _nextDuckingRuleId = rule.id + 1;
    }

    // Register with Rust
    _ffi.middlewareAddDuckingRule(rule);

    // Sync with DuckingService
    DuckingService.instance.addRule(rule);

    notifyListeners();
  }

  /// Update a ducking rule
  void updateRule(int ruleId, DuckingRule rule) {
    if (!_duckingRules.containsKey(ruleId)) return;

    _duckingRules[ruleId] = rule;

    // Re-register (remove + add)
    _ffi.middlewareRemoveDuckingRule(ruleId);
    _ffi.middlewareAddDuckingRule(rule);

    // Sync with DuckingService
    DuckingService.instance.updateRule(rule);

    notifyListeners();
  }

  /// Remove a ducking rule
  void removeRule(int ruleId) {
    _duckingRules.remove(ruleId);
    _ffi.middlewareRemoveDuckingRule(ruleId);

    // Sync with DuckingService
    DuckingService.instance.removeRule(ruleId);

    notifyListeners();
  }

  /// Enable/disable a ducking rule
  void setRuleEnabled(int ruleId, bool enabled) {
    final rule = _duckingRules[ruleId];
    if (rule == null) return;

    final updatedRule = rule.copyWith(enabled: enabled);
    _duckingRules[ruleId] = updatedRule;
    _ffi.middlewareSetDuckingRuleEnabled(ruleId, enabled);

    // Sync with DuckingService
    DuckingService.instance.updateRule(updatedRule);

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export ducking rules to JSON
  List<Map<String, dynamic>> toJson() {
    return _duckingRules.values.map((r) => r.toJson()).toList();
  }

  /// Import ducking rules from JSON
  void fromJson(List<dynamic> json) {
    for (final item in json) {
      final rule = DuckingRule.fromJson(item as Map<String, dynamic>);
      registerRule(rule);
    }
  }

  /// Clear all ducking rules
  void clear() {
    // Remove from services
    for (final ruleId in _duckingRules.keys.toList()) {
      _ffi.middlewareRemoveDuckingRule(ruleId);
      DuckingService.instance.removeRule(ruleId);
    }

    _duckingRules.clear();
    _nextDuckingRuleId = 1;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // §28 — PER-BEHAVIOR-NODE DUCKING ASSIGNMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Behavior node → ducking rule assignments
  /// Key: behavior node ID (e.g., 'reel_stop', 'cascade_step')
  /// Value: list of rule IDs assigned to that node
  final Map<String, List<BehaviorNodeDuckingAssignment>> _behaviorAssignments = {};

  /// Get ducking assignments for a behavior node
  List<BehaviorNodeDuckingAssignment> getAssignmentsForNode(String behaviorNodeId) =>
      List.unmodifiable(_behaviorAssignments[behaviorNodeId] ?? []);

  /// Get ducking rules active for a behavior node
  List<DuckingRule> getDuckingRulesForNode(String behaviorNodeId) {
    final assignments = _behaviorAssignments[behaviorNodeId];
    if (assignments == null) return [];
    return assignments
        .where((a) => a.enabled)
        .map((a) => _duckingRules[a.ruleId])
        .whereType<DuckingRule>()
        .toList();
  }

  /// Assign a ducking rule to a behavior node
  void addBehaviorAssignment({
    required String behaviorNodeId,
    required int ruleId,
    bool enabled = true,
    double? duckOverrideDb,
  }) {
    if (!_duckingRules.containsKey(ruleId)) return;
    _behaviorAssignments.putIfAbsent(behaviorNodeId, () => []).add(
      BehaviorNodeDuckingAssignment(
        behaviorNodeId: behaviorNodeId,
        ruleId: ruleId,
        enabled: enabled,
        duckOverrideDb: duckOverrideDb,
      ),
    );
    notifyListeners();
  }

  /// Remove a ducking assignment from a behavior node
  void removeBehaviorAssignment(String behaviorNodeId, int ruleId) {
    _behaviorAssignments[behaviorNodeId]?.removeWhere((a) => a.ruleId == ruleId);
    if (_behaviorAssignments[behaviorNodeId]?.isEmpty ?? false) {
      _behaviorAssignments.remove(behaviorNodeId);
    }
    notifyListeners();
  }

  /// Enable/disable a specific assignment
  void setBehaviorAssignmentEnabled(String behaviorNodeId, int ruleId, bool enabled) {
    final assignments = _behaviorAssignments[behaviorNodeId];
    if (assignments == null) return;
    final index = assignments.indexWhere((a) => a.ruleId == ruleId);
    if (index >= 0) {
      assignments[index] = assignments[index].copyWith(enabled: enabled);
      notifyListeners();
    }
  }

  /// Get all behavior nodes that have ducking assignments
  Set<String> get assignedBehaviorNodes => _behaviorAssignments.keys.toSet();

  /// Behavior assignment serialization
  List<Map<String, dynamic>> behaviorAssignmentsToJson() {
    final result = <Map<String, dynamic>>[];
    for (final entry in _behaviorAssignments.entries) {
      for (final assignment in entry.value) {
        result.add(assignment.toJson());
      }
    }
    return result;
  }

  /// Behavior assignment deserialization
  void behaviorAssignmentsFromJson(List<dynamic> json) {
    _behaviorAssignments.clear();
    for (final item in json) {
      final assignment = BehaviorNodeDuckingAssignment.fromJson(item as Map<String, dynamic>);
      _behaviorAssignments.putIfAbsent(assignment.behaviorNodeId, () => []).add(assignment);
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _duckingRules.clear();
    _behaviorAssignments.clear();
    super.dispose();
  }
}

/// Per-behavior-node ducking assignment (§28)
class BehaviorNodeDuckingAssignment {
  final String behaviorNodeId;
  final int ruleId;
  final bool enabled;
  /// Override the rule's duckAmountDb for this behavior node (null = use rule default)
  final double? duckOverrideDb;

  const BehaviorNodeDuckingAssignment({
    required this.behaviorNodeId,
    required this.ruleId,
    this.enabled = true,
    this.duckOverrideDb,
  });

  BehaviorNodeDuckingAssignment copyWith({
    bool? enabled,
    double? duckOverrideDb,
  }) => BehaviorNodeDuckingAssignment(
    behaviorNodeId: behaviorNodeId,
    ruleId: ruleId,
    enabled: enabled ?? this.enabled,
    duckOverrideDb: duckOverrideDb ?? this.duckOverrideDb,
  );

  Map<String, dynamic> toJson() => {
    'behaviorNodeId': behaviorNodeId,
    'ruleId': ruleId,
    'enabled': enabled,
    'duckOverrideDb': duckOverrideDb,
  };

  factory BehaviorNodeDuckingAssignment.fromJson(Map<String, dynamic> json) =>
      BehaviorNodeDuckingAssignment(
        behaviorNodeId: json['behaviorNodeId'] as String,
        ruleId: json['ruleId'] as int,
        enabled: json['enabled'] as bool? ?? true,
        duckOverrideDb: (json['duckOverrideDb'] as num?)?.toDouble(),
      );
}
