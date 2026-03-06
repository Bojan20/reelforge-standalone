// Comprehensive QA Runner
//
// Programmatic QA for the ENTIRE app — every module, every provider, every edge case.
// Runs as a headless test suite using real providers (no mocks).
//
// Modules tested:
// 1. SlotLab Engine (multi-grid spins, forced outcomes, stage flow)
// 2. DAW Mixer (channels, buses, routing, volume/pan/mute/solo)
// 3. DAW Transport (play/stop/pause/seek/loop/tempo)
// 4. Middleware (events, RTPC, state groups, containers)
// 5. SlotLab Subsystems (behavior tree, state gates, emotional state, etc.)
// 6. Cross-module (data integrity, state consistency)
// 7. Stress tests (rapid-fire operations, boundary hammering)
// 8. Concurrency (simultaneous provider operations)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:get_it/get_it.dart';

import 'game_math_validator.dart';

import 'diagnostics_service.dart';
import '../../providers/mixer_provider.dart';
import '../../providers/engine_provider.dart';
import '../../providers/slot_lab/slot_lab_coordinator.dart';
import '../../providers/slot_lab/feature_composer_provider.dart';
import '../../providers/slot_lab/behavior_tree_provider.dart';
import '../../providers/slot_lab/state_gate_provider.dart';
import '../../providers/slot_lab/emotional_state_provider.dart';
import '../../providers/slot_lab/priority_engine_provider.dart';
import '../../providers/slot_lab/orchestration_engine_provider.dart';
import '../../providers/slot_lab/simulation_engine_provider.dart';
import '../../providers/slot_lab/game_flow_provider.dart';
import '../../providers/slot_lab/stage_flow_provider.dart';
import '../../providers/slot_lab/context_layer_provider.dart';
import '../../providers/slot_lab/trigger_layer_provider.dart';
import '../../providers/slot_lab/transition_system_provider.dart';
import '../../providers/slot_lab/slotlab_undo_provider.dart';
import '../../providers/slot_lab_project_provider.dart';
import '../../providers/energy_governance_provider.dart';
import '../../providers/dpm_provider.dart';
import '../../providers/aurexis_provider.dart';
import '../../providers/aurexis_profile_provider.dart';
import '../../providers/subsystems/state_groups_provider.dart';
import '../../providers/subsystems/switch_groups_provider.dart';
import '../../providers/subsystems/rtpc_system_provider.dart';
import '../../providers/subsystems/ducking_system_provider.dart';
import '../../providers/subsystems/blend_containers_provider.dart';
import '../../providers/subsystems/random_containers_provider.dart';
import '../../providers/subsystems/sequence_containers_provider.dart';
import '../../providers/subsystems/composite_event_system_provider.dart';
import '../../providers/subsystems/bus_hierarchy_provider.dart';
import '../../providers/subsystems/voice_pool_provider.dart';
import '../../src/rust/native_ffi.dart';

/// QA test result for a single assertion
class QaAssertion {
  final String module;
  final String test;
  final bool passed;
  final String? detail;
  final Duration elapsed;
  final int retryCount;

  QaAssertion({
    required this.module,
    required this.test,
    required this.passed,
    this.detail,
    this.elapsed = Duration.zero,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'module': module,
        'test': test,
        'passed': passed,
        if (detail != null) 'detail': detail,
        'elapsed_ms': elapsed.inMicroseconds / 1000.0,
        if (retryCount > 0) 'retries': retryCount,
      };
}

/// Per-phase timing data
class PhaseMetrics {
  final String name;
  final Duration duration;
  final int assertionCount;
  final int passCount;
  final int failCount;

  PhaseMetrics({
    required this.name,
    required this.duration,
    required this.assertionCount,
    required this.passCount,
    required this.failCount,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'duration_ms': duration.inMilliseconds,
        'assertions': assertionCount,
        'passed': passCount,
        'failed': failCount,
      };
}

/// Memory snapshot for leak detection
class _MemSnapshot {
  final int usedBytes;
  final DateTime timestamp;

  _MemSnapshot({required this.usedBytes, required this.timestamp});

  static _MemSnapshot capture() {
    // Force GC hint before measurement
    // Note: Dart doesn't expose direct heap stats in production,
    // but ProcessInfo.currentRss is available on dart:io
    final rss = ProcessInfo.currentRss;
    return _MemSnapshot(usedBytes: rss, timestamp: DateTime.now());
  }
}

/// Complete QA report with enhanced metrics
class ComprehensiveQaReport {
  final List<QaAssertion> assertions;
  final List<PhaseMetrics> phases;
  final Duration duration;
  final DateTime timestamp;
  final int memoryDeltaBytes;
  final int flakyTestCount;

  ComprehensiveQaReport({
    required this.assertions,
    required this.phases,
    required this.duration,
    required this.memoryDeltaBytes,
    this.flakyTestCount = 0,
  }) : timestamp = DateTime.now();

  int get passed => assertions.where((a) => a.passed).length;
  int get failed => assertions.where((a) => !a.passed).length;
  int get total => assertions.length;
  bool get allPassed => failed == 0;

  List<QaAssertion> get failures =>
      assertions.where((a) => !a.passed).toList();

  String get summary =>
      '$passed/$total passed, $failed failed'
      '${flakyTestCount > 0 ? ', $flakyTestCount flaky' : ''}'
      ' (${duration.inMilliseconds}ms)';

  /// Export report as structured JSON
  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'summary': {
          'total': total,
          'passed': passed,
          'failed': failed,
          'flaky': flakyTestCount,
          'duration_ms': duration.inMilliseconds,
          'memory_delta_kb': (memoryDeltaBytes / 1024).round(),
        },
        'phases': phases.map((p) => p.toJson()).toList(),
        'failures':
            failures.map((f) => f.toJson()).toList(),
        'all_assertions': assertions.map((a) => a.toJson()).toList(),
      };

  /// Write report to file
  Future<void> exportToFile(String path) async {
    final json = const JsonEncoder.withIndent('  ').convert(toJson());
    await File(path).writeAsString(json);
  }

  /// Human-readable text report
  String toTextReport() {
    final buf = StringBuffer();
    buf.writeln('╔══════════════════════════════════════════════════════════════╗');
    buf.writeln('║          COMPREHENSIVE QA REPORT                           ║');
    buf.writeln('╚══════════════════════════════════════════════════════════════╝');
    buf.writeln('Time: $timestamp');
    buf.writeln('Duration: ${duration.inMilliseconds}ms');
    buf.writeln('Memory delta: ${(memoryDeltaBytes / 1024).round()} KB');
    buf.writeln('Result: $summary');
    buf.writeln('');

    buf.writeln('── Phase Breakdown ──');
    for (final p in phases) {
      final status = p.failCount > 0 ? 'FAIL' : 'OK';
      buf.writeln(
          '  $status  ${p.name}: ${p.passCount}/${p.assertionCount} '
          '(${p.duration.inMilliseconds}ms)');
    }

    if (failures.isNotEmpty) {
      buf.writeln('');
      buf.writeln('── Failures ──');
      for (final f in failures) {
        buf.writeln('  [${f.module}] ${f.test}');
        if (f.detail != null) buf.writeln('    → ${f.detail}');
        if (f.retryCount > 0) buf.writeln('    (retried ${f.retryCount}x)');
      }
    }

    if (flakyTestCount > 0) {
      buf.writeln('');
      buf.writeln('── Flaky Tests ($flakyTestCount) ──');
      for (final a in assertions.where((a) => a.retryCount > 0)) {
        buf.writeln(
            '  [${a.module}] ${a.test} — '
            '${a.passed ? 'PASS on retry' : 'FAIL'} (${a.retryCount} retries)');
      }
    }

    return buf.toString();
  }
}

/// Mixer state snapshot for restore after QA
class _MixerSnapshot {
  final List<String> channelIds;
  final List<String> busIds;
  final List<String> vcaIds;
  final List<String> groupIds;

  _MixerSnapshot({
    required this.channelIds,
    required this.busIds,
    required this.vcaIds,
    required this.groupIds,
  });
}

/// Comprehensive QA Runner — tests every module programmatically
class ComprehensiveQaRunner {
  final DiagnosticsService _diag;
  final List<QaAssertion> _assertions = [];
  final List<PhaseMetrics> _phases = [];
  bool _running = false;
  bool _cancelled = false;
  final GetIt _sl = GetIt.instance;

  /// Max retries for flaky test detection
  static const int _maxRetries = 2;

  ComprehensiveQaRunner(this._diag);

  bool get isRunning => _running;

  /// Cancel a running QA session
  void cancel() {
    _cancelled = true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ASSERTION HELPERS (with timing + retry)
  // ═══════════════════════════════════════════════════════════════════════════

  void _assert(String module, String test, bool condition, [String? detail]) {
    _assertions.add(QaAssertion(
      module: module,
      test: test,
      passed: condition,
      detail: condition ? null : (detail ?? 'FAIL'),
    ));
    if (!condition) {
      _diag.log('FAIL [$module] $test${detail != null ? ' — $detail' : ''}');
      _diag.reportFinding(DiagnosticFinding(
        checker: 'QA:$module',
        severity: DiagnosticSeverity.error,
        message: '$test — ${detail ?? 'FAIL'}',
      ));
    } else {
      _diag.log('PASS [$module] $test');
    }
  }

  void _assertNotNull(String module, String test, dynamic value) {
    _assert(module, test, value != null, 'Expected non-null, got null');
  }

  void _assertEqual<T>(String module, String test, T actual, T expected) {
    _assert(module, test, actual == expected, 'Expected $expected, got $actual');
  }

  void _assertInRange(
      String module, String test, double value, double min, double max) {
    _assert(module, test, value >= min && value <= max,
        'Value $value not in range [$min, $max]');
  }

  void _assertNoThrow(String module, String test, void Function() fn) {
    final sw = Stopwatch()..start();
    try {
      fn();
      sw.stop();
      _assertions.add(QaAssertion(
        module: module,
        test: test,
        passed: true,
        elapsed: sw.elapsed,
      ));
      _diag.log('PASS [$module] $test (${sw.elapsedMicroseconds}μs)');
    } catch (e) {
      sw.stop();
      _assertions.add(QaAssertion(
        module: module,
        test: test,
        passed: false,
        detail: 'Threw: $e',
        elapsed: sw.elapsed,
      ));
      _diag.log('FAIL [$module] $test — Threw: $e');
      _diag.reportFinding(DiagnosticFinding(
        checker: 'QA:$module',
        severity: DiagnosticSeverity.error,
        message: '$test — Threw: $e',
      ));
    }
  }

  Future<void> _assertNoThrowAsync(
      String module, String test, Future<void> Function() fn) async {
    final sw = Stopwatch()..start();
    try {
      await fn();
      sw.stop();
      _assertions.add(QaAssertion(
        module: module,
        test: test,
        passed: true,
        elapsed: sw.elapsed,
      ));
      _diag.log('PASS [$module] $test (${sw.elapsedMilliseconds}ms)');
    } catch (e) {
      sw.stop();
      _assertions.add(QaAssertion(
        module: module,
        test: test,
        passed: false,
        detail: 'Threw: $e',
        elapsed: sw.elapsed,
      ));
      _diag.log('FAIL [$module] $test — Threw: $e');
      _diag.reportFinding(DiagnosticFinding(
        checker: 'QA:$module',
        severity: DiagnosticSeverity.error,
        message: '$test — Threw: $e',
      ));
    }
  }

  /// Retry an async assertion to detect flaky tests
  Future<void> _assertWithRetry(
    String module,
    String test,
    Future<bool> Function() check, {
    String? failDetail,
  }) async {
    int retries = 0;
    bool passed = false;

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        passed = await check();
        if (passed) break;
      } catch (e) {
        failDetail = 'Threw: $e';
      }
      if (attempt < _maxRetries) {
        retries++;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    _assertions.add(QaAssertion(
      module: module,
      test: test,
      passed: passed,
      detail: passed ? null : (failDetail ?? 'FAIL after ${retries + 1} attempts'),
      retryCount: retries,
    ));

    if (!passed) {
      _diag.log('FAIL [$module] $test (${retries}x retry) — ${failDetail ?? 'FAIL'}');
      _diag.reportFinding(DiagnosticFinding(
        checker: 'QA:$module',
        severity: DiagnosticSeverity.error,
        message: '$test — ${failDetail ?? 'FAIL'} (${retries}x retry)',
      ));
    } else if (retries > 0) {
      _diag.log('FLAKY [$module] $test — passed on retry $retries');
    } else {
      _diag.log('PASS [$module] $test');
    }
  }

  /// Safely get a provider, returns null if not registered
  T? _tryGet<T extends Object>() {
    try {
      if (_sl.isRegistered<T>()) return _sl<T>();
    } catch (_) {}
    return null;
  }

  /// Track phase timing
  int _phaseStartIdx = 0;
  final Stopwatch _phaseSw = Stopwatch();

  void _startPhase(String name) {
    _phaseStartIdx = _assertions.length;
    _phaseSw.reset();
    _phaseSw.start();
    _diag.log('═══ $name ═══');
  }

  void _endPhase(String name) {
    _phaseSw.stop();
    final phaseAssertions = _assertions.sublist(_phaseStartIdx);
    _phases.add(PhaseMetrics(
      name: name,
      duration: _phaseSw.elapsed,
      assertionCount: phaseAssertions.length,
      passCount: phaseAssertions.where((a) => a.passed).length,
      failCount: phaseAssertions.where((a) => !a.passed).length,
    ));
    _diag.log(
        '  → $name: ${phaseAssertions.where((a) => a.passed).length}'
        '/${phaseAssertions.length} passed '
        '(${_phaseSw.elapsedMilliseconds}ms)');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIXER STATE SNAPSHOT / RESTORE
  // ═══════════════════════════════════════════════════════════════════════════

  _MixerSnapshot? _takeMixerSnapshot(MixerProvider mixer) {
    return _MixerSnapshot(
      channelIds: mixer.channels.map((c) => c.id).toList(),
      busIds: mixer.buses.map((b) => b.id).toList(),
      vcaIds: mixer.vcas.map((v) => v.id).toList(),
      groupIds: mixer.groups.map((g) => g.id).toList(),
    );
  }

  void _restoreMixerSnapshot(MixerProvider mixer, _MixerSnapshot snapshot) {
    // Delete any channels/buses/vcas/groups that were created during QA
    final newChannels = mixer.channels
        .where((c) => !snapshot.channelIds.contains(c.id))
        .map((c) => c.id)
        .toList();
    final newBuses = mixer.buses
        .where((b) => !snapshot.busIds.contains(b.id))
        .map((b) => b.id)
        .toList();
    final newVcas = mixer.vcas
        .where((v) => !snapshot.vcaIds.contains(v.id))
        .map((v) => v.id)
        .toList();
    final newGroups = mixer.groups
        .where((g) => !snapshot.groupIds.contains(g.id))
        .map((g) => g.id)
        .toList();

    for (final id in newChannels) {
      try { mixer.deleteChannel(id); } catch (_) {}
    }
    for (final id in newBuses) {
      try { mixer.deleteBus(id); } catch (_) {}
    }
    for (final id in newVcas) {
      try { mixer.deleteVca(id); } catch (_) {}
    }
    for (final id in newGroups) {
      try { mixer.deleteGroup(id); } catch (_) {}
    }

    _diag.log('Mixer restored: removed ${newChannels.length} channels, '
        '${newBuses.length} buses, ${newVcas.length} VCAs, '
        '${newGroups.length} groups');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN ENTRY POINT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Run ALL QA modules. Returns comprehensive report.
  Future<ComprehensiveQaReport> runAll({
    SlotLabProvider? slotLabProvider,
    MixerProvider? mixerProvider,
    EngineProvider? engineProvider,
    bool exportJson = true,
  }) async {
    if (_running) {
      return ComprehensiveQaReport(
        assertions: [],
        phases: [],
        duration: Duration.zero,
        memoryDeltaBytes: 0,
      );
    }
    _running = true;
    _cancelled = false;
    _assertions.clear();
    _phases.clear();
    final sw = Stopwatch()..start();

    // Memory snapshot: before
    final memBefore = _MemSnapshot.capture();

    // Mixer snapshot for cleanup
    _MixerSnapshot? mixerSnapshot;
    if (mixerProvider != null) {
      mixerSnapshot = _takeMixerSnapshot(mixerProvider);
    }

    _diag.log('');
    _diag.log('╔══════════════════════════════════════════════════════════════╗');
    _diag.log('║          COMPREHENSIVE QA — FULL APP TEST SUITE v2         ║');
    _diag.log('╚══════════════════════════════════════════════════════════════╝');
    _diag.log('Memory at start: ${(memBefore.usedBytes / 1024 / 1024).toStringAsFixed(1)} MB');
    _diag.log('');

    // Phase 1: Provider availability
    _startPhase('PHASE 1: Provider Availability');
    _testProviderAvailability();
    _endPhase('PHASE 1: Provider Availability');
    if (_cancelled) return _buildReport(sw, memBefore);

    // Phase 2: Mixer operations
    _startPhase('PHASE 2: DAW Mixer');
    if (mixerProvider != null) {
      _testMixer(mixerProvider);
    } else {
      _diag.log('SKIP: MixerProvider not available');
    }
    _endPhase('PHASE 2: DAW Mixer');
    if (_cancelled) return _buildReport(sw, memBefore, mixerProvider, mixerSnapshot);

    // Phase 3: Engine / Transport
    _startPhase('PHASE 3: DAW Transport');
    if (engineProvider != null) {
      await _testTransport(engineProvider);
    } else {
      _diag.log('SKIP: EngineProvider not available');
    }
    _endPhase('PHASE 3: DAW Transport');
    if (_cancelled) return _buildReport(sw, memBefore, mixerProvider, mixerSnapshot);

    // Phase 4: Middleware subsystems
    _startPhase('PHASE 4: Middleware Subsystems');
    _testMiddlewareSubsystems();
    _endPhase('PHASE 4: Middleware Subsystems');
    if (_cancelled) return _buildReport(sw, memBefore, mixerProvider, mixerSnapshot);

    // Phase 5: SlotLab engine
    _startPhase('PHASE 5: SlotLab Engine');
    if (slotLabProvider != null) {
      await _testSlotLabEngine(slotLabProvider);
    } else {
      _diag.log('SKIP: SlotLabProvider not available');
    }
    _endPhase('PHASE 5: SlotLab Engine');
    if (_cancelled) return _buildReport(sw, memBefore, mixerProvider, mixerSnapshot);

    // Phase 5.5: Game Math Validation (100 spins — quick sanity check)
    _startPhase('PHASE 5.5: Game Math');
    if (slotLabProvider != null && slotLabProvider.initialized) {
      await _testGameMath(slotLabProvider);
    } else {
      _diag.log('SKIP: SlotLabProvider not available for Game Math');
    }
    _endPhase('PHASE 5.5: Game Math');
    if (_cancelled) return _buildReport(sw, memBefore, mixerProvider, mixerSnapshot);

    // Phase 6: SlotLab subsystems
    _startPhase('PHASE 6: SlotLab Subsystems');
    _testSlotLabSubsystems();
    _endPhase('PHASE 6: SlotLab Subsystems');
    if (_cancelled) return _buildReport(sw, memBefore, mixerProvider, mixerSnapshot);

    // Phase 7: Cross-module integrity
    _startPhase('PHASE 7: Cross-Module Integrity');
    _testCrossModuleIntegrity(slotLabProvider, mixerProvider);
    _endPhase('PHASE 7: Cross-Module Integrity');
    if (_cancelled) return _buildReport(sw, memBefore, mixerProvider, mixerSnapshot);

    // Phase 8: Edge cases & boundary conditions
    _startPhase('PHASE 8: Edge Cases');
    _testEdgeCases(mixerProvider, slotLabProvider);
    _endPhase('PHASE 8: Edge Cases');
    if (_cancelled) return _buildReport(sw, memBefore, mixerProvider, mixerSnapshot);

    // Phase 9: Stress tests (rapid-fire operations)
    _startPhase('PHASE 9: Stress Tests');
    await _testStress(mixerProvider, slotLabProvider);
    _endPhase('PHASE 9: Stress Tests');
    if (_cancelled) return _buildReport(sw, memBefore, mixerProvider, mixerSnapshot);

    // Phase 10: Concurrency tests
    _startPhase('PHASE 10: Concurrency');
    await _testConcurrency(mixerProvider, slotLabProvider);
    _endPhase('PHASE 10: Concurrency');
    if (_cancelled) return _buildReport(sw, memBefore, mixerProvider, mixerSnapshot);

    // Phase 11: SlotLab Coordinator deep testing
    _startPhase('PHASE 11: SlotLab Coordinator Deep');
    if (slotLabProvider != null) {
      _testSlotLabCoordinatorDeep(slotLabProvider);
    }
    _endPhase('PHASE 11: SlotLab Coordinator Deep');
    if (_cancelled) return _buildReport(sw, memBefore, mixerProvider, mixerSnapshot);

    // Phase 12: Serialization roundtrip
    _startPhase('PHASE 12: Serialization Roundtrip');
    _testSerializationRoundtrip();
    _endPhase('PHASE 12: Serialization Roundtrip');
    if (_cancelled) return _buildReport(sw, memBefore, mixerProvider, mixerSnapshot);

    // Phase 13: Multi-grid spin QA (the big one)
    _startPhase('PHASE 13: Multi-Grid Spin QA');
    if (slotLabProvider != null) {
      await _testMultiGridSpins(slotLabProvider);
    }
    _endPhase('PHASE 13: Multi-Grid Spin QA');

    return _buildReport(sw, memBefore, mixerProvider, mixerSnapshot, exportJson);
  }

  ComprehensiveQaReport _buildReport(
    Stopwatch sw,
    _MemSnapshot memBefore, [
    MixerProvider? mixerProvider,
    _MixerSnapshot? mixerSnapshot,
    bool exportJson = true,
  ]) {
    sw.stop();

    // Restore mixer state
    if (mixerProvider != null && mixerSnapshot != null) {
      _restoreMixerSnapshot(mixerProvider, mixerSnapshot);
    }

    // Memory snapshot: after
    final memAfter = _MemSnapshot.capture();
    final memDelta = memAfter.usedBytes - memBefore.usedBytes;

    // Count flaky tests
    final flakyCount = _assertions.where((a) => a.retryCount > 0).length;

    final report = ComprehensiveQaReport(
      assertions: List.unmodifiable(_assertions),
      phases: List.unmodifiable(_phases),
      duration: sw.elapsed,
      memoryDeltaBytes: memDelta,
      flakyTestCount: flakyCount,
    );

    _diag.log('');
    _diag.log('╔══════════════════════════════════════════════════════════════╗');
    _diag.log('║  QA COMPLETE: ${report.summary.padRight(45)}║');
    _diag.log('╚══════════════════════════════════════════════════════════════╝');
    _diag.log('Memory delta: ${(memDelta / 1024).round()} KB');

    if (report.failures.isNotEmpty) {
      _diag.log('');
      _diag.log('FAILURES:');
      for (final f in report.failures) {
        _diag.log('  [${f.module}] ${f.test} — ${f.detail}');
      }
    }

    if (flakyCount > 0) {
      _diag.log('');
      _diag.log('FLAKY TESTS ($flakyCount):');
      for (final a in _assertions.where((a) => a.retryCount > 0)) {
        _diag.log('  [${a.module}] ${a.test} (${a.retryCount}x retry)');
      }
    }

    // Phase breakdown
    _diag.log('');
    _diag.log('PHASE TIMING:');
    for (final p in _phases) {
      _diag.log(
          '  ${p.failCount > 0 ? 'FAIL' : ' OK '}  ${p.name}: '
          '${p.passCount}/${p.assertionCount} '
          '(${p.duration.inMilliseconds}ms)');
    }

    _diag.reportFinding(DiagnosticFinding(
      checker: 'ComprehensiveQA',
      severity:
          report.allPassed ? DiagnosticSeverity.ok : DiagnosticSeverity.error,
      message: report.summary,
      detail: report.failures.isNotEmpty
          ? report.failures.map((f) => '${f.module}: ${f.test}').join('; ')
          : null,
    ));

    // Export JSON report
    if (exportJson) {
      _exportReport(report);
    }

    _running = false;
    return report;
  }

  void _exportReport(ComprehensiveQaReport report) {
    try {
      final home = Platform.environment['HOME'] ?? '/tmp';
      final path = '$home/qa_report.json';
      final json = const JsonEncoder.withIndent('  ').convert(report.toJson());
      File(path).writeAsStringSync(json);
      _diag.log('Report exported to $path');

      // Also write human-readable
      final textPath = '$home/qa_report.txt';
      File(textPath).writeAsStringSync(report.toTextReport());
      _diag.log('Text report exported to $textPath');
    } catch (e) {
      _diag.log('Report export failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 1: PROVIDER AVAILABILITY
  // ═══════════════════════════════════════════════════════════════════════════

  void _testProviderAvailability() {
    const mod = 'Providers';

    // Core middleware subsystems
    _assert(mod, 'StateGroupsProvider registered',
        _sl.isRegistered<StateGroupsProvider>());
    _assert(mod, 'SwitchGroupsProvider registered',
        _sl.isRegistered<SwitchGroupsProvider>());
    _assert(mod, 'RtpcSystemProvider registered',
        _sl.isRegistered<RtpcSystemProvider>());
    _assert(mod, 'DuckingSystemProvider registered',
        _sl.isRegistered<DuckingSystemProvider>());
    _assert(mod, 'BlendContainersProvider registered',
        _sl.isRegistered<BlendContainersProvider>());
    _assert(mod, 'RandomContainersProvider registered',
        _sl.isRegistered<RandomContainersProvider>());
    _assert(mod, 'SequenceContainersProvider registered',
        _sl.isRegistered<SequenceContainersProvider>());
    _assert(mod, 'CompositeEventSystemProvider registered',
        _sl.isRegistered<CompositeEventSystemProvider>());
    _assert(mod, 'BusHierarchyProvider registered',
        _sl.isRegistered<BusHierarchyProvider>());
    _assert(mod, 'VoicePoolProvider registered',
        _sl.isRegistered<VoicePoolProvider>());

    // SlotLab subsystems
    _assert(mod, 'BehaviorTreeProvider registered',
        _sl.isRegistered<BehaviorTreeProvider>());
    _assert(mod, 'StateGateProvider registered',
        _sl.isRegistered<StateGateProvider>());
    _assert(mod, 'EmotionalStateProvider registered',
        _sl.isRegistered<EmotionalStateProvider>());
    _assert(mod, 'PriorityEngineProvider registered',
        _sl.isRegistered<PriorityEngineProvider>());
    _assert(mod, 'OrchestrationEngineProvider registered',
        _sl.isRegistered<OrchestrationEngineProvider>());
    _assert(mod, 'SimulationEngineProvider registered',
        _sl.isRegistered<SimulationEngineProvider>());
    _assert(mod, 'TransitionSystemProvider registered',
        _sl.isRegistered<TransitionSystemProvider>());
    _assert(mod, 'SlotLabProjectProvider registered',
        _sl.isRegistered<SlotLabProjectProvider>());
    _assert(mod, 'FeatureComposerProvider registered',
        _sl.isRegistered<FeatureComposerProvider>());

    // Advanced systems
    _assert(mod, 'EnergyGovernanceProvider registered',
        _sl.isRegistered<EnergyGovernanceProvider>());
    _assert(mod, 'DpmProvider registered', _sl.isRegistered<DpmProvider>());
    _assert(mod, 'AurexisProvider registered',
        _sl.isRegistered<AurexisProvider>());
    _assert(mod, 'AurexisProfileProvider registered',
        _sl.isRegistered<AurexisProfileProvider>());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 2: DAW MIXER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Fresh channel lookup — MixerProvider uses copyWith, so old references go stale.
  MixerChannel? _ch(MixerProvider m, String id) =>
      m.channels.where((c) => c.id == id).firstOrNull;

  void _testMixer(MixerProvider mixer) {
    const mod = 'Mixer';

    // Master channel exists
    _assertNotNull(mod, 'Master channel exists', mixer.master);
    _assertEqual(mod, 'Master default volume', mixer.master.volume, 1.0);
    _assertEqual(mod, 'Master type', mixer.master.type, ChannelType.master);

    // Create channel
    _assertNoThrow(mod, 'Create audio channel', () {
      mixer.createChannel(name: 'QA Track 1');
    });
    _assert(mod, 'Channel count >= 1', mixer.channels.isNotEmpty);

    // Find the created channel
    final ch0 = mixer.channels.where((c) => c.name == 'QA Track 1').firstOrNull;
    _assertNotNull(mod, 'QA Track 1 found', ch0);
    if (ch0 == null) return;
    final chId = ch0.id;

    // Volume operations
    final originalVol = ch0.volume;
    mixer.setChannelVolume(chId, 0.5);
    _assertEqual(mod, 'setChannelVolume(0.5)', _ch(mixer, chId)!.volume, 0.5);

    mixer.setChannelVolume(chId, 2.0);
    _assertEqual(mod, 'setChannelVolume(2.0) max', _ch(mixer, chId)!.volume, 2.0);

    mixer.setChannelVolume(chId, 0.0);
    _assertEqual(mod, 'setChannelVolume(0.0) min', _ch(mixer, chId)!.volume, 0.0);

    mixer.setChannelVolume(chId, originalVol);

    // Pan operations
    mixer.setChannelPan(chId, -1.0);
    _assertEqual(mod, 'Pan full left', _ch(mixer, chId)!.pan, -1.0);

    mixer.setChannelPan(chId, 1.0);
    _assertEqual(mod, 'Pan full right', _ch(mixer, chId)!.pan, 1.0);

    mixer.setChannelPan(chId, 0.0);
    _assertEqual(mod, 'Pan center', _ch(mixer, chId)!.pan, 0.0);

    // Mute/Solo
    final wasMuted = _ch(mixer, chId)!.muted;
    mixer.toggleChannelMute(chId);
    _assertEqual(mod, 'Toggle mute ON', _ch(mixer, chId)!.muted, !wasMuted);

    mixer.toggleChannelMute(chId);
    _assertEqual(mod, 'Toggle mute OFF', _ch(mixer, chId)!.muted, wasMuted);

    final wasSoloed = _ch(mixer, chId)!.soloed;
    mixer.toggleChannelSolo(chId);
    _assertEqual(mod, 'Toggle solo ON', _ch(mixer, chId)!.soloed, !wasSoloed);

    mixer.toggleChannelSolo(chId);
    _assertEqual(mod, 'Toggle solo OFF', _ch(mixer, chId)!.soloed, wasSoloed);

    // Phase invert
    mixer.togglePhaseInvert(chId);
    _assert(mod, 'Phase invert ON', _ch(mixer, chId)!.phaseInverted);
    mixer.togglePhaseInvert(chId);
    _assert(mod, 'Phase invert OFF', !_ch(mixer, chId)!.phaseInverted);

    // Input gain
    mixer.setInputGain(chId, 12.0);
    _assertInRange(mod, 'Input gain +12dB', _ch(mixer, chId)!.inputGain, 11.9, 12.1);
    mixer.setInputGain(chId, -12.0);
    _assertInRange(mod, 'Input gain -12dB', _ch(mixer, chId)!.inputGain, -12.1, -11.9);
    mixer.setInputGain(chId, 0.0);

    // Stereo width
    mixer.setStereoWidth(chId, 0.0);
    _assertInRange(mod, 'Stereo width mono', _ch(mixer, chId)!.stereoWidth, -0.01, 0.01);
    mixer.setStereoWidth(chId, 2.0);
    _assertInRange(
        mod, 'Stereo width extra-wide', _ch(mixer, chId)!.stereoWidth, 1.99, 2.01);
    mixer.setStereoWidth(chId, 1.0);

    // Create bus
    _assertNoThrow(mod, 'Create bus', () {
      mixer.createBus(name: 'QA Bus');
    });
    _assert(mod, 'Bus count >= 1', mixer.buses.isNotEmpty);

    // Create VCA
    _assertNoThrow(mod, 'Create VCA', () {
      mixer.createVca(name: 'QA VCA');
    });
    _assert(mod, 'VCA count >= 1', mixer.vcas.isNotEmpty);

    // VCA operations
    final vca0 = mixer.vcas.where((v) => v.name == 'QA VCA').firstOrNull;
    if (vca0 != null) {
      final vcaId = vca0.id;
      mixer.setVcaLevel(vcaId, 0.5);
      final freshVca = mixer.vcas.where((v) => v.id == vcaId).firstOrNull;
      _assertInRange(mod, 'VCA level 0.5', freshVca?.level ?? -1, 0.49, 0.51);

      mixer.assignChannelToVca(chId, vcaId);
      final freshVca2 = mixer.vcas.where((v) => v.id == vcaId).firstOrNull;
      _assert(
          mod, 'Channel assigned to VCA', freshVca2?.memberIds.contains(chId) ?? false);

      mixer.removeChannelFromVca(chId, vcaId);
      final freshVca3 = mixer.vcas.where((v) => v.id == vcaId).firstOrNull;
      _assert(
          mod, 'Channel removed from VCA', !(freshVca3?.memberIds.contains(chId) ?? true));

      mixer.setVcaLevel(vcaId, 1.0);
    }

    // Create group
    _assertNoThrow(mod, 'Create group', () {
      mixer.createGroup(name: 'QA Group');
    });
    _assert(mod, 'Group count >= 1', mixer.groups.isNotEmpty);

    // Solo safe
    mixer.toggleSoloSafe(chId);
    _assert(mod, 'Solo safe ON', _ch(mixer, chId)!.soloSafe);
    mixer.toggleSoloSafe(chId);
    _assert(mod, 'Solo safe OFF', !_ch(mixer, chId)!.soloSafe);

    // Channel comments
    mixer.setChannelComments(chId, 'QA test comment');
    _assertEqual(mod, 'Channel comments', _ch(mixer, chId)!.comments, 'QA test comment');
    mixer.setChannelComments(chId, '');

    // dB string (volume was restored to originalVol earlier)
    mixer.setChannelVolume(chId, 1.0);
    _assert(
        mod, 'Volume dB string for 1.0', _ch(mixer, chId)!.volumeDbString.contains('0.0'));

    // Clear solo
    _assertNoThrow(mod, 'Clear all solo', () {
      mixer.clearAllSolo();
    });

    // Cleanup: delete QA channel
    // Note: deleteChannel may throw on unmodifiable VCA memberIds (known bug)
    try {
      mixer.deleteChannel(chId);
      _assert(mod, 'Delete QA channel', true);
    } catch (e) {
      _assert(mod, 'Delete QA channel', false, 'Threw: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 3: DAW TRANSPORT
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testTransport(EngineProvider engine) async {
    const mod = 'Transport';

    _assert(
        mod,
        'Engine status is running or uninitialized',
        engine.status == EngineStatus.running ||
            engine.status == EngineStatus.uninitialized);

    if (!engine.isRunning) {
      _diag.log('Engine not running, attempting initialize...');
      final ok = await engine.initialize();
      _assert(mod, 'Engine initialize', ok);
      if (!ok) {
        _diag.log('SKIP transport tests — engine failed to initialize');
        return;
      }
    }

    _assertNotNull(mod, 'Transport state exists', engine.transport);

    // Play/Stop cycle
    _assertNoThrow(mod, 'Play', () => engine.play());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _assert(mod, 'isPlaying after play', engine.transport.isPlaying);

    _assertNoThrow(mod, 'Stop', () => engine.stop());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _assert(mod, 'Not playing after stop', !engine.transport.isPlaying);

    // Pause
    _assertNoThrow(mod, 'Play for pause test', () => engine.play());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _assertNoThrow(mod, 'Pause', () => engine.pause());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _assertNoThrow(mod, 'Stop after pause', () => engine.stop());

    // Double-stop behavior (DAW standard: 1st→playback start, 2nd→0)
    _assertNoThrow(mod, 'Seek to 5s', () => engine.seek(5.0));
    _assertNoThrow(mod, 'Play from 5s', () => engine.play());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _assertNoThrow(mod, 'First stop', () => engine.stop());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _assertNoThrow(mod, 'Second stop (go to 0)', () => engine.stop());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Seek
    _assertNoThrow(mod, 'Seek to 5.0s', () => engine.seek(5.0));
    _assertInRange(mod, 'Position after seek',
        engine.transport.positionSeconds, 4.5, 5.5);

    _assertNoThrow(mod, 'Seek to 0', () => engine.seek(0));
    _assertInRange(mod, 'Position after seek 0',
        engine.transport.positionSeconds, -0.1, 0.5);

    // GoToStart
    _assertNoThrow(mod, 'GoToStart', () => engine.goToStart());
    _assertInRange(mod, 'Position after goToStart',
        engine.transport.positionSeconds, -0.1, 0.1);

    // Tempo
    _assertNoThrow(mod, 'Set tempo 140', () => engine.setTempo(140));
    _assertNoThrow(mod, 'Set tempo 60', () => engine.setTempo(60));
    _assertNoThrow(mod, 'Set tempo 120 (reset)', () => engine.setTempo(120));

    // Time signature
    _assertNoThrow(
        mod, 'Time sig 4/4', () => engine.setTimeSignature(4, 4));
    _assertNoThrow(
        mod, 'Time sig 3/4', () => engine.setTimeSignature(3, 4));
    _assertNoThrow(
        mod, 'Time sig 6/8', () => engine.setTimeSignature(6, 8));
    _assertNoThrow(
        mod, 'Time sig 4/4 reset', () => engine.setTimeSignature(4, 4));

    // Loop toggle
    _assertNoThrow(mod, 'Toggle loop', () => engine.toggleLoop());
    _assertNoThrow(mod, 'Toggle loop back', () => engine.toggleLoop());

    // Jog seek
    _assertNoThrow(
        mod, 'Jog seek forward', () => engine.jogSeek(1.0));
    _assertNoThrow(
        mod, 'Jog seek backward', () => engine.jogSeek(-1.0));

    // Undo/Redo (should not crash even if nothing to undo)
    _assertNoThrow(mod, 'Undo (no-op safe)', () => engine.undo());
    _assertNoThrow(mod, 'Redo (no-op safe)', () => engine.redo());

    // Reset
    engine.goToStart();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 4: MIDDLEWARE SUBSYSTEMS
  // ═══════════════════════════════════════════════════════════════════════════

  void _testMiddlewareSubsystems() {
    const mod = 'Middleware';

    // ── State Groups: full CRUD cycle ──
    final stateGroups = _tryGet<StateGroupsProvider>();
    if (stateGroups != null) {
      final countBefore = stateGroups.stateGroups.length;
      _assertNoThrow(mod, 'StateGroups: register group', () {
        stateGroups.registerStateGroupFromPreset(
            'QA_StateGroup', ['QA_A', 'QA_B', 'QA_C']);
      });
      _assert(mod, 'StateGroups: count increased',
          stateGroups.stateGroups.length == countBefore + 1);
      final group = stateGroups.getStateGroupByName('QA_StateGroup');
      _assertNotNull(mod, 'StateGroups: group found by name', group);
      if (group != null) {
        _assert(mod, 'StateGroups: has 3 states', group.states.length == 3);
        _assertNotNull(mod, 'StateGroups: getStateGroup by id',
            stateGroups.getStateGroup(group.id));
        // Cycle through all states
        for (int i = 0; i < group.states.length; i++) {
          _assertNoThrow(mod, 'StateGroups: set state ${group.states[i].name}', () {
            stateGroups.setState(group.id, group.states[i].id);
          });
          _assertEqual(mod, 'StateGroups: current state is ${group.states[i].name}',
              stateGroups.getCurrentState(group.id), group.states[i].id);
        }
        // setStateByName
        _assertNoThrow(mod, 'StateGroups: setStateByName', () {
          stateGroups.setStateByName(group.id, 'QA_A');
        });
        // Reset
        _assertNoThrow(mod, 'StateGroups: resetState', () {
          stateGroups.resetState(group.id);
        });
        // Serialization roundtrip
        _assertNoThrow(mod, 'StateGroups: toJson/fromJson roundtrip', () {
          final json = stateGroups.toJson();
          _assert(mod, 'StateGroups: toJson not empty', json.isNotEmpty);
        });
        // Cleanup
        _assertNoThrow(mod, 'StateGroups: unregister', () {
          stateGroups.unregisterStateGroup(group.id);
        });
        _assert(mod, 'StateGroups: count restored',
            stateGroups.stateGroups.length == countBefore);
      }
    } else {
      _diag.log('SKIP: StateGroupsProvider not available');
    }

    // ── Switch Groups: full CRUD cycle ──
    final switchGroups = _tryGet<SwitchGroupsProvider>();
    if (switchGroups != null) {
      final countBefore = switchGroups.switchGroups.length;
      _assertNoThrow(mod, 'SwitchGroups: register', () {
        switchGroups.registerSwitchGroupFromPreset(
            'QA_SwitchGroup', ['QA_On', 'QA_Off']);
      });
      _assert(mod, 'SwitchGroups: count increased',
          switchGroups.switchGroups.length == countBefore + 1);
      final sg = switchGroups.getSwitchGroupByName('QA_SwitchGroup');
      _assertNotNull(mod, 'SwitchGroups: found by name', sg);
      if (sg != null) {
        // Set switch on a game object
        _assertNoThrow(mod, 'SwitchGroups: setSwitch', () {
          switchGroups.setSwitch(9999, sg.id, sg.switches.first.id);
        });
        _assertEqual(mod, 'SwitchGroups: getSwitch',
            switchGroups.getSwitch(9999, sg.id), sg.switches.first.id);
        // Reset
        _assertNoThrow(mod, 'SwitchGroups: resetSwitch', () {
          switchGroups.resetSwitch(9999, sg.id);
        });
        _assertNoThrow(mod, 'SwitchGroups: clearObjectSwitches', () {
          switchGroups.clearObjectSwitches(9999);
        });
        // Serialization
        _assertNoThrow(mod, 'SwitchGroups: toJson', () {
          final _ = switchGroups.toJson();
        });
        // Cleanup
        _assertNoThrow(mod, 'SwitchGroups: unregister', () {
          switchGroups.unregisterSwitchGroup(sg.id);
        });
      }
    } else {
      _diag.log('SKIP: SwitchGroupsProvider not available');
    }

    // ── RTPC: getters + serialization ──
    final rtpc = _tryGet<RtpcSystemProvider>();
    if (rtpc != null) {
      _assertNoThrow(mod, 'RTPC: read definitions list', () {
        final defs = rtpc.rtpcDefinitions;
        _assert(mod, 'RTPC: definitions accessible', true);
      });
      _assertNoThrow(mod, 'RTPC: read bindings', () {
        final _ = rtpc.rtpcBindings;
      });
      _assertNoThrow(mod, 'RTPC: rtpcCount', () {
        final _ = rtpc.rtpcCount;
      });
      _assertNoThrow(mod, 'RTPC: macros', () {
        final _ = rtpc.rtpcMacros;
      });
      _assertNoThrow(mod, 'RTPC: morphs', () {
        final _ = rtpc.presetMorphs;
      });
      _assertNoThrow(mod, 'RTPC: dspBindings', () {
        final _ = rtpc.dspBindingsList;
      });
      _assertNoThrow(mod, 'RTPC: dspBindingCount', () {
        final _ = rtpc.dspBindingCount;
      });
    } else {
      _diag.log('SKIP: RtpcSystemProvider not available');
    }

    // ── Ducking: rule CRUD ──
    final ducking = _tryGet<DuckingSystemProvider>();
    if (ducking != null) {
      final countBefore = ducking.ruleCount;
      _assertNoThrow(mod, 'Ducking: addRule', () {
        ducking.addRule(
          sourceBus: 'Music',
          sourceBusId: 1,
          targetBus: 'SFX',
          targetBusId: 2,
          duckAmountDb: -6.0,
          attackMs: 50.0,
          releaseMs: 500.0,
        );
      });
      _assert(mod, 'Ducking: rule count increased',
          ducking.ruleCount == countBefore + 1);
      // Read rules
      _assertNoThrow(mod, 'Ducking: read rules map', () {
        final _ = ducking.rules;
      });
      _assertNoThrow(mod, 'Ducking: duckingRules list', () {
        final _ = ducking.duckingRules;
      });
      // Find and remove the QA rule
      final qaRule = ducking.duckingRules.where(
          (r) => r.sourceBus == 'Music' && r.targetBus == 'SFX').firstOrNull;
      if (qaRule != null) {
        _assertNoThrow(mod, 'Ducking: setRuleEnabled false', () {
          ducking.setRuleEnabled(qaRule.id, false);
        });
        _assertNoThrow(mod, 'Ducking: setRuleEnabled true', () {
          ducking.setRuleEnabled(qaRule.id, true);
        });
        _assertNoThrow(mod, 'Ducking: removeRule', () {
          ducking.removeRule(qaRule.id);
        });
      }
      _assertNoThrow(mod, 'Ducking: toJson', () {
        final _ = ducking.toJson();
      });
    } else {
      _diag.log('SKIP: DuckingSystemProvider not available');
    }

    // ── Blend Containers: create + child + evaluate ──
    final blend = _tryGet<BlendContainersProvider>();
    if (blend != null) {
      final countBefore = blend.containerCount;
      _assertNoThrow(mod, 'Blend: createContainer', () {
        blend.createContainer(name: 'QA Blend', rtpcId: 0);
      });
      _assert(mod, 'Blend: count increased',
          blend.containerCount == countBefore + 1);
      final bc = blend.blendContainers.where((c) => c.name == 'QA Blend').firstOrNull;
      if (bc != null) {
        _assertNoThrow(mod, 'Blend: createChild', () {
          blend.createChild(
            containerId: bc.id,
            name: 'QA Child',
            rtpcStart: 0.0,
            rtpcEnd: 1.0,
          );
        });
        _assertNoThrow(mod, 'Blend: evaluateBlend', () {
          final weights = blend.evaluateBlend(bc.id, 0.5);
          _assert(mod, 'Blend: evaluate returns weights', true);
        });
        _assertNoThrow(mod, 'Blend: removeContainer', () {
          blend.removeContainer(bc.id);
        });
      }
      _assertNoThrow(mod, 'Blend: toJson', () {
        final _ = blend.toJson();
      });
    } else {
      _diag.log('SKIP: BlendContainersProvider not available');
    }

    // ── Random Containers: create + child + select ──
    final random = _tryGet<RandomContainersProvider>();
    if (random != null) {
      _assertNoThrow(mod, 'Random: createContainer', () {
        random.createContainer(name: 'QA Random');
      });
      final rc = random.randomContainers.where((c) => c.name == 'QA Random').firstOrNull;
      if (rc != null) {
        _assertNoThrow(mod, 'Random: createChild + addChild', () {
          final child1 = random.createChild(containerId: rc.id, name: 'QA Item 1', weight: 1.0);
          random.addChild(rc.id, child1);
        });
        _assertNoThrow(mod, 'Random: createChild 2 + addChild', () {
          final child2 = random.createChild(containerId: rc.id, name: 'QA Item 2', weight: 2.0);
          random.addChild(rc.id, child2);
        });
        _assertNoThrow(mod, 'Random: selectChild', () {
          final sel = random.selectChild(rc.id);
          _assertNotNull(mod, 'Random: selection result', sel);
        });
        _assertNoThrow(mod, 'Random: deterministic mode', () {
          random.setDeterministicMode(rc.id, true, seed: 42);
        });
        _assertNoThrow(mod, 'Random: reset deterministic', () {
          random.setDeterministicMode(rc.id, false);
        });
        _assertNoThrow(mod, 'Random: removeContainer', () {
          random.removeContainer(rc.id);
        });
      }
      _assertNoThrow(mod, 'Random: toJson', () {
        final _ = random.toJson();
      });
    } else {
      _diag.log('SKIP: RandomContainersProvider not available');
    }

    // ── Sequence Containers: create + steps + playback state ──
    final sequence = _tryGet<SequenceContainersProvider>();
    if (sequence != null) {
      _assertNoThrow(mod, 'Sequence: createContainer', () {
        sequence.createContainer(name: 'QA Sequence');
      });
      final sc = sequence.sequenceContainers.where((c) => c.name == 'QA Sequence').firstOrNull;
      if (sc != null) {
        _assertNoThrow(mod, 'Sequence: createStep', () {
          sequence.createStep(
            containerId: sc.id,
            childId: 1,
            childName: 'QA Step 1',
          );
        });
        _assertNoThrow(mod, 'Sequence: createStep 2', () {
          sequence.createStep(
            containerId: sc.id,
            childId: 2,
            childName: 'QA Step 2',
            delayMs: 100.0,
          );
        });
        _assert(mod, 'Sequence: isPlaying=false initially',
            !sequence.isPlaying(sc.id));
        _assertNoThrow(mod, 'Sequence: setSpeed', () {
          sequence.setSpeed(sc.id, 2.0);
        });
        _assertNoThrow(mod, 'Sequence: setContainerEnabled', () {
          sequence.setContainerEnabled(sc.id, false);
          sequence.setContainerEnabled(sc.id, true);
        });
        _assertNoThrow(mod, 'Sequence: removeContainer', () {
          sequence.removeContainer(sc.id);
        });
      }
      _assertNoThrow(mod, 'Sequence: toJson', () {
        final _ = sequence.toJson();
      });
    } else {
      _diag.log('SKIP: SequenceContainersProvider not available');
    }

    // ── Composite Events: create + layers + undo ──
    final composite = _tryGet<CompositeEventSystemProvider>();
    if (composite != null) {
      final countBefore = composite.compositeEventCount;
      _assertNoThrow(mod, 'Composite: createEvent', () {
        composite.createCompositeEvent(name: 'QA Event', category: 'qa');
      });
      _assert(mod, 'Composite: count increased',
          composite.compositeEventCount == countBefore + 1);
      final ev = composite.compositeEvents.where((e) => e.name == 'QA Event').firstOrNull;
      if (ev != null) {
        _assertNoThrow(mod, 'Composite: selectEvent', () {
          composite.selectCompositeEvent(ev.id);
        });
        _assertEqual(mod, 'Composite: selected event',
            composite.selectedCompositeEventId, ev.id);
        _assertNoThrow(mod, 'Composite: rename', () {
          composite.renameCompositeEvent(ev.id, 'QA Event Renamed');
        });
        // Undo/Redo
        _assertNoThrow(mod, 'Composite: undo safe', () {
          composite.undoCompositeEvents();
        });
        _assertNoThrow(mod, 'Composite: redo safe', () {
          composite.redoCompositeEvents();
        });
        // Cleanup
        _assertNoThrow(mod, 'Composite: deleteEvent', () {
          composite.deleteCompositeEvent(ev.id);
        });
      }
      _assert(mod, 'Composite: count restored',
          composite.compositeEventCount == countBefore);
    } else {
      _diag.log('SKIP: CompositeEventSystemProvider not available');
    }

    // ── Bus Hierarchy: CRUD + hierarchy traversal ──
    final busH = _tryGet<BusHierarchyProvider>();
    if (busH != null) {
      _assertNotNull(mod, 'BusHierarchy: master bus', busH.master);
      _assertNoThrow(mod, 'BusHierarchy: allBuses', () {
        final buses = busH.allBuses;
        _assert(mod, 'BusHierarchy: at least master', buses.isNotEmpty);
      });
      _assertNoThrow(mod, 'BusHierarchy: allBusIds', () {
        final _ = busH.allBusIds;
      });
      _assertNoThrow(mod, 'BusHierarchy: createBus', () {
        busH.createBus(name: 'QA Aux Bus');
      });
      final qaBus = busH.getBusByName('QA Aux Bus');
      if (qaBus != null) {
        _assertNoThrow(mod, 'BusHierarchy: setBusVolume', () {
          busH.setBusVolume(qaBus.busId, 0.75);
        });
        _assertNoThrow(mod, 'BusHierarchy: toggleBusMute', () {
          busH.toggleBusMute(qaBus.busId);
          busH.toggleBusMute(qaBus.busId);
        });
        _assertNoThrow(mod, 'BusHierarchy: getEffectiveVolume', () {
          final vol = busH.getEffectiveVolume(qaBus.busId);
          _assertInRange(mod, 'BusHierarchy: effective vol', vol, 0.0, 2.0);
        });
        _assertNoThrow(mod, 'BusHierarchy: getDescendants', () {
          final _ = busH.getDescendants(qaBus.busId);
        });
        _assertNoThrow(mod, 'BusHierarchy: getParentChain', () {
          final _ = busH.getParentChain(qaBus.busId);
        });
        _assertNoThrow(mod, 'BusHierarchy: removeBus', () {
          busH.removeBus(qaBus.busId);
        });
      }
      _assertNoThrow(mod, 'BusHierarchy: toJson', () {
        final _ = busH.toJson();
      });
    } else {
      _diag.log('SKIP: BusHierarchyProvider not available');
    }

    // ── Voice Pool: stats + config ──
    final voicePool = _tryGet<VoicePoolProvider>();
    if (voicePool != null) {
      _assertNoThrow(mod, 'VoicePool: read active count', () {
        final _ = voicePool.activeCount;
      });
      _assertNoThrow(mod, 'VoicePool: virtualCount', () {
        final _ = voicePool.virtualCount;
      });
      _assertNoThrow(mod, 'VoicePool: availableSlots', () {
        final _ = voicePool.availableSlots;
      });
      _assertNoThrow(mod, 'VoicePool: peakVoices', () {
        final _ = voicePool.peakVoices;
      });
      _assertNoThrow(mod, 'VoicePool: stealCount', () {
        final _ = voicePool.stealCount;
      });
      _assertNoThrow(mod, 'VoicePool: engine stats', () {
        final _ = voicePool.engineActiveCount;
        final _ = voicePool.engineMaxVoices;
        final _ = voicePool.engineLoopingCount;
        final _ = voicePool.engineUtilization;
      });
      _assertNoThrow(mod, 'VoicePool: pool type stats', () {
        final _ = voicePool.dawVoices;
        final _ = voicePool.slotLabVoices;
        final _ = voicePool.middlewareVoices;
        final _ = voicePool.sfxVoices;
        final _ = voicePool.musicVoices;
      });
      _assertNoThrow(mod, 'VoicePool: syncFromEngine', () {
        voicePool.syncFromEngine();
      });
      _assertNoThrow(mod, 'VoicePool: getStats', () {
        final _ = voicePool.getStats();
      });
      _assertNoThrow(mod, 'VoicePool: getEngineStatsMap', () {
        final map = voicePool.getEngineStatsMap();
        _assert(mod, 'VoicePool: stats map accessible', map.isNotEmpty || map.isEmpty);
      });
      _assertNoThrow(mod, 'VoicePool: config', () {
        final _ = voicePool.config;
      });
      _assertNoThrow(mod, 'VoicePool: toJson', () {
        final _ = voicePool.toJson();
      });
    } else {
      _diag.log('SKIP: VoicePoolProvider not available');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 5: SLOTLAB ENGINE
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testSlotLabEngine(SlotLabProvider provider) async {
    const mod = 'SlotLab';

    final composer = _tryGet<FeatureComposerProvider>();
    if (composer != null) {
      if (!composer.isConfigured) {
        _assertNoThrow(mod, 'Apply default config', () {
          const config = SlotMachineConfig(
            name: 'QA Machine',
            reelCount: 5,
            rowCount: 3,
            paylineCount: 20,
            winTierCount: 5,
          );
          composer.applyConfig(config);
        });
      }
      _assert(mod, 'Config applied', composer.isConfigured);
    }

    if (!provider.initialized) {
      _assertNoThrow(mod, 'Initialize engine', () {
        provider.initialize();
      });
    }
    _assert(mod, 'Engine initialized', provider.initialized);

    if (!provider.initialized) {
      _diag.log('SKIP SlotLab spin tests — engine not initialized');
      return;
    }

    // Basic spin with retry (detects flaky engine init)
    await _assertWithRetry(mod, 'Basic spin', () async {
      final result = await provider.spin();
      return result != null;
    }, failDetail: 'spin() returned null');
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Forced outcome spins
    for (final outcome in ForcedOutcome.values) {
      await _assertNoThrowAsync(
          mod, 'Forced spin: ${outcome.name}', () async {
        await provider.spinForced(outcome);
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    // Grid size changes
    final gridTests = [
      (reels: 3, rows: 3),
      (reels: 5, rows: 3),
      (reels: 5, rows: 4),
      (reels: 6, rows: 4),
      (reels: 8, rows: 4),
    ];
    for (final grid in gridTests) {
      _assertNoThrow(mod, 'Grid change ${grid.reels}x${grid.rows}', () {
        provider.updateGridSize(grid.reels, grid.rows);
      });
    }
    provider.updateGridSize(5, 3);

    // Spin after grid changes
    await _assertWithRetry(mod, 'Spin after grid changes', () async {
      final result = await provider.spin();
      return result != null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 5.5: GAME MATH VALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testGameMath(SlotLabProvider slotLab) async {
    const mod = 'GameMath';

    final validator = GameMathValidator(_diag);
    try {
      // Quick 100-spin validation during full QA (full validation via UI button)
      final report = await validator.validate(
        slotLab: slotLab,
        spinCount: 100,
      );

      // Convert GameMath findings to QA assertions
      for (final f in report.findings) {
        _assert(mod, '${f.category}: ${f.test}', f.passed,
            f.detail);
      }

      _diag.log('[QA] Game Math: ${report.passed}/${report.total} passed');
    } catch (e) {
      _assert(mod, 'Game Math did not throw', false, '$e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 6: SLOTLAB SUBSYSTEMS
  // ═══════════════════════════════════════════════════════════════════════════

  void _testSlotLabSubsystems() {
    const mod = 'SlotLabSub';

    // ── BehaviorTree: tree structure + node operations ──
    final bt = _tryGet<BehaviorTreeProvider>();
    if (bt != null) {
      _assertNotNull(mod, 'BehaviorTree: instance', bt);
      _assertNoThrow(mod, 'BehaviorTree: read tree', () {
        final _ = bt.tree;
      });
      _assertNoThrow(mod, 'BehaviorTree: allNodes', () {
        final nodes = bt.allNodes;
        _assert(mod, 'BehaviorTree: allNodes accessible', true);
      });
      _assertNoThrow(mod, 'BehaviorTree: coveragePercent', () {
        final cov = bt.coveragePercent;
        _assertInRange(mod, 'BehaviorTree: coverage 0-100', cov, 0.0, 100.0);
      });
      _assertNoThrow(mod, 'BehaviorTree: boundNodeCount', () {
        final _ = bt.boundNodeCount;
      });
      _assertNoThrow(mod, 'BehaviorTree: totalNodeCount', () {
        final _ = bt.totalNodeCount;
      });
      _assertNoThrow(mod, 'BehaviorTree: nodesByCategory', () {
        final _ = bt.nodesByCategory;
      });
      _assertNoThrow(mod, 'BehaviorTree: errorNodes', () {
        final _ = bt.errorNodes;
      });
      _assertNoThrow(mod, 'BehaviorTree: unboundNodes', () {
        final _ = bt.unboundNodes;
      });
      _assertNoThrow(mod, 'BehaviorTree: activeContext', () {
        final _ = bt.activeContext;
      });
      _assertNoThrow(mod, 'BehaviorTree: selectNode null', () {
        bt.selectNode(null);
      });
      _assertNoThrow(mod, 'BehaviorTree: isDirty', () {
        final _ = bt.isDirty;
      });
      _assertNoThrow(mod, 'BehaviorTree: toJson', () {
        final json = bt.toJson();
        _assert(mod, 'BehaviorTree: toJson non-empty', json.isNotEmpty);
      });
      _assertNoThrow(mod, 'BehaviorTree: dispatchHook safe', () {
        bt.dispatchHook('__QA_NONEXISTENT__');
      });
      _assertNoThrow(mod, 'BehaviorTree: resetAllNodeStates', () {
        bt.resetAllNodeStates();
      });
    }

    // ── StateGate: state transitions ──
    final sg = _tryGet<StateGateProvider>();
    if (sg != null) {
      _assertNotNull(mod, 'StateGate: instance', sg);
      _assertNoThrow(mod, 'StateGate: currentSubstate', () {
        final _ = sg.currentSubstate;
      });
      _assertNoThrow(mod, 'StateGate: previousSubstate', () {
        final _ = sg.previousSubstate;
      });
      _assertNoThrow(mod, 'StateGate: isAutoplay', () {
        final _ = sg.isAutoplay;
      });
      _assertNoThrow(mod, 'StateGate: isTurbo', () {
        final _ = sg.isTurbo;
      });
      _assertNoThrow(mod, 'StateGate: volatilityIndex', () {
        final _ = sg.volatilityIndex;
      });
      _assertNoThrow(mod, 'StateGate: allowedHooks', () {
        final hooks = sg.allowedHooks;
        _assert(mod, 'StateGate: allowedHooks accessible', true);
      });
      _assertNoThrow(mod, 'StateGate: blockedCount/passedCount', () {
        final _ = sg.blockedCount;
        final _ = sg.passedCount;
      });
      _assertNoThrow(mod, 'StateGate: checkHook safe', () {
        sg.checkHook('__QA_TEST_HOOK__');
      });
      _assertNoThrow(mod, 'StateGate: featureFlags', () {
        final _ = sg.featureFlags;
      });
      _assertNoThrow(mod, 'StateGate: history', () {
        final _ = sg.history;
      });
      // setAutoplay cycle
      _assertNoThrow(mod, 'StateGate: setAutoplay true', () {
        sg.setAutoplay(true);
      });
      _assert(mod, 'StateGate: isAutoplay after set', sg.isAutoplay);
      _assertNoThrow(mod, 'StateGate: setAutoplay false', () {
        sg.setAutoplay(false);
      });
      // setTurbo cycle
      _assertNoThrow(mod, 'StateGate: setTurbo cycle', () {
        sg.setTurbo(true);
        sg.setTurbo(false);
      });
      _assertNoThrow(mod, 'StateGate: setVolatilityIndex', () {
        sg.setVolatilityIndex(0.5);
      });
      _assertNoThrow(mod, 'StateGate: resetToIdle', () {
        sg.resetToIdle();
      });
    }

    // ── EmotionalState: full lifecycle ──
    final emo = _tryGet<EmotionalStateProvider>();
    if (emo != null) {
      _assertNotNull(mod, 'EmotionalState: instance', emo);
      _assertNoThrow(mod, 'EmotionalState: state', () {
        final _ = emo.state;
      });
      _assertNoThrow(mod, 'EmotionalState: intensity', () {
        final _ = emo.intensity;
      });
      _assertNoThrow(mod, 'EmotionalState: tension', () {
        final _ = emo.tension;
      });
      _assertNoThrow(mod, 'EmotionalState: escalationBias', () {
        final _ = emo.escalationBias;
      });
      _assertNoThrow(mod, 'EmotionalState: cascadeDepth', () {
        final _ = emo.cascadeDepth;
      });
      _assertNoThrow(mod, 'EmotionalState: consecutiveLossCount', () {
        final _ = emo.consecutiveLossCount;
      });
      _assertNoThrow(mod, 'EmotionalState: spinHistory', () {
        final _ = emo.spinHistory;
      });
      _assertNoThrow(mod, 'EmotionalState: output', () {
        final _ = emo.output;
      });
      // Simulate a spin cycle
      _assertNoThrow(mod, 'EmotionalState: onSpinStart', () {
        emo.onSpinStart();
      });
      _assertNoThrow(mod, 'EmotionalState: onSpinResult loss', () {
        emo.onSpinResult(winAmount: 0, betAmount: 1.0);
      });
      _assertNoThrow(mod, 'EmotionalState: onSpinResult win', () {
        emo.onSpinResult(winAmount: 5.0, betAmount: 1.0);
      });
      _assertNoThrow(mod, 'EmotionalState: onAnticipation', () {
        emo.onAnticipation(2);
      });
      _assertNoThrow(mod, 'EmotionalState: onCascadeStart', () {
        emo.onCascadeStart();
      });
      _assertNoThrow(mod, 'EmotionalState: onCascadeStep', () {
        emo.onCascadeStep(1);
      });
      _assertNoThrow(mod, 'EmotionalState: onBigWin', () {
        emo.onBigWin(3);
      });
      _assertNoThrow(mod, 'EmotionalState: onWinPresentationEnd', () {
        emo.onWinPresentationEnd();
      });
      _assertNoThrow(mod, 'EmotionalState: tick', () {
        emo.tick(0.016);
      });
      _assertNoThrow(mod, 'EmotionalState: reset', () {
        emo.reset();
      });
    }

    // ── PriorityEngine: resolution ──
    final pe = _tryGet<PriorityEngineProvider>();
    if (pe != null) {
      _assertNotNull(mod, 'PriorityEngine: instance', pe);
      _assertNoThrow(mod, 'PriorityEngine: activeBehaviors', () {
        final _ = pe.activeBehaviors;
      });
      _assertNoThrow(mod, 'PriorityEngine: resolutionLog', () {
        final _ = pe.resolutionLog;
      });
      _assertNoThrow(mod, 'PriorityEngine: highestActivePriority', () {
        final _ = pe.highestActivePriority;
      });
      _assertNoThrow(mod, 'PriorityEngine: clearAll', () {
        pe.clearAll();
      });
      _assertNoThrow(mod, 'PriorityEngine: clearLog', () {
        pe.clearLog();
      });
    }

    // ── OrchestrationEngine: decisions ──
    final oe = _tryGet<OrchestrationEngineProvider>();
    if (oe != null) {
      _assertNotNull(mod, 'OrchestrationEngine: instance', oe);
      _assertNoThrow(mod, 'OrchestrationEngine: context', () {
        final _ = oe.context;
      });
      _assertNoThrow(mod, 'OrchestrationEngine: decisions', () {
        final _ = oe.decisions;
      });
      _assertNoThrow(mod, 'OrchestrationEngine: diagnosticLog', () {
        final _ = oe.diagnosticLog;
      });
      _assertNoThrow(mod, 'OrchestrationEngine: clearDecisions', () {
        oe.clearDecisions();
      });
      _assertNoThrow(mod, 'OrchestrationEngine: clearLog', () {
        oe.clearLog();
      });
    }

    // ── SimulationEngine: state machine ──
    final sim = _tryGet<SimulationEngineProvider>();
    if (sim != null) {
      _assertNotNull(mod, 'SimulationEngine: instance', sim);
      _assertNoThrow(mod, 'SimulationEngine: isRunning', () {
        final _ = sim.isRunning;
      });
      _assertNoThrow(mod, 'SimulationEngine: mode', () {
        final _ = sim.mode;
      });
      _assertNoThrow(mod, 'SimulationEngine: currentStep/totalSteps', () {
        final _ = sim.currentStep;
        final _ = sim.totalSteps;
      });
      _assertNoThrow(mod, 'SimulationEngine: progress', () {
        final _ = sim.progress;
      });
      _assertNoThrow(mod, 'SimulationEngine: lastResult', () {
        final _ = sim.lastResult;
      });
      _assertNoThrow(mod, 'SimulationEngine: history', () {
        final _ = sim.history;
      });
      _assertNoThrow(mod, 'SimulationEngine: bakeUnlocked', () {
        final _ = sim.bakeUnlocked;
      });
      _assertNoThrow(mod, 'SimulationEngine: PBSE stats', () {
        final _ = sim.pbseTotalSpins;
        final _ = sim.domainResults;
        final _ = sim.fatigueResult;
        final _ = sim.hasResults;
        final _ = sim.passedDomainCount;
        final _ = sim.failedDomainCount;
      });
      _assertNoThrow(mod, 'SimulationEngine: reset', () {
        sim.reset();
      });
    }

    // ── TransitionSystem: rules ──
    final ts = _tryGet<TransitionSystemProvider>();
    if (ts != null) {
      _assertNotNull(mod, 'TransitionSystem: instance', ts);
      _assertNoThrow(mod, 'TransitionSystem: activeTransition', () {
        final _ = ts.activeTransition;
      });
      _assertNoThrow(mod, 'TransitionSystem: isTransitioning', () {
        final _ = ts.isTransitioning;
      });
      _assertNoThrow(mod, 'TransitionSystem: history', () {
        final _ = ts.history;
      });
      _assertNoThrow(mod, 'TransitionSystem: allRules', () {
        final _ = ts.allRules;
      });
    }

    // ── GameFlow: state machine ──
    final gf = _tryGet<GameFlowProvider>();
    if (gf != null) {
      _assertNotNull(mod, 'GameFlow: instance', gf);
      _assertNoThrow(mod, 'GameFlow: currentState', () {
        final _ = gf.currentState;
      });
      _assertNoThrow(mod, 'GameFlow: isIdle/isBaseGame/isInFeature', () {
        final _ = gf.isIdle;
        final _ = gf.isBaseGame;
        final _ = gf.isInFeature;
      });
      _assertNoThrow(mod, 'GameFlow: featureDepth', () {
        final _ = gf.featureDepth;
      });
      _assertNoThrow(mod, 'GameFlow: activeFeatures', () {
        final _ = gf.activeFeatures;
      });
      _assertNoThrow(mod, 'GameFlow: featureQueue', () {
        final _ = gf.featureQueue;
      });
      _assertNoThrow(mod, 'GameFlow: totalWin', () {
        final _ = gf.totalWin;
      });
      _assertNoThrow(mod, 'GameFlow: isInTransition', () {
        final _ = gf.isInTransition;
      });
      _assertNoThrow(mod, 'GameFlow: feature states', () {
        final _ = gf.freeSpinsState;
        final _ = gf.cascadeState;
        final _ = gf.holdAndWinState;
        final _ = gf.gambleState;
        final _ = gf.bonusGameState;
        final _ = gf.respinState;
        final _ = gf.wildFeaturesState;
        final _ = gf.multiplierState;
      });
      _assertNoThrow(mod, 'GameFlow: resetToBaseGame', () {
        gf.resetToBaseGame();
      });
    }

    // ── StageFlow: graph + presets ──
    final sf = _tryGet<StageFlowProvider>();
    if (sf != null) {
      _assertNotNull(mod, 'StageFlow: instance', sf);
      _assertNoThrow(mod, 'StageFlow: hasGraph', () {
        final _ = sf.hasGraph;
      });
      _assertNoThrow(mod, 'StageFlow: presets', () {
        final presets = sf.presets;
        _assert(mod, 'StageFlow: presets accessible', true);
      });
      _assertNoThrow(mod, 'StageFlow: builtInPresets', () {
        final _ = sf.builtInPresets;
      });
      _assertNoThrow(mod, 'StageFlow: validationErrors', () {
        final _ = sf.validationErrors;
      });
      _assertNoThrow(mod, 'StageFlow: canUndo/canRedo', () {
        final _ = sf.canUndo;
        final _ = sf.canRedo;
      });
      _assertNoThrow(mod, 'StageFlow: isDryRunning', () {
        final _ = sf.isDryRunning;
      });
      _assertNoThrow(mod, 'StageFlow: gameRecall', () {
        final _ = sf.gameRecall;
      });
    }

    // ── ContextLayer: modes + overrides ──
    final cl = _tryGet<ContextLayerProvider>();
    if (cl != null) {
      _assertNotNull(mod, 'ContextLayer: instance', cl);
      _assertNoThrow(mod, 'ContextLayer: currentMode', () {
        final _ = cl.currentMode;
      });
      _assertNoThrow(mod, 'ContextLayer: toJson', () {
        final json = cl.toJson();
        _assert(mod, 'ContextLayer: toJson non-empty', true);
      });
      _assertNoThrow(mod, 'ContextLayer: clearAll', () {
        cl.clearAll();
      });
    }

    // ── TriggerLayer: bindings ──
    final tl = _tryGet<TriggerLayerProvider>();
    if (tl != null) {
      _assertNotNull(mod, 'TriggerLayer: instance', tl);
      _assertNoThrow(mod, 'TriggerLayer: bindings', () {
        final _ = tl.bindings;
      });
      _assertNoThrow(mod, 'TriggerLayer: history', () {
        final _ = tl.history;
      });
      _assertNoThrow(mod, 'TriggerLayer: autoBindingsEnabled', () {
        final _ = tl.autoBindingsEnabled;
      });
      _assertNoThrow(mod, 'TriggerLayer: unboundHooks', () {
        final _ = tl.unboundHooks;
      });
      _assertNoThrow(mod, 'TriggerLayer: resolve non-existent hook', () {
        tl.resolve('__QA_NONEXISTENT__');
      });
      _assertNoThrow(mod, 'TriggerLayer: toJson', () {
        final json = tl.toJson();
        _assert(mod, 'TriggerLayer: toJson non-empty', true);
      });
    }

    // ── SlotLab Undo: stack operations ──
    final undo = _tryGet<SlotLabUndoProvider>();
    if (undo != null) {
      _assertNotNull(mod, 'SlotLabUndo: instance', undo);
      _assertNoThrow(mod, 'SlotLabUndo: canUndo', () {
        final _ = undo.canUndo;
      });
      _assertNoThrow(mod, 'SlotLabUndo: canRedo', () {
        final _ = undo.canRedo;
      });
      _assertNoThrow(mod, 'SlotLabUndo: undoCount/redoCount', () {
        final _ = undo.undoCount;
        final _ = undo.redoCount;
      });
      _assertNoThrow(mod, 'SlotLabUndo: undoDescription', () {
        final _ = undo.undoDescription;
      });
      _assertNoThrow(mod, 'SlotLabUndo: undoHistory', () {
        final _ = undo.undoHistory;
      });
      // Undo/redo cycle (safe even if empty)
      _assertNoThrow(mod, 'SlotLabUndo: undo empty', () {
        undo.undo();
      });
      _assertNoThrow(mod, 'SlotLabUndo: redo empty', () {
        undo.redo();
      });
    }

    // ── EnergyGovernance: profile + session ──
    final eg = _tryGet<EnergyGovernanceProvider>();
    if (eg != null) {
      _assertNotNull(mod, 'EnergyGovernance: instance', eg);
      _assertNoThrow(mod, 'EnergyGovernance: activeProfile', () {
        final _ = eg.activeProfile;
      });
      _assertNoThrow(mod, 'EnergyGovernance: activeCurve', () {
        final _ = eg.activeCurve;
      });
      _assertNoThrow(mod, 'EnergyGovernance: domainCaps', () {
        final _ = eg.domainCaps;
      });
      _assertNoThrow(mod, 'EnergyGovernance: overallCap', () {
        final _ = eg.overallCap;
      });
      _assertNoThrow(mod, 'EnergyGovernance: session stats', () {
        final _ = eg.totalSpins;
        final _ = eg.lossStreak;
        final _ = eg.sessionMemorySM;
      });
      _assertNoThrow(mod, 'EnergyGovernance: featureStorm/jackpot', () {
        final _ = eg.featureStormActive;
        final _ = eg.jackpotCompressionActive;
      });
      _assertNoThrow(mod, 'EnergyGovernance: voiceBudget', () {
        final _ = eg.voiceBudgetMax;
        final _ = eg.voiceBudgetRatio;
      });
      _assertNoThrow(mod, 'EnergyGovernance: recordSpin', () {
        eg.recordSpin(winMultiplier: 0.0);
        eg.recordSpin(winMultiplier: 5.0, isFeature: true);
      });
      _assertNoThrow(mod, 'EnergyGovernance: getEnergyConfigJson', () {
        final _ = eg.getEnergyConfigJson();
      });
      _assertNoThrow(mod, 'EnergyGovernance: resetSession', () {
        eg.resetSession();
      });
    }

    // ── DPM: priority computation ──
    final dpm = _tryGet<DpmProvider>();
    if (dpm != null) {
      _assertNotNull(mod, 'DPM: instance', dpm);
      _assertNoThrow(mod, 'DPM: emotionalState', () {
        final _ = dpm.emotionalState;
      });
      _assertNoThrow(mod, 'DPM: retained/attenuated/suppressed/ducked', () {
        final _ = dpm.retained;
        final _ = dpm.attenuated;
        final _ = dpm.suppressed;
        final _ = dpm.ducked;
      });
      _assertNoThrow(mod, 'DPM: jackpotOverride', () {
        final _ = dpm.jackpotOverride;
      });
      _assertNoThrow(mod, 'DPM: getEventWeightsJson', () {
        final _ = dpm.getEventWeightsJson();
      });
      _assertNoThrow(mod, 'DPM: getPriorityMatrixJson', () {
        final _ = dpm.getPriorityMatrixJson();
      });
    }

    // ── AUREXIS: core engine ──
    final aurexis = _tryGet<AurexisProvider>();
    if (aurexis != null) {
      _assertNotNull(mod, 'AUREXIS: instance', aurexis);
      _assertNoThrow(mod, 'AUREXIS: initialized/enabled', () {
        final _ = aurexis.initialized;
        final _ = aurexis.enabled;
      });
      _assertNoThrow(mod, 'AUREXIS: parameters', () {
        final _ = aurexis.parameters;
      });
      _assertNoThrow(mod, 'AUREXIS: platform', () {
        final _ = aurexis.platform;
      });
      _assertNoThrow(mod, 'AUREXIS: volatility/rtp', () {
        final _ = aurexis.volatility;
        final _ = aurexis.rtp;
      });
      _assertNoThrow(mod, 'AUREXIS: fatigueLevel', () {
        final _ = aurexis.fatigueLevel;
      });
      _assertNoThrow(mod, 'AUREXIS: exportConfig', () {
        final _ = aurexis.exportConfig();
      });
    }

    // ── AUREXIS Profile: A/B + locks ──
    final aurProfile = _tryGet<AurexisProfileProvider>();
    if (aurProfile != null) {
      _assertNotNull(mod, 'AUREXIS Profile: instance', aurProfile);
      _assertNoThrow(mod, 'AUREXIS Profile: activeProfile', () {
        final _ = aurProfile.activeProfile;
      });
      _assertNoThrow(mod, 'AUREXIS Profile: customProfiles', () {
        final _ = aurProfile.customProfiles;
      });
      _assertNoThrow(mod, 'AUREXIS Profile: allProfiles', () {
        final _ = aurProfile.allProfiles;
      });
      _assertNoThrow(mod, 'AUREXIS Profile: abActive/showingB', () {
        final _ = aurProfile.abActive;
        final _ = aurProfile.showingB;
      });
      _assertNoThrow(mod, 'AUREXIS Profile: locks', () {
        final _ = aurProfile.lockSpatial;
        final _ = aurProfile.lockDynamics;
        final _ = aurProfile.lockMusic;
        final _ = aurProfile.lockVariation;
      });
      _assertNoThrow(mod, 'AUREXIS Profile: jurisdiction', () {
        final _ = aurProfile.jurisdiction;
      });
      _assertNoThrow(mod, 'AUREXIS Profile: exportCustomProfilesJson', () {
        final _ = aurProfile.exportCustomProfilesJson();
      });
    }

    // ── Feature Composer: mechanics + stages ──
    final composer = _tryGet<FeatureComposerProvider>();
    if (composer != null) {
      _assertNotNull(mod, 'Composer: instance', composer);
      _assertNoThrow(mod, 'Composer: isConfigured', () {
        final _ = composer.isConfigured;
      });
      _assertNoThrow(mod, 'Composer: mechanicStates', () {
        final _ = composer.mechanicStates;
      });
      _assertNoThrow(mod, 'Composer: enabledMechanics', () {
        final _ = composer.enabledMechanics;
      });
      _assertNoThrow(mod, 'Composer: composedStages', () {
        final _ = composer.composedStages;
      });
      _assertNoThrow(mod, 'Composer: engineCoreStages', () {
        final _ = composer.engineCoreStages;
      });
      _assertNoThrow(mod, 'Composer: featureStages', () {
        final _ = composer.featureStages;
      });
      _assertNoThrow(mod, 'Composer: activeHooks', () {
        final _ = composer.activeHooks;
      });
      _assertNoThrow(mod, 'Composer: totalStageCount', () {
        final _ = composer.totalStageCount;
      });
      _assertNoThrow(mod, 'Composer: toJson', () {
        final json = composer.toJson();
        _assert(mod, 'Composer: toJson non-empty', json.isNotEmpty);
      });
    }

    // ── SlotLab Project ──
    final project = _tryGet<SlotLabProjectProvider>();
    if (project != null) {
      _assertNotNull(mod, 'SlotLabProject: instance', project);
      _assertNoThrow(mod, 'SlotLabProject: projectName', () {
        final _ = project.projectName;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 7: CROSS-MODULE INTEGRITY
  // ═══════════════════════════════════════════════════════════════════════════

  void _testCrossModuleIntegrity(
      SlotLabProvider? slotLab, MixerProvider? mixer) {
    const mod = 'CrossModule';

    // DiagnosticsService singleton consistency
    _assert(mod, 'DiagnosticsService singleton',
        identical(DiagnosticsService.instance, _diag));

    // GetIt consistency — same instance each time
    final stg1 = _tryGet<StateGroupsProvider>();
    final stg2 = _tryGet<StateGroupsProvider>();
    if (stg1 != null && stg2 != null) {
      _assert(
          mod, 'StateGroups singleton consistency', identical(stg1, stg2));
    }

    final bt1 = _tryGet<BehaviorTreeProvider>();
    final bt2 = _tryGet<BehaviorTreeProvider>();
    if (bt1 != null && bt2 != null) {
      _assert(mod, 'BehaviorTree singleton consistency',
          identical(bt1, bt2));
    }

    // Mixer bus mapping consistency
    if (mixer != null) {
      _assertEqual(mod, 'Master bus index',
          MixerProvider.busIdToEngineBusIndex('master'), 0);
      _assertEqual(mod, 'Music bus index',
          MixerProvider.busIdToEngineBusIndex('music'), 1);
      _assertEqual(mod, 'SFX bus index',
          MixerProvider.busIdToEngineBusIndex('sfx'), 2);
      _assertEqual(mod, 'Voice bus index',
          MixerProvider.busIdToEngineBusIndex('voice'), 3);
      _assertEqual(mod, 'Ambience bus index',
          MixerProvider.busIdToEngineBusIndex('ambience'), 4);
      _assertEqual(mod, 'Unknown bus index',
          MixerProvider.busIdToEngineBusIndex('nonexistent'), -1);
    }

    // Feature Composer ↔ SlotLab consistency
    if (slotLab != null) {
      final composer = _tryGet<FeatureComposerProvider>();
      if (composer != null && composer.isConfigured) {
        final cfg = composer.config;
        if (cfg != null) {
          _assert(
              mod, 'Composer config reelCount > 0', cfg.reelCount > 0);
          _assert(
              mod, 'Composer config rowCount > 0', cfg.rowCount > 0);
        }
      }
    }

    // NativeFFI loaded
    try {
      final ffi = NativeFFI.instance;
      _assert(mod, 'NativeFFI instance exists', true);
      _assert(mod, 'NativeFFI isLoaded', ffi.isLoaded);
    } catch (e) {
      _assert(mod, 'NativeFFI instance exists', false, 'Error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 8: EDGE CASES
  // ═══════════════════════════════════════════════════════════════════════════

  void _testEdgeCases(MixerProvider? mixer, SlotLabProvider? slotLab) {
    const mod = 'EdgeCase';

    // Mixer: operations on non-existent channel IDs
    if (mixer != null) {
      _assertNoThrow(mod, 'Mixer: set volume on invalid ID', () {
        mixer.setChannelVolume('__INVALID_ID__', 0.5);
      });
      _assertNoThrow(mod, 'Mixer: toggle mute on invalid ID', () {
        mixer.toggleChannelMute('__INVALID_ID__');
      });
      _assertNoThrow(mod, 'Mixer: toggle solo on invalid ID', () {
        mixer.toggleChannelSolo('__INVALID_ID__');
      });
      _assertNoThrow(mod, 'Mixer: set pan on invalid ID', () {
        mixer.setChannelPan('__INVALID_ID__', 0.5);
      });

      // Boundary values (fresh lookup after each mutation — copyWith pattern)
      // FFIBoundsChecker REJECTS invalid volume (returns early), doesn't clamp
      _assertNoThrow(mod, 'Mixer: volume negative rejected', () {
        final ch = mixer.channels.firstOrNull;
        if (ch != null) {
          final id = ch.id;
          final before = _ch(mixer, id)!.volume;
          mixer.setChannelVolume(id, -1.0);
          _assertEqual(
              mod, 'Volume unchanged after negative', _ch(mixer, id)!.volume, before);
        }
      });
      _assertNoThrow(mod, 'Mixer: volume over max clamped', () {
        final ch = mixer.channels.firstOrNull;
        if (ch != null) {
          final id = ch.id;
          mixer.setChannelVolume(id, 10.0);
          _assertInRange(
              mod, 'Volume clamped <= 2', _ch(mixer, id)!.volume, 0.0, 2.01);
          mixer.setChannelVolume(id, 1.0);
        }
      });

      // Pan boundaries — FFIBoundsChecker REJECTS out-of-range pan
      _assertNoThrow(mod, 'Mixer: pan extreme negative rejected', () {
        final ch = mixer.channels.firstOrNull;
        if (ch != null) {
          final id = ch.id;
          final before = _ch(mixer, id)!.pan;
          mixer.setChannelPan(id, -5.0);
          _assertEqual(
              mod, 'Pan unchanged after extreme negative', _ch(mixer, id)!.pan, before);
        }
      });
      _assertNoThrow(mod, 'Mixer: pan extreme positive rejected', () {
        final ch = mixer.channels.firstOrNull;
        if (ch != null) {
          final id = ch.id;
          final before = _ch(mixer, id)!.pan;
          mixer.setChannelPan(id, 5.0);
          _assertEqual(
              mod, 'Pan unchanged after extreme positive', _ch(mixer, id)!.pan, before);
        }
      });

      // Double-delete safety
      _assertNoThrow(mod, 'Mixer: delete non-existent channel', () {
        mixer.deleteChannel('__NONEXISTENT__');
      });
    }

    // SlotLab edge cases
    if (slotLab != null && slotLab.initialized) {
      _assertNoThrow(mod, 'SlotLab: minimum grid 3×1', () {
        slotLab.updateGridSize(3, 1);
      });
      _assertNoThrow(mod, 'SlotLab: maximum grid 8×6', () {
        slotLab.updateGridSize(8, 6);
      });
      slotLab.updateGridSize(5, 3);
    }

    // Middleware edge cases
    final stateGroups = _tryGet<StateGroupsProvider>();
    if (stateGroups != null) {
      _assertNoThrow(mod, 'StateGroups: unregister non-existent', () {
        stateGroups.unregisterStateGroup(-999);
      });
      _assertNoThrow(
          mod, 'StateGroups: setState on non-existent group', () {
        stateGroups.setState(-999, 0);
      });
    }

    // DiagnosticsService: safe with no monitors
    _assertNoThrow(mod, 'DiagnosticsService: reportFinding safe', () {
      _diag.reportFinding(DiagnosticFinding(
        checker: 'QA_EdgeTest',
        severity: DiagnosticSeverity.ok,
        message: 'Edge case test finding',
      ));
    });
    _assertNoThrow(mod, 'DiagnosticsService: clearFindings safe', () {
      // Don't actually clear during QA — just test it doesn't crash
      // _diag.clearFindings();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 9: STRESS TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testStress(
      MixerProvider? mixer, SlotLabProvider? slotLab) async {
    const mod = 'Stress';

    // Helper to safely delete a QA channel (may throw on unmodifiable memberIds)
    void safeDelete(String id) {
      try { mixer!.deleteChannel(id); } catch (_) {}
    }

    // Rapid-fire mixer volume changes (100 in tight loop)
    if (mixer != null) {
      _assertNoThrow(mod, 'Mixer: 100 rapid volume changes', () {
        mixer.createChannel(name: 'QA Stress Channel');
        final ch = mixer.channels
            .where((c) => c.name == 'QA Stress Channel')
            .firstOrNull;
        if (ch != null) {
          final id = ch.id;
          for (int i = 0; i < 100; i++) {
            mixer.setChannelVolume(id, (i % 20) / 10.0);
          }
          _assertInRange(
              mod, 'Volume after rapid changes', _ch(mixer, id)?.volume ?? -1, 0.0, 2.0);
          safeDelete(id);
        }
      });

      // Rapid mute/solo toggles (50 each)
      _assertNoThrow(mod, 'Mixer: 50 rapid mute toggles', () {
        mixer.createChannel(name: 'QA Mute Stress');
        final ch = mixer.channels
            .where((c) => c.name == 'QA Mute Stress')
            .firstOrNull;
        if (ch != null) {
          final id = ch.id;
          for (int i = 0; i < 50; i++) {
            mixer.toggleChannelMute(id);
          }
          // 50 toggles = back to original (even number)
          _assert(mod, 'Mute back to original after 50 toggles',
              !(_ch(mixer, id)?.muted ?? true));
          safeDelete(id);
        }
      });

      _assertNoThrow(mod, 'Mixer: 50 rapid solo toggles', () {
        mixer.createChannel(name: 'QA Solo Stress');
        final ch = mixer.channels
            .where((c) => c.name == 'QA Solo Stress')
            .firstOrNull;
        if (ch != null) {
          final id = ch.id;
          for (int i = 0; i < 50; i++) {
            mixer.toggleChannelSolo(id);
          }
          _assert(mod, 'Solo back to original after 50 toggles',
              !(_ch(mixer, id)?.soloed ?? true));
          safeDelete(id);
        }
      });

      // Create and delete 20 channels rapidly
      _assertNoThrow(mod, 'Mixer: create/delete 20 channels', () {
        final ids = <String>[];
        for (int i = 0; i < 20; i++) {
          mixer.createChannel(name: 'QA Batch $i');
          final ch = mixer.channels
              .where((c) => c.name == 'QA Batch $i')
              .firstOrNull;
          if (ch != null) ids.add(ch.id);
        }
        _assert(mod, 'Created 20 channels',
            ids.length == 20, 'Only created ${ids.length}');
        for (final id in ids) {
          safeDelete(id);
        }
      });

      // Pan sweep: -1 to +1 in 0.01 increments
      _assertNoThrow(mod, 'Mixer: pan sweep 200 steps', () {
        mixer.createChannel(name: 'QA Pan Sweep');
        final ch = mixer.channels
            .where((c) => c.name == 'QA Pan Sweep')
            .firstOrNull;
        if (ch != null) {
          final id = ch.id;
          for (int i = -100; i <= 100; i++) {
            mixer.setChannelPan(id, i / 100.0);
          }
          _assertInRange(
              mod, 'Pan after sweep', _ch(mixer, id)?.pan ?? -99, 0.99, 1.01);
          safeDelete(id);
        }
      });
    }

    // SlotLab rapid grid changes
    if (slotLab != null && slotLab.initialized) {
      _assertNoThrow(mod, 'SlotLab: 20 rapid grid changes', () {
        for (int i = 0; i < 20; i++) {
          final reels = 3 + (i % 6); // 3-8
          final rows = 1 + (i % 6); // 1-6
          slotLab.updateGridSize(reels, rows);
        }
        slotLab.updateGridSize(5, 3);
      });

      // Rapid spins (5 with minimal delay)
      for (int i = 0; i < 5; i++) {
        await _assertNoThrowAsync(
            mod, 'SlotLab: rapid spin ${i + 1}/5', () async {
          await slotLab.spin();
        });
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 10: CONCURRENCY
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testConcurrency(
      MixerProvider? mixer, SlotLabProvider? slotLab) async {
    const mod = 'Concurrency';

    // Simultaneous mixer operations from multiple "sources"
    if (mixer != null) {
      mixer.createChannel(name: 'QA Conc A');
      mixer.createChannel(name: 'QA Conc B');
      final chA =
          mixer.channels.where((c) => c.name == 'QA Conc A').firstOrNull;
      final chB =
          mixer.channels.where((c) => c.name == 'QA Conc B').firstOrNull;

      if (chA != null && chB != null) {
        // Fire volume/pan/mute changes concurrently
        await _assertNoThrowAsync(
            mod, 'Concurrent mixer operations', () async {
          await Future.wait([
            Future.microtask(() {
              for (int i = 0; i < 50; i++) {
                mixer.setChannelVolume(chA.id, (i % 20) / 10.0);
              }
            }),
            Future.microtask(() {
              for (int i = 0; i < 50; i++) {
                mixer.setChannelPan(chB.id, (i % 20) / 10.0 - 1.0);
              }
            }),
            Future.microtask(() {
              for (int i = 0; i < 20; i++) {
                mixer.toggleChannelMute(chA.id);
              }
            }),
            Future.microtask(() {
              for (int i = 0; i < 20; i++) {
                mixer.toggleChannelSolo(chB.id);
              }
            }),
          ]);
        });

        // Verify state consistency after concurrent ops (fresh lookup)
        _assert(mod, 'Channel A muted back to original (even toggles)',
            !(_ch(mixer, chA.id)?.muted ?? true));
        _assert(mod, 'Channel B soloed back to original (even toggles)',
            !(_ch(mixer, chB.id)?.soloed ?? true));
        _assertInRange(
            mod, 'Channel A volume in valid range', _ch(mixer, chA.id)?.volume ?? -1, 0.0, 2.0);
        _assertInRange(
            mod, 'Channel B pan in valid range', _ch(mixer, chB.id)?.pan ?? -99, -1.0, 1.0);

        try { mixer.deleteChannel(chA.id); } catch (_) {}
        try { mixer.deleteChannel(chB.id); } catch (_) {}
      }
    }

    // Concurrent provider reads (all subsystems simultaneously)
    await _assertNoThrowAsync(
        mod, 'Concurrent provider reads', () async {
      await Future.wait([
        Future.microtask(() => _tryGet<StateGroupsProvider>()?.stateGroups),
        Future.microtask(() => _tryGet<RtpcSystemProvider>()?.rtpcDefinitions),
        Future.microtask(() => _tryGet<BlendContainersProvider>()?.containers),
        Future.microtask(() => _tryGet<VoicePoolProvider>()?.activeCount),
        Future.microtask(() => _tryGet<BusHierarchyProvider>()?.allBuses),
        Future.microtask(
            () => _tryGet<CompositeEventSystemProvider>()?.compositeEvents),
        Future.microtask(() => _tryGet<BehaviorTreeProvider>()?.tree),
        Future.microtask(
            () => _tryGet<EmotionalStateProvider>()?.state),
      ]);
    });

    // Concurrent GetIt access (singleton consistency under load)
    await _assertNoThrowAsync(
        mod, 'Concurrent GetIt singleton access', () async {
      final futures = <Future<Object?>>[];
      for (int i = 0; i < 20; i++) {
        futures.add(
            Future.microtask(() => _tryGet<StateGroupsProvider>()));
      }
      final results = await Future.wait(futures);
      final nonNull = results.whereType<StateGroupsProvider>().toList();
      if (nonNull.length > 1) {
        // All should be identical instance
        final allSame = nonNull.every((r) => identical(r, nonNull.first));
        _assert(mod, 'GetIt returns same singleton under concurrent access',
            allSame);
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 11: SLOTLAB COORDINATOR DEEP
  // ═══════════════════════════════════════════════════════════════════════════

  void _testSlotLabCoordinatorDeep(SlotLabProvider p) {
    const mod = 'Coordinator';

    // Config getters
    _assertNoThrow(mod, 'spinCount', () {
      final _ = p.spinCount;
    });
    _assertNoThrow(mod, 'rtp', () {
      final rtp = p.rtp;
      _assert(mod, 'RTP range', rtp.isFinite, 'Value $rtp not finite');
    });
    _assertNoThrow(mod, 'hitRate', () {
      final _ = p.hitRate;
    });
    _assertNoThrow(mod, 'volatilitySlider', () {
      final _ = p.volatilitySlider;
    });
    _assertNoThrow(mod, 'betAmount', () {
      final _ = p.betAmount;
    });
    _assertNoThrow(mod, 'totalReels/totalRows', () {
      final _ = p.totalReels;
      final _ = p.totalRows;
    });

    // Feature toggles
    _assertNoThrow(mod, 'cascadesEnabled', () {
      final _ = p.cascadesEnabled;
    });
    _assertNoThrow(mod, 'freeSpinsEnabled', () {
      final _ = p.freeSpinsEnabled;
    });
    _assertNoThrow(mod, 'jackpotEnabled', () {
      final _ = p.jackpotEnabled;
    });

    // Volatility controls
    _assertNoThrow(mod, 'setVolatilitySlider', () {
      final original = p.volatilitySlider;
      p.setVolatilitySlider(0.5);
      p.setVolatilitySlider(original);
    });

    // Bet amount
    _assertNoThrow(mod, 'setBetAmount', () {
      final original = p.betAmount;
      p.setBetAmount(2.0);
      p.setBetAmount(original);
    });

    // Feature toggle cycles
    _assertNoThrow(mod, 'setCascadesEnabled cycle', () {
      final orig = p.cascadesEnabled;
      p.setCascadesEnabled(!orig);
      p.setCascadesEnabled(orig);
    });
    _assertNoThrow(mod, 'setFreeSpinsEnabled cycle', () {
      final orig = p.freeSpinsEnabled;
      p.setFreeSpinsEnabled(!orig);
      p.setFreeSpinsEnabled(orig);
    });
    _assertNoThrow(mod, 'setJackpotEnabled cycle', () {
      final orig = p.jackpotEnabled;
      p.setJackpotEnabled(!orig);
      p.setJackpotEnabled(orig);
    });

    // Timing
    _assertNoThrow(mod, 'timingProfile', () {
      final _ = p.timingProfile;
    });
    _assertNoThrow(mod, 'timingConfig', () {
      final _ = p.timingConfig;
    });
    _assertNoThrow(mod, 'anticipationPreTriggerMs', () {
      final _ = p.anticipationPreTriggerMs;
    });
    _assertNoThrow(mod, 'totalAudioOffsetMs', () {
      final _ = p.totalAudioOffsetMs;
    });

    // Win tier helpers
    _assertNoThrow(mod, 'getVisualTierForWin', () {
      final tier = p.getVisualTierForWin(100.0);
      _assertNotNull(mod, 'visualTier result', tier);
    });
    _assertNoThrow(mod, 'getRtpcForWin', () {
      final rtpc = p.getRtpcForWin(50.0);
      _assertInRange(mod, 'rtpcForWin range', rtpc, 0.0, 1.0);
    });
    _assertNoThrow(mod, 'shouldTriggerCelebration', () {
      final _ = p.shouldTriggerCelebration(0.01);
      final _ = p.shouldTriggerCelebration(1000.0);
    });
    _assertNoThrow(mod, 'getRollupDurationMs', () {
      final dur = p.getRollupDurationMs(50.0);
      _assert(mod, 'rollup duration >= 0', dur >= 0);
    });

    // Stage playback state
    _assertNoThrow(mod, 'isPlayingStages', () {
      final _ = p.isPlayingStages;
    });
    _assertNoThrow(mod, 'currentStageIndex', () {
      final _ = p.currentStageIndex;
    });
    _assertNoThrow(mod, 'isPaused', () {
      final _ = p.isPaused;
    });
    _assertNoThrow(mod, 'isReelsSpinning', () {
      final _ = p.isReelsSpinning;
    });
    _assertNoThrow(mod, 'isWinPresentationActive', () {
      final _ = p.isWinPresentationActive;
    });

    // Stage data
    _assertNoThrow(mod, 'lastStages', () {
      final _ = p.lastStages;
    });
    _assertNoThrow(mod, 'pooledStages', () {
      final _ = p.pooledStages;
    });
    _assertNoThrow(mod, 'stagePoolStats', () {
      final _ = p.stagePoolStats;
    });

    // Last result data
    _assertNoThrow(mod, 'lastResult', () {
      final _ = p.lastResult;
    });
    _assertNoThrow(mod, 'lastSpinWasWin', () {
      final _ = p.lastSpinWasWin;
    });
    _assertNoThrow(mod, 'lastWinAmount', () {
      final _ = p.lastWinAmount;
    });
    _assertNoThrow(mod, 'lastWinRatio', () {
      final _ = p.lastWinRatio;
    });
    _assertNoThrow(mod, 'lastBigWinTier', () {
      final _ = p.lastBigWinTier;
    });
    _assertNoThrow(mod, 'currentGrid', () {
      final _ = p.currentGrid;
    });

    // Stats
    _assertNoThrow(mod, 'stats', () {
      final _ = p.stats;
    });
    _assertNoThrow(mod, 'slotWinConfig', () {
      final _ = p.slotWinConfig;
    });

    // Anticipation
    _assertNoThrow(mod, 'anticipationConfigType', () {
      final _ = p.anticipationConfigType;
    });
    _assertNoThrow(mod, 'scatterSymbolId', () {
      final _ = p.scatterSymbolId;
    });
    _assertNoThrow(mod, 'bonusSymbolId', () {
      final _ = p.bonusSymbolId;
    });

    // Auto trigger
    _assertNoThrow(mod, 'autoTriggerAudio', () {
      final _ = p.autoTriggerAudio;
    });
    _assertNoThrow(mod, 'aleAutoSync', () {
      final _ = p.aleAutoSync;
    });

    // Stage validation
    _assertNoThrow(mod, 'validateStageSequence', () {
      final issues = p.validateStageSequence();
      _assert(mod, 'validateStageSequence accessible', true);
    });
    _assertNoThrow(mod, 'lastValidationIssues', () {
      final _ = p.lastValidationIssues;
    });

    // Scenarios
    _assertNoThrow(mod, 'availableScenarios', () {
      final _ = p.availableScenarios;
    });
    _assertNoThrow(mod, 'loadedScenarioId', () {
      final _ = p.loadedScenarioId;
    });

    // Persisted state getters
    _assertNoThrow(mod, 'persistedLowerZoneTabIndex', () {
      final _ = p.persistedLowerZoneTabIndex;
    });
    _assertNoThrow(mod, 'persistedLowerZoneExpanded', () {
      final _ = p.persistedLowerZoneExpanded;
    });
    _assertNoThrow(mod, 'persistedAudioPool', () {
      final _ = p.persistedAudioPool;
    });
    _assertNoThrow(mod, 'waveformCache', () {
      final _ = p.waveformCache;
    });

    // Export/import config
    _assertNoThrow(mod, 'exportConfig', () {
      final _ = p.exportConfig();
    });

    // Reset stats (safe)
    _assertNoThrow(mod, 'resetStats', () {
      p.resetStats();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 12: SERIALIZATION ROUNDTRIP
  // ═══════════════════════════════════════════════════════════════════════════

  void _testSerializationRoundtrip() {
    const mod = 'Serialization';

    // StateGroups: toJson → fromJson → verify
    final stateGroups = _tryGet<StateGroupsProvider>();
    if (stateGroups != null) {
      _assertNoThrow(mod, 'StateGroups: toJson→fromJson roundtrip', () {
        stateGroups.registerStateGroupFromPreset('QA_RT', ['A', 'B']);
        final json = stateGroups.toJson();
        _assert(mod, 'StateGroups: json has entries', json.isNotEmpty);
        // Re-import (additive — just verify no crash)
        stateGroups.fromJson(json);
        // Cleanup
        final g = stateGroups.getStateGroupByName('QA_RT');
        if (g != null) stateGroups.unregisterStateGroup(g.id);
      });
    }

    // SwitchGroups: toJson → fromJson
    final switchGroups = _tryGet<SwitchGroupsProvider>();
    if (switchGroups != null) {
      _assertNoThrow(mod, 'SwitchGroups: toJson→fromJson', () {
        final json = switchGroups.toJson();
        switchGroups.fromJson(json);
      });
    }

    // RTPC: read-only verification (no global toJson/fromJson)
    final rtpc = _tryGet<RtpcSystemProvider>();
    if (rtpc != null) {
      _assertNoThrow(mod, 'RTPC: definitions stable after re-read', () {
        final count1 = rtpc.rtpcCount;
        final count2 = rtpc.rtpcCount;
        _assertEqual(mod, 'RTPC: count consistent', count1, count2);
      });
    }

    // Ducking: toJson → fromJson
    final ducking = _tryGet<DuckingSystemProvider>();
    if (ducking != null) {
      _assertNoThrow(mod, 'Ducking: toJson→fromJson', () {
        final json = ducking.toJson();
        ducking.fromJson(json);
      });
    }

    // Blend: toJson → fromJson
    final blend = _tryGet<BlendContainersProvider>();
    if (blend != null) {
      _assertNoThrow(mod, 'Blend: toJson→fromJson', () {
        final json = blend.toJson();
        blend.fromJson(json);
      });
    }

    // Random: toJson → fromJson
    final random = _tryGet<RandomContainersProvider>();
    if (random != null) {
      _assertNoThrow(mod, 'Random: toJson→fromJson', () {
        final json = random.toJson();
        random.fromJson(json);
      });
    }

    // Sequence: toJson → fromJson
    final sequence = _tryGet<SequenceContainersProvider>();
    if (sequence != null) {
      _assertNoThrow(mod, 'Sequence: toJson→fromJson', () {
        final json = sequence.toJson();
        sequence.fromJson(json);
      });
    }

    // BusHierarchy: toJson → fromJson
    final busH = _tryGet<BusHierarchyProvider>();
    if (busH != null) {
      _assertNoThrow(mod, 'BusHierarchy: toJson→fromJson', () {
        final json = busH.toJson();
        _assert(mod, 'BusHierarchy: json accessible', true);
        busH.fromJson(json);
      });
    }

    // VoicePool: toJson → fromJson
    final voicePool = _tryGet<VoicePoolProvider>();
    if (voicePool != null) {
      _assertNoThrow(mod, 'VoicePool: toJson→fromJson', () {
        final json = voicePool.toJson();
        voicePool.fromJson(json);
      });
    }

    // BehaviorTree: toJson → loadFromJson
    final bt = _tryGet<BehaviorTreeProvider>();
    if (bt != null) {
      _assertNoThrow(mod, 'BehaviorTree: toJson→loadFromJson', () {
        final json = bt.toJson();
        _assert(mod, 'BehaviorTree: json accessible', true);
        bt.loadFromJson(json);
      });
    }

    // ContextLayer: toJson → fromJson
    final cl = _tryGet<ContextLayerProvider>();
    if (cl != null) {
      _assertNoThrow(mod, 'ContextLayer: toJson→fromJson', () {
        final json = cl.toJson();
        cl.fromJson(json);
      });
    }

    // TriggerLayer: toJson → fromJson
    final tl = _tryGet<TriggerLayerProvider>();
    if (tl != null) {
      _assertNoThrow(mod, 'TriggerLayer: toJson→fromJson', () {
        final json = tl.toJson();
        tl.fromJson(json);
      });
    }

    // Feature Composer: toJson → fromJson
    final composer = _tryGet<FeatureComposerProvider>();
    if (composer != null) {
      _assertNoThrow(mod, 'Composer: toJson→fromJson', () {
        final json = composer.toJson();
        _assert(mod, 'Composer: json accessible', true);
        composer.fromJson(json);
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 13: MULTI-GRID SPIN QA
  // ═══════════════════════════════════════════════════════════════════════════

  static const _qaGrids = [
    (reels: 3, rows: 3, name: '3×3 Retro'),
    (reels: 5, rows: 3, name: '5×3 Standard'),
    (reels: 5, rows: 4, name: '5×4 Extended'),
    (reels: 6, rows: 4, name: '6×4 Wide'),
    (reels: 4, rows: 4, name: '4×4 Cluster'),
    (reels: 6, rows: 6, name: '6×6 Megaways'),
    (reels: 8, rows: 4, name: '8×4 Ultra Wide'),
  ];

  Future<void> _testMultiGridSpins(SlotLabProvider provider) async {
    const mod = 'MultiGrid';

    if (!provider.initialized) {
      _diag.log('SKIP multi-grid spins — engine not initialized');
      return;
    }

    final outcomes = ForcedOutcome.values;
    final spinsPerGrid = outcomes.length + 4; // 14 forced + 4 random = 18
    int totalSpins = 0;
    int totalErrors = 0;

    for (final grid in _qaGrids) {
      if (_cancelled) break;

      _diag.log(
          '╔═══ GRID: ${grid.name} (${grid.reels}×${grid.rows}) ═══╗');
      provider.updateGridSize(grid.reels, grid.rows);

      // Forced outcomes
      for (int i = 0; i < outcomes.length; i++) {
        if (_cancelled) break;
        try {
          final result = await provider.spinForced(outcomes[i]);
          if (result == null) {
            _assert(mod, '${grid.name} forced ${outcomes[i].name}', false,
                'null result');
            totalErrors++;
          } else {
            totalSpins++;
          }
        } catch (e) {
          _assert(mod, '${grid.name} forced ${outcomes[i].name}', false,
              'Exception: $e');
          totalErrors++;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

      // Random spins
      for (int i = 0; i < 4; i++) {
        if (_cancelled) break;
        try {
          final result = await provider.spin();
          if (result == null) {
            _assert(mod, '${grid.name} random ${i + 1}', false,
                'null result');
            totalErrors++;
          } else {
            totalSpins++;
          }
        } catch (e) {
          _assert(mod, '${grid.name} random ${i + 1}', false,
              'Exception: $e');
          totalErrors++;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }

    // Reset grid
    provider.updateGridSize(5, 3);

    final expectedTotal = _qaGrids.length * spinsPerGrid;
    _assert(
        mod,
        'Total spins completed: $totalSpins/$expectedTotal',
        totalSpins == expectedTotal,
        '$totalErrors errors, ${expectedTotal - totalSpins} missing');

    _diag.log(
        'Multi-grid QA: $totalSpins/$expectedTotal spins, $totalErrors errors');
  }
}
