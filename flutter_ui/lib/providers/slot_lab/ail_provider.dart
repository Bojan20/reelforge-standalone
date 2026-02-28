/// AIL Provider — Authoring Intelligence Layer §9
///
/// Advisory analysis post-PBSE. Cannot block BAKE — only flags/warns/recommends.
/// 10 analysis domains, AIL Score (0-100), ranked recommendations.
///
/// See: FLUXFORGE_MASTER_SPEC.md §9

import 'package:flutter/foundation.dart';
import '../../src/rust/native_ffi.dart';

/// AIL overall status.
enum AilStatusLevel {
  excellent,
  good,
  fair,
  poor,
  critical,
}

extension AilStatusLevelExtension on AilStatusLevel {
  String get displayName {
    switch (this) {
      case AilStatusLevel.excellent: return 'EXCELLENT';
      case AilStatusLevel.good: return 'GOOD';
      case AilStatusLevel.fair: return 'FAIR';
      case AilStatusLevel.poor: return 'POOR';
      case AilStatusLevel.critical: return 'CRITICAL';
    }
  }

  static AilStatusLevel? fromIndex(int index) {
    if (index < 0 || index > 4) return null;
    return AilStatusLevel.values[index];
  }
}

/// Recommendation severity level.
enum AilRecommendationLevel {
  info,
  warning,
  critical,
}

extension AilRecommendationLevelExtension on AilRecommendationLevel {
  String get displayName {
    switch (this) {
      case AilRecommendationLevel.info: return 'INFO';
      case AilRecommendationLevel.warning: return 'WARNING';
      case AilRecommendationLevel.critical: return 'CRITICAL';
    }
  }

  static AilRecommendationLevel? fromIndex(int index) {
    if (index < 0 || index > 2) return null;
    return AilRecommendationLevel.values[index];
  }
}

/// Per-domain analysis result.
class AilDomainResult {
  final int index;
  final String name;
  final double score;
  final double risk;

  const AilDomainResult({
    required this.index,
    required this.name,
    required this.score,
    required this.risk,
  });
}

/// AIL recommendation.
class AilRecommendation {
  final int rank;
  final AilRecommendationLevel level;
  final String title;
  final String description;
  final double impactScore;
  final int domainIndex;

  const AilRecommendation({
    required this.rank,
    required this.level,
    required this.title,
    required this.description,
    required this.impactScore,
    required this.domainIndex,
  });
}

/// AIL fatigue analysis result.
class AilFatigueResult {
  final double fatigueScore;
  final double peakFrequency;
  final double harmonicDensity;
  final double temporalDensity;
  final double recoveryFactor;
  final String riskLevel;

  const AilFatigueResult({
    required this.fatigueScore,
    required this.peakFrequency,
    required this.harmonicDensity,
    required this.temporalDensity,
    required this.recoveryFactor,
    required this.riskLevel,
  });
}

/// AIL voice efficiency result.
class AilVoiceEfficiency {
  final double avgVoices;
  final int peakVoices;
  final int budgetCap;
  final double utilizationPct;
  final double efficiencyScore;

  const AilVoiceEfficiency({
    required this.avgVoices,
    required this.peakVoices,
    required this.budgetCap,
    required this.utilizationPct,
    required this.efficiencyScore,
  });
}

class AilProvider extends ChangeNotifier {
  final NativeFFI? _ffi;

  bool _isRunning = false;
  bool _hasResults = false;
  double _score = 0.0;
  AilStatusLevel _status = AilStatusLevel.excellent;
  bool? _pbsePassed;
  int _simulationSpins = 0;

  List<AilDomainResult> _domainResults = [];
  List<AilRecommendation> _recommendations = [];
  AilFatigueResult? _fatigueResult;
  AilVoiceEfficiency? _voiceEfficiency;
  double _spectralClarityScore = 0.0;
  double _spectralSci = 0.0;
  double _volatilityAlignmentScore = 0.0;

  int _criticalCount = 0;
  int _warningCount = 0;
  int _infoCount = 0;

  AilProvider([this._ffi]);

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get isRunning => _isRunning;
  bool get hasResults => _hasResults;
  double get score => _score;
  AilStatusLevel get status => _status;
  bool? get pbsePassed => _pbsePassed;
  int get simulationSpins => _simulationSpins;

  List<AilDomainResult> get domainResults => List.unmodifiable(_domainResults);
  List<AilRecommendation> get recommendations => List.unmodifiable(_recommendations);
  AilFatigueResult? get fatigueResult => _fatigueResult;
  AilVoiceEfficiency? get voiceEfficiency => _voiceEfficiency;
  double get spectralClarityScore => _spectralClarityScore;
  double get spectralSci => _spectralSci;
  double get volatilityAlignmentScore => _volatilityAlignmentScore;

  int get criticalCount => _criticalCount;
  int get warningCount => _warningCount;
  int get infoCount => _infoCount;
  int get totalRecommendations => _recommendations.length;

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Run full AIL analysis.
  bool runAnalysis() {
    final ffi = _ffi;
    if (ffi == null) return false;

    _isRunning = true;
    notifyListeners();

    final success = ffi.ailRunAnalysis();
    if (success) {
      _refreshState();
    }

    _isRunning = false;
    notifyListeners();
    return success;
  }

  /// Reset AIL state.
  void reset() {
    _ffi?.ailReset();
    _hasResults = false;
    _score = 0.0;
    _status = AilStatusLevel.excellent;
    _pbsePassed = null;
    _simulationSpins = 0;
    _domainResults = [];
    _recommendations = [];
    _fatigueResult = null;
    _voiceEfficiency = null;
    _spectralClarityScore = 0.0;
    _spectralSci = 0.0;
    _volatilityAlignmentScore = 0.0;
    _criticalCount = 0;
    _warningCount = 0;
    _infoCount = 0;
    notifyListeners();
  }

  /// Get JSON report.
  String? getReportJson() => _ffi?.ailReportJson();

  void _refreshState() {
    final ffi = _ffi;
    if (ffi == null) return;

    _hasResults = ffi.ailHasResults();
    if (!_hasResults) return;

    _score = ffi.ailScore();
    final statusIdx = ffi.ailStatus();
    _status = AilStatusLevelExtension.fromIndex(statusIdx) ?? AilStatusLevel.excellent;
    _pbsePassed = ffi.ailPbsePassed();
    _simulationSpins = ffi.ailSimulationSpins();

    // Domain results
    _domainResults = [];
    for (int i = 0; i < 10; i++) {
      final name = ffi.ailDomainName(i) ?? 'Domain $i';
      final score = ffi.ailDomainScore(i);
      final risk = ffi.ailDomainRisk(i);
      if (score >= 0) {
        _domainResults.add(AilDomainResult(
          index: i, name: name, score: score, risk: risk,
        ));
      }
    }

    // Fatigue
    final fatScore = ffi.ailFatigueScore();
    if (fatScore >= 0) {
      final riskIdx = ffi.ailFatigueRiskLevel();
      _fatigueResult = AilFatigueResult(
        fatigueScore: fatScore,
        peakFrequency: ffi.ailFatiguePeakFrequency(),
        harmonicDensity: ffi.ailFatigueHarmonicDensity(),
        temporalDensity: ffi.ailFatigueTemporalDensity(),
        recoveryFactor: ffi.ailFatigueRecoveryFactor(),
        riskLevel: const ['LOW', 'MODERATE', 'HIGH', 'CRITICAL'][riskIdx.clamp(0, 3)],
      );
    }

    // Voice efficiency
    _voiceEfficiency = AilVoiceEfficiency(
      avgVoices: ffi.ailVoiceAvg(),
      peakVoices: ffi.ailVoicePeak(),
      budgetCap: ffi.ailVoiceBudget(),
      utilizationPct: ffi.ailVoiceUtilizationPct(),
      efficiencyScore: ffi.ailVoiceEfficiencyScore(),
    );

    // Spectral clarity
    _spectralSci = ffi.ailSpectralSci();
    _spectralClarityScore = ffi.ailSpectralClarityScore();

    // Volatility alignment
    _volatilityAlignmentScore = ffi.ailVolatilityAlignmentScore();

    // Recommendations
    _criticalCount = ffi.ailCriticalCount();
    _warningCount = ffi.ailWarningCount();
    _infoCount = ffi.ailInfoCount();

    final recCount = ffi.ailRecommendationCount();
    _recommendations = [];
    for (int i = 0; i < recCount; i++) {
      final levelIdx = ffi.ailRecommendationLevel(i);
      final level = AilRecommendationLevelExtension.fromIndex(levelIdx) ?? AilRecommendationLevel.info;
      final title = ffi.ailRecommendationTitle(i) ?? '';
      final desc = ffi.ailRecommendationDescription(i) ?? '';
      final impact = ffi.ailRecommendationImpact(i);
      final domain = ffi.ailRecommendationDomain(i);

      _recommendations.add(AilRecommendation(
        rank: i + 1,
        level: level,
        title: title,
        description: desc,
        impactScore: impact,
        domainIndex: domain,
      ));
    }
  }
}
