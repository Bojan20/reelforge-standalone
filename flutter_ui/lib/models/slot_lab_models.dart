/// SlotLab V6 Data Models
///
/// Models for Symbol Strip, Music Layers, and Context definitions.
/// Used by SlotLabProjectProvider for state management.
///
/// See: .claude/architecture/DYNAMIC_SYMBOL_CONFIGURATION.md

import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../services/gdd_import_service.dart';
import '../providers/slot_lab/feature_composer_provider.dart';

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
  static SymbolAudioContext? fromString(String value) =>
      SymbolAudioContext.values.firstWhereOrNull(
        (e) => e.name.toLowerCase() == value.toLowerCase(),
      );
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
  final String? artworkPath; // Optional path to symbol artwork image (PNG/JPG)

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
    this.artworkPath,
  });

  /// Get the effective display color
  Color get displayColor => customColor ?? type.defaultColor;

  /// Audio stage name for this symbol + context
  /// Naming convention: {SYMBOL}_{ACTION}
  /// - land → HP1_LAND
  /// - win → HP1_WIN
  /// - expand → HP1_EXPAND
  /// - lock → HP1_LOCK
  /// - transform → HP1_TRANSFORM
  String stageName(String context) {
    switch (context.toLowerCase()) {
      case 'land':
        return stageIdLand;  // HP1_LAND
      case 'win':
        return stageIdWin;   // HP1_WIN
      case 'expand':
        return stageIdExpand;  // HP1_EXPAND
      case 'lock':
        return stageIdLock;    // HP1_LOCK
      case 'transform':
        return stageIdTransform;  // HP1_TRANSFORM
      default:
        return '${id.toUpperCase()}_${context.toUpperCase()}';  // Fallback
    }
  }

  /// Stage ID for symbol landing
  String get stageIdLand => '${id.toUpperCase()}_LAND';

  /// Stage ID for symbol win highlight
  String get stageIdWin => '${id.toUpperCase()}_WIN';

  /// Stage ID for symbol expansion
  String get stageIdExpand => '${id.toUpperCase()}_EXPAND';

  /// Stage ID for symbol locking (Hold & Win)
  String get stageIdLock => '${id.toUpperCase()}_LOCK';

  /// Stage ID for symbol transformation
  String get stageIdTransform => '${id.toUpperCase()}_TRANSFORM';

  /// Get all stage IDs this symbol can generate
  List<String> get allStageIds {
    final stages = <String>[];
    for (final ctx in contexts) {
      stages.add(stageName(ctx));
    }
    // Always include WIN variant
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
    String? artworkPath,
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
      artworkPath: artworkPath ?? this.artworkPath,
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
      artworkPath: json['artworkPath'] as String?,
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
      if (artworkPath != null) 'artworkPath': artworkPath,
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
  static SymbolPreset? getById(String id) =>
      builtInPresets.firstWhereOrNull((p) => p.id == id);

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

  /// Engine-compatible stage prefix (e.g., 'FS' for freespins, 'HOLD' for holdwin)
  /// Maps context id to the canonical stage naming used across all services.
  String get stagePrefix => switch (id) {
    'base' => 'BASE',
    'freespins' => 'FS',
    'holdwin' => 'HOLD',
    'bonus' => 'BONUS',
    'cascade' => 'CASCADE',
    'jackpot' => 'JACKPOT',
    'gamble' => 'GAMBLE',
    _ => id.toUpperCase(),
  };

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

  /// Stage name: {SYMBOL}_{ACTION} format
  String get stageName {
    switch (context.toLowerCase()) {
      case 'win':
        return '${symbolId.toUpperCase()}_WIN';
      case 'land':
        return '${symbolId.toUpperCase()}_LAND';
      case 'expand':
        return '${symbolId.toUpperCase()}_EXPAND';
      case 'lock':
        return '${symbolId.toUpperCase()}_LOCK';
      case 'transform':
        return '${symbolId.toUpperCase()}_TRANSFORM';
      default:
        return '${symbolId.toUpperCase()}_${context.toUpperCase()}';
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

/// Dynamic music layer escalation/de-escalation configuration.
/// Data-driven: thresholds, crossfade durations, revert spin count — all configurable.
class MusicLayerConfig {
  /// Ordered list of layer thresholds (index 0 = L1, index 1 = L2, etc.)
  /// L1 is the default layer (always active, threshold 0).
  final List<MusicLayerThreshold> thresholds;

  /// Number of spins without meeting the escalated layer's threshold
  /// before auto-reverting to the previous layer (used when revertMode == 'spins').
  final int revertSpinCount;

  /// Revert mode: 'spins' (count non-winning spins) or 'seconds' (timer-based)
  final String revertMode;

  /// Seconds before auto-reverting when revertMode == 'seconds'
  final double revertSeconds;

  /// Fade-in duration in ms for upshift (escalation)
  final int upshiftFadeMs;

  /// Fade-out duration in ms for downshift (de-escalation / revert)
  final int downshiftFadeMs;

  /// Crossfade curve type: 'equalPower', 'linear', 'sCurve'
  final String crossfadeCurve;

  /// Whether dynamic layer switching is enabled.
  final bool enabled;

  const MusicLayerConfig({
    this.thresholds = const [],
    this.revertSpinCount = 7,
    this.revertMode = 'spins',
    this.revertSeconds = 10.0,
    this.upshiftFadeMs = 1500,
    this.downshiftFadeMs = 1500,
    this.crossfadeCurve = 'equalPower',
    this.enabled = true,
  });

  /// Legacy getter — returns upshiftFadeMs for backward compatibility
  int get crossfadeMs => upshiftFadeMs;

  MusicLayerConfig copyWith({
    List<MusicLayerThreshold>? thresholds,
    int? revertSpinCount,
    String? revertMode,
    double? revertSeconds,
    int? upshiftFadeMs,
    int? downshiftFadeMs,
    int? crossfadeMs, // legacy — maps to upshiftFadeMs
    String? crossfadeCurve,
    bool? enabled,
  }) {
    return MusicLayerConfig(
      thresholds: thresholds ?? this.thresholds,
      revertSpinCount: revertSpinCount ?? this.revertSpinCount,
      revertMode: revertMode ?? this.revertMode,
      revertSeconds: revertSeconds ?? this.revertSeconds,
      upshiftFadeMs: crossfadeMs ?? upshiftFadeMs ?? this.upshiftFadeMs,
      downshiftFadeMs: downshiftFadeMs ?? this.downshiftFadeMs,
      crossfadeCurve: crossfadeCurve ?? this.crossfadeCurve,
      enabled: enabled ?? this.enabled,
    );
  }

  factory MusicLayerConfig.fromJson(Map<String, dynamic> json) {
    final legacyCrossfade = json['crossfadeMs'] as int? ?? 1500;
    return MusicLayerConfig(
      thresholds: (json['thresholds'] as List<dynamic>?)
              ?.map((e) => MusicLayerThreshold.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      revertSpinCount: json['revertSpinCount'] as int? ?? 7,
      revertMode: json['revertMode'] as String? ?? 'spins',
      revertSeconds: (json['revertSeconds'] as num?)?.toDouble() ?? 10.0,
      upshiftFadeMs: json['upshiftFadeMs'] as int? ?? legacyCrossfade,
      downshiftFadeMs: json['downshiftFadeMs'] as int? ?? legacyCrossfade,
      crossfadeCurve: json['crossfadeCurve'] as String? ?? 'equalPower',
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'thresholds': thresholds.map((t) => t.toJson()).toList(),
      'revertSpinCount': revertSpinCount,
      'revertMode': revertMode,
      'revertSeconds': revertSeconds,
      'upshiftFadeMs': upshiftFadeMs,
      'downshiftFadeMs': downshiftFadeMs,
      'crossfadeCurve': crossfadeCurve,
      'enabled': enabled,
    };
  }

  /// Default config for 3 layers: L1 = base, L2 = mid wins, L3 = hot streak
  factory MusicLayerConfig.defaultThreeLayers() {
    return const MusicLayerConfig(
      thresholds: [
        MusicLayerThreshold(layer: 1, minWinRatio: 0.0, label: 'Calm'),
        MusicLayerThreshold(layer: 2, minWinRatio: 1.0, label: 'Warm'),
        MusicLayerThreshold(layer: 3, minWinRatio: 2.0, label: 'Hot'),
      ],
      revertSpinCount: 7,
      upshiftFadeMs: 1500,
      downshiftFadeMs: 1500,
      crossfadeCurve: 'equalPower',
      enabled: true,
    );
  }

  /// Default config for 5 layers
  factory MusicLayerConfig.defaultFiveLayers() {
    return const MusicLayerConfig(
      thresholds: [
        MusicLayerThreshold(layer: 1, minWinRatio: 0.0, label: 'Calm'),
        MusicLayerThreshold(layer: 2, minWinRatio: 1.0, label: 'Warm'),
        MusicLayerThreshold(layer: 3, minWinRatio: 2.0, label: 'Hot'),
        MusicLayerThreshold(layer: 4, minWinRatio: 3.0, label: 'Fire'),
        MusicLayerThreshold(layer: 5, minWinRatio: 4.0, label: 'Inferno'),
      ],
      revertSpinCount: 7,
      upshiftFadeMs: 2000,
      downshiftFadeMs: 2000,
      crossfadeCurve: 'equalPower',
      enabled: true,
    );
  }
}

/// Threshold definition for a single music layer.
/// When winRatio >= minWinRatio, this layer becomes eligible for activation.
class MusicLayerThreshold {
  /// Layer number (1-5, matches MUSIC_BASE_L1-L5)
  final int layer;

  /// Minimum win ratio to activate this layer (0 = always, 2 = 2x bet, etc.)
  final double minWinRatio;

  /// Human-readable label for this layer state
  final String label;

  const MusicLayerThreshold({
    required this.layer,
    required this.minWinRatio,
    this.label = '',
  });

  factory MusicLayerThreshold.fromJson(Map<String, dynamic> json) {
    return MusicLayerThreshold(
      layer: json['layer'] as int,
      minWinRatio: (json['minWinRatio'] as num).toDouble(),
      label: json['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'layer': layer,
      'minWinRatio': minWinRatio,
      'label': label,
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

  // V11: Slot Machine Config (Trostepeni Stage System)
  final SlotMachineConfig? slotMachineConfig;

  // V12: Audio persistence (composite events + EventRegistry)
  final List<Map<String, dynamic>>? compositeEventsJson;
  final List<Map<String, dynamic>>? eventRegistryJson;

  // V13: Dynamic Music Layer Config
  final MusicLayerConfig? musicLayerConfig;

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
    // V11: Slot machine config
    this.slotMachineConfig,
    // V12: Audio persistence
    this.compositeEventsJson,
    this.eventRegistryJson,
    // V13: Dynamic music layer config
    this.musicLayerConfig,
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
      // V11: Slot machine config
      slotMachineConfig: json['slotMachineConfig'] != null
          ? SlotMachineConfig.fromJson(json['slotMachineConfig'] as Map<String, dynamic>)
          : null,
      // V12: Audio persistence
      compositeEventsJson: (json['compositeEvents'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>(),
      eventRegistryJson: (json['eventRegistry'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>(),
      // V13: Dynamic music layer config
      musicLayerConfig: json['musicLayerConfig'] != null
          ? MusicLayerConfig.fromJson(json['musicLayerConfig'] as Map<String, dynamic>)
          : null,
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
      // V11: Slot machine config
      if (slotMachineConfig != null) 'slotMachineConfig': slotMachineConfig!.toJson(),
      // V12: Audio persistence
      if (compositeEventsJson != null && compositeEventsJson!.isNotEmpty)
        'compositeEvents': compositeEventsJson,
      if (eventRegistryJson != null && eventRegistryJson!.isNotEmpty)
        'eventRegistry': eventRegistryJson,
      // V13: Dynamic music layer config
      if (musicLayerConfig != null) 'musicLayerConfig': musicLayerConfig!.toJson(),
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
SymbolDefinition? findSymbolById(List<SymbolDefinition> symbols, String id) =>
    symbols.firstWhereOrNull((s) => s.id == id);

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
