/// FLUX_MASTER_TODO 0.5 B.4 — Event Timing Trace Exporter tests.
///
/// Pin invariants za trace export. Bez ovih testova "small tweak" na
/// stage→category mapping ili JSON shape moze tiho razbiti marketing
/// clip metadata pipeline + compliance audit trail.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/event_timing_trace_exporter.dart';
import 'package:fluxforge_ui/src/rust/native_ffi.dart';

void main() {
  SlotLabStageEvent stage(String type, double tsMs) {
    return SlotLabStageEvent(
      stageType: type,
      timestampMs: tsMs,
      payload: const {},
      rawStage: const {},
    );
  }

  group('SpinTraceReport invariants', () {
    test('durationMs racuna na osnovu prvog i poslednjeg stage-a', () {
      final report = SpinTraceReport(
        spinId: 'test-1',
        exportedAt: DateTime(2026),
        result: null,
        stages: [
          stage('REEL_SPIN_LOOP', 0),
          stage('REEL_STOP_0', 800),
          stage('REEL_STOP_4', 2400),
          stage('WIN_PRESENT', 2600),
        ],
      );
      expect(report.durationMs, equals(2600.0));
    });

    test('durationMs = 0 za <2 stage-a', () {
      final empty = SpinTraceReport(
        spinId: 'empty',
        exportedAt: DateTime(2026),
        result: null,
        stages: const [],
      );
      expect(empty.durationMs, equals(0));

      final single = SpinTraceReport(
        spinId: 'single',
        exportedAt: DateTime(2026),
        result: null,
        stages: [stage('REEL_SPIN_LOOP', 0)],
      );
      expect(single.durationMs, equals(0));
    });

    test('stagesByCategory grupise prefiks-bazirano', () {
      final report = SpinTraceReport(
        spinId: 'cat-test',
        exportedAt: DateTime(2026),
        result: null,
        stages: [
          stage('REEL_SPIN_LOOP', 0),
          stage('REEL_STOP_0', 800),
          stage('REEL_STOP_4', 2400),
          stage('ANTICIPATION_TENSION_LAYER_2', 1500),
          stage('WIN_PRESENT', 2600),
          stage('ROLLUP_START', 2700),
          stage('ROLLUP_END', 3500),
          stage('FEATURE_ENTER', 3600),
          stage('JACKPOT_TRIGGER', 5000),
          stage('CASCADE_STEP', 4000),
          stage('UI_SKIP_PRESS', 6000),
          stage('SOMETHING_WEIRD', 7000),
        ],
      );
      final cats = report.stagesByCategory();
      expect(cats['reel'], equals(3));
      expect(cats['win'], equals(3)); // WIN_ + ROLLUP_ both win category
      expect(cats['anticipation'], equals(1));
      expect(cats['feature'], equals(1));
      expect(cats['jackpot'], equals(1));
      expect(cats['cascade'], equals(1));
      expect(cats['ui'], equals(1));
      expect(cats['other'], equals(1));
    });

    test('toJson ukljucuje schema_version + stage_count + duration_ms',
        () {
      final report = SpinTraceReport(
        spinId: 'json-test',
        exportedAt: DateTime.utc(2026, 5, 10, 12, 0, 0),
        result: null,
        stages: [
          stage('REEL_SPIN_LOOP', 0),
          stage('WIN_PRESENT', 1500),
        ],
        metadata: const {'note': 'sanity'},
      );
      final json = report.toJson();
      expect(json['schema_version'], equals(1));
      expect(json['spin_id'], equals('json-test'));
      expect(json['stage_count'], equals(2));
      expect(json['duration_ms'], equals(1500.0));
      expect(json['exported_at'], equals('2026-05-10T12:00:00.000Z'));
      expect(json['stages'], hasLength(2));
      expect(json['metadata']['note'], equals('sanity'));
    });

    test('toJson ne ukljucuje result kad je null', () {
      final report = SpinTraceReport(
        spinId: 'no-result',
        exportedAt: DateTime(2026),
        result: null,
        stages: [stage('REEL_SPIN_LOOP', 0)],
      );
      final json = report.toJson();
      expect(json.containsKey('result'), isFalse);
    });

    test('toJson stages snima samo stage_type + timestamp + payload', () {
      final report = SpinTraceReport(
        spinId: 's',
        exportedAt: DateTime(2026),
        result: null,
        stages: [
          SlotLabStageEvent(
            stageType: 'REEL_STOP_0',
            timestampMs: 800,
            payload: const {'reel': 0, 'symbol_id': 5},
            rawStage: const {'verbose': 'ignored'},
          ),
        ],
      );
      final stageJson =
          (report.toJson()['stages'] as List).first as Map<String, dynamic>;
      expect(stageJson.keys, containsAll(['stage_type', 'timestamp_ms', 'payload']));
      expect(stageJson.containsKey('raw_stage'), isFalse);
      expect(stageJson['payload']['reel'], equals(0));
    });
  });
}
