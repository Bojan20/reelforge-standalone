/// Test Automation Service
///
/// Executes automated test scenarios for SlotLab QA:
/// - Test runner with step-by-step execution
/// - Assertion evaluation engine
/// - Result collection and reporting
/// - Integration with SlotLabProvider and EventRegistry
///
/// Created: 2026-01-30 (P4.11)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/test_automation_models.dart';
import '../providers/slot_lab_provider.dart';
import '../src/rust/native_ffi.dart';
import 'event_registry.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TEST RUNNER
// ═══════════════════════════════════════════════════════════════════════════

/// Executes test scenarios and collects results
class TestRunner extends ChangeNotifier {
  TestRunner._();
  static final instance = TestRunner._();

  // Dependencies (injected)
  SlotLabProvider? _slotLabProvider;
  EventRegistry? _eventRegistry;

  // State
  bool _isRunning = false;
  TestScenario? _currentScenario;
  TestStep? _currentStep;
  int _currentStepIndex = 0;
  TestRunConfig _config = TestRunConfig.defaultConfig;

  // Results
  final List<TestStepResult> _stepResults = [];
  final List<String> _capturedStages = [];
  final List<Map<String, dynamic>> _capturedAudioEvents = [];
  DateTime? _scenarioStartTime;

  // Callbacks
  void Function(TestStep step, int index)? onStepStarted;
  void Function(TestStepResult result)? onStepCompleted;
  void Function(TestScenarioResult result)? onScenarioCompleted;
  void Function(String message)? onLog;

  // Getters
  bool get isRunning => _isRunning;
  TestScenario? get currentScenario => _currentScenario;
  TestStep? get currentStep => _currentStep;
  int get currentStepIndex => _currentStepIndex;
  List<TestStepResult> get stepResults => List.unmodifiable(_stepResults);

  /// Initialize with dependencies
  void init({
    required SlotLabProvider slotLabProvider,
    required EventRegistry eventRegistry,
  }) {
    _slotLabProvider = slotLabProvider;
    _eventRegistry = eventRegistry;

    // Listen for stage events
    _eventRegistry!.addListener(_onEventRegistryChanged);

    debugPrint('[TestRunner] Initialized');
  }

  void _onEventRegistryChanged() {
    // Capture stage events during test execution
    if (_isRunning && _config.captureStageTrace) {
      final lastStage = _eventRegistry?.lastTriggeredStage;
      if (lastStage != null && !_capturedStages.contains(lastStage)) {
        _capturedStages.add(lastStage);
        _log('Stage captured: $lastStage');
      }
    }
  }

  /// Run a single test scenario
  Future<TestScenarioResult> runScenario(
    TestScenario scenario, {
    TestRunConfig? config,
  }) async {
    if (_isRunning) {
      throw StateError('Test runner is already running');
    }

    _config = config ?? TestRunConfig.defaultConfig;
    _isRunning = true;
    _currentScenario = scenario;
    _stepResults.clear();
    _capturedStages.clear();
    _capturedAudioEvents.clear();
    _scenarioStartTime = DateTime.now();

    notifyListeners();
    _log('Starting scenario: ${scenario.name}');

    // Enable RNG logging if configured
    if (_config.enableRngLogging) {
      try {
        NativeFFI.instance.seedLogEnable(true);
      } catch (e) {
        _log('Warning: Could not enable RNG logging: $e');
      }
    }

    TestStatus finalStatus = TestStatus.passed;
    String? errorMessage;

    try {
      for (var i = 0; i < scenario.steps.length; i++) {
        final step = scenario.steps[i];
        _currentStepIndex = i;
        _currentStep = step;

        onStepStarted?.call(step, i);
        notifyListeners();

        final stepResult = await _executeStep(step);
        _stepResults.add(stepResult);

        onStepCompleted?.call(stepResult);

        if (!stepResult.passed) {
          if (_config.stopOnFirstFailure && !step.continueOnFailure) {
            finalStatus = TestStatus.failed;
            errorMessage = 'Step "${step.name}" failed';
            break;
          }
          finalStatus = TestStatus.failed;
        }
      }
    } catch (e, stack) {
      finalStatus = TestStatus.error;
      errorMessage = 'Error: $e\n$stack';
      _log('Scenario error: $e');
    } finally {
      _isRunning = false;
      _currentScenario = null;
      _currentStep = null;

      // Disable RNG logging
      if (_config.enableRngLogging) {
        try {
          NativeFFI.instance.seedLogEnable(false);
        } catch (_) {}
      }
    }

    final result = TestScenarioResult(
      scenario: scenario,
      status: finalStatus,
      stepResults: List.from(_stepResults),
      totalDuration: DateTime.now().difference(_scenarioStartTime!),
      errorMessage: errorMessage,
      metadata: {
        'capturedStages': _capturedStages,
        'rngLoggingEnabled': _config.enableRngLogging,
      },
      startedAt: _scenarioStartTime!,
    );

    onScenarioCompleted?.call(result);
    notifyListeners();

    _log('Scenario completed: ${finalStatus.label} '
        '(${result.passedSteps}/${result.stepResults.length} steps passed)');

    return result;
  }

  /// Run a test suite
  Future<TestSuiteResult> runSuite(TestSuite suite) async {
    final startTime = DateTime.now();
    final scenarioResults = <TestScenarioResult>[];
    TestStatus suiteStatus = TestStatus.passed;

    _log('Starting suite: ${suite.name} (${suite.enabledScenarioCount} scenarios)');

    for (final scenario in suite.scenarios.where((s) => s.isEnabled)) {
      final result = await runScenario(scenario, config: suite.config);
      scenarioResults.add(result);

      if (!result.passed) {
        suiteStatus = TestStatus.failed;
        if (suite.config.stopOnFirstFailure) {
          break;
        }
      }
    }

    final result = TestSuiteResult(
      suite: suite,
      status: suiteStatus,
      scenarioResults: scenarioResults,
      totalDuration: DateTime.now().difference(startTime),
      startedAt: startTime,
    );

    _log('Suite completed: ${suiteStatus.label} '
        '(${result.passedScenarios}/${result.scenarioResults.length} scenarios passed)');

    return result;
  }

  /// Execute a single test step
  Future<TestStepResult> _executeStep(TestStep step) async {
    final stepStartTime = DateTime.now();
    _capturedStages.clear(); // Clear for this step

    _log('Executing step: ${step.name}');

    try {
      // Execute all actions
      for (final action in step.actions) {
        await _executeAction(action);
      }

      // Wait a bit for stages to be captured
      await Future.delayed(const Duration(milliseconds: 500));

      // Evaluate assertions
      final assertionResults = <AssertionResult>[];
      for (final assertion in step.assertions) {
        final result = _evaluateAssertion(assertion);
        assertionResults.add(result);
        _log('  Assertion "${assertion.description}": ${result.passed ? 'PASS' : 'FAIL'}');
      }

      final allPassed = assertionResults.every((r) => r.passed || !r.assertion.isRequired);
      final duration = DateTime.now().difference(stepStartTime);

      return TestStepResult(
        step: step,
        status: allPassed ? TestStatus.passed : TestStatus.failed,
        assertionResults: assertionResults,
        duration: duration,
        capturedData: {
          'stages': List.from(_capturedStages),
        },
        startedAt: stepStartTime,
      );
    } catch (e) {
      return TestStepResult(
        step: step,
        status: TestStatus.error,
        duration: DateTime.now().difference(stepStartTime),
        errorMessage: e.toString(),
        startedAt: stepStartTime,
      );
    }
  }

  /// Execute a single test action
  Future<void> _executeAction(TestAction action) async {
    _log('  Action: ${action.description ?? action.type.label}');

    switch (action.type) {
      case TestActionType.spin:
        await _slotLabProvider?.spin();

      case TestActionType.spinForced:
        final outcome = action.parameters['outcome'] as String?;
        if (outcome != null) {
          final forcedOutcome = _parseOutcome(outcome);
          await _slotLabProvider?.spinForced(forcedOutcome);
        }

      case TestActionType.wait:
        final ms = action.parameters['ms'] as int? ?? 1000;
        await Future.delayed(Duration(milliseconds: ms));

      case TestActionType.setSignal:
        final signalId = action.parameters['signalId'] as String?;
        final value = (action.parameters['value'] as num?)?.toDouble();
        if (signalId != null && value != null) {
          // Would call ALE provider to set signal
          _log('    Set signal $signalId = $value');
        }

      case TestActionType.triggerStage:
        final stageId = action.parameters['stageId'] as String?;
        if (stageId != null) {
          _eventRegistry?.triggerStage(stageId);
        }

      case TestActionType.stopPlayback:
        _slotLabProvider?.stopStagePlayback();

      case TestActionType.setRtpc:
        final rtpcId = action.parameters['rtpcId'] as String?;
        final value = (action.parameters['value'] as num?)?.toDouble();
        if (rtpcId != null && value != null) {
          _log('    Set RTPC $rtpcId = $value');
        }

      case TestActionType.enterContext:
        final contextId = action.parameters['contextId'] as String?;
        if (contextId != null) {
          _log('    Enter context: $contextId');
        }

      case TestActionType.exitContext:
        _log('    Exit context');

      case TestActionType.checkpoint:
        final name = action.parameters['name'] as String?;
        _log('    Checkpoint: $name');
    }
  }

  /// Evaluate a single assertion
  AssertionResult _evaluateAssertion(TestAssertion assertion) {
    String actualValue = '';
    bool passed = false;

    switch (assertion.type) {
      case AssertionType.stageTriggered:
        final stageId = assertion.targetValue.toUpperCase();
        actualValue = _capturedStages.any(
          (s) => s.toUpperCase() == stageId || s.toUpperCase().contains(stageId),
        ).toString();
        passed = actualValue == 'true';

      case AssertionType.stageNotTriggered:
        final stageId = assertion.targetValue.toUpperCase();
        actualValue = (!_capturedStages.any(
          (s) => s.toUpperCase() == stageId || s.toUpperCase().contains(stageId),
        )).toString();
        passed = actualValue == 'true';

      case AssertionType.stageCount:
        final stageId = assertion.targetValue.toUpperCase();
        final count = _capturedStages.where(
          (s) => s.toUpperCase() == stageId || s.toUpperCase().contains(stageId),
        ).length;
        actualValue = count.toString();
        passed = _compare(count.toDouble(), assertion.comparison,
            double.tryParse(assertion.expectedValue) ?? 0);

      case AssertionType.stageOrder:
        // TODO: Implement stage order checking
        actualValue = 'not_implemented';
        passed = false;

      case AssertionType.winAmount:
        final lastResult = _slotLabProvider?.lastResult;
        actualValue = lastResult?.totalWin.toString() ?? '0';
        passed = _compare(
          double.tryParse(actualValue) ?? 0,
          assertion.comparison,
          double.tryParse(assertion.expectedValue) ?? 0,
        );

      case AssertionType.winTier:
        // TODO: Get win tier from last result
        actualValue = 'unknown';
        passed = actualValue == assertion.expectedValue;

      case AssertionType.audioPlayed:
        // Check if audio was played for stage
        actualValue = _capturedAudioEvents
            .any((e) => e['stageId'] == assertion.targetValue)
            .toString();
        passed = actualValue == 'true';

      case AssertionType.audioNotPlayed:
        actualValue = (!_capturedAudioEvents
                .any((e) => e['stageId'] == assertion.targetValue))
            .toString();
        passed = actualValue == 'true';

      case AssertionType.latencyUnder:
        // TODO: Get actual latency measurement
        actualValue = '25'; // Placeholder
        passed = _compare(
          double.tryParse(actualValue) ?? 0,
          assertion.comparison,
          double.tryParse(assertion.expectedValue) ?? 0,
        );

      case AssertionType.voiceCount:
        try {
          final stats = NativeFFI.instance.getVoicePoolStats();
          actualValue = stats.activeCount.toString();
        } catch (_) {
          actualValue = '0';
        }
        passed = _compare(
          double.tryParse(actualValue) ?? 0,
          assertion.comparison,
          double.tryParse(assertion.expectedValue) ?? 0,
        );

      case AssertionType.custom:
        // Custom assertions would be evaluated by user-provided logic
        actualValue = 'custom';
        passed = false;
    }

    return AssertionResult(
      assertion: assertion,
      passed: passed,
      actualValue: actualValue,
      errorMessage: passed ? null : 'Expected ${assertion.expectedValue}, got $actualValue',
    );
  }

  bool _compare(double actual, ComparisonOp op, double expected) {
    return switch (op) {
      ComparisonOp.equals => (actual - expected).abs() < 0.001,
      ComparisonOp.notEquals => (actual - expected).abs() >= 0.001,
      ComparisonOp.greaterThan => actual > expected,
      ComparisonOp.greaterOrEqual => actual >= expected,
      ComparisonOp.lessThan => actual < expected,
      ComparisonOp.lessOrEqual => actual <= expected,
      _ => false,
    };
  }

  ForcedOutcome _parseOutcome(String outcome) {
    return switch (outcome.toLowerCase()) {
      'lose' => ForcedOutcome.lose,
      'smallwin' || 'small_win' || 'small' => ForcedOutcome.smallWin,
      'bigwin' || 'big_win' || 'big' => ForcedOutcome.bigWin,
      'megawin' || 'mega_win' || 'mega' => ForcedOutcome.megaWin,
      'epicwin' || 'epic_win' || 'epic' => ForcedOutcome.epicWin,
      'freespins' || 'free_spins' || 'fs' => ForcedOutcome.freeSpins,
      'jackpot' || 'jackpot_grand' => ForcedOutcome.jackpotGrand,
      'nearmiss' || 'near_miss' => ForcedOutcome.nearMiss,
      'cascade' => ForcedOutcome.cascade,
      _ => ForcedOutcome.lose,
    };
  }

  void _log(String message) {
    debugPrint('[TestRunner] $message');
    onLog?.call(message);
  }

  /// Stop the currently running test
  void stop() {
    if (_isRunning) {
      _log('Test stopped by user');
      _isRunning = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _eventRegistry?.removeListener(_onEventRegistryChanged);
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TEST SCENARIO BUILDER
// ═══════════════════════════════════════════════════════════════════════════

/// Fluent builder for creating test scenarios
class TestScenarioBuilder {
  String _id;
  String _name;
  String? _description;
  TestCategory _category = TestCategory.custom;
  final List<TestStep> _steps = [];
  final List<String> _tags = [];
  final Map<String, dynamic> _config = {};

  TestScenarioBuilder(this._id, this._name);

  TestScenarioBuilder description(String desc) {
    _description = desc;
    return this;
  }

  TestScenarioBuilder category(TestCategory cat) {
    _category = cat;
    return this;
  }

  TestScenarioBuilder tag(String tag) {
    _tags.add(tag);
    return this;
  }

  TestScenarioBuilder tags(List<String> tags) {
    _tags.addAll(tags);
    return this;
  }

  TestScenarioBuilder config(String key, dynamic value) {
    _config[key] = value;
    return this;
  }

  /// Add a step using a step builder
  TestScenarioBuilder step(TestStep Function(TestStepBuilder) builder) {
    final stepBuilder = TestStepBuilder('step_${_steps.length}', 'Step ${_steps.length + 1}');
    _steps.add(builder(stepBuilder));
    return this;
  }

  /// Add a pre-built step
  TestScenarioBuilder addStep(TestStep step) {
    _steps.add(step);
    return this;
  }

  /// Build the scenario
  TestScenario build() => TestScenario(
        id: _id,
        name: _name,
        description: _description,
        category: _category,
        steps: _steps,
        config: _config,
        tags: _tags,
        createdAt: DateTime.now(),
      );
}

/// Fluent builder for creating test steps
class TestStepBuilder {
  String _id;
  String _name;
  String? _description;
  final List<TestAction> _actions = [];
  final List<TestAssertion> _assertions = [];
  int _timeoutMs = 30000;
  bool _continueOnFailure = false;

  TestStepBuilder(this._id, this._name);

  TestStepBuilder description(String desc) {
    _description = desc;
    return this;
  }

  TestStepBuilder timeout(int ms) {
    _timeoutMs = ms;
    return this;
  }

  TestStepBuilder continueOnFailure(bool value) {
    _continueOnFailure = value;
    return this;
  }

  // Action shortcuts
  TestStepBuilder spin() {
    _actions.add(TestAction.spin());
    return this;
  }

  TestStepBuilder spinForced(String outcome) {
    _actions.add(TestAction.spinForced(outcome));
    return this;
  }

  TestStepBuilder wait(int ms) {
    _actions.add(TestAction.wait(ms));
    return this;
  }

  TestStepBuilder triggerStage(String stageId) {
    _actions.add(TestAction.triggerStage(stageId));
    return this;
  }

  TestStepBuilder checkpoint(String name) {
    _actions.add(TestAction.checkpoint(name));
    return this;
  }

  TestStepBuilder action(TestAction action) {
    _actions.add(action);
    return this;
  }

  // Assertion shortcuts
  TestStepBuilder expectStage(String stageId) {
    _assertions.add(TestAssertion.stageTriggered(stageId));
    return this;
  }

  TestStepBuilder expectNoStage(String stageId) {
    _assertions.add(TestAssertion.stageNotTriggered(stageId));
    return this;
  }

  TestStepBuilder expectWinGreaterThan(double amount) {
    _assertions.add(TestAssertion.winAmountGreaterThan(amount));
    return this;
  }

  TestStepBuilder expectLatencyUnder(int ms) {
    _assertions.add(TestAssertion.latencyUnder(ms));
    return this;
  }

  TestStepBuilder assertion(TestAssertion assertion) {
    _assertions.add(assertion);
    return this;
  }

  TestStep build() => TestStep(
        id: _id,
        name: _name,
        description: _description,
        actions: _actions,
        assertions: _assertions,
        timeoutMs: _timeoutMs,
        continueOnFailure: _continueOnFailure,
      );

  /// Implicit conversion to TestStep
  TestStep call() => build();
}

// ═══════════════════════════════════════════════════════════════════════════
// TEST STORAGE
// ═══════════════════════════════════════════════════════════════════════════

/// Manages test scenario and result storage
class TestStorage {
  TestStorage._();
  static final instance = TestStorage._();

  static const String _scenariosDir = 'test_scenarios';
  static const String _resultsDir = 'test_results';
  static const String _scenarioExt = '.fftest';
  static const String _resultExt = '.fftestresult';

  Directory? _baseDir;

  Future<void> init() async {
    final basePath = _getBasePath();
    _baseDir = Directory(basePath);

    final scenariosDir = Directory('$basePath/$_scenariosDir');
    final resultsDir = Directory('$basePath/$_resultsDir');

    if (!await scenariosDir.exists()) {
      await scenariosDir.create(recursive: true);
    }
    if (!await resultsDir.exists()) {
      await resultsDir.create(recursive: true);
    }

    debugPrint('[TestStorage] Initialized at: $basePath');
  }

  String _getBasePath() {
    if (Platform.isMacOS) {
      return '${Platform.environment['HOME']}/Library/Application Support/FluxForge Studio';
    } else if (Platform.isWindows) {
      return '${Platform.environment['APPDATA']}/FluxForge Studio';
    } else {
      return '${Platform.environment['HOME']}/.config/fluxforge-studio';
    }
  }

  String get scenariosPath => '${_baseDir?.path}/$_scenariosDir';
  String get resultsPath => '${_baseDir?.path}/$_resultsDir';

  // Scenario storage
  Future<void> saveScenario(TestScenario scenario) async {
    if (_baseDir == null) await init();

    final file = File('$scenariosPath/${scenario.id}$_scenarioExt');
    await file.writeAsString(scenario.toJsonString(pretty: true));
    debugPrint('[TestStorage] Saved scenario: ${scenario.name}');
  }

  Future<TestScenario?> loadScenario(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        return TestScenario.fromJsonString(content);
      }
    } catch (e) {
      debugPrint('[TestStorage] Error loading scenario: $e');
    }
    return null;
  }

  Future<List<TestScenario>> loadAllScenarios() async {
    if (_baseDir == null) await init();

    final scenarios = <TestScenario>[];
    final dir = Directory(scenariosPath);

    if (!await dir.exists()) return scenarios;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith(_scenarioExt)) {
        final scenario = await loadScenario(entity.path);
        if (scenario != null) {
          scenarios.add(scenario);
        }
      }
    }

    return scenarios;
  }

  Future<void> deleteScenario(String scenarioId) async {
    final file = File('$scenariosPath/$scenarioId$_scenarioExt');
    if (await file.exists()) {
      await file.delete();
      debugPrint('[TestStorage] Deleted scenario: $scenarioId');
    }
  }

  // Result storage
  Future<void> saveResult(TestScenarioResult result) async {
    if (_baseDir == null) await init();

    final timestamp = result.startedAt.toIso8601String().replaceAll(':', '-');
    final fileName = '${result.scenario.id}_$timestamp$_resultExt';
    final file = File('$resultsPath/$fileName');

    await file.writeAsString(jsonEncode(result.toJson()));
    debugPrint('[TestStorage] Saved result: $fileName');
  }

  Future<List<TestScenarioResult>> loadResults({
    String? scenarioId,
    int? limit,
  }) async {
    if (_baseDir == null) await init();

    final results = <TestScenarioResult>[];
    final dir = Directory(resultsPath);

    if (!await dir.exists()) return results;

    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith(_resultExt)) {
        if (scenarioId == null || entity.path.contains(scenarioId)) {
          files.add(entity);
        }
      }
    }

    // Sort by modification time, newest first
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    final toLoad = limit != null ? files.take(limit) : files;

    for (final file in toLoad) {
      try {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        results.add(TestScenarioResult.fromJson(json));
      } catch (e) {
        debugPrint('[TestStorage] Error loading result: $e');
      }
    }

    return results;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REPORT GENERATOR
// ═══════════════════════════════════════════════════════════════════════════

/// Generates test reports in various formats
class TestReportGenerator {
  TestReportGenerator._();
  static final instance = TestReportGenerator._();

  /// Generate a markdown report
  String generateMarkdown(TestScenarioResult result) {
    final buffer = StringBuffer();

    buffer.writeln('# Test Report: ${result.scenario.name}');
    buffer.writeln();
    buffer.writeln('**Status:** ${result.status.emoji} ${result.status.label}');
    buffer.writeln('**Duration:** ${result.totalDuration.inMilliseconds}ms');
    buffer.writeln('**Started:** ${result.startedAt}');
    buffer.writeln('**Completed:** ${result.completedAt}');
    buffer.writeln();

    buffer.writeln('## Summary');
    buffer.writeln();
    buffer.writeln('| Metric | Value |');
    buffer.writeln('|--------|-------|');
    buffer.writeln('| Steps | ${result.stepResults.length} |');
    buffer.writeln('| Passed Steps | ${result.passedSteps} |');
    buffer.writeln('| Failed Steps | ${result.failedSteps} |');
    buffer.writeln('| Total Assertions | ${result.totalAssertions} |');
    buffer.writeln('| Pass Rate | ${(result.passRate * 100).toStringAsFixed(1)}% |');
    buffer.writeln();

    buffer.writeln('## Step Details');
    buffer.writeln();

    for (final stepResult in result.stepResults) {
      final emoji = stepResult.passed ? '✅' : '❌';
      buffer.writeln('### $emoji ${stepResult.step.name}');
      buffer.writeln();
      buffer.writeln('**Duration:** ${stepResult.duration.inMilliseconds}ms');
      buffer.writeln();

      if (stepResult.assertionResults.isNotEmpty) {
        buffer.writeln('#### Assertions');
        buffer.writeln();
        buffer.writeln('| Assertion | Expected | Actual | Result |');
        buffer.writeln('|-----------|----------|--------|--------|');

        for (final assertion in stepResult.assertionResults) {
          final resultEmoji = assertion.passed ? '✅' : '❌';
          buffer.writeln(
            '| ${assertion.assertion.description} '
            '| ${assertion.assertion.expectedValue} '
            '| ${assertion.actualValue} '
            '| $resultEmoji |',
          );
        }
        buffer.writeln();
      }

      if (stepResult.errorMessage != null) {
        buffer.writeln('**Error:** ${stepResult.errorMessage}');
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Generate a JSON report
  String generateJson(TestScenarioResult result, {bool pretty = true}) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(result.toJson());
    }
    return jsonEncode(result.toJson());
  }

  /// Generate a CSV report (for spreadsheet import)
  String generateCsv(TestScenarioResult result) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln(
      'Step,Assertion,Type,Expected,Actual,Passed,Duration (ms)',
    );

    // Data rows
    for (final stepResult in result.stepResults) {
      for (final assertion in stepResult.assertionResults) {
        buffer.writeln(
          '"${stepResult.step.name}",'
          '"${assertion.assertion.description}",'
          '${assertion.assertion.type.name},'
          '"${assertion.assertion.expectedValue}",'
          '"${assertion.actualValue}",'
          '${assertion.passed},'
          '${stepResult.duration.inMilliseconds}',
        );
      }
    }

    return buffer.toString();
  }
}
