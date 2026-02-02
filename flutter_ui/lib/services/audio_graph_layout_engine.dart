// audio_graph_layout_engine.dart — Graph Layout Algorithms
// Part of P10.1.7 — Force-directed + Hierarchical layouts

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/audio_graph_models.dart';

/// Layout engine for audio graph visualization
class AudioGraphLayoutEngine {
  /// Fruchterman-Reingold force-directed layout
  /// Ref: Graph Drawing by Force-directed Placement (1991)
  static List<AudioGraphNode> forceDirectedLayout({
    required List<AudioGraphNode> nodes,
    required List<AudioGraphEdge> edges,
    required Size canvasSize,
    int iterations = 50,
    double repulsionStrength = 5000.0,
    double attractionStrength = 0.5,
    double coolingFactor = 0.95,
  }) {
    if (nodes.isEmpty) return [];

    // Initialize with random positions if needed
    var workingNodes = nodes.map((node) {
      if (node.position == Offset.zero) {
        final random = math.Random(node.id.hashCode);
        return node.copyWith(
          position: Offset(
            random.nextDouble() * canvasSize.width,
            random.nextDouble() * canvasSize.height,
          ),
        );
      }
      return node;
    }).toList();

    // Calculate optimal edge length based on canvas and node count
    final area = canvasSize.width * canvasSize.height;
    final k = math.sqrt(area / nodes.length);

    // Temperature starts high, cools over iterations
    double temperature = canvasSize.width / 10.0;

    for (int iter = 0; iter < iterations; iter++) {
      // Calculate repulsive forces (all pairs)
      final repulsiveForces = <String, Offset>{};
      for (int i = 0; i < workingNodes.length; i++) {
        final nodeA = workingNodes[i];
        Offset force = Offset.zero;

        for (int j = 0; j < workingNodes.length; j++) {
          if (i == j) continue;

          final nodeB = workingNodes[j];
          final delta = nodeA.position - nodeB.position;
          final distance = math.max(delta.distance, 0.01);  // Avoid division by zero

          // Repulsive force: f_r(d) = k^2 / d
          final magnitude = (k * k * repulsionStrength) / distance;
          force += delta / distance * magnitude;
        }

        repulsiveForces[nodeA.id] = force;
      }

      // Calculate attractive forces (edges only)
      final attractiveForces = <String, Offset>{};
      for (final node in workingNodes) {
        attractiveForces[node.id] = Offset.zero;
      }

      for (final edge in edges) {
        final sourceNode = workingNodes.firstWhere((n) => n.id == edge.sourceNodeId, orElse: () => workingNodes[0]);
        final targetNode = workingNodes.firstWhere((n) => n.id == edge.targetNodeId, orElse: () => workingNodes[0]);

        if (sourceNode == targetNode) continue;

        final delta = targetNode.position - sourceNode.position;
        final distance = math.max(delta.distance, 0.01);

        // Attractive force: f_a(d) = d^2 / k * strength
        final magnitude = (distance * distance * attractionStrength) / k;
        final force = delta / distance * magnitude;

        attractiveForces[sourceNode.id] = (attractiveForces[sourceNode.id] ?? Offset.zero) + force;
        attractiveForces[targetNode.id] = (attractiveForces[targetNode.id] ?? Offset.zero) - force;
      }

      // Apply forces to update positions
      workingNodes = workingNodes.map((node) {
        final repulsive = repulsiveForces[node.id] ?? Offset.zero;
        final attractive = attractiveForces[node.id] ?? Offset.zero;
        final totalForce = repulsive + attractive;

        // Limit displacement by temperature
        final displacement = totalForce.distance;
        final limitedDisplacement = math.min(displacement, temperature);

        Offset newPosition;
        if (displacement > 0.01) {
          newPosition = node.position + (totalForce / displacement) * limitedDisplacement;
        } else {
          newPosition = node.position;
        }

        // Keep within canvas bounds (with padding)
        const padding = 50.0;
        newPosition = Offset(
          newPosition.dx.clamp(padding, canvasSize.width - padding),
          newPosition.dy.clamp(padding, canvasSize.height - padding),
        );

        return node.copyWith(position: newPosition);
      }).toList();

      // Cool down temperature
      temperature *= coolingFactor;
    }

    return workingNodes;
  }

  /// Hierarchical layout (top-to-bottom signal flow)
  /// Nodes arranged in layers based on topological sort
  static List<AudioGraphNode> hierarchicalLayout({
    required List<AudioGraphNode> nodes,
    required List<AudioGraphEdge> edges,
    required Size canvasSize,
    double layerSpacing = 150.0,
    double nodeSpacing = 120.0,
  }) {
    if (nodes.isEmpty) return nodes;

    // Build adjacency map
    final outgoing = <String, List<String>>{};
    for (final edge in edges) {
      outgoing.putIfAbsent(edge.sourceNodeId, () => []).add(edge.targetNodeId);
    }

    // Topological sort to determine layers
    final layers = <int, List<AudioGraphNode>>{};
    final nodeLayer = <String, int>{};

    void assignLayer(String nodeId, int layer) {
      if (nodeLayer.containsKey(nodeId)) {
        // Update layer if we found a longer path
        if (layer > nodeLayer[nodeId]!) {
          layers[nodeLayer[nodeId]!]!.removeWhere((n) => n.id == nodeId);
          nodeLayer[nodeId] = layer;
          final node = nodes.firstWhere((n) => n.id == nodeId);
          layers.putIfAbsent(layer, () => []).add(node);
        }
        return;
      }

      nodeLayer[nodeId] = layer;
      final node = nodes.firstWhere((n) => n.id == nodeId, orElse: () => nodes[0]);
      layers.putIfAbsent(layer, () => []).add(node);

      // Recursively assign children to next layer
      final children = outgoing[nodeId] ?? [];
      for (final childId in children) {
        assignLayer(childId, layer + 1);
      }
    }

    // Find root nodes (no incoming edges)
    final hasIncoming = edges.map((e) => e.targetNodeId).toSet();
    final roots = nodes.where((n) => !hasIncoming.contains(n.id)).toList();

    // Assign layers starting from roots
    for (final root in roots) {
      assignLayer(root.id, 0);
    }

    // Handle disconnected nodes
    for (final node in nodes) {
      if (!nodeLayer.containsKey(node.id)) {
        assignLayer(node.id, 0);
      }
    }

    // Position nodes within layers
    final maxLayer = layers.keys.isEmpty ? 0 : layers.keys.reduce(math.max);
    final layoutNodes = <AudioGraphNode>[];

    for (int layer = 0; layer <= maxLayer; layer++) {
      final layerNodes = layers[layer] ?? [];
      final y = 100.0 + layer * layerSpacing;

      // Center nodes horizontally
      final totalWidth = (layerNodes.length - 1) * nodeSpacing;
      final startX = (canvasSize.width - totalWidth) / 2;

      for (int i = 0; i < layerNodes.length; i++) {
        final x = startX + i * nodeSpacing;
        layoutNodes.add(layerNodes[i].copyWith(
          position: Offset(x, y),
        ));
      }
    }

    return layoutNodes;
  }

  /// Circular layout (equal spacing around circle)
  static List<AudioGraphNode> circularLayout({
    required List<AudioGraphNode> nodes,
    required Size canvasSize,
    double radius = 300.0,
  }) {
    if (nodes.isEmpty) return nodes;

    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final angleStep = (2 * math.pi) / nodes.length;

    return nodes.asMap().entries.map((entry) {
      final index = entry.key;
      final node = entry.value;
      final angle = index * angleStep - math.pi / 2;  // Start from top

      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);

      return node.copyWith(position: Offset(x, y));
    }).toList();
  }

  /// Apply layout algorithm based on mode
  static List<AudioGraphNode> applyLayout({
    required AudioGraphLayoutMode mode,
    required List<AudioGraphNode> nodes,
    required List<AudioGraphEdge> edges,
    required Size canvasSize,
  }) {
    switch (mode) {
      case AudioGraphLayoutMode.hierarchical:
        return hierarchicalLayout(
          nodes: nodes,
          edges: edges,
          canvasSize: canvasSize,
        );
      case AudioGraphLayoutMode.circular:
        return circularLayout(
          nodes: nodes,
          canvasSize: canvasSize,
        );
      case AudioGraphLayoutMode.forceDirected:
        return forceDirectedLayout(
          nodes: nodes,
          edges: edges,
          canvasSize: canvasSize,
        );
      case AudioGraphLayoutMode.manual:
        return nodes;  // User-positioned, no automatic layout
    }
  }

  /// Find closest node to point (for selection)
  static AudioGraphNode? findNodeAtPoint({
    required Offset point,
    required List<AudioGraphNode> nodes,
    double threshold = 20.0,
  }) {
    AudioGraphNode? closest;
    double minDistance = double.infinity;

    for (final node in nodes) {
      final nodeCenter = node.position + Offset(node.size.width / 2, node.size.height / 2);
      final distance = (point - nodeCenter).distance;

      if (distance < threshold && distance < minDistance) {
        minDistance = distance;
        closest = node;
      }
    }

    return closest;
  }

  /// Find edge near point (for selection)
  static AudioGraphEdge? findEdgeAtPoint({
    required Offset point,
    required List<AudioGraphEdge> edges,
    required List<AudioGraphNode> nodes,
    double threshold = 10.0,
  }) {
    for (final edge in edges) {
      final source = nodes.firstWhere((n) => n.id == edge.sourceNodeId, orElse: () => nodes[0]);
      final target = nodes.firstWhere((n) => n.id == edge.targetNodeId, orElse: () => nodes[0]);

      final sourceCenter = source.position + Offset(source.size.width / 2, source.size.height / 2);
      final targetCenter = target.position + Offset(target.size.width / 2, target.size.height / 2);

      // Distance from point to line segment
      final distance = _distanceToLineSegment(point, sourceCenter, targetCenter);

      if (distance < threshold) {
        return edge;
      }
    }

    return null;
  }

  /// Calculate distance from point to line segment
  static double _distanceToLineSegment(Offset point, Offset a, Offset b) {
    final ab = b - a;
    final ap = point - a;

    final lengthSq = ab.distanceSquared;
    if (lengthSq < 0.0001) return ap.distance;  // a == b

    final t = (ap.dx * ab.dx + ap.dy * ab.dy) / lengthSq;
    final tClamped = t.clamp(0.0, 1.0);

    final projection = a + ab * tClamped;
    return (point - projection).distance;
  }
}
