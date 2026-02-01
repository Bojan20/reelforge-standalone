// ============================================================================
// FluxForge Studio — Hold & Win Block
// ============================================================================
// P13.1.3: Feature block for Hold & Win (Lightning Link style) configuration
// Defines coin symbols, jackpots, respins, and prize collection mechanics.
// ============================================================================

import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';
import '../models/feature_builder/feature_block.dart';

/// Jackpot tier definitions.
enum JackpotTier {
  /// Mini jackpot (smallest).
  mini,

  /// Minor jackpot.
  minor,

  /// Major jackpot.
  major,

  /// Grand jackpot (largest).
  grand,

  /// Mega jackpot (optional top tier).
  mega,
}

/// Coin value type.
enum CoinValueType {
  /// Fixed bet multiplier.
  fixedMultiplier,

  /// Random from range.
  randomRange,

  /// Weighted random values.
  weightedRandom,

  /// Progressive based on position.
  positional,
}

/// Hold & Win mode variation.
enum HoldAndWinMode {
  /// Classic Lightning Link style.
  classic,

  /// Cash on Reels (any position).
  cashOnReels,

  /// Link & Win (connected symbols).
  linkAndWin,

  /// Coin Collector (collect mechanics).
  coinCollector,
}

/// Feature block for Hold & Win configuration.
///
/// This block defines:
/// - Trigger conditions and coin symbols
/// - Jackpot tiers and values
/// - Respin mechanics and progression
/// - Coin value configuration
/// - Special Hold & Win features
/// - Audio stages for all phases
class HoldAndWinBlock extends FeatureBlockBase {
  HoldAndWinBlock() : super(enabled: false);

  @override
  String get id => 'hold_and_win';

  @override
  String get name => 'Hold & Win';

  @override
  String get description =>
      'Lightning Link style feature with coins, jackpots, and respins';

  @override
  BlockCategory get category => BlockCategory.feature;

  @override
  String get iconName => 'casino';

  @override
  bool get canBeDisabled => true;

  @override
  int get stagePriority => 12;

  @override
  List<BlockOption> createOptions() => [
        // ========== Mode & Trigger ==========
        BlockOptionFactory.dropdown(
          id: 'mode',
          name: 'Hold & Win Mode',
          description: 'Variation of Hold & Win mechanics',
          choices: [
            const OptionChoice(
              value: 'classic',
              label: 'Classic',
              description: 'Lightning Link style',
            ),
            const OptionChoice(
              value: 'cashOnReels',
              label: 'Cash on Reels',
              description: 'Any position coin collection',
            ),
            const OptionChoice(
              value: 'linkAndWin',
              label: 'Link & Win',
              description: 'Connected symbols bonus',
            ),
            const OptionChoice(
              value: 'coinCollector',
              label: 'Coin Collector',
              description: 'Collection mechanics',
            ),
          ],
          defaultValue: 'classic',
          group: 'Mode',
          order: 1,
        ),

        BlockOptionFactory.count(
          id: 'minCoinsToTrigger',
          name: 'Min Coins to Trigger',
          description: 'Minimum coin symbols to trigger feature',
          min: 4,
          max: 8,
          defaultValue: 6,
          group: 'Trigger',
          order: 2,
        ),

        BlockOptionFactory.toggle(
          id: 'triggerInFreeSpins',
          name: 'Trigger in Free Spins',
          description: 'Can trigger during free spins',
          defaultValue: true,
          group: 'Trigger',
          order: 3,
        ),

        // ========== Respins Configuration ==========
        BlockOptionFactory.count(
          id: 'initialRespins',
          name: 'Initial Respins',
          description: 'Starting respin count',
          min: 1,
          max: 5,
          defaultValue: 3,
          group: 'Respins',
          order: 4,
        ),

        BlockOptionFactory.toggle(
          id: 'respinsReset',
          name: 'Respins Reset on Land',
          description: 'Respins reset when new coin lands',
          defaultValue: true,
          group: 'Respins',
          order: 5,
        ),

        BlockOptionFactory.count(
          id: 'maxRespins',
          name: 'Max Respins',
          description: 'Maximum respins (0 = start value is max)',
          min: 0,
          max: 10,
          defaultValue: 0,
          group: 'Respins',
          order: 6,
        ),

        BlockOptionFactory.toggle(
          id: 'stickyCoins',
          name: 'Sticky Coins',
          description: 'Coins stay in place during respins',
          defaultValue: true,
          group: 'Respins',
          order: 7,
        ),

        // ========== Jackpot Configuration ==========
        BlockOptionFactory.toggle(
          id: 'hasJackpots',
          name: 'Has Jackpots',
          description: 'Enable jackpot prizes',
          defaultValue: true,
          group: 'Jackpots',
          order: 8,
        ),

        BlockOptionFactory.count(
          id: 'jackpotTierCount',
          name: 'Jackpot Tiers',
          description: 'Number of jackpot tiers (1-5)',
          min: 1,
          max: 5,
          defaultValue: 4,
          group: 'Jackpots',
          order: 9,
        ),

        BlockOptionFactory.toggle(
          id: 'progressiveJackpots',
          name: 'Progressive Jackpots',
          description: 'Jackpots grow over time',
          defaultValue: true,
          group: 'Jackpots',
          order: 10,
        ),

        // Jackpot values (bet multipliers)
        BlockOptionFactory.count(
          id: 'miniJackpotValue',
          name: 'Mini Jackpot',
          description: 'Mini jackpot value (bet multiplier)',
          min: 10,
          max: 100,
          defaultValue: 20,
          group: 'Jackpots',
          order: 11,
        ),

        BlockOptionFactory.count(
          id: 'minorJackpotValue',
          name: 'Minor Jackpot',
          description: 'Minor jackpot value (bet multiplier)',
          min: 25,
          max: 250,
          defaultValue: 50,
          group: 'Jackpots',
          order: 12,
        ),

        BlockOptionFactory.count(
          id: 'majorJackpotValue',
          name: 'Major Jackpot',
          description: 'Major jackpot value (bet multiplier)',
          min: 100,
          max: 1000,
          defaultValue: 250,
          group: 'Jackpots',
          order: 13,
        ),

        BlockOptionFactory.count(
          id: 'grandJackpotValue',
          name: 'Grand Jackpot',
          description: 'Grand jackpot value (bet multiplier)',
          min: 500,
          max: 5000,
          defaultValue: 1000,
          group: 'Jackpots',
          order: 14,
        ),

        BlockOptionFactory.toggle(
          id: 'gridFullBonusJackpot',
          name: 'Grid Full = Grand',
          description: 'Filling grid awards Grand jackpot',
          defaultValue: true,
          group: 'Jackpots',
          order: 15,
        ),

        // ========== Coin Values ==========
        BlockOptionFactory.dropdown(
          id: 'coinValueType',
          name: 'Coin Value Type',
          description: 'How coin values are determined',
          choices: [
            const OptionChoice(
              value: 'fixedMultiplier',
              label: 'Fixed Multipliers',
              description: 'Set multiplier values',
            ),
            const OptionChoice(
              value: 'randomRange',
              label: 'Random Range',
              description: 'Random from min/max range',
            ),
            const OptionChoice(
              value: 'weightedRandom',
              label: 'Weighted Random',
              description: 'Weighted value selection',
            ),
            const OptionChoice(
              value: 'positional',
              label: 'Positional',
              description: 'Value based on position',
            ),
          ],
          defaultValue: 'fixedMultiplier',
          group: 'Coin Values',
          order: 16,
        ),

        BlockOptionFactory.count(
          id: 'minCoinValue',
          name: 'Min Coin Value',
          description: 'Minimum coin value (bet multiplier)',
          min: 1,
          max: 10,
          defaultValue: 1,
          group: 'Coin Values',
          order: 17,
        ),

        BlockOptionFactory.count(
          id: 'maxCoinValue',
          name: 'Max Coin Value',
          description: 'Maximum coin value (bet multiplier)',
          min: 5,
          max: 100,
          defaultValue: 10,
          group: 'Coin Values',
          order: 18,
        ),

        BlockOptionFactory.toggle(
          id: 'coinsShowValues',
          name: 'Show Coin Values',
          description: 'Display values on coin symbols',
          defaultValue: true,
          group: 'Coin Values',
          order: 19,
        ),

        // ========== Special Features ==========
        BlockOptionFactory.toggle(
          id: 'hasMultiplierCoins',
          name: 'Multiplier Coins',
          description: 'Some coins multiply total win',
          defaultValue: false,
          group: 'Special Features',
          order: 20,
        ),

        BlockOptionFactory.toggle(
          id: 'hasCollectorCoins',
          name: 'Collector Coins',
          description: 'Coins that collect other coin values',
          defaultValue: false,
          group: 'Special Features',
          order: 21,
        ),

        BlockOptionFactory.toggle(
          id: 'hasUpgradeCoins',
          name: 'Upgrade Coins',
          description: 'Coins that upgrade other coins',
          defaultValue: false,
          group: 'Special Features',
          order: 22,
        ),

        BlockOptionFactory.toggle(
          id: 'hasWildCoins',
          name: 'Wild Coins',
          description: 'Wild coins with random values',
          defaultValue: false,
          group: 'Special Features',
          order: 23,
        ),

        BlockOptionFactory.toggle(
          id: 'hasPersistentCoins',
          name: 'Persistent Coins',
          description: 'Coins persist between spins',
          defaultValue: false,
          group: 'Special Features',
          order: 24,
        ),

        BlockOptionFactory.toggle(
          id: 'hasLinkedReels',
          name: 'Linked Reels',
          description: 'Reels can link during feature',
          defaultValue: false,
          group: 'Special Features',
          order: 25,
        ),

        // ========== Audio Settings ==========
        BlockOptionFactory.toggle(
          id: 'hasDedicatedMusic',
          name: 'Dedicated Music',
          description: 'Special music track during Hold & Win',
          defaultValue: true,
          group: 'Audio',
          order: 26,
        ),

        BlockOptionFactory.toggle(
          id: 'hasCoinLandSound',
          name: 'Coin Land Sound',
          description: 'Sound when coin lands',
          defaultValue: true,
          group: 'Audio',
          order: 27,
        ),

        BlockOptionFactory.toggle(
          id: 'hasRespinCountdown',
          name: 'Respin Countdown Audio',
          description: 'Audio cue for remaining respins',
          defaultValue: true,
          group: 'Audio',
          order: 28,
        ),

        BlockOptionFactory.toggle(
          id: 'hasJackpotFanfare',
          name: 'Jackpot Fanfare',
          description: 'Special audio for jackpot wins',
          defaultValue: true,
          group: 'Audio',
          order: 29,
        ),
      ];

  @override
  List<BlockDependency> createDependencies() => [
        // Requires Game Core
        BlockDependency.requires(
          source: id,
          target: 'game_core',
          description: 'Hold & Win requires Game Core configuration',
          autoResolvable: true,
        ),

        // Requires Grid
        BlockDependency.requires(
          source: id,
          target: 'grid',
          description: 'Hold & Win requires Grid configuration',
          autoResolvable: true,
        ),

        // Requires Symbol Set (for coin symbols)
        BlockDependency.requires(
          source: id,
          target: 'symbol_set',
          description: 'Hold & Win requires Symbol Set for coin symbols',
          autoResolvable: true,
        ),

        // Modifies Win Presentation
        BlockDependency.modifies(
          source: id,
          target: 'win_presentation',
          description: 'Hold & Win has unique win presentation',
        ),

        // Modifies Music States
        BlockDependency.modifies(
          source: id,
          target: 'music_states',
          description: 'Hold & Win has dedicated music context',
        ),

        // Potential conflict with Respins (similar mechanics)
        BlockDependency.conflicts(
          source: id,
          target: 'respin',
          description: 'Hold & Win conflicts with Respins (overlapping mechanics)',
        ),
      ];

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];
    final hasMusic = getOptionValue<bool>('hasDedicatedMusic') ?? true;
    final hasCoinSound = getOptionValue<bool>('hasCoinLandSound') ?? true;
    final hasCountdown = getOptionValue<bool>('hasRespinCountdown') ?? true;
    final hasJackpots = getOptionValue<bool>('hasJackpots') ?? true;
    final hasJackpotFanfare = getOptionValue<bool>('hasJackpotFanfare') ?? true;
    final jackpotTiers = getOptionValue<int>('jackpotTierCount') ?? 4;
    final hasMultiplierCoins = getOptionValue<bool>('hasMultiplierCoins') ?? false;
    final hasCollectorCoins = getOptionValue<bool>('hasCollectorCoins') ?? false;
    final hasUpgradeCoins = getOptionValue<bool>('hasUpgradeCoins') ?? false;
    final gridFullBonusJackpot = getOptionValue<bool>('gridFullBonusJackpot') ?? true;

    // ========== Trigger Stages ==========
    stages.add(GeneratedStage(
      name: 'HOLD_TRIGGER',
      description: 'Hold & Win feature triggered',
      bus: 'sfx',
      priority: 90,
      sourceBlockId: id,
      category: 'Hold & Win',
    ));

    stages.add(GeneratedStage(
      name: 'HOLD_INTRO',
      description: 'Hold & Win intro sequence',
      bus: 'sfx',
      priority: 88,
      sourceBlockId: id,
      category: 'Hold & Win',
    ));

    stages.add(GeneratedStage(
      name: 'HOLD_ENTER',
      description: 'Enter Hold & Win mode',
      bus: 'sfx',
      priority: 85,
      sourceBlockId: id,
      category: 'Hold & Win',
    ));

    // ========== Music Stages ==========
    if (hasMusic) {
      stages.add(GeneratedStage(
        name: 'HOLD_MUSIC',
        description: 'Hold & Win background music',
        bus: 'music',
        priority: 20,
        looping: true,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));

      stages.add(GeneratedStage(
        name: 'HOLD_MUSIC_TENSION',
        description: 'Tension music (low respins)',
        bus: 'music',
        priority: 25,
        looping: true,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));
    }

    // ========== Coin Stages ==========
    if (hasCoinSound) {
      stages.add(GeneratedStage(
        name: 'HOLD_COIN_LAND',
        description: 'Coin symbol lands',
        bus: 'sfx',
        priority: 75,
        pooled: true, // Multiple coins can land
        sourceBlockId: id,
        category: 'Hold & Win',
      ));

      stages.add(GeneratedStage(
        name: 'HOLD_COIN_REVEAL',
        description: 'Coin value revealed',
        bus: 'sfx',
        priority: 72,
        pooled: true,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));

      stages.add(GeneratedStage(
        name: 'HOLD_COIN_LOCK',
        description: 'Coin locks in position',
        bus: 'sfx',
        priority: 70,
        pooled: true,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));
    }

    // ========== Special Coin Stages ==========
    if (hasMultiplierCoins) {
      stages.add(GeneratedStage(
        name: 'HOLD_MULTIPLIER_COIN',
        description: 'Multiplier coin lands',
        bus: 'sfx',
        priority: 78,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));

      stages.add(GeneratedStage(
        name: 'HOLD_MULTIPLIER_APPLY',
        description: 'Multiplier applies to total',
        bus: 'sfx',
        priority: 80,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));
    }

    if (hasCollectorCoins) {
      stages.add(GeneratedStage(
        name: 'HOLD_COLLECTOR_COIN',
        description: 'Collector coin lands',
        bus: 'sfx',
        priority: 78,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));

      stages.add(GeneratedStage(
        name: 'HOLD_COLLECT_VALUES',
        description: 'Collector collects other coins',
        bus: 'sfx',
        priority: 82,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));
    }

    if (hasUpgradeCoins) {
      stages.add(GeneratedStage(
        name: 'HOLD_UPGRADE_COIN',
        description: 'Upgrade coin lands',
        bus: 'sfx',
        priority: 78,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));

      stages.add(GeneratedStage(
        name: 'HOLD_COIN_UPGRADE',
        description: 'Coin value upgrades',
        bus: 'sfx',
        priority: 76,
        pooled: true,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));
    }

    // ========== Respin Stages ==========
    stages.add(GeneratedStage(
      name: 'HOLD_RESPIN_START',
      description: 'Hold & Win respin begins',
      bus: 'sfx',
      priority: 70,
      sourceBlockId: id,
      category: 'Hold & Win',
    ));

    stages.add(GeneratedStage(
      name: 'HOLD_RESPIN_END',
      description: 'Hold & Win respin ends',
      bus: 'sfx',
      priority: 65,
      sourceBlockId: id,
      category: 'Hold & Win',
    ));

    if (hasCountdown) {
      stages.add(GeneratedStage(
        name: 'HOLD_RESPIN_COUNTER',
        description: 'Respin counter update',
        bus: 'ui',
        priority: 50,
        pooled: true,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));

      stages.add(GeneratedStage(
        name: 'HOLD_RESPIN_RESET',
        description: 'Respin counter resets',
        bus: 'sfx',
        priority: 68,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));

      stages.add(GeneratedStage(
        name: 'HOLD_LAST_RESPIN',
        description: 'Last respin warning',
        bus: 'sfx',
        priority: 72,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));
    }

    // ========== Jackpot Stages ==========
    if (hasJackpots && hasJackpotFanfare) {
      // Per-tier jackpot stages
      final tierNames = ['MINI', 'MINOR', 'MAJOR', 'GRAND', 'MEGA'];
      for (var i = 0; i < jackpotTiers && i < tierNames.length; i++) {
        stages.add(GeneratedStage(
          name: 'HOLD_JACKPOT_${tierNames[i]}',
          description: '${tierNames[i].toLowerCase().capitalize()} jackpot won',
          bus: 'sfx',
          priority: 90 + i, // Higher tiers higher priority
          sourceBlockId: id,
          category: 'Hold & Win',
        ));
      }

      stages.add(GeneratedStage(
        name: 'HOLD_JACKPOT_TRIGGER',
        description: 'Jackpot symbol triggered',
        bus: 'sfx',
        priority: 88,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));
    }

    // ========== Grid Full Stage ==========
    if (gridFullBonusJackpot) {
      stages.add(GeneratedStage(
        name: 'HOLD_GRID_FULL',
        description: 'Grid completely filled with coins',
        bus: 'sfx',
        priority: 95,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));

      stages.add(GeneratedStage(
        name: 'HOLD_GRAND_PRIZE',
        description: 'Grand prize awarded for full grid',
        bus: 'sfx',
        priority: 96,
        sourceBlockId: id,
        category: 'Hold & Win',
      ));
    }

    // ========== Collection Stages ==========
    stages.add(GeneratedStage(
      name: 'HOLD_COLLECT_START',
      description: 'Start collecting coin values',
      bus: 'sfx',
      priority: 82,
      sourceBlockId: id,
      category: 'Hold & Win',
    ));

    stages.add(GeneratedStage(
      name: 'HOLD_COLLECT_COIN',
      description: 'Individual coin collected',
      bus: 'sfx',
      priority: 75,
      pooled: true,
      sourceBlockId: id,
      category: 'Hold & Win',
    ));

    stages.add(GeneratedStage(
      name: 'HOLD_COLLECT_END',
      description: 'Collection complete',
      bus: 'sfx',
      priority: 84,
      sourceBlockId: id,
      category: 'Hold & Win',
    ));

    // ========== Exit Stages ==========
    stages.add(GeneratedStage(
      name: 'HOLD_OUTRO',
      description: 'Hold & Win outro sequence',
      bus: 'sfx',
      priority: 80,
      sourceBlockId: id,
      category: 'Hold & Win',
    ));

    stages.add(GeneratedStage(
      name: 'HOLD_EXIT',
      description: 'Exit Hold & Win mode',
      bus: 'sfx',
      priority: 78,
      sourceBlockId: id,
      category: 'Hold & Win',
    ));

    stages.add(GeneratedStage(
      name: 'HOLD_TOTAL_WIN',
      description: 'Total Hold & Win win presentation',
      bus: 'sfx',
      priority: 85,
      sourceBlockId: id,
      category: 'Hold & Win',
    ));

    return stages;
  }

  @override
  List<String> get pooledStages => [
        'HOLD_COIN_LAND',
        'HOLD_COIN_REVEAL',
        'HOLD_COIN_LOCK',
        'HOLD_RESPIN_COUNTER',
        'HOLD_COIN_UPGRADE',
        'HOLD_COLLECT_COIN',
      ];

  @override
  String getBusForStage(String stageName) {
    if (stageName.contains('MUSIC')) return 'music';
    if (stageName.contains('COUNTER')) return 'ui';
    return 'sfx';
  }

  @override
  int getPriorityForStage(String stageName) {
    if (stageName.contains('JACKPOT')) return 90;
    if (stageName == 'HOLD_GRID_FULL') return 95;
    if (stageName == 'HOLD_GRAND_PRIZE') return 96;
    if (stageName == 'HOLD_TRIGGER') return 90;
    if (stageName.contains('COLLECT')) return 80;
    if (stageName.contains('COIN')) return 75;
    if (stageName.contains('MUSIC')) return 20;
    return 70;
  }

  // ============================================================================
  // Convenience Getters
  // ============================================================================

  /// Get Hold & Win mode.
  HoldAndWinMode get mode {
    final value = getOptionValue<String>('mode') ?? 'classic';
    return HoldAndWinMode.values.firstWhere(
      (m) => m.name == value,
      orElse: () => HoldAndWinMode.classic,
    );
  }

  /// Get coin value type.
  CoinValueType get coinValueType {
    final value = getOptionValue<String>('coinValueType') ?? 'fixedMultiplier';
    return CoinValueType.values.firstWhere(
      (c) => c.name == value,
      orElse: () => CoinValueType.fixedMultiplier,
    );
  }

  /// Get minimum coins to trigger.
  int get minCoinsToTrigger => getOptionValue<int>('minCoinsToTrigger') ?? 6;

  /// Get initial respins.
  int get initialRespins => getOptionValue<int>('initialRespins') ?? 3;

  /// Whether respins reset on new coin.
  bool get respinsReset => getOptionValue<bool>('respinsReset') ?? true;

  /// Get jackpot tier count.
  int get jackpotTierCount => getOptionValue<int>('jackpotTierCount') ?? 4;

  /// Get jackpot value for tier.
  int getJackpotValue(JackpotTier tier) {
    switch (tier) {
      case JackpotTier.mini:
        return getOptionValue<int>('miniJackpotValue') ?? 20;
      case JackpotTier.minor:
        return getOptionValue<int>('minorJackpotValue') ?? 50;
      case JackpotTier.major:
        return getOptionValue<int>('majorJackpotValue') ?? 250;
      case JackpotTier.grand:
        return getOptionValue<int>('grandJackpotValue') ?? 1000;
      case JackpotTier.mega:
        return getOptionValue<int>('grandJackpotValue')! * 5; // 5x Grand
    }
  }

  /// Whether progressive jackpots are enabled.
  bool get hasProgressiveJackpots =>
      getOptionValue<bool>('progressiveJackpots') ?? true;

  /// Whether filling grid awards grand jackpot.
  bool get gridFullAwardsGrand =>
      getOptionValue<bool>('gridFullBonusJackpot') ?? true;
}

// Helper extension for String capitalization
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}
