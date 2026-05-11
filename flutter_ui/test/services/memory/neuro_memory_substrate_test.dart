/// FAZA 4.3.4 — `NeuroMemorySubstrate` unit tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/memory/neuro_memory_substrate.dart';

NeuroSnapshot _snap({
  double arousal = 0.0,
  double valence = 0.5,
  double fatigue = 0.0,
  double churnProb = 0.0,
  DateTime? ts,
}) =>
    NeuroSnapshot(
      timestamp: ts ?? DateTime.now().toUtc(),
      arousal: arousal,
      valence: valence,
      engagement: 0.5,
      riskTolerance: 0.5,
      frustration: 0.0,
      anticipation: 0.0,
      fatigue: fatigue,
      churnProb: churnProb,
    );

void main() {
  group('NeuroSnapshot — JSON + dimension access', () {
    test('fromJson reads all 8 dimensions', () {
      final s = NeuroSnapshot.fromJson({
        'arousal': 0.7,
        'valence': 0.6,
        'engagement': 0.8,
        'risk_tolerance': 0.4,
        'frustration': 0.2,
        'anticipation': 0.9,
        'fatigue': 0.3,
        'churn_prob': 0.1,
      });
      expect(s.arousal, 0.7);
      expect(s.churnProb, 0.1);
    });

    test('fromJson handles missing keys with defaults', () {
      final s = NeuroSnapshot.fromJson({'arousal': 0.5});
      expect(s.arousal, 0.5);
      expect(s.valence, 0.0);
      expect(s.churnProb, 0.0);
    });

    test('dimension() returns correct value snake_case', () {
      final s = _snap(arousal: 0.42, fatigue: 0.7);
      expect(s.dimension('arousal'), 0.42);
      expect(s.dimension('fatigue'), 0.7);
      expect(s.dimension('risk_tolerance'), 0.5);
    });

    test('dimension() returns NaN for unknown name', () {
      final s = _snap();
      expect(s.dimension('unknown_dim').isNaN, isTrue);
    });

    test('toJson roundtrip preserves values', () {
      final s = _snap(arousal: 0.7, fatigue: 0.3);
      final json = s.toJson();
      expect(json['arousal'], 0.7);
      expect(json['fatigue'], 0.3);
      expect(json['ts'], isA<String>());
    });
  });

  group('NeuroMemorySubstrate — record + ring', () {
    setUp(() => NeuroMemorySubstrate.instance.clearForTest());

    test('record grows size', () {
      final sub = NeuroMemorySubstrate.instance;
      sub.recordSnapshot(_snap());
      sub.recordSnapshot(_snap());
      expect(sub.size, 2);
    });

    test('latest reflects most-recent snapshot', () {
      final sub = NeuroMemorySubstrate.instance;
      sub.recordSnapshot(_snap(arousal: 0.1));
      sub.recordSnapshot(_snap(arousal: 0.9));
      expect(sub.latest?.arousal, 0.9);
    });

    test('clear resets ring', () {
      final sub = NeuroMemorySubstrate.instance;
      sub.recordSnapshot(_snap());
      sub.clear();
      expect(sub.size, 0);
      expect(sub.latest, isNull);
    });
  });

  group('NeuroMemorySubstrate — trend + baseline', () {
    setUp(() => NeuroMemorySubstrate.instance.clearForTest());

    test('trend computes moving average over lookback', () {
      final sub = NeuroMemorySubstrate.instance;
      for (int i = 0; i < 10; i++) {
        sub.recordSnapshot(_snap(arousal: i / 10.0));
      }
      // Last 5 arousal-a: 0.5, 0.6, 0.7, 0.8, 0.9 → avg = 0.7
      expect(sub.trend('arousal', lookback: 5), closeTo(0.7, 1e-9));
    });

    test('trend with empty ring returns 0', () {
      final sub = NeuroMemorySubstrate.instance;
      expect(sub.trend('arousal'), 0.0);
    });

    test('trend with lookback=0 returns 0', () {
      final sub = NeuroMemorySubstrate.instance;
      sub.recordSnapshot(_snap(arousal: 0.5));
      expect(sub.trend('arousal', lookback: 0), 0.0);
    });

    test('baseline averages entire ring', () {
      final sub = NeuroMemorySubstrate.instance;
      sub.recordSnapshot(_snap(arousal: 0.0));
      sub.recordSnapshot(_snap(arousal: 1.0));
      expect(sub.baseline('arousal'), closeTo(0.5, 1e-9));
    });

    test('trend ignores NaN dimension', () {
      final sub = NeuroMemorySubstrate.instance;
      sub.recordSnapshot(_snap(arousal: 0.5));
      // Unknown dim returns NaN → trend = 0.0
      expect(sub.trend('bogus_dim', lookback: 10), 0.0);
    });
  });

  group('NeuroMemorySubstrate — peaks', () {
    setUp(() => NeuroMemorySubstrate.instance.clearForTest());

    test('peaks descending returns top-K highest', () {
      final sub = NeuroMemorySubstrate.instance;
      for (final v in [0.1, 0.9, 0.5, 0.7, 0.3]) {
        sub.recordSnapshot(_snap(arousal: v));
      }
      final top3 = sub.peaks('arousal', k: 3);
      expect(top3.length, 3);
      expect(top3[0].value, 0.9);
      expect(top3[1].value, 0.7);
      expect(top3[2].value, 0.5);
    });

    test('peaks ascending returns bottom-K lowest', () {
      final sub = NeuroMemorySubstrate.instance;
      for (final v in [0.1, 0.9, 0.5, 0.7]) {
        sub.recordSnapshot(_snap(arousal: v));
      }
      final bot2 = sub.peaks('arousal', k: 2, descending: false);
      expect(bot2.length, 2);
      expect(bot2[0].value, 0.1);
      expect(bot2[1].value, 0.5);
    });

    test('peaks empty ring returns empty list', () {
      final sub = NeuroMemorySubstrate.instance;
      expect(sub.peaks('arousal'), isEmpty);
    });
  });

  group('NeuroMemorySubstrate — trajectory', () {
    setUp(() => NeuroMemorySubstrate.instance.clearForTest());

    test('trajectory returns newest-first', () {
      final sub = NeuroMemorySubstrate.instance;
      for (int i = 0; i < 5; i++) {
        sub.recordSnapshot(_snap(arousal: i / 5.0));
      }
      final traj = sub.trajectory('arousal', limit: 3);
      expect(traj.length, 3);
      // Newest is 0.8 (i=4), then 0.6 (i=3), then 0.4 (i=2)
      expect(traj[0].value, closeTo(0.8, 1e-9));
      expect(traj[1].value, closeTo(0.6, 1e-9));
      expect(traj[2].value, closeTo(0.4, 1e-9));
    });

    test('trajectory limit > size returns all', () {
      final sub = NeuroMemorySubstrate.instance;
      sub.recordSnapshot(_snap(arousal: 0.5));
      final traj = sub.trajectory('arousal', limit: 100);
      expect(traj.length, 1);
    });
  });
}
