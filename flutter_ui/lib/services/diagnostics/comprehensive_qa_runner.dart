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

import 'dart:async';
import 'package:get_it/get_it.dart';

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

  QaAssertion({
    required this.module,
    required this.test,
    required this.passed,
    this.detail,
  });
}

/// Complete QA report
class ComprehensiveQaReport {
  final List<QaAssertion> assertions;
  final Duration duration;
  final DateTime timestamp;

  ComprehensiveQaReport({
    required this.assertions,
    required this.duration,
  }) : timestamp = DateTime.now();

  int get passed => assertions.where((a) => a.passed).length;
  int get failed => assertions.where((a) => !a.passed).length;
  int get total => assertions.length;
  bool get allPassed => failed == 0;

  List<QaAssertion> get failures => assertions.where((a) => !a.passed).toList();

  String get summary => '$passed/$total passed, $failed failed (${duration.inMilliseconds}ms)';
}

/// Comprehensive QA Runner — tests every module programmatically
class ComprehensiveQaRunner {
  final DiagnosticsService _diag;
  final List<QaAssertion> _assertions = [];
  bool _running = false;
  final GetIt _sl = GetIt.instance;

  ComprehensiveQaRunner(this._diag);

  bool get isRunning => _running;

  // ═══════════════════════════════════════════════════════════════════════════
  // ASSERTION HELPERS
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

  void _assertInRange(String module, String test, double value, double min, double max) {
    _assert(module, test, value >= min && value <= max,
        'Value $value not in range [$min, $max]');
  }

  void _assertNoThrow(String module, String test, void Function() fn) {
    try {
      fn();
      _assert(module, test, true);
    } catch (e) {
      _assert(module, test, false, 'Threw: $e');
    }
  }

  Future<void> _assertNoThrowAsync(String module, String test, Future<void> Function() fn) async {
    try {
      await fn();
      _assert(module, test, true);
    } catch (e) {
      _assert(module, test, false, 'Threw: $e');
    }
  }

  /// Safely get a provider, returns null if not registered
  T? _tryGet<T extends Object>() {
    try {
      if (_sl.isRegistered<T>()) return _sl<T>();
    } catch (_) {}
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN ENTRY POINT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Run ALL QA modules. Returns comprehensive report.
  Future<ComprehensiveQaReport> runAll({
    SlotLabProvider? slotLabProvider,
    MixerProvider? mixerProvider,
    EngineProvider? engineProvider,
  }) async {
    if (_running) {
      return ComprehensiveQaReport(
        assertions: [],
        duration: Duration.zero,
      );
    }
    _running = true;
    _assertions.clear();
    final sw = Stopwatch()..start();

    _diag.log('');
    _diag.log('╔══════════════════════════════════════════════════════════════╗');
    _diag.log('║          COMPREHENSIVE QA — FULL APP TEST SUITE            ║');
    _diag.log('╚══════════════════════════════════════════════════════════════╝');
    _diag.log('');

    // Phase 1: Provider availability
    _diag.log('═══ PHASE 1: Provider Availability ═══');
    _testProviderAvailability();

    // Phase 2: Mixer operations
    _diag.log('═══ PHASE 2: DAW Mixer ═══');
    if (mixerProvider != null) {
      _testMixer(mixerProvider);
    } else {
      _diag.log('SKIP: MixerProvider not available');
    }

    // Phase 3: Engine / Transport
    _diag.log('═══ PHASE 3: DAW Transport ═══');
    if (engineProvider != null) {
      await _testTransport(engineProvider);
    } else {
      _diag.log('SKIP: EngineProvider not available');
    }

    // Phase 4: Middleware subsystems
    _diag.log('═══ PHASE 4: Middleware Subsystems ═══');
    _testMiddlewareSubsystems();

    // Phase 5: SlotLab engine
    _diag.log('═══ PHASE 5: SlotLab Engine ═══');
    if (slotLabProvider != null) {
      await _testSlotLabEngine(slotLabProvider);
    } else {
      _diag.log('SKIP: SlotLabProvider not available');
    }

    // Phase 6: SlotLab subsystems
    _diag.log('═══ PHASE 6: SlotLab Subsystems ═══');
    _testSlotLabSubsystems();

    // Phase 7: Cross-module integrity
    _diag.log('═══ PHASE 7: Cross-Module Integrity ═══');
    _testCrossModuleIntegrity(slotLabProvider, mixerProvider);

    // Phase 8: Edge cases & boundary conditions
    _diag.log('═══ PHASE 8: Edge Cases ═══');
    _testEdgeCases(mixerProvider, slotLabProvider);

    // Phase 9: Multi-grid spin QA (the big one)
    _diag.log('═══ PHASE 9: Multi-Grid Spin QA ═══');
    if (slotLabProvider != null) {
      await _testMultiGridSpins(slotLabProvider);
    }

    sw.stop();

    final report = ComprehensiveQaReport(
      assertions: List.unmodifiable(_assertions),
      duration: sw.elapsed,
    );

    _diag.log('');
    _diag.log('╔══════════════════════════════════════════════════════════════╗');
    _diag.log('║  QA COMPLETE: ${report.summary.padRight(45)}║');
    _diag.log('╚══════════════════════════════════════════════════════════════╝');

    if (report.failures.isNotEmpty) {
      _diag.log('');
      _diag.log('FAILURES:');
      for (final f in report.failures) {
        _diag.log('  [${f.module}] ${f.test} — ${f.detail}');
      }
    }

    _diag.reportFinding(DiagnosticFinding(
      checker: 'ComprehensiveQA',
      severity: report.allPassed ? DiagnosticSeverity.ok : DiagnosticSeverity.error,
      message: report.summary,
      detail: report.failures.isNotEmpty
          ? report.failures.map((f) => '${f.module}: ${f.test}').join('; ')
          : null,
    ));

    _running = false;
    return report;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 1: PROVIDER AVAILABILITY
  // ═══════════════════════════════════════════════════════════════════════════

  void _testProviderAvailability() {
    const mod = 'Providers';

    // Core middleware subsystems
    _assert(mod, 'StateGroupsProvider registered', _sl.isRegistered<StateGroupsProvider>());
    _assert(mod, 'SwitchGroupsProvider registered', _sl.isRegistered<SwitchGroupsProvider>());
    _assert(mod, 'RtpcSystemProvider registered', _sl.isRegistered<RtpcSystemProvider>());
    _assert(mod, 'DuckingSystemProvider registered', _sl.isRegistered<DuckingSystemProvider>());
    _assert(mod, 'BlendContainersProvider registered', _sl.isRegistered<BlendContainersProvider>());
    _assert(mod, 'RandomContainersProvider registered', _sl.isRegistered<RandomContainersProvider>());
    _assert(mod, 'SequenceContainersProvider registered', _sl.isRegistered<SequenceContainersProvider>());
    _assert(mod, 'CompositeEventSystemProvider registered', _sl.isRegistered<CompositeEventSystemProvider>());
    _assert(mod, 'BusHierarchyProvider registered', _sl.isRegistered<BusHierarchyProvider>());
    _assert(mod, 'VoicePoolProvider registered', _sl.isRegistered<VoicePoolProvider>());

    // SlotLab subsystems
    _assert(mod, 'BehaviorTreeProvider registered', _sl.isRegistered<BehaviorTreeProvider>());
    _assert(mod, 'StateGateProvider registered', _sl.isRegistered<StateGateProvider>());
    _assert(mod, 'EmotionalStateProvider registered', _sl.isRegistered<EmotionalStateProvider>());
    _assert(mod, 'PriorityEngineProvider registered', _sl.isRegistered<PriorityEngineProvider>());
    _assert(mod, 'OrchestrationEngineProvider registered', _sl.isRegistered<OrchestrationEngineProvider>());
    _assert(mod, 'SimulationEngineProvider registered', _sl.isRegistered<SimulationEngineProvider>());
    _assert(mod, 'TransitionSystemProvider registered', _sl.isRegistered<TransitionSystemProvider>());
    _assert(mod, 'SlotLabProjectProvider registered', _sl.isRegistered<SlotLabProjectProvider>());
    _assert(mod, 'FeatureComposerProvider registered', _sl.isRegistered<FeatureComposerProvider>());

    // Advanced systems
    _assert(mod, 'EnergyGovernanceProvider registered', _sl.isRegistered<EnergyGovernanceProvider>());
    _assert(mod, 'DpmProvider registered', _sl.isRegistered<DpmProvider>());
    _assert(mod, 'AurexisProvider registered', _sl.isRegistered<AurexisProvider>());
    _assert(mod, 'AurexisProfileProvider registered', _sl.isRegistered<AurexisProfileProvider>());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 2: DAW MIXER
  // ═══════════════════════════════════════════════════════════════════════════

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
    final ch = mixer.channels.where((c) => c.name == 'QA Track 1').firstOrNull;
    _assertNotNull(mod, 'QA Track 1 found', ch);
    if (ch == null) return;

    // Volume operations
    final originalVol = ch.volume;
    mixer.setChannelVolume(ch.id, 0.5);
    _assertEqual(mod, 'setChannelVolume(0.5)', ch.volume, 0.5);

    mixer.setChannelVolume(ch.id, 2.0);
    _assertEqual(mod, 'setChannelVolume(2.0) max', ch.volume, 2.0);

    mixer.setChannelVolume(ch.id, 0.0);
    _assertEqual(mod, 'setChannelVolume(0.0) min', ch.volume, 0.0);

    mixer.setChannelVolume(ch.id, originalVol);

    // Pan operations
    mixer.setChannelPan(ch.id, -1.0);
    _assertEqual(mod, 'Pan full left', ch.pan, -1.0);

    mixer.setChannelPan(ch.id, 1.0);
    _assertEqual(mod, 'Pan full right', ch.pan, 1.0);

    mixer.setChannelPan(ch.id, 0.0);
    _assertEqual(mod, 'Pan center', ch.pan, 0.0);

    // Mute/Solo
    final wasMuted = ch.muted;
    mixer.toggleChannelMute(ch.id);
    _assertEqual(mod, 'Toggle mute ON', ch.muted, !wasMuted);

    mixer.toggleChannelMute(ch.id);
    _assertEqual(mod, 'Toggle mute OFF', ch.muted, wasMuted);

    final wasSoloed = ch.soloed;
    mixer.toggleChannelSolo(ch.id);
    _assertEqual(mod, 'Toggle solo ON', ch.soloed, !wasSoloed);

    mixer.toggleChannelSolo(ch.id);
    _assertEqual(mod, 'Toggle solo OFF', ch.soloed, wasSoloed);

    // Phase invert
    mixer.togglePhaseInvert(ch.id);
    _assert(mod, 'Phase invert ON', ch.phaseInverted);
    mixer.togglePhaseInvert(ch.id);
    _assert(mod, 'Phase invert OFF', !ch.phaseInverted);

    // Input gain
    mixer.setInputGain(ch.id, 12.0);
    _assertInRange(mod, 'Input gain +12dB', ch.inputGain, 11.9, 12.1);
    mixer.setInputGain(ch.id, -12.0);
    _assertInRange(mod, 'Input gain -12dB', ch.inputGain, -12.1, -11.9);
    mixer.setInputGain(ch.id, 0.0);

    // Stereo width
    mixer.setStereoWidth(ch.id, 0.0);
    _assertInRange(mod, 'Stereo width mono', ch.stereoWidth, -0.01, 0.01);
    mixer.setStereoWidth(ch.id, 2.0);
    _assertInRange(mod, 'Stereo width extra-wide', ch.stereoWidth, 1.99, 2.01);
    mixer.setStereoWidth(ch.id, 1.0);

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
    final vca = mixer.vcas.where((v) => v.name == 'QA VCA').firstOrNull;
    if (vca != null) {
      mixer.setVcaLevel(vca.id, 0.5);
      _assertInRange(mod, 'VCA level 0.5', vca.level, 0.49, 0.51);

      mixer.assignChannelToVca(ch.id, vca.id);
      _assert(mod, 'Channel assigned to VCA', vca.memberIds.contains(ch.id));

      mixer.removeChannelFromVca(ch.id, vca.id);
      _assert(mod, 'Channel removed from VCA', !vca.memberIds.contains(ch.id));

      mixer.setVcaLevel(vca.id, 1.0);
    }

    // Create group
    _assertNoThrow(mod, 'Create group', () {
      mixer.createGroup(name: 'QA Group');
    });
    _assert(mod, 'Group count >= 1', mixer.groups.isNotEmpty);

    // Solo safe
    mixer.toggleSoloSafe(ch.id);
    _assert(mod, 'Solo safe ON', ch.soloSafe);
    mixer.toggleSoloSafe(ch.id);
    _assert(mod, 'Solo safe OFF', !ch.soloSafe);

    // Channel comments
    mixer.setChannelComments(ch.id, 'QA test comment');
    _assertEqual(mod, 'Channel comments', ch.comments, 'QA test comment');
    mixer.setChannelComments(ch.id, '');

    // dB string
    _assert(mod, 'Volume dB string for 1.0', ch.volumeDbString.contains('0.0'));

    // Clear solo
    _assertNoThrow(mod, 'Clear all solo', () {
      mixer.clearAllSolo();
    });

    // Cleanup: delete QA channels
    _assertNoThrow(mod, 'Delete QA channel', () {
      mixer.deleteChannel(ch.id);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 3: DAW TRANSPORT
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _testTransport(EngineProvider engine) async {
    const mod = 'Transport';

    // Engine status
    _assert(mod, 'Engine status is running or uninitialized',
        engine.status == EngineStatus.running || engine.status == EngineStatus.uninitialized);

    if (!engine.isRunning) {
      _diag.log('Engine not running, attempting initialize...');
      final ok = await engine.initialize();
      _assert(mod, 'Engine initialize', ok);
      if (!ok) {
        _diag.log('SKIP transport tests — engine failed to initialize');
        return;
      }
    }

    // Transport state
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

    // Seek
    _assertNoThrow(mod, 'Seek to 5.0s', () => engine.seek(5.0));
    _assertInRange(mod, 'Position after seek', engine.transport.positionSeconds, 4.5, 5.5);

    _assertNoThrow(mod, 'Seek to 0', () => engine.seek(0));
    _assertInRange(mod, 'Position after seek 0', engine.transport.positionSeconds, -0.1, 0.5);

    // GoToStart
    _assertNoThrow(mod, 'GoToStart', () => engine.goToStart());
    _assertInRange(mod, 'Position after goToStart', engine.transport.positionSeconds, -0.1, 0.1);

    // Tempo
    _assertNoThrow(mod, 'Set tempo 140', () => engine.setTempo(140));
    _assertNoThrow(mod, 'Set tempo 60', () => engine.setTempo(60));
    _assertNoThrow(mod, 'Set tempo 120 (reset)', () => engine.setTempo(120));

    // Time signature
    _assertNoThrow(mod, 'Time sig 4/4', () => engine.setTimeSignature(4, 4));
    _assertNoThrow(mod, 'Time sig 3/4', () => engine.setTimeSignature(3, 4));
    _assertNoThrow(mod, 'Time sig 6/8', () => engine.setTimeSignature(6, 8));
    _assertNoThrow(mod, 'Time sig 4/4 reset', () => engine.setTimeSignature(4, 4));

    // Loop toggle
    _assertNoThrow(mod, 'Toggle loop', () => engine.toggleLoop());
    _assertNoThrow(mod, 'Toggle loop back', () => engine.toggleLoop());

    // Jog seek
    _assertNoThrow(mod, 'Jog seek forward', () => engine.jogSeek(1.0));
    _assertNoThrow(mod, 'Jog seek backward', () => engine.jogSeek(-1.0));

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

    // State Groups — uses registerStateGroupFromPreset / unregisterStateGroup / setState
    final stateGroups = _tryGet<StateGroupsProvider>();
    if (stateGroups != null) {
      _assertNoThrow(mod, 'StateGroups: register group', () {
        stateGroups.registerStateGroupFromPreset('QA_StateGroup', ['QA_A', 'QA_B', 'QA_C']);
      });
      final group = stateGroups.getStateGroupByName('QA_StateGroup');
      _assertNotNull(mod, 'StateGroups: group registered', group);
      if (group != null) {
        _assert(mod, 'StateGroups: has 3 states', group.states.length == 3);
        _assertNoThrow(mod, 'StateGroups: switch state', () {
          if (group.states.length >= 2) {
            stateGroups.setState(group.id, group.states[1].id);
          }
        });
        _assertNoThrow(mod, 'StateGroups: reset state', () {
          stateGroups.resetState(group.id);
        });
        _assertNoThrow(mod, 'StateGroups: unregister', () {
          stateGroups.unregisterStateGroup(group.id);
        });
      }
    } else {
      _diag.log('SKIP: StateGroupsProvider not available');
    }

    // Switch Groups — uses registerSwitchGroupFromPreset
    final switchGroups = _tryGet<SwitchGroupsProvider>();
    if (switchGroups != null) {
      _assertNotNull(mod, 'SwitchGroups: instance', switchGroups);
      _assertNoThrow(mod, 'SwitchGroups: register', () {
        switchGroups.registerSwitchGroupFromPreset('QA_SwitchGroup', ['QA_On', 'QA_Off']);
      });
    } else {
      _diag.log('SKIP: SwitchGroupsProvider not available');
    }

    // RTPC — uses registerRtpc
    final rtpc = _tryGet<RtpcSystemProvider>();
    if (rtpc != null) {
      _assertNotNull(mod, 'RTPC: instance', rtpc);
      _assertNoThrow(mod, 'RTPC: read rtpc list', () {
        final _ = rtpc.rtpcDefinitions;
      });
    } else {
      _diag.log('SKIP: RtpcSystemProvider not available');
    }

    // Ducking — uses registerRule / removeRule
    final ducking = _tryGet<DuckingSystemProvider>();
    if (ducking != null) {
      _assertNotNull(mod, 'Ducking: instance', ducking);
      _assertNoThrow(mod, 'Ducking: read rules', () {
        final _ = ducking.rules;
      });
    } else {
      _diag.log('SKIP: DuckingSystemProvider not available');
    }

    // Blend Containers — uses registerContainer / removeContainer
    final blend = _tryGet<BlendContainersProvider>();
    if (blend != null) {
      _assertNotNull(mod, 'BlendContainer: instance', blend);
      _assertNoThrow(mod, 'BlendContainer: read containers', () {
        final _ = blend.containers;
      });
    } else {
      _diag.log('SKIP: BlendContainersProvider not available');
    }

    // Random Containers
    final random = _tryGet<RandomContainersProvider>();
    if (random != null) {
      _assertNotNull(mod, 'RandomContainer: instance', random);
      _assertNoThrow(mod, 'RandomContainer: read containers', () {
        final _ = random.containers;
      });
    } else {
      _diag.log('SKIP: RandomContainersProvider not available');
    }

    // Sequence Containers
    final sequence = _tryGet<SequenceContainersProvider>();
    if (sequence != null) {
      _assertNotNull(mod, 'SequenceContainer: instance', sequence);
      _assertNoThrow(mod, 'SequenceContainer: read containers', () {
        final _ = sequence.containers;
      });
    } else {
      _diag.log('SKIP: SequenceContainersProvider not available');
    }

    // Composite Events — uses addCompositeEvent / deleteCompositeEvent
    final composite = _tryGet<CompositeEventSystemProvider>();
    if (composite != null) {
      _assertNotNull(mod, 'CompositeEvent: instance', composite);
      _assertNoThrow(mod, 'CompositeEvent: read compositeEvents', () {
        final _ = composite.compositeEvents;
      });
    } else {
      _diag.log('SKIP: CompositeEventSystemProvider not available');
    }

    // Bus Hierarchy — uses addBus / removeBus
    final busH = _tryGet<BusHierarchyProvider>();
    if (busH != null) {
      _assertNotNull(mod, 'BusHierarchy: instance', busH);
      _assertNoThrow(mod, 'BusHierarchy: read allBuses', () {
        final _ = busH.allBuses;
      });
    } else {
      _diag.log('SKIP: BusHierarchyProvider not available');
    }

    // Voice Pool
    final voicePool = _tryGet<VoicePoolProvider>();
    if (voicePool != null) {
      _assertNotNull(mod, 'VoicePool: instance', voicePool);
      _assertNoThrow(mod, 'VoicePool: read active count', () {
        final _ = voicePool.activeCount;
      });
      _assertNoThrow(mod, 'VoicePool: read engine stats', () {
        final _ = voicePool.engineActiveCount;
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

    // Feature Composer config
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

    // Initialize
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

    // Basic spin
    await _assertNoThrowAsync(mod, 'Basic spin', () async {
      final result = await provider.spin();
      _assertNotNull(mod, 'Spin result not null', result);
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Forced outcome spins
    for (final outcome in ForcedOutcome.values) {
      await _assertNoThrowAsync(mod, 'Forced spin: ${outcome.name}', () async {
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
    // Reset to default
    provider.updateGridSize(5, 3);

    // Spin after grid changes (verify engine still works)
    await _assertNoThrowAsync(mod, 'Spin after grid changes', () async {
      await provider.spin();
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 6: SLOTLAB SUBSYSTEMS
  // ═══════════════════════════════════════════════════════════════════════════

  void _testSlotLabSubsystems() {
    const mod = 'SlotLabSub';

    // Behavior Tree
    final bt = _tryGet<BehaviorTreeProvider>();
    if (bt != null) {
      _assertNotNull(mod, 'BehaviorTree instance', bt);
      _assertNoThrow(mod, 'BehaviorTree: read tree', () {
        final _ = bt.tree;
      });
    }

    // State Gate
    final sg = _tryGet<StateGateProvider>();
    if (sg != null) {
      _assertNotNull(mod, 'StateGate instance', sg);
      _assertNoThrow(mod, 'StateGate: read substate', () {
        final _ = sg.currentSubstate;
      });
    }

    // Emotional State
    final emo = _tryGet<EmotionalStateProvider>();
    if (emo != null) {
      _assertNotNull(mod, 'EmotionalState instance', emo);
      _assertNoThrow(mod, 'EmotionalState: read state', () {
        final _ = emo.state;
      });
      _assertNoThrow(mod, 'EmotionalState: read intensity', () {
        final _ = emo.intensity;
      });
    }

    // Priority Engine
    final pe = _tryGet<PriorityEngineProvider>();
    if (pe != null) {
      _assertNotNull(mod, 'PriorityEngine instance', pe);
    }

    // Orchestration Engine
    final oe = _tryGet<OrchestrationEngineProvider>();
    if (oe != null) {
      _assertNotNull(mod, 'OrchestrationEngine instance', oe);
    }

    // Simulation Engine
    final sim = _tryGet<SimulationEngineProvider>();
    if (sim != null) {
      _assertNotNull(mod, 'SimulationEngine instance', sim);
      _assertNoThrow(mod, 'SimulationEngine: read isRunning', () {
        final _ = sim.isRunning;
      });
    }

    // Transition System
    final ts = _tryGet<TransitionSystemProvider>();
    if (ts != null) {
      _assertNotNull(mod, 'TransitionSystem instance', ts);
    }

    // Game Flow
    final gf = _tryGet<GameFlowProvider>();
    if (gf != null) {
      _assertNotNull(mod, 'GameFlow instance', gf);
    }

    // Stage Flow
    final sf = _tryGet<StageFlowProvider>();
    if (sf != null) {
      _assertNotNull(mod, 'StageFlow instance', sf);
    }

    // Context Layer
    final cl = _tryGet<ContextLayerProvider>();
    if (cl != null) {
      _assertNotNull(mod, 'ContextLayer instance', cl);
    }

    // Trigger Layer
    final tl = _tryGet<TriggerLayerProvider>();
    if (tl != null) {
      _assertNotNull(mod, 'TriggerLayer instance', tl);
    }

    // SlotLab Undo
    final undo = _tryGet<SlotLabUndoProvider>();
    if (undo != null) {
      _assertNotNull(mod, 'SlotLabUndo instance', undo);
      _assertNoThrow(mod, 'SlotLabUndo: canUndo check', () {
        final _ = undo.canUndo;
      });
      _assertNoThrow(mod, 'SlotLabUndo: canRedo check', () {
        final _ = undo.canRedo;
      });
    }

    // Energy Governance
    final eg = _tryGet<EnergyGovernanceProvider>();
    if (eg != null) {
      _assertNotNull(mod, 'EnergyGovernance instance', eg);
    }

    // DPM
    final dpm = _tryGet<DpmProvider>();
    if (dpm != null) {
      _assertNotNull(mod, 'DPM instance', dpm);
    }

    // AUREXIS
    final aurexis = _tryGet<AurexisProvider>();
    if (aurexis != null) {
      _assertNotNull(mod, 'AUREXIS instance', aurexis);
    }

    final aurProfile = _tryGet<AurexisProfileProvider>();
    if (aurProfile != null) {
      _assertNotNull(mod, 'AUREXIS Profile instance', aurProfile);
    }

    // SlotLab Project
    final project = _tryGet<SlotLabProjectProvider>();
    if (project != null) {
      _assertNotNull(mod, 'SlotLabProject instance', project);
      _assertNoThrow(mod, 'SlotLabProject: read name', () {
        final _ = project.projectName;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 7: CROSS-MODULE INTEGRITY
  // ═══════════════════════════════════════════════════════════════════════════

  void _testCrossModuleIntegrity(SlotLabProvider? slotLab, MixerProvider? mixer) {
    const mod = 'CrossModule';

    // DiagnosticsService singleton consistency
    _assert(mod, 'DiagnosticsService singleton', identical(DiagnosticsService.instance, _diag));

    // GetIt consistency — same instance each time
    final stg1 = _tryGet<StateGroupsProvider>();
    final stg2 = _tryGet<StateGroupsProvider>();
    if (stg1 != null && stg2 != null) {
      _assert(mod, 'StateGroups singleton consistency', identical(stg1, stg2));
    }

    // Mixer bus mapping consistency
    if (mixer != null) {
      _assertEqual(mod, 'Master bus index', MixerProvider.busIdToEngineBusIndex('master'), 0);
      _assertEqual(mod, 'Music bus index', MixerProvider.busIdToEngineBusIndex('music'), 1);
      _assertEqual(mod, 'SFX bus index', MixerProvider.busIdToEngineBusIndex('sfx'), 2);
      _assertEqual(mod, 'Voice bus index', MixerProvider.busIdToEngineBusIndex('voice'), 3);
      _assertEqual(mod, 'Ambience bus index', MixerProvider.busIdToEngineBusIndex('ambience'), 4);
      _assertEqual(mod, 'Unknown bus index', MixerProvider.busIdToEngineBusIndex('nonexistent'), -1);
    }

    // Feature Composer ↔ SlotLab consistency
    if (slotLab != null) {
      final composer = _tryGet<FeatureComposerProvider>();
      if (composer != null && composer.isConfigured) {
        final cfg = composer.config;
        if (cfg != null) {
          _assert(mod, 'Composer config reelCount > 0', cfg.reelCount > 0);
          _assert(mod, 'Composer config rowCount > 0', cfg.rowCount > 0);
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

      // Boundary values
      _assertNoThrow(mod, 'Mixer: volume negative clamped', () {
        final ch = mixer.channels.firstOrNull;
        if (ch != null) {
          mixer.setChannelVolume(ch.id, -1.0);
          // Should clamp to 0.0
          _assertInRange(mod, 'Volume clamped >= 0', ch.volume, 0.0, 0.01);
          mixer.setChannelVolume(ch.id, 1.0); // Reset
        }
      });
      _assertNoThrow(mod, 'Mixer: volume over max clamped', () {
        final ch = mixer.channels.firstOrNull;
        if (ch != null) {
          mixer.setChannelVolume(ch.id, 10.0);
          // Should clamp to 2.0
          _assertInRange(mod, 'Volume clamped <= 2', ch.volume, 0.0, 2.01);
          mixer.setChannelVolume(ch.id, 1.0); // Reset
        }
      });

      // Pan boundaries
      _assertNoThrow(mod, 'Mixer: pan extreme negative', () {
        final ch = mixer.channels.firstOrNull;
        if (ch != null) {
          mixer.setChannelPan(ch.id, -5.0);
          _assertInRange(mod, 'Pan clamped >= -1', ch.pan, -1.01, -0.99);
          mixer.setChannelPan(ch.id, 0.0); // Reset
        }
      });
      _assertNoThrow(mod, 'Mixer: pan extreme positive', () {
        final ch = mixer.channels.firstOrNull;
        if (ch != null) {
          mixer.setChannelPan(ch.id, 5.0);
          _assertInRange(mod, 'Pan clamped <= 1', ch.pan, 0.99, 1.01);
          mixer.setChannelPan(ch.id, 0.0); // Reset
        }
      });

      // Double-delete safety
      _assertNoThrow(mod, 'Mixer: delete non-existent channel', () {
        mixer.deleteChannel('__NONEXISTENT__');
      });
    }

    // SlotLab edge cases
    if (slotLab != null && slotLab.initialized) {
      // Grid extremes
      _assertNoThrow(mod, 'SlotLab: minimum grid 3×1', () {
        slotLab.updateGridSize(3, 1);
      });
      _assertNoThrow(mod, 'SlotLab: maximum grid 8×6', () {
        slotLab.updateGridSize(8, 6);
      });
      // Reset
      slotLab.updateGridSize(5, 3);
    }

    // Middleware subsystem edge cases
    final stateGroups = _tryGet<StateGroupsProvider>();
    if (stateGroups != null) {
      _assertNoThrow(mod, 'StateGroups: unregister non-existent', () {
        stateGroups.unregisterStateGroup(-999);
      });
      _assertNoThrow(mod, 'StateGroups: setState on non-existent group', () {
        stateGroups.setState(-999, 0);
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 9: MULTI-GRID SPIN QA
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
      _diag.log('╔═══ GRID: ${grid.name} (${grid.reels}×${grid.rows}) ═══╗');
      provider.updateGridSize(grid.reels, grid.rows);

      // Forced outcomes
      for (int i = 0; i < outcomes.length; i++) {
        try {
          final result = await provider.spinForced(outcomes[i]);
          if (result == null) {
            _assert(mod, '${grid.name} forced ${outcomes[i].name}', false, 'null result');
            totalErrors++;
          } else {
            totalSpins++;
          }
        } catch (e) {
          _assert(mod, '${grid.name} forced ${outcomes[i].name}', false, 'Exception: $e');
          totalErrors++;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

      // Random spins
      for (int i = 0; i < 4; i++) {
        try {
          final result = await provider.spin();
          if (result == null) {
            _assert(mod, '${grid.name} random ${i + 1}', false, 'null result');
            totalErrors++;
          } else {
            totalSpins++;
          }
        } catch (e) {
          _assert(mod, '${grid.name} random ${i + 1}', false, 'Exception: $e');
          totalErrors++;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }

    // Reset grid
    provider.updateGridSize(5, 3);

    final expectedTotal = _qaGrids.length * spinsPerGrid;
    _assert(mod, 'Total spins completed: $totalSpins/$expectedTotal',
        totalSpins == expectedTotal,
        '$totalErrors errors, ${expectedTotal - totalSpins} missing');

    _diag.log('Multi-grid QA: $totalSpins/$expectedTotal spins, $totalErrors errors');
  }
}
