/// Sprint 15 Faza 4.D.3 — pure unit tests for the slot-preview fallback
/// rectangle.  These exercise the math the HELIX screen relies on when its
/// GlobalKey-backed RenderBox lookup hasn't attached yet (first build,
/// headless tests, disposal mid-frame).
///
/// The helper is intentionally side-effect free so we can cover all of its
/// edge cases without pumping a widget tree.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/screens/helix/helpers/slot_rect_resolver.dart';

void main() {
  group('computeSlotRectFallback (Sprint 15 Faza 4.D.3)', () {
    // ── Happy path ─────────────────────────────────────────────────────────

    test('returns rect with width = screenWidth × ratio (60% standard)', () {
      final rect = computeSlotRectFallback(
        screenSize: const Size(1920, 1080),
        gridWidthRatio: 0.6,
        leftOffsetPx: 60,
        vInsetPx: 60,
      );
      expect(rect.left, 60);
      expect(rect.top, 60);
      expect(rect.width, closeTo(1920 * 0.6, 1e-9));
      expect(rect.height, closeTo(1080 - 120, 1e-9));
    });

    test('honors leftOffset as origin.dx (decoupled from width math)', () {
      final rect = computeSlotRectFallback(
        screenSize: const Size(1000, 500),
        gridWidthRatio: 0.5,
        leftOffsetPx: 137.5,
        vInsetPx: 40,
      );
      expect(rect.left, 137.5);
    });

    test('vInset applies symmetrically to top and bottom', () {
      final rect = computeSlotRectFallback(
        screenSize: const Size(800, 600),
        gridWidthRatio: 0.5,
        leftOffsetPx: 0,
        vInsetPx: 75,
      );
      expect(rect.top, 75);
      expect(rect.height, 600 - 2 * 75);
      // bottom = top + height should reach exactly `screenH - vInset`.
      expect(rect.bottom, 600 - 75);
    });

    // ── Defensive edges ────────────────────────────────────────────────────

    test('gridWidthRatio == 0 yields zero-width rect at origin', () {
      final rect = computeSlotRectFallback(
        screenSize: const Size(1920, 1080),
        gridWidthRatio: 0,
        leftOffsetPx: 60,
        vInsetPx: 60,
      );
      expect(rect.width, 0);
      // Origin still honored — only width collapses.
      expect(rect.left, 60);
      expect(rect.top, 60);
    });

    test('zero screenWidth still produces a valid (zero-width) rect', () {
      final rect = computeSlotRectFallback(
        screenSize: const Size(0, 800),
        gridWidthRatio: 0.6,
        leftOffsetPx: 0,
        vInsetPx: 20,
      );
      expect(rect.width, 0);
      // Height still computed normally.
      expect(rect.height, 800 - 40);
      expect(rect.isFinite, isTrue);
    });

    test('vInset larger than half-screen does not produce a negative rect', () {
      // 600px screen with 400px inset would have produced height=-200
      // (Rect.fromLTWH treats negative dimensions as an inverted rect).
      // The helper clamps to 0 to keep the rect well-formed.
      final rect = computeSlotRectFallback(
        screenSize: const Size(800, 600),
        gridWidthRatio: 0.5,
        leftOffsetPx: 0,
        vInsetPx: 400,
      );
      expect(rect.height, 0,
          reason: 'oversize inset must clamp to 0, not produce -200 height');
      expect(rect.top, 400);
    });

    test('negative gridWidthRatio clamps width to 0 (no inverted rect)', () {
      final rect = computeSlotRectFallback(
        screenSize: const Size(1000, 600),
        gridWidthRatio: -0.5,
        leftOffsetPx: 100,
        vInsetPx: 30,
      );
      expect(rect.width, 0);
      // Origin and height unchanged.
      expect(rect.left, 100);
      expect(rect.height, 540);
    });

    // ── Real HELIX_SCREEN constants ───────────────────────────────────────

    test('matches the production constants on common viewport sizes', () {
      // Constants pulled from `helix_screen.dart` (lines 167–169):
      const double kGridWidthRatio = 0.6;
      const double kLeftOffsetPx = 60.0;
      const double kVInsetPx = 60.0;

      // MBP 13" Retina (logical 1440×900)
      final mbp = computeSlotRectFallback(
        screenSize: const Size(1440, 900),
        gridWidthRatio: kGridWidthRatio,
        leftOffsetPx: kLeftOffsetPx,
        vInsetPx: kVInsetPx,
      );
      expect(mbp.left, 60);
      expect(mbp.top, 60);
      expect(mbp.width, closeTo(1440 * 0.6, 1e-9));
      expect(mbp.height, 900 - 120);

      // External 4K (logical 1920×1200 with HiDPI scaling)
      final extDisplay = computeSlotRectFallback(
        screenSize: const Size(1920, 1200),
        gridWidthRatio: kGridWidthRatio,
        leftOffsetPx: kLeftOffsetPx,
        vInsetPx: kVInsetPx,
      );
      expect(extDisplay.width, closeTo(1920 * 0.6, 1e-9));
      expect(extDisplay.height, 1200 - 120);

      // Tiny window (just above the inset threshold)
      final tiny = computeSlotRectFallback(
        screenSize: const Size(400, 200),
        gridWidthRatio: kGridWidthRatio,
        leftOffsetPx: kLeftOffsetPx,
        vInsetPx: kVInsetPx,
      );
      expect(tiny.width, closeTo(400 * 0.6, 1e-9));
      expect(tiny.height, 200 - 120);
      expect(tiny.height, greaterThan(0));
    });

    test('returned rect is always finite and well-formed', () {
      // Sanity: for any reasonable input we never propagate NaN/Infinity.
      final rect = computeSlotRectFallback(
        screenSize: const Size(1920, 1080),
        gridWidthRatio: 0.6,
        leftOffsetPx: 60,
        vInsetPx: 60,
      );
      expect(rect.isFinite, isTrue);
      expect(rect.width >= 0, isTrue);
      expect(rect.height >= 0, isTrue);
      expect(rect.left.isFinite, isTrue);
      expect(rect.top.isFinite, isTrue);
    });
  });
}
