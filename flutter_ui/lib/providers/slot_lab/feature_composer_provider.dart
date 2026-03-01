/// Feature Composer Provider — Trostepeni Stage System Layer 2
///
/// Dynamically composes stage sets from selected game mechanics.
/// Engine Core stages (Layer 1) are always present and locked.
/// Feature-derived stages (Layer 2) appear/disappear based on enabled mechanics.
///
/// Integration:
/// - Feeds TriggerLayerProvider with hook mappings for new stages
/// - Updates StateGateProvider with valid transitions for mechanics
/// - Drives UltimateAudioPanel V11 dynamic filtering
///
/// See: .claude/architecture/TROSTEPENI_STAGE_SYSTEM.md

import 'package:flutter/foundation.dart';
import '../../models/stage_models.dart';

// =============================================================================
// STAGE LAYER CLASSIFICATION
// =============================================================================

/// Which tier a stage belongs to
enum StageLayer {
  /// Layer 1: Engine Core — locked, always present
  engineCore,
  /// Layer 2: Feature-derived — appears when mechanic is enabled
  featureDerived,
  /// Always visible non-mechanic stages (Music, UI)
  alwaysVisible,
}

// =============================================================================
// SLOT MECHANIC (superset of FeatureType — includes core mechanics)
// =============================================================================

/// Game mechanics that generate stages when enabled.
/// Extends beyond FeatureType to include base game mechanics like cascading.
enum SlotMechanic {
  cascading('Cascading Wins'),
  freeSpins('Free Spins'),
  holdAndWin('Hold & Win'),
  pickBonus('Pick Bonus'),
  wheelBonus('Wheel Bonus'),
  jackpot('Jackpots'),
  gamble('Gamble'),
  megaways('Megaways'),
  nudgeRespin('Nudge / Respin'),
  expandingWilds('Expanding Wilds'),
  stickyWilds('Sticky Wilds'),
  multiplierTrail('Multiplier Trail');

  const SlotMechanic(this.displayName);
  final String displayName;

  /// Stages generated when this mechanic is enabled
  List<ComposedStage> get generatedStages => _mechanicStages[this] ?? [];

  /// Hook names registered for this mechanic
  List<String> get hookNames => generatedStages
      .expand((s) => s.hooks)
      .toList();

  /// Map to existing FeatureType (if applicable)
  FeatureType? get featureType => switch (this) {
    cascading => FeatureType.cascade,
    freeSpins => FeatureType.freeSpins,
    holdAndWin => FeatureType.holdAndSpin,
    pickBonus => FeatureType.pickBonus,
    wheelBonus => FeatureType.wheelBonus,
    megaways => FeatureType.megaways,
    expandingWilds => FeatureType.expandingWilds,
    stickyWilds => FeatureType.stickyWilds,
    multiplierTrail => FeatureType.multiplier,
    _ => null,
  };
}

// =============================================================================
// COMPOSED STAGE MODEL
// =============================================================================

/// A stage in the composed state machine
class ComposedStage {
  /// Unique stage ID (e.g. 'CASCADE_STEP', 'SPIN_START')
  final String id;

  /// Human-readable name
  final String displayName;

  /// Which layer this stage belongs to
  final StageLayer layer;

  /// Which mechanic generated this stage (null for Engine Core)
  final SlotMechanic? mechanic;

  /// Middleware hooks mapped to this stage
  final List<String> hooks;

  /// Whether this stage is locked (Engine Core = true)
  final bool locked;

  /// Display sort order within its group
  final int sortOrder;

  /// Audio bus suggestion
  final String suggestedBus;

  /// Priority level
  final String priority;

  const ComposedStage({
    required this.id,
    required this.displayName,
    required this.layer,
    this.mechanic,
    this.hooks = const [],
    this.locked = false,
    this.sortOrder = 0,
    this.suggestedBus = 'sfx',
    this.priority = 'P1',
  });
}

// =============================================================================
// ENGINE CORE STAGES (Layer 1 — always present)
// =============================================================================

const List<ComposedStage> _engineCoreStages = [
  // ═══ Spin Lifecycle ═══
  ComposedStage(
    id: 'SPIN_START', displayName: 'Spin Start',
    layer: StageLayer.engineCore, locked: true, sortOrder: 0,
    hooks: ['onSpinStart'], suggestedBus: 'reels', priority: 'P0',
  ),
  ComposedStage(
    id: 'REEL_SPIN_LOOP', displayName: 'Reel Spin Loop',
    layer: StageLayer.engineCore, locked: true, sortOrder: 1,
    hooks: ['onReelSpinLoop'], suggestedBus: 'reels', priority: 'P0',
  ),
  ComposedStage(
    id: 'SPIN_END', displayName: 'Spin End',
    layer: StageLayer.engineCore, locked: true, sortOrder: 2,
    hooks: ['onSpinEnd'], suggestedBus: 'reels', priority: 'P0',
  ),

  // ═══ Reel Stops (per-reel) ═══
  ComposedStage(
    id: 'REEL_STOP_0', displayName: 'Reel Stop 1',
    layer: StageLayer.engineCore, locked: true, sortOrder: 3,
    hooks: ['onReelStop_r1'], suggestedBus: 'reels', priority: 'P0',
  ),
  ComposedStage(
    id: 'REEL_STOP_1', displayName: 'Reel Stop 2',
    layer: StageLayer.engineCore, locked: true, sortOrder: 4,
    hooks: ['onReelStop_r2'], suggestedBus: 'reels', priority: 'P0',
  ),
  ComposedStage(
    id: 'REEL_STOP_2', displayName: 'Reel Stop 3',
    layer: StageLayer.engineCore, locked: true, sortOrder: 5,
    hooks: ['onReelStop_r3'], suggestedBus: 'reels', priority: 'P0',
  ),
  ComposedStage(
    id: 'REEL_STOP_3', displayName: 'Reel Stop 4',
    layer: StageLayer.engineCore, locked: true, sortOrder: 6,
    hooks: ['onReelStop_r4'], suggestedBus: 'reels', priority: 'P0',
  ),
  ComposedStage(
    id: 'REEL_STOP_4', displayName: 'Reel Stop 5',
    layer: StageLayer.engineCore, locked: true, sortOrder: 7,
    hooks: ['onReelStop_r5'], suggestedBus: 'reels', priority: 'P0',
  ),

  // ═══ Symbol Landing ═══
  ComposedStage(
    id: 'SYMBOL_LAND', displayName: 'Symbol Land',
    layer: StageLayer.engineCore, locked: true, sortOrder: 8,
    hooks: ['onSymbolLand'], suggestedBus: 'reels', priority: 'P0',
  ),
  ComposedStage(
    id: 'SYMBOL_LAND_WILD', displayName: 'Wild Symbol Land',
    layer: StageLayer.engineCore, locked: true, sortOrder: 9,
    hooks: ['onSymbolLand'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'SYMBOL_LAND_SCATTER', displayName: 'Scatter Symbol Land',
    layer: StageLayer.engineCore, locked: true, sortOrder: 10,
    hooks: ['onSymbolLand'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'SYMBOL_LAND_BONUS', displayName: 'Bonus Symbol Land',
    layer: StageLayer.engineCore, locked: true, sortOrder: 11,
    hooks: ['onSymbolLand'], suggestedBus: 'sfx', priority: 'P0',
  ),

  // ═══ Win Evaluation & Tiers ═══
  ComposedStage(
    id: 'WIN_TIER_1', displayName: 'Win Tier 1',
    layer: StageLayer.engineCore, locked: true, sortOrder: 20,
    hooks: ['onWinEvaluate_tier1'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'WIN_TIER_2', displayName: 'Win Tier 2',
    layer: StageLayer.engineCore, locked: true, sortOrder: 21,
    hooks: ['onWinEvaluate_tier2'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'WIN_TIER_3', displayName: 'Win Tier 3',
    layer: StageLayer.engineCore, locked: true, sortOrder: 22,
    hooks: ['onWinEvaluate_tier3'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'WIN_TIER_4', displayName: 'Win Tier 4',
    layer: StageLayer.engineCore, locked: true, sortOrder: 23,
    hooks: ['onWinEvaluate_tier4'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'WIN_TIER_5', displayName: 'Win Tier 5',
    layer: StageLayer.engineCore, locked: true, sortOrder: 24,
    hooks: ['onWinEvaluate_tier5'], suggestedBus: 'sfx', priority: 'P0',
  ),

  // ═══ Win Presentation ═══
  ComposedStage(
    id: 'WIN_SYMBOL_HIGHLIGHT', displayName: 'Win Symbol Highlight',
    layer: StageLayer.engineCore, locked: true, sortOrder: 25,
    hooks: ['onWinPresent'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'WIN_LINE_SHOW', displayName: 'Win Line Show',
    layer: StageLayer.engineCore, locked: true, sortOrder: 26,
    hooks: ['onWinPresent'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'WIN_COLLECT', displayName: 'Win Collect',
    layer: StageLayer.engineCore, locked: true, sortOrder: 27,
    hooks: ['onWinCollect'], suggestedBus: 'sfx', priority: 'P0',
  ),

  // ═══ Rollup / Countup ═══
  ComposedStage(
    id: 'ROLLUP_START', displayName: 'Rollup Start',
    layer: StageLayer.engineCore, locked: true, sortOrder: 30,
    hooks: ['onRollupStart'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'ROLLUP_TICK', displayName: 'Rollup Tick',
    layer: StageLayer.engineCore, locked: true, sortOrder: 31,
    hooks: ['onRollupTick'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'ROLLUP_END', displayName: 'Rollup End',
    layer: StageLayer.engineCore, locked: true, sortOrder: 32,
    hooks: ['onRollupEnd'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'COUNTUP_TICK', displayName: 'Countup Tick',
    layer: StageLayer.engineCore, locked: true, sortOrder: 33,
    hooks: ['onCountUpTick'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'COUNTUP_END', displayName: 'Countup End',
    layer: StageLayer.engineCore, locked: true, sortOrder: 34,
    hooks: ['onCountUpEnd'], suggestedBus: 'sfx', priority: 'P0',
  ),

  // ═══ Big Win Presentation ═══
  ComposedStage(
    id: 'BIG_WIN_INTRO', displayName: 'Big Win Intro',
    layer: StageLayer.engineCore, locked: true, sortOrder: 35,
    hooks: ['onBigWinStart'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'BIG_WIN_LOOP', displayName: 'Big Win Loop',
    layer: StageLayer.engineCore, locked: true, sortOrder: 36,
    hooks: ['onBigWinLoop'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'BIG_WIN_COINS', displayName: 'Big Win Coins',
    layer: StageLayer.engineCore, locked: true, sortOrder: 37,
    hooks: ['onBigWinCoins'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'BIG_WIN_END', displayName: 'Big Win End',
    layer: StageLayer.engineCore, locked: true, sortOrder: 38,
    hooks: ['onBigWinEnd'], suggestedBus: 'sfx', priority: 'P0',
  ),

  // ═══ Anticipation & Near Miss ═══
  ComposedStage(
    id: 'ANTICIPATION_ON', displayName: 'Anticipation On',
    layer: StageLayer.engineCore, locked: true, sortOrder: 39,
    hooks: ['onAnticipation'], suggestedBus: 'sfx', priority: 'P0',
  ),
  ComposedStage(
    id: 'NEAR_MISS', displayName: 'Near Miss',
    layer: StageLayer.engineCore, locked: true, sortOrder: 40,
    hooks: ['onNearMiss'], suggestedBus: 'sfx', priority: 'P0',
  ),
];

// =============================================================================
// ALWAYS-VISIBLE STAGES (Music, UI — not mechanic-dependent)
// =============================================================================

const List<ComposedStage> _alwaysVisibleStages = [
  // Music & Ambience (IDs match UltimateAudioPanel PHASE 6 slots)
  ComposedStage(
    id: 'MUSIC_BASE', displayName: 'Base Music',
    layer: StageLayer.alwaysVisible, sortOrder: 100,
    hooks: [], suggestedBus: 'music', priority: 'P1',
  ),
  ComposedStage(
    id: 'MUSIC_LAYER_1', displayName: 'Music Layer 1',
    layer: StageLayer.alwaysVisible, sortOrder: 101,
    hooks: [], suggestedBus: 'music', priority: 'P1',
  ),
  ComposedStage(
    id: 'MUSIC_LAYER_2', displayName: 'Music Layer 2',
    layer: StageLayer.alwaysVisible, sortOrder: 102,
    hooks: [], suggestedBus: 'music', priority: 'P1',
  ),
  ComposedStage(
    id: 'MUSIC_LAYER_3', displayName: 'Music Layer 3',
    layer: StageLayer.alwaysVisible, sortOrder: 103,
    hooks: [], suggestedBus: 'music', priority: 'P1',
  ),
  ComposedStage(
    id: 'MUSIC_FREESPINS', displayName: 'FS Music',
    layer: StageLayer.alwaysVisible, sortOrder: 104,
    hooks: [], suggestedBus: 'music', priority: 'P1',
  ),
  ComposedStage(
    id: 'MUSIC_BONUS', displayName: 'Bonus Music',
    layer: StageLayer.alwaysVisible, sortOrder: 105,
    hooks: [], suggestedBus: 'music', priority: 'P1',
  ),
  ComposedStage(
    id: 'MUSIC_BIG_WIN', displayName: 'Big Win Music',
    layer: StageLayer.alwaysVisible, sortOrder: 106,
    hooks: [], suggestedBus: 'music', priority: 'P1',
  ),
  ComposedStage(
    id: 'AMBIENCE', displayName: 'Ambience',
    layer: StageLayer.alwaysVisible, sortOrder: 103,
    hooks: [], suggestedBus: 'ambience', priority: 'P2',
  ),
  // UI
  ComposedStage(
    id: 'BUTTON_PRESS', displayName: 'Button Press',
    layer: StageLayer.alwaysVisible, sortOrder: 200,
    hooks: ['onButtonPress'], suggestedBus: 'ui', priority: 'P2',
  ),
  ComposedStage(
    id: 'BUTTON_RELEASE', displayName: 'Button Release',
    layer: StageLayer.alwaysVisible, sortOrder: 201,
    hooks: ['onButtonRelease'], suggestedBus: 'ui', priority: 'P2',
  ),
  ComposedStage(
    id: 'POPUP_SHOW', displayName: 'Popup Show',
    layer: StageLayer.alwaysVisible, sortOrder: 202,
    hooks: ['onPopupShow'], suggestedBus: 'ui', priority: 'P2',
  ),
  ComposedStage(
    id: 'POPUP_DISMISS', displayName: 'Popup Dismiss',
    layer: StageLayer.alwaysVisible, sortOrder: 203,
    hooks: ['onPopupDismiss'], suggestedBus: 'ui', priority: 'P2',
  ),
];

// =============================================================================
// MECHANIC → STAGES MAPPING
// =============================================================================

const Map<SlotMechanic, List<ComposedStage>> _mechanicStages = {
  SlotMechanic.cascading: [
    ComposedStage(
      id: 'CASCADE_START', displayName: 'Cascade Start',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.cascading,
      hooks: ['onCascadeStart'], suggestedBus: 'sfx', priority: 'P0', sortOrder: 30,
    ),
    ComposedStage(
      id: 'CASCADE_STEP', displayName: 'Cascade Step',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.cascading,
      hooks: ['onCascadeStep'], suggestedBus: 'sfx', priority: 'P0', sortOrder: 31,
    ),
    ComposedStage(
      id: 'CASCADE_END', displayName: 'Cascade End',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.cascading,
      hooks: ['onCascadeEnd'], suggestedBus: 'sfx', priority: 'P0', sortOrder: 32,
    ),
  ],

  SlotMechanic.freeSpins: [
    ComposedStage(
      id: 'FEATURE_ENTER', displayName: 'Feature Enter',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.freeSpins,
      hooks: ['onFeatureEnter'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 40,
    ),
    ComposedStage(
      id: 'FEATURE_LOOP', displayName: 'Feature Loop',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.freeSpins,
      hooks: ['onFeatureLoop'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 41,
    ),
    ComposedStage(
      id: 'FEATURE_EXIT', displayName: 'Feature Exit',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.freeSpins,
      hooks: ['onFeatureExit'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 42,
    ),
  ],

  SlotMechanic.holdAndWin: [
    ComposedStage(
      id: 'HOLD_WIN_LOCK', displayName: 'Hold & Win Lock',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.holdAndWin,
      hooks: ['onFeatureEnter'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 50,
    ),
    ComposedStage(
      id: 'HOLD_WIN_SPIN', displayName: 'Hold & Win Spin',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.holdAndWin,
      hooks: ['onFeatureLoop'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 51,
    ),
    ComposedStage(
      id: 'HOLD_WIN_REVEAL', displayName: 'Hold & Win Reveal',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.holdAndWin,
      hooks: ['onFeatureExit'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 52,
    ),
  ],

  SlotMechanic.pickBonus: [
    ComposedStage(
      id: 'PICK_START', displayName: 'Pick Start',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.pickBonus,
      hooks: ['onFeatureEnter'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 60,
    ),
    ComposedStage(
      id: 'PICK_REVEAL', displayName: 'Pick Reveal',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.pickBonus,
      hooks: ['onFeatureLoop'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 61,
    ),
    ComposedStage(
      id: 'PICK_END', displayName: 'Pick End',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.pickBonus,
      hooks: ['onFeatureExit'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 62,
    ),
  ],

  SlotMechanic.wheelBonus: [
    ComposedStage(
      id: 'WHEEL_START', displayName: 'Wheel Start',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.wheelBonus,
      hooks: ['onFeatureEnter'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 70,
    ),
    ComposedStage(
      id: 'WHEEL_SPIN', displayName: 'Wheel Spin',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.wheelBonus,
      hooks: ['onFeatureLoop'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 71,
    ),
    ComposedStage(
      id: 'WHEEL_RESULT', displayName: 'Wheel Result',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.wheelBonus,
      hooks: ['onFeatureExit'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 72,
    ),
  ],

  SlotMechanic.jackpot: [
    ComposedStage(
      id: 'JACKPOT_TRIGGER', displayName: 'Jackpot Trigger',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.jackpot,
      hooks: [], suggestedBus: 'sfx', priority: 'P1', sortOrder: 80,
    ),
    ComposedStage(
      id: 'JACKPOT_MINI', displayName: 'Jackpot Mini',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.jackpot,
      hooks: ['onJackpotReveal_mini'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 81,
    ),
    ComposedStage(
      id: 'JACKPOT_MAJOR', displayName: 'Jackpot Major',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.jackpot,
      hooks: ['onJackpotReveal_major'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 82,
    ),
    ComposedStage(
      id: 'JACKPOT_GRAND', displayName: 'Jackpot Grand',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.jackpot,
      hooks: ['onJackpotReveal_grand'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 83,
    ),
  ],

  SlotMechanic.gamble: [
    ComposedStage(
      id: 'GAMBLE_START', displayName: 'Gamble Start',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.gamble,
      hooks: ['onButtonPress'], suggestedBus: 'sfx', priority: 'P2', sortOrder: 90,
    ),
    ComposedStage(
      id: 'GAMBLE_WIN', displayName: 'Gamble Win',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.gamble,
      hooks: [], suggestedBus: 'sfx', priority: 'P2', sortOrder: 91,
    ),
    ComposedStage(
      id: 'GAMBLE_LOSE', displayName: 'Gamble Lose',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.gamble,
      hooks: [], suggestedBus: 'sfx', priority: 'P2', sortOrder: 92,
    ),
  ],

  SlotMechanic.nudgeRespin: [
    ComposedStage(
      id: 'REEL_NUDGE', displayName: 'Reel Nudge',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.nudgeRespin,
      hooks: ['onReelNudge'], suggestedBus: 'reels', priority: 'P1', sortOrder: 35,
    ),
    ComposedStage(
      id: 'RESPIN_START', displayName: 'Respin Start',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.nudgeRespin,
      hooks: ['onSpinStart'], suggestedBus: 'reels', priority: 'P1', sortOrder: 36,
    ),
  ],

  SlotMechanic.megaways: [
    ComposedStage(
      id: 'MEGAWAYS_REVEAL', displayName: 'Megaways Reveal',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.megaways,
      hooks: [], suggestedBus: 'sfx', priority: 'P1', sortOrder: 37,
    ),
  ],

  SlotMechanic.expandingWilds: [
    ComposedStage(
      id: 'WILD_EXPAND', displayName: 'Wild Expand',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.expandingWilds,
      hooks: ['onSymbolLand'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 38,
    ),
  ],

  SlotMechanic.stickyWilds: [
    ComposedStage(
      id: 'WILD_STICKY', displayName: 'Sticky Wild Lock',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.stickyWilds,
      hooks: ['onSymbolLand'], suggestedBus: 'sfx', priority: 'P1', sortOrder: 39,
    ),
  ],

  SlotMechanic.multiplierTrail: [
    ComposedStage(
      id: 'MULTIPLIER_INCREMENT', displayName: 'Multiplier +1',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.multiplierTrail,
      hooks: [], suggestedBus: 'sfx', priority: 'P1', sortOrder: 33,
    ),
    ComposedStage(
      id: 'MULTIPLIER_APPLY', displayName: 'Multiplier Apply',
      layer: StageLayer.featureDerived, mechanic: SlotMechanic.multiplierTrail,
      hooks: [], suggestedBus: 'sfx', priority: 'P1', sortOrder: 34,
    ),
  ],
};

// =============================================================================
// SLOT MACHINE CONFIG (onboarding / project definition)
// =============================================================================

/// Defines a slot machine's core properties.
/// Created once at project start (via wizard), persisted with project.
class SlotMachineConfig {
  /// Display name (e.g. "Book of Ra", "Sweet Bonanza")
  final String name;

  /// Number of reels (3-8, typically 5)
  final int reelCount;

  /// Number of rows (1-6, typically 3)
  final int rowCount;

  /// Payline count (0=cluster, 1-50=lines, 100+=ways)
  final int paylineCount;

  /// Whether paylines are fixed or use cluster/ways
  final PaylineType paylineType;

  /// Number of win tiers (1-5)
  final int winTierCount;

  /// Enabled game mechanics
  final Map<SlotMechanic, bool> mechanics;

  /// Volatility profile
  final String volatilityProfile;

  /// Enabled block IDs from Feature Builder (includes non-mechanic blocks like transitions, anticipation)
  final List<String> enabledBlockIds;

  const SlotMachineConfig({
    required this.name,
    this.reelCount = 3,
    this.rowCount = 3,
    this.paylineCount = 20,
    this.paylineType = PaylineType.lines,
    this.winTierCount = 5,
    this.mechanics = const {},
    this.volatilityProfile = 'medium',
    this.enabledBlockIds = const [],
  });

  SlotMachineConfig copyWith({
    String? name,
    int? reelCount,
    int? rowCount,
    int? paylineCount,
    PaylineType? paylineType,
    int? winTierCount,
    Map<SlotMechanic, bool>? mechanics,
    String? volatilityProfile,
    List<String>? enabledBlockIds,
  }) => SlotMachineConfig(
    name: name ?? this.name,
    reelCount: reelCount ?? this.reelCount,
    rowCount: rowCount ?? this.rowCount,
    paylineCount: paylineCount ?? this.paylineCount,
    paylineType: paylineType ?? this.paylineType,
    winTierCount: winTierCount ?? this.winTierCount,
    mechanics: mechanics ?? this.mechanics,
    volatilityProfile: volatilityProfile ?? this.volatilityProfile,
    enabledBlockIds: enabledBlockIds ?? this.enabledBlockIds,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'reelCount': reelCount,
    'rowCount': rowCount,
    'paylineCount': paylineCount,
    'paylineType': paylineType.name,
    'winTierCount': winTierCount,
    'mechanics': {
      for (final e in mechanics.entries) e.key.name: e.value,
    },
    'volatilityProfile': volatilityProfile,
    'enabledBlockIds': enabledBlockIds,
  };

  factory SlotMachineConfig.fromJson(Map<String, dynamic> json) {
    final mechanicsMap = <SlotMechanic, bool>{};
    final rawMechanics = json['mechanics'] as Map<String, dynamic>?;
    if (rawMechanics != null) {
      for (final e in rawMechanics.entries) {
        final m = SlotMechanic.values.where((v) => v.name == e.key).firstOrNull;
        if (m != null) mechanicsMap[m] = e.value as bool;
      }
    }
    return SlotMachineConfig(
      name: json['name'] as String? ?? 'Untitled',
      reelCount: json['reelCount'] as int? ?? 3,
      rowCount: json['rowCount'] as int? ?? 3,
      paylineCount: json['paylineCount'] as int? ?? 20,
      paylineType: PaylineType.values.where(
        (v) => v.name == (json['paylineType'] as String?)
      ).firstOrNull ?? PaylineType.lines,
      winTierCount: json['winTierCount'] as int? ?? 5,
      mechanics: mechanicsMap,
      volatilityProfile: json['volatilityProfile'] as String? ?? 'medium',
      enabledBlockIds: (json['enabledBlockIds'] as List<dynamic>?)
          ?.cast<String>() ?? const [],
    );
  }
}

/// How paylines work in this slot
enum PaylineType {
  lines('Lines'),
  ways('Ways'),
  cluster('Cluster'),
  megaways('Megaways');

  const PaylineType(this.displayName);
  final String displayName;
}

// =============================================================================
// PROVIDER
// =============================================================================

class FeatureComposerProvider extends ChangeNotifier {
  /// Slot machine config — null means "not configured yet" (show wizard)
  SlotMachineConfig? _config;

  /// Currently enabled mechanics
  final Map<SlotMechanic, bool> _enabledMechanics = {
    for (final m in SlotMechanic.values) m: false,
  };

  /// Whether a slot machine has been configured
  bool get isConfigured => _config != null;

  /// Current config (null = show wizard)
  SlotMachineConfig? get config => _config;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get enabled state for a mechanic
  bool isEnabled(SlotMechanic mechanic) => _enabledMechanics[mechanic] ?? false;

  /// Check if a specific block ID is enabled (for non-mechanic blocks like transitions, anticipation)
  bool isBlockEnabled(String blockId) => _config?.enabledBlockIds.contains(blockId) ?? false;

  /// Get all enabled mechanics
  List<SlotMechanic> get enabledMechanics =>
      _enabledMechanics.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

  /// All mechanics with their enabled state
  Map<SlotMechanic, bool> get mechanicStates => Map.unmodifiable(_enabledMechanics);

  /// Get ALL composed stages: Engine Core + active feature stages + always visible
  /// Returns empty list if not configured (wizard should be shown)
  List<ComposedStage> get composedStages {
    if (!isConfigured) return [];

    final stages = <ComposedStage>[
      ...dynamicEngineCoreStages,
    ];

    // Add stages for enabled mechanics
    for (final mechanic in SlotMechanic.values) {
      if (_enabledMechanics[mechanic] == true) {
        stages.addAll(_mechanicStages[mechanic] ?? []);
      }
    }

    // Always-visible stages
    stages.addAll(_alwaysVisibleStages);

    // Sort by sortOrder
    stages.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return stages;
  }

  /// Get only Engine Core stages (dynamic based on config)
  List<ComposedStage> get engineCoreStages => isConfigured
      ? dynamicEngineCoreStages
      : List.unmodifiable(_engineCoreStages);

  /// Get only feature-derived stages (active mechanics)
  List<ComposedStage> get featureStages {
    final stages = <ComposedStage>[];
    for (final mechanic in SlotMechanic.values) {
      if (_enabledMechanics[mechanic] == true) {
        stages.addAll(_mechanicStages[mechanic] ?? []);
      }
    }
    stages.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return stages;
  }

  /// Get stages grouped by mechanic (for UI display)
  Map<SlotMechanic, List<ComposedStage>> get stagesByMechanic {
    final result = <SlotMechanic, List<ComposedStage>>{};
    for (final mechanic in SlotMechanic.values) {
      if (_enabledMechanics[mechanic] == true) {
        final stages = _mechanicStages[mechanic];
        if (stages != null && stages.isNotEmpty) {
          result[mechanic] = stages;
        }
      }
    }
    return result;
  }

  /// Get always-visible stages
  List<ComposedStage> get alwaysVisibleStages => List.unmodifiable(_alwaysVisibleStages);

  /// All hook names from enabled mechanics
  Set<String> get activeHooks {
    final hooks = <String>{};
    // Engine core hooks
    for (final s in _engineCoreStages) {
      hooks.addAll(s.hooks);
    }
    // Feature hooks
    for (final mechanic in SlotMechanic.values) {
      if (_enabledMechanics[mechanic] == true) {
        for (final s in _mechanicStages[mechanic] ?? <ComposedStage>[]) {
          hooks.addAll(s.hooks);
        }
      }
    }
    // Always-visible hooks
    for (final s in _alwaysVisibleStages) {
      hooks.addAll(s.hooks);
    }
    return hooks;
  }

  /// Total stage count (for progress indicators)
  int get totalStageCount => composedStages.length;

  /// Engine core stage count
  int get coreStageCount => _engineCoreStages.length;

  /// Feature stage count (only enabled)
  int get featureStageCount => featureStages.length;

  // ═══════════════════════════════════════════════════════════════════════════
  // MECHANIC MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enable or disable a mechanic
  void setMechanic(SlotMechanic mechanic, bool enabled) {
    if (_enabledMechanics[mechanic] == enabled) return;
    _enabledMechanics[mechanic] = enabled;
    notifyListeners();
  }

  /// Toggle a mechanic
  void toggleMechanic(SlotMechanic mechanic) {
    _enabledMechanics[mechanic] = !(_enabledMechanics[mechanic] ?? false);
    notifyListeners();
  }

  /// Enable multiple mechanics at once
  void setMechanics(Map<SlotMechanic, bool> mechanics) {
    bool changed = false;
    for (final entry in mechanics.entries) {
      if (_enabledMechanics[entry.key] != entry.value) {
        _enabledMechanics[entry.key] = entry.value;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Enable all mechanics
  void enableAll() {
    for (final m in SlotMechanic.values) {
      _enabledMechanics[m] = true;
    }
    notifyListeners();
  }

  /// Disable all mechanics
  void disableAll() {
    for (final m in SlotMechanic.values) {
      _enabledMechanics[m] = false;
    }
    notifyListeners();
  }

  /// Quick preset: Basic slot (cascading only)
  void presetBasic() {
    disableAll();
    _enabledMechanics[SlotMechanic.cascading] = true;
    notifyListeners();
  }

  /// Quick preset: Standard slot (cascading + free spins + jackpots)
  void presetStandard() {
    disableAll();
    _enabledMechanics[SlotMechanic.cascading] = true;
    _enabledMechanics[SlotMechanic.freeSpins] = true;
    _enabledMechanics[SlotMechanic.jackpot] = true;
    notifyListeners();
  }

  /// Quick preset: Full feature slot (everything enabled)
  void presetFull() {
    enableAll();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SLOT MACHINE CONFIG
  // ═══════════════════════════════════════════════════════════════════════════

  /// Apply a full slot machine config (from wizard or project load)
  void applyConfig(SlotMachineConfig config) {
    _config = config;

    // Apply mechanics from config
    for (final m in SlotMechanic.values) {
      _enabledMechanics[m] = config.mechanics[m] ?? false;
    }

    notifyListeners();
  }

  /// Reset config (back to wizard state)
  void resetConfig() {
    _config = null;
    disableAll();
  }

  /// Update config name
  void updateConfigName(String name) {
    if (_config == null) return;
    _config = _config!.copyWith(name: name);
    notifyListeners();
  }

  /// Get dynamic Engine Core stages based on config reel count
  List<ComposedStage> get dynamicEngineCoreStages {
    final reelCount = _config?.reelCount ?? 3;
    final winTiers = _config?.winTierCount ?? 5;

    final stages = <ComposedStage>[
      const ComposedStage(
        id: 'SPIN_START', displayName: 'Spin Start',
        layer: StageLayer.engineCore, locked: true, sortOrder: 0,
        hooks: ['onSpinStart'], suggestedBus: 'reels', priority: 'P0',
      ),
    ];

    // Dynamic reel stops based on reel count
    for (int i = 0; i < reelCount; i++) {
      stages.add(ComposedStage(
        id: 'REEL_STOP_$i', displayName: 'Reel Stop ${i + 1}',
        layer: StageLayer.engineCore, locked: true, sortOrder: 1 + i,
        hooks: ['onReelStop_r${i + 1}'], suggestedBus: 'reels', priority: 'P0',
      ));
    }

    stages.add(ComposedStage(
      id: 'SYMBOL_LAND', displayName: 'Symbol Land',
      layer: StageLayer.engineCore, locked: true, sortOrder: 1 + reelCount,
      hooks: ['onSymbolLand'], suggestedBus: 'reels', priority: 'P0',
    ));

    // Dynamic win tiers based on config
    for (int i = 0; i < winTiers; i++) {
      stages.add(ComposedStage(
        id: 'WIN_TIER_${i + 1}', displayName: 'Win Tier ${i + 1}',
        layer: StageLayer.engineCore, locked: true, sortOrder: 10 + i,
        hooks: ['onWinEvaluate_tier${i + 1}'], suggestedBus: 'sfx', priority: 'P0',
      ));
    }

    stages.addAll(const [
      ComposedStage(
        id: 'COUNTUP_TICK', displayName: 'Countup Tick',
        layer: StageLayer.engineCore, locked: true, sortOrder: 20,
        hooks: ['onCountUpTick'], suggestedBus: 'sfx', priority: 'P0',
      ),
      ComposedStage(
        id: 'COUNTUP_END', displayName: 'Countup End',
        layer: StageLayer.engineCore, locked: true, sortOrder: 21,
        hooks: ['onCountUpEnd'], suggestedBus: 'sfx', priority: 'P0',
      ),
    ]);

    return stages;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE LOOKUP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Find a composed stage by ID
  ComposedStage? findStage(String stageId) {
    // Check engine core first
    for (final s in _engineCoreStages) {
      if (s.id == stageId) return s;
    }
    // Check mechanic stages
    for (final mechanic in SlotMechanic.values) {
      for (final s in _mechanicStages[mechanic] ?? <ComposedStage>[]) {
        if (s.id == stageId) return s;
      }
    }
    // Check always-visible
    for (final s in _alwaysVisibleStages) {
      if (s.id == stageId) return s;
    }
    return null;
  }

  /// Check if a stage ID is currently active (visible in composed set)
  bool isStageActive(String stageId) {
    return composedStages.any((s) => s.id == stageId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
    'enabledMechanics': {
      for (final entry in _enabledMechanics.entries)
        entry.key.name: entry.value,
    },
    if (_config != null) 'slotMachineConfig': _config!.toJson(),
  };

  void fromJson(Map<String, dynamic> json) {
    // Restore config
    final configJson = json['slotMachineConfig'] as Map<String, dynamic>?;
    if (configJson != null) {
      _config = SlotMachineConfig.fromJson(configJson);
    }

    // Restore mechanics
    final mechanics = json['enabledMechanics'] as Map<String, dynamic>?;
    if (mechanics != null) {
      for (final entry in mechanics.entries) {
        final mechanic = SlotMechanic.values.where((m) => m.name == entry.key).firstOrNull;
        if (mechanic != null) {
          _enabledMechanics[mechanic] = entry.value as bool;
        }
      }
    }
    notifyListeners();
  }
}
