// Auto-bind regression test — Boki "ne čuje se svaki reel land" (2026-05-10).
//
// Pre-fix bug:
//   reel_land_1.wav → REEL_STOP_1   (engine reel 2, should be 0)
//   reel_land_2.wav → REEL_STOP_2   (engine reel 3, should be 1)
//   reel_land_3.wav → REEL_STOP_3   (engine reel 4, should be 2)
//   reel_land_4.wav → REEL_STOP_4   (engine reel 5, should be 3)
//   reel_land_5.wav → REEL_STOP_5   (engine reel 6 — orphan on 5-reel slot)
//
// Effect: REEL_STOP_0 (the FIRST reel) had no audio bound, so the leftmost
// reel was silent every spin.  REEL_STOP_5 was bound to a file that never
// triggers on a 5-reel game.  That perfectly matches the user-visible
// symptom of "neki reel land se ne čuje".
//
// Post-fix: per-reel index correction handles BOTH the generic
// `REEL_STOP` form AND the already-indexed `REEL_STOP_N` form (which the
// prefix-alias path produces) by checking whether the existing index
// equals the filename's 1-based trailing digit.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/auto_bind/auto_bind_engine.dart';
import 'package:fluxforge_ui/services/stage_configuration_service.dart'
    show StageConfigurationService;

void main() {
  group('AutoBind reel-land 1-based → 0-based index correction', () {
    late Directory tmp;

    setUpAll(() {
      // Initialize stage taxonomy for the entire group — analyze() relies on
      // StageConfigurationService.getAllStages() being populated to know what
      // names like REEL_STOP_0..4 are valid landing targets.
      StageConfigurationService.instance.init();
    });

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('autobind_reel_stop_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// Helper: create empty audio files inside [tmp].
    void writeFiles(List<String> names) {
      for (final n in names) {
        File('${tmp.path}/$n').writeAsBytesSync(<int>[]);
      }
    }

    /// Helper: collect stage→file map from analysis (primary file per stage).
    Map<String, String> _stageMap(dynamic analysis) {
      final out = <String, String>{};
      for (final entry in analysis.stageGroups.entries) {
        // Primary is the first non-variant; analyze() puts the primary
        // first when grouping anyway.
        final group = entry.value as List;
        if (group.isEmpty) continue;
        out[entry.key as String] = (group.first.fileName as String);
      }
      return out;
    }

    test('5 reel_land_N.wav files map to REEL_STOP_0..4 (zero-based)', () {
      writeFiles([
        'reel_land_1.wav',
        'reel_land_2.wav',
        'reel_land_3.wav',
        'reel_land_4.wav',
        'reel_land_5.wav',
      ]);

      final analysis = AutoBindEngine.analyze(tmp.path);
      final stages = _stageMap(analysis);

      expect(stages['REEL_STOP_0'], 'reel_land_1.wav',
          reason: 'reel_land_1 is the FIRST reel → engine REEL_STOP_0');
      expect(stages['REEL_STOP_1'], 'reel_land_2.wav');
      expect(stages['REEL_STOP_2'], 'reel_land_3.wav');
      expect(stages['REEL_STOP_3'], 'reel_land_4.wav');
      expect(stages['REEL_STOP_4'], 'reel_land_5.wav',
          reason: 'reel_land_5 is the FIFTH reel → engine REEL_STOP_4');

      // Pre-fix bug surface: REEL_STOP_5 should NOT exist (orphan stage on
      // a 5-reel slot).  REEL_STOP (generic) should also NOT exist —
      // every file should resolve to a per-reel slot.
      expect(stages.containsKey('REEL_STOP_5'), isFalse,
          reason: 'reel_land_5 must NOT bind to REEL_STOP_5 (orphan)');
      expect(stages.containsKey('REEL_STOP'), isFalse,
          reason: 'reel_land_N must never collapse to generic REEL_STOP');
    });

    test('reelStop1..reelStop5.wav (CamelCase) also remap correctly', () {
      writeFiles([
        'reelStop1.wav',
        'reelStop2.wav',
        'reelStop3.wav',
        'reelStop4.wav',
        'reelStop5.wav',
      ]);

      final analysis = AutoBindEngine.analyze(tmp.path);
      final stages = _stageMap(analysis);

      expect(stages['REEL_STOP_0'], 'reelStop1.wav');
      expect(stages['REEL_STOP_1'], 'reelStop2.wav');
      expect(stages['REEL_STOP_2'], 'reelStop3.wav');
      expect(stages['REEL_STOP_3'], 'reelStop4.wav');
      expect(stages['REEL_STOP_4'], 'reelStop5.wav');
    });

    test('reelClick1..reelClick5.wav remap correctly', () {
      writeFiles([
        'reelClick1.wav',
        'reelClick2.wav',
        'reelClick3.wav',
        'reelClick4.wav',
        'reelClick5.wav',
      ]);

      final analysis = AutoBindEngine.analyze(tmp.path);
      final stages = _stageMap(analysis);

      expect(stages['REEL_STOP_0'], 'reelClick1.wav');
      expect(stages['REEL_STOP_4'], 'reelClick5.wav');
    });

    test('a single un-numbered reel_land.wav stays on generic REEL_STOP', () {
      writeFiles(['reel_land.wav']);

      final analysis = AutoBindEngine.analyze(tmp.path);
      final stages = _stageMap(analysis);

      // No trailing digit → no per-reel correction → goes to REEL_STOP.
      expect(stages.containsKey('REEL_STOP'), isTrue);
      expect(stages.containsKey('REEL_STOP_0'), isFalse);
    });

    test('partial folder (3 files) still maps to REEL_STOP_0..2', () {
      writeFiles([
        'reel_land_1.wav',
        'reel_land_2.wav',
        'reel_land_3.wav',
      ]);

      final analysis = AutoBindEngine.analyze(tmp.path);
      final stages = _stageMap(analysis);

      expect(stages['REEL_STOP_0'], 'reel_land_1.wav');
      expect(stages['REEL_STOP_1'], 'reel_land_2.wav');
      expect(stages['REEL_STOP_2'], 'reel_land_3.wav');
      expect(stages.containsKey('REEL_STOP_3'), isFalse);
      expect(stages.containsKey('REEL_STOP_4'), isFalse);
    });
  });
}
