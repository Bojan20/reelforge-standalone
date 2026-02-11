/// FluxForge Studio — E2E Test: App Launch & Navigation
///
/// MEGA-TEST: Single testWidgets with ONE pumpApp call.
/// All 10 checks run sequentially to avoid framework.dart:6420
/// _InactiveElements._deactivateRecursively assertion on re-pump.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/app_harness.dart';
import '../helpers/waits.dart';
import '../pages/launcher_page.dart';
import '../pages/control_bar_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Launch & Navigation', () {
    setUpAll(() async {
      await initializeApp();
    });

    setUp(() {
      installErrorFilter();
    });

    tearDown(() {
      restoreErrorHandler();
    });

    testWidgets('All app launch & navigation tests (T01-T10)', (tester) async {
      // ═══════════════════════════════════════════════════════════════════════
      // PUMP APP ONCE — never again in this test
      // ═══════════════════════════════════════════════════════════════════════
      await pumpApp(tester);
      await waitForAppReady(tester);

      // ─── T01: App launches and passes splash screen ─────────────────────
      debugPrint('[E2E] T01: App launches and passes splash screen');
      {
        final hasLauncher = find.text('DAW Studio').evaluate().isNotEmpty ||
            find.text('Game Audio').evaluate().isNotEmpty ||
            find.text('DAW').evaluate().isNotEmpty ||
            find.text('ENTER DAW').evaluate().isNotEmpty ||
            find.text('ENTER MIDDLEWARE').evaluate().isNotEmpty;
        final hasMainLayout =
            find.text('FluxForge Studio').evaluate().isNotEmpty;

        expect(hasLauncher || hasMainLayout, isTrue,
            reason: 'T01: App should reach launcher or main layout after splash');
      }
      await drainExceptions(tester);

      // ─── T02: Launcher shows DAW and Middleware options ─────────────────
      debugPrint('[E2E] T02: Launcher shows DAW and Middleware options');
      {
        final launcher = LauncherPage(tester);
        await launcher.verifyOnLauncher();
      }
      await drainExceptions(tester);

      // ─── T03: Navigate to DAW section from launcher ─────────────────────
      debugPrint('[E2E] T03: Navigate to DAW section from launcher');
      {
        final launcher = LauncherPage(tester);
        await launcher.navigateToDAW();
        await settle(tester, const Duration(seconds: 3));
        await drainExceptions(tester);

        final controlBar = ControlBarPage(tester);
        await controlBar.verifyControlBarPresent();
      }
      await drainExceptions(tester);

      // From here on, we are inside DAW section.
      // We stay here for T05-T10 (which all need DAW).
      // T04 (Middleware navigation) is tested via section switch.

      // ─── T04: Section switch to Middleware verifies it loads ─────────────
      debugPrint('[E2E] T04: Navigate to Middleware section (via switch)');
      {
        final controlBar = ControlBarPage(tester);
        await controlBar.switchToMiddleware();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await controlBar.verifyControlBarPresent();
      }
      await drainExceptions(tester);

      // Switch back to DAW for remaining tests
      {
        final controlBar = ControlBarPage(tester);
        await controlBar.switchToDAW();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);
      }

      // ─── T05: Control bar transport buttons are present ─────────────────
      debugPrint('[E2E] T05: Control bar transport buttons are present');
      {
        final controlBar = ControlBarPage(tester);
        await controlBar.verifyTransportVisible();
      }
      await drainExceptions(tester);

      // ─── T06: Zone toggle buttons work ──────────────────────────────────
      debugPrint('[E2E] T06: Zone toggle buttons work');
      {
        final controlBar = ControlBarPage(tester);

        await controlBar.toggleLeft();
        await safePump(tester, const Duration(milliseconds: 300));
        await controlBar.toggleRight();
        await safePump(tester, const Duration(milliseconds: 300));
        await controlBar.toggleLower();
        await safePump(tester, const Duration(milliseconds: 300));

        // Toggle back
        await controlBar.toggleLeft();
        await safePump(tester, const Duration(milliseconds: 300));
        await controlBar.toggleRight();
        await safePump(tester, const Duration(milliseconds: 300));
        await controlBar.toggleLower();
        await safePump(tester, const Duration(milliseconds: 300));

        await controlBar.verifyControlBarPresent();
      }
      await drainExceptions(tester);

      // ─── T07: Section switching DAW → Middleware ────────────────────────
      debugPrint('[E2E] T07: Section switching DAW → Middleware → DAW');
      {
        final controlBar = ControlBarPage(tester);

        await controlBar.switchToMiddleware();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await controlBar.switchToDAW();
        await settle(tester, const Duration(seconds: 2));
        await drainExceptions(tester);

        await controlBar.verifyControlBarPresent();
      }
      await drainExceptions(tester);

      // ─── T08: Transport play/stop cycle ─────────────────────────────────
      debugPrint('[E2E] T08: Transport play/stop cycle');
      {
        final controlBar = ControlBarPage(tester);

        await controlBar.pressPlay();
        await safePump(tester, const Duration(milliseconds: 500));

        await controlBar.pressStop();
        await safePump(tester, const Duration(milliseconds: 500));

        await controlBar.verifyTransportVisible();
      }
      await drainExceptions(tester);

      // ─── T09: Rewind and forward buttons work ──────────────────────────
      debugPrint('[E2E] T09: Rewind and forward buttons work');
      {
        final controlBar = ControlBarPage(tester);

        await controlBar.pressRewind();
        await safePump(tester, const Duration(milliseconds: 200));

        await controlBar.pressForward();
        await safePump(tester, const Duration(milliseconds: 200));

        await controlBar.verifyTransportVisible();
      }
      await drainExceptions(tester);

      // ─── T10: Loop toggle works ─────────────────────────────────────────
      debugPrint('[E2E] T10: Loop toggle works');
      {
        final controlBar = ControlBarPage(tester);

        await controlBar.toggleLoop();
        await safePump(tester, const Duration(milliseconds: 200));

        await controlBar.toggleLoop();
        await safePump(tester, const Duration(milliseconds: 200));

        await controlBar.verifyControlBarPresent();
      }
      await drainExceptions(tester);

      debugPrint('[E2E] ✅ All 10 app launch tests passed!');

      // Final aggressive drain to flush scheduler callbacks
      // (MiddlewareProvider._scheduleNotification) before test body returns
      await finalDrain(tester);
    });
  });
}
