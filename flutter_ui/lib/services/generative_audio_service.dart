// FAZA 5.1.3 — Dart bindings for `rf-bridge::generative_ffi`.
//
// Mirrors `GenerativeFfiBuffer` (repr(C)) from
// `crates/rf-bridge/src/generative_ffi.rs`. Sends `GenerationRequest` as
// JSON, receives an interleaved `Float32List` plus provenance metadata,
// and frees the native buffer exactly once.
//
// Threading model: the underlying inference call is blocking. For the
// `MockBackend` it costs sub-millisecond per 100 ms of audio, so calling
// from the UI thread is fine. Once `feature = "onnx"` ships a real model
// (5.1.2), callers MUST move this off the UI thread (e.g. via `Isolate.run`)
// — the API itself is `async` precisely so we don't have to change it later.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Coarse stage hints — keep in sync with `rf_generative::SlotStageHint`.
enum SlotStageHint {
  idle,
  anticipation,
  reelStop,
  winSmall,
  winMedium,
  winBig,
  winMega,
  bonusTrigger,
  freeSpinStart,
  jackpotHit,
  cascade,
  gameOver;

  /// snake_case identifier expected on the wire.
  String get wireName {
    switch (this) {
      case SlotStageHint.idle:
        return 'idle';
      case SlotStageHint.anticipation:
        return 'anticipation';
      case SlotStageHint.reelStop:
        return 'reel_stop';
      case SlotStageHint.winSmall:
        return 'win_small';
      case SlotStageHint.winMedium:
        return 'win_medium';
      case SlotStageHint.winBig:
        return 'win_big';
      case SlotStageHint.winMega:
        return 'win_mega';
      case SlotStageHint.bonusTrigger:
        return 'bonus_trigger';
      case SlotStageHint.freeSpinStart:
        return 'free_spin_start';
      case SlotStageHint.jackpotHit:
        return 'jackpot_hit';
      case SlotStageHint.cascade:
        return 'cascade';
      case SlotStageHint.gameOver:
        return 'game_over';
    }
  }
}

/// Single point of an emotional arc envelope. Both fields are normalized
/// to `[0.0, 1.0]`. Points must be monotonic in `t` — backend will reject
/// otherwise.
class EmotionalArcPoint {
  final double t;
  final double intensity;
  const EmotionalArcPoint({required this.t, required this.intensity});

  Map<String, dynamic> toJson() => {'t': t, 'intensity': intensity};
}

/// Time-varying emotional intensity envelope.
class EmotionalArc {
  final List<EmotionalArcPoint> points;
  const EmotionalArc(this.points);

  Map<String, dynamic> toJson() =>
      {'points': points.map((p) => p.toJson()).toList()};
}

class GenerationStyle {
  final SlotStageHint? stageHint;
  final EmotionalArc? emotionalArc;
  final List<String> tags;

  const GenerationStyle({
    this.stageHint,
    this.emotionalArc,
    this.tags = const [],
  });

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{};
    if (stageHint != null) out['stage_hint'] = stageHint!.wireName;
    if (emotionalArc != null) out['emotional_arc'] = emotionalArc!.toJson();
    if (tags.isNotEmpty) out['tags'] = tags;
    return out;
  }
}

class GenerationRequest {
  final String prompt;
  final double durationSeconds;
  final int sampleRateHz; // 0 = backend native
  final int? seed;
  final GenerationStyle style;

  const GenerationRequest({
    required this.prompt,
    required this.durationSeconds,
    this.sampleRateHz = 0,
    this.seed,
    this.style = const GenerationStyle(),
  });

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'duration_seconds': durationSeconds,
        'sample_rate_hz': sampleRateHz,
        if (seed != null) 'seed': seed,
        'style': style.toJson(),
      };

  /// Build a copy with a different seed — used by 5.1.7 variation generation
  /// to step a single request across N deterministic seeds.
  GenerationRequest withSeed(int newSeed) => GenerationRequest(
        prompt: prompt,
        durationSeconds: durationSeconds,
        sampleRateHz: sampleRateHz,
        seed: newSeed,
        style: style,
      );
}

/// Provenance + timing info that always travels with a generated buffer.
class GenerationMetadata {
  final String backendId;
  final String modelId;
  final int? seed;
  final String generatedAtUtc;
  final double durationSeconds;
  final int frameCount;

  const GenerationMetadata({
    required this.backendId,
    required this.modelId,
    required this.seed,
    required this.generatedAtUtc,
    required this.durationSeconds,
    required this.frameCount,
  });

  factory GenerationMetadata.fromJson(Map<String, dynamic> json) =>
      GenerationMetadata(
        backendId: json['backend_id'] as String? ?? 'unknown',
        modelId: json['model_id'] as String? ?? 'none',
        seed: (json['seed'] as num?)?.toInt(),
        generatedAtUtc: json['generated_at_utc'] as String? ?? '',
        durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 0.0,
        frameCount: (json['frame_count'] as num?)?.toInt() ?? 0,
      );
}

/// Returned to UI callers. PCM is a *copy* of the native buffer — the
/// native side is freed before this object exists.
class GenerationResult {
  final Float32List pcm;
  final int sampleRateHz;
  final int channels;
  final int latencyMs;
  final GenerationMetadata metadata;

  const GenerationResult({
    required this.pcm,
    required this.sampleRateHz,
    required this.channels,
    required this.latencyMs,
    required this.metadata,
  });

  int get frameCount => channels == 0 ? 0 : pcm.length ~/ channels;
}

/// Thrown when the Rust side reports a structured error (validation,
/// backend failure, etc.). Distinct from FFI / library-load failures
/// which surface as plain `StateError`.
class GenerationException implements Exception {
  final String message;
  GenerationException(this.message);
  @override
  String toString() => 'GenerationException: $message';
}

/// Native repr(C) mirror of `GenerativeFfiBuffer`. Must match the Rust
/// struct field-for-field (incl. padding).
final class _GenerativeFfiBuffer extends Struct {
  external Pointer<Float> pcmPtr;
  @Size()
  external int pcmLen;
  @Uint32()
  external int sampleRateHz;
  @Uint16()
  external int channels;
  @Uint16()
  external int pad;
  @Uint32()
  external int latencyMs;
  external Pointer<Utf8> metadataJson;
  external Pointer<Utf8> errorJson;
}

typedef _GenerateNative = _GenerativeFfiBuffer Function(Pointer<Utf8>);
typedef _GenerateDart = _GenerativeFfiBuffer Function(Pointer<Utf8>);

typedef _FreeBufferNative = Void Function(_GenerativeFfiBuffer);
typedef _FreeBufferDart = void Function(_GenerativeFfiBuffer);

class GenerativeAudioService {
  GenerativeAudioService._();
  static final GenerativeAudioService instance = GenerativeAudioService._();

  DynamicLibrary? _lib;
  _GenerateDart? _generate;
  _FreeBufferDart? _freeBuffer;

  void _ensureLoaded() {
    if (_lib != null) return;
    final lib = _openLibrary();
    _generate = lib
        .lookupFunction<_GenerateNative, _GenerateDart>('generative_generate');
    _freeBuffer = lib.lookupFunction<_FreeBufferNative, _FreeBufferDart>(
        'generative_free_buffer');
    _lib = lib;
  }

  DynamicLibrary _openLibrary() {
    // Same probing order as `NativeFFI._openLibrary` — cdylib lives next
    // to the app on every supported platform.
    if (Platform.isMacOS) {
      return DynamicLibrary.open('librf_bridge.dylib');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('librf_bridge.so');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('rf_bridge.dll');
    }
    throw StateError(
        'GenerativeAudioService: unsupported platform ${Platform.operatingSystem}');
  }

  /// Run a generation request. Async so callers can `await` and we can
  /// later move the work to an isolate without changing the signature.
  ///
  /// Throws `GenerationException` for validation / backend errors. Throws
  /// `StateError` if the library is missing or FFI symbols are absent.
  Future<GenerationResult> generate(GenerationRequest request) async {
    _ensureLoaded();
    final generate = _generate!;
    final freeBuffer = _freeBuffer!;

    final requestJson = jsonEncode(request.toJson());
    final requestPtr = requestJson.toNativeUtf8();
    _GenerativeFfiBuffer buf;
    try {
      buf = generate(requestPtr);
    } finally {
      malloc.free(requestPtr);
    }

    try {
      // Error path: pcmPtr null + errorJson populated.
      if (buf.pcmPtr == nullptr || buf.pcmLen == 0) {
        final message = buf.errorJson == nullptr
            ? 'generative_generate returned an empty buffer with no error'
            : _decodeError(buf.errorJson.toDartString());
        throw GenerationException(message);
      }

      // Copy PCM out of native memory into Dart-owned Float32List.
      final native = buf.pcmPtr.asTypedList(buf.pcmLen);
      final pcm = Float32List(buf.pcmLen)..setAll(0, native);

      final metadata = buf.metadataJson == nullptr
          ? const GenerationMetadata(
              backendId: 'unknown',
              modelId: 'none',
              seed: null,
              generatedAtUtc: '',
              durationSeconds: 0,
              frameCount: 0,
            )
          : GenerationMetadata.fromJson(
              jsonDecode(buf.metadataJson.toDartString())
                  as Map<String, dynamic>,
            );

      return GenerationResult(
        pcm: pcm,
        sampleRateHz: buf.sampleRateHz,
        channels: buf.channels,
        latencyMs: buf.latencyMs,
        metadata: metadata,
      );
    } finally {
      // Always free — native side coalesces null pointers safely.
      freeBuffer(buf);
    }
  }

  /// FAZA 5.1.7 — generate N variations of the same request, stepping the
  /// seed deterministically so the same `(request, count)` pair always
  /// yields byte-identical variations.
  ///
  /// Semantics:
  /// - `count` is clamped to `[1, 10]` (UI never sends out-of-range; the
  ///   clamp is defensive so a stray caller can't DoS the FFI).
  /// - Base seed = `request.seed` if present, otherwise a deterministic
  ///   hash of the prompt+arc — this means an "auto" request still produces
  ///   stable variations across reruns of the same session.
  /// - Seeds step by 7919 (a prime) so adjacent variations diverge
  ///   meaningfully across MockBackend's chord presets rather than landing
  ///   on adjacent integers that may map to similar timbres.
  /// - Sequential (one at a time); the MockBackend is sub-millisecond and
  ///   the future ONNX backend will live on a worker isolate either way.
  /// - Atomic: if *any* variation fails the whole call throws — partial
  ///   lists confuse the UI (which variation is missing?). The caller
  ///   re-runs after fixing the request.
  Future<List<GenerationResult>> generateVariations(
    GenerationRequest request,
    int count,
  ) async {
    final n = count.clamp(1, 10);
    final baseSeed = request.seed ?? _deterministicSeed(request);
    final out = <GenerationResult>[];
    for (var i = 0; i < n; i++) {
      // Step by a prime so seed differences don't trivially align with
      // SplitMix64's mixing pattern.
      final s = (baseSeed + (i * 7919)) & 0x7FFFFFFFFFFFFFFF;
      out.add(await generate(request.withSeed(s)));
    }
    return out;
  }

  /// Cheap, stable seed derivation when the caller didn't pin one. Uses
  /// FNV-1a 64 over prompt + arc — same input → same starting seed across
  /// app restarts, which matches user expectation ("re-roll the same brief").
  int _deterministicSeed(GenerationRequest req) {
    const fnvOffset = 0xcbf29ce484222325;
    const fnvPrime = 0x100000001b3;
    var hash = fnvOffset;
    void mix(String s) {
      for (final code in s.codeUnits) {
        hash ^= code;
        hash = (hash * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
      }
    }

    mix(req.prompt);
    mix(req.durationSeconds.toStringAsFixed(3));
    mix(req.style.stageHint?.wireName ?? '');
    for (final p in req.style.emotionalArc?.points ?? const []) {
      mix(p.t.toStringAsFixed(4));
      mix(p.intensity.toStringAsFixed(4));
    }
    for (final tag in req.style.tags) {
      mix(tag);
    }
    // Mask to 63 bits — Rust side `seed: Option<u64>` accepts the value but
    // staying in non-negative i64 keeps Dart JSON encoding boring.
    return hash & 0x7FFFFFFFFFFFFFFF;
  }

  /// Decode a `{"error": "..."}` JSON blob into a readable message. Falls
  /// back to the raw payload if it doesn't parse.
  String _decodeError(String raw) {
    try {
      final v = jsonDecode(raw);
      if (v is Map && v['error'] is String) return v['error'] as String;
    } catch (_) {/* fall through */}
    return raw;
  }
}
