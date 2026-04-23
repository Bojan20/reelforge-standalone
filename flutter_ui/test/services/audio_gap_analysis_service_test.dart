/// Unit tests for AudioGapAnalysisService (Phase 10 ghost stage indicator).

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/audio_gap_analysis_service.dart';
import 'package:fluxforge_ui/services/stage_configuration_service.dart';
import 'package:fluxforge_ui/spatial/auto_spatial.dart';

StageDefinition _s(String name, StageCategory cat) => StageDefinition(
      name: name,
      category: cat,
      bus: SpatialBus.sfx,
    );

void main() {
  group('AudioGapReport — empty & full edges', () {
    test('empty report constant is all zeros', () {
      expect(AudioGapReport.empty.totalStages, 0);
      expect(AudioGapReport.empty.boundStages, 0);
      expect(AudioGapReport.empty.coverage, 0.0);
      expect(AudioGapReport.empty.missingCount, 0);
      expect(AudioGapReport.empty.isFull, isFalse);
    });

    test('service returns empty when no stages', () {
      final r = AudioGapAnalysisService.instance.analyze(
        {'ANY_STAGE': '/tmp/x.wav'},
        stageSource: const [],
      );
      expect(r.totalStages, 0);
      expect(r.categorySlices, isEmpty);
    });
  });

  group('AudioGapAnalysisService.analyze', () {
    final stages = [
      _s('SPIN_START',    StageCategory.spin),
      _s('SPIN_STOP',     StageCategory.spin),
      _s('REEL_STOP',     StageCategory.spin),
      _s('WIN_SMALL',     StageCategory.win),
      _s('WIN_BIG',       StageCategory.win),
      _s('FEATURE_START', StageCategory.feature),
      _s('UI_CLICK',      StageCategory.ui),
    ];

    test('no bindings → 0% coverage, every stage missing', () {
      final r = AudioGapAnalysisService.instance.analyze(
        const {},
        stageSource: stages,
      );
      expect(r.totalStages, 7);
      expect(r.boundStages, 0);
      expect(r.coverage, 0.0);
      expect(r.missingCount, 7);
      expect(r.allMissing, hasLength(7));
      // Per-category slice breakdown
      final spin = r.categorySlices.firstWhere(
          (s) => s.category == StageCategory.spin);
      expect(spin.total, 3);
      expect(spin.bound, 0);
      expect(spin.missingCount, 3);
    });

    test('partial bindings tracked per category', () {
      final r = AudioGapAnalysisService.instance.analyze(
        {
          'SPIN_START':    '/a.wav',
          'SPIN_STOP':     '/b.wav',
          'WIN_SMALL':     '/c.wav',
          'UI_CLICK':      '/d.wav',
        },
        stageSource: stages,
      );
      expect(r.boundStages, 4);
      expect(r.totalStages, 7);
      expect(r.coverage, closeTo(4 / 7, 1e-6));
      final spin = r.categorySlices.firstWhere(
          (s) => s.category == StageCategory.spin);
      final win = r.categorySlices.firstWhere(
          (s) => s.category == StageCategory.win);
      final feat = r.categorySlices.firstWhere(
          (s) => s.category == StageCategory.feature);
      expect(spin.bound, 2);
      expect(spin.missing, contains('REEL_STOP'));
      expect(win.bound, 1);
      expect(win.missing, contains('WIN_BIG'));
      expect(feat.bound, 0);
      expect(feat.missing, contains('FEATURE_START'));
    });

    test('empty string value does NOT count as bound', () {
      final r = AudioGapAnalysisService.instance.analyze(
        {'SPIN_START': '', 'SPIN_STOP': '/a.wav'},
        stageSource: stages,
      );
      expect(r.boundStages, 1);
    });

    test('dotted legacy key is treated as bound', () {
      final r = AudioGapAnalysisService.instance.analyze(
        {'ui.click': '/a.wav'},
        stageSource: stages,
      );
      final ui = r.categorySlices.firstWhere(
          (s) => s.category == StageCategory.ui);
      expect(ui.bound, 1);
      expect(ui.missingCount, 0);
    });

    test('full coverage reports isFull=true', () {
      final all = <String, String>{
        for (final s in stages) s.name: '/a.wav',
      };
      final r = AudioGapAnalysisService.instance.analyze(
        all,
        stageSource: stages,
      );
      expect(r.isFull, isTrue);
      expect(r.coverage, 1.0);
      expect(r.missingCount, 0);
      for (final slice in r.categorySlices) {
        expect(slice.isFull, isTrue);
        expect(slice.missing, isEmpty);
      }
    });

    test('missing lists are alphabetically sorted', () {
      final r = AudioGapAnalysisService.instance.analyze(
        const {},
        stageSource: stages,
      );
      final spin = r.categorySlices
          .firstWhere((s) => s.category == StageCategory.spin);
      final copy = List<String>.from(spin.missing);
      copy.sort();
      expect(spin.missing, equals(copy));
      final copy2 = List<String>.from(r.allMissing);
      copy2.sort();
      expect(r.allMissing, equals(copy2));
    });

    test('summary string matches the public getters', () {
      final r = AudioGapAnalysisService.instance.analyze(
        {'SPIN_START': '/a.wav'},
        stageSource: stages,
      );
      expect(r.summary, contains('${r.boundStages} / ${r.totalStages}'));
      expect(r.summary, contains('${r.missingCount} gap'));
    });
  });
}
