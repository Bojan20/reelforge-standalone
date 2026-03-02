/// Dynamic Stage Flow Editor — Data Models (P-DSF Layer 1)
///
/// Immutable, JSON-serializable graph model for visual stage flow orchestration.
/// Replaces hardcoded Future.delayed() chains with a directed acyclic graph (DAG).
///
/// Integration points:
///   StageFlowGraph ←→ StageConfigurationService (130+ registered stages)
///   FlowExecutor   ←→ EventRegistry.triggerStage() (audio dispatch)
///   FlowPreset     ←→ SlotLabTemplate.behaviorTreeConfig (persistence)
library;

import 'dart:collection';

/// Sentinel value for copyWith — allows explicitly setting nullable fields to null.
const Object _sentinel = Object();

// ═══════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════

/// Node type determines execution behavior.
enum StageFlowNodeType {
  /// Regular stage — triggers EventRegistry.triggerStage(stageId)
  stage,

  /// Conditional gate — evaluates expression, routes to true/false edges
  gate,

  /// Fork — splits execution into parallel branches
  fork,

  /// Join — waits for all/any incoming parallel branches to complete
  join,

  /// Pure delay — no stage trigger, just timing
  delay,

  /// Group — contains sub-nodes (visual organization, collapsible)
  group;

  String toJson() => name;

  static StageFlowNodeType fromJson(dynamic json) {
    final s = json.toString();
    return StageFlowNodeType.values.firstWhere(
      (e) => e.name == s,
      orElse: () => StageFlowNodeType.stage,
    );
  }
}

/// Layer determines editability constraints.
enum FlowLayer {
  /// Layer 1: Engine Core — SPIN_START through SPIN_END
  /// LOCKED — cannot be deleted or reordered relative to other engineCore nodes
  engineCore,

  /// Layer 2: Feature Composer — cascade, free spins, hold & win, etc.
  /// Dynamic — enabled/disabled per game config
  featureComposer,

  /// Layer 3: Audio Mapping — user-defined presentation stages
  /// Fully editable — user can add, remove, reorder freely
  audioMapping;

  String toJson() => name;

  static FlowLayer fromJson(dynamic json) {
    final s = json.toString();
    return FlowLayer.values.firstWhere(
      (e) => e.name == s,
      orElse: () => FlowLayer.audioMapping,
    );
  }
}

/// How timing is resolved for a node.
enum TimingMode {
  /// Execute immediately after previous node completes
  sequential,

  /// Execute after fixed delayMs from graph start (absolute timeline position)
  absolute,

  /// Execute relative to another node's completion
  relative,

  /// Snap execution to nearest musical beat boundary
  beatQuantized;

  String toJson() => name;

  static TimingMode fromJson(dynamic json) {
    final s = json.toString();
    return TimingMode.values.firstWhere(
      (e) => e.name == s,
      orElse: () => TimingMode.sequential,
    );
  }
}

/// Edge connection type — determines routing behavior.
enum EdgeType {
  /// Default sequential connection
  normal,

  /// Gate node → condition evaluates to true
  onTrue,

  /// Gate node → condition evaluates to false
  onFalse,

  /// Fork node → parallel branch
  parallel,

  /// Executed only if primary edge's condition fails
  fallback;

  String toJson() => name;

  static EdgeType fromJson(dynamic json) {
    final s = json.toString();
    return EdgeType.values.firstWhere(
      (e) => e.name == s,
      orElse: () => EdgeType.normal,
    );
  }
}

/// Runtime variable type for condition expressions.
enum RuntimeVarType {
  intType,
  doubleType,
  boolType,
  stringType;

  String toJson() => name;

  static RuntimeVarType fromJson(dynamic json) {
    final s = json.toString();
    return RuntimeVarType.values.firstWhere(
      (e) => e.name == s,
      orElse: () => RuntimeVarType.intType,
    );
  }
}

/// Validation error severity.
enum FlowValidationSeverity {
  error,
  warning,
  info;

  String toJson() => name;

  static FlowValidationSeverity fromJson(dynamic json) {
    final s = json.toString();
    return FlowValidationSeverity.values.firstWhere(
      (e) => e.name == s,
      orElse: () => FlowValidationSeverity.error,
    );
  }
}

/// Flow preset category.
enum FlowPresetCategory {
  baseGame,
  freeSpins,
  holdAndWin,
  cascading,
  bonusGame,
  jackpotPresentation,
  custom;

  String toJson() => name;

  static FlowPresetCategory fromJson(dynamic json) {
    final s = json.toString();
    return FlowPresetCategory.values.firstWhere(
      (e) => e.name == s,
      orElse: () => FlowPresetCategory.custom,
    );
  }

  String get displayName => switch (this) {
    baseGame => 'Base Game',
    freeSpins => 'Free Spins',
    holdAndWin => 'Hold & Win',
    cascading => 'Cascading',
    bonusGame => 'Bonus Game',
    jackpotPresentation => 'Jackpot',
    custom => 'Custom',
  };
}

/// Join mode for parallel branch convergence.
enum JoinMode {
  /// Wait for ALL incoming branches to complete
  all,

  /// Proceed when FIRST branch completes (cancel others)
  any;

  String toJson() => name;

  static JoinMode fromJson(dynamic json) {
    final s = json.toString();
    return JoinMode.values.firstWhere(
      (e) => e.name == s,
      orElse: () => JoinMode.all,
    );
  }
}

/// Flow execution result status.
enum FlowExecutionStatus {
  completed,
  cancelled,
  slamStopped,
  error;

  String toJson() => name;

  static FlowExecutionStatus fromJson(dynamic json) {
    final s = json.toString();
    return FlowExecutionStatus.values.firstWhere(
      (e) => e.name == s,
      orElse: () => FlowExecutionStatus.error,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TIMING CONFIG
// ═══════════════════════════════════════════════════════════════════════════

/// Timing configuration for a node.
class TimingConfig {
  final TimingMode mode;
  final int delayMs;
  final int durationMs;
  final String? relativeToNodeId;
  final int relativeOffsetMs;
  final double? beatQuantize;
  final int minDurationMs;
  final int maxDurationMs;
  final bool canSkip;
  final bool canSlamStop;

  const TimingConfig({
    this.mode = TimingMode.sequential,
    this.delayMs = 0,
    this.durationMs = 0,
    this.relativeToNodeId,
    this.relativeOffsetMs = 0,
    this.beatQuantize,
    this.minDurationMs = 0,
    this.maxDurationMs = 0,
    this.canSkip = true,
    this.canSlamStop = true,
  });

  const TimingConfig.instant() : this();

  const TimingConfig.fixed(int ms) : this(durationMs: ms);

  const TimingConfig.afterNode(String nodeId, {int offsetMs = 0})
      : this(
          mode: TimingMode.relative,
          relativeToNodeId: nodeId,
          relativeOffsetMs: offsetMs,
        );

  TimingConfig copyWith({
    TimingMode? mode,
    int? delayMs,
    int? durationMs,
    Object? relativeToNodeId = _sentinel,
    int? relativeOffsetMs,
    Object? beatQuantize = _sentinel,
    int? minDurationMs,
    int? maxDurationMs,
    bool? canSkip,
    bool? canSlamStop,
  }) {
    return TimingConfig(
      mode: mode ?? this.mode,
      delayMs: delayMs ?? this.delayMs,
      durationMs: durationMs ?? this.durationMs,
      relativeToNodeId: identical(relativeToNodeId, _sentinel)
          ? this.relativeToNodeId
          : relativeToNodeId as String?,
      relativeOffsetMs: relativeOffsetMs ?? this.relativeOffsetMs,
      beatQuantize: identical(beatQuantize, _sentinel)
          ? this.beatQuantize
          : beatQuantize as double?,
      minDurationMs: minDurationMs ?? this.minDurationMs,
      maxDurationMs: maxDurationMs ?? this.maxDurationMs,
      canSkip: canSkip ?? this.canSkip,
      canSlamStop: canSlamStop ?? this.canSlamStop,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.toJson(),
    'delayMs': delayMs,
    'durationMs': durationMs,
    if (relativeToNodeId != null) 'relativeToNodeId': relativeToNodeId,
    'relativeOffsetMs': relativeOffsetMs,
    if (beatQuantize != null) 'beatQuantize': beatQuantize,
    'minDurationMs': minDurationMs,
    'maxDurationMs': maxDurationMs,
    'canSkip': canSkip,
    'canSlamStop': canSlamStop,
  };

  factory TimingConfig.fromJson(Map<String, dynamic> json) => TimingConfig(
    mode: TimingMode.fromJson(json['mode']),
    delayMs: json['delayMs'] as int? ?? 0,
    durationMs: json['durationMs'] as int? ?? 0,
    relativeToNodeId: json['relativeToNodeId'] as String?,
    relativeOffsetMs: json['relativeOffsetMs'] as int? ?? 0,
    beatQuantize: (json['beatQuantize'] as num?)?.toDouble(),
    minDurationMs: json['minDurationMs'] as int? ?? 0,
    maxDurationMs: json['maxDurationMs'] as int? ?? 0,
    canSkip: json['canSkip'] as bool? ?? true,
    canSlamStop: json['canSlamStop'] as bool? ?? true,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE FLOW NODE
// ═══════════════════════════════════════════════════════════════════════════

/// A single node in the stage flow graph.
/// Immutable, JSON-serializable, uniquely identified.
class StageFlowNode {
  final String id;
  final String stageId;
  final StageFlowNodeType type;
  final FlowLayer layer;
  final bool locked;

  // Timing
  final TimingConfig timing;

  // Conditions (expression strings)
  final String? enterCondition;
  final String? skipCondition;
  final String? exitCondition;

  // Visual position (for editor canvas)
  final double x;
  final double y;

  // Metadata
  final Map<String, dynamic> properties;
  final String? description;
  final String? color;

  // Join mode (only relevant for join nodes)
  final JoinMode joinMode;

  // Group parent (for nodes inside a group)
  final String? parentGroupId;

  const StageFlowNode({
    required this.id,
    required this.stageId,
    this.type = StageFlowNodeType.stage,
    this.layer = FlowLayer.audioMapping,
    this.locked = false,
    this.timing = const TimingConfig(),
    this.enterCondition,
    this.skipCondition,
    this.exitCondition,
    this.x = 0,
    this.y = 0,
    this.properties = const {},
    this.description,
    this.color,
    this.joinMode = JoinMode.all,
    this.parentGroupId,
  });

  StageFlowNode copyWith({
    String? id,
    String? stageId,
    StageFlowNodeType? type,
    FlowLayer? layer,
    bool? locked,
    TimingConfig? timing,
    Object? enterCondition = _sentinel,
    Object? skipCondition = _sentinel,
    Object? exitCondition = _sentinel,
    double? x,
    double? y,
    Map<String, dynamic>? properties,
    Object? description = _sentinel,
    Object? color = _sentinel,
    JoinMode? joinMode,
    Object? parentGroupId = _sentinel,
  }) {
    return StageFlowNode(
      id: id ?? this.id,
      stageId: stageId ?? this.stageId,
      type: type ?? this.type,
      layer: layer ?? this.layer,
      locked: locked ?? this.locked,
      timing: timing ?? this.timing,
      enterCondition: identical(enterCondition, _sentinel)
          ? this.enterCondition
          : enterCondition as String?,
      skipCondition: identical(skipCondition, _sentinel)
          ? this.skipCondition
          : skipCondition as String?,
      exitCondition: identical(exitCondition, _sentinel)
          ? this.exitCondition
          : exitCondition as String?,
      x: x ?? this.x,
      y: y ?? this.y,
      properties: properties ?? this.properties,
      description: identical(description, _sentinel)
          ? this.description
          : description as String?,
      color: identical(color, _sentinel) ? this.color : color as String?,
      joinMode: joinMode ?? this.joinMode,
      parentGroupId: identical(parentGroupId, _sentinel)
          ? this.parentGroupId
          : parentGroupId as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'stageId': stageId,
    'type': type.toJson(),
    'layer': layer.toJson(),
    'locked': locked,
    'timing': timing.toJson(),
    if (enterCondition != null) 'enterCondition': enterCondition,
    if (skipCondition != null) 'skipCondition': skipCondition,
    if (exitCondition != null) 'exitCondition': exitCondition,
    'x': x,
    'y': y,
    if (properties.isNotEmpty) 'properties': properties,
    if (description != null) 'description': description,
    if (color != null) 'color': color,
    'joinMode': joinMode.toJson(),
    if (parentGroupId != null) 'parentGroupId': parentGroupId,
  };

  factory StageFlowNode.fromJson(Map<String, dynamic> json) => StageFlowNode(
    id: json['id'] as String,
    stageId: json['stageId'] as String,
    type: StageFlowNodeType.fromJson(json['type']),
    layer: FlowLayer.fromJson(json['layer']),
    locked: json['locked'] as bool? ?? false,
    timing: json['timing'] != null
        ? TimingConfig.fromJson(json['timing'] as Map<String, dynamic>)
        : const TimingConfig(),
    enterCondition: json['enterCondition'] as String?,
    skipCondition: json['skipCondition'] as String?,
    exitCondition: json['exitCondition'] as String?,
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    properties: (json['properties'] as Map<String, dynamic>?) ?? const {},
    description: json['description'] as String?,
    color: json['color'] as String?,
    joinMode: json['joinMode'] != null
        ? JoinMode.fromJson(json['joinMode'])
        : JoinMode.all,
    parentGroupId: json['parentGroupId'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is StageFlowNode && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'StageFlowNode($id: $stageId [$type])';
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE FLOW EDGE
// ═══════════════════════════════════════════════════════════════════════════

/// Directed connection between two nodes.
class StageFlowEdge {
  final String id;
  final String sourceNodeId;
  final String targetNodeId;
  final String? condition;
  final int transitionDelayMs;
  final EdgeType type;

  const StageFlowEdge({
    required this.id,
    required this.sourceNodeId,
    required this.targetNodeId,
    this.condition,
    this.transitionDelayMs = 0,
    this.type = EdgeType.normal,
  });

  StageFlowEdge copyWith({
    String? id,
    String? sourceNodeId,
    String? targetNodeId,
    Object? condition = _sentinel,
    int? transitionDelayMs,
    EdgeType? type,
  }) {
    return StageFlowEdge(
      id: id ?? this.id,
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      targetNodeId: targetNodeId ?? this.targetNodeId,
      condition: identical(condition, _sentinel)
          ? this.condition
          : condition as String?,
      transitionDelayMs: transitionDelayMs ?? this.transitionDelayMs,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceNodeId': sourceNodeId,
    'targetNodeId': targetNodeId,
    if (condition != null) 'condition': condition,
    'transitionDelayMs': transitionDelayMs,
    'type': type.toJson(),
  };

  factory StageFlowEdge.fromJson(Map<String, dynamic> json) => StageFlowEdge(
    id: json['id'] as String,
    sourceNodeId: json['sourceNodeId'] as String,
    targetNodeId: json['targetNodeId'] as String,
    condition: json['condition'] as String?,
    transitionDelayMs: json['transitionDelayMs'] as int? ?? 0,
    type: EdgeType.fromJson(json['type']),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is StageFlowEdge && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'StageFlowEdge($sourceNodeId → $targetNodeId [$type])';
}

// ═══════════════════════════════════════════════════════════════════════════
// RUNTIME VARIABLE DEFINITION
// ═══════════════════════════════════════════════════════════════════════════

/// Definition of a variable available during flow execution.
class RuntimeVariableDefinition {
  final String name;
  final RuntimeVarType type;
  final dynamic defaultValue;
  final String? description;
  final bool readOnly;

  const RuntimeVariableDefinition({
    required this.name,
    this.type = RuntimeVarType.intType,
    this.defaultValue,
    this.description,
    this.readOnly = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.toJson(),
    if (defaultValue != null) 'defaultValue': defaultValue,
    if (description != null) 'description': description,
    'readOnly': readOnly,
  };

  factory RuntimeVariableDefinition.fromJson(Map<String, dynamic> json) =>
      RuntimeVariableDefinition(
        name: json['name'] as String,
        type: RuntimeVarType.fromJson(json['type']),
        defaultValue: json['defaultValue'],
        description: json['description'] as String?,
        readOnly: json['readOnly'] as bool? ?? false,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOW CONSTRAINTS
// ═══════════════════════════════════════════════════════════════════════════

/// Regulatory and design constraints applied to the graph.
class FlowConstraints {
  final int minSpinCycleMs;
  final bool allowSlamStop;
  final int maxRecallDepth;
  final int maxParallelBranches;
  final int maxGraphNodes;
  final int maxNestingDepth;
  final bool requireDeterministic;

  const FlowConstraints({
    this.minSpinCycleMs = 2500,
    this.allowSlamStop = true,
    this.maxRecallDepth = 10,
    this.maxParallelBranches = 8,
    this.maxGraphNodes = 200,
    this.maxNestingDepth = 4,
    this.requireDeterministic = true,
  });

  /// UKGC feature mode — stricter constraints
  const FlowConstraints.ukgcFeature()
      : minSpinCycleMs = 2500,
        allowSlamStop = false,
        maxRecallDepth = 10,
        maxParallelBranches = 8,
        maxGraphNodes = 200,
        maxNestingDepth = 4,
        requireDeterministic = true;

  /// Relaxed mode for development/testing
  const FlowConstraints.relaxed()
      : minSpinCycleMs = 0,
        allowSlamStop = true,
        maxRecallDepth = 10,
        maxParallelBranches = 16,
        maxGraphNodes = 500,
        maxNestingDepth = 8,
        requireDeterministic = false;

  Map<String, dynamic> toJson() => {
    'minSpinCycleMs': minSpinCycleMs,
    'allowSlamStop': allowSlamStop,
    'maxRecallDepth': maxRecallDepth,
    'maxParallelBranches': maxParallelBranches,
    'maxGraphNodes': maxGraphNodes,
    'maxNestingDepth': maxNestingDepth,
    'requireDeterministic': requireDeterministic,
  };

  factory FlowConstraints.fromJson(Map<String, dynamic> json) =>
      FlowConstraints(
        minSpinCycleMs: json['minSpinCycleMs'] as int? ?? 2500,
        allowSlamStop: json['allowSlamStop'] as bool? ?? true,
        maxRecallDepth: json['maxRecallDepth'] as int? ?? 10,
        maxParallelBranches: json['maxParallelBranches'] as int? ?? 8,
        maxGraphNodes: json['maxGraphNodes'] as int? ?? 200,
        maxNestingDepth: json['maxNestingDepth'] as int? ?? 4,
        requireDeterministic: json['requireDeterministic'] as bool? ?? true,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOW VALIDATION ERROR
// ═══════════════════════════════════════════════════════════════════════════

/// Validation error/warning for a flow graph.
class FlowValidationError {
  final FlowValidationSeverity severity;
  final String nodeId;
  final String code;
  final String message;

  const FlowValidationError({
    required this.severity,
    required this.nodeId,
    required this.code,
    required this.message,
  });

  bool get isError => severity == FlowValidationSeverity.error;
  bool get isWarning => severity == FlowValidationSeverity.warning;

  @override
  String toString() => '[$severity] $code @ $nodeId: $message';
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE FLOW GRAPH
// ═══════════════════════════════════════════════════════════════════════════

/// Complete directed graph representing a game flow.
/// Immutable — all mutations return new instances.
class StageFlowGraph {
  final String id;
  final String name;
  final String? description;
  final List<StageFlowNode> nodes;
  final List<StageFlowEdge> edges;
  final Map<String, RuntimeVariableDefinition> variables;
  final FlowConstraints constraints;
  final DateTime createdAt;
  final DateTime modifiedAt;

  const StageFlowGraph({
    required this.id,
    required this.name,
    this.description,
    this.nodes = const [],
    this.edges = const [],
    this.variables = const {},
    this.constraints = const FlowConstraints(),
    required this.createdAt,
    required this.modifiedAt,
  });

  // ─── Node index for O(1) lookups ──────────────────────────────────────

  Map<String, StageFlowNode> get _nodeIndex {
    final map = <String, StageFlowNode>{};
    for (final n in nodes) {
      map[n.id] = n;
    }
    return map;
  }

  // ─── Graph operations (return new instance) ───────────────────────────

  StageFlowGraph addNode(StageFlowNode node) {
    if (nodes.length >= constraints.maxGraphNodes) return this;
    return _copyWith(
      nodes: [...nodes, node],
      modifiedAt: DateTime.now(),
    );
  }

  StageFlowGraph removeNode(String nodeId) {
    final node = getNode(nodeId);
    if (node == null || node.locked) return this;
    return _copyWith(
      nodes: nodes.where((n) => n.id != nodeId).toList(),
      edges: edges
          .where((e) => e.sourceNodeId != nodeId && e.targetNodeId != nodeId)
          .toList(),
      modifiedAt: DateTime.now(),
    );
  }

  StageFlowGraph updateNode(String nodeId, StageFlowNode updated) {
    return _copyWith(
      nodes: nodes.map((n) => n.id == nodeId ? updated : n).toList(),
      modifiedAt: DateTime.now(),
    );
  }

  StageFlowGraph moveNode(String nodeId, double x, double y) {
    return _copyWith(
      nodes: nodes
          .map((n) => n.id == nodeId ? n.copyWith(x: x, y: y) : n)
          .toList(),
      modifiedAt: DateTime.now(),
    );
  }

  StageFlowGraph addEdge(StageFlowEdge edge) {
    return _copyWith(
      edges: [...edges, edge],
      modifiedAt: DateTime.now(),
    );
  }

  StageFlowGraph removeEdge(String edgeId) {
    return _copyWith(
      edges: edges.where((e) => e.id != edgeId).toList(),
      modifiedAt: DateTime.now(),
    );
  }

  // ─── Reordering (the core feature) ────────────────────────────────────

  /// Move nodeId to execute after afterNodeId (rewire edges).
  StageFlowGraph reorderNode(
    String nodeId, {
    String? afterNodeId,
    String? beforeNodeId,
  }) {
    final node = getNode(nodeId);
    if (node == null || node.locked) return this;

    // Remove all edges connected to this node
    final filteredEdges = edges
        .where((e) => e.sourceNodeId != nodeId && e.targetNodeId != nodeId)
        .toList();

    if (afterNodeId != null) {
      // Get outgoing edges from afterNode
      final afterOutEdges =
          filteredEdges.where((e) => e.sourceNodeId == afterNodeId).toList();

      // Remove those edges — they'll be rerouted through our node
      final rewired = filteredEdges
          .where((e) => !afterOutEdges.contains(e))
          .toList();

      // afterNode → nodeId
      rewired.add(StageFlowEdge(
        id: '${afterNodeId}_to_$nodeId',
        sourceNodeId: afterNodeId,
        targetNodeId: nodeId,
      ));

      // nodeId → each original target of afterNode
      for (final e in afterOutEdges) {
        rewired.add(StageFlowEdge(
          id: '${nodeId}_to_${e.targetNodeId}',
          sourceNodeId: nodeId,
          targetNodeId: e.targetNodeId,
          type: e.type,
          condition: e.condition,
          transitionDelayMs: e.transitionDelayMs,
        ));
      }

      return _copyWith(edges: rewired, modifiedAt: DateTime.now());
    }

    if (beforeNodeId != null) {
      // Get incoming edges to beforeNode
      final beforeInEdges =
          filteredEdges.where((e) => e.targetNodeId == beforeNodeId).toList();

      final rewired = filteredEdges
          .where((e) => !beforeInEdges.contains(e))
          .toList();

      // Each original source → nodeId
      for (final e in beforeInEdges) {
        rewired.add(StageFlowEdge(
          id: '${e.sourceNodeId}_to_$nodeId',
          sourceNodeId: e.sourceNodeId,
          targetNodeId: nodeId,
          type: e.type,
          condition: e.condition,
          transitionDelayMs: e.transitionDelayMs,
        ));
      }

      // nodeId → beforeNode
      rewired.add(StageFlowEdge(
        id: '${nodeId}_to_$beforeNodeId',
        sourceNodeId: nodeId,
        targetNodeId: beforeNodeId,
      ));

      return _copyWith(edges: rewired, modifiedAt: DateTime.now());
    }

    return this;
  }

  /// Swap execution positions of two nodes.
  StageFlowGraph swapNodes(String nodeIdA, String nodeIdB) {
    final a = getNode(nodeIdA);
    final b = getNode(nodeIdB);
    if (a == null || b == null) return this;
    if (a.locked || b.locked) return this;

    // Swap all edge references
    final swappedEdges = edges.map((e) {
      var src = e.sourceNodeId;
      var tgt = e.targetNodeId;
      if (src == nodeIdA) {
        src = nodeIdB;
      } else if (src == nodeIdB) {
        src = nodeIdA;
      }
      if (tgt == nodeIdA) {
        tgt = nodeIdB;
      } else if (tgt == nodeIdB) {
        tgt = nodeIdA;
      }
      return e.copyWith(sourceNodeId: src, targetNodeId: tgt);
    }).toList();

    return _copyWith(edges: swappedEdges, modifiedAt: DateTime.now());
  }

  /// Move a node into a parallel branch of a fork.
  StageFlowGraph moveNodeToParallelBranch(
    String nodeId,
    String forkId,
    int branchIndex,
  ) {
    final node = getNode(nodeId);
    final fork = getNode(forkId);
    if (node == null || fork == null) return this;
    if (fork.type != StageFlowNodeType.fork) return this;

    final branches = getParallelBranches(forkId);
    if (branchIndex < 0 || branchIndex >= branches.length) return this;

    // Remove node from current position
    var result = removeNode(nodeId);
    // Re-add node
    result = result.addNode(node);

    // Insert into target branch: find last node in branch, add edge from it to our node
    final branch = branches[branchIndex];
    if (branch.isNotEmpty) {
      final lastInBranch = branch.last;
      // Find join node that this branch connects to
      final joinEdge = edges.firstWhere(
        (e) => e.sourceNodeId == lastInBranch.id,
        orElse: () => StageFlowEdge(
          id: 'temp',
          sourceNodeId: lastInBranch.id,
          targetNodeId: '',
        ),
      );
      if (joinEdge.targetNodeId.isNotEmpty) {
        // lastInBranch → nodeId → joinTarget
        result = result.addEdge(StageFlowEdge(
          id: '${lastInBranch.id}_to_$nodeId',
          sourceNodeId: lastInBranch.id,
          targetNodeId: nodeId,
          type: EdgeType.parallel,
        ));
        result = result.addEdge(StageFlowEdge(
          id: '${nodeId}_to_${joinEdge.targetNodeId}',
          sourceNodeId: nodeId,
          targetNodeId: joinEdge.targetNodeId,
        ));
      }
    }

    return result;
  }

  // ─── Queries ──────────────────────────────────────────────────────────

  StageFlowNode? getNode(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  List<StageFlowNode> getSuccessors(String nodeId) {
    final index = _nodeIndex;
    return edges
        .where((e) => e.sourceNodeId == nodeId)
        .map((e) => index[e.targetNodeId])
        .whereType<StageFlowNode>()
        .toList();
  }

  List<StageFlowNode> getPredecessors(String nodeId) {
    final index = _nodeIndex;
    return edges
        .where((e) => e.targetNodeId == nodeId)
        .map((e) => index[e.sourceNodeId])
        .whereType<StageFlowNode>()
        .toList();
  }

  List<StageFlowEdge> getOutEdges(String nodeId) {
    return edges.where((e) => e.sourceNodeId == nodeId).toList();
  }

  List<StageFlowEdge> getInEdges(String nodeId) {
    return edges.where((e) => e.targetNodeId == nodeId).toList();
  }

  /// Get parallel branches emanating from a fork node.
  List<List<StageFlowNode>> getParallelBranches(String forkId) {
    final parallelEdges =
        edges.where((e) => e.sourceNodeId == forkId && e.type == EdgeType.parallel);

    final branches = <List<StageFlowNode>>[];
    final index = _nodeIndex;

    for (final edge in parallelEdges) {
      final branch = <StageFlowNode>[];
      var currentId = edge.targetNodeId;

      // Walk until we hit a join node or dead end
      while (true) {
        final node = index[currentId];
        if (node == null || node.type == StageFlowNodeType.join) break;
        branch.add(node);

        final outEdges = getOutEdges(currentId);
        if (outEdges.length != 1) break;
        currentId = outEdges.first.targetNodeId;
      }

      branches.add(branch);
    }

    return branches;
  }

  /// Cycle detection — graph must be a DAG.
  bool hasCycle() {
    final visited = <String>{};
    final inStack = <String>{};

    bool dfs(String nodeId) {
      if (inStack.contains(nodeId)) return true;
      if (visited.contains(nodeId)) return false;

      visited.add(nodeId);
      inStack.add(nodeId);

      for (final edge in getOutEdges(nodeId)) {
        if (dfs(edge.targetNodeId)) return true;
      }

      inStack.remove(nodeId);
      return false;
    }

    for (final node in nodes) {
      if (dfs(node.id)) return true;
    }
    return false;
  }

  /// Topological sort (Kahn's algorithm).
  List<StageFlowNode> topologicalSort() {
    final index = _nodeIndex;
    final inDegree = <String, int>{};

    for (final n in nodes) {
      inDegree[n.id] = 0;
    }
    for (final e in edges) {
      inDegree[e.targetNodeId] = (inDegree[e.targetNodeId] ?? 0) + 1;
    }

    final queue = Queue<String>();
    for (final entry in inDegree.entries) {
      if (entry.value == 0) queue.add(entry.key);
    }

    final result = <StageFlowNode>[];
    while (queue.isNotEmpty) {
      final id = queue.removeFirst();
      final node = index[id];
      if (node != null) result.add(node);

      for (final edge in getOutEdges(id)) {
        final target = edge.targetNodeId;
        inDegree[target] = (inDegree[target] ?? 1) - 1;
        if (inDegree[target] == 0) queue.add(target);
      }
    }

    return result;
  }

  /// First node — entry point of the flow.
  StageFlowNode? get entryNode {
    final hasIncoming = edges.map((e) => e.targetNodeId).toSet();
    for (final n in nodes) {
      if (!hasIncoming.contains(n.id)) return n;
    }
    return nodes.isNotEmpty ? nodes.first : null;
  }

  /// Last node — exit point of the flow.
  StageFlowNode? get exitNode {
    final hasOutgoing = edges.map((e) => e.sourceNodeId).toSet();
    for (final n in nodes) {
      if (!hasOutgoing.contains(n.id)) return n;
    }
    return nodes.isNotEmpty ? nodes.last : null;
  }

  // ─── Subgraph operations ──────────────────────────────────────────────

  /// Extract a subgraph containing only the specified node IDs.
  StageFlowGraph extractSubgraph(Set<String> nodeIds) {
    return _copyWith(
      nodes: nodes.where((n) => nodeIds.contains(n.id)).toList(),
      edges: edges
          .where((e) =>
              nodeIds.contains(e.sourceNodeId) &&
              nodeIds.contains(e.targetNodeId))
          .toList(),
      modifiedAt: DateTime.now(),
    );
  }

  /// Merge a subgraph after a specific node.
  StageFlowGraph mergeSubgraph(StageFlowGraph sub, String attachAfterNodeId) {
    var result = _copyWith(
      nodes: [...nodes, ...sub.nodes],
      edges: [...edges, ...sub.edges],
      modifiedAt: DateTime.now(),
    );

    // Connect attachAfterNode → subgraph entry
    final subEntry = sub.entryNode;
    if (subEntry != null) {
      result = result.addEdge(StageFlowEdge(
        id: '${attachAfterNodeId}_to_${subEntry.id}',
        sourceNodeId: attachAfterNodeId,
        targetNodeId: subEntry.id,
      ));
    }

    return result;
  }

  // ─── Validation ───────────────────────────────────────────────────────

  List<FlowValidationError> validate() {
    final errors = <FlowValidationError>[];
    final index = _nodeIndex;

    // MISSING_ENTRY
    if (entryNode == null) {
      errors.add(const FlowValidationError(
        severity: FlowValidationSeverity.error,
        nodeId: '',
        code: 'MISSING_ENTRY',
        message: 'No entry node found (no node without incoming edges)',
      ));
    }

    // MISSING_EXIT
    if (exitNode == null && nodes.isNotEmpty) {
      errors.add(const FlowValidationError(
        severity: FlowValidationSeverity.error,
        nodeId: '',
        code: 'MISSING_EXIT',
        message: 'No exit node found (no node without outgoing edges)',
      ));
    }

    // CYCLE_DETECTED
    if (hasCycle()) {
      errors.add(const FlowValidationError(
        severity: FlowValidationSeverity.error,
        nodeId: '',
        code: 'CYCLE_DETECTED',
        message: 'Graph contains a cycle — must be a DAG',
      ));
    }

    // Per-node validation
    final reachable = _computeReachable();

    for (final node in nodes) {
      final inEdges = getInEdges(node.id);
      final outEdges = getOutEdges(node.id);

      // ORPHAN_NODE — no edges at all (unless it's the only node)
      if (nodes.length > 1 && inEdges.isEmpty && outEdges.isEmpty) {
        errors.add(FlowValidationError(
          severity: FlowValidationSeverity.error,
          nodeId: node.id,
          code: 'ORPHAN_NODE',
          message: 'Node "${node.stageId}" has no connections',
        ));
      }

      // UNREACHABLE_NODE
      if (!reachable.contains(node.id) && entryNode?.id != node.id) {
        errors.add(FlowValidationError(
          severity: FlowValidationSeverity.warning,
          nodeId: node.id,
          code: 'UNREACHABLE_NODE',
          message: 'Node "${node.stageId}" is unreachable from entry',
        ));
      }

      // Gate-specific validation
      if (node.type == StageFlowNodeType.gate) {
        final hasTrue = outEdges.any((e) => e.type == EdgeType.onTrue);
        final hasFalse = outEdges.any((e) => e.type == EdgeType.onFalse);

        if (!hasTrue) {
          errors.add(FlowValidationError(
            severity: FlowValidationSeverity.error,
            nodeId: node.id,
            code: 'GATE_MISSING_TRUE',
            message: 'Gate "${node.stageId}" has no onTrue edge',
          ));
        }
        if (!hasFalse) {
          errors.add(FlowValidationError(
            severity: FlowValidationSeverity.warning,
            nodeId: node.id,
            code: 'GATE_MISSING_FALSE',
            message: 'Gate "${node.stageId}" has no onFalse edge (defaults to skip)',
          ));
        }
      }

      // Fork-specific validation
      if (node.type == StageFlowNodeType.fork) {
        final parallelEdges =
            outEdges.where((e) => e.type == EdgeType.parallel).toList();
        if (parallelEdges.length < 2) {
          errors.add(FlowValidationError(
            severity: FlowValidationSeverity.warning,
            nodeId: node.id,
            code: 'FORK_SINGLE_BRANCH',
            message: 'Fork "${node.stageId}" has fewer than 2 parallel branches',
          ));
        }
        if (parallelEdges.length > constraints.maxParallelBranches) {
          errors.add(FlowValidationError(
            severity: FlowValidationSeverity.error,
            nodeId: node.id,
            code: 'PARALLEL_LIMIT',
            message:
                'Fork "${node.stageId}" has ${parallelEdges.length} branches (max ${constraints.maxParallelBranches})',
          ));
        }
      }

      // Timing validation
      if (node.timing.durationMs > 0 &&
          node.timing.maxDurationMs > 0 &&
          node.timing.durationMs > node.timing.maxDurationMs) {
        errors.add(FlowValidationError(
          severity: FlowValidationSeverity.warning,
          nodeId: node.id,
          code: 'TIMING_EXCEEDS_MAX',
          message:
              'Node "${node.stageId}" duration ${node.timing.durationMs}ms exceeds max ${node.timing.maxDurationMs}ms',
        ));
      }
    }

    // Nesting depth
    _validateNestingDepth(errors);

    return errors;
  }

  Set<String> _computeReachable() {
    final entry = entryNode;
    if (entry == null) return {};

    final visited = <String>{};
    final queue = Queue<String>();
    queue.add(entry.id);
    visited.add(entry.id);

    while (queue.isNotEmpty) {
      final id = queue.removeFirst();
      for (final edge in getOutEdges(id)) {
        if (!visited.contains(edge.targetNodeId)) {
          visited.add(edge.targetNodeId);
          queue.add(edge.targetNodeId);
        }
      }
    }
    return visited;
  }

  void _validateNestingDepth(List<FlowValidationError> errors) {
    for (final node in nodes) {
      var depth = 0;
      var parentId = node.parentGroupId;
      while (parentId != null && depth < constraints.maxNestingDepth + 1) {
        depth++;
        final parent = getNode(parentId);
        parentId = parent?.parentGroupId;
      }
      if (depth > constraints.maxNestingDepth) {
        errors.add(FlowValidationError(
          severity: FlowValidationSeverity.error,
          nodeId: node.id,
          code: 'NESTING_LIMIT',
          message:
              'Node "${node.stageId}" nesting depth $depth exceeds max ${constraints.maxNestingDepth}',
        ));
      }
    }
  }

  // ─── Serialization ────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'edges': edges.map((e) => e.toJson()).toList(),
    'variables':
        variables.map((k, v) => MapEntry(k, v.toJson())),
    'constraints': constraints.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
  };

  factory StageFlowGraph.fromJson(Map<String, dynamic> json) {
    final varsJson = json['variables'] as Map<String, dynamic>? ?? {};
    final variables = varsJson.map((k, v) =>
        MapEntry(k, RuntimeVariableDefinition.fromJson(v as Map<String, dynamic>)));

    return StageFlowGraph(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      nodes: (json['nodes'] as List<dynamic>?)
              ?.map((n) => StageFlowNode.fromJson(n as Map<String, dynamic>))
              .toList() ??
          [],
      edges: (json['edges'] as List<dynamic>?)
              ?.map((e) => StageFlowEdge.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      variables: variables,
      constraints: json['constraints'] != null
          ? FlowConstraints.fromJson(json['constraints'] as Map<String, dynamic>)
          : const FlowConstraints(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
    );
  }

  // ─── Private ──────────────────────────────────────────────────────────

  StageFlowGraph _copyWith({
    String? id,
    String? name,
    String? description,
    List<StageFlowNode>? nodes,
    List<StageFlowEdge>? edges,
    Map<String, RuntimeVariableDefinition>? variables,
    FlowConstraints? constraints,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    return StageFlowGraph(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      variables: variables ?? this.variables,
      constraints: constraints ?? this.constraints,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  @override
  String toString() =>
      'StageFlowGraph($name: ${nodes.length} nodes, ${edges.length} edges)';
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOW PRESET
// ═══════════════════════════════════════════════════════════════════════════

/// Named snapshot of a complete flow graph.
class FlowPreset {
  final String id;
  final String name;
  final String? description;
  final FlowPresetCategory category;
  final StageFlowGraph graph;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final bool isBuiltIn;

  const FlowPreset({
    required this.id,
    required this.name,
    this.description,
    this.category = FlowPresetCategory.custom,
    required this.graph,
    this.metadata = const {},
    required this.createdAt,
    this.isBuiltIn = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'category': category.toJson(),
    'graph': graph.toJson(),
    if (metadata.isNotEmpty) 'metadata': metadata,
    'createdAt': createdAt.toIso8601String(),
    'isBuiltIn': isBuiltIn,
  };

  factory FlowPreset.fromJson(Map<String, dynamic> json) => FlowPreset(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    category: FlowPresetCategory.fromJson(json['category']),
    graph: StageFlowGraph.fromJson(json['graph'] as Map<String, dynamic>),
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    createdAt: DateTime.parse(json['createdAt'] as String),
    isBuiltIn: json['isBuiltIn'] as bool? ?? false,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOW RECORDER MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// Snapshot of a graph state for undo/redo.
class FlowSnapshot {
  final StageFlowGraph beforeGraph;
  final StageFlowGraph afterGraph;
  final String description;
  final DateTime timestamp;

  const FlowSnapshot({
    required this.beforeGraph,
    required this.afterGraph,
    required this.description,
    required this.timestamp,
  });
}

/// Complete result of one flow execution.
class FlowExecutionResult {
  final FlowExecutionStatus status;
  final int totalDurationMs;
  final int nodesExecuted;
  final int nodesSkipped;
  final String? errorMessage;

  const FlowExecutionResult({
    required this.status,
    required this.totalDurationMs,
    this.nodesExecuted = 0,
    this.nodesSkipped = 0,
    this.errorMessage,
  });
}

/// Complete record of one flow execution for GLI-11 game recall.
class FlowExecutionRecord {
  final String graphId;
  final DateTime startTime;
  final DateTime endTime;
  final int totalDurationMs;
  final List<NodeExecutionEntry> entries;
  final Map<String, dynamic> initialVariables;
  final Map<String, dynamic> finalVariables;
  final FlowExecutionResult result;

  const FlowExecutionRecord({
    required this.graphId,
    required this.startTime,
    required this.endTime,
    required this.totalDurationMs,
    this.entries = const [],
    this.initialVariables = const {},
    this.finalVariables = const {},
    required this.result,
  });
}

/// Single node execution entry within a flow execution record.
class NodeExecutionEntry {
  final String nodeId;
  final String stageId;
  final int startMs;
  final int durationMs;
  final bool skipped;
  final String? skipReason;

  const NodeExecutionEntry({
    required this.nodeId,
    required this.stageId,
    required this.startMs,
    required this.durationMs,
    this.skipped = false,
    this.skipReason,
  });
}

/// Resolved timing values for a node at execution time.
class ResolvedTiming {
  final int delayMs;
  final int durationMs;
  final bool canSkip;
  final bool canSlamStop;

  const ResolvedTiming({
    required this.delayMs,
    required this.durationMs,
    this.canSkip = true,
    this.canSlamStop = true,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// BUILT-IN RUNTIME VARIABLES
// ═══════════════════════════════════════════════════════════════════════════

/// All engine-provided read-only runtime variables.
class BuiltInRuntimeVariables {
  static const Map<String, RuntimeVariableDefinition> all = {
    'win_amount': RuntimeVariableDefinition(
      name: 'win_amount', type: RuntimeVarType.doubleType,
      defaultValue: 0.0, description: 'Total win in credits', readOnly: true,
    ),
    'win_ratio': RuntimeVariableDefinition(
      name: 'win_ratio', type: RuntimeVarType.doubleType,
      defaultValue: 0.0, description: 'win_amount / total_bet', readOnly: true,
    ),
    'scatter_count': RuntimeVariableDefinition(
      name: 'scatter_count', type: RuntimeVarType.intType,
      defaultValue: 0, description: 'Scatter symbols visible', readOnly: true,
    ),
    'bonus_count': RuntimeVariableDefinition(
      name: 'bonus_count', type: RuntimeVarType.intType,
      defaultValue: 0, description: 'Bonus symbols visible', readOnly: true,
    ),
    'is_free_spin': RuntimeVariableDefinition(
      name: 'is_free_spin', type: RuntimeVarType.boolType,
      defaultValue: false, description: 'Currently in free spins', readOnly: true,
    ),
    'is_cascade': RuntimeVariableDefinition(
      name: 'is_cascade', type: RuntimeVarType.boolType,
      defaultValue: false, description: 'Currently cascading', readOnly: true,
    ),
    'cascade_step': RuntimeVariableDefinition(
      name: 'cascade_step', type: RuntimeVarType.intType,
      defaultValue: 0, description: 'Current cascade depth', readOnly: true,
    ),
    'turbo_mode': RuntimeVariableDefinition(
      name: 'turbo_mode', type: RuntimeVarType.boolType,
      defaultValue: false, description: 'Turbo/quick spin active', readOnly: true,
    ),
    'autoplay_active': RuntimeVariableDefinition(
      name: 'autoplay_active', type: RuntimeVarType.boolType,
      defaultValue: false, description: 'Autoplay running', readOnly: true,
    ),
    'anticipation_active': RuntimeVariableDefinition(
      name: 'anticipation_active', type: RuntimeVarType.boolType,
      defaultValue: false, description: 'Anticipation in progress', readOnly: true,
    ),
    'reel_count': RuntimeVariableDefinition(
      name: 'reel_count', type: RuntimeVarType.intType,
      defaultValue: 5, description: 'Number of reels', readOnly: true,
    ),
    'current_reel': RuntimeVariableDefinition(
      name: 'current_reel', type: RuntimeVarType.intType,
      defaultValue: 0, description: 'Reel currently stopping', readOnly: true,
    ),
    'total_bet': RuntimeVariableDefinition(
      name: 'total_bet', type: RuntimeVarType.doubleType,
      defaultValue: 0.0, description: 'Total bet amount', readOnly: true,
    ),
    'balance': RuntimeVariableDefinition(
      name: 'balance', type: RuntimeVarType.doubleType,
      defaultValue: 0.0, description: 'Player balance', readOnly: true,
    ),
    'spin_count': RuntimeVariableDefinition(
      name: 'spin_count', type: RuntimeVarType.intType,
      defaultValue: 0, description: 'Total spins this session', readOnly: true,
    ),
    'feature_state': RuntimeVariableDefinition(
      name: 'feature_state', type: RuntimeVarType.stringType,
      defaultValue: 'none', description: 'Current feature name', readOnly: true,
    ),
    'win_tier': RuntimeVariableDefinition(
      name: 'win_tier', type: RuntimeVarType.intType,
      defaultValue: -1, description: 'Current win tier index (-1 to 6)', readOnly: true,
    ),
    'big_win_tier': RuntimeVariableDefinition(
      name: 'big_win_tier', type: RuntimeVarType.intType,
      defaultValue: 0, description: 'Big win tier (0=none, 1-5)', readOnly: true,
    ),
    'hold_spins_remaining': RuntimeVariableDefinition(
      name: 'hold_spins_remaining', type: RuntimeVarType.intType,
      defaultValue: 0, description: 'Remaining hold respins', readOnly: true,
    ),
    'jackpot_level': RuntimeVariableDefinition(
      name: 'jackpot_level', type: RuntimeVarType.stringType,
      defaultValue: 'none', description: 'Active jackpot level', readOnly: true,
    ),
  };

  BuiltInRuntimeVariables._();
}
