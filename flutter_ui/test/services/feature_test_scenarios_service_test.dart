/// Feature Test Scenarios Service Tests (P12.1.21)
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/feature_test_scenarios_service.dart';

void main() {
  group('ScenarioStep', () {
    test('creates with required fields', () {
      const step = ScenarioStep(stageName: 'SPIN_START');

      expect(step.stageName, 'SPIN_START');
      expect(step.delayMs, 0);
      expect(step.payload, isEmpty);
    });

    test('toJson serializes all fields', () {
      const step = ScenarioStep(
        stageName: 'WIN_PRESENT',
        delayMs: 500,
        payload: {'amount': 100},
        description: 'Win presentation',
      );
      final json = step.toJson();

      expect(json['stageName'], 'WIN_PRESENT');
      expect(json['delayMs'], 500);
      expect(json['payload']['amount'], 100);
      expect(json['description'], 'Win presentation');
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'stageName': 'ROLLUP_TICK',
        'delayMs': 100,
        'payload': {},
      };
      final step = ScenarioStep.fromJson(json);

      expect(step.stageName, 'ROLLUP_TICK');
      expect(step.delayMs, 100);
    });
  });

  group('TestScenario', () {
    test('totalDurationMs sums step delays', () {
      const scenario = TestScenario(
        id: 'test_1',
        name: 'Test',
        description: 'Test scenario',
        type: ScenarioType.spin,
        steps: [
          ScenarioStep(stageName: 'A', delayMs: 100),
          ScenarioStep(stageName: 'B', delayMs: 200),
          ScenarioStep(stageName: 'C', delayMs: 300),
        ],
      );

      expect(scenario.totalDurationMs, 600);
    });

    test('stepCount returns correct count', () {
      const scenario = TestScenario(
        id: 'test_1',
        name: 'Test',
        description: 'Test scenario',
        type: ScenarioType.spin,
        steps: [
          ScenarioStep(stageName: 'A'),
          ScenarioStep(stageName: 'B'),
        ],
      );

      expect(scenario.stepCount, 2);
    });

    test('toJson/fromJson roundtrip', () {
      const scenario = TestScenario(
        id: 'test_1',
        name: 'Test Scenario',
        description: 'Description',
        type: ScenarioType.bigWin,
        requiredStages: ['STAGE_A', 'STAGE_B'],
        steps: [
          ScenarioStep(stageName: 'STAGE_A', delayMs: 100),
          ScenarioStep(stageName: 'STAGE_B', delayMs: 200),
        ],
      );
      final json = scenario.toJson();
      final restored = TestScenario.fromJson(json);

      expect(restored.id, scenario.id);
      expect(restored.name, scenario.name);
      expect(restored.type, scenario.type);
      expect(restored.steps.length, scenario.steps.length);
      expect(restored.requiredStages, scenario.requiredStages);
    });
  });

  group('BuiltInScenarios', () {
    test('has 8 built-in scenarios', () {
      expect(BuiltInScenarios.all.length, 8);
    });

    test('all scenarios have steps', () {
      for (final scenario in BuiltInScenarios.all) {
        expect(scenario.steps, isNotEmpty);
        expect(scenario.isBuiltIn, true);
      }
    });

    test('scenario types are diverse', () {
      final types = BuiltInScenarios.all.map((s) => s.type).toSet();
      expect(types.length, greaterThanOrEqualTo(6));
    });

    test('basic spin scenario has correct flow', () {
      final spin = BuiltInScenarios.basicSpin;
      final stageNames = spin.steps.map((s) => s.stageName).toList();

      expect(stageNames.first, 'SPIN_START');
      expect(stageNames.last, 'SPIN_END');
      expect(stageNames, contains('REEL_STOP_0'));
      expect(stageNames, contains('REEL_STOP_4'));
    });
  });

  group('ScenarioValidationResult', () {
    test('calculates success rate', () {
      const result = ScenarioValidationResult(
        scenarioId: 'test',
        passed: true,
        totalSteps: 10,
        successfulSteps: 8,
      );

      expect(result.successRate, 0.8);
    });

    test('success rate is 0 when no steps', () {
      const result = ScenarioValidationResult(
        scenarioId: 'test',
        passed: false,
        totalSteps: 0,
        successfulSteps: 0,
      );

      expect(result.successRate, 0.0);
    });
  });
}
