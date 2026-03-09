// ============================================================================
// FluxForge Studio — Anticipation Block
// ============================================================================
// P13.9.1: Feature block for Anticipation system configuration
// Defines anticipation triggers, tension escalation, visual effects, and audio.
// ============================================================================

import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';
import '../models/feature_builder/feature_block.dart';

/// Anticipation pattern types.
enum AnticipationPattern {
  /// Type A: 2+ scatters trigger anticipation on remaining reels.
  tipA,

  /// Type B: Near miss pattern detection triggers anticipation.
  tipB,
}

/// Trigger symbol types for anticipation.
enum AnticipationTriggerSymbol {
  /// Scatter symbols trigger anticipation.
  scatter,

  /// Bonus symbols trigger anticipation.
  bonus,

  /// Wild symbols trigger anticipation.
  wild,
}

/// Visual effect types for anticipation.
enum AnticipationVisualEffect {
  /// Glowing reel effect.
  glow,

  /// Pulsing reel effect.
  pulse,

  /// Flashing reel effect.
  flash,

  /// Shaking reel effect.
  shake,
}

/// Audio intensity profiles for anticipation.
enum AnticipationAudioProfile {
  /// Subtle: Quiet, minimal pitch shift.
  subtle,

  /// Moderate: Standard intensity.
  moderate,

  /// Dramatic: Loud, high pitch, long duration.
  dramatic,
}

/// Feature block for Anticipation system configuration.
///
/// This block defines:
/// - Anticipation trigger patterns (Tip A: scatter-based, Tip B: near miss)
/// - Trigger symbol selection (Scatter, Bonus, Wild)
/// - Tension escalation levels (L1-L4 per reel)
/// - Visual effects (glow, pulse, flash, shake)
/// - Audio intensity profiles (subtle, moderate, dramatic)
/// - Per-reel audio stages with tension level escalation
class AnticipationBlock extends FeatureBlockBase {
  AnticipationBlock() : super(enabled: false);

  @override
  String get id => 'anticipation';

  @override
  String get name => 'Anticipation';

  @override
  String get description =>
      'Reel slowdown and tension building when near-trigger symbols appear';

  @override
  BlockCategory get category => BlockCategory.bonus;

  @override
  String get iconName => 'hourglass_empty';

  @override
  bool get canBeDisabled => true;

  @override
  int get stagePriority => 25; // After core, before features

  /// Maximum reel count supported (GridBlock allows 3-8).
  static const int maxReelCount = 8;

  @override
  List<BlockOption> createOptions() => [
        // ========== Pattern Selection ==========
        BlockOptionFactory.dropdown(
          id: 'pattern',
          name: 'Anticipation Pattern',
          description: 'How anticipation is triggered',
          choices: [
            const OptionChoice(
              value: 'tip_a',
              label: 'Type A (Scatter)',
              description: '2+ scatters trigger anticipation on remaining reels',
            ),
            const OptionChoice(
              value: 'tip_b',
              label: 'Type B (Near Miss)',
              description: 'Near miss pattern triggers anticipation',
            ),
          ],
          defaultValue: 'tip_a',
          group: 'Trigger',
          order: 1,
        ),

        // ========== Trigger Symbol ==========
        BlockOptionFactory.dropdown(
          id: 'triggerSymbol',
          name: 'Trigger Symbol',
          description: 'Which symbol type triggers anticipation',
          choices: [
            const OptionChoice(
              value: 'scatter',
              label: 'Scatter',
              description: 'Scatter symbols trigger anticipation',
            ),
            const OptionChoice(
              value: 'bonus',
              label: 'Bonus',
              description: 'Bonus symbols trigger anticipation',
            ),
            const OptionChoice(
              value: 'wild',
              label: 'Wild',
              description: 'Wild symbols trigger anticipation',
            ),
          ],
          defaultValue: 'scatter',
          group: 'Trigger',
          order: 2,
        ),

        // ========== Minimum Symbols to Trigger ==========
        BlockOptionFactory.count(
          id: 'minSymbolsToTrigger',
          name: 'Min Symbols to Trigger',
          description: 'Minimum trigger symbols needed before anticipation starts',
          min: 1,
          max: 4,
          defaultValue: 2,
          group: 'Trigger',
          order: 3,
        ),

        // ========== Reel Count (from Grid) ==========
        BlockOptionFactory.count(
          id: 'reelCount',
          name: 'Reel Count',
          description: 'Number of reels in the grid (must match Grid block)',
          min: 3,
          max: maxReelCount,
          defaultValue: 5,
          group: 'Grid',
          order: 4,
        ),

        // ========== Anticipation Reels (multi-select) ==========
        BlockOptionFactory.multiSelect(
          id: 'anticipationReels',
          name: 'Anticipation Reels',
          description: 'Which reels can have anticipation (depends on game logic)',
          choices: [
            for (int r = 0; r < maxReelCount; r++)
              OptionChoice(
                value: r,
                label: 'Reel ${r + 1}',
                description: 'Reel index $r',
              ),
          ],
          defaultValue: const [2, 3, 4], // Default: reels 3-5 for 5×3
          group: 'Grid',
          order: 5,
        ),

        // ========== Tension Escalation Toggle ==========
        BlockOptionFactory.toggle(
          id: 'tensionEscalationEnabled',
          name: 'Tension Escalation',
          description: 'Enable per-reel tension level escalation (L1-L4)',
          defaultValue: true,
          group: 'Tension',
          order: 10,
        ),

        // ========== Tension Levels Count ==========
        BlockOptionFactory.count(
          id: 'tensionLevels',
          name: 'Tension Levels',
          description: 'Number of tension escalation levels (1-4)',
          min: 1,
          max: 4,
          defaultValue: 4,
          group: 'Tension',
          order: 11,
          visibleWhen: {'tensionEscalationEnabled': true},
        ),

        // ========== Reel Slowdown Factor ==========
        BlockOptionFactory.percentage(
          id: 'reelSlowdownFactor',
          name: 'Reel Slowdown',
          description: 'How much to slow down anticipating reels (% of normal speed)',
          defaultValue: 30.0, // 30% of normal speed
          group: 'Tension',
          order: 12,
        ),

        // ========== Visual Effect ==========
        BlockOptionFactory.dropdown(
          id: 'visualEffect',
          name: 'Visual Effect',
          description: 'Visual feedback during anticipation',
          choices: [
            const OptionChoice(
              value: 'glow',
              label: 'Glow',
              description: 'Glowing reel effect',
            ),
            const OptionChoice(
              value: 'pulse',
              label: 'Pulse',
              description: 'Pulsing reel effect',
            ),
            const OptionChoice(
              value: 'flash',
              label: 'Flash',
              description: 'Flashing reel effect',
            ),
            const OptionChoice(
              value: 'shake',
              label: 'Shake',
              description: 'Shaking reel effect',
            ),
          ],
          defaultValue: 'glow',
          group: 'Visual',
          order: 20,
        ),

        // ========== Audio Profile ==========
        BlockOptionFactory.dropdown(
          id: 'audioProfile',
          name: 'Audio Profile',
          description: 'Audio intensity during anticipation',
          choices: [
            const OptionChoice(
              value: 'subtle',
              label: 'Subtle',
              description: 'Quiet, minimal pitch shift',
            ),
            const OptionChoice(
              value: 'moderate',
              label: 'Moderate',
              description: 'Standard intensity',
            ),
            const OptionChoice(
              value: 'dramatic',
              label: 'Dramatic',
              description: 'Loud, high pitch, long duration',
            ),
          ],
          defaultValue: 'moderate',
          group: 'Audio',
          order: 30,
        ),

        // ========== Per-Reel Audio ==========
        BlockOptionFactory.toggle(
          id: 'perReelAudio',
          name: 'Per-Reel Audio',
          description: 'Generate separate audio stages for each reel',
          defaultValue: true,
          group: 'Audio',
          order: 31,
        ),

        // ========== Audio Pitch Escalation ==========
        BlockOptionFactory.toggle(
          id: 'audioPitchEscalation',
          name: 'Pitch Escalation',
          description: 'Increase pitch with each tension level',
          defaultValue: true,
          group: 'Audio',
          order: 32,
          visibleWhen: {'tensionEscalationEnabled': true},
        ),

        // ========== Audio Volume Escalation ==========
        BlockOptionFactory.toggle(
          id: 'audioVolumeEscalation',
          name: 'Volume Escalation',
          description: 'Increase volume with each tension level',
          defaultValue: true,
          group: 'Audio',
          order: 33,
          visibleWhen: {'tensionEscalationEnabled': true},
        ),
      ];

  @override
  List<BlockDependency> createDependencies() => [
        // Requires Symbol Set for trigger symbol validation
        BlockDependency.requires(
          source: id,
          target: 'symbol_set',
          description: 'Needs Scatter OR Bonus symbol as trigger',
          autoResolvable: true,
        ),

        // Modifies Grid (adds reel slowdown timing)
        BlockDependency.modifies(
          source: id,
          target: 'grid',
          description: 'Adds reel slowdown timing',
        ),

        // Modifies Music States (adds anticipation music context)
        BlockDependency.modifies(
          source: id,
          target: 'music_states',
          description: 'Adds anticipation music layer',
        ),
      ];

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];
    final pattern = getOptionValue<String>('pattern') ?? 'tip_a';
    final hasTensionEscalation =
        getOptionValue<bool>('tensionEscalationEnabled') ?? true;
    final tensionLevels = getOptionValue<int>('tensionLevels') ?? 4;
    final hasPerReelAudio = getOptionValue<bool>('perReelAudio') ?? true;
    final reels = anticipationReelIndices;

    // ========== Core Anticipation Stages ==========
    stages.add(const GeneratedStage(
      name: 'ANTICIPATION_TENSION',
      description: 'Generic anticipation tension (fallback)',
      bus: 'sfx',
      priority: 78,
      looping: true,
      sourceBlockId: 'anticipation',
      category: 'Anticipation',
    ));

    stages.add(const GeneratedStage(
      name: 'ANTICIPATION_MISS',
      description: 'Anticipation resolved without trigger',
      bus: 'sfx',
      priority: 50,
      sourceBlockId: 'anticipation',
      category: 'Anticipation',
    ));

    // ========== Per-Reel Tension Stages ==========
    // Generated for each reel selected in anticipationReels config.
    // Any reel (R0-R7) can have anticipation depending on grid and game logic.
    if (hasPerReelAudio) {
      for (final reel in reels) {
        // Generic per-reel stage (fallback)
        stages.add(GeneratedStage(
          name: 'ANTICIPATION_TENSION_R$reel',
          description: 'Anticipation tension for reel ${reel + 1}',
          bus: 'sfx',
          priority: 77,
          looping: true,
          sourceBlockId: id,
          category: 'Anticipation',
        ));

        // Per-reel tension level stages (L1-L4)
        // Tension level depends on ORDER of anticipation reel, not absolute index.
        // E.g., if reels [2,3,4] have anticipation: R2=L1, R3=L2, R4=L3.
        // But we register ALL levels for each reel since the runtime
        // decides the actual tension level based on trigger positions.
        if (hasTensionEscalation) {
          for (int level = 1; level <= tensionLevels; level++) {
            stages.add(GeneratedStage(
              name: 'ANTICIPATION_TENSION_R${reel}_L$level',
              description: 'Reel ${reel + 1}, tension level $level',
              bus: 'sfx',
              priority: 76 + level, // Higher level = higher priority
              looping: true,
              sourceBlockId: id,
              category: 'Anticipation',
            ));
          }
        }
      }
    }

    // ========== Near Miss Stages (Type B) ==========
    if (pattern == 'tip_b') {
      final reelCount = getOptionValue<int>('reelCount') ?? 5;
      for (int reel = 0; reel < reelCount; reel++) {
        stages.add(GeneratedStage(
          name: 'NEAR_MISS_REEL_$reel',
          description: 'Near miss detected on reel ${reel + 1}',
          bus: 'sfx',
          priority: 72,
          sourceBlockId: id,
          category: 'Anticipation',
        ));
      }

      stages.add(const GeneratedStage(
        name: 'NEAR_MISS_REVEAL',
        description: 'Near miss outcome revealed',
        bus: 'sfx',
        priority: 74,
        sourceBlockId: 'anticipation',
        category: 'Anticipation',
      ));
    }

    // ========== Anticipation Result Stages ==========
    stages.add(const GeneratedStage(
      name: 'ANTICIPATION_SUCCESS',
      description: 'Anticipation resulted in trigger (feature activated)',
      bus: 'sfx',
      priority: 85,
      sourceBlockId: 'anticipation',
      category: 'Anticipation',
    ));

    stages.add(const GeneratedStage(
      name: 'ANTICIPATION_FAIL',
      description: 'Anticipation did not result in trigger',
      bus: 'sfx',
      priority: 70,
      sourceBlockId: 'anticipation',
      category: 'Anticipation',
    ));

    return stages;
  }

  @override
  List<String> get pooledStages {
    // Tension stages are looping, not pooled.
    // Near miss stages may fire rapidly — pool them.
    final reelCount = getOptionValue<int>('reelCount') ?? 5;
    return [
      for (int r = 0; r < reelCount; r++) 'NEAR_MISS_REEL_$r',
    ];
  }

  @override
  String getBusForStage(String stageName) => 'sfx';

  @override
  int getPriorityForStage(String stageName) {
    // Success/Fail results
    if (stageName == 'ANTICIPATION_SUCCESS') return 85;
    if (stageName == 'ANTICIPATION_TENSION') return 80;

    // Tension levels (higher level = higher priority)
    if (stageName.contains('_L4')) return 80;
    if (stageName.contains('_L3')) return 79;
    if (stageName.contains('_L2')) return 78;
    if (stageName.contains('_L1')) return 77;

    // Generic tension
    if (stageName.contains('TENSION')) return 78;

    // Near miss
    if (stageName.contains('NEAR_MISS')) return 72;

    // Off/Fail
    if (stageName == 'ANTICIPATION_MISS') return 50;
    if (stageName == 'ANTICIPATION_FAIL') return 70;

    return 75;
  }

  @override
  List<String> validateOptions() {
    final errors = super.validateOptions();
    final pattern = getOptionValue<String>('pattern');
    final triggerSymbol = getOptionValue<String>('triggerSymbol');
    final minSymbols = getOptionValue<int>('minSymbolsToTrigger') ?? 2;

    // Validate min symbols makes sense for pattern
    if (pattern == 'tip_a' && minSymbols < 2) {
      errors.add('Type A pattern requires at least 2 symbols to trigger');
    }

    // Validate trigger symbol is valid
    if (triggerSymbol == null ||
        !['scatter', 'bonus', 'wild'].contains(triggerSymbol)) {
      errors.add('Invalid trigger symbol selected');
    }

    return errors;
  }

  // ============================================================================
  // Convenience Getters
  // ============================================================================

  /// Get the anticipation pattern.
  AnticipationPattern get pattern {
    final value = getOptionValue<String>('pattern') ?? 'tip_a';
    return value == 'tip_b' ? AnticipationPattern.tipB : AnticipationPattern.tipA;
  }

  /// Get the trigger symbol type.
  AnticipationTriggerSymbol get triggerSymbol {
    final value = getOptionValue<String>('triggerSymbol') ?? 'scatter';
    switch (value) {
      case 'bonus':
        return AnticipationTriggerSymbol.bonus;
      case 'wild':
        return AnticipationTriggerSymbol.wild;
      default:
        return AnticipationTriggerSymbol.scatter;
    }
  }

  /// Get minimum symbols to trigger anticipation.
  int get minSymbolsToTrigger =>
      getOptionValue<int>('minSymbolsToTrigger') ?? 2;

  /// Get reel count (from grid configuration).
  int get reelCount => getOptionValue<int>('reelCount') ?? 5;

  /// Get the list of reel indices that can have anticipation.
  /// These are the reels the user selected in the Anticipation Reels multi-select.
  /// Sorted ascending and filtered to be within reelCount range.
  List<int> get anticipationReelIndices {
    final raw = getOptionValue<List>('anticipationReels');
    if (raw == null || raw.isEmpty) return const [2, 3, 4]; // Default
    final count = reelCount;
    final reels = raw
        .map((v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? -1))
        .where((r) => r >= 0 && r < count)
        .toList()
      ..sort();
    return reels;
  }

  /// Whether tension escalation is enabled.
  bool get hasTensionEscalation =>
      getOptionValue<bool>('tensionEscalationEnabled') ?? true;

  /// Get number of tension levels (1-4).
  int get tensionLevels => getOptionValue<int>('tensionLevels') ?? 4;

  /// Get reel slowdown factor (percentage).
  double get reelSlowdownFactor =>
      getOptionValue<double>('reelSlowdownFactor') ?? 30.0;

  /// Get the visual effect type.
  AnticipationVisualEffect get visualEffect {
    final value = getOptionValue<String>('visualEffect') ?? 'glow';
    switch (value) {
      case 'pulse':
        return AnticipationVisualEffect.pulse;
      case 'flash':
        return AnticipationVisualEffect.flash;
      case 'shake':
        return AnticipationVisualEffect.shake;
      default:
        return AnticipationVisualEffect.glow;
    }
  }

  /// Get the audio profile.
  AnticipationAudioProfile get audioProfile {
    final value = getOptionValue<String>('audioProfile') ?? 'moderate';
    switch (value) {
      case 'subtle':
        return AnticipationAudioProfile.subtle;
      case 'dramatic':
        return AnticipationAudioProfile.dramatic;
      default:
        return AnticipationAudioProfile.moderate;
    }
  }

  /// Whether per-reel audio is enabled.
  bool get hasPerReelAudio => getOptionValue<bool>('perReelAudio') ?? true;

  /// Whether audio pitch escalation is enabled.
  bool get hasAudioPitchEscalation =>
      getOptionValue<bool>('audioPitchEscalation') ?? true;

  /// Whether audio volume escalation is enabled.
  bool get hasAudioVolumeEscalation =>
      getOptionValue<bool>('audioVolumeEscalation') ?? true;

  /// Get volume multiplier for a tension level.
  double getVolumeForLevel(int level) {
    if (!hasAudioVolumeEscalation) return 1.0;
    // L1=0.6x, L2=0.7x, L3=0.8x, L4=0.9x
    return 0.5 + (level * 0.1);
  }

  /// Get pitch offset (semitones) for a tension level.
  int getPitchOffsetForLevel(int level) {
    if (!hasAudioPitchEscalation) return 0;
    // L1=+1st, L2=+2st, L3=+3st, L4=+4st
    return level;
  }

  /// Get all generated stage names for a specific reel.
  /// [reelIndex] is the 0-based reel index (R0-R7).
  List<String> getStagesForReel(int reelIndex) {
    final stages = <String>[];
    if (!anticipationReelIndices.contains(reelIndex)) return stages;

    stages.add('ANTICIPATION_TENSION_R$reelIndex');
    if (hasTensionEscalation) {
      for (int level = 1; level <= tensionLevels; level++) {
        stages.add('ANTICIPATION_TENSION_R${reelIndex}_L$level');
      }
    }
    return stages;
  }
}
