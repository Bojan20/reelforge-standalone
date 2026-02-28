import 'dart:convert';

/// AUREXIS™ Audit Trail — Session recording and change logging.
///
/// Records every significant AUREXIS operation for compliance auditing,
/// session replay, and debugging. Supports JSON export for regulatory
/// submission and deterministic replay verification.

/// Type of auditable action.
enum AuditActionType {
  /// Profile was selected or changed.
  profileChange,

  /// Behavior parameter was modified.
  behaviorChange,

  /// Jurisdiction was set or changed.
  jurisdictionChange,

  /// Compliance check was run.
  complianceCheck,

  /// Cabinet simulator profile was changed.
  cabinetChange,

  /// Engine was initialized or reset.
  engineLifecycle,

  /// Configuration was pushed to engine.
  configPush,

  /// A/B comparison was activated/toggled.
  abComparison,

  /// Re-theme mapping was applied.
  reThemeApply,

  /// Platform target was changed.
  platformChange,

  /// Custom profile was saved/deleted.
  customProfileOp,

  /// Session start/end marker.
  sessionMarker;

  String get label => switch (this) {
        profileChange => 'Profile',
        behaviorChange => 'Behavior',
        jurisdictionChange => 'Jurisdiction',
        complianceCheck => 'Compliance',
        cabinetChange => 'Cabinet',
        engineLifecycle => 'Engine',
        configPush => 'Config',
        abComparison => 'A/B',
        reThemeApply => 'Re-Theme',
        platformChange => 'Platform',
        customProfileOp => 'Custom',
        sessionMarker => 'Session',
      };

  String get icon => switch (this) {
        profileChange => 'P',
        behaviorChange => 'B',
        jurisdictionChange => 'J',
        complianceCheck => 'C',
        cabinetChange => 'K',
        engineLifecycle => 'E',
        configPush => '→',
        abComparison => 'AB',
        reThemeApply => 'RT',
        platformChange => 'PL',
        customProfileOp => 'CP',
        sessionMarker => '●',
      };
}

/// Severity level for audit entries.
enum AuditSeverity {
  /// Informational (normal operation).
  info,

  /// Warning (potential issue).
  warning,

  /// Critical (compliance-relevant).
  critical;

  String get label => switch (this) {
        info => 'INFO',
        warning => 'WARN',
        critical => 'CRIT',
      };
}

/// A single audit trail entry.
class AuditEntry {
  /// Unique sequential ID.
  final int id;

  /// When this action occurred.
  final DateTime timestamp;

  /// Type of action.
  final AuditActionType action;

  /// Severity level.
  final AuditSeverity severity;

  /// Human-readable description.
  final String description;

  /// Previous value (for changes).
  final String? previousValue;

  /// New value (for changes).
  final String? newValue;

  /// Additional metadata.
  final Map<String, dynamic>? metadata;

  /// Deterministic seed at time of action (for replay verification).
  final int? deterministicSeed;

  const AuditEntry({
    required this.id,
    required this.timestamp,
    required this.action,
    this.severity = AuditSeverity.info,
    required this.description,
    this.previousValue,
    this.newValue,
    this.metadata,
    this.deterministicSeed,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'action': action.name,
        'severity': severity.name,
        'description': description,
        if (previousValue != null) 'prev': previousValue,
        if (newValue != null) 'new': newValue,
        if (metadata != null) 'meta': metadata,
        if (deterministicSeed != null) 'seed': deterministicSeed,
      };

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    return AuditEntry(
      id: json['id'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
      action: AuditActionType.values.firstWhere(
        (a) => a.name == json['action'],
        orElse: () => AuditActionType.sessionMarker,
      ),
      severity: AuditSeverity.values.firstWhere(
        (s) => s.name == json['severity'],
        orElse: () => AuditSeverity.info,
      ),
      description: json['description'] as String,
      previousValue: json['prev'] as String?,
      newValue: json['new'] as String?,
      metadata: json['meta'] as Map<String, dynamic>?,
      deterministicSeed: json['seed'] as int?,
    );
  }
}

/// Session audit trail container.
class AuditSession {
  /// Session identifier.
  final String sessionId;

  /// When the session started.
  final DateTime startedAt;

  /// Project/profile name.
  final String projectName;

  /// All entries in this session.
  final List<AuditEntry> entries;

  /// Running entry counter.
  int _nextId;

  AuditSession({
    required this.sessionId,
    DateTime? startedAt,
    this.projectName = '',
    List<AuditEntry>? entries,
  })  : startedAt = startedAt ?? DateTime.now(),
        entries = entries ?? [],
        _nextId = (entries?.length ?? 0);

  /// Add a new entry to the trail.
  AuditEntry record({
    required AuditActionType action,
    required String description,
    AuditSeverity severity = AuditSeverity.info,
    String? previousValue,
    String? newValue,
    Map<String, dynamic>? metadata,
    int? deterministicSeed,
  }) {
    final entry = AuditEntry(
      id: _nextId++,
      timestamp: DateTime.now(),
      action: action,
      severity: severity,
      description: description,
      previousValue: previousValue,
      newValue: newValue,
      metadata: metadata,
      deterministicSeed: deterministicSeed,
    );
    entries.add(entry);
    return entry;
  }

  /// Total entries count.
  int get length => entries.length;

  /// Get entries filtered by action type.
  List<AuditEntry> byType(AuditActionType type) =>
      entries.where((e) => e.action == type).toList();

  /// Get entries filtered by severity.
  List<AuditEntry> bySeverity(AuditSeverity severity) =>
      entries.where((e) => e.severity == severity).toList();

  /// Get entries within a time range.
  List<AuditEntry> inRange(DateTime start, DateTime end) =>
      entries.where((e) => e.timestamp.isAfter(start) && e.timestamp.isBefore(end)).toList();

  /// Count of critical entries.
  int get criticalCount =>
      entries.where((e) => e.severity == AuditSeverity.critical).length;

  /// Count of warning entries.
  int get warningCount =>
      entries.where((e) => e.severity == AuditSeverity.warning).length;

  /// Export full session as JSON string.
  String toJsonString() => jsonEncode({
        'sessionId': sessionId,
        'startedAt': startedAt.toIso8601String(),
        'projectName': projectName,
        'entryCount': entries.length,
        'criticalCount': criticalCount,
        'warningCount': warningCount,
        'entries': entries.map((e) => e.toJson()).toList(),
      });

  /// Import from JSON string.
  factory AuditSession.fromJson(Map<String, dynamic> json) {
    final entries = (json['entries'] as List<dynamic>?)
            ?.map((e) => AuditEntry.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return AuditSession(
      sessionId: json['sessionId'] as String,
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'] as String)
          : null,
      projectName: json['projectName'] as String? ?? '',
      entries: entries,
    );
  }
}
