/// Random Containers Provider
///
/// Extracted from MiddlewareProvider as part of P0.2 decomposition (Phase 3).
/// Manages weighted random sound selection (Wwise/FMOD-style).
///
/// Random containers select sounds randomly from a pool, with optional:
/// - Weighted probabilities per child
/// - Avoid repeat (don't play same sound twice in a row)
/// - Global pitch/volume randomization
/// - Multiple modes: Random, Shuffle, ShuffleWithHistory, Round Robin
///
/// P2 Optimization: Syncs to Rust FFI for sub-millisecond selection.

import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/middleware_models.dart';
import '../../services/container_service.dart';
import '../../src/rust/native_ffi.dart';

/// Result of random child selection
class RandomChildSelection {
  final RandomChild child;
  final double pitchOffset;
  final double volumeMultiplier;

  const RandomChildSelection({
    required this.child,
    required this.pitchOffset,
    required this.volumeMultiplier,
  });
}

/// Record of deterministic selection for tracing/replay (M4)
class DeterministicSelectionRecord {
  final int containerId;
  final int selectedChildId;
  final int seed;
  final int sequenceIndex;
  final DateTime timestamp;

  const DeterministicSelectionRecord({
    required this.containerId,
    required this.selectedChildId,
    required this.seed,
    required this.sequenceIndex,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'containerId': containerId,
    'selectedChildId': selectedChildId,
    'seed': seed,
    'sequenceIndex': sequenceIndex,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Provider for managing random containers
class RandomContainersProvider extends ChangeNotifier {
  final NativeFFI _ffi;
  final Random _random = Random();

  /// Random container storage
  final Map<int, RandomContainer> _containers = {};

  /// Play history for avoid-repeat (containerId -> list of recent childIds)
  final Map<int, List<int>> _playHistory = {};

  /// Current shuffle index per container (for shuffle mode)
  final Map<int, int> _shuffleIndex = {};

  /// Shuffled order per container (for shuffle mode)
  final Map<int, List<int>> _shuffleOrder = {};

  /// Round robin index per container
  final Map<int, int> _roundRobinIndex = {};

  /// Next available container ID
  int _nextContainerId = 1;

  // ═══════════════════════════════════════════════════════════════════════════
  // DETERMINISM MODE (M4)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Seeded Random instances per container (for deterministic mode)
  final Map<int, Random> _seededRandoms = {};

  /// Selection history for event tracing (containerId -> list of selection records)
  final Map<int, List<DeterministicSelectionRecord>> _selectionHistory = {};

  /// Global deterministic mode override (applies to all containers)
  bool _globalDeterministicMode = false;

  /// Get global deterministic mode state
  bool get globalDeterministicMode => _globalDeterministicMode;

  /// Set global deterministic mode (overrides per-container setting)
  void setGlobalDeterministicMode(bool enabled) {
    _globalDeterministicMode = enabled;
    notifyListeners();
    debugPrint('[RandomContainers] Global deterministic mode: $enabled');
  }

  RandomContainersProvider({required NativeFFI ffi}) : _ffi = ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all random containers
  Map<int, RandomContainer> get containers => Map.unmodifiable(_containers);

  /// Get all random containers as list
  List<RandomContainer> get randomContainers => _containers.values.toList();

  /// Get count of random containers
  int get containerCount => _containers.length;

  /// Get a specific random container
  RandomContainer? getContainer(int containerId) => _containers[containerId];

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTAINER MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new random container
  RandomContainer createContainer({
    required String name,
    RandomMode mode = RandomMode.random,
    int avoidRepeatCount = 2,
    double globalPitchMin = 0.0,
    double globalPitchMax = 0.0,
    double globalVolumeMin = 0.0,
    double globalVolumeMax = 0.0,
  }) {
    final id = _nextContainerId++;

    final container = RandomContainer(
      id: id,
      name: name,
      mode: mode,
      avoidRepeatCount: avoidRepeatCount,
      globalPitchMin: globalPitchMin,
      globalPitchMax: globalPitchMax,
      globalVolumeMin: globalVolumeMin,
      globalVolumeMax: globalVolumeMax,
    );

    _containers[id] = container;
    _ffi.middlewareCreateRandomContainer(container);

    // P2: Sync to Rust Container FFI for sub-ms selection
    ContainerService.instance.syncRandomToRust(container);

    notifyListeners();
    return container;
  }

  /// Register a random container (from JSON import or preset)
  void registerContainer(RandomContainer container) {
    _containers[container.id] = container;

    // Update next ID if needed
    if (container.id >= _nextContainerId) {
      _nextContainerId = container.id + 1;
    }

    // Register with Rust middleware
    _ffi.middlewareCreateRandomContainer(container);

    // P2: Sync to Container FFI
    ContainerService.instance.syncRandomToRust(container);

    notifyListeners();
  }

  /// Update a random container
  void updateContainer(RandomContainer container) {
    if (!_containers.containsKey(container.id)) return;

    _containers[container.id] = container;

    // Re-register with Rust middleware
    _ffi.middlewareRemoveRandomContainer(container.id);
    _ffi.middlewareCreateRandomContainer(container);

    // P2: Re-sync to Container FFI
    ContainerService.instance.unsyncRandomFromRust(container.id);
    ContainerService.instance.syncRandomToRust(container);

    // Reset playback state when mode changes
    _playHistory.remove(container.id);
    _shuffleIndex.remove(container.id);
    _shuffleOrder.remove(container.id);
    _roundRobinIndex.remove(container.id);

    notifyListeners();
  }

  /// Remove a random container
  void removeContainer(int containerId) {
    _containers.remove(containerId);
    _playHistory.remove(containerId);
    _shuffleIndex.remove(containerId);
    _shuffleOrder.remove(containerId);
    _roundRobinIndex.remove(containerId);

    _ffi.middlewareRemoveRandomContainer(containerId);

    // P2: Remove from Container FFI
    ContainerService.instance.unsyncRandomFromRust(containerId);

    notifyListeners();
  }

  /// Enable/disable a random container
  void setContainerEnabled(int containerId, bool enabled) {
    final container = _containers[containerId];
    if (container == null) return;

    _containers[containerId] = container.copyWith(enabled: enabled);
    notifyListeners();
  }

  /// Set global variation (convenience for MiddlewareProvider compatibility)
  void setGlobalVariation(
    int containerId, {
    double pitchMin = 0.0,
    double pitchMax = 0.0,
    double volumeMin = 0.0,
    double volumeMax = 0.0,
  }) {
    final container = _containers[containerId];
    if (container == null) return;

    _containers[containerId] = container.copyWith(
      globalPitchMin: pitchMin,
      globalPitchMax: pitchMax,
      globalVolumeMin: volumeMin,
      globalVolumeMax: volumeMax,
    );

    _ffi.middlewareRandomSetGlobalVariation(
      containerId,
      pitchMin: pitchMin,
      pitchMax: pitchMax,
      volumeMin: volumeMin,
      volumeMax: volumeMax,
    );
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHILD MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a child to a random container
  void addChild(int containerId, RandomChild child) {
    final container = _containers[containerId];
    if (container == null) return;

    final updatedChildren = [...container.children, child];
    _containers[containerId] = container.copyWith(children: updatedChildren);

    // Reset shuffle order when children change
    _shuffleOrder.remove(containerId);

    _ffi.middlewareRandomAddChild(containerId, child);
    notifyListeners();
  }

  /// Remove a child from a random container
  void removeChild(int containerId, int childId) {
    final container = _containers[containerId];
    if (container == null) return;

    final updatedChildren = container.children.where((c) => c.id != childId).toList();
    _containers[containerId] = container.copyWith(children: updatedChildren);

    // Reset shuffle order when children change
    _shuffleOrder.remove(containerId);

    _ffi.middlewareRandomRemoveChild(containerId, childId);
    notifyListeners();
  }

  /// Update a child in a random container
  void updateChild(int containerId, RandomChild child) {
    final container = _containers[containerId];
    if (container == null) return;

    final updatedChildren = container.children.map((c) {
      return c.id == child.id ? child : c;
    }).toList();
    _containers[containerId] = container.copyWith(children: updatedChildren);

    // Update Rust
    _ffi.middlewareRemoveRandomContainer(containerId);
    _ffi.middlewareCreateRandomContainer(_containers[containerId]!);

    notifyListeners();
  }

  /// Create a new child with auto-generated ID
  RandomChild createChild({
    required int containerId,
    required String name,
    String? audioPath,
    double weight = 1.0,
    double pitchMin = 0.0,
    double pitchMax = 0.0,
    double volumeMin = 0.0,
    double volumeMax = 0.0,
  }) {
    final container = _containers[containerId];
    final nextId = (container?.children.length ?? 0) + 1;

    return RandomChild(
      id: nextId,
      name: name,
      audioPath: audioPath,
      weight: weight,
      pitchMin: pitchMin,
      pitchMax: pitchMax,
      volumeMin: volumeMin,
      volumeMax: volumeMax,
    );
  }

  /// Update audio path for a specific child
  void updateChildAudioPath(int containerId, int childId, String? audioPath) {
    final container = _containers[containerId];
    if (container == null) return;

    final updatedChildren = container.children.map((c) {
      if (c.id == childId) {
        return c.copyWith(audioPath: audioPath);
      }
      return c;
    }).toList();

    _containers[containerId] = container.copyWith(children: updatedChildren);

    // Re-register with Rust
    _ffi.middlewareRemoveRandomContainer(containerId);
    _ffi.middlewareCreateRandomContainer(_containers[containerId]!);

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RANDOM SELECTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Select a random child from the container
  /// Returns null if no valid selection available
  RandomChildSelection? selectChild(int containerId) {
    final container = _containers[containerId];
    if (container == null || !container.enabled || container.children.isEmpty) {
      return null;
    }

    // Determine which Random to use (seeded or default)
    final useSeeded = _globalDeterministicMode || container.useDeterministicMode;
    final rng = useSeeded ? _getSeededRandom(container) : _random;

    final selectedChild = switch (container.mode) {
      RandomMode.random => _selectRandom(container, rng),
      RandomMode.shuffle => _selectShuffle(container, rng),
      RandomMode.shuffleWithHistory => _selectShuffleWithHistory(container, rng),
      RandomMode.roundRobin => _selectRoundRobin(container),
    };

    if (selectedChild == null) return null;

    // Calculate randomization offsets using same RNG
    final pitchOffset = _randomInRange(
      container.globalPitchMin + selectedChild.pitchMin,
      container.globalPitchMax + selectedChild.pitchMax,
      rng,
    );
    final volumeOffset = _randomInRange(
      container.globalVolumeMin + selectedChild.volumeMin,
      container.globalVolumeMax + selectedChild.volumeMax,
      rng,
    );

    // Update history
    _updateHistory(containerId, selectedChild.id, container.avoidRepeatCount);

    // Record selection for tracing (M4 Determinism)
    if (useSeeded) {
      _recordSelection(container, selectedChild.id);
    }

    return RandomChildSelection(
      child: selectedChild,
      pitchOffset: pitchOffset,
      volumeMultiplier: 1.0 + volumeOffset,
    );
  }

  /// Get or create seeded Random for a container (M4 Determinism)
  Random _getSeededRandom(RandomContainer container) {
    if (!_seededRandoms.containsKey(container.id)) {
      final seed = container.seed ?? RandomContainer.generateSeed();
      _seededRandoms[container.id] = Random(seed);
      debugPrint('[RandomContainers] Created seeded Random for ${container.name} with seed: $seed');
    }
    return _seededRandoms[container.id]!;
  }

  /// Record selection for event tracing (M4 Determinism)
  void _recordSelection(RandomContainer container, int childId) {
    _selectionHistory[container.id] ??= [];
    final history = _selectionHistory[container.id]!;

    history.add(DeterministicSelectionRecord(
      containerId: container.id,
      selectedChildId: childId,
      seed: container.seed ?? 0,
      sequenceIndex: history.length,
      timestamp: DateTime.now(),
    ));

    // Keep last 100 records per container
    if (history.length > 100) {
      history.removeAt(0);
    }
  }

  /// Get selection history for a container (M4 Determinism)
  List<DeterministicSelectionRecord> getSelectionHistory(int containerId) {
    return List.unmodifiable(_selectionHistory[containerId] ?? []);
  }

  /// Reset seeded random for a container (starts fresh from seed)
  void resetSeededRandom(int containerId) {
    _seededRandoms.remove(containerId);
    _selectionHistory.remove(containerId);
    debugPrint('[RandomContainers] Reset seeded Random for container $containerId');
  }

  /// Set deterministic mode for a specific container
  void setDeterministicMode(int containerId, bool enabled, {int? seed}) {
    final container = _containers[containerId];
    if (container == null) return;

    final newSeed = seed ?? (enabled ? RandomContainer.generateSeed() : null);
    _containers[containerId] = container.copyWith(
      useDeterministicMode: enabled,
      seed: newSeed,
    );

    // Reset seeded random to use new seed
    _seededRandoms.remove(containerId);
    _selectionHistory.remove(containerId);

    notifyListeners();
    debugPrint('[RandomContainers] Deterministic mode for ${container.name}: $enabled (seed: $newSeed)');
  }

  RandomChild? _selectRandom(RandomContainer container, Random rng) {
    final history = _playHistory[container.id] ?? [];
    final availableChildren = container.children.where((c) {
      return !history.contains(c.id);
    }).toList();

    // If all children are in history, use all children
    final candidates = availableChildren.isEmpty ? container.children : availableChildren;
    if (candidates.isEmpty) return null;

    // Weighted random selection
    final totalWeight = candidates.fold<double>(0, (sum, c) => sum + c.weight);
    if (totalWeight <= 0) return candidates.first;

    var target = rng.nextDouble() * totalWeight;
    for (final child in candidates) {
      target -= child.weight;
      if (target <= 0) return child;
    }

    return candidates.last;
  }

  RandomChild? _selectShuffle(RandomContainer container, Random rng) {
    // Initialize shuffle order if needed
    if (!_shuffleOrder.containsKey(container.id) ||
        _shuffleOrder[container.id]!.length != container.children.length) {
      final order = List<int>.generate(container.children.length, (i) => i);
      order.shuffle(rng);
      _shuffleOrder[container.id] = order;
      _shuffleIndex[container.id] = 0;
    }

    final order = _shuffleOrder[container.id]!;
    var index = _shuffleIndex[container.id] ?? 0;

    // Reshuffle if at end
    if (index >= order.length) {
      order.shuffle(rng);
      index = 0;
    }

    _shuffleIndex[container.id] = index + 1;

    if (order[index] >= container.children.length) return null;
    return container.children[order[index]];
  }

  RandomChild? _selectShuffleWithHistory(RandomContainer container, Random rng) {
    // Similar to shuffle but tracks history to avoid repeats
    final history = _playHistory[container.id] ?? [];
    final availableChildren = container.children.where((c) {
      return !history.contains(c.id);
    }).toList();

    // If no available children, reset history and use all
    if (availableChildren.isEmpty) {
      _playHistory[container.id] = [];
      return _selectRandom(container, rng);
    }

    // Select randomly from available
    return availableChildren[rng.nextInt(availableChildren.length)];
  }

  RandomChild? _selectRoundRobin(RandomContainer container) {
    var index = _roundRobinIndex[container.id] ?? 0;

    if (index >= container.children.length) {
      index = 0;
    }

    _roundRobinIndex[container.id] = index + 1;
    return container.children[index];
  }

  void _updateHistory(int containerId, int childId, int maxHistory) {
    _playHistory[containerId] ??= [];
    final history = _playHistory[containerId]!;

    history.add(childId);

    // Trim history to avoid-repeat count
    while (history.length > maxHistory) {
      history.removeAt(0);
    }
  }

  double _randomInRange(double min, double max, Random rng) {
    if (min >= max) return 0.0;
    return min + rng.nextDouble() * (max - min);
  }

  /// Reset playback state (history, shuffle, etc.)
  void resetPlaybackState(int containerId) {
    _playHistory.remove(containerId);
    _shuffleIndex.remove(containerId);
    _shuffleOrder.remove(containerId);
    _roundRobinIndex.remove(containerId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export random containers to JSON
  List<Map<String, dynamic>> toJson() {
    return _containers.values.map((c) => c.toJson()).toList();
  }

  /// Import random containers from JSON
  void fromJson(List<dynamic> json) {
    for (final item in json) {
      final container = RandomContainer.fromJson(item as Map<String, dynamic>);
      registerContainer(container);
    }
  }

  /// Clear all random containers
  void clear() {
    // Remove from Rust
    for (final containerId in _containers.keys.toList()) {
      _ffi.middlewareRemoveRandomContainer(containerId);
    }

    _containers.clear();
    _playHistory.clear();
    _shuffleIndex.clear();
    _shuffleOrder.clear();
    _roundRobinIndex.clear();
    _nextContainerId = 1;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export all selection history to JSON (M4 Determinism - for QA/debugging)
  List<Map<String, dynamic>> exportSelectionHistoryToJson() {
    final result = <Map<String, dynamic>>[];
    for (final entry in _selectionHistory.entries) {
      for (final record in entry.value) {
        result.add(record.toJson());
      }
    }
    return result;
  }

  /// Clear all selection history
  void clearSelectionHistory() {
    _selectionHistory.clear();
    debugPrint('[RandomContainers] Cleared all selection history');
  }

  @override
  void dispose() {
    _containers.clear();
    _playHistory.clear();
    _shuffleIndex.clear();
    _shuffleOrder.clear();
    _roundRobinIndex.clear();
    _seededRandoms.clear();
    _selectionHistory.clear();
    super.dispose();
  }
}
