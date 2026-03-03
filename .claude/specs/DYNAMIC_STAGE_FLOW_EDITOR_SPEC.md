# DYNAMIC STAGE FLOW EDITOR — Ultimate Specification

## P-DSF: Dynamic Stage Flow Editor & Runtime Orchestration Engine

**Version:** 1.0.0
**Status:** SPECIFICATION COMPLETE
**Target:** ~3,200 LOC across 8 files
**Priority:** P-DSF (post P14, pre P-FMC integration)

---

## 1. PROBLEM STATEMENT

### Current State — Hardcoded Sequential Flow

SlotLab's spin lifecycle is controlled by a chain of `Future.delayed()` calls in
`slot_preview_widget.dart`. The order is baked into code:

```
SPIN_START → REEL_SPIN_LOOP → [ANTICIPATION] → REEL_STOP_0..4 → EVALUATE_WINS
→ WIN_PRESENT → WIN_LINE_SHOW → [BIG_WIN_TIER] → ROLLUP → WIN_COLLECT → SPIN_END
```

**Problems:**
1. **No runtime reordering** — Moving WIN_SYMBOL_HIGHLIGHT before/after ROLLUP requires code changes
2. **No conditional branching** — Can't express "if scatter_count >= 3, skip to FS_TRIGGER"
3. **No parallel execution** — WIN_LINE_SHOW and ROLLUP_START can't run simultaneously
4. **No timing control** — All delays are `const int` values, not user-adjustable
5. **No visual editor** — Sound designers must ask developers for any flow change
6. **No dry-run** — Can't preview flow without spinning the slot machine
7. **No undo** — Changes are permanent until manually reverted
8. **No presets** — Every game starts from scratch

### Industry Standard

**IGT:** XML-based game flow definitions with branching states, each state has entry/exit audio hooks.
**NetEnt:** Event graph with parallel nodes for visual + audio synchronization.
**Pragmatic Play:** Layered system — core engine locked, features composable, audio mapped per state.
**FMOD:** Switch Containers with transition rules, quantized beat sync, parameter-driven branching.
**Wwise:** State Groups + Music Switch Containers + RTPC for real-time parameter control.
**GLI-11:** 10-game recall requirement — every state transition must be deterministic and reproducible.
**UKGC:** 2.5s minimum spin cycle, no slam-stop during feature, responsible gaming interrupts.

---

## 2. ARCHITECTURE — Three-Layer Design

```
┌─────────────────────────────────────────────────────────────┐
│  LAYER 3: VISUAL EDITOR (Flutter UI)                        │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Drag & drop node canvas with connection wires        │  │
│  │  Property inspector panel                             │  │
│  │  Dry-run timeline preview                             │  │
│  │  Preset browser & save/load                           │  │
│  └───────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  LAYER 2: EXECUTION ENGINE (Dart runtime)                   │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  FlowExecutor — walks graph, evaluates conditions     │  │
│  │  ConditionEvaluator — expression parser               │  │
│  │  TimingResolver — absolute/relative/beat-quantized    │  │
│  │  ParallelScheduler — concurrent branch execution      │  │
│  │  FlowRecorder — undo/redo stack + 10-game recall      │  │
│  └───────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  LAYER 1: DATA MODEL (Immutable, JSON-serializable)         │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  StageFlowGraph — directed graph of StageFlowNodes    │  │
│  │  StageFlowNode — stage + timing + conditions          │  │
│  │  StageFlowEdge — connection with condition/delay      │  │
│  │  FlowPreset — named snapshot of complete graph        │  │
│  │  RuntimeVariable — dynamic value during execution     │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Integration Points

```
StageFlowGraph ←→ StageConfigurationService (130+ registered stages)
FlowExecutor   ←→ EventRegistry.triggerStage() (audio dispatch)
FlowExecutor   ←→ GameFlowProvider (FSM state transitions)
FlowExecutor   ←→ SlotPreviewWidget (visual sync callbacks)
FlowPreset     ←→ SlotLabTemplate.behaviorTreeConfig (persistence)
Visual Editor  ←→ StageDependencyEditor (existing UI, to be replaced)
```

---

## 3. LAYER 1 — DATA MODEL

### 3.1 StageFlowNode

```dart
/// A single node in the stage flow graph.
/// Immutable, JSON-serializable, uniquely identified.
class StageFlowNode {
  final String id;                    // UUID v4
  final String stageId;              // e.g. 'WIN_PRESENT', 'ROLLUP_START'
  final StageFlowNodeType type;      // stage | gate | fork | join | delay | group
  final FlowLayer layer;             // engineCore | featureComposer | audioMapping
  final bool locked;                 // engineCore nodes = true (non-deletable)

  // — Timing ———————————————————————————————————————————————
  final TimingConfig timing;

  // — Conditions ———————————————————————————————————————————
  final String? enterCondition;      // Expression: "win_amount > 0"
  final String? skipCondition;       // Expression: "turbo_mode == true"
  final String? exitCondition;       // Expression: "rollup_complete == true"

  // — Visual position (for editor canvas) ——————————————————
  final double x;
  final double y;

  // — Metadata —————————————————————————————————————————————
  final Map<String, dynamic> properties;  // Stage-specific overrides
  final String? description;
  final String? color;               // Hex override, null = use category default

  const StageFlowNode({...});
  StageFlowNode copyWith({...});
  Map<String, dynamic> toJson();
  factory StageFlowNode.fromJson(Map<String, dynamic> json);
}
```

### 3.2 StageFlowNodeType

```dart
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

  /// Group — contains sub-nodes (for visual organization, collapsible)
  group,
}
```

### 3.3 FlowLayer

```dart
/// Matches the Trostepeni Layer System
enum FlowLayer {
  /// Layer 1: Engine Core — SPIN_START through SPIN_END
  /// LOCKED — cannot be deleted or reordered relative to other engineCore nodes
  engineCore,

  /// Layer 2: Feature Composer — cascade, free spins, hold & win, etc.
  /// Dynamic — enabled/disabled per game config
  featureComposer,

  /// Layer 3: Audio Mapping — user-defined presentation stages
  /// Fully editable — user can add, remove, reorder freely
  audioMapping,
}
```

### 3.4 TimingConfig

```dart
/// Timing configuration for a node.
/// Supports absolute, relative, and beat-quantized timing.
class TimingConfig {
  final TimingMode mode;
  final int delayMs;                 // Absolute: fixed delay before execution
  final int durationMs;              // How long this stage runs (0 = instant)
  final String? relativeToNodeId;    // Relative: delay after this node completes
  final int relativeOffsetMs;        // Relative: offset from reference node
  final double? beatQuantize;        // Beat-quantized: snap to nearest beat (0.25 = 16th note)
  final int minDurationMs;           // Minimum duration (regulatory: UKGC 2500ms for full cycle)
  final int maxDurationMs;           // Maximum duration (0 = no limit)
  final bool canSkip;                // If true, user tap/click can skip this stage
  final bool canSlamStop;            // If false, cannot be interrupted (UKGC feature rule)

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
      : this(mode: TimingMode.relative, relativeToNodeId: nodeId, relativeOffsetMs: offsetMs);

  Map<String, dynamic> toJson();
  factory TimingConfig.fromJson(Map<String, dynamic> json);
}

enum TimingMode {
  /// Execute immediately after previous node completes
  sequential,

  /// Execute after fixed delayMs from graph start (absolute timeline position)
  absolute,

  /// Execute relative to another node's completion
  relative,

  /// Snap execution to nearest musical beat boundary
  beatQuantized,
}
```

### 3.5 StageFlowEdge

```dart
/// Directed connection between two nodes.
class StageFlowEdge {
  final String id;
  final String sourceNodeId;
  final String targetNodeId;
  final String? condition;           // Expression for conditional routing (gate nodes)
  final int transitionDelayMs;       // Additional delay on this specific edge
  final EdgeType type;               // normal | onTrue | onFalse | parallel | fallback

  const StageFlowEdge({...});
  Map<String, dynamic> toJson();
  factory StageFlowEdge.fromJson(Map<String, dynamic> json);
}

enum EdgeType {
  normal,        // Default sequential connection
  onTrue,        // Gate node → condition evaluates to true
  onFalse,       // Gate node → condition evaluates to false
  parallel,      // Fork node → parallel branch
  fallback,      // Executed only if primary edge's condition fails
}
```

### 3.6 StageFlowGraph

```dart
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

  const StageFlowGraph({...});

  // — Graph operations (return new instance) ———————————————
  StageFlowGraph addNode(StageFlowNode node);
  StageFlowGraph removeNode(String nodeId);       // Fails if node.locked
  StageFlowGraph updateNode(String nodeId, StageFlowNode updated);
  StageFlowGraph moveNode(String nodeId, double x, double y);
  StageFlowGraph addEdge(StageFlowEdge edge);
  StageFlowGraph removeEdge(String edgeId);

  // — Reordering (the core feature) ———————————————————————
  StageFlowGraph reorderNode(String nodeId, {String? afterNodeId, String? beforeNodeId});
  StageFlowGraph swapNodes(String nodeIdA, String nodeIdB);
  StageFlowGraph moveNodeToParallelBranch(String nodeId, String forkId, int branchIndex);

  // — Queries —————————————————————————————————————————————
  StageFlowNode? getNode(String id);
  List<StageFlowNode> getSuccessors(String nodeId);
  List<StageFlowNode> getPredecessors(String nodeId);
  List<StageFlowEdge> getOutEdges(String nodeId);
  List<StageFlowEdge> getInEdges(String nodeId);
  List<List<StageFlowNode>> getParallelBranches(String forkId);
  bool hasCycle();                   // Validation — must be DAG
  List<StageFlowNode> topologicalSort();
  StageFlowNode? get entryNode;     // First node (SPIN_START for base game)
  StageFlowNode? get exitNode;      // Last node (SPIN_END for base game)

  // — Subgraph extraction —————————————————————————————————
  StageFlowGraph extractSubgraph(Set<String> nodeIds);
  StageFlowGraph mergeSubgraph(StageFlowGraph sub, String attachAfterNodeId);

  // — Validation ——————————————————————————————————————————
  List<FlowValidationError> validate();

  // — Serialization ———————————————————————————————————————
  Map<String, dynamic> toJson();
  factory StageFlowGraph.fromJson(Map<String, dynamic> json);
}
```

### 3.7 Runtime Variables

```dart
/// Definition of a variable available during flow execution.
class RuntimeVariableDefinition {
  final String name;                 // e.g. 'win_amount', 'scatter_count'
  final RuntimeVarType type;         // int | double | bool | string
  final dynamic defaultValue;
  final String? description;
  final bool readOnly;               // Engine-provided variables = true

  const RuntimeVariableDefinition({...});
}

enum RuntimeVarType { intType, doubleType, boolType, stringType }
```

**Built-in Runtime Variables** (read-only, engine-provided):

| Variable | Type | Source | Description |
|----------|------|--------|-------------|
| `win_amount` | double | SlotPreviewWidget._winAmount | Total win in credits |
| `win_ratio` | double | computed | win_amount / total_bet |
| `scatter_count` | int | _scatterReels.length | Scatter symbols visible |
| `bonus_count` | int | _bonusCount | Bonus symbols visible |
| `is_free_spin` | bool | GameFlowProvider | Currently in free spins |
| `is_cascade` | bool | GameFlowProvider | Currently cascading |
| `cascade_step` | int | _cascadeStep | Current cascade depth |
| `turbo_mode` | bool | _isTurboMode | Turbo/quick spin active |
| `autoplay_active` | bool | _isAutoplaying | Autoplay running |
| `anticipation_active` | bool | _isAnticipating | Anticipation in progress |
| `reel_count` | int | config.reelCount | Number of reels |
| `current_reel` | int | _currentStopReel | Reel currently stopping |
| `total_bet` | double | _currentBet * _linesCount | Total bet amount |
| `balance` | double | _balance | Player balance |
| `spin_count` | int | _totalSpins | Total spins this session |
| `feature_state` | string | GameFlowProvider | Current feature name or 'none' |
| `win_tier` | int | computed | Current win tier index (-1 to 6) |
| `big_win_tier` | int | computed | Big win tier (0=none, 1-5) |
| `hold_spins_remaining` | int | HoldAndWinState | Remaining hold respins |
| `jackpot_level` | string | 'none'\|'mini'\|'minor'\|'major'\|'grand' | Active jackpot |

**User-defined Variables** (read-write):

Sound designers can define custom variables for flow control:
```yaml
variables:
  custom_tension_level:
    type: int
    default: 0
    description: "Manual tension override for testing"
  skip_rollup:
    type: bool
    default: false
    description: "Skip rollup animation for debug"
```

### 3.8 Flow Constraints

```dart
/// Regulatory and design constraints applied to the graph.
class FlowConstraints {
  final int minSpinCycleMs;          // UKGC: 2500ms minimum
  final bool allowSlamStop;          // UKGC: false during features
  final int maxRecallDepth;          // GLI-11: 10 game recall
  final int maxParallelBranches;     // Performance limit: 8
  final int maxGraphNodes;           // Sanity limit: 200
  final int maxNestingDepth;         // Groups/subgraphs: 4
  final bool requireDeterministic;   // GLI-11: every path must be reproducible

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
}
```

### 3.9 FlowPreset

```dart
/// Named snapshot of a complete flow graph.
/// Stored in SlotLabTemplate.behaviorTreeConfig.
class FlowPreset {
  final String id;
  final String name;
  final String? description;
  final FlowPresetCategory category;
  final StageFlowGraph graph;
  final Map<String, dynamic> metadata;   // version, author, game type
  final DateTime createdAt;
  final bool isBuiltIn;                  // Factory presets = true

  const FlowPreset({...});
  Map<String, dynamic> toJson();
  factory FlowPreset.fromJson(Map<String, dynamic> json);
}

enum FlowPresetCategory {
  baseGame,           // Standard spin cycle
  freeSpins,          // Free spin variant
  holdAndWin,         // Hold & Win variant
  cascading,          // Tumble/cascade variant
  bonusGame,          // Pick bonus variant
  jackpotPresentation,// Jackpot reveal flow
  custom,             // User-created
}
```

### 3.10 Validation Errors

```dart
class FlowValidationError {
  final FlowValidationSeverity severity;   // error | warning | info
  final String nodeId;                      // Which node has the problem
  final String code;                        // Machine-readable error code
  final String message;                     // Human-readable description

  const FlowValidationError({...});
}

enum FlowValidationSeverity { error, warning, info }
```

**Validation rules:**
| Code | Severity | Description |
|------|----------|-------------|
| `CYCLE_DETECTED` | error | Graph contains a cycle — must be DAG |
| `ORPHAN_NODE` | error | Node has no incoming or outgoing edges |
| `MISSING_ENTRY` | error | No entry node (SPIN_START or equivalent) |
| `MISSING_EXIT` | error | No exit node (SPIN_END or equivalent) |
| `LOCKED_NODE_DELETED` | error | Attempt to delete an engineCore node |
| `LOCKED_NODE_REORDERED` | error | Attempt to move engineCore node past another engineCore node |
| `GATE_MISSING_TRUE` | error | Gate node has no onTrue edge |
| `GATE_MISSING_FALSE` | warning | Gate node has no onFalse edge (defaults to skip) |
| `FORK_SINGLE_BRANCH` | warning | Fork with only one branch (unnecessary) |
| `JOIN_MISSING_BRANCHES` | error | Join doesn't match all fork branches |
| `INVALID_EXPRESSION` | error | Condition expression has syntax errors |
| `UNKNOWN_VARIABLE` | warning | Expression references undefined variable |
| `TIMING_BELOW_MIN` | warning | Total cycle time < minSpinCycleMs |
| `TIMING_EXCEEDS_MAX` | warning | Node duration exceeds maxDurationMs |
| `UNREACHABLE_NODE` | warning | Node cannot be reached from entry |
| `PARALLEL_LIMIT` | error | Too many parallel branches (> maxParallelBranches) |
| `NESTING_LIMIT` | error | Group nesting exceeds maxNestingDepth |

---

## 4. LAYER 2 — EXECUTION ENGINE

### 4.1 ConditionEvaluator

```dart
/// Evaluates simple boolean expressions against runtime variables.
///
/// Supported operators:
///   Comparison: ==, !=, >, <, >=, <=
///   Logical:    &&, ||, !
///   Arithmetic: +, -, *, / (in sub-expressions)
///   Grouping:   ( )
///
/// Examples:
///   "win_amount > 0"
///   "scatter_count >= 3 && !turbo_mode"
///   "win_ratio >= 20.0 || jackpot_level != 'none'"
///   "cascade_step > 0 && cascade_step <= 10"
///   "(is_free_spin || is_cascade) && win_amount > 50"
///
/// NOT supported (by design — keep it deterministic):
///   - Function calls
///   - Array/list operations
///   - String manipulation beyond ==, !=
///   - Random values
///   - External API calls
class ConditionEvaluator {
  /// Parse and evaluate an expression against variables.
  /// Returns null if expression is null or empty (treated as "always true").
  bool? evaluate(String? expression, Map<String, dynamic> variables);

  /// Validate an expression without evaluating it.
  /// Returns list of errors (empty = valid).
  List<String> validate(String expression, Map<String, RuntimeVariableDefinition> schema);

  /// Extract all variable names referenced in an expression.
  Set<String> extractVariables(String expression);
}
```

**Implementation:** Recursive descent parser. No external dependencies. Tokenizer → AST → Evaluator.
~300 LOC. Well-tested pattern used in game engines (similar to Unity's Animator Conditions).

### 4.2 FlowExecutor

```dart
/// Walks the StageFlowGraph, executing nodes in order.
/// Manages parallel branches, timing, and condition evaluation.
class FlowExecutor {
  final StageFlowGraph graph;
  final ConditionEvaluator evaluator;
  final TimingResolver timing;
  final FlowRecorder recorder;

  // — Runtime state ———————————————————————————————————————
  final Map<String, dynamic> _variables = {};
  final Set<String> _completedNodes = {};
  final Set<String> _activeNodes = {};
  final Map<String, List<String>> _parallelBranches = {};  // forkId → active branch node ids
  bool _isRunning = false;
  bool _isPaused = false;

  // — Callbacks ———————————————————————————————————————————
  void Function(String stageId, Map<String, dynamic>? context)? onTriggerStage;
  void Function(String nodeId, StageFlowNode node)? onNodeEnter;
  void Function(String nodeId, StageFlowNode node)? onNodeComplete;
  void Function(String nodeId, StageFlowNode node)? onNodeSkipped;
  void Function(FlowExecutionResult result)? onFlowComplete;
  void Function(String error)? onError;

  /// Start executing the graph from the entry node.
  Future<FlowExecutionResult> execute({
    Map<String, dynamic>? initialVariables,
    bool dryRun = false,
  });

  /// Pause execution (can resume).
  void pause();

  /// Resume after pause.
  void resume();

  /// Cancel execution entirely.
  void cancel();

  /// Skip the current active node (if canSkip = true).
  bool skipCurrentNode();

  /// Slam stop — immediately jump to exit (if allowSlamStop = true).
  bool slamStop();

  /// Update a runtime variable during execution.
  void setVariable(String name, dynamic value);

  /// Get current variable value.
  dynamic getVariable(String name);
}
```

**Execution algorithm:**

```
1. Start at entryNode
2. For current node:
   a. Check enterCondition → if false, check skipCondition → skip or block
   b. If gate: evaluate condition, follow onTrue or onFalse edge
   c. If fork: spawn parallel executors for each parallel edge
   d. If join: wait for all/any incoming branches (configurable)
   e. If delay: wait for timing.delayMs
   f. If stage: call onTriggerStage(stageId, properties)
      → This calls EventRegistry.triggerStage()
   g. Wait for timing.durationMs (or exitCondition becomes true)
   h. Mark node complete
   i. Follow outgoing edges to next node(s)
3. Continue until exitNode or no more reachable nodes
4. Return FlowExecutionResult
```

**Parallel execution detail:**

```
           ┌─→ [WIN_LINE_SHOW] ─→ [WIN_LINE_CYCLE] ─→┐
[FORK] ────┤                                           ├──→ [JOIN] → next
           └─→ [ROLLUP_START] ─→ [ROLLUP_TICK×N] ────┘

Fork:  Spawns N independent execution streams
Join:  mode=all (wait for ALL) or mode=any (proceed when FIRST completes)
```

### 4.3 TimingResolver

```dart
/// Resolves timing for nodes based on mode and context.
class TimingResolver {
  /// Resolve the actual delay/duration for a node at execution time.
  ResolvedTiming resolve(
    TimingConfig config,
    Map<String, dynamic> variables,
    Map<String, DateTime> nodeCompletionTimes,
    double? currentBpm,
  );
}

class ResolvedTiming {
  final int delayMs;       // Actual delay before execution
  final int durationMs;    // Actual duration of execution
  final bool canSkip;
  final bool canSlamStop;
}
```

**Beat quantization:** When `beatQuantize` is set (e.g., 0.25 for 16th note):
```
actualDelayMs = roundToNearest(delayMs, (60000 / bpm) * beatQuantize)
```
This enables FMOD-style quantized transitions for musical sync.

### 4.4 FlowRecorder (Undo/Redo + Game Recall)

```dart
/// Records all flow modifications for undo/redo and GLI-11 game recall.
class FlowRecorder {
  static const int maxUndoDepth = 50;
  static const int maxRecallDepth = 10;    // GLI-11 requirement

  final List<FlowSnapshot> _undoStack = [];
  final List<FlowSnapshot> _redoStack = [];
  final List<FlowExecutionRecord> _gameRecall = [];  // Ring buffer, max 10

  /// Record a graph mutation.
  void recordMutation(StageFlowGraph before, StageFlowGraph after, String description);

  /// Undo last mutation. Returns previous graph state.
  StageFlowGraph? undo();

  /// Redo last undone mutation.
  StageFlowGraph? redo();

  bool get canUndo;
  bool get canRedo;

  /// Record a completed flow execution for game recall.
  void recordExecution(FlowExecutionRecord record);

  /// Get the last N execution records (for GLI-11 compliance).
  List<FlowExecutionRecord> getRecall({int count = 10});
}

/// Snapshot of a graph state for undo/redo.
class FlowSnapshot {
  final StageFlowGraph graph;
  final String description;           // "Moved WIN_PRESENT after ROLLUP_END"
  final DateTime timestamp;
}

/// Complete record of one flow execution for game recall.
class FlowExecutionRecord {
  final String graphId;
  final DateTime startTime;
  final DateTime endTime;
  final int totalDurationMs;
  final List<NodeExecutionEntry> entries;   // Every node that executed
  final Map<String, dynamic> initialVariables;
  final Map<String, dynamic> finalVariables;
  final FlowExecutionResult result;
}

class NodeExecutionEntry {
  final String nodeId;
  final String stageId;
  final int startMs;                  // Offset from flow start
  final int durationMs;
  final bool skipped;
  final String? skipReason;           // Condition that caused skip
}
```

---

## 5. LAYER 3 — VISUAL EDITOR

### 5.1 Editor Layout

```
┌──────────────────────────────────────────────────────────────────┐
│  TOOLBAR: [Undo] [Redo] [DryRun▶] [Presets▼] [Validate✓] [⚙]  │
├──────────────┬───────────────────────────────────────────────────┤
│              │                                                   │
│   PALETTE    │              CANVAS                               │
│              │                                                   │
│  ┌────────┐  │    ┌──────┐     ┌──────┐     ┌──────┐           │
│  │ Stage  │  │    │SPIN  │────→│REEL  │────→│EVAL  │           │
│  ├────────┤  │    │START │     │STOP  │     │WINS  │           │
│  │ Gate   │  │    └──────┘     └──────┘     └──┬───┘           │
│  ├────────┤  │                                  │               │
│  │ Fork   │  │                          ┌───────┴───────┐      │
│  ├────────┤  │                    [GATE: win>0]         │      │
│  │ Join   │  │                    ↙true      ↘false     │      │
│  ├────────┤  │              ┌──────┐      ┌──────┐      │      │
│  │ Delay  │  │              │WIN   │      │SPIN  │      │      │
│  ├────────┤  │              │PRSNT │      │END   │      │      │
│  │ Group  │  │              └──────┘      └──────┘      │      │
│  └────────┘  │                                          │      │
│              │                                          │      │
│  STAGES:     │   ─── (drag from palette to canvas) ──── │      │
│  ┌────────┐  │                                                  │
│  │ROLLUP  │  │                                                  │
│  │WIN_LINE│  │                                                  │
│  │BIG_WIN │  │                                                  │
│  │FS_ENTER│  │                                                  │
│  │CASCADE │  │                                                  │
│  │...130+ │  │                                                  │
│  └────────┘  │                                                  │
├──────────────┴───────────────────────────────────────────────────┤
│  INSPECTOR: [Node: WIN_PRESENT] [Timing: 0ms→1050ms] [Cond: ●] │
│  ┌─ Timing ─────────────────────────────────────────────────┐   │
│  │ Mode: [Sequential▼] Delay: [0ms] Duration: [1050ms]     │   │
│  │ Can Skip: [✓] Slam Stop: [✓] Beat Quantize: [off]       │   │
│  ├─ Conditions ─────────────────────────────────────────────┤   │
│  │ Enter: [win_amount > 0           ] ← expression editor   │   │
│  │ Skip:  [turbo_mode == true       ]                        │   │
│  ├─ Properties ─────────────────────────────────────────────┤   │
│  │ Bus: [sfx▼] Priority: [55] Ducking: [off▼]               │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

### 5.2 Palette — Node Source

Left panel lists all available node types and registered stages from
`StageConfigurationService`. Stages are grouped by `StageCategory`:

- **Spin** (blue) — SPIN_START, SPIN_BUTTON_PRESS, REEL_SPIN_LOOP, REEL_STOP_0..5, SPIN_END
- **Win** (gold) — WIN_PRESENT, WIN_SMALL..ULTRA, WIN_LINE_SHOW, WIN_COLLECT, ROLLUP_*
- **Feature** (green) — FS_TRIGGER, FS_ENTER, FS_SPIN_*, BONUS_*, CASCADE_*
- **Jackpot** (red) — JACKPOT_TRIGGER, JACKPOT_BUILDUP, JACKPOT_REVEAL, JACKPOT_*
- **Hold** (orange) — HOLD_TRIGGER, HOLD_ENTER, HOLD_SPIN, HOLD_*
- **Symbol** (pink) — SYMBOL_LAND_*, WILD_*, SCATTER_LAND_*
- **Anticipation** (purple) — ANTICIPATION_ON/OFF, ANTICIPATION_TENSION_*
- **UI** (gray) — UI_SPIN_PRESS, UI_BUTTON_*, UI_BET_*
- **Music** (light green) — GAME_START, BASE_GAME_START, MUSIC_*, AMBIENT_*
- **Logic** (white) — Gate, Fork, Join, Delay, Group (non-stage nodes)

Drag from palette → drop on canvas to create a new node.

### 5.3 Canvas — Node Graph

- **Panning:** Middle mouse drag or two-finger trackpad
- **Zooming:** Scroll wheel or pinch, range 25%–400%
- **Node selection:** Click to select, Shift+click for multi-select, drag rectangle for box select
- **Connections:** Drag from node output port → another node's input port
- **Reordering:** Drag selected node(s) to new position. Auto-reconnects edges.
- **Delete:** Backspace/Delete key (fails silently on locked nodes)
- **Copy/Paste:** Cmd+C/Cmd+V for selected non-locked nodes

**Node visual:**
```
┌─────────────────────┐
│ ● SPIN_START     🔒 │  ← 🔒 = locked (engineCore)
│   [spin] pri:70      │  ← category badge + priority
│   delay:0  dur:0     │  ← timing summary
│                      │
│ ○────────────────○   │  ← input port (left) / output port (right)
└─────────────────────┘

Color: node border/header matches StageCategory color
Locked: subtle padlock icon, cannot be dragged past other locked nodes
Active (during dry-run): pulsing glow highlight
Completed (during dry-run): green checkmark overlay
Skipped (during dry-run): diagonal strikethrough + gray dimming
```

**Edge visual:**
```
Normal edge:    ──────→  (solid line, category color)
Conditional:    ── ◆ ──→  (diamond = gate condition indicator)
  onTrue:       ── ◆ ──→  (green)
  onFalse:      ── ◆ ──→  (red dashed)
Parallel:       ══════→  (double line)
Fallback:       ╌╌╌╌╌→  (dotted)
```

### 5.4 Inspector — Property Editor

Bottom panel shows details for the selected node:

**Timing section:**
- Mode dropdown: Sequential / Absolute / Relative / Beat Quantized
- Delay field (ms): spinner with ±10ms/±100ms buttons
- Duration field (ms): spinner
- Relative To: dropdown of all other nodes (only when mode=relative)
- Beat Quantize: dropdown (off / 1/4 / 1/8 / 1/16 / 1/32)
- Can Skip: checkbox
- Slam Stop: checkbox

**Conditions section:**
- Enter condition: text field with autocomplete for variable names
- Skip condition: text field with autocomplete
- Exit condition: text field with autocomplete
- Live validation indicator (green check / red X)

**Properties section:**
- Bus routing: dropdown (master / music / sfx / ambience / voice)
- Priority: 0-100 slider
- Ducking: dropdown (off / light / medium / heavy / full)
- Looping: toggle
- Pooled: toggle
- Custom properties: key-value editor

### 5.5 Dry-Run Mode

Click `DryRun▶` to simulate flow execution without triggering actual audio:

```
┌─────────────────────────────────────────────────────┐
│  DRY RUN — Base Game Flow                           │
│  ┌──────────────────────────────────────────────┐   │
│  │  ■■■■■■■■■■■□□□□□□□□□□  42% | 1.23s / 2.95s │   │  ← progress bar
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  Timeline:                                          │
│  0ms    ── SPIN_START ──────── ✓                    │
│  0ms    ── REEL_SPIN_LOOP ──── ✓ (looping)          │
│  1000ms ── REEL_STOP_0 ─────── ✓                    │
│  1370ms ── REEL_STOP_1 ─────── ✓                    │
│  1740ms ── REEL_STOP_2 ─────── ⏵ ACTIVE             │
│  2110ms ── REEL_STOP_3 ─────── ○ pending             │
│  2480ms ── REEL_STOP_4 ─────── ○ pending             │
│  2500ms ── EVALUATE_WINS ───── ○ pending             │
│  2500ms ── [GATE: win>0] ───── ○ pending             │
│  ...                                                │
│                                                     │
│  Variables:  win_amount=245  scatter_count=2         │
│              turbo_mode=false  cascade_step=0        │
│                                                     │
│  [Pause] [Step ⏭] [Reset] [Set Variables...]       │
└─────────────────────────────────────────────────────┘
```

- Variables can be manually set before/during dry-run
- Step mode: advance one node at a time
- Canvas highlights current node with animated glow
- Edges animate flow direction (traveling dot)

### 5.6 Preset Management

```
┌─────────────────────────────────────────┐
│  PRESETS                            [+] │
│  ───────────────────────────────────── │
│  BUILT-IN                              │
│  ├─ 🎰 Classic 5-Reel               ▶ │
│  ├─ 💎 Cascade/Tumble               ▶ │
│  ├─ 🎲 Hold & Win                   ▶ │
│  ├─ 🏆 Jackpot Progressive          ▶ │
│  ├─ 🎁 Pick Bonus                   ▶ │
│  └─ ⚡ High Volatility              ▶ │
│                                        │
│  USER                                  │
│  ├─ My Custom Flow v2             ✎ 🗑 │
│  └─ Test Flow — Big Win Only      ✎ 🗑 │
│                                        │
│  [Import...] [Export...]               │
└─────────────────────────────────────────┘
```

---

## 6. BUILT-IN FLOW PRESETS

### 6.1 Classic 5-Reel Base Game

```
SPIN_START → REEL_SPIN_LOOP → [ANTICIPATION branch] → REEL_STOP_0..4
→ EVALUATE_WINS → [GATE: win_amount > 0]
  ├─ true → WIN_PRESENT → [GATE: win_ratio >= 20]
  │           ├─ true → BIG_WIN_INTRO → BIG_WIN_TIER_N → BIG_WIN_END
  │           └─ false → [FORK]
  │                        ├─→ WIN_LINE_SHOW (cycle×3) → WIN_LINE_HIDE
  │                        └─→ ROLLUP_START → ROLLUP_TICK×N → ROLLUP_END
  │                      [JOIN all]
  │           → WIN_COLLECT
  └─ false → (skip to end)
→ SPIN_END
```

### 6.2 Cascade/Tumble Flow

```
SPIN_START → REEL_SPIN_LOOP → REEL_STOP_0..4
→ EVALUATE_WINS → [GATE: win_amount > 0]
  ├─ true → WIN_LINE_SHOW → CASCADE_START
  │         → CASCADE_SYMBOL_POP → TUMBLE_DROP → TUMBLE_LAND
  │         → EVALUATE_WINS (re-enter loop)
  │         [GATE: cascade_step <= 10 && win_amount > 0]
  │           ├─ true → CASCADE_STEP → (loop back to CASCADE_SYMBOL_POP)
  │           └─ false → CASCADE_END → ROLLUP_START → ROLLUP_END → WIN_COLLECT
  └─ false → SPIN_END
```

### 6.3 Hold & Win Flow

```
[GATE: coin_count >= trigger_threshold]
  ├─ true → HOLD_TRIGGER → HOLD_ENTER → HOLD_MUSIC
  │         → [LOOP: hold_spins_remaining > 0]
  │           → HOLD_SPIN → HOLD_RESPIN_STOP
  │           → [GATE: new_coin_landed]
  │             ├─ true → HOLD_SYMBOL_LAND → HOLD_RESPIN_RESET
  │             └─ false → (continue loop)
  │         → [GATE: grid_full]
  │           ├─ true → HOLD_GRID_FULL → JACKPOT_GRAND
  │           └─ false → HOLD_EXIT
  └─ false → (continue base game)
```

### 6.4 Jackpot Progressive Flow

```
JACKPOT_TRIGGER → JACKPOT_BUILDUP
→ [GATE: jackpot_level]
  ├─ 'mini' → JACKPOT_MINI → JACKPOT_PRESENT
  ├─ 'minor' → JACKPOT_MINOR → JACKPOT_PRESENT
  ├─ 'major' → JACKPOT_MAJOR → JACKPOT_PRESENT
  └─ 'grand' → JACKPOT_GRAND → JACKPOT_CELEBRATION (loop) → JACKPOT_PRESENT
→ JACKPOT_REVEAL → JACKPOT_END
```

### 6.5 Free Spins Flow

```
FS_TRIGGER → FS_ENTER → FS_MUSIC (looping, parallel)
→ [LOOP: fs_remaining > 0]
  → FS_SPIN_START → REEL_SPIN_LOOP → REEL_STOP_0..4
  → EVALUATE_WINS
  → [GATE: scatter_count >= retrigger_threshold]
    ├─ true → FS_RETRIGGER → (add spins)
    └─ false → (continue)
  → [GATE: win_amount > 0]
    ├─ true → WIN_PRESENT → ROLLUP → WIN_COLLECT
    └─ false → FS_SPIN_END
→ FS_EXIT
```

### 6.6 Pick Bonus Flow

```
BONUS_TRIGGER → BONUS_ENTER
→ [LOOP: picks_remaining > 0]
  → BONUS_STEP → [Player picks]
  → BONUS_REVEAL
  → [GATE: is_grand_prize]
    ├─ true → (end picks early)
    └─ false → (continue)
→ BONUS_EXIT → WIN_PRESENT → ROLLUP → WIN_COLLECT
```

---

## 7. CONDITION EXPRESSION LANGUAGE

### 7.1 Grammar (BNF)

```
expression     → or_expr
or_expr        → and_expr ('||' and_expr)*
and_expr       → not_expr ('&&' not_expr)*
not_expr       → '!' not_expr | comparison
comparison     → add_expr (comp_op add_expr)?
comp_op        → '==' | '!=' | '>' | '<' | '>=' | '<='
add_expr       → mul_expr (('+' | '-') mul_expr)*
mul_expr       → unary (('*' | '/') unary)*
unary          → '-' unary | primary
primary        → NUMBER | STRING | BOOL | IDENTIFIER | '(' expression ')'
NUMBER         → [0-9]+ ('.' [0-9]+)?
STRING         → '\'' [^']* '\''
BOOL           → 'true' | 'false'
IDENTIFIER     → [a-zA-Z_][a-zA-Z0-9_]*
```

### 7.2 Examples

```
# Simple comparisons
win_amount > 0
scatter_count >= 3
turbo_mode == true

# Combined conditions
win_ratio >= 20.0 && !turbo_mode
(is_free_spin || is_cascade) && win_amount > 50
cascade_step > 0 && cascade_step <= 10

# Feature routing
feature_state == 'freeSpins'
jackpot_level != 'none'
hold_spins_remaining > 0

# Win tier routing
win_tier >= 3 && big_win_tier == 0     # Nice win but not big win
big_win_tier >= 1                       # Any big win tier
win_ratio >= 100.0                      # Mega win territory

# Skip conditions (turbo mode)
turbo_mode == true && win_ratio < 5.0   # Skip small win presentation in turbo
autoplay_active == true && win_tier <= 1 # Skip minimal wins during autoplay
```

---

## 8. REORDERING RULES & CONSTRAINTS

### 8.1 Layer Rules

```
ENGINE CORE (Layer 1) — LOCKED ordering relative to each other:
  SPIN_START must be FIRST
  REEL_STOP_N must be AFTER REEL_SPIN_LOOP
  EVALUATE_WINS must be AFTER all REEL_STOP_N
  SPIN_END must be LAST

  User CAN insert nodes BETWEEN engine core nodes.
  User CANNOT delete or reorder engine core nodes.

FEATURE COMPOSER (Layer 2) — Semi-locked:
  Feature entry must come AFTER EVALUATE_WINS
  Feature exit must come BEFORE SPIN_END
  Internal feature ordering is user-editable

AUDIO MAPPING (Layer 3) — Fully editable:
  User can add, remove, reorder any audio mapping node
  No restrictions except graph must remain a valid DAG
```

### 8.2 Reorder Operations

| Operation | Description | Constraint |
|-----------|-------------|------------|
| **Move After** | Place node after another | Cannot move locked past locked |
| **Move Before** | Place node before another | Cannot move locked past locked |
| **Swap** | Exchange positions of two nodes | Both must be same layer or unlocked |
| **Insert Between** | Add new node between two connected nodes | Auto-reconnects edges |
| **Extract to Parallel** | Move node to a new parallel branch | Creates fork/join if needed |
| **Collapse Parallel** | Merge parallel branch back to sequential | Removes fork/join |
| **Group** | Wrap selected nodes in a group | Visual only, no execution change |
| **Ungroup** | Remove group wrapper | Visual only |

### 8.3 Edge Cases

1. **Reordering WIN_SYMBOL_HIGHLIGHT to before EVALUATE_WINS** — Blocked. WIN_SYMBOL_HIGHLIGHT
   depends on win evaluation results (which symbols won). Validation error: "Node depends on
   EVALUATE_WINS output."

2. **Running ROLLUP and WIN_LINE_SHOW in parallel** — Allowed. Common industry pattern. Creates
   fork before both + join after both.

3. **Moving BIG_WIN_TIER inside free spins** — Allowed. BIG_WIN can occur during any feature.
   The tier escalation logic runs identically regardless of context.

4. **Deleting SPIN_START** — Blocked. `locked = true`. Validation error: "Cannot delete engine
   core node."

5. **Creating a cycle (A→B→C→A)** — Blocked. `hasCycle()` check on every edge addition. Use
   loop nodes instead (GATE with back-edge to earlier node, constrained by loop counter).

---

## 9. EXISTING CODE INTEGRATION

### 9.1 Replacing Future.delayed Chains

Current `slot_preview_widget.dart` hardcodes the flow:

```dart
// CURRENT (hardcoded):
Future.delayed(Duration(milliseconds: 500), () {
  eventRegistry.triggerStage('WIN_PRESENT');
  Future.delayed(Duration(milliseconds: _symbolHighlightDurationMs), () {
    _startRollup();
    // ...
  });
});

// NEW (graph-driven):
final executor = FlowExecutor(graph: currentFlowGraph, ...);
executor.onTriggerStage = (stageId, context) {
  eventRegistry.triggerStage(stageId, context: context);
};
await executor.execute(initialVariables: _buildVariableSnapshot());
```

### 9.2 Variable Snapshot Builder

```dart
/// Builds runtime variables from current slot state.
Map<String, dynamic> _buildVariableSnapshot() => {
  'win_amount': _winAmount,
  'win_ratio': _winAmount / (_currentBet * _linesCount),
  'scatter_count': _scatterReels.length,
  'bonus_count': _bonusCount,
  'is_free_spin': gameFlowProvider.currentState == GameFlowState.freeSpins,
  'is_cascade': gameFlowProvider.currentState == GameFlowState.cascading,
  'cascade_step': _cascadeStep,
  'turbo_mode': _isTurboMode,
  'autoplay_active': _isAutoplaying,
  'anticipation_active': _isAnticipating,
  'reel_count': widget.config.reelCount,
  'current_reel': _currentStopReel,
  'total_bet': _currentBet * _linesCount,
  'balance': _balance,
  'spin_count': _totalSpins,
  'feature_state': gameFlowProvider.currentState.name,
  'win_tier': _computeWinTier(),
  'big_win_tier': _computeBigWinTier(),
  'hold_spins_remaining': _holdSpinsRemaining,
  'jackpot_level': _activeJackpotLevel ?? 'none',
};
```

### 9.3 StageDependencyEditor Migration

The existing `StageDependencyEditor` widget (simple list of dependencies) will be superseded
by the full visual editor. Migration path:

1. Existing `StageDependency` data → converted to `StageFlowEdge` entries
2. `dependentStage` → `sourceNodeId`, `requiredStage` → `targetNodeId`
3. `minDelayMs` → `TimingConfig.delayMs`, `maxDelayMs` → `TimingConfig.maxDurationMs`
4. `isBlocking` → `EdgeType.normal` (blocking) or `EdgeType.fallback` (non-blocking)

### 9.4 GameFlowProvider Integration

`GameFlowProvider` FSM transitions map to gate nodes:

| FSM Transition | Gate Condition |
|----------------|----------------|
| baseGame → freeSpins | `scatter_count >= 3` |
| baseGame → holdAndWin | `coin_count >= 6` |
| baseGame → bonusGame | `bonus_count >= 3` |
| baseGame → cascading | `cascade_win == true` |
| baseGame → gamble | `player_gamble == true` |
| baseGame → jackpotPresentation | `jackpot_triggered == true` |
| freeSpins → freeSpins (retrigger) | `scatter_count >= 3 && is_free_spin` |

### 9.5 SlotLabTemplate Storage

Flow graphs are stored in `SlotLabTemplate.behaviorTreeConfig`:

```json
{
  "behaviorTreeConfig": {
    "version": 2,
    "type": "stageFlowGraph",
    "graph": { /* StageFlowGraph.toJson() */ }
  }
}
```

Backward compatibility: `version: 1` (legacy StageDependency list) auto-converts on load.

---

## 10. REGULATORY COMPLIANCE

### 10.1 GLI-11 (Gaming Laboratories International)

| Requirement | Implementation |
|-------------|----------------|
| **10-game recall** | `FlowRecorder._gameRecall` ring buffer (max 10) |
| **Deterministic outcomes** | `requireDeterministic = true` — no random in conditions |
| **State reproducibility** | `FlowExecutionRecord` captures full variable snapshot |
| **Audit trail** | Every node execution logged with timestamp and duration |
| **Error recovery** | Flow resumes from last completed node after crash |

### 10.2 UKGC (UK Gambling Commission)

| Requirement | Implementation |
|-------------|----------------|
| **2.5s minimum spin cycle** | `FlowConstraints.minSpinCycleMs = 2500` validated on dry-run |
| **No slam stop during features** | `canSlamStop = false` on feature nodes |
| **Responsible gaming interrupts** | `UI_REALITY_CHECK` / `UI_SESSION_LIMIT` stages can interrupt any flow |
| **Play time warnings** | `UI_PLAY_TIME_WARNING` node insertable at any point |
| **Cool-off period** | `UI_COOL_OFF_PERIOD` blocks flow execution entirely |

### 10.3 MGA / Curaçao / PAGCOR

Standard compliance through the same constraint system. Jurisdiction-specific constraints
loaded from a `FlowConstraints` preset:

```dart
FlowConstraints.mga()      // Malta: 3.5s min cycle, no turbo in bonus
FlowConstraints.curacao()   // Curaçao: minimal restrictions
FlowConstraints.pagcor()    // Philippines: 2.0s min cycle
FlowConstraints.ukgc()      // UK: 2.5s min, no slam stop
FlowConstraints.gli11()     // GLI: 10-game recall, deterministic
```

---

## 11. TIMING REFERENCE — Current Values

All timing values extracted from `slot_preview_widget.dart`:

### 11.1 Core Timing Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `_anticipationDurationMs` | 3000 | Per-reel anticipation duration |
| `_symbolHighlightDurationMs` | 1050 | 3 cycles × 350ms |
| `_symbolPulseCycleMs` | 350 | Single pulse cycle |
| `_symbolPulseCycles` | 3 | Number of highlight pulses |
| `_bigWinIntroDurationMs` | 500 | Big win intro stage |
| `_tierDisplayDurationMs` | 4000 | Each tier displays for 4s |
| `_bigWinEndDurationMs` | 4000 | Big win outro |
| `_rollupTicksTotal` | 15 | ~1.5s at 100ms intervals |
| `_winLineCycleDuration` | 1500ms | Win line show/hide cycle |
| `_symbolPopStaggerMs` | 100 | L→R wave stagger |

### 11.2 Rollup Durations by Tier

| Tier | Duration | Tick Rate |
|------|----------|-----------|
| BIG_WIN_TIER_1 (20x-50x) | 800ms | 20/s |
| BIG_WIN_TIER_2 (50x-100x) | 1200ms | 18/s |
| BIG_WIN_TIER_3 (100x-250x) | 2000ms | 15/s |
| BIG_WIN_TIER_4 (250x-500x) | 3500ms | 12/s |
| BIG_WIN_TIER_5 (500x+) | 6000ms | 8/s |
| Default (small wins) | 800ms | 20/s |

### 11.3 Animation Controllers

| Controller | Duration | Behavior |
|------------|----------|----------|
| `_winPulseController` | 600ms | Repeat reverse |
| `_winAmountController` | 800ms | Elastic out |
| `_winCounterController` | 1500ms | Forward |
| `_symbolBounceController` | 350ms | Forward |
| `_particleController` | 3000ms | Forward |
| `_anticipationController` | 400ms | Repeat reverse |
| `_nearMissController` | 600ms | Elastic out |
| `_cascadePopController` | 400ms | Ease in back |
| `_screenFlashController` | 150ms | Ease out |
| `_plaqueGlowController` | 400ms | Repeat reverse |
| `_lineGrowController` | 250ms | Forward |
| `_spinLoopFadeMs` | 15ms | EventRegistry constant |

### 11.4 Visual-Sync Reel Stop Timing (5-reel, default)

| Reel | Stop Time | Delta |
|------|-----------|-------|
| 0 | 1000ms | — |
| 1 | 1370ms | +370ms |
| 2 | 1740ms | +370ms |
| 3 | 2110ms | +370ms |
| 4 | 2480ms | +370ms |

### 11.5 Crossfade Durations by Stage Group

| Group | Crossfade | Stages |
|-------|-----------|--------|
| MUSIC | 500ms | MUSIC_BASE_L1, MUSIC_FEATURE, MUSIC_TENSION, etc. |
| AMBIENT | 400ms | AMBIENT_BASE, AMBIENT_FEATURE, AMBIENT_LOOP |
| WIN | 100ms | WIN_PRESENT |
| BIGWIN | 150ms | BIGWIN_START |
| MEGAWIN | 200ms | MEGAWIN_START |
| ROLLUP | 50ms | ROLLUP_* |
| SPIN | 50ms | SPIN_* |
| REEL | 30ms | REEL_* |
| FREESPIN | 200ms | FS_* |
| BONUS | 200ms | BONUS_* |
| HOLD | 200ms | HOLD_* |

---

## 12. STAGE REGISTRY — Complete Reference

130+ stages organized by category. Full list in `stage_configuration_service.dart`.

### 12.1 Stage Categories and Counts

| Category | Count | Key Stages |
|----------|-------|------------|
| Spin | 10 | SPIN_START, REEL_SPIN_LOOP, REEL_STOP_0..5, SPIN_END |
| Win | 25+ | WIN_PRESENT, WIN_SMALL..ULTRA, WIN_TIER_0..7, WIN_LINE_*, ROLLUP_* |
| Feature | 18 | FS_TRIGGER..EXIT, BONUS_TRIGGER..EXIT |
| Cascade | 12 | CASCADE_START..END, TUMBLE_DROP/LAND, CASCADE_COMBO_3..10 |
| Jackpot | 10 | JACKPOT_TRIGGER..END, JACKPOT_MINI..GRAND |
| Hold | 9 | HOLD_TRIGGER..EXIT, HOLD_MUSIC |
| Gamble | 6 | GAMBLE_START..END |
| Symbol | 17 | SYMBOL_LAND_*, WILD_*, SCATTER_LAND_* |
| Anticipation | 26 | ANTICIPATION_ON/OFF, _TENSION_R{0-4}_L{1-4}, NEAR_MISS_* |
| UI | 80+ | UI_SPIN_*, UI_BUTTON_*, UI_BET_*, UI_AUTOPLAY_*, etc. |
| Music | 8 | GAME_START, BASE_GAME_START, MUSIC_*, AMBIENT_*, ATTRACT_MODE |

### 12.2 Dynamic Stage Generation

- **P5 Win Tier stages:** Generated from `SlotWinConfiguration` — WIN_LOW, WIN_EQUAL, WIN_1..6 + presentation + rollup variants per tier
- **Symbol-specific stages:** Generated per symbol × 8 contexts (LAND, HIGHLIGHT, EXPAND, LOCK, TRANSFORM, COLLECT, STACK, TRIGGER, ANTICIPATION)

### 12.3 Fallback Resolution Chain

```
ANTICIPATION_TENSION_R2_L3 → _R2 → ANTICIPATION_TENSION → ANTICIPATION_ON
REEL_STOP_3                → REEL_STOP
CASCADE_STEP_5             → CASCADE_STEP
WIN_SYMBOL_HIGHLIGHT_HP1   → _HP → WIN_SYMBOL_HIGHLIGHT
```

Max 3 fallback attempts. Case-insensitive. Suffix stripping by underscore segments.

---

## 13. IMPLEMENTATION PLAN

### Phase 1: Data Model (~500 LOC)

**File:** `flutter_ui/lib/models/stage_flow_models.dart`

- `StageFlowNode`, `StageFlowNodeType`, `FlowLayer`
- `TimingConfig`, `TimingMode`
- `StageFlowEdge`, `EdgeType`
- `StageFlowGraph` (immutable, all operations return new instances)
- `FlowConstraints`
- `FlowPreset`, `FlowPresetCategory`
- `RuntimeVariableDefinition`, `RuntimeVarType`
- `FlowValidationError`, `FlowValidationSeverity`
- `FlowSnapshot`, `FlowExecutionRecord`, `NodeExecutionEntry`
- Full JSON serialization for all types

### Phase 2: Condition Evaluator (~300 LOC)

**File:** `flutter_ui/lib/services/condition_evaluator.dart`

- Tokenizer: string → token list
- Parser: token list → AST (recursive descent)
- Evaluator: AST + variables → bool result
- Validator: AST + schema → error list
- Variable extractor: AST → Set<String>

### Phase 3: Execution Engine (~600 LOC)

**File:** `flutter_ui/lib/services/flow_executor.dart`

- `FlowExecutor` — main execution loop
- `TimingResolver` — timing mode resolution
- `ParallelScheduler` — fork/join management
- `FlowRecorder` — undo/redo stack + game recall
- Integration with `EventRegistry.triggerStage()`

### Phase 4: Flow Provider (~400 LOC)

**File:** `flutter_ui/lib/providers/slot_lab/stage_flow_provider.dart`

- `StageFlowProvider extends ChangeNotifier`
- Current graph state management
- Preset loading/saving (integrates with `SlotLabTemplate`)
- Undo/redo commands
- Validation on every mutation
- GetIt singleton registration (Layer 5)
- Bridge between `FlowExecutor` and `SlotPreviewWidget`

### Phase 5: Built-in Presets (~350 LOC)

**File:** `flutter_ui/lib/services/stage_flow_presets.dart`

- 6 factory presets (Classic, Cascade, Hold&Win, Jackpot, FreeSpin, PickBonus)
- `StageFlowGraph` builder helpers for common patterns
- `defaultBaseGameGraph()` — the standard 5-reel flow
- Variable schema definitions per preset

### Phase 6: Visual Editor Widget (~800 LOC)

**File:** `flutter_ui/lib/widgets/slot_lab/stage_flow_editor_widget.dart`

- Canvas with pan/zoom (InteractiveViewer)
- Node rendering (CustomPainter)
- Edge rendering (CustomPainter with Bézier curves)
- Drag & drop from palette
- Node selection and multi-select
- Connection drawing (drag from port to port)
- Node reordering with constraint validation
- Keyboard shortcuts (Delete, Cmd+Z, Cmd+Shift+Z, Cmd+C, Cmd+V)

### Phase 7: Inspector & Dry-Run (~250 LOC)

**File:** `flutter_ui/lib/widgets/slot_lab/stage_flow_inspector_widget.dart`

- Property inspector panel
- Timing editor with all modes
- Condition editor with autocomplete
- Dry-run execution view with timeline
- Variable editor for dry-run input

### Phase 8: Integration (~200 LOC, spread across existing files)

- `slot_preview_widget.dart` — Replace `Future.delayed` chains with `FlowExecutor`
- `slot_lab_screen.dart` — Add editor to Lower Zone tab options
- `service_locator.dart` — Register `StageFlowProvider` at Layer 5
- `slotlab_template_provider.dart` — Add `behaviorTreeConfig` v2 support

**Total: ~3,400 LOC across 8 files**

### Implementation Order

```
Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 8 (backend complete)
                                                ↘ Phase 6 → Phase 7 (UI complete)
```

Phases 1-5 enable the engine to drive the slot flow from a graph instead of hardcoded delays.
Phases 6-7 provide the visual editor for sound designers.
Phase 8 wires everything together.

---

## 14. TESTING STRATEGY

### Unit Tests

| Test | Target | Count |
|------|--------|-------|
| `stage_flow_models_test.dart` | Data model serialization, graph ops | ~25 |
| `condition_evaluator_test.dart` | Expression parsing, evaluation | ~30 |
| `flow_executor_test.dart` | Execution, parallel, timing | ~20 |
| `flow_recorder_test.dart` | Undo/redo, game recall | ~10 |

### Integration Tests

| Test | Description |
|------|-------------|
| Classic flow dry-run | Execute default graph, verify all stages fire in order |
| Parallel execution | Fork/join with WIN_LINE_SHOW + ROLLUP_START |
| Condition routing | Gate with win_amount > 0 → true path vs false path |
| Big win escalation | Verify tier progression from INTRO through correct max tier |
| Cascade looping | Verify cascade step increments and exit condition |
| Turbo mode skip | Verify small win stages are skipped when turbo_mode = true |
| Regulatory timing | Verify total cycle >= 2500ms |
| Undo/redo | 10 mutations, undo all, redo all, verify graph equality |
| Preset load/save | Save custom preset, reload, verify identical graph |

### Validation Tests

| Test | Description |
|------|-------------|
| Cycle detection | Insert cycle edge → error |
| Orphan detection | Add disconnected node → warning |
| Locked node protection | Delete SPIN_START → error |
| Expression validation | Invalid syntax → error list |
| Timing validation | Total < 2500ms → warning |

---

## 15. FUTURE EXTENSIONS (Post-MVP)

These features are NOT in the initial implementation but the architecture supports them:

1. **FluxMacro Integration** — `StageFlowGraph` as a FluxMacro step type
2. **FMOD Export** — Generate FMOD Designer project from graph
3. **Wwise Export** — Generate Wwise SoundBank structure from graph
4. **A/B Testing** — Run two graphs simultaneously, compare execution metrics
5. **Machine Learning** — Auto-generate optimal flow based on player engagement data
6. **Multiplayer Sync** — Synchronized flow execution across multiple clients
7. **Timeline View** — Horizontal timeline representation (DAW-style) as alternate to node graph
8. **Audio Preview** — Play actual audio during dry-run (currently visual only)
9. **Collaborative Editing** — Multiple designers editing the same graph (CRDT-based)
10. **Version Control** — Git-like branching for flow graph versions

---

## APPENDIX A: File Map

| File | LOC | Phase |
|------|-----|-------|
| `flutter_ui/lib/models/stage_flow_models.dart` | ~500 | 1 |
| `flutter_ui/lib/services/condition_evaluator.dart` | ~300 | 2 |
| `flutter_ui/lib/services/flow_executor.dart` | ~600 | 3 |
| `flutter_ui/lib/providers/slot_lab/stage_flow_provider.dart` | ~400 | 4 |
| `flutter_ui/lib/services/stage_flow_presets.dart` | ~350 | 5 |
| `flutter_ui/lib/widgets/slot_lab/stage_flow_editor_widget.dart` | ~800 | 6 |
| `flutter_ui/lib/widgets/slot_lab/stage_flow_inspector_widget.dart` | ~250 | 7 |
| Various existing files (integration) | ~200 | 8 |
| **TOTAL** | **~3,400** | |

## APPENDIX B: Dependency Graph

```
stage_flow_models.dart  (Phase 1 — no deps)
         ↓
condition_evaluator.dart (Phase 2 — depends on models)
         ↓
flow_executor.dart (Phase 3 — depends on models + evaluator)
         ↓
stage_flow_provider.dart (Phase 4 — depends on all above)
         ↓
stage_flow_presets.dart (Phase 5 — depends on models)
         ↓
stage_flow_editor_widget.dart (Phase 6 — depends on provider)
         ↓
stage_flow_inspector_widget.dart (Phase 7 — depends on editor + provider)
         ↓
Integration (Phase 8 — depends on all above)
```

## APPENDIX C: Industry Comparison Matrix

| Feature | FluxForge (this spec) | IGT | NetEnt | Pragmatic | FMOD | Wwise |
|---------|----------------------|-----|--------|-----------|------|-------|
| Visual node editor | ✅ | ✅ (XML) | ✅ | ⚠️ (internal) | ✅ | ✅ |
| Condition expressions | ✅ (runtime) | ✅ (compile) | ✅ | ✅ | ✅ (RTPC) | ✅ (State) |
| Parallel branches | ✅ (fork/join) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Beat quantization | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| Dry-run preview | ✅ | ❌ | ⚠️ | ❌ | ✅ (profiler) | ✅ (profiler) |
| Undo/redo | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| Presets | ✅ (6 built-in) | ✅ | ⚠️ | ⚠️ | ✅ | ✅ |
| GLI-11 recall | ✅ (10 game) | ✅ | ✅ | ✅ | N/A | N/A |
| UKGC compliance | ✅ (constraints) | ✅ | ✅ | ✅ | N/A | N/A |
| Runtime reordering | ✅ | ❌ | ❌ | ❌ | ⚠️ | ⚠️ |
| Sound designer access | ✅ (drag&drop) | ❌ (dev only) | ❌ | ❌ | ✅ | ✅ |

---

**END OF SPECIFICATION**

*This document is the single source of truth for the Dynamic Stage Flow Editor system.
All implementation must conform to this spec. Any deviations require spec update first.*
