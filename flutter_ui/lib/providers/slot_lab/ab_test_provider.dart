/// A/B Testing Analytics Engine™ (STUB 7)
///
/// "Data-driven audio decisions, not guesswork."
///
/// Simulates A/B testing of audio packages on virtual player populations.
/// Measures behavioral metrics (session duration, re-engagement, win celebration
/// satisfaction) to determine which audio variant drives more engagement —
/// with built-in Responsible Gaming checks.
///
/// See: FLUXFORGE_SLOTLAB_ULTIMATE_ARCHITECTURE.md §STUB7
library;

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

// =============================================================================
// PLAYER ARCHETYPES
// =============================================================================

/// Player archetype for simulation — each has distinct behavioral patterns
enum PlayerArchetype {
  casual,    // Short sessions, low bets, low risk tolerance
  regular,   // Medium sessions, moderate bets, balanced
  highRoller, // Long sessions, high bets, high risk tolerance
  newPlayer,  // Very short, exploring, high churn risk
  vip,       // Extended sessions, high bets, loyalty bonuses
}

extension PlayerArchetypeX on PlayerArchetype {
  String get displayName => switch (this) {
        PlayerArchetype.casual => 'Casual',
        PlayerArchetype.regular => 'Regular',
        PlayerArchetype.highRoller => 'High Roller',
        PlayerArchetype.newPlayer => 'New Player',
        PlayerArchetype.vip => 'VIP',
      };

  /// Typical session duration in minutes
  double get avgSessionMinutes => switch (this) {
        PlayerArchetype.casual => 15.0,
        PlayerArchetype.regular => 45.0,
        PlayerArchetype.highRoller => 90.0,
        PlayerArchetype.newPlayer => 8.0,
        PlayerArchetype.vip => 120.0,
      };

  /// Average bet multiplier (1.0 = base)
  double get betMultiplier => switch (this) {
        PlayerArchetype.casual => 0.5,
        PlayerArchetype.regular => 1.0,
        PlayerArchetype.highRoller => 5.0,
        PlayerArchetype.newPlayer => 0.3,
        PlayerArchetype.vip => 8.0,
      };

  /// Sensitivity to audio stimulation (0-1)
  double get audioSensitivity => switch (this) {
        PlayerArchetype.casual => 0.7,
        PlayerArchetype.regular => 0.5,
        PlayerArchetype.highRoller => 0.3,
        PlayerArchetype.newPlayer => 0.9,
        PlayerArchetype.vip => 0.4,
      };

  /// Population weight (percentage of typical casino floor)
  double get populationWeight => switch (this) {
        PlayerArchetype.casual => 0.35,
        PlayerArchetype.regular => 0.30,
        PlayerArchetype.highRoller => 0.10,
        PlayerArchetype.newPlayer => 0.20,
        PlayerArchetype.vip => 0.05,
      };
}

// =============================================================================
// SUCCESS METRICS
// =============================================================================

/// What we're measuring in the A/B test
enum SuccessMetric {
  sessionDuration,       // How long players stay
  reEngagement,         // Probability of returning next session
  voluntaryEnd,         // Player chose to stop (vs budget/time forced)
  nearMissTolerance,    // How players react to near-miss audio
  winCelebrationScore,  // Win celebration satisfaction
  betEscalation,        // RESPONSIBLE GAMING: does audio cause bet increases?
  sessionExtension,     // RESPONSIBLE GAMING: excessive play continuation?
}

extension SuccessMetricX on SuccessMetric {
  String get displayName => switch (this) {
        SuccessMetric.sessionDuration => 'Session Duration',
        SuccessMetric.reEngagement => 'Re-engagement Rate',
        SuccessMetric.voluntaryEnd => 'Voluntary End Rate',
        SuccessMetric.nearMissTolerance => 'Near-miss Tolerance',
        SuccessMetric.winCelebrationScore => 'Win Celebration Score',
        SuccessMetric.betEscalation => 'Bet Escalation (RG)',
        SuccessMetric.sessionExtension => 'Session Extension (RG)',
      };

  bool get isResponsibleGaming => switch (this) {
        SuccessMetric.betEscalation || SuccessMetric.sessionExtension => true,
        _ => false,
      };

  /// Higher is better (true) or lower is better (false)?
  bool get higherIsBetter => switch (this) {
        SuccessMetric.sessionDuration || SuccessMetric.reEngagement || SuccessMetric.voluntaryEnd ||
        SuccessMetric.nearMissTolerance || SuccessMetric.winCelebrationScore => true,
        SuccessMetric.betEscalation || SuccessMetric.sessionExtension => false,
      };
}

// =============================================================================
// AUDIO VARIANT
// =============================================================================

/// An audio package variant for A/B testing
class AudioVariant {
  final String name;
  final String description;

  // Audio characteristics (normalized 0-1)
  final double winCelebrationIntensity;
  final double nearMissAnticipation;
  final double ambientEngagement;
  final double reelSpinExcitement;
  final double featureTriggerImpact;
  final double lossDisguiseLevel;
  final double tempoAverage;
  final double dynamicRange;

  const AudioVariant({
    required this.name,
    this.description = '',
    this.winCelebrationIntensity = 0.5,
    this.nearMissAnticipation = 0.5,
    this.ambientEngagement = 0.5,
    this.reelSpinExcitement = 0.5,
    this.featureTriggerImpact = 0.5,
    this.lossDisguiseLevel = 0.3,
    this.tempoAverage = 0.5,
    this.dynamicRange = 0.5,
  });

  Map<String, double> get characteristics => {
        'Win Intensity': winCelebrationIntensity,
        'Near-miss': nearMissAnticipation,
        'Ambient': ambientEngagement,
        'Spin Excitement': reelSpinExcitement,
        'Feature Impact': featureTriggerImpact,
        'Loss Disguise': lossDisguiseLevel,
        'Tempo': tempoAverage,
        'Dynamic Range': dynamicRange,
      };
}

// =============================================================================
// SIMULATION RESULTS
// =============================================================================

/// Results for one variant
class VariantMetrics {
  final String variantName;
  final Map<SuccessMetric, double> scores;
  final int sampleSize;
  final Map<PlayerArchetype, Map<SuccessMetric, double>> perArchetype;

  const VariantMetrics({
    required this.variantName,
    required this.scores,
    required this.sampleSize,
    required this.perArchetype,
  });
}

/// Complete A/B test result
class AbTestResult {
  final VariantMetrics variantA;
  final VariantMetrics variantB;
  final double pValue;              // Statistical significance
  final (double, double) confidenceInterval;  // 95% CI
  final String? winner;             // null if not significant
  final List<String> responsibleGamingFlags;
  final DateTime timestamp;

  const AbTestResult({
    required this.variantA,
    required this.variantB,
    required this.pValue,
    required this.confidenceInterval,
    this.winner,
    required this.responsibleGamingFlags,
    required this.timestamp,
  });

  bool get isSignificant => pValue < 0.05;

  double getDelta(SuccessMetric metric) {
    final a = variantA.scores[metric] ?? 0;
    final b = variantB.scores[metric] ?? 0;
    return b - a;
  }

  double getDeltaPercent(SuccessMetric metric) {
    final a = variantA.scores[metric] ?? 0;
    if (a == 0) return 0;
    return ((variantB.scores[metric] ?? 0) - a) / a * 100;
  }
}

// =============================================================================
// A/B TEST PROVIDER
// =============================================================================

/// A/B Testing Analytics Engine
class AbTestProvider extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  AudioVariant _variantA = const AudioVariant(
    name: 'Variant A',
    description: 'Current production audio',
    winCelebrationIntensity: 0.6,
    nearMissAnticipation: 0.5,
    ambientEngagement: 0.4,
    reelSpinExcitement: 0.5,
    featureTriggerImpact: 0.7,
    lossDisguiseLevel: 0.3,
    tempoAverage: 0.5,
    dynamicRange: 0.5,
  );

  AudioVariant _variantB = const AudioVariant(
    name: 'Variant B',
    description: 'New audio package',
    winCelebrationIntensity: 0.8,
    nearMissAnticipation: 0.6,
    ambientEngagement: 0.6,
    reelSpinExcitement: 0.7,
    featureTriggerImpact: 0.8,
    lossDisguiseLevel: 0.2,
    tempoAverage: 0.6,
    dynamicRange: 0.7,
  );

  int _sampleSize = 10000;
  bool _isSimulating = false;
  double _simulationProgress = 0.0;
  AbTestResult? _lastResult;
  final List<AbTestResult> _history = [];

  // Population mix
  final Map<PlayerArchetype, double> _populationMix = {
    for (final a in PlayerArchetype.values) a: a.populationWeight,
  };

  // Active metrics
  final Set<SuccessMetric> _activeMetrics = Set.from(SuccessMetric.values);

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  AudioVariant get variantA => _variantA;
  AudioVariant get variantB => _variantB;
  int get sampleSize => _sampleSize;
  bool get isSimulating => _isSimulating;
  double get simulationProgress => _simulationProgress;
  AbTestResult? get lastResult => _lastResult;
  List<AbTestResult> get history => List.unmodifiable(_history);
  Map<PlayerArchetype, double> get populationMix => Map.unmodifiable(_populationMix);
  Set<SuccessMetric> get activeMetrics => Set.unmodifiable(_activeMetrics);

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  void setVariantA(AudioVariant v) {
    _variantA = v;
    notifyListeners();
  }

  void setVariantB(AudioVariant v) {
    _variantB = v;
    notifyListeners();
  }

  void setSampleSize(int n) {
    _sampleSize = n.clamp(100, 100000);
    notifyListeners();
  }

  void setPopulationWeight(PlayerArchetype archetype, double weight) {
    _populationMix[archetype] = weight.clamp(0, 1);
    // Normalize to sum to 1.0
    final total = _populationMix.values.fold<double>(0, (s, v) => s + v);
    if (total > 0) {
      for (final k in _populationMix.keys) {
        _populationMix[k] = _populationMix[k]! / total;
      }
    }
    notifyListeners();
  }

  void toggleMetric(SuccessMetric metric) {
    if (_activeMetrics.contains(metric)) {
      _activeMetrics.remove(metric);
    } else {
      _activeMetrics.add(metric);
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SIMULATION ENGINE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Run the A/B test simulation
  void runSimulation() {
    if (_isSimulating) return;
    _isSimulating = true;
    _simulationProgress = 0.0;
    notifyListeners();

    // Synchronous simulation (fast enough for UI thread with reasonable sample sizes)
    final rng = math.Random();

    final aScores = <SuccessMetric, List<double>>{};
    final bScores = <SuccessMetric, List<double>>{};
    final aPerArchetype = <PlayerArchetype, Map<SuccessMetric, List<double>>>{};
    final bPerArchetype = <PlayerArchetype, Map<SuccessMetric, List<double>>>{};

    for (final m in _activeMetrics) {
      aScores[m] = [];
      bScores[m] = [];
    }
    for (final arch in PlayerArchetype.values) {
      aPerArchetype[arch] = {for (final m in _activeMetrics) m: <double>[]};
      bPerArchetype[arch] = {for (final m in _activeMetrics) m: <double>[]};
    }

    for (int i = 0; i < _sampleSize; i++) {
      // Determine archetype based on population mix
      final archetype = _sampleArchetype(rng);

      // Simulate one player session for each variant
      for (final metric in _activeMetrics) {
        final scoreA = _simulateMetric(metric, _variantA, archetype, rng);
        final scoreB = _simulateMetric(metric, _variantB, archetype, rng);

        aScores[metric]!.add(scoreA);
        bScores[metric]!.add(scoreB);
        aPerArchetype[archetype]![metric]!.add(scoreA);
        bPerArchetype[archetype]![metric]!.add(scoreB);
      }

      // Update progress every 1000 players
      if (i % 1000 == 0) {
        _simulationProgress = i / _sampleSize;
      }
    }

    // Aggregate scores
    final aAgg = <SuccessMetric, double>{};
    final bAgg = <SuccessMetric, double>{};
    for (final m in _activeMetrics) {
      aAgg[m] = _mean(aScores[m]!);
      bAgg[m] = _mean(bScores[m]!);
    }

    // Per-archetype aggregation
    final aPerArch = <PlayerArchetype, Map<SuccessMetric, double>>{};
    final bPerArch = <PlayerArchetype, Map<SuccessMetric, double>>{};
    for (final arch in PlayerArchetype.values) {
      aPerArch[arch] = {};
      bPerArch[arch] = {};
      for (final m in _activeMetrics) {
        final aList = aPerArchetype[arch]![m]!;
        final bList = bPerArchetype[arch]![m]!;
        if (aList.isNotEmpty) aPerArch[arch]![m] = _mean(aList);
        if (bList.isNotEmpty) bPerArch[arch]![m] = _mean(bList);
      }
    }

    // Statistical significance — Welch's t-test on primary metric
    final primaryMetric = _activeMetrics.contains(SuccessMetric.sessionDuration)
        ? SuccessMetric.sessionDuration
        : _activeMetrics.first;

    final pValue = _welchTTest(aScores[primaryMetric]!, bScores[primaryMetric]!);
    final ci = _confidenceInterval95(aScores[primaryMetric]!, bScores[primaryMetric]!);

    // Determine winner
    String? winner;
    if (pValue < 0.05) {
      final aMean = aAgg[primaryMetric]!;
      final bMean = bAgg[primaryMetric]!;
      if (primaryMetric.higherIsBetter) {
        winner = bMean > aMean ? _variantB.name : _variantA.name;
      } else {
        winner = bMean < aMean ? _variantB.name : _variantA.name;
      }
    }

    // Responsible gaming flags
    final rgFlags = <String>[];
    if (_activeMetrics.contains(SuccessMetric.sessionExtension)) {
      final seA = aAgg[SuccessMetric.sessionExtension] ?? 0;
      final seB = bAgg[SuccessMetric.sessionExtension] ?? 0;
      if (seB > seA * 1.10) {
        rgFlags.add('⚠ ${_variantB.name} shows >10% session extension increase for high-risk players');
      }
      if (seA > seB * 1.10) {
        rgFlags.add('⚠ ${_variantA.name} shows >10% session extension increase for high-risk players');
      }
    }
    if (_activeMetrics.contains(SuccessMetric.betEscalation)) {
      final beA = aAgg[SuccessMetric.betEscalation] ?? 0;
      final beB = bAgg[SuccessMetric.betEscalation] ?? 0;
      if (beB > 0.3) {
        rgFlags.add('⚠ ${_variantB.name}: bet escalation score ${(beB * 100).toStringAsFixed(1)}% — potential responsible gaming concern');
      }
      if (beA > 0.3) {
        rgFlags.add('⚠ ${_variantA.name}: bet escalation score ${(beA * 100).toStringAsFixed(1)}% — potential responsible gaming concern');
      }
    }

    final result = AbTestResult(
      variantA: VariantMetrics(
        variantName: _variantA.name,
        scores: aAgg,
        sampleSize: _sampleSize,
        perArchetype: aPerArch,
      ),
      variantB: VariantMetrics(
        variantName: _variantB.name,
        scores: bAgg,
        sampleSize: _sampleSize,
        perArchetype: bPerArch,
      ),
      pValue: pValue,
      confidenceInterval: ci,
      winner: winner,
      responsibleGamingFlags: rgFlags,
      timestamp: DateTime.now(),
    );

    _lastResult = result;
    _history.insert(0, result);
    if (_history.length > 20) _history.removeLast();
    _isSimulating = false;
    _simulationProgress = 1.0;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BEHAVIORAL SIMULATION MODEL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Simulate a single metric for one player session
  double _simulateMetric(
    SuccessMetric metric,
    AudioVariant variant,
    PlayerArchetype archetype,
    math.Random rng,
  ) {
    final sensitivity = archetype.audioSensitivity;

    return switch (metric) {
      SuccessMetric.sessionDuration => _simSessionDuration(variant, archetype, sensitivity, rng),
      SuccessMetric.reEngagement => _simReEngagement(variant, archetype, sensitivity, rng),
      SuccessMetric.voluntaryEnd => _simVoluntaryEnd(variant, archetype, sensitivity, rng),
      SuccessMetric.nearMissTolerance => _simNearMissTolerance(variant, sensitivity, rng),
      SuccessMetric.winCelebrationScore => _simWinCelebration(variant, sensitivity, rng),
      SuccessMetric.betEscalation => _simBetEscalation(variant, archetype, sensitivity, rng),
      SuccessMetric.sessionExtension => _simSessionExtension(variant, archetype, sensitivity, rng),
    };
  }

  double _simSessionDuration(AudioVariant v, PlayerArchetype arch, double sens, math.Random rng) {
    final base = arch.avgSessionMinutes;
    // Audio engagement effect: ambient + spin excitement extend sessions
    final audioEffect = (v.ambientEngagement * 0.4 + v.reelSpinExcitement * 0.3 + v.dynamicRange * 0.3) * sens;
    // Gaussian noise
    final noise = _gaussianNoise(rng) * base * 0.2;
    return (base * (1 + audioEffect * 0.3) + noise).clamp(1.0, base * 3);
  }

  double _simReEngagement(AudioVariant v, PlayerArchetype arch, double sens, math.Random rng) {
    // Base re-engagement rate by archetype
    final base = switch (arch) {
      PlayerArchetype.casual => 0.3,
      PlayerArchetype.regular => 0.6,
      PlayerArchetype.highRoller => 0.8,
      PlayerArchetype.newPlayer => 0.15,
      PlayerArchetype.vip => 0.9,
    };
    // Win celebration and ambient quality drive return visits
    final audioEffect = (v.winCelebrationIntensity * 0.4 + v.ambientEngagement * 0.3 + v.featureTriggerImpact * 0.3) * sens;
    final noise = _gaussianNoise(rng) * 0.1;
    return (base + audioEffect * 0.15 + noise).clamp(0.0, 1.0);
  }

  double _simVoluntaryEnd(AudioVariant v, PlayerArchetype arch, double sens, math.Random rng) {
    // How often player chooses to stop (vs running out of budget)
    final base = switch (arch) {
      PlayerArchetype.casual => 0.7,
      PlayerArchetype.regular => 0.5,
      PlayerArchetype.highRoller => 0.4,
      PlayerArchetype.newPlayer => 0.6,
      PlayerArchetype.vip => 0.35,
    };
    // Lower loss disguise → more honest → more voluntary stops (good)
    final audioEffect = (1 - v.lossDisguiseLevel) * sens * 0.1;
    final noise = _gaussianNoise(rng) * 0.1;
    return (base + audioEffect + noise).clamp(0.0, 1.0);
  }

  double _simNearMissTolerance(AudioVariant v, double sens, math.Random rng) {
    // How well players handle near-miss audio (higher = better tolerance)
    final base = 0.5;
    // High near-miss anticipation can reduce tolerance (player gets frustrated)
    final audioEffect = -v.nearMissAnticipation * sens * 0.2 + v.ambientEngagement * sens * 0.1;
    final noise = _gaussianNoise(rng) * 0.15;
    return (base + audioEffect + noise).clamp(0.0, 1.0);
  }

  double _simWinCelebration(AudioVariant v, double sens, math.Random rng) {
    // Win celebration satisfaction (higher = better)
    final base = 0.5;
    final audioEffect = (v.winCelebrationIntensity * 0.5 + v.dynamicRange * 0.3 + v.featureTriggerImpact * 0.2) * sens;
    final noise = _gaussianNoise(rng) * 0.1;
    return (base + audioEffect * 0.4 + noise).clamp(0.0, 1.0);
  }

  double _simBetEscalation(AudioVariant v, PlayerArchetype arch, double sens, math.Random rng) {
    // RESPONSIBLE GAMING: does audio cause bet increases? (lower = better)
    final archFactor = arch.betMultiplier / 8.0; // Normalize
    // High excitement + high loss disguise → more bet escalation
    final audioEffect = (v.reelSpinExcitement * 0.3 + v.lossDisguiseLevel * 0.4 + v.winCelebrationIntensity * 0.3) * sens;
    final noise = _gaussianNoise(rng) * 0.08;
    return (archFactor * 0.3 + audioEffect * 0.3 + noise).clamp(0.0, 1.0);
  }

  double _simSessionExtension(AudioVariant v, PlayerArchetype arch, double sens, math.Random rng) {
    // RESPONSIBLE GAMING: excessive play continuation? (lower = better)
    final archFactor = switch (arch) {
      PlayerArchetype.casual => 0.1,
      PlayerArchetype.regular => 0.2,
      PlayerArchetype.highRoller => 0.4,
      PlayerArchetype.newPlayer => 0.05,
      PlayerArchetype.vip => 0.5,
    };
    // High ambient + spin excitement → session extension
    final audioEffect = (v.ambientEngagement * 0.4 + v.reelSpinExcitement * 0.3 + v.tempoAverage * 0.3) * sens;
    final noise = _gaussianNoise(rng) * 0.08;
    return (archFactor + audioEffect * 0.25 + noise).clamp(0.0, 1.0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  double _mean(List<double> data) {
    if (data.isEmpty) return 0;
    return data.fold<double>(0, (s, v) => s + v) / data.length;
  }

  double _stdDev(List<double> data) {
    if (data.length < 2) return 0;
    final m = _mean(data);
    final variance = data.fold<double>(0, (s, v) => s + (v - m) * (v - m)) / (data.length - 1);
    return math.sqrt(variance);
  }

  /// Welch's t-test — returns approximate p-value
  double _welchTTest(List<double> a, List<double> b) {
    final n1 = a.length.toDouble();
    final n2 = b.length.toDouble();
    if (n1 < 2 || n2 < 2) return 1.0;

    final m1 = _mean(a);
    final m2 = _mean(b);
    final s1 = _stdDev(a);
    final s2 = _stdDev(b);

    final se = math.sqrt(s1 * s1 / n1 + s2 * s2 / n2);
    if (se == 0) return 1.0;

    final t = (m1 - m2).abs() / se;

    // Welch-Satterthwaite degrees of freedom
    final v1 = s1 * s1 / n1;
    final v2 = s2 * s2 / n2;
    final df = (v1 + v2) * (v1 + v2) / (v1 * v1 / (n1 - 1) + v2 * v2 / (n2 - 1));

    // Approximate p-value using Student's t-distribution
    // For large df, use normal approximation
    return _tDistPValue(t, df);
  }

  /// Approximate two-tailed p-value from t-distribution
  double _tDistPValue(double t, double df) {
    // For large df (>30), normal approximation is adequate
    if (df > 30) {
      // Standard normal CDF approximation
      final z = t.abs();
      final p = 2.0 * _normalCdfComplement(z);
      return p.clamp(0.0, 1.0);
    }
    // For smaller df, use approximation
    final x = df / (df + t * t);
    final p = _incompleteBeta(df / 2, 0.5, x);
    return p.clamp(0.0, 1.0);
  }

  /// Complementary standard normal CDF: P(Z > z)
  double _normalCdfComplement(double z) {
    // Abramowitz & Stegun approximation
    const a1 = 0.254829592;
    const a2 = -0.284496736;
    const a3 = 1.421413741;
    const a4 = -1.453152027;
    const a5 = 1.061405429;
    const p = 0.3275911;

    final sign = z < 0 ? -1.0 : 1.0;
    z = z.abs() / math.sqrt(2.0);

    final t = 1.0 / (1.0 + p * z);
    final y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * math.exp(-z * z);

    return 0.5 * (1.0 - sign * y);
  }

  /// Regularized incomplete beta function — simple series approximation
  double _incompleteBeta(double a, double b, double x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    // Use continued fraction for better convergence
    double result = 0;
    final lnBeta = _lnGamma(a) + _lnGamma(b) - _lnGamma(a + b);
    final front = math.exp(math.log(x) * a + math.log(1 - x) * b - lnBeta) / a;
    // Series expansion
    double term = 1.0;
    for (int n = 1; n < 200; n++) {
      term *= (n - b) * x / n;
      result += term / (a + n);
      if (term.abs() < 1e-10) break;
    }
    return (front * (1.0 + result * a)).clamp(0.0, 1.0);
  }

  /// Stirling's approximation for ln(Gamma(x))
  double _lnGamma(double x) {
    const c = [
      76.18009172947146, -86.50532032941677, 24.01409824083091,
      -1.231739572450155, 0.1208650973866179e-2, -0.5395239384953e-5
    ];
    double y = x;
    double tmp = x + 5.5;
    tmp -= (x + 0.5) * math.log(tmp);
    double ser = 1.000000000190015;
    for (int j = 0; j < 6; j++) {
      y += 1;
      ser += c[j] / y;
    }
    return -tmp + math.log(2.5066282746310005 * ser / x);
  }

  /// 95% confidence interval for difference in means
  (double, double) _confidenceInterval95(List<double> a, List<double> b) {
    final diff = _mean(b) - _mean(a);
    final se = math.sqrt(
      _stdDev(a) * _stdDev(a) / a.length +
      _stdDev(b) * _stdDev(b) / b.length,
    );
    // z = 1.96 for 95% CI
    return (diff - 1.96 * se, diff + 1.96 * se);
  }

  /// Gaussian noise using Box-Muller transform
  double _gaussianNoise(math.Random rng) {
    final u1 = rng.nextDouble();
    final u2 = rng.nextDouble();
    return math.sqrt(-2 * math.log(u1.clamp(1e-10, 1.0))) * math.cos(2 * math.pi * u2);
  }

  /// Sample player archetype based on population mix
  PlayerArchetype _sampleArchetype(math.Random rng) {
    final r = rng.nextDouble();
    double cumulative = 0;
    for (final entry in _populationMix.entries) {
      cumulative += entry.value;
      if (r <= cumulative) return entry.key;
    }
    return PlayerArchetype.regular;
  }
}
