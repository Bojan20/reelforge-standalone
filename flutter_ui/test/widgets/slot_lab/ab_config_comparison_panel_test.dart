import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/slot_lab/ab_config_comparison_panel.dart';

void main() {
  group('SlotConfiguration', () {
    test('creates with required fields', () {
      final config = SlotConfiguration(
        id: 'test-1',
        name: 'Test Config',
        lastModified: DateTime(2026, 2, 2),
        grid: const SlotGridConfig(reels: 5, rows: 3, paylines: 10, mechanic: 'lines'),
        symbols: const [],
        winTiers: const SlotWinTierConfig(
          bigWinThreshold: 20.0,
          megaWinThreshold: 50.0,
          epicWinThreshold: 100.0,
          rollupDurationMs: 2500,
        ),
        audioAssignments: const {},
      );

      expect(config.id, 'test-1');
      expect(config.name, 'Test Config');
      expect(config.grid.reels, 5);
      expect(config.winTiers.bigWinThreshold, 20.0);
    });

    test('toJson and fromJson roundtrip', () {
      final original = SlotConfiguration(
        id: 'test-1',
        name: 'Test Config',
        lastModified: DateTime(2026, 2, 2),
        grid: const SlotGridConfig(reels: 5, rows: 3, paylines: 10, mechanic: 'lines'),
        symbols: const [
          SlotSymbolConfig(id: 'HP1', name: 'High Pay 1', type: 'high', payouts: {3: 10.0, 4: 20.0, 5: 50.0}),
        ],
        winTiers: const SlotWinTierConfig(
          bigWinThreshold: 20.0,
          megaWinThreshold: 50.0,
          epicWinThreshold: 100.0,
          rollupDurationMs: 2500,
        ),
        audioAssignments: const {'SPIN_START': 'spin.wav'},
      );

      final json = original.toJson();
      final restored = SlotConfiguration.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.grid.reels, original.grid.reels);
      expect(restored.symbols.length, original.symbols.length);
      expect(restored.audioAssignments['SPIN_START'], 'spin.wav');
    });

    test('copyWith creates modified copy', () {
      final original = SlotConfiguration(
        id: 'test-1',
        name: 'Original',
        lastModified: DateTime(2026, 2, 2),
        grid: const SlotGridConfig(reels: 5, rows: 3, paylines: 10, mechanic: 'lines'),
        symbols: const [],
        winTiers: const SlotWinTierConfig(
          bigWinThreshold: 20.0,
          megaWinThreshold: 50.0,
          epicWinThreshold: 100.0,
          rollupDurationMs: 2500,
        ),
        audioAssignments: const {},
      );

      final modified = original.copyWith(name: 'Modified');

      expect(modified.name, 'Modified');
      expect(modified.id, original.id);
      expect(original.name, 'Original');
    });
  });

  group('SlotGridConfig', () {
    test('equality check works correctly', () {
      const grid1 = SlotGridConfig(reels: 5, rows: 3, paylines: 10, mechanic: 'lines');
      const grid2 = SlotGridConfig(reels: 5, rows: 3, paylines: 10, mechanic: 'lines');
      const grid3 = SlotGridConfig(reels: 6, rows: 3, paylines: 10, mechanic: 'lines');

      expect(grid1 == grid2, isTrue);
      expect(grid1 == grid3, isFalse);
    });

    test('hashCode is consistent', () {
      const grid1 = SlotGridConfig(reels: 5, rows: 3, paylines: 10, mechanic: 'lines');
      const grid2 = SlotGridConfig(reels: 5, rows: 3, paylines: 10, mechanic: 'lines');

      expect(grid1.hashCode, grid2.hashCode);
    });
  });

  group('SlotWinTierConfig', () {
    test('equality check works correctly', () {
      const tiers1 = SlotWinTierConfig(
        bigWinThreshold: 20.0,
        megaWinThreshold: 50.0,
        epicWinThreshold: 100.0,
        rollupDurationMs: 2500,
      );
      const tiers2 = SlotWinTierConfig(
        bigWinThreshold: 20.0,
        megaWinThreshold: 50.0,
        epicWinThreshold: 100.0,
        rollupDurationMs: 2500,
      );
      const tiers3 = SlotWinTierConfig(
        bigWinThreshold: 25.0,
        megaWinThreshold: 50.0,
        epicWinThreshold: 100.0,
        rollupDurationMs: 2500,
      );

      expect(tiers1 == tiers2, isTrue);
      expect(tiers1 == tiers3, isFalse);
    });
  });

  group('ConfigDiff', () {
    test('creates with all diff types', () {
      const addedDiff = ConfigDiff(
        category: 'symbols',
        path: 'symbols.HP1',
        type: DiffType.added,
        valueB: 'HP1',
      );

      const removedDiff = ConfigDiff(
        category: 'symbols',
        path: 'symbols.HP2',
        type: DiffType.removed,
        valueA: 'HP2',
      );

      const changedDiff = ConfigDiff(
        category: 'grid',
        path: 'grid.reels',
        type: DiffType.changed,
        valueA: 5,
        valueB: 6,
      );

      expect(addedDiff.type, DiffType.added);
      expect(removedDiff.type, DiffType.removed);
      expect(changedDiff.type, DiffType.changed);
    });
  });

  group('ABConfigComparisonPanel', () {
    testWidgets('displays empty state when no configs', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: ABConfigComparisonPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('A/B Configuration Comparison'), findsOneWidget);
      expect(find.text('No Config A'), findsOneWidget);
      expect(find.text('No Config B'), findsOneWidget);
    });

    testWidgets('displays config names when provided', (tester) async {
      final configA = SlotConfiguration(
        id: 'a',
        name: 'Config Alpha',
        lastModified: DateTime(2026, 2, 2),
        grid: const SlotGridConfig(reels: 5, rows: 3, paylines: 10, mechanic: 'lines'),
        symbols: const [],
        winTiers: const SlotWinTierConfig(
          bigWinThreshold: 20.0,
          megaWinThreshold: 50.0,
          epicWinThreshold: 100.0,
          rollupDurationMs: 2500,
        ),
        audioAssignments: const {},
      );

      final configB = SlotConfiguration(
        id: 'b',
        name: 'Config Beta',
        lastModified: DateTime(2026, 2, 2),
        grid: const SlotGridConfig(reels: 5, rows: 3, paylines: 10, mechanic: 'lines'),
        symbols: const [],
        winTiers: const SlotWinTierConfig(
          bigWinThreshold: 20.0,
          megaWinThreshold: 50.0,
          epicWinThreshold: 100.0,
          rollupDurationMs: 2500,
        ),
        audioAssignments: const {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: ABConfigComparisonPanel(
                configA: configA,
                configB: configB,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Config Alpha'), findsOneWidget);
      expect(find.text('Config Beta'), findsOneWidget);
    });

    testWidgets('shows category filter chips', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: ABConfigComparisonPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Grid'), findsOneWidget);
      expect(find.text('Symbols'), findsOneWidget);
      expect(find.text('Win Tiers'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);
    });

    testWidgets('copy buttons trigger callbacks', (tester) async {
      bool copyTriggered = false;

      final configA = SlotConfiguration(
        id: 'a',
        name: 'Config A',
        lastModified: DateTime(2026, 2, 2),
        grid: const SlotGridConfig(reels: 5, rows: 3, paylines: 10, mechanic: 'lines'),
        symbols: const [],
        winTiers: const SlotWinTierConfig(
          bigWinThreshold: 20.0,
          megaWinThreshold: 50.0,
          epicWinThreshold: 100.0,
          rollupDurationMs: 2500,
        ),
        audioAssignments: const {},
      );

      final configB = configA.copyWith(id: 'b', name: 'Config B');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: ABConfigComparisonPanel(
                configA: configA,
                configB: configB,
                onCopySettings: (from, to) => copyTriggered = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Copy A to B'));
      await tester.pumpAndSettle();

      expect(copyTriggered, isTrue);
    });

    testWidgets('shows difference count badge', (tester) async {
      final configA = SlotConfiguration(
        id: 'a',
        name: 'Config A',
        lastModified: DateTime(2026, 2, 2),
        grid: const SlotGridConfig(reels: 5, rows: 3, paylines: 10, mechanic: 'lines'),
        symbols: const [],
        winTiers: const SlotWinTierConfig(
          bigWinThreshold: 20.0,
          megaWinThreshold: 50.0,
          epicWinThreshold: 100.0,
          rollupDurationMs: 2500,
        ),
        audioAssignments: const {},
      );

      final configB = SlotConfiguration(
        id: 'b',
        name: 'Config B',
        lastModified: DateTime(2026, 2, 2),
        grid: const SlotGridConfig(reels: 6, rows: 4, paylines: 20, mechanic: 'ways'),
        symbols: const [],
        winTiers: const SlotWinTierConfig(
          bigWinThreshold: 25.0,
          megaWinThreshold: 60.0,
          epicWinThreshold: 120.0,
          rollupDurationMs: 3000,
        ),
        audioAssignments: const {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: ABConfigComparisonPanel(
                configA: configA,
                configB: configB,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show differences text
      expect(find.textContaining('differences'), findsOneWidget);
    });

    testWidgets('differences only toggle works', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: ABConfigComparisonPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Differences only'), findsOneWidget);

      // Find and tap the switch
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      // Toggle should now be on
    });
  });

  group('DiffType', () {
    test('has all required values', () {
      expect(DiffType.values, contains(DiffType.added));
      expect(DiffType.values, contains(DiffType.removed));
      expect(DiffType.values, contains(DiffType.changed));
      expect(DiffType.values, contains(DiffType.unchanged));
      expect(DiffType.values.length, 4);
    });
  });
}
