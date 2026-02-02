// audio_graph_models.dart — Audio Graph Visualization Models
// Part of P10.1.7 — Node-based audio routing visualization

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Node types in audio graph
enum AudioGraphNodeType {
  audioTrack,    // Timeline audio tracks
  instrument,    // Virtual instruments
  aux,           // Aux return buses
  bus,           // Mix buses
  master,        // Master bus
  insert,        // Insert plugin
  send,          // Aux send
}

/// Audio graph node representing single signal processor
class AudioGraphNode {
  final String id;
  final String label;
  final AudioGraphNodeType type;
  final Offset position;  // In graph space (not screen space)
  final Size size;
  final bool isSelected;
  final bool isMuted;
  final bool isSoloed;
  final bool isBypassed;

  /// Plugin delay compensation in samples (0 if no delay)
  final int pdcSamples;

  /// Input/output channel configuration
  final int inputChannels;
  final int outputChannels;

  /// Metering data (peak levels 0.0-1.0)
  final double? inputLevel;
  final double? outputLevel;

  /// Color coding by type
  Color get color {
    switch (type) {
      case AudioGraphNodeType.audioTrack:
        return const Color(0xFF4A9EFF);  // Blue
      case AudioGraphNodeType.instrument:
        return const Color(0xFF9370DB);  // Purple
      case AudioGraphNodeType.aux:
        return const Color(0xFF40C8FF);  // Cyan
      case AudioGraphNodeType.bus:
        return const Color(0xFFFF9040);  // Orange
      case AudioGraphNodeType.master:
        return const Color(0xFFFF4060);  // Red
      case AudioGraphNodeType.insert:
        return const Color(0xFFFFD700);  // Gold
      case AudioGraphNodeType.send:
        return const Color(0xFF40FF90);  // Green
    }
  }

  const AudioGraphNode({
    required this.id,
    required this.label,
    required this.type,
    required this.position,
    this.size = const Size(120, 60),
    this.isSelected = false,
    this.isMuted = false,
    this.isSoloed = false,
    this.isBypassed = false,
    this.pdcSamples = 0,
    this.inputChannels = 2,
    this.outputChannels = 2,
    this.inputLevel,
    this.outputLevel,
  });

  AudioGraphNode copyWith({
    String? id,
    String? label,
    AudioGraphNodeType? type,
    Offset? position,
    Size? size,
    bool? isSelected,
    bool? isMuted,
    bool? isSoloed,
    bool? isBypassed,
    int? pdcSamples,
    int? inputChannels,
    int? outputChannels,
    double? inputLevel,
    double? outputLevel,
  }) {
    return AudioGraphNode(
      id: id ?? this.id,
      label: label ?? this.label,
      type: type ?? this.type,
      position: position ?? this.position,
      size: size ?? this.size,
      isSelected: isSelected ?? this.isSelected,
      isMuted: isMuted ?? this.isMuted,
      isSoloed: isSoloed ?? this.isSoloed,
      isBypassed: isBypassed ?? this.isBypassed,
      pdcSamples: pdcSamples ?? this.pdcSamples,
      inputChannels: inputChannels ?? this.inputChannels,
      outputChannels: outputChannels ?? this.outputChannels,
      inputLevel: inputLevel ?? this.inputLevel,
      outputLevel: outputLevel ?? this.outputLevel,
    );
  }

  /// Get PDC in milliseconds at 48kHz
  double get pdcMs => pdcSamples / 48.0;

  /// Check if node has any routing issues
  bool get hasIssues => isMuted || pdcSamples > 10000; // >208ms delay

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioGraphNode &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Audio graph edge representing signal routing
class AudioGraphEdge {
  final String id;
  final String sourceNodeId;
  final String targetNodeId;

  /// Output index on source node (0-based)
  final int sourceOutputIndex;

  /// Input index on target node (0-based)
  final int targetInputIndex;

  /// Send level (0.0-4.0 linear, 1.0 = unity)
  final double gain;

  /// Pre/post fader for sends
  final bool isPreFader;

  /// Visual styling
  final bool isSelected;
  final bool isHighlighted;

  const AudioGraphEdge({
    required this.id,
    required this.sourceNodeId,
    required this.targetNodeId,
    this.sourceOutputIndex = 0,
    this.targetInputIndex = 0,
    this.gain = 1.0,
    this.isPreFader = false,
    this.isSelected = false,
    this.isHighlighted = false,
  });

  AudioGraphEdge copyWith({
    String? id,
    String? sourceNodeId,
    String? targetNodeId,
    int? sourceOutputIndex,
    int? targetInputIndex,
    double? gain,
    bool? isPreFader,
    bool? isSelected,
    bool? isHighlighted,
  }) {
    return AudioGraphEdge(
      id: id ?? this.id,
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      targetNodeId: targetNodeId ?? this.targetNodeId,
      sourceOutputIndex: sourceOutputIndex ?? this.sourceOutputIndex,
      targetInputIndex: targetInputIndex ?? this.targetInputIndex,
      gain: gain ?? this.gain,
      isPreFader: isPreFader ?? this.isPreFader,
      isSelected: isSelected ?? this.isSelected,
      isHighlighted: isHighlighted ?? this.isHighlighted,
    );
  }

  /// Gain in dB for display
  double get gainDb => gain > 0.0001 ? 20.0 * math.log(gain.clamp(0.0001, 4.0)) / math.ln10 : -60.0;

  /// Edge color based on gain level
  Color get color {
    if (gain < 0.001) return Colors.grey.withOpacity(0.3);  // Muted
    if (gain > 1.5) return const Color(0xFFFF9040);  // Boosted (orange)
    return const Color(0xFF4A9EFF);  // Normal (blue)
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioGraphEdge &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Complete audio graph state
class AudioGraphState {
  final List<AudioGraphNode> nodes;
  final List<AudioGraphEdge> edges;

  /// Graph viewport transform
  final Offset panOffset;
  final double zoomLevel;  // 0.25 - 4.0

  /// Layout algorithm state
  final AudioGraphLayoutMode layoutMode;
  final bool autoLayout;

  const AudioGraphState({
    this.nodes = const [],
    this.edges = const [],
    this.panOffset = Offset.zero,
    this.zoomLevel = 1.0,
    this.layoutMode = AudioGraphLayoutMode.hierarchical,
    this.autoLayout = true,
  });

  AudioGraphState copyWith({
    List<AudioGraphNode>? nodes,
    List<AudioGraphEdge>? edges,
    Offset? panOffset,
    double? zoomLevel,
    AudioGraphLayoutMode? layoutMode,
    bool? autoLayout,
  }) {
    return AudioGraphState(
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      panOffset: panOffset ?? this.panOffset,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      layoutMode: layoutMode ?? this.layoutMode,
      autoLayout: autoLayout ?? this.autoLayout,
    );
  }

  /// Find node by ID
  AudioGraphNode? findNode(String id) {
    try {
      return nodes.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Find all edges connected to node
  List<AudioGraphEdge> getConnectedEdges(String nodeId) {
    return edges.where((e) =>
      e.sourceNodeId == nodeId || e.targetNodeId == nodeId
    ).toList();
  }

  /// Get incoming edges for node
  List<AudioGraphEdge> getIncomingEdges(String nodeId) {
    return edges.where((e) => e.targetNodeId == nodeId).toList();
  }

  /// Get outgoing edges for node
  List<AudioGraphEdge> getOutgoingEdges(String nodeId) {
    return edges.where((e) => e.sourceNodeId == nodeId).toList();
  }

  /// Topological sort for signal flow order
  List<AudioGraphNode> topologicalSort() {
    final result = <AudioGraphNode>[];
    final visited = <String>{};
    final visiting = <String>{};

    void visit(String nodeId) {
      if (visited.contains(nodeId)) return;
      if (visiting.contains(nodeId)) {
        // Cycle detected — skip to prevent infinite loop
        return;
      }

      visiting.add(nodeId);

      // Visit all incoming edges first
      for (final edge in getIncomingEdges(nodeId)) {
        visit(edge.sourceNodeId);
      }

      visiting.remove(nodeId);
      visited.add(nodeId);

      final node = findNode(nodeId);
      if (node != null) {
        result.add(node);
      }
    }

    // Start from nodes with no incoming edges (audio tracks, instruments)
    for (final node in nodes) {
      if (getIncomingEdges(node.id).isEmpty) {
        visit(node.id);
      }
    }

    // Visit remaining nodes (in case of cycles or disconnected components)
    for (final node in nodes) {
      visit(node.id);
    }

    return result;
  }

  /// Calculate total PDC for each node (accumulated from inputs)
  Map<String, int> calculatePDC() {
    final pdcMap = <String, int>{};
    final sorted = topologicalSort();

    for (final node in sorted) {
      int maxInputPdc = 0;

      // Find max PDC from all input paths
      for (final edge in getIncomingEdges(node.id)) {
        final sourcePdc = pdcMap[edge.sourceNodeId] ?? 0;
        if (sourcePdc > maxInputPdc) {
          maxInputPdc = sourcePdc;
        }
      }

      // Add this node's own PDC
      pdcMap[node.id] = maxInputPdc + node.pdcSamples;
    }

    return pdcMap;
  }
}

/// Layout algorithm modes
enum AudioGraphLayoutMode {
  hierarchical,   // Top-to-bottom signal flow
  circular,       // Circular arrangement
  forceDirected,  // Physics-based (Fruchterman-Reingold)
  manual,         // User-positioned nodes
}

/// Graph interaction mode
enum AudioGraphInteractionMode {
  pan,       // Pan viewport
  select,    // Select nodes/edges
  connect,   // Create new edges
  delete,    // Delete nodes/edges
}
