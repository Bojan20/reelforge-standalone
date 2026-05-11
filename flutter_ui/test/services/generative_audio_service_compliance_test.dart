// FAZA 5.1.8 — Dart-side compliance manifest parsing.
//
// These tests pin the wire contract between rf-generative's serde-emitted
// JSON (see compliance.rs::serde_round_trip) and the Dart parser. If the
// Rust side renames a field or changes a level encoding, the failure
// surfaces here long before it shows up as a blank badge in the UI.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/generative_audio_service.dart';

void main() {
  group('ComplianceLevel.parse', () {
    test('accepts snake_case wire values', () {
      expect(ComplianceLevel.parse('pass'), ComplianceLevel.pass);
      expect(ComplianceLevel.parse('warn'), ComplianceLevel.warn);
      expect(ComplianceLevel.parse('fail'), ComplianceLevel.fail);
    });

    test('unknown / null defaults to warn (loud, not silent)', () {
      expect(ComplianceLevel.parse(null), ComplianceLevel.warn);
      expect(ComplianceLevel.parse('weird'), ComplianceLevel.warn);
      expect(ComplianceLevel.parse(''), ComplianceLevel.warn);
    });

    test('comparison ordering matches Rust derive', () {
      // Rust: Pass < Warn < Fail. Same here so callers can write
      // `if (level.index >= warn.index)` safely.
      expect(ComplianceLevel.pass.index < ComplianceLevel.warn.index, isTrue);
      expect(ComplianceLevel.warn.index < ComplianceLevel.fail.index, isTrue);
    });
  });

  group('ComplianceReport.fromJson', () {
    test('parses a full report end-to-end', () {
      final json = {
        'level': 'warn',
        'findings': [
          {
            'id': 'peak-too-hot',
            'level': 'warn',
            'message': 'Peak -0.42 dBFS exceeds headroom',
            'value': -0.42,
          },
          {
            'id': 'clean',
            'level': 'pass',
            'message': 'All compliance checks passed',
          },
        ],
        'peak_dbfs': -0.42,
        'rms_dbfs': -12.5,
        'dc_offset': 0.001,
        'clip_count': 0,
        'nan_count': 0,
        'silence_ratio': 0.05,
        'duration_seconds': 1.0,
      };
      final r = ComplianceReport.fromJson(json);
      expect(r.level, ComplianceLevel.warn);
      expect(r.findings.length, 2);
      expect(r.findings.first.id, 'peak-too-hot');
      expect(r.findings.first.value, closeTo(-0.42, 1e-6));
      expect(r.peakDbfs, closeTo(-0.42, 1e-6));
      expect(r.clipCount, 0);
      expect(r.silenceRatio, closeTo(0.05, 1e-6));
    });

    test('peak_dbfs encoded as -Infinity string parses as -inf', () {
      // serde_json emits `-Infinity` (bare token) which Dart's jsonDecode
      // rejects with `FormatException`. Most clients pre-sanitize, but a
      // string form survives — our parser accepts both.
      final r = ComplianceReport.fromJson(const {
        'level': 'fail',
        'findings': [],
        'peak_dbfs': '-Infinity',
        'rms_dbfs': '-Infinity',
        'dc_offset': 0.0,
        'clip_count': 0,
        'nan_count': 0,
        'silence_ratio': 1.0,
        'duration_seconds': 0.0,
      });
      expect(r.peakDbfs.isInfinite, isTrue);
      expect(r.peakDbfs.isNegative, isTrue);
      expect(r.rmsDbfs.isInfinite, isTrue);
    });

    test('missing / malformed findings degrades to empty list', () {
      final r = ComplianceReport.fromJson(const {
        'level': 'pass',
        'findings': 'not a list',
        'peak_dbfs': -6.0,
        'rms_dbfs': -12.0,
        'dc_offset': 0.0,
        'clip_count': 0,
        'nan_count': 0,
        'silence_ratio': 0.0,
        'duration_seconds': 1.0,
      });
      expect(r.findings, isEmpty);
      // Level still parsed.
      expect(r.level, ComplianceLevel.pass);
    });

    test('missing fields default to safe values, not crash', () {
      final r = ComplianceReport.fromJson(const {'level': 'pass'});
      expect(r.level, ComplianceLevel.pass);
      expect(r.findings, isEmpty);
      expect(r.peakDbfs, 0.0);
      expect(r.clipCount, 0);
    });
  });

  group('ComplianceReport.unknown stub', () {
    test('emits a warn-level no-report finding (never silent pass)', () {
      final r = ComplianceReport.unknown();
      expect(r.level, ComplianceLevel.warn);
      expect(r.findings.single.id, 'no-report');
      expect(r.isPass, isFalse);
      expect(r.isFail, isFalse);
    });
  });

  group('GenerationMetadata.fromJson with compliance', () {
    test('embedded compliance object is parsed into metadata', () {
      final json = {
        'backend_id': 'mock',
        'model_id': 'none',
        'seed': 42,
        'generated_at_utc': '2026-05-11T00:00:00Z',
        'duration_seconds': 1.0,
        'frame_count': 48000,
        'compliance': {
          'level': 'pass',
          'findings': [
            {
              'id': 'clean',
              'level': 'pass',
              'message': 'All compliance checks passed',
            }
          ],
          'peak_dbfs': -6.0,
          'rms_dbfs': -12.0,
          'dc_offset': 0.0,
          'clip_count': 0,
          'nan_count': 0,
          'silence_ratio': 0.05,
          'duration_seconds': 1.0,
        },
      };
      final m = GenerationMetadata.fromJson(json);
      expect(m.compliance.isPass, isTrue);
      expect(m.compliance.findings.first.id, 'clean');
    });

    test('legacy metadata without compliance falls back to unknown stub', () {
      final json = {
        'backend_id': 'mock',
        'model_id': 'none',
        'seed': 42,
        'generated_at_utc': '2026-05-11T00:00:00Z',
        'duration_seconds': 1.0,
        'frame_count': 48000,
      };
      final m = GenerationMetadata.fromJson(json);
      expect(m.compliance.level, ComplianceLevel.warn);
      expect(m.compliance.findings.single.id, 'no-report');
    });
  });

  group('worstFindings filter', () {
    test('returns only findings matching the report level', () {
      final r = ComplianceReport.fromJson(const {
        'level': 'fail',
        'findings': [
          {'id': 'a', 'level': 'fail', 'message': 'A'},
          {'id': 'b', 'level': 'warn', 'message': 'B'},
          {'id': 'c', 'level': 'fail', 'message': 'C'},
          {'id': 'd', 'level': 'pass', 'message': 'D'},
        ],
        'peak_dbfs': -1.0,
        'rms_dbfs': -12.0,
        'dc_offset': 0.0,
        'clip_count': 0,
        'nan_count': 0,
        'silence_ratio': 0.0,
        'duration_seconds': 1.0,
      });
      final worst = r.worstFindings;
      expect(worst.length, 2);
      expect(worst.map((f) => f.id).toSet(), {'a', 'c'});
    });
  });
}
