/// Stage Configuration Service
///
/// Centralized configuration for all stage-related data:
/// - Canonical stage names and categories
/// - Priority mappings (0-100)
/// - Bus routing mappings
/// - Spatial intent mappings
/// - Voice pooling configuration
/// - Custom stage definitions
///
/// Part of P3.3: Centralize stage configuration
library;

import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import '../models/slot_lab_models.dart';
import '../models/win_tier_config.dart' show SlotWinConfiguration, BigWinConfig;
import '../spatial/auto_spatial.dart' show SpatialBus;

// ═══════════════════════════════════════════════════════════════════════════
// STAGE CATEGORY
// ═══════════════════════════════════════════════════════════════════════════

/// Categories for grouping stages
enum StageCategory {
  spin,        // SPIN_*, REEL_*
  win,         // WIN_*, ROLLUP_*, BIGWIN_*
  feature,     // FS_*, BONUS_*, FEATURE_*
  cascade,     // CASCADE_*, TUMBLE_*
  jackpot,     // JACKPOT_*
  hold,        // HOLD_*, RESPIN_*
  gamble,      // GAMBLE_*
  ui,          // UI_*, SYSTEM_*, MENU_*
  music,       // MUSIC_*, AMBIENT_*
  symbol,      // SYMBOL_*, WILD_*, SCATTER_*
  custom,      // User-defined
}

extension StageCategoryExtension on StageCategory {
  String get label => switch (this) {
    StageCategory.spin => 'Spin',
    StageCategory.win => 'Win',
    StageCategory.feature => 'Feature',
    StageCategory.cascade => 'Cascade',
    StageCategory.jackpot => 'Jackpot',
    StageCategory.hold => 'Hold & Spin',
    StageCategory.gamble => 'Gamble',
    StageCategory.ui => 'UI',
    StageCategory.music => 'Music',
    StageCategory.symbol => 'Symbol',
    StageCategory.custom => 'Custom',
  };

  int get color => switch (this) {
    StageCategory.spin => 0xFF4A9EFF,    // Blue
    StageCategory.win => 0xFFFFD700,     // Gold
    StageCategory.feature => 0xFF40FF90, // Green
    StageCategory.cascade => 0xFF40C8FF, // Cyan
    StageCategory.jackpot => 0xFFFF4040, // Red
    StageCategory.hold => 0xFFFF9040,    // Orange
    StageCategory.gamble => 0xFFE040FB,  // Purple
    StageCategory.ui => 0xFF888888,      // Gray
    StageCategory.music => 0xFF90EE90,   // Light green
    StageCategory.symbol => 0xFFFFB6C1,  // Light pink
    StageCategory.custom => 0xFFFFFFFF,  // White
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// SPATIAL BUS — imported from auto_spatial.dart
// ═══════════════════════════════════════════════════════════════════════════
// Uses SpatialBus from ../spatial/auto_spatial.dart

// ═══════════════════════════════════════════════════════════════════════════
// STAGE DEFINITION
// ═══════════════════════════════════════════════════════════════════════════

/// Complete stage definition with all configuration
class StageDefinition {
  final String name;
  final String? displayLabel;  // Human-friendly label (synced with ASSIGN tab)
  final StageCategory category;
  final int priority;         // 0-100
  final SpatialBus bus;
  final String spatialIntent;
  final bool isPooled;        // Voice pooling enabled
  final bool isLooping;       // Loops until stopped
  final bool ducksMusic;      // Ducks music bus
  final String? description;

  const StageDefinition({
    required this.name,
    this.displayLabel,
    required this.category,
    this.priority = 50,
    this.bus = SpatialBus.sfx,
    this.spatialIntent = 'DEFAULT',
    this.isPooled = false,
    this.isLooping = false,
    this.ducksMusic = false,
    this.description,
  });

  StageDefinition copyWith({
    String? name,
    String? displayLabel,
    StageCategory? category,
    int? priority,
    SpatialBus? bus,
    String? spatialIntent,
    bool? isPooled,
    bool? isLooping,
    bool? ducksMusic,
    String? description,
  }) {
    return StageDefinition(
      name: name ?? this.name,
      displayLabel: displayLabel ?? this.displayLabel,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      bus: bus ?? this.bus,
      spatialIntent: spatialIntent ?? this.spatialIntent,
      isPooled: isPooled ?? this.isPooled,
      isLooping: isLooping ?? this.isLooping,
      ducksMusic: ducksMusic ?? this.ducksMusic,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (displayLabel != null) 'displayLabel': displayLabel,
    'category': category.name,
    'priority': priority,
    'bus': bus.name,
    'spatialIntent': spatialIntent,
    'isPooled': isPooled,
    'isLooping': isLooping,
    'ducksMusic': ducksMusic,
    'description': description,
  };

  factory StageDefinition.fromJson(Map<String, dynamic> json) {
    return StageDefinition(
      name: json['name'] as String,
      displayLabel: json['displayLabel'] as String?,
      category: StageCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => StageCategory.custom,
      ),
      priority: json['priority'] as int? ?? 50,
      bus: SpatialBus.values.firstWhere(
        (b) => b.name == json['bus'],
        orElse: () => SpatialBus.sfx,
      ),
      spatialIntent: json['spatialIntent'] as String? ?? 'DEFAULT',
      isPooled: json['isPooled'] as bool? ?? false,
      isLooping: json['isLooping'] as bool? ?? false,
      ducksMusic: json['ducksMusic'] as bool? ?? false,
      description: json['description'] as String?,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE CONFIGURATION SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Singleton service for centralized stage configuration
class StageConfigurationService extends ChangeNotifier {
  StageConfigurationService._();
  static final StageConfigurationService instance = StageConfigurationService._();

  /// All registered stage definitions
  final Map<String, StageDefinition> _stages = {};

  /// Custom user-defined stages
  final Map<String, StageDefinition> _customStages = {};

  bool _initialized = false;

  /// Initialize with default stage definitions
  void init() {
    if (_initialized) return;
    _initialized = true;
    _registerDefaultStages();
  }

  /// Get all stage names (custom overrides default)
  List<String> get allStageNames => ({..._stages, ..._customStages}).keys.toList()..sort();

  /// Get stages by category
  List<StageDefinition> getByCategory(StageCategory category) {
    return allStages.where((s) => s.category == category).toList();
  }

  /// Get all stage definitions
  /// All stages (custom overrides default when names overlap)
  List<StageDefinition> get allStages => ({..._stages, ..._customStages}).values.toList();

  /// Get stage definition by name (case insensitive)
  StageDefinition? getStage(String name) {
    final normalized = name.toUpperCase().trim();
    return _stages[normalized] ?? _customStages[normalized];
  }

  /// Get display label for stage — single source of truth for event names.
  /// Used by _ensureCompositeEventForStage to name composite events consistently
  /// with ASSIGN tab labels. Falls back to Title Case conversion if no label defined.
  String getDisplayLabel(String stage) {
    final upper = stage.toUpperCase();
    // 1. Check centralized label map (matches ASSIGN tab _SlotConfig labels)
    final label = _stageDisplayLabels[upper];
    if (label != null) return label;
    // 2. Check definition displayLabel
    final def = getStage(stage);
    if (def?.displayLabel != null) return def!.displayLabel!;
    // 3. Dynamic per-reel labels
    final reelMatch = RegExp(r'^REEL_STOP_(\d+)$').firstMatch(upper);
    if (reelMatch != null) return 'Reel ${int.parse(reelMatch.group(1)!) + 1} Stop';
    final nearMissReel = RegExp(r'^NEAR_MISS_REEL_(\d+)$').firstMatch(upper);
    if (nearMissReel != null) return 'Near Miss R${int.parse(nearMissReel.group(1)!) + 1}';
    final anticR = RegExp(r'^ANTICIPATION_TENSION_R(\d+)$').firstMatch(upper);
    if (anticR != null) return 'Reel ${int.parse(anticR.group(1)!) + 1} Tension';
    final anticRL = RegExp(r'^ANTICIPATION_TENSION_R(\d+)_L(\d+)$').firstMatch(upper);
    if (anticRL != null) return 'Reel ${int.parse(anticRL.group(1)!) + 1} Level ${anticRL.group(2)}';
    final scatterLand = RegExp(r'^SCATTER_LAND_(\d+)$').firstMatch(upper);
    if (scatterLand != null) return 'Scatter #${scatterLand.group(1)}';
    final cascadeStep = RegExp(r'^CASCADE_STEP_(\d+)$').firstMatch(upper);
    if (cascadeStep != null) return 'Cascade ${cascadeStep.group(1)}';
    if (upper == 'CASCADE_STEP_6PLUS') return 'Cascade 6+';
    final fsScatterR = RegExp(r'^FS_SCATTER_LAND_R(\d+)$').firstMatch(upper);
    if (fsScatterR != null) return 'FS Scatter R${fsScatterR.group(1)}';
    final fsRetrigger = RegExp(r'^FS_RETRIGGER_(\d+)$').firstMatch(upper);
    if (fsRetrigger != null) return '+${fsRetrigger.group(1)} Free Spins';
    // Per-symbol LAND with reel count: WILD_LAND_3 → "Wild Land #3"
    final symbolLandN = RegExp(r'^(\w+)_LAND_(\d+)$').firstMatch(upper);
    if (symbolLandN != null) {
      final sym = symbolLandN.group(1)!;
      return '${sym[0]}${sym.substring(1).toLowerCase()} Land #${symbolLandN.group(2)}';
    }
    final multiX = RegExp(r'^MULTIPLIER_X(\d+)$').firstMatch(upper);
    if (multiX != null) return 'Multi x${multiX.group(1)}';
    // 4. Music context dynamic labels (MUSIC_BASE_L1 → Base Game L1)
    final musicLayer = RegExp(r'^MUSIC_(\w+)_L(\d+)$').firstMatch(upper);
    if (musicLayer != null) {
      final ctx = musicLayer.group(1)!.split('_').map((w) =>
        w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}' : w
      ).join(' ');
      return '$ctx L${musicLayer.group(2)}';
    }
    final musicIntro = RegExp(r'^MUSIC_(\w+)_INTRO$').firstMatch(upper);
    if (musicIntro != null) {
      final ctx = musicIntro.group(1)!.split('_').map((w) =>
        w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}' : w
      ).join(' ');
      return '$ctx Intro';
    }
    final musicOutro = RegExp(r'^MUSIC_(\w+)_OUTRO$').firstMatch(upper);
    if (musicOutro != null) {
      final ctx = musicOutro.group(1)!.split('_').map((w) =>
        w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}' : w
      ).join(' ');
      return '$ctx Outro';
    }
    // 5. Fallback: Title Case from stage name (UI_SPIN_PRESS → Ui Spin Press)
    return stage.replaceAll('_', ' ').split(' ').map((w) =>
      w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}' : w
    ).join(' ');
  }

  /// Centralized stage → display label map (SSoT for ASSIGN tab + composite event names)
  static const _stageDisplayLabels = <String, String>{
    // ── PHASE 1: CORE LOOP ──
    // Idle/Attract
    'ATTRACT_LOOP': 'Attract Loop',
    'ATTRACT_EXIT': 'Attract Exit',
    'IDLE_LOOP': 'Idle Loop',
    'IDLE_TO_ACTIVE': 'Idle → Active',
    'GAME_READY': 'Game Ready',
    'GAME_START': 'Base Game Start',
    // Spin Controls
    'UI_SPIN_PRESS': 'Spin Press',
    'SPIN_CANCEL': 'Spin Cancel',
    'UI_STOP_PRESS': 'Stop Press',
    'QUICK_STOP': 'Quick Stop',
    'SLAM_STOP': 'Slam Stop',
    'SLAM_STOP_IMPACT': 'Slam Impact',
    'UI_AUTOPLAY_START': 'AutoSpin On',
    'UI_AUTOPLAY_STOP': 'AutoSpin Off',
    'UI_TURBO_ON': 'Turbo On',
    'UI_TURBO_OFF': 'Turbo Off',
    // Reel Animation
    'REEL_SPIN_LOOP': 'Spin Loop',
    'SPIN_ACCELERATION': 'Spin Accel',
    'SPIN_DECELERATION': 'Spin Decel',
    'TURBO_SPIN_LOOP': 'Turbo Loop',
    'REEL_SLOW_STOP': 'Slow Stop',
    'REEL_SHAKE': 'Reel Shake',
    'REEL_WIGGLE': 'Reel Wiggle',
    // Reel Stops
    'REEL_STOP': 'Generic Stop',
    // Anticipation
    'ANTICIPATION_TENSION': 'Anticipation (Global)',
    'ANTICIPATION_MISS': 'Anticipation Miss',
    // Spin End / Near Miss
    'SPIN_END': 'Spin End',
    'NO_WIN': 'No Win',
    'NEAR_MISS': 'Near Miss (Generic)',
    'NEAR_MISS_SCATTER': 'Near Miss Scatter',
    'NEAR_MISS_BONUS': 'Near Miss Bonus',
    'NEAR_MISS_JACKPOT': 'Near Miss JP',
    'NEAR_MISS_WILD': 'Near Miss Wild',
    'NEAR_MISS_FEATURE': 'Near Miss Feature',

    // ── PHASE 2: WINS ──
    // Win Evaluation
    'WIN_EVAL': 'Win Evaluate',
    'WIN_DETECTED': 'Win Detected',
    'WIN_CALCULATE': 'Win Calculate',
    // Paylines
    'PAYLINE_HIGHLIGHT': 'Payline Highlight',
    'WIN_LINE_SHOW': 'Line Show',
    'WIN_LINE_HIDE': 'Line Hide',
    'SYMBOL_WIN': 'Symbol Win (Generic)',
    'WIN_LINE_CYCLE': 'Line Cycle',
    // Per-Symbol Win Highlights
    'HP_WIN': 'HP (All) Win',
    'HP1_WIN': 'HP1 Win',
    'HP2_WIN': 'HP2 Win',
    'HP3_WIN': 'HP3 Win',
    'HP4_WIN': 'HP4 Win',
    'MP_WIN': 'MP (All) Win',
    'MP1_WIN': 'MP1 Win',
    'MP2_WIN': 'MP2 Win',
    'MP3_WIN': 'MP3 Win',
    'MP4_WIN': 'MP4 Win',
    'MP5_WIN': 'MP5 Win',
    'LP_WIN': 'LP (All) Win',
    'LP1_WIN': 'LP1 Win',
    'LP2_WIN': 'LP2 Win',
    'LP3_WIN': 'LP3 Win',
    'LP4_WIN': 'LP4 Win',
    'LP5_WIN': 'LP5 Win',
    'LP6_WIN': 'LP6 Win',
    'WILD_WIN': 'Wild Win',
    'SCATTER_WIN': 'Scatter Win',
    'BONUS_WIN': 'Bonus Win',
    // Win Tiers (static defaults — P5 dynamic tiers use WinTierConfig labels)
    'WIN_PRESENT_LOW': 'Low Win (< bet)',
    'WIN_PRESENT_EQUAL': 'Equal Win (= bet)',
    'WIN_PRESENT_1': 'Win Tier 1 (>1x, ≤2x)',
    'WIN_PRESENT_2': 'Win Tier 2 (>2x, ≤4x)',
    'WIN_PRESENT_3': 'Win Tier 3 (>4x, ≤8x)',
    'WIN_PRESENT_4': 'Win Tier 4 (>8x, ≤13x)',
    'WIN_PRESENT_5': 'Win Tier 5 (>13x)',
    'BIG_WIN_TRIGGER': 'Big Win Trigger (≥20x)',
    'BIG_WIN_TIER_1': 'Big Win Tier 1 (20x-50x)',
    'BIG_WIN_TIER_2': 'Big Win Tier 2 (50x-100x)',
    'BIG_WIN_TIER_3': 'Big Win Tier 3 (100x-250x)',
    'BIG_WIN_TIER_4': 'Big Win Tier 4 (250x-500x)',
    'BIG_WIN_TIER_5': 'Big Win Tier 5 (500x+)',
    // Big Win Stages
    'BIG_WIN_START': 'Big Win Intro',
    'BIG_WIN_END': 'Big Win End',
    'BIG_WIN_TICK_START': 'Big Win Tick Start',
    'BIG_WIN_TICK_END': 'Big Win Tick End',
    'COIN_SHOWER_START': 'Coin Shower Start',
    'COIN_SHOWER_END': 'Coin Shower End',
    // Rollup
    'ROLLUP_START': 'Rollup Start',
    'ROLLUP_TICK': 'Rollup Tick',
    'ROLLUP_TICK_FAST': 'Rollup Fast',
    'ROLLUP_TICK_SLOW': 'Rollup Slow',
    'ROLLUP_ACCELERATION': 'Rollup Accel',
    'ROLLUP_DECELERATION': 'Rollup Decel',
    'ROLLUP_END': 'Rollup End',
    'ROLLUP_SKIP': 'Rollup Skip',
    // Win Celebration
    'COIN_BURST': 'Coin Burst',
    'COIN_DROP': 'Coin Drop',
    'COIN_SHOWER': 'Coin Shower',
    'COIN_RAIN': 'Coin Rain',
    'SCREEN_SHAKE': 'Screen Shake',
    'LIGHT_FLASH': 'Light Flash',
    'CONFETTI_BURST': 'Confetti Burst',
    'FIREWORKS_LAUNCH': 'Fireworks Launch',
    'FIREWORKS_EXPLODE': 'Fireworks Explode',
    'WIN_FANFARE': 'Win Fanfare',
    // Voice Overs
    'VO_WIN_1': 'VO Win Tier 1',
    'VO_WIN_2': 'VO Win Tier 2',
    'VO_WIN_3': 'VO Win Tier 3',
    'VO_WIN_4': 'VO Win Tier 4',
    'VO_WIN_5': 'VO Win Tier 5',
    'VO_BIG_WIN': 'VO Big Win',
    'VO_CONGRATULATIONS': 'VO Congrats',
    'VO_INCREDIBLE': 'VO Incredible',
    'VO_SENSATIONAL': 'VO Sensational',

    // ── CASCADE / TUMBLE ──
    'CASCADE_START': 'Cascade Start',
    'CASCADE_STEP': 'Cascade Step',
    'CASCADE_POP': 'Cascade Pop',
    'CASCADE_END': 'Cascade End',
    'CASCADE_SYMBOL_POP': 'Symbol Pop',
    'CASCADE_SYMBOL_DROP': 'Symbol Drop',
    'CASCADE_SYMBOL_LAND': 'Symbol Land',
    'CASCADE_CHAIN_START': 'Chain Start',
    'CASCADE_CHAIN_CONTINUE': 'Chain Continue',
    'CASCADE_CHAIN_END': 'Chain End',
    'CASCADE_ANTICIPATION': 'Cascade Antic',
    'CASCADE_MEGA': 'Cascade Mega',
    'TUMBLE_DROP': 'Tumble Drop',
    'TUMBLE_IMPACT': 'Tumble Impact',
    'AVALANCHE_TRIGGER': 'Avalanche Trigger',
    'REACTION_WIN': 'Reaction Win',
    'GRAVITY_SHIFT': 'Gravity Shift',
    'REPLACEMENT_FALL': 'Replacement Fall',
    'CLUSTER_FORM': 'Cluster Form',
    'CLUSTER_EXPLODE': 'Cluster Explode',
    'CLUSTER_WIN': 'Cluster Win',

    // ── MULTIPLIERS ──
    'MULTIPLIER_INCREASE': 'Multi Increase',
    'MULTIPLIER_APPLY': 'Multi Apply',
    'MULTIPLIER_MAX': 'Multi Max',
    'MULTIPLIER_RESET': 'Multi Reset',
    'PROGRESSIVE_MULTIPLIER': 'Prog Multi',
    'GLOBAL_MULTIPLIER': 'Global Multi',
    'MULTIPLIER_TRAIL': 'Trail Multi',
    'MULTIPLIER_STACK': 'Stack Multi',
    'RANDOM_MULTIPLIER': 'Random Multi',
    'MULTIPLIER_WILD': 'Wild Multi',
    'MULTIPLIER_REEL': 'Reel Multi',
    'MULTIPLIER_SYMBOL': 'Symbol Multi',
    'MULTIPLIER_LAND': 'Multi Land',
    // Modifiers
    'MODIFIER_TRIGGER': 'Modifier Trigger',
    'RANDOM_FEATURE': 'Random Feature',
    'RANDOM_WILD': 'Random Wild',
    'RANDOM_NUDGE': 'Random Nudge',
    'RANDOM_RESPIN': 'Random Respin',
    'RANDOM_UPGRADE': 'Random Upgrade',
    'LIGHTNING_STRIKE': 'Lightning Strike',
    'MAGIC_TOUCH': 'Magic Touch',

    // ── PHASE 3: FEATURES ──
    // Free Spins
    'FS_HOLD_INTRO': 'Hold Intro',
    'FS_HOLD_OUTRO': 'Hold Outro',
    'FS_START': 'FS Start',
    'FS_SPIN_START': 'Spin Start',
    'FS_SPIN_END': 'Spin End',
    'FS_WIN': 'FS Win',
    'FS_STICKY_WILD': 'Sticky Wild',
    'FS_EXPANDING_WILD': 'Expand Wild',
    'FS_MULTIPLIER_UP': 'Multi Up',
    'FS_SCATTER_LAND': 'FS Scatter',
    'FS_RETRIGGER': 'Retrigger',
    'FS_END': 'FS End',
    // Bonus Games
    'BONUS_TRIGGER': 'Bonus Trigger',
    'BONUS_ENTER': 'Bonus Enter',
    'BONUS_STEP': 'Bonus Step',
    'BONUS_EXIT': 'Bonus Exit',
    'BONUS_MUSIC': 'Bonus Music',
    'BONUS_SUMMARY': 'Bonus Summary',
    'BONUS_TOTAL': 'Bonus Total',
    'VO_BONUS': 'VO Bonus',
    // Pick
    'PICK_REVEAL': 'Pick Reveal',
    'PICK_GOOD': 'Pick Good',
    'PICK_BAD': 'Pick Bad',
    'PICK_BONUS': 'Pick Bonus',
    'PICK_MULTIPLIER': 'Pick Multi',
    'PICK_UPGRADE': 'Pick Upgrade',
    'PICK_COLLECT': 'Pick Collect',
    'PICK_HOVER': 'Pick Hover',
    'PICK_CHEST_OPEN': 'Chest Open',
    'PICK_ALL_REVEALED': 'All Revealed',
    'PICK_MEGA_PRIZE': 'Mega Prize',
    // Wheel
    'WHEEL_START': 'Wheel Start',
    'WHEEL_SPIN': 'Wheel Spin',
    'WHEEL_TICK': 'Wheel Tick',
    'WHEEL_POINTER_TICK': 'Pointer Tick',
    'WHEEL_SLOW': 'Wheel Slow',
    'WHEEL_ACCELERATION': 'Wheel Accel',
    'WHEEL_LAND': 'Wheel Land',
    'WHEEL_ANTICIPATION': 'Wheel Antic',
    'WHEEL_NEAR_MISS': 'Wheel Near Miss',
    'WHEEL_CELEBRATION': 'Wheel Celebrate',
    'WHEEL_PRIZE': 'Wheel Prize',
    'WHEEL_BONUS': 'Wheel Bonus',
    'WHEEL_MULTIPLIER': 'Wheel Multi',
    'WHEEL_JACKPOT_LAND': 'Wheel JP Land',
    // Wild Features
    'WILD_EXPAND_START': 'Wild Expand Start',
    'WILD_EXPAND_STEP': 'Wild Expand Step',
    'WILD_EXPAND_END': 'Wild Expand End',
    'WILD_STICK': 'Wild Stick',
    'WILD_WALK_LEFT': 'Wild Walk L',
    'WILD_WALK_RIGHT': 'Wild Walk R',
    'WILD_TRANSFORM': 'Wild Transform',
    'WILD_MULTIPLY': 'Wild Multiply',
    'WILD_SPREAD': 'Wild Spread',
    'WILD_NUDGE': 'Wild Nudge',
    'WILD_STACK': 'Wild Stack',
    'WILD_COLOSSAL': 'Colossal Wild',
    'WILD_REEL': 'Wild Reel',
    'WILD_UPGRADE': 'Wild Upgrade',
    'WILD_COLLECT': 'Wild Collect',
    // Mystery/Collector
    'MYSTERY_LAND': 'Mystery Land',
    'MYSTERY_REVEAL': 'Mystery Reveal',
    'MYSTERY_TRANSFORM': 'Mystery Transform',
    'COLLECTOR_LAND': 'Collector Land',
    'COLLECTOR_COLLECT': 'Collector Collect',
    'COLLECTOR_ACTIVATE': 'Collector Activate',
    'COIN_LAND': 'Coin Land',
    'COIN_VALUE_REVEAL': 'Coin Value Reveal',
    'COIN_COLLECT': 'Coin Collect',
    // Nudge/Respin
    'REEL_NUDGE': 'Reel Nudge',
    'NUDGE_UP': 'Nudge Up',
    'NUDGE_DOWN': 'Nudge Down',
    'NUDGE_TRIGGER': 'Nudge Trigger',
    'NUDGE_COMPLETE': 'Nudge Complete',
    'RESPIN_TRIGGER': 'Respin Trigger',
    'RESPIN_START': 'Respin Start',
    'RESPIN_SPIN': 'Respin Spin',
    'RESPIN_STOP': 'Respin Stop',
    'RESPIN_END': 'Respin End',
    'RESPIN_RETRIGGER': 'Respin Retrigger',

    // ── PHASE 4: JACKPOTS ──
    'JACKPOT_TRIGGER': 'JP Trigger',
    'JACKPOT_ELIGIBLE': 'JP Eligible',
    'JACKPOT_PROGRESS': 'JP Progress',
    'JACKPOT_BUILDUP': 'JP Buildup',
    'JACKPOT_ANIMATION_START': 'JP Anim Start',
    'JACKPOT_METER_FILL': 'JP Meter Fill',
    'JACKPOT_REVEAL': 'JP Reveal',
    'JACKPOT_WHEEL_SPIN': 'JP Wheel Spin',
    'JACKPOT_WHEEL_TICK': 'JP Wheel Tick',
    'JACKPOT_WHEEL_LAND': 'JP Wheel Land',
    'JACKPOT_MINI': 'JP Mini',
    'JACKPOT_MINOR': 'JP Minor',
    'JACKPOT_MAJOR': 'JP Major',
    'JACKPOT_GRAND': 'JP Grand',
    'JACKPOT_MEGA': 'JP Mega',
    'JACKPOT_ULTRA': 'JP Ultra',
    'JACKPOT_PRESENT': 'JP Present',
    'JACKPOT_AWARD': 'JP Award',
    'JACKPOT_ROLLUP': 'JP Rollup',
    'JACKPOT_BELLS': 'JP Bells',
    'JACKPOT_SIRENS': 'JP Sirens',
    'JACKPOT_CELEBRATION': 'JP Celebration',
    'JACKPOT_MACHINE_WIN': 'JP Machine Win',
    'JACKPOT_COLLECT': 'JP Collect',
    'JACKPOT_END': 'JP End',
    'PROGRESSIVE_INCREMENT': 'Prog Increment',
    'PROGRESSIVE_FLASH': 'Prog Flash',
    'PROGRESSIVE_HIT': 'Prog Hit',
    'JACKPOT_TICKER_INCREMENT': 'JP Ticker',
    'MUST_HIT_BY_WARNING': 'Must Hit Warning',
    'MUST_HIT_BY_IMMINENT': 'Must Hit Imminent',
    'HOT_DROP_WARNING': 'Hot Drop Warning',
    'HOT_DROP_HIT': 'Hot Drop Hit',
    'HOT_DROP_NEAR': 'Hot Drop Near',
    'LINK_WIN': 'Link Win',
    'NETWORK_JACKPOT': 'Network JP',
    'LOCAL_JACKPOT': 'Local JP',

    // ── PHASE 5: GAMBLE ──
    'GAMBLE_ENTER': 'Gamble Enter',
    'GAMBLE_OFFER': 'Gamble Offer',
    'GAMBLE_CARD_FLIP': 'Card Flip',
    'GAMBLE_COLOR_PICK': 'Color Pick',
    'GAMBLE_SUIT_PICK': 'Suit Pick',
    'GAMBLE_LADDER_STEP': 'Ladder Step',
    'GAMBLE_WIN': 'Gamble Win',
    'GAMBLE_LOSE': 'Gamble Lose',
    'GAMBLE_DOUBLE': 'Gamble Double',
    'GAMBLE_HALF': 'Gamble Half',
    'GAMBLE_LADDER_FALL': 'Ladder Fall',
    'GAMBLE_COLLECT': 'Gamble Collect',
    'GAMBLE_EXIT': 'Gamble Exit',
    'GAMBLE_LIMIT': 'Gamble Limit',
    'GAMBLE_TIMEOUT': 'Gamble Timeout',

    // ── PHASE 6: MUSIC ──
    'MUSIC_TENSION_LOW': 'Tension Low',
    'MUSIC_TENSION_MED': 'Tension Med',
    'MUSIC_TENSION_HIGH': 'Tension High',
    'MUSIC_TENSION_MAX': 'Tension Max',
    'MUSIC_BUILDUP': 'Music Buildup',

    // ── PHASE 7: UI & SYSTEM ──
    'UI_BUTTON_PRESS': 'Button Press',
    'UI_BUTTON_HOVER': 'Button Hover',
    'UI_SPIN_HOVER': 'Spin Hover',
    'UI_SPIN_RELEASE': 'Spin Release',
    'UI_BET_UP': 'Bet Up',
    'UI_BET_DOWN': 'Bet Down',
    'UI_BET_MAX': 'Bet Max',
    'UI_BET_MIN': 'Bet Min',
    'UI_MENU_OPEN': 'Menu Open',
    'UI_MENU_CLOSE': 'Menu Close',
    'UI_MENU_HOVER': 'Menu Hover',
    'UI_MENU_SELECT': 'Menu Select',
    'UI_TAB_SWITCH': 'Tab Switch',
    'UI_PAGE_FLIP': 'Page Flip',
    'UI_SCROLL': 'Scroll',
    'UI_PAYTABLE_OPEN': 'Paytable Open',
    'UI_PAYTABLE_CLOSE': 'Paytable Close',
    'UI_RULES_OPEN': 'Rules Open',
    'UI_HELP_OPEN': 'Help Open',
    'UI_INFO_PRESS': 'Info Press',
    'UI_SETTINGS_OPEN': 'Settings Open',
    'UI_SETTINGS_CLOSE': 'Settings Close',
    'UI_NOTIFICATION': 'Notification',
    'UI_ALERT': 'Alert',
    'UI_ERROR': 'Error',
    'UI_WARNING': 'Warning',
    'UI_POPUP_OPEN': 'Popup Open',
    'UI_POPUP_CLOSE': 'Popup Close',
    'UI_TOOLTIP_SHOW': 'Tooltip Show',
    'UI_TOOLTIP_HIDE': 'Tooltip Hide',
    'UI_CHECKBOX_ON': 'Checkbox On',
    'UI_CHECKBOX_OFF': 'Checkbox Off',
    'UI_SLIDER_DRAG': 'Slider Drag',
    'UI_SLIDER_RELEASE': 'Slider Release',
    'UI_SOUND_ON': 'Sound On',
    'UI_SOUND_OFF': 'Sound Off',
    'UI_VOLUME_CHANGE': 'Volume Change',
    'UI_FULLSCREEN_ENTER': 'Fullscreen Enter',
    'UI_FULLSCREEN_EXIT': 'Fullscreen Exit',

    // ── HOLD & WIN ──
    'HOLD_TRIGGER': 'Hold Trigger',
    'HOLD_START': 'Hold Start',
    'HOLD_SPIN': 'Hold Spin',
    'HOLD_LAND': 'Hold Land',
    'HOLD_UPGRADE': 'Hold Upgrade',
    'HOLD_COLLECT': 'Hold Collect',
    'HOLD_END': 'Hold End',
    'HOLD_GRAND': 'Hold Grand',
    'HOLD_RESPINS_RESET': 'Respins Reset',

    // ── MEGAWAYS ──
    'MEGAWAYS_REVEAL': 'Megaways Reveal',
    'MEGAWAYS_EXPAND': 'Megaways Expand',
    'MEGAWAYS_ROWS_CHANGE': 'Rows Change',
  };

  /// Get priority for stage (0-100)
  int getPriority(String stage) {
    final def = getStage(stage);
    if (def != null) return def.priority;

    // Fallback: prefix-based priority
    return _getPriorityByPrefix(stage.toUpperCase());
  }

  /// Get category for stage (SSoT for all category lookups)
  StageCategory getCategory(String stage) {
    final def = getStage(stage);
    if (def != null) return def.category;

    // Fallback: comprehensive prefix-based category detection
    final upper = stage.toUpperCase();
    if (upper.startsWith('SPIN_') || upper.startsWith('REEL_')) return StageCategory.spin;
    if (upper.startsWith('WIN_') || upper.startsWith('ROLLUP_') || upper.startsWith('BIGWIN_')) return StageCategory.win;
    if (upper.startsWith('FS_') || upper.startsWith('BONUS_') || upper.startsWith('FEATURE_') ||
        upper.startsWith('FREE_SPIN') || upper.startsWith('WHEEL_') || upper.startsWith('PICK_') ||
        upper.startsWith('CASH_COLLECT')) return StageCategory.feature;
    if (upper.startsWith('CASCADE_') || upper.startsWith('TUMBLE_')) return StageCategory.cascade;
    if (upper.startsWith('JACKPOT_')) return StageCategory.jackpot;
    if (upper.startsWith('HOLD_') || upper.startsWith('RESPIN_')) return StageCategory.hold;
    if (upper.startsWith('GAMBLE_')) return StageCategory.gamble;
    if (upper.startsWith('UI_') || upper.startsWith('SYSTEM_') || upper.startsWith('MENU_')) return StageCategory.ui;
    if (upper.startsWith('MUSIC_') || upper.startsWith('AMBIENT_') || upper.startsWith('IDLE_') ||
        upper.startsWith('ATTRACT_') || upper.startsWith('HOLD_MUSIC')) return StageCategory.music;
    if (upper.startsWith('SYMBOL_') || upper.startsWith('WILD_') || upper.startsWith('SCATTER_') ||
        upper.startsWith('ANTICIPATION_') || upper.startsWith('NEAR_MISS') || upper.startsWith('STICKY_') ||
        upper.startsWith('CASH_SYMBOL') || upper.startsWith('CASH_VALUE')) return StageCategory.symbol;
    if (upper.startsWith('TRANSITION_') || upper.startsWith('COLLECT_')) return StageCategory.custom;
    return StageCategory.custom;
  }

  /// Get category label for stage (convenience method for UI display)
  String getCategoryLabel(String stage) => getCategory(stage).label;

  /// Get category color for stage (convenience method for UI display)
  Color getCategoryColor(String stage) => Color(getCategory(stage).color);

  /// Get bus for stage
  SpatialBus getBus(String stage) {
    final def = getStage(stage);
    if (def != null) return def.bus;

    // Fallback: prefix-based bus
    return _getBusByPrefix(stage.toUpperCase());
  }

  /// Get spatial intent for stage
  String getSpatialIntent(String stage) {
    final def = getStage(stage);
    if (def != null) return def.spatialIntent;

    // Fallback: prefix-based spatial intent
    return _getSpatialIntentByPrefix(stage.toUpperCase());
  }

  /// Check if stage should use voice pooling
  bool isPooled(String stage) {
    final def = getStage(stage);
    return def?.isPooled ?? _pooledStages.contains(stage.toUpperCase());
  }

  /// Check if stage audio should loop by default
  bool isLooping(String stage) {
    final def = getStage(stage);
    if (def != null) return def.isLooping;

    // Fallback: check common looping stage patterns
    final upper = stage.toUpperCase();
    return _loopingStages.contains(upper) ||
        upper.endsWith('_LOOP') ||
        upper.startsWith('MUSIC_') ||
        upper.startsWith('AMBIENT_') ||
        upper.startsWith('ATTRACT_') ||
        upper.startsWith('IDLE_');
  }

  /// Get pooled stage names (for voice pool)
  Set<String> get pooledStageNames {
    final result = <String>{};
    for (final stage in allStages) {
      if (stage.isPooled) result.add(stage.name);
    }
    return result;
  }

  /// Register custom stage
  void registerCustomStage(StageDefinition stage) {
    final normalized = stage.name.toUpperCase().trim();
    _customStages[normalized] = stage.copyWith(name: normalized);
    notifyListeners();
  }

  /// Remove custom stage
  void removeCustomStage(String name) {
    final normalized = name.toUpperCase().trim();
    if (_customStages.remove(normalized) != null) {
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P5 WIN TIER STAGE GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Track which stages were generated from win tier config (for cleanup)
  final Set<String> _winTierGeneratedStages = {};

  /// Register all stages from a win tier configuration (P5 system)
  ///
  /// Generates stages like:
  /// - WIN_LOW, WIN_EQUAL, WIN_1..6 — Regular win tiers
  /// - WIN_PRESENT_LOW, WIN_PRESENT_1..6 — Win presentation
  /// - ROLLUP_START_*, ROLLUP_TICK_*, ROLLUP_END_* — Rollup stages
  /// - BIG_WIN_START, BIG_WIN_TIER_1..5, BIG_WIN_END — Big win celebration
  void registerWinTierStages(SlotWinConfiguration config) {
    // Clear previous win tier stages
    for (final stageName in _winTierGeneratedStages) {
      _customStages.remove(stageName);
    }
    _winTierGeneratedStages.clear();

    // Register regular win tier stages
    for (final tier in config.regularWins.tiers) {
      // Main tier stage (WIN_LOW, WIN_1, etc.)
      _registerWinStage(
        name: tier.stageName,
        category: StageCategory.win,
        priority: 50 + tier.tierId.clamp(-1, 6) * 5, // Higher tier = higher priority
        description: 'Regular win tier: ${tier.tierId == -1 ? "LOW" : tier.tierId == 0 ? "EQUAL" : tier.tierId.toString()}',
      );

      // Presentation stage
      _registerWinStage(
        name: tier.presentStageName,
        category: StageCategory.win,
        priority: 55 + tier.tierId.clamp(-1, 6) * 5,
        description: 'Win presentation for tier ${tier.tierId}',
      );

      // Rollup stages (not for WIN_LOW which is instant)
      if (tier.rollupStartStageName != null) {
        _registerWinStage(
          name: tier.rollupStartStageName!,
          category: StageCategory.win,
          priority: 45,
          description: 'Rollup start for tier ${tier.tierId}',
        );
        _registerWinStage(
          name: tier.rollupTickStageName!,
          category: StageCategory.win,
          priority: 40,
          isPooled: true, // Rapid-fire event
          description: 'Rollup tick for tier ${tier.tierId}',
        );
        _registerWinStage(
          name: tier.rollupEndStageName!,
          category: StageCategory.win,
          priority: 45,
          description: 'Rollup end for tier ${tier.tierId}',
        );
      }
    }

    // Register big win stages
    _registerWinStage(
      name: BigWinConfig.startStageName, // BIG_WIN_START
      category: StageCategory.win,
      priority: 85,
      ducksMusic: true,
      description: 'Big win intro (threshold: ${config.bigWins.threshold}x)',
    );

    for (final tier in config.bigWins.tiers) {
      _registerWinStage(
        name: tier.stageName, // BIG_WIN_TIER_1..5
        category: StageCategory.win,
        priority: 80 + tier.tierId * 2, // Higher tier = higher priority
        ducksMusic: true,
        description: 'Big win tier ${tier.tierId}: ${tier.fromMultiplier}x-${tier.toMultiplier}x',
      );
    }

    _registerWinStage(
      name: BigWinConfig.endStageName, // BIG_WIN_END
      category: StageCategory.win,
      priority: 75,
      description: 'Big win celebration end',
    );

    _registerWinStage(
      name: BigWinConfig.tickStartStageName, // BIG_WIN_TICK_START
      category: StageCategory.win,
      priority: 60,
      isPooled: true,
      description: 'Big win rollup tick',
    );

    _registerWinStage(
      name: BigWinConfig.tickEndStageName, // BIG_WIN_TICK_END
      category: StageCategory.win,
      priority: 55,
      description: 'Big win rollup tick end',
    );

    notifyListeners();
  }

  /// Helper to register a single win stage
  void _registerWinStage({
    required String name,
    required StageCategory category,
    required int priority,
    bool isPooled = false,
    bool ducksMusic = false,
    String? description,
  }) {
    final def = StageDefinition(
      name: name,
      category: category,
      priority: priority,
      bus: SpatialBus.sfx,
      spatialIntent: 'win_celebration',
      isPooled: isPooled,
      isLooping: false,
      ducksMusic: ducksMusic,
      description: description ?? 'P5 win tier stage',
    );
    _customStages[name] = def;
    _winTierGeneratedStages.add(name);
  }

  /// Get all win tier generated stage names
  Set<String> get allWinTierStageNames => Set.unmodifiable(_winTierGeneratedStages);

  /// Check if a stage was generated from win tier config
  bool isWinTierGenerated(String stage) {
    return _winTierGeneratedStages.contains(stage.toUpperCase());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DYNAMIC SYMBOL STAGE GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Track which stages were generated from symbols (for cleanup)
  final Set<String> _symbolGeneratedStages = {};

  /// Register all stages for a symbol based on its contexts
  ///
  /// Generates stages like:
  /// - {ID}_LAND — Symbol landing on reel
  /// - {ID}_WIN — Symbol highlighted during win
  /// - {ID}_EXPAND — Wild/symbol expansion
  /// - {ID}_LOCK — Symbol locking (Hold & Win)
  /// - {ID}_TRANSFORM — Symbol transformation
  /// - {ID}_COLLECT — Coin/gem collection
  /// - {ID}_STACK — Symbol stacking
  /// - {ID}_TRIGGER — Feature trigger
  /// - {ID}_ANTICIPATION — Anticipation before feature
  void registerSymbolStages(SymbolDefinition symbol) {
    final id = symbol.id.toUpperCase();
    final priority = _getPriorityForSymbolType(symbol.type);
    final bus = _getBusForSymbolType(symbol.type);

    // Register each context-specific stage (contexts are strings like 'land', 'win', etc.)
    for (final contextStr in symbol.contexts) {
      final context = SymbolAudioContext.fromString(contextStr);
      if (context == null) {
        continue;
      }

      final stageName = _getStageNameForContext(id, context);
      final def = StageDefinition(
        name: stageName,
        category: StageCategory.symbol,
        priority: _getPriorityForContext(context, priority),
        bus: bus,
        spatialIntent: _getSpatialIntentForContext(context, id),
        isPooled: _isContextPooled(context),
        isLooping: false,
        ducksMusic: context == SymbolAudioContext.trigger || context == SymbolAudioContext.anticipation,
        description: 'Auto-generated for symbol: ${symbol.name}',
      );
      _customStages[stageName] = def;
      _symbolGeneratedStages.add(stageName);
    }

  }

  /// Remove all stages for a symbol
  void removeSymbolStages(String symbolId) {
    final id = symbolId.toUpperCase();
    final toRemove = <String>[];

    for (final stageName in _symbolGeneratedStages) {
      // {SYMBOL}_{ACTION} convention: stages START with symbolId
      if (stageName.startsWith('${id}_')) {
        toRemove.add(stageName);
      }
    }

    for (final name in toRemove) {
      _customStages.remove(name);
      _symbolGeneratedStages.remove(name);
    }

    if (toRemove.isNotEmpty) {
      notifyListeners();
    }
  }

  /// Sync all symbol stages from a list of symbols
  /// Clears old symbol-generated stages and registers new ones
  void syncSymbolStages(List<SymbolDefinition> symbols) {
    // Clear all symbol-generated stages
    for (final stageName in _symbolGeneratedStages) {
      _customStages.remove(stageName);
    }
    _symbolGeneratedStages.clear();

    // Register stages for each symbol
    for (final symbol in symbols) {
      registerSymbolStages(symbol);
    }

    notifyListeners();
  }

  /// Get all stage names generated from a specific symbol
  List<String> getSymbolStageNames(String symbolId) {
    final id = symbolId.toUpperCase();
    return _symbolGeneratedStages.where((s) => s.startsWith('${id}_')).toList();
  }

  /// Get all symbol-generated stage names
  Set<String> get allSymbolStageNames => Set.unmodifiable(_symbolGeneratedStages);

  /// Check if a stage was generated from a symbol definition
  bool isSymbolGenerated(String stage) {
    return _symbolGeneratedStages.contains(stage.toUpperCase());
  }

  /// Get all registered stages (both default and custom)
  List<StageDefinition> getAllStages() {
    final allStages = <StageDefinition>[];
    allStages.addAll(_stages.values);
    allStages.addAll(_customStages.values);
    return allStages;
  }

  // Helper methods for symbol stage generation

  String _getStageNameForContext(String symbolId, SymbolAudioContext context) {
    switch (context) {
      case SymbolAudioContext.land:
        return '${symbolId}_LAND';
      case SymbolAudioContext.win:
        return '${symbolId}_WIN';
      case SymbolAudioContext.expand:
        return '${symbolId}_EXPAND';
      case SymbolAudioContext.lock:
        return '${symbolId}_LOCK';
      case SymbolAudioContext.transform:
        return '${symbolId}_TRANSFORM';
      case SymbolAudioContext.collect:
        return '${symbolId}_COLLECT';
      case SymbolAudioContext.stack:
        return '${symbolId}_STACK';
      case SymbolAudioContext.trigger:
        return '${symbolId}_TRIGGER';
      case SymbolAudioContext.anticipation:
        return '${symbolId}_ANTICIPATION';
    }
  }

  int _getPriorityForSymbolType(SymbolType type) {
    switch (type) {
      case SymbolType.wild:
      case SymbolType.scatter:
      case SymbolType.bonus:
        return 70; // High priority for special symbols
      case SymbolType.multiplier:
      case SymbolType.collector:
        return 65;
      case SymbolType.highPay:
      case SymbolType.high:
        return 55;
      case SymbolType.mediumPay:
        return 50;
      case SymbolType.lowPay:
      case SymbolType.low:
        return 45;
      case SymbolType.mystery:
        return 60;
      case SymbolType.custom:
        return 50;
    }
  }

  int _getPriorityForContext(SymbolAudioContext context, int baseP) {
    switch (context) {
      case SymbolAudioContext.trigger:
        return baseP + 15; // Triggers are highest
      case SymbolAudioContext.anticipation:
        return baseP + 10;
      case SymbolAudioContext.win:
        return baseP + 5;
      case SymbolAudioContext.expand:
      case SymbolAudioContext.transform:
        return baseP + 5;
      case SymbolAudioContext.collect:
      case SymbolAudioContext.lock:
        return baseP;
      case SymbolAudioContext.land:
      case SymbolAudioContext.stack:
        return baseP - 5;
    }
  }

  SpatialBus _getBusForSymbolType(SymbolType type) {
    switch (type) {
      case SymbolType.wild:
      case SymbolType.scatter:
      case SymbolType.bonus:
      case SymbolType.multiplier:
      case SymbolType.collector:
        return SpatialBus.sfx; // Special effects bus
      case SymbolType.highPay:
      case SymbolType.high:
      case SymbolType.mediumPay:
      case SymbolType.lowPay:
      case SymbolType.low:
        return SpatialBus.reels; // Reel sounds
      case SymbolType.mystery:
      case SymbolType.custom:
        return SpatialBus.sfx;
    }
  }

  String _getSpatialIntentForContext(SymbolAudioContext context, String symbolId) {
    switch (context) {
      case SymbolAudioContext.land:
        return '${symbolId}_LAND';
      case SymbolAudioContext.win:
        return 'SYMBOL_WIN';
      case SymbolAudioContext.expand:
        return 'WILD_EXPAND';
      case SymbolAudioContext.lock:
        return 'HOLD_LOCK';
      case SymbolAudioContext.transform:
        return 'MYSTERY_REVEAL';
      case SymbolAudioContext.collect:
        return 'COIN_COLLECT';
      case SymbolAudioContext.stack:
        return 'SYMBOL_STACK';
      case SymbolAudioContext.trigger:
        return 'FEATURE_TRIGGER';
      case SymbolAudioContext.anticipation:
        return 'ANTICIPATION_TENSION';
    }
  }

  bool _isContextPooled(SymbolAudioContext context) {
    // Land and collect are rapid-fire events
    return context == SymbolAudioContext.land ||
        context == SymbolAudioContext.collect ||
        context == SymbolAudioContext.stack;
  }

  /// Update stage definition
  void updateStage(String name, StageDefinition definition) {
    final normalized = name.toUpperCase().trim();
    if (_customStages.containsKey(normalized)) {
      _customStages[normalized] = definition.copyWith(name: normalized);
      notifyListeners();
    }
  }

  /// Export configuration to JSON
  Map<String, dynamic> toJson() {
    return {
      'customStages': _customStages.values.map((s) => s.toJson()).toList(),
    };
  }

  /// Import configuration from JSON
  void fromJson(Map<String, dynamic> json) {
    final customList = json['customStages'] as List<dynamic>?;
    if (customList != null) {
      _customStages.clear();
      for (final item in customList) {
        final stage = StageDefinition.fromJson(item as Map<String, dynamic>);
        _customStages[stage.name.toUpperCase()] = stage;
      }
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DEFAULT STAGES
  // ═══════════════════════════════════════════════════════════════════════════

  void _registerDefaultStages() {
    // ─────────────────────────────────────────────────────────────────────────
    // SPIN LIFECYCLE
    // ─────────────────────────────────────────────────────────────────────────
    // SPIN_START removed — UI_SPIN_PRESS covers button press
    // SPIN_BUTTON_PRESS removed — UI_SPIN_PRESS covers this
    _register('REEL_SPIN_LOOP', StageCategory.spin, 45, SpatialBus.reels, 'DEFAULT', isLooping: true);

    // Per-reel stops (pooled for rapid fire)
    for (var i = 0; i < 6; i++) {
      _register('REEL_STOP_$i', StageCategory.spin, 65, SpatialBus.reels, 'REEL_STOP_$i', isPooled: true);
    }
    _register('REEL_STOP', StageCategory.spin, 65, SpatialBus.reels, 'REEL_STOP', isPooled: true);
    _register('SPIN_END', StageCategory.spin, 40, SpatialBus.sfx, 'DEFAULT');

    // ─────────────────────────────────────────────────────────────────────────
    // P1.1: WIN EVALUATION — Bridge between REEL_STOP and WIN_PRESENT
    // This stage fires immediately after last reel stops and before win display
    // Audio: Short "calculation" or "whoosh" sound to fill the gap
    // ─────────────────────────────────────────────────────────────────────────
    _register('WIN_EVAL', StageCategory.win, 58, SpatialBus.sfx, 'DEFAULT');

    // ─────────────────────────────────────────────────────────────────────────
    // WIN PRESENTATION AUDIO — THE unified win sound system (win/bet ratio)
    //
    // WIN_PRESENT_LOW:   < 1x bet  — sub-bet win (often silent or subtle)
    // WIN_PRESENT_EQUAL: = 1x bet  — break-even
    // WIN_PRESENT_1:     >1x, ≤2x  — small win
    // WIN_PRESENT_2:     >2x, ≤4x  — medium win
    // WIN_PRESENT_3:     >4x, ≤8x  — good win
    // WIN_PRESENT_4:     >8x, ≤13x — great win (ducks music)
    // WIN_PRESENT_5:     >13x      — excellent win (ducks music)
    //
    // For ≥20x → BIG_WIN_TIER_1..5 (configured via BigWinConfig)
    // ─────────────────────────────────────────────────────────────────────────
    _register('WIN_PRESENT_LOW', StageCategory.win, 35, SpatialBus.sfx, 'DEFAULT');
    _register('WIN_PRESENT_EQUAL', StageCategory.win, 38, SpatialBus.sfx, 'DEFAULT');
    _register('WIN_PRESENT_1', StageCategory.win, 40, SpatialBus.sfx, 'DEFAULT');
    _register('WIN_PRESENT_2', StageCategory.win, 45, SpatialBus.sfx, 'DEFAULT');
    _register('WIN_PRESENT_3', StageCategory.win, 50, SpatialBus.sfx, 'DEFAULT');
    _register('WIN_PRESENT_4', StageCategory.win, 55, SpatialBus.sfx, 'DEFAULT', ducksMusic: true);
    _register('WIN_PRESENT_5', StageCategory.win, 65, SpatialBus.sfx, 'DEFAULT', ducksMusic: true);

    // ─────────────────────────────────────────────────────────────────────────
    // BIG WIN (≥20x bet) — Celebration
    // BIG_WIN_START/END/TIER_1..5: Registered dynamically from BigWinConfig
    // BIG_WIN_TICK_START/END: Rollup ticks during big win
    // COIN_SHOWER_START/END: Coin animation audio
    // ─────────────────────────────────────────────────────────────────────────
    _register('BIG_WIN_TRIGGER', StageCategory.win, 80, SpatialBus.sfx, 'DEFAULT');
    _register('BIG_WIN_END', StageCategory.win, 75, SpatialBus.music, 'DEFAULT');
    _register('BIG_WIN_TICK_START', StageCategory.win, 60, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('BIG_WIN_TICK_END', StageCategory.win, 55, SpatialBus.sfx, 'DEFAULT');
    _register('COIN_SHOWER_START', StageCategory.win, 75, SpatialBus.sfx, 'DEFAULT');
    _register('COIN_SHOWER_END', StageCategory.win, 70, SpatialBus.sfx, 'DEFAULT');
    _register('MAX_AWARD_CAP', StageCategory.win, 95, SpatialBus.sfx, 'JACKPOT_TRIGGER', ducksMusic: true);

    // Rollup counter (pooled for rapid fire)
    _register('ROLLUP_START', StageCategory.win, 45, SpatialBus.sfx, 'DEFAULT');
    _register('ROLLUP_TICK', StageCategory.win, 25, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('ROLLUP_TICK_FAST', StageCategory.win, 25, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('ROLLUP_TICK_SLOW', StageCategory.win, 25, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('ROLLUP_END', StageCategory.win, 50, SpatialBus.sfx, 'DEFAULT');
    _register('ROLLUP_SKIP', StageCategory.win, 45, SpatialBus.sfx, 'DEFAULT');

    // Win lines (pooled)
    _register('WIN_LINE_SHOW', StageCategory.win, 30, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('WIN_LINE_HIDE', StageCategory.win, 20, SpatialBus.sfx, 'DEFAULT');
    _register('WIN_LINE_CYCLE', StageCategory.win, 25, SpatialBus.sfx, 'DEFAULT');
    _register('SYMBOL_WIN', StageCategory.win, 30, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('WIN_DETECTED', StageCategory.win, 55, SpatialBus.sfx, 'DEFAULT');
    _register('WIN_CALCULATE', StageCategory.win, 55, SpatialBus.sfx, 'DEFAULT');
    _register('WIN_PRESENT_END', StageCategory.win, 45, SpatialBus.sfx, 'DEFAULT');

    // No-win & Win collection
    _register('NO_WIN', StageCategory.win, 20, SpatialBus.sfx, 'DEFAULT');
    _register('WIN_COLLECT', StageCategory.win, 50, SpatialBus.sfx, 'DEFAULT');
    _register('WIN_FANFARE', StageCategory.win, 70, SpatialBus.sfx, 'DEFAULT');

    // Special Symbol Wins — Triggered when symbols are in winning combination
    // Full hierarchy: HP1_WIN → HP_WIN → SYMBOL_WIN
    _register('WILD_WIN', StageCategory.win, 65, SpatialBus.sfx, 'WIN_BIG');
    _register('SCATTER_WIN', StageCategory.win, 70, SpatialBus.sfx, 'FREE_SPIN_TRIGGER');
    _register('BONUS_WIN', StageCategory.win, 70, SpatialBus.sfx, 'FEATURE_ENTER');

    // Per-symbol wins — High Pay symbols
    _register('HP_WIN', StageCategory.win, 45, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('HP1_WIN', StageCategory.win, 50, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('HP2_WIN', StageCategory.win, 48, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('HP3_WIN', StageCategory.win, 46, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('HP4_WIN', StageCategory.win, 44, SpatialBus.sfx, 'DEFAULT', isPooled: true);

    // Per-symbol wins — Medium Pay symbols
    _register('MP_WIN', StageCategory.win, 40, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('MP1_WIN', StageCategory.win, 43, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('MP2_WIN', StageCategory.win, 42, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('MP3_WIN', StageCategory.win, 41, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('MP4_WIN', StageCategory.win, 40, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('MP5_WIN', StageCategory.win, 39, SpatialBus.sfx, 'DEFAULT', isPooled: true);

    // Per-symbol wins — Low Pay symbols
    _register('LP_WIN', StageCategory.win, 35, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('LP1_WIN', StageCategory.win, 38, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('LP2_WIN', StageCategory.win, 37, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('LP3_WIN', StageCategory.win, 36, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('LP4_WIN', StageCategory.win, 35, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('LP5_WIN', StageCategory.win, 34, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('LP6_WIN', StageCategory.win, 33, SpatialBus.sfx, 'DEFAULT', isPooled: true);

    // Payline highlight — Triggered when win line is shown during presentation
    _register('PAYLINE_HIGHLIGHT', StageCategory.win, 28, SpatialBus.sfx, 'DEFAULT', isPooled: true);

    // ─────────────────────────────────────────────────────────────────────────
    // FEATURE / FREE SPINS
    // ─────────────────────────────────────────────────────────────────────────
    _register('FS_HOLD_INTRO', StageCategory.feature, 85, SpatialBus.sfx, 'FEATURE_ENTER', ducksMusic: true);
    _register('FS_HOLD_OUTRO', StageCategory.feature, 80, SpatialBus.sfx, 'DEFAULT');
    _register('FS_START', StageCategory.feature, 75, SpatialBus.sfx, 'DEFAULT');
    _register('FS_SPIN_START', StageCategory.feature, 55, SpatialBus.sfx, 'DEFAULT');
    _register('FS_SPIN_END', StageCategory.feature, 45, SpatialBus.sfx, 'DEFAULT');
    _register('FS_WIN', StageCategory.feature, 60, SpatialBus.sfx, 'DEFAULT');
    _register('FS_SCATTER_LAND', StageCategory.feature, 70, SpatialBus.sfx, 'DEFAULT');
    _register('FS_SCATTER_LAND_R1', StageCategory.feature, 70, SpatialBus.sfx, 'DEFAULT');
    _register('FS_SCATTER_LAND_R2', StageCategory.feature, 70, SpatialBus.sfx, 'DEFAULT');
    _register('FS_SCATTER_LAND_R3', StageCategory.feature, 70, SpatialBus.sfx, 'DEFAULT');
    _register('FS_SCATTER_LAND_R4', StageCategory.feature, 70, SpatialBus.sfx, 'DEFAULT');
    _register('FS_SCATTER_LAND_R5', StageCategory.feature, 70, SpatialBus.sfx, 'DEFAULT');
    _register('FS_STICKY_WILD', StageCategory.feature, 65, SpatialBus.sfx, 'DEFAULT');
    _register('FS_EXPANDING_WILD', StageCategory.feature, 65, SpatialBus.sfx, 'DEFAULT');
    _register('FS_MULTIPLIER_UP', StageCategory.feature, 65, SpatialBus.sfx, 'DEFAULT');
    _register('FS_RETRIGGER', StageCategory.feature, 80, SpatialBus.sfx, 'FREE_SPIN_TRIGGER', ducksMusic: true);
    _register('FS_RETRIGGER_3', StageCategory.feature, 80, SpatialBus.sfx, 'FREE_SPIN_TRIGGER', ducksMusic: true);
    _register('FS_RETRIGGER_5', StageCategory.feature, 80, SpatialBus.sfx, 'FREE_SPIN_TRIGGER', ducksMusic: true);
    _register('FS_RETRIGGER_10', StageCategory.feature, 80, SpatialBus.sfx, 'FREE_SPIN_TRIGGER', ducksMusic: true);
    _register('FS_END', StageCategory.feature, 70, SpatialBus.sfx, 'DEFAULT');

    // Scene transitions (context switches between game phases)
    _register('CONTEXT_BASE_TO_FS', StageCategory.feature, 85, SpatialBus.music, 'FEATURE_ENTER', ducksMusic: true);
    _register('CONTEXT_FS_TO_BASE', StageCategory.feature, 80, SpatialBus.music, 'DEFAULT');
    _register('CONTEXT_BASE_TO_BONUS', StageCategory.feature, 88, SpatialBus.music, 'FEATURE_ENTER', ducksMusic: true);
    _register('CONTEXT_BONUS_TO_BASE', StageCategory.feature, 78, SpatialBus.music, 'DEFAULT');
    _register('CONTEXT_BASE_TO_HOLDWIN', StageCategory.feature, 87, SpatialBus.music, 'FEATURE_ENTER', ducksMusic: true);
    _register('CONTEXT_HOLDWIN_TO_BASE', StageCategory.feature, 76, SpatialBus.music, 'DEFAULT');
    _register('CONTEXT_BASE_TO_GAMBLE', StageCategory.feature, 75, SpatialBus.music, 'DEFAULT');
    _register('CONTEXT_GAMBLE_TO_BASE', StageCategory.feature, 74, SpatialBus.music, 'DEFAULT');
    _register('CONTEXT_BASE_TO_JACKPOT', StageCategory.feature, 92, SpatialBus.music, 'WIN_EPIC', ducksMusic: true);
    _register('CONTEXT_JACKPOT_TO_BASE', StageCategory.feature, 74, SpatialBus.music, 'DEFAULT');

    // Bonus / Pick (IGT: onPickBonusStart/Select/Reveal/End)
    _register('BONUS_TRIGGER', StageCategory.feature, 85, SpatialBus.sfx, 'FEATURE_ENTER', ducksMusic: true);
    _register('BONUS_ENTER', StageCategory.feature, 75, SpatialBus.sfx, 'FEATURE_ENTER', ducksMusic: true);
    _register('BONUS_STEP', StageCategory.feature, 55, SpatialBus.sfx, 'DEFAULT');
    _register('BONUS_REVEAL', StageCategory.feature, 60, SpatialBus.sfx, 'DEFAULT');
    _register('BONUS_EXIT', StageCategory.feature, 70, SpatialBus.sfx, 'DEFAULT');
    _register('BONUS_LAND_3', StageCategory.feature, 80, SpatialBus.sfx, 'FEATURE_ENTER');
    _register('PICK_SELECT', StageCategory.feature, 55, SpatialBus.sfx, 'DEFAULT');
    _register('PICK_REVEAL', StageCategory.feature, 60, SpatialBus.sfx, 'DEFAULT');
    _register('PICK_MUSIC', StageCategory.music, 40, SpatialBus.music, 'DEFAULT', isLooping: true);

    // ─────────────────────────────────────────────────────────────────────────
    // CASCADE / TUMBLE
    // ─────────────────────────────────────────────────────────────────────────
    _register('CASCADE_START', StageCategory.cascade, 55, SpatialBus.sfx, 'DEFAULT');
    _register('CASCADE_STEP', StageCategory.cascade, 50, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('CASCADE_SYMBOL_POP', StageCategory.cascade, 45, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('CASCADE_END', StageCategory.cascade, 55, SpatialBus.sfx, 'DEFAULT');

    // Tumble variants
    _register('TUMBLE_DROP', StageCategory.cascade, 45, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('TUMBLE_LAND', StageCategory.cascade, 50, SpatialBus.sfx, 'DEFAULT', isPooled: true);

    // Cascade combos
    for (var i = 3; i <= 10; i++) {
      final priority = 55 + i * 3;
      final intent = i >= 7 ? 'WIN_EPIC' : (i >= 5 ? 'WIN_BIG' : 'DEFAULT');
      _register('CASCADE_COMBO_$i', StageCategory.cascade, priority, SpatialBus.sfx, intent, ducksMusic: i >= 6);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LAYOUT — Megaways/expanding reels (IGT: onReelExpand/Contract, onExtraRow)
    // ─────────────────────────────────────────────────────────────────────────
    _register('REEL_EXPAND_START', StageCategory.spin, 45, SpatialBus.sfx, 'DEFAULT');
    _register('REEL_EXPAND_END', StageCategory.spin, 40, SpatialBus.sfx, 'DEFAULT');
    _register('REEL_CONTRACT', StageCategory.spin, 40, SpatialBus.sfx, 'DEFAULT');
    _register('EXTRA_ROW_ENABLE', StageCategory.spin, 50, SpatialBus.sfx, 'DEFAULT');
    _register('EXTRA_ROW_DISABLE', StageCategory.spin, 40, SpatialBus.sfx, 'DEFAULT');

    // ─────────────────────────────────────────────────────────────────────────
    // STICKY SYMBOLS (IGT: onStickySymbolApply/Release)
    // ─────────────────────────────────────────────────────────────────────────
    _register('STICKY_SYMBOL_APPLY', StageCategory.symbol, 55, SpatialBus.sfx, 'DEFAULT');
    _register('STICKY_SYMBOL_RELEASE', StageCategory.symbol, 45, SpatialBus.sfx, 'DEFAULT');

    // ─────────────────────────────────────────────────────────────────────────
    // JACKPOT
    // ─────────────────────────────────────────────────────────────────────────
    _register('JACKPOT_TRIGGER', StageCategory.jackpot, 100, SpatialBus.sfx, 'JACKPOT_TRIGGER', ducksMusic: true);
    // P1.5: Expanded jackpot audio sequence (industry standard)
    _register('JACKPOT_BUILDUP', StageCategory.jackpot, 98, SpatialBus.sfx, 'JACKPOT_TRIGGER', ducksMusic: true);
    _register('JACKPOT_REVEAL', StageCategory.jackpot, 99, SpatialBus.sfx, 'JACKPOT_TRIGGER', ducksMusic: true);
    _register('JACKPOT_CELEBRATION', StageCategory.jackpot, 95, SpatialBus.sfx, 'JACKPOT_TRIGGER', ducksMusic: true, isLooping: true);
    // Tier-specific jackpots
    _register('JACKPOT_MINI', StageCategory.jackpot, 85, SpatialBus.sfx, 'JACKPOT_TRIGGER', ducksMusic: true);
    _register('JACKPOT_MINOR', StageCategory.jackpot, 90, SpatialBus.sfx, 'JACKPOT_TRIGGER', ducksMusic: true);
    _register('JACKPOT_MAJOR', StageCategory.jackpot, 95, SpatialBus.sfx, 'JACKPOT_TRIGGER', ducksMusic: true);
    _register('JACKPOT_GRAND', StageCategory.jackpot, 100, SpatialBus.sfx, 'JACKPOT_TRIGGER', ducksMusic: true);
    _register('JACKPOT_PRESENT', StageCategory.jackpot, 95, SpatialBus.sfx, 'JACKPOT_TRIGGER', ducksMusic: true);
    _register('JACKPOT_END', StageCategory.jackpot, 80, SpatialBus.sfx, 'DEFAULT');

    // ─────────────────────────────────────────────────────────────────────────
    // HOLD & SPIN / RESPIN
    // ─────────────────────────────────────────────────────────────────────────
    _register('HOLD_TRIGGER', StageCategory.hold, 80, SpatialBus.sfx, 'FEATURE_ENTER', ducksMusic: true);
    _register('HOLD_ENTER', StageCategory.hold, 70, SpatialBus.sfx, 'FEATURE_ENTER');
    _register('HOLD_SPIN', StageCategory.hold, 50, SpatialBus.sfx, 'DEFAULT');
    _register('HOLD_RESPIN_STOP', StageCategory.hold, 55, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('HOLD_SYMBOL_LAND', StageCategory.hold, 55, SpatialBus.sfx, 'DEFAULT');
    _register('HOLD_SYMBOL_LOCK', StageCategory.hold, 60, SpatialBus.sfx, 'DEFAULT');
    _register('HOLD_RESPIN_STEP', StageCategory.hold, 50, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('HOLD_RESPIN_RESET', StageCategory.hold, 60, SpatialBus.sfx, 'DEFAULT');
    _register('HOLD_GRID_FULL', StageCategory.hold, 90, SpatialBus.sfx, 'WIN_EPIC', ducksMusic: true);
    _register('HOLD_EXIT', StageCategory.hold, 65, SpatialBus.sfx, 'DEFAULT');
    _register('HOLD_MUSIC', StageCategory.music, 40, SpatialBus.music, 'DEFAULT', isLooping: true);

    // ─────────────────────────────────────────────────────────────────────────
    // WHEEL BONUS (IGT: onWheelBonusEnter/SpinStart/Tick/Stop/Reveal/Exit)
    // ─────────────────────────────────────────────────────────────────────────
    _register('WHEEL_ENTER', StageCategory.feature, 70, SpatialBus.sfx, 'FEATURE_ENTER', ducksMusic: true);
    _register('WHEEL_SPIN_START', StageCategory.feature, 55, SpatialBus.sfx, 'DEFAULT');
    _register('WHEEL_SPIN_LOOP', StageCategory.feature, 50, SpatialBus.sfx, 'DEFAULT', isLooping: true);
    _register('WHEEL_TICK', StageCategory.feature, 25, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('WHEEL_SPIN_STOP', StageCategory.feature, 60, SpatialBus.sfx, 'DEFAULT');
    _register('WHEEL_RESULT_REVEAL', StageCategory.feature, 65, SpatialBus.sfx, 'WIN_BIG');
    _register('WHEEL_EXIT', StageCategory.feature, 55, SpatialBus.sfx, 'DEFAULT');
    _register('WHEEL_MUSIC', StageCategory.music, 40, SpatialBus.music, 'DEFAULT', isLooping: true);

    // ─────────────────────────────────────────────────────────────────────────
    // CASH ON REELS / COLLECT (IGT: onCashSymbolLand/ValueReveal/CollectStart/End)
    // ─────────────────────────────────────────────────────────────────────────
    _register('CASH_SYMBOL_LAND', StageCategory.symbol, 55, SpatialBus.sfx, 'DEFAULT');
    _register('CASH_VALUE_REVEAL', StageCategory.symbol, 50, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('CASH_COLLECT_START', StageCategory.feature, 65, SpatialBus.sfx, 'DEFAULT');
    _register('CASH_COLLECT_END', StageCategory.feature, 60, SpatialBus.sfx, 'DEFAULT');

    // ─────────────────────────────────────────────────────────────────────────
    // GAMBLE
    // ─────────────────────────────────────────────────────────────────────────
    _register('GAMBLE_START', StageCategory.gamble, 55, SpatialBus.sfx, 'DEFAULT');
    _register('GAMBLE_CHOICE', StageCategory.gamble, 50, SpatialBus.sfx, 'DEFAULT');
    _register('GAMBLE_WIN', StageCategory.gamble, 65, SpatialBus.sfx, 'WIN_MEDIUM');
    _register('GAMBLE_LOSE', StageCategory.gamble, 60, SpatialBus.sfx, 'DEFAULT');
    _register('GAMBLE_COLLECT', StageCategory.gamble, 55, SpatialBus.sfx, 'DEFAULT');
    _register('GAMBLE_END', StageCategory.gamble, 50, SpatialBus.sfx, 'DEFAULT');

    // ─────────────────────────────────────────────────────────────────────────
    // SYMBOLS
    // ─────────────────────────────────────────────────────────────────────────
    _register('SYMBOL_LAND', StageCategory.symbol, 30, SpatialBus.reels, 'DEFAULT', isPooled: true);
    _register('SYMBOL_LAND_LOW', StageCategory.symbol, 25, SpatialBus.reels, 'DEFAULT', isPooled: true);
    _register('SYMBOL_LAND_MID', StageCategory.symbol, 30, SpatialBus.reels, 'DEFAULT', isPooled: true);
    _register('SYMBOL_LAND_HIGH', StageCategory.symbol, 35, SpatialBus.reels, 'DEFAULT', isPooled: true);

    // Wild
    _register('WILD_LAND', StageCategory.symbol, 60, SpatialBus.sfx, 'DEFAULT');
    _register('WILD_LAND_1', StageCategory.symbol, 60, SpatialBus.sfx, 'DEFAULT');
    _register('WILD_LAND_2', StageCategory.symbol, 65, SpatialBus.sfx, 'DEFAULT');
    _register('WILD_LAND_3', StageCategory.symbol, 70, SpatialBus.sfx, 'DEFAULT');
    _register('WILD_LAND_4', StageCategory.symbol, 75, SpatialBus.sfx, 'DEFAULT');
    _register('WILD_LAND_5', StageCategory.symbol, 80, SpatialBus.sfx, 'DEFAULT');
    _register('WILD_EXPAND', StageCategory.symbol, 65, SpatialBus.sfx, 'DEFAULT');
    _register('WILD_STICKY', StageCategory.symbol, 60, SpatialBus.sfx, 'DEFAULT');
    _register('WILD_WALKING', StageCategory.symbol, 55, SpatialBus.sfx, 'DEFAULT');
    _register('WILD_MULTIPLIER', StageCategory.symbol, 65, SpatialBus.sfx, 'DEFAULT');

    // Scatter
    _register('SCATTER_LAND', StageCategory.symbol, 55, SpatialBus.sfx, 'DEFAULT');
    _register('SCATTER_LAND_1', StageCategory.symbol, 55, SpatialBus.sfx, 'DEFAULT');
    _register('SCATTER_LAND_2', StageCategory.symbol, 60, SpatialBus.sfx, 'DEFAULT');
    _register('SCATTER_LAND_3', StageCategory.symbol, 75, SpatialBus.sfx, 'FREE_SPIN_TRIGGER');
    _register('SCATTER_LAND_4', StageCategory.symbol, 80, SpatialBus.sfx, 'FREE_SPIN_TRIGGER');
    _register('SCATTER_LAND_5', StageCategory.symbol, 85, SpatialBus.sfx, 'FREE_SPIN_TRIGGER');
    _register('SCATTER_WIN', StageCategory.symbol, 70, SpatialBus.sfx, 'DEFAULT');

    // Bonus
    _register('BONUS_LAND', StageCategory.symbol, 55, SpatialBus.sfx, 'DEFAULT');

    // ─────────────────────────────────────────────────────────────────────────
    // ANTICIPATION SYSTEM
    //
    // 3 layers of specificity:
    //   1. ANTICIPATION_TENSION — single sound for all anticipation
    //   2. ANTICIPATION_TENSION_R0..R7 — different sound per reel
    //   3. ANTICIPATION_TENSION_R*_L* — per-reel + tension level
    // Fallback: R2_L3 → R2 → TENSION
    //
    // Any reel (R0-R7) can have anticipation depending on grid config
    // and game logic. Max 8 reels supported (GridBlock allows 3-8).
    //
    // ANTICIPATION_MISS — fires when anticipation resolves without trigger
    // ─────────────────────────────────────────────────────────────────────────
    _register('ANTICIPATION_TENSION', StageCategory.symbol, 66, SpatialBus.sfx, 'ANTICIPATION');
    _register('ANTICIPATION_MISS', StageCategory.symbol, 50, SpatialBus.sfx, 'DEFAULT');

    // Per-reel tension R0-R7 (any reel can have anticipation)
    for (int r = 0; r < 8; r++) {
      _register('ANTICIPATION_TENSION_R$r', StageCategory.symbol, 67 + r, SpatialBus.sfx, 'ANTICIPATION');
      // Per-reel + tension level (L1-L4)
      for (int l = 1; l <= 4; l++) {
        _register('ANTICIPATION_TENSION_R${r}_L$l', StageCategory.symbol, 67 + r + l, SpatialBus.sfx, 'ANTICIPATION');
      }
    }

    _register('NEAR_MISS', StageCategory.symbol, 55, SpatialBus.sfx, 'NEAR_MISS');

    // P3.3: Per-reel near-miss stages (different sounds for each reel that "missed")
    // Later reels have higher priority (more dramatic)
    for (int r = 0; r < 8; r++) {
      _register('NEAR_MISS_REEL_$r', StageCategory.symbol, 50 + r * 2, SpatialBus.sfx, 'NEAR_MISS');
    }

    // Near-miss type-specific stages
    _register('NEAR_MISS_SCATTER', StageCategory.symbol, 60, SpatialBus.sfx, 'NEAR_MISS');
    _register('NEAR_MISS_BONUS', StageCategory.symbol, 60, SpatialBus.sfx, 'NEAR_MISS');
    _register('NEAR_MISS_WILD', StageCategory.symbol, 55, SpatialBus.sfx, 'NEAR_MISS');
    _register('NEAR_MISS_FEATURE', StageCategory.symbol, 58, SpatialBus.sfx, 'NEAR_MISS');
    _register('NEAR_MISS_JACKPOT', StageCategory.symbol, 65, SpatialBus.sfx, 'NEAR_MISS');

    // ─────────────────────────────────────────────────────────────────────────
    // UI — COMPREHENSIVE INDUSTRY STANDARD (NetEnt, Pragmatic, IGT, BTG)
    // ─────────────────────────────────────────────────────────────────────────

    // ═══════════════════════════════════════════════════════════════════════
    // SPIN BUTTON INTERACTIONS
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_SPIN_PRESS', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');
    _register('UI_SPIN_HOVER', StageCategory.ui, 15, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_SPIN_RELEASE', StageCategory.ui, 20, SpatialBus.ui, 'DEFAULT');
    _register('UI_STOP_PRESS', StageCategory.ui, 30, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // GENERIC BUTTON INTERACTIONS
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_BUTTON_PRESS', StageCategory.ui, 20, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_BUTTON_HOVER', StageCategory.ui, 15, SpatialBus.ui, 'DEFAULT', isPooled: true);

    // ═══════════════════════════════════════════════════════════════════════
    // BET CONTROLS
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_BET_UP', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_BET_DOWN', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_BET_MAX', StageCategory.ui, 30, SpatialBus.ui, 'DEFAULT');
    _register('UI_BET_MIN', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // AUTOPLAY
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_AUTOPLAY_START', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');
    _register('UI_AUTOPLAY_STOP', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');
    _register('UI_AUTOPLAY_CONFIG_OPEN', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_AUTOPLAY_CONFIG_CLOSE', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // TURBO / QUICK SPIN (Pragmatic Play, BTG, Play'n GO)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_TURBO_ON', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_TURBO_OFF', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_QUICKSPIN_ON', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_QUICKSPIN_OFF', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // MENUS & NAVIGATION
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_MENU_OPEN', StageCategory.ui, 30, SpatialBus.ui, 'DEFAULT');
    _register('UI_MENU_CLOSE', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_MENU_HOVER', StageCategory.ui, 15, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_MENU_SELECT', StageCategory.ui, 22, SpatialBus.ui, 'DEFAULT');
    _register('UI_TAB_SWITCH', StageCategory.ui, 20, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_PAGE_FLIP', StageCategory.ui, 18, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_SCROLL', StageCategory.ui, 12, SpatialBus.ui, 'DEFAULT', isPooled: true);

    // ═══════════════════════════════════════════════════════════════════════
    // PAYTABLE / INFO / RULES (NetEnt, Pragmatic, IGT)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_PAYTABLE_OPEN', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_PAYTABLE_CLOSE', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_PAYTABLE_PAGE', StageCategory.ui, 18, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_RULES_OPEN', StageCategory.ui, 26, SpatialBus.ui, 'DEFAULT');
    _register('UI_RULES_CLOSE', StageCategory.ui, 24, SpatialBus.ui, 'DEFAULT');
    _register('UI_HELP_OPEN', StageCategory.ui, 26, SpatialBus.ui, 'DEFAULT');
    _register('UI_HELP_CLOSE', StageCategory.ui, 24, SpatialBus.ui, 'DEFAULT');
    _register('UI_INFO_PRESS', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // SETTINGS / PREFERENCES
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_SETTINGS_OPEN', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_SETTINGS_CLOSE', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_SETTINGS_CHANGE', StageCategory.ui, 20, SpatialBus.ui, 'DEFAULT');
    _register('UI_CHECKBOX_ON', StageCategory.ui, 20, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_CHECKBOX_OFF', StageCategory.ui, 18, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_SLIDER_DRAG', StageCategory.ui, 12, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_SLIDER_RELEASE', StageCategory.ui, 18, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // AUDIO CONTROLS (NetEnt, Pragmatic, BTG — essential)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_SOUND_ON', StageCategory.ui, 30, SpatialBus.ui, 'DEFAULT');
    _register('UI_SOUND_OFF', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_MUSIC_ON', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_MUSIC_OFF', StageCategory.ui, 24, SpatialBus.ui, 'DEFAULT');
    _register('UI_SFX_ON', StageCategory.ui, 26, SpatialBus.ui, 'DEFAULT');
    _register('UI_SFX_OFF', StageCategory.ui, 22, SpatialBus.ui, 'DEFAULT');
    _register('UI_VOLUME_CHANGE', StageCategory.ui, 15, SpatialBus.ui, 'DEFAULT', isPooled: true);

    // ═══════════════════════════════════════════════════════════════════════
    // FULLSCREEN / WINDOW
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_FULLSCREEN_ENTER', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_FULLSCREEN_EXIT', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_EXIT_PRESS', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_HOME_PRESS', StageCategory.ui, 26, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // POPUPS & TOOLTIPS
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_POPUP_OPEN', StageCategory.ui, 30, SpatialBus.ui, 'DEFAULT');
    _register('UI_POPUP_CLOSE', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_TOOLTIP_SHOW', StageCategory.ui, 12, SpatialBus.ui, 'DEFAULT');
    _register('UI_TOOLTIP_HIDE', StageCategory.ui, 10, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // NOTIFICATIONS & ALERTS
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_NOTIFICATION', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');
    _register('UI_ERROR', StageCategory.ui, 45, SpatialBus.ui, 'DEFAULT');
    _register('UI_WARNING', StageCategory.ui, 40, SpatialBus.ui, 'DEFAULT');
    _register('UI_ALERT', StageCategory.ui, 42, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // BUY FEATURE (Pragmatic, BTG — Feature Buy)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_BUYIN_OPEN', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');
    _register('UI_BUYIN_CLOSE', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_BUYIN_CONFIRM', StageCategory.ui, 45, SpatialBus.ui, 'DEFAULT');
    _register('UI_BUYIN_CANCEL', StageCategory.ui, 30, SpatialBus.ui, 'DEFAULT');
    _register('UI_BUYIN_HOVER', StageCategory.ui, 18, SpatialBus.ui, 'DEFAULT');
    _register('UI_FEATURE_INFO', StageCategory.ui, 26, SpatialBus.ui, 'DEFAULT');

    // ─────────────────────────────────────────────────────────────────────────
    // GAME START (triggers base music automatically on first spin)
    // NOTE: These are looping music stages — they loop until explicitly stopped
    // ─────────────────────────────────────────────────────────────────────────
    _register('GAME_START', StageCategory.music, 5, SpatialBus.music, 'DEFAULT', isLooping: true);

    // ─────────────────────────────────────────────────────────────────────────
    // MUSIC & AMBIENT
    // ─────────────────────────────────────────────────────────────────────────
    _register('MUSIC_BASE_INTRO', StageCategory.music, 10, SpatialBus.music, 'DEFAULT');
    _register('MUSIC_BASE_OUTRO', StageCategory.music, 10, SpatialBus.music, 'DEFAULT');
    _register('MUSIC_BASE_L1', StageCategory.music, 10, SpatialBus.music, 'DEFAULT', isLooping: true);
    _register('MUSIC_BASE_L2', StageCategory.music, 10, SpatialBus.music, 'DEFAULT', isLooping: true);
    _register('MUSIC_BASE_L3', StageCategory.music, 10, SpatialBus.music, 'DEFAULT', isLooping: true);
    _register('MUSIC_BASE_L4', StageCategory.music, 10, SpatialBus.music, 'DEFAULT', isLooping: true);
    _register('MUSIC_BASE_L5', StageCategory.music, 10, SpatialBus.music, 'DEFAULT', isLooping: true);
    _register('MUSIC_TENSION', StageCategory.music, 15, SpatialBus.music, 'DEFAULT', isLooping: true);
    // Big Win music handled via BIG_WIN_START/END composite event layers
    // Free Spins music
    _register('MUSIC_FS_INTRO', StageCategory.music, 20, SpatialBus.music, 'DEFAULT');
    _register('MUSIC_FS_OUTRO', StageCategory.music, 20, SpatialBus.music, 'DEFAULT');
    _register('MUSIC_FS_L1', StageCategory.music, 20, SpatialBus.music, 'DEFAULT', isLooping: true);
    _register('MUSIC_FS_L2', StageCategory.music, 20, SpatialBus.music, 'DEFAULT', isLooping: true);
    _register('MUSIC_FS_L3', StageCategory.music, 20, SpatialBus.music, 'DEFAULT', isLooping: true);
    _register('MUSIC_FS_L4', StageCategory.music, 20, SpatialBus.music, 'DEFAULT', isLooping: true);
    _register('MUSIC_FS_L5', StageCategory.music, 20, SpatialBus.music, 'DEFAULT', isLooping: true);
    _register('AMBIENT_LOOP', StageCategory.music, 5, SpatialBus.ambience, 'DEFAULT', isLooping: true);
    _register('ATTRACT_MODE', StageCategory.music, 5, SpatialBus.music, 'DEFAULT', isLooping: true);
    _register('IDLE_LOOP', StageCategory.music, 5, SpatialBus.ambience, 'DEFAULT', isLooping: true);
  }

  void _register(
    String name,
    StageCategory category,
    int priority,
    SpatialBus bus,
    String intent, {
    bool isPooled = false,
    bool isLooping = false,
    bool ducksMusic = false,
  }) {
    _stages[name] = StageDefinition(
      name: name,
      category: category,
      priority: priority,
      bus: bus,
      spatialIntent: intent,
      isPooled: isPooled,
      isLooping: isLooping,
      ducksMusic: ducksMusic,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FALLBACK MAPPINGS (for unknown stages)
  // ═══════════════════════════════════════════════════════════════════════════

  int _getPriorityByPrefix(String stage) {
    // HIGHEST (80-100)
    if (stage.startsWith('JACKPOT')) return 95;
    if (stage.startsWith('WIN_EPIC') || stage.startsWith('WIN_ULTRA')) return 85;
    if (stage.startsWith('FS_HOLD_INTRO') || stage.startsWith('BONUS_TRIGGER')) return 85;

    // HIGH (60-79)
    if (stage.startsWith('WIN_BIG') || stage.startsWith('WIN_MEGA')) return 70;
    if (stage.startsWith('UI_SPIN_PRESS')) return 70;
    if (stage.startsWith('REEL_STOP')) return 65;
    if (stage.startsWith('WILD_')) return 60;
    if (stage.startsWith('SCATTER_')) return 60;

    // MEDIUM (40-59)
    if (stage.startsWith('WIN_') || stage.startsWith('ROLLUP_')) return 50;
    if (stage.startsWith('CASCADE_') || stage.startsWith('TUMBLE_')) return 50;
    if (stage.startsWith('FS_') || stage.startsWith('BONUS_')) return 55;
    if (stage.startsWith('GAMBLE_')) return 50;
    if (stage.startsWith('HOLD_')) return 55;

    // LOW (20-39)
    if (stage.startsWith('UI_') || stage.startsWith('SYSTEM_')) return 25;
    if (stage.startsWith('SYMBOL_')) return 30;

    // LOWEST (0-19)
    if (stage.startsWith('MUSIC_') || stage.startsWith('AMBIENT_')) return 10;
    if (stage.startsWith('IDLE_') || stage.startsWith('ATTRACT_')) return 5;

    return 50; // Default
  }

  SpatialBus _getBusByPrefix(String stage) {
    if (stage.startsWith('REEL_') || stage == 'SYMBOL_LAND' || stage.startsWith('SYMBOL_LAND_')) return SpatialBus.reels;
    if (stage.startsWith('MUSIC_') || stage.startsWith('HOLD_MUSIC') ||
        stage.startsWith('WHEEL_MUSIC') || stage.startsWith('PICK_MUSIC')) return SpatialBus.music;
    if (stage.startsWith('UI_') || stage.startsWith('SYSTEM_')) return SpatialBus.ui;
    if (stage.startsWith('AMBIENT_') || stage.startsWith('IDLE_')) return SpatialBus.ambience;
    if (stage.contains('VOICE') || stage.contains('_VO')) return SpatialBus.vo;
    return SpatialBus.sfx;
  }

  /// Fallback spatial intent based on stage prefix patterns
  String _getSpatialIntentByPrefix(String stage) {
    // REEL STOPS — per-reel spatial positioning
    if (stage.startsWith('REEL_STOP_')) {
      final suffix = stage.substring(10);
      if (suffix.length == 1 && int.tryParse(suffix) != null) {
        return 'REEL_STOP_$suffix';
      }
      return 'REEL_STOP_2'; // Default center
    }
    if (stage.startsWith('REEL_SLAM_')) {
      final suffix = stage.substring(10);
      if (suffix.length == 1 && int.tryParse(suffix) != null) {
        return 'REEL_STOP_$suffix';
      }
      return 'REEL_STOP_2';
    }
    if (stage.startsWith('REEL_SPIN')) return 'REEL_SPIN';
    if (stage.startsWith('REEL_')) return 'DEFAULT';

    // SPIN
    if (stage.startsWith('SPIN_')) return 'DEFAULT';

    // WILD — position-based or win-level
    if (stage.startsWith('WILD_LAND_')) {
      final suffix = stage.substring(10);
      if (suffix.length == 1 && int.tryParse(suffix) != null) {
        return 'REEL_STOP_$suffix';
      }
      return 'WIN_MEDIUM';
    }
    if (stage.startsWith('WILD_EXPAND') || stage.startsWith('WILD_MULTIPLY')) return 'WIN_BIG';
    if (stage.startsWith('WILD_STACK') || stage.startsWith('WILD_COLOSSAL')) return 'WIN_MEGA';
    if (stage.startsWith('WILD_')) return 'WIN_MEDIUM';

    // SCATTER — trigger free spins on 3+
    if (stage.startsWith('SCATTER_LAND_3') || stage.startsWith('SCATTER_LAND_4') || stage.startsWith('SCATTER_LAND_5')) {
      return 'FREE_SPIN_TRIGGER';
    }
    if (stage.startsWith('SCATTER_')) return 'ANTICIPATION';

    // BONUS
    if (stage.startsWith('BONUS_TRIGGER') || stage.startsWith('BONUS_ENTER')) return 'FEATURE_ENTER';
    if (stage.startsWith('BONUS_LAND_3')) return 'FEATURE_ENTER';
    if (stage.startsWith('BONUS_')) return 'DEFAULT';

    // WIN TIERS
    if (stage.contains('WIN_ULTRA') || stage.contains('WIN_TIER_7')) return 'JACKPOT_TRIGGER';
    if (stage.contains('WIN_EPIC') || stage.contains('WIN_TIER_6')) return 'WIN_EPIC';
    if (stage.contains('WIN_MEGA') || stage.contains('WIN_TIER_4') || stage.contains('WIN_TIER_5')) return 'WIN_MEGA';
    if (stage.contains('WIN_BIG') || stage.contains('WIN_TIER_3')) return 'WIN_BIG';
    if (stage.contains('WIN_MEDIUM') || stage.contains('WIN_TIER_2')) return 'WIN_MEDIUM';
    if (stage.contains('WIN_SMALL') || stage.contains('WIN_TIER_1') || stage.contains('WIN_TIER_0')) return 'WIN_SMALL';
    if (stage.startsWith('WIN_')) return 'WIN_MEDIUM';

    // BIGWIN TIERS
    if (stage.startsWith('BIGWIN_TIER_ULTRA')) return 'JACKPOT_TRIGGER';
    if (stage.startsWith('BIGWIN_TIER_EPIC')) return 'WIN_EPIC';
    if (stage.startsWith('BIGWIN_TIER_MEGA')) return 'WIN_MEGA';
    if (stage.startsWith('BIGWIN_TIER_')) return 'WIN_BIG';

    // JACKPOT
    if (stage.startsWith('JACKPOT_GRAND') || stage.startsWith('JACKPOT_MEGA')) return 'JACKPOT_TRIGGER';
    if (stage.startsWith('JACKPOT_MAJOR')) return 'WIN_EPIC';
    if (stage.startsWith('JACKPOT_MINOR')) return 'WIN_MEGA';
    if (stage.startsWith('JACKPOT_MINI')) return 'WIN_BIG';
    if (stage.startsWith('JACKPOT_')) return 'JACKPOT_TRIGGER';

    // CASCADE
    if (stage.startsWith('CASCADE_COMBO_5') || stage.startsWith('CASCADE_COMBO_6')) return 'WIN_EPIC';
    if (stage.startsWith('CASCADE_COMBO_4')) return 'WIN_MEGA';
    if (stage.startsWith('CASCADE_COMBO_3')) return 'WIN_BIG';
    if (stage.startsWith('CASCADE_COMBO_')) return 'WIN_MEDIUM';
    if (stage.startsWith('CASCADE_')) return 'CASCADE_STEP';
    if (stage.startsWith('TUMBLE_') || stage.startsWith('AVALANCHE_')) return 'CASCADE_STEP';

    // FREE SPINS
    if (stage.startsWith('FS_RETRIGGER')) return 'FREE_SPIN_TRIGGER';
    if (stage.startsWith('FS_HOLD_INTRO') || stage.startsWith('FS_TRANSITION_IN')) return 'FEATURE_ENTER';
    if (stage.startsWith('FS_END') || stage.startsWith('FS_TRANSITION_OUT')) return 'FEATURE_EXIT';
    if (stage.startsWith('FS_MULTIPLIER')) return 'WIN_BIG';
    if (stage.startsWith('FS_')) return 'DEFAULT';

    // HOLD & SPIN
    if (stage.startsWith('HOLD_TRIGGER') || stage.startsWith('HOLD_ENTER')) return 'FEATURE_ENTER';
    if (stage.startsWith('HOLD_GRID_FULL')) return 'WIN_EPIC';
    if (stage.startsWith('HOLD_JACKPOT')) return 'JACKPOT_TRIGGER';
    if (stage.startsWith('HOLD_SPECIAL')) return 'WIN_MEGA';
    if (stage.startsWith('HOLD_EXIT') || stage.startsWith('HOLD_END')) return 'FEATURE_EXIT';
    if (stage.startsWith('HOLD_COLLECT') || stage.startsWith('HOLD_SUMMARY')) return 'WIN_MEGA';
    if (stage.startsWith('HOLD_RESPIN_COUNTER_1')) return 'ANTICIPATION';
    if (stage.startsWith('HOLD_')) return 'DEFAULT';

    // ROLLUP
    if (stage.startsWith('ROLLUP_START')) return 'WIN_MEDIUM';
    if (stage.startsWith('ROLLUP_SLAM') || stage.startsWith('ROLLUP_END')) return 'WIN_BIG';
    if (stage.startsWith('ROLLUP_MILESTONE')) return 'WIN_MEDIUM';
    if (stage.startsWith('ROLLUP_')) return 'DEFAULT';

    // MULTIPLIER
    if (stage.startsWith('MULT_100') || stage.startsWith('MULT_MAX')) return 'WIN_EPIC';
    if (stage.startsWith('MULT_25') || stage.startsWith('MULT_50')) return 'WIN_MEGA';
    if (stage.startsWith('MULT_5') || stage.startsWith('MULT_10')) return 'WIN_BIG';
    if (stage.startsWith('MULT_')) return 'WIN_MEDIUM';

    // ANTICIPATION
    if (stage.startsWith('ANTICIPATION') || stage.startsWith('NEAR_MISS') || stage.startsWith('TENSION_')) {
      return 'ANTICIPATION';
    }

    // GAMBLE
    if (stage.startsWith('GAMBLE_WIN') || stage.startsWith('GAMBLE_DOUBLE')) return 'WIN_BIG';
    if (stage.startsWith('GAMBLE_MAX_WIN')) return 'WIN_MEGA';
    if (stage.startsWith('GAMBLE_')) return 'DEFAULT';

    // PICK & WHEEL
    if (stage.startsWith('PICK_REVEAL_JACKPOT')) return 'JACKPOT_TRIGGER';
    if (stage.startsWith('PICK_REVEAL_LARGE') || stage.startsWith('PICK_LEVEL_UP')) return 'WIN_BIG';
    if (stage.startsWith('PICK_REVEAL_MEDIUM') || stage.startsWith('PICK_REVEAL_MULTIPLIER')) return 'WIN_MEDIUM';
    if (stage.startsWith('PICK_REVEAL_SMALL')) return 'WIN_SMALL';
    if (stage.startsWith('WHEEL_APPEAR')) return 'FEATURE_ENTER';
    if (stage.startsWith('WHEEL_LAND') || stage.startsWith('WHEEL_PRIZE_REVEAL')) return 'WIN_BIG';
    if (stage.startsWith('WHEEL_ADVANCE')) return 'WIN_MEGA';

    // TRAIL
    if (stage.startsWith('TRAIL_ENTER')) return 'FEATURE_ENTER';
    if (stage.startsWith('TRAIL_LAND_ADVANCE')) return 'WIN_BIG';
    if (stage.startsWith('TRAIL_LAND_MULTIPLIER')) return 'WIN_MEDIUM';
    if (stage.startsWith('TRAIL_LAND_PRIZE')) return 'WIN_SMALL';

    // Default for UI, MUSIC, AMBIENT, SYSTEM
    return 'DEFAULT';
  }

  /// Known pooled stage prefixes for fallback (0-indexed for 5-reel slots)
  static const _pooledStages = {
    'REEL_STOP', 'REEL_STOP_0', 'REEL_STOP_1', 'REEL_STOP_2', 'REEL_STOP_3', 'REEL_STOP_4',
    'CASCADE_STEP', 'CASCADE_SYMBOL_POP', 'TUMBLE_DROP', 'TUMBLE_LAND',
    'ROLLUP_TICK', 'ROLLUP_TICK_FAST', 'ROLLUP_TICK_SLOW',
    'WIN_LINE_SHOW', 'SYMBOL_WIN',
    'UI_BUTTON_PRESS', 'UI_BUTTON_HOVER', 'UI_BET_UP', 'UI_BET_DOWN', 'UI_TAB_SWITCH',
    'SYMBOL_LAND', 'SYMBOL_LAND_LOW', 'SYMBOL_LAND_MID', 'SYMBOL_LAND_HIGH',
    'WHEEL_TICK', 'TRAIL_MOVE_STEP', 'HOLD_RESPIN_STOP',
  };

  /// Known looping stage names for fallback
  static const _loopingStages = {
    'REEL_SPIN_LOOP',
    // Base game layers
    'MUSIC_BASE_L1', 'MUSIC_BASE_L2', 'MUSIC_BASE_L3', 'MUSIC_BASE_L4', 'MUSIC_BASE_L5',
    // Free spins
    'MUSIC_FS_L1', 'MUSIC_FS_L2', 'MUSIC_FS_L3', 'MUSIC_FS_L4', 'MUSIC_FS_L5',
    // Bonus
    'MUSIC_BONUS_L1', 'MUSIC_BONUS_L2', 'MUSIC_BONUS_L3', 'MUSIC_BONUS_L4', 'MUSIC_BONUS_L5',
    // Hold & Spin
    'MUSIC_HOLD_L1', 'MUSIC_HOLD_L2', 'MUSIC_HOLD_L3', 'MUSIC_HOLD_L4', 'MUSIC_HOLD_L5',
    // Big Win — handled via BIG_WIN_START/END composite event layers
    // Jackpot
    'MUSIC_JACKPOT_L1', 'MUSIC_JACKPOT_L2', 'MUSIC_JACKPOT_L3', 'MUSIC_JACKPOT_L4', 'MUSIC_JACKPOT_L5',
    // Gamble
    'MUSIC_GAMBLE_L1', 'MUSIC_GAMBLE_L2', 'MUSIC_GAMBLE_L3', 'MUSIC_GAMBLE_L4', 'MUSIC_GAMBLE_L5',
    // Reveal
    'MUSIC_REVEAL_L1', 'MUSIC_REVEAL_L2', 'MUSIC_REVEAL_L3', 'MUSIC_REVEAL_L4', 'MUSIC_REVEAL_L5',
    // Tension
    'MUSIC_TENSION_LOW', 'MUSIC_TENSION_MED', 'MUSIC_TENSION_HIGH',
    // Legacy compat
    'MUSIC_BASE', 'MUSIC_FREESPINS', 'MUSIC_HOLD', 'MUSIC_BONUS',
    'MUSIC_BIG_WIN', 'MUSIC_JACKPOT', 'MUSIC_GAMBLE',
    'AMBIENT_LOOP', 'ATTRACT_MODE', 'IDLE_LOOP', 'ATTRACT_LOOP',
    'ANTICIPATION_TENSION',
    'GAME_START', 'GAME_MUSIC',
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIORITY TIER PRESETS — P3.8
  // ═══════════════════════════════════════════════════════════════════════════

  /// Active priority preset (null = default)
  PriorityTierPreset? _activePreset;

  /// User-defined priority presets
  final Map<String, PriorityTierPreset> _presets = {};

  /// Get active preset
  PriorityTierPreset? get activePreset => _activePreset;

  /// Get all presets (built-in + custom)
  List<PriorityTierPreset> get allPresets => [
    ...PriorityTierPreset.builtInPresets,
    ..._presets.values,
  ];

  /// Apply a priority preset
  void applyPreset(PriorityTierPreset preset) {
    _activePreset = preset;

    // Apply category-based priority overrides
    for (final stage in _stages.values.toList()) {
      final categoryPriority = preset.getCategoryPriority(stage.category);
      if (categoryPriority != null) {
        _stages[stage.name] = stage.copyWith(priority: categoryPriority);
      }
    }

    // Apply stage-specific overrides
    for (final entry in preset.stageOverrides.entries) {
      final stage = _stages[entry.key];
      if (stage != null) {
        _stages[entry.key] = stage.copyWith(priority: entry.value);
      }
    }

    notifyListeners();
  }

  /// Reset to default priorities
  void resetToDefaults() {
    _activePreset = null;
    _stages.clear();
    _registerDefaultStages();
    notifyListeners();
  }

  /// Save custom preset
  void savePreset(PriorityTierPreset preset) {
    _presets[preset.id] = preset;
    notifyListeners();
  }

  /// Delete custom preset
  void deletePreset(String presetId) {
    if (_presets.remove(presetId) != null) {
      if (_activePreset?.id == presetId) {
        _activePreset = null;
      }
      notifyListeners();
    }
  }

  /// Export presets to JSON
  Map<String, dynamic> presetsToJson() {
    return {
      'activePresetId': _activePreset?.id,
      'customPresets': _presets.values.map((p) => p.toJson()).toList(),
    };
  }

  /// Import presets from JSON
  void presetsFromJson(Map<String, dynamic> json) {
    final customList = json['customPresets'] as List<dynamic>?;
    if (customList != null) {
      _presets.clear();
      for (final item in customList) {
        final preset = PriorityTierPreset.fromJson(item as Map<String, dynamic>);
        _presets[preset.id] = preset;
      }
    }

    final activeId = json['activePresetId'] as String?;
    if (activeId != null) {
      final preset = _presets[activeId] ??
          PriorityTierPreset.builtInPresets.where((p) => p.id == activeId).firstOrNull;
      if (preset != null) {
        applyPreset(preset);
      }
    } else {
      _activePreset = null;
    }
    notifyListeners();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PRIORITY TIER PRESET — Configuration for priority mappings
// ═══════════════════════════════════════════════════════════════════════════

/// Priority profile style defining overall priority distribution
enum PriorityProfileStyle {
  balanced,     // Even distribution across tiers
  aggressive,   // High priorities for critical events
  conservative, // Lower priorities, more voice sharing
  cinematic,    // Emphasis on big moments
  arcade,       // Fast, responsive, short sounds priority
  custom,       // User-defined
}

extension PriorityProfileStyleExtension on PriorityProfileStyle {
  String get label => switch (this) {
    PriorityProfileStyle.balanced => 'Balanced',
    PriorityProfileStyle.aggressive => 'Aggressive',
    PriorityProfileStyle.conservative => 'Conservative',
    PriorityProfileStyle.cinematic => 'Cinematic',
    PriorityProfileStyle.arcade => 'Arcade',
    PriorityProfileStyle.custom => 'Custom',
  };

  String get description => switch (this) {
    PriorityProfileStyle.balanced => 'Even priority distribution across all event types',
    PriorityProfileStyle.aggressive => 'Critical events always take priority over ambient',
    PriorityProfileStyle.conservative => 'More voice sharing, smoother transitions',
    PriorityProfileStyle.cinematic => 'Big wins and jackpots dominate the soundscape',
    PriorityProfileStyle.arcade => 'Fast, responsive sounds for arcade-style games',
    PriorityProfileStyle.custom => 'User-defined priority configuration',
  };

  int get color => switch (this) {
    PriorityProfileStyle.balanced => 0xFF4A9EFF,
    PriorityProfileStyle.aggressive => 0xFFFF4040,
    PriorityProfileStyle.conservative => 0xFF40FF90,
    PriorityProfileStyle.cinematic => 0xFFFFD700,
    PriorityProfileStyle.arcade => 0xFFFF9040,
    PriorityProfileStyle.custom => 0xFFE040FB,
  };
}

/// Priority tier preset — defines priority mappings for stages
class PriorityTierPreset {
  final String id;
  final String name;
  final String description;
  final PriorityProfileStyle style;
  final bool isBuiltIn;
  final DateTime createdAt;

  /// Category-based priority mappings (0-100)
  final Map<StageCategory, int> categoryPriorities;

  /// Stage-specific priority overrides (0-100)
  final Map<String, int> stageOverrides;

  const PriorityTierPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.style,
    this.isBuiltIn = false,
    required this.createdAt,
    this.categoryPriorities = const {},
    this.stageOverrides = const {},
  });

  /// Get priority for category (null = use default)
  int? getCategoryPriority(StageCategory category) {
    return categoryPriorities[category];
  }

  /// Get priority for stage (null = use category or default)
  int? getStagePriority(String stage) {
    return stageOverrides[stage.toUpperCase()];
  }

  PriorityTierPreset copyWith({
    String? id,
    String? name,
    String? description,
    PriorityProfileStyle? style,
    bool? isBuiltIn,
    DateTime? createdAt,
    Map<StageCategory, int>? categoryPriorities,
    Map<String, int>? stageOverrides,
  }) {
    return PriorityTierPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      style: style ?? this.style,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdAt: createdAt ?? this.createdAt,
      categoryPriorities: categoryPriorities ?? this.categoryPriorities,
      stageOverrides: stageOverrides ?? this.stageOverrides,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'style': style.name,
    'isBuiltIn': isBuiltIn,
    'createdAt': createdAt.toIso8601String(),
    'categoryPriorities': categoryPriorities.map((k, v) => MapEntry(k.name, v)),
    'stageOverrides': stageOverrides,
  };

  factory PriorityTierPreset.fromJson(Map<String, dynamic> json) {
    return PriorityTierPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      style: PriorityProfileStyle.values.firstWhere(
        (s) => s.name == json['style'],
        orElse: () => PriorityProfileStyle.custom,
      ),
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      categoryPriorities: (json['categoryPriorities'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(
          StageCategory.values.firstWhere((c) => c.name == k, orElse: () => StageCategory.custom),
          v as int,
        ),
      ) ?? {},
      stageOverrides: (json['stageOverrides'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as int),
      ) ?? {},
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILT-IN PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  static final List<PriorityTierPreset> builtInPresets = [
    _balancedPreset,
    _aggressivePreset,
    _conservativePreset,
    _cinematicPreset,
    _arcadePreset,
  ];

  /// Balanced — Even distribution
  static final _balancedPreset = PriorityTierPreset(
    id: 'builtin_balanced',
    name: 'Balanced',
    description: 'Even priority distribution across all categories',
    style: PriorityProfileStyle.balanced,
    isBuiltIn: true,
    createdAt: DateTime(2026, 1, 1),
    categoryPriorities: {
      StageCategory.jackpot: 95,
      StageCategory.win: 60,
      StageCategory.feature: 70,
      StageCategory.cascade: 55,
      StageCategory.spin: 50,
      StageCategory.hold: 65,
      StageCategory.gamble: 55,
      StageCategory.symbol: 40,
      StageCategory.ui: 25,
      StageCategory.music: 15,
    },
  );

  /// Aggressive — Critical events always win
  static final _aggressivePreset = PriorityTierPreset(
    id: 'builtin_aggressive',
    name: 'Aggressive',
    description: 'Critical events always take priority',
    style: PriorityProfileStyle.aggressive,
    isBuiltIn: true,
    createdAt: DateTime(2026, 1, 1),
    categoryPriorities: {
      StageCategory.jackpot: 100,
      StageCategory.win: 85,
      StageCategory.feature: 90,
      StageCategory.cascade: 75,
      StageCategory.spin: 70,
      StageCategory.hold: 80,
      StageCategory.gamble: 65,
      StageCategory.symbol: 50,
      StageCategory.ui: 20,
      StageCategory.music: 5,
    },
    stageOverrides: {
      'WIN_ULTRA': 100,
      'WIN_EPIC': 98,
      'WIN_MEGA': 95,
      'FS_HOLD_INTRO': 98,
      'BONUS_TRIGGER': 98,
    },
  );

  /// Conservative — More voice sharing
  static final _conservativePreset = PriorityTierPreset(
    id: 'builtin_conservative',
    name: 'Conservative',
    description: 'Lower priorities, smoother voice transitions',
    style: PriorityProfileStyle.conservative,
    isBuiltIn: true,
    createdAt: DateTime(2026, 1, 1),
    categoryPriorities: {
      StageCategory.jackpot: 80,
      StageCategory.win: 50,
      StageCategory.feature: 55,
      StageCategory.cascade: 45,
      StageCategory.spin: 40,
      StageCategory.hold: 50,
      StageCategory.gamble: 45,
      StageCategory.symbol: 35,
      StageCategory.ui: 30,
      StageCategory.music: 25,
    },
  );

  /// Cinematic — Big moments dominate
  static final _cinematicPreset = PriorityTierPreset(
    id: 'builtin_cinematic',
    name: 'Cinematic',
    description: 'Big wins and jackpots dominate the soundscape',
    style: PriorityProfileStyle.cinematic,
    isBuiltIn: true,
    createdAt: DateTime(2026, 1, 1),
    categoryPriorities: {
      StageCategory.jackpot: 100,
      StageCategory.win: 75,
      StageCategory.feature: 85,
      StageCategory.cascade: 60,
      StageCategory.spin: 35,
      StageCategory.hold: 70,
      StageCategory.gamble: 55,
      StageCategory.symbol: 30,
      StageCategory.ui: 15,
      StageCategory.music: 40, // Music is important for cinematic
    },
    stageOverrides: {
      'WIN_ULTRA': 100,
      'WIN_EPIC': 98,
      'WIN_MEGA': 95,
      'WIN_BIG': 85,
      'JACKPOT_GRAND': 100,
      'JACKPOT_MAJOR': 98,
      'FS_HOLD_INTRO': 95,
      'BIG_WIN_START': 50, // Big win gets extra priority
      'ANTICIPATION_TENSION': 70,
    },
  );

  /// Arcade — Fast, responsive
  static final _arcadePreset = PriorityTierPreset(
    id: 'builtin_arcade',
    name: 'Arcade',
    description: 'Fast, responsive sounds for arcade-style games',
    style: PriorityProfileStyle.arcade,
    isBuiltIn: true,
    createdAt: DateTime(2026, 1, 1),
    categoryPriorities: {
      StageCategory.jackpot: 90,
      StageCategory.win: 70,
      StageCategory.feature: 75,
      StageCategory.cascade: 65,
      StageCategory.spin: 80, // Spin sounds are important
      StageCategory.hold: 70,
      StageCategory.gamble: 60,
      StageCategory.symbol: 55, // Symbol lands are audible
      StageCategory.ui: 50, // UI feedback is important
      StageCategory.music: 10,
    },
    stageOverrides: {
      'UI_SPIN_PRESS': 85,
      'REEL_STOP': 75,
      'REEL_STOP_0': 75,
      'REEL_STOP_1': 75,
      'REEL_STOP_2': 75,
      'REEL_STOP_3': 75,
      'REEL_STOP_4': 75,
      'UI_BUTTON_PRESS': 60,
      'CASCADE_STEP': 70,
    },
  );
}
