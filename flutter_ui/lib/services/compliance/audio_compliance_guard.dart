/// FAZA 4.2.4 — Error Prevention Validators (Audio Compliance Guard)
///
/// **Cilj:** flag audio kombinacije koje krše compliance pravila PRE nego
/// što korisnik čuje rezultat. Tri validator-a koja se izvršavaju u prevent
/// modu (vs `LiveComplianceProvider` koji je post-hoc tracker):
///
/// 1. **LDW Guard** — ako stage je WIN_BIG/MASSIVE/MEGA a `win <= bet * 1.1`,
///    flag-uj kao UKGC LDW violation. "Losses Disguised as Wins" pravilo
///    zabranjuje celebration audio za micro-win-ove.
///
/// 2. **Near-Miss Quota** — ako trenutni near-miss ratio iz `LiveCompliance-
///    Provider` > 0.03 (UKGC cap) i ovaj stage je `ANTICIPATION_TENSION_*`,
///    flag kao "near-miss audio quota exceeded".
///
/// 3. **Celebration LUFS** — ako stage je WIN_BIG/MASSIVE/MEGA i poznata
///    integrated LUFS > -16 (UKGC max za celebration), flag kao loudness
///    violation.
///
/// **API:**
/// - `validate(stage, win, bet, integratedLufs)` → `ComplianceWarning?`
/// - `warnings` stream — ako se warning ne handle inline, listener može
///   da prikaže banner / toast.
///
/// **Singleton** preko GetIt; depends `LiveComplianceProvider` da pristupi
/// snapshot-u za near-miss ratio. NE polluje audio thread — sve operacije
/// su Dart-side, < 1µs po validate-u.
///
/// **Future (Sprint 18+):** kuke u `AudioPlaybackService.playFileToBus` da
/// se warning emituje pre stvarnog play-a + opcionalni suppress mode.
library;

import 'dart:async';

import '../../providers/slot_lab/live_compliance_provider.dart';

/// Severity tier — koristi se za UI color coding + auto-suppress odluku.
enum ComplianceWarningSeverity {
  /// Soft hint — log only, no UI interrupt.
  info,

  /// Yellow tier — UI banner sa "Continue / Cancel" choice.
  warn,

  /// Red tier — UI modal, blokira play dok korisnik ne odluči.
  block,
}

/// One pre-flight compliance warning. Immutable.
class ComplianceWarning {
  /// Short rule code (e.g., `ldw_disguise`, `near_miss_quota`,
  /// `celebration_lufs`).
  final String ruleId;

  /// Human-readable warning text.
  final String message;

  /// Concrete remediation suggestion za UI.
  final String suggestion;

  final ComplianceWarningSeverity severity;

  /// Stage koji je flag-ovan.
  final String stage;

  /// Optional jurisdiction tag (UKGC, MGA, NV…) za multi-jurisdiction filter.
  final String? jurisdiction;

  /// Timestamp emit-a.
  final DateTime timestamp;

  ComplianceWarning({
    required this.ruleId,
    required this.message,
    required this.suggestion,
    required this.severity,
    required this.stage,
    this.jurisdiction,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'rule_id': ruleId,
        'message': message,
        'suggestion': suggestion,
        'severity': severity.name,
        'stage': stage,
        if (jurisdiction != null) 'jurisdiction': jurisdiction,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Pre-flight compliance validator. Stateless osim recently-emitted ring
/// (za UI history panel) i optional `LiveComplianceProvider` ref.
class AudioComplianceGuard {
  AudioComplianceGuard({LiveComplianceProvider? liveProvider})
      : _liveProvider = liveProvider;

  final LiveComplianceProvider? _liveProvider;

  /// UKGC LDW threshold — win <= bet * `_ldwRatioCap` triggers warning.
  /// 1.1 = 10% above bet is still "disguise"-like.
  static const double _ldwRatioCap = 1.1;

  /// UKGC near-miss quota cap — 3% per UKGC RTS 13.
  static const double _nearMissRatioCap = 0.03;

  /// UKGC max integrated LUFS za celebration audio.
  static const double _celebrationLufsCap = -16.0;

  /// Stage substring-i koji aktiviraju LDW + Celebration LUFS pravilo.
  /// Case-insensitive match (uses `.toUpperCase()`).
  static const _winCelebrationMarkers = ['WIN_BIG', 'WIN_MASSIVE', 'WIN_MEGA'];

  /// Stage substring-i koji aktiviraju near-miss quota pravilo.
  static const _nearMissMarkers = ['ANTICIPATION_TENSION'];

  /// Stream emit-a; UI listenuje za banner / toast notification.
  final StreamController<ComplianceWarning> _warningsController =
      StreamController<ComplianceWarning>.broadcast();
  Stream<ComplianceWarning> get warnings => _warningsController.stream;

  /// In-memory ring za UI history panel.
  static const int _ringCapacity = 50;
  final List<ComplianceWarning> _ring = <ComplianceWarning>[];
  List<ComplianceWarning> get recent =>
      List.unmodifiable(_ring.reversed.toList(growable: false));

  /// Vraća prvu validation greška ili `null` ako prolazi. Emituje na
  /// `warnings` stream + puše u ring.
  ///
  /// Parametri:
  /// - `stage` — canonical stage name (npr. `WIN_BIG`)
  /// - `win` / `bet` — current spin context (LDW check)
  /// - `integratedLufs` — opciono, iz audio asset metadata (LUFS check)
  ComplianceWarning? validate({
    required String stage,
    double? win,
    double? bet,
    double? integratedLufs,
  }) {
    final upper = stage.toUpperCase();
    final warning = _runValidators(
      stage: upper,
      win: win,
      bet: bet,
      integratedLufs: integratedLufs,
    );
    if (warning != null) {
      _ring.add(warning);
      if (_ring.length > _ringCapacity) {
        _ring.removeRange(0, _ring.length - _ringCapacity);
      }
      _warningsController.add(warning);
    }
    return warning;
  }

  ComplianceWarning? _runValidators({
    required String stage,
    double? win,
    double? bet,
    double? integratedLufs,
  }) {
    // ── Validator 1: LDW Guard ─────────────────────────────────────────
    final isWinCelebration =
        _winCelebrationMarkers.any((m) => stage.contains(m));
    if (isWinCelebration && win != null && bet != null && bet > 0) {
      final ratio = win / bet;
      if (ratio <= _ldwRatioCap) {
        return ComplianceWarning(
          ruleId: 'ldw_disguise',
          message:
              'WIN celebration audio za micro-win (ratio ${ratio.toStringAsFixed(2)}× bet). '
              'UKGC LDW pravilo zabranjuje celebration sa win ≤ bet × $_ldwRatioCap.',
          suggestion:
              'Suppress big-win sting; switch na neutral feedback (UI_CLICK ili tihi cue).',
          severity: ComplianceWarningSeverity.block,
          stage: stage,
          jurisdiction: 'UKGC',
        );
      }
    }

    // ── Validator 2: Near-Miss Quota ──────────────────────────────────
    final isNearMiss = _nearMissMarkers.any((m) => stage.contains(m));
    if (isNearMiss && _liveProvider != null) {
      final ratio = _liveProvider.snapshot.nearMissRatio;
      if (ratio > _nearMissRatioCap) {
        return ComplianceWarning(
          ruleId: 'near_miss_quota',
          message:
              'Near-miss ratio ${(ratio * 100).toStringAsFixed(1)}% premašuje UKGC cap '
              '${(_nearMissRatioCap * 100).toStringAsFixed(0)}%. '
              'ANTICIPATION audio dalje pojačava percepciju near-miss-a.',
          suggestion:
              'Reduce near-miss frequency u math config, ili duck ANTICIPATION audio '
              'tokom narednih ${(ratio / _nearMissRatioCap * 100).toStringAsFixed(0)} spin-ova.',
          severity: ComplianceWarningSeverity.warn,
          stage: stage,
          jurisdiction: 'UKGC',
        );
      }
    }

    // ── Validator 3: Celebration LUFS ──────────────────────────────────
    if (isWinCelebration && integratedLufs != null) {
      if (integratedLufs > _celebrationLufsCap) {
        return ComplianceWarning(
          ruleId: 'celebration_lufs',
          message:
              'Celebration audio LUFS = ${integratedLufs.toStringAsFixed(1)} dB '
              'premašuje UKGC cap $_celebrationLufsCap dB.',
          suggestion:
              'Apply normalize -3 dB ili switch na quieter sting variant.',
          severity: ComplianceWarningSeverity.warn,
          stage: stage,
          jurisdiction: 'UKGC',
        );
      }
    }

    return null;
  }

  /// Batch validate — koristi se kad korisnik importuje game model i hoće
  /// pre-flight scan svih (stage × audio) parova. Vraća listu warnings;
  /// stream emisije se preskaču (svesno; UI prikazuje listu odjednom).
  List<ComplianceWarning> validateBatch({
    required Map<String, ({double win, double bet, double? lufs})> contexts,
  }) {
    final results = <ComplianceWarning>[];
    for (final entry in contexts.entries) {
      final ctx = entry.value;
      final w = _runValidators(
        stage: entry.key.toUpperCase(),
        win: ctx.win,
        bet: ctx.bet,
        integratedLufs: ctx.lufs,
      );
      if (w != null) results.add(w);
    }
    return results;
  }

  void clearForTest() {
    _ring.clear();
  }

  Future<void> dispose() async {
    _ring.clear();
    await _warningsController.close();
  }
}
