/// HRTF (Head-Related Transfer Function) FFI Bindings
///
/// Bridges the Rust `rf-bridge::hrtf_ffi` C ABI surface into Dart.
/// Supports:
///   * default + clamp anthropometric profile JSON
///   * generate personalized HRTF database from a profile
///   * persist / load `.ffhrtf` bundles to/from disk
///   * read live metadata (sample rate, filter length, measurement count)
///
/// All `*_json` functions return owned C strings that **must** be freed
/// with `hrtfFreeString`.  This binding handles that automatically and
/// returns plain Dart `String?` values to the caller.

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// HRTF FFI EXTENSION
// ═══════════════════════════════════════════════════════════════════════════

extension HrtfFFI on NativeFFI {
  // ── Profile ──────────────────────────────────────────────────────────────

  static final _hrtfDefaultProfileJson = NativeFFI.instance.lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('hrtf_default_profile_json');

  static final _hrtfClampProfileJson = NativeFFI.instance.lib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('hrtf_clamp_profile_json');

  // ── Generation ───────────────────────────────────────────────────────────

  static final _hrtfGenerate = NativeFFI.instance.lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Uint32),
      int Function(Pointer<Utf8>, int)>('hrtf_generate');

  static final _hrtfGenerateDefault = NativeFFI.instance.lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('hrtf_generate_default');

  // ── Persistence ──────────────────────────────────────────────────────────

  static final _hrtfSaveFfhrtf = NativeFFI.instance.lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
      int Function(Pointer<Utf8>, Pointer<Utf8>)>('hrtf_save_ffhrtf');

  static final _hrtfLoadFfhrtf = NativeFFI.instance.lib.lookupFunction<
      Int32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('hrtf_load_ffhrtf');

  // ── Metadata ─────────────────────────────────────────────────────────────

  static final _hrtfMetadataJson = NativeFFI.instance.lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('hrtf_metadata_json');

  // ── Lifecycle ────────────────────────────────────────────────────────────

  static final _hrtfFreeString = NativeFFI.instance.lib.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('hrtf_free_string');

  // ── Audition (P1.2) ──────────────────────────────────────────────────────

  static final _hrtfAuditionRenderToWav =
      NativeFFI.instance.lib.lookupFunction<
          Int32 Function(Float, Float, Uint8, Uint32, Pointer<Utf8>),
          int Function(double, double, int, int, Pointer<Utf8>)>(
              'hrtf_audition_render_to_wav');

  // ── Default presets bundle (P1.3) ────────────────────────────────────────

  static final _hrtfSaveDefaultPresets =
      NativeFFI.instance.lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Uint32),
          int Function(Pointer<Utf8>, int)>('hrtf_save_default_presets');

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get the default (CIPIC average) anthropometric profile as JSON.
  String? hrtfDefaultProfileJson() => _consumeOwnedJson(_hrtfDefaultProfileJson());

  /// Pull every field of the supplied profile into its biologically
  /// plausible range.  Returns `null` if the JSON cannot be parsed.
  String? hrtfClampProfileJson(String profileJson) {
    final p = profileJson.toNativeUtf8();
    try {
      return _consumeOwnedJson(_hrtfClampProfileJson(p));
    } finally {
      malloc.free(p);
    }
  }

  /// Generate a personalized HRTF database from the given profile JSON.
  /// Returns `0` on success, `-1` on parse / argument error.
  int hrtfGenerate(String profileJson, int sampleRate) {
    final p = profileJson.toNativeUtf8();
    try {
      return _hrtfGenerate(p, sampleRate);
    } finally {
      malloc.free(p);
    }
  }

  /// Generate using the default profile (faster, no JSON round-trip).
  int hrtfGenerateDefault(int sampleRate) => _hrtfGenerateDefault(sampleRate);

  /// Persist the current in-memory HRTF database to a `.ffhrtf` directory.
  /// Returns `0` on success, `-1` if no DB is loaded, `-2` on I/O error.
  int hrtfSaveFfhrtf(String path, String subjectId) {
    final pPath = path.toNativeUtf8();
    final pSubj = subjectId.toNativeUtf8();
    try {
      return _hrtfSaveFfhrtf(pPath, pSubj);
    } finally {
      malloc.free(pPath);
      malloc.free(pSubj);
    }
  }

  /// Load a `.ffhrtf` directory and replace the in-memory HRTF database.
  /// Returns `0` on success, `-1` on error.
  int hrtfLoadFfhrtf(String path) {
    final p = path.toNativeUtf8();
    try {
      return _hrtfLoadFfhrtf(p);
    } finally {
      malloc.free(p);
    }
  }

  /// Read live database metadata as JSON, or `null` if no DB is loaded.
  /// The JSON is `{ "sample_rate": u32, "filter_length": usize,
  /// "measurement_count": usize }`.
  String? hrtfMetadataJson() => _consumeOwnedJson(_hrtfMetadataJson());

  /// Render a personalized HRTF audition tone to a stereo WAV file.
  ///
  /// Returns:
  /// *  `0` on success — file is ready to play
  /// * `-1` no HRTF database loaded
  /// * `-2` invalid argument (bad signal type, empty path, etc.)
  /// * `-3` rendering failed
  /// * `-4` WAV write failed
  ///
  /// `signalType`:
  /// * `0` — pink noise (default — best for general HRTF auditioning)
  /// * `1` — white noise
  /// * `2` — 440 Hz sine
  /// * `3` — 1 kHz sine
  /// * `4` — 200 Hz → 8 kHz log chirp
  int hrtfAuditionRenderToWav({
    required double azimuthDeg,
    required double elevationDeg,
    required int signalType,
    required int durationMs,
    required String outPath,
  }) {
    final p = outPath.toNativeUtf8();
    try {
      return _hrtfAuditionRenderToWav(
          azimuthDeg, elevationDeg, signalType, durationMs, p);
    } finally {
      malloc.free(p);
    }
  }

  /// Generate the three canonical anthropometric presets (small / average /
  /// large) and persist them as `.ffhrtf` directories under `outDir`.
  /// Each preset becomes its own subdirectory of [outDir] using its name.
  ///
  /// Returns:
  /// *  `0` on success
  /// * `-1` invalid argument
  /// * `-2` I/O error
  int hrtfSaveDefaultPresets(String outDir, int sampleRate) {
    final p = outDir.toNativeUtf8();
    try {
      return _hrtfSaveDefaultPresets(p, sampleRate);
    } finally {
      malloc.free(p);
    }
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  /// Consume a `*mut c_char` returned by Rust, copying it into a Dart
  /// `String` and freeing the underlying allocation via `hrtf_free_string`.
  /// Returns `null` for null pointers.
  String? _consumeOwnedJson(Pointer<Utf8> ptr) {
    if (ptr == nullptr) return null;
    try {
      return ptr.toDartString();
    } finally {
      _hrtfFreeString(ptr);
    }
  }
}
