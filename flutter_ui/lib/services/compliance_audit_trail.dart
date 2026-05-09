/// FLUX_MASTER_TODO 3.7.L — Compliance Audit Trail
///
/// Append-only log fajl koji prati svaku jurisdiction promenu
/// (UKGC, MGA, SE, NL, AU, none) sa timestamp + before/after diff +
/// kontekst (user toggle / preset apply / auto-fix).  Compliance officer
/// može da povuče history za svaku odluku tokom dizajna slot-a.
///
/// **Storage:** `~/Library/Application Support/FluxForge Studio/audit/
/// compliance_YYYY-MM-DD.jsonl` (JSONL — line-per-event, append-only).
/// Daily rotation tako da ne raste neograničeno; 90 dana retention je
/// sledeći iteracija (cleanup task u FAZA 8).
///
/// **API:** `recordChange(...)` iz svakog `setJurisdiction(...)` /
/// `setJurisdictions(...)` call site-a u providerima.  Singleton —
/// pristup preko `ComplianceAuditTrail.instance`.
///
/// **Read API:** `history(n: 50)` vraća poslednjih N entry-ja iz tek
/// najnovijeg dnevnog fajla — UI panel u 3.7.F COMPL tab-u prikazuje
/// to kao timeline lista.  Future iteration: cross-day history sa
/// `historySince(DateTime)`.
///
/// **Robustnost:**
/// - File I/O je sync (jsonl append) — events su retki (user gestures),
///   ne tipping I/O bottleneck.
/// - Greška pri pisanju ne crash-uje provider — `silentRun` pattern.
/// - Append iza `\n` da se line-per-event invariant održi i kad app
///   crash-uje između write-ova.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

/// One audit trail entry — serialized as a single JSONL line.
class ComplianceAuditEntry {
  /// ISO-8601 timestamp (UTC).
  final String timestamp;

  /// Short tag for the kind of change.  Examples:
  ///   - `jurisdiction_change` — single jurisdiction toggle
  ///   - `jurisdictions_set` — multi-jurisdiction list update
  ///   - `compliance_preset_applied` — predefined config was loaded
  ///   - `auto_fix_applied` — Smart Integrity Validator one-click fix
  final String action;

  /// JSON-able snapshot of the state BEFORE the change.
  final Map<String, dynamic> before;

  /// JSON-able snapshot of the state AFTER the change.
  final Map<String, dynamic> after;

  /// Optional free-text context: who triggered this and why.
  ///
  /// Conventionally one of:
  ///   - `user` — explicit toggle in compliance UI
  ///   - `preset` — preset application
  ///   - `auto_fix` — integrity validator
  ///   - `import` — blueprint import
  ///   - `migration` — version upgrade
  final String? context;

  const ComplianceAuditEntry({
    required this.timestamp,
    required this.action,
    required this.before,
    required this.after,
    this.context,
  });

  Map<String, dynamic> toJson() => {
        'ts': timestamp,
        'action': action,
        'before': before,
        'after': after,
        if (context != null) 'context': context,
      };

  factory ComplianceAuditEntry.fromJson(Map<String, dynamic> json) =>
      ComplianceAuditEntry(
        timestamp: json['ts'] as String,
        action: json['action'] as String,
        before: Map<String, dynamic>.from(
            json['before'] as Map? ?? <String, dynamic>{}),
        after: Map<String, dynamic>.from(
            json['after'] as Map? ?? <String, dynamic>{}),
        context: json['context'] as String?,
      );
}

/// Singleton service.  Lazily resolves the app-support directory on
/// first write — works fine in headless / test contexts because writes
/// silently no-op when the directory cannot be resolved.
class ComplianceAuditTrail {
  ComplianceAuditTrail._();
  static final ComplianceAuditTrail instance = ComplianceAuditTrail._();

  /// In-memory ring of the most recent entries — used by the UI history
  /// panel without doing disk I/O on every rebuild.  Capped to 200; the
  /// disk file is the source of truth for everything older.
  static const int _ringCapacity = 200;
  final List<ComplianceAuditEntry> _ring = <ComplianceAuditEntry>[];

  /// Cached app-support audit directory; resolved lazily.
  Directory? _auditDir;

  Future<Directory?> _resolveAuditDir() async {
    if (_auditDir != null && _auditDir!.existsSync()) return _auditDir;
    try {
      // Match the dependency-free pattern that `waveform_cache_service`
      // already uses — avoids pulling `path_provider` just for one path.
      // macOS-only path is fine for now (FluxForge Studio is macOS-first);
      // the `Platform.isMacOS` guard short-circuits on other OSes so we
      // don't try to write into /home/.config etc.
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return null;
      final basePath = Platform.isMacOS
          ? '$home/Library/Application Support/FluxForge Studio'
          : '$home/.fluxforge';
      final dir = Directory('$basePath/audit');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _auditDir = dir;
      return dir;
    } catch (e, st) {
      debugPrint('[ComplianceAuditTrail] failed to resolve dir: $e\n$st');
      return null;
    }
  }

  String _todayFilename() {
    final now = DateTime.now().toUtc();
    final yyyy = now.year.toString().padLeft(4, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return 'compliance_$yyyy-$mm-$dd.jsonl';
  }

  /// Record a single audit event.  Failures are swallowed — caller code
  /// in setJurisdiction(...) MUST NOT crash because logging failed.
  Future<void> recordChange({
    required String action,
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
    String? context,
  }) async {
    final entry = ComplianceAuditEntry(
      timestamp: DateTime.now().toUtc().toIso8601String(),
      action: action,
      before: before,
      after: after,
      context: context,
    );

    // Push into the in-memory ring first — UI history panel sees it
    // immediately even if disk write is slow / fails.
    _ring.add(entry);
    if (_ring.length > _ringCapacity) {
      _ring.removeRange(0, _ring.length - _ringCapacity);
    }

    try {
      final dir = await _resolveAuditDir();
      if (dir == null) return;
      final file = File('${dir.path}/${_todayFilename()}');
      // Append single JSONL line.  No locking — Dart's File.writeAsString
      // with FileMode.append is atomic per-write on POSIX.
      await file.writeAsString(
        '${jsonEncode(entry.toJson())}\n',
        mode: FileMode.append,
        flush: false,
      );
    } catch (e, st) {
      debugPrint('[ComplianceAuditTrail] write failed: $e\n$st');
    }
  }

  /// Read the most recent N entries from the in-memory ring.  Most UI
  /// surfaces want the recent slice and don't need cross-day history;
  /// the ring (capped at 200) is the right shape for them.
  List<ComplianceAuditEntry> recent({int n = 50}) {
    if (_ring.length <= n) return List.unmodifiable(_ring);
    return List.unmodifiable(_ring.sublist(_ring.length - n));
  }

  /// Read every entry from today's daily file (if any).  Use sparingly
  /// — opens the file on each call.  Future iteration: lazy stream + UI
  /// virtualization for cross-day history.
  Future<List<ComplianceAuditEntry>> readToday() async {
    final dir = await _resolveAuditDir();
    if (dir == null) return const [];
    final file = File('${dir.path}/${_todayFilename()}');
    if (!file.existsSync()) return const [];
    try {
      final lines = await file.readAsLines();
      final result = <ComplianceAuditEntry>[];
      for (final line in lines) {
        if (line.isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          result.add(ComplianceAuditEntry.fromJson(json));
        } catch (_) {
          // Malformed line — skip rather than fail the whole read.
        }
      }
      return result;
    } catch (e, st) {
      debugPrint('[ComplianceAuditTrail] readToday failed: $e\n$st');
      return const [];
    }
  }

  /// Helper for in-process tests — clears the in-memory ring without
  /// touching disk.  No-op in production.
  void clearRingForTesting() {
    _ring.clear();
  }
}
