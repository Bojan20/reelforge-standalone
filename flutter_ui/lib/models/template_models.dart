/// Template Gallery Models
///
/// Data models for slot audio templates.
/// Templates are pure JSON configurations - NO audio files included.
///
/// P3-12: Template Gallery
library;

import 'dart:convert';

// ═══════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════

/// Template category for gallery organization
enum TemplateCategory {
  classic('Classic', 'Traditional slot mechanics'),
  video('Video Slots', 'Modern video slot features'),
  megaways('Megaways', 'Dynamic reel mechanics'),
  cluster('Cluster Pays', 'Cluster-based wins'),
  holdWin('Hold & Win', 'Coin collection mechanics'),
  jackpot('Jackpot', 'Progressive jackpot games'),
  branded('Branded', 'Licensed/themed games'),
  custom('Custom', 'User-created templates');

  const TemplateCategory(this.displayName, this.description);
  final String displayName;
  final String description;
}

/// Symbol type classification
enum SymbolType {
  highPay('High Pay', 6), // HP1-HP6
  mediumPay('Medium Pay', 3), // MP1-MP3
  lowPay('Low Pay', 4), // LP1-LP4
  wild('Wild', 1),
  scatter('Scatter', 1),
  bonus('Bonus', 1),
  coin('Coin', 1),
  mystery('Mystery', 1),
  multiplier('Multiplier', 1),
  jackpotMini('Jackpot Mini', 1),
  jackpotMinor('Jackpot Minor', 1),
  jackpotMajor('Jackpot Major', 1),
  jackpotGrand('Jackpot Grand', 1);

  const SymbolType(this.displayName, this.maxCount);
  final String displayName;
  final int maxCount;
}

/// Audio context for symbol sounds
enum SymbolAudioContext {
  land('land', 'SYMBOL_LAND'),
  win('win', 'WIN_SYMBOL_HIGHLIGHT'),
  expand('expand', 'SYMBOL_EXPAND'),
  lock('lock', 'SYMBOL_LOCK'),
  transform('transform', 'SYMBOL_TRANSFORM'),
  collect('collect', 'SYMBOL_COLLECT');

  const SymbolAudioContext(this.id, this.stagePrefix);
  final String id;
  final String stagePrefix;

  String stageForSymbol(String symbolId) => '${stagePrefix}_$symbolId';
}

/// Feature module types
enum FeatureModuleType {
  freeSpins('Free Spins', 'Triggered free spin rounds'),
  holdWin('Hold & Win', 'Coin collection with respins'),
  cascade('Cascade/Tumble', 'Symbols fall and cascade'),
  megaways('Megaways', 'Variable reel sizes'),
  jackpot('Jackpot', 'Progressive or fixed jackpots'),
  gamble('Gamble', 'Risk/reward mini-game'),
  buyBonus('Buy Bonus', 'Direct feature purchase'),
  multiplier('Multiplier', 'Win multiplier mechanics'),
  expanding('Expanding', 'Expanding symbols/wilds'),
  sticky('Sticky', 'Sticky wilds/symbols'),
  walking('Walking', 'Moving wilds'),
  splitting('Splitting', 'Symbol splitting'),
  cloning('Cloning', 'Symbol duplication'),
  mystery('Mystery', 'Mystery symbol reveals');

  const FeatureModuleType(this.displayName, this.description);
  final String displayName;
  final String description;
}

/// Win tier levels (user-configurable thresholds)
enum WinTier {
  tier1('TIER_1', 'Small Win', 1.0), // ≤1x bet always
  tier2('TIER_2', 'Medium Win', 5.0),
  tier3('TIER_3', 'Big Win', 15.0),
  tier4('TIER_4', 'Super Win', 30.0),
  tier5('TIER_5', 'Mega Win', 60.0),
  tier6('TIER_6', 'Epic Win', 100.0);

  const WinTier(this.id, this.defaultLabel, this.defaultThreshold);
  final String id;
  final String defaultLabel;
  final double defaultThreshold;
}

/// Stage category for organization
enum TemplateStageCategory {
  spin('Spin', 'Spin mechanics'),
  reel('Reel', 'Reel animations'),
  symbol('Symbol', 'Symbol interactions'),
  win('Win', 'Win presentation'),
  feature('Feature', 'Feature triggers'),
  music('Music', 'Background music'),
  ui('UI', 'User interface'),
  ambient('Ambient', 'Ambient sounds');

  const TemplateStageCategory(this.displayName, this.description);
  final String displayName;
  final String description;
}

/// Bus routing targets
enum TemplateBus {
  master(0, 'Master', null),
  music(1, 'Music', 0),
  sfx(2, 'SFX', 0),
  reels(3, 'Reels', 2), // Child of SFX
  wins(4, 'Wins', 2), // Child of SFX
  vo(5, 'Voice', 0),
  ui(6, 'UI', 0),
  ambience(7, 'Ambience', 0);

  const TemplateBus(this.engineId, this.displayName, this.parentId);
  final int engineId;
  final String displayName;
  final int? parentId;
}

// ═══════════════════════════════════════════════════════════════════════════
// SYMBOL DEFINITION
// ═══════════════════════════════════════════════════════════════════════════

/// Definition of a symbol in the template
class TemplateSymbol {
  final String id; // HP1, WILD, SCATTER, etc.
  final SymbolType type;
  final int tier; // 1-6 for pay symbols, 0 for special
  final Set<SymbolAudioContext> audioContexts;
  final String? description;

  const TemplateSymbol({
    required this.id,
    required this.type,
    this.tier = 0,
    this.audioContexts = const {
      SymbolAudioContext.land,
      SymbolAudioContext.win,
    },
    this.description,
  });

  /// Generate all stage IDs for this symbol
  List<String> get stageIds => audioContexts.map((c) => c.stageForSymbol(id)).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'tier': tier,
        'audioContexts': audioContexts.map((c) => c.id).toList(),
        if (description != null) 'description': description,
      };

  factory TemplateSymbol.fromJson(Map<String, dynamic> json) => TemplateSymbol(
        id: json['id'] as String,
        type: SymbolType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => SymbolType.lowPay,
        ),
        tier: json['tier'] as int? ?? 0,
        audioContexts: (json['audioContexts'] as List<dynamic>?)
                ?.map((c) => SymbolAudioContext.values.firstWhere(
                      (ctx) => ctx.id == c,
                      orElse: () => SymbolAudioContext.land,
                    ))
                .toSet() ??
            {SymbolAudioContext.land, SymbolAudioContext.win},
        description: json['description'] as String?,
      );

  TemplateSymbol copyWith({
    String? id,
    SymbolType? type,
    int? tier,
    Set<SymbolAudioContext>? audioContexts,
    String? description,
  }) =>
      TemplateSymbol(
        id: id ?? this.id,
        type: type ?? this.type,
        tier: tier ?? this.tier,
        audioContexts: audioContexts ?? this.audioContexts,
        description: description ?? this.description,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// WIN TIER CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// User-configurable win tier settings
class WinTierConfig {
  final WinTier tier;
  final String label; // User-defined label like "BIG WIN!"
  final double threshold; // Multiplier threshold (e.g., 15.0 = 15x bet)
  final double volumeMultiplier; // Audio volume scaling
  final double pitchOffset; // Pitch adjustment in semitones
  final int rollupDurationMs; // How long the rollup animation lasts
  final bool hasScreenEffect; // Screen flash/shake

  const WinTierConfig({
    required this.tier,
    required this.label,
    required this.threshold,
    this.volumeMultiplier = 1.0,
    this.pitchOffset = 0.0,
    this.rollupDurationMs = 2000,
    this.hasScreenEffect = false,
  });

  /// Stage ID for this tier
  String get stageStart => 'WIN_${tier.id}_START';
  String get stageLoop => 'WIN_${tier.id}_LOOP';
  String get stageEnd => 'WIN_${tier.id}_END';

  Map<String, dynamic> toJson() => {
        'tier': tier.name,
        'label': label,
        'threshold': threshold,
        'volumeMultiplier': volumeMultiplier,
        'pitchOffset': pitchOffset,
        'rollupDurationMs': rollupDurationMs,
        'hasScreenEffect': hasScreenEffect,
      };

  factory WinTierConfig.fromJson(Map<String, dynamic> json) => WinTierConfig(
        tier: WinTier.values.firstWhere(
          (t) => t.name == json['tier'],
          orElse: () => WinTier.tier1,
        ),
        label: json['label'] as String,
        threshold: (json['threshold'] as num).toDouble(),
        volumeMultiplier: (json['volumeMultiplier'] as num?)?.toDouble() ?? 1.0,
        pitchOffset: (json['pitchOffset'] as num?)?.toDouble() ?? 0.0,
        rollupDurationMs: json['rollupDurationMs'] as int? ?? 2000,
        hasScreenEffect: json['hasScreenEffect'] as bool? ?? false,
      );

  WinTierConfig copyWith({
    WinTier? tier,
    String? label,
    double? threshold,
    double? volumeMultiplier,
    double? pitchOffset,
    int? rollupDurationMs,
    bool? hasScreenEffect,
  }) =>
      WinTierConfig(
        tier: tier ?? this.tier,
        label: label ?? this.label,
        threshold: threshold ?? this.threshold,
        volumeMultiplier: volumeMultiplier ?? this.volumeMultiplier,
        pitchOffset: pitchOffset ?? this.pitchOffset,
        rollupDurationMs: rollupDurationMs ?? this.rollupDurationMs,
        hasScreenEffect: hasScreenEffect ?? this.hasScreenEffect,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE DEFINITION
// ═══════════════════════════════════════════════════════════════════════════

/// Definition of a stage in the template
class TemplateStageDefinition {
  final String id;
  final String name;
  final TemplateStageCategory category;
  final int priority; // 0-100 (higher = more important)
  final TemplateBus bus;
  final String spatialIntent;
  final bool isPooled; // Use voice pooling for rapid-fire
  final bool isLooping; // Audio loops until stopped
  final bool ducksMusic; // Auto-duck music when playing
  final String? description;

  const TemplateStageDefinition({
    required this.id,
    required this.name,
    required this.category,
    this.priority = 50,
    this.bus = TemplateBus.sfx,
    this.spatialIntent = 'CENTER',
    this.isPooled = false,
    this.isLooping = false,
    this.ducksMusic = false,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.name,
        'priority': priority,
        'bus': bus.name,
        'spatialIntent': spatialIntent,
        'isPooled': isPooled,
        'isLooping': isLooping,
        'ducksMusic': ducksMusic,
        if (description != null) 'description': description,
      };

  factory TemplateStageDefinition.fromJson(Map<String, dynamic> json) =>
      TemplateStageDefinition(
        id: json['id'] as String,
        name: json['name'] as String,
        category: TemplateStageCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => TemplateStageCategory.spin,
        ),
        priority: json['priority'] as int? ?? 50,
        bus: TemplateBus.values.firstWhere(
          (b) => b.name == json['bus'],
          orElse: () => TemplateBus.sfx,
        ),
        spatialIntent: json['spatialIntent'] as String? ?? 'CENTER',
        isPooled: json['isPooled'] as bool? ?? false,
        isLooping: json['isLooping'] as bool? ?? false,
        ducksMusic: json['ducksMusic'] as bool? ?? false,
        description: json['description'] as String?,
      );

  TemplateStageDefinition copyWith({
    String? id,
    String? name,
    TemplateStageCategory? category,
    int? priority,
    TemplateBus? bus,
    String? spatialIntent,
    bool? isPooled,
    bool? isLooping,
    bool? ducksMusic,
    String? description,
  }) =>
      TemplateStageDefinition(
        id: id ?? this.id,
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

// ═══════════════════════════════════════════════════════════════════════════
// FEATURE MODULE
// ═══════════════════════════════════════════════════════════════════════════

/// Feature module that can be added to a template
class FeatureModule {
  final String id;
  final String name;
  final FeatureModuleType type;
  final String description;
  final List<TemplateStageDefinition> stages;
  final List<String> conflictsWith; // Module IDs that conflict
  final List<String> interactsWith; // Module IDs that create interaction stages
  final Map<String, dynamic> defaultConfig;

  const FeatureModule({
    required this.id,
    required this.name,
    required this.type,
    required this.description,
    required this.stages,
    this.conflictsWith = const [],
    this.interactsWith = const [],
    this.defaultConfig = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'description': description,
        'stages': stages.map((s) => s.toJson()).toList(),
        'conflictsWith': conflictsWith,
        'interactsWith': interactsWith,
        'defaultConfig': defaultConfig,
      };

  factory FeatureModule.fromJson(Map<String, dynamic> json) => FeatureModule(
        id: json['id'] as String,
        name: json['name'] as String,
        type: FeatureModuleType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => FeatureModuleType.freeSpins,
        ),
        description: json['description'] as String,
        stages: (json['stages'] as List<dynamic>)
            .map((s) => TemplateStageDefinition.fromJson(s as Map<String, dynamic>))
            .toList(),
        conflictsWith: (json['conflictsWith'] as List<dynamic>?)?.cast<String>() ?? [],
        interactsWith: (json['interactsWith'] as List<dynamic>?)?.cast<String>() ?? [],
        defaultConfig: json['defaultConfig'] as Map<String, dynamic>? ?? {},
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// DUCKING RULE DEFINITION
// ═══════════════════════════════════════════════════════════════════════════

/// Ducking rule definition for template
class TemplateDuckingRule {
  final TemplateBus sourceBus;
  final TemplateBus targetBus;
  final double duckAmountDb;
  final double attackMs;
  final double releaseMs;
  final String? description;

  const TemplateDuckingRule({
    required this.sourceBus,
    required this.targetBus,
    this.duckAmountDb = -6.0,
    this.attackMs = 50.0,
    this.releaseMs = 500.0,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'sourceBus': sourceBus.name,
        'targetBus': targetBus.name,
        'duckAmountDb': duckAmountDb,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
        if (description != null) 'description': description,
      };

  factory TemplateDuckingRule.fromJson(Map<String, dynamic> json) =>
      TemplateDuckingRule(
        sourceBus: TemplateBus.values.firstWhere(
          (b) => b.name == json['sourceBus'],
          orElse: () => TemplateBus.sfx,
        ),
        targetBus: TemplateBus.values.firstWhere(
          (b) => b.name == json['targetBus'],
          orElse: () => TemplateBus.music,
        ),
        duckAmountDb: (json['duckAmountDb'] as num?)?.toDouble() ?? -6.0,
        attackMs: (json['attackMs'] as num?)?.toDouble() ?? 50.0,
        releaseMs: (json['releaseMs'] as num?)?.toDouble() ?? 500.0,
        description: json['description'] as String?,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// ALE CONTEXT DEFINITION
// ═══════════════════════════════════════════════════════════════════════════

/// ALE layer definition
class TemplateAleLayer {
  final int index; // 0-4 (L1-L5)
  final String assetPattern; // Pattern for matching audio file
  final double baseVolume;

  const TemplateAleLayer({
    required this.index,
    required this.assetPattern,
    this.baseVolume = 0.8,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'assetPattern': assetPattern,
        'baseVolume': baseVolume,
      };

  factory TemplateAleLayer.fromJson(Map<String, dynamic> json) =>
      TemplateAleLayer(
        index: json['index'] as int,
        assetPattern: json['assetPattern'] as String,
        baseVolume: (json['baseVolume'] as num?)?.toDouble() ?? 0.8,
      );
}

/// ALE context definition for template
class TemplateAleContext {
  final String id;
  final String name;
  final List<TemplateAleLayer> layers;
  final List<String> entryStages; // Stages that enter this context
  final List<String> exitStages; // Stages that exit this context
  final String? description;

  const TemplateAleContext({
    required this.id,
    required this.name,
    required this.layers,
    this.entryStages = const [],
    this.exitStages = const [],
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'layers': layers.map((l) => l.toJson()).toList(),
        'entryStages': entryStages,
        'exitStages': exitStages,
        if (description != null) 'description': description,
      };

  factory TemplateAleContext.fromJson(Map<String, dynamic> json) =>
      TemplateAleContext(
        id: json['id'] as String,
        name: json['name'] as String,
        layers: (json['layers'] as List<dynamic>)
            .map((l) => TemplateAleLayer.fromJson(l as Map<String, dynamic>))
            .toList(),
        entryStages: (json['entryStages'] as List<dynamic>?)?.cast<String>() ?? [],
        exitStages: (json['exitStages'] as List<dynamic>?)?.cast<String>() ?? [],
        description: json['description'] as String?,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// RTPC DEFINITION
// ═══════════════════════════════════════════════════════════════════════════

/// RTPC curve point
class TemplateRtpcPoint {
  final double x;
  final double y;

  const TemplateRtpcPoint(this.x, this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory TemplateRtpcPoint.fromJson(Map<String, dynamic> json) =>
      TemplateRtpcPoint(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      );
}

/// RTPC definition for template
class TemplateRtpcDefinition {
  final String name;
  final double min;
  final double max;
  final double defaultValue;
  final List<TemplateRtpcPoint> volumeCurve; // Input → Volume multiplier
  final List<TemplateRtpcPoint> pitchCurve; // Input → Pitch offset (semitones)
  final List<TemplateRtpcPoint>? rollupSpeedCurve; // Input → Rollup speed multiplier

  const TemplateRtpcDefinition({
    required this.name,
    required this.min,
    required this.max,
    this.defaultValue = 0.0,
    this.volumeCurve = const [],
    this.pitchCurve = const [],
    this.rollupSpeedCurve,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'min': min,
        'max': max,
        'defaultValue': defaultValue,
        'volumeCurve': volumeCurve.map((p) => p.toJson()).toList(),
        'pitchCurve': pitchCurve.map((p) => p.toJson()).toList(),
        if (rollupSpeedCurve != null)
          'rollupSpeedCurve': rollupSpeedCurve!.map((p) => p.toJson()).toList(),
      };

  factory TemplateRtpcDefinition.fromJson(Map<String, dynamic> json) =>
      TemplateRtpcDefinition(
        name: json['name'] as String,
        min: (json['min'] as num).toDouble(),
        max: (json['max'] as num).toDouble(),
        defaultValue: (json['defaultValue'] as num?)?.toDouble() ?? 0.0,
        volumeCurve: (json['volumeCurve'] as List<dynamic>?)
                ?.map((p) => TemplateRtpcPoint.fromJson(p as Map<String, dynamic>))
                .toList() ??
            [],
        pitchCurve: (json['pitchCurve'] as List<dynamic>?)
                ?.map((p) => TemplateRtpcPoint.fromJson(p as Map<String, dynamic>))
                .toList() ??
            [],
        rollupSpeedCurve: (json['rollupSpeedCurve'] as List<dynamic>?)
            ?.map((p) => TemplateRtpcPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO MAPPING CONVENTION
// ═══════════════════════════════════════════════════════════════════════════

/// Pattern for matching audio files to stages
class AudioMappingPattern {
  final String stagePattern; // Regex or glob pattern for stage ID
  final String filePattern; // Regex or glob pattern for file name
  final int? reelIndex; // For per-reel stages (0-based)
  final String? description;

  const AudioMappingPattern({
    required this.stagePattern,
    required this.filePattern,
    this.reelIndex,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'stagePattern': stagePattern,
        'filePattern': filePattern,
        if (reelIndex != null) 'reelIndex': reelIndex,
        if (description != null) 'description': description,
      };

  factory AudioMappingPattern.fromJson(Map<String, dynamic> json) =>
      AudioMappingPattern(
        stagePattern: json['stagePattern'] as String,
        filePattern: json['filePattern'] as String,
        reelIndex: json['reelIndex'] as int?,
        description: json['description'] as String?,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN TEMPLATE CLASS
// ═══════════════════════════════════════════════════════════════════════════

/// Complete slot audio template
class SlotTemplate {
  final String id;
  final String name;
  final String version;
  final TemplateCategory category;
  final String description;
  final String? author;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Grid configuration
  final int reelCount;
  final int rowCount;
  final bool hasMegaways;

  // Symbols
  final List<TemplateSymbol> symbols;

  // Win tiers (user-configurable)
  final List<WinTierConfig> winTiers;

  // Core stages (always present)
  final List<TemplateStageDefinition> coreStages;

  // Feature modules (optional)
  final List<FeatureModule> modules;

  // Audio routing
  final List<TemplateDuckingRule> duckingRules;

  // Music system (ALE)
  final List<TemplateAleContext> aleContexts;

  // RTPC configuration
  final TemplateRtpcDefinition winMultiplierRtpc;

  // Audio mapping patterns
  final List<AudioMappingPattern> mappingPatterns;

  // Metadata
  final Map<String, dynamic> metadata;

  const SlotTemplate({
    required this.id,
    required this.name,
    required this.version,
    required this.category,
    required this.description,
    this.author,
    this.createdAt,
    this.updatedAt,
    this.reelCount = 5,
    this.rowCount = 3,
    this.hasMegaways = false,
    required this.symbols,
    required this.winTiers,
    required this.coreStages,
    this.modules = const [],
    required this.duckingRules,
    required this.aleContexts,
    required this.winMultiplierRtpc,
    this.mappingPatterns = const [],
    this.metadata = const {},
  });

  /// Get all stages including module stages
  List<TemplateStageDefinition> get allStages {
    final stages = <TemplateStageDefinition>[...coreStages];
    for (final module in modules) {
      stages.addAll(module.stages);
    }
    return stages;
  }

  /// Get all stage IDs
  Set<String> get allStageIds => allStages.map((s) => s.id).toSet();

  /// Get stages by category
  List<TemplateStageDefinition> stagesByCategory(TemplateStageCategory cat) =>
      allStages.where((s) => s.category == cat).toList();

  /// Check if has a specific module type
  bool hasModule(FeatureModuleType type) =>
      modules.any((m) => m.type == type);

  /// Get module by type
  FeatureModule? getModule(FeatureModuleType type) =>
      modules.where((m) => m.type == type).firstOrNull;

  /// Calculate total stage count
  int get totalStageCount => allStages.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'category': category.name,
        'description': description,
        if (author != null) 'author': author,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        'reelCount': reelCount,
        'rowCount': rowCount,
        'hasMegaways': hasMegaways,
        'symbols': symbols.map((s) => s.toJson()).toList(),
        'winTiers': winTiers.map((t) => t.toJson()).toList(),
        'coreStages': coreStages.map((s) => s.toJson()).toList(),
        'modules': modules.map((m) => m.toJson()).toList(),
        'duckingRules': duckingRules.map((r) => r.toJson()).toList(),
        'aleContexts': aleContexts.map((c) => c.toJson()).toList(),
        'winMultiplierRtpc': winMultiplierRtpc.toJson(),
        'mappingPatterns': mappingPatterns.map((p) => p.toJson()).toList(),
        'metadata': metadata,
      };

  factory SlotTemplate.fromJson(Map<String, dynamic> json) => SlotTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        version: json['version'] as String,
        category: TemplateCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => TemplateCategory.custom,
        ),
        description: json['description'] as String,
        author: json['author'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
        reelCount: json['reelCount'] as int? ?? 5,
        rowCount: json['rowCount'] as int? ?? 3,
        hasMegaways: json['hasMegaways'] as bool? ?? false,
        symbols: (json['symbols'] as List<dynamic>)
            .map((s) => TemplateSymbol.fromJson(s as Map<String, dynamic>))
            .toList(),
        winTiers: (json['winTiers'] as List<dynamic>)
            .map((t) => WinTierConfig.fromJson(t as Map<String, dynamic>))
            .toList(),
        coreStages: (json['coreStages'] as List<dynamic>)
            .map((s) => TemplateStageDefinition.fromJson(s as Map<String, dynamic>))
            .toList(),
        modules: (json['modules'] as List<dynamic>?)
                ?.map((m) => FeatureModule.fromJson(m as Map<String, dynamic>))
                .toList() ??
            [],
        duckingRules: (json['duckingRules'] as List<dynamic>)
            .map((r) => TemplateDuckingRule.fromJson(r as Map<String, dynamic>))
            .toList(),
        aleContexts: (json['aleContexts'] as List<dynamic>)
            .map((c) => TemplateAleContext.fromJson(c as Map<String, dynamic>))
            .toList(),
        winMultiplierRtpc: TemplateRtpcDefinition.fromJson(
            json['winMultiplierRtpc'] as Map<String, dynamic>),
        mappingPatterns: (json['mappingPatterns'] as List<dynamic>?)
                ?.map((p) => AudioMappingPattern.fromJson(p as Map<String, dynamic>))
                .toList() ??
            [],
        metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      );

  SlotTemplate copyWith({
    String? id,
    String? name,
    String? version,
    TemplateCategory? category,
    String? description,
    String? author,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? reelCount,
    int? rowCount,
    bool? hasMegaways,
    List<TemplateSymbol>? symbols,
    List<WinTierConfig>? winTiers,
    List<TemplateStageDefinition>? coreStages,
    List<FeatureModule>? modules,
    List<TemplateDuckingRule>? duckingRules,
    List<TemplateAleContext>? aleContexts,
    TemplateRtpcDefinition? winMultiplierRtpc,
    List<AudioMappingPattern>? mappingPatterns,
    Map<String, dynamic>? metadata,
  }) =>
      SlotTemplate(
        id: id ?? this.id,
        name: name ?? this.name,
        version: version ?? this.version,
        category: category ?? this.category,
        description: description ?? this.description,
        author: author ?? this.author,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        reelCount: reelCount ?? this.reelCount,
        rowCount: rowCount ?? this.rowCount,
        hasMegaways: hasMegaways ?? this.hasMegaways,
        symbols: symbols ?? this.symbols,
        winTiers: winTiers ?? this.winTiers,
        coreStages: coreStages ?? this.coreStages,
        modules: modules ?? this.modules,
        duckingRules: duckingRules ?? this.duckingRules,
        aleContexts: aleContexts ?? this.aleContexts,
        winMultiplierRtpc: winMultiplierRtpc ?? this.winMultiplierRtpc,
        mappingPatterns: mappingPatterns ?? this.mappingPatterns,
        metadata: metadata ?? this.metadata,
      );

  /// Export to formatted JSON string
  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Parse from JSON string
  factory SlotTemplate.fromJsonString(String jsonString) =>
      SlotTemplate.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
}

// ═══════════════════════════════════════════════════════════════════════════
// BUILT TEMPLATE (Result of applying template + audio mapping)
// ═══════════════════════════════════════════════════════════════════════════

/// Audio mapping result - stage ID to audio file path
class AudioMapping {
  final String stageId;
  final String audioPath;
  final double volume;
  final double pan;
  final int busId;
  final int priority;
  final bool isLooping;
  final String? notes;

  const AudioMapping({
    required this.stageId,
    required this.audioPath,
    this.volume = 0.8,
    this.pan = 0.0,
    required this.busId,
    this.priority = 50,
    this.isLooping = false,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'stageId': stageId,
        'audioPath': audioPath,
        'volume': volume,
        'pan': pan,
        'busId': busId,
        'priority': priority,
        'isLooping': isLooping,
        if (notes != null) 'notes': notes,
      };

  factory AudioMapping.fromJson(Map<String, dynamic> json) => AudioMapping(
        stageId: json['stageId'] as String,
        audioPath: json['audioPath'] as String,
        volume: (json['volume'] as num?)?.toDouble() ?? 0.8,
        pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
        busId: json['busId'] as int,
        priority: json['priority'] as int? ?? 50,
        isLooping: json['isLooping'] as bool? ?? false,
        notes: json['notes'] as String?,
      );
}

/// Complete built template with all audio mappings resolved
class BuiltTemplate {
  final SlotTemplate source;
  final List<AudioMapping> audioMappings;
  final String audioFolderPath;
  final DateTime builtAt;
  final Map<String, String> userWinLabels; // tier.id → user label

  const BuiltTemplate({
    required this.source,
    required this.audioMappings,
    required this.audioFolderPath,
    required this.builtAt,
    this.userWinLabels = const {},
  });

  /// Get unmapped stages (no audio file assigned)
  List<String> get unmappedStages {
    final mapped = audioMappings.map((m) => m.stageId).toSet();
    return source.allStageIds.where((id) => !mapped.contains(id)).toList();
  }

  /// Get mapping for a specific stage
  AudioMapping? getMappingForStage(String stageId) =>
      audioMappings.where((m) => m.stageId == stageId).firstOrNull;

  /// Check if all critical stages are mapped
  bool get allCriticalStagesMapped {
    const criticalPrefixes = [
      'SPIN_START',
      'SPIN_END',
      'REEL_STOP',
      'WIN_',
    ];
    for (final prefix in criticalPrefixes) {
      final stages = source.allStages.where((s) => s.id.startsWith(prefix));
      for (final stage in stages) {
        if (getMappingForStage(stage.id) == null) {
          return false;
        }
      }
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'source': source.toJson(),
        'audioMappings': audioMappings.map((m) => m.toJson()).toList(),
        'audioFolderPath': audioFolderPath,
        'builtAt': builtAt.toIso8601String(),
        'userWinLabels': userWinLabels,
      };

  factory BuiltTemplate.fromJson(Map<String, dynamic> json) => BuiltTemplate(
        source: SlotTemplate.fromJson(json['source'] as Map<String, dynamic>),
        audioMappings: (json['audioMappings'] as List<dynamic>)
            .map((m) => AudioMapping.fromJson(m as Map<String, dynamic>))
            .toList(),
        audioFolderPath: json['audioFolderPath'] as String,
        builtAt: DateTime.parse(json['builtAt'] as String),
        userWinLabels: (json['userWinLabels'] as Map<String, dynamic>?)
                ?.cast<String, String>() ??
            {},
      );
}
