/// FAZA 4.3.4 — Neuro Memory Substrate
///
/// Dart-side memory layer iznad `rf-neuro::PlayerStateVector` FFI output-a.
/// Drži sliding ring buffer 8D state vektora i izvozi:
///
/// - **Trend** — moving average za dat dimension kroz N poslednjih snapshot-a
/// - **Baseline** — long-term average preko cele istorije (per-dimension)
/// - **Peaks** — top-K extreme moments za UI highlight (npr. "max arousal")
/// - **Trajectory** — sliding history za chart rendering
///
/// **Why Dart, not Rust?** rf-neuro je već stateful (5-min sliding window),
/// ali nije persistent — process restart resetuje historiju. Ovaj substrate
/// dodaje long-term episodičnu memoriju koja preživljava restart, plus
/// integrate-uje sa `MemoryEventLog` da snapshot-i idu u jedinstveni
/// audit trail uz feedback + compliance events.
///
/// **Performance:** sve operacije O(1) za record, O(n) za trend/baseline
/// gde je n = ringSize (default 1000). Single thread (Dart event loop).
library;

import 'dart:collection';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'memory_event_log.dart';

/// 8D player state — mirror `rf-neuro::PlayerStateVector` Rust struct-a.
/// Sve vrednosti su [0.0, 1.0] osim ako specifirano.
class NeuroSnapshot {
  final DateTime timestamp;

  /// 8 dimenzija — names se moraju da match-uju FFI JSON keys.
  final double arousal;
  final double valence;
  final double engagement;
  final double riskTolerance;
  final double frustration;
  final double anticipation;
  final double fatigue;
  final double churnProb;

  const NeuroSnapshot({
    required this.timestamp,
    required this.arousal,
    required this.valence,
    required this.engagement,
    required this.riskTolerance,
    required this.frustration,
    required this.anticipation,
    required this.fatigue,
    required this.churnProb,
  });

  /// Parse JSON iz `neuro_engine_process` FFI return-a.
  factory NeuroSnapshot.fromJson(Map<String, dynamic> json,
      {DateTime? timestamp}) {
    double readDim(String k) => (json[k] as num?)?.toDouble() ?? 0.0;
    return NeuroSnapshot(
      timestamp: timestamp ?? DateTime.now().toUtc(),
      arousal: readDim('arousal'),
      valence: readDim('valence'),
      engagement: readDim('engagement'),
      riskTolerance: readDim('risk_tolerance'),
      frustration: readDim('frustration'),
      anticipation: readDim('anticipation'),
      fatigue: readDim('fatigue'),
      churnProb: readDim('churn_prob'),
    );
  }

  Map<String, dynamic> toJson() => {
        'ts': timestamp.toIso8601String(),
        'arousal': arousal,
        'valence': valence,
        'engagement': engagement,
        'risk_tolerance': riskTolerance,
        'frustration': frustration,
        'anticipation': anticipation,
        'fatigue': fatigue,
        'churn_prob': churnProb,
      };

  /// Pristup dimension-u po naizvu (snake_case ili camelCase friendly).
  double dimension(String name) {
    switch (name.toLowerCase()) {
      case 'arousal':
        return arousal;
      case 'valence':
        return valence;
      case 'engagement':
        return engagement;
      case 'risk_tolerance':
      case 'risktolerance':
        return riskTolerance;
      case 'frustration':
        return frustration;
      case 'anticipation':
        return anticipation;
      case 'fatigue':
        return fatigue;
      case 'churn_prob':
      case 'churnprob':
        return churnProb;
      default:
        return double.nan;
    }
  }
}

/// Top-K peak entry za UI highlight.
class NeuroPeakEntry {
  final NeuroSnapshot snapshot;
  final double value;
  const NeuroPeakEntry({required this.snapshot, required this.value});
}

/// Substrate singleton. Sve operacije su sync (Dart event loop).
class NeuroMemorySubstrate {
  NeuroMemorySubstrate._({int ringSize = 1000}) : _maxSize = ringSize;
  static final NeuroMemorySubstrate instance = NeuroMemorySubstrate._();

  final int _maxSize;
  final Queue<NeuroSnapshot> _ring = Queue<NeuroSnapshot>();

  /// Optional integration sa MemoryEventLog — kad je attached, svaki
  /// recordSnapshot() takođe ide u event log kao `neuro_snapshot` kind.
  bool _logToMemoryEvents = false;

  /// Wire-uj MemoryEventLog hook. Idempotent.
  void attachMemoryEventLog({bool enabled = true}) {
    _logToMemoryEvents = enabled;
  }

  /// Record one snapshot. Slabo blokirajuće (O(1) Queue add + cap).
  void recordSnapshot(NeuroSnapshot snapshot) {
    _ring.add(snapshot);
    while (_ring.length > _maxSize) {
      _ring.removeFirst();
    }
    if (_logToMemoryEvents) {
      // Fire-and-forget — MemoryEventLog ima sopstveni async path.
      MemoryEventLog.instance.record(
        kind: 'neuro_snapshot',
        data: snapshot.toJson(),
      );
    }
  }

  /// Moving average za dimension u poslednjih N snapshot-a.
  /// `lookback <= 0` ili empty ring vraća 0.0 (UI ne crash-uje).
  double trend(String dimension, {int lookback = 30}) {
    if (lookback <= 0 || _ring.isEmpty) return 0.0;
    final from = _ring.length > lookback ? _ring.length - lookback : 0;
    final slice = _ring.toList(growable: false).sublist(from);
    double sum = 0.0;
    int count = 0;
    for (final s in slice) {
      final v = s.dimension(dimension);
      if (v.isNaN) continue;
      sum += v;
      count++;
    }
    return count > 0 ? sum / count : 0.0;
  }

  /// Long-term baseline (entire ring).
  double baseline(String dimension) => trend(dimension, lookback: _ring.length);

  /// Top-K extreme moments za dimension. `descending: true` → highest first.
  List<NeuroPeakEntry> peaks(
    String dimension, {
    int k = 5,
    bool descending = true,
  }) {
    if (_ring.isEmpty) return const [];
    final entries = _ring
        .map((s) => NeuroPeakEntry(snapshot: s, value: s.dimension(dimension)))
        .where((e) => !e.value.isNaN)
        .toList();
    entries.sort((a, b) =>
        descending ? b.value.compareTo(a.value) : a.value.compareTo(b.value));
    return entries.take(k).toList(growable: false);
  }

  /// Trajectory za chart — vraća newest-first listu (dimension only).
  /// Limit > ringSize → vraća ceo ring.
  List<({DateTime ts, double value})> trajectory(
    String dimension, {
    int limit = 100,
  }) {
    if (_ring.isEmpty) return const [];
    final n = limit > _ring.length ? _ring.length : limit;
    final slice = _ring.toList(growable: false);
    final from = slice.length - n;
    final result = <({DateTime ts, double value})>[];
    for (int i = slice.length - 1; i >= from; i--) {
      final v = slice[i].dimension(dimension);
      if (!v.isNaN) {
        result.add((ts: slice[i].timestamp, value: v));
      }
    }
    return result;
  }

  /// Trenutni size — for debug overlay / tests.
  int get size => _ring.length;

  /// Najnoviji snapshot (ili null ako ring prazan).
  NeuroSnapshot? get latest => _ring.isEmpty ? null : _ring.last;

  /// Briše ring (reset session-state).
  void clear() {
    _ring.clear();
  }

  @visibleForTesting
  void clearForTest() {
    _ring.clear();
    _logToMemoryEvents = false;
  }
}
