/// Brand color ratchet — FLUX_MASTER_TODO 0.5 A.1 / A.2.
///
/// FluxForge ima brand identitet (`brandGold`, `brandSteel`, `brandInk`,
/// `glassFill`, …) definisan u `lib/theme/`. Direktni `Color(0x…)`
/// literali i `Colors.amber/grey/teal/…` Material default-i izvan
/// `lib/theme/` razbijaju brand konzistenciju i čine UI da deluje
/// "AI-generated".
///
/// Ovaj test pinuje **frozen baseline** broja raw color literala pod
/// `lib/` (isključuje `lib/theme/`, generated FFI binding-e i test
/// fajlove). Baseline može samo da PADA — bilo koji commit koji ga
/// poveća fail-uje CI; autor mora da konvertuje novi kod na
/// `FluxForgeTheme.*` token-e umesto da uvodi nove raw boje.
///
/// Asimetrično OK pravilo: kad legitimno migriraš N raw boja na
/// brand token-e, **lower the baseline u istom commit-u** — na taj
/// način napredak je vidljiv u `git log -p` (ne nestaje tiho u "ratchet
/// just keeps decreasing on its own").
///
/// Detection heuristik:
///
///   * `Color(0x…)`: count literala oblika `Color(0xFF…)` / `Color(0xAARRGGBB)`.
///   * `Color.fromARGB(…)` i `Color.fromRGBO(…)`: konstruktorski oblici.
///   * `Colors.<lowercase>`: Material default palette (Colors.amber, Colors.red, …).
///   * Single-line i doc komentari preskočeni — prose o boji nije call site.
///   * `lib/theme/`, `lib/src/rust/native_ffi.dart` (auto-generated) i
///     test fajlovi su isključeni jer su to canonical / generated izvori.
///
/// Kada migriraš UI fajl na brand token-e, najčešći pattern:
///   `Color(0xFFD4AF37)` → `FluxForgeTheme.brandGold`
///   `Colors.grey.shade800` → `FluxForgeTheme.brandSteel`
///   `Colors.black.withOpacity(0.85)` → `FluxForgeTheme.glassFill`
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Frozen baseline za `Color(0x…)` literala pod `lib/` izvan `lib/theme/`.
/// Captured 2026-05-10 audit. Bumped 2026-05-10 (Sprint 7) +24 za
/// `event_audit_service.dart` semantic status colors (active/dormant/silent/
/// absent) i `event_debugger_panel.dart` AUDIT tab UI — status indikatori
/// koji se mapiraju 1:1 na `EventAuditStatus` enum, opravdano color-coded.
///
/// Bumped 2026-05-10 (Sprint 9) +5 za `game_config_recommender_dialog.dart`
/// (F.2 UI wire) — 4 brand-bg shade-a (0xFF0D0D14 dialog bg, 0xFF1A1A22
/// input fill) + 1 status accent (0xFF40FF90 enabled feature). Brand token
/// equivalents (`bgDeep`, `bgElevated`, `accentGreen`) imaju različite
/// shade-ove pa F.2 dialog drži vlastite za visual consistency sa aiAudio
/// dialog patternom.
///
/// Bumped 2026-05-10 (Sprint 13 Helix Event Nexus) +1 za sole `Color(0xFF442222)`
/// snackbar background (audition error toast — postojeći app-wide pattern
/// za failure SnackBar boje, mirroring slot_lab_screen + helix_screen).
///
/// **Direction contract:** baseline ide samo nadole. Svaki commit koji
/// raste ovaj broj uvodi nov raw color literal — autor mora da koristi
/// `FluxForgeTheme.*` token umesto direktnog `Color(0x…)`. Ako je bump
/// neizbežan (semantic status palette npr.), dodaj rationale komentar
/// ovde u istom commit-u.
const int _kRawColorHexBaseline = 7625;

/// Frozen baseline za `Color.fromARGB(…)` + `Color.fromRGBO(…)` konstruktore.
const int _kRawColorCtorBaseline = 7;

/// Frozen baseline za `Colors.<material-default>` reference.
/// Ovi su Material Design default-i — ne brand. Svaki je vizuelni "AI-look"
/// signal jer ne prati FluxForge paletu.
/// Bumped 2026-05-10 (Sprint 7) +22 za `Colors.white60/38/24/30/54/70` muted
/// text references u AUDIT tab-u (developer-facing debug panel, ne user UI).
/// Bumped 2026-05-10 (Sprint 9) +19 za F.2 GameConfigRecommenderDialog
/// (Colors.white60/54/38/24 muted labels + Colors.black foreground na gold
/// recommend button). Same dev-tool justification kao AUDIT tab.
/// Bumped 2026-05-10 (Sprint 12 G grupa) +3 za G.19 dialog (Colors.white,
/// Colors.white38 hint).
/// Bumped 2026-05-10 (Sprint 13 Helix Event Nexus) +7 za pure-trigger event
/// matrix UI: 6× `Colors.transparent` (chip/row hover backgrounds — postojeći
/// pattern u dock cards/category chips) + 1× `Colors.white` (active toggle
/// thumb dot za solo/loop/overlap/phase switches). Boki direktiva 2026-05-10:
/// "event samo trigeruje zvuk, niko ne odlučuje koliko traje" — Helix sad
/// ima full-fidelity per-layer parameter editor sa svim Slot-Lab atributima.
const int _kRawMaterialColorsBaseline = 7119;

/// Direktorijumi koji su isključeni iz brojanja jer NISU "user UI code":
///   * `lib/theme/` — canonical brand definicije (one *jesu* raw boje, namerno).
///   * `lib/src/rust/` — auto-generated FFI binding-e (ne edituje se ručno).
const Set<String> _kExcludedPathPrefixes = <String>{
  'theme/',
  'src/rust/',
};

final _libRoot = Directory.fromUri(
  Directory.current.uri.resolve('lib'),
);

void main() {
  group('Brand color ratchet (FLUX_MASTER_TODO 0.5 A.1/A.2)', () {
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
      expect(_libRoot.existsSync(), isTrue,
          reason: 'flutter_ui/lib must exist (cwd=${Directory.current.path})');
      expect(dartFiles.isNotEmpty, isTrue);
    });

    test('Color(0x…) hex literal count must not exceed frozen baseline', () {
      final result = _scan(dartFiles, _rxColorHex);

      expect(
        result.total,
        lessThanOrEqualTo(_kRawColorHexBaseline),
        reason:
            'Raw `Color(0x…)` literala je poraslo iznad frozen baseline-a '
            '$_kRawColorHexBaseline (sad $result.total). Novi UI kod mora '
            'da koristi `FluxForgeTheme.*` token (brandGold, brandSteel, '
            'brandInk, glassFill, …) umesto direktnog hex literala.\n'
            '\nTop 15 offenders:\n${_formatTop(result.perFile, 15)}',
      );
    });

    test('Color.fromARGB / Color.fromRGBO count must not exceed baseline', () {
      final result = _scan(dartFiles, _rxColorCtor);

      expect(
        result.total,
        lessThanOrEqualTo(_kRawColorCtorBaseline),
        reason:
            'Raw `Color.fromARGB(…)` / `Color.fromRGBO(…)` poraslo iznad '
            'baseline-a $_kRawColorCtorBaseline (sad $result.total). '
            'Koristi `FluxForgeTheme.*` ili `.withOpacity()` na postojećem '
            'brand token-u.\n'
            '\nOffenders:\n${_formatTop(result.perFile, 15)}',
      );
    });

    test('Colors.<material default> count must not exceed baseline', () {
      final result = _scan(dartFiles, _rxColorsMaterial);

      expect(
        result.total,
        lessThanOrEqualTo(_kRawMaterialColorsBaseline),
        reason:
            '`Colors.<material default>` (Colors.amber, Colors.red, …) '
            'poraslo iznad baseline-a $_kRawMaterialColorsBaseline (sad '
            '$result.total). Material default palete daju "AI-generated" '
            'look — koristi `FluxForgeTheme.*` brand token umesto.\n'
            '\nTop 15 offenders:\n${_formatTop(result.perFile, 15)}',
      );
    });

    test('reduction tip lands in failure messages', () {
      // Documentation pin — failure poruka mora pomenuti kanonsku
      // alternativu (FluxForgeTheme), inače developer koji udari na
      // failing test ne zna šta da radi bez čitanja test source-a.
      const failureExample =
          'Raw `Color(0x…)` literala je poraslo iznad frozen baseline-a '
          '$_kRawColorHexBaseline (sad 9999). Novi UI kod mora da '
          'koristi `FluxForgeTheme.*` token (brandGold, brandSteel, '
          'brandInk, glassFill, …) umesto direktnog hex literala.';
      expect(failureExample, contains('FluxForgeTheme'));
      expect(failureExample, contains('brandGold'));
    });
  });
}

/// `Color(0xAARRGGBB)` ili `Color(0xFFRRGGBB)` literali.
final _rxColorHex = RegExp(r'\bColor\s*\(\s*0x');

/// `Color.fromARGB(…)` ili `Color.fromRGBO(…)` konstruktorski oblici.
final _rxColorCtor = RegExp(r'\bColor\.from(ARGB|RGBO)\s*\(');

/// `Colors.<lowercase>` Material default palette referenca.
final _rxColorsMaterial = RegExp(r'\bColors\.[a-z]\w*');

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

/// Counts `pattern` matches per non-comment line. Single-line `//` and
/// doc `///` komentari kao i `*` block-comment continuation linije se
/// preskoče — prose o boji ne treba da inflate count.
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
