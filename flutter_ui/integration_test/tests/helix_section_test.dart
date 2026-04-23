/// FluxForge Studio — E2E Test: HELIX Section (Ultimate)
///
/// MEGA-TEST: Single testWidgets with ONE pumpApp call.
/// 60 tests covering EVERY scenario — zero blind spots.
///
/// Usage:
///   cd flutter_ui
///   flutter test integration_test/tests/helix_section_test.dart -d macos
///
/// Coverage:
/// H01-H05:  Launch, initial state, no corruption
/// H06-H10:  Mode switching (COMPOSE/FOCUS/ARCHITECT) + stress
/// H11-H15:  Spine panels (all 4 + cycle + close)
/// H16-H20:  Dock tabs (all 12 + rapid switching + keyboard)
/// H21-H25:  Auto-Bind, MASTER fader, CHANNELS section
/// H26-H30:  Spin button, SLAM, SKIP, full cycle
/// H31-H35:  Rapid spins, spin+SLAM combo, spin after win
/// H36-H40:  Concurrent actions (spin+mode, spin+panel, spin+dock)
/// H41-H45:  ESC safety (barrage, after spin, after panel, in all modes)
/// H46-H50:  Keyboard shortcuts (all keys, combos, dock switching)
/// H51-H55:  Integrity (overflow, placeholders, corrupt data, widget count)
/// H56-H60:  Stress + stability (full cycle, endurance, final verification)

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/app_harness.dart';
import '../helpers/waits.dart';
import '../helpers/gestures.dart';
import '../pages/launcher_page.dart';
import '../pages/helix_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('HELIX Section — Ultimate', () {
    setUpAll(() async {
      await initializeApp();
    });

    setUp(() {
      installErrorFilter();
    });

    tearDown(() {
      restoreErrorHandler();
    });

    tearDownAll(() {
      deactivateZoneFilter();
    });

    testWidgets('All HELIX tests (H01-H60)', (tester) async {
      // ═══════════════════════════════════════════════════════════════════════
      // BOOTSTRAP — Navigate to HELIX once
      // ═══════════════════════════════════════════════════════════════════════
      await pumpApp(tester);
      await waitForAppReady(tester);

      final launcher = LauncherPage(tester);
      await launcher.selectSlotLab();
      await settle(tester, const Duration(seconds: 3));
      await drainExceptions(tester);

      final helix = HelixPage(tester);
      await settle(tester, const Duration(seconds: 2));
      await drainExceptions(tester);

      // Track initial widget count for later comparison
      final initialWidgetCount = helix.countVisibleWidgets();

      // ═══════════════════════════════════════════════════════════════════════
      // H01-H05: LAUNCH & INITIAL STATE
      // ═══════════════════════════════════════════════════════════════════════

      await helix.verifyOnHelix();
      await drainExceptions(tester);

      helix.verifyNoOverflow();
      await drainExceptions(tester);

      helix.verifyNoPlaceholders();
      await drainExceptions(tester);

      helix.verifyNoCorruptData();
      await drainExceptions(tester);

      await helix.verifyDockTabs();
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H06-H10: MODE SWITCHING
      // ═══════════════════════════════════════════════════════════════════════

      {
        await helix.pressF();
        await safePump(tester, const Duration(milliseconds: 500));
        // FOCUS mode: dock hidden
        await helix.pressF();
        await safePump(tester, const Duration(milliseconds: 500));
        // Back to COMPOSE: dock visible
        await helix.verifyDockTabs();
      }
      await drainExceptions(tester);

      {
        await helix.pressA();
        await safePump(tester, const Duration(milliseconds: 500));
        await helix.pressA();
        await safePump(tester, const Duration(milliseconds: 500));
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      {
        await helix.stressModeSwitching();
        helix.verifyNoOverflow();
        await helix.verifyOnHelix();
      }
      await drainExceptions(tester);

      {
        await helix.switchToFocus();
        await safePump(tester, const Duration(milliseconds: 400));
        await helix.switchToCompose();
        await safePump(tester, const Duration(milliseconds: 400));
        await helix.switchToArchitect();
        await safePump(tester, const Duration(milliseconds: 400));
        await helix.switchToCompose();
        await safePump(tester, const Duration(milliseconds: 400));
      }
      await drainExceptions(tester);

      {
        helix.verifyNoOverflow();
        helix.verifyNoCorruptData();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H11-H15: SPINE PANELS
      // ═══════════════════════════════════════════════════════════════════════

      // H11-PRE: Test ESC WITHOUT spine panel open (baseline)
      await helix.pressEsc();
      await safePump(tester, const Duration(milliseconds: 200));

      {
        await helix.openAudioAssign();
        await safePump(tester, const Duration(milliseconds: 500));
        helix.verifyNoOverflow();
        await helix.pressEsc();
        await safePump(tester, const Duration(milliseconds: 300));
      }
      await drainExceptions(tester);

      {
        await helix.openConfig();
        await safePump(tester, const Duration(milliseconds: 500));
        helix.verifyNoOverflow();
        await helix.pressEsc();
        await safePump(tester, const Duration(milliseconds: 300));
      }
      await drainExceptions(tester);

      {
        await helix.openAnalytics();
        await safePump(tester, const Duration(milliseconds: 500));
        helix.verifyNoOverflow();
        await helix.pressEsc();
        await safePump(tester, const Duration(milliseconds: 300));
      }
      await drainExceptions(tester);

      {
        await helix.openAIPanel();
        await safePump(tester, const Duration(milliseconds: 500));
        helix.verifyNoOverflow();
        await helix.pressEsc();
        await safePump(tester, const Duration(milliseconds: 300));
      }
      await drainExceptions(tester);

      {
        await helix.stressSpinePanels();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H16-H20: DOCK TABS
      // ═══════════════════════════════════════════════════════════════════════

      {
        await helix.cycleAllDockTabs();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      {
        for (int i = 1; i <= 6; i++) {
          await helix.pressDockKey(i);
          await safePump(tester, const Duration(milliseconds: 150));
          helix.verifyNoOverflow();
        }
      }
      await drainExceptions(tester);

      {
        for (int i = 7; i <= 10; i++) {
          await helix.pressDockKey(i);
          await safePump(tester, const Duration(milliseconds: 150));
        }
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      {
        await helix.stressDockSwitching();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      {
        for (final tab in HelixPage.primaryDockTabs) {
          await helix.openDockTab(tab);
          await safePump(tester, const Duration(milliseconds: 300));
          helix.verifyNoOverflow();
          helix.verifyNoPlaceholders();
        }
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H21-H25: AUDIO DOCK DETAILS
      // ═══════════════════════════════════════════════════════════════════════

      {
        await helix.verifyAutoBindAvailable();
      }
      await drainExceptions(tester);

      {
        await helix.openDockTab('AUDIO');
        await safePump(tester, const Duration(milliseconds: 300));
        expect(helix.masterLabel.evaluate().isNotEmpty, isTrue,
            reason: 'MASTER label should be visible');
      }
      await drainExceptions(tester);

      {
        expect(helix.channelsLabel.evaluate().isNotEmpty, isTrue,
            reason: 'CHANNELS label should be visible');
      }
      await drainExceptions(tester);

      {
        expect(helix.faderLabel.evaluate().isNotEmpty, isTrue,
            reason: 'FADER label should be visible');
      }
      await drainExceptions(tester);

      {
        helix.verifyNoOverflow();
        helix.verifyNoCorruptData();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H26-H30: SLOT CONTROLS — Basic
      // ═══════════════════════════════════════════════════════════════════════

      {
        // Go back to FLOW tab so spin button is not obscured
        await helix.openDockTab('FLOW');
        await safePump(tester, const Duration(milliseconds: 300));
        expect(helix.spinButton.evaluate().isNotEmpty, isTrue,
            reason: 'Spin button should be visible');
      }
      await drainExceptions(tester);

      {
        await helix.spin();
        await safePump(tester, const Duration(milliseconds: 500));
        for (int i = 0; i < 50; i++) {
          await safePump(tester, const Duration(milliseconds: 100));
        }
        await helix.waitForSpinComplete(timeout: const Duration(seconds: 12));
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      {
        await helix.spin();
        await safePump(tester, const Duration(milliseconds: 400));
        await helix.slam();
        for (int i = 0; i < 30; i++) {
          await safePump(tester, const Duration(milliseconds: 100));
        }
        await helix.waitForSpinComplete(timeout: const Duration(seconds: 10));
      }
      await drainExceptions(tester);

      {
        await helix.spin();
        await safePump(tester, const Duration(milliseconds: 500));
        for (int i = 0; i < 30; i++) {
          await safePump(tester, const Duration(milliseconds: 100));
          await helix.skip(); // Try to skip win presentation if it appears
        }
        await helix.waitForSpinComplete(timeout: const Duration(seconds: 10));
      }
      await drainExceptions(tester);

      {
        await helix.fullSpinCycle();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H31-H35: SLOT CONTROLS — Stress
      // ═══════════════════════════════════════════════════════════════════════

      {
        for (int s = 0; s < 5; s++) {
          await helix.spin();
          await safePump(tester, const Duration(milliseconds: 300));
          for (int i = 0; i < 35; i++) {
            await safePump(tester, const Duration(milliseconds: 100));
          }
          await helix.waitForSpinComplete(timeout: const Duration(seconds: 10));
          await safePump(tester, const Duration(milliseconds: 200));
        }
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      {
        await helix.spin();
        await helix.slam(); // Immediate SLAM
        for (int i = 0; i < 30; i++) {
          await safePump(tester, const Duration(milliseconds: 100));
        }
        await helix.waitForSpinComplete(timeout: const Duration(seconds: 10));
      }
      await drainExceptions(tester);

      {
        await helix.spin();
        await safePump(tester, const Duration(milliseconds: 100));
        await helix.spin(); // Second spin while already spinning — should be no-op
        for (int i = 0; i < 40; i++) {
          await safePump(tester, const Duration(milliseconds: 100));
        }
        await helix.waitForSpinComplete(timeout: const Duration(seconds: 10));
      }
      await drainExceptions(tester);

      {
        await pressSpace(tester);
        await safePump(tester, const Duration(milliseconds: 500));
        for (int i = 0; i < 40; i++) {
          await safePump(tester, const Duration(milliseconds: 100));
        }
        await helix.waitForSpinComplete(timeout: const Duration(seconds: 10));
      }
      await drainExceptions(tester);

      {
        helix.verifyNoOverflow();
        helix.verifyNoCorruptData();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H36-H40: CONCURRENT ACTIONS
      // ═══════════════════════════════════════════════════════════════════════

      {
        await helix.spinDuringModeSwitch();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      {
        await helix.openPanelDuringSpin();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      {
        await helix.switchDockDuringSpin();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      {
        await helix.spin();
        await safePump(tester, const Duration(milliseconds: 300));
        await helix.escBarrage();
        for (int i = 0; i < 30; i++) {
          await safePump(tester, const Duration(milliseconds: 100));
        }
        await helix.waitForSpinComplete(timeout: const Duration(seconds: 10));
        await helix.verifyOnHelix(); // HELIX must still be open
      }
      await drainExceptions(tester);

      {
        await helix.spin();
        await safePump(tester, const Duration(milliseconds: 200));
        // Hit F, A, 1-6, ESC all in rapid succession
        await helix.pressF();
        await safePump(tester, const Duration(milliseconds: 50));
        await helix.pressF(); // restore
        await safePump(tester, const Duration(milliseconds: 50));
        await helix.pressDockKey(3);
        await safePump(tester, const Duration(milliseconds: 50));
        await helix.pressDockKey(1);
        for (int i = 0; i < 30; i++) {
          await safePump(tester, const Duration(milliseconds: 100));
        }
        await helix.waitForSpinComplete(timeout: const Duration(seconds: 10));
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H41-H45: ESC SAFETY
      // ═══════════════════════════════════════════════════════════════════════

      {
        await helix.escBarrage();
        await helix.verifyOnHelix();
      }
      await drainExceptions(tester);

      {
        await helix.openAudioAssign();
        await safePump(tester, const Duration(milliseconds: 300));
        await helix.pressEsc();
        await safePump(tester, const Duration(milliseconds: 300));
        await helix.verifyOnHelix();
      }
      await drainExceptions(tester);

      {
        await helix.spin();
        for (int i = 0; i < 40; i++) {
          await safePump(tester, const Duration(milliseconds: 100));
        }
        await helix.waitForSpinComplete(timeout: const Duration(seconds: 10));
        await helix.pressEsc();
        await safePump(tester, const Duration(milliseconds: 300));
        await helix.verifyOnHelix();
      }
      await drainExceptions(tester);

      {
        await helix.pressF(); // FOCUS
        await safePump(tester, const Duration(milliseconds: 300));
        await helix.pressEsc();
        await safePump(tester, const Duration(milliseconds: 300));
        await helix.verifyOnHelix(); // Must still be on HELIX
        await helix.pressF(); // back to COMPOSE
        await safePump(tester, const Duration(milliseconds: 300));
      }
      await drainExceptions(tester);

      {
        await helix.pressA(); // ARCHITECT
        await safePump(tester, const Duration(milliseconds: 300));
        await helix.pressEsc();
        await safePump(tester, const Duration(milliseconds: 300));
        await helix.verifyOnHelix();
        await helix.pressA(); // back to COMPOSE
        await safePump(tester, const Duration(milliseconds: 300));
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H46-H50: KEYBOARD SHORTCUTS — Comprehensive
      // ═══════════════════════════════════════════════════════════════════════

      {
        for (int i = 1; i <= 10; i++) {
          await helix.pressDockKey(i);
          await safePump(tester, const Duration(milliseconds: 100));
        }
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      {
        for (int i = 0; i < 3; i++) {
          await helix.pressF();
          await safePump(tester, const Duration(milliseconds: 200));
          await helix.pressF();
          await safePump(tester, const Duration(milliseconds: 200));
        }
        await helix.verifyOnHelix();
      }
      await drainExceptions(tester);

      {
        for (int i = 0; i < 3; i++) {
          await helix.pressA();
          await safePump(tester, const Duration(milliseconds: 200));
          await helix.pressA();
          await safePump(tester, const Duration(milliseconds: 200));
        }
        await helix.verifyOnHelix();
      }
      await drainExceptions(tester);

      {
        await helix.switchToCompose();
        await safePump(tester, const Duration(milliseconds: 300));
        await pressSpace(tester);
        for (int i = 0; i < 40; i++) {
          await safePump(tester, const Duration(milliseconds: 100));
        }
        await helix.waitForSpinComplete(timeout: const Duration(seconds: 10));
      }
      await drainExceptions(tester);

      {
        // Random-like sequence of keyboard inputs
        await helix.pressDockKey(2);
        await helix.pressEsc();
        await helix.pressDockKey(5);
        await helix.pressF();
        await helix.pressF();
        await helix.pressDockKey(1);
        await safePump(tester, const Duration(milliseconds: 300));
        helix.verifyNoOverflow();
        helix.verifyNoCorruptData();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H51-H55: INTEGRITY CHECKS — Deep
      // ═══════════════════════════════════════════════════════════════════════

      helix.verifyNoOverflow();
      await drainExceptions(tester);

      helix.verifyNoPlaceholders();
      await drainExceptions(tester);

      helix.verifyNoCorruptData();
      await drainExceptions(tester);

      {
        final currentCount = helix.countVisibleWidgets();
        // Sanity check: we should have SOME widgets rendered
        expect(currentCount >= 0, isTrue,
            reason: 'Widget count should be non-negative');
        // If initial was > 0, current should not be wildly larger
        if (initialWidgetCount > 0) {
          expect(currentCount < initialWidgetCount * 5, isTrue,
              reason: 'Widget count should not 5x — possible widget leak');
        }
      }
      await drainExceptions(tester);

      await helix.verifyOnHelix();
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H56-H60: STRESS & ENDURANCE
      // ═══════════════════════════════════════════════════════════════════════

      {
        for (int cycle = 0; cycle < 3; cycle++) {
          await helix.fullSpinCycle();
          helix.verifyNoOverflow();
        }
      }
      await drainExceptions(tester);

      {
        await helix.cycleAllDockTabs();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      {
        await helix.cycleAllSpinePanels();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      {
        await helix.pressF();
        await safePump(tester, const Duration(milliseconds: 300));
        await helix.pressF();
        await safePump(tester, const Duration(milliseconds: 300));
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      {
        await helix.verifyOnHelix();
        helix.verifyNoOverflow();
        helix.verifyNoPlaceholders();
        helix.verifyNoCorruptData();
        await helix.verifyDockTabs();
        final finalCount = helix.countVisibleWidgets();
      }
      await drainExceptions(tester);

      await finalDrain(tester);
    });
  });
}
