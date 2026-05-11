/// FAZA 4.2.1 — `MixDeltaProposer` unit tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/copilot/mix_delta_proposer.dart';

void main() {
  group('MixDeltaProposer — happy paths', () {
    final p = MixDeltaProposer.instance;

    test('euphoric rollup → 3 deltas (volume + brightness + tempo)', () {
      final r = p.propose('make rollup more euphoric');
      expect(r.isSuccess, isTrue);
      expect(r.deltas!.length, 3);
      expect(r.deltas!.every((d) => d.stage == 'WIN_ROLLUP_*'), isTrue);
      final params = r.deltas!.map((d) => d.parameter).toSet();
      expect(params, contains('volume_db'));
      expect(params, contains('brightness_pct'));
      expect(params, contains('tempo_pct'));
    });

    test('tense anticipation → 3 deltas (brightness + low_pass + tempo)', () {
      final r = p.propose('make anticipation more tense');
      expect(r.isSuccess, isTrue);
      expect(r.deltas!.every((d) => d.stage == 'ANTICIPATION_*'), isTrue);
      expect(r.deltas!.any((d) => d.parameter == 'brightness_pct'), isTrue);
      expect(r.deltas!.any((d) => d.parameter == 'low_pass_hz'), isTrue);
      // Tense should reduce brightness (negative delta)
      final brightness = r.deltas!.firstWhere(
        (d) => d.parameter == 'brightness_pct',
      );
      expect(brightness.delta, lessThan(0));
    });

    test('punchy reel stop → transient + reverb deltas', () {
      final r = p.propose('reel stop more punchy');
      expect(r.isSuccess, isTrue);
      expect(r.deltas!.every((d) => d.stage == 'REEL_STOP_*'), isTrue);
      expect(r.deltas!.any((d) => d.parameter == 'transient_pct'), isTrue);
    });
  });

  group('MixDeltaProposer — intensity parsing', () {
    final p = MixDeltaProposer.instance;

    test('"15% more euphoric" → 15% intensity', () {
      final r = p.propose('make rollup 15% more euphoric');
      expect(r.isSuccess, isTrue);
      final volume = r.deltas!.firstWhere((d) => d.parameter == 'volume_db');
      // Euphoric volume = 2.0 * intensity = 2.0 * 0.15 = 0.30
      expect(volume.delta, closeTo(0.30, 1e-6));
    });

    test('"much more euphoric" → 30% intensity', () {
      final r = p.propose('make rollup much more euphoric');
      expect(r.isSuccess, isTrue);
      final volume = r.deltas!.firstWhere((d) => d.parameter == 'volume_db');
      // 2.0 * 0.30 = 0.60
      expect(volume.delta, closeTo(0.60, 1e-6));
    });

    test('"less aggressive" → negative intensity', () {
      final r = p.propose('reel stop less aggressive');
      expect(r.isSuccess, isTrue);
      final volume = r.deltas!.firstWhere((d) => d.parameter == 'volume_db');
      // Aggressive volume = 3.0 * intensity = 3.0 * -0.15 = -0.45
      expect(volume.delta, lessThan(0));
    });

    test('default intensity = 15%', () {
      final r = p.propose('rollup euphoric');
      expect(r.isSuccess, isTrue);
      final volume = r.deltas!.firstWhere((d) => d.parameter == 'volume_db');
      expect(volume.delta, closeTo(0.30, 1e-6));
    });
  });

  group('MixDeltaProposer — error paths', () {
    final p = MixDeltaProposer.instance;

    test('empty intent → failure', () {
      final r = p.propose('');
      expect(r.isSuccess, isFalse);
      expect(r.error, contains('Empty'));
    });

    test('no stage keyword → failure', () {
      final r = p.propose('make it euphoric please');
      expect(r.isSuccess, isFalse);
      expect(r.error, contains('target stage'));
    });

    test('no emotion keyword → failure', () {
      final r = p.propose('change the rollup somehow');
      expect(r.isSuccess, isFalse);
      expect(r.error, contains('emotional intent'));
    });

    test('explicit stagePattern overrides extraction', () {
      final r = p.propose('make it euphoric', stagePattern: 'WIN_BIG_3');
      expect(r.isSuccess, isTrue);
      expect(r.deltas!.first.stage, 'WIN_BIG_3');
    });
  });

  group('MixDelta — JSON shape', () {
    test('toJson contains all fields', () {
      const d = MixDelta(
        stage: 'WIN_BIG',
        parameter: 'volume_db',
        delta: 1.5,
        rationale: 'test',
      );
      final json = d.toJson();
      expect(json['stage'], 'WIN_BIG');
      expect(json['parameter'], 'volume_db');
      expect(json['delta'], 1.5);
      expect(json['rationale'], 'test');
    });
  });

  group('MixDeltaProposer — stage extraction edge cases', () {
    final p = MixDeltaProposer.instance;

    test('"big win" preferred over generic "win"', () {
      final r = p.propose('big win euphoric');
      expect(r.deltas!.first.stage, 'WIN_BIG_*');
    });

    test('"reel stop" preferred over "reel"', () {
      final r = p.propose('reel stop punchy');
      expect(r.deltas!.first.stage, 'REEL_STOP_*');
    });

    test('"free spin" maps to FREE_SPIN_*', () {
      final r = p.propose('free spin triumphant');
      expect(r.deltas!.first.stage, 'FREE_SPIN_*');
    });
  });
}
