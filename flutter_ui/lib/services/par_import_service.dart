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

  const ParFeature({
    required this.featureType,
    this.name = '',
    this.triggerProbability = 0.0,
    this.avgPayoutMultiplier = 0.0,
    this.rtpContribution = 0.0,
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
