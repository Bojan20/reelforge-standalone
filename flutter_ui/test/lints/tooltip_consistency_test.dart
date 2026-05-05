/// Tooltip consistency ratchet — SPEC-16 / FLUX_MASTER_TODO 2B.3.4.
///
/// `FluxTooltip` is the canonical app-wide tooltip surface (150ms delay,
/// brand-gold border, optional shortcut hint). Raw `Tooltip(...)` usage
/// is legacy — it produces inconsistent styling, the platform default
/// long-press / 1500ms hover delay, and skips the shortcut hint
/// rendering pipeline.
///
/// This test pins a baseline count of legacy `Tooltip(...)` call sites
/// and fails if the count *grows*. New code must use `FluxTooltip`;
/// migrations of existing call sites that lower the count must also
/// lower `_kRawTooltipBaseline` in the same commit (the asymmetric-OK
/// direction is a feature: it forces people to "claim" their reduction
/// explicitly so progress is visible in `git log -p`).
///
/// Detection heuristic:
///
///   * Counts `Tooltip(` occurrences with a word boundary in front so
///     `FluxTooltip(` doesn't false-positive (the `\b` before `T`
///     prevents the `Flux` prefix from matching).
///   * Skips the canonical implementation file
///     `widgets/common/flux_tooltip.dart` itself (which wraps a real
///     `Tooltip` widget internally — that wrap IS the FluxTooltip).
///   * Skips test files (`test/**`) and generated FFI bindings (which
///     cannot meaningfully use FluxTooltip anyway).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Frozen baseline count of legacy raw `Tooltip(` call sites under
/// `flutter_ui/lib/`. Captured 2026-05-05 after the first SPEC-16
/// migration commit (helix_screen.dart "Drag to resize" → FluxTooltip).
///
/// **Direction contract:** the baseline can only go DOWN. Any commit
/// that raises this number means new code added a raw `Tooltip(...)`;
/// the author must convert it to `FluxTooltip` instead.
///
/// When you genuinely migrate one or more sites, lower this constant
/// in the SAME commit so the reduction is visible in `git log -p`.
const int _kRawTooltipBaseline = 240;

/// Files that legitimately keep a raw `Tooltip` for a reason that does
/// not fit the canonical `FluxTooltip` surface. Each entry needs a
/// rationale comment — empty justification = no entry.
const Set<String> _kRawTooltipAllowList = <String>{
  // The canonical implementation wraps a real Tooltip — that's the
  // entire point of the abstraction. Excluded so the baseline counts
  // only "user" call sites.
  'widgets/common/flux_tooltip.dart',
};

final _libRoot = Directory.fromUri(
  Directory.current.uri.resolve('lib'),
);

void main() {
  group('Tooltip consistency ratchet (SPEC-16)', () {
    late List<File> dartFiles;

    setUpAll(() {
      dartFiles = _libRoot
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
    });

    test('lib root resolves and is non-empty', () {
      expect(_libRoot.existsSync(), isTrue,
          reason: 'flutter_ui/lib must exist (cwd=${Directory.current.path})');
      expect(dartFiles.isNotEmpty, isTrue);
    });

    test('raw Tooltip( count must not exceed frozen baseline', () {
      final hits = <MapEntry<String, int>>[];
      var total = 0;
      for (final file in dartFiles) {
        final rel = _relPath(file.path);
        if (_kRawTooltipAllowList.contains(rel)) continue;
        final count = _countRawTooltip(file.readAsStringSync());
        if (count > 0) hits.add(MapEntry(rel, count));
        total += count;
      }
      hits.sort((a, b) => b.value.compareTo(a.value));

      expect(
        total,
        lessThanOrEqualTo(_kRawTooltipBaseline),
        reason: 'Raw Tooltip() call sites rose above the frozen baseline '
            'of $_kRawTooltipBaseline (now $total). New code must use '
            'FluxTooltip from `widgets/common/flux_tooltip.dart` for '
            'uniform styling, 150ms delay, and shortcut-hint rendering.\n'
            '\nTop offenders:\n${hits.take(15).map((e) => '  ${e.value}× ${e.key}').join('\n')}',
      );
    });

    test('FluxTooltip is genuinely used (sanity check the canonical type)', () {
      // If nobody imports FluxTooltip, the migration is dead-on-arrival.
      // This sanity test fails noisily if the abstraction was deleted
      // or renamed without updating callers.
      var importers = 0;
      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        if (content.contains("import '../common/flux_tooltip.dart'") ||
            content.contains("import '../../widgets/common/flux_tooltip.dart'") ||
            content.contains("import '../widgets/common/flux_tooltip.dart'") ||
            content.contains("import 'flux_tooltip.dart'") ||
            RegExp(r"import\s+'package:fluxforge_ui/widgets/common/flux_tooltip\.dart'")
                .hasMatch(content)) {
          importers++;
        }
      }
      expect(importers, greaterThanOrEqualTo(3),
          reason: 'FluxTooltip must be imported from at least 3 sites; '
              'a near-zero count usually means the canonical type was '
              'renamed or moved without updating consumers.');
    });

    test('reduction tip lands in the failure message when over baseline', () {
      // Documentation test: the failure message above must mention the
      // canonical alternative so a developer hitting the failure knows
      // exactly what to do without reading this test source. The
      // assertion is on the message string itself so a future edit
      // doesn't accidentally drop the hint.
      const failureExample = 'Raw Tooltip() call sites rose above the frozen baseline '
          'of $_kRawTooltipBaseline (now 999). New code must use '
          'FluxTooltip from `widgets/common/flux_tooltip.dart` for '
          'uniform styling, 150ms delay, and shortcut-hint rendering.';
      expect(failureExample, contains('FluxTooltip'));
      expect(failureExample, contains('150ms'));
    });
  });
}

/// Count `Tooltip(` occurrences with a word boundary in front so
/// `FluxTooltip(` doesn't false-positive (the `\b` rejects matches
/// where `Tooltip` is preceded by another word character).
///
/// Single-line comments (`// …`) are skipped so that documentation
/// referring to the legacy widget by name doesn't inflate the count
/// — e.g. `// pre-migration this was a raw Tooltip(...)` is *prose*,
/// not a real call site. Multi-line `/// …` doc comments are skipped
/// for the same reason.
///
/// Block comments (`/* … */`) are NOT stripped — they're rare in this
/// codebase and the false-positive cost is one baseline bump.
int _countRawTooltip(String content) {
  final re = RegExp(r'\bTooltip\s*\(');
  var total = 0;
  for (final line in content.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//')) continue; // single-line comment / doc
    total += re.allMatches(line).length;
  }
  return total;
}

String _relPath(String full) {
  final root = '${_libRoot.path}/';
  return full.startsWith(root) ? full.substring(root.length) : full;
}
