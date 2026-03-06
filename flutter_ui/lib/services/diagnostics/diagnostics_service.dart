import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Severity level for diagnostic findings
enum DiagnosticSeverity {
  /// System working correctly
  ok,
  /// Non-critical issue, system functional
  warning,
  /// Critical issue, feature broken or data loss risk
  error,
}

/// Single diagnostic finding from any checker
class DiagnosticFinding {
  final String checker;
  final DiagnosticSeverity severity;
  final String message;
  final String? detail;
  final DateTime timestamp;
  final String? affectedStage;

  DiagnosticFinding({
    required this.checker,
    required this.severity,
    required this.message,
    this.detail,
    this.affectedStage,
  }) : timestamp = DateTime.now();

  bool get isOk => severity == DiagnosticSeverity.ok;
  bool get isWarning => severity == DiagnosticSeverity.warning;
  bool get isError => severity == DiagnosticSeverity.error;

  @override
  String toString() => '[$checker] ${severity.name.toUpperCase()}: $message';
}

/// Result of a full diagnostic check run
class DiagnosticReport {
  final List<DiagnosticFinding> findings;
  final DateTime timestamp;
  final Duration duration;

  DiagnosticReport({
    required this.findings,
    required this.timestamp,
    required this.duration,
  });

  int get errorCount => findings.where((f) => f.isError).length;
  int get warningCount => findings.where((f) => f.isWarning).length;
  int get okCount => findings.where((f) => f.isOk).length;
  int get totalChecks => findings.length;
  bool get healthy => errorCount == 0;

  DiagnosticSeverity get overallSeverity {
    if (errorCount > 0) return DiagnosticSeverity.error;
    if (warningCount > 0) return DiagnosticSeverity.warning;
    return DiagnosticSeverity.ok;
  }

  List<DiagnosticFinding> get errors =>
      findings.where((f) => f.isError).toList();
  List<DiagnosticFinding> get warnings =>
      findings.where((f) => f.isWarning).toList();
}

/// Base class for all diagnostic checkers
abstract class DiagnosticChecker {
  /// Short name for this checker (e.g., "StageContract", "VoiceAuditor")
  String get name;

  /// Human-readable description
  String get description;

  /// Run all checks and return findings
  List<DiagnosticFinding> check();
}

/// Runtime event monitor — continuously watches for issues during operation
abstract class DiagnosticMonitor {
  /// Short name
  String get name;

  /// Start monitoring
  void start();

  /// Stop monitoring
  void stop();

  /// Get accumulated findings since last clear
  List<DiagnosticFinding> drain();
}

/// Central diagnostics service — orchestrates all checkers and monitors
class DiagnosticsService extends ChangeNotifier {
  static final DiagnosticsService instance = DiagnosticsService._();
  DiagnosticsService._() {
    _initLogFile();
  }

  final List<DiagnosticChecker> _checkers = [];
  final List<DiagnosticMonitor> _monitors = [];
  final List<DiagnosticFinding> _liveFindings = [];
  DiagnosticReport? _lastReport;
  Timer? _autoCheckTimer;
  bool _monitoring = false;
  File? _logFile;

  void _initLogFile() {
    try {
      final home = Platform.environment['HOME'] ?? '/tmp';
      _logFile = File('$home/diag.log');
      _logFile!.writeAsStringSync('--- DIAG LOG START ${DateTime.now()} ---\n');
    } catch (_) {}
  }

  void log(String msg) {
    try {
      _logFile?.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $msg\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  /// Last full diagnostic report
  DiagnosticReport? get lastReport => _lastReport;

  /// Live findings from monitors (accumulated since last drain)
  List<DiagnosticFinding> get liveFindings =>
      List.unmodifiable(_liveFindings);

  /// All registered checker names
  List<String> get checkerNames => _checkers.map((c) => c.name).toList();

  /// All registered monitor names
  List<String> get monitorNames => _monitors.map((m) => m.name).toList();

  /// Whether continuous monitoring is active
  bool get isMonitoring => _monitoring;

  /// Overall health status
  DiagnosticSeverity get health {
    if (_liveFindings.any((f) => f.isError)) return DiagnosticSeverity.error;
    if (_lastReport != null && !_lastReport!.healthy) {
      return DiagnosticSeverity.error;
    }
    if (_liveFindings.any((f) => f.isWarning)) {
      return DiagnosticSeverity.warning;
    }
    if (_lastReport != null && _lastReport!.warningCount > 0) {
      return DiagnosticSeverity.warning;
    }
    return DiagnosticSeverity.ok;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a diagnostic checker (runs on-demand)
  void registerChecker(DiagnosticChecker checker) {
    if (_checkers.any((c) => c.name == checker.name)) return;
    _checkers.add(checker);
  }

  /// Register a runtime monitor (runs continuously)
  void registerMonitor(DiagnosticMonitor monitor) {
    if (_monitors.any((m) => m.name == monitor.name)) return;
    _monitors.add(monitor);
    if (_monitoring) monitor.start();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ON-DEMAND CHECKS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Run ALL registered checkers and produce a report
  DiagnosticReport runFullCheck() {
    final sw = Stopwatch()..start();
    final findings = <DiagnosticFinding>[];

    for (final checker in _checkers) {
      try {
        findings.addAll(checker.check());
      } catch (e) {
        findings.add(DiagnosticFinding(
          checker: checker.name,
          severity: DiagnosticSeverity.error,
          message: 'Checker crashed: $e',
        ));
      }
    }

    // Drain monitor findings too
    for (final monitor in _monitors) {
      try {
        findings.addAll(monitor.drain());
      } catch (e) {
        findings.add(DiagnosticFinding(
          checker: monitor.name,
          severity: DiagnosticSeverity.error,
          message: 'Monitor drain crashed: $e',
        ));
      }
    }

    sw.stop();
    _lastReport = DiagnosticReport(
      findings: findings,
      timestamp: DateTime.now(),
      duration: sw.elapsed,
    );
    _liveFindings.clear();
    notifyListeners();
    return _lastReport!;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTINUOUS MONITORING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start continuous monitoring + periodic auto-checks
  void startMonitoring({Duration interval = const Duration(seconds: 30)}) {
    log('startMonitoring called, already=$_monitoring');
    if (_monitoring) return;
    _monitoring = true;
    for (final monitor in _monitors) {
      monitor.start();
    }
    // Confirm monitoring is active with a finding
    _liveFindings.add(DiagnosticFinding(
      checker: 'System',
      severity: DiagnosticSeverity.ok,
      message: 'Monitoring started — ${_monitors.length} monitors, '
          '${_checkers.length} checkers active. Spin to see results.',
    ));
    _autoCheckTimer = Timer.periodic(interval, (_) {
      _drainMonitors();
    });
    notifyListeners();
  }

  /// Stop continuous monitoring
  void stopMonitoring() {
    _autoCheckTimer?.cancel();
    _autoCheckTimer = null;
    _monitoring = false;
    for (final monitor in _monitors) {
      monitor.stop();
    }
    notifyListeners();
  }

  /// Drain all monitors and add findings to live list
  void _drainMonitors() {
    bool hasNew = false;
    for (final monitor in _monitors) {
      final findings = monitor.drain();
      if (findings.isNotEmpty) {
        for (final f in findings) {
          log('DRAIN [${f.checker}] ${f.severity.name}: ${f.message}${f.detail != null ? ' | ${f.detail}' : ''}');
        }
        _liveFindings.addAll(findings);
        hasNew = true;
      }
    }
    // Cap live findings to prevent unbounded growth
    if (_liveFindings.length > 500) {
      _liveFindings.removeRange(0, _liveFindings.length - 500);
    }
    if (hasNew) notifyListeners();
  }

  /// Forward a stage trigger to all active monitors.
  /// Call this from SlotLabProvider._triggerStage() for every stage.
  void onStageTrigger(String stageName, double engineTimestampMs) {
    if (!_monitoring) return;
    for (final monitor in _monitors) {
      if (monitor is StageTriggerAware) {
        (monitor as StageTriggerAware).onStageTrigger(stageName, engineTimestampMs);
      }
    }
  }

  /// Notify monitors that a spin has completed.
  /// Call this from SlotLabProvider when SPIN_END fires.
  void onSpinComplete() {
    log('onSpinComplete called, monitoring=$_monitoring');
    if (!_monitoring) return;
    for (final monitor in _monitors) {
      if (monitor is SpinCompleteAware) {
        (monitor as SpinCompleteAware).onSpinComplete();
      }
    }
    // Auto-drain after spin to surface findings quickly
    _drainMonitors();
  }

  /// Add a finding from external source (e.g., inline assertion failure)
  void reportFinding(DiagnosticFinding finding) {
    log('FINDING [${finding.checker}] ${finding.severity.name}: ${finding.message}');
    _liveFindings.add(finding);
    if (_liveFindings.length > 500) {
      _liveFindings.removeRange(0, _liveFindings.length - 500);
    }
    notifyListeners();
  }

  /// Clear all live findings
  void clearFindings() {
    _liveFindings.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO-SPIN QA
  // ═══════════════════════════════════════════════════════════════════════════

  bool _autoSpinRunning = false;
  int _autoSpinCompleted = 0;
  int _autoSpinTotal = 0;

  bool get autoSpinRunning => _autoSpinRunning;
  int get autoSpinCompleted => _autoSpinCompleted;
  int get autoSpinTotal => _autoSpinTotal;

  /// Run N automated spins, collecting diagnostics after each.
  /// [spinFn] should call provider.spin() and return the result.
  /// [beforeSpin] optional callback before each spin (e.g. grid changes).
  /// [label] optional label for this QA run shown in logs/findings.
  Future<void> runAutoSpinQA({
    required Future<dynamic> Function() spinFn,
    void Function(int spinIndex)? beforeSpin,
    String label = 'AutoSpinQA',
    int count = 20,
    Duration delayBetween = const Duration(milliseconds: 500),
  }) async {
    if (_autoSpinRunning) return;
    _autoSpinRunning = true;
    _autoSpinCompleted = 0;
    _autoSpinTotal = count;
    clearFindings();
    if (!_monitoring) startMonitoring();
    notifyListeners();

    log('═══ $label START — $count spins ═══');

    int errors = 0;
    int warnings = 0;

    for (int i = 0; i < count; i++) {
      if (!_autoSpinRunning) {
        log('$label CANCELLED at spin ${i + 1}/$count');
        break;
      }

      // Pre-spin callback (grid changes, config, etc.)
      if (beforeSpin != null) {
        try {
          beforeSpin(i);
        } catch (e) {
          log('$label beforeSpin($i) EXCEPTION: $e');
          reportFinding(DiagnosticFinding(
            checker: label,
            severity: DiagnosticSeverity.error,
            message: 'beforeSpin($i) threw: $e',
          ));
        }
      }

      log('── $label ${i + 1}/$count ──');

      try {
        final result = await spinFn();
        _drainMonitors();
        if (result == null) {
          log('$label ${i + 1}: spin() returned null');
        }
      } catch (e) {
        log('$label ${i + 1}: EXCEPTION $e');
        reportFinding(DiagnosticFinding(
          checker: label,
          severity: DiagnosticSeverity.error,
          message: 'Spin ${i + 1} threw: $e',
        ));
      }

      _autoSpinCompleted = i + 1;
      notifyListeners();

      await Future<void>.delayed(delayBetween);
    }

    // Final summary
    for (final f in _liveFindings) {
      if (f.isError) errors++;
      if (f.isWarning) warnings++;
    }

    log('═══ $label DONE — $_autoSpinCompleted/$count spins ═══');
    log('═══ SUMMARY: $errors errors, $warnings warnings, ${_liveFindings.length} total findings ═══');

    reportFinding(DiagnosticFinding(
      checker: label,
      severity: errors > 0
          ? DiagnosticSeverity.error
          : warnings > 0
              ? DiagnosticSeverity.warning
              : DiagnosticSeverity.ok,
      message: 'QA complete: $_autoSpinCompleted spins, $errors errors, $warnings warnings',
    ));

    _autoSpinRunning = false;
    notifyListeners();
  }

  void stopAutoSpin() {
    _autoSpinRunning = false;
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}

/// Interface for monitors that respond to individual stage triggers
abstract class StageTriggerAware {
  void onStageTrigger(String stageName, double engineTimestampMs);
}

/// Interface for monitors that respond to spin completion
abstract class SpinCompleteAware {
  void onSpinComplete();
}
