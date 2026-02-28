import 'dart:convert';

/// AUREXIS™ QA Framework — Dart-side quality assurance tools.
///
/// Provides automated validation of AUREXIS configuration,
/// coverage analysis, and deterministic replay verification.

/// QA check category.
enum QaCategory {
  /// Configuration consistency checks.
  config,

  /// Coverage analysis (are all events covered?).
  coverage,

  /// Determinism verification.
  determinism,

  /// Performance checks (memory, CPU budget).
  performance,

  /// Compliance readiness.
  compliance,

  /// Audio quality checks.
  audioQuality;

  String get label => switch (this) {
        config => 'Config',
        coverage => 'Coverage',
        determinism => 'Determinism',
        performance => 'Performance',
        compliance => 'Compliance',
        audioQuality => 'Audio Quality',
      };
}

/// Result of a single QA check.
enum QaResult {
  pass,
  warn,
  fail,
  skip;

  String get label => switch (this) {
        pass => 'PASS',
        warn => 'WARN',
        fail => 'FAIL',
        skip => 'SKIP',
      };
}

/// A single QA check definition and result.
class QaCheck {
  /// Check identifier.
  final String id;

  /// Human-readable name.
  final String name;

  /// Category this check belongs to.
  final QaCategory category;

  /// Result of the check.
  final QaResult result;

  /// Detailed message explaining the result.
  final String detail;

  /// Expected value (for comparison).
  final String? expected;

  /// Actual value found.
  final String? actual;

  const QaCheck({
    required this.id,
    required this.name,
    required this.category,
    required this.result,
    this.detail = '',
    this.expected,
    this.actual,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.name,
        'result': result.name,
        'detail': detail,
        if (expected != null) 'expected': expected,
        if (actual != null) 'actual': actual,
      };
}

/// Complete QA report.
class QaReport {
  /// When the report was generated.
  final DateTime timestamp;

  /// All checks that were run.
  final List<QaCheck> checks;

  /// Engine configuration snapshot at time of check.
  final Map<String, dynamic>? configSnapshot;

  QaReport({
    DateTime? timestamp,
    required this.checks,
    this.configSnapshot,
  }) : timestamp = timestamp ?? DateTime.now();

  int get totalCount => checks.length;
  int get passCount => checks.where((c) => c.result == QaResult.pass).length;
  int get warnCount => checks.where((c) => c.result == QaResult.warn).length;
  int get failCount => checks.where((c) => c.result == QaResult.fail).length;
  int get skipCount => checks.where((c) => c.result == QaResult.skip).length;

  bool get allPassed => failCount == 0;
  double get passPercent => totalCount > 0 ? passCount / totalCount : 0.0;

  List<QaCheck> byCategory(QaCategory category) =>
      checks.where((c) => c.category == category).toList();

  String toJsonString() => jsonEncode({
        'timestamp': timestamp.toIso8601String(),
        'total': totalCount,
        'passed': passCount,
        'warned': warnCount,
        'failed': failCount,
        'skipped': skipCount,
        'checks': checks.map((c) => c.toJson()).toList(),
      });
}

/// Pre-defined QA check suite for AUREXIS.
class AurexisQaEngine {
  AurexisQaEngine._();

  /// Run full QA suite against current AUREXIS state.
  static QaReport runFullSuite({
    required bool engineInitialized,
    required double rtp,
    required double fatigueIndex,
    required double escalationMultiplier,
    required double energyDensity,
    required int voiceCount,
    required double stereoWidth,
    required double memoryUsedMb,
    required double memoryBudgetMb,
    required bool isDeterministic,
    required String jurisdictionCode,
    required String profileId,
  }) {
    final checks = <QaCheck>[];

    // ═══ CONFIG CHECKS ═══
    checks.add(QaCheck(
      id: 'cfg_engine',
      name: 'Engine Initialized',
      category: QaCategory.config,
      result: engineInitialized ? QaResult.pass : QaResult.fail,
      detail: engineInitialized ? 'Engine is running' : 'Engine not initialized',
    ));

    checks.add(QaCheck(
      id: 'cfg_profile',
      name: 'Profile Loaded',
      category: QaCategory.config,
      result: profileId.isNotEmpty ? QaResult.pass : QaResult.fail,
      detail: 'Active profile: $profileId',
    ));

    checks.add(QaCheck(
      id: 'cfg_rtp',
      name: 'RTP Range Valid',
      category: QaCategory.config,
      result: (rtp >= 85.0 && rtp <= 99.5) ? QaResult.pass : QaResult.fail,
      detail: 'RTP: ${rtp.toStringAsFixed(1)}%',
      expected: '85.0-99.5%',
      actual: '${rtp.toStringAsFixed(1)}%',
    ));

    // ═══ COVERAGE CHECKS ═══
    checks.add(QaCheck(
      id: 'cov_voices',
      name: 'Voice Allocation',
      category: QaCategory.coverage,
      result: voiceCount > 0
          ? voiceCount <= 32
              ? QaResult.pass
              : QaResult.warn
          : QaResult.fail,
      detail: '$voiceCount voices active',
      expected: '1-32',
      actual: '$voiceCount',
    ));

    checks.add(QaCheck(
      id: 'cov_stereo',
      name: 'Stereo Width Range',
      category: QaCategory.coverage,
      result: (stereoWidth >= 0.0 && stereoWidth <= 2.0) ? QaResult.pass : QaResult.warn,
      detail: 'Width: ${stereoWidth.toStringAsFixed(2)}',
      expected: '0.0-2.0',
      actual: stereoWidth.toStringAsFixed(2),
    ));

    // ═══ DETERMINISM CHECKS ═══
    checks.add(QaCheck(
      id: 'det_mode',
      name: 'Deterministic Mode',
      category: QaCategory.determinism,
      result: isDeterministic ? QaResult.pass : QaResult.warn,
      detail: isDeterministic ? 'Deterministic seed active' : 'Non-deterministic',
    ));

    // ═══ PERFORMANCE CHECKS ═══
    checks.add(QaCheck(
      id: 'perf_memory',
      name: 'Memory Budget',
      category: QaCategory.performance,
      result: memoryUsedMb <= memoryBudgetMb
          ? memoryUsedMb > memoryBudgetMb * 0.8
              ? QaResult.warn
              : QaResult.pass
          : QaResult.fail,
      detail: '${memoryUsedMb.toStringAsFixed(1)}/${memoryBudgetMb.toStringAsFixed(1)} MB',
      expected: '<= ${memoryBudgetMb.toStringAsFixed(1)} MB',
      actual: '${memoryUsedMb.toStringAsFixed(1)} MB',
    ));

    checks.add(QaCheck(
      id: 'perf_fatigue',
      name: 'Fatigue Level',
      category: QaCategory.performance,
      result: fatigueIndex < 0.6
          ? QaResult.pass
          : fatigueIndex < 0.8
              ? QaResult.warn
              : QaResult.fail,
      detail: '${(fatigueIndex * 100).toStringAsFixed(0)}%',
      expected: '< 60%',
      actual: '${(fatigueIndex * 100).toStringAsFixed(0)}%',
    ));

    checks.add(QaCheck(
      id: 'perf_energy',
      name: 'Energy Density',
      category: QaCategory.performance,
      result: energyDensity < 0.9
          ? QaResult.pass
          : energyDensity < 1.0
              ? QaResult.warn
              : QaResult.fail,
      detail: '${(energyDensity * 100).toStringAsFixed(0)}%',
      expected: '< 90%',
      actual: '${(energyDensity * 100).toStringAsFixed(0)}%',
    ));

    // ═══ COMPLIANCE CHECKS ═══
    checks.add(QaCheck(
      id: 'comp_jurisdiction',
      name: 'Jurisdiction Set',
      category: QaCategory.compliance,
      result: jurisdictionCode.isNotEmpty ? QaResult.pass : QaResult.skip,
      detail: jurisdictionCode.isNotEmpty
          ? 'Jurisdiction: $jurisdictionCode'
          : 'No jurisdiction configured',
    ));

    checks.add(QaCheck(
      id: 'comp_escalation',
      name: 'Escalation Within Limits',
      category: QaCategory.compliance,
      result: escalationMultiplier <= 10.0
          ? escalationMultiplier <= 5.0
              ? QaResult.pass
              : QaResult.warn
          : QaResult.fail,
      detail: '${escalationMultiplier.toStringAsFixed(1)}x',
      expected: '<= 10.0x',
      actual: '${escalationMultiplier.toStringAsFixed(1)}x',
    ));

    // ═══ AUDIO QUALITY CHECKS ═══
    checks.add(QaCheck(
      id: 'aq_clipping',
      name: 'No Clipping',
      category: QaCategory.audioQuality,
      result: escalationMultiplier < 8.0 ? QaResult.pass : QaResult.warn,
      detail: escalationMultiplier < 8.0
          ? 'Escalation within safe range'
          : 'High escalation may cause clipping',
    ));

    checks.add(QaCheck(
      id: 'aq_headroom',
      name: 'Headroom Adequate',
      category: QaCategory.audioQuality,
      result: energyDensity < 0.85 ? QaResult.pass : QaResult.warn,
      detail: 'Energy density: ${(energyDensity * 100).toStringAsFixed(0)}%',
    ));

    return QaReport(checks: checks);
  }
}
