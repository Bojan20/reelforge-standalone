/// Sequence Containers Provider
///
/// Extracted from MiddlewareProvider as part of P0.2 decomposition (Phase 3).
/// Manages timed sound sequences (Wwise/FMOD-style).
///
/// Sequence containers play sounds in a defined order with timing:
/// - Step-based timeline
/// - Loop/HoldLast/Ping-pong end behaviors
/// - Speed control for tempo adjustment
///
/// P2 Optimization: Syncs to Rust FFI for sub-millisecond tick processing.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/middleware_models.dart';
import '../../services/container_service.dart';
import '../../src/rust/native_ffi.dart';

/// Callback type for step playback
typedef StepPlayCallback = void Function(SequenceStep step, int stepIndex);

/// Provider for managing sequence containers
class SequenceContainersProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  /// Sequence container storage
  final Map<int, SequenceContainer> _containers = {};

  /// Active playback state per container
  final Map<int, _SequencePlaybackState> _playbackStates = {};

  /// Playback timers
  final Map<int, Timer> _playbackTimers = {};

  /// Next available container ID
  int _nextContainerId = 1;

  SequenceContainersProvider({required NativeFFI ffi}) : _ffi = ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all sequence containers
  Map<int, SequenceContainer> get containers => Map.unmodifiable(_containers);

  /// Get all sequence containers as list
  List<SequenceContainer> get sequenceContainers => _containers.values.toList();

  /// Get count of sequence containers
  int get containerCount => _containers.length;

  /// Get a specific sequence container
  SequenceContainer? getContainer(int containerId) => _containers[containerId];

  /// Check if a sequence is currently playing
  bool isPlaying(int containerId) => _playbackStates[containerId]?.isPlaying ?? false;

  /// Get current step index for a playing sequence
  int? getCurrentStep(int containerId) => _playbackStates[containerId]?.currentStep;

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTAINER MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new sequence container
  SequenceContainer createContainer({
    required String name,
    SequenceEndBehavior endBehavior = SequenceEndBehavior.stop,
    double speed = 1.0,
  }) {
    final id = _nextContainerId++;

    final container = SequenceContainer(
      id: id,
      name: name,
      endBehavior: endBehavior,
      speed: speed,
    );

    _containers[id] = container;
    _ffi.middlewareCreateSequenceContainer(container);

    // P2: Sync to Rust Container FFI for sub-ms tick
    ContainerService.instance.syncSequenceToRust(container);

    notifyListeners();
    return container;
  }

  /// Register a sequence container (from JSON import or preset)
  void registerContainer(SequenceContainer container) {
    _containers[container.id] = container;

    // Update next ID if needed
    if (container.id >= _nextContainerId) {
      _nextContainerId = container.id + 1;
    }

    // Register with Rust middleware
    _ffi.middlewareCreateSequenceContainer(container);

    // P2: Sync to Container FFI
    ContainerService.instance.syncSequenceToRust(container);

    notifyListeners();
  }

  /// Update a sequence container
  void updateContainer(SequenceContainer container) {
    if (!_containers.containsKey(container.id)) return;

    // Stop if playing
    if (isPlaying(container.id)) {
      stop(container.id);
    }

    _containers[container.id] = container;

    // Re-register with Rust middleware
    _ffi.middlewareRemoveSequenceContainer(container.id);
    _ffi.middlewareCreateSequenceContainer(container);

    // P2: Re-sync to Container FFI
    ContainerService.instance.unsyncSequenceFromRust(container.id);
    ContainerService.instance.syncSequenceToRust(container);

    notifyListeners();
  }

  /// Remove a sequence container
  void removeContainer(int containerId) {
    // Stop if playing
    if (isPlaying(containerId)) {
      stop(containerId);
    }

    _containers.remove(containerId);
    _playbackStates.remove(containerId);

    _ffi.middlewareRemoveSequenceContainer(containerId);

    // P2: Remove from Container FFI
    ContainerService.instance.unsyncSequenceFromRust(containerId);

    notifyListeners();
  }

  /// Enable/disable a sequence container
  void setContainerEnabled(int containerId, bool enabled) {
    final container = _containers[containerId];
    if (container == null) return;

    if (!enabled && isPlaying(containerId)) {
      stop(containerId);
    }

    _containers[containerId] = container.copyWith(enabled: enabled);
    notifyListeners();
  }

  /// Set playback speed
  void setSpeed(int containerId, double speed) {
    final container = _containers[containerId];
    if (container == null) return;

    _containers[containerId] = container.copyWith(speed: speed.clamp(0.1, 10.0));
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a step to a sequence container
  void addStep(int containerId, SequenceStep step) {
    final container = _containers[containerId];
    if (container == null) return;

    final updatedSteps = [...container.steps, step];
    _containers[containerId] = container.copyWith(steps: updatedSteps);

    // Update Rust
    _ffi.middlewareRemoveSequenceContainer(containerId);
    _ffi.middlewareCreateSequenceContainer(_containers[containerId]!);

    notifyListeners();
  }

  /// Remove a step from a sequence container
  void removeStep(int containerId, int stepIndex) {
    final container = _containers[containerId];
    if (container == null) return;

    final updatedSteps = [...container.steps];
    if (stepIndex >= 0 && stepIndex < updatedSteps.length) {
      updatedSteps.removeAt(stepIndex);
    }
    _containers[containerId] = container.copyWith(steps: updatedSteps);

    // Update Rust
    _ffi.middlewareRemoveSequenceContainer(containerId);
    _ffi.middlewareCreateSequenceContainer(_containers[containerId]!);

    notifyListeners();
  }

  /// Update a step in a sequence container
  void updateStep(int containerId, int stepIndex, SequenceStep step) {
    final container = _containers[containerId];
    if (container == null) return;

    final updatedSteps = [...container.steps];
    if (stepIndex >= 0 && stepIndex < updatedSteps.length) {
      updatedSteps[stepIndex] = step;
    }
    _containers[containerId] = container.copyWith(steps: updatedSteps);

    // Update Rust
    _ffi.middlewareRemoveSequenceContainer(containerId);
    _ffi.middlewareCreateSequenceContainer(_containers[containerId]!);

    notifyListeners();
  }

  /// Move a step within the sequence
  void moveStep(int containerId, int fromIndex, int toIndex) {
    final container = _containers[containerId];
    if (container == null) return;

    final updatedSteps = [...container.steps];
    if (fromIndex < 0 || fromIndex >= updatedSteps.length) return;
    if (toIndex < 0 || toIndex >= updatedSteps.length) return;

    final step = updatedSteps.removeAt(fromIndex);
    updatedSteps.insert(toIndex, step);

    _containers[containerId] = container.copyWith(steps: updatedSteps);

    // Update Rust
    _ffi.middlewareRemoveSequenceContainer(containerId);
    _ffi.middlewareCreateSequenceContainer(_containers[containerId]!);

    notifyListeners();
  }

  /// Create a new step with auto-generated index
  SequenceStep createStep({
    required int containerId,
    required int childId,
    required String childName,
    String? audioPath,
    double delayMs = 0.0,
    double durationMs = 1000.0,
    double fadeInMs = 0.0,
    double fadeOutMs = 0.0,
    int loopCount = 1,
  }) {
    final container = _containers[containerId];
    final nextIndex = container?.steps.length ?? 0;

    return SequenceStep(
      index: nextIndex,
      childId: childId,
      childName: childName,
      audioPath: audioPath,
      delayMs: delayMs,
      durationMs: durationMs,
      fadeInMs: fadeInMs,
      fadeOutMs: fadeOutMs,
      loopCount: loopCount,
    );
  }

  /// Update audio path for a specific step
  void updateStepAudioPath(int containerId, int stepIndex, String? audioPath) {
    final container = _containers[containerId];
    if (container == null) return;
    if (stepIndex < 0 || stepIndex >= container.steps.length) return;

    final updatedSteps = container.steps.map((s) {
      if (s.index == stepIndex) {
        return s.copyWith(audioPath: audioPath);
      }
      return s;
    }).toList();

    _containers[containerId] = container.copyWith(steps: updatedSteps);

    // Re-register with Rust
    _ffi.middlewareRemoveSequenceContainer(containerId);
    _ffi.middlewareCreateSequenceContainer(_containers[containerId]!);

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYBACK CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start sequence playback
  void play(int containerId, {StepPlayCallback? onStep}) {
    final container = _containers[containerId];
    if (container == null || !container.enabled || container.steps.isEmpty) {
      return;
    }

    // Stop if already playing
    stop(containerId);

    // Initialize playback state
    _playbackStates[containerId] = _SequencePlaybackState(
      isPlaying: true,
      currentStep: 0,
      direction: 1,
      onStep: onStep,
    );

    // Start first step
    _playStep(containerId);
  }

  /// Stop sequence playback
  void stop(int containerId) {
    _playbackTimers[containerId]?.cancel();
    _playbackTimers.remove(containerId);
    _playbackStates.remove(containerId);
    notifyListeners();
  }

  /// Pause sequence playback
  void pause(int containerId) {
    final state = _playbackStates[containerId];
    if (state == null || !state.isPlaying) return;

    _playbackTimers[containerId]?.cancel();
    _playbackStates[containerId] = state.copyWith(isPlaying: false);
    notifyListeners();
  }

  /// Resume sequence playback
  void resume(int containerId) {
    final state = _playbackStates[containerId];
    if (state == null || state.isPlaying) return;

    _playbackStates[containerId] = state.copyWith(isPlaying: true);
    _playStep(containerId);
  }

  /// Jump to specific step
  void jumpToStep(int containerId, int stepIndex) {
    final container = _containers[containerId];
    final state = _playbackStates[containerId];
    if (container == null || state == null) return;

    if (stepIndex < 0 || stepIndex >= container.steps.length) return;

    _playbackTimers[containerId]?.cancel();
    _playbackStates[containerId] = state.copyWith(currentStep: stepIndex);
    _playStep(containerId);
  }

  void _playStep(int containerId) {
    final container = _containers[containerId];
    final state = _playbackStates[containerId];
    if (container == null || state == null || !state.isPlaying) return;

    final stepIndex = state.currentStep;
    if (stepIndex < 0 || stepIndex >= container.steps.length) {
      _handleSequenceEnd(containerId);
      return;
    }

    final step = container.steps[stepIndex];

    // Notify callback
    state.onStep?.call(step, stepIndex);

    // Calculate actual duration with speed
    final durationMs = step.durationMs / container.speed;

    // Schedule next step
    _playbackTimers[containerId] = Timer(
      Duration(milliseconds: durationMs.round()),
      () => _advanceStep(containerId),
    );

    notifyListeners();
  }

  void _advanceStep(int containerId) {
    final container = _containers[containerId];
    final state = _playbackStates[containerId];
    if (container == null || state == null) return;

    int nextStep = state.currentStep + state.direction;

    // Handle boundaries
    if (nextStep >= container.steps.length || nextStep < 0) {
      _handleSequenceEnd(containerId);
      return;
    }

    _playbackStates[containerId] = state.copyWith(currentStep: nextStep);
    _playStep(containerId);
  }

  void _handleSequenceEnd(int containerId) {
    final container = _containers[containerId];
    final state = _playbackStates[containerId];
    if (container == null || state == null) return;

    switch (container.endBehavior) {
      case SequenceEndBehavior.stop:
        stop(containerId);
        break;

      case SequenceEndBehavior.loop:
        // Restart from beginning
        _playbackStates[containerId] = state.copyWith(
          currentStep: 0,
          direction: 1,
        );
        _playStep(containerId);
        break;

      case SequenceEndBehavior.holdLast:
        // Stay on last step, stop playback
        _playbackTimers[containerId]?.cancel();
        _playbackStates[containerId] = state.copyWith(
          isPlaying: false,
          currentStep: container.steps.length - 1,
        );
        notifyListeners();
        break;

      case SequenceEndBehavior.pingPong:
        // Reverse direction
        final newDirection = -state.direction;
        final newStep = newDirection > 0 ? 0 : container.steps.length - 1;
        _playbackStates[containerId] = state.copyWith(
          currentStep: newStep,
          direction: newDirection,
        );
        _playStep(containerId);
        break;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export sequence containers to JSON
  List<Map<String, dynamic>> toJson() {
    return _containers.values.map((c) => c.toJson()).toList();
  }

  /// Import sequence containers from JSON
  void fromJson(List<dynamic> json) {
    for (final item in json) {
      final container = SequenceContainer.fromJson(item as Map<String, dynamic>);
      registerContainer(container);
    }
  }

  /// Clear all sequence containers
  void clear() {
    // Stop all playback
    for (final containerId in _containers.keys.toList()) {
      stop(containerId);
      _ffi.middlewareRemoveSequenceContainer(containerId);
    }

    _containers.clear();
    _playbackStates.clear();
    _playbackTimers.clear();
    _nextContainerId = 1;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    // Cancel all timers
    for (final timer in _playbackTimers.values) {
      timer.cancel();
    }
    _playbackTimers.clear();
    _containers.clear();
    _playbackStates.clear();
    super.dispose();
  }
}

/// Internal playback state
class _SequencePlaybackState {
  final bool isPlaying;
  final int currentStep;
  final int direction; // 1 = forward, -1 = backward
  final StepPlayCallback? onStep;

  const _SequencePlaybackState({
    required this.isPlaying,
    required this.currentStep,
    required this.direction,
    this.onStep,
  });

  _SequencePlaybackState copyWith({
    bool? isPlaying,
    int? currentStep,
    int? direction,
  }) {
    return _SequencePlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      currentStep: currentStep ?? this.currentStep,
      direction: direction ?? this.direction,
      onStep: onStep,
    );
  }
}
