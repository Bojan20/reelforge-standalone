import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/cortex_intelligence_loop.dart';
import 'package:fluxforge_ui/services/ai_mixing_service.dart';

void main() {
  group('CortexIntelligenceLoop', () {
    late CortexIntelligenceLoop loop;

    setUp(() {
      loop = CortexIntelligenceLoop.instance;
      loop.stop(); // ensure clean state
    });

    test('singleton instance', () {
      final a = CortexIntelligenceLoop.instance;
      final b = CortexIntelligenceLoop.instance;
      expect(identical(a, b), isTrue);
    });

    test('initial state is not running', () {
      expect(loop.isRunning, isFalse);
      expect(loop.isAnalyzing, isFalse);
      expect(loop.history, isEmpty);
      expect(loop.totalCycles, 0);
    });

    test('start without mixer does nothing', () {
      loop.start();
      expect(loop.isRunning, isFalse);
    });

    test('runOnce without mixer returns null', () async {
      final result = await loop.runOnce();
      expect(result, isNull);
    });

    test('acceptance rate starts at 0', () {
      expect(loop.acceptanceRate, 0.0);
    });

    test('recordApplied increments counter', () {
      final before = loop.appliedSuggestions;
      loop.recordApplied();
      expect(loop.appliedSuggestions, before + 1);
    });

    test('IntelligenceCycleResult hasCriticalIssues', () {
      final noCritical = IntelligenceCycleResult(
        timestamp: DateTime.now(),
        tracksAnalyzed: 5,
        suggestionsGenerated: 3,
        criticalIssues: 0,
        mixScore: 85.0,
        detectedGenre: GenreProfile.pop,
        analysisTime: const Duration(milliseconds: 120),
      );
      expect(noCritical.hasCriticalIssues, isFalse);

      final withCritical = IntelligenceCycleResult(
        timestamp: DateTime.now(),
        tracksAnalyzed: 5,
        suggestionsGenerated: 3,
        criticalIssues: 2,
        mixScore: 45.0,
        detectedGenre: GenreProfile.rock,
        analysisTime: const Duration(milliseconds: 200),
      );
      expect(withCritical.hasCriticalIssues, isTrue);
    });

    test('IntelligenceCycleResult toString', () {
      final result = IntelligenceCycleResult(
        timestamp: DateTime.now(),
        tracksAnalyzed: 8,
        suggestionsGenerated: 5,
        criticalIssues: 1,
        mixScore: 72.0,
        detectedGenre: GenreProfile.electronic,
        analysisTime: const Duration(milliseconds: 150),
      );

      final str = result.toString();
      expect(str, contains('8 tracks'));
      expect(str, contains('score=72.0'));
      expect(str, contains('5 suggestions'));
      expect(str, contains('1 critical'));
    });

    test('stop is idempotent', () {
      loop.stop();
      loop.stop();
      expect(loop.isRunning, isFalse);
    });
  });
}
