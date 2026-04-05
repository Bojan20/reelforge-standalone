// audio_graph_test.dart — Comprehensive Audio Graph Visualization Tests
// Part of P10.1.7 — Testing graph models and layout algorithms
//
// Test Coverage:
// - Graph Models: Node/Edge equality, color mapping, topological sort, PDC
// - Force-Directed Layout: Convergence, repulsion, attraction, boundaries
// - Hierarchical Layout: Layers, centering, roots, disconnected components
// - Circular Layout: Equal spacing, radius calculation
// - Hit Detection: findNodeAtPoint, findEdgeAtPoint
//
// Mathematical validation included where applicable.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge_ui/models/audio_graph_models.dart';
import 'package:fluxforge_ui/services/audio_graph_layout_engine.dart';

void main() {
  // ==========================================================================
  // CATEGORY 1: Graph Models (5 tests)
  // ==========================================================================

  group('Graph Models', () {
    test('AudioGraphNode equality uses id only', () {
      // Given: Two nodes with same ID but different properties
      const nodeA = AudioGraphNode(
        id: 'track1',
        label: 'Track 1',
        type: AudioGraphNodeType.audioTrack,
        position: Offset(0, 0),
        isMuted: false,
      );
      const nodeB = AudioGraphNode(
        id: 'track1',
        label: 'Different Label',
        type: AudioGraphNodeType.bus,  // Different type
        position: Offset(100, 200),    // Different position
        isMuted: true,                 // Different state
      );
      const nodeC = AudioGraphNode(
        id: 'track2',  // Different ID
        label: 'Track 1',
        type: AudioGraphNodeType.audioTrack,
        position: Offset(0, 0),
      );

      // Then: Equality based on ID only
      expect(nodeA == nodeB, isTrue, reason: 'Same ID should be equal');
      expect(nodeA == nodeC, isFalse, reason: 'Different ID should not be equal');
      expect(nodeA.hashCode, equals(nodeB.hashCode));
      expect(nodeA.hashCode, isNot(equals(nodeC.hashCode)));
    });

    test('AudioGraphEdge color calculation maps gain to correct color', () {
      // Given: Edges with different gain levels
      // Gain mapping: <0.001 → grey, >1.5 → orange, else → blue
      const mutedEdge = AudioGraphEdge(
        id: 'e1',
        sourceNodeId: 'a',
        targetNodeId: 'b',
        gain: 0.0005,  // Below muted threshold
      );
      const normalEdge = AudioGraphEdge(
        id: 'e2',
        sourceNodeId: 'a',
        targetNodeId: 'b',
        gain: 1.0,  // Unity gain
      );
      const boostedEdge = AudioGraphEdge(
        id: 'e3',
        sourceNodeId: 'a',
        targetNodeId: 'b',
        gain: 2.0,  // Above boost threshold
      );
      const boundaryLowEdge = AudioGraphEdge(
        id: 'e4',
        sourceNodeId: 'a',
        targetNodeId: 'b',
        gain: 1.5,  // Exactly at boundary (should be blue)
      );
      const boundaryHighEdge = AudioGraphEdge(
        id: 'e5',
        sourceNodeId: 'a',
        targetNodeId: 'b',
        gain: 1.51,  // Just above boundary (should be orange)
      );

      // Then: Colors match gain thresholds
      expect(mutedEdge.color.opacity, lessThan(0.5), reason: 'Muted edge should be transparent');
      expect(normalEdge.color, equals(const Color(0xFF4A9EFF)), reason: 'Normal gain should be blue');
      expect(boostedEdge.color, equals(const Color(0xFFFF9040)), reason: 'Boosted gain should be orange');
      expect(boundaryLowEdge.color, equals(const Color(0xFF4A9EFF)), reason: 'Boundary 1.5 should be blue');
      expect(boundaryHighEdge.color, equals(const Color(0xFFFF9040)), reason: 'Above 1.5 should be orange');

      // Verify dB conversion: 20 * log10(gain)
      // At gain=1.0: 20 * log10(1) = 0 dB
      // At gain=2.0: 20 * log10(2) ≈ 6.02 dB
      expect(normalEdge.gainDb, closeTo(0.0, 0.01));
      expect(boostedEdge.gainDb, closeTo(6.02, 0.1));
    });

    test('topologicalSort returns nodes in signal flow order (acyclic graph)', () {
      // Given: Linear chain A → B → C → D
      //        Mathematical property: ∀(u,v) ∈ E: index(u) < index(v)
      final nodes = [
        const AudioGraphNode(id: 'D', label: 'D', type: AudioGraphNodeType.master, position: Offset.zero),
        const AudioGraphNode(id: 'A', label: 'A', type: AudioGraphNodeType.audioTrack, position: Offset.zero),
        const AudioGraphNode(id: 'C', label: 'C', type: AudioGraphNodeType.bus, position: Offset.zero),
        const AudioGraphNode(id: 'B', label: 'B', type: AudioGraphNodeType.aux, position: Offset.zero),
      ];
      final edges = [
        const AudioGraphEdge(id: 'e1', sourceNodeId: 'A', targetNodeId: 'B'),
        const AudioGraphEdge(id: 'e2', sourceNodeId: 'B', targetNodeId: 'C'),
        const AudioGraphEdge(id: 'e3', sourceNodeId: 'C', targetNodeId: 'D'),
      ];
      final state = AudioGraphState(nodes: nodes, edges: edges);

      // When: Topological sort
      final sorted = state.topologicalSort();

      // Then: A before B before C before D
      final indexA = sorted.indexWhere((n) => n.id == 'A');
      final indexB = sorted.indexWhere((n) => n.id == 'B');
      final indexC = sorted.indexWhere((n) => n.id == 'C');
      final indexD = sorted.indexWhere((n) => n.id == 'D');

      expect(indexA, lessThan(indexB), reason: 'A must come before B');
      expect(indexB, lessThan(indexC), reason: 'B must come before C');
      expect(indexC, lessThan(indexD), reason: 'C must come before D');
      expect(sorted.length, equals(4));
    });

    test('topologicalSort handles cycles gracefully without infinite loop', () {
      // Given: Graph with cycle A → B → C → A
      //        This is invalid for audio routing but should not crash
      final nodes = [
        const AudioGraphNode(id: 'A', label: 'A', type: AudioGraphNodeType.audioTrack, position: Offset.zero),
        const AudioGraphNode(id: 'B', label: 'B', type: AudioGraphNodeType.bus, position: Offset.zero),
        const AudioGraphNode(id: 'C', label: 'C', type: AudioGraphNodeType.aux, position: Offset.zero),
      ];
      final edges = [
        const AudioGraphEdge(id: 'e1', sourceNodeId: 'A', targetNodeId: 'B'),
        const AudioGraphEdge(id: 'e2', sourceNodeId: 'B', targetNodeId: 'C'),
        const AudioGraphEdge(id: 'e3', sourceNodeId: 'C', targetNodeId: 'A'),  // CYCLE!
      ];
      final state = AudioGraphState(nodes: nodes, edges: edges);

      // When: Topological sort on cyclic graph
      final stopwatch = Stopwatch()..start();
      final sorted = state.topologicalSort();
      stopwatch.stop();

      // Then: Should complete without infinite loop (timeout protection)
      expect(stopwatch.elapsedMilliseconds, lessThan(100), reason: 'Must not hang on cycles');
      expect(sorted.length, equals(3), reason: 'All nodes should be visited');
    });

    test('calculatePDC accumulates plugin delay compensation correctly', () {
      // Given: Graph with PDC values
      //        A(100) → B(50) → D(0)    Path A→B→D: 100+50+0 = 150
      //        C(200) → D                Path C→D: 200+0 = 200
      //        D should have max(150, 200) = 200 samples accumulated PDC
      final nodes = [
        const AudioGraphNode(id: 'A', label: 'EQ', type: AudioGraphNodeType.insert, position: Offset.zero, pdcSamples: 100),
        const AudioGraphNode(id: 'B', label: 'Comp', type: AudioGraphNodeType.insert, position: Offset.zero, pdcSamples: 50),
        const AudioGraphNode(id: 'C', label: 'Reverb', type: AudioGraphNodeType.insert, position: Offset.zero, pdcSamples: 200),
        const AudioGraphNode(id: 'D', label: 'Master', type: AudioGraphNodeType.master, position: Offset.zero, pdcSamples: 0),
      ];
      final edges = [
        const AudioGraphEdge(id: 'e1', sourceNodeId: 'A', targetNodeId: 'B'),
        const AudioGraphEdge(id: 'e2', sourceNodeId: 'B', targetNodeId: 'D'),
        const AudioGraphEdge(id: 'e3', sourceNodeId: 'C', targetNodeId: 'D'),
      ];
      final state = AudioGraphState(nodes: nodes, edges: edges);

      // When: Calculate PDC
      final pdcMap = state.calculatePDC();

      // Then: PDC accumulates along longest path to each node
      expect(pdcMap['A'], equals(100), reason: 'A has no inputs, just its own PDC');
      expect(pdcMap['B'], equals(150), reason: 'B = A(100) + own(50) = 150');
      expect(pdcMap['C'], equals(200), reason: 'C has no inputs, just its own PDC');
      expect(pdcMap['D'], equals(200), reason: 'D = max(B=150, C=200) + own(0) = 200');

      // Verify PDC to ms conversion at 48kHz: samples / 48 = ms
      final nodeA = nodes.firstWhere((n) => n.id == 'A');
      expect(nodeA.pdcMs, closeTo(2.083, 0.001), reason: '100 samples @ 48kHz = 2.083ms');
    });
  });

  // ==========================================================================
  // CATEGORY 2: Force-Directed Layout (5 tests)
  // ==========================================================================

  group('Force-Directed Layout', () {
    test('layout converges to stable positions within tolerance', () {
      // Given: Small graph with 3 connected nodes
      final nodes = [
        const AudioGraphNode(id: 'A', label: 'A', type: AudioGraphNodeType.audioTrack, position: Offset.zero),
        const AudioGraphNode(id: 'B', label: 'B', type: AudioGraphNodeType.bus, position: Offset.zero),
        const AudioGraphNode(id: 'C', label: 'C', type: AudioGraphNodeType.master, position: Offset.zero),
      ];
      final edges = [
        const AudioGraphEdge(id: 'e1', sourceNodeId: 'A', targetNodeId: 'B'),
        const AudioGraphEdge(id: 'e2', sourceNodeId: 'B', targetNodeId: 'C'),
      ];
      const canvasSize = Size(800, 600);

      // When: Apply layout twice with same input
      final result1 = AudioGraphLayoutEngine.forceDirectedLayout(
        nodes: nodes,
        edges: edges,
        canvasSize: canvasSize,
        iterations: 100,
      );

      // Run second pass starting from result1 positions
      final result2 = AudioGraphLayoutEngine.forceDirectedLayout(
        nodes: result1,
        edges: edges,
        canvasSize: canvasSize,
        iterations: 50,
      );

      // Then: Positions should be nearly identical (converged)
      for (int i = 0; i < result1.length; i++) {
        final delta = (result1[i].position - result2[i].position).distance;
        expect(delta, lessThan(20.0),
          reason: 'Node ${result1[i].id} should have converged (delta: $delta)');
      }
    });

    test('repulsive forces push disconnected nodes apart', () {
      // Given: Two disconnected nodes at the same position
      //        Fruchterman-Reingold repulsion: f_r(d) = k² / d
      //        As d → 0, repulsion → ∞
      final nodes = [
        const AudioGraphNode(id: 'A', label: 'A', type: AudioGraphNodeType.audioTrack, position: Offset(400, 300)),
        const AudioGraphNode(id: 'B', label: 'B', type: AudioGraphNodeType.audioTrack, position: Offset(401, 300)),
      ];
      const canvasSize = Size(800, 600);

      // When: Apply force-directed layout (no edges = only repulsion)
      final result = AudioGraphLayoutEngine.forceDirectedLayout(
        nodes: nodes,
        edges: const [],
        canvasSize: canvasSize,
        iterations: 50,
        repulsionStrength: 5000.0,
      );

      // Then: Nodes should be pushed far apart
      final distance = (result[0].position - result[1].position).distance;
      expect(distance, greaterThan(100.0),
        reason: 'Repulsive forces should push nodes apart (got $distance)');
    });

    test('attractive forces reduce distance between connected vs disconnected nodes', () {
      // Given: Same node configuration, with and without connecting edge
      //        Using LARGE canvas (3000x2000) to prevent boundary clamping
      //        Starting nodes at center to avoid boundary effects
      final nodesConnected = [
        const AudioGraphNode(id: 'A', label: 'A', type: AudioGraphNodeType.audioTrack, position: Offset(1300, 1000)),
        const AudioGraphNode(id: 'B', label: 'B', type: AudioGraphNodeType.master, position: Offset(1700, 1000)),
      ];
      final nodesDisconnected = [
        const AudioGraphNode(id: 'A', label: 'A', type: AudioGraphNodeType.audioTrack, position: Offset(1300, 1000)),
        const AudioGraphNode(id: 'B', label: 'B', type: AudioGraphNodeType.master, position: Offset(1700, 1000)),
      ];
      final edges = [
        const AudioGraphEdge(id: 'e1', sourceNodeId: 'A', targetNodeId: 'B'),
      ];
      const canvasSize = Size(3000, 2000);  // Large canvas

      // When: Apply layout WITH edge (attraction present)
      final resultConnected = AudioGraphLayoutEngine.forceDirectedLayout(
        nodes: nodesConnected,
        edges: edges,
        canvasSize: canvasSize,
        iterations: 150,
        repulsionStrength: 3000.0,   // Moderate repulsion
        attractionStrength: 0.8,     // Strong attraction
        coolingFactor: 0.97,
      );

      // When: Apply layout WITHOUT edge (only repulsion)
      final resultDisconnected = AudioGraphLayoutEngine.forceDirectedLayout(
        nodes: nodesDisconnected,
        edges: const [],
        canvasSize: canvasSize,
        iterations: 150,
        repulsionStrength: 3000.0,
        attractionStrength: 0.8,
        coolingFactor: 0.97,
      );

      // Then: Connected nodes should be CLOSER than disconnected nodes
      final distanceConnected = (resultConnected[0].position - resultConnected[1].position).distance;
      final distanceDisconnected = (resultDisconnected[0].position - resultDisconnected[1].position).distance;

      // Mathematical reasoning:
      // - Disconnected: only repulsion → nodes pushed maximally apart (limited by canvas/cooling)
      // - Connected: repulsion + attraction → equilibrium closer than repulsion-only
      // - With attraction, nodes converge toward optimal edge length k
      expect(distanceConnected, lessThanOrEqualTo(distanceDisconnected),
        reason: 'Connected nodes ($distanceConnected) should not be farther than disconnected ($distanceDisconnected)');
    });

    test('nodes stay within canvas boundaries with padding', () {
      // Given: Nodes that would be pushed outside canvas
      //        Boundary constraint: padding ≤ x ≤ width-padding, padding ≤ y ≤ height-padding
      final nodes = [
        const AudioGraphNode(id: 'A', label: 'A', type: AudioGraphNodeType.audioTrack, position: Offset(10, 10)),
        const AudioGraphNode(id: 'B', label: 'B', type: AudioGraphNodeType.audioTrack, position: Offset(790, 590)),
        const AudioGraphNode(id: 'C', label: 'C', type: AudioGraphNodeType.audioTrack, position: Offset(400, 300)),
      ];
      const canvasSize = Size(800, 600);
      const padding = 50.0;

      // When: Apply force-directed layout
      final result = AudioGraphLayoutEngine.forceDirectedLayout(
        nodes: nodes,
        edges: const [],
        canvasSize: canvasSize,
        iterations: 50,
      );

      // Then: All nodes within bounds
      for (final node in result) {
        expect(node.position.dx, greaterThanOrEqualTo(padding),
          reason: '${node.id} x should be >= padding');
        expect(node.position.dx, lessThanOrEqualTo(canvasSize.width - padding),
          reason: '${node.id} x should be <= width-padding');
        expect(node.position.dy, greaterThanOrEqualTo(padding),
          reason: '${node.id} y should be >= padding');
        expect(node.position.dy, lessThanOrEqualTo(canvasSize.height - padding),
          reason: '${node.id} y should be <= height-padding');
      }
    });

    test('layout is deterministic (same seed produces same result)', () {
      // Given: Same graph configuration
      //        Random initialization uses node.id.hashCode as seed
      final nodes = [
        const AudioGraphNode(id: 'TrackA', label: 'A', type: AudioGraphNodeType.audioTrack, position: Offset.zero),
        const AudioGraphNode(id: 'TrackB', label: 'B', type: AudioGraphNodeType.audioTrack, position: Offset.zero),
        const AudioGraphNode(id: 'Master', label: 'M', type: AudioGraphNodeType.master, position: Offset.zero),
      ];
      final edges = [
        const AudioGraphEdge(id: 'e1', sourceNodeId: 'TrackA', targetNodeId: 'Master'),
        const AudioGraphEdge(id: 'e2', sourceNodeId: 'TrackB', targetNodeId: 'Master'),
      ];
      const canvasSize = Size(800, 600);

      // When: Apply layout twice with identical parameters
      final result1 = AudioGraphLayoutEngine.forceDirectedLayout(
        nodes: nodes,
        edges: edges,
        canvasSize: canvasSize,
        iterations: 50,
      );
      final result2 = AudioGraphLayoutEngine.forceDirectedLayout(
        nodes: nodes,
        edges: edges,
        canvasSize: canvasSize,
        iterations: 50,
      );

      // Then: Results should be identical
      for (int i = 0; i < result1.length; i++) {
        expect(result1[i].position.dx, equals(result2[i].position.dx),
          reason: 'Node ${result1[i].id} X should be deterministic');
        expect(result1[i].position.dy, equals(result2[i].position.dy),
          reason: 'Node ${result1[i].id} Y should be deterministic');
      }
    });
  });

  // ==========================================================================
  // CATEGORY 3: Hierarchical Layout (4 tests)
  // ==========================================================================

  group('Hierarchical Layout', () {
    test('assigns layers based on topological depth from roots', () {
      // Given: Graph A → B → D, A → C → D
      //        Layer 0: A (root)
      //        Layer 1: B, C
      //        Layer 2: D
      final nodes = [
        const AudioGraphNode(id: 'A', label: 'A', type: AudioGraphNodeType.audioTrack, position: Offset.zero),
        const AudioGraphNode(id: 'B', label: 'B', type: AudioGraphNodeType.bus, position: Offset.zero),
        const AudioGraphNode(id: 'C', label: 'C', type: AudioGraphNodeType.aux, position: Offset.zero),
        const AudioGraphNode(id: 'D', label: 'D', type: AudioGraphNodeType.master, position: Offset.zero),
      ];
      final edges = [
        const AudioGraphEdge(id: 'e1', sourceNodeId: 'A', targetNodeId: 'B'),
        const AudioGraphEdge(id: 'e2', sourceNodeId: 'A', targetNodeId: 'C'),
        const AudioGraphEdge(id: 'e3', sourceNodeId: 'B', targetNodeId: 'D'),
        const AudioGraphEdge(id: 'e4', sourceNodeId: 'C', targetNodeId: 'D'),
      ];
      const canvasSize = Size(800, 600);
      const layerSpacing = 150.0;

      // When: Apply hierarchical layout
      final result = AudioGraphLayoutEngine.hierarchicalLayout(
        nodes: nodes,
        edges: edges,
        canvasSize: canvasSize,
        layerSpacing: layerSpacing,
      );

      // Then: Y positions reflect layer assignment
      final nodeA = result.firstWhere((n) => n.id == 'A');
      final nodeB = result.firstWhere((n) => n.id == 'B');
      final nodeC = result.firstWhere((n) => n.id == 'C');
      final nodeD = result.firstWhere((n) => n.id == 'D');

      // Layer 0: y = 100
      // Layer 1: y = 100 + 150 = 250
      // Layer 2: y = 100 + 300 = 400
      expect(nodeA.position.dy, closeTo(100.0, 1.0), reason: 'A should be in layer 0');
      expect(nodeB.position.dy, closeTo(250.0, 1.0), reason: 'B should be in layer 1');
      expect(nodeC.position.dy, closeTo(250.0, 1.0), reason: 'C should be in layer 1');
      expect(nodeD.position.dy, closeTo(400.0, 1.0), reason: 'D should be in layer 2');
    });

    test('horizontally centers nodes within each layer', () {
      // Given: Layer with 3 nodes
      //        Mathematical formula: startX = (canvasWidth - (n-1)*spacing) / 2
      //        For n=3, spacing=120, canvas=800: startX = (800-240)/2 = 280
      final nodes = [
        const AudioGraphNode(id: 'A', label: 'A', type: AudioGraphNodeType.audioTrack, position: Offset.zero),
        const AudioGraphNode(id: 'B', label: 'B', type: AudioGraphNodeType.audioTrack, position: Offset.zero),
        const AudioGraphNode(id: 'C', label: 'C', type: AudioGraphNodeType.audioTrack, position: Offset.zero),
        const AudioGraphNode(id: 'D', label: 'D', type: AudioGraphNodeType.master, position: Offset.zero),
      ];
      final edges = [
        const AudioGraphEdge(id: 'e1', sourceNodeId: 'A', targetNodeId: 'D'),
        const AudioGraphEdge(id: 'e2', sourceNodeId: 'B', targetNodeId: 'D'),
        const AudioGraphEdge(id: 'e3', sourceNodeId: 'C', targetNodeId: 'D'),
      ];
      const canvasSize = Size(800, 600);
      const nodeSpacing = 120.0;

      // When: Apply hierarchical layout
      final result = AudioGraphLayoutEngine.hierarchicalLayout(
        nodes: nodes,
        edges: edges,
        canvasSize: canvasSize,
        nodeSpacing: nodeSpacing,
      );

      // Then: Layer 0 (A,B,C) should be centered
      final layer0Nodes = result.where((n) => n.id != 'D').toList();
      final totalWidth = (layer0Nodes.length - 1) * nodeSpacing;
      final expectedStartX = (canvasSize.width - totalWidth) / 2;

      // Sort by X to get order
      layer0Nodes.sort((a, b) => a.position.dx.compareTo(b.position.dx));

      expect(layer0Nodes[0].position.dx, closeTo(expectedStartX, 1.0),
        reason: 'First node X = $expectedStartX');
      expect(layer0Nodes[1].position.dx, closeTo(expectedStartX + nodeSpacing, 1.0),
        reason: 'Second node X = ${expectedStartX + nodeSpacing}');
      expect(layer0Nodes[2].position.dx, closeTo(expectedStartX + 2 * nodeSpacing, 1.0),
        reason: 'Third node X = ${expectedStartX + 2 * nodeSpacing}');

      // Layer 1 (D) single node should be centered
      final nodeD = result.firstWhere((n) => n.id == 'D');
      expect(nodeD.position.dx, closeTo(canvasSize.width / 2, 1.0),
        reason: 'Single node in layer should be centered');
    });

    test('correctly identifies root nodes (no incoming edges)', () {
      // Given: Multiple roots A, B both feeding into C
      final nodes = [
        const AudioGraphNode(id: 'A', label: 'A', type: AudioGraphNodeType.audioTrack, position: Offset.zero),
        const AudioGraphNode(id: 'B', label: 'B', type: AudioGraphNodeType.instrument, position: Offset.zero),
        const AudioGraphNode(id: 'C', label: 'C', type: AudioGraphNodeType.master, position: Offset.zero),
      ];
      final edges = [
        const AudioGraphEdge(id: 'e1', sourceNodeId: 'A', targetNodeId: 'C'),
        const AudioGraphEdge(id: 'e2', sourceNodeId: 'B', targetNodeId: 'C'),
      ];
      const canvasSize = Size(800, 600);

      // When: Apply hierarchical layout
      final result = AudioGraphLayoutEngine.hierarchicalLayout(
        nodes: nodes,
        edges: edges,
        canvasSize: canvasSize,
      );

      // Then: A and B should be in layer 0, C in layer 1
      final nodeA = result.firstWhere((n) => n.id == 'A');
      final nodeB = result.firstWhere((n) => n.id == 'B');
      final nodeC = result.firstWhere((n) => n.id == 'C');

      expect(nodeA.position.dy, equals(nodeB.position.dy),
        reason: 'Both roots should be in same layer');
      expect(nodeC.position.dy, greaterThan(nodeA.position.dy),
        reason: 'Non-root should be in lower layer');
    });

    test('handles disconnected components by placing them at layer 0', () {
      // Given: Two disconnected subgraphs
      //        Component 1: A → B
      //        Component 2: C → D (disconnected)
      final nodes = [
        const AudioGraphNode(id: 'A', label: 'A', type: AudioGraphNodeType.audioTrack, position: Offset.zero),
        const AudioGraphNode(id: 'B', label: 'B', type: AudioGraphNodeType.master, position: Offset.zero),
        const AudioGraphNode(id: 'C', label: 'C', type: AudioGraphNodeType.instrument, position: Offset.zero),
        const AudioGraphNode(id: 'D', label: 'D', type: AudioGraphNodeType.bus, position: Offset.zero),
      ];
      final edges = [
        const AudioGraphEdge(id: 'e1', sourceNodeId: 'A', targetNodeId: 'B'),
        const AudioGraphEdge(id: 'e2', sourceNodeId: 'C', targetNodeId: 'D'),
      ];
      const canvasSize = Size(800, 600);

      // When: Apply hierarchical layout
      final result = AudioGraphLayoutEngine.hierarchicalLayout(
        nodes: nodes,
        edges: edges,
        canvasSize: canvasSize,
      );

      // Then: Both A and C should be roots (layer 0)
      final nodeA = result.firstWhere((n) => n.id == 'A');
      final nodeC = result.firstWhere((n) => n.id == 'C');

      expect(nodeA.position.dy, equals(nodeC.position.dy),
        reason: 'Roots of disconnected components should be in same layer');
      expect(result.length, equals(4), reason: 'All nodes should be included');
    });
  });

  // ==========================================================================
  // CATEGORY 4: Circular Layout (2 tests)
  // ==========================================================================

  group('Circular Layout', () {
    test('distributes nodes with equal angular spacing', () {
      // Given: 6 nodes
      //        Expected angle step = 2π / 6 = π/3 radians = 60°
      final nodes = List.generate(6, (i) => AudioGraphNode(
        id: 'node$i',
        label: 'N$i',
        type: AudioGraphNodeType.audioTrack,
        position: Offset.zero,
      ));
      const canvasSize = Size(800, 600);

      // When: Apply circular layout
      final result = AudioGraphLayoutEngine.circularLayout(
        nodes: nodes,
        canvasSize: canvasSize,
        radius: 200.0,
      );

      // Then: Each adjacent pair should have same angular distance
      final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
      final expectedAngleStep = 2 * math.pi / nodes.length;

      for (int i = 0; i < result.length; i++) {
        final next = (i + 1) % result.length;

        // Calculate angles from center
        final angle1 = math.atan2(
          result[i].position.dy - center.dy,
          result[i].position.dx - center.dx,
        );
        final angle2 = math.atan2(
          result[next].position.dy - center.dy,
          result[next].position.dx - center.dx,
        );

        // Normalize angle difference to [0, 2π]
        var angleDiff = (angle2 - angle1) % (2 * math.pi);
        if (angleDiff < 0) angleDiff += 2 * math.pi;

        expect(angleDiff, closeTo(expectedAngleStep, 0.01),
          reason: 'Angular spacing between node $i and $next should be ${expectedAngleStep * 180 / math.pi}°');
      }
    });

    test('positions nodes at specified radius from center', () {
      // Given: 4 nodes with radius 250
      //        Mathematical verification: distance(node, center) = radius
      final nodes = List.generate(4, (i) => AudioGraphNode(
        id: 'node$i',
        label: 'N$i',
        type: AudioGraphNodeType.bus,
        position: Offset.zero,
      ));
      const canvasSize = Size(800, 600);
      const radius = 250.0;

      // When: Apply circular layout
      final result = AudioGraphLayoutEngine.circularLayout(
        nodes: nodes,
        canvasSize: canvasSize,
        radius: radius,
      );

      // Then: Each node should be exactly radius distance from center
      final center = Offset(canvasSize.width / 2, canvasSize.height / 2);

      for (final node in result) {
        final distance = (node.position - center).distance;
        expect(distance, closeTo(radius, 0.001),
          reason: 'Node ${node.id} should be at radius $radius from center (got $distance)');
      }

      // Verify first node starts at top (angle = -π/2)
      final firstNode = result[0];
      final angle = math.atan2(
        firstNode.position.dy - center.dy,
        firstNode.position.dx - center.dx,
      );
      expect(angle, closeTo(-math.pi / 2, 0.01),
        reason: 'First node should be at top (angle = -π/2)');
    });
  });

  // ==========================================================================
  // CATEGORY 5: Hit Detection (4 tests)
  // ==========================================================================

  group('Hit Detection', () {
    test('findNodeAtPoint returns node when within threshold distance', () {
      // Given: Node at (200, 150) with size 120x60
      //        Node center = (200 + 60, 150 + 30) = (260, 180)
      final nodes = [
        const AudioGraphNode(
          id: 'track1',
          label: 'Track 1',
          type: AudioGraphNodeType.audioTrack,
          position: Offset(200, 150),
          size: Size(120, 60),
        ),
      ];
      const threshold = 20.0;

      // When: Test point at center (distance = 0)
      final hitAtCenter = AudioGraphLayoutEngine.findNodeAtPoint(
        point: const Offset(260, 180),
        nodes: nodes,
        threshold: threshold,
      );

      // When: Test point just inside threshold (distance = 15 < 20)
      final hitNearby = AudioGraphLayoutEngine.findNodeAtPoint(
        point: const Offset(275, 180),  // 15 pixels right of center
        nodes: nodes,
        threshold: threshold,
      );

      // Then: Both should find the node
      expect(hitAtCenter, isNotNull);
      expect(hitAtCenter!.id, equals('track1'));
      expect(hitNearby, isNotNull);
      expect(hitNearby!.id, equals('track1'));
    });

    test('findNodeAtPoint returns null when outside threshold', () {
      // Given: Node with center at (260, 180)
      final nodes = [
        const AudioGraphNode(
          id: 'track1',
          label: 'Track 1',
          type: AudioGraphNodeType.audioTrack,
          position: Offset(200, 150),
          size: Size(120, 60),
        ),
      ];
      const threshold = 20.0;

      // When: Test point outside threshold (distance = 25 > 20)
      final miss = AudioGraphLayoutEngine.findNodeAtPoint(
        point: const Offset(285, 180),  // 25 pixels right of center
        nodes: nodes,
        threshold: threshold,
      );

      // Then: Should return null
      expect(miss, isNull, reason: 'Point 25px away should not hit with threshold 20');
    });

    test('findEdgeAtPoint returns edge when point is near line segment', () {
      // Given: Edge from (100, 100) to (300, 100) — horizontal line
      //        Point (200, 105) is 5 pixels below midpoint
      final nodes = [
        const AudioGraphNode(id: 'A', label: 'A', type: AudioGraphNodeType.audioTrack,
          position: Offset(40, 70), size: Size(120, 60)),  // center: (100, 100)
        const AudioGraphNode(id: 'B', label: 'B', type: AudioGraphNodeType.master,
          position: Offset(240, 70), size: Size(120, 60)),  // center: (300, 100)
      ];
      final edges = [
        const AudioGraphEdge(id: 'e1', sourceNodeId: 'A', targetNodeId: 'B'),
      ];

      // When: Test point 5 pixels below edge (should hit with threshold 10)
      final hit = AudioGraphLayoutEngine.findEdgeAtPoint(
        point: const Offset(200, 105),
        edges: edges,
        nodes: nodes,
        threshold: 10.0,
      );

      // Then: Should find the edge
      expect(hit, isNotNull);
      expect(hit!.id, equals('e1'));
    });

    test('findEdgeAtPoint returns null when point is far from edge', () {
      // Given: Same horizontal edge
      //        Point (200, 150) is 50 pixels below the line
      final nodes = [
        const AudioGraphNode(id: 'A', label: 'A', type: AudioGraphNodeType.audioTrack,
          position: Offset(40, 70), size: Size(120, 60)),
        const AudioGraphNode(id: 'B', label: 'B', type: AudioGraphNodeType.master,
          position: Offset(240, 70), size: Size(120, 60)),
      ];
      final edges = [
        const AudioGraphEdge(id: 'e1', sourceNodeId: 'A', targetNodeId: 'B'),
      ];

      // When: Test point 50 pixels away from edge
      final miss = AudioGraphLayoutEngine.findEdgeAtPoint(
        point: const Offset(200, 150),
        edges: edges,
        nodes: nodes,
        threshold: 10.0,
      );

      // Then: Should not find any edge
      expect(miss, isNull, reason: 'Point 50px away should not hit edge with threshold 10');
    });
  });

  // ==========================================================================
  // CATEGORY 6: Edge Cases & Performance (4 bonus tests)
  // ==========================================================================

  group('Edge Cases & Performance', () {
    test('empty graph returns empty result for all layouts', () {
      // Given: Empty graph
      const canvasSize = Size(800, 600);

      // When: Apply all layout types
      final forceResult = AudioGraphLayoutEngine.forceDirectedLayout(
        nodes: const [],
        edges: const [],
        canvasSize: canvasSize,
      );
      final hierarchicalResult = AudioGraphLayoutEngine.hierarchicalLayout(
        nodes: const [],
        edges: const [],
        canvasSize: canvasSize,
      );
      final circularResult = AudioGraphLayoutEngine.circularLayout(
        nodes: const [],
        canvasSize: canvasSize,
      );

      // Then: All should return empty lists
      expect(forceResult, isEmpty);
      expect(hierarchicalResult, isEmpty);
      expect(circularResult, isEmpty);
    });

    test('single node graph is handled correctly', () {
      // Given: Single node
      final nodes = [
        const AudioGraphNode(id: 'solo', label: 'Solo', type: AudioGraphNodeType.master, position: Offset.zero),
      ];
      const canvasSize = Size(800, 600);

      // When: Apply circular layout (would normally divide by n)
      final result = AudioGraphLayoutEngine.circularLayout(
        nodes: nodes,
        canvasSize: canvasSize,
        radius: 200.0,
      );

      // Then: Node should be at top of circle (single node case)
      expect(result.length, equals(1));
      // With angle = -π/2, node should be directly above center
      expect(result[0].position.dx, closeTo(canvasSize.width / 2, 1.0));
      expect(result[0].position.dy, closeTo(canvasSize.height / 2 - 200.0, 1.0));
    });

    test('layout completes within performance budget (<100ms for 50 nodes)', () {
      // Given: Large graph with 50 nodes
      final nodes = List.generate(50, (i) => AudioGraphNode(
        id: 'node$i',
        label: 'N$i',
        type: AudioGraphNodeType.audioTrack,
        position: Offset.zero,
      ));
      // Create ring topology: each node connects to next
      final edges = List.generate(50, (i) => AudioGraphEdge(
        id: 'e$i',
        sourceNodeId: 'node$i',
        targetNodeId: 'node${(i + 1) % 50}',
      ));
      const canvasSize = Size(1920, 1080);

      // When: Time the force-directed layout
      final stopwatch = Stopwatch()..start();
      AudioGraphLayoutEngine.forceDirectedLayout(
        nodes: nodes,
        edges: edges,
        canvasSize: canvasSize,
        iterations: 50,
      );
      stopwatch.stop();

      // Then: Should complete within 100ms
      expect(stopwatch.elapsedMilliseconds, lessThan(100),
        reason: 'Layout should complete within 100ms (took ${stopwatch.elapsedMilliseconds}ms)');
    });

    test('node type colors are distinct and match specification', () {
      // Given: All node types
      final nodeTypes = AudioGraphNodeType.values;
      final expectedColors = <AudioGraphNodeType, Color>{
        AudioGraphNodeType.audioTrack: const Color(0xFF4A9EFF),   // Blue
        AudioGraphNodeType.instrument: const Color(0xFF9370DB),   // Purple
        AudioGraphNodeType.aux: const Color(0xFF40C8FF),          // Cyan
        AudioGraphNodeType.bus: const Color(0xFFFF9040),          // Orange
        AudioGraphNodeType.master: const Color(0xFFFF4060),       // Red
        AudioGraphNodeType.insert: const Color(0xFFFFD700),       // Gold
        AudioGraphNodeType.send: const Color(0xFF40FF90),         // Green
      };

      // When/Then: Verify each type has correct color
      for (final type in nodeTypes) {
        final node = AudioGraphNode(
          id: 'test',
          label: 'Test',
          type: type,
          position: Offset.zero,
        );
        expect(node.color, equals(expectedColors[type]),
          reason: 'Node type $type should have color ${expectedColors[type]}');
      }

      // Verify all colors are unique
      final colors = expectedColors.values.toSet();
      expect(colors.length, equals(nodeTypes.length),
        reason: 'All node type colors should be unique');
    });
  });
}
