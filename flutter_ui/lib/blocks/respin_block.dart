// ============================================================================
// FluxForge Studio — Respin Block
// ============================================================================
// P13.1.2: Feature block for Respin configuration
// Defines respin triggers, locked symbols, and progression mechanics.
// ============================================================================

import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';
import '../models/feature_builder/feature_block.dart';

/// Respin trigger conditions.
enum RespinTrigger {
  /// Specific symbols trigger respins.
  symbolBased,

  /// Near-miss situations trigger respins.
  nearMiss,

  /// After certain win conditions.
  winBased,

  /// Random chance on any spin.
  random,

  /// Cascades trigger respins.
  cascadeBased,
}

/// What happens to symbols during respin.
enum SymbolBehavior {
  /// All symbols respin.
  allRespin,

  /// Winning symbols lock in place.
  lockWinning,

  /// Specific symbol types lock.
  lockSpecific,

  /// Nudge symbols to create wins.
  nudge,
}

/// Respin progression type.
enum RespinProgression {
  /// Fixed number of respins.
  fixed,

  /// Respins continue while symbols land.
  untilNoNew,

  /// Respins until grid is full.
  untilFull,

  /// Limited by counter.
  countdown,
}

/// Feature block for Respin configuration.
///
/// This block defines:
/// - Respin trigger conditions
/// - Symbol locking/nudging behavior
/// - Respin count and progression
/// - Special respin features
/// - Audio stages for respin phases
class RespinBlock extends FeatureBlockBase {
  RespinBlock() : super(enabled: false);

  @override
  String get id => 'respin';

  @override
  String get name => 'Respins';

  @override
  String get description =>
      'Respin mechanics with symbol locking and progression';

  @override
  BlockCategory get category => BlockCategory.feature;

  @override
  String get iconName => 'replay';

  @override
  bool get canBeDisabled => true;

  @override
  int get stagePriority => 15;

  @override
  List<BlockOption> createOptions() => [
        // ========== Trigger Settings ==========
        BlockOptionFactory.dropdown(
          id: 'triggerCondition',
          name: 'Trigger Condition',
          description: 'What triggers a respin',
          choices: [
            const OptionChoice(
              value: 'symbolBased',
              label: 'Symbol Based',
              description: 'Specific symbols trigger respins',
            ),
            const OptionChoice(
              value: 'nearMiss',
              label: 'Near Miss',
              description: 'Almost-winning situations trigger',
            ),
            const OptionChoice(
              value: 'winBased',
              label: 'Win Based',
              description: 'Certain wins trigger respins',
            ),
            const OptionChoice(
              value: 'random',
              label: 'Random',
              description: 'Random chance on any spin',
            ),
            const OptionChoice(
              value: 'cascadeBased',
              label: 'Cascade Based',
              description: 'After cascades complete',
            ),
          ],
          defaultValue: 'symbolBased',
          group: 'Trigger',
          order: 1,
        ),

        BlockOptionFactory.count(
          id: 'minSymbolsToTrigger',
          name: 'Min Symbols to Trigger',
          description: 'Minimum triggering symbols needed',
          min: 1,
          max: 6,
          defaultValue: 3,
          group: 'Trigger',
          order: 2,
        ),

        BlockOptionFactory.percentage(
          id: 'randomTriggerChance',
          name: 'Random Trigger Chance',
          description: 'Chance of random respin trigger',
          defaultValue: 5,
          group: 'Trigger',
          order: 3,
        ),

        BlockOptionFactory.toggle(
          id: 'triggerOnlyOnLoss',
          name: 'Trigger Only on Loss',
          description: 'Only trigger respins on non-winning spins',
          defaultValue: false,
          group: 'Trigger',
          order: 4,
        ),

        // ========== Symbol Behavior ==========
        BlockOptionFactory.dropdown(
          id: 'symbolBehavior',
          name: 'Symbol Behavior',
          description: 'How symbols behave during respins',
          choices: [
            const OptionChoice(
              value: 'allRespin',
              label: 'All Respin',
              description: 'All symbols respin',
            ),
            const OptionChoice(
              value: 'lockWinning',
              label: 'Lock Winning',
              description: 'Winning symbols stay in place',
            ),
            const OptionChoice(
              value: 'lockSpecific',
              label: 'Lock Specific',
              description: 'Specific symbol types lock',
            ),
            const OptionChoice(
              value: 'nudge',
              label: 'Nudge',
              description: 'Symbols nudge to create wins',
            ),
          ],
          defaultValue: 'lockWinning',
          group: 'Symbol Behavior',
          order: 5,
        ),

        BlockOptionFactory.toggle(
          id: 'lockTriggering',
          name: 'Lock Triggering Symbols',
          description: 'Lock the symbols that triggered respin',
          defaultValue: true,
          group: 'Symbol Behavior',
          order: 6,
        ),

        BlockOptionFactory.toggle(
          id: 'lockWilds',
          name: 'Lock Wilds',
          description: 'Wild symbols lock during respins',
          defaultValue: true,
          group: 'Symbol Behavior',
          order: 7,
        ),

        BlockOptionFactory.toggle(
          id: 'lockScatters',
          name: 'Lock Scatters',
          description: 'Scatter symbols lock during respins',
          defaultValue: false,
          group: 'Symbol Behavior',
          order: 8,
        ),

        BlockOptionFactory.toggle(
          id: 'hasNudge',
          name: 'Has Nudge Feature',
          description: 'Symbols can nudge to create wins',
          defaultValue: false,
          group: 'Symbol Behavior',
          order: 9,
        ),

        BlockOptionFactory.count(
          id: 'maxNudgePositions',
          name: 'Max Nudge Positions',
          description: 'Maximum positions a symbol can nudge',
          min: 1,
          max: 3,
          defaultValue: 1,
          group: 'Symbol Behavior',
          order: 10,
        ),

        // ========== Respin Count ==========
        BlockOptionFactory.dropdown(
          id: 'progressionType',
          name: 'Progression Type',
          description: 'How respin count is determined',
          choices: [
            const OptionChoice(
              value: 'fixed',
              label: 'Fixed Count',
              description: 'Fixed number of respins',
            ),
            const OptionChoice(
              value: 'untilNoNew',
              label: 'Until No New',
              description: 'Continue while new symbols land',
            ),
            const OptionChoice(
              value: 'untilFull',
              label: 'Until Full',
              description: 'Continue until grid is full',
            ),
            const OptionChoice(
              value: 'countdown',
              label: 'Countdown',
              description: 'Counter decreases each respin',
            ),
          ],
          defaultValue: 'fixed',
          group: 'Progression',
          order: 11,
        ),

        BlockOptionFactory.count(
          id: 'fixedRespinCount',
          name: 'Fixed Respin Count',
          description: 'Number of respins for fixed mode',
          min: 1,
          max: 10,
          defaultValue: 1,
          group: 'Progression',
          order: 12,
        ),

        BlockOptionFactory.count(
          id: 'maxRespins',
          name: 'Max Respins',
          description: 'Maximum respins allowed (0 = unlimited)',
          min: 0,
          max: 50,
          defaultValue: 10,
          group: 'Progression',
          order: 13,
        ),

        BlockOptionFactory.count(
          id: 'startingCounter',
          name: 'Starting Counter',
          description: 'Initial countdown value for countdown mode',
          min: 1,
          max: 10,
          defaultValue: 3,
          group: 'Progression',
          order: 14,
        ),

        BlockOptionFactory.toggle(
          id: 'counterResets',
          name: 'Counter Resets on Land',
          description: 'Counter resets when new symbols land',
          defaultValue: true,
          group: 'Progression',
          order: 15,
        ),

        // ========== Special Features ==========
        BlockOptionFactory.toggle(
          id: 'hasMultiplier',
          name: 'Has Multiplier',
          description: 'Multiplier applies during respins',
          defaultValue: false,
          group: 'Special Features',
          order: 16,
        ),

        BlockOptionFactory.count(
          id: 'respinMultiplier',
          name: 'Respin Multiplier',
          description: 'Win multiplier during respins',
          min: 1,
          max: 10,
          defaultValue: 2,
          group: 'Special Features',
          order: 17,
        ),

        BlockOptionFactory.toggle(
          id: 'progressiveMultiplier',
          name: 'Progressive Multiplier',
          description: 'Multiplier increases with each respin',
          defaultValue: false,
          group: 'Special Features',
          order: 18,
        ),

        BlockOptionFactory.toggle(
          id: 'hasSymbolUpgrade',
          name: 'Symbol Upgrade',
          description: 'Locked symbols can upgrade',
          defaultValue: false,
          group: 'Special Features',
          order: 19,
        ),

        BlockOptionFactory.toggle(
          id: 'hasWildTransform',
          name: 'Wild Transform',
          description: 'Symbols can transform to wilds',
          defaultValue: false,
          group: 'Special Features',
          order: 20,
        ),

        BlockOptionFactory.toggle(
          id: 'freeRespin',
          name: 'Free Respins',
          description: 'Respins don\'t cost additional bet',
          defaultValue: true,
          group: 'Special Features',
          order: 21,
        ),

        // ========== Audio Settings ==========
        BlockOptionFactory.toggle(
          id: 'hasRespinMusic',
          name: 'Respin Music',
          description: 'Dedicated music during respins',
          defaultValue: false,
          group: 'Audio',
          order: 22,
        ),

        BlockOptionFactory.toggle(
          id: 'hasLockSound',
          name: 'Lock Sound',
          description: 'Sound when symbols lock',
          defaultValue: true,
          group: 'Audio',
          order: 23,
        ),

        BlockOptionFactory.toggle(
          id: 'hasCounterSound',
          name: 'Counter Sound',
          description: 'Sound for countdown counter',
          defaultValue: true,
          group: 'Audio',
          order: 24,
        ),
      ];

  @override
  List<BlockDependency> createDependencies() => [
        // Requires Game Core
        BlockDependency.requires(
          source: id,
          target: 'game_core',
          description: 'Respins requires Game Core configuration',
          autoResolvable: true,
        ),

        // Requires Grid (for symbol positions)
        BlockDependency.requires(
          source: id,
          target: 'grid',
          description: 'Respins requires Grid configuration',
          autoResolvable: true,
        ),

        // Modifies Symbol Set
        BlockDependency.modifies(
          source: id,
          target: 'symbol_set',
          description: 'Respins modifies symbol behavior',
        ),

        // Potential conflict with Hold & Win (similar mechanics)
        BlockDependency.conflicts(
          source: id,
          target: 'hold_and_win',
          description: 'Respins conflicts with Hold & Win (similar mechanics)',
        ),
      ];

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];
    final hasMusic = getOptionValue<bool>('hasRespinMusic') ?? false;
    final hasLockSound = getOptionValue<bool>('hasLockSound') ?? true;
    final hasCounterSound = getOptionValue<bool>('hasCounterSound') ?? true;
    final hasMultiplier = getOptionValue<bool>('hasMultiplier') ?? false;
    final hasNudge = getOptionValue<bool>('hasNudge') ?? false;
    final hasWildTransform = getOptionValue<bool>('hasWildTransform') ?? false;
    final hasSymbolUpgrade = getOptionValue<bool>('hasSymbolUpgrade') ?? false;
    final progressionType = getOptionValue<String>('progressionType') ?? 'fixed';

    // ========== Trigger Stages ==========
    stages.add(GeneratedStage(
      name: 'RESPIN_TRIGGER',
      description: 'Respin feature triggered',
      bus: 'sfx',
      priority: 80,
      sourceBlockId: id,
      category: 'Respins',
    ));

    stages.add(GeneratedStage(
      name: 'RESPIN_ENTER',
      description: 'Enter respin mode',
      bus: 'sfx',
      priority: 78,
      sourceBlockId: id,
      category: 'Respins',
    ));

    // ========== Music Stages ==========
    if (hasMusic) {
      stages.add(GeneratedStage(
        name: 'RESPIN_MUSIC',
        description: 'Respin background music',
        bus: 'music',
        priority: 20,
        looping: true,
        sourceBlockId: id,
        category: 'Respins',
      ));
    }

    // ========== Symbol Lock Stages ==========
    if (hasLockSound) {
      stages.add(GeneratedStage(
        name: 'RESPIN_SYMBOL_LOCK',
        description: 'Symbol locks in place',
        bus: 'sfx',
        priority: 70,
        pooled: true, // Multiple symbols can lock
        sourceBlockId: id,
        category: 'Respins',
      ));

      stages.add(GeneratedStage(
        name: 'RESPIN_SYMBOL_UNLOCK',
        description: 'Symbol unlocks',
        bus: 'sfx',
        priority: 65,
        pooled: true,
        sourceBlockId: id,
        category: 'Respins',
      ));
    }

    // ========== Spin Stages ==========
    stages.add(GeneratedStage(
      name: 'RESPIN_START',
      description: 'Respin begins',
      bus: 'sfx',
      priority: 72,
      sourceBlockId: id,
      category: 'Respins',
    ));

    stages.add(GeneratedStage(
      name: 'RESPIN_END',
      description: 'Respin ends',
      bus: 'sfx',
      priority: 68,
      sourceBlockId: id,
      category: 'Respins',
    ));

    // ========== Counter Stages ==========
    if (progressionType == 'countdown' && hasCounterSound) {
      stages.add(GeneratedStage(
        name: 'RESPIN_COUNTER_TICK',
        description: 'Countdown counter decreases',
        bus: 'ui',
        priority: 50,
        pooled: true,
        sourceBlockId: id,
        category: 'Respins',
      ));

      stages.add(GeneratedStage(
        name: 'RESPIN_COUNTER_RESET',
        description: 'Counter resets to initial value',
        bus: 'sfx',
        priority: 60,
        sourceBlockId: id,
        category: 'Respins',
      ));
    }

    // ========== Nudge Stages ==========
    if (hasNudge) {
      stages.add(GeneratedStage(
        name: 'RESPIN_NUDGE',
        description: 'Symbol nudges to new position',
        bus: 'sfx',
        priority: 65,
        pooled: true,
        sourceBlockId: id,
        category: 'Respins',
      ));

      stages.add(GeneratedStage(
        name: 'RESPIN_NUDGE_WIN',
        description: 'Nudge creates a win',
        bus: 'sfx',
        priority: 72,
        sourceBlockId: id,
        category: 'Respins',
      ));
    }

    // ========== Multiplier Stages ==========
    if (hasMultiplier) {
      stages.add(GeneratedStage(
        name: 'RESPIN_MULTIPLIER_ACTIVE',
        description: 'Multiplier is active',
        bus: 'sfx',
        priority: 70,
        sourceBlockId: id,
        category: 'Respins',
      ));

      stages.add(GeneratedStage(
        name: 'RESPIN_MULTIPLIER_INCREASE',
        description: 'Multiplier increases',
        bus: 'sfx',
        priority: 72,
        pooled: true,
        sourceBlockId: id,
        category: 'Respins',
      ));
    }

    // ========== Special Feature Stages ==========
    if (hasWildTransform) {
      stages.add(GeneratedStage(
        name: 'RESPIN_WILD_TRANSFORM',
        description: 'Symbol transforms to wild',
        bus: 'sfx',
        priority: 74,
        sourceBlockId: id,
        category: 'Respins',
      ));
    }

    if (hasSymbolUpgrade) {
      stages.add(GeneratedStage(
        name: 'RESPIN_SYMBOL_UPGRADE',
        description: 'Symbol upgrades to higher value',
        bus: 'sfx',
        priority: 73,
        pooled: true,
        sourceBlockId: id,
        category: 'Respins',
      ));
    }

    // ========== Result Stages ==========
    stages.add(GeneratedStage(
      name: 'RESPIN_NO_NEW',
      description: 'No new symbols landed',
      bus: 'sfx',
      priority: 55,
      sourceBlockId: id,
      category: 'Respins',
    ));

    stages.add(GeneratedStage(
      name: 'RESPIN_NEW_SYMBOL',
      description: 'New triggering symbol landed',
      bus: 'sfx',
      priority: 70,
      pooled: true,
      sourceBlockId: id,
      category: 'Respins',
    ));

    stages.add(GeneratedStage(
      name: 'RESPIN_GRID_FULL',
      description: 'Grid is completely filled',
      bus: 'sfx',
      priority: 85,
      sourceBlockId: id,
      category: 'Respins',
    ));

    // ========== Exit Stages ==========
    stages.add(GeneratedStage(
      name: 'RESPIN_EXIT',
      description: 'Exit respin mode',
      bus: 'sfx',
      priority: 75,
      sourceBlockId: id,
      category: 'Respins',
    ));

    stages.add(GeneratedStage(
      name: 'RESPIN_TOTAL_WIN',
      description: 'Total respin win presentation',
      bus: 'sfx',
      priority: 80,
      sourceBlockId: id,
      category: 'Respins',
    ));

    return stages;
  }

  @override
  List<String> get pooledStages => [
        'RESPIN_SYMBOL_LOCK',
        'RESPIN_SYMBOL_UNLOCK',
        'RESPIN_COUNTER_TICK',
        'RESPIN_NUDGE',
        'RESPIN_MULTIPLIER_INCREASE',
        'RESPIN_SYMBOL_UPGRADE',
        'RESPIN_NEW_SYMBOL',
      ];

  @override
  String getBusForStage(String stageName) {
    if (stageName == 'RESPIN_MUSIC') return 'music';
    if (stageName.contains('COUNTER_TICK')) return 'ui';
    return 'sfx';
  }

  @override
  int getPriorityForStage(String stageName) {
    if (stageName == 'RESPIN_TRIGGER') return 80;
    if (stageName == 'RESPIN_GRID_FULL') return 85;
    if (stageName == 'RESPIN_TOTAL_WIN') return 80;
    if (stageName.contains('LOCK')) return 70;
    if (stageName.contains('MULTIPLIER')) return 72;
    if (stageName == 'RESPIN_MUSIC') return 20;
    return 65;
  }

  // ============================================================================
  // Convenience Getters
  // ============================================================================

  /// Get the trigger condition.
  RespinTrigger get triggerCondition {
    final value = getOptionValue<String>('triggerCondition') ?? 'symbolBased';
    return RespinTrigger.values.firstWhere(
      (t) => t.name == value,
      orElse: () => RespinTrigger.symbolBased,
    );
  }

  /// Get symbol behavior during respins.
  SymbolBehavior get symbolBehavior {
    final value = getOptionValue<String>('symbolBehavior') ?? 'lockWinning';
    return SymbolBehavior.values.firstWhere(
      (b) => b.name == value,
      orElse: () => SymbolBehavior.lockWinning,
    );
  }

  /// Get progression type.
  RespinProgression get progressionType {
    final value = getOptionValue<String>('progressionType') ?? 'fixed';
    return RespinProgression.values.firstWhere(
      (p) => p.name == value,
      orElse: () => RespinProgression.fixed,
    );
  }

  /// Get fixed respin count.
  int get fixedRespinCount => getOptionValue<int>('fixedRespinCount') ?? 1;

  /// Get max respins.
  int get maxRespins => getOptionValue<int>('maxRespins') ?? 10;

  /// Whether respins are free.
  bool get isFreeRespin => getOptionValue<bool>('freeRespin') ?? true;

  /// Whether symbols lock on trigger.
  bool get locksTriggeringSymbols =>
      getOptionValue<bool>('lockTriggering') ?? true;

  /// Whether wilds lock.
  bool get locksWilds => getOptionValue<bool>('lockWilds') ?? true;

  /// Get respin multiplier.
  int get respinMultiplier => getOptionValue<int>('respinMultiplier') ?? 2;
}
