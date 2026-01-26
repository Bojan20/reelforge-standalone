// ═══════════════════════════════════════════════════════════════════════════
// P1.16 + P1.17: EXTERNALIZED STAGE CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════
//
// Centralized configuration for stage colors, icons, and categories.
// Allows customization without modifying widget code.
//
// Usage:
//   final color = StageConfig.instance.getColor('spin_start');
//   final icon = StageConfig.instance.getIcon('win_present');
//   StageConfig.instance.registerStage('custom_stage', color: myColor, icon: Icons.star);

import 'package:flutter/material.dart';

/// P1.16 + P1.17: Stage category for grouping related stages
enum StageCategory {
  spin,       // Spin lifecycle: start, spinning, stop, end
  anticipation, // Anticipation stages
  win,        // Win presentation: present, line_show, line_hide
  rollup,     // Rollup counter stages
  bigwin,     // Big win tiers
  feature,    // Feature stages: enter, step, exit
  cascade,    // Cascade/tumble stages
  jackpot,    // Jackpot stages
  bonus,      // Bonus game stages
  gamble,     // Gamble feature stages
  music,      // Music/ambient stages
  ui,         // UI interaction stages
  system,     // System stages
  custom,     // User-defined stages
}

/// P1.16 + P1.17: Stage configuration entry
class StageConfigEntry {
  final Color color;
  final IconData icon;
  final StageCategory category;
  final String? description;
  final bool isPooled; // Rapid-fire stage requiring voice pooling

  const StageConfigEntry({
    required this.color,
    required this.icon,
    this.category = StageCategory.custom,
    this.description,
    this.isPooled = false,
  });

  StageConfigEntry copyWith({
    Color? color,
    IconData? icon,
    StageCategory? category,
    String? description,
    bool? isPooled,
  }) {
    return StageConfigEntry(
      color: color ?? this.color,
      icon: icon ?? this.icon,
      category: category ?? this.category,
      description: description ?? this.description,
      isPooled: isPooled ?? this.isPooled,
    );
  }
}

/// P1.16 + P1.17: Centralized stage configuration singleton
class StageConfig {
  StageConfig._();
  static final StageConfig instance = StageConfig._();

  // Default color for unknown stages
  static const Color defaultColor = Color(0xFF6B7280);
  static const IconData defaultIcon = Icons.circle;

  // ═══════════════════════════════════════════════════════════════════════════
  // P2.2: HIGH CONTRAST MODE
  // ═══════════════════════════════════════════════════════════════════════════

  /// P2.2: High contrast mode flag for accessibility
  bool _highContrastMode = false;

  /// P2.2: Get high contrast mode status
  bool get highContrastMode => _highContrastMode;

  /// P2.2: Enable/disable high contrast mode
  void setHighContrastMode(bool enabled) {
    _highContrastMode = enabled;
  }

  /// P2.2: High contrast colors per category (WCAG 2.1 AA compliant)
  static const Map<StageCategory, Color> _highContrastColors = {
    StageCategory.spin: Color(0xFF0066FF),      // Bright blue
    StageCategory.anticipation: Color(0xFFFF6600), // Bright orange
    StageCategory.win: Color(0xFF00FF00),       // Pure green
    StageCategory.rollup: Color(0xFFFFFF00),    // Pure yellow
    StageCategory.bigwin: Color(0xFFFF0066),    // Hot pink
    StageCategory.feature: Color(0xFF00FFFF),   // Cyan
    StageCategory.cascade: Color(0xFFFF00FF),   // Magenta
    StageCategory.jackpot: Color(0xFFFFD700),   // Gold
    StageCategory.bonus: Color(0xFF9933FF),     // Purple
    StageCategory.gamble: Color(0xFFFF3333),    // Red
    StageCategory.music: Color(0xFF33CCFF),     // Light blue
    StageCategory.ui: Color(0xFFCCCCCC),        // Light gray
    StageCategory.system: Color(0xFF999999),    // Medium gray
    StageCategory.custom: Color(0xFFFFFFFF),    // White
  };

  /// P2.2: Get high contrast color for a category
  Color _getHighContrastColor(StageCategory category) {
    return _highContrastColors[category] ?? const Color(0xFFFFFFFF);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.16: STAGE COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Built-in stage configurations
  final Map<String, StageConfigEntry> _stages = {
    // ─────────────────────────────────────────────────────────────────────────
    // SPIN LIFECYCLE
    // ─────────────────────────────────────────────────────────────────────────
    'spin_start': const StageConfigEntry(
      color: Color(0xFF4A9EFF),
      icon: Icons.play_circle_outline,
      category: StageCategory.spin,
      description: 'Spin button pressed',
    ),
    'reel_spinning': const StageConfigEntry(
      color: Color(0xFF6B7280),
      icon: Icons.sync,
      category: StageCategory.spin,
      description: 'Reels are spinning',
      isPooled: true,
    ),
    'reel_stop': const StageConfigEntry(
      color: Color(0xFF8B5CF6),
      icon: Icons.stop_circle_outlined,
      category: StageCategory.spin,
      description: 'Reel stops',
      isPooled: true,
    ),
    'reel_stop_0': const StageConfigEntry(
      color: Color(0xFF8B5CF6),
      icon: Icons.stop_circle_outlined,
      category: StageCategory.spin,
      description: 'Reel 1 stops',
      isPooled: true,
    ),
    'reel_stop_1': const StageConfigEntry(
      color: Color(0xFF8B5CF6),
      icon: Icons.stop_circle_outlined,
      category: StageCategory.spin,
      description: 'Reel 2 stops',
      isPooled: true,
    ),
    'reel_stop_2': const StageConfigEntry(
      color: Color(0xFF8B5CF6),
      icon: Icons.stop_circle_outlined,
      category: StageCategory.spin,
      description: 'Reel 3 stops',
      isPooled: true,
    ),
    'reel_stop_3': const StageConfigEntry(
      color: Color(0xFF8B5CF6),
      icon: Icons.stop_circle_outlined,
      category: StageCategory.spin,
      description: 'Reel 4 stops',
      isPooled: true,
    ),
    'reel_stop_4': const StageConfigEntry(
      color: Color(0xFF8B5CF6),
      icon: Icons.stop_circle_outlined,
      category: StageCategory.spin,
      description: 'Reel 5 stops',
      isPooled: true,
    ),
    'spin_end': const StageConfigEntry(
      color: Color(0xFF4A9EFF),
      icon: Icons.stop,
      category: StageCategory.spin,
      description: 'Spin sequence complete',
    ),
    'evaluate_wins': const StageConfigEntry(
      color: Color(0xFF6B7280),
      icon: Icons.calculate,
      category: StageCategory.spin,
      description: 'Evaluating win combinations',
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ANTICIPATION
    // ─────────────────────────────────────────────────────────────────────────
    'anticipation_on': const StageConfigEntry(
      color: Color(0xFFFF9040),
      icon: Icons.warning_amber,
      category: StageCategory.anticipation,
      description: 'Anticipation starts',
    ),
    'anticipation_off': const StageConfigEntry(
      color: Color(0xFFFF9040),
      icon: Icons.warning_amber,
      category: StageCategory.anticipation,
      description: 'Anticipation ends',
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // WIN PRESENTATION
    // ─────────────────────────────────────────────────────────────────────────
    'win_present': const StageConfigEntry(
      color: Color(0xFF40FF90),
      icon: Icons.stars,
      category: StageCategory.win,
      description: 'Win presentation starts',
    ),
    'win_line_show': const StageConfigEntry(
      color: Color(0xFF40FF90),
      icon: Icons.timeline,
      category: StageCategory.win,
      description: 'Win line displayed',
      isPooled: true,
    ),
    'win_line_hide': const StageConfigEntry(
      color: Color(0xFF40FF90),
      icon: Icons.visibility_off,
      category: StageCategory.win,
      description: 'Win line hidden',
      isPooled: true,
    ),
    'win_symbol_highlight': const StageConfigEntry(
      color: Color(0xFF40FF90),
      icon: Icons.highlight,
      category: StageCategory.win,
      description: 'Winning symbols highlighted',
      isPooled: true,
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // ROLLUP
    // ─────────────────────────────────────────────────────────────────────────
    'rollup_start': const StageConfigEntry(
      color: Color(0xFFFFD700),
      icon: Icons.trending_up,
      category: StageCategory.rollup,
      description: 'Rollup counter starts',
    ),
    'rollup_tick': const StageConfigEntry(
      color: Color(0xFFFFD700),
      icon: Icons.add_circle_outline,
      category: StageCategory.rollup,
      description: 'Rollup counter tick',
      isPooled: true,
    ),
    'rollup_end': const StageConfigEntry(
      color: Color(0xFFFFD700),
      icon: Icons.check_circle_outline,
      category: StageCategory.rollup,
      description: 'Rollup counter complete',
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // BIG WIN TIERS
    // ─────────────────────────────────────────────────────────────────────────
    'bigwin_tier': const StageConfigEntry(
      color: Color(0xFFFF4080),
      icon: Icons.emoji_events,
      category: StageCategory.bigwin,
      description: 'Big win tier determined',
    ),
    'win_present_small': const StageConfigEntry(
      color: Color(0xFF40FF90),
      icon: Icons.star_outline,
      category: StageCategory.bigwin,
      description: 'Small win (<5x)',
    ),
    'win_present_big': const StageConfigEntry(
      color: Color(0xFFFF4080),
      icon: Icons.star_half,
      category: StageCategory.bigwin,
      description: 'Big win (5-15x)',
    ),
    'win_present_super': const StageConfigEntry(
      color: Color(0xFFFF4080),
      icon: Icons.star,
      category: StageCategory.bigwin,
      description: 'Super win (15-30x)',
    ),
    'win_present_mega': const StageConfigEntry(
      color: Color(0xFFFFD700),
      icon: Icons.stars,
      category: StageCategory.bigwin,
      description: 'Mega win (30-60x)',
    ),
    'win_present_epic': const StageConfigEntry(
      color: Color(0xFFFFD700),
      icon: Icons.auto_awesome,
      category: StageCategory.bigwin,
      description: 'Epic win (60-100x)',
    ),
    'win_present_ultra': const StageConfigEntry(
      color: Color(0xFFE040FB),
      icon: Icons.workspace_premium,
      category: StageCategory.bigwin,
      description: 'Ultra win (100x+)',
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // FEATURES
    // ─────────────────────────────────────────────────────────────────────────
    'feature_enter': const StageConfigEntry(
      color: Color(0xFF40C8FF),
      icon: Icons.auto_awesome,
      category: StageCategory.feature,
      description: 'Feature game enters',
    ),
    'feature_step': const StageConfigEntry(
      color: Color(0xFF40C8FF),
      icon: Icons.skip_next,
      category: StageCategory.feature,
      description: 'Feature game step',
    ),
    'feature_exit': const StageConfigEntry(
      color: Color(0xFF40C8FF),
      icon: Icons.exit_to_app,
      category: StageCategory.feature,
      description: 'Feature game exits',
    ),
    'freespin_trigger': const StageConfigEntry(
      color: Color(0xFF40C8FF),
      icon: Icons.rocket_launch,
      category: StageCategory.feature,
      description: 'Free spins triggered',
    ),
    'freespin_start': const StageConfigEntry(
      color: Color(0xFF40C8FF),
      icon: Icons.play_arrow,
      category: StageCategory.feature,
      description: 'Free spins start',
    ),
    'freespin_end': const StageConfigEntry(
      color: Color(0xFF40C8FF),
      icon: Icons.stop,
      category: StageCategory.feature,
      description: 'Free spins end',
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // CASCADE / TUMBLE
    // ─────────────────────────────────────────────────────────────────────────
    'cascade_start': const StageConfigEntry(
      color: Color(0xFFE040FB),
      icon: Icons.south,
      category: StageCategory.cascade,
      description: 'Cascade starts',
    ),
    'cascade_step': const StageConfigEntry(
      color: Color(0xFFE040FB),
      icon: Icons.arrow_downward,
      category: StageCategory.cascade,
      description: 'Cascade step',
      isPooled: true,
    ),
    'cascade_end': const StageConfigEntry(
      color: Color(0xFFE040FB),
      icon: Icons.done,
      category: StageCategory.cascade,
      description: 'Cascade ends',
    ),
    'symbol_pop': const StageConfigEntry(
      color: Color(0xFFE040FB),
      icon: Icons.burst_mode,
      category: StageCategory.cascade,
      description: 'Symbol pops/explodes',
      isPooled: true,
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // JACKPOT
    // ─────────────────────────────────────────────────────────────────────────
    'jackpot_trigger': const StageConfigEntry(
      color: Color(0xFFFFD700),
      icon: Icons.diamond,
      category: StageCategory.jackpot,
      description: 'Jackpot triggered',
    ),
    'jackpot_present': const StageConfigEntry(
      color: Color(0xFFFFD700),
      icon: Icons.celebration,
      category: StageCategory.jackpot,
      description: 'Jackpot presented',
    ),
    'jackpot_buildup': const StageConfigEntry(
      color: Color(0xFFFFD700),
      icon: Icons.trending_up,
      category: StageCategory.jackpot,
      description: 'Jackpot buildup',
    ),
    'jackpot_reveal': const StageConfigEntry(
      color: Color(0xFFFFD700),
      icon: Icons.visibility,
      category: StageCategory.jackpot,
      description: 'Jackpot tier reveal',
    ),
    'jackpot_celebration': const StageConfigEntry(
      color: Color(0xFFFFD700),
      icon: Icons.party_mode,
      category: StageCategory.jackpot,
      description: 'Jackpot celebration',
    ),
    'jackpot_end': const StageConfigEntry(
      color: Color(0xFFFFD700),
      icon: Icons.check,
      category: StageCategory.jackpot,
      description: 'Jackpot ends',
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // BONUS
    // ─────────────────────────────────────────────────────────────────────────
    'bonus_trigger': const StageConfigEntry(
      color: Color(0xFF9370DB),
      icon: Icons.card_giftcard,
      category: StageCategory.bonus,
      description: 'Bonus triggered',
    ),
    'bonus_enter': const StageConfigEntry(
      color: Color(0xFF9370DB),
      icon: Icons.gamepad,
      category: StageCategory.bonus,
      description: 'Bonus game starts',
    ),
    'bonus_exit': const StageConfigEntry(
      color: Color(0xFF9370DB),
      icon: Icons.exit_to_app,
      category: StageCategory.bonus,
      description: 'Bonus game ends',
    ),
    'pick_bonus_start': const StageConfigEntry(
      color: Color(0xFF9370DB),
      icon: Icons.touch_app,
      category: StageCategory.bonus,
      description: 'Pick bonus starts',
    ),
    'pick_bonus_pick': const StageConfigEntry(
      color: Color(0xFF9370DB),
      icon: Icons.pan_tool,
      category: StageCategory.bonus,
      description: 'Pick made',
    ),
    'pick_bonus_end': const StageConfigEntry(
      color: Color(0xFF9370DB),
      icon: Icons.done_all,
      category: StageCategory.bonus,
      description: 'Pick bonus ends',
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // GAMBLE
    // ─────────────────────────────────────────────────────────────────────────
    'gamble_start': const StageConfigEntry(
      color: Color(0xFFFF6B6B),
      icon: Icons.casino,
      category: StageCategory.gamble,
      description: 'Gamble starts',
    ),
    'gamble_win': const StageConfigEntry(
      color: Color(0xFF40FF90),
      icon: Icons.thumb_up,
      category: StageCategory.gamble,
      description: 'Gamble won',
    ),
    'gamble_lose': const StageConfigEntry(
      color: Color(0xFFFF4040),
      icon: Icons.thumb_down,
      category: StageCategory.gamble,
      description: 'Gamble lost',
    ),
    'gamble_collect': const StageConfigEntry(
      color: Color(0xFFFFD700),
      icon: Icons.savings,
      category: StageCategory.gamble,
      description: 'Gamble collected',
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // MUSIC / AMBIENT
    // ─────────────────────────────────────────────────────────────────────────
    'music_base': const StageConfigEntry(
      color: Color(0xFF40C8FF),
      icon: Icons.music_note,
      category: StageCategory.music,
      description: 'Base game music',
    ),
    'music_feature': const StageConfigEntry(
      color: Color(0xFF40C8FF),
      icon: Icons.queue_music,
      category: StageCategory.music,
      description: 'Feature music',
    ),
    'music_bigwin': const StageConfigEntry(
      color: Color(0xFFFF4080),
      icon: Icons.music_note,
      category: StageCategory.music,
      description: 'Big win music',
    ),
    'ambient_loop': const StageConfigEntry(
      color: Color(0xFF6B7280),
      icon: Icons.surround_sound,
      category: StageCategory.music,
      description: 'Ambient loop',
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // UI
    // ─────────────────────────────────────────────────────────────────────────
    'ui_button_press': const StageConfigEntry(
      color: Color(0xFF808080),
      icon: Icons.touch_app,
      category: StageCategory.ui,
      description: 'UI button pressed',
      isPooled: true,
    ),
    'ui_button_hover': const StageConfigEntry(
      color: Color(0xFF808080),
      icon: Icons.mouse,
      category: StageCategory.ui,
      description: 'UI button hovered',
      isPooled: true,
    ),
    'ui_popup_open': const StageConfigEntry(
      color: Color(0xFF808080),
      icon: Icons.open_in_new,
      category: StageCategory.ui,
      description: 'Popup opened',
    ),
    'ui_popup_close': const StageConfigEntry(
      color: Color(0xFF808080),
      icon: Icons.close,
      category: StageCategory.ui,
      description: 'Popup closed',
    ),

    // ─────────────────────────────────────────────────────────────────────────
    // SYSTEM
    // ─────────────────────────────────────────────────────────────────────────
    'game_load': const StageConfigEntry(
      color: Color(0xFF6B7280),
      icon: Icons.download,
      category: StageCategory.system,
      description: 'Game loading',
    ),
    'game_ready': const StageConfigEntry(
      color: Color(0xFF40FF90),
      icon: Icons.check_circle,
      category: StageCategory.system,
      description: 'Game ready',
    ),
    'error': const StageConfigEntry(
      color: Color(0xFFFF4040),
      icon: Icons.error,
      category: StageCategory.system,
      description: 'Error occurred',
    ),
  };

  /// Custom stages registered at runtime
  final Map<String, StageConfigEntry> _customStages = {};

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// P1.16: Get color for a stage type (case-insensitive)
  /// P2.2: Returns high contrast color when highContrastMode is enabled
  Color getColor(String stageType) {
    final normalized = stageType.toLowerCase();
    final config = _customStages[normalized] ?? _stages[normalized];

    // P2.2: Return high contrast color if mode is enabled
    if (_highContrastMode && config != null) {
      return _getHighContrastColor(config.category);
    }

    return config?.color ?? defaultColor;
  }

  /// P1.17: Get icon for a stage type (case-insensitive)
  IconData getIcon(String stageType) {
    final normalized = stageType.toLowerCase();
    return _customStages[normalized]?.icon ??
        _stages[normalized]?.icon ??
        defaultIcon;
  }

  /// Get full configuration entry for a stage
  StageConfigEntry? getConfig(String stageType) {
    final normalized = stageType.toLowerCase();
    return _customStages[normalized] ?? _stages[normalized];
  }

  /// Get category for a stage type
  StageCategory getCategory(String stageType) {
    final config = getConfig(stageType);
    return config?.category ?? StageCategory.custom;
  }

  /// Check if a stage is pooled (rapid-fire)
  bool isPooled(String stageType) {
    final config = getConfig(stageType);
    return config?.isPooled ?? false;
  }

  /// Get description for a stage type
  String? getDescription(String stageType) {
    final config = getConfig(stageType);
    return config?.description;
  }

  /// Register a custom stage configuration
  void registerStage(
    String stageType, {
    required Color color,
    required IconData icon,
    StageCategory category = StageCategory.custom,
    String? description,
    bool isPooled = false,
  }) {
    final normalized = stageType.toLowerCase();
    _customStages[normalized] = StageConfigEntry(
      color: color,
      icon: icon,
      category: category,
      description: description,
      isPooled: isPooled,
    );
  }

  /// Register multiple custom stages at once
  void registerStages(Map<String, StageConfigEntry> stages) {
    for (final entry in stages.entries) {
      final normalized = entry.key.toLowerCase();
      _customStages[normalized] = entry.value;
    }
  }

  /// Update an existing stage configuration
  void updateStage(
    String stageType, {
    Color? color,
    IconData? icon,
    StageCategory? category,
    String? description,
    bool? isPooled,
  }) {
    final normalized = stageType.toLowerCase();
    final existing = getConfig(normalized);
    if (existing != null) {
      _customStages[normalized] = existing.copyWith(
        color: color,
        icon: icon,
        category: category,
        description: description,
        isPooled: isPooled,
      );
    }
  }

  /// Remove a custom stage configuration
  void removeCustomStage(String stageType) {
    final normalized = stageType.toLowerCase();
    _customStages.remove(normalized);
  }

  /// Clear all custom stage configurations
  void clearCustomStages() {
    _customStages.clear();
  }

  /// Get all registered stage types
  List<String> getAllStageTypes() {
    final types = <String>{};
    types.addAll(_stages.keys);
    types.addAll(_customStages.keys);
    return types.toList()..sort();
  }

  /// Get all stages in a category
  List<String> getStagesInCategory(StageCategory category) {
    final result = <String>[];
    for (final entry in _stages.entries) {
      if (entry.value.category == category) {
        result.add(entry.key);
      }
    }
    for (final entry in _customStages.entries) {
      if (entry.value.category == category) {
        result.add(entry.key);
      }
    }
    return result..sort();
  }

  /// Get all pooled stages (for voice pool optimization)
  List<String> getPooledStages() {
    final result = <String>[];
    for (final entry in _stages.entries) {
      if (entry.value.isPooled) {
        result.add(entry.key);
      }
    }
    for (final entry in _customStages.entries) {
      if (entry.value.isPooled) {
        result.add(entry.key);
      }
    }
    return result;
  }

  /// Export all configurations as JSON-serializable map
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};
    for (final entry in _stages.entries) {
      result[entry.key] = _entryToJson(entry.value);
    }
    for (final entry in _customStages.entries) {
      result[entry.key] = _entryToJson(entry.value);
    }
    return result;
  }

  Map<String, dynamic> _entryToJson(StageConfigEntry entry) {
    return {
      'color': entry.color.value,
      'icon': entry.icon.codePoint,
      'category': entry.category.name,
      'description': entry.description,
      'isPooled': entry.isPooled,
    };
  }

  /// Import configurations from JSON
  void fromJson(Map<String, dynamic> json) {
    for (final entry in json.entries) {
      final data = entry.value as Map<String, dynamic>;
      registerStage(
        entry.key,
        color: Color(data['color'] as int),
        icon: IconData(data['icon'] as int, fontFamily: 'MaterialIcons'),
        category: StageCategory.values.firstWhere(
          (c) => c.name == data['category'],
          orElse: () => StageCategory.custom,
        ),
        description: data['description'] as String?,
        isPooled: data['isPooled'] as bool? ?? false,
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CATEGORY COLOR HELPERS
// ═══════════════════════════════════════════════════════════════════════════

/// Get default color for a category
Color getCategoryColor(StageCategory category) {
  switch (category) {
    case StageCategory.spin:
      return const Color(0xFF4A9EFF);
    case StageCategory.anticipation:
      return const Color(0xFFFF9040);
    case StageCategory.win:
      return const Color(0xFF40FF90);
    case StageCategory.rollup:
      return const Color(0xFFFFD700);
    case StageCategory.bigwin:
      return const Color(0xFFFF4080);
    case StageCategory.feature:
      return const Color(0xFF40C8FF);
    case StageCategory.cascade:
      return const Color(0xFFE040FB);
    case StageCategory.jackpot:
      return const Color(0xFFFFD700);
    case StageCategory.bonus:
      return const Color(0xFF9370DB);
    case StageCategory.gamble:
      return const Color(0xFFFF6B6B);
    case StageCategory.music:
      return const Color(0xFF40C8FF);
    case StageCategory.ui:
      return const Color(0xFF808080);
    case StageCategory.system:
      return const Color(0xFF6B7280);
    case StageCategory.custom:
      return const Color(0xFF6B7280);
  }
}

/// Get default icon for a category
IconData getCategoryIcon(StageCategory category) {
  switch (category) {
    case StageCategory.spin:
      return Icons.play_circle;
    case StageCategory.anticipation:
      return Icons.warning_amber;
    case StageCategory.win:
      return Icons.stars;
    case StageCategory.rollup:
      return Icons.trending_up;
    case StageCategory.bigwin:
      return Icons.emoji_events;
    case StageCategory.feature:
      return Icons.auto_awesome;
    case StageCategory.cascade:
      return Icons.south;
    case StageCategory.jackpot:
      return Icons.diamond;
    case StageCategory.bonus:
      return Icons.card_giftcard;
    case StageCategory.gamble:
      return Icons.casino;
    case StageCategory.music:
      return Icons.music_note;
    case StageCategory.ui:
      return Icons.touch_app;
    case StageCategory.system:
      return Icons.settings;
    case StageCategory.custom:
      return Icons.circle;
  }
}

/// Get display name for a category
String getCategoryName(StageCategory category) {
  switch (category) {
    case StageCategory.spin:
      return 'Spin';
    case StageCategory.anticipation:
      return 'Anticipation';
    case StageCategory.win:
      return 'Win';
    case StageCategory.rollup:
      return 'Rollup';
    case StageCategory.bigwin:
      return 'Big Win';
    case StageCategory.feature:
      return 'Feature';
    case StageCategory.cascade:
      return 'Cascade';
    case StageCategory.jackpot:
      return 'Jackpot';
    case StageCategory.bonus:
      return 'Bonus';
    case StageCategory.gamble:
      return 'Gamble';
    case StageCategory.music:
      return 'Music';
    case StageCategory.ui:
      return 'UI';
    case StageCategory.system:
      return 'System';
    case StageCategory.custom:
      return 'Custom';
  }
}
