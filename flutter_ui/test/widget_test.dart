// ReelForge UI Widget Test
//
// Basic smoke test for the ReelForge DAW Flutter UI

import 'package:flutter_test/flutter_test.dart';

import 'package:reelforge_ui/main.dart';

void main() {
  testWidgets('ReelForge app launches', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ReelForgeApp());

    // Verify that the app title is present
    expect(find.text('ReelForge DAW'), findsOneWidget);
  });
}
