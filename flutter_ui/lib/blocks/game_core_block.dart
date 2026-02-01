// ============================================================================
// FluxForge Studio — Game Core Block
// ============================================================================
// P13.0.7: Core block defining fundamental game structure
// Pay model, spin type, volatility, RTP configuration.
// ============================================================================

import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';
import '../models/feature_builder/feature_block.dart';

/// Pay model types for slot games.
enum PayModel {
  /// Traditional paylines (10, 20, 25, 50 lines).
  lines,

  /// Ways to win (243, 1024, etc.).
  ways,

  /// Cluster pays (groups of adjacent symbols).
  cluster,

  /// Megaways (dynamic reel sizes).
  megaways,
}

/// Spin type options.
enum SpinType {
  /// Standard spin and stop.
  standard,

  /// Quick stop option available.
  quickStop,

  /// Turbo mode available.
  turbo,

  /// Slam stop (instant stop).
  slamStop,
}

/// Volatility levels.
enum Volatility {
  low,
  mediumLow,
  medium,
  mediumHigh,
  high,
  veryHigh,
  extreme,
}

/// Core block defining fundamental game structure.
///
/// This is a required block that cannot be disabled.
/// It defines the basic game parameters that other blocks depend on.
class GameCoreBlock extends FeatureBlockBase {
  GameCoreBlock() : super(enabled: true); // Always enabled

  @override
  String get id => 'game_core';

  @override
  String get name => 'Game Core';

  @override
  String get description =>
      'Fundamental game structure: pay model, spin type, volatility';

  @override
  BlockCategory get category => BlockCategory.core;

  @override
  String get iconName => 'settings';

  @override
  bool get canBeDisabled => false; // Core blocks cannot be disabled

  @override
  int get stagePriority => 0; // First in stage generation

  @override
  List<BlockOption> createOptions() => [
        // ========== Pay Model ==========
        BlockOptionFactory.dropdown(
          id: 'payModel',
          name: 'Pay Model',
          description: 'How wins are calculated',
          choices: [
            const OptionChoice(
              value: 'lines',
              label: 'Paylines',
              description: 'Traditional paylines (10, 20, 25, 50)',
            ),
            const OptionChoice(
              value: 'ways',
              label: 'Ways to Win',
              description: 'Any matching symbols on adjacent reels (243, 1024)',
            ),
            const OptionChoice(
              value: 'cluster',
              label: 'Cluster Pays',
              description: 'Groups of adjacent matching symbols',
            ),
            const OptionChoice(
              value: 'megaways',
              label: 'Megaways',
              description: 'Dynamic reel sizes (up to 117,649 ways)',
            ),
          ],
          defaultValue: 'lines',
          group: 'Game Structure',
          order: 1,
        ),

        // ========== Spin Type ==========
        BlockOptionFactory.dropdown(
          id: 'spinType',
          name: 'Spin Type',
          description: 'Spin behavior options',
          choices: [
            const OptionChoice(
              value: 'standard',
              label: 'Standard',
              description: 'Normal spin and stop',
            ),
            const OptionChoice(
              value: 'quickStop',
              label: 'Quick Stop',
              description: 'Player can tap to stop reels faster',
            ),
            const OptionChoice(
              value: 'turbo',
              label: 'Turbo Mode',
              description: 'Fast animation mode available',
            ),
            const OptionChoice(
              value: 'slamStop',
              label: 'Slam Stop',
              description: 'Instant stop on tap',
            ),
          ],
          defaultValue: 'quickStop',
          group: 'Game Structure',
          order: 2,
        ),

        // ========== Volatility ==========
        BlockOptionFactory.dropdown(
          id: 'volatility',
          name: 'Volatility',
          description: 'Win frequency vs win size balance',
          choices: [
            const OptionChoice(
              value: 'low',
              label: 'Low',
              description: 'Frequent small wins',
            ),
            const OptionChoice(
              value: 'mediumLow',
              label: 'Medium-Low',
              description: 'Balanced towards frequent wins',
            ),
            const OptionChoice(
              value: 'medium',
              label: 'Medium',
              description: 'Balanced win frequency and size',
            ),
            const OptionChoice(
              value: 'mediumHigh',
              label: 'Medium-High',
              description: 'Balanced towards larger wins',
            ),
            const OptionChoice(
              value: 'high',
              label: 'High',
              description: 'Less frequent, larger wins',
            ),
            const OptionChoice(
              value: 'veryHigh',
              label: 'Very High',
              description: 'Rare but significant wins',
            ),
            const OptionChoice(
              value: 'extreme',
              label: 'Extreme',
              description: 'Very rare, very large wins',
            ),
          ],
          defaultValue: 'medium',
          group: 'Math Model',
          order: 3,
        ),

        // ========== Target RTP ==========
        BlockOptionFactory.range(
          id: 'targetRtp',
          name: 'Target RTP',
          description: 'Return to player percentage (for audio intensity)',
          min: 85.0,
          max: 99.0,
          step: 0.1,
          defaultValue: 96.0,
          group: 'Math Model',
          order: 4,
        ),

        // ========== Hit Frequency ==========
        BlockOptionFactory.range(
          id: 'hitFrequency',
          name: 'Hit Frequency',
          description: 'Approximate percentage of spins that result in a win',
          min: 10.0,
          max: 50.0,
          step: 1.0,
          defaultValue: 30.0,
          group: 'Math Model',
          order: 5,
        ),

        // ========== Max Win Multiplier ==========
        BlockOptionFactory.count(
          id: 'maxWinMultiplier',
          name: 'Max Win Multiplier',
          description: 'Maximum win as multiple of bet (affects audio escalation)',
          min: 500,
          max: 50000,
          defaultValue: 5000,
          group: 'Math Model',
          order: 6,
        ),

        // ========== Base Game Music ==========
        BlockOptionFactory.toggle(
          id: 'baseGameMusic',
          name: 'Base Game Music',
          description: 'Enable background music during base game',
          defaultValue: true,
          group: 'Audio',
          order: 7,
        ),

        // ========== Spin Sound Mode ==========
        BlockOptionFactory.dropdown(
          id: 'spinSoundMode',
          name: 'Spin Sound Mode',
          description: 'How spin sounds are played',
          choices: [
            const OptionChoice(
              value: 'loop',
              label: 'Looping',
              description: 'Single loop during spin',
            ),
            const OptionChoice(
              value: 'perReel',
              label: 'Per Reel',
              description: 'Individual sounds per reel stop',
            ),
            const OptionChoice(
              value: 'both',
              label: 'Both',
              description: 'Loop + per-reel stops',
            ),
          ],
          defaultValue: 'both',
          group: 'Audio',
          order: 8,
        ),
      ];

  @override
  List<BlockDependency> createDependencies() => [
        // Game Core enables all other blocks (implicit dependency)
        BlockDependency.enables(
          source: id,
          target: 'grid',
          description: 'Game Core enables Grid configuration',
        ),
        BlockDependency.enables(
          source: id,
          target: 'symbol_set',
          description: 'Game Core enables Symbol Set configuration',
        ),
      ];

  @override
  List<GeneratedStage> generateStages() => [
        GeneratedStage(
          name: 'SPIN_START',
          description: 'Spin button pressed, reels start spinning',
          bus: 'ui',
          priority: 80,
          sourceBlockId: id,
          category: 'Base Game Loop',
        ),
        GeneratedStage(
          name: 'SPIN_END',
          description: 'All reels stopped, evaluation begins',
          bus: 'sfx',
          priority: 70,
          sourceBlockId: id,
          category: 'Base Game Loop',
        ),
        GeneratedStage(
          name: 'REEL_SPIN_LOOP',
          description: 'Looping audio during reel spin',
          bus: 'reels',
          priority: 60,
          looping: true,
          sourceBlockId: id,
          category: 'Base Game Loop',
        ),
        if (getOptionValue<bool>('baseGameMusic') == true)
          GeneratedStage(
            name: 'MUSIC_BASE',
            description: 'Base game background music',
            bus: 'music',
            priority: 10,
            looping: true,
            sourceBlockId: id,
            category: 'Music & Ambience',
          ),
      ];

  @override
  List<String> get pooledStages => []; // Core stages are not pooled

  @override
  String getBusForStage(String stageName) {
    switch (stageName) {
      case 'SPIN_START':
        return 'ui';
      case 'SPIN_END':
        return 'sfx';
      case 'REEL_SPIN_LOOP':
        return 'reels';
      case 'MUSIC_BASE':
        return 'music';
      default:
        return 'sfx';
    }
  }

  @override
  int getPriorityForStage(String stageName) {
    switch (stageName) {
      case 'SPIN_START':
        return 80;
      case 'SPIN_END':
        return 70;
      case 'REEL_SPIN_LOOP':
        return 60;
      case 'MUSIC_BASE':
        return 10;
      default:
        return 50;
    }
  }

  // ============================================================================
  // Convenience Getters
  // ============================================================================

  /// Get the current pay model.
  PayModel get payModel {
    final value = getOptionValue<String>('payModel') ?? 'lines';
    return PayModel.values.firstWhere(
      (p) => p.name == value,
      orElse: () => PayModel.lines,
    );
  }

  /// Get the current spin type.
  SpinType get spinType {
    final value = getOptionValue<String>('spinType') ?? 'quickStop';
    return SpinType.values.firstWhere(
      (s) => s.name == value,
      orElse: () => SpinType.quickStop,
    );
  }

  /// Get the current volatility.
  Volatility get volatility {
    final value = getOptionValue<String>('volatility') ?? 'medium';
    return Volatility.values.firstWhere(
      (v) => v.name == value,
      orElse: () => Volatility.medium,
    );
  }

  /// Get target RTP.
  double get targetRtp => getOptionValue<double>('targetRtp') ?? 96.0;

  /// Get hit frequency.
  double get hitFrequency => getOptionValue<double>('hitFrequency') ?? 30.0;

  /// Get max win multiplier.
  int get maxWinMultiplier => getOptionValue<int>('maxWinMultiplier') ?? 5000;

  /// Whether base game music is enabled.
  bool get hasBaseGameMusic => getOptionValue<bool>('baseGameMusic') ?? true;

  /// Get spin sound mode.
  String get spinSoundMode => getOptionValue<String>('spinSoundMode') ?? 'both';
}
