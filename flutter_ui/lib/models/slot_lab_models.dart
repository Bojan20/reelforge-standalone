/// SlotLab V6 Data Models
///
/// Models for Symbol Strip, Music Layers, and Context definitions.
/// Used by SlotLabProjectProvider for state management.
///
/// See: .claude/architecture/DYNAMIC_SYMBOL_CONFIGURATION.md

import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/gdd_import_service.dart';

// =============================================================================
// SYMBOL AUDIO CONTEXTS (Typed)
// =============================================================================

/// Typed audio contexts for symbol events
enum SymbolAudioContext {
  land,      // Symbol lands on reel
  win,       // Symbol is part of a win
  expand,    // Symbol expands (expanding wild)
  lock,      // Symbol locks (Hold & Win)
  transform, // Symbol transforms to another
  collect,   // Symbol is collected
  stack,     // Symbol stacks
  trigger,   // Symbol triggers feature
  anticipation, // Symbol creates anticipation
  ;

  /// Convert to stage suffix
  String get stageSuffix => name.toUpperCase();

  /// Parse from string
  static SymbolAudioContext? fromString(String value) {
    try {
      return SymbolAudioContext.values.firstWhere(
        (e) => e.name.toLowerCase() == value.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }
}

// =============================================================================
// SYMBOL DEFINITIONS
// =============================================================================

/// Symbol type categories for slot games
enum SymbolType {
  wild,       // Wild symbols (substitutes)
  scatter,    // Scatter symbols (triggers features)
  bonus,      // Bonus trigger symbols
  highPay,    // High-paying themed symbols
  mediumPay,  // Medium-paying themed symbols
  lowPay,     // Low-paying card symbols (A, K, Q, J, 10)
  multiplier, // Multiplier symbols
  collector,  // Collection symbols (coins, gems)
  mystery,    // Mystery/random symbols
  custom,     // User-defined custom symbols

  // Legacy compatibility
  high,       // Alias for highPay
  low,        // Alias for lowPay
  ;

  /// Get display name for UI
  String get displayName {
    switch (this) {
      case SymbolType.wild: return 'Wild';
      case SymbolType.scatter: return 'Scatter';
      case SymbolType.bonus: return 'Bonus';
      case SymbolType.highPay:
      case SymbolType.high: return 'High Pay';
      case SymbolType.mediumPay: return 'Medium Pay';
      case SymbolType.lowPay:
      case SymbolType.low: return 'Low Pay';
      case SymbolType.multiplier: return 'Multiplier';
      case SymbolType.collector: return 'Collector';
      case SymbolType.mystery: return 'Mystery';
      case SymbolType.custom: return 'Custom';
    }
  }

  /// Get default color for this symbol type
  Color get defaultColor {
    switch (this) {
      case SymbolType.wild: return const Color(0xFF9C27B0); // Purple
      case SymbolType.scatter: return const Color(0xFFFFD700); // Gold
      case SymbolType.bonus: return const Color(0xFFFF5722); // Deep Orange
      case SymbolType.highPay:
      case SymbolType.high: return const Color(0xFF2196F3); // Blue
      case SymbolType.mediumPay: return const Color(0xFF4CAF50); // Green
      case SymbolType.lowPay:
      case SymbolType.low: return const Color(0xFF607D8B); // Blue Grey
      case SymbolType.multiplier: return const Color(0xFFE91E63); // Pink
      case SymbolType.collector: return const Color(0xFFFFC107); // Amber
      case SymbolType.mystery: return const Color(0xFF795548); // Brown
      case SymbolType.custom: return const Color(0xFF9E9E9E); // Grey
    }
  }

  /// Get default emoji for this symbol type
  String get defaultEmoji {
    switch (this) {
      case SymbolType.wild: return '🃏';
      case SymbolType.scatter: return '⭐';
      case SymbolType.bonus: return '🎁';
      case SymbolType.highPay:
      case SymbolType.high: return '💎';
      case SymbolType.mediumPay: return '🔔';
      case SymbolType.lowPay:
      case SymbolType.low: return 'A';
      case SymbolType.multiplier: return '✖️';
      case SymbolType.collector: return '💰';
      case SymbolType.mystery: return '❓';
      case SymbolType.custom: return '🔷';
    }
  }
}

/// Definition of a slot symbol with audio contexts
class SymbolDefinition {
  final String id;
  final String name;
  final String emoji;
  final SymbolType type;
  final List<String> contexts; // Audio contexts: ['land', 'win', 'expand', 'stack']
  final int? payMultiplier; // Base pay multiplier (for sorting)
  final Color? customColor; // Optional custom color override
  final int sortOrder; // Display order in UI
  final Map<String, dynamic>? metadata; // Additional custom data

  const SymbolDefinition({
    required this.id,
    required this.name,
    required this.emoji,
    required this.type,
    this.contexts = const ['land', 'win'],
    this.payMultiplier,
    this.customColor,
    this.sortOrder = 0,
    this.metadata,
  });

  /// Get the effective display color
  Color get displayColor => customColor ?? type.defaultColor;

  /// Audio stage name for this symbol + context
  /// FIX 2026-01-25: Use correct stage ID getters for each context
  /// - land → SYMBOL_LAND_HP1
  /// - win → WIN_SYMBOL_HIGHLIGHT_HP1 (matches slot_preview_widget.dart triggers)
  /// - expand → SYMBOL_EXPAND_HP1
  /// - lock → SYMBOL_LOCK_HP1
  /// - transform → SYMBOL_TRANSFORM_HP1
  String stageName(String context) {
    switch (context.toLowerCase()) {
      case 'land':
        return stageIdLand;  // SYMBOL_LAND_HP1
      case 'win':
        return stageIdWin;   // WIN_SYMBOL_HIGHLIGHT_HP1 (CRITICAL: matches trigger)
      case 'expand':
        return stageIdExpand;  // SYMBOL_EXPAND_HP1
      case 'lock':
        return stageIdLock;    // SYMBOL_LOCK_HP1
      case 'transform':
        return stageIdTransform;  // SYMBOL_TRANSFORM_HP1
      default:
        return 'SYMBOL_${context.toUpperCase()}_${id.toUpperCase()}';  // Fallback
    }
  }

  /// Stage ID for symbol landing
  String get stageIdLand => 'SYMBOL_LAND_${id.toUpperCase()}';

  /// Stage ID for symbol win highlight
  String get stageIdWin => 'WIN_SYMBOL_HIGHLIGHT_${id.toUpperCase()}';

  /// Stage ID for symbol expansion
  String get stageIdExpand => 'SYMBOL_EXPAND_${id.toUpperCase()}';

  /// Stage ID for symbol locking (Hold & Win)
  String get stageIdLock => 'SYMBOL_LOCK_${id.toUpperCase()}';

  /// Stage ID for symbol transformation
  String get stageIdTransform => 'SYMBOL_TRANSFORM_${id.toUpperCase()}';

  /// Get all stage IDs this symbol can generate
  List<String> get allStageIds {
    final stages = <String>[];
    for (final ctx in contexts) {
      stages.add(stageName(ctx));
    }
    // Always include WIN_SYMBOL_HIGHLIGHT variant
    if (!stages.contains(stageIdWin)) {
      stages.add(stageIdWin);
    }
    return stages;
  }

  /// Get typed audio contexts
  Set<SymbolAudioContext> get typedContexts {
    return contexts
        .map((c) => SymbolAudioContext.fromString(c))
        .whereType<SymbolAudioContext>()
        .toSet();
  }

  /// Check if symbol has a specific audio context
  bool hasContext(SymbolAudioContext context) {
    return contexts.contains(context.name);
  }

  /// Create a copy with updated fields
  SymbolDefinition copyWith({
    String? id,
    String? name,
    String? emoji,
    SymbolType? type,
    List<String>? contexts,
    int? payMultiplier,
    Color? customColor,
    int? sortOrder,
    Map<String, dynamic>? metadata,
  }) {
    return SymbolDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      type: type ?? this.type,
      contexts: contexts ?? this.contexts,
      payMultiplier: payMultiplier ?? this.payMultiplier,
      customColor: customColor ?? this.customColor,
      sortOrder: sortOrder ?? this.sortOrder,
      metadata: metadata ?? this.metadata,
    );
  }

  factory SymbolDefinition.fromJson(Map<String, dynamic> json) {
    return SymbolDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      emoji: json['emoji'] as String,
      type: SymbolType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SymbolType.lowPay,
      ),
      contexts: (json['contexts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const ['land', 'win'],
      payMultiplier: json['payMultiplier'] as int?,
      customColor: json['customColor'] != null
          ? Color(json['customColor'] as int)
          : null,
      sortOrder: json['sortOrder'] as int? ?? 0,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'emoji': emoji,
      'type': type.name,
      'contexts': contexts,
      if (payMultiplier != null) 'payMultiplier': payMultiplier,
      if (customColor != null) 'customColor': customColor!.value,
      if (sortOrder != 0) 'sortOrder': sortOrder,
      if (metadata != null) 'metadata': metadata,
    };
  }

  @override
  String toString() => 'SymbolDefinition($name, $emoji, $type)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SymbolDefinition && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

// =============================================================================
// SYMBOL PRESETS
// =============================================================================

/// Preset type for common slot configurations
enum SymbolPresetType {
  standard5x3,    // Standard 5-reel, 3-row slot
  megaways,       // Megaways-style (6 reels, variable rows)
  holdAndWin,     // Hold & Win with collector symbols
  cascading,      // Cascading/Avalanche with multipliers
  custom,         // User-defined preset
}

/// Preset template for quick symbol configuration
class SymbolPreset {
  final String id;
  final String name;
  final String description;
  final SymbolPresetType type;
  final List<SymbolDefinition> symbols;
  final String? iconPath;

  const SymbolPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.symbols,
    this.iconPath,
  });

  /// Standard 5x3 slot with Wild, Scatter, Bonus, 4 HP, 6 LP
  /// Matches Rust StandardSymbolSet (crates/rf-slot-lab/src/symbols.rs)
  static SymbolPreset get standard5x3 => SymbolPreset(
    id: 'standard_5x3',
    name: 'Standard 5x3',
    description: '5-reel, 3-row classic layout: Wild, Scatter, Bonus, 4 High Pay, 6 Low Pay',
    type: SymbolPresetType.standard5x3,
    symbols: const [
      SymbolDefinition(id: 'wild', name: 'Wild', emoji: '🃏', type: SymbolType.wild,
        contexts: ['land', 'win', 'expand'], payMultiplier: 100, sortOrder: 0),
      SymbolDefinition(id: 'scatter', name: 'Scatter', emoji: '⭐', type: SymbolType.scatter,
        contexts: ['land', 'win', 'trigger'], payMultiplier: 50, sortOrder: 1),
      SymbolDefinition(id: 'bonus', name: 'Bonus', emoji: '🎁', type: SymbolType.bonus,
        contexts: ['land', 'trigger'], payMultiplier: 0, sortOrder: 2),
      SymbolDefinition(id: 'hp1', name: 'High Pay 1', emoji: '💎', type: SymbolType.highPay,
        contexts: ['land', 'win'], payMultiplier: 30, sortOrder: 3),
      SymbolDefinition(id: 'hp2', name: 'High Pay 2', emoji: '👑', type: SymbolType.highPay,
        contexts: ['land', 'win'], payMultiplier: 25, sortOrder: 4),
      SymbolDefinition(id: 'hp3', name: 'High Pay 3', emoji: '🔔', type: SymbolType.highPay,
        contexts: ['land', 'win'], payMultiplier: 20, sortOrder: 5),
      SymbolDefinition(id: 'hp4', name: 'High Pay 4', emoji: '🍀', type: SymbolType.highPay,
        contexts: ['land', 'win'], payMultiplier: 15, sortOrder: 6),
      SymbolDefinition(id: 'lp1', name: 'Ace', emoji: 'A', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 5, sortOrder: 7),
      SymbolDefinition(id: 'lp2', name: 'King', emoji: 'K', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 4, sortOrder: 8),
      SymbolDefinition(id: 'lp3', name: 'Queen', emoji: 'Q', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 3, sortOrder: 9),
      SymbolDefinition(id: 'lp4', name: 'Jack', emoji: 'J', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 2, sortOrder: 10),
      SymbolDefinition(id: 'lp5', name: 'Ten', emoji: '10', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 1, sortOrder: 11),
      SymbolDefinition(id: 'lp6', name: 'Nine', emoji: '9', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 1, sortOrder: 12),
    ],
  );

  /// Megaways-style with mystery symbols
  static SymbolPreset get megaways => SymbolPreset(
    id: 'megaways',
    name: 'Megaways',
    description: '6-reel Megaways: Wild, Scatter, Mystery, 4 High Pay, 4 Low Pay',
    type: SymbolPresetType.megaways,
    symbols: const [
      SymbolDefinition(id: 'wild', name: 'Wild', emoji: '🃏', type: SymbolType.wild,
        contexts: ['land', 'win'], payMultiplier: 100, sortOrder: 0),
      SymbolDefinition(id: 'scatter', name: 'Scatter', emoji: '⭐', type: SymbolType.scatter,
        contexts: ['land', 'win', 'trigger'], payMultiplier: 50, sortOrder: 1),
      SymbolDefinition(id: 'mystery', name: 'Mystery', emoji: '❓', type: SymbolType.mystery,
        contexts: ['land', 'transform'], payMultiplier: 0, sortOrder: 2),
      SymbolDefinition(id: 'hp1', name: 'Red Gem', emoji: '🔴', type: SymbolType.highPay,
        contexts: ['land', 'win'], payMultiplier: 30, sortOrder: 3),
      SymbolDefinition(id: 'hp2', name: 'Blue Gem', emoji: '🔵', type: SymbolType.highPay,
        contexts: ['land', 'win'], payMultiplier: 25, sortOrder: 4),
      SymbolDefinition(id: 'hp3', name: 'Green Gem', emoji: '🟢', type: SymbolType.highPay,
        contexts: ['land', 'win'], payMultiplier: 20, sortOrder: 5),
      SymbolDefinition(id: 'hp4', name: 'Purple Gem', emoji: '🟣', type: SymbolType.highPay,
        contexts: ['land', 'win'], payMultiplier: 15, sortOrder: 6),
      SymbolDefinition(id: 'lp1', name: 'Ace', emoji: 'A', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 5, sortOrder: 7),
      SymbolDefinition(id: 'lp2', name: 'King', emoji: 'K', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 4, sortOrder: 8),
      SymbolDefinition(id: 'lp3', name: 'Queen', emoji: 'Q', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 3, sortOrder: 9),
      SymbolDefinition(id: 'lp4', name: 'Jack', emoji: 'J', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 2, sortOrder: 10),
    ],
  );

  /// Hold & Win with collector symbols
  static SymbolPreset get holdAndWin => SymbolPreset(
    id: 'hold_and_win',
    name: 'Hold & Win',
    description: 'Hold & Win: Wild, Scatter, Coins (Mini/Minor/Major/Grand), 3 HP, 4 LP',
    type: SymbolPresetType.holdAndWin,
    symbols: const [
      SymbolDefinition(id: 'wild', name: 'Wild', emoji: '🃏', type: SymbolType.wild,
        contexts: ['land', 'win'], payMultiplier: 100, sortOrder: 0),
      SymbolDefinition(id: 'scatter', name: 'Scatter', emoji: '⭐', type: SymbolType.scatter,
        contexts: ['land', 'win', 'trigger'], payMultiplier: 50, sortOrder: 1),
      SymbolDefinition(id: 'coin_mini', name: 'Mini Coin', emoji: '🪙', type: SymbolType.collector,
        contexts: ['land', 'lock', 'collect'], payMultiplier: 1, sortOrder: 2),
      SymbolDefinition(id: 'coin_minor', name: 'Minor Coin', emoji: '💰', type: SymbolType.collector,
        contexts: ['land', 'lock', 'collect'], payMultiplier: 5, sortOrder: 3),
      SymbolDefinition(id: 'coin_major', name: 'Major Coin', emoji: '💎', type: SymbolType.collector,
        contexts: ['land', 'lock', 'collect'], payMultiplier: 25, sortOrder: 4),
      SymbolDefinition(id: 'coin_grand', name: 'Grand Coin', emoji: '👑', type: SymbolType.collector,
        contexts: ['land', 'lock', 'collect'], payMultiplier: 100, sortOrder: 5),
      SymbolDefinition(id: 'hp1', name: 'High Pay 1', emoji: '🔔', type: SymbolType.highPay,
        contexts: ['land', 'win'], payMultiplier: 20, sortOrder: 6),
      SymbolDefinition(id: 'hp2', name: 'High Pay 2', emoji: '🍇', type: SymbolType.highPay,
        contexts: ['land', 'win'], payMultiplier: 15, sortOrder: 7),
      SymbolDefinition(id: 'hp3', name: 'High Pay 3', emoji: '🍒', type: SymbolType.highPay,
        contexts: ['land', 'win'], payMultiplier: 10, sortOrder: 8),
      SymbolDefinition(id: 'lp1', name: 'Ace', emoji: 'A', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 5, sortOrder: 9),
      SymbolDefinition(id: 'lp2', name: 'King', emoji: 'K', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 4, sortOrder: 10),
      SymbolDefinition(id: 'lp3', name: 'Queen', emoji: 'Q', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 3, sortOrder: 11),
      SymbolDefinition(id: 'lp4', name: 'Jack', emoji: 'J', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 2, sortOrder: 12),
    ],
  );

  /// Cascading/Avalanche with multipliers
  static SymbolPreset get cascading => SymbolPreset(
    id: 'cascading',
    name: 'Cascading/Avalanche',
    description: 'Cascade mechanics: Wild, Scatter, Multiplier, 4 HP, 4 LP',
    type: SymbolPresetType.cascading,
    symbols: const [
      SymbolDefinition(id: 'wild', name: 'Wild', emoji: '🃏', type: SymbolType.wild,
        contexts: ['land', 'win'], payMultiplier: 100, sortOrder: 0),
      SymbolDefinition(id: 'scatter', name: 'Scatter', emoji: '⭐', type: SymbolType.scatter,
        contexts: ['land', 'win', 'trigger'], payMultiplier: 50, sortOrder: 1),
      SymbolDefinition(id: 'multiplier', name: 'Multiplier', emoji: '✖️', type: SymbolType.multiplier,
        contexts: ['land', 'win'], payMultiplier: 0, sortOrder: 2),
      SymbolDefinition(id: 'hp1', name: 'Red', emoji: '🔴', type: SymbolType.highPay,
        contexts: ['land', 'win'], payMultiplier: 30, sortOrder: 3),
      SymbolDefinition(id: 'hp2', name: 'Blue', emoji: '🔵', type: SymbolType.highPay,
        contexts: ['land', 'win'], payMultiplier: 25, sortOrder: 4),
      SymbolDefinition(id: 'hp3', name: 'Green', emoji: '🟢', type: SymbolType.highPay,
        contexts: ['land', 'win'], payMultiplier: 20, sortOrder: 5),
      SymbolDefinition(id: 'hp4', name: 'Yellow', emoji: '🟡', type: SymbolType.highPay,
        contexts: ['land', 'win'], payMultiplier: 15, sortOrder: 6),
      SymbolDefinition(id: 'lp1', name: 'Purple', emoji: '🟣', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 5, sortOrder: 7),
      SymbolDefinition(id: 'lp2', name: 'Orange', emoji: '🟠', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 4, sortOrder: 8),
      SymbolDefinition(id: 'lp3', name: 'White', emoji: '⚪', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 3, sortOrder: 9),
      SymbolDefinition(id: 'lp4', name: 'Black', emoji: '⚫', type: SymbolType.lowPay,
        contexts: ['land', 'win'], payMultiplier: 2, sortOrder: 10),
    ],
  );

  /// Get all built-in presets
  static List<SymbolPreset> get builtInPresets => [
    standard5x3,
    megaways,
    holdAndWin,
    cascading,
  ];

  /// Get preset by ID
  static SymbolPreset? getById(String id) {
    try {
      return builtInPresets.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  SymbolPreset copyWith({
    String? id,
    String? name,
    String? description,
    SymbolPresetType? type,
    List<SymbolDefinition>? symbols,
    String? iconPath,
  }) {
    return SymbolPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      symbols: symbols ?? this.symbols,
      iconPath: iconPath ?? this.iconPath,
    );
  }

  factory SymbolPreset.fromJson(Map<String, dynamic> json) {
    return SymbolPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      type: SymbolPresetType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SymbolPresetType.custom,
      ),
      symbols: (json['symbols'] as List<dynamic>?)
              ?.map((e) => SymbolDefinition.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      iconPath: json['iconPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.name,
      'symbols': symbols.map((e) => e.toJson()).toList(),
      if (iconPath != null) 'iconPath': iconPath,
    };
  }

  @override
  String toString() => 'SymbolPreset($name, ${symbols.length} symbols)';
}

// =============================================================================
// CONTEXT DEFINITIONS (Game Chapters)
// =============================================================================

/// Context type for game chapters/modes
enum ContextType {
  base,       // Base game
  freeSpins,  // Free spins feature
  holdWin,    // Hold & Win / Respins
  bonus,      // Bonus game
  bigWin,     // Big Win celebration
  cascade,    // Cascade/Avalanche mode
  jackpot,    // Jackpot mode
  gamble,     // Gamble feature
}

/// Definition of a game context (chapter) with music layers
class ContextDefinition {
  final String id;
  final String displayName;
  final String icon; // Icon name or emoji
  final ContextType type;
  final int layerCount; // Number of intensity layers (usually 5)
  final String? description;

  const ContextDefinition({
    required this.id,
    required this.displayName,
    required this.icon,
    required this.type,
    this.layerCount = 5,
    this.description,
  });

  /// Factory for base game context
  factory ContextDefinition.base() {
    return const ContextDefinition(
      id: 'base',
      displayName: 'Base Game',
      icon: '🎰',
      type: ContextType.base,
      layerCount: 5,
      description: 'Main game context with standard layers',
    );
  }

  /// Factory for free spins context
  factory ContextDefinition.freeSpins() {
    return const ContextDefinition(
      id: 'freespins',
      displayName: 'Free Spins',
      icon: '🎁',
      type: ContextType.freeSpins,
      layerCount: 5,
      description: 'Free spins feature with enhanced audio',
    );
  }

  /// Factory for hold & win context
  factory ContextDefinition.holdWin() {
    return const ContextDefinition(
      id: 'holdwin',
      displayName: 'Hold & Win',
      icon: '🔒',
      type: ContextType.holdWin,
      layerCount: 5,
      description: 'Hold & Win respins feature',
    );
  }

  ContextDefinition copyWith({
    String? id,
    String? displayName,
    String? icon,
    ContextType? type,
    int? layerCount,
    String? description,
  }) {
    return ContextDefinition(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      icon: icon ?? this.icon,
      type: type ?? this.type,
      layerCount: layerCount ?? this.layerCount,
      description: description ?? this.description,
    );
  }

  factory ContextDefinition.fromJson(Map<String, dynamic> json) {
    return ContextDefinition(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      icon: json['icon'] as String,
      type: ContextType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ContextType.base,
      ),
      layerCount: json['layerCount'] as int? ?? 5,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'icon': icon,
      'type': type.name,
      'layerCount': layerCount,
      if (description != null) 'description': description,
    };
  }

  @override
  String toString() => 'ContextDefinition($displayName, $type)';
}

// =============================================================================
// AUDIO ASSIGNMENTS
// =============================================================================

/// Audio assignment for a symbol context slot
class SymbolAudioAssignment {
  final String symbolId;
  final String context; // 'land', 'win', 'expand', etc.
  final String audioPath;
  final double volume;
  final double pan;

  const SymbolAudioAssignment({
    required this.symbolId,
    required this.context,
    required this.audioPath,
    this.volume = 1.0,
    this.pan = 0.0,
  });

  /// FIX 2026-01-25: Use correct stage format per context type
  /// - win → WIN_SYMBOL_HIGHLIGHT_HP1 (matches slot_preview_widget.dart triggers)
  /// - others → SYMBOL_{CONTEXT}_{SYMBOL}
  String get stageName {
    switch (context.toLowerCase()) {
      case 'win':
        return 'WIN_SYMBOL_HIGHLIGHT_${symbolId.toUpperCase()}';
      case 'land':
        return 'SYMBOL_LAND_${symbolId.toUpperCase()}';
      case 'expand':
        return 'SYMBOL_EXPAND_${symbolId.toUpperCase()}';
      case 'lock':
        return 'SYMBOL_LOCK_${symbolId.toUpperCase()}';
      case 'transform':
        return 'SYMBOL_TRANSFORM_${symbolId.toUpperCase()}';
      default:
        return 'SYMBOL_${context.toUpperCase()}_${symbolId.toUpperCase()}';
    }
  }

  SymbolAudioAssignment copyWith({
    String? symbolId,
    String? context,
    String? audioPath,
    double? volume,
    double? pan,
  }) {
    return SymbolAudioAssignment(
      symbolId: symbolId ?? this.symbolId,
      context: context ?? this.context,
      audioPath: audioPath ?? this.audioPath,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
    );
  }

  factory SymbolAudioAssignment.fromJson(Map<String, dynamic> json) {
    return SymbolAudioAssignment(
      symbolId: json['symbolId'] as String,
      context: json['context'] as String,
      audioPath: json['audioPath'] as String,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'symbolId': symbolId,
      'context': context,
      'audioPath': audioPath,
      'volume': volume,
      'pan': pan,
    };
  }
}

/// Audio assignment for a music layer slot
class MusicLayerAssignment {
  final String contextId;
  final int layer; // 1-5 typically
  final String audioPath;
  final double volume;
  final bool loop;

  const MusicLayerAssignment({
    required this.contextId,
    required this.layer,
    required this.audioPath,
    this.volume = 1.0,
    this.loop = true,
  });

  MusicLayerAssignment copyWith({
    String? contextId,
    int? layer,
    String? audioPath,
    double? volume,
    bool? loop,
  }) {
    return MusicLayerAssignment(
      contextId: contextId ?? this.contextId,
      layer: layer ?? this.layer,
      audioPath: audioPath ?? this.audioPath,
      volume: volume ?? this.volume,
      loop: loop ?? this.loop,
    );
  }

  factory MusicLayerAssignment.fromJson(Map<String, dynamic> json) {
    return MusicLayerAssignment(
      contextId: json['contextId'] as String,
      layer: json['layer'] as int,
      audioPath: json['audioPath'] as String,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      loop: json['loop'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'contextId': contextId,
      'layer': layer,
      'audioPath': audioPath,
      'volume': volume,
      'loop': loop,
    };
  }
}

// =============================================================================
// SLOTLAB PROJECT (Complete state)
// =============================================================================

/// Complete SlotLab project state for serialization
class SlotLabProject {
  final String name;
  final String version;
  final List<SymbolDefinition> symbols;
  final List<ContextDefinition> contexts;
  final List<SymbolAudioAssignment> symbolAudio;
  final List<MusicLayerAssignment> musicLayers;
  final Map<String, dynamic>? metadata;

  // V7: UltimateAudioPanel state
  final Map<String, String> audioAssignments;
  final Set<String> expandedSections;
  final Set<String> expandedGroups;
  final String? lastActiveTab;

  // V8: GDD Import data
  final GddGridConfig? gridConfig;
  final GameDesignDocument? importedGdd;

  // V9: UI State Persistence (SL-INT-P1.2, SL-INT-P1.4)
  final String? selectedEventId;
  final double? lowerZoneHeight;
  final String? audioBrowserDirectory;

  const SlotLabProject({
    required this.name,
    this.version = '1.0',
    this.symbols = const [],
    this.contexts = const [],
    this.symbolAudio = const [],
    this.musicLayers = const [],
    this.metadata,
    this.audioAssignments = const {},
    this.expandedSections = const {'spins_reels', 'symbols', 'wins'},
    this.expandedGroups = const {
      'spins_reels_spin_controls',
      'spins_reels_reel_stops',
      'symbols_land',
      'symbols_win',
      'wins_tiers',
      'wins_lines',
    },
    this.lastActiveTab,
    // V8: GDD data
    this.gridConfig,
    this.importedGdd,
    // V9: UI state
    this.selectedEventId,
    this.lowerZoneHeight,
    this.audioBrowserDirectory,
  });

  /// Create default project with standard symbols and contexts
  factory SlotLabProject.defaultProject(String name) {
    return SlotLabProject(
      name: name,
      symbols: defaultSymbols,
      contexts: [
        ContextDefinition.base(),
        ContextDefinition.freeSpins(),
        ContextDefinition.holdWin(),
      ],
    );
  }

  SlotLabProject copyWith({
    String? name,
    String? version,
    List<SymbolDefinition>? symbols,
    List<ContextDefinition>? contexts,
    List<SymbolAudioAssignment>? symbolAudio,
    List<MusicLayerAssignment>? musicLayers,
    Map<String, dynamic>? metadata,
    Map<String, String>? audioAssignments,
    Set<String>? expandedSections,
    Set<String>? expandedGroups,
    String? lastActiveTab,
    GddGridConfig? gridConfig,
    GameDesignDocument? importedGdd,
    String? selectedEventId,
    double? lowerZoneHeight,
    String? audioBrowserDirectory,
  }) {
    return SlotLabProject(
      name: name ?? this.name,
      version: version ?? this.version,
      symbols: symbols ?? this.symbols,
      contexts: contexts ?? this.contexts,
      symbolAudio: symbolAudio ?? this.symbolAudio,
      musicLayers: musicLayers ?? this.musicLayers,
      metadata: metadata ?? this.metadata,
      audioAssignments: audioAssignments ?? this.audioAssignments,
      expandedSections: expandedSections ?? this.expandedSections,
      expandedGroups: expandedGroups ?? this.expandedGroups,
      lastActiveTab: lastActiveTab ?? this.lastActiveTab,
      gridConfig: gridConfig ?? this.gridConfig,
      importedGdd: importedGdd ?? this.importedGdd,
      selectedEventId: selectedEventId ?? this.selectedEventId,
      lowerZoneHeight: lowerZoneHeight ?? this.lowerZoneHeight,
      audioBrowserDirectory: audioBrowserDirectory ?? this.audioBrowserDirectory,
    );
  }

  factory SlotLabProject.fromJson(Map<String, dynamic> json) {
    return SlotLabProject(
      name: json['name'] as String,
      version: json['version'] as String? ?? '1.0',
      symbols: (json['symbols'] as List<dynamic>?)
              ?.map((e) => SymbolDefinition.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      contexts: (json['contexts'] as List<dynamic>?)
              ?.map((e) => ContextDefinition.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      symbolAudio: (json['symbolAudio'] as List<dynamic>?)
              ?.map((e) => SymbolAudioAssignment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      musicLayers: (json['musicLayers'] as List<dynamic>?)
              ?.map((e) => MusicLayerAssignment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      metadata: json['metadata'] as Map<String, dynamic>?,
      // V7: UltimateAudioPanel state
      audioAssignments: (json['audioAssignments'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          const {},
      expandedSections: (json['expandedSections'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toSet() ??
          const {'spins_reels', 'symbols', 'wins'},
      expandedGroups: (json['expandedGroups'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toSet() ??
          const {
            'spins_reels_spin_controls',
            'spins_reels_reel_stops',
            'symbols_land',
            'symbols_win',
            'wins_tiers',
            'wins_lines',
          },
      lastActiveTab: json['lastActiveTab'] as String?,
      // V8: GDD data
      gridConfig: json['gridConfig'] != null
          ? GddGridConfig.fromJson(json['gridConfig'] as Map<String, dynamic>)
          : null,
      importedGdd: json['importedGdd'] != null
          ? GameDesignDocument.fromJson(json['importedGdd'] as Map<String, dynamic>)
          : null,
      // V9: UI state
      selectedEventId: json['selectedEventId'] as String?,
      lowerZoneHeight: (json['lowerZoneHeight'] as num?)?.toDouble(),
      audioBrowserDirectory: json['audioBrowserDirectory'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'version': version,
      'symbols': symbols.map((e) => e.toJson()).toList(),
      'contexts': contexts.map((e) => e.toJson()).toList(),
      'symbolAudio': symbolAudio.map((e) => e.toJson()).toList(),
      'musicLayers': musicLayers.map((e) => e.toJson()).toList(),
      if (metadata != null) 'metadata': metadata,
      // V7: UltimateAudioPanel state
      if (audioAssignments.isNotEmpty) 'audioAssignments': audioAssignments,
      'expandedSections': expandedSections.toList(),
      'expandedGroups': expandedGroups.toList(),
      if (lastActiveTab != null) 'lastActiveTab': lastActiveTab,
      // V8: GDD data
      if (gridConfig != null) 'gridConfig': gridConfig!.toJson(),
      if (importedGdd != null) 'importedGdd': importedGdd!.toJson(),
      // V9: UI state
      if (selectedEventId != null) 'selectedEventId': selectedEventId,
      if (lowerZoneHeight != null) 'lowerZoneHeight': lowerZoneHeight,
      if (audioBrowserDirectory != null) 'audioBrowserDirectory': audioBrowserDirectory,
    };
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory SlotLabProject.fromJsonString(String jsonString) {
    return SlotLabProject.fromJson(json.decode(jsonString) as Map<String, dynamic>);
  }
}

// =============================================================================
// DEFAULT SYMBOLS
// =============================================================================

/// Standard slot symbols for new projects (uses Standard 5x3 preset)
List<SymbolDefinition> get defaultSymbols => SymbolPreset.standard5x3.symbols;

/// Standard symbol contexts for audio assignment
const List<String> standardSymbolContexts = [
  'land',      // Symbol lands on reel
  'win',       // Symbol is part of a win
  'expand',    // Symbol expands (expanding wild)
  'stack',     // Symbol stacks
  'trigger',   // Symbol triggers feature
  'lock',      // Symbol locks in place (Hold & Win)
  'transform', // Symbol transforms to another
  'collect',   // Symbol is collected
  'anticipation', // Symbol creates anticipation
];

/// Get all unique stage IDs from a list of symbols
List<String> getAllSymbolStageIds(List<SymbolDefinition> symbols) {
  final stages = <String>{};
  for (final symbol in symbols) {
    stages.addAll(symbol.allStageIds);
  }
  return stages.toList()..sort();
}

/// Find symbol by ID
SymbolDefinition? findSymbolById(List<SymbolDefinition> symbols, String id) {
  try {
    return symbols.firstWhere((s) => s.id == id);
  } catch (_) {
    return null;
  }
}

/// Get symbols by type
List<SymbolDefinition> getSymbolsByType(List<SymbolDefinition> symbols, SymbolType type) {
  return symbols.where((s) => s.type == type).toList();
}

/// Sort symbols by pay multiplier (highest first), then by sort order
List<SymbolDefinition> sortSymbolsByValue(List<SymbolDefinition> symbols) {
  final sorted = List<SymbolDefinition>.from(symbols);
  sorted.sort((a, b) {
    // First compare by pay multiplier (descending)
    final payCompare = (b.payMultiplier ?? 0).compareTo(a.payMultiplier ?? 0);
    if (payCompare != 0) return payCompare;
    // Then by sort order (ascending)
    return a.sortOrder.compareTo(b.sortOrder);
  });
  return sorted;
}
