/// FAZA 4.3.1 — `MemoryEventLog` unit tests.
///
/// Pokriva:
/// - record() generiše unique id + timestamp + JSON shape
/// - ring growth + capacity cap (200)
/// - recentCached(n, kind) filter + newest-first
/// - kindCounts aggregation
/// - JSON roundtrip (toJson / fromJson)
/// - auto-hooks: feedback stream → predictive_accept / _reject
/// - auto-hooks: compliance warning → compliance_warning
///
/// Disk I/O testovi koriste hermetički temp dir.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/compliance/audio_compliance_guard.dart';
import 'package:fluxforge_ui/services/memory/memory_event_log.dart';
import 'package:fluxforge_ui/services/predictive/predictive_analyzer.dart';

void main() {
  group('MemoryEventLog — record + ring', () {
    late MemoryEventLog log;
    late Directory tempDir;

    setUp(() async {
      log = MemoryEventLog.instance;
      log.clearForTest();
      tempDir = await Directory.systemTemp.createTemp('memory_log_test_');
      log.setMemoryDirForTest(tempDir);
    });

    tearDown(() async {
      log.clearForTest();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('record generates unique id + timestamp', () async {
      final e1 = await log.record(kind: 'test_kind', data: {'k': 'v'});
      final e2 = await log.record(kind: 'test_kind', data: {'k': 'v2'});

      expect(e1.id, isNot(equals(e2.id)));
      expect(e1.kind, 'test_kind');
      expect(e1.data['k'], 'v');
      expect(e2.data['k'], 'v2');
      // Timestamp je monotone (e2 >= e1 always)
      expect(e2.timestamp.isAfter(e1.timestamp) ||
              e2.timestamp.isAtSameMomentAs(e1.timestamp), isTrue);
    });

    test('ring grows but caps at 200', () async {
      for (int i = 0; i < 250; i++) {
        await log.record(kind: 'k_$i');
      }
      final cached = log.recentCached(n: 1000);
      expect(cached.length, 200);
      // Newest first
      expect(cached.first.kind, 'k_249');
    });

    test('recentCached filter by kind', () async {
      for (int i = 0; i < 10; i++) {
        await log.record(kind: i.isEven ? 'even' : 'odd');
      }
      final even = log.recentCached(kind: 'even');
      expect(even.length, 5);
      expect(even.every((e) => e.kind == 'even'), isTrue);
    });
  });

  group('MemoryEvent — JSON roundtrip', () {
    test('toJson + fromJson preserves all fields', () {
      final ts = DateTime.parse('2026-05-11T18:00:00Z');
      final ev = MemoryEvent(
        id: 'abc_1',
        timestamp: ts,
        kind: 'spin_completed',
        data: {'win': 100, 'bet': 1.0, 'multiplier': 100.0},
      );
      final json = ev.toJson();
      final back = MemoryEvent.fromJson(json);
      expect(back.id, ev.id);
      expect(back.kind, ev.kind);
      expect(back.timestamp.toUtc(), ts);
      expect(back.data['win'], 100);
      expect(back.data['multiplier'], 100.0);
    });

    test('fromJson handles missing data field', () {
      final back = MemoryEvent.fromJson({
        'id': 'x',
        'ts': '2026-05-11T18:00:00Z',
        'kind': 'k',
      });
      expect(back.data, isEmpty);
    });
  });

  group('MemoryEventLog — kindCounts', () {
    late MemoryEventLog log;
    setUp(() {
      log = MemoryEventLog.instance;
      log.clearForTest();
      log.setMemoryDirForTest(null);
    });

    test('aggregates ring counts per kind', () async {
      await log.record(kind: 'assignment_set');
      await log.record(kind: 'assignment_set');
      await log.record(kind: 'spin_completed');
      final counts = await log.kindCounts();
      expect(counts['assignment_set'], 2);
      expect(counts['spin_completed'], 1);
    });
  });

  group('MemoryEventLog — auto-hooks', () {
    late MemoryEventLog log;
    setUp(() {
      log = MemoryEventLog.instance;
      log.clearForTest();
      log.setMemoryDirForTest(null);
    });

    test('predictive accept event → predictive_accept record', () async {
      final analyzer = PredictiveAnalyzer.forTest();
      log.attachAutoHooks(analyzer: analyzer);

      analyzer.recordFeedback(
        audioPath: '/x.wav',
        suggestedStage: 'REEL_STOP',
        suggestedConfidence: 0.85,
        actualStage: 'REEL_STOP',
        accepted: true,
      );
      await Future<void>.delayed(Duration.zero);

      final cached = log.recentCached();
      expect(cached.length, 1);
      expect(cached.first.kind, 'predictive_accept');
      expect(cached.first.data['audioPath'], '/x.wav');

      await analyzer.dispose();
    });

    test('predictive reject event → predictive_reject record', () async {
      final analyzer = PredictiveAnalyzer.forTest();
      log.attachAutoHooks(analyzer: analyzer);

      analyzer.recordFeedback(
        audioPath: '/y.wav',
        suggestedStage: 'WIN_BIG',
        suggestedConfidence: 0.42,
        actualStage: null,
        accepted: false,
      );
      await Future<void>.delayed(Duration.zero);

      final cached = log.recentCached();
      expect(cached.length, 1);
      expect(cached.first.kind, 'predictive_reject');

      await analyzer.dispose();
    });

    test('compliance warning event → compliance_warning record', () async {
      final guard = AudioComplianceGuard();
      log.attachAutoHooks(guard: guard);

      guard.validate(stage: 'WIN_BIG', win: 1.0, bet: 1.0);
      await Future<void>.delayed(Duration.zero);

      final cached = log.recentCached();
      expect(cached.length, 1);
      expect(cached.first.kind, 'compliance_warning');
      expect(cached.first.data['rule_id'], 'ldw_disguise');

      await guard.dispose();
    });

    test('re-attach is idempotent — no duplicate hooks', () async {
      final analyzer = PredictiveAnalyzer.forTest();
      log.attachAutoHooks(analyzer: analyzer);
      log.attachAutoHooks(analyzer: analyzer); // double attach

      analyzer.recordFeedback(
        audioPath: '/z.wav',
        suggestedStage: 'X',
        suggestedConfidence: 0.5,
        actualStage: null,
        accepted: false,
      );
      await Future<void>.delayed(Duration.zero);

      expect(log.recentCached().length, 1); // not 2

      await analyzer.dispose();
    });
  });

  group('MemoryEventLog — disk persistence', () {
    late MemoryEventLog log;
    late Directory tempDir;

    setUp(() async {
      log = MemoryEventLog.instance;
      log.clearForTest();
      tempDir = await Directory.systemTemp.createTemp('mem_disk_');
      log.setMemoryDirForTest(tempDir);
    });

    tearDown(() async {
      log.clearForTest();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('record writes JSONL line to disk', () async {
      await log.record(kind: 'persisted', data: {'foo': 'bar'});
      final files = tempDir.listSync().whereType<File>().toList();
      expect(files.length, 1);
      expect(files.first.path.endsWith('.jsonl'), isTrue);
      final lines = files.first.readAsLinesSync();
      expect(lines.length, 1);
      expect(lines.first.contains('persisted'), isTrue);
      expect(lines.first.contains('"foo":"bar"'), isTrue);
    });

    test('query after ring eviction reads from disk', () async {
      // Record 250 events → ring drops oldest 50.
      for (int i = 0; i < 250; i++) {
        await log.record(kind: 'q_$i');
      }
      // Newest-first across ring + disk = full 250 entries.
      final all = await log.query(limit: 300);
      expect(all.length, 250);
      // First (newest) is q_249.
      expect(all.first.kind, 'q_249');
    });

    test('query filter by kind', () async {
      await log.record(kind: 'A');
      await log.record(kind: 'B');
      await log.record(kind: 'A');
      final aOnly = await log.query(kind: 'A');
      expect(aOnly.length, 2);
      expect(aOnly.every((e) => e.kind == 'A'), isTrue);
    });
  });
}
