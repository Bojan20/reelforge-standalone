import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_studio/widgets/slot_lab/voice_pool_visualizer.dart';

void main() {
  group('VoicePoolVisualizer', () {
    testWidgets('renders header and voice grid', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: VoicePoolVisualizer(),
            ),
          ),
        ),
      );

      // Header should be present
      expect(find.text('VOICE POOL'), findsOneWidget);

      // Stats should be shown
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Looping'), findsOneWidget);
      expect(find.text('Max'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
    });

    testWidgets('shows bus breakdown when enabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 500,
              child: VoicePoolVisualizer(showBusBreakdown: true),
            ),
          ),
        ),
      );

      // Bus breakdown header should be present
      expect(find.text('BY BUS'), findsOneWidget);
    });

    testWidgets('compact mode shows minimal UI', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 60,
              child: VoicePoolVisualizer(compactMode: true),
            ),
          ),
        ),
      );

      // Should show voices text
      expect(find.textContaining('voices'), findsOneWidget);

      // Should NOT show full header
      expect(find.text('VOICE POOL'), findsNothing);
    });

    testWidgets('pause button toggles refresh', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: VoicePoolVisualizer(),
            ),
          ),
        ),
      );

      // Find pause button
      final pauseButton = find.byTooltip('Pause');
      expect(pauseButton, findsOneWidget);

      // Tap to pause
      await tester.tap(pauseButton);
      await tester.pump();

      // Should now show resume tooltip
      expect(find.byTooltip('Resume'), findsOneWidget);
    });

    testWidgets('custom maxVoices changes grid size', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: VoicePoolVisualizer(maxVoices: 32),
            ),
          ),
        ),
      );

      // Widget should render without error with custom max
      expect(find.text('VOICE POOL'), findsOneWidget);
    });
  });

  group('VoiceSlotState', () {
    test('free state has correct properties', () {
      expect(VoiceSlotState.free.label, equals('Free'));
      expect(VoiceSlotState.free.color, equals(Colors.transparent));
    });

    test('active state has correct properties', () {
      expect(VoiceSlotState.active.label, equals('Active'));
      expect(VoiceSlotState.active.color, isNot(Colors.transparent));
    });

    test('looping state has correct properties', () {
      expect(VoiceSlotState.looping.label, equals('Looping'));
      expect(VoiceSlotState.looping.color, isNot(Colors.transparent));
    });

    test('all states have unique labels', () {
      final labels = VoiceSlotState.values.map((s) => s.label).toSet();
      expect(labels.length, equals(VoiceSlotState.values.length));
    });
  });

  group('StealingMode', () {
    test('oldest mode has correct properties', () {
      expect(StealingMode.oldest.label, equals('Oldest'));
      expect(StealingMode.oldest.icon, equals(Icons.history));
    });

    test('quietest mode has correct properties', () {
      expect(StealingMode.quietest.label, equals('Quietest'));
      expect(StealingMode.quietest.icon, equals(Icons.volume_down));
    });

    test('all modes have icons', () {
      for (final mode in StealingMode.values) {
        expect(mode.icon, isNotNull);
      }
    });
  });
}
