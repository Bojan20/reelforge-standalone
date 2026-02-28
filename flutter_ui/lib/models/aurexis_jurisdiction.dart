import 'dart:convert';

// ═══════════════════════════════════════════════════════════════════════════════
// AUREXIS™ JURISDICTION ENGINE
//
// Jurisdiction-aware audio compliance system.
// Each jurisdiction defines limits on win celebration audio, session duration
// warnings, and responsible gaming audio behavior.
//
// One project → multiple jurisdictions → automatically compliant audio packages.
// ═══════════════════════════════════════════════════════════════════════════════

/// Supported regulatory jurisdictions.
enum AurexisJurisdiction {
  /// No jurisdiction — unrestricted.
  none,

  /// UK Gambling Commission.
  ukgc,

  /// Malta Gaming Authority.
  mga,

  /// Nevada / New Jersey (GLI-11).
  gli11,

  /// Ontario (Canada).
  ontario,

  /// Australia (Victoria/NSW).
  australia;

  String get label => switch (this) {
    none => 'None (Unrestricted)',
    ukgc => 'UK (UKGC)',
    mga => 'Malta (MGA)',
    gli11 => 'Nevada/NJ (GLI-11)',
    ontario => 'Ontario (Canada)',
    australia => 'Australia (VIC/NSW)',
  };

  String get code => switch (this) {
    none => 'NONE',
    ukgc => 'UKGC',
    mga => 'MGA',
    gli11 => 'GLI11',
    ontario => 'ONT',
    australia => 'AUS',
  };
}

/// Jurisdiction-specific audio compliance rules.
class JurisdictionRules {
  /// Maximum win celebration audio duration (seconds). 0 = unrestricted.
  final double maxCelebrationDurationS;

  /// Whether "Loss Disguised as Win" (LDW) audio suppression is required.
  final bool ldwSuppression;

  /// Maximum autoplay session duration before audio warning (minutes). 0 = no limit.
  final double autoplayWarningMinutes;

  /// Whether session time audio cues are required.
  final bool sessionTimeCues;

  /// Maximum volume boost during win celebrations (dB above baseline).
  final double maxWinVolumeBoostDb;

  /// Whether the word "WIN" or similar celebratory labels are restricted in audio.
  final bool celebrationLabelRestriction;

  /// Maximum escalation multiplier allowed (caps width/harmonic/reverb growth).
  final double maxEscalationMultiplier;

  /// Minimum fatigue regulation aggressiveness (0.0-1.0). Higher = more protection.
  final double minFatigueRegulation;

  /// Required cooldown between consecutive win celebrations (seconds).
  final double celebrationCooldownS;

  /// Whether deterministic replay verification is required for audits.
  final bool requireDeterministicVerification;

  /// Notes about this jurisdiction's specific requirements.
  final String notes;

  const JurisdictionRules({
    this.maxCelebrationDurationS = 0,
    this.ldwSuppression = false,
    this.autoplayWarningMinutes = 0,
    this.sessionTimeCues = false,
    this.maxWinVolumeBoostDb = 12.0,
    this.celebrationLabelRestriction = false,
    this.maxEscalationMultiplier = 10.0,
    this.minFatigueRegulation = 0.0,
    this.celebrationCooldownS = 0,
    this.requireDeterministicVerification = false,
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
    'maxCelebrationDurationS': maxCelebrationDurationS,
    'ldwSuppression': ldwSuppression,
    'autoplayWarningMinutes': autoplayWarningMinutes,
    'sessionTimeCues': sessionTimeCues,
    'maxWinVolumeBoostDb': maxWinVolumeBoostDb,
    'celebrationLabelRestriction': celebrationLabelRestriction,
    'maxEscalationMultiplier': maxEscalationMultiplier,
    'minFatigueRegulation': minFatigueRegulation,
    'celebrationCooldownS': celebrationCooldownS,
    'requireDeterministicVerification': requireDeterministicVerification,
    'notes': notes,
  };

  factory JurisdictionRules.fromJson(Map<String, dynamic> json) =>
      JurisdictionRules(
        maxCelebrationDurationS:
            (json['maxCelebrationDurationS'] as num?)?.toDouble() ?? 0,
        ldwSuppression: json['ldwSuppression'] as bool? ?? false,
        autoplayWarningMinutes:
            (json['autoplayWarningMinutes'] as num?)?.toDouble() ?? 0,
        sessionTimeCues: json['sessionTimeCues'] as bool? ?? false,
        maxWinVolumeBoostDb:
            (json['maxWinVolumeBoostDb'] as num?)?.toDouble() ?? 12.0,
        celebrationLabelRestriction:
            json['celebrationLabelRestriction'] as bool? ?? false,
        maxEscalationMultiplier:
            (json['maxEscalationMultiplier'] as num?)?.toDouble() ?? 10.0,
        minFatigueRegulation:
            (json['minFatigueRegulation'] as num?)?.toDouble() ?? 0.0,
        celebrationCooldownS:
            (json['celebrationCooldownS'] as num?)?.toDouble() ?? 0,
        requireDeterministicVerification:
            json['requireDeterministicVerification'] as bool? ?? false,
        notes: json['notes'] as String? ?? '',
      );
}

/// Built-in jurisdiction rule definitions.
class JurisdictionDatabase {
  JurisdictionDatabase._();

  static const Map<AurexisJurisdiction, JurisdictionRules> _rules = {
    AurexisJurisdiction.none: JurisdictionRules(
      notes: 'No restrictions. Full AUREXIS intelligence active.',
    ),

    AurexisJurisdiction.ukgc: JurisdictionRules(
      maxCelebrationDurationS: 5.0,
      ldwSuppression: true,
      autoplayWarningMinutes: 60,
      sessionTimeCues: true,
      maxWinVolumeBoostDb: 6.0,
      celebrationLabelRestriction: true,
      maxEscalationMultiplier: 3.0,
      minFatigueRegulation: 0.5,
      celebrationCooldownS: 2.0,
      requireDeterministicVerification: true,
      notes:
          'UKGC: LDW suppression mandatory. Celebration duration and volume '
          'capped. Session time warnings required every 60 minutes.',
    ),

    AurexisJurisdiction.mga: JurisdictionRules(
      maxCelebrationDurationS: 10.0,
      ldwSuppression: false,
      autoplayWarningMinutes: 0,
      sessionTimeCues: false,
      maxWinVolumeBoostDb: 9.0,
      maxEscalationMultiplier: 5.0,
      minFatigueRegulation: 0.2,
      requireDeterministicVerification: true,
      notes: 'MGA: Standard EU requirements. Moderate escalation limits.',
    ),

    AurexisJurisdiction.gli11: JurisdictionRules(
      maxCelebrationDurationS: 0, // No specific limit
      ldwSuppression: false,
      autoplayWarningMinutes: 0,
      sessionTimeCues: false,
      maxWinVolumeBoostDb: 12.0,
      maxEscalationMultiplier: 10.0,
      minFatigueRegulation: 0.1,
      requireDeterministicVerification: true,
      notes:
          'GLI-11: No random() allowed — deterministic seed only. '
          'Full replay verification required for compliance testing.',
    ),

    AurexisJurisdiction.ontario: JurisdictionRules(
      maxCelebrationDurationS: 8.0,
      ldwSuppression: true,
      autoplayWarningMinutes: 30,
      sessionTimeCues: true,
      maxWinVolumeBoostDb: 6.0,
      celebrationLabelRestriction: true,
      maxEscalationMultiplier: 4.0,
      minFatigueRegulation: 0.4,
      celebrationCooldownS: 1.5,
      requireDeterministicVerification: false,
      notes:
          'Ontario (AGCO): LDW suppression, session warnings every 30 minutes, '
          'moderate celebration limits.',
    ),

    AurexisJurisdiction.australia: JurisdictionRules(
      maxCelebrationDurationS: 3.0,
      ldwSuppression: true,
      autoplayWarningMinutes: 30,
      sessionTimeCues: true,
      maxWinVolumeBoostDb: 4.0,
      celebrationLabelRestriction: true,
      maxEscalationMultiplier: 2.5,
      minFatigueRegulation: 0.6,
      celebrationCooldownS: 3.0,
      requireDeterministicVerification: false,
      notes:
          'Australia: Strictest celebration limits. Very short win audio, '
          'strong fatigue regulation, LDW suppression, frequent session warnings.',
    ),
  };

  /// Get rules for a jurisdiction.
  static JurisdictionRules getRules(AurexisJurisdiction jurisdiction) {
    return _rules[jurisdiction] ?? const JurisdictionRules();
  }

  /// Get all jurisdictions.
  static List<AurexisJurisdiction> get allJurisdictions =>
      AurexisJurisdiction.values;
}

/// Compliance check result for a single rule.
class ComplianceCheck {
  final String ruleName;
  final bool passed;
  final String detail;

  const ComplianceCheck({
    required this.ruleName,
    required this.passed,
    this.detail = '',
  });
}

/// Full compliance report for a jurisdiction.
class JurisdictionComplianceReport {
  final AurexisJurisdiction jurisdiction;
  final List<ComplianceCheck> checks;
  final DateTime timestamp;

  JurisdictionComplianceReport({
    required this.jurisdiction,
    required this.checks,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get allPassed => checks.every((c) => c.passed);
  int get passedCount => checks.where((c) => c.passed).length;
  int get failedCount => checks.where((c) => !c.passed).length;
  int get totalCount => checks.length;

  String toJsonString() => jsonEncode({
    'jurisdiction': jurisdiction.code,
    'timestamp': timestamp.toIso8601String(),
    'allPassed': allPassed,
    'passed': passedCount,
    'failed': failedCount,
    'total': totalCount,
    'checks': checks.map((c) => {
      'rule': c.ruleName,
      'passed': c.passed,
      'detail': c.detail,
    }).toList(),
  });
}

/// Engine that validates AUREXIS configuration against jurisdiction rules.
class JurisdictionComplianceEngine {
  JurisdictionComplianceEngine._();

  /// Run a full compliance check against the given jurisdiction.
  static JurisdictionComplianceReport checkCompliance({
    required AurexisJurisdiction jurisdiction,
    required double currentEscalationMultiplier,
    required double currentFatigueRegulation,
    required double currentWinVolumeBoostDb,
    required double currentCelebrationDurationS,
    required bool isDeterministic,
    required bool hasLdwSuppression,
    required bool hasSessionTimeCues,
  }) {
    final rules = JurisdictionDatabase.getRules(jurisdiction);
    final checks = <ComplianceCheck>[];

    // Escalation multiplier
    if (rules.maxEscalationMultiplier < 10.0) {
      checks.add(ComplianceCheck(
        ruleName: 'Escalation Multiplier',
        passed: currentEscalationMultiplier <= rules.maxEscalationMultiplier,
        detail:
            'Current: ${currentEscalationMultiplier.toStringAsFixed(1)}x, '
            'Max: ${rules.maxEscalationMultiplier.toStringAsFixed(1)}x',
      ));
    }

    // Fatigue regulation
    if (rules.minFatigueRegulation > 0) {
      checks.add(ComplianceCheck(
        ruleName: 'Fatigue Regulation',
        passed: currentFatigueRegulation >= rules.minFatigueRegulation,
        detail:
            'Current: ${currentFatigueRegulation.toStringAsFixed(2)}, '
            'Min: ${rules.minFatigueRegulation.toStringAsFixed(2)}',
      ));
    }

    // Win volume boost
    if (rules.maxWinVolumeBoostDb < 12.0) {
      checks.add(ComplianceCheck(
        ruleName: 'Win Volume Boost',
        passed: currentWinVolumeBoostDb <= rules.maxWinVolumeBoostDb,
        detail:
            'Current: ${currentWinVolumeBoostDb.toStringAsFixed(1)} dB, '
            'Max: ${rules.maxWinVolumeBoostDb.toStringAsFixed(1)} dB',
      ));
    }

    // Celebration duration
    if (rules.maxCelebrationDurationS > 0) {
      checks.add(ComplianceCheck(
        ruleName: 'Celebration Duration',
        passed: currentCelebrationDurationS <= rules.maxCelebrationDurationS,
        detail:
            'Current: ${currentCelebrationDurationS.toStringAsFixed(1)}s, '
            'Max: ${rules.maxCelebrationDurationS.toStringAsFixed(1)}s',
      ));
    }

    // LDW suppression
    if (rules.ldwSuppression) {
      checks.add(ComplianceCheck(
        ruleName: 'LDW Suppression',
        passed: hasLdwSuppression,
        detail: hasLdwSuppression ? 'Active' : 'Not configured',
      ));
    }

    // Deterministic verification
    if (rules.requireDeterministicVerification) {
      checks.add(ComplianceCheck(
        ruleName: 'Deterministic Verification',
        passed: isDeterministic,
        detail: isDeterministic ? 'Deterministic mode active' : 'Non-deterministic',
      ));
    }

    // Session time cues
    if (rules.sessionTimeCues) {
      checks.add(ComplianceCheck(
        ruleName: 'Session Time Cues',
        passed: hasSessionTimeCues,
        detail: hasSessionTimeCues ? 'Configured' : 'Not configured',
      ));
    }

    return JurisdictionComplianceReport(
      jurisdiction: jurisdiction,
      checks: checks,
    );
  }

  /// Get the engine config overrides needed for a jurisdiction.
  /// These cap values that exceed jurisdiction limits.
  static Map<String, dynamic> getConfigOverrides(AurexisJurisdiction jurisdiction) {
    final rules = JurisdictionDatabase.getRules(jurisdiction);
    final overrides = <String, dynamic>{};

    // Cap escalation
    if (rules.maxEscalationMultiplier < 10.0) {
      final capWidth = 1.0 + rules.maxEscalationMultiplier * 0.2;
      overrides['escalation'] = {
        'width_max': capWidth.clamp(1.5, 3.0),
        'harmonic_max': (1.0 + rules.maxEscalationMultiplier * 0.15).clamp(1.2, 2.0),
        'sub_max_db': (rules.maxEscalationMultiplier * 1.5).clamp(3.0, 12.0),
        'reverb_max_ms': (rules.maxEscalationMultiplier * 200).clamp(500, 2000),
      };
    }

    // Enforce minimum fatigue
    if (rules.minFatigueRegulation > 0.2) {
      overrides['fatigue'] = {
        'max_hf_atten_db': -3.0 - rules.minFatigueRegulation * 6.0,
        'max_transient_smooth': 0.3 + rules.minFatigueRegulation * 0.5,
        'rms_threshold_db': -18.0 + (1.0 - rules.minFatigueRegulation) * 8.0,
      };
    }

    return overrides;
  }
}
