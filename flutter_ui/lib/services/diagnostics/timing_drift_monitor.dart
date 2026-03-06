import 'diagnostics_service.dart';

/// Monitors timing drift between engine-planned timestamps and actual trigger times.
///
/// When a stage is triggered, compares the engine's planned timestamp (from Rust)
/// with the actual wall-clock time. Drift > threshold = warning.
/// This catches:
/// - Timer inaccuracies in Dart
/// - UI thread blocking causing delayed stage triggers
/// - Wrong timestamp values from engine
class TimingDriftMonitor extends DiagnosticMonitor
    implements StageTriggerAware, SpinCompleteAware {
  final List<DiagnosticFinding> _findings = [];
  bool _active = false;

  /// Drift threshold in milliseconds — above this is a warning
  final int warningThresholdMs;

  /// Drift threshold for error — above this the system is unusable
  final int errorThresholdMs;

  // Track spin start wall-clock for relative timing
  DateTime? _spinStartWallClock;
  double? _spinStartEngineMs;

  // Stats
  int _totalSamples = 0;
  double _totalDriftMs = 0;
  double _maxDriftMs = 0;
  String? _maxDriftStage;

  TimingDriftMonitor({
    this.warningThresholdMs = 150,
    this.errorThresholdMs = 500,
  });

  @override
  String get name => 'TimingDrift';

  @override
  void start() {
    _active = true;
    _findings.clear();
    _resetStats();
  }

  @override
  void stop() {
    _active = false;
  }

  @override
  List<DiagnosticFinding> drain() {
    final drained = List<DiagnosticFinding>.from(_findings);

    // Add summary finding if we have data
    if (_totalSamples > 0) {
      final avgDrift = _totalDriftMs / _totalSamples;
      drained.add(DiagnosticFinding(
        checker: name,
        severity: avgDrift > warningThresholdMs
            ? DiagnosticSeverity.warning
            : DiagnosticSeverity.ok,
        message: 'Avg drift: ${avgDrift.toStringAsFixed(1)}ms '
            '(max: ${_maxDriftMs.toStringAsFixed(1)}ms on $_maxDriftStage, '
            '$_totalSamples samples)',
      ));
      _resetStats();
    }

    _findings.clear();
    return drained;
  }

  @override
  void onStageTrigger(String stageName, double engineTimestampMs) {
    if (!_active) return;

    final now = DateTime.now();
    final upper = stageName.toUpperCase();

    // On UI_SPIN_PRESS, mark spin start reference point
    if (upper == 'UI_SPIN_PRESS') {
      _spinStartWallClock = now;
      _spinStartEngineMs = engineTimestampMs;
      return; // No drift to measure for first stage
    }

    // Can't measure drift without reference
    if (_spinStartWallClock == null || _spinStartEngineMs == null) return;

    // Calculate expected wall-clock time based on engine timestamps
    final engineDeltaMs = engineTimestampMs - _spinStartEngineMs!;
    final wallDeltaMs =
        now.difference(_spinStartWallClock!).inMilliseconds.toDouble();
    final driftMs = (wallDeltaMs - engineDeltaMs).abs();

    // Track stats
    _totalSamples++;
    _totalDriftMs += driftMs;
    if (driftMs > _maxDriftMs) {
      _maxDriftMs = driftMs;
      _maxDriftStage = upper;
    }

    // Report significant drift
    if (driftMs > errorThresholdMs) {
      _findings.add(DiagnosticFinding(
        checker: name,
        severity: DiagnosticSeverity.error,
        message: '$upper: ${driftMs.toStringAsFixed(0)}ms drift '
            '(engine: ${engineDeltaMs.toStringAsFixed(0)}ms, '
            'wall: ${wallDeltaMs.toStringAsFixed(0)}ms)',
        detail: 'Audio/visual sync severely broken. '
            'Check for UI thread blocking or wrong engine timestamps.',
        affectedStage: upper,
      ));
    } else if (driftMs > warningThresholdMs) {
      _findings.add(DiagnosticFinding(
        checker: name,
        severity: DiagnosticSeverity.warning,
        message: '$upper: ${driftMs.toStringAsFixed(0)}ms drift',
        affectedStage: upper,
      ));
    }
  }

  @override
  void onSpinComplete() {
    if (!_active || _totalSamples == 0) return;
    final avgDrift = _totalDriftMs / _totalSamples;
    _findings.add(DiagnosticFinding(
      checker: name,
      severity: avgDrift > warningThresholdMs
          ? DiagnosticSeverity.warning
          : DiagnosticSeverity.ok,
      message: 'Drift avg: ${avgDrift.toStringAsFixed(1)}ms, '
          'max: ${_maxDriftMs.toStringAsFixed(1)}ms${_maxDriftStage != null ? ' ($maxDriftStage)' : ''}, '
          '$_totalSamples samples',
    ));
    _resetStats();
  }

  String? get maxDriftStage => _maxDriftStage;

  void _resetStats() {
    _totalSamples = 0;
    _totalDriftMs = 0;
    _maxDriftMs = 0;
    _maxDriftStage = null;
  }
}
