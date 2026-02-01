/// Win Tier Configuration System (P5)
///
/// Fleksibilan, data-driven sistem za definisanje win tier-ova u slot igrama.
/// Umesto hardkodiranih naziva koristi se numerička nomenklatura sa
/// konfigurisanim opsezima.
///
/// ## Tier System
///
/// **Regular Wins (< 20x bet):**
/// - WIN_LOW: < 1x bet (sub-bet win)
/// - WIN_EQUAL: = 1x bet (push)
/// - WIN_1 through WIN_5: 1x to 13x+ bet (WIN_5 is default for >13x)
///
/// **Big Wins (20x+ bet):**
/// - Single BIG_WIN with 5 internal tiers
/// - Configurable escalation through tiers
///
/// Spec: .claude/specs/WIN_TIER_SYSTEM_SPEC.md

import 'dart:convert';
import 'dart:ui' show Color;

// ============================================================================
// P5 ENUMS
// ============================================================================

/// Source of win tier configuration
enum WinTierConfigSource {
  builtin,    // Factory default
  gddImport,  // Imported from GDD
  manual,     // Manually configured
  custom,     // Custom preset
}

// ============================================================================
// P5 REGULAR WIN TIERS (< 20x bet)
// ============================================================================

/// Definition of a single regular win tier (P5 system)
class WinTierDefinition {
  /// Tier ID (-1=LOW, 0=EQUAL, 1-5=regular tiers)
  final int tierId;

  /// Stage name generated from ID: "WIN_LOW", "WIN_EQUAL", "WIN_1", etc.
  String get stageName {
    if (tierId == -1) return 'WIN_LOW';
    if (tierId == 0) return 'WIN_EQUAL';
    return 'WIN_$tierId';
  }

  /// Win present stage name
  String get presentStageName {
    if (tierId == -1) return 'WIN_PRESENT_LOW';
    if (tierId == 0) return 'WIN_PRESENT_EQUAL';
    return 'WIN_PRESENT_$tierId';
  }

  /// Rollup stage names (null for WIN_LOW which is instant)
  String? get rollupStartStageName =>
      tierId == -1 ? null : 'ROLLUP_START_${tierId == 0 ? 'EQUAL' : tierId}';
  String? get rollupTickStageName =>
      tierId == -1 ? null : 'ROLLUP_TICK_${tierId == 0 ? 'EQUAL' : tierId}';
  String? get rollupEndStageName =>
      tierId == -1 ? null : 'ROLLUP_END_${tierId == 0 ? 'EQUAL' : tierId}';

  /// Multiplier range: from X times bet TO Y times bet
  /// fromMultiplier is inclusive, toMultiplier is exclusive (except last tier = infinity)
  final double fromMultiplier;
  final double toMultiplier;

  /// Display label shown in win plaque (fully user-editable)
  final String displayLabel;

  /// Rollup duration in milliseconds (0 for instant)
  final int rollupDurationMs;

  /// Rollup tick rate (ticks per second)
  final int rollupTickRate;

  /// Optional: Custom color for this tier's plaque
  final Color? plaqueColor;

  /// Particle burst count for celebration effects
  final int particleBurstCount;

  const WinTierDefinition({
    required this.tierId,
    required this.fromMultiplier,
    required this.toMultiplier,
    required this.displayLabel,
    required this.rollupDurationMs,
    required this.rollupTickRate,
    this.plaqueColor,
    this.particleBurstCount = 0,
  });

  /// Check if win amount falls into this tier
  bool matches(double winAmount, double betAmount) {
    if (betAmount <= 0) return false;
    final multiplier = winAmount / betAmount;
    return multiplier >= fromMultiplier && multiplier < toMultiplier;
  }

  /// Create copy with updated values
  WinTierDefinition copyWith({
    int? tierId,
    double? fromMultiplier,
    double? toMultiplier,
    String? displayLabel,
    int? rollupDurationMs,
    int? rollupTickRate,
    Color? plaqueColor,
    int? particleBurstCount,
  }) {
    return WinTierDefinition(
      tierId: tierId ?? this.tierId,
      fromMultiplier: fromMultiplier ?? this.fromMultiplier,
      toMultiplier: toMultiplier ?? this.toMultiplier,
      displayLabel: displayLabel ?? this.displayLabel,
      rollupDurationMs: rollupDurationMs ?? this.rollupDurationMs,
      rollupTickRate: rollupTickRate ?? this.rollupTickRate,
      plaqueColor: plaqueColor ?? this.plaqueColor,
      particleBurstCount: particleBurstCount ?? this.particleBurstCount,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
    'tierId': tierId,
    'fromMultiplier': fromMultiplier,
    'toMultiplier': toMultiplier,
    'displayLabel': displayLabel,
    'rollupDurationMs': rollupDurationMs,
    'rollupTickRate': rollupTickRate,
    if (plaqueColor != null) 'plaqueColor': plaqueColor!.value,
    'particleBurstCount': particleBurstCount,
  };

  /// Deserialize from JSON
  factory WinTierDefinition.fromJson(Map<String, dynamic> json) {
    return WinTierDefinition(
      tierId: json['tierId'] as int,
      fromMultiplier: (json['fromMultiplier'] as num).toDouble(),
      toMultiplier: (json['toMultiplier'] as num).toDouble(),
      displayLabel: json['displayLabel'] as String? ?? '',
      rollupDurationMs: json['rollupDurationMs'] as int? ?? 1000,
      rollupTickRate: json['rollupTickRate'] as int? ?? 15,
      plaqueColor: json['plaqueColor'] != null
          ? Color(json['plaqueColor'] as int)
          : null,
      particleBurstCount: json['particleBurstCount'] as int? ?? 0,
    );
  }
}

/// Configuration for all regular win tiers (P5 system)
class RegularWinTierConfig {
  /// Config ID (e.g., "default", "high_volatility", "gdd_imported")
  final String configId;

  /// Display name for this config
  final String name;

  /// List of tier definitions (ordered by fromMultiplier)
  final List<WinTierDefinition> tiers;

  /// Source of this config
  final WinTierConfigSource source;

  const RegularWinTierConfig({
    required this.configId,
    required this.name,
    required this.tiers,
    required this.source,
  });

  /// Get tier for given win/bet amounts
  WinTierDefinition? getTierForWin(double winAmount, double betAmount) {
    for (final tier in tiers) {
      if (tier.matches(winAmount, betAmount)) {
        return tier;
      }
    }
    return null; // No win or below minimum threshold
  }

  /// Validate config (no gaps, no overlaps)
  bool validate() {
    if (tiers.isEmpty) return false;

    // Sort by fromMultiplier
    final sorted = [...tiers]..sort(
      (a, b) => a.fromMultiplier.compareTo(b.fromMultiplier)
    );

    // Check continuity (no gaps, no overlaps)
    for (int i = 0; i < sorted.length - 1; i++) {
      // Allow small epsilon for floating point comparison
      final gap = (sorted[i].toMultiplier - sorted[i + 1].fromMultiplier).abs();
      if (gap > 0.001) {
        return false; // Gap or overlap detected
      }
    }

    return true;
  }

  /// Get validation errors (if any)
  List<String> getValidationErrors() {
    final errors = <String>[];

    if (tiers.isEmpty) {
      errors.add('At least one tier is required');
      return errors;
    }

    final sorted = [...tiers]..sort(
      (a, b) => a.fromMultiplier.compareTo(b.fromMultiplier)
    );

    for (int i = 0; i < sorted.length - 1; i++) {
      final current = sorted[i];
      final next = sorted[i + 1];

      if (current.toMultiplier < next.fromMultiplier) {
        errors.add(
          'Gap detected between ${current.stageName} '
          '(ends at ${current.toMultiplier}x) and ${next.stageName} '
          '(starts at ${next.fromMultiplier}x)'
        );
      } else if (current.toMultiplier > next.fromMultiplier) {
        errors.add(
          'Overlap detected between ${current.stageName} '
          '(ends at ${current.toMultiplier}x) and ${next.stageName} '
          '(starts at ${next.fromMultiplier}x)'
        );
      }
    }

    return errors;
  }

  /// Create copy with updated values
  RegularWinTierConfig copyWith({
    String? configId,
    String? name,
    List<WinTierDefinition>? tiers,
    WinTierConfigSource? source,
  }) {
    return RegularWinTierConfig(
      configId: configId ?? this.configId,
      name: name ?? this.name,
      tiers: tiers ?? this.tiers,
      source: source ?? this.source,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
    'configId': configId,
    'name': name,
    'tiers': tiers.map((t) => t.toJson()).toList(),
    'source': source.name,
  };

  /// Deserialize from JSON
  factory RegularWinTierConfig.fromJson(Map<String, dynamic> json) {
    return RegularWinTierConfig(
      configId: json['configId'] as String? ?? 'unknown',
      name: json['name'] as String? ?? 'Unknown',
      tiers: (json['tiers'] as List<dynamic>?)
          ?.map((t) => WinTierDefinition.fromJson(t as Map<String, dynamic>))
          .toList() ?? [],
      source: WinTierConfigSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => WinTierConfigSource.custom,
      ),
    );
  }

  /// Default configuration with standard win tiers
  factory RegularWinTierConfig.defaultConfig() {
    return RegularWinTierConfig(
      configId: 'default',
      name: 'Standard',
      source: WinTierConfigSource.builtin,
      tiers: [
        // WIN_LOW: < 1x bet (sub-bet win)
        const WinTierDefinition(
          tierId: -1,
          displayLabel: '',
          fromMultiplier: 0,
          toMultiplier: 1,
          rollupDurationMs: 0, // Instant
          rollupTickRate: 0,
          particleBurstCount: 0,
        ),
        // WIN_EQUAL: = 1x bet (push)
        const WinTierDefinition(
          tierId: 0,
          displayLabel: 'PUSH',
          fromMultiplier: 1,
          toMultiplier: 1.001, // Effectively = 1x
          rollupDurationMs: 500,
          rollupTickRate: 20,
          particleBurstCount: 0,
        ),
        // WIN_1: >1x, ≤2x bet
        const WinTierDefinition(
          tierId: 1,
          displayLabel: 'WIN',
          fromMultiplier: 1.001,
          toMultiplier: 2,
          rollupDurationMs: 800,
          rollupTickRate: 18,
          particleBurstCount: 5,
        ),
        // WIN_2: >2x, ≤4x bet
        const WinTierDefinition(
          tierId: 2,
          displayLabel: 'WIN',
          fromMultiplier: 2,
          toMultiplier: 4,
          rollupDurationMs: 1000,
          rollupTickRate: 16,
          particleBurstCount: 8,
        ),
        // WIN_3: >4x, ≤8x bet
        const WinTierDefinition(
          tierId: 3,
          displayLabel: 'NICE',
          fromMultiplier: 4,
          toMultiplier: 8,
          rollupDurationMs: 1200,
          rollupTickRate: 15,
          particleBurstCount: 12,
        ),
        // WIN_4: >8x, ≤13x bet
        const WinTierDefinition(
          tierId: 4,
          displayLabel: 'NICE WIN',
          fromMultiplier: 8,
          toMultiplier: 13,
          rollupDurationMs: 1500,
          rollupTickRate: 14,
          particleBurstCount: 18,
        ),
        // WIN_5: >13x bet (default for regular wins before BIG_WIN)
        const WinTierDefinition(
          tierId: 5,
          displayLabel: 'GREAT WIN',
          fromMultiplier: 13,
          toMultiplier: 20, // up to BIG_WIN threshold
          rollupDurationMs: 2000,
          rollupTickRate: 12,
          particleBurstCount: 25,
        ),
        // WIN_6 REMOVED - WIN_5 is now default for >13x
      ],
    );
  }
}

// ============================================================================
// P5 BIG WIN SYSTEM (20x+ bet)
// ============================================================================

/// Definition of a single big win tier (internal escalation tier)
class BigWinTierDefinition {
  /// Tier ID (1-5)
  final int tierId;

  /// Stage name: "BIG_WIN_TIER_1", etc.
  String get stageName => 'BIG_WIN_TIER_$tierId';

  /// Multiplier range
  /// fromMultiplier is inclusive, toMultiplier is exclusive (Tier 5 = infinity)
  final double fromMultiplier;
  final double toMultiplier;

  /// Display label — FULLY DYNAMIC, user-editable
  /// Default: empty string (no hardcoded names like "MEGA WIN!")
  final String displayLabel;

  /// Duration in milliseconds (default 4000ms)
  final int durationMs;

  /// Rollup tick rate during this tier
  final int rollupTickRate;

  /// Visual intensity multiplier (1.0 - 2.0)
  final double visualIntensity;

  /// Particle effects multiplier
  final double particleMultiplier;

  /// Audio intensity (1.0 - 2.0) — volume/pitch scaling
  final double audioIntensity;

  const BigWinTierDefinition({
    required this.tierId,
    required this.fromMultiplier,
    required this.toMultiplier,
    this.displayLabel = '',
    this.durationMs = 4000,
    this.rollupTickRate = 10,
    this.visualIntensity = 1.0,
    this.particleMultiplier = 1.0,
    this.audioIntensity = 1.0,
  });

  /// Check if win amount falls into this tier
  bool matches(double winAmount, double betAmount) {
    if (betAmount <= 0) return false;
    final multiplier = winAmount / betAmount;
    return multiplier >= fromMultiplier && multiplier < toMultiplier;
  }

  /// Create copy with updated values
  BigWinTierDefinition copyWith({
    int? tierId,
    double? fromMultiplier,
    double? toMultiplier,
    String? displayLabel,
    int? durationMs,
    int? rollupTickRate,
    double? visualIntensity,
    double? particleMultiplier,
    double? audioIntensity,
  }) {
    return BigWinTierDefinition(
      tierId: tierId ?? this.tierId,
      fromMultiplier: fromMultiplier ?? this.fromMultiplier,
      toMultiplier: toMultiplier ?? this.toMultiplier,
      displayLabel: displayLabel ?? this.displayLabel,
      durationMs: durationMs ?? this.durationMs,
      rollupTickRate: rollupTickRate ?? this.rollupTickRate,
      visualIntensity: visualIntensity ?? this.visualIntensity,
      particleMultiplier: particleMultiplier ?? this.particleMultiplier,
      audioIntensity: audioIntensity ?? this.audioIntensity,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
    'tierId': tierId,
    'fromMultiplier': fromMultiplier,
    'toMultiplier': toMultiplier == double.infinity ? 'infinity' : toMultiplier,
    'displayLabel': displayLabel,
    'durationMs': durationMs,
    'rollupTickRate': rollupTickRate,
    'visualIntensity': visualIntensity,
    'particleMultiplier': particleMultiplier,
    'audioIntensity': audioIntensity,
  };

  /// Deserialize from JSON
  factory BigWinTierDefinition.fromJson(Map<String, dynamic> json) {
    final toMult = json['toMultiplier'];
    return BigWinTierDefinition(
      tierId: json['tierId'] as int,
      fromMultiplier: (json['fromMultiplier'] as num).toDouble(),
      toMultiplier: toMult == 'infinity'
          ? double.infinity
          : (toMult as num).toDouble(),
      displayLabel: json['displayLabel'] as String? ?? '',
      durationMs: json['durationMs'] as int? ?? 4000,
      rollupTickRate: json['rollupTickRate'] as int? ?? 10,
      visualIntensity: (json['visualIntensity'] as num?)?.toDouble() ?? 1.0,
      particleMultiplier: (json['particleMultiplier'] as num?)?.toDouble() ?? 1.0,
      audioIntensity: (json['audioIntensity'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Configuration for big win celebration system
class BigWinConfig {
  /// Big win threshold multiplier (default 20x)
  final double threshold;

  /// Intro duration (default 500ms)
  final int introDurationMs;

  /// End duration (default 4000ms)
  final int endDurationMs;

  /// Fade out duration (default 1000ms)
  final int fadeOutDurationMs;

  /// Tier definitions (ordered 1-5)
  final List<BigWinTierDefinition> tiers;

  const BigWinConfig({
    this.threshold = 20.0,
    this.introDurationMs = 500,
    this.endDurationMs = 4000,
    this.fadeOutDurationMs = 1000,
    required this.tiers,
  });

  /// Stage names for big win flow
  static const String introStageName = 'BIG_WIN_INTRO';
  static const String endStageName = 'BIG_WIN_END';
  static const String fadeOutStageName = 'BIG_WIN_FADE_OUT';
  static const String rollupTickStageName = 'BIG_WIN_ROLLUP_TICK';

  /// Check if win qualifies for Big Win
  bool isBigWin(double winAmount, double betAmount) {
    if (betAmount <= 0) return false;
    final multiplier = winAmount / betAmount;
    return multiplier >= threshold;
  }

  /// Get max tier for win amount (returns 0 if not a big win)
  int getMaxTierForWin(double winAmount, double betAmount) {
    if (!isBigWin(winAmount, betAmount)) return 0;

    final multiplier = winAmount / betAmount;

    // Find highest tier that matches
    for (int i = tiers.length - 1; i >= 0; i--) {
      if (multiplier >= tiers[i].fromMultiplier) {
        return tiers[i].tierId;
      }
    }
    return 1; // Default to tier 1 if big win but no tier matches
  }

  /// Get tier definition by ID
  BigWinTierDefinition? getTierById(int tierId) {
    return tiers.cast<BigWinTierDefinition?>().firstWhere(
      (t) => t?.tierId == tierId,
      orElse: () => null,
    );
  }

  /// Get all tiers up to and including the max tier for this win
  List<BigWinTierDefinition> getTiersForWin(double winAmount, double betAmount) {
    final maxTier = getMaxTierForWin(winAmount, betAmount);
    if (maxTier == 0) return [];
    return tiers.where((t) => t.tierId <= maxTier).toList();
  }

  /// Validate big win configuration (no gaps, no overlaps, tiers start at threshold)
  bool validate() {
    if (tiers.isEmpty) return false;
    if (threshold <= 0) return false;

    // Check that tier 1 starts at threshold
    final tier1 = tiers.firstWhere((t) => t.tierId == 1, orElse: () =>
        const BigWinTierDefinition(tierId: 0, fromMultiplier: -1, toMultiplier: -1));
    if (tier1.fromMultiplier != threshold) return false;

    // Sort by fromMultiplier
    final sorted = [...tiers]..sort(
      (a, b) => a.fromMultiplier.compareTo(b.fromMultiplier)
    );

    // Check continuity
    for (int i = 0; i < sorted.length - 1; i++) {
      final gap = (sorted[i].toMultiplier - sorted[i + 1].fromMultiplier).abs();
      if (gap > 0.001 && sorted[i].toMultiplier != double.infinity) {
        return false;
      }
    }

    return true;
  }

  /// Calculate total celebration duration for a win
  int getTotalDurationMs(double winAmount, double betAmount) {
    final tiersToPlay = getTiersForWin(winAmount, betAmount);
    if (tiersToPlay.isEmpty) return 0;

    int total = introDurationMs;
    for (final tier in tiersToPlay) {
      total += tier.durationMs;
    }
    total += endDurationMs;
    total += fadeOutDurationMs;
    return total;
  }

  /// Create copy with updated values
  BigWinConfig copyWith({
    double? threshold,
    int? introDurationMs,
    int? endDurationMs,
    int? fadeOutDurationMs,
    List<BigWinTierDefinition>? tiers,
  }) {
    return BigWinConfig(
      threshold: threshold ?? this.threshold,
      introDurationMs: introDurationMs ?? this.introDurationMs,
      endDurationMs: endDurationMs ?? this.endDurationMs,
      fadeOutDurationMs: fadeOutDurationMs ?? this.fadeOutDurationMs,
      tiers: tiers ?? this.tiers,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
    'threshold': threshold,
    'introDurationMs': introDurationMs,
    'endDurationMs': endDurationMs,
    'fadeOutDurationMs': fadeOutDurationMs,
    'tiers': tiers.map((t) => t.toJson()).toList(),
  };

  /// Deserialize from JSON
  factory BigWinConfig.fromJson(Map<String, dynamic> json) {
    return BigWinConfig(
      threshold: (json['threshold'] as num?)?.toDouble() ?? 20.0,
      introDurationMs: json['introDurationMs'] as int? ?? 500,
      endDurationMs: json['endDurationMs'] as int? ?? 4000,
      fadeOutDurationMs: json['fadeOutDurationMs'] as int? ?? 1000,
      tiers: (json['tiers'] as List<dynamic>?)
          ?.map((t) => BigWinTierDefinition.fromJson(t as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  /// Default big win configuration based on industry research
  factory BigWinConfig.defaultConfig() {
    return BigWinConfig(
      threshold: 20.0,
      introDurationMs: 500,
      endDurationMs: 4000,
      fadeOutDurationMs: 1000,
      tiers: const [
        // Tier 1: 20x - 50x (Low volatility "Big Win")
        BigWinTierDefinition(
          tierId: 1,
          fromMultiplier: 20,
          toMultiplier: 50,
          displayLabel: '', // User fills this in
          durationMs: 4000,
          rollupTickRate: 12,
          visualIntensity: 1.0,
          particleMultiplier: 1.0,
          audioIntensity: 1.0,
        ),
        // Tier 2: 50x - 100x (High volatility "Mega Win")
        BigWinTierDefinition(
          tierId: 2,
          fromMultiplier: 50,
          toMultiplier: 100,
          displayLabel: '', // User fills this in
          durationMs: 4000,
          rollupTickRate: 10,
          visualIntensity: 1.2,
          particleMultiplier: 1.5,
          audioIntensity: 1.1,
        ),
        // Tier 3: 100x - 250x (Streamer threshold)
        BigWinTierDefinition(
          tierId: 3,
          fromMultiplier: 100,
          toMultiplier: 250,
          displayLabel: '', // User fills this in
          durationMs: 4000,
          rollupTickRate: 8,
          visualIntensity: 1.4,
          particleMultiplier: 2.0,
          audioIntensity: 1.2,
        ),
        // Tier 4: 250x - 500x (Ultra-high zone)
        BigWinTierDefinition(
          tierId: 4,
          fromMultiplier: 250,
          toMultiplier: 500,
          displayLabel: '', // User fills this in
          durationMs: 4000,
          rollupTickRate: 6,
          visualIntensity: 1.6,
          particleMultiplier: 2.5,
          audioIntensity: 1.3,
        ),
        // Tier 5: 500x+ (Max win celebration)
        BigWinTierDefinition(
          tierId: 5,
          fromMultiplier: 500,
          toMultiplier: double.infinity,
          displayLabel: '', // User fills this in
          durationMs: 4000,
          rollupTickRate: 4,
          visualIntensity: 2.0,
          particleMultiplier: 3.0,
          audioIntensity: 1.5,
        ),
      ],
    );
  }
}

// ============================================================================
// P5 COMBINED CONFIGURATION
// ============================================================================

/// Combined configuration for all win tiers (regular + big win) - P5 System
class SlotWinConfiguration {
  /// Regular win tier configuration
  final RegularWinTierConfig regularWins;

  /// Big win configuration
  final BigWinConfig bigWins;

  const SlotWinConfiguration({
    required this.regularWins,
    required this.bigWins,
  });

  /// Get regular tier for win (returns null if big win)
  WinTierDefinition? getRegularTier(double winAmount, double betAmount) {
    if (bigWins.isBigWin(winAmount, betAmount)) return null;
    return regularWins.getTierForWin(winAmount, betAmount);
  }

  /// Check if win qualifies for big win
  bool isBigWin(double winAmount, double betAmount) {
    return bigWins.isBigWin(winAmount, betAmount);
  }

  /// Get max big win tier (0 if not a big win)
  int getBigWinMaxTier(double winAmount, double betAmount) {
    return bigWins.getMaxTierForWin(winAmount, betAmount);
  }

  /// Get all stage names for audio assignment (getter form)
  List<String> get allStageNames => getAllStageNames();

  /// Get all stage names for audio assignment
  List<String> getAllStageNames() {
    final stages = <String>[];

    // Regular win stages
    for (final tier in regularWins.tiers) {
      stages.add(tier.stageName);
      stages.add(tier.presentStageName);
      if (tier.rollupStartStageName != null) {
        stages.add(tier.rollupStartStageName!);
        stages.add(tier.rollupTickStageName!);
        stages.add(tier.rollupEndStageName!);
      }
    }

    // Big win stages
    stages.add(BigWinConfig.introStageName);
    for (final tier in bigWins.tiers) {
      stages.add(tier.stageName);
    }
    stages.add(BigWinConfig.endStageName);
    stages.add(BigWinConfig.fadeOutStageName);
    stages.add(BigWinConfig.rollupTickStageName);

    return stages;
  }

  /// Create copy with updated values
  SlotWinConfiguration copyWith({
    RegularWinTierConfig? regularWins,
    BigWinConfig? bigWins,
  }) {
    return SlotWinConfiguration(
      regularWins: regularWins ?? this.regularWins,
      bigWins: bigWins ?? this.bigWins,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
    'regularWins': regularWins.toJson(),
    'bigWins': bigWins.toJson(),
  };

  /// Deserialize from JSON
  factory SlotWinConfiguration.fromJson(Map<String, dynamic> json) {
    return SlotWinConfiguration(
      regularWins: RegularWinTierConfig.fromJson(
        json['regularWins'] as Map<String, dynamic>
      ),
      bigWins: BigWinConfig.fromJson(
        json['bigWins'] as Map<String, dynamic>
      ),
    );
  }

  /// Serialize to JSON string
  String toJsonString() => jsonEncode(toJson());

  /// Deserialize from JSON string
  factory SlotWinConfiguration.fromJsonString(String jsonString) {
    return SlotWinConfiguration.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  /// Default configuration
  factory SlotWinConfiguration.defaultConfig() {
    return SlotWinConfiguration(
      regularWins: RegularWinTierConfig.defaultConfig(),
      bigWins: BigWinConfig.defaultConfig(),
    );
  }
}

// ============================================================================
// P5 WIN CONFIGURATION PRESETS
// ============================================================================

/// Factory presets for SlotWinConfiguration (P5 system)
class SlotWinConfigurationPresets {
  SlotWinConfigurationPresets._();

  /// Standard preset - balanced for most slots
  static SlotWinConfiguration get standard {
    return SlotWinConfiguration(
      regularWins: RegularWinTierConfig(
        configId: 'standard',
        name: 'Standard',
        source: WinTierConfigSource.builtin,
        tiers: [
          const WinTierDefinition(
            tierId: -1,
            fromMultiplier: 0.0,
            toMultiplier: 1.0,
            displayLabel: 'Win',
            rollupDurationMs: 800,
            rollupTickRate: 20,
          ),
          const WinTierDefinition(
            tierId: 0,
            fromMultiplier: 1.0,
            toMultiplier: 1.001, // Small epsilon for WIN_EQUAL
            displayLabel: 'Push',
            rollupDurationMs: 1000,
            rollupTickRate: 15,
          ),
          const WinTierDefinition(
            tierId: 1,
            fromMultiplier: 1.001,
            toMultiplier: 2.0,
            displayLabel: 'Nice Win',
            rollupDurationMs: 1200,
            rollupTickRate: 15,
          ),
          const WinTierDefinition(
            tierId: 2,
            fromMultiplier: 2.0,
            toMultiplier: 5.0,
            displayLabel: 'Good Win',
            rollupDurationMs: 1500,
            rollupTickRate: 12,
          ),
          const WinTierDefinition(
            tierId: 3,
            fromMultiplier: 5.0,
            toMultiplier: 10.0,
            displayLabel: 'Great Win',
            rollupDurationMs: 2000,
            rollupTickRate: 10,
          ),
          const WinTierDefinition(
            tierId: 4,
            fromMultiplier: 10.0,
            toMultiplier: 15.0,
            displayLabel: 'Awesome Win',
            rollupDurationMs: 2500,
            rollupTickRate: 8,
          ),
          const WinTierDefinition(
            tierId: 5,
            fromMultiplier: 15.0,
            toMultiplier: 20.0,
            displayLabel: 'Amazing Win',
            rollupDurationMs: 3000,
            rollupTickRate: 8,
          ),
        ],
      ),
      bigWins: BigWinConfig.defaultConfig(),
    );
  }

  /// High volatility preset - higher thresholds, more dramatic tiers
  static SlotWinConfiguration get highVolatility {
    return SlotWinConfiguration(
      regularWins: RegularWinTierConfig(
        configId: 'high_volatility',
        name: 'High Volatility',
        source: WinTierConfigSource.builtin,
        tiers: [
          const WinTierDefinition(
            tierId: -1,
            fromMultiplier: 0.0,
            toMultiplier: 1.0,
            displayLabel: 'Win',
            rollupDurationMs: 600,
            rollupTickRate: 25,
          ),
          const WinTierDefinition(
            tierId: 1,
            fromMultiplier: 1.0,
            toMultiplier: 3.0,
            displayLabel: 'Win',
            rollupDurationMs: 1000,
            rollupTickRate: 18,
          ),
          const WinTierDefinition(
            tierId: 2,
            fromMultiplier: 3.0,
            toMultiplier: 8.0,
            displayLabel: 'Nice',
            rollupDurationMs: 1500,
            rollupTickRate: 15,
          ),
          const WinTierDefinition(
            tierId: 3,
            fromMultiplier: 8.0,
            toMultiplier: 15.0,
            displayLabel: 'Great',
            rollupDurationMs: 2000,
            rollupTickRate: 12,
          ),
          const WinTierDefinition(
            tierId: 4,
            fromMultiplier: 15.0,
            toMultiplier: 25.0,
            displayLabel: 'Super',
            rollupDurationMs: 3000,
            rollupTickRate: 10,
          ),
        ],
      ),
      bigWins: BigWinConfig(
        threshold: 25.0, // Higher threshold for high volatility
        tiers: [
          const BigWinTierDefinition(
            tierId: 1,
            fromMultiplier: 25.0,
            toMultiplier: 50.0,
            displayLabel: 'BIG WIN',
            durationMs: 5000,
            rollupTickRate: 10,
          ),
          const BigWinTierDefinition(
            tierId: 2,
            fromMultiplier: 50.0,
            toMultiplier: 100.0,
            displayLabel: 'HUGE WIN',
            durationMs: 8000,
            rollupTickRate: 8,
          ),
          const BigWinTierDefinition(
            tierId: 3,
            fromMultiplier: 100.0,
            toMultiplier: 200.0,
            displayLabel: 'MASSIVE WIN',
            durationMs: 12000,
            rollupTickRate: 6,
          ),
          const BigWinTierDefinition(
            tierId: 4,
            fromMultiplier: 200.0,
            toMultiplier: 500.0,
            displayLabel: 'INSANE WIN',
            durationMs: 18000,
            rollupTickRate: 5,
          ),
          const BigWinTierDefinition(
            tierId: 5,
            fromMultiplier: 500.0,
            toMultiplier: double.infinity,
            displayLabel: 'LEGENDARY WIN',
            durationMs: 25000,
            rollupTickRate: 4,
          ),
        ],
      ),
    );
  }

  /// Jackpot-focused preset - emphasis on big wins
  static SlotWinConfiguration get jackpotFocus {
    return SlotWinConfiguration(
      regularWins: RegularWinTierConfig(
        configId: 'jackpot',
        name: 'Jackpot Focus',
        source: WinTierConfigSource.builtin,
        tiers: [
          const WinTierDefinition(
            tierId: -1,
            fromMultiplier: 0.0,
            toMultiplier: 1.0,
            displayLabel: 'Win',
            rollupDurationMs: 500,
            rollupTickRate: 30,
          ),
          const WinTierDefinition(
            tierId: 1,
            fromMultiplier: 1.0,
            toMultiplier: 5.0,
            displayLabel: 'Win',
            rollupDurationMs: 800,
            rollupTickRate: 20,
          ),
          const WinTierDefinition(
            tierId: 2,
            fromMultiplier: 5.0,
            toMultiplier: 15.0,
            displayLabel: 'Nice',
            rollupDurationMs: 1200,
            rollupTickRate: 15,
          ),
        ],
      ),
      bigWins: BigWinConfig(
        threshold: 15.0, // Lower threshold to trigger big wins more often
        tiers: [
          const BigWinTierDefinition(
            tierId: 1,
            fromMultiplier: 15.0,
            toMultiplier: 30.0,
            displayLabel: 'BIG WIN',
            durationMs: 4000,
            rollupTickRate: 12,
          ),
          const BigWinTierDefinition(
            tierId: 2,
            fromMultiplier: 30.0,
            toMultiplier: 60.0,
            displayLabel: 'SUPER WIN',
            durationMs: 6000,
            rollupTickRate: 10,
          ),
          const BigWinTierDefinition(
            tierId: 3,
            fromMultiplier: 60.0,
            toMultiplier: 150.0,
            displayLabel: 'MEGA WIN',
            durationMs: 10000,
            rollupTickRate: 8,
          ),
          const BigWinTierDefinition(
            tierId: 4,
            fromMultiplier: 150.0,
            toMultiplier: 500.0,
            displayLabel: 'EPIC WIN',
            durationMs: 15000,
            rollupTickRate: 6,
          ),
          const BigWinTierDefinition(
            tierId: 5,
            fromMultiplier: 500.0,
            toMultiplier: double.infinity,
            displayLabel: 'JACKPOT',
            durationMs: 25000,
            rollupTickRate: 4,
          ),
        ],
      ),
    );
  }

  /// Mobile optimized preset - faster celebrations
  static SlotWinConfiguration get mobileOptimized {
    return SlotWinConfiguration(
      regularWins: RegularWinTierConfig(
        configId: 'mobile',
        name: 'Mobile Optimized',
        source: WinTierConfigSource.builtin,
        tiers: [
          const WinTierDefinition(
            tierId: -1,
            fromMultiplier: 0.0,
            toMultiplier: 1.0,
            displayLabel: 'Win',
            rollupDurationMs: 400,
            rollupTickRate: 30,
          ),
          const WinTierDefinition(
            tierId: 1,
            fromMultiplier: 1.0,
            toMultiplier: 3.0,
            displayLabel: 'Win',
            rollupDurationMs: 600,
            rollupTickRate: 25,
          ),
          const WinTierDefinition(
            tierId: 2,
            fromMultiplier: 3.0,
            toMultiplier: 8.0,
            displayLabel: 'Nice',
            rollupDurationMs: 900,
            rollupTickRate: 20,
          ),
          const WinTierDefinition(
            tierId: 3,
            fromMultiplier: 8.0,
            toMultiplier: 20.0,
            displayLabel: 'Great',
            rollupDurationMs: 1200,
            rollupTickRate: 15,
          ),
        ],
      ),
      bigWins: BigWinConfig(
        threshold: 20.0,
        tiers: [
          const BigWinTierDefinition(
            tierId: 1,
            fromMultiplier: 20.0,
            toMultiplier: 40.0,
            displayLabel: 'BIG WIN',
            durationMs: 2500,
            rollupTickRate: 15,
          ),
          const BigWinTierDefinition(
            tierId: 2,
            fromMultiplier: 40.0,
            toMultiplier: 80.0,
            displayLabel: 'SUPER WIN',
            durationMs: 4000,
            rollupTickRate: 12,
          ),
          const BigWinTierDefinition(
            tierId: 3,
            fromMultiplier: 80.0,
            toMultiplier: 150.0,
            displayLabel: 'MEGA WIN',
            durationMs: 6000,
            rollupTickRate: 10,
          ),
          const BigWinTierDefinition(
            tierId: 4,
            fromMultiplier: 150.0,
            toMultiplier: 300.0,
            displayLabel: 'EPIC WIN',
            durationMs: 8000,
            rollupTickRate: 8,
          ),
          const BigWinTierDefinition(
            tierId: 5,
            fromMultiplier: 300.0,
            toMultiplier: double.infinity,
            displayLabel: 'ULTRA WIN',
            durationMs: 12000,
            rollupTickRate: 6,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// P5 WIN TIER RESULT
// ============================================================================

/// Result of win tier evaluation (used by provider)
class WinTierResult {
  /// Whether this is a big win (20x+ by default)
  final bool isBigWin;

  /// Win multiplier (win / bet)
  final double multiplier;

  /// Regular tier definition (null if big win)
  final WinTierDefinition? regularTier;

  /// Big win tier definition (null if regular win)
  final BigWinTierDefinition? bigWinTier;

  /// Max big win tier reached (1-5, null if regular win)
  final int? bigWinMaxTier;

  const WinTierResult({
    required this.isBigWin,
    required this.multiplier,
    this.regularTier,
    this.bigWinTier,
    this.bigWinMaxTier,
  });

  /// Get primary stage name to trigger
  String get primaryStageName {
    if (isBigWin) {
      return BigWinConfig.introStageName;
    }
    return regularTier?.stageName ?? 'WIN_1';
  }

  /// Get display label (user-configurable)
  String get displayLabel {
    if (isBigWin && bigWinTier != null) {
      return bigWinTier!.displayLabel;
    }
    return regularTier?.displayLabel ?? '';
  }

  /// Get rollup duration in ms
  int get rollupDurationMs {
    if (isBigWin && bigWinTier != null) {
      return bigWinTier!.durationMs;
    }
    return regularTier?.rollupDurationMs ?? 1000;
  }

  @override
  String toString() {
    if (isBigWin) {
      return 'WinTierResult(BIG_WIN, tier=$bigWinMaxTier, ${multiplier.toStringAsFixed(1)}x)';
    }
    return 'WinTierResult(${regularTier?.stageName}, ${multiplier.toStringAsFixed(1)}x)';
  }
}

// ============================================================================
// P5 LEGACY STAGE MAPPING (Backward Compatibility)
// ============================================================================

/// Maps old hardcoded stage names to new tier-based names
const legacyStageMapping = <String, String>{
  // Regular wins
  'SMALL_WIN': 'WIN_1',
  'WIN_PRESENT_SMALL': 'WIN_PRESENT_1',

  // Big wins (old names → new system)
  'BIG_WIN': 'BIG_WIN_INTRO',
  'WIN_PRESENT_BIG': 'BIG_WIN_INTRO',
  'MEGA_WIN': 'BIG_WIN_TIER_2',
  'WIN_PRESENT_MEGA': 'BIG_WIN_TIER_2',
  'EPIC_WIN': 'BIG_WIN_TIER_3',
  'WIN_PRESENT_EPIC': 'BIG_WIN_TIER_3',
  'ULTRA_WIN': 'BIG_WIN_TIER_5',
  'WIN_PRESENT_ULTRA': 'BIG_WIN_TIER_5',

  // Generic rollup (maps to WIN_1 as fallback)
  'ROLLUP_START': 'ROLLUP_START_1',
  'ROLLUP_TICK': 'ROLLUP_TICK_1',
  'ROLLUP_END': 'ROLLUP_END_1',
};

/// Get mapped stage name (or original if no mapping exists)
String getMappedStageName(String originalStage) {
  return legacyStageMapping[originalStage] ?? originalStage;
}

// ============================================================================
// LEGACY M4 SYSTEM (Backward Compatibility)
// ============================================================================

/// Standard win tier enum (M4 legacy)
enum WinTier {
  noWin,
  smallWin,
  mediumWin,
  bigWin,
  megaWin,
  epicWin,
  ultraWin,
  jackpotMini,
  jackpotMinor,
  jackpotMajor,
  jackpotGrand;

  String get displayName {
    switch (this) {
      case WinTier.noWin:
        return 'No Win';
      case WinTier.smallWin:
        return 'Small Win';
      case WinTier.mediumWin:
        return 'Medium Win';
      case WinTier.bigWin:
        return 'Big Win';
      case WinTier.megaWin:
        return 'Mega Win';
      case WinTier.epicWin:
        return 'Epic Win';
      case WinTier.ultraWin:
        return 'Ultra Win';
      case WinTier.jackpotMini:
        return 'Mini Jackpot';
      case WinTier.jackpotMinor:
        return 'Minor Jackpot';
      case WinTier.jackpotMajor:
        return 'Major Jackpot';
      case WinTier.jackpotGrand:
        return 'Grand Jackpot';
    }
  }

  /// Audio intensity level (0-10) for this tier
  int get audioIntensity {
    switch (this) {
      case WinTier.noWin:
        return 0;
      case WinTier.smallWin:
        return 2;
      case WinTier.mediumWin:
        return 4;
      case WinTier.bigWin:
        return 6;
      case WinTier.megaWin:
        return 7;
      case WinTier.epicWin:
        return 8;
      case WinTier.ultraWin:
        return 9;
      case WinTier.jackpotMini:
        return 7;
      case WinTier.jackpotMinor:
        return 8;
      case WinTier.jackpotMajor:
        return 9;
      case WinTier.jackpotGrand:
        return 10;
    }
  }
}

/// Win tier threshold definition (M4 legacy)
class WinTierThreshold {
  final WinTier tier;

  /// Minimum win in bet multiplier (e.g., 5.0 = 5x bet)
  final double minXBet;

  /// Maximum win in bet multiplier (null = unlimited)
  final double? maxXBet;

  /// RTPC value to set when this tier is reached (0.0 - 1.0)
  final double rtpcValue;

  /// Stage to trigger when this tier is reached
  final String? triggerStage;

  /// Whether this tier should trigger celebration animation
  final bool triggerCelebration;

  /// Rollup duration multiplier (1.0 = normal, 2.0 = slower for big wins)
  final double rollupDurationMultiplier;

  const WinTierThreshold({
    required this.tier,
    required this.minXBet,
    this.maxXBet,
    required this.rtpcValue,
    this.triggerStage,
    this.triggerCelebration = false,
    this.rollupDurationMultiplier = 1.0,
  });

  WinTierThreshold copyWith({
    WinTier? tier,
    double? minXBet,
    double? maxXBet,
    double? rtpcValue,
    String? triggerStage,
    bool? triggerCelebration,
    double? rollupDurationMultiplier,
  }) {
    return WinTierThreshold(
      tier: tier ?? this.tier,
      minXBet: minXBet ?? this.minXBet,
      maxXBet: maxXBet ?? this.maxXBet,
      rtpcValue: rtpcValue ?? this.rtpcValue,
      triggerStage: triggerStage ?? this.triggerStage,
      triggerCelebration: triggerCelebration ?? this.triggerCelebration,
      rollupDurationMultiplier:
          rollupDurationMultiplier ?? this.rollupDurationMultiplier,
    );
  }

  Map<String, dynamic> toJson() => {
        'tier': tier.name,
        'minXBet': minXBet,
        'maxXBet': maxXBet,
        'rtpcValue': rtpcValue,
        'triggerStage': triggerStage,
        'triggerCelebration': triggerCelebration,
        'rollupDurationMultiplier': rollupDurationMultiplier,
      };

  factory WinTierThreshold.fromJson(Map<String, dynamic> json) {
    return WinTierThreshold(
      tier: WinTier.values.firstWhere(
        (t) => t.name == json['tier'],
        orElse: () => WinTier.noWin,
      ),
      minXBet: (json['minXBet'] as num).toDouble(),
      maxXBet: (json['maxXBet'] as num?)?.toDouble(),
      rtpcValue: (json['rtpcValue'] as num).toDouble(),
      triggerStage: json['triggerStage'] as String?,
      triggerCelebration: json['triggerCelebration'] as bool? ?? false,
      rollupDurationMultiplier:
          (json['rollupDurationMultiplier'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Win tier configuration for a game (M4 legacy)
class WinTierConfig {
  final String gameId;
  final String gameName;
  final List<WinTierThreshold> tiers;

  /// RTPC parameter to bind win tier to
  final String rtpcParameterName;

  /// Default base bet for calculations
  final double defaultBaseBet;

  /// Maximum win cap (in currency, not multiplier)
  final double? maxWinCap;

  /// Whether to use linear or logarithmic RTPC scaling
  final bool useLogarithmicScaling;

  const WinTierConfig({
    required this.gameId,
    required this.gameName,
    required this.tiers,
    this.rtpcParameterName = 'winTier',
    this.defaultBaseBet = 1.0,
    this.maxWinCap,
    this.useLogarithmicScaling = true,
  });

  WinTierConfig copyWith({
    String? gameId,
    String? gameName,
    List<WinTierThreshold>? tiers,
    String? rtpcParameterName,
    double? defaultBaseBet,
    double? maxWinCap,
    bool? useLogarithmicScaling,
  }) {
    return WinTierConfig(
      gameId: gameId ?? this.gameId,
      gameName: gameName ?? this.gameName,
      tiers: tiers ?? this.tiers,
      rtpcParameterName: rtpcParameterName ?? this.rtpcParameterName,
      defaultBaseBet: defaultBaseBet ?? this.defaultBaseBet,
      maxWinCap: maxWinCap ?? this.maxWinCap,
      useLogarithmicScaling:
          useLogarithmicScaling ?? this.useLogarithmicScaling,
    );
  }

  /// Get the tier for a given win amount
  WinTierThreshold? getTierForWin(double winAmount, double betAmount) {
    if (betAmount <= 0) return null;
    final xBet = winAmount / betAmount;

    WinTierThreshold? result;
    for (final tier in tiers) {
      if (xBet >= tier.minXBet) {
        if (tier.maxXBet == null || xBet < tier.maxXBet!) {
          result = tier;
        }
      }
    }
    return result;
  }

  /// Get RTPC value for a given win amount
  double getRtpcForWin(double winAmount, double betAmount) {
    final tier = getTierForWin(winAmount, betAmount);
    return tier?.rtpcValue ?? 0.0;
  }

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'gameName': gameName,
        'tiers': tiers.map((t) => t.toJson()).toList(),
        'rtpcParameterName': rtpcParameterName,
        'defaultBaseBet': defaultBaseBet,
        'maxWinCap': maxWinCap,
        'useLogarithmicScaling': useLogarithmicScaling,
      };

  factory WinTierConfig.fromJson(Map<String, dynamic> json) {
    return WinTierConfig(
      gameId: json['gameId'] as String,
      gameName: json['gameName'] as String,
      tiers: (json['tiers'] as List<dynamic>)
          .map((t) => WinTierThreshold.fromJson(t as Map<String, dynamic>))
          .toList(),
      rtpcParameterName:
          json['rtpcParameterName'] as String? ?? 'winTier',
      defaultBaseBet: (json['defaultBaseBet'] as num?)?.toDouble() ?? 1.0,
      maxWinCap: (json['maxWinCap'] as num?)?.toDouble(),
      useLogarithmicScaling: json['useLogarithmicScaling'] as bool? ?? true,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory WinTierConfig.fromJsonString(String jsonString) {
    return WinTierConfig.fromJson(jsonDecode(jsonString));
  }
}

/// Default win tier configurations (M4 legacy)
class DefaultWinTierConfigs {
  /// Standard slot configuration (5x3 video slot)
  static WinTierConfig get standard => const WinTierConfig(
        gameId: 'standard',
        gameName: 'Standard Slot',
        tiers: [
          WinTierThreshold(
            tier: WinTier.noWin,
            minXBet: 0,
            maxXBet: 0.1,
            rtpcValue: 0.0,
          ),
          WinTierThreshold(
            tier: WinTier.smallWin,
            minXBet: 0.1,
            maxXBet: 2.0,
            rtpcValue: 0.2,
            triggerStage: 'WIN_SMALL',
          ),
          WinTierThreshold(
            tier: WinTier.mediumWin,
            minXBet: 2.0,
            maxXBet: 5.0,
            rtpcValue: 0.4,
            triggerStage: 'WIN_MEDIUM',
          ),
          WinTierThreshold(
            tier: WinTier.bigWin,
            minXBet: 5.0,
            maxXBet: 20.0,
            rtpcValue: 0.6,
            triggerStage: 'WIN_BIG',
            triggerCelebration: true,
            rollupDurationMultiplier: 1.5,
          ),
          WinTierThreshold(
            tier: WinTier.megaWin,
            minXBet: 20.0,
            maxXBet: 50.0,
            rtpcValue: 0.8,
            triggerStage: 'WIN_MEGA',
            triggerCelebration: true,
            rollupDurationMultiplier: 2.0,
          ),
          WinTierThreshold(
            tier: WinTier.epicWin,
            minXBet: 50.0,
            maxXBet: null,
            rtpcValue: 1.0,
            triggerStage: 'WIN_EPIC',
            triggerCelebration: true,
            rollupDurationMultiplier: 3.0,
          ),
        ],
      );

  /// High volatility slot configuration
  static WinTierConfig get highVolatility => const WinTierConfig(
        gameId: 'high_volatility',
        gameName: 'High Volatility Slot',
        tiers: [
          WinTierThreshold(
            tier: WinTier.noWin,
            minXBet: 0,
            maxXBet: 1.0,
            rtpcValue: 0.0,
          ),
          WinTierThreshold(
            tier: WinTier.smallWin,
            minXBet: 1.0,
            maxXBet: 5.0,
            rtpcValue: 0.15,
            triggerStage: 'WIN_SMALL',
          ),
          WinTierThreshold(
            tier: WinTier.mediumWin,
            minXBet: 5.0,
            maxXBet: 20.0,
            rtpcValue: 0.3,
            triggerStage: 'WIN_MEDIUM',
          ),
          WinTierThreshold(
            tier: WinTier.bigWin,
            minXBet: 20.0,
            maxXBet: 100.0,
            rtpcValue: 0.5,
            triggerStage: 'WIN_BIG',
            triggerCelebration: true,
            rollupDurationMultiplier: 2.0,
          ),
          WinTierThreshold(
            tier: WinTier.megaWin,
            minXBet: 100.0,
            maxXBet: 500.0,
            rtpcValue: 0.7,
            triggerStage: 'WIN_MEGA',
            triggerCelebration: true,
            rollupDurationMultiplier: 3.0,
          ),
          WinTierThreshold(
            tier: WinTier.epicWin,
            minXBet: 500.0,
            maxXBet: 1000.0,
            rtpcValue: 0.85,
            triggerStage: 'WIN_EPIC',
            triggerCelebration: true,
            rollupDurationMultiplier: 4.0,
          ),
          WinTierThreshold(
            tier: WinTier.ultraWin,
            minXBet: 1000.0,
            maxXBet: null,
            rtpcValue: 1.0,
            triggerStage: 'WIN_ULTRA',
            triggerCelebration: true,
            rollupDurationMultiplier: 5.0,
          ),
        ],
      );

  /// Jackpot slot configuration
  static WinTierConfig get jackpot => const WinTierConfig(
        gameId: 'jackpot',
        gameName: 'Jackpot Slot',
        tiers: [
          WinTierThreshold(
            tier: WinTier.noWin,
            minXBet: 0,
            maxXBet: 0.5,
            rtpcValue: 0.0,
          ),
          WinTierThreshold(
            tier: WinTier.smallWin,
            minXBet: 0.5,
            maxXBet: 3.0,
            rtpcValue: 0.15,
            triggerStage: 'WIN_SMALL',
          ),
          WinTierThreshold(
            tier: WinTier.mediumWin,
            minXBet: 3.0,
            maxXBet: 10.0,
            rtpcValue: 0.3,
            triggerStage: 'WIN_MEDIUM',
          ),
          WinTierThreshold(
            tier: WinTier.bigWin,
            minXBet: 10.0,
            maxXBet: 50.0,
            rtpcValue: 0.5,
            triggerStage: 'WIN_BIG',
            triggerCelebration: true,
          ),
          WinTierThreshold(
            tier: WinTier.jackpotMini,
            minXBet: 50.0,
            maxXBet: 200.0,
            rtpcValue: 0.7,
            triggerStage: 'JACKPOT_MINI',
            triggerCelebration: true,
            rollupDurationMultiplier: 2.0,
          ),
          WinTierThreshold(
            tier: WinTier.jackpotMinor,
            minXBet: 200.0,
            maxXBet: 1000.0,
            rtpcValue: 0.8,
            triggerStage: 'JACKPOT_MINOR',
            triggerCelebration: true,
            rollupDurationMultiplier: 3.0,
          ),
          WinTierThreshold(
            tier: WinTier.jackpotMajor,
            minXBet: 1000.0,
            maxXBet: 5000.0,
            rtpcValue: 0.9,
            triggerStage: 'JACKPOT_MAJOR',
            triggerCelebration: true,
            rollupDurationMultiplier: 4.0,
          ),
          WinTierThreshold(
            tier: WinTier.jackpotGrand,
            minXBet: 5000.0,
            maxXBet: null,
            rtpcValue: 1.0,
            triggerStage: 'JACKPOT_GRAND',
            triggerCelebration: true,
            rollupDurationMultiplier: 5.0,
          ),
        ],
      );
}
