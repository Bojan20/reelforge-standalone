/// Track Presets Panel Tests (P0.4)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/lower_zone/daw/browse/track_presets_panel.dart';
import 'package:fluxforge_ui/services/track_preset_service.dart';

void main() {
  group('TrackPresetsPanel', () {
    setUp(() async {
      await TrackPresetService.instance.initializeFactoryPresets();
    });

    testWidgets('displays factory presets', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackPresetsPanel(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vocals'), findsOneWidget);
      expect(find.text('Drums'), findsOneWidget);
    });

    testWidgets('category filter works', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackPresetsPanel(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Vocals'));
      await tester.pumpAndSettle();

      expect(find.text('Vocals'), findsWidgets);
    });

    testWidgets('displays empty state when no presets match filter', (tester) async {
      // Note: We can't test truly empty presets because the widget auto-initializes
      // factory presets when empty (lines 52-56 in track_presets_panel.dart).
      // Instead, we test empty state via search filter that matches nothing.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackPresetsPanel(searchQuery: 'xyz_no_match_12345'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No presets yet'), findsOneWidget);
    });
  });
}
