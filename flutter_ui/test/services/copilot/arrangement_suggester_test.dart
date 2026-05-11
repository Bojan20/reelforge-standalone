/// FAZA 4.2.5 — `ArrangementSuggester` unit tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/copilot/arrangement_suggester.dart';

void main() {
  group('ArrangementSuggester — happy paths', () {
    final s = ArrangementSuggester.instance;

    test('tense buildup to big win → 5-step build→peak→transient→release→sustained',
        () {
      final r = s.propose('tense buildup to big win');
      expect(r.isSuccess, isTrue);
      expect(r.steps!.length, 5);
      expect(r.steps![0].stageId, 'ANTICIPATION_LOW');
      expect(r.steps![0].envelope, EnvelopeShape.build);
      expect(r.steps![1].stageId, 'ANTICIPATION_HIGH');
      expect(r.steps![1].envelope, EnvelopeShape.peak);
      expect(r.steps![2].envelope, EnvelopeShape.transient);
      expect(r.steps![3].stageId, 'WIN_BIG_TIER');
      expect(r.steps![3].envelope, EnvelopeShape.release);
      expect(r.steps![4].stageId, 'WIN_ROLLUP');
      expect(r.steps![4].envelope, EnvelopeShape.sustained);
    });

    test('euphoric climax to mega win → 4 steps with peak + sustained + fade',
        () {
      final r = s.propose('euphoric climax to mega win');
      expect(r.isSuccess, isTrue);
      expect(r.steps!.length, 4);
      expect(r.steps![1].stageId, 'WIN_MEGA_TIER');
      expect(r.steps![1].envelope, EnvelopeShape.peak);
      expect(r.steps!.last.envelope, EnvelopeShape.fade);
    });

    test('calm intro → 3 ambient/idle steps (no win)', () {
      final r = s.propose('calm intro');
      expect(r.isSuccess, isTrue);
      expect(r.steps!.length, 3);
      expect(r.steps![0].stageId, 'AMBIENT_INTRO');
      expect(r.steps![1].stageId, 'IDLE_LOOP');
      expect(r.steps!.every((st) => !st.stageId.contains('WIN')), isTrue);
    });

    test('punchy hit → 3 transient/fade steps (no sustained)', () {
      final r = s.propose('punchy hit to big win');
      expect(r.isSuccess, isTrue);
      expect(r.steps!.length, 3);
      final envelopes = r.steps!.map((st) => st.envelope).toSet();
      expect(envelopes, isNot(contains(EnvelopeShape.sustained)));
      expect(envelopes, contains(EnvelopeShape.transient));
      expect(envelopes, contains(EnvelopeShape.fade));
    });

    test('triumphant finale to jackpot → 4 steps ending with fade', () {
      final r = s.propose('triumphant finale to jackpot');
      expect(r.isSuccess, isTrue);
      expect(r.steps!.length, 4);
      expect(r.steps![0].stageId, 'JACKPOT_TRIGGER');
      expect(r.steps![1].stageId, 'WIN_JACKPOT');
      expect(r.steps!.last.envelope, EnvelopeShape.fade);
    });

    test('dark setup → 3 steps with no win stage', () {
      final r = s.propose('dark setup');
      expect(r.isSuccess, isTrue);
      expect(r.steps!.length, 3);
      expect(r.steps!.any((st) => st.stageId.contains('WIN')), isFalse);
    });

    test('smooth transition → outro + intro + idle (crossfade pattern)', () {
      final r = s.propose('smooth transition');
      expect(r.isSuccess, isTrue);
      expect(r.steps!.length, 3);
      expect(r.steps![0].stageId, 'AMBIENT_OUTRO');
      expect(r.steps![1].stageId, 'AMBIENT_INTRO');
      expect(r.steps![2].stageId, 'IDLE_LOOP');
    });

    test('aggressive sequence to free spins → 4 steps targeting FREE_SPIN_WIN',
        () {
      final r = s.propose('aggressive sequence to free spins');
      expect(r.isSuccess, isTrue);
      expect(r.steps!.length, 4);
      expect(r.steps![2].stageId, 'FREE_SPIN_WIN');
    });

    test('bright payoff to bonus → trigger + win + rollup', () {
      final r = s.propose('bright payoff to bonus');
      expect(r.isSuccess, isTrue);
      expect(r.steps!.length, 3);
      expect(r.steps![0].stageId, 'BONUS_TRIGGER');
      expect(r.steps![1].stageId, 'BONUS_WIN');
      expect(r.steps![2].stageId, 'WIN_ROLLUP');
    });
  });

  group('ArrangementSuggester — scale modifiers', () {
    final s = ArrangementSuggester.instance;

    test('"short" modifier halves all durations vs baseline', () {
      final base = s.propose('tense buildup to big win');
      final short = s.propose('short tense buildup to big win');
      expect(base.isSuccess, isTrue);
      expect(short.isSuccess, isTrue);
      for (int i = 0; i < base.steps!.length; i++) {
        // 0.5x scale, allow ±1 ms rounding tolerance.
        expect(
          (short.steps![i].durationMs - base.steps![i].durationMs * 0.5).abs(),
          lessThanOrEqualTo(1),
          reason: 'step $i should be ~half duration',
        );
      }
    });

    test('"long" modifier extends durations by 1.75x', () {
      final base = s.propose('euphoric climax');
      final long = s.propose('long euphoric climax');
      expect(base.isSuccess, isTrue);
      expect(long.isSuccess, isTrue);
      // Total must scale ~1.75x.
      final ratio = long.totalMs / base.totalMs;
      expect(ratio, closeTo(1.75, 0.05));
    });

    test('"epic" triggers long scale (alias for long)', () {
      final epic = s.propose('epic triumphant finale to jackpot');
      final base = s.propose('triumphant finale to jackpot');
      expect(epic.totalMs > base.totalMs, isTrue);
    });

    test('no modifier defaults to scale=1.0', () {
      final r = s.propose('punchy hit');
      expect(r.steps![0].durationMs, 150);
      expect(r.steps![1].durationMs, 500);
      expect(r.steps![2].durationMs, 300);
    });
  });

  group('ArrangementSuggester — target extraction & override', () {
    final s = ArrangementSuggester.instance;

    test('no target → generic WIN_GENERIC stage', () {
      final r = s.propose('tense buildup');
      expect(r.isSuccess, isTrue);
      expect(
        r.steps!.firstWhere((st) => st.envelope == EnvelopeShape.release).stageId,
        'WIN_GENERIC',
      );
    });

    test('explicit targetOverride beats text parsing', () {
      final r = s.propose(
        'tense buildup to big win',
        targetOverride: ArrangementTarget.jackpot,
      );
      expect(r.isSuccess, isTrue);
      expect(
        r.steps!.firstWhere((st) => st.envelope == EnvelopeShape.release).stageId,
        'WIN_JACKPOT',
      );
    });

    test('cascade target wires CASCADE_WIN', () {
      final r = s.propose('punchy hit to cascade');
      expect(r.steps![1].stageId, 'CASCADE_WIN');
    });
  });

  group('ArrangementSuggester — failure paths', () {
    final s = ArrangementSuggester.instance;

    test('empty intent → failure', () {
      final r = s.propose('');
      expect(r.isSuccess, isFalse);
      expect(r.error, 'Empty intent phrase.');
    });

    test('whitespace-only intent → failure', () {
      final r = s.propose('   ');
      expect(r.isSuccess, isFalse);
    });

    test('unknown shape → failure with helpful hint', () {
      final r = s.propose('make it banana');
      expect(r.isSuccess, isFalse);
      expect(r.error, contains('tense buildup'));
    });
  });

  group('ArrangementSuggester — determinism & serialization', () {
    final s = ArrangementSuggester.instance;

    test('same input → same output (deterministic)', () {
      final r1 = s.propose('euphoric climax to mega win');
      final r2 = s.propose('euphoric climax to mega win');
      expect(r1.steps!.length, r2.steps!.length);
      for (int i = 0; i < r1.steps!.length; i++) {
        expect(r1.steps![i].stageId, r2.steps![i].stageId);
        expect(r1.steps![i].durationMs, r2.steps![i].durationMs);
        expect(r1.steps![i].envelope, r2.steps![i].envelope);
      }
    });

    test('totalMs equals sum of durations', () {
      final r = s.propose('tense buildup to big win');
      final sum = r.steps!.fold<int>(0, (acc, st) => acc + st.durationMs);
      expect(r.totalMs, sum);
    });

    test('failure totalMs is 0', () {
      final r = s.propose('');
      expect(r.totalMs, 0);
    });

    test('toJson exposes required keys', () {
      final r = s.propose('punchy hit');
      final j = r.steps![0].toJson();
      expect(j['stage_id'], isA<String>());
      expect(j['duration_ms'], isA<int>());
      expect(j['envelope'], isA<String>());
      expect(j['rationale'], isA<String>());
    });
  });
}
