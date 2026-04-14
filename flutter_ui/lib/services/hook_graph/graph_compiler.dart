/// GraphCompiler — Validates, optimizes, and compiles HookGraphDefinition.
///
/// Validation: cycle detection, type checking, required port connections.
/// Optimization: dead node elimination, constant folding candidates.
/// Output: execution order + wire map ready for ControlRateExecutor.

import 'dart:collection';

import '../../models/hook_graph/graph_definition.dart';
import '../../models/hook_graph/node_types.dart';

/// Compilation error
class GraphCompilationError {
  final String nodeId;
  final String message;
  final GraphErrorSeverity severity;

  const GraphCompilationError({
    required this.nodeId,
    required this.message,
    this.severity = GraphErrorSeverity.error,
  });

  @override
  String toString() => '[$severity] Node $nodeId: $message';
}

enum GraphErrorSeverity { warning, error }

/// Compiled graph ready for execution
class CompiledGraph {
  final HookGraphDefinition source;
  final List<String> executionOrder;
  final Map<String, int> wireMap;
  final List<GraphCompilationError> warnings;
  final bool valid;

  const CompiledGraph({
    required this.source,
    required this.executionOrder,
    required this.wireMap,
    this.warnings = const [],
    this.valid = true,
  });
}

class GraphCompiler {
  final List<NodeTypeDefinition> _nodeTypes;

  GraphCompiler({List<NodeTypeDefinition>? nodeTypes})
      : _nodeTypes = nodeTypes ?? phase1NodeTypes;

  /// Compile a graph definition. Returns compiled result or errors.
  CompiledGraph compile(HookGraphDefinition graph) {
    final errors = <GraphCompilationError>[];

    // Validate nodes exist in registry
    for (final node in graph.nodes) {
      if (!_nodeTypes.any((t) => t.typeId == node.typeId)) {
        errors.add(GraphCompilationError(
          nodeId: node.id,
          message: 'Unknown node type: ${node.typeId}',
        ));
      }
    }

    // Check for cycles
    if (_hasCycle(graph)) {
      errors.add(const GraphCompilationError(
        nodeId: '*',
        message: 'Graph contains a cycle — execution order undefined',
      ));
    }

    // Validate connections
    for (final conn in graph.connections) {
      final fromNode = graph.nodeById(conn.fromNodeId);
      final toNode = graph.nodeById(conn.toNodeId);
      if (fromNode == null) {
        errors.add(GraphCompilationError(
          nodeId: conn.fromNodeId,
          message: 'Connection source node not found',
        ));
      }
      if (toNode == null) {
        errors.add(GraphCompilationError(
          nodeId: conn.toNodeId,
          message: 'Connection target node not found',
        ));
      }
    }

    // Check required ports
    for (final node in graph.nodes) {
      final typeDef = _nodeTypes.where((t) => t.typeId == node.typeId).firstOrNull;
      if (typeDef == null) continue;

      for (final port in typeDef.inputPorts) {
        if (!port.required) continue;
        final hasConnection = graph.connections
            .any((c) => c.toNodeId == node.id && c.toPortId == port.id);
        if (!hasConnection) {
          errors.add(GraphCompilationError(
            nodeId: node.id,
            message: 'Required input port "${port.id}" is not connected',
            severity: GraphErrorSeverity.warning,
          ));
        }
      }
    }

    // Dead node detection
    final reachable = _findReachableNodes(graph);
    for (final node in graph.nodes) {
      if (!reachable.contains(node.id) && node.typeId != 'EventEntry') {
        errors.add(GraphCompilationError(
          nodeId: node.id,
          message: 'Node is unreachable from any EventEntry',
          severity: GraphErrorSeverity.warning,
        ));
      }
    }

    if (errors.any((e) => e.severity == GraphErrorSeverity.error)) {
      return CompiledGraph(
        source: graph,
        executionOrder: const [],
        wireMap: const {},
        warnings: errors,
        valid: false,
      );
    }

    // Topological sort
    final order = _topologicalSort(graph);

    // Build wire map
    final wireMap = _buildWireMap(graph);

    return CompiledGraph(
      source: graph,
      executionOrder: order,
      wireMap: wireMap,
      warnings: errors.where((e) => e.severity == GraphErrorSeverity.warning).toList(),
      valid: true,
    );
  }

  bool _hasCycle(HookGraphDefinition graph) {
    final visited = <String>{};
    final stack = <String>{};

    bool dfs(String nodeId) {
      if (stack.contains(nodeId)) return true;
      if (visited.contains(nodeId)) return false;

      visited.add(nodeId);
      stack.add(nodeId);

      for (final conn in graph.connectionsFrom(nodeId)) {
        if (dfs(conn.toNodeId)) return true;
      }

      stack.remove(nodeId);
      return false;
    }

    for (final node in graph.nodes) {
      if (dfs(node.id)) return true;
    }
    return false;
  }

  Set<String> _findReachableNodes(HookGraphDefinition graph) {
    final reachable = <String>{};
    final queue = Queue<String>();

    for (final node in graph.nodes) {
      if (node.typeId == 'EventEntry') {
        queue.add(node.id);
        reachable.add(node.id);
      }
    }

    while (queue.isNotEmpty) {
      final nodeId = queue.removeFirst();
      for (final conn in graph.connectionsFrom(nodeId)) {
        if (!reachable.contains(conn.toNodeId)) {
          reachable.add(conn.toNodeId);
          queue.add(conn.toNodeId);
        }
      }
    }

    return reachable;
  }

  List<String> _topologicalSort(HookGraphDefinition graph) {
    final inDegree = <String, int>{};
    final adjacency = <String, List<String>>{};

    for (final node in graph.nodes) {
      inDegree[node.id] = 0;
      adjacency[node.id] = [];
    }

    for (final conn in graph.connections) {
      adjacency[conn.fromNodeId]?.add(conn.toNodeId);
      inDegree[conn.toNodeId] = (inDegree[conn.toNodeId] ?? 0) + 1;
    }

    final queue = Queue<String>();
    for (final entry in inDegree.entries) {
      if (entry.value == 0) queue.add(entry.key);
    }

    final sorted = <String>[];
    while (queue.isNotEmpty) {
      final nodeId = queue.removeFirst();
      sorted.add(nodeId);
      for (final neighbor in (adjacency[nodeId] ?? [])) {
        inDegree[neighbor] = (inDegree[neighbor] ?? 1) - 1;
        if (inDegree[neighbor] == 0) queue.add(neighbor);
      }
    }

    return sorted;
  }

  Map<String, int> _buildWireMap(HookGraphDefinition graph) {
    final wireMap = <String, int>{};
    int idx = 0;

    for (final conn in graph.connections) {
      final fromKey = '${conn.fromNodeId}.${conn.fromPortId}';
      final toKey = '${conn.toNodeId}.${conn.toPortId}';
      wireMap.putIfAbsent(fromKey, () => idx++);
      wireMap.putIfAbsent(toKey, () => idx++);
    }

    // Also index ports that aren't connected (for parameter defaults)
    for (final node in graph.nodes) {
      for (final key in node.parameters.keys) {
        wireMap.putIfAbsent('${node.id}.$key', () => idx++);
      }
    }

    return wireMap;
  }
}
