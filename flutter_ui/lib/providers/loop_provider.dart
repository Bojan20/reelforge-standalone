/// Loop Provider — Advanced Looping System State Management
///
/// Provides Flutter state management for the Wwise-grade loop system.
/// Handles asset registration, instance lifecycle, callback polling,
/// region switching, and per-iteration gain control.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';
import '../src/rust/loop_ffi.dart';
import '../models/loop_asset_models.dart';

class LoopProvider extends ChangeNotifier {
  static LoopProvider? _instance;
  static LoopProvider get instance {
    _instance ??= LoopProvider._();
    return _instance!;
  }

  LoopProvider._();

  bool _initialized = false;
  Timer? _pollTimer;

  /// Registered assets (id → asset).
  final Map<String, LoopAsset> _assets = {};

  /// Active instances (instanceId → state).
  final Map<int, LoopInstanceState> _instances = {};

  /// Recent callbacks (for UI display / debugging).
  final List<LoopCallback> _recentCallbacks = [];
  static const int _maxRecentCallbacks = 100;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get isInitialized => _initialized;
  Map<String, LoopAsset> get assets => Map.unmodifiable(_assets);
  Map<int, LoopInstanceState> get instances => Map.unmodifiable(_instances);
  List<LoopCallback> get recentCallbacks =>
      List.unmodifiable(_recentCallbacks);

  /// Get all active (non-stopped) instances.
  List<LoopInstanceState> get activeInstances =>
      _instances.values
          .where((i) => i.state != LoopPlaybackState.stopped)
          .toList();

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize the loop system. Call once at engine startup.
  bool init({int sampleRate = 48000}) {
    if (_initialized) return true;

    final ffi = NativeFFI.instance;
    final ok = ffi.loopSystemInit(sampleRate: sampleRate);
    if (!ok) return false;

    _initialized = true;

    // Start polling callbacks from audio thread
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 16), // ~60fps
      (_) => _pollCallbacks(),
    );

    notifyListeners();
    return true;
  }

  /// Destroy the loop system.
  void destroy() {
    _pollTimer?.cancel();
    _pollTimer = null;

    if (_initialized) {
      NativeFFI.instance.loopSystemDestroy();
    }

    _initialized = false;
    _assets.clear();
    _instances.clear();
    _recentCallbacks.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ASSET MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a loop asset (both locally and to engine).
  bool registerAsset(LoopAsset asset) {
    if (!_initialized) return false;

    // Validate first
    final errors = NativeFFI.instance.loopValidateAsset(asset);
    if (errors != null) {
      assert(() { debugPrint('[LoopProvider] Asset validation failed: $errors'); return true; }());
      return false;
    }

    // Register to engine
    final ok = NativeFFI.instance.loopRegisterAssetDirect(asset);
    if (!ok) return false;

    _assets[asset.id] = asset;
    notifyListeners();
    return true;
  }

  /// Unregister an asset (local only — engine handles cleanup).
  void unregisterAsset(String assetId) {
    _assets.remove(assetId);
    notifyListeners();
  }

  /// Get asset by ID.
  LoopAsset? getAsset(String assetId) => _assets[assetId];

  /// Parse sidecar markers and register the resulting asset.
  LoopAsset? importFromSidecar({
    required String sidecarJson,
    required String assetId,
    required String soundId,
    int sampleRate = 48000,
    int channels = 2,
    required int lengthSamples,
    bool autoRegister = true,
  }) {
    final asset = NativeFFI.instance.loopParseSidecarMarkers(
      sidecarJson: sidecarJson,
      assetId: assetId,
      soundId: soundId,
      sampleRate: sampleRate,
      channels: channels,
      lengthSamples: lengthSamples,
    );
    if (asset == null) return null;

    if (autoRegister) {
      registerAsset(asset);
    }
    return asset;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYBACK CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Play a loop instance.
  bool play({
    required String assetId,
    String region = 'LoopA',
    double volume = 1.0,
    int bus = 0,
    bool useDualVoice = false,
    double fadeInMs = 0.0,
  }) {
    if (!_initialized) return false;
    return NativeFFI.instance.loopPlay(
      assetId: assetId,
      region: region,
      volume: volume,
      bus: bus,
      useDualVoice: useDualVoice,
      fadeInMs: fadeInMs,
    );
  }

  /// Switch loop region.
  bool setRegion({
    required int instanceId,
    required String region,
    SyncMode syncMode = SyncMode.immediate,
    double crossfadeMs = 50.0,
    LoopCrossfadeCurve crossfadeCurve = LoopCrossfadeCurve.equalPower,
  }) {
    if (!_initialized) return false;
    return NativeFFI.instance.loopSetRegion(
      instanceId: instanceId,
      region: region,
      syncMode: syncMode,
      crossfadeMs: crossfadeMs,
      crossfadeCurve: crossfadeCurve,
    );
  }

  /// Exit a loop instance.
  bool exit({
    required int instanceId,
    SyncMode syncMode = SyncMode.immediate,
    double fadeOutMs = 0.0,
    bool playPostExit = false,
  }) {
    if (!_initialized) return false;
    return NativeFFI.instance.loopExit(
      instanceId: instanceId,
      syncMode: syncMode,
      fadeOutMs: fadeOutMs,
      playPostExit: playPostExit,
    );
  }

  /// Stop a loop instance.
  bool stop({required int instanceId, double fadeOutMs = 0.0}) {
    if (!_initialized) return false;
    return NativeFFI.instance.loopStop(
      instanceId: instanceId,
      fadeOutMs: fadeOutMs,
    );
  }

  /// Set volume on a loop instance.
  bool setVolume({
    required int instanceId,
    required double volume,
    double fadeMs = 0.0,
  }) {
    if (!_initialized) return false;

    final ok = NativeFFI.instance.loopSetVolume(
      instanceId: instanceId,
      volume: volume,
      fadeMs: fadeMs,
    );

    if (ok) {
      final inst = _instances[instanceId];
      if (inst != null) {
        inst.volume = volume;
        notifyListeners();
      }
    }
    return ok;
  }

  /// Set bus routing.
  bool setBus({required int instanceId, required int bus}) {
    if (!_initialized) return false;

    final ok = NativeFFI.instance.loopSetBus(
      instanceId: instanceId,
      bus: bus,
    );

    if (ok) {
      final inst = _instances[instanceId];
      if (inst != null) {
        inst.bus = bus;
        notifyListeners();
      }
    }
    return ok;
  }

  /// Set per-iteration gain factor.
  bool setIterationGain({
    required int instanceId,
    required double factor,
  }) {
    if (!_initialized) return false;
    return NativeFFI.instance.loopSetIterationGain(
      instanceId: instanceId,
      factor: factor,
    );
  }

  /// Stop all active instances.
  void stopAll({double fadeOutMs = 100.0}) {
    for (final inst in activeInstances) {
      stop(instanceId: inst.instanceId, fadeOutMs: fadeOutMs);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CALLBACK POLLING
  // ═══════════════════════════════════════════════════════════════════════════

  void _pollCallbacks() {
    if (!_initialized) return;

    final callbacks = NativeFFI.instance.loopDrainCallbacks();
    if (callbacks.isEmpty) return;

    bool changed = false;

    for (final cb in callbacks) {
      _recentCallbacks.add(cb);
      if (_recentCallbacks.length > _maxRecentCallbacks) {
        _recentCallbacks.removeAt(0);
      }

      changed = true;
      _handleCallback(cb);
    }

    if (changed) {
      notifyListeners();
    }
  }

  void _handleCallback(LoopCallback cb) {
    if (cb.isStarted && cb.instanceId != null) {
      _instances[cb.instanceId!] = LoopInstanceState(
        instanceId: cb.instanceId!,
        assetId: cb.assetId ?? '',
        currentRegion: 'LoopA',
        state: LoopPlaybackState.intro,
      );
    } else if (cb.isStateChanged && cb.instanceId != null) {
      final inst = _instances[cb.instanceId!];
      if (inst != null && cb.state != null) {
        inst.state = cb.state!;
      }
    } else if (cb.isWrap && cb.instanceId != null) {
      final inst = _instances[cb.instanceId!];
      if (inst != null && cb.loopCount != null) {
        inst.loopCount = cb.loopCount!;
      }
    } else if (cb.isRegionSwitched && cb.instanceId != null) {
      final inst = _instances[cb.instanceId!];
      if (inst != null && cb.toRegion != null) {
        inst.currentRegion = cb.toRegion!;
      }
    } else if (cb.isStopped && cb.instanceId != null) {
      final inst = _instances[cb.instanceId!];
      if (inst != null) {
        inst.state = LoopPlaybackState.stopped;
      }
    }
  }

  @override
  void dispose() {
    destroy();
    super.dispose();
  }
}
