/// RGAI™ — Responsible Gaming Audio Intelligence
///
/// Quantitative compliance analysis for slot audio assets.
/// Generates Responsible Gaming Audio Report (RGAR) per jurisdiction.
///
/// Per-asset metrics:
///   - Arousal Coefficient (0.0–1.0) — stimulation measurement
///   - Near-Miss Deception Index — how much sound suggests "almost won"
///   - Loss-Disguise Score — whether loss sounds like a win
///   - Temporal Distortion Factor — whether sound distorts time perception
///   - Addiction Risk Rating (LOW / MEDIUM / HIGH / PROHIBITED)
///
/// Regulatory exports: JSON audit, PDF report (future), XML (future).
/// Auto-remediation: suggests parameter changes for flagged assets.
///
/// See: FLUXFORGE_SLOTLAB_ULTIMATE_ARCHITECTURE.md §STUB3
library;

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../models/aurexis_jurisdiction.dart';
import '../aurexis_provider.dart';
import 'emotional_state_provider.dart';
import 'neuro_audio_provider.dart';

// =============================================================================
// RISK RATINGS
// =============================================================================

/// Addiction risk rating per regulatory standards
enum AddictionRiskRating {
  low,
  medium,
  high,
  prohibited;

  String get displayName => switch (this) {
        low => 'LOW',
        medium => 'MEDIUM',
        high => 'HIGH',
        prohibited => 'PROHIBITED',
      };

  int get colorValue => switch (this) {
        low => 0xFF44CC44,
        medium => 0xFFDDAA22,
        high => 0xFFCC4444,
        prohibited => 0xFFFF0000,
      };

  /// Whether this rating requires remediation
  bool get requiresRemediation => this == high || this == prohibited;
}

// =============================================================================
// RGAR ANALYSIS — Per-asset compliance metrics
// =============================================================================

/// RGAR (Responsible Gaming Audio Report) analysis for a single audio asset
class RgarAssetAnalysis {
  /// Asset identifier
  final String assetId;
  final String assetName;

  /// Stage this asset is mapped to (e.g., "WIN_3", "REEL_STOP")
  final String stage;

  /// Arousal Coefficient (0.0–1.0)
  /// How stimulating is this sound? Combines volume, tempo, spectral energy.
  final double arousalCoefficient;

  /// Near-Miss Deception Index (0.0–1.0)
  /// Does this sound suggest "almost won" when used on near-miss events?
  final double nearMissDeceptionIndex;

  /// Loss-Disguise Score (0.0–1.0)
  /// Does a loss event sound like a win? (celebratory audio on sub-bet wins)
  final double lossDisguiseScore;

  /// Temporal Distortion Factor (0.0–1.0)
  /// Does this sound distort time perception? (repetitive loops, tempo shifts)
  final double temporalDistortionFactor;

  /// Overall addiction risk rating
  final AddictionRiskRating riskRating;

  /// Specific regulatory flags
  final List<String> flags;

  /// Auto-remediation suggestions
  final List<RemediationSuggestion> remediations;

  const RgarAssetAnalysis({
    required this.assetId,
    required this.assetName,
    required this.stage,
    required this.arousalCoefficient,
    required this.nearMissDeceptionIndex,
    required this.lossDisguiseScore,
    required this.temporalDistortionFactor,
    required this.riskRating,
    this.flags = const [],
    this.remediations = const [],
  });

  /// Composite risk score (0.0–1.0)
  double get compositeRisk =>
      (arousalCoefficient * 0.3 +
              nearMissDeceptionIndex * 0.3 +
              lossDisguiseScore * 0.25 +
              temporalDistortionFactor * 0.15)
          .clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
        'asset_id': assetId,
        'asset_name': assetName,
        'stage': stage,
        'arousal_coefficient': arousalCoefficient,
        'near_miss_deception_index': nearMissDeceptionIndex,
        'loss_disguise_score': lossDisguiseScore,
        'temporal_distortion_factor': temporalDistortionFactor,
        'risk_rating': riskRating.displayName,
        'composite_risk': compositeRisk,
        'flags': flags,
        'remediations': remediations.map((r) => r.toJson()).toList(),
      };
}

/// A remediation suggestion for a flagged asset
class RemediationSuggestion {
  final String parameter;
  final String currentValue;
  final String suggestedValue;
  final String reason;

  const RemediationSuggestion({
    required this.parameter,
    required this.currentValue,
    required this.suggestedValue,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'parameter': parameter,
        'current': currentValue,
        'suggested': suggestedValue,
        'reason': reason,
      };
}

// =============================================================================
// RGAR REPORT — Complete regulatory report
// =============================================================================

/// Complete RGAR report for a jurisdiction
class RgarReport {
  final String gameName;
  final AurexisJurisdiction jurisdiction;
  final DateTime generatedAt;
  final List<RgarAssetAnalysis> assets;
  final RgarSummary summary;

  const RgarReport({
    required this.gameName,
    required this.jurisdiction,
    required this.generatedAt,
    required this.assets,
    required this.summary,
  });

  Map<String, dynamic> toJson() => {
        'game_name': gameName,
        'jurisdiction': jurisdiction.code,
        'jurisdiction_label': jurisdiction.label,
        'generated_at': generatedAt.toIso8601String(),
        'summary': summary.toJson(),
        'assets': assets.map((a) => a.toJson()).toList(),
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Summary statistics for an RGAR report
class RgarSummary {
  final int totalAssets;
  final int passedAssets;
  final int flaggedAssets;
  final int prohibitedAssets;
  final double overallComplianceScore; // 0.0-100.0
  final double avgArousal;
  final double maxNearMissDeception;
  final double maxLossDisguise;
  final Map<AddictionRiskRating, int> ratingDistribution;

  const RgarSummary({
    required this.totalAssets,
    required this.passedAssets,
    required this.flaggedAssets,
    required this.prohibitedAssets,
    required this.overallComplianceScore,
    required this.avgArousal,
    required this.maxNearMissDeception,
    required this.maxLossDisguise,
    required this.ratingDistribution,
  });

  bool get isCompliant => prohibitedAssets == 0 && flaggedAssets == 0;

  /// Aggregate risk rating for the whole project
  AddictionRiskRating? get overallRiskRating {
    if (prohibitedAssets > 0) return AddictionRiskRating.prohibited;
    if (flaggedAssets > 0) return AddictionRiskRating.high;
    if (totalAssets == 0) return null;
    // Check distribution for medium
    final medCount = ratingDistribution[AddictionRiskRating.medium] ?? 0;
    if (medCount > 0) return AddictionRiskRating.medium;
    return AddictionRiskRating.low;
  }

  Map<String, dynamic> toJson() => {
        'total_assets': totalAssets,
        'passed': passedAssets,
        'flagged': flaggedAssets,
        'prohibited': prohibitedAssets,
        'compliance_score': overallComplianceScore,
        'avg_arousal': avgArousal,
        'max_near_miss_deception': maxNearMissDeception,
        'max_loss_disguise': maxLossDisguise,
        'is_compliant': isCompliant,
        'rating_distribution': ratingDistribution.map(
          (k, v) => MapEntry(k.displayName, v),
        ),
      };
}

// =============================================================================
// RGAI PROVIDER
// =============================================================================

/// RGAI™ engine — analyzes audio assets for responsible gaming compliance
/// and generates RGAR reports per jurisdiction.
class RgaiProvider extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  AurexisJurisdiction _jurisdiction = AurexisJurisdiction.ukgc;
  RgarReport? _report;
  bool _isAnalyzing = false;
  bool _safeModeActive = false;
  final List<RgarAssetAnalysis> _liveAnalyses = [];

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  AurexisJurisdiction get jurisdiction => _jurisdiction;
  RgarReport? get report => _report;
  bool get isAnalyzing => _isAnalyzing;
  bool get safeModeActive => _safeModeActive;
  List<RgarAssetAnalysis> get liveAnalyses => List.unmodifiable(_liveAnalyses);
  bool get hasReport => _report != null;
  bool get isCompliant => _report?.summary.isCompliant ?? true;

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  void setJurisdiction(AurexisJurisdiction j) {
    if (_jurisdiction == j) return;
    _jurisdiction = j;
    // Re-analyze if we have data
    if (_liveAnalyses.isNotEmpty) {
      _regenerateReport();
    }
    notifyListeners();
  }

  /// Enable Safe Mode — all parameters clamped to regulatory safety range
  void setSafeModeActive(bool active) {
    if (_safeModeActive == active) return;
    _safeModeActive = active;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANALYSIS — Per-asset RGAR computation
  // ═══════════════════════════════════════════════════════════════════════════

  /// Analyze a single audio asset mapped to a stage
  RgarAssetAnalysis analyzeAsset({
    required String assetId,
    required String assetName,
    required String stage,
    required double volumeDb,
    required double durationS,
    required double tempoMultiplier,
    required double spectralCentroidHz,
    required bool isWinEvent,
    required bool isNearMissEvent,
    required bool isLossEvent,
    double betMultiplier = 0.0,
  }) {
    final rules = JurisdictionDatabase.getRules(_jurisdiction);

    // ─── 1. Arousal Coefficient ──────────────────────────────────────
    // Based on volume, tempo, spectral centroid, duration
    final volumeNorm = ((volumeDb + 60) / 60).clamp(0.0, 1.0); // -60dB to 0dB
    final tempoArousal = ((tempoMultiplier - 0.7) / 0.6).clamp(0.0, 1.0); // 0.7x-1.3x
    final spectralArousal = (spectralCentroidHz / 8000).clamp(0.0, 1.0); // higher = more arousing
    final durationArousal = (durationS / 10).clamp(0.0, 1.0); // longer = more arousing
    final arousal = (volumeNorm * 0.35 + tempoArousal * 0.25 +
            spectralArousal * 0.2 + durationArousal * 0.2)
        .clamp(0.0, 1.0);

    // ─── 2. Near-Miss Deception Index ────────────────────────────────
    // How much does the sound suggest "almost won"?
    double nearMissDeception = 0.0;
    if (isNearMissEvent) {
      // High arousal on near-miss = deceptive
      nearMissDeception = arousal * 0.6;
      // Win-like spectral profile on near-miss = very deceptive
      if (spectralCentroidHz > 4000) nearMissDeception += 0.2;
      // Duration > 2s on near-miss = building false anticipation
      if (durationS > 2.0) nearMissDeception += 0.2;
    }
    nearMissDeception = nearMissDeception.clamp(0.0, 1.0);

    // ─── 3. Loss-Disguise Score ──────────────────────────────────────
    // Does a loss or sub-bet win sound like a real win?
    double lossDisguise = 0.0;
    if (isLossEvent || (isWinEvent && betMultiplier < 1.0)) {
      // Celebratory audio on loss/sub-bet = disguise
      if (arousal > 0.5) lossDisguise = (arousal - 0.3) * 1.5;
      // High spectral centroid on loss = sounds like win
      if (spectralCentroidHz > 3000) lossDisguise += 0.15;
      // Long duration on loss = sounds important
      if (durationS > 1.5) lossDisguise += 0.1;
    }
    lossDisguise = lossDisguise.clamp(0.0, 1.0);

    // ─── 4. Temporal Distortion Factor ───────────────────────────────
    // Does the sound distort time perception?
    double temporalDistortion = 0.0;
    // Repetitive loops > 5s = time distortion
    if (durationS > 5.0) temporalDistortion += (durationS / 15).clamp(0.0, 0.4);
    // Extreme tempo = distortion
    if (tempoMultiplier > 1.2 || tempoMultiplier < 0.8) {
      temporalDistortion += (tempoMultiplier - 1.0).abs() * 0.5;
    }
    // Very high arousal sustained = trance-like
    if (arousal > 0.8 && durationS > 3.0) temporalDistortion += 0.3;
    temporalDistortion = temporalDistortion.clamp(0.0, 1.0);

    // ─── 5. Risk Rating ──────────────────────────────────────────────
    final composite = (arousal * 0.3 + nearMissDeception * 0.3 +
            lossDisguise * 0.25 + temporalDistortion * 0.15)
        .clamp(0.0, 1.0);

    AddictionRiskRating rating;
    if (composite > 0.8) {
      rating = AddictionRiskRating.prohibited;
    } else if (composite > 0.6) {
      rating = AddictionRiskRating.high;
    } else if (composite > 0.35) {
      rating = AddictionRiskRating.medium;
    } else {
      rating = AddictionRiskRating.low;
    }

    // ─── 6. Regulatory Flags ─────────────────────────────────────────
    final flags = <String>[];

    if (rules.ldwSuppression && lossDisguise > 0.3) {
      flags.add('LDW: Loss-disguised-as-win audio detected');
    }
    if (rules.maxCelebrationDurationS > 0 && durationS > rules.maxCelebrationDurationS && isWinEvent) {
      flags.add('DURATION: Win celebration exceeds ${rules.maxCelebrationDurationS}s limit');
    }
    if (volumeDb > -6 + rules.maxWinVolumeBoostDb && isWinEvent) {
      flags.add('VOLUME: Win boost exceeds ${rules.maxWinVolumeBoostDb}dB limit');
    }
    if (nearMissDeception > 0.5) {
      flags.add('NEAR-MISS: High deception index on near-miss event');
    }
    if (temporalDistortion > 0.6) {
      flags.add('TEMPORAL: Sound may distort time perception');
    }

    // ─── 7. Auto-Remediation Suggestions ─────────────────────────────
    final remediations = <RemediationSuggestion>[];

    if (arousal > 0.7 && (isNearMissEvent || isLossEvent)) {
      remediations.add(RemediationSuggestion(
        parameter: 'Volume',
        currentValue: '${volumeDb.toStringAsFixed(1)} dB',
        suggestedValue: '${(volumeDb - 6).toStringAsFixed(1)} dB',
        reason: 'Reduce stimulation on non-win events',
      ));
    }
    if (lossDisguise > 0.4) {
      remediations.add(const RemediationSuggestion(
        parameter: 'Spectral Profile',
        currentValue: 'Bright/celebratory',
        suggestedValue: 'Neutral/muted',
        reason: 'LDW compliance: loss should not sound like win',
      ));
    }
    if (durationS > (rules.maxCelebrationDurationS > 0 ? rules.maxCelebrationDurationS : 8.0) && isWinEvent) {
      remediations.add(RemediationSuggestion(
        parameter: 'Duration',
        currentValue: '${durationS.toStringAsFixed(1)}s',
        suggestedValue: '${math.min(durationS, rules.maxCelebrationDurationS > 0 ? rules.maxCelebrationDurationS : 5.0).toStringAsFixed(1)}s',
        reason: 'Excessive celebration duration',
      ));
    }
    if (nearMissDeception > 0.5) {
      remediations.add(const RemediationSuggestion(
        parameter: 'Near-Miss Tone',
        currentValue: 'Win-like',
        suggestedValue: 'Neutral tension',
        reason: 'Near-miss should not suggest a win outcome',
      ));
    }

    final analysis = RgarAssetAnalysis(
      assetId: assetId,
      assetName: assetName,
      stage: stage,
      arousalCoefficient: arousal,
      nearMissDeceptionIndex: nearMissDeception,
      lossDisguiseScore: lossDisguise,
      temporalDistortionFactor: temporalDistortion,
      riskRating: rating,
      flags: flags,
      remediations: remediations,
    );

    // Add to live analyses
    _liveAnalyses.removeWhere((a) => a.assetId == assetId);
    _liveAnalyses.add(analysis);

    _regenerateReport();
    return analysis;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BATCH ANALYSIS — Analyze all mapped assets
  // ═══════════════════════════════════════════════════════════════════════════

  /// Analyze a batch of assets and generate report
  RgarReport analyzeBatch({
    required String gameName,
    required List<({String id, String name, String stage, double volumeDb, double durationS, double tempo, double spectralHz, bool isWin, bool isNearMiss, bool isLoss, double betMult})> assets,
  }) {
    _isAnalyzing = true;
    _liveAnalyses.clear();
    notifyListeners();

    for (final asset in assets) {
      analyzeAsset(
        assetId: asset.id,
        assetName: asset.name,
        stage: asset.stage,
        volumeDb: asset.volumeDb,
        durationS: asset.durationS,
        tempoMultiplier: asset.tempo,
        spectralCentroidHz: asset.spectralHz,
        isWinEvent: asset.isWin,
        isNearMissEvent: asset.isNearMiss,
        isLossEvent: asset.isLoss,
        betMultiplier: asset.betMult,
      );
    }

    _isAnalyzing = false;
    notifyListeners();
    return _report!;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SAFE MODE — Clamp all parameters to regulatory safety range
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get safe mode parameters for a given jurisdiction
  Map<String, double> getSafeModeParameters() {
    final rules = JurisdictionDatabase.getRules(_jurisdiction);
    return {
      'max_celebration_duration_s': rules.maxCelebrationDurationS > 0
          ? rules.maxCelebrationDurationS
          : 5.0,
      'max_win_volume_boost_db': rules.maxWinVolumeBoostDb,
      'max_escalation_multiplier': rules.maxEscalationMultiplier,
      'min_fatigue_regulation': rules.minFatigueRegulation,
      'celebration_cooldown_s': rules.celebrationCooldownS,
      'ldw_suppression': rules.ldwSuppression ? 1.0 : 0.0,
      'max_arousal_coefficient': 0.6, // safe upper bound
      'max_near_miss_deception': 0.3, // safe upper bound
      'max_loss_disguise': 0.2, // safe upper bound
      'max_temporal_distortion': 0.4, // safe upper bound
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPORT — Regulatory report output
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export RGAR as JSON audit trail
  String exportJsonAudit() {
    if (_report == null) return '{}';
    return _report!.toJsonString();
  }

  /// Reset all state
  void reset() {
    _report = null;
    _liveAnalyses.clear();
    _isAnalyzing = false;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL — Report generation
  // ═══════════════════════════════════════════════════════════════════════════

  void _regenerateReport() {
    if (_liveAnalyses.isEmpty) return;

    final ratingDist = <AddictionRiskRating, int>{};
    double totalArousal = 0;
    double maxNmd = 0;
    double maxLd = 0;
    int flagged = 0;
    int prohibited = 0;

    for (final a in _liveAnalyses) {
      ratingDist[a.riskRating] = (ratingDist[a.riskRating] ?? 0) + 1;
      totalArousal += a.arousalCoefficient;
      if (a.nearMissDeceptionIndex > maxNmd) maxNmd = a.nearMissDeceptionIndex;
      if (a.lossDisguiseScore > maxLd) maxLd = a.lossDisguiseScore;
      if (a.riskRating == AddictionRiskRating.high) flagged++;
      if (a.riskRating == AddictionRiskRating.prohibited) prohibited++;
    }

    final passed = _liveAnalyses.length - flagged - prohibited;
    final complianceScore = _liveAnalyses.isNotEmpty
        ? (passed / _liveAnalyses.length * 100).clamp(0.0, 100.0)
        : 100.0;

    final summary = RgarSummary(
      totalAssets: _liveAnalyses.length,
      passedAssets: passed,
      flaggedAssets: flagged,
      prohibitedAssets: prohibited,
      overallComplianceScore: complianceScore,
      avgArousal: _liveAnalyses.isNotEmpty ? totalArousal / _liveAnalyses.length : 0,
      maxNearMissDeception: maxNmd,
      maxLossDisguise: maxLd,
      ratingDistribution: ratingDist,
    );

    _report = RgarReport(
      gameName: 'Current Project',
      jurisdiction: _jurisdiction,
      generatedAt: DateTime.now(),
      assets: List.unmodifiable(_liveAnalyses),
      summary: summary,
    );

    notifyListeners();
  }
}
