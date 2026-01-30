/// Blend Containers Provider
///
/// Extracted from MiddlewareProvider as part of P0.2 decomposition (Phase 3).
/// Manages RTPC-based crossfade between sounds (Wwise/FMOD-style).
///
/// Blend containers automatically crossfade between child sounds based on
/// an RTPC value. Example: Engine sounds crossfade based on RPM.
///
/// P2 Optimization: Syncs to Rust FFI for sub-millisecond evaluation.

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../models/middleware_models.dart';
import '../../services/container_service.dart';
import '../../src/rust/native_ffi.dart';

/// Provider for managing blend containers
class BlendContainersProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  /// Blend container storage
  final Map<int, BlendContainer> _containers = {};

  /// Next available container ID
  int _nextContainerId = 1;

  BlendContainersProvider({required NativeFFI ffi}) : _ffi = ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all blend containers
  Map<int, BlendContainer> get containers => Map.unmodifiable(_containers);

  /// Get all blend containers as list
  List<BlendContainer> get blendContainers => _containers.values.toList();

  /// Get count of blend containers
  int get containerCount => _containers.length;

  /// Get a specific blend container
  BlendContainer? getContainer(int containerId) => _containers[containerId];

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTAINER MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new blend container
  BlendContainer createContainer({
    required String name,
    required int rtpcId,
    CrossfadeCurve crossfadeCurve = CrossfadeCurve.equalPower,
  }) {
    final id = _nextContainerId++;

    final container = BlendContainer(
      id: id,
      name: name,
      rtpcId: rtpcId,
      crossfadeCurve: crossfadeCurve,
    );

    _containers[id] = container;
    _ffi.middlewareCreateBlendContainer(container);

    // P2: Sync to Rust Container FFI for sub-ms evaluation
    ContainerService.instance.syncBlendToRust(container);

    notifyListeners();
    return container;
  }

  /// Register a blend container (from JSON import or preset)
  void registerContainer(BlendContainer container) {
    _containers[container.id] = container;

    // Update next ID if needed
    if (container.id >= _nextContainerId) {
      _nextContainerId = container.id + 1;
    }

    // Register with Rust middleware
    _ffi.middlewareCreateBlendContainer(container);

    // P2: Sync to Container FFI
    ContainerService.instance.syncBlendToRust(container);

    notifyListeners();
  }

  /// Update a blend container
  void updateContainer(BlendContainer container) {
    if (!_containers.containsKey(container.id)) return;

    _containers[container.id] = container;

    // Re-register with Rust middleware
    _ffi.middlewareRemoveBlendContainer(container.id);
    _ffi.middlewareCreateBlendContainer(container);

    // P2: Re-sync to Container FFI
    ContainerService.instance.unsyncBlendFromRust(container.id);
    ContainerService.instance.syncBlendToRust(container);

    // P1-05: Sync smoothing parameter to Rust
    _ffi.containerSetBlendSmoothing(container.id, container.smoothingMs);

    notifyListeners();
  }

  /// Remove a blend container
  void removeContainer(int containerId) {
    _containers.remove(containerId);
    _ffi.middlewareRemoveBlendContainer(containerId);

    // P2: Remove from Container FFI
    ContainerService.instance.unsyncBlendFromRust(containerId);

    notifyListeners();
  }

  /// Enable/disable a blend container
  void setContainerEnabled(int containerId, bool enabled) {
    final container = _containers[containerId];
    if (container == null) return;

    _containers[containerId] = container.copyWith(enabled: enabled);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHILD MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a child to a blend container
  void addChild(int containerId, BlendChild child) {
    final container = _containers[containerId];
    if (container == null) return;

    final updatedChildren = List<BlendChild>.from(container.children)..add(child);
    _containers[containerId] = container.copyWith(children: updatedChildren);

    _ffi.middlewareBlendAddChild(containerId, child);
    notifyListeners();
  }

  /// Remove a child from a blend container
  void removeChild(int containerId, int childId) {
    final container = _containers[containerId];
    if (container == null) return;

    final updatedChildren = container.children.where((c) => c.id != childId).toList();
    _containers[containerId] = container.copyWith(children: updatedChildren);

    _ffi.middlewareBlendRemoveChild(containerId, childId);
    notifyListeners();
  }

  /// Update a child in a blend container
  void updateChild(int containerId, BlendChild child) {
    final container = _containers[containerId];
    if (container == null) return;

    final updatedChildren = container.children.map((c) => c.id == child.id ? child : c).toList();
    _containers[containerId] = container.copyWith(children: updatedChildren);

    // Re-register with Rust
    _ffi.middlewareRemoveBlendContainer(containerId);
    _ffi.middlewareCreateBlendContainer(_containers[containerId]!);

    notifyListeners();
  }

  /// Create a child with auto-generated ID
  BlendChild createChild({
    required int containerId,
    required String name,
    required double rtpcStart,
    required double rtpcEnd,
    double crossfadeWidth = 0.1,
    String? audioPath,
  }) {
    final container = _containers[containerId];
    final nextId = (container?.children.length ?? 0) + 1;

    return BlendChild(
      id: nextId,
      name: name,
      audioPath: audioPath,
      rtpcStart: rtpcStart,
      rtpcEnd: rtpcEnd,
      crossfadeWidth: crossfadeWidth,
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
    _ffi.middlewareRemoveBlendContainer(containerId);
    _ffi.middlewareCreateBlendContainer(_containers[containerId]!);

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CROSSFADE EVALUATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Evaluate blend volumes for a given RTPC value
  /// Returns map of childId -> volume (0.0-1.0)
  Map<int, double> evaluateBlend(int containerId, double rtpcValue) {
    final container = _containers[containerId];
    if (container == null || !container.enabled) return {};

    final volumes = <int, double>{};

    for (final child in container.children) {
      final volume = _calculateChildVolume(
        rtpcValue,
        child.rtpcStart,
        child.rtpcEnd,
        child.crossfadeWidth,
        container.crossfadeCurve,
      );
      if (volume > 0) {
        volumes[child.id] = volume;
      }
    }

    return volumes;
  }

  double _calculateChildVolume(
    double rtpcValue,
    double rtpcStart,
    double rtpcEnd,
    double crossfadeWidth,
    CrossfadeCurve curve,
  ) {
    // Outside range (with crossfade buffer)
    if (rtpcValue < rtpcStart - crossfadeWidth || rtpcValue > rtpcEnd + crossfadeWidth) {
      return 0.0;
    }

    // Fully in range
    if (rtpcValue >= rtpcStart && rtpcValue <= rtpcEnd) {
      return 1.0;
    }

    // In crossfade zone
    double position;
    if (rtpcValue < rtpcStart) {
      // Fading in
      position = (rtpcValue - (rtpcStart - crossfadeWidth)) / crossfadeWidth;
    } else {
      // Fading out
      position = 1.0 - (rtpcValue - rtpcEnd) / crossfadeWidth;
    }
    position = position.clamp(0.0, 1.0);

    // Apply curve
    switch (curve) {
      case CrossfadeCurve.linear:
        return position;
      case CrossfadeCurve.equalPower:
        // Equal power crossfade: sin(x * pi/2)
        return math.sin(position * math.pi / 2);
      case CrossfadeCurve.sCurve:
        // S-curve (smooth transition)
        return position * position * (3 - 2 * position);
      case CrossfadeCurve.sinCos:
        // Sin/cos transition
        return (1 - math.cos(position * math.pi)) / 2;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export blend containers to JSON
  List<Map<String, dynamic>> toJson() {
    return _containers.values.map((c) => c.toJson()).toList();
  }

  /// Import blend containers from JSON
  void fromJson(List<dynamic> json) {
    for (final item in json) {
      final container = BlendContainer.fromJson(item as Map<String, dynamic>);
      registerContainer(container);
    }
  }

  /// Clear all blend containers
  void clear() {
    for (final containerId in _containers.keys.toList()) {
      _ffi.middlewareRemoveBlendContainer(containerId);
    }

    _containers.clear();
    _nextContainerId = 1;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _containers.clear();
    super.dispose();
  }
}
