import 'package:flutter/foundation.dart';
import '../models/aurexis_audit.dart';

/// AUREXIS™ Audit Trail Provider.
///
/// Manages session audit recording, filtering, and export.
/// Listens to AurexisProvider and AurexisProfileProvider changes
/// and records significant actions automatically.
class AurexisAuditProvider extends ChangeNotifier {
  late AuditSession _session;
  AuditActionType? _filterType;
  AuditSeverity? _filterSeverity;
  bool _recording = true;

  AurexisAuditProvider() {
    _session = AuditSession(
      sessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
      projectName: 'FluxForge Studio',
    );
    // Record session start
    record(
      action: AuditActionType.sessionMarker,
      description: 'AUREXIS audit session started',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  AuditSession get session => _session;
  bool get recording => _recording;
  AuditActionType? get filterType => _filterType;
  AuditSeverity? get filterSeverity => _filterSeverity;

  /// Get filtered entries based on current filters.
  List<AuditEntry> get filteredEntries {
    var entries = _session.entries;
    if (_filterType != null) {
      entries = entries.where((e) => e.action == _filterType).toList();
    }
    if (_filterSeverity != null) {
      entries = entries.where((e) => e.severity == _filterSeverity).toList();
    }
    return entries;
  }

  /// Total entry count (unfiltered).
  int get totalCount => _session.length;
  int get criticalCount => _session.criticalCount;
  int get warningCount => _session.warningCount;

  // ═══════════════════════════════════════════════════════════════════════════
  // RECORDING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Record an audit entry.
  void record({
    required AuditActionType action,
    required String description,
    AuditSeverity severity = AuditSeverity.info,
    String? previousValue,
    String? newValue,
    Map<String, dynamic>? metadata,
    int? deterministicSeed,
  }) {
    if (!_recording) return;

    _session.record(
      action: action,
      description: description,
      severity: severity,
      previousValue: previousValue,
      newValue: newValue,
      metadata: metadata,
      deterministicSeed: deterministicSeed,
    );
    notifyListeners();
  }

  /// Toggle recording on/off.
  void toggleRecording() {
    _recording = !_recording;
    record(
      action: AuditActionType.sessionMarker,
      description: _recording ? 'Recording resumed' : 'Recording paused',
    );
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FILTERING
  // ═══════════════════════════════════════════════════════════════════════════

  void setFilterType(AuditActionType? type) {
    _filterType = type;
    notifyListeners();
  }

  void setFilterSeverity(AuditSeverity? severity) {
    _filterSeverity = severity;
    notifyListeners();
  }

  void clearFilters() {
    _filterType = null;
    _filterSeverity = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export full session as JSON.
  String exportJson() => _session.toJsonString();

  /// Clear audit trail and start new session.
  void clearAndRestart() {
    _session = AuditSession(
      sessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
      projectName: 'FluxForge Studio',
    );
    record(
      action: AuditActionType.sessionMarker,
      description: 'Audit trail cleared and restarted',
    );
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONVENIENCE RECORDERS
  // ═══════════════════════════════════════════════════════════════════════════

  void recordProfileChange(String from, String to) {
    record(
      action: AuditActionType.profileChange,
      description: 'Profile changed: $from → $to',
      previousValue: from,
      newValue: to,
    );
  }

  void recordBehaviorChange(String group, String param, double from, double to) {
    record(
      action: AuditActionType.behaviorChange,
      description: '$group.$param: ${from.toStringAsFixed(3)} → ${to.toStringAsFixed(3)}',
      previousValue: from.toStringAsFixed(3),
      newValue: to.toStringAsFixed(3),
      metadata: {'group': group, 'param': param},
    );
  }

  void recordJurisdictionChange(String from, String to) {
    record(
      action: AuditActionType.jurisdictionChange,
      description: 'Jurisdiction: $from → $to',
      severity: AuditSeverity.critical,
      previousValue: from,
      newValue: to,
    );
  }

  void recordComplianceCheck(bool allPassed, int passed, int total) {
    record(
      action: AuditActionType.complianceCheck,
      description: 'Compliance check: $passed/$total ${allPassed ? "PASSED" : "FAILED"}',
      severity: allPassed ? AuditSeverity.info : AuditSeverity.warning,
      metadata: {'passed': passed, 'total': total, 'allPassed': allPassed},
    );
  }

  void recordConfigPush(Map<String, dynamic> config) {
    record(
      action: AuditActionType.configPush,
      description: 'Config pushed to engine (${config.length} parameters)',
      metadata: config,
    );
  }
}
