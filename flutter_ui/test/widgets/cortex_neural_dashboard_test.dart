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

    testWidgets('renders events sub-tab with COMMAND filter', (tester) async {
      await tester.pumpWidget(_testApp(
        const CortexNeuralDashboard(subTab: DawCortexSubTab.events),
      ));
      await tester.pump();

      expect(find.text('EVENT STREAM'), findsOneWidget);
      expect(find.text('ALL'), findsOneWidget);
      expect(find.text('HEALTH'), findsOneWidget);
      expect(find.text('REFLEX'), findsOneWidget);
      expect(find.text('PATTERN'), findsOneWidget);
      expect(find.text('COMMAND'), findsOneWidget);
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

    testWidgets('immune shows clear status and antibodies section', (tester) async {
      await tester.pumpWidget(_testApp(
        const CortexNeuralDashboard(subTab: DawCortexSubTab.immune),
      ));
      await tester.pump();

      expect(find.text('Clear'), findsOneWidget); // No chronic
      expect(find.text('0'), findsWidgets); // No active anomalies
      expect(find.text('ANTIBODIES'), findsOneWidget);
      // No antibodies = clear message
      expect(find.textContaining('No active antibodies'), findsOneWidget);
    });

    testWidgets('all sub-tabs have consistent dark bg', (tester) async {
      for (final subTab in DawCortexSubTab.values) {
        // chat renders BrainChat which needs BrainProvider + CortexDaemonClient
        // (full daemon stack) — skip in unit-test context; covered in integration tests.
        if (subTab == DawCortexSubTab.chat) continue;

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
    test('has 6 values', () {
      // chat was added as first element (index 0) after the original 5 were written.
      expect(DawCortexSubTab.values.length, 6);
    });

    test('labels are correct', () {
      expect(DawCortexSubTab.chat.label, 'Chat');
      expect(DawCortexSubTab.overview.label, 'Overview');
      expect(DawCortexSubTab.awareness.label, 'Awareness');
      expect(DawCortexSubTab.neural.label, 'Neural');
      expect(DawCortexSubTab.immune.label, 'Immune');
      expect(DawCortexSubTab.events.label, 'Events');
    });

    test('shortcuts are Q-Y', () {
      // chat is now index 0 → 'Q'; all others shifted by one position.
      expect(DawCortexSubTab.chat.shortcut, 'Q');
      expect(DawCortexSubTab.overview.shortcut, 'W');
      expect(DawCortexSubTab.awareness.shortcut, 'E');
      expect(DawCortexSubTab.neural.shortcut, 'R');
      expect(DawCortexSubTab.immune.shortcut, 'T');
      expect(DawCortexSubTab.events.shortcut, 'Y');
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
      // index 0=chat, 1=overview, 2=awareness, 3=neural, 4=immune, 5=events
      state.setSubTabIndex(2);
      expect(state.cortexSubTab, DawCortexSubTab.awareness);
    });

    test('currentSubTabIndex returns cortex index', () {
      final state = PaneTabState(
        superTab: DawSuperTab.cortex,
        cortexSubTab: DawCortexSubTab.events,
      );
      // events is now at index 5 (chat was prepended)
      expect(state.currentSubTabIndex, 5);
    });

    test('subTabLabels returns cortex labels', () {
      final state = PaneTabState(superTab: DawSuperTab.cortex);
      // 6 tabs: chat + original 5
      expect(state.subTabLabels.length, 6);
      expect(state.subTabLabels.first, 'Chat');
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
      // Enum: chat(0) overview(1) awareness(2) neural(3) immune(4) events(5)
      state.setSubTabIndex(4);
      expect(state.cortexSubTab, DawCortexSubTab.immune);
    });

    test('currentSubTabIndex returns cortex index', () {
      final state = DawLowerZoneState(
        superTab: DawSuperTab.cortex,
        cortexSubTab: DawCortexSubTab.events,
      );
      // events is at index 5 (chat prepended as index 0)
      expect(state.currentSubTabIndex, 5);
    });

    test('subTabLabels returns cortex labels', () {
      final state = DawLowerZoneState(superTab: DawSuperTab.cortex);
      // 6 tabs: chat + original 5
      expect(state.subTabLabels.length, 6);
    });

    test('copyWith preserves cortexSubTab', () {
      final state = DawLowerZoneState(cortexSubTab: DawCortexSubTab.awareness);
      final copied = state.copyWith(superTab: DawSuperTab.cortex);
      expect(copied.cortexSubTab, DawCortexSubTab.awareness);
    });

    test('toJson includes cortexSubTab', () {
      final state = DawLowerZoneState(cortexSubTab: DawCortexSubTab.neural);
      final json = state.toJson();
      // neural is now at index 3 (chat was prepended)
      expect(json['cortexSubTab'], 3);
    });

    test('fromJson restores cortexSubTab', () {
      final state = DawLowerZoneState.fromJson({
        'cortexSubTab': 5,
      });
      // index 5 = events
      expect(state.cortexSubTab, DawCortexSubTab.events);
    });

    test('fromJson handles missing cortexSubTab', () {
      final state = DawLowerZoneState.fromJson({});
      // Missing key defaults to index 0; with chat prepended that is now chat.
      expect(state.cortexSubTab, DawCortexSubTab.chat);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CORTEX MODEL TESTS — CortexEvent, ReflexInfo, PatternInfo, etc.
  // ═══════════════════════════════════════════════════════════════════════

  group('CortexEvent', () {
    test('fromJson creates event correctly', () {
      final event = CortexEvent.fromJson({
        'event_type': 'health_changed',
        'value': 0.85,
        'value2': 0.92,
        'name': '',
        'detail': '',
      });
      expect(event.eventType, 'health_changed');
      expect(event.value, 0.85);
      expect(event.value2, 0.92);
      expect(event.isHealthChanged, isTrue);
      expect(event.isReflexFired, isFalse);
    });

    test('fromJson handles missing fields gracefully', () {
      final event = CortexEvent.fromJson({});
      expect(event.eventType, '');
      expect(event.value, 0.0);
      expect(event.name, '');
    });

    test('timestamp is set on creation', () {
      final before = DateTime.now();
      final event = CortexEvent.fromJson({'event_type': 'test'});
      final after = DateTime.now();
      expect(event.timestamp.isAfter(before) || event.timestamp.isAtSameMomentAs(before), isTrue);
      expect(event.timestamp.isBefore(after) || event.timestamp.isAtSameMomentAs(after), isTrue);
    });

    test('all type checks work', () {
      final types = {
        'health_changed': (CortexEvent e) => e.isHealthChanged,
        'degraded_changed': (CortexEvent e) => e.isDegradedChanged,
        'pattern_recognized': (CortexEvent e) => e.isPatternRecognized,
        'reflex_fired': (CortexEvent e) => e.isReflexFired,
        'command_dispatched': (CortexEvent e) => e.isCommandDispatched,
        'immune_escalation': (CortexEvent e) => e.isImmuneEscalation,
        'chronic_changed': (CortexEvent e) => e.isChronicChanged,
        'awareness_updated': (CortexEvent e) => e.isAwarenessUpdated,
        'healing_complete': (CortexEvent e) => e.isHealingComplete,
        'signal_milestone': (CortexEvent e) => e.isSignalMilestone,
      };
      for (final entry in types.entries) {
        final event = CortexEvent.fromJson({'event_type': entry.key});
        expect(entry.value(event), isTrue, reason: '${entry.key} check should be true');
      }
    });
  });

  group('CortexReflexInfo', () {
    test('fromJson parses correctly', () {
      final r = CortexReflexInfo.fromJson({
        'name': 'buffer-underrun-alert',
        'fire_count': 42,
        'enabled': true,
      });
      expect(r.name, 'buffer-underrun-alert');
      expect(r.fireCount, 42);
      expect(r.enabled, isTrue);
    });

    test('fromJson handles missing fields', () {
      final r = CortexReflexInfo.fromJson({});
      expect(r.name, '');
      expect(r.fireCount, 0);
      expect(r.enabled, isFalse);
    });
  });

  group('CortexPatternInfo', () {
    test('fromJson parses correctly', () {
      final p = CortexPatternInfo.fromJson({
        'name': 'repeated-underruns',
        'severity': 0.9,
        'description': '3+ underruns in 10s',
      });
      expect(p.name, 'repeated-underruns');
      expect(p.severity, 0.9);
      expect(p.description, '3+ underruns in 10s');
    });
  });

  group('CortexAntibodyInfo', () {
    test('fromJson parses all fields', () {
      final ab = CortexAntibodyInfo.fromJson({
        'category': 'audio.underrun',
        'count': 7,
        'escalation_level': 2,
        'max_severity': 0.85,
        'is_chronic': false,
      });
      expect(ab.category, 'audio.underrun');
      expect(ab.count, 7);
      expect(ab.escalationLevel, 2);
      expect(ab.maxSeverity, 0.85);
      expect(ab.isChronic, isFalse);
    });

    test('escalationLabel returns correct labels', () {
      expect(CortexAntibodyInfo.fromJson({'escalation_level': 0}).escalationLabel, 'Normal');
      expect(CortexAntibodyInfo.fromJson({'escalation_level': 1}).escalationLabel, 'Elevated');
      expect(CortexAntibodyInfo.fromJson({'escalation_level': 2}).escalationLabel, 'High');
      expect(CortexAntibodyInfo.fromJson({'escalation_level': 3}).escalationLabel, 'Critical');
      expect(CortexAntibodyInfo.fromJson({'escalation_level': 4}).escalationLabel, 'Critical');
    });
  });

  group('CortexExecutionInfo', () {
    test('fromJson parses correctly', () {
      final ex = CortexExecutionInfo.fromJson({
        'action_tag': 'AdjustBufferSize',
        'reason': 'Buffer underrun escalation L1',
        'priority': 'High',
        'result': 'Executed',
        'healing_detail': 'Buffer size increased to 512',
        'healed': true,
      });
      expect(ex.actionTag, 'AdjustBufferSize');
      expect(ex.reason, 'Buffer underrun escalation L1');
      expect(ex.priority, 'High');
      expect(ex.result, 'Executed');
      expect(ex.healingDetail, 'Buffer size increased to 512');
      expect(ex.healed, isTrue);
    });

    test('fromJson handles missing fields', () {
      final ex = CortexExecutionInfo.fromJson({});
      expect(ex.actionTag, '');
      expect(ex.healed, isFalse);
    });
  });
}
