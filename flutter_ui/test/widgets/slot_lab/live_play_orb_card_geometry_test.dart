/// Live Play Orb — Card geometry invariant tests
///
/// Pure-math tests that prove the 2px RenderFlex overflow fix is correct:
///   cardH(orbPx) == columnContentHeight(orbPx) + 2 * borderW  for all orbPx
///
/// If this invariant holds, the card Container always has exactly enough
/// height to accommodate the Column children stack plus the BoxDecoration
/// border inset (1px top + 1px bottom). Before the fix, cardH was equal to
/// columnContentHeight — so the border stole 2px from the Column space,
/// triggering "RenderFlex overflowed by 2.0 pixels on the bottom".
///
/// These tests run without the Flutter engine, without FFI, without any
/// provider — pure arithmetic. They are the programmatic "hands + eyes"
/// proof that the fix matches the intent, for every orb size in range.
@Tags(['widget'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/slot_lab/live_play_orb_overlay.dart';

void main() {
  group('LivePlayOrbCardGeometry — border inset invariant', () {
    test('cardH == columnContentHeight + 2 * borderW for minOrbPx', () {
      const orbPx = LivePlayOrbCardGeometry.minOrbPx;
      final delta =
          LivePlayOrbCardGeometry.cardH(orbPx) -
          LivePlayOrbCardGeometry.columnContentHeight(orbPx);
      expect(delta, closeTo(2 * LivePlayOrbCardGeometry.borderW, 1e-9));
      expect(delta, closeTo(2.0, 1e-9));
    });

    test('cardH == columnContentHeight + 2 * borderW for maxOrbPx', () {
      const orbPx = LivePlayOrbCardGeometry.maxOrbPx;
      final delta =
          LivePlayOrbCardGeometry.cardH(orbPx) -
          LivePlayOrbCardGeometry.columnContentHeight(orbPx);
      expect(delta, closeTo(2.0, 1e-9));
    });

    test('invariant holds across full orb range (sweep 10px steps)', () {
      for (
        double orb = LivePlayOrbCardGeometry.minOrbPx;
        orb <= LivePlayOrbCardGeometry.maxOrbPx;
        orb += 10.0
      ) {
        final delta =
            LivePlayOrbCardGeometry.cardH(orb) -
            LivePlayOrbCardGeometry.columnContentHeight(orb);
        expect(
          delta,
          closeTo(2.0, 1e-9),
          reason:
              'Border inset compensation broken at orbPx=$orb — '
              'expected 2.0px, got $delta. This would trigger '
              'RenderFlex overflow by ${2.0 - delta}px.',
        );
      }
    });

    test('cardH strictly greater than columnContentHeight', () {
      // Regression guard: if someone accidentally removes the +2*borderW,
      // this fails immediately.
      for (final orb in [90.0, 140.0, 160.0, 200.0, 260.0, 320.0]) {
        expect(
          LivePlayOrbCardGeometry.cardH(orb),
          greaterThan(LivePlayOrbCardGeometry.columnContentHeight(orb)),
          reason: 'cardH must leave room for border at orbPx=$orb',
        );
      }
    });
  });

  group('LivePlayOrbCardGeometry — concrete known values', () {
    // Layout sum check for a canonical standard orb size (160px).
    //   titleH(34) + vGap(6) + orbPx(160) + vGap(6) + busHdrH(16)
    //   + 6*busRowH(132) + vGap(6) + footerH(34) + cardPadH(10)
    //   = 404
    // cardH = 404 + 2 = 406
    test('standard orb (160px): content=404, cardH=406', () {
      expect(LivePlayOrbCardGeometry.columnContentHeight(160.0), 404.0);
      expect(LivePlayOrbCardGeometry.cardH(160.0), 406.0);
    });

    test('minimum orb (90px): content=334, cardH=336', () {
      expect(LivePlayOrbCardGeometry.columnContentHeight(90.0), 334.0);
      expect(LivePlayOrbCardGeometry.cardH(90.0), 336.0);
    });

    test('maximum orb (320px): content=564, cardH=566', () {
      expect(LivePlayOrbCardGeometry.columnContentHeight(320.0), 564.0);
      expect(LivePlayOrbCardGeometry.cardH(320.0), 566.0);
    });
  });

  group('LivePlayOrbCardGeometry — width', () {
    test('cardW respects minCardW floor when orb is small', () {
      expect(
        LivePlayOrbCardGeometry.cardW(90.0),
        LivePlayOrbCardGeometry.minCardW,
      );
      expect(
        LivePlayOrbCardGeometry.cardW(150.0),
        LivePlayOrbCardGeometry.minCardW,
      );
    });

    test('cardW grows with orb beyond minCardW', () {
      // orbPx + 2*cardPadH = 320 + 20 = 340 > 320 floor
      expect(LivePlayOrbCardGeometry.cardW(320.0), 340.0);
    });
  });

  group('LivePlayOrbCardGeometry — constants sanity', () {
    test('borderW matches BoxDecoration Border.all(width: 1)', () {
      expect(LivePlayOrbCardGeometry.borderW, 1.0);
    });

    test('numBusRows matches OrbBusId enum length (6 buses)', () {
      expect(LivePlayOrbCardGeometry.numBusRows, 6);
    });
  });
}
