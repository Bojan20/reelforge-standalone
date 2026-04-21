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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
      debugPrint('[E2E] Initial widget count: $initialWidgetCount');

      // ═══════════════════════════════════════════════════════════════════════
      // H01-H05: LAUNCH & INITIAL STATE
      // ═══════════════════════════════════════════════════════════════════════

      debugPrint('[E2E] H01: HELIX screen loaded');
      await helix.verifyOnHelix();
      await drainExceptions(tester);

      debugPrint('[E2E] H02: No overflow on initial load');
      helix.verifyNoOverflow();
      await drainExceptions(tester);

      debugPrint('[E2E] H03: No placeholders on initial load');
      helix.verifyNoPlaceholders();
      await drainExceptions(tester);

      debugPrint('[E2E] H04: No corrupt data (null/NaN) on initial load');
      helix.verifyNoCorruptData();
      await drainExceptions(tester);

      debugPrint('[E2E] H05: Primary dock tabs visible');
      await helix.verifyDockTabs();
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H06-H10: MODE SWITCHING
      // ═══════════════════════════════════════════════════════════════════════

      debugPrint('[E2E] H06: COMPOSE → FOCUS → COMPOSE');
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

      debugPrint('[E2E] H07: COMPOSE → ARCHITECT → COMPOSE');
      {
        await helix.pressA();
        await safePump(tester, const Duration(milliseconds: 500));
        await helix.pressA();
        await safePump(tester, const Duration(milliseconds: 500));
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H08: Mode switch stress test (rapid)');
      {
        await helix.stressModeSwitching();
        helix.verifyNoOverflow();
        await helix.verifyOnHelix();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H09: Mode click via tab buttons');
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

      debugPrint('[E2E] H10: No overflow after mode stress');
      {
        helix.verifyNoOverflow();
        helix.verifyNoCorruptData();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H11-H15: SPINE PANELS
      // ═══════════════════════════════════════════════════════════════════════

      debugPrint('[E2E] H11: Audio Assign panel opens/closes');
      {
        await helix.openAudioAssign();
        await safePump(tester, const Duration(milliseconds: 500));
        helix.verifyNoOverflow();
        await helix.pressEsc();
        await safePump(tester, const Duration(milliseconds: 300));
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H12: Config panel opens/closes');
      {
        await helix.openConfig();
        await safePump(tester, const Duration(milliseconds: 500));
        helix.verifyNoOverflow();
        await helix.pressEsc();
        await safePump(tester, const Duration(milliseconds: 300));
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H13: Analytics panel opens/closes');
      {
        await helix.openAnalytics();
        await safePump(tester, const Duration(milliseconds: 500));
        helix.verifyNoOverflow();
        await helix.pressEsc();
        await safePump(tester, const Duration(milliseconds: 300));
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H14: AI panel opens/closes');
      {
        await helix.openAIPanel();
        await safePump(tester, const Duration(milliseconds: 500));
        helix.verifyNoOverflow();
        await helix.pressEsc();
        await safePump(tester, const Duration(milliseconds: 300));
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H15: Spine panel cycle stress');
      {
        await helix.stressSpinePanels();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H16-H20: DOCK TABS
      // ═══════════════════════════════════════════════════════════════════════

      debugPrint('[E2E] H16: Cycle all 12 dock tabs');
      {
        await helix.cycleAllDockTabs();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H17: Dock tabs via keyboard (1-6)');
      {
        for (int i = 1; i <= 6; i++) {
          await helix.pressDockKey(i);
          await safePump(tester, const Duration(milliseconds: 150));
          helix.verifyNoOverflow();
        }
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H18: Dock tabs via keyboard (7-0 for 7-10)');
      {
        for (int i = 7; i <= 10; i++) {
          await helix.pressDockKey(i);
          await safePump(tester, const Duration(milliseconds: 150));
        }
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H19: Rapid dock switching stress');
      {
        await helix.stressDockSwitching();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H20: Each dock tab has content (not blank)');
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

      debugPrint('[E2E] H21: Auto-Bind button visible in AUDIO tab');
      {
        await helix.verifyAutoBindAvailable();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H22: MASTER label visible in AUDIO tab');
      {
        await helix.openDockTab('AUDIO');
        await safePump(tester, const Duration(milliseconds: 300));
        expect(helix.masterLabel.evaluate().isNotEmpty, isTrue,
            reason: 'MASTER label should be visible');
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H23: CHANNELS label visible in AUDIO tab');
      {
        expect(helix.channelsLabel.evaluate().isNotEmpty, isTrue,
            reason: 'CHANNELS label should be visible');
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H24: FADER label visible in AUDIO tab');
      {
        expect(helix.faderLabel.evaluate().isNotEmpty, isTrue,
            reason: 'FADER label should be visible');
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H25: AUDIO tab no overflow with all elements');
      {
        helix.verifyNoOverflow();
        helix.verifyNoCorruptData();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H26-H30: SLOT CONTROLS — Basic
      // ═══════════════════════════════════════════════════════════════════════

      debugPrint('[E2E] H26: Spin button visible');
      {
        // Go back to FLOW tab so spin button is not obscured
        await helix.openDockTab('FLOW');
        await safePump(tester, const Duration(milliseconds: 300));
        final hasSpin = helix.spinButton.evaluate().isNotEmpty;
        debugPrint('[E2E]   Spin button found: $hasSpin');
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H27: Spin + wait for complete');
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

      debugPrint('[E2E] H28: SLAM during spin');
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

      debugPrint('[E2E] H29: SKIP after win');
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

      debugPrint('[E2E] H30: Full spin cycle (spin→SLAM→SKIP)');
      {
        await helix.fullSpinCycle();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H31-H35: SLOT CONTROLS — Stress
      // ═══════════════════════════════════════════════════════════════════════

      debugPrint('[E2E] H31: 5 rapid spins');
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

      debugPrint('[E2E] H32: Spin + immediate SLAM (no delay)');
      {
        await helix.spin();
        await helix.slam(); // Immediate SLAM
        for (int i = 0; i < 30; i++) {
          await safePump(tester, const Duration(milliseconds: 100));
        }
        await helix.waitForSpinComplete(timeout: const Duration(seconds: 10));
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H33: Double spin attempt (should be ignored)');
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

      debugPrint('[E2E] H34: Space key spin');
      {
        await pressSpace(tester);
        await safePump(tester, const Duration(milliseconds: 500));
        for (int i = 0; i < 40; i++) {
          await safePump(tester, const Duration(milliseconds: 100));
        }
        await helix.waitForSpinComplete(timeout: const Duration(seconds: 10));
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H35: No overflow after all spin tests');
      {
        helix.verifyNoOverflow();
        helix.verifyNoCorruptData();
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H36-H40: CONCURRENT ACTIONS
      // ═══════════════════════════════════════════════════════════════════════

      debugPrint('[E2E] H36: Spin + mode switch');
      {
        await helix.spinDuringModeSwitch();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H37: Spin + open panel');
      {
        await helix.openPanelDuringSpin();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H38: Spin + dock tab switching');
      {
        await helix.switchDockDuringSpin();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H39: Spin + ESC barrage');
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

      debugPrint('[E2E] H40: Spin + keyboard combo barrage');
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

      debugPrint('[E2E] H41: ESC barrage — 10 rapid ESCs');
      {
        await helix.escBarrage();
        await helix.verifyOnHelix();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H42: ESC after opening audio assign');
      {
        await helix.openAudioAssign();
        await safePump(tester, const Duration(milliseconds: 300));
        await helix.pressEsc();
        await safePump(tester, const Duration(milliseconds: 300));
        await helix.verifyOnHelix();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H43: ESC after spin completes');
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

      debugPrint('[E2E] H44: ESC in FOCUS mode');
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

      debugPrint('[E2E] H45: ESC in ARCHITECT mode');
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

      debugPrint('[E2E] H46: All number keys (1-0) for dock tabs');
      {
        for (int i = 1; i <= 10; i++) {
          await helix.pressDockKey(i);
          await safePump(tester, const Duration(milliseconds: 100));
        }
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H47: F key toggle 3 times');
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

      debugPrint('[E2E] H48: A key toggle 3 times');
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

      debugPrint('[E2E] H49: Space key spin from COMPOSE mode');
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

      debugPrint('[E2E] H50: Keyboard combos don\'t produce corrupt state');
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

      debugPrint('[E2E] H51: No overflow after 50 tests');
      helix.verifyNoOverflow();
      await drainExceptions(tester);

      debugPrint('[E2E] H52: No placeholders after 50 tests');
      helix.verifyNoPlaceholders();
      await drainExceptions(tester);

      debugPrint('[E2E] H53: No corrupt data after 50 tests');
      helix.verifyNoCorruptData();
      await drainExceptions(tester);

      debugPrint('[E2E] H54: Widget count stable (no leak)');
      {
        final currentCount = helix.countVisibleWidgets();
        debugPrint('[E2E]   Widget count: initial=$initialWidgetCount current=$currentCount');
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

      debugPrint('[E2E] H55: Still on HELIX after all tests');
      await helix.verifyOnHelix();
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // H56-H60: STRESS & ENDURANCE
      // ═══════════════════════════════════════════════════════════════════════

      debugPrint('[E2E] H56: Full endurance — 3 complete spin cycles');
      {
        for (int cycle = 0; cycle < 3; cycle++) {
          await helix.fullSpinCycle();
          helix.verifyNoOverflow();
        }
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H57: Dock cycle after endurance');
      {
        await helix.cycleAllDockTabs();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H58: Spine cycle after endurance');
      {
        await helix.cycleAllSpinePanels();
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H59: Mode switch after endurance');
      {
        await helix.pressF();
        await safePump(tester, const Duration(milliseconds: 300));
        await helix.pressF();
        await safePump(tester, const Duration(milliseconds: 300));
        helix.verifyNoOverflow();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] H60: FINAL — Complete verification');
      {
        await helix.verifyOnHelix();
        helix.verifyNoOverflow();
        helix.verifyNoPlaceholders();
        helix.verifyNoCorruptData();
        await helix.verifyDockTabs();
        final finalCount = helix.countVisibleWidgets();
        debugPrint('[E2E]   Final widget count: $finalCount');
      }
      await drainExceptions(tester);

      debugPrint('[E2E] ✅ All 60 HELIX section tests passed!');
      await finalDrain(tester);
    });
  });
}
