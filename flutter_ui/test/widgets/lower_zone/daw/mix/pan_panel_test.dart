/// Pan Panel Tests (P0.4)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/lower_zone/daw/mix/pan_panel.dart';

void main() {
  group('PanPanel', () {
    testWidgets('shows no track selected when null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PanPanel(selectedTrackId: null),
          ),
        ),
      );

      expect(find.text('No track selected'), findsOneWidget);
    });

    testWidgets('shows stereo panner header by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PanPanel(selectedTrackId: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default is stereo panner
      expect(find.text('STEREO PANNER'), findsOneWidget);
    });

    testWidgets('displays pan law selector', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PanPanel(selectedTrackId: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pan law label should be visible (with colon)
      expect(find.text('Pan Law:'), findsOneWidget);
      // Default pan law is -3dB
      expect(find.text('-3dB'), findsOneWidget);
    });

    testWidgets('shows width control section', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PanPanel(selectedTrackId: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Width section should be visible for stereo tracks (uppercase)
      expect(find.text('WIDTH'), findsOneWidget);
    });
  });
}
