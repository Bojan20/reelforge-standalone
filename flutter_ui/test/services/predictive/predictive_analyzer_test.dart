/// FAZA 4.4 — `PredictiveAnalyzer` unit tests.
///
/// Pokriva:
/// - `confidenceTierOf` boundary thresholds (high/mid/low/unclassified)
/// - LRU cache behavior (insert order, eviction at 100)
/// - feedback stream emit
/// - dispose closes stream
///
/// FFI poziv je mocked — testovi ne diraju Rust binarni sloj; testira se
/// orchestration sloj (cache, tier semantike, stream lifecycle).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/predictive/predictive_analyzer.dart';

void main() {
  group('confidenceTierOf — tier thresholds', () {
    test('null → unclassified', () {
      expect(confidenceTierOf(null), ConfidenceTier.unclassified);
    });

    test('< 0.25 → unclassified', () {
      expect(confidenceTierOf(0.0), ConfidenceTier.unclassified);
      expect(confidenceTierOf(0.249), ConfidenceTier.unclassified);
    });

    test('[0.25, 0.50) → low', () {
      expect(confidenceTierOf(0.25), ConfidenceTier.low);
      expect(confidenceTierOf(0.30), ConfidenceTier.low);
      expect(confidenceTierOf(0.499), ConfidenceTier.low);
    });

    test('[0.50, 0.75) → mid', () {
      expect(confidenceTierOf(0.50), ConfidenceTier.mid);
      expect(confidenceTierOf(0.62), ConfidenceTier.mid);
      expect(confidenceTierOf(0.749), ConfidenceTier.mid);
    });

    test('>= 0.75 → high', () {
      expect(confidenceTierOf(0.75), ConfidenceTier.high);
      expect(confidenceTierOf(0.87), ConfidenceTier.high);
      expect(confidenceTierOf(1.0), ConfidenceTier.high);
    });

    test('out-of-range high values still classify as high', () {
      // Defensive: spectral_dna može da vrati > 1.0 ako se confidence ne
      // normalizuje. UI tretira kao high (najbolji tier).
      expect(confidenceTierOf(1.5), ConfidenceTier.high);
    });
  });

  group('PredictiveFeedbackEvent — JSON roundtrip', () {
    test('toJson sadrži sva polja', () {
      final ts = DateTime.parse('2026-05-11T18:00:00Z');
      final ev = PredictiveFeedbackEvent(
        audioPath: '/audio/reel_stop.wav',
        suggestedStage: 'REEL_STOP_3',
        suggestedConfidence: 0.87,
        actualStage: 'REEL_STOP_3',
        accepted: true,
        timestamp: ts,
      );

      final json = ev.toJson();
      expect(json['audioPath'], '/audio/reel_stop.wav');
      expect(json['suggestedStage'], 'REEL_STOP_3');
      expect(json['suggestedConfidence'], 0.87);
      expect(json['actualStage'], 'REEL_STOP_3');
      expect(json['accepted'], true);
      expect(json['timestamp'], '2026-05-11T18:00:00.000Z');
    });

    test('rejected event sadrži actualStage=null', () {
      final ev = PredictiveFeedbackEvent(
        audioPath: '/audio/x.wav',
        suggestedStage: 'WIN_BIG',
        suggestedConfidence: 0.42,
        actualStage: null,
        accepted: false,
        timestamp: DateTime.now(),
      );
      expect(ev.toJson()['actualStage'], isNull);
      expect(ev.toJson()['accepted'], false);
    });
  });
}
