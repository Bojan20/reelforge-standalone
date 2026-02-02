/// Group Manager Panel Tests (P10.1.20)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:fluxforge_ui/providers/mixer_provider.dart';
import 'package:fluxforge_ui/widgets/mixer/group_manager_panel.dart';

void main() {
  group('GroupManagerPanel', () {
    late MixerProvider mixerProvider;

    setUp(() {
      mixerProvider = MixerProvider();
    });

    Widget buildTestWidget({Widget? child}) {
      return MaterialApp(
        home: ChangeNotifierProvider<MixerProvider>.value(
          value: mixerProvider,
          child: Scaffold(
            body: SizedBox(
              width: 300,
              height: 400,
              child: child ?? const GroupManagerPanel(),
            ),
          ),
        ),
      );
    }

    testWidgets('displays empty state when no groups', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('No Groups'), findsOneWidget);
      expect(find.text('Create a group to organize tracks'), findsOneWidget);
    });

    testWidgets('displays header with add button', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Track Groups'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows create group dialog on add tap', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('Create Group'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('creates group via dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Open dialog
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Enter name
      await tester.enterText(find.byType(TextField), 'Drums');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // Verify group created
      expect(mixerProvider.groups.length, 1);
      expect(mixerProvider.groups.first.name, 'Drums');
    });

    testWidgets('displays group with member count', (tester) async {
      mixerProvider.createGroup(name: 'Vocals');
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Vocals'), findsOneWidget);
      expect(find.text('0'), findsOneWidget); // Member count badge
    });

    testWidgets('shows link toggles for group', (tester) async {
      mixerProvider.createGroup(name: 'Test Group');
      await tester.pumpWidget(buildTestWidget());

      // Expand group to show link toggles
      expect(find.text('Vol'), findsOneWidget);
      expect(find.text('Pan'), findsOneWidget);
      expect(find.text('M'), findsOneWidget); // Mute
      expect(find.text('S'), findsOneWidget); // Solo
    });

    testWidgets('shows delete confirmation dialog', (tester) async {
      mixerProvider.createGroup(name: 'Delete Me');
      await tester.pumpWidget(buildTestWidget());

      // Find and tap delete button
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Delete Group'), findsOneWidget);
      expect(find.text('Delete "Delete Me"? Tracks will be ungrouped.'),
          findsOneWidget);
    });

    testWidgets('deletes group via confirmation', (tester) async {
      mixerProvider.createGroup(name: 'Delete Me');
      expect(mixerProvider.groups.length, 1);

      await tester.pumpWidget(buildTestWidget());

      // Delete via dialog
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(mixerProvider.groups.length, 0);
    });

    testWidgets('toggles group link parameter', (tester) async {
      final group = mixerProvider.createGroup(name: 'Link Test');
      expect(group.linkVolume, true); // Default is true

      await tester.pumpWidget(buildTestWidget());

      // Find and tap Vol toggle
      await tester.tap(find.text('Vol'));
      await tester.pumpAndSettle();

      // Volume link should now be toggled
      final updatedGroup = mixerProvider.getGroup(group.id);
      expect(updatedGroup?.linkVolume, false);
    });

    testWidgets('compact mode hides ungrouped section', (tester) async {
      mixerProvider.createChannel(name: 'Track 1');

      await tester
          .pumpWidget(buildTestWidget(child: const GroupManagerPanel(compact: true)));

      expect(find.text('Ungrouped Tracks'), findsNothing);
    });
  });
}
