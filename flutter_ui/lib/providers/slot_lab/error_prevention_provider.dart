/// Error Prevention Provider — SlotLab Middleware §15
///
/// 7 continuous validations that run in real-time to catch
/// configuration errors before they reach the audio engine.
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §15

import 'package:flutter/foundation.dart';
import '../../models/behavior_tree_models.dart';

enum ValidationSeverity {
  error,
  warning,
  info,
}

enum ValidationType {
  /// Missing audio assignments on critical nodes
  missingAudio,
  /// Bus routing to non-existent bus
  invalidBusRoute,
  /// Priority conflict (same priority on conflicting nodes)
  priorityConflict,
  /// Circular transition rules
  circularTransition,
  /// Orphan hooks (hooks not mapped to any behavior)
  orphanHooks,
  /// Voice pool overflow risk
  voicePoolOverflow,
  /// Context override conflicts
  contextConflict,
}

extension ValidationTypeExtension on ValidationType {
  String get displayName {
    switch (this) {
      case ValidationType.missingAudio: return 'Missing Audio';
      case ValidationType.invalidBusRoute: return 'Invalid Bus Route';
      case ValidationType.priorityConflict: return 'Priority Conflict';
      case ValidationType.circularTransition: return 'Circular Transition';
      case ValidationType.orphanHooks: return 'Orphan Hooks';
      case ValidationType.voicePoolOverflow: return 'Voice Pool Overflow';
      case ValidationType.contextConflict: return 'Context Conflict';
    }
  }
}

class ValidationIssue {
  final ValidationType type;
  final ValidationSeverity severity;
  final String message;
  final String? nodeId;
  final String? suggestion;

  const ValidationIssue({
    required this.type,
    required this.severity,
    required this.message,
    this.nodeId,
    this.suggestion,
  });
}

class ErrorPreventionProvider extends ChangeNotifier {
  final List<ValidationIssue> _issues = [];
  bool _isValidating = false;
  DateTime? _lastValidation;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  List<ValidationIssue> get issues => List.unmodifiable(_issues);
  bool get isValidating => _isValidating;
  DateTime? get lastValidation => _lastValidation;

  int get errorCount => _issues.where((i) => i.severity == ValidationSeverity.error).length;
  int get warningCount => _issues.where((i) => i.severity == ValidationSeverity.warning).length;
  int get infoCount => _issues.where((i) => i.severity == ValidationSeverity.info).length;
  bool get hasErrors => errorCount > 0;
  bool get isClean => _issues.isEmpty;

  List<ValidationIssue> getIssuesForNode(String nodeId) =>
      _issues.where((i) => i.nodeId == nodeId).toList();

  // ═══════════════════════════════════════════════════════════════════════════
  // VALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Run all 7 validations against a behavior tree
  void validate(BehaviorTree tree, {Set<String>? validBuses}) {
    _isValidating = true;
    _issues.clear();
    notifyListeners();

    _validateMissingAudio(tree);
    _validateBusRoutes(tree, validBuses ?? _defaultBuses);
    _validatePriorityConflicts(tree);
    _validateOrphanHooks(tree);
    _validateVoicePoolRisk(tree);
    _validateContextConflicts(tree);
    // CircularTransition validation requires TransitionSystemProvider — deferred

    _isValidating = false;
    _lastValidation = DateTime.now();
    notifyListeners();
  }

  void _validateMissingAudio(BehaviorTree tree) {
    for (final node in tree.nodes.values) {
      if (!node.hasAudio) {
        final isCritical = node.basicParams.priorityClass == BehaviorPriorityClass.critical ||
                           node.basicParams.priorityClass == BehaviorPriorityClass.core;
        _issues.add(ValidationIssue(
          type: ValidationType.missingAudio,
          severity: isCritical ? ValidationSeverity.error : ValidationSeverity.warning,
          message: '${node.nodeType.category.displayName}/${node.nodeType.displayName} has no audio assigned',
          nodeId: node.id,
          suggestion: 'Use AutoBind or drag audio file to this node',
        ));
      }
    }
  }

  void _validateBusRoutes(BehaviorTree tree, Set<String> validBuses) {
    for (final node in tree.nodes.values) {
      if (!validBuses.contains(node.basicParams.busRoute)) {
        _issues.add(ValidationIssue(
          type: ValidationType.invalidBusRoute,
          severity: ValidationSeverity.error,
          message: '${node.id}: bus route "${node.basicParams.busRoute}" does not exist',
          nodeId: node.id,
          suggestion: 'Change to one of: ${validBuses.join(", ")}',
        ));
      }
    }
  }

  void _validatePriorityConflicts(BehaviorTree tree) {
    // Check for same-priority nodes in same category that could conflict
    final byCategory = tree.nodesByCategory;
    for (final entry in byCategory.entries) {
      final nodes = entry.value;
      final priorityGroups = <BehaviorPriorityClass, List<BehaviorNode>>{};
      for (final node in nodes) {
        priorityGroups.putIfAbsent(node.basicParams.priorityClass, () => []).add(node);
      }
      for (final group in priorityGroups.entries) {
        if (group.value.length > 1 && group.key == BehaviorPriorityClass.critical) {
          _issues.add(ValidationIssue(
            type: ValidationType.priorityConflict,
            severity: ValidationSeverity.warning,
            message: 'Multiple CRITICAL priority nodes in ${entry.key.displayName}: ${group.value.map((n) => n.nodeType.displayName).join(", ")}',
            suggestion: 'Consider differentiating priorities to avoid conflicts',
          ));
        }
      }
    }
  }

  void _validateOrphanHooks(BehaviorTree tree) {
    // All hooks should map to at least one node
    final mappedHooks = <String>{};
    for (final node in tree.nodes.values) {
      mappedHooks.addAll(node.mappedHooks);
    }
    // Known hooks that should exist
    const expectedHooks = [
      'onReelStop_r1', 'onReelStop_r2', 'onReelStop_r3', 'onReelStop_r4', 'onReelStop_r5',
      'onSymbolLand', 'onAnticipationStart', 'onAnticipationEnd',
      'onCascadeStart', 'onCascadeStep', 'onCascadeEnd',
      'onWinEvaluate_tier1', 'onWinEvaluate_tier2', 'onWinEvaluate_tier3',
      'onCountUpTick', 'onCountUpEnd',
      'onFeatureEnter', 'onFeatureLoop', 'onFeatureExit',
      'onSessionStart', 'onSessionEnd',
    ];
    for (final hook in expectedHooks) {
      if (!mappedHooks.contains(hook)) {
        _issues.add(ValidationIssue(
          type: ValidationType.orphanHooks,
          severity: ValidationSeverity.info,
          message: 'Hook "$hook" is not mapped to any behavior node',
          suggestion: 'This hook will be silently ignored during gameplay',
        ));
      }
    }
  }

  void _validateVoicePoolRisk(BehaviorTree tree) {
    // Count nodes that could fire simultaneously
    int maxSimultaneous = 0;
    for (final category in BehaviorCategory.values) {
      final nodes = tree.getNodesByCategory(category);
      for (final node in nodes) {
        if (node.hasAudio) {
          // Each node with audio could need voices
          maxSimultaneous += node.variantCount > 0 ? 1 : 0;
        }
      }
    }
    if (maxSimultaneous > 32) {
      _issues.add(ValidationIssue(
        type: ValidationType.voicePoolOverflow,
        severity: ValidationSeverity.warning,
        message: 'Up to $maxSimultaneous voices could be active simultaneously (pool max: 32)',
        suggestion: 'Consider reducing simultaneous sounds or increasing voice pool',
      ));
    }
  }

  void _validateContextConflicts(BehaviorTree tree) {
    for (final node in tree.nodes.values) {
      final contexts = node.contextOverrides;
      final contextIds = contexts.map((c) => c.contextId).toSet();
      if (contextIds.length != contexts.length) {
        _issues.add(ValidationIssue(
          type: ValidationType.contextConflict,
          severity: ValidationSeverity.error,
          message: '${node.id}: duplicate context overrides detected',
          nodeId: node.id,
          suggestion: 'Remove duplicate context entries',
        ));
      }
    }
  }

  static const Set<String> _defaultBuses = {
    'master', 'sfx_master', 'sfx_reels', 'sfx_cascade', 'sfx_wins',
    'sfx_features', 'sfx_jackpot', 'sfx_ui', 'sfx_system',
    'music_master', 'music_base', 'music_feature', 'music_celebration',
    'ambience', 'voice',
  };

  /// Clear all issues
  void clearIssues() {
    _issues.clear();
    notifyListeners();
  }
}
