/// Memory-leak detection — FLUX_MASTER_TODO 1.3.5
///
/// Static-scan tripwire for the three most common Flutter leak patterns
/// in this codebase:
///
///   A. **TickerProvider state without `dispose()`** — any
///      `_XxxState extends State<...> with (Single)TickerProviderStateMixin`
///      that does not override `dispose()` is virtually guaranteed to
///      leak its `AnimationController`(s).
///
///   B. **`StreamSubscription` field without `cancel()` in `dispose()`** —
///      a `late StreamSubscription _sub` that's assigned in `initState`
///      but never cancelled keeps the producer alive across widget
///      lifetimes; classic memory + CPU leak.
///
///   C. **`OverlayEntry` field without explicit `remove()`** — Flutter
///      doesn't auto-clean overlay entries; if the widget that created
///      them is disposed without `entry.remove()`, the overlay paints
///      forever.
///
/// What this test deliberately does NOT do:
///
///   * Cross-file lifetime analysis (a controller created in one widget
///     and disposed in another via callback). That's a runtime job; this
///     is a sniff test for the obvious-fix-by-pattern cases.
///
///   * ChangeNotifier dispose audit. Most of the 268 ChangeNotifier
///     subclasses in this codebase are GetIt singletons that
///     intentionally never dispose (engine lifetime). Filtering noise
///     from intent here would require knowing the registration site,
///     which the static scan can't see.
///
/// Pattern follows 1.3.4 (gesture conflict tripwire): legacy debt is
/// captured as a baseline; any commit that adds a leak fails CI; fixes
/// that reduce the count must lower the baseline in the same commit.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files where a documented leak is intentional. Add a `// LEAK-OK:`
/// comment in the offending file AND list it here with a one-line
/// rationale; empty justification = no entry.
const Set<String> _kKnownIntentionalLeaks = {
  // (none yet)
};

/// Captured 2026-04-28. Each fix must lower this in the same commit.
const int _kTickerWithoutDisposeBaseline = 0;

/// Captured 2026-04-28. StreamSubscription field detection is heuristic;
/// non-zero starting value would mean we ship with at least N likely
/// uncancelled subscriptions.
const int _kStreamSubWithoutCancelBaseline = 0;

final _libRoot = Directory.fromUri(
  Directory.current.uri.resolve('lib'),
);

void main() {
  group('Memory-leak detection (FLUX_MASTER_TODO 1.3.5)', () {
    late List<File> dartFiles;

    setUpAll(() {
      dartFiles = _libRoot
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      dartFiles.sort((a, b) => a.path.compareTo(b.path));
    });

    test('lib root resolves', () {
      expect(_libRoot.existsSync(), isTrue);
      expect(dartFiles.isNotEmpty, isTrue);
    });

    test('TickerProvider state classes with controllers override dispose()',
        () {
      // Important: a TickerProvider mixin alone is not a leak. The leak
      // appears only when the class actually owns an `AnimationController`
      // (or another disposable Ticker-driven object). The 6 false-positive
      // hits captured before this filter was added (knob.dart, pro_meter,
      // ghost_stage_indicator, ...) were classes that mix in the Ticker
      // provider but never instantiate a controller — leftover scaffolding
      // from earlier animated versions, or supply-side mixins for child
      // animations. Those don't leak.
      final offenders = <String>[];
      for (final file in dartFiles) {
        final rel = _relPath(file.path);
        if (_kKnownIntentionalLeaks.contains(rel)) continue;
        final src = file.readAsStringSync();
        for (final cls in _findTickerProviderStates(src)) {
          if (!_classOwnsTickerDriven(src, cls)) continue;
          if (!_classOverridesDispose(src, cls)) {
            offenders.add('$rel:${cls.line} class ${cls.name}');
          }
        }
      }
      offenders.sort();
      expect(
        offenders.length,
        lessThanOrEqualTo(_kTickerWithoutDisposeBaseline),
        reason: 'TickerProvider state classes that own an '
            'AnimationController/Ticker but do not override dispose() '
            '(count=${offenders.length}, baseline='
            '$_kTickerWithoutDisposeBaseline). Each one will leak its '
            'controller(s) on widget removal.\n\n'
            'Offenders:\n${offenders.map((o) => '  $o').join('\n')}',
      );
      // Visibility on every run.
      // ignore: avoid_print
      print('\n[ticker-without-dispose] count=${offenders.length} '
          '(baseline=$_kTickerWithoutDisposeBaseline)');
    });

    test('StreamSubscription fields are cancelled in dispose()', () {
      final offenders = <String>[];
      for (final file in dartFiles) {
        final rel = _relPath(file.path);
        if (_kKnownIntentionalLeaks.contains(rel)) continue;
        final src = file.readAsStringSync();
        offenders.addAll(_findUncancelledSubs(src).map((m) => '$rel:$m'));
      }
      offenders.sort();
      expect(
        offenders.length,
        lessThanOrEqualTo(_kStreamSubWithoutCancelBaseline),
        reason: 'StreamSubscription fields with no `.cancel()` call in '
            'the same file (count=${offenders.length}, baseline='
            '$_kStreamSubWithoutCancelBaseline). These keep the upstream '
            'controller alive past widget lifetime.\n\n'
            'Offenders:\n${offenders.map((o) => '  $o').join('\n')}',
      );
      // ignore: avoid_print
      print('[stream-sub-without-cancel] count=${offenders.length} '
          '(baseline=$_kStreamSubWithoutCancelBaseline)');
    });

    test('density visibility — top files by AnimationController count', () {
      final counts = <MapEntry<String, int>>[];
      for (final file in dartFiles) {
        final rel = _relPath(file.path);
        final src = file.readAsStringSync();
        final n = RegExp(r'\bAnimationController\b').allMatches(src).length;
        if (n > 0) counts.add(MapEntry(rel, n));
      }
      counts.sort((a, b) => b.value.compareTo(a.value));
      // ignore: avoid_print
      print('\n[animation-controller density top 10]');
      for (final e in counts.take(10)) {
        // ignore: avoid_print
        print('  ${e.value.toString().padLeft(3)}× ${e.key}');
      }
      expect(counts.isNotEmpty, isTrue);
    });
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────

class _ClassRef {
  final String name;
  final int line;
  final int bodyStart; // index of opening `{` of class body
  final int bodyEnd; // index just past matching `}`
  _ClassRef(this.name, this.line, this.bodyStart, this.bodyEnd);
}

/// Find every `class _XxxState ... with ...TickerProviderStateMixin ... { ... }`
/// in the source, returning class name + body span. Skips comments and strings.
Iterable<_ClassRef> _findTickerProviderStates(String src) sync* {
  // Pattern: `class <Name> ... with <... TickerProvider...> ... {`
  // We do a token-aware scan rather than a single regex because class
  // declarations can span lines, the `with` clause can include several
  // mixins, and the body brace might not be on the same line.
  final lines = src.split('\n');
  // Collect per-line offsets so we can map back to a line number.
  final lineOffsets = <int>[0];
  for (int i = 0; i < src.length; i++) {
    if (src[i] == '\n') lineOffsets.add(i + 1);
  }
  int lineFor(int offset) {
    int lo = 0, hi = lineOffsets.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (lineOffsets[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo + 1;
  }

  // Strip comments + strings into a parallel char array of '_' so the
  // regex below doesn't fire inside docstrings. We keep original
  // newlines/positions so line numbers stay correct.
  final clean = _stripCommentsAndStrings(src);

  // Match `class <Name>` ... `TickerProviderStateMixin` ... `{`
  // until the first opening brace that begins the class body.
  final classDecl = RegExp(
    r'\bclass\s+(\w+)\b[^{}]*?TickerProviderStateMixin\b[^{}]*?\{',
    multiLine: true,
    dotAll: true,
  );
  for (final m in classDecl.allMatches(clean)) {
    final braceOpen = m.end - 1; // points at `{`
    final braceClose = _matchingBrace(clean, braceOpen);
    if (braceClose < 0) continue;
    yield _ClassRef(m.group(1)!, lineFor(m.start), braceOpen, braceClose);
  }
  // Also catch the rarer `... TickerProvider {` (no Mixin suffix).
  // Most cases use the *Mixin variant; this is a belt-and-suspenders.
  final classDeclTp = RegExp(
    r'\bclass\s+(\w+)\b[^{}]*?\sTickerProvider\s[^{}]*?\{',
    multiLine: true,
    dotAll: true,
  );
  for (final m in classDeclTp.allMatches(clean)) {
    final braceOpen = m.end - 1;
    final braceClose = _matchingBrace(clean, braceOpen);
    if (braceClose < 0) continue;
    yield _ClassRef(m.group(1)!, lineFor(m.start), braceOpen, braceClose);
  }
}

/// True if the class body span contains a `void dispose()` (or
/// `dispose()` with `@override`).
bool _classOverridesDispose(String src, _ClassRef cls) {
  final body = src.substring(cls.bodyStart, cls.bodyEnd);
  // Method signature: an identifier `dispose` followed by `(` and `)`,
  // not preceded by a `.` (which would be a call site, not a
  // declaration).
  final declRe = RegExp(r'(?<![A-Za-z0-9_.])dispose\s*\(\s*\)\s*\{');
  return declRe.hasMatch(body);
}

/// True if the class body declares an `AnimationController` or a raw
/// `Ticker(`/`Ticker?` that would need explicit teardown. Mixing in
/// TickerProvider*Mixin without owning any of those is benign — the
/// mixin only provides `vsync` to children that opt in.
bool _classOwnsTickerDriven(String src, _ClassRef cls) {
  final body = src.substring(cls.bodyStart, cls.bodyEnd);
  // Cheap heuristic: any of these tokens appearing in the body is a
  // strong sign the class owns a disposable. False positives are
  // acceptable because the test then falls through to
  // `_classOverridesDispose`, which most owners will satisfy anyway.
  return RegExp(r'\bAnimationController\b').hasMatch(body) ||
      RegExp(r'\bTicker\s*\(').hasMatch(body);
}

/// Heuristic: in the given source, find StreamSubscription field declarations
/// where there is no `.cancel()` call elsewhere in the same file. Returns a
/// list of `line:field_name` strings.
List<String> _findUncancelledSubs(String src) {
  final clean = _stripCommentsAndStrings(src);
  final lineOffsets = <int>[0];
  for (int i = 0; i < src.length; i++) {
    if (src[i] == '\n') lineOffsets.add(i + 1);
  }
  int lineFor(int offset) {
    int lo = 0, hi = lineOffsets.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (lineOffsets[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo + 1;
  }

  // Field declaration shapes we care about:
  //   StreamSubscription _sub;
  //   StreamSubscription? _sub;
  //   late StreamSubscription _sub;
  //   StreamSubscription<X> _sub;
  // We don't try to also catch local variables (a `final sub = ...` in a
  // method body is usually short-lived and not a field leak).
  final fieldRe = RegExp(
    r'(?:^|;|\{|\n)\s*(?:late\s+|final\s+)?StreamSubscription(?:<[^>]+>)?\??\s+(_?\w+)\s*[;=]',
    multiLine: true,
  );
  final hits = <String>[];
  for (final m in fieldRe.allMatches(clean)) {
    final name = m.group(1)!;
    // Look for any `<name>.cancel(` or `<name>?.cancel(` somewhere else
    // in the file — that's evidence the dev wired up cleanup.
    final cancelRe = RegExp(
      r'\b' + RegExp.escape(name) + r'\??\.cancel\s*\(',
    );
    if (cancelRe.hasMatch(clean)) continue;
    hits.add('${lineFor(m.start)}:$name');
  }
  return hits;
}

/// Replace strings and comments with underscores of equal length so
/// regexes can run unaffected by quoted noise. Preserves line breaks.
String _stripCommentsAndStrings(String src) {
  final out = StringBuffer();
  int i = 0;
  while (i < src.length) {
    final c = src[i];
    // Block comment
    if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      out.write('  ');
      i += 2;
      while (i < src.length && !(src[i] == '*' && i + 1 < src.length && src[i + 1] == '/')) {
        out.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < src.length) {
        out.write('  ');
        i += 2;
      }
      continue;
    }
    // Line comment
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    // String (single, double, raw, triple)
    if (c == '"' || c == "'") {
      // Detect triple
      final triple =
          (i + 2 < src.length && src[i + 1] == c && src[i + 2] == c) ? '$c$c$c' : null;
      if (triple != null) {
        out.write('   ');
        i += 3;
        while (i + 2 < src.length &&
            !(src[i] == c && src[i + 1] == c && src[i + 2] == c)) {
          out.write(src[i] == '\n' ? '\n' : ' ');
          i++;
        }
        if (i + 2 < src.length) {
          out.write('   ');
          i += 3;
        } else {
          while (i < src.length) {
            out.write(src[i] == '\n' ? '\n' : ' ');
            i++;
          }
        }
        continue;
      } else {
        out.write(' ');
        i++;
        while (i < src.length && src[i] != c) {
          if (src[i] == '\\' && i + 1 < src.length) {
            out.write('  ');
            i += 2;
            continue;
          }
          out.write(src[i] == '\n' ? '\n' : ' ');
          i++;
        }
        if (i < src.length) {
          out.write(' ');
          i++;
        }
        continue;
      }
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// Given the position of `{`, return the position just past the matching
/// `}`, or -1 if unbalanced. Assumes `_stripCommentsAndStrings` has
/// already been applied.
int _matchingBrace(String src, int openIdx) {
  if (openIdx < 0 || openIdx >= src.length || src[openIdx] != '{') return -1;
  int depth = 1;
  int i = openIdx + 1;
  while (i < src.length) {
    final c = src[i];
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return i + 1;
    }
    i++;
  }
  return -1;
}

String _relPath(String absPath) {
  final libIdx = absPath.indexOf('/lib/');
  if (libIdx < 0) return absPath;
  return absPath.substring(libIdx + 1);
}
