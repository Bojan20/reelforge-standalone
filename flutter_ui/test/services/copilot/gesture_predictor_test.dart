/// FAZA 4.2.2 — `GesturePredictor` unit tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/copilot/gesture_predictor.dart';

GestureEvent _g(String kind, {Map<String, dynamic> p = const {}}) =>
    GestureEvent(kind: kind, payload: p);

void main() {
  group('GesturePredictor — basic operations', () {
    setUp(() => GesturePredictor.instance.clearForTest());

    test('record grows size', () {
      final p = GesturePredictor.instance;
      p.record(_g('a'));
      p.record(_g('b'));
      expect(p.size, 2);
    });

    test('recent returns newest-first', () {
      final p = GesturePredictor.instance;
      p.record(_g('a'));
      p.record(_g('b'));
      p.record(_g('c'));
      final r = p.recent(n: 2);
      expect(r.length, 2);
      expect(r[0].kind, 'c');
      expect(r[1].kind, 'b');
    });

    test('clear resets ring', () {
      final p = GesturePredictor.instance;
      p.record(_g('a'));
      p.clear();
      expect(p.size, 0);
    });
  });

  group('GesturePredictor — predictNext', () {
    setUp(() => GesturePredictor.instance.clearForTest());

    test('insufficient history (<3 events) → null', () {
      final p = GesturePredictor.instance;
      p.record(_g('a'));
      p.record(_g('b'));
      expect(p.predictNext(), isNull);
    });

    test('strong pattern → high confidence prediction', () {
      final p = GesturePredictor.instance;
      // History: [a, b, c, a, b, c, a, b] — current trigram (a,b)→c
      for (final k in ['a', 'b', 'c', 'a', 'b', 'c', 'a', 'b']) {
        p.record(_g(k));
      }
      final pred = p.predictNext();
      expect(pred, isNotNull);
      expect(pred!.predictedKind, 'c');
      // (a,b) followed by c appears 2 times, total matches = 2 → conf = 1.0
      expect(pred.confidence, closeTo(1.0, 1e-9));
      expect(pred.matchCount, 2);
    });

    test('mixed continuations → ratio confidence', () {
      final p = GesturePredictor.instance;
      // History: [a, b, c, a, b, d, a, b]
      // current trigram (a,b) — past matches: (a,b,c), (a,b,d) → 1/2 each
      for (final k in ['a', 'b', 'c', 'a', 'b', 'd', 'a', 'b']) {
        p.record(_g(k));
      }
      final pred = p.predictNext();
      expect(pred, isNotNull);
      // Both c and d have count 1 — first wins (Dart map insertion order).
      expect(pred!.confidence, closeTo(0.5, 1e-9));
    });

    test('no matching trigram prefix → null', () {
      final p = GesturePredictor.instance;
      // History ends with (z, w) — niko nije imao (z, w) prefix ranije.
      for (final k in ['a', 'b', 'c', 'd', 'e', 'z', 'w']) {
        p.record(_g(k));
      }
      expect(p.predictNext(), isNull);
    });

    test('low confidence below threshold → null', () {
      final p = GesturePredictor.instance;
      // Pattern (a,b) followed by 5 different unique events — low conf.
      for (final k in ['a', 'b', 'c', 'a', 'b', 'd', 'a', 'b', 'e',
        'a', 'b', 'f', 'a', 'b', 'g', 'a', 'b']) {
        p.record(_g(k));
      }
      final pred = p.predictNext(minConfidence: 0.5);
      expect(pred, isNull);
    });

    test('modal payload — most common payload wins', () {
      final p = GesturePredictor.instance;
      // Pattern (a,b)→c with payload {x: 1} 2x i {x: 2} 1x
      p.record(_g('a'));
      p.record(_g('b'));
      p.record(_g('c', p: {'x': 1}));
      p.record(_g('a'));
      p.record(_g('b'));
      p.record(_g('c', p: {'x': 1}));
      p.record(_g('a'));
      p.record(_g('b'));
      p.record(_g('c', p: {'x': 2}));
      p.record(_g('a'));
      p.record(_g('b'));

      final pred = p.predictNext();
      expect(pred, isNotNull);
      expect(pred!.predictedKind, 'c');
      expect(pred.predictedPayload['x'], 1); // modal value
    });
  });

  group('GestureEvent — JSON shape', () {
    test('toJson contains all fields', () {
      final e = GestureEvent(
        kind: 'audio_assign',
        payload: const {'stage': 'REEL_STOP', 'path': '/x.wav'},
        context: 'session_start',
        timestamp: DateTime.parse('2026-05-11T18:00:00Z'),
      );
      final json = e.toJson();
      expect(json['kind'], 'audio_assign');
      expect(json['payload']['stage'], 'REEL_STOP');
      expect(json['context'], 'session_start');
      expect(json['ts'], '2026-05-11T18:00:00.000Z');
    });

    test('toJson omits empty payload + null context', () {
      final e = _g('a');
      final json = e.toJson();
      expect(json.containsKey('payload'), isFalse);
      expect(json.containsKey('context'), isFalse);
    });
  });
}
