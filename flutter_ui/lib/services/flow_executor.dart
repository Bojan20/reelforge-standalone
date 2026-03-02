/// P-DSF Execution Engine — FlowExecutor, TimingResolver, FlowRecorder
///
/// Walks a StageFlowGraph DAG, evaluating conditions, managing parallel
/// branches, resolving timing (absolute/relative/beat-quantized), and
/// recording every execution for GLI-11 game recall.
///
/// Integration: EventRegistry.triggerStage() dispatches audio events.
library;

import 'dart:async';

import '../models/stage_flow_models.dart';
import 'condition_evaluator.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TIMING RESOLVER
// ═══════════════════════════════════════════════════════════════════════════

/// Resolves timing for nodes based on mode and context.
class TimingResolver {
  /// Resolve the actual delay/duration for a node at execution time.
  ResolvedTiming resolve(
    TimingConfig config,
    Map<String, dynamic> variables,
    Map<String, DateTime> nodeCompletionTimes,
    double? currentBpm,
  ) {
    int delayMs = config.delayMs;
    int durationMs = config.durationMs;

    switch (config.mode) {
      case TimingMode.sequential:
        // No extra delay — execute immediately after predecessor
        delayMs = config.delayMs;
        break;

      case TimingMode.absolute:
        // delayMs is from graph start — already absolute
        break;

      case TimingMode.relative:
        // Delay relative to a specific node's completion
        if (config.relativeToNodeId != null) {
          final refTime = nodeCompletionTimes[config.relativeToNodeId!];
          if (refTime != null) {
            final elapsed =
                DateTime.now().difference(refTime).inMilliseconds;
            delayMs = (config.relativeOffsetMs - elapsed).clamp(0, 999999);
          }
        }
        break;

      case TimingMode.beatQuantized:
        // Snap to nearest beat boundary
        if (currentBpm != null && currentBpm > 0 && config.beatQuantize != null) {
          final beatMs = (60000.0 / currentBpm) * config.beatQuantize!;
          if (beatMs > 0) {
            delayMs = (delayMs / beatMs).round() * beatMs.round();
            if (delayMs < 0) delayMs = 0;
          }
        }
        break;
    }

    // Enforce min/max duration
    if (config.minDurationMs > 0 && durationMs < config.minDurationMs) {
      durationMs = config.minDurationMs;
    }
    if (config.maxDurationMs > 0 && durationMs > config.maxDurationMs) {
      durationMs = config.maxDurationMs;
    }

    return ResolvedTiming(
      delayMs: delayMs,
      durationMs: durationMs,
      canSkip: config.canSkip,
      canSlamStop: config.canSlamStop,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOW RECORDER (Undo/Redo + GLI-11 Game Recall)
// ═══════════════════════════════════════════════════════════════════════════

/// Records graph mutations (undo/redo) and execution history (game recall).
class FlowRecorder {
  static const int maxUndoDepth = 50;
  static const int maxRecallDepth = 10;

  final List<FlowSnapshot> _undoStack = [];
  final List<FlowSnapshot> _redoStack = [];
  final List<FlowExecutionRecord> _gameRecall = [];

  /// Record a graph mutation for undo/redo.
  void recordMutation(
    StageFlowGraph before,
    StageFlowGraph after,
    String description,
  ) {
    _undoStack.add(FlowSnapshot(
      graph: before,
      description: description,
      timestamp: DateTime.now(),
    ));
    if (_undoStack.length > maxUndoDepth) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Undo last mutation. Returns previous graph state.
  StageFlowGraph? undo() {
    if (_undoStack.isEmpty) return null;
    final snapshot = _undoStack.removeLast();
    _redoStack.add(snapshot);
    return snapshot.graph;
  }

  /// Redo last undone mutation.
  StageFlowGraph? redo() {
    if (_redoStack.isEmpty) return null;
    final snapshot = _redoStack.removeLast();
    _undoStack.add(snapshot);
    return snapshot.graph;
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Record a completed flow execution for GLI-11 game recall.
  void recordExecution(FlowExecutionRecord record) {
    _gameRecall.add(record);
    if (_gameRecall.length > maxRecallDepth) {
      _gameRecall.removeAt(0);
    }
  }

  /// Get last N execution records.
  List<FlowExecutionRecord> getRecall({int count = 10}) {
    final start =
        (_gameRecall.length - count).clamp(0, _gameRecall.length);
    return _gameRecall.sublist(start);
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    _gameRecall.clear();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOW EXECUTOR
// ═══════════════════════════════════════════════════════════════════════════

/// Walks the StageFlowGraph DAG, executing nodes in topological order.
/// Manages parallel branches (fork/join), timing, and condition evaluation.
class FlowExecutor {
  final StageFlowGraph graph;
  final ConditionEvaluator evaluator;
  final TimingResolver timing;
  final FlowRecorder recorder;

  // Runtime state
  final Map<String, dynamic> _variables = {};
  final Set<String> _completedNodes = {};
  final Set<String> _activeNodes = {};
  final Map<String, DateTime> _nodeCompletionTimes = {};
  final List<NodeExecutionEntry> _executionEntries = [];
  bool _isRunning = false;
  bool _isPaused = false;
  bool _isCancelled = false;
  Completer<void>? _pauseCompleter;
  String? _currentNodeId;
  DateTime? _flowStartTime;
  double? currentBpm;

  // Callbacks
  void Function(String stageId, Map<String, dynamic>? context)? onTriggerStage;
  void Function(String nodeId, StageFlowNode node)? onNodeEnter;
  void Function(String nodeId, StageFlowNode node)? onNodeComplete;
  void Function(String nodeId, StageFlowNode node)? onNodeSkipped;
  void Function(FlowExecutionResult result)? onFlowComplete;
  void Function(String error)? onError;

  FlowExecutor({
    required this.graph,
    ConditionEvaluator? evaluator,
    TimingResolver? timing,
    FlowRecorder? recorder,
  })  : evaluator = evaluator ?? ConditionEvaluator(),
        timing = timing ?? TimingResolver(),
        recorder = recorder ?? FlowRecorder();

  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  String? get currentNodeId => _currentNodeId;
  Map<String, dynamic> get variables => Map.unmodifiable(_variables);

  /// Start executing the graph from the entry node.
  Future<FlowExecutionResult> execute({
    Map<String, dynamic>? initialVariables,
    bool dryRun = false,
  }) async {
    if (_isRunning) {
      return const FlowExecutionResult(
        status: FlowExecutionStatus.error,
        totalDurationMs: 0,
        errorMessage: 'Flow already running',
      );
    }

    _isRunning = true;
    _isPaused = false;
    _isCancelled = false;
    _completedNodes.clear();
    _activeNodes.clear();
    _nodeCompletionTimes.clear();
    _executionEntries.clear();
    _currentNodeId = null;

    // Initialize variables: built-ins + initial overrides
    _variables.clear();
    for (final entry in BuiltInRuntimeVariables.all.entries) {
      _variables[entry.key] = entry.value.defaultValue;
    }
    for (final entry in graph.variables.entries) {
      _variables[entry.key] = entry.value.defaultValue;
    }
    if (initialVariables != null) {
      _variables.addAll(initialVariables);
    }

    _flowStartTime = DateTime.now();
    final initialVarsCopy = Map<String, dynamic>.from(_variables);

    try {
      final entry = graph.entryNode;
      if (entry == null) {
        final result = const FlowExecutionResult(
          status: FlowExecutionStatus.error,
          totalDurationMs: 0,
          errorMessage: 'No entry node in graph',
        );
        onFlowComplete?.call(result);
        return result;
      }

      await _executeNode(entry, dryRun);

      final totalMs =
          DateTime.now().difference(_flowStartTime!).inMilliseconds;
      final skippedCount =
          _executionEntries.where((e) => e.skipped).length;

      final result = FlowExecutionResult(
        status: _isCancelled
            ? FlowExecutionStatus.cancelled
            : FlowExecutionStatus.completed,
        totalDurationMs: totalMs,
        nodesExecuted: _executionEntries.length - skippedCount,
        nodesSkipped: skippedCount,
      );

      // Record for GLI-11 game recall
      if (!dryRun) {
        recorder.recordExecution(FlowExecutionRecord(
          graphId: graph.id,
          startTime: _flowStartTime!,
          endTime: DateTime.now(),
          totalDurationMs: totalMs,
          entries: List.unmodifiable(_executionEntries),
          initialVariables: initialVarsCopy,
          finalVariables: Map.from(_variables),
          result: result,
        ));
      }

      onFlowComplete?.call(result);
      return result;
    } catch (e) {
      final totalMs =
          DateTime.now().difference(_flowStartTime!).inMilliseconds;
      final result = FlowExecutionResult(
        status: FlowExecutionStatus.error,
        totalDurationMs: totalMs,
        errorMessage: e.toString(),
      );
      onError?.call(e.toString());
      onFlowComplete?.call(result);
      return result;
    } finally {
      _isRunning = false;
      _isPaused = false;
      _currentNodeId = null;
    }
  }

  /// Pause execution (can resume).
  void pause() {
    if (!_isRunning || _isPaused) return;
    _isPaused = true;
    _pauseCompleter = Completer<void>();
  }

  /// Resume after pause.
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    _pauseCompleter?.complete();
    _pauseCompleter = null;
  }

  /// Cancel execution entirely.
  void cancel() {
    _isCancelled = true;
    if (_isPaused) resume();
  }

  /// Skip the current active node (if canSkip = true).
  bool skipCurrentNode() {
    final nodeId = _currentNodeId;
    if (nodeId == null) return false;
    final node = graph.getNode(nodeId);
    if (node == null || !node.timing.canSkip) return false;
    _completedNodes.add(nodeId);
    return true;
  }

  /// Slam stop — immediately jump to exit (if allowSlamStop = true).
  bool slamStop() {
    if (!graph.constraints.allowSlamStop) return false;
    final nodeId = _currentNodeId;
    if (nodeId != null) {
      final node = graph.getNode(nodeId);
      if (node != null && !node.timing.canSlamStop) return false;
    }
    _isCancelled = true;
    if (_isPaused) resume();
    return true;
  }

  /// Update a runtime variable during execution.
  void setVariable(String name, dynamic value) {
    final def = graph.variables[name] ?? BuiltInRuntimeVariables.all[name];
    if (def != null && def.readOnly) return;
    _variables[name] = value;
  }

  /// Get current variable value.
  dynamic getVariable(String name) => _variables[name];

  // ─── Internal execution ───────────────────────────────────────────────

  Future<void> _executeNode(StageFlowNode node, bool dryRun) async {
    if (_isCancelled) return;

    // Pause check
    if (_isPaused) {
      await _pauseCompleter?.future;
    }
    if (_isCancelled) return;

    // Already completed?
    if (_completedNodes.contains(node.id)) return;

    _currentNodeId = node.id;
    _activeNodes.add(node.id);

    final nodeStartMs =
        DateTime.now().difference(_flowStartTime!).inMilliseconds;

    // Check enterCondition
    final enterResult = evaluator.evaluate(node.enterCondition, _variables);
    if (enterResult == false) {
      // Check skipCondition
      final skipResult = evaluator.evaluate(node.skipCondition, _variables);
      if (skipResult != false) {
        // Skip this node
        onNodeSkipped?.call(node.id, node);
        _executionEntries.add(NodeExecutionEntry(
          nodeId: node.id,
          stageId: node.stageId,
          startMs: nodeStartMs,
          durationMs: 0,
          skipped: true,
          skipReason: 'enterCondition false: ${node.enterCondition}',
        ));
        _completedNodes.add(node.id);
        _activeNodes.remove(node.id);

        // Continue to successors
        await _executeSuccessors(node, dryRun);
        return;
      }
      // enterCondition false and skipCondition false → block (don't proceed)
      _activeNodes.remove(node.id);
      return;
    }

    onNodeEnter?.call(node.id, node);

    // Resolve timing
    final resolved = timing.resolve(
      node.timing,
      _variables,
      _nodeCompletionTimes,
      currentBpm,
    );

    // Apply delay
    if (resolved.delayMs > 0 && !dryRun) {
      await _delayWithPauseSupport(resolved.delayMs);
      if (_isCancelled) return;
    }

    // Execute based on node type
    switch (node.type) {
      case StageFlowNodeType.stage:
        if (!dryRun) {
          onTriggerStage?.call(node.stageId, node.properties);
        }
        // Wait for duration
        if (resolved.durationMs > 0 && !dryRun) {
          await _waitWithExitCondition(node, resolved.durationMs);
        }
        break;

      case StageFlowNodeType.gate:
        // Evaluate gate condition, then follow appropriate edge
        await _executeGate(node, dryRun);
        // Gate handles its own successor routing — skip normal successor flow
        _recordCompletion(node, nodeStartMs);
        return;

      case StageFlowNodeType.fork:
        // Execute parallel branches
        await _executeFork(node, dryRun);
        _recordCompletion(node, nodeStartMs);
        return;

      case StageFlowNodeType.join:
        // Join is a synchronization point — arrival here means branch is done
        // The fork handler manages join completion
        break;

      case StageFlowNodeType.delay:
        if (resolved.durationMs > 0 && !dryRun) {
          await _delayWithPauseSupport(resolved.durationMs);
        }
        break;

      case StageFlowNodeType.group:
        // Groups are visual-only — execute children sequentially
        break;
    }

    if (_isCancelled) return;

    _recordCompletion(node, nodeStartMs);

    // Continue to successors
    await _executeSuccessors(node, dryRun);
  }

  void _recordCompletion(StageFlowNode node, int nodeStartMs) {
    final durationMs =
        DateTime.now().difference(_flowStartTime!).inMilliseconds -
            nodeStartMs;

    _executionEntries.add(NodeExecutionEntry(
      nodeId: node.id,
      stageId: node.stageId,
      startMs: nodeStartMs,
      durationMs: durationMs,
    ));
    _completedNodes.add(node.id);
    _activeNodes.remove(node.id);
    _nodeCompletionTimes[node.id] = DateTime.now();
    onNodeComplete?.call(node.id, node);
  }

  Future<void> _executeSuccessors(StageFlowNode node, bool dryRun) async {
    final outEdges = graph.getOutEdges(node.id);
    final normalEdges =
        outEdges.where((e) => e.type == EdgeType.normal).toList();

    for (final edge in normalEdges) {
      if (_isCancelled) return;
      final targetNode = graph.getNode(edge.targetNodeId);
      if (targetNode == null) continue;

      // Apply edge transition delay
      if (edge.transitionDelayMs > 0 && !dryRun) {
        await _delayWithPauseSupport(edge.transitionDelayMs);
      }

      await _executeNode(targetNode, dryRun);
    }
  }

  Future<void> _executeGate(StageFlowNode gate, bool dryRun) async {
    final outEdges = graph.getOutEdges(gate.id);
    final condition = gate.enterCondition ?? gate.skipCondition ?? 'true';
    final result = evaluator.evaluate(condition, _variables);
    final isTrue = result ?? true;

    // Find onTrue/onFalse edges
    StageFlowEdge? targetEdge;
    if (isTrue) {
      targetEdge = outEdges.cast<StageFlowEdge?>().firstWhere(
            (e) => e!.type == EdgeType.onTrue,
            orElse: () => null,
          );
    } else {
      targetEdge = outEdges.cast<StageFlowEdge?>().firstWhere(
            (e) => e!.type == EdgeType.onFalse,
            orElse: () => null,
          );
    }

    // Fallback edge
    targetEdge ??= outEdges.cast<StageFlowEdge?>().firstWhere(
          (e) => e!.type == EdgeType.fallback,
          orElse: () => null,
        );

    if (targetEdge != null) {
      final targetNode = graph.getNode(targetEdge.targetNodeId);
      if (targetNode != null) {
        if (targetEdge.transitionDelayMs > 0 && !dryRun) {
          await _delayWithPauseSupport(targetEdge.transitionDelayMs);
        }
        await _executeNode(targetNode, dryRun);
      }
    }
  }

  Future<void> _executeFork(StageFlowNode fork, bool dryRun) async {
    final outEdges = graph.getOutEdges(fork.id);
    final parallelEdges =
        outEdges.where((e) => e.type == EdgeType.parallel).toList();

    if (parallelEdges.isEmpty) {
      // No parallel branches — treat as normal node
      await _executeSuccessors(fork, dryRun);
      return;
    }

    // Find the join node — follow each branch until we hit a join
    String? joinNodeId;
    for (final edge in parallelEdges) {
      var currentId = edge.targetNodeId;
      while (true) {
        final node = graph.getNode(currentId);
        if (node == null) break;
        if (node.type == StageFlowNodeType.join) {
          joinNodeId = node.id;
          break;
        }
        final nextEdges = graph.getOutEdges(currentId);
        if (nextEdges.isEmpty) break;
        currentId = nextEdges.first.targetNodeId;
      }
      if (joinNodeId != null) break;
    }

    // Determine join mode
    final joinNode = joinNodeId != null ? graph.getNode(joinNodeId) : null;
    final joinMode = joinNode?.joinMode ?? JoinMode.all;

    // Spawn parallel executions
    final branchFutures = <Future<void>>[];
    for (final edge in parallelEdges) {
      final targetNode = graph.getNode(edge.targetNodeId);
      if (targetNode == null) continue;
      branchFutures.add(_executeBranch(targetNode, joinNodeId, dryRun));
    }

    // Wait based on join mode
    if (joinMode == JoinMode.all) {
      await Future.wait(branchFutures);
    } else {
      // JoinMode.any — first to complete wins
      await Future.any(branchFutures);
    }

    // Execute join node and continue
    if (joinNode != null && !_isCancelled) {
      _completedNodes.add(joinNode.id);
      _nodeCompletionTimes[joinNode.id] = DateTime.now();
      onNodeComplete?.call(joinNode.id, joinNode);

      // Continue after join
      await _executeSuccessors(joinNode, dryRun);
    }
  }

  /// Execute a single branch of a fork until we hit joinNodeId or dead end.
  Future<void> _executeBranch(
    StageFlowNode startNode,
    String? joinNodeId,
    bool dryRun,
  ) async {
    var currentNode = startNode;
    while (!_isCancelled) {
      if (currentNode.id == joinNodeId) return;
      await _executeNode(currentNode, dryRun);

      // Find next node in this branch
      final outEdges = graph.getOutEdges(currentNode.id);
      final normalEdges =
          outEdges.where((e) => e.type == EdgeType.normal).toList();
      if (normalEdges.isEmpty) return;

      final nextId = normalEdges.first.targetNodeId;
      if (nextId == joinNodeId) return;

      final nextNode = graph.getNode(nextId);
      if (nextNode == null) return;
      currentNode = nextNode;
    }
  }

  /// Wait for durationMs, but check exitCondition periodically.
  Future<void> _waitWithExitCondition(
    StageFlowNode node,
    int durationMs,
  ) async {
    if (node.exitCondition == null) {
      await _delayWithPauseSupport(durationMs);
      return;
    }

    // Poll exitCondition every 16ms (~60fps)
    const pollMs = 16;
    var elapsed = 0;
    while (elapsed < durationMs && !_isCancelled) {
      await _delayWithPauseSupport(pollMs);
      elapsed += pollMs;

      final exitResult = evaluator.evaluate(node.exitCondition, _variables);
      if (exitResult == true) return;

      // Skip check
      if (_completedNodes.contains(node.id)) return;
    }
  }

  /// Delay that respects pause state.
  Future<void> _delayWithPauseSupport(int ms) async {
    if (_isCancelled) return;
    if (_isPaused) {
      await _pauseCompleter?.future;
    }
    if (_isCancelled) return;
    await Future<void>.delayed(Duration(milliseconds: ms));
  }
}
