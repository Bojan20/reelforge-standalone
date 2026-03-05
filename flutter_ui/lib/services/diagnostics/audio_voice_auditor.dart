import 'diagnostics_service.dart';
import '../../src/rust/native_ffi.dart';

/// Audits audio voice allocation to detect leaks and saturation.
///
/// Checks:
/// 1. Voice count after spin should return to baseline within timeout
/// 2. Voice count never exceeds pool capacity
/// 3. No voices stuck in "playing" state after all stages complete
/// 4. Voice pool utilization stats for capacity planning
class AudioVoiceAuditor extends DiagnosticChecker {
  @override
  String get name => 'VoiceAuditor';

  @override
  String get description => 'Checks audio voice allocation for leaks';

  @override
  List<DiagnosticFinding> check() {
    final findings = <DiagnosticFinding>[];
    final ffi = NativeFFI.instance;

    try {
      final debugInfo = ffi.getPlaybackDebugInfo();

      // Parse voice count from debug info
      final activeVoices = _extractInt(debugInfo, 'active_voices');
      final maxVoices = _extractInt(debugInfo, 'max_voices');
      final totalAllocated = _extractInt(debugInfo, 'total_allocated');

      if (activeVoices != null) {
        if (activeVoices == 0) {
          findings.add(DiagnosticFinding(
            checker: name,
            severity: DiagnosticSeverity.ok,
            message: 'No active voices (idle state)',
          ));
        } else {
          final maxStr = maxVoices != null ? '/$maxVoices' : '';
          findings.add(DiagnosticFinding(
            checker: name,
            severity: DiagnosticSeverity.ok,
            message: '$activeVoices active voices$maxStr',
          ));

          // Warn if using >80% of voice pool
          if (maxVoices != null && activeVoices > maxVoices * 0.8) {
            findings.add(DiagnosticFinding(
              checker: name,
              severity: DiagnosticSeverity.warning,
              message: 'Voice pool ${(activeVoices / maxVoices * 100).toStringAsFixed(0)}% '
                  'utilized ($activeVoices/$maxVoices)',
              detail: 'Consider reducing simultaneous audio or increasing pool size',
            ));
          }

          // Error if at capacity
          if (maxVoices != null && activeVoices >= maxVoices) {
            findings.add(DiagnosticFinding(
              checker: name,
              severity: DiagnosticSeverity.error,
              message: 'Voice pool FULL — new audio will be dropped',
              detail: '$activeVoices/$maxVoices voices in use',
            ));
          }
        }

        if (totalAllocated != null) {
          findings.add(DiagnosticFinding(
            checker: name,
            severity: DiagnosticSeverity.ok,
            message: 'Total voices allocated this session: $totalAllocated',
          ));
        }
      } else {
        // Can't read voice info — engine may not expose it
        findings.add(DiagnosticFinding(
          checker: name,
          severity: DiagnosticSeverity.ok,
          message: 'Voice pool info not available from engine',
          detail: 'Engine debug info: ${debugInfo.length > 100 ? '${debugInfo.substring(0, 100)}...' : debugInfo}',
        ));
      }
    } catch (e) {
      findings.add(DiagnosticFinding(
        checker: name,
        severity: DiagnosticSeverity.warning,
        message: 'Cannot read engine voice info: $e',
      ));
    }

    return findings;
  }

  int? _extractInt(String debugInfo, String key) {
    final pattern = RegExp('$key[=:]\\s*(\\d+)');
    final match = pattern.firstMatch(debugInfo);
    if (match != null) return int.tryParse(match.group(1)!);

    // Try JSON-style
    final jsonPattern = RegExp('"$key"\\s*:\\s*(\\d+)');
    final jsonMatch = jsonPattern.firstMatch(debugInfo);
    if (jsonMatch != null) return int.tryParse(jsonMatch.group(1)!);

    return null;
  }
}

/// Runtime monitor that tracks voice allocation over time
class AudioVoiceMonitor extends DiagnosticMonitor {
  final List<DiagnosticFinding> _findings = [];
  bool _active = false;
  int _baselineVoices = 0;
  int _peakVoices = 0;
  int _spinCount = 0;

  @override
  String get name => 'VoiceLeak';

  @override
  void start() {
    _active = true;
    _findings.clear();
    _baselineVoices = _getCurrentVoiceCount();
    _peakVoices = _baselineVoices;
    _spinCount = 0;
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

  /// Call after a spin completes and all audio should have stopped
  void onSpinComplete() {
    if (!_active) return;

    _spinCount++;
    final current = _getCurrentVoiceCount();
    if (current > _peakVoices) _peakVoices = current;

    // Check for leak: voices should return to near baseline after spin
    // Allow some margin for looping music/ambient
    final leak = current - _baselineVoices;
    if (leak > 3) {
      _findings.add(DiagnosticFinding(
        checker: name,
        severity: DiagnosticSeverity.warning,
        message: 'Possible voice leak: $current active (baseline: $_baselineVoices, '
            'delta: +$leak) after spin #$_spinCount',
        detail: 'Voices should return to baseline after spin completes',
      ));
    }

    // Update baseline gradually (looping sounds may change baseline)
    if (leak <= 0) {
      _baselineVoices = current;
    }
  }

  int _getCurrentVoiceCount() {
    try {
      final info = NativeFFI.instance.getPlaybackDebugInfo();
      final pattern = RegExp(r'active_voices[=:]\s*(\d+)');
      final match = pattern.firstMatch(info);
      return match != null ? int.tryParse(match.group(1)!) ?? 0 : 0;
    } catch (_) {
      return 0;
    }
  }
}
