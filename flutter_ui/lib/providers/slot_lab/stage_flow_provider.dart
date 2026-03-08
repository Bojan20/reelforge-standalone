/// P-DSF Stage Flow Provider — Flutter ChangeNotifier bridge for FlowExecutor
///
/// Manages the active StageFlowGraph, presets, undo/redo, dry-run mode,
/// and bridges FlowExecutor events to UI state.
///
/// GetIt singleton — registered in service_locator.dart.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/stage_flow_models.dart';
import '../../services/condition_evaluator.dart';
import '../../services/flow_executor.dart';

/// Provider that manages stage flow graph editing and execution.
class StageFlowProvider extends ChangeNotifier {
  // ─── Core state ──────────────────────────────────────────────────────

  StageFlowGraph? _graph;
  FlowExecutor? _executor;
  final FlowRecorder _recorder = FlowRecorder();
  final ConditionEvaluator _evaluator = ConditionEvaluator();
  final TimingResolver _timingResolver = TimingResolver();

  // ─── Presets ─────────────────────────────────────────────────────────

  final List<FlowPreset> _presets = [];
  String? _activePresetId;

  // ─── Editor state ────────────────────────────────────────────────────

  String? _selectedNodeId;
  final Set<String> _selectedNodeIds = {};
  List<FlowValidationError> _validationErrors = [];

  // ─── Execution state ─────────────────────────────────────────────────

  bool _isDryRunning = false;
  bool _isDryRunPaused = false;
  String? _activeNodeId;
  final Set<String> _completedNodeIds = {};
  final Set<String> _skippedNodeIds = {};
  FlowExecutionResult? _lastResult;
  Map<String, dynamic> _dryRunVariables = {};

  // ─── Callbacks ───────────────────────────────────────────────────────

  void Function(String stageId, Map<String, dynamic>? context)?
      onTriggerStage;
  void Function(FlowExecutionResult result)? onFlowComplete;

  // ═════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═════════════════════════════════════════════════════════════════════

  StageFlowGraph? get graph => _graph;
  bool get hasGraph => _graph != null;
  String? get selectedNodeId => _selectedNodeId;
  Set<String> get selectedNodeIds => Set.unmodifiable(_selectedNodeIds);
  List<FlowValidationError> get validationErrors =>
      List.unmodifiable(_validationErrors);
  bool get hasErrors =>
      _validationErrors.any((e) => e.severity == FlowValidationSeverity.error);
  bool get hasWarnings =>
      _validationErrors.any((e) => e.severity == FlowValidationSeverity.warning);

  List<FlowPreset> get presets => List.unmodifiable(_presets);
  List<FlowPreset> get builtInPresets =>
      _presets.where((p) => p.isBuiltIn).toList();
  List<FlowPreset> get userPresets =>
      _presets.where((p) => !p.isBuiltIn).toList();
  String? get activePresetId => _activePresetId;

  bool get isDryRunning => _isDryRunning;
  bool get isDryRunPaused => _isDryRunPaused;
  String? get activeNodeId => _activeNodeId;
  Set<String> get completedNodeIds => Set.unmodifiable(_completedNodeIds);
  Set<String> get skippedNodeIds => Set.unmodifiable(_skippedNodeIds);
  FlowExecutionResult? get lastResult => _lastResult;
  Map<String, dynamic> get dryRunVariables =>
      Map.unmodifiable(_dryRunVariables);

  bool get canUndo => _recorder.canUndo;
  bool get canRedo => _recorder.canRedo;
  List<FlowExecutionRecord> get gameRecall => _recorder.getRecall();

  StageFlowNode? get selectedNode {
    if (_selectedNodeId == null || _graph == null) return null;
    return _graph!.getNode(_selectedNodeId!);
  }

  // ═════════════════════════════════════════════════════════════════════
  // GRAPH MANAGEMENT
  // ═════════════════════════════════════════════════════════════════════

  /// Load a graph for editing.
  void loadGraph(StageFlowGraph graph) {
    // Cancel any active execution before loading a new graph
    if (_isDryRunning) {
      cancelExecution();
    }
    _graph = graph;
    _selectedNodeId = null;
    _selectedNodeIds.clear();
    _validationErrors = graph.validate();
    notifyListeners();
  }

  /// Create a new empty graph.
  void createNewGraph(String name, {FlowConstraints? constraints}) {
    final now = DateTime.now();
    _graph = StageFlowGraph(
      id: 'flow_${now.millisecondsSinceEpoch}',
      name: name,
      constraints: constraints ?? const FlowConstraints(),
      createdAt: now,
      modifiedAt: now,
    );
    _selectedNodeId = null;
    _selectedNodeIds.clear();
    _validationErrors = [];
    notifyListeners();
  }

  /// Load graph from JSON.
  void loadGraphFromJson(Map<String, dynamic> json) {
    loadGraph(StageFlowGraph.fromJson(json));
  }

  /// Export graph as JSON string.
  String? exportGraphJson() {
    if (_graph == null) return null;
    return jsonEncode(_graph!.toJson());
  }

  // ═════════════════════════════════════════════════════════════════════
  // NODE OPERATIONS
  // ═════════════════════════════════════════════════════════════════════

  void addNode(StageFlowNode node) {
    if (_graph == null) return;
    _recordAndApply(
      _graph!.addNode(node),
      'Add ${node.stageId}',
    );
  }

  void removeNode(String nodeId) {
    if (_graph == null) return;
    final node = _graph!.getNode(nodeId);
    if (node == null || node.locked) return;
    _recordAndApply(
      _graph!.removeNode(nodeId),
      'Remove ${node.stageId}',
    );
    _selectedNodeIds.remove(nodeId);
    if (_selectedNodeId == nodeId) {
      _selectedNodeId =
          _selectedNodeIds.isNotEmpty ? _selectedNodeIds.first : null;
    }
  }

  void updateNode(String nodeId, StageFlowNode updated) {
    if (_graph == null) return;
    _recordAndApply(
      _graph!.updateNode(nodeId, updated),
      'Update ${updated.stageId}',
    );
  }

  void moveNode(String nodeId, double x, double y) {
    if (_graph == null) return;
    // Move doesn't record undo (too frequent during drag)
    _graph = _graph!.moveNode(nodeId, x, y);
    notifyListeners();
  }

  void reorderNode(String nodeId, {String? afterNodeId, String? beforeNodeId}) {
    if (_graph == null) return;
    final node = _graph!.getNode(nodeId);
    if (node == null) return;
    _recordAndApply(
      _graph!.reorderNode(nodeId, afterNodeId: afterNodeId, beforeNodeId: beforeNodeId),
      'Reorder ${node.stageId}',
    );
  }

  void swapNodes(String nodeIdA, String nodeIdB) {
    if (_graph == null) return;
    _recordAndApply(
      _graph!.swapNodes(nodeIdA, nodeIdB),
      'Swap nodes',
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // EDGE OPERATIONS
  // ═════════════════════════════════════════════════════════════════════

  void addEdge(StageFlowEdge edge) {
    if (_graph == null) return;
    final newGraph = _graph!.addEdge(edge);
    // Check for cycles
    if (newGraph.hasCycle()) return;
    _recordAndApply(
      newGraph,
      'Connect ${edge.sourceNodeId} → ${edge.targetNodeId}',
    );
  }

  void removeEdge(String edgeId) {
    if (_graph == null) return;
    _recordAndApply(
      _graph!.removeEdge(edgeId),
      'Remove edge',
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // SELECTION
  // ═════════════════════════════════════════════════════════════════════

  void selectNode(String? nodeId) {
    _selectedNodeId = nodeId;
    _selectedNodeIds.clear();
    if (nodeId != null) _selectedNodeIds.add(nodeId);
    notifyListeners();
  }

  void toggleNodeSelection(String nodeId) {
    if (_selectedNodeIds.contains(nodeId)) {
      _selectedNodeIds.remove(nodeId);
      if (_selectedNodeId == nodeId) {
        _selectedNodeId =
            _selectedNodeIds.isNotEmpty ? _selectedNodeIds.first : null;
      }
    } else {
      _selectedNodeIds.add(nodeId);
      _selectedNodeId = nodeId;
    }
    notifyListeners();
  }

  void selectNodes(Set<String> nodeIds) {
    _selectedNodeIds.clear();
    _selectedNodeIds.addAll(nodeIds);
    _selectedNodeId = nodeIds.isNotEmpty ? nodeIds.first : null;
    notifyListeners();
  }

  void clearSelection() {
    _selectedNodeId = null;
    _selectedNodeIds.clear();
    notifyListeners();
  }

  // ═════════════════════════════════════════════════════════════════════
  // UNDO / REDO
  // ═════════════════════════════════════════════════════════════════════

  void undo() {
    final previous = _recorder.undo();
    if (previous != null) {
      _graph = previous;
      _validationErrors = _graph!.validate();
      _invalidateSelectionForGraph();
      notifyListeners();
    }
  }

  void redo() {
    final next = _recorder.redo();
    if (next != null) {
      _graph = next;
      _validationErrors = _graph!.validate();
      _invalidateSelectionForGraph();
      notifyListeners();
    }
  }

  /// Remove selected nodes that no longer exist in the current graph.
  void _invalidateSelectionForGraph() {
    if (_graph == null) return;
    _selectedNodeIds.removeWhere((id) => _graph!.getNode(id) == null);
    if (_selectedNodeId != null && _graph!.getNode(_selectedNodeId!) == null) {
      _selectedNodeId =
          _selectedNodeIds.isNotEmpty ? _selectedNodeIds.first : null;
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  // VALIDATION
  // ═════════════════════════════════════════════════════════════════════

  List<FlowValidationError> revalidate() {
    if (_graph == null) return [];
    _validationErrors = _graph!.validate();
    notifyListeners();
    return _validationErrors;
  }

  /// Validate a condition expression against available variables.
  List<String> validateCondition(String expression) {
    if (_graph == null) return [];
    final allVars = <String, RuntimeVariableDefinition>{
      ...BuiltInRuntimeVariables.all,
      ..._graph!.variables,
    };
    return _evaluator.validate(expression, allVars);
  }

  // ═════════════════════════════════════════════════════════════════════
  // PRESET MANAGEMENT
  // ═════════════════════════════════════════════════════════════════════

  void addPresets(List<FlowPreset> presets) {
    _presets.addAll(presets);
    notifyListeners();
  }

  void loadPreset(String presetId) {
    final preset =
        _presets.cast<FlowPreset?>().firstWhere(
              (p) => p!.id == presetId,
              orElse: () => null,
            );
    if (preset == null) return;
    _activePresetId = presetId;
    loadGraph(preset.graph);
  }

  void saveAsPreset(String name, {FlowPresetCategory? category, String? description}) {
    if (_graph == null) return;
    final preset = FlowPreset(
      id: 'preset_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description,
      category: category ?? FlowPresetCategory.custom,
      graph: _graph!,
      createdAt: DateTime.now(),
    );
    _presets.add(preset);
    _activePresetId = preset.id;
    notifyListeners();
  }

  void deletePreset(String presetId) {
    _presets.removeWhere((p) => p.id == presetId && !p.isBuiltIn);
    if (_activePresetId == presetId) _activePresetId = null;
    notifyListeners();
  }

  // ═════════════════════════════════════════════════════════════════════
  // DRY-RUN EXECUTION
  // ═════════════════════════════════════════════════════════════════════

  /// Start a dry-run simulation of the current graph.
  Future<FlowExecutionResult?> startDryRun({
    Map<String, dynamic>? variables,
  }) async {
    if (_graph == null || _isDryRunning) return null;

    _isDryRunning = true;
    _isDryRunPaused = false;
    _activeNodeId = null;
    _completedNodeIds.clear();
    _skippedNodeIds.clear();
    _dryRunVariables = variables ?? {};
    _lastResult = null;
    notifyListeners();

    _executor = FlowExecutor(
      graph: _graph!,
      evaluator: _evaluator,
      timing: _timingResolver,
      recorder: _recorder,
    );

    _executor!.onNodeEnter = (nodeId, node) {
      _activeNodeId = nodeId;
      notifyListeners();
    };

    _executor!.onNodeComplete = (nodeId, node) {
      _completedNodeIds.add(nodeId);
      notifyListeners();
    };

    _executor!.onNodeSkipped = (nodeId, node) {
      _skippedNodeIds.add(nodeId);
      notifyListeners();
    };

    _executor!.onTriggerStage = (stageId, context) {
      // In dry-run, don't trigger actual audio — but still fire callback for UI
      onTriggerStage?.call(stageId, context);
    };

    final result = await _executor!.execute(
      initialVariables: _dryRunVariables,
      dryRun: true,
    );

    _isDryRunning = false;
    _isDryRunPaused = false;
    _activeNodeId = null;
    _lastResult = result;
    _executor = null;
    notifyListeners();

    return result;
  }

  /// Start real execution (dispatches actual audio events).
  Future<FlowExecutionResult?> startExecution({
    Map<String, dynamic>? variables,
  }) async {
    if (_graph == null || _isDryRunning) return null;

    _isDryRunning = true;
    _isDryRunPaused = false;
    _activeNodeId = null;
    _completedNodeIds.clear();
    _skippedNodeIds.clear();
    _lastResult = null;
    notifyListeners();

    _executor = FlowExecutor(
      graph: _graph!,
      evaluator: _evaluator,
      timing: _timingResolver,
      recorder: _recorder,
    );

    _executor!.onNodeEnter = (nodeId, node) {
      _activeNodeId = nodeId;
      notifyListeners();
    };

    _executor!.onNodeComplete = (nodeId, node) {
      _completedNodeIds.add(nodeId);
      notifyListeners();
    };

    _executor!.onNodeSkipped = (nodeId, node) {
      _skippedNodeIds.add(nodeId);
      notifyListeners();
    };

    _executor!.onTriggerStage = onTriggerStage;

    final result = await _executor!.execute(
      initialVariables: variables,
    );

    _isDryRunning = false;
    _activeNodeId = null;
    _lastResult = result;
    _executor = null;
    onFlowComplete?.call(result);
    notifyListeners();

    return result;
  }

  void pauseDryRun() {
    _executor?.pause();
    _isDryRunPaused = true;
    notifyListeners();
  }

  void resumeDryRun() {
    _executor?.resume();
    _isDryRunPaused = false;
    notifyListeners();
  }

  void cancelExecution() {
    _executor?.cancel();
    _isDryRunning = false;
    _isDryRunPaused = false;
    _activeNodeId = null;
    notifyListeners();
  }

  bool skipCurrentNode() {
    return _executor?.skipCurrentNode() ?? false;
  }

  bool slamStop() {
    return _executor?.slamStop() ?? false;
  }

  /// Update a variable during execution.
  void setDryRunVariable(String name, dynamic value) {
    _dryRunVariables[name] = value;
    _executor?.setVariable(name, value);
    notifyListeners();
  }

  // ═════════════════════════════════════════════════════════════════════
  // INTERNAL
  // ═════════════════════════════════════════════════════════════════════

  void _recordAndApply(StageFlowGraph newGraph, String description) {
    if (_graph == null) return;
    _recorder.recordMutation(_graph!, newGraph, description);
    _graph = newGraph;
    _validationErrors = _graph!.validate();
    notifyListeners();
  }

  @override
  void dispose() {
    _executor?.cancel();
    _recorder.clear();
    onTriggerStage = null;
    onFlowComplete = null;
    super.dispose();
  }
}
