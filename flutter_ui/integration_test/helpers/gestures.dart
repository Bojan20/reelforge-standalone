/// FluxForge Studio — E2E Gesture Helpers
///
/// High-level gesture abstractions for E2E tests.
/// Drag, scroll, long-press, keyboard shortcuts.
///
/// NOTE: All settle calls use bounded pump loops (NOT pumpAndSettle)
/// because FluxForge has persistent timers that never idle.

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'waits.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TAP HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Tap a finder and wait for animations to settle
Future<void> tapAndSettle(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 5)}) async {
  await tester.tap(finder);
  await settle(tester, const Duration(milliseconds: 300));
}

/// Double-tap a finder
Future<void> doubleTapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await settle(tester, const Duration(milliseconds: 300));
}

/// Right-click (secondary tap)
Future<void> rightClick(WidgetTester tester, Finder finder) async {
  await tester.tap(finder, buttons: kSecondaryButton);
  await settle(tester, const Duration(milliseconds: 300));
}

// ═══════════════════════════════════════════════════════════════════════════════
// DRAG HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Drag a widget horizontally
Future<void> dragHorizontal(
    WidgetTester tester, Finder finder, double dx) async {
  await tester.drag(finder, Offset(dx, 0));
  await settle(tester);
}

/// Drag a widget vertically
Future<void> dragVertical(
    WidgetTester tester, Finder finder, double dy) async {
  await tester.drag(finder, Offset(0, dy));
  await settle(tester);
}

/// Drag from one finder to another
Future<void> dragFromTo(
    WidgetTester tester, Finder from, Finder to) async {
  final fromCenter = tester.getCenter(from);
  final toCenter = tester.getCenter(to);
  await tester.dragFrom(fromCenter, toCenter - fromCenter);
  await settle(tester);
}

/// Long press drag (for reordering)
Future<void> longPressDrag(
    WidgetTester tester, Finder finder, Offset offset) async {
  await tester.timedDrag(finder, offset, const Duration(milliseconds: 500));
  await settle(tester);
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCROLL HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Scroll down in a scrollable
Future<void> scrollDown(WidgetTester tester, Finder scrollable,
    {double amount = 300}) async {
  await tester.drag(scrollable, Offset(0, -amount));
  await settle(tester);
}

/// Scroll up in a scrollable
Future<void> scrollUp(WidgetTester tester, Finder scrollable,
    {double amount = 300}) async {
  await tester.drag(scrollable, Offset(0, amount));
  await settle(tester);
}

/// Scroll until a widget is visible
Future<void> scrollUntilVisible(
    WidgetTester tester, Finder finder, Finder scrollable,
    {double delta = -200, int maxIterations = 20}) async {
  for (int i = 0; i < maxIterations; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.drag(scrollable, Offset(0, delta));
    await settle(tester);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// KEYBOARD HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Send a keyboard shortcut
Future<void> sendKeyCombo(WidgetTester tester,
    {bool meta = false,
    bool ctrl = false,
    bool shift = false,
    bool alt = false,
    required LogicalKeyboardKey key}) async {
  final List<LogicalKeyboardKey> modifiers = [
    if (meta) LogicalKeyboardKey.metaLeft,
    if (ctrl) LogicalKeyboardKey.controlLeft,
    if (shift) LogicalKeyboardKey.shiftLeft,
    if (alt) LogicalKeyboardKey.altLeft,
  ];

  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await settle(tester);
}

/// Press Space key
Future<void> pressSpace(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.space);
  await settle(tester);
}

/// Press Escape key
Future<void> pressEscape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await settle(tester);
}

/// Press Enter key
Future<void> pressEnter(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await settle(tester);
}

/// Type text into a text field
Future<void> typeText(WidgetTester tester, Finder field, String text) async {
  await tester.tap(field);
  await tester.enterText(field, text);
  await settle(tester);
}

// ═══════════════════════════════════════════════════════════════════════════════
// SLIDER HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Move a slider to a specific value (0.0 to 1.0 normalized)
Future<void> moveSlider(
    WidgetTester tester, Finder sliderFinder, double normalizedValue) async {
  final slider = tester.widget<Slider>(sliderFinder);
  final rect = tester.getRect(sliderFinder);
  final targetX =
      rect.left + (rect.width * normalizedValue);
  final centerY = rect.center.dy;

  await tester.tapAt(Offset(targetX, centerY));
  await settle(tester);
}
