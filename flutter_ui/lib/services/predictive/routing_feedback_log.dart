/// FAZA 4.4.5 — Routing Feedback Log
///
/// Persistent log korisničkih reakcija na predikcije (accept / reject)
/// koji se kasnije koristi za kalibrisanje classifier-a. Sleduje pattern
/// `ComplianceAuditTrail`:
///   - JSONL append-only u `~/Library/Application Support/FluxForge Studio/
///     audit/routing_feedback_YYYY-MM-DD.jsonl`
///   - Daily rotation
///   - In-memory ring (200 entries) za quick UI access
///   - Failures su silentRun (logging nikad ne sme da crash-uje workflow)
///
/// **Activation:** `RoutingFeedbackLog.instance.attach(analyzer)` listenuje
/// na `PredictiveAnalyzer.feedbackStream` i persist-uje sve emitted event-e.
/// Auto-disposes kad se analyzer dispose-uje.
///
/// **Future (Sprint 18+):**
///   - SQLite migration ako log raste > 10MB / dan
///   - Per-stage acceptance rate aggregator (UI bar chart)
///   - Bayesian prior update: ako Boki uvek odbije WIN_BIG predictions sa
///     "long sustained" envelope, classifier prilagodi taj feature weight.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import 'predictive_analyzer.dart';

class RoutingFeedbackLog {
  RoutingFeedbackLog._();
  static final RoutingFeedbackLog instance = RoutingFeedbackLog._();

  static const int _ringCapacity = 200;
  final List<PredictiveFeedbackEvent> _ring = <PredictiveFeedbackEvent>[];

  StreamSubscription<PredictiveFeedbackEvent>? _sub;
  Directory? _auditDir;

  /// Wire-uje log na analyzer-ov stream. Idempotent — re-attach na isti
  /// analyzer NE pravi duplikat subscription-a.
  void attach(PredictiveAnalyzer analyzer) {
    _sub?.cancel();
    _sub = analyzer.feedbackStream.listen(_onEvent);
  }

  Future<void> detach() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _onEvent(PredictiveFeedbackEvent event) async {
    _ring.add(event);
    if (_ring.length > _ringCapacity) {
      _ring.removeRange(0, _ring.length - _ringCapacity);
    }

    final dir = await _resolveAuditDir();
    if (dir == null) return;
    try {
      final filename = _todayFilename();
      final file = File('${dir.path}/$filename');
      // JSONL: jedna linija = jedan event.
      file.writeAsStringSync(
        '${jsonEncode(event.toJson())}\n',
        mode: FileMode.append,
        flush: false,
      );
    } catch (e, st) {
      debugPrint('[RoutingFeedbackLog] write fail: $e\n$st');
    }
  }

  Future<Directory?> _resolveAuditDir() async {
    if (_auditDir != null && _auditDir!.existsSync()) return _auditDir;
    try {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return null;
      final basePath = Platform.isMacOS
          ? '$home/Library/Application Support/FluxForge Studio'
          : '$home/.fluxforge';
      final dir = Directory('$basePath/audit');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _auditDir = dir;
      return dir;
    } catch (e, st) {
      debugPrint('[RoutingFeedbackLog] resolve dir fail: $e\n$st');
      return null;
    }
  }

  String _todayFilename() {
    final now = DateTime.now().toUtc();
    final yyyy = now.year.toString().padLeft(4, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return 'routing_feedback_$yyyy-$mm-$dd.jsonl';
  }

  /// Last N entries iz in-memory ring-a (newest first). UI panel može da
  /// prikaže "Recent feedback" stream bez disk I/O.
  List<PredictiveFeedbackEvent> recent({int n = 50}) {
    if (_ring.isEmpty) return const [];
    final start = _ring.length > n ? _ring.length - n : 0;
    return _ring.sublist(start).reversed.toList(growable: false);
  }

  /// Statistike po stage-u: koliko accept-ova, koliko reject-ova, prosečna
  /// confidence accepted. Read-only aggregate iz in-memory ring-a.
  Map<String, ({int accepted, int rejected, double avgAcceptedConf})>
      statsByStage() {
    final out = <String, ({int accepted, int rejected, double avgAcceptedConf})>{};
    final acceptedConfSum = <String, double>{};
    final acceptedCount = <String, int>{};
    final rejectedCount = <String, int>{};

    for (final ev in _ring) {
      final stage = ev.suggestedStage;
      if (ev.accepted) {
        acceptedCount[stage] = (acceptedCount[stage] ?? 0) + 1;
        acceptedConfSum[stage] =
            (acceptedConfSum[stage] ?? 0.0) + ev.suggestedConfidence;
      } else {
        rejectedCount[stage] = (rejectedCount[stage] ?? 0) + 1;
      }
    }

    final keys = {...acceptedCount.keys, ...rejectedCount.keys};
    for (final k in keys) {
      final a = acceptedCount[k] ?? 0;
      final r = rejectedCount[k] ?? 0;
      final avg = a > 0 ? (acceptedConfSum[k] ?? 0.0) / a : 0.0;
      out[k] = (accepted: a, rejected: r, avgAcceptedConf: avg);
    }
    return out;
  }

  /// In-memory size — za debug overlay / tests.
  int get inMemoryCount => _ring.length;

  /// Test helper — clear ring + sub. NE briše disk fajlove.
  void clearForTest() {
    _ring.clear();
    _sub?.cancel();
    _sub = null;
  }
}
