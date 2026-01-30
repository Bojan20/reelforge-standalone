/// Test Automation Models
///
/// Data structures for automated SlotLab testing:
/// - Test scenarios with spin sequences
/// - Expected outcomes and assertions
/// - Test results and reports
/// - Batch test configurations
///
/// Created: 2026-01-30 (P4.11)

import 'dart:convert';

// ═══════════════════════════════════════════════════════════════════════════
// TEST STATUS & RESULTS
// ═══════════════════════════════════════════════════════════════════════════

/// Status of a test execution
enum TestStatus {
  pending('Pending', '⏳'),
  running('Running', '▶️'),
  passed('Passed', '✅'),
  failed('Failed', '❌'),
  skipped('Skipped', '⏭️'),
  error('Error', '⚠️'),
  timeout('Timeout', '⏱️');

  final String label;
  final String emoji;

  const TestStatus(this.label, this.emoji);

  bool get isTerminal =>
      this == passed || this == failed || this == skipped || this == error || this == timeout;

  bool get isSuccess => this == passed;
}

/// Type of assertion to validate
enum AssertionType {
  stageTriggered('Stage Triggered'),
  stageNotTriggered('Stage Not Triggered'),
  stageOrder('Stage Order'),
  stageCount('Stage Count'),
  winAmount('Win Amount'),
  winTier('Win Tier'),
  audioPlayed('Audio Played'),
  audioNotPlayed('Audio Not Played'),
  latencyUnder('Latency Under'),
  voiceCount('Voice Count'),
  custom('Custom');

  final String label;

  const AssertionType(this.label);
}

/// Comparison operator for assertions
enum ComparisonOp {
  equals('=='),
  notEquals('!='),
  greaterThan('>'),
  greaterOrEqual('>='),
  lessThan('<'),
  lessOrEqual('<='),
  contains('contains'),
  startsWith('startsWith'),
  endsWith('endsWith'),
  matches('matches');

  final String symbol;

  const ComparisonOp(this.symbol);
}

/// Single assertion within a test step
class TestAssertion {
  final String id;
  final AssertionType type;
  final String description;
  final String targetValue;
  final ComparisonOp comparison;
  final String expectedValue;
  final bool isRequired;

  const TestAssertion({
    required this.id,
    required this.type,
    required this.description,
    required this.targetValue,
    this.comparison = ComparisonOp.equals,
    required this.expectedValue,
    this.isRequired = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'description': description,
        'targetValue': targetValue,
        'comparison': comparison.name,
        'expectedValue': expectedValue,
        'isRequired': isRequired,
      };

  factory TestAssertion.fromJson(Map<String, dynamic> json) => TestAssertion(
        id: json['id'] as String,
        type: AssertionType.values.byName(json['type'] as String),
        description: json['description'] as String,
        targetValue: json['targetValue'] as String,
        comparison: ComparisonOp.values.byName(json['comparison'] as String? ?? 'equals'),
        expectedValue: json['expectedValue'] as String,
        isRequired: json['isRequired'] as bool? ?? true,
      );

  /// Factory constructors for common assertions
  factory TestAssertion.stageTriggered(String stageId, {String? id}) => TestAssertion(
        id: id ?? 'stage_triggered_$stageId',
        type: AssertionType.stageTriggered,
        description: 'Stage "$stageId" should be triggered',
        targetValue: stageId,
        expectedValue: 'true',
      );

  factory TestAssertion.stageNotTriggered(String stageId, {String? id}) => TestAssertion(
        id: id ?? 'stage_not_triggered_$stageId',
        type: AssertionType.stageNotTriggered,
        description: 'Stage "$stageId" should NOT be triggered',
        targetValue: stageId,
        expectedValue: 'false',
      );

  factory TestAssertion.winAmountEquals(double amount, {String? id}) => TestAssertion(
        id: id ?? 'win_amount_equals',
        type: AssertionType.winAmount,
        description: 'Win amount should equal $amount',
        targetValue: 'winAmount',
        comparison: ComparisonOp.equals,
        expectedValue: amount.toString(),
      );

  factory TestAssertion.winAmountGreaterThan(double amount, {String? id}) => TestAssertion(
        id: id ?? 'win_amount_gt',
        type: AssertionType.winAmount,
        description: 'Win amount should be greater than $amount',
        targetValue: 'winAmount',
        comparison: ComparisonOp.greaterThan,
        expectedValue: amount.toString(),
      );

  factory TestAssertion.latencyUnder(int maxMs, {String? id}) => TestAssertion(
        id: id ?? 'latency_under_$maxMs',
        type: AssertionType.latencyUnder,
        description: 'Audio latency should be under ${maxMs}ms',
        targetValue: 'latencyMs',
        comparison: ComparisonOp.lessThan,
        expectedValue: maxMs.toString(),
      );

  factory TestAssertion.stageCountEquals(String stageId, int count, {String? id}) =>
      TestAssertion(
        id: id ?? 'stage_count_$stageId',
        type: AssertionType.stageCount,
        description: 'Stage "$stageId" should trigger $count times',
        targetValue: stageId,
        comparison: ComparisonOp.equals,
        expectedValue: count.toString(),
      );
}

/// Result of evaluating a single assertion
class AssertionResult {
  final TestAssertion assertion;
  final bool passed;
  final String actualValue;
  final String? errorMessage;
  final DateTime evaluatedAt;

  AssertionResult({
    required this.assertion,
    required this.passed,
    required this.actualValue,
    this.errorMessage,
    DateTime? evaluatedAt,
  }) : evaluatedAt = evaluatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'assertion': assertion.toJson(),
        'passed': passed,
        'actualValue': actualValue,
        'errorMessage': errorMessage,
        'evaluatedAt': evaluatedAt.toIso8601String(),
      };

  factory AssertionResult.fromJson(Map<String, dynamic> json) => AssertionResult(
        assertion: TestAssertion.fromJson(json['assertion'] as Map<String, dynamic>),
        passed: json['passed'] as bool,
        actualValue: json['actualValue'] as String,
        errorMessage: json['errorMessage'] as String?,
        evaluatedAt: DateTime.parse(json['evaluatedAt'] as String),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// TEST STEPS & ACTIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Type of action to perform in a test step
enum TestActionType {
  spin('Spin'),
  spinForced('Forced Spin'),
  wait('Wait'),
  setSignal('Set Signal'),
  triggerStage('Trigger Stage'),
  stopPlayback('Stop Playback'),
  setRtpc('Set RTPC'),
  enterContext('Enter Context'),
  exitContext('Exit Context'),
  checkpoint('Checkpoint');

  final String label;

  const TestActionType(this.label);
}

/// A single action within a test step
class TestAction {
  final String id;
  final TestActionType type;
  final Map<String, dynamic> parameters;
  final String? description;

  const TestAction({
    required this.id,
    required this.type,
    this.parameters = const {},
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'parameters': parameters,
        'description': description,
      };

  factory TestAction.fromJson(Map<String, dynamic> json) => TestAction(
        id: json['id'] as String,
        type: TestActionType.values.byName(json['type'] as String),
        parameters: Map<String, dynamic>.from(json['parameters'] as Map? ?? {}),
        description: json['description'] as String?,
      );

  /// Factory constructors for common actions
  factory TestAction.spin({String? id}) => TestAction(
        id: id ?? 'spin_${DateTime.now().millisecondsSinceEpoch}',
        type: TestActionType.spin,
        description: 'Execute normal spin',
      );

  factory TestAction.spinForced(String outcome, {String? id}) => TestAction(
        id: id ?? 'spin_forced_$outcome',
        type: TestActionType.spinForced,
        parameters: {'outcome': outcome},
        description: 'Execute forced spin: $outcome',
      );

  factory TestAction.wait(int milliseconds, {String? id}) => TestAction(
        id: id ?? 'wait_$milliseconds',
        type: TestActionType.wait,
        parameters: {'ms': milliseconds},
        description: 'Wait ${milliseconds}ms',
      );

  factory TestAction.setSignal(String signalId, double value, {String? id}) => TestAction(
        id: id ?? 'set_signal_$signalId',
        type: TestActionType.setSignal,
        parameters: {'signalId': signalId, 'value': value},
        description: 'Set signal $signalId = $value',
      );

  factory TestAction.triggerStage(String stageId, {String? id}) => TestAction(
        id: id ?? 'trigger_$stageId',
        type: TestActionType.triggerStage,
        parameters: {'stageId': stageId},
        description: 'Trigger stage: $stageId',
      );

  factory TestAction.checkpoint(String name, {String? id}) => TestAction(
        id: id ?? 'checkpoint_$name',
        type: TestActionType.checkpoint,
        parameters: {'name': name},
        description: 'Checkpoint: $name',
      );
}

/// A single step in a test scenario
class TestStep {
  final String id;
  final String name;
  final String? description;
  final List<TestAction> actions;
  final List<TestAssertion> assertions;
  final int timeoutMs;
  final bool continueOnFailure;

  const TestStep({
    required this.id,
    required this.name,
    this.description,
    this.actions = const [],
    this.assertions = const [],
    this.timeoutMs = 30000,
    this.continueOnFailure = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'actions': actions.map((a) => a.toJson()).toList(),
        'assertions': assertions.map((a) => a.toJson()).toList(),
        'timeoutMs': timeoutMs,
        'continueOnFailure': continueOnFailure,
      };

  factory TestStep.fromJson(Map<String, dynamic> json) => TestStep(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        actions: (json['actions'] as List?)
                ?.map((a) => TestAction.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [],
        assertions: (json['assertions'] as List?)
                ?.map((a) => TestAssertion.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [],
        timeoutMs: json['timeoutMs'] as int? ?? 30000,
        continueOnFailure: json['continueOnFailure'] as bool? ?? false,
      );

  TestStep copyWith({
    String? id,
    String? name,
    String? description,
    List<TestAction>? actions,
    List<TestAssertion>? assertions,
    int? timeoutMs,
    bool? continueOnFailure,
  }) =>
      TestStep(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        actions: actions ?? this.actions,
        assertions: assertions ?? this.assertions,
        timeoutMs: timeoutMs ?? this.timeoutMs,
        continueOnFailure: continueOnFailure ?? this.continueOnFailure,
      );
}

/// Result of executing a test step
class TestStepResult {
  final TestStep step;
  final TestStatus status;
  final List<AssertionResult> assertionResults;
  final Duration duration;
  final String? errorMessage;
  final Map<String, dynamic> capturedData;
  final DateTime startedAt;
  final DateTime completedAt;

  TestStepResult({
    required this.step,
    required this.status,
    this.assertionResults = const [],
    required this.duration,
    this.errorMessage,
    this.capturedData = const {},
    required this.startedAt,
    DateTime? completedAt,
  }) : completedAt = completedAt ?? DateTime.now();

  bool get passed => status == TestStatus.passed;

  int get passedAssertions => assertionResults.where((r) => r.passed).length;

  int get failedAssertions => assertionResults.where((r) => !r.passed).length;

  Map<String, dynamic> toJson() => {
        'step': step.toJson(),
        'status': status.name,
        'assertionResults': assertionResults.map((r) => r.toJson()).toList(),
        'durationMs': duration.inMilliseconds,
        'errorMessage': errorMessage,
        'capturedData': capturedData,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt.toIso8601String(),
      };

  factory TestStepResult.fromJson(Map<String, dynamic> json) => TestStepResult(
        step: TestStep.fromJson(json['step'] as Map<String, dynamic>),
        status: TestStatus.values.byName(json['status'] as String),
        assertionResults: (json['assertionResults'] as List?)
                ?.map((r) => AssertionResult.fromJson(r as Map<String, dynamic>))
                .toList() ??
            [],
        duration: Duration(milliseconds: json['durationMs'] as int),
        errorMessage: json['errorMessage'] as String?,
        capturedData: Map<String, dynamic>.from(json['capturedData'] as Map? ?? {}),
        startedAt: DateTime.parse(json['startedAt'] as String),
        completedAt: DateTime.parse(json['completedAt'] as String),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// TEST SCENARIOS
// ═══════════════════════════════════════════════════════════════════════════

/// Category for organizing test scenarios
enum TestCategory {
  smoke('Smoke Tests'),
  regression('Regression Tests'),
  audio('Audio Tests'),
  performance('Performance Tests'),
  feature('Feature Tests'),
  integration('Integration Tests'),
  custom('Custom Tests');

  final String label;

  const TestCategory(this.label);
}

/// A complete test scenario with multiple steps
class TestScenario {
  final String id;
  final String name;
  final String? description;
  final TestCategory category;
  final List<TestStep> steps;
  final Map<String, dynamic> config;
  final List<String> tags;
  final bool isEnabled;
  final int version;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const TestScenario({
    required this.id,
    required this.name,
    this.description,
    this.category = TestCategory.custom,
    this.steps = const [],
    this.config = const {},
    this.tags = const [],
    this.isEnabled = true,
    this.version = 1,
    required this.createdAt,
    this.updatedAt,
  });

  int get stepCount => steps.length;

  int get assertionCount => steps.fold(0, (sum, step) => sum + step.assertions.length);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category.name,
        'steps': steps.map((s) => s.toJson()).toList(),
        'config': config,
        'tags': tags,
        'isEnabled': isEnabled,
        'version': version,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  String toJsonString({bool pretty = false}) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(toJson());
    }
    return jsonEncode(toJson());
  }

  factory TestScenario.fromJson(Map<String, dynamic> json) => TestScenario(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        category: TestCategory.values.byName(json['category'] as String? ?? 'custom'),
        steps: (json['steps'] as List?)
                ?.map((s) => TestStep.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        config: Map<String, dynamic>.from(json['config'] as Map? ?? {}),
        tags: (json['tags'] as List?)?.cast<String>() ?? [],
        isEnabled: json['isEnabled'] as bool? ?? true,
        version: json['version'] as int? ?? 1,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt:
            json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : null,
      );

  factory TestScenario.fromJsonString(String jsonString) =>
      TestScenario.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

  TestScenario copyWith({
    String? id,
    String? name,
    String? description,
    TestCategory? category,
    List<TestStep>? steps,
    Map<String, dynamic>? config,
    List<String>? tags,
    bool? isEnabled,
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      TestScenario(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        category: category ?? this.category,
        steps: steps ?? this.steps,
        config: config ?? this.config,
        tags: tags ?? this.tags,
        isEnabled: isEnabled ?? this.isEnabled,
        version: version ?? this.version,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// Result of executing a complete test scenario
class TestScenarioResult {
  final TestScenario scenario;
  final TestStatus status;
  final List<TestStepResult> stepResults;
  final Duration totalDuration;
  final String? errorMessage;
  final Map<String, dynamic> metadata;
  final DateTime startedAt;
  final DateTime completedAt;

  TestScenarioResult({
    required this.scenario,
    required this.status,
    this.stepResults = const [],
    required this.totalDuration,
    this.errorMessage,
    this.metadata = const {},
    required this.startedAt,
    DateTime? completedAt,
  }) : completedAt = completedAt ?? DateTime.now();

  bool get passed => status == TestStatus.passed;

  int get passedSteps => stepResults.where((r) => r.passed).length;

  int get failedSteps => stepResults.where((r) => !r.passed).length;

  int get totalAssertions =>
      stepResults.fold(0, (sum, r) => sum + r.assertionResults.length);

  int get passedAssertions =>
      stepResults.fold(0, (sum, r) => sum + r.passedAssertions);

  int get failedAssertions =>
      stepResults.fold(0, (sum, r) => sum + r.failedAssertions);

  double get passRate =>
      totalAssertions > 0 ? passedAssertions / totalAssertions : 0.0;

  Map<String, dynamic> toJson() => {
        'scenario': scenario.toJson(),
        'status': status.name,
        'stepResults': stepResults.map((r) => r.toJson()).toList(),
        'totalDurationMs': totalDuration.inMilliseconds,
        'errorMessage': errorMessage,
        'metadata': metadata,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt.toIso8601String(),
      };

  factory TestScenarioResult.fromJson(Map<String, dynamic> json) => TestScenarioResult(
        scenario: TestScenario.fromJson(json['scenario'] as Map<String, dynamic>),
        status: TestStatus.values.byName(json['status'] as String),
        stepResults: (json['stepResults'] as List?)
                ?.map((r) => TestStepResult.fromJson(r as Map<String, dynamic>))
                .toList() ??
            [],
        totalDuration: Duration(milliseconds: json['totalDurationMs'] as int),
        errorMessage: json['errorMessage'] as String?,
        metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? {}),
        startedAt: DateTime.parse(json['startedAt'] as String),
        completedAt: DateTime.parse(json['completedAt'] as String),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// TEST SUITE & BATCH EXECUTION
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration for test execution
class TestRunConfig {
  final bool stopOnFirstFailure;
  final int defaultTimeoutMs;
  final bool captureAudioEvents;
  final bool captureStageTrace;
  final bool enableRngLogging;
  final int parallelScenarios;
  final Map<String, dynamic> environment;

  const TestRunConfig({
    this.stopOnFirstFailure = false,
    this.defaultTimeoutMs = 30000,
    this.captureAudioEvents = true,
    this.captureStageTrace = true,
    this.enableRngLogging = true,
    this.parallelScenarios = 1,
    this.environment = const {},
  });

  Map<String, dynamic> toJson() => {
        'stopOnFirstFailure': stopOnFirstFailure,
        'defaultTimeoutMs': defaultTimeoutMs,
        'captureAudioEvents': captureAudioEvents,
        'captureStageTrace': captureStageTrace,
        'enableRngLogging': enableRngLogging,
        'parallelScenarios': parallelScenarios,
        'environment': environment,
      };

  factory TestRunConfig.fromJson(Map<String, dynamic> json) => TestRunConfig(
        stopOnFirstFailure: json['stopOnFirstFailure'] as bool? ?? false,
        defaultTimeoutMs: json['defaultTimeoutMs'] as int? ?? 30000,
        captureAudioEvents: json['captureAudioEvents'] as bool? ?? true,
        captureStageTrace: json['captureStageTrace'] as bool? ?? true,
        enableRngLogging: json['enableRngLogging'] as bool? ?? true,
        parallelScenarios: json['parallelScenarios'] as int? ?? 1,
        environment: Map<String, dynamic>.from(json['environment'] as Map? ?? {}),
      );

  static const TestRunConfig defaultConfig = TestRunConfig();
}

/// A test suite containing multiple scenarios
class TestSuite {
  final String id;
  final String name;
  final String? description;
  final List<TestScenario> scenarios;
  final TestRunConfig config;
  final DateTime createdAt;

  const TestSuite({
    required this.id,
    required this.name,
    this.description,
    this.scenarios = const [],
    this.config = TestRunConfig.defaultConfig,
    required this.createdAt,
  });

  int get scenarioCount => scenarios.length;

  int get enabledScenarioCount => scenarios.where((s) => s.isEnabled).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'scenarios': scenarios.map((s) => s.toJson()).toList(),
        'config': config.toJson(),
        'createdAt': createdAt.toIso8601String(),
      };

  String toJsonString({bool pretty = false}) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(toJson());
    }
    return jsonEncode(toJson());
  }

  factory TestSuite.fromJson(Map<String, dynamic> json) => TestSuite(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        scenarios: (json['scenarios'] as List?)
                ?.map((s) => TestScenario.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        config: json['config'] != null
            ? TestRunConfig.fromJson(json['config'] as Map<String, dynamic>)
            : TestRunConfig.defaultConfig,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  factory TestSuite.fromJsonString(String jsonString) =>
      TestSuite.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
}

/// Result of executing a complete test suite
class TestSuiteResult {
  final TestSuite suite;
  final TestStatus status;
  final List<TestScenarioResult> scenarioResults;
  final Duration totalDuration;
  final DateTime startedAt;
  final DateTime completedAt;

  TestSuiteResult({
    required this.suite,
    required this.status,
    this.scenarioResults = const [],
    required this.totalDuration,
    required this.startedAt,
    DateTime? completedAt,
  }) : completedAt = completedAt ?? DateTime.now();

  bool get passed => status == TestStatus.passed;

  int get passedScenarios => scenarioResults.where((r) => r.passed).length;

  int get failedScenarios => scenarioResults.where((r) => !r.passed).length;

  int get totalSteps =>
      scenarioResults.fold(0, (sum, r) => sum + r.stepResults.length);

  int get passedSteps =>
      scenarioResults.fold(0, (sum, r) => sum + r.passedSteps);

  double get passRate =>
      scenarioResults.isNotEmpty ? passedScenarios / scenarioResults.length : 0.0;

  Map<String, dynamic> toJson() => {
        'suite': suite.toJson(),
        'status': status.name,
        'scenarioResults': scenarioResults.map((r) => r.toJson()).toList(),
        'totalDurationMs': totalDuration.inMilliseconds,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt.toIso8601String(),
      };

  factory TestSuiteResult.fromJson(Map<String, dynamic> json) => TestSuiteResult(
        suite: TestSuite.fromJson(json['suite'] as Map<String, dynamic>),
        status: TestStatus.values.byName(json['status'] as String),
        scenarioResults: (json['scenarioResults'] as List?)
                ?.map((r) => TestScenarioResult.fromJson(r as Map<String, dynamic>))
                .toList() ??
            [],
        totalDuration: Duration(milliseconds: json['totalDurationMs'] as int),
        startedAt: DateTime.parse(json['startedAt'] as String),
        completedAt: DateTime.parse(json['completedAt'] as String),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// BUILT-IN TEST SCENARIOS
// ═══════════════════════════════════════════════════════════════════════════

/// Factory for built-in test scenarios
class BuiltInTestScenarios {
  BuiltInTestScenarios._();

  /// Smoke test: Basic spin cycle
  static TestScenario basicSpinCycle() => TestScenario(
        id: 'smoke_basic_spin',
        name: 'Basic Spin Cycle',
        description: 'Verifies basic spin functionality with audio triggers',
        category: TestCategory.smoke,
        tags: ['smoke', 'spin', 'audio'],
        createdAt: DateTime.now(),
        steps: [
          TestStep(
            id: 'step_1_spin',
            name: 'Execute Spin',
            actions: [TestAction.spin()],
            assertions: [
              TestAssertion.stageTriggered('SPIN_START'),
              TestAssertion.stageTriggered('REEL_STOP'),
              TestAssertion.stageTriggered('SPIN_END'),
            ],
          ),
        ],
      );

  /// Win tier test: Big Win
  static TestScenario bigWinTest() => TestScenario(
        id: 'win_big_win',
        name: 'Big Win Presentation',
        description: 'Tests big win audio sequence',
        category: TestCategory.audio,
        tags: ['win', 'big_win', 'audio'],
        createdAt: DateTime.now(),
        steps: [
          TestStep(
            id: 'step_1_force_big_win',
            name: 'Force Big Win',
            actions: [TestAction.spinForced('bigWin')],
            assertions: [
              TestAssertion.stageTriggered('WIN_PRESENT'),
              TestAssertion.stageTriggered('WIN_PRESENT_BIG'),
              TestAssertion.stageTriggered('ROLLUP_START'),
              TestAssertion.stageTriggered('ROLLUP_END'),
              TestAssertion.winAmountGreaterThan(0),
            ],
          ),
        ],
      );

  /// Feature test: Free Spins trigger
  static TestScenario freeSpinsTrigger() => TestScenario(
        id: 'feature_free_spins',
        name: 'Free Spins Trigger',
        description: 'Tests free spins feature activation',
        category: TestCategory.feature,
        tags: ['feature', 'free_spins'],
        createdAt: DateTime.now(),
        steps: [
          TestStep(
            id: 'step_1_trigger_fs',
            name: 'Trigger Free Spins',
            actions: [TestAction.spinForced('freeSpins')],
            assertions: [
              TestAssertion.stageTriggered('FEATURE_TRIGGER'),
              TestAssertion.stageTriggered('FREESPIN_INTRO'),
            ],
          ),
          TestStep(
            id: 'step_2_play_fs',
            name: 'Play Free Spin',
            actions: [
              TestAction.wait(2000),
              TestAction.spin(),
            ],
            assertions: [
              TestAssertion.stageTriggered('FREESPIN_SPIN_START'),
            ],
          ),
        ],
      );

  /// Performance test: Audio latency
  static TestScenario audioLatencyTest() => TestScenario(
        id: 'perf_audio_latency',
        name: 'Audio Latency Test',
        description: 'Verifies audio triggers within latency threshold',
        category: TestCategory.performance,
        tags: ['performance', 'latency', 'audio'],
        createdAt: DateTime.now(),
        steps: [
          TestStep(
            id: 'step_1_latency_check',
            name: 'Check Audio Latency',
            actions: [
              TestAction.spinForced('smallWin'),
            ],
            assertions: [
              TestAssertion.latencyUnder(50),
              TestAssertion.stageTriggered('WIN_PRESENT'),
            ],
          ),
        ],
      );

  /// Regression test: Cascade sequence
  static TestScenario cascadeSequence() => TestScenario(
        id: 'regression_cascade',
        name: 'Cascade Sequence',
        description: 'Tests cascade win sequence stages',
        category: TestCategory.regression,
        tags: ['regression', 'cascade'],
        createdAt: DateTime.now(),
        steps: [
          TestStep(
            id: 'step_1_cascade',
            name: 'Trigger Cascade',
            actions: [TestAction.spinForced('cascade')],
            assertions: [
              TestAssertion.stageTriggered('CASCADE_START'),
              TestAssertion.stageTriggered('CASCADE_STEP'),
              TestAssertion.stageTriggered('CASCADE_END'),
            ],
          ),
        ],
      );

  /// Get all built-in scenarios
  static List<TestScenario> all() => [
        basicSpinCycle(),
        bigWinTest(),
        freeSpinsTrigger(),
        audioLatencyTest(),
        cascadeSequence(),
      ];

  /// Get scenarios by category
  static List<TestScenario> byCategory(TestCategory category) =>
      all().where((s) => s.category == category).toList();
}
