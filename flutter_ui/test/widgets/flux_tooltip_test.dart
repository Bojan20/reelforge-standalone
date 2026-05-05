/// SPEC-16 — `FluxTooltip` is the app-wide canonical tooltip surface.
/// These tests pin the load-bearing pure-formatter contract and the
/// widget-level rendering contract that the lint ratchet
/// (`test/lints/tooltip_consistency_test.dart`) enforces migration
/// against.
///
/// What we cover:
///
///   * `formatShortcut` — the macOS keyboard-symbol mapping that turns
///     `Cmd+K` into `⌘K`. A regression that swaps glyphs (e.g. `⌘`
///     and `⌃`) would silently mislabel every shortcut hint in the
///     app — easy to ship, hard to spot at a glance.
///   * `kWaitDuration` — the 150ms delay constant that distinguishes
///     a uniform FluxForge tooltip from the platform default. If
///     someone bumps it without thinking they break the "feels
///     instant" UX contract.
///   * Widget render — child renders even when shortcut hint is null;
///     wrapping doesn't change layout (no extra padding around child).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/common/flux_tooltip.dart';

void main() {
  group('FluxTooltip.formatShortcut — macOS keyboard symbol mapping', () {
    test('Cmd+ maps to ⌘', () {
      expect(FluxTooltip.formatShortcut('Cmd+K'), '⌘K');
    });

    test('Ctrl+ maps to ⌃ (different glyph from Cmd)', () {
      // Cmd and Ctrl are different keys on macOS. A regression that
      // collapsed them to the same glyph would silently mislabel
      // every cross-platform shortcut.
      expect(FluxTooltip.formatShortcut('Ctrl+K'), '⌃K');
      expect(FluxTooltip.formatShortcut('Ctrl+K') ==
             FluxTooltip.formatShortcut('Cmd+K'), isFalse);
    });

    test('Shift+ maps to ⇧', () {
      expect(FluxTooltip.formatShortcut('Shift+1'), '⇧1');
    });

    test('Alt+ and Option+ both map to ⌥ (intentional collapse)', () {
      // Alt and Option are the same physical key on macOS — the glyph
      // collapse is deliberate, not a bug.
      expect(FluxTooltip.formatShortcut('Alt+F'), '⌥F');
      expect(FluxTooltip.formatShortcut('Option+F'), '⌥F');
    });

    test('compound modifiers stack: Cmd+Shift+M → ⌘⇧M', () {
      expect(FluxTooltip.formatShortcut('Cmd+Shift+M'), '⌘⇧M');
    });

    test('all-three stack: Cmd+Ctrl+Alt+Shift+T → ⌘⌃⌥⇧T', () {
      expect(FluxTooltip.formatShortcut('Cmd+Ctrl+Alt+Shift+T'), '⌘⌃⌥⇧T');
    });

    test('non-modifier text passes through verbatim', () {
      // `Space`, `Enter`, `Esc`, etc. don't have a shortcut prefix, so
      // they must render exactly as written — no accidental glyph
      // substitution from a partial-match regex.
      expect(FluxTooltip.formatShortcut('Space'), 'Space');
      expect(FluxTooltip.formatShortcut('Enter'), 'Enter');
      expect(FluxTooltip.formatShortcut('Esc'), 'Esc');
    });

    test('pre-formatted glyphs pass through (no double-conversion)', () {
      // Callers may write '⌘K' directly (e.g. from a keymap config
      // that already stores the glyph). Idempotency means the
      // formatter doesn't re-substitute already-substituted text.
      expect(FluxTooltip.formatShortcut('⌘K'), '⌘K');
    });

    test('empty string round-trips', () {
      expect(FluxTooltip.formatShortcut(''), '');
    });

    test('text containing the substring "Cmd" without "+" passes through', () {
      // Defensive: only the `Cmd+` *prefix* (with the +) is mapped.
      // `Command` should not become `⌘mand`.
      expect(FluxTooltip.formatShortcut('Command'), 'Command');
    });
  });

  group('FluxTooltip.kWaitDuration — 150ms uniform delay', () {
    test('is exactly 150ms (not the platform default)', () {
      // The platform default Tooltip waitDuration is 0 (instant on
      // hover) or 1500ms depending on platform. 150ms is the FluxForge
      // "feels instant but doesn't fire on accidental cursor pass-by"
      // sweet spot. Bumping this constant would feel sluggish; lowering
      // would cause flicker on cursor scrubs.
      expect(FluxTooltip.kWaitDuration, const Duration(milliseconds: 150));
    });

    test('is a const so it can be used in const widget constructors', () {
      // Const usage is required for hot-reload friendliness in widget
      // trees; a runtime-computed Duration would force a rebuild.
      const d = FluxTooltip.kWaitDuration;
      expect(d, const Duration(milliseconds: 150));
    });
  });

  group('FluxTooltip widget rendering', () {
    testWidgets('renders the child without modifying its layout', (tester) async {
      const childKey = Key('flux-tooltip-child');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FluxTooltip(
              message: 'hello',
              child: SizedBox(key: childKey, width: 40, height: 40),
            ),
          ),
        ),
      );
      // Child renders.
      expect(find.byKey(childKey), findsOneWidget);
      // Child preserves its declared size — FluxTooltip is a transparent
      // wrapper, no extra padding or constraints.
      final size = tester.getSize(find.byKey(childKey));
      expect(size, const Size(40, 40));
    });

    testWidgets('accepts a null shortcutHint and still renders', (tester) async {
      // The hint is optional; absence must not throw.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FluxTooltip(
              message: 'no hint',
              child: SizedBox(width: 10, height: 10),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('accepts an empty shortcutHint and still renders', (tester) async {
      // Empty string is treated as "no hint" by the internal `hasHint`
      // guard — no rendering branch fires. This must not throw on
      // `formatShortcut('')` (covered by pure tests above).
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FluxTooltip(
              message: 'with empty hint',
              shortcutHint: '',
              child: SizedBox(width: 10, height: 10),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('preferBelow defaults to true and is overridable', (tester) async {
      // Smoke test that the constructor accepts the override and
      // doesn't throw on either branch.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                FluxTooltip(
                  message: 'below',
                  child: SizedBox(width: 10, height: 10),
                ),
                FluxTooltip(
                  message: 'above',
                  preferBelow: false,
                  child: SizedBox(width: 10, height: 10),
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
