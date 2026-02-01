/// WinPresentationBlock - Win Presentation configuration for Feature Builder
///
/// Defines win tiers, rollup mechanics, line win presentation, and big win celebrations.
/// Part of P13 Feature Builder Panel implementation.

import '../models/feature_block_models.dart';

/// Win tier system type
enum WinTierSystem {
  /// Simple: Small, Big, Mega
  simple,

  /// Standard: Small, Big, Super, Mega, Epic, Ultra
  standard,

  /// Extended: 8+ tiers with custom thresholds
  extended,

  /// Dynamic: Tiers based on relative win size
  dynamic,
}

/// Rollup style for win counter
enum RollupStyle {
  /// Traditional: Linear increment
  linear,

  /// Accelerating: Starts slow, speeds up
  accelerating,

  /// Decelerating: Starts fast, slows down
  decelerating,

  /// Logarithmic: Fast at start, very slow at end
  logarithmic,

  /// Stepped: Increments in chunks
  stepped,

  /// Slot machine style: Digit by digit RTL
  slotMachine,
}

/// Line win presentation style
enum LineWinStyle {
  /// Sequential: One line at a time
  sequential,

  /// Grouped: Similar wins together
  grouped,

  /// Simultaneous: All lines at once
  simultaneous,

  /// Priority: Biggest wins first
  priorityBased,

  /// Animated: Flying symbols to total
  animated,
}

/// Big win celebration level
enum BigWinCelebration {
  /// None: No special celebration
  none,

  /// Simple: Just the plaque
  simple,

  /// Standard: Plaque with particles
  standard,

  /// Elaborate: Full screen takeover
  elaborate,

  /// Epic: Extended celebration with multiple phases
  epic,
}

/// Win symbol highlight style
enum SymbolHighlightStyle {
  /// Glow: Soft glow around symbols
  glow,

  /// Pulse: Pulsing animation
  pulse,

  /// Frame: Animated frame around symbols
  frame,

  /// Particles: Particle effects on symbols
  particles,

  /// Bounce: Symbols bounce in place
  bounce,

  /// Spin: Symbols spin/rotate
  spin,
}

/// Win Presentation feature block
class WinPresentationBlock extends FeatureBlockBase {
  WinPresentationBlock() : super();

  @override
  String get id => 'win_presentation';

  @override
  String get name => 'Win Presentation';

  @override
  String get description =>
      'Configure win tiers, rollup mechanics, line win presentation, and big win celebrations';

  @override
  BlockCategory get category => BlockCategory.presentation;

  @override
  String get iconName => 'emoji_events';

  @override
  bool get canBeDisabled => false; // Always needed

  @override
  int get stagePriority => 50; // Medium-high priority

  @override
  List<BlockOption> createOptions() {
    return [
      // === WIN TIERS GROUP ===
      BlockOptionFactory.dropdown(
        id: 'tier_system',
        name: 'Win Tier System',
        description: 'How win tiers are organized',
        defaultValue: WinTierSystem.standard.name,
        choices: WinTierSystem.values.map((e) => OptionChoice(value: e.name, label: e.name)).toList(),
        group: 'Win Tiers',
      ),
      BlockOptionFactory.count(
        id: 'tier_count',
        name: 'Number of Tiers',
        description: 'How many win tiers (for extended system)',
        defaultValue: 6,
        min: 3,
        max: 10,
        group: 'Win Tiers',
      ),
      BlockOptionFactory.range(
        id: 'small_win_threshold',
        name: 'Small Win Threshold',
        description: 'Minimum multiplier for small win',
        defaultValue: 1.0,
        min: 0.5,
        max: 5.0,
        group: 'Win Tiers',
      ),
      BlockOptionFactory.range(
        id: 'big_win_threshold',
        name: 'Big Win Threshold',
        description: 'Multiplier threshold for big win',
        defaultValue: 10.0,
        min: 5.0,
        max: 25.0,
        group: 'Win Tiers',
      ),
      BlockOptionFactory.range(
        id: 'super_win_threshold',
        name: 'Super Win Threshold',
        description: 'Multiplier threshold for super win',
        defaultValue: 25.0,
        min: 15.0,
        max: 50.0,
        group: 'Win Tiers',
      ),
      BlockOptionFactory.range(
        id: 'mega_win_threshold',
        name: 'Mega Win Threshold',
        description: 'Multiplier threshold for mega win',
        defaultValue: 50.0,
        min: 30.0,
        max: 100.0,
        group: 'Win Tiers',
      ),
      BlockOptionFactory.range(
        id: 'epic_win_threshold',
        name: 'Epic Win Threshold',
        description: 'Multiplier threshold for epic win',
        defaultValue: 100.0,
        min: 50.0,
        max: 200.0,
        group: 'Win Tiers',
      ),
      BlockOptionFactory.range(
        id: 'ultra_win_threshold',
        name: 'Ultra Win Threshold',
        description: 'Multiplier threshold for ultra win',
        defaultValue: 200.0,
        min: 100.0,
        max: 500.0,
        group: 'Win Tiers',
      ),

      // === ROLLUP GROUP ===
      BlockOptionFactory.dropdown(
        id: 'rollup_style',
        name: 'Rollup Style',
        description: 'How the win counter animates',
        defaultValue: RollupStyle.slotMachine.name,
        choices: RollupStyle.values.map((e) => OptionChoice(value: e.name, label: e.name)).toList(),
        group: 'Rollup',
      ),
      BlockOptionFactory.toggle(
        id: 'rollup_enabled',
        name: 'Enable Rollup',
        description: 'Animate win counter',
        defaultValue: true,
        group: 'Rollup',
      ),
      BlockOptionFactory.toggle(
        id: 'rollup_skip_small',
        name: 'Skip Small Win Rollup',
        description: 'Instant display for small wins',
        defaultValue: true,
        group: 'Rollup',
      ),
      BlockOptionFactory.count(
        id: 'rollup_base_duration',
        name: 'Base Rollup Duration (ms)',
        description: 'Base duration for rollup animation',
        defaultValue: 1500,
        min: 500,
        max: 5000,
        group: 'Rollup',
      ),
      BlockOptionFactory.toggle(
        id: 'rollup_scale_with_win',
        name: 'Scale Duration with Win Size',
        description: 'Larger wins have longer rollup',
        defaultValue: true,
        group: 'Rollup',
      ),
      BlockOptionFactory.count(
        id: 'rollup_max_duration',
        name: 'Max Rollup Duration (ms)',
        description: 'Maximum rollup duration',
        defaultValue: 20000,
        min: 5000,
        max: 60000,
        group: 'Rollup',
      ),
      BlockOptionFactory.count(
        id: 'rollup_tick_rate_base',
        name: 'Base Tick Rate (per second)',
        description: 'Base number of rollup ticks per second',
        defaultValue: 15,
        min: 5,
        max: 30,
        group: 'Rollup',
      ),
      BlockOptionFactory.toggle(
        id: 'rollup_volume_escalation',
        name: 'Rollup Volume Escalation',
        description: 'Volume increases during rollup',
        defaultValue: true,
        group: 'Rollup',
      ),
      BlockOptionFactory.toggle(
        id: 'rollup_pitch_escalation',
        name: 'Rollup Pitch Escalation',
        description: 'Pitch increases during rollup',
        defaultValue: false,
        group: 'Rollup',
      ),

      // === LINE WIN PRESENTATION GROUP ===
      BlockOptionFactory.dropdown(
        id: 'line_win_style',
        name: 'Line Win Style',
        description: 'How line wins are presented',
        defaultValue: LineWinStyle.sequential.name,
        choices: LineWinStyle.values.map((e) => OptionChoice(value: e.name, label: e.name)).toList(),
        group: 'Line Wins',
      ),
      BlockOptionFactory.count(
        id: 'line_win_duration',
        name: 'Line Win Duration (ms)',
        description: 'How long each line win is shown',
        defaultValue: 1500,
        min: 500,
        max: 5000,
        group: 'Line Wins',
      ),
      BlockOptionFactory.count(
        id: 'max_lines_to_show',
        name: 'Max Lines to Show',
        description: 'Maximum number of line wins to display individually',
        defaultValue: 5,
        min: 1,
        max: 20,
        group: 'Line Wins',
      ),
      BlockOptionFactory.toggle(
        id: 'show_line_amounts',
        name: 'Show Line Amounts',
        description: 'Display win amount for each line',
        defaultValue: true,
        group: 'Line Wins',
      ),
      BlockOptionFactory.toggle(
        id: 'line_audio_per_line',
        name: 'Audio Per Line',
        description: 'Play sound for each line win',
        defaultValue: true,
        group: 'Line Wins',
      ),

      // === SYMBOL HIGHLIGHTS GROUP ===
      BlockOptionFactory.dropdown(
        id: 'highlight_style',
        name: 'Symbol Highlight Style',
        description: 'How winning symbols are highlighted',
        defaultValue: SymbolHighlightStyle.glow.name,
        choices: SymbolHighlightStyle.values.map((e) => OptionChoice(value: e.name, label: e.name)).toList(),
        group: 'Symbol Highlights',
      ),
      BlockOptionFactory.toggle(
        id: 'highlight_winning_symbols',
        name: 'Highlight Winning Symbols',
        description: 'Visually highlight winning symbol positions',
        defaultValue: true,
        group: 'Symbol Highlights',
      ),
      BlockOptionFactory.count(
        id: 'highlight_duration',
        name: 'Highlight Duration (ms)',
        description: 'How long symbols stay highlighted',
        defaultValue: 1000,
        min: 250,
        max: 3000,
        group: 'Symbol Highlights',
      ),
      BlockOptionFactory.toggle(
        id: 'symbol_audio_on_highlight',
        name: 'Audio on Symbol Highlight',
        description: 'Play sound when symbols highlight',
        defaultValue: true,
        group: 'Symbol Highlights',
      ),

      // === BIG WIN CELEBRATION GROUP ===
      BlockOptionFactory.dropdown(
        id: 'big_win_celebration',
        name: 'Big Win Celebration Level',
        description: 'How elaborate big win celebrations are',
        defaultValue: BigWinCelebration.standard.name,
        choices: BigWinCelebration.values.map((e) => OptionChoice(value: e.name, label: e.name)).toList(),
        group: 'Big Win Celebration',
      ),
      BlockOptionFactory.toggle(
        id: 'show_win_plaque',
        name: 'Show Win Plaque',
        description: 'Display tier plaque (BIG WIN!, MEGA WIN!, etc.)',
        defaultValue: true,
        group: 'Big Win Celebration',
      ),
      BlockOptionFactory.dropdown(
        id: 'plaque_animation_style',
        name: 'Plaque Animation Style',
        description: 'How the win plaque animates in',
        defaultValue: 'scale_bounce',
        choices: [
          OptionChoice(value: 'fade_in', label: 'Fade In'),
          OptionChoice(value: 'scale_bounce', label: 'Scale Bounce'),
          OptionChoice(value: 'slide_down', label: 'Slide Down'),
          OptionChoice(value: 'explode_in', label: 'Explode In'),
          OptionChoice(value: 'spiral_in', label: 'Spiral In'),
        ],
        group: 'Big Win Celebration',
      ),
      BlockOptionFactory.toggle(
        id: 'coin_shower',
        name: 'Coin Shower Effect',
        description: 'Show falling coins during big wins',
        defaultValue: true,
        group: 'Big Win Celebration',
      ),
      BlockOptionFactory.toggle(
        id: 'screen_flash',
        name: 'Screen Flash Effect',
        description: 'Flash screen on big win reveal',
        defaultValue: true,
        group: 'Big Win Celebration',
      ),
      BlockOptionFactory.toggle(
        id: 'celebration_loop_music',
        name: 'Loop Celebration Music',
        description: 'Play looping music during big win celebration',
        defaultValue: true,
        group: 'Big Win Celebration',
      ),

      // === AUDIO GROUP ===
      BlockOptionFactory.toggle(
        id: 'win_eval_audio',
        name: 'Win Eval Audio',
        description: 'Play audio during win evaluation',
        defaultValue: true,
        group: 'Audio',
      ),
      BlockOptionFactory.toggle(
        id: 'tier_specific_audio',
        name: 'Tier-Specific Audio',
        description: 'Different audio per win tier',
        defaultValue: true,
        group: 'Audio',
      ),
      BlockOptionFactory.toggle(
        id: 'duck_base_music',
        name: 'Duck Base Music',
        description: 'Lower base music during big wins',
        defaultValue: true,
        group: 'Audio',
      ),
      BlockOptionFactory.range(
        id: 'duck_amount',
        name: 'Duck Amount (dB)',
        description: 'How much to duck base music',
        defaultValue: -12.0,
        min: -24.0,
        max: -3.0,
        group: 'Audio',
      ),
    ];
  }

  @override
  List<BlockDependency> createDependencies() {
    return [
      // Requires game core for bet amount calculations
      BlockDependency.requires(
        source: id,
        target: 'game_core',
        description: 'Needs bet amount for tier calculations',
      ),
      // Cascades modify win presentation (multipliers affect tier)
      BlockDependency.modifies(
        source: 'cascades',
        target: id,
        description: 'Cascade multipliers affect win tier',
      ),
      // Free spins modify win presentation
      BlockDependency.modifies(
        source: 'free_spins',
        target: id,
        description: 'Free spin multipliers affect win tier',
      ),
      // Collectors modify win presentation
      BlockDependency.modifies(
        source: 'collector',
        target: id,
        description: 'Collected values may affect presentation',
      ),
    ];
  }

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];
    final tierSystem =
        WinTierSystem.values.byName(getOptionValue('tier_system') as String);
    final tierCount = getOptionValue('tier_count') as int;
    final rollupEnabled = getOptionValue('rollup_enabled') as bool;
    final tierSpecificAudio = getOptionValue('tier_specific_audio') as bool;
    final highlightSymbols = getOptionValue('highlight_winning_symbols') as bool;
    final lineAudioPerLine = getOptionValue('line_audio_per_line') as bool;
    final celebrationLoop = getOptionValue('celebration_loop_music') as bool;

    // === WIN EVALUATION STAGES ===
    stages.add(GeneratedStage(
      name: 'WIN_EVAL',
      description: 'Win evaluation phase',
      bus: 'sfx',
      priority: 55,
      sourceBlockId: id,
    ));

    // === SYMBOL HIGHLIGHT STAGES ===
    if (highlightSymbols) {
      stages.add(GeneratedStage(
        name: 'WIN_SYMBOL_HIGHLIGHT',
        description: 'Generic symbol highlight',
        bus: 'sfx',
        priority: 50,
        pooled: true, // Rapid-fire for multiple symbols
        sourceBlockId: id,
      ));

      // Per-symbol type highlights (generated dynamically based on symbol set)
      for (final symbolType in [
        'HP1',
        'HP2',
        'MP1',
        'MP2',
        'LP1',
        'LP2',
        'LP3',
        'WILD',
        'SCATTER'
      ]) {
        stages.add(GeneratedStage(
          name: 'WIN_SYMBOL_HIGHLIGHT_$symbolType',
          description: 'Highlight $symbolType symbol',
          bus: 'sfx',
          priority: 50,
          pooled: true,
          sourceBlockId: id,
        ));
      }
    }

    // === LINE WIN STAGES ===
    stages.add(GeneratedStage(
      name: 'WIN_LINE_SHOW',
      description: 'Show win line',
      bus: 'sfx',
      priority: 48,
      pooled: lineAudioPerLine, // Pooled if showing many lines
      sourceBlockId: id,
    ));

    stages.add(GeneratedStage(
      name: 'WIN_LINE_HIDE',
      description: 'Hide win line',
      bus: 'sfx',
      priority: 45,
      pooled: true,
      sourceBlockId: id,
    ));

    // === WIN TIER PRESENTATION STAGES ===
    final tiers = _getTierNames(tierSystem, tierCount);
    for (final tier in tiers) {
      final tierUpper = tier.toUpperCase();

      // Win present stage per tier
      stages.add(GeneratedStage(
        name: 'WIN_PRESENT_$tierUpper',
        description: '$tier win presentation',
        bus: tierSpecificAudio ? 'wins' : 'sfx',
        priority: _getTierPriority(tier),
        sourceBlockId: id,
      ));

      // Intro for big+ tiers
      if (_isBigWinTier(tier)) {
        stages.add(GeneratedStage(
          name: '${tierUpper}_WIN_INTRO',
          description: '$tier win intro fanfare',
          bus: 'wins',
          priority: _getTierPriority(tier) + 5,
          sourceBlockId: id,
        ));

        if (celebrationLoop) {
          stages.add(GeneratedStage(
            name: '${tierUpper}_WIN_LOOP',
            description: '$tier celebration music loop',
            bus: 'music',
            priority: _getTierPriority(tier),
            looping: true,
            sourceBlockId: id,
          ));
        }

        stages.add(GeneratedStage(
          name: '${tierUpper}_WIN_END',
          description: '$tier celebration end',
          bus: 'wins',
          priority: _getTierPriority(tier),
          sourceBlockId: id,
        ));
      }
    }

    // === ROLLUP STAGES ===
    if (rollupEnabled) {
      stages.add(GeneratedStage(
        name: 'ROLLUP_START',
        description: 'Rollup counter start',
        bus: 'sfx',
        priority: 40,
        sourceBlockId: id,
      ));

      stages.add(GeneratedStage(
        name: 'ROLLUP_TICK',
        description: 'Rollup counter tick',
        bus: 'sfx',
        priority: 38,
        pooled: true, // Very rapid-fire
        sourceBlockId: id,
      ));

      // Tier-specific rollup ticks for different sounds
      for (final tier in tiers) {
        stages.add(GeneratedStage(
          name: 'ROLLUP_TICK_${tier.toUpperCase()}',
          description: '$tier rollup tick',
          bus: 'sfx',
          priority: 38,
          pooled: true,
          sourceBlockId: id,
        ));
      }

      stages.add(GeneratedStage(
        name: 'ROLLUP_END',
        description: 'Rollup counter complete',
        bus: 'sfx',
        priority: 42,
        sourceBlockId: id,
      ));

      // Rollup milestone stages
      for (final milestone in ['25', '50', '75', '100']) {
        stages.add(GeneratedStage(
          name: 'ROLLUP_MILESTONE_$milestone',
          description: '$milestone% rollup milestone',
          bus: 'sfx',
          priority: 41,
          sourceBlockId: id,
        ));
      }
    }

    // === BIG WIN CELEBRATION STAGES ===
    stages.add(GeneratedStage(
      name: 'BIG_WIN_SCREEN_FLASH',
      description: 'Screen flash on big win',
      bus: 'sfx',
      priority: 85,
      sourceBlockId: id,
    ));

    stages.add(GeneratedStage(
      name: 'BIG_WIN_COIN_SHOWER',
      description: 'Coin shower particle effect audio',
      bus: 'sfx',
      priority: 60,
      pooled: true, // Many coin sounds
      sourceBlockId: id,
    ));

    stages.add(GeneratedStage(
      name: 'BIG_WIN_PLAQUE_SHOW',
      description: 'Win tier plaque appears',
      bus: 'sfx',
      priority: 80,
      sourceBlockId: id,
    ));

    stages.add(GeneratedStage(
      name: 'BIG_WIN_PLAQUE_HIDE',
      description: 'Win tier plaque disappears',
      bus: 'sfx',
      priority: 50,
      sourceBlockId: id,
    ));

    // === TOTAL WIN STAGES ===
    stages.add(GeneratedStage(
      name: 'WIN_TOTAL_SHOW',
      description: 'Total win amount display',
      bus: 'sfx',
      priority: 55,
      sourceBlockId: id,
    ));

    stages.add(GeneratedStage(
      name: 'WIN_TOTAL_HIDE',
      description: 'Total win amount hide',
      bus: 'sfx',
      priority: 45,
      sourceBlockId: id,
    ));

    stages.add(GeneratedStage(
      name: 'WIN_COMPLETE',
      description: 'Win presentation complete',
      bus: 'sfx',
      priority: 40,
      sourceBlockId: id,
    ));

    return stages;
  }

  /// Get tier names based on system and count
  List<String> _getTierNames(WinTierSystem system, int count) {
    switch (system) {
      case WinTierSystem.simple:
        return ['small', 'big', 'mega'];
      case WinTierSystem.standard:
        return ['small', 'big', 'super', 'mega', 'epic', 'ultra'];
      case WinTierSystem.extended:
        final tiers = <String>['small', 'big', 'super', 'mega', 'epic', 'ultra'];
        for (var i = 7; i <= count; i++) {
          tiers.add('tier_$i');
        }
        return tiers.take(count).toList();
      case WinTierSystem.dynamic:
        return ['low', 'medium', 'high', 'very_high', 'extreme', 'legendary'];
    }
  }

  /// Check if tier is considered a "big" win tier
  bool _isBigWinTier(String tier) {
    return ['big', 'super', 'mega', 'epic', 'ultra', 'extreme', 'legendary']
            .contains(tier.toLowerCase()) ||
        tier.startsWith('tier_');
  }

  /// Get priority for a tier (higher tiers = higher priority)
  int _getTierPriority(String tier) {
    final priorities = {
      'small': 50,
      'low': 50,
      'medium': 55,
      'big': 60,
      'high': 60,
      'super': 70,
      'very_high': 70,
      'mega': 80,
      'epic': 85,
      'extreme': 85,
      'ultra': 90,
      'legendary': 95,
    };
    return priorities[tier.toLowerCase()] ?? 75;
  }

  @override
  List<String> get pooledStages => [
        'WIN_SYMBOL_HIGHLIGHT',
        'WIN_LINE_SHOW',
        'WIN_LINE_HIDE',
        'ROLLUP_TICK',
        'BIG_WIN_COIN_SHOWER',
      ];

  @override
  String getBusForStage(String stageName) {
    if (stageName.contains('LOOP') || stageName.contains('MUSIC')) {
      return 'music';
    }
    if (stageName.contains('WIN_PRESENT') ||
        stageName.contains('WIN_INTRO') ||
        stageName.contains('WIN_END')) {
      return 'wins';
    }
    return 'sfx';
  }

  @override
  int getPriorityForStage(String stageName) {
    if (stageName.contains('ULTRA')) return 90;
    if (stageName.contains('EPIC')) return 85;
    if (stageName.contains('MEGA')) return 80;
    if (stageName.contains('SUPER')) return 70;
    if (stageName.contains('BIG')) return 60;
    if (stageName.contains('ROLLUP_TICK')) return 38;
    if (stageName.contains('SCREEN_FLASH')) return 85;
    if (stageName.contains('PLAQUE_SHOW')) return 80;
    return 50;
  }

  // === CONVENIENCE GETTERS ===

  WinTierSystem get tierSystem =>
      WinTierSystem.values.byName(getOptionValue('tier_system') as String);

  int get tierCount => getOptionValue('tier_count') as int;

  double get smallWinThreshold =>
      getOptionValue('small_win_threshold') as double;

  double get bigWinThreshold => getOptionValue('big_win_threshold') as double;

  double get superWinThreshold =>
      getOptionValue('super_win_threshold') as double;

  double get megaWinThreshold => getOptionValue('mega_win_threshold') as double;

  double get epicWinThreshold => getOptionValue('epic_win_threshold') as double;

  double get ultraWinThreshold =>
      getOptionValue('ultra_win_threshold') as double;

  RollupStyle get rollupStyle =>
      RollupStyle.values.byName(getOptionValue('rollup_style') as String);

  bool get rollupEnabled => getOptionValue('rollup_enabled') as bool;

  bool get rollupSkipSmall => getOptionValue('rollup_skip_small') as bool;

  int get rollupBaseDuration => getOptionValue('rollup_base_duration') as int;

  bool get rollupScaleWithWin =>
      getOptionValue('rollup_scale_with_win') as bool;

  int get rollupMaxDuration => getOptionValue('rollup_max_duration') as int;

  int get rollupTickRateBase => getOptionValue('rollup_tick_rate_base') as int;

  bool get rollupVolumeEscalation =>
      getOptionValue('rollup_volume_escalation') as bool;

  bool get rollupPitchEscalation =>
      getOptionValue('rollup_pitch_escalation') as bool;

  LineWinStyle get lineWinStyle =>
      LineWinStyle.values.byName(getOptionValue('line_win_style') as String);

  int get lineWinDuration => getOptionValue('line_win_duration') as int;

  int get maxLinesToShow => getOptionValue('max_lines_to_show') as int;

  bool get showLineAmounts => getOptionValue('show_line_amounts') as bool;

  bool get lineAudioPerLine => getOptionValue('line_audio_per_line') as bool;

  SymbolHighlightStyle get highlightStyle => SymbolHighlightStyle.values
      .byName(getOptionValue('highlight_style') as String);

  bool get highlightWinningSymbols =>
      getOptionValue('highlight_winning_symbols') as bool;

  int get highlightDuration => getOptionValue('highlight_duration') as int;

  bool get symbolAudioOnHighlight =>
      getOptionValue('symbol_audio_on_highlight') as bool;

  BigWinCelebration get bigWinCelebration => BigWinCelebration.values
      .byName(getOptionValue('big_win_celebration') as String);

  bool get showWinPlaque => getOptionValue('show_win_plaque') as bool;

  String get plaqueAnimationStyle =>
      getOptionValue('plaque_animation_style') as String;

  bool get coinShower => getOptionValue('coin_shower') as bool;

  bool get screenFlash => getOptionValue('screen_flash') as bool;

  bool get celebrationLoopMusic =>
      getOptionValue('celebration_loop_music') as bool;

  bool get winEvalAudio => getOptionValue('win_eval_audio') as bool;

  bool get tierSpecificAudio => getOptionValue('tier_specific_audio') as bool;

  bool get duckBaseMusic => getOptionValue('duck_base_music') as bool;

  double get duckAmount => getOptionValue('duck_amount') as double;
}
