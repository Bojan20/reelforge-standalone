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
import '../models/win_tier_config.dart';

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
      // Accept both 'reels' (Rust) and 'columns' (legacy) for compatibility
      columns: json['reels'] as int? ?? json['columns'] as int? ?? 5,
      mechanic: json['mechanic'] as String? ?? 'lines',
      paylines: json['paylines'] as int?,
      ways: json['ways'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'rows': rows,
    'reels': columns,  // Rust engine expects 'reels' not 'columns'
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

  /// Convert to Rust-expected GDD JSON format
  /// This is the format that rf-slot-lab's GddParser expects
  Map<String, dynamic> toRustJson() {
    // Convert symbol tier enum to numeric tier (1-8)
    int tierToNum(SymbolTier tier) => switch (tier) {
      SymbolTier.low => 1,
      SymbolTier.mid => 2,
      SymbolTier.high => 3,
      SymbolTier.premium => 4,
      SymbolTier.special => 5,
      SymbolTier.wild => 6,
      SymbolTier.scatter => 7,
      SymbolTier.bonus => 8,
    };

    // Convert symbol type to Rust string
    String symbolTypeStr(GddSymbol s) {
      if (s.isWild) return 'wild';
      if (s.isScatter) return 'scatter';
      if (s.isBonus) return 'bonus';
      return switch (s.tier) {
        SymbolTier.premium => 'high_pay',
        SymbolTier.high => 'high_pay',
        SymbolTier.mid => 'mid_pay',
        SymbolTier.low => 'low_pay',
        _ => 'regular',
      };
    }

    // Convert payouts map to pays array [0, 0, 3x, 4x, 5x, ...]
    // Index = symbol count, value = payout multiplier
    List<double> payoutsToArray(Map<int, double> payouts) {
      if (payouts.isEmpty) return [0, 0, 0, 0, 0];
      final maxCount = payouts.keys.reduce((a, b) => a > b ? a : b);
      final pays = List<double>.filled(maxCount + 1, 0);
      for (final entry in payouts.entries) {
        pays[entry.key] = entry.value;
      }
      return pays;
    }

    // Convert feature type to Rust string
    String featureTypeStr(GddFeatureType type) => switch (type) {
      GddFeatureType.freeSpins => 'free_spins',
      GddFeatureType.bonus => 'bonus',
      GddFeatureType.holdAndSpin => 'hold_and_spin',
      GddFeatureType.cascade => 'cascade',
      GddFeatureType.gamble => 'gamble',
      GddFeatureType.jackpot => 'jackpot',
      GddFeatureType.multiplier => 'multiplier',
      GddFeatureType.expanding => 'expanding_wild',
      GddFeatureType.sticky => 'sticky_wild',
      GddFeatureType.random => 'random',
    };

    // Build symbol weights - distribute by tier
    // Higher tiers = lower frequency (smaller weights)
    final symbolWeights = <String, List<int>>{};
    for (int i = 0; i < symbols.length; i++) {
      final s = symbols[i];
      // Default weights per reel (5 reels) based on tier
      final baseWeight = switch (s.tier) {
        SymbolTier.wild => 2,    // Very rare
        SymbolTier.scatter => 3, // Rare
        SymbolTier.bonus => 3,   // Rare
        SymbolTier.premium => 5, // Uncommon
        SymbolTier.high => 8,    // Less common
        SymbolTier.mid => 12,    // Common
        SymbolTier.low => 18,    // Very common
        SymbolTier.special => 4, // Rare
      };
      // Create weights for each reel
      symbolWeights[s.name] = List.filled(grid.columns, baseWeight);
    }

    return {
      // Game info (Rust expects nested 'game' object)
      'game': {
        'name': name,
        'id': name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_'),
        'provider': 'FluxForge',
        'volatility': math.volatility,
        'target_rtp': math.rtp,
      },
      // Grid (Rust expects reels, rows, paylines)
      'grid': {
        'reels': grid.columns,
        'rows': grid.rows,
        'paylines': grid.paylines ?? (grid.mechanic == 'ways' ? null : 20),
      },
      // Win mechanism
      'win_mechanism': grid.mechanic == 'ways'
          ? 'ways_${grid.ways ?? 243}'
          : grid.mechanic == 'cluster'
              ? 'cluster'
              : grid.mechanic == 'megaways'
                  ? 'megaways'
                  : 'paylines',
      // Symbols (Rust expects id as u32, type as string, pays as array)
      'symbols': symbols.asMap().entries.map((entry) {
        final i = entry.key;
        final s = entry.value;
        return {
          'id': i, // Numeric ID
          'name': s.name,
          'type': symbolTypeStr(s),
          'pays': payoutsToArray(s.payouts),
          'tier': tierToNum(s.tier),
        };
      }).toList(),
      // Features (Rust expects feature_type and trigger)
      'features': features.map((f) {
        return {
          'type': featureTypeStr(f.type),
          'trigger': f.triggerCondition ?? '3+ scatter',
          if (f.initialSpins != null) 'spins': f.initialSpins,
          if (f.retriggerable != null) 'retriggerable': f.retriggerable,
          'id': f.id,
        };
      }).toList(),
      // Win tiers
      'win_tiers': math.winTiers.map((t) {
        return {
          'name': t.name,
          'min_ratio': t.minMultiplier,
          'max_ratio': t.maxMultiplier,
        };
      }).toList(),
      // Math model with symbol weights
      'math': {
        'target_rtp': math.rtp,
        'volatility': math.volatility,
        'symbol_weights': symbolWeights,
      },
    };
  }

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
// P5 WIN TIER CONVERSION FROM GDD
// ═══════════════════════════════════════════════════════════════════════════

/// Convert GDD win tiers to P5 SlotWinConfiguration
///
/// Maps GDD win tiers (simple multiplier ranges) to the full P5 system with:
/// - Regular wins (< threshold)
/// - Big wins (>= threshold)
/// - Rollup durations calculated from multiplier ranges
SlotWinConfiguration convertGddWinTiersToP5(GddMathModel math) {
  final gddTiers = math.winTiers;

  // Determine big win threshold based on GDD volatility
  // Higher volatility = higher threshold for big wins
  final bigWinThreshold = switch (math.volatility.toLowerCase()) {
    'very_high' || 'extreme' => 25.0,
    'high' => 20.0,
    'medium' || 'med' => 15.0,
    'low' => 10.0,
    _ => 20.0, // Default
  };

  // Split tiers into regular and big wins
  final regularGddTiers = gddTiers.where((t) => t.minMultiplier < bigWinThreshold).toList();
  final bigGddTiers = gddTiers.where((t) => t.minMultiplier >= bigWinThreshold).toList();

  // Build regular win tiers (P5 format)
  final regularTiers = <WinTierDefinition>[];

  // Add WIN_LOW tier (< 1x bet)
  regularTiers.add(const WinTierDefinition(
    tierId: -1,
    fromMultiplier: 0.0,
    toMultiplier: 1.0,
    displayLabel: 'Win',
    rollupDurationMs: 800,
    rollupTickRate: 20,
  ));

  // Convert each GDD regular tier to P5 tier
  int tierId = 1;
  for (final gddTier in regularGddTiers) {
    // Skip tiers that would overlap with bigWin
    if (gddTier.maxMultiplier > bigWinThreshold) {
      // Clamp to bigWinThreshold
      final clampedMax = bigWinThreshold;
      if (gddTier.minMultiplier >= clampedMax) continue;

      regularTiers.add(WinTierDefinition(
        tierId: tierId,
        fromMultiplier: gddTier.minMultiplier,
        toMultiplier: clampedMax,
        displayLabel: gddTier.name,
        rollupDurationMs: _calculateRollupDuration(gddTier.minMultiplier, clampedMax),
        rollupTickRate: _calculateTickRate(gddTier.minMultiplier),
      ));
    } else {
      regularTiers.add(WinTierDefinition(
        tierId: tierId,
        fromMultiplier: gddTier.minMultiplier,
        toMultiplier: gddTier.maxMultiplier,
        displayLabel: gddTier.name,
        rollupDurationMs: _calculateRollupDuration(gddTier.minMultiplier, gddTier.maxMultiplier),
        rollupTickRate: _calculateTickRate(gddTier.minMultiplier),
      ));
    }
    tierId++;
    if (tierId > 5) break; // Max 5 regular tiers (WIN_1 to WIN_5)
  }

  // Build big win tiers (P5 format)
  final bigWinTiers = <BigWinTierDefinition>[];

  // If GDD has explicit big win tiers, use them
  if (bigGddTiers.isNotEmpty) {
    int bigTierId = 1;
    for (final gddTier in bigGddTiers) {
      bigWinTiers.add(BigWinTierDefinition(
        tierId: bigTierId,
        fromMultiplier: gddTier.minMultiplier,
        toMultiplier: gddTier.maxMultiplier > 9999 ? double.infinity : gddTier.maxMultiplier,
        displayLabel: gddTier.name.toUpperCase(),
        durationMs: _calculateBigWinDuration(bigTierId, math.volatility),
        rollupTickRate: _calculateBigWinTickRate(bigTierId),
      ));
      bigTierId++;
      if (bigTierId > 5) break; // Max 5 big win tiers
    }
  }

  // If no big win tiers in GDD, generate defaults
  if (bigWinTiers.isEmpty) {
    bigWinTiers.addAll(_defaultBigWinTiersForVolatility(math.volatility, bigWinThreshold));
  }

  // Ensure we have 5 big win tiers (fill gaps)
  while (bigWinTiers.length < 5) {
    final lastTier = bigWinTiers.lastOrNull;
    final nextTierId = (lastTier?.tierId ?? 0) + 1;
    final fromMult = lastTier?.toMultiplier ?? bigWinThreshold;

    bigWinTiers.add(BigWinTierDefinition(
      tierId: nextTierId,
      fromMultiplier: fromMult,
      toMultiplier: nextTierId == 5 ? double.infinity : fromMult * 2,
      displayLabel: 'BIG WIN ${nextTierId}',
      durationMs: _calculateBigWinDuration(nextTierId, math.volatility),
      rollupTickRate: _calculateBigWinTickRate(nextTierId),
    ));
  }

  return SlotWinConfiguration(
    regularWins: RegularWinTierConfig(
      configId: 'gdd_imported',
      name: 'GDD Import',
      source: WinTierConfigSource.gddImport,
      tiers: regularTiers,
    ),
    bigWins: BigWinConfig(
      threshold: bigWinThreshold,
      tiers: bigWinTiers,
    ),
  );
}

/// Calculate rollup duration based on multiplier range
int _calculateRollupDuration(double fromMult, double toMult) {
  final midMult = (fromMult + toMult) / 2;
  // Base duration scales with multiplier
  if (midMult < 1) return 800;
  if (midMult < 2) return 1000;
  if (midMult < 5) return 1500;
  if (midMult < 10) return 2000;
  if (midMult < 15) return 2500;
  return 3000;
}

/// Calculate tick rate (slower for higher wins)
int _calculateTickRate(double fromMult) {
  if (fromMult < 1) return 25;
  if (fromMult < 2) return 20;
  if (fromMult < 5) return 15;
  if (fromMult < 10) return 12;
  if (fromMult < 15) return 10;
  return 8;
}

/// Calculate big win duration based on tier and volatility
int _calculateBigWinDuration(int tierId, String volatility) {
  final isHighVol = volatility.toLowerCase().contains('high');

  // Higher tiers = longer celebrations
  final baseDuration = switch (tierId) {
    1 => 3000,
    2 => 5000,
    3 => 8000,
    4 => 12000,
    5 => 18000,
    _ => 3000,
  };

  // High volatility games have longer celebrations
  return isHighVol ? (baseDuration * 1.3).round() : baseDuration;
}

/// Calculate big win tick rate (slower for higher tiers)
int _calculateBigWinTickRate(int tierId) {
  return switch (tierId) {
    1 => 12,
    2 => 10,
    3 => 8,
    4 => 6,
    5 => 4,
    _ => 10,
  };
}

/// Generate default big win tiers based on volatility
List<BigWinTierDefinition> _defaultBigWinTiersForVolatility(String volatility, double threshold) {
  final volLower = volatility.toLowerCase();

  // Determine tier multiplier ranges based on volatility
  final (t1End, t2End, t3End, t4End) = switch (volLower) {
    'very_high' || 'extreme' => (50.0, 100.0, 250.0, 500.0),
    'high' => (40.0, 80.0, 150.0, 300.0),
    'medium' || 'med' => (30.0, 60.0, 100.0, 200.0),
    'low' => (25.0, 50.0, 80.0, 150.0),
    _ => (40.0, 80.0, 150.0, 300.0),
  };

  return [
    BigWinTierDefinition(
      tierId: 1,
      fromMultiplier: threshold,
      toMultiplier: t1End,
      displayLabel: 'BIG WIN',
      durationMs: _calculateBigWinDuration(1, volatility),
      rollupTickRate: _calculateBigWinTickRate(1),
    ),
    BigWinTierDefinition(
      tierId: 2,
      fromMultiplier: t1End,
      toMultiplier: t2End,
      displayLabel: 'SUPER WIN',
      durationMs: _calculateBigWinDuration(2, volatility),
      rollupTickRate: _calculateBigWinTickRate(2),
    ),
    BigWinTierDefinition(
      tierId: 3,
      fromMultiplier: t2End,
      toMultiplier: t3End,
      displayLabel: 'MEGA WIN',
      durationMs: _calculateBigWinDuration(3, volatility),
      rollupTickRate: _calculateBigWinTickRate(3),
    ),
    BigWinTierDefinition(
      tierId: 4,
      fromMultiplier: t3End,
      toMultiplier: t4End,
      displayLabel: 'EPIC WIN',
      durationMs: _calculateBigWinDuration(4, volatility),
      rollupTickRate: _calculateBigWinTickRate(4),
    ),
    BigWinTierDefinition(
      tierId: 5,
      fromMultiplier: t4End,
      toMultiplier: double.infinity,
      displayLabel: 'ULTRA WIN',
      durationMs: _calculateBigWinDuration(5, volatility),
      rollupTickRate: _calculateBigWinTickRate(5),
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════
// GDD IMPORT SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for importing and processing GDD files
class GddImportService {
  GddImportService._();
  static final GddImportService instance = GddImportService._();

  /// Parse GDD from JSON string or plain text
  GddImportResult? importFromJson(String input) {
    final trimmed = input.trim();

    // Try JSON first
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return _parseFromJson(trimmed);
    }

    // Fallback: parse as plain text (PDF extraction)
    return _parseFromText(trimmed);
  }

  /// Parse from JSON format
  GddImportResult? _parseFromJson(String jsonString) {
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
      debugPrint('[GddImportService] JSON parse error: $e');
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
        errors: ['Failed to parse JSON: $e'],
      );
    }
  }

  /// Parse GDD from plain text (PDF extraction)
  /// Extracts game configuration using regex patterns
  GddImportResult? _parseFromText(String text) {
    debugPrint('[GddImportService] Parsing plain text (${text.length} chars)');

    final warnings = <String>[];
    final textLower = text.toLowerCase();

    // ═══════════════════════════════════════════════════════════════════════
    // EXTRACT GAME NAME
    // ═══════════════════════════════════════════════════════════════════════
    String gameName = 'Imported Game';

    // Try to find game name from common patterns
    final namePatterns = [
      RegExp(r'game\s*name[:\s]+([^\n\r]+)', caseSensitive: false),
      RegExp(r'title[:\s]+([^\n\r]+)', caseSensitive: false),
      RegExp(r'^([A-Z][A-Za-z\s]+)\s*$', multiLine: true), // Title case at start
    ];
    for (final pattern in namePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.group(1) != null) {
        gameName = match.group(1)!.trim();
        if (gameName.length > 3 && gameName.length < 50) break;
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXTRACT GRID CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════
    int reels = 5;
    int rows = 3;
    String mechanic = 'lines';
    int? paylines;
    int? ways;

    // Reels: "5 reels", "5-reel", "5 kolona", "reels: 5"
    final reelPatterns = [
      RegExp(r'(\d+)\s*[-\s]?reels?', caseSensitive: false),
      RegExp(r'reels?[:\s]+(\d+)', caseSensitive: false),
      RegExp(r'(\d+)\s*kolona', caseSensitive: false),
      RegExp(r'(\d+)\s*columns?', caseSensitive: false),
    ];
    for (final pattern in reelPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final val = int.tryParse(match.group(1) ?? '');
        if (val != null && val >= 3 && val <= 10) {
          reels = val;
          break;
        }
      }
    }

    // Rows: "3 rows", "3 reda", "rows: 3"
    final rowPatterns = [
      RegExp(r'(\d+)\s*rows?', caseSensitive: false),
      RegExp(r'rows?[:\s]+(\d+)', caseSensitive: false),
      RegExp(r'(\d+)\s*reda', caseSensitive: false),
      RegExp(r'(\d+)\s*x\s*\d+', caseSensitive: false), // "3x5" grid
    ];
    for (final pattern in rowPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final val = int.tryParse(match.group(1) ?? '');
        if (val != null && val >= 2 && val <= 8) {
          rows = val;
          break;
        }
      }
    }

    // Paylines: "20 paylines", "20 linija", "paylines: 20"
    final paylinesPatterns = [
      RegExp(r'(\d+)\s*paylines?', caseSensitive: false),
      RegExp(r'paylines?[:\s]+(\d+)', caseSensitive: false),
      RegExp(r'(\d+)\s*linija', caseSensitive: false),
      RegExp(r'(\d+)\s*lines?', caseSensitive: false),
    ];
    for (final pattern in paylinesPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final val = int.tryParse(match.group(1) ?? '');
        if (val != null && val >= 1 && val <= 1000) {
          paylines = val;
          mechanic = 'lines';
          break;
        }
      }
    }

    // Ways: "243 ways", "ways to win", "megaways"
    if (textLower.contains('megaways')) {
      mechanic = 'megaways';
      ways = 117649; // Default Megaways
    } else if (textLower.contains('ways to win') || textLower.contains('all ways')) {
      mechanic = 'ways';
      final waysMatch = RegExp(r'(\d+)\s*ways', caseSensitive: false).firstMatch(text);
      if (waysMatch != null) {
        ways = int.tryParse(waysMatch.group(1) ?? '');
      }
      ways ??= 243; // Default ways
    }

    // Cluster
    if (textLower.contains('cluster') || textLower.contains('grid')) {
      mechanic = 'cluster';
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXTRACT MATH MODEL
    // ═══════════════════════════════════════════════════════════════════════
    double rtp = 0.96;
    String volatility = 'medium';
    double hitFrequency = 0.25;

    // RTP: "96.5%", "RTP: 96.5", "RTP 96.5%"
    final rtpPatterns = [
      RegExp(r'rtp[:\s]*(\d+\.?\d*)\s*%?', caseSensitive: false),
      RegExp(r'(\d+\.?\d*)\s*%?\s*rtp', caseSensitive: false),
      RegExp(r'return[:\s]*(\d+\.?\d*)\s*%', caseSensitive: false),
    ];
    for (final pattern in rtpPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final val = double.tryParse(match.group(1) ?? '');
        if (val != null) {
          rtp = val > 1 ? val / 100 : val; // Convert percentage
          break;
        }
      }
    }

    // Volatility: "high volatility", "medium variance"
    if (textLower.contains('very high') || textLower.contains('extreme')) {
      volatility = 'very_high';
    } else if (textLower.contains('high volatility') || textLower.contains('high variance')) {
      volatility = 'high';
    } else if (textLower.contains('low volatility') || textLower.contains('low variance')) {
      volatility = 'low';
    } else if (textLower.contains('medium') || textLower.contains('mid')) {
      volatility = 'medium';
    }

    // Hit frequency: "hit rate: 25%", "25% hit frequency"
    final hitPatterns = [
      RegExp(r'hit\s*(?:rate|frequency)[:\s]*(\d+\.?\d*)\s*%?', caseSensitive: false),
      RegExp(r'(\d+\.?\d*)\s*%?\s*hit', caseSensitive: false),
    ];
    for (final pattern in hitPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final val = double.tryParse(match.group(1) ?? '');
        if (val != null) {
          hitFrequency = val > 1 ? val / 100 : val;
          break;
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXTRACT SYMBOLS
    // ═══════════════════════════════════════════════════════════════════════
    final symbols = <GddSymbol>[];

    // Common slot symbol names with tier assignments
    final symbolKeywords = {
      // Low pay (playing cards)
      '10': (SymbolTier.low, false, false, false),
      'ten': (SymbolTier.low, false, false, false),
      'j': (SymbolTier.low, false, false, false),
      'jack': (SymbolTier.low, false, false, false),
      'q': (SymbolTier.low, false, false, false),
      'queen': (SymbolTier.low, false, false, false),
      'k': (SymbolTier.mid, false, false, false),
      'king': (SymbolTier.mid, false, false, false),
      'a': (SymbolTier.mid, false, false, false),
      'ace': (SymbolTier.mid, false, false, false),
      // Special
      'wild': (SymbolTier.wild, true, false, false),
      'scatter': (SymbolTier.scatter, false, true, false),
      'bonus': (SymbolTier.bonus, false, false, true),
      // High pay (common themes)
      'diamond': (SymbolTier.premium, false, false, false),
      'gem': (SymbolTier.premium, false, false, false),
      'crown': (SymbolTier.high, false, false, false),
      'gold': (SymbolTier.high, false, false, false),
      'star': (SymbolTier.high, false, false, false),
      'seven': (SymbolTier.premium, false, false, false),
      '7': (SymbolTier.premium, false, false, false),
      'bar': (SymbolTier.mid, false, false, false),
      'bell': (SymbolTier.mid, false, false, false),
      'cherry': (SymbolTier.low, false, false, false),
      'fruit': (SymbolTier.low, false, false, false),
      // Greek mythology theme symbols
      'zeus': (SymbolTier.premium, false, false, false),
      'poseidon': (SymbolTier.premium, false, false, false),
      'hades': (SymbolTier.high, false, false, false),
      'athena': (SymbolTier.high, false, false, false),
      'apollo': (SymbolTier.high, false, false, false),
      'hermes': (SymbolTier.mid, false, false, false),
      'ares': (SymbolTier.high, false, false, false),
      'trident': (SymbolTier.mid, false, false, false),
      'helmet': (SymbolTier.mid, false, false, false),
      'shield': (SymbolTier.mid, false, false, false),
      'lyre': (SymbolTier.mid, false, false, false),
      'vase': (SymbolTier.low, false, false, false),
      'laurel': (SymbolTier.low, false, false, false),
      'amphora': (SymbolTier.low, false, false, false),
      'coin': (SymbolTier.low, false, false, false),
      'orb': (SymbolTier.bonus, false, false, true),
      'lightning': (SymbolTier.wild, true, false, false),
      // Egyptian theme
      'pharaoh': (SymbolTier.premium, false, false, false),
      'cleopatra': (SymbolTier.premium, false, false, false),
      'anubis': (SymbolTier.high, false, false, false),
      'ra': (SymbolTier.high, false, false, false),
      'horus': (SymbolTier.high, false, false, false),
      'scarab': (SymbolTier.mid, false, false, false),
      'eye': (SymbolTier.mid, false, false, false),
      'ankh': (SymbolTier.mid, false, false, false),
      'pyramid': (SymbolTier.mid, false, false, false),
      // Asian theme
      'dragon': (SymbolTier.premium, false, false, false),
      'phoenix': (SymbolTier.premium, false, false, false),
      'tiger': (SymbolTier.high, false, false, false),
      'turtle': (SymbolTier.high, false, false, false),
      'koi': (SymbolTier.mid, false, false, false),
      'lantern': (SymbolTier.mid, false, false, false),
      'fan': (SymbolTier.low, false, false, false),
      // Irish/Celtic theme
      'leprechaun': (SymbolTier.premium, false, false, false),
      'pot': (SymbolTier.high, false, false, false),
      'rainbow': (SymbolTier.high, false, false, false),
      'clover': (SymbolTier.mid, false, false, false),
      'shamrock': (SymbolTier.mid, false, false, false),
      'horseshoe': (SymbolTier.mid, false, false, false),
      // Norse theme
      'odin': (SymbolTier.premium, false, false, false),
      'thor': (SymbolTier.premium, false, false, false),
      'freya': (SymbolTier.high, false, false, false),
      'loki': (SymbolTier.high, false, false, false),
      'mjolnir': (SymbolTier.mid, false, false, false),
      'raven': (SymbolTier.mid, false, false, false),
      'rune': (SymbolTier.low, false, false, false),
      // Adventure theme
      'explorer': (SymbolTier.premium, false, false, false),
      'treasure': (SymbolTier.high, false, false, false),
      'map': (SymbolTier.mid, false, false, false),
      'compass': (SymbolTier.mid, false, false, false),
      'chest': (SymbolTier.high, false, false, false),
      // Animal theme
      'lion': (SymbolTier.premium, false, false, false),
      'eagle': (SymbolTier.high, false, false, false),
      'wolf': (SymbolTier.high, false, false, false),
      'bear': (SymbolTier.high, false, false, false),
      'buffalo': (SymbolTier.premium, false, false, false),
    };

    // Find symbol mentions from keywords
    for (final entry in symbolKeywords.entries) {
      final keyword = entry.key;
      final (tier, isWild, isScatter, isBonus) = entry.value;

      // Check if keyword appears in text as a word
      if (RegExp(r'\b' + keyword + r'\b', caseSensitive: false).hasMatch(text)) {
        // Avoid duplicates
        if (!symbols.any((s) => s.id.toLowerCase() == keyword.toLowerCase())) {
          symbols.add(GddSymbol(
            id: keyword.toUpperCase(),
            name: keyword[0].toUpperCase() + keyword.substring(1),
            tier: tier,
            payouts: _defaultPayoutsForTier(tier),
            isWild: isWild,
            isScatter: isScatter,
            isBonus: isBonus,
          ));
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXTRACT CUSTOM SYMBOLS FROM PAYTABLE PATTERNS
    // ═══════════════════════════════════════════════════════════════════════
    // Look for patterns like "Symbol 3OAK 4OAK 5OAK" or "Zeus 0.60× 2.00×"
    final paytablePatterns = [
      // "Zeus 0.60× 2.00× 6.00×" pattern
      RegExp(r'^([A-Z][a-zA-Z]+)\s+[\d.]+[×x]\s+[\d.]+[×x]\s+[\d.]+[×x]', multiLine: true),
      // "High Symbols: Zeus, Poseidon, Hades"
      RegExp(r'High\s*Symbols?[:\s]+([A-Za-z,\s]+)', caseSensitive: false),
      // "Medium Symbols: Trident, Helmet"
      RegExp(r'Medium\s*Symbols?[:\s]+([A-Za-z,\s]+)', caseSensitive: false),
      // "Low Symbols: Vase, Laurel"
      RegExp(r'Low\s*Symbols?[:\s]+([A-Za-z,\s]+)', caseSensitive: false),
    ];

    // Extract custom symbol names from "High Symbols: ..." patterns
    for (final pattern in paytablePatterns.skip(1)) {
      final match = pattern.firstMatch(text);
      if (match != null && match.groupCount >= 1) {
        final symbolsText = match.group(1) ?? '';
        final symbolNames = symbolsText.split(RegExp(r'[,\s]+'))
            .where((s) => s.isNotEmpty && s.length > 1)
            .toList();

        for (final name in symbolNames) {
          final cleanName = name.trim();
          if (cleanName.isEmpty) continue;

          // Determine tier from pattern
          final tier = pattern.pattern.contains('High') ? SymbolTier.high
              : pattern.pattern.contains('Medium') ? SymbolTier.mid
              : SymbolTier.low;

          // Add if not already present
          if (!symbols.any((s) => s.id.toLowerCase() == cleanName.toLowerCase())) {
            symbols.add(GddSymbol(
              id: cleanName.toUpperCase(),
              name: cleanName[0].toUpperCase() + cleanName.substring(1).toLowerCase(),
              tier: tier,
              payouts: _defaultPayoutsForTier(tier),
            ));
          }
        }
      }
    }

    // Extract from paytable rows with payout values
    final paytableRowPattern = RegExp(
      r'^([A-Z][a-zA-Z\s]+?)\s+([\d.]+)[×x]\s+([\d.]+)[×x]\s+([\d.]+)[×x]',
      multiLine: true,
    );
    for (final match in paytableRowPattern.allMatches(text)) {
      final name = match.group(1)?.trim() ?? '';
      final pay3 = double.tryParse(match.group(2) ?? '') ?? 0;
      final pay4 = double.tryParse(match.group(3) ?? '') ?? 0;
      final pay5 = double.tryParse(match.group(4) ?? '') ?? 0;

      if (name.isEmpty || name.length < 2) continue;

      // Skip if already exists
      if (symbols.any((s) => s.id.toLowerCase() == name.toLowerCase())) continue;

      // Determine tier based on payout values
      final tier = pay5 >= 10 ? SymbolTier.premium
          : pay5 >= 4 ? SymbolTier.high
          : pay5 >= 2 ? SymbolTier.mid
          : SymbolTier.low;

      final isWild = name.toLowerCase().contains('wild');
      final isScatter = name.toLowerCase().contains('scatter');
      final isBonus = name.toLowerCase().contains('bonus') || name.toLowerCase().contains('orb');

      symbols.add(GddSymbol(
        id: name.toUpperCase().replaceAll(' ', '_'),
        name: name,
        tier: isWild ? SymbolTier.wild : isScatter ? SymbolTier.scatter : isBonus ? SymbolTier.bonus : tier,
        payouts: {3: pay3, 4: pay4, 5: pay5},
        isWild: isWild,
        isScatter: isScatter,
        isBonus: isBonus,
      ));
    }

    // If no symbols found, add defaults
    if (symbols.isEmpty) {
      warnings.add('No symbols found in text. Added default symbol set.');
      symbols.addAll([
        const GddSymbol(id: '10', name: 'Ten', tier: SymbolTier.low, payouts: {3: 0.5, 4: 1, 5: 2}),
        const GddSymbol(id: 'J', name: 'Jack', tier: SymbolTier.low, payouts: {3: 0.5, 4: 1.5, 5: 2.5}),
        const GddSymbol(id: 'Q', name: 'Queen', tier: SymbolTier.mid, payouts: {3: 1, 4: 2, 5: 4}),
        const GddSymbol(id: 'K', name: 'King', tier: SymbolTier.mid, payouts: {3: 1, 4: 2.5, 5: 5}),
        const GddSymbol(id: 'A', name: 'Ace', tier: SymbolTier.high, payouts: {3: 1.5, 4: 3, 5: 7.5}),
        const GddSymbol(id: 'WILD', name: 'Wild', tier: SymbolTier.wild, payouts: {3: 5, 4: 15, 5: 50}, isWild: true),
        const GddSymbol(id: 'SCATTER', name: 'Scatter', tier: SymbolTier.scatter, payouts: {3: 2, 4: 10, 5: 50}, isScatter: true),
      ]);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXTRACT FEATURES
    // ═══════════════════════════════════════════════════════════════════════
    final features = <GddFeature>[];

    // Feature patterns
    final featurePatterns = {
      'free spin': GddFeatureType.freeSpins,
      'freespin': GddFeatureType.freeSpins,
      'bonus game': GddFeatureType.bonus,
      'bonus round': GddFeatureType.bonus,
      'pick': GddFeatureType.bonus,
      'hold and spin': GddFeatureType.holdAndSpin,
      'hold & spin': GddFeatureType.holdAndSpin,
      'respin': GddFeatureType.holdAndSpin,
      'cascade': GddFeatureType.cascade,
      'tumble': GddFeatureType.cascade,
      'avalanche': GddFeatureType.cascade,
      'gamble': GddFeatureType.gamble,
      'double up': GddFeatureType.gamble,
      'jackpot': GddFeatureType.jackpot,
      'progressive': GddFeatureType.jackpot,
      'multiplier': GddFeatureType.multiplier,
      'expanding wild': GddFeatureType.expanding,
      'sticky wild': GddFeatureType.sticky,
      'random wild': GddFeatureType.random,
    };

    for (final entry in featurePatterns.entries) {
      if (textLower.contains(entry.key)) {
        // Avoid duplicate feature types
        if (!features.any((f) => f.type == entry.value)) {
          features.add(GddFeature(
            id: entry.value.name,
            name: entry.value.label,
            type: entry.value,
            triggerCondition: _inferTriggerCondition(entry.value, text),
            initialSpins: entry.value == GddFeatureType.freeSpins ? _extractFreeSpinCount(text) : null,
          ));
        }
      }
    }

    // If no features found, add default
    if (features.isEmpty) {
      warnings.add('No features found in text. Added default Free Spins feature.');
      features.add(const GddFeature(
        id: 'freespins',
        name: 'Free Spins',
        type: GddFeatureType.freeSpins,
        triggerCondition: '3+ scatter',
        initialSpins: 10,
      ));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXTRACT WIN TIERS
    // ═══════════════════════════════════════════════════════════════════════
    final winTiers = <GddWinTier>[];

    // Look for win tier mentions
    final tierKeywords = {
      'small win': (0.5, 5.0),
      'medium win': (5.0, 15.0),
      'big win': (15.0, 30.0),
      'mega win': (30.0, 60.0),
      'epic win': (60.0, 100.0),
      'ultra win': (100.0, 500.0),
    };

    for (final entry in tierKeywords.entries) {
      if (textLower.contains(entry.key)) {
        final (min, max) = entry.value;
        winTiers.add(GddWinTier(
          id: entry.key.replaceAll(' ', '_'),
          name: entry.key.split(' ').map((w) => w[0].toUpperCase() + w.substring(1)).join(' '),
          minMultiplier: min,
          maxMultiplier: max,
        ));
      }
    }

    // Add default tiers if none found
    if (winTiers.isEmpty) {
      winTiers.addAll(const [
        GddWinTier(id: 'small', name: 'Small Win', minMultiplier: 0.5, maxMultiplier: 5),
        GddWinTier(id: 'big', name: 'Big Win', minMultiplier: 5, maxMultiplier: 15),
        GddWinTier(id: 'mega', name: 'Mega Win', minMultiplier: 15, maxMultiplier: 30),
        GddWinTier(id: 'epic', name: 'Epic Win', minMultiplier: 30, maxMultiplier: 100),
      ]);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BUILD GDD
    // ═══════════════════════════════════════════════════════════════════════
    final gdd = GameDesignDocument(
      name: gameName,
      version: '1.0',
      description: 'Imported from PDF text',
      grid: GddGridConfig(
        rows: rows,
        columns: reels,
        mechanic: mechanic,
        paylines: paylines,
        ways: ways,
      ),
      math: GddMathModel(
        rtp: rtp,
        volatility: volatility,
        hitFrequency: hitFrequency,
        winTiers: winTiers,
      ),
      symbols: symbols,
      features: features,
    );

    final stages = _generateStages(gdd);
    final symbolDefs = generateSymbolDefinitions(gdd);
    final validationWarnings = _validateGdd(gdd);
    warnings.addAll(validationWarnings);

    debugPrint('[GddImportService] Text parse complete:');
    debugPrint('  - Name: $gameName');
    debugPrint('  - Grid: ${reels}x$rows ($mechanic)');
    debugPrint('  - RTP: ${(rtp * 100).toStringAsFixed(2)}%');
    debugPrint('  - Symbols: ${symbols.length}');
    debugPrint('  - Features: ${features.length}');
    debugPrint('  - Stages: ${stages.length}');

    return GddImportResult(
      gdd: gdd,
      generatedStages: stages,
      generatedSymbols: symbolDefs,
      warnings: warnings,
    );
  }

  /// Default payouts based on symbol tier
  Map<int, double> _defaultPayoutsForTier(SymbolTier tier) {
    return switch (tier) {
      SymbolTier.low => {3: 0.5, 4: 1.0, 5: 2.0},
      SymbolTier.mid => {3: 1.0, 4: 2.0, 5: 4.0},
      SymbolTier.high => {3: 1.5, 4: 3.0, 5: 7.5},
      SymbolTier.premium => {3: 2.0, 4: 5.0, 5: 15.0},
      SymbolTier.wild => {3: 5.0, 4: 15.0, 5: 50.0},
      SymbolTier.scatter => {3: 2.0, 4: 10.0, 5: 50.0},
      SymbolTier.bonus => {3: 0.0, 4: 0.0, 5: 0.0},
      SymbolTier.special => {3: 3.0, 4: 10.0, 5: 25.0},
    };
  }

  /// Infer trigger condition from feature type and text
  String? _inferTriggerCondition(GddFeatureType type, String text) {
    final textLower = text.toLowerCase();

    switch (type) {
      case GddFeatureType.freeSpins:
        if (textLower.contains('3 scatter')) return '3+ scatter';
        if (textLower.contains('bonus symbol')) return '3+ bonus symbols';
        return '3+ scatter';
      case GddFeatureType.bonus:
        if (textLower.contains('3 bonus')) return '3+ bonus symbols';
        return '3+ bonus symbols';
      case GddFeatureType.holdAndSpin:
        if (textLower.contains('6 coin')) return '6+ coins';
        return '6+ special symbols';
      case GddFeatureType.jackpot:
        if (textLower.contains('15 coin')) return '15 coins';
        return 'Fill grid';
      default:
        return null;
    }
  }

  /// Extract free spin count from text
  int? _extractFreeSpinCount(String text) {
    final patterns = [
      RegExp(r'(\d+)\s*free\s*spins?', caseSensitive: false),
      RegExp(r'award[s]?\s*(\d+)\s*spins?', caseSensitive: false),
      RegExp(r'(\d+)\s*spins?\s*awarded', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final val = int.tryParse(match.group(1) ?? '');
        if (val != null && val >= 3 && val <= 100) {
          return val;
        }
      }
    }

    return 10; // Default
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

    // Win tiers (legacy per-GDD)
    for (final tier in gdd.math.winTiers) {
      final stageName = 'WIN_${tier.id.toUpperCase()}';
      stages.add(stageName);
    }

    // Win tier templates (P0 WF-02: Auto-generation)
    stages.addAll(generateWinTierStages());

    // Symbol lands by tier (legacy, kept for backward compat)
    for (final tier in SymbolTier.values) {
      if (gdd.symbols.any((s) => s.tier == tier)) {
        stages.add('SYMBOL_LAND_${tier.name.toUpperCase()}');
      }
    }

    // Per-symbol stages (P0 WF-01: Auto-generation)
    stages.addAll(generateSymbolStages(gdd.symbols));

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

    // Special types first
    if (gddSymbol.isWild) return '🌟';
    if (gddSymbol.isScatter) return '💠';
    if (gddSymbol.isBonus) return '🎁';

    // Playing card symbols
    if (idLower == '10' || nameLower.contains('ten')) return '🔟';
    if (idLower == 'j' || nameLower.contains('jack')) return '🃏';
    if (idLower == 'q' || nameLower.contains('queen')) return '👸';
    if (idLower == 'k' || nameLower.contains('king')) return '🤴';
    if (idLower == 'a' || nameLower.contains('ace')) return '🅰️';

    // Greek mythology
    if (nameLower.contains('zeus')) return '⚡';
    if (nameLower.contains('poseidon')) return '🔱';
    if (nameLower.contains('hades')) return '💀';
    if (nameLower.contains('athena')) return '🦉';
    if (nameLower.contains('apollo')) return '☀️';
    if (nameLower.contains('hermes')) return '👟';
    if (nameLower.contains('ares')) return '⚔️';
    if (nameLower.contains('trident')) return '🔱';
    if (nameLower.contains('helmet')) return '⛑️';
    if (nameLower.contains('shield')) return '🛡️';
    if (nameLower.contains('lyre')) return '🎸';
    if (nameLower.contains('vase') || nameLower.contains('amphora')) return '🏺';
    if (nameLower.contains('laurel')) return '🌿';
    if (nameLower.contains('orb')) return '🔮';
    if (nameLower.contains('lightning')) return '⚡';
    if (nameLower.contains('emblem')) return '🏛️';

    // Egyptian
    if (nameLower.contains('pharaoh')) return '👑';
    if (nameLower.contains('cleopatra')) return '👸';
    if (nameLower.contains('anubis')) return '🐺';
    if (nameLower.contains('ra') || nameLower == 'sun') return '☀️';
    if (nameLower.contains('horus')) return '🦅';
    if (nameLower.contains('scarab')) return '🪲';
    if (nameLower.contains('eye')) return '👁️';
    if (nameLower.contains('ankh')) return '☥';
    if (nameLower.contains('pyramid')) return '🔺';

    // Asian
    if (nameLower.contains('dragon')) return '🐉';
    if (nameLower.contains('phoenix')) return '🦅';
    if (nameLower.contains('tiger')) return '🐅';
    if (nameLower.contains('turtle')) return '🐢';
    if (nameLower.contains('koi')) return '🐟';
    if (nameLower.contains('lantern')) return '🏮';
    if (nameLower.contains('fan')) return '🪭';

    // Irish/Celtic
    if (nameLower.contains('leprechaun')) return '🧙';
    if (nameLower.contains('pot')) return '🪙';
    if (nameLower.contains('rainbow')) return '🌈';
    if (nameLower.contains('clover') || nameLower.contains('shamrock')) return '🍀';
    if (nameLower.contains('horseshoe')) return '🧲';

    // Norse
    if (nameLower.contains('odin')) return '👁️';
    if (nameLower.contains('thor')) return '🔨';
    if (nameLower.contains('freya')) return '💕';
    if (nameLower.contains('loki')) return '🎭';
    if (nameLower.contains('mjolnir')) return '🔨';
    if (nameLower.contains('raven')) return '🐦‍⬛';
    if (nameLower.contains('rune')) return '🔮';

    // Adventure
    if (nameLower.contains('explorer')) return '🧭';
    if (nameLower.contains('treasure')) return '💰';
    if (nameLower.contains('map')) return '🗺️';
    if (nameLower.contains('compass')) return '🧭';
    if (nameLower.contains('chest')) return '📦';

    // Animals
    if (nameLower.contains('lion')) return '🦁';
    if (nameLower.contains('eagle')) return '🦅';
    if (nameLower.contains('wolf')) return '🐺';
    if (nameLower.contains('bear')) return '🐻';
    if (nameLower.contains('buffalo')) return '🦬';

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

  /// Generate per-symbol audio stage events (P0 WF-01)
  ///
  /// For each symbol in GDD, generates:
  /// - SYMBOL_LAND_{SYMBOL_ID}
  /// - WIN_SYMBOL_HIGHLIGHT_{SYMBOL_ID}
  /// - SYMBOL_EXPAND_{SYMBOL_ID} (if Wild)
  /// - SYMBOL_LOCK_{SYMBOL_ID} (if Hold & Win)
  ///
  /// Returns list of stage names to register in StageConfigurationService
  List<String> generateSymbolStages(List<GddSymbol> symbols) {
    final stages = <String>[];

    for (final symbol in symbols) {
      final symbolId = symbol.id.toUpperCase();

      // Core stages (all symbols)
      stages.add('SYMBOL_LAND_$symbolId');
      stages.add('WIN_SYMBOL_HIGHLIGHT_$symbolId');

      // Wild-specific stages
      if (symbol.isWild) {
        stages.add('WILD_EXPAND_$symbolId');
        stages.add('WILD_SUBSTITUTE_$symbolId');
        stages.add('WILD_STICKY_$symbolId');
      }

      // Scatter-specific stages
      if (symbol.isScatter) {
        stages.add('SCATTER_COLLECT_$symbolId');
        stages.add('SCATTER_TRIGGER_$symbolId');
      }

      // Bonus-specific stages
      if (symbol.isBonus) {
        stages.add('BONUS_COLLECT_$symbolId');
        stages.add('BONUS_TRIGGER_$symbolId');
      }
    }

    return stages;
  }

  /// Generate win tier audio stage events (P0 WF-02)
  ///
  /// For standard win tiers, generates:
  /// - WIN_PRESENT_{TIER} (Small/Big/Super/Mega/Epic/Ultra)
  /// - WIN_LINE_SHOW_{TIER}
  /// - ROLLUP_START_{TIER}
  /// - ROLLUP_TICK_{TIER}
  /// - ROLLUP_END_{TIER}
  ///
  /// Returns list of stage names to register
  List<String> generateWinTierStages() {
    final tiers = ['SMALL', 'BIG', 'SUPER', 'MEGA', 'EPIC', 'ULTRA'];
    final stages = <String>[];

    for (final tier in tiers) {
      stages.add('WIN_PRESENT_$tier');
      stages.add('WIN_LINE_SHOW_$tier');
      stages.add('ROLLUP_START_$tier');
      stages.add('ROLLUP_TICK_$tier');
      stages.add('ROLLUP_END_$tier');
    }

    return stages;
  }
}
