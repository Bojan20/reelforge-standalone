import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/aurexis_qa.dart';

void main() {
  group('AurexisQaEngine', () {
    test('full suite returns checks for all categories', () {
      final report = AurexisQaEngine.runFullSuite(
        engineInitialized: true,
        rtp: 95.0,
        fatigueIndex: 0.3,
        escalationMultiplier: 2.0,
        energyDensity: 0.5,
        voiceCount: 8,
        stereoWidth: 1.0,
        memoryUsedMb: 3.0,
        memoryBudgetMb: 6.0,
        isDeterministic: true,
        jurisdictionCode: 'UKGC',
        profileId: 'calm_classic',
      );

      expect(report.totalCount, greaterThan(0));
      expect(report.checks, isNotEmpty);

      // Should have checks for each category
      final categories = report.checks.map((c) => c.category).toSet();
      expect(categories, contains(QaCategory.config));
      expect(categories, contains(QaCategory.coverage));
      expect(categories, contains(QaCategory.determinism));
      expect(categories, contains(QaCategory.performance));
      expect(categories, contains(QaCategory.compliance));
      expect(categories, contains(QaCategory.audioQuality));
    });

    test('healthy state passes all checks', () {
      final report = AurexisQaEngine.runFullSuite(
        engineInitialized: true,
        rtp: 95.0,
        fatigueIndex: 0.2,
        escalationMultiplier: 1.5,
        energyDensity: 0.4,
        voiceCount: 8,
        stereoWidth: 1.0,
        memoryUsedMb: 2.0,
        memoryBudgetMb: 6.0,
        isDeterministic: true,
        jurisdictionCode: 'NONE',
        profileId: 'calm_classic',
      );

      expect(report.allPassed, true);
      expect(report.failCount, 0);
    });

    test('uninitialized engine fails config check', () {
      final report = AurexisQaEngine.runFullSuite(
        engineInitialized: false,
        rtp: 95.0,
        fatigueIndex: 0.2,
        escalationMultiplier: 1.5,
        energyDensity: 0.4,
        voiceCount: 8,
        stereoWidth: 1.0,
        memoryUsedMb: 2.0,
        memoryBudgetMb: 6.0,
        isDeterministic: true,
        jurisdictionCode: '',
        profileId: 'test',
      );

      final engineCheck = report.checks.firstWhere((c) => c.id == 'cfg_engine');
      expect(engineCheck.result, QaResult.fail);
    });

    test('over-budget memory fails performance check', () {
      final report = AurexisQaEngine.runFullSuite(
        engineInitialized: true,
        rtp: 95.0,
        fatigueIndex: 0.2,
        escalationMultiplier: 1.5,
        energyDensity: 0.4,
        voiceCount: 8,
        stereoWidth: 1.0,
        memoryUsedMb: 7.0,
        memoryBudgetMb: 6.0,
        isDeterministic: true,
        jurisdictionCode: '',
        profileId: 'test',
      );

      final memCheck = report.checks.firstWhere((c) => c.id == 'perf_memory');
      expect(memCheck.result, QaResult.fail);
    });

    test('invalid RTP fails config check', () {
      final report = AurexisQaEngine.runFullSuite(
        engineInitialized: true,
        rtp: 50.0, // Way too low
        fatigueIndex: 0.2,
        escalationMultiplier: 1.5,
        energyDensity: 0.4,
        voiceCount: 8,
        stereoWidth: 1.0,
        memoryUsedMb: 2.0,
        memoryBudgetMb: 6.0,
        isDeterministic: true,
        jurisdictionCode: '',
        profileId: 'test',
      );

      final rtpCheck = report.checks.firstWhere((c) => c.id == 'cfg_rtp');
      expect(rtpCheck.result, QaResult.fail);
    });

    test('report JSON export works', () {
      final report = AurexisQaEngine.runFullSuite(
        engineInitialized: true,
        rtp: 95.0,
        fatigueIndex: 0.2,
        escalationMultiplier: 1.5,
        energyDensity: 0.4,
        voiceCount: 8,
        stereoWidth: 1.0,
        memoryUsedMb: 2.0,
        memoryBudgetMb: 6.0,
        isDeterministic: true,
        jurisdictionCode: 'MGA',
        profileId: 'standard',
      );

      final json = report.toJsonString();
      expect(json, contains('checks'));
      expect(json, contains('passed'));
      expect(json, contains('total'));
    });

    test('byCategory filters correctly', () {
      final report = AurexisQaEngine.runFullSuite(
        engineInitialized: true,
        rtp: 95.0,
        fatigueIndex: 0.2,
        escalationMultiplier: 1.5,
        energyDensity: 0.4,
        voiceCount: 8,
        stereoWidth: 1.0,
        memoryUsedMb: 2.0,
        memoryBudgetMb: 6.0,
        isDeterministic: true,
        jurisdictionCode: '',
        profileId: 'test',
      );

      final configChecks = report.byCategory(QaCategory.config);
      expect(configChecks, isNotEmpty);
      expect(configChecks.every((c) => c.category == QaCategory.config), true);
    });
  });

  group('QaCheck', () {
    test('toJson includes all fields', () {
      const check = QaCheck(
        id: 'test_1',
        name: 'Test Check',
        category: QaCategory.config,
        result: QaResult.pass,
        detail: 'All good',
        expected: '100',
        actual: '100',
      );
      final json = check.toJson();
      expect(json['id'], 'test_1');
      expect(json['result'], 'pass');
      expect(json['expected'], '100');
    });
  });
}
