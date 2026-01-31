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
  /// - BIG_WIN_INTRO, BIG_WIN_TIER_1..5, BIG_WIN_END — Big win celebration
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
      name: BigWinConfig.introStageName, // BIG_WIN_INTRO
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
      name: BigWinConfig.fadeOutStageName, // BIG_WIN_FADE_OUT
      category: StageCategory.win,
      priority: 70,
      description: 'Big win fade out transition',
    );

    _registerWinStage(
      name: BigWinConfig.rollupTickStageName, // BIG_WIN_ROLLUP_TICK
      category: StageCategory.win,
      priority: 60,
      isPooled: true, // Rapid-fire event
      description: 'Big win rollup tick',
    );

    notifyListeners();
    debugPrint('[StageConfig] Registered ${_winTierGeneratedStages.length} P5 win tier stages');
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
  /// - SYMBOL_LAND_{ID} — Symbol landing on reel
  /// - WIN_SYMBOL_HIGHLIGHT_{ID} — Symbol highlighted during win
  /// - SYMBOL_EXPAND_{ID} — Wild/symbol expansion
  /// - SYMBOL_LOCK_{ID} — Symbol locking (Hold & Win)
  /// - SYMBOL_TRANSFORM_{ID} — Symbol transformation
  /// - SYMBOL_COLLECT_{ID} — Coin/gem collection
  /// - SYMBOL_STACK_{ID} — Symbol stacking
  /// - SYMBOL_TRIGGER_{ID} — Feature trigger
  /// - ANTICIPATION_{ID} — Anticipation before feature
  void registerSymbolStages(SymbolDefinition symbol) {
    final id = symbol.id.toUpperCase();
    final priority = _getPriorityForSymbolType(symbol.type);
    final bus = _getBusForSymbolType(symbol.type);

    // Register each context-specific stage (contexts are strings like 'land', 'win', etc.)
    for (final contextStr in symbol.contexts) {
      final context = SymbolAudioContext.fromString(contextStr);
      if (context == null) {
        debugPrint('[StageConfig] Unknown context: $contextStr for symbol: ${symbol.id}');
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

    debugPrint('[StageConfig] Registered ${symbol.contexts.length} stages for symbol: ${symbol.id}');
  }

  /// Remove all stages for a symbol
  void removeSymbolStages(String symbolId) {
    final id = symbolId.toUpperCase();
    final toRemove = <String>[];

    for (final stageName in _symbolGeneratedStages) {
      if (stageName.endsWith('_$id')) {
        toRemove.add(stageName);
      }
    }

    for (final name in toRemove) {
      _customStages.remove(name);
      _symbolGeneratedStages.remove(name);
    }

    if (toRemove.isNotEmpty) {
      debugPrint('[StageConfig] Removed ${toRemove.length} stages for symbol: $symbolId');
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
    debugPrint('[StageConfig] Synced ${_symbolGeneratedStages.length} stages from ${symbols.length} symbols');
  }

  /// Get all stage names generated from a specific symbol
  List<String> getSymbolStageNames(String symbolId) {
    final id = symbolId.toUpperCase();
    return _symbolGeneratedStages.where((s) => s.endsWith('_$id')).toList();
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
        return 'SYMBOL_LAND_$symbolId';
      case SymbolAudioContext.win:
        return 'WIN_SYMBOL_HIGHLIGHT_$symbolId';
      case SymbolAudioContext.expand:
        return 'SYMBOL_EXPAND_$symbolId';
      case SymbolAudioContext.lock:
        return 'SYMBOL_LOCK_$symbolId';
      case SymbolAudioContext.transform:
        return 'SYMBOL_TRANSFORM_$symbolId';
      case SymbolAudioContext.collect:
        return 'SYMBOL_COLLECT_$symbolId';
      case SymbolAudioContext.stack:
        return 'SYMBOL_STACK_$symbolId';
      case SymbolAudioContext.trigger:
        return 'SYMBOL_TRIGGER_$symbolId';
      case SymbolAudioContext.anticipation:
        return 'ANTICIPATION_$symbolId';
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
        return 'SYMBOL_LAND_$symbolId';
      case SymbolAudioContext.win:
        return 'WIN_SYMBOL_HIGHLIGHT';
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
        return 'ANTICIPATION_ON';
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
    // P1.1: WIN EVALUATION — Bridge between REEL_STOP and WIN_PRESENT
    // This stage fires immediately after last reel stops and before win display
    // Audio: Short "calculation" or "whoosh" sound to fill the gap
    // ─────────────────────────────────────────────────────────────────────────
    _register('EVALUATE_WINS', StageCategory.win, 58, SpatialBus.sfx, 'DEFAULT');
    _register('WIN_EVAL', StageCategory.win, 58, SpatialBus.sfx, 'DEFAULT'); // Alias

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

    // ─────────────────────────────────────────────────────────────────────────
    // WIN PRESENTATION AUDIO — Unified win sound tiers based on win/bet ratio
    // This is THE win presentation audio system. Duration in parentheses:
    // WIN_PRESENT_1: ≤ 1x bet    (0.5s) — tiny win
    // WIN_PRESENT_2: > 1x, ≤ 2x  (1.0s)
    // WIN_PRESENT_3: > 2x, ≤ 4x  (1.5s)
    // WIN_PRESENT_4: > 4x, ≤ 8x  (2.0s)
    // WIN_PRESENT_5: > 8x, ≤ 13x (3.0s)
    // WIN_PRESENT_6: > 13x       (4.0s) — mega/epic/ultra territory
    // ─────────────────────────────────────────────────────────────────────────
    _register('WIN_PRESENT_1', StageCategory.win, 40, SpatialBus.sfx, 'DEFAULT');
    _register('WIN_PRESENT_2', StageCategory.win, 45, SpatialBus.sfx, 'DEFAULT');
    _register('WIN_PRESENT_3', StageCategory.win, 50, SpatialBus.sfx, 'WIN_SMALL');
    _register('WIN_PRESENT_4', StageCategory.win, 55, SpatialBus.sfx, 'WIN_BIG');
    _register('WIN_PRESENT_5', StageCategory.win, 65, SpatialBus.sfx, 'WIN_SUPER', ducksMusic: true);
    _register('WIN_PRESENT_6', StageCategory.win, 85, SpatialBus.sfx, 'WIN_EPIC', ducksMusic: true);

    // ─────────────────────────────────────────────────────────────────────────
    // BIG WIN (≥20x bet) — Celebration loop and coin sfx
    // BIG_WIN_LOOP: Looping celebration music (ducks base music)
    // BIG_WIN_COINS: Coin shower particle sfx
    // ─────────────────────────────────────────────────────────────────────────
    _register('BIG_WIN_LOOP', StageCategory.win, 90, SpatialBus.music, 'WIN_EPIC', ducksMusic: true, isLooping: true);
    _register('BIG_WIN_COINS', StageCategory.win, 75, SpatialBus.sfx, 'WIN_EPIC');

    // ─────────────────────────────────────────────────────────────────────────
    // WIN TIER VISUAL STAGES — Optional per-tier audio during BIG+ progression
    // These fire during tier progression display (BIG → SUPER → MEGA → ...)
    // ─────────────────────────────────────────────────────────────────────────
    _register('WIN_TIER_BIG', StageCategory.win, 55, SpatialBus.sfx, 'WIN_BIG');
    _register('WIN_TIER_SUPER', StageCategory.win, 65, SpatialBus.sfx, 'WIN_SUPER');
    _register('WIN_TIER_MEGA', StageCategory.win, 75, SpatialBus.sfx, 'WIN_MEGA');
    _register('WIN_TIER_EPIC', StageCategory.win, 85, SpatialBus.sfx, 'WIN_EPIC');
    _register('WIN_TIER_ULTRA', StageCategory.win, 95, SpatialBus.sfx, 'WIN_EPIC');

    // Rollup counter (pooled for rapid fire)
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
    _register('ANTICIPATION_LOOP', StageCategory.symbol, 60, SpatialBus.sfx, 'ANTICIPATION', isLooping: true);

    // P0.2: Per-reel tension stages — matches Rust engine output
    // Fallback hierarchy: ANTICIPATION_TENSION_R2_L3 → ANTICIPATION_TENSION_R2 → ANTICIPATION_TENSION → ANTICIPATION_ON
    _register('ANTICIPATION_TENSION', StageCategory.symbol, 66, SpatialBus.sfx, 'ANTICIPATION');

    // Per-reel tension (reel fallback — used when specific level not configured)
    // Reel 1 (index 0) never has anticipation (first reel can't trigger anticipation)
    _register('ANTICIPATION_TENSION_R1', StageCategory.symbol, 67, SpatialBus.sfx, 'ANTICIPATION');
    _register('ANTICIPATION_TENSION_R2', StageCategory.symbol, 68, SpatialBus.sfx, 'ANTICIPATION');
    _register('ANTICIPATION_TENSION_R3', StageCategory.symbol, 69, SpatialBus.sfx, 'ANTICIPATION');
    _register('ANTICIPATION_TENSION_R4', StageCategory.symbol, 70, SpatialBus.sfx, 'ANTICIPATION');

    // Full specificity: per-reel + tension level (L1=low, L2=medium, L3=high, L4=max)
    // Priority escalates with reel index and tension level (later reels + higher levels = more dramatic)
    // R1 (Reel 2): L1 only possible
    _register('ANTICIPATION_TENSION_R1_L1', StageCategory.symbol, 67, SpatialBus.sfx, 'ANTICIPATION');

    // R2 (Reel 3): L1-L2 possible
    _register('ANTICIPATION_TENSION_R2_L1', StageCategory.symbol, 68, SpatialBus.sfx, 'ANTICIPATION');
    _register('ANTICIPATION_TENSION_R2_L2', StageCategory.symbol, 69, SpatialBus.sfx, 'ANTICIPATION');

    // R3 (Reel 4): L1-L3 possible
    _register('ANTICIPATION_TENSION_R3_L1', StageCategory.symbol, 69, SpatialBus.sfx, 'ANTICIPATION');
    _register('ANTICIPATION_TENSION_R3_L2', StageCategory.symbol, 70, SpatialBus.sfx, 'ANTICIPATION');
    _register('ANTICIPATION_TENSION_R3_L3', StageCategory.symbol, 71, SpatialBus.sfx, 'ANTICIPATION');

    // R4 (Reel 5): L1-L4 all possible (maximum tension on last reel)
    _register('ANTICIPATION_TENSION_R4_L1', StageCategory.symbol, 70, SpatialBus.sfx, 'ANTICIPATION');
    _register('ANTICIPATION_TENSION_R4_L2', StageCategory.symbol, 71, SpatialBus.sfx, 'ANTICIPATION');
    _register('ANTICIPATION_TENSION_R4_L3', StageCategory.symbol, 72, SpatialBus.sfx, 'ANTICIPATION');
    _register('ANTICIPATION_TENSION_R4_L4', StageCategory.symbol, 75, SpatialBus.sfx, 'ANTICIPATION'); // MAX TENSION

    // Legacy anticipation types (optional — designers can use these for specific effects)
    _register('ANTICIPATION_HEARTBEAT', StageCategory.symbol, 64, SpatialBus.sfx, 'ANTICIPATION', isLooping: true);
    _register('ANTICIPATION_RESOLVE', StageCategory.symbol, 50, SpatialBus.sfx, 'DEFAULT');

    _register('NEAR_MISS', StageCategory.symbol, 55, SpatialBus.sfx, 'NEAR_MISS');

    // P3.3: Per-reel near-miss stages (different sounds for each reel that "missed")
    // Later reels have higher priority (more dramatic)
    _register('NEAR_MISS_REEL_0', StageCategory.symbol, 50, SpatialBus.sfx, 'NEAR_MISS');
    _register('NEAR_MISS_REEL_1', StageCategory.symbol, 52, SpatialBus.sfx, 'NEAR_MISS');
    _register('NEAR_MISS_REEL_2', StageCategory.symbol, 54, SpatialBus.sfx, 'NEAR_MISS');
    _register('NEAR_MISS_REEL_3', StageCategory.symbol, 56, SpatialBus.sfx, 'NEAR_MISS');
    _register('NEAR_MISS_REEL_4', StageCategory.symbol, 58, SpatialBus.sfx, 'NEAR_MISS');

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
    _register('UI_SPIN_DISABLED', StageCategory.ui, 20, SpatialBus.ui, 'DEFAULT');
    _register('UI_STOP_PRESS', StageCategory.ui, 30, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // GENERIC BUTTON INTERACTIONS
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_BUTTON_PRESS', StageCategory.ui, 20, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_BUTTON_HOVER', StageCategory.ui, 15, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_BUTTON_RELEASE', StageCategory.ui, 18, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_BUTTON_DISABLED', StageCategory.ui, 15, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // BET CONTROLS (NetEnt, Pragmatic Play, IGT standard)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_BET_UP', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_BET_DOWN', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_BET_MAX', StageCategory.ui, 30, SpatialBus.ui, 'DEFAULT');
    _register('UI_BET_MIN', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_BET_CHANGE', StageCategory.ui, 22, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_COIN_UP', StageCategory.ui, 22, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_COIN_DOWN', StageCategory.ui, 22, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_COIN_CHANGE', StageCategory.ui, 22, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_LINES_UP', StageCategory.ui, 22, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_LINES_DOWN', StageCategory.ui, 22, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_LINES_MAX', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_TOTALBET_CHANGE', StageCategory.ui, 22, SpatialBus.ui, 'DEFAULT', isPooled: true);

    // ═══════════════════════════════════════════════════════════════════════
    // AUTOPLAY (Industry standard — all major providers)
    // ═══════════════════════════════════════════════════════════════════════
    _register('AUTOPLAY_START', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');
    _register('AUTOPLAY_STOP', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');
    _register('UI_AUTOPLAY_CONFIG_OPEN', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_AUTOPLAY_CONFIG_CLOSE', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_AUTOPLAY_SPIN_TICK', StageCategory.ui, 18, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_AUTOPLAY_LOSS_LIMIT', StageCategory.ui, 40, SpatialBus.ui, 'DEFAULT');
    _register('UI_AUTOPLAY_WIN_LIMIT', StageCategory.ui, 40, SpatialBus.ui, 'DEFAULT');
    _register('UI_AUTOPLAY_FEATURE_STOP', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // TURBO / QUICK SPIN (Pragmatic Play, BTG, Play'n GO)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_TURBO_ON', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_TURBO_OFF', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_QUICKSPIN_ON', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_QUICKSPIN_OFF', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // MENUS & NAVIGATION (All major providers)
    // ═══════════════════════════════════════════════════════════════════════
    _register('MENU_OPEN', StageCategory.ui, 30, SpatialBus.ui, 'DEFAULT');
    _register('MENU_CLOSE', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
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
    // HISTORY / STATS (Play'n GO, NetEnt, Microgaming)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_HISTORY_OPEN', StageCategory.ui, 26, SpatialBus.ui, 'DEFAULT');
    _register('UI_HISTORY_CLOSE', StageCategory.ui, 24, SpatialBus.ui, 'DEFAULT');
    _register('UI_HISTORY_SCROLL', StageCategory.ui, 15, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_STATS_OPEN', StageCategory.ui, 26, SpatialBus.ui, 'DEFAULT');
    _register('UI_STATS_CLOSE', StageCategory.ui, 24, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // SETTINGS / PREFERENCES (All providers)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_SETTINGS_OPEN', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_SETTINGS_CLOSE', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_SETTINGS_CHANGE', StageCategory.ui, 20, SpatialBus.ui, 'DEFAULT');
    _register('UI_CHECKBOX_ON', StageCategory.ui, 20, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_CHECKBOX_OFF', StageCategory.ui, 18, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_SLIDER_DRAG', StageCategory.ui, 12, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_SLIDER_RELEASE', StageCategory.ui, 18, SpatialBus.ui, 'DEFAULT');
    _register('UI_DROPDOWN_OPEN', StageCategory.ui, 22, SpatialBus.ui, 'DEFAULT');
    _register('UI_DROPDOWN_SELECT', StageCategory.ui, 20, SpatialBus.ui, 'DEFAULT');
    _register('UI_DROPDOWN_CLOSE', StageCategory.ui, 18, SpatialBus.ui, 'DEFAULT');

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
    // FULLSCREEN / WINDOW (Desktop & Mobile)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_FULLSCREEN_ENTER', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_FULLSCREEN_EXIT', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_MINIMIZE', StageCategory.ui, 20, SpatialBus.ui, 'DEFAULT');
    _register('UI_EXIT_PRESS', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_HOME_PRESS', StageCategory.ui, 26, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // POPUPS & DIALOGS (All providers)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_POPUP_OPEN', StageCategory.ui, 30, SpatialBus.ui, 'DEFAULT');
    _register('UI_POPUP_CLOSE', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_DIALOG_OPEN', StageCategory.ui, 32, SpatialBus.ui, 'DEFAULT');
    _register('UI_DIALOG_CLOSE', StageCategory.ui, 26, SpatialBus.ui, 'DEFAULT');
    _register('UI_DIALOG_CONFIRM', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_DIALOG_CANCEL', StageCategory.ui, 24, SpatialBus.ui, 'DEFAULT');
    _register('UI_TOOLTIP_SHOW', StageCategory.ui, 12, SpatialBus.ui, 'DEFAULT');
    _register('UI_TOOLTIP_HIDE', StageCategory.ui, 10, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // BALANCE & CURRENCY (Critical for regulated markets)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_BALANCE_UPDATE', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');
    _register('UI_BALANCE_LOW', StageCategory.ui, 45, SpatialBus.ui, 'DEFAULT');
    _register('UI_BALANCE_EMPTY', StageCategory.ui, 50, SpatialBus.ui, 'DEFAULT');
    _register('UI_BALANCE_ADD', StageCategory.ui, 40, SpatialBus.ui, 'DEFAULT');
    _register('UI_WIN_TRANSFER', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');
    _register('UI_CREDIT_METER_TICK', StageCategory.ui, 18, SpatialBus.ui, 'DEFAULT', isPooled: true);

    // ═══════════════════════════════════════════════════════════════════════
    // JACKPOT METERS (IGT, Aristocrat, Scientific Games)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_JACKPOT_METER_TICK', StageCategory.ui, 20, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_JACKPOT_METER_UPDATE', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_PROGRESSIVE_GROW', StageCategory.ui, 22, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_JACKPOT_MINI_TICK', StageCategory.ui, 18, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_JACKPOT_MINOR_TICK', StageCategory.ui, 20, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_JACKPOT_MAJOR_TICK', StageCategory.ui, 22, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_JACKPOT_GRAND_TICK', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT', isPooled: true);

    // ═══════════════════════════════════════════════════════════════════════
    // NOTIFICATIONS & ALERTS (All providers)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_NOTIFICATION', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');
    _register('UI_SUCCESS', StageCategory.ui, 32, SpatialBus.ui, 'DEFAULT');
    _register('UI_ERROR', StageCategory.ui, 45, SpatialBus.ui, 'DEFAULT');
    _register('UI_WARNING', StageCategory.ui, 40, SpatialBus.ui, 'DEFAULT');
    _register('UI_ALERT', StageCategory.ui, 42, SpatialBus.ui, 'DEFAULT');
    _register('UI_INFO_TOAST', StageCategory.ui, 30, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // GAMIFICATION (Modern slots — loyalty, achievements)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_ACHIEVEMENT_UNLOCK', StageCategory.ui, 50, SpatialBus.ui, 'DEFAULT');
    _register('UI_LEVEL_UP', StageCategory.ui, 55, SpatialBus.ui, 'DEFAULT');
    _register('UI_XP_GAIN', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT', isPooled: true);
    _register('UI_REWARD_CLAIM', StageCategory.ui, 45, SpatialBus.ui, 'DEFAULT');
    _register('UI_BADGE_EARN', StageCategory.ui, 40, SpatialBus.ui, 'DEFAULT');
    _register('UI_DAILY_BONUS', StageCategory.ui, 48, SpatialBus.ui, 'DEFAULT');
    _register('UI_LOYALTY_POINT', StageCategory.ui, 22, SpatialBus.ui, 'DEFAULT', isPooled: true);

    // ═══════════════════════════════════════════════════════════════════════
    // GAME STATE (Essential for all providers)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_GAME_LOADING', StageCategory.ui, 15, SpatialBus.ui, 'DEFAULT');
    _register('UI_GAME_LOADED', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');
    _register('UI_GAME_READY', StageCategory.ui, 30, SpatialBus.ui, 'DEFAULT');
    _register('UI_GAME_START', StageCategory.ui, 38, SpatialBus.ui, 'DEFAULT');
    _register('UI_GAME_EXIT', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_GAME_PAUSE', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_GAME_RESUME', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // CONNECTION / NETWORK (Critical for online play)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_CONNECTION_LOST', StageCategory.ui, 55, SpatialBus.ui, 'DEFAULT');
    _register('UI_CONNECTION_RESTORED', StageCategory.ui, 45, SpatialBus.ui, 'DEFAULT');
    _register('UI_RECONNECTING', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');
    _register('UI_SESSION_TIMEOUT', StageCategory.ui, 50, SpatialBus.ui, 'DEFAULT');
    _register('UI_SERVER_ERROR', StageCategory.ui, 55, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // RESPONSIBLE GAMING (Regulated markets — UK, EU, AU)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_REALITY_CHECK', StageCategory.ui, 60, SpatialBus.ui, 'DEFAULT');
    _register('UI_SESSION_LIMIT', StageCategory.ui, 58, SpatialBus.ui, 'DEFAULT');
    _register('UI_PLAY_TIME_WARNING', StageCategory.ui, 55, SpatialBus.ui, 'DEFAULT');
    _register('UI_DEPOSIT_LIMIT', StageCategory.ui, 52, SpatialBus.ui, 'DEFAULT');
    _register('UI_LOSS_LIMIT_WARNING', StageCategory.ui, 55, SpatialBus.ui, 'DEFAULT');
    _register('UI_COOL_OFF_PERIOD', StageCategory.ui, 50, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // BUY FEATURE (Pragmatic, BTG — Feature Buy)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_BUYIN_OPEN', StageCategory.ui, 35, SpatialBus.ui, 'DEFAULT');
    _register('UI_BUYIN_CLOSE', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');
    _register('UI_BUYIN_CONFIRM', StageCategory.ui, 45, SpatialBus.ui, 'DEFAULT');
    _register('UI_BUYIN_CANCEL', StageCategory.ui, 30, SpatialBus.ui, 'DEFAULT');
    _register('UI_BUYIN_HOVER', StageCategory.ui, 18, SpatialBus.ui, 'DEFAULT');
    _register('UI_FEATURE_INFO', StageCategory.ui, 26, SpatialBus.ui, 'DEFAULT');

    // ═══════════════════════════════════════════════════════════════════════
    // DISPLAY UPDATES (Win/Bet meters)
    // ═══════════════════════════════════════════════════════════════════════
    _register('UI_WIN_DISPLAY_UPDATE', StageCategory.ui, 25, SpatialBus.ui, 'DEFAULT');
    _register('UI_BET_DISPLAY_UPDATE', StageCategory.ui, 22, SpatialBus.ui, 'DEFAULT');
    _register('UI_METER_FLASH', StageCategory.ui, 28, SpatialBus.ui, 'DEFAULT');

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
    'BIG_WIN_LOOP',
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
