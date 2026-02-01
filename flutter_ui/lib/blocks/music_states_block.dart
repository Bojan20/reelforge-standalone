/// MusicStatesBlock - Music States configuration for Feature Builder
///
/// Defines music contexts, layer levels, transitions, and adaptive music behavior.
/// Part of P13 Feature Builder Panel implementation.

import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';
import '../models/feature_builder/feature_block.dart';

/// Music context types (game chapters)
enum MusicContext {
  /// Base game music
  baseGame,

  /// Free spins feature music
  freeSpins,

  /// Hold & Win feature music
  holdAndWin,

  /// Bonus game music
  bonus,

  /// Big win celebration music
  bigWin,

  /// Jackpot celebration music
  jackpot,

  /// Attract/idle mode music
  attract,

  /// Gamble feature music
  gamble,

  /// Custom context
  custom,
}

/// Music layer intensity levels
enum LayerLevel {
  /// L1: Ambient, minimal
  l1,

  /// L2: Low energy
  l2,

  /// L3: Medium energy
  l3,

  /// L4: High energy
  l4,

  /// L5: Maximum intensity
  l5,
}

/// Music transition sync mode
enum TransitionSyncMode {
  /// Immediate: Transition right away
  immediate,

  /// Beat: On next beat
  beat,

  /// Bar: On next bar
  bar,

  /// Phrase: On next phrase (4 bars)
  phrase,

  /// Downbeat: On next downbeat
  downbeat,

  /// Custom: Custom grid position
  custom,
}

/// Fade curve types
enum FadeCurve {
  /// Linear fade
  linear,

  /// Ease in (slow start)
  easeIn,

  /// Ease out (slow end)
  easeOut,

  /// Ease in-out (slow both ends)
  easeInOut,

  /// S-curve (smooth)
  sCurve,

  /// Exponential (dramatic)
  exponential,

  /// Logarithmic (natural)
  logarithmic,
}

/// Context exit policy
enum ContextExitPolicy {
  /// Immediate: Stop immediately
  immediate,

  /// Fade out: Fade to silence
  fadeOut,

  /// Crossfade: Crossfade to next context
  crossfade,

  /// Complete phrase: Finish current phrase
  completePhrase,

  /// Complete bar: Finish current bar
  completeBar,

  /// Stinger: Play exit stinger then stop
  stinger,
}

/// Layer change trigger
enum LayerChangeTrigger {
  /// Win tier (small, big, mega, etc.)
  winTier,

  /// Win multiplier value
  winMultiplier,

  /// Consecutive wins count
  consecutiveWins,

  /// Consecutive losses count
  consecutiveLosses,

  /// Feature progress
  featureProgress,

  /// Cascade depth
  cascadeDepth,

  /// Balance trend
  balanceTrend,

  /// Momentum (derived signal)
  momentum,

  /// Manual/explicit
  manual,
}

/// Music States feature block
class MusicStatesBlock extends FeatureBlockBase {
  MusicStatesBlock() : super();

  @override
  String get id => 'music_states';

  @override
  String get name => 'Music States';

  @override
  String get description =>
      'Configure music contexts, layer levels, transitions, and adaptive music behavior';

  @override
  BlockCategory get category => BlockCategory.presentation;

  @override
  String get iconName => 'music_note';

  @override
  bool get canBeDisabled => true;

  @override
  int get stagePriority => 20; // Background priority

  @override
  List<BlockOption> createOptions() {
    return [
      // === CONTEXTS GROUP ===
      BlockOptionFactory.toggle(
        id: 'base_game_context',
        name: 'Base Game Context',
        description: 'Enable base game music context',
        defaultValue: true,
        group: 'Contexts',
        order: 1,
      ),
      BlockOptionFactory.toggle(
        id: 'free_spins_context',
        name: 'Free Spins Context',
        description: 'Enable free spins music context',
        defaultValue: true,
        group: 'Contexts',
        order: 2,
      ),
      BlockOptionFactory.toggle(
        id: 'hold_win_context',
        name: 'Hold & Win Context',
        description: 'Enable hold & win music context',
        defaultValue: true,
        group: 'Contexts',
        order: 3,
      ),
      BlockOptionFactory.toggle(
        id: 'bonus_context',
        name: 'Bonus Context',
        description: 'Enable bonus game music context',
        defaultValue: true,
        group: 'Contexts',
        order: 4,
      ),
      BlockOptionFactory.toggle(
        id: 'big_win_context',
        name: 'Big Win Context',
        description: 'Enable big win celebration context',
        defaultValue: true,
        group: 'Contexts',
        order: 5,
      ),
      BlockOptionFactory.toggle(
        id: 'attract_context',
        name: 'Attract Mode Context',
        description: 'Enable attract/idle mode music',
        defaultValue: false,
        group: 'Contexts',
        order: 6,
      ),

      // === LAYERS GROUP ===
      BlockOptionFactory.count(
        id: 'layer_count',
        name: 'Layer Count',
        description: 'Number of intensity layers (L1-L5)',
        min: 2,
        max: 8,
        defaultValue: 5,
        group: 'Layers',
        order: 10,
      ),
      BlockOption(
        id: 'layer_trigger',
        name: 'Layer Change Trigger',
        description: 'What triggers layer changes',
        type: BlockOptionType.dropdown,
        defaultValue: 'winTier',
        choices: LayerChangeTrigger.values
            .map((e) => OptionChoice(value: e.name, label: _formatEnumName(e.name)))
            .toList(),
        group: 'Layers',
        order: 11,
      ),
      BlockOptionFactory.toggle(
        id: 'auto_layer_escalation',
        name: 'Auto Layer Escalation',
        description: 'Automatically increase layers on wins',
        defaultValue: true,
        group: 'Layers',
        order: 12,
      ),
      BlockOptionFactory.toggle(
        id: 'auto_layer_decay',
        name: 'Auto Layer Decay',
        description: 'Automatically decrease layers on inactivity',
        defaultValue: true,
        group: 'Layers',
        order: 13,
      ),
      BlockOptionFactory.count(
        id: 'layer_decay_spins',
        name: 'Decay After Spins',
        description: 'Spins of inactivity before layer decreases',
        min: 1,
        max: 20,
        defaultValue: 5,
        group: 'Layers',
        order: 14,
      ),

      // === TRANSITIONS GROUP ===
      BlockOption(
        id: 'transition_sync_mode',
        name: 'Transition Sync Mode',
        description: 'How transitions synchronize with music',
        type: BlockOptionType.dropdown,
        defaultValue: 'bar',
        choices: TransitionSyncMode.values
            .map((e) => OptionChoice(value: e.name, label: _formatEnumName(e.name)))
            .toList(),
        group: 'Transitions',
        order: 20,
      ),
      BlockOption(
        id: 'fade_curve',
        name: 'Fade Curve',
        description: 'Volume fade curve type',
        type: BlockOptionType.dropdown,
        defaultValue: 'easeInOut',
        choices: FadeCurve.values
            .map((e) => OptionChoice(value: e.name, label: _formatEnumName(e.name)))
            .toList(),
        group: 'Transitions',
        order: 21,
      ),
      BlockOptionFactory.count(
        id: 'crossfade_duration_ms',
        name: 'Crossfade Duration (ms)',
        description: 'Duration of crossfade between contexts',
        min: 100,
        max: 5000,
        defaultValue: 1000,
        group: 'Transitions',
        order: 22,
      ),
      BlockOption(
        id: 'context_exit_policy',
        name: 'Context Exit Policy',
        description: 'How to exit a music context',
        type: BlockOptionType.dropdown,
        defaultValue: 'crossfade',
        choices: ContextExitPolicy.values
            .map((e) => OptionChoice(value: e.name, label: _formatEnumName(e.name)))
            .toList(),
        group: 'Transitions',
        order: 23,
      ),

      // === TEMPO GROUP ===
      BlockOptionFactory.count(
        id: 'base_tempo_bpm',
        name: 'Base Tempo (BPM)',
        description: 'Base tempo for synchronization',
        min: 60,
        max: 200,
        defaultValue: 120,
        group: 'Tempo',
        order: 30,
      ),
      BlockOptionFactory.toggle(
        id: 'tempo_match_game_speed',
        name: 'Match Game Speed',
        description: 'Adjust tempo based on turbo mode',
        defaultValue: false,
        group: 'Tempo',
        order: 31,
      ),
      BlockOptionFactory.count(
        id: 'beats_per_bar',
        name: 'Beats per Bar',
        description: 'Time signature denominator',
        min: 2,
        max: 8,
        defaultValue: 4,
        group: 'Tempo',
        order: 32,
      ),
      BlockOptionFactory.count(
        id: 'bars_per_phrase',
        name: 'Bars per Phrase',
        description: 'Bars in a musical phrase',
        min: 2,
        max: 16,
        defaultValue: 4,
        group: 'Tempo',
        order: 33,
      ),

      // === STINGERS GROUP ===
      BlockOptionFactory.toggle(
        id: 'use_entry_stingers',
        name: 'Entry Stingers',
        description: 'Play stingers when entering contexts',
        defaultValue: true,
        group: 'Stingers',
        order: 40,
      ),
      BlockOptionFactory.toggle(
        id: 'use_exit_stingers',
        name: 'Exit Stingers',
        description: 'Play stingers when exiting contexts',
        defaultValue: false,
        group: 'Stingers',
        order: 41,
      ),
      BlockOptionFactory.toggle(
        id: 'use_layer_stingers',
        name: 'Layer Stingers',
        description: 'Play stingers on layer changes',
        defaultValue: false,
        group: 'Stingers',
        order: 42,
      ),

      // === BIG WIN MUSIC ===
      BlockOptionFactory.toggle(
        id: 'big_win_music_override',
        name: 'Big Win Music Override',
        description: 'Override context music during big wins',
        defaultValue: true,
        group: 'Big Win',
        order: 50,
      ),
      BlockOptionFactory.count(
        id: 'big_win_threshold_x',
        name: 'Big Win Threshold (x bet)',
        description: 'Multiplier threshold for big win music',
        min: 5,
        max: 100,
        defaultValue: 20,
        group: 'Big Win',
        order: 51,
      ),
      BlockOptionFactory.toggle(
        id: 'big_win_escalation',
        name: 'Big Win Escalation',
        description: 'Escalate music during big win rollup',
        defaultValue: true,
        group: 'Big Win',
        order: 52,
      ),

      // === DUCKING ===
      BlockOptionFactory.toggle(
        id: 'duck_on_wins',
        name: 'Duck on Wins',
        description: 'Lower music volume during win presentation',
        defaultValue: true,
        group: 'Ducking',
        order: 60,
      ),
      BlockOptionFactory.percentage(
        id: 'duck_amount',
        name: 'Duck Amount (%)',
        description: 'Volume reduction when ducking',
        defaultValue: 30.0,
        group: 'Ducking',
        order: 61,
      ),
      BlockOptionFactory.count(
        id: 'duck_attack_ms',
        name: 'Duck Attack (ms)',
        description: 'Time to reach ducked level',
        min: 10,
        max: 500,
        defaultValue: 100,
        group: 'Ducking',
        order: 62,
      ),
      BlockOptionFactory.count(
        id: 'duck_release_ms',
        name: 'Duck Release (ms)',
        description: 'Time to return from ducked level',
        min: 100,
        max: 2000,
        defaultValue: 500,
        group: 'Ducking',
        order: 63,
      ),
    ];
  }

  /// Format enum name for display (camelCase to Title Case)
  static String _formatEnumName(String name) {
    final result = StringBuffer();
    for (var i = 0; i < name.length; i++) {
      final char = name[i];
      if (i == 0) {
        result.write(char.toUpperCase());
      } else if (char == char.toUpperCase() && char != char.toLowerCase()) {
        result.write(' ');
        result.write(char);
      } else {
        result.write(char);
      }
    }
    return result.toString();
  }

  @override
  List<BlockDependency> createDependencies() {
    return [
      // Music states work with most features
      BlockDependency.modifies(
        source: id,
        target: 'free_spins',
        description: 'Provides dedicated free spins music context',
      ),
      BlockDependency.modifies(
        source: id,
        target: 'hold_and_win',
        description: 'Provides dedicated hold & win music context',
      ),
      BlockDependency.modifies(
        source: id,
        target: 'win_presentation',
        description: 'Music responds to win tiers',
      ),
      BlockDependency.modifies(
        source: id,
        target: 'cascades',
        description: 'Music layers can respond to cascade depth',
      ),
    ];
  }

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];

    // Base game context stages
    if (getOptionValue<bool>('base_game_context') ?? true) {
      stages.addAll([
        GeneratedStage(
          name: 'MUSIC_BASE_ENTER',
          description: 'Enter base game music context',
          bus: 'music',
          priority: 10,
          sourceBlockId: id,
          category: 'music',
        ),
        GeneratedStage(
          name: 'MUSIC_BASE_EXIT',
          description: 'Exit base game music context',
          bus: 'music',
          priority: 10,
          sourceBlockId: id,
          category: 'music',
        ),
        GeneratedStage(
          name: 'MUSIC_BASE_LOOP',
          description: 'Base game music loop',
          bus: 'music',
          priority: 5,
          looping: true,
          sourceBlockId: id,
          category: 'music',
        ),
      ]);
    }

    // Free spins context stages
    if (getOptionValue<bool>('free_spins_context') ?? true) {
      stages.addAll([
        GeneratedStage(
          name: 'MUSIC_FS_ENTER',
          description: 'Enter free spins music context',
          bus: 'music',
          priority: 60,
          sourceBlockId: id,
          category: 'music',
        ),
        GeneratedStage(
          name: 'MUSIC_FS_EXIT',
          description: 'Exit free spins music context',
          bus: 'music',
          priority: 60,
          sourceBlockId: id,
          category: 'music',
        ),
        GeneratedStage(
          name: 'MUSIC_FS_LOOP',
          description: 'Free spins music loop',
          bus: 'music',
          priority: 55,
          looping: true,
          sourceBlockId: id,
          category: 'music',
        ),
      ]);
    }

    // Hold & Win context stages
    if (getOptionValue<bool>('hold_win_context') ?? true) {
      stages.addAll([
        GeneratedStage(
          name: 'MUSIC_HOLD_ENTER',
          description: 'Enter hold & win music context',
          bus: 'music',
          priority: 65,
          sourceBlockId: id,
          category: 'music',
        ),
        GeneratedStage(
          name: 'MUSIC_HOLD_EXIT',
          description: 'Exit hold & win music context',
          bus: 'music',
          priority: 65,
          sourceBlockId: id,
          category: 'music',
        ),
        GeneratedStage(
          name: 'MUSIC_HOLD_LOOP',
          description: 'Hold & win music loop',
          bus: 'music',
          priority: 60,
          looping: true,
          sourceBlockId: id,
          category: 'music',
        ),
      ]);
    }

    // Bonus context stages
    if (getOptionValue<bool>('bonus_context') ?? true) {
      stages.addAll([
        GeneratedStage(
          name: 'MUSIC_BONUS_ENTER',
          description: 'Enter bonus game music context',
          bus: 'music',
          priority: 70,
          sourceBlockId: id,
          category: 'music',
        ),
        GeneratedStage(
          name: 'MUSIC_BONUS_EXIT',
          description: 'Exit bonus game music context',
          bus: 'music',
          priority: 70,
          sourceBlockId: id,
          category: 'music',
        ),
        GeneratedStage(
          name: 'MUSIC_BONUS_LOOP',
          description: 'Bonus game music loop',
          bus: 'music',
          priority: 65,
          looping: true,
          sourceBlockId: id,
          category: 'music',
        ),
      ]);
    }

    // Big win context stages
    if (getOptionValue<bool>('big_win_context') ?? true) {
      stages.addAll([
        GeneratedStage(
          name: 'MUSIC_BIG_WIN_ENTER',
          description: 'Enter big win celebration context',
          bus: 'music',
          priority: 80,
          sourceBlockId: id,
          category: 'music',
        ),
        GeneratedStage(
          name: 'MUSIC_BIG_WIN_EXIT',
          description: 'Exit big win celebration context',
          bus: 'music',
          priority: 80,
          sourceBlockId: id,
          category: 'music',
        ),
        GeneratedStage(
          name: 'MUSIC_BIG_WIN_LOOP',
          description: 'Big win celebration music loop',
          bus: 'music',
          priority: 75,
          looping: true,
          sourceBlockId: id,
          category: 'music',
        ),
      ]);
    }

    // Attract mode context stages
    if (getOptionValue<bool>('attract_context') ?? false) {
      stages.addAll([
        GeneratedStage(
          name: 'MUSIC_ATTRACT_ENTER',
          description: 'Enter attract mode music context',
          bus: 'music',
          priority: 5,
          sourceBlockId: id,
          category: 'music',
        ),
        GeneratedStage(
          name: 'MUSIC_ATTRACT_EXIT',
          description: 'Exit attract mode music context',
          bus: 'music',
          priority: 5,
          sourceBlockId: id,
          category: 'music',
        ),
        GeneratedStage(
          name: 'MUSIC_ATTRACT_LOOP',
          description: 'Attract mode music loop',
          bus: 'music',
          priority: 3,
          looping: true,
          sourceBlockId: id,
          category: 'music',
        ),
      ]);
    }

    // Layer change stages
    final layerCount = getOptionValue<int>('layer_count') ?? 5;
    for (var i = 1; i <= layerCount; i++) {
      stages.add(GeneratedStage(
        name: 'MUSIC_LAYER_L$i',
        description: 'Music layer $i active',
        bus: 'music',
        priority: 10 + i,
        sourceBlockId: id,
        category: 'music',
      ));
    }

    // Stinger stages
    if (getOptionValue<bool>('use_entry_stingers') ?? true) {
      stages.add(GeneratedStage(
        name: 'MUSIC_STINGER_ENTRY',
        description: 'Context entry stinger',
        bus: 'music',
        priority: 90,
        sourceBlockId: id,
        category: 'music',
      ));
    }

    if (getOptionValue<bool>('use_exit_stingers') ?? false) {
      stages.add(GeneratedStage(
        name: 'MUSIC_STINGER_EXIT',
        description: 'Context exit stinger',
        bus: 'music',
        priority: 90,
        sourceBlockId: id,
        category: 'music',
      ));
    }

    if (getOptionValue<bool>('use_layer_stingers') ?? false) {
      stages.add(GeneratedStage(
        name: 'MUSIC_STINGER_LAYER_UP',
        description: 'Layer increase stinger',
        bus: 'music',
        priority: 50,
        sourceBlockId: id,
        category: 'music',
      ));
      stages.add(GeneratedStage(
        name: 'MUSIC_STINGER_LAYER_DOWN',
        description: 'Layer decrease stinger',
        bus: 'music',
        priority: 50,
        sourceBlockId: id,
        category: 'music',
      ));
    }

    return stages;
  }

  @override
  List<String> get pooledStages => []; // Music stages are not pooled

  @override
  String getBusForStage(String stageName) => 'music';

  @override
  int getPriorityForStage(String stageName) {
    if (stageName.contains('BIG_WIN')) return 80;
    if (stageName.contains('BONUS')) return 70;
    if (stageName.contains('HOLD')) return 65;
    if (stageName.contains('FS')) return 60;
    if (stageName.contains('STINGER')) return 90;
    if (stageName.contains('ATTRACT')) return 5;
    return 10; // Base music
  }
}
