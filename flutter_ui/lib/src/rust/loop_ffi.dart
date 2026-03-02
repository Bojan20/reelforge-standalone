/// Advanced Loop System FFI Bindings
///
/// Dart bindings for Wwise-grade loop control: LoopAsset registration,
/// instance lifecycle, region switching, per-iteration gain, marker ingest.
///
/// Usage: Access via NativeFFI.instance extension methods.

import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'native_ffi.dart';
import '../../models/loop_asset_models.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ADVANCED LOOP SYSTEM EXTENSION
// ═══════════════════════════════════════════════════════════════════════════════

extension AdvancedLoopFFI on NativeFFI {
  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize the advanced looping system.
  bool loopSystemInit({int sampleRate = 48000}) {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(Uint32),
        int Function(int)
      >('loop_system_init');
      return fn(sampleRate) == 1;
    } catch (e) {
      return false;
    }
  }

  /// Check if the loop system is initialized.
  bool loopSystemIsInitialized() {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(),
        int Function()
      >('loop_system_is_initialized');
      return fn() == 1;
    } catch (e) {
      return false;
    }
  }

  /// Destroy the loop system and free resources.
  bool loopSystemDestroy() {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(),
        int Function()
      >('loop_system_destroy');
      return fn() == 1;
    } catch (e) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ASSET REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a LoopAsset via the command queue (sent to audio thread).
  bool loopRegisterAssetJson(LoopAsset asset) {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)
      >('loop_register_asset_json');
      return withNativeString(asset.toJsonString(), (ptr) => fn(ptr) == 1);
    } catch (e) {
      return false;
    }
  }

  /// Register a LoopAsset directly (stored for audio thread pickup).
  bool loopRegisterAssetDirect(LoopAsset asset) {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)
      >('loop_register_asset_direct');
      return withNativeString(asset.toJsonString(), (ptr) => fn(ptr) == 1);
    } catch (e) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYBACK CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start a loop instance.
  bool loopPlay({
    required String assetId,
    required String region,
    double volume = 1.0,
    int bus = 0,
    bool useDualVoice = false,
    double fadeInMs = 0.0,
  }) {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Float, Uint32, Int32, Float),
        int Function(Pointer<Utf8>, Pointer<Utf8>, double, int, int, double)
      >('loop_play');
      return withNativeStrings2(assetId, region, (p1, p2) {
        return fn(p1, p2, volume, bus, useDualVoice ? 1 : 0, fadeInMs) == 1;
      });
    } catch (e) {
      return false;
    }
  }

  /// Set loop region with sync mode.
  bool loopSetRegion({
    required int instanceId,
    required String region,
    SyncMode syncMode = SyncMode.immediate,
    double crossfadeMs = 50.0,
    LoopCrossfadeCurve crossfadeCurve = LoopCrossfadeCurve.equalPower,
  }) {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(Uint64, Pointer<Utf8>, Uint32, Float, Uint32),
        int Function(int, Pointer<Utf8>, int, double, int)
      >('loop_set_region');
      final regionPtr = region.toNativeUtf8();
      try {
        return fn(instanceId, regionPtr, syncMode.engineIndex,
                crossfadeMs, crossfadeCurve.engineIndex) ==
            1;
      } finally {
        calloc.free(regionPtr);
      }
    } catch (e) {
      return false;
    }
  }

  /// Exit a loop instance.
  bool loopExit({
    required int instanceId,
    SyncMode syncMode = SyncMode.immediate,
    double fadeOutMs = 0.0,
    bool playPostExit = false,
  }) {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(Uint64, Uint32, Float, Int32),
        int Function(int, int, double, int)
      >('loop_exit');
      return fn(instanceId, syncMode.engineIndex, fadeOutMs,
              playPostExit ? 1 : 0) ==
          1;
    } catch (e) {
      return false;
    }
  }

  /// Stop a loop instance immediately (optional fade).
  bool loopStop({required int instanceId, double fadeOutMs = 0.0}) {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(Uint64, Float),
        int Function(int, double)
      >('loop_stop');
      return fn(instanceId, fadeOutMs) == 1;
    } catch (e) {
      return false;
    }
  }

  /// Set volume on a loop instance.
  bool loopSetVolume({
    required int instanceId,
    required double volume,
    double fadeMs = 0.0,
  }) {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(Uint64, Float, Float),
        int Function(int, double, double)
      >('loop_set_volume');
      return fn(instanceId, volume, fadeMs) == 1;
    } catch (e) {
      return false;
    }
  }

  /// Set bus routing for a loop instance.
  bool loopSetBus({required int instanceId, required int bus}) {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(Uint64, Uint32),
        int Function(int, int)
      >('loop_set_bus');
      return fn(instanceId, bus) == 1;
    } catch (e) {
      return false;
    }
  }

  /// Seek to a position (debug/QA).
  bool loopSeek({required int instanceId, required int positionSamples}) {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(Uint64, Uint64),
        int Function(int, int)
      >('loop_seek');
      return fn(instanceId, positionSamples) == 1;
    } catch (e) {
      return false;
    }
  }

  /// Set per-iteration gain factor.
  bool loopSetIterationGain({
    required int instanceId,
    required double factor,
  }) {
    try {
      final fn = lib.lookupFunction<
        Int32 Function(Uint64, Float),
        int Function(int, double)
      >('loop_set_iteration_gain');
      return fn(instanceId, factor) == 1;
    } catch (e) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CALLBACK POLLING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Poll next callback from the audio thread.
  /// Returns null if no callback available.
  LoopCallback? loopPollCallback() {
    try {
      final pollFn = lib.lookupFunction<
        Pointer<Utf8> Function(),
        Pointer<Utf8> Function()
      >('loop_poll_callback');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('loop_free_string');

      final ptr = pollFn();
      if (ptr == nullptr) return null;

      final json = ptr.toDartString();
      freeFn(ptr);

      return LoopCallback.fromJsonString(json);
    } catch (e) {
      return null;
    }
  }

  /// Drain all available callbacks.
  List<LoopCallback> loopDrainCallbacks({int maxCount = 64}) {
    final callbacks = <LoopCallback>[];
    for (int i = 0; i < maxCount; i++) {
      final cb = loopPollCallback();
      if (cb == null) break;
      callbacks.add(cb);
    }
    return callbacks;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARKER INGEST
  // ═══════════════════════════════════════════════════════════════════════════

  /// Parse sidecar markers (.ffmarkers.json) and return a LoopAsset.
  LoopAsset? loopParseSidecarMarkers({
    required String sidecarJson,
    required String assetId,
    required String soundId,
    int sampleRate = 48000,
    int channels = 2,
    required int lengthSamples,
  }) {
    try {
      final parseFn = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Uint32, Uint16, Uint64),
        Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int, int, int)
      >('loop_parse_sidecar_markers');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('loop_free_string');

      final p1 = sidecarJson.toNativeUtf8();
      final p2 = assetId.toNativeUtf8();
      final p3 = soundId.toNativeUtf8();
      try {
        final ptr = parseFn(p1, p2, p3, sampleRate, channels, lengthSamples);
        if (ptr == nullptr) return null;

        final json = ptr.toDartString();
        freeFn(ptr);

        return LoopAsset.fromJsonString(json);
      } finally {
        calloc.free(p1);
        calloc.free(p2);
        calloc.free(p3);
      }
    } catch (e) {
      return null;
    }
  }

  /// Validate a LoopAsset. Returns null if valid, error list if invalid.
  List<String>? loopValidateAsset(LoopAsset asset) {
    try {
      final validateFn = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)
      >('loop_validate_asset');

      final freeFn = lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('loop_free_string');

      final jsonStr = asset.toJsonString();
      final jsonPtr = jsonStr.toNativeUtf8();
      try {
        final ptr = validateFn(jsonPtr);
        if (ptr == nullptr) return null; // valid

        final result = ptr.toDartString();
        freeFn(ptr);

        final parsed = jsonDecode(result);
        if (parsed is Map && parsed.containsKey('errors')) {
          return (parsed['errors'] as List).cast<String>();
        }
        if (parsed is Map && parsed.containsKey('error')) {
          return [parsed['error'] as String];
        }
        return [result];
      } finally {
        calloc.free(jsonPtr);
      }
    } catch (e) {
      return ['FFI error: $e'];
    }
  }
}
