// ============================================================================
// FluxForge Studio — Feature Builder Block Dependencies
// ============================================================================
// P13.0.3: Block dependency model and relationship types
// Defines how blocks interact with each other (enables, requires, modifies, conflicts).
// ============================================================================

/// Types of dependencies between blocks.
enum DependencyType {
  /// This block enables another block's features.
  /// Example: Free Spins enables Respins during FS mode.
  enables,

  /// This block requires another block to function.
  /// Example: Free Spins requires Scatter symbol from Symbol Set.
  requires,

  /// This block modifies another block's behavior.
  /// Example: Cascades modifies Win Presentation (adds cascade multiplier display).
  modifies,

  /// This block cannot be used with another block.
  /// Example: Respin conflicts with Hold & Win (both use respin mechanics).
  conflicts,
}

/// Extension providing display properties for [DependencyType].
extension DependencyTypeExtension on DependencyType {
  /// Human-readable display name.
  String get displayName {
    switch (this) {
      case DependencyType.enables:
        return 'Enables';
      case DependencyType.requires:
        return 'Requires';
      case DependencyType.modifies:
        return 'Modifies';
      case DependencyType.conflicts:
        return 'Conflicts';
    }
  }

  /// Short description for tooltips.
  String get description {
    switch (this) {
      case DependencyType.enables:
        return 'This block enables additional features in another block';
      case DependencyType.requires:
        return 'This block requires another block to be enabled';
      case DependencyType.modifies:
        return 'This block changes behavior of another block';
      case DependencyType.conflicts:
        return 'This block cannot be used together with another block';
    }
  }

  /// Color for dependency badge (hex value).
  int get colorValue {
    switch (this) {
      case DependencyType.enables:
        return 0xFF40FF90; // Green
      case DependencyType.requires:
        return 0xFF4A9EFF; // Blue
      case DependencyType.modifies:
        return 0xFFFFD700; // Gold
      case DependencyType.conflicts:
        return 0xFFFF4060; // Red
    }
  }

  /// Icon name for the dependency type.
  String get iconName {
    switch (this) {
      case DependencyType.enables:
        return 'arrow_forward';
      case DependencyType.requires:
        return 'link';
      case DependencyType.modifies:
        return 'edit';
      case DependencyType.conflicts:
        return 'block';
    }
  }

  /// Severity level (higher = more important to show).
  int get severity {
    switch (this) {
      case DependencyType.conflicts:
        return 4; // Most important - blocking
      case DependencyType.requires:
        return 3; // Important - must resolve
      case DependencyType.modifies:
        return 2; // Informational
      case DependencyType.enables:
        return 1; // Nice to know
    }
  }
}

/// A dependency relationship between two blocks.
class BlockDependency {
  /// The block that has this dependency (source).
  final String sourceBlockId;

  /// The block that this dependency relates to (target).
  final String targetBlockId;

  /// The type of dependency relationship.
  final DependencyType type;

  /// Optional specific requirement within the target block.
  /// Example: For "requires Symbol Set > Scatter", this would be "scatter".
  final String? targetOption;

  /// Optional condition for when this dependency applies.
  /// Format: {"optionId": expectedValue}
  final Map<String, dynamic>? condition;

  /// Human-readable description of the dependency.
  final String? description;

  /// Whether this dependency can be auto-resolved.
  final bool autoResolvable;

  /// The action to take for auto-resolution (if autoResolvable).
  final AutoResolveAction? autoResolveAction;

  const BlockDependency({
    required this.sourceBlockId,
    required this.targetBlockId,
    required this.type,
    this.targetOption,
    this.condition,
    this.description,
    this.autoResolvable = false,
    this.autoResolveAction,
  });

  /// Create an "enables" dependency.
  factory BlockDependency.enables({
    required String source,
    required String target,
    String? description,
    Map<String, dynamic>? condition,
  }) =>
      BlockDependency(
        sourceBlockId: source,
        targetBlockId: target,
        type: DependencyType.enables,
        description: description,
        condition: condition,
      );

  /// Create a "requires" dependency.
  factory BlockDependency.requires({
    required String source,
    required String target,
    String? targetOption,
    String? description,
    bool autoResolvable = true,
    AutoResolveAction? autoResolveAction,
  }) =>
      BlockDependency(
        sourceBlockId: source,
        targetBlockId: target,
        type: DependencyType.requires,
        targetOption: targetOption,
        description: description,
        autoResolvable: autoResolvable,
        autoResolveAction: autoResolveAction,
      );

  /// Create a "modifies" dependency.
  factory BlockDependency.modifies({
    required String source,
    required String target,
    String? description,
    Map<String, dynamic>? condition,
  }) =>
      BlockDependency(
        sourceBlockId: source,
        targetBlockId: target,
        type: DependencyType.modifies,
        description: description,
        condition: condition,
      );

  /// Create a "conflicts" dependency.
  factory BlockDependency.conflicts({
    required String source,
    required String target,
    String? description,
  }) =>
      BlockDependency(
        sourceBlockId: source,
        targetBlockId: target,
        type: DependencyType.conflicts,
        description: description,
        autoResolvable: false,
      );

  /// Generate a human-readable message for this dependency.
  String get message {
    if (description != null) return description!;

    final targetStr =
        targetOption != null ? '$targetBlockId ($targetOption)' : targetBlockId;

    switch (type) {
      case DependencyType.enables:
        return '$sourceBlockId enables features in $targetStr';
      case DependencyType.requires:
        return '$sourceBlockId requires $targetStr';
      case DependencyType.modifies:
        return '$sourceBlockId modifies $targetStr';
      case DependencyType.conflicts:
        return '$sourceBlockId conflicts with $targetStr';
    }
  }

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
        'sourceBlockId': sourceBlockId,
        'targetBlockId': targetBlockId,
        'type': type.name,
        if (targetOption != null) 'targetOption': targetOption,
        if (condition != null) 'condition': condition,
        if (description != null) 'description': description,
        'autoResolvable': autoResolvable,
        if (autoResolveAction != null)
          'autoResolveAction': autoResolveAction!.toJson(),
      };

  /// Deserialize from JSON.
  factory BlockDependency.fromJson(Map<String, dynamic> json) =>
      BlockDependency(
        sourceBlockId: json['sourceBlockId'] as String,
        targetBlockId: json['targetBlockId'] as String,
        type: DependencyType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => DependencyType.requires,
        ),
        targetOption: json['targetOption'] as String?,
        condition: json['condition'] as Map<String, dynamic>?,
        description: json['description'] as String?,
        autoResolvable: json['autoResolvable'] as bool? ?? false,
        autoResolveAction: json['autoResolveAction'] != null
            ? AutoResolveAction.fromJson(
                json['autoResolveAction'] as Map<String, dynamic>)
            : null,
      );

  @override
  String toString() =>
      'BlockDependency(${type.name}: $sourceBlockId -> $targetBlockId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockDependency &&
          sourceBlockId == other.sourceBlockId &&
          targetBlockId == other.targetBlockId &&
          type == other.type &&
          targetOption == other.targetOption;

  @override
  int get hashCode => Object.hash(sourceBlockId, targetBlockId, type, targetOption);
}

/// Action to take for auto-resolving a dependency.
class AutoResolveAction {
  /// Type of resolution action.
  final AutoResolveType type;

  /// Target block to modify.
  final String targetBlockId;

  /// Option to modify (for setOption type).
  final String? optionId;

  /// Value to set (for setOption type).
  final dynamic value;

  /// Human-readable description of the action.
  final String description;

  const AutoResolveAction({
    required this.type,
    required this.targetBlockId,
    this.optionId,
    this.value,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'targetBlockId': targetBlockId,
        if (optionId != null) 'optionId': optionId,
        if (value != null) 'value': value,
        'description': description,
      };

  factory AutoResolveAction.fromJson(Map<String, dynamic> json) =>
      AutoResolveAction(
        type: AutoResolveType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => AutoResolveType.enableBlock,
        ),
        targetBlockId: json['targetBlockId'] as String,
        optionId: json['optionId'] as String?,
        value: json['value'],
        description: json['description'] as String,
      );
}

/// Types of auto-resolve actions.
enum AutoResolveType {
  /// Enable the target block.
  enableBlock,

  /// Disable the target block.
  disableBlock,

  /// Set a specific option on the target block.
  setOption,
}

// ============================================================================
// Dependency Graph for Visualization
// ============================================================================

/// A node in the dependency graph (represents a block).
class DependencyGraphNode {
  final String blockId;
  final String displayName;
  final bool isEnabled;
  final bool hasErrors;
  final List<String> incomingEdges; // Blocks that point TO this node
  final List<String> outgoingEdges; // Blocks this node points TO

  const DependencyGraphNode({
    required this.blockId,
    required this.displayName,
    required this.isEnabled,
    this.hasErrors = false,
    this.incomingEdges = const [],
    this.outgoingEdges = const [],
  });

  DependencyGraphNode copyWith({
    String? blockId,
    String? displayName,
    bool? isEnabled,
    bool? hasErrors,
    List<String>? incomingEdges,
    List<String>? outgoingEdges,
  }) =>
      DependencyGraphNode(
        blockId: blockId ?? this.blockId,
        displayName: displayName ?? this.displayName,
        isEnabled: isEnabled ?? this.isEnabled,
        hasErrors: hasErrors ?? this.hasErrors,
        incomingEdges: incomingEdges ?? this.incomingEdges,
        outgoingEdges: outgoingEdges ?? this.outgoingEdges,
      );
}

/// An edge in the dependency graph (represents a dependency).
class DependencyGraphEdge {
  final String sourceId;
  final String targetId;
  final DependencyType type;
  final bool isSatisfied;
  final String? errorMessage;

  const DependencyGraphEdge({
    required this.sourceId,
    required this.targetId,
    required this.type,
    this.isSatisfied = true,
    this.errorMessage,
  });
}

/// The complete dependency graph for visualization.
class DependencyGraph {
  final List<DependencyGraphNode> nodes;
  final List<DependencyGraphEdge> edges;

  const DependencyGraph({
    required this.nodes,
    required this.edges,
  });

  /// Get all edges for a specific block.
  List<DependencyGraphEdge> getEdgesFor(String blockId) => edges
      .where((e) => e.sourceId == blockId || e.targetId == blockId)
      .toList();

  /// Get incoming edges (dependencies ON this block).
  List<DependencyGraphEdge> getIncomingEdges(String blockId) =>
      edges.where((e) => e.targetId == blockId).toList();

  /// Get outgoing edges (dependencies FROM this block).
  List<DependencyGraphEdge> getOutgoingEdges(String blockId) =>
      edges.where((e) => e.sourceId == blockId).toList();

  /// Check if there are any unsatisfied dependencies.
  bool get hasErrors => edges.any((e) => !e.isSatisfied);

  /// Get all edges with errors.
  List<DependencyGraphEdge> get errorEdges =>
      edges.where((e) => !e.isSatisfied).toList();
}

// ============================================================================
// Dependency Resolution Result
// ============================================================================

/// Result of dependency resolution.
class DependencyResolutionResult {
  /// Whether all dependencies are satisfied.
  final bool isValid;

  /// List of errors (blocking issues).
  final List<DependencyError> errors;

  /// List of warnings (non-blocking issues).
  final List<DependencyWarning> warnings;

  /// List of suggested auto-fix actions.
  final List<AutoResolveAction> suggestedFixes;

  /// The dependency graph for visualization.
  final DependencyGraph graph;

  const DependencyResolutionResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
    this.suggestedFixes = const [],
    required this.graph,
  });

  /// Create a valid result with no issues.
  factory DependencyResolutionResult.valid(DependencyGraph graph) =>
      DependencyResolutionResult(isValid: true, graph: graph);

  /// Check if there are any issues (errors or warnings).
  bool get hasIssues => errors.isNotEmpty || warnings.isNotEmpty;
}

/// A blocking dependency error.
class DependencyError {
  final BlockDependency dependency;
  final String message;
  final AutoResolveAction? suggestedFix;

  const DependencyError({
    required this.dependency,
    required this.message,
    this.suggestedFix,
  });
}

/// A non-blocking dependency warning.
class DependencyWarning {
  final BlockDependency dependency;
  final String message;

  const DependencyWarning({
    required this.dependency,
    required this.message,
  });
}
