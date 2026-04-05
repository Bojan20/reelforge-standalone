// Nested Bus Hierarchy Service
//
// Provides hierarchical bus management for professional audio mixing:
// - Tree structure with parent-child relationships
// - Level-based indentation for mixer visualization
// - Drag-drop parent reassignment
// - Collapse/expand bus groups
// - Auto-routing (child buses default to parent)
// - Effective volume propagation through hierarchy

import 'package:flutter/foundation.dart';
import '../models/advanced_middleware_models.dart';
import '../providers/subsystems/bus_hierarchy_provider.dart';

// =============================================================================
// BUS NODE MODEL
// =============================================================================

/// Represents a node in the bus hierarchy tree
class BusNode {
  /// Unique bus ID
  final int id;

  /// Display name
  final String name;

  /// Parent bus ID (null = root/master)
  final int? parentId;

  /// List of child bus IDs
  final List<int> childIds;

  /// Nesting level (0 = root, 1 = first level children, etc.)
  final int level;

  /// Whether this node is collapsed in the UI
  bool collapsed;

  /// Whether this is a folder (group) node vs leaf node
  final bool isGroup;

  /// Original AudioBus reference
  final AudioBus? audioBus;

  BusNode({
    required this.id,
    required this.name,
    this.parentId,
    List<int>? childIds,
    this.level = 0,
    this.collapsed = false,
    this.isGroup = false,
    this.audioBus,
  }) : childIds = childIds ?? [];

  /// Check if this node has children
  bool get hasChildren => childIds.isNotEmpty;

  /// Check if this is the master bus
  bool get isMaster => parentId == null && id == 0;

  /// Create a copy with optional modifications
  BusNode copyWith({
    int? id,
    String? name,
    int? parentId,
    List<int>? childIds,
    int? level,
    bool? collapsed,
    bool? isGroup,
    AudioBus? audioBus,
  }) {
    return BusNode(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      childIds: childIds ?? List.from(this.childIds),
      level: level ?? this.level,
      collapsed: collapsed ?? this.collapsed,
      isGroup: isGroup ?? this.isGroup,
      audioBus: audioBus ?? this.audioBus,
    );
  }

  @override
  String toString() => 'BusNode($name, level=$level, children=${childIds.length})';
}

// =============================================================================
// BUS MOVE RESULT
// =============================================================================

/// Result of a bus move operation
enum BusMoveResult {
  success,
  wouldCreateCycle,
  invalidTarget,
  invalidSource,
  sameParent,
}

// =============================================================================
// NESTED BUS HIERARCHY SERVICE
// =============================================================================

/// Service for managing nested bus hierarchies
class NestedBusHierarchyService extends ChangeNotifier {
  /// Singleton instance
  static final NestedBusHierarchyService _instance = NestedBusHierarchyService._internal();
  static NestedBusHierarchyService get instance => _instance;

  NestedBusHierarchyService._internal();

  /// Reference to the bus hierarchy provider
  BusHierarchyProvider? _provider;

  /// Bus nodes indexed by ID
  final Map<int, BusNode> _nodes = {};

  /// Collapse state cache
  final Map<int, bool> _collapseState = {};

  /// Maximum nesting depth
  static const int maxNestingDepth = 8;

  // ===========================================================================
  // INITIALIZATION
  // ===========================================================================

  /// Initialize with a bus hierarchy provider
  void init(BusHierarchyProvider provider) {
    _provider = provider;
    _provider!.addListener(_onProviderChanged);
    _rebuildTree();
  }

  /// Handle provider changes
  void _onProviderChanged() {
    _rebuildTree();
    notifyListeners();
  }

  /// Rebuild the tree from provider data
  void _rebuildTree() {
    if (_provider == null) return;

    _nodes.clear();

    // First pass: create all nodes
    for (final bus in _provider!.allBuses) {
      _nodes[bus.busId] = BusNode(
        id: bus.busId,
        name: bus.name,
        parentId: bus.parentBusId,
        childIds: List.from(bus.childBusIds),
        level: 0,
        collapsed: _collapseState[bus.busId] ?? false,
        isGroup: bus.childBusIds.isNotEmpty,
        audioBus: bus,
      );
    }

    // Second pass: calculate levels
    for (final node in _nodes.values) {
      _nodes[node.id] = node.copyWith(level: _calculateLevel(node.id));
    }
  }

  /// Calculate the nesting level of a bus
  int _calculateLevel(int busId) {
    int level = 0;
    int? currentId = _nodes[busId]?.parentId;

    while (currentId != null && level < maxNestingDepth) {
      level++;
      currentId = _nodes[currentId]?.parentId;
    }

    return level;
  }

  // ===========================================================================
  // GETTERS
  // ===========================================================================

  /// Get all bus nodes
  List<BusNode> get allNodes => _nodes.values.toList();

  /// Get a specific node by ID
  BusNode? getNode(int busId) => _nodes[busId];

  /// Get the root node (master)
  BusNode? get rootNode => _nodes[0];

  /// Get children of a node
  List<BusNode> getChildren(int busId) {
    final node = _nodes[busId];
    if (node == null) return [];

    return node.childIds
        .map((id) => _nodes[id])
        .whereType<BusNode>()
        .toList();
  }

  /// Get all descendants of a node (recursive)
  List<BusNode> getDescendants(int busId) {
    final descendants = <BusNode>[];
    final node = _nodes[busId];
    if (node == null) return descendants;

    for (final childId in node.childIds) {
      final child = _nodes[childId];
      if (child != null) {
        descendants.add(child);
        descendants.addAll(getDescendants(childId));
      }
    }

    return descendants;
  }

  /// Get parent chain from a node to root
  List<BusNode> getParentChain(int busId) {
    final chain = <BusNode>[];
    int? currentId = busId;

    while (currentId != null) {
      final node = _nodes[currentId];
      if (node == null) break;
      chain.add(node);
      currentId = node.parentId;
    }

    return chain;
  }

  /// Get all visible nodes (respecting collapse state)
  List<BusNode> getVisibleNodes() {
    final visible = <BusNode>[];
    _addVisibleNodes(0, visible);
    return visible;
  }

  void _addVisibleNodes(int busId, List<BusNode> visible) {
    final node = _nodes[busId];
    if (node == null) return;

    visible.add(node);

    if (!node.collapsed) {
      for (final childId in node.childIds) {
        _addVisibleNodes(childId, visible);
      }
    }
  }

  /// Get flattened list for mixer display (respects collapse, sorted by hierarchy)
  List<BusNode> getFlattenedForMixer() {
    final result = <BusNode>[];
    _flattenNode(0, result);
    return result;
  }

  void _flattenNode(int busId, List<BusNode> result) {
    final node = _nodes[busId];
    if (node == null) return;

    result.add(node);

    if (!node.collapsed) {
      for (final childId in node.childIds) {
        _flattenNode(childId, result);
      }
    }
  }

  // ===========================================================================
  // COLLAPSE/EXPAND
  // ===========================================================================

  /// Toggle collapse state of a bus group
  void toggleCollapse(int busId) {
    final node = _nodes[busId];
    if (node == null || !node.hasChildren) return;

    _collapseState[busId] = !(node.collapsed);
    _nodes[busId] = node.copyWith(collapsed: !node.collapsed);
    notifyListeners();
  }

  /// Collapse a bus group
  void collapse(int busId) {
    final node = _nodes[busId];
    if (node == null || !node.hasChildren) return;

    _collapseState[busId] = true;
    _nodes[busId] = node.copyWith(collapsed: true);
    notifyListeners();
  }

  /// Expand a bus group
  void expand(int busId) {
    final node = _nodes[busId];
    if (node == null) return;

    _collapseState[busId] = false;
    _nodes[busId] = node.copyWith(collapsed: false);
    notifyListeners();
  }

  /// Collapse all groups
  void collapseAll() {
    for (final node in _nodes.values) {
      if (node.hasChildren) {
        _collapseState[node.id] = true;
        _nodes[node.id] = node.copyWith(collapsed: true);
      }
    }
    notifyListeners();
  }

  /// Expand all groups
  void expandAll() {
    for (final node in _nodes.values) {
      _collapseState[node.id] = false;
      _nodes[node.id] = node.copyWith(collapsed: false);
    }
    notifyListeners();
  }

  // ===========================================================================
  // HIERARCHY MODIFICATIONS
  // ===========================================================================

  /// Check if moving a bus to a new parent would create a cycle
  bool wouldCreateCycle(int busId, int newParentId) {
    // Can't parent to self
    if (busId == newParentId) return true;

    // Can't parent to any descendant
    final descendants = getDescendants(busId);
    if (descendants.any((d) => d.id == newParentId)) return true;

    return false;
  }

  /// Move a bus to a new parent
  /// Returns the result of the operation
  BusMoveResult moveBus(int busId, int newParentId) {
    if (_provider == null) return BusMoveResult.invalidSource;

    final node = _nodes[busId];
    if (node == null) return BusMoveResult.invalidSource;

    // Can't move master
    if (node.isMaster) return BusMoveResult.invalidSource;

    final newParent = _nodes[newParentId];
    if (newParent == null) return BusMoveResult.invalidTarget;

    // Check for same parent
    if (node.parentId == newParentId) return BusMoveResult.sameParent;

    // Check for cycles
    if (wouldCreateCycle(busId, newParentId)) return BusMoveResult.wouldCreateCycle;

    // Check depth limit
    final newLevel = _calculateLevel(newParentId) + 1;
    final maxDescendantDepth = _getMaxDescendantDepth(busId);
    if (newLevel + maxDescendantDepth > maxNestingDepth) {
      return BusMoveResult.wouldCreateCycle; // Exceeds depth limit
    }

    // Perform the move via provider
    _performMove(busId, newParentId);

    return BusMoveResult.success;
  }

  /// Get maximum depth of descendants
  int _getMaxDescendantDepth(int busId) {
    final descendants = getDescendants(busId);
    if (descendants.isEmpty) return 0;

    int maxDepth = 0;
    for (final d in descendants) {
      final relativeDepth = d.level - (_nodes[busId]?.level ?? 0);
      if (relativeDepth > maxDepth) maxDepth = relativeDepth;
    }
    return maxDepth;
  }

  /// Perform the actual move operation
  void _performMove(int busId, int newParentId) {
    if (_provider == null) return;

    final bus = _provider!.getBus(busId);
    final oldParent = bus?.parentBusId != null ? _provider!.getBus(bus!.parentBusId!) : null;
    final newParent = _provider!.getBus(newParentId);

    if (bus == null || newParent == null) return;

    // Remove from old parent's children
    if (oldParent != null) {
      oldParent.childBusIds.remove(busId);
    }

    // Add to new parent's children
    newParent.childBusIds.add(busId);

    // Create new bus with updated parent
    // Note: Since AudioBus.parentBusId is final, we need to create a new bus
    final updatedBus = AudioBus(
      busId: bus.busId,
      name: bus.name,
      parentBusId: newParentId,
      childBusIds: bus.childBusIds,
      volume: bus.volume,
      pan: bus.pan,
      mute: bus.mute,
      solo: bus.solo,
      preInserts: bus.preInserts,
      postInserts: bus.postInserts,
    );

    // Remove old and add new
    _provider!.removeBus(busId);
    _provider!.addBus(updatedBus);

    _rebuildTree();
    notifyListeners();
  }

  /// Create a new bus under a parent
  BusNode? createBus({
    required String name,
    required int parentId,
    bool isGroup = false,
  }) {
    if (_provider == null) return null;

    final bus = _provider!.createBus(name: name, parentBusId: parentId);
    _rebuildTree();
    return _nodes[bus.busId];
  }

  /// Delete a bus (reparents children to grandparent)
  bool deleteBus(int busId) {
    if (_provider == null) return false;

    final node = _nodes[busId];
    if (node == null || node.isMaster) return false;

    _provider!.removeBus(busId);
    _rebuildTree();
    return true;
  }

  // ===========================================================================
  // EFFECTIVE VOLUME CALCULATION
  // ===========================================================================

  /// Calculate effective volume considering parent chain
  double getEffectiveVolume(int busId) {
    if (_provider == null) return 0.0;
    return _provider!.getEffectiveVolume(busId);
  }

  /// Get all buses that should be affected by a bus mute/solo
  /// (includes all descendants)
  List<int> getAffectedBusIds(int busId) {
    final affected = <int>[busId];
    final descendants = getDescendants(busId);
    affected.addAll(descendants.map((d) => d.id));
    return affected;
  }

  // ===========================================================================
  // VISUALIZATION HELPERS
  // ===========================================================================

  /// Get indent width for a node (in pixels)
  double getIndentWidth(int busId, {double indentPerLevel = 20.0}) {
    final node = _nodes[busId];
    if (node == null) return 0.0;
    return node.level * indentPerLevel;
  }

  /// Check if a node is visible (no collapsed ancestors)
  bool isNodeVisible(int busId) {
    final chain = getParentChain(busId);
    // Skip self, check if any ancestor is collapsed
    for (int i = 1; i < chain.length; i++) {
      if (chain[i].collapsed) return false;
    }
    return true;
  }

  /// Get tree connector info for drawing hierarchy lines
  TreeConnectorInfo getConnectorInfo(int busId) {
    final node = _nodes[busId];
    if (node == null) {
      return const TreeConnectorInfo(
        hasParent: false,
        hasSiblingAbove: false,
        hasSiblingBelow: false,
        hasChildren: false,
      );
    }

    final parent = node.parentId != null ? _nodes[node.parentId] : null;
    final siblings = parent?.childIds ?? [];
    final siblingIndex = siblings.indexOf(busId);

    return TreeConnectorInfo(
      hasParent: node.parentId != null,
      hasSiblingAbove: siblingIndex > 0,
      hasSiblingBelow: siblingIndex < siblings.length - 1,
      hasChildren: node.hasChildren,
    );
  }

  // ===========================================================================
  // SERIALIZATION
  // ===========================================================================

  /// Export collapse state to JSON
  Map<String, dynamic> exportCollapseState() {
    return {
      'collapsed': _collapseState.map((k, v) => MapEntry(k.toString(), v)),
    };
  }

  /// Import collapse state from JSON
  void importCollapseState(Map<String, dynamic> json) {
    _collapseState.clear();
    final collapsed = json['collapsed'] as Map<String, dynamic>?;
    if (collapsed != null) {
      for (final entry in collapsed.entries) {
        final id = int.tryParse(entry.key);
        if (id != null && entry.value is bool) {
          _collapseState[id] = entry.value as bool;
        }
      }
    }
    _rebuildTree();
    notifyListeners();
  }

  // ===========================================================================
  // CLEANUP
  // ===========================================================================

  @override
  void dispose() {
    _provider?.removeListener(_onProviderChanged);
    super.dispose();
  }
}

// =============================================================================
// TREE CONNECTOR INFO
// =============================================================================

/// Information for drawing tree hierarchy connectors
class TreeConnectorInfo {
  final bool hasParent;
  final bool hasSiblingAbove;
  final bool hasSiblingBelow;
  final bool hasChildren;

  const TreeConnectorInfo({
    required this.hasParent,
    required this.hasSiblingAbove,
    required this.hasSiblingBelow,
    required this.hasChildren,
  });

  /// Returns the type of vertical line to draw
  /// null = no line, 'full' = full height, 'half' = half height (last sibling)
  String? get verticalLineType {
    if (!hasParent) return null;
    return hasSiblingBelow ? 'full' : 'half';
  }

  /// Whether to draw a horizontal branch line
  bool get drawHorizontalBranch => hasParent;

  /// Whether to draw an expand/collapse indicator
  bool get drawExpandIndicator => hasChildren;
}
