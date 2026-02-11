/// FluxForge Studio — Launcher Page Object Model
///
/// Encapsulates all interactions with the Launcher screen.
/// Provides semantic methods for mode selection and navigation.

import 'package:flutter_test/flutter_test.dart';
import '../helpers/app_harness.dart';
import '../helpers/waits.dart';
import '../helpers/gestures.dart';

/// Page Object for the initial Launcher screen (DAW / Middleware selection).
class LauncherPage {
  final WidgetTester tester;
  const LauncherPage(this.tester);

  // ─── Finders ───────────────────────────────────────────────────────────────

  /// Primary: "ENTER DAW" / "ENTER MIDDLEWARE" buttons (launcher_screen.dart:791)
  Finder get enterDawButton => find.text('ENTER DAW');
  Finder get enterMiddlewareButton => find.text('ENTER MIDDLEWARE');

  /// Panel titles: "DAW" and "MIDDLEWARE" (launcher_screen.dart:285,312)
  Finder get dawPanelTitle => find.text('DAW');
  Finder get middlewarePanelTitle => find.text('MIDDLEWARE');

  /// Subtitles
  Finder get dawSubtitle => find.text('Digital Audio Workstation');
  Finder get middlewareSubtitle => find.text('Game Audio Authoring');

  /// Branding
  Finder get studioTitle => find.text('FluxForge Studio');

  // ─── Assertions ────────────────────────────────────────────────────────────

  /// Verify we're on the launcher screen
  Future<void> verifyOnLauncher() async {
    // Launcher shows split panels with "ENTER DAW" / "ENTER MIDDLEWARE"
    // or panel titles "DAW" / "MIDDLEWARE"
    final hasEnterDaw = enterDawButton.evaluate().isNotEmpty;
    final hasEnterMiddleware = enterMiddlewareButton.evaluate().isNotEmpty;
    final hasDawTitle = dawPanelTitle.evaluate().isNotEmpty;
    final hasMiddlewareTitle = middlewarePanelTitle.evaluate().isNotEmpty;
    expect(hasEnterDaw || hasEnterMiddleware || hasDawTitle || hasMiddlewareTitle,
        isTrue,
        reason: 'Expected to be on the Launcher screen');
  }

  /// Verify FluxForge branding is visible
  Future<void> verifyBranding() async {
    await waitForWidget(tester, studioTitle,
        timeout: const Duration(seconds: 15),
        description: 'FluxForge Studio title');
  }

  // ─── Actions ───────────────────────────────────────────────────────────────

  /// Select DAW mode from the launcher
  Future<void> selectDAW() async {
    // Primary: "ENTER DAW" button
    if (enterDawButton.evaluate().isNotEmpty) {
      await tapAndSettle(tester, enterDawButton);
      return;
    }
    // Fallback: tap on "DAW" panel title (entire panel is clickable)
    if (dawPanelTitle.evaluate().isNotEmpty) {
      await tapAndSettle(tester, dawPanelTitle.first);
      return;
    }
    fail('Could not find DAW selection on launcher');
  }

  /// Select Middleware mode from the launcher
  Future<void> selectMiddleware() async {
    // Primary: "ENTER MIDDLEWARE" button
    if (enterMiddlewareButton.evaluate().isNotEmpty) {
      await tapAndSettle(tester, enterMiddlewareButton);
      return;
    }
    // Fallback: tap on "MIDDLEWARE" panel title
    if (middlewarePanelTitle.evaluate().isNotEmpty) {
      await tapAndSettle(tester, middlewarePanelTitle.first);
      return;
    }
    fail('Could not find Middleware selection on launcher');
  }

  // ─── Hub Screen Finders ────────────────────────────────────────────────────
  // After launcher selection, a Hub screen appears (DawHubScreen / MiddlewareHubScreen)
  // The create button text is "Create ${template.name} Project" — default: "Create Empty Project"

  Finder get createProjectButton => find.textContaining('Create');
  Finder get quickStartButton => find.textContaining('Quick Start');
  Finder get createNewProjectLabel => find.text('CREATE NEW PROJECT');

  /// Navigate through Hub screen — tap "Create Empty Project" or similar
  Future<void> createNewProject() async {
    // Wait for hub screen entry animation
    await settle(tester, const Duration(seconds: 1));

    // Primary: "Create Empty Project" button (DAW hub default template)
    if (createProjectButton.evaluate().isNotEmpty) {
      await tapAndSettle(tester, createProjectButton.first);
      await settle(tester, const Duration(seconds: 2));
      return;
    }
    // Fallback: Quick Start (Middleware hub)
    if (quickStartButton.evaluate().isNotEmpty) {
      await tapAndSettle(tester, quickStartButton.first);
      await settle(tester, const Duration(seconds: 2));
      return;
    }
    // If no hub screen, we may already be on the main layout
  }

  /// Full navigation: select DAW mode → Hub → Create Project → MainLayout
  Future<void> navigateToDAW() async {
    await selectDAW();
    // Wait for launcher exit animation (600ms) + hub screen load
    await settle(tester, const Duration(seconds: 2));
    await drainExceptions(tester);
    await createNewProject();
    // Wait for main layout to fully load after project creation
    await settle(tester, const Duration(seconds: 3));
    // Drain async framework errors from widget tree rebuild
    await drainExceptions(tester);
  }

  /// Full navigation: select Middleware mode → Hub → Create Project → MiddlewareLayout
  Future<void> navigateToMiddleware() async {
    await selectMiddleware();
    // Wait for launcher exit animation (600ms) + hub screen load
    await settle(tester, const Duration(seconds: 2));
    await drainExceptions(tester);
    await createNewProject();
    // Wait for middleware layout to fully load
    await settle(tester, const Duration(seconds: 3));
    // Drain async framework errors from widget tree rebuild
    await drainExceptions(tester);
  }
}
