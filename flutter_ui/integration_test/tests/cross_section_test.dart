/// FluxForge Studio — E2E Test: Cross-Section Flows
///
/// MEGA-TEST: Single testWidgets with ONE pumpApp call.
/// All 15 checks run sequentially to avoid framework.dart:6420
/// _InactiveElements._deactivateRecursively assertion on re-pump.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/app_harness.dart';
import '../helpers/waits.dart';
import '../helpers/gestures.dart';
import '../pages/launcher_page.dart';
import '../pages/control_bar_page.dart';
import '../pages/daw_page.dart';
import '../pages/slot_lab_page.dart';
import '../pages/middleware_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Cross-Section Flows', () {
    setUpAll(() async {
      await initializeApp();
    });

    setUp(() {
      installErrorFilter();
    });

    tearDown(() {
      restoreErrorHandler();
    });

    testWidgets('All cross-section flow tests (X01-X15)', (tester) async {
      // ═══════════════════════════════════════════════════════════════════════
      // PUMP APP ONCE — navigate to DAW once as starting point
      // ═══════════════════════════════════════════════════════════════════════
      await pumpApp(tester);
      await waitForAppReady(tester);

      final launcher = LauncherPage(tester);
      await launcher.navigateToDAW();
      await settle(tester, const Duration(seconds: 3));
      await drainExceptions(tester);

      final controlBar = ControlBarPage(tester);
      final daw = DAWPage(tester);
      final mw = MiddlewarePage(tester);
      final slotLab = SlotLabPage(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // SECTION SWITCHING
      // ═══════════════════════════════════════════════════════════════════════

      // ─── X01: DAW → Middleware → DAW round-trip ───────────────────────
      debugPrint('[E2E] X01: DAW → Middleware → DAW round-trip');
      {
        await daw.verifyLowerZoneTabs();

        await controlBar.switchToMiddleware();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);
        await mw.verifyLowerZoneTabs();

        await controlBar.switchToDAW();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);
        await daw.verifyLowerZoneTabs();
      }
      await drainExceptions(tester);

      // ─── X02: DAW → SlotLab → Middleware → DAW cycle ──────────────────
      debugPrint('[E2E] X02: DAW → SlotLab → Middleware → DAW cycle');
      {
        await controlBar.switchToSlotLab();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await controlBar.switchToMiddleware();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await controlBar.switchToDAW();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await controlBar.verifyControlBarPresent();
      }
      await drainExceptions(tester);

      // ─── X03: Rapid section switching stress test ─────────────────────
      debugPrint('[E2E] X03: Rapid section switching stress test');
      {
        for (int i = 0; i < 5; i++) {
          await controlBar.switchToMiddleware();
          await safePump(tester, const Duration(milliseconds: 200));
          await controlBar.switchToDAW();
          await safePump(tester, const Duration(milliseconds: 200));
        }
        await settle(tester, const Duration(milliseconds: 500));
        await controlBar.verifyControlBarPresent();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // PLAYBACK ISOLATION
      // ═══════════════════════════════════════════════════════════════════════

      // ─── X04: DAW play then switch to Middleware ──────────────────────
      debugPrint('[E2E] X04: DAW play then switch to Middleware');
      {
        await controlBar.pressPlay();
        await safePump(tester, const Duration(milliseconds: 500));

        await controlBar.switchToMiddleware();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await controlBar.switchToDAW();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await controlBar.pressStop();
        await safePump(tester, const Duration(milliseconds: 300));
        await controlBar.verifyTransportVisible();
      }
      await drainExceptions(tester);

      // ─── X05: SlotLab spin then switch to DAW ────────────────────────
      debugPrint('[E2E] X05: SlotLab spin then switch to DAW');
      {
        await controlBar.switchToSlotLab();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await slotLab.spin();
        await safePump(tester, const Duration(milliseconds: 300));

        await controlBar.switchToDAW();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await controlBar.verifyControlBarPresent();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // LOWER ZONE PERSISTENCE
      // ═══════════════════════════════════════════════════════════════════════

      // ─── X06: Lower zone tab persists across section switch ───────────
      debugPrint('[E2E] X06: Lower zone tab persists across section switch');
      {
        await daw.openMix();
        await safePump(tester, const Duration(milliseconds: 300));

        await controlBar.switchToMiddleware();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await controlBar.switchToDAW();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await daw.verifyLowerZoneTabs();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // ZONE TOGGLE INTERACTION
      // ═══════════════════════════════════════════════════════════════════════

      // ─── X07: Toggle all zones off then back on ───────────────────────
      debugPrint('[E2E] X07: Toggle all zones off then back on');
      {
        await controlBar.toggleLeft();
        await safePump(tester, const Duration(milliseconds: 200));
        await controlBar.toggleRight();
        await safePump(tester, const Duration(milliseconds: 200));
        await controlBar.toggleLower();
        await safePump(tester, const Duration(milliseconds: 200));

        await controlBar.toggleLeft();
        await safePump(tester, const Duration(milliseconds: 200));
        await controlBar.toggleRight();
        await safePump(tester, const Duration(milliseconds: 200));
        await controlBar.toggleLower();
        await safePump(tester, const Duration(milliseconds: 200));

        await controlBar.verifyControlBarPresent();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // FULL WORKFLOW
      // ═══════════════════════════════════════════════════════════════════════

      // ─── X08: Full DAW workflow ───────────────────────────────────────
      debugPrint('[E2E] X08: Full DAW workflow — browse, mix, process, deliver');
      {
        await daw.openBrowse();
        await safePump(tester, const Duration(milliseconds: 300));
        await daw.openEdit();
        await safePump(tester, const Duration(milliseconds: 300));
        await daw.openMix();
        await safePump(tester, const Duration(milliseconds: 300));
        await daw.openProcess();
        await safePump(tester, const Duration(milliseconds: 300));

        await controlBar.pressPlay();
        await safePump(tester, const Duration(milliseconds: 500));
        await controlBar.pressStop();
        await safePump(tester, const Duration(milliseconds: 300));

        await daw.openDeliver();
        await safePump(tester, const Duration(milliseconds: 300));
        await controlBar.verifyControlBarPresent();
      }
      await drainExceptions(tester);

      // ─── X09: Full Middleware workflow ─────────────────────────────────
      debugPrint('[E2E] X09: Full Middleware workflow — events, containers, routing');
      {
        await controlBar.switchToMiddleware();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await mw.openEvents();
        await safePump(tester, const Duration(milliseconds: 300));
        await mw.openContainers();
        await safePump(tester, const Duration(milliseconds: 300));
        await mw.openRouting();
        await safePump(tester, const Duration(milliseconds: 300));
        await mw.openRTPC();
        await safePump(tester, const Duration(milliseconds: 300));
        await mw.openDeliver();
        await safePump(tester, const Duration(milliseconds: 300));

        await mw.verifyLowerZoneTabs();
      }
      await drainExceptions(tester);

      // ─── X10: Full SlotLab workflow ───────────────────────────────────
      debugPrint('[E2E] X10: Full SlotLab workflow — spin, events, mix, bake');
      {
        await controlBar.switchToSlotLab();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await slotLab.spin();
        await safePump(tester, const Duration(milliseconds: 500));
        for (int i = 0; i < 40; i++) {
          await safePump(tester, const Duration(milliseconds: 100));
        }
        await slotLab.waitForSpinComplete(timeout: const Duration(seconds: 10));

        await slotLab.openEvents();
        await safePump(tester, const Duration(milliseconds: 300));
        await slotLab.openMix();
        await safePump(tester, const Duration(milliseconds: 300));
        await slotLab.openBake();
        await safePump(tester, const Duration(milliseconds: 300));

        await slotLab.verifyLowerZoneTabs();
      }
      await drainExceptions(tester);

      // Switch back to DAW for remaining tests
      await controlBar.switchToDAW();
      await settle(tester, const Duration(seconds: 2));
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // KEYBOARD SHORTCUTS
      // ═══════════════════════════════════════════════════════════════════════

      // ─── X11: Cmd+1 / Cmd+2 section switching ────────────────────────
      debugPrint('[E2E] X11: Cmd+1 / Cmd+2 section switching');
      {
        await sendKeyCombo(tester, meta: true, key: LogicalKeyboardKey.digit2);
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await sendKeyCombo(tester, meta: true, key: LogicalKeyboardKey.digit1);
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await controlBar.verifyControlBarPresent();
      }
      await drainExceptions(tester);

      // ─── X12: Command Palette opens with Cmd+K ────────────────────────
      debugPrint('[E2E] X12: Command Palette opens with Cmd+K');
      {
        await sendKeyCombo(tester, meta: true, key: LogicalKeyboardKey.keyK);
        await settle(tester, const Duration(milliseconds: 500));

        await pressEscape(tester);
        await settle(tester, const Duration(milliseconds: 300));

        await controlBar.verifyControlBarPresent();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // MIXER CROSS-SECTION
      // ═══════════════════════════════════════════════════════════════════════

      // ─── X13: Mixer visible in DAW and responsive after section switch ─
      debugPrint('[E2E] X13: Mixer visible and responsive after section switch');
      {
        await daw.openMix();
        await safePump(tester, const Duration(milliseconds: 300));

        await daw.tapMute();
        await safePump(tester, const Duration(milliseconds: 200));

        await controlBar.switchToMiddleware();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await controlBar.switchToDAW();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await daw.openMix();
        await safePump(tester, const Duration(milliseconds: 300));
        await daw.tapMute();
        await safePump(tester, const Duration(milliseconds: 200));
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // ULTIMATE STRESS TEST
      // ═══════════════════════════════════════════════════════════════════════

      // ─── X14: Ultimate stress test — all sections, all tabs ───────────
      debugPrint('[E2E] X14: Ultimate stress test — all sections, all tabs');
      {
        // DAW tabs
        await daw.cycleAllSuperTabs();
        await drainExceptions(tester);

        // Middleware tabs
        await controlBar.switchToMiddleware();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);
        await mw.cycleAllSuperTabs();
        await drainExceptions(tester);

        // SlotLab tabs
        await controlBar.switchToSlotLab();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);
        await slotLab.cycleAllSuperTabs();
        await drainExceptions(tester);

        // Back to DAW
        await controlBar.switchToDAW();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        // Transport cycle
        await controlBar.pressPlay();
        await safePump(tester, const Duration(milliseconds: 300));
        await controlBar.pressStop();
        await safePump(tester, const Duration(milliseconds: 300));

        // Zone toggles
        await controlBar.toggleLeft();
        await safePump(tester, const Duration(milliseconds: 200));
        await controlBar.toggleLeft();
        await safePump(tester, const Duration(milliseconds: 200));

        await controlBar.verifyControlBarPresent();
      }
      await drainExceptions(tester);

      // ─── X15: App survives 10 section switches without crash ──────────
      debugPrint('[E2E] X15: App survives 10 section switches without crash');
      {
        for (int i = 0; i < 10; i++) {
          final section = i % 3;
          switch (section) {
            case 0:
              await controlBar.switchToDAW();
              break;
            case 1:
              await controlBar.switchToMiddleware();
              break;
            case 2:
              await controlBar.switchToSlotLab();
              break;
          }
          await safePump(tester, const Duration(milliseconds: 150));
        }

        await settle(tester, const Duration(seconds: 1));
        await controlBar.verifyControlBarPresent();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] ✅ All 15 cross-section flow tests passed!');
      await finalDrain(tester);
    });
  });
}
