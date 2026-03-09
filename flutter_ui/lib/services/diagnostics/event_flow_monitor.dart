import 'diagnostics_service.dart';
import '../event_registry.dart';

/// Runtime monitor that watches EventRegistry triggers for anomalies.
///
/// Detects:
/// 1. Double triggers — same stage fired twice within 50ms
/// 2. Orphan triggers — stage triggered but no audio event registered
/// 3. Rapid fire — same stage fired >5 times in 1 second
/// 4. Sequence violations — REEL_STOP before UI_SPIN_PRESS in same spin
class EventFlowMonitor extends DiagnosticMonitor
    implements StageTriggerAware, SpinCompleteAware {
  final List<DiagnosticFinding> _findings = [];
  final Map<String, DateTime> _lastTriggerTime = {};
  final Map<String, int> _triggerCountWindow = {};
  DateTime? _windowStart;
  bool _active = false;

  // Track spin state for sequence validation
  bool _spinActive = false;
  bool _seenUiSpinPress = false;

  /// Stages that fire multiple times per spin (per-reel, per-symbol, looping)
  /// Shared exclusion list for both double-trigger and rapid-fire detection
  static const _perReelPrefixes = [
    'REEL_SPINNING_START_', 'REEL_SPINNING_', 'REEL_STOP_',
    'SCATTER_LAND', 'SYMBOL_LAND',
    'ANTICIPATION_TENSION',
  ];
  /// Suffixes for per-symbol stages ({SYMBOL}_WIN naming convention)
  static const _perSymbolSuffixes = ['_WIN'];
  static const _perReelExact = {
    'REEL_SPINNING_START', 'REEL_SPINNING', 'REEL_SPINNING_STOP',
    'REEL_STOP', 'REEL_SPIN_LOOP', 'IDLE_LOOP', 'ROLLUP_TICK',
  };

  // Per-spin counters for summary
  int _spinStageCount = 0;
  int _spinNumber = 0;

  @override
  String get name => 'EventFlow';

  @override
  void start() {
    _active = true;
    _findings.clear();
    _lastTriggerTime.clear();
    _resetWindow();
    _resetSpinState();
  }

  @override
  void stop() {
    _active = false;
  }

  @override
  List<DiagnosticFinding> drain() {
    final drained = List<DiagnosticFinding>.from(_findings);
    _findings.clear();
    return drained;
  }

  @override
  void onStageTrigger(String stageName, double engineTimestampMs) {
    if (!_active) return;

    final now = DateTime.now();
    final upper = stageName.toUpperCase();

    // ── Double trigger detection ──
    // Skip per-reel and per-symbol stages (fire multiple times per spin, not real doubles)
    final isPerReelStage = _perReelExact.contains(upper) ||
        _perReelPrefixes.any((p) => upper.startsWith(p)) ||
        _perSymbolSuffixes.any((s) => upper.endsWith(s));
    if (!isPerReelStage) {
      final lastTime = _lastTriggerTime[upper];
      if (lastTime != null) {
        final elapsed = now.difference(lastTime).inMilliseconds;
        if (elapsed < 50 && elapsed >= 0) {
          _findings.add(DiagnosticFinding(
            checker: name,
            severity: DiagnosticSeverity.warning,
            message: 'Double trigger: $upper fired twice within ${elapsed}ms',
            affectedStage: upper,
          ));
        }
      }
    }
    _lastTriggerTime[upper] = now;

    // ── Rapid fire detection ──
    _ensureWindow(now);
    _triggerCountWindow[upper] = (_triggerCountWindow[upper] ?? 0) + 1;
    final count = _triggerCountWindow[upper]!;
    if (count > 5 && !isPerReelStage) {
      _findings.add(DiagnosticFinding(
        checker: name,
        severity: DiagnosticSeverity.warning,
        message: 'Rapid fire: $upper triggered $count times in 1 second',
        affectedStage: upper,
      ));
      // Reset to avoid spamming
      _triggerCountWindow[upper] = 0;
    }

    _spinStageCount++;

    // ── Spin sequence validation ──
    if (upper == 'UI_SPIN_PRESS') {
      _resetSpinState();
      _spinActive = true;
      _seenUiSpinPress = true;
      _spinStageCount = 1;
    } else if (upper == 'REEL_STOP' || upper.startsWith('REEL_STOP_')) {
      if (_spinActive && !_seenUiSpinPress) {
        _findings.add(DiagnosticFinding(
          checker: name,
          severity: DiagnosticSeverity.error,
          message: 'REEL_STOP without prior UI_SPIN_PRESS',
          detail: 'Stage sequence violated — spin not properly initiated',
          affectedStage: upper,
        ));
      }
    } else if (upper == 'SPIN_END') {
      _spinActive = false;
    }

    // ── Orphan trigger — no audio event for this stage ──
    final registry = EventRegistry.instance;
    if (!registry.hasEventForStage(stageName) &&
        !_isInternalStage(upper)) {
      // Only warn for stages that typically have audio
      if (_isAudioExpectedStage(upper)) {
        _findings.add(DiagnosticFinding(
          checker: name,
          severity: DiagnosticSeverity.ok,
          message: 'No audio for $upper (may be intentional)',
          affectedStage: upper,
        ));
      }
    }
  }

  @override
  void onSpinComplete() {
    if (!_active) return;
    _spinNumber++;
    // Always emit a summary so the user sees the system is working
    final issueCount = _findings.where((f) => !f.isOk).length;
    if (issueCount == 0) {
      _findings.add(DiagnosticFinding(
        checker: name,
        severity: DiagnosticSeverity.ok,
        message: 'Spin #$_spinNumber OK — $_spinStageCount stages, no issues',
      ));
    }
    _spinStageCount = 0;
  }

  void _ensureWindow(DateTime now) {
    if (_windowStart == null ||
        now.difference(_windowStart!).inMilliseconds > 1000) {
      _windowStart = now;
      _triggerCountWindow.clear();
    }
  }

  void _resetWindow() {
    _windowStart = null;
    _triggerCountWindow.clear();
  }

  void _resetSpinState() {
    _spinActive = false;
    _seenUiSpinPress = false;
    // Clear trigger time cache to prevent unbounded map growth across spins
    _lastTriggerTime.clear();
  }

  bool _isInternalStage(String upper) {
    // Internal/meta stages that don't need audio
    return upper == 'EVALUATE_WINS' ||
        upper == 'REEL_SPINNING' ||
        upper.startsWith('REEL_SPINNING_') ||
        upper == 'REEL_SPIN_LOOP' ||
        upper == 'ANTICIPATION_OFF' ||
        upper == 'WIN_LINE_HIDE' ||
        upper == 'NO_WIN';
  }

  bool _isAudioExpectedStage(String upper) {
    // Stages where missing audio is noteworthy
    return upper == 'UI_SPIN_PRESS' ||
        upper.startsWith('REEL_STOP') ||
        upper == 'SPIN_END' ||
        upper.startsWith('WIN_PRESENT') ||
        upper.startsWith('SCATTER_LAND') ||
        upper.startsWith('BIG_WIN') ||
        upper == 'ROLLUP_START';
  }
}
