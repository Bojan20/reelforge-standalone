// FLUX_MASTER_TODO 2.1.7 — `GridResizePipeline` is the single entry
// point for "user changed REELS×ROWS" (Omnibar inline pill, GAME CONFIG
// button, future Cmd+K command, CortexEye automation). The full
// pipeline depends on `GetIt`-registered providers + a live Rust
// engine, so end-to-end execution lives in widget integration tests.
//
// These unit tests pin the *pure* edges of the pipeline:
//
//   * `GridResizeBounds.validate` / `isValid` — REELS 3..6, ROWS 2..4
//   * `GridResizePipeline.parseGridInput` — `5x3`, `5×3`, `5X3`, junk
//   * `GridResizeResult.shortStatus` — `✓ N×M ready` / `✗ message`
//
// A regression in any of those three pure surfaces would either:
//   - admit out-of-range input and crash downstream (validate)
//   - reject legitimate user input as malformed (parseGridInput)
//   - render the wrong toast color in the Omnibar pill (shortStatus)
//
// All three would be hard to spot in a manual smoke test.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/grid_resize_pipeline.dart';

void main() {
  group('GridResizeBounds.validate', () {
    test('accepts the canonical 5x3 grid', () {
      expect(GridResizeBounds.validate(5, 3), isNull);
      expect(GridResizeBounds.isValid(5, 3), isTrue);
    });

    test('accepts every in-range pair', () {
      for (int r = GridResizeBounds.minReels; r <= GridResizeBounds.maxReels; r++) {
        for (int rows = GridResizeBounds.minRows; rows <= GridResizeBounds.maxRows; rows++) {
          expect(GridResizeBounds.isValid(r, rows), isTrue,
              reason: '$r × $rows must be valid');
        }
      }
    });

    test('rejects REELS below the floor', () {
      expect(GridResizeBounds.validate(2, 3), contains('REELS'));
      expect(GridResizeBounds.isValid(2, 3), isFalse);
    });

    test('rejects REELS above the ceiling', () {
      expect(GridResizeBounds.validate(7, 3), contains('REELS'));
      expect(GridResizeBounds.isValid(7, 3), isFalse);
    });

    test('rejects ROWS below the floor', () {
      expect(GridResizeBounds.validate(5, 1), contains('ROWS'));
      expect(GridResizeBounds.isValid(5, 1), isFalse);
    });

    test('rejects ROWS above the ceiling', () {
      expect(GridResizeBounds.validate(5, 5), contains('ROWS'));
      expect(GridResizeBounds.isValid(5, 5), isFalse);
    });

    test('error message names the offending dimension first', () {
      // When both dims are bad, the REELS check fires first so the user
      // fixes one error at a time instead of guessing which is wrong.
      final msg = GridResizeBounds.validate(99, 99);
      expect(msg, isNotNull);
      expect(msg, contains('REELS'));
    });

    test('rejects negative inputs (defensive against int overflow paths)', () {
      expect(GridResizeBounds.isValid(-1, 3), isFalse);
      expect(GridResizeBounds.isValid(5, -1), isFalse);
    });
  });

  group('GridResizePipeline.parseGridInput', () {
    test('ASCII lowercase x', () {
      expect(GridResizePipeline.parseGridInput('5x3'), (5, 3));
    });

    test('ASCII uppercase X', () {
      expect(GridResizePipeline.parseGridInput('5X3'), (5, 3));
    });

    test('typographic times sign ×', () {
      expect(GridResizePipeline.parseGridInput('5×3'), (5, 3));
    });

    test('mixed whitespace tolerated', () {
      expect(GridResizePipeline.parseGridInput('  5  x  3  '), (5, 3));
    });

    test('out-of-range pair still parses (validation is a separate step)', () {
      // The parser deliberately doesn't validate — that's
      // `GridResizeBounds`. Mixing the two would couple the inline-edit
      // affordance's parse step to the engine's resize envelope, and
      // make it harder to surface a bounds error vs a format error.
      expect(GridResizePipeline.parseGridInput('99x99'), (99, 99));
    });

    test('empty input returns null', () {
      expect(GridResizePipeline.parseGridInput(''), isNull);
      expect(GridResizePipeline.parseGridInput('   '), isNull);
    });

    test('single number returns null (no separator)', () {
      expect(GridResizePipeline.parseGridInput('5'), isNull);
    });

    test('non-numeric segments return null', () {
      expect(GridResizePipeline.parseGridInput('fivexthree'), isNull);
      expect(GridResizePipeline.parseGridInput('5xthree'), isNull);
    });

    test('extra separators return null', () {
      expect(GridResizePipeline.parseGridInput('5x3x2'), isNull);
    });

    test('decimals return null (grid is integer-only)', () {
      expect(GridResizePipeline.parseGridInput('5.5x3'), isNull);
      expect(GridResizePipeline.parseGridInput('5x3.0'), isNull);
    });
  });

  group('GridResizeResult.shortStatus', () {
    test('success format: ✓ N×M ready', () {
      const r = GridResizeResult(
        success: true, message: '5×3 ready', reels: 5, rows: 3,
      );
      expect(r.shortStatus, '✓ 5×3 ready');
    });

    test('failure format: ✗ <message>', () {
      const r = GridResizeResult(
        success: false, message: 'Engine init failed', reels: 5, rows: 3,
      );
      expect(r.shortStatus, '✗ Engine init failed');
    });

    test('success short-status starts with ✓ (used by Omnibar flash color)', () {
      // The pill renders RED when shortStatus starts with ✗ and GREEN
      // when it starts with ✓. A regression that swapped the prefix
      // would silently mis-color the toast.
      const ok = GridResizeResult(
          success: true, message: 'whatever', reels: 5, rows: 3);
      const err = GridResizeResult(
          success: false, message: 'whatever', reels: 5, rows: 3);
      expect(ok.shortStatus.startsWith('✓'), isTrue);
      expect(err.shortStatus.startsWith('✗'), isTrue);
    });
  });

  group('GridResizeBounds constants pin the supported envelope', () {
    test('canonical defaults sit at the typical industry slot grid', () {
      // 5×3 is the canonical slot lab default. If the bounds shift
      // such that 5×3 is no longer valid, *something* is broken.
      expect(GridResizeBounds.isValid(5, 3), isTrue);
    });

    test('REELS envelope is 3..6', () {
      expect(GridResizeBounds.minReels, 3);
      expect(GridResizeBounds.maxReels, 6);
    });

    test('ROWS envelope is 2..4', () {
      expect(GridResizeBounds.minRows, 2);
      expect(GridResizeBounds.maxRows, 4);
    });
  });
}
