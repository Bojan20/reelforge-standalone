/// AI Co-Pilot™ Service — T5.1–T5.4
///
/// Context-aware suggestion engine that analyzes slot audio projects and
/// produces actionable recommendations based on industry benchmarks.
///
/// Wraps the rf-copilot Rust crate FFI.
/// Pure rule-based, deterministic — no LLM/cloud required.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';
import 'math_audio_bridge_service.dart';
import 'par_import_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Suggestion category (mirrors Rust SuggestionCategory)
enum CopilotCategory {
  voiceBudget,
  eventCoverage,
  winTierCalibration,
  featureAudio,
  responsibleGaming,
  loopCoverage,
  timingBenchmark,
  industryStandard,
  compliance,
  performance;

  static CopilotCategory fromKey(String key) => switch (key) {
    'voice_budget'         => CopilotCategory.voiceBudget,
    'event_coverage'       => CopilotCategory.eventCoverage,
    'win_tier_calibration' => CopilotCategory.winTierCalibration,
    'feature_audio'        => CopilotCategory.featureAudio,
    'responsible_gaming'   => CopilotCategory.responsibleGaming,
    'loop_coverage'        => CopilotCategory.loopCoverage,
    'timing_benchmark'     => CopilotCategory.timingBenchmark,
    'industry_standard'    => CopilotCategory.industryStandard,
    'compliance'           => CopilotCategory.compliance,
    'performance'          => CopilotCategory.performance,
    _                      => CopilotCategory.industryStandard,
  };

  String get displayName => switch (this) {
    CopilotCategory.voiceBudget        => 'Voice Budget',
    CopilotCategory.eventCoverage      => 'Event Coverage',
    CopilotCategory.winTierCalibration => 'Win Tier Calibration',
    CopilotCategory.featureAudio       => 'Feature Audio',
    CopilotCategory.responsibleGaming  => 'Responsible Gaming',
    CopilotCategory.loopCoverage       => 'Loop Coverage',
    CopilotCategory.timingBenchmark    => 'Timing Benchmark',
    CopilotCategory.industryStandard   => 'Industry Standard',
    CopilotCategory.compliance         => 'Compliance',
    CopilotCategory.performance        => 'Performance',
  };

  int get colorValue => switch (this) {
    CopilotCategory.voiceBudget        => 0xFF44AAFF,
    CopilotCategory.eventCoverage      => 0xFF44CC88,
    CopilotCategory.winTierCalibration => 0xFFFFCC44,
    CopilotCategory.featureAudio       => 0xFFCC44CC,
    CopilotCategory.responsibleGaming  => 0xFFCC4444,
    CopilotCategory.loopCoverage       => 0xFF44CCCC,
    CopilotCategory.timingBenchmark    => 0xFF88AACC,
    CopilotCategory.industryStandard   => 0xFF8866FF,
    CopilotCategory.compliance         => 0xFFDD6622,
    CopilotCategory.performance        => 0xFF88CC44,
  };
}

/// Suggestion severity
enum CopilotSeverity {
  info, suggestion, warning, critical;

  static CopilotSeverity fromKey(String key) => switch (key) {
    'critical'   => CopilotSeverity.critical,
    'warning'    => CopilotSeverity.warning,
    'suggestion' => CopilotSeverity.suggestion,
    _            => CopilotSeverity.info,
  };

  String get displayName => switch (this) {
    CopilotSeverity.info       => 'Info',
    CopilotSeverity.suggestion => 'Suggestion',
    CopilotSeverity.warning    => 'Warning',
    CopilotSeverity.critical   => 'Critical',
  };

  int get colorValue => switch (this) {
    CopilotSeverity.info       => 0xFF6688AA,
    CopilotSeverity.suggestion => 0xFF44AACC,
    CopilotSeverity.warning    => 0xFFDD8822,
    CopilotSeverity.critical   => 0xFFCC3333,
  };

  String get icon => switch (this) {
    CopilotSeverity.info       => 'ℹ',
    CopilotSeverity.suggestion => '💡',
    CopilotSeverity.warning    => '⚠',
    CopilotSeverity.critical   => '🔴',
  };
}

/// One actionable Co-Pilot suggestion
class CopilotSuggestion {
  final String ruleId;
  final CopilotCategory category;
  final CopilotSeverity severity;
  final String title;
  final String description;
  final String action;
  final String? affectedEvent;
  final String? benchmarkValue;
  final bool autoApplicable;

  const CopilotSuggestion({
    required this.ruleId,
    required this.category,
    required this.severity,
    required this.title,
    required this.description,
    required this.action,
    this.affectedEvent,
    this.benchmarkValue,
    required this.autoApplicable,
  });

  factory CopilotSuggestion.fromJson(Map<String, dynamic> j) => CopilotSuggestion(
    ruleId:         (j['rule_id'] as String?) ?? '',
    category:       CopilotCategory.fromKey((j['category'] as String?) ?? ''),
    severity:       CopilotSeverity.fromKey((j['severity'] as String?) ?? ''),
    title:          (j['title'] as String?) ?? '',
    description:    (j['description'] as String?) ?? '',
    action:         (j['action'] as String?) ?? '',
    affectedEvent:  j['affected_event'] as String?,
    benchmarkValue: j['benchmark_value'] as String?,
    autoApplicable: (j['auto_applicable'] as bool?) ?? false,
  );
}

/// Complete Co-Pilot analysis report
class CopilotReport {
  final List<CopilotSuggestion> suggestions;
  final int qualityScore;
  final int industryMatchPct;
  final String closestReference;
  final String summary;

  const CopilotReport({
    required this.suggestions,
    required this.qualityScore,
    required this.industryMatchPct,
    required this.closestReference,
    required this.summary,
  });

  factory CopilotReport.fromJson(Map<String, dynamic> j) => CopilotReport(
    suggestions: ((j['suggestions'] as List?) ?? [])
        .map((e) => CopilotSuggestion.fromJson(e as Map<String, dynamic>))
        .toList(),
    qualityScore:    (j['quality_score']    as int?) ?? 0,
    industryMatchPct:(j['industry_match_pct'] as int?) ?? 0,
    closestReference:(j['closest_reference'] as String?) ?? '',
    summary:         (j['summary'] as String?) ?? '',
  );

  List<CopilotSuggestion> get criticals =>
      suggestions.where((s) => s.severity == CopilotSeverity.critical).toList();

  List<CopilotSuggestion> get warnings =>
      suggestions.where((s) => s.severity == CopilotSeverity.warning).toList();

  List<CopilotSuggestion> get autoApplicable =>
      suggestions.where((s) => s.autoApplicable).toList();

  bool get hasCriticals => criticals.isNotEmpty;
}

/// An industry benchmark reference
class IndustryBenchmarkInfo {
  final String name;
  final String description;

  const IndustryBenchmarkInfo({required this.name, required this.description});

  factory IndustryBenchmarkInfo.fromJson(Map<String, dynamic> j) => IndustryBenchmarkInfo(
    name:        (j['name'] as String?) ?? '',
    description: (j['description'] as String?) ?? '',
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// AI Co-Pilot™ Service
class AiCopilotService extends ChangeNotifier {
  CopilotReport? _lastReport;
  bool _isAnalyzing = false;
  String? _lastError;
  List<IndustryBenchmarkInfo> _benchmarks = [];

  CopilotReport? get lastReport => _lastReport;
  bool get isAnalyzing => _isAnalyzing;
  String? get lastError => _lastError;
  List<IndustryBenchmarkInfo> get benchmarks => _benchmarks;

  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Load available industry benchmarks from Rust
  void loadBenchmarks() {
    try {
      final json = NativeFFI.instance.copilotAvailableBenchmarks();
      if (json == null) return;
      final list = jsonDecode(json) as List;
      _benchmarks = list
          .map((e) => IndustryBenchmarkInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  /// Analyze AudioEventMap + PAR document.
  /// Returns CopilotReport or null on failure.
  Future<CopilotReport?> analyze({
    required AudioEventMap audioMap,
    required ParDocument par,
    double? estimatedPeakVoices,
  }) async {
    _isAnalyzing = true;
    _lastError = null;
    notifyListeners();

    try {
      final projectJson = _buildProjectJson(audioMap, par, estimatedPeakVoices);
      final result = await compute(_analyzeInBackground, projectJson);

      if (result == null) {
        _lastError = 'Analysis failed: no output from Co-Pilot engine';
        return null;
      }

      final report = CopilotReport.fromJson(
        jsonDecode(result) as Map<String, dynamic>,
      );
      _lastReport = report;
      notifyListeners();
      return report;
    } catch (e) {
      _lastError = 'Analysis error: $e';
      notifyListeners();
      return null;
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  /// Get quality score color based on value
  static int qualityScoreColor(int score) {
    if (score >= 85) return 0xFF44CC44;
    if (score >= 70) return 0xFF88AA44;
    if (score >= 50) return 0xFFDD8822;
    return 0xFFCC3333;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private
  // ──────────────────────────────────────────────────────────────────────────

  String _buildProjectJson(
    AudioEventMap audioMap,
    ParDocument par,
    double? estimatedPeakVoices,
  ) {
    final events = audioMap.events.map((e) => {
      'name': e.name,
      'category': _categoryKey(e.category),
      'tier': e.tier.name,
      'duration_ms': e.suggestedDurationMs,
      'voice_count': e.suggestedVoiceCount,
      'is_required': e.isRequired,
      'can_loop': e.name.contains('SPIN') && e.name != 'SPIN_START' && e.name != 'SPIN_END',
      'trigger_probability': e.triggerProbability,
      'audio_weight': e.audioWeight,
      'rtp_contribution': e.rtpContribution,
    }).toList();

    return jsonEncode({
      'game_name': par.gameName,
      'game_id': par.gameId,
      'rtp_target': par.rtpTarget,
      'volatility': par.volatility.name.toUpperCase(),
      'voice_budget': 48,
      'reels': par.reels,
      'rows': par.rows,
      'win_mechanism': par.waysToWin != null
          ? '${par.waysToWin} ways'
          : '${par.paylines} paylines',
      'audio_events': events,
      'estimated_peak_voices': estimatedPeakVoices,
    });
  }

  String _categoryKey(AudioEventCategory cat) => switch (cat) {
    AudioEventCategory.baseGame => 'BaseGame',
    AudioEventCategory.win      => 'Win',
    AudioEventCategory.nearMiss => 'NearMiss',
    AudioEventCategory.feature  => 'Feature',
    AudioEventCategory.jackpot  => 'Jackpot',
    AudioEventCategory.special  => 'Special',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Background isolate
// ─────────────────────────────────────────────────────────────────────────────

String? _analyzeInBackground(String projectJson) {
  return NativeFFI.instance.copilotAnalyze(projectJson);
}
