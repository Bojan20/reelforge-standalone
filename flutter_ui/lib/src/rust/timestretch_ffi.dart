/// Elastic Audio Per-Clip FFI Bindings
///
/// Basic per-clip time-stretch + pitch shift operations.
/// These complement the existing TimeStretchSlotLabAPI and ElasticProAPI
/// already in native_ffi.dart.
///
/// Provides: create/destroy per-clip processors, ratio, pitch,
/// quality, mode, STN, transients, formants, apply.

import 'dart:ffi';
import 'native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ELASTIC AUDIO — Per-clip time-stretch + pitch shift (basic)
// ElasticPro (per-track) is in native_ffi.dart ElasticProAPI extension
// TimeStretch (SlotLab) is in native_ffi.dart TimeStretchSlotLabAPI extension
// ═══════════════════════════════════════════════════════════════════════════════

extension ElasticClipFFI on NativeFFI {
  static final _elasticCreate = loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32 clipId, Double sampleRate),
      int Function(int clipId, double sampleRate)>('elastic_create');

  static final _elasticRemove = loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32 clipId),
      int Function(int clipId)>('elastic_remove');

  static final _elasticSetRatio = loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32 clipId, Double ratio),
      int Function(int clipId, double ratio)>('elastic_set_ratio');

  static final _elasticSetPitch = loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32 clipId, Double semitones),
      int Function(int clipId, double semitones)>('elastic_set_pitch');

  static final _elasticSetQuality = loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32 clipId, Uint8 quality),
      int Function(int clipId, int quality)>('elastic_set_quality');

  static final _elasticSetMode = loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32 clipId, Uint8 mode),
      int Function(int clipId, int mode)>('elastic_set_mode');

  static final _elasticSetStnEnabled = loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32 clipId, Int32 enabled),
      int Function(int clipId, int enabled)>('elastic_set_stn_enabled');

  static final _elasticSetPreserveTransients = loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32 clipId, Int32 enabled),
      int Function(int clipId, int enabled)>('elastic_set_preserve_transients');

  static final _elasticSetPreserveFormants = loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32 clipId, Int32 enabled),
      int Function(int clipId, int enabled)>('elastic_set_preserve_formants');

  static final _elasticSetTonalThreshold = loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32 clipId, Double threshold),
      int Function(int clipId, double threshold)>('elastic_set_tonal_threshold');

  static final _elasticSetTransientThreshold = loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32 clipId, Double threshold),
      int Function(int clipId, double threshold)>('elastic_set_transient_threshold');

  static final _elasticGetOutputLength = loadNativeLibrary().lookupFunction<
      Uint32 Function(Uint32 clipId, Uint32 inputLen),
      int Function(int clipId, int inputLen)>('elastic_get_output_length');

  static final _elasticGetRatio = loadNativeLibrary().lookupFunction<
      Double Function(Uint32 clipId),
      double Function(int clipId)>('elastic_get_ratio');

  static final _elasticGetPitch = loadNativeLibrary().lookupFunction<
      Double Function(Uint32 clipId),
      double Function(int clipId)>('elastic_get_pitch');

  static final _elasticReset = loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32 clipId),
      int Function(int clipId)>('elastic_reset');

  static final _elasticApplyToClip = loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32 clipId),
      int Function(int clipId)>('elastic_apply_to_clip');

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  int elasticCreate(int clipId, double sampleRate) => _elasticCreate(clipId, sampleRate);
  int elasticRemove(int clipId) => _elasticRemove(clipId);
  int elasticSetRatio(int clipId, double ratio) => _elasticSetRatio(clipId, ratio);
  int elasticSetPitch(int clipId, double semitones) => _elasticSetPitch(clipId, semitones);
  int elasticSetQuality(int clipId, int quality) => _elasticSetQuality(clipId, quality);
  int elasticSetMode(int clipId, int mode) => _elasticSetMode(clipId, mode);

  int elasticSetStnEnabled(int clipId, bool enabled) =>
      _elasticSetStnEnabled(clipId, enabled ? 1 : 0);

  int elasticSetPreserveTransients(int clipId, bool enabled) =>
      _elasticSetPreserveTransients(clipId, enabled ? 1 : 0);

  int elasticSetPreserveFormants(int clipId, bool enabled) =>
      _elasticSetPreserveFormants(clipId, enabled ? 1 : 0);

  int elasticSetTonalThreshold(int clipId, double threshold) =>
      _elasticSetTonalThreshold(clipId, threshold);

  int elasticSetTransientThreshold(int clipId, double threshold) =>
      _elasticSetTransientThreshold(clipId, threshold);

  int elasticGetOutputLength(int clipId, int inputLen) =>
      _elasticGetOutputLength(clipId, inputLen);

  double elasticGetRatio(int clipId) => _elasticGetRatio(clipId);
  double elasticGetPitch(int clipId) => _elasticGetPitch(clipId);
  int elasticReset(int clipId) => _elasticReset(clipId);
  int elasticApplyToClip(int clipId) => _elasticApplyToClip(clipId);
}
