/// Feature Test Scenarios Service (P12.1.21)
///
/// Pre-built test scenarios for slot game audio validation.
/// Features:
/// - One-click trigger for common scenarios
/// - Big Win, Free Spins, Jackpot, Cascade sequences
/// - Audio coverage validation
/// - Custom scenario builder
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

// =============================================================================
// SCENARIO MODELS
// =============================================================================

/// Type of test scenario
enum ScenarioType {
  spin('Spin', 'Basic spin cycle'),
  bigWin('Big Win', 'Win celebration sequence'),
  freeSpins('Free Spins', 'Free spins feature'),
  bonus('Bonus', 'Bonus game sequence'),
  jackpot('Jackpot', 'Jackpot win sequence'),
  cascade('Cascade', 'Cascading wins'),
  anticipation('Anticipation', 'Anticipation buildup'),
  holdAndWin('Hold & Win', 'Hold and win feature'),
  custom('Custom', 'User-defined scenario');

  final String displayName;
  final String description;
  const ScenarioType(this.displayName, this.description);
}

/// A single stage trigger in a scenario
class ScenarioStep {
  final String stageName;
  final int delayMs;        // Delay before this step
  final Map<String, dynamic> payload;
  final String? description;

  const ScenarioStep({
    required this.stageName,
    this.delayMs = 0,
    this.payload = const {},
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'stageName': stageName,
    'delayMs': delayMs,
    'payload': payload,
    'description': description,
  };

  factory ScenarioStep.fromJson(Map<String, dynamic> json) {
    final payloadRaw = json['payload'];
    final Map<String, dynamic> payload = payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : {};
    return ScenarioStep(
      stageName: json['stageName'] as String? ?? '',
      delayMs: json['delayMs'] as int? ?? 0,
      payload: payload,
      description: json['description'] as String?,
    );
  }
}

/// Complete test scenario
class TestScenario {
  final String id;
  final String name;
  final String description;
  final ScenarioType type;
  final List<ScenarioStep> steps;
  final List<String> requiredStages; // Stages that must have audio assigned
  final bool isBuiltIn;
  final DateTime? createdAt;

  const TestScenario({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.steps,
    this.requiredStages = const [],
    this.isBuiltIn = false,
    this.createdAt,
  });

  int get totalDurationMs => steps.fold(0, (sum, step) => sum + step.delayMs);

  int get stepCount => steps.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'type': type.name,
    'steps': steps.map((s) => s.toJson()).toList(),
    'requiredStages': requiredStages,
    'isBuiltIn': isBuiltIn,
    'createdAt': createdAt?.toIso8601String(),
  };

  factory TestScenario.fromJson(Map<String, dynamic> json) {
    return TestScenario(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: ScenarioType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => ScenarioType.custom,
      ),
      steps: (json['steps'] as List<dynamic>?)
          ?.map((e) => ScenarioStep.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      requiredStages: (json['requiredStages'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? [],
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }
}

/// Result of scenario validation
class ScenarioValidationResult {
  final String scenarioId;
  final bool passed;
  final List<String> missingStages;
  final List<String> triggeredStages;
  final int totalSteps;
  final int successfulSteps;
  final String? errorMessage;

  const ScenarioValidationResult({
    required this.scenarioId,
    required this.passed,
    this.missingStages = const [],
    this.triggeredStages = const [],
    this.totalSteps = 0,
    this.successfulSteps = 0,
    this.errorMessage,
  });

  double get successRate => totalSteps > 0 ? successfulSteps / totalSteps : 0.0;
}

// =============================================================================
// BUILT-IN SCENARIOS
// =============================================================================

class BuiltInScenarios {
  static const basicSpin = TestScenario(
    id: 'basic_spin',
    name: 'Basic Spin',
    description: 'Standard spin sequence with reel stops',
    type: ScenarioType.spin,
    isBuiltIn: true,
    requiredStages: ['SPIN_START', 'REEL_SPIN_LOOP', 'REEL_STOP_0', 'REEL_STOP_1', 'REEL_STOP_2', 'REEL_STOP_3', 'REEL_STOP_4', 'SPIN_END'],
    steps: [
      ScenarioStep(stageName: 'SPIN_START', delayMs: 0),
      ScenarioStep(stageName: 'REEL_SPIN_LOOP', delayMs: 100),
      ScenarioStep(stageName: 'REEL_STOP_0', delayMs: 500),
      ScenarioStep(stageName: 'REEL_STOP_1', delayMs: 370),
      ScenarioStep(stageName: 'REEL_STOP_2', delayMs: 370),
      ScenarioStep(stageName: 'REEL_STOP_3', delayMs: 370),
      ScenarioStep(stageName: 'REEL_STOP_4', delayMs: 370),
      ScenarioStep(stageName: 'SPIN_END', delayMs: 200),
    ],
  );

  static const bigWin = TestScenario(
    id: 'big_win',
    name: 'Big Win Celebration',
    description: 'Big win presentation with rollup',
    type: ScenarioType.bigWin,
    isBuiltIn: true,
    requiredStages: ['WIN_PRESENT_BIG', 'ROLLUP_START', 'ROLLUP_TICK', 'ROLLUP_END', 'BIG_WIN_LOOP'],
    steps: [
      ScenarioStep(stageName: 'WIN_PRESENT_BIG', delayMs: 0, payload: {'winAmount': 500, 'winRatio': 10}),
      ScenarioStep(stageName: 'BIG_WIN_LOOP', delayMs: 200),
      ScenarioStep(stageName: 'ROLLUP_START', delayMs: 500),
      ScenarioStep(stageName: 'ROLLUP_TICK', delayMs: 100),
      ScenarioStep(stageName: 'ROLLUP_TICK', delayMs: 100),
      ScenarioStep(stageName: 'ROLLUP_TICK', delayMs: 100),
      ScenarioStep(stageName: 'ROLLUP_TICK', delayMs: 100),
      ScenarioStep(stageName: 'ROLLUP_TICK', delayMs: 100),
      ScenarioStep(stageName: 'ROLLUP_END', delayMs: 200),
    ],
  );

  static const megaWin = TestScenario(
    id: 'mega_win',
    name: 'Mega Win Celebration',
    description: 'Mega win with extended celebration',
    type: ScenarioType.bigWin,
    isBuiltIn: true,
    requiredStages: ['WIN_PRESENT_MEGA', 'BIG_WIN_TIER_3', 'ROLLUP_START', 'ROLLUP_TICK', 'ROLLUP_END'],
    steps: [
      ScenarioStep(stageName: 'WIN_PRESENT_MEGA', delayMs: 0, payload: {'winAmount': 2000, 'winRatio': 40}),
      ScenarioStep(stageName: 'BIG_WIN_TIER_3', delayMs: 300),
      ScenarioStep(stageName: 'ROLLUP_START', delayMs: 500),
      ScenarioStep(stageName: 'ROLLUP_TICK', delayMs: 80),
      ScenarioStep(stageName: 'ROLLUP_TICK', delayMs: 80),
      ScenarioStep(stageName: 'ROLLUP_TICK', delayMs: 80),
      ScenarioStep(stageName: 'ROLLUP_TICK', delayMs: 80),
      ScenarioStep(stageName: 'ROLLUP_TICK', delayMs: 80),
      ScenarioStep(stageName: 'ROLLUP_TICK', delayMs: 80),
      ScenarioStep(stageName: 'ROLLUP_TICK', delayMs: 80),
      ScenarioStep(stageName: 'ROLLUP_TICK', delayMs: 80),
      ScenarioStep(stageName: 'ROLLUP_END', delayMs: 300),
    ],
  );

  static const freeSpinsTrigger = TestScenario(
    id: 'free_spins_trigger',
    name: 'Free Spins Trigger',
    description: 'Free spins feature trigger sequence',
    type: ScenarioType.freeSpins,
    isBuiltIn: true,
    requiredStages: ['FS_TRIGGER', 'FS_INTRO', 'FS_MUSIC', 'FS_SPIN_START', 'FS_SPIN_END'],
    steps: [
      ScenarioStep(stageName: 'SCATTER_LAND', delayMs: 0, payload: {'count': 3}),
      ScenarioStep(stageName: 'FS_TRIGGER', delayMs: 500),
      ScenarioStep(stageName: 'FS_INTRO', delayMs: 800),
      ScenarioStep(stageName: 'FS_MUSIC', delayMs: 1500),
      ScenarioStep(stageName: 'FS_SPIN_START', delayMs: 1000),
      ScenarioStep(stageName: 'FS_SPIN_END', delayMs: 2000),
    ],
  );

  static const cascade = TestScenario(
    id: 'cascade',
    name: 'Cascade Sequence',
    description: 'Cascading wins with multiple steps',
    type: ScenarioType.cascade,
    isBuiltIn: true,
    requiredStages: ['CASCADE_START', 'CASCADE_STEP', 'CASCADE_END'],
    steps: [
      ScenarioStep(stageName: 'CASCADE_START', delayMs: 0),
      ScenarioStep(stageName: 'CASCADE_STEP', delayMs: 400, payload: {'step': 1}),
      ScenarioStep(stageName: 'CASCADE_STEP', delayMs: 400, payload: {'step': 2}),
      ScenarioStep(stageName: 'CASCADE_STEP', delayMs: 400, payload: {'step': 3}),
      ScenarioStep(stageName: 'CASCADE_END', delayMs: 500),
    ],
  );

  static const anticipation = TestScenario(
    id: 'anticipation',
    name: 'Anticipation Buildup',
    description: 'Scatter anticipation on multiple reels',
    type: ScenarioType.anticipation,
    isBuiltIn: true,
    requiredStages: ['ANTICIPATION_ON', 'ANTICIPATION_TENSION_R2_L1', 'ANTICIPATION_OFF'],
    steps: [
      ScenarioStep(stageName: 'SPIN_START', delayMs: 0),
      ScenarioStep(stageName: 'REEL_STOP_0', delayMs: 600, payload: {'hasScatter': true}),
      ScenarioStep(stageName: 'REEL_STOP_1', delayMs: 370, payload: {'hasScatter': true}),
      ScenarioStep(stageName: 'ANTICIPATION_ON', delayMs: 100, payload: {'reelIndex': 2}),
      ScenarioStep(stageName: 'ANTICIPATION_TENSION_R2_L1', delayMs: 200),
      ScenarioStep(stageName: 'REEL_STOP_2', delayMs: 800),
      ScenarioStep(stageName: 'ANTICIPATION_OFF', delayMs: 100),
    ],
  );

  static const jackpot = TestScenario(
    id: 'jackpot',
    name: 'Jackpot Win',
    description: 'Grand jackpot win sequence',
    type: ScenarioType.jackpot,
    isBuiltIn: true,
    requiredStages: ['JACKPOT_TRIGGER', 'JACKPOT_REVEAL', 'JACKPOT_PRESENT'],
    steps: [
      ScenarioStep(stageName: 'JACKPOT_TRIGGER', delayMs: 0, payload: {'tier': 'grand'}),
      ScenarioStep(stageName: 'JACKPOT_BUILDUP', delayMs: 500),
      ScenarioStep(stageName: 'JACKPOT_REVEAL', delayMs: 2000, payload: {'tier': 'grand'}),
      ScenarioStep(stageName: 'JACKPOT_PRESENT', delayMs: 1500, payload: {'amount': 10000}),
      ScenarioStep(stageName: 'JACKPOT_CELEBRATION', delayMs: 3000),
    ],
  );

  static const holdAndWin = TestScenario(
    id: 'hold_and_win',
    name: 'Hold & Win',
    description: 'Hold and win feature trigger',
    type: ScenarioType.holdAndWin,
    isBuiltIn: true,
    requiredStages: ['HOLD_TRIGGER', 'HOLD_SPIN', 'HOLD_LAND'],
    steps: [
      ScenarioStep(stageName: 'HOLD_TRIGGER', delayMs: 0, payload: {'coins': 6}),
      ScenarioStep(stageName: 'HOLD_INTRO', delayMs: 500),
      ScenarioStep(stageName: 'HOLD_SPIN', delayMs: 1000),
      ScenarioStep(stageName: 'HOLD_LAND', delayMs: 500, payload: {'newCoins': 2}),
      ScenarioStep(stageName: 'HOLD_SPIN', delayMs: 300),
      ScenarioStep(stageName: 'HOLD_LAND', delayMs: 500, payload: {'newCoins': 1}),
      ScenarioStep(stageName: 'HOLD_END', delayMs: 500),
    ],
  );

  static List<TestScenario> get all => [
    basicSpin,
    bigWin,
    megaWin,
    freeSpinsTrigger,
    cascade,
    anticipation,
    jackpot,
    holdAndWin,
  ];
}

// =============================================================================
// FEATURE TEST SCENARIOS SERVICE — Singleton
// =============================================================================

class FeatureTestScenariosService extends ChangeNotifier {
  static final FeatureTestScenariosService _instance = FeatureTestScenariosService._();
  static FeatureTestScenariosService get instance => _instance;

  FeatureTestScenariosService._();

  final List<TestScenario> _customScenarios = [];
  TestScenario? _runningScenario;
  int _currentStepIndex = -1;
  bool _isCancelled = false;
  final Set<String> _triggeredStages = {};

  // Callback for stage triggering (to be set by consumer)
  void Function(String stageName, Map<String, dynamic> payload)? onTriggerStage;

  // ─── Getters ────────────────────────────────────────────────────────────────

  List<TestScenario> get builtInScenarios => BuiltInScenarios.all;

  List<TestScenario> get customScenarios => List.unmodifiable(_customScenarios);

  List<TestScenario> get allScenarios => [...builtInScenarios, ..._customScenarios];

  bool get isRunning => _runningScenario != null;

  TestScenario? get runningScenario => _runningScenario;

  int get currentStepIndex => _currentStepIndex;

  double get progress {
    if (_runningScenario == null) return 0.0;
    return (_currentStepIndex + 1) / _runningScenario!.steps.length;
  }

  // ─── Scenario Execution ─────────────────────────────────────────────────────

  /// Run a scenario by triggering its stages with timing
  Future<ScenarioValidationResult> runScenario(TestScenario scenario) async {
    if (_runningScenario != null) {
      return ScenarioValidationResult(
        scenarioId: scenario.id,
        passed: false,
        errorMessage: 'Another scenario is already running',
      );
    }

    _runningScenario = scenario;
    _currentStepIndex = -1;
    _isCancelled = false;
    _triggeredStages.clear();
    notifyListeners();


    int successfulSteps = 0;

    for (var i = 0; i < scenario.steps.length && !_isCancelled; i++) {
      final step = scenario.steps[i];
      _currentStepIndex = i;
      notifyListeners();

      // Wait for delay
      if (step.delayMs > 0) {
        await Future.delayed(Duration(milliseconds: step.delayMs));
      }

      if (_isCancelled) break;

      // Trigger stage
      try {
        onTriggerStage?.call(step.stageName, step.payload);
        _triggeredStages.add(step.stageName);
        successfulSteps++;
      } catch (e) { /* ignored */ }
    }

    // Calculate missing stages
    final missingStages = scenario.requiredStages
        .where((s) => !_triggeredStages.contains(s))
        .toList();

    final passed = !_isCancelled && missingStages.isEmpty && successfulSteps == scenario.steps.length;

    _runningScenario = null;
    _currentStepIndex = -1;
    notifyListeners();


    return ScenarioValidationResult(
      scenarioId: scenario.id,
      passed: passed,
      missingStages: missingStages,
      triggeredStages: _triggeredStages.toList(),
      totalSteps: scenario.steps.length,
      successfulSteps: successfulSteps,
    );
  }

  /// Cancel running scenario
  void cancelScenario() {
    if (_runningScenario != null) {
      _isCancelled = true;
    }
  }

  // ─── Custom Scenarios ───────────────────────────────────────────────────────

  void addCustomScenario(TestScenario scenario) {
    _customScenarios.add(scenario);
    notifyListeners();
  }

  void removeCustomScenario(String scenarioId) {
    _customScenarios.removeWhere((s) => s.id == scenarioId);
    notifyListeners();
  }

  // ─── Validation ─────────────────────────────────────────────────────────────

  /// Check if all required stages have audio assigned
  List<String> validateScenarioCoverage(
    TestScenario scenario,
    Set<String> assignedStages,
  ) {
    return scenario.requiredStages
        .where((s) => !assignedStages.contains(s))
        .toList();
  }
}
