// ============================================================================
// FluxForge Studio — Grid Block
// ============================================================================
// P13.0.8: Core block defining grid configuration
// Reels, rows, paylines/ways, reel stop timing.
// ============================================================================

import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';
import '../models/feature_builder/feature_block.dart';

/// Grid layout presets.
enum GridPreset {
  classic3x3,
  classic5x3,
  video5x4,
  video6x4,
  megaways6x7,
  cluster7x7,
  custom,
}

/// Core block defining grid configuration.
///
/// This is a required block that cannot be disabled.
/// It defines the reel and row layout, payline/ways count, and reel timing.
class GridBlock extends FeatureBlockBase {
  GridBlock() : super(enabled: true); // Always enabled

  @override
  String get id => 'grid';

  @override
  String get name => 'Grid';

  @override
  String get description => 'Reel and row configuration, paylines/ways, timing';

  @override
  BlockCategory get category => BlockCategory.core;

  @override
  String get iconName => 'grid_view';

  @override
  bool get canBeDisabled => false; // Core blocks cannot be disabled

  @override
  int get stagePriority => 1; // After Game Core

  @override
  List<BlockOption> createOptions() => [
        // ========== Grid Preset ==========
        BlockOptionFactory.dropdown(
          id: 'preset',
          name: 'Grid Preset',
          description: 'Quick select common grid configurations',
          choices: [
            const OptionChoice(
              value: 'classic3x3',
              label: 'Classic 3×3',
              description: '3 reels, 3 rows, 5 paylines',
            ),
            const OptionChoice(
              value: 'classic5x3',
              label: 'Classic 5×3',
              description: '5 reels, 3 rows, 20 paylines',
            ),
            const OptionChoice(
              value: 'video5x4',
              label: 'Video 5×4',
              description: '5 reels, 4 rows, 40 paylines or 1024 ways',
            ),
            const OptionChoice(
              value: 'video6x4',
              label: 'Video 6×4',
              description: '6 reels, 4 rows, 4096 ways',
            ),
            const OptionChoice(
              value: 'megaways6x7',
              label: 'Megaways 6×7',
              description: '6 reels, 2-7 rows, up to 117,649 ways',
            ),
            const OptionChoice(
              value: 'cluster7x7',
              label: 'Cluster 7×7',
              description: '7×7 grid for cluster pays',
            ),
            const OptionChoice(
              value: 'custom',
              label: 'Custom',
              description: 'Define your own grid size',
            ),
          ],
          defaultValue: 'classic5x3',
          group: 'Grid Size',
          order: 1,
        ),

        // ========== Reel Count ==========
        BlockOptionFactory.count(
          id: 'reelCount',
          name: 'Reel Count',
          description: 'Number of reels (columns)',
          min: 3,
          max: 8,
          defaultValue: 5,
          group: 'Grid Size',
          order: 2,
        ),

        // ========== Row Count ==========
        BlockOptionFactory.count(
          id: 'rowCount',
          name: 'Row Count',
          description: 'Number of visible rows per reel',
          min: 1,
          max: 10,
          defaultValue: 3,
          group: 'Grid Size',
          order: 3,
        ),

        // ========== Dynamic Rows (Megaways) ==========
        BlockOptionFactory.toggle(
          id: 'dynamicRows',
          name: 'Dynamic Rows',
          description: 'Rows vary per spin (Megaways style)',
          defaultValue: false,
          group: 'Grid Size',
          order: 4,
          visibleWhen: {'preset': 'megaways6x7'},
        ),

        // ========== Min Rows (Dynamic) ==========
        BlockOptionFactory.count(
          id: 'minRows',
          name: 'Min Rows',
          description: 'Minimum rows per reel (dynamic mode)',
          min: 2,
          max: 6,
          defaultValue: 2,
          group: 'Grid Size',
          order: 5,
          visibleWhen: {'dynamicRows': true},
        ),

        // ========== Max Rows (Dynamic) ==========
        BlockOptionFactory.count(
          id: 'maxRows',
          name: 'Max Rows',
          description: 'Maximum rows per reel (dynamic mode)',
          min: 4,
          max: 10,
          defaultValue: 7,
          group: 'Grid Size',
          order: 6,
          visibleWhen: {'dynamicRows': true},
        ),

        // ========== Payline Count ==========
        BlockOptionFactory.count(
          id: 'paylineCount',
          name: 'Payline Count',
          description: 'Number of paylines (for payline games)',
          min: 1,
          max: 100,
          defaultValue: 20,
          group: 'Win Structure',
          order: 7,
        ),

        // ========== Ways Calculation ==========
        BlockOptionFactory.dropdown(
          id: 'waysCalculation',
          name: 'Ways Calculation',
          description: 'How ways-to-win are calculated',
          choices: [
            const OptionChoice(
              value: 'none',
              label: 'Not Applicable',
              description: 'Using paylines instead',
            ),
            const OptionChoice(
              value: 'standard',
              label: 'Standard Ways',
              description: 'rows^reels (e.g., 3^5 = 243)',
            ),
            const OptionChoice(
              value: 'megaways',
              label: 'Megaways',
              description: 'Dynamic per spin based on reel sizes',
            ),
          ],
          defaultValue: 'none',
          group: 'Win Structure',
          order: 8,
        ),

        // ========== Reel Stop Timing ==========
        BlockOptionFactory.dropdown(
          id: 'reelStopTiming',
          name: 'Reel Stop Timing',
          description: 'How reels stop',
          choices: [
            const OptionChoice(
              value: 'sequential',
              label: 'Sequential',
              description: 'Reels stop left to right with delay',
            ),
            const OptionChoice(
              value: 'simultaneous',
              label: 'Simultaneous',
              description: 'All reels stop at once',
            ),
            const OptionChoice(
              value: 'random',
              label: 'Random Order',
              description: 'Reels stop in random order',
            ),
          ],
          defaultValue: 'sequential',
          group: 'Animation',
          order: 9,
        ),

        // ========== Reel Stop Interval ==========
        BlockOptionFactory.range(
          id: 'reelStopInterval',
          name: 'Reel Stop Interval',
          description: 'Delay between reel stops (ms)',
          min: 100,
          max: 500,
          step: 10,
          defaultValue: 200,
          group: 'Animation',
          order: 10,
          visibleWhen: {'reelStopTiming': 'sequential'},
        ),

        // ========== Spin Duration ==========
        BlockOptionFactory.range(
          id: 'spinDuration',
          name: 'Base Spin Duration',
          description: 'Minimum spin time before first reel stops (ms)',
          min: 500,
          max: 3000,
          step: 100,
          defaultValue: 1000,
          group: 'Animation',
          order: 11,
        ),

        // ========== Per-Reel Audio Pan ==========
        BlockOptionFactory.toggle(
          id: 'perReelPan',
          name: 'Per-Reel Stereo Pan',
          description: 'Reel stops are panned across stereo field',
          defaultValue: true,
          group: 'Audio',
          order: 12,
        ),

        // ========== Pan Spread ==========
        BlockOptionFactory.range(
          id: 'panSpread',
          name: 'Pan Spread',
          description: 'Stereo spread for reel stops (0=center, 1=full L-R)',
          min: 0.0,
          max: 1.0,
          step: 0.1,
          defaultValue: 0.8,
          group: 'Audio',
          order: 13,
          visibleWhen: {'perReelPan': true},
        ),
      ];

  @override
  List<BlockDependency> createDependencies() => [
        BlockDependency.requires(
          source: id,
          target: 'game_core',
          description: 'Grid requires Game Core',
        ),
      ];

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];
    final reels = reelCount;
    final usePan = getOptionValue<bool>('perReelPan') ?? true;
    final panSpread = getOptionValue<double>('panSpread') ?? 0.8;

    // Generate per-reel stop stages
    for (int i = 0; i < reels; i++) {
      final pan = usePan ? _calculatePan(i, reels, panSpread) : 0.0;
      stages.add(GeneratedStage(
        name: 'REEL_STOP_$i',
        description: 'Reel ${i + 1} stops (pan: ${pan.toStringAsFixed(2)})',
        bus: 'reels',
        priority: 65 - i, // Earlier reels have slightly higher priority
        pooled: true, // Reel stops are pooled for quick succession
        sourceBlockId: id,
        category: 'Base Game Loop',
      ));
    }

    // Generic reel stop (fallback)
    stages.add(const GeneratedStage(
      name: 'REEL_STOP',
      description: 'Generic reel stop (fallback)',
      bus: 'reels',
      priority: 60,
      pooled: true,
      sourceBlockId: 'grid',
      category: 'Base Game Loop',
    ));

    // Win evaluation
    stages.add(const GeneratedStage(
      name: 'WIN_EVAL',
      description: 'Win evaluation after all reels stop',
      bus: 'sfx',
      priority: 55,
      sourceBlockId: 'grid',
      category: 'Win Presentation',
    ));

    return stages;
  }

  /// Calculate stereo pan position for a reel.
  double _calculatePan(int reelIndex, int totalReels, double spread) {
    if (totalReels <= 1) return 0.0;
    // Map reel index to -spread..+spread
    final normalized = (reelIndex / (totalReels - 1)) * 2 - 1; // -1 to +1
    return normalized * spread;
  }

  @override
  List<String> get pooledStages {
    final reels = reelCount;
    return [
      for (int i = 0; i < reels; i++) 'REEL_STOP_$i',
      'REEL_STOP',
    ];
  }

  @override
  String getBusForStage(String stageName) {
    if (stageName.startsWith('REEL_STOP')) return 'reels';
    if (stageName == 'WIN_EVAL') return 'sfx';
    return 'sfx';
  }

  @override
  int getPriorityForStage(String stageName) {
    if (stageName.startsWith('REEL_STOP_')) {
      final index = int.tryParse(stageName.split('_').last) ?? 0;
      return 65 - index;
    }
    if (stageName == 'REEL_STOP') return 60;
    if (stageName == 'WIN_EVAL') return 55;
    return 50;
  }

  // ============================================================================
  // Convenience Getters
  // ============================================================================

  /// Get reel count.
  int get reelCount => getOptionValue<int>('reelCount') ?? 5;

  /// Get row count.
  int get rowCount => getOptionValue<int>('rowCount') ?? 3;

  /// Whether using dynamic rows (Megaways).
  bool get hasDynamicRows => getOptionValue<bool>('dynamicRows') ?? false;

  /// Get min rows (dynamic mode).
  int get minRows => getOptionValue<int>('minRows') ?? 2;

  /// Get max rows (dynamic mode).
  int get maxRows => getOptionValue<int>('maxRows') ?? 7;

  /// Get payline count.
  int get paylineCount => getOptionValue<int>('paylineCount') ?? 20;

  /// Get ways calculation mode.
  String get waysCalculation =>
      getOptionValue<String>('waysCalculation') ?? 'none';

  /// Calculate total ways (for ways games).
  int get totalWays {
    if (waysCalculation == 'none') return 0;
    if (hasDynamicRows) {
      // Max ways for Megaways
      return List.generate(reelCount, (_) => maxRows).reduce((a, b) => a * b);
    }
    return List.generate(reelCount, (_) => rowCount).reduce((a, b) => a * b);
  }

  /// Get reel stop interval (ms).
  int get reelStopInterval =>
      getOptionValue<int>('reelStopInterval')?.toInt() ?? 200;

  /// Get base spin duration (ms).
  int get spinDuration =>
      getOptionValue<int>('spinDuration')?.toInt() ?? 1000;

  /// Calculate total spin duration including all reel stops.
  int get totalSpinDuration {
    final timing = getOptionValue<String>('reelStopTiming') ?? 'sequential';
    if (timing == 'simultaneous') return spinDuration;
    return spinDuration + (reelCount - 1) * reelStopInterval;
  }

  /// Get grid size as string (e.g., "5×3").
  String get gridSizeString => '$reelCount×$rowCount';

  /// Get preset.
  GridPreset get preset {
    final value = getOptionValue<String>('preset') ?? 'classic5x3';
    return GridPreset.values.firstWhere(
      (p) => p.name == value,
      orElse: () => GridPreset.classic5x3,
    );
  }

  /// Apply a preset.
  void applyPreset(GridPreset preset) {
    setOptionValue('preset', preset.name);
    switch (preset) {
      case GridPreset.classic3x3:
        setOptionValue('reelCount', 3);
        setOptionValue('rowCount', 3);
        setOptionValue('paylineCount', 5);
        setOptionValue('waysCalculation', 'none');
        setOptionValue('dynamicRows', false);
        break;
      case GridPreset.classic5x3:
        setOptionValue('reelCount', 5);
        setOptionValue('rowCount', 3);
        setOptionValue('paylineCount', 20);
        setOptionValue('waysCalculation', 'none');
        setOptionValue('dynamicRows', false);
        break;
      case GridPreset.video5x4:
        setOptionValue('reelCount', 5);
        setOptionValue('rowCount', 4);
        setOptionValue('paylineCount', 40);
        setOptionValue('waysCalculation', 'standard');
        setOptionValue('dynamicRows', false);
        break;
      case GridPreset.video6x4:
        setOptionValue('reelCount', 6);
        setOptionValue('rowCount', 4);
        setOptionValue('paylineCount', 50);
        setOptionValue('waysCalculation', 'standard');
        setOptionValue('dynamicRows', false);
        break;
      case GridPreset.megaways6x7:
        setOptionValue('reelCount', 6);
        setOptionValue('rowCount', 7);
        setOptionValue('dynamicRows', true);
        setOptionValue('minRows', 2);
        setOptionValue('maxRows', 7);
        setOptionValue('waysCalculation', 'megaways');
        break;
      case GridPreset.cluster7x7:
        setOptionValue('reelCount', 7);
        setOptionValue('rowCount', 7);
        setOptionValue('waysCalculation', 'none');
        setOptionValue('dynamicRows', false);
        break;
      case GridPreset.custom:
        // Keep current values
        break;
    }
  }
}
