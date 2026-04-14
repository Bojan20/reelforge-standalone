/// Core graph definition models for the Dynamic Hook Graph System.
///
/// HookGraphDefinition is the serializable representation of a complete hook graph.
/// It contains nodes, connections, and metadata.

import 'dart:ui';

/// Node execution state
enum NodeState { idle, active, cooldown, error }

/// Graph instance lifecycle state
enum GraphInstanceState { pooled, allocated, executing, finishing, done }

/// Node category for palette grouping and visual styling
enum NodeCategory {
  event(Color(0xFFFFD700), 'Event'),
  condition(Color(0xFFFF6B6B), 'Condition'),
  logic(Color(0xFF4ECDC4), 'Logic'),
  timing(Color(0xFFA78BFA), 'Timing'),
  audio(Color(0xFFFF9F43), 'Audio'),
  dsp(Color(0xFFEE5A24), 'DSP'),
  layer(Color(0xFF6C5CE7), 'Layer'),
  container(Color(0xFF00CEC9), 'Container'),
  control(Color(0xFF636E72), 'Control'),
  state(Color(0xFF55A3F0), 'State'),
  analytics(Color(0xFFE84393), 'Analytics'),
  slot(Color(0xFFFDAA2D), 'Slot'),
  debug(Color(0xFF95A5A6), 'Debug'),
  utility(Color(0xFFBDC3C7), 'Utility');

  final Color color;
  final String label;
  const NodeCategory(this.color, this.label);
}

/// A connection between two ports in the graph
class GraphConnection {
  final String id;
  final String fromNodeId;
  final String fromPortId;
  final String toNodeId;
  final String toPortId;

  const GraphConnection({
    required this.id,
    required this.fromNodeId,
    required this.fromPortId,
    required this.toNodeId,
    required this.toPortId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': {'node': fromNodeId, 'port': fromPortId},
        'to': {'node': toNodeId, 'port': toPortId},
      };

  factory GraphConnection.fromJson(Map<String, dynamic> json) {
    final from = json['from'] as Map<String, dynamic>;
    final to = json['to'] as Map<String, dynamic>;
    return GraphConnection(
      id: json['id'] as String,
      fromNodeId: from['node'] as String,
      fromPortId: from['port'] as String,
      toNodeId: to['node'] as String,
      toPortId: to['port'] as String,
    );
  }
}

/// Base graph node definition (serializable)
class GraphNodeDef {
  final String id;
  final String typeId;
  final Offset position;
  final Map<String, dynamic> parameters;

  const GraphNodeDef({
    required this.id,
    required this.typeId,
    required this.position,
    this.parameters = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': typeId,
        'position': {'x': position.dx, 'y': position.dy},
        'parameters': parameters,
      };

  factory GraphNodeDef.fromJson(Map<String, dynamic> json) {
    final pos = json['position'] as Map<String, dynamic>;
    return GraphNodeDef(
      id: json['id'] as String,
      typeId: json['type'] as String,
      position: Offset(
        (pos['x'] as num).toDouble(),
        (pos['y'] as num).toDouble(),
      ),
      parameters: (json['parameters'] as Map<String, dynamic>?) ?? {},
    );
  }
}

/// Complete hook graph definition
class HookGraphDefinition {
  final String id;
  final String name;
  final String description;
  final int version;
  final List<GraphNodeDef> nodes;
  final List<GraphConnection> connections;
  final Map<String, dynamic> metadata;

  const HookGraphDefinition({
    required this.id,
    required this.name,
    this.description = '',
    this.version = 1,
    this.nodes = const [],
    this.connections = const [],
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'version': version,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'connections': connections.map((c) => c.toJson()).toList(),
        'metadata': metadata,
      };

  factory HookGraphDefinition.fromJson(Map<String, dynamic> json) {
    return HookGraphDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      version: json['version'] as int? ?? 1,
      nodes: (json['nodes'] as List?)
              ?.map((n) => GraphNodeDef.fromJson(n as Map<String, dynamic>))
              .toList() ??
          [],
      connections: (json['connections'] as List?)
              ?.map(
                  (c) => GraphConnection.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  GraphNodeDef? nodeById(String nodeId) {
    try {
      return nodes.firstWhere((n) => n.id == nodeId);
    } catch (_) {
      return null;
    }
  }

  List<GraphConnection> connectionsTo(String nodeId) {
    return connections.where((c) => c.toNodeId == nodeId).toList();
  }

  List<GraphConnection> connectionsFrom(String nodeId) {
    return connections.where((c) => c.fromNodeId == nodeId).toList();
  }
}

/// Binding between an event pattern and a graph
class HookGraphBinding {
  final String eventPattern;
  final String graphId;
  final int priority;
  final bool exclusive;
  final String? stateGroup;
  final String? stateValue;

  const HookGraphBinding({
    required this.eventPattern,
    required this.graphId,
    this.priority = 0,
    this.exclusive = false,
    this.stateGroup,
    this.stateValue,
  });

  Map<String, dynamic> toJson() => {
        'event': eventPattern,
        'graph': graphId,
        'priority': priority,
        'exclusive': exclusive,
        if (stateGroup != null) 'stateGroup': stateGroup,
        if (stateValue != null) 'stateValue': stateValue,
      };

  factory HookGraphBinding.fromJson(Map<String, dynamic> json) {
    return HookGraphBinding(
      eventPattern: json['event'] as String,
      graphId: json['graph'] as String,
      priority: json['priority'] as int? ?? 0,
      exclusive: json['exclusive'] as bool? ?? false,
      stateGroup: json['stateGroup'] as String?,
      stateValue: json['stateValue'] as String?,
    );
  }
}
