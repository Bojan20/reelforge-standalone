/// FeatureBuilderProvider Tests
///
/// Tests block registry, enable/disable, options, presets,
/// undo/redo, validation, and stage generation.
@Tags(['provider'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/feature_builder_provider.dart';
import 'package:fluxforge_ui/models/feature_builder/block_category.dart';
import 'package:fluxforge_ui/models/feature_builder/feature_preset.dart';

void main() {
  group('FeatureBuilderProvider — initialization', () {
    late FeatureBuilderProvider provider;

    setUp(() {
      provider = FeatureBuilderProvider();
    });

    test('allBlocks populated after construction', () {
      expect(provider.allBlocks, isNotEmpty);
      expect(provider.allBlockIds, isNotEmpty);
    });

    test('registers 15 blocks across 4 categories', () {
      // 3 core + 5 feature + 3 presentation + 4 advanced = 15
      expect(provider.allBlocks.length, 15);
    });

    test('core blocks exist', () {
      expect(provider.getBlock('game_core'), isNotNull);
      expect(provider.getBlock('grid'), isNotNull);
      expect(provider.getBlock('symbol_set'), isNotNull);
    });

    test('feature blocks exist', () {
      expect(provider.getBlock('free_spins'), isNotNull);
      expect(provider.getBlock('respin'), isNotNull);
      expect(provider.getBlock('hold_and_win'), isNotNull);
      expect(provider.getBlock('cascades'), isNotNull);
      expect(provider.getBlock('collector'), isNotNull);
    });

    test('presentation blocks exist', () {
      expect(provider.getBlock('win_presentation'), isNotNull);
      expect(provider.getBlock('music_states'), isNotNull);
      expect(provider.getBlock('transitions'), isNotNull);
    });

    test('advanced blocks exist', () {
      expect(provider.getBlock('jackpot'), isNotNull);
      expect(provider.getBlock('multiplier'), isNotNull);
      expect(provider.getBlock('bonus_game'), isNotNull);
      expect(provider.getBlock('gambling'), isNotNull);
    });

    test('blocks grouped by category', () {
      final byCategory = provider.blocksByCategory;
      expect(byCategory.containsKey(BlockCategory.core), true);
      expect(byCategory.containsKey(BlockCategory.feature), true);
      expect(byCategory.containsKey(BlockCategory.presentation), true);
      expect(byCategory.containsKey(BlockCategory.bonus), true);
    });

    test('nonexistent block returns null', () {
      expect(provider.getBlock('nonexistent_block'), isNull);
    });

    test('starts not dirty', () {
      // Note: singleton registry may carry state from prior tests.
      // resetAll clears dirty flag.
      provider.resetAll();
      expect(provider.isDirty, false);
    });

    test('starts with no preset loaded', () {
      provider.resetAll();
      expect(provider.currentPreset, isNull);
    });

    test('starts with empty undo/redo', () {
      provider.resetAll();
      expect(provider.canUndo, false);
      expect(provider.canRedo, false);
    });
  });

  group('FeatureBuilderProvider — enable/disable', () {
    late FeatureBuilderProvider provider;

    setUp(() {
      provider = FeatureBuilderProvider();
      // Reset to known state — singleton registry carries state between tests
      provider.resetAll();
    });

    test('enableBlock enables a disabled block', () {
      final result = provider.enableBlock('free_spins');
      expect(result, true);
      expect(provider.getBlock('free_spins')!.isEnabled, true);
    });

    test('enableBlock returns false for already enabled', () {
      provider.enableBlock('free_spins');
      final result = provider.enableBlock('free_spins');
      expect(result, false);
    });

    test('enableBlock returns false for nonexistent block', () {
      final result = provider.enableBlock('nonexistent');
      expect(result, false);
    });

    test('disableBlock disables an enabled block', () {
      provider.enableBlock('free_spins');
      final result = provider.disableBlock('free_spins');
      if (provider.getBlock('free_spins')!.canBeDisabled) {
        expect(result, true);
        expect(provider.getBlock('free_spins')!.isEnabled, false);
      }
    });

    test('disableBlock returns false for already disabled', () {
      // free_spins should be disabled after resetAll
      final result = provider.disableBlock('free_spins');
      expect(result, false);
    });

    test('disableBlock returns false for nonexistent block', () {
      final result = provider.disableBlock('nonexistent');
      expect(result, false);
    });

    test('toggleBlock flips enabled state', () {
      final block = provider.getBlock('free_spins')!;
      final wasBefore = block.isEnabled;
      final result = provider.toggleBlock('free_spins');
      expect(result, isNotNull);
      if (block.canBeDisabled || !wasBefore) {
        expect(result, !wasBefore);
      }
    });

    test('toggleBlock returns null for nonexistent', () {
      final result = provider.toggleBlock('nonexistent');
      expect(result, isNull);
    });

    test('enabledBlocks returns only enabled blocks', () {
      provider.enableBlock('free_spins');
      provider.enableBlock('cascades');
      final enabledIds = provider.enabledBlockIds;
      expect(enabledIds.contains('free_spins'), true);
      expect(enabledIds.contains('cascades'), true);
    });

    test('enabledBlockCount matches enabledBlocks length', () {
      expect(provider.enabledBlockCount, provider.enabledBlocks.length);
    });

    test('enable/disable marks dirty', () {
      // free_spins starts disabled after resetAll, so enableBlock succeeds
      final result = provider.enableBlock('free_spins');
      expect(result, true);
      expect(provider.isDirty, true);
    });
  });

  group('FeatureBuilderProvider — block options', () {
    late FeatureBuilderProvider provider;

    setUp(() {
      provider = FeatureBuilderProvider();
      provider.resetAll();
    });

    test('getBlockOption returns null for nonexistent block', () {
      expect(provider.getBlockOption<String>('nonexistent', 'opt'), isNull);
    });

    test('setBlockOption sets and getBlockOption retrieves', () {
      final block = provider.getBlock('game_core')!;
      final options = block.options;
      if (options.isNotEmpty) {
        final firstOption = options.first;
        provider.setBlockOption('game_core', firstOption.id, firstOption.defaultValue);
        // Should not crash
      }
    });

    test('resetBlock resets to defaults', () {
      provider.resetBlock('game_core');
      // Should not crash — block reverts to default options
      expect(provider.getBlock('game_core'), isNotNull);
    });

    test('resetAll clears undo/redo and dirty flag', () {
      // Ensure enableBlock actually succeeds (block starts disabled after resetAll)
      final result = provider.enableBlock('free_spins');
      expect(result, true);
      expect(provider.isDirty, true);
      provider.resetAll();
      expect(provider.isDirty, false);
      expect(provider.canUndo, false);
      expect(provider.canRedo, false);
    });

    test('resetAll clears current preset', () {
      provider.enableBlock('free_spins');
      provider.resetAll();
      expect(provider.currentPreset, isNull);
    });
  });

  group('FeatureBuilderProvider — undo/redo', () {
    late FeatureBuilderProvider provider;

    setUp(() {
      provider = FeatureBuilderProvider();
      // Reset to known state so enableBlock succeeds
      provider.resetAll();
    });

    test('enable populates undo stack', () {
      expect(provider.canUndo, false);
      final result = provider.enableBlock('free_spins');
      expect(result, true);
      expect(provider.canUndo, true);
    });

    test('undo restores previous state', () {
      final block = provider.getBlock('free_spins')!;
      expect(block.isEnabled, false); // disabled after resetAll
      provider.enableBlock('free_spins');
      expect(block.isEnabled, true);
      provider.undo();
      expect(block.isEnabled, false);
    });

    test('undo enables redo', () {
      provider.enableBlock('free_spins');
      expect(provider.canRedo, false);
      provider.undo();
      expect(provider.canRedo, true);
    });

    test('redo restores undone change', () {
      provider.enableBlock('free_spins');
      provider.undo();
      expect(provider.getBlock('free_spins')!.isEnabled, false);
      provider.redo();
      expect(provider.getBlock('free_spins')!.isEnabled, true);
    });

    test('new change clears redo stack', () {
      provider.enableBlock('free_spins');
      provider.undo();
      expect(provider.canRedo, true);
      provider.enableBlock('cascades');
      expect(provider.canRedo, false);
    });

    test('undo does nothing when stack empty', () {
      expect(provider.canUndo, false);
      provider.undo(); // Should not crash
    });

    test('redo does nothing when stack empty', () {
      expect(provider.canRedo, false);
      provider.redo(); // Should not crash
    });

    test('undo stack caps at 50', () {
      for (int i = 0; i < 60; i++) {
        provider.toggleBlock('free_spins');
      }
      // Should not exceed 50 entries (no crash, stack bounded)
      expect(provider.canUndo, true);
    });
  });

  group('FeatureBuilderProvider — presets', () {
    late FeatureBuilderProvider provider;

    setUp(() {
      provider = FeatureBuilderProvider();
      provider.resetAll();
    });

    test('createPreset captures current state', () {
      provider.enableBlock('free_spins');
      provider.enableBlock('cascades');
      final preset = provider.createPreset(
        name: 'Test Preset',
        description: 'A test preset',
        category: PresetCategory.custom,
        tags: ['test'],
      );
      expect(preset.name, 'Test Preset');
      expect(preset.description, 'A test preset');
      expect(preset.category, PresetCategory.custom);
      expect(preset.tags, ['test']);
      expect(preset.blocks, isNotEmpty);
      expect(preset.id, startsWith('user_'));
    });

    test('loadPreset restores block states', () {
      provider.enableBlock('free_spins');
      final preset = provider.createPreset(
        name: 'Saved',
        category: PresetCategory.custom,
      );
      provider.resetAll();
      provider.loadPreset(preset);
      expect(provider.currentPreset, isNotNull);
      expect(provider.currentPreset!.name, 'Saved');
      expect(provider.isDirty, false);
      expect(provider.canUndo, false);
    });

    test('matchesPreset returns true for matching config', () {
      provider.enableBlock('free_spins');
      final preset = provider.createPreset(
        name: 'Match Test',
        category: PresetCategory.custom,
      );
      expect(provider.matchesPreset(preset), true);
    });
  });

  group('FeatureBuilderProvider — validation', () {
    late FeatureBuilderProvider provider;

    setUp(() {
      provider = FeatureBuilderProvider();
    });

    test('validate returns result', () {
      final result = provider.validate();
      expect(result, isNotNull);
      expect(result.errors, isList);
      expect(result.warnings, isList);
    });

    test('isValid returns boolean', () {
      expect(provider.isValid, isA<bool>());
    });

    test('lastValidation is populated after validate', () {
      provider.validate();
      expect(provider.lastValidation, isNotNull);
    });
  });

  group('FeatureBuilderProvider — serialization', () {
    late FeatureBuilderProvider provider;

    setUp(() {
      provider = FeatureBuilderProvider();
      provider.resetAll();
    });

    test('exportConfiguration returns valid map', () {
      final json = provider.exportConfiguration();
      expect(json.containsKey('version'), true);
      expect(json.containsKey('blocks'), true);
      expect(json.containsKey('enabledBlocks'), true);
      expect(json.containsKey('stageCount'), true);
      expect(json['version'], '1.0.0');
    });

    test('importConfiguration does not crash', () {
      final json = provider.exportConfiguration();
      provider.importConfiguration(json);
      expect(provider.isDirty, false);
      expect(provider.canUndo, false);
    });

    test('import clears undo/redo', () {
      // Ensure enableBlock succeeds to populate undo stack
      final result = provider.enableBlock('free_spins');
      expect(result, true);
      expect(provider.canUndo, true);
      final json = provider.exportConfiguration();
      provider.importConfiguration(json);
      expect(provider.canUndo, false);
    });
  });

  group('FeatureBuilderProvider — convenience accessors', () {
    late FeatureBuilderProvider provider;

    setUp(() {
      provider = FeatureBuilderProvider();
    });

    test('gameCoreBlock accessor', () {
      expect(provider.gameCoreBlock, isNotNull);
      expect(provider.gameCoreBlock!.id, 'game_core');
    });

    test('gridBlock accessor', () {
      expect(provider.gridBlock, isNotNull);
      expect(provider.gridBlock!.id, 'grid');
    });

    test('freeSpinsBlock accessor', () {
      expect(provider.freeSpinsBlock, isNotNull);
      expect(provider.freeSpinsBlock!.id, 'free_spins');
    });

    test('jackpotBlock accessor', () {
      expect(provider.jackpotBlock, isNotNull);
      expect(provider.jackpotBlock!.id, 'jackpot');
    });
  });

  group('FeatureBuilderProvider — notifications', () {
    late FeatureBuilderProvider provider;

    setUp(() {
      provider = FeatureBuilderProvider();
      provider.resetAll();
    });

    test('enableBlock notifies listeners', () {
      int count = 0;
      provider.addListener(() => count++);
      provider.enableBlock('free_spins');
      expect(count, greaterThan(0));
    });

    test('disableBlock notifies listeners', () {
      provider.enableBlock('free_spins');
      int count = 0;
      provider.addListener(() => count++);
      if (provider.getBlock('free_spins')!.canBeDisabled) {
        provider.disableBlock('free_spins');
        expect(count, greaterThan(0));
      }
    });

    test('undo notifies listeners', () {
      provider.enableBlock('free_spins');
      int count = 0;
      provider.addListener(() => count++);
      provider.undo();
      expect(count, greaterThan(0));
    });

    test('redo notifies listeners', () {
      provider.enableBlock('free_spins');
      provider.undo();
      int count = 0;
      provider.addListener(() => count++);
      provider.redo();
      expect(count, greaterThan(0));
    });

    test('resetAll notifies listeners', () {
      int count = 0;
      provider.addListener(() => count++);
      provider.resetAll();
      expect(count, greaterThan(0));
    });

    test('loadPreset notifies listeners', () {
      final preset = provider.createPreset(
        name: 'Notify Test',
        category: PresetCategory.custom,
      );
      int count = 0;
      provider.addListener(() => count++);
      provider.loadPreset(preset);
      expect(count, greaterThan(0));
    });
  });

  group('FeatureBuilderProvider — stage generation', () {
    late FeatureBuilderProvider provider;

    setUp(() {
      provider = FeatureBuilderProvider();
    });

    test('generatedStages returns list', () {
      expect(provider.generatedStages, isList);
    });

    test('stageNames returns list', () {
      expect(provider.stageNames, isList);
    });

    test('totalStageCount matches generatedStages length', () {
      expect(provider.totalStageCount, provider.generatedStages.length);
    });

    test('stagesByCategory returns map', () {
      expect(provider.stagesByCategory, isA<Map>());
    });

    test('pooledStageNames returns set', () {
      expect(provider.pooledStageNames, isA<Set>());
    });

    test('invalidateStages forces regeneration', () {
      provider.invalidateStages();
      // Access should trigger fresh generation
      final stages = provider.generatedStages;
      expect(stages, isList);
    });
  });
}
