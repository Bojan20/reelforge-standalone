import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_studio/widgets/slot_lab/memory_usage_panel.dart';

void main() {
  group('MemoryUsagePanel', () {
    testWidgets('renders header and usage bar', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MemoryUsagePanel(),
            ),
          ),
        ),
      );

      // Header should be present
      expect(find.text('MEMORY USAGE'), findsOneWidget);

      // Should show MB display
      expect(find.textContaining('MB'), findsWidgets);
    });

    testWidgets('shows category breakdown when enabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 500,
              child: MemoryUsagePanel(showBreakdown: true),
            ),
          ),
        ),
      );

      // Category labels should be present
      expect(find.text('Audio'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);
      expect(find.text('Containers'), findsOneWidget);
      expect(find.text('Streaming'), findsOneWidget);
      expect(find.text('Cache'), findsOneWidget);
    });

    testWidgets('compact mode shows minimal UI', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 60,
              child: MemoryUsagePanel(compactMode: true),
            ),
          ),
        ),
      );

      // Should show MB value
      expect(find.textContaining('MB'), findsOneWidget);

      // Should NOT show full header
      expect(find.text('MEMORY USAGE'), findsNothing);
    });

    testWidgets('pause button toggles refresh', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MemoryUsagePanel(),
            ),
          ),
        ),
      );

      // Find pause button
      final pauseButton = find.byTooltip('Pause');
      expect(pauseButton, findsOneWidget);

      // Tap to pause
      await tester.tap(pauseButton);
      await tester.pump();

      // Should now show resume tooltip
      expect(find.byTooltip('Resume'), findsOneWidget);
    });

    testWidgets('custom budget changes display', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MemoryUsagePanel(
                totalBudgetBytes: 256 * 1024 * 1024, // 256MB
              ),
            ),
          ),
        ),
      );

      // Should show 256 MB in display
      expect(find.textContaining('256'), findsOneWidget);
    });
  });

  group('MemoryCategory', () {
    test('audio category has correct properties', () {
      expect(MemoryCategory.audio.label, equals('Audio'));
      expect(MemoryCategory.audio.icon, equals(Icons.audiotrack));
    });

    test('all categories have unique labels', () {
      final labels = MemoryCategory.values.map((c) => c.label).toSet();
      expect(labels.length, equals(MemoryCategory.values.length));
    });

    test('all categories have icons and colors', () {
      for (final category in MemoryCategory.values) {
        expect(category.icon, isNotNull);
        expect(category.color, isNot(Colors.transparent));
      }
    });
  });

  group('MemoryCategoryData', () {
    test('usedMb calculates correctly', () {
      const data = MemoryCategoryData(
        category: MemoryCategory.audio,
        usedBytes: 10 * 1024 * 1024, // 10MB
        budgetBytes: 50 * 1024 * 1024,
      );

      expect(data.usedMb, closeTo(10.0, 0.01));
    });

    test('percent calculates correctly', () {
      const data = MemoryCategoryData(
        category: MemoryCategory.audio,
        usedBytes: 25 * 1024 * 1024, // 25MB
        budgetBytes: 100 * 1024 * 1024, // 100MB
      );

      expect(data.percent, closeTo(0.25, 0.01));
    });

    test('isWarning returns true above threshold', () {
      const data = MemoryCategoryData(
        category: MemoryCategory.audio,
        usedBytes: 80 * 1024 * 1024, // 80MB
        budgetBytes: 100 * 1024 * 1024, // 100MB = 80%
      );

      expect(data.isWarning, isTrue);
    });

    test('isCritical returns true above 90%', () {
      const data = MemoryCategoryData(
        category: MemoryCategory.audio,
        usedBytes: 95 * 1024 * 1024, // 95MB
        budgetBytes: 100 * 1024 * 1024, // 100MB = 95%
      );

      expect(data.isCritical, isTrue);
    });

    test('handles zero budget without division error', () {
      const data = MemoryCategoryData(
        category: MemoryCategory.audio,
        usedBytes: 10 * 1024 * 1024,
        budgetBytes: 0,
      );

      expect(data.percent, equals(0.0));
    });
  });
}
