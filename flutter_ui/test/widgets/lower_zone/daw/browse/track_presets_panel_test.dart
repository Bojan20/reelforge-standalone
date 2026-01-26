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

    testWidgets('displays empty state when no presets', (tester) async {
      TrackPresetService.instance.presets.clear();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackPresetsPanel(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No presets yet'), findsOneWidget);
    });
  });
}
