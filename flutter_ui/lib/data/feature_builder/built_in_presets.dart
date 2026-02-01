// ============================================================================
// FluxForge Studio — Built-in Feature Builder Presets
// ============================================================================
// P13.9.9: Additional built-in presets for Feature Builder
// Provides ready-to-use configurations for common slot game types.
// ============================================================================

import '../../models/feature_builder/feature_preset.dart';

/// Built-in presets for the Feature Builder.
///
/// These presets provide starting configurations for common slot game types.
/// Users can apply a preset and then customize it further.
class BuiltInPresets {
  BuiltInPresets._();

  /// All built-in presets.
  static List<FeaturePreset> get all => [
        classic5x3,
        ways243,
        megaways117649,
        clusterPays,
        holdAndWin,
        cascadingReels,
        jackpotNetwork,
        bonusBuy,
        // P13.9.9: Additional presets
        anticipationFocus,
        wildHeavy,
        bonusHeavy,
        multiplierFocus,
        jackpotFocus,
        fullFeatureUltra,
      ];

  /// Get a preset by ID.
  static FeaturePreset? getById(String id) {
    return all.where((p) => p.id == id).firstOrNull;
  }

  /// Get presets by category.
  static List<FeaturePreset> getByCategory(PresetCategory category) {
    return all.where((p) => p.category == category).toList();
  }

  // ============================================================================
  // Classic Presets (1-8)
  // ============================================================================

  /// Classic 5x3 slot with paylines.
  static final classic5x3 = FeaturePreset(
    id: 'classic_5x3',
    name: 'Classic 5x3',
    description: 'Traditional 5-reel, 3-row slot with 10-20 paylines',
    category: PresetCategory.classic,
    isBuiltIn: true,
    tags: ['classic', 'paylines', 'traditional'],
    blocks: {
      'game_core': const BlockPresetData(isEnabled: true, options: {
        'payModel': 'paylines',
        'volatility': 'medium',
      }),
      'grid': const BlockPresetData(isEnabled: true, options: {
        'reels': 5,
        'rows': 3,
        'paylines': 10,
      }),
      'symbol_set': const BlockPresetData(isEnabled: true, options: {
        'hasWild': true,
        'hasScatter': true,
      }),
      'free_spins': const BlockPresetData(isEnabled: true, options: {
        'triggerCount': 3,
        'spinCount': 10,
      }),
      'win_presentation': const BlockPresetData(isEnabled: true),
    },
  );

  /// 243 Ways slot.
  static final ways243 = FeaturePreset(
    id: 'ways_243',
    name: '243 Ways',
    description: 'Modern 5x3 with 243 ways to win and multiplier wilds',
    category: PresetCategory.video,
    isBuiltIn: true,
    tags: ['ways', '243', 'modern'],
    blocks: {
      'game_core': const BlockPresetData(isEnabled: true, options: {
        'payModel': 'ways',
        'volatility': 'medium_high',
      }),
      'grid': const BlockPresetData(isEnabled: true, options: {
        'reels': 5,
        'rows': 3,
        'ways': 243,
      }),
      'symbol_set': const BlockPresetData(isEnabled: true, options: {
        'hasWild': true,
        'hasScatter': true,
      }),
      'wild_features': const BlockPresetData(isEnabled: true, options: {
        'expansion': 'disabled',
        'multiplier_range': [2, 3],
      }),
      'free_spins': const BlockPresetData(isEnabled: true),
      'win_presentation': const BlockPresetData(isEnabled: true),
    },
  );

  /// Megaways 117,649.
  static final megaways117649 = FeaturePreset(
    id: 'megaways_117649',
    name: 'Megaways 117,649',
    description: 'Dynamic 6-reel Megaways with cascades and free spins',
    category: PresetCategory.megaways,
    isBuiltIn: true,
    tags: ['megaways', 'dynamic', 'cascades'],
    blocks: {
      'game_core': const BlockPresetData(isEnabled: true, options: {
        'payModel': 'megaways',
        'volatility': 'high',
      }),
      'grid': const BlockPresetData(isEnabled: true, options: {
        'reels': 6,
        'rows': 7,
        'isDynamic': true,
      }),
      'symbol_set': const BlockPresetData(isEnabled: true, options: {
        'hasWild': true,
        'hasScatter': true,
      }),
      'cascades': const BlockPresetData(isEnabled: true, options: {
        'multiplierType': 'progressive',
        'maxMultiplier': 10,
      }),
      'free_spins': const BlockPresetData(isEnabled: true),
      'win_presentation': const BlockPresetData(isEnabled: true),
    },
  );

  /// Cluster Pays.
  static final clusterPays = FeaturePreset(
    id: 'cluster_pays',
    name: 'Cluster Pays',
    description: '7x7 cluster pays with cascades',
    category: PresetCategory.cluster,
    isBuiltIn: true,
    tags: ['cluster', 'cascades', 'large_grid'],
    blocks: {
      'game_core': const BlockPresetData(isEnabled: true, options: {
        'payModel': 'cluster',
        'volatility': 'medium_high',
      }),
      'grid': const BlockPresetData(isEnabled: true, options: {
        'reels': 7,
        'rows': 7,
      }),
      'symbol_set': const BlockPresetData(isEnabled: true, options: {
        'hasWild': true,
      }),
      'cascades': const BlockPresetData(isEnabled: true),
      'free_spins': const BlockPresetData(isEnabled: true),
      'win_presentation': const BlockPresetData(isEnabled: true),
    },
  );

  /// Hold & Win.
  static final holdAndWin = FeaturePreset(
    id: 'hold_and_win',
    name: 'Hold & Win',
    description: 'Lightning Link style with coins, respins, and 4-tier jackpots',
    category: PresetCategory.holdWin,
    isBuiltIn: true,
    tags: ['hold_win', 'jackpots', 'coins'],
    blocks: {
      'game_core': const BlockPresetData(isEnabled: true, options: {
        'payModel': 'paylines',
        'volatility': 'high',
      }),
      'grid': const BlockPresetData(isEnabled: true, options: {
        'reels': 5,
        'rows': 3,
      }),
      'symbol_set': const BlockPresetData(isEnabled: true, options: {
        'hasWild': true,
        'hasBonus': true,
        'hasCoin': true,
      }),
      'hold_and_win': const BlockPresetData(isEnabled: true, options: {
        'respinCount': 3,
        'jackpotTiers': 4,
      }),
      'jackpot': const BlockPresetData(isEnabled: true, options: {
        'type': 'local',
        'tiers': 4,
      }),
      'win_presentation': const BlockPresetData(isEnabled: true),
      'music_states': const BlockPresetData(isEnabled: true),
    },
  );

  /// Cascading Reels.
  static final cascadingReels = FeaturePreset(
    id: 'cascading_reels',
    name: 'Cascading Reels',
    description: '5x4 tumble with escalating multipliers',
    category: PresetCategory.video,
    isBuiltIn: true,
    tags: ['cascades', 'tumble', 'multipliers'],
    blocks: {
      'game_core': const BlockPresetData(isEnabled: true, options: {
        'payModel': 'ways',
        'volatility': 'high',
      }),
      'grid': const BlockPresetData(isEnabled: true, options: {
        'reels': 5,
        'rows': 4,
      }),
      'symbol_set': const BlockPresetData(isEnabled: true, options: {
        'hasWild': true,
        'hasScatter': true,
      }),
      'cascades': const BlockPresetData(isEnabled: true, options: {
        'multiplierType': 'progressive',
        'maxCascades': 10,
        'multiplierProgression': [1, 2, 3, 5, 10],
      }),
      'free_spins': const BlockPresetData(isEnabled: true),
      'multiplier': const BlockPresetData(isEnabled: true, options: {
        'type': 'cascade',
        'maxMultiplier': 10,
      }),
      'win_presentation': const BlockPresetData(isEnabled: true),
    },
  );

  /// Jackpot Network.
  static final jackpotNetwork = FeaturePreset(
    id: 'jackpot_network',
    name: 'Jackpot Network',
    description: 'Progressive jackpots with wheel bonus',
    category: PresetCategory.jackpot,
    isBuiltIn: true,
    tags: ['jackpot', 'progressive', 'wheel'],
    blocks: {
      'game_core': const BlockPresetData(isEnabled: true, options: {
        'payModel': 'paylines',
        'volatility': 'very_high',
      }),
      'grid': const BlockPresetData(isEnabled: true, options: {
        'reels': 5,
        'rows': 3,
      }),
      'symbol_set': const BlockPresetData(isEnabled: true, options: {
        'hasWild': true,
        'hasScatter': true,
        'hasBonus': true,
      }),
      'jackpot': const BlockPresetData(isEnabled: true, options: {
        'type': 'progressive',
        'tiers': 5,
        'contributionPercent': 1.0,
      }),
      'bonus_game': const BlockPresetData(isEnabled: true, options: {
        'type': 'wheel',
      }),
      'win_presentation': const BlockPresetData(isEnabled: true),
      'music_states': const BlockPresetData(isEnabled: true),
    },
  );

  /// Bonus Buy.
  static final bonusBuy = FeaturePreset(
    id: 'bonus_buy',
    name: 'Bonus Buy',
    description: '5x4 video slot with feature buy and multiplier wilds',
    category: PresetCategory.video,
    isBuiltIn: true,
    tags: ['bonus_buy', 'feature_buy', 'modern'],
    blocks: {
      'game_core': const BlockPresetData(isEnabled: true, options: {
        'payModel': 'ways',
        'volatility': 'high',
      }),
      'grid': const BlockPresetData(isEnabled: true, options: {
        'reels': 5,
        'rows': 4,
      }),
      'symbol_set': const BlockPresetData(isEnabled: true, options: {
        'hasWild': true,
        'hasScatter': true,
      }),
      'wild_features': const BlockPresetData(isEnabled: true, options: {
        'expansion': 'full_reel',
        'multiplier_range': [2, 3, 5],
      }),
      'free_spins': const BlockPresetData(isEnabled: true, options: {
        'hasFeatureBuy': true,
        'featureBuyCost': 100,
      }),
      'win_presentation': const BlockPresetData(isEnabled: true),
    },
  );

  // ============================================================================
  // P13.9.9: Additional Presets (13-18)
  // ============================================================================

  /// Preset 13: Anticipation Focus
  /// Tension-heavy slot with escalating anticipation on near-triggers.
  static final anticipationFocus = FeaturePreset(
    id: 'anticipation_focus',
    name: 'Anticipation Focus',
    description: 'Tension-heavy slot with escalating anticipation',
    category: PresetCategory.video,
    isBuiltIn: true,
    tags: ['anticipation', 'tension', 'dramatic'],
    blocks: {
      'game_core': const BlockPresetData(isEnabled: true, options: {
        'payModel': 'ways',
        'volatility': 'high',
      }),
      'grid': const BlockPresetData(isEnabled: true, options: {
        'reels': 5,
        'rows': 3,
      }),
      'symbol_set': const BlockPresetData(isEnabled: true, options: {
        'hasWild': true,
        'hasScatter': true,
        'hasBonus': true,
      }),
      'free_spins': const BlockPresetData(isEnabled: true, options: {
        'triggerCount': 3,
        'spinCount': 10,
      }),
      'anticipation': const BlockPresetData(isEnabled: true, options: {
        'pattern': 'tip_a',
        'tensionLevels': 4,
        'audioProfile': 'dramatic',
        'tensionEscalationEnabled': true,
        'reelSlowdownFactor': 30.0,
        'visualEffect': 'glow',
        'perReelAudio': true,
        'audioPitchEscalation': true,
        'audioVolumeEscalation': true,
      }),
      'win_presentation': const BlockPresetData(isEnabled: true),
      'music_states': const BlockPresetData(isEnabled: true),
    },
  );

  /// Preset 14: Wild Heavy
  /// Wild-centric gameplay with expansion, sticky, and multipliers.
  static final wildHeavy = FeaturePreset(
    id: 'wild_heavy',
    name: 'Wild Heavy',
    description: 'Wild-centric gameplay with expansion and multipliers',
    category: PresetCategory.video,
    isBuiltIn: true,
    tags: ['wild', 'expansion', 'multipliers', 'sticky'],
    blocks: {
      'game_core': const BlockPresetData(isEnabled: true, options: {
        'payModel': 'ways',
        'volatility': 'high',
      }),
      'grid': const BlockPresetData(isEnabled: true, options: {
        'reels': 5,
        'rows': 4,
      }),
      'symbol_set': const BlockPresetData(isEnabled: true, options: {
        'hasWild': true,
        'hasScatter': true,
      }),
      'free_spins': const BlockPresetData(isEnabled: true, options: {
        'triggerCount': 3,
        'spinCount': 12,
      }),
      'wild_features': const BlockPresetData(isEnabled: true, options: {
        'expansion': 'full_reel',
        'sticky_duration': 3,
        'multiplier_range': [2, 3, 5],
        'walking_direction': 'none',
        'has_expansion_sound': true,
        'has_sticky_sound': true,
        'has_multiplier_sound': true,
      }),
      'win_presentation': const BlockPresetData(isEnabled: true),
    },
  );

  /// Preset 15: Bonus Heavy
  /// Multi-stage bonus games with multipliers.
  static final bonusHeavy = FeaturePreset(
    id: 'bonus_heavy',
    name: 'Bonus Heavy',
    description: 'Multi-stage bonus games with multipliers',
    category: PresetCategory.video,
    isBuiltIn: true,
    tags: ['bonus', 'pick', 'multipliers', 'stages'],
    blocks: {
      'game_core': const BlockPresetData(isEnabled: true, options: {
        'payModel': 'paylines',
        'volatility': 'medium_high',
      }),
      'grid': const BlockPresetData(isEnabled: true, options: {
        'reels': 5,
        'rows': 3,
      }),
      'symbol_set': const BlockPresetData(isEnabled: true, options: {
        'hasWild': true,
        'hasBonus': true,
      }),
      'bonus_game': const BlockPresetData(isEnabled: true, options: {
        'type': 'pick',
        'stages': 3,
        'hasMultipliers': true,
      }),
      'multiplier': const BlockPresetData(isEnabled: true, options: {
        'type': 'global',
        'maxMultiplier': 10,
      }),
      'win_presentation': const BlockPresetData(isEnabled: true),
    },
  );

  /// Preset 16: Multiplier Focus
  /// Cascading wins with progressive multipliers.
  static final multiplierFocus = FeaturePreset(
    id: 'multiplier_focus',
    name: 'Multiplier Focus',
    description: 'Cascading wins with progressive multipliers',
    category: PresetCategory.video,
    isBuiltIn: true,
    tags: ['multipliers', 'cascades', 'progressive'],
    blocks: {
      'game_core': const BlockPresetData(isEnabled: true, options: {
        'payModel': 'ways',
        'volatility': 'high',
      }),
      'grid': const BlockPresetData(isEnabled: true, options: {
        'reels': 6,
        'rows': 5,
      }),
      'symbol_set': const BlockPresetData(isEnabled: true, options: {
        'hasWild': true,
        'hasScatter': true,
      }),
      'cascades': const BlockPresetData(isEnabled: true, options: {
        'maxCascades': 10,
        'multiplierType': 'progressive',
        'multiplierProgression': [1, 2, 3, 5, 10],
        'multiplierIncrement': 1,
        'maxMultiplier': 10,
      }),
      'multiplier': const BlockPresetData(isEnabled: true, options: {
        'type': 'cascade',
        'maxMultiplier': 10,
      }),
      'win_presentation': const BlockPresetData(isEnabled: true),
    },
  );

  /// Preset 17: Jackpot Focus
  /// Progressive jackpots with Hold & Win trigger.
  static final jackpotFocus = FeaturePreset(
    id: 'jackpot_focus',
    name: 'Jackpot Focus',
    description: 'Progressive jackpots with Hold & Win trigger',
    category: PresetCategory.jackpot,
    isBuiltIn: true,
    tags: ['jackpot', 'progressive', 'hold_win'],
    blocks: {
      'game_core': const BlockPresetData(isEnabled: true, options: {
        'payModel': 'paylines',
        'volatility': 'very_high',
      }),
      'grid': const BlockPresetData(isEnabled: true, options: {
        'reels': 5,
        'rows': 3,
      }),
      'symbol_set': const BlockPresetData(isEnabled: true, options: {
        'hasWild': true,
        'hasScatter': true,
        'hasBonus': true,
        'hasCoin': true,
      }),
      'jackpot': const BlockPresetData(isEnabled: true, options: {
        'type': 'progressive',
        'tiers': 5,
        'contributionPercent': 1.0,
      }),
      'hold_and_win': const BlockPresetData(isEnabled: true, options: {
        'respinCount': 3,
        'jackpotTiers': 4,
      }),
      'win_presentation': const BlockPresetData(isEnabled: true),
      'music_states': const BlockPresetData(isEnabled: true),
    },
  );

  /// Preset 18: Full Feature Ultra
  /// Everything enabled — for testing and experimentation.
  static final fullFeatureUltra = FeaturePreset(
    id: 'full_feature_ultra',
    name: 'Full Feature Ultra',
    description: 'Everything enabled — for testing and experimentation',
    category: PresetCategory.test,
    isBuiltIn: true,
    tags: ['all', 'testing', 'ultra', 'complete'],
    blocks: {
      // ========== Core Blocks ==========
      'game_core': const BlockPresetData(isEnabled: true, options: {
        'payModel': 'ways',
        'volatility': 'high',
      }),
      'grid': const BlockPresetData(isEnabled: true, options: {
        'reels': 5,
        'rows': 4,
      }),
      'symbol_set': const BlockPresetData(isEnabled: true, options: {
        'hasWild': true,
        'hasScatter': true,
        'hasBonus': true,
        'hasCoin': true,
      }),

      // ========== Feature Blocks ==========
      'free_spins': const BlockPresetData(isEnabled: true, options: {
        'triggerCount': 3,
        'spinCount': 10,
        'hasFeatureBuy': true,
      }),
      'cascades': const BlockPresetData(isEnabled: true, options: {
        'multiplierType': 'progressive',
        'maxCascades': 10,
      }),
      'hold_and_win': const BlockPresetData(isEnabled: true, options: {
        'respinCount': 3,
      }),
      'bonus_game': const BlockPresetData(isEnabled: true, options: {
        'type': 'pick',
        'stages': 2,
      }),
      'jackpot': const BlockPresetData(isEnabled: true, options: {
        'type': 'local',
        'tiers': 4,
      }),
      'multiplier': const BlockPresetData(isEnabled: true, options: {
        'type': 'cascade',
        'maxMultiplier': 10,
      }),
      'respin': const BlockPresetData(isEnabled: false), // Conflicts with hold_and_win
      'gambling': const BlockPresetData(isEnabled: true),
      'collector': const BlockPresetData(isEnabled: true),

      // ========== Bonus Blocks ==========
      'anticipation': const BlockPresetData(isEnabled: true, options: {
        'pattern': 'tip_a',
        'tensionLevels': 4,
        'audioProfile': 'dramatic',
      }),
      'wild_features': const BlockPresetData(isEnabled: true, options: {
        'expansion': 'full_reel',
        'sticky_duration': 2,
        'multiplier_range': [2, 3],
      }),

      // ========== Presentation Blocks ==========
      'win_presentation': const BlockPresetData(isEnabled: true),
      'music_states': const BlockPresetData(isEnabled: true),
      'transitions': const BlockPresetData(isEnabled: true),
    },
  );
}
