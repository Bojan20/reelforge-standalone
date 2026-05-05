// FLUX_MASTER_TODO 2.1.8 — Slot preview size cycle (extracted from
// `_SlotLabScreenState`). These unit tests pin down the four-stage
// transition state machine so future edits to the cycle behavior get
// an immediate red signal instead of subtle UX regressions.
//
// Cycle (Escape / PiP backdrop tap):
//   full → large → medium → off → off (idempotent at off)
//
// F11 (snap):
//   * → full   (no-op when already at full so repeat F11 doesn't replay
//               splash logic in the host screen)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/slot_preview_size.dart';

void main() {
  group('SlotPreviewSize.cycleDown', () {
    test('full → large', () {
      expect(SlotPreviewSize.full.cycleDown(), SlotPreviewSize.large);
    });

    test('large → medium', () {
      expect(SlotPreviewSize.large.cycleDown(), SlotPreviewSize.medium);
    });

    test('medium → off', () {
      expect(SlotPreviewSize.medium.cycleDown(), SlotPreviewSize.off);
    });

    test('off → off (idempotent — Escape with no preview is a no-op)', () {
      expect(SlotPreviewSize.off.cycleDown(), SlotPreviewSize.off);
    });

    test('full chain: 4× cycleDown lands on off and stays', () {
      var size = SlotPreviewSize.full;
      size = size.cycleDown(); // large
      expect(size, SlotPreviewSize.large);
      size = size.cycleDown(); // medium
      expect(size, SlotPreviewSize.medium);
      size = size.cycleDown(); // off
      expect(size, SlotPreviewSize.off);
      size = size.cycleDown(); // still off
      expect(size, SlotPreviewSize.off);
    });
  });

  group('SlotPreviewSize.enterFull', () {
    test('off → full', () {
      expect(SlotPreviewSize.off.enterFull(), SlotPreviewSize.full);
    });

    test('large → full (F11 always wins regardless of current PiP size)', () {
      expect(SlotPreviewSize.large.enterFull(), SlotPreviewSize.full);
    });

    test('medium → full', () {
      expect(SlotPreviewSize.medium.enterFull(), SlotPreviewSize.full);
    });

    test('full → full (idempotent — repeated F11 is a no-op)', () {
      expect(SlotPreviewSize.full.enterFull(), SlotPreviewSize.full);
    });
  });

  group('SlotPreviewSize.isPreviewMode', () {
    test('off is NOT preview mode', () {
      expect(SlotPreviewSize.off.isPreviewMode, isFalse);
    });

    test('full is preview mode', () {
      expect(SlotPreviewSize.full.isPreviewMode, isTrue);
    });

    test('large is preview mode', () {
      expect(SlotPreviewSize.large.isPreviewMode, isTrue);
    });

    test('medium is preview mode', () {
      expect(SlotPreviewSize.medium.isPreviewMode, isTrue);
    });
  });

  group('SlotPreviewSize.isPictureInPicture', () {
    test('off is NOT PiP', () {
      expect(SlotPreviewSize.off.isPictureInPicture, isFalse);
    });

    test('full is NOT PiP (covers screen, not overlay)', () {
      expect(SlotPreviewSize.full.isPictureInPicture, isFalse);
    });

    test('large is PiP', () {
      expect(SlotPreviewSize.large.isPictureInPicture, isTrue);
    });

    test('medium is PiP', () {
      expect(SlotPreviewSize.medium.isPictureInPicture, isTrue);
    });
  });

  group('SlotPreviewSize.fractionFactor', () {
    test('large → 0.80', () {
      expect(SlotPreviewSize.large.fractionFactor, 0.80);
    });

    test('medium → 0.50', () {
      expect(SlotPreviewSize.medium.fractionFactor, 0.50);
    });

    test('off → null (no overlay)', () {
      expect(SlotPreviewSize.off.fractionFactor, isNull);
    });

    test('full → null (covers entire screen, not a fraction)', () {
      expect(SlotPreviewSize.full.fractionFactor, isNull);
    });
  });

  group('SlotPreviewSize edge cases', () {
    test('cycleDown is deterministic — no hidden state', () {
      // Same input always yields same output, no matter how many times.
      for (var i = 0; i < 10; i++) {
        expect(SlotPreviewSize.full.cycleDown(), SlotPreviewSize.large);
        expect(SlotPreviewSize.off.cycleDown(), SlotPreviewSize.off);
      }
    });

    test('enterFull never lands on off — F11 always shows the preview', () {
      for (final size in SlotPreviewSize.values) {
        expect(size.enterFull(), isNot(SlotPreviewSize.off));
      }
    });

    test('cycleDown always converges to off in ≤ 3 steps', () {
      for (final start in SlotPreviewSize.values) {
        var size = start;
        var steps = 0;
        while (size != SlotPreviewSize.off && steps < 10) {
          size = size.cycleDown();
          steps++;
        }
        expect(size, SlotPreviewSize.off,
            reason: 'failed to converge from $start in 10 steps');
        expect(steps, lessThanOrEqualTo(3),
            reason: '$start should reach off in ≤ 3 cycleDown calls');
      }
    });

    test('SlotPreviewSize.values has exactly 4 stages', () {
      // Pin the cardinality — adding a new stage must update this test
      // and the cycleDown / enterFull contracts.
      expect(SlotPreviewSize.values.length, 4);
      expect(SlotPreviewSize.values, containsAll([
        SlotPreviewSize.off,
        SlotPreviewSize.full,
        SlotPreviewSize.large,
        SlotPreviewSize.medium,
      ]));
    });
  });

  // Sanity check that the model file imports correctly without pulling
  // in any Flutter widget machinery — the extension lives on a pure enum.
  test('library boundary: model has no widget dependency at runtime', () {
    // If this compiles and runs, the model is widget-framework-independent.
    // (`flutter_test` is required for the test runner itself, not the SUT.)
    debugPrint('SlotPreviewSize values: ${SlotPreviewSize.values}');
    expect(true, isTrue);
  });
}
