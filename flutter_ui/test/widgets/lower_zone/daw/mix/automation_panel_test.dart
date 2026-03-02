/// Automation Panel Tests (P0.4)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:fluxforge_ui/providers/automation_provider.dart';
import 'package:fluxforge_ui/widgets/lower_zone/daw/mix/automation_panel.dart';

void main() {
  setUp(() {
    final sl = GetIt.instance;
    if (!sl.isRegistered<AutomationProvider>()) {
      sl.registerLazySingleton<AutomationProvider>(
        () => AutomationProvider(),
      );
    }
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  group('AutomationPanel', () {
    testWidgets('shows no track selected when null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AutomationPanel(selectedTrackId: null),
          ),
        ),
      );

      // When no track is selected, the header shows 'No Track Selected' in the track indicator
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

      // Default mode is Read — the mode chip labels include Read, Write, Touch
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

      // Default parameter is Volume — shown in the parameter dropdown
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
