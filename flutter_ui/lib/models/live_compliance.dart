/// FLUX_MASTER_TODO 3.4.1 / 3.4.3 / 3.4.4 — Live compliance models.
///
/// Mirror Rust types iz `crates/rf-rgai/src/live.rs`. Decoder za JSON
/// koji izlazi iz `rgai_live_snapshot_json()` FFI poziv-a; UI traffic
/// lights, LDW guard, near-miss tracker svi konzumiraju ove modele.

library;

/// Per-jurisdiction trenutni status (paralel za Rust enum).
enum JurisdictionStatus {
  /// Sve metrike ispod 80% threshold-a — zeleno svetlo.
  ok,
  /// Bar jedna metrika u 80–100% threshold-a — žuto svetlo.
  warn,
  /// Bar jedna metrika preko threshold-a — crveno svetlo, gate aktivan.
  violation;

  /// Parser iz JSON string-a (`"ok" | "warn" | "violation"`).
  /// Nepoznata vrednost → `ok` (defensive default — neka UI bude zeleno
  /// pre nego da krše korisnika sa lažnim alertom).
  static JurisdictionStatus fromJson(String? raw) {
    return switch (raw?.toLowerCase()) {
      'violation' => JurisdictionStatus.violation,
      'warn' => JurisdictionStatus.warn,
      _ => JurisdictionStatus.ok,
    };
  }

  /// Display label za toast/tooltip.
  String get label => switch (this) {
        JurisdictionStatus.ok => 'OK',
        JurisdictionStatus.warn => 'WARN',
        JurisdictionStatus.violation => 'VIOLATION',
      };
}

/// Per-jurisdiction live entry — paralel za Rust `JurisdictionLive`.
class JurisdictionLive {
  /// Code (`"UKGC"`, `"MGA"`, ...). Mapa na `Jurisdiction::code()`.
  final String code;

  /// Trenutni status (Ok / Warn / Violation).
  final JurisdictionStatus status;

  /// Worst metric utilization — `"ldw"`, `"near_miss"`, `"arousal"`.
  final String worstMetric;

  /// Worst metric utilization ratio (`current / threshold`).
  /// `0.0` = unused, `1.0` = exact threshold, `> 1.0` = violation.
  final double worstUtilization;

  const JurisdictionLive({
    required this.code,
    required this.status,
    required this.worstMetric,
    required this.worstUtilization,
  });

  /// Parser iz Rust JSON object-a.
  factory JurisdictionLive.fromJson(Map<String, dynamic> json) {
    return JurisdictionLive(
      code: json['code'] as String? ?? 'UNKNOWN',
      status: JurisdictionStatus.fromJson(json['status'] as String?),
      worstMetric: json['worst_metric'] as String? ?? 'ldw',
      worstUtilization: (json['worst_utilization'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Snapshot za UI poll. Mirror Rust `LiveComplianceSnapshot`.
class LiveComplianceSnapshot {
  /// Ukupan broj spin-ova od `init()` ili `reset()`.
  final int spinsTotal;

  /// Broj LDW spin-ova (win ≈ bet).
  final int ldwCount;

  /// Tekući LDW ratio (`ldw_count / spins_total`, 0 kada nema spin-ova).
  final double ldwRatio;

  /// Broj near-miss spin-ova.
  final int nearMissCount;

  /// Tekući near-miss ratio (`near_miss_count / spins_total`).
  final double nearMissRatio;

  /// Per-jurisdiction status.
  final List<JurisdictionLive> jurisdictions;

  const LiveComplianceSnapshot({
    required this.spinsTotal,
    required this.ldwCount,
    required this.ldwRatio,
    required this.nearMissCount,
    required this.nearMissRatio,
    required this.jurisdictions,
  });

  /// Default empty snapshot (pre prvi spin). UI ga koristi u idle state-u.
  factory LiveComplianceSnapshot.empty() {
    return const LiveComplianceSnapshot(
      spinsTotal: 0,
      ldwCount: 0,
      ldwRatio: 0.0,
      nearMissCount: 0,
      nearMissRatio: 0.0,
      jurisdictions: [],
    );
  }

  /// Parser iz Rust JSON object-a. Defensive — null fields → default
  /// vrednosti tako da malformed snapshot ne ruši UI.
  factory LiveComplianceSnapshot.fromJson(Map<String, dynamic> json) {
    final juris = (json['jurisdictions'] as List<dynamic>?) ?? [];
    return LiveComplianceSnapshot(
      spinsTotal: (json['spins_total'] as num?)?.toInt() ?? 0,
      ldwCount: (json['ldw_count'] as num?)?.toInt() ?? 0,
      ldwRatio: (json['ldw_ratio'] as num?)?.toDouble() ?? 0.0,
      nearMissCount: (json['near_miss_count'] as num?)?.toInt() ?? 0,
      nearMissRatio: (json['near_miss_ratio'] as num?)?.toDouble() ?? 0.0,
      jurisdictions: juris
          .whereType<Map<String, dynamic>>()
          .map(JurisdictionLive.fromJson)
          .toList(growable: false),
    );
  }

  /// True ako bilo koja jurisdiction ima `Violation` status — UI koristi
  /// za "all-red" alert state (ozbiljnija boja, audio cue).
  bool get hasViolation =>
      jurisdictions.any((j) => j.status == JurisdictionStatus.violation);

  /// True ako bilo koja jurisdiction ima ≥ `Warn` status — UI ovo gleda
  /// pre nego da pokrene slabiji "warning" pulse na badge.
  bool get hasWarning => jurisdictions
      .any((j) => j.status != JurisdictionStatus.ok);
}
