// ============================================================================
// FluxForge Studio — Collector Block
// ============================================================================
// P13.1.5: Feature block for Symbol Collection mechanics
// Defines collection triggers, meters, rewards, and progression.
// ============================================================================

import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';
import '../models/feature_builder/feature_block.dart';

/// What can be collected.
enum CollectibleType {
  /// Specific symbols are collected.
  symbols,

  /// Coin values are collected.
  coins,

  /// Multiplier values are collected.
  multipliers,

  /// Win amounts are collected.
  wins,

  /// Feature fragments are collected.
  fragments,
}

/// Meter behavior when full.
enum MeterFullBehavior {
  /// Award prize immediately.
  awardPrize,

  /// Trigger free spins.
  triggerFreeSpins,

  /// Trigger bonus game.
  triggerBonus,

  /// Upgrade symbol tier.
  upgradeSymbol,

  /// Reset with higher tier.
  resetUpgraded,
}

/// Collection persistence.
enum CollectionPersistence {
  /// Resets each spin.
  perSpin,

  /// Persists across spins.
  persistent,

  /// Only in feature.
  featureOnly,

  /// Session-based (saves between sessions).
  session,
}

/// Feature block for Symbol Collection configuration.
///
/// This block defines:
/// - What symbols/values can be collected
/// - Collection meter configuration
/// - Rewards when meter is full
/// - Collection persistence and progression
/// - Audio stages for collection phases
class CollectorBlock extends FeatureBlockBase {
  CollectorBlock() : super(enabled: false);

  @override
  String get id => 'collector';

  @override
  String get name => 'Symbol Collector';

  @override
  String get description =>
      'Collection meters with progressive rewards and upgrades';

  @override
  BlockCategory get category => BlockCategory.feature;

  @override
  String get iconName => 'inventory_2';

  @override
  bool get canBeDisabled => true;

  @override
  int get stagePriority => 18;

  @override
  List<BlockOption> createOptions() => [
        // ========== Collection Target ==========
        BlockOptionFactory.dropdown(
          id: 'collectibleType',
          name: 'Collectible Type',
          description: 'What is being collected',
          choices: [
            const OptionChoice(
              value: 'symbols',
              label: 'Symbols',
              description: 'Collect specific symbols',
            ),
            const OptionChoice(
              value: 'coins',
              label: 'Coins',
              description: 'Collect coin values',
            ),
            const OptionChoice(
              value: 'multipliers',
              label: 'Multipliers',
              description: 'Collect multiplier values',
            ),
            const OptionChoice(
              value: 'wins',
              label: 'Wins',
              description: 'Collect win amounts',
            ),
            const OptionChoice(
              value: 'fragments',
              label: 'Fragments',
              description: 'Collect feature fragments',
            ),
          ],
          defaultValue: 'symbols',
          group: 'Collection',
          order: 1,
        ),

        BlockOptionFactory.toggle(
          id: 'collectSpecificSymbol',
          name: 'Specific Symbol Only',
          description: 'Only collect one symbol type',
          defaultValue: false,
          group: 'Collection',
          order: 2,
        ),

        BlockOptionFactory.toggle(
          id: 'collectWilds',
          name: 'Collect Wilds',
          description: 'Wild symbols count toward collection',
          defaultValue: true,
          group: 'Collection',
          order: 3,
        ),

        BlockOptionFactory.toggle(
          id: 'collectScatters',
          name: 'Collect Scatters',
          description: 'Scatter symbols count toward collection',
          defaultValue: false,
          group: 'Collection',
          order: 4,
        ),

        BlockOptionFactory.toggle(
          id: 'collectFromWins',
          name: 'Collect From Wins Only',
          description: 'Only collect symbols from winning combinations',
          defaultValue: false,
          group: 'Collection',
          order: 5,
        ),

        // ========== Meter Configuration ==========
        BlockOptionFactory.count(
          id: 'meterCount',
          name: 'Number of Meters',
          description: 'How many collection meters',
          min: 1,
          max: 6,
          defaultValue: 1,
          group: 'Meter',
          order: 6,
        ),

        BlockOptionFactory.count(
          id: 'meterSize',
          name: 'Meter Size',
          description: 'Symbols needed to fill meter',
          min: 5,
          max: 100,
          defaultValue: 25,
          group: 'Meter',
          order: 7,
        ),

        BlockOptionFactory.toggle(
          id: 'hasPartialRewards',
          name: 'Partial Rewards',
          description: 'Rewards at meter milestones',
          defaultValue: true,
          group: 'Meter',
          order: 8,
        ),

        BlockOptionFactory.count(
          id: 'milestoneCount',
          name: 'Milestone Count',
          description: 'Number of milestone rewards',
          min: 0,
          max: 5,
          defaultValue: 3,
          group: 'Meter',
          order: 9,
        ),

        BlockOptionFactory.toggle(
          id: 'meterVisible',
          name: 'Meter Always Visible',
          description: 'Show meter on screen always',
          defaultValue: true,
          group: 'Meter',
          order: 10,
        ),

        // ========== Meter Behavior ==========
        BlockOptionFactory.dropdown(
          id: 'meterFullBehavior',
          name: 'When Meter Full',
          description: 'What happens when meter is full',
          choices: [
            const OptionChoice(
              value: 'awardPrize',
              label: 'Award Prize',
              description: 'Award coin/multiplier prize',
            ),
            const OptionChoice(
              value: 'triggerFreeSpins',
              label: 'Trigger Free Spins',
              description: 'Start free spins bonus',
            ),
            const OptionChoice(
              value: 'triggerBonus',
              label: 'Trigger Bonus',
              description: 'Start bonus game',
            ),
            const OptionChoice(
              value: 'upgradeSymbol',
              label: 'Upgrade Symbol',
              description: 'Upgrade collected symbol',
            ),
            const OptionChoice(
              value: 'resetUpgraded',
              label: 'Reset Upgraded',
              description: 'Reset meter with bigger rewards',
            ),
          ],
          defaultValue: 'awardPrize',
          group: 'Behavior',
          order: 11,
        ),

        BlockOptionFactory.dropdown(
          id: 'persistence',
          name: 'Collection Persistence',
          description: 'How long collection persists',
          choices: [
            const OptionChoice(
              value: 'perSpin',
              label: 'Per Spin',
              description: 'Resets each spin',
            ),
            const OptionChoice(
              value: 'persistent',
              label: 'Persistent',
              description: 'Persists across spins',
            ),
            const OptionChoice(
              value: 'featureOnly',
              label: 'Feature Only',
              description: 'Only during features',
            ),
            const OptionChoice(
              value: 'session',
              label: 'Session',
              description: 'Saves between sessions',
            ),
          ],
          defaultValue: 'persistent',
          group: 'Behavior',
          order: 12,
        ),

        BlockOptionFactory.toggle(
          id: 'resetOnFeature',
          name: 'Reset on Feature',
          description: 'Reset meter when feature triggers',
          defaultValue: true,
          group: 'Behavior',
          order: 13,
        ),

        // ========== Rewards Configuration ==========
        BlockOptionFactory.count(
          id: 'basePrizeMultiplier',
          name: 'Base Prize (x bet)',
          description: 'Base prize when meter is full',
          min: 5,
          max: 100,
          defaultValue: 10,
          group: 'Rewards',
          order: 14,
        ),

        BlockOptionFactory.toggle(
          id: 'hasProgressiveRewards',
          name: 'Progressive Rewards',
          description: 'Rewards increase with each fill',
          defaultValue: true,
          group: 'Rewards',
          order: 15,
        ),

        BlockOptionFactory.count(
          id: 'rewardIncrementPercent',
          name: 'Reward Increment %',
          description: 'Percentage increase per fill',
          min: 10,
          max: 100,
          defaultValue: 25,
          group: 'Rewards',
          order: 16,
        ),

        BlockOptionFactory.count(
          id: 'freeSpinsReward',
          name: 'Free Spins Reward',
          description: 'Free spins when meter full (if applicable)',
          min: 3,
          max: 30,
          defaultValue: 10,
          group: 'Rewards',
          order: 17,
        ),

        // ========== Symbol Upgrade Configuration ==========
        BlockOptionFactory.toggle(
          id: 'hasSymbolUpgrade',
          name: 'Symbol Upgrade Path',
          description: 'Collected symbols can upgrade',
          defaultValue: false,
          group: 'Upgrades',
          order: 18,
        ),

        BlockOptionFactory.count(
          id: 'upgradeTiers',
          name: 'Upgrade Tiers',
          description: 'Number of upgrade levels',
          min: 2,
          max: 5,
          defaultValue: 3,
          group: 'Upgrades',
          order: 19,
        ),

        BlockOptionFactory.toggle(
          id: 'upgradeVisual',
          name: 'Visual Upgrade Effect',
          description: 'Symbol appearance changes on upgrade',
          defaultValue: true,
          group: 'Upgrades',
          order: 20,
        ),

        // ========== Collection Animation ==========
        BlockOptionFactory.toggle(
          id: 'flyToMeter',
          name: 'Fly to Meter',
          description: 'Symbols animate flying to meter',
          defaultValue: true,
          group: 'Animation',
          order: 21,
        ),

        BlockOptionFactory.count(
          id: 'collectDelay',
          name: 'Collection Delay (ms)',
          description: 'Delay between symbol collections',
          min: 50,
          max: 500,
          defaultValue: 100,
          group: 'Animation',
          order: 22,
        ),

        BlockOptionFactory.toggle(
          id: 'simultaneousCollection',
          name: 'Simultaneous Collection',
          description: 'Collect all symbols at once',
          defaultValue: false,
          group: 'Animation',
          order: 23,
        ),

        // ========== Audio Settings ==========
        BlockOptionFactory.toggle(
          id: 'hasCollectSound',
          name: 'Collection Sound',
          description: 'Sound when symbol is collected',
          defaultValue: true,
          group: 'Audio',
          order: 24,
        ),

        BlockOptionFactory.toggle(
          id: 'hasMilestoneSound',
          name: 'Milestone Sound',
          description: 'Sound at meter milestones',
          defaultValue: true,
          group: 'Audio',
          order: 25,
        ),

        BlockOptionFactory.toggle(
          id: 'hasMeterFullSound',
          name: 'Meter Full Sound',
          description: 'Sound when meter is full',
          defaultValue: true,
          group: 'Audio',
          order: 26,
        ),

        BlockOptionFactory.toggle(
          id: 'hasUpgradeSound',
          name: 'Upgrade Sound',
          description: 'Sound when symbol upgrades',
          defaultValue: true,
          group: 'Audio',
          order: 27,
        ),
      ];

  @override
  List<BlockDependency> createDependencies() => [
        // Requires Game Core
        BlockDependency.requires(
          source: id,
          target: 'game_core',
          description: 'Collector requires Game Core configuration',
          autoResolvable: true,
        ),

        // Requires Symbol Set
        BlockDependency.requires(
          source: id,
          target: 'symbol_set',
          description: 'Collector requires Symbol Set configuration',
          autoResolvable: true,
        ),

        // Enables Free Spins if trigger behavior
        if (getOptionValue<String>('meterFullBehavior') == 'triggerFreeSpins')
          BlockDependency.requires(
            source: id,
            target: 'free_spins',
            description: 'Collector triggers Free Spins when full',
            autoResolvable: true,
          ),

        // Modifies Win Presentation
        BlockDependency.modifies(
          source: id,
          target: 'win_presentation',
          description: 'Collector adds collection animations to wins',
        ),
      ];

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];
    final hasCollectSound = getOptionValue<bool>('hasCollectSound') ?? true;
    final hasMilestoneSound = getOptionValue<bool>('hasMilestoneSound') ?? true;
    final hasMeterFullSound = getOptionValue<bool>('hasMeterFullSound') ?? true;
    final hasUpgradeSound = getOptionValue<bool>('hasUpgradeSound') ?? true;
    final hasPartialRewards = getOptionValue<bool>('hasPartialRewards') ?? true;
    final hasSymbolUpgrade = getOptionValue<bool>('hasSymbolUpgrade') ?? false;
    final meterCount = getOptionValue<int>('meterCount') ?? 1;
    final milestoneCount = getOptionValue<int>('milestoneCount') ?? 3;
    final meterFullBehavior = getOptionValue<String>('meterFullBehavior') ?? 'awardPrize';

    // ========== Collection Stages ==========
    if (hasCollectSound) {
      stages.add(GeneratedStage(
        name: 'COLLECT_SYMBOL',
        description: 'Symbol collected to meter',
        bus: 'sfx',
        priority: 65,
        pooled: true, // Many symbols collected
        sourceBlockId: id,
        category: 'Collector',
      ));

      stages.add(GeneratedStage(
        name: 'COLLECT_FLY_START',
        description: 'Symbol starts flying to meter',
        bus: 'sfx',
        priority: 62,
        pooled: true,
        sourceBlockId: id,
        category: 'Collector',
      ));

      stages.add(GeneratedStage(
        name: 'COLLECT_FLY_END',
        description: 'Symbol arrives at meter',
        bus: 'sfx',
        priority: 64,
        pooled: true,
        sourceBlockId: id,
        category: 'Collector',
      ));
    }

    // ========== Per-Meter Stages ==========
    for (var i = 1; i <= meterCount; i++) {
      final suffix = meterCount > 1 ? '_$i' : '';

      stages.add(GeneratedStage(
        name: 'COLLECT_METER_UPDATE$suffix',
        description: 'Meter $i value updated',
        bus: 'ui',
        priority: 50,
        pooled: true,
        sourceBlockId: id,
        category: 'Collector',
      ));

      if (hasMeterFullSound) {
        stages.add(GeneratedStage(
          name: 'COLLECT_METER_FULL$suffix',
          description: 'Meter $i is full',
          bus: 'sfx',
          priority: 85,
          sourceBlockId: id,
          category: 'Collector',
        ));
      }
    }

    // ========== Milestone Stages ==========
    if (hasPartialRewards && hasMilestoneSound) {
      for (var i = 1; i <= milestoneCount; i++) {
        stages.add(GeneratedStage(
          name: 'COLLECT_MILESTONE_$i',
          description: 'Reached milestone $i',
          bus: 'sfx',
          priority: 70 + i,
          sourceBlockId: id,
          category: 'Collector',
        ));
      }

      stages.add(GeneratedStage(
        name: 'COLLECT_MILESTONE_REWARD',
        description: 'Milestone reward awarded',
        bus: 'sfx',
        priority: 75,
        sourceBlockId: id,
        category: 'Collector',
      ));
    }

    // ========== Reward Stages ==========
    stages.add(GeneratedStage(
      name: 'COLLECT_REWARD_START',
      description: 'Collection reward begins',
      bus: 'sfx',
      priority: 82,
      sourceBlockId: id,
      category: 'Collector',
    ));

    // Behavior-specific reward stages
    switch (meterFullBehavior) {
      case 'awardPrize':
        stages.add(GeneratedStage(
          name: 'COLLECT_PRIZE_AWARD',
          description: 'Prize value awarded',
          bus: 'sfx',
          priority: 84,
          sourceBlockId: id,
          category: 'Collector',
        ));
        break;
      case 'triggerFreeSpins':
        stages.add(GeneratedStage(
          name: 'COLLECT_FS_TRIGGER',
          description: 'Free spins triggered by collection',
          bus: 'sfx',
          priority: 88,
          sourceBlockId: id,
          category: 'Collector',
        ));
        break;
      case 'triggerBonus':
        stages.add(GeneratedStage(
          name: 'COLLECT_BONUS_TRIGGER',
          description: 'Bonus game triggered by collection',
          bus: 'sfx',
          priority: 88,
          sourceBlockId: id,
          category: 'Collector',
        ));
        break;
      case 'upgradeSymbol':
        // Handled in upgrade stages below
        break;
      case 'resetUpgraded':
        stages.add(GeneratedStage(
          name: 'COLLECT_RESET_UPGRADE',
          description: 'Meter resets with higher tier',
          bus: 'sfx',
          priority: 80,
          sourceBlockId: id,
          category: 'Collector',
        ));
        break;
    }

    stages.add(GeneratedStage(
      name: 'COLLECT_REWARD_END',
      description: 'Collection reward complete',
      bus: 'sfx',
      priority: 78,
      sourceBlockId: id,
      category: 'Collector',
    ));

    // ========== Upgrade Stages ==========
    if (hasSymbolUpgrade && hasUpgradeSound) {
      stages.add(GeneratedStage(
        name: 'COLLECT_UPGRADE_START',
        description: 'Symbol upgrade begins',
        bus: 'sfx',
        priority: 78,
        sourceBlockId: id,
        category: 'Collector',
      ));

      stages.add(GeneratedStage(
        name: 'COLLECT_UPGRADE_TRANSFORM',
        description: 'Symbol transforms to higher tier',
        bus: 'sfx',
        priority: 80,
        sourceBlockId: id,
        category: 'Collector',
      ));

      stages.add(GeneratedStage(
        name: 'COLLECT_UPGRADE_COMPLETE',
        description: 'Symbol upgrade complete',
        bus: 'sfx',
        priority: 76,
        sourceBlockId: id,
        category: 'Collector',
      ));

      stages.add(GeneratedStage(
        name: 'COLLECT_UPGRADE_MAX',
        description: 'Symbol at maximum upgrade level',
        bus: 'sfx',
        priority: 85,
        sourceBlockId: id,
        category: 'Collector',
      ));
    }

    // ========== Reset Stages ==========
    stages.add(GeneratedStage(
      name: 'COLLECT_METER_RESET',
      description: 'Collection meter resets',
      bus: 'sfx',
      priority: 55,
      sourceBlockId: id,
      category: 'Collector',
    ));

    // ========== Special Collection Stages ==========
    stages.add(GeneratedStage(
      name: 'COLLECT_MULTI',
      description: 'Multiple symbols collected at once',
      bus: 'sfx',
      priority: 68,
      sourceBlockId: id,
      category: 'Collector',
    ));

    stages.add(GeneratedStage(
      name: 'COLLECT_COMBO',
      description: 'Collection combo bonus',
      bus: 'sfx',
      priority: 72,
      sourceBlockId: id,
      category: 'Collector',
    ));

    return stages;
  }

  @override
  List<String> get pooledStages => [
        'COLLECT_SYMBOL',
        'COLLECT_FLY_START',
        'COLLECT_FLY_END',
        'COLLECT_METER_UPDATE',
        'COLLECT_METER_UPDATE_1',
        'COLLECT_METER_UPDATE_2',
        'COLLECT_METER_UPDATE_3',
        'COLLECT_METER_UPDATE_4',
        'COLLECT_METER_UPDATE_5',
        'COLLECT_METER_UPDATE_6',
      ];

  @override
  String getBusForStage(String stageName) {
    if (stageName.contains('METER_UPDATE')) return 'ui';
    return 'sfx';
  }

  @override
  int getPriorityForStage(String stageName) {
    if (stageName.contains('TRIGGER')) return 88;
    if (stageName.contains('FULL')) return 85;
    if (stageName.contains('UPGRADE_MAX')) return 85;
    if (stageName.contains('REWARD')) return 82;
    if (stageName.contains('UPGRADE')) return 78;
    if (stageName.contains('MILESTONE')) return 72;
    if (stageName.contains('COLLECT_SYMBOL')) return 65;
    if (stageName.contains('METER_UPDATE')) return 50;
    return 60;
  }

  // ============================================================================
  // Convenience Getters
  // ============================================================================

  /// Get collectible type.
  CollectibleType get collectibleType {
    final value = getOptionValue<String>('collectibleType') ?? 'symbols';
    return CollectibleType.values.firstWhere(
      (c) => c.name == value,
      orElse: () => CollectibleType.symbols,
    );
  }

  /// Get meter full behavior.
  MeterFullBehavior get meterFullBehavior {
    final value = getOptionValue<String>('meterFullBehavior') ?? 'awardPrize';
    return MeterFullBehavior.values.firstWhere(
      (m) => m.name == value,
      orElse: () => MeterFullBehavior.awardPrize,
    );
  }

  /// Get collection persistence.
  CollectionPersistence get persistence {
    final value = getOptionValue<String>('persistence') ?? 'persistent';
    return CollectionPersistence.values.firstWhere(
      (p) => p.name == value,
      orElse: () => CollectionPersistence.persistent,
    );
  }

  /// Get meter count.
  int get meterCount => getOptionValue<int>('meterCount') ?? 1;

  /// Get meter size.
  int get meterSize => getOptionValue<int>('meterSize') ?? 25;

  /// Get milestone count.
  int get milestoneCount => getOptionValue<int>('milestoneCount') ?? 3;

  /// Get base prize multiplier.
  int get basePrizeMultiplier => getOptionValue<int>('basePrizeMultiplier') ?? 10;

  /// Whether wilds are collected.
  bool get collectsWilds => getOptionValue<bool>('collectWilds') ?? true;

  /// Whether scatters are collected.
  bool get collectsScatters => getOptionValue<bool>('collectScatters') ?? false;

  /// Get collection delay.
  int get collectDelay => getOptionValue<int>('collectDelay') ?? 100;

  /// Whether symbols fly to meter.
  bool get flyToMeter => getOptionValue<bool>('flyToMeter') ?? true;
}
