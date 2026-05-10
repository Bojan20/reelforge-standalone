// FLUX_MASTER_TODO 0.5 B.4 — Event Timing Trace Export
//
// Per-spin trace export — uzima `_lastStages` cache iz `SlotStageProvider`
// + spin metadata (spinId, RNG seed, win amount, multiplier, tier) i izlazi
// kao strukturisan JSON pod
// `~/Library/Application Support/FluxForge Studio/audit/spin_<id>_trace.json`.
//
// Use-cases:
//   * Marketing clip metadata (3.6.F) — embed RNG seed + stage timeline
//     u clip JSON za reproducibility
//   * Compliance audit trail — per-spin proof of stage timing
//   * Post-session QA — replay scenario
//   * Cross-session diff (lokal A/B test za math/feature changes)
//
// Razlika vs. SessionRecorder (3.6.E):
//   * SessionRecorder snima N spinova zaredom (ring buffer, in-memory)
//   * Trace exporter snima JEDAN spin u file (per-spin granularity)
//
// Ovo je samostalan service — bez UI panela. Trigger se zove iz:
//   * `helix_action` programatski (CortexHands)
//   * `EventTimingTraceExporter.exportLastSpin(...)` direktno

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../providers/slot_lab/slot_stage_provider.dart';
import '../src/rust/native_ffi.dart' show SlotLabSpinResult, SlotLabStageEvent;

/// Per-spin trace report — sve sto treba za reproducibility + audit.
class SpinTraceReport {
  final String spinId;
  final DateTime exportedAt;
  final SlotLabSpinResult? result;
  final List<SlotLabStageEvent> stages;
  final Map<String, dynamic> metadata;

  const SpinTraceReport({
    required this.spinId,
    required this.exportedAt,
    required this.result,
    required this.stages,
    this.metadata = const {},
  });

  /// Total spin duration u ms (od prvog do poslednjeg stage event-a).
  double get durationMs {
    if (stages.length < 2) return 0;
    return stages.last.timestampMs - stages.first.timestampMs;
  }

  /// Stage count po category-i (reel/win/feature/anticipation/...).
  Map<String, int> stagesByCategory() {
    final counts = <String, int>{};
    for (final s in stages) {
      final type = s.stageType.toUpperCase();
      String cat;
      if (type.startsWith('REEL_')) {
        cat = 'reel';
      } else if (type.startsWith('WIN_') || type.startsWith('ROLLUP_')) {
        cat = 'win';
      } else if (type.startsWith('FEATURE_') ||
          type.startsWith('FS_') ||
          type.startsWith('BONUS_')) {
        cat = 'feature';
      } else if (type.startsWith('ANTICIPATION_')) {
        cat = 'anticipation';
      } else if (type.startsWith('JACKPOT_')) {
        cat = 'jackpot';
      } else if (type.startsWith('CASCADE_')) {
        cat = 'cascade';
      } else if (type.startsWith('UI_')) {
        cat = 'ui';
      } else {
        cat = 'other';
      }
      counts[cat] = (counts[cat] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, dynamic> toJson() => {
        'schema_version': 1,
        'spin_id': spinId,
        'exported_at': exportedAt.toIso8601String(),
        'duration_ms': durationMs,
        'stage_count': stages.length,
        'stages_by_category': stagesByCategory(),
        if (result != null) 'result': _resultToJson(result!),
        'stages': stages.map(_stageToJson).toList(),
        'metadata': metadata,
      };

  static Map<String, dynamic> _resultToJson(SlotLabSpinResult r) => {
        'spin_id': r.spinId,
        'bet': r.bet,
        'total_win': r.totalWin,
        'win_ratio': r.winRatio,
        'win_tier': r.winTierName,
        'big_win_tier': r.bigWinTier?.name,
        'feature_triggered': r.featureTriggered,
        'near_miss': r.nearMiss,
        'is_free_spins': r.isFreeSpins,
        'free_spin_index': r.freeSpinIndex,
        'multiplier': r.multiplier,
        'cascade_count': r.cascadeCount,
        'grid': r.grid,
        'line_win_count': r.lineWins.length,
      };

  static Map<String, dynamic> _stageToJson(SlotLabStageEvent s) => {
        'stage_type': s.stageType,
        'timestamp_ms': s.timestampMs,
        'payload': s.payload,
        // raw_stage je intentionally skipped — verbose, ima strukturne
        // duplikate sa payload-om. Replay-able iz combination.
      };
}

/// Singleton exporter. Stateless service — sav state se cita iz
/// `SlotStageProvider` na poziv-by-poziv osnovi.
class EventTimingTraceExporter extends ChangeNotifier {
  static final EventTimingTraceExporter instance =
      EventTimingTraceExporter._();
  EventTimingTraceExporter._();

  String? _lastExportedPath;
  String? get lastExportedPath => _lastExportedPath;

  /// Eksportuje poslednji spin iz `SlotStageProvider._lastStages` zajedno sa
  /// `result` (ako je dostavljen) u JSON file.
  /// Vraca putanju do file-a ili null ako nema stages.
  Future<String?> exportLastSpin({
    required SlotStageProvider stageProvider,
    SlotLabSpinResult? result,
    Map<String, dynamic>? extraMetadata,
  }) async {
    final stages = stageProvider.lastStages;
    if (stages.isEmpty) return null;

    final spinId =
        result?.spinId ?? 'manual-${DateTime.now().millisecondsSinceEpoch}';
    final report = SpinTraceReport(
      spinId: spinId,
      exportedAt: DateTime.now(),
      result: result,
      stages: List.unmodifiable(stages),
      metadata: {
        ...?extraMetadata,
        'export_source': 'EventTimingTraceExporter',
        'platform': Platform.operatingSystem,
      },
    );

    final filePath = await _writeReport(report);
    _lastExportedPath = filePath;
    notifyListeners();
    return filePath;
  }

  /// Eksportuje proizvoljan SpinTraceReport (npr. iz session recorder
  /// snapshot-a) — re-use putanje za marketing clip metadata.
  Future<String?> exportReport(SpinTraceReport report) async {
    final filePath = await _writeReport(report);
    _lastExportedPath = filePath;
    notifyListeners();
    return filePath;
  }

  Future<String?> _writeReport(SpinTraceReport report) async {
    final home = Platform.environment['HOME'];
    final base = (home != null && home.isNotEmpty)
        ? '$home/Library/Application Support/FluxForge Studio'
        : '/tmp/fluxforge-studio';
    final auditDir = Directory('$base/audit');
    if (!auditDir.existsSync()) {
      await auditDir.create(recursive: true);
    }
    // Sanitize spin_id za safe file names (no slashes, colons, spaces).
    final safeId = report.spinId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final ts = report.exportedAt
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')[0];
    final filePath = '${auditDir.path}/spin_${safeId}_$ts.json';
    final f = File(filePath);
    final json = const JsonEncoder.withIndent('  ').convert(report.toJson());
    await f.writeAsString(json, flush: true);
    return filePath;
  }
}
