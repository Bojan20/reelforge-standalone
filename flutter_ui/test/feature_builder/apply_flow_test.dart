// ============================================================================
// FluxForge Studio — Feature Builder Apply Flow Integration Tests
// ============================================================================
// P13.8.9: Integration tests for Feature Builder apply and build flow.
// Tests verify that configurations are correctly applied to the slot machine.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/feature_builder_provider.dart';
import 'package:fluxforge_ui/blocks/game_core_block.dart';
import 'package:fluxforge_ui/blocks/grid_block.dart';
import 'package:fluxforge_ui/blocks/symbol_set_block.dart';
import 'package:fluxforge_ui/blocks/anticipation_block.dart';
import 'package:fluxforge_ui/blocks/wild_features_block.dart';
import 'package:fluxforge_ui/blocks/free_spins_block.dart';
import 'package:fluxforge_ui/blocks/cascades_block.dart';

void main() {
  group('Apply and Build Flow', () {
    test('full flow: configure → validate → generate stages', () {
      final provider = FeatureBuilderProvider();

      // Configure blocks
      provider.enableBlock('free_spins');
      provider.enableBlock('cascades');

      // Set options
      provider.setBlockOption('grid', 'reelCount', 5);
      provider.setBlockOption('grid', 'rowCount', 3);
      provider.setBlockOption('free_spins', 'baseSpinsCount', 12);

      // Validate
      final validationResult = provider.validate();
      expect(validationResult.isValid, isTrue);

      // Generate stages
      final stageResult = provider.generateStages();
      expect(stageResult.isValid, isTrue);
      expect(stageResult.stages.isNotEmpty, isTrue);

      // Verify stages from multiple blocks are present
      final stageNames = stageResult.stages.map((s) => s.name).toList();
      expect(stageNames.any((s) => s.startsWith('SPIN')), isTrue);
      expect(stageNames.any((s) => s.startsWith('FS_')), isTrue);
      expect(stageNames.any((s) => s.startsWith('CASCADE')), isTrue);
    });

    test('totalStageCount reflects all enabled blocks', () {
      final provider = FeatureBuilderProvider();

      final initialCount = provider.totalStageCount;

      // Enable more blocks
      provider.enableBlock('free_spins');
      provider.enableBlock('cascades');
      provider.enableBlock('jackpot');

      final newCount = provider.totalStageCount;

      expect(newCount, greaterThan(initialCount));
    });

    test('disabling block removes its stages', () {
      final provider = FeatureBuilderProvider();

      // Enable and count
      provider.enableBlock('free_spins');
      final withFreeSpins = provider.totalStageCount;

      // Disable and count
      provider.disableBlock('free_spins');
      final withoutFreeSpins = provider.totalStageCount;

      expect(withoutFreeSpins, lessThan(withFreeSpins));
    });
  });

  group('Grid Dimensions Applied', () {
    test('reelCount option updates correctly', () {
      final provider = FeatureBuilderProvider();

      provider.setBlockOption('grid', 'reelCount', 6);
      final reelCount = provider.getBlockOption<int>('grid', 'reelCount');

      expect(reelCount, 6);
    });

    test('rowCount option updates correctly', () {
      final provider = FeatureBuilderProvider();

      provider.setBlockOption('grid', 'rowCount', 4);
      final rowCount = provider.getBlockOption<int>('grid', 'rowCount');

      expect(rowCount, 4);
    });

    test('grid block generates correct number of REEL_STOP stages', () {
      final provider = FeatureBuilderProvider();

      provider.setBlockOption('grid', 'reelCount', 6);
      final gridBlock = provider.gridBlock;
      final stages = gridBlock?.generateStages() ?? [];

      // Should have REEL_STOP_0 through REEL_STOP_5 (6 reels)
      final reelStopStages = stages.where((s) => s.name.startsWith('REEL_STOP_'));
      expect(reelStopStages.length, 6);
    });
  });

  group('Symbols Generated', () {
    test('symbol set block is always enabled', () {
      final provider = FeatureBuilderProvider();

      expect(provider.symbolSetBlock?.isEnabled, isTrue);
      expect(provider.symbolSetBlock?.canBeDisabled, isFalse);
    });

    test('symbol set generates landing stages', () {
      final provider = FeatureBuilderProvider();

      final symbolSetBlock = provider.symbolSetBlock;
      expect(symbolSetBlock, isNotNull);

      final stages = symbolSetBlock?.generateStages() ?? [];
      expect(stages.isNotEmpty, isTrue);
    });
  });

  group('Stages Registered', () {
    test('generated stages have valid names', () {
      final provider = FeatureBuilderProvider();

      provider.enableBlock('free_spins');
      final result = provider.generateStages();

      for (final stage in result.stages) {
        // Stage names should be uppercase snake_case
        expect(stage.name, matches(RegExp(r'^[A-Z][A-Z0-9_]*$')));
      }
    });

    test('generated stages have valid bus assignments', () {
      final provider = FeatureBuilderProvider();

      provider.enableBlock('free_spins');
      final result = provider.generateStages();

      final validBuses = ['sfx', 'music', 'ui', 'reels', 'vo', 'ambience'];

      for (final stage in result.stages) {
        expect(validBuses.contains(stage.stage.bus), isTrue,
            reason: 'Stage ${stage.stage.name} has invalid bus: ${stage.stage.bus}');
      }
    });

    test('generated stages have valid priorities (0-100)', () {
      final provider = FeatureBuilderProvider();

      provider.enableBlock('free_spins');
      provider.enableBlock('cascades');
      final result = provider.generateStages();

      for (final stage in result.stages) {
        expect(stage.stage.priority, inInclusiveRange(0, 100),
            reason: 'Stage ${stage.stage.name} has invalid priority: ${stage.stage.priority}');
      }
    });
  });

  group('Anticipation Apply Flow', () {
    test('applying anticipation block adds anticipation stages', () {
      final provider = FeatureBuilderProvider();

      // Enable anticipation
      provider.enableBlock('anticipation');

      final result = provider.generateStages();
      final stageNames = result.stages.map((s) => s.name).toList();

      expect(stageNames.contains('ANTICIPATION_ON'), isTrue);
      expect(stageNames.contains('ANTICIPATION_OFF'), isTrue);
      expect(stageNames.contains('ANTICIPATION_TENSION'), isTrue);
    });

    test('tension escalation option affects stage generation', () {
      final provider = FeatureBuilderProvider();

      provider.enableBlock('anticipation');
      provider.setBlockOption('anticipation', 'tensionEscalationEnabled', true);
      provider.setBlockOption('anticipation', 'tensionLevels', 4);
      provider.setBlockOption('anticipation', 'perReelAudio', true);

      final result = provider.generateStages();
      final stageNames = result.stages.map((s) => s.name).toList();

      // Should have per-reel tension level stages
      expect(stageNames.any((s) => s.contains('ANTICIPATION_TENSION_R')), isTrue);
      expect(stageNames.any((s) => s.contains('_L1')), isTrue);
      expect(stageNames.any((s) => s.contains('_L4')), isTrue);
    });

    test('Type B pattern generates near miss stages', () {
      final provider = FeatureBuilderProvider();

      provider.enableBlock('anticipation');
      provider.setBlockOption('anticipation', 'pattern', 'tip_b');

      final result = provider.generateStages();
      final stageNames = result.stages.map((s) => s.name).toList();

      expect(stageNames.contains('NEAR_MISS_REVEAL'), isTrue);
      expect(stageNames.any((s) => s.startsWith('NEAR_MISS_REEL_')), isTrue);
    });
  });

  group('Wild Features Apply Flow', () {
    test('applying wild features block adds wild stages', () {
      final provider = FeatureBuilderProvider();

      provider.enableBlock('wild_features');

      final result = provider.generateStages();
      final stageNames = result.stages.map((s) => s.name).toList();

      expect(stageNames.contains('WILD_LAND'), isTrue);
    });

    test('expansion option affects stage generation', () {
      final provider = FeatureBuilderProvider();

      provider.enableBlock('wild_features');
      provider.setBlockOption('wild_features', 'expansion', 'full_reel');
      provider.setBlockOption('wild_features', 'has_expansion_sound', true);

      final result = provider.generateStages();
      final stageNames = result.stages.map((s) => s.name).toList();

      expect(stageNames.any((s) => s.contains('WILD_EXPAND')), isTrue);
    });

    test('sticky duration option affects stage generation', () {
      final provider = FeatureBuilderProvider();

      provider.enableBlock('wild_features');
      provider.setBlockOption('wild_features', 'sticky_duration', 3);
      provider.setBlockOption('wild_features', 'has_sticky_sound', true);

      final result = provider.generateStages();
      final stageNames = result.stages.map((s) => s.name).toList();

      expect(stageNames.any((s) => s.contains('WILD_STICK')), isTrue);
    });

    test('walking direction option affects stage generation', () {
      final provider = FeatureBuilderProvider();

      provider.enableBlock('wild_features');
      provider.setBlockOption('wild_features', 'walking_direction', 'left');
      provider.setBlockOption('wild_features', 'has_walking_sound', true);

      final result = provider.generateStages();
      final stageNames = result.stages.map((s) => s.name).toList();

      expect(stageNames.any((s) => s.contains('WILD_WALK')), isTrue);
    });

    test('multiplier range option affects stage generation', () {
      final provider = FeatureBuilderProvider();

      provider.enableBlock('wild_features');
      provider.setBlockOption('wild_features', 'multiplier_range', [2, 5, 10]);
      provider.setBlockOption('wild_features', 'has_multiplier_sound', true);

      final result = provider.generateStages();
      final stageNames = result.stages.map((s) => s.name).toList();

      expect(stageNames.contains('WILD_MULT_APPLY_X2'), isTrue);
      expect(stageNames.contains('WILD_MULT_APPLY_X5'), isTrue);
      expect(stageNames.contains('WILD_MULT_APPLY_X10'), isTrue);
    });
  });

  group('Undo/Redo in Apply Flow', () {
    test('undo reverts block enable', () {
      final provider = FeatureBuilderProvider();

      expect(provider.freeSpinsBlock?.isEnabled, isFalse);

      provider.enableBlock('free_spins');
      expect(provider.freeSpinsBlock?.isEnabled, isTrue);

      provider.undo();
      expect(provider.freeSpinsBlock?.isEnabled, isFalse);
    });

    test('undo reverts option change', () {
      final provider = FeatureBuilderProvider();

      final originalValue = provider.getBlockOption<int>('grid', 'reelCount');

      provider.setBlockOption('grid', 'reelCount', 7);
      expect(provider.getBlockOption<int>('grid', 'reelCount'), 7);

      provider.undo();
      expect(provider.getBlockOption<int>('grid', 'reelCount'), originalValue);
    });

    test('redo restores undone change', () {
      final provider = FeatureBuilderProvider();

      provider.enableBlock('free_spins');
      provider.undo();
      expect(provider.freeSpinsBlock?.isEnabled, isFalse);

      provider.redo();
      expect(provider.freeSpinsBlock?.isEnabled, isTrue);
    });
  });
}
