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

import 'package:flutter/foundation.dart';
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

  /// Get all stage names
  List<String> get allStageNames => [..._stages.keys, ..._customStages.keys]..sort();

  /// Get stages by category
  List<StageDefinition> getByCategory(StageCategory category) {
    return allStages.where((s) => s.category == category).toList();
  }

  /// Get all stage definitions
  List<StageDefinition> get allStages => [
    ..._stages.values,
    ..._customStages.values,
  ];

  /// Get stage definition by name (case insensitive)
  StageDefinition? getStage(String name) {
    final normalized = name.toUpperCase().trim();
    return _stages[normalized] ?? _customStages[normalized];
  }

  /// Get priority for stage (0-100)
  int getPriority(String stage) {
    final def = getStage(stage);
    if (def != null) return def.priority;

    // Fallback: prefix-based priority
    return _getPriorityByPrefix(stage.toUpperCase());
  }

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
    _register('SPIN_START', StageCategory.spin, 70, SpatialBus.sfx, 'SPIN_START');
    _register('SPIN_BUTTON_PRESS', StageCategory.spin, 60, SpatialBus.ui, 'DEFAULT');
    _register('REEL_SPIN_LOOP', StageCategory.spin, 45, SpatialBus.reels, 'DEFAULT', isLooping: true);

    // Per-reel stops (pooled for rapid fire)
    for (var i = 0; i < 6; i++) {
      _register('REEL_STOP_$i', StageCategory.spin, 65, SpatialBus.reels, 'REEL_STOP_$i', isPooled: true);
    }
    _register('REEL_STOP', StageCategory.spin, 65, SpatialBus.reels, 'REEL_STOP', isPooled: true);
    _register('SPIN_END', StageCategory.spin, 40, SpatialBus.sfx, 'DEFAULT');

    // ─────────────────────────────────────────────────────────────────────────
    // WIN LIFECYCLE
    // ─────────────────────────────────────────────────────────────────────────
    _register('WIN_PRESENT', StageCategory.win, 55, SpatialBus.sfx, 'DEFAULT');
    _register('WIN_SMALL', StageCategory.win, 50, SpatialBus.sfx, 'WIN_SMALL');
    _register('WIN_MEDIUM', StageCategory.win, 55, SpatialBus.sfx, 'WIN_MEDIUM');
    _register('WIN_BIG', StageCategory.win, 65, SpatialBus.sfx, 'WIN_BIG', ducksMusic: true);
    _register('WIN_MEGA', StageCategory.win, 75, SpatialBus.sfx, 'WIN_EPIC', ducksMusic: true);
    _register('WIN_EPIC', StageCategory.win, 85, SpatialBus.sfx, 'WIN_EPIC', ducksMusic: true);
    _register('WIN_ULTRA', StageCategory.win, 90, SpatialBus.sfx, 'JACKPOT_TRIGGER', ducksMusic: true);

    // Win tiers (0-7)
    for (var i = 0; i <= 7; i++) {
      final priority = 45 + i * 5;
      final intent = i < 3 ? 'WIN_SMALL' : (i < 5 ? 'WIN_MEDIUM' : 'WIN_BIG');
      _register('WIN_TIER_$i', StageCategory.win, priority, SpatialBus.sfx, intent, ducksMusic: i >= 4);
    }

    // Rollup (pooled for rapid fire)
    _register('ROLLUP_START', StageCategory.win, 45, SpatialBus.sfx, 'DEFAULT');
    _register('ROLLUP_TICK', StageCategory.win, 25, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('ROLLUP_TICK_FAST', StageCategory.win, 25, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('ROLLUP_TICK_SLOW', StageCategory.win, 25, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('ROLLUP_END', StageCategory.win, 50, SpatialBus.sfx, 'DEFAULT');

    // Win lines (pooled)
    _register('WIN_LINE_SHOW', StageCategory.win, 30, SpatialBus.sfx, 'DEFAULT', isPooled: true);
    _register('WIN_LINE_HIDE', StageCategory.win, 20, SpatialBus.sfx, 'DEFAULT');
    _register('WIN_SYMBOL_HIGHLIGHT', StageCategory.win, 30, SpatialBus.sfx, 'DEFAULT', isPooled: true);

    // ─────────────────────────────────────────────────────────────────────────
    // FEATURE / FREE SPINS
    // ─────────────────────────────────────────────────────────────────────────
    _register('FS_TRIGGER', StageCategory.feature, 85, SpatialBus.sfx, 'FREE_SPIN_TRIGGER', ducksMusic: true);
    _register('FS_ENTER', StageCategory.feature, 75, SpatialBus.sfx, 'FEATURE_ENTER', ducksMusic: true);
    _register('FS_SPIN_START', StageCategory.feature, 55, SpatialBus.sfx, 'SPIN_START');
    _register('FS_SPIN_END', StageCategory.feature, 45, SpatialBus.sfx, 'DEFAULT');
    _register('FS_RETRIGGER', StageCategory.feature, 80, SpatialBus.sfx, 'FREE_SPIN_TRIGGER', ducksMusic: true);
    _register('FS_EXIT', StageCategory.feature, 70, SpatialBus.sfx, 'DEFAULT');
    _register('FS_MUSIC', StageCategory.music, 40, SpatialBus.music, 'DEFAULT', isLooping: true);

    // Bonus
    _register('BONUS_TRIGGER', StageCategory.feature, 85, SpatialBus.sfx, 'FEATURE_ENTER', ducksMusic: true);
    _register('BONUS_ENTER', StageCategory.feature, 75, SpatialBus.sfx, 'FEATURE_ENTER', ducksMusic: true);
    _register('BONUS_STEP', StageCategory.feature, 55, SpatialBus.sfx, 'DEFAULT');
    _register('BONUS_REVEAL', StageCategory.feature, 60, SpatialBus.sfx, 'DEFAULT');
    _register('BONUS_EXIT', StageCategory.feature, 70, SpatialBus.sfx, 'DEFAULT');
    _register('BONUS_LAND_3', StageCategory.feature, 80, SpatialBus.sfx, 'FEATURE_ENTER');

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
    // JACKPOT
    // ─────────────────────────────────────────────────────────────────────────
    _register('JACKPOT_TRIGGER', StageCategory.jackpot, 100, SpatialBus.sfx, 'JACKPOT_TRIGGER', ducksMusic: true);
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
    _register('HOLD_RESPIN_RESET', StageCategory.hold, 60, SpatialBus.sfx, 'DEFAULT');
    _register('HOLD_GRID_FULL', StageCategory.hold, 90, SpatialBus.sfx, 'WIN_EPIC', ducksMusic: true);
    _register('HOLD_EXIT', StageCategory.hold, 65, SpatialBus.sfx, 'DEFAULT');
    _register('HOLD_MUSIC', StageCategory.music, 40, SpatialBus.music, 'DEFAULT', isLooping: true);

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
    _register('WILD_EXPAND', StageCategory.symbol, 65, SpatialBus.sfx, 'DEFAULT');
    _register('WILD_STICKY', StageCategory.symbol, 60, SpatialBus.sfx, 'DEFAULT');
    _register('WILD_WALKING', StageCategory.symbol, 55, SpatialBus.sfx, 'DEFAULT');
    _register('WILD_MULTIPLIER', StageCategory.symbol, 65, SpatialBus.sfx, 'DEFAULT');

    // Scatter
    _register('SCATTER_LAND', StageCategory.symbol, 55, SpatialBus.sfx, 'DEFAULT');
    _register('SCATTER_LAND_2', StageCategory.symbol, 60, SpatialBus.sfx, 'DEFAULT');
    _register('SCATTER_LAND_3', StageCategory.symbol, 75, SpatialBus.sfx, 'FREE_SPIN_TRIGGER');
    _register('SCATTER_LAND_4', StageCategory.symbol, 80, SpatialBus.sfx, 'FREE_SPIN_TRIGGER');
    _register('SCATTER_LAND_5', StageCategory.symbol, 85, SpatialBus.sfx, 'FREE_SPIN_TRIGGER');

    // Anticipation
    _register('ANTICIPATION_ON', StageCategory.symbol, 65, SpatialBus.sfx, 'ANTICIPATION');
    _register('ANTICIPATION_OFF', StageCategory.symbol, 45, SpatialBus.sfx, 'DEFAULT');
    _register('NEAR_MISS', StageCategory.symbol, 55, SpatialBus.sfx, 'NEAR_MISS');

    // ─────────────────────────────────────────────────────────────────────────
    // UI
    // ─────────────────────────────────────────────────────────────────────────
    _register('UI_BUTTON_PRESS', StageCategory.ui, 20, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_BUTTON_HOVER', StageCategory.ui, 15, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_BET_UP', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_BET_DOWN', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_TAB_SWITCH', StageCategory.ui, 20, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('MENU_OPEN', StageCategory.ui, 30, SpatialBus.ui, 'DEFAULT');
    _register('MENU_CLOSE', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('AUTOPLAY_START', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');
    _register('AUTOPLAY_STOP', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');

    // ─────────────────────────────────────────────────────────────────────────
    // GAME START (triggers base music automatically on first spin)
    // ─────────────────────────────────────────────────────────────────────────
    _register('GAME_START', StageCategory.music, 5, SpatialBus.music, 'DEFAULT');
    _register('BASE_GAME_START', StageCategory.music, 5, SpatialBus.music, 'DEFAULT');

    // ─────────────────────────────────────────────────────────────────────────
    // MUSIC & AMBIENT
    // ─────────────────────────────────────────────────────────────────────────
    _register('MUSIC_BASE', StageCategory.music, 10, SpatialBus.music, 'DEFAULT', isLooping: true);
    _register('MUSIC_TENSION', StageCategory.music, 15, SpatialBus.music, 'DEFAULT', isLooping: true);
    _register('MUSIC_BIGWIN', StageCategory.music, 25, SpatialBus.music, 'DEFAULT');
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
    if (stage.startsWith('FS_TRIGGER') || stage.startsWith('BONUS_TRIGGER')) return 85;

    // HIGH (60-79)
    if (stage.startsWith('WIN_BIG') || stage.startsWith('WIN_MEGA')) return 70;
    if (stage.startsWith('SPIN_START')) return 70;
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
    if (stage.startsWith('REEL_') || stage.startsWith('SYMBOL_LAND')) return SpatialBus.reels;
    if (stage.startsWith('MUSIC_') || stage.startsWith('FS_MUSIC') || stage.startsWith('HOLD_MUSIC')) return SpatialBus.music;
    if (stage.startsWith('UI_') || stage.startsWith('SYSTEM_') || stage.startsWith('MENU_')) return SpatialBus.ui;
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
    if (stage.startsWith('SPIN_')) return 'SPIN_START';

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
    if (stage.startsWith('FS_TRIGGER') || stage.startsWith('FS_RETRIGGER')) return 'FREE_SPIN_TRIGGER';
    if (stage.startsWith('FS_ENTER') || stage.startsWith('FS_TRANSITION_IN')) return 'FEATURE_ENTER';
    if (stage.startsWith('FS_EXIT') || stage.startsWith('FS_TRANSITION_OUT')) return 'FEATURE_EXIT';
    if (stage.startsWith('FS_SUMMARY')) return 'WIN_MEGA';
    if (stage.startsWith('FS_MULTIPLIER')) return 'WIN_BIG';
    if (stage.startsWith('FS_LAST_SPIN')) return 'ANTICIPATION';
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
    'WIN_LINE_SHOW', 'WIN_SYMBOL_HIGHLIGHT',
    'UI_BUTTON_PRESS', 'UI_BUTTON_HOVER', 'UI_BET_UP', 'UI_BET_DOWN', 'UI_TAB_SWITCH',
    'SYMBOL_LAND', 'SYMBOL_LAND_LOW', 'SYMBOL_LAND_MID', 'SYMBOL_LAND_HIGH',
    'WHEEL_TICK', 'TRAIL_MOVE_STEP', 'HOLD_RESPIN_STOP',
  };

  /// Known looping stage names for fallback
  static const _loopingStages = {
    'REEL_SPIN_LOOP',
    'MUSIC_BASE', 'MUSIC_TENSION', 'MUSIC_FEATURE',
    'FS_MUSIC', 'HOLD_MUSIC', 'BONUS_MUSIC',
    'AMBIENT_LOOP', 'ATTRACT_MODE', 'IDLE_LOOP',
    'ANTICIPATION_LOOP', 'FEATURE_MUSIC',
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
      'FS_TRIGGER': 98,
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
      'FS_TRIGGER': 95,
      'MUSIC_BIGWIN': 50, // Big win music gets extra priority
      'ANTICIPATION_ON': 70,
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
      'SPIN_START': 85,
      'SPIN_BUTTON_PRESS': 80,
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
