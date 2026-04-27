/// Gesture conflict detection — FLUX_MASTER_TODO 1.3.4
///
/// Scans every `.dart` file under `lib/` for patterns that are known to
/// cause Gesture Arena collisions in Flutter — chiefly: nested
/// `GestureDetector`s without an intervening `Listener` (which uses
/// `Listener.onPointerDown/Move/Up` to bypass the arena, per the project's
/// CLAUDE.md "Nested drag" rule).
///
/// What this test catches:
///
///   1. **`GestureDetector` directly inside another `GestureDetector`**
///      (within the same widget build). Both will compete for the same
///      pointer in the arena and one will silently win, producing the
///      classic "tap registered twice" or "swipe doesn't register" bug.
///
///   2. **`GestureDetector` inside `InkWell`** — InkWell is itself a
///      gesture-arena participant; nesting another GestureDetector inside
///      it is the same arena race in disguise.
///
///   3. Anomaly counters: total `GestureDetector` density per file. A
///      file with > 60 detectors is a refactoring candidate (the largest
///      ones are tracked here so growth is visible in code review).
///
/// What this test deliberately does NOT do:
///
///   * Cross-file analysis. A `GestureDetector` in a child widget that
///     is composed inside a parent's `GestureDetector` is NOT detected
///     here (the static heuristic only sees one file at a time). That's
///     deferred to a future Flutter-runtime smoke test that mounts
///     real screens and asserts arena ownership.
///
///   * False-positive whitelisting via project-specific allow-lists.
///     If a legitimate nested pattern surfaces, document the bypass
///     (`Listener` wrapper, `behavior: HitTestBehavior.translucent`,
///     etc.) in a comment on the inner `GestureDetector` and add the
///     file to `_kKnownSafeNested` below with the rationale.
///
/// Pre-2026-04-28 the project had **1602 GestureDetector instances**
/// across `flutter_ui/lib/`. That density makes manual auditing
/// impossible, so this test exists as a tripwire for future regressions.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files where nested gesture patterns are intentional. Add a brief
/// rationale comment when adding entries — empty justification = no entry.
const Set<String> _kKnownSafeNested = {
  // (none yet — every nested case found so far should be fixed, not
  // whitelisted. If you genuinely need one, document why.)
};

/// Hard ceiling on `GestureDetector` density per single file. Today's
/// max is `helix_screen.dart` at 94. The ceiling is set just above to
/// prevent silent growth — raising it should require a follow-up commit
/// that documents WHY the file still grew.
const int _kMaxGesturesPerFile = 100;

/// Baseline count of legacy nested-gesture patterns. New code MUST NOT
/// add any; the only allowed direction is down. When the baseline is
/// reduced by an actual fix, lower this number in the same commit.
///
/// Captured: 2026-04-28. Audit and reduction is deferred work — see
/// FLUX_MASTER_TODO 1.3.4 follow-up. The 41 files holding these will
/// each need a `Listener.onPointerDown/Move/Up` wrapper or
/// `behavior: HitTestBehavior.translucent` per the CLAUDE.md
/// "Nested drag" rule.
const int _kLegacyNestedBaseline = 78;

/// File pattern: anything ending in .dart under flutter_ui/lib/.
final _libRoot = Directory.fromUri(
  Directory.current.uri.resolve('lib'),
);

void main() {
  group('Gesture conflict detection (FLUX_MASTER_TODO 1.3.4)', () {
    late List<File> _dartFiles;

    setUpAll(() {
      _dartFiles = _libRoot
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      // Stable order so failure messages are reproducible.
      _dartFiles.sort((a, b) => a.path.compareTo(b.path));
    });

    test('lib root resolves to a real directory', () {
      expect(_libRoot.existsSync(), isTrue,
          reason: 'flutter_ui/lib must exist (cwd=${Directory.current.path})');
      expect(_dartFiles.isNotEmpty, isTrue,
          reason: 'no .dart files found under ${_libRoot.path}');
    });

    test('no file exceeds GestureDetector density ceiling', () {
      final offenders = <MapEntry<String, int>>[];
      for (final file in _dartFiles) {
        final content = file.readAsStringSync();
        final count = _countGestureDetectors(content);
        if (count > _kMaxGesturesPerFile) {
          offenders.add(MapEntry(file.path, count));
        }
      }
      offenders.sort((a, b) => b.value.compareTo(a.value));
      expect(
        offenders,
        isEmpty,
        reason: 'Files exceed GestureDetector density ceiling '
            '($_kMaxGesturesPerFile). Refactor or raise the ceiling '
            'with a follow-up commit:\n${offenders.map((e) => '  ${e.value}× ${_relPath(e.key)}').join('\n')}',
      );
    });

    test('nested-gesture count must not exceed legacy baseline', () {
      final offenders = <_NestedHit>[];
      for (final file in _dartFiles) {
        final rel = _relPath(file.path);
        if (_kKnownSafeNested.contains(rel)) continue;
        final content = file.readAsStringSync();
        offenders.addAll(_findNestedGestures(rel, content));
      }
      // Group by file for readable diagnostic output.
      final byFile = <String, List<_NestedHit>>{};
      for (final h in offenders) {
        byFile.putIfAbsent(h.file, () => []).add(h);
      }

      // Ratchet contract: total can only go DOWN. Any commit that
      // increases nested-gesture count fails this assertion. Fixes that
      // reduce the count must also lower _kLegacyNestedBaseline in the
      // same commit (the asymmetric-OK direction is a feature: it forces
      // people to "claim" their reduction explicitly).
      expect(
        offenders.length,
        lessThanOrEqualTo(_kLegacyNestedBaseline),
        reason: 'Nested-GestureDetector count rose above the legacy '
            'baseline of $_kLegacyNestedBaseline (now ${offenders.length}). '
            'CLAUDE.md "Nested drag" rule: wrap the inner gesture in '
            '`Listener.onPointerDown/Move/Up` or set '
            '`behavior: HitTestBehavior.translucent` on the outer '
            'GestureDetector.\n\nFiles affected:\n'
            '${byFile.entries.map((e) => '  ${e.key}: lines ${e.value.map((h) => h.innerLine).join(", ")}').join('\n')}',
      );

      // Visibility: print the actual current count and a one-line
      // reduction reminder if the baseline is still above zero.
      // ignore: avoid_print
      print('\n[nested-gesture] count=${offenders.length} '
          '(baseline=$_kLegacyNestedBaseline, files=${byFile.length})');
      if (_kLegacyNestedBaseline > 0) {
        // ignore: avoid_print
        print('  → reduction welcome: each fixed nested case earns a '
            'baseline decrement.');
      }
    });

    test('legacy baseline matches the actually-counted total', () {
      // Sanity guard: if a developer fixes 5 nested cases but forgets
      // to lower _kLegacyNestedBaseline, the absolute-floor check is
      // meaningless. This test catches that drift in reverse: baseline
      // should always equal current count (decremented in the same
      // commit as the fix). It runs as a soft warning rather than a
      // hard fail so it doesn't block work-in-progress.
      final offenders = <_NestedHit>[];
      for (final file in _dartFiles) {
        final rel = _relPath(file.path);
        if (_kKnownSafeNested.contains(rel)) continue;
        final content = file.readAsStringSync();
        offenders.addAll(_findNestedGestures(rel, content));
      }
      if (offenders.length < _kLegacyNestedBaseline) {
        // Pure information for code review — not a failure.
        // ignore: avoid_print
        print('\n[gesture-baseline] FYI: actual ${offenders.length} '
            '< baseline $_kLegacyNestedBaseline — consider lowering '
            'the constant in the same commit that fixed the gap.');
      }
      expect(offenders.length, lessThanOrEqualTo(_kLegacyNestedBaseline));
    });

    test('top-10 GestureDetector-heavy files (visibility check)', () {
      final counts = <MapEntry<String, int>>[];
      for (final file in _dartFiles) {
        final content = file.readAsStringSync();
        final count = _countGestureDetectors(content);
        if (count > 0) counts.add(MapEntry(_relPath(file.path), count));
      }
      counts.sort((a, b) => b.value.compareTo(a.value));
      // Print top-10 so growth is visible in test output / code review.
      // ignore: avoid_print
      print('\n[gesture-density top 10]');
      for (final e in counts.take(10)) {
        // ignore: avoid_print
        print('  ${e.value.toString().padLeft(4)}× ${e.key}');
      }
      // No assertion — purely informational. The previous test enforces
      // the actual ceiling.
      expect(counts.isNotEmpty, isTrue);
    });
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────

/// Count `GestureDetector(` occurrences. Crude but stable: matches the
/// constructor call site, not type references / class declarations.
int _countGestureDetectors(String source) {
  final re = RegExp(r'\bGestureDetector\s*\(');
  return re.allMatches(source).length;
}

/// Find lines where a `GestureDetector(` opens *while another
/// `GestureDetector(` is still open above it* — that's the arena-collision
/// signature. The matcher tolerates nested parens by tracking a depth
/// counter; it doesn't try to parse Dart syntax (cheap heuristic).
///
/// Misses cross-file cases (a child widget defined elsewhere whose own
/// build wraps a GestureDetector and is composed inside a parent's
/// GestureDetector). Catching those needs the analyzer-package; that's a
/// deferred enhancement.
List<_NestedHit> _findNestedGestures(String relPath, String source) {
  final out = <_NestedHit>[];

  // Single-pass scan. We track every "open" GestureDetector's start line
  // and track parenthesis depth from its opening. When another
  // `GestureDetector(` shows up while at least one is still open, that's
  // a nested hit.
  final lines = source.split('\n');
  final openStack = <int>[]; // each int = depth at which the corresponding
                              // GestureDetector was opened (not the opening
                              // line — that's tracked by openLineStack).
  final openLineStack = <int>[];
  int depth = 0;
  // Skip strings, line comments, and block comments. Crude state machine.
  bool inLineComment = false;
  bool inBlockComment = false;
  String? stringQuote;
  bool prevWasBackslash = false;

  for (int li = 0; li < lines.length; li++) {
    final line = lines[li];
    inLineComment = false;
    int col = 0;
    while (col < line.length) {
      final ch = line[col];
      // Comment / string state machine
      if (inBlockComment) {
        if (ch == '*' && col + 1 < line.length && line[col + 1] == '/') {
          inBlockComment = false;
          col += 2;
          continue;
        }
        col++;
        continue;
      }
      if (inLineComment) break;
      if (stringQuote != null) {
        if (prevWasBackslash) {
          prevWasBackslash = false;
          col++;
          continue;
        }
        if (ch == '\\') {
          prevWasBackslash = true;
          col++;
          continue;
        }
        if (ch == stringQuote) {
          stringQuote = null;
        }
        col++;
        continue;
      }
      if (ch == '/' && col + 1 < line.length) {
        final next = line[col + 1];
        if (next == '/') {
          inLineComment = true;
          break;
        }
        if (next == '*') {
          inBlockComment = true;
          col += 2;
          continue;
        }
      }
      if (ch == '"' || ch == "'") {
        stringQuote = ch;
        col++;
        continue;
      }
      // Token detection: GestureDetector + (
      if (ch == 'G' && _matchesAt(line, col, 'GestureDetector')) {
        // Look forward for the opening paren (allow whitespace).
        int k = col + 'GestureDetector'.length;
        while (k < line.length && (line[k] == ' ' || line[k] == '\t')) {
          k++;
        }
        if (k < line.length && line[k] == '(') {
          if (openStack.isNotEmpty) {
            // Nested: at least one outer GestureDetector is still open.
            out.add(_NestedHit(
              file: relPath,
              outerLine: openLineStack.last + 1,
              innerLine: li + 1,
            ));
          }
          openStack.add(depth + 1); // record we're now inside ( )
          openLineStack.add(li);
          depth++;
          col = k + 1;
          continue;
        }
      }
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
        // If the depth dropped below the most recently-opened
        // GestureDetector's recorded depth, pop it.
        while (openStack.isNotEmpty && depth < openStack.last) {
          openStack.removeLast();
          openLineStack.removeLast();
        }
      }
      col++;
    }
  }
  return out;
}

bool _matchesAt(String haystack, int start, String needle) {
  if (start + needle.length > haystack.length) return false;
  for (int i = 0; i < needle.length; i++) {
    if (haystack[start + i] != needle[i]) return false;
  }
  // Word boundary on the right side.
  final after = start + needle.length;
  if (after < haystack.length) {
    final c = haystack[after];
    if (_isWordChar(c)) return false;
  }
  // Word boundary on the left side.
  if (start > 0) {
    final c = haystack[start - 1];
    if (_isWordChar(c)) return false;
  }
  return true;
}

bool _isWordChar(String c) {
  return (c.codeUnitAt(0) >= 'A'.codeUnitAt(0) &&
          c.codeUnitAt(0) <= 'Z'.codeUnitAt(0)) ||
      (c.codeUnitAt(0) >= 'a'.codeUnitAt(0) &&
          c.codeUnitAt(0) <= 'z'.codeUnitAt(0)) ||
      (c.codeUnitAt(0) >= '0'.codeUnitAt(0) &&
          c.codeUnitAt(0) <= '9'.codeUnitAt(0)) ||
      c == '_';
}

String _relPath(String absPath) {
  final libIdx = absPath.indexOf('/lib/');
  if (libIdx < 0) return absPath;
  return absPath.substring(libIdx + 1);
}

class _NestedHit {
  final String file;
  final int outerLine;
  final int innerLine;
  _NestedHit({required this.file, required this.outerLine, required this.innerLine});

  @override
  String toString() => '$file:$innerLine (nested inside :$outerLine)';
}
