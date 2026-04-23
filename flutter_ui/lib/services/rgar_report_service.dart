/// RGAR Report Service — Responsible Gaming Audio Report
///
/// T1.4 + T1.6: Auto-analyses all composite events from the live session,
/// runs RGAI compliance metrics, and exports in regulatory formats.
///
/// Formats:
///  - JSON (machine-readable audit trail)
///  - Human-readable text summary
///  - ComplianceMetadata (structured regulatory export)
///
/// Data sources (auto-wired, no manual input needed):
///  - CompositeEventSystemProvider → all audio events + layers
///  - PacingEngineProvider         → RTP, volatility, hit frequency
///  - EmotionalStateProvider       → tension, escalation bias
///  - AurexisProvider              → volatility, rtp, win multiplier
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/aurexis_jurisdiction.dart';
import '../models/slot_audio_events.dart';
import '../providers/slot_lab/rgai_provider.dart';
import '../providers/slot_lab/emotional_state_provider.dart';
import '../providers/slot_lab/pacing_engine_provider.dart';
import '../providers/aurexis_provider.dart';
import 'service_locator.dart';

// =============================================================================
// COMPLIANCE METADATA — regulatory-format export (T1.6)
// =============================================================================

/// Structured metadata block for regulatory submission
class ComplianceMetadata {
  final String schemaVersion = '1.0';
  final String tool = 'FluxForge SlotLab';
  final String toolVersion = '2.4.0';
  final DateTime generatedAt;
  final String gameName;
  final String jurisdictionCode;
  final String overallRating;
  final double complianceScore;

  // Session parameters
  final double rtp;
  final double volatility;
  final double hitFrequency;

  // RGAI metrics (session averages)
  final double avgArousalCoefficient;
  final double maxNearMissDeceptionIndex;
  final double maxLossDisguiseScore;
  final double maxTemporalDistortionFactor;

  // Counts
  final int totalAssetsAnalyzed;
  final int assetsPass;
  final int assetsWarn;
  final int assetsBlocked;

  // Violations list
  final List<String> violations;

  // Full per-asset detail
  final List<Map<String, dynamic>> assetDetails;

  const ComplianceMetadata({
    required this.generatedAt,
    required this.gameName,
    required this.jurisdictionCode,
    required this.overallRating,
    required this.complianceScore,
    required this.rtp,
    required this.volatility,
    required this.hitFrequency,
    required this.avgArousalCoefficient,
    required this.maxNearMissDeceptionIndex,
    required this.maxLossDisguiseScore,
    required this.maxTemporalDistortionFactor,
    required this.totalAssetsAnalyzed,
    required this.assetsPass,
    required this.assetsWarn,
    required this.assetsBlocked,
    required this.violations,
    required this.assetDetails,
  });

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'tool': tool,
        'tool_version': toolVersion,
        'generated_at': generatedAt.toIso8601String(),
        'game_name': gameName,
        'jurisdiction': jurisdictionCode,
        'overall_rating': overallRating,
        'compliance_score_pct': complianceScore,
        'math_params': {
          'rtp_pct': rtp * 100,
          'volatility': volatility,
          'hit_frequency': hitFrequency,
        },
        'rgai_metrics': {
          'avg_arousal_coefficient': avgArousalCoefficient,
          'max_near_miss_deception_index': maxNearMissDeceptionIndex,
          'max_loss_disguise_score': maxLossDisguiseScore,
          'max_temporal_distortion_factor': maxTemporalDistortionFactor,
        },
        'asset_summary': {
          'total': totalAssetsAnalyzed,
          'pass': assetsPass,
          'warn': assetsWarn,
          'blocked': assetsBlocked,
        },
        'violations': violations,
        'assets': assetDetails,
      };

  String toJsonString({bool pretty = true}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(toJson());
  }

  /// Malta MGA XML format
  String toMgaXml() {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<RGARReport xmlns="https://mga.org.mt/rgar/1.0">');
    buf.writeln('  <Header>');
    buf.writeln('    <Tool>$tool v$toolVersion</Tool>');
    buf.writeln('    <GeneratedAt>${generatedAt.toIso8601String()}</GeneratedAt>');
    buf.writeln('    <GameName>$gameName</GameName>');
    buf.writeln('    <Jurisdiction>$jurisdictionCode</Jurisdiction>');
    buf.writeln('  </Header>');
    buf.writeln('  <Summary>');
    buf.writeln('    <OverallRating>$overallRating</OverallRating>');
    buf.writeln(
        '    <ComplianceScore>${complianceScore.toStringAsFixed(1)}</ComplianceScore>');
    buf.writeln('    <TotalAssets>$totalAssetsAnalyzed</TotalAssets>');
    buf.writeln('    <PassAssets>$assetsPass</PassAssets>');
    buf.writeln('    <WarnAssets>$assetsWarn</WarnAssets>');
    buf.writeln('    <BlockedAssets>$assetsBlocked</BlockedAssets>');
    buf.writeln('  </Summary>');
    buf.writeln('  <MathParams>');
    buf.writeln(
        '    <RTP>${(rtp * 100).toStringAsFixed(2)}</RTP>');
    buf.writeln('    <Volatility>${volatility.toStringAsFixed(3)}</Volatility>');
    buf.writeln(
        '    <HitFrequency>${hitFrequency.toStringAsFixed(4)}</HitFrequency>');
    buf.writeln('  </MathParams>');
    buf.writeln('  <RGAIMetrics>');
    buf.writeln(
        '    <ArousalCoefficient>${avgArousalCoefficient.toStringAsFixed(3)}</ArousalCoefficient>');
    buf.writeln(
        '    <NearMissDeceptionIndex>${maxNearMissDeceptionIndex.toStringAsFixed(3)}</NearMissDeceptionIndex>');
    buf.writeln(
        '    <LossDisguiseScore>${maxLossDisguiseScore.toStringAsFixed(3)}</LossDisguiseScore>');
    buf.writeln('  </RGAIMetrics>');
    if (violations.isNotEmpty) {
      buf.writeln('  <Violations>');
      for (final v in violations) {
        buf.writeln('    <Violation>$v</Violation>');
      }
      buf.writeln('  </Violations>');
    }
    buf.writeln('</RGARReport>');
    return buf.toString();
  }
}

// =============================================================================
// EXPORT GATE RESULT — T1.5
// =============================================================================

/// Result of compliance gate check before export
class ComplianceGateResult {
  final bool allowed;
  final bool hasWarnings;
  final AddictionRiskRating rating;
  final String ratingLabel;
  final double complianceScore;
  final List<String> blockers; // Reasons export is BLOCKED
  final List<String> warnings; // Warnings that allow but flag export
  final ComplianceMetadata? metadata;

  const ComplianceGateResult({
    required this.allowed,
    required this.hasWarnings,
    required this.rating,
    required this.ratingLabel,
    required this.complianceScore,
    required this.blockers,
    required this.warnings,
    this.metadata,
  });

  factory ComplianceGateResult.noData() => const ComplianceGateResult(
        allowed: true,
        hasWarnings: false,
        rating: AddictionRiskRating.low,
        ratingLabel: 'N/A',
        complianceScore: 100.0,
        blockers: [],
        warnings: ['No audio assets analysed — RGAR not generated'],
      );

  factory ComplianceGateResult.blocked(
          List<String> reasons, ComplianceMetadata meta) =>
      ComplianceGateResult(
        allowed: false,
        hasWarnings: true,
        rating: AddictionRiskRating.prohibited,
        ratingLabel: 'PROHIBITED',
        complianceScore: meta.complianceScore,
        blockers: reasons,
        warnings: [],
        metadata: meta,
      );
}

// =============================================================================
// RGAR REPORT SERVICE — main entry point
// =============================================================================

/// Auto-analyses the live session and generates RGAR compliance report.
///
/// Usage:
///   final service = GetIt.instance\<RgarReportService\>();
///   final gate = await service.runComplianceGate();
///   if (!gate.allowed) { ... show error ... }
class RgarReportService extends ChangeNotifier {
  bool _isRunning = false;
  ComplianceMetadata? _lastMetadata;
  ComplianceGateResult? _lastGate;
  DateTime? _lastRunAt;

  bool get isRunning => _isRunning;
  ComplianceMetadata? get lastMetadata => _lastMetadata;
  ComplianceGateResult? get lastGate => _lastGate;
  DateTime? get lastRunAt => _lastRunAt;
  bool get hasReport => _lastMetadata != null;

  // ---------------------------------------------------------------------------
  // PUBLIC API
  // ---------------------------------------------------------------------------

  /// Run full compliance analysis on the current session.
  /// Returns a gate result indicating whether export is permitted.
  Future<ComplianceGateResult> runComplianceGate({
    String gameName = 'Untitled Project',
    AurexisJurisdiction? jurisdiction,
  }) async {
    if (_isRunning) return _lastGate ?? ComplianceGateResult.noData();

    _isRunning = true;
    notifyListeners();

    try {
      final gate = await _doAnalysis(
        gameName: gameName,
        jurisdiction: jurisdiction ?? AurexisJurisdiction.ukgc,
      );
      _lastGate = gate;
      _lastRunAt = DateTime.now();
      return gate;
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  /// Export last report to disk (JSON + XML).
  /// Returns list of written file paths.
  Future<List<String>> exportToDisk(String outputDirectory) async {
    final meta = _lastMetadata;
    if (meta == null) return [];

    final dir = Directory(outputDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final ts = meta.generatedAt
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);

    final paths = <String>[];

    // JSON audit trail
    final jsonPath = p.join(outputDirectory, 'rgar_${ts}.json');
    await File(jsonPath).writeAsString(meta.toJsonString());
    paths.add(jsonPath);

    // MGA XML format
    final xmlPath = p.join(outputDirectory, 'rgar_mga_${ts}.xml');
    await File(xmlPath).writeAsString(meta.toMgaXml());
    paths.add(xmlPath);

    return paths;
  }

  // ---------------------------------------------------------------------------
  // INTERNAL — analysis logic
  // ---------------------------------------------------------------------------

  Future<ComplianceGateResult> _doAnalysis({
    required String gameName,
    required AurexisJurisdiction jurisdiction,
  }) async {
    // Pull live providers
    final rgai = sl<RgaiProvider>();
    final pacing = sl<PacingEngineProvider>();
    final emotional = sl<EmotionalStateProvider>();
    final aurexis = sl<AurexisProvider>();

    // Pull math params from PacingEngine (most reliable source)
    final rtp = pacing.rtp.clamp(0.0, 1.0);
    final volatility = pacing.volatility.clamp(0.0, 1.0);
    final hitFreq = pacing.hitFrequency.clamp(0.0, 1.0);

    // Pull live emotional/aurexis signals for spectral estimation
    final tension = emotional.tension;
    final escalation = emotional.escalationBias;
    final winMult = aurexis.winMultiplier;

    // Get all composite events with audio assets
    final allEvents = _getAllCompositeEvents();

    if (allEvents.isEmpty) {
      return ComplianceGateResult.noData();
    }

    // Analyse each event's layers
    rgai.setJurisdiction(jurisdiction);
    final assetDetails = <Map<String, dynamic>>[];
    final allViolations = <String>[];
    int blockedCount = 0;

    for (final event in allEvents) {
      final stageName = _classifyStage(event);
      final isWin = _isWinStage(stageName);
      final isNearMiss = _isNearMissStage(stageName);
      final isLoss = _isLossStage(stageName);
      final betMult = _estimateBetMultiplier(stageName, winMult);

      for (final layer in event.layers) {
        if (layer.audioPath.isEmpty || layer.muted) continue;

        final volumeDb = _toDb(layer.volume * event.masterVolume);
        final durationS = layer.durationSeconds ?? _estimateDuration(stageName);
        final spectralHz =
            _estimateSpectralCentroid(stageName, isWin, isNearMiss, tension);
        final tempoMult = _estimateTempoMultiplier(escalation, stageName);

        final analysis = rgai.analyzeAsset(
          assetId: '${event.id}_${layer.id}',
          assetName: p.basename(layer.audioPath),
          stage: stageName,
          volumeDb: volumeDb,
          durationS: durationS,
          tempoMultiplier: tempoMult,
          spectralCentroidHz: spectralHz,
          isWinEvent: isWin,
          isNearMissEvent: isNearMiss,
          isLossEvent: isLoss,
          betMultiplier: betMult,
        );

        if (analysis.riskRating == AddictionRiskRating.prohibited) {
          blockedCount++;
          allViolations.add(
              '[BLOCKED] ${event.name}/${p.basename(layer.audioPath)}: ${analysis.flags.join('; ')}');
        } else if (analysis.riskRating == AddictionRiskRating.high) {
          allViolations.add(
              '[HIGH] ${event.name}/${p.basename(layer.audioPath)}: ${analysis.flags.join('; ')}');
        }

        assetDetails.add({
          'event_id': event.id,
          'event_name': event.name,
          'stage': stageName,
          'asset': p.basename(layer.audioPath),
          'volume_db': volumeDb.toStringAsFixed(1),
          'duration_s': durationS.toStringAsFixed(2),
          'arousal': analysis.arousalCoefficient.toStringAsFixed(3),
          'near_miss_deception': analysis.nearMissDeceptionIndex.toStringAsFixed(3),
          'loss_disguise': analysis.lossDisguiseScore.toStringAsFixed(3),
          'temporal_distortion': analysis.temporalDistortionFactor.toStringAsFixed(3),
          'rating': analysis.riskRating.displayName,
          'flags': analysis.flags,
        });
      }
    }

    // Build summary from RGAI provider's report
    final report = rgai.report;
    final compScore = report?.summary.overallComplianceScore ?? 100.0;
    final avgArousal = report?.summary.avgArousal ?? 0.0;
    final maxNmd = report?.summary.maxNearMissDeception ?? 0.0;
    final maxLd = report?.summary.maxLossDisguise ?? 0.0;
    final totalAssets = assetDetails.length;
    final passCount = (report?.summary.passedAssets ?? totalAssets);
    final warnCount = report?.summary.flaggedAssets ?? 0;
    final maxTdf = assetDetails.isEmpty
        ? 0.0
        : assetDetails.fold<double>(
              0.0,
              (prev, a) => math.max(
                prev,
                double.tryParse(a['temporal_distortion'].toString()) ?? 0.0,
              ),
            );

    final meta = ComplianceMetadata(
      generatedAt: DateTime.now(),
      gameName: gameName,
      jurisdictionCode: jurisdiction.name.toUpperCase(),
      overallRating: report?.summary.overallRiskRating?.displayName ?? 'LOW',
      complianceScore: compScore,
      rtp: rtp,
      volatility: volatility,
      hitFrequency: hitFreq,
      avgArousalCoefficient: avgArousal,
      maxNearMissDeceptionIndex: maxNmd,
      maxLossDisguiseScore: maxLd,
      maxTemporalDistortionFactor: maxTdf,
      totalAssetsAnalyzed: totalAssets,
      assetsPass: passCount,
      assetsWarn: warnCount,
      assetsBlocked: blockedCount,
      violations: allViolations,
      assetDetails: assetDetails,
    );

    _lastMetadata = meta;

    // Gate decision
    if (blockedCount > 0) {
      final blockers = allViolations
          .where((v) => v.startsWith('[BLOCKED]'))
          .toList();
      return ComplianceGateResult.blocked(blockers, meta);
    }

    final hasWarnings = allViolations.isNotEmpty;
    final rating = report?.summary.overallRiskRating ?? AddictionRiskRating.low;

    return ComplianceGateResult(
      allowed: true,
      hasWarnings: hasWarnings,
      rating: rating,
      ratingLabel: rating.displayName,
      complianceScore: compScore,
      blockers: [],
      warnings:
          allViolations.where((v) => v.startsWith('[HIGH]')).toList(),
      metadata: meta,
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS — heuristic parameter estimation from metadata
  // ---------------------------------------------------------------------------

  List<SlotCompositeEvent> _getAllCompositeEvents() {
    try {
      // Access via GetIt — CompositeEventSystemProvider registered as singleton
      final providerType = sl.isRegistered<CompositeEventAccessor>()
          ? sl<CompositeEventAccessor>().events
          : <SlotCompositeEvent>[];
      return providerType;
    } catch (_) {
      return [];
    }
  }

  String _classifyStage(SlotCompositeEvent event) {
    final name = event.name.toUpperCase();
    final cat = event.category.toUpperCase();
    final stages = event.triggerStages.map((s) => s.toUpperCase()).toList();

    // Check trigger stages first (most accurate)
    for (final s in stages) {
      if (s.contains('WIN')) return s;
      if (s.contains('JACKPOT')) return 'JACKPOT';
      if (s.contains('NEAR_MISS') || s.contains('ANTICIPATION'))
        return 'ANTICIPATION';
      if (s.contains('REEL_STOP')) return 'REEL_STOP';
      if (s.contains('SCATTER')) return 'SCATTER';
      if (s.contains('FEATURE') || s.contains('FREE_SPIN'))
        return 'FREE_SPINS';
    }

    // Fall back to name/category heuristic
    if (name.contains('WIN') || cat == 'WIN') {
      if (name.contains('BIG') || name.contains('5')) return 'WIN_BIG';
      if (name.contains('MEGA') || name.contains('JACK')) return 'JACKPOT';
      return 'WIN_SMALL';
    }
    if (name.contains('JACKPOT')) return 'JACKPOT';
    if (name.contains('ANTI') || name.contains('NEAR')) return 'ANTICIPATION';
    if (name.contains('REEL') || name.contains('SPIN')) return 'REEL_STOP';
    if (name.contains('FEATURE') || name.contains('FREE')) return 'FREE_SPINS';
    if (name.contains('SCATTER')) return 'SCATTER';
    if (name.contains('AMBIENT') || name.contains('MUSIC')) return 'AMBIENT';
    if (cat == 'SPIN') return 'SPIN_START';

    return cat.isNotEmpty ? cat : 'BASE';
  }

  bool _isWinStage(String stage) {
    return stage.contains('WIN') ||
        stage == 'JACKPOT' ||
        stage == 'FREE_SPINS' ||
        stage == 'SCATTER';
  }

  bool _isNearMissStage(String stage) {
    return stage == 'ANTICIPATION' || stage.contains('NEAR');
  }

  bool _isLossStage(String stage) {
    return stage == 'BASE' || stage == 'REEL_STOP' || stage == 'SPIN_START';
  }

  double _estimateBetMultiplier(String stage, double winMult) {
    if (stage == 'JACKPOT') return 100.0;
    if (stage == 'WIN_BIG') return winMult > 0 ? winMult : 20.0;
    if (stage.contains('WIN')) return winMult > 0 ? winMult : 5.0;
    if (stage == 'SCATTER' || stage == 'FREE_SPINS') return 3.0;
    return 0.0;
  }

  double _estimateDuration(String stage) {
    return switch (stage) {
      'JACKPOT' => 8.0,
      'WIN_BIG' => 4.5,
      'FREE_SPINS' => 5.0,
      'SCATTER' => 3.0,
      'WIN_SMALL' => 2.0,
      'ANTICIPATION' => 2.5,
      'AMBIENT' => 30.0,
      _ => 1.5,
    };
  }

  /// Estimate spectral centroid from stage type (Hz)
  /// Without DSP analysis of the actual file, use stage-based heuristics.
  double _estimateSpectralCentroid(
      String stage, bool isWin, bool isNearMiss, double tension) {
    // Base centroid by stage type
    double base = switch (stage) {
      'JACKPOT' => 7500.0,
      'WIN_BIG' => 6000.0,
      'FREE_SPINS' || 'SCATTER' => 5500.0,
      'WIN_SMALL' => 4500.0,
      'ANTICIPATION' => 4000.0,
      'REEL_STOP' => 2500.0,
      'AMBIENT' => 2000.0,
      _ => 2000.0,
    };

    // Modulate by live emotional tension
    base += tension * 1500.0;

    return base.clamp(500.0, 12000.0);
  }

  double _estimateTempoMultiplier(double escalation, String stage) {
    // Base multiplier by stage
    double base = switch (stage) {
      'JACKPOT' => 1.3,
      'WIN_BIG' => 1.2,
      'ANTICIPATION' => 1.15,
      'WIN_SMALL' => 1.05,
      'AMBIENT' => 0.9,
      _ => 1.0,
    };

    // Add escalation influence
    base += escalation * 0.15;
    return base.clamp(0.7, 1.5);
  }

  double _toDb(double linear) {
    if (linear <= 0) return -60.0;
    return (20 * math.log(linear) / math.ln10).clamp(-60.0, 0.0);
  }
}

// =============================================================================
// COMPOSITE EVENT ACCESSOR — thin interface for DI (avoids circular imports)
// =============================================================================

/// Minimal interface to expose composite events to RgarReportService
/// without importing MiddlewareProvider (which would create circular dependency).
abstract class CompositeEventAccessor {
  List<SlotCompositeEvent> get events;
}
