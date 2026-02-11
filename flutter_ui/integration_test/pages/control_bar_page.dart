/// FluxForge Studio — Control Bar Page Object Model
///
/// Encapsulates all interactions with the top control bar.
/// Provides semantic methods for transport, section switching, zone toggles.
///
/// Icons and tooltips verified against:
///   flutter_ui/lib/widgets/layout/control_bar.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/waits.dart';
import '../helpers/gestures.dart';

/// Page Object for the top Control Bar (transport, mode, tempo).
class ControlBarPage {
  final WidgetTester tester;
  const ControlBarPage(this.tester);

  // ─── Transport Finders ─────────────────────────────────────────────────────
  // Source: control_bar.dart lines 997-1027 (Ultimate Transport Bar)

  /// Play button — toggles to pause icon when playing
  Finder get playButton => find.byIcon(Icons.play_arrow);
  Finder get pauseButton => find.byIcon(Icons.pause);
  Finder get stopButton => find.byIcon(Icons.stop);
  Finder get recordButton => find.byIcon(Icons.fiber_manual_record);

  /// Rewind = skip_previous (NOT fast_rewind)
  Finder get rewindButton => find.byIcon(Icons.skip_previous);

  /// Forward = skip_next (NOT fast_forward)
  Finder get forwardButton => find.byIcon(Icons.skip_next);

  /// Loop = Icons.repeat (secondary controls, line 344)
  Finder get loopButton => find.byIcon(Icons.repeat);

  /// Transport tooltips (include keyboard shortcuts)
  Finder get playTooltip => find.byTooltip('Play/Pause (Space)');
  Finder get stopTooltip => find.byTooltip('Stop (.)');
  Finder get rewindTooltip => find.byTooltip('Rewind (,)');
  Finder get forwardTooltip => find.byTooltip('Forward (/)');
  Finder get recordTooltip => find.byTooltip('Record (R)');
  Finder get loopTooltip => find.byTooltip('Loop (L)');

  // ─── Mode Switcher Finders ────────────────────────────────────────────────
  // Source: control_bar.dart lines 86-111 (modeConfigs) + line 528 (tooltip)
  // Tooltip format: '${name} - ${description} (${shortcut})'

  Finder get dawTab => find.byTooltip('DAW - Timeline editing (1)');
  Finder get middlewareTab => find.byTooltip('Middleware - Event routing (2)');
  Finder get slotLabTab => find.byTooltip('Slot - Slot audio (3)');

  /// Fallback: text labels used in mode switcher buttons
  Finder get dawTabText => find.text('DAW');
  Finder get middlewareTabText => find.text('Middleware');
  Finder get slotTabText => find.text('Slot');

  // ─── Zone Toggles ─────────────────────────────────────────────────────────
  // Source: control_bar.dart lines 1502-1527
  // Uses Unicode symbols (◀▼▶), NOT Material Icons

  Finder get toggleLeftZone => find.byTooltip('Toggle Left Zone (Ctrl+L)');
  Finder get toggleLowerZone => find.byTooltip('Toggle Lower Zone (Ctrl+B)');
  Finder get toggleRightZone => find.byTooltip('Toggle Right Zone (Ctrl+R)');

  // ─── Transport Actions ─────────────────────────────────────────────────────

  /// Press Play (or toggle pause)
  Future<void> pressPlay() async {
    // Prefer tooltip (unique) over icon (may have duplicates)
    if (playTooltip.evaluate().isNotEmpty) {
      await tapAndSettle(tester, playTooltip);
    } else if (playButton.evaluate().isNotEmpty) {
      await tapAndSettle(tester, playButton.first);
    } else {
      // Keyboard fallback: Space
      await pressSpace(tester);
    }
  }

  /// Press Stop
  Future<void> pressStop() async {
    if (stopTooltip.evaluate().isNotEmpty) {
      await tapAndSettle(tester, stopTooltip);
    } else if (stopButton.evaluate().isNotEmpty) {
      await tapAndSettle(tester, stopButton.first);
    }
  }

  /// Press Record
  Future<void> pressRecord() async {
    if (recordTooltip.evaluate().isNotEmpty) {
      await tapAndSettle(tester, recordTooltip);
    } else if (recordButton.evaluate().isNotEmpty) {
      await tapAndSettle(tester, recordButton.first);
    }
  }

  /// Press Rewind (skip_previous)
  Future<void> pressRewind() async {
    if (rewindTooltip.evaluate().isNotEmpty) {
      await tapAndSettle(tester, rewindTooltip);
    } else if (rewindButton.evaluate().isNotEmpty) {
      await tapAndSettle(tester, rewindButton.first);
    }
  }

  /// Press Forward (skip_next)
  Future<void> pressForward() async {
    if (forwardTooltip.evaluate().isNotEmpty) {
      await tapAndSettle(tester, forwardTooltip);
    } else if (forwardButton.evaluate().isNotEmpty) {
      await tapAndSettle(tester, forwardButton.first);
    }
  }

  /// Toggle loop mode
  Future<void> toggleLoop() async {
    if (loopTooltip.evaluate().isNotEmpty) {
      await tapAndSettle(tester, loopTooltip);
    } else if (loopButton.evaluate().isNotEmpty) {
      await tapAndSettle(tester, loopButton.first);
    }
  }

  // ─── Section Switching ─────────────────────────────────────────────────────

  /// Switch to DAW section
  Future<void> switchToDAW() async {
    // Primary: tooltip-based finder
    if (dawTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, dawTab);
    } else if (dawTabText.evaluate().isNotEmpty) {
      // Fallback: text label
      await tapAndSettle(tester, dawTabText.first);
    } else {
      // Keyboard shortcut: Cmd+1
      await sendKeyCombo(tester, meta: true, key: LogicalKeyboardKey.digit1);
    }
    await settle(tester, const Duration(milliseconds: 500));
  }

  /// Switch to Middleware section
  Future<void> switchToMiddleware() async {
    if (middlewareTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, middlewareTab);
    } else if (middlewareTabText.evaluate().isNotEmpty) {
      await tapAndSettle(tester, middlewareTabText.first);
    } else {
      await sendKeyCombo(tester, meta: true, key: LogicalKeyboardKey.digit2);
    }
    await settle(tester, const Duration(milliseconds: 500));
  }

  /// Switch to SlotLab section
  Future<void> switchToSlotLab() async {
    if (slotLabTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, slotLabTab);
    } else if (slotTabText.evaluate().isNotEmpty) {
      await tapAndSettle(tester, slotTabText.first);
    } else {
      await sendKeyCombo(tester, meta: true, key: LogicalKeyboardKey.digit3);
    }
    await settle(tester, const Duration(milliseconds: 500));
  }

  // ─── Zone Toggles ─────────────────────────────────────────────────────────

  /// Toggle Left Zone visibility
  Future<void> toggleLeft() async {
    if (toggleLeftZone.evaluate().isNotEmpty) {
      await tapAndSettle(tester, toggleLeftZone);
    }
  }

  /// Toggle Right Zone visibility
  Future<void> toggleRight() async {
    if (toggleRightZone.evaluate().isNotEmpty) {
      await tapAndSettle(tester, toggleRightZone);
    }
  }

  /// Toggle Lower Zone visibility
  Future<void> toggleLower() async {
    if (toggleLowerZone.evaluate().isNotEmpty) {
      await tapAndSettle(tester, toggleLowerZone);
    }
  }

  // ─── Assertions ────────────────────────────────────────────────────────────

  /// Verify transport controls are visible (icon OR tooltip based)
  Future<void> verifyTransportVisible() async {
    final hasPlay = playButton.evaluate().isNotEmpty ||
        playTooltip.evaluate().isNotEmpty;
    final hasPause = pauseButton.evaluate().isNotEmpty;
    final hasStop = stopButton.evaluate().isNotEmpty ||
        stopTooltip.evaluate().isNotEmpty;
    expect(hasPlay || hasPause, isTrue,
        reason: 'Expected Play or Pause button to be visible');
    expect(hasStop, isTrue, reason: 'Expected Stop button to be visible');
  }

  /// Verify a specific section tab is visible
  Future<void> verifyDAWTabVisible() async {
    final hasTab = dawTab.evaluate().isNotEmpty ||
        dawTabText.evaluate().isNotEmpty;
    expect(hasTab, isTrue, reason: 'DAW tab should be visible');
  }

  /// Verify control bar exists (any transport button or tooltip)
  Future<void> verifyControlBarPresent() async {
    final hasAnyTransport = playButton.evaluate().isNotEmpty ||
        pauseButton.evaluate().isNotEmpty ||
        stopButton.evaluate().isNotEmpty ||
        rewindButton.evaluate().isNotEmpty ||
        forwardButton.evaluate().isNotEmpty ||
        playTooltip.evaluate().isNotEmpty ||
        stopTooltip.evaluate().isNotEmpty;
    expect(hasAnyTransport, isTrue,
        reason: 'Control bar should have at least one transport button');
  }
}
