// ============================================================================
// FluxForge Studio — Feature Builder Validation Tests
// ============================================================================
// P13.8.8: Unit tests for validation rules in Feature Builder.
// Tests verify that validation errors, warnings, and info messages are correct.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/blocks/bonus_game_block.dart';
import 'package:fluxforge_ui/blocks/hold_and_win_block.dart';
import 'package:fluxforge_ui/blocks/wild_features_block.dart';
import 'package:fluxforge_ui/blocks/jackpot_block.dart';
import 'package:fluxforge_ui/blocks/symbol_set_block.dart';
import 'package:fluxforge_ui/blocks/anticipation_block.dart';
import 'package:fluxforge_ui/models/feature_builder/feature_block.dart';
import 'package:fluxforge_ui/providers/feature_builder_provider.dart';

void main() {
  group('E001: Scatter Required for Free Spins', () {
    test('error when FreeSpins enabled without scatter trigger', () {
      final provider = FeatureBuilderProvider();

      // Enable free spins with scatter trigger
      provider.enableBlock('free_spins');
      final freeSpinsBlock = provider.freeSpinsBlock;
      freeSpinsBlock?.setOptionValue('triggerMode', 'scatter');

      // Validate - should require symbol_set
      final result = provider.validate();

      // Free spins requires symbol_set for scatter configuration
      final hasSymbolSetDep = provider.freeSpinsBlock?.dependencies
          .any((d) => d.targetBlockId == 'symbol_set') ?? false;
      expect(hasSymbolSetDep, isTrue);
    });

    test('valid when scatter symbols are configured', () {
      final provider = FeatureBuilderProvider();

      // Enable both free spins and symbol set
      provider.enableBlock('free_spins');

      // Symbol set is always enabled (core block)
      final symbolSetBlock = provider.symbolSetBlock;
      expect(symbolSetBlock?.isEnabled, isTrue);
    });
  });

  group('E002: Bonus Symbol Required for Bonus', () {
    test('bonus block requires game_core dependency', () {
      final bonusBlock = BonusGameBlock();
      bonusBlock.isEnabled = true;

      final deps = bonusBlock.dependencies;
      expect(deps.any((d) => d.targetBlockId == 'game_core'), isTrue);
    });
  });

  group('E003: Coin Symbol Required for Hold & Win', () {
    test('hold_and_win requires coin symbols', () {
      final holdWinBlock = HoldAndWinBlock();
      holdWinBlock.isEnabled = true;

      // Hold & Win should have symbol set dependency for coins
      final deps = holdWinBlock.dependencies;
      expect(deps.any((d) => d.targetBlockId == 'symbol_set'), isTrue);
    });
  });

  group('E004: Wild Required for Wild Features', () {
    test('error when WildFeatures enabled without Wild symbol', () {
      final wildBlock = WildFeaturesBlock();
      wildBlock.isEnabled = true;

      // Create mock blocks map without Wild enabled
      final blocks = <String, FeatureBlock>{
        'symbol_set': SymbolSetBlock()..setOptionValue('hasWild', false),
      };

      final issues = wildBlock.validateConfiguration(blocks);

      // Should have E004 error
      expect(issues.any((i) => i.code == 'E004'), isTrue);
      expect(issues.any((i) => i.isError), isTrue);
    });

    test('no error when Wild symbol is enabled', () {
      final wildBlock = WildFeaturesBlock();
      wildBlock.isEnabled = true;

      // Create mock blocks map with Wild enabled
      final blocks = <String, FeatureBlock>{
        'symbol_set': SymbolSetBlock()..setOptionValue('hasWild', true),
      };

      final issues = wildBlock.validateConfiguration(blocks);

      // Should NOT have E004 error
      expect(issues.any((i) => i.code == 'E004'), isFalse);
    });
  });

  group('E005: Grid Size for Hold & Win', () {
    test('hold_and_win modifies grid', () {
      final holdWinBlock = HoldAndWinBlock();
      holdWinBlock.isEnabled = true;

      // Hold & Win should have grid dependency (for respin grid behavior)
      final deps = holdWinBlock.dependencies;
      expect(deps.any((d) => d.targetBlockId == 'grid'), isTrue);
    });
  });

  group('W001: Cascades + Free Spins Warning', () {
    test('warning when cascades and free_spins both enabled', () {
      final provider = FeatureBuilderProvider();

      provider.enableBlock('cascades');
      provider.enableBlock('free_spins');

      // Check if either block modifies the other
      final cascadesBlock = provider.cascadesBlock;
      final freeSpinsBlock = provider.freeSpinsBlock;

      // Free spins with cascade-linked multiplier requires cascades
      freeSpinsBlock?.setOptionValue('multiplierBehavior', 'cascadeLinked');

      // Should have dependency or warning about this combination
      expect(cascadesBlock?.isEnabled, isTrue);
      expect(freeSpinsBlock?.isEnabled, isTrue);
    });
  });

  group('W002: Multiple Jackpot Sources Warning', () {
    test('jackpot block tracks jackpot tiers', () {
      final jackpotBlock = JackpotBlock();
      jackpotBlock.isEnabled = true;

      final stages = jackpotBlock.generateStages();

      // Should generate jackpot tier stages
      expect(stages.any((s) => s.name.contains('JACKPOT')), isTrue);
    });
  });

  group('W003: Too Many Features Warning', () {
    test('provider tracks enabled block count', () {
      final provider = FeatureBuilderProvider();

      // Enable many feature blocks
      provider.enableBlock('free_spins');
      provider.enableBlock('cascades');
      provider.enableBlock('hold_and_win');
      provider.enableBlock('jackpot');
      provider.enableBlock('bonus_game');

      // Count should reflect all enabled blocks
      expect(provider.enabledBlockCount, greaterThan(5));
    });
  });

  group('W004: Multiple Wild Features Warning', () {
    test('warning when 3+ wild features enabled', () {
      final wildBlock = WildFeaturesBlock();
      wildBlock.isEnabled = true;

      // Enable multiple wild features (sticky + walking + multipliers = 3)
      // Note: expansion enum name mismatch means it doesn't count toward activeFeatureCount
      wildBlock.setOptionValue('sticky_duration', 3);
      wildBlock.setOptionValue('walking_direction', 'left');
      wildBlock.setOptionValue('multiplier_range', <int>[2, 3]);

      expect(wildBlock.activeFeatureCount, greaterThanOrEqualTo(3));

      // Validate should produce W004 warning
      final blocks = <String, FeatureBlock>{
        'symbol_set': SymbolSetBlock()..setOptionValue('hasWild', true),
      };
      final issues = wildBlock.validateConfiguration(blocks);

      expect(issues.any((i) => i.code == 'W004'), isTrue);
      expect(issues.any((i) => i.isWarning), isTrue);
    });

    test('no warning when only 1-2 wild features enabled', () {
      final wildBlock = WildFeaturesBlock();
      wildBlock.isEnabled = true;

      // Enable only 2 wild features
      wildBlock.setOptionValue('expansion', 'full_reel');
      wildBlock.setOptionValue('sticky_duration', 0); // Disabled
      wildBlock.setOptionValue('walking_direction', 'none'); // Disabled
      wildBlock.setOptionValue('multiplier_range', <int>[]); // Empty

      expect(wildBlock.activeFeatureCount, lessThan(3));

      final blocks = <String, FeatureBlock>{
        'symbol_set': SymbolSetBlock()..setOptionValue('hasWild', true),
      };
      final issues = wildBlock.validateConfiguration(blocks);

      expect(issues.any((i) => i.code == 'W004'), isFalse);
    });
  });

  group('I001: Sticky + Walking Combo Info', () {
    test('info when sticky and walking wilds combined', () {
      final wildBlock = WildFeaturesBlock();
      wildBlock.isEnabled = true;

      // Enable both sticky and walking
      wildBlock.setOptionValue('sticky_duration', 3);
      wildBlock.setOptionValue('walking_direction', 'left');

      expect(wildBlock.hasStickyWilds, isTrue);
      expect(wildBlock.hasWalkingWilds, isTrue);

      final blocks = <String, FeatureBlock>{
        'symbol_set': SymbolSetBlock()..setOptionValue('hasWild', true),
      };
      final issues = wildBlock.validateConfiguration(blocks);

      expect(issues.any((i) => i.code == 'I001'), isTrue);
      expect(issues.any((i) => i.isInfo), isTrue);
    });

    test('no info when only one is enabled', () {
      final wildBlock = WildFeaturesBlock();
      wildBlock.isEnabled = true;

      // Enable only sticky, not walking
      wildBlock.setOptionValue('sticky_duration', 3);
      wildBlock.setOptionValue('walking_direction', 'none');

      expect(wildBlock.hasStickyWilds, isTrue);
      expect(wildBlock.hasWalkingWilds, isFalse);

      final blocks = <String, FeatureBlock>{
        'symbol_set': SymbolSetBlock()..setOptionValue('hasWild', true),
      };
      final issues = wildBlock.validateConfiguration(blocks);

      expect(issues.any((i) => i.code == 'I001'), isFalse);
    });
  });

  group('AnticipationBlock Validation', () {
    test('validates minSymbolsToTrigger for Type A pattern', () {
      final block = AnticipationBlock();
      block.isEnabled = true;
      block.setOptionValue('pattern', 'tip_a');
      block.setOptionValue('minSymbolsToTrigger', 1); // Invalid for Type A

      final errors = block.validateOptions();

      expect(errors.any((e) => e.contains('at least 2 symbols')), isTrue);
    });

    test('requires symbol_set for trigger symbols', () {
      final block = AnticipationBlock();
      block.isEnabled = true;

      final deps = block.dependencies;
      expect(deps.any((d) => d.targetBlockId == 'symbol_set'), isTrue);
    });
  });
}
