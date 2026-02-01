/// DependencyResolver - Block dependency resolution for Feature Builder
///
/// Handles dependency validation, cycle detection, conflict resolution,
/// and topological sorting of feature blocks.
/// Part of P13 Feature Builder Panel implementation.

import '../models/feature_block_models.dart';

/// Result of dependency resolution for the resolver service
class ResolverResult {
  /// Whether resolution was successful (no cycles, no critical conflicts)
  final bool isValid;

  /// Sorted list of block IDs in dependency order
  final List<String> sortedBlockIds;

  /// Detected cycles (if any)
  final List<DependencyCycle> cycles;

  /// Detected conflicts
  final List<ResolverConflict> conflicts;

  /// Warnings (non-critical issues)
  final List<ResolverWarning> warnings;

  /// Missing required dependencies
  final List<MissingDependency> missingDependencies;

  const ResolverResult({
    required this.isValid,
    required this.sortedBlockIds,
    this.cycles = const [],
    this.conflicts = const [],
    this.warnings = const [],
    this.missingDependencies = const [],
  });

  /// Create a failed result
  factory ResolverResult.failed({
    List<DependencyCycle> cycles = const [],
    List<ResolverConflict> conflicts = const [],
    List<MissingDependency> missingDependencies = const [],
  }) {
    return ResolverResult(
      isValid: false,
      sortedBlockIds: [],
      cycles: cycles,
      conflicts: conflicts,
      missingDependencies: missingDependencies,
    );
  }

  /// Whether there are any issues (even non-blocking)
  bool get hasIssues =>
      cycles.isNotEmpty ||
      conflicts.isNotEmpty ||
      warnings.isNotEmpty ||
      missingDependencies.isNotEmpty;

  /// Get all critical issues
  List<String> get criticalIssues {
    final issues = <String>[];
    for (final cycle in cycles) {
      issues.add('Cycle detected: ${cycle.path.join(' → ')} → ${cycle.path.first}');
    }
    for (final conflict in conflicts.where((c) => c.severity >= 2)) {
      issues.add('Conflict: ${conflict.description}');
    }
    for (final missing in missingDependencies) {
      issues.add('Missing required: ${missing.blockId} requires ${missing.requiredBlockId}');
    }
    return issues;
  }
}

/// Represents a dependency cycle
class DependencyCycle {
  /// Block IDs in the cycle path
  final List<String> path;

  const DependencyCycle(this.path);

  @override
  String toString() => 'Cycle: ${path.join(' → ')} → ${path.first}';
}

/// Represents a dependency conflict (resolver-specific)
class ResolverConflict {
  /// First block in conflict
  final String blockIdA;

  /// Second block in conflict
  final String blockIdB;

  /// Description of the conflict
  final String description;

  /// Severity: 0=info, 1=warning, 2=error, 3=critical
  final int severity;

  /// Suggested resolution
  final String? resolution;

  const ResolverConflict({
    required this.blockIdA,
    required this.blockIdB,
    required this.description,
    this.severity = 1,
    this.resolution,
  });

  bool get isBlocking => severity >= 2;
}

/// Represents a dependency warning (resolver-specific)
class ResolverWarning {
  /// Block ID with the warning
  final String blockId;

  /// Warning message
  final String message;

  /// Category of warning
  final String category;

  const ResolverWarning({
    required this.blockId,
    required this.message,
    this.category = 'general',
  });
}

/// Represents a missing required dependency
class MissingDependency {
  /// Block ID that has the missing dependency
  final String blockId;

  /// Required block ID that is missing
  final String requiredBlockId;

  /// Description of why it's needed
  final String? reason;

  const MissingDependency({
    required this.blockId,
    required this.requiredBlockId,
    this.reason,
  });
}

/// Dependency graph node for internal processing
class _DependencyNode {
  final String id;
  final Set<String> requires;
  final Set<String> enables;
  final Set<String> modifies;
  final Set<String> isModifiedBy; // Computed inverse of modifies
  final Set<String> conflicts;
  int inDegree;

  _DependencyNode({
    required this.id,
    Set<String>? requires,
    Set<String>? enables,
    Set<String>? modifies,
    Set<String>? isModifiedBy,
    Set<String>? conflicts,
  })  : requires = requires ?? {},
        enables = enables ?? {},
        modifies = modifies ?? {},
        isModifiedBy = isModifiedBy ?? {},
        conflicts = conflicts ?? {},
        inDegree = 0;

  /// All blocks this node depends on (for topological sort)
  Set<String> get allDependencies => {...requires, ...isModifiedBy};
}

/// Service for resolving block dependencies
class DependencyResolver {
  // Singleton pattern
  static final DependencyResolver _instance = DependencyResolver._internal();
  factory DependencyResolver() => _instance;
  static DependencyResolver get instance => _instance;
  DependencyResolver._internal();

  /// Resolve dependencies for a set of blocks
  ResolverResult resolve(List<FeatureBlockBase> blocks) {
    if (blocks.isEmpty) {
      return const ResolverResult(
        isValid: true,
        sortedBlockIds: [],
      );
    }

    // Build dependency graph
    final graph = _buildGraph(blocks);
    final blockIds = blocks.map((b) => b.id).toSet();

    // Check for missing required dependencies
    final missingDeps = _findMissingDependencies(graph, blockIds, blocks);
    if (missingDeps.isNotEmpty) {
      return ResolverResult.failed(
        missingDependencies: missingDeps,
      );
    }

    // Detect cycles using DFS
    final cycles = _detectCycles(graph, blockIds);
    if (cycles.isNotEmpty) {
      return ResolverResult.failed(cycles: cycles);
    }

    // Find conflicts
    final conflicts = _findConflicts(graph, blockIds, blocks);
    final blockingConflicts = conflicts.where((c) => c.isBlocking).toList();
    if (blockingConflicts.isNotEmpty) {
      return ResolverResult.failed(
        conflicts: blockingConflicts,
      );
    }

    // Perform topological sort
    final sortedIds = _topologicalSort(graph, blockIds);

    // Generate warnings
    final warnings = _generateWarnings(graph, blockIds, blocks);

    return ResolverResult(
      isValid: true,
      sortedBlockIds: sortedIds,
      conflicts: conflicts,
      warnings: warnings,
    );
  }

  /// Build dependency graph from blocks
  Map<String, _DependencyNode> _buildGraph(List<FeatureBlockBase> blocks) {
    final graph = <String, _DependencyNode>{};

    // First pass: create nodes and direct dependencies
    for (final block in blocks) {
      final node = _DependencyNode(id: block.id);

      for (final dep in block.dependencies) {
        switch (dep.type) {
          case DependencyType.requires:
            node.requires.add(dep.targetBlockId);
            break;
          case DependencyType.enables:
            node.enables.add(dep.targetBlockId);
            break;
          case DependencyType.modifies:
            node.modifies.add(dep.targetBlockId);
            break;
          case DependencyType.conflicts:
            node.conflicts.add(dep.targetBlockId);
            break;
        }
      }

      graph[block.id] = node;
    }

    // Second pass: compute inverse relationships (isModifiedBy)
    // If block A modifies block B, then block B isModifiedBy A
    for (final block in blocks) {
      final node = graph[block.id];
      if (node == null) continue;

      for (final modifiedBlockId in node.modifies) {
        final modifiedNode = graph[modifiedBlockId];
        if (modifiedNode != null) {
          modifiedNode.isModifiedBy.add(block.id);
        }
      }
    }

    return graph;
  }

  /// Find missing required dependencies
  List<MissingDependency> _findMissingDependencies(
    Map<String, _DependencyNode> graph,
    Set<String> availableBlockIds,
    List<FeatureBlockBase> blocks,
  ) {
    final missing = <MissingDependency>[];

    for (final block in blocks) {
      if (!block.isEnabled) continue; // Skip disabled blocks

      for (final dep in block.dependencies) {
        if (dep.type == DependencyType.requires) {
          // Check if required block exists and is enabled
          final requiredBlock = blocks.where((b) => b.id == dep.targetBlockId).firstOrNull;
          if (requiredBlock == null) {
            missing.add(MissingDependency(
              blockId: block.id,
              requiredBlockId: dep.targetBlockId,
              reason: dep.description,
            ));
          } else if (!requiredBlock.isEnabled) {
            missing.add(MissingDependency(
              blockId: block.id,
              requiredBlockId: dep.targetBlockId,
              reason: '${dep.targetBlockId} is disabled but required',
            ));
          }
        }
      }
    }

    return missing;
  }

  /// Detect cycles using DFS with coloring
  List<DependencyCycle> _detectCycles(
    Map<String, _DependencyNode> graph,
    Set<String> blockIds,
  ) {
    final cycles = <DependencyCycle>[];

    // Node colors: 0=white (unvisited), 1=gray (in progress), 2=black (done)
    final colors = <String, int>{};
    final parent = <String, String?>{};

    for (final id in blockIds) {
      colors[id] = 0;
      parent[id] = null;
    }

    void dfs(String nodeId, List<String> path) {
      colors[nodeId] = 1; // Mark as in progress
      path.add(nodeId);

      final node = graph[nodeId];
      if (node != null) {
        for (final depId in node.allDependencies) {
          if (!blockIds.contains(depId)) continue; // Skip external deps

          if (colors[depId] == 1) {
            // Found a cycle - extract the cycle path
            final cycleStartIndex = path.indexOf(depId);
            if (cycleStartIndex >= 0) {
              final cyclePath = path.sublist(cycleStartIndex);
              cycles.add(DependencyCycle(cyclePath));
            }
          } else if (colors[depId] == 0) {
            dfs(depId, path);
          }
        }
      }

      colors[nodeId] = 2; // Mark as done
      path.removeLast();
    }

    for (final id in blockIds) {
      if (colors[id] == 0) {
        dfs(id, []);
      }
    }

    return cycles;
  }

  /// Find conflicts between blocks
  List<ResolverConflict> _findConflicts(
    Map<String, _DependencyNode> graph,
    Set<String> blockIds,
    List<FeatureBlockBase> blocks,
  ) {
    final conflicts = <ResolverConflict>[];

    for (final block in blocks) {
      if (!block.isEnabled) continue;

      final node = graph[block.id];
      if (node == null) continue;

      for (final conflictId in node.conflicts) {
        // Check if conflicting block is enabled
        final conflictBlock = blocks.where((b) => b.id == conflictId).firstOrNull;
        if (conflictBlock != null && conflictBlock.isEnabled) {
          // Find the dependency definition for description
          final dep = block.dependencies.firstWhere(
            (d) => d.targetBlockId == conflictId && d.type == DependencyType.conflicts,
            orElse: () => BlockDependency.conflicts(
              source: block.id,
              target: conflictId,
              description: 'Blocks conflict with each other',
            ),
          );

          conflicts.add(ResolverConflict(
            blockIdA: block.id,
            blockIdB: conflictId,
            description: dep.description ?? 'Blocks conflict with each other',
            severity: dep.type.severity, // Get severity from DependencyType extension
          ));
        }
      }
    }

    // Deduplicate (A conflicts B and B conflicts A)
    final seen = <String>{};
    return conflicts.where((c) {
      final key = [c.blockIdA, c.blockIdB]..sort();
      final keyStr = key.join(':');
      if (seen.contains(keyStr)) return false;
      seen.add(keyStr);
      return true;
    }).toList();
  }

  /// Topological sort using Kahn's algorithm
  List<String> _topologicalSort(
    Map<String, _DependencyNode> graph,
    Set<String> blockIds,
  ) {
    // Calculate in-degrees
    final inDegree = <String, int>{};
    for (final id in blockIds) {
      inDegree[id] = 0;
    }

    for (final id in blockIds) {
      final node = graph[id];
      if (node != null) {
        for (final depId in node.allDependencies) {
          if (blockIds.contains(depId)) {
            inDegree[id] = (inDegree[id] ?? 0) + 1;
          }
        }
      }
    }

    // Queue of nodes with no incoming edges
    final queue = <String>[];
    for (final id in blockIds) {
      if (inDegree[id] == 0) {
        queue.add(id);
      }
    }

    final sorted = <String>[];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      sorted.add(current);

      // Find blocks that depend on current
      for (final id in blockIds) {
        final node = graph[id];
        if (node != null && node.allDependencies.contains(current)) {
          inDegree[id] = (inDegree[id] ?? 1) - 1;
          if (inDegree[id] == 0) {
            queue.add(id);
          }
        }
      }
    }

    return sorted;
  }

  /// Generate warnings for non-critical issues
  List<ResolverWarning> _generateWarnings(
    Map<String, _DependencyNode> graph,
    Set<String> blockIds,
    List<FeatureBlockBase> blocks,
  ) {
    final warnings = <ResolverWarning>[];

    for (final block in blocks) {
      if (!block.isEnabled) continue;

      final node = graph[block.id];
      if (node == null) continue;

      // Warn about optional dependencies that aren't enabled
      for (final dep in block.dependencies) {
        if (dep.type == DependencyType.enables) {
          final enabledBlock = blocks.where((b) => b.id == dep.targetBlockId).firstOrNull;
          if (enabledBlock == null || !enabledBlock.isEnabled) {
            warnings.add(ResolverWarning(
              blockId: block.id,
              message: 'Optional block "${dep.targetBlockId}" could enhance ${block.name}',
              category: 'suggestion',
            ));
          }
        }
      }

      // Warn about modifications where target doesn't acknowledge modifier
      if (node.modifies.isNotEmpty) {
        for (final modifiedId in node.modifies) {
          final modifiedNode = graph[modifiedId];
          if (modifiedNode != null && !modifiedNode.isModifiedBy.contains(block.id)) {
            // This warning is informational only - the relationship is one-way by design
            // (source declares modifies, target doesn't need to declare anything back)
          }
        }
      }
    }

    return warnings;
  }

  /// Get dependency graph data for visualization
  ResolverGraphData getVisualizationData(List<FeatureBlockBase> blocks) {
    final nodes = <ResolverGraphNode>[];
    final edges = <ResolverGraphEdge>[];

    // Create nodes
    for (final block in blocks) {
      nodes.add(ResolverGraphNode(
        id: block.id,
        name: block.name,
        category: block.category,
        isEnabled: block.isEnabled,
        canBeDisabled: block.canBeDisabled,
      ));
    }

    // Create edges
    for (final block in blocks) {
      for (final dep in block.dependencies) {
        edges.add(ResolverGraphEdge(
          from: dep.sourceBlockId,
          to: dep.targetBlockId,
          type: dep.type,
          description: dep.description,
        ));
      }
    }

    return ResolverGraphData(nodes: nodes, edges: edges);
  }

  /// Get blocks in the correct initialization order
  List<String> getInitializationOrder(List<FeatureBlockBase> blocks) {
    final result = resolve(blocks);
    return result.isValid ? result.sortedBlockIds : [];
  }

  /// Check if adding a block would create issues
  ResolverResult previewAddBlock(
    List<FeatureBlockBase> existingBlocks,
    FeatureBlockBase newBlock,
  ) {
    return resolve([...existingBlocks, newBlock]);
  }

  /// Check if removing a block would create issues
  ResolverResult previewRemoveBlock(
    List<FeatureBlockBase> existingBlocks,
    String blockIdToRemove,
  ) {
    final remaining = existingBlocks.where((b) => b.id != blockIdToRemove).toList();
    return resolve(remaining);
  }

  /// Get all blocks that depend on a given block
  Set<String> getDependents(
    List<FeatureBlockBase> blocks,
    String blockId,
  ) {
    final dependents = <String>{};

    for (final block in blocks) {
      for (final dep in block.dependencies) {
        if (dep.targetBlockId == blockId && dep.type == DependencyType.requires) {
          dependents.add(block.id);
        }
      }
    }

    // Also check computed isModifiedBy relationships
    final graph = _buildGraph(blocks);
    final node = graph[blockId];
    if (node != null) {
      // Blocks that this block modifies consider this block as a dependent
      for (final modifiesId in node.modifies) {
        dependents.add(modifiesId);
      }
    }

    return dependents;
  }

  /// Get all blocks that a given block depends on
  Set<String> getDependencies(
    List<FeatureBlockBase> blocks,
    String blockId,
  ) {
    final block = blocks.where((b) => b.id == blockId).firstOrNull;
    if (block == null) return {};

    final dependencies = <String>{};
    for (final dep in block.dependencies) {
      if (dep.type == DependencyType.requires) {
        dependencies.add(dep.targetBlockId);
      }
    }

    // Also check computed isModifiedBy relationships
    final graph = _buildGraph(blocks);
    final node = graph[blockId];
    if (node != null) {
      dependencies.addAll(node.isModifiedBy);
    }

    return dependencies;
  }
}

/// Data structure for graph visualization (resolver-specific)
class ResolverGraphData {
  final List<ResolverGraphNode> nodes;
  final List<ResolverGraphEdge> edges;

  const ResolverGraphData({
    required this.nodes,
    required this.edges,
  });

  /// Get edges of a specific type
  List<ResolverGraphEdge> getEdgesOfType(DependencyType type) {
    return edges.where((e) => e.type == type).toList();
  }

  /// Get incoming edges for a node
  List<ResolverGraphEdge> getIncomingEdges(String nodeId) {
    return edges.where((e) => e.to == nodeId).toList();
  }

  /// Get outgoing edges for a node
  List<ResolverGraphEdge> getOutgoingEdges(String nodeId) {
    return edges.where((e) => e.from == nodeId).toList();
  }
}

/// Graph node for visualization (resolver-specific)
class ResolverGraphNode {
  final String id;
  final String name;
  final BlockCategory category;
  final bool isEnabled;
  final bool canBeDisabled;

  const ResolverGraphNode({
    required this.id,
    required this.name,
    required this.category,
    required this.isEnabled,
    required this.canBeDisabled,
  });
}

/// Graph edge for visualization (resolver-specific)
class ResolverGraphEdge {
  final String from;
  final String to;
  final DependencyType type;
  final String? description;

  const ResolverGraphEdge({
    required this.from,
    required this.to,
    required this.type,
    this.description,
  });

  /// Get edge color for visualization
  String get colorHex {
    switch (type) {
      case DependencyType.requires:
        return '#FF4444'; // Red - required
      case DependencyType.enables:
        return '#44FF44'; // Green - enables
      case DependencyType.modifies:
        return '#4444FF'; // Blue - modifies
      case DependencyType.conflicts:
        return '#FF8800'; // Orange - conflicts
    }
  }

  /// Get line style for visualization
  String get lineStyle {
    switch (type) {
      case DependencyType.requires:
        return 'solid';
      case DependencyType.enables:
        return 'dashed';
      case DependencyType.modifies:
        return 'dotted';
      case DependencyType.conflicts:
        return 'double';
    }
  }
}

// ============================================================================
// Type Aliases for API Compatibility
// ============================================================================
// These aliases allow external code to use `resolver.DependencyResolutionResult`
// without needing to know the internal class names.

/// Type alias for dependency resolution result
typedef DependencyResolutionResult = ResolverResult;

/// Type alias for dependency graph data
typedef DependencyGraphData = ResolverGraphData;

// ============================================================================
// Block Dependency Matrix
// ============================================================================
// Centralized documentation of expected block dependencies.
// This serves as a reference for validating block implementations.
// ============================================================================

/// Centralized dependency matrix for all feature blocks.
///
/// This class documents the expected dependencies for each block type.
/// Use [validateBlockDependencies] to verify a block's dependencies match
/// the expected configuration.
class BlockDependencyMatrix {
  BlockDependencyMatrix._();

  /// The dependency matrix: blockId -> dependency spec
  static const Map<String, BlockDependencySpec> matrix = {
    // ========== Core Blocks ==========
    'game_core': BlockDependencySpec(
      requires: [],
      modifies: [],
      enables: ['grid', 'symbol_set'],
      conflicts: [],
    ),
    'grid': BlockDependencySpec(
      requires: ['game_core'],
      modifies: [],
      enables: [],
      conflicts: [],
    ),
    'symbol_set': BlockDependencySpec(
      requires: ['game_core'],
      modifies: [],
      enables: ['anticipation', 'wild_features'],
      conflicts: [],
    ),

    // ========== Feature Blocks ==========
    'free_spins': BlockDependencySpec(
      requires: ['game_core', 'symbol_set'],
      modifies: ['win_presentation', 'music_states'],
      enables: [],
      conflicts: [],
    ),
    'cascades': BlockDependencySpec(
      requires: ['game_core', 'grid', 'symbol_set'],
      modifies: ['win_presentation'],
      enables: ['free_spins'],
      conflicts: [],
    ),
    'hold_and_win': BlockDependencySpec(
      requires: ['game_core', 'grid', 'symbol_set'],
      modifies: ['win_presentation', 'music_states'],
      enables: ['jackpot'],
      conflicts: ['respin'],
    ),
    'bonus_game': BlockDependencySpec(
      requires: ['game_core', 'symbol_set'],
      modifies: ['music_states'],
      enables: ['multiplier'],
      conflicts: [],
    ),
    'jackpot': BlockDependencySpec(
      requires: ['game_core'],
      modifies: ['win_presentation', 'music_states'],
      enables: [],
      conflicts: [],
    ),
    'multiplier': BlockDependencySpec(
      requires: ['game_core'],
      modifies: ['win_presentation'],
      enables: [],
      conflicts: [],
    ),

    // ========== P13.9.8: Anticipation Block ==========
    'anticipation': BlockDependencySpec(
      requires: ['symbol_set'], // Needs scatter/bonus/wild symbol
      modifies: ['grid', 'music_states'],
      enables: [],
      conflicts: [],
    ),

    // ========== P13.9.8: Wild Features Block ==========
    'wild_features': BlockDependencySpec(
      requires: ['symbol_set'], // Needs wild symbol enabled
      modifies: ['win_presentation'],
      enables: ['multiplier'], // If multiplier_range is not empty
      conflicts: [],
    ),

    // ========== Presentation Blocks ==========
    'win_presentation': BlockDependencySpec(
      requires: ['game_core'],
      modifies: [],
      enables: [],
      conflicts: [],
    ),
    'music_states': BlockDependencySpec(
      requires: ['game_core'],
      modifies: [],
      enables: [],
      conflicts: [],
    ),
    'transitions': BlockDependencySpec(
      requires: ['game_core'],
      modifies: [],
      enables: [],
      conflicts: [],
    ),

    // ========== Other Feature Blocks ==========
    'respin': BlockDependencySpec(
      requires: ['game_core', 'grid'],
      modifies: [],
      enables: [],
      conflicts: ['hold_and_win'],
    ),
    'gambling': BlockDependencySpec(
      requires: ['game_core'],
      modifies: ['win_presentation'],
      enables: [],
      conflicts: [],
    ),
    'collector': BlockDependencySpec(
      requires: ['game_core', 'symbol_set'],
      modifies: ['win_presentation'],
      enables: [],
      conflicts: [],
    ),
  };

  /// Validate a block's dependencies against the matrix.
  ///
  /// Returns a list of validation messages. Empty list means valid.
  static List<String> validateBlockDependencies(FeatureBlockBase block) {
    final spec = matrix[block.id];
    if (spec == null) {
      return ['Block "${block.id}" not found in dependency matrix'];
    }

    final messages = <String>[];
    final actualRequires = <String>{};
    final actualModifies = <String>{};
    final actualEnables = <String>{};
    final actualConflicts = <String>{};

    for (final dep in block.dependencies) {
      switch (dep.type) {
        case DependencyType.requires:
          actualRequires.add(dep.targetBlockId);
          break;
        case DependencyType.modifies:
          actualModifies.add(dep.targetBlockId);
          break;
        case DependencyType.enables:
          actualEnables.add(dep.targetBlockId);
          break;
        case DependencyType.conflicts:
          actualConflicts.add(dep.targetBlockId);
          break;
      }
    }

    // Check for missing required dependencies
    for (final required in spec.requires) {
      if (!actualRequires.contains(required)) {
        messages.add('Missing required dependency: $required');
      }
    }

    // Check for conflicts that should be declared
    for (final conflict in spec.conflicts) {
      if (!actualConflicts.contains(conflict)) {
        messages.add('Expected conflict with: $conflict');
      }
    }

    return messages;
  }

  /// Get all blocks that depend on a given block (from the matrix).
  static List<String> getBlocksThatRequire(String blockId) {
    final result = <String>[];
    for (final entry in matrix.entries) {
      if (entry.value.requires.contains(blockId)) {
        result.add(entry.key);
      }
    }
    return result;
  }

  /// Get all blocks that a given block enables.
  static List<String> getEnabledBlocks(String blockId) {
    final spec = matrix[blockId];
    return spec?.enables ?? [];
  }

  /// Check if enabling blockA would require enabling blockB.
  static bool wouldRequireEnabling(String blockA, String blockB) {
    final spec = matrix[blockA];
    if (spec == null) return false;
    return spec.requires.contains(blockB);
  }

  /// Check if two blocks conflict.
  static bool blocksConflict(String blockA, String blockB) {
    final specA = matrix[blockA];
    final specB = matrix[blockB];
    if (specA == null || specB == null) return false;
    return specA.conflicts.contains(blockB) || specB.conflicts.contains(blockA);
  }

  /// Get the complete dependency chain for a block (recursive).
  static Set<String> getDependencyChain(String blockId) {
    final chain = <String>{};
    _addDependencies(blockId, chain);
    return chain;
  }

  static void _addDependencies(String blockId, Set<String> chain) {
    final spec = matrix[blockId];
    if (spec == null) return;

    for (final required in spec.requires) {
      if (!chain.contains(required)) {
        chain.add(required);
        _addDependencies(required, chain);
      }
    }
  }
}

/// Specification for a block's expected dependencies.
class BlockDependencySpec {
  /// Blocks that this block requires to function.
  final List<String> requires;

  /// Blocks that this block modifies.
  final List<String> modifies;

  /// Blocks that this block enables/unlocks.
  final List<String> enables;

  /// Blocks that cannot be used with this block.
  final List<String> conflicts;

  const BlockDependencySpec({
    this.requires = const [],
    this.modifies = const [],
    this.enables = const [],
    this.conflicts = const [],
  });
}
