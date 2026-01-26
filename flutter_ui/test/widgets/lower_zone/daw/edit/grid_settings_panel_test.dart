/// Grid Settings Panel Tests (P0.4)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/lower_zone/daw/edit/grid_settings_panel.dart';

void main() {
  group('GridSettingsPanel', () {
    testWidgets('displays tempo correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GridSettingsPanel(tempo: 140.0),
          ),
        ),
      );

      expect(find.text('140.0 BPM'), findsOneWidget);
    });

    testWidgets('displays time signature', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GridSettingsPanel(
              timeSignatureNumerator: 6,
              timeSignatureDenominator: 8,
            ),
          ),
        ),
      );

      expect(find.text('6'), findsWidgets);
      expect(find.text('8'), findsWidgets);
      expect(find.text('/'), findsOneWidget);
    });

    testWidgets('snap toggle shows correct state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GridSettingsPanel(snapEnabled: true),
          ),
        ),
      );

      expect(find.text('Snap Active'), findsOneWidget);
    });
  });
}
