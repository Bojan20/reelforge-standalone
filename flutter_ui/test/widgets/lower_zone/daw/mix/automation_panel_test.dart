/// Automation Panel Tests (P0.4)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/lower_zone/daw/mix/automation_panel.dart';

void main() {
  group('AutomationPanel', () {
    testWidgets('shows no track selected when null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AutomationPanel(selectedTrackId: null),
          ),
        ),
      );

      expect(find.text('No Track Selected'), findsOneWidget);
    });

    testWidgets('shows track name when track selected', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AutomationPanel(selectedTrackId: 5),
          ),
        ),
      );

      expect(find.text('Track 5'), findsOneWidget);
    });

    testWidgets('displays automation header', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AutomationPanel(selectedTrackId: 1),
          ),
        ),
      );

      expect(find.text('AUTOMATION'), findsOneWidget);
    });

    testWidgets('shows mode selector with Read default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AutomationPanel(selectedTrackId: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default mode is Read
      expect(find.text('Read'), findsOneWidget);
    });

    testWidgets('shows parameter selector with Volume default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AutomationPanel(selectedTrackId: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default parameter is Volume
      expect(find.text('Volume'), findsOneWidget);
    });

    testWidgets('displays automation icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AutomationPanel(selectedTrackId: 1),
          ),
        ),
      );

      expect(find.byIcon(Icons.auto_graph), findsOneWidget);
    });
  });
}
