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
/// Bumped 2026-05-10 (Sprint 10 E.1) +2 za `_ExportClipButton` u
/// `session_recorder_panel.dart` — 2 inline TextStyle poziva za dinamicki
/// label boja (success green / error red / brand gold idle).
/// Bumped 2026-05-10 (Sprint 11 G grupa) +3 za G.7 hot-reload SnackBar
/// label, G.21 blend preview snackbar (2× — active+empty paths).
/// Bumped 2026-05-10 (Sprint 12 G grupa) +8 za G.16 (3× snackbar +
/// dialog title), G.19 (snackbar + dialog title + hint), G.18 (—).
/// Bumped 2026-05-10 (Sprint 13 Helix Event Nexus) +43 za pure-trigger
/// event matrix UI (`helix_event_nexus.dart`): per-stage row labels,
/// per-layer parameter sliders (volume/pan/dual-pan/width/gain/delay/
/// fadeIn/fadeOut/trim/curves), event-level controls, header badges,
/// category chips, meta chips, dropdown labels, micro toggles. Each
/// inline TextStyle is intentionally fontSize=8–11 (dock-density) sa
/// monospace value displays — FluxForgeTheme typography tokens (h1/h2/
/// body) ne pokrivaju ovu density tier (dock UI density), pa su inline
/// styles privremeno opravdani; kad token paleta dobije .dockLabel /
/// .dockMono varijante migration je trivial.
/// Bumped 2026-05-10 (Sprint 14 Helix Faza 4.A.2) +1 za WIP feature
/// SnackBar (`_showFeatureWipToast`) koji zameni dead `() {}` na 6 stub
/// dock tabova (SFX/BT/DNA/AI/CLOUD/A/B). Inline TextStyle za monospace
/// snack content jer SnackBar-default Theme nije FluxForge-tokenized.
/// Bumped 2026-05-10 (Sprint 14 Helix Faza 4.B.4) +1 za `_ModeIndicator`
/// label u Omnibar-u (monospace 9px, weight 800 — dock-density tier).
const int _kRawTextStyleBaseline = 9253;

/// Frozen baseline za `fontFamily:` referenca van theme/.
/// Bumped 2026-05-10 (Sprint 10 E.1) +1 za `_ExportClipButton` `'monospace'`
/// font (aligned sa _SessionStat sibling badge).
/// Bumped 2026-05-10 (Sprint 13 Helix Event Nexus) +16 za monospace value
/// displays u Event Nexus parameter editor (volume %, pan L/R/C, fadeMs,
/// trimMs, file size KB/MB, duration s, dB readout). Monospace je
/// canonical kod numerical readout-a; FluxForgeTheme.monoFontFamily
/// migration prati .dockMono token kreaciju.
/// Bumped 2026-05-10 (Sprint 14 Helix Faza 4.A.2) +1 za WIP toast u
/// `_showFeatureWipToast` — monospace fontFamily da snack izgleda
/// konzistentno sa drugim status pillovima u dock-u.
/// Bumped 2026-05-10 (Sprint 14 Helix Faza 4.B.4) +1 za `_ModeIndicator`
/// monospace label.
const int _kRawFontFamilyBaseline = 1226;

/// Frozen baseline za `fontSize:` referenca van theme/.
/// Bumped 2026-05-10 (Sprint 10 E.1) +1 za `_ExportClipButton` 9px label
/// (aligned sa _SessionStat sibling badge size).
/// Bumped 2026-05-10 (Sprint 12 G grupa) +1 za G.19 dialog title fontSize.
/// Bumped 2026-05-10 (Sprint 13 Helix Event Nexus) +43 za dock-density
/// parameter editor (sve 7–11px brojeve mapirano na .label/.labelTiny/
/// .mono token, ali dok token paleta ne pokriva 7px tier, inline
/// fontSize ostaje. Sve manje od FluxForgeTheme.body (12px)).
/// Bumped 2026-05-10 (Sprint 14 Helix Faza 4.A.2) +1 za WIP toast 11px
/// label (matches dock-density tier).
/// Bumped 2026-05-10 (Sprint 14 Helix Faza 4.B.4) +1 za `_ModeIndicator`
/// 9px label.
const int _kRawFontSizeBaseline = 8810;

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
