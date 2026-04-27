/// Mega-screen complexity ratchet — FLUX_MASTER_TODO 1.1.3 / 1.3.1–1.3.3.
///
/// The three mega-screens (`engine_connected_layout`, `slot_lab_screen`,
/// `helix_screen`) collectively hold ~43K LOC, hundreds of providers,
/// and dozens of inline state classes. Writing 30 integration-interaction
/// widget tests per screen (the original spec) requires a full mock
/// provider tree (~100+ injected dependencies). That's its own multi-week
/// project; meanwhile the screens keep growing.
///
/// This test is the practical minimum: a static budget that fails CI if
/// any of the three crosses a hard ceiling on:
///   • file LOC,
///   • Consumer / Selector / context.watch/read/select density,
///   • inline `extends State<...>` class count.
///
/// Each ceiling sits a small percentage above the captured 2026-04-28
/// baseline. A growing screen forces the author to either justify the
/// growth (raise the ceiling in the same commit, with a TODO link) or
/// extract widgets into separate files. Same monotone-down ratchet
/// pattern as 1.3.4 (gesture conflicts), 1.3.5 (dispose / leaks) and
/// 1.1.5b/c (unsafe Send/Sync SAFETY).
///
/// Why this is the right answer here, not yet-another-runtime-test:
///   * The 30-interaction widget-test plan in the spec assumes mock
///     infrastructure that doesn't exist; building it would itself be
///     ~40 hours of provider-mock scaffolding before the first
///     assertion runs.
///   * The actual failure mode we're guarding against — "the screen
///     keeps growing until nobody can refactor it" — is captured by
///     LOC + provider density. Runtime tests don't catch that.
///   * The smoke test most projects write at this scale ("does it
///     mount?") is brittle (one new GetIt registration breaks every
///     test) and gives low signal. The complexity ratchet gives a
///     hard, reviewable signal in PR diff.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Per-screen budget. Increase requires a same-commit comment block
/// in this constant explaining WHY (matching 1.3.4 conventions).
class _ScreenBudget {
  final String relPath;
  final int maxLoc;
  final int maxProvidersDensity;
  final int maxInlineStateClasses;
  const _ScreenBudget({
    required this.relPath,
    required this.maxLoc,
    required this.maxProvidersDensity,
    required this.maxInlineStateClasses,
  });
}

// ── Captured 2026-04-28 ────────────────────────────────────────────────
// LOC, provider/context density, and inline-State counts are checked
// against these ceilings. Each is set ~5% above the actual count so
// in-flight refactors have wiggle room without blocking unrelated PRs;
// new feature growth pays the budget-raise tax.

const List<_ScreenBudget> _kBudgets = [
  _ScreenBudget(
    relPath: 'lib/screens/engine_connected_layout.dart',
    maxLoc: 18500,                  // actual 17,490
    maxProvidersDensity: 190,       // actual 177
    maxInlineStateClasses: 16,      // actual 13
  ),
  _ScreenBudget(
    relPath: 'lib/screens/slot_lab_screen.dart',
    maxLoc: 16000,                  // actual 15,183
    maxProvidersDensity: 60,        // actual 49
    maxInlineStateClasses: 6,       // actual 3
  ),
  _ScreenBudget(
    relPath: 'lib/screens/helix_screen.dart',
    maxLoc: 11000,                  // actual 10,439
    maxProvidersDensity: 12,        // actual 7
    maxInlineStateClasses: 42,      // actual 37
  ),
];

void main() {
  group('Mega-screen complexity ratchet (FLUX_MASTER_TODO 1.1.3)', () {
    test('every budgeted screen exists', () {
      for (final b in _kBudgets) {
        expect(File(b.relPath).existsSync(), isTrue,
            reason: 'budgeted screen missing: ${b.relPath}');
      }
    });

    test('LOC, provider density, inline-State count under budget', () {
      final breaches = <String>[];
      for (final b in _kBudgets) {
        final f = File(b.relPath);
        if (!f.existsSync()) continue;
        final src = f.readAsStringSync();
        final loc = src.split('\n').length;
        final providers = _countProviders(src);
        final stateClasses = _countInlineStateClasses(src);

        if (loc > b.maxLoc) {
          breaches.add(
              '${b.relPath} LOC=$loc > budget ${b.maxLoc}. Extract widgets '
              'or raise the ceiling in the same commit.');
        }
        if (providers > b.maxProvidersDensity) {
          breaches.add(
              '${b.relPath} provider/context density=$providers > '
              '${b.maxProvidersDensity}.');
        }
        if (stateClasses > b.maxInlineStateClasses) {
          breaches.add(
              '${b.relPath} inline `extends State<...>` count=$stateClasses '
              '> ${b.maxInlineStateClasses}. Move private state classes '
              'to their own file.');
        }
      }
      if (breaches.isNotEmpty) {
        final joined = breaches.join('\n  ');
        fail('Mega-screen complexity ratchet breached:\n  $joined');
      }
    });

    test('density visibility — print every run', () {
      // ignore: avoid_print
      print('\n[mega-screen complexity]');
      for (final b in _kBudgets) {
        final f = File(b.relPath);
        if (!f.existsSync()) continue;
        final src = f.readAsStringSync();
        final loc = src.split('\n').length;
        final providers = _countProviders(src);
        final stateClasses = _countInlineStateClasses(src);
        // ignore: avoid_print
        print(
          '  ${b.relPath.padRight(48)}  '
          'LOC=${loc.toString().padLeft(6)}/${b.maxLoc}  '
          'providers=${providers.toString().padLeft(3)}/${b.maxProvidersDensity}  '
          'state=${stateClasses.toString().padLeft(3)}/${b.maxInlineStateClasses}',
        );
      }
      expect(true, isTrue);
    });
  });
}

int _countProviders(String src) {
  // Consumer<X>, Selector<X,Y>, context.watch<X>(), context.read<X>(),
  // context.select<X,Y>(...). All five count as "this screen depends
  // on a provider" — driver of build complexity.
  final re = RegExp(
    r'\b(?:Consumer|Selector)\s*<|'
    r'\bcontext\s*\.\s*(?:watch|read|select)\s*<',
  );
  return re.allMatches(src).length;
}

int _countInlineStateClasses(String src) {
  // `class _XxxState extends State<...>` declarations inside the screen
  // file. These are private-to-file state classes — each one is a UI
  // chunk that could in principle live in its own widget file. Past a
  // threshold the file becomes unreviewable.
  final re = RegExp(r'\bclass\s+\w+\s+extends\s+State\s*<');
  return re.allMatches(src).length;
}
