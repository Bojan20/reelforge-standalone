/// FluxMacro Provider Tests — FM-46
///
/// Tests FluxMacroProvider models, state management, and serialization.
@Tags(['provider'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/fluxmacro_provider.dart';

void main() {
  group('FluxMacroRunResult', () {
    test('fromJson parses all fields', () {
      final json = {
        'success': true,
        'game_id': 'GoldenPantheon',
        'seed': 42,
        'run_hash': 'abcdef1234567890abcdef1234567890',
        'duration_ms': 1500,
        'qa_passed': 4,
        'qa_failed': 0,
        'artifacts': ['adb.md', 'profile.json', 'manifest.json'],
        'warnings': ['Missing theme specification'],
        'errors': [],
      };

      final result = FluxMacroRunResult.fromJson(json);

      expect(result.success, true);
      expect(result.gameId, 'GoldenPantheon');
      expect(result.seed, 42);
      expect(result.runHash, 'abcdef1234567890abcdef1234567890');
      expect(result.durationMs, 1500);
      expect(result.qaPassed, 4);
      expect(result.qaFailed, 0);
      expect(result.artifacts.length, 3);
      expect(result.warnings.length, 1);
      expect(result.errors, isEmpty);
    });

    test('fromJson handles missing fields with defaults', () {
      final result = FluxMacroRunResult.fromJson({});

      expect(result.success, false);
      expect(result.gameId, '');
      expect(result.seed, 0);
      expect(result.runHash, '');
      expect(result.durationMs, 0);
      expect(result.qaPassed, 0);
      expect(result.qaFailed, 0);
      expect(result.artifacts, isEmpty);
      expect(result.warnings, isEmpty);
      expect(result.errors, isEmpty);
    });

    test('qaTotal computes correctly', () {
      final result = FluxMacroRunResult.fromJson({
        'qa_passed': 3,
        'qa_failed': 1,
      });

      expect(result.qaTotal, 4);
    });

    test('shortHash returns first 16 chars', () {
      final result = FluxMacroRunResult.fromJson({
        'run_hash': 'abcdef1234567890fedcba9876543210',
      });

      expect(result.shortHash, 'abcdef1234567890');
    });

    test('shortHash handles short hashes', () {
      final result = FluxMacroRunResult.fromJson({
        'run_hash': 'abc',
      });

      expect(result.shortHash, 'abc');
    });

    test('shortHash handles empty hash', () {
      final result = FluxMacroRunResult.fromJson({
        'run_hash': '',
      });

      expect(result.shortHash, '');
    });
  });

  group('FluxMacroHistoryEntry', () {
    test('fromJson parses all fields', () {
      final json = {
        'run_id': '2026-03-01T12-00-00',
        'macro_name': 'build_release',
        'game_id': 'GoldenPantheon',
        'success': true,
        'timestamp': '2026-03-01T12:00:00Z',
        'duration_ms': 2000,
        'run_hash': 'abc123def456',
      };

      final entry = FluxMacroHistoryEntry.fromJson(json);

      expect(entry.runId, '2026-03-01T12-00-00');
      expect(entry.macroName, 'build_release');
      expect(entry.gameId, 'GoldenPantheon');
      expect(entry.success, true);
      expect(entry.timestamp, '2026-03-01T12:00:00Z');
      expect(entry.durationMs, 2000);
      expect(entry.runHash, 'abc123def456');
    });

    test('fromJson handles missing fields', () {
      final entry = FluxMacroHistoryEntry.fromJson({});

      expect(entry.runId, '');
      expect(entry.macroName, '');
      expect(entry.gameId, '');
      expect(entry.success, false);
      expect(entry.timestamp, '');
      expect(entry.durationMs, 0);
      expect(entry.runHash, '');
    });
  });

  group('FluxMacroStepInfo', () {
    test('fromJson parses all fields', () {
      final json = {
        'name': 'adb.generate',
        'description': 'Generate Audio Design Brief',
        'estimated_ms': 500,
      };

      final step = FluxMacroStepInfo.fromJson(json);

      expect(step.name, 'adb.generate');
      expect(step.description, 'Generate Audio Design Brief');
      expect(step.estimatedMs, 500);
    });

    test('fromJson handles missing fields', () {
      final step = FluxMacroStepInfo.fromJson({});

      expect(step.name, '');
      expect(step.description, '');
      expect(step.estimatedMs, 0);
    });
  });

  group('FluxMacroRunState', () {
    test('all states exist', () {
      expect(FluxMacroRunState.values, containsAll([
        FluxMacroRunState.idle,
        FluxMacroRunState.running,
        FluxMacroRunState.completed,
        FluxMacroRunState.failed,
        FluxMacroRunState.cancelled,
      ]));
    });

    test('has 5 states', () {
      expect(FluxMacroRunState.values.length, 5);
    });
  });

  group('FluxMacroProvider lifecycle', () {
    test('initial state is correct', () {
      final provider = FluxMacroProvider();

      expect(provider.initialized, false);
      expect(provider.runState, FluxMacroRunState.idle);
      expect(provider.lastResult, isNull);
      expect(provider.progress, 0.0);
      expect(provider.currentStep, isNull);
      expect(provider.isRunning, false);
      expect(provider.steps, isEmpty);
      expect(provider.history, isEmpty);
      expect(provider.stepCount, 0);
    });

    test('isRunning reflects running state', () {
      // Can't fully test without FFI, but we verify the getter logic
      final provider = FluxMacroProvider();
      expect(provider.isRunning, false);
    });

    test('dispose does not throw', () {
      final provider = FluxMacroProvider();
      expect(() => provider.dispose(), returnsNormally);
    });

    test('shutdown resets all state', () {
      final provider = FluxMacroProvider();
      provider.shutdown();

      expect(provider.initialized, false);
      expect(provider.runState, FluxMacroRunState.idle);
      expect(provider.lastResult, isNull);
      expect(provider.progress, 0.0);
      expect(provider.currentStep, isNull);
      expect(provider.steps, isEmpty);
      expect(provider.history, isEmpty);
    });

    test('runYaml returns null when not initialized', () async {
      final provider = FluxMacroProvider();
      final result = await provider.runYaml('macro: test', '/tmp');
      expect(result, isNull);
    });

    test('runFile returns null when not initialized', () async {
      final provider = FluxMacroProvider();
      final result = await provider.runFile('/tmp/test.ffmacro.yaml');
      expect(result, isNull);
    });

    test('validate returns null when not initialized', () {
      final provider = FluxMacroProvider();
      final result = provider.validate('macro: test');
      expect(result, isNull);
    });

    test('cancel does nothing when not running', () {
      final provider = FluxMacroProvider();
      // Should not throw
      provider.cancel();
      expect(provider.runState, FluxMacroRunState.idle);
    });

    test('getQaResults returns null when not initialized', () {
      final provider = FluxMacroProvider();
      expect(provider.getQaResults(), isNull);
    });

    test('getLogs returns null when not initialized', () {
      final provider = FluxMacroProvider();
      expect(provider.getLogs(), isNull);
    });
  });
}
