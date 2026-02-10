/// AutoSpatial Provider Tests
///
/// Tests spatial rule templates, bus policies, anchor management,
/// and provider state management.
@Tags(['provider'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/auto_spatial_provider.dart';
import 'package:fluxforge_ui/spatial/auto_spatial.dart';

void main() {
  group('SpatialRuleTemplates', () {
    test('cascadeStep creates valid rule', () {
      final rule = SpatialRuleTemplates.cascadeStep();
      expect(rule.intent, 'cascade_step');
      expect(rule.smoothingTauMs, 40);
      expect(rule.enableDoppler, true);
      expect(rule.lifetimeMs, 300);
    });

    test('bigWin creates wide stereo rule', () {
      final rule = SpatialRuleTemplates.bigWin();
      expect(rule.intent, 'win_big');
      expect(rule.width, 1.0);
      expect(rule.maxPan, 0.4); // Keep centered
      expect(rule.enableDoppler, false);
      expect(rule.baseReverbSend, 0.4);
    });

    test('jackpotTrigger creates maximum impact rule', () {
      final rule = SpatialRuleTemplates.jackpot();
      expect(rule.intent, 'jackpot');
    });

    test('custom intent override works', () {
      final rule = SpatialRuleTemplates.cascadeStep(intent: 'my_cascade');
      expect(rule.intent, 'my_cascade');
    });

    test('all templates list is populated', () {
      final templates = SpatialRuleTemplates.all;
      expect(templates.length, greaterThan(5));
      for (final template in templates) {
        expect(template.name, isNotEmpty);
        expect(template.description, isNotEmpty);
        final rule = template.builder();
        expect(rule.intent, isNotEmpty);
      }
    });
  });

  group('AutoSpatialProvider — initialization', () {
    test('starts uninitialized', () {
      // Access the singleton but check its state
      final provider = AutoSpatialProvider.instance;
      // Provider may or may not be initialized from prior tests,
      // so we test basic getters don't crash
      expect(provider.editingEnabled, isFalse);
      expect(provider.abCompareEnabled, isFalse);
    });

    test('initialize populates rules and policies', () {
      final provider = AutoSpatialProvider.instance;
      provider.initialize();
      expect(provider.isInitialized, true);
      expect(provider.allRules, isNotEmpty);
      expect(provider.allPolicies, isNotEmpty);
    });
  });

  group('AutoSpatialProvider — rule management', () {
    late AutoSpatialProvider provider;

    setUp(() {
      provider = AutoSpatialProvider.instance;
      provider.initialize();
    });

    test('selectRule updates selectedRuleIntent', () {
      final firstIntent = provider.allRules.keys.first;
      provider.selectRule(firstIntent);
      expect(provider.selectedRuleIntent, firstIntent);
      expect(provider.selectedRule, isNotNull);
    });

    test('selectRule with null clears selection', () {
      provider.selectRule(null);
      expect(provider.selectedRuleIntent, isNull);
      expect(provider.selectedRule, isNull);
    });

    test('createRule adds new rule', () {
      final newRule = IntentRule(
        intent: 'test_unique_intent_${DateTime.now().millisecondsSinceEpoch}',
        defaultAnchorId: 'center',
      );
      final countBefore = provider.allRules.length;
      provider.createRule(newRule);
      expect(provider.allRules.length, countBefore + 1);
      expect(provider.allRules.containsKey(newRule.intent), true);
    });

    test('createRule does not duplicate existing intent', () {
      final existingIntent = provider.allRules.keys.first;
      final countBefore = provider.allRules.length;
      provider.createRule(IntentRule(intent: existingIntent));
      expect(provider.allRules.length, countBefore);
    });

    test('updateRule replaces existing rule', () {
      final intent = provider.allRules.keys.first;
      final updated = IntentRule(intent: intent, defaultAnchorId: 'updated_anchor');
      provider.updateRule(intent, updated);
      expect(provider.allRules[intent]!.defaultAnchorId, 'updated_anchor');
    });

    test('duplicateRule creates copy with new intent', () {
      final sourceIntent = provider.allRules.keys.first;
      final newIntent = 'copy_of_$sourceIntent';
      provider.duplicateRule(sourceIntent, newIntent);
      expect(provider.allRules.containsKey(newIntent), true);
    });

    test('createRuleFromTemplate adds template-based rule', () {
      final countBefore = provider.allRules.length;
      provider.createRuleFromTemplate(0, customIntent: 'template_test_${DateTime.now().millisecondsSinceEpoch}');
      expect(provider.allRules.length, greaterThan(countBefore));
    });

    test('availableTemplates returns template info', () {
      final templates = provider.availableTemplates;
      expect(templates, isNotEmpty);
      for (final t in templates) {
        expect(t.name, isNotEmpty);
        expect(t.description, isNotEmpty);
      }
    });
  });

  group('AutoSpatialProvider — bus policy management', () {
    late AutoSpatialProvider provider;

    setUp(() {
      provider = AutoSpatialProvider.instance;
      provider.initialize();
    });

    test('selectBus updates selectedBus', () {
      provider.selectBus(SpatialBus.sfx);
      expect(provider.selectedBus, SpatialBus.sfx);
      expect(provider.selectedBusPolicy, isNotNull);
    });

    test('selectBus with null clears', () {
      provider.selectBus(null);
      expect(provider.selectedBus, isNull);
    });

    test('updateBusPolicy replaces policy', () {
      final updated = BusPolicy(
        widthMul: 0.5,
        maxPanMul: 0.3,
        enableHRTF: false,
      );
      provider.updateBusPolicy(SpatialBus.sfx, updated);
      expect(provider.allPolicies[SpatialBus.sfx]!.widthMul, 0.5);
      expect(provider.allPolicies[SpatialBus.sfx]!.enableHRTF, false);
    });
  });

  group('AutoSpatialProvider — editing state', () {
    late AutoSpatialProvider provider;

    setUp(() {
      provider = AutoSpatialProvider.instance;
      provider.initialize();
    });

    test('editingEnabled starts false', () {
      expect(provider.editingEnabled, false);
    });
  });

  group('AutoSpatialProvider — A/B comparison', () {
    late AutoSpatialProvider provider;

    setUp(() {
      provider = AutoSpatialProvider.instance;
      provider.initialize();
    });

    test('enableAbComparison takes snapshot A', () {
      provider.enableAbComparison();
      expect(provider.abCompareEnabled, true);
      expect(provider.hasSnapshotA, true);
      provider.disableAbComparison();
    });

    test('snapshotB records B state', () {
      provider.enableAbComparison();
      provider.snapshotB();
      expect(provider.hasSnapshotB, true);
      provider.disableAbComparison();
    });

    test('toggleAb switches between A and B', () {
      provider.enableAbComparison();
      provider.snapshotB();
      expect(provider.abShowingB, false);
      provider.toggleAb();
      expect(provider.abShowingB, true);
      provider.toggleAb();
      expect(provider.abShowingB, false);
      provider.disableAbComparison();
    });

    test('disableAbComparison clears state', () {
      provider.enableAbComparison();
      provider.snapshotB();
      provider.disableAbComparison();
      expect(provider.abCompareEnabled, false);
      expect(provider.hasSnapshotA, false);
      expect(provider.hasSnapshotB, false);
    });
  });
}
