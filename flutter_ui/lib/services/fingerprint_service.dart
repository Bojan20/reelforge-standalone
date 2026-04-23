// T6.1–T6.5: Neural Fingerprint™ + A/B Analytics + Honeypot Export Mode
//
// FingerprintService: SHA-256 audio bundle fingerprinting + verification
// AbTestService: Two-proportion z-test statistical significance analysis
// HoneypotService: Recipient watermarking for leak attribution

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data Models
// ─────────────────────────────────────────────────────────────────────────────

/// One audio event for fingerprinting (T6.1)
class FingerprintEventSpec {
  final String name;
  final String category;
  final String tier;
  final int durationMs;
  final int voiceCount;
  final bool isRequired;
  final bool canLoop;

  const FingerprintEventSpec({
    required this.name,
    required this.category,
    required this.tier,
    required this.durationMs,
    required this.voiceCount,
    required this.isRequired,
    required this.canLoop,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'tier': tier,
    'duration_ms': durationMs,
    'voice_count': voiceCount,
    'is_required': isRequired,
    'can_loop': canLoop,
  };
}

/// Computed fingerprint for a bundle (T6.1)
class BundleFingerprint {
  final String digest;
  final String gameId;
  final int eventCount;
  final String shortId;
  final String toolVersion;
  final String generatedAt;

  const BundleFingerprint({
    required this.digest,
    required this.gameId,
    required this.eventCount,
    required this.shortId,
    required this.toolVersion,
    required this.generatedAt,
  });

  factory BundleFingerprint.fromJson(Map<String, dynamic> json) => BundleFingerprint(
    digest: json['digest'] as String,
    gameId: json['game_id'] as String,
    eventCount: json['event_count'] as int,
    shortId: json['short_id'] as String,
    toolVersion: json['tool_version'] as String,
    generatedAt: json['generated_at'] as String,
  );

  Map<String, dynamic> toJson() => {
    'digest': digest,
    'game_id': gameId,
    'event_count': eventCount,
    'short_id': shortId,
    'tool_version': toolVersion,
    'generated_at': generatedAt,
  };
}

/// Fingerprint verification result (T6.4)
class VerificationResult {
  final bool matches;
  final String expectedDigest;
  final String actualDigest;
  final int expectedEventCount;
  final int actualEventCount;
  final String message;

  const VerificationResult({
    required this.matches,
    required this.expectedDigest,
    required this.actualDigest,
    required this.expectedEventCount,
    required this.actualEventCount,
    required this.message,
  });

  factory VerificationResult.fromJson(Map<String, dynamic> json) => VerificationResult(
    matches: json['matches'] as bool,
    expectedDigest: json['expected_digest'] as String,
    actualDigest: json['actual_digest'] as String,
    expectedEventCount: json['expected_event_count'] as int,
    actualEventCount: json['actual_event_count'] as int,
    message: json['message'] as String,
  );
}

/// A/B test variant (T6.2)
class AbVariant {
  final String name;
  final int sampleSize;
  final int conversions;
  final double? avgSessionS;
  final double? avgSpins;
  final double? returnRate;
  final String description;

  const AbVariant({
    required this.name,
    required this.sampleSize,
    required this.conversions,
    this.avgSessionS,
    this.avgSpins,
    this.returnRate,
    required this.description,
  });

  double get conversionRate => sampleSize == 0 ? 0.0 : conversions / sampleSize;

  Map<String, dynamic> toJson() => {
    'name': name,
    'sample_size': sampleSize,
    'conversions': conversions,
    if (avgSessionS != null) 'avg_session_s': avgSessionS,
    if (avgSpins != null) 'avg_spins': avgSpins,
    if (returnRate != null) 'return_rate': returnRate,
    'description': description,
  };
}

/// A/B test configuration (T6.2)
class AbTestConfig {
  final String testName;
  final String gameId;
  final String metric;
  final AbVariant variantA;
  final AbVariant variantB;
  final double minimumDetectableEffect;
  final double significanceLevel;
  final double targetPower;

  const AbTestConfig({
    required this.testName,
    required this.gameId,
    required this.metric,
    required this.variantA,
    required this.variantB,
    this.minimumDetectableEffect = 0.05,
    this.significanceLevel = 0.05,
    this.targetPower = 0.80,
  });

  Map<String, dynamic> toJson() => {
    'test_name': testName,
    'game_id': gameId,
    'metric': metric,
    'variant_a': variantA.toJson(),
    'variant_b': variantB.toJson(),
    'minimum_detectable_effect': minimumDetectableEffect,
    'significance_level': significanceLevel,
    'target_power': targetPower,
  };
}

/// Statistical analysis result (T6.3)
class StatisticalResult {
  final bool isSignificant;
  final double pValue;
  final double zScore;
  final double confidenceIntervalLo;
  final double confidenceIntervalHi;
  final double relativeImprovement;
  final double currentPower;
  final int requiredSampleSize;
  final int additionalSamplesNeeded;

  const StatisticalResult({
    required this.isSignificant,
    required this.pValue,
    required this.zScore,
    required this.confidenceIntervalLo,
    required this.confidenceIntervalHi,
    required this.relativeImprovement,
    required this.currentPower,
    required this.requiredSampleSize,
    required this.additionalSamplesNeeded,
  });

  factory StatisticalResult.fromJson(Map<String, dynamic> json) => StatisticalResult(
    isSignificant: json['is_significant'] as bool,
    pValue: (json['p_value'] as num).toDouble(),
    zScore: (json['z_score'] as num).toDouble(),
    confidenceIntervalLo: (json['confidence_interval_lo'] as num).toDouble(),
    confidenceIntervalHi: (json['confidence_interval_hi'] as num).toDouble(),
    relativeImprovement: (json['relative_improvement'] as num).toDouble(),
    currentPower: (json['current_power'] as num).toDouble(),
    requiredSampleSize: json['required_sample_size'] as int,
    additionalSamplesNeeded: json['additional_samples_needed'] as int,
  );
}

/// Complete A/B test report (T6.3)
class AbTestReport {
  final String testName;
  final String gameId;
  final String metric;
  final double variantARate;
  final double variantBRate;
  final StatisticalResult result;
  final String recommendation;
  final int sampleAdequacyPct;

  const AbTestReport({
    required this.testName,
    required this.gameId,
    required this.metric,
    required this.variantARate,
    required this.variantBRate,
    required this.result,
    required this.recommendation,
    required this.sampleAdequacyPct,
  });

  factory AbTestReport.fromJson(Map<String, dynamic> json) => AbTestReport(
    testName: json['test_name'] as String,
    gameId: json['game_id'] as String,
    metric: json['metric'] as String,
    variantARate: (json['variant_a_rate'] as num).toDouble(),
    variantBRate: (json['variant_b_rate'] as num).toDouble(),
    result: StatisticalResult.fromJson(json['result'] as Map<String, dynamic>),
    recommendation: json['recommendation'] as String,
    sampleAdequacyPct: json['sample_adequacy_pct'] as int,
  );

  /// True if B outperforms A and the difference is statistically significant
  bool get bWins => result.isSignificant && result.relativeImprovement > 0;

  /// True if A outperforms B and the difference is statistically significant
  bool get aWins => result.isSignificant && result.relativeImprovement < 0;
}

/// Honeypot marker for leak attribution (T6.5)
class HoneypotMarker {
  final String token;
  final String shortToken;
  final String recipientHash;
  final String gameId;
  final String issuedAt;
  final int schemeVersion;
  final bool triggered;

  const HoneypotMarker({
    required this.token,
    required this.shortToken,
    required this.recipientHash,
    required this.gameId,
    required this.issuedAt,
    required this.schemeVersion,
    required this.triggered,
  });

  factory HoneypotMarker.fromJson(Map<String, dynamic> json) => HoneypotMarker(
    token: json['token'] as String,
    shortToken: json['short_token'] as String,
    recipientHash: json['recipient_hash'] as String,
    gameId: json['game_id'] as String,
    issuedAt: json['issued_at'] as String,
    schemeVersion: json['scheme_version'] as int,
    triggered: json['triggered'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'token': token,
    'short_token': shortToken,
    'recipient_hash': recipientHash,
    'game_id': gameId,
    'issued_at': issuedAt,
    'scheme_version': schemeVersion,
    'triggered': triggered,
  };
}

/// Honeypot detection / attribution result (T6.5)
class HoneypotDetectionResult {
  final String? foundToken;
  final bool attributed;
  final String? recipientHash;
  final String message;

  const HoneypotDetectionResult({
    required this.foundToken,
    required this.attributed,
    required this.recipientHash,
    required this.message,
  });

  factory HoneypotDetectionResult.fromJson(Map<String, dynamic> json) => HoneypotDetectionResult(
    foundToken: json['found_token'] as String?,
    attributed: json['attributed'] as bool,
    recipientHash: json['recipient_hash'] as String?,
    message: json['message'] as String,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// FingerprintService (T6.1 + T6.4)
// ─────────────────────────────────────────────────────────────────────────────

/// SHA-256 audio bundle fingerprinting and verification service.
///
/// Usage:
/// ```dart
/// final fp = await fingerprintService.compute(
///   gameId: 'golden_phoenix',
///   events: [...],
///   toolVersion: '2.0.0',
/// );
/// ```
class FingerprintService extends ChangeNotifier {
  final NativeFFI _ffi;

  BundleFingerprint? _lastFingerprint;
  VerificationResult? _lastVerification;
  bool _isComputing = false;

  FingerprintService(this._ffi);

  BundleFingerprint? get lastFingerprint => _lastFingerprint;
  VerificationResult? get lastVerification => _lastVerification;
  bool get isComputing => _isComputing;

  /// Compute fingerprint for a list of audio event specs.
  Future<BundleFingerprint?> compute({
    required String gameId,
    required List<FingerprintEventSpec> events,
    String toolVersion = '1.0.0',
    String? generatedAt,
  }) async {
    _isComputing = true;
    notifyListeners();

    try {
      final now = generatedAt ?? DateTime.now().toUtc().toIso8601String();
      final request = jsonEncode({
        'game_id': gameId,
        'tool_version': toolVersion,
        'generated_at': now,
        'events': events.map((e) => e.toJson()).toList(),
      });

      final result = await compute_(_ffi, request);
      _lastFingerprint = result;
      return result;
    } finally {
      _isComputing = false;
      notifyListeners();
    }
  }

  static Future<BundleFingerprint?> compute_(NativeFFI ffi, String request) async {
    return await Future(() {
      final json = ffi.fingerprintCompute(request);
      if (json == null) return null;
      return BundleFingerprint.fromJson(jsonDecode(json) as Map<String, dynamic>);
    });
  }

  /// Verify a current bundle against a stored fingerprint.
  Future<VerificationResult?> verify({
    required BundleFingerprint stored,
    required BundleFingerprint current,
  }) async {
    _isComputing = true;
    notifyListeners();

    try {
      final request = jsonEncode({
        'stored': stored.toJson(),
        'current': current.toJson(),
      });

      final result = await Future(() {
        final json = _ffi.fingerprintVerify(request);
        if (json == null) return null;
        return VerificationResult.fromJson(jsonDecode(json) as Map<String, dynamic>);
      });

      _lastVerification = result;
      return result;
    } finally {
      _isComputing = false;
      notifyListeners();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AbTestService (T6.2 + T6.3)
// ─────────────────────────────────────────────────────────────────────────────

/// Statistical A/B test significance analysis service.
///
/// Uses two-proportion z-test (Rust backend, T6.2–T6.3).
///
/// Usage:
/// ```dart
/// final report = await abTestService.analyze(
///   config: AbTestConfig(
///     testName: 'Ambient Music v2',
///     gameId: 'golden_phoenix',
///     metric: 'session_length',
///     variantA: AbVariant(name: 'A', sampleSize: 2000, conversions: 400, description: 'Original'),
///     variantB: AbVariant(name: 'B', sampleSize: 2000, conversions: 520, description: 'New Track'),
///   ),
/// );
/// ```
class AbTestService extends ChangeNotifier {
  final NativeFFI _ffi;

  AbTestReport? _lastReport;
  bool _isAnalyzing = false;

  AbTestService(this._ffi);

  AbTestReport? get lastReport => _lastReport;
  bool get isAnalyzing => _isAnalyzing;

  /// Run full A/B test analysis.
  Future<AbTestReport?> analyze({required AbTestConfig config}) async {
    _isAnalyzing = true;
    notifyListeners();

    try {
      final request = jsonEncode(config.toJson());
      final report = await Future(() {
        final json = _ffi.abTestAnalyze(request);
        if (json == null) return null;
        return AbTestReport.fromJson(jsonDecode(json) as Map<String, dynamic>);
      });

      _lastReport = report;
      return report;
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  /// Quick helper: is variant B significantly better than A?
  Future<bool> isBSignificantlyBetter({
    required String gameId,
    required String metric,
    required AbVariant variantA,
    required AbVariant variantB,
  }) async {
    final report = await analyze(
      config: AbTestConfig(
        testName: 'quick_test',
        gameId: gameId,
        metric: metric,
        variantA: variantA,
        variantB: variantB,
      ),
    );
    return report?.bWins ?? false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HoneypotService (T6.5)
// ─────────────────────────────────────────────────────────────────────────────

/// Honeypot export mode — unique watermark injection for leak tracing.
///
/// Each distribution recipient gets a uniquely-watermarked bundle.
/// If a package appears in the wild, [detect] identifies the recipient.
///
/// SECURITY NOTE: `secretSeed` must NEVER be sent to the recipient.
/// Store it server-side only. Without the seed, tokens cannot be
/// re-derived and attribution will fail.
///
/// Usage:
/// ```dart
/// // When exporting:
/// final marker = await honeypotService.generate(
///   gameId: 'golden_phoenix',
///   recipientId: 'casino_malta_ltd',
///   secretSeed: serverSideSecret,
/// );
/// final watermarkedJson = await honeypotService.inject(
///   marker: marker!,
///   exportJson: bundleJson,
/// );
///
/// // When investigating a leak:
/// final result = await honeypotService.detect(exportJson: leakedJson, marker: knownMarker);
/// ```
class HoneypotService extends ChangeNotifier {
  final NativeFFI _ffi;

  HoneypotMarker? _lastMarker;
  HoneypotDetectionResult? _lastDetection;

  HoneypotService(this._ffi);

  HoneypotMarker? get lastMarker => _lastMarker;
  HoneypotDetectionResult? get lastDetection => _lastDetection;

  /// Generate a unique honeypot marker for a recipient.
  Future<HoneypotMarker?> generate({
    required String gameId,
    required String recipientId,
    required String secretSeed,
    String? issuedAt,
  }) async {
    final now = issuedAt ?? DateTime.now().toUtc().toIso8601String();
    final request = jsonEncode({
      'game_id': gameId,
      'recipient_id': recipientId,
      'secret_seed': secretSeed,
      'issued_at': now,
    });

    final marker = await Future(() {
      final json = _ffi.honeypotGenerate(request);
      if (json == null) return null;
      return HoneypotMarker.fromJson(jsonDecode(json) as Map<String, dynamic>);
    });

    _lastMarker = marker;
    notifyListeners();
    return marker;
  }

  /// Inject a honeypot marker into an export JSON payload.
  Future<String?> inject({
    required HoneypotMarker marker,
    required String exportJson,
  }) async {
    final request = jsonEncode({
      'marker': marker.toJson(),
      'export_json': exportJson,
    });

    return await Future(() => _ffi.honeypotInject(request));
  }

  /// Detect and attribute a honeypot marker in a leaked export.
  Future<HoneypotDetectionResult?> detect({
    required String exportJson,
    HoneypotMarker? marker,
  }) async {
    final request = jsonEncode({
      'export_json': exportJson,
      if (marker != null) 'marker': marker.toJson(),
    });

    final result = await Future(() {
      final json = _ffi.honeypotDetect(request);
      if (json == null) return null;
      return HoneypotDetectionResult.fromJson(jsonDecode(json) as Map<String, dynamic>);
    });

    _lastDetection = result;
    notifyListeners();
    return result;
  }
}
