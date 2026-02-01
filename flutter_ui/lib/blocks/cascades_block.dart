// ============================================================================
// FluxForge Studio — Cascades Block
// ============================================================================
// P13.1.4: Feature block for Cascading/Tumbling reels configuration
// Defines cascade mechanics, multipliers, and symbol removal behavior.
// ============================================================================

import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';
import '../models/feature_builder/feature_block.dart';

/// Cascade trigger condition.
enum CascadeTrigger {
  /// Any winning combination triggers cascade.
  anyWin,

  /// Only specific symbols trigger cascade.
  specificSymbols,

  /// Scatter symbols trigger cascade.
  scatterBased,

  /// Wild symbols trigger cascade.
  wildBased,
}

/// Symbol removal animation style.
enum RemovalStyle {
  /// Symbols explode/burst.
  explode,

  /// Symbols dissolve/fade.
  dissolve,

  /// Symbols fall off screen.
  fallOff,

  /// Symbols collected (fly to meter).
  collect,

  /// Symbols shatter.
  shatter,
}

/// How new symbols enter.
enum FillStyle {
  /// Symbols drop from above.
  dropFromTop,

  /// Symbols slide from side.
  slideIn,

  /// Symbols fade in place.
  fadeIn,

  /// Symbols pop into place.
  popIn,
}

/// Multiplier progression type.
enum CascadeMultiplierType {
  /// No multiplier.
  none,

  /// Multiplier increases each cascade.
  progressive,

  /// Fixed multiplier for all cascades.
  fixed,

  /// Random multiplier each cascade.
  random,

  /// Multiplier resets after feature ends.
  resetting,
}

/// Feature block for Cascading Reels configuration.
///
/// This block defines:
/// - Cascade trigger and termination conditions
/// - Symbol removal and refill behavior
/// - Multiplier progression
/// - Cascade limits and bonuses
/// - Audio stages for all cascade phases
class CascadesBlock extends FeatureBlockBase {
  CascadesBlock() : super(enabled: false);

  @override
  String get id => 'cascades';

  @override
  String get name => 'Cascading Reels';

  @override
  String get description =>
      'Tumbling reels with multipliers and chain reactions';

  @override
  BlockCategory get category => BlockCategory.feature;

  @override
  String get iconName => 'animation';

  @override
  bool get canBeDisabled => true;

  @override
  int get stagePriority => 8;

  @override
  List<BlockOption> createOptions() => [
        // ========== Trigger Settings ==========
        BlockOptionFactory.dropdown(
          id: 'triggerCondition',
          name: 'Trigger Condition',
          description: 'What triggers a cascade',
          choices: [
            const OptionChoice(
              value: 'anyWin',
              label: 'Any Win',
              description: 'Any winning combination',
            ),
            const OptionChoice(
              value: 'specificSymbols',
              label: 'Specific Symbols',
              description: 'Only certain symbols',
            ),
            const OptionChoice(
              value: 'scatterBased',
              label: 'Scatter Based',
              description: 'Scatter symbols trigger',
            ),
            const OptionChoice(
              value: 'wildBased',
              label: 'Wild Based',
              description: 'Wild symbols trigger',
            ),
          ],
          defaultValue: 'anyWin',
          group: 'Trigger',
          order: 1,
        ),

        BlockOptionFactory.toggle(
          id: 'cascadeOnBaseGame',
          name: 'Cascade in Base Game',
          description: 'Enable cascades in base game',
          defaultValue: true,
          group: 'Trigger',
          order: 2,
        ),

        BlockOptionFactory.toggle(
          id: 'cascadeInFreeSpins',
          name: 'Cascade in Free Spins',
          description: 'Enable cascades during free spins',
          defaultValue: true,
          group: 'Trigger',
          order: 3,
        ),

        // ========== Removal Settings ==========
        BlockOptionFactory.dropdown(
          id: 'removalStyle',
          name: 'Removal Style',
          description: 'How winning symbols are removed',
          choices: [
            const OptionChoice(
              value: 'explode',
              label: 'Explode',
              description: 'Symbols burst/explode',
            ),
            const OptionChoice(
              value: 'dissolve',
              label: 'Dissolve',
              description: 'Symbols fade away',
            ),
            const OptionChoice(
              value: 'fallOff',
              label: 'Fall Off',
              description: 'Symbols fall off screen',
            ),
            const OptionChoice(
              value: 'collect',
              label: 'Collect',
              description: 'Symbols fly to meter',
            ),
            const OptionChoice(
              value: 'shatter',
              label: 'Shatter',
              description: 'Symbols break apart',
            ),
          ],
          defaultValue: 'explode',
          group: 'Animation',
          order: 4,
        ),

        BlockOptionFactory.dropdown(
          id: 'fillStyle',
          name: 'Fill Style',
          description: 'How new symbols enter',
          choices: [
            const OptionChoice(
              value: 'dropFromTop',
              label: 'Drop from Top',
              description: 'Cascade from above',
            ),
            const OptionChoice(
              value: 'slideIn',
              label: 'Slide In',
              description: 'Slide from side',
            ),
            const OptionChoice(
              value: 'fadeIn',
              label: 'Fade In',
              description: 'Fade into place',
            ),
            const OptionChoice(
              value: 'popIn',
              label: 'Pop In',
              description: 'Pop into position',
            ),
          ],
          defaultValue: 'dropFromTop',
          group: 'Animation',
          order: 5,
        ),

        BlockOptionFactory.count(
          id: 'cascadeDelay',
          name: 'Cascade Delay (ms)',
          description: 'Delay between cascades',
          min: 100,
          max: 1000,
          defaultValue: 300,
          group: 'Animation',
          order: 6,
        ),

        BlockOptionFactory.toggle(
          id: 'simultaneousRemoval',
          name: 'Simultaneous Removal',
          description: 'Remove all winning symbols at once',
          defaultValue: true,
          group: 'Animation',
          order: 7,
        ),

        // ========== Cascade Limits ==========
        BlockOptionFactory.count(
          id: 'maxCascades',
          name: 'Max Cascades',
          description: 'Maximum cascades per spin (0 = unlimited)',
          min: 0,
          max: 20,
          defaultValue: 0,
          group: 'Limits',
          order: 8,
        ),

        BlockOptionFactory.toggle(
          id: 'cascadesUntilNoWin',
          name: 'Cascade Until No Win',
          description: 'Continue cascading until no more wins',
          defaultValue: true,
          group: 'Limits',
          order: 9,
        ),

        // ========== Multiplier Settings ==========
        BlockOptionFactory.dropdown(
          id: 'multiplierType',
          name: 'Multiplier Type',
          description: 'How cascade multiplier works',
          choices: [
            const OptionChoice(
              value: 'none',
              label: 'No Multiplier',
              description: 'No multiplier applied',
            ),
            const OptionChoice(
              value: 'progressive',
              label: 'Progressive',
              description: 'Increases each cascade',
            ),
            const OptionChoice(
              value: 'fixed',
              label: 'Fixed',
              description: 'Same multiplier always',
            ),
            const OptionChoice(
              value: 'random',
              label: 'Random',
              description: 'Random each cascade',
            ),
            const OptionChoice(
              value: 'resetting',
              label: 'Resetting',
              description: 'Resets after feature',
            ),
          ],
          defaultValue: 'progressive',
          group: 'Multiplier',
          order: 10,
        ),

        BlockOptionFactory.count(
          id: 'baseMultiplier',
          name: 'Base Multiplier',
          description: 'Starting multiplier value',
          min: 1,
          max: 5,
          defaultValue: 1,
          group: 'Multiplier',
          order: 11,
        ),

        BlockOptionFactory.count(
          id: 'multiplierIncrement',
          name: 'Multiplier Increment',
          description: 'Amount multiplier increases',
          min: 1,
          max: 5,
          defaultValue: 1,
          group: 'Multiplier',
          order: 12,
        ),

        BlockOptionFactory.count(
          id: 'maxMultiplier',
          name: 'Max Multiplier',
          description: 'Maximum multiplier value',
          min: 2,
          max: 100,
          defaultValue: 10,
          group: 'Multiplier',
          order: 13,
        ),

        BlockOptionFactory.toggle(
          id: 'multiplierCarriesOver',
          name: 'Multiplier Carries Over',
          description: 'Multiplier persists between spins',
          defaultValue: false,
          group: 'Multiplier',
          order: 14,
        ),

        BlockOptionFactory.toggle(
          id: 'freeSpinsMultiplier',
          name: 'Higher FS Multiplier',
          description: 'Higher multipliers during free spins',
          defaultValue: true,
          group: 'Multiplier',
          order: 15,
        ),

        BlockOptionFactory.count(
          id: 'freeSpinsMultiplierBonus',
          name: 'FS Multiplier Bonus',
          description: 'Extra multiplier in free spins',
          min: 0,
          max: 10,
          defaultValue: 1,
          group: 'Multiplier',
          order: 16,
        ),

        // ========== Special Features ==========
        BlockOptionFactory.toggle(
          id: 'hasChainReaction',
          name: 'Chain Reaction Bonus',
          description: 'Bonus for consecutive cascades',
          defaultValue: false,
          group: 'Special Features',
          order: 17,
        ),

        BlockOptionFactory.count(
          id: 'chainReactionThreshold',
          name: 'Chain Reaction Threshold',
          description: 'Cascades needed for bonus',
          min: 3,
          max: 10,
          defaultValue: 5,
          group: 'Special Features',
          order: 18,
        ),

        BlockOptionFactory.toggle(
          id: 'hasSymbolTransform',
          name: 'Symbol Transform',
          description: 'Symbols can transform after cascade',
          defaultValue: false,
          group: 'Special Features',
          order: 19,
        ),

        BlockOptionFactory.toggle(
          id: 'hasWildGeneration',
          name: 'Wild Generation',
          description: 'Generate wilds on cascades',
          defaultValue: false,
          group: 'Special Features',
          order: 20,
        ),

        BlockOptionFactory.count(
          id: 'cascadesForWild',
          name: 'Cascades for Wild',
          description: 'Consecutive cascades to generate wild',
          min: 2,
          max: 5,
          defaultValue: 3,
          group: 'Special Features',
          order: 21,
        ),

        BlockOptionFactory.toggle(
          id: 'hasMeterCollection',
          name: 'Collection Meter',
          description: 'Collect symbols into meter',
          defaultValue: false,
          group: 'Special Features',
          order: 22,
        ),

        // ========== Audio Settings ==========
        BlockOptionFactory.toggle(
          id: 'hasCascadeMusic',
          name: 'Cascade Music',
          description: 'Music intensifies during cascades',
          defaultValue: true,
          group: 'Audio',
          order: 23,
        ),

        BlockOptionFactory.toggle(
          id: 'perCascadePitch',
          name: 'Pitch Escalation',
          description: 'Audio pitch increases each cascade',
          defaultValue: true,
          group: 'Audio',
          order: 24,
        ),

        BlockOptionFactory.toggle(
          id: 'hasRemovalSound',
          name: 'Removal Sound',
          description: 'Sound when symbols are removed',
          defaultValue: true,
          group: 'Audio',
          order: 25,
        ),

        BlockOptionFactory.toggle(
          id: 'hasFillSound',
          name: 'Fill Sound',
          description: 'Sound when new symbols land',
          defaultValue: true,
          group: 'Audio',
          order: 26,
        ),
      ];

  @override
  List<BlockDependency> createDependencies() => [
        // Requires Game Core
        BlockDependency.requires(
          source: id,
          target: 'game_core',
          description: 'Cascades requires Game Core configuration',
          autoResolvable: true,
        ),

        // Requires Grid
        BlockDependency.requires(
          source: id,
          target: 'grid',
          description: 'Cascades requires Grid configuration',
          autoResolvable: true,
        ),

        // Requires Symbol Set
        BlockDependency.requires(
          source: id,
          target: 'symbol_set',
          description: 'Cascades requires Symbol Set configuration',
          autoResolvable: true,
        ),

        // Modifies Win Presentation
        BlockDependency.modifies(
          source: id,
          target: 'win_presentation',
          description: 'Cascades modifies win presentation flow',
        ),

        // Enables Free Spins multiplier linking
        BlockDependency.enables(
          source: id,
          target: 'free_spins',
          description: 'Cascades can link to Free Spins multipliers',
        ),
      ];

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];
    final hasMusic = getOptionValue<bool>('hasCascadeMusic') ?? true;
    final hasRemovalSound = getOptionValue<bool>('hasRemovalSound') ?? true;
    final hasFillSound = getOptionValue<bool>('hasFillSound') ?? true;
    final perCascadePitch = getOptionValue<bool>('perCascadePitch') ?? true;
    final multiplierType = getOptionValue<String>('multiplierType') ?? 'progressive';
    final hasChainReaction = getOptionValue<bool>('hasChainReaction') ?? false;
    final hasWildGeneration = getOptionValue<bool>('hasWildGeneration') ?? false;
    final hasMeter = getOptionValue<bool>('hasMeterCollection') ?? false;
    final removalStyle = getOptionValue<String>('removalStyle') ?? 'explode';

    // ========== Cascade Start ==========
    stages.add(GeneratedStage(
      name: 'CASCADE_START',
      description: 'Cascade sequence begins',
      bus: 'sfx',
      priority: 75,
      sourceBlockId: id,
      category: 'Cascades',
    ));

    // ========== Removal Stages ==========
    if (hasRemovalSound) {
      // Style-specific removal sound
      stages.add(GeneratedStage(
        name: 'CASCADE_SYMBOL_REMOVE',
        description: 'Winning symbols removed',
        bus: 'sfx',
        priority: 72,
        pooled: true, // Multiple symbols removed
        sourceBlockId: id,
        category: 'Cascades',
      ));

      // Per-removal-style stages for unique sounds
      final removalStage = 'CASCADE_${removalStyle.toUpperCase()}';
      stages.add(GeneratedStage(
        name: removalStage,
        description: '$removalStyle removal effect',
        bus: 'sfx',
        priority: 70,
        pooled: true,
        sourceBlockId: id,
        category: 'Cascades',
      ));
    }

    // ========== Fill Stages ==========
    if (hasFillSound) {
      stages.add(GeneratedStage(
        name: 'CASCADE_SYMBOLS_DROP',
        description: 'New symbols dropping in',
        bus: 'sfx',
        priority: 68,
        sourceBlockId: id,
        category: 'Cascades',
      ));

      stages.add(GeneratedStage(
        name: 'CASCADE_SYMBOLS_LAND',
        description: 'New symbols land in place',
        bus: 'sfx',
        priority: 65,
        pooled: true,
        sourceBlockId: id,
        category: 'Cascades',
      ));
    }

    // ========== Per-Cascade Stages ==========
    stages.add(GeneratedStage(
      name: 'CASCADE_STEP',
      description: 'Individual cascade step (for counting)',
      bus: 'sfx',
      priority: 70,
      pooled: true, // Many cascades possible
      sourceBlockId: id,
      category: 'Cascades',
    ));

    if (perCascadePitch) {
      // Pitch-escalated cascade stages
      for (var i = 1; i <= 5; i++) {
        stages.add(GeneratedStage(
          name: 'CASCADE_STEP_$i',
          description: 'Cascade step $i (escalating pitch)',
          bus: 'sfx',
          priority: 70 + i,
          pooled: true,
          sourceBlockId: id,
          category: 'Cascades',
        ));
      }

      stages.add(GeneratedStage(
        name: 'CASCADE_STEP_MAX',
        description: 'Cascade at maximum escalation',
        bus: 'sfx',
        priority: 78,
        pooled: true,
        sourceBlockId: id,
        category: 'Cascades',
      ));
    }

    // ========== Music Stages ==========
    if (hasMusic) {
      stages.add(GeneratedStage(
        name: 'CASCADE_MUSIC_LAYER_1',
        description: 'Cascade music layer 1 (base)',
        bus: 'music',
        priority: 30,
        looping: true,
        sourceBlockId: id,
        category: 'Cascades',
      ));

      stages.add(GeneratedStage(
        name: 'CASCADE_MUSIC_LAYER_2',
        description: 'Cascade music layer 2 (building)',
        bus: 'music',
        priority: 32,
        looping: true,
        sourceBlockId: id,
        category: 'Cascades',
      ));

      stages.add(GeneratedStage(
        name: 'CASCADE_MUSIC_LAYER_3',
        description: 'Cascade music layer 3 (intense)',
        bus: 'music',
        priority: 34,
        looping: true,
        sourceBlockId: id,
        category: 'Cascades',
      ));
    }

    // ========== Multiplier Stages ==========
    if (multiplierType != 'none') {
      stages.add(GeneratedStage(
        name: 'CASCADE_MULTIPLIER_INCREASE',
        description: 'Cascade multiplier increases',
        bus: 'sfx',
        priority: 73,
        pooled: true,
        sourceBlockId: id,
        category: 'Cascades',
      ));

      stages.add(GeneratedStage(
        name: 'CASCADE_MULTIPLIER_MAX',
        description: 'Cascade multiplier at maximum',
        bus: 'sfx',
        priority: 80,
        sourceBlockId: id,
        category: 'Cascades',
      ));
    }

    // ========== Chain Reaction Stages ==========
    if (hasChainReaction) {
      stages.add(GeneratedStage(
        name: 'CASCADE_CHAIN_BONUS',
        description: 'Chain reaction bonus triggered',
        bus: 'sfx',
        priority: 82,
        sourceBlockId: id,
        category: 'Cascades',
      ));
    }

    // ========== Wild Generation Stages ==========
    if (hasWildGeneration) {
      stages.add(GeneratedStage(
        name: 'CASCADE_WILD_SPAWN',
        description: 'Wild symbol generated from cascades',
        bus: 'sfx',
        priority: 77,
        sourceBlockId: id,
        category: 'Cascades',
      ));
    }

    // ========== Collection Meter Stages ==========
    if (hasMeter) {
      stages.add(GeneratedStage(
        name: 'CASCADE_METER_COLLECT',
        description: 'Symbol collected to meter',
        bus: 'sfx',
        priority: 65,
        pooled: true,
        sourceBlockId: id,
        category: 'Cascades',
      ));

      stages.add(GeneratedStage(
        name: 'CASCADE_METER_FULL',
        description: 'Collection meter is full',
        bus: 'sfx',
        priority: 85,
        sourceBlockId: id,
        category: 'Cascades',
      ));
    }

    // ========== End Stages ==========
    stages.add(GeneratedStage(
      name: 'CASCADE_NO_WIN',
      description: 'No more winning combinations',
      bus: 'sfx',
      priority: 55,
      sourceBlockId: id,
      category: 'Cascades',
    ));

    stages.add(GeneratedStage(
      name: 'CASCADE_END',
      description: 'Cascade sequence complete',
      bus: 'sfx',
      priority: 60,
      sourceBlockId: id,
      category: 'Cascades',
    ));

    stages.add(GeneratedStage(
      name: 'CASCADE_TOTAL_WIN',
      description: 'Total cascade win presentation',
      bus: 'sfx',
      priority: 78,
      sourceBlockId: id,
      category: 'Cascades',
    ));

    return stages;
  }

  @override
  List<String> get pooledStages => [
        'CASCADE_SYMBOL_REMOVE',
        'CASCADE_EXPLODE',
        'CASCADE_DISSOLVE',
        'CASCADE_FALLOFF',
        'CASCADE_COLLECT',
        'CASCADE_SHATTER',
        'CASCADE_SYMBOLS_LAND',
        'CASCADE_STEP',
        'CASCADE_STEP_1',
        'CASCADE_STEP_2',
        'CASCADE_STEP_3',
        'CASCADE_STEP_4',
        'CASCADE_STEP_5',
        'CASCADE_STEP_MAX',
        'CASCADE_MULTIPLIER_INCREASE',
        'CASCADE_METER_COLLECT',
      ];

  @override
  String getBusForStage(String stageName) {
    if (stageName.contains('MUSIC')) return 'music';
    return 'sfx';
  }

  @override
  int getPriorityForStage(String stageName) {
    if (stageName == 'CASCADE_METER_FULL') return 85;
    if (stageName == 'CASCADE_CHAIN_BONUS') return 82;
    if (stageName == 'CASCADE_MULTIPLIER_MAX') return 80;
    if (stageName.contains('STEP_')) return 72;
    if (stageName.contains('REMOVE')) return 70;
    if (stageName.contains('MUSIC')) return 30;
    return 65;
  }

  // ============================================================================
  // Convenience Getters
  // ============================================================================

  /// Get cascade trigger condition.
  CascadeTrigger get triggerCondition {
    final value = getOptionValue<String>('triggerCondition') ?? 'anyWin';
    return CascadeTrigger.values.firstWhere(
      (t) => t.name == value,
      orElse: () => CascadeTrigger.anyWin,
    );
  }

  /// Get removal animation style.
  RemovalStyle get removalStyle {
    final value = getOptionValue<String>('removalStyle') ?? 'explode';
    return RemovalStyle.values.firstWhere(
      (r) => r.name == value,
      orElse: () => RemovalStyle.explode,
    );
  }

  /// Get fill animation style.
  FillStyle get fillStyle {
    final value = getOptionValue<String>('fillStyle') ?? 'dropFromTop';
    return FillStyle.values.firstWhere(
      (f) => f.name == value,
      orElse: () => FillStyle.dropFromTop,
    );
  }

  /// Get multiplier type.
  CascadeMultiplierType get multiplierType {
    final value = getOptionValue<String>('multiplierType') ?? 'progressive';
    return CascadeMultiplierType.values.firstWhere(
      (m) => m.name == value,
      orElse: () => CascadeMultiplierType.progressive,
    );
  }

  /// Get base multiplier.
  int get baseMultiplier => getOptionValue<int>('baseMultiplier') ?? 1;

  /// Get multiplier increment.
  int get multiplierIncrement => getOptionValue<int>('multiplierIncrement') ?? 1;

  /// Get max multiplier.
  int get maxMultiplier => getOptionValue<int>('maxMultiplier') ?? 10;

  /// Get cascade delay in milliseconds.
  int get cascadeDelay => getOptionValue<int>('cascadeDelay') ?? 300;

  /// Get max cascades (0 = unlimited).
  int get maxCascades => getOptionValue<int>('maxCascades') ?? 0;

  /// Whether cascades active in base game.
  bool get cascadeOnBaseGame => getOptionValue<bool>('cascadeOnBaseGame') ?? true;

  /// Whether cascades active in free spins.
  bool get cascadeInFreeSpins => getOptionValue<bool>('cascadeInFreeSpins') ?? true;
}
