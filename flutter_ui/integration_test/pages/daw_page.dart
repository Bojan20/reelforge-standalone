/// FluxForge Studio — DAW Page Object Model
///
/// Timeline, mixer, lower zone Browse/Edit/Mix/Process/Deliver tabs.
///
/// Tab labels verified against:
///   flutter_ui/lib/widgets/lower_zone/lower_zone_types.dart (lines 181-254)
///   Super-tabs are UPPERCASE, sub-tabs are Title Case.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/gestures.dart';

/// Page Object for the DAW section (timeline, mixer, lower zone).
class DAWPage {
  final WidgetTester tester;
  const DAWPage(this.tester);

  // ─── Lower Zone Super-Tab Finders ──────────────────────────────────────────
  // Super-tabs are UPPERCASE in the real UI

  Finder get browseTab => find.text('BROWSE');
  Finder get editTab => find.text('EDIT');
  Finder get mixTab => find.text('MIX');
  Finder get processTab => find.text('PROCESS');
  Finder get deliverTab => find.text('DELIVER');

  // ─── Browse Sub-Tab Finders ────────────────────────────────────────────────

  Finder get filesSubTab => find.text('Files');
  Finder get presetsSubTab => find.text('Presets');
  Finder get pluginsSubTab => find.text('Plugins');
  Finder get historySubTab => find.text('History');

  // ─── Edit Sub-Tab Finders ──────────────────────────────────────────────────

  Finder get timelineSubTab => find.text('Timeline');
  Finder get pianoRollSubTab => find.text('Piano Roll');
  Finder get fadesSubTab => find.text('Fades');
  Finder get gridSubTab => find.text('Grid');

  // ─── Mix Sub-Tab Finders ───────────────────────────────────────────────────

  Finder get mixerSubTab => find.text('Mixer');
  Finder get sendsSubTab => find.text('Sends');
  Finder get panSubTab => find.text('Pan');
  Finder get autoSubTab => find.text('Auto');

  // ─── Process Sub-Tab Finders ──────────────────────────────────────────────

  Finder get eqSubTab => find.text('EQ');
  Finder get compSubTab => find.text('Comp');
  Finder get limiterSubTab => find.text('Limiter');
  Finder get fxChainSubTab => find.text('FX Chain');
  Finder get sidechainSubTab => find.text('Sidechain');

  // ─── Deliver Sub-Tab Finders ──────────────────────────────────────────────

  Finder get exportSubTab => find.text('Export');
  Finder get stemsSubTab => find.text('Stems');
  Finder get bounceSubTab => find.text('Bounce');
  Finder get archiveSubTab => find.text('Archive');

  // ─── Mixer Finders ─────────────────────────────────────────────────────────

  Finder get muteButtons => find.text('M');
  Finder get soloButtons => find.text('S');
  Finder get armButtons => find.text('R');
  Finder get sliders => find.byType(Slider);
  Finder get addTrackButton => find.byIcon(Icons.add);

  // ─── Timeline Finders ──────────────────────────────────────────────────────

  Finder get timelineWidget => find.byType(GestureDetector);

  // ─── Lower Zone Tab Actions ────────────────────────────────────────────────

  /// Switch to Browse super-tab
  Future<void> openBrowse() async {
    if (browseTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, browseTab.first);
    }
  }

  /// Switch to Edit super-tab
  Future<void> openEdit() async {
    if (editTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, editTab.first);
    }
  }

  /// Switch to Mix super-tab
  Future<void> openMix() async {
    if (mixTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, mixTab.first);
    }
  }

  /// Switch to Process super-tab
  Future<void> openProcess() async {
    if (processTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, processTab.first);
    }
  }

  /// Switch to Deliver super-tab
  Future<void> openDeliver() async {
    if (deliverTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, deliverTab.first);
    }
  }

  // ─── Sub-Tab Actions ───────────────────────────────────────────────────────

  /// Navigate to a specific sub-tab by text
  Future<void> openSubTab(String tabText) async {
    final finder = find.text(tabText);
    if (finder.evaluate().isNotEmpty) {
      await tapAndSettle(tester, finder.first);
    }
  }

  // ─── Mixer Actions ─────────────────────────────────────────────────────────

  /// Tap the first Mute button found
  Future<void> tapMute({int index = 0}) async {
    final buttons = muteButtons;
    if (buttons.evaluate().length > index) {
      await tapAndSettle(tester, buttons.at(index));
    }
  }

  /// Tap the first Solo button found
  Future<void> tapSolo({int index = 0}) async {
    final buttons = soloButtons;
    if (buttons.evaluate().length > index) {
      await tapAndSettle(tester, buttons.at(index));
    }
  }

  /// Tap the first Arm button found
  Future<void> tapArm({int index = 0}) async {
    final buttons = armButtons;
    if (buttons.evaluate().length > index) {
      await tapAndSettle(tester, buttons.at(index));
    }
  }

  /// Move a fader slider to a normalized position (0.0 to 1.0)
  Future<void> moveFader(int index, double normalizedValue) async {
    final allSliders = sliders;
    if (allSliders.evaluate().length > index) {
      await moveSlider(tester, allSliders.at(index), normalizedValue);
    }
  }

  // ─── Transport Shortcuts ───────────────────────────────────────────────────

  /// Press Space for play/pause
  Future<void> togglePlayback() async {
    await pressSpace(tester);
  }

  // ─── Cycle Through All Tabs ────────────────────────────────────────────────

  /// Navigate through all super-tabs in sequence
  Future<void> cycleAllSuperTabs() async {
    await openBrowse();
    await tester.pump(const Duration(milliseconds: 200));
    await openEdit();
    await tester.pump(const Duration(milliseconds: 200));
    await openMix();
    await tester.pump(const Duration(milliseconds: 200));
    await openProcess();
    await tester.pump(const Duration(milliseconds: 200));
    await openDeliver();
    await tester.pump(const Duration(milliseconds: 200));
  }

  // ─── Assertions ────────────────────────────────────────────────────────────

  /// Verify DAW lower zone tabs are visible
  Future<void> verifyLowerZoneTabs() async {
    final hasBrowse = browseTab.evaluate().isNotEmpty;
    final hasEdit = editTab.evaluate().isNotEmpty;
    final hasMix = mixTab.evaluate().isNotEmpty;
    expect(hasBrowse || hasEdit || hasMix, isTrue,
        reason: 'Expected DAW lower zone tabs (BROWSE, EDIT, MIX)');
  }

  /// Verify mixer channel strips are present
  Future<void> verifyMixerVisible() async {
    final hasMute = muteButtons.evaluate().isNotEmpty;
    final hasSolo = soloButtons.evaluate().isNotEmpty;
    expect(hasMute || hasSolo, isTrue,
        reason: 'Expected mixer channel strips to be visible');
  }

  /// Verify slider widgets exist (faders)
  Future<void> verifyFadersPresent() async {
    expect(sliders.evaluate().isNotEmpty, isTrue,
        reason: 'Expected at least one fader/slider in the mixer');
  }
}
