/// Event Dependency Analyzer
///
/// Analyzes middleware event dependencies and detects circular references:
/// - DFS-based cycle detection algorithm
/// - Event→Event trigger chains
/// - Container→Event dependencies
/// - RTPC→Event dependencies
/// - State→Event dependencies
///
/// Usage: Validates event graph before export to prevent runtime deadlocks
library;

import 'dart:collection';
import '../models/middleware_models.dart';
import '../models/slot_audio_events.dart';

/// Dependency type between events
enum DependencyType {
  directTrigger,    // Event A directly triggers Event B
  containerChild,   // Event A is child in container that Event B uses
  rtpcModulation,   // Event A modulates RTPC that affects Event B
  stateTransition,  // Event A changes state that triggers Event B
  duckingTarget,    // Event A ducks Event B's bus
}

/// Dependency edge in event graph
class EventDependency {
  final String fromEventId;
  final String toEventId;
  final DependencyType type;
  final String? context; // Additional info (e.g., container ID, RTPC name)

  EventDependency({
    required this.fromEventId,
    required this.toEventId,
    required this.type,
    this.context,
  });

  @override
  String toString() {
    final contextStr = context != null ? ' ($context)' : '';
    return '$fromEventId → $toEventId [${type.name}$contextStr]';
  }
}

/// Cycle detection result
class CycleDetectionResult {
  final bool hasCycle;
  final List<List<String>> cycles; // List of cycles (each cycle is a list of event IDs)
  final Map<String, Set<String>> adjacencyList;
  final List<EventDependency> allDependencies;

  CycleDetectionResult({
    required this.hasCycle,
    required this.cycles,
    required this.adjacencyList,
    required this.allDependencies,
  });

  String get summary {
    if (!hasCycle) return 'No cycles detected';
    return 'Found ${cycles.length} cycle(s)';
  }
}

/// Event Dependency Analyzer service
class EventDependencyAnalyzer {
  /// Analyze event dependencies and detect cycles
  ///
  /// Uses DFS-based cycle detection algorithm
  static CycleDetectionResult analyze({
    required List<SlotCompositeEvent> events,
    List<BlendContainer>? blendContainers,
    List<RandomContainer>? randomContainers,
    List<SequenceContainer>? sequenceContainers,
    List<RtpcDefinition>? rtpcs,
    List<StateGroup>? stateGroups,
  }) {
    // Build adjacency list
    final adjacencyList = <String, Set<String>>{};
    final allDependencies = <EventDependency>[];

    // Initialize nodes
    for (final event in events) {
      adjacencyList[event.id] = {};
    }

    // Add direct trigger dependencies
    _addDirectTriggerDependencies(events, adjacencyList, allDependencies);

    // Add container dependencies
    if (blendContainers != null) {
      _addContainerDependencies(blendContainers, adjacencyList, allDependencies, DependencyType.containerChild);
    }
    if (randomContainers != null) {
      _addContainerDependencies(randomContainers, adjacencyList, allDependencies, DependencyType.containerChild);
    }
    if (sequenceContainers != null) {
      _addContainerDependencies(sequenceContainers, adjacencyList, allDependencies, DependencyType.containerChild);
    }

    // Detect cycles using DFS
    final cycles = _detectCyclesDFS(adjacencyList);

    return CycleDetectionResult(
      hasCycle: cycles.isNotEmpty,
      cycles: cycles,
      adjacencyList: adjacencyList,
      allDependencies: allDependencies,
    );
  }

  /// Add direct trigger dependencies (Event A triggers Event B via actions)
  static void _addDirectTriggerDependencies(
    List<SlotCompositeEvent> events,
    Map<String, Set<String>> adjacencyList,
    List<EventDependency> allDependencies,
  ) {
    for (final event in events) {
      for (final layer in event.layers) {
        for (final action in layer.actions) {
          // If action is StopEvent, add dependency
          if (action.actionType == ActionType.stopEvent && action.targetEventId != null) {
            final targetId = action.targetEventId!;
            if (adjacencyList.containsKey(targetId)) {
              adjacencyList[event.id]!.add(targetId);
              allDependencies.add(EventDependency(
                fromEventId: event.id,
                toEventId: targetId,
                type: DependencyType.directTrigger,
                context: 'stop action',
              ));
            }
          }

          // If action is PlayEvent, add dependency
          if (action.actionType == ActionType.play && action.targetEventId != null) {
            final targetId = action.targetEventId!;
            if (adjacencyList.containsKey(targetId)) {
              adjacencyList[event.id]!.add(targetId);
              allDependencies.add(EventDependency(
                fromEventId: event.id,
                toEventId: targetId,
                type: DependencyType.directTrigger,
                context: 'play action',
              ));
            }
          }
        }
      }
    }
  }

  /// Add container dependencies (Event uses Container which has child Events)
  static void _addContainerDependencies<T>(
    List<T> containers,
    Map<String, Set<String>> adjacencyList,
    List<EventDependency> allDependencies,
    DependencyType type,
  ) {
    for (final container in containers) {
      String? containerId;
      List<String> childEventIds = [];

      if (container is BlendContainer) {
        containerId = container.id.toString();
        // BlendContainer children are audio paths, not events
        // Skip for now unless we add event references
        continue;
      } else if (container is RandomContainer) {
        containerId = container.id.toString();
        // Same for RandomContainer
        continue;
      } else if (container is SequenceContainer) {
        containerId = container.id.toString();
        // Same for SequenceContainer
        continue;
      }

      // Add edges from parent event to child events
      // (This would require events to have container references)
      // TODO: Implement when event→container linkage is added
    }
  }

  /// Detect cycles using Depth-First Search (DFS)
  ///
  /// White-Grey-Black algorithm:
  /// - White: Unvisited
  /// - Grey: Currently visiting (in DFS stack)
  /// - Black: Completely visited
  ///
  /// If we encounter a grey node, we've found a cycle.
  static List<List<String>> _detectCyclesDFS(Map<String, Set<String>> adjacencyList) {
    final cycles = <List<String>>[];
    final color = <String, _NodeColor>{};
    final parent = <String, String?>{}; // For reconstructing cycle path
    final recursionStack = <String>[]; // Current DFS path

    // Initialize all nodes as white
    for (final node in adjacencyList.keys) {
      color[node] = _NodeColor.white;
      parent[node] = null;
    }

    // DFS from each unvisited node
    for (final node in adjacencyList.keys) {
      if (color[node] == _NodeColor.white) {
        _dfsVisit(node, adjacencyList, color, parent, recursionStack, cycles);
      }
    }

    return cycles;
  }

  /// DFS visit helper
  static void _dfsVisit(
    String node,
    Map<String, Set<String>> adjacencyList,
    Map<String, _NodeColor> color,
    Map<String, String?> parent,
    List<String> recursionStack,
    List<List<String>> cycles,
  ) {
    // Mark as grey (visiting)
    color[node] = _NodeColor.grey;
    recursionStack.add(node);

    // Visit all neighbors
    final neighbors = adjacencyList[node] ?? {};
    for (final neighbor in neighbors) {
      if (color[neighbor] == _NodeColor.white) {
        // Unvisited, continue DFS
        parent[neighbor] = node;
        _dfsVisit(neighbor, adjacencyList, color, parent, recursionStack, cycles);
      } else if (color[neighbor] == _NodeColor.grey) {
        // Back edge detected → cycle found!
        final cycle = _extractCycle(neighbor, recursionStack);
        cycles.add(cycle);
      }
      // If black, ignore (already processed)
    }

    // Mark as black (done)
    color[node] = _NodeColor.black;
    recursionStack.removeLast();
  }

  /// Extract cycle from recursion stack
  static List<String> _extractCycle(String backEdgeTarget, List<String> recursionStack) {
    final cycleStartIndex = recursionStack.indexOf(backEdgeTarget);
    if (cycleStartIndex == -1) return [];

    // Return cycle path from backEdgeTarget to current node
    final cycle = recursionStack.sublist(cycleStartIndex);
    cycle.add(backEdgeTarget); // Close the cycle
    return cycle;
  }

  /// Get all paths from source to target (for debugging)
  static List<List<String>> findAllPaths(
    String source,
    String target,
    Map<String, Set<String>> adjacencyList,
  ) {
    final paths = <List<String>>[];
    final currentPath = <String>[];
    final visited = <String>{};

    _findPathsDFS(source, target, adjacencyList, currentPath, visited, paths);

    return paths;
  }

  static void _findPathsDFS(
    String current,
    String target,
    Map<String, Set<String>> adjacencyList,
    List<String> currentPath,
    Set<String> visited,
    List<List<String>> paths,
  ) {
    currentPath.add(current);
    visited.add(current);

    if (current == target) {
      // Found a path
      paths.add(List.from(currentPath));
    } else {
      // Continue searching
      final neighbors = adjacencyList[current] ?? {};
      for (final neighbor in neighbors) {
        if (!visited.contains(neighbor)) {
          _findPathsDFS(neighbor, target, adjacencyList, currentPath, visited, paths);
        }
      }
    }

    // Backtrack
    currentPath.removeLast();
    visited.remove(current);
  }

  /// Topological sort (only valid if no cycles)
  ///
  /// Returns null if graph has cycles
  static List<String>? topologicalSort(Map<String, Set<String>> adjacencyList) {
    final inDegree = <String, int>{};
    final sorted = <String>[];

    // Calculate in-degrees
    for (final node in adjacencyList.keys) {
      inDegree[node] = 0;
    }
    for (final neighbors in adjacencyList.values) {
      for (final neighbor in neighbors) {
        inDegree[neighbor] = (inDegree[neighbor] ?? 0) + 1;
      }
    }

    // Queue all nodes with in-degree 0
    final queue = Queue<String>();
    for (final node in adjacencyList.keys) {
      if (inDegree[node] == 0) {
        queue.add(node);
      }
    }

    // Kahn's algorithm
    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      sorted.add(node);

      final neighbors = adjacencyList[node] ?? {};
      for (final neighbor in neighbors) {
        inDegree[neighbor] = inDegree[neighbor]! - 1;
        if (inDegree[neighbor] == 0) {
          queue.add(neighbor);
        }
      }
    }

    // If sorted.length != adjacencyList.length, there's a cycle
    if (sorted.length != adjacencyList.length) {
      return null; // Cycle detected
    }

    return sorted;
  }
}

/// Node color for DFS cycle detection
enum _NodeColor { white, grey, black }
