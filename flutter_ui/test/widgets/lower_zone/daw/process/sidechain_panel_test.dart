/// Sidechain Panel Tests (P0.5)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/lower_zone/daw/process/sidechain_panel.dart';

void main() {
  group('SidechainPanel', () {
    testWidgets('shows no track selected when null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SidechainPanel(selectedTrackId: null),
          ),
        ),
      );

      expect(find.text('No Track Selected'), findsOneWidget);
      expect(find.text('Select a track to configure sidechain'), findsOneWidget);
      expect(find.byIcon(Icons.call_split), findsOneWidget);
    });

    testWidgets('renders sidechain panel when track selected', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SidechainPanel(selectedTrackId: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should not show empty state
      expect(find.text('No Track Selected'), findsNothing);
    });

    testWidgets('uses provided sources when available', (tester) async {
      const sources = [
        SidechainSourceOption(
          id: 1,
          name: 'Kick Track',
          type: SidechainSourceType.track,
        ),
        SidechainSourceOption(
          id: 2,
          name: 'Master Bus',
          type: SidechainSourceType.bus,
        ),
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SidechainPanel(
              selectedTrackId: 0,
              availableSources: sources,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should render without errors
      expect(find.text('No Track Selected'), findsNothing);
    });

    testWidgets('supports all source types', (tester) async {
      const sources = [
        SidechainSourceOption(
          id: 0,
          name: 'Internal',
          type: SidechainSourceType.internal,
        ),
        SidechainSourceOption(
          id: 1,
          name: 'Track 2',
          type: SidechainSourceType.track,
        ),
        SidechainSourceOption(
          id: 2,
          name: 'Master',
          type: SidechainSourceType.bus,
        ),
        SidechainSourceOption(
          id: 3,
          name: 'External In',
          type: SidechainSourceType.external,
        ),
        SidechainSourceOption(
          id: 4,
          name: 'Mid',
          type: SidechainSourceType.mid,
        ),
        SidechainSourceOption(
          id: 5,
          name: 'Side',
          type: SidechainSourceType.side,
        ),
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SidechainPanel(
              selectedTrackId: 0,
              availableSources: sources,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should render without errors for all source types
      expect(find.text('No Track Selected'), findsNothing);
    });
  });

  group('SidechainSourceOption', () {
    test('creates with required fields', () {
      const option = SidechainSourceOption(
        id: 1,
        name: 'Test Source',
        type: SidechainSourceType.track,
      );

      expect(option.id, 1);
      expect(option.name, 'Test Source');
      expect(option.type, SidechainSourceType.track);
    });
  });

  group('SidechainSourceType', () {
    test('has all expected values', () {
      expect(SidechainSourceType.values.length, 6);
      expect(SidechainSourceType.values, contains(SidechainSourceType.internal));
      expect(SidechainSourceType.values, contains(SidechainSourceType.track));
      expect(SidechainSourceType.values, contains(SidechainSourceType.bus));
      expect(SidechainSourceType.values, contains(SidechainSourceType.external));
      expect(SidechainSourceType.values, contains(SidechainSourceType.mid));
      expect(SidechainSourceType.values, contains(SidechainSourceType.side));
    });
  });
}
