/// FluxForge Studio — E2E Widget Finders
///
/// Semantic finders for locating UI elements in E2E tests.
/// Uses text, type, key, and descendant strategies.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CONTROL BAR FINDERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Find transport buttons by icon
Finder findPlayButton() => find.byIcon(Icons.play_arrow);
Finder findStopButton() => find.byIcon(Icons.stop);
Finder findRecordButton() => find.byIcon(Icons.fiber_manual_record);
Finder findRewindButton() => find.byIcon(Icons.fast_rewind);
Finder findForwardButton() => find.byIcon(Icons.fast_forward);
Finder findLoopButton() => find.byIcon(Icons.loop);

/// Find zone toggle buttons by tooltip
Finder findToggleLeftZone() => find.byTooltip('Toggle Left Zone');
Finder findToggleRightZone() => find.byTooltip('Toggle Right Zone');
Finder findToggleLowerZone() => find.byTooltip('Toggle Lower Zone');

// ═══════════════════════════════════════════════════════════════════════════════
// MODE/SECTION SWITCHING FINDERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Find launcher mode buttons
Finder findDAWLauncherButton() => find.text('DAW Studio');
Finder findMiddlewareLauncherButton() => find.text('Game Audio');

/// Find section tabs in control bar (when in main layout)
Finder findDAWTab() => find.text('DAW');
Finder findMiddlewareTab() => find.text('Middleware');
Finder findSlotLabTab() => find.text('Slot Lab');

// ═══════════════════════════════════════════════════════════════════════════════
// LOWER ZONE FINDERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Find lower zone super-tabs by text
Finder findLowerZoneTab(String tabText) => find.text(tabText);

/// Common lower zone tabs
Finder findBrowseTab() => find.text('Browse');
Finder findEditTab() => find.text('Edit');
Finder findMixTab() => find.text('Mix');
Finder findProcessTab() => find.text('Process');
Finder findDeliverTab() => find.text('Deliver');

// ═══════════════════════════════════════════════════════════════════════════════
// MIXER FINDERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Find mixer channel strips by name
Finder findChannelStrip(String channelName) => find.textContaining(channelName);

/// Find fader slider
Finder findFaderByIndex(int index) {
  final sliders = find.byType(Slider);
  return sliders.at(index);
}

/// Find mute button
Finder findMuteButton() => find.text('M');
Finder findSoloButton() => find.text('S');
Finder findArmButton() => find.text('R');

// ═══════════════════════════════════════════════════════════════════════════════
// SLOTLAB FINDERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Find spin button
Finder findSpinButton() => find.text('SPIN');
Finder findStopSpinButton() => find.text('STOP');

/// Find forced outcome buttons
Finder findForcedOutcome(String label) => find.text(label);
Finder findLoseOutcome() => find.text('Lose');
Finder findSmallWinOutcome() => find.text('Small Win');
Finder findBigWinOutcome() => find.text('Big Win');

/// Find SlotLab edit mode toggle
Finder findEditModeToggle() => find.text('Edit Mode');

// ═══════════════════════════════════════════════════════════════════════════════
// MIDDLEWARE FINDERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Find events panel
Finder findEventsPanel() => find.text('Events');
Finder findCreateEventButton() => find.byIcon(Icons.add);

/// Find container tabs
Finder findBlendTab() => find.text('Blend');
Finder findRandomTab() => find.text('Random');
Finder findSequenceTab() => find.text('Sequence');

// ═══════════════════════════════════════════════════════════════════════════════
// GENERIC HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Find any button by its text label
Finder findButton(String text) => find.widgetWithText(TextButton, text);
Finder findElevatedButton(String text) =>
    find.widgetWithText(ElevatedButton, text);
Finder findIconButton(IconData icon) => find.widgetWithIcon(IconButton, icon);

/// Find tab by text
Finder findTab(String text) => find.text(text);

/// Find a widget that contains specific text
Finder findContaining(String text) => find.textContaining(text);

/// Find by semantic label
Finder findBySemantic(String label) => find.bySemanticsLabel(label);

/// Find the Nth widget of a type
Finder findNth(Type type, int index) => find.byType(type).at(index);

/// Find a descendant of a specific parent
Finder findDescendant({
  required Finder parent,
  required Finder descendant,
}) =>
    find.descendant(of: parent, matching: descendant);
