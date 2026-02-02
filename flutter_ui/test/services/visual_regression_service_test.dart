/// Visual Regression Service Tests
///
/// Tests for the visual regression testing service.
/// Tests cover configuration, comparison logic, and session management.

import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge_ui/services/visual_regression_service.dart';

void main() {
  group('VisualRegressionConfig', () {
    test('default config has expected values', () {
      const config = VisualRegressionConfig();

      expect(config.goldenDirectory, 'test/visual_regression/goldens/slotlab');
      expect(config.captureDirectory, 'test/visual_regression/captures');
      expect(config.diffDirectory, 'test/visual_regression/diffs');
      expect(config.maxDiffThreshold, 0.001);
      expect(config.pixelRatio, 2.0);
      expect(config.autoUpdateMissingGoldens, false);
      expect(config.generateHtmlReport, true);
    });

    test('ci config is stricter than default', () {
      expect(VisualRegressionConfig.ci.maxDiffThreshold, lessThan(VisualRegressionConfig().maxDiffThreshold));
      expect(VisualRegressionConfig.ci.autoUpdateMissingGoldens, false);
    });

    test('local config is more lenient', () {
      expect(VisualRegressionConfig.local.maxDiffThreshold, greaterThan(VisualRegressionConfig.ci.maxDiffThreshold));
      expect(VisualRegressionConfig.local.autoUpdateMissingGoldens, true);
    });

    test('copyWith creates new config with overrides', () {
      const original = VisualRegressionConfig();
      final modified = original.copyWith(
        maxDiffThreshold: 0.05,
        autoUpdateMissingGoldens: true,
      );

      expect(modified.maxDiffThreshold, 0.05);
      expect(modified.autoUpdateMissingGoldens, true);
      expect(modified.goldenDirectory, original.goldenDirectory); // Unchanged
    });
  });

  group('SlotMachineState', () {
    test('all states have unique ids', () {
      final ids = SlotMachineState.values.map((s) => s.id).toSet();
      expect(ids.length, SlotMachineState.values.length);
    });

    test('goldenFileName returns expected format', () {
      expect(SlotMachineState.idle.goldenFileName, 'idle.png');
      expect(SlotMachineState.winBig.goldenFileName, 'win_big.png');
      expect(SlotMachineState.freeSpinsTrigger.goldenFileName, 'freespins_trigger.png');
    });

    test('goldenFileNameWithVariant includes variant', () {
      expect(
        SlotMachineState.idle.goldenFileNameWithVariant('dark'),
        'idle_dark.png',
      );
      expect(
        SlotMachineState.winMega.goldenFileNameWithVariant('5x3'),
        'win_mega_5x3.png',
      );
    });

    test('all states have descriptions', () {
      for (final state in SlotMachineState.values) {
        expect(state.description.isNotEmpty, true);
      }
    });
  });

  group('ImageComparisonResult', () {
    test('factory failed creates failed result', () {
      final result = ImageComparisonResult.failed(
        testName: 'test_failed',
        errorMessage: 'Something went wrong',
      );

      expect(result.passed, false);
      expect(result.testName, 'test_failed');
      expect(result.errorMessage, 'Something went wrong');
      expect(result.diffPercent, 1.0);
    });

    test('factory identical creates passed result', () {
      final result = ImageComparisonResult.identical(
        testName: 'test_identical',
        totalPixels: 1000,
        goldenPath: '/path/to/golden.png',
      );

      expect(result.passed, true);
      expect(result.testName, 'test_identical');
      expect(result.diffPercent, 0.0);
      expect(result.diffPixelCount, 0);
      expect(result.totalPixelCount, 1000);
    });

    test('toJson serializes all fields', () {
      final result = ImageComparisonResult(
        testName: 'serialize_test',
        passed: true,
        diffPercent: 0.0001,
        diffPixelCount: 10,
        totalPixelCount: 100000,
        goldenPath: '/golden.png',
        capturePath: '/capture.png',
        timestamp: DateTime(2026, 2, 2),
        maxColorDiff: 5,
      );

      final json = result.toJson();

      expect(json['testName'], 'serialize_test');
      expect(json['passed'], true);
      expect(json['diffPercent'], 0.0001);
      expect(json['diffPixelCount'], 10);
      expect(json['totalPixelCount'], 100000);
      expect(json['maxColorDiff'], 5);
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'testName': 'deserialize_test',
        'passed': false,
        'diffPercent': 0.05,
        'diffPixelCount': 500,
        'totalPixelCount': 10000,
        'timestamp': '2026-02-02T12:00:00.000Z',
        'maxColorDiff': 128,
      };

      final result = ImageComparisonResult.fromJson(json);

      expect(result.testName, 'deserialize_test');
      expect(result.passed, false);
      expect(result.diffPercent, 0.05);
      expect(result.diffPixelCount, 500);
      expect(result.maxColorDiff, 128);
    });

    test('toString shows pass/fail status', () {
      final passed = ImageComparisonResult.identical(
        testName: 'pass_test',
        totalPixels: 100,
      );
      final failed = ImageComparisonResult.failed(
        testName: 'fail_test',
        errorMessage: 'Error occurred',
      );

      expect(passed.toString(), contains('PASS'));
      expect(failed.toString(), contains('FAIL'));
      expect(failed.toString(), contains('Error occurred'));
    });
  });

  group('VisualRegressionSession', () {
    test('initializes with default values', () {
      final session = VisualRegressionSession(
        config: const VisualRegressionConfig(),
      );

      expect(session.results.isEmpty, true);
      expect(session.totalTests, 0);
      expect(session.passedTests, 0);
      expect(session.failedTests, 0);
      expect(session.passRate, 1.0); // No tests = 100% pass rate
      expect(session.allPassed, true);
      expect(session.endTime, isNull);
    });

    test('addResult tracks results correctly', () {
      final session = VisualRegressionSession(
        config: const VisualRegressionConfig(),
      );

      session.addResult(ImageComparisonResult.identical(
        testName: 'test1',
        totalPixels: 100,
      ));
      session.addResult(ImageComparisonResult.failed(
        testName: 'test2',
        errorMessage: 'Failed',
      ));
      session.addResult(ImageComparisonResult.identical(
        testName: 'test3',
        totalPixels: 100,
      ));

      expect(session.totalTests, 3);
      expect(session.passedTests, 2);
      expect(session.failedTests, 1);
      expect(session.passRate, closeTo(0.666, 0.01));
      expect(session.allPassed, false);
    });

    test('complete sets endTime', () {
      final session = VisualRegressionSession(
        config: const VisualRegressionConfig(),
      );

      expect(session.endTime, isNull);

      session.complete();

      expect(session.endTime, isNotNull);
      expect(session.duration, isNotNull);
    });

    test('toJson serializes session', () {
      final session = VisualRegressionSession(
        sessionId: 'test_session_123',
        config: const VisualRegressionConfig(),
      );

      session.addResult(ImageComparisonResult.identical(
        testName: 'test1',
        totalPixels: 100,
      ));
      session.complete();

      final json = session.toJson();

      expect(json['sessionId'], 'test_session_123');
      expect(json['totalTests'], 1);
      expect(json['passedTests'], 1);
      expect(json['failedTests'], 0);
      expect(json['results'], isA<List>());
      expect((json['results'] as List).length, 1);
    });
  });

  group('VisualRegressionService', () {
    test('singleton instance exists', () {
      final service = VisualRegressionService.instance;
      expect(service, isNotNull);
      expect(VisualRegressionService.instance, same(service));
    });

    test('configure updates config', () {
      final service = VisualRegressionService.instance;
      final originalConfig = service.config;

      service.configure(VisualRegressionConfig.ci);

      expect(service.config.maxDiffThreshold, VisualRegressionConfig.ci.maxDiffThreshold);

      // Restore original config
      service.configure(originalConfig);
    });

    test('startSession creates session and sets running state', () {
      final service = VisualRegressionService.instance;

      expect(service.isRunning, false);

      final session = service.startSession(sessionId: 'test_session');

      expect(service.isRunning, true);
      expect(service.currentSession, isNotNull);
      expect(service.currentSession?.sessionId, 'test_session');

      service.endSession();
    });

    test('endSession completes session and stores in history', () {
      final service = VisualRegressionService.instance;

      final session = service.startSession(sessionId: 'history_test');
      session.addResult(ImageComparisonResult.identical(
        testName: 'test1',
        totalPixels: 100,
      ));

      service.endSession();

      expect(service.isRunning, false);
      expect(service.currentSession, isNull);
      expect(service.sessionHistory.isNotEmpty, true);
      expect(service.sessionHistory.first.sessionId, 'history_test');
    });

    test('startSession throws if already running', () {
      final service = VisualRegressionService.instance;

      service.startSession();

      expect(
        () => service.startSession(),
        throwsA(isA<StateError>()),
      );

      service.endSession();
    });

    test('clearHistory removes all sessions', () {
      final service = VisualRegressionService.instance;

      // Add a session
      service.startSession();
      service.endSession();

      expect(service.sessionHistory.isNotEmpty, true);

      service.clearHistory();

      expect(service.sessionHistory.isEmpty, true);
    });

    test('latestSession returns most recent session', () {
      final service = VisualRegressionService.instance;

      service.clearHistory();

      expect(service.latestSession, isNull);

      service.startSession(sessionId: 'session_1');
      service.endSession();

      service.startSession(sessionId: 'session_2');
      service.endSession();

      expect(service.latestSession?.sessionId, 'session_2');
    });

    test('progress tracking works during session', () {
      final service = VisualRegressionService.instance;

      expect(service.progress, isNotNull);

      service.startSession();

      expect(service.progress, 0.0);

      service.endSession();

      expect(service.progress, 1.0);
    });
  });
}
