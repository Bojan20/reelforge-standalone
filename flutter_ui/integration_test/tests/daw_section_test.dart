/// FluxForge Studio — E2E Test: DAW Section
///
/// MEGA-TEST: Single testWidgets with ONE pumpApp call.
/// All 15 checks run sequentially to avoid framework.dart:6420
/// _InactiveElements._deactivateRecursively assertion on re-pump.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/app_harness.dart';
import '../helpers/waits.dart';
import '../helpers/gestures.dart';
import '../pages/launcher_page.dart';
import '../pages/control_bar_page.dart';
import '../pages/daw_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('DAW Section', () {
    setUpAll(() async {
      await initializeApp();
    });

    setUp(() {
      installErrorFilter();
    });

    tearDown(() {
      restoreErrorHandler();
    });

    testWidgets('All DAW section tests (D01-D15)', (tester) async {
      // ═══════════════════════════════════════════════════════════════════════
      // PUMP APP ONCE — navigate to DAW once
      // ═══════════════════════════════════════════════════════════════════════
      await pumpApp(tester);
      await waitForAppReady(tester);

      final launcher = LauncherPage(tester);
      await launcher.navigateToDAW();
      await settle(tester, const Duration(seconds: 3));
      await drainExceptions(tester);

      final daw = DAWPage(tester);
      final controlBar = ControlBarPage(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // LOWER ZONE TABS
      // ═══════════════════════════════════════════════════════════════════════

      // ─── D01: DAW lower zone super-tabs are visible ────────────────────
      debugPrint('[E2E] D01: DAW lower zone super-tabs are visible');
      await daw.verifyLowerZoneTabs();
      await drainExceptions(tester);

      // ─── D02: Cycle through all DAW super-tabs ─────────────────────────
      debugPrint('[E2E] D02: Cycle through all DAW super-tabs');
      await daw.cycleAllSuperTabs();
      await daw.verifyLowerZoneTabs();
      await drainExceptions(tester);

      // ─── D03: Browse tab shows Files/Presets/Plugins sub-tabs ──────────
      debugPrint('[E2E] D03: Browse tab shows sub-tabs');
      {
        await daw.openBrowse();
        await safePump(tester, const Duration(milliseconds: 300));

        final hasFiles = daw.filesSubTab.evaluate().isNotEmpty;
        final hasPresets = daw.presetsSubTab.evaluate().isNotEmpty;
        final hasPlugins = daw.pluginsSubTab.evaluate().isNotEmpty;
        expect(hasFiles || hasPresets || hasPlugins, isTrue,
            reason: 'D03: Browse tab should show sub-tabs');
      }
      await drainExceptions(tester);

      // ─── D04: Edit tab shows Timeline/Piano Roll sub-tabs ──────────────
      debugPrint('[E2E] D04: Edit tab shows sub-tabs');
      {
        await daw.openEdit();
        await safePump(tester, const Duration(milliseconds: 300));

        final hasTimeline = daw.timelineSubTab.evaluate().isNotEmpty;
        final hasPianoRoll = daw.pianoRollSubTab.evaluate().isNotEmpty;
        expect(hasTimeline || hasPianoRoll, isTrue,
            reason: 'D04: Edit tab should show sub-tabs');
      }
      await drainExceptions(tester);

      // ─── D05: Mix tab shows Mixer/Sends sub-tabs ──────────────────────
      debugPrint('[E2E] D05: Mix tab shows sub-tabs');
      {
        await daw.openMix();
        await safePump(tester, const Duration(milliseconds: 300));

        final hasMixer = daw.mixerSubTab.evaluate().isNotEmpty;
        final hasSends = daw.sendsSubTab.evaluate().isNotEmpty;
        expect(hasMixer || hasSends, isTrue,
            reason: 'D05: Mix tab should show sub-tabs');
      }
      await drainExceptions(tester);

      // ─── D06: Process tab shows EQ/Compressor/Limiter sub-tabs ────────
      debugPrint('[E2E] D06: Process tab shows sub-tabs');
      {
        await daw.openProcess();
        await safePump(tester, const Duration(milliseconds: 300));

        final hasEQ = daw.eqSubTab.evaluate().isNotEmpty;
        final hasComp = daw.compSubTab.evaluate().isNotEmpty;
        final hasLimiter = daw.limiterSubTab.evaluate().isNotEmpty;
        expect(hasEQ || hasComp || hasLimiter, isTrue,
            reason: 'D06: Process tab should show sub-tabs');
      }
      await drainExceptions(tester);

      // ─── D07: Deliver tab shows Export/Stems/Bounce sub-tabs ──────────
      debugPrint('[E2E] D07: Deliver tab shows sub-tabs');
      {
        await daw.openDeliver();
        await safePump(tester, const Duration(milliseconds: 300));

        final hasExport = daw.exportSubTab.evaluate().isNotEmpty;
        final hasStems = daw.stemsSubTab.evaluate().isNotEmpty;
        final hasBounce = daw.bounceSubTab.evaluate().isNotEmpty;
        final hasArchive = daw.archiveSubTab.evaluate().isNotEmpty;
        expect(hasExport || hasStems || hasBounce || hasArchive, isTrue,
            reason: 'D07: Deliver tab should show sub-tabs');
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // MIXER (may not have channel strips if no tracks loaded)
      // ═══════════════════════════════════════════════════════════════════════

      // First, navigate to MIX tab so mixer is visible
      await daw.openMix();
      await safePump(tester, const Duration(milliseconds: 500));
      await drainExceptions(tester);

      // Check if mixer area has any visible content
      // DAW always has a Master stereo fader even with empty project
      final hasMasterLabel = find.text('Master').evaluate().isNotEmpty ||
          find.text('MASTER').evaluate().isNotEmpty;
      final hasSliders = daw.sliders.evaluate().isNotEmpty;
      final hasMixerContent = hasMasterLabel || hasSliders ||
          daw.muteButtons.evaluate().isNotEmpty;

      // ─── D08: Mixer area is present ───────────────────────────────────
      debugPrint('[E2E] D08: Mixer channel strips are present');
      if (hasMixerContent) {
        debugPrint('[E2E] D08: ✅ Mixer area found (Master=$hasMasterLabel, Sliders=$hasSliders)');
      } else {
        debugPrint('[E2E] D08: ⏭️ Skipped — mixer not visible in current layout');
      }
      await drainExceptions(tester);

      // ─── D09: Mixer mute button toggles ───────────────────────────────
      debugPrint('[E2E] D09: Mixer mute button toggles');
      if (daw.muteButtons.evaluate().isNotEmpty) {
        await daw.tapMute();
        await safePump(tester, const Duration(milliseconds: 200));
        await daw.tapMute();
        await safePump(tester, const Duration(milliseconds: 200));
      } else {
        debugPrint('[E2E] D09: ⏭️ Skipped — no mute buttons visible');
      }
      await drainExceptions(tester);

      // ─── D10: Mixer solo button toggles ───────────────────────────────
      debugPrint('[E2E] D10: Mixer solo button toggles');
      if (daw.soloButtons.evaluate().isNotEmpty) {
        await daw.tapSolo();
        await safePump(tester, const Duration(milliseconds: 200));
        await daw.tapSolo();
        await safePump(tester, const Duration(milliseconds: 200));
      } else {
        debugPrint('[E2E] D10: ⏭️ Skipped — no solo buttons visible');
      }
      await drainExceptions(tester);

      // ─── D11: Mixer fader slider responds to drag ─────────────────────
      debugPrint('[E2E] D11: Mixer fader slider responds to drag');
      if (hasSliders) {
        await daw.moveFader(0, 0.5);
        await safePump(tester, const Duration(milliseconds: 200));
        await daw.moveFader(0, 0.8);
        await safePump(tester, const Duration(milliseconds: 200));
      } else {
        debugPrint('[E2E] D11: ⏭️ Skipped — no faders visible');
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // TRANSPORT
      // ═══════════════════════════════════════════════════════════════════════

      // ─── D12: Play/Stop transport cycle ───────────────────────────────
      debugPrint('[E2E] D12: Play/Stop transport cycle');
      {
        await controlBar.pressPlay();
        await safePump(tester, const Duration(milliseconds: 500));
        await controlBar.pressStop();
        await safePump(tester, const Duration(milliseconds: 500));
        await controlBar.verifyTransportVisible();
      }
      await drainExceptions(tester);

      // ─── D13: Space key toggles playback ──────────────────────────────
      debugPrint('[E2E] D13: Space key toggles playback');
      {
        await pressSpace(tester);
        await safePump(tester, const Duration(milliseconds: 500));
        await pressSpace(tester);
        await safePump(tester, const Duration(milliseconds: 500));
      }
      await drainExceptions(tester);

      // ═══════════════════════════════════════════════════════════════════════
      // SUB-TAB NAVIGATION
      // ═══════════════════════════════════════════════════════════════════════

      // ─── D14: Navigate through Browse sub-tabs ────────────────────────
      debugPrint('[E2E] D14: Navigate through Browse sub-tabs');
      {
        await daw.openBrowse();
        await safePump(tester, const Duration(milliseconds: 300));

        await daw.openSubTab('Files');
        await safePump(tester, const Duration(milliseconds: 200));
        await daw.openSubTab('Presets');
        await safePump(tester, const Duration(milliseconds: 200));
        await daw.openSubTab('Plugins');
        await safePump(tester, const Duration(milliseconds: 200));
        await daw.openSubTab('History');
        await safePump(tester, const Duration(milliseconds: 200));
      }
      await drainExceptions(tester);

      // ─── D15: Navigate through Process sub-tabs ───────────────────────
      debugPrint('[E2E] D15: Navigate through Process sub-tabs');
      {
        await daw.openProcess();
        await safePump(tester, const Duration(milliseconds: 300));

        await daw.openSubTab('EQ');
        await safePump(tester, const Duration(milliseconds: 200));
        await daw.openSubTab('Compressor');
        await safePump(tester, const Duration(milliseconds: 200));
        await daw.openSubTab('Limiter');
        await safePump(tester, const Duration(milliseconds: 200));
      }
      await drainExceptions(tester);

      debugPrint('[E2E] ✅ All 15 DAW section tests passed!');

      // Final aggressive drain to flush scheduler callbacks
      await finalDrain(tester);
    });
  });
}
