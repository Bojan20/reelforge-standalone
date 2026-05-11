/// FAZA 4.3.3 — `StyleFingerprint` + service unit tests.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/memory/style_fingerprint.dart';

StyleFingerprint _sample({String? name}) => StyleFingerprint(
      version: StyleFingerprint.currentVersion,
      name: name ?? 'Cinematic Test',
      audioDna: const {
        'brand': 'FluxForge',
        'bpm_min': 120.0,
        'bpm_max': 140.0,
        'root_key': 'C',
        'mode': 'minor',
        'instruments': ['piano', 'strings'],
      },
      assignmentsTemplate: const {
        'REEL_STOP_*': '*reel_stop*.wav',
        'WIN_BIG': '*big_win*.wav',
      },
      busProfile: const {
        'sfx': {'volume': 0.85, 'pan': 0.0},
        'music': {'volume': 0.7, 'pan': 0.0},
      },
      complianceTargets: const {
        'jurisdictions': ['UKGC', 'MGA'],
        'ldw_cap_ratio': 1.1,
        'near_miss_cap': 0.03,
      },
      metadata: {
        'author': 'Boki',
        'created_at': DateTime.parse('2026-05-11T18:00:00Z').toIso8601String(),
      },
    );

void main() {
  group('StyleFingerprint — JSON roundtrip', () {
    test('toJson + fromJson preserves all fields', () {
      final fp = _sample();
      final json = fp.toJson();
      final back = StyleFingerprint.fromJson(json);
      expect(back.version, fp.version);
      expect(back.name, fp.name);
      expect(back.audioDna['brand'], 'FluxForge');
      expect(back.audioDna['instruments'], ['piano', 'strings']);
      expect(back.assignmentsTemplate['REEL_STOP_*'], '*reel_stop*.wav');
      expect(back.busProfile['sfx']?['volume'], 0.85);
      expect(back.complianceTargets['ldw_cap_ratio'], 1.1);
      expect(back.metadata['author'], 'Boki');
    });

    test('fromJson handles minimal payload', () {
      final back = StyleFingerprint.fromJson({
        'version': '1.0.0',
        'name': 'Empty',
      });
      expect(back.name, 'Empty');
      expect(back.audioDna, isEmpty);
      expect(back.assignmentsTemplate, isEmpty);
      expect(back.busProfile, isEmpty);
    });

    test('fromJson rejects incompatible major version', () {
      expect(
        () => StyleFingerprint.fromJson({
          'version': '2.0.0', // future major
          'name': 'Future',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson accepts same-major minor bumps', () {
      // 1.0.0 → 1.5.0 should still load (backward-compat within major).
      final back = StyleFingerprint.fromJson({
        'version': '1.5.0',
        'name': 'Minor bump',
      });
      expect(back.version, '1.5.0');
    });
  });

  group('StyleFingerprintService — export/import roundtrip', () {
    late Directory tempDir;
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('style_test_');
    });
    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('export → import preserves fingerprint', () async {
      final fp = _sample(name: 'Roundtrip');
      final outPath = '${tempDir.path}/test.style';
      final exported = await StyleFingerprintService.export(
        fingerprint: fp,
        outPath: outPath,
      );
      expect(exported, isTrue);
      expect(File(outPath).existsSync(), isTrue);

      final imported = StyleFingerprintService.import(outPath);
      expect(imported, isNotNull);
      expect(imported!.name, 'Roundtrip');
      expect(imported.audioDna['brand'], 'FluxForge');
    });

    test('import returns null for missing file', () {
      final result = StyleFingerprintService.import('${tempDir.path}/nope.style');
      expect(result, isNull);
    });

    test('import returns null for malformed JSON', () async {
      final bad = File('${tempDir.path}/bad.style');
      await bad.writeAsString('not json at all{');
      final result = StyleFingerprintService.import(bad.path);
      expect(result, isNull);
    });

    test('export is pretty-printed (newlines + indent)', () async {
      final fp = _sample();
      final outPath = '${tempDir.path}/pretty.style';
      await StyleFingerprintService.export(
        fingerprint: fp,
        outPath: outPath,
      );
      final content = File(outPath).readAsStringSync();
      expect(content.contains('\n'), isTrue);
      expect(content.contains('  '), isTrue); // 2-space indent
    });
  });

  group('StyleFingerprintService — safeFilenameFor', () {
    test('handles common cases', () {
      final f1 = StyleFingerprintService.safeFilenameFor('My Cool Style');
      expect(f1.endsWith('.style'), isTrue);
      expect(f1, contains('my_cool_style_'));
      expect(f1, isNot(contains(' ')));
    });

    test('strips unsafe characters', () {
      final f = StyleFingerprintService.safeFilenameFor('a/b\\c:d*e');
      expect(f, isNot(contains('/')));
      expect(f, isNot(contains('\\')));
      expect(f, isNot(contains(':')));
      expect(f, isNot(contains('*')));
    });

    test('collapses repeated underscores', () {
      final f = StyleFingerprintService.safeFilenameFor('a    b____c');
      expect(f, isNot(contains('__')));
    });
  });
}
