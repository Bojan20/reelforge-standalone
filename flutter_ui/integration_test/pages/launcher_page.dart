/// FluxForge Studio — Launcher Page Object Model
///
/// Encapsulates all interactions with the Launcher screen.
/// Provides semantic methods for mode selection and navigation.

import 'package:flutter_test/flutter_test.dart';
import '../helpers/app_harness.dart';
import '../helpers/waits.dart';
import '../helpers/gestures.dart';

/// Page Object for the initial Launcher screen (DAW / SlotLab selection).
class LauncherPage {
  final WidgetTester tester;
  const LauncherPage(this.tester);

  // ─── Finders ───────────────────────────────────────────────────────────────

  /// Primary: "ENTER DAW" / "ENTER SLOTLAB" buttons
  Finder get enterDawButton => find.text('ENTER DAW');
  Finder get enterSlotLabButton => find.text('ENTER SLOTLAB');

  /// Panel titles
  Finder get dawPanelTitle => find.text('DAW');
  Finder get slotLabPanelTitle => find.text('SLOTLAB');

  /// Subtitles
  Finder get dawSubtitle => find.text('Digital Audio Workstation');
  Finder get slotLabSubtitle => find.text('Slot Game Audio Studio');

  /// Branding
  Finder get studioTitle => find.text('FluxForge Studio');

  // ─── Assertions ────────────────────────────────────────────────────────────

  /// Verify we're on the launcher screen
  Future<void> verifyOnLauncher() async {
    final hasEnterDaw = enterDawButton.evaluate().isNotEmpty;
    final hasEnterSlotLab = enterSlotLabButton.evaluate().isNotEmpty;
    final hasDawTitle = dawPanelTitle.evaluate().isNotEmpty;
    final hasSlotLabTitle = slotLabPanelTitle.evaluate().isNotEmpty;
    expect(hasEnterDaw || hasEnterSlotLab || hasDawTitle || hasSlotLabTitle,
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
    if (enterDawButton.evaluate().isNotEmpty) {
      await tapAndSettle(tester, enterDawButton);
      return;
    }
    if (dawPanelTitle.evaluate().isNotEmpty) {
      await tapAndSettle(tester, dawPanelTitle.first);
      return;
    }
    fail('Could not find DAW selection on launcher');
  }

  /// Select SlotLab mode from the launcher
  Future<void> selectSlotLab() async {
    if (enterSlotLabButton.evaluate().isNotEmpty) {
      await tapAndSettle(tester, enterSlotLabButton);
      return;
    }
    if (slotLabPanelTitle.evaluate().isNotEmpty) {
      await tapAndSettle(tester, slotLabPanelTitle.first);
      return;
    }
    fail('Could not find SlotLab selection on launcher');
  }

  // ─── Hub Screen Finders ────────────────────────────────────────────────────

  Finder get createProjectButton => find.textContaining('Create');
  Finder get quickStartButton => find.textContaining('Quick Start');
  Finder get createNewProjectLabel => find.text('CREATE NEW PROJECT');

  /// Navigate through Hub screen — tap "Create Empty Project" or similar
  Future<void> createNewProject() async {
    await settle(tester, const Duration(seconds: 1));

    if (createProjectButton.evaluate().isNotEmpty) {
      await tapAndSettle(tester, createProjectButton.first);
      await settle(tester, const Duration(seconds: 2));
      return;
    }
    if (quickStartButton.evaluate().isNotEmpty) {
      await tapAndSettle(tester, quickStartButton.first);
      await settle(tester, const Duration(seconds: 2));
      return;
    }
  }

  /// Full navigation: select DAW mode → Hub → Create Project → MainLayout
  Future<void> navigateToDAW() async {
    await selectDAW();
    await settle(tester, const Duration(seconds: 2));
    await drainExceptions(tester);
    await createNewProject();
    await settle(tester, const Duration(seconds: 3));
    await drainExceptions(tester);
  }

  /// Full navigation: select SlotLab mode → SlotLabLayout
  Future<void> navigateToSlotLab() async {
    await selectSlotLab();
    await settle(tester, const Duration(seconds: 2));
    await drainExceptions(tester);
    await createNewProject();
    await settle(tester, const Duration(seconds: 3));
    await drainExceptions(tester);
  }
}
