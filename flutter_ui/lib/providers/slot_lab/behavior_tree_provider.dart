/// Behavior Tree Provider — SlotLab Middleware §5
///
/// State management for the behavior tree — the primary authoring
/// abstraction that maps ~22 behavior nodes to 300+ engine hooks.
///
/// Responsibilities:
/// - Owns the BehaviorTree (all 22 nodes)
/// - Handles node CRUD, sound assignments, context overrides
/// - Dispatches engine hooks to behavior nodes
/// - Tracks runtime state (active/idle/cooldown/error)
/// - Provides coverage statistics for the Coverage Panel
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §5

import 'package:flutter/foundation.dart';
import '../../models/behavior_tree_models.dart';

class BehaviorTreeProvider extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// The behavior tree containing all nodes
  BehaviorTree _tree = BehaviorTree.defaultTree();

  /// Currently selected node ID (for inspector panel)
  String? _selectedNodeId;

  /// Current game context (base, freeSpins, bonus, etc.)
  String _activeContext = 'base';

  /// Hook → BehaviorNode mapping cache (rebuilt on tree changes)
  Map<String, List<String>> _hookToNodeMap = {};

  /// Whether tree has unsaved changes
  bool _isDirty = false;

  /// Granular change tracking for selective UI rebuilds
  bool _changeTree = false;
  bool _changeSelection = false;
  bool _changeNodeState = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  BehaviorTree get tree => _tree;
  String? get selectedNodeId => _selectedNodeId;
  String get activeContext => _activeContext;
  bool get isDirty => _isDirty;

  /// Currently selected node (convenience)
  BehaviorNode? get selectedNode =>
      _selectedNodeId != null ? _tree.getNode(_selectedNodeId!) : null;

  /// All nodes as flat list
  List<BehaviorNode> get allNodes => _tree.nodes.values.toList();

  /// Nodes grouped by category
  Map<BehaviorCategory, List<BehaviorNode>> get nodesByCategory =>
      _tree.nodesByCategory;

  /// Total coverage percentage (0.0-1.0)
  double get coveragePercent => _tree.coveragePercent;

  /// Count of bound nodes
  int get boundNodeCount => _tree.boundNodeCount;

  /// Count of total nodes
  int get totalNodeCount => _tree.nodeCount;

  /// Nodes with errors
  List<BehaviorNode> get errorNodes =>
      allNodes.where((n) => n.runtimeState == BehaviorNodeState.error).toList();

  /// Nodes currently active (playing)
  List<BehaviorNode> get activeNodes =>
      allNodes.where((n) => n.runtimeState == BehaviorNodeState.active).toList();

  /// Unbound nodes (no audio assigned)
  List<BehaviorNode> get unboundNodes =>
      allNodes.where((n) => !n.hasAudio).toList();

  // ═══════════════════════════════════════════════════════════════════════════
  // TREE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize with default 22-node tree
  void initDefaultTree() {
    _tree = BehaviorTree.defaultTree();
    _rebuildHookMap();
    _isDirty = false;
    _changeTree = true;
    _notify();
  }

  /// Initialize with specific node types (for templates)
  void initFromNodeTypes(List<BehaviorNodeType> types) {
    _tree = BehaviorTree.fromNodeTypes(types);
    _rebuildHookMap();
    _isDirty = false;
    _changeTree = true;
    _notify();
  }

  /// Load tree from JSON (deserialization)
  void loadFromJson(Map<String, dynamic> json) {
    _tree = BehaviorTree.fromJson(json);
    _rebuildHookMap();
    _isDirty = false;
    _changeTree = true;
    _notify();
  }

  /// Export tree to JSON (serialization)
  Map<String, dynamic> toJson() => _tree.toJson();

  /// Reset tree to default 22 nodes
  void resetToDefault() {
    initDefaultTree();
    _isDirty = true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NODE OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Select a node for the inspector panel
  void selectNode(String? nodeId) {
    if (_selectedNodeId == nodeId) return;
    _selectedNodeId = nodeId;
    _changeSelection = true;
    _notify();
  }

  /// Update a node (replaces entire node)
  void updateNode(BehaviorNode node) {
    _tree.setNode(node);
    _isDirty = true;
    _changeTree = true;
    _rebuildHookMap();
    _notify();
  }

  /// Update node's basic params
  void updateNodeBasicParams(String nodeId, BasicParams params) {
    final node = _tree.getNode(nodeId);
    if (node == null) return;
    _tree.setNode(node.copyWith(basicParams: params));
    _isDirty = true;
    _changeTree = true;
    _notify();
  }

  /// Update node's advanced params
  void updateNodeAdvancedParams(String nodeId, AdvancedParams params) {
    final node = _tree.getNode(nodeId);
    if (node == null) return;
    _tree.setNode(node.copyWith(advancedParams: params));
    _isDirty = true;
    _changeTree = true;
    _notify();
  }

  /// Update node's expert params
  void updateNodeExpertParams(String nodeId, ExpertParams params) {
    final node = _tree.getNode(nodeId);
    if (node == null) return;
    _tree.setNode(node.copyWith(expertParams: params));
    _isDirty = true;
    _changeTree = true;
    _notify();
  }

  /// Update node's playback mode
  void updateNodePlaybackMode(String nodeId, PlaybackMode mode) {
    final node = _tree.getNode(nodeId);
    if (node == null) return;
    _tree.setNode(node.copyWith(playbackMode: mode));
    _isDirty = true;
    _changeTree = true;
    _notify();
  }

  /// Update node's variant config
  void updateNodeVariantConfig(String nodeId, VariantConfig config) {
    final node = _tree.getNode(nodeId);
    if (node == null) return;
    _tree.setNode(node.copyWith(variantConfig: config));
    _isDirty = true;
    _changeTree = true;
    _notify();
  }

  /// Update node's emotional weight
  void updateNodeEmotionalWeight(String nodeId, double weight) {
    final node = _tree.getNode(nodeId);
    if (node == null) return;
    _tree.setNode(node.copyWith(emotionalWeight: weight.clamp(0.0, 1.0)));
    _isDirty = true;
    _changeTree = true;
    _notify();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SOUND ASSIGNMENTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a sound assignment to a node
  void addSoundAssignment(String nodeId, BehaviorSoundAssignment assignment) {
    final node = _tree.getNode(nodeId);
    if (node == null) return;
    final maxVariants = node.variantConfig.maxVariants;
    if (node.soundAssignments.length >= maxVariants) return;

    final updatedAssignments = [...node.soundAssignments, assignment];
    _tree.setNode(node.copyWith(soundAssignments: updatedAssignments));
    _isDirty = true;
    _changeTree = true;
    _notify();
  }

  /// Remove a sound assignment from a node
  void removeSoundAssignment(String nodeId, String assignmentId) {
    final node = _tree.getNode(nodeId);
    if (node == null) return;

    final updatedAssignments = node.soundAssignments
        .where((a) => a.id != assignmentId)
        .toList();
    _tree.setNode(node.copyWith(soundAssignments: updatedAssignments));
    _isDirty = true;
    _changeTree = true;
    _notify();
  }

  /// Replace all sound assignments for a node (used by AutoBind)
  void setSoundAssignments(String nodeId, List<BehaviorSoundAssignment> assignments) {
    final node = _tree.getNode(nodeId);
    if (node == null) return;
    _tree.setNode(node.copyWith(soundAssignments: assignments));
    _isDirty = true;
    _changeTree = true;
    _notify();
  }

  /// Clear all sound assignments from a node
  void clearSoundAssignments(String nodeId) {
    setSoundAssignments(nodeId, []);
  }

  /// Clear all auto-bound assignments (keep manual)
  void clearAutoBoundAssignments() {
    for (final node in allNodes) {
      final manualOnly = node.soundAssignments
          .where((a) => !a.autoBound)
          .toList();
      if (manualOnly.length != node.soundAssignments.length) {
        _tree.setNode(node.copyWith(soundAssignments: manualOnly));
      }
    }
    _isDirty = true;
    _changeTree = true;
    _notify();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTEXT OVERRIDES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set active game context
  void setActiveContext(String contextId) {
    if (_activeContext == contextId) return;
    _activeContext = contextId;
    _changeTree = true;
    _notify();
  }

  /// Add or update a context override for a node
  void setContextOverride(String nodeId, ContextOverride override) {
    final node = _tree.getNode(nodeId);
    if (node == null) return;

    final overrides = [...node.contextOverrides];
    final existingIndex = overrides.indexWhere((o) => o.contextId == override.contextId);
    if (existingIndex >= 0) {
      overrides[existingIndex] = override;
    } else {
      overrides.add(override);
    }
    _tree.setNode(node.copyWith(contextOverrides: overrides));
    _isDirty = true;
    _changeTree = true;
    _notify();
  }

  /// Remove a context override
  void removeContextOverride(String nodeId, String contextId) {
    final node = _tree.getNode(nodeId);
    if (node == null) return;

    final overrides = node.contextOverrides
        .where((o) => o.contextId != contextId)
        .toList();
    _tree.setNode(node.copyWith(contextOverrides: overrides));
    _isDirty = true;
    _changeTree = true;
    _notify();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RUNTIME STATE (called during spin/gameplay)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set a node's runtime state
  void setNodeState(String nodeId, BehaviorNodeState state) {
    final node = _tree.getNode(nodeId);
    if (node == null) return;
    if (node.runtimeState == state) return;
    node.runtimeState = state;
    _changeNodeState = true;
    _notify();
  }

  /// Reset all nodes to idle
  void resetAllNodeStates() {
    for (final node in allNodes) {
      node.runtimeState = BehaviorNodeState.idle;
    }
    _changeNodeState = true;
    _notify();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ENGINE HOOK DISPATCH
  // ═══════════════════════════════════════════════════════════════════════════

  /// Dispatch an engine hook — finds matching behavior nodes and triggers them
  /// Returns list of node IDs that were triggered
  List<String> dispatchHook(String hookName) {
    final nodeIds = _hookToNodeMap[hookName];
    if (nodeIds == null || nodeIds.isEmpty) return [];

    final triggered = <String>[];
    for (final nodeId in nodeIds) {
      final node = _tree.getNode(nodeId);
      if (node == null) continue;

      // Check if node is disabled in current context
      if (node.isDisabledInContext(_activeContext)) continue;

      // Check if node has audio
      if (!node.hasAudio) continue;

      // Select variant
      final variantIndex = node.selectVariant();
      if (variantIndex < 0) continue;

      // Set node to active
      setNodeState(nodeId, BehaviorNodeState.active);
      triggered.add(nodeId);
    }

    return triggered;
  }

  /// Get all hooks that map to a specific node
  List<String> getHooksForNode(String nodeId) {
    final node = _tree.getNode(nodeId);
    if (node == null) return [];
    return node.mappedHooks;
  }

  /// Get all node IDs that listen to a specific hook
  List<String> getNodesForHook(String hookName) {
    return _hookToNodeMap[hookName] ?? [];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COVERAGE STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get coverage stats per category
  Map<BehaviorCategory, CoverageStat> get coverageByCategory {
    final result = <BehaviorCategory, CoverageStat>{};
    for (final cat in BehaviorCategory.values) {
      final catNodes = _tree.getNodesByCategory(cat);
      if (catNodes.isEmpty) continue;
      final bound = catNodes.where((n) => n.hasAudio).length;
      result[cat] = CoverageStat(
        total: catNodes.length,
        bound: bound,
        autoBound: catNodes.where((n) => n.coverageStatus == BehaviorCoverageStatus.autoBound).length,
        manualBound: catNodes.where((n) => n.coverageStatus == BehaviorCoverageStatus.manualBound).length,
      );
    }
    return result;
  }

  /// Get all unbound nodes (for coverage panel warnings)
  List<BehaviorNode> get unboundNodesList {
    return allNodes.where((n) => !n.hasAudio).toList()
      ..sort((a, b) => a.category.index.compareTo(b.category.index));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Rebuild the hook → node mapping cache
  void _rebuildHookMap() {
    _hookToNodeMap = {};
    for (final node in allNodes) {
      for (final hook in node.mappedHooks) {
        _hookToNodeMap.putIfAbsent(hook, () => []).add(node.id);
      }
    }
  }

  /// Batched notification (prevents cascading rebuilds)
  void _notify() {
    // Reset all change flags after notify
    _changeTree = false;
    _changeSelection = false;
    _changeNodeState = false;
    notifyListeners();
  }

  /// Check if a specific change type occurred
  bool get hasTreeChange => _changeTree;
  bool get hasSelectionChange => _changeSelection;
  bool get hasNodeStateChange => _changeNodeState;

  /// Mark as saved (clears dirty flag)
  void markSaved() {
    _isDirty = false;
    _notify();
  }
}

// =============================================================================
// COVERAGE STAT (for coverage panel)
// =============================================================================

/// Coverage statistics for a category
class CoverageStat {
  final int total;
  final int bound;
  final int autoBound;
  final int manualBound;

  const CoverageStat({
    required this.total,
    required this.bound,
    required this.autoBound,
    required this.manualBound,
  });

  int get unbound => total - bound;
  double get percent => total > 0 ? bound / total : 0.0;
}
