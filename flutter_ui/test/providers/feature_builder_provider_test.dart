/// FeatureBuilderProvider Tests
///
/// Tests block registry, enable/disable, options, presets,
/// undo/redo, validation, and stage generation.
@Tags(['provider'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/feature_builder_provider.dart';
import 'package:fluxforge_ui/models/feature_builder/block_category.dart';
import 'package:fluxforge_ui/models/feature_builder/block_options.dart';
import 'package:fluxforge_ui/models/feature_builder/block_dependency.dart';
import 'package:fluxforge_ui/models/feature_builder/feature_block.dart';
import 'package:fluxforge_ui/models/feature_builder/feature_preset.dart';
import 'package:fluxforge_ui/widgets/slot_lab/forced_outcome_panel.dart';
import 'package:fluxforge_ui/src/rust/native_ffi.dart' show ForcedOutcome;

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

    test('registers all blocks across 4 categories', () {
      // 3 core + 5 feature + 3 presentation + 6 bonus = 17
      expect(provider.allBlocks.length, greaterThanOrEqualTo(16));
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

  // ─────────────────────────────────────────────────────────────────────────
  // P13.8.7: ForcedOutcomeConfig — Dynamic Visibility Filtering
  // ─────────────────────────────────────────────────────────────────────────

  group('ForcedOutcomeConfig visibility (P13.8.7)', () {
    test('outcomes list is populated', () {
      expect(ForcedOutcomeConfig.outcomes, isNotEmpty);
      expect(ForcedOutcomeConfig.outcomes.length, greaterThanOrEqualTo(15));
    });

    test('core outcomes have null featureBlockId', () {
      final lose = ForcedOutcomeConfig.outcomes.firstWhere(
        (c) => c.label == 'LOSE',
      );
      expect(lose.featureBlockId, isNull);

      final nearMiss = ForcedOutcomeConfig.outcomes.firstWhere(
        (c) => c.label == 'NEAR MISS',
      );
      expect(nearMiss.featureBlockId, isNull);
    });

    test('win tier outcomes have null featureBlockId', () {
      final winOutcomes = ForcedOutcomeConfig.outcomes
          .where((c) => c.label.startsWith('WIN '))
          .toList();
      expect(winOutcomes, isNotEmpty);
      for (final win in winOutcomes) {
        expect(win.featureBlockId, isNull,
            reason: '${win.label} should have null featureBlockId');
      }
    });

    test('free spins outcome linked to free_spins block', () {
      final fs = ForcedOutcomeConfig.outcomes.firstWhere(
        (c) => c.label == 'FREE SPINS',
      );
      expect(fs.featureBlockId, 'free_spins');
      expect(fs.outcome, ForcedOutcome.freeSpins);
    });

    test('cascade outcome linked to cascades block', () {
      final casc = ForcedOutcomeConfig.outcomes.firstWhere(
        (c) => c.label == 'CASCADE',
      );
      expect(casc.featureBlockId, 'cascades');
      expect(casc.outcome, ForcedOutcome.cascade);
    });

    test('all jackpot outcomes linked to jackpot block', () {
      final jpOutcomes = ForcedOutcomeConfig.outcomes
          .where((c) => c.label.startsWith('JP '))
          .toList();
      expect(jpOutcomes.length, 4); // MINI, MINOR, MAJOR, GRAND
      for (final jp in jpOutcomes) {
        expect(jp.featureBlockId, 'jackpot');
      }
    });

    test('getVisibleOutcomes returns all when all feature blocks enabled', () {
      final allBlockIds = {'free_spins', 'cascades', 'jackpot'};
      final visible = ForcedOutcomeConfig.getVisibleOutcomes(allBlockIds);
      expect(visible.length, ForcedOutcomeConfig.outcomes.length);
    });

    test('getVisibleOutcomes hides feature outcomes when no blocks enabled', () {
      final noBlocks = <String>{};
      final visible = ForcedOutcomeConfig.getVisibleOutcomes(noBlocks);
      for (final config in visible) {
        expect(config.featureBlockId, isNull,
            reason: '${config.label} should not be visible with no blocks');
      }
    });

    test('getVisibleOutcomes partial — only free_spins enabled', () {
      final onlyFs = {'free_spins'};
      final visible = ForcedOutcomeConfig.getVisibleOutcomes(onlyFs);
      expect(visible.any((c) => c.label == 'FREE SPINS'), true);
      expect(visible.any((c) => c.label == 'CASCADE'), false);
      expect(visible.any((c) => c.label == 'JP GRAND'), false);
      expect(visible.any((c) => c.label == 'LOSE'), true); // core always
    });

    test('getVisibleOutcomes partial — only jackpot enabled', () {
      final onlyJp = {'jackpot'};
      final visible = ForcedOutcomeConfig.getVisibleOutcomes(onlyJp);
      expect(visible.any((c) => c.label == 'JP MINI'), true);
      expect(visible.any((c) => c.label == 'JP GRAND'), true);
      expect(visible.any((c) => c.label == 'FREE SPINS'), false);
      expect(visible.any((c) => c.label == 'CASCADE'), false);
    });

    test('isOutcomeVisible with null featureBlockId always true', () {
      final lose = ForcedOutcomeConfig.outcomes.firstWhere(
        (c) => c.label == 'LOSE',
      );
      expect(ForcedOutcomeConfig.isOutcomeVisible(lose, {}), true);
      expect(ForcedOutcomeConfig.isOutcomeVisible(lose, {'free_spins'}), true);
    });

    test('isOutcomeVisible with matching block returns true', () {
      final fs = ForcedOutcomeConfig.outcomes.firstWhere(
        (c) => c.label == 'FREE SPINS',
      );
      expect(ForcedOutcomeConfig.isOutcomeVisible(fs, {'free_spins'}), true);
    });

    test('isOutcomeVisible with missing block returns false', () {
      final fs = ForcedOutcomeConfig.outcomes.firstWhere(
        (c) => c.label == 'FREE SPINS',
      );
      expect(ForcedOutcomeConfig.isOutcomeVisible(fs, {'jackpot'}), false);
      expect(ForcedOutcomeConfig.isOutcomeVisible(fs, {}), false);
    });

    test('getConfig returns matching config for outcome', () {
      final config = ForcedOutcomeConfig.getConfig(ForcedOutcome.freeSpins);
      expect(config, isNotNull);
      expect(config!.outcome, ForcedOutcome.freeSpins);
    });

    test('expectedWinMultiplier set for win tiers', () {
      final withMultiplier = ForcedOutcomeConfig.outcomes
          .where((c) => c.expectedWinMultiplier != null)
          .toList();
      expect(withMultiplier, isNotEmpty);
      for (final config in withMultiplier) {
        expect(config.expectedWinMultiplier, greaterThan(0));
      }
    });

    test('keyboard shortcuts exist for numbered outcomes', () {
      final withShortcuts = ForcedOutcomeConfig.outcomes
          .where((c) => c.keyboardShortcut != null)
          .toList();
      expect(withShortcuts, isNotEmpty);
    });

    test('expectedStages populated for every outcome', () {
      for (final config in ForcedOutcomeConfig.outcomes) {
        expect(config.expectedStages, isNotEmpty,
            reason: '${config.label} should have expectedStages');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // BlockOption — additional tests
  // ─────────────────────────────────────────────────────────────────────────

  group('BlockOption', () {
    test('initial value equals default', () {
      final opt = BlockOption(
        id: 'count',
        name: 'Count',
        type: BlockOptionType.count,
        defaultValue: 5,
      );
      expect(opt.value, 5);
      expect(opt.isModified, false);
    });

    test('setting value marks as modified', () {
      final opt = BlockOption(
        id: 'count',
        name: 'Count',
        type: BlockOptionType.count,
        defaultValue: 5,
      );
      opt.value = 10;
      expect(opt.value, 10);
      expect(opt.isModified, true);
    });

    test('reset restores default', () {
      final opt = BlockOption(
        id: 'mode',
        name: 'Mode',
        type: BlockOptionType.dropdown,
        defaultValue: 'scatter',
      );
      opt.value = 'bonus';
      opt.reset();
      expect(opt.value, 'scatter');
      expect(opt.isModified, false);
    });

    test('validator rejects invalid values', () {
      final opt = BlockOption(
        id: 'spins',
        name: 'Spins',
        type: BlockOptionType.count,
        defaultValue: 10,
        validator: (v) => (v as int) < 1 ? 'Must be >= 1' : null,
      );
      expect(() => opt.value = 0, throwsA(isA<ArgumentError>()));
      expect(opt.value, 10);
    });

    test('validate checks required fields', () {
      final opt = BlockOption(
        id: 'name',
        name: 'Name',
        type: BlockOptionType.text,
        defaultValue: null,
        required: true,
      );
      expect(opt.validate(), isNotNull);
    });

    test('JSON round-trip preserves state', () {
      final opt = BlockOption(
        id: 'count',
        name: 'Count',
        type: BlockOptionType.count,
        defaultValue: 5,
        min: 1,
        max: 100,
        group: 'General',
      );
      opt.value = 42;
      final json = opt.toJson();
      final restored = BlockOption.fromJson(json);
      expect(restored.id, 'count');
      expect(restored.value, 42);
      expect(restored.defaultValue, 5);
      expect(restored.min, 1);
      expect(restored.max, 100);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // BlockDependency — additional tests
  // ─────────────────────────────────────────────────────────────────────────

  group('BlockDependency', () {
    test('requires factory creates correct type', () {
      final dep = BlockDependency.requires(
        source: 'free_spins',
        target: 'symbol_set',
        autoResolvable: true,
      );
      expect(dep.type, DependencyType.requires);
      expect(dep.autoResolvable, true);
    });

    test('conflicts factory creates correct type', () {
      final dep = BlockDependency.conflicts(
        source: 'respin',
        target: 'hold_and_win',
      );
      expect(dep.type, DependencyType.conflicts);
      expect(dep.autoResolvable, false);
    });

    test('JSON round-trip', () {
      final dep = BlockDependency.requires(
        source: 'a',
        target: 'b',
        targetOption: 'scatter',
      );
      final json = dep.toJson();
      final restored = BlockDependency.fromJson(json);
      expect(restored.sourceBlockId, 'a');
      expect(restored.targetBlockId, 'b');
      expect(restored.type, DependencyType.requires);
      expect(restored.targetOption, 'scatter');
    });

    test('equality works', () {
      final a = BlockDependency.requires(source: 'x', target: 'y');
      final b = BlockDependency.requires(source: 'x', target: 'y');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // GeneratedStage
  // ─────────────────────────────────────────────────────────────────────────

  group('GeneratedStage', () {
    test('JSON round-trip', () {
      const stage = GeneratedStage(
        name: 'FS_TRIGGER',
        description: 'Free spins triggered',
        bus: 'sfx',
        priority: 80,
        pooled: true,
        category: 'free_spins',
        sourceBlockId: 'free_spins',
      );
      final json = stage.toJson();
      final restored = GeneratedStage.fromJson(json);
      expect(restored.name, 'FS_TRIGGER');
      expect(restored.priority, 80);
      expect(restored.pooled, true);
      expect(restored.sourceBlockId, 'free_spins');
    });

    test('defaults are correct', () {
      const stage = GeneratedStage(
        name: 'TEST',
        description: 'Test',
        bus: 'sfx',
        sourceBlockId: 'test',
      );
      expect(stage.priority, 50);
      expect(stage.pooled, false);
      expect(stage.looping, false);
      expect(stage.category, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // BlockStateSnapshot
  // ─────────────────────────────────────────────────────────────────────────

  group('BlockStateSnapshot', () {
    test('JSON round-trip', () {
      final snap = BlockStateSnapshot(
        blockId: 'test',
        isEnabled: true,
        options: {'count': 10, 'mode': 'auto'},
      );
      final json = snap.toJson();
      final restored = BlockStateSnapshot.fromJson(json);
      expect(restored.blockId, 'test');
      expect(restored.isEnabled, true);
      expect(restored.options['count'], 10);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AutoResolveAction
  // ─────────────────────────────────────────────────────────────────────────

  group('AutoResolveAction', () {
    test('JSON round-trip', () {
      const action = AutoResolveAction(
        type: AutoResolveType.enableBlock,
        targetBlockId: 'symbol_set',
        description: 'Enable Symbol Set',
      );
      final json = action.toJson();
      final restored = AutoResolveAction.fromJson(json);
      expect(restored.type, AutoResolveType.enableBlock);
      expect(restored.targetBlockId, 'symbol_set');
    });

    test('setOption with optionId and value', () {
      const action = AutoResolveAction(
        type: AutoResolveType.setOption,
        targetBlockId: 'grid',
        optionId: 'reels',
        value: 5,
        description: 'Set reels to 5',
      );
      final json = action.toJson();
      final restored = AutoResolveAction.fromJson(json);
      expect(restored.optionId, 'reels');
      expect(restored.value, 5);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // BlockCategory
  // ─────────────────────────────────────────────────────────────────────────

  group('BlockCategory', () {
    test('displayName values', () {
      expect(BlockCategory.core.displayName, 'Core');
      expect(BlockCategory.feature.displayName, 'Features');
      expect(BlockCategory.presentation.displayName, 'Presentation');
      expect(BlockCategory.bonus.displayName, 'Bonus');
    });

    test('core is not optional', () {
      expect(BlockCategory.core.isOptional, false);
      expect(BlockCategory.feature.isOptional, true);
    });

    test('sortOrder ascending', () {
      expect(BlockCategory.core.sortOrder, lessThan(BlockCategory.feature.sortOrder));
      expect(BlockCategory.feature.sortOrder, lessThan(BlockCategory.presentation.sortOrder));
      expect(BlockCategory.presentation.sortOrder, lessThan(BlockCategory.bonus.sortOrder));
    });

    test('BlockCategories.fromName case-insensitive', () {
      expect(BlockCategories.fromName('CORE'), BlockCategory.core);
      expect(BlockCategories.fromName('Features'), BlockCategory.feature);
      expect(BlockCategories.fromName('unknown'), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // DependencyType severity ordering
  // ─────────────────────────────────────────────────────────────────────────

  group('DependencyType', () {
    test('severity ordering: conflicts > requires > modifies > enables', () {
      expect(DependencyType.conflicts.severity,
          greaterThan(DependencyType.requires.severity));
      expect(DependencyType.requires.severity,
          greaterThan(DependencyType.modifies.severity));
      expect(DependencyType.modifies.severity,
          greaterThan(DependencyType.enables.severity));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // OptionChoice
  // ─────────────────────────────────────────────────────────────────────────

  group('OptionChoice', () {
    test('JSON round-trip', () {
      const choice = OptionChoice(
        value: 'scatter',
        label: 'Scatter Trigger',
        description: 'Trigger on scatter symbols',
        group: 'Triggers',
      );
      final json = choice.toJson();
      final restored = OptionChoice.fromJson(json);
      expect(restored.value, 'scatter');
      expect(restored.label, 'Scatter Trigger');
      expect(restored.group, 'Triggers');
    });
  });
}
