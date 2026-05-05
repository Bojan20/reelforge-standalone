/// Tests for StageAssetCsvExporter (RFC 4180 + UTF-8 BOM contract).
///
/// Pre-fix the exporter wrote LF line endings without a BOM and only
/// wrapped fields in quotes for `,` `"` `\n` — bare `\r` slipped through
/// and Excel-Windows mojibake'd non-ASCII payload paths. These tests pin
/// the new contract so future refactors cannot silently regress it.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/middleware_models.dart';
import 'package:fluxforge_ui/services/stage_asset_csv_exporter.dart';

MiddlewareEvent _evt({
  required String stage,
  required String name,
  required String assetId,
  String bus = 'SFX',
}) {
  return MiddlewareEvent(
    id: '$stage::$name',
    name: name,
    stage: stage,
    actions: [
      MiddlewareAction(id: 'a1', assetId: assetId, bus: bus),
    ],
  );
}

void main() {
  group('StageAssetCsvExporter — RFC 4180 contract', () {
    test('starts with UTF-8 BOM so Excel auto-detects UTF-8', () {
      final csv = StageAssetCsvExporter.exportToCsv([
        _evt(stage: 'UI_SPIN_PRESS', name: 'onUiSpin', assetId: '/a/spin.wav'),
      ]);
      expect(csv.codeUnitAt(0), 0xFEFF,
          reason: 'CSV must lead with U+FEFF BOM (Excel-Windows compat)');
    });

    test('uses CRLF record separators, never bare LF', () {
      final csv = StageAssetCsvExporter.exportToCsv([
        _evt(stage: 'A', name: 'x', assetId: '/a.wav'),
        _evt(stage: 'B', name: 'y', assetId: '/b.wav'),
      ]);
      // Header + 2 rows = 3 CRLF
      final crlfCount = '\r\n'.allMatches(csv).length;
      expect(crlfCount, 3,
          reason: 'each line must terminate with \\r\\n per RFC 4180');
      // Strip CRLF then assert no orphan LF or CR remains.
      final stripped = csv.replaceAll('\r\n', '');
      expect(stripped.contains('\n'), isFalse,
          reason: 'no bare LF allowed (would break strict parsers)');
      expect(stripped.contains('\r'), isFalse,
          reason: 'no bare CR allowed');
    });

    test('header is exactly the documented column order', () {
      final csv = StageAssetCsvExporter.exportToCsv([]);
      // Strip BOM, take first line.
      final firstLine = csv.substring(1).split('\r\n').first;
      expect(
        firstLine,
        'stage,event_name,audio_path,volume,pan,offset,bus,fade_in,fade_out,trim_start,trim_end,ale_layer',
      );
    });

    test('fields with comma are quoted', () {
      final csv = StageAssetCsvExporter.exportToCsv([
        _evt(stage: 'S', name: 'evt,with,commas', assetId: '/a.wav'),
      ]);
      expect(csv.contains('"evt,with,commas"'), isTrue);
    });

    test('fields with double quotes get RFC 4180 quote-doubling', () {
      final csv = StageAssetCsvExporter.exportToCsv([
        _evt(stage: 'S', name: 'has "quote"', assetId: '/a.wav'),
      ]);
      // RFC 4180: " inside quoted field becomes ""
      expect(csv.contains('"has ""quote"""'), isTrue);
    });

    test('field with bare CR is quoted (regression guard)', () {
      // Pre-fix this slipped through unquoted because the escaper only
      // checked \n. A bare \r in an asset path (Windows clipboard paste)
      // would split the row mid-field for strict parsers.
      final csv = StageAssetCsvExporter.exportToCsv([
        _evt(stage: 'S', name: 'evt', assetId: '/path\rwith\rcr.wav'),
      ]);
      expect(csv.contains('"/path\rwith\rcr.wav"'), isTrue);
    });

    test('field with LF is quoted', () {
      final csv = StageAssetCsvExporter.exportToCsv([
        _evt(stage: 'S', name: 'multi\nline', assetId: '/a.wav'),
      ]);
      expect(csv.contains('"multi\nline"'), isTrue);
    });

    test('skips events with empty stage', () {
      final csv = StageAssetCsvExporter.exportToCsv([
        MiddlewareEvent(
          id: 'no-stage',
          name: 'orphan',
          // stage stays at default ''
          actions: [
            MiddlewareAction(id: 'a', assetId: '/x.wav'),
          ],
        ),
      ]);
      // After header (BOM + header + CRLF) the body should be empty.
      final body = csv.split('\r\n').skip(1).where((l) => l.isNotEmpty);
      expect(body, isEmpty);
    });

    test('round-trips a UTF-8 stage label without mojibake', () {
      // Cyrillic + Latin extended (čćšđž) is the case Excel-Windows
      // mishandles without BOM.
      final csv = StageAssetCsvExporter.exportToCsv([
        _evt(stage: 'KOLO_ZAVRŠENO_Č', name: 'onSpin', assetId: '/a.wav'),
      ]);
      expect(csv.contains('KOLO_ZAVRŠENO_Č'), isTrue);
    });
  });
}
