/// DRC Provider — Deterministic Replay Core + Certification Gate §10
///
/// Full certification pipeline: PBSE + DRC + Safety Envelope + Manifest.
/// 5-stage certification with pass/fail per stage.
///
/// See: FLUXFORGE_MASTER_SPEC.md §10

import 'package:flutter/foundation.dart';
import '../../src/rust/native_ffi.dart';

/// Certification status.
enum CertificationStatusLevel {
  pending,
  certified,
  failed,
}

extension CertificationStatusExtension on CertificationStatusLevel {
  String get displayName {
    switch (this) {
      case CertificationStatusLevel.pending: return 'PENDING';
      case CertificationStatusLevel.certified: return 'CERTIFIED';
      case CertificationStatusLevel.failed: return 'FAILED';
    }
  }

  static CertificationStatusLevel fromIndex(int index) {
    switch (index) {
      case 1: return CertificationStatusLevel.certified;
      case 2: return CertificationStatusLevel.failed;
      default: return CertificationStatusLevel.pending;
    }
  }
}

/// A single certification stage result.
class CertStageResult {
  final int index;
  final String name;
  final bool passed;
  final String details;

  const CertStageResult({
    required this.index,
    required this.name,
    required this.passed,
    required this.details,
  });
}

/// Safety envelope metrics.
class EnvelopeMetrics {
  final bool passed;
  final double peakEnergy;
  final int peakVoices;
  final int maxPeakDuration;
  final double peakSci;
  final double peakSessionPct;
  final int violationCount;

  const EnvelopeMetrics({
    required this.passed,
    required this.peakEnergy,
    required this.peakVoices,
    required this.maxPeakDuration,
    required this.peakSci,
    required this.peakSessionPct,
    required this.violationCount,
  });
}

/// Safety limits (hard caps).
class SafetyLimitsData {
  final double maxEnergy;
  final int maxPeakDuration;
  final int maxVoices;
  final int maxHarmonicDensity;
  final double maxSci;
  final double maxPeakSessionPct;

  const SafetyLimitsData({
    required this.maxEnergy,
    required this.maxPeakDuration,
    required this.maxVoices,
    required this.maxHarmonicDensity,
    required this.maxSci,
    required this.maxPeakSessionPct,
  });
}

/// DRC replay metrics.
class ReplayMetrics {
  final bool passed;
  final int totalFrames;
  final int mismatchCount;
  final String? recordedHash;
  final String? replayHash;

  const ReplayMetrics({
    required this.passed,
    required this.totalFrames,
    required this.mismatchCount,
    this.recordedHash,
    this.replayHash,
  });
}

class DrcProvider extends ChangeNotifier {
  final NativeFFI? _ffi;

  bool _isRunning = false;
  bool _hasResult = false;
  bool _isCertified = false;
  CertificationStatusLevel _status = CertificationStatusLevel.pending;

  List<CertStageResult> _stages = [];
  List<String> _blockingFailures = [];

  // Manifest
  int _manifestHash = 0;
  int _configBundleHash = 0;
  String _manifestVersion = '';

  // Safety envelope
  EnvelopeMetrics? _envelopeMetrics;
  SafetyLimitsData? _safetyLimits;

  // DRC replay
  ReplayMetrics? _replayMetrics;

  DrcProvider([this._ffi]);

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get isRunning => _isRunning;
  bool get hasResult => _hasResult;
  bool get isCertified => _isCertified;
  CertificationStatusLevel get status => _status;

  List<CertStageResult> get stages => List.unmodifiable(_stages);
  List<String> get blockingFailures => List.unmodifiable(_blockingFailures);
  int get passedStageCount => _stages.where((s) => s.passed).length;
  int get totalStageCount => _stages.length;

  int get manifestHash => _manifestHash;
  int get configBundleHash => _configBundleHash;
  String get manifestVersion => _manifestVersion;

  EnvelopeMetrics? get envelopeMetrics => _envelopeMetrics;
  SafetyLimitsData? get safetyLimits => _safetyLimits;
  ReplayMetrics? get replayMetrics => _replayMetrics;

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Run full certification pipeline.
  bool runCertification() {
    final ffi = _ffi;
    if (ffi == null) return false;

    _isRunning = true;
    notifyListeners();

    final certified = ffi.drcRunCertification();
    _refreshState();

    _isRunning = false;
    notifyListeners();
    return certified;
  }

  /// Run certification with custom spin count.
  bool runCertificationWithSpins(int spinCount) {
    final ffi = _ffi;
    if (ffi == null) return false;

    _isRunning = true;
    notifyListeners();

    final certified = ffi.drcRunCertificationWithSpins(spinCount);
    _refreshState();

    _isRunning = false;
    notifyListeners();
    return certified;
  }

  /// Reset all DRC state.
  void reset() {
    _ffi?.drcReset();
    _hasResult = false;
    _isCertified = false;
    _status = CertificationStatusLevel.pending;
    _stages = [];
    _blockingFailures = [];
    _manifestHash = 0;
    _configBundleHash = 0;
    _manifestVersion = '';
    _envelopeMetrics = null;
    _safetyLimits = null;
    _replayMetrics = null;
    notifyListeners();
  }

  /// Get manifest JSON.
  String? getManifestJson() => _ffi?.drcManifestJson();

  /// Get certification report JSON.
  String? getReportJson() => _ffi?.drcReportJson();

  /// Get DRC trace JSON.
  String? getTraceJson() => _ffi?.drcTraceJson();

  void _refreshState() {
    final ffi = _ffi;
    if (ffi == null) return;

    _hasResult = ffi.drcHasResult();
    if (!_hasResult) return;

    _isCertified = ffi.drcIsCertified();
    _status = CertificationStatusExtension.fromIndex(ffi.drcCertificationStatus());

    // Stage results
    _stages = [];
    final stageCount = ffi.drcStageCount();
    for (int i = 0; i < stageCount; i++) {
      final name = ffi.drcStageName(i) ?? 'Stage $i';
      final passed = ffi.drcStagePassed(i) == 1;
      final details = ffi.drcStageDetails(i) ?? '';
      _stages.add(CertStageResult(
        index: i, name: name, passed: passed, details: details,
      ));
    }

    // Blocking failures
    _blockingFailures = [];
    final failCount = ffi.drcBlockingFailureCount();
    for (int i = 0; i < failCount; i++) {
      final msg = ffi.drcBlockingFailure(i);
      if (msg != null) _blockingFailures.add(msg);
    }

    // Manifest
    _manifestHash = ffi.drcManifestHash();
    _configBundleHash = ffi.drcConfigBundleHash();
    _manifestVersion = ffi.drcManifestVersion() ?? '';

    // Safety envelope
    _envelopeMetrics = EnvelopeMetrics(
      passed: ffi.drcEnvelopePassed(),
      peakEnergy: ffi.drcEnvelopePeakEnergy(),
      peakVoices: ffi.drcEnvelopePeakVoices(),
      maxPeakDuration: ffi.drcEnvelopeMaxPeakDuration(),
      peakSci: ffi.drcEnvelopePeakSci(),
      peakSessionPct: ffi.drcEnvelopePeakSessionPct(),
      violationCount: ffi.drcEnvelopeViolationCount(),
    );

    // Safety limits
    _safetyLimits = SafetyLimitsData(
      maxEnergy: ffi.drcLimitMaxEnergy(),
      maxPeakDuration: ffi.drcLimitMaxPeakDuration(),
      maxVoices: ffi.drcLimitMaxVoices(),
      maxHarmonicDensity: ffi.drcLimitMaxHarmonicDensity(),
      maxSci: ffi.drcLimitMaxSci(),
      maxPeakSessionPct: ffi.drcLimitMaxPeakSessionPct(),
    );

    // DRC replay
    _replayMetrics = ReplayMetrics(
      passed: ffi.drcReplayPassed(),
      totalFrames: ffi.drcReplayTotalFrames(),
      mismatchCount: ffi.drcReplayMismatchCount(),
      recordedHash: ffi.drcReplayRecordedHash(),
      replayHash: ffi.drcReplayReplayHash(),
    );
  }
}
