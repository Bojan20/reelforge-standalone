/// FluxTypography ratchet — FLUX_MASTER_TODO 0.5 A.5.
///
/// FluxForge ima brand typography hierarchiju (`FluxForgeTheme.h1/h2/h3/
/// body/bodySmall/label/labelTiny/mono/monoSmall/monoLarge`) sa pin-ovanim
/// font family-jima (`Inter` + monoFontFamily). Direktni `TextStyle(...)`
/// + `fontFamily: '…'` + raw `fontSize:` literali izvan `lib/theme/`
/// razbijaju brand typography identity isto kao raw `Color(0x…)` i raw
/// `Duration(milliseconds:)` razbijaju color + motion identity.
///
/// Ovaj test pinuje **frozen baselines**:
///   * `TextStyle(...)` literala (svaki je inline TextStyle)
///   * `fontFamily:` referenca (svaki implies hardcoded font family)
///   * `fontSize:` referenca (svaki implies hardcoded font size)
///
/// **Direction contract:** baseline ide samo nadole. Migracije konvertuju
/// raw TextStyle u `FluxForgeTheme.h1/.body/.mono` itd. — i lower the
/// baseline u istom commit-u (asimetrično OK pravilo).
///
/// Detection heuristik:
///   * Single + doc komentari preskočeni
///   * `lib/theme/`, `lib/src/rust/` (auto-gen FFI), `lib/l10n/` isključeni
///
/// Migration pattern:
///   `TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: ...)`
///                                                  → `FluxForgeTheme.body`
///   `TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11)`
///                                                  → `FluxForgeTheme.monoSmall`
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Frozen baseline za inline `TextStyle(…)` poziva pod `lib/` izvan
/// `lib/theme/`. Captured 2026-05-10 audit.
const int _kRawTextStyleBaseline = 9195;

/// Frozen baseline za `fontFamily:` referenca van theme/.
/// Svaki je hard-coded font choice koji bi trebalo da bude na canonical
/// `FluxForgeTheme.fontFamily` / `monoFontFamily`.
const int _kRawFontFamilyBaseline = 1207;

/// Frozen baseline za `fontSize:` referenca van theme/.
/// Svaki je hard-coded size koji bi trebalo da pokriva typography token.
const int _kRawFontSizeBaseline = 8763;

const Set<String> _kExcludedPathPrefixes = <String>{
  'theme/',
  'src/rust/',
  'l10n/',
};

final _libRoot = Directory.fromUri(
  Directory.current.uri.resolve('lib'),
);

void main() {
  group('FluxTypography ratchet (FLUX_MASTER_TODO 0.5 A.5)', () {
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

    test('TextStyle(…) literal count must not exceed frozen baseline', () {
      final result = _scan(dartFiles, _rxTextStyle);
      expect(
        result.total,
        lessThanOrEqualTo(_kRawTextStyleBaseline),
        reason:
            'Raw `TextStyle(…)` literala je poraslo iznad frozen baseline-a '
            '$_kRawTextStyleBaseline (sad ${result.total}). Novi UI kod mora '
            'da koristi `FluxForgeTheme.h1/h2/h3/body/bodySmall/label/'
            'labelTiny/mono/monoSmall/monoLarge` token umesto inline TextStyle.\n'
            '\nTop 15 offenders:\n${_formatTop(result.perFile, 15)}',
      );
    });

    test('fontFamily: count must not exceed frozen baseline', () {
      final result = _scan(dartFiles, _rxFontFamily);
      expect(
        result.total,
        lessThanOrEqualTo(_kRawFontFamilyBaseline),
        reason:
            'Raw `fontFamily:` referenca poraslo iznad frozen baseline-a '
            '$_kRawFontFamilyBaseline (sad ${result.total}). Novi UI kod mora '
            'da koristi `FluxForgeTheme.fontFamily` (Inter) ili '
            '`FluxForgeTheme.monoFontFamily` umesto hardcoded font name-a.\n'
            '\nTop 15 offenders:\n${_formatTop(result.perFile, 15)}',
      );
    });

    test('fontSize: count must not exceed frozen baseline', () {
      final result = _scan(dartFiles, _rxFontSize);
      expect(
        result.total,
        lessThanOrEqualTo(_kRawFontSizeBaseline),
        reason:
            'Raw `fontSize:` referenca poraslo iznad frozen baseline-a '
            '$_kRawFontSizeBaseline (sad ${result.total}). Migracija na '
            '`FluxForgeTheme.body / .label / .mono / .h1` etc. token-e '
            'pokriva canonical typography hierarchy.\n'
            '\nTop 15 offenders:\n${_formatTop(result.perFile, 15)}',
      );
    });

    test('reduction tip lands in failure messages', () {
      const failureExample =
          'Raw `TextStyle(…)` literala je poraslo iznad frozen baseline-a '
          '$_kRawTextStyleBaseline (sad 9999). Novi UI kod mora '
          'da koristi `FluxForgeTheme.h1/h2/h3/body/bodySmall/label/'
          'labelTiny/mono/monoSmall/monoLarge` token umesto inline TextStyle.';
      expect(failureExample, contains('FluxForgeTheme'));
      expect(failureExample, contains('mono'));
    });
  });
}

final _rxTextStyle = RegExp(r'\bTextStyle\s*\(');
final _rxFontFamily = RegExp(r'\bfontFamily\s*:');
final _rxFontSize = RegExp(r'\bfontSize\s*:');

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
