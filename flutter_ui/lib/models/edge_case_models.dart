/// Edge Case Preset Models
///
/// Predefined game state configurations for edge case testing:
/// - Betting: min/max bet, fractional bet, zero balance
/// - Balance: negative trend, depleting, huge win streak
/// - Feature states: max multiplier, extended features, near miss
///
/// Created: 2026-01-30 (P4.14)

// Edge Case Models

// ═══════════════════════════════════════════════════════════════════════════
// EDGE CASE CATEGORY
// ═══════════════════════════════════════════════════════════════════════════

/// Category of edge case presets
enum EdgeCaseCategory {
  betting('Betting', 'Bet amount edge cases'),
  balance('Balance', 'Player balance scenarios'),
  feature('Feature', 'Game feature states'),
  stress('Stress', 'Performance stress tests'),
  audio('Audio', 'Audio-specific edge cases'),
  visual('Visual', 'Visual edge cases'),
  custom('Custom', 'User-defined presets');

  const EdgeCaseCategory(this.label, this.description);
  final String label;
  final String description;
}

// ═══════════════════════════════════════════════════════════════════════════
// EDGE CASE PRESET
// ═══════════════════════════════════════════════════════════════════════════

/// A preset configuration for testing edge cases
class EdgeCasePreset {
  final String id;
  final String name;
  final String description;
  final EdgeCaseCategory category;
  final EdgeCaseConfig config;
  final List<String> tags;
  final bool isBuiltIn;
  final DateTime? createdAt;

  const EdgeCasePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.config,
    this.tags = const [],
    this.isBuiltIn = false,
    this.createdAt,
  });

  EdgeCasePreset copyWith({
    String? id,
    String? name,
    String? description,
    EdgeCaseCategory? category,
    EdgeCaseConfig? config,
    List<String>? tags,
    bool? isBuiltIn,
    DateTime? createdAt,
  }) {
    return EdgeCasePreset(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      config: config ?? this.config,
      tags: tags ?? this.tags,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'category': category.name,
    'config': config.toJson(),
    'tags': tags,
    'isBuiltIn': isBuiltIn,
    'createdAt': createdAt?.toIso8601String(),
  };

  factory EdgeCasePreset.fromJson(Map<String, dynamic> json) {
    return EdgeCasePreset(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      category: EdgeCaseCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => EdgeCaseCategory.custom,
      ),
      config: EdgeCaseConfig.fromJson(json['config'] as Map<String, dynamic>),
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EDGE CASE CONFIG
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration values for an edge case
class EdgeCaseConfig {
  // Betting config
  final double? betAmount;
  final double? coinValue;
  final int? linesPlayed;
  final bool? maxBet;
  final bool? minBet;

  // Balance config
  final double? balance;
  final double? initialBalance;
  final bool? zeroBalance;
  final bool? lowBalance;
  final bool? negativeBalance;

  // Feature config
  final int? multiplier;
  final int? freeSpinsRemaining;
  final int? cascadeLevel;
  final bool? featureActive;
  final String? featureType;

  // Stress config
  final int? spinCount;
  final int? spinDelay;
  final bool? turboMode;
  final bool? autoPlay;

  // Audio config
  final bool? musicEnabled;
  final bool? sfxEnabled;
  final double? volume;
  final bool? mutedBuses;

  // Signal overrides (RTPC/ALE)
  final Map<String, double>? signalOverrides;

  // Forced outcome
  final String? forcedOutcome;
  final List<List<int>>? forcedGrid;

  const EdgeCaseConfig({
    this.betAmount,
    this.coinValue,
    this.linesPlayed,
    this.maxBet,
    this.minBet,
    this.balance,
    this.initialBalance,
    this.zeroBalance,
    this.lowBalance,
    this.negativeBalance,
    this.multiplier,
    this.freeSpinsRemaining,
    this.cascadeLevel,
    this.featureActive,
    this.featureType,
    this.spinCount,
    this.spinDelay,
    this.turboMode,
    this.autoPlay,
    this.musicEnabled,
    this.sfxEnabled,
    this.volume,
    this.mutedBuses,
    this.signalOverrides,
    this.forcedOutcome,
    this.forcedGrid,
  });

  EdgeCaseConfig copyWith({
    double? betAmount,
    double? coinValue,
    int? linesPlayed,
    bool? maxBet,
    bool? minBet,
    double? balance,
    double? initialBalance,
    bool? zeroBalance,
    bool? lowBalance,
    bool? negativeBalance,
    int? multiplier,
    int? freeSpinsRemaining,
    int? cascadeLevel,
    bool? featureActive,
    String? featureType,
    int? spinCount,
    int? spinDelay,
    bool? turboMode,
    bool? autoPlay,
    bool? musicEnabled,
    bool? sfxEnabled,
    double? volume,
    bool? mutedBuses,
    Map<String, double>? signalOverrides,
    String? forcedOutcome,
    List<List<int>>? forcedGrid,
  }) {
    return EdgeCaseConfig(
      betAmount: betAmount ?? this.betAmount,
      coinValue: coinValue ?? this.coinValue,
      linesPlayed: linesPlayed ?? this.linesPlayed,
      maxBet: maxBet ?? this.maxBet,
      minBet: minBet ?? this.minBet,
      balance: balance ?? this.balance,
      initialBalance: initialBalance ?? this.initialBalance,
      zeroBalance: zeroBalance ?? this.zeroBalance,
      lowBalance: lowBalance ?? this.lowBalance,
      negativeBalance: negativeBalance ?? this.negativeBalance,
      multiplier: multiplier ?? this.multiplier,
      freeSpinsRemaining: freeSpinsRemaining ?? this.freeSpinsRemaining,
      cascadeLevel: cascadeLevel ?? this.cascadeLevel,
      featureActive: featureActive ?? this.featureActive,
      featureType: featureType ?? this.featureType,
      spinCount: spinCount ?? this.spinCount,
      spinDelay: spinDelay ?? this.spinDelay,
      turboMode: turboMode ?? this.turboMode,
      autoPlay: autoPlay ?? this.autoPlay,
      musicEnabled: musicEnabled ?? this.musicEnabled,
      sfxEnabled: sfxEnabled ?? this.sfxEnabled,
      volume: volume ?? this.volume,
      mutedBuses: mutedBuses ?? this.mutedBuses,
      signalOverrides: signalOverrides ?? this.signalOverrides,
      forcedOutcome: forcedOutcome ?? this.forcedOutcome,
      forcedGrid: forcedGrid ?? this.forcedGrid,
    );
  }

  Map<String, dynamic> toJson() => {
    if (betAmount != null) 'betAmount': betAmount,
    if (coinValue != null) 'coinValue': coinValue,
    if (linesPlayed != null) 'linesPlayed': linesPlayed,
    if (maxBet != null) 'maxBet': maxBet,
    if (minBet != null) 'minBet': minBet,
    if (balance != null) 'balance': balance,
    if (initialBalance != null) 'initialBalance': initialBalance,
    if (zeroBalance != null) 'zeroBalance': zeroBalance,
    if (lowBalance != null) 'lowBalance': lowBalance,
    if (negativeBalance != null) 'negativeBalance': negativeBalance,
    if (multiplier != null) 'multiplier': multiplier,
    if (freeSpinsRemaining != null) 'freeSpinsRemaining': freeSpinsRemaining,
    if (cascadeLevel != null) 'cascadeLevel': cascadeLevel,
    if (featureActive != null) 'featureActive': featureActive,
    if (featureType != null) 'featureType': featureType,
    if (spinCount != null) 'spinCount': spinCount,
    if (spinDelay != null) 'spinDelay': spinDelay,
    if (turboMode != null) 'turboMode': turboMode,
    if (autoPlay != null) 'autoPlay': autoPlay,
    if (musicEnabled != null) 'musicEnabled': musicEnabled,
    if (sfxEnabled != null) 'sfxEnabled': sfxEnabled,
    if (volume != null) 'volume': volume,
    if (mutedBuses != null) 'mutedBuses': mutedBuses,
    if (signalOverrides != null) 'signalOverrides': signalOverrides,
    if (forcedOutcome != null) 'forcedOutcome': forcedOutcome,
    if (forcedGrid != null) 'forcedGrid': forcedGrid,
  };

  factory EdgeCaseConfig.fromJson(Map<String, dynamic> json) {
    return EdgeCaseConfig(
      betAmount: (json['betAmount'] as num?)?.toDouble(),
      coinValue: (json['coinValue'] as num?)?.toDouble(),
      linesPlayed: json['linesPlayed'] as int?,
      maxBet: json['maxBet'] as bool?,
      minBet: json['minBet'] as bool?,
      balance: (json['balance'] as num?)?.toDouble(),
      initialBalance: (json['initialBalance'] as num?)?.toDouble(),
      zeroBalance: json['zeroBalance'] as bool?,
      lowBalance: json['lowBalance'] as bool?,
      negativeBalance: json['negativeBalance'] as bool?,
      multiplier: json['multiplier'] as int?,
      freeSpinsRemaining: json['freeSpinsRemaining'] as int?,
      cascadeLevel: json['cascadeLevel'] as int?,
      featureActive: json['featureActive'] as bool?,
      featureType: json['featureType'] as String?,
      spinCount: json['spinCount'] as int?,
      spinDelay: json['spinDelay'] as int?,
      turboMode: json['turboMode'] as bool?,
      autoPlay: json['autoPlay'] as bool?,
      musicEnabled: json['musicEnabled'] as bool?,
      sfxEnabled: json['sfxEnabled'] as bool?,
      volume: (json['volume'] as num?)?.toDouble(),
      mutedBuses: json['mutedBuses'] as bool?,
      signalOverrides: (json['signalOverrides'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
      forcedOutcome: json['forcedOutcome'] as String?,
      forcedGrid: (json['forcedGrid'] as List<dynamic>?)
          ?.map((row) => (row as List<dynamic>).cast<int>().toList())
          .toList(),
    );
  }

  @override
  String toString() => 'EdgeCaseConfig(${{
    if (betAmount != null) 'bet': betAmount,
    if (balance != null) 'bal': balance,
    if (multiplier != null) 'mult': multiplier,
    if (forcedOutcome != null) 'forced': forcedOutcome,
  }})';
}

// ═══════════════════════════════════════════════════════════════════════════
// BUILT-IN PRESETS
// ═══════════════════════════════════════════════════════════════════════════

/// Factory for built-in edge case presets
class BuiltInEdgeCasePresets {
  BuiltInEdgeCasePresets._();

  /// Get all built-in presets
  static List<EdgeCasePreset> all() => [
    ...betting(),
    ...balance(),
    ...feature(),
    ...stress(),
    ...audio(),
  ];

  /// Betting edge cases
  static List<EdgeCasePreset> betting() => [
    const EdgeCasePreset(
      id: 'min_bet',
      name: 'Minimum Bet',
      description: 'Test with the smallest possible bet',
      category: EdgeCaseCategory.betting,
      config: EdgeCaseConfig(minBet: true, betAmount: 0.01),
      tags: ['bet', 'min'],
      isBuiltIn: true,
    ),
    const EdgeCasePreset(
      id: 'max_bet',
      name: 'Maximum Bet',
      description: 'Test with the largest possible bet',
      category: EdgeCaseCategory.betting,
      config: EdgeCaseConfig(maxBet: true, betAmount: 1000.0),
      tags: ['bet', 'max'],
      isBuiltIn: true,
    ),
    const EdgeCasePreset(
      id: 'fractional_bet',
      name: 'Fractional Bet',
      description: 'Test with fractional coin values',
      category: EdgeCaseCategory.betting,
      config: EdgeCaseConfig(coinValue: 0.001, betAmount: 0.123),
      tags: ['bet', 'fractional', 'decimal'],
      isBuiltIn: true,
    ),
    const EdgeCasePreset(
      id: 'single_line',
      name: 'Single Line',
      description: 'Play only one payline',
      category: EdgeCaseCategory.betting,
      config: EdgeCaseConfig(linesPlayed: 1),
      tags: ['bet', 'lines', 'single'],
      isBuiltIn: true,
    ),
  ];

  /// Balance edge cases
  static List<EdgeCasePreset> balance() => [
    const EdgeCasePreset(
      id: 'zero_balance',
      name: 'Zero Balance',
      description: 'Player has exactly 0 balance',
      category: EdgeCaseCategory.balance,
      config: EdgeCaseConfig(zeroBalance: true, balance: 0.0),
      tags: ['balance', 'zero', 'empty'],
      isBuiltIn: true,
    ),
    const EdgeCasePreset(
      id: 'low_balance',
      name: 'Low Balance',
      description: 'Balance less than one max bet',
      category: EdgeCaseCategory.balance,
      config: EdgeCaseConfig(lowBalance: true, balance: 5.0),
      tags: ['balance', 'low'],
      isBuiltIn: true,
    ),
    const EdgeCasePreset(
      id: 'exact_balance',
      name: 'Exact Balance',
      description: 'Balance exactly equals bet amount',
      category: EdgeCaseCategory.balance,
      config: EdgeCaseConfig(balance: 10.0, betAmount: 10.0),
      tags: ['balance', 'exact', 'edge'],
      isBuiltIn: true,
    ),
    const EdgeCasePreset(
      id: 'whale_balance',
      name: 'Whale Balance',
      description: 'Very large balance (high roller)',
      category: EdgeCaseCategory.balance,
      config: EdgeCaseConfig(balance: 1000000.0),
      tags: ['balance', 'high', 'whale'],
      isBuiltIn: true,
    ),
  ];

  /// Feature edge cases
  static List<EdgeCasePreset> feature() => [
    const EdgeCasePreset(
      id: 'max_multiplier',
      name: 'Max Multiplier',
      description: 'Test with maximum multiplier value',
      category: EdgeCaseCategory.feature,
      config: EdgeCaseConfig(multiplier: 100, featureActive: true),
      tags: ['feature', 'multiplier', 'max'],
      isBuiltIn: true,
    ),
    const EdgeCasePreset(
      id: 'extended_freespins',
      name: 'Extended Free Spins',
      description: 'Free spins with many remaining',
      category: EdgeCaseCategory.feature,
      config: EdgeCaseConfig(
        featureActive: true,
        featureType: 'freespins',
        freeSpinsRemaining: 100,
      ),
      tags: ['feature', 'freespins', 'extended'],
      isBuiltIn: true,
    ),
    const EdgeCasePreset(
      id: 'deep_cascade',
      name: 'Deep Cascade',
      description: 'High cascade level',
      category: EdgeCaseCategory.feature,
      config: EdgeCaseConfig(cascadeLevel: 10),
      tags: ['feature', 'cascade', 'deep'],
      isBuiltIn: true,
    ),
    const EdgeCasePreset(
      id: 'near_miss_scatter',
      name: 'Near Miss Scatter',
      description: 'Force 2 scatters (near miss)',
      category: EdgeCaseCategory.feature,
      config: EdgeCaseConfig(forcedOutcome: 'near_miss'),
      tags: ['feature', 'nearmiss', 'scatter'],
      isBuiltIn: true,
    ),
  ];

  /// Stress test presets
  static List<EdgeCasePreset> stress() => [
    const EdgeCasePreset(
      id: 'rapid_spins',
      name: 'Rapid Spins',
      description: '100 spins with no delay',
      category: EdgeCaseCategory.stress,
      config: EdgeCaseConfig(
        spinCount: 100,
        spinDelay: 0,
        turboMode: true,
        autoPlay: true,
      ),
      tags: ['stress', 'rapid', 'turbo'],
      isBuiltIn: true,
    ),
    const EdgeCasePreset(
      id: 'extended_session',
      name: 'Extended Session',
      description: '1000 spins for long session test',
      category: EdgeCaseCategory.stress,
      config: EdgeCaseConfig(
        spinCount: 1000,
        spinDelay: 100,
        autoPlay: true,
      ),
      tags: ['stress', 'long', 'session'],
      isBuiltIn: true,
    ),
  ];

  /// Audio edge cases
  static List<EdgeCasePreset> audio() => [
    const EdgeCasePreset(
      id: 'muted_all',
      name: 'All Audio Muted',
      description: 'Test with all audio muted',
      category: EdgeCaseCategory.audio,
      config: EdgeCaseConfig(
        musicEnabled: false,
        sfxEnabled: false,
        volume: 0.0,
        mutedBuses: true,
      ),
      tags: ['audio', 'mute', 'silent'],
      isBuiltIn: true,
    ),
    const EdgeCasePreset(
      id: 'music_only',
      name: 'Music Only',
      description: 'Only music, no SFX',
      category: EdgeCaseCategory.audio,
      config: EdgeCaseConfig(
        musicEnabled: true,
        sfxEnabled: false,
        volume: 1.0,
      ),
      tags: ['audio', 'music'],
      isBuiltIn: true,
    ),
    const EdgeCasePreset(
      id: 'sfx_only',
      name: 'SFX Only',
      description: 'Only SFX, no music',
      category: EdgeCaseCategory.audio,
      config: EdgeCaseConfig(
        musicEnabled: false,
        sfxEnabled: true,
        volume: 1.0,
      ),
      tags: ['audio', 'sfx'],
      isBuiltIn: true,
    ),
    const EdgeCasePreset(
      id: 'low_volume',
      name: 'Low Volume',
      description: 'Test at very low volume',
      category: EdgeCaseCategory.audio,
      config: EdgeCaseConfig(volume: 0.1),
      tags: ['audio', 'volume', 'low'],
      isBuiltIn: true,
    ),
  ];

  /// Get preset by ID
  static EdgeCasePreset? byId(String id) {
    try {
      return all().firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get presets by category
  static List<EdgeCasePreset> byCategory(EdgeCaseCategory category) {
    return all().where((p) => p.category == category).toList();
  }
}
