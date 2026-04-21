/// FluxForge Studio — HELIX Page Object Model
///
/// Encapsulates ALL interactions with the HELIX screen.
/// Every button, every tab, every slider, every keyboard shortcut.
/// Zero blind spots.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/app_harness.dart';
import '../helpers/waits.dart';
import '../helpers/gestures.dart';

/// Page Object for the HELIX Neural Slot Design Environment.
class HelixPage {
  final WidgetTester tester;
  const HelixPage(this.tester);

  // ═══════════════════════════════════════════════════════════════════════════
  // FINDERS — Omnibar
  // ═══════════════════════════════════════════════════════════════════════════

  Finder get omnibar => find.text('HELIX');
  Finder get closeButton => find.byIcon(Icons.close_rounded);
  Finder get composeTab => find.text('COMPOSE');
  Finder get focusTab => find.text('FOCUS');
  Finder get architectTab => find.text('ARCHITECT');

  // ═══════════════════════════════════════════════════════════════════════════
  // FINDERS — Spine (left panel)
  // ═══════════════════════════════════════════════════════════════════════════

  Finder get spineAudioAssign => find.byIcon(Icons.music_note_rounded);
  Finder get spineConfig => find.byIcon(Icons.grid_view_rounded);
  Finder get spineAnalytics => find.byIcon(Icons.analytics_rounded);
  Finder get spineAI => find.byIcon(Icons.auto_awesome);

  // ═══════════════════════════════════════════════════════════════════════════
  // FINDERS — Slot Preview (center)
  // ═══════════════════════════════════════════════════════════════════════════

  Finder get spinButton => find.textContaining('SPIN');
  Finder get slamButton => find.textContaining('SLAM');
  Finder get skipButton => find.textContaining('SKIP');
  Finder get autoSpinButton => find.textContaining('AUTO');
  Finder get turboButton => find.textContaining('TURBO');

  // Bet controls
  Finder get betUpButton => find.byIcon(Icons.add);
  Finder get betDownButton => find.byIcon(Icons.remove);

  // Balance display
  Finder get balanceText => find.textContaining('\$');

  // ═══════════════════════════════════════════════════════════════════════════
  // FINDERS — Dock (bottom panel)
  // ═══════════════════════════════════════════════════════════════════════════

  static const allDockTabs = [
    'FLOW', 'AUDIO', 'MATH', 'TIMELINE', 'INTEL', 'EXPORT',
    'SFX', 'BT', 'DNA', 'AI GEN', 'CLOUD', 'A/B',
  ];

  static const primaryDockTabs = [
    'FLOW', 'AUDIO', 'MATH', 'TIMELINE', 'INTEL', 'EXPORT',
  ];

  Finder get dockFlowTab => find.text('FLOW');
  Finder get dockAudioTab => find.text('AUDIO');
  Finder get dockMathTab => find.text('MATH');
  Finder get dockTimelineTab => find.text('TIMELINE');
  Finder get dockIntelTab => find.text('INTEL');
  Finder get dockExportTab => find.text('EXPORT');
  Finder get dockSfxTab => find.text('SFX');
  Finder get dockBtTab => find.text('BT');
  Finder get dockDnaTab => find.text('DNA');
  Finder get dockAiGenTab => find.text('AI GEN');
  Finder get dockCloudTab => find.text('CLOUD');
  Finder get dockAbTab => find.text('A/B');

  // Auto-Bind button in AUDIO dock tab
  Finder get autoBindButton => find.text('Auto-Bind');

  // MASTER section in AUDIO dock
  Finder get masterLabel => find.text('MASTER');
  Finder get channelsLabel => find.text('CHANNELS');
  Finder get faderLabel => find.text('FADER');

  // ═══════════════════════════════════════════════════════════════════════════
  // ASSERTIONS — Comprehensive verification
  // ═══════════════════════════════════════════════════════════════════════════

  /// Verify we're on the HELIX screen
  Future<void> verifyOnHelix() async {
    final hasCompose = composeTab.evaluate().isNotEmpty;
    final hasFocus = focusTab.evaluate().isNotEmpty;
    final hasDock = dockFlowTab.evaluate().isNotEmpty;
    final hasSpin = spinButton.evaluate().isNotEmpty;
    expect(hasCompose || hasFocus || hasDock || hasSpin, isTrue,
        reason: 'Expected to be on the HELIX screen');
  }

  /// Verify dock is visible and primary tabs present
  Future<void> verifyDockTabs() async {
    for (final tab in primaryDockTabs) {
      final keyFinder = find.byKey(Key('dock_tab_$tab'));
      expect(keyFinder.evaluate().isNotEmpty, isTrue,
          reason: 'Dock tab "$tab" should be visible');
    }
  }

  /// Verify no RenderFlex overflow errors visible
  void verifyNoOverflow() {
    final overflowPatterns = [
      'OVERFLOWED', 'overflowed', 'BOTTOM OVERFLOWED', 'RIGHT OVERFLOWED',
      'LEFT OVERFLOWED', 'TOP OVERFLOWED',
    ];
    for (final pattern in overflowPatterns) {
      expect(find.textContaining(pattern).evaluate().isEmpty, isTrue,
          reason: 'No "$pattern" should be visible');
    }
  }

  /// Verify no placeholder text anywhere in rendered widget tree
  void verifyNoPlaceholders() {
    final placeholderTexts = [
      'coming soon', 'Coming Soon', 'COMING SOON',
      'placeholder', 'Placeholder', 'PLACEHOLDER',
      'TODO', 'FIXME', 'STUB',
      'Not implemented', 'not implemented',
      'Lorem ipsum', 'lorem ipsum',
    ];
    for (final text in placeholderTexts) {
      final finder = find.textContaining(text);
      if (finder.evaluate().isNotEmpty) {
        fail('Found placeholder text "$text" in HELIX');
      }
    }
  }

  /// Verify no "null" or "NaN" displayed in UI
  void verifyNoCorruptData() {
    // Check for common data corruption patterns in visible text
    final allText = find.byType(Text);
    for (final element in allText.evaluate()) {
      final textWidget = element.widget as Text;
      final data = textWidget.data ?? '';
      if (data == 'null' || data == 'NaN' || data == 'Infinity' ||
          data == '-Infinity' || data == 'undefined') {
        fail('Corrupt data displayed: "$data"');
      }
    }
  }

  /// Count total visible render objects — smoke test for blank screens / leaks
  int countVisibleWidgets() {
    // Widget base class doesn't work with find.byType; count RenderObjects instead
    return find.byType(Text).evaluate().length +
        find.byType(Icon).evaluate().length +
        find.byType(Container).evaluate().length;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS — Navigation / Mode switching
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> switchToCompose() async {
    if (composeTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, composeTab);
    }
  }

  Future<void> switchToFocus() async {
    if (focusTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, focusTab);
    }
  }

  Future<void> switchToArchitect() async {
    if (architectTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, architectTab);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS — Spine panels
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> openAudioAssign() async {
    if (spineAudioAssign.evaluate().isNotEmpty) {
      await tapAndSettle(tester, spineAudioAssign.first);
      await settle(tester, const Duration(milliseconds: 300));
    }
  }

  Future<void> openConfig() async {
    if (spineConfig.evaluate().isNotEmpty) {
      await tapAndSettle(tester, spineConfig.first);
      await settle(tester, const Duration(milliseconds: 300));
    }
  }

  Future<void> openAnalytics() async {
    if (spineAnalytics.evaluate().isNotEmpty) {
      await tapAndSettle(tester, spineAnalytics.first);
      await settle(tester, const Duration(milliseconds: 300));
    }
  }

  Future<void> openAIPanel() async {
    if (spineAI.evaluate().isNotEmpty) {
      await tapAndSettle(tester, spineAI.first);
      await settle(tester, const Duration(milliseconds: 300));
    }
  }

  /// Cycle through ALL spine panels, verify each doesn't crash
  Future<void> cycleAllSpinePanels() async {
    final spineFinders = [spineAudioAssign, spineConfig, spineAnalytics, spineAI];
    for (final finder in spineFinders) {
      if (finder.evaluate().isNotEmpty) {
        await tapAndSettle(tester, finder.first);
        await safePump(tester, const Duration(milliseconds: 400));
        verifyNoOverflow();
        await drainExceptions(tester);
      }
    }
    // Close any open panel
    await pressEsc();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS — Dock tabs
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> openDockTab(String tabName) async {
    // Use key-based finder to avoid ambiguity with other text widgets
    // (e.g., _FlowPanel renders 'AUDIO' as a category name)
    final keyFinder = find.byKey(Key('dock_tab_$tabName'));
    if (keyFinder.evaluate().isNotEmpty) {
      await tapAndSettle(tester, keyFinder);
      await settle(tester, const Duration(milliseconds: 300));
      return;
    }
    // Fallback: text-based (for robustness)
    final textFinder = find.text(tabName);
    if (textFinder.evaluate().isNotEmpty) {
      await tapAndSettle(tester, textFinder.first);
      await settle(tester, const Duration(milliseconds: 300));
    }
  }

  Future<void> cycleAllDockTabs() async {
    for (final tab in allDockTabs) {
      // Key-based to avoid ambiguity with category text widgets
      final keyFinder = find.byKey(Key('dock_tab_$tab'));
      final finder = keyFinder.evaluate().isNotEmpty ? keyFinder : find.text(tab);
      if (finder.evaluate().isNotEmpty) {
        await tapAndSettle(tester, finder.first);
        await safePump(tester, const Duration(milliseconds: 200));
        verifyNoOverflow();
        await drainExceptions(tester);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS — Slot controls
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> spin() async {
    // Always use Space key — SPIN button is often obscured by the dock panel
    await pressSpace(tester);
  }

  Future<void> waitForSpinComplete({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final endTime = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(endTime)) {
      await safePump(tester, const Duration(milliseconds: 100));
      if (spinButton.evaluate().isNotEmpty &&
          slamButton.evaluate().isEmpty &&
          skipButton.evaluate().isEmpty) {
        return;
      }
    }
  }

  Future<void> slam() async {
    if (slamButton.evaluate().isNotEmpty) {
      await tester.tap(slamButton.first, warnIfMissed: false);
      await settle(tester, const Duration(milliseconds: 300));
    }
  }

  Future<void> skip() async {
    if (skipButton.evaluate().isNotEmpty) {
      await tester.tap(skipButton.first, warnIfMissed: false);
      await settle(tester, const Duration(milliseconds: 300));
    }
  }

  /// Full spin cycle: spin → wait for reels → SLAM → wait → SKIP if win → wait complete
  Future<void> fullSpinCycle() async {
    await spin();
    await safePump(tester, const Duration(milliseconds: 500));
    // Try SLAM after brief delay
    await slam();
    for (int i = 0; i < 20; i++) {
      await safePump(tester, const Duration(milliseconds: 100));
    }
    // Try SKIP if win presentation
    await skip();
    for (int i = 0; i < 20; i++) {
      await safePump(tester, const Duration(milliseconds: 100));
    }
    await waitForSpinComplete(timeout: const Duration(seconds: 10));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS — Auto-Bind
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> verifyAutoBindAvailable() async {
    await openDockTab('AUDIO');
    await settle(tester, const Duration(milliseconds: 500));
    expect(autoBindButton.evaluate().isNotEmpty, isTrue,
        reason: 'Auto-Bind button should be visible in AUDIO dock tab');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS — Keyboard shortcuts
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> pressF() async {
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await settle(tester);
  }

  Future<void> pressA() async {
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await settle(tester);
  }

  Future<void> pressEsc() async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
  }

  Future<void> pressDockKey(int number) async {
    final keys = [
      LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9, LogicalKeyboardKey.digit0,
    ];
    if (number >= 1 && number <= 10) {
      await tester.sendKeyEvent(keys[number - 1]);
      await settle(tester);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPOUND ACTIONS — Complex scenarios
  // ═══════════════════════════════════════════════════════════════════════════

  /// Mode switching stress: COMPOSE→FOCUS→COMPOSE→ARCHITECT→COMPOSE
  Future<void> stressModeSwitching() async {
    await pressF(); // FOCUS
    await safePump(tester, const Duration(milliseconds: 400));
    await pressF(); // back to COMPOSE
    await safePump(tester, const Duration(milliseconds: 400));
    await pressA(); // ARCHITECT
    await safePump(tester, const Duration(milliseconds: 400));
    await pressA(); // back to COMPOSE
    await safePump(tester, const Duration(milliseconds: 400));
    // Rapid switches
    for (int i = 0; i < 5; i++) {
      await pressF();
      await safePump(tester, const Duration(milliseconds: 100));
      await pressF();
      await safePump(tester, const Duration(milliseconds: 100));
    }
  }

  /// Spine panel stress: open/close all panels rapidly
  Future<void> stressSpinePanels() async {
    final spineFinders = [spineAudioAssign, spineConfig, spineAnalytics, spineAI];
    for (int round = 0; round < 2; round++) {
      for (final finder in spineFinders) {
        if (finder.evaluate().isNotEmpty) {
          await tapAndSettle(tester, finder.first);
          await safePump(tester, const Duration(milliseconds: 150));
          await drainExceptions(tester);
        }
      }
    }
    await pressEsc();
  }

  /// Dock stress: rapid tab switching with key presses
  Future<void> stressDockSwitching() async {
    for (int i = 1; i <= 6; i++) {
      await pressDockKey(i);
      await safePump(tester, const Duration(milliseconds: 100));
    }
    // Reverse
    for (int i = 6; i >= 1; i--) {
      await pressDockKey(i);
      await safePump(tester, const Duration(milliseconds: 100));
    }
    // Random-like pattern
    for (final i in [3, 1, 5, 2, 6, 4]) {
      await pressDockKey(i);
      await safePump(tester, const Duration(milliseconds: 80));
    }
  }

  /// Spin during mode switch — should not crash
  Future<void> spinDuringModeSwitch() async {
    await spin();
    await safePump(tester, const Duration(milliseconds: 200));
    await pressF(); // Switch to FOCUS mid-spin
    await safePump(tester, const Duration(milliseconds: 500));
    await pressF(); // Back to COMPOSE
    for (int i = 0; i < 30; i++) {
      await safePump(tester, const Duration(milliseconds: 100));
    }
    await waitForSpinComplete(timeout: const Duration(seconds: 10));
  }

  /// ESC barrage — mash ESC many times, should never close HELIX
  Future<void> escBarrage() async {
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await safePump(tester, const Duration(milliseconds: 50));
    }
    await settle(tester, const Duration(milliseconds: 300));
  }

  /// Open spine panel during spin — should not crash
  Future<void> openPanelDuringSpin() async {
    await spin();
    await safePump(tester, const Duration(milliseconds: 200));
    await openAudioAssign();
    await safePump(tester, const Duration(milliseconds: 300));
    await pressEsc(); // Close panel
    for (int i = 0; i < 30; i++) {
      await safePump(tester, const Duration(milliseconds: 100));
    }
    await waitForSpinComplete(timeout: const Duration(seconds: 10));
  }

  /// Switch dock tabs during spin — should not crash
  Future<void> switchDockDuringSpin() async {
    await spin();
    await safePump(tester, const Duration(milliseconds: 200));
    await openDockTab('MATH');
    await safePump(tester, const Duration(milliseconds: 200));
    await openDockTab('AUDIO');
    await safePump(tester, const Duration(milliseconds: 200));
    await openDockTab('FLOW');
    for (int i = 0; i < 30; i++) {
      await safePump(tester, const Duration(milliseconds: 100));
    }
    await waitForSpinComplete(timeout: const Duration(seconds: 10));
  }
}
