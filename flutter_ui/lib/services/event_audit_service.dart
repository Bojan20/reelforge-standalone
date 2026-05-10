// FLUX_MASTER_TODO 0.5 B.1 — Event Audit Tool
//
// Cross-references 4 services (EventRegistry + StageCoverageService +
// StageConfigurationService + SlotLabProjectProvider) i pravi unified audit
// report po kategoriji + audio binding status + orphan list + missing-audio list.
//
// Output use-cases:
//   * Live UI gauge u HELIX MONITOR DEBUG sub-tab (per-category coverage)
//   * Export `audit/events_<timestamp>.json` za marketing clip metadata,
//     compliance trail, post-session QA review.
//
// Razlika vs. EventOrphanDetectorService:
//   * Orphan = "registrovan ali nije fired"  (već postoji)
//   * Audit = "registrovan + ima audio binding + fired count + per-category roll-up"
//   * Audit je SUPERSET — daje punu sliku event lifecycle-a, ne samo orphan.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../providers/slot_lab_project_provider.dart';
import 'event_registry.dart';
import 'stage_configuration_service.dart';
import 'stage_coverage_service.dart';

/// Per-stage audit entry.
class EventAuditEntry {
  /// Stage name (npr. "REEL_STOP_0", "WIN_BIG", "FS_INTRO").
  final String stage;

  /// Category iz `StageConfigurationService.getCategory()`.
  final StageCategory category;

  /// Da li je stage registrovan u `EventRegistry`.
  final bool isRegistered;

  /// Da li ima audio file pridruženo (audioAssignments[stage] != null).
  final bool hasAudio;

  /// Audio path (ako postoji) ili `null`.
  final String? audioPath;

  /// Trigger count u trenutnoj session-i (iz `StageCoverageService`).
  final int triggerCount;

  /// Last-triggered timestamp (može biti `null` ako nije fired).
  final DateTime? lastTriggered;

  /// AudioEvent ID iz EventRegistry (npr. "audio_REEL_STOP_0") ili `null`.
  final String? eventId;

  const EventAuditEntry({
    required this.stage,
    required this.category,
    required this.isRegistered,
    required this.hasAudio,
    this.audioPath,
    this.triggerCount = 0,
    this.lastTriggered,
    this.eventId,
  });

  /// Status kompozicija: 4-level health flag.
  EventAuditStatus get status {
    if (!isRegistered && !hasAudio) return EventAuditStatus.absent;
    if (isRegistered && !hasAudio) return EventAuditStatus.silent;
    if (isRegistered && hasAudio && triggerCount == 0) {
      return EventAuditStatus.dormant;
    }
    return EventAuditStatus.active;
  }

  Map<String, dynamic> toJson() => {
        'stage': stage,
        'category': category.name,
        'is_registered': isRegistered,
        'has_audio': hasAudio,
        'audio_path': audioPath,
        'trigger_count': triggerCount,
        'last_triggered': lastTriggered?.toIso8601String(),
        'event_id': eventId,
        'status': status.name,
      };
}

/// 4-level health flag za event lifecycle.
enum EventAuditStatus {
  /// Stage definisan u taxonomy ali ni audio ni event registracija nedostaju.
  /// Najlošije stanje — stage postoji u kodu ali je potpuno mrtav.
  absent,

  /// Event registrovan, ali audio binding nedostaje.
  /// Trigger će fire, ali korisnik neće čuti ništa.
  silent,

  /// Event registrovan + audio bound, ali nikad nije triggered u session-i.
  /// Verovatno valid za feature stage-ove koji se ne fire-uju u base game.
  dormant,

  /// Sve dobro — registrovan, audio bound, fired bar 1×.
  active,
}

extension EventAuditStatusExtension on EventAuditStatus {
  String get label => switch (this) {
        EventAuditStatus.absent => 'ABSENT',
        EventAuditStatus.silent => 'SILENT',
        EventAuditStatus.dormant => 'DORMANT',
        EventAuditStatus.active => 'ACTIVE',
      };

  /// Boja za UI badge (gold-tier = zdravo, red = problem).
  int get colorHex => switch (this) {
        EventAuditStatus.absent => 0xFFFF4040, // crveno — najgore
        EventAuditStatus.silent => 0xFFFF9040, // narandžasto — registrovan ali nemo
        EventAuditStatus.dormant => 0xFFE8BC5C, // brand gold — registrovan ali nije fired
        EventAuditStatus.active => 0xFF40FF90, // zeleno — sve OK
      };
}

/// Per-category roll-up summary.
class CategoryAuditSummary {
  final StageCategory category;
  final int total;
  final int absent;
  final int silent;
  final int dormant;
  final int active;

  const CategoryAuditSummary({
    required this.category,
    required this.total,
    required this.absent,
    required this.silent,
    required this.dormant,
    required this.active,
  });

  /// Procenat aktivnih stage-ova (fired sa audio binding-om) u kategoriji.
  /// 1.0 = sve fired sa audio; 0.0 = ništa fired.
  double get activeRatio => total == 0 ? 0.0 : active / total;

  /// Procenat zdravih stage-ova (sve sem `absent`).
  double get healthyRatio =>
      total == 0 ? 0.0 : (total - absent) / total;

  Map<String, dynamic> toJson() => {
        'category': category.name,
        'total': total,
        'absent': absent,
        'silent': silent,
        'dormant': dormant,
        'active': active,
        'active_ratio': activeRatio,
        'healthy_ratio': healthyRatio,
      };
}

/// Full audit snapshot — generisan u jednom prolazu.
class EventAuditReport {
  final DateTime generatedAt;
  final List<EventAuditEntry> entries;
  final List<CategoryAuditSummary> categorySummaries;

  const EventAuditReport({
    required this.generatedAt,
    required this.entries,
    required this.categorySummaries,
  });

  // Top-line metrics ────────────────────────────────────────────────────────

  int get totalStages => entries.length;
  int get activeCount =>
      entries.where((e) => e.status == EventAuditStatus.active).length;
  int get dormantCount =>
      entries.where((e) => e.status == EventAuditStatus.dormant).length;
  int get silentCount =>
      entries.where((e) => e.status == EventAuditStatus.silent).length;
  int get absentCount =>
      entries.where((e) => e.status == EventAuditStatus.absent).length;

  /// Overall health score [0..1]. 1.0 = sve `active`, 0.0 = sve `absent`.
  /// Weighted: active=1.0, dormant=0.7, silent=0.3, absent=0.0.
  double get healthScore {
    if (entries.isEmpty) return 0.0;
    final sum = entries.fold<double>(0.0, (acc, e) {
      return acc +
          switch (e.status) {
            EventAuditStatus.active => 1.0,
            EventAuditStatus.dormant => 0.7,
            EventAuditStatus.silent => 0.3,
            EventAuditStatus.absent => 0.0,
          };
    });
    return sum / entries.length;
  }

  Map<String, dynamic> toJson() => {
        'generated_at': generatedAt.toIso8601String(),
        'total_stages': totalStages,
        'active_count': activeCount,
        'dormant_count': dormantCount,
        'silent_count': silentCount,
        'absent_count': absentCount,
        'health_score': healthScore,
        'category_summaries':
            categorySummaries.map((s) => s.toJson()).toList(),
        'entries': entries.map((e) => e.toJson()).toList(),
      };
}

/// Singleton audit service. Computes report on-demand iz 4 izvora.
class EventAuditService extends ChangeNotifier {
  static final EventAuditService instance = EventAuditService._();
  EventAuditService._();

  EventAuditReport? _lastReport;
  EventAuditReport? get lastReport => _lastReport;

  /// Generiše snapshot report iz svih izvora i kešira u `lastReport`.
  EventAuditReport generate({
    required SlotLabProjectProvider projectProvider,
  }) {
    final allStages = StageConfigurationService.instance.getAllStages();
    final coverage = StageCoverageService.instance.coverage;
    final registered = EventRegistry.instance.registeredStages.toSet();
    final assignments = projectProvider.audioAssignments;

    final entries = <EventAuditEntry>[];
    for (final def in allStages) {
      final stage = def.name;
      final cov = coverage[stage];
      final isReg = registered.contains(stage);
      final audioPath = assignments[stage];
      final hasAudio = audioPath != null && audioPath.isNotEmpty;
      final eventId =
          isReg ? EventRegistry.instance.getEventForStage(stage)?.id : null;

      entries.add(EventAuditEntry(
        stage: stage,
        category: def.category,
        isRegistered: isReg,
        hasAudio: hasAudio,
        audioPath: audioPath,
        triggerCount: cov?.triggerCount ?? 0,
        lastTriggered: cov?.lastTriggered,
        eventId: eventId,
      ));
    }

    // Per-category roll-up
    final byCategory = <StageCategory, List<EventAuditEntry>>{};
    for (final e in entries) {
      byCategory.putIfAbsent(e.category, () => []).add(e);
    }
    final summaries = <CategoryAuditSummary>[];
    for (final cat in StageCategory.values) {
      final list = byCategory[cat] ?? const [];
      summaries.add(CategoryAuditSummary(
        category: cat,
        total: list.length,
        absent: list
            .where((e) => e.status == EventAuditStatus.absent)
            .length,
        silent: list
            .where((e) => e.status == EventAuditStatus.silent)
            .length,
        dormant: list
            .where((e) => e.status == EventAuditStatus.dormant)
            .length,
        active: list
            .where((e) => e.status == EventAuditStatus.active)
            .length,
      ));
    }

    final report = EventAuditReport(
      generatedAt: DateTime.now(),
      entries: entries,
      categorySummaries: summaries,
    );
    _lastReport = report;
    notifyListeners();
    return report;
  }

  /// Eksportuje keširan report kao JSON fajl u
  /// `~/Library/Application Support/FluxForge Studio/audit/events_<ts>.json`.
  /// Vraća putanju do fajla ili `null` ako nema report-a.
  /// Mirror compliance_audit_trail.dart path strategije.
  ///
  /// FLUX_MASTER_TODO 0.5 B.1 BUG FIX (Sprint 8 QA) — koristi async file I/O
  /// (`writeAsString` umesto `writeAsStringSync`) da ne blokira UI thread
  /// dok se 60+ stage izveštaj ozbiljenom JSON encoder-om serializuje.
  Future<String?> exportToJson() async {
    final report = _lastReport;
    if (report == null) return null;
    final home = Platform.environment['HOME'];
    final base = (home != null && home.isNotEmpty)
        ? '$home/Library/Application Support/FluxForge Studio'
        : '/tmp/fluxforge-studio';
    final auditDir = Directory('$base/audit');
    if (!auditDir.existsSync()) {
      await auditDir.create(recursive: true);
    }
    final ts =
        report.generatedAt.toIso8601String().replaceAll(':', '-').split('.')[0];
    final filePath = '${auditDir.path}/events_$ts.json';
    final f = File(filePath);
    final json = const JsonEncoder.withIndent('  ').convert(report.toJson());
    await f.writeAsString(json, flush: true);
    return filePath;
  }
}
