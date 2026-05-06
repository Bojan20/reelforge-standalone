// FLUX_MASTER_TODO 3.1.2 — kinematska Splash → Slot animacija.
//
// Ovi testovi pinuju load-bearing contract:
//   * onComplete callback fire-uje **tačno jednom** posle 1.6s.
//   * Animacija ne blokira pointer evente — IgnorePointer wrapping je
//     invariant da se SlotLabScreen klikovi ispod ne sačuvaju.
//   * Default reels (5×3) se renderuje bez throwing-a — painter neće
//     crash na common config.
//   * Custom reels (3x3, 6x4) su validne dimenzije.
//
// Animacija je čisto vizuelna pa nema "pixel-perfect" testovi za
// boje/glow — ti su covered code review-om i live ekranskim verify-om.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/splash/slot_entry_animation.dart';

void main() {
  group('SlotEntryAnimation — completion contract', () {
    testWidgets('onComplete fire-uje tačno jednom posle 1.6s', (tester) async {
      var fireCount = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SlotEntryAnimation(
            onComplete: () => fireCount++,
          ),
        ),
      ));

      // Pre punog trajanja — onComplete NE sme da bude pozvan.
      await tester.pump(const Duration(milliseconds: 800));
      expect(fireCount, 0, reason: 'onComplete ne sme da fire-uje pre kraja animacije');

      // Posle 1.6s + buffer — tačno jednom.
      await tester.pump(const Duration(milliseconds: 900));
      expect(fireCount, 1, reason: 'onComplete mora da fire-uje tačno jednom kad master reach-uje completed');

      // Dodatni pump-ovi NE smeju da dvostruko fire-uju.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(fireCount, 1, reason: 'guard `_completedFired` mora da spreči duplicate fire-ove');
    });

    testWidgets('IgnorePointer wraps overlay — klikovi prolaze ispod', (tester) async {
      // Ako bi animacija blokirala pointer evente, korisnik bi morao da
      // sačeka 1.6s pre nego što interagovao sa SlotLab-om — frustrirajuće
      // i pogrešno (animacija je vizuelni teaser, ne barrier).
      var bottomTaps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => bottomTaps++,
                child: const SizedBox.expand(),
              ),
              SlotEntryAnimation(onComplete: () {}),
            ],
          ),
        ),
      ));

      // Tap u sredini ekrana (gde animacija renderuje bloom).
      await tester.tap(find.byType(SlotEntryAnimation));
      await tester.pump();
      expect(bottomTaps, 1,
          reason: 'IgnorePointer mora da pusti klik kroz overlay na underlying widget');
    });

    testWidgets('default 5×3 reels renderuje bez throwing-a', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SlotEntryAnimation(onComplete: () {}),
        ),
      ));
      // Pump kroz različite tačke animacije — svaki frame mora da
      // izađe bez exception-a iz painter-a.
      for (final ms in [50, 200, 500, 800, 1100, 1400, 1700]) {
        await tester.pump(Duration(milliseconds: ms));
        expect(tester.takeException(), isNull,
            reason: 'painter exception na ${ms}ms — animacija puca mid-flight');
      }
    });

    testWidgets('custom 6×4 reels renderuje bez throwing-a', (tester) async {
      // Veće dimenzije — defensive smoke da painter ne pretpostavlja 5×3.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SlotEntryAnimation(
            reelCount: 6,
            rowCount: 4,
            onComplete: () {},
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('minimal 3×3 reels renderuje bez throwing-a', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SlotEntryAnimation(
            reelCount: 3,
            rowCount: 3,
            onComplete: () {},
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('dispose tokom mid-animacije ne fire-uje onComplete', (tester) async {
      // Edge case: ako parent unmount-uje overlay pre kraja, onComplete
      // NE sme da pozove (caller je već routed-uo dalje).
      var fireCount = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SlotEntryAnimation(onComplete: () => fireCount++),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      // Replace widget tree — animacija je disposed mid-flight.
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pump(const Duration(seconds: 2));
      expect(fireCount, 0,
          reason: 'mid-flight dispose ne sme da pozove onComplete (parent već routed dalje)');
    });
  });
}
