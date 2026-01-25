/// GDD Import Service
///
/// Parses Game Design Documents (JSON format) and extracts:
/// - Grid configuration (rows, columns, ways)
/// - Symbol definitions with tiers
/// - Paytable structure
/// - Feature definitions (Free Spins, Bonus, Hold & Spin, etc.)
/// - Stage event mappings
///
/// Part of P3.4: GDD import wizard
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/slot_lab_models.dart' show SymbolDefinition, SymbolType;

// ═══════════════════════════════════════════════════════════════════════════
// GDD MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// Grid configuration from GDD
class GddGridConfig {
  final int rows;
  final int columns;
  final String mechanic; // 'lines', 'ways', 'cluster', 'megaways'
  final int? paylines;
  final int? ways;

  const GddGridConfig({
    required this.rows,
    required this.columns,
    required this.mechanic,
    this.paylines,
    this.ways,
  });

  factory GddGridConfig.fromJson(Map<String, dynamic> json) {
    return GddGridConfig(
      rows: json['rows'] as int? ?? 3,
      columns: json['columns'] as int? ?? 5,
      mechanic: json['mechanic'] as String? ?? 'lines',
      paylines: json['paylines'] as int?,
      ways: json['ways'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'rows': rows,
    'columns': columns,
    'mechanic': mechanic,
    if (paylines != null) 'paylines': paylines,
    if (ways != null) 'ways': ways,
  };
}

/// Symbol tier for audio mapping
enum SymbolTier { low, mid, high, premium, special, wild, scatter, bonus }

extension SymbolTierExtension on SymbolTier {
  String get label => name[0].toUpperCase() + name.substring(1);

  static SymbolTier fromString(String s) {
    return SymbolTier.values.firstWhere(
      (t) => t.name.toLowerCase() == s.toLowerCase(),
      orElse: () => SymbolTier.low,
    );
  }
}

/// Symbol definition from GDD
class GddSymbol {
  final String id;
  final String name;
  final SymbolTier tier;
  final Map<int, double> payouts; // count -> payout multiplier
  final bool isWild;
  final bool isScatter;
  final bool isBonus;

  const GddSymbol({
    required this.id,
    required this.name,
    required this.tier,
    required this.payouts,
    this.isWild = false,
    this.isScatter = false,
    this.isBonus = false,
  });

  factory GddSymbol.fromJson(Map<String, dynamic> json) {
    final payoutsJson = json['payouts'] as Map<String, dynamic>? ?? {};
    final payouts = <int, double>{};
    for (final entry in payoutsJson.entries) {
      payouts[int.parse(entry.key)] = (entry.value as num).toDouble();
    }

    return GddSymbol(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      tier: SymbolTierExtension.fromString(json['tier'] as String? ?? 'low'),
      payouts: payouts,
      isWild: json['isWild'] as bool? ?? false,
      isScatter: json['isScatter'] as bool? ?? false,
      isBonus: json['isBonus'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tier': tier.name,
    'payouts': payouts.map((k, v) => MapEntry(k.toString(), v)),
    'isWild': isWild,
    'isScatter': isScatter,
    'isBonus': isBonus,
  };
}

/// Feature type
enum GddFeatureType {
  freeSpins,
  bonus,
  holdAndSpin,
  cascade,
  gamble,
  jackpot,
  multiplier,
  expanding,
  sticky,
  random,
}

extension GddFeatureTypeExtension on GddFeatureType {
  String get label => switch (this) {
    GddFeatureType.freeSpins => 'Free Spins',
    GddFeatureType.bonus => 'Bonus Game',
    GddFeatureType.holdAndSpin => 'Hold & Spin',
    GddFeatureType.cascade => 'Cascade/Tumble',
    GddFeatureType.gamble => 'Gamble',
    GddFeatureType.jackpot => 'Jackpot',
    GddFeatureType.multiplier => 'Multiplier',
    GddFeatureType.expanding => 'Expanding',
    GddFeatureType.sticky => 'Sticky',
    GddFeatureType.random => 'Random Feature',
  };

  static GddFeatureType fromString(String s) {
    final normalized = s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return GddFeatureType.values.firstWhere(
      (t) => t.name.toLowerCase() == normalized ||
             t.label.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '') == normalized,
      orElse: () => GddFeatureType.bonus,
    );
  }
}

/// Feature definition from GDD
class GddFeature {
  final String id;
  final String name;
  final GddFeatureType type;
  final String? triggerCondition; // e.g., "3+ scatter"
  final int? initialSpins;
  final int? retriggerable;
  final List<String> stages; // Associated stage names

  const GddFeature({
    required this.id,
    required this.name,
    required this.type,
    this.triggerCondition,
    this.initialSpins,
    this.retriggerable,
    this.stages = const [],
  });

  factory GddFeature.fromJson(Map<String, dynamic> json) {
    return GddFeature(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: GddFeatureTypeExtension.fromString(json['type'] as String? ?? 'bonus'),
      triggerCondition: json['triggerCondition'] as String?,
      initialSpins: json['initialSpins'] as int?,
      retriggerable: json['retriggerable'] as int?,
      stages: (json['stages'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    if (triggerCondition != null) 'triggerCondition': triggerCondition,
    if (initialSpins != null) 'initialSpins': initialSpins,
    if (retriggerable != null) 'retriggerable': retriggerable,
    'stages': stages,
  };
}

/// Win tier definition
class GddWinTier {
  final String id;
  final String name;
  final double minMultiplier;
  final double maxMultiplier;

  const GddWinTier({
    required this.id,
    required this.name,
    required this.minMultiplier,
    required this.maxMultiplier,
  });

  factory GddWinTier.fromJson(Map<String, dynamic> json) {
    return GddWinTier(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      minMultiplier: (json['minMultiplier'] as num?)?.toDouble() ?? 0,
      maxMultiplier: (json['maxMultiplier'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'minMultiplier': minMultiplier,
    'maxMultiplier': maxMultiplier,
  };
}

/// Math model configuration
class GddMathModel {
  final double rtp; // Return to Player (0.0-1.0)
  final String volatility; // 'low', 'medium', 'high', 'very_high'
  final double hitFrequency; // 0.0-1.0
  final List<GddWinTier> winTiers;

  const GddMathModel({
    required this.rtp,
    required this.volatility,
    required this.hitFrequency,
    this.winTiers = const [],
  });

  factory GddMathModel.fromJson(Map<String, dynamic> json) {
    final tiersJson = json['winTiers'] as List<dynamic>? ?? [];
    return GddMathModel(
      rtp: (json['rtp'] as num?)?.toDouble() ?? 0.96,
      volatility: json['volatility'] as String? ?? 'medium',
      hitFrequency: (json['hitFrequency'] as num?)?.toDouble() ?? 0.25,
      winTiers: tiersJson.map((t) => GddWinTier.fromJson(t as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'rtp': rtp,
    'volatility': volatility,
    'hitFrequency': hitFrequency,
    'winTiers': winTiers.map((t) => t.toJson()).toList(),
  };
}

/// Complete GDD document
class GameDesignDocument {
  final String name;
  final String version;
  final String? description;
  final GddGridConfig grid;
  final GddMathModel math;
  final List<GddSymbol> symbols;
  final List<GddFeature> features;
  final List<String> customStages; // Additional custom stages

  const GameDesignDocument({
    required this.name,
    required this.version,
    this.description,
    required this.grid,
    required this.math,
    required this.symbols,
    required this.features,
    this.customStages = const [],
  });

  factory GameDesignDocument.fromJson(Map<String, dynamic> json) {
    final symbolsJson = json['symbols'] as List<dynamic>? ?? [];
    final featuresJson = json['features'] as List<dynamic>? ?? [];

    return GameDesignDocument(
      name: json['name'] as String? ?? 'Untitled',
      version: json['version'] as String? ?? '1.0',
      description: json['description'] as String?,
      grid: GddGridConfig.fromJson(json['grid'] as Map<String, dynamic>? ?? {}),
      math: GddMathModel.fromJson(json['math'] as Map<String, dynamic>? ?? {}),
      symbols: symbolsJson.map((s) => GddSymbol.fromJson(s as Map<String, dynamic>)).toList(),
      features: featuresJson.map((f) => GddFeature.fromJson(f as Map<String, dynamic>)).toList(),
      customStages: (json['customStages'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    if (description != null) 'description': description,
    'grid': grid.toJson(),
    'math': math.toJson(),
    'symbols': symbols.map((s) => s.toJson()).toList(),
    'features': features.map((f) => f.toJson()).toList(),
    'customStages': customStages,
  };

  /// Get all symbols of a specific tier
  List<GddSymbol> symbolsByTier(SymbolTier tier) =>
      symbols.where((s) => s.tier == tier).toList();

  /// Check if has free spins feature
  bool get hasFreeSpins =>
      features.any((f) => f.type == GddFeatureType.freeSpins);

  /// Check if has hold and spin feature
  bool get hasHoldAndSpin =>
      features.any((f) => f.type == GddFeatureType.holdAndSpin);

  /// Check if has cascade/tumble mechanic
  bool get hasCascade =>
      features.any((f) => f.type == GddFeatureType.cascade);

  /// Check if has jackpot feature
  bool get hasJackpot =>
      features.any((f) => f.type == GddFeatureType.jackpot);
}

// ═══════════════════════════════════════════════════════════════════════════
// IMPORT RESULT
// ═══════════════════════════════════════════════════════════════════════════

/// Result of GDD import with extracted stages and symbols
class GddImportResult {
  final GameDesignDocument gdd;
  final List<String> generatedStages;
  final List<SymbolDefinition> generatedSymbols;
  final List<String> warnings;
  final List<String> errors;

  const GddImportResult({
    required this.gdd,
    required this.generatedStages,
    required this.generatedSymbols,
    this.warnings = const [],
    this.errors = const [],
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
}

// ═══════════════════════════════════════════════════════════════════════════
// GDD IMPORT SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for importing and processing GDD files
class GddImportService {
  GddImportService._();
  static final GddImportService instance = GddImportService._();

  /// Parse GDD from JSON string
  GddImportResult? importFromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final gdd = GameDesignDocument.fromJson(json);
      final stages = _generateStages(gdd);
      final symbols = generateSymbolDefinitions(gdd);
      final warnings = _validateGdd(gdd);

      debugPrint('[GddImportService] Imported GDD: ${gdd.name}');
      debugPrint('[GddImportService] Generated ${stages.length} stages, ${symbols.length} symbols');

      return GddImportResult(
        gdd: gdd,
        generatedStages: stages,
        generatedSymbols: symbols,
        warnings: warnings,
      );
    } catch (e) {
      debugPrint('[GddImportService] Parse error: $e');
      return GddImportResult(
        gdd: const GameDesignDocument(
          name: 'Error',
          version: '0',
          grid: GddGridConfig(rows: 3, columns: 5, mechanic: 'lines'),
          math: GddMathModel(rtp: 0.96, volatility: 'medium', hitFrequency: 0.25),
          symbols: [],
          features: [],
        ),
        generatedStages: [],
        generatedSymbols: [],
        errors: ['Failed to parse GDD: $e'],
      );
    }
  }

  /// Generate stage names based on GDD features
  List<String> _generateStages(GameDesignDocument gdd) {
    final stages = <String>[];

    // Core spin stages (always present)
    stages.addAll([
      'SPIN_START',
      'SPIN_END',
      'REEL_SPIN_LOOP',
    ]);

    // Per-reel stops
    for (var i = 0; i < gdd.grid.columns; i++) {
      stages.add('REEL_STOP_$i');
    }

    // Win evaluation
    stages.addAll([
      'WIN_EVAL',
      'WIN_PRESENT',
      'WIN_LINE_SHOW',
      'WIN_LINE_HIDE',
    ]);

    // Win tiers
    for (final tier in gdd.math.winTiers) {
      final stageName = 'WIN_${tier.id.toUpperCase()}';
      stages.add(stageName);
    }

    // Symbol lands by tier
    for (final tier in SymbolTier.values) {
      if (gdd.symbols.any((s) => s.tier == tier)) {
        stages.add('SYMBOL_LAND_${tier.name.toUpperCase()}');
      }
    }

    // Wild stages
    if (gdd.symbols.any((s) => s.isWild)) {
      stages.addAll([
        'WILD_LAND',
        'WILD_EXPAND',
        'WILD_STICKY',
      ]);
    }

    // Scatter stages
    if (gdd.symbols.any((s) => s.isScatter)) {
      stages.addAll([
        'SCATTER_LAND',
        'SCATTER_LAND_2',
        'SCATTER_LAND_3',
        'ANTICIPATION_ON',
        'ANTICIPATION_OFF',
      ]);
    }

    // Feature-specific stages
    for (final feature in gdd.features) {
      stages.addAll(_stagesForFeature(feature));
    }

    // Rollup
    stages.addAll([
      'ROLLUP_START',
      'ROLLUP_TICK',
      'ROLLUP_END',
    ]);

    // Add custom stages from GDD
    stages.addAll(gdd.customStages);

    return stages.toSet().toList()..sort();
  }

  /// Generate stages for a specific feature
  List<String> _stagesForFeature(GddFeature feature) {
    switch (feature.type) {
      case GddFeatureType.freeSpins:
        return [
          'FS_TRIGGER',
          'FS_ENTER',
          'FS_SPIN_START',
          'FS_SPIN_END',
          'FS_RETRIGGER',
          'FS_EXIT',
          'FS_SUMMARY',
          'FS_MUSIC',
        ];

      case GddFeatureType.bonus:
        return [
          'BONUS_TRIGGER',
          'BONUS_ENTER',
          'BONUS_STEP',
          'BONUS_REVEAL',
          'BONUS_EXIT',
          'BONUS_MUSIC',
        ];

      case GddFeatureType.holdAndSpin:
        return [
          'HOLD_TRIGGER',
          'HOLD_ENTER',
          'HOLD_SPIN',
          'HOLD_SYMBOL_LAND',
          'HOLD_RESPIN_RESET',
          'HOLD_GRID_FULL',
          'HOLD_EXIT',
          'HOLD_MUSIC',
        ];

      case GddFeatureType.cascade:
        return [
          'CASCADE_START',
          'CASCADE_STEP',
          'CASCADE_SYMBOL_POP',
          'CASCADE_END',
          'CASCADE_COMBO_3',
          'CASCADE_COMBO_4',
          'CASCADE_COMBO_5',
        ];

      case GddFeatureType.gamble:
        return [
          'GAMBLE_START',
          'GAMBLE_CHOICE',
          'GAMBLE_WIN',
          'GAMBLE_LOSE',
          'GAMBLE_COLLECT',
          'GAMBLE_END',
        ];

      case GddFeatureType.jackpot:
        return [
          'JACKPOT_TRIGGER',
          'JACKPOT_MINI',
          'JACKPOT_MINOR',
          'JACKPOT_MAJOR',
          'JACKPOT_GRAND',
          'JACKPOT_PRESENT',
          'JACKPOT_END',
        ];

      case GddFeatureType.multiplier:
        return [
          'MULT_LAND',
          'MULT_APPLY',
          'MULT_INCREASE',
        ];

      case GddFeatureType.expanding:
        return [
          'SYMBOL_EXPAND_START',
          'SYMBOL_EXPAND_COMPLETE',
        ];

      case GddFeatureType.sticky:
        return [
          'SYMBOL_STICKY_LAND',
          'SYMBOL_STICKY_HOLD',
        ];

      case GddFeatureType.random:
        return [
          'RANDOM_TRIGGER',
          'RANDOM_APPLY',
        ];
    }
  }

  /// Validate GDD and return warnings
  List<String> _validateGdd(GameDesignDocument gdd) {
    final warnings = <String>[];

    // Check grid
    if (gdd.grid.rows < 2 || gdd.grid.rows > 8) {
      warnings.add('Unusual row count: ${gdd.grid.rows}');
    }
    if (gdd.grid.columns < 3 || gdd.grid.columns > 10) {
      warnings.add('Unusual column count: ${gdd.grid.columns}');
    }

    // Check math
    if (gdd.math.rtp < 0.85 || gdd.math.rtp > 0.99) {
      warnings.add('RTP ${(gdd.math.rtp * 100).toStringAsFixed(2)}% may be unusual');
    }

    // Check symbols
    if (gdd.symbols.isEmpty) {
      warnings.add('No symbols defined');
    }
    if (!gdd.symbols.any((s) => s.isWild)) {
      warnings.add('No wild symbol defined');
    }

    // Check features
    if (gdd.features.isEmpty) {
      warnings.add('No features defined');
    }

    return warnings;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYMBOL CONVERSION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Convert GDD symbols to SymbolDefinition objects for SlotLabProjectProvider
  List<SymbolDefinition> generateSymbolDefinitions(GameDesignDocument gdd) {
    final symbols = <SymbolDefinition>[];
    var sortOrder = 0;

    for (final gddSymbol in gdd.symbols) {
      symbols.add(_convertGddSymbolToDefinition(gddSymbol, sortOrder++));
    }

    return symbols;
  }

  /// Convert a single GddSymbol to SymbolDefinition
  SymbolDefinition _convertGddSymbolToDefinition(GddSymbol gddSymbol, int sortOrder) {
    // Determine SymbolType from GddSymbol properties
    final SymbolType type;
    if (gddSymbol.isWild) {
      type = SymbolType.wild;
    } else if (gddSymbol.isScatter) {
      type = SymbolType.scatter;
    } else if (gddSymbol.isBonus) {
      type = SymbolType.bonus;
    } else {
      type = _tierToSymbolType(gddSymbol.tier);
    }

    // Generate audio contexts based on symbol type
    final contexts = _generateContextsForType(type, gddSymbol);

    // Get highest payout for payMultiplier
    int? payMultiplier;
    if (gddSymbol.payouts.isNotEmpty) {
      final maxPayout = gddSymbol.payouts.values.reduce((a, b) => a > b ? a : b);
      payMultiplier = maxPayout.round();
    }

    // Choose emoji based on symbol properties
    final emoji = _emojiForSymbol(gddSymbol, type);

    return SymbolDefinition(
      id: gddSymbol.id.toUpperCase(),
      name: gddSymbol.name,
      emoji: emoji,
      type: type,
      contexts: contexts,
      payMultiplier: payMultiplier,
      sortOrder: sortOrder,
      metadata: {
        'tier': gddSymbol.tier.name,
        'payouts': gddSymbol.payouts.map((k, v) => MapEntry(k.toString(), v)),
      },
    );
  }

  /// Map SymbolTier to SymbolType
  SymbolType _tierToSymbolType(SymbolTier tier) {
    switch (tier) {
      case SymbolTier.low:
        return SymbolType.lowPay;
      case SymbolTier.mid:
        return SymbolType.mediumPay;
      case SymbolTier.high:
        return SymbolType.highPay;
      case SymbolTier.premium:
        return SymbolType.highPay;
      case SymbolTier.special:
        return SymbolType.bonus;
      case SymbolTier.wild:
        return SymbolType.wild;
      case SymbolTier.scatter:
        return SymbolType.scatter;
      case SymbolTier.bonus:
        return SymbolType.bonus;
    }
  }

  /// Generate audio contexts based on symbol type
  List<String> _generateContextsForType(SymbolType type, GddSymbol gddSymbol) {
    final contexts = <String>['land', 'win']; // All symbols have land and win

    switch (type) {
      case SymbolType.wild:
        contexts.addAll(['expand', 'transform', 'stack']);
        break;
      case SymbolType.scatter:
        contexts.addAll(['trigger', 'anticipation', 'collect']);
        break;
      case SymbolType.bonus:
        contexts.addAll(['trigger', 'anticipation']);
        break;
      case SymbolType.multiplier:
        contexts.addAll(['trigger', 'collect']);
        break;
      case SymbolType.collector:
        contexts.addAll(['collect', 'trigger']);
        break;
      case SymbolType.mystery:
        contexts.addAll(['transform', 'trigger']);
        break;
      case SymbolType.highPay:
      case SymbolType.high:
        contexts.add('stack'); // High pay symbols often stack
        break;
      case SymbolType.mediumPay:
      case SymbolType.lowPay:
      case SymbolType.low:
      case SymbolType.custom:
        // Just land and win
        break;
    }

    return contexts;
  }

  /// Get emoji for a symbol based on its properties
  String _emojiForSymbol(GddSymbol gddSymbol, SymbolType type) {
    // Check for common symbol names first
    final nameLower = gddSymbol.name.toLowerCase();
    final idLower = gddSymbol.id.toLowerCase();

    // Playing card symbols
    if (idLower == '10' || nameLower.contains('ten')) return '🔟';
    if (idLower == 'j' || nameLower.contains('jack')) return '🃏';
    if (idLower == 'q' || nameLower.contains('queen')) return '👸';
    if (idLower == 'k' || nameLower.contains('king')) return '🤴';
    if (idLower == 'a' || nameLower.contains('ace')) return '🅰️';

    // Common slot symbols
    if (nameLower.contains('gem') || nameLower.contains('diamond')) return '💎';
    if (nameLower.contains('gold') || nameLower.contains('coin')) return '🪙';
    if (nameLower.contains('crown')) return '👑';
    if (nameLower.contains('star')) return '⭐';
    if (nameLower.contains('bell')) return '🔔';
    if (nameLower.contains('cherry') || nameLower.contains('fruit')) return '🍒';
    if (nameLower.contains('seven') || idLower == '7') return '7️⃣';
    if (nameLower.contains('bar')) return '🎰';

    // Fallback based on type
    return switch (type) {
      SymbolType.wild => '🌟',
      SymbolType.scatter => '💠',
      SymbolType.bonus => '🎁',
      SymbolType.multiplier => '✖️',
      SymbolType.collector => '🧲',
      SymbolType.mystery => '❓',
      SymbolType.highPay || SymbolType.high => '💎',
      SymbolType.mediumPay => '🔷',
      SymbolType.lowPay || SymbolType.low => '🔹',
      SymbolType.custom => '🎰',
    };
  }

  /// Create sample GDD JSON for reference
  String createSampleGddJson() {
    final sample = GameDesignDocument(
      name: 'Sample Slot',
      version: '1.0',
      description: 'A sample slot game configuration',
      grid: const GddGridConfig(
        rows: 3,
        columns: 5,
        mechanic: 'lines',
        paylines: 20,
      ),
      math: GddMathModel(
        rtp: 0.96,
        volatility: 'medium',
        hitFrequency: 0.28,
        winTiers: const [
          GddWinTier(id: 'small', name: 'Small Win', minMultiplier: 0.5, maxMultiplier: 2),
          GddWinTier(id: 'medium', name: 'Medium Win', minMultiplier: 2, maxMultiplier: 10),
          GddWinTier(id: 'big', name: 'Big Win', minMultiplier: 10, maxMultiplier: 25),
          GddWinTier(id: 'mega', name: 'Mega Win', minMultiplier: 25, maxMultiplier: 50),
          GddWinTier(id: 'epic', name: 'Epic Win', minMultiplier: 50, maxMultiplier: 100),
        ],
      ),
      symbols: const [
        GddSymbol(id: '10', name: 'Ten', tier: SymbolTier.low, payouts: {3: 0.5, 4: 1, 5: 2}),
        GddSymbol(id: 'J', name: 'Jack', tier: SymbolTier.low, payouts: {3: 0.5, 4: 1.5, 5: 2.5}),
        GddSymbol(id: 'Q', name: 'Queen', tier: SymbolTier.mid, payouts: {3: 1, 4: 2, 5: 4}),
        GddSymbol(id: 'K', name: 'King', tier: SymbolTier.mid, payouts: {3: 1, 4: 2.5, 5: 5}),
        GddSymbol(id: 'A', name: 'Ace', tier: SymbolTier.high, payouts: {3: 1.5, 4: 3, 5: 7.5}),
        GddSymbol(id: 'gem', name: 'Gem', tier: SymbolTier.premium, payouts: {3: 2, 4: 5, 5: 15}),
        GddSymbol(id: 'wild', name: 'Wild', tier: SymbolTier.wild, payouts: {3: 5, 4: 15, 5: 50}, isWild: true),
        GddSymbol(id: 'scatter', name: 'Scatter', tier: SymbolTier.scatter, payouts: {3: 2, 4: 10, 5: 50}, isScatter: true),
      ],
      features: const [
        GddFeature(
          id: 'freespins',
          name: 'Free Spins',
          type: GddFeatureType.freeSpins,
          triggerCondition: '3+ scatter',
          initialSpins: 10,
          retriggerable: 5,
        ),
        GddFeature(
          id: 'gamble',
          name: 'Gamble',
          type: GddFeatureType.gamble,
        ),
      ],
      customStages: ['MY_CUSTOM_EVENT'],
    );

    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(sample.toJson());
  }
}
