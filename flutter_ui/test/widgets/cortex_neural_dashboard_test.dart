import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:fluxforge_ui/providers/cortex_provider.dart';
import 'package:fluxforge_ui/widgets/lower_zone/daw/cortex/cortex_neural_dashboard.dart';
import 'package:fluxforge_ui/widgets/lower_zone/lower_zone_types.dart';

/// Wrap a widget with CortexProvider for testing
Widget _testApp(Widget child) {
  return MaterialApp(
    home: ChangeNotifierProvider<CortexProvider>(
      create: (_) => CortexProvider(),
      child: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('CortexNeuralDashboard', () {
    testWidgets('renders overview sub-tab', (tester) async {
      await tester.pumpWidget(_testApp(
        const CortexNeuralDashboard(subTab: DawCortexSubTab.overview),
      ));
      await tester.pump();

      expect(find.text('AWARENESS RADAR'), findsOneWidget);
      expect(find.text('HEALTH TIMELINE'), findsOneWidget);
      expect(find.text('VITAL SIGNS'), findsOneWidget);
      expect(find.text('ORGANISM STATUS'), findsOneWidget);
    });

    testWidgets('renders awareness sub-tab', (tester) async {
      await tester.pumpWidget(_testApp(
        const CortexNeuralDashboard(subTab: DawCortexSubTab.awareness),
      ));
      await tester.pump();

      expect(find.text('AWARENESS DIMENSIONS'), findsOneWidget);
      expect(find.text('DIMENSION DETAILS'), findsOneWidget);
      expect(find.text('Throughput'), findsOneWidget);
      expect(find.text('Reliability'), findsOneWidget);
      expect(find.text('Responsiveness'), findsOneWidget);
      expect(find.text('Coverage'), findsOneWidget);
      expect(find.text('Cognition'), findsOneWidget);
      expect(find.text('Efficiency'), findsOneWidget);
      expect(find.text('Coherence'), findsOneWidget);
    });

    testWidgets('renders neural sub-tab', (tester) async {
      await tester.pumpWidget(_testApp(
        const CortexNeuralDashboard(subTab: DawCortexSubTab.neural),
      ));
      await tester.pump();

      expect(find.text('SIGNAL THROUGHPUT'), findsOneWidget);
      expect(find.text('DROP RATE'), findsOneWidget);
      expect(find.text('NEURAL STATS'), findsOneWidget);
      expect(find.text('REFLEX ARC'), findsOneWidget);
      expect(find.text('PATTERN RECOGNITION'), findsOneWidget);
      expect(find.text('AUTONOMIC COMMANDS'), findsOneWidget);
    });

    testWidgets('renders immune sub-tab', (tester) async {
      await tester.pumpWidget(_testApp(
        const CortexNeuralDashboard(subTab: DawCortexSubTab.immune),
      ));
      await tester.pump();

      expect(find.text('IMMUNE DEFENSE STATUS'), findsOneWidget);
      expect(find.text('DEFENSE METRICS'), findsOneWidget);
      expect(find.text('HEALING'), findsOneWidget);
    });

    testWidgets('renders events sub-tab', (tester) async {
      await tester.pumpWidget(_testApp(
        const CortexNeuralDashboard(subTab: DawCortexSubTab.events),
      ));
      await tester.pump();

      expect(find.text('EVENT STREAM'), findsOneWidget);
      expect(find.text('ALL'), findsOneWidget);
      expect(find.text('HEALTH'), findsOneWidget);
      expect(find.text('REFLEX'), findsOneWidget);
      expect(find.text('PATTERN'), findsOneWidget);
      expect(find.text('IMMUNE'), findsOneWidget);
      expect(find.text('HEAL'), findsOneWidget);
    });

    testWidgets('events filter chips toggle', (tester) async {
      await tester.pumpWidget(_testApp(
        const CortexNeuralDashboard(subTab: DawCortexSubTab.events),
      ));
      await tester.pump();

      // Tap REFLEX filter
      await tester.tap(find.text('REFLEX'));
      await tester.pump();

      // Tap ALL to reset
      await tester.tap(find.text('ALL'));
      await tester.pump();
    });

    testWidgets('overview shows healthy status', (tester) async {
      await tester.pumpWidget(_testApp(
        const CortexNeuralDashboard(subTab: DawCortexSubTab.overview),
      ));
      await tester.pump();

      // Default health is 1.0 = HEALTHY
      expect(find.text('HEALTHY'), findsOneWidget);
    });

    testWidgets('immune shows clear status by default', (tester) async {
      await tester.pumpWidget(_testApp(
        const CortexNeuralDashboard(subTab: DawCortexSubTab.immune),
      ));
      await tester.pump();

      expect(find.text('Clear'), findsOneWidget); // No chronic
      expect(find.text('0'), findsWidgets); // No active anomalies
    });

    testWidgets('all sub-tabs have consistent dark bg', (tester) async {
      for (final subTab in DawCortexSubTab.values) {
        await tester.pumpWidget(_testApp(
          CortexNeuralDashboard(subTab: subTab),
        ));
        await tester.pump();

        // Should find at least one Container with the CORTEX bg color
        final containers = tester.widgetList<Container>(find.byType(Container));
        final hasDarkBg = containers.any((c) => c.color == const Color(0xFF0A0A14));
        expect(hasDarkBg, isTrue, reason: 'Sub-tab ${subTab.name} should have dark bg');
      }
    });
  });

  group('DawCortexSubTab', () {
    test('has 5 values', () {
      expect(DawCortexSubTab.values.length, 5);
    });

    test('labels are correct', () {
      expect(DawCortexSubTab.overview.label, 'Overview');
      expect(DawCortexSubTab.awareness.label, 'Awareness');
      expect(DawCortexSubTab.neural.label, 'Neural');
      expect(DawCortexSubTab.immune.label, 'Immune');
      expect(DawCortexSubTab.events.label, 'Events');
    });

    test('shortcuts are Q-T', () {
      expect(DawCortexSubTab.overview.shortcut, 'Q');
      expect(DawCortexSubTab.awareness.shortcut, 'W');
      expect(DawCortexSubTab.neural.shortcut, 'E');
      expect(DawCortexSubTab.immune.shortcut, 'R');
      expect(DawCortexSubTab.events.shortcut, 'T');
    });

    test('icons are not null', () {
      for (final tab in DawCortexSubTab.values) {
        expect(tab.icon, isNotNull);
      }
    });

    test('tooltips are not empty', () {
      for (final tab in DawCortexSubTab.values) {
        expect(tab.tooltip.isNotEmpty, isTrue);
      }
    });
  });

  group('DawSuperTab.cortex', () {
    test('exists in enum', () {
      expect(DawSuperTab.cortex.index, 5);
    });

    test('has neural pink color', () {
      expect(DawSuperTab.cortex.color, const Color(0xFFFF60B0));
    });

    test('label is CORTEX', () {
      expect(DawSuperTab.cortex.label, 'CORTEX');
    });

    test('category is NEURAL', () {
      expect(DawSuperTab.cortex.category, 'NEURAL');
    });

    test('shortcut is 6', () {
      expect(DawSuperTab.cortex.shortcut, '6');
    });
  });

  group('PaneTabState cortex integration', () {
    test('default cortexSubTab is overview', () {
      final state = PaneTabState();
      expect(state.cortexSubTab, DawCortexSubTab.overview);
    });

    test('setSubTabIndex works for cortex', () {
      final state = PaneTabState(superTab: DawSuperTab.cortex);
      state.setSubTabIndex(2);
      expect(state.cortexSubTab, DawCortexSubTab.neural);
    });

    test('currentSubTabIndex returns cortex index', () {
      final state = PaneTabState(
        superTab: DawSuperTab.cortex,
        cortexSubTab: DawCortexSubTab.events,
      );
      expect(state.currentSubTabIndex, 4);
    });

    test('subTabLabels returns cortex labels', () {
      final state = PaneTabState(superTab: DawSuperTab.cortex);
      expect(state.subTabLabels.length, 5);
      expect(state.subTabLabels.first, 'Overview');
    });

    test('copy preserves cortexSubTab', () {
      final state = PaneTabState(
        superTab: DawSuperTab.cortex,
        cortexSubTab: DawCortexSubTab.immune,
      );
      final copied = state.copy();
      expect(copied.cortexSubTab, DawCortexSubTab.immune);
    });

    test('toJson/fromJson roundtrip', () {
      final state = PaneTabState(
        superTab: DawSuperTab.cortex,
        cortexSubTab: DawCortexSubTab.neural,
      );
      final json = state.toJson();
      final restored = PaneTabState.fromJson(json);
      expect(restored.superTab, DawSuperTab.cortex);
      expect(restored.cortexSubTab, DawCortexSubTab.neural);
    });
  });

  group('DawLowerZoneState cortex integration', () {
    test('default cortexSubTab is overview', () {
      final state = DawLowerZoneState();
      expect(state.cortexSubTab, DawCortexSubTab.overview);
    });

    test('setSubTabIndex works for cortex', () {
      final state = DawLowerZoneState(superTab: DawSuperTab.cortex);
      state.setSubTabIndex(3);
      expect(state.cortexSubTab, DawCortexSubTab.immune);
    });

    test('currentSubTabIndex returns cortex index', () {
      final state = DawLowerZoneState(
        superTab: DawSuperTab.cortex,
        cortexSubTab: DawCortexSubTab.events,
      );
      expect(state.currentSubTabIndex, 4);
    });

    test('subTabLabels returns cortex labels', () {
      final state = DawLowerZoneState(superTab: DawSuperTab.cortex);
      expect(state.subTabLabels.length, 5);
    });

    test('copyWith preserves cortexSubTab', () {
      final state = DawLowerZoneState(cortexSubTab: DawCortexSubTab.awareness);
      final copied = state.copyWith(superTab: DawSuperTab.cortex);
      expect(copied.cortexSubTab, DawCortexSubTab.awareness);
    });

    test('toJson includes cortexSubTab', () {
      final state = DawLowerZoneState(cortexSubTab: DawCortexSubTab.neural);
      final json = state.toJson();
      expect(json['cortexSubTab'], 2);
    });

    test('fromJson restores cortexSubTab', () {
      final state = DawLowerZoneState.fromJson({
        'cortexSubTab': 4,
      });
      expect(state.cortexSubTab, DawCortexSubTab.events);
    });

    test('fromJson handles missing cortexSubTab', () {
      final state = DawLowerZoneState.fromJson({});
      expect(state.cortexSubTab, DawCortexSubTab.overview);
    });
  });
}
