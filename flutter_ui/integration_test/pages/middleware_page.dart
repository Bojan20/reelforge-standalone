/// FluxForge Studio — Middleware Page Object Model
///
/// Events, containers, routing, RTPC, deliver tabs.
///
/// Tab labels verified against:
///   flutter_ui/lib/widgets/lower_zone/lower_zone_types.dart (lines 490-527)
///   Super-tabs are UPPERCASE, sub-tabs are Title Case.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/gestures.dart';

/// Page Object for the Middleware section.
class MiddlewarePage {
  final WidgetTester tester;
  const MiddlewarePage(this.tester);

  // ─── Lower Zone Super-Tab Finders ──────────────────────────────────────────
  // Super-tabs are UPPERCASE in the real UI

  Finder get eventsTab => find.text('EVENTS');
  Finder get containersTab => find.text('CONTAINERS');
  Finder get routingTab => find.text('ROUTING');
  Finder get rtpcTab => find.text('RTPC');
  Finder get deliverTab => find.text('DELIVER');

  // ─── Events Sub-Tab Finders ────────────────────────────────────────────────

  Finder get eventBrowserSubTab => find.text('Browser');
  Finder get eventEditorSubTab => find.text('Editor');
  Finder get eventTriggersSubTab => find.text('Triggers');
  Finder get eventDebugSubTab => find.text('Debug');

  // ─── Containers Sub-Tab Finders ────────────────────────────────────────────

  Finder get randomSubTab => find.text('Random');
  Finder get sequenceSubTab => find.text('Sequence');
  Finder get blendSubTab => find.text('Blend');
  Finder get switchSubTab => find.text('Switch');

  // ─── Routing Sub-Tab Finders ───────────────────────────────────────────────

  Finder get busesSubTab => find.text('Buses');
  Finder get duckingSubTab => find.text('Ducking');
  Finder get matrixSubTab => find.text('Matrix');
  Finder get prioritySubTab => find.text('Priority');

  // ─── RTPC Sub-Tab Finders ────────────────────────────────────────────────

  Finder get curvesSubTab => find.text('Curves');
  Finder get bindingsSubTab => find.text('Bindings');
  Finder get metersSubTab => find.text('Meters');
  Finder get profilerSubTab => find.text('Profiler');

  // ─── Deliver Sub-Tab Finders ─────────────────────────────────────────────

  Finder get bakeSubTab => find.text('Bake');
  Finder get soundbankSubTab => find.text('Soundbank');
  Finder get validateSubTab => find.text('Validate');
  Finder get packageSubTab => find.text('Package');

  // ─── Action Buttons ────────────────────────────────────────────────────────

  Finder get createEventButton => find.byIcon(Icons.add);
  Finder get deleteButton => find.byIcon(Icons.delete);
  Finder get duplicateButton => find.byIcon(Icons.copy);
  Finder get testButton => find.byIcon(Icons.play_arrow);

  // ─── Event Editor Finders ──────────────────────────────────────────────────

  Finder get eventNameField => find.byType(TextField);
  Finder get addLayerButton => find.textContaining('Add Layer');

  // ─── Lower Zone Tab Actions ────────────────────────────────────────────────

  /// Switch to Events super-tab
  Future<void> openEvents() async {
    if (eventsTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, eventsTab.first);
    }
  }

  /// Switch to Containers super-tab
  Future<void> openContainers() async {
    if (containersTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, containersTab.first);
    }
  }

  /// Switch to Routing super-tab
  Future<void> openRouting() async {
    if (routingTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, routingTab.first);
    }
  }

  /// Switch to RTPC super-tab
  Future<void> openRTPC() async {
    if (rtpcTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, rtpcTab.first);
    }
  }

  /// Switch to Deliver super-tab
  Future<void> openDeliver() async {
    if (deliverTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, deliverTab.first);
    }
  }

  /// Cycle through all super-tabs
  Future<void> cycleAllSuperTabs() async {
    await openEvents();
    await tester.pump(const Duration(milliseconds: 200));
    await openContainers();
    await tester.pump(const Duration(milliseconds: 200));
    await openRouting();
    await tester.pump(const Duration(milliseconds: 200));
    await openRTPC();
    await tester.pump(const Duration(milliseconds: 200));
    await openDeliver();
    await tester.pump(const Duration(milliseconds: 200));
  }

  // ─── Sub-Tab Actions ───────────────────────────────────────────────────────

  /// Navigate to a specific sub-tab by text
  Future<void> openSubTab(String tabText) async {
    final finder = find.text(tabText);
    if (finder.evaluate().isNotEmpty) {
      await tapAndSettle(tester, finder.first);
    }
  }

  /// Open Random container panel
  Future<void> openRandomContainers() async {
    await openContainers();
    await openSubTab('Random');
  }

  /// Open Sequence container panel
  Future<void> openSequenceContainers() async {
    await openContainers();
    await openSubTab('Sequence');
  }

  /// Open Blend container panel
  Future<void> openBlendContainers() async {
    await openContainers();
    await openSubTab('Blend');
  }

  /// Open Ducking panel
  Future<void> openDucking() async {
    await openRouting();
    await openSubTab('Ducking');
  }

  /// Open Buses panel
  Future<void> openBuses() async {
    await openRouting();
    await openSubTab('Buses');
  }

  // ─── Event Actions ─────────────────────────────────────────────────────────

  /// Create a new event by clicking the + button
  Future<void> createEvent() async {
    await openEvents();
    if (createEventButton.evaluate().isNotEmpty) {
      await tapAndSettle(tester, createEventButton.first);
    }
  }

  // ─── Assertions ────────────────────────────────────────────────────────────

  /// Verify Middleware lower zone tabs are visible
  Future<void> verifyLowerZoneTabs() async {
    final hasEvents = eventsTab.evaluate().isNotEmpty;
    final hasContainers = containersTab.evaluate().isNotEmpty;
    final hasRouting = routingTab.evaluate().isNotEmpty;
    expect(hasEvents || hasContainers || hasRouting, isTrue,
        reason: 'Expected Middleware lower zone tabs (EVENTS, CONTAINERS, ROUTING)');
  }

  /// Verify container panels are accessible
  Future<void> verifyContainersAccessible() async {
    await openContainers();
    final hasRandom = randomSubTab.evaluate().isNotEmpty;
    final hasSequence = sequenceSubTab.evaluate().isNotEmpty;
    final hasBlend = blendSubTab.evaluate().isNotEmpty;
    expect(hasRandom || hasSequence || hasBlend, isTrue,
        reason: 'Expected container sub-tabs (Random, Sequence, Blend)');
  }

  /// Verify routing panels are accessible
  Future<void> verifyRoutingAccessible() async {
    await openRouting();
    final hasBuses = busesSubTab.evaluate().isNotEmpty;
    final hasDucking = duckingSubTab.evaluate().isNotEmpty;
    expect(hasBuses || hasDucking, isTrue,
        reason: 'Expected routing sub-tabs (Buses, Ducking)');
  }
}
