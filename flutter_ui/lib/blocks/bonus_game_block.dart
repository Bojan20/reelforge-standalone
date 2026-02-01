// ============================================================================
// FluxForge Studio — Feature Builder: Bonus Game Block
// ============================================================================
// P13.9: Bonus game system configuration
// Defines pick games, wheel bonuses, trail bonuses, and ladder games
// ============================================================================

import '../models/feature_builder/feature_block.dart';
import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';

/// Bonus game system configuration block.
///
/// Configures:
/// - Bonus types (pick, wheel, trail, ladder, board)
/// - Entry triggers and conditions
/// - Prize distribution and revelation
/// - Presentation and progression
class BonusGameBlock extends FeatureBlockBase {
  BonusGameBlock() : super(enabled: false);

  @override
  String get id => 'bonus_game';

  @override
  String get name => 'Bonus Games';

  @override
  String get description =>
      'Secondary bonus game configuration including pick games, wheel bonuses, '
      'trail features, and ladder bonuses.';

  @override
  BlockCategory get category => BlockCategory.bonus;

  @override
  String get iconName => 'casino';

  @override
  int get stagePriority => 80;

  // ============================================================================
  // Options
  // ============================================================================

  @override
  List<BlockOption> createOptions() => [
        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Bonus Type
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.dropdown(
          id: 'bonus_type',
          name: 'Bonus Type',
          description: 'Primary bonus game mechanic',
          choices: const [
            OptionChoice(
              value: 'pick',
              label: 'Pick Game',
              description: 'Player selects from hidden items',
            ),
            OptionChoice(
              value: 'wheel',
              label: 'Wheel Bonus',
              description: 'Spinning wheel determines prize',
            ),
            OptionChoice(
              value: 'trail',
              label: 'Trail/Board Game',
              description: 'Progress along path with prizes',
            ),
            OptionChoice(
              value: 'ladder',
              label: 'Ladder Bonus',
              description: 'Climb ladder with increasing prizes',
            ),
            OptionChoice(
              value: 'expanding',
              label: 'Expanding Grid',
              description: 'Grid reveals and expands',
            ),
            OptionChoice(
              value: 'match',
              label: 'Match Game',
              description: 'Match symbols for prizes',
            ),
          ],
          defaultValue: 'pick',
          group: 'Type',
          order: 0,
        ),

        BlockOptionFactory.toggle(
          id: 'multi_level',
          name: 'Multi-Level',
          description: 'Bonus has multiple levels/stages',
          defaultValue: false,
          group: 'Type',
          order: 1,
        ),

        BlockOptionFactory.count(
          id: 'level_count',
          name: 'Number of Levels',
          description: 'How many bonus levels',
          min: 2,
          max: 10,
          defaultValue: 3,
          group: 'Type',
          order: 2,
          visibleWhen: {'multi_level': true},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Entry Trigger
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.dropdown(
          id: 'trigger_type',
          name: 'Trigger Type',
          description: 'How bonus is triggered',
          choices: const [
            OptionChoice(
              value: 'scatter',
              label: 'Scatter Symbols',
              description: 'Scatter/bonus symbols trigger entry',
            ),
            OptionChoice(
              value: 'random',
              label: 'Random',
              description: 'Randomly triggered on any spin',
            ),
            OptionChoice(
              value: 'collect',
              label: 'Collect',
              description: 'Collect items to trigger',
            ),
            OptionChoice(
              value: 'feature_end',
              label: 'Feature End',
              description: 'Triggers at end of another feature',
            ),
            OptionChoice(
              value: 'buy',
              label: 'Feature Buy',
              description: 'Purchased with bonus buy',
            ),
          ],
          defaultValue: 'scatter',
          group: 'Trigger',
          order: 10,
        ),

        BlockOptionFactory.count(
          id: 'scatter_count',
          name: 'Scatters Required',
          description: 'Number of bonus symbols needed',
          min: 3,
          max: 6,
          defaultValue: 3,
          group: 'Trigger',
          order: 11,
          visibleWhen: {'trigger_type': 'scatter'},
        ),

        BlockOptionFactory.percentage(
          id: 'random_chance',
          name: 'Random Trigger Chance',
          description: 'Chance per spin (percentage)',
          defaultValue: 1.0,
          group: 'Trigger',
          order: 12,
          visibleWhen: {'trigger_type': 'random'},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Pick Game Settings
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.count(
          id: 'pick_items',
          name: 'Pick Items',
          description: 'Number of items to choose from',
          min: 6,
          max: 30,
          defaultValue: 12,
          group: 'Pick',
          order: 20,
          visibleWhen: {'bonus_type': 'pick'},
        ),

        BlockOptionFactory.count(
          id: 'pick_allowed',
          name: 'Picks Allowed',
          description: 'Number of picks player gets',
          min: 1,
          max: 10,
          defaultValue: 3,
          group: 'Pick',
          order: 21,
          visibleWhen: {'bonus_type': 'pick'},
        ),

        BlockOptionFactory.toggle(
          id: 'pick_until_popper',
          name: 'Pick Until Popper',
          description: 'Continue until collect/end symbol found',
          defaultValue: true,
          group: 'Pick',
          order: 22,
          visibleWhen: {'bonus_type': 'pick'},
        ),

        BlockOptionFactory.toggle(
          id: 'pick_reveal_all',
          name: 'Reveal All After',
          description: 'Show all items after bonus ends',
          defaultValue: true,
          group: 'Pick',
          order: 23,
          visibleWhen: {'bonus_type': 'pick'},
        ),

        BlockOptionFactory.dropdown(
          id: 'pick_prize_type',
          name: 'Prize Type',
          description: 'What can be won from picks',
          choices: const [
            OptionChoice(
              value: 'credits',
              label: 'Credit Prizes',
              description: 'Fixed or bet-multiplied credits',
            ),
            OptionChoice(
              value: 'multiplier',
              label: 'Multipliers',
              description: 'Win multiplier values',
            ),
            OptionChoice(
              value: 'spins',
              label: 'Free Spins',
              description: 'Award free spins',
            ),
            OptionChoice(
              value: 'mixed',
              label: 'Mixed',
              description: 'Combination of prize types',
            ),
          ],
          defaultValue: 'credits',
          group: 'Pick',
          order: 24,
          visibleWhen: {'bonus_type': 'pick'},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Wheel Settings
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.count(
          id: 'wheel_segments',
          name: 'Wheel Segments',
          description: 'Number of segments on wheel',
          min: 8,
          max: 24,
          defaultValue: 12,
          group: 'Wheel',
          order: 30,
          visibleWhen: {'bonus_type': 'wheel'},
        ),

        BlockOptionFactory.toggle(
          id: 'wheel_progressive',
          name: 'Progressive Wheel',
          description: 'Multiple wheel spins possible',
          defaultValue: false,
          group: 'Wheel',
          order: 31,
          visibleWhen: {'bonus_type': 'wheel'},
        ),

        BlockOptionFactory.toggle(
          id: 'wheel_multiplier',
          name: 'Multiplier Wheel',
          description: 'Wheel awards multipliers, not credits',
          defaultValue: false,
          group: 'Wheel',
          order: 32,
          visibleWhen: {'bonus_type': 'wheel'},
        ),

        BlockOptionFactory.toggle(
          id: 'wheel_jackpot_segment',
          name: 'Jackpot Segment',
          description: 'Wheel can award jackpot',
          defaultValue: false,
          group: 'Wheel',
          order: 33,
          visibleWhen: {'bonus_type': 'wheel'},
        ),

        BlockOptionFactory.dropdown(
          id: 'wheel_stop_mode',
          name: 'Wheel Stop',
          description: 'How wheel determines prize',
          choices: const [
            OptionChoice(
              value: 'random',
              label: 'RNG Determined',
              description: 'Result predetermined by RNG',
            ),
            OptionChoice(
              value: 'timed',
              label: 'Timed Stop',
              description: 'Player stops wheel',
            ),
            OptionChoice(
              value: 'physics',
              label: 'Physics',
              description: 'Realistic momentum-based stop',
            ),
          ],
          defaultValue: 'random',
          group: 'Wheel',
          order: 34,
          visibleWhen: {'bonus_type': 'wheel'},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Trail Settings
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.count(
          id: 'trail_length',
          name: 'Trail Length',
          description: 'Number of spaces on trail',
          min: 10,
          max: 50,
          defaultValue: 20,
          group: 'Trail',
          order: 40,
          visibleWhen: {'bonus_type': 'trail'},
        ),

        BlockOptionFactory.dropdown(
          id: 'trail_movement',
          name: 'Movement Method',
          description: 'How player moves on trail',
          choices: const [
            OptionChoice(
              value: 'dice',
              label: 'Dice Roll',
              description: 'Roll dice to determine steps',
            ),
            OptionChoice(
              value: 'spinner',
              label: 'Spinner',
              description: 'Spinner determines steps',
            ),
            OptionChoice(
              value: 'card',
              label: 'Card Draw',
              description: 'Draw card to move',
            ),
            OptionChoice(
              value: 'fixed',
              label: 'Fixed Steps',
              description: 'Move fixed number each turn',
            ),
          ],
          defaultValue: 'dice',
          group: 'Trail',
          order: 41,
          visibleWhen: {'bonus_type': 'trail'},
        ),

        BlockOptionFactory.toggle(
          id: 'trail_branching',
          name: 'Branching Paths',
          description: 'Trail has multiple path choices',
          defaultValue: false,
          group: 'Trail',
          order: 42,
          visibleWhen: {'bonus_type': 'trail'},
        ),

        BlockOptionFactory.toggle(
          id: 'trail_loops',
          name: 'Allow Loops',
          description: 'Trail can loop back on itself',
          defaultValue: false,
          group: 'Trail',
          order: 43,
          visibleWhen: {'bonus_type': 'trail'},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Ladder Settings
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.count(
          id: 'ladder_rungs',
          name: 'Ladder Rungs',
          description: 'Number of steps on ladder',
          min: 5,
          max: 20,
          defaultValue: 10,
          group: 'Ladder',
          order: 50,
          visibleWhen: {'bonus_type': 'ladder'},
        ),

        BlockOptionFactory.dropdown(
          id: 'ladder_gamble',
          name: 'Gamble Mode',
          description: 'How climbing works',
          choices: const [
            OptionChoice(
              value: 'auto',
              label: 'Automatic',
              description: 'Climb automatically',
            ),
            OptionChoice(
              value: 'gamble',
              label: 'Gamble',
              description: 'Gamble to climb higher',
            ),
            OptionChoice(
              value: 'collect_or_climb',
              label: 'Collect or Climb',
              description: 'Choose to collect or try climbing',
            ),
          ],
          defaultValue: 'collect_or_climb',
          group: 'Ladder',
          order: 51,
          visibleWhen: {'bonus_type': 'ladder'},
        ),

        BlockOptionFactory.toggle(
          id: 'ladder_fall_risk',
          name: 'Fall Risk',
          description: 'Can fall and lose winnings',
          defaultValue: true,
          group: 'Ladder',
          order: 52,
          visibleWhen: {'bonus_type': 'ladder'},
        ),

        BlockOptionFactory.toggle(
          id: 'ladder_safe_rungs',
          name: 'Safe Rungs',
          description: 'Some rungs are safe points',
          defaultValue: true,
          group: 'Ladder',
          order: 53,
          visibleWhen: {'ladder_fall_risk': true},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Prizes
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'prize_bet_multiplied',
          name: 'Bet Multiplied',
          description: 'Prizes are multiplied by bet',
          defaultValue: true,
          group: 'Prizes',
          order: 60,
        ),

        BlockOptionFactory.toggle(
          id: 'prize_progressive',
          name: 'Progressive Prizes',
          description: 'Prizes increase through bonus',
          defaultValue: false,
          group: 'Prizes',
          order: 61,
        ),

        BlockOptionFactory.toggle(
          id: 'prize_jackpot_possible',
          name: 'Jackpot Possible',
          description: 'Bonus can award jackpot',
          defaultValue: false,
          group: 'Prizes',
          order: 62,
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Presentation
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'fullscreen',
          name: 'Fullscreen',
          description: 'Bonus takes over entire screen',
          defaultValue: true,
          group: 'Presentation',
          order: 70,
        ),

        BlockOptionFactory.toggle(
          id: 'animated_intro',
          name: 'Animated Intro',
          description: 'Play intro animation before bonus',
          defaultValue: true,
          group: 'Presentation',
          order: 71,
        ),

        BlockOptionFactory.toggle(
          id: 'running_total',
          name: 'Running Total',
          description: 'Show accumulated wins during bonus',
          defaultValue: true,
          group: 'Presentation',
          order: 72,
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Audio Stages
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'stage_intro',
          name: 'Intro Stages',
          description: 'Entry and intro audio',
          defaultValue: true,
          group: 'Audio',
          order: 80,
        ),

        BlockOptionFactory.toggle(
          id: 'stage_action',
          name: 'Action Stages',
          description: 'Pick/spin/move audio',
          defaultValue: true,
          group: 'Audio',
          order: 81,
        ),

        BlockOptionFactory.toggle(
          id: 'stage_reveal',
          name: 'Reveal Stages',
          description: 'Prize reveal audio',
          defaultValue: true,
          group: 'Audio',
          order: 82,
        ),

        BlockOptionFactory.toggle(
          id: 'stage_music',
          name: 'Bonus Music',
          description: 'Dedicated bonus background music',
          defaultValue: true,
          group: 'Audio',
          order: 83,
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
          description: 'Bonus needs base game configuration',
        ),
        BlockDependency.enables(
          source: id,
          target: 'jackpot',
          description: 'Bonus can award jackpot',
        ),
        BlockDependency.modifies(
          source: id,
          target: 'free_spins',
          description: 'Bonus can award free spins',
        ),
        BlockDependency.modifies(
          source: id,
          target: 'multiplier',
          description: 'Bonus can include multipliers',
        ),
      ];

  // ============================================================================
  // Stage Generation
  // ============================================================================

  @override
  List<String> get pooledStages => const [
        'BONUS_PICK_SELECT',
        'BONUS_WHEEL_TICK',
        'BONUS_TRAIL_STEP',
        'BONUS_LADDER_STEP',
        'BONUS_PRIZE_REVEAL',
      ];

  @override
  String getBusForStage(String stageName) {
    if (stageName.contains('MUSIC')) return 'music';
    if (stageName.contains('JACKPOT')) return 'wins';
    if (stageName.contains('GRAND') || stageName.contains('MEGA')) return 'wins';
    return 'sfx';
  }

  @override
  int getPriorityForStage(String stageName) {
    if (stageName.contains('JACKPOT')) return 95;
    if (stageName.contains('GRAND') || stageName.contains('MEGA')) return 90;
    if (stageName.contains('INTRO') || stageName.contains('OUTRO')) return 85;
    if (stageName.contains('REVEAL')) return 75;
    return 65;
  }

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];
    if (!isEnabled) return stages;

    final bonusType = getOptionValue<String>('bonus_type') ?? 'pick';
    final multiLevel = getOptionValue<bool>('multi_level') ?? false;
    final levelCount = getOptionValue<int>('level_count') ?? 3;
    final stageIntro = getOptionValue<bool>('stage_intro') ?? true;
    final stageAction = getOptionValue<bool>('stage_action') ?? true;
    final stageReveal = getOptionValue<bool>('stage_reveal') ?? true;
    final stageMusic = getOptionValue<bool>('stage_music') ?? true;

    // ═══════════════════════════════════════════════════════════════════════
    // Entry and intro stages
    // ═══════════════════════════════════════════════════════════════════════
    stages.add(GeneratedStage(
      name: 'BONUS_TRIGGER',
      description: 'Bonus game triggered',
      bus: 'sfx',
      priority: 85,
      sourceBlockId: id,
    ));

    if (stageIntro) {
      stages.add(GeneratedStage(
        name: 'BONUS_INTRO_START',
        description: 'Bonus intro animation begins',
        bus: 'sfx',
        priority: 82,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_INTRO_END',
        description: 'Bonus intro animation ends',
        bus: 'sfx',
        priority: 80,
        sourceBlockId: id,
      ));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Bonus music
    // ═══════════════════════════════════════════════════════════════════════
    if (stageMusic) {
      stages.add(GeneratedStage(
        name: 'BONUS_MUSIC_START',
        description: 'Bonus background music starts',
        bus: 'music',
        priority: 50,
        looping: true,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_MUSIC_LOOP',
        description: 'Bonus music loop',
        bus: 'music',
        priority: 45,
        looping: true,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_MUSIC_END',
        description: 'Bonus music ends',
        bus: 'music',
        priority: 55,
        sourceBlockId: id,
      ));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Type-specific stages
    // ═══════════════════════════════════════════════════════════════════════
    if (bonusType == 'pick') {
      _addPickStages(stages, stageAction, stageReveal);
    } else if (bonusType == 'wheel') {
      _addWheelStages(stages, stageAction, stageReveal);
    } else if (bonusType == 'trail') {
      _addTrailStages(stages, stageAction, stageReveal);
    } else if (bonusType == 'ladder') {
      _addLadderStages(stages, stageAction, stageReveal);
    } else if (bonusType == 'expanding') {
      _addExpandingStages(stages, stageAction, stageReveal);
    } else if (bonusType == 'match') {
      _addMatchStages(stages, stageAction, stageReveal);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Multi-level stages
    // ═══════════════════════════════════════════════════════════════════════
    if (multiLevel) {
      for (int i = 1; i <= levelCount; i++) {
        stages.add(GeneratedStage(
          name: 'BONUS_LEVEL_${i}_START',
          description: 'Level $i starting',
          bus: 'sfx',
          priority: 75,
          sourceBlockId: id,
        ));
        stages.add(GeneratedStage(
          name: 'BONUS_LEVEL_${i}_COMPLETE',
          description: 'Level $i completed',
          bus: 'sfx',
          priority: 78,
          sourceBlockId: id,
        ));
      }
      stages.add(GeneratedStage(
        name: 'BONUS_LEVEL_UP',
        description: 'Advancing to next level',
        bus: 'sfx',
        priority: 80,
        sourceBlockId: id,
      ));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Prize and end stages
    // ═══════════════════════════════════════════════════════════════════════
    stages.add(GeneratedStage(
      name: 'BONUS_PRIZE_SMALL',
      description: 'Small prize awarded',
      bus: 'sfx',
      priority: 65,
      sourceBlockId: id,
    ));
    stages.add(GeneratedStage(
      name: 'BONUS_PRIZE_MEDIUM',
      description: 'Medium prize awarded',
      bus: 'sfx',
      priority: 70,
      sourceBlockId: id,
    ));
    stages.add(GeneratedStage(
      name: 'BONUS_PRIZE_BIG',
      description: 'Big prize awarded',
      bus: 'sfx',
      priority: 78,
      sourceBlockId: id,
    ));
    stages.add(GeneratedStage(
      name: 'BONUS_PRIZE_MEGA',
      description: 'Mega prize awarded',
      bus: 'wins',
      priority: 85,
      sourceBlockId: id,
    ));

    stages.add(GeneratedStage(
      name: 'BONUS_TOTAL_DISPLAY',
      description: 'Total bonus win displayed',
      bus: 'sfx',
      priority: 75,
      sourceBlockId: id,
    ));

    stages.add(GeneratedStage(
      name: 'BONUS_END',
      description: 'Bonus game ending',
      bus: 'sfx',
      priority: 70,
      sourceBlockId: id,
    ));

    stages.add(GeneratedStage(
      name: 'BONUS_RETURN_TO_GAME',
      description: 'Returning to base game',
      bus: 'sfx',
      priority: 60,
      sourceBlockId: id,
    ));

    return stages;
  }

  void _addPickStages(
      List<GeneratedStage> stages, bool stageAction, bool stageReveal) {
    if (stageAction) {
      stages.add(GeneratedStage(
        name: 'BONUS_PICK_READY',
        description: 'Ready for player pick',
        bus: 'sfx',
        priority: 60,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_PICK_SELECT',
        description: 'Player selecting item',
        bus: 'ui',
        priority: 55,
        pooled: true,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_PICK_HOVER',
        description: 'Hovering over pick item',
        bus: 'ui',
        priority: 40,
        pooled: true,
        sourceBlockId: id,
      ));
    }

    if (stageReveal) {
      stages.add(GeneratedStage(
        name: 'BONUS_PICK_REVEAL',
        description: 'Pick item revealing',
        bus: 'sfx',
        priority: 70,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_PICK_REVEAL_PRIZE',
        description: 'Prize item revealed',
        bus: 'sfx',
        priority: 72,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_PICK_REVEAL_COLLECT',
        description: 'Collect/end item revealed',
        bus: 'sfx',
        priority: 75,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_PICK_REVEAL_UPGRADE',
        description: 'Upgrade item revealed',
        bus: 'sfx',
        priority: 73,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_PICK_REVEAL_ALL',
        description: 'Revealing all remaining items',
        bus: 'sfx',
        priority: 65,
        sourceBlockId: id,
      ));
    }
  }

  void _addWheelStages(
      List<GeneratedStage> stages, bool stageAction, bool stageReveal) {
    if (stageAction) {
      stages.add(GeneratedStage(
        name: 'BONUS_WHEEL_READY',
        description: 'Wheel ready to spin',
        bus: 'sfx',
        priority: 60,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_WHEEL_SPIN_START',
        description: 'Wheel starting to spin',
        bus: 'sfx',
        priority: 70,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_WHEEL_SPIN_LOOP',
        description: 'Wheel spinning',
        bus: 'sfx',
        priority: 65,
        looping: true,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_WHEEL_TICK',
        description: 'Wheel segment tick',
        bus: 'sfx',
        priority: 50,
        pooled: true,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_WHEEL_SLOW',
        description: 'Wheel slowing down',
        bus: 'sfx',
        priority: 68,
        sourceBlockId: id,
      ));
    }

    if (stageReveal) {
      stages.add(GeneratedStage(
        name: 'BONUS_WHEEL_STOP',
        description: 'Wheel stopped',
        bus: 'sfx',
        priority: 72,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_WHEEL_REVEAL',
        description: 'Wheel prize revealed',
        bus: 'sfx',
        priority: 75,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_WHEEL_JACKPOT',
        description: 'Wheel landed on jackpot',
        bus: 'wins',
        priority: 90,
        sourceBlockId: id,
      ));
    }
  }

  void _addTrailStages(
      List<GeneratedStage> stages, bool stageAction, bool stageReveal) {
    if (stageAction) {
      stages.add(GeneratedStage(
        name: 'BONUS_TRAIL_DICE_ROLL',
        description: 'Rolling dice',
        bus: 'sfx',
        priority: 65,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_TRAIL_DICE_RESULT',
        description: 'Dice result shown',
        bus: 'sfx',
        priority: 68,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_TRAIL_STEP',
        description: 'Moving one step',
        bus: 'sfx',
        priority: 60,
        pooled: true,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_TRAIL_LAND',
        description: 'Landed on space',
        bus: 'sfx',
        priority: 70,
        sourceBlockId: id,
      ));
    }

    if (stageReveal) {
      stages.add(GeneratedStage(
        name: 'BONUS_TRAIL_PRIZE_SPACE',
        description: 'Landed on prize space',
        bus: 'sfx',
        priority: 72,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_TRAIL_BONUS_SPACE',
        description: 'Landed on bonus space',
        bus: 'sfx',
        priority: 75,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_TRAIL_END_SPACE',
        description: 'Reached end of trail',
        bus: 'sfx',
        priority: 80,
        sourceBlockId: id,
      ));
    }
  }

  void _addLadderStages(
      List<GeneratedStage> stages, bool stageAction, bool stageReveal) {
    if (stageAction) {
      stages.add(GeneratedStage(
        name: 'BONUS_LADDER_CLIMB_START',
        description: 'Starting to climb',
        bus: 'sfx',
        priority: 65,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_LADDER_STEP',
        description: 'Climbing one rung',
        bus: 'sfx',
        priority: 60,
        pooled: true,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_LADDER_GAMBLE',
        description: 'Gamble decision moment',
        bus: 'sfx',
        priority: 70,
        sourceBlockId: id,
      ));
    }

    if (stageReveal) {
      stages.add(GeneratedStage(
        name: 'BONUS_LADDER_SUCCESS',
        description: 'Successfully climbed',
        bus: 'sfx',
        priority: 72,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_LADDER_FAIL',
        description: 'Failed to climb',
        bus: 'sfx',
        priority: 70,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_LADDER_FALL',
        description: 'Falling down ladder',
        bus: 'sfx',
        priority: 75,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_LADDER_SAFE_RUNG',
        description: 'Reached safe rung',
        bus: 'sfx',
        priority: 73,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_LADDER_TOP',
        description: 'Reached top of ladder',
        bus: 'wins',
        priority: 85,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_LADDER_COLLECT',
        description: 'Collecting ladder prize',
        bus: 'sfx',
        priority: 72,
        sourceBlockId: id,
      ));
    }
  }

  void _addExpandingStages(
      List<GeneratedStage> stages, bool stageAction, bool stageReveal) {
    if (stageAction) {
      stages.add(GeneratedStage(
        name: 'BONUS_EXPAND_START',
        description: 'Grid expanding starts',
        bus: 'sfx',
        priority: 65,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_EXPAND_CELL',
        description: 'Cell expanding',
        bus: 'sfx',
        priority: 60,
        pooled: true,
        sourceBlockId: id,
      ));
    }

    if (stageReveal) {
      stages.add(GeneratedStage(
        name: 'BONUS_EXPAND_REVEAL',
        description: 'Cell content revealed',
        bus: 'sfx',
        priority: 70,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_EXPAND_COMPLETE',
        description: 'Grid fully expanded',
        bus: 'sfx',
        priority: 75,
        sourceBlockId: id,
      ));
    }
  }

  void _addMatchStages(
      List<GeneratedStage> stages, bool stageAction, bool stageReveal) {
    if (stageAction) {
      stages.add(GeneratedStage(
        name: 'BONUS_MATCH_SELECT',
        description: 'Selecting item to reveal',
        bus: 'ui',
        priority: 55,
        pooled: true,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_MATCH_FLIP',
        description: 'Flipping item',
        bus: 'sfx',
        priority: 60,
        sourceBlockId: id,
      ));
    }

    if (stageReveal) {
      stages.add(GeneratedStage(
        name: 'BONUS_MATCH_FOUND',
        description: 'Match found',
        bus: 'sfx',
        priority: 75,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_MATCH_MISS',
        description: 'No match',
        bus: 'sfx',
        priority: 65,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'BONUS_MATCH_COMPLETE',
        description: 'All matches found',
        bus: 'sfx',
        priority: 80,
        sourceBlockId: id,
      ));
    }
  }
}
