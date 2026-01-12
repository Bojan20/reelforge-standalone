// FluxForge Studio UI Widget Test
//
// Basic smoke test for the FluxForge Studio DAW Flutter UI

import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge_ui/main.dart';

void main() {
  testWidgets('FluxForge Studio app launches', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FluxForgeApp());

    // Verify that the app title is present
    expect(find.text('FluxForge Studio DAW'), findsOneWidget);
  });
}
