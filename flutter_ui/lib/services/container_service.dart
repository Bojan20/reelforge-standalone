/// FluxForge Container Service
///
/// Wwise/FMOD-style container playback:
/// - BlendContainer: RTPC-based crossfade between sounds
/// - RandomContainer: Weighted random/shuffle selection
/// - SequenceContainer: Timed sound sequences
///
/// P2 Optimization: Uses Rust FFI for sub-millisecond container evaluation
/// when available, with fallback to Dart implementation.
///
/// Usage:
/// 1. Register container with EventRegistry
/// 2. When triggered, container determines which sound(s) to play
/// 3. Supports per-play variation (random, RTPC-based selection)
library;

import 'dart:async';
import 'dart:math' as math;
import '../models/middleware_models.dart';
import '../providers/middleware_provider.dart';
import '../src/rust/native_ffi.dart';
import 'audio_playback_service.dart';
import 'container_eval_history.dart';

/// Service for container-based audio playback
class ContainerService {
  static final ContainerService _instance = ContainerService._();
  static ContainerService get instance => _instance;

  ContainerService._();

  // Reference to middleware provider
  MiddlewareProvider? _middleware;

  // FFI instance (lazy loaded)
  NativeFFI? _ffi;

  // Whether Rust FFI is available
  bool _ffiAvailable = false;

  // Random number generator (fallback for Dart-only mode)
  final _random = math.Random();

  // Round-robin state per container (containerId → currentIndex)
  final Map<int, int> _roundRobinState = {};

  // Shuffle history per container (containerId → played indices)
  final Map<int, List<int>> _shuffleHistory = {};

  // Rust container ID mapping (Dart containerId → Rust containerId)
  final Map<int, int> _blendRustIds = {};
  final Map<int, int> _randomRustIds = {};
  final Map<int, int> _sequenceRustIds = {};

  // P3A: Active Rust tick-based sequences (instanceId → _SequenceInstanceRust)
  final Map<int, _SequenceInstanceRust> _activeRustSequences = {};

  // P2-17: Container evaluation history tracking
  final List<ContainerEvalHistoryEntry> _evalHistory = [];
  bool _trackHistory = false;
  int _maxHistorySize = 1000;

  /// Initialize with middleware provider
  void init(MiddlewareProvider middleware) {
    _middleware = middleware;

    // Try to initialize FFI
    try {
      _ffi = NativeFFI.instance;
      if (_ffi!.isLoaded) {
        _ffi!.containerInit();
        _ffiAvailable = true;
      } else {
        _ffiAvailable = false;
      }
    } catch (e) {
      _ffiAvailable = false;
    }
  }

  /// Check if Rust FFI is available
  bool get isRustAvailable => _ffiAvailable;

  /// Get Rust container count (for debugging)
  int get rustContainerCount => _ffiAvailable ? _ffi!.containerGetTotalCount() : 0;

  /// Get a blend container by ID (for logging/info)
  BlendContainer? getBlendContainer(int id) => _middleware?.getBlendContainer(id);

  /// Get a random container by ID (for logging/info)
  RandomContainer? getRandomContainer(int id) => _middleware?.getRandomContainer(id);

  /// Get a sequence container by ID (for logging/info)
  SequenceContainer? getSequenceContainer(int id) => _middleware?.getSequenceContainer(id);

  // ═══════════════════════════════════════════════════════════════════════════
  // BLEND CONTAINER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get active blend children with their volumes based on current RTPC value
  /// Returns map of childId → volume (0.0-1.0)
  Map<int, double> evaluateBlendContainer(BlendContainer container) {
    if (!container.enabled || container.children.isEmpty) return {};
    if (_middleware == null) return {};

    final rtpcDef = _middleware!.getRtpc(container.rtpcId);
    if (rtpcDef == null) return {};

    final rtpcValue = rtpcDef.normalizedValue; // 0-1
    final result = <int, double>{};

    for (final child in container.children) {
      // Check if RTPC value is within this child's range
      if (rtpcValue < child.rtpcStart || rtpcValue > child.rtpcEnd) continue;

      // Calculate volume based on position within range and crossfade width
      double volume = 1.0;

      // Fade in at start of range
      if (rtpcValue < child.rtpcStart + child.crossfadeWidth) {
        final fadePos = (rtpcValue - child.rtpcStart) / child.crossfadeWidth;
        volume = _applyCrossfadeCurve(fadePos, container.crossfadeCurve);
      }
      // Fade out at end of range
      else if (rtpcValue > child.rtpcEnd - child.crossfadeWidth) {
        final fadePos = (child.rtpcEnd - rtpcValue) / child.crossfadeWidth;
        volume = _applyCrossfadeCurve(fadePos, container.crossfadeCurve);
      }

      result[child.id] = volume.clamp(0.0, 1.0);
    }

    // P2-17: Record evaluation history
    containerEvalHistory.record(ContainerEvalHistoryEntry(
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      containerType: 'blend',
      containerId: container.id,
      containerName: container.name,
      result: result,
      context: {'rtpcValue': rtpcValue, 'rtpcId': container.rtpcId},
    ));

    return result;
  }

  /// Apply crossfade curve to a 0-1 value
  double _applyCrossfadeCurve(double t, CrossfadeCurve curve) {
    switch (curve) {
      case CrossfadeCurve.linear:
        return t;
      case CrossfadeCurve.equalPower:
        return math.sqrt(t);
      case CrossfadeCurve.sCurve:
        return t * t * (3.0 - 2.0 * t);
      case CrossfadeCurve.sinCos:
        return math.sin(t * math.pi / 2);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RANDOM CONTAINER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Select which child to play from a random container
  /// Returns the selected child index, or -1 if none
  int selectRandomChild(RandomContainer container) {
    if (!container.enabled || container.children.isEmpty) return -1;

    final selected = switch (container.mode) {
      RandomMode.random => _selectWeightedRandom(container),
      RandomMode.shuffle => _selectShuffle(container, useHistory: false),
      RandomMode.shuffleWithHistory => _selectShuffle(container, useHistory: true),
      RandomMode.roundRobin => _selectRoundRobin(container),
    };

    // P2-17: Record evaluation history
    if (selected >= 0) {
      containerEvalHistory.record(ContainerEvalHistoryEntry(
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        containerType: 'random',
        containerId: container.id,
        containerName: container.name,
        result: selected,
        context: {
          'mode': container.mode.name,
          'childCount': container.children.length,
        },
      ));
    }

    return selected;
  }

  /// Weighted random selection
  int _selectWeightedRandom(RandomContainer container) {
    double totalWeight = 0.0;
    for (final child in container.children) {
      totalWeight += child.weight;
    }

    if (totalWeight <= 0) return 0;

    double roll = _random.nextDouble() * totalWeight;
    double cumulative = 0.0;

    for (int i = 0; i < container.children.length; i++) {
      cumulative += container.children[i].weight;
      if (roll <= cumulative) return i;
    }

    return container.children.length - 1;
  }

  /// Shuffle selection (optionally avoiding recent plays)
  int _selectShuffle(RandomContainer container, {required bool useHistory}) {
    final history = _shuffleHistory[container.id] ?? [];

    if (!useHistory || history.length >= container.children.length) {
      // Reset history if full or not using history
      _shuffleHistory[container.id] = [];
    }

    // Get available indices (not in recent history)
    final available = <int>[];
    for (int i = 0; i < container.children.length; i++) {
      if (!history.contains(i)) available.add(i);
    }

    if (available.isEmpty) {
      // Fallback to first
      return 0;
    }

    // Select random from available
    final selected = available[_random.nextInt(available.length)];

    // Add to history if using history
    if (useHistory) {
      _shuffleHistory[container.id] = [...history, selected];
    }

    return selected;
  }

  /// Round-robin selection
  int _selectRoundRobin(RandomContainer container) {
    final current = _roundRobinState[container.id] ?? 0;
    final next = (current + 1) % container.children.length;
    _roundRobinState[container.id] = next;
    return current;
  }

  /// Apply pitch and volume variation to selected child
  /// Returns map with 'pitch' and 'volume' modifiers
  Map<String, double> applyRandomVariation(RandomChild child) {
    // Pitch variation: random between pitchMin and pitchMax
    final pitchRange = child.pitchMax - child.pitchMin;
    final pitch = child.pitchMin + _random.nextDouble() * pitchRange;

    // Volume variation: random between volumeMin and volumeMax
    final volumeRange = child.volumeMax - child.volumeMin;
    final volume = child.volumeMin + _random.nextDouble() * volumeRange;

    return {
      'pitch': pitch,
      'volume': volume,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEQUENCE CONTAINER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get the steps that should play at a given time (ms from start)
  /// Uses delayMs as the start time for each step
  List<SequenceStep> getActiveSteps(SequenceContainer container, double timeMs) {
    if (!container.enabled || container.steps.isEmpty) return [];

    final result = <SequenceStep>[];
    for (final step in container.steps) {
      // Step active if timeMs is between delay and delay+duration
      if (timeMs >= step.delayMs && timeMs < step.delayMs + step.durationMs) {
        result.add(step);
      }
    }
    return result;
  }

  /// Get total duration of sequence container
  double getSequenceDuration(SequenceContainer container) {
    if (container.steps.isEmpty) return 0.0;

    double maxEnd = 0.0;
    for (final step in container.steps) {
      final end = step.delayMs + step.durationMs;
      if (end > maxEnd) maxEnd = end;
    }
    return maxEnd;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTAINER PLAYBACK — Trigger Methods
  // ═══════════════════════════════════════════════════════════════════════════

  // Active sequence instances (instanceId → _SequenceInstance)
  final Map<int, _SequenceInstance> _activeSequences = {};
  int _nextSequenceId = 1;

  /// Trigger a blend container — plays active children with RTPC-based volumes
  /// Returns list of voice IDs for each played child
  Future<List<int>> triggerBlendContainer(
    int containerId, {
    required int busId,
    Map<String, dynamic>? context,
  }) async {
    if (_middleware == null) {
      return [];
    }

    final container = _middleware!.getBlendContainer(containerId);
    if (container == null) {
      return [];
    }

    // Get RTPC value for evaluation
    final rtpcDef = _middleware!.getRtpc(container.rtpcId);
    final rtpcValue = rtpcDef?.normalizedValue ?? 0.5;

    Map<int, double> volumes;

    // Try Rust FFI first for sub-ms evaluation
    if (_ffiAvailable && _blendRustIds.containsKey(containerId)) {
      final rustId = _blendRustIds[containerId]!;
      final results = _ffi!.containerEvaluateBlend(rustId, rtpcValue);

      if (results.isNotEmpty) {
        volumes = {for (final r in results) r.childId: r.volume};
      } else {
        // Fallback to Dart
        volumes = evaluateBlendContainer(container);
      }
    } else {
      // Dart fallback
      volumes = evaluateBlendContainer(container);
    }

    if (volumes.isEmpty) {
      return [];
    }

    final voiceIds = <int>[];
    final playbackService = AudioPlaybackService.instance;

    for (final entry in volumes.entries) {
      final childId = entry.key;
      final volume = entry.value;

      // Get audio path - try Rust first, then Dart model
      String? audioPath;
      if (_ffiAvailable && _blendRustIds.containsKey(containerId)) {
        audioPath = _ffi!.containerGetBlendChildAudioPath(_blendRustIds[containerId]!, childId);
      }
      if (audioPath == null || audioPath.isEmpty) {
        // Fallback to Dart model
        final child = container.children.firstWhere(
          (c) => c.id == childId,
          orElse: () => container.children.first,
        );
        audioPath = child.audioPath;
      }

      if (audioPath == null || audioPath.isEmpty) {
        continue;
      }

      // Play the child with calculated volume
      final contextPan = (context?['pan'] as num?)?.toDouble() ?? 0.0;
      final voiceId = playbackService.playFileToBus(
        audioPath,
        busId: busId,
        volume: volume,
        pan: contextPan,
      );

      if (voiceId > 0) {
        voiceIds.add(voiceId);
      }
    }

    return voiceIds;
  }

  /// Trigger a random container — selects and plays one child
  /// Returns the voice ID of the played sound, or -1 on failure
  Future<int> triggerRandomContainer(
    int containerId, {
    required int busId,
    Map<String, dynamic>? context,
  }) async {
    if (_middleware == null) {
      return -1;
    }

    final container = _middleware!.getRandomContainer(containerId);
    if (container == null) {
      return -1;
    }

    int selectedChildId;
    double pitchOffset = 0.0;
    double volumeOffset = 0.0;
    String? audioPath;

    // Try Rust FFI first for sub-ms selection
    if (_ffiAvailable && _randomRustIds.containsKey(containerId)) {
      final rustId = _randomRustIds[containerId]!;
      final result = _ffi!.containerSelectRandom(rustId);

      if (result != null) {
        selectedChildId = result.childId;
        pitchOffset = result.pitchOffset;
        volumeOffset = result.volumeOffset;
        audioPath = _ffi!.containerGetRandomChildAudioPath(rustId, selectedChildId);
      } else {
        // Rust returned null (disabled/empty), try Dart fallback
        final selectedIndex = selectRandomChild(container);
        if (selectedIndex < 0 || selectedIndex >= container.children.length) {
          return -1;
        }
        final child = container.children[selectedIndex];
        selectedChildId = child.id;
        final variation = applyRandomVariation(child);
        pitchOffset = variation['pitch']!;
        volumeOffset = variation['volume']!;
        audioPath = child.audioPath;
      }
    } else {
      // Dart fallback
      final selectedIndex = selectRandomChild(container);
      if (selectedIndex < 0 || selectedIndex >= container.children.length) {
        return -1;
      }
      final child = container.children[selectedIndex];
      selectedChildId = child.id;
      final variation = applyRandomVariation(child);
      pitchOffset = variation['pitch']!;
      volumeOffset = variation['volume']!;
      audioPath = child.audioPath;
    }

    if (audioPath == null || audioPath.isEmpty) {
      return -1;
    }

    // Calculate final volume
    final baseVolume = (context?['volume'] as num?)?.toDouble() ?? 1.0;
    final contextPan = (context?['pan'] as num?)?.toDouble() ?? 0.0;
    final finalVolume = (baseVolume + volumeOffset).clamp(0.0, 1.0);

    final playbackService = AudioPlaybackService.instance;
    final voiceId = playbackService.playFileToBus(
      audioPath,
      busId: busId,
      volume: finalVolume,
      pan: contextPan,
      // Note: pitch variation would need engine support
    );

    if (voiceId > 0) {
    }

    return voiceId;
  }

  /// Trigger a sequence container — schedules steps with timing
  /// Returns the sequence instance ID for tracking/stopping
  ///
  /// P3A: Uses Rust FFI tick-based timing when available for sub-ms precision.
  /// Falls back to Dart Timer scheduling if FFI unavailable.
  Future<int> triggerSequenceContainer(
    int containerId, {
    required int busId,
    Map<String, dynamic>? context,
  }) async {
    if (_middleware == null) {
      return -1;
    }

    final container = _middleware!.getSequenceContainer(containerId);
    if (container == null) {
      return -1;
    }

    if (container.steps.isEmpty) {
      return -1;
    }

    // P3A: Use Rust tick-based timing if FFI available
    if (_ffiAvailable && _sequenceRustIds.containsKey(containerId)) {
      return _triggerSequenceViaRustTick(containerId, container, busId, context);
    }

    // Fallback: Dart Timer scheduling
    return _triggerSequenceViaDartTimer(containerId, container, busId, context);
  }

  /// P3A: Rust tick-based sequence playback
  /// Uses Rust internal clock for precise step timing
  int _triggerSequenceViaRustTick(
    int containerId,
    SequenceContainer container,
    int busId,
    Map<String, dynamic>? context,
  ) {
    final rustId = _sequenceRustIds[containerId]!;
    final instanceId = _nextSequenceId++;

    // Start playback in Rust
    _ffi!.containerPlaySequence(rustId);

    // Create instance with tick timer
    final instance = _SequenceInstanceRust(
      instanceId: instanceId,
      containerId: containerId,
      rustId: rustId,
      container: container,
      voiceIds: [],
      busId: busId,
      context: context,
      lastTickTime: DateTime.now(),
    );

    _activeRustSequences[instanceId] = instance;

    // Start tick loop (~60fps = 16.67ms)
    instance.tickTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      _tickRustSequence(instanceId);
    });

    return instanceId;
  }

  /// Tick a Rust-based sequence, triggering any due steps
  void _tickRustSequence(int instanceId) {
    final instance = _activeRustSequences[instanceId];
    if (instance == null) return;

    final now = DateTime.now();
    final deltaMs = now.difference(instance.lastTickTime).inMicroseconds / 1000.0;
    instance.lastTickTime = now;

    // Tick Rust and get triggered steps
    final result = _ffi!.containerTickSequence(instance.rustId, deltaMs);

    // Play triggered steps
    for (final stepIdx in result.triggeredSteps) {
      _playSequenceStep(instance, stepIdx);
    }

    // Handle sequence end
    if (result.ended) {
      _stopRustSequence(instanceId, 'ended');
    } else if (result.looped) {
    }
  }

  /// Play a single sequence step
  void _playSequenceStep(_SequenceInstanceRust instance, int stepIdx) {
    // Get audio path from Rust
    String? audioPath = _ffi!.containerGetSequenceStepAudioPath(instance.rustId, stepIdx);

    // Fallback to Dart model if Rust path empty
    if (audioPath == null || audioPath.isEmpty) {
      if (stepIdx < instance.container.steps.length) {
        audioPath = instance.container.steps[stepIdx].audioPath;
      }
    }

    if (audioPath == null || audioPath.isEmpty) {
      return;
    }

    final contextPan = (instance.context?['pan'] as num?)?.toDouble() ?? 0.0;
    final step = stepIdx < instance.container.steps.length
        ? instance.container.steps[stepIdx]
        : null;
    final volume = step?.volume ?? 1.0;

    final voiceId = AudioPlaybackService.instance.playFileToBus(
      audioPath,
      busId: instance.busId,
      volume: volume,
      pan: contextPan,
    );

    if (voiceId > 0) {
      instance.voiceIds.add(voiceId);
      final stepName = step?.childName ?? 'step_$stepIdx';
    }
  }

  /// Stop a Rust-based sequence
  void _stopRustSequence(int instanceId, String reason) {
    final instance = _activeRustSequences.remove(instanceId);
    if (instance == null) return;

    instance.tickTimer?.cancel();
    _ffi!.containerStopSequence(instance.rustId);

    // Stop all playing voices
    for (final voiceId in instance.voiceIds) {
      AudioPlaybackService.instance.stopOneShotVoice(voiceId);
    }

  }

  /// Dart Timer fallback for sequence playback
  /// [reversed] - if true, plays steps in reverse order (for ping-pong)
  int _triggerSequenceViaDartTimer(
    int containerId,
    SequenceContainer container,
    int busId,
    Map<String, dynamic>? context, {
    bool reversed = false,
  }) {
    final instanceId = _nextSequenceId++;
    final voiceIds = <int>[];
    final timers = <Timer>[];

    // Get steps in correct order (reversed for ping-pong return)
    final stepsToPlay = reversed ? container.steps.reversed.toList() : container.steps;

    // Calculate cumulative delays for reversed order
    double cumulativeDelay = 0;

    // Schedule each step
    for (final step in stepsToPlay) {
      if (step.audioPath == null || step.audioPath!.isEmpty) {
        continue;
      }

      // For reversed playback, use cumulative timing
      // For forward playback, use original delayMs
      final adjustedDelay = reversed
          ? (cumulativeDelay / container.speed).round()
          : (step.delayMs / container.speed).round();

      if (reversed) {
        // Add this step's duration for next step's delay
        cumulativeDelay += step.durationMs;
      }

      final timer = Timer(Duration(milliseconds: adjustedDelay), () async {
        final playbackService = AudioPlaybackService.instance;
        final contextPan = (context?['pan'] as num?)?.toDouble() ?? 0.0;

        final voiceId = playbackService.playFileToBus(
          step.audioPath!,
          busId: busId,
          volume: step.volume,
          pan: contextPan,
        );

        if (voiceId > 0) {
          voiceIds.add(voiceId);
        }
      });

      timers.add(timer);
    }

    // Store instance for tracking
    final totalDuration = getSequenceDuration(container) / container.speed;
    _activeSequences[instanceId] = _SequenceInstance(
      containerId: containerId,
      voiceIds: voiceIds,
      timers: timers,
      startTime: DateTime.now(),
      endBehavior: container.endBehavior,
      durationMs: totalDuration,
      busId: busId,
      context: context,
      reversed: reversed,
    );

    // Schedule end behavior handling
    Timer(Duration(milliseconds: totalDuration.round()), () {
      _handleSequenceEnd(instanceId);
    });

    return instanceId;
  }

  /// Stop a running sequence (handles both Dart Timer and Rust tick modes)
  void stopSequence(int instanceId) {
    // P3A: Check if this is a Rust tick-based sequence
    if (_activeRustSequences.containsKey(instanceId)) {
      _stopRustSequence(instanceId, 'manual stop');
      return;
    }

    // Dart Timer-based sequence
    final instance = _activeSequences[instanceId];
    if (instance == null) return;

    // Cancel all pending timers
    for (final timer in instance.timers) {
      timer.cancel();
    }

    // Stop all playing voices
    for (final voiceId in instance.voiceIds) {
      AudioPlaybackService.instance.stopOneShotVoice(voiceId);
    }

    _activeSequences.remove(instanceId);
  }

  /// Handle sequence end behavior (loop, hold, ping-pong)
  void _handleSequenceEnd(int instanceId) {
    final instance = _activeSequences[instanceId];
    if (instance == null) return;

    switch (instance.endBehavior) {
      case SequenceEndBehavior.stop:
        // Just clean up
        _activeSequences.remove(instanceId);
        break;

      case SequenceEndBehavior.loop:
        // Restart the sequence
        _activeSequences.remove(instanceId);
        triggerSequenceContainer(
          instance.containerId,
          busId: instance.busId,
          context: instance.context,
        );
        break;

      case SequenceEndBehavior.holdLast:
        // Keep the last sound playing (handled by voice)
        break;

      case SequenceEndBehavior.pingPong:
        // Reverse direction and play again
        _activeSequences.remove(instanceId);
        final container = _middleware?.getSequenceContainer(instance.containerId);
        if (container != null) {
          // Toggle reversed state for next pass
          final nextReversed = !instance.reversed;
          _triggerSequenceViaDartTimer(
            instance.containerId,
            container,
            instance.busId,
            instance.context,
            reversed: nextReversed,
          );
        } else {
        }
        break;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RUST SYNC — Sync containers to Rust for FFI evaluation
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sync a blend container to Rust
  /// Call this when container is created or updated
  bool syncBlendToRust(BlendContainer container) {
    if (!_ffiAvailable) return false;

    try {
      final config = {
        'id': container.id,
        'name': container.name,
        'enabled': container.enabled,
        'curve': container.crossfadeCurve.index,
        'rtpc_name': 'rtpc_${container.rtpcId}',
        'children': container.children.map((c) => {
          'id': c.id,
          'name': c.name,
          'audio_path': c.audioPath ?? '',
          'rtpc_start': c.rtpcStart,
          'rtpc_end': c.rtpcEnd,
          'crossfade_width': c.crossfadeWidth,
          'volume': 1.0,
        }).toList(),
      };

      final rustId = _ffi!.containerCreateBlend(config);
      if (rustId > 0) {
        _blendRustIds[container.id] = rustId;
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Sync a random container to Rust
  bool syncRandomToRust(RandomContainer container) {
    if (!_ffiAvailable) return false;

    try {
      final config = {
        'id': container.id,
        'name': container.name,
        'enabled': container.enabled,
        'mode': container.mode.index,
        'avoid_repeat': true,
        'avoid_repeat_count': 1,
        'global_pitch_min': container.globalPitchMin,
        'global_pitch_max': container.globalPitchMax,
        'global_volume_min': container.globalVolumeMin,
        'global_volume_max': container.globalVolumeMax,
        'children': container.children.map((c) => {
          'id': c.id,
          'name': c.name,
          'audio_path': c.audioPath ?? '',
          'weight': c.weight,
          'pitch_min': c.pitchMin,
          'pitch_max': c.pitchMax,
          'volume_min': c.volumeMin,
          'volume_max': c.volumeMax,
        }).toList(),
      };

      final rustId = _ffi!.containerCreateRandom(config);
      if (rustId > 0) {
        _randomRustIds[container.id] = rustId;
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Sync a sequence container to Rust
  bool syncSequenceToRust(SequenceContainer container) {
    if (!_ffiAvailable) return false;

    try {
      final config = {
        'id': container.id,
        'name': container.name,
        'enabled': container.enabled,
        'end_behavior': container.endBehavior.index,
        'speed': container.speed,
        'steps': container.steps.asMap().entries.map((e) => {
          'index': e.key,
          'child_id': e.value.childId,
          'child_name': e.value.childName,
          'audio_path': e.value.audioPath ?? '',
          'delay_ms': e.value.delayMs,
          'duration_ms': e.value.durationMs,
          'fade_in_ms': e.value.fadeInMs,
          'fade_out_ms': e.value.fadeOutMs,
          'loop_count': e.value.loopCount,
          'volume': 1.0,
        }).toList(),
      };

      final rustId = _ffi!.containerCreateSequence(config);
      if (rustId > 0) {
        _sequenceRustIds[container.id] = rustId;
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Remove blend container from Rust
  void unsyncBlendFromRust(int containerId) {
    if (!_ffiAvailable) return;
    final rustId = _blendRustIds.remove(containerId);
    if (rustId != null) {
      _ffi!.containerRemoveBlend(rustId);
    }
  }

  /// Remove random container from Rust
  void unsyncRandomFromRust(int containerId) {
    if (!_ffiAvailable) return;
    final rustId = _randomRustIds.remove(containerId);
    if (rustId != null) {
      _ffi!.containerRemoveRandom(rustId);
    }
  }

  /// Remove sequence container from Rust
  void unsyncSequenceFromRust(int containerId) {
    if (!_ffiAvailable) return;
    final rustId = _sequenceRustIds.remove(containerId);
    if (rustId != null) {
      _ffi!.containerRemoveSequence(rustId);
    }
  }

  /// Sync all containers from middleware to Rust
  void syncAllToRust() {
    if (!_ffiAvailable || _middleware == null) return;

    // Clear existing Rust containers
    _ffi!.containerClearAll();
    _blendRustIds.clear();
    _randomRustIds.clear();
    _sequenceRustIds.clear();

    // Sync all blend containers
    for (final container in _middleware!.blendContainers) {
      syncBlendToRust(container);
    }

    // Sync all random containers
    for (final container in _middleware!.randomContainers) {
      syncRandomToRust(container);
    }

    // Sync all sequence containers
    for (final container in _middleware!.sequenceContainers) {
      syncSequenceToRust(container);
    }

  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Reset all container state (shuffle history, round-robin positions)
  void resetState() {
    _roundRobinState.clear();
    _shuffleHistory.clear();

    // Stop all active Dart Timer sequences
    for (final instanceId in _activeSequences.keys.toList()) {
      stopSequence(instanceId);
    }

    // P3A: Stop all active Rust tick-based sequences
    for (final instanceId in _activeRustSequences.keys.toList()) {
      _stopRustSequence(instanceId, 'reset');
    }
  }

  /// Clear all data
  void clear() {
    resetState();

    // Clear Rust containers
    if (_ffiAvailable) {
      _ffi!.containerClearAll();
      _ffi!.containerShutdown();
    }

    _blendRustIds.clear();
    _randomRustIds.clear();
    _sequenceRustIds.clear();
    _middleware = null;
  }
}

// =============================================================================
// SEQUENCE INSTANCE — Tracking active sequence playback
// =============================================================================

class _SequenceInstance {
  final int containerId;
  final List<int> voiceIds;
  final List<Timer> timers;
  final DateTime startTime;
  final SequenceEndBehavior endBehavior;
  final double durationMs;
  final int busId;
  final Map<String, dynamic>? context;
  final bool reversed; // For ping-pong playback direction

  _SequenceInstance({
    required this.containerId,
    required this.voiceIds,
    required this.timers,
    required this.startTime,
    required this.endBehavior,
    required this.durationMs,
    required this.busId,
    this.reversed = false,
    this.context,
  });
}

// =============================================================================
// P3A: RUST TICK-BASED SEQUENCE INSTANCE
// =============================================================================

/// Instance for Rust tick-based sequence playback (P3A optimization)
class _SequenceInstanceRust {
  final int instanceId;
  final int containerId;
  final int rustId;
  final SequenceContainer container;
  final List<int> voiceIds;
  final int busId;
  final Map<String, dynamic>? context;

  /// Timer for periodic tick calls (~60fps)
  Timer? tickTimer;

  /// Last tick timestamp for delta calculation
  DateTime lastTickTime;

  _SequenceInstanceRust({
    required this.instanceId,
    required this.containerId,
    required this.rustId,
    required this.container,
    required this.voiceIds,
    required this.busId,
    required this.lastTickTime,
    this.context,
  });
}
