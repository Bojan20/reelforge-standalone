/// FAZA 4.2.2 — Predictive Automation (Gesture History Predictor)
///
/// Beleži poslednjih N user gestures (audio assign, parameter change, stage
/// trigger, etc.) i predviđa next-most-likely action sa confidence
/// score-om. UI prikazuje "ghost suggestion" preview koji korisnik može
/// jednim klikom da prihvati.
///
/// **Algoritam:** trigram pattern detector — gleda zadnja 2 gesture-a i
/// traži najčešći nastavak iz history-a. Bez ML modela; pure frequency
/// counting. Efikasno za sub-100-gesture session-e.
///
/// **Primer:**
///   History: [setVolume(reel,+1), setVolume(win,+1), setVolume(idle,+1)]
///   Pattern: (setVolume, setVolume) → setVolume (confidence 1.0)
///   Suggestion: "+1dB volume na next stage"
///
/// **Future:**
///   - Bayesian prior update iz reject feedback (4.4.5 routing log)
///   - Cross-session pattern recall (memory_event_log integration)
///   - LSTM predictor (4.1.2 Phi-4 dependency)
library;

import 'dart:collection';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// One recorded user gesture.
class GestureEvent {
  /// Short kind code — npr. `audio_assign`, `param_change`, `stage_trigger`,
  /// `bus_route`, `eq_band_adjust`.
  final String kind;

  /// Optional payload (target stage, parameter name, delta etc.).
  final Map<String, dynamic> payload;

  /// Optional context (npr. "session_start", "after_solo").
  final String? context;

  final DateTime timestamp;

  GestureEvent({
    required this.kind,
    this.payload = const {},
    this.context,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (payload.isNotEmpty) 'payload': payload,
        if (context != null) 'context': context,
        'ts': timestamp.toIso8601String(),
      };
}

/// Prediction rezultat sa confidence.
class GesturePrediction {
  /// Predviđena akcija — najčešći nastavak trigram-a.
  final String predictedKind;

  /// Confidence [0.0, 1.0] = freq / total_continuations.
  final double confidence;

  /// Predviđen payload (modal value preko svih history matches).
  final Map<String, dynamic> predictedPayload;

  /// Broj observed matches kojima je predikcija formirana.
  final int matchCount;

  const GesturePrediction({
    required this.predictedKind,
    required this.confidence,
    required this.predictedPayload,
    required this.matchCount,
  });
}

class GesturePredictor {
  GesturePredictor._({int ringSize = 100}) : _maxSize = ringSize;
  static final GesturePredictor instance = GesturePredictor._();

  final int _maxSize;
  final Queue<GestureEvent> _ring = Queue<GestureEvent>();

  /// Record one gesture event. O(1).
  void record(GestureEvent event) {
    _ring.add(event);
    while (_ring.length > _maxSize) {
      _ring.removeFirst();
    }
  }

  /// Predict next-most-likely gesture na osnovu zadnjih 2 (trigram pattern).
  ///
  /// Returns null ako:
  ///   - History < 3 events (insufficient)
  ///   - Nema match-eva za trenutni trigram prefix
  ///   - Confidence < `minConfidence` threshold (default 0.30)
  GesturePrediction? predictNext({double minConfidence = 0.30}) {
    if (_ring.length < 3) return null;
    final list = _ring.toList(growable: false);
    final lastTwo = list.sublist(list.length - 2);
    final prefixA = lastTwo[0].kind;
    final prefixB = lastTwo[1].kind;

    // Scan history za pattern (prefixA, prefixB, X) → count X-ova.
    final continuations = <String, int>{};
    final payloadsByKind = <String, List<Map<String, dynamic>>>{};
    int totalMatches = 0;

    // Iterate triplets (i, i+1, i+2) — last triplet je current state, skip.
    for (int i = 0; i < list.length - 2; i++) {
      if (list[i].kind == prefixA && list[i + 1].kind == prefixB) {
        final next = list[i + 2];
        continuations[next.kind] = (continuations[next.kind] ?? 0) + 1;
        payloadsByKind
            .putIfAbsent(next.kind, () => <Map<String, dynamic>>[])
            .add(next.payload);
        totalMatches++;
      }
    }

    if (totalMatches == 0) return null;

    // Find modal continuation.
    String? bestKind;
    int bestCount = 0;
    for (final entry in continuations.entries) {
      if (entry.value > bestCount) {
        bestCount = entry.value;
        bestKind = entry.key;
      }
    }
    if (bestKind == null) return null;

    final confidence = bestCount / totalMatches;
    if (confidence < minConfidence) return null;

    // Modal payload — najčešća payload mapa za bestKind.
    final modalPayload = _modalPayload(payloadsByKind[bestKind] ?? const []);

    return GesturePrediction(
      predictedKind: bestKind,
      confidence: confidence,
      predictedPayload: modalPayload,
      matchCount: bestCount,
    );
  }

  /// Pronađi modal (najčešći) payload iz liste payload mapa.
  Map<String, dynamic> _modalPayload(List<Map<String, dynamic>> payloads) {
    if (payloads.isEmpty) return const {};
    // Group by serialized JSON key.
    final counts = <String, int>{};
    final originals = <String, Map<String, dynamic>>{};
    for (final p in payloads) {
      final key = _serializePayload(p);
      counts[key] = (counts[key] ?? 0) + 1;
      originals.putIfAbsent(key, () => p);
    }
    String? bestKey;
    int bestCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        bestCount = entry.value;
        bestKey = entry.key;
      }
    }
    return bestKey == null ? const {} : originals[bestKey] ?? const {};
  }

  String _serializePayload(Map<String, dynamic> p) {
    // Stable serialize — sort keys.
    final keys = p.keys.toList()..sort();
    return keys.map((k) => '$k=${p[k]}').join('|');
  }

  /// Trenutni count snimljenih events.
  int get size => _ring.length;

  /// Recent N events (newest-first).
  List<GestureEvent> recent({int n = 20}) {
    final list = _ring.toList(growable: false);
    final start = list.length > n ? list.length - n : 0;
    return list.sublist(start).reversed.toList(growable: false);
  }

  /// Reset ring (session boundary).
  void clear() => _ring.clear();

  @visibleForTesting
  void clearForTest() => _ring.clear();
}
