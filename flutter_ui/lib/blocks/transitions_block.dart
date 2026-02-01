// ============================================================================
// FluxForge Studio — Transitions Block
// ============================================================================
// P13.0.11: Audio transitions between game contexts and states
// Handles context switches, music crossfades, feature entry/exit, and more.
// ============================================================================

import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';
import '../models/feature_builder/feature_block.dart';

/// Transitions Block — generates stages for audio transitions between contexts.
///
/// Covers:
/// - Context transitions (BASE↔FREESPINS, BASE↔BONUS, etc.)
/// - Music crossfades and layer transitions
/// - Feature entry/exit with audio cues
/// - Anticipation build-up and resolution
/// - Win tier escalation transitions
/// - UI state changes (menu, settings, etc.)
class TransitionsBlock extends FeatureBlockBase {
  TransitionsBlock() : super(enabled: true);

  @override
  String get id => 'transitions';

  @override
  String get name => 'Transitions';

  @override
  String get description =>
      'Audio transitions between game contexts, music states, and features';

  @override
  BlockCategory get category => BlockCategory.presentation;

  @override
  String get iconName => 'swap_horiz';

  @override
  bool get canBeDisabled => true;

  @override
  int get stagePriority => 30;

  @override
  List<BlockOption> createOptions() => [
        // ═══════════════════════════════════════════════════════════════════
        // CONTEXT TRANSITIONS
        // ═══════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'context_transitions',
          name: 'Context Transitions',
          description: 'Enable transitions between game contexts',
          defaultValue: true,
          group: 'Context',
          order: 0,
        ),
        BlockOptionFactory.toggle(
          id: 'base_to_freespins',
          name: 'Base → Free Spins',
          description: 'Transition from base game to free spins',
          defaultValue: true,
          group: 'Context',
          order: 1,
          visibleWhen: {'context_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'freespins_to_base',
          name: 'Free Spins → Base',
          description: 'Transition from free spins to base game',
          defaultValue: true,
          group: 'Context',
          order: 2,
          visibleWhen: {'context_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'base_to_bonus',
          name: 'Base → Bonus',
          description: 'Transition from base game to bonus round',
          defaultValue: true,
          group: 'Context',
          order: 3,
          visibleWhen: {'context_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'bonus_to_base',
          name: 'Bonus → Base',
          description: 'Transition from bonus round to base game',
          defaultValue: true,
          group: 'Context',
          order: 4,
          visibleWhen: {'context_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'base_to_holdwin',
          name: 'Base → Hold & Win',
          description: 'Transition from base game to Hold & Win',
          defaultValue: true,
          group: 'Context',
          order: 5,
          visibleWhen: {'context_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'holdwin_to_base',
          name: 'Hold & Win → Base',
          description: 'Transition from Hold & Win to base game',
          defaultValue: true,
          group: 'Context',
          order: 6,
          visibleWhen: {'context_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'base_to_bigwin',
          name: 'Base → Big Win',
          description: 'Transition to big win celebration',
          defaultValue: true,
          group: 'Context',
          order: 7,
          visibleWhen: {'context_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'bigwin_to_base',
          name: 'Big Win → Base',
          description: 'Transition from big win celebration to base',
          defaultValue: true,
          group: 'Context',
          order: 8,
          visibleWhen: {'context_transitions': true},
        ),

        // ═══════════════════════════════════════════════════════════════════
        // MUSIC TRANSITIONS
        // ═══════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'music_crossfades',
          name: 'Music Crossfades',
          description: 'Enable smooth music crossfade transitions',
          defaultValue: true,
          group: 'Music',
          order: 10,
        ),
        BlockOptionFactory.dropdown(
          id: 'crossfade_duration',
          name: 'Crossfade Duration',
          description: 'Duration of music crossfade',
          choices: [
            const OptionChoice(value: '500', label: '500ms'),
            const OptionChoice(value: '1000', label: '1000ms'),
            const OptionChoice(value: '1500', label: '1500ms'),
            const OptionChoice(value: '2000', label: '2000ms'),
            const OptionChoice(value: '3000', label: '3000ms'),
          ],
          defaultValue: '1500',
          group: 'Music',
          order: 11,
          visibleWhen: {'music_crossfades': true},
        ),
        BlockOptionFactory.toggle(
          id: 'music_layer_transitions',
          name: 'Layer Transitions',
          description: 'Enable ALE layer transitions (L1-L5)',
          defaultValue: true,
          group: 'Music',
          order: 12,
        ),
        BlockOptionFactory.toggle(
          id: 'music_stingers',
          name: 'Transition Stingers',
          description: 'Play stinger sounds during transitions',
          defaultValue: true,
          group: 'Music',
          order: 13,
        ),
        BlockOptionFactory.toggle(
          id: 'beat_sync',
          name: 'Beat-Synced',
          description: 'Synchronize transitions to beats/bars',
          defaultValue: true,
          group: 'Music',
          order: 14,
        ),

        // ═══════════════════════════════════════════════════════════════════
        // ANTICIPATION TRANSITIONS
        // ═══════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'anticipation_transitions',
          name: 'Anticipation Sequences',
          description: 'Enable anticipation build-up transitions',
          defaultValue: true,
          group: 'Anticipation',
          order: 20,
        ),
        BlockOptionFactory.count(
          id: 'anticipation_levels',
          name: 'Tension Levels',
          description: 'Number of tension levels (1-4)',
          min: 1,
          max: 4,
          defaultValue: 4,
          group: 'Anticipation',
          order: 21,
          visibleWhen: {'anticipation_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'anticipation_per_reel',
          name: 'Per-Reel Anticipation',
          description: 'Generate per-reel anticipation stages',
          defaultValue: true,
          group: 'Anticipation',
          order: 22,
          visibleWhen: {'anticipation_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'scatter_anticipation',
          name: 'Scatter Trigger',
          description: 'Anticipation triggered by scatters',
          defaultValue: true,
          group: 'Anticipation',
          order: 23,
          visibleWhen: {'anticipation_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'bonus_anticipation',
          name: 'Bonus Trigger',
          description: 'Anticipation triggered by bonus symbols',
          defaultValue: true,
          group: 'Anticipation',
          order: 24,
          visibleWhen: {'anticipation_transitions': true},
        ),

        // ═══════════════════════════════════════════════════════════════════
        // WIN TIER TRANSITIONS
        // ═══════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'win_tier_transitions',
          name: 'Win Tier Escalation',
          description: 'Enable win tier transitions during rollup',
          defaultValue: true,
          group: 'Win Tiers',
          order: 30,
        ),
        BlockOptionFactory.toggle(
          id: 'win_tier_upgrade',
          name: 'Tier Upgrade Fanfare',
          description: 'Play fanfare on tier upgrade',
          defaultValue: true,
          group: 'Win Tiers',
          order: 31,
          visibleWhen: {'win_tier_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'rollup_acceleration',
          name: 'Rollup Acceleration',
          description: 'Accelerate rollup during tier transitions',
          defaultValue: true,
          group: 'Win Tiers',
          order: 32,
          visibleWhen: {'win_tier_transitions': true},
        ),

        // ═══════════════════════════════════════════════════════════════════
        // UI TRANSITIONS
        // ═══════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'ui_transitions',
          name: 'UI State Transitions',
          description: 'Enable UI state change audio',
          defaultValue: true,
          group: 'UI',
          order: 40,
        ),
        BlockOptionFactory.toggle(
          id: 'menu_transitions',
          name: 'Menu Open/Close',
          description: 'Menu panel transitions',
          defaultValue: true,
          group: 'UI',
          order: 41,
          visibleWhen: {'ui_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'paytable_transitions',
          name: 'Paytable View',
          description: 'Paytable/info screen transitions',
          defaultValue: true,
          group: 'UI',
          order: 42,
          visibleWhen: {'ui_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'autoplay_transitions',
          name: 'Autoplay Mode',
          description: 'Autoplay start/stop transitions',
          defaultValue: true,
          group: 'UI',
          order: 43,
          visibleWhen: {'ui_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'turbo_transitions',
          name: 'Turbo Mode',
          description: 'Turbo mode toggle transitions',
          defaultValue: true,
          group: 'UI',
          order: 44,
          visibleWhen: {'ui_transitions': true},
        ),

        // ═══════════════════════════════════════════════════════════════════
        // SPECIAL TRANSITIONS
        // ═══════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'special_transitions',
          name: 'Special Transitions',
          description: 'Enable special/rare transition events',
          defaultValue: true,
          group: 'Special',
          order: 50,
        ),
        BlockOptionFactory.toggle(
          id: 'jackpot_approach',
          name: 'Jackpot Approach',
          description: 'Tension when approaching jackpot trigger',
          defaultValue: true,
          group: 'Special',
          order: 51,
          visibleWhen: {'special_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'near_miss_resolve',
          name: 'Near Miss Resolution',
          description: 'Audio cue when near-miss resolves',
          defaultValue: true,
          group: 'Special',
          order: 52,
          visibleWhen: {'special_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'session_bookends',
          name: 'Session Bookends',
          description: 'Audio for session start/end',
          defaultValue: false,
          group: 'Special',
          order: 53,
          visibleWhen: {'special_transitions': true},
        ),

        // ═══════════════════════════════════════════════════════════════════
        // JACKPOT TRANSITIONS
        // ═══════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'jackpot_transitions',
          name: 'Jackpot Transitions',
          description: 'Enable jackpot entry/exit transitions',
          defaultValue: true,
          group: 'Jackpot',
          order: 60,
        ),
        BlockOptionFactory.toggle(
          id: 'jackpot_tier_transitions',
          name: 'Tier Escalation',
          description: 'Audio for jackpot tier reveals',
          defaultValue: true,
          group: 'Jackpot',
          order: 61,
          visibleWhen: {'jackpot_transitions': true},
        ),

        // ═══════════════════════════════════════════════════════════════════
        // MULTIPLIER TRANSITIONS
        // ═══════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'multiplier_transitions',
          name: 'Multiplier Transitions',
          description: 'Enable multiplier change transitions',
          defaultValue: true,
          group: 'Multiplier',
          order: 70,
        ),
        BlockOptionFactory.toggle(
          id: 'multiplier_escalation',
          name: 'Escalation Steps',
          description: 'Distinct audio for each multiplier level',
          defaultValue: true,
          group: 'Multiplier',
          order: 71,
          visibleWhen: {'multiplier_transitions': true},
        ),

        // ═══════════════════════════════════════════════════════════════════
        // BONUS GAME TRANSITIONS
        // ═══════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'bonus_game_transitions',
          name: 'Bonus Game Transitions',
          description: 'Enable bonus game entry/exit transitions',
          defaultValue: true,
          group: 'Bonus Game',
          order: 80,
        ),
        BlockOptionFactory.toggle(
          id: 'bonus_level_transitions',
          name: 'Level Transitions',
          description: 'Transitions between bonus game levels',
          defaultValue: true,
          group: 'Bonus Game',
          order: 81,
          visibleWhen: {'bonus_game_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'bonus_pick_transitions',
          name: 'Pick Transitions',
          description: 'Audio for pick selections in bonus',
          defaultValue: true,
          group: 'Bonus Game',
          order: 82,
          visibleWhen: {'bonus_game_transitions': true},
        ),

        // ═══════════════════════════════════════════════════════════════════
        // GAMBLING TRANSITIONS
        // ═══════════════════════════════════════════════════════════════════
        BlockOptionFactory.toggle(
          id: 'gambling_transitions',
          name: 'Gamble Transitions',
          description: 'Enable gamble feature transitions',
          defaultValue: true,
          group: 'Gambling',
          order: 90,
        ),
        BlockOptionFactory.toggle(
          id: 'gambling_reveal_transitions',
          name: 'Reveal Transitions',
          description: 'Suspense and reveal audio',
          defaultValue: true,
          group: 'Gambling',
          order: 91,
          visibleWhen: {'gambling_transitions': true},
        ),
        BlockOptionFactory.toggle(
          id: 'gambling_streak_transitions',
          name: 'Streak Transitions',
          description: 'Win streak escalation audio',
          defaultValue: true,
          group: 'Gambling',
          order: 92,
          visibleWhen: {'gambling_transitions': true},
        ),
      ];

  @override
  List<BlockDependency> createDependencies() => [
        // Modifies music states block behavior
        BlockDependency.modifies(
          source: id,
          target: 'music_states',
          description: 'Transitions modify music state behavior',
        ),
        // Modifies win presentation block for tier transitions
        BlockDependency.modifies(
          source: id,
          target: 'win_presentation',
          description: 'Transitions modify win tier escalation',
        ),
        // Modifies jackpot block for tier reveal transitions
        BlockDependency.modifies(
          source: id,
          target: 'jackpot',
          description: 'Transitions modify jackpot tier reveals',
        ),
        // Modifies multiplier block for escalation transitions
        BlockDependency.modifies(
          source: id,
          target: 'multiplier',
          description: 'Transitions modify multiplier escalation',
        ),
        // Modifies bonus game block for level transitions
        BlockDependency.modifies(
          source: id,
          target: 'bonus_game',
          description: 'Transitions modify bonus game level flow',
        ),
        // Modifies gambling block for reveal and streak transitions
        BlockDependency.modifies(
          source: id,
          target: 'gambling',
          description: 'Transitions modify gamble reveal and streak audio',
        ),
      ];

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];

    // ═══════════════════════════════════════════════════════════════════════
    // CONTEXT TRANSITIONS
    // ═══════════════════════════════════════════════════════════════════════
    if (getOptionValue<bool>('context_transitions') == true) {
      // Base ↔ Free Spins
      if (getOptionValue<bool>('base_to_freespins') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'CONTEXT_BASE_TO_FS',
            description: 'Transition from base game to free spins',
            bus: 'music',
            priority: 85,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'CONTEXT_BASE_TO_FS_STINGER',
            description: 'Stinger for base to free spins transition',
            bus: 'sfx',
            priority: 86,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'MUSIC_CROSSFADE_BASE_TO_FS',
            description: 'Music crossfade: base → free spins',
            bus: 'music',
            priority: 84,
            sourceBlockId: id,
          ),
        ]);
      }

      if (getOptionValue<bool>('freespins_to_base') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'CONTEXT_FS_TO_BASE',
            description: 'Transition from free spins to base game',
            bus: 'music',
            priority: 80,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'CONTEXT_FS_TO_BASE_STINGER',
            description: 'Stinger for free spins to base transition',
            bus: 'sfx',
            priority: 81,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'MUSIC_CROSSFADE_FS_TO_BASE',
            description: 'Music crossfade: free spins → base',
            bus: 'music',
            priority: 79,
            sourceBlockId: id,
          ),
        ]);
      }

      // Base ↔ Bonus
      if (getOptionValue<bool>('base_to_bonus') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'CONTEXT_BASE_TO_BONUS',
            description: 'Transition from base game to bonus round',
            bus: 'music',
            priority: 88,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'CONTEXT_BASE_TO_BONUS_STINGER',
            description: 'Stinger for base to bonus transition',
            bus: 'sfx',
            priority: 89,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'MUSIC_CROSSFADE_BASE_TO_BONUS',
            description: 'Music crossfade: base → bonus',
            bus: 'music',
            priority: 87,
            sourceBlockId: id,
          ),
        ]);
      }

      if (getOptionValue<bool>('bonus_to_base') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'CONTEXT_BONUS_TO_BASE',
            description: 'Transition from bonus round to base game',
            bus: 'music',
            priority: 78,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'CONTEXT_BONUS_TO_BASE_STINGER',
            description: 'Stinger for bonus to base transition',
            bus: 'sfx',
            priority: 79,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'MUSIC_CROSSFADE_BONUS_TO_BASE',
            description: 'Music crossfade: bonus → base',
            bus: 'music',
            priority: 77,
            sourceBlockId: id,
          ),
        ]);
      }

      // Base ↔ Hold & Win
      if (getOptionValue<bool>('base_to_holdwin') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'CONTEXT_BASE_TO_HOLDWIN',
            description: 'Transition from base game to Hold & Win',
            bus: 'music',
            priority: 87,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'CONTEXT_BASE_TO_HOLDWIN_STINGER',
            description: 'Stinger for base to Hold & Win transition',
            bus: 'sfx',
            priority: 88,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'MUSIC_CROSSFADE_BASE_TO_HOLDWIN',
            description: 'Music crossfade: base → Hold & Win',
            bus: 'music',
            priority: 86,
            sourceBlockId: id,
          ),
        ]);
      }

      if (getOptionValue<bool>('holdwin_to_base') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'CONTEXT_HOLDWIN_TO_BASE',
            description: 'Transition from Hold & Win to base game',
            bus: 'music',
            priority: 76,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'CONTEXT_HOLDWIN_TO_BASE_STINGER',
            description: 'Stinger for Hold & Win to base transition',
            bus: 'sfx',
            priority: 77,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'MUSIC_CROSSFADE_HOLDWIN_TO_BASE',
            description: 'Music crossfade: Hold & Win → base',
            bus: 'music',
            priority: 75,
            sourceBlockId: id,
          ),
        ]);
      }

      // Base ↔ Big Win
      if (getOptionValue<bool>('base_to_bigwin') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'CONTEXT_BASE_TO_BIGWIN',
            description: 'Transition to big win celebration',
            bus: 'music',
            priority: 90,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'CONTEXT_BIGWIN_INTRO_STINGER',
            description: 'Intro stinger for big win celebration',
            bus: 'sfx',
            priority: 92,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'MUSIC_DUCK_FOR_BIGWIN',
            description: 'Duck base music for big win',
            bus: 'music',
            priority: 89,
            sourceBlockId: id,
          ),
        ]);
      }

      if (getOptionValue<bool>('bigwin_to_base') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'CONTEXT_BIGWIN_TO_BASE',
            description: 'Transition from big win to base',
            bus: 'music',
            priority: 74,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'CONTEXT_BIGWIN_OUTRO_STINGER',
            description: 'Outro stinger after big win',
            bus: 'sfx',
            priority: 75,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'MUSIC_RESTORE_AFTER_BIGWIN',
            description: 'Restore base music after big win',
            bus: 'music',
            priority: 73,
            sourceBlockId: id,
          ),
        ]);
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MUSIC TRANSITIONS
    // ═══════════════════════════════════════════════════════════════════════
    if (getOptionValue<bool>('music_crossfades') == true) {
      stages.addAll([
        GeneratedStage(
          name: 'MUSIC_CROSSFADE_START',
          description: 'Start music crossfade',
          bus: 'music',
          priority: 60,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'MUSIC_CROSSFADE_END',
          description: 'End music crossfade',
          bus: 'music',
          priority: 60,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'MUSIC_FADE_OUT',
          description: 'Fade out current music',
          bus: 'music',
          priority: 58,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'MUSIC_FADE_IN',
          description: 'Fade in new music',
          bus: 'music',
          priority: 62,
          sourceBlockId: id,
        ),
      ]);
    }

    if (getOptionValue<bool>('music_layer_transitions') == true) {
      // ALE Layer transitions L1-L5
      for (int fromLevel = 1; fromLevel <= 5; fromLevel++) {
        for (int toLevel = 1; toLevel <= 5; toLevel++) {
          if (fromLevel != toLevel) {
            final direction = toLevel > fromLevel ? 'UP' : 'DOWN';
            stages.add(GeneratedStage(
              name: 'MUSIC_LAYER_L${fromLevel}_TO_L$toLevel',
              description: 'Layer transition: L$fromLevel → L$toLevel ($direction)',
              bus: 'music',
              priority: 55 + (toLevel > fromLevel ? 5 : 0),
              sourceBlockId: id,
            ));
          }
        }
      }

      stages.addAll([
        GeneratedStage(
          name: 'MUSIC_LAYER_STEP_UP',
          description: 'Step up one layer level',
          bus: 'music',
          priority: 56,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'MUSIC_LAYER_STEP_DOWN',
          description: 'Step down one layer level',
          bus: 'music',
          priority: 54,
          sourceBlockId: id,
        ),
      ]);
    }

    if (getOptionValue<bool>('music_stingers') == true) {
      stages.addAll([
        GeneratedStage(
          name: 'TRANSITION_STINGER_SOFT',
          description: 'Soft transition stinger',
          bus: 'sfx',
          priority: 65,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'TRANSITION_STINGER_MEDIUM',
          description: 'Medium transition stinger',
          bus: 'sfx',
          priority: 68,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'TRANSITION_STINGER_HARD',
          description: 'Hard/impactful transition stinger',
          bus: 'sfx',
          priority: 72,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'TRANSITION_WHOOSH',
          description: 'Whoosh sound for transitions',
          bus: 'sfx',
          priority: 64,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'TRANSITION_SHIMMER',
          description: 'Shimmer/sparkle transition sound',
          bus: 'sfx',
          priority: 63,
          sourceBlockId: id,
        ),
      ]);
    }

    if (getOptionValue<bool>('beat_sync') == true) {
      stages.addAll([
        GeneratedStage(
          name: 'BEAT_SYNC_READY',
          description: 'Ready to sync on next beat',
          bus: 'music',
          priority: 50,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'BEAT_SYNC_EXECUTE',
          description: 'Execute beat-synced transition',
          bus: 'music',
          priority: 52,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'BAR_SYNC_READY',
          description: 'Ready to sync on next bar',
          bus: 'music',
          priority: 51,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'BAR_SYNC_EXECUTE',
          description: 'Execute bar-synced transition',
          bus: 'music',
          priority: 53,
          sourceBlockId: id,
        ),
      ]);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ANTICIPATION TRANSITIONS
    // ═══════════════════════════════════════════════════════════════════════
    if (getOptionValue<bool>('anticipation_transitions') == true) {
      final levels = getOptionValue<int>('anticipation_levels') ?? 4;

      stages.addAll([
        GeneratedStage(
          name: 'ANTICIPATION_BUILD_START',
          description: 'Start anticipation build-up',
          bus: 'music',
          priority: 75,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'ANTICIPATION_BUILD_END',
          description: 'End anticipation build-up',
          bus: 'music',
          priority: 76,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'ANTICIPATION_RESOLVE_WIN',
          description: 'Resolve anticipation with win',
          bus: 'sfx',
          priority: 80,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'ANTICIPATION_RESOLVE_MISS',
          description: 'Resolve anticipation with miss',
          bus: 'sfx',
          priority: 70,
          sourceBlockId: id,
        ),
      ]);

      // Tension levels
      for (int level = 1; level <= levels; level++) {
        stages.add(GeneratedStage(
          name: 'ANTICIPATION_TENSION_L$level',
          description: 'Anticipation tension level $level',
          bus: 'music',
          priority: 74 + level,
          sourceBlockId: id,
        ));
      }

      // Per-reel anticipation
      if (getOptionValue<bool>('anticipation_per_reel') == true) {
        for (int reel = 1; reel <= 5; reel++) {
          for (int level = 1; level <= levels; level++) {
            stages.add(GeneratedStage(
              name: 'ANTICIPATION_R${reel}_L$level',
              description: 'Reel $reel anticipation at level $level',
              bus: 'sfx',
              priority: 73 + level,
              sourceBlockId: id,
            ));
          }

          stages.addAll([
            GeneratedStage(
              name: 'ANTICIPATION_REEL_${reel}_START',
              description: 'Start anticipation on reel $reel',
              bus: 'sfx',
              priority: 74,
              sourceBlockId: id,
            ),
            GeneratedStage(
              name: 'ANTICIPATION_REEL_${reel}_END',
              description: 'End anticipation on reel $reel',
              bus: 'sfx',
              priority: 75,
              sourceBlockId: id,
            ),
          ]);
        }
      }

      // Scatter/Bonus anticipation
      if (getOptionValue<bool>('scatter_anticipation') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'ANTICIPATION_SCATTER_2',
            description: 'Anticipation with 2 scatters visible',
            bus: 'sfx',
            priority: 76,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'ANTICIPATION_SCATTER_TRIGGER',
            description: 'Anticipation when scatter trigger possible',
            bus: 'sfx',
            priority: 78,
            sourceBlockId: id,
          ),
        ]);
      }

      if (getOptionValue<bool>('bonus_anticipation') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'ANTICIPATION_BONUS_2',
            description: 'Anticipation with 2 bonus symbols visible',
            bus: 'sfx',
            priority: 76,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'ANTICIPATION_BONUS_TRIGGER',
            description: 'Anticipation when bonus trigger possible',
            bus: 'sfx',
            priority: 79,
            sourceBlockId: id,
          ),
        ]);
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WIN TIER TRANSITIONS
    // ═══════════════════════════════════════════════════════════════════════
    if (getOptionValue<bool>('win_tier_transitions') == true) {
      if (getOptionValue<bool>('win_tier_upgrade') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'WIN_TIER_UPGRADE_1_TO_2',
            description: 'Upgrade from tier 1 to tier 2',
            bus: 'sfx',
            priority: 82,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'WIN_TIER_UPGRADE_2_TO_3',
            description: 'Upgrade from tier 2 to tier 3',
            bus: 'sfx',
            priority: 84,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'WIN_TIER_UPGRADE_3_TO_4',
            description: 'Upgrade from tier 3 to tier 4',
            bus: 'sfx',
            priority: 86,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'WIN_TIER_UPGRADE_4_TO_5',
            description: 'Upgrade from tier 4 to tier 5',
            bus: 'sfx',
            priority: 88,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'WIN_TIER_UPGRADE_GENERIC',
            description: 'Generic win tier upgrade fanfare',
            bus: 'sfx',
            priority: 83,
            sourceBlockId: id,
          ),
        ]);
      }

      if (getOptionValue<bool>('rollup_acceleration') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'ROLLUP_ACCELERATE_START',
            description: 'Start rollup acceleration',
            bus: 'sfx',
            priority: 70,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'ROLLUP_ACCELERATE_PEAK',
            description: 'Peak rollup speed',
            bus: 'sfx',
            priority: 72,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'ROLLUP_PITCH_INCREASE',
            description: 'Increase rollup pitch',
            bus: 'sfx',
            priority: 68,
            sourceBlockId: id,
          ),
        ]);
      }

      stages.addAll([
        GeneratedStage(
          name: 'WIN_TO_BIGWIN_TRANSITION',
          description: 'Transition from regular win to big win',
          bus: 'sfx',
          priority: 85,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'BIGWIN_ESCALATION',
          description: 'Big win escalation to higher tier',
          bus: 'sfx',
          priority: 87,
          sourceBlockId: id,
        ),
      ]);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // UI TRANSITIONS
    // ═══════════════════════════════════════════════════════════════════════
    if (getOptionValue<bool>('ui_transitions') == true) {
      if (getOptionValue<bool>('menu_transitions') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'UI_MENU_OPEN',
            description: 'Menu panel opens',
            bus: 'ui',
            priority: 40,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'UI_MENU_CLOSE',
            description: 'Menu panel closes',
            bus: 'ui',
            priority: 40,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'UI_SETTINGS_OPEN',
            description: 'Settings panel opens',
            bus: 'ui',
            priority: 40,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'UI_SETTINGS_CLOSE',
            description: 'Settings panel closes',
            bus: 'ui',
            priority: 40,
            sourceBlockId: id,
          ),
        ]);
      }

      if (getOptionValue<bool>('paytable_transitions') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'UI_PAYTABLE_OPEN',
            description: 'Paytable/info screen opens',
            bus: 'ui',
            priority: 42,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'UI_PAYTABLE_CLOSE',
            description: 'Paytable/info screen closes',
            bus: 'ui',
            priority: 42,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'UI_PAYTABLE_PAGE_TURN',
            description: 'Page turn in paytable',
            bus: 'ui',
            priority: 38,
            pooled: true,
            sourceBlockId: id,
          ),
        ]);
      }

      if (getOptionValue<bool>('autoplay_transitions') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'UI_AUTOPLAY_START',
            description: 'Autoplay mode starts',
            bus: 'ui',
            priority: 45,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'UI_AUTOPLAY_STOP',
            description: 'Autoplay mode stops',
            bus: 'ui',
            priority: 45,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'UI_AUTOPLAY_COUNTDOWN',
            description: 'Autoplay countdown tick',
            bus: 'ui',
            priority: 35,
            pooled: true,
            sourceBlockId: id,
          ),
        ]);
      }

      if (getOptionValue<bool>('turbo_transitions') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'UI_TURBO_ON',
            description: 'Turbo mode enabled',
            bus: 'ui',
            priority: 44,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'UI_TURBO_OFF',
            description: 'Turbo mode disabled',
            bus: 'ui',
            priority: 44,
            sourceBlockId: id,
          ),
        ]);
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SPECIAL TRANSITIONS
    // ═══════════════════════════════════════════════════════════════════════
    if (getOptionValue<bool>('special_transitions') == true) {
      if (getOptionValue<bool>('jackpot_approach') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'JACKPOT_APPROACH_BUILD',
            description: 'Building tension approaching jackpot',
            bus: 'music',
            priority: 88,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'JACKPOT_APPROACH_PEAK',
            description: 'Peak tension before jackpot trigger',
            bus: 'music',
            priority: 92,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'JACKPOT_APPROACH_MISS',
            description: 'Jackpot approach but no trigger',
            bus: 'sfx',
            priority: 70,
            sourceBlockId: id,
          ),
        ]);
      }

      if (getOptionValue<bool>('near_miss_resolve') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'NEAR_MISS_RESOLVE',
            description: 'Near miss resolution (almost won)',
            bus: 'sfx',
            priority: 55,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'NEAR_MISS_SIGH',
            description: 'Disappointment cue for near miss',
            bus: 'sfx',
            priority: 50,
            sourceBlockId: id,
          ),
        ]);
      }

      if (getOptionValue<bool>('session_bookends') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'SESSION_START',
            description: 'Session/game start fanfare',
            bus: 'music',
            priority: 30,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'SESSION_END',
            description: 'Session/game end music',
            bus: 'music',
            priority: 30,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'SESSION_WELCOME_BACK',
            description: 'Welcome back returning player',
            bus: 'sfx',
            priority: 35,
            sourceBlockId: id,
          ),
        ]);
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // JACKPOT TRANSITIONS
    // ═══════════════════════════════════════════════════════════════════════
    if (getOptionValue<bool>('jackpot_transitions') == true) {
      stages.addAll([
        GeneratedStage(
          name: 'CONTEXT_BASE_TO_JACKPOT',
          description: 'Transition from base game to jackpot',
          bus: 'music',
          priority: 92,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'CONTEXT_JACKPOT_TO_BASE',
          description: 'Transition from jackpot to base game',
          bus: 'music',
          priority: 75,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'JACKPOT_TRANSITION_STINGER',
          description: 'Stinger for jackpot transitions',
          bus: 'sfx',
          priority: 93,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'MUSIC_CROSSFADE_BASE_TO_JACKPOT',
          description: 'Music crossfade: base → jackpot',
          bus: 'music',
          priority: 91,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'MUSIC_CROSSFADE_JACKPOT_TO_BASE',
          description: 'Music crossfade: jackpot → base',
          bus: 'music',
          priority: 74,
          sourceBlockId: id,
        ),
      ]);

      if (getOptionValue<bool>('jackpot_tier_transitions') == true) {
        final tiers = ['MINI', 'MINOR', 'MAJOR', 'GRAND', 'MEGA'];
        for (int i = 0; i < tiers.length - 1; i++) {
          stages.add(GeneratedStage(
            name: 'JACKPOT_TIER_${tiers[i]}_TO_${tiers[i + 1]}',
            description: 'Jackpot tier escalation: ${tiers[i]} → ${tiers[i + 1]}',
            bus: 'sfx',
            priority: 88 + i,
            sourceBlockId: id,
          ));
        }
        stages.addAll([
          GeneratedStage(
            name: 'JACKPOT_TIER_REVEAL_BUILDUP',
            description: 'Tension before jackpot tier reveal',
            bus: 'music',
            priority: 90,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'JACKPOT_TIER_REVEALED',
            description: 'Jackpot tier has been revealed',
            bus: 'sfx',
            priority: 94,
            sourceBlockId: id,
          ),
        ]);
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MULTIPLIER TRANSITIONS
    // ═══════════════════════════════════════════════════════════════════════
    if (getOptionValue<bool>('multiplier_transitions') == true) {
      stages.addAll([
        GeneratedStage(
          name: 'MULTIPLIER_ACTIVATE',
          description: 'Multiplier feature activates',
          bus: 'sfx',
          priority: 78,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'MULTIPLIER_DEACTIVATE',
          description: 'Multiplier feature deactivates',
          bus: 'sfx',
          priority: 65,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'MULTIPLIER_INCREASE',
          description: 'Multiplier value increases',
          bus: 'sfx',
          priority: 75,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'MULTIPLIER_DECREASE',
          description: 'Multiplier value decreases',
          bus: 'sfx',
          priority: 60,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'MULTIPLIER_RESET',
          description: 'Multiplier resets to base',
          bus: 'sfx',
          priority: 58,
          sourceBlockId: id,
        ),
      ]);

      if (getOptionValue<bool>('multiplier_escalation') == true) {
        // Multiplier escalation steps 2x through 10x+
        final multipliers = [2, 3, 4, 5, 6, 7, 8, 9, 10];
        for (int i = 0; i < multipliers.length - 1; i++) {
          stages.add(GeneratedStage(
            name: 'MULTIPLIER_${multipliers[i]}X_TO_${multipliers[i + 1]}X',
            description: 'Multiplier escalation: ${multipliers[i]}x → ${multipliers[i + 1]}x',
            bus: 'sfx',
            priority: 72 + (i ~/ 2),
            sourceBlockId: id,
          ));
        }
        stages.addAll([
          GeneratedStage(
            name: 'MULTIPLIER_MAX_REACHED',
            description: 'Maximum multiplier reached',
            bus: 'wins',
            priority: 82,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'MULTIPLIER_MILESTONE',
            description: 'Multiplier milestone reached (5x, 10x, etc.)',
            bus: 'sfx',
            priority: 78,
            sourceBlockId: id,
          ),
        ]);
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BONUS GAME TRANSITIONS
    // ═══════════════════════════════════════════════════════════════════════
    if (getOptionValue<bool>('bonus_game_transitions') == true) {
      stages.addAll([
        GeneratedStage(
          name: 'CONTEXT_BASE_TO_BONUS_GAME',
          description: 'Transition from base game to bonus game',
          bus: 'music',
          priority: 88,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'CONTEXT_BONUS_GAME_TO_BASE',
          description: 'Transition from bonus game to base game',
          bus: 'music',
          priority: 72,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'BONUS_GAME_INTRO_STINGER',
          description: 'Stinger for bonus game entry',
          bus: 'sfx',
          priority: 89,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'BONUS_GAME_OUTRO_STINGER',
          description: 'Stinger for bonus game exit',
          bus: 'sfx',
          priority: 73,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'MUSIC_CROSSFADE_BASE_TO_BONUS_GAME',
          description: 'Music crossfade: base → bonus game',
          bus: 'music',
          priority: 87,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'MUSIC_CROSSFADE_BONUS_GAME_TO_BASE',
          description: 'Music crossfade: bonus game → base',
          bus: 'music',
          priority: 71,
          sourceBlockId: id,
        ),
      ]);

      if (getOptionValue<bool>('bonus_level_transitions') == true) {
        for (int level = 1; level <= 5; level++) {
          if (level < 5) {
            stages.add(GeneratedStage(
              name: 'BONUS_LEVEL_${level}_TO_${level + 1}',
              description: 'Bonus level transition: $level → ${level + 1}',
              bus: 'sfx',
              priority: 80 + level,
              sourceBlockId: id,
            ));
          }
          stages.add(GeneratedStage(
            name: 'BONUS_LEVEL_$level _ENTER',
            description: 'Enter bonus game level $level',
            bus: 'sfx',
            priority: 78 + level,
            sourceBlockId: id,
          ));
        }
        stages.addAll([
          GeneratedStage(
            name: 'BONUS_FINAL_LEVEL_REACHED',
            description: 'Final bonus level reached',
            bus: 'wins',
            priority: 88,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'BONUS_LEVEL_COMPLETE',
            description: 'Bonus level completed',
            bus: 'sfx',
            priority: 82,
            sourceBlockId: id,
          ),
        ]);
      }

      if (getOptionValue<bool>('bonus_pick_transitions') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'BONUS_PICK_HOVER',
            description: 'Hovering over pick item',
            bus: 'ui',
            priority: 45,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'BONUS_PICK_SELECT',
            description: 'Pick item selected',
            bus: 'sfx',
            priority: 68,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'BONUS_PICK_REVEAL_GOOD',
            description: 'Pick reveals good item',
            bus: 'sfx',
            priority: 75,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'BONUS_PICK_REVEAL_GREAT',
            description: 'Pick reveals great item',
            bus: 'wins',
            priority: 80,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'BONUS_PICK_REVEAL_BAD',
            description: 'Pick reveals end/bad item',
            bus: 'sfx',
            priority: 65,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'BONUS_PICK_REMAINING_REVEAL',
            description: 'Remaining picks revealed',
            bus: 'sfx',
            priority: 55,
            pooled: true,
            sourceBlockId: id,
          ),
        ]);
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GAMBLING TRANSITIONS
    // ═══════════════════════════════════════════════════════════════════════
    if (getOptionValue<bool>('gambling_transitions') == true) {
      stages.addAll([
        GeneratedStage(
          name: 'CONTEXT_WIN_TO_GAMBLE',
          description: 'Transition from win to gamble feature',
          bus: 'sfx',
          priority: 68,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'CONTEXT_GAMBLE_TO_BASE',
          description: 'Transition from gamble to base game',
          bus: 'sfx',
          priority: 58,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_OFFER_POPUP',
          description: 'Gamble offer popup appears',
          bus: 'ui',
          priority: 55,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'GAMBLE_OFFER_DISMISS',
          description: 'Gamble offer dismissed',
          bus: 'ui',
          priority: 50,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'MUSIC_CROSSFADE_WIN_TO_GAMBLE',
          description: 'Music crossfade: win → gamble',
          bus: 'music',
          priority: 65,
          sourceBlockId: id,
        ),
        GeneratedStage(
          name: 'MUSIC_CROSSFADE_GAMBLE_TO_BASE',
          description: 'Music crossfade: gamble → base',
          bus: 'music',
          priority: 56,
          sourceBlockId: id,
        ),
      ]);

      if (getOptionValue<bool>('gambling_reveal_transitions') == true) {
        stages.addAll([
          GeneratedStage(
            name: 'GAMBLE_REVEAL_ANTICIPATION_BUILD',
            description: 'Tension building before gamble reveal',
            bus: 'music',
            priority: 70,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'GAMBLE_REVEAL_ANTICIPATION_PEAK',
            description: 'Peak tension before gamble reveal',
            bus: 'sfx',
            priority: 74,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'GAMBLE_REVEAL_WIN_TRANSITION',
            description: 'Transition audio for gamble win',
            bus: 'wins',
            priority: 80,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'GAMBLE_REVEAL_LOSE_TRANSITION',
            description: 'Transition audio for gamble loss',
            bus: 'sfx',
            priority: 68,
            sourceBlockId: id,
          ),
        ]);
      }

      if (getOptionValue<bool>('gambling_streak_transitions') == true) {
        for (int streak = 2; streak <= 5; streak++) {
          stages.add(GeneratedStage(
            name: 'GAMBLE_STREAK_${streak}_ESCALATION',
            description: 'Win streak $streak escalation fanfare',
            bus: 'wins',
            priority: 76 + streak,
            sourceBlockId: id,
          ));
        }
        stages.addAll([
          GeneratedStage(
            name: 'GAMBLE_STREAK_BROKEN',
            description: 'Win streak has been broken',
            bus: 'sfx',
            priority: 65,
            sourceBlockId: id,
          ),
          GeneratedStage(
            name: 'GAMBLE_STREAK_PERFECT',
            description: 'Perfect streak achieved (max rounds)',
            bus: 'wins',
            priority: 88,
            sourceBlockId: id,
          ),
        ]);
      }
    }

    return stages;
  }

  @override
  List<String> get pooledStages => [
        'UI_PAYTABLE_PAGE_TURN',
        'UI_AUTOPLAY_COUNTDOWN',
      ];

  @override
  String getBusForStage(String stageName) {
    if (stageName.startsWith('MUSIC_') ||
        (stageName.startsWith('CONTEXT_') && !stageName.contains('STINGER')) ||
        stageName.contains('BEAT_SYNC') ||
        stageName.contains('BAR_SYNC') ||
        stageName.startsWith('ANTICIPATION_BUILD') ||
        stageName.startsWith('ANTICIPATION_TENSION') ||
        (stageName.startsWith('JACKPOT_APPROACH') && !stageName.contains('MISS')) ||
        stageName.startsWith('SESSION_') ||
        stageName.contains('_ANTICIPATION_BUILD') ||
        stageName.contains('_ANTICIPATION_PEAK')) {
      return 'music';
    }
    if (stageName.startsWith('UI_') ||
        stageName.contains('_HOVER') ||
        stageName.contains('_POPUP') ||
        stageName.contains('_DISMISS')) {
      return 'ui';
    }
    if (stageName.contains('WIN_TRANSITION') ||
        stageName.contains('MAX_REACHED') ||
        stageName.contains('PERFECT') ||
        stageName.contains('FINAL_LEVEL') ||
        stageName.contains('REVEAL_GREAT')) {
      return 'wins';
    }
    return 'sfx';
  }

  @override
  int getPriorityForStage(String stageName) {
    if (stageName.contains('JACKPOT_TIER')) return 92;
    if (stageName.contains('JACKPOT')) return 90;
    if (stageName.contains('BIGWIN')) return 85;
    if (stageName.contains('TIER_UPGRADE')) return 83;
    if (stageName.contains('BONUS_FINAL')) return 88;
    if (stageName.contains('BONUS_LEVEL')) return 80;
    if (stageName.contains('MULTIPLIER_MAX')) return 82;
    if (stageName.contains('MULTIPLIER')) return 75;
    if (stageName.contains('GAMBLE_STREAK_PERFECT')) return 88;
    if (stageName.contains('GAMBLE_STREAK')) return 78;
    if (stageName.contains('GAMBLE_REVEAL')) return 72;
    if (stageName.contains('ANTICIPATION')) return 75;
    if (stageName.contains('CROSSFADE')) return 60;
    if (stageName.startsWith('UI_')) return 40;
    return 50;
  }
}
