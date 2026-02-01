// ============================================================================
// FluxForge Studio — Feature Builder: Multiplier Block
// ============================================================================
// P13.9: Multiplier system configuration
// Defines global, win, reel, and symbol multipliers with progression
// ============================================================================

import '../models/feature_builder/feature_block.dart';
import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';

/// Multiplier system configuration block.
///
/// Configures:
/// - Multiplier types (global, win, reel, symbol, random)
/// - Progression systems (cascade, streak, feature)
/// - Maximum caps and reset conditions
/// - Visual and audio presentation
class MultiplierBlock extends FeatureBlockBase {
  MultiplierBlock() : super(enabled: false);

  @override
  String get id => 'multiplier';

  @override
  String get name => 'Multiplier System';

  @override
  String get description =>
      'Win and feature multiplier configuration including progression, '
      'caps, and presentation settings.';

  @override
  BlockCategory get category => BlockCategory.feature;

  @override
  String get iconName => 'close'; // × symbol

  @override
  int get stagePriority => 75;

  // ============================================================================
  // Options
  // ============================================================================

  @override
  List<BlockOption> createOptions() => [
        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Multiplier Types
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'enable_global',
          name: 'Global Multiplier',
          description: 'Single multiplier applied to all wins',
          defaultValue: true,
          group: 'Types',
          order: 0,
        ),

        BlockOptionFactory.toggle(
          id: 'enable_win',
          name: 'Win Multiplier',
          description: 'Multiplier applied per winning combination',
          defaultValue: false,
          group: 'Types',
          order: 1,
        ),

        BlockOptionFactory.toggle(
          id: 'enable_reel',
          name: 'Reel Multiplier',
          description: 'Per-reel multiplier overlay',
          defaultValue: false,
          group: 'Types',
          order: 2,
        ),

        BlockOptionFactory.toggle(
          id: 'enable_symbol',
          name: 'Symbol Multiplier',
          description: 'Special symbols carry multiplier values',
          defaultValue: false,
          group: 'Types',
          order: 3,
        ),

        BlockOptionFactory.toggle(
          id: 'enable_random',
          name: 'Random Multiplier',
          description: 'Random multiplier applied on trigger',
          defaultValue: false,
          group: 'Types',
          order: 4,
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Global Multiplier Settings
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.count(
          id: 'global_starting',
          name: 'Starting Value',
          description: 'Initial global multiplier',
          min: 1,
          max: 10,
          defaultValue: 1,
          group: 'Global',
          order: 10,
          visibleWhen: {'enable_global': true},
        ),

        BlockOptionFactory.count(
          id: 'global_max',
          name: 'Maximum Value',
          description: 'Maximum global multiplier cap',
          min: 2,
          max: 1000,
          defaultValue: 100,
          group: 'Global',
          order: 11,
          visibleWhen: {'enable_global': true},
        ),

        BlockOptionFactory.dropdown(
          id: 'global_progression',
          name: 'Progression Type',
          description: 'How global multiplier increases',
          choices: const [
            OptionChoice(
              value: 'fixed',
              label: 'Fixed',
              description: 'Always stays at starting value',
            ),
            OptionChoice(
              value: 'cascade',
              label: 'Cascade',
              description: 'Increases with each cascade/tumble',
            ),
            OptionChoice(
              value: 'win_streak',
              label: 'Win Streak',
              description: 'Increases with consecutive wins',
            ),
            OptionChoice(
              value: 'feature_spin',
              label: 'Feature Spin',
              description: 'Increases each spin during feature',
            ),
            OptionChoice(
              value: 'collect',
              label: 'Collect Symbol',
              description: 'Increases when collecting special symbols',
            ),
          ],
          defaultValue: 'cascade',
          group: 'Global',
          order: 12,
          visibleWhen: {'enable_global': true},
        ),

        BlockOptionFactory.dropdown(
          id: 'global_increase_mode',
          name: 'Increase Mode',
          description: 'How multiplier grows',
          choices: const [
            OptionChoice(
              value: 'add_1',
              label: '+1',
              description: 'Add 1 each step',
            ),
            OptionChoice(
              value: 'add_2',
              label: '+2',
              description: 'Add 2 each step',
            ),
            OptionChoice(
              value: 'double',
              label: '×2',
              description: 'Double each step',
            ),
            OptionChoice(
              value: 'fibonacci',
              label: 'Fibonacci',
              description: '1, 1, 2, 3, 5, 8, 13...',
            ),
            OptionChoice(
              value: 'custom_steps',
              label: 'Custom Steps',
              description: 'Use predefined step values',
            ),
          ],
          defaultValue: 'add_1',
          group: 'Global',
          order: 13,
          visibleWhen: {'enable_global': true},
        ),

        BlockOptionFactory.toggle(
          id: 'global_persists_feature',
          name: 'Persists Through Feature',
          description: 'Multiplier maintained during free spins',
          defaultValue: true,
          group: 'Global',
          order: 14,
          visibleWhen: {'enable_global': true},
        ),

        BlockOptionFactory.toggle(
          id: 'global_resets_spin',
          name: 'Resets Each Spin',
          description: 'Multiplier resets after each base spin',
          defaultValue: false,
          group: 'Global',
          order: 15,
          visibleWhen: {'enable_global': true},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Reel Multiplier Settings
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.dropdown(
          id: 'reel_position',
          name: 'Reel Position',
          description: 'Which reels can have multipliers',
          choices: const [
            OptionChoice(
              value: 'any',
              label: 'Any Reel',
              description: 'Multiplier can appear on any reel',
            ),
            OptionChoice(
              value: 'middle_only',
              label: 'Middle Reels',
              description: 'Only on reels 2, 3, 4',
            ),
            OptionChoice(
              value: 'last_only',
              label: 'Last Reel',
              description: 'Only on the rightmost reel',
            ),
            OptionChoice(
              value: 'specific',
              label: 'Specific Reels',
              description: 'Configured per-reel',
            ),
          ],
          defaultValue: 'any',
          group: 'Reel',
          order: 20,
          visibleWhen: {'enable_reel': true},
        ),

        BlockOptionFactory.multiSelect(
          id: 'reel_values',
          name: 'Available Values',
          description: 'Multiplier values that can appear on reels',
          choices: const [
            OptionChoice(value: 2, label: '2x'),
            OptionChoice(value: 3, label: '3x'),
            OptionChoice(value: 5, label: '5x'),
            OptionChoice(value: 10, label: '10x'),
            OptionChoice(value: 25, label: '25x'),
            OptionChoice(value: 50, label: '50x'),
            OptionChoice(value: 100, label: '100x'),
          ],
          defaultValue: [2, 3, 5, 10],
          group: 'Reel',
          order: 21,
          visibleWhen: {'enable_reel': true},
        ),

        BlockOptionFactory.dropdown(
          id: 'reel_combine',
          name: 'Combination Mode',
          description: 'How multiple reel multipliers combine',
          choices: const [
            OptionChoice(
              value: 'multiply',
              label: 'Multiply',
              description: '2x × 3x = 6x',
            ),
            OptionChoice(
              value: 'add',
              label: 'Add',
              description: '2x + 3x = 5x',
            ),
            OptionChoice(
              value: 'highest',
              label: 'Highest Only',
              description: 'Use the highest value only',
            ),
          ],
          defaultValue: 'multiply',
          group: 'Reel',
          order: 22,
          visibleWhen: {'enable_reel': true},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Symbol Multiplier Settings
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'symbol_wild_multiplier',
          name: 'Wild Carries Multiplier',
          description: 'Wild symbols can have multiplier values',
          defaultValue: true,
          group: 'Symbol',
          order: 30,
          visibleWhen: {'enable_symbol': true},
        ),

        BlockOptionFactory.multiSelect(
          id: 'symbol_wild_values',
          name: 'Wild Multiplier Values',
          description: 'Possible multiplier values on wilds',
          choices: const [
            OptionChoice(value: 2, label: '2x'),
            OptionChoice(value: 3, label: '3x'),
            OptionChoice(value: 4, label: '4x'),
            OptionChoice(value: 5, label: '5x'),
            OptionChoice(value: 10, label: '10x'),
          ],
          defaultValue: [2, 3, 5],
          group: 'Symbol',
          order: 31,
          visibleWhen: {'symbol_wild_multiplier': true},
        ),

        BlockOptionFactory.dropdown(
          id: 'symbol_combine',
          name: 'Symbol Combination',
          description: 'How multiple symbol multipliers combine',
          choices: const [
            OptionChoice(
              value: 'multiply',
              label: 'Multiply',
              description: '2x × 3x = 6x',
            ),
            OptionChoice(
              value: 'add',
              label: 'Add',
              description: '2x + 3x = 5x',
            ),
            OptionChoice(
              value: 'sum_then_mult',
              label: 'Sum Then Multiply',
              description: '(2 + 3)x = 5x',
            ),
          ],
          defaultValue: 'multiply',
          group: 'Symbol',
          order: 32,
          visibleWhen: {'enable_symbol': true},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Random Multiplier Settings
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.percentage(
          id: 'random_trigger_chance',
          name: 'Trigger Chance',
          description: 'Chance per spin to trigger random multiplier',
          defaultValue: 5.0,
          group: 'Random',
          order: 40,
          visibleWhen: {'enable_random': true},
        ),

        BlockOptionFactory.multiSelect(
          id: 'random_values',
          name: 'Possible Values',
          description: 'Random multiplier value pool',
          choices: const [
            OptionChoice(value: 2, label: '2x'),
            OptionChoice(value: 3, label: '3x'),
            OptionChoice(value: 5, label: '5x'),
            OptionChoice(value: 10, label: '10x'),
            OptionChoice(value: 15, label: '15x'),
            OptionChoice(value: 20, label: '20x'),
            OptionChoice(value: 50, label: '50x'),
            OptionChoice(value: 100, label: '100x'),
          ],
          defaultValue: [2, 3, 5, 10],
          group: 'Random',
          order: 41,
          visibleWhen: {'enable_random': true},
        ),

        BlockOptionFactory.toggle(
          id: 'random_weighted',
          name: 'Weighted Distribution',
          description: 'Lower values more common than higher',
          defaultValue: true,
          group: 'Random',
          order: 42,
          visibleWhen: {'enable_random': true},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Presentation
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.dropdown(
          id: 'display_style',
          name: 'Display Style',
          description: 'How multiplier is shown',
          choices: const [
            OptionChoice(
              value: 'overlay',
              label: 'Overlay',
              description: 'Overlay on reels',
            ),
            OptionChoice(
              value: 'meter',
              label: 'Meter',
              description: 'Separate meter display',
            ),
            OptionChoice(
              value: 'counter',
              label: 'Counter',
              description: 'Numeric counter',
            ),
            OptionChoice(
              value: 'badge',
              label: 'Badge',
              description: 'Symbol badge indicator',
            ),
          ],
          defaultValue: 'overlay',
          group: 'Presentation',
          order: 50,
        ),

        BlockOptionFactory.toggle(
          id: 'animate_increase',
          name: 'Animate Increase',
          description: 'Play animation when multiplier increases',
          defaultValue: true,
          group: 'Presentation',
          order: 51,
        ),

        BlockOptionFactory.toggle(
          id: 'show_applied',
          name: 'Show Applied',
          description: 'Show multiplier being applied to win',
          defaultValue: true,
          group: 'Presentation',
          order: 52,
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Audio Stages
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'stage_increase',
          name: 'Increase Stage',
          description: 'Audio when multiplier increases',
          defaultValue: true,
          group: 'Audio',
          order: 60,
        ),

        BlockOptionFactory.toggle(
          id: 'stage_apply',
          name: 'Apply Stage',
          description: 'Audio when multiplier applied to win',
          defaultValue: true,
          group: 'Audio',
          order: 61,
        ),

        BlockOptionFactory.toggle(
          id: 'stage_tier_specific',
          name: 'Tier-Specific',
          description: 'Different audio for different multiplier ranges',
          defaultValue: true,
          group: 'Audio',
          order: 62,
        ),

        BlockOptionFactory.toggle(
          id: 'stage_max_reached',
          name: 'Max Reached',
          description: 'Special audio when max multiplier reached',
          defaultValue: true,
          group: 'Audio',
          order: 63,
        ),
      ];

  // ============================================================================
  // Dependencies
  // ============================================================================

  @override
  List<BlockDependency> createDependencies() => [
        BlockDependency.requires(
          source: id,
          target: 'game_core',
          description: 'Multiplier needs base game configuration',
        ),
        BlockDependency.modifies(
          source: id,
          target: 'cascades',
          description: 'Cascade multipliers use cascade mechanic',
        ),
        BlockDependency.modifies(
          source: id,
          target: 'free_spins',
          description: 'Multipliers often persist during free spins',
        ),
        BlockDependency.modifies(
          source: id,
          target: 'symbol_set',
          description: 'Wilds can carry symbol multipliers',
        ),
      ];

  // ============================================================================
  // Stage Generation
  // ============================================================================

  @override
  List<String> get pooledStages => const [
        'MULTIPLIER_INCREASE',
        'MULTIPLIER_APPLY',
      ];

  @override
  String getBusForStage(String stageName) {
    if (stageName.contains('MAX')) return 'wins';
    return 'sfx';
  }

  @override
  int getPriorityForStage(String stageName) {
    if (stageName.contains('MAX')) return 85;
    if (stageName.contains('APPLY')) return 75;
    return 65;
  }

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];
    if (!isEnabled) return stages;

    final enableGlobal = getOptionValue<bool>('enable_global') ?? true;
    final enableReel = getOptionValue<bool>('enable_reel') ?? false;
    final enableSymbol = getOptionValue<bool>('enable_symbol') ?? false;
    final enableRandom = getOptionValue<bool>('enable_random') ?? false;
    final stageIncrease = getOptionValue<bool>('stage_increase') ?? true;
    final stageApply = getOptionValue<bool>('stage_apply') ?? true;
    final stageTierSpecific = getOptionValue<bool>('stage_tier_specific') ?? true;
    final stageMaxReached = getOptionValue<bool>('stage_max_reached') ?? true;

    // ═══════════════════════════════════════════════════════════════════════
    // Global multiplier stages
    // ═══════════════════════════════════════════════════════════════════════
    if (enableGlobal) {
      if (stageIncrease) {
        stages.add(GeneratedStage(
          name: 'MULTIPLIER_INCREASE',
          description: 'Global multiplier increased',
          bus: 'sfx',
          priority: 70,
          pooled: true,
          sourceBlockId: id,
        ));

        if (stageTierSpecific) {
          // Low tier: 1-5x
          stages.add(GeneratedStage(
            name: 'MULTIPLIER_INCREASE_LOW',
            description: 'Multiplier increased (1-5x range)',
            bus: 'sfx',
            priority: 65,
            pooled: true,
            sourceBlockId: id,
          ));
          // Medium tier: 5-20x
          stages.add(GeneratedStage(
            name: 'MULTIPLIER_INCREASE_MEDIUM',
            description: 'Multiplier increased (5-20x range)',
            bus: 'sfx',
            priority: 70,
            pooled: true,
            sourceBlockId: id,
          ));
          // High tier: 20-100x
          stages.add(GeneratedStage(
            name: 'MULTIPLIER_INCREASE_HIGH',
            description: 'Multiplier increased (20-100x range)',
            bus: 'sfx',
            priority: 75,
            sourceBlockId: id,
          ));
          // Extreme tier: 100x+
          stages.add(GeneratedStage(
            name: 'MULTIPLIER_INCREASE_EXTREME',
            description: 'Multiplier increased (100x+ range)',
            bus: 'wins',
            priority: 80,
            sourceBlockId: id,
          ));
        }
      }

      if (stageApply) {
        stages.add(GeneratedStage(
          name: 'MULTIPLIER_APPLY',
          description: 'Multiplier applied to win',
          bus: 'sfx',
          priority: 75,
          pooled: true,
          sourceBlockId: id,
        ));
      }

      if (stageMaxReached) {
        stages.add(GeneratedStage(
          name: 'MULTIPLIER_MAX_REACHED',
          description: 'Maximum multiplier value reached',
          bus: 'wins',
          priority: 85,
          sourceBlockId: id,
        ));
      }

      stages.add(GeneratedStage(
        name: 'MULTIPLIER_RESET',
        description: 'Multiplier reset to starting value',
        bus: 'sfx',
        priority: 50,
        sourceBlockId: id,
      ));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Reel multiplier stages
    // ═══════════════════════════════════════════════════════════════════════
    if (enableReel) {
      stages.add(GeneratedStage(
        name: 'REEL_MULTIPLIER_APPEAR',
        description: 'Multiplier appeared on reel',
        bus: 'sfx',
        priority: 68,
        sourceBlockId: id,
      ));

      stages.add(GeneratedStage(
        name: 'REEL_MULTIPLIER_LAND',
        description: 'Reel with multiplier stopped',
        bus: 'sfx',
        priority: 70,
        pooled: true,
        sourceBlockId: id,
      ));

      stages.add(GeneratedStage(
        name: 'REEL_MULTIPLIER_APPLY',
        description: 'Reel multiplier applied',
        bus: 'sfx',
        priority: 75,
        sourceBlockId: id,
      ));

      stages.add(GeneratedStage(
        name: 'REEL_MULTIPLIER_COMBINE',
        description: 'Multiple reel multipliers combining',
        bus: 'sfx',
        priority: 78,
        sourceBlockId: id,
      ));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Symbol multiplier stages
    // ═══════════════════════════════════════════════════════════════════════
    if (enableSymbol) {
      stages.add(GeneratedStage(
        name: 'SYMBOL_MULTIPLIER_LAND',
        description: 'Symbol with multiplier landed',
        bus: 'sfx',
        priority: 68,
        pooled: true,
        sourceBlockId: id,
      ));

      stages.add(GeneratedStage(
        name: 'SYMBOL_MULTIPLIER_IN_WIN',
        description: 'Multiplier symbol part of winning line',
        bus: 'sfx',
        priority: 72,
        sourceBlockId: id,
      ));

      stages.add(GeneratedStage(
        name: 'SYMBOL_MULTIPLIER_APPLY',
        description: 'Symbol multiplier applied to win',
        bus: 'sfx',
        priority: 75,
        sourceBlockId: id,
      ));

      stages.add(GeneratedStage(
        name: 'SYMBOL_MULTIPLIER_COMBINE',
        description: 'Multiple symbol multipliers combining',
        bus: 'sfx',
        priority: 78,
        sourceBlockId: id,
      ));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Random multiplier stages
    // ═══════════════════════════════════════════════════════════════════════
    if (enableRandom) {
      stages.add(GeneratedStage(
        name: 'RANDOM_MULTIPLIER_TRIGGER',
        description: 'Random multiplier triggered',
        bus: 'sfx',
        priority: 70,
        sourceBlockId: id,
      ));

      stages.add(GeneratedStage(
        name: 'RANDOM_MULTIPLIER_REVEAL',
        description: 'Random multiplier value revealed',
        bus: 'sfx',
        priority: 75,
        sourceBlockId: id,
      ));

      stages.add(GeneratedStage(
        name: 'RANDOM_MULTIPLIER_APPLY',
        description: 'Random multiplier applied',
        bus: 'sfx',
        priority: 78,
        sourceBlockId: id,
      ));

      if (stageTierSpecific) {
        stages.add(GeneratedStage(
          name: 'RANDOM_MULTIPLIER_BIG',
          description: 'Large random multiplier awarded (10x+)',
          bus: 'wins',
          priority: 82,
          sourceBlockId: id,
        ));
        stages.add(GeneratedStage(
          name: 'RANDOM_MULTIPLIER_HUGE',
          description: 'Huge random multiplier awarded (50x+)',
          bus: 'wins',
          priority: 88,
          sourceBlockId: id,
        ));
      }
    }

    return stages;
  }
}
