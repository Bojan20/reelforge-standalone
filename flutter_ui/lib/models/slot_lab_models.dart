/// SlotLab V6 Data Models
///
/// Models for Symbol Strip, Music Layers, and Context definitions.
/// Used by SlotLabProjectProvider for state management.

import 'dart:convert';

// =============================================================================
// SYMBOL DEFINITIONS
// =============================================================================

/// Symbol type categories for slot games
enum SymbolType {
  wild,     // Wild symbols (substitutes)
  scatter,  // Scatter symbols (triggers features)
  high,     // High-paying symbols
  low,      // Low-paying symbols
  bonus,    // Bonus trigger symbols
  multiplier, // Multiplier symbols
  collector,  // Collection symbols
  mystery,    // Mystery/random symbols
}

/// Definition of a slot symbol with audio contexts
class SymbolDefinition {
  final String id;
  final String name;
  final String emoji;
  final SymbolType type;
  final List<String> contexts; // Audio contexts: ['land', 'win', 'expand', 'stack']
  final int? payMultiplier; // Base pay multiplier (for sorting)

  const SymbolDefinition({
    required this.id,
    required this.name,
    required this.emoji,
    required this.type,
    this.contexts = const ['land', 'win'],
    this.payMultiplier,
  });

  /// Audio stage name for this symbol + context
  /// e.g., SYMBOL_LAND_WILD, SYMBOL_WIN_SCATTER
  String stageName(String context) {
    return 'SYMBOL_${context.toUpperCase()}_${id.toUpperCase()}';
  }

  /// Create a copy with updated fields
  SymbolDefinition copyWith({
    String? id,
    String? name,
    String? emoji,
    SymbolType? type,
    List<String>? contexts,
    int? payMultiplier,
  }) {
    return SymbolDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      type: type ?? this.type,
      contexts: contexts ?? this.contexts,
      payMultiplier: payMultiplier ?? this.payMultiplier,
    );
  }

  factory SymbolDefinition.fromJson(Map<String, dynamic> json) {
    return SymbolDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      emoji: json['emoji'] as String,
      type: SymbolType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SymbolType.low,
      ),
      contexts: (json['contexts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const ['land', 'win'],
      payMultiplier: json['payMultiplier'] as int?,
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
    };
  }

  @override
  String toString() => 'SymbolDefinition($name, $emoji, $type)';
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

  String get stageName => 'SYMBOL_${context.toUpperCase()}_${symbolId.toUpperCase()}';

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

  const SlotLabProject({
    required this.name,
    this.version = '1.0',
    this.symbols = const [],
    this.contexts = const [],
    this.symbolAudio = const [],
    this.musicLayers = const [],
    this.metadata,
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
  }) {
    return SlotLabProject(
      name: name ?? this.name,
      version: version ?? this.version,
      symbols: symbols ?? this.symbols,
      contexts: contexts ?? this.contexts,
      symbolAudio: symbolAudio ?? this.symbolAudio,
      musicLayers: musicLayers ?? this.musicLayers,
      metadata: metadata ?? this.metadata,
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

/// Standard slot symbols for new projects
const List<SymbolDefinition> defaultSymbols = [
  SymbolDefinition(
    id: 'wild',
    name: 'Wild',
    emoji: '🃏',
    type: SymbolType.wild,
    contexts: ['land', 'win', 'expand', 'stack'],
    payMultiplier: 100,
  ),
  SymbolDefinition(
    id: 'scatter',
    name: 'Scatter',
    emoji: '⭐',
    type: SymbolType.scatter,
    contexts: ['land', 'win', 'trigger'],
    payMultiplier: 50,
  ),
  SymbolDefinition(
    id: 'bonus',
    name: 'Bonus',
    emoji: '🎁',
    type: SymbolType.bonus,
    contexts: ['land', 'win', 'trigger'],
    payMultiplier: 30,
  ),
  SymbolDefinition(
    id: 'high1',
    name: 'Premium A',
    emoji: '💎',
    type: SymbolType.high,
    contexts: ['land', 'win'],
    payMultiplier: 25,
  ),
  SymbolDefinition(
    id: 'high2',
    name: 'Premium B',
    emoji: '👑',
    type: SymbolType.high,
    contexts: ['land', 'win'],
    payMultiplier: 20,
  ),
  SymbolDefinition(
    id: 'high3',
    name: 'Premium C',
    emoji: '🔔',
    type: SymbolType.high,
    contexts: ['land', 'win'],
    payMultiplier: 15,
  ),
  SymbolDefinition(
    id: 'low1',
    name: 'Low A',
    emoji: 'A',
    type: SymbolType.low,
    contexts: ['land', 'win'],
    payMultiplier: 5,
  ),
  SymbolDefinition(
    id: 'low2',
    name: 'Low K',
    emoji: 'K',
    type: SymbolType.low,
    contexts: ['land', 'win'],
    payMultiplier: 4,
  ),
  SymbolDefinition(
    id: 'low3',
    name: 'Low Q',
    emoji: 'Q',
    type: SymbolType.low,
    contexts: ['land', 'win'],
    payMultiplier: 3,
  ),
  SymbolDefinition(
    id: 'low4',
    name: 'Low J',
    emoji: 'J',
    type: SymbolType.low,
    contexts: ['land', 'win'],
    payMultiplier: 2,
  ),
];

/// Standard symbol contexts for audio assignment
const List<String> standardSymbolContexts = [
  'land',   // Symbol lands on reel
  'win',    // Symbol is part of a win
  'expand', // Symbol expands (expanding wild)
  'stack',  // Symbol stacks
  'trigger',// Symbol triggers feature
];
