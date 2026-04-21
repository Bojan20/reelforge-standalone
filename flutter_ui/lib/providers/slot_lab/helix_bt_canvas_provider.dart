/// HELIX Behavior Tree Canvas Provider
///
/// Persists the visual behavior tree canvas state (nodes, connections,
/// positions) so it survives tab switches and rebuilds.
///
/// This is separate from BehaviorTreeProvider which manages the audio
/// behavior model (22 BehaviorNodes → engine hooks). This provider
/// manages the VISUAL EDITOR state — the logic tree that controls
/// execution flow (Sequence, Selector, Parallel, etc.).

import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// A node on the behavior tree canvas
class BtCanvasNode {
  final String id;
  final String category;
  final String name;
  Offset position;

  BtCanvasNode({
    required this.id,
    required this.category,
    required this.name,
    required this.position,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'name': name,
        'x': position.dx,
        'y': position.dy,
      };

  factory BtCanvasNode.fromJson(Map<String, dynamic> json) => BtCanvasNode(
        id: json['id'] as String,
        category: json['category'] as String,
        name: json['name'] as String,
        position: Offset(
          (json['x'] as num).toDouble(),
          (json['y'] as num).toDouble(),
        ),
      );
}

/// A connection between two canvas nodes
class BtCanvasEdge {
  final String fromId;
  final String toId;

  const BtCanvasEdge({required this.fromId, required this.toId});

  Map<String, dynamic> toJson() => {'from': fromId, 'to': toId};

  factory BtCanvasEdge.fromJson(Map<String, dynamic> json) => BtCanvasEdge(
        fromId: json['from'] as String,
        toId: json['to'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is BtCanvasEdge && fromId == other.fromId && toId == other.toId;

  @override
  int get hashCode => Object.hash(fromId, toId);
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class HelixBtCanvasProvider extends ChangeNotifier {
  final List<BtCanvasNode> _nodes = [];
  final Set<BtCanvasEdge> _edges = {};
  String? _selectedNodeId;
  int _nextId = 0;
  bool _isDirty = false;

  // ─── Getters ───────────────────────────────────────────────────────────────

  List<BtCanvasNode> get nodes => List.unmodifiable(_nodes);
  Set<BtCanvasEdge> get edges => Set.unmodifiable(_edges);
  String? get selectedNodeId => _selectedNodeId;
  bool get isDirty => _isDirty;
  int get nodeCount => _nodes.length;
  int get edgeCount => _edges.length;

  BtCanvasNode? get selectedNode {
    if (_selectedNodeId == null) return null;
    final idx = _nodes.indexWhere((n) => n.id == _selectedNodeId);
    return idx >= 0 ? _nodes[idx] : null;
  }

  // ─── Node Operations ──────────────────────────────────────────────────────

  /// Add a node to the canvas
  String addNode(String category, String name, {Offset? position}) {
    final id = 'bt_node_${_nextId++}';
    _nodes.add(BtCanvasNode(
      id: id,
      category: category,
      name: name,
      position: position ??
          Offset(
            100.0 + (_nodes.length % 5) * 130.0,
            80.0 + (_nodes.length ~/ 5) * 90.0,
          ),
    ));
    _isDirty = true;
    notifyListeners();
    return id;
  }

  /// Move a node to a new position
  void moveNode(String nodeId, Offset delta) {
    final idx = _nodes.indexWhere((n) => n.id == nodeId);
    if (idx < 0) return;
    _nodes[idx].position += delta;
    _isDirty = true;
    notifyListeners();
  }

  /// Delete a node and its connections
  void deleteNode(String nodeId) {
    _nodes.removeWhere((n) => n.id == nodeId);
    _edges.removeWhere((e) => e.fromId == nodeId || e.toId == nodeId);
    if (_selectedNodeId == nodeId) _selectedNodeId = null;
    _isDirty = true;
    notifyListeners();
  }

  /// Select a node (or null to deselect)
  void selectNode(String? nodeId) {
    if (_selectedNodeId == nodeId) return;
    _selectedNodeId = nodeId;
    notifyListeners();
  }

  // ─── Edge Operations ──────────────────────────────────────────────────────

  /// Connect two nodes. Returns false if edge already exists or would self-loop.
  bool connect(String fromId, String toId) {
    if (fromId == toId) return false;
    final edge = BtCanvasEdge(fromId: fromId, toId: toId);
    if (_edges.contains(edge)) return false;

    // Cycle detection — BFS from toId, check if we reach fromId
    if (_wouldCreateCycle(fromId, toId)) return false;

    _edges.add(edge);
    _isDirty = true;
    notifyListeners();
    return true;
  }

  /// Disconnect two nodes
  void disconnect(String fromId, String toId) {
    _edges.remove(BtCanvasEdge(fromId: fromId, toId: toId));
    _isDirty = true;
    notifyListeners();
  }

  /// Check if adding fromId→toId would create a cycle
  bool _wouldCreateCycle(String fromId, String toId) {
    final visited = <String>{};
    final queue = <String>[toId];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (current == fromId) return true;
      if (visited.contains(current)) continue;
      visited.add(current);
      for (final edge in _edges) {
        if (edge.fromId == current) {
          queue.add(edge.toId);
        }
      }
    }
    return false;
  }

  // ─── Bulk Operations ──────────────────────────────────────────────────────

  /// Clear the entire canvas
  void clear() {
    _nodes.clear();
    _edges.clear();
    _selectedNodeId = null;
    _isDirty = true;
    notifyListeners();
  }

  /// Auto-layout nodes in a tree hierarchy (top-down)
  void autoLayout() {
    if (_nodes.isEmpty) return;

    // Find root nodes (no incoming edges)
    final childIds = _edges.map((e) => e.toId).toSet();
    final roots = _nodes.where((n) => !childIds.contains(n.id)).toList();
    if (roots.isEmpty) {
      // All nodes have parents — use first node as root
      roots.add(_nodes.first);
    }

    final positioned = <String>{};
    var currentY = 40.0;

    void layoutLevel(List<BtCanvasNode> level, double y) {
      final spacing = 140.0;
      final startX = (level.length - 1) * spacing / -2.0 + 300.0;
      for (var i = 0; i < level.length; i++) {
        level[i].position = Offset(startX + i * spacing, y);
        positioned.add(level[i].id);
      }

      // Find children of this level
      final nextLevel = <BtCanvasNode>[];
      for (final parent in level) {
        for (final edge in _edges) {
          if (edge.fromId == parent.id && !positioned.contains(edge.toId)) {
            final child = _nodes.firstWhere(
              (n) => n.id == edge.toId,
              orElse: () => parent,
            );
            if (child.id != parent.id) nextLevel.add(child);
          }
        }
      }
      if (nextLevel.isNotEmpty) {
        layoutLevel(nextLevel, y + 90.0);
      }
    }

    layoutLevel(roots, currentY);

    // Position any orphan nodes at the bottom
    for (final node in _nodes) {
      if (!positioned.contains(node.id)) {
        node.position = Offset(
          100.0 + positioned.length * 130.0,
          currentY + 300.0,
        );
        positioned.add(node.id);
      }
    }

    _isDirty = true;
    notifyListeners();
  }

  // ─── Serialization ────────────────────────────────────────────────────────

  /// Serialize to JSON string
  String toJsonString() {
    return jsonEncode({
      'nodes': _nodes.map((n) => n.toJson()).toList(),
      'edges': _edges.map((e) => e.toJson()).toList(),
      'next_id': _nextId,
    });
  }

  /// Load from JSON string
  void loadFromJson(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      _nodes.clear();
      _edges.clear();

      final nodesJson = data['nodes'] as List<dynamic>? ?? [];
      for (final nj in nodesJson) {
        _nodes.add(BtCanvasNode.fromJson(nj as Map<String, dynamic>));
      }

      final edgesJson = data['edges'] as List<dynamic>? ?? [];
      for (final ej in edgesJson) {
        _edges.add(BtCanvasEdge.fromJson(ej as Map<String, dynamic>));
      }

      _nextId = data['next_id'] as int? ?? _nodes.length;
      _selectedNodeId = null;
      _isDirty = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[HelixBtCanvas] Failed to load: $e');
    }
  }

  /// Mark as saved
  void markClean() {
    _isDirty = false;
  }
}
