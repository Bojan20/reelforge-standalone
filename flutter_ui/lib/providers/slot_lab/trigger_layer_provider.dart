/// Trigger Layer Provider — SlotLab Middleware §3
///
/// Maps engine events to behavior node triggers.
/// Engine fires raw hooks (onReelStop_r1, onCascadeStep, etc.)
/// → Trigger Layer resolves which behavior node(s) should activate
/// → State Gate validates
/// → Priority Engine resolves conflicts
/// → Orchestration Engine shapes audio
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §3

import 'package:flutter/foundation.dart';
import '../../models/behavior_tree_models.dart';

/// A trigger binding: engine hook → behavior node(s)
class TriggerBinding {
  /// Engine hook name (e.g., 'onReelStop_r1', 'onCascadeStep')
  final String hookName;
  /// Behavior node IDs to activate when this hook fires
  final List<String> targetNodeIds;
  /// Whether this binding is enabled
  final bool enabled;
  /// Optional delay before triggering (ms)
  final int delayMs;
  /// Optional condition expression (simple string for now)
  final String? condition;

  const TriggerBinding({
    required this.hookName,
    required this.targetNodeIds,
    this.enabled = true,
    this.delayMs = 0,
    this.condition,
  });

  TriggerBinding copyWith({
    List<String>? targetNodeIds,
    bool? enabled,
    int? delayMs,
    String? condition,
  }) => TriggerBinding(
    hookName: hookName,
    targetNodeIds: targetNodeIds ?? this.targetNodeIds,
    enabled: enabled ?? this.enabled,
    delayMs: delayMs ?? this.delayMs,
    condition: condition ?? this.condition,
  );

  Map<String, dynamic> toJson() => {
    'hookName': hookName,
    'targetNodeIds': targetNodeIds,
    'enabled': enabled,
    'delayMs': delayMs,
    'condition': condition,
  };

  factory TriggerBinding.fromJson(Map<String, dynamic> json) => TriggerBinding(
    hookName: json['hookName'] as String,
    targetNodeIds: (json['targetNodeIds'] as List<dynamic>).cast<String>(),
    enabled: json['enabled'] as bool? ?? true,
    delayMs: json['delayMs'] as int? ?? 0,
    condition: json['condition'] as String?,
  );
}

/// Result of a trigger resolution
class TriggerResult {
  final String hookName;
  final List<String> activatedNodeIds;
  final List<String> blockedNodeIds;
  final DateTime timestamp;

  const TriggerResult({
    required this.hookName,
    required this.activatedNodeIds,
    this.blockedNodeIds = const [],
    required this.timestamp,
  });
}

class TriggerLayerProvider extends ChangeNotifier {
  /// All trigger bindings: key = hookName
  final Map<String, TriggerBinding> _bindings = {};

  /// Trigger history (diagnostics)
  final List<TriggerResult> _history = [];

  /// Auto-generated bindings from behavior tree node types
  bool _autoBindingsEnabled = true;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, TriggerBinding> get bindings => Map.unmodifiable(_bindings);
  List<TriggerResult> get history => List.unmodifiable(_history);
  bool get autoBindingsEnabled => _autoBindingsEnabled;

  /// Get binding for a specific hook
  TriggerBinding? getBinding(String hookName) => _bindings[hookName];

  /// Get all hooks that target a specific node
  List<String> getHooksForNode(String nodeId) {
    return _bindings.entries
        .where((e) => e.value.targetNodeIds.contains(nodeId))
        .map((e) => e.key)
        .toList();
  }

  /// Get unbound hooks (hooks with no targets)
  List<String> get unboundHooks => _bindings.entries
      .where((e) => e.value.targetNodeIds.isEmpty)
      .map((e) => e.key)
      .toList();

  // ═══════════════════════════════════════════════════════════════════════════
  // BINDING MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set or update a binding
  void setBinding(TriggerBinding binding) {
    _bindings[binding.hookName] = binding;
    notifyListeners();
  }

  /// Remove a binding
  void removeBinding(String hookName) {
    _bindings.remove(hookName);
    notifyListeners();
  }

  /// Add a target node to an existing binding
  void addTargetNode(String hookName, String nodeId) {
    final existing = _bindings[hookName];
    if (existing != null) {
      if (existing.targetNodeIds.contains(nodeId)) return;
      _bindings[hookName] = existing.copyWith(
        targetNodeIds: [...existing.targetNodeIds, nodeId],
      );
    } else {
      _bindings[hookName] = TriggerBinding(
        hookName: hookName,
        targetNodeIds: [nodeId],
      );
    }
    notifyListeners();
  }

  /// Remove a target node from a binding
  void removeTargetNode(String hookName, String nodeId) {
    final existing = _bindings[hookName];
    if (existing == null) return;
    _bindings[hookName] = existing.copyWith(
      targetNodeIds: existing.targetNodeIds.where((id) => id != nodeId).toList(),
    );
    notifyListeners();
  }

  /// Enable/disable a binding
  void setBindingEnabled(String hookName, bool enabled) {
    final existing = _bindings[hookName];
    if (existing == null) return;
    _bindings[hookName] = existing.copyWith(enabled: enabled);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO-BIND FROM BEHAVIOR TREE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate default bindings from behavior node type mapped hooks
  void generateAutoBindings() {
    if (!_autoBindingsEnabled) return;

    for (final nodeType in BehaviorNodeType.values) {
      for (final hook in nodeType.mappedHooks) {
        final existing = _bindings[hook];
        if (existing == null) {
          _bindings[hook] = TriggerBinding(
            hookName: hook,
            targetNodeIds: [nodeType.nodeId],
          );
        } else if (!existing.targetNodeIds.contains(nodeType.nodeId)) {
          _bindings[hook] = existing.copyWith(
            targetNodeIds: [...existing.targetNodeIds, nodeType.nodeId],
          );
        }
      }
    }
    notifyListeners();
  }

  /// Set auto-bindings mode
  void setAutoBindingsEnabled(bool enabled) {
    _autoBindingsEnabled = enabled;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRIGGER RESOLUTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Resolve which behavior nodes should be triggered for a hook
  TriggerResult resolve(String hookName) {
    final binding = _bindings[hookName];
    final result = TriggerResult(
      hookName: hookName,
      activatedNodeIds: binding != null && binding.enabled
          ? List.unmodifiable(binding.targetNodeIds)
          : const [],
      timestamp: DateTime.now(),
    );

    _history.add(result);
    if (_history.length > 500) _history.removeRange(0, 250);

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DIAGNOSTICS
  // ═══════════════════════════════════════════════════════════════════════════

  void clearHistory() {
    _history.clear();
    notifyListeners();
  }

  void clearAllBindings() {
    _bindings.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
    'bindings': _bindings.values.map((b) => b.toJson()).toList(),
    'autoBindingsEnabled': _autoBindingsEnabled,
  };

  void fromJson(Map<String, dynamic> json) {
    _bindings.clear();
    final bindingsList = json['bindings'] as List<dynamic>?;
    if (bindingsList != null) {
      for (final item in bindingsList) {
        final binding = TriggerBinding.fromJson(item as Map<String, dynamic>);
        _bindings[binding.hookName] = binding;
      }
    }
    _autoBindingsEnabled = json['autoBindingsEnabled'] as bool? ?? true;
    notifyListeners();
  }
}
