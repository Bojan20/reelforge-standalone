/// FAZA 4.2.4 — `AudioComplianceGuard` unit tests.
///
/// Pokriva sve 3 validator-a + boundary thresholds + batch validate +
/// stream emit + ring growth/cap.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/compliance/audio_compliance_guard.dart';

void main() {
  group('AudioComplianceGuard — LDW Validator', () {
    late AudioComplianceGuard guard;
    setUp(() => guard = AudioComplianceGuard());
    tearDown(() async => await guard.dispose());

    test('WIN_BIG with win = bet (LDW) → block', () {
      final w = guard.validate(stage: 'WIN_BIG', win: 1.0, bet: 1.0);
      expect(w, isNotNull);
      expect(w!.ruleId, 'ldw_disguise');
      expect(w.severity, ComplianceWarningSeverity.block);
      expect(w.jurisdiction, 'UKGC');
    });

    test('WIN_BIG with win = bet * 1.05 (still LDW) → block', () {
      final w = guard.validate(stage: 'WIN_BIG', win: 1.05, bet: 1.0);
      expect(w, isNotNull);
      expect(w!.ruleId, 'ldw_disguise');
    });

    test('WIN_BIG with win = bet * 1.1 (boundary) → still LDW', () {
      // ratio <= 1.1 → LDW
      final w = guard.validate(stage: 'WIN_BIG', win: 1.1, bet: 1.0);
      expect(w, isNotNull);
    });

    test('WIN_BIG with win = bet * 1.5 (safe) → null', () {
      final w = guard.validate(stage: 'WIN_BIG', win: 1.5, bet: 1.0);
      expect(w, isNull);
    });

    test('WIN_MASSIVE / WIN_MEGA also trigger LDW', () {
      expect(
        guard.validate(stage: 'WIN_MASSIVE', win: 1.0, bet: 1.0),
        isNotNull,
      );
      guard.clearForTest();
      expect(
        guard.validate(stage: 'WIN_MEGA', win: 1.0, bet: 1.0),
        isNotNull,
      );
    });

    test('Non-celebration stage (REEL_STOP) skips LDW even with LDW math', () {
      final w = guard.validate(stage: 'REEL_STOP_3', win: 1.0, bet: 1.0);
      expect(w, isNull);
    });

    test('Missing win/bet → skip LDW gracefully', () {
      final w = guard.validate(stage: 'WIN_BIG'); // no win/bet
      expect(w, isNull);
    });

    test('Bet = 0 → skip LDW (no division by zero)', () {
      final w = guard.validate(stage: 'WIN_BIG', win: 100, bet: 0);
      expect(w, isNull);
    });
  });

  group('AudioComplianceGuard — Celebration LUFS Validator', () {
    late AudioComplianceGuard guard;
    setUp(() => guard = AudioComplianceGuard());
    tearDown(() async => await guard.dispose());

    test('WIN_BIG with LUFS = -10 (loud) → warn', () {
      final w = guard.validate(
        stage: 'WIN_BIG',
        win: 100,
        bet: 1.0, // safe ratio
        integratedLufs: -10.0,
      );
      expect(w, isNotNull);
      expect(w!.ruleId, 'celebration_lufs');
      expect(w.severity, ComplianceWarningSeverity.warn);
    });

    test('WIN_BIG with LUFS = -16 (exact cap) → no warn', () {
      final w = guard.validate(
        stage: 'WIN_BIG',
        win: 100,
        bet: 1.0,
        integratedLufs: -16.0,
      );
      expect(w, isNull);
    });

    test('WIN_BIG with LUFS = -20 (quiet) → null', () {
      final w = guard.validate(
        stage: 'WIN_BIG',
        win: 100,
        bet: 1.0,
        integratedLufs: -20.0,
      );
      expect(w, isNull);
    });

    test('Non-celebration stage skips LUFS check', () {
      final w = guard.validate(
        stage: 'REEL_STOP',
        integratedLufs: -5.0, // very loud
      );
      expect(w, isNull);
    });
  });

  group('AudioComplianceGuard — stream + ring', () {
    test('warning is emitted on validate', () async {
      final guard = AudioComplianceGuard();
      final emitted = <ComplianceWarning>[];
      final sub = guard.warnings.listen(emitted.add);

      guard.validate(stage: 'WIN_BIG', win: 1.0, bet: 1.0);
      await Future<void>.delayed(Duration.zero);

      expect(emitted.length, 1);
      expect(emitted.first.ruleId, 'ldw_disguise');

      await sub.cancel();
      await guard.dispose();
    });

    test('no warning emitted when validate passes', () async {
      final guard = AudioComplianceGuard();
      final emitted = <ComplianceWarning>[];
      final sub = guard.warnings.listen(emitted.add);

      guard.validate(stage: 'REEL_STOP', win: 1.0, bet: 1.0);
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isEmpty);

      await sub.cancel();
      await guard.dispose();
    });

    test('ring grows but caps at 50', () async {
      final guard = AudioComplianceGuard();
      for (int i = 0; i < 60; i++) {
        guard.validate(stage: 'WIN_BIG', win: 1.0, bet: 1.0);
      }
      expect(guard.recent.length, 50);
      await guard.dispose();
    });
  });

  group('AudioComplianceGuard — batch validate', () {
    test('batch over heterogeneous contexts', () {
      final guard = AudioComplianceGuard();
      final results = guard.validateBatch(contexts: {
        'WIN_BIG': (win: 1.0, bet: 1.0, lufs: null), // LDW
        'WIN_MASSIVE': (win: 100, bet: 1.0, lufs: -10.0), // LUFS
        'REEL_STOP': (win: 1.0, bet: 1.0, lufs: null), // safe
        'WIN_MEGA': (win: 100, bet: 1.0, lufs: -20.0), // safe
      });
      expect(results.length, 2);
      expect(results.any((r) => r.ruleId == 'ldw_disguise'), isTrue);
      expect(results.any((r) => r.ruleId == 'celebration_lufs'), isTrue);
    });
  });

  group('ComplianceWarning — JSON shape', () {
    test('toJson contains all required fields', () {
      final w = ComplianceWarning(
        ruleId: 'ldw_disguise',
        message: 'msg',
        suggestion: 'sg',
        severity: ComplianceWarningSeverity.block,
        stage: 'WIN_BIG',
        jurisdiction: 'UKGC',
        timestamp: DateTime.parse('2026-05-11T18:00:00Z'),
      );
      final j = w.toJson();
      expect(j['rule_id'], 'ldw_disguise');
      expect(j['severity'], 'block');
      expect(j['stage'], 'WIN_BIG');
      expect(j['jurisdiction'], 'UKGC');
      expect(j['timestamp'], '2026-05-11T18:00:00.000Z');
    });

    test('toJson omits jurisdiction when null', () {
      final w = ComplianceWarning(
        ruleId: 'r',
        message: 'm',
        suggestion: 's',
        severity: ComplianceWarningSeverity.info,
        stage: 'X',
      );
      expect(w.toJson().containsKey('jurisdiction'), isFalse);
    });
  });
}
