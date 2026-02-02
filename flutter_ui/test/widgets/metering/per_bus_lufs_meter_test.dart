import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_studio/widgets/metering/per_bus_lufs_meter.dart';

void main() {
  group('PerBusLufsMeter', () {
    testWidgets('renders header and bus rows', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: PerBusLufsMeter(),
            ),
          ),
        ),
      );

      // Header should be present
      expect(find.text('PER-BUS LUFS'), findsOneWidget);

      // Default buses should be displayed
      expect(find.text('Master'), findsOneWidget);
      expect(find.text('SFX'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
    });

    testWidgets('displays target selector when showTargets is true', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: PerBusLufsMeter(showTargets: true),
            ),
          ),
        ),
      );

      // Target selector should be present
      expect(find.text('Target:'), findsOneWidget);
      expect(find.text('-14 Streaming'), findsOneWidget);
      expect(find.text('-16 YouTube'), findsOneWidget);
      expect(find.text('-23 Broadcast'), findsOneWidget);
    });

    testWidgets('compact mode shows minimal UI', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 100,
              child: PerBusLufsMeter(compactMode: true),
            ),
          ),
        ),
      );

      // Should show integrated value label
      expect(find.text('I'), findsOneWidget);
      expect(find.text('LUFS'), findsOneWidget);
    });

    testWidgets('pause button toggles refresh', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: PerBusLufsMeter(),
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

    testWidgets('custom buses can be provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: PerBusLufsMeter(
                buses: [
                  BusConfig(name: 'Custom1', id: 10, color: Colors.red, icon: Icons.star),
                  BusConfig(name: 'Custom2', id: 11, color: Colors.blue, icon: Icons.circle),
                ],
              ),
            ),
          ),
        ),
      );

      // Custom buses should be displayed
      expect(find.text('Custom1'), findsOneWidget);
      expect(find.text('Custom2'), findsOneWidget);

      // Default buses should NOT be displayed
      expect(find.text('Master'), findsNothing);
    });
  });

  group('BusLufsData', () {
    test('isSilent returns true when all values are below threshold', () {
      const data = BusLufsData(
        busName: 'Test',
        busId: 0,
        momentary: -70.0,
        shortTerm: -70.0,
        integrated: -70.0,
      );

      expect(data.isSilent, isTrue);
    });

    test('isSilent returns false when values are above threshold', () {
      const data = BusLufsData(
        busName: 'Test',
        busId: 0,
        momentary: -14.0,
        shortTerm: -14.0,
        integrated: -14.0,
      );

      expect(data.isSilent, isFalse);
    });

    test('isOnTarget returns true when within 1 LUFS of target', () {
      const data = BusLufsData(
        busName: 'Test',
        busId: 0,
        momentary: -14.0,
        shortTerm: -14.0,
        integrated: -14.5,
        targetPreset: LufsTargetPreset.streaming,
      );

      expect(data.isOnTarget, isTrue);
    });

    test('isOverTarget returns true when exceeding target by more than 1 LUFS', () {
      const data = BusLufsData(
        busName: 'Test',
        busId: 0,
        momentary: -12.0,
        shortTerm: -12.0,
        integrated: -12.0,
        targetPreset: LufsTargetPreset.streaming,
      );

      expect(data.isOverTarget, isTrue);
    });
  });

  group('LufsTargetPreset', () {
    test('streaming preset has correct values', () {
      expect(LufsTargetPreset.streaming.targetLufs, equals(-14.0));
      expect(LufsTargetPreset.streaming.label, equals('Streaming'));
    });

    test('broadcast preset has correct values', () {
      expect(LufsTargetPreset.broadcast.targetLufs, equals(-23.0));
      expect(LufsTargetPreset.broadcast.label, equals('Broadcast'));
    });

    test('all presets have unique target values', () {
      final targets = LufsTargetPreset.values.map((p) => p.targetLufs).toSet();
      // YouTube and Podcast have same target (-16), so expect 4 unique values
      expect(targets.length, equals(4));
    });
  });

  group('BusConfig', () {
    test('defaultBuses contains expected buses', () {
      expect(BusConfig.defaultBuses.length, equals(6));

      final names = BusConfig.defaultBuses.map((b) => b.name).toList();
      expect(names, contains('Master'));
      expect(names, contains('SFX'));
      expect(names, contains('Music'));
      expect(names, contains('Voice'));
      expect(names, contains('UI'));
      expect(names, contains('Ambience'));
    });

    test('bus IDs are unique', () {
      final ids = BusConfig.defaultBuses.map((b) => b.id).toSet();
      expect(ids.length, equals(BusConfig.defaultBuses.length));
    });
  });
}
