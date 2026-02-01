// ============================================================================
// FluxForge Studio — Free Spins Block
// ============================================================================
// P13.1.1: Feature block for Free Spins configuration
// Defines free spin triggers, retriggers, multipliers, and audio stages.
// ============================================================================

import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';
import '../models/feature_builder/feature_block.dart';

/// Free Spins trigger modes.
enum FreeSpinsTriggerMode {
  /// Scatter symbols trigger free spins.
  scatter,

  /// Bonus symbols trigger free spins.
  bonus,

  /// Any winning combination can trigger.
  anyWin,

  /// Specific symbol combinations trigger.
  specific,

  /// Random trigger on any spin.
  random,

  /// Feature buy (direct purchase).
  featureBuy,
}

/// Free Spins multiplier behavior.
enum MultiplierBehavior {
  /// Fixed multiplier for all free spins.
  fixed,

  /// Multiplier increases with each spin.
  progressive,

  /// Multiplier increases with each cascade.
  cascadeLinked,

  /// Multiplier increases with each wild.
  wildLinked,

  /// Random multiplier each spin.
  random,

  /// Multiplier resets on non-winning spin.
  resetting,
}

/// Free Spins retrigger mode.
enum RetriggerMode {
  /// Cannot retrigger during free spins.
  none,

  /// Add more spins (same multiplier).
  addSpins,

  /// Restart with fresh spins count.
  restart,

  /// Add spins with increased multiplier.
  addSpinsWithMultiplier,

  /// Unlimited retriggers possible.
  unlimited,
}

/// Feature block for Free Spins configuration.
///
/// This block defines:
/// - Trigger conditions and scatter requirements
/// - Number of free spins and retrigger behavior
/// - Multiplier mechanics (fixed, progressive, cascade-linked)
/// - Special free spins features (sticky wilds, extra wilds)
/// - Audio stages for all free spins phases
class FreeSpinsBlock extends FeatureBlockBase {
  FreeSpinsBlock() : super(enabled: false);

  @override
  String get id => 'free_spins';

  @override
  String get name => 'Free Spins';

  @override
  String get description =>
      'Bonus round with free spins, multipliers, and special features';

  @override
  BlockCategory get category => BlockCategory.feature;

  @override
  String get iconName => 'stars';

  @override
  bool get canBeDisabled => true;

  @override
  int get stagePriority => 10;

  @override
  List<BlockOption> createOptions() => [
        // ========== Trigger Settings ==========
        BlockOptionFactory.dropdown(
          id: 'triggerMode',
          name: 'Trigger Mode',
          description: 'How free spins are triggered',
          choices: [
            const OptionChoice(
              value: 'scatter',
              label: 'Scatter Symbols',
              description: 'Land required scatter symbols',
            ),
            const OptionChoice(
              value: 'bonus',
              label: 'Bonus Symbols',
              description: 'Land bonus symbols on specific reels',
            ),
            const OptionChoice(
              value: 'anyWin',
              label: 'Any Win Trigger',
              description: 'Any winning spin can trigger',
            ),
            const OptionChoice(
              value: 'specific',
              label: 'Specific Combination',
              description: 'Specific symbol combinations',
            ),
            const OptionChoice(
              value: 'random',
              label: 'Random Trigger',
              description: 'Random chance on any spin',
            ),
            const OptionChoice(
              value: 'featureBuy',
              label: 'Feature Buy',
              description: 'Direct purchase option',
            ),
          ],
          defaultValue: 'scatter',
          group: 'Trigger',
          order: 1,
        ),

        BlockOptionFactory.count(
          id: 'minScattersToTrigger',
          name: 'Min Scatters to Trigger',
          description: 'Minimum scatter symbols needed',
          min: 2,
          max: 6,
          defaultValue: 3,
          group: 'Trigger',
          order: 2,
        ),

        BlockOptionFactory.toggle(
          id: 'hasFeatureBuy',
          name: 'Feature Buy Available',
          description: 'Allow direct purchase of free spins',
          defaultValue: false,
          group: 'Trigger',
          order: 3,
        ),

        BlockOptionFactory.count(
          id: 'featureBuyCost',
          name: 'Feature Buy Cost',
          description: 'Cost multiplier relative to bet',
          min: 50,
          max: 500,
          defaultValue: 100,
          group: 'Trigger',
          order: 4,
        ),

        // ========== Spins Configuration ==========
        BlockOptionFactory.count(
          id: 'baseSpinsCount',
          name: 'Base Spins Count',
          description: 'Number of free spins awarded',
          min: 3,
          max: 50,
          defaultValue: 10,
          group: 'Spins',
          order: 5,
        ),

        BlockOptionFactory.toggle(
          id: 'variableSpins',
          name: 'Variable Spins',
          description: 'Different scatter counts give different spins',
          defaultValue: true,
          group: 'Spins',
          order: 6,
        ),

        // Spins per scatter tier (when variableSpins = true)
        BlockOptionFactory.count(
          id: 'spinsFor3Scatters',
          name: 'Spins for 3 Scatters',
          description: 'Free spins for 3 scatter symbols',
          min: 5,
          max: 30,
          defaultValue: 10,
          group: 'Spins',
          order: 7,
        ),

        BlockOptionFactory.count(
          id: 'spinsFor4Scatters',
          name: 'Spins for 4 Scatters',
          description: 'Free spins for 4 scatter symbols',
          min: 8,
          max: 40,
          defaultValue: 15,
          group: 'Spins',
          order: 8,
        ),

        BlockOptionFactory.count(
          id: 'spinsFor5Scatters',
          name: 'Spins for 5 Scatters',
          description: 'Free spins for 5 scatter symbols',
          min: 10,
          max: 50,
          defaultValue: 20,
          group: 'Spins',
          order: 9,
        ),

        // ========== Retrigger Settings ==========
        BlockOptionFactory.dropdown(
          id: 'retriggerMode',
          name: 'Retrigger Mode',
          description: 'How free spins can be retriggered',
          choices: [
            const OptionChoice(
              value: 'none',
              label: 'No Retrigger',
              description: 'Cannot retrigger during free spins',
            ),
            const OptionChoice(
              value: 'addSpins',
              label: 'Add Spins',
              description: 'Add more free spins',
            ),
            const OptionChoice(
              value: 'restart',
              label: 'Restart',
              description: 'Restart with fresh count',
            ),
            const OptionChoice(
              value: 'addSpinsWithMultiplier',
              label: 'Add + Multiplier',
              description: 'Add spins with increased multiplier',
            ),
            const OptionChoice(
              value: 'unlimited',
              label: 'Unlimited',
              description: 'No limit on retriggers',
            ),
          ],
          defaultValue: 'addSpins',
          group: 'Retrigger',
          order: 10,
        ),

        BlockOptionFactory.count(
          id: 'retriggerSpins',
          name: 'Retrigger Spins',
          description: 'Spins added on retrigger',
          min: 1,
          max: 20,
          defaultValue: 5,
          group: 'Retrigger',
          order: 11,
        ),

        BlockOptionFactory.count(
          id: 'maxRetriggers',
          name: 'Max Retriggers',
          description: 'Maximum number of retriggers (0 = unlimited)',
          min: 0,
          max: 10,
          defaultValue: 3,
          group: 'Retrigger',
          order: 12,
        ),

        // ========== Multiplier Settings ==========
        BlockOptionFactory.toggle(
          id: 'hasMultiplier',
          name: 'Has Multiplier',
          description: 'Enable win multiplier during free spins',
          defaultValue: true,
          group: 'Multiplier',
          order: 13,
        ),

        BlockOptionFactory.dropdown(
          id: 'multiplierBehavior',
          name: 'Multiplier Behavior',
          description: 'How the multiplier changes',
          choices: [
            const OptionChoice(
              value: 'fixed',
              label: 'Fixed',
              description: 'Constant multiplier',
            ),
            const OptionChoice(
              value: 'progressive',
              label: 'Progressive',
              description: 'Increases each spin',
            ),
            const OptionChoice(
              value: 'cascadeLinked',
              label: 'Cascade Linked',
              description: 'Increases with cascades',
            ),
            const OptionChoice(
              value: 'wildLinked',
              label: 'Wild Linked',
              description: 'Increases with wilds',
            ),
            const OptionChoice(
              value: 'random',
              label: 'Random',
              description: 'Random each spin',
            ),
            const OptionChoice(
              value: 'resetting',
              label: 'Resetting',
              description: 'Resets on non-win',
            ),
          ],
          defaultValue: 'fixed',
          group: 'Multiplier',
          order: 14,
        ),

        BlockOptionFactory.count(
          id: 'baseMultiplier',
          name: 'Base Multiplier',
          description: 'Starting multiplier value',
          min: 1,
          max: 10,
          defaultValue: 2,
          group: 'Multiplier',
          order: 15,
        ),

        BlockOptionFactory.count(
          id: 'maxMultiplier',
          name: 'Max Multiplier',
          description: 'Maximum multiplier value',
          min: 2,
          max: 100,
          defaultValue: 10,
          group: 'Multiplier',
          order: 16,
        ),

        BlockOptionFactory.count(
          id: 'multiplierStep',
          name: 'Multiplier Step',
          description: 'Amount multiplier increases',
          min: 1,
          max: 5,
          defaultValue: 1,
          group: 'Multiplier',
          order: 17,
        ),

        // ========== Special Features ==========
        BlockOptionFactory.toggle(
          id: 'hasStickyWilds',
          name: 'Sticky Wilds',
          description: 'Wilds stay in place during free spins',
          defaultValue: false,
          group: 'Special Features',
          order: 18,
        ),

        BlockOptionFactory.toggle(
          id: 'hasExpandingWilds',
          name: 'Expanding Wilds',
          description: 'Wilds expand to cover entire reel',
          defaultValue: false,
          group: 'Special Features',
          order: 19,
        ),

        BlockOptionFactory.toggle(
          id: 'hasWalkingWilds',
          name: 'Walking Wilds',
          description: 'Wilds move one position each spin',
          defaultValue: false,
          group: 'Special Features',
          order: 20,
        ),

        BlockOptionFactory.toggle(
          id: 'hasExtraWilds',
          name: 'Extra Wilds',
          description: 'Additional wild symbols during free spins',
          defaultValue: false,
          group: 'Special Features',
          order: 21,
        ),

        BlockOptionFactory.toggle(
          id: 'hasMysterySymbols',
          name: 'Mystery Symbols',
          description: 'Mystery symbols during free spins',
          defaultValue: false,
          group: 'Special Features',
          order: 22,
        ),

        BlockOptionFactory.toggle(
          id: 'hasGamble',
          name: 'Gamble Option',
          description: 'Gamble free spins wins',
          defaultValue: false,
          group: 'Special Features',
          order: 23,
        ),

        // ========== Audio Settings ==========
        BlockOptionFactory.toggle(
          id: 'hasDedicatedMusic',
          name: 'Dedicated Music',
          description: 'Special music track during free spins',
          defaultValue: true,
          group: 'Audio',
          order: 24,
        ),

        BlockOptionFactory.toggle(
          id: 'hasIntroSequence',
          name: 'Intro Sequence',
          description: 'Play intro animation/audio before spins start',
          defaultValue: true,
          group: 'Audio',
          order: 25,
        ),

        BlockOptionFactory.toggle(
          id: 'hasOutroSequence',
          name: 'Outro Sequence',
          description: 'Play outro animation/audio after spins end',
          defaultValue: true,
          group: 'Audio',
          order: 26,
        ),

        BlockOptionFactory.toggle(
          id: 'hasSpinCounter',
          name: 'Spin Counter Audio',
          description: 'Audio cue for remaining spins',
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
          description: 'Free Spins requires Game Core configuration',
          autoResolvable: true,
        ),

        // Requires Symbol Set (for scatter configuration)
        BlockDependency.requires(
          source: id,
          target: 'symbol_set',
          description: 'Free Spins requires Symbol Set for scatter symbols',
          autoResolvable: true,
        ),

        // Modifies Win Presentation (multipliers affect wins)
        BlockDependency.modifies(
          source: id,
          target: 'win_presentation',
          description: 'Free Spins modifies win presentation with multipliers',
        ),

        // Modifies Music States
        BlockDependency.modifies(
          source: id,
          target: 'music_states',
          description: 'Free Spins has dedicated music context',
        ),

        // Enables Cascades (if cascade-linked multiplier)
        if (getOptionValue<String>('multiplierBehavior') == 'cascadeLinked')
          BlockDependency.requires(
            source: id,
            target: 'cascades',
            description: 'Cascade-linked multiplier requires Cascades block',
            autoResolvable: true,
          ),
      ];

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];
    final hasIntro = getOptionValue<bool>('hasIntroSequence') ?? true;
    final hasOutro = getOptionValue<bool>('hasOutroSequence') ?? true;
    final hasMusic = getOptionValue<bool>('hasDedicatedMusic') ?? true;
    final hasCounter = getOptionValue<bool>('hasSpinCounter') ?? true;
    final hasMultiplier = getOptionValue<bool>('hasMultiplier') ?? true;
    final hasStickyWilds = getOptionValue<bool>('hasStickyWilds') ?? false;
    final hasExpandingWilds = getOptionValue<bool>('hasExpandingWilds') ?? false;
    final hasWalkingWilds = getOptionValue<bool>('hasWalkingWilds') ?? false;
    final retriggerMode = getOptionValue<String>('retriggerMode') ?? 'addSpins';
    final hasGamble = getOptionValue<bool>('hasGamble') ?? false;

    // ========== Trigger Stages ==========
    stages.add(GeneratedStage(
      name: 'FS_TRIGGER',
      description: 'Free spins feature triggered',
      bus: 'sfx',
      priority: 90,
      sourceBlockId: id,
      category: 'Free Spins',
    ));

    stages.add(GeneratedStage(
      name: 'FS_SCATTER_LAND',
      description: 'Scatter symbol lands (per scatter)',
      bus: 'sfx',
      priority: 75,
      pooled: true, // Rapid-fire for multiple scatters
      sourceBlockId: id,
      category: 'Free Spins',
    ));

    // ========== Intro/Transition Stages ==========
    if (hasIntro) {
      stages.add(GeneratedStage(
        name: 'FS_INTRO_START',
        description: 'Free spins intro sequence begins',
        bus: 'sfx',
        priority: 88,
        sourceBlockId: id,
        category: 'Free Spins',
      ));

      stages.add(GeneratedStage(
        name: 'FS_INTRO_END',
        description: 'Free spins intro sequence ends',
        bus: 'sfx',
        priority: 87,
        sourceBlockId: id,
        category: 'Free Spins',
      ));
    }

    stages.add(GeneratedStage(
      name: 'FS_ENTER',
      description: 'Enter free spins mode',
      bus: 'sfx',
      priority: 85,
      sourceBlockId: id,
      category: 'Free Spins',
    ));

    // ========== Music Stages ==========
    if (hasMusic) {
      stages.add(GeneratedStage(
        name: 'FS_MUSIC',
        description: 'Free spins background music',
        bus: 'music',
        priority: 20,
        looping: true,
        sourceBlockId: id,
        category: 'Free Spins',
      ));
    }

    // ========== Spin Stages ==========
    stages.add(GeneratedStage(
      name: 'FS_SPIN_START',
      description: 'Free spin begins',
      bus: 'sfx',
      priority: 70,
      sourceBlockId: id,
      category: 'Free Spins',
    ));

    stages.add(GeneratedStage(
      name: 'FS_SPIN_END',
      description: 'Free spin ends',
      bus: 'sfx',
      priority: 65,
      sourceBlockId: id,
      category: 'Free Spins',
    ));

    if (hasCounter) {
      stages.add(GeneratedStage(
        name: 'FS_SPIN_COUNTER',
        description: 'Spin counter update (X spins remaining)',
        bus: 'ui',
        priority: 50,
        pooled: true,
        sourceBlockId: id,
        category: 'Free Spins',
      ));

      stages.add(GeneratedStage(
        name: 'FS_LAST_SPIN',
        description: 'Last free spin indicator',
        bus: 'sfx',
        priority: 75,
        sourceBlockId: id,
        category: 'Free Spins',
      ));
    }

    // ========== Multiplier Stages ==========
    if (hasMultiplier) {
      stages.add(GeneratedStage(
        name: 'FS_MULTIPLIER_INCREASE',
        description: 'Multiplier value increases',
        bus: 'sfx',
        priority: 72,
        pooled: true,
        sourceBlockId: id,
        category: 'Free Spins',
      ));

      stages.add(GeneratedStage(
        name: 'FS_MULTIPLIER_MAX',
        description: 'Multiplier reached maximum',
        bus: 'sfx',
        priority: 78,
        sourceBlockId: id,
        category: 'Free Spins',
      ));

      stages.add(GeneratedStage(
        name: 'FS_MULTIPLIER_RESET',
        description: 'Multiplier resets (for resetting behavior)',
        bus: 'sfx',
        priority: 60,
        sourceBlockId: id,
        category: 'Free Spins',
      ));
    }

    // ========== Wild Feature Stages ==========
    if (hasStickyWilds) {
      stages.add(GeneratedStage(
        name: 'FS_WILD_STICK',
        description: 'Wild becomes sticky',
        bus: 'sfx',
        priority: 68,
        pooled: true,
        sourceBlockId: id,
        category: 'Free Spins',
      ));
    }

    if (hasExpandingWilds) {
      stages.add(GeneratedStage(
        name: 'FS_WILD_EXPAND',
        description: 'Wild expands to full reel',
        bus: 'sfx',
        priority: 70,
        sourceBlockId: id,
        category: 'Free Spins',
      ));
    }

    if (hasWalkingWilds) {
      stages.add(GeneratedStage(
        name: 'FS_WILD_WALK',
        description: 'Wild walks to new position',
        bus: 'sfx',
        priority: 65,
        pooled: true,
        sourceBlockId: id,
        category: 'Free Spins',
      ));

      stages.add(GeneratedStage(
        name: 'FS_WILD_EXIT',
        description: 'Walking wild exits the grid',
        bus: 'sfx',
        priority: 60,
        sourceBlockId: id,
        category: 'Free Spins',
      ));
    }

    // ========== Retrigger Stages ==========
    if (retriggerMode != 'none') {
      stages.add(GeneratedStage(
        name: 'FS_RETRIGGER',
        description: 'Free spins retriggered',
        bus: 'sfx',
        priority: 85,
        sourceBlockId: id,
        category: 'Free Spins',
      ));

      stages.add(GeneratedStage(
        name: 'FS_SPINS_ADDED',
        description: 'Additional spins added',
        bus: 'sfx',
        priority: 80,
        sourceBlockId: id,
        category: 'Free Spins',
      ));
    }

    // ========== Gamble Stages ==========
    if (hasGamble) {
      stages.add(GeneratedStage(
        name: 'FS_GAMBLE_OFFER',
        description: 'Gamble option offered',
        bus: 'sfx',
        priority: 70,
        sourceBlockId: id,
        category: 'Free Spins',
      ));
    }

    // ========== Exit Stages ==========
    if (hasOutro) {
      stages.add(GeneratedStage(
        name: 'FS_OUTRO_START',
        description: 'Free spins outro sequence begins',
        bus: 'sfx',
        priority: 82,
        sourceBlockId: id,
        category: 'Free Spins',
      ));

      stages.add(GeneratedStage(
        name: 'FS_OUTRO_END',
        description: 'Free spins outro sequence ends',
        bus: 'sfx',
        priority: 81,
        sourceBlockId: id,
        category: 'Free Spins',
      ));
    }

    stages.add(GeneratedStage(
      name: 'FS_EXIT',
      description: 'Exit free spins mode',
      bus: 'sfx',
      priority: 80,
      sourceBlockId: id,
      category: 'Free Spins',
    ));

    stages.add(GeneratedStage(
      name: 'FS_TOTAL_WIN',
      description: 'Total free spins win presentation',
      bus: 'sfx',
      priority: 85,
      sourceBlockId: id,
      category: 'Free Spins',
    ));

    return stages;
  }

  @override
  List<String> get pooledStages => [
        'FS_SCATTER_LAND',
        'FS_SPIN_COUNTER',
        'FS_MULTIPLIER_INCREASE',
        'FS_WILD_STICK',
        'FS_WILD_WALK',
      ];

  @override
  String getBusForStage(String stageName) {
    if (stageName == 'FS_MUSIC') return 'music';
    if (stageName.contains('COUNTER')) return 'ui';
    return 'sfx';
  }

  @override
  int getPriorityForStage(String stageName) {
    // Trigger and feature entry are highest
    if (stageName == 'FS_TRIGGER') return 90;
    if (stageName.contains('INTRO')) return 88;
    if (stageName == 'FS_ENTER') return 85;
    if (stageName == 'FS_RETRIGGER') return 85;
    if (stageName == 'FS_TOTAL_WIN') return 85;
    if (stageName == 'FS_EXIT') return 80;

    // Spin and multiplier events
    if (stageName.contains('SPIN')) return 70;
    if (stageName.contains('MULTIPLIER')) return 72;
    if (stageName.contains('WILD')) return 68;

    // Music lowest
    if (stageName == 'FS_MUSIC') return 20;

    return 50;
  }

  // ============================================================================
  // Convenience Getters
  // ============================================================================

  /// Get the trigger mode.
  FreeSpinsTriggerMode get triggerMode {
    final value = getOptionValue<String>('triggerMode') ?? 'scatter';
    return FreeSpinsTriggerMode.values.firstWhere(
      (t) => t.name == value,
      orElse: () => FreeSpinsTriggerMode.scatter,
    );
  }

  /// Get the multiplier behavior.
  MultiplierBehavior get multiplierBehavior {
    final value = getOptionValue<String>('multiplierBehavior') ?? 'fixed';
    return MultiplierBehavior.values.firstWhere(
      (m) => m.name == value,
      orElse: () => MultiplierBehavior.fixed,
    );
  }

  /// Get the retrigger mode.
  RetriggerMode get retriggerMode {
    final value = getOptionValue<String>('retriggerMode') ?? 'addSpins';
    return RetriggerMode.values.firstWhere(
      (r) => r.name == value,
      orElse: () => RetriggerMode.addSpins,
    );
  }

  /// Get base spins count.
  int get baseSpinsCount => getOptionValue<int>('baseSpinsCount') ?? 10;

  /// Get spins for specific scatter count.
  int getSpinsForScatters(int scatterCount) {
    if (!(getOptionValue<bool>('variableSpins') ?? true)) {
      return baseSpinsCount;
    }

    switch (scatterCount) {
      case 3:
        return getOptionValue<int>('spinsFor3Scatters') ?? 10;
      case 4:
        return getOptionValue<int>('spinsFor4Scatters') ?? 15;
      case 5:
        return getOptionValue<int>('spinsFor5Scatters') ?? 20;
      default:
        return scatterCount >= 5
            ? getOptionValue<int>('spinsFor5Scatters') ?? 20
            : baseSpinsCount;
    }
  }

  /// Get base multiplier.
  int get baseMultiplier => getOptionValue<int>('baseMultiplier') ?? 2;

  /// Get max multiplier.
  int get maxMultiplier => getOptionValue<int>('maxMultiplier') ?? 10;

  /// Whether sticky wilds are enabled.
  bool get hasStickyWilds => getOptionValue<bool>('hasStickyWilds') ?? false;

  /// Whether expanding wilds are enabled.
  bool get hasExpandingWilds =>
      getOptionValue<bool>('hasExpandingWilds') ?? false;

  /// Whether walking wilds are enabled.
  bool get hasWalkingWilds => getOptionValue<bool>('hasWalkingWilds') ?? false;

  /// Whether feature buy is available.
  bool get hasFeatureBuy => getOptionValue<bool>('hasFeatureBuy') ?? false;

  /// Get feature buy cost (multiplier of bet).
  int get featureBuyCost => getOptionValue<int>('featureBuyCost') ?? 100;
}
