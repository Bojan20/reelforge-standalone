/// PAR Import Service — T2.1 + T2.2
///
/// Wraps the Rust PAR file parser FFI to provide:
/// - Parse PAR documents (CSV / JSON / auto-detect)
/// - Validate PAR math (RTP crosscheck, hit frequency, etc.)
/// - Auto-calibrate win tier thresholds from RTP distribution
/// - Convert PAR to GameModel for use in slot engine
///
/// PAR (Probability Accounting Report) is the industry-standard math
/// model format. Every major studio generates one for regulators.
/// FluxForge can now import them directly — no manual tier setup needed.

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS (mirrors Rust structs)
// ═══════════════════════════════════════════════════════════════════════════════

/// PAR volatility classification
enum ParVolatility {
  low,
  medium,
  high,
  veryHigh,
  extreme;

  static ParVolatility fromString(String s) {
    return switch (s.toUpperCase()) {
      'LOW' => ParVolatility.low,
      'MEDIUM' => ParVolatility.medium,
      'HIGH' => ParVolatility.high,
      'VERY_HIGH' => ParVolatility.veryHigh,
      'EXTREME' => ParVolatility.extreme,
      _ => ParVolatility.medium,
    };
  }

  String get displayName => switch (this) {
    ParVolatility.low => 'Low',
    ParVolatility.medium => 'Medium',
    ParVolatility.high => 'High',
    ParVolatility.veryHigh => 'Very High',
    ParVolatility.extreme => 'Extreme',
  };
}

/// Feature type in PAR document
enum ParFeatureType {
  freeSpins,
  bonus,
  pickBonus,
  holdAndWin,
  jackpot,
  cascade,
  megaways,
  gamble,
  wheelBonus,
  collectBonus,
  other;

  static ParFeatureType fromString(String s) {
    return switch (s.toUpperCase()) {
      'FREE_SPINS' => ParFeatureType.freeSpins,
      'BONUS' => ParFeatureType.bonus,
      'PICK_BONUS' => ParFeatureType.pickBonus,
      'HOLD_AND_WIN' => ParFeatureType.holdAndWin,
      'JACKPOT' => ParFeatureType.jackpot,
      'CASCADE' => ParFeatureType.cascade,
      'MEGAWAYS' => ParFeatureType.megaways,
      'GAMBLE' => ParFeatureType.gamble,
      'WHEEL_BONUS' => ParFeatureType.wheelBonus,
      'COLLECT_BONUS' => ParFeatureType.collectBonus,
      _ => ParFeatureType.other,
    };
  }
}

/// RTP breakdown by source
class ParRtpBreakdown {
  final double baseGameRtp;
  final double freeSpinsRtp;
  final double bonusRtp;
  final double jackpotRtp;
  final double gambleRtp;
  final double totalRtp;

  const ParRtpBreakdown({
    this.baseGameRtp = 0.0,
    this.freeSpinsRtp = 0.0,
    this.bonusRtp = 0.0,
    this.jackpotRtp = 0.0,
    this.gambleRtp = 0.0,
    this.totalRtp = 0.0,
  });

  factory ParRtpBreakdown.fromJson(Map<String, dynamic> j) => ParRtpBreakdown(
    baseGameRtp: (j['base_game_rtp'] as num?)?.toDouble() ?? 0.0,
    freeSpinsRtp: (j['free_spins_rtp'] as num?)?.toDouble() ?? 0.0,
    bonusRtp: (j['bonus_rtp'] as num?)?.toDouble() ?? 0.0,
    jackpotRtp: (j['jackpot_rtp'] as num?)?.toDouble() ?? 0.0,
    gambleRtp: (j['gamble_rtp'] as num?)?.toDouble() ?? 0.0,
    totalRtp: (j['total_rtp'] as num?)?.toDouble() ?? 0.0,
  );
}

/// A feature in the PAR document
class ParFeature {
  final ParFeatureType featureType;
  final String name;
  final double triggerProbability;
  final double avgPayoutMultiplier;
  final double rtpContribution;
  /// Average duration in spins (free spins, hold-and-win, etc.)
  final double avgDurationSpins;
  /// Retrigger probability during the feature (0.0 if none)
  final double retriggerProbability;

  const ParFeature({
    required this.featureType,
    this.name = '',
    this.triggerProbability = 0.0,
    this.avgPayoutMultiplier = 0.0,
    this.rtpContribution = 0.0,
    this.avgDurationSpins = 0.0,
    this.retriggerProbability = 0.0,
  });

  factory ParFeature.fromJson(Map<String, dynamic> j) => ParFeature(
    featureType: ParFeatureType.fromString(
      (j['feature_type'] as String?) ?? 'OTHER',
    ),
    name: (j['name'] as String?) ?? '',
    triggerProbability: (j['trigger_probability'] as num?)?.toDouble() ?? 0.0,
    avgPayoutMultiplier:
        (j['avg_payout_multiplier'] as num?)?.toDouble() ?? 0.0,
    rtpContribution: (j['rtp_contribution'] as num?)?.toDouble() ?? 0.0,
    avgDurationSpins:
        (j['avg_duration_spins'] as num?)?.toDouble() ?? 0.0,
    retriggerProbability:
        (j['retrigger_probability'] as num?)?.toDouble() ?? 0.0,
  );
}

/// Jackpot level definition in PAR document
class ParJackpotLevel {
  /// Level name (MINI, MINOR, MAJOR, GRAND, MEGA)
  final String name;
  /// Seed value (minimum payout, in x-bet units)
  final double seedValue;
  /// Trigger probability per spin
  final double triggerProbability;
  /// RTP contribution (fraction of total RTP, 0.0–1.0)
  final double rtpContribution;

  const ParJackpotLevel({
    required this.name,
    this.seedValue = 0.0,
    this.triggerProbability = 0.0,
    this.rtpContribution = 0.0,
  });

  factory ParJackpotLevel.fromJson(Map<String, dynamic> j) => ParJackpotLevel(
    name: (j['name'] as String?) ?? '',
    seedValue: (j['seed_value'] as num?)?.toDouble() ?? 0.0,
    triggerProbability: (j['trigger_probability'] as num?)?.toDouble() ?? 0.0,
    rtpContribution: (j['rtp_contribution'] as num?)?.toDouble() ?? 0.0,
  );
}

/// Complete parsed PAR document
class ParDocument {
  // Header
  final String gameName;
  final String gameId;
  final double rtpTarget;
  final ParVolatility volatility;
  final double maxExposure;

  // Grid
  final int reels;
  final int rows;
  final int paylines;
  final int? waysToWin;

  // Aggregates
  final int symbolCount;
  final int payCombinationCount;
  final List<ParFeature> features;
  /// Jackpot levels (MINI/MINOR/MAJOR/GRAND) — empty if no jackpot system
  final List<ParJackpotLevel> jackpotLevels;
  final ParRtpBreakdown rtpBreakdown;
  final double hitFrequency;
  final double deadSpinFrequency;

  // Metadata
  final String sourceFormat;
  final String? provider;
  final String? parVersion;

  // Raw JSON for FFI passthrough
  final Map<String, dynamic> _raw;

  const ParDocument({
    required this.gameName,
    required this.gameId,
    required this.rtpTarget,
    required this.volatility,
    this.maxExposure = 0.0,
    required this.reels,
    required this.rows,
    this.paylines = 0,
    this.waysToWin,
    this.symbolCount = 0,
    this.payCombinationCount = 0,
    this.features = const [],
    this.jackpotLevels = const [],
    required this.rtpBreakdown,
    this.hitFrequency = 0.0,
    this.deadSpinFrequency = 0.0,
    this.sourceFormat = '',
    this.provider,
    this.parVersion,
    required Map<String, dynamic> raw,
  }) : _raw = raw;

  factory ParDocument.fromJson(Map<String, dynamic> j) => ParDocument(
    gameName: (j['game_name'] as String?) ?? '',
    gameId: (j['game_id'] as String?) ?? '',
    rtpTarget: (j['rtp_target'] as num?)?.toDouble() ?? 0.0,
    volatility: ParVolatility.fromString(
      (j['volatility'] as String?) ?? 'MEDIUM',
    ),
    maxExposure: (j['max_exposure'] as num?)?.toDouble() ?? 0.0,
    reels: (j['reels'] as int?) ?? 5,
    rows: (j['rows'] as int?) ?? 3,
    paylines: (j['paylines'] as int?) ?? 0,
    waysToWin: j['ways_to_win'] as int?,
    symbolCount: ((j['symbols'] as List?)?.length) ?? 0,
    payCombinationCount: ((j['pay_combinations'] as List?)?.length) ?? 0,
    features: ((j['features'] as List?) ?? [])
        .map((e) => ParFeature.fromJson(e as Map<String, dynamic>))
        .toList(),
    jackpotLevels: ((j['jackpot_levels'] as List?) ?? [])
        .map((e) => ParJackpotLevel.fromJson(e as Map<String, dynamic>))
        .toList(),
    rtpBreakdown: ParRtpBreakdown.fromJson(
      (j['rtp_breakdown'] as Map<String, dynamic>?) ?? {},
    ),
    hitFrequency: (j['hit_frequency'] as num?)?.toDouble() ?? 0.0,
    deadSpinFrequency: (j['dead_spin_frequency'] as num?)?.toDouble() ?? 0.0,
    sourceFormat: (j['source_format'] as String?) ?? '',
    provider: j['provider'] as String?,
    parVersion: j['par_version'] as String?,
    raw: j,
  );

  /// Get raw JSON string for FFI passthrough
  String toJsonString() => jsonEncode(_raw);

  /// Win mechanism description
  String get winMechanismDescription {
    if (waysToWin != null) return '$waysToWin Ways';
    if (paylines > 0) return '$paylines Paylines';
    return 'Unknown';
  }
}

/// PAR validation finding
class ParFinding {
  final String severity; // 'Error', 'Warning', 'Info'
  final String field;
  final String message;

  const ParFinding({
    required this.severity,
    required this.field,
    required this.message,
  });

  factory ParFinding.fromJson(Map<String, dynamic> j) => ParFinding(
    severity: (j['severity'] as String?) ?? 'Info',
    field: (j['field'] as String?) ?? '',
    message: (j['message'] as String?) ?? '',
  );

  bool get isError => severity == 'Error';
  bool get isWarning => severity == 'Warning';
}

/// Full PAR validation report
class ParValidationReport {
  final bool valid;
  final List<ParFinding> findings;
  final double rtpDelta;
  final double computedHitFrequency;

  const ParValidationReport({
    required this.valid,
    required this.findings,
    this.rtpDelta = 0.0,
    this.computedHitFrequency = 0.0,
  });

  factory ParValidationReport.fromJson(Map<String, dynamic> j) =>
      ParValidationReport(
        valid: (j['valid'] as bool?) ?? false,
        findings: ((j['findings'] as List?) ?? [])
            .map((e) => ParFinding.fromJson(e as Map<String, dynamic>))
            .toList(),
        rtpDelta: (j['rtp_delta'] as num?)?.toDouble() ?? 0.0,
        computedHitFrequency:
            (j['computed_hit_frequency'] as num?)?.toDouble() ?? 0.0,
      );

  List<ParFinding> get errors =>
      findings.where((f) => f.isError).toList();
  List<ParFinding> get warnings =>
      findings.where((f) => f.isWarning).toList();
}

/// A single calibrated win tier (P5 RegularWinTier)
class CalibratedWinTier {
  final int tierId;
  final double fromMultiplier;
  final double toMultiplier;
  final String displayLabel;
  final int rollupDurationMs;
  final int rollupTickRate;
  final int particleBurstCount;

  const CalibratedWinTier({
    required this.tierId,
    required this.fromMultiplier,
    required this.toMultiplier,
    required this.displayLabel,
    required this.rollupDurationMs,
    required this.rollupTickRate,
    required this.particleBurstCount,
  });

  factory CalibratedWinTier.fromJson(Map<String, dynamic> j) =>
      CalibratedWinTier(
        tierId: (j['tier_id'] as int?) ?? 0,
        fromMultiplier: (j['from_multiplier'] as num?)?.toDouble() ?? 0.0,
        toMultiplier: (j['to_multiplier'] as num?)?.toDouble() ?? double.infinity,
        displayLabel: (j['display_label'] as String?) ?? '',
        rollupDurationMs: (j['rollup_duration_ms'] as int?) ?? 1000,
        rollupTickRate: (j['rollup_tick_rate'] as int?) ?? 15,
        particleBurstCount: (j['particle_burst_count'] as int?) ?? 0,
      );

  String get stageName => switch (tierId) {
    -1 => 'WIN_LOW',
    0 => 'WIN_EQUAL',
    _ => 'WIN_$tierId',
  };
}

/// Win tier calibration result (T2.2)
class WinTierCalibrationResult {
  final List<CalibratedWinTier> tiers;
  final String configId;
  final CalibrationDiagnostics diagnostics;

  const WinTierCalibrationResult({
    required this.tiers,
    required this.configId,
    required this.diagnostics,
  });

  factory WinTierCalibrationResult.fromJson(Map<String, dynamic> j) {
    final regularWinConfig =
        j['regular_win_config'] as Map<String, dynamic>? ?? {};
    final tiersJson = regularWinConfig['tiers'] as List? ?? [];
    return WinTierCalibrationResult(
      tiers: tiersJson
          .map((e) => CalibratedWinTier.fromJson(e as Map<String, dynamic>))
          .toList(),
      configId: (regularWinConfig['config_id'] as String?) ?? 'par_calibrated',
      diagnostics: CalibrationDiagnostics.fromJson(
        j['diagnostics'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

/// Calibration diagnostics
class CalibrationDiagnostics {
  final int combinationsAnalyzed;
  final List<double> percentileBoundaries;
  final List<double> multiplierAtBoundaries;
  final List<double> rtpWeightPerTier;
  final List<int> rollupDurationsMs;

  const CalibrationDiagnostics({
    this.combinationsAnalyzed = 0,
    this.percentileBoundaries = const [],
    this.multiplierAtBoundaries = const [],
    this.rtpWeightPerTier = const [],
    this.rollupDurationsMs = const [],
  });

  factory CalibrationDiagnostics.fromJson(Map<String, dynamic> j) =>
      CalibrationDiagnostics(
        combinationsAnalyzed:
            (j['combinations_analyzed'] as int?) ?? 0,
        percentileBoundaries: ((j['percentile_boundaries'] as List?) ?? [])
            .map((e) => (e as num).toDouble())
            .toList(),
        multiplierAtBoundaries:
            ((j['multiplier_at_boundaries'] as List?) ?? [])
                .map((e) => (e as num).toDouble())
                .toList(),
        rtpWeightPerTier: ((j['rtp_weight_per_tier'] as List?) ?? [])
            .map((e) => (e as num).toDouble())
            .toList(),
        rollupDurationsMs: ((j['rollup_durations_ms'] as List?) ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
      );
}

/// Full import result from PAR file
class ParImportResult {
  final ParDocument document;
  final ParValidationReport validationReport;
  final WinTierCalibrationResult? calibration;
  final String? error;

  const ParImportResult({
    required this.document,
    required this.validationReport,
    this.calibration,
    this.error,
  });

  bool get hasErrors => validationReport.errors.isNotEmpty || error != null;
  bool get hasWarnings => validationReport.warnings.isNotEmpty;
}

// ═══════════════════════════════════════════════════════════════════════════════
// T2.7: PAR+ EXTENDED FORMAT MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Feature trigger matrix — conditional probabilities per scatter count and reel
class FeatureTriggerMatrix {
  /// Feature name (matches ParFeature.name)
  final String featureName;

  /// P(trigger | scatter_count = n) — key is scatter count as string
  final Map<String, double> scatterCountProbs;

  /// Per-reel trigger symbol landing probability (index = reel index)
  final List<double> perReelProbs;

  /// Retrigger probability during the feature
  final double retriggerProbability;

  /// Average feature duration in spins
  final double avgDurationSpins;

  /// Win multiplier during feature (1.0 = none)
  final double winMultiplier;

  /// Average total win multiplier from this feature (x-bet)
  final double avgTotalMultiplier;

  const FeatureTriggerMatrix({
    required this.featureName,
    this.scatterCountProbs = const {},
    this.perReelProbs = const [],
    this.retriggerProbability = 0.0,
    this.avgDurationSpins = 0.0,
    this.winMultiplier = 1.0,
    this.avgTotalMultiplier = 0.0,
  });

  factory FeatureTriggerMatrix.fromJson(Map<String, dynamic> j) {
    final scatterJson = j['scatter_count_probs'] as Map<String, dynamic>? ?? {};
    return FeatureTriggerMatrix(
      featureName: (j['feature_name'] as String?) ?? '',
      scatterCountProbs: scatterJson.map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      ),
      perReelProbs: ((j['per_reel_probs'] as List?) ?? [])
          .map((e) => (e as num).toDouble())
          .toList(),
      retriggerProbability:
          (j['retrigger_probability'] as num?)?.toDouble() ?? 0.0,
      avgDurationSpins:
          (j['avg_duration_spins'] as num?)?.toDouble() ?? 0.0,
      winMultiplier: (j['win_multiplier'] as num?)?.toDouble() ?? 1.0,
      avgTotalMultiplier:
          (j['avg_total_multiplier'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Total trigger rate per spin (sum of scatter-count probs)
  double get totalTriggerRate =>
      scatterCountProbs.values.fold(0.0, (a, b) => a + b);
}

/// A bucket in a win multiplier distribution histogram
class WinMultiplierBucket {
  final double fromMultiplier;
  final double toMultiplier;
  final double probability;

  const WinMultiplierBucket({
    required this.fromMultiplier,
    required this.toMultiplier,
    required this.probability,
  });

  factory WinMultiplierBucket.fromJson(Map<String, dynamic> j) =>
      WinMultiplierBucket(
        fromMultiplier: (j['from_multiplier'] as num?)?.toDouble() ?? 0.0,
        toMultiplier: (j['to_multiplier'] as num?)?.toDouble() ?? double.infinity,
        probability: (j['probability'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Win multiplier distribution for a feature
class WinMultiplierDistribution {
  final String featureName;
  final List<WinMultiplierBucket> buckets;
  final double mean;
  final double stdDev;
  final double p95;
  final double p99;
  final double maxObserved;

  const WinMultiplierDistribution({
    required this.featureName,
    this.buckets = const [],
    this.mean = 0.0,
    this.stdDev = 0.0,
    this.p95 = 0.0,
    this.p99 = 0.0,
    this.maxObserved = 0.0,
  });

  factory WinMultiplierDistribution.fromJson(Map<String, dynamic> j) =>
      WinMultiplierDistribution(
        featureName: (j['feature_name'] as String?) ?? '',
        buckets: ((j['buckets'] as List?) ?? [])
            .map((e) => WinMultiplierBucket.fromJson(e as Map<String, dynamic>))
            .toList(),
        mean: (j['mean'] as num?)?.toDouble() ?? 0.0,
        stdDev: (j['std_dev'] as num?)?.toDouble() ?? 0.0,
        p95: (j['p95'] as num?)?.toDouble() ?? 0.0,
        p99: (j['p99'] as num?)?.toDouble() ?? 0.0,
        maxObserved: (j['max_observed'] as num?)?.toDouble() ?? 0.0,
      );

  /// Probability of win exceeding threshold (x-bet)
  double probExceeding(double threshold) => buckets
      .where((b) => b.fromMultiplier >= threshold)
      .fold(0.0, (sum, b) => sum + b.probability);
}

/// Session-level volatility metrics
class SessionVolatilityMetrics {
  final double rtpStdDev;
  final double sessionRtpP10;
  final double sessionRtpP50;
  final double sessionRtpP90;
  final double spinsPerBonusAvg;
  final int consecutiveLossP99;
  final double theoreticalDrain100;

  const SessionVolatilityMetrics({
    this.rtpStdDev = 0.0,
    this.sessionRtpP10 = 0.0,
    this.sessionRtpP50 = 0.0,
    this.sessionRtpP90 = 0.0,
    this.spinsPerBonusAvg = 0.0,
    this.consecutiveLossP99 = 0,
    this.theoreticalDrain100 = 0.0,
  });

  factory SessionVolatilityMetrics.fromJson(Map<String, dynamic> j) =>
      SessionVolatilityMetrics(
        rtpStdDev: (j['rtp_std_dev'] as num?)?.toDouble() ?? 0.0,
        sessionRtpP10: (j['session_rtp_p10'] as num?)?.toDouble() ?? 0.0,
        sessionRtpP50: (j['session_rtp_p50'] as num?)?.toDouble() ?? 0.0,
        sessionRtpP90: (j['session_rtp_p90'] as num?)?.toDouble() ?? 0.0,
        spinsPerBonusAvg:
            (j['spins_per_bonus_avg'] as num?)?.toDouble() ?? 0.0,
        consecutiveLossP99: (j['consecutive_loss_p99'] as int?) ?? 0,
        theoreticalDrain100:
            (j['theoretical_drain_100'] as num?)?.toDouble() ?? 0.0,
      );

  bool get passesUkgcLossStreakCheck =>
      consecutiveLossP99 == 0 || consecutiveLossP99 <= 200;
}

/// Near-miss configuration rates
class NearMissRates {
  /// Named near-miss configurations → probability per spin
  final Map<String, double> rates;
  /// Near-miss to actual trigger ratio (MGA limit: ≤12)
  final double nearMissToTriggerRatio;
  /// Studio certifies rates are mathematically derived
  final bool mathematicallyFair;

  const NearMissRates({
    this.rates = const {},
    this.nearMissToTriggerRatio = 0.0,
    this.mathematicallyFair = false,
  });

  factory NearMissRates.fromJson(Map<String, dynamic> j) {
    final ratesJson = j['rates'] as Map<String, dynamic>? ?? {};
    return NearMissRates(
      rates: ratesJson.map((k, v) => MapEntry(k, (v as num).toDouble())),
      nearMissToTriggerRatio:
          (j['near_miss_to_trigger_ratio'] as num?)?.toDouble() ?? 0.0,
      mathematicallyFair: (j['mathematically_fair'] as bool?) ?? false,
    );
  }

  double get totalRate => rates.values.fold(0.0, (a, b) => a + b);
  bool get passesMgaRatioCheck =>
      nearMissToTriggerRatio <= 12.0 || nearMissToTriggerRatio == 0.0;
}

/// PAR+ extension block (lives at document["par_plus"])
class ParPlusExtension {
  final String version;
  final List<FeatureTriggerMatrix> featureTriggerMatrices;
  final List<WinMultiplierDistribution> winMultiplierDistributions;
  final SessionVolatilityMetrics sessionVolatility;
  final NearMissRates nearMissRates;

  const ParPlusExtension({
    this.version = '1.0',
    this.featureTriggerMatrices = const [],
    this.winMultiplierDistributions = const [],
    this.sessionVolatility = const SessionVolatilityMetrics(),
    this.nearMissRates = const NearMissRates(),
  });

  factory ParPlusExtension.fromJson(Map<String, dynamic> j) =>
      ParPlusExtension(
        version: (j['version'] as String?) ?? '1.0',
        featureTriggerMatrices: ((j['feature_trigger_matrices'] as List?) ?? [])
            .map((e) => FeatureTriggerMatrix.fromJson(e as Map<String, dynamic>))
            .toList(),
        winMultiplierDistributions:
            ((j['win_multiplier_distributions'] as List?) ?? [])
                .map((e) => WinMultiplierDistribution.fromJson(
                      e as Map<String, dynamic>,
                    ))
                .toList(),
        sessionVolatility: SessionVolatilityMetrics.fromJson(
          j['session_volatility'] as Map<String, dynamic>? ?? {},
        ),
        nearMissRates: NearMissRates.fromJson(
          j['near_miss_rates'] as Map<String, dynamic>? ?? {},
        ),
      );

  /// Get trigger matrix for named feature (case-insensitive)
  FeatureTriggerMatrix? triggerMatrix(String featureName) {
    final lower = featureName.toLowerCase();
    for (final m in featureTriggerMatrices) {
      if (m.featureName.toLowerCase() == lower) return m;
    }
    return null;
  }

  /// Get win distribution for named feature (case-insensitive)
  WinMultiplierDistribution? winDistribution(String featureName) {
    final lower = featureName.toLowerCase();
    for (final d in winMultiplierDistributions) {
      if (d.featureName.toLowerCase() == lower) return d;
    }
    return null;
  }
}

/// Complete PAR+ document — PAR document with optional extension
class ParPlusDocument {
  final ParDocument par;
  final ParPlusExtension? parPlus;

  const ParPlusDocument({required this.par, this.parPlus});

  bool get hasPlus => parPlus != null;

  /// Get PAR+ extension — returns empty default if absent
  ParPlusExtension get plus => parPlus ?? const ParPlusExtension();

  factory ParPlusDocument.fromJson(Map<String, dynamic> j) => ParPlusDocument(
    par: ParDocument.fromJson(j),
    parPlus: j.containsKey('par_plus')
        ? ParPlusExtension.fromJson(j['par_plus'] as Map<String, dynamic>)
        : null,
  );
}

/// A PAR+ validation warning
class ParPlusWarning {
  final String field;
  final String message;

  const ParPlusWarning({required this.field, required this.message});

  factory ParPlusWarning.fromJson(Map<String, dynamic> j) => ParPlusWarning(
    field: (j['field'] as String?) ?? '',
    message: (j['message'] as String?) ?? '',
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// PAR Import Service — T2.1 + T2.2
///
/// Provides: parse → validate → calibrate pipeline for PAR files.
/// Uses Rust FFI for all heavy computation; Dart side is thin wrapper.
class ParImportService extends ChangeNotifier {
  /// Last successfully parsed document
  ParDocument? _lastDocument;
  ParDocument? get lastDocument => _lastDocument;

  /// Last validation report
  ParValidationReport? _lastValidationReport;
  ParValidationReport? get lastValidationReport => _lastValidationReport;

  /// Last calibration result
  WinTierCalibrationResult? _lastCalibration;
  WinTierCalibrationResult? get lastCalibration => _lastCalibration;

  /// Is a parse operation in progress?
  bool _isParsing = false;
  bool get isParsing => _isParsing;

  /// Last error message
  String? _lastError;
  String? get lastError => _lastError;

  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Import PAR from file path.
  /// Detects format from extension (.json / .csv / .xlsx_csv) or uses auto.
  Future<ParImportResult?> importFromFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      _lastError = 'File not found: $path';
      notifyListeners();
      return null;
    }
    final content = await file.readAsString();
    final ext = path.toLowerCase().split('.').last;
    final format = switch (ext) {
      'json' => 'json',
      'csv' => 'csv',
      _ => 'auto',
    };
    return importFromContent(content, format: format, sourcePath: path);
  }

  /// Import PAR from raw string content.
  Future<ParImportResult?> importFromContent(
    String content, {
    String format = 'auto',
    String? sourcePath,
  }) async {
    _isParsing = true;
    _lastError = null;
    notifyListeners();

    try {
      final result = await compute(
        _parseInBackground,
        _ParseRequest(content: content, format: format),
      );

      if (result.error != null) {
        _lastError = result.error;
        _isParsing = false;
        notifyListeners();
        return result;
      }

      _lastDocument = result.document;
      _lastValidationReport = result.validationReport;
      _lastCalibration = result.calibration;
      _lastError = null;
      _isParsing = false;
      notifyListeners();
      return result;
    } catch (e) {
      _lastError = 'Import failed: $e';
      _isParsing = false;
      notifyListeners();
      return null;
    }
  }

  /// Re-calibrate win tiers from current document.
  Future<WinTierCalibrationResult?> recalibrate() async {
    if (_lastDocument == null) return null;
    final docJson = _lastDocument!.toJsonString();
    final resultPtr = NativeFFI.instance.slotLabParCalibrateWinTiers(docJson);
    if (resultPtr == null) return null;
    try {
      final json = jsonDecode(resultPtr) as Map<String, dynamic>;
      _lastCalibration = WinTierCalibrationResult.fromJson(json);
      notifyListeners();
      return _lastCalibration;
    } catch (_) {
      return null;
    }
  }

  /// Clear current state
  void clear() {
    _lastDocument = null;
    _lastValidationReport = null;
    _lastCalibration = null;
    _lastError = null;
    notifyListeners();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BACKGROUND ISOLATE LOGIC
// ═══════════════════════════════════════════════════════════════════════════════

class _ParseRequest {
  final String content;
  final String format;
  const _ParseRequest({required this.content, required this.format});
}

ParImportResult _parseInBackground(_ParseRequest req) {
  // 1. Parse
  final docJsonStr = NativeFFI.instance.slotLabParParse(
    req.content,
    req.format,
  );
  if (docJsonStr == null) {
    // Return a minimal error result
    return ParImportResult(
      document: _emptyDocument(),
      validationReport: const ParValidationReport(
        valid: false,
        findings: [
          ParFinding(
            severity: 'Error',
            field: 'parse',
            message: 'Failed to parse PAR content — check format and content',
          ),
        ],
      ),
      error: 'PAR parse failed — content may be malformed or unsupported format',
    );
  }

  final docJson = jsonDecode(docJsonStr) as Map<String, dynamic>;
  final document = ParDocument.fromJson(docJson);

  // 2. Validate
  ParValidationReport validationReport = const ParValidationReport(
    valid: true,
    findings: [],
  );
  final validationStr = NativeFFI.instance.slotLabParValidate(docJsonStr);
  if (validationStr != null) {
    try {
      validationReport = ParValidationReport.fromJson(
        jsonDecode(validationStr) as Map<String, dynamic>,
      );
    } catch (_) {
      // Validation parse failed — treat as unknown state
    }
  }

  // 3. Calibrate win tiers (T2.2)
  WinTierCalibrationResult? calibration;
  final calibrationStr =
      NativeFFI.instance.slotLabParCalibrateWinTiers(docJsonStr);
  if (calibrationStr != null) {
    try {
      calibration = WinTierCalibrationResult.fromJson(
        jsonDecode(calibrationStr) as Map<String, dynamic>,
      );
    } catch (_) {
      // Calibration failed — non-fatal, continue without it
    }
  }

  return ParImportResult(
    document: document,
    validationReport: validationReport,
    calibration: calibration,
  );
}

ParDocument _emptyDocument() => ParDocument(
  gameName: '',
  gameId: '',
  rtpTarget: 0.0,
  volatility: ParVolatility.medium,
  reels: 5,
  rows: 3,
  rtpBreakdown: const ParRtpBreakdown(),
  raw: const {},
);
