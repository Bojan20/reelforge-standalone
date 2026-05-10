/// FluxMotion ratchet — FLUX_MASTER_TODO 0.5 A.4.
///
/// Pinuje frozen baseline za raw animation patterns van canonical
/// `lib/theme/flux_motion.dart`. Asimetrično pravilo: baseline ide samo
/// nadole. Svaki commit koji raste ovaj broj uvodi novu raw animaciju
/// — autor mora da koristi `FluxMotion.*` token (instant/quick/standard/
/// slow/cinematic + uiSpring/glassSpring/scrubberSpring/elasticSpring/
/// pageSpring) umesto direktnog `Duration(milliseconds:)` + `Curves.*`.
///
/// **Direction contract:** baseline samo PADA. Migracije moraju
/// **lower the baseline u istom commit-u** — napredak je vidljiv u
/// `git log -p`.
///
/// Detection heuristik:
///
///   * `Duration(milliseconds: …)`: literal Duration konstruktor.
///   * `Duration(seconds: …)`: literal Duration konstruktor (drugi unit).
///   * `Curves.<name>`: Material curve referenca.
///   * Komentari (single + doc) preskočeni — prose o Duration nije call site.
///   * `lib/theme/`, `lib/src/rust/` (generated FFI), test fajlovi
///     isključeni (canonical / generated izvori).
///
/// Migration pattern:
///
///   `Duration(milliseconds: 300)`        → `FluxMotion.standard`
///   `Curves.easeOutCubic`                 → `FluxMotion.uiSpring`
///   `Duration(milliseconds: 500), Curves.elasticOut`
///                                         → `FluxMotion.celebration.duration / .curve`
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Frozen baseline za `Duration(milliseconds: …)` literala pod `lib/`
/// izvan `lib/theme/`. Captured 2026-05-10 audit.
/// Bumped 2026-05-10 (Sprint 10 E.1) +1 za `_ExportClipButton` Tooltip
/// `waitDuration: Duration(milliseconds: 350)`.
const int _kRawDurationMsBaseline = 948;

/// Frozen baseline za `Duration(seconds: …)` literala.
/// Bumped 2026-05-10 (Sprint 10 E.1) +1 za `_ExportClipButton` SnackBar
/// `duration: Duration(seconds: 4)`.
/// Bumped 2026-05-10 (Sprint 11 G grupa) +3 za G.7 hot-reload SnackBar
/// (3s) + G.21 blend preview (2s × 2 paths).
const int _kRawDurationSecBaseline = 206;

/// Frozen baseline za `Curves.<name>` referenca.
const int _kRawCurvesBaseline = 148;

/// Excluded path prefixes (canonical / generated).
const Set<String> _kExcludedPathPrefixes = <String>{
  'theme/',
  'src/rust/',
};

final _libRoot = Directory.fromUri(
  Directory.current.uri.resolve('lib'),
);

void main() {
  group('FluxMotion ratchet (FLUX_MASTER_TODO 0.5 A.4)', () {
    late List<File> dartFiles;

    setUpAll(() {
      dartFiles = _libRoot
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !_isExcluded(_relPath(f.path)))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
    });

    test('lib root resolves and is non-empty', () {
      expect(_libRoot.existsSync(), isTrue);
      expect(dartFiles.isNotEmpty, isTrue);
    });

    test('Duration(milliseconds: …) count must not exceed frozen baseline',
        () {
      final result = _scan(dartFiles, _rxDurationMs);
      expect(
        result.total,
        lessThanOrEqualTo(_kRawDurationMsBaseline),
        reason:
            'Raw `Duration(milliseconds: …)` poraslo iznad frozen baseline-a '
            '$_kRawDurationMsBaseline (sad ${result.total}). Novi UI kod mora '
            'da koristi `FluxMotion.*` token (instant=80ms, quick=150ms, '
            'standard=300ms, entrance=360ms, slow=500ms, cinematic=800ms) '
            'umesto direktnog literala.\n'
            '\nTop 15 offenders:\n${_formatTop(result.perFile, 15)}',
      );
    });

    test('Duration(seconds: …) count must not exceed frozen baseline', () {
      final result = _scan(dartFiles, _rxDurationSec);
      expect(
        result.total,
        lessThanOrEqualTo(_kRawDurationSecBaseline),
        reason:
            'Raw `Duration(seconds: …)` poraslo iznad frozen baseline-a '
            '$_kRawDurationSecBaseline (sad ${result.total}). Razmotri da li '
            'je baš sekunda potrebna ili može `FluxMotion.cinematic` (800ms).\n'
            '\nTop 15 offenders:\n${_formatTop(result.perFile, 15)}',
      );
    });

    test('Curves.<name> count must not exceed frozen baseline', () {
      final result = _scan(dartFiles, _rxCurves);
      expect(
        result.total,
        lessThanOrEqualTo(_kRawCurvesBaseline),
        reason:
            'Raw `Curves.<name>` reference poraslo iznad frozen baseline-a '
            '$_kRawCurvesBaseline (sad ${result.total}). Novi UI kod mora '
            'da koristi `FluxMotion.<purpose>Spring` token (uiSpring, '
            'glassSpring, scrubberSpring, elasticSpring, pageSpring) umesto '
            'direktne Material curve reference.\n'
            '\nTop 15 offenders:\n${_formatTop(result.perFile, 15)}',
      );
    });

    test('reduction tip lands in failure messages', () {
      const failureExample =
          'Raw `Duration(milliseconds: …)` poraslo iznad frozen baseline-a '
          '$_kRawDurationMsBaseline (sad 9999). Novi UI kod mora '
          'da koristi `FluxMotion.*` token (instant=80ms, quick=150ms, '
          'standard=300ms, entrance=360ms, slow=500ms, cinematic=800ms)';
      expect(failureExample, contains('FluxMotion'));
      expect(failureExample, contains('quick=150ms'));
    });
  });
}

final _rxDurationMs =
    RegExp(r'\bDuration\s*\(\s*milliseconds\s*:');
final _rxDurationSec =
    RegExp(r'\bDuration\s*\(\s*seconds\s*:');
final _rxCurves = RegExp(r'\bCurves\.\w');

class _ScanResult {
  _ScanResult(this.total, this.perFile);
  final int total;
  final List<MapEntry<String, int>> perFile;
}

_ScanResult _scan(List<File> files, RegExp pattern) {
  final perFile = <MapEntry<String, int>>[];
  var total = 0;
  for (final file in files) {
    final rel = _relPath(file.path);
    final count = _countMatches(file.readAsStringSync(), pattern);
    if (count > 0) perFile.add(MapEntry(rel, count));
    total += count;
  }
  perFile.sort((a, b) => b.value.compareTo(a.value));
  return _ScanResult(total, perFile);
}

int _countMatches(String content, RegExp pattern) {
  var total = 0;
  for (final line in content.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
    total += pattern.allMatches(line).length;
  }
  return total;
}

bool _isExcluded(String relPath) {
  for (final prefix in _kExcludedPathPrefixes) {
    if (relPath.startsWith(prefix)) return true;
  }
  return false;
}

String _formatTop(List<MapEntry<String, int>> entries, int n) {
  return entries.take(n).map((e) => '  ${e.value}× ${e.key}').join('\n');
}

String _relPath(String full) {
  final root = '${_libRoot.path}/';
  return full.startsWith(root) ? full.substring(root.length) : full;
}
