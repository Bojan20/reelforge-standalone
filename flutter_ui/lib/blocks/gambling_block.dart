// ============================================================================
// FluxForge Studio — Feature Builder: Gambling Block
// ============================================================================
// P13.10: Gamble/Double-Up feature configuration
// Defines gamble types, win limits, bet options, and presentation styles
// ============================================================================

import '../models/feature_builder/feature_block.dart';
import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';

/// Gambling/Double-Up feature configuration block.
///
/// Configures:
/// - Gamble types (card, coin flip, wheel, ladder, dice)
/// - Win/loss limits and history
/// - Bet options (half, all, custom)
/// - Presentation and animation settings
/// - Audio stage generation for gamble flow
class GamblingBlock extends FeatureBlockBase {
  GamblingBlock() : super(enabled: false);

  @override
  String get id => 'gambling';

  @override
  String get name => 'Gamble Feature';

  @override
  String get description =>
      'Double-up gamble feature with multiple game types, win limits, '
      'and customizable presentation options.';

  @override
  BlockCategory get category => BlockCategory.feature;

  @override
  String get iconName => 'casino';

  @override
  int get stagePriority => 55;

  // ============================================================================
  // Options
  // ============================================================================

  @override
  List<BlockOption> createOptions() => [
        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Gamble Type
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.dropdown(
          id: 'gamble_type',
          name: 'Gamble Type',
          description: 'Primary gamble game type',
          choices: const [
            OptionChoice(
              value: 'card_color',
              label: 'Card Color (Red/Black)',
              description: 'Classic 50/50 red or black card gamble',
            ),
            OptionChoice(
              value: 'card_suit',
              label: 'Card Suit',
              description: '25% chance - guess the suit',
            ),
            OptionChoice(
              value: 'coin_flip',
              label: 'Coin Flip',
              description: 'Heads or tails coin flip gamble',
            ),
            OptionChoice(
              value: 'wheel',
              label: 'Gamble Wheel',
              description: 'Spin the wheel for multipliers',
            ),
            OptionChoice(
              value: 'ladder',
              label: 'Ladder Climb',
              description: 'Climb the ladder for increasing prizes',
            ),
            OptionChoice(
              value: 'dice',
              label: 'Dice Roll',
              description: 'Higher or lower dice roll gamble',
            ),
            OptionChoice(
              value: 'higher_lower',
              label: 'Higher/Lower',
              description: 'Guess if next card is higher or lower',
            ),
          ],
          defaultValue: 'card_color',
          group: 'Type',
          order: 0,
        ),

        BlockOptionFactory.toggle(
          id: 'allow_multiple_types',
          name: 'Multiple Types',
          description: 'Allow player to choose between gamble types',
          defaultValue: false,
          group: 'Type',
          order: 1,
        ),

        BlockOptionFactory.multiSelect(
          id: 'available_types',
          name: 'Available Types',
          description: 'Which gamble types are available',
          choices: const [
            OptionChoice(value: 'card_color', label: 'Card Color'),
            OptionChoice(value: 'card_suit', label: 'Card Suit'),
            OptionChoice(value: 'coin_flip', label: 'Coin Flip'),
            OptionChoice(value: 'wheel', label: 'Wheel'),
            OptionChoice(value: 'ladder', label: 'Ladder'),
            OptionChoice(value: 'dice', label: 'Dice'),
            OptionChoice(value: 'higher_lower', label: 'Higher/Lower'),
          ],
          defaultValue: ['card_color', 'coin_flip'],
          group: 'Type',
          order: 2,
          visibleWhen: {'allow_multiple_types': true},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Limits & Rules
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'enable_win_limit',
          name: 'Win Limit',
          description: 'Limit maximum gamble wins',
          defaultValue: true,
          group: 'Limits',
          order: 10,
        ),

        BlockOptionFactory.range(
          id: 'max_win_multiplier',
          name: 'Max Win Multiplier',
          description: 'Maximum win as multiplier of original bet',
          min: 2,
          max: 256,
          step: 2,
          defaultValue: 32,
          group: 'Limits',
          order: 11,
          visibleWhen: {'enable_win_limit': true},
        ),

        BlockOptionFactory.count(
          id: 'max_gamble_rounds',
          name: 'Max Rounds',
          description: 'Maximum consecutive gamble rounds allowed',
          min: 1,
          max: 10,
          defaultValue: 5,
          group: 'Limits',
          order: 12,
        ),

        BlockOptionFactory.toggle(
          id: 'enable_loss_limit',
          name: 'Loss Protection',
          description: 'Automatically collect after losses',
          defaultValue: false,
          group: 'Limits',
          order: 13,
        ),

        BlockOptionFactory.count(
          id: 'max_consecutive_losses',
          name: 'Max Losses',
          description: 'Force collect after consecutive losses',
          min: 1,
          max: 5,
          defaultValue: 3,
          group: 'Limits',
          order: 14,
          visibleWhen: {'enable_loss_limit': true},
        ),

        BlockOptionFactory.toggle(
          id: 'gamble_history',
          name: 'Show History',
          description: 'Display gamble history during session',
          defaultValue: true,
          group: 'Limits',
          order: 15,
        ),

        BlockOptionFactory.count(
          id: 'history_count',
          name: 'History Count',
          description: 'Number of previous results to show',
          min: 3,
          max: 20,
          defaultValue: 10,
          group: 'Limits',
          order: 16,
          visibleWhen: {'gamble_history': true},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Bet Options
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'allow_half_gamble',
          name: 'Gamble Half',
          description: 'Allow gambling half the win',
          defaultValue: true,
          group: 'Bet Options',
          order: 20,
        ),

        BlockOptionFactory.toggle(
          id: 'allow_custom_amount',
          name: 'Custom Amount',
          description: 'Allow custom gamble amounts',
          defaultValue: false,
          group: 'Bet Options',
          order: 21,
        ),

        BlockOptionFactory.dropdown(
          id: 'default_gamble_amount',
          name: 'Default Amount',
          description: 'Default gamble amount option',
          choices: const [
            OptionChoice(value: 'all', label: 'All'),
            OptionChoice(value: 'half', label: 'Half'),
            OptionChoice(value: 'quarter', label: 'Quarter'),
          ],
          defaultValue: 'all',
          group: 'Bet Options',
          order: 22,
        ),

        BlockOptionFactory.toggle(
          id: 'auto_gamble_option',
          name: 'Auto-Gamble',
          description: 'Enable auto-gamble for set rounds',
          defaultValue: false,
          group: 'Bet Options',
          order: 23,
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Card Gamble Settings
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'show_card_deck',
          name: 'Show Deck',
          description: 'Show remaining cards in deck',
          defaultValue: false,
          group: 'Card Settings',
          order: 30,
          visibleWhen: {'gamble_type': 'card_color'},
        ),

        BlockOptionFactory.toggle(
          id: 'fresh_deck_each_round',
          name: 'Fresh Deck',
          description: 'Use fresh deck each gamble round',
          defaultValue: true,
          group: 'Card Settings',
          order: 31,
          visibleWhen: {'gamble_type': 'card_color'},
        ),

        BlockOptionFactory.toggle(
          id: 'card_flip_animation',
          name: 'Card Flip',
          description: 'Animate card flip reveal',
          defaultValue: true,
          group: 'Card Settings',
          order: 32,
          visibleWhen: {'gamble_type': 'card_color'},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Wheel Settings
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.count(
          id: 'wheel_segments',
          name: 'Wheel Segments',
          description: 'Number of segments on wheel',
          min: 4,
          max: 24,
          defaultValue: 8,
          group: 'Wheel Settings',
          order: 40,
          visibleWhen: {'gamble_type': 'wheel'},
        ),

        BlockOptionFactory.toggle(
          id: 'wheel_has_lose_segment',
          name: 'Lose Segment',
          description: 'Include lose-all segment on wheel',
          defaultValue: true,
          group: 'Wheel Settings',
          order: 41,
          visibleWhen: {'gamble_type': 'wheel'},
        ),

        BlockOptionFactory.toggle(
          id: 'wheel_progressive',
          name: 'Progressive Multipliers',
          description: 'Multipliers increase each successful spin',
          defaultValue: false,
          group: 'Wheel Settings',
          order: 42,
          visibleWhen: {'gamble_type': 'wheel'},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Ladder Settings
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.count(
          id: 'ladder_steps',
          name: 'Ladder Steps',
          description: 'Number of ladder steps',
          min: 3,
          max: 12,
          defaultValue: 6,
          group: 'Ladder Settings',
          order: 50,
          visibleWhen: {'gamble_type': 'ladder'},
        ),

        BlockOptionFactory.toggle(
          id: 'ladder_safe_zones',
          name: 'Safe Zones',
          description: 'Include safe zones on ladder',
          defaultValue: true,
          group: 'Ladder Settings',
          order: 51,
          visibleWhen: {'gamble_type': 'ladder'},
        ),

        BlockOptionFactory.dropdown(
          id: 'ladder_progression',
          name: 'Progression Type',
          description: 'How multipliers increase up the ladder',
          choices: const [
            OptionChoice(value: 'linear', label: 'Linear (2x, 3x, 4x...)'),
            OptionChoice(value: 'exponential', label: 'Exponential (2x, 4x, 8x...)'),
            OptionChoice(value: 'fibonacci', label: 'Fibonacci (2x, 3x, 5x...)'),
            OptionChoice(value: 'custom', label: 'Custom'),
          ],
          defaultValue: 'exponential',
          group: 'Ladder Settings',
          order: 52,
          visibleWhen: {'gamble_type': 'ladder'},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Presentation
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.dropdown(
          id: 'presentation_style',
          name: 'Presentation Style',
          description: 'Visual presentation of gamble feature',
          choices: const [
            OptionChoice(
              value: 'classic',
              label: 'Classic',
              description: 'Traditional gamble screen',
            ),
            OptionChoice(
              value: 'overlay',
              label: 'Overlay',
              description: 'Gamble overlays on reels',
            ),
            OptionChoice(
              value: 'fullscreen',
              label: 'Fullscreen',
              description: 'Dedicated fullscreen gamble',
            ),
            OptionChoice(
              value: 'inline',
              label: 'Inline',
              description: 'Gamble in win display area',
            ),
          ],
          defaultValue: 'classic',
          group: 'Presentation',
          order: 60,
        ),

        BlockOptionFactory.toggle(
          id: 'show_odds',
          name: 'Show Odds',
          description: 'Display win odds to player',
          defaultValue: true,
          group: 'Presentation',
          order: 61,
        ),

        BlockOptionFactory.toggle(
          id: 'show_potential_win',
          name: 'Show Potential Win',
          description: 'Display potential win amount',
          defaultValue: true,
          group: 'Presentation',
          order: 62,
        ),

        BlockOptionFactory.toggle(
          id: 'countdown_timer',
          name: 'Decision Timer',
          description: 'Auto-collect after timeout',
          defaultValue: true,
          group: 'Presentation',
          order: 63,
        ),

        BlockOptionFactory.count(
          id: 'timer_seconds',
          name: 'Timer Duration',
          description: 'Seconds before auto-collect',
          min: 5,
          max: 60,
          defaultValue: 15,
          group: 'Presentation',
          order: 64,
          visibleWhen: {'countdown_timer': true},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Audio Stages
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'stage_offer',
          name: 'Gamble Offer',
          description: 'Audio when gamble is offered',
          defaultValue: true,
          group: 'Audio',
          order: 70,
        ),

        BlockOptionFactory.toggle(
          id: 'stage_suspense',
          name: 'Suspense Loop',
          description: 'Looping suspense during decision',
          defaultValue: true,
          group: 'Audio',
          order: 71,
        ),

        BlockOptionFactory.toggle(
          id: 'stage_reveal',
          name: 'Reveal Anticipation',
          description: 'Tension building before reveal',
          defaultValue: true,
          group: 'Audio',
          order: 72,
        ),

        BlockOptionFactory.toggle(
          id: 'stage_streak',
          name: 'Win Streak',
          description: 'Escalating audio for win streaks',
          defaultValue: true,
          group: 'Audio',
          order: 73,
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
          description: 'Gamble needs base game configuration',
        ),
        BlockDependency.requires(
          source: id,
          target: 'win_presentation',
          description: 'Gamble requires win presentation for trigger',
        ),
        BlockDependency.modifies(
          source: id,
          target: 'win_presentation',
          description: 'Gamble modifies win flow with collect/gamble choice',
        ),
      ];

  // ============================================================================
  // Stage Generation
  // ============================================================================

  @override
  List<String> get pooledStages => const [
        'GAMBLE_TIMER_TICK',
        'GAMBLE_HISTORY_SCROLL',
      ];

  @override
  String getBusForStage(String stageName) {
    if (stageName.contains('MUSIC') || stageName.contains('SUSPENSE')) {
      return 'music';
    }
    if (stageName.contains('WIN') ||
        stageName.contains('LOSE') ||
        stageName.contains('REVEAL') ||
        stageName.contains('COLLECT')) {
      return 'wins';
    }
    if (stageName.contains('UI') ||
        stageName.contains('BUTTON') ||
        stageName.contains('TIMER')) {
      return 'ui';
    }
    return 'sfx';
  }

  @override
  int getPriorityForStage(String stageName) {
    if (stageName.contains('JACKPOT') || stageName.contains('MAX_WIN')) {
      return 95;
    }
    if (stageName.contains('WIN')) return 80;
    if (stageName.contains('REVEAL')) return 75;
    if (stageName.contains('SUSPENSE')) return 65;
    if (stageName.contains('LOSE')) return 70;
    if (stageName.contains('ENTER') || stageName.contains('EXIT')) return 60;
    return 55;
  }

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];
    if (!isEnabled) return stages;

    final gambleType = getOptionValue<String>('gamble_type') ?? 'card_color';
    final stageOffer = getOptionValue<bool>('stage_offer') ?? true;
    final stageSuspense = getOptionValue<bool>('stage_suspense') ?? true;
    final stageReveal = getOptionValue<bool>('stage_reveal') ?? true;
    final stageStreak = getOptionValue<bool>('stage_streak') ?? true;
    final countdownTimer = getOptionValue<bool>('countdown_timer') ?? true;
    final gambleHistory = getOptionValue<bool>('gamble_history') ?? true;
    final maxRounds = getOptionValue<int>('max_gamble_rounds') ?? 5;

    // ═══════════════════════════════════════════════════════════════════════
    // Core Gamble Flow Stages
    // ═══════════════════════════════════════════════════════════════════════

    // Entry stages
    if (stageOffer) {
      stages.add(GeneratedStage(
        name: 'GAMBLE_OFFER',
        description: 'Gamble feature offered to player',
        bus: 'sfx',
        priority: 60,
        sourceBlockId: id,
      ));
    }

    stages.addAll([
      GeneratedStage(
        name: 'GAMBLE_ENTER',
        description: 'Player enters gamble feature',
        bus: 'sfx',
        priority: 62,
        sourceBlockId: id,
      ),
      GeneratedStage(
        name: 'GAMBLE_MUSIC_START',
        description: 'Gamble background music starts',
        bus: 'music',
        priority: 58,
        looping: true,
        sourceBlockId: id,
      ),
    ]);

    // Decision stages
    stages.addAll([
      GeneratedStage(
        name: 'GAMBLE_CHOICE_MADE',
        description: 'Player made their choice',
        bus: 'ui',
        priority: 65,
        sourceBlockId: id,
      ),
      GeneratedStage(
        name: 'GAMBLE_BUTTON_PRESS',
        description: 'Gamble button pressed',
        bus: 'ui',
        priority: 55,
        sourceBlockId: id,
      ),
    ]);

    // Suspense stages
    if (stageSuspense) {
      stages.addAll([
        GeneratedStage(
          name: 'GAMBLE_SUSPENSE_START',
          description: 'Suspense begins after choice',
          bus: 'music',
          priority: 64,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_SUSPENSE_LOOP',
          description: 'Looping suspense during reveal',
          bus: 'music',
          priority: 63,
          looping: true,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_SUSPENSE_END',
          description: 'Suspense ends at reveal',
          bus: 'music',
          priority: 66,
          sourceBlockId: id,
        ),
      ]);
    }

    // Reveal stages
    if (stageReveal) {
      stages.addAll([
        GeneratedStage(
          name: 'GAMBLE_REVEAL_BUILDUP',
          description: 'Tension building before reveal',
          bus: 'sfx',
          priority: 72,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_REVEAL',
          description: 'Result is revealed',
          bus: 'sfx',
          priority: 75,
          sourceBlockId: id,
        ),
      ]);
    }

    // Win stages
    stages.addAll([
      GeneratedStage(
        name: 'GAMBLE_WIN',
        description: 'Player won the gamble',
        bus: 'wins',
        priority: 80,
        sourceBlockId: id,
      ),
      GeneratedStage(
        name: 'GAMBLE_WIN_DOUBLE',
        description: 'Double win achieved (2x)',
        bus: 'wins',
        priority: 81,
        sourceBlockId: id,
      ),
      GeneratedStage(
        name: 'GAMBLE_WIN_BIG',
        description: 'Big win in gamble (high multiplier)',
        bus: 'wins',
        priority: 85,
        sourceBlockId: id,
      ),
      GeneratedStage(
        name: 'GAMBLE_WIN_MAX',
        description: 'Maximum gamble win achieved',
        bus: 'wins',
        priority: 90,
        sourceBlockId: id,
      ),
    ]);

    // Loss stages
    stages.addAll([
      GeneratedStage(
        name: 'GAMBLE_LOSE',
        description: 'Player lost the gamble',
        bus: 'wins',
        priority: 70,
        sourceBlockId: id,
      ),
      GeneratedStage(
        name: 'GAMBLE_LOSE_ALL',
        description: 'Player lost entire gamble amount',
        bus: 'wins',
        priority: 72,
        sourceBlockId: id,
      ),
    ]);

    // Win streak stages
    if (stageStreak) {
      for (int streak = 2; streak <= maxRounds; streak++) {
        stages.add(GeneratedStage(
          name: 'GAMBLE_STREAK_$streak',
          description: 'Win streak of $streak in a row',
          bus: 'wins',
          priority: 78 + streak,
          sourceBlockId: id,
        ));
      }
    }

    // Collect stages
    stages.addAll([
      GeneratedStage(
        name: 'GAMBLE_COLLECT',
        description: 'Player collects winnings',
        bus: 'sfx',
        priority: 68,
        sourceBlockId: id,
      ),
      GeneratedStage(
        name: 'GAMBLE_COLLECT_BUTTON',
        description: 'Collect button pressed',
        bus: 'ui',
        priority: 54,
        sourceBlockId: id,
      ),
    ]);

    // Exit stages
    stages.addAll([
      GeneratedStage(
        name: 'GAMBLE_EXIT',
        description: 'Exiting gamble feature',
        bus: 'sfx',
        priority: 58,
        sourceBlockId: id,
      ),
      GeneratedStage(
        name: 'GAMBLE_MUSIC_END',
        description: 'Gamble background music stops',
        bus: 'music',
        priority: 56,
        sourceBlockId: id,
      ),
      GeneratedStage(
        name: 'GAMBLE_RETURN_TO_GAME',
        description: 'Return to base game after gamble',
        bus: 'sfx',
        priority: 55,
        sourceBlockId: id,
      ),
    ]);

    // Timer stages
    if (countdownTimer) {
      stages.addAll([
        GeneratedStage(
          name: 'GAMBLE_TIMER_START',
          description: 'Decision timer started',
          bus: 'ui',
          priority: 50,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_TIMER_TICK',
          description: 'Timer countdown tick',
          bus: 'ui',
          priority: 45,
          pooled: true,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_TIMER_WARNING',
          description: 'Timer warning (low time)',
          bus: 'ui',
          priority: 52,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_TIMER_EXPIRED',
          description: 'Timer expired - auto collect',
          bus: 'ui',
          priority: 55,
          sourceBlockId: id,
        ),
      ]);
    }

    // History stages
    if (gambleHistory) {
      stages.addAll([
        GeneratedStage(
          name: 'GAMBLE_HISTORY_UPDATE',
          description: 'History updated with new result',
          bus: 'ui',
          priority: 40,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_HISTORY_SCROLL',
          description: 'History scrolling',
          bus: 'ui',
          priority: 35,
          pooled: true,
          sourceBlockId: id,
        ),
      ]);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Type-Specific Stages
    // ═══════════════════════════════════════════════════════════════════════

    if (gambleType == 'card_color' || gambleType == 'card_suit' ||
        gambleType == 'higher_lower') {
      stages.addAll([
        GeneratedStage(
          name: 'GAMBLE_CARD_DEAL',
          description: 'Card being dealt',
          bus: 'sfx',
          priority: 67,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_CARD_FLIP',
          description: 'Card flipping over',
          bus: 'sfx',
          priority: 70,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_CARD_SLIDE',
          description: 'Card sliding into position',
          bus: 'sfx',
          priority: 62,
          sourceBlockId: id,
        ),
      ]);

      if (gambleType == 'card_suit') {
        stages.add(GeneratedStage(
          name: 'GAMBLE_SUIT_SELECT',
          description: 'Player selects suit',
          bus: 'ui',
          priority: 58,
          sourceBlockId: id,
        ));
      }

      if (gambleType == 'higher_lower') {
        stages.addAll([
          GeneratedStage(
            name: 'GAMBLE_HIGHER_SELECT',
            description: 'Player selects higher',
            bus: 'ui',
            priority: 58,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'GAMBLE_LOWER_SELECT',
            description: 'Player selects lower',
            bus: 'ui',
            priority: 58,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'GAMBLE_TIE',
            description: 'Cards are equal - tie',
            bus: 'sfx',
            priority: 72,
            sourceBlockId: id,
          ),
        ]);
      }
    }

    if (gambleType == 'coin_flip') {
      stages.addAll([
        GeneratedStage(
          name: 'GAMBLE_COIN_TOSS',
          description: 'Coin being tossed',
          bus: 'sfx',
          priority: 68,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_COIN_SPIN_LOOP',
          description: 'Coin spinning in air',
          bus: 'sfx',
          priority: 64,
          looping: true,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_COIN_LAND',
          description: 'Coin landing',
          bus: 'sfx',
          priority: 72,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_HEADS_SELECT',
          description: 'Player selects heads',
          bus: 'ui',
          priority: 58,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_TAILS_SELECT',
          description: 'Player selects tails',
          bus: 'ui',
          priority: 58,
          sourceBlockId: id,
        ),
      ]);
    }

    if (gambleType == 'wheel') {
      stages.addAll([
        GeneratedStage(
          name: 'GAMBLE_WHEEL_SPIN_START',
          description: 'Wheel starts spinning',
          bus: 'sfx',
          priority: 68,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_WHEEL_SPIN_LOOP',
          description: 'Wheel spinning',
          bus: 'sfx',
          priority: 64,
          looping: true,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_WHEEL_SLOW',
          description: 'Wheel slowing down',
          bus: 'sfx',
          priority: 70,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_WHEEL_STOP',
          description: 'Wheel stopped',
          bus: 'sfx',
          priority: 74,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_WHEEL_TICK',
          description: 'Wheel tick as segment passes',
          bus: 'sfx',
          priority: 50,
          pooled: true,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_WHEEL_NEAR_WIN',
          description: 'Near big segment on wheel',
          bus: 'sfx',
          priority: 72,
          sourceBlockId: id,
        ),
      ]);
    }

    if (gambleType == 'ladder') {
      stages.addAll([
        GeneratedStage(
          name: 'GAMBLE_LADDER_CLIMB',
          description: 'Climbing up the ladder',
          bus: 'sfx',
          priority: 68,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_LADDER_STEP',
          description: 'Reached a ladder step',
          bus: 'sfx',
          priority: 65,
          pooled: true,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_LADDER_SAFE',
          description: 'Reached safe zone on ladder',
          bus: 'sfx',
          priority: 75,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_LADDER_TOP',
          description: 'Reached top of ladder',
          bus: 'wins',
          priority: 85,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_LADDER_FALL',
          description: 'Falling down ladder (lose)',
          bus: 'sfx',
          priority: 72,
          sourceBlockId: id,
        ),
      ]);
    }

    if (gambleType == 'dice') {
      stages.addAll([
        GeneratedStage(
          name: 'GAMBLE_DICE_SHAKE',
          description: 'Dice being shaken',
          bus: 'sfx',
          priority: 64,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_DICE_ROLL',
          description: 'Dice rolling',
          bus: 'sfx',
          priority: 68,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_DICE_BOUNCE',
          description: 'Dice bouncing',
          bus: 'sfx',
          priority: 66,
          pooled: true,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_DICE_STOP',
          description: 'Dice stopped',
          bus: 'sfx',
          priority: 72,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_DICE_HIGHER_SELECT',
          description: 'Player selects higher',
          bus: 'ui',
          priority: 58,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_DICE_LOWER_SELECT',
          description: 'Player selects lower',
          bus: 'ui',
          priority: 58,
          sourceBlockId: id,
        ),
      ]);
    }

    return stages;
  }
}
