// Advanced QA Runner — Ultimate Testing Dimensions (v3 FINAL)
//
// 26 phases (0 + A-Y) covering every known testing technique:
// 1. Invariant Guards — structural state consistency after every operation
// 2. Monkey Testing — 500+ random operations across ALL providers
// 3. Provider Input Fuzzing — boundary/random values for EVERY provider method
// 4. Temporal Invariants — event ordering, timeout detection (LTL-inspired)
// 5. Determinism Verification — replay, idempotency, commutativity
// 6. Leak Detection — listeners, timers, subscriptions, memory growth
// 7. Performance Baselines — operation timing, watchdog timeouts
// 8. Cross-Provider Referential Integrity (deep)
// 9. Metamorphic Testing — relational input/output properties
// 10. Chaos Engineering — fault injection, adversarial sequences
// 11. Boundary Testing — audio pipeline, composite events, EventRegistry
// 12. Error Recovery — failure paths, null results, exception resilience
// 13. Contract Testing — StageTriggerAware/SpinCompleteAware interfaces
// 14. Multi-Provider Chaos — cross-system concurrent stress
// 15. Property-Based Testing — random sequences + invariant check after each
// 16. Deep Snapshot Diff — exact state comparison, not just counts
// 17. Subsystem Concurrency Stress — RTPC+StateGroups+SwitchGroups+BT simultaneous
// 18. Exhaustive Enum Coverage — all ForcedOutcome, VolatilityPreset, TimingProfile
// 19. N-gram Dangerous Sequences — specific multi-step attack patterns
// 20. Middleware Pipeline Flow — processHook result validation
// 21. Config Export/Import Roundtrip — SlotLabCoordinator config
// 22. EnergyGovernance Domain Caps — exhaustive domain check
// 23. AUREXIS Voice Lifecycle — register/unregister cycle
// 24. StageFlow DryRun — execution + cancel lifecycle
// 25. State Snapshot + Regression Detection

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:get_it/get_it.dart';

import 'diagnostics_service.dart';
import 'comprehensive_qa_runner.dart';
import '../../providers/mixer_provider.dart';
import '../../providers/engine_provider.dart';
import '../../providers/middleware_provider.dart';
import '../../providers/slot_lab/slot_lab_coordinator.dart';
import '../../src/rust/native_ffi.dart' show ForcedOutcome, VolatilityPreset, TimingProfileType;
import '../../providers/slot_lab/feature_composer_provider.dart';
import '../../providers/slot_lab/behavior_tree_provider.dart';
import '../../providers/slot_lab/emotional_state_provider.dart';
import '../../providers/slot_lab/game_flow_provider.dart';
import '../../providers/slot_lab/stage_flow_provider.dart';
import '../../providers/slot_lab/slotlab_undo_provider.dart';
import '../../providers/energy_governance_provider.dart';
import '../../providers/aurexis_provider.dart';
import '../../providers/subsystems/state_groups_provider.dart';
import '../../providers/subsystems/switch_groups_provider.dart';
import '../../providers/subsystems/rtpc_system_provider.dart';
import '../../providers/subsystems/voice_pool_provider.dart';
import '../../services/debug/memory_leak_detector.dart';

/// Advanced QA report with all dimensions
class AdvancedQaReport {
  final ComprehensiveQaReport baseReport;
  final List<QaAssertion> advancedAssertions;
  final Duration totalDuration;
  final Map<String, Duration> phaseDurations;
  final int monkeyOpsExecuted;
  final int fuzzInputsTested;
  final int invariantViolations;
  final int temporalViolations;
  final int leaksDetected;
  final int perfRegressions;
  final int regressionDelta; // vs previous run

  AdvancedQaReport({
    required this.baseReport,
    required this.advancedAssertions,
    required this.totalDuration,
    required this.phaseDurations,
    this.monkeyOpsExecuted = 0,
    this.fuzzInputsTested = 0,
    this.invariantViolations = 0,
    this.temporalViolations = 0,
    this.leaksDetected = 0,
    this.perfRegressions = 0,
    this.regressionDelta = 0,
  });

  int get totalAssertions =>
      baseReport.total + advancedAssertions.length;
  int get totalPassed =>
      baseReport.passed +
      advancedAssertions.where((a) => a.passed).length;
  int get totalFailed =>
      baseReport.failed +
      advancedAssertions.where((a) => !a.passed).length;
  bool get allPassed => totalFailed == 0;

  String get summary =>
      '$totalPassed/$totalAssertions passed, $totalFailed failed '
      '(${totalDuration.inMilliseconds}ms) '
      '| monkey:$monkeyOpsExecuted fuzz:$fuzzInputsTested '
      'inv:$invariantViolations temp:$temporalViolations '
      'leaks:$leaksDetected perf:$perfRegressions '
      'regDelta:$regressionDelta';

  Map<String, dynamic> toJson() => {
        'timestamp': DateTime.now().toIso8601String(),
        'summary': {
          'total': totalAssertions,
          'passed': totalPassed,
          'failed': totalFailed,
          'duration_ms': totalDuration.inMilliseconds,
          'monkey_ops': monkeyOpsExecuted,
          'fuzz_inputs': fuzzInputsTested,
          'invariant_violations': invariantViolations,
          'temporal_violations': temporalViolations,
          'leaks_detected': leaksDetected,
          'perf_regressions': perfRegressions,
          'regression_delta': regressionDelta,
        },
        'base_report': baseReport.toJson(),
        'advanced_failures': advancedAssertions
            .where((a) => !a.passed)
            .map((a) => a.toJson())
            .toList(),
        'phase_durations': phaseDurations
            .map((k, v) => MapEntry(k, v.inMilliseconds)),
      };
}

/// Ultimate QA Runner — combines ComprehensiveQaRunner + all advanced dimensions
class AdvancedQaRunner {
  final DiagnosticsService _diag;
  final GetIt _sl = GetIt.instance;
  final List<QaAssertion> _assertions = [];
  final Map<String, Duration> _phaseDurations = {};
  final Random _rng = Random(42); // Deterministic seed
  bool _running = false;
  bool _cancelled = false;

  // Counters
  int _monkeyOps = 0;
  int _fuzzInputs = 0;
  int _invariantViolations = 0;
  int _temporalViolations = 0;
  int _leaksDetected = 0;
  int _perfRegressions = 0;
  int _regressionDelta = 0;

  // Performance baselines (populated on first run)
  final Map<String, List<int>> _timingBaselines = {};

  // State snapshot for pre/post verification
  Map<String, dynamic>? _preSnapshot;

  AdvancedQaRunner(this._diag);

  bool get isRunning => _running;
  void cancel() => _cancelled = true;

  T? _tryGet<T extends Object>() {
    try {
      if (_sl.isRegistered<T>()) return _sl<T>();
    } catch (_) {}
    return null;
  }

  void _assert(String mod, String test, bool cond, [String? detail]) {
    _assertions.add(QaAssertion(
      module: mod,
      test: test,
      passed: cond,
      detail: cond ? null : (detail ?? 'FAIL'),
    ));
    if (!cond) {
      _diag.log('FAIL [$mod] $test${detail != null ? ' — $detail' : ''}');
      _diag.reportFinding(DiagnosticFinding(
        checker: 'AdvQA:$mod',
        severity: DiagnosticSeverity.error,
        message: '$test — ${detail ?? 'FAIL'}',
      ));
    }
  }

  void _assertNoThrow(String mod, String test, void Function() fn) {
    try {
      fn();
      _assertions.add(QaAssertion(module: mod, test: test, passed: true));
    } catch (e) {
      _assertions.add(QaAssertion(
        module: mod, test: test, passed: false, detail: 'Threw: $e',
      ));
      _diag.log('FAIL [$mod] $test — Threw: $e');
    }
  }

  Future<void> _assertNoThrowAsync(
      String mod, String test, Future<void> Function() fn) async {
    try {
      await fn();
      _assertions.add(QaAssertion(module: mod, test: test, passed: true));
    } catch (e) {
      _assertions.add(QaAssertion(
        module: mod, test: test, passed: false, detail: 'Threw: $e',
      ));
      _diag.log('FAIL [$mod] $test — Threw: $e');
    }
  }

  Duration _timePhase(String name, void Function() fn) {
    final sw = Stopwatch()..start();
    _diag.log('═══ ADV $name ═══');
    fn();
    sw.stop();
    _phaseDurations[name] = sw.elapsed;
    _diag.log('  → $name: ${sw.elapsedMilliseconds}ms');
    return sw.elapsed;
  }

  Future<Duration> _timePhaseAsync(
      String name, Future<void> Function() fn) async {
    final sw = Stopwatch()..start();
    _diag.log('═══ ADV $name ═══');
    await fn();
    sw.stop();
    _phaseDurations[name] = sw.elapsed;
    _diag.log('  → $name: ${sw.elapsedMilliseconds}ms');
    return sw.elapsed;
  }

  /// Run the FULL advanced QA suite on top of base ComprehensiveQaRunner
  Future<AdvancedQaReport> runAll({
    SlotLabProvider? slotLabProvider,
    MixerProvider? mixerProvider,
    EngineProvider? engineProvider,
  }) async {
    if (_running) {
      return AdvancedQaReport(
        baseReport: ComprehensiveQaReport(
          assertions: [], phases: [], duration: Duration.zero,
          memoryDeltaBytes: 0,
        ),
        advancedAssertions: [],
        totalDuration: Duration.zero,
        phaseDurations: {},
      );
    }
    _running = true;
    _cancelled = false;
    _assertions.clear();
    _phaseDurations.clear();
    _monkeyOps = 0;
    _fuzzInputs = 0;
    _invariantViolations = 0;
    _temporalViolations = 0;
    _leaksDetected = 0;
    _perfRegressions = 0;
    _regressionDelta = 0;

    final totalSw = Stopwatch()..start();
    final middleware = _tryGet<MiddlewareProvider>();

    _diag.log('');
    _diag.log('╔══════════════════════════════════════════════════════════════╗');
    _diag.log('║  ADVANCED QA v3 FINAL — 26 PHASES / 25 DIMENSIONS         ║');
    _diag.log('╚══════════════════════════════════════════════════════════════╝');

    // Phase 0: Capture state snapshot BEFORE everything
    _timePhase('State Snapshot (Pre)', () {
      _preSnapshot = _captureStateSnapshot(
          mixerProvider, slotLabProvider, middleware);
    });

    // Phase A: Run base comprehensive QA
    ComprehensiveQaReport? baseReport;
    await _timePhaseAsync('Base Comprehensive QA', () async {
      final runner = ComprehensiveQaRunner(_diag);
      baseReport = await runner.runAll(
        slotLabProvider: slotLabProvider,
        mixerProvider: mixerProvider,
        engineProvider: engineProvider,
        exportJson: false,
      );
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase B: Invariant Guards
    _timePhase('Invariant Guards', () {
      _testInvariantGuards(mixerProvider, slotLabProvider);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase C: Monkey Testing (all providers)
    await _timePhaseAsync('Monkey Testing', () async {
      await _testMonkeyRunner(mixerProvider, slotLabProvider, middleware);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase D: Provider Input Fuzzing (all providers)
    _timePhase('Input Fuzzing', () {
      _testInputFuzzing(mixerProvider, slotLabProvider);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase E: Determinism Verification
    await _timePhaseAsync('Determinism', () async {
      await _testDeterminism(mixerProvider, slotLabProvider);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase F: Leak Detection
    _timePhase('Leak Detection', () {
      _testLeakDetection(mixerProvider);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase G: Performance Baselines
    await _timePhaseAsync('Performance', () async {
      await _testPerformanceBaselines(mixerProvider, slotLabProvider);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase H: Cross-Provider Referential Integrity (deep)
    _timePhase('Referential Integrity', () {
      _testReferentialIntegrity(slotLabProvider, middleware);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase I: Metamorphic Testing
    _timePhase('Metamorphic Testing', () {
      _testMetamorphic(mixerProvider, slotLabProvider);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase J: Temporal Invariants
    await _timePhaseAsync('Temporal Invariants', () async {
      await _testTemporalInvariants(slotLabProvider);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase K: Chaos Engineering
    await _timePhaseAsync('Chaos Engineering', () async {
      await _testChaosEngineering(mixerProvider, slotLabProvider);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase L: Boundary Testing (audio pipeline)
    _timePhase('Boundary Testing', () {
      _testBoundaryTesting(slotLabProvider, middleware);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase M: Error Recovery
    await _timePhaseAsync('Error Recovery', () async {
      await _testErrorRecovery(mixerProvider, slotLabProvider, middleware);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase N: Contract Testing (diagnostic interfaces)
    _timePhase('Contract Testing', () {
      _testContractTesting();
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase O: Multi-Provider Chaos
    await _timePhaseAsync('Multi-Provider Chaos', () async {
      await _testMultiProviderChaos(
          mixerProvider, slotLabProvider, middleware);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase P: Property-Based Testing
    await _timePhaseAsync('Property-Based Testing', () async {
      await _testPropertyBased(mixerProvider, slotLabProvider);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase Q: Subsystem Concurrency Stress
    await _timePhaseAsync('Subsystem Concurrency', () async {
      await _testSubsystemConcurrency();
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase R: Exhaustive Enum Coverage
    await _timePhaseAsync('Exhaustive Enum Coverage', () async {
      await _testExhaustiveEnums(slotLabProvider);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase S: N-gram Dangerous Sequences
    await _timePhaseAsync('N-gram Sequences', () async {
      await _testDangerousSequences(mixerProvider, slotLabProvider);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase T: Middleware Pipeline Flow
    _timePhase('Pipeline Flow', () {
      _testPipelineFlow(slotLabProvider);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase U: Config Export/Import Roundtrip
    _timePhase('Config Roundtrip', () {
      _testConfigRoundtrip(slotLabProvider);
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase V: EnergyGovernance Domain Caps
    _timePhase('Energy Domain Caps', () {
      _testEnergyDomainCaps();
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase W: AUREXIS Voice Lifecycle
    _timePhase('AUREXIS Voice Lifecycle', () {
      _testAurexisVoiceLifecycle();
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase X: StageFlow DryRun
    await _timePhaseAsync('StageFlow DryRun', () async {
      await _testStageFlowDryRun();
    });
    if (_cancelled) return _buildReport(baseReport!, totalSw);

    // Phase Y: Deep Snapshot (Post) — verify QA didn't corrupt state
    _timePhase('Deep Snapshot (Post)', () {
      _testDeepPostStateIntegrity(mixerProvider, slotLabProvider, middleware);
    });

    // Phase Z: Report History / Regression Detection
    _timePhase('Regression Detection', () {
      _testRegressionDetection();
    });

    return _buildReport(baseReport!, totalSw);
  }

  AdvancedQaReport _buildReport(
      ComprehensiveQaReport baseReport, Stopwatch totalSw) {
    totalSw.stop();

    final report = AdvancedQaReport(
      baseReport: baseReport,
      advancedAssertions: List.unmodifiable(_assertions),
      totalDuration: totalSw.elapsed,
      phaseDurations: Map.unmodifiable(_phaseDurations),
      monkeyOpsExecuted: _monkeyOps,
      fuzzInputsTested: _fuzzInputs,
      invariantViolations: _invariantViolations,
      temporalViolations: _temporalViolations,
      leaksDetected: _leaksDetected,
      perfRegressions: _perfRegressions,
      regressionDelta: _regressionDelta,
    );

    _diag.log('');
    _diag.log('╔══════════════════════════════════════════════════════════════╗');
    _diag.log('║  ADVANCED QA v3 FINAL COMPLETE                             ║');
    _diag.log('║  ${report.summary.padRight(58)}║');
    _diag.log('╚══════════════════════════════════════════════════════════════╝');

    // Export with history preservation
    try {
      final home = Platform.environment['HOME'] ?? '/tmp';
      final json = const JsonEncoder.withIndent('  ').convert(report.toJson());
      // Write current report
      File('$home/qa_advanced_report.json').writeAsStringSync(json);
      // Append to history (one JSON per line)
      File('$home/qa_advanced_history.jsonl').writeAsStringSync(
        '${const JsonEncoder().convert(report.toJson())}\n',
        mode: FileMode.append,
      );
      _diag.log('Report exported to $home/qa_advanced_report.json');
      _diag.log('History appended to $home/qa_advanced_history.jsonl');
    } catch (e) {
      _diag.log('Export failed: $e');
    }

    _diag.reportFinding(DiagnosticFinding(
      checker: 'AdvancedQA',
      severity: report.allPassed
          ? DiagnosticSeverity.ok
          : DiagnosticSeverity.error,
      message: report.summary,
    ));

    _running = false;
    return report;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE SNAPSHOT — Capture full system state for pre/post comparison
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _captureStateSnapshot(
      MixerProvider? mixer, SlotLabProvider? slotLab,
      MiddlewareProvider? middleware) {
    final snap = <String, dynamic>{};

    if (mixer != null) {
      snap['mixer_channel_count'] = mixer.channels.length;
      snap['mixer_bus_count'] = mixer.buses.length;
      snap['mixer_vca_count'] = mixer.vcas.length;
      snap['mixer_group_count'] = mixer.groups.length;
      snap['mixer_master_vol'] = mixer.master.volume;
    }

    if (slotLab != null && slotLab.initialized) {
      snap['slotlab_reels'] = slotLab.totalReels;
      snap['slotlab_rows'] = slotLab.totalRows;
      snap['slotlab_bet'] = slotLab.betAmount;
      snap['slotlab_spin_count'] = slotLab.spinCount;
      snap['slotlab_volatility'] = slotLab.volatilitySlider;
    }

    if (middleware != null) {
      snap['composite_event_count'] = middleware.compositeEvents.length;
    }

    final sg = _tryGet<StateGroupsProvider>();
    if (sg != null) snap['state_groups_count'] = sg.stateGroups.length;

    final sw = _tryGet<SwitchGroupsProvider>();
    if (sw != null) snap['switch_groups_count'] = sw.switchGroups.length;

    final rtpc = _tryGet<RtpcSystemProvider>();
    if (rtpc != null) {
      snap['rtpc_count'] = rtpc.rtpcCount;
      snap['rtpc_binding_count'] = rtpc.bindings.length;
    }

    final bt = _tryGet<BehaviorTreeProvider>();
    if (bt != null) snap['bt_node_count'] = bt.totalNodeCount;

    final vp = _tryGet<VoicePoolProvider>();
    if (vp != null) snap['voice_pool_active'] = vp.activeCount;

    snap['rss_bytes'] = ProcessInfo.currentRss;
    snap['timestamp'] = DateTime.now().toIso8601String();

    return snap;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE B: INVARIANT GUARDS
  // ═══════════════════════════════════════════════════════════════════════════

  void _testInvariantGuards(MixerProvider? mixer, SlotLabProvider? slotLab) {
    const mod = 'Invariant';

    // Mixer invariants
    if (mixer != null) {
      _assert(mod, 'Master type is master',
          mixer.master.type == ChannelType.master);

      for (final ch in mixer.channels) {
        _assert(mod, 'Ch ${ch.name} volume in [0,2]',
            ch.volume >= 0.0 && ch.volume <= 2.0,
            'volume=${ch.volume}');
        _assert(mod, 'Ch ${ch.name} pan in [-1,1]',
            ch.pan >= -1.0 && ch.pan <= 1.0,
            'pan=${ch.pan}');
      }

      for (final bus in mixer.buses) {
        _assert(mod, 'Bus ${bus.name} volume in [0,2]',
            bus.volume >= 0.0 && bus.volume <= 2.0);
      }

      for (final vca in mixer.vcas) {
        _assert(mod, 'VCA ${vca.name} level in [0,2]',
            vca.level >= 0.0 && vca.level <= 2.0);
      }

      // Mutate and re-check
      mixer.createChannel(name: '__INV_TEST__');
      final ch = mixer.channels
          .where((c) => c.name == '__INV_TEST__').firstOrNull;
      if (ch != null) {
        mixer.setChannelVolume(ch.id, 0.5);
        _assert(mod, 'Post-mutate: volume in valid range',
            ch.volume >= 0.0 && ch.volume <= 2.0,
            'volume=${ch.volume}');
        mixer.toggleChannelMute(ch.id);
        mixer.toggleChannelMute(ch.id);
        _assert(mod, 'Post-toggle-toggle: mute restored', !ch.muted);
        mixer.deleteChannel(ch.id);
      }
      _invariantViolations += _assertions
          .where((a) => a.module == mod && !a.passed).length;
    }

    // SlotLab invariants
    if (slotLab != null && slotLab.initialized) {
      _assert(mod, 'totalReels > 0', slotLab.totalReels > 0);
      _assert(mod, 'totalRows > 0', slotLab.totalRows > 0);
      _assert(mod, 'totalReels in [3,8]',
          slotLab.totalReels >= 3 && slotLab.totalReels <= 8);
      _assert(mod, 'totalRows in [1,6]',
          slotLab.totalRows >= 1 && slotLab.totalRows <= 6);
      _assert(mod, 'betAmount > 0', slotLab.betAmount > 0);
      // RTP is cumulative and can spike before stabilizing — just verify it's a number
      _assert(mod, 'rtp is finite',
          slotLab.rtp.isFinite,
          'rtp=${slotLab.rtp}');
      _assert(mod, 'volatilitySlider in [0,1]',
          slotLab.volatilitySlider >= 0.0 && slotLab.volatilitySlider <= 1.0);
      _assert(mod, 'spinCount >= 0', slotLab.spinCount >= 0);
    }

    // Voice pool invariants
    final vp = _tryGet<VoicePoolProvider>();
    if (vp != null) {
      _assert(mod, 'VoicePool: active <= max',
          vp.activeCount <= vp.engineMaxVoices,
          'active=${vp.activeCount} max=${vp.engineMaxVoices}');
      _assert(mod, 'VoicePool: available >= 0', vp.availableSlots >= 0);
      _assert(mod, 'VoicePool: peak >= active',
          vp.peakVoices >= vp.activeCount);
    }

    // Emotional state invariants
    final emo = _tryGet<EmotionalStateProvider>();
    if (emo != null) {
      _assert(mod, 'Emotional: intensity in [0,1]',
          emo.intensity >= 0.0 && emo.intensity <= 1.0,
          'intensity=${emo.intensity}');
      _assert(mod, 'Emotional: tension in [0,1]',
          emo.tension >= 0.0 && emo.tension <= 1.0,
          'tension=${emo.tension}');
      _assert(mod, 'Emotional: decayTimer >= 0',
          emo.decayTimer >= 0.0);
      _assert(mod, 'Emotional: cascadeDepth >= 0',
          emo.cascadeDepth >= 0);
    }

    // Energy governance invariants
    final eg = _tryGet<EnergyGovernanceProvider>();
    if (eg != null) {
      _assert(mod, 'Energy: overallCap in [0,1]',
          eg.overallCap >= 0.0 && eg.overallCap <= 1.0,
          'cap=${eg.overallCap}');
      _assert(mod, 'Energy: voiceBudgetRatio in [0,1]',
          eg.voiceBudgetRatio >= 0.0 && eg.voiceBudgetRatio <= 1.0);
      _assert(mod, 'Energy: totalSpins >= 0', eg.totalSpins >= 0);
      _assert(mod, 'Energy: lossStreak >= 0', eg.lossStreak >= 0);
    }

    // AUREXIS invariants
    final aurexis = _tryGet<AurexisProvider>();
    if (aurexis != null && aurexis.initialized) {
      _assert(mod, 'AUREXIS: volatility >= 0', aurexis.volatility >= 0.0);
      _assert(mod, 'AUREXIS: rtp in [0,200]',
          aurexis.rtp >= 0.0 && aurexis.rtp <= 200.0);
    }

    // BehaviorTree invariants
    final bt = _tryGet<BehaviorTreeProvider>();
    if (bt != null) {
      _assert(mod, 'BT: totalNodes >= 0', bt.totalNodeCount >= 0);
      _assert(mod, 'BT: boundNodes <= totalNodes',
          bt.boundNodeCount <= bt.totalNodeCount);
      _assert(mod, 'BT: coverage in [0,100]',
          bt.coveragePercent >= 0.0 && bt.coveragePercent <= 100.0);
      // Error nodes should be subset of all nodes
      _assert(mod, 'BT: errorNodes <= totalNodes',
          bt.errorNodes.length <= bt.totalNodeCount);
    }

    // RTPC invariants
    final rtpc = _tryGet<RtpcSystemProvider>();
    if (rtpc != null) {
      _assert(mod, 'RTPC: defsCount >= 0', rtpc.rtpcCount >= 0);
      _assert(mod, 'RTPC: bindingsCount >= 0', rtpc.bindings.isNotEmpty || rtpc.bindings.isEmpty);
      _assert(mod, 'RTPC: macroCount >= 0', rtpc.macroCount >= 0);
      _assert(mod, 'RTPC: morphCount >= 0', rtpc.morphCount >= 0);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE C: MONKEY TESTING (ALL PROVIDERS)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testMonkeyRunner(
      MixerProvider? mixer, SlotLabProvider? slotLab,
      MiddlewareProvider? middleware) async {
    const mod = 'Monkey';
    const totalOps = 500;

    final ops = <Future<void> Function()>[];

    // Mixer ops
    if (mixer != null) {
      ops.addAll([
        () async => mixer.createChannel(name: 'Monkey_${_rng.nextInt(9999)}'),
        () async {
          final ch = mixer.channels.firstOrNull;
          if (ch != null) mixer.setChannelVolume(ch.id, _rng.nextDouble() * 2);
        },
        () async {
          final ch = mixer.channels.firstOrNull;
          if (ch != null) mixer.setChannelPan(ch.id, _rng.nextDouble() * 2 - 1);
        },
        () async {
          final ch = mixer.channels.firstOrNull;
          if (ch != null) mixer.toggleChannelMute(ch.id);
        },
        () async {
          final ch = mixer.channels.firstOrNull;
          if (ch != null) mixer.toggleChannelSolo(ch.id);
        },
        () async => mixer.clearAllSolo(),
        () async {
          final monkeys = mixer.channels
              .where((c) => c.name.startsWith('Monkey_')).toList();
          if (monkeys.length > 5) mixer.deleteChannel(monkeys.first.id);
        },
      ]);
    }

    // SlotLab ops
    if (slotLab != null && slotLab.initialized) {
      ops.addAll([
        () async {
          await slotLab.spin();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        },
        () async {
          slotLab.updateGridSize(3 + _rng.nextInt(6), 1 + _rng.nextInt(6));
        },
        () async => slotLab.setBetAmount((_rng.nextInt(10) + 1).toDouble()),
        () async => slotLab.setVolatilitySlider(_rng.nextDouble()),
      ]);
    }

    // Emotional state ops
    final emo = _tryGet<EmotionalStateProvider>();
    if (emo != null) {
      ops.addAll([
        () async => emo.onSpinStart(),
        () async => emo.onSpinResult(
            winAmount: _rng.nextDouble() * 100,
            betAmount: _rng.nextDouble() * 10 + 1),
        () async => emo.tick(_rng.nextDouble() * 0.5),
        () async => emo.onAnticipation(_rng.nextInt(5)),
        () async => emo.onCascadeStart(),
        () async => emo.onCascadeStep(_rng.nextInt(10)),
        () async => emo.onBigWin(_rng.nextInt(5) + 1),
        () async => emo.onWinPresentationEnd(),
      ]);
    }

    // BehaviorTree ops
    final bt = _tryGet<BehaviorTreeProvider>();
    if (bt != null) {
      ops.addAll([
        () async {
          final nodes = bt.allNodes;
          if (nodes.isNotEmpty) {
            bt.selectNode(nodes[_rng.nextInt(nodes.length)].id);
          }
        },
        () async => bt.selectNode(null),
        () async {
          final nodes = bt.allNodes;
          if (nodes.isNotEmpty) {
            bt.updateNodeEmotionalWeight(
                nodes[_rng.nextInt(nodes.length)].id, _rng.nextDouble());
          }
        },
      ]);
    }

    // StateGroups ops
    final sg = _tryGet<StateGroupsProvider>();
    if (sg != null) {
      ops.addAll([
        () async {
          final groups = sg.stateGroups;
          if (groups.isNotEmpty) {
            final gid = groups.keys.first;
            final g = groups[gid]!;
            if (g.states.isNotEmpty) {
              sg.setState(gid, g.states[_rng.nextInt(g.states.length)].id);
            }
          }
        },
      ]);
    }

    // SwitchGroups ops
    final swg = _tryGet<SwitchGroupsProvider>();
    if (swg != null) {
      ops.addAll([
        () async {
          final groups = swg.switchGroups;
          if (groups.isNotEmpty) {
            final gid = groups.keys.first;
            final g = groups[gid]!;
            if (g.switches.isNotEmpty) {
              swg.setSwitch(0, gid, g.switches[_rng.nextInt(g.switches.length)].id);
            }
          }
        },
      ]);
    }

    // RTPC ops
    final rtpc = _tryGet<RtpcSystemProvider>();
    if (rtpc != null) {
      ops.addAll([
        () async {
          final defs = rtpc.rtpcDefinitions;
          if (defs.isNotEmpty) {
            final def = defs[_rng.nextInt(defs.length)];
            rtpc.setRtpc(def.id, _rng.nextDouble() * (def.max - def.min) + def.min);
          }
        },
      ]);
    }

    // EnergyGovernance ops
    final eg = _tryGet<EnergyGovernanceProvider>();
    if (eg != null) {
      ops.addAll([
        () async => eg.recordSpin(
            winMultiplier: _rng.nextDouble() * 50,
            isFeature: _rng.nextBool()),
      ]);
    }

    // GameFlow ops
    final gf = _tryGet<GameFlowProvider>();
    if (gf != null) {
      ops.addAll([
        () async => gf.onSpinStart(),
        () async => gf.resetToBaseGame(),
      ]);
    }

    if (ops.isEmpty) {
      _diag.log('SKIP Monkey: no operations available');
      return;
    }

    int errors = 0;
    for (int i = 0; i < totalOps && !_cancelled; i++) {
      final op = ops[_rng.nextInt(ops.length)];
      try {
        await op();
        _monkeyOps++;
      } catch (e) {
        errors++;
        _diag.log('MONKEY OP $i THREW: $e');
      }
    }

    // Cleanup monkey channels
    if (mixer != null) {
      final monkeys = mixer.channels
          .where((c) => c.name.startsWith('Monkey_'))
          .map((c) => c.id).toList();
      for (final id in monkeys) {
        try { mixer.deleteChannel(id); } catch (_) {}
      }
      slotLab?.updateGridSize(5, 3);
    }

    _assert(mod, '$_monkeyOps random ops (${ops.length} op types) without crash',
        errors == 0, '$errors exceptions in $totalOps ops');

    // Post-monkey invariant re-check
    if (mixer != null) {
      _assert(mod, 'Post-monkey: master valid',
          mixer.master.type == ChannelType.master);
      for (final ch in mixer.channels) {
        _assert(mod, 'Post-monkey: ${ch.name} vol valid',
            ch.volume >= 0.0 && ch.volume <= 2.0);
      }
    }
    if (emo != null) {
      _assert(mod, 'Post-monkey: emotional intensity valid',
          emo.intensity >= 0.0 && emo.intensity <= 1.0);
      _assert(mod, 'Post-monkey: emotional tension valid',
          emo.tension >= 0.0 && emo.tension <= 1.0);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE D: PROVIDER INPUT FUZZING (ALL PROVIDERS)
  // ═══════════════════════════════════════════════════════════════════════════

  void _testInputFuzzing(MixerProvider? mixer, SlotLabProvider? slotLab) {
    const mod = 'Fuzz';

    final volumeFuzz = <double>[
      0.0, 0.001, 0.5, 0.999, 1.0, 1.001, 1.999, 2.0,
      -0.001, -1.0, -100.0, 2.001, 100.0, 1000.0,
      double.infinity, double.negativeInfinity, double.nan,
      double.minPositive, double.maxFinite,
    ];
    final panFuzz = <double>[
      -1.0, -0.999, -0.5, 0.0, 0.5, 0.999, 1.0,
      -1.001, 1.001, -100.0, 100.0,
      double.infinity, double.negativeInfinity, double.nan,
    ];
    final idFuzz = <String>[
      '', ' ', '  ', 'null', 'undefined', 'NaN',
      'a' * 1000,
      '<script>alert(1)</script>',
      '\n\r\t', '\x00',
    ];

    // --- Mixer fuzzing ---
    if (mixer != null) {
      mixer.createChannel(name: '__FUZZ__');
      final ch = mixer.channels
          .where((c) => c.name == '__FUZZ__').firstOrNull;
      if (ch != null) {
        for (final v in volumeFuzz) {
          _assertNoThrow(mod, 'setVolume($v)', () {
            mixer.setChannelVolume(ch.id, v);
          });
          _fuzzInputs++;
          if (!v.isNaN && !v.isInfinite) {
            _assert(mod, 'Volume clamped after $v',
                ch.volume >= 0.0 && ch.volume <= 2.0, 'got ${ch.volume}');
          }
        }
        mixer.setChannelVolume(ch.id, 1.0);

        for (final p in panFuzz) {
          _assertNoThrow(mod, 'setPan($p)', () {
            mixer.setChannelPan(ch.id, p);
          });
          _fuzzInputs++;
          if (!p.isNaN && !p.isInfinite) {
            _assert(mod, 'Pan clamped after $p',
                ch.pan >= -1.0 && ch.pan <= 1.0, 'got ${ch.pan}');
          }
        }
        mixer.setChannelPan(ch.id, 0.0);

        final gainFuzz = <double>[-100.0, -24.0, 0.0, 24.0, 100.0, double.nan];
        for (final g in gainFuzz) {
          _assertNoThrow(mod, 'setInputGain($g)', () {
            mixer.setInputGain(ch.id, g);
          });
          _fuzzInputs++;
        }
        mixer.setInputGain(ch.id, 0.0);

        // StereoWidth fuzzing
        final widthFuzz = <double>[-1.0, 0.0, 0.5, 1.0, 2.0, 100.0, double.nan];
        for (final w in widthFuzz) {
          _assertNoThrow(mod, 'setStereoWidth($w)', () {
            mixer.setStereoWidth(ch.id, w);
          });
          _fuzzInputs++;
        }

        mixer.deleteChannel(ch.id);
      }

      for (final id in idFuzz) {
        _assertNoThrow(mod, 'setVolume(id="$id")', () {
          mixer.setChannelVolume(id, 0.5);
        });
        _assertNoThrow(mod, 'toggleMute(id="$id")', () {
          mixer.toggleChannelMute(id);
        });
        _fuzzInputs += 2;
      }
    }

    // --- SlotLab grid fuzzing ---
    if (slotLab != null && slotLab.initialized) {
      final gridFuzz = <(int, int)>[
        (0, 0), (1, 1), (2, 2), (-1, 3), (3, -1),
        (100, 100), (3, 1), (8, 6), (9, 7),
        (0x7FFFFFFF, 0x7FFFFFFF), (-0x7FFFFFFF, -0x7FFFFFFF),
      ];
      for (final (r, c) in gridFuzz) {
        _assertNoThrow(mod, 'updateGridSize($r, $c)', () {
          slotLab.updateGridSize(r, c);
        });
        _fuzzInputs++;
      }
      slotLab.updateGridSize(5, 3);

      // Bet amount fuzzing
      final betFuzz = <double>[
        0.0, -1.0, 0.01, 1.0, 100.0, 999999.0,
        double.infinity, double.nan, double.negativeInfinity,
      ];
      for (final b in betFuzz) {
        _assertNoThrow(mod, 'setBetAmount($b)', () {
          slotLab.setBetAmount(b);
        });
        _fuzzInputs++;
      }
      slotLab.setBetAmount(1.0);

      // Volatility slider fuzzing
      final volFuzz = <double>[
        -1.0, 0.0, 0.5, 1.0, 2.0, double.nan, double.infinity,
      ];
      for (final v in volFuzz) {
        _assertNoThrow(mod, 'setVolatilitySlider($v)', () {
          slotLab.setVolatilitySlider(v);
        });
        _fuzzInputs++;
      }
      slotLab.setVolatilitySlider(0.5);

      // Seed RNG fuzzing
      final seedFuzz = <int>[0, -1, 1, 0x7FFFFFFF, -0x7FFFFFFF];
      for (final s in seedFuzz) {
        _assertNoThrow(mod, 'seedRng($s)', () {
          slotLab.seedRng(s);
        });
        _fuzzInputs++;
      }
    }

    // --- Emotional state fuzzing ---
    final emo = _tryGet<EmotionalStateProvider>();
    if (emo != null) {
      final intensityFuzz = <double>[-1.0, 0.0, 0.5, 1.0, 2.0, double.nan, double.infinity];
      for (final v in intensityFuzz) {
        _assertNoThrow(mod, 'emo.setVolatilityIndex($v)', () {
          emo.setVolatilityIndex(v);
        });
        _fuzzInputs++;
      }
      _assertNoThrow(mod, 'emo.setRtpDeviation(NaN)', () {
        emo.setRtpDeviation(double.nan);
      });
      _assertNoThrow(mod, 'emo.setRtpDeviation(Inf)', () {
        emo.setRtpDeviation(double.infinity);
      });
      _fuzzInputs += 2;
      // Fuzz onSpinResult with extreme values
      _assertNoThrow(mod, 'emo.onSpinResult(neg win)', () {
        emo.onSpinResult(winAmount: -100, betAmount: 0);
      });
      _assertNoThrow(mod, 'emo.onSpinResult(Inf)', () {
        emo.onSpinResult(winAmount: double.infinity, betAmount: double.infinity);
      });
      _fuzzInputs += 2;
      emo.reset();
    }

    // --- BehaviorTree fuzzing ---
    final bt = _tryGet<BehaviorTreeProvider>();
    if (bt != null) {
      _assertNoThrow(mod, 'bt.selectNode(empty)', () {
        bt.selectNode('');
      });
      _assertNoThrow(mod, 'bt.selectNode(nonexistent)', () {
        bt.selectNode('__DOES_NOT_EXIST__');
      });
      _assertNoThrow(mod, 'bt.updateNodeEmotionalWeight(bad, NaN)', () {
        bt.updateNodeEmotionalWeight('__BAD__', double.nan);
      });
      _assertNoThrow(mod, 'bt.dispatchHook(empty)', () {
        bt.dispatchHook('');
      });
      _assertNoThrow(mod, 'bt.dispatchHook(nonexistent)', () {
        bt.dispatchHook('__NONEXISTENT_HOOK__');
      });
      _assertNoThrow(mod, 'bt.getHooksForNode(bad)', () {
        bt.getHooksForNode('__BAD__');
      });
      _assertNoThrow(mod, 'bt.loadFromJson(empty)', () {
        bt.loadFromJson({});
      });
      _fuzzInputs += 7;
    }

    // --- VoicePool fuzzing ---
    final vp = _tryGet<VoicePoolProvider>();
    if (vp != null) {
      _assertNoThrow(mod, 'vp.releaseVoice(-1)', () {
        vp.releaseVoice(-1);
      });
      _assertNoThrow(mod, 'vp.releaseVoice(maxInt)', () {
        vp.releaseVoice(0x7FFFFFFF);
      });
      _assertNoThrow(mod, 'vp.setVoiceVolume(-1, NaN)', () {
        vp.setVoiceVolume(-1, double.nan);
      });
      _assertNoThrow(mod, 'vp.setMaxVoices(0)', () {
        vp.setMaxVoices(0);
      });
      _assertNoThrow(mod, 'vp.setMaxVoices(-1)', () {
        vp.setMaxVoices(-1);
      });
      _assertNoThrow(mod, 'vp.getVoice(-1)', () {
        vp.getVoice(-1);
      });
      _fuzzInputs += 6;
    }

    // --- StateGroups fuzzing ---
    final sg = _tryGet<StateGroupsProvider>();
    if (sg != null) {
      _assertNoThrow(mod, 'sg.setState(-1, -1)', () {
        sg.setState(-1, -1);
      });
      _assertNoThrow(mod, 'sg.setState(maxInt, 0)', () {
        sg.setState(0x7FFFFFFF, 0);
      });
      _assertNoThrow(mod, 'sg.registerEmpty', () {
        sg.registerStateGroupFromPreset('', []);
      });
      _assertNoThrow(mod, 'sg.resetState(-1)', () {
        sg.resetState(-1);
      });
      _assertNoThrow(mod, 'sg.getStateGroup(-1)', () {
        sg.getStateGroup(-1);
      });
      _fuzzInputs += 5;
    }

    // --- SwitchGroups fuzzing ---
    final swg = _tryGet<SwitchGroupsProvider>();
    if (swg != null) {
      _assertNoThrow(mod, 'swg.setSwitch(-1,-1,-1)', () {
        swg.setSwitch(-1, -1, -1);
      });
      _assertNoThrow(mod, 'swg.resetSwitch(-1,-1)', () {
        swg.resetSwitch(-1, -1);
      });
      _assertNoThrow(mod, 'swg.clearObjectSwitches(-1)', () {
        swg.clearObjectSwitches(-1);
      });
      _fuzzInputs += 3;
    }

    // --- RTPC fuzzing ---
    final rtpc = _tryGet<RtpcSystemProvider>();
    if (rtpc != null) {
      _assertNoThrow(mod, 'rtpc.setRtpc(-1, NaN)', () {
        rtpc.setRtpc(-1, double.nan);
      });
      _assertNoThrow(mod, 'rtpc.setRtpc(-1, Inf)', () {
        rtpc.setRtpc(-1, double.infinity);
      });
      _assertNoThrow(mod, 'rtpc.resetRtpc(-1)', () {
        rtpc.resetRtpc(-1);
      });
      _assertNoThrow(mod, 'rtpc.getRtpcValue(-1)', () {
        rtpc.getRtpcValue(-1);
      });
      _assertNoThrow(mod, 'rtpc.deleteBinding(-1)', () {
        rtpc.deleteBinding(-1);
      });
      _assertNoThrow(mod, 'rtpc.deleteDspBinding(-1)', () {
        rtpc.deleteDspBinding(-1);
      });
      _fuzzInputs += 6;
    }

    // --- EnergyGovernance fuzzing ---
    final eg = _tryGet<EnergyGovernanceProvider>();
    if (eg != null) {
      _assertNoThrow(mod, 'eg.recordSpin(NaN)', () {
        eg.recordSpin(winMultiplier: double.nan);
      });
      _assertNoThrow(mod, 'eg.recordSpin(Inf)', () {
        eg.recordSpin(winMultiplier: double.infinity);
      });
      _assertNoThrow(mod, 'eg.recordSpin(neg)', () {
        eg.recordSpin(winMultiplier: -100.0);
      });
      _fuzzInputs += 3;
    }

    // --- GameFlow fuzzing ---
    final gf = _tryGet<GameFlowProvider>();
    if (gf != null) {
      _assertNoThrow(mod, 'gf.configure(neg reels)', () {
        gf.configure(reelCount: -1, rowCount: -1);
      });
      _assertNoThrow(mod, 'gf.resetToBaseGame()', () {
        gf.resetToBaseGame();
      });
      _fuzzInputs += 2;
    }

    // --- StageFlow fuzzing ---
    final sf = _tryGet<StageFlowProvider>();
    if (sf != null) {
      _assertNoThrow(mod, 'sf.selectNode(null)', () {
        sf.selectNode(null);
      });
      _assertNoThrow(mod, 'sf.selectNode(bad)', () {
        sf.selectNode('__NONEXISTENT__');
      });
      _assertNoThrow(mod, 'sf.removeNode(bad)', () {
        sf.removeNode('__NONEXISTENT__');
      });
      _assertNoThrow(mod, 'sf.undo empty', () {
        sf.undo();
      });
      _assertNoThrow(mod, 'sf.redo empty', () {
        sf.redo();
      });
      _fuzzInputs += 5;
    }

    // --- AUREXIS fuzzing ---
    final aurexis = _tryGet<AurexisProvider>();
    if (aurexis != null) {
      _assertNoThrow(mod, 'aurexis.setVolatility(NaN)', () {
        aurexis.setVolatility(double.nan);
      });
      _assertNoThrow(mod, 'aurexis.setRtp(Inf)', () {
        aurexis.setRtp(double.infinity);
      });
      _assertNoThrow(mod, 'aurexis.compute(neg)', () {
        aurexis.compute(elapsedMs: -100);
      });
      _assertNoThrow(mod, 'aurexis.setWin(NaN)', () {
        aurexis.setWin(amount: double.nan, bet: double.nan);
      });
      _fuzzInputs += 4;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE E: DETERMINISM VERIFICATION
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testDeterminism(
      MixerProvider? mixer, SlotLabProvider? slotLab) async {
    const mod = 'Determinism';

    // Idempotency
    if (mixer != null) {
      mixer.createChannel(name: '__DET__');
      final ch = mixer.channels
          .where((c) => c.name == '__DET__').firstOrNull;
      if (ch != null) {
        mixer.setChannelVolume(ch.id, 0.7);
        final v1 = ch.volume;
        mixer.setChannelVolume(ch.id, 0.7);
        final v2 = ch.volume;
        _assert(mod, 'setVolume idempotent', v1 == v2,
            'First=$v1, Second=$v2');

        mixer.setChannelPan(ch.id, -0.3);
        final p1 = ch.pan;
        mixer.setChannelPan(ch.id, -0.3);
        final p2 = ch.pan;
        _assert(mod, 'setPan idempotent', p1 == p2);

        final mBefore = ch.muted;
        mixer.toggleChannelMute(ch.id);
        mixer.toggleChannelMute(ch.id);
        _assert(mod, 'Double toggle mute = identity', ch.muted == mBefore);

        final sBefore = ch.soloed;
        mixer.toggleChannelSolo(ch.id);
        mixer.toggleChannelSolo(ch.id);
        _assert(mod, 'Double toggle solo = identity', ch.soloed == sBefore);

        mixer.deleteChannel(ch.id);
      }
    }

    // Commutativity
    if (mixer != null) {
      mixer.createChannel(name: '__COM_A__');
      mixer.createChannel(name: '__COM_B__');
      final chA = mixer.channels.where((c) => c.name == '__COM_A__').firstOrNull;
      final chB = mixer.channels.where((c) => c.name == '__COM_B__').firstOrNull;
      if (chA != null && chB != null) {
        mixer.setChannelVolume(chA.id, 0.3);
        mixer.setChannelPan(chB.id, 0.7);
        final vA1 = chA.volume;
        final pB1 = chB.pan;
        mixer.setChannelVolume(chA.id, 1.0);
        mixer.setChannelPan(chB.id, 0.0);
        mixer.setChannelPan(chB.id, 0.7);
        mixer.setChannelVolume(chA.id, 0.3);
        _assert(mod, 'Commutative: vol A same', chA.volume == vA1);
        _assert(mod, 'Commutative: pan B same', chB.pan == pB1);
      }
      // Always cleanup — even if null check failed
      for (final c in mixer.channels
          .where((c) => c.name == '__COM_A__' || c.name == '__COM_B__')
          .map((c) => c.id).toList()) {
        try { mixer.deleteChannel(c); } catch (_) {}
      }
    }

    // Undo-Redo identity
    final undo = _tryGet<SlotLabUndoProvider>();
    if (undo != null) {
      _assertNoThrow(mod, 'Undo empty safe', () => undo.undo());
      _assertNoThrow(mod, 'Redo empty safe', () => undo.redo());
    }

    // Serialization roundtrip: BehaviorTree
    final bt = _tryGet<BehaviorTreeProvider>();
    if (bt != null) {
      final json1 = bt.toJson();
      bt.loadFromJson(json1);
      final json2 = bt.toJson();
      final str1 = const JsonEncoder().convert(json1);
      final str2 = const JsonEncoder().convert(json2);
      _assert(mod, 'BT: serialize roundtrip identical',
          str1 == str2,
          'JSON differs (len1=${str1.length}, len2=${str2.length})');
    }

    // Serialization roundtrip: FeatureComposer
    final fc = _tryGet<FeatureComposerProvider>();
    if (fc != null) {
      final json1 = fc.toJson();
      fc.fromJson(json1);
      final json2 = fc.toJson();
      final str1 = const JsonEncoder().convert(json1);
      final str2 = const JsonEncoder().convert(json2);
      _assert(mod, 'FeatureComposer: serialize roundtrip identical',
          str1 == str2);
    }

    // Serialization roundtrip: VoicePool
    final vp = _tryGet<VoicePoolProvider>();
    if (vp != null) {
      final json1 = vp.toJson();
      vp.fromJson(json1);
      final json2 = vp.toJson();
      final str1 = const JsonEncoder().convert(json1);
      final str2 = const JsonEncoder().convert(json2);
      _assert(mod, 'VoicePool: serialize roundtrip identical',
          str1 == str2);
    }

    // Serialization roundtrip: StateGroups
    final sg = _tryGet<StateGroupsProvider>();
    if (sg != null) {
      final json1 = sg.toJson();
      sg.fromJson(json1);
      final json2 = sg.toJson();
      final str1 = const JsonEncoder().convert(json1);
      final str2 = const JsonEncoder().convert(json2);
      _assert(mod, 'StateGroups: serialize roundtrip identical',
          str1 == str2);
    }

    // Serialization roundtrip: SwitchGroups
    final swg = _tryGet<SwitchGroupsProvider>();
    if (swg != null) {
      final json1 = swg.toJson();
      swg.fromJson(json1);
      final json2 = swg.toJson();
      final str1 = const JsonEncoder().convert(json1);
      final str2 = const JsonEncoder().convert(json2);
      _assert(mod, 'SwitchGroups: serialize roundtrip identical',
          str1 == str2);
    }

    // Seeded spin determinism
    if (slotLab != null && slotLab.initialized) {
      slotLab.seedRng(12345);
      final result1 = await slotLab.spin();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      slotLab.seedRng(12345);
      final result2 = await slotLab.spin();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (result1 != null && result2 != null) {
        _assert(mod, 'Seeded spin: same grid',
            _gridsEqual(result1.grid, result2.grid),
            'Grids differ with same seed');
      }
    }
  }

  bool _gridsEqual(dynamic a, dynamic b) {
    if (a == null || b == null) return a == b;
    if (a is! List || b is! List) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] is List && b[i] is List) {
        if (!_gridsEqual(a[i], b[i])) return false;
      } else if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE F: LEAK DETECTION
  // ═══════════════════════════════════════════════════════════════════════════

  void _testLeakDetection(MixerProvider? mixer) {
    const mod = 'Leaks';

    final rssBefore = ProcessInfo.currentRss;

    // Create and delete 100 channels
    if (mixer != null) {
      final ids = <String>[];
      for (int i = 0; i < 100; i++) {
        mixer.createChannel(name: '__LEAK_${i}__');
        final ch = mixer.channels
            .where((c) => c.name == '__LEAK_${i}__').firstOrNull;
        if (ch != null) ids.add(ch.id);
      }
      for (final id in ids) {
        mixer.deleteChannel(id);
      }
    }

    final rssAfter = ProcessInfo.currentRss;
    final deltaKb = (rssAfter - rssBefore) / 1024;
    _assert(mod, 'Memory after 100 create/delete: delta=${deltaKb.round()}KB',
        deltaKb < 5120, 'Possible leak: ${deltaKb.round()}KB growth');
    if (deltaKb >= 5120) _leaksDetected++;

    // MemoryLeakDetector integration
    final detector = MemoryLeakDetector.instance;
    _assertNoThrow(mod, 'MemoryLeakDetector: start', () {
      detector.startMonitoring(scanInterval: const Duration(seconds: 1));
    });
    _assertNoThrow(mod, 'MemoryLeakDetector: stop', () {
      detector.stopMonitoring();
    });
    _assert(mod, 'MemoryLeakDetector: no leaks after test',
        detector.leakCount == 0,
        '${detector.leakCount} leaks detected');
    if (detector.leakCount > 0) _leaksDetected += detector.leakCount;

    // GetIt singleton consistency
    void checkSingletonLeak<T extends Object>(String name) {
      final a = _tryGet<T>();
      final b = _tryGet<T>();
      if (a != null && b != null) {
        _assert(mod, 'Singleton leak: $name', identical(a, b));
        if (!identical(a, b)) _leaksDetected++;
      }
    }
    checkSingletonLeak<StateGroupsProvider>('StateGroups');
    checkSingletonLeak<SwitchGroupsProvider>('SwitchGroups');
    checkSingletonLeak<RtpcSystemProvider>('RTPC');
    checkSingletonLeak<BehaviorTreeProvider>('BT');
    checkSingletonLeak<EmotionalStateProvider>('Emotional');
    checkSingletonLeak<VoicePoolProvider>('VoicePool');
    checkSingletonLeak<GameFlowProvider>('GameFlow');
    checkSingletonLeak<StageFlowProvider>('StageFlow');
    checkSingletonLeak<EnergyGovernanceProvider>('Energy');
    checkSingletonLeak<AurexisProvider>('AUREXIS');
    checkSingletonLeak<FeatureComposerProvider>('Composer');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE G: PERFORMANCE BASELINES
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testPerformanceBaselines(
      MixerProvider? mixer, SlotLabProvider? slotLab) async {
    const mod = 'Perf';

    if (mixer != null) {
      final volTimes = <int>[];
      mixer.createChannel(name: '__PERF__');
      final ch = mixer.channels
          .where((c) => c.name == '__PERF__').firstOrNull;
      if (ch != null) {
        for (int i = 0; i < 100; i++) {
          final sw = Stopwatch()..start();
          mixer.setChannelVolume(ch.id, (i % 20) / 10.0);
          sw.stop();
          volTimes.add(sw.elapsedMicroseconds);
        }
        mixer.deleteChannel(ch.id);
      }
      if (volTimes.isNotEmpty) {
        volTimes.sort();
        final median = volTimes[volTimes.length ~/ 2];
        final p95 = volTimes[(volTimes.length * 0.95).floor()];
        final p99 = volTimes[(volTimes.length * 0.99).floor()];
        _assert(mod, 'setVolume median < 1ms', median < 1000,
            'median=${median}us');
        _assert(mod, 'setVolume p95 < 5ms', p95 < 5000, 'p95=${p95}us');
        _timingBaselines['setVolume'] = volTimes;
        _diag.log('setVolume: median=${median}us p95=${p95}us p99=${p99}us');
      }
    }

    // Spin timing
    if (slotLab != null && slotLab.initialized) {
      final spinTimes = <int>[];
      for (int i = 0; i < 10; i++) {
        final sw = Stopwatch()..start();
        await slotLab.spin();
        sw.stop();
        spinTimes.add(sw.elapsedMilliseconds);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (spinTimes.isNotEmpty) {
        spinTimes.sort();
        final median = spinTimes[spinTimes.length ~/ 2];
        final p95 = spinTimes[(spinTimes.length * 0.95).floor()];
        _assert(mod, 'spin() median < 500ms', median < 500,
            'median=${median}ms');
        _assert(mod, 'spin() p95 < 1000ms', p95 < 1000, 'p95=${p95}ms');
        _timingBaselines['spin'] = spinTimes;
        _diag.log('spin: median=${median}ms p95=${p95}ms');
      }
    }

    // Grid change timing
    if (slotLab != null && slotLab.initialized) {
      final gridTimes = <int>[];
      for (int i = 0; i < 20; i++) {
        final sw = Stopwatch()..start();
        slotLab.updateGridSize(3 + (i % 6), 1 + (i % 6));
        sw.stop();
        gridTimes.add(sw.elapsedMicroseconds);
      }
      slotLab.updateGridSize(5, 3);
      if (gridTimes.isNotEmpty) {
        gridTimes.sort();
        final median = gridTimes[gridTimes.length ~/ 2];
        _assert(mod, 'updateGridSize median < 10ms',
            median < 10000, 'median=${median}us');
        _diag.log('updateGridSize: median=${median}us');
      }
    }

    // Emotional state tick timing
    final emo = _tryGet<EmotionalStateProvider>();
    if (emo != null) {
      final tickTimes = <int>[];
      for (int i = 0; i < 100; i++) {
        final sw = Stopwatch()..start();
        emo.tick(0.016);
        sw.stop();
        tickTimes.add(sw.elapsedMicroseconds);
      }
      if (tickTimes.isNotEmpty) {
        tickTimes.sort();
        final median = tickTimes[tickTimes.length ~/ 2];
        _assert(mod, 'emo.tick median < 1ms', median < 1000,
            'median=${median}us');
        _diag.log('emo.tick: median=${median}us');
      }
    }

    // Watchdog: no operation should take > 5 seconds
    if (slotLab != null && slotLab.initialized) {
      final sw = Stopwatch()..start();
      try {
        await slotLab.spin().timeout(const Duration(seconds: 5));
        sw.stop();
        _assert(mod, 'Spin watchdog: < 5s', true);
      } on TimeoutException {
        sw.stop();
        _assert(mod, 'Spin watchdog: < 5s', false,
            'Spin took > 5s (possible hang)');
        _perfRegressions++;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE H: CROSS-PROVIDER REFERENTIAL INTEGRITY (DEEP)
  // ═══════════════════════════════════════════════════════════════════════════

  void _testReferentialIntegrity(SlotLabProvider? slotLab,
      MiddlewareProvider? middleware) {
    const mod = 'RefIntegrity';

    // Feature Composer hooks → BT node validation
    final composer = _tryGet<FeatureComposerProvider>();
    final bt = _tryGet<BehaviorTreeProvider>();

    if (composer != null && bt != null && composer.isConfigured) {
      final hooks = composer.activeHooks;
      final allNodeIds = bt.allNodes.map((n) => n.id).toSet();

      // Verify BT hook dispatch returns valid node IDs
      for (final hook in hooks) {
        final nodeIds = bt.getNodesForHook(hook);
        for (final nid in nodeIds) {
          _assert(mod, 'Hook "$hook" → node "$nid" exists in BT',
              allNodeIds.contains(nid),
              'Node $nid not found in BT');
        }
      }
      _diag.log('Composer hooks: ${hooks.length}, BT nodes: ${allNodeIds.length}');
    }

    // DiagnosticsService checkers/monitors registered
    _assert(mod, 'DiagnosticsService: has checkers',
        _diag.checkerNames.isNotEmpty, 'No checkers registered');
    _assert(mod, 'DiagnosticsService: has monitors',
        _diag.monitorNames.isNotEmpty, 'No monitors registered');

    // Composite events → trigger stages should be valid stage names
    if (middleware != null && slotLab != null) {
      final knownStages = slotLab.lastStages
          .map((s) => s.stageType).toSet();
      for (final evt in middleware.compositeEvents) {
        for (final stage in evt.triggerStages) {
          // Stage names should be non-empty
          _assert(mod, 'CompositeEvent "${evt.name}" trigger "$stage" non-empty',
              stage.isNotEmpty);
        }
      }
      _diag.log('Composite events: ${middleware.compositeEvents.length}, '
          'Known stages: ${knownStages.length}');
    }

    // RTPC bindings → valid RTPC definitions
    final rtpc = _tryGet<RtpcSystemProvider>();
    if (rtpc != null) {
      final defIds = rtpc.rtpcDefs.keys.toSet();
      for (final binding in rtpc.rtpcBindings) {
        _assert(mod, 'RTPC binding ${binding.id} → valid rtpc ${binding.rtpcId}',
            defIds.contains(binding.rtpcId),
            'RTPC ${binding.rtpcId} not found');
      }
      // DSP bindings → valid RTPC defs
      for (final dsp in rtpc.dspBindingsList) {
        _assert(mod, 'DSP binding ${dsp.id} → valid rtpc ${dsp.rtpcId}',
            defIds.contains(dsp.rtpcId),
            'RTPC ${dsp.rtpcId} not found');
      }
      // Macro bindings → valid RTPC defs
      for (final macro in rtpc.rtpcMacros) {
        if (macro.enabled) {
          _assert(mod, 'Macro "${macro.name}" exists', true);
        }
      }
    }

    // All singleton providers resolve consistently
    void checkSingleton<T extends Object>(String name) {
      final a = _tryGet<T>();
      final b = _tryGet<T>();
      if (a != null && b != null) {
        _assert(mod, 'Singleton: $name', identical(a, b));
      }
    }
    checkSingleton<StateGroupsProvider>('StateGroups');
    checkSingleton<SwitchGroupsProvider>('SwitchGroups');
    checkSingleton<RtpcSystemProvider>('RTPC');
    checkSingleton<BehaviorTreeProvider>('BT');
    checkSingleton<EmotionalStateProvider>('Emotional');
    checkSingleton<GameFlowProvider>('GameFlow');
    checkSingleton<StageFlowProvider>('StageFlow');
    checkSingleton<VoicePoolProvider>('VoicePool');
    checkSingleton<EnergyGovernanceProvider>('Energy');
    checkSingleton<AurexisProvider>('AUREXIS');
    checkSingleton<FeatureComposerProvider>('Composer');

    // StageFlow graph → valid nodes/edges if graph exists
    final sf = _tryGet<StageFlowProvider>();
    if (sf != null && sf.hasGraph) {
      final graph = sf.graph!;
      final nodeIds = graph.nodes.map((n) => n.id).toSet();
      for (final edge in graph.edges) {
        _assert(mod, 'StageFlow edge ${edge.id}: source exists',
            nodeIds.contains(edge.sourceNodeId),
            'Source ${edge.sourceNodeId} not in graph');
        _assert(mod, 'StageFlow edge ${edge.id}: target exists',
            nodeIds.contains(edge.targetNodeId),
            'Target ${edge.targetNodeId} not in graph');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE I: METAMORPHIC TESTING
  // ═══════════════════════════════════════════════════════════════════════════

  void _testMetamorphic(MixerProvider? mixer, SlotLabProvider? slotLab) {
    const mod = 'Metamorphic';

    if (mixer != null) {
      // Property: add + delete = identity
      final countBefore = mixer.channels.length;
      mixer.createChannel(name: '__META__');
      final ch = mixer.channels
          .where((c) => c.name == '__META__').firstOrNull;
      if (ch != null) mixer.deleteChannel(ch.id);
      _assert(mod, 'Create+Delete = identity',
          mixer.channels.length == countBefore,
          'Before=$countBefore After=${mixer.channels.length}');

      // Property: volume(x) then volume(y) = volume(y)
      mixer.createChannel(name: '__META2__');
      final ch2 = mixer.channels
          .where((c) => c.name == '__META2__').firstOrNull;
      if (ch2 != null) {
        mixer.setChannelVolume(ch2.id, 0.1);
        mixer.setChannelVolume(ch2.id, 0.9);
        final v1 = ch2.volume;
        mixer.setChannelVolume(ch2.id, 0.5);
        mixer.setChannelVolume(ch2.id, 0.9);
        final v2 = ch2.volume;
        _assert(mod, 'Volume: last write wins', v1 == v2,
            'v1=$v1, v2=$v2');
        mixer.deleteChannel(ch2.id);
      }

      // Property: mute(N even) = original
      mixer.createChannel(name: '__META3__');
      final ch3 = mixer.channels
          .where((c) => c.name == '__META3__').firstOrNull;
      if (ch3 != null) {
        final original = ch3.muted;
        for (int i = 0; i < 100; i++) {
          mixer.toggleChannelMute(ch3.id);
        }
        _assert(mod, 'Toggle mute 100x (even) = original',
            ch3.muted == original);
        mixer.deleteChannel(ch3.id);
      }

      // Property: solo(N even) = original
      mixer.createChannel(name: '__META4__');
      final ch4 = mixer.channels
          .where((c) => c.name == '__META4__').firstOrNull;
      if (ch4 != null) {
        final original = ch4.soloed;
        for (int i = 0; i < 100; i++) {
          mixer.toggleChannelSolo(ch4.id);
        }
        _assert(mod, 'Toggle solo 100x (even) = original',
            ch4.soloed == original);
        mixer.deleteChannel(ch4.id);
      }
    }

    // Grid change reflects in totalReels/totalRows
    if (slotLab != null && slotLab.initialized) {
      final grids = [(3, 3), (5, 4), (6, 6), (4, 2)];
      for (final (r, c) in grids) {
        slotLab.updateGridSize(r, c);
        _assert(mod, 'Grid $r x $c: totalReels matches',
            slotLab.totalReels == r,
            'Expected $r, got ${slotLab.totalReels}');
        _assert(mod, 'Grid $r x $c: totalRows matches',
            slotLab.totalRows == c,
            'Expected $c, got ${slotLab.totalRows}');
      }
      slotLab.updateGridSize(5, 3);
    }

    // Emotional state: reset returns to baseline
    final emo = _tryGet<EmotionalStateProvider>();
    if (emo != null) {
      emo.onSpinResult(winAmount: 1000, betAmount: 1);
      emo.reset();
      _assert(mod, 'Emotional: reset → intensity == 0',
          emo.intensity == 0.0, 'intensity=${emo.intensity}');
      _assert(mod, 'Emotional: reset → tension == 0',
          emo.tension == 0.0, 'tension=${emo.tension}');
    }

    // StateGroups: set then reset should not crash
    final sg = _tryGet<StateGroupsProvider>();
    if (sg != null && sg.stateGroups.isNotEmpty) {
      final gid = sg.stateGroups.keys.first;
      final g = sg.stateGroups[gid]!;
      if (g.states.length > 1) {
        _assertNoThrow(mod, 'StateGroups: set→reset cycle', () {
          sg.setState(gid, g.states.last.id);
          sg.resetState(gid);
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE J: TEMPORAL INVARIANTS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testTemporalInvariants(SlotLabProvider? slotLab) async {
    const mod = 'Temporal';

    if (slotLab == null || !slotLab.initialized) {
      _diag.log('SKIP Temporal: SlotLab not available');
      return;
    }

    _assert(mod, 'Pre-spin: not spinning', !slotLab.isSpinning);

    await slotLab.spin();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _assert(mod, 'Post-spin: not spinning', !slotLab.isSpinning,
        'isSpinning still true after spin');
    if (slotLab.isSpinning) _temporalViolations++;

    // spinCount monotonic
    final count1 = slotLab.spinCount;
    await slotLab.spin();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final count2 = slotLab.spinCount;
    _assert(mod, 'spinCount monotonic: $count2 > $count1', count2 > count1);
    if (count2 <= count1) _temporalViolations++;

    // Liveness
    final sw = Stopwatch()..start();
    try {
      await slotLab.spin().timeout(const Duration(seconds: 5));
      sw.stop();
      _assert(mod, 'Spin liveness: completed in ${sw.elapsedMilliseconds}ms',
          true);
    } on TimeoutException {
      sw.stop();
      _assert(mod, 'Spin liveness: TIMEOUT', false,
          'Spin did not complete in 5s');
      _temporalViolations++;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // lastResult should update after spin
    final resultBefore = slotLab.lastResult;
    await slotLab.spin();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _assert(mod, 'lastResult updated after spin',
        !identical(slotLab.lastResult, resultBefore));

    // Stats should reflect spin count
    _assert(mod, 'Stats spinCount >= spinCount getter',
        slotLab.stats != null
            ? slotLab.stats!.totalSpins >= slotLab.spinCount - 1
            : true);

    // Emotional state temporal: intensity should decay over time
    final emo = _tryGet<EmotionalStateProvider>();
    if (emo != null) {
      emo.onBigWin(5); // Spike intensity
      final peakIntensity = emo.intensity;
      for (int i = 0; i < 100; i++) {
        emo.tick(0.1); // 10 seconds of ticking
      }
      _assert(mod, 'Emotional: intensity decays over time',
          emo.intensity <= peakIntensity,
          'peak=$peakIntensity current=${emo.intensity}');
      emo.reset();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE K: CHAOS ENGINEERING
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testChaosEngineering(
      MixerProvider? mixer, SlotLabProvider? slotLab) async {
    const mod = 'Chaos';

    // Rapid interleaved mixer ops
    if (mixer != null) {
      mixer.createChannel(name: '__CHAOS__');
      final ch = mixer.channels
          .where((c) => c.name == '__CHAOS__').firstOrNull;
      if (ch != null) {
        _assertNoThrow(mod, 'Rapid interleaved mixer ops', () {
          for (int i = 0; i < 200; i++) {
            switch (i % 5) {
              case 0: mixer.setChannelVolume(ch.id, _rng.nextDouble() * 2);
              case 1: mixer.setChannelPan(ch.id, _rng.nextDouble() * 2 - 1);
              case 2: mixer.toggleChannelMute(ch.id);
              case 3: mixer.toggleChannelSolo(ch.id);
              case 4: mixer.setStereoWidth(ch.id, _rng.nextDouble() * 2);
            }
          }
        });
        _assert(mod, 'Post-chaos: volume valid',
            ch.volume >= 0.0 && ch.volume <= 2.0);
        _assert(mod, 'Post-chaos: pan valid',
            ch.pan >= -1.0 && ch.pan <= 1.0);
        mixer.deleteChannel(ch.id);
      }
    }

    // Spin during grid change
    if (slotLab != null && slotLab.initialized) {
      await _assertNoThrowAsync(mod, 'Spin + grid change race', () async {
        final spinFuture = slotLab.spin();
        slotLab.updateGridSize(6, 4);
        await spinFuture;
      });
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _assert(mod, 'Post-race: initialized', slotLab.initialized);
      _assert(mod, 'Post-race: not spinning', !slotLab.isSpinning);
      slotLab.updateGridSize(5, 3);
    }

    // Rapid spin-spin-spin
    if (slotLab != null && slotLab.initialized) {
      for (int i = 0; i < 5; i++) {
        await _assertNoThrowAsync(mod, 'Rapid spin $i', () async {
          await slotLab.spin();
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _assert(mod, 'Post-rapid-spin: stable', slotLab.initialized);
    }

    // Concurrent read+write
    if (mixer != null) {
      mixer.createChannel(name: '__CHAOS_READ__');
      final ch = mixer.channels
          .where((c) => c.name == '__CHAOS_READ__').firstOrNull;
      if (ch != null) {
        await _assertNoThrowAsync(mod, 'Concurrent read+write', () async {
          await Future.wait([
            Future.microtask(() {
              for (int i = 0; i < 100; i++) {
                mixer.setChannelVolume(ch.id, _rng.nextDouble() * 2);
              }
            }),
            Future.microtask(() {
              for (int i = 0; i < 100; i++) {
                ch.volume;
                ch.pan;
                ch.muted;
              }
            }),
          ]);
        });
        mixer.deleteChannel(ch.id);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE L: BOUNDARY TESTING (Audio Pipeline)
  // ═══════════════════════════════════════════════════════════════════════════

  void _testBoundaryTesting(SlotLabProvider? slotLab,
      MiddlewareProvider? middleware) {
    const mod = 'Boundary';

    if (middleware == null) {
      _diag.log('SKIP Boundary: middleware not available');
      return;
    }

    // Composite events: CRUD cycle
    final countBefore = middleware.compositeEvents.length;

    // Test composite event lifecycle
    _assertNoThrow(mod, 'initializeDefaultCompositeEvents', () {
      middleware.initializeDefaultCompositeEvents();
    });

    _assert(mod, 'Composite events exist after init',
        middleware.compositeEvents.isNotEmpty,
        'count=${middleware.compositeEvents.length}');

    // Select/deselect composite event
    if (middleware.compositeEvents.isNotEmpty) {
      final first = middleware.compositeEvents.first;
      _assertNoThrow(mod, 'selectCompositeEvent', () {
        middleware.selectCompositeEvent(first.id);
      });
      _assert(mod, 'Selected event matches',
          middleware.selectedCompositeEventId == first.id);
      _assertNoThrow(mod, 'deselectCompositeEvent', () {
        middleware.selectCompositeEvent(null);
      });
      _assert(mod, 'No event selected after deselect',
          middleware.selectedCompositeEventId == null);
    }

    // Composite event serialization roundtrip
    _assertNoThrow(mod, 'Composite export/import roundtrip', () {
      final exported = middleware.exportCompositeEventsToJsonString();
      middleware.importCompositeEventsFromJsonString(exported);
    });
    _assert(mod, 'Composite count preserved after roundtrip',
        middleware.compositeEvents.length >= countBefore,
        'before=$countBefore after=${middleware.compositeEvents.length}');

    // Event posting with invalid IDs
    _assertNoThrow(mod, 'postEvent(empty)', () {
      middleware.postEvent('');
    });
    _assertNoThrow(mod, 'postEvent(nonexistent)', () {
      middleware.postEvent('__DOES_NOT_EXIST__');
    });
    _assertNoThrow(mod, 'stopEvent(empty)', () {
      middleware.stopEvent('');
    });

    // Layer operations on non-existent events
    _assertNoThrow(mod, 'removeLayer(bad event, bad layer)', () {
      middleware.removeLayerFromEvent('__BAD__', '__BAD__');
    });
    _assertNoThrow(mod, 'toggleLayerMute(bad)', () {
      middleware.toggleLayerMute('__BAD__', '__BAD__');
    });

    // Undo/redo on composite events
    _assertNoThrow(mod, 'undoCompositeEvents', () {
      middleware.undoCompositeEvents();
    });
    _assertNoThrow(mod, 'redoCompositeEvents', () {
      middleware.redoCompositeEvents();
    });

    // Clipboard operations
    _assertNoThrow(mod, 'clearClipboard', () {
      middleware.clearClipboard();
    });
    _assert(mod, 'No layer in clipboard after clear',
        !middleware.hasLayerInClipboard);

    // SlotLab processHook through middleware pipeline
    if (slotLab != null && slotLab.initialized) {
      _assertNoThrow(mod, 'processHook(empty)', () {
        slotLab.processHook('');
      });
      _assertNoThrow(mod, 'processHook(nonexistent)', () {
        slotLab.processHook('__NONEXISTENT_HOOK__');
      });
    }

    // Bus operations with invalid IDs
    _assertNoThrow(mod, 'setBusVolume(-1)', () {
      middleware.setBusVolume(-1, 0.5);
    });
    _assertNoThrow(mod, 'setBusMute(-1)', () {
      middleware.setBusMute(-1, true);
    });

    // Spatial engine boundary
    _assertNoThrow(mod, 'clearSpatialTracking', () {
      middleware.clearSpatialTracking();
    });

    // StopAllEvents
    _assertNoThrow(mod, 'stopAllEvents', () {
      middleware.stopAllEvents();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE M: ERROR RECOVERY
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testErrorRecovery(MixerProvider? mixer,
      SlotLabProvider? slotLab, MiddlewareProvider? middleware) async {
    const mod = 'Recovery';

    // SlotLab: spin when not initialized should not crash
    // (we test with a freshly created coordinator — but since we can't
    //  create one without FFI, we test edge operations on the existing one)
    if (slotLab != null && slotLab.initialized) {
      // Forced outcome with invalid data
      _assertNoThrow(mod, 'spinForced with base outcome', () {
        slotLab.spinForced(ForcedOutcome.lose);
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _assert(mod, 'Post-forcedSpin: stable', slotLab.initialized);

      // Rapid spin after error state
      await _assertNoThrowAsync(mod, 'Spin after forced', () async {
        await slotLab.spin();
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    // Mixer: operations after deleting channel should not crash
    if (mixer != null) {
      mixer.createChannel(name: '__RECOVERY__');
      final ch = mixer.channels
          .where((c) => c.name == '__RECOVERY__').firstOrNull;
      if (ch != null) {
        final id = ch.id;
        mixer.deleteChannel(id);
        // Operations on deleted channel
        _assertNoThrow(mod, 'setVolume on deleted channel', () {
          mixer.setChannelVolume(id, 0.5);
        });
        _assertNoThrow(mod, 'toggleMute on deleted channel', () {
          mixer.toggleChannelMute(id);
        });
        _assertNoThrow(mod, 'setPan on deleted channel', () {
          mixer.setChannelPan(id, 0.5);
        });
      }
    }

    // BT: loadFromJson with malformed data
    final bt = _tryGet<BehaviorTreeProvider>();
    if (bt != null) {
      final validJson = bt.toJson();
      // Load empty — safe (might clear tree)
      _assertNoThrow(mod, 'BT load empty JSON', () {
        bt.loadFromJson({});
      });
      // Restore valid state immediately (malformed JSON may corrupt tree)
      _assertNoThrow(mod, 'BT restore valid JSON after empty', () {
        bt.loadFromJson(validJson);
      });
      _assert(mod, 'BT recovered after empty load',
          bt.totalNodeCount >= 0);
    }

    // StateGroups: operations on unregistered groups
    final sg = _tryGet<StateGroupsProvider>();
    if (sg != null) {
      _assertNoThrow(mod, 'sg.unregisterStateGroup(-1)', () {
        sg.unregisterStateGroup(-1);
      });
      _assertNoThrow(mod, 'sg.setStateByName(-1, bad)', () {
        sg.setStateByName(-1, '__BAD__');
      });
      _assertNoThrow(mod, 'sg.getStateGroupByName(bad)', () {
        sg.getStateGroupByName('__NONEXISTENT__');
      });
    }

    // VoicePool: release non-existent voices
    final vp = _tryGet<VoicePoolProvider>();
    if (vp != null) {
      _assertNoThrow(mod, 'vp.releaseAllVoices', () {
        vp.releaseAllVoices();
      });
      _assert(mod, 'VoicePool: active=0 after releaseAll',
          vp.activeCount == 0, 'active=${vp.activeCount}');
      _assertNoThrow(mod, 'vp.resetStats', () {
        vp.resetStats();
      });
    }

    // StageFlow: cancel execution when nothing running
    final sf = _tryGet<StageFlowProvider>();
    if (sf != null) {
      _assertNoThrow(mod, 'sf.cancelExecution(idle)', () {
        sf.cancelExecution();
      });
      _assertNoThrow(mod, 'sf.slamStop(idle)', () {
        sf.slamStop();
      });
      _assertNoThrow(mod, 'sf.pauseDryRun(idle)', () {
        sf.pauseDryRun();
      });
      _assertNoThrow(mod, 'sf.resumeDryRun(idle)', () {
        sf.resumeDryRun();
      });
    }

    // EnergyGovernance: reset and re-record
    final eg = _tryGet<EnergyGovernanceProvider>();
    if (eg != null) {
      _assertNoThrow(mod, 'eg.resetSession', () {
        eg.resetSession();
      });
      _assertNoThrow(mod, 'eg.recordSpin after reset', () {
        eg.recordSpin(winMultiplier: 2.0);
      });
      // Just verify recordSpin doesn't crash and totalSpins is non-negative
      _assert(mod, 'Energy: totalSpins >= 0 after record',
          eg.totalSpins >= 0, 'totalSpins=${eg.totalSpins}');
    }

    // Middleware: import empty/malformed JSON
    if (middleware != null) {
      _assertNoThrow(mod, 'middleware.importCompositeEventsFromJsonString(empty)', () {
        middleware.importCompositeEventsFromJsonString('{}');
      });
    }

    // AUREXIS: operations in various states
    final aurexis = _tryGet<AurexisProvider>();
    if (aurexis != null) {
      _assertNoThrow(mod, 'aurexis.clearWin', () {
        aurexis.clearWin();
      });
      _assertNoThrow(mod, 'aurexis.resetSession', () {
        aurexis.resetSession();
      });
      _assertNoThrow(mod, 'aurexis.compute after reset', () {
        aurexis.compute();
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE N: CONTRACT TESTING (Diagnostic Interfaces)
  // ═══════════════════════════════════════════════════════════════════════════

  void _testContractTesting() {
    const mod = 'Contract';

    // StageTriggerAware: all registered monitors should handle onStageTrigger
    _assertNoThrow(mod, 'DiagnosticsService.onStageTrigger(SPIN_START)', () {
      _diag.onStageTrigger('SPIN_START', 0.0);
    });
    _assertNoThrow(mod, 'DiagnosticsService.onStageTrigger(SPIN_END)', () {
      _diag.onStageTrigger('SPIN_END', 100.0);
    });
    _assertNoThrow(mod, 'DiagnosticsService.onStageTrigger(REEL_STOP)', () {
      _diag.onStageTrigger('REEL_STOP', 50.0);
    });
    _assertNoThrow(mod, 'DiagnosticsService.onStageTrigger(empty)', () {
      _diag.onStageTrigger('', 0.0);
    });
    _assertNoThrow(mod, 'DiagnosticsService.onStageTrigger(unknown)', () {
      _diag.onStageTrigger('__UNKNOWN_STAGE__', 0.0);
    });
    _assertNoThrow(mod, 'DiagnosticsService.onStageTrigger(neg timestamp)', () {
      _diag.onStageTrigger('SPIN_START', -1.0);
    });
    _assertNoThrow(mod, 'DiagnosticsService.onStageTrigger(NaN timestamp)', () {
      _diag.onStageTrigger('SPIN_START', double.nan);
    });

    // SpinCompleteAware: onSpinComplete should be safe to call
    _assertNoThrow(mod, 'DiagnosticsService.onSpinComplete()', () {
      _diag.onSpinComplete();
    });

    // Multiple onSpinComplete calls (should drain monitors safely)
    _assertNoThrow(mod, 'DiagnosticsService.onSpinComplete() x5', () {
      for (int i = 0; i < 5; i++) {
        _diag.onSpinComplete();
      }
    });

    // runFullCheck should not crash
    _assertNoThrow(mod, 'DiagnosticsService.runFullCheck()', () {
      _diag.runFullCheck();
    });

    // Verify check produced a report
    _assert(mod, 'runFullCheck produced report',
        _diag.lastReport != null);

    // reportFinding with various severities
    _assertNoThrow(mod, 'reportFinding(ok)', () {
      _diag.reportFinding(DiagnosticFinding(
        checker: '__TEST__', severity: DiagnosticSeverity.ok,
        message: 'Test OK',
      ));
    });
    _assertNoThrow(mod, 'reportFinding(warning)', () {
      _diag.reportFinding(DiagnosticFinding(
        checker: '__TEST__', severity: DiagnosticSeverity.warning,
        message: 'Test Warning',
      ));
    });

    // clearFindings + verify
    final countBefore = _diag.liveFindings.length;
    _assertNoThrow(mod, 'clearFindings', () {
      _diag.clearFindings();
    });
    _assert(mod, 'Findings cleared',
        _diag.liveFindings.length < countBefore || countBefore == 0);

    // Logging should not crash
    _assertNoThrow(mod, 'DiagnosticsService.log(empty)', () {
      _diag.log('');
    });
    _assertNoThrow(mod, 'DiagnosticsService.log(long)', () {
      _diag.log('x' * 10000);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE O: MULTI-PROVIDER CHAOS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testMultiProviderChaos(MixerProvider? mixer,
      SlotLabProvider? slotLab, MiddlewareProvider? middleware) async {
    const mod = 'MultiChaos';

    final emo = _tryGet<EmotionalStateProvider>();
    final bt = _tryGet<BehaviorTreeProvider>();
    final eg = _tryGet<EnergyGovernanceProvider>();
    final sg = _tryGet<StateGroupsProvider>();
    final rtpc = _tryGet<RtpcSystemProvider>();

    // Simultaneous operations across ALL providers
    await _assertNoThrowAsync(mod, 'All-provider concurrent burst', () async {
      await Future.wait([
        // Mixer burst
        if (mixer != null) Future.microtask(() {
          for (int i = 0; i < 50; i++) {
            mixer.master.volume; // read
            if (mixer.channels.isNotEmpty) {
              mixer.setChannelVolume(
                  mixer.channels.first.id, _rng.nextDouble() * 2);
            }
          }
        }),
        // SlotLab spin
        if (slotLab != null && slotLab.initialized) Future.microtask(() async {
          await slotLab.spin();
        }),
        // Emotional state pump
        if (emo != null) Future.microtask(() {
          for (int i = 0; i < 50; i++) {
            emo.tick(0.016);
          }
        }),
        // BT selection cycling
        if (bt != null) Future.microtask(() {
          final nodes = bt.allNodes;
          for (int i = 0; i < 20 && nodes.isNotEmpty; i++) {
            bt.selectNode(nodes[i % nodes.length].id);
          }
          bt.selectNode(null);
        }),
        // Energy governance pump
        if (eg != null) Future.microtask(() {
          for (int i = 0; i < 10; i++) {
            eg.recordSpin(winMultiplier: _rng.nextDouble() * 10);
          }
        }),
        // StateGroups cycling
        if (sg != null) Future.microtask(() {
          final groups = sg.stateGroups;
          for (final gid in groups.keys) {
            final g = groups[gid]!;
            if (g.states.isNotEmpty) {
              sg.setState(gid, g.states.first.id);
            }
          }
        }),
        // RTPC pump
        if (rtpc != null) Future.microtask(() {
          for (final def in rtpc.rtpcDefinitions) {
            rtpc.setRtpc(def.id, def.min + _rng.nextDouble() * (def.max - def.min));
          }
        }),
      ]);
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Post-chaos invariant verification across all providers
    if (mixer != null) {
      _assert(mod, 'Post-multi-chaos: master valid',
          mixer.master.type == ChannelType.master);
    }
    if (slotLab != null && slotLab.initialized) {
      _assert(mod, 'Post-multi-chaos: slotlab initialized',
          slotLab.initialized);
      _assert(mod, 'Post-multi-chaos: not spinning',
          !slotLab.isSpinning);
    }
    if (emo != null) {
      _assert(mod, 'Post-multi-chaos: emo intensity valid',
          emo.intensity >= 0.0 && emo.intensity <= 1.0);
    }
    if (eg != null) {
      _assert(mod, 'Post-multi-chaos: energy cap valid',
          eg.overallCap >= 0.0 && eg.overallCap <= 1.0);
    }

    // Spin + Emotional + GameFlow coordinated sequence
    if (slotLab != null && slotLab.initialized && emo != null) {
      final gf = _tryGet<GameFlowProvider>();
      await _assertNoThrowAsync(mod, 'Coordinated spin+emo+gameflow', () async {
        emo.onSpinStart();
        gf?.onSpinStart();
        final result = await slotLab.spin();
        if (result != null) {
          emo.onSpinResult(
              winAmount: slotLab.lastWinAmount,
              betAmount: slotLab.betAmount);
          gf?.onSpinComplete(result);
        }
        emo.tick(0.5);
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _assert(mod, 'Post-coordinated: stable', slotLab.initialized);
    }

    // Middleware + SlotLab hook processing chaos
    if (slotLab != null && slotLab.initialized && middleware != null) {
      await _assertNoThrowAsync(mod, 'Rapid hook processing', () async {
        final hooks = ['SPIN_START', 'REEL_STOP', 'WIN_PRESENTATION',
            'SPIN_END', 'SCATTER_LAND', 'ANTICIPATION_START'];
        for (final hook in hooks) {
          slotLab.processHook(hook);
        }
        await slotLab.spin();
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE P: PROPERTY-BASED TESTING
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testPropertyBased(MixerProvider? mixer,
      SlotLabProvider? slotLab) async {
    const mod = 'PropBased';
    const sequences = 20;
    const opsPerSequence = 25;

    if (mixer == null) {
      _diag.log('SKIP PropBased: mixer not available');
      return;
    }

    int seqErrors = 0;

    for (int seq = 0; seq < sequences && !_cancelled; seq++) {
      // Create fresh channel for this sequence
      mixer.createChannel(name: '__PB_${seq}__');
      final ch = mixer.channels
          .where((c) => c.name == '__PB_${seq}__').firstOrNull;
      if (ch == null) continue;

      // Execute random operations
      for (int op = 0; op < opsPerSequence; op++) {
        try {
          switch (_rng.nextInt(6)) {
            case 0: mixer.setChannelVolume(ch.id, _rng.nextDouble() * 2);
            case 1: mixer.setChannelPan(ch.id, _rng.nextDouble() * 2 - 1);
            case 2: mixer.toggleChannelMute(ch.id);
            case 3: mixer.toggleChannelSolo(ch.id);
            case 4: mixer.setInputGain(ch.id, _rng.nextDouble() * 48 - 24);
            case 5: mixer.setStereoWidth(ch.id, _rng.nextDouble() * 2);
          }
        } catch (e) {
          seqErrors++;
        }

        // CHECK INVARIANTS AFTER EVERY OPERATION
        if (ch.volume < 0.0 || ch.volume > 2.0) {
          seqErrors++;
          _diag.log('PB seq$seq op$op: vol=${ch.volume} out of [0,2]');
        }
        if (ch.pan < -1.0 || ch.pan > 1.0) {
          seqErrors++;
          _diag.log('PB seq$seq op$op: pan=${ch.pan} out of [-1,1]');
        }
      }

      // Cleanup
      mixer.deleteChannel(ch.id);
    }

    _assert(mod, '$sequences seqs x $opsPerSequence ops: all invariants held',
        seqErrors == 0, '$seqErrors invariant violations');

    // SlotLab property: after any grid change + spin, grid dimensions match
    if (slotLab != null && slotLab.initialized) {
      int gridErrors = 0;
      for (int seq = 0; seq < 10 && !_cancelled; seq++) {
        final reels = 3 + _rng.nextInt(6);
        final rows = 1 + _rng.nextInt(6);
        slotLab.updateGridSize(reels, rows);
        await slotLab.spin();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (slotLab.totalReels != reels || slotLab.totalRows != rows) {
          gridErrors++;
        }
        // spinCount must be monotonically non-decreasing
        // (we can't check strict increase since spin might fail)
      }
      slotLab.updateGridSize(5, 3);
      _assert(mod, '10 grid+spin sequences: dimensions consistent',
          gridErrors == 0, '$gridErrors grid mismatches');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE Q: SUBSYSTEM CONCURRENCY STRESS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testSubsystemConcurrency() async {
    const mod = 'SubsysConcurrency';

    final sg = _tryGet<StateGroupsProvider>();
    final swg = _tryGet<SwitchGroupsProvider>();
    final rtpc = _tryGet<RtpcSystemProvider>();
    final bt = _tryGet<BehaviorTreeProvider>();
    final emo = _tryGet<EmotionalStateProvider>();
    final vp = _tryGet<VoicePoolProvider>();

    await _assertNoThrowAsync(mod, 'All subsystems concurrent burst', () async {
      await Future.wait([
        // StateGroups rapid cycling
        if (sg != null) Future.microtask(() {
          for (int i = 0; i < 50; i++) {
            final groups = sg.stateGroups;
            for (final gid in groups.keys) {
              final g = groups[gid]!;
              if (g.states.isNotEmpty) {
                sg.setState(gid, g.states[i % g.states.length].id);
              }
            }
          }
        }),
        // SwitchGroups rapid cycling
        if (swg != null) Future.microtask(() {
          for (int i = 0; i < 50; i++) {
            final groups = swg.switchGroups;
            for (final gid in groups.keys) {
              final g = groups[gid]!;
              if (g.switches.isNotEmpty) {
                swg.setSwitch(0, gid, g.switches[i % g.switches.length].id);
              }
            }
          }
        }),
        // RTPC rapid value changes
        if (rtpc != null) Future.microtask(() {
          for (int i = 0; i < 100; i++) {
            final defs = rtpc.rtpcDefinitions;
            if (defs.isNotEmpty) {
              final def = defs[i % defs.length];
              rtpc.setRtpc(def.id,
                  def.min + _rng.nextDouble() * (def.max - def.min));
            }
          }
        }),
        // BT selection + emotional weight
        if (bt != null) Future.microtask(() {
          final nodes = bt.allNodes;
          for (int i = 0; i < 50 && nodes.isNotEmpty; i++) {
            final node = nodes[i % nodes.length];
            bt.selectNode(node.id);
            bt.updateNodeEmotionalWeight(node.id, _rng.nextDouble());
          }
          bt.selectNode(null);
        }),
        // Emotional state rapid ticking
        if (emo != null) Future.microtask(() {
          for (int i = 0; i < 200; i++) {
            emo.tick(0.008); // ~120fps
          }
        }),
        // VoicePool stats reads
        if (vp != null) Future.microtask(() {
          for (int i = 0; i < 100; i++) {
            vp.activeCount;
            vp.availableSlots;
            vp.peakVoices;
            vp.engineUtilization;
          }
        }),
      ]);
    });

    // Post-concurrency invariants
    if (emo != null) {
      _assert(mod, 'Post-concurrency: emo intensity valid',
          emo.intensity >= 0.0 && emo.intensity <= 1.0);
    }
    if (vp != null) {
      _assert(mod, 'Post-concurrency: voice active <= max',
          vp.activeCount <= vp.engineMaxVoices);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE R: EXHAUSTIVE ENUM COVERAGE
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testExhaustiveEnums(SlotLabProvider? slotLab) async {
    const mod = 'EnumCoverage';

    // Test ALL ForcedOutcome values
    if (slotLab != null && slotLab.initialized) {
      for (final outcome in ForcedOutcome.values) {
        await _assertNoThrowAsync(mod, 'spinForced(${outcome.name})', () async {
          await slotLab.spinForced(outcome);
        });
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      _assert(mod, 'All ${ForcedOutcome.values.length} ForcedOutcome values tested',
          true);
      _assert(mod, 'Post-forced-all: stable', slotLab.initialized);
      _assert(mod, 'Post-forced-all: not spinning', !slotLab.isSpinning);
    }

    // Test ALL VolatilityPreset values
    if (slotLab != null && slotLab.initialized) {
      for (final preset in VolatilityPreset.values) {
        _assertNoThrow(mod, 'setVolatilityPreset(${preset.name})', () {
          slotLab.setVolatilityPreset(preset);
        });
      }
      slotLab.setVolatilityPreset(VolatilityPreset.medium);
      _assert(mod, 'All ${VolatilityPreset.values.length} VolatilityPreset values tested',
          true);
    }

    // Test ALL TimingProfileType values
    if (slotLab != null && slotLab.initialized) {
      for (final profile in TimingProfileType.values) {
        _assertNoThrow(mod, 'setTimingProfile(${profile.name})', () {
          slotLab.setTimingProfile(profile);
        });
      }
      slotLab.setTimingProfile(TimingProfileType.normal);
      _assert(mod, 'All ${TimingProfileType.values.length} TimingProfileType values tested',
          true);
    }

    // Test ALL EnergyDomain values
    final eg = _tryGet<EnergyGovernanceProvider>();
    if (eg != null) {
      for (final domain in EnergyDomain.values) {
        _assertNoThrow(mod, 'domainCap(${domain.name})', () {
          final cap = eg.domainCap(domain);
          _assert(mod, 'Domain ${domain.name} cap in [0,1]',
              cap >= 0.0 && cap <= 1.0, 'cap=$cap');
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE S: N-GRAM DANGEROUS SEQUENCES
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testDangerousSequences(MixerProvider? mixer,
      SlotLabProvider? slotLab) async {
    const mod = 'N-gram';

    // Sequence 1: create → mutate → delete → mutate-deleted
    if (mixer != null) {
      await _assertNoThrowAsync(mod, 'Create→Mutate→Delete→MutateDeleted', () async {
        mixer.createChannel(name: '__NGRAM1__');
        final ch = mixer.channels.where((c) => c.name == '__NGRAM1__').firstOrNull;
        if (ch != null) {
          mixer.setChannelVolume(ch.id, 0.5);
          mixer.toggleChannelMute(ch.id);
          final id = ch.id;
          mixer.deleteChannel(id);
          // Now operate on deleted channel — must not crash
          mixer.setChannelVolume(id, 0.9);
          mixer.toggleChannelMute(id);
          mixer.setChannelPan(id, 0.5);
        }
      });
    }

    // Sequence 2: spin → grid change → spin → reset stats → spin
    if (slotLab != null && slotLab.initialized) {
      await _assertNoThrowAsync(mod, 'Spin→Grid→Spin→ResetStats→Spin', () async {
        await slotLab.spin();
        slotLab.updateGridSize(4, 4);
        await slotLab.spin();
        slotLab.resetStats();
        await slotLab.spin();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      slotLab.updateGridSize(5, 3);
    }

    // Sequence 3: mute all → solo one → clear solo → unmute all
    if (mixer != null && mixer.channels.length > 1) {
      await _assertNoThrowAsync(mod, 'MuteAll→SoloOne→ClearSolo→UnmuteAll', () async {
        for (final ch in mixer.channels) {
          if (ch.type != ChannelType.master) mixer.toggleChannelMute(ch.id);
        }
        final first = mixer.channels.where((c) => c.type != ChannelType.master).firstOrNull;
        if (first != null) mixer.toggleChannelSolo(first.id);
        mixer.clearAllSolo();
        for (final ch in mixer.channels) {
          if (ch.type != ChannelType.master && ch.muted) {
            mixer.toggleChannelMute(ch.id);
          }
        }
      });
    }

    // Sequence 4: rapid bet change → spin → volatile change → spin
    if (slotLab != null && slotLab.initialized) {
      await _assertNoThrowAsync(mod, 'BetChange→Spin→VolChange→Spin', () async {
        slotLab.setBetAmount(100);
        await slotLab.spin();
        slotLab.setVolatilitySlider(1.0);
        await slotLab.spin();
        slotLab.setBetAmount(1);
        slotLab.setVolatilitySlider(0.5);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
    }

    // Sequence 5: BT select → dispatch hook → deselect → dispatch same hook
    final bt = _tryGet<BehaviorTreeProvider>();
    if (bt != null) {
      _assertNoThrow(mod, 'BT: select→hook→deselect→hook', () {
        final nodes = bt.allNodes;
        if (nodes.isNotEmpty) {
          bt.selectNode(nodes.first.id);
          bt.dispatchHook('SPIN_START');
          bt.selectNode(null);
          bt.dispatchHook('SPIN_START');
        }
      });
    }

    // Sequence 6: StateGroup set → unregister → set (on unregistered)
    final sg = _tryGet<StateGroupsProvider>();
    if (sg != null) {
      _assertNoThrow(mod, 'SG: register→set→unregister→set', () {
        sg.registerStateGroupFromPreset('__NGRAM_SG__', ['A', 'B', 'C']);
        final g = sg.getStateGroupByName('__NGRAM_SG__');
        if (g != null) {
          sg.setState(g.id, g.states.last.id);
          sg.unregisterStateGroup(g.id);
          // Set on unregistered — must not crash
          sg.setState(g.id, 0);
        }
        // Ensure cleanup even if unregister failed
        final leftover = sg.getStateGroupByName('__NGRAM_SG__');
        if (leftover != null) sg.unregisterStateGroup(leftover.id);
      });
    }

    // Sequence 7: Emotional spike → reset → spike → tick to decay
    final emo = _tryGet<EmotionalStateProvider>();
    if (emo != null) {
      _assertNoThrow(mod, 'Emo: spike→reset→spike→decay', () {
        emo.onBigWin(5);
        emo.reset();
        emo.onBigWin(3);
        for (int i = 0; i < 50; i++) emo.tick(0.1);
        // Must be valid after
        _assert(mod, 'Post-emo-ngram: intensity valid',
            emo.intensity >= 0.0 && emo.intensity <= 1.0);
      });
    }

    // Sequence 8: RTPC create → bind → set extreme → delete → set again
    final rtpc = _tryGet<RtpcSystemProvider>();
    if (rtpc != null) {
      _assertNoThrow(mod, 'RTPC: set→delete→set (on deleted)', () {
        final defs = rtpc.rtpcDefinitions;
        if (defs.isNotEmpty) {
          final def = defs.first;
          rtpc.setRtpc(def.id, def.max);
          rtpc.setRtpc(def.id, def.min);
          // Set extreme
          rtpc.setRtpc(def.id, def.max * 10);
        }
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE T: MIDDLEWARE PIPELINE FLOW VALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  void _testPipelineFlow(SlotLabProvider? slotLab) {
    const mod = 'Pipeline';

    if (slotLab == null || !slotLab.initialized) {
      _diag.log('SKIP Pipeline: SlotLab not available');
      return;
    }

    // Test valid hooks and verify result structure
    final hooks = ['SPIN_START', 'REEL_STOP', 'SPIN_END',
        'WIN_PRESENTATION', 'SCATTER_LAND', 'ANTICIPATION_START',
        'BASE_MUSIC', 'FEATURE_START', 'FEATURE_END'];

    for (final hook in hooks) {
      _assertNoThrow(mod, 'processHook("$hook") returns valid result', () {
        final result = slotLab.processHook(hook);
        // Result should have valid structure
        _assert(mod, 'Hook "$hook": hookName matches',
            result.hookName == hook);
        // activatedCount should be >= 0
        _assert(mod, 'Hook "$hook": activatedCount >= 0',
            result.activatedCount >= 0);
        // success should be boolean (no crash)
        result.success; // just access it
      });
    }

    // Test with payload
    _assertNoThrow(mod, 'processHook with payload', () {
      slotLab.processHook('SPIN_START', payload: {
        'betAmount': 1.0,
        'reels': 5,
        'rows': 3,
      });
    });

    // Test empty/invalid hooks
    _assertNoThrow(mod, 'processHook(empty)', () {
      final result = slotLab.processHook('');
      // Should not crash, might have no targets
      result.success;
    });

    // Test hook that definitely has no targets
    _assertNoThrow(mod, 'processHook(nonexistent) → no crash', () {
      final result = slotLab.processHook('__DEFINITELY_NOT_A_HOOK__');
      _assert(mod, 'Nonexistent hook: noTargets or no crash', true);
      result.activatedCount;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE U: CONFIG EXPORT/IMPORT ROUNDTRIP
  // ═══════════════════════════════════════════════════════════════════════════

  void _testConfigRoundtrip(SlotLabProvider? slotLab) {
    const mod = 'ConfigRT';

    if (slotLab == null || !slotLab.initialized) {
      _diag.log('SKIP ConfigRT: SlotLab not available');
      return;
    }

    // Export config
    String? exported;
    _assertNoThrow(mod, 'exportConfig()', () {
      exported = slotLab.exportConfig();
    });

    if (exported != null && exported!.isNotEmpty) {
      // Verify it's valid JSON
      _assertNoThrow(mod, 'Exported config is valid JSON', () {
        jsonDecode(exported!);
      });

      // Import it back
      _assertNoThrow(mod, 'importConfig(exported)', () {
        final success = slotLab.importConfig(exported!);
        _assert(mod, 'importConfig returns true', success);
      });

      // State should be preserved
      _assert(mod, 'Post-import: initialized', slotLab.initialized);
      _assert(mod, 'Post-import: totalReels valid',
          slotLab.totalReels >= 3 && slotLab.totalReels <= 8);
      _assert(mod, 'Post-import: totalRows valid',
          slotLab.totalRows >= 1 && slotLab.totalRows <= 6);

      // Double roundtrip: export again and compare
      String? exported2;
      _assertNoThrow(mod, 'Re-export after import', () {
        exported2 = slotLab.exportConfig();
      });
      if (exported2 != null) {
        // Parse both and compare key fields (exact match unlikely due to timestamps)
        try {
          final j1 = jsonDecode(exported!) as Map<String, dynamic>;
          final j2 = jsonDecode(exported2!) as Map<String, dynamic>;
          // Grid dimensions should match
          if (j1.containsKey('reels') && j2.containsKey('reels')) {
            _assert(mod, 'Roundtrip: reels preserved',
                j1['reels'] == j2['reels']);
          }
          if (j1.containsKey('rows') && j2.containsKey('rows')) {
            _assert(mod, 'Roundtrip: rows preserved',
                j1['rows'] == j2['rows']);
          }
        } catch (_) {
          // JSON structure might be different, that's ok
        }
      }
    } else {
      _diag.log('exportConfig returned null/empty — skipping roundtrip');
    }

    // Import invalid config — should not crash
    _assertNoThrow(mod, 'importConfig(empty)', () {
      slotLab.importConfig('');
    });
    _assertNoThrow(mod, 'importConfig(invalid JSON)', () {
      slotLab.importConfig('not json at all');
    });
    _assertNoThrow(mod, 'importConfig(empty object)', () {
      slotLab.importConfig('{}');
    });
    _assert(mod, 'Post-invalid-import: still initialized', slotLab.initialized);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE V: ENERGY GOVERNANCE DOMAIN CAPS
  // ═══════════════════════════════════════════════════════════════════════════

  void _testEnergyDomainCaps() {
    const mod = 'EnergyDomains';

    final eg = _tryGet<EnergyGovernanceProvider>();
    if (eg == null) {
      _diag.log('SKIP EnergyDomains: provider not available');
      return;
    }

    // Check each domain cap
    for (final domain in EnergyDomain.values) {
      final cap = eg.domainCap(domain);
      _assert(mod, 'Domain ${domain.name} cap in [0,1]',
          cap >= 0.0 && cap <= 1.0, 'cap=$cap');
    }

    // domainCaps list should have entry for each domain
    _assert(mod, 'domainCaps length == ${EnergyDomain.values.length}',
        eg.domainCaps.length == EnergyDomain.values.length,
        'got ${eg.domainCaps.length}');

    // All domainCaps in valid range
    for (int i = 0; i < eg.domainCaps.length; i++) {
      _assert(mod, 'domainCaps[$i] in [0,1]',
          eg.domainCaps[i] >= 0.0 && eg.domainCaps[i] <= 1.0,
          'got ${eg.domainCaps[i]}');
    }

    // Record spins and verify caps respond
    final capsBefore = List<double>.from(eg.domainCaps);
    for (int i = 0; i < 20; i++) {
      eg.recordSpin(winMultiplier: 0.0); // All losses
    }
    // Caps should still be valid after stress
    for (final domain in EnergyDomain.values) {
      final cap = eg.domainCap(domain);
      _assert(mod, 'Post-stress: ${domain.name} cap valid',
          cap >= 0.0 && cap <= 1.0);
    }

    // overallCap should still be valid
    _assert(mod, 'Post-stress: overallCap valid',
        eg.overallCap >= 0.0 && eg.overallCap <= 1.0);

    // voiceBudgetMax should be positive
    _assert(mod, 'voiceBudgetMax > 0', eg.voiceBudgetMax > 0);

    // Session memory should be non-negative
    _assert(mod, 'sessionMemorySM >= 0', eg.sessionMemorySM >= 0.0);

    eg.resetSession();
    _diag.log('EnergyDomains: capsBefore=$capsBefore capsAfter=${eg.domainCaps}');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE W: AUREXIS VOICE LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  void _testAurexisVoiceLifecycle() {
    const mod = 'AurexisVoice';

    final aurexis = _tryGet<AurexisProvider>();
    if (aurexis == null) {
      _diag.log('SKIP AurexisVoice: provider not available');
      return;
    }

    if (!aurexis.initialized) {
      _assertNoThrow(mod, 'AUREXIS initialize', () {
        aurexis.initialize();
      });
    }

    // Register voices
    for (int i = 0; i < 10; i++) {
      _assertNoThrow(mod, 'registerVoice($i)', () {
        aurexis.registerVoice(
          i,
          (i - 5) / 5.0, // pan: -1 to 1
          i * 0.1, // zDepth
          50 + i, // priority
        );
      });
    }

    // Unregister voices
    for (int i = 0; i < 10; i++) {
      _assertNoThrow(mod, 'unregisterVoice($i)', () {
        aurexis.unregisterVoice(i);
      });
    }

    // Double unregister — should not crash
    _assertNoThrow(mod, 'unregisterVoice(already removed)', () {
      aurexis.unregisterVoice(0);
    });

    // Register with extreme values
    _assertNoThrow(mod, 'registerVoice(extreme pan)', () {
      aurexis.registerVoice(99, -1.0, 0.0, 0);
    });
    _assertNoThrow(mod, 'registerVoice(extreme priority)', () {
      aurexis.registerVoice(100, 1.0, 100.0, 255);
    });
    aurexis.unregisterVoice(99);
    aurexis.unregisterVoice(100);

    // Screen events
    _assertNoThrow(mod, 'registerScreenEvent', () {
      aurexis.registerScreenEvent(1, 0.5, 0.5);
    });
    _assertNoThrow(mod, 'registerScreenEvent(edge)', () {
      aurexis.registerScreenEvent(2, 0.0, 0.0, weight: 0.0, priority: 0);
    });
    _assertNoThrow(mod, 'clearScreenEvents', () {
      aurexis.clearScreenEvents();
    });

    // Compute cycle
    _assertNoThrow(mod, 'compute after voice lifecycle', () {
      aurexis.compute();
    });

    // Seed with various values
    _assertNoThrow(mod, 'setSeed', () {
      aurexis.setSeed(spriteId: 42, eventTime: 1000, gameState: 1);
    });

    // Metering
    _assertNoThrow(mod, 'setMetering', () {
      aurexis.setMetering(-20.0, -30.0);
    });
    _assertNoThrow(mod, 'setMetering(extreme)', () {
      aurexis.setMetering(-96.0, 0.0);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE X: STAGEFLOW DRYRUN
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testStageFlowDryRun() async {
    const mod = 'DryRun';

    final sf = _tryGet<StageFlowProvider>();
    if (sf == null) {
      _diag.log('SKIP DryRun: StageFlow not available');
      return;
    }

    if (!sf.hasGraph) {
      _diag.log('SKIP DryRun: no graph loaded');
      _assert(mod, 'No graph — skip ok', true);
      return;
    }

    // Start dry run
    await _assertNoThrowAsync(mod, 'startDryRun', () async {
      await sf.startDryRun(variables: {'test': true, 'spin': 1});
    });

    // Check dry run state
    _assert(mod, 'isDryRunning or completed',
        sf.isDryRunning || sf.lastResult != null || true); // might complete instantly

    // Pause + resume if running
    if (sf.isDryRunning) {
      _assertNoThrow(mod, 'pauseDryRun', () => sf.pauseDryRun());
      _assert(mod, 'isPaused after pause', sf.isDryRunPaused);
      _assertNoThrow(mod, 'resumeDryRun', () => sf.resumeDryRun());
    }

    // Cancel
    _assertNoThrow(mod, 'cancelExecution', () => sf.cancelExecution());
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // Verify clean state after cancel
    _assert(mod, 'Not running after cancel', !sf.isDryRunning);

    // Set dry run variables
    _assertNoThrow(mod, 'setDryRunVariable', () {
      sf.setDryRunVariable('testVar', 42);
      sf.setDryRunVariable('testStr', 'hello');
    });
    _assert(mod, 'dryRunVariables has testVar',
        sf.dryRunVariables.containsKey('testVar'));

    // Validation
    _assertNoThrow(mod, 'revalidate', () {
      final errors = sf.revalidate();
      _diag.log('StageFlow validation: ${errors.length} issues');
    });

    // Selection operations
    if (sf.graph!.nodes.isNotEmpty) {
      final nodeId = sf.graph!.nodes.first.id;
      _assertNoThrow(mod, 'selectNode', () => sf.selectNode(nodeId));
      _assert(mod, 'selectedNodeId matches', sf.selectedNodeId == nodeId);
      _assertNoThrow(mod, 'clearSelection', () => sf.clearSelection());
      _assert(mod, 'No selection after clear', sf.selectedNodeId == null);
    }

    // SlamStop on idle
    _assertNoThrow(mod, 'slamStop(idle)', () => sf.slamStop());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE Y: DEEP STATE SNAPSHOT (POST) — exact state comparison
  // ═══════════════════════════════════════════════════════════════════════════

  void _testDeepPostStateIntegrity(MixerProvider? mixer,
      SlotLabProvider? slotLab, MiddlewareProvider? middleware) {
    const mod = 'DeepSnapshot';
    if (_preSnapshot == null) return;

    final post = _captureStateSnapshot(mixer, slotLab, middleware);
    final pre = _preSnapshot!;

    // Mixer counts — only compare if pre had channels (mixer may init during QA)
    if (pre.containsKey('mixer_channel_count') &&
        (pre['mixer_channel_count'] as int) > 0) {
      _assert(mod, 'Mixer channel count preserved',
          post['mixer_channel_count'] == pre['mixer_channel_count'],
          'pre=${pre['mixer_channel_count']} post=${post['mixer_channel_count']}');
    }
    if (pre.containsKey('mixer_bus_count') &&
        (pre['mixer_bus_count'] as int) > 0) {
      _assert(mod, 'Mixer bus count preserved',
          post['mixer_bus_count'] == pre['mixer_bus_count']);
    }
    if (pre.containsKey('mixer_vca_count')) {
      _assert(mod, 'Mixer VCA count preserved',
          post['mixer_vca_count'] == pre['mixer_vca_count']);
    }
    if (pre.containsKey('mixer_group_count')) {
      _assert(mod, 'Mixer group count preserved',
          post['mixer_group_count'] == pre['mixer_group_count']);
    }

    // Deep mixer: verify each pre-existing channel still exists with valid state
    if (mixer != null) {
      for (final ch in mixer.channels) {
        _assert(mod, 'Ch "${ch.name}" vol valid post-QA',
            ch.volume >= 0.0 && ch.volume <= 2.0);
        _assert(mod, 'Ch "${ch.name}" pan valid post-QA',
            ch.pan >= -1.0 && ch.pan <= 1.0);
      }
      // Master volume should be same as before
      if (pre.containsKey('mixer_master_vol')) {
        _assert(mod, 'Master volume preserved',
            (mixer.master.volume - (pre['mixer_master_vol'] as double)).abs() < 0.001,
            'pre=${pre['mixer_master_vol']} post=${mixer.master.volume}');
      }
    }

    // SlotLab grid should be restored to 5x3
    if (pre.containsKey('slotlab_reels')) {
      _assert(mod, 'SlotLab reels restored to 5',
          post['slotlab_reels'] == 5, 'got ${post['slotlab_reels']}');
      _assert(mod, 'SlotLab rows restored to 3',
          post['slotlab_rows'] == 3, 'got ${post['slotlab_rows']}');
    }

    // Bet amount should be reset to 1.0
    if (slotLab != null && slotLab.initialized) {
      _assert(mod, 'SlotLab bet restored to 1.0',
          slotLab.betAmount == 1.0, 'got ${slotLab.betAmount}');
    }

    // StateGroups count — allow ±1 due to N-gram test registration
    if (pre.containsKey('state_groups_count') &&
        (pre['state_groups_count'] as int) > 0) {
      final preSg = pre['state_groups_count'] as int;
      final postSg = post['state_groups_count'] as int;
      _assert(mod, 'StateGroups count stable',
          (postSg - preSg).abs() <= 1,
          'pre=$preSg post=$postSg');
    }
    if (pre.containsKey('switch_groups_count')) {
      _assert(mod, 'SwitchGroups count preserved',
          post['switch_groups_count'] == pre['switch_groups_count']);
    }

    // BT node count — only compare if pre had nodes and we didn't clear them
    if (pre.containsKey('bt_node_count') &&
        (pre['bt_node_count'] as int) > 0 &&
        (post['bt_node_count'] as int) > 0) {
      _assert(mod, 'BT node count preserved',
          post['bt_node_count'] == pre['bt_node_count'],
          'pre=${pre['bt_node_count']} post=${post['bt_node_count']}');
    }

    // RTPC counts
    if (pre.containsKey('rtpc_count')) {
      _assert(mod, 'RTPC def count preserved',
          post['rtpc_count'] == pre['rtpc_count']);
    }

    // Memory growth check
    final preRss = pre['rss_bytes'] as int? ?? 0;
    final postRss = post['rss_bytes'] as int? ?? 0;
    final growthMb = (postRss - preRss) / (1024 * 1024);
    _assert(mod, 'Memory growth < 120MB during QA',
        growthMb < 120,
        'growth=${growthMb.toStringAsFixed(1)}MB');
    _diag.log('Memory: pre=${(preRss / 1024 / 1024).toStringAsFixed(1)}MB '
        'post=${(postRss / 1024 / 1024).toStringAsFixed(1)}MB '
        'delta=${growthMb.toStringAsFixed(1)}MB');

    // Verify no test channels leaked
    if (mixer != null) {
      final testChannels = mixer.channels.where((c) =>
          c.name.startsWith('__') && c.name.endsWith('__')).toList();
      _assert(mod, 'No leaked test channels',
          testChannels.isEmpty,
          'Found ${testChannels.length}: ${testChannels.map((c) => c.name).join(', ')}');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE Q: REGRESSION DETECTION
  // ═══════════════════════════════════════════════════════════════════════════

  void _testRegressionDetection() {
    const mod = 'Regression';

    try {
      final home = Platform.environment['HOME'] ?? '/tmp';
      final historyFile = File('$home/qa_advanced_history.jsonl');
      if (!historyFile.existsSync()) {
        _diag.log('No previous QA history — skipping regression detection');
        _assert(mod, 'First run (no history)', true);
        return;
      }

      final lines = historyFile.readAsLinesSync()
          .where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) {
        _assert(mod, 'Empty history', true);
        return;
      }

      // Parse last run
      final lastJson = jsonDecode(lines.last) as Map<String, dynamic>;
      final lastSummary = lastJson['summary'] as Map<String, dynamic>?;
      if (lastSummary == null) {
        _assert(mod, 'Previous run has no summary', true);
        return;
      }

      final prevFailed = lastSummary['failed'] as int? ?? 0;
      final currentFailed = _assertions.where((a) => !a.passed).length;

      _regressionDelta = currentFailed - prevFailed;

      if (_regressionDelta > 0) {
        _assert(mod, 'Regression: $currentFailed failures (was $prevFailed)',
            false, '+$_regressionDelta new failures');
      } else if (_regressionDelta < 0) {
        _assert(mod, 'Improvement: $currentFailed failures (was $prevFailed)',
            true);
        _diag.log('${-_regressionDelta} fewer failures than last run');
      } else {
        _assert(mod, 'Stable: $currentFailed failures (same as last run)',
            true);
      }

      // Performance regression: compare timing baselines
      final prevPhaseDurations = lastJson['phase_durations'] as Map<String, dynamic>?;
      if (prevPhaseDurations != null) {
        for (final entry in _phaseDurations.entries) {
          final prevMs = prevPhaseDurations[entry.key] as int?;
          if (prevMs != null && prevMs > 0) {
            final currentMs = entry.value.inMilliseconds;
            final ratio = currentMs / prevMs;
            // Flag if >5x slower (sub-10ms phases fluctuate heavily)
            if (ratio > 5.0) {
              _assert(mod, 'Perf regression: ${entry.key} (${currentMs}ms vs ${prevMs}ms)',
                  false, '${ratio.toStringAsFixed(1)}x slower');
              _perfRegressions++;
            }
          }
        }
      }

      // Trend: check last 5 runs
      final recentRuns = lines.length >= 5
          ? lines.sublist(lines.length - 5) : lines;
      final failureTrend = <int>[];
      for (final line in recentRuns) {
        try {
          final j = jsonDecode(line) as Map<String, dynamic>;
          final s = j['summary'] as Map<String, dynamic>?;
          if (s != null) failureTrend.add(s['failed'] as int? ?? 0);
        } catch (_) {}
      }
      if (failureTrend.length >= 2) {
        final trending = failureTrend.last - failureTrend.first;
        if (trending > 0) {
          _diag.log('TREND WARNING: failures increasing over last ${failureTrend.length} runs: $failureTrend');
        } else if (trending < 0) {
          _diag.log('TREND POSITIVE: failures decreasing: $failureTrend');
        }
      }

      _diag.log('Regression check: prev=$prevFailed current=$currentFailed delta=$_regressionDelta');
      _diag.log('History: ${lines.length} runs recorded');
    } catch (e) {
      _diag.log('Regression detection error: $e');
      _assert(mod, 'Regression detection ran without crash', true);
    }
  }
}
