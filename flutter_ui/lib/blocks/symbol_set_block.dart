// ============================================================================
// FluxForge Studio — Symbol Set Block
// ============================================================================
// P13.0.9: Core block defining symbol configuration
// Symbol counts, types, special symbols (Wild, Scatter, Bonus).
// ============================================================================

import '../models/feature_builder/block_category.dart';
import '../models/feature_builder/block_dependency.dart';
import '../models/feature_builder/block_options.dart';
import '../models/feature_builder/feature_block.dart';

/// Symbol tiers for payout categorization.
enum SymbolTier {
  low,
  medium,
  high,
  premium,
  special,
}

/// Special symbol types.
enum SpecialSymbolType {
  wild,
  scatter,
  bonus,
  coin,
  collector,
  multiplier,
  mystery,
}

/// Core block defining symbol configuration.
///
/// This is a required block that cannot be disabled.
/// It defines the symbol set including regular and special symbols.
class SymbolSetBlock extends FeatureBlockBase {
  SymbolSetBlock() : super(enabled: true); // Always enabled

  @override
  String get id => 'symbol_set';

  @override
  String get name => 'Symbol Set';

  @override
  String get description =>
      'Symbol configuration: counts, types, special symbols';

  @override
  BlockCategory get category => BlockCategory.core;

  @override
  String get iconName => 'stars';

  @override
  bool get canBeDisabled => false; // Core blocks cannot be disabled

  @override
  int get stagePriority => 2; // After Grid

  @override
  List<BlockOption> createOptions() => [
        // ========== Low Pay Symbols ==========
        BlockOptionFactory.count(
          id: 'lowPayCount',
          name: 'Low Pay Symbols',
          description: 'Number of low-paying symbols (A, K, Q, J, 10, 9)',
          min: 0,
          max: 8,
          defaultValue: 4,
          group: 'Regular Symbols',
          order: 1,
        ),

        // ========== Medium Pay Symbols ==========
        BlockOptionFactory.count(
          id: 'mediumPayCount',
          name: 'Medium Pay Symbols',
          description: 'Number of medium-paying symbols',
          min: 0,
          max: 6,
          defaultValue: 2,
          group: 'Regular Symbols',
          order: 2,
        ),

        // ========== High Pay Symbols ==========
        BlockOptionFactory.count(
          id: 'highPayCount',
          name: 'High Pay Symbols',
          description: 'Number of high-paying symbols',
          min: 0,
          max: 4,
          defaultValue: 2,
          group: 'Regular Symbols',
          order: 3,
        ),

        // ========== Premium Symbols ==========
        BlockOptionFactory.count(
          id: 'premiumCount',
          name: 'Premium Symbols',
          description: 'Number of premium/themed symbols (highest pay)',
          min: 0,
          max: 3,
          defaultValue: 1,
          group: 'Regular Symbols',
          order: 4,
        ),

        // ========== Wild Symbol ==========
        BlockOptionFactory.toggle(
          id: 'hasWild',
          name: 'Wild Symbol',
          description: 'Include Wild symbol that substitutes for others',
          defaultValue: true,
          group: 'Special Symbols',
          order: 5,
        ),

        // ========== Wild Multiplier ==========
        BlockOptionFactory.toggle(
          id: 'wildMultiplier',
          name: 'Wild Multiplier',
          description: 'Wild symbols carry multipliers',
          defaultValue: false,
          group: 'Special Symbols',
          order: 6,
          visibleWhen: {'hasWild': true},
        ),

        // ========== Wild Multiplier Values ==========
        BlockOptionFactory.multiSelect(
          id: 'wildMultiplierValues',
          name: 'Multiplier Values',
          description: 'Possible Wild multiplier values',
          choices: [
            const OptionChoice(value: 2, label: '2x'),
            const OptionChoice(value: 3, label: '3x'),
            const OptionChoice(value: 4, label: '4x'),
            const OptionChoice(value: 5, label: '5x'),
            const OptionChoice(value: 10, label: '10x'),
          ],
          defaultValue: [2, 3, 5],
          group: 'Special Symbols',
          order: 7,
          visibleWhen: {'wildMultiplier': true},
        ),

        // ========== Scatter Symbol ==========
        BlockOptionFactory.toggle(
          id: 'hasScatter',
          name: 'Scatter Symbol',
          description: 'Include Scatter symbol for triggering features',
          defaultValue: true,
          group: 'Special Symbols',
          order: 8,
        ),

        // ========== Scatter Count for Trigger ==========
        BlockOptionFactory.count(
          id: 'scatterTriggerCount',
          name: 'Scatter Trigger Count',
          description: 'Number of Scatters needed to trigger feature',
          min: 2,
          max: 6,
          defaultValue: 3,
          group: 'Special Symbols',
          order: 9,
          visibleWhen: {'hasScatter': true},
        ),

        // ========== Bonus Symbol ==========
        BlockOptionFactory.toggle(
          id: 'hasBonus',
          name: 'Bonus Symbol',
          description: 'Include Bonus symbol for bonus games',
          defaultValue: false,
          group: 'Special Symbols',
          order: 10,
        ),

        // ========== Coin Symbol (Hold & Win) ==========
        BlockOptionFactory.toggle(
          id: 'hasCoin',
          name: 'Coin Symbol',
          description: 'Include Coin symbol for Hold & Win features',
          defaultValue: false,
          group: 'Special Symbols',
          order: 11,
        ),

        // ========== Collector Symbol ==========
        BlockOptionFactory.toggle(
          id: 'hasCollector',
          name: 'Collector Symbol',
          description: 'Include Collector symbol for meter features',
          defaultValue: false,
          group: 'Special Symbols',
          order: 12,
        ),

        // ========== Mystery Symbol ==========
        BlockOptionFactory.toggle(
          id: 'hasMystery',
          name: 'Mystery Symbol',
          description: 'Include Mystery symbol that reveals as random symbol',
          defaultValue: false,
          group: 'Special Symbols',
          order: 13,
        ),

        // ========== Symbol Land Sound Mode ==========
        BlockOptionFactory.dropdown(
          id: 'symbolLandMode',
          name: 'Symbol Land Sounds',
          description: 'How symbol landing sounds are played',
          choices: [
            const OptionChoice(
              value: 'none',
              label: 'None',
              description: 'No symbol landing sounds',
            ),
            const OptionChoice(
              value: 'special_only',
              label: 'Special Only',
              description: 'Only special symbols (Wild, Scatter, etc.)',
            ),
            const OptionChoice(
              value: 'high_and_special',
              label: 'High + Special',
              description: 'High pay and special symbols',
            ),
            const OptionChoice(
              value: 'all',
              label: 'All Symbols',
              description: 'Every symbol has a landing sound',
            ),
          ],
          defaultValue: 'special_only',
          group: 'Audio',
          order: 14,
        ),

        // ========== Win Symbol Highlight ==========
        BlockOptionFactory.toggle(
          id: 'winHighlight',
          name: 'Win Symbol Highlight',
          description: 'Play sound when winning symbols are highlighted',
          defaultValue: true,
          group: 'Audio',
          order: 15,
        ),
      ];

  @override
  List<BlockDependency> createDependencies() => [
        BlockDependency.requires(
          source: id,
          target: 'game_core',
          description: 'Symbol Set requires Game Core',
        ),
        BlockDependency.requires(
          source: id,
          target: 'grid',
          description: 'Symbol Set requires Grid',
        ),
      ];

  @override
  List<GeneratedStage> generateStages() {
    final stages = <GeneratedStage>[];
    final landMode = getOptionValue<String>('symbolLandMode') ?? 'special_only';
    final hasHighlight = getOptionValue<bool>('winHighlight') ?? true;

    // ========== Special Symbol Landing ==========
    if (hasWild) {
      stages.add(const GeneratedStage(
        name: 'WILD_LAND',
        description: 'Wild symbol lands on reel',
        bus: 'sfx',
        priority: 70,
        pooled: true,
        sourceBlockId: 'symbol_set',
        category: 'Symbols & Lands',
      ));
    }

    if (hasScatter) {
      stages.add(const GeneratedStage(
        name: 'SCATTER_LAND',
        description: 'Scatter symbol lands on reel',
        bus: 'sfx',
        priority: 75,
        pooled: true,
        sourceBlockId: 'symbol_set',
        category: 'Symbols & Lands',
      ));
    }

    if (hasBonus) {
      stages.add(const GeneratedStage(
        name: 'BONUS_LAND',
        description: 'Bonus symbol lands on reel',
        bus: 'sfx',
        priority: 72,
        pooled: true,
        sourceBlockId: 'symbol_set',
        category: 'Symbols & Lands',
      ));
    }

    if (hasCoin) {
      stages.add(const GeneratedStage(
        name: 'COIN_LAND',
        description: 'Coin symbol lands on reel',
        bus: 'sfx',
        priority: 68,
        pooled: true,
        sourceBlockId: 'symbol_set',
        category: 'Symbols & Lands',
      ));
    }

    if (hasCollector) {
      stages.add(const GeneratedStage(
        name: 'COLLECTOR_LAND',
        description: 'Collector symbol lands on reel',
        bus: 'sfx',
        priority: 65,
        pooled: true,
        sourceBlockId: 'symbol_set',
        category: 'Symbols & Lands',
      ));
    }

    if (hasMystery) {
      stages.add(const GeneratedStage(
        name: 'MYSTERY_LAND',
        description: 'Mystery symbol lands on reel',
        bus: 'sfx',
        priority: 67,
        pooled: true,
        sourceBlockId: 'symbol_set',
        category: 'Symbols & Lands',
      ));
      stages.add(const GeneratedStage(
        name: 'MYSTERY_REVEAL',
        description: 'Mystery symbol reveals its value',
        bus: 'sfx',
        priority: 66,
        sourceBlockId: 'symbol_set',
        category: 'Symbols & Lands',
      ));
    }

    // ========== Regular Symbol Landing (based on mode) ==========
    if (landMode == 'high_and_special' || landMode == 'all') {
      // High pay symbols
      for (int i = 0; i < highPayCount; i++) {
        stages.add(GeneratedStage(
          name: 'SYMBOL_LAND_HP${i + 1}',
          description: 'High pay symbol ${i + 1} lands',
          bus: 'sfx',
          priority: 55,
          pooled: true,
          sourceBlockId: id,
          category: 'Symbols & Lands',
        ));
      }
      // Premium symbols
      for (int i = 0; i < premiumCount; i++) {
        stages.add(GeneratedStage(
          name: 'SYMBOL_LAND_PREMIUM${i + 1}',
          description: 'Premium symbol ${i + 1} lands',
          bus: 'sfx',
          priority: 58,
          pooled: true,
          sourceBlockId: id,
          category: 'Symbols & Lands',
        ));
      }
    }

    if (landMode == 'all') {
      // Medium pay symbols
      for (int i = 0; i < mediumPayCount; i++) {
        stages.add(GeneratedStage(
          name: 'SYMBOL_LAND_MP${i + 1}',
          description: 'Medium pay symbol ${i + 1} lands',
          bus: 'sfx',
          priority: 50,
          pooled: true,
          sourceBlockId: id,
          category: 'Symbols & Lands',
        ));
      }
      // Low pay symbols
      for (int i = 0; i < lowPayCount; i++) {
        stages.add(GeneratedStage(
          name: 'SYMBOL_LAND_LP${i + 1}',
          description: 'Low pay symbol ${i + 1} lands',
          bus: 'sfx',
          priority: 45,
          pooled: true,
          sourceBlockId: id,
          category: 'Symbols & Lands',
        ));
      }
    }

    // Generic symbol land (fallback)
    stages.add(const GeneratedStage(
      name: 'SYMBOL_LAND',
      description: 'Generic symbol landing (fallback)',
      bus: 'sfx',
      priority: 40,
      pooled: true,
      sourceBlockId: 'symbol_set',
      category: 'Symbols & Lands',
    ));

    // ========== Win Symbol Highlight ==========
    if (hasHighlight) {
      stages.add(const GeneratedStage(
        name: 'WIN_SYMBOL_HIGHLIGHT',
        description: 'Winning symbol highlight animation',
        bus: 'sfx',
        priority: 60,
        pooled: true,
        sourceBlockId: 'symbol_set',
        category: 'Win Presentation',
      ));

      // Per-symbol highlight stages for special symbols
      if (hasWild) {
        stages.add(const GeneratedStage(
          name: 'WIN_SYMBOL_HIGHLIGHT_WILD',
          description: 'Wild symbol win highlight',
          bus: 'sfx',
          priority: 62,
          pooled: true,
          sourceBlockId: 'symbol_set',
          category: 'Win Presentation',
        ));
      }
    }

    return stages;
  }

  @override
  List<String> get pooledStages {
    final pools = <String>[
      'SYMBOL_LAND',
      'WIN_SYMBOL_HIGHLIGHT',
    ];

    if (hasWild) {
      pools.add('WILD_LAND');
      pools.add('WIN_SYMBOL_HIGHLIGHT_WILD');
    }
    if (hasScatter) pools.add('SCATTER_LAND');
    if (hasBonus) pools.add('BONUS_LAND');
    if (hasCoin) pools.add('COIN_LAND');
    if (hasCollector) pools.add('COLLECTOR_LAND');
    if (hasMystery) pools.add('MYSTERY_LAND');

    return pools;
  }

  @override
  String getBusForStage(String stageName) => 'sfx';

  @override
  int getPriorityForStage(String stageName) {
    if (stageName.contains('SCATTER')) return 75;
    if (stageName.contains('BONUS')) return 72;
    if (stageName.contains('WILD')) return 70;
    if (stageName.contains('COIN')) return 68;
    if (stageName.contains('MYSTERY')) return 67;
    if (stageName.contains('COLLECTOR')) return 65;
    if (stageName.contains('WIN_SYMBOL')) return 60;
    if (stageName.contains('PREMIUM')) return 58;
    if (stageName.contains('HP')) return 55;
    if (stageName.contains('MP')) return 50;
    if (stageName.contains('LP')) return 45;
    return 40;
  }

  // ============================================================================
  // Convenience Getters
  // ============================================================================

  /// Get low pay symbol count.
  int get lowPayCount => getOptionValue<int>('lowPayCount') ?? 4;

  /// Get medium pay symbol count.
  int get mediumPayCount => getOptionValue<int>('mediumPayCount') ?? 2;

  /// Get high pay symbol count.
  int get highPayCount => getOptionValue<int>('highPayCount') ?? 2;

  /// Get premium symbol count.
  int get premiumCount => getOptionValue<int>('premiumCount') ?? 1;

  /// Total regular symbol count.
  int get totalRegularSymbols =>
      lowPayCount + mediumPayCount + highPayCount + premiumCount;

  /// Whether Wild symbol is enabled.
  bool get hasWild => getOptionValue<bool>('hasWild') ?? true;

  /// Whether Wild has multiplier.
  bool get hasWildMultiplier => getOptionValue<bool>('wildMultiplier') ?? false;

  /// Get Wild multiplier values.
  List<int> get wildMultiplierValues {
    final values = getOptionValue<List<dynamic>>('wildMultiplierValues');
    if (values == null) return [2, 3, 5];
    return values.cast<int>();
  }

  /// Whether Scatter symbol is enabled.
  bool get hasScatter => getOptionValue<bool>('hasScatter') ?? true;

  /// Get Scatter trigger count.
  int get scatterTriggerCount => getOptionValue<int>('scatterTriggerCount') ?? 3;

  /// Whether Bonus symbol is enabled.
  bool get hasBonus => getOptionValue<bool>('hasBonus') ?? false;

  /// Whether Coin symbol is enabled (Hold & Win).
  bool get hasCoin => getOptionValue<bool>('hasCoin') ?? false;

  /// Whether Collector symbol is enabled.
  bool get hasCollector => getOptionValue<bool>('hasCollector') ?? false;

  /// Whether Mystery symbol is enabled.
  bool get hasMystery => getOptionValue<bool>('hasMystery') ?? false;

  /// Total special symbol count.
  int get totalSpecialSymbols {
    int count = 0;
    if (hasWild) count++;
    if (hasScatter) count++;
    if (hasBonus) count++;
    if (hasCoin) count++;
    if (hasCollector) count++;
    if (hasMystery) count++;
    return count;
  }

  /// Total symbol count.
  int get totalSymbols => totalRegularSymbols + totalSpecialSymbols;

  /// Get symbol land mode.
  String get symbolLandMode =>
      getOptionValue<String>('symbolLandMode') ?? 'special_only';

  /// Whether win highlight is enabled.
  bool get hasWinHighlight => getOptionValue<bool>('winHighlight') ?? true;

  /// Get list of all enabled special symbol types.
  List<SpecialSymbolType> get enabledSpecialSymbols {
    final types = <SpecialSymbolType>[];
    if (hasWild) types.add(SpecialSymbolType.wild);
    if (hasScatter) types.add(SpecialSymbolType.scatter);
    if (hasBonus) types.add(SpecialSymbolType.bonus);
    if (hasCoin) types.add(SpecialSymbolType.coin);
    if (hasCollector) types.add(SpecialSymbolType.collector);
    if (hasMystery) types.add(SpecialSymbolType.mystery);
    return types;
  }
}
