// ============================================================================
// FluxForge Studio — Feature Builder: Jackpot Block
// ============================================================================
// P13.9: Jackpot system configuration
// Defines progressive/fixed jackpots, tiers, triggers, and contribution rates
// ============================================================================

import '../models/feature_builder/feature_block.dart';
import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';

/// Jackpot system configuration block.
///
/// Configures:
/// - Jackpot types (progressive, fixed, mystery)
/// - Tier structure (Mini, Minor, Major, Grand, etc.)
/// - Trigger mechanisms (symbol, random, bet-based)
/// - Contribution rates and caps
/// - Presentation settings
class JackpotBlock extends FeatureBlockBase {
  JackpotBlock() : super(enabled: false);

  @override
  String get id => 'jackpot';

  @override
  String get name => 'Jackpot System';

  @override
  String get description =>
      'Progressive and fixed jackpot configuration with multiple tiers, '
      'trigger modes, and contribution systems.';

  @override
  BlockCategory get category => BlockCategory.bonus;

  @override
  String get iconName => 'diamond';

  @override
  int get stagePriority => 95; // Highest priority

  // ============================================================================
  // Options
  // ============================================================================

  @override
  List<BlockOption> createOptions() => [
        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Jackpot Type
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.dropdown(
          id: 'jackpot_type',
          name: 'Jackpot Type',
          description: 'Primary jackpot system type',
          choices: const [
            OptionChoice(
              value: 'progressive',
              label: 'Progressive',
              description: 'Grows with player contributions',
            ),
            OptionChoice(
              value: 'fixed',
              label: 'Fixed',
              description: 'Static prize amounts',
            ),
            OptionChoice(
              value: 'mystery',
              label: 'Mystery',
              description: 'Triggers at random threshold',
            ),
            OptionChoice(
              value: 'network',
              label: 'Network Progressive',
              description: 'Shared across multiple games',
            ),
            OptionChoice(
              value: 'hybrid',
              label: 'Hybrid',
              description: 'Mix of progressive and fixed tiers',
            ),
          ],
          defaultValue: 'progressive',
          group: 'Type',
          order: 0,
        ),

        BlockOptionFactory.toggle(
          id: 'enable_mini',
          name: 'Enable Mini Jackpot',
          description: 'Lowest tier jackpot (frequent)',
          defaultValue: true,
          group: 'Tiers',
          order: 10,
        ),

        BlockOptionFactory.toggle(
          id: 'enable_minor',
          name: 'Enable Minor Jackpot',
          description: 'Second tier jackpot',
          defaultValue: true,
          group: 'Tiers',
          order: 11,
        ),

        BlockOptionFactory.toggle(
          id: 'enable_major',
          name: 'Enable Major Jackpot',
          description: 'Third tier jackpot',
          defaultValue: true,
          group: 'Tiers',
          order: 12,
        ),

        BlockOptionFactory.toggle(
          id: 'enable_grand',
          name: 'Enable Grand Jackpot',
          description: 'Highest tier jackpot (rare)',
          defaultValue: true,
          group: 'Tiers',
          order: 13,
        ),

        BlockOptionFactory.toggle(
          id: 'enable_mega',
          name: 'Enable Mega Jackpot',
          description: 'Ultra-rare mega tier (optional)',
          defaultValue: false,
          group: 'Tiers',
          order: 14,
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Trigger Mechanism
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.dropdown(
          id: 'trigger_mode',
          name: 'Trigger Mode',
          description: 'How jackpot is triggered',
          choices: const [
            OptionChoice(
              value: 'symbol_combo',
              label: 'Symbol Combination',
              description: 'Specific symbol pattern triggers jackpot',
            ),
            OptionChoice(
              value: 'random',
              label: 'Random Trigger',
              description: 'Any spin can randomly trigger',
            ),
            OptionChoice(
              value: 'collect',
              label: 'Coin Collect',
              description: 'Collect special symbols to fill meter',
            ),
            OptionChoice(
              value: 'wheel',
              label: 'Jackpot Wheel',
              description: 'Bonus wheel determines jackpot',
            ),
            OptionChoice(
              value: 'pick',
              label: 'Pick Game',
              description: 'Pick bonus reveals jackpot',
            ),
            OptionChoice(
              value: 'bet_based',
              label: 'Bet Based',
              description: 'Higher bets unlock higher tiers',
            ),
          ],
          defaultValue: 'symbol_combo',
          group: 'Trigger',
          order: 20,
        ),

        BlockOptionFactory.count(
          id: 'trigger_symbols_required',
          name: 'Symbols Required',
          description: 'Number of jackpot symbols needed to trigger',
          min: 3,
          max: 15,
          defaultValue: 5,
          group: 'Trigger',
          order: 21,
          visibleWhen: {'trigger_mode': 'symbol_combo'},
        ),

        BlockOptionFactory.toggle(
          id: 'trigger_any_position',
          name: 'Any Position',
          description: 'Symbols can appear anywhere (scatter-style)',
          defaultValue: true,
          group: 'Trigger',
          order: 22,
          visibleWhen: {'trigger_mode': 'symbol_combo'},
        ),

        BlockOptionFactory.percentage(
          id: 'random_trigger_rate',
          name: 'Random Trigger Rate',
          description: 'Base chance per spin (per-mille)',
          defaultValue: 5.0, // 0.5%
          perMille: true,
          group: 'Trigger',
          order: 23,
          visibleWhen: {'trigger_mode': 'random'},
        ),

        BlockOptionFactory.toggle(
          id: 'bet_qualifies',
          name: 'Bet Qualification',
          description: 'Only max bet qualifies for grand jackpot',
          defaultValue: true,
          group: 'Trigger',
          order: 24,
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Progressive Settings
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.percentage(
          id: 'contribution_rate',
          name: 'Contribution Rate',
          description: 'Percentage of bet contributing to jackpot pool',
          defaultValue: 1.5,
          group: 'Progressive',
          order: 30,
          visibleWhen: {'jackpot_type': 'progressive'},
        ),

        BlockOptionFactory.range(
          id: 'mini_seed',
          name: 'Mini Seed Value',
          description: 'Starting value for Mini jackpot (multiplier of bet)',
          min: 10,
          max: 100,
          step: 5,
          defaultValue: 20,
          group: 'Progressive',
          order: 31,
        ),

        BlockOptionFactory.range(
          id: 'minor_seed',
          name: 'Minor Seed Value',
          description: 'Starting value for Minor jackpot (multiplier of bet)',
          min: 50,
          max: 500,
          step: 10,
          defaultValue: 100,
          group: 'Progressive',
          order: 32,
        ),

        BlockOptionFactory.range(
          id: 'major_seed',
          name: 'Major Seed Value',
          description: 'Starting value for Major jackpot (multiplier of bet)',
          min: 500,
          max: 5000,
          step: 100,
          defaultValue: 1000,
          group: 'Progressive',
          order: 33,
        ),

        BlockOptionFactory.range(
          id: 'grand_seed',
          name: 'Grand Seed Value',
          description: 'Starting value for Grand jackpot (multiplier of bet)',
          min: 5000,
          max: 50000,
          step: 1000,
          defaultValue: 10000,
          group: 'Progressive',
          order: 34,
        ),

        BlockOptionFactory.toggle(
          id: 'has_cap',
          name: 'Jackpot Cap',
          description: 'Limit maximum jackpot value',
          defaultValue: false,
          group: 'Progressive',
          order: 35,
        ),

        BlockOptionFactory.range(
          id: 'cap_multiplier',
          name: 'Cap Multiplier',
          description: 'Maximum value as multiplier of seed',
          min: 2,
          max: 20,
          step: 1,
          defaultValue: 10,
          group: 'Progressive',
          order: 36,
          visibleWhen: {'has_cap': true},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Mystery Jackpot
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.range(
          id: 'mystery_min_threshold',
          name: 'Mystery Min Threshold',
          description: 'Minimum value before mystery can trigger',
          min: 100,
          max: 10000,
          step: 100,
          defaultValue: 500,
          group: 'Mystery',
          order: 40,
          visibleWhen: {'jackpot_type': 'mystery'},
        ),

        BlockOptionFactory.range(
          id: 'mystery_max_threshold',
          name: 'Mystery Max Threshold',
          description: 'Maximum value when mystery must trigger',
          min: 500,
          max: 50000,
          step: 500,
          defaultValue: 5000,
          group: 'Mystery',
          order: 41,
          visibleWhen: {'jackpot_type': 'mystery'},
        ),

        BlockOptionFactory.toggle(
          id: 'mystery_visible_threshold',
          name: 'Show Threshold',
          description: 'Display current mystery threshold to player',
          defaultValue: false,
          group: 'Mystery',
          order: 42,
          visibleWhen: {'jackpot_type': 'mystery'},
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Presentation
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.dropdown(
          id: 'presentation_style',
          name: 'Presentation Style',
          description: 'How jackpot win is presented',
          choices: const [
            OptionChoice(
              value: 'ticker_reveal',
              label: 'Ticker Reveal',
              description: 'Dramatic ticker with tier reveal',
            ),
            OptionChoice(
              value: 'explosion',
              label: 'Explosion',
              description: 'Big bang celebration effect',
            ),
            OptionChoice(
              value: 'coin_shower',
              label: 'Coin Shower',
              description: 'Raining coins animation',
            ),
            OptionChoice(
              value: 'spotlight',
              label: 'Spotlight',
              description: 'Focused spotlight effect',
            ),
          ],
          defaultValue: 'ticker_reveal',
          group: 'Presentation',
          order: 50,
        ),

        BlockOptionFactory.count(
          id: 'celebration_duration_sec',
          name: 'Celebration Duration',
          description: 'Jackpot celebration duration in seconds',
          min: 3,
          max: 30,
          defaultValue: 10,
          group: 'Presentation',
          order: 51,
        ),

        BlockOptionFactory.toggle(
          id: 'show_all_tiers',
          name: 'Show All Tiers',
          description: 'Display all jackpot tiers in UI',
          defaultValue: true,
          group: 'Presentation',
          order: 52,
        ),

        BlockOptionFactory.toggle(
          id: 'animate_contribution',
          name: 'Animate Contribution',
          description: 'Show contribution animation on each spin',
          defaultValue: true,
          group: 'Presentation',
          order: 53,
        ),

        // ══════════════════════════════════════════════════════════════════════
        // GROUP: Audio Stages
        // ══════════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'stage_contribution_tick',
          name: 'Contribution Tick',
          description: 'Audio tick on each contribution',
          defaultValue: true,
          group: 'Audio',
          order: 60,
        ),

        BlockOptionFactory.toggle(
          id: 'stage_near_trigger',
          name: 'Near Trigger',
          description: 'Audio cue when close to triggering',
          defaultValue: true,
          group: 'Audio',
          order: 61,
        ),

        BlockOptionFactory.toggle(
          id: 'stage_tier_specific',
          name: 'Tier-Specific Stages',
          description: 'Different audio for each tier',
          defaultValue: true,
          group: 'Audio',
          order: 62,
        ),

        BlockOptionFactory.toggle(
          id: 'stage_buildup',
          name: 'Jackpot Buildup',
          description: 'Tension building audio before reveal',
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
          description: 'Jackpot needs base game configuration',
        ),
        BlockDependency.enables(
          source: id,
          target: 'hold_and_win',
          description: 'Jackpot can enhance Hold & Win collection mechanic',
        ),
        BlockDependency.enables(
          source: id,
          target: 'bonus_game',
          description: 'Jackpot can be awarded through bonus game',
        ),
      ];

  // ============================================================================
  // Stage Generation
  // ============================================================================

  @override
  List<String> get pooledStages => const [
        'JACKPOT_CONTRIBUTION_TICK',
      ];

  @override
  String getBusForStage(String stageName) {
    if (stageName.contains('TRIGGER') ||
        stageName.contains('BUILDUP') ||
        stageName.contains('AWARD') ||
        stageName.contains('CELEBRATION')) {
      return 'wins'; // High priority bus
    }
    if (stageName.contains('CONTRIBUTION') || stageName.contains('NEAR')) {
      return 'sfx';
    }
    return 'sfx';
  }

  @override
  int getPriorityForStage(String stageName) {
    if (stageName.contains('GRAND') || stageName.contains('MEGA')) return 100;
    if (stageName.contains('MAJOR')) return 95;
    if (stageName.contains('MINOR')) return 90;
    if (stageName.contains('MINI')) return 85;
    if (stageName.contains('TRIGGER') || stageName.contains('BUILDUP')) {
      return 92;
    }
    return 70;
  }

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];
    if (!isEnabled) return stages;

    final triggerMode = getOptionValue<String>('trigger_mode') ?? 'symbol_combo';
    final presentationStyle =
        getOptionValue<String>('presentation_style') ?? 'ticker_reveal';
    final enableMini = getOptionValue<bool>('enable_mini') ?? true;
    final enableMinor = getOptionValue<bool>('enable_minor') ?? true;
    final enableMajor = getOptionValue<bool>('enable_major') ?? true;
    final enableGrand = getOptionValue<bool>('enable_grand') ?? true;
    final enableMega = getOptionValue<bool>('enable_mega') ?? false;
    final stageContributionTick =
        getOptionValue<bool>('stage_contribution_tick') ?? true;
    final stageNearTrigger = getOptionValue<bool>('stage_near_trigger') ?? true;
    final stageTierSpecific =
        getOptionValue<bool>('stage_tier_specific') ?? true;
    final stageBuildup = getOptionValue<bool>('stage_buildup') ?? true;

    // Build tier list
    final tiers = <String>[];
    if (enableMini) tiers.add('MINI');
    if (enableMinor) tiers.add('MINOR');
    if (enableMajor) tiers.add('MAJOR');
    if (enableGrand) tiers.add('GRAND');
    if (enableMega) tiers.add('MEGA');

    // ═══════════════════════════════════════════════════════════════════════
    // Contribution stages
    // ═══════════════════════════════════════════════════════════════════════
    if (stageContributionTick) {
      stages.add(GeneratedStage(
        name: 'JACKPOT_CONTRIBUTION_TICK',
        description: 'Audio tick when contribution added to jackpot pool',
        bus: 'sfx',
        priority: 40,
        pooled: true,
        sourceBlockId: id,
      ));
    }

    // Near trigger stages
    if (stageNearTrigger) {
      for (final tier in tiers) {
        stages.add(GeneratedStage(
          name: 'JACKPOT_NEAR_${tier}',
          description: 'Close to triggering $tier jackpot',
          bus: 'sfx',
          priority: 75,
          sourceBlockId: id,
        ));
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Trigger stages based on mode
    // ═══════════════════════════════════════════════════════════════════════
    stages.add(GeneratedStage(
      name: 'JACKPOT_TRIGGER',
      description: 'Generic jackpot triggered',
      bus: 'wins',
      priority: 92,
      sourceBlockId: id,
    ));

    if (triggerMode == 'symbol_combo') {
      stages.add(GeneratedStage(
        name: 'JACKPOT_SYMBOL_LAND',
        description: 'Jackpot symbol landed',
        bus: 'reels',
        priority: 70,
        pooled: true,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'JACKPOT_SYMBOL_COLLECT',
        description: 'Jackpot symbol collected/counted',
        bus: 'sfx',
        priority: 72,
        pooled: true,
        sourceBlockId: id,
      ));
    }

    if (triggerMode == 'wheel') {
      stages.add(GeneratedStage(
        name: 'JACKPOT_WHEEL_SPIN',
        description: 'Jackpot wheel spinning',
        bus: 'sfx',
        priority: 80,
        looping: true,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'JACKPOT_WHEEL_STOP',
        description: 'Jackpot wheel stopped',
        bus: 'sfx',
        priority: 85,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'JACKPOT_WHEEL_REVEAL',
        description: 'Jackpot wheel reveals tier',
        bus: 'wins',
        priority: 90,
        sourceBlockId: id,
      ));
    }

    if (triggerMode == 'pick') {
      stages.add(GeneratedStage(
        name: 'JACKPOT_PICK_SELECT',
        description: 'Player selecting in pick game',
        bus: 'ui',
        priority: 60,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'JACKPOT_PICK_REVEAL',
        description: 'Pick item reveals jackpot',
        bus: 'wins',
        priority: 88,
        sourceBlockId: id,
      ));
    }

    if (triggerMode == 'collect') {
      stages.add(GeneratedStage(
        name: 'JACKPOT_METER_FILL',
        description: 'Meter filling up',
        bus: 'sfx',
        priority: 65,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'JACKPOT_METER_FULL',
        description: 'Meter is full, jackpot ready',
        bus: 'wins',
        priority: 85,
        sourceBlockId: id,
      ));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Buildup and reveal stages
    // ═══════════════════════════════════════════════════════════════════════
    if (stageBuildup) {
      stages.add(GeneratedStage(
        name: 'JACKPOT_BUILDUP_START',
        description: 'Tension building before jackpot reveal',
        bus: 'wins',
        priority: 88,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'JACKPOT_BUILDUP_LOOP',
        description: 'Sustained tension loop',
        bus: 'wins',
        priority: 87,
        looping: true,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'JACKPOT_BUILDUP_END',
        description: 'Buildup culmination',
        bus: 'wins',
        priority: 89,
        sourceBlockId: id,
      ));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Tier-specific award stages
    // ═══════════════════════════════════════════════════════════════════════
    if (stageTierSpecific) {
      for (final tier in tiers) {
        stages.add(GeneratedStage(
          name: 'JACKPOT_REVEAL_$tier',
          description: '$tier jackpot tier revealed',
          bus: 'wins',
          priority: getPriorityForStage('JACKPOT_REVEAL_$tier'),
          sourceBlockId: id,
        ));
        stages.add(GeneratedStage(
          name: 'JACKPOT_AWARD_$tier',
          description: '$tier jackpot awarded',
          bus: 'wins',
          priority: getPriorityForStage('JACKPOT_AWARD_$tier'),
          sourceBlockId: id,
        ));
        stages.add(GeneratedStage(
          name: 'JACKPOT_CELEBRATION_$tier',
          description: '$tier jackpot celebration',
          bus: 'wins',
          priority: getPriorityForStage('JACKPOT_CELEBRATION_$tier'),
          looping: true,
          sourceBlockId: id,
        ));
      }
    } else {
      // Generic tier stages
      stages.add(GeneratedStage(
        name: 'JACKPOT_REVEAL',
        description: 'Jackpot tier revealed',
        bus: 'wins',
        priority: 90,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'JACKPOT_AWARD',
        description: 'Jackpot awarded',
        bus: 'wins',
        priority: 95,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'JACKPOT_CELEBRATION',
        description: 'Jackpot celebration',
        bus: 'wins',
        priority: 92,
        looping: true,
        sourceBlockId: id,
      ));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Presentation-specific stages
    // ═══════════════════════════════════════════════════════════════════════
    if (presentationStyle == 'ticker_reveal') {
      stages.add(GeneratedStage(
        name: 'JACKPOT_TICKER_START',
        description: 'Jackpot ticker animation starts',
        bus: 'wins',
        priority: 86,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'JACKPOT_TICKER_LOOP',
        description: 'Jackpot ticker counting',
        bus: 'wins',
        priority: 84,
        looping: true,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'JACKPOT_TICKER_END',
        description: 'Jackpot ticker finished',
        bus: 'wins',
        priority: 88,
        sourceBlockId: id,
      ));
    }

    if (presentationStyle == 'explosion') {
      stages.add(GeneratedStage(
        name: 'JACKPOT_EXPLOSION',
        description: 'Jackpot explosion effect',
        bus: 'wins',
        priority: 95,
        sourceBlockId: id,
      ));
    }

    if (presentationStyle == 'coin_shower') {
      stages.add(GeneratedStage(
        name: 'JACKPOT_COIN_SHOWER_START',
        description: 'Coin shower begins',
        bus: 'wins',
        priority: 85,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'JACKPOT_COIN_SHOWER_LOOP',
        description: 'Coin shower ongoing',
        bus: 'wins',
        priority: 80,
        looping: true,
        sourceBlockId: id,
      ));
      stages.add(GeneratedStage(
        name: 'JACKPOT_COIN_SHOWER_END',
        description: 'Coin shower ends',
        bus: 'wins',
        priority: 82,
        sourceBlockId: id,
      ));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // End stages
    // ═══════════════════════════════════════════════════════════════════════
    stages.add(GeneratedStage(
      name: 'JACKPOT_CELEBRATION_END',
      description: 'Jackpot celebration ending',
      bus: 'wins',
      priority: 75,
      sourceBlockId: id,
    ));

    stages.add(GeneratedStage(
      name: 'JACKPOT_RETURN_TO_GAME',
      description: 'Return to base game after jackpot',
      bus: 'sfx',
      priority: 60,
      sourceBlockId: id,
    ));

    return stages;
  }
}
