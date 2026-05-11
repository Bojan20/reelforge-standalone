/// FAZA 4.3.1 — Persistent Memory Event Log
///
/// Lokalno-only event log koji prati šta korisnik radi tokom rada na
/// projektu. Pet glavnih kind-ova:
///
/// - `assignment_set` — audio fajl mapovan na stage
/// - `assignment_remove` — assignment uklonjen
/// - `predictive_accept` — user prihvatio suggestion (iz 4.4.5 routing log)
/// - `predictive_reject` — user odbio suggestion
/// - `compliance_warning` — pre-flight validator detektovao kršenje (4.2.4)
/// - `spin_completed` — slot spin zatvoren (RTPC update)
/// - `project_saved` — manual save event
/// - `custom` — generic API za nove kindove
///
/// **Storage:** JSONL append-only u `~/Library/Application Support/
/// FluxForge Studio/memory/events_YYYY-MM.jsonl` (monthly rotation —
/// dnevna granularnost bi pravila previše fajlova za long-running projekat).
///
/// **Query API:**
/// - `query(kind, since, limit)` — vraća entries iz trenutnog meseca file-a
/// - `recentCached(n)` — in-memory ring (200) za UI quick refresh
/// - `purgeOlderThan(days)` — cleanup (cron 1x dnevno)
///
/// **Auto-hooks:**
/// - Subscribe na `PredictiveAnalyzer.feedbackStream` → emituje
///   `predictive_accept` / `predictive_reject`
/// - Subscribe na `AudioComplianceGuard.warnings` → emituje
///   `compliance_warning`
/// - Subscribe na `SlotLabProjectProvider` audioAssignments changes →
///   emituje `assignment_set` / `assignment_remove`
///
/// **Privacy:** local-only. NIKAD ne ide u cloud. Sva data je on-disk u
/// home dir-u korisnika. Compliant sa GDPR (right to erasure → user može
/// da obriše memory/ folder).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../compliance/audio_compliance_guard.dart';
import '../predictive/predictive_analyzer.dart';

/// One memory event — immutable, JSON serializable.
class MemoryEvent {
  final String id; // UUID-lite: ts_ms + monotonic counter
  final DateTime timestamp;
  final String kind;
  final Map<String, dynamic> data;

  const MemoryEvent({
    required this.id,
    required this.timestamp,
    required this.kind,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'ts': timestamp.toIso8601String(),
        'kind': kind,
        'data': data,
      };

  factory MemoryEvent.fromJson(Map<String, dynamic> json) => MemoryEvent(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['ts'] as String),
        kind: json['kind'] as String,
        data: Map<String, dynamic>.from(json['data'] as Map? ?? const {}),
      );
}

class MemoryEventLog {
  MemoryEventLog._();
  static final MemoryEventLog instance = MemoryEventLog._();

  static const int _ringCapacity = 200;
  final List<MemoryEvent> _ring = <MemoryEvent>[];

  Directory? _memoryDir;
  int _monotonic = 0;

  // Auto-hook subscriptions.
  StreamSubscription<PredictiveFeedbackEvent>? _feedbackSub;
  StreamSubscription<ComplianceWarning>? _warningsSub;

  /// Wire-uje sve auto-hooks. Idempotent.
  void attachAutoHooks({
    PredictiveAnalyzer? analyzer,
    AudioComplianceGuard? guard,
  }) {
    _feedbackSub?.cancel();
    _warningsSub?.cancel();

    if (analyzer != null) {
      _feedbackSub = analyzer.feedbackStream.listen((ev) {
        record(
          kind: ev.accepted ? 'predictive_accept' : 'predictive_reject',
          data: ev.toJson(),
        );
      });
    }
    if (guard != null) {
      _warningsSub = guard.warnings.listen((w) {
        record(
          kind: 'compliance_warning',
          data: w.toJson(),
        );
      });
    }
  }

  /// Record one event. Auto-generates `id` + `timestamp`.
  ///
  /// Disk I/O je sync (single fajl append <1ms tipično). Events su retki
  /// (user gestures), pa overhead je negligibilan.
  Future<MemoryEvent> record({
    required String kind,
    Map<String, dynamic> data = const {},
  }) async {
    final ts = DateTime.now().toUtc();
    final id = '${ts.millisecondsSinceEpoch}_${++_monotonic}';
    final event = MemoryEvent(
      id: id,
      timestamp: ts,
      kind: kind,
      data: data,
    );

    _ring.add(event);
    if (_ring.length > _ringCapacity) {
      _ring.removeRange(0, _ring.length - _ringCapacity);
    }

    final dir = await _resolveMemoryDir();
    if (dir == null) return event; // headless / test mode

    try {
      final file = File('${dir.path}/${_monthlyFilename(ts)}');
      file.writeAsStringSync(
        '${jsonEncode(event.toJson())}\n',
        mode: FileMode.append,
        flush: false,
      );
    } catch (e, st) {
      debugPrint('[MemoryEventLog] write fail: $e\n$st');
    }
    return event;
  }

  /// Query iz trenutnog meseca + ringa. Limit poslednjih N (newest first).
  ///
  /// Cross-month query je deferred — koristi explicit `queryRange(from, to)`
  /// koji čita više fajlova.
  Future<List<MemoryEvent>> query({
    String? kind,
    DateTime? since,
    int limit = 100,
  }) async {
    // Filter ring first.
    Iterable<MemoryEvent> filtered = _ring.reversed;
    if (kind != null) {
      filtered = filtered.where((e) => e.kind == kind);
    }
    if (since != null) {
      filtered = filtered.where((e) => e.timestamp.isAfter(since));
    }
    final ringHit = filtered.take(limit).toList(growable: false);
    if (ringHit.length >= limit) return ringHit;

    // Need disk read — load this month's file.
    final dir = await _resolveMemoryDir();
    if (dir == null) return ringHit;

    final monthFile =
        File('${dir.path}/${_monthlyFilename(DateTime.now().toUtc())}');
    if (!monthFile.existsSync()) return ringHit;

    try {
      final lines = monthFile.readAsLinesSync();
      // Reverse iter to newest-first.
      final out = <MemoryEvent>[...ringHit];
      final seenIds = ringHit.map((e) => e.id).toSet();
      for (final line in lines.reversed) {
        if (out.length >= limit) break;
        if (line.isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final ev = MemoryEvent.fromJson(json);
          if (seenIds.contains(ev.id)) continue;
          if (kind != null && ev.kind != kind) continue;
          if (since != null && !ev.timestamp.isAfter(since)) continue;
          out.add(ev);
        } catch (_) {
          // Skip malformed line.
        }
      }
      return out;
    } catch (e, st) {
      debugPrint('[MemoryEventLog] query fail: $e\n$st');
      return ringHit;
    }
  }

  /// In-memory only — za UI quick refresh bez disk I/O.
  List<MemoryEvent> recentCached({int n = 50, String? kind}) {
    Iterable<MemoryEvent> rev = _ring.reversed;
    if (kind != null) rev = rev.where((e) => e.kind == kind);
    return rev.take(n).toList(growable: false);
  }

  /// Aggregirana statistika kroz ring + this-month disk. Vraća
  /// `Map<kind, count>` za quick dashboard chart.
  Future<Map<String, int>> kindCounts() async {
    final counts = <String, int>{};
    for (final ev in _ring) {
      counts[ev.kind] = (counts[ev.kind] ?? 0) + 1;
    }
    // Disk merge — for accurate aggregate beyond ring.
    final dir = await _resolveMemoryDir();
    if (dir == null) return counts;
    final monthFile =
        File('${dir.path}/${_monthlyFilename(DateTime.now().toUtc())}');
    if (!monthFile.existsSync()) return counts;
    try {
      final lines = monthFile.readAsLinesSync();
      final seenIds = _ring.map((e) => e.id).toSet();
      for (final line in lines) {
        if (line.isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final id = json['id'] as String? ?? '';
          if (seenIds.contains(id)) continue;
          final kind = json['kind'] as String? ?? 'unknown';
          counts[kind] = (counts[kind] ?? 0) + 1;
        } catch (_) {
          // Skip malformed.
        }
      }
    } catch (e, st) {
      debugPrint('[MemoryEventLog] kindCounts fail: $e\n$st');
    }
    return counts;
  }

  /// Cleanup fajlova starijih od N dana. Kroz idle daemon ili user action.
  Future<int> purgeOlderThan({required int days}) async {
    if (days < 1) return 0;
    final dir = await _resolveMemoryDir();
    if (dir == null) return 0;

    final cutoff = DateTime.now().subtract(Duration(days: days));
    int deleted = 0;
    try {
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.jsonl')) continue;
        final stat = entity.statSync();
        if (stat.modified.isBefore(cutoff)) {
          entity.deleteSync();
          deleted++;
        }
      }
    } catch (e, st) {
      debugPrint('[MemoryEventLog] purge fail: $e\n$st');
    }
    return deleted;
  }

  // ── Internal helpers ──────────────────────────────────────────────────

  Future<Directory?> _resolveMemoryDir() async {
    if (_memoryDir != null && _memoryDir!.existsSync()) return _memoryDir;
    try {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return null;
      final basePath = Platform.isMacOS
          ? '$home/Library/Application Support/FluxForge Studio'
          : '$home/.fluxforge';
      final dir = Directory('$basePath/memory');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _memoryDir = dir;
      return dir;
    } catch (e, st) {
      debugPrint('[MemoryEventLog] resolve dir fail: $e\n$st');
      return null;
    }
  }

  String _monthlyFilename(DateTime ts) {
    final yyyy = ts.year.toString().padLeft(4, '0');
    final mm = ts.month.toString().padLeft(2, '0');
    return 'events_$yyyy-$mm.jsonl';
  }

  /// Test helper — clear ring + cancel subs. NE briše disk fajlove.
  @visibleForTesting
  void clearForTest() {
    _ring.clear();
    _feedbackSub?.cancel();
    _warningsSub?.cancel();
    _feedbackSub = null;
    _warningsSub = null;
    _monotonic = 0;
  }

  /// Test helper — inject custom dir za hermetičke disk testove.
  @visibleForTesting
  void setMemoryDirForTest(Directory? dir) {
    _memoryDir = dir;
  }
}
