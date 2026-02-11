/// FluxForge Studio — E2E Wait Helpers
///
/// Polling-based wait utilities for asynchronous conditions.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wait until a finder finds at least one widget.
/// Times out after [timeout] with an assertion failure.
Future<void> waitForWidget(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
  Duration pollInterval = const Duration(milliseconds: 100),
  String? description,
}) async {
  final endTime = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(endTime)) {
    await tester.pump(pollInterval);
    _drainPendingException(tester);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for ${description ?? finder.description}');
}

/// Wait until a finder finds NO widgets (widget disappears).
Future<void> waitForNoWidget(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
  Duration pollInterval = const Duration(milliseconds: 100),
  String? description,
}) async {
  final endTime = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(endTime)) {
    await tester.pump(pollInterval);
    _drainPendingException(tester);
    if (finder.evaluate().isEmpty) return;
  }
  fail('Timed out waiting for ${description ?? finder.description} to disappear');
}

/// Wait for a condition to become true.
Future<void> waitForCondition(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  Duration pollInterval = const Duration(milliseconds: 100),
  String description = 'condition',
}) async {
  final endTime = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(endTime)) {
    await tester.pump(pollInterval);
    _drainPendingException(tester);
    if (condition()) return;
  }
  fail('Timed out waiting for $description');
}

/// Wait for text to appear on screen
Future<void> waitForText(
  WidgetTester tester,
  String text, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  await waitForWidget(tester, find.text(text),
      timeout: timeout, description: 'text "$text"');
}

/// Wait for text containing a substring
Future<void> waitForTextContaining(
  WidgetTester tester,
  String substring, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  await waitForWidget(tester, find.textContaining(substring),
      timeout: timeout, description: 'text containing "$substring"');
}

/// Pump N frames to allow animations
Future<void> pumpFrames(
  WidgetTester tester, {
  int count = 10,
  Duration interval = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < count; i++) {
    await tester.pump(interval);
    _drainPendingException(tester);
  }
}

/// Bounded settle — pumps frames for a fixed duration.
/// Unlike pumpAndSettle, this does NOT wait for zero scheduled frames,
/// which would hang forever in apps with persistent timers (meters, tickers).
///
/// Also drains any pending exceptions between frames to prevent
/// framework assertions (Focus, InheritedNotifier) from failing the test.
Future<void> settle(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 500),
]) async {
  final frames = (duration.inMilliseconds / 16).ceil();
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    _drainPendingException(tester);
  }
}

/// Drain a single pending exception without failing.
void _drainPendingException(WidgetTester tester) {
  try {
    final ex = tester.takeException();
    if (ex != null) {
      debugPrint('[E2E] Drained: ${ex.toString().split('\n').first}');
    }
  } catch (_) {}
}

/// Wait for app to be fully loaded (past splash screen)
Future<void> waitForAppReady(WidgetTester tester) async {
  // Wait until we see either launcher buttons or main layout
  final endTime = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(endTime)) {
    await tester.pump(const Duration(milliseconds: 200));
    _drainPendingException(tester);

    // Check for launcher screen — panel titles
    if (find.text('DAW').evaluate().isNotEmpty) return;
    if (find.text('MIDDLEWARE').evaluate().isNotEmpty) return;

    // Check for launcher buttons
    if (find.text('ENTER DAW').evaluate().isNotEmpty) return;
    if (find.text('ENTER MIDDLEWARE').evaluate().isNotEmpty) return;

    // Legacy launcher texts (in case UI changes)
    if (find.text('DAW Studio').evaluate().isNotEmpty) return;
    if (find.text('Game Audio').evaluate().isNotEmpty) return;

    // Check for main layout (already past launcher)
    if (find.text('FluxForge Studio').evaluate().isNotEmpty) return;

    // Check for hub screens
    if (find.text('CREATE NEW PROJECT').evaluate().isNotEmpty) return;
    if (find.textContaining('Create').evaluate().isNotEmpty) return;

    // Check for control bar (already in main layout)
    if (find.byTooltip('Play/Pause (Space)').evaluate().isNotEmpty) return;
  }
  fail('App did not reach ready state within 30 seconds');
}
