/// Cycle Action Service — Sequential Action Cycling
///
/// #25: Each invocation executes the next step in a cycle.
///
/// Features:
/// - Named cycle actions with ordered steps
/// - Each call advances to next step (wraps around)
/// - Conditional steps (if/then/else based on state queries)
/// - Integration with CommandRegistry for palette/shortcut access
/// - Persistence via JSON serialization
library;

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CYCLE STEP MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Type of step in a cycle
enum CycleStepType {
  /// Execute a CommandRegistry command by ID
  command,

  /// Execute a custom action string (dispatched via onDspAction)
  action,

  /// Conditional: evaluate condition, then execute 'then' or 'else' step
  conditional,
}

/// Condition operator for conditional steps
enum ConditionOp {
  equals,
  notEquals,
  greaterThan,
  lessThan,
}

/// A condition that queries state
class CycleCondition {
  /// State key to query (e.g., 'mixer.solo.track1', 'transport.playing')
  final String stateKey;

  /// Comparison operator
  final ConditionOp op;

  /// Value to compare against
  final String compareValue;

  const CycleCondition({
    required this.stateKey,
    required this.op,
    required this.compareValue,
  });

  /// Evaluate condition against a state provider
  bool evaluate(String Function(String key) stateQuery) {
    final actual = stateQuery(stateKey);
    switch (op) {
      case ConditionOp.equals:
        return actual == compareValue;
      case ConditionOp.notEquals:
        return actual != compareValue;
      case ConditionOp.greaterThan:
        final a = double.tryParse(actual) ?? 0;
        final b = double.tryParse(compareValue) ?? 0;
        return a > b;
      case ConditionOp.lessThan:
        final a = double.tryParse(actual) ?? 0;
        final b = double.tryParse(compareValue) ?? 0;
        return a < b;
    }
  }

  Map<String, dynamic> toJson() => {
    'stateKey': stateKey,
    'op': op.name,
    'compareValue': compareValue,
  };

  factory CycleCondition.fromJson(Map<String, dynamic> json) => CycleCondition(
    stateKey: json['stateKey'] as String? ?? '',
    op: ConditionOp.values.firstWhere(
      (o) => o.name == json['op'],
      orElse: () => ConditionOp.equals,
    ),
    compareValue: json['compareValue'] as String? ?? '',
  );
}

/// A single step in a cycle action
class CycleStep {
  final String id;
  final String label;
  final CycleStepType type;

  /// For command type: CommandRegistry command ID
  final String? commandId;

  /// For action type: action string + params
  final String? actionName;
  final Map<String, dynamic>? actionParams;

  /// For conditional type
  final CycleCondition? condition;
  final CycleStep? thenStep;
  final CycleStep? elseStep;

  const CycleStep({
    required this.id,
    required this.label,
    required this.type,
    this.commandId,
    this.actionName,
    this.actionParams,
    this.condition,
    this.thenStep,
    this.elseStep,
  });

  /// Create a command step
  factory CycleStep.command({
    required String id,
    required String label,
    required String commandId,
  }) => CycleStep(
    id: id,
    label: label,
    type: CycleStepType.command,
    commandId: commandId,
  );

  /// Create an action step
  factory CycleStep.action({
    required String id,
    required String label,
    required String actionName,
    Map<String, dynamic>? params,
  }) => CycleStep(
    id: id,
    label: label,
    type: CycleStepType.action,
    actionName: actionName,
    actionParams: params,
  );

  /// Create a conditional step
  factory CycleStep.conditional({
    required String id,
    required String label,
    required CycleCondition condition,
    required CycleStep thenStep,
    CycleStep? elseStep,
  }) => CycleStep(
    id: id,
    label: label,
    type: CycleStepType.conditional,
    condition: condition,
    thenStep: thenStep,
    elseStep: elseStep,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'type': type.name,
    if (commandId != null) 'commandId': commandId,
    if (actionName != null) 'actionName': actionName,
    if (actionParams != null) 'actionParams': actionParams,
    if (condition != null) 'condition': condition!.toJson(),
    if (thenStep != null) 'thenStep': thenStep!.toJson(),
    if (elseStep != null) 'elseStep': elseStep!.toJson(),
  };

  factory CycleStep.fromJson(Map<String, dynamic> json) => CycleStep(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    type: CycleStepType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => CycleStepType.command,
    ),
    commandId: json['commandId'] as String?,
    actionName: json['actionName'] as String?,
    actionParams: json['actionParams'] as Map<String, dynamic>?,
    condition: json['condition'] != null
        ? CycleCondition.fromJson(json['condition'] as Map<String, dynamic>)
        : null,
    thenStep: json['thenStep'] != null
        ? CycleStep.fromJson(json['thenStep'] as Map<String, dynamic>)
        : null,
    elseStep: json['elseStep'] != null
        ? CycleStep.fromJson(json['elseStep'] as Map<String, dynamic>)
        : null,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// CYCLE ACTION
// ═══════════════════════════════════════════════════════════════════════════════

/// A complete cycle action with ordered steps
class CycleAction {
  final String id;
  String name;
  String? description;
  final List<CycleStep> steps;
  int _currentIndex;

  CycleAction({
    required this.id,
    required this.name,
    this.description,
    required this.steps,
    int currentIndex = 0,
  }) : _currentIndex = currentIndex;

  int get currentIndex => _currentIndex;
  int get stepCount => steps.length;
  bool get isEmpty => steps.isEmpty;

  CycleStep? get currentStep =>
      steps.isEmpty ? null : steps[_currentIndex % steps.length];

  /// Advance to next step and return the step to execute
  CycleStep? advance() {
    if (steps.isEmpty) return null;
    final step = steps[_currentIndex % steps.length];
    _currentIndex = (_currentIndex + 1) % steps.length;
    return step;
  }

  /// Reset cycle to first step
  void reset() => _currentIndex = 0;

  /// Get step at specific index
  CycleStep? stepAt(int index) =>
      index >= 0 && index < steps.length ? steps[index] : null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'steps': steps.map((s) => s.toJson()).toList(),
    'currentIndex': _currentIndex,
  };

  factory CycleAction.fromJson(Map<String, dynamic> json) => CycleAction(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
    steps: (json['steps'] as List<dynamic>?)
        ?.map((s) => CycleStep.fromJson(s as Map<String, dynamic>))
        .toList() ?? [],
    currentIndex: json['currentIndex'] as int? ?? 0,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// CYCLE ACTION SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Service for managing and executing cycle actions
class CycleActionService extends ChangeNotifier {
  CycleActionService._();
  static final CycleActionService instance = CycleActionService._();

  final Map<String, CycleAction> _cycles = {};

  /// Callback for executing commands (bound to CommandRegistry.execute)
  void Function(String commandId)? onExecuteCommand;

  /// Callback for dispatching actions (bound to onDspAction)
  void Function(String action, Map<String, dynamic>? params)? onDispatchAction;

  /// Callback for querying state (for conditional steps)
  String Function(String key)? onQueryState;

  // Getters
  List<CycleAction> get cycles => _cycles.values.toList();
  int get count => _cycles.length;

  CycleAction? getCycle(String id) => _cycles[id];

  /// Add a new cycle action
  void addCycle(CycleAction cycle) {
    _cycles[cycle.id] = cycle;
    notifyListeners();
  }

  /// Remove a cycle action
  void removeCycle(String id) {
    _cycles.remove(id);
    notifyListeners();
  }

  /// Rename a cycle
  void renameCycle(String id, String newName) {
    final cycle = _cycles[id];
    if (cycle == null) return;
    cycle.name = newName;
    notifyListeners();
  }

  /// Add a step to a cycle
  void addStep(String cycleId, CycleStep step) {
    final cycle = _cycles[cycleId];
    if (cycle == null) return;
    cycle.steps.add(step);
    notifyListeners();
  }

  /// Remove a step from a cycle
  void removeStep(String cycleId, String stepId) {
    final cycle = _cycles[cycleId];
    if (cycle == null) return;
    cycle.steps.removeWhere((s) => s.id == stepId);
    if (cycle.currentIndex >= cycle.steps.length) {
      cycle.reset();
    }
    notifyListeners();
  }

  /// Move step up in cycle
  void moveStepUp(String cycleId, int index) {
    final cycle = _cycles[cycleId];
    if (cycle == null || index <= 0 || index >= cycle.steps.length) return;
    final step = cycle.steps.removeAt(index);
    cycle.steps.insert(index - 1, step);
    notifyListeners();
  }

  /// Move step down in cycle
  void moveStepDown(String cycleId, int index) {
    final cycle = _cycles[cycleId];
    if (cycle == null || index < 0 || index >= cycle.steps.length - 1) return;
    final step = cycle.steps.removeAt(index);
    cycle.steps.insert(index + 1, step);
    notifyListeners();
  }

  /// Execute the next step in a cycle
  void executeCycle(String id) {
    final cycle = _cycles[id];
    if (cycle == null || cycle.isEmpty) return;

    final step = cycle.advance();
    if (step == null) return;

    _executeStep(step);
    notifyListeners();
  }

  /// Reset a cycle to its first step
  void resetCycle(String id) {
    final cycle = _cycles[id];
    if (cycle == null) return;
    cycle.reset();
    notifyListeners();
  }

  /// Reset all cycles
  void resetAll() {
    for (final cycle in _cycles.values) {
      cycle.reset();
    }
    notifyListeners();
  }

  /// Execute a step (recursive for conditionals)
  void _executeStep(CycleStep step) {
    switch (step.type) {
      case CycleStepType.command:
        if (step.commandId != null) {
          onExecuteCommand?.call(step.commandId!);
        }

      case CycleStepType.action:
        if (step.actionName != null) {
          onDispatchAction?.call(step.actionName!, step.actionParams);
        }

      case CycleStepType.conditional:
        if (step.condition != null && onQueryState != null) {
          final result = step.condition!.evaluate(onQueryState!);
          if (result && step.thenStep != null) {
            _executeStep(step.thenStep!);
          } else if (!result && step.elseStep != null) {
            _executeStep(step.elseStep!);
          }
        }
    }
  }

  /// Duplicate a cycle
  void duplicateCycle(String id) {
    final cycle = _cycles[id];
    if (cycle == null) return;

    final newId = 'cycle_${DateTime.now().millisecondsSinceEpoch}';
    final json = cycle.toJson();
    json['id'] = newId;
    json['name'] = '${cycle.name} (Copy)';
    json['currentIndex'] = 0;

    _cycles[newId] = CycleAction.fromJson(json);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILT-IN CYCLE PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create built-in presets (skips already-present cycles)
  void loadPresets() {
    void _addIfAbsent(CycleAction cycle) {
      if (!_cycles.containsKey(cycle.id)) addCycle(cycle);
    }

    // Cycle: Monitor modes (Stereo → Mono → Left → Right)
    _addIfAbsent(CycleAction(
      id: 'preset_monitor_mode',
      name: 'Cycle Monitor Mode',
      description: 'Stereo → Mono → Left → Right',
      steps: [
        CycleStep.action(id: 's1', label: 'Stereo', actionName: 'setMonitorMode', params: {'mode': 'stereo'}),
        CycleStep.action(id: 's2', label: 'Mono', actionName: 'setMonitorMode', params: {'mode': 'mono'}),
        CycleStep.action(id: 's3', label: 'Left Only', actionName: 'setMonitorMode', params: {'mode': 'left'}),
        CycleStep.action(id: 's4', label: 'Right Only', actionName: 'setMonitorMode', params: {'mode': 'right'}),
      ],
    ));

    // Cycle: Grid resolution (1/4 → 1/8 → 1/16 → 1/32)
    _addIfAbsent(CycleAction(
      id: 'preset_grid_resolution',
      name: 'Cycle Grid Resolution',
      description: '1/4 → 1/8 → 1/16 → 1/32',
      steps: [
        CycleStep.action(id: 'g1', label: '1/4', actionName: 'setGridResolution', params: {'division': 4}),
        CycleStep.action(id: 'g2', label: '1/8', actionName: 'setGridResolution', params: {'division': 8}),
        CycleStep.action(id: 'g3', label: '1/16', actionName: 'setGridResolution', params: {'division': 16}),
        CycleStep.action(id: 'g4', label: '1/32', actionName: 'setGridResolution', params: {'division': 32}),
      ],
    ));

    // Cycle: Zoom presets (Fit All → Zoom to Selection → 1:1 → Wide)
    _addIfAbsent(CycleAction(
      id: 'preset_zoom_cycle',
      name: 'Cycle Zoom Level',
      description: 'Fit All → Selection → 1:1 → Wide',
      steps: [
        CycleStep.command(id: 'z1', label: 'Fit All', commandId: 'view.zoom_fit'),
        CycleStep.command(id: 'z2', label: 'Zoom to Selection', commandId: 'view.zoom_selection'),
        CycleStep.action(id: 'z3', label: '1:1 Zoom', actionName: 'setZoomLevel', params: {'level': 1.0}),
        CycleStep.action(id: 'z4', label: 'Wide View', actionName: 'setZoomLevel', params: {'level': 0.25}),
      ],
    ));

    // Conditional: Toggle mute with solo awareness
    _addIfAbsent(CycleAction(
      id: 'preset_smart_mute',
      name: 'Smart Mute Toggle',
      description: 'If soloed → unsolo, else toggle mute',
      steps: [
        CycleStep.conditional(
          id: 'sm1',
          label: 'Smart Mute',
          condition: CycleCondition(
            stateKey: 'selectedTrack.soloed',
            op: ConditionOp.equals,
            compareValue: 'true',
          ),
          thenStep: CycleStep.command(id: 'sm1t', label: 'Unsolo', commandId: 'mix.toggle_solo'),
          elseStep: CycleStep.command(id: 'sm1e', label: 'Toggle Mute', commandId: 'mix.toggle_mute'),
        ),
      ],
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
    'cycles': _cycles.values.map((c) => c.toJson()).toList(),
  };

  void fromJson(Map<String, dynamic> json) {
    _cycles.clear();
    final list = json['cycles'] as List<dynamic>?;
    if (list != null) {
      for (final item in list) {
        final cycle = CycleAction.fromJson(item as Map<String, dynamic>);
        _cycles[cycle.id] = cycle;
      }
    }
    notifyListeners();
  }
}
