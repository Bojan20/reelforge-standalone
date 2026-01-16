/// FluxForge Studio Native FFI Bindings
///
/// Direct FFI bindings to Rust engine C API.
/// Uses dart:ffi for low-level native function calls.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'engine_api.dart' show TruePeak8xData, PsrData, CrestFactorData, PsychoacousticData;
import '../../models/middleware_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WAVEFORM DATA STRUCTURES
// ═══════════════════════════════════════════════════════════════════════════

/// Pixel-exact waveform data (Cubase-style)
/// Contains min/max/rms per pixel for accurate waveform rendering
class WaveformPixelData {
  /// Minimum values per pixel (for peak stroke)
  final Float32List mins;
  /// Maximum values per pixel (for peak stroke)
  final Float32List maxs;
  /// RMS values per pixel (for body fill)
  final Float32List rms;

  const WaveformPixelData({
    required this.mins,
    required this.maxs,
    required this.rms,
  });

  /// Number of pixels
  int get length => mins.length;

  /// Check if empty
  bool get isEmpty => mins.isEmpty;
}

/// Stereo pixel-exact waveform data
/// Contains min/max/rms per pixel for BOTH left and right channels
class StereoWaveformPixelData {
  /// Left channel data
  final WaveformPixelData left;
  /// Right channel data
  final WaveformPixelData right;

  const StereoWaveformPixelData({
    required this.left,
    required this.right,
  });

  /// Number of pixels
  int get length => left.length;

  /// Check if empty
  bool get isEmpty => left.isEmpty;
}

/// Tile query for batch waveform requests
class WaveformTileQuery {
  final int clipId;
  final int startFrame;
  final int endFrame;
  final int numPixels;

  const WaveformTileQuery({
    required this.clipId,
    required this.startFrame,
    required this.endFrame,
    required this.numPixels,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// NATIVE LIBRARY LOADING
// ═══════════════════════════════════════════════════════════════════════════

DynamicLibrary? _cachedLib;

/// Load the native library
DynamicLibrary _loadNativeLibrary() {
  if (_cachedLib != null) return _cachedLib!;

  String libName;
  if (Platform.isLinux) {
    libName = 'librf_bridge.so';
  } else if (Platform.isMacOS) {
    libName = 'librf_bridge.dylib';
  } else if (Platform.isWindows) {
    libName = 'rf_bridge.dll';
  } else {
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  // Get script/executable directory for reliable path resolution
  final scriptDir = Platform.script.toFilePath();
  final execDir = Platform.resolvedExecutable;
  print('[NativeFFI] Script path: $scriptDir');
  print('[NativeFFI] Executable path: $execDir');
  print('[NativeFFI] CWD: ${Directory.current.path}');

  // Try multiple paths
  // Get executable directory for macOS app bundle
  final executableDir = Platform.resolvedExecutable.contains('/')
      ? Platform.resolvedExecutable.substring(0, Platform.resolvedExecutable.lastIndexOf('/'))
      : '.';
  final frameworksDir = '$executableDir/../Frameworks';

  final paths = [
    // macOS app bundle - Frameworks directory (FIRST for sandboxed apps)
    '$frameworksDir/$libName',
    // macOS app bundle - MacOS directory
    '$executableDir/$libName',
    // Relative to CWD
    libName,
    'lib/$libName',
    // Relative to project root
    '../target/release/$libName',
    '../target/debug/$libName',
    '../../target/release/$libName',
    '../../target/debug/$libName',
    // Development: Use environment variable or home directory
    if (Platform.environment.containsKey('REELFORGE_LIB_PATH'))
      '${Platform.environment['REELFORGE_LIB_PATH']}/$libName'
    else if (Platform.environment.containsKey('HOME'))
      '${Platform.environment['HOME']}/Desktop/fluxforge-studio/target/release/$libName'
    else
      'target/release/$libName',
  ];

  for (final path in paths) {
    try {
      print('[NativeFFI] Trying: $path');
      _cachedLib = DynamicLibrary.open(path);
      print('[NativeFFI] SUCCESS: Loaded from $path');
      return _cachedLib!;
    } catch (e) {
      print('[NativeFFI] Failed: $path - $e');
      continue;
    }
  }

  throw Exception('Could not load native library: $libName (tried ${paths.length} paths)');
}

// ═══════════════════════════════════════════════════════════════════════════
// FFI TYPEDEFS
// ═══════════════════════════════════════════════════════════════════════════

// Track management
typedef EngineCreateTrackNative = Uint64 Function(Pointer<Utf8> name, Uint32 color, Uint32 busId);
typedef EngineCreateTrackDart = int Function(Pointer<Utf8> name, int color, int busId);

typedef EngineDeleteTrackNative = Int32 Function(Uint64 trackId);
typedef EngineDeleteTrackDart = int Function(int trackId);

typedef EngineSetTrackNameNative = Int32 Function(Uint64 trackId, Pointer<Utf8> name);
typedef EngineSetTrackNameDart = int Function(int trackId, Pointer<Utf8> name);

typedef EngineSetTrackMuteNative = Int32 Function(Uint64 trackId, Int32 muted);
typedef EngineSetTrackMuteDart = int Function(int trackId, int muted);

typedef EngineSetTrackSoloNative = Int32 Function(Uint64 trackId, Int32 solo);
typedef EngineSetTrackSoloDart = int Function(int trackId, int solo);

typedef EngineIsSoloActiveNative = Int32 Function();
typedef EngineIsSoloActiveDart = int Function();

typedef EngineClearAllSolosNative = Int32 Function();
typedef EngineClearAllSolosDart = int Function();

typedef EngineSetTrackArmedNative = Int32 Function(Uint64 trackId, Int32 armed);
typedef EngineSetTrackArmedDart = int Function(int trackId, int armed);

typedef EngineSetTrackVolumeNative = Int32 Function(Uint64 trackId, Double volume);
typedef EngineSetTrackVolumeDart = int Function(int trackId, double volume);

typedef EngineSetTrackPanNative = Int32 Function(Uint64 trackId, Double pan);
typedef EngineSetTrackPanDart = int Function(int trackId, double pan);

typedef EngineSetTrackPanRightNative = Int32 Function(Uint64 trackId, Double pan);
typedef EngineSetTrackPanRightDart = int Function(int trackId, double pan);

typedef EngineGetTrackChannelsNative = Uint32 Function(Uint64 trackId);
typedef EngineGetTrackChannelsDart = int Function(int trackId);

typedef EngineSetTrackChannelsNative = Int32 Function(Uint64 trackId, Uint32 channels);
typedef EngineSetTrackChannelsDart = int Function(int trackId, int channels);

typedef EngineSetTrackBusNative = Int32 Function(Uint64 trackId, Uint32 busId);
typedef EngineSetTrackBusDart = int Function(int trackId, int busId);

typedef EngineGetTrackCountNative = IntPtr Function();
typedef EngineGetTrackCountDart = int Function();

typedef EngineGetTrackPeakNative = Double Function(Uint64 trackId);
typedef EngineGetTrackPeakDart = double Function(int trackId);

typedef EngineGetTrackPeakStereoNative = Bool Function(Uint64 trackId, Pointer<Double> outPeakL, Pointer<Double> outPeakR);
typedef EngineGetTrackPeakStereoDart = bool Function(int trackId, Pointer<Double> outPeakL, Pointer<Double> outPeakR);

typedef EngineGetTrackRmsStereoNative = Bool Function(Uint64 trackId, Pointer<Double> outRmsL, Pointer<Double> outRmsR);
typedef EngineGetTrackRmsStereoDart = bool Function(int trackId, Pointer<Double> outRmsL, Pointer<Double> outRmsR);

typedef EngineGetTrackCorrelationNative = Double Function(Uint64 trackId);
typedef EngineGetTrackCorrelationDart = double Function(int trackId);

typedef EngineGetTrackMeterNative = Bool Function(Uint64 trackId, Pointer<Double> outPeakL, Pointer<Double> outPeakR, Pointer<Double> outRmsL, Pointer<Double> outRmsR, Pointer<Double> outCorrelation);
typedef EngineGetTrackMeterDart = bool Function(int trackId, Pointer<Double> outPeakL, Pointer<Double> outPeakR, Pointer<Double> outRmsL, Pointer<Double> outRmsR, Pointer<Double> outCorrelation);

typedef EngineGetAllTrackPeaksNative = IntPtr Function(Pointer<Uint64> outIds, Pointer<Double> outPeaks, IntPtr maxCount);
typedef EngineGetAllTrackPeaksDart = int Function(Pointer<Uint64> outIds, Pointer<Double> outPeaks, int maxCount);

typedef EngineGetAllTrackMetersNative = IntPtr Function(Pointer<Uint64> outIds, Pointer<Double> outPeakL, Pointer<Double> outPeakR, Pointer<Double> outRmsL, Pointer<Double> outRmsR, Pointer<Double> outCorr, IntPtr maxCount);
typedef EngineGetAllTrackMetersDart = int Function(Pointer<Uint64> outIds, Pointer<Double> outPeakL, Pointer<Double> outPeakR, Pointer<Double> outRmsL, Pointer<Double> outRmsR, Pointer<Double> outCorr, int maxCount);

// Audio import
typedef EngineImportAudioNative = Uint64 Function(Pointer<Utf8> path, Uint64 trackId, Double startTime);
typedef EngineImportAudioDart = int Function(Pointer<Utf8> path, int trackId, double startTime);

// Clip management
typedef EngineAddClipNative = Uint64 Function(Uint64 trackId, Pointer<Utf8> name, Double startTime, Double duration, Double sourceOffset, Double sourceDuration);
typedef EngineAddClipDart = int Function(int trackId, Pointer<Utf8> name, double startTime, double duration, double sourceOffset, double sourceDuration);

typedef EngineMoveClipNative = Int32 Function(Uint64 clipId, Uint64 targetTrackId, Double startTime);
typedef EngineMoveClipDart = int Function(int clipId, int targetTrackId, double startTime);

typedef EngineResizeClipNative = Int32 Function(Uint64 clipId, Double startTime, Double duration, Double sourceOffset);
typedef EngineResizeClipDart = int Function(int clipId, double startTime, double duration, double sourceOffset);

typedef EngineSplitClipNative = Uint64 Function(Uint64 clipId, Double atTime);
typedef EngineSplitClipDart = int Function(int clipId, double atTime);

typedef EngineDuplicateClipNative = Uint64 Function(Uint64 clipId);
typedef EngineDuplicateClipDart = int Function(int clipId);

typedef EngineDeleteClipNative = Int32 Function(Uint64 clipId);
typedef EngineDeleteClipDart = int Function(int clipId);

typedef EngineSetClipGainNative = Int32 Function(Uint64 clipId, Double gain);
typedef EngineSetClipGainDart = int Function(int clipId, double gain);

typedef EngineSetClipMutedNative = Int32 Function(Uint64 clipId, Int32 muted);
typedef EngineSetClipMutedDart = int Function(int clipId, int muted);

typedef EngineGetClipDurationNative = Double Function(Uint64 clipId);
typedef EngineGetClipDurationDart = double Function(int clipId);

typedef EngineGetClipSourceDurationNative = Double Function(Uint64 clipId);
typedef EngineGetClipSourceDurationDart = double Function(int clipId);

typedef EngineGetAudioFileDurationNative = Double Function(Pointer<Utf8> path);
typedef EngineGetAudioFileDurationDart = double Function(Pointer<Utf8> path);

// Waveform
typedef EngineGetWaveformPeaksNative = IntPtr Function(Uint64 clipId, Uint32 lodLevel, Pointer<Float> outPeaks, IntPtr maxPeaks);
typedef EngineGetWaveformPeaksDart = int Function(int clipId, int lodLevel, Pointer<Float> outPeaks, int maxPeaks);

typedef EngineGetWaveformLodLevelsNative = IntPtr Function();
typedef EngineGetWaveformLodLevelsDart = int Function();

// Pixel-exact waveform query (Cubase-style)
typedef EngineQueryWaveformPixelsNative = Uint32 Function(Uint64 clipId, Uint64 startFrame, Uint64 endFrame, Uint32 numPixels, Pointer<Float> outData);
typedef EngineQueryWaveformPixelsDart = int Function(int clipId, int startFrame, int endFrame, int numPixels, Pointer<Float> outData);

// Stereo pixel-exact waveform query
typedef EngineQueryWaveformPixelsStereoNative = Uint32 Function(Uint64 clipId, Uint64 startFrame, Uint64 endFrame, Uint32 numPixels, Pointer<Float> outData);
typedef EngineQueryWaveformPixelsStereoDart = int Function(int clipId, int startFrame, int endFrame, int numPixels, Pointer<Float> outData);

typedef EngineGetWaveformSampleRateNative = Uint32 Function(Uint64 clipId);
typedef EngineGetWaveformSampleRateDart = int Function(int clipId);

// Batch waveform tile query (Cubase-style zero-hitch zoom)
typedef EngineQueryWaveformTilesBatchNative = Uint32 Function(Pointer<Double> queries, Uint32 numTiles, Pointer<Float> outData, Uint32 outCapacity);
typedef EngineQueryWaveformTilesBatchDart = int Function(Pointer<Double> queries, int numTiles, Pointer<Float> outData, int outCapacity);

// Raw samples query (sample-mode ultra zoom)
typedef EngineQueryRawSamplesNative = Uint32 Function(Uint64 clipId, Uint64 startFrame, Uint32 numFrames, Pointer<Float> outSamples, Uint32 outCapacity);
typedef EngineQueryRawSamplesDart = int Function(int clipId, int startFrame, int numFrames, Pointer<Float> outSamples, int outCapacity);

typedef EngineGetWaveformTotalSamplesNative = Uint64 Function(Uint64 clipId);
typedef EngineGetWaveformTotalSamplesDart = int Function(int clipId);

// Loop region
typedef EngineSetLoopRegionNative = Void Function(Double start, Double end);
typedef EngineSetLoopRegionDart = void Function(double start, double end);

typedef EngineSetLoopEnabledNative = Void Function(Int32 enabled);
typedef EngineSetLoopEnabledDart = void Function(int enabled);

// Markers
typedef EngineAddMarkerNative = Uint64 Function(Pointer<Utf8> name, Double time, Uint32 color);
typedef EngineAddMarkerDart = int Function(Pointer<Utf8> name, double time, int color);

typedef EngineDeleteMarkerNative = Int32 Function(Uint64 markerId);
typedef EngineDeleteMarkerDart = int Function(int markerId);

// Crossfade
typedef EngineCreateCrossfadeNative = Uint64 Function(Uint64 clipAId, Uint64 clipBId, Double duration, Uint32 curve);
typedef EngineCreateCrossfadeDart = int Function(int clipAId, int clipBId, double duration, int curve);

typedef EngineDeleteCrossfadeNative = Int32 Function(Uint64 crossfadeId);
typedef EngineDeleteCrossfadeDart = int Function(int crossfadeId);

typedef EngineUpdateCrossfadeNative = Int32 Function(Uint64 crossfadeId, Double duration, Uint32 curve);
typedef EngineUpdateCrossfadeDart = int Function(int crossfadeId, double duration, int curve);

// Memory
typedef EngineFreeStringNative = Void Function(Pointer<Utf8> ptr);
typedef EngineFreeStringDart = void Function(Pointer<Utf8> ptr);

typedef EngineClearAllNative = Void Function();
typedef EngineClearAllDart = void Function();

// Snap
typedef EngineSnapToGridNative = Double Function(Double time, Double gridSize);
typedef EngineSnapToGridDart = double Function(double time, double gridSize);

typedef EngineSnapToEventNative = Double Function(Double time, Double threshold);
typedef EngineSnapToEventDart = double Function(double time, double threshold);

// Transport / Playback
typedef EnginePlayNative = Void Function();
typedef EnginePlayDart = void Function();

typedef EnginePauseNative = Void Function();
typedef EnginePauseDart = void Function();

typedef EngineStopNative = Void Function();
typedef EngineStopDart = void Function();

typedef EngineSeekNative = Void Function(Double seconds);
typedef EngineSeekDart = void Function(double seconds);

// Scrubbing
typedef EngineStartScrubNative = Void Function(Double seconds);
typedef EngineStartScrubDart = void Function(double seconds);

typedef EngineUpdateScrubNative = Void Function(Double seconds, Double velocity);
typedef EngineUpdateScrubDart = void Function(double seconds, double velocity);

typedef EngineStopScrubNative = Void Function();
typedef EngineStopScrubDart = void Function();

typedef EngineIsScrubbingNative = Int32 Function();
typedef EngineIsScrubbingDart = int Function();

typedef EngineSetScrubWindowMsNative = Void Function(Uint32 ms);
typedef EngineSetScrubWindowMsDart = void Function(int ms);

typedef EngineGetPositionNative = Double Function();
typedef EngineGetPositionDart = double Function();

typedef EngineGetPlaybackStateNative = Uint8 Function();
typedef EngineGetPlaybackStateDart = int Function();

typedef EngineIsPlayingNative = Int32 Function();
typedef EngineIsPlayingDart = int Function();

typedef EngineSetMasterVolumeNative = Void Function(Double volume);
typedef EngineSetMasterVolumeDart = void Function(double volume);

typedef EngineGetMasterVolumeNative = Double Function();
typedef EngineGetMasterVolumeDart = double Function();

// Varispeed
typedef EngineSetVarispeedEnabledNative = Void Function(Int32 enabled);
typedef EngineSetVarispeedEnabledDart = void Function(int enabled);

typedef EngineIsVarispeedEnabledNative = Int32 Function();
typedef EngineIsVarispeedEnabledDart = int Function();

typedef EngineSetVarispeedRateNative = Void Function(Double rate);
typedef EngineSetVarispeedRateDart = void Function(double rate);

typedef EngineGetVarispeedRateNative = Double Function();
typedef EngineGetVarispeedRateDart = double Function();

typedef EngineSetVarispeedSemitonesNative = Void Function(Double semitones);
typedef EngineSetVarispeedSemitonesDart = void Function(double semitones);

typedef EngineGetVarispeedSemitonesNative = Double Function();
typedef EngineGetVarispeedSemitonesDart = double Function();

typedef EngineGetEffectivePlaybackRateNative = Double Function();
typedef EngineGetEffectivePlaybackRateDart = double Function();

typedef EngineGetPlaybackPositionSecondsNative = Double Function();
typedef EngineGetPlaybackPositionSecondsDart = double Function();

typedef EngineGetPlaybackPositionSamplesNative = Uint64 Function();
typedef EngineGetPlaybackPositionSamplesDart = int Function();

typedef EnginePreloadAllNative = Void Function();
typedef EnginePreloadAllDart = void Function();

typedef EnginePreloadRangeNative = Void Function(Double startTime, Double endTime);
typedef EnginePreloadRangeDart = void Function(double startTime, double endTime);

typedef EngineSyncLoopFromRegionNative = Void Function();
typedef EngineSyncLoopFromRegionDart = void Function();

typedef EngineGetSampleRateNative = Uint32 Function();
typedef EngineGetSampleRateDart = int Function();

// Audio stream control (start/stop the audio output device)
typedef EngineStartPlaybackNative = Int32 Function();
typedef EngineStartPlaybackDart = int Function();

typedef EngineStopPlaybackNative = Void Function();
typedef EngineStopPlaybackDart = void Function();

// Undo/Redo
typedef EngineUndoNative = Int32 Function();
typedef EngineUndoDart = int Function();

typedef EngineRedoNative = Int32 Function();
typedef EngineRedoDart = int Function();

typedef EngineCanUndoNative = Int32 Function();
typedef EngineCanUndoDart = int Function();

typedef EngineCanRedoNative = Int32 Function();
typedef EngineCanRedoDart = int Function();

// Project save/load
typedef EngineSaveProjectNative = Int32 Function(Pointer<Utf8> path);
typedef EngineSaveProjectDart = int Function(Pointer<Utf8> path);

typedef EngineLoadProjectNative = Int32 Function(Pointer<Utf8> path);
typedef EngineLoadProjectDart = int Function(Pointer<Utf8> path);

// Project dirty state
typedef EngineIsProjectModifiedNative = Int32 Function();
typedef EngineIsProjectModifiedDart = int Function();

typedef EngineMarkProjectDirtyNative = Void Function();
typedef EngineMarkProjectDirtyDart = void Function();

typedef EngineMarkProjectCleanNative = Void Function();
typedef EngineMarkProjectCleanDart = void Function();

typedef EngineSetProjectFilePathNative = Void Function(Pointer<Utf8> path);
typedef EngineSetProjectFilePathDart = void Function(Pointer<Utf8> path);

typedef EngineGetProjectFilePathNative = Pointer<Utf8> Function();
typedef EngineGetProjectFilePathDart = Pointer<Utf8> Function();

// Memory stats
typedef EngineGetMemoryUsageNative = Float Function();
typedef EngineGetMemoryUsageDart = double Function();

// Metering (real-time peak/RMS from audio thread)
typedef EngineGetPeakMetersNative = Void Function(Pointer<Double> outLeft, Pointer<Double> outRight);
typedef EngineGetPeakMetersDart = void Function(Pointer<Double> outLeft, Pointer<Double> outRight);

typedef EngineGetRmsMetersNative = Void Function(Pointer<Double> outLeft, Pointer<Double> outRight);
typedef EngineGetRmsMetersDart = void Function(Pointer<Double> outLeft, Pointer<Double> outRight);

typedef EngineGetLufsMetersNative = Void Function(Pointer<Double> outMomentary, Pointer<Double> outShort, Pointer<Double> outIntegrated);
typedef EngineGetLufsMetersDart = void Function(Pointer<Double> outMomentary, Pointer<Double> outShort, Pointer<Double> outIntegrated);

typedef EngineGetTruePeakMetersNative = Void Function(Pointer<Double> outLeft, Pointer<Double> outRight);
typedef EngineGetTruePeakMetersDart = void Function(Pointer<Double> outLeft, Pointer<Double> outRight);

// Stereo analysis metering
typedef EngineGetCorrelationNative = Float Function();
typedef EngineGetCorrelationDart = double Function();

typedef EngineGetStereoBalanceNative = Float Function();
typedef EngineGetStereoBalanceDart = double Function();

typedef EngineGetDynamicRangeNative = Float Function();
typedef EngineGetDynamicRangeDart = double Function();

typedef EngineGetMasterSpectrumNative = IntPtr Function(Pointer<Float> outData, IntPtr maxCount);
typedef EngineGetMasterSpectrumDart = int Function(Pointer<Float> outData, int maxCount);

// EQ functions
typedef EngineEqSetBandEnabledNative = Int32 Function(Uint32 trackId, Uint8 bandIndex, Int32 enabled);
typedef EngineEqSetBandEnabledDart = int Function(int trackId, int bandIndex, int enabled);

typedef EngineEqSetBandFrequencyNative = Int32 Function(Uint32 trackId, Uint8 bandIndex, Double frequency);
typedef EngineEqSetBandFrequencyDart = int Function(int trackId, int bandIndex, double frequency);

typedef EngineEqSetBandGainNative = Int32 Function(Uint32 trackId, Uint8 bandIndex, Double gain);
typedef EngineEqSetBandGainDart = int Function(int trackId, int bandIndex, double gain);

typedef EngineEqSetBandQNative = Int32 Function(Uint32 trackId, Uint8 bandIndex, Double q);
typedef EngineEqSetBandQDart = int Function(int trackId, int bandIndex, double q);

typedef EngineEqSetBandShapeNative = Int32 Function(Uint32 trackId, Uint8 bandIndex, Int32 shape);
typedef EngineEqSetBandShapeDart = int Function(int trackId, int bandIndex, int shape);

typedef EngineEqSetBypassNative = Int32 Function(Uint32 trackId, Int32 bypass);
typedef EngineEqSetBypassDart = int Function(int trackId, int bypass);

// Mixer bus functions
typedef EngineMixerSetBusVolumeNative = Int32 Function(Uint32 busId, Double volumeDb);
typedef EngineMixerSetBusVolumeDart = int Function(int busId, double volumeDb);

typedef EngineMixerSetBusMuteNative = Int32 Function(Uint32 busId, Int32 muted);
typedef EngineMixerSetBusMuteDart = int Function(int busId, int muted);

typedef EngineMixerSetBusSoloNative = Int32 Function(Uint32 busId, Int32 solo);
typedef EngineMixerSetBusSoloDart = int Function(int busId, int solo);

typedef EngineMixerSetBusPanNative = Int32 Function(Uint32 busId, Double pan);
typedef EngineMixerSetBusPanDart = int Function(int busId, double pan);

typedef EngineMixerSetMasterVolumeNative = Int32 Function(Double volumeDb);
typedef EngineMixerSetMasterVolumeDart = int Function(double volumeDb);

// Audio processing functions
typedef EngineClipNormalizeNative = Int32 Function(Uint64 clipId, Double targetDb);
typedef EngineClipNormalizeDart = int Function(int clipId, double targetDb);

typedef EngineClipReverseNative = Int32 Function(Uint64 clipId);
typedef EngineClipReverseDart = int Function(int clipId);

typedef EngineClipFadeInNative = Int32 Function(Uint64 clipId, Double durationSec, Uint8 curveType);
typedef EngineClipFadeInDart = int Function(int clipId, double durationSec, int curveType);

typedef EngineClipFadeOutNative = Int32 Function(Uint64 clipId, Double durationSec, Uint8 curveType);
typedef EngineClipFadeOutDart = int Function(int clipId, double durationSec, int curveType);

typedef EngineClipApplyGainNative = Int32 Function(Uint64 clipId, Double gainDb);
typedef EngineClipApplyGainDart = int Function(int clipId, double gainDb);

// Track management
typedef EngineTrackRenameNative = Int32 Function(Uint64 trackId, Pointer<Utf8> name);
typedef EngineTrackRenameDart = int Function(int trackId, Pointer<Utf8> name);

typedef EngineTrackDuplicateNative = Uint64 Function(Uint64 trackId);
typedef EngineTrackDuplicateDart = int Function(int trackId);

typedef EngineTrackSetColorNative = Int32 Function(Uint64 trackId, Uint32 color);
typedef EngineTrackSetColorDart = int Function(int trackId, int color);

// VCA functions
typedef EngineVcaCreateNative = Uint64 Function(Pointer<Utf8> name);
typedef EngineVcaCreateDart = int Function(Pointer<Utf8> name);

typedef EngineVcaDeleteNative = Int32 Function(Uint64 vcaId);
typedef EngineVcaDeleteDart = int Function(int vcaId);

typedef EngineVcaSetLevelNative = Int32 Function(Uint64 vcaId, Double level);
typedef EngineVcaSetLevelDart = int Function(int vcaId, double level);

typedef EngineVcaGetLevelNative = Double Function(Uint64 vcaId);
typedef EngineVcaGetLevelDart = double Function(int vcaId);

typedef EngineVcaSetMuteNative = Int32 Function(Uint64 vcaId, Int32 muted);
typedef EngineVcaSetMuteDart = int Function(int vcaId, int muted);

typedef EngineVcaAssignTrackNative = Int32 Function(Uint64 vcaId, Uint64 trackId);
typedef EngineVcaAssignTrackDart = int Function(int vcaId, int trackId);

typedef EngineVcaRemoveTrackNative = Int32 Function(Uint64 vcaId, Uint64 trackId);
typedef EngineVcaRemoveTrackDart = int Function(int vcaId, int trackId);

typedef EngineVcaGetTrackEffectiveVolumeNative = Double Function(Uint64 trackId, Double baseVolume);
typedef EngineVcaGetTrackEffectiveVolumeDart = double Function(int trackId, double baseVolume);

// Group functions
typedef EngineGroupCreateNative = Uint64 Function(Pointer<Utf8> name);
typedef EngineGroupCreateDart = int Function(Pointer<Utf8> name);

typedef EngineGroupDeleteNative = Int32 Function(Uint64 groupId);
typedef EngineGroupDeleteDart = int Function(int groupId);

typedef EngineGroupAddTrackNative = Int32 Function(Uint64 groupId, Uint64 trackId);
typedef EngineGroupAddTrackDart = int Function(int groupId, int trackId);

typedef EngineGroupRemoveTrackNative = Int32 Function(Uint64 groupId, Uint64 trackId);
typedef EngineGroupRemoveTrackDart = int Function(int groupId, int trackId);

typedef EngineGroupSetLinkModeNative = Int32 Function(Uint64 groupId, Uint32 linkMode);
typedef EngineGroupSetLinkModeDart = int Function(int groupId, int linkMode);

// Clip FX functions
typedef ClipFxAddNative = Uint64 Function(Uint64 clipId, Uint8 fxType);
typedef ClipFxAddDart = int Function(int clipId, int fxType);

typedef ClipFxRemoveNative = Int32 Function(Uint64 clipId, Uint64 slotId);
typedef ClipFxRemoveDart = int Function(int clipId, int slotId);

typedef ClipFxMoveNative = Int32 Function(Uint64 clipId, Uint64 slotId, Uint64 newIndex);
typedef ClipFxMoveDart = int Function(int clipId, int slotId, int newIndex);

typedef ClipFxSetBypassNative = Int32 Function(Uint64 clipId, Uint64 slotId, Int32 bypass);
typedef ClipFxSetBypassDart = int Function(int clipId, int slotId, int bypass);

typedef ClipFxSetChainBypassNative = Int32 Function(Uint64 clipId, Int32 bypass);
typedef ClipFxSetChainBypassDart = int Function(int clipId, int bypass);

typedef ClipFxSetWetDryNative = Int32 Function(Uint64 clipId, Uint64 slotId, Double wetDry);
typedef ClipFxSetWetDryDart = int Function(int clipId, int slotId, double wetDry);

typedef ClipFxSetInputGainNative = Int32 Function(Uint64 clipId, Double gainDb);
typedef ClipFxSetInputGainDart = int Function(int clipId, double gainDb);

typedef ClipFxSetOutputGainNative = Int32 Function(Uint64 clipId, Double gainDb);
typedef ClipFxSetOutputGainDart = int Function(int clipId, double gainDb);

typedef ClipFxSetGainParamsNative = Int32 Function(Uint64 clipId, Uint64 slotId, Double db, Double pan);
typedef ClipFxSetGainParamsDart = int Function(int clipId, int slotId, double db, double pan);

typedef ClipFxSetCompressorParamsNative = Int32 Function(Uint64 clipId, Uint64 slotId, Double ratio, Double thresholdDb, Double attackMs, Double releaseMs);
typedef ClipFxSetCompressorParamsDart = int Function(int clipId, int slotId, double ratio, double thresholdDb, double attackMs, double releaseMs);

typedef ClipFxSetLimiterParamsNative = Int32 Function(Uint64 clipId, Uint64 slotId, Double ceilingDb);
typedef ClipFxSetLimiterParamsDart = int Function(int clipId, int slotId, double ceilingDb);

typedef ClipFxSetGateParamsNative = Int32 Function(Uint64 clipId, Uint64 slotId, Double thresholdDb, Double attackMs, Double releaseMs);
typedef ClipFxSetGateParamsDart = int Function(int clipId, int slotId, double thresholdDb, double attackMs, double releaseMs);

typedef ClipFxSetSaturationParamsNative = Int32 Function(Uint64 clipId, Uint64 slotId, Double drive, Double mix);
typedef ClipFxSetSaturationParamsDart = int Function(int clipId, int slotId, double drive, double mix);

typedef ClipFxCopyNative = Int32 Function(Uint64 sourceClipId, Uint64 targetClipId);
typedef ClipFxCopyDart = int Function(int sourceClipId, int targetClipId);

typedef ClipFxClearNative = Int32 Function(Uint64 clipId);
typedef ClipFxClearDart = int Function(int clipId);

// Click track functions
typedef ClickSetEnabledNative = Void Function(Int32 enabled);
typedef ClickSetEnabledDart = void Function(int enabled);

typedef ClickIsEnabledNative = Int32 Function();
typedef ClickIsEnabledDart = int Function();

typedef ClickSetVolumeNative = Void Function(Double volume);
typedef ClickSetVolumeDart = void Function(double volume);

typedef ClickSetPatternNative = Void Function(Uint8 pattern);
typedef ClickSetPatternDart = void Function(int pattern);

typedef ClickSetCountInNative = Void Function(Uint8 mode);
typedef ClickSetCountInDart = void Function(int mode);

typedef ClickSetPanNative = Void Function(Double pan);
typedef ClickSetPanDart = void Function(double pan);

// Send functions
typedef SendSetLevelNative = Void Function(Uint64 trackId, Uint32 sendIndex, Double level);
typedef SendSetLevelDart = void Function(int trackId, int sendIndex, double level);

typedef SendSetLevelDbNative = Void Function(Uint64 trackId, Uint32 sendIndex, Double db);
typedef SendSetLevelDbDart = void Function(int trackId, int sendIndex, double db);

typedef SendSetDestinationNative = Void Function(Uint64 trackId, Uint32 sendIndex, Uint32 destination);
typedef SendSetDestinationDart = void Function(int trackId, int sendIndex, int destination);

typedef SendSetPanNative = Void Function(Uint64 trackId, Uint32 sendIndex, Double pan);
typedef SendSetPanDart = void Function(int trackId, int sendIndex, double pan);

typedef SendSetEnabledNative = Void Function(Uint64 trackId, Uint32 sendIndex, Int32 enabled);
typedef SendSetEnabledDart = void Function(int trackId, int sendIndex, int enabled);

typedef SendSetMutedNative = Void Function(Uint64 trackId, Uint32 sendIndex, Int32 muted);
typedef SendSetMutedDart = void Function(int trackId, int sendIndex, int muted);

typedef SendSetTapPointNative = Void Function(Uint64 trackId, Uint32 sendIndex, Uint8 tapPoint);
typedef SendSetTapPointDart = void Function(int trackId, int sendIndex, int tapPoint);

typedef SendCreateBankNative = Void Function(Uint64 trackId);
typedef SendCreateBankDart = void Function(int trackId);

typedef SendRemoveBankNative = Void Function(Uint64 trackId);
typedef SendRemoveBankDart = void Function(int trackId);

// Return bus functions
typedef ReturnSetLevelNative = Void Function(Uint32 returnIndex, Double level);
typedef ReturnSetLevelDart = void Function(int returnIndex, double level);

typedef ReturnSetLevelDbNative = Void Function(Uint32 returnIndex, Double db);
typedef ReturnSetLevelDbDart = void Function(int returnIndex, double db);

typedef ReturnSetPanNative = Void Function(Uint32 returnIndex, Double pan);
typedef ReturnSetPanDart = void Function(int returnIndex, double pan);

typedef ReturnSetMutedNative = Void Function(Uint32 returnIndex, Int32 muted);
typedef ReturnSetMutedDart = void Function(int returnIndex, int muted);

typedef ReturnSetSoloNative = Void Function(Uint32 returnIndex, Int32 solo);
typedef ReturnSetSoloDart = void Function(int returnIndex, int solo);

// Sidechain functions
typedef SidechainAddRouteNative = Uint32 Function(Uint32 sourceId, Uint32 destProcessorId, Int32 preFader);
typedef SidechainAddRouteDart = int Function(int sourceId, int destProcessorId, int preFader);

typedef SidechainRemoveRouteNative = Int32 Function(Uint32 routeId);
typedef SidechainRemoveRouteDart = int Function(int routeId);

typedef SidechainCreateInputNative = Void Function(Uint32 processorId);
typedef SidechainCreateInputDart = void Function(int processorId);

typedef SidechainRemoveInputNative = Void Function(Uint32 processorId);
typedef SidechainRemoveInputDart = void Function(int processorId);

typedef SidechainSetSourceNative = Void Function(Uint32 processorId, Uint8 sourceType, Uint32 externalId);
typedef SidechainSetSourceDart = void Function(int processorId, int sourceType, int externalId);

typedef SidechainSetFilterModeNative = Void Function(Uint32 processorId, Uint8 mode);
typedef SidechainSetFilterModeDart = void Function(int processorId, int mode);

typedef SidechainSetFilterFreqNative = Void Function(Uint32 processorId, Double freq);
typedef SidechainSetFilterFreqDart = void Function(int processorId, double freq);

typedef SidechainSetFilterQNative = Void Function(Uint32 processorId, Double q);
typedef SidechainSetFilterQDart = void Function(int processorId, double q);

typedef SidechainSetMixNative = Void Function(Uint32 processorId, Double mix);
typedef SidechainSetMixDart = void Function(int processorId, double mix);

typedef SidechainSetGainDbNative = Void Function(Uint32 processorId, Double db);
typedef SidechainSetGainDbDart = void Function(int processorId, double db);

typedef SidechainSetMonitorNative = Void Function(Uint32 processorId, Int32 monitor);
typedef SidechainSetMonitorDart = void Function(int processorId, int monitor);

typedef SidechainIsMonitoringNative = Int32 Function(Uint32 processorId);
typedef SidechainIsMonitoringDart = int Function(int processorId);

// Automation
typedef AutomationSetModeNative = Void Function(Uint8 mode);
typedef AutomationSetModeDart = void Function(int mode);

typedef AutomationGetModeNative = Uint8 Function();
typedef AutomationGetModeDart = int Function();

typedef AutomationSetRecordingNative = Void Function(Int32 enabled);
typedef AutomationSetRecordingDart = void Function(int enabled);

typedef AutomationIsRecordingNative = Int32 Function();
typedef AutomationIsRecordingDart = int Function();

typedef AutomationTouchParamNative = Void Function(Uint64 trackId, Pointer<Utf8> paramName, Double value);
typedef AutomationTouchParamDart = void Function(int trackId, Pointer<Utf8> paramName, double value);

typedef AutomationReleaseParamNative = Void Function(Uint64 trackId, Pointer<Utf8> paramName);
typedef AutomationReleaseParamDart = void Function(int trackId, Pointer<Utf8> paramName);

typedef AutomationRecordChangeNative = Void Function(Uint64 trackId, Pointer<Utf8> paramName, Double value);
typedef AutomationRecordChangeDart = void Function(int trackId, Pointer<Utf8> paramName, double value);

typedef AutomationAddPointNative = Void Function(Uint64 trackId, Pointer<Utf8> paramName, Uint64 timeSamples, Double value, Uint8 curveType);
typedef AutomationAddPointDart = void Function(int trackId, Pointer<Utf8> paramName, int timeSamples, double value, int curveType);

typedef AutomationGetValueNative = Double Function(Uint64 trackId, Pointer<Utf8> paramName, Uint64 timeSamples);
typedef AutomationGetValueDart = double Function(int trackId, Pointer<Utf8> paramName, int timeSamples);

typedef AutomationClearLaneNative = Void Function(Uint64 trackId, Pointer<Utf8> paramName);
typedef AutomationClearLaneDart = void Function(int trackId, Pointer<Utf8> paramName);

// Plugin Automation
typedef AutomationAddPluginPointNative = Int32 Function(Uint64 trackId, Uint32 slot, Uint32 paramIndex, Uint64 timeSamples, Double value, Uint8 curveType);
typedef AutomationAddPluginPointDart = int Function(int trackId, int slot, int paramIndex, int timeSamples, double value, int curveType);

typedef AutomationGetPluginValueNative = Double Function(Uint64 trackId, Uint32 slot, Uint32 paramIndex, Uint64 timeSamples);
typedef AutomationGetPluginValueDart = double Function(int trackId, int slot, int paramIndex, int timeSamples);

typedef AutomationClearPluginLaneNative = Void Function(Uint64 trackId, Uint32 slot, Uint32 paramIndex);
typedef AutomationClearPluginLaneDart = void Function(int trackId, int slot, int paramIndex);

typedef AutomationTouchPluginNative = Void Function(Uint64 trackId, Uint32 slot, Uint32 paramIndex, Double value);
typedef AutomationTouchPluginDart = void Function(int trackId, int slot, int paramIndex, double value);

typedef AutomationReleasePluginNative = Void Function(Uint64 trackId, Uint32 slot, Uint32 paramIndex);
typedef AutomationReleasePluginDart = void Function(int trackId, int slot, int paramIndex);

// Insert Effects
typedef InsertCreateChainNative = Void Function(Uint64 trackId);
typedef InsertCreateChainDart = void Function(int trackId);

typedef InsertRemoveChainNative = Void Function(Uint64 trackId);
typedef InsertRemoveChainDart = void Function(int trackId);

typedef InsertSetBypassNative = Void Function(Uint64 trackId, Uint32 slot, Int32 bypass);
typedef InsertSetBypassDart = void Function(int trackId, int slot, int bypass);

typedef InsertSetMixNative = Void Function(Uint64 trackId, Uint32 slot, Double mix);
typedef InsertSetMixDart = void Function(int trackId, int slot, double mix);

typedef InsertGetMixNative = Double Function(Uint64 trackId, Uint32 slot);
typedef InsertGetMixDart = double Function(int trackId, int slot);

typedef InsertBypassAllNative = Void Function(Uint64 trackId, Int32 bypass);
typedef InsertBypassAllDart = void Function(int trackId, int bypass);

typedef InsertGetTotalLatencyNative = Uint32 Function(Uint64 trackId);
typedef InsertGetTotalLatencyDart = int Function(int trackId);

typedef InsertLoadProcessorNative = Int32 Function(Uint32 trackId, Uint32 slotIndex, Pointer<Utf8> processorName);
typedef InsertLoadProcessorDart = int Function(int trackId, int slotIndex, Pointer<Utf8> processorName);

typedef InsertUnloadSlotNative = Int32 Function(Uint32 trackId, Uint32 slotIndex);
typedef InsertUnloadSlotDart = int Function(int trackId, int slotIndex);

typedef InsertSetParamNative = Int32 Function(Uint32 trackId, Uint32 slotIndex, Uint32 paramIndex, Double value);
typedef InsertSetParamDart = int Function(int trackId, int slotIndex, int paramIndex, double value);

typedef InsertGetParamNative = Double Function(Uint32 trackId, Uint32 slotIndex, Uint32 paramIndex);
typedef InsertGetParamDart = double Function(int trackId, int slotIndex, int paramIndex);

typedef InsertIsLoadedNative = Int32 Function(Uint32 trackId, Uint32 slotIndex);
typedef InsertIsLoadedDart = int Function(int trackId, int slotIndex);

typedef InsertOpenEditorNative = Int32 Function(Uint32 trackId, Uint32 slotIndex);
typedef InsertOpenEditorDart = int Function(int trackId, int slotIndex);

// Plugin State/Preset
typedef PluginGetStateNative = Int32 Function(Pointer<Utf8> instanceId, Pointer<Uint8> outData, Uint32 maxLen);
typedef PluginGetStateDart = int Function(Pointer<Utf8> instanceId, Pointer<Uint8> outData, int maxLen);

typedef PluginSetStateNative = Int32 Function(Pointer<Utf8> instanceId, Pointer<Uint8> data, Uint32 len);
typedef PluginSetStateDart = int Function(Pointer<Utf8> instanceId, Pointer<Uint8> data, int len);

typedef PluginSavePresetNative = Int32 Function(Pointer<Utf8> instanceId, Pointer<Utf8> path, Pointer<Utf8> presetName);
typedef PluginSavePresetDart = int Function(Pointer<Utf8> instanceId, Pointer<Utf8> path, Pointer<Utf8> presetName);

typedef PluginLoadPresetNative = Int32 Function(Pointer<Utf8> instanceId, Pointer<Utf8> path);
typedef PluginLoadPresetDart = int Function(Pointer<Utf8> instanceId, Pointer<Utf8> path);

// Transient Detection
typedef TransientDetectNative = Uint32 Function(Pointer<Double> samples, Uint32 length, Double sampleRate, Double sensitivity, Uint8 algorithm, Pointer<Uint64> outPositions, Uint32 outMaxCount);
typedef TransientDetectDart = int Function(Pointer<Double> samples, int length, double sampleRate, double sensitivity, int algorithm, Pointer<Uint64> outPositions, int outMaxCount);

// Clip-based transient detection (Sample Editor hitpoints)
typedef EngineDetectClipTransientsNative = Uint32 Function(
  Uint64 clipId,
  Float sensitivity,
  Uint32 algorithm,
  Float minGapMs,
  Pointer<Uint64> outPositions,
  Pointer<Float> outStrengths,
  Uint32 outCapacity,
);
typedef EngineDetectClipTransientsDart = int Function(
  int clipId,
  double sensitivity,
  int algorithm,
  double minGapMs,
  Pointer<Uint64> outPositions,
  Pointer<Float> outStrengths,
  int outCapacity,
);

typedef EngineGetClipSampleRateNative = Uint32 Function(Uint64 clipId);
typedef EngineGetClipSampleRateDart = int Function(int clipId);

typedef EngineGetClipTotalFramesNative = Uint64 Function(Uint64 clipId);
typedef EngineGetClipTotalFramesDart = int Function(int clipId);

// Pitch Detection
typedef PitchDetectNative = Double Function(Pointer<Double> samples, Uint32 length, Double sampleRate);
typedef PitchDetectDart = double Function(Pointer<Double> samples, int length, double sampleRate);

typedef PitchDetectMidiNative = Int32 Function(Pointer<Double> samples, Uint32 length, Double sampleRate);
typedef PitchDetectMidiDart = int Function(Pointer<Double> samples, int length, double sampleRate);

// Wave Cache (Multi-Resolution Waveform Caching)
typedef WaveCacheHasCacheNative = Int32 Function(Pointer<Utf8> audioPath);
typedef WaveCacheHasCacheDart = int Function(Pointer<Utf8> audioPath);

typedef WaveCacheBuildNative = Int32 Function(Pointer<Utf8> audioPath, Uint32 sampleRate, Uint8 channels, Uint64 totalFrames);
typedef WaveCacheBuildDart = int Function(Pointer<Utf8> audioPath, int sampleRate, int channels, int totalFrames);

typedef WaveCacheBuildProgressNative = Float Function(Pointer<Utf8> audioPath);
typedef WaveCacheBuildProgressDart = double Function(Pointer<Utf8> audioPath);

typedef WaveCacheQueryTilesNative = Pointer<Float> Function(
  Pointer<Utf8> audioPath,
  Uint64 startFrame,
  Uint64 endFrame,
  Double pixelsPerSecond,
  Uint32 sampleRate,
  Pointer<Uint32> outMipLevel,
  Pointer<Uint32> outSamplesPerTile,
  Pointer<Uint32> outTileCount,
);
typedef WaveCacheQueryTilesDart = Pointer<Float> Function(
  Pointer<Utf8> audioPath,
  int startFrame,
  int endFrame,
  double pixelsPerSecond,
  int sampleRate,
  Pointer<Uint32> outMipLevel,
  Pointer<Uint32> outSamplesPerTile,
  Pointer<Uint32> outTileCount,
);

typedef WaveCacheFreeTilesNative = Void Function(Pointer<Float> ptr, Uint32 count);
typedef WaveCacheFreeTilesDart = void Function(Pointer<Float> ptr, int count);

typedef WaveCacheBuildFromSamplesNative = Int32 Function(
  Pointer<Utf8> audioPath,
  Pointer<Float> samples,
  Uint64 sampleCount,
  Uint8 channels,
  Uint32 sampleRate,
);
typedef WaveCacheBuildFromSamplesDart = int Function(
  Pointer<Utf8> audioPath,
  Pointer<Float> samples,
  int sampleCount,
  int channels,
  int sampleRate,
);

typedef WaveCacheClearAllNative = Void Function();
typedef WaveCacheClearAllDart = void Function();

typedef WaveCacheLoadedCountNative = Uint32 Function();
typedef WaveCacheLoadedCountDart = int Function();

// ═══════════════════════════════════════════════════════════════════════════
// COMPING TYPEDEFS
// ═══════════════════════════════════════════════════════════════════════════

typedef CompingCreateLaneNative = Uint64 Function(Uint64 trackId);
typedef CompingCreateLaneDart = int Function(int trackId);

typedef CompingDeleteLaneNative = Int32 Function(Uint64 trackId, Uint64 laneId);
typedef CompingDeleteLaneDart = int Function(int trackId, int laneId);

typedef CompingSetActiveLaneNative = Int32 Function(Uint64 trackId, Uint32 laneIndex);
typedef CompingSetActiveLaneDart = int Function(int trackId, int laneIndex);

typedef CompingToggleLaneMuteNative = Int32 Function(Uint64 trackId, Uint64 laneId);
typedef CompingToggleLaneMuteDart = int Function(int trackId, int laneId);

typedef CompingSetLaneVisibleNative = Int32 Function(Uint64 trackId, Uint64 laneId, Int32 visible);
typedef CompingSetLaneVisibleDart = int Function(int trackId, int laneId, int visible);

typedef CompingSetLaneHeightNative = Int32 Function(Uint64 trackId, Uint64 laneId, Double height);
typedef CompingSetLaneHeightDart = int Function(int trackId, int laneId, double height);

typedef CompingAddTakeNative = Uint64 Function(Uint64 trackId, Pointer<Utf8> sourcePath, Double startTime, Double duration);
typedef CompingAddTakeDart = int Function(int trackId, Pointer<Utf8> sourcePath, double startTime, double duration);

typedef CompingDeleteTakeNative = Int32 Function(Uint64 trackId, Uint64 takeId);
typedef CompingDeleteTakeDart = int Function(int trackId, int takeId);

typedef CompingSetTakeRatingNative = Int32 Function(Uint64 trackId, Uint64 takeId, Int32 rating);
typedef CompingSetTakeRatingDart = int Function(int trackId, int takeId, int rating);

typedef CompingToggleTakeMuteNative = Int32 Function(Uint64 trackId, Uint64 takeId);
typedef CompingToggleTakeMuteDart = int Function(int trackId, int takeId);

typedef CompingToggleTakeInCompNative = Int32 Function(Uint64 trackId, Uint64 takeId);
typedef CompingToggleTakeInCompDart = int Function(int trackId, int takeId);

typedef CompingSetTakeGainNative = Int32 Function(Uint64 trackId, Uint64 takeId, Double gain);
typedef CompingSetTakeGainDart = int Function(int trackId, int takeId, double gain);

typedef CompingCreateRegionNative = Uint64 Function(Uint64 trackId, Uint64 takeId, Double startTime, Double endTime);
typedef CompingCreateRegionDart = int Function(int trackId, int takeId, double startTime, double endTime);

typedef CompingDeleteRegionNative = Int32 Function(Uint64 trackId, Uint64 regionId);
typedef CompingDeleteRegionDart = int Function(int trackId, int regionId);

typedef CompingSetRegionCrossfadeInNative = Int32 Function(Uint64 trackId, Uint64 regionId, Double duration);
typedef CompingSetRegionCrossfadeInDart = int Function(int trackId, int regionId, double duration);

typedef CompingSetRegionCrossfadeOutNative = Int32 Function(Uint64 trackId, Uint64 regionId, Double duration);
typedef CompingSetRegionCrossfadeOutDart = int Function(int trackId, int regionId, double duration);

typedef CompingSetRegionCrossfadeTypeNative = Int32 Function(Uint64 trackId, Uint64 regionId, Int32 crossfadeType);
typedef CompingSetRegionCrossfadeTypeDart = int Function(int trackId, int regionId, int crossfadeType);

typedef CompingSetModeNative = Int32 Function(Uint64 trackId, Int32 mode);
typedef CompingSetModeDart = int Function(int trackId, int mode);

typedef CompingGetModeNative = Int32 Function(Uint64 trackId);
typedef CompingGetModeDart = int Function(int trackId);

typedef CompingToggleLanesExpandedNative = Int32 Function(Uint64 trackId);
typedef CompingToggleLanesExpandedDart = int Function(int trackId);

typedef CompingGetLanesExpandedNative = Int32 Function(Uint64 trackId);
typedef CompingGetLanesExpandedDart = int Function(int trackId);

typedef CompingGetLaneCountNative = Uint32 Function(Uint64 trackId);
typedef CompingGetLaneCountDart = int Function(int trackId);

typedef CompingGetActiveLaneIndexNative = Int32 Function(Uint64 trackId);
typedef CompingGetActiveLaneIndexDart = int Function(int trackId);

typedef CompingClearCompNative = Int32 Function(Uint64 trackId);
typedef CompingClearCompDart = int Function(int trackId);

typedef CompingGetStateJsonNative = Pointer<Utf8> Function(Uint64 trackId);
typedef CompingGetStateJsonDart = Pointer<Utf8> Function(int trackId);

typedef CompingLoadStateJsonNative = Int32 Function(Uint64 trackId, Pointer<Utf8> json);
typedef CompingLoadStateJsonDart = int Function(int trackId, Pointer<Utf8> json);

typedef CompingStartRecordingNative = Int32 Function(Uint64 trackId, Double startTime);
typedef CompingStartRecordingDart = int Function(int trackId, double startTime);

typedef CompingStopRecordingNative = Int32 Function(Uint64 trackId);
typedef CompingStopRecordingDart = int Function(int trackId);

typedef CompingIsRecordingNative = Int32 Function(Uint64 trackId);
typedef CompingIsRecordingDart = int Function(int trackId);

typedef CompingDeleteBadTakesNative = Uint32 Function(Uint64 trackId);
typedef CompingDeleteBadTakesDart = int Function(int trackId);

typedef CompingPromoteBestTakesNative = Uint32 Function(Uint64 trackId);
typedef CompingPromoteBestTakesDart = int Function(int trackId);

typedef CompingRemoveTrackNative = Void Function(Uint64 trackId);
typedef CompingRemoveTrackDart = void Function(int trackId);

typedef CompingClearAllNative = Void Function();
typedef CompingClearAllDart = void Function();

// ═══════════════════════════════════════════════════════════════════════════
// VIDEO FFI TYPEDEFS
// ═══════════════════════════════════════════════════════════════════════════

typedef VideoAddTrackNative = Uint64 Function(Pointer<Utf8> name);
typedef VideoAddTrackDart = int Function(Pointer<Utf8> name);

typedef VideoImportNative = Uint64 Function(Uint64 trackId, Pointer<Utf8> path, Uint64 timelineStartSamples);
typedef VideoImportDart = int Function(int trackId, Pointer<Utf8> path, int timelineStartSamples);

typedef VideoSetPlayheadNative = Void Function(Uint64 samples);
typedef VideoSetPlayheadDart = void Function(int samples);

typedef VideoGetPlayheadNative = Uint64 Function();
typedef VideoGetPlayheadDart = int Function();

typedef VideoGetFrameNative = Pointer<Uint8> Function(Uint64 clipId, Uint64 frameSamples, Pointer<Uint32> width, Pointer<Uint32> height, Pointer<Uint64> dataSize);
typedef VideoGetFrameDart = Pointer<Uint8> Function(int clipId, int frameSamples, Pointer<Uint32> width, Pointer<Uint32> height, Pointer<Uint64> dataSize);

typedef VideoFreeFrameNative = Void Function(Pointer<Uint8> data, Uint64 size);
typedef VideoFreeFrameDart = void Function(Pointer<Uint8> data, int size);

typedef VideoGetInfoJsonNative = Pointer<Utf8> Function(Uint64 clipId);
typedef VideoGetInfoJsonDart = Pointer<Utf8> Function(int clipId);

typedef VideoGenerateThumbnailsNative = Uint32 Function(Uint64 clipId, Uint32 width, Uint64 intervalFrames);
typedef VideoGenerateThumbnailsDart = int Function(int clipId, int width, int intervalFrames);

typedef VideoGetTrackCountNative = Uint32 Function();
typedef VideoGetTrackCountDart = int Function();

typedef VideoClearAllNative = Void Function();
typedef VideoClearAllDart = void Function();

typedef VideoFormatTimecodeNative = Pointer<Utf8> Function(Double seconds, Double frameRate, Int32 dropFrame);
typedef VideoFormatTimecodeDart = Pointer<Utf8> Function(double seconds, double frameRate, int dropFrame);

typedef VideoParseTimecodeNative = Double Function(Pointer<Utf8> tcStr, Double frameRate);
typedef VideoParseTimecodeDart = double Function(Pointer<Utf8> tcStr, double frameRate);

// Mastering Engine FFI
typedef MasteringEngineInitNative = Void Function(Uint32 sampleRate);
typedef MasteringEngineInitDart = void Function(int sampleRate);

typedef MasteringSetPresetNative = Int32 Function(Uint8 preset);
typedef MasteringSetPresetDart = int Function(int preset);

typedef MasteringSetLoudnessTargetNative = Int32 Function(Float integratedLufs, Float truePeak, Float lraTarget);
typedef MasteringSetLoudnessTargetDart = int Function(double integratedLufs, double truePeak, double lraTarget);

typedef MasteringSetReferenceNative = Int32 Function(Pointer<Utf8> name, Pointer<Float> left, Pointer<Float> right, Uint32 length);
typedef MasteringSetReferenceDart = int Function(Pointer<Utf8> name, Pointer<Float> left, Pointer<Float> right, int length);

typedef MasteringProcessOfflineNative = Int32 Function(Pointer<Float> left, Pointer<Float> right, Pointer<Float> outLeft, Pointer<Float> outRight, Uint32 length);
typedef MasteringProcessOfflineDart = int Function(Pointer<Float> left, Pointer<Float> right, Pointer<Float> outLeft, Pointer<Float> outRight, int length);

typedef MasteringGetResultNative = MasteringResultFFIStruct Function();
typedef MasteringGetResultDart = MasteringResultFFIStruct Function();

typedef MasteringGetWarningNative = Pointer<Utf8> Function(Uint32 index);
typedef MasteringGetWarningDart = Pointer<Utf8> Function(int index);

typedef MasteringGetChainSummaryNative = Pointer<Utf8> Function();
typedef MasteringGetChainSummaryDart = Pointer<Utf8> Function();

typedef MasteringResetNative = Void Function();
typedef MasteringResetDart = void Function();

typedef MasteringSetActiveNative = Void Function(Int32 active);
typedef MasteringSetActiveDart = void Function(int active);

typedef MasteringGetGainReductionNative = Float Function();
typedef MasteringGetGainReductionDart = double Function();

typedef MasteringGetDetectedGenreNative = Uint8 Function();
typedef MasteringGetDetectedGenreDart = int Function();

typedef MasteringGetLatencyNative = Uint32 Function();
typedef MasteringGetLatencyDart = int Function();

// Mastering result struct (matches Rust MasteringResultFFI)
final class MasteringResultFFIStruct extends Struct {
  @Float()
  external double inputLufs;
  @Float()
  external double outputLufs;
  @Float()
  external double inputPeak;
  @Float()
  external double outputPeak;
  @Float()
  external double appliedGain;
  @Float()
  external double peakReduction;
  @Float()
  external double qualityScore;
  @Uint8()
  external int detectedGenre;
  @Uint32()
  external int warningCount;
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO RESTORATION FFI TYPEDEFS
// ═══════════════════════════════════════════════════════════════════════════

typedef RestorationInitNative = Void Function(Uint32 sampleRate);
typedef RestorationInitDart = void Function(int sampleRate);

typedef RestorationSetSettingsNative = Int32 Function(
  Int32 denoiseEnabled, Float denoiseStrength,
  Int32 declickEnabled, Float declickSensitivity,
  Int32 declipEnabled, Float declipThreshold,
  Int32 dehumEnabled, Float dehumFrequency, Uint32 dehumHarmonics,
  Int32 dereverbEnabled, Float dereverbAmount,
);
typedef RestorationSetSettingsDart = int Function(
  int denoiseEnabled, double denoiseStrength,
  int declickEnabled, double declickSensitivity,
  int declipEnabled, double declipThreshold,
  int dehumEnabled, double dehumFrequency, int dehumHarmonics,
  int dereverbEnabled, double dereverbAmount,
);

typedef RestorationGetSettingsNative = RestorationSettingsFFIStruct Function();
typedef RestorationGetSettingsDart = RestorationSettingsFFIStruct Function();

typedef RestorationAnalyzeNative = RestorationAnalysisFFIStruct Function(Pointer<Utf8> path);
typedef RestorationAnalyzeDart = RestorationAnalysisFFIStruct Function(Pointer<Utf8> path);

typedef RestorationGetSuggestionCountNative = Uint32 Function();
typedef RestorationGetSuggestionCountDart = int Function();

typedef RestorationGetSuggestionNative = Pointer<Utf8> Function(Uint32 index);
typedef RestorationGetSuggestionDart = Pointer<Utf8> Function(int index);

typedef RestorationProcessNative = Int32 Function(Pointer<Float> input, Pointer<Float> output, Uint32 length);
typedef RestorationProcessDart = int Function(Pointer<Float> input, Pointer<Float> output, int length);

typedef RestorationProcessFileNative = Int32 Function(Pointer<Utf8> inputPath, Pointer<Utf8> outputPath);
typedef RestorationProcessFileDart = int Function(Pointer<Utf8> inputPath, Pointer<Utf8> outputPath);

typedef RestorationLearnNoiseProfileNative = Int32 Function(Pointer<Float> input, Uint32 length);
typedef RestorationLearnNoiseProfileDart = int Function(Pointer<Float> input, int length);

typedef RestorationClearNoiseProfileNative = Void Function();
typedef RestorationClearNoiseProfileDart = void Function();

typedef RestorationGetStateNative = Void Function(Pointer<Int32> outIsProcessing, Pointer<Float> outProgress);
typedef RestorationGetStateDart = void Function(Pointer<Int32> outIsProcessing, Pointer<Float> outProgress);

typedef RestorationGetPhaseNative = Pointer<Utf8> Function();
typedef RestorationGetPhaseDart = Pointer<Utf8> Function();

typedef RestorationSetActiveNative = Void Function(Int32 active);
typedef RestorationSetActiveDart = void Function(int active);

typedef RestorationGetLatencyNative = Uint32 Function();
typedef RestorationGetLatencyDart = int Function();

typedef RestorationResetNative = Void Function();
typedef RestorationResetDart = void Function();

// Restoration settings struct (matches Rust RestorationSettingsFFI)
final class RestorationSettingsFFIStruct extends Struct {
  @Int32()
  external int denoiseEnabled;
  @Float()
  external double denoiseStrength;
  @Int32()
  external int declickEnabled;
  @Float()
  external double declickSensitivity;
  @Int32()
  external int declipEnabled;
  @Float()
  external double declipThreshold;
  @Int32()
  external int dehumEnabled;
  @Float()
  external double dehumFrequency;
  @Uint32()
  external int dehumHarmonics;
  @Int32()
  external int dereverbEnabled;
  @Float()
  external double dereverbAmount;
}

// Restoration analysis struct (matches Rust RestorationAnalysisFFI)
final class RestorationAnalysisFFIStruct extends Struct {
  @Float()
  external double noiseFloorDb;
  @Float()
  external double clicksPerSecond;
  @Float()
  external double clippingPercent;
  @Int32()
  external int humDetected;
  @Float()
  external double humFrequency;
  @Float()
  external double humLevelDb;
  @Float()
  external double reverbTailSeconds;
  @Float()
  external double qualityScore;
}

// ═══════════════════════════════════════════════════════════════════════════
// ML/AI PROCESSING FFI TYPEDEFS
// ═══════════════════════════════════════════════════════════════════════════

typedef MlInitNative = Void Function();
typedef MlInitDart = void Function();

typedef MlGetModelCountNative = Uint32 Function();
typedef MlGetModelCountDart = int Function();

typedef MlGetModelNameNative = Pointer<Utf8> Function(Uint32 index);
typedef MlGetModelNameDart = Pointer<Utf8> Function(int index);

typedef MlModelIsAvailableNative = Int32 Function(Uint32 index);
typedef MlModelIsAvailableDart = int Function(int index);

typedef MlGetModelSizeNative = Uint32 Function(Uint32 index);
typedef MlGetModelSizeDart = int Function(int index);

typedef MlDenoiseStartNative = Int32 Function(Pointer<Utf8> inputPath, Pointer<Utf8> outputPath, Float strength);
typedef MlDenoiseStartDart = int Function(Pointer<Utf8> inputPath, Pointer<Utf8> outputPath, double strength);

typedef MlSeparateStartNative = Int32 Function(Pointer<Utf8> inputPath, Pointer<Utf8> outputDir, Uint32 stemsMask);
typedef MlSeparateStartDart = int Function(Pointer<Utf8> inputPath, Pointer<Utf8> outputDir, int stemsMask);

typedef MlEnhanceVoiceStartNative = Int32 Function(Pointer<Utf8> inputPath, Pointer<Utf8> outputPath);
typedef MlEnhanceVoiceStartDart = int Function(Pointer<Utf8> inputPath, Pointer<Utf8> outputPath);

typedef MlGetProgressNative = Float Function();
typedef MlGetProgressDart = double Function();

typedef MlIsProcessingNative = Int32 Function();
typedef MlIsProcessingDart = int Function();

typedef MlGetPhaseNative = Pointer<Utf8> Function();
typedef MlGetPhaseDart = Pointer<Utf8> Function();

typedef MlGetCurrentModelNative = Pointer<Utf8> Function();
typedef MlGetCurrentModelDart = Pointer<Utf8> Function();

typedef MlCancelNative = Int32 Function();
typedef MlCancelDart = int Function();

typedef MlSetExecutionProviderNative = Int32 Function(Int32 provider);
typedef MlSetExecutionProviderDart = int Function(int provider);

typedef MlGetErrorNative = Pointer<Utf8> Function();
typedef MlGetErrorDart = Pointer<Utf8> Function();

typedef MlResetNative = Void Function();
typedef MlResetDart = void Function();

// ═══════════════════════════════════════════════════════════════════════════
// LUA SCRIPTING FFI TYPEDEFS
// ═══════════════════════════════════════════════════════════════════════════

typedef ScriptInitNative = Int32 Function();
typedef ScriptInitDart = int Function();

typedef ScriptShutdownNative = Void Function();
typedef ScriptShutdownDart = void Function();

typedef ScriptIsInitializedNative = Int32 Function();
typedef ScriptIsInitializedDart = int Function();

typedef ScriptExecuteNative = Int32 Function(Pointer<Utf8> code);
typedef ScriptExecuteDart = int Function(Pointer<Utf8> code);

typedef ScriptExecuteFileNative = Int32 Function(Pointer<Utf8> path);
typedef ScriptExecuteFileDart = int Function(Pointer<Utf8> path);

typedef ScriptLoadFileNative = Pointer<Utf8> Function(Pointer<Utf8> path);
typedef ScriptLoadFileDart = Pointer<Utf8> Function(Pointer<Utf8> path);

typedef ScriptRunNative = Int32 Function(Pointer<Utf8> name);
typedef ScriptRunDart = int Function(Pointer<Utf8> name);

typedef ScriptGetOutputNative = Pointer<Utf8> Function();
typedef ScriptGetOutputDart = Pointer<Utf8> Function();

typedef ScriptGetErrorNative = Pointer<Utf8> Function();
typedef ScriptGetErrorDart = Pointer<Utf8> Function();

typedef ScriptGetDurationNative = Uint32 Function();
typedef ScriptGetDurationDart = int Function();

typedef ScriptPollActionsNative = Uint32 Function();
typedef ScriptPollActionsDart = int Function();

typedef ScriptGetNextActionNative = Pointer<Utf8> Function();
typedef ScriptGetNextActionDart = Pointer<Utf8> Function();

typedef ScriptSetContextNative = Void Function(Uint64 playhead, Int32 isPlaying, Int32 isRecording, Uint32 sampleRate);
typedef ScriptSetContextDart = void Function(int playhead, int isPlaying, int isRecording, int sampleRate);

typedef ScriptSetSelectedTracksNative = Void Function(Pointer<Uint64> trackIds, Uint32 count);
typedef ScriptSetSelectedTracksDart = void Function(Pointer<Uint64> trackIds, int count);

typedef ScriptSetSelectedClipsNative = Void Function(Pointer<Uint64> clipIds, Uint32 count);
typedef ScriptSetSelectedClipsDart = void Function(Pointer<Uint64> clipIds, int count);

typedef ScriptAddSearchPathNative = Void Function(Pointer<Utf8> path);
typedef ScriptAddSearchPathDart = void Function(Pointer<Utf8> path);

typedef ScriptGetLoadedCountNative = Uint32 Function();
typedef ScriptGetLoadedCountDart = int Function();

typedef ScriptGetNameNative = Pointer<Utf8> Function(Uint32 index);
typedef ScriptGetNameDart = Pointer<Utf8> Function(int index);

typedef ScriptGetDescriptionNative = Pointer<Utf8> Function(Uint32 index);
typedef ScriptGetDescriptionDart = Pointer<Utf8> Function(int index);

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN HOSTING FFI TYPEDEFS
// ═══════════════════════════════════════════════════════════════════════════

typedef PluginHostInitNative = Int32 Function();
typedef PluginHostInitDart = int Function();

typedef PluginScanAllNative = Int32 Function();
typedef PluginScanAllDart = int Function();

typedef PluginGetCountNative = Uint32 Function();
typedef PluginGetCountDart = int Function();

typedef PluginGetAllJsonNative = Pointer<Utf8> Function();
typedef PluginGetAllJsonDart = Pointer<Utf8> Function();

typedef PluginGetInfoJsonNative = Pointer<Utf8> Function(Uint32 index);
typedef PluginGetInfoJsonDart = Pointer<Utf8> Function(int index);

typedef PluginLoadNative = Int32 Function(Pointer<Utf8> pluginId, Pointer<Uint8> outInstanceId, Uint32 maxLen);
typedef PluginLoadDart = int Function(Pointer<Utf8> pluginId, Pointer<Uint8> outInstanceId, int maxLen);

typedef PluginUnloadNative = Int32 Function(Pointer<Utf8> instanceId);
typedef PluginUnloadDart = int Function(Pointer<Utf8> instanceId);

typedef PluginActivateNative = Int32 Function(Pointer<Utf8> instanceId);
typedef PluginActivateDart = int Function(Pointer<Utf8> instanceId);

typedef PluginDeactivateNative = Int32 Function(Pointer<Utf8> instanceId);
typedef PluginDeactivateDart = int Function(Pointer<Utf8> instanceId);

typedef PluginGetParamCountNative = Int32 Function(Pointer<Utf8> instanceId);
typedef PluginGetParamCountDart = int Function(Pointer<Utf8> instanceId);

typedef PluginGetParamNative = Double Function(Pointer<Utf8> instanceId, Uint32 paramId);
typedef PluginGetParamDart = double Function(Pointer<Utf8> instanceId, int paramId);

typedef PluginSetParamNative = Int32 Function(Pointer<Utf8> instanceId, Uint32 paramId, Double value);
typedef PluginSetParamDart = int Function(Pointer<Utf8> instanceId, int paramId, double value);

typedef PluginGetAllParamsJsonNative = Pointer<Utf8> Function(Pointer<Utf8> instanceId);
typedef PluginGetAllParamsJsonDart = Pointer<Utf8> Function(Pointer<Utf8> instanceId);

typedef PluginHasEditorNative = Int32 Function(Pointer<Utf8> instanceId);
typedef PluginHasEditorDart = int Function(Pointer<Utf8> instanceId);

typedef PluginGetLatencyNative = Int32 Function(Pointer<Utf8> instanceId);
typedef PluginGetLatencyDart = int Function(Pointer<Utf8> instanceId);

typedef PluginOpenEditorNative = Int32 Function(Pointer<Utf8> instanceId, Pointer<Void> parentWindow);
typedef PluginOpenEditorDart = int Function(Pointer<Utf8> instanceId, Pointer<Void> parentWindow);

typedef PluginCloseEditorNative = Int32 Function(Pointer<Utf8> instanceId);
typedef PluginCloseEditorDart = int Function(Pointer<Utf8> instanceId);

typedef PluginEditorSizeNative = Uint64 Function(Pointer<Utf8> instanceId);
typedef PluginEditorSizeDart = int Function(Pointer<Utf8> instanceId);

typedef PluginResizeEditorNative = Int32 Function(Pointer<Utf8> instanceId, Uint32 width, Uint32 height);
typedef PluginResizeEditorDart = int Function(Pointer<Utf8> instanceId, int width, int height);

typedef PluginSearchNative = Uint32 Function(Pointer<Utf8> query, Pointer<Uint32> outIndices, Uint32 maxIndices);
typedef PluginSearchDart = int Function(Pointer<Utf8> query, Pointer<Uint32> outIndices, int maxIndices);

typedef PluginGetByTypeNative = Uint32 Function(Uint8 pluginType, Pointer<Uint32> outIndices, Uint32 maxIndices);
typedef PluginGetByTypeDart = int Function(int pluginType, Pointer<Uint32> outIndices, int maxIndices);

typedef PluginGetByCategoryNative = Uint32 Function(Uint8 category, Pointer<Uint32> outIndices, Uint32 maxIndices);
typedef PluginGetByCategoryDart = int Function(int category, Pointer<Uint32> outIndices, int maxIndices);

typedef PluginGetInstancesJsonNative = Pointer<Utf8> Function();
typedef PluginGetInstancesJsonDart = Pointer<Utf8> Function();

// Plugin Insert Chain
typedef PluginInsertLoadNative = Int32 Function(Uint64 channelId, Pointer<Utf8> pluginId);
typedef PluginInsertLoadDart = int Function(int channelId, Pointer<Utf8> pluginId);

typedef PluginInsertRemoveNative = Int32 Function(Uint64 channelId, Uint32 slotIndex);
typedef PluginInsertRemoveDart = int Function(int channelId, int slotIndex);

typedef PluginInsertSetBypassNative = Int32 Function(Uint64 channelId, Uint32 slotIndex, Int32 bypass);
typedef PluginInsertSetBypassDart = int Function(int channelId, int slotIndex, int bypass);

typedef PluginInsertSetMixNative = Int32 Function(Uint64 channelId, Uint32 slotIndex, Float mix);
typedef PluginInsertSetMixDart = int Function(int channelId, int slotIndex, double mix);

typedef PluginInsertGetMixNative = Float Function(Uint64 channelId, Uint32 slotIndex);
typedef PluginInsertGetMixDart = double Function(int channelId, int slotIndex);

typedef PluginInsertGetLatencyNative = Int32 Function(Uint64 channelId, Uint32 slotIndex);
typedef PluginInsertGetLatencyDart = int Function(int channelId, int slotIndex);

typedef PluginInsertChainLatencyNative = Int32 Function(Uint64 channelId);
typedef PluginInsertChainLatencyDart = int Function(int channelId);

// MIDI I/O
typedef MidiScanInputDevicesNative = Uint32 Function();
typedef MidiScanInputDevicesDart = int Function();

typedef MidiScanOutputDevicesNative = Uint32 Function();
typedef MidiScanOutputDevicesDart = int Function();

typedef MidiGetInputDeviceNameNative = Int32 Function(Uint32 index, Pointer<Utf8> outName, Uint32 maxLen);
typedef MidiGetInputDeviceNameDart = int Function(int index, Pointer<Utf8> outName, int maxLen);

typedef MidiGetOutputDeviceNameNative = Int32 Function(Uint32 index, Pointer<Utf8> outName, Uint32 maxLen);
typedef MidiGetOutputDeviceNameDart = int Function(int index, Pointer<Utf8> outName, int maxLen);

typedef MidiInputDeviceCountNative = Uint32 Function();
typedef MidiInputDeviceCountDart = int Function();

typedef MidiOutputDeviceCountNative = Uint32 Function();
typedef MidiOutputDeviceCountDart = int Function();

typedef MidiConnectInputNative = Int32 Function(Uint32 deviceIndex);
typedef MidiConnectInputDart = int Function(int deviceIndex);

typedef MidiDisconnectInputNative = Int32 Function(Uint32 connectionIndex);
typedef MidiDisconnectInputDart = int Function(int connectionIndex);

typedef MidiDisconnectAllInputsNative = Void Function();
typedef MidiDisconnectAllInputsDart = void Function();

typedef MidiActiveInputCountNative = Uint32 Function();
typedef MidiActiveInputCountDart = int Function();

typedef MidiConnectOutputNative = Int32 Function(Uint32 deviceIndex);
typedef MidiConnectOutputDart = int Function(int deviceIndex);

typedef MidiDisconnectOutputNative = Void Function();
typedef MidiDisconnectOutputDart = void Function();

typedef MidiIsOutputConnectedNative = Int32 Function();
typedef MidiIsOutputConnectedDart = int Function();

typedef MidiStartRecordingNative = Void Function(Uint64 trackId);
typedef MidiStartRecordingDart = void Function(int trackId);

typedef MidiStopRecordingNative = Void Function();
typedef MidiStopRecordingDart = void Function();

typedef MidiArmTrackNative = Void Function(Uint64 trackId);
typedef MidiArmTrackDart = void Function(int trackId);

typedef MidiIsRecordingNative = Int32 Function();
typedef MidiIsRecordingDart = int Function();

typedef MidiGetRecordingStateNative = Uint32 Function();
typedef MidiGetRecordingStateDart = int Function();

typedef MidiRecordedEventCountNative = Uint32 Function();
typedef MidiRecordedEventCountDart = int Function();

typedef MidiGetTargetTrackNative = Uint64 Function();
typedef MidiGetTargetTrackDart = int Function();

typedef MidiSetSampleRateNative = Void Function(Uint32 sampleRate);
typedef MidiSetSampleRateDart = void Function(int sampleRate);

typedef MidiSetThruNative = Void Function(Int32 enabled);
typedef MidiSetThruDart = void Function(int enabled);

typedef MidiIsThruEnabledNative = Int32 Function();
typedef MidiIsThruEnabledDart = int Function();

typedef MidiSendNoteOnNative = Int32 Function(Uint8 channel, Uint8 note, Uint8 velocity);
typedef MidiSendNoteOnDart = int Function(int channel, int note, int velocity);

typedef MidiSendNoteOffNative = Int32 Function(Uint8 channel, Uint8 note, Uint8 velocity);
typedef MidiSendNoteOffDart = int Function(int channel, int note, int velocity);

typedef MidiSendCcNative = Int32 Function(Uint8 channel, Uint8 cc, Uint8 value);
typedef MidiSendCcDart = int Function(int channel, int cc, int value);

typedef MidiSendPitchBendNative = Int32 Function(Uint8 channel, Uint16 value);
typedef MidiSendPitchBendDart = int Function(int channel, int value);

typedef MidiSendProgramChangeNative = Int32 Function(Uint8 channel, Uint8 program);
typedef MidiSendProgramChangeDart = int Function(int channel, int program);

// Autosave System
typedef AutosaveInitNative = Int32 Function(Pointer<Utf8> projectName);
typedef AutosaveInitDart = int Function(Pointer<Utf8> projectName);

typedef AutosaveShutdownNative = Void Function();
typedef AutosaveShutdownDart = void Function();

typedef AutosaveSetEnabledNative = Void Function(Int32 enabled);
typedef AutosaveSetEnabledDart = void Function(int enabled);

typedef AutosaveIsEnabledNative = Int32 Function();
typedef AutosaveIsEnabledDart = int Function();

typedef AutosaveSetIntervalNative = Void Function(Uint32 intervalSecs);
typedef AutosaveSetIntervalDart = void Function(int intervalSecs);

typedef AutosaveGetIntervalNative = Uint32 Function();
typedef AutosaveGetIntervalDart = int Function();

typedef AutosaveSetBackupCountNative = Void Function(Uint32 count);
typedef AutosaveSetBackupCountDart = void Function(int count);

typedef AutosaveGetBackupCountNative = Uint32 Function();
typedef AutosaveGetBackupCountDart = int Function();

typedef AutosaveMarkDirtyNative = Void Function();
typedef AutosaveMarkDirtyDart = void Function();

typedef AutosaveMarkCleanNative = Void Function();
typedef AutosaveMarkCleanDart = void Function();

typedef AutosaveIsDirtyNative = Int32 Function();
typedef AutosaveIsDirtyDart = int Function();

typedef AutosaveShouldSaveNative = Int32 Function();
typedef AutosaveShouldSaveDart = int Function();

typedef AutosaveNowNative = Int32 Function(Pointer<Utf8> projectData);
typedef AutosaveNowDart = int Function(Pointer<Utf8> projectData);

typedef AutosaveBackupCountNative = Uint32 Function();
typedef AutosaveBackupCountDart = int Function();

typedef AutosaveLatestPathNative = Int32 Function(Pointer<Utf8> outPath, Uint32 maxLen);
typedef AutosaveLatestPathDart = int Function(Pointer<Utf8> outPath, int maxLen);

typedef AutosaveClearBackupsNative = Void Function();
typedef AutosaveClearBackupsDart = void Function();

// Recent Projects
typedef RecentProjectsAddNative = Int32 Function(Pointer<Utf8> path);
typedef RecentProjectsAddDart = int Function(Pointer<Utf8> path);

typedef RecentProjectsCountNative = Uint32 Function();
typedef RecentProjectsCountDart = int Function();

typedef RecentProjectsGetNative = Int32 Function(Uint32 index, Pointer<Utf8> outPath, Uint32 maxLen);
typedef RecentProjectsGetDart = int Function(int index, Pointer<Utf8> outPath, int maxLen);

typedef RecentProjectsRemoveNative = Int32 Function(Pointer<Utf8> path);
typedef RecentProjectsRemoveDart = int Function(Pointer<Utf8> path);

typedef RecentProjectsClearNative = Void Function();
typedef RecentProjectsClearDart = void Function();

// Middleware Event System
typedef MiddlewareInitNative = Pointer<Void> Function();
typedef MiddlewareInitDart = Pointer<Void> Function();

typedef MiddlewareShutdownNative = Void Function();
typedef MiddlewareShutdownDart = void Function();

typedef MiddlewareIsInitializedNative = Int32 Function();
typedef MiddlewareIsInitializedDart = int Function();

typedef MiddlewareRegisterEventNative = Int32 Function(Uint32 eventId, Pointer<Utf8> name, Pointer<Utf8> category, Uint32 maxInstances);
typedef MiddlewareRegisterEventDart = int Function(int eventId, Pointer<Utf8> name, Pointer<Utf8> category, int maxInstances);

typedef MiddlewareAddActionNative = Int32 Function(Uint32 eventId, Uint32 actionType, Uint32 assetId, Uint32 busId, Uint32 scope, Uint32 priority, Uint32 fadeCurve, Uint32 fadeTimeMs, Uint32 delayMs);
typedef MiddlewareAddActionDart = int Function(int eventId, int actionType, int assetId, int busId, int scope, int priority, int fadeCurve, int fadeTimeMs, int delayMs);

typedef MiddlewarePostEventNative = Uint64 Function(Uint32 eventId, Uint64 gameObjectId);
typedef MiddlewarePostEventDart = int Function(int eventId, int gameObjectId);

typedef MiddlewarePostEventByNameNative = Uint64 Function(Pointer<Utf8> eventName, Uint64 gameObjectId);
typedef MiddlewarePostEventByNameDart = int Function(Pointer<Utf8> eventName, int gameObjectId);

typedef MiddlewareStopPlayingIdNative = Int32 Function(Uint64 playingId, Uint32 fadeMs);
typedef MiddlewareStopPlayingIdDart = int Function(int playingId, int fadeMs);

typedef MiddlewareStopEventNative = Void Function(Uint32 eventId, Uint64 gameObjectId, Uint32 fadeMs);
typedef MiddlewareStopEventDart = void Function(int eventId, int gameObjectId, int fadeMs);

typedef MiddlewareStopAllNative = Void Function(Uint32 fadeMs);
typedef MiddlewareStopAllDart = void Function(int fadeMs);

typedef MiddlewareRegisterStateGroupNative = Int32 Function(Uint32 groupId, Pointer<Utf8> name, Uint32 defaultState);
typedef MiddlewareRegisterStateGroupDart = int Function(int groupId, Pointer<Utf8> name, int defaultState);

typedef MiddlewareAddStateNative = Int32 Function(Uint32 groupId, Uint32 stateId, Pointer<Utf8> stateName);
typedef MiddlewareAddStateDart = int Function(int groupId, int stateId, Pointer<Utf8> stateName);

typedef MiddlewareSetStateNative = Int32 Function(Uint32 groupId, Uint32 stateId);
typedef MiddlewareSetStateDart = int Function(int groupId, int stateId);

typedef MiddlewareGetStateNative = Uint32 Function(Uint32 groupId);
typedef MiddlewareGetStateDart = int Function(int groupId);

typedef MiddlewareRegisterSwitchGroupNative = Int32 Function(Uint32 groupId, Pointer<Utf8> name);
typedef MiddlewareRegisterSwitchGroupDart = int Function(int groupId, Pointer<Utf8> name);

typedef MiddlewareAddSwitchNative = Int32 Function(Uint32 groupId, Uint32 switchId, Pointer<Utf8> switchName);
typedef MiddlewareAddSwitchDart = int Function(int groupId, int switchId, Pointer<Utf8> switchName);

typedef MiddlewareSetSwitchNative = Int32 Function(Uint64 gameObjectId, Uint32 groupId, Uint32 switchId);
typedef MiddlewareSetSwitchDart = int Function(int gameObjectId, int groupId, int switchId);

typedef MiddlewareRegisterRtpcNative = Int32 Function(Uint32 rtpcId, Pointer<Utf8> name, Float minValue, Float maxValue, Float defaultValue);
typedef MiddlewareRegisterRtpcDart = int Function(int rtpcId, Pointer<Utf8> name, double minValue, double maxValue, double defaultValue);

typedef MiddlewareSetRtpcNative = Int32 Function(Uint32 rtpcId, Float value, Uint32 interpolationMs);
typedef MiddlewareSetRtpcDart = int Function(int rtpcId, double value, int interpolationMs);

typedef MiddlewareSetRtpcOnObjectNative = Int32 Function(Uint64 gameObjectId, Uint32 rtpcId, Float value, Uint32 interpolationMs);
typedef MiddlewareSetRtpcOnObjectDart = int Function(int gameObjectId, int rtpcId, double value, int interpolationMs);

typedef MiddlewareGetRtpcNative = Float Function(Uint32 rtpcId);
typedef MiddlewareGetRtpcDart = double Function(int rtpcId);

typedef MiddlewareResetRtpcNative = Int32 Function(Uint32 rtpcId, Uint32 interpolationMs);
typedef MiddlewareResetRtpcDart = int Function(int rtpcId, int interpolationMs);

typedef MiddlewareRegisterGameObjectNative = Int32 Function(Uint64 gameObjectId, Pointer<Utf8> name);
typedef MiddlewareRegisterGameObjectDart = int Function(int gameObjectId, Pointer<Utf8> name);

typedef MiddlewareUnregisterGameObjectNative = Void Function(Uint64 gameObjectId);
typedef MiddlewareUnregisterGameObjectDart = void Function(int gameObjectId);

typedef MiddlewareGetEventCountNative = Uint32 Function();
typedef MiddlewareGetEventCountDart = int Function();

typedef MiddlewareGetStateGroupCountNative = Uint32 Function();
typedef MiddlewareGetStateGroupCountDart = int Function();

typedef MiddlewareGetSwitchGroupCountNative = Uint32 Function();
typedef MiddlewareGetSwitchGroupCountDart = int Function();

typedef MiddlewareGetRtpcCountNative = Uint32 Function();
typedef MiddlewareGetRtpcCountDart = int Function();

typedef MiddlewareGetActiveInstanceCountNative = Uint32 Function();
typedef MiddlewareGetActiveInstanceCountDart = int Function();

// ═══════════════════════════════════════════════════════════════════════════
// STAGE SYSTEM TYPEDEFS
// ═══════════════════════════════════════════════════════════════════════════

// Stage parsing
// Returns JSON result string (not bool) - contains trace_id or error
typedef StageParseJsonNative = Pointer<Utf8> Function(Pointer<Utf8> adapterId, Pointer<Utf8> jsonContent);
typedef StageParseJsonDart = Pointer<Utf8> Function(Pointer<Utf8> adapterId, Pointer<Utf8> jsonContent);
typedef StageGetTraceJsonNative = Pointer<Utf8> Function();
typedef StageGetTraceJsonDart = Pointer<Utf8> Function();
typedef StageGetEventCountNative = Uint32 Function();
typedef StageGetEventCountDart = int Function();
typedef StageGetEventJsonNative = Pointer<Utf8> Function(Uint32 index);
typedef StageGetEventJsonDart = Pointer<Utf8> Function(int index);

// Timing resolution
// profile: 0=Normal, 1=Turbo, 2=Mobile, 3=Studio, 4=Instant
typedef StageResolveTimingNative = Int32 Function(Uint8 profile);
typedef StageResolveTimingDart = int Function(int profile);
typedef StageGetTimedTraceJsonNative = Pointer<Utf8> Function();
typedef StageGetTimedTraceJsonDart = Pointer<Utf8> Function();
typedef StageGetDurationMsNative = Double Function();
typedef StageGetDurationMsDart = double Function();
typedef StageGetEventsAtTimeNative = Pointer<Utf8> Function(Double timeMs);
typedef StageGetEventsAtTimeDart = Pointer<Utf8> Function(double timeMs);

// Wizard
typedef WizardAnalyzeJsonNative = Bool Function(Pointer<Utf8> json);
typedef WizardAnalyzeJsonDart = bool Function(Pointer<Utf8> json);
typedef WizardGetConfidenceNative = Double Function();
typedef WizardGetConfidenceDart = double Function();
typedef WizardGetRecommendedLayerNative = Pointer<Utf8> Function();
typedef WizardGetRecommendedLayerDart = Pointer<Utf8> Function();
typedef WizardGetDetectedCompanyNative = Pointer<Utf8> Function();
typedef WizardGetDetectedCompanyDart = Pointer<Utf8> Function();
typedef WizardGetDetectedEngineNative = Pointer<Utf8> Function();
typedef WizardGetDetectedEngineDart = Pointer<Utf8> Function();
typedef WizardGetConfigTomlNative = Pointer<Utf8> Function();
typedef WizardGetConfigTomlDart = Pointer<Utf8> Function();
typedef WizardGetDetectedEventCountNative = Uint32 Function();
typedef WizardGetDetectedEventCountDart = int Function();
typedef WizardGetDetectedEventJsonNative = Pointer<Utf8> Function(Uint32 index);
typedef WizardGetDetectedEventJsonDart = Pointer<Utf8> Function(int index);

// Adapter registry
typedef AdapterLoadConfigNative = Bool Function(Pointer<Utf8> toml);
typedef AdapterLoadConfigDart = bool Function(Pointer<Utf8> toml);
typedef AdapterGetCountNative = Uint32 Function();
typedef AdapterGetCountDart = int Function();
typedef AdapterGetIdAtNative = Pointer<Utf8> Function(Uint32 index);
typedef AdapterGetIdAtDart = Pointer<Utf8> Function(int index);
typedef AdapterGetInfoJsonNative = Pointer<Utf8> Function(Uint32 index);
typedef AdapterGetInfoJsonDart = Pointer<Utf8> Function(int index);

// ═══════════════════════════════════════════════════════════════════════════
// NATIVE FFI CLASS
// ═══════════════════════════════════════════════════════════════════════════

/// Native FFI bindings to Rust engine
class NativeFFI {
  static NativeFFI? _instance;
  static NativeFFI get instance => _instance ??= NativeFFI._();

  late final DynamicLibrary _lib;
  bool _loaded = false;

  // Function pointers
  late final EngineCreateTrackDart _createTrack;
  late final EngineDeleteTrackDart _deleteTrack;
  late final EngineSetTrackNameDart _setTrackName;
  late final EngineSetTrackMuteDart _setTrackMute;
  late final EngineSetTrackSoloDart _setTrackSolo;
  late final EngineIsSoloActiveDart _isSoloActive;
  late final EngineClearAllSolosDart _clearAllSolos;
  late final EngineSetTrackArmedDart _setTrackArmed;
  late final EngineSetTrackVolumeDart _setTrackVolume;
  late final EngineSetTrackPanDart _setTrackPan;
  late final EngineSetTrackPanRightDart _setTrackPanRight;
  late final EngineGetTrackChannelsDart _getTrackChannels;
  late final EngineSetTrackChannelsDart _setTrackChannels;
  late final EngineSetTrackBusDart _setTrackBus;
  late final EngineGetTrackCountDart _getTrackCount;
  late final EngineGetTrackPeakDart _getTrackPeak;
  late final EngineGetTrackPeakStereoDart _getTrackPeakStereo;
  late final EngineGetTrackRmsStereoDart _getTrackRmsStereo;
  late final EngineGetTrackCorrelationDart _getTrackCorrelation;
  late final EngineGetTrackMeterDart _getTrackMeter;
  late final EngineGetAllTrackPeaksDart _getAllTrackPeaks;
  late final EngineGetAllTrackMetersDart _getAllTrackMeters;

  late final EngineImportAudioDart _importAudio;

  late final EngineAddClipDart _addClip;
  late final EngineMoveClipDart _moveClip;
  late final EngineResizeClipDart _resizeClip;
  late final EngineSplitClipDart _splitClip;
  late final EngineDuplicateClipDart _duplicateClip;
  late final EngineDeleteClipDart _deleteClip;
  late final EngineSetClipGainDart _setClipGain;
  late final EngineSetClipMutedDart _setClipMuted;
  late final EngineGetClipDurationDart _getClipDuration;
  late final EngineGetClipSourceDurationDart _getClipSourceDuration;
  late final EngineGetAudioFileDurationDart _getAudioFileDuration;

  late final EngineGetWaveformPeaksDart _getWaveformPeaks;
  late final EngineGetWaveformLodLevelsDart _getWaveformLodLevels;
  late final EngineQueryWaveformPixelsDart _queryWaveformPixels;
  late final EngineQueryWaveformPixelsStereoDart _queryWaveformPixelsStereo;
  late final EngineGetWaveformSampleRateDart _getWaveformSampleRate;
  late final EngineGetWaveformTotalSamplesDart _getWaveformTotalSamples;
  late final EngineQueryWaveformTilesBatchDart _queryWaveformTilesBatch;
  late final EngineQueryRawSamplesDart _queryRawSamples;

  late final EngineSetLoopRegionDart _setLoopRegion;
  late final EngineSetLoopEnabledDart _setLoopEnabled;

  late final EngineAddMarkerDart _addMarker;
  late final EngineDeleteMarkerDart _deleteMarker;

  late final EngineCreateCrossfadeDart _createCrossfade;
  late final EngineDeleteCrossfadeDart _deleteCrossfade;
  late final EngineUpdateCrossfadeDart _updateCrossfade;

  // ignore: unused_field
  late final EngineFreeStringDart _freeString;
  late final EngineClearAllDart _clearAll;

  late final EngineSnapToGridDart _snapToGrid;
  late final EngineSnapToEventDart _snapToEvent;

  // Transport
  late final EnginePlayDart _play;
  late final EnginePauseDart _pause;
  late final EngineStopDart _stop;
  late final EngineSeekDart _seek;
  late final EngineStartScrubDart _startScrub;
  late final EngineUpdateScrubDart _updateScrub;
  late final EngineStopScrubDart _stopScrub;
  late final EngineIsScrubbingDart _isScrubbing;
  late final EngineSetScrubWindowMsDart _setScrubWindowMs;
  late final EngineGetPositionDart _getPosition;
  late final EngineGetPlaybackStateDart _getPlaybackState;
  late final EngineIsPlayingDart _isPlaying;
  late final EngineSetMasterVolumeDart _setMasterVolume;
  late final EngineGetMasterVolumeDart _getMasterVolume;

  // Varispeed
  late final EngineSetVarispeedEnabledDart _setVarispeedEnabled;
  late final EngineIsVarispeedEnabledDart _isVarispeedEnabled;
  late final EngineSetVarispeedRateDart _setVarispeedRate;
  late final EngineGetVarispeedRateDart _getVarispeedRate;
  late final EngineSetVarispeedSemitonesDart _setVarispeedSemitones;
  late final EngineGetVarispeedSemitonesDart _getVarispeedSemitones;
  late final EngineGetEffectivePlaybackRateDart _getEffectivePlaybackRate;

  late final EngineGetPlaybackPositionSecondsDart _getPlaybackPositionSeconds;
  late final EngineGetPlaybackPositionSamplesDart _getPlaybackPositionSamples;
  late final EnginePreloadAllDart _preloadAll;
  late final EnginePreloadRangeDart _preloadRange;
  late final EngineSyncLoopFromRegionDart _syncLoopFromRegion;
  late final EngineGetSampleRateDart _getSampleRate;

  // Audio stream control
  late final EngineStartPlaybackDart _startPlayback;
  late final EngineStopPlaybackDart _stopPlayback;

  // Undo/Redo
  late final EngineUndoDart _undo;
  late final EngineRedoDart _redo;
  late final EngineCanUndoDart _canUndo;
  late final EngineCanRedoDart _canRedo;

  // Project
  late final EngineSaveProjectDart _saveProject;
  late final EngineLoadProjectDart _loadProject;
  late final EngineIsProjectModifiedDart _isProjectModified;
  late final EngineMarkProjectDirtyDart _markProjectDirty;
  late final EngineMarkProjectCleanDart _markProjectClean;
  late final EngineSetProjectFilePathDart _setProjectFilePath;
  late final EngineGetProjectFilePathDart _getProjectFilePath;

  // Memory
  late final EngineGetMemoryUsageDart _getMemoryUsage;

  // Metering
  late final EngineGetPeakMetersDart _getPeakMeters;
  late final EngineGetRmsMetersDart _getRmsMeters;
  late final EngineGetLufsMetersDart _getLufsMeters;
  late final EngineGetTruePeakMetersDart _getTruePeakMeters;
  late final EngineGetCorrelationDart _getCorrelation;
  late final EngineGetStereoBalanceDart _getStereoBalance;
  late final EngineGetDynamicRangeDart _getDynamicRange;
  late final EngineGetMasterSpectrumDart _getMasterSpectrum;

  // EQ
  late final EngineEqSetBandEnabledDart _eqSetBandEnabled;
  late final EngineEqSetBandFrequencyDart _eqSetBandFrequency;
  late final EngineEqSetBandGainDart _eqSetBandGain;
  late final EngineEqSetBandQDart _eqSetBandQ;
  late final EngineEqSetBandShapeDart _eqSetBandShape;
  late final EngineEqSetBypassDart _eqSetBypass;

  // Mixer buses
  late final EngineMixerSetBusVolumeDart _mixerSetBusVolume;
  late final EngineMixerSetBusMuteDart _mixerSetBusMute;
  late final EngineMixerSetBusSoloDart _mixerSetBusSolo;
  late final EngineMixerSetBusPanDart _mixerSetBusPan;
  late final EngineMixerSetMasterVolumeDart _mixerSetMasterVolume;

  // Audio processing
  late final EngineClipNormalizeDart _clipNormalize;
  late final EngineClipReverseDart _clipReverse;
  late final EngineClipFadeInDart _clipFadeIn;
  late final EngineClipFadeOutDart _clipFadeOut;
  late final EngineClipApplyGainDart _clipApplyGain;

  // Track management
  late final EngineTrackRenameDart _trackRename;
  late final EngineTrackDuplicateDart _trackDuplicate;
  late final EngineTrackSetColorDart _trackSetColor;

  // VCA
  late final EngineVcaCreateDart _vcaCreate;
  late final EngineVcaDeleteDart _vcaDelete;
  late final EngineVcaSetLevelDart _vcaSetLevel;
  late final EngineVcaGetLevelDart _vcaGetLevel;
  late final EngineVcaSetMuteDart _vcaSetMute;
  late final EngineVcaAssignTrackDart _vcaAssignTrack;
  late final EngineVcaRemoveTrackDart _vcaRemoveTrack;
  late final EngineVcaGetTrackEffectiveVolumeDart _vcaGetTrackEffectiveVolume;

  // Group
  late final EngineGroupCreateDart _groupCreate;
  late final EngineGroupDeleteDart _groupDelete;
  late final EngineGroupAddTrackDart _groupAddTrack;
  late final EngineGroupRemoveTrackDart _groupRemoveTrack;
  late final EngineGroupSetLinkModeDart _groupSetLinkMode;

  // Clip FX
  late final ClipFxAddDart _clipFxAdd;
  late final ClipFxRemoveDart _clipFxRemove;
  late final ClipFxMoveDart _clipFxMove;
  late final ClipFxSetBypassDart _clipFxSetBypass;
  late final ClipFxSetChainBypassDart _clipFxSetChainBypass;
  late final ClipFxSetWetDryDart _clipFxSetWetDry;
  late final ClipFxSetInputGainDart _clipFxSetInputGain;
  late final ClipFxSetOutputGainDart _clipFxSetOutputGain;
  late final ClipFxSetGainParamsDart _clipFxSetGainParams;
  late final ClipFxSetCompressorParamsDart _clipFxSetCompressorParams;
  late final ClipFxSetLimiterParamsDart _clipFxSetLimiterParams;
  late final ClipFxSetGateParamsDart _clipFxSetGateParams;
  late final ClipFxSetSaturationParamsDart _clipFxSetSaturationParams;
  late final ClipFxCopyDart _clipFxCopy;
  late final ClipFxClearDart _clipFxClear;

  // Click track
  late final ClickSetEnabledDart _clickSetEnabled;
  late final ClickIsEnabledDart _clickIsEnabled;
  late final ClickSetVolumeDart _clickSetVolume;
  late final ClickSetPatternDart _clickSetPattern;
  late final ClickSetCountInDart _clickSetCountIn;
  late final ClickSetPanDart _clickSetPan;

  // Send functions
  late final SendSetLevelDart _sendSetLevel;
  late final SendSetLevelDbDart _sendSetLevelDb;
  late final SendSetDestinationDart _sendSetDestination;
  late final SendSetPanDart _sendSetPan;
  late final SendSetEnabledDart _sendSetEnabled;
  late final SendSetMutedDart _sendSetMuted;
  late final SendSetTapPointDart _sendSetTapPoint;
  late final SendCreateBankDart _sendCreateBank;
  late final SendRemoveBankDart _sendRemoveBank;

  // Return bus functions
  late final ReturnSetLevelDart _returnSetLevel;
  late final ReturnSetLevelDbDart _returnSetLevelDb;
  late final ReturnSetPanDart _returnSetPan;
  late final ReturnSetMutedDart _returnSetMuted;
  late final ReturnSetSoloDart _returnSetSolo;

  // Sidechain functions
  late final SidechainAddRouteDart _sidechainAddRoute;
  late final SidechainRemoveRouteDart _sidechainRemoveRoute;
  late final SidechainCreateInputDart _sidechainCreateInput;
  late final SidechainRemoveInputDart _sidechainRemoveInput;
  late final SidechainSetSourceDart _sidechainSetSource;
  late final SidechainSetFilterModeDart _sidechainSetFilterMode;
  late final SidechainSetFilterFreqDart _sidechainSetFilterFreq;
  late final SidechainSetFilterQDart _sidechainSetFilterQ;
  late final SidechainSetMixDart _sidechainSetMix;
  late final SidechainSetGainDbDart _sidechainSetGainDb;
  late final SidechainSetMonitorDart _sidechainSetMonitor;
  late final SidechainIsMonitoringDart _sidechainIsMonitoring;

  // Automation
  late final AutomationSetModeDart _automationSetMode;
  late final AutomationGetModeDart _automationGetMode;
  late final AutomationSetRecordingDart _automationSetRecording;
  late final AutomationIsRecordingDart _automationIsRecording;
  late final AutomationTouchParamDart _automationTouchParam;
  late final AutomationReleaseParamDart _automationReleaseParam;
  late final AutomationRecordChangeDart _automationRecordChange;
  late final AutomationAddPointDart _automationAddPoint;
  late final AutomationGetValueDart _automationGetValue;
  late final AutomationClearLaneDart _automationClearLane;

  // Plugin Automation
  late final AutomationAddPluginPointDart _automationAddPluginPoint;
  late final AutomationGetPluginValueDart _automationGetPluginValue;
  late final AutomationClearPluginLaneDart _automationClearPluginLane;
  late final AutomationTouchPluginDart _automationTouchPlugin;
  late final AutomationReleasePluginDart _automationReleasePlugin;

  // Insert Effects
  late final InsertCreateChainDart _insertCreateChain;
  late final InsertRemoveChainDart _insertRemoveChain;
  late final InsertSetBypassDart _insertSetBypass;
  late final InsertSetMixDart _insertSetMix;
  late final InsertGetMixDart _insertGetMix;
  late final InsertBypassAllDart _insertBypassAll;
  late final InsertGetTotalLatencyDart _insertGetTotalLatency;
  late final InsertLoadProcessorDart _insertLoadProcessor;
  late final InsertUnloadSlotDart _insertUnloadSlot;
  late final InsertSetParamDart _insertSetParam;
  late final InsertGetParamDart _insertGetParam;
  late final InsertIsLoadedDart _insertIsLoaded;
  late final InsertOpenEditorDart _insertOpenEditor;

  // Plugin State/Preset
  late final PluginGetStateDart _pluginGetState;
  late final PluginSetStateDart _pluginSetState;
  late final PluginSavePresetDart _pluginSavePreset;
  late final PluginLoadPresetDart _pluginLoadPreset;

  // Transient Detection
  late final TransientDetectDart _transientDetect;
  late final EngineDetectClipTransientsDart _detectClipTransients;
  late final EngineGetClipSampleRateDart _getClipSampleRate;
  late final EngineGetClipTotalFramesDart _getClipTotalFrames;

  // Pitch Detection
  late final PitchDetectDart _pitchDetect;
  late final PitchDetectMidiDart _pitchDetectMidi;

  // Wave Cache
  late final WaveCacheHasCacheDart _waveCacheHasCache;
  late final WaveCacheBuildDart _waveCacheBuild;
  late final WaveCacheBuildProgressDart _waveCacheBuildProgress;
  late final WaveCacheQueryTilesDart _waveCacheQueryTiles;
  late final WaveCacheFreeTilesDart _waveCacheFreeTiles;
  late final WaveCacheBuildFromSamplesDart _waveCacheBuildFromSamples;
  late final WaveCacheClearAllDart _waveCacheClearAll;
  late final WaveCacheLoadedCountDart _waveCacheLoadedCount;

  // Comping
  late final CompingCreateLaneDart _compingCreateLane;
  late final CompingDeleteLaneDart _compingDeleteLane;
  late final CompingSetActiveLaneDart _compingSetActiveLane;
  late final CompingToggleLaneMuteDart _compingToggleLaneMute;
  late final CompingSetLaneVisibleDart _compingSetLaneVisible;
  late final CompingSetLaneHeightDart _compingSetLaneHeight;
  late final CompingAddTakeDart _compingAddTake;
  late final CompingDeleteTakeDart _compingDeleteTake;
  late final CompingSetTakeRatingDart _compingSetTakeRating;
  late final CompingToggleTakeMuteDart _compingToggleTakeMute;
  late final CompingToggleTakeInCompDart _compingToggleTakeInComp;
  late final CompingSetTakeGainDart _compingSetTakeGain;
  late final CompingCreateRegionDart _compingCreateRegion;
  late final CompingDeleteRegionDart _compingDeleteRegion;
  late final CompingSetRegionCrossfadeInDart _compingSetRegionCrossfadeIn;
  late final CompingSetRegionCrossfadeOutDart _compingSetRegionCrossfadeOut;
  late final CompingSetRegionCrossfadeTypeDart _compingSetRegionCrossfadeType;
  late final CompingSetModeDart _compingSetMode;
  late final CompingGetModeDart _compingGetMode;
  late final CompingToggleLanesExpandedDart _compingToggleLanesExpanded;
  late final CompingGetLanesExpandedDart _compingGetLanesExpanded;
  late final CompingGetLaneCountDart _compingGetLaneCount;
  late final CompingGetActiveLaneIndexDart _compingGetActiveLaneIndex;
  late final CompingClearCompDart _compingClearComp;
  late final CompingGetStateJsonDart _compingGetStateJson;
  late final CompingLoadStateJsonDart _compingLoadStateJson;
  late final CompingStartRecordingDart _compingStartRecording;
  late final CompingStopRecordingDart _compingStopRecording;
  late final CompingIsRecordingDart _compingIsRecording;
  late final CompingDeleteBadTakesDart _compingDeleteBadTakes;
  late final CompingPromoteBestTakesDart _compingPromoteBestTakes;
  late final CompingRemoveTrackDart _compingRemoveTrack;
  late final CompingClearAllDart _compingClearAll;

  // Video FFI
  late final VideoAddTrackDart _videoAddTrack;
  late final VideoImportDart _videoImport;
  late final VideoSetPlayheadDart _videoSetPlayhead;
  late final VideoGetPlayheadDart _videoGetPlayhead;
  late final VideoGetFrameDart _videoGetFrame;
  late final VideoFreeFrameDart _videoFreeFrame;
  late final VideoGetInfoJsonDart _videoGetInfoJson;
  late final VideoGenerateThumbnailsDart _videoGenerateThumbnails;
  late final VideoGetTrackCountDart _videoGetTrackCount;
  late final VideoClearAllDart _videoClearAll;
  late final VideoFormatTimecodeDart _videoFormatTimecode;
  late final VideoParseTimecodeDart _videoParseTimecode;

  // Mastering Engine
  late final MasteringEngineInitDart _masteringEngineInit;
  late final MasteringSetPresetDart _masteringSetPreset;
  late final MasteringSetLoudnessTargetDart _masteringSetLoudnessTarget;
  late final MasteringSetReferenceDart _masteringSetReference;
  late final MasteringProcessOfflineDart _masteringProcessOffline;
  late final MasteringGetResultDart _masteringGetResult;
  late final MasteringGetWarningDart _masteringGetWarning;
  late final MasteringGetChainSummaryDart _masteringGetChainSummary;
  late final MasteringResetDart _masteringReset;
  late final MasteringSetActiveDart _masteringSetActive;
  late final MasteringGetGainReductionDart _masteringGetGainReduction;
  late final MasteringGetDetectedGenreDart _masteringGetDetectedGenre;
  late final MasteringGetLatencyDart _masteringGetLatency;

  // Restoration functions
  late final RestorationInitDart _restorationInit;
  late final RestorationSetSettingsDart _restorationSetSettings;
  late final RestorationGetSettingsDart _restorationGetSettings;
  late final RestorationAnalyzeDart _restorationAnalyze;
  late final RestorationGetSuggestionCountDart _restorationGetSuggestionCount;
  late final RestorationGetSuggestionDart _restorationGetSuggestion;
  late final RestorationProcessDart _restorationProcess;
  late final RestorationProcessFileDart _restorationProcessFile;
  late final RestorationLearnNoiseProfileDart _restorationLearnNoiseProfile;
  late final RestorationClearNoiseProfileDart _restorationClearNoiseProfile;
  late final RestorationGetStateDart _restorationGetState;
  late final RestorationGetPhaseDart _restorationGetPhase;
  late final RestorationSetActiveDart _restorationSetActive;
  late final RestorationGetLatencyDart _restorationGetLatency;
  late final RestorationResetDart _restorationReset;

  // ML/AI functions
  late final MlInitDart _mlInit;
  late final MlGetModelCountDart _mlGetModelCount;
  late final MlGetModelNameDart _mlGetModelName;
  late final MlModelIsAvailableDart _mlModelIsAvailable;
  late final MlGetModelSizeDart _mlGetModelSize;
  late final MlDenoiseStartDart _mlDenoiseStart;
  late final MlSeparateStartDart _mlSeparateStart;
  late final MlEnhanceVoiceStartDart _mlEnhanceVoiceStart;
  late final MlGetProgressDart _mlGetProgress;
  late final MlIsProcessingDart _mlIsProcessing;
  late final MlGetPhaseDart _mlGetPhase;
  late final MlGetCurrentModelDart _mlGetCurrentModel;
  late final MlCancelDart _mlCancel;
  late final MlSetExecutionProviderDart _mlSetExecutionProvider;
  late final MlGetErrorDart _mlGetError;
  late final MlResetDart _mlReset;

  // Lua Scripting functions
  late final ScriptInitDart _scriptInit;
  late final ScriptShutdownDart _scriptShutdown;
  late final ScriptIsInitializedDart _scriptIsInitialized;
  late final ScriptExecuteDart _scriptExecute;
  late final ScriptExecuteFileDart _scriptExecuteFile;
  late final ScriptLoadFileDart _scriptLoadFile;
  late final ScriptRunDart _scriptRun;
  late final ScriptGetOutputDart _scriptGetOutput;
  late final ScriptGetErrorDart _scriptGetError;
  late final ScriptGetDurationDart _scriptGetDuration;
  late final ScriptPollActionsDart _scriptPollActions;
  late final ScriptGetNextActionDart _scriptGetNextAction;
  late final ScriptSetContextDart _scriptSetContext;
  late final ScriptSetSelectedTracksDart _scriptSetSelectedTracks;
  late final ScriptSetSelectedClipsDart _scriptSetSelectedClips;
  late final ScriptAddSearchPathDart _scriptAddSearchPath;
  late final ScriptGetLoadedCountDart _scriptGetLoadedCount;
  late final ScriptGetNameDart _scriptGetName;
  late final ScriptGetDescriptionDart _scriptGetDescription;

  // Plugin Hosting functions
  late final PluginHostInitDart _pluginHostInit;
  late final PluginScanAllDart _pluginScanAll;
  late final PluginGetCountDart _pluginGetCount;
  late final PluginGetAllJsonDart _pluginGetAllJson;
  late final PluginGetInfoJsonDart _pluginGetInfoJson;
  late final PluginLoadDart _pluginLoad;
  late final PluginUnloadDart _pluginUnload;
  late final PluginActivateDart _pluginActivate;
  late final PluginDeactivateDart _pluginDeactivate;
  late final PluginGetParamCountDart _pluginGetParamCount;
  late final PluginGetParamDart _pluginGetParam;
  late final PluginSetParamDart _pluginSetParam;
  late final PluginGetAllParamsJsonDart _pluginGetAllParamsJson;
  late final PluginHasEditorDart _pluginHasEditor;
  late final PluginGetLatencyDart _pluginGetLatency;
  late final PluginOpenEditorDart _pluginOpenEditor;
  late final PluginCloseEditorDart _pluginCloseEditor;
  late final PluginEditorSizeDart _pluginEditorSize;
  late final PluginResizeEditorDart _pluginResizeEditor;
  late final PluginSearchDart _pluginSearch;
  late final PluginGetByTypeDart _pluginGetByType;
  late final PluginGetByCategoryDart _pluginGetByCategory;
  late final PluginGetInstancesJsonDart _pluginGetInstancesJson;

  // Plugin insert chain
  late final PluginInsertLoadDart _pluginInsertLoad;
  late final PluginInsertRemoveDart _pluginInsertRemove;
  late final PluginInsertSetBypassDart _pluginInsertSetBypass;
  late final PluginInsertSetMixDart _pluginInsertSetMix;
  late final PluginInsertGetMixDart _pluginInsertGetMix;
  late final PluginInsertGetLatencyDart _pluginInsertGetLatency;
  late final PluginInsertChainLatencyDart _pluginInsertChainLatency;

  // MIDI I/O
  late final MidiScanInputDevicesDart _midiScanInputDevices;
  late final MidiScanOutputDevicesDart _midiScanOutputDevices;
  late final MidiGetInputDeviceNameDart _midiGetInputDeviceName;
  late final MidiGetOutputDeviceNameDart _midiGetOutputDeviceName;
  late final MidiInputDeviceCountDart _midiInputDeviceCount;
  late final MidiOutputDeviceCountDart _midiOutputDeviceCount;
  late final MidiConnectInputDart _midiConnectInput;
  late final MidiDisconnectInputDart _midiDisconnectInput;
  late final MidiDisconnectAllInputsDart _midiDisconnectAllInputs;
  late final MidiActiveInputCountDart _midiActiveInputCount;
  late final MidiConnectOutputDart _midiConnectOutput;
  late final MidiDisconnectOutputDart _midiDisconnectOutput;
  late final MidiIsOutputConnectedDart _midiIsOutputConnected;
  late final MidiStartRecordingDart _midiStartRecording;
  late final MidiStopRecordingDart _midiStopRecording;
  late final MidiArmTrackDart _midiArmTrack;
  late final MidiIsRecordingDart _midiIsRecording;
  late final MidiGetRecordingStateDart _midiGetRecordingState;
  late final MidiRecordedEventCountDart _midiRecordedEventCount;
  late final MidiGetTargetTrackDart _midiGetTargetTrack;
  late final MidiSetSampleRateDart _midiSetSampleRate;
  late final MidiSetThruDart _midiSetThru;
  late final MidiIsThruEnabledDart _midiIsThruEnabled;
  late final MidiSendNoteOnDart _midiSendNoteOn;
  late final MidiSendNoteOffDart _midiSendNoteOff;
  late final MidiSendCcDart _midiSendCc;
  late final MidiSendPitchBendDart _midiSendPitchBend;
  late final MidiSendProgramChangeDart _midiSendProgramChange;

  // Autosave System
  late final AutosaveInitDart _autosaveInit;
  late final AutosaveShutdownDart _autosaveShutdown;
  late final AutosaveSetEnabledDart _autosaveSetEnabled;
  late final AutosaveIsEnabledDart _autosaveIsEnabled;
  late final AutosaveSetIntervalDart _autosaveSetInterval;
  late final AutosaveGetIntervalDart _autosaveGetInterval;
  late final AutosaveSetBackupCountDart _autosaveSetBackupCount;
  late final AutosaveGetBackupCountDart _autosaveGetBackupCount;
  late final AutosaveMarkDirtyDart _autosaveMarkDirty;
  late final AutosaveMarkCleanDart _autosaveMarkClean;
  late final AutosaveIsDirtyDart _autosaveIsDirty;
  late final AutosaveShouldSaveDart _autosaveShouldSave;
  late final AutosaveNowDart _autosaveNow;
  late final AutosaveBackupCountDart _autosaveBackupCount;
  late final AutosaveLatestPathDart _autosaveLatestPath;
  late final AutosaveClearBackupsDart _autosaveClearBackups;

  // Recent Projects
  late final RecentProjectsAddDart _recentProjectsAdd;
  late final RecentProjectsCountDart _recentProjectsCount;
  late final RecentProjectsGetDart _recentProjectsGet;
  late final RecentProjectsRemoveDart _recentProjectsRemove;
  late final RecentProjectsClearDart _recentProjectsClear;

  // Middleware Event System
  late final MiddlewareInitDart _middlewareInit;
  late final MiddlewareShutdownDart _middlewareShutdown;
  late final MiddlewareIsInitializedDart _middlewareIsInitialized;
  late final MiddlewareRegisterEventDart _middlewareRegisterEvent;
  late final MiddlewareAddActionDart _middlewareAddAction;
  late final MiddlewarePostEventDart _middlewarePostEvent;
  late final MiddlewarePostEventByNameDart _middlewarePostEventByName;
  late final MiddlewareStopPlayingIdDart _middlewareStopPlayingId;
  late final MiddlewareStopEventDart _middlewareStopEvent;
  late final MiddlewareStopAllDart _middlewareStopAll;
  late final MiddlewareRegisterStateGroupDart _middlewareRegisterStateGroup;
  late final MiddlewareAddStateDart _middlewareAddState;
  late final MiddlewareSetStateDart _middlewareSetState;
  late final MiddlewareGetStateDart _middlewareGetState;
  late final MiddlewareRegisterSwitchGroupDart _middlewareRegisterSwitchGroup;
  late final MiddlewareAddSwitchDart _middlewareAddSwitch;
  late final MiddlewareSetSwitchDart _middlewareSetSwitch;
  late final MiddlewareRegisterRtpcDart _middlewareRegisterRtpc;
  late final MiddlewareSetRtpcDart _middlewareSetRtpc;
  late final MiddlewareSetRtpcOnObjectDart _middlewareSetRtpcOnObject;
  late final MiddlewareGetRtpcDart _middlewareGetRtpc;
  late final MiddlewareResetRtpcDart _middlewareResetRtpc;
  late final MiddlewareRegisterGameObjectDart _middlewareRegisterGameObject;
  late final MiddlewareUnregisterGameObjectDart _middlewareUnregisterGameObject;
  late final MiddlewareGetEventCountDart _middlewareGetEventCount;
  late final MiddlewareGetStateGroupCountDart _middlewareGetStateGroupCount;
  late final MiddlewareGetSwitchGroupCountDart _middlewareGetSwitchGroupCount;
  late final MiddlewareGetRtpcCountDart _middlewareGetRtpcCount;
  late final MiddlewareGetActiveInstanceCountDart _middlewareGetActiveInstanceCount;

  // Stage System
  late final StageParseJsonDart _stageParseJson;
  late final StageGetTraceJsonDart _stageGetTraceJson;
  late final StageGetEventCountDart _stageGetEventCount;
  late final StageGetEventJsonDart _stageGetEventJson;
  late final StageResolveTimingDart _stageResolveTiming;
  late final StageGetTimedTraceJsonDart _stageGetTimedTraceJson;
  late final StageGetDurationMsDart _stageGetDurationMs;
  late final StageGetEventsAtTimeDart _stageGetEventsAtTime;
  late final WizardAnalyzeJsonDart _wizardAnalyzeJson;
  late final WizardGetConfidenceDart _wizardGetConfidence;
  late final WizardGetRecommendedLayerDart _wizardGetRecommendedLayer;
  late final WizardGetDetectedCompanyDart _wizardGetDetectedCompany;
  late final WizardGetDetectedEngineDart _wizardGetDetectedEngine;
  late final WizardGetConfigTomlDart _wizardGetConfigToml;
  late final WizardGetDetectedEventCountDart _wizardGetDetectedEventCount;
  late final WizardGetDetectedEventJsonDart _wizardGetDetectedEventJson;
  late final AdapterLoadConfigDart _adapterLoadConfig;
  late final AdapterGetCountDart _adapterGetCount;
  late final AdapterGetIdAtDart _adapterGetIdAt;
  late final AdapterGetInfoJsonDart _adapterGetInfoJson;

  NativeFFI._();

  /// Try to load the native library
  /// Returns true if successful, false if not available
  bool tryLoad() {
    if (_loaded) return true;

    try {
      _lib = _loadNativeLibrary();
      _bindFunctions();
      _loaded = true;
      return true;
    } catch (e) {
      print('[NativeFFI] Failed to load native library: $e');
      return false;
    }
  }

  /// Check if native library is loaded
  bool get isLoaded => _loaded;

  void _bindFunctions() {
    _createTrack = _lib.lookupFunction<EngineCreateTrackNative, EngineCreateTrackDart>('engine_create_track');
    _deleteTrack = _lib.lookupFunction<EngineDeleteTrackNative, EngineDeleteTrackDart>('engine_delete_track');
    _setTrackName = _lib.lookupFunction<EngineSetTrackNameNative, EngineSetTrackNameDart>('engine_set_track_name');
    _setTrackMute = _lib.lookupFunction<EngineSetTrackMuteNative, EngineSetTrackMuteDart>('engine_set_track_mute');
    _setTrackSolo = _lib.lookupFunction<EngineSetTrackSoloNative, EngineSetTrackSoloDart>('engine_set_track_solo');
    _isSoloActive = _lib.lookupFunction<EngineIsSoloActiveNative, EngineIsSoloActiveDart>('engine_is_solo_active');
    _clearAllSolos = _lib.lookupFunction<EngineClearAllSolosNative, EngineClearAllSolosDart>('engine_clear_all_solos');
    _setTrackArmed = _lib.lookupFunction<EngineSetTrackArmedNative, EngineSetTrackArmedDart>('engine_set_track_armed');
    _setTrackVolume = _lib.lookupFunction<EngineSetTrackVolumeNative, EngineSetTrackVolumeDart>('engine_set_track_volume');
    _setTrackPan = _lib.lookupFunction<EngineSetTrackPanNative, EngineSetTrackPanDart>('engine_set_track_pan');
    _setTrackPanRight = _lib.lookupFunction<EngineSetTrackPanRightNative, EngineSetTrackPanRightDart>('engine_set_track_pan_right');
    _getTrackChannels = _lib.lookupFunction<EngineGetTrackChannelsNative, EngineGetTrackChannelsDart>('engine_get_track_channels');
    _setTrackChannels = _lib.lookupFunction<EngineSetTrackChannelsNative, EngineSetTrackChannelsDart>('engine_set_track_channels');
    _setTrackBus = _lib.lookupFunction<EngineSetTrackBusNative, EngineSetTrackBusDart>('engine_set_track_bus');
    _getTrackCount = _lib.lookupFunction<EngineGetTrackCountNative, EngineGetTrackCountDart>('engine_get_track_count');
    _getTrackPeak = _lib.lookupFunction<EngineGetTrackPeakNative, EngineGetTrackPeakDart>('engine_get_track_peak');
    _getTrackPeakStereo = _lib.lookupFunction<EngineGetTrackPeakStereoNative, EngineGetTrackPeakStereoDart>('engine_get_track_peak_stereo');
    _getTrackRmsStereo = _lib.lookupFunction<EngineGetTrackRmsStereoNative, EngineGetTrackRmsStereoDart>('engine_get_track_rms_stereo');
    _getTrackCorrelation = _lib.lookupFunction<EngineGetTrackCorrelationNative, EngineGetTrackCorrelationDart>('engine_get_track_correlation');
    _getTrackMeter = _lib.lookupFunction<EngineGetTrackMeterNative, EngineGetTrackMeterDart>('engine_get_track_meter');
    _getAllTrackPeaks = _lib.lookupFunction<EngineGetAllTrackPeaksNative, EngineGetAllTrackPeaksDart>('engine_get_all_track_peaks');
    _getAllTrackMeters = _lib.lookupFunction<EngineGetAllTrackMetersNative, EngineGetAllTrackMetersDart>('engine_get_all_track_meters');

    _importAudio = _lib.lookupFunction<EngineImportAudioNative, EngineImportAudioDart>('engine_import_audio');

    _addClip = _lib.lookupFunction<EngineAddClipNative, EngineAddClipDart>('engine_add_clip');
    _moveClip = _lib.lookupFunction<EngineMoveClipNative, EngineMoveClipDart>('engine_move_clip');
    _resizeClip = _lib.lookupFunction<EngineResizeClipNative, EngineResizeClipDart>('engine_resize_clip');
    _splitClip = _lib.lookupFunction<EngineSplitClipNative, EngineSplitClipDart>('engine_split_clip');
    _duplicateClip = _lib.lookupFunction<EngineDuplicateClipNative, EngineDuplicateClipDart>('engine_duplicate_clip');
    _deleteClip = _lib.lookupFunction<EngineDeleteClipNative, EngineDeleteClipDart>('engine_delete_clip');
    _setClipGain = _lib.lookupFunction<EngineSetClipGainNative, EngineSetClipGainDart>('engine_set_clip_gain');
    _setClipMuted = _lib.lookupFunction<EngineSetClipMutedNative, EngineSetClipMutedDart>('engine_set_clip_muted');
    _getClipDuration = _lib.lookupFunction<EngineGetClipDurationNative, EngineGetClipDurationDart>('engine_get_clip_duration');
    _getClipSourceDuration = _lib.lookupFunction<EngineGetClipSourceDurationNative, EngineGetClipSourceDurationDart>('engine_get_clip_source_duration');
    _getAudioFileDuration = _lib.lookupFunction<EngineGetAudioFileDurationNative, EngineGetAudioFileDurationDart>('engine_get_audio_file_duration');

    _getWaveformPeaks = _lib.lookupFunction<EngineGetWaveformPeaksNative, EngineGetWaveformPeaksDart>('engine_get_waveform_peaks');
    _getWaveformLodLevels = _lib.lookupFunction<EngineGetWaveformLodLevelsNative, EngineGetWaveformLodLevelsDart>('engine_get_waveform_lod_levels');
    _queryWaveformPixels = _lib.lookupFunction<EngineQueryWaveformPixelsNative, EngineQueryWaveformPixelsDart>('engine_query_waveform_pixels');
    _queryWaveformPixelsStereo = _lib.lookupFunction<EngineQueryWaveformPixelsStereoNative, EngineQueryWaveformPixelsStereoDart>('engine_query_waveform_pixels_stereo');
    _getWaveformSampleRate = _lib.lookupFunction<EngineGetWaveformSampleRateNative, EngineGetWaveformSampleRateDart>('engine_get_waveform_sample_rate');
    _getWaveformTotalSamples = _lib.lookupFunction<EngineGetWaveformTotalSamplesNative, EngineGetWaveformTotalSamplesDart>('engine_get_waveform_total_samples');
    _queryWaveformTilesBatch = _lib.lookupFunction<EngineQueryWaveformTilesBatchNative, EngineQueryWaveformTilesBatchDart>('engine_query_waveform_tiles_batch');
    _queryRawSamples = _lib.lookupFunction<EngineQueryRawSamplesNative, EngineQueryRawSamplesDart>('engine_query_raw_samples');

    _setLoopRegion = _lib.lookupFunction<EngineSetLoopRegionNative, EngineSetLoopRegionDart>('engine_set_loop_region');
    _setLoopEnabled = _lib.lookupFunction<EngineSetLoopEnabledNative, EngineSetLoopEnabledDart>('engine_set_loop_enabled');

    _addMarker = _lib.lookupFunction<EngineAddMarkerNative, EngineAddMarkerDart>('engine_add_marker');
    _deleteMarker = _lib.lookupFunction<EngineDeleteMarkerNative, EngineDeleteMarkerDart>('engine_delete_marker');

    _createCrossfade = _lib.lookupFunction<EngineCreateCrossfadeNative, EngineCreateCrossfadeDart>('engine_create_crossfade');
    _deleteCrossfade = _lib.lookupFunction<EngineDeleteCrossfadeNative, EngineDeleteCrossfadeDart>('engine_delete_crossfade');
    _updateCrossfade = _lib.lookupFunction<EngineUpdateCrossfadeNative, EngineUpdateCrossfadeDart>('engine_update_crossfade');

    _freeString = _lib.lookupFunction<EngineFreeStringNative, EngineFreeStringDart>('engine_free_string');
    _clearAll = _lib.lookupFunction<EngineClearAllNative, EngineClearAllDart>('engine_clear_all');

    _snapToGrid = _lib.lookupFunction<EngineSnapToGridNative, EngineSnapToGridDart>('engine_snap_to_grid');
    _snapToEvent = _lib.lookupFunction<EngineSnapToEventNative, EngineSnapToEventDart>('engine_snap_to_event');

    // Transport
    _play = _lib.lookupFunction<EnginePlayNative, EnginePlayDart>('engine_play');
    _pause = _lib.lookupFunction<EnginePauseNative, EnginePauseDart>('engine_pause');
    _stop = _lib.lookupFunction<EngineStopNative, EngineStopDart>('engine_stop');
    _seek = _lib.lookupFunction<EngineSeekNative, EngineSeekDart>('engine_seek');
    _startScrub = _lib.lookupFunction<EngineStartScrubNative, EngineStartScrubDart>('engine_start_scrub');
    _updateScrub = _lib.lookupFunction<EngineUpdateScrubNative, EngineUpdateScrubDart>('engine_update_scrub');
    _stopScrub = _lib.lookupFunction<EngineStopScrubNative, EngineStopScrubDart>('engine_stop_scrub');
    _isScrubbing = _lib.lookupFunction<EngineIsScrubbingNative, EngineIsScrubbingDart>('engine_is_scrubbing');
    _setScrubWindowMs = _lib.lookupFunction<EngineSetScrubWindowMsNative, EngineSetScrubWindowMsDart>('engine_set_scrub_window_ms');
    _getPosition = _lib.lookupFunction<EngineGetPositionNative, EngineGetPositionDart>('engine_get_position');
    _getPlaybackState = _lib.lookupFunction<EngineGetPlaybackStateNative, EngineGetPlaybackStateDart>('engine_get_playback_state');
    _isPlaying = _lib.lookupFunction<EngineIsPlayingNative, EngineIsPlayingDart>('engine_is_playing');
    _setMasterVolume = _lib.lookupFunction<EngineSetMasterVolumeNative, EngineSetMasterVolumeDart>('engine_set_master_volume');
    _getMasterVolume = _lib.lookupFunction<EngineGetMasterVolumeNative, EngineGetMasterVolumeDart>('engine_get_master_volume');

    // Varispeed
    _setVarispeedEnabled = _lib.lookupFunction<EngineSetVarispeedEnabledNative, EngineSetVarispeedEnabledDart>('engine_set_varispeed_enabled');
    _isVarispeedEnabled = _lib.lookupFunction<EngineIsVarispeedEnabledNative, EngineIsVarispeedEnabledDart>('engine_is_varispeed_enabled');
    _setVarispeedRate = _lib.lookupFunction<EngineSetVarispeedRateNative, EngineSetVarispeedRateDart>('engine_set_varispeed_rate');
    _getVarispeedRate = _lib.lookupFunction<EngineGetVarispeedRateNative, EngineGetVarispeedRateDart>('engine_get_varispeed_rate');
    _setVarispeedSemitones = _lib.lookupFunction<EngineSetVarispeedSemitonesNative, EngineSetVarispeedSemitonesDart>('engine_set_varispeed_semitones');
    _getVarispeedSemitones = _lib.lookupFunction<EngineGetVarispeedSemitonesNative, EngineGetVarispeedSemitonesDart>('engine_get_varispeed_semitones');
    _getEffectivePlaybackRate = _lib.lookupFunction<EngineGetEffectivePlaybackRateNative, EngineGetEffectivePlaybackRateDart>('engine_get_effective_playback_rate');

    _getPlaybackPositionSeconds = _lib.lookupFunction<EngineGetPlaybackPositionSecondsNative, EngineGetPlaybackPositionSecondsDart>('engine_get_playback_position_seconds');
    _getPlaybackPositionSamples = _lib.lookupFunction<EngineGetPlaybackPositionSamplesNative, EngineGetPlaybackPositionSamplesDart>('engine_get_playback_position_samples');
    _preloadAll = _lib.lookupFunction<EnginePreloadAllNative, EnginePreloadAllDart>('engine_preload_all');
    _preloadRange = _lib.lookupFunction<EnginePreloadRangeNative, EnginePreloadRangeDart>('engine_preload_range');
    _syncLoopFromRegion = _lib.lookupFunction<EngineSyncLoopFromRegionNative, EngineSyncLoopFromRegionDart>('engine_sync_loop_from_region');
    _getSampleRate = _lib.lookupFunction<EngineGetSampleRateNative, EngineGetSampleRateDart>('engine_get_sample_rate');

    // Audio stream control
    _startPlayback = _lib.lookupFunction<EngineStartPlaybackNative, EngineStartPlaybackDart>('engine_start_playback');
    _stopPlayback = _lib.lookupFunction<EngineStopPlaybackNative, EngineStopPlaybackDart>('engine_stop_playback');

    // Undo/Redo
    _undo = _lib.lookupFunction<EngineUndoNative, EngineUndoDart>('engine_undo');
    _redo = _lib.lookupFunction<EngineRedoNative, EngineRedoDart>('engine_redo');
    _canUndo = _lib.lookupFunction<EngineCanUndoNative, EngineCanUndoDart>('engine_can_undo');
    _canRedo = _lib.lookupFunction<EngineCanRedoNative, EngineCanRedoDart>('engine_can_redo');

    // Project
    _saveProject = _lib.lookupFunction<EngineSaveProjectNative, EngineSaveProjectDart>('engine_save_project');
    _loadProject = _lib.lookupFunction<EngineLoadProjectNative, EngineLoadProjectDart>('engine_load_project');
    _isProjectModified = _lib.lookupFunction<EngineIsProjectModifiedNative, EngineIsProjectModifiedDart>('engine_project_is_modified');
    _markProjectDirty = _lib.lookupFunction<EngineMarkProjectDirtyNative, EngineMarkProjectDirtyDart>('engine_project_mark_dirty');
    _markProjectClean = _lib.lookupFunction<EngineMarkProjectCleanNative, EngineMarkProjectCleanDart>('engine_project_mark_clean');
    _setProjectFilePath = _lib.lookupFunction<EngineSetProjectFilePathNative, EngineSetProjectFilePathDart>('engine_project_set_file_path');
    _getProjectFilePath = _lib.lookupFunction<EngineGetProjectFilePathNative, EngineGetProjectFilePathDart>('engine_project_get_file_path');

    // Memory
    _getMemoryUsage = _lib.lookupFunction<EngineGetMemoryUsageNative, EngineGetMemoryUsageDart>('engine_get_memory_usage');

    // Metering
    _getPeakMeters = _lib.lookupFunction<EngineGetPeakMetersNative, EngineGetPeakMetersDart>('engine_get_peak_meters');
    _getRmsMeters = _lib.lookupFunction<EngineGetRmsMetersNative, EngineGetRmsMetersDart>('engine_get_rms_meters');
    _getLufsMeters = _lib.lookupFunction<EngineGetLufsMetersNative, EngineGetLufsMetersDart>('engine_get_lufs_meters');
    _getTruePeakMeters = _lib.lookupFunction<EngineGetTruePeakMetersNative, EngineGetTruePeakMetersDart>('engine_get_true_peak_meters');
    _getCorrelation = _lib.lookupFunction<EngineGetCorrelationNative, EngineGetCorrelationDart>('metering_get_master_correlation');
    _getStereoBalance = _lib.lookupFunction<EngineGetStereoBalanceNative, EngineGetStereoBalanceDart>('metering_get_master_balance');
    _getDynamicRange = _lib.lookupFunction<EngineGetDynamicRangeNative, EngineGetDynamicRangeDart>('metering_get_master_dynamic_range');
    _getMasterSpectrum = _lib.lookupFunction<EngineGetMasterSpectrumNative, EngineGetMasterSpectrumDart>('metering_get_master_spectrum');

    // EQ
    _eqSetBandEnabled = _lib.lookupFunction<EngineEqSetBandEnabledNative, EngineEqSetBandEnabledDart>('eq_set_band_enabled');
    _eqSetBandFrequency = _lib.lookupFunction<EngineEqSetBandFrequencyNative, EngineEqSetBandFrequencyDart>('eq_set_band_frequency');
    _eqSetBandGain = _lib.lookupFunction<EngineEqSetBandGainNative, EngineEqSetBandGainDart>('eq_set_band_gain');
    _eqSetBandQ = _lib.lookupFunction<EngineEqSetBandQNative, EngineEqSetBandQDart>('eq_set_band_q');
    _eqSetBandShape = _lib.lookupFunction<EngineEqSetBandShapeNative, EngineEqSetBandShapeDart>('eq_set_band_shape');
    _eqSetBypass = _lib.lookupFunction<EngineEqSetBypassNative, EngineEqSetBypassDart>('eq_set_bypass');

    // Mixer buses
    _mixerSetBusVolume = _lib.lookupFunction<EngineMixerSetBusVolumeNative, EngineMixerSetBusVolumeDart>('mixer_set_bus_volume');
    _mixerSetBusMute = _lib.lookupFunction<EngineMixerSetBusMuteNative, EngineMixerSetBusMuteDart>('mixer_set_bus_mute');
    _mixerSetBusSolo = _lib.lookupFunction<EngineMixerSetBusSoloNative, EngineMixerSetBusSoloDart>('mixer_set_bus_solo');
    _mixerSetBusPan = _lib.lookupFunction<EngineMixerSetBusPanNative, EngineMixerSetBusPanDart>('mixer_set_bus_pan');
    _mixerSetMasterVolume = _lib.lookupFunction<EngineMixerSetMasterVolumeNative, EngineMixerSetMasterVolumeDart>('mixer_set_master_volume');

    // Audio processing
    _clipNormalize = _lib.lookupFunction<EngineClipNormalizeNative, EngineClipNormalizeDart>('clip_normalize');
    _clipReverse = _lib.lookupFunction<EngineClipReverseNative, EngineClipReverseDart>('clip_reverse');
    _clipFadeIn = _lib.lookupFunction<EngineClipFadeInNative, EngineClipFadeInDart>('clip_fade_in');
    _clipFadeOut = _lib.lookupFunction<EngineClipFadeOutNative, EngineClipFadeOutDart>('clip_fade_out');
    _clipApplyGain = _lib.lookupFunction<EngineClipApplyGainNative, EngineClipApplyGainDart>('clip_apply_gain');

    // Track management
    _trackRename = _lib.lookupFunction<EngineTrackRenameNative, EngineTrackRenameDart>('track_rename');
    _trackDuplicate = _lib.lookupFunction<EngineTrackDuplicateNative, EngineTrackDuplicateDart>('track_duplicate');
    _trackSetColor = _lib.lookupFunction<EngineTrackSetColorNative, EngineTrackSetColorDart>('track_set_color');

    // VCA
    _vcaCreate = _lib.lookupFunction<EngineVcaCreateNative, EngineVcaCreateDart>('vca_create');
    _vcaDelete = _lib.lookupFunction<EngineVcaDeleteNative, EngineVcaDeleteDart>('vca_delete');
    _vcaSetLevel = _lib.lookupFunction<EngineVcaSetLevelNative, EngineVcaSetLevelDart>('vca_set_level');
    _vcaGetLevel = _lib.lookupFunction<EngineVcaGetLevelNative, EngineVcaGetLevelDart>('vca_get_level');
    _vcaSetMute = _lib.lookupFunction<EngineVcaSetMuteNative, EngineVcaSetMuteDart>('vca_set_mute');
    _vcaAssignTrack = _lib.lookupFunction<EngineVcaAssignTrackNative, EngineVcaAssignTrackDart>('vca_add_track');
    _vcaRemoveTrack = _lib.lookupFunction<EngineVcaRemoveTrackNative, EngineVcaRemoveTrackDart>('vca_remove_track');
    _vcaGetTrackEffectiveVolume = _lib.lookupFunction<EngineVcaGetTrackEffectiveVolumeNative, EngineVcaGetTrackEffectiveVolumeDart>('vca_get_track_contribution');

    // Group
    _groupCreate = _lib.lookupFunction<EngineGroupCreateNative, EngineGroupCreateDart>('group_create');
    _groupDelete = _lib.lookupFunction<EngineGroupDeleteNative, EngineGroupDeleteDart>('group_delete');
    _groupAddTrack = _lib.lookupFunction<EngineGroupAddTrackNative, EngineGroupAddTrackDart>('group_add_track');
    _groupRemoveTrack = _lib.lookupFunction<EngineGroupRemoveTrackNative, EngineGroupRemoveTrackDart>('group_remove_track');
    _groupSetLinkMode = _lib.lookupFunction<EngineGroupSetLinkModeNative, EngineGroupSetLinkModeDart>('group_set_link_mode');

    // Clip FX
    _clipFxAdd = _lib.lookupFunction<ClipFxAddNative, ClipFxAddDart>('clip_fx_add');
    _clipFxRemove = _lib.lookupFunction<ClipFxRemoveNative, ClipFxRemoveDart>('clip_fx_remove');
    _clipFxMove = _lib.lookupFunction<ClipFxMoveNative, ClipFxMoveDart>('clip_fx_move');
    _clipFxSetBypass = _lib.lookupFunction<ClipFxSetBypassNative, ClipFxSetBypassDart>('clip_fx_set_bypass');
    _clipFxSetChainBypass = _lib.lookupFunction<ClipFxSetChainBypassNative, ClipFxSetChainBypassDart>('clip_fx_set_chain_bypass');
    _clipFxSetWetDry = _lib.lookupFunction<ClipFxSetWetDryNative, ClipFxSetWetDryDart>('clip_fx_set_wet_dry');
    _clipFxSetInputGain = _lib.lookupFunction<ClipFxSetInputGainNative, ClipFxSetInputGainDart>('clip_fx_set_input_gain');
    _clipFxSetOutputGain = _lib.lookupFunction<ClipFxSetOutputGainNative, ClipFxSetOutputGainDart>('clip_fx_set_output_gain');
    _clipFxSetGainParams = _lib.lookupFunction<ClipFxSetGainParamsNative, ClipFxSetGainParamsDart>('clip_fx_set_gain_params');
    _clipFxSetCompressorParams = _lib.lookupFunction<ClipFxSetCompressorParamsNative, ClipFxSetCompressorParamsDart>('clip_fx_set_compressor_params');
    _clipFxSetLimiterParams = _lib.lookupFunction<ClipFxSetLimiterParamsNative, ClipFxSetLimiterParamsDart>('clip_fx_set_limiter_params');
    _clipFxSetGateParams = _lib.lookupFunction<ClipFxSetGateParamsNative, ClipFxSetGateParamsDart>('clip_fx_set_gate_params');
    _clipFxSetSaturationParams = _lib.lookupFunction<ClipFxSetSaturationParamsNative, ClipFxSetSaturationParamsDart>('clip_fx_set_saturation_params');
    _clipFxCopy = _lib.lookupFunction<ClipFxCopyNative, ClipFxCopyDart>('clip_fx_copy');
    _clipFxClear = _lib.lookupFunction<ClipFxClearNative, ClipFxClearDart>('clip_fx_clear');

    // Click track
    _clickSetEnabled = _lib.lookupFunction<ClickSetEnabledNative, ClickSetEnabledDart>('click_set_enabled');
    _clickIsEnabled = _lib.lookupFunction<ClickIsEnabledNative, ClickIsEnabledDart>('click_is_enabled');
    _clickSetVolume = _lib.lookupFunction<ClickSetVolumeNative, ClickSetVolumeDart>('click_set_volume');
    _clickSetPattern = _lib.lookupFunction<ClickSetPatternNative, ClickSetPatternDart>('click_set_pattern');
    _clickSetCountIn = _lib.lookupFunction<ClickSetCountInNative, ClickSetCountInDart>('click_set_count_in');
    _clickSetPan = _lib.lookupFunction<ClickSetPanNative, ClickSetPanDart>('click_set_pan');

    // Send functions
    _sendSetLevel = _lib.lookupFunction<SendSetLevelNative, SendSetLevelDart>('send_set_level');
    _sendSetLevelDb = _lib.lookupFunction<SendSetLevelDbNative, SendSetLevelDbDart>('send_set_level_db');
    _sendSetDestination = _lib.lookupFunction<SendSetDestinationNative, SendSetDestinationDart>('send_set_destination');
    _sendSetPan = _lib.lookupFunction<SendSetPanNative, SendSetPanDart>('send_set_pan');
    _sendSetEnabled = _lib.lookupFunction<SendSetEnabledNative, SendSetEnabledDart>('send_set_enabled');
    _sendSetMuted = _lib.lookupFunction<SendSetMutedNative, SendSetMutedDart>('send_set_muted');
    _sendSetTapPoint = _lib.lookupFunction<SendSetTapPointNative, SendSetTapPointDart>('send_set_tap_point');
    _sendCreateBank = _lib.lookupFunction<SendCreateBankNative, SendCreateBankDart>('send_create_bank');
    _sendRemoveBank = _lib.lookupFunction<SendRemoveBankNative, SendRemoveBankDart>('send_remove_bank');

    // Return bus functions
    _returnSetLevel = _lib.lookupFunction<ReturnSetLevelNative, ReturnSetLevelDart>('return_set_level');
    _returnSetLevelDb = _lib.lookupFunction<ReturnSetLevelDbNative, ReturnSetLevelDbDart>('return_set_level_db');
    _returnSetPan = _lib.lookupFunction<ReturnSetPanNative, ReturnSetPanDart>('return_set_pan');
    _returnSetMuted = _lib.lookupFunction<ReturnSetMutedNative, ReturnSetMutedDart>('return_set_muted');
    _returnSetSolo = _lib.lookupFunction<ReturnSetSoloNative, ReturnSetSoloDart>('return_set_solo');

    // Sidechain functions
    _sidechainAddRoute = _lib.lookupFunction<SidechainAddRouteNative, SidechainAddRouteDart>('sidechain_add_route');
    _sidechainRemoveRoute = _lib.lookupFunction<SidechainRemoveRouteNative, SidechainRemoveRouteDart>('sidechain_remove_route');
    _sidechainCreateInput = _lib.lookupFunction<SidechainCreateInputNative, SidechainCreateInputDart>('sidechain_create_input');
    _sidechainRemoveInput = _lib.lookupFunction<SidechainRemoveInputNative, SidechainRemoveInputDart>('sidechain_remove_input');
    _sidechainSetSource = _lib.lookupFunction<SidechainSetSourceNative, SidechainSetSourceDart>('sidechain_set_source');
    _sidechainSetFilterMode = _lib.lookupFunction<SidechainSetFilterModeNative, SidechainSetFilterModeDart>('sidechain_set_filter_mode');
    _sidechainSetFilterFreq = _lib.lookupFunction<SidechainSetFilterFreqNative, SidechainSetFilterFreqDart>('sidechain_set_filter_freq');
    _sidechainSetFilterQ = _lib.lookupFunction<SidechainSetFilterQNative, SidechainSetFilterQDart>('sidechain_set_filter_q');
    _sidechainSetMix = _lib.lookupFunction<SidechainSetMixNative, SidechainSetMixDart>('sidechain_set_mix');
    _sidechainSetGainDb = _lib.lookupFunction<SidechainSetGainDbNative, SidechainSetGainDbDart>('sidechain_set_gain_db');
    _sidechainSetMonitor = _lib.lookupFunction<SidechainSetMonitorNative, SidechainSetMonitorDart>('sidechain_set_monitor');
    _sidechainIsMonitoring = _lib.lookupFunction<SidechainIsMonitoringNative, SidechainIsMonitoringDart>('sidechain_is_monitoring');

    // Automation
    _automationSetMode = _lib.lookupFunction<AutomationSetModeNative, AutomationSetModeDart>('automation_set_mode');
    _automationGetMode = _lib.lookupFunction<AutomationGetModeNative, AutomationGetModeDart>('automation_get_mode');
    _automationSetRecording = _lib.lookupFunction<AutomationSetRecordingNative, AutomationSetRecordingDart>('automation_set_recording');
    _automationIsRecording = _lib.lookupFunction<AutomationIsRecordingNative, AutomationIsRecordingDart>('automation_is_recording');
    _automationTouchParam = _lib.lookupFunction<AutomationTouchParamNative, AutomationTouchParamDart>('automation_touch_param');
    _automationReleaseParam = _lib.lookupFunction<AutomationReleaseParamNative, AutomationReleaseParamDart>('automation_release_param');
    _automationRecordChange = _lib.lookupFunction<AutomationRecordChangeNative, AutomationRecordChangeDart>('automation_record_change');
    _automationAddPoint = _lib.lookupFunction<AutomationAddPointNative, AutomationAddPointDart>('automation_add_point');
    _automationGetValue = _lib.lookupFunction<AutomationGetValueNative, AutomationGetValueDart>('automation_get_value');
    _automationClearLane = _lib.lookupFunction<AutomationClearLaneNative, AutomationClearLaneDart>('automation_clear_lane');

    // Plugin Automation
    _automationAddPluginPoint = _lib.lookupFunction<AutomationAddPluginPointNative, AutomationAddPluginPointDart>('automation_add_plugin_point');
    _automationGetPluginValue = _lib.lookupFunction<AutomationGetPluginValueNative, AutomationGetPluginValueDart>('automation_get_plugin_value');
    _automationClearPluginLane = _lib.lookupFunction<AutomationClearPluginLaneNative, AutomationClearPluginLaneDart>('automation_clear_plugin_lane');
    _automationTouchPlugin = _lib.lookupFunction<AutomationTouchPluginNative, AutomationTouchPluginDart>('automation_touch_plugin');
    _automationReleasePlugin = _lib.lookupFunction<AutomationReleasePluginNative, AutomationReleasePluginDart>('automation_release_plugin');

    // Insert Effects
    _insertCreateChain = _lib.lookupFunction<InsertCreateChainNative, InsertCreateChainDart>('insert_create_chain');
    _insertRemoveChain = _lib.lookupFunction<InsertRemoveChainNative, InsertRemoveChainDart>('insert_remove_chain');
    _insertSetBypass = _lib.lookupFunction<InsertSetBypassNative, InsertSetBypassDart>('ffi_insert_set_bypass');
    _insertSetMix = _lib.lookupFunction<InsertSetMixNative, InsertSetMixDart>('ffi_insert_set_mix');
    _insertGetMix = _lib.lookupFunction<InsertGetMixNative, InsertGetMixDart>('ffi_insert_get_mix');
    _insertBypassAll = _lib.lookupFunction<InsertBypassAllNative, InsertBypassAllDart>('ffi_insert_bypass_all');
    _insertGetTotalLatency = _lib.lookupFunction<InsertGetTotalLatencyNative, InsertGetTotalLatencyDart>('ffi_insert_get_total_latency');
    _insertLoadProcessor = _lib.lookupFunction<InsertLoadProcessorNative, InsertLoadProcessorDart>('insert_load_processor');
    _insertUnloadSlot = _lib.lookupFunction<InsertUnloadSlotNative, InsertUnloadSlotDart>('insert_unload_slot');
    _insertSetParam = _lib.lookupFunction<InsertSetParamNative, InsertSetParamDart>('insert_set_param');
    _insertGetParam = _lib.lookupFunction<InsertGetParamNative, InsertGetParamDart>('insert_get_param');
    _insertIsLoaded = _lib.lookupFunction<InsertIsLoadedNative, InsertIsLoadedDart>('insert_is_loaded');
    _insertOpenEditor = _lib.lookupFunction<InsertOpenEditorNative, InsertOpenEditorDart>('insert_open_editor');

    // Transient Detection
    _transientDetect = _lib.lookupFunction<TransientDetectNative, TransientDetectDart>('transient_detect');
    _detectClipTransients = _lib.lookupFunction<EngineDetectClipTransientsNative, EngineDetectClipTransientsDart>('engine_detect_clip_transients');
    _getClipSampleRate = _lib.lookupFunction<EngineGetClipSampleRateNative, EngineGetClipSampleRateDart>('engine_get_clip_sample_rate');
    _getClipTotalFrames = _lib.lookupFunction<EngineGetClipTotalFramesNative, EngineGetClipTotalFramesDart>('engine_get_clip_total_frames');

    // Pitch Detection
    _pitchDetect = _lib.lookupFunction<PitchDetectNative, PitchDetectDart>('pitch_detect');
    _pitchDetectMidi = _lib.lookupFunction<PitchDetectMidiNative, PitchDetectMidiDart>('pitch_detect_midi');

    // Wave Cache
    _waveCacheHasCache = _lib.lookupFunction<WaveCacheHasCacheNative, WaveCacheHasCacheDart>('wave_cache_has_cache');
    _waveCacheBuild = _lib.lookupFunction<WaveCacheBuildNative, WaveCacheBuildDart>('wave_cache_build');
    _waveCacheBuildProgress = _lib.lookupFunction<WaveCacheBuildProgressNative, WaveCacheBuildProgressDart>('wave_cache_build_progress');
    _waveCacheQueryTiles = _lib.lookupFunction<WaveCacheQueryTilesNative, WaveCacheQueryTilesDart>('wave_cache_query_tiles');
    _waveCacheFreeTiles = _lib.lookupFunction<WaveCacheFreeTilesNative, WaveCacheFreeTilesDart>('wave_cache_free_tiles');
    _waveCacheBuildFromSamples = _lib.lookupFunction<WaveCacheBuildFromSamplesNative, WaveCacheBuildFromSamplesDart>('wave_cache_build_from_samples');
    _waveCacheClearAll = _lib.lookupFunction<WaveCacheClearAllNative, WaveCacheClearAllDart>('wave_cache_clear_all');
    _waveCacheLoadedCount = _lib.lookupFunction<WaveCacheLoadedCountNative, WaveCacheLoadedCountDart>('wave_cache_loaded_count');

    // Comping
    _compingCreateLane = _lib.lookupFunction<CompingCreateLaneNative, CompingCreateLaneDart>('comping_create_lane');
    _compingDeleteLane = _lib.lookupFunction<CompingDeleteLaneNative, CompingDeleteLaneDart>('comping_delete_lane');
    _compingSetActiveLane = _lib.lookupFunction<CompingSetActiveLaneNative, CompingSetActiveLaneDart>('comping_set_active_lane');
    _compingToggleLaneMute = _lib.lookupFunction<CompingToggleLaneMuteNative, CompingToggleLaneMuteDart>('comping_toggle_lane_mute');
    _compingSetLaneVisible = _lib.lookupFunction<CompingSetLaneVisibleNative, CompingSetLaneVisibleDart>('comping_set_lane_visible');
    _compingSetLaneHeight = _lib.lookupFunction<CompingSetLaneHeightNative, CompingSetLaneHeightDart>('comping_set_lane_height');
    _compingAddTake = _lib.lookupFunction<CompingAddTakeNative, CompingAddTakeDart>('comping_add_take');
    _compingDeleteTake = _lib.lookupFunction<CompingDeleteTakeNative, CompingDeleteTakeDart>('comping_delete_take');
    _compingSetTakeRating = _lib.lookupFunction<CompingSetTakeRatingNative, CompingSetTakeRatingDart>('comping_set_take_rating');
    _compingToggleTakeMute = _lib.lookupFunction<CompingToggleTakeMuteNative, CompingToggleTakeMuteDart>('comping_toggle_take_mute');
    _compingToggleTakeInComp = _lib.lookupFunction<CompingToggleTakeInCompNative, CompingToggleTakeInCompDart>('comping_toggle_take_in_comp');
    _compingSetTakeGain = _lib.lookupFunction<CompingSetTakeGainNative, CompingSetTakeGainDart>('comping_set_take_gain');
    _compingCreateRegion = _lib.lookupFunction<CompingCreateRegionNative, CompingCreateRegionDart>('comping_create_region');
    _compingDeleteRegion = _lib.lookupFunction<CompingDeleteRegionNative, CompingDeleteRegionDart>('comping_delete_region');
    _compingSetRegionCrossfadeIn = _lib.lookupFunction<CompingSetRegionCrossfadeInNative, CompingSetRegionCrossfadeInDart>('comping_set_region_crossfade_in');
    _compingSetRegionCrossfadeOut = _lib.lookupFunction<CompingSetRegionCrossfadeOutNative, CompingSetRegionCrossfadeOutDart>('comping_set_region_crossfade_out');
    _compingSetRegionCrossfadeType = _lib.lookupFunction<CompingSetRegionCrossfadeTypeNative, CompingSetRegionCrossfadeTypeDart>('comping_set_region_crossfade_type');
    _compingSetMode = _lib.lookupFunction<CompingSetModeNative, CompingSetModeDart>('comping_set_mode');
    _compingGetMode = _lib.lookupFunction<CompingGetModeNative, CompingGetModeDart>('comping_get_mode');
    _compingToggleLanesExpanded = _lib.lookupFunction<CompingToggleLanesExpandedNative, CompingToggleLanesExpandedDart>('comping_toggle_lanes_expanded');
    _compingGetLanesExpanded = _lib.lookupFunction<CompingGetLanesExpandedNative, CompingGetLanesExpandedDart>('comping_get_lanes_expanded');
    _compingGetLaneCount = _lib.lookupFunction<CompingGetLaneCountNative, CompingGetLaneCountDart>('comping_get_lane_count');
    _compingGetActiveLaneIndex = _lib.lookupFunction<CompingGetActiveLaneIndexNative, CompingGetActiveLaneIndexDart>('comping_get_active_lane_index');
    _compingClearComp = _lib.lookupFunction<CompingClearCompNative, CompingClearCompDart>('comping_clear_comp');
    _compingGetStateJson = _lib.lookupFunction<CompingGetStateJsonNative, CompingGetStateJsonDart>('comping_get_state_json');
    _compingLoadStateJson = _lib.lookupFunction<CompingLoadStateJsonNative, CompingLoadStateJsonDart>('comping_load_state_json');
    _compingStartRecording = _lib.lookupFunction<CompingStartRecordingNative, CompingStartRecordingDart>('comping_start_recording');
    _compingStopRecording = _lib.lookupFunction<CompingStopRecordingNative, CompingStopRecordingDart>('comping_stop_recording');
    _compingIsRecording = _lib.lookupFunction<CompingIsRecordingNative, CompingIsRecordingDart>('comping_is_recording');
    _compingDeleteBadTakes = _lib.lookupFunction<CompingDeleteBadTakesNative, CompingDeleteBadTakesDart>('comping_delete_bad_takes');
    _compingPromoteBestTakes = _lib.lookupFunction<CompingPromoteBestTakesNative, CompingPromoteBestTakesDart>('comping_promote_best_takes');
    _compingRemoveTrack = _lib.lookupFunction<CompingRemoveTrackNative, CompingRemoveTrackDart>('comping_remove_track');
    _compingClearAll = _lib.lookupFunction<CompingClearAllNative, CompingClearAllDart>('comping_clear_all');

    // Video FFI
    _videoAddTrack = _lib.lookupFunction<VideoAddTrackNative, VideoAddTrackDart>('video_add_track');
    _videoImport = _lib.lookupFunction<VideoImportNative, VideoImportDart>('video_import');
    _videoSetPlayhead = _lib.lookupFunction<VideoSetPlayheadNative, VideoSetPlayheadDart>('video_set_playhead');
    _videoGetPlayhead = _lib.lookupFunction<VideoGetPlayheadNative, VideoGetPlayheadDart>('video_get_playhead');
    _videoGetFrame = _lib.lookupFunction<VideoGetFrameNative, VideoGetFrameDart>('video_get_frame');
    _videoFreeFrame = _lib.lookupFunction<VideoFreeFrameNative, VideoFreeFrameDart>('video_free_frame');
    _videoGetInfoJson = _lib.lookupFunction<VideoGetInfoJsonNative, VideoGetInfoJsonDart>('video_get_info_json');
    _videoGenerateThumbnails = _lib.lookupFunction<VideoGenerateThumbnailsNative, VideoGenerateThumbnailsDart>('video_generate_thumbnails');
    _videoGetTrackCount = _lib.lookupFunction<VideoGetTrackCountNative, VideoGetTrackCountDart>('video_get_track_count');
    _videoClearAll = _lib.lookupFunction<VideoClearAllNative, VideoClearAllDart>('video_clear_all');
    _videoFormatTimecode = _lib.lookupFunction<VideoFormatTimecodeNative, VideoFormatTimecodeDart>('video_format_timecode');
    _videoParseTimecode = _lib.lookupFunction<VideoParseTimecodeNative, VideoParseTimecodeDart>('video_parse_timecode');

    // Mastering Engine
    _masteringEngineInit = _lib.lookupFunction<MasteringEngineInitNative, MasteringEngineInitDart>('mastering_engine_init');
    _masteringSetPreset = _lib.lookupFunction<MasteringSetPresetNative, MasteringSetPresetDart>('mastering_set_preset');
    _masteringSetLoudnessTarget = _lib.lookupFunction<MasteringSetLoudnessTargetNative, MasteringSetLoudnessTargetDart>('mastering_set_loudness_target');
    _masteringSetReference = _lib.lookupFunction<MasteringSetReferenceNative, MasteringSetReferenceDart>('mastering_set_reference');
    _masteringProcessOffline = _lib.lookupFunction<MasteringProcessOfflineNative, MasteringProcessOfflineDart>('mastering_process_offline');
    _masteringGetResult = _lib.lookupFunction<MasteringGetResultNative, MasteringGetResultDart>('mastering_get_result');
    _masteringGetWarning = _lib.lookupFunction<MasteringGetWarningNative, MasteringGetWarningDart>('mastering_get_warning');
    _masteringGetChainSummary = _lib.lookupFunction<MasteringGetChainSummaryNative, MasteringGetChainSummaryDart>('mastering_get_chain_summary');
    _masteringReset = _lib.lookupFunction<MasteringResetNative, MasteringResetDart>('mastering_reset');
    _masteringSetActive = _lib.lookupFunction<MasteringSetActiveNative, MasteringSetActiveDart>('mastering_set_active');
    _masteringGetGainReduction = _lib.lookupFunction<MasteringGetGainReductionNative, MasteringGetGainReductionDart>('mastering_get_gain_reduction');
    _masteringGetDetectedGenre = _lib.lookupFunction<MasteringGetDetectedGenreNative, MasteringGetDetectedGenreDart>('mastering_get_detected_genre');
    _masteringGetLatency = _lib.lookupFunction<MasteringGetLatencyNative, MasteringGetLatencyDart>('mastering_get_latency');

    // Restoration bindings
    _restorationInit = _lib.lookupFunction<RestorationInitNative, RestorationInitDart>('restoration_init');
    _restorationSetSettings = _lib.lookupFunction<RestorationSetSettingsNative, RestorationSetSettingsDart>('restoration_set_settings');
    _restorationGetSettings = _lib.lookupFunction<RestorationGetSettingsNative, RestorationGetSettingsDart>('restoration_get_settings');
    _restorationAnalyze = _lib.lookupFunction<RestorationAnalyzeNative, RestorationAnalyzeDart>('restoration_analyze');
    _restorationGetSuggestionCount = _lib.lookupFunction<RestorationGetSuggestionCountNative, RestorationGetSuggestionCountDart>('restoration_get_suggestion_count');
    _restorationGetSuggestion = _lib.lookupFunction<RestorationGetSuggestionNative, RestorationGetSuggestionDart>('restoration_get_suggestion');
    _restorationProcess = _lib.lookupFunction<RestorationProcessNative, RestorationProcessDart>('restoration_process');
    _restorationProcessFile = _lib.lookupFunction<RestorationProcessFileNative, RestorationProcessFileDart>('restoration_process_file');
    _restorationLearnNoiseProfile = _lib.lookupFunction<RestorationLearnNoiseProfileNative, RestorationLearnNoiseProfileDart>('restoration_learn_noise_profile');
    _restorationClearNoiseProfile = _lib.lookupFunction<RestorationClearNoiseProfileNative, RestorationClearNoiseProfileDart>('restoration_clear_noise_profile');
    _restorationGetState = _lib.lookupFunction<RestorationGetStateNative, RestorationGetStateDart>('restoration_get_state');
    _restorationGetPhase = _lib.lookupFunction<RestorationGetPhaseNative, RestorationGetPhaseDart>('restoration_get_phase');
    _restorationSetActive = _lib.lookupFunction<RestorationSetActiveNative, RestorationSetActiveDart>('restoration_set_active');
    _restorationGetLatency = _lib.lookupFunction<RestorationGetLatencyNative, RestorationGetLatencyDart>('restoration_get_latency');
    _restorationReset = _lib.lookupFunction<RestorationResetNative, RestorationResetDart>('restoration_reset');

    // ML/AI bindings
    _mlInit = _lib.lookupFunction<MlInitNative, MlInitDart>('ml_init');
    _mlGetModelCount = _lib.lookupFunction<MlGetModelCountNative, MlGetModelCountDart>('ml_get_model_count');
    _mlGetModelName = _lib.lookupFunction<MlGetModelNameNative, MlGetModelNameDart>('ml_get_model_name');
    _mlModelIsAvailable = _lib.lookupFunction<MlModelIsAvailableNative, MlModelIsAvailableDart>('ml_model_is_available');
    _mlGetModelSize = _lib.lookupFunction<MlGetModelSizeNative, MlGetModelSizeDart>('ml_get_model_size');
    _mlDenoiseStart = _lib.lookupFunction<MlDenoiseStartNative, MlDenoiseStartDart>('ml_denoise_start');
    _mlSeparateStart = _lib.lookupFunction<MlSeparateStartNative, MlSeparateStartDart>('ml_separate_start');
    _mlEnhanceVoiceStart = _lib.lookupFunction<MlEnhanceVoiceStartNative, MlEnhanceVoiceStartDart>('ml_enhance_voice_start');
    _mlGetProgress = _lib.lookupFunction<MlGetProgressNative, MlGetProgressDart>('ml_get_progress');
    _mlIsProcessing = _lib.lookupFunction<MlIsProcessingNative, MlIsProcessingDart>('ml_is_processing');
    _mlGetPhase = _lib.lookupFunction<MlGetPhaseNative, MlGetPhaseDart>('ml_get_phase');
    _mlGetCurrentModel = _lib.lookupFunction<MlGetCurrentModelNative, MlGetCurrentModelDart>('ml_get_current_model');
    _mlCancel = _lib.lookupFunction<MlCancelNative, MlCancelDart>('ml_cancel');
    _mlSetExecutionProvider = _lib.lookupFunction<MlSetExecutionProviderNative, MlSetExecutionProviderDart>('ml_set_execution_provider');
    _mlGetError = _lib.lookupFunction<MlGetErrorNative, MlGetErrorDart>('ml_get_error');
    _mlReset = _lib.lookupFunction<MlResetNative, MlResetDart>('ml_reset');

    // Lua Scripting bindings
    _scriptInit = _lib.lookupFunction<ScriptInitNative, ScriptInitDart>('script_init');
    _scriptShutdown = _lib.lookupFunction<ScriptShutdownNative, ScriptShutdownDart>('script_shutdown');
    _scriptIsInitialized = _lib.lookupFunction<ScriptIsInitializedNative, ScriptIsInitializedDart>('script_is_initialized');
    _scriptExecute = _lib.lookupFunction<ScriptExecuteNative, ScriptExecuteDart>('script_execute');
    _scriptExecuteFile = _lib.lookupFunction<ScriptExecuteFileNative, ScriptExecuteFileDart>('script_execute_file');
    _scriptLoadFile = _lib.lookupFunction<ScriptLoadFileNative, ScriptLoadFileDart>('script_load_file');
    _scriptRun = _lib.lookupFunction<ScriptRunNative, ScriptRunDart>('script_run');
    _scriptGetOutput = _lib.lookupFunction<ScriptGetOutputNative, ScriptGetOutputDart>('script_get_output');
    _scriptGetError = _lib.lookupFunction<ScriptGetErrorNative, ScriptGetErrorDart>('script_get_error');
    _scriptGetDuration = _lib.lookupFunction<ScriptGetDurationNative, ScriptGetDurationDart>('script_get_duration');
    _scriptPollActions = _lib.lookupFunction<ScriptPollActionsNative, ScriptPollActionsDart>('script_poll_actions');
    _scriptGetNextAction = _lib.lookupFunction<ScriptGetNextActionNative, ScriptGetNextActionDart>('script_get_next_action');
    _scriptSetContext = _lib.lookupFunction<ScriptSetContextNative, ScriptSetContextDart>('script_set_context');
    _scriptSetSelectedTracks = _lib.lookupFunction<ScriptSetSelectedTracksNative, ScriptSetSelectedTracksDart>('script_set_selected_tracks');
    _scriptSetSelectedClips = _lib.lookupFunction<ScriptSetSelectedClipsNative, ScriptSetSelectedClipsDart>('script_set_selected_clips');
    _scriptAddSearchPath = _lib.lookupFunction<ScriptAddSearchPathNative, ScriptAddSearchPathDart>('script_add_search_path');
    _scriptGetLoadedCount = _lib.lookupFunction<ScriptGetLoadedCountNative, ScriptGetLoadedCountDart>('script_get_loaded_count');
    _scriptGetName = _lib.lookupFunction<ScriptGetNameNative, ScriptGetNameDart>('script_get_name');
    _scriptGetDescription = _lib.lookupFunction<ScriptGetDescriptionNative, ScriptGetDescriptionDart>('script_get_description');

    // Plugin Hosting
    _pluginHostInit = _lib.lookupFunction<PluginHostInitNative, PluginHostInitDart>('plugin_host_init');
    _pluginScanAll = _lib.lookupFunction<PluginScanAllNative, PluginScanAllDart>('plugin_scan_all');
    _pluginGetCount = _lib.lookupFunction<PluginGetCountNative, PluginGetCountDart>('plugin_get_count');
    _pluginGetAllJson = _lib.lookupFunction<PluginGetAllJsonNative, PluginGetAllJsonDart>('plugin_get_all_json');
    _pluginGetInfoJson = _lib.lookupFunction<PluginGetInfoJsonNative, PluginGetInfoJsonDart>('plugin_get_info_json');
    _pluginLoad = _lib.lookupFunction<PluginLoadNative, PluginLoadDart>('plugin_load');
    _pluginUnload = _lib.lookupFunction<PluginUnloadNative, PluginUnloadDart>('plugin_unload');
    _pluginActivate = _lib.lookupFunction<PluginActivateNative, PluginActivateDart>('plugin_activate');
    _pluginDeactivate = _lib.lookupFunction<PluginDeactivateNative, PluginDeactivateDart>('plugin_deactivate');
    _pluginGetParamCount = _lib.lookupFunction<PluginGetParamCountNative, PluginGetParamCountDart>('plugin_get_param_count');
    _pluginGetParam = _lib.lookupFunction<PluginGetParamNative, PluginGetParamDart>('plugin_get_param');
    _pluginSetParam = _lib.lookupFunction<PluginSetParamNative, PluginSetParamDart>('plugin_set_param');
    _pluginGetAllParamsJson = _lib.lookupFunction<PluginGetAllParamsJsonNative, PluginGetAllParamsJsonDart>('plugin_get_all_params_json');
    _pluginHasEditor = _lib.lookupFunction<PluginHasEditorNative, PluginHasEditorDart>('plugin_has_editor');
    _pluginGetLatency = _lib.lookupFunction<PluginGetLatencyNative, PluginGetLatencyDart>('plugin_get_latency');
    _pluginOpenEditor = _lib.lookupFunction<PluginOpenEditorNative, PluginOpenEditorDart>('plugin_open_editor');
    _pluginCloseEditor = _lib.lookupFunction<PluginCloseEditorNative, PluginCloseEditorDart>('plugin_close_editor');
    _pluginEditorSize = _lib.lookupFunction<PluginEditorSizeNative, PluginEditorSizeDart>('plugin_editor_size');
    _pluginResizeEditor = _lib.lookupFunction<PluginResizeEditorNative, PluginResizeEditorDart>('plugin_resize_editor');
    _pluginGetState = _lib.lookupFunction<PluginGetStateNative, PluginGetStateDart>('plugin_get_state');
    _pluginSetState = _lib.lookupFunction<PluginSetStateNative, PluginSetStateDart>('plugin_set_state');
    _pluginSavePreset = _lib.lookupFunction<PluginSavePresetNative, PluginSavePresetDart>('plugin_save_preset');
    _pluginLoadPreset = _lib.lookupFunction<PluginLoadPresetNative, PluginLoadPresetDart>('plugin_load_preset');
    _pluginSearch = _lib.lookupFunction<PluginSearchNative, PluginSearchDart>('plugin_search');
    _pluginGetByType = _lib.lookupFunction<PluginGetByTypeNative, PluginGetByTypeDart>('plugin_get_by_type');
    _pluginGetByCategory = _lib.lookupFunction<PluginGetByCategoryNative, PluginGetByCategoryDart>('plugin_get_by_category');
    _pluginGetInstancesJson = _lib.lookupFunction<PluginGetInstancesJsonNative, PluginGetInstancesJsonDart>('plugin_get_instances_json');

    // Plugin insert chain
    _pluginInsertLoad = _lib.lookupFunction<PluginInsertLoadNative, PluginInsertLoadDart>('plugin_insert_load');
    _pluginInsertRemove = _lib.lookupFunction<PluginInsertRemoveNative, PluginInsertRemoveDart>('plugin_insert_remove');
    _pluginInsertSetBypass = _lib.lookupFunction<PluginInsertSetBypassNative, PluginInsertSetBypassDart>('plugin_insert_set_bypass');
    _pluginInsertSetMix = _lib.lookupFunction<PluginInsertSetMixNative, PluginInsertSetMixDart>('plugin_insert_set_mix');
    _pluginInsertGetMix = _lib.lookupFunction<PluginInsertGetMixNative, PluginInsertGetMixDart>('plugin_insert_get_mix');
    _pluginInsertGetLatency = _lib.lookupFunction<PluginInsertGetLatencyNative, PluginInsertGetLatencyDart>('plugin_insert_get_latency');
    _pluginInsertChainLatency = _lib.lookupFunction<PluginInsertChainLatencyNative, PluginInsertChainLatencyDart>('plugin_insert_chain_latency');

    // MIDI I/O
    _midiScanInputDevices = _lib.lookupFunction<MidiScanInputDevicesNative, MidiScanInputDevicesDart>('midi_scan_input_devices');
    _midiScanOutputDevices = _lib.lookupFunction<MidiScanOutputDevicesNative, MidiScanOutputDevicesDart>('midi_scan_output_devices');
    _midiGetInputDeviceName = _lib.lookupFunction<MidiGetInputDeviceNameNative, MidiGetInputDeviceNameDart>('midi_get_input_device_name');
    _midiGetOutputDeviceName = _lib.lookupFunction<MidiGetOutputDeviceNameNative, MidiGetOutputDeviceNameDart>('midi_get_output_device_name');
    _midiInputDeviceCount = _lib.lookupFunction<MidiInputDeviceCountNative, MidiInputDeviceCountDart>('midi_input_device_count');
    _midiOutputDeviceCount = _lib.lookupFunction<MidiOutputDeviceCountNative, MidiOutputDeviceCountDart>('midi_output_device_count');
    _midiConnectInput = _lib.lookupFunction<MidiConnectInputNative, MidiConnectInputDart>('midi_connect_input');
    _midiDisconnectInput = _lib.lookupFunction<MidiDisconnectInputNative, MidiDisconnectInputDart>('midi_disconnect_input');
    _midiDisconnectAllInputs = _lib.lookupFunction<MidiDisconnectAllInputsNative, MidiDisconnectAllInputsDart>('midi_disconnect_all_inputs');
    _midiActiveInputCount = _lib.lookupFunction<MidiActiveInputCountNative, MidiActiveInputCountDart>('midi_active_input_count');
    _midiConnectOutput = _lib.lookupFunction<MidiConnectOutputNative, MidiConnectOutputDart>('midi_connect_output');
    _midiDisconnectOutput = _lib.lookupFunction<MidiDisconnectOutputNative, MidiDisconnectOutputDart>('midi_disconnect_output');
    _midiIsOutputConnected = _lib.lookupFunction<MidiIsOutputConnectedNative, MidiIsOutputConnectedDart>('midi_is_output_connected');
    _midiStartRecording = _lib.lookupFunction<MidiStartRecordingNative, MidiStartRecordingDart>('midi_start_recording');
    _midiStopRecording = _lib.lookupFunction<MidiStopRecordingNative, MidiStopRecordingDart>('midi_stop_recording');
    _midiArmTrack = _lib.lookupFunction<MidiArmTrackNative, MidiArmTrackDart>('midi_arm_track');
    _midiIsRecording = _lib.lookupFunction<MidiIsRecordingNative, MidiIsRecordingDart>('midi_is_recording');
    _midiGetRecordingState = _lib.lookupFunction<MidiGetRecordingStateNative, MidiGetRecordingStateDart>('midi_get_recording_state');
    _midiRecordedEventCount = _lib.lookupFunction<MidiRecordedEventCountNative, MidiRecordedEventCountDart>('midi_recorded_event_count');
    _midiGetTargetTrack = _lib.lookupFunction<MidiGetTargetTrackNative, MidiGetTargetTrackDart>('midi_get_target_track');
    _midiSetSampleRate = _lib.lookupFunction<MidiSetSampleRateNative, MidiSetSampleRateDart>('midi_set_sample_rate');
    _midiSetThru = _lib.lookupFunction<MidiSetThruNative, MidiSetThruDart>('midi_set_thru');
    _midiIsThruEnabled = _lib.lookupFunction<MidiIsThruEnabledNative, MidiIsThruEnabledDart>('midi_is_thru_enabled');
    _midiSendNoteOn = _lib.lookupFunction<MidiSendNoteOnNative, MidiSendNoteOnDart>('midi_send_note_on');
    _midiSendNoteOff = _lib.lookupFunction<MidiSendNoteOffNative, MidiSendNoteOffDart>('midi_send_note_off');
    _midiSendCc = _lib.lookupFunction<MidiSendCcNative, MidiSendCcDart>('midi_send_cc');
    _midiSendPitchBend = _lib.lookupFunction<MidiSendPitchBendNative, MidiSendPitchBendDart>('midi_send_pitch_bend');
    _midiSendProgramChange = _lib.lookupFunction<MidiSendProgramChangeNative, MidiSendProgramChangeDart>('midi_send_program_change');

    // Autosave System
    _autosaveInit = _lib.lookupFunction<AutosaveInitNative, AutosaveInitDart>('autosave_init');
    _autosaveShutdown = _lib.lookupFunction<AutosaveShutdownNative, AutosaveShutdownDart>('autosave_shutdown');
    _autosaveSetEnabled = _lib.lookupFunction<AutosaveSetEnabledNative, AutosaveSetEnabledDart>('autosave_set_enabled');
    _autosaveIsEnabled = _lib.lookupFunction<AutosaveIsEnabledNative, AutosaveIsEnabledDart>('autosave_is_enabled');
    _autosaveSetInterval = _lib.lookupFunction<AutosaveSetIntervalNative, AutosaveSetIntervalDart>('autosave_set_interval');
    _autosaveGetInterval = _lib.lookupFunction<AutosaveGetIntervalNative, AutosaveGetIntervalDart>('autosave_get_interval');
    _autosaveSetBackupCount = _lib.lookupFunction<AutosaveSetBackupCountNative, AutosaveSetBackupCountDart>('autosave_set_backup_count');
    _autosaveGetBackupCount = _lib.lookupFunction<AutosaveGetBackupCountNative, AutosaveGetBackupCountDart>('autosave_get_backup_count');
    _autosaveMarkDirty = _lib.lookupFunction<AutosaveMarkDirtyNative, AutosaveMarkDirtyDart>('autosave_mark_dirty');
    _autosaveMarkClean = _lib.lookupFunction<AutosaveMarkCleanNative, AutosaveMarkCleanDart>('autosave_mark_clean');
    _autosaveIsDirty = _lib.lookupFunction<AutosaveIsDirtyNative, AutosaveIsDirtyDart>('autosave_is_dirty');
    _autosaveShouldSave = _lib.lookupFunction<AutosaveShouldSaveNative, AutosaveShouldSaveDart>('autosave_should_save');
    _autosaveNow = _lib.lookupFunction<AutosaveNowNative, AutosaveNowDart>('autosave_now');
    _autosaveBackupCount = _lib.lookupFunction<AutosaveBackupCountNative, AutosaveBackupCountDart>('autosave_backup_count');
    _autosaveLatestPath = _lib.lookupFunction<AutosaveLatestPathNative, AutosaveLatestPathDart>('autosave_latest_path');
    _autosaveClearBackups = _lib.lookupFunction<AutosaveClearBackupsNative, AutosaveClearBackupsDart>('autosave_clear_backups');

    // Recent Projects
    _recentProjectsAdd = _lib.lookupFunction<RecentProjectsAddNative, RecentProjectsAddDart>('recent_projects_add');
    _recentProjectsCount = _lib.lookupFunction<RecentProjectsCountNative, RecentProjectsCountDart>('recent_projects_count');
    _recentProjectsGet = _lib.lookupFunction<RecentProjectsGetNative, RecentProjectsGetDart>('recent_projects_get');
    _recentProjectsRemove = _lib.lookupFunction<RecentProjectsRemoveNative, RecentProjectsRemoveDart>('recent_projects_remove');
    _recentProjectsClear = _lib.lookupFunction<RecentProjectsClearNative, RecentProjectsClearDart>('recent_projects_clear');

    // Middleware Event System
    _middlewareInit = _lib.lookupFunction<MiddlewareInitNative, MiddlewareInitDart>('middleware_init');
    _middlewareShutdown = _lib.lookupFunction<MiddlewareShutdownNative, MiddlewareShutdownDart>('middleware_shutdown');
    _middlewareIsInitialized = _lib.lookupFunction<MiddlewareIsInitializedNative, MiddlewareIsInitializedDart>('middleware_is_initialized');
    _middlewareRegisterEvent = _lib.lookupFunction<MiddlewareRegisterEventNative, MiddlewareRegisterEventDart>('middleware_register_event');
    _middlewareAddAction = _lib.lookupFunction<MiddlewareAddActionNative, MiddlewareAddActionDart>('middleware_add_action');
    _middlewarePostEvent = _lib.lookupFunction<MiddlewarePostEventNative, MiddlewarePostEventDart>('middleware_post_event');
    _middlewarePostEventByName = _lib.lookupFunction<MiddlewarePostEventByNameNative, MiddlewarePostEventByNameDart>('middleware_post_event_by_name');
    _middlewareStopPlayingId = _lib.lookupFunction<MiddlewareStopPlayingIdNative, MiddlewareStopPlayingIdDart>('middleware_stop_playing_id');
    _middlewareStopEvent = _lib.lookupFunction<MiddlewareStopEventNative, MiddlewareStopEventDart>('middleware_stop_event');
    _middlewareStopAll = _lib.lookupFunction<MiddlewareStopAllNative, MiddlewareStopAllDart>('middleware_stop_all');
    _middlewareRegisterStateGroup = _lib.lookupFunction<MiddlewareRegisterStateGroupNative, MiddlewareRegisterStateGroupDart>('middleware_register_state_group');
    _middlewareAddState = _lib.lookupFunction<MiddlewareAddStateNative, MiddlewareAddStateDart>('middleware_add_state');
    _middlewareSetState = _lib.lookupFunction<MiddlewareSetStateNative, MiddlewareSetStateDart>('middleware_set_state');
    _middlewareGetState = _lib.lookupFunction<MiddlewareGetStateNative, MiddlewareGetStateDart>('middleware_get_state');
    _middlewareRegisterSwitchGroup = _lib.lookupFunction<MiddlewareRegisterSwitchGroupNative, MiddlewareRegisterSwitchGroupDart>('middleware_register_switch_group');
    _middlewareAddSwitch = _lib.lookupFunction<MiddlewareAddSwitchNative, MiddlewareAddSwitchDart>('middleware_add_switch');
    _middlewareSetSwitch = _lib.lookupFunction<MiddlewareSetSwitchNative, MiddlewareSetSwitchDart>('middleware_set_switch');
    _middlewareRegisterRtpc = _lib.lookupFunction<MiddlewareRegisterRtpcNative, MiddlewareRegisterRtpcDart>('middleware_register_rtpc');
    _middlewareSetRtpc = _lib.lookupFunction<MiddlewareSetRtpcNative, MiddlewareSetRtpcDart>('middleware_set_rtpc');
    _middlewareSetRtpcOnObject = _lib.lookupFunction<MiddlewareSetRtpcOnObjectNative, MiddlewareSetRtpcOnObjectDart>('middleware_set_rtpc_on_object');
    _middlewareGetRtpc = _lib.lookupFunction<MiddlewareGetRtpcNative, MiddlewareGetRtpcDart>('middleware_get_rtpc');
    _middlewareResetRtpc = _lib.lookupFunction<MiddlewareResetRtpcNative, MiddlewareResetRtpcDart>('middleware_reset_rtpc');
    _middlewareRegisterGameObject = _lib.lookupFunction<MiddlewareRegisterGameObjectNative, MiddlewareRegisterGameObjectDart>('middleware_register_game_object');
    _middlewareUnregisterGameObject = _lib.lookupFunction<MiddlewareUnregisterGameObjectNative, MiddlewareUnregisterGameObjectDart>('middleware_unregister_game_object');
    _middlewareGetEventCount = _lib.lookupFunction<MiddlewareGetEventCountNative, MiddlewareGetEventCountDart>('middleware_get_event_count');
    _middlewareGetStateGroupCount = _lib.lookupFunction<MiddlewareGetStateGroupCountNative, MiddlewareGetStateGroupCountDart>('middleware_get_state_group_count');
    _middlewareGetSwitchGroupCount = _lib.lookupFunction<MiddlewareGetSwitchGroupCountNative, MiddlewareGetSwitchGroupCountDart>('middleware_get_switch_group_count');
    _middlewareGetRtpcCount = _lib.lookupFunction<MiddlewareGetRtpcCountNative, MiddlewareGetRtpcCountDart>('middleware_get_rtpc_count');
    _middlewareGetActiveInstanceCount = _lib.lookupFunction<MiddlewareGetActiveInstanceCountNative, MiddlewareGetActiveInstanceCountDart>('middleware_get_active_instance_count');

    // Stage System bindings
    _stageParseJson = _lib.lookupFunction<StageParseJsonNative, StageParseJsonDart>('stage_parse_json');
    _stageGetTraceJson = _lib.lookupFunction<StageGetTraceJsonNative, StageGetTraceJsonDart>('stage_get_trace_json');
    _stageGetEventCount = _lib.lookupFunction<StageGetEventCountNative, StageGetEventCountDart>('stage_get_event_count');
    _stageGetEventJson = _lib.lookupFunction<StageGetEventJsonNative, StageGetEventJsonDart>('stage_get_event_json');
    _stageResolveTiming = _lib.lookupFunction<StageResolveTimingNative, StageResolveTimingDart>('stage_resolve_timing');
    _stageGetTimedTraceJson = _lib.lookupFunction<StageGetTimedTraceJsonNative, StageGetTimedTraceJsonDart>('stage_get_timed_trace_json');
    _stageGetDurationMs = _lib.lookupFunction<StageGetDurationMsNative, StageGetDurationMsDart>('stage_get_duration_ms');
    _stageGetEventsAtTime = _lib.lookupFunction<StageGetEventsAtTimeNative, StageGetEventsAtTimeDart>('stage_get_events_at_time');
    _wizardAnalyzeJson = _lib.lookupFunction<WizardAnalyzeJsonNative, WizardAnalyzeJsonDart>('wizard_analyze_json');
    _wizardGetConfidence = _lib.lookupFunction<WizardGetConfidenceNative, WizardGetConfidenceDart>('wizard_get_confidence');
    _wizardGetRecommendedLayer = _lib.lookupFunction<WizardGetRecommendedLayerNative, WizardGetRecommendedLayerDart>('wizard_get_recommended_layer');
    _wizardGetDetectedCompany = _lib.lookupFunction<WizardGetDetectedCompanyNative, WizardGetDetectedCompanyDart>('wizard_get_detected_company');
    _wizardGetDetectedEngine = _lib.lookupFunction<WizardGetDetectedEngineNative, WizardGetDetectedEngineDart>('wizard_get_detected_engine');
    _wizardGetConfigToml = _lib.lookupFunction<WizardGetConfigTomlNative, WizardGetConfigTomlDart>('wizard_get_config_toml');
    _wizardGetDetectedEventCount = _lib.lookupFunction<WizardGetDetectedEventCountNative, WizardGetDetectedEventCountDart>('wizard_get_detected_event_count');
    _wizardGetDetectedEventJson = _lib.lookupFunction<WizardGetDetectedEventJsonNative, WizardGetDetectedEventJsonDart>('wizard_get_detected_event_json');
    _adapterLoadConfig = _lib.lookupFunction<AdapterLoadConfigNative, AdapterLoadConfigDart>('adapter_load_config');
    _adapterGetCount = _lib.lookupFunction<AdapterGetCountNative, AdapterGetCountDart>('adapter_get_count');
    _adapterGetIdAt = _lib.lookupFunction<AdapterGetIdAtNative, AdapterGetIdAtDart>('adapter_get_id_at');
    _adapterGetInfoJson = _lib.lookupFunction<AdapterGetInfoJsonNative, AdapterGetInfoJsonDart>('adapter_get_info_json');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new track
  /// Returns track ID (non-zero) or 0 on failure
  int createTrack(String name, int color, int busId) {
    if (!_loaded) return 0;
    final namePtr = name.toNativeUtf8();
    try {
      return _createTrack(namePtr, color, busId);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Delete a track
  bool deleteTrack(int trackId) {
    if (!_loaded) return false;
    return _deleteTrack(trackId) != 0;
  }

  /// Set track name
  bool setTrackName(int trackId, String name) {
    if (!_loaded) return false;
    final namePtr = name.toNativeUtf8();
    try {
      return _setTrackName(trackId, namePtr) != 0;
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Set track mute state
  bool setTrackMute(int trackId, bool muted) {
    if (!_loaded) return false;
    return _setTrackMute(trackId, muted ? 1 : 0) != 0;
  }

  /// Set track solo state (Cubase-style: when any track is soloed, non-soloed tracks are silent)
  bool setTrackSolo(int trackId, bool solo) {
    if (!_loaded) return false;
    return _setTrackSolo(trackId, solo ? 1 : 0) != 0;
  }

  /// Check if solo mode is active (any track is soloed)
  bool isSoloActive() {
    if (!_loaded) return false;
    return _isSoloActive() != 0;
  }

  /// Clear all track solos
  bool clearAllSolos() {
    if (!_loaded) return false;
    return _clearAllSolos() != 0;
  }

  /// Set track armed (record ready) state
  bool setTrackArmed(int trackId, bool armed) {
    if (!_loaded) return false;
    return _setTrackArmed(trackId, armed ? 1 : 0) != 0;
  }

  /// Set track volume (0.0 - 2.0, 1.0 = unity)
  bool setTrackVolume(int trackId, double volume) {
    if (!_loaded) return false;
    return _setTrackVolume(trackId, volume) != 0;
  }

  /// Set track pan (-1.0 to 1.0)
  /// For stereo tracks with dual-pan, this controls the left channel
  bool setTrackPan(int trackId, double pan) {
    if (!_loaded) return false;
    return _setTrackPan(trackId, pan) != 0;
  }

  /// Set track right channel pan (-1.0 to 1.0)
  /// For stereo tracks with dual-pan (Pro Tools style), this controls the right channel
  bool setTrackPanRight(int trackId, double pan) {
    if (!_loaded) return false;
    return _setTrackPanRight(trackId, pan) != 0;
  }

  /// Get track channel count (1 = mono, 2 = stereo)
  int getTrackChannels(int trackId) {
    if (!_loaded) return 2;
    return _getTrackChannels(trackId);
  }

  /// Set track channel count
  bool setTrackChannels(int trackId, int channels) {
    if (!_loaded) return false;
    return _setTrackChannels(trackId, channels) != 0;
  }

  /// Set track output bus (0=Master, 1=Music, 2=SFX, 3=Voice, 4=Ambience, 5=Aux)
  bool setTrackBus(int trackId, int busId) {
    if (!_loaded) return false;
    return _setTrackBus(trackId, busId) != 0;
  }

  /// Get track count
  int getTrackCount() {
    if (!_loaded) return 0;
    return _getTrackCount();
  }

  /// Get track peak level (0.0 - 1.0+) by track ID - returns max(L, R)
  double getTrackPeak(int trackId) {
    if (!_loaded) return 0.0;
    return _getTrackPeak(trackId);
  }

  /// Get track stereo peak levels (L, R) by track ID
  /// Returns (peakL, peakR) tuple
  (double, double) getTrackPeakStereo(int trackId) {
    if (!_loaded) return (0.0, 0.0);
    final peakLPtr = calloc<Double>();
    final peakRPtr = calloc<Double>();
    try {
      _getTrackPeakStereo(trackId, peakLPtr, peakRPtr);
      return (peakLPtr.value, peakRPtr.value);
    } finally {
      calloc.free(peakLPtr);
      calloc.free(peakRPtr);
    }
  }

  /// Get track stereo RMS levels (L, R) by track ID
  /// Returns (rmsL, rmsR) tuple
  (double, double) getTrackRmsStereo(int trackId) {
    if (!_loaded) return (0.0, 0.0);
    final rmsLPtr = calloc<Double>();
    final rmsRPtr = calloc<Double>();
    try {
      _getTrackRmsStereo(trackId, rmsLPtr, rmsRPtr);
      return (rmsLPtr.value, rmsRPtr.value);
    } finally {
      calloc.free(rmsLPtr);
      calloc.free(rmsRPtr);
    }
  }

  /// Get track correlation by track ID (-1.0 to 1.0)
  double getTrackCorrelation(int trackId) {
    if (!_loaded) return 1.0;
    return _getTrackCorrelation(trackId);
  }

  /// Get full track meter data (peakL, peakR, rmsL, rmsR, correlation)
  /// Returns TrackMeterData record
  ({double peakL, double peakR, double rmsL, double rmsR, double correlation}) getTrackMeter(int trackId) {
    if (!_loaded) return (peakL: 0.0, peakR: 0.0, rmsL: 0.0, rmsR: 0.0, correlation: 1.0);
    final peakLPtr = calloc<Double>();
    final peakRPtr = calloc<Double>();
    final rmsLPtr = calloc<Double>();
    final rmsRPtr = calloc<Double>();
    final corrPtr = calloc<Double>();
    try {
      _getTrackMeter(trackId, peakLPtr, peakRPtr, rmsLPtr, rmsRPtr, corrPtr);
      return (
        peakL: peakLPtr.value,
        peakR: peakRPtr.value,
        rmsL: rmsLPtr.value,
        rmsR: rmsRPtr.value,
        correlation: corrPtr.value,
      );
    } finally {
      calloc.free(peakLPtr);
      calloc.free(peakRPtr);
      calloc.free(rmsLPtr);
      calloc.free(rmsRPtr);
      calloc.free(corrPtr);
    }
  }

  /// Get all track peaks at once (more efficient for UI metering)
  /// Returns map of track_id -> peak value (max of L/R for backward compat)
  Map<int, double> getAllTrackPeaks(int maxTracks) {
    if (!_loaded) return {};
    final idsPtr = calloc<Uint64>(maxTracks);
    final peaksPtr = calloc<Double>(maxTracks);
    try {
      final count = _getAllTrackPeaks(idsPtr, peaksPtr, maxTracks);
      final result = <int, double>{};
      for (int i = 0; i < count; i++) {
        result[idsPtr[i]] = peaksPtr[i];
      }
      return result;
    } finally {
      calloc.free(idsPtr);
      calloc.free(peaksPtr);
    }
  }

  /// Get all track stereo meters at once (most efficient for UI)
  /// Returns map of track_id -> TrackMeterData
  Map<int, ({double peakL, double peakR, double rmsL, double rmsR, double correlation})> getAllTrackMeters(int maxTracks) {
    if (!_loaded) return {};
    final idsPtr = calloc<Uint64>(maxTracks);
    final peakLPtr = calloc<Double>(maxTracks);
    final peakRPtr = calloc<Double>(maxTracks);
    final rmsLPtr = calloc<Double>(maxTracks);
    final rmsRPtr = calloc<Double>(maxTracks);
    final corrPtr = calloc<Double>(maxTracks);
    try {
      final count = _getAllTrackMeters(idsPtr, peakLPtr, peakRPtr, rmsLPtr, rmsRPtr, corrPtr, maxTracks);
      final result = <int, ({double peakL, double peakR, double rmsL, double rmsR, double correlation})>{};
      for (int i = 0; i < count; i++) {
        result[idsPtr[i]] = (
          peakL: peakLPtr[i],
          peakR: peakRPtr[i],
          rmsL: rmsLPtr[i],
          rmsR: rmsRPtr[i],
          correlation: corrPtr[i],
        );
      }
      return result;
    } finally {
      calloc.free(idsPtr);
      calloc.free(peakLPtr);
      calloc.free(peakRPtr);
      calloc.free(rmsLPtr);
      calloc.free(rmsRPtr);
      calloc.free(corrPtr);
    }
  }

  /// Import audio file to track
  /// Returns clip ID or 0 on failure
  int importAudio(String path, int trackId, double startTime) {
    if (!_loaded) return 0;
    final pathPtr = path.toNativeUtf8();
    try {
      return _importAudio(pathPtr, trackId, startTime);
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Add a clip to a track
  /// Returns clip ID
  int addClip(int trackId, String name, double startTime, double duration, double sourceOffset, double sourceDuration) {
    if (!_loaded) return 0;
    final namePtr = name.toNativeUtf8();
    try {
      return _addClip(trackId, namePtr, startTime, duration, sourceOffset, sourceDuration);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Move a clip
  bool moveClip(int clipId, int targetTrackId, double startTime) {
    if (!_loaded) return false;
    return _moveClip(clipId, targetTrackId, startTime) != 0;
  }

  /// Resize a clip
  bool resizeClip(int clipId, double startTime, double duration, double sourceOffset) {
    if (!_loaded) return false;
    return _resizeClip(clipId, startTime, duration, sourceOffset) != 0;
  }

  /// Split a clip at time
  /// Returns new clip ID or 0 on failure
  int splitClip(int clipId, double atTime) {
    if (!_loaded) return 0;
    return _splitClip(clipId, atTime);
  }

  /// Duplicate a clip
  /// Returns new clip ID or 0 on failure
  int duplicateClip(int clipId) {
    if (!_loaded) return 0;
    return _duplicateClip(clipId);
  }

  /// Delete a clip
  bool deleteClip(int clipId) {
    if (!_loaded) return false;
    return _deleteClip(clipId) != 0;
  }

  /// Set clip gain
  bool setClipGain(int clipId, double gain) {
    if (!_loaded) return false;
    return _setClipGain(clipId, gain) != 0;
  }

  /// Set clip muted state
  bool setClipMuted(int clipId, bool muted) {
    if (!_loaded) return false;
    return _setClipMuted(clipId, muted ? 1 : 0) != 0;
  }

  /// Get clip duration (in seconds)
  /// Returns -1 if clip not found
  double getClipDuration(int clipId) {
    if (!_loaded) return -1;
    return _getClipDuration(clipId);
  }

  /// Get clip source duration (original file duration in seconds)
  /// Returns -1 if clip not found
  double getClipSourceDuration(int clipId) {
    if (!_loaded) return -1;
    return _getClipSourceDuration(clipId);
  }

  /// Get audio file duration (in seconds) by reading the file
  /// Returns -1 on error
  double getAudioFileDuration(String path) {
    if (!_loaded) return -1;
    final pathPtr = path.toNativeUtf8();
    try {
      return _getAudioFileDuration(pathPtr);
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Get waveform peaks for a clip
  /// Returns list of (min, max) peak pairs
  List<double> getWaveformPeaks(int clipId, {int lodLevel = 0, int maxPeaks = 4096}) {
    if (!_loaded) return [];

    final buffer = calloc<Float>(maxPeaks * 2);
    try {
      final count = _getWaveformPeaks(clipId, lodLevel, buffer, maxPeaks);
      if (count == 0) return [];

      final result = <double>[];
      for (var i = 0; i < count * 2; i++) {
        result.add(buffer[i]);
      }
      return result;
    } finally {
      calloc.free(buffer);
    }
  }

  /// Get number of LOD levels
  int getWaveformLodLevels() {
    if (!_loaded) return 0;
    return _getWaveformLodLevels();
  }

  /// Pixel-exact waveform query (Cubase-style)
  /// Returns WaveformPixelData with min/max/rms per pixel
  WaveformPixelData? queryWaveformPixels(int clipId, int startFrame, int endFrame, int numPixels) {
    if (!_loaded || numPixels <= 0) return null;

    final buffer = calloc<Float>(numPixels * 3); // min, max, rms per pixel
    try {
      final count = _queryWaveformPixels(clipId, startFrame, endFrame, numPixels, buffer);
      if (count == 0) return null;

      final mins = Float32List(count);
      final maxs = Float32List(count);
      final rms = Float32List(count);

      for (var i = 0; i < count; i++) {
        mins[i] = buffer[i * 3];
        maxs[i] = buffer[i * 3 + 1];
        rms[i] = buffer[i * 3 + 2];
      }

      return WaveformPixelData(mins: mins, maxs: maxs, rms: rms);
    } finally {
      calloc.free(buffer);
    }
  }

  /// Stereo pixel-exact waveform query
  /// Returns StereoWaveformPixelData with min/max/rms per pixel for both L/R channels
  StereoWaveformPixelData? queryWaveformPixelsStereo(int clipId, int startFrame, int endFrame, int numPixels) {
    if (!_loaded || numPixels <= 0) return null;

    // 6 floats per pixel: L_min, L_max, L_rms, R_min, R_max, R_rms
    final buffer = calloc<Float>(numPixels * 6);
    try {
      final count = _queryWaveformPixelsStereo(clipId, startFrame, endFrame, numPixels, buffer);
      if (count == 0) return null;

      final leftMins = Float32List(count);
      final leftMaxs = Float32List(count);
      final leftRms = Float32List(count);
      final rightMins = Float32List(count);
      final rightMaxs = Float32List(count);
      final rightRms = Float32List(count);

      for (var i = 0; i < count; i++) {
        final idx = i * 6;
        leftMins[i] = buffer[idx];
        leftMaxs[i] = buffer[idx + 1];
        leftRms[i] = buffer[idx + 2];
        rightMins[i] = buffer[idx + 3];
        rightMaxs[i] = buffer[idx + 4];
        rightRms[i] = buffer[idx + 5];
      }

      return StereoWaveformPixelData(
        left: WaveformPixelData(mins: leftMins, maxs: leftMaxs, rms: leftRms),
        right: WaveformPixelData(mins: rightMins, maxs: rightMaxs, rms: rightRms),
      );
    } finally {
      calloc.free(buffer);
    }
  }

  /// Get waveform sample rate for a clip
  int getWaveformSampleRate(int clipId) {
    if (!_loaded) return 48000;
    return _getWaveformSampleRate(clipId);
  }

  /// Get waveform total samples for a clip
  int getWaveformTotalSamples(int clipId) {
    if (!_loaded) return 0;
    return _getWaveformTotalSamples(clipId);
  }

  /// Batch query waveform tiles (Cubase-style zero-hitch zoom)
  /// Returns list of WaveformPixelData, one per tile
  List<WaveformPixelData> queryWaveformTilesBatch(List<WaveformTileQuery> queries) {
    if (!_loaded || queries.isEmpty) return [];

    // Build input buffer: [clipId, startFrame, endFrame, numPixels] per tile
    final inputBuffer = calloc<Double>(queries.length * 4);
    int totalPixels = 0;
    for (var i = 0; i < queries.length; i++) {
      final q = queries[i];
      inputBuffer[i * 4] = q.clipId.toDouble();
      inputBuffer[i * 4 + 1] = q.startFrame.toDouble();
      inputBuffer[i * 4 + 2] = q.endFrame.toDouble();
      inputBuffer[i * 4 + 3] = q.numPixels.toDouble();
      totalPixels += q.numPixels;
    }

    // Output buffer: min/max/rms per pixel per tile
    final outputCapacity = totalPixels * 3;
    final outputBuffer = calloc<Float>(outputCapacity);

    try {
      final totalWritten = _queryWaveformTilesBatch(
        inputBuffer,
        queries.length,
        outputBuffer,
        outputCapacity,
      );

      if (totalWritten == 0) return [];

      // Parse results
      final results = <WaveformPixelData>[];
      var offset = 0;
      for (var i = 0; i < queries.length; i++) {
        final numPixels = queries[i].numPixels;
        final floatsForTile = numPixels * 3;
        if (offset + floatsForTile > totalWritten) break;

        final mins = Float32List(numPixels);
        final maxs = Float32List(numPixels);
        final rms = Float32List(numPixels);

        for (var p = 0; p < numPixels; p++) {
          mins[p] = outputBuffer[offset + p * 3];
          maxs[p] = outputBuffer[offset + p * 3 + 1];
          rms[p] = outputBuffer[offset + p * 3 + 2];
        }

        results.add(WaveformPixelData(mins: mins, maxs: maxs, rms: rms));
        offset += floatsForTile;
      }

      return results;
    } finally {
      calloc.free(inputBuffer);
      calloc.free(outputBuffer);
    }
  }

  /// Query raw samples for sample-mode rendering (ultra zoom-in)
  Float32List? queryRawSamples(int clipId, int startFrame, int numFrames) {
    if (!_loaded || numFrames <= 0) return null;

    final buffer = calloc<Float>(numFrames);
    try {
      final count = _queryRawSamples(clipId, startFrame, numFrames, buffer, numFrames);
      if (count == 0) return null;

      final samples = Float32List(count);
      for (var i = 0; i < count; i++) {
        samples[i] = buffer[i];
      }
      return samples;
    } finally {
      calloc.free(buffer);
    }
  }

  /// Set loop region
  void setLoopRegion(double start, double end) {
    if (!_loaded) return;
    _setLoopRegion(start, end);
  }

  /// Enable/disable loop
  void setLoopEnabled(bool enabled) {
    if (!_loaded) return;
    _setLoopEnabled(enabled ? 1 : 0);
  }

  /// Add a marker
  /// Returns marker ID
  int addMarker(String name, double time, int color) {
    if (!_loaded) return 0;
    final namePtr = name.toNativeUtf8();
    try {
      return _addMarker(namePtr, time, color);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Delete a marker
  bool deleteMarker(int markerId) {
    if (!_loaded) return false;
    return _deleteMarker(markerId) != 0;
  }

  /// Create a crossfade
  /// curve: 0=Linear, 1=EqualPower, 2=SCurve
  int createCrossfade(int clipAId, int clipBId, double duration, int curve) {
    if (!_loaded) return 0;
    return _createCrossfade(clipAId, clipBId, duration, curve);
  }

  /// Delete a crossfade
  bool deleteCrossfade(int crossfadeId) {
    if (!_loaded) return false;
    return _deleteCrossfade(crossfadeId) != 0;
  }

  /// Update a crossfade
  /// curve: 0=Linear, 1=EqualPower, 2=SCurve, 3=Logarithmic, 4=Exponential
  bool updateCrossfade(int crossfadeId, double duration, int curve) {
    if (!_loaded) return false;
    return _updateCrossfade(crossfadeId, duration, curve) != 0;
  }

  /// Clear all engine state
  void clearAll() {
    if (!_loaded) return;
    _clearAll();
  }

  /// Free a string allocated by Rust
  void freeString(Pointer<Utf8> ptr) {
    if (!_loaded || ptr.address == 0) return;
    _freeString(ptr);
  }

  /// Snap time to grid
  double snapToGrid(double time, double gridSize) {
    if (!_loaded) return time;
    return _snapToGrid(time, gridSize);
  }

  /// Snap time to nearest event
  double snapToEvent(double time, double threshold) {
    if (!_loaded) return time;
    return _snapToEvent(time, threshold);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRANSPORT API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start playback
  void play() {
    if (!_loaded) return;
    _play();
  }

  /// Pause playback
  void pause() {
    if (!_loaded) return;
    _pause();
  }

  /// Stop playback and reset position
  void stop() {
    if (!_loaded) return;
    _stop();
  }

  /// Seek to position in seconds
  void seek(double seconds) {
    if (!_loaded) return;
    _seek(seconds);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCRUBBING (Pro Tools / Cubase style audio preview on drag)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start scrubbing at given position
  void playbackStartScrub(double seconds) {
    if (!_loaded) return;
    _startScrub(seconds);
  }

  /// Update scrub position with velocity
  void playbackUpdateScrub(double seconds, double velocity) {
    if (!_loaded) return;
    _updateScrub(seconds, velocity);
  }

  /// Stop scrubbing
  void playbackStopScrub() {
    if (!_loaded) return;
    _stopScrub();
  }

  /// Check if currently scrubbing
  bool playbackIsScrubbing() {
    if (!_loaded) return false;
    return _isScrubbing() != 0;
  }

  /// Set scrub window size in milliseconds
  void playbackSetScrubWindowMs(int ms) {
    if (!_loaded) return;
    _setScrubWindowMs(ms);
  }

  /// Get current playback position in seconds
  double getPosition() {
    if (!_loaded) return 0.0;
    return _getPosition();
  }

  /// Get playback state (0=Stopped, 1=Playing, 2=Paused)
  int getPlaybackState() {
    if (!_loaded) return 0;
    return _getPlaybackState();
  }

  /// Check if currently playing
  bool isPlaying() {
    if (!_loaded) return false;
    return _isPlaying() != 0;
  }

  /// Set master volume (0.0 - 1.5)
  void setMasterVolume(double volume) {
    if (!_loaded) return;
    _setMasterVolume(volume);
  }

  /// Get master volume
  double getMasterVolume() {
    if (!_loaded) return 1.0;
    return _getMasterVolume();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VARISPEED CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enable/disable varispeed mode (tape-style speed with pitch change)
  void setVarispeedEnabled(bool enabled) {
    if (!_loaded) return;
    _setVarispeedEnabled(enabled ? 1 : 0);
  }

  /// Check if varispeed is enabled
  bool isVarispeedEnabled() {
    if (!_loaded) return false;
    return _isVarispeedEnabled() != 0;
  }

  /// Set varispeed rate (0.25 to 4.0, 1.0 = normal speed)
  void setVarispeedRate(double rate) {
    if (!_loaded) return;
    _setVarispeedRate(rate);
  }

  /// Get current varispeed rate
  double getVarispeedRate() {
    if (!_loaded) return 1.0;
    return _getVarispeedRate();
  }

  /// Set varispeed by semitone offset (+12 = 2x speed, -12 = 0.5x speed)
  void setVarispeedSemitones(double semitones) {
    if (!_loaded) return;
    _setVarispeedSemitones(semitones);
  }

  /// Get varispeed rate in semitones
  double getVarispeedSemitones() {
    if (!_loaded) return 0.0;
    return _getVarispeedSemitones();
  }

  /// Get effective playback rate (1.0 if varispeed disabled, actual rate if enabled)
  double getEffectivePlaybackRate() {
    if (!_loaded) return 1.0;
    return _getEffectivePlaybackRate();
  }

  /// Get current playback position in seconds (sample-accurate)
  double getPlaybackPositionSeconds() {
    if (!_loaded) return 0.0;
    return _getPlaybackPositionSeconds();
  }

  /// Get current playback position in samples
  int getPlaybackPositionSamples() {
    if (!_loaded) return 0;
    return _getPlaybackPositionSamples();
  }

  /// Preload all audio files for playback
  void preloadAll() {
    if (!_loaded) return;
    _preloadAll();
  }

  /// Preload audio files in time range
  void preloadRange(double startTime, double endTime) {
    if (!_loaded) return;
    _preloadRange(startTime, endTime);
  }

  /// Sync transport loop settings from loop region
  void syncLoopFromRegion() {
    if (!_loaded) return;
    _syncLoopFromRegion();
  }

  /// Get sample rate
  int getSampleRate() {
    if (!_loaded) return 48000;
    return _getSampleRate();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO STREAM API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start the audio output stream (cpal device)
  bool startPlayback() {
    if (!_loaded) return false;
    return _startPlayback() != 0;
  }

  /// Stop the audio output stream
  void stopPlayback() {
    if (!_loaded) return;
    _stopPlayback();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // METERING API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get peak meter values (left, right) as linear amplitude
  /// Returns (0.0, 0.0) if not loaded
  (double, double) getPeakMeters() {
    if (!_loaded) return (0.0, 0.0);
    final leftPtr = calloc<Double>();
    final rightPtr = calloc<Double>();
    try {
      _getPeakMeters(leftPtr, rightPtr);
      return (leftPtr.value, rightPtr.value);
    } finally {
      calloc.free(leftPtr);
      calloc.free(rightPtr);
    }
  }

  /// Get RMS meter values (left, right) as linear amplitude
  /// Returns (0.0, 0.0) if not loaded
  (double, double) getRmsMeters() {
    if (!_loaded) return (0.0, 0.0);
    final leftPtr = calloc<Double>();
    final rightPtr = calloc<Double>();
    try {
      _getRmsMeters(leftPtr, rightPtr);
      return (leftPtr.value, rightPtr.value);
    } finally {
      calloc.free(leftPtr);
      calloc.free(rightPtr);
    }
  }

  /// Get LUFS meter values (momentary, short-term, integrated) in LUFS
  /// Returns (-70.0, -70.0, -70.0) if not loaded
  (double, double, double) getLufsMeters() {
    if (!_loaded) return (-70.0, -70.0, -70.0);
    final momentaryPtr = calloc<Double>();
    final shortPtr = calloc<Double>();
    final integratedPtr = calloc<Double>();
    try {
      _getLufsMeters(momentaryPtr, shortPtr, integratedPtr);
      return (momentaryPtr.value, shortPtr.value, integratedPtr.value);
    } finally {
      calloc.free(momentaryPtr);
      calloc.free(shortPtr);
      calloc.free(integratedPtr);
    }
  }

  /// Get True Peak meter values (left, right) in dBTP
  /// Returns (-70.0, -70.0) if not loaded
  (double, double) getTruePeakMeters() {
    if (!_loaded) return (-70.0, -70.0);
    final leftPtr = calloc<Double>();
    final rightPtr = calloc<Double>();
    try {
      _getTruePeakMeters(leftPtr, rightPtr);
      return (leftPtr.value, rightPtr.value);
    } finally {
      calloc.free(leftPtr);
      calloc.free(rightPtr);
    }
  }

  /// Get stereo correlation (-1.0 = out of phase, 0.0 = uncorrelated, 1.0 = mono)
  /// Returns 1.0 (mono) if not loaded
  double getCorrelation() {
    if (!_loaded) return 1.0;
    return _getCorrelation();
  }

  /// Get stereo balance (-1.0 = full left, 0.0 = center, 1.0 = full right)
  /// Returns 0.0 (center) if not loaded
  double getStereoBalance() {
    if (!_loaded) return 0.0;
    return _getStereoBalance();
  }

  /// Get dynamic range (peak - RMS in dB)
  /// Returns 0.0 if not loaded
  double getDynamicRange() {
    if (!_loaded) return 0.0;
    return _getDynamicRange();
  }

  /// Get master spectrum data (256 bins, normalized 0-1, log-scaled 20Hz-20kHz)
  Float32List getMasterSpectrum() {
    if (!_loaded) return Float32List(256);
    final outData = calloc<Float>(256);
    try {
      final count = _getMasterSpectrum(outData, 256);
      if (count <= 0) return Float32List(256);
      return Float32List.fromList(outData.asTypedList(count));
    } finally {
      calloc.free(outData);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UNDO/REDO API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Undo last action
  bool undo() {
    if (!_loaded) return false;
    return _undo() != 0;
  }

  /// Redo last undone action
  bool redo() {
    if (!_loaded) return false;
    return _redo() != 0;
  }

  /// Check if undo is available
  bool canUndo() {
    if (!_loaded) return false;
    return _canUndo() != 0;
  }

  /// Check if redo is available
  bool canRedo() {
    if (!_loaded) return false;
    return _canRedo() != 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROJECT API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Save project to path
  bool saveProject(String path) {
    if (!_loaded) return false;
    final pathPtr = path.toNativeUtf8();
    try {
      return _saveProject(pathPtr) != 0;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Load project from path
  bool loadProject(String path) {
    if (!_loaded) return false;
    final pathPtr = path.toNativeUtf8();
    try {
      return _loadProject(pathPtr) != 0;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Check if project has unsaved changes
  bool isProjectModified() {
    if (!_loaded) return false;
    return _isProjectModified() != 0;
  }

  /// Mark project as dirty (has unsaved changes)
  void markProjectDirty() {
    if (!_loaded) return;
    _markProjectDirty();
  }

  /// Mark project as clean (just saved)
  void markProjectClean() {
    if (!_loaded) return;
    _markProjectClean();
  }

  /// Set project file path
  void setProjectFilePath(String? path) {
    if (!_loaded) return;
    if (path == null) {
      // Pass null as empty string - Rust will interpret empty as None
      final ptr = ''.toNativeUtf8();
      try {
        _setProjectFilePath(ptr);
      } finally {
        calloc.free(ptr);
      }
    } else {
      final pathPtr = path.toNativeUtf8();
      try {
        _setProjectFilePath(pathPtr);
      } finally {
        calloc.free(pathPtr);
      }
    }
  }

  /// Get project file path
  String? getProjectFilePath() {
    if (!_loaded) return null;
    final ptr = _getProjectFilePath();
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    return str.isEmpty ? null : str;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MEMORY API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get memory usage in MB
  double getMemoryUsage() {
    if (!_loaded) return 0.0;
    return _getMemoryUsage();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EQ API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enable/disable EQ band
  bool eqSetBandEnabled(int trackId, int bandIndex, bool enabled) {
    if (!_loaded) return false;
    return _eqSetBandEnabled(trackId, bandIndex, enabled ? 1 : 0) != 0;
  }

  /// Set EQ band frequency
  bool eqSetBandFrequency(int trackId, int bandIndex, double frequency) {
    if (!_loaded) return false;
    return _eqSetBandFrequency(trackId, bandIndex, frequency) != 0;
  }

  /// Set EQ band gain
  bool eqSetBandGain(int trackId, int bandIndex, double gain) {
    if (!_loaded) return false;
    return _eqSetBandGain(trackId, bandIndex, gain) != 0;
  }

  /// Set EQ band Q
  bool eqSetBandQ(int trackId, int bandIndex, double q) {
    if (!_loaded) return false;
    return _eqSetBandQ(trackId, bandIndex, q) != 0;
  }

  /// Set EQ band shape
  /// shape: 0=Bell, 1=LowShelf, 2=HighShelf, 3=LowCut, 4=HighCut, 5=Notch, 6=Bandpass, 7=TiltShelf, 8=Allpass, 9=Brickwall
  bool eqSetBandShape(int trackId, int bandIndex, int shape) {
    if (!_loaded) return false;
    return _eqSetBandShape(trackId, bandIndex, shape) != 0;
  }

  /// Set EQ bypass
  bool eqSetBypass(int trackId, bool bypass) {
    if (!_loaded) return false;
    return _eqSetBypass(trackId, bypass ? 1 : 0) != 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIXER BUS API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set bus volume in dB
  bool mixerSetBusVolume(int busId, double volumeDb) {
    if (!_loaded) return false;
    return _mixerSetBusVolume(busId, volumeDb) != 0;
  }

  /// Set bus mute
  bool mixerSetBusMute(int busId, bool muted) {
    if (!_loaded) return false;
    return _mixerSetBusMute(busId, muted ? 1 : 0) != 0;
  }

  /// Set bus solo
  bool mixerSetBusSolo(int busId, bool solo) {
    if (!_loaded) return false;
    return _mixerSetBusSolo(busId, solo ? 1 : 0) != 0;
  }

  /// Set bus pan
  bool mixerSetBusPan(int busId, double pan) {
    if (!_loaded) return false;
    return _mixerSetBusPan(busId, pan) != 0;
  }

  /// Set master volume in dB
  bool mixerSetMasterVolume(double volumeDb) {
    if (!_loaded) return false;
    return _mixerSetMasterVolume(volumeDb) != 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO PROCESSING API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Normalize clip to target dB level
  bool clipNormalize(int clipId, double targetDb) {
    if (!_loaded) return false;
    return _clipNormalize(clipId, targetDb) != 0;
  }

  /// Reverse clip audio
  bool clipReverse(int clipId) {
    if (!_loaded) return false;
    return _clipReverse(clipId) != 0;
  }

  /// Apply fade in to clip
  /// curveType: 0=Linear, 1=EqualPower, 2=SCurve
  bool clipFadeIn(int clipId, double durationSec, int curveType) {
    if (!_loaded) return false;
    return _clipFadeIn(clipId, durationSec, curveType) != 0;
  }

  /// Apply fade out to clip
  bool clipFadeOut(int clipId, double durationSec, int curveType) {
    if (!_loaded) return false;
    return _clipFadeOut(clipId, durationSec, curveType) != 0;
  }

  /// Apply gain adjustment to clip
  bool clipApplyGain(int clipId, double gainDb) {
    if (!_loaded) return false;
    return _clipApplyGain(clipId, gainDb) != 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK MANAGEMENT API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Rename a track
  bool trackRename(int trackId, String name) {
    if (!_loaded) return false;
    final namePtr = name.toNativeUtf8();
    try {
      return _trackRename(trackId, namePtr) != 0;
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Duplicate a track
  int trackDuplicate(int trackId) {
    if (!_loaded) return 0;
    return _trackDuplicate(trackId);
  }

  /// Set track color
  bool trackSetColor(int trackId, int color) {
    if (!_loaded) return false;
    return _trackSetColor(trackId, color) != 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLIP FX API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add FX to clip - returns slot ID or null
  int? addClipFx(int clipId, int fxType) {
    if (!_loaded) return null;
    final result = _clipFxAdd(clipId, fxType);
    return result > 0 ? result : null;
  }

  /// Remove FX from clip
  bool removeClipFx(int clipId, int slotId) {
    if (!_loaded) return false;
    return _clipFxRemove(clipId, slotId) != 0;
  }

  /// Set FX slot bypass
  bool setClipFxBypass(int clipId, int slotId, bool bypass) {
    if (!_loaded) return false;
    return _clipFxSetBypass(clipId, slotId, bypass ? 1 : 0) != 0;
  }

  /// Set FX chain bypass
  bool setClipFxChainBypass(int clipId, bool bypass) {
    if (!_loaded) return false;
    return _clipFxSetChainBypass(clipId, bypass ? 1 : 0) != 0;
  }

  /// Set FX wet/dry mix
  bool setClipFxWetDry(int clipId, int slotId, double wetDry) {
    if (!_loaded) return false;
    return _clipFxSetWetDry(clipId, slotId, wetDry) != 0;
  }

  /// Set FX chain input gain
  bool setClipFxInputGain(int clipId, double gainDb) {
    if (!_loaded) return false;
    return _clipFxSetInputGain(clipId, gainDb) != 0;
  }

  /// Set FX chain output gain
  bool setClipFxOutputGain(int clipId, double gainDb) {
    if (!_loaded) return false;
    return _clipFxSetOutputGain(clipId, gainDb) != 0;
  }

  /// Set Gain FX parameters
  bool setClipFxGainParams(int clipId, int slotId, double db, double pan) {
    if (!_loaded) return false;
    return _clipFxSetGainParams(clipId, slotId, db, pan) != 0;
  }

  /// Set Compressor FX parameters
  bool setClipFxCompressorParams(
    int clipId,
    int slotId,
    double ratio,
    double thresholdDb,
    double attackMs,
    double releaseMs,
  ) {
    if (!_loaded) return false;
    return _clipFxSetCompressorParams(clipId, slotId, ratio, thresholdDb, attackMs, releaseMs) != 0;
  }

  /// Set Limiter FX parameters
  bool setClipFxLimiterParams(int clipId, int slotId, double ceilingDb) {
    if (!_loaded) return false;
    return _clipFxSetLimiterParams(clipId, slotId, ceilingDb) != 0;
  }

  /// Set Gate FX parameters
  bool setClipFxGateParams(
    int clipId,
    int slotId,
    double thresholdDb,
    double attackMs,
    double releaseMs,
  ) {
    if (!_loaded) return false;
    return _clipFxSetGateParams(clipId, slotId, thresholdDb, attackMs, releaseMs) != 0;
  }

  /// Set Saturation FX parameters
  bool setClipFxSaturationParams(int clipId, int slotId, double drive, double mix) {
    if (!_loaded) return false;
    return _clipFxSetSaturationParams(clipId, slotId, drive, mix) != 0;
  }

  /// Move FX slot in chain
  bool moveClipFx(int clipId, int slotId, int newIndex) {
    if (!_loaded) return false;
    return _clipFxMove(clipId, slotId, newIndex) != 0;
  }

  /// Copy FX chain from one clip to another
  bool copyClipFx(int sourceClipId, int targetClipId) {
    if (!_loaded) return false;
    return _clipFxCopy(sourceClipId, targetClipId) != 0;
  }

  /// Clear all FX from clip
  bool clearClipFx(int clipId) {
    if (!_loaded) return false;
    return _clipFxClear(clipId) != 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VCA API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new VCA fader
  int vcaCreate(String name) {
    if (!_loaded) return 0;
    final namePtr = name.toNativeUtf8();
    try {
      return _vcaCreate(namePtr);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Delete a VCA fader
  bool vcaDelete(int vcaId) {
    if (!_loaded) return false;
    return _vcaDelete(vcaId) != 0;
  }

  /// Set VCA level (0.0 - 1.5)
  bool vcaSetLevel(int vcaId, double level) {
    if (!_loaded) return false;
    return _vcaSetLevel(vcaId, level) != 0;
  }

  /// Get VCA level
  double vcaGetLevel(int vcaId) {
    if (!_loaded) return 1.0;
    return _vcaGetLevel(vcaId);
  }

  /// Set VCA mute state
  bool vcaSetMute(int vcaId, bool muted) {
    if (!_loaded) return false;
    return _vcaSetMute(vcaId, muted ? 1 : 0) != 0;
  }

  /// Assign track to VCA
  bool vcaAssignTrack(int vcaId, int trackId) {
    if (!_loaded) return false;
    return _vcaAssignTrack(vcaId, trackId) != 0;
  }

  /// Remove track from VCA
  bool vcaRemoveTrack(int vcaId, int trackId) {
    if (!_loaded) return false;
    return _vcaRemoveTrack(vcaId, trackId) != 0;
  }

  /// Get effective volume for track including VCA contribution
  double vcaGetTrackEffectiveVolume(int trackId, double baseVolume) {
    if (!_loaded) return baseVolume;
    return _vcaGetTrackEffectiveVolume(trackId, baseVolume);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new track group
  int groupCreate(String name) {
    if (!_loaded) return 0;
    final namePtr = name.toNativeUtf8();
    try {
      return _groupCreate(namePtr);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Delete a track group
  bool groupDelete(int groupId) {
    if (!_loaded) return false;
    return _groupDelete(groupId) != 0;
  }

  /// Add track to group
  bool groupAddTrack(int groupId, int trackId) {
    if (!_loaded) return false;
    return _groupAddTrack(groupId, trackId) != 0;
  }

  /// Remove track from group
  bool groupRemoveTrack(int groupId, int trackId) {
    if (!_loaded) return false;
    return _groupRemoveTrack(groupId, trackId) != 0;
  }

  /// Set group link mode (0=Relative, 1=Absolute)
  bool groupSetLinkMode(int groupId, int linkMode) {
    if (!_loaded) return false;
    return _groupSetLinkMode(groupId, linkMode) != 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLICK TRACK API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enable/disable click track (metronome)
  void clickSetEnabled(bool enabled) {
    if (!_loaded) return;
    _clickSetEnabled(enabled ? 1 : 0);
  }

  /// Check if click track is enabled
  bool clickIsEnabled() {
    if (!_loaded) return false;
    return _clickIsEnabled() != 0;
  }

  /// Set click track volume (0.0 - 1.0)
  void clickSetVolume(double volume) {
    if (!_loaded) return;
    _clickSetVolume(volume);
  }

  /// Set click pattern (0=Quarter, 1=Eighth, 2=Sixteenth, 3=Triplet, 4=DownbeatOnly)
  void clickSetPattern(int pattern) {
    if (!_loaded) return;
    _clickSetPattern(pattern);
  }

  /// Set count-in mode (0=Off, 1=OneBar, 2=TwoBars, 3=FourBeats)
  void clickSetCountIn(int mode) {
    if (!_loaded) return;
    _clickSetCountIn(mode);
  }

  /// Set click pan (-1.0 left, 0.0 center, 1.0 right)
  void clickSetPan(double pan) {
    if (!_loaded) return;
    _clickSetPan(pan);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEND API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set send level (linear 0.0 - 1.0)
  void sendSetLevel(int trackId, int sendIndex, double level) {
    if (!_loaded) return;
    _sendSetLevel(trackId, sendIndex, level);
  }

  /// Set send level in dB
  void sendSetLevelDb(int trackId, int sendIndex, double db) {
    if (!_loaded) return;
    _sendSetLevelDb(trackId, sendIndex, db);
  }

  /// Set send destination (return bus index 0-3)
  void sendSetDestination(int trackId, int sendIndex, int destination) {
    if (!_loaded) return;
    _sendSetDestination(trackId, sendIndex, destination);
  }

  /// Set send pan (-1.0 left, 0.0 center, 1.0 right)
  void sendSetPan(int trackId, int sendIndex, double pan) {
    if (!_loaded) return;
    _sendSetPan(trackId, sendIndex, pan);
  }

  /// Enable/disable send
  void sendSetEnabled(int trackId, int sendIndex, bool enabled) {
    if (!_loaded) return;
    _sendSetEnabled(trackId, sendIndex, enabled ? 1 : 0);
  }

  /// Mute/unmute send
  void sendSetMuted(int trackId, int sendIndex, bool muted) {
    if (!_loaded) return;
    _sendSetMuted(trackId, sendIndex, muted ? 1 : 0);
  }

  /// Set send tap point (0=PreFader, 1=PostFader, 2=PostPan)
  void sendSetTapPoint(int trackId, int sendIndex, int tapPoint) {
    if (!_loaded) return;
    _sendSetTapPoint(trackId, sendIndex, tapPoint);
  }

  /// Create send bank for a track (call when track is created)
  void sendCreateBank(int trackId) {
    if (!_loaded) return;
    _sendCreateBank(trackId);
  }

  /// Remove send bank (call when track is deleted)
  void sendRemoveBank(int trackId) {
    if (!_loaded) return;
    _sendRemoveBank(trackId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RETURN BUS API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set return bus level (linear)
  void returnSetLevel(int returnIndex, double level) {
    if (!_loaded) return;
    _returnSetLevel(returnIndex, level);
  }

  /// Set return bus level in dB
  void returnSetLevelDb(int returnIndex, double db) {
    if (!_loaded) return;
    _returnSetLevelDb(returnIndex, db);
  }

  /// Set return bus pan
  void returnSetPan(int returnIndex, double pan) {
    if (!_loaded) return;
    _returnSetPan(returnIndex, pan);
  }

  /// Mute/unmute return bus
  void returnSetMuted(int returnIndex, bool muted) {
    if (!_loaded) return;
    _returnSetMuted(returnIndex, muted ? 1 : 0);
  }

  /// Solo/unsolo return bus
  void returnSetSolo(int returnIndex, bool solo) {
    if (!_loaded) return;
    _returnSetSolo(returnIndex, solo ? 1 : 0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SIDECHAIN API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a sidechain route (returns route ID)
  int sidechainAddRoute(int sourceId, int destProcessorId, {bool preFader = false}) {
    if (!_loaded) return 0;
    return _sidechainAddRoute(sourceId, destProcessorId, preFader ? 1 : 0);
  }

  /// Remove a sidechain route
  bool sidechainRemoveRoute(int routeId) {
    if (!_loaded) return false;
    return _sidechainRemoveRoute(routeId) != 0;
  }

  /// Create sidechain input for a processor
  void sidechainCreateInput(int processorId) {
    if (!_loaded) return;
    _sidechainCreateInput(processorId);
  }

  /// Remove sidechain input
  void sidechainRemoveInput(int processorId) {
    if (!_loaded) return;
    _sidechainRemoveInput(processorId);
  }

  /// Set sidechain source type
  /// sourceType: 0=Internal, 1=External, 2=Mid, 3=Side
  void sidechainSetSource(int processorId, int sourceType, {int externalId = 0}) {
    if (!_loaded) return;
    _sidechainSetSource(processorId, sourceType, externalId);
  }

  /// Set sidechain filter mode
  /// mode: 0=Off, 1=HighPass, 2=LowPass, 3=BandPass
  void sidechainSetFilterMode(int processorId, int mode) {
    if (!_loaded) return;
    _sidechainSetFilterMode(processorId, mode);
  }

  /// Set sidechain filter frequency (20-20000 Hz)
  void sidechainSetFilterFreq(int processorId, double freq) {
    if (!_loaded) return;
    _sidechainSetFilterFreq(processorId, freq);
  }

  /// Set sidechain filter Q (0.1-10.0)
  void sidechainSetFilterQ(int processorId, double q) {
    if (!_loaded) return;
    _sidechainSetFilterQ(processorId, q);
  }

  /// Set sidechain mix (0.0=internal, 1.0=external)
  void sidechainSetMix(int processorId, double mix) {
    if (!_loaded) return;
    _sidechainSetMix(processorId, mix);
  }

  /// Set sidechain gain in dB
  void sidechainSetGainDb(int processorId, double db) {
    if (!_loaded) return;
    _sidechainSetGainDb(processorId, db);
  }

  /// Enable/disable sidechain monitor (listen to key signal)
  void sidechainSetMonitor(int processorId, bool monitor) {
    if (!_loaded) return;
    _sidechainSetMonitor(processorId, monitor ? 1 : 0);
  }

  /// Check if sidechain is monitoring
  bool sidechainIsMonitoring(int processorId) {
    if (!_loaded) return false;
    return _sidechainIsMonitoring(processorId) != 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTOMATION API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set automation mode
  /// mode: 0=Read, 1=Touch, 2=Latch, 3=Write, 4=Trim, 5=Off
  void automationSetMode(int mode) {
    if (!_loaded) return;
    _automationSetMode(mode);
  }

  /// Get current automation mode
  int automationGetMode() {
    if (!_loaded) return 0;
    return _automationGetMode();
  }

  /// Enable/disable automation recording
  void automationSetRecording(bool enabled) {
    if (!_loaded) return;
    _automationSetRecording(enabled ? 1 : 0);
  }

  /// Check if automation recording is enabled
  bool automationIsRecording() {
    if (!_loaded) return false;
    return _automationIsRecording() != 0;
  }

  /// Touch parameter (start recording in touch/latch modes)
  void automationTouchParam(int trackId, String paramName, double value) {
    if (!_loaded) return;
    final namePtr = paramName.toNativeUtf8();
    try {
      _automationTouchParam(trackId, namePtr, value);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Release parameter (stop touch recording)
  void automationReleaseParam(int trackId, String paramName) {
    if (!_loaded) return;
    final namePtr = paramName.toNativeUtf8();
    try {
      _automationReleaseParam(trackId, namePtr);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Record parameter change
  void automationRecordChange(int trackId, String paramName, double value) {
    if (!_loaded) return;
    final namePtr = paramName.toNativeUtf8();
    try {
      _automationRecordChange(trackId, namePtr, value);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Add automation point directly
  /// curveType: 0=Linear, 1=Bezier, 2=Exponential, 3=Logarithmic, 4=Step, 5=SCurve
  void automationAddPoint(int trackId, String paramName, int timeSamples, double value, {int curveType = 0}) {
    if (!_loaded) return;
    final namePtr = paramName.toNativeUtf8();
    try {
      _automationAddPoint(trackId, namePtr, timeSamples, value, curveType);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Get automation value at position
  double automationGetValue(int trackId, String paramName, int timeSamples) {
    if (!_loaded) return 0.5;
    final namePtr = paramName.toNativeUtf8();
    try {
      return _automationGetValue(trackId, namePtr, timeSamples);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Clear automation lane
  void automationClearLane(int trackId, String paramName) {
    if (!_loaded) return;
    final namePtr = paramName.toNativeUtf8();
    try {
      _automationClearLane(trackId, namePtr);
    } finally {
      calloc.free(namePtr);
    }
  }

  // Bezier automation binding
  late final _automationAddPointBezier = _lib.lookupFunction<
      Void Function(Uint64, Pointer<Utf8>, Uint64, Double, Double, Double, Double, Double),
      void Function(int, Pointer<Utf8>, int, double, double, double, double, double)>('automation_add_point_bezier');

  late final _automationSetPointCurve = _lib.lookupFunction<
      Int32 Function(Uint64, Pointer<Utf8>, Uint64, Uint8),
      int Function(int, Pointer<Utf8>, int, int)>('automation_set_point_curve');

  /// Add automation point with bezier control points
  /// cp1: First control point (normalized 0-1)
  /// cp2: Second control point (normalized 0-1)
  void automationAddPointBezier(int trackId, String paramName, int timeSamples, double value,
      double cp1X, double cp1Y, double cp2X, double cp2Y) {
    if (!_loaded) return;
    final namePtr = paramName.toNativeUtf8();
    try {
      _automationAddPointBezier(trackId, namePtr, timeSamples, value, cp1X, cp1Y, cp2X, cp2Y);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Set curve type for existing automation point
  /// curveType: 0=Linear, 1=Bezier, 2=Exponential, 3=Logarithmic, 4=Step, 5=SCurve
  /// Returns true if point found and updated
  bool automationSetPointCurve(int trackId, String paramName, int timeSamples, int curveType) {
    if (!_loaded) return false;
    final namePtr = paramName.toNativeUtf8();
    try {
      return _automationSetPointCurve(trackId, namePtr, timeSamples, curveType) == 1;
    } finally {
      calloc.free(namePtr);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLUGIN AUTOMATION API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add automation point for plugin parameter
  /// Returns 1 on success, 0 on failure
  int automationAddPluginPoint(int trackId, int slot, int paramIndex, int timeSamples, double value, int curveType) {
    if (!_loaded) return 0;
    return _automationAddPluginPoint(trackId, slot, paramIndex, timeSamples, value, curveType);
  }

  /// Get automated plugin parameter value at sample position
  double automationGetPluginValue(int trackId, int slot, int paramIndex, int timeSamples) {
    if (!_loaded) return -1.0;
    return _automationGetPluginValue(trackId, slot, paramIndex, timeSamples);
  }

  /// Clear automation lane for plugin parameter
  void automationClearPluginLane(int trackId, int slot, int paramIndex) {
    if (!_loaded) return;
    _automationClearPluginLane(trackId, slot, paramIndex);
  }

  /// Touch plugin parameter (start automation recording)
  void automationTouchPlugin(int trackId, int slot, int paramIndex, double value) {
    if (!_loaded) return;
    _automationTouchPlugin(trackId, slot, paramIndex, value);
  }

  /// Release plugin parameter (stop automation recording)
  void automationReleasePlugin(int trackId, int slot, int paramIndex) {
    if (!_loaded) return;
    _automationReleasePlugin(trackId, slot, paramIndex);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INSERT EFFECTS API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create insert chain for a track
  void insertCreateChain(int trackId) {
    if (!_loaded) return;
    _insertCreateChain(trackId);
  }

  /// Remove insert chain
  void insertRemoveChain(int trackId) {
    if (!_loaded) return;
    _insertRemoveChain(trackId);
  }

  /// Set insert slot bypass
  void insertSetBypass(int trackId, int slot, bool bypass) {
    if (!_loaded) return;
    _insertSetBypass(trackId, slot, bypass ? 1 : 0);
  }

  /// Set insert slot wet/dry mix
  void insertSetMix(int trackId, int slot, double mix) {
    if (!_loaded) return;
    _insertSetMix(trackId, slot, mix);
  }

  /// Get insert slot wet/dry mix (0.0 = dry, 1.0 = wet)
  double insertGetMix(int trackId, int slot) {
    if (!_loaded) return 1.0;
    return _insertGetMix(trackId, slot);
  }

  /// Bypass all inserts on track
  void insertBypassAll(int trackId, bool bypass) {
    if (!_loaded) return;
    _insertBypassAll(trackId, bypass ? 1 : 0);
  }

  /// Get total latency of insert chain (samples)
  int insertGetTotalLatency(int trackId) {
    if (!_loaded) return 0;
    return _insertGetTotalLatency(trackId);
  }

  /// Load processor into insert slot
  /// Available processors: "pro-eq", "pultec", "api550", "neve1073", "compressor", "limiter", "gate", "expander"
  /// Returns 0 on success, negative on error
  int insertLoadProcessor(int trackId, int slotIndex, String processorName) {
    if (!_loaded) return -1;
    final namePtr = processorName.toNativeUtf8();
    try {
      return _insertLoadProcessor(trackId, slotIndex, namePtr);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Unload processor from insert slot
  /// Returns 0 on success, negative on error
  int insertUnloadSlot(int trackId, int slotIndex) {
    if (!_loaded) return -1;
    return _insertUnloadSlot(trackId, slotIndex);
  }

  /// Set parameter on insert slot processor
  /// Returns 0 on success
  int insertSetParam(int trackId, int slotIndex, int paramIndex, double value) {
    if (!_loaded) return -1;
    print('[NativeFFI] insertSetParam: track=$trackId, slot=$slotIndex, param=$paramIndex, value=${value.toStringAsFixed(3)}');
    return _insertSetParam(trackId, slotIndex, paramIndex, value);
  }

  /// Get parameter from insert slot processor
  double insertGetParam(int trackId, int slotIndex, int paramIndex) {
    if (!_loaded) return 0.0;
    return _insertGetParam(trackId, slotIndex, paramIndex);
  }

  /// Check if insert slot has a processor loaded
  bool insertIsLoaded(int trackId, int slotIndex) {
    if (!_loaded) return false;
    return _insertIsLoaded(trackId, slotIndex) != 0;
  }

  /// Open plugin editor for insert slot
  /// Returns 0 on success, negative on error
  int insertOpenEditor(int trackId, int slotIndex) {
    if (!_loaded) return -1;
    return _insertOpenEditor(trackId, slotIndex);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLUGIN STATE/PRESET API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get plugin state (for saving presets)
  /// Returns null if failed
  Uint8List? pluginGetState(String instanceId) {
    if (!_loaded) return null;
    final idPtr = instanceId.toNativeUtf8();
    try {
      // First get size
      final size = _pluginGetState(idPtr, nullptr, 0);
      if (size <= 0) return null;

      // Allocate buffer and get state
      final bufferPtr = calloc<Uint8>(size);
      try {
        final written = _pluginGetState(idPtr, bufferPtr, size);
        if (written <= 0) return null;
        return Uint8List.fromList(bufferPtr.asTypedList(written));
      } finally {
        calloc.free(bufferPtr);
      }
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Set plugin state (for loading presets)
  /// Returns true on success
  bool pluginSetState(String instanceId, Uint8List state) {
    if (!_loaded || state.isEmpty) return false;
    final idPtr = instanceId.toNativeUtf8();
    final statePtr = calloc<Uint8>(state.length);
    try {
      for (int i = 0; i < state.length; i++) {
        statePtr[i] = state[i];
      }
      return _pluginSetState(idPtr, statePtr, state.length) == 1;
    } finally {
      calloc.free(idPtr);
      calloc.free(statePtr);
    }
  }

  /// Save plugin preset to file
  /// Returns true on success
  bool pluginSavePreset(String instanceId, String path, String presetName) {
    if (!_loaded) return false;
    final idPtr = instanceId.toNativeUtf8();
    final pathPtr = path.toNativeUtf8();
    final namePtr = presetName.toNativeUtf8();
    try {
      return _pluginSavePreset(idPtr, pathPtr, namePtr) == 1;
    } finally {
      calloc.free(idPtr);
      calloc.free(pathPtr);
      calloc.free(namePtr);
    }
  }

  /// Load plugin preset from file
  /// Returns true on success
  bool pluginLoadPreset(String instanceId, String path) {
    if (!_loaded) return false;
    final idPtr = instanceId.toNativeUtf8();
    final pathPtr = path.toNativeUtf8();
    try {
      return _pluginLoadPreset(idPtr, pathPtr) == 1;
    } finally {
      calloc.free(idPtr);
      calloc.free(pathPtr);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRANSIENT DETECTION API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Detect transients in audio buffer
  /// Returns list of transient positions (in samples)
  /// algorithm: 0=HighEmphasis, 1=LowEmphasis, 2=Enhanced, 3=SpectralFlux, 4=ComplexDomain
  List<int> transientDetect(List<double> samples, double sampleRate, {double sensitivity = 0.5, int algorithm = 2, int maxCount = 1000}) {
    if (!_loaded || samples.isEmpty) return [];

    // Allocate native buffers
    final samplesPtr = calloc<Double>(samples.length);
    final outPositionsPtr = calloc<Uint64>(maxCount);

    try {
      // Copy samples to native buffer
      for (int i = 0; i < samples.length; i++) {
        samplesPtr[i] = samples[i];
      }

      final count = _transientDetect(samplesPtr, samples.length, sampleRate, sensitivity, algorithm, outPositionsPtr, maxCount);

      // Read results
      final positions = <int>[];
      for (int i = 0; i < count; i++) {
        positions.add(outPositionsPtr[i]);
      }
      return positions;
    } finally {
      calloc.free(samplesPtr);
      calloc.free(outPositionsPtr);
    }
  }

  /// Detect transients in a clip by clip ID
  /// Returns list of (position, strength) tuples
  /// algorithm: 0=Enhanced, 1=HighEmphasis, 2=LowEmphasis, 3=SpectralFlux, 4=ComplexDomain
  List<({int position, double strength})> detectClipTransients(
    int clipId, {
    double sensitivity = 0.5,
    int algorithm = 0,
    double minGapMs = 20.0,
    int maxCount = 2000,
  }) {
    if (!_loaded) return [];

    final outPositions = calloc<Uint64>(maxCount);
    final outStrengths = calloc<Float>(maxCount);

    try {
      final count = _detectClipTransients(
        clipId,
        sensitivity,
        algorithm,
        minGapMs,
        outPositions,
        outStrengths,
        maxCount,
      );

      final result = <({int position, double strength})>[];
      for (int i = 0; i < count; i++) {
        result.add((position: outPositions[i], strength: outStrengths[i]));
      }
      return result;
    } finally {
      calloc.free(outPositions);
      calloc.free(outStrengths);
    }
  }

  /// Get clip sample rate
  int getClipSampleRate(int clipId) {
    if (!_loaded) return 48000;
    return _getClipSampleRate(clipId);
  }

  /// Get clip total frames
  int getClipTotalFrames(int clipId) {
    if (!_loaded) return 0;
    return _getClipTotalFrames(clipId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PITCH DETECTION API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Detect pitch in audio buffer
  /// Returns frequency in Hz (0.0 if no pitch detected)
  double pitchDetect(List<double> samples, double sampleRate) {
    if (!_loaded || samples.isEmpty) return 0.0;

    final samplesPtr = calloc<Double>(samples.length);
    try {
      for (int i = 0; i < samples.length; i++) {
        samplesPtr[i] = samples[i];
      }
      return _pitchDetect(samplesPtr, samples.length, sampleRate);
    } finally {
      calloc.free(samplesPtr);
    }
  }

  /// Detect pitch and return MIDI note number
  /// Returns -1 if no pitch detected
  int pitchDetectMidi(List<double> samples, double sampleRate) {
    if (!_loaded || samples.isEmpty) return -1;

    final samplesPtr = calloc<Double>(samples.length);
    try {
      for (int i = 0; i < samples.length; i++) {
        samplesPtr[i] = samples[i];
      }
      return _pitchDetectMidi(samplesPtr, samples.length, sampleRate);
    } finally {
      calloc.free(samplesPtr);
    }
  }

  // ============================================================
  // FOLDER TRACK API
  // ============================================================

  late final _folderCreate = _lib.lookupFunction<
      Int32 Function(Uint64, Pointer<Utf8>),
      int Function(int, Pointer<Utf8>)>('folder_create');

  late final _folderDelete = _lib.lookupFunction<
      Int32 Function(Uint64),
      int Function(int)>('folder_delete');

  late final _folderAddChild = _lib.lookupFunction<
      Int32 Function(Uint64, Uint64),
      int Function(int, int)>('folder_add_child');

  late final _folderRemoveChild = _lib.lookupFunction<
      Int32 Function(Uint64, Uint64),
      int Function(int, int)>('folder_remove_child');

  late final _folderToggle = _lib.lookupFunction<
      Int32 Function(Uint64),
      int Function(int)>('folder_toggle');

  late final _folderIsExpanded = _lib.lookupFunction<
      Int32 Function(Uint64),
      int Function(int)>('folder_is_expanded');

  late final _folderGetChildren = _lib.lookupFunction<
      UnsignedLong Function(Uint64, Pointer<Uint64>, UnsignedLong),
      int Function(int, Pointer<Uint64>, int)>('folder_get_children');

  late final _folderGetParent = _lib.lookupFunction<
      Uint64 Function(Uint64),
      int Function(int)>('folder_get_parent');

  late final _folderSetColor = _lib.lookupFunction<
      Int32 Function(Uint64, Uint32),
      int Function(int, int)>('folder_set_color');

  /// Create a folder track
  bool folderCreate(int folderId, String name) {
    if (!_loaded) return false;
    final namePtr = name.toNativeUtf8();
    try {
      return _folderCreate(folderId, namePtr) == 1;
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Delete a folder track
  bool folderDelete(int folderId) {
    if (!_loaded) return false;
    return _folderDelete(folderId) == 1;
  }

  /// Add a track as child of folder
  bool folderAddChild(int folderId, int trackId) {
    if (!_loaded) return false;
    return _folderAddChild(folderId, trackId) == 1;
  }

  /// Remove a track from folder
  bool folderRemoveChild(int folderId, int trackId) {
    if (!_loaded) return false;
    return _folderRemoveChild(folderId, trackId) == 1;
  }

  /// Toggle folder expanded/collapsed
  bool folderToggle(int folderId) {
    if (!_loaded) return false;
    return _folderToggle(folderId) == 1;
  }

  /// Check if folder is expanded
  bool folderIsExpanded(int folderId) {
    if (!_loaded) return false;
    return _folderIsExpanded(folderId) == 1;
  }

  /// Get children track IDs of a folder
  List<int> folderGetChildren(int folderId, {int maxCount = 100}) {
    if (!_loaded) return [];
    final outIds = calloc<Uint64>(maxCount);
    try {
      final count = _folderGetChildren(folderId, outIds, maxCount);
      return List.generate(count, (i) => outIds[i]);
    } finally {
      calloc.free(outIds);
    }
  }

  /// Get parent folder of a track (0 if no parent)
  int folderGetParent(int trackId) {
    if (!_loaded) return 0;
    return _folderGetParent(trackId);
  }

  /// Set folder color
  bool folderSetColor(int folderId, int color) {
    if (!_loaded) return false;
    return _folderSetColor(folderId, color) == 1;
  }

  // ============================================================
  // VCA ADVANCED API
  // ============================================================

  late final _vcaSetColor = _lib.lookupFunction<
      Int32 Function(Uint64, Uint32),
      int Function(int, int)>('vca_set_color');

  late final _vcaSetTrim = _lib.lookupFunction<
      Int32 Function(Uint64, Uint64, Double),
      int Function(int, int, double)>('vca_set_trim');

  late final _vcaGetMemberCount = _lib.lookupFunction<
      UnsignedLong Function(Uint64),
      int Function(int)>('vca_get_member_count');

  late final _vcaGetMembers = _lib.lookupFunction<
      UnsignedLong Function(Uint64, Pointer<Uint64>, UnsignedLong),
      int Function(int, Pointer<Uint64>, int)>('vca_get_members');

  late final _vcaGetAll = _lib.lookupFunction<
      UnsignedLong Function(Pointer<Uint64>, UnsignedLong),
      int Function(Pointer<Uint64>, int)>('vca_get_all');

  late final _vcaIsMuted = _lib.lookupFunction<
      Int32 Function(Uint64),
      int Function(int)>('vca_is_track_muted');

  late final _vcaGetTrackContribution = _lib.lookupFunction<
      Double Function(Uint64),
      double Function(int)>('vca_get_track_contribution');

  late final _vcaSetSolo = _lib.lookupFunction<
      Int32 Function(Uint64, Int32),
      int Function(int, int)>('vca_set_solo');

  /// Set VCA color
  bool vcaSetColor(int vcaId, int color) {
    if (!_loaded) return false;
    return _vcaSetColor(vcaId, color) == 1;
  }

  /// Set per-track trim within VCA
  bool vcaSetTrim(int vcaId, int trackId, double trimDb) {
    if (!_loaded) return false;
    return _vcaSetTrim(vcaId, trackId, trimDb) == 1;
  }

  /// Get member count of VCA
  int vcaGetMemberCount(int vcaId) {
    if (!_loaded) return 0;
    return _vcaGetMemberCount(vcaId);
  }

  /// Get all member track IDs of VCA
  List<int> vcaGetMembers(int vcaId, {int maxCount = 100}) {
    if (!_loaded) return [];
    final outIds = calloc<Uint64>(maxCount);
    try {
      final count = _vcaGetMembers(vcaId, outIds, maxCount);
      return List.generate(count, (i) => outIds[i]);
    } finally {
      calloc.free(outIds);
    }
  }

  /// Get all VCA IDs
  List<int> vcaGetAll({int maxCount = 32}) {
    if (!_loaded) return [];
    final outIds = calloc<Uint64>(maxCount);
    try {
      final count = _vcaGetAll(outIds, maxCount);
      return List.generate(count, (i) => outIds[i]);
    } finally {
      calloc.free(outIds);
    }
  }

  /// Check if track is muted via VCA
  bool vcaIsTrackMuted(int trackId) {
    if (!_loaded) return false;
    return _vcaIsMuted(trackId) == 1;
  }

  /// Get track's contribution from VCA (dB offset)
  double vcaGetTrackContribution(int trackId) {
    if (!_loaded) return 0.0;
    return _vcaGetTrackContribution(trackId);
  }

  /// Set VCA solo
  bool vcaSetSolo(int vcaId, bool solo) {
    if (!_loaded) return false;
    return _vcaSetSolo(vcaId, solo ? 1 : 0) == 1;
  }

  // ============================================================
  // GROUP LINKING API
  // ============================================================

  late final _groupToggleLink = _lib.lookupFunction<
      Int32 Function(Uint64, Uint8),
      int Function(int, int)>('group_toggle_link');

  late final _groupIsParamLinked = _lib.lookupFunction<
      Int32 Function(Uint64, Uint8),
      int Function(int, int)>('group_is_param_linked');

  late final _groupGetLinkedTracks = _lib.lookupFunction<
      UnsignedLong Function(Uint64, Pointer<Uint64>, UnsignedLong),
      int Function(int, Pointer<Uint64>, int)>('group_get_linked_tracks');

  late final _groupSetColor = _lib.lookupFunction<
      Int32 Function(Uint64, Uint32),
      int Function(int, int)>('group_set_color');

  late final _groupSetActive = _lib.lookupFunction<
      Int32 Function(Uint64, Int32),
      int Function(int, int)>('group_set_active');

  /// Toggle link for a parameter type
  /// param: 0=Volume, 1=Pan, 2=Mute, 3=Solo, 4=Sends, 5=Inserts, 6=EQ, 7=Edit
  bool groupToggleLink(int groupId, int param) {
    if (!_loaded) return false;
    return _groupToggleLink(groupId, param) == 1;
  }

  /// Check if parameter is linked
  bool groupIsParamLinked(int groupId, int param) {
    if (!_loaded) return false;
    return _groupIsParamLinked(groupId, param) == 1;
  }

  /// Get all tracks in group
  List<int> groupGetLinkedTracks(int groupId, {int maxCount = 100}) {
    if (!_loaded) return [];
    final outIds = calloc<Uint64>(maxCount);
    try {
      final count = _groupGetLinkedTracks(groupId, outIds, maxCount);
      return List.generate(count, (i) => outIds[i]);
    } finally {
      calloc.free(outIds);
    }
  }

  /// Set group color
  bool groupSetColor(int groupId, int color) {
    if (!_loaded) return false;
    return _groupSetColor(groupId, color) == 1;
  }

  /// Set group active state
  bool groupSetActive(int groupId, bool active) {
    if (!_loaded) return false;
    return _groupSetActive(groupId, active ? 1 : 0) == 1;
  }


  // ============================================================
  // BUS VOLUME/PAN API (legacy engine_set_bus_*)
  // ============================================================

  late final _engineSetBusVolume = _lib.lookupFunction<
      Void Function(Int32, Double),
      void Function(int, double)>('engine_set_bus_volume');

  late final _engineSetBusPan = _lib.lookupFunction<
      Void Function(Int32, Double),
      void Function(int, double)>('engine_set_bus_pan');

  late final _engineSetBusMute = _lib.lookupFunction<
      Void Function(Int32, Int32),
      void Function(int, int)>('engine_set_bus_mute');

  late final _engineSetBusSolo = _lib.lookupFunction<
      Void Function(Int32, Int32),
      void Function(int, int)>('engine_set_bus_solo');

  late final _engineGetBusVolume = _lib.lookupFunction<
      Double Function(Int32),
      double Function(int)>('engine_get_bus_volume');

  late final _engineGetBusMute = _lib.lookupFunction<
      Int32 Function(Int32),
      int Function(int)>('engine_get_bus_mute');

  late final _engineGetBusSolo = _lib.lookupFunction<
      Int32 Function(Int32),
      int Function(int)>('engine_get_bus_solo');

  /// Set bus volume (0.0-1.0 linear)
  void setBusVolume(int busIdx, double volume) {
    if (!_loaded) return;
    _engineSetBusVolume(busIdx, volume);
  }

  /// Set bus pan (-1.0 to 1.0)
  void setBusPan(int busIdx, double pan) {
    if (!_loaded) return;
    _engineSetBusPan(busIdx, pan);
  }

  /// Set bus mute
  void setBusMute(int busIdx, bool muted) {
    if (!_loaded) return;
    _engineSetBusMute(busIdx, muted ? 1 : 0);
  }

  /// Set bus solo
  void setBusSolo(int busIdx, bool solo) {
    if (!_loaded) return;
    _engineSetBusSolo(busIdx, solo ? 1 : 0);
  }

  /// Get bus volume
  double getBusVolume(int busIdx) {
    if (!_loaded) return 0.0;
    return _engineGetBusVolume(busIdx);
  }

  /// Get bus mute state
  bool getBusMute(int busIdx) {
    if (!_loaded) return false;
    return _engineGetBusMute(busIdx) == 1;
  }

  /// Get bus solo state
  bool getBusSolo(int busIdx) {
    if (!_loaded) return false;
    return _engineGetBusSolo(busIdx) == 1;
  }

  // ============================================================
  // ELASTIC PRO (TIME STRETCHING) API
  // ============================================================

  late final _elasticCreate = _lib.lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('elastic_create');

  late final _elasticRemove = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('elastic_remove');

  late final _elasticSetRatio = _lib.lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('elastic_set_ratio');

  late final _elasticSetPitch = _lib.lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('elastic_set_pitch');

  late final _elasticSetQuality = _lib.lookupFunction<
      Int32 Function(Uint32, Uint8),
      int Function(int, int)>('elastic_set_quality');

  late final _elasticSetMode = _lib.lookupFunction<
      Int32 Function(Uint32, Uint8),
      int Function(int, int)>('elastic_set_mode');

  late final _elasticSetStnEnabled = _lib.lookupFunction<
      Int32 Function(Uint32, Int32),
      int Function(int, int)>('elastic_set_stn_enabled');

  late final _elasticSetPreserveTransients = _lib.lookupFunction<
      Int32 Function(Uint32, Int32),
      int Function(int, int)>('elastic_set_preserve_transients');

  late final _elasticSetPreserveFormants = _lib.lookupFunction<
      Int32 Function(Uint32, Int32),
      int Function(int, int)>('elastic_set_preserve_formants');

  late final _elasticSetTonalThreshold = _lib.lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('elastic_set_tonal_threshold');

  late final _elasticSetTransientThreshold = _lib.lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('elastic_set_transient_threshold');

  late final _elasticGetOutputLength = _lib.lookupFunction<
      Uint32 Function(Uint32, Uint32),
      int Function(int, int)>('elastic_get_output_length');

  late final _elasticGetRatio = _lib.lookupFunction<
      Double Function(Uint32),
      double Function(int)>('elastic_get_ratio');

  late final _elasticGetPitch = _lib.lookupFunction<
      Double Function(Uint32),
      double Function(int)>('elastic_get_pitch');

  late final _elasticReset = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('elastic_reset');

  late final _elasticProcess = _lib.lookupFunction<
      Uint32 Function(Uint32, Pointer<Double>, Uint32, Pointer<Double>, Uint32),
      int Function(int, Pointer<Double>, int, Pointer<Double>, int)>('elastic_process');

  late final _elasticProcessStereo = _lib.lookupFunction<
      Uint32 Function(Uint32, Pointer<Double>, Pointer<Double>, Uint32, Pointer<Double>, Pointer<Double>, Uint32),
      int Function(int, Pointer<Double>, Pointer<Double>, int, Pointer<Double>, Pointer<Double>, int)>('elastic_process_stereo');

  /// Create time stretch processor for clip
  bool elasticCreate(int clipId, double sampleRate) {
    if (!_loaded) return false;
    return _elasticCreate(clipId, sampleRate) == 1;
  }

  /// Remove time stretch processor
  bool elasticRemove(int clipId) {
    if (!_loaded) return false;
    return _elasticRemove(clipId) == 1;
  }

  /// Set stretch ratio (0.1 to 10.0, 1.0 = no change)
  bool elasticSetRatio(int clipId, double ratio) {
    if (!_loaded) return false;
    return _elasticSetRatio(clipId, ratio) == 1;
  }

  /// Set pitch shift in semitones (-24 to +24)
  bool elasticSetPitch(int clipId, double semitones) {
    if (!_loaded) return false;
    return _elasticSetPitch(clipId, semitones) == 1;
  }

  /// Set quality preset
  /// 0=Preview, 1=Standard, 2=High, 3=Ultra
  bool elasticSetQuality(int clipId, int quality) {
    if (!_loaded) return false;
    return _elasticSetQuality(clipId, quality) == 1;
  }

  /// Set algorithm mode
  /// 0=Auto, 1=Polyphonic, 2=Monophonic, 3=Rhythmic, 4=Speech, 5=Creative
  bool elasticSetMode(int clipId, int mode) {
    if (!_loaded) return false;
    return _elasticSetMode(clipId, mode) == 1;
  }

  /// Enable/disable STN decomposition
  bool elasticSetStnEnabled(int clipId, bool enabled) {
    if (!_loaded) return false;
    return _elasticSetStnEnabled(clipId, enabled ? 1 : 0) == 1;
  }

  /// Enable/disable transient preservation
  bool elasticSetPreserveTransients(int clipId, bool enabled) {
    if (!_loaded) return false;
    return _elasticSetPreserveTransients(clipId, enabled ? 1 : 0) == 1;
  }

  /// Enable/disable formant preservation (for voice)
  bool elasticSetPreserveFormants(int clipId, bool enabled) {
    if (!_loaded) return false;
    return _elasticSetPreserveFormants(clipId, enabled ? 1 : 0) == 1;
  }

  /// Set tonal threshold (0.0-1.0)
  bool elasticSetTonalThreshold(int clipId, double threshold) {
    if (!_loaded) return false;
    return _elasticSetTonalThreshold(clipId, threshold) == 1;
  }

  /// Set transient threshold (0.0-1.0)
  bool elasticSetTransientThreshold(int clipId, double threshold) {
    if (!_loaded) return false;
    return _elasticSetTransientThreshold(clipId, threshold) == 1;
  }

  /// Get expected output length for given input length
  int elasticGetOutputLength(int clipId, int inputLength) {
    if (!_loaded) return inputLength;
    return _elasticGetOutputLength(clipId, inputLength);
  }

  /// Get current stretch ratio
  double elasticGetRatio(int clipId) {
    if (!_loaded) return 1.0;
    return _elasticGetRatio(clipId);
  }

  /// Get current pitch shift in semitones
  double elasticGetPitch(int clipId) {
    if (!_loaded) return 0.0;
    return _elasticGetPitch(clipId);
  }

  /// Reset elastic processor state
  bool elasticReset(int clipId) {
    if (!_loaded) return false;
    return _elasticReset(clipId) == 1;
  }

  /// Process mono audio through time stretch
  /// Returns the processed audio or null on error
  Float64List? elasticProcess(int clipId, Float64List input, {int maxOutputLength = 0}) {
    if (!_loaded || input.isEmpty) return null;
    final outputLen = maxOutputLength > 0 ? maxOutputLength : (input.length * 4); // 4x buffer for safety
    final inputPtr = calloc<Double>(input.length);
    final outputPtr = calloc<Double>(outputLen);
    try {
      for (int i = 0; i < input.length; i++) {
        inputPtr[i] = input[i];
      }
      final written = _elasticProcess(clipId, inputPtr, input.length, outputPtr, outputLen);
      if (written <= 0) return null;
      return Float64List.fromList(outputPtr.asTypedList(written));
    } finally {
      calloc.free(inputPtr);
      calloc.free(outputPtr);
    }
  }

  /// Process stereo audio through time stretch
  /// Returns (left, right) processed audio or null on error
  (Float64List, Float64List)? elasticProcessStereo(int clipId, Float64List inputL, Float64List inputR, {int maxOutputLength = 0}) {
    if (!_loaded || inputL.isEmpty || inputR.isEmpty || inputL.length != inputR.length) return null;
    final outputLen = maxOutputLength > 0 ? maxOutputLength : (inputL.length * 4);
    final inputLPtr = calloc<Double>(inputL.length);
    final inputRPtr = calloc<Double>(inputR.length);
    final outputLPtr = calloc<Double>(outputLen);
    final outputRPtr = calloc<Double>(outputLen);
    try {
      for (int i = 0; i < inputL.length; i++) {
        inputLPtr[i] = inputL[i];
        inputRPtr[i] = inputR[i];
      }
      final written = _elasticProcessStereo(clipId, inputLPtr, inputRPtr, inputL.length, outputLPtr, outputRPtr, outputLen);
      if (written <= 0) return null;
      return (
        Float64List.fromList(outputLPtr.asTypedList(written)),
        Float64List.fromList(outputRPtr.asTypedList(written)),
      );
    } finally {
      calloc.free(inputLPtr);
      calloc.free(inputRPtr);
      calloc.free(outputLPtr);
      calloc.free(outputRPtr);
    }
  }

  // ============================================================
  // PIANO ROLL API
  // ============================================================

  late final _pianoRollCreate = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('piano_roll_create');

  late final _pianoRollRemove = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('piano_roll_remove');

  late final _pianoRollAddNote = _lib.lookupFunction<
      Uint64 Function(Uint32, Uint8, Uint64, Uint64, Uint16),
      int Function(int, int, int, int, int)>('piano_roll_add_note');

  late final _pianoRollRemoveNote = _lib.lookupFunction<
      Int32 Function(Uint32, Uint64),
      int Function(int, int)>('piano_roll_remove_note');

  late final _pianoRollSelect = _lib.lookupFunction<
      Int32 Function(Uint32, Uint64, Int32),
      int Function(int, int, int)>('piano_roll_select');

  late final _pianoRollDeselectAll = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('piano_roll_deselect_all');

  late final _pianoRollSelectAll = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('piano_roll_select_all');

  late final _pianoRollSelectRect = _lib.lookupFunction<
      Int32 Function(Uint32, Uint64, Uint64, Uint8, Uint8, Int32),
      int Function(int, int, int, int, int, int)>('piano_roll_select_rect');

  late final _pianoRollMoveSelected = _lib.lookupFunction<
      Int32 Function(Uint32, Int64, Int8),
      int Function(int, int, int)>('piano_roll_move_selected');

  late final _pianoRollResizeSelected = _lib.lookupFunction<
      Int32 Function(Uint32, Int64, Int32),
      int Function(int, int, int)>('piano_roll_resize_selected');

  late final _pianoRollSetVelocity = _lib.lookupFunction<
      Int32 Function(Uint32, Uint16),
      int Function(int, int)>('piano_roll_set_velocity');

  late final _pianoRollQuantize = _lib.lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('piano_roll_quantize');

  late final _pianoRollTranspose = _lib.lookupFunction<
      Int32 Function(Uint32, Int8),
      int Function(int, int)>('piano_roll_transpose');

  late final _pianoRollCopy = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('piano_roll_copy');

  late final _pianoRollCut = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('piano_roll_cut');

  late final _pianoRollPaste = _lib.lookupFunction<
      Int32 Function(Uint32, Uint64),
      int Function(int, int)>('piano_roll_paste');

  late final _pianoRollDuplicate = _lib.lookupFunction<
      Int32 Function(Uint32, Uint64),
      int Function(int, int)>('piano_roll_duplicate');

  late final _pianoRollDeleteSelected = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('piano_roll_delete_selected');

  late final _pianoRollUndo = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('piano_roll_undo');

  late final _pianoRollRedo = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('piano_roll_redo');

  late final _pianoRollSetGrid = _lib.lookupFunction<
      Int32 Function(Uint32, Uint32),
      int Function(int, int)>('piano_roll_set_grid');

  late final _pianoRollSetSnap = _lib.lookupFunction<
      Int32 Function(Uint32, Int32),
      int Function(int, int)>('piano_roll_set_snap');

  late final _pianoRollSetTool = _lib.lookupFunction<
      Int32 Function(Uint32, Uint32),
      int Function(int, int)>('piano_roll_set_tool');

  late final _pianoRollSetLength = _lib.lookupFunction<
      Int32 Function(Uint32, Uint64),
      int Function(int, int)>('piano_roll_set_length');

  late final _pianoRollGetNoteCount = _lib.lookupFunction<
      Uint32 Function(Uint32),
      int Function(int)>('piano_roll_get_note_count');

  late final _pianoRollGetSelectionCount = _lib.lookupFunction<
      Uint32 Function(Uint32),
      int Function(int)>('piano_roll_get_selection_count');

  late final _pianoRollGetNote = _lib.lookupFunction<
      Int32 Function(Uint32, Uint32, Pointer<Uint64>, Pointer<Uint8>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint16>, Pointer<Int32>, Pointer<Int32>),
      int Function(int, int, Pointer<Uint64>, Pointer<Uint8>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint16>, Pointer<Int32>, Pointer<Int32>)>('piano_roll_get_note');

  late final _pianoRollNoteAt = _lib.lookupFunction<
      Uint64 Function(Uint32, Uint64, Uint8),
      int Function(int, int, int)>('piano_roll_note_at');

  late final _pianoRollSetZoom = _lib.lookupFunction<
      Int32 Function(Uint32, Double, Double),
      int Function(int, double, double)>('piano_roll_set_zoom');

  late final _pianoRollSetScroll = _lib.lookupFunction<
      Int32 Function(Uint32, Uint64, Uint8),
      int Function(int, int, int)>('piano_roll_set_scroll');

  late final _pianoRollCanUndo = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('piano_roll_can_undo');

  late final _pianoRollCanRedo = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('piano_roll_can_redo');

  /// Create piano roll state for clip
  bool pianoRollCreate(int clipId) {
    if (!_loaded) return false;
    return _pianoRollCreate(clipId) == 1;
  }

  /// Remove piano roll state
  bool pianoRollRemove(int clipId) {
    if (!_loaded) return false;
    return _pianoRollRemove(clipId) == 1;
  }

  /// Add note to piano roll
  int pianoRollAddNote(int clipId, int note, int startTick, int duration, int velocity) {
    if (!_loaded) return 0;
    return _pianoRollAddNote(clipId, note, startTick, duration, velocity);
  }

  /// Remove note by ID
  bool pianoRollRemoveNote(int clipId, int noteId) {
    if (!_loaded) return false;
    return _pianoRollRemoveNote(clipId, noteId) == 1;
  }

  /// Select note
  bool pianoRollSelect(int clipId, int noteId, {bool addToSelection = false}) {
    if (!_loaded) return false;
    return _pianoRollSelect(clipId, noteId, addToSelection ? 1 : 0) == 1;
  }

  /// Deselect all
  bool pianoRollDeselectAll(int clipId) {
    if (!_loaded) return false;
    return _pianoRollDeselectAll(clipId) == 1;
  }

  /// Select all
  bool pianoRollSelectAll(int clipId) {
    if (!_loaded) return false;
    return _pianoRollSelectAll(clipId) == 1;
  }

  /// Select rectangle
  bool pianoRollSelectRect(int clipId, int tickStart, int tickEnd, int noteLow, int noteHigh, {bool add = false}) {
    if (!_loaded) return false;
    return _pianoRollSelectRect(clipId, tickStart, tickEnd, noteLow, noteHigh, add ? 1 : 0) == 1;
  }

  /// Move selected notes
  bool pianoRollMoveSelected(int clipId, int deltaTick, int deltaNote) {
    if (!_loaded) return false;
    return _pianoRollMoveSelected(clipId, deltaTick, deltaNote) == 1;
  }

  /// Resize selected notes
  bool pianoRollResizeSelected(int clipId, int deltaDuration, {bool fromStart = false}) {
    if (!_loaded) return false;
    return _pianoRollResizeSelected(clipId, deltaDuration, fromStart ? 1 : 0) == 1;
  }

  /// Set velocity for selected notes
  bool pianoRollSetVelocity(int clipId, int velocity) {
    if (!_loaded) return false;
    return _pianoRollSetVelocity(clipId, velocity) == 1;
  }

  /// Quantize selected notes
  bool pianoRollQuantize(int clipId, double strength) {
    if (!_loaded) return false;
    return _pianoRollQuantize(clipId, strength) == 1;
  }

  /// Transpose selected notes
  bool pianoRollTranspose(int clipId, int semitones) {
    if (!_loaded) return false;
    return _pianoRollTranspose(clipId, semitones) == 1;
  }

  /// Copy selected notes
  bool pianoRollCopy(int clipId) {
    if (!_loaded) return false;
    return _pianoRollCopy(clipId) == 1;
  }

  /// Cut selected notes
  bool pianoRollCut(int clipId) {
    if (!_loaded) return false;
    return _pianoRollCut(clipId) == 1;
  }

  /// Paste notes at position
  bool pianoRollPaste(int clipId, int tick) {
    if (!_loaded) return false;
    return _pianoRollPaste(clipId, tick) == 1;
  }

  /// Duplicate selected notes
  bool pianoRollDuplicate(int clipId, int offsetTicks) {
    if (!_loaded) return false;
    return _pianoRollDuplicate(clipId, offsetTicks) == 1;
  }

  /// Delete selected notes
  bool pianoRollDeleteSelected(int clipId) {
    if (!_loaded) return false;
    return _pianoRollDeleteSelected(clipId) == 1;
  }

  /// Undo
  bool pianoRollUndo(int clipId) {
    if (!_loaded) return false;
    return _pianoRollUndo(clipId) == 1;
  }

  /// Redo
  bool pianoRollRedo(int clipId) {
    if (!_loaded) return false;
    return _pianoRollRedo(clipId) == 1;
  }

  /// Set grid division (0=Bar, 1=Half, 2=Quarter, 3=Eighth, 4=16th, 5=32nd, 6=8T, 7=16T)
  bool pianoRollSetGrid(int clipId, int gridIndex) {
    if (!_loaded) return false;
    return _pianoRollSetGrid(clipId, gridIndex) == 1;
  }

  /// Set snap enabled
  bool pianoRollSetSnap(int clipId, bool enabled) {
    if (!_loaded) return false;
    return _pianoRollSetSnap(clipId, enabled ? 1 : 0) == 1;
  }

  /// Set tool (0=Select, 1=Draw, 2=Erase, 3=Velocity, 4=Slice, 5=Glue, 6=Mute)
  bool pianoRollSetTool(int clipId, int toolIndex) {
    if (!_loaded) return false;
    return _pianoRollSetTool(clipId, toolIndex) == 1;
  }

  /// Set clip length in ticks
  bool pianoRollSetLength(int clipId, int lengthTicks) {
    if (!_loaded) return false;
    return _pianoRollSetLength(clipId, lengthTicks) == 1;
  }

  /// Get note count
  int pianoRollGetNoteCount(int clipId) {
    if (!_loaded) return 0;
    return _pianoRollGetNoteCount(clipId);
  }

  /// Get selection count
  int pianoRollGetSelectionCount(int clipId) {
    if (!_loaded) return 0;
    return _pianoRollGetSelectionCount(clipId);
  }

  /// Get note at index
  PianoRollNote? pianoRollGetNote(int clipId, int index) {
    if (!_loaded) return null;

    final outId = calloc<Uint64>();
    final outNote = calloc<Uint8>();
    final outStartTick = calloc<Uint64>();
    final outDuration = calloc<Uint64>();
    final outVelocity = calloc<Uint16>();
    final outSelected = calloc<Int32>();
    final outMuted = calloc<Int32>();

    try {
      final result = _pianoRollGetNote(
        clipId, index,
        outId, outNote, outStartTick, outDuration, outVelocity, outSelected, outMuted,
      );

      if (result == 1) {
        return PianoRollNote(
          id: outId.value,
          note: outNote.value,
          startTick: outStartTick.value,
          duration: outDuration.value,
          velocity: outVelocity.value,
          selected: outSelected.value == 1,
          muted: outMuted.value == 1,
        );
      }
      return null;
    } finally {
      calloc.free(outId);
      calloc.free(outNote);
      calloc.free(outStartTick);
      calloc.free(outDuration);
      calloc.free(outVelocity);
      calloc.free(outSelected);
      calloc.free(outMuted);
    }
  }

  /// Get all notes for clip
  List<PianoRollNote> pianoRollGetAllNotes(int clipId) {
    final notes = <PianoRollNote>[];
    final count = pianoRollGetNoteCount(clipId);
    for (int i = 0; i < count; i++) {
      final note = pianoRollGetNote(clipId, i);
      if (note != null) {
        notes.add(note);
      }
    }
    return notes;
  }

  /// Get note ID at position
  int pianoRollNoteAt(int clipId, int tick, int note) {
    if (!_loaded) return 0;
    return _pianoRollNoteAt(clipId, tick, note);
  }

  /// Set view zoom
  bool pianoRollSetZoom(int clipId, double pixelsPerBeat, double pixelsPerNote) {
    if (!_loaded) return false;
    return _pianoRollSetZoom(clipId, pixelsPerBeat, pixelsPerNote) == 1;
  }

  /// Set scroll position
  bool pianoRollSetScroll(int clipId, int scrollTick, int scrollNote) {
    if (!_loaded) return false;
    return _pianoRollSetScroll(clipId, scrollTick, scrollNote) == 1;
  }

  /// Can undo?
  bool pianoRollCanUndo(int clipId) {
    if (!_loaded) return false;
    return _pianoRollCanUndo(clipId) == 1;
  }

  /// Can redo?
  bool pianoRollCanRedo(int clipId) {
    if (!_loaded) return false;
    return _pianoRollCanRedo(clipId) == 1;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO DEVICE ENUMERATION
  // ═══════════════════════════════════════════════════════════════════════════

  late final _audioGetOutputDeviceCount = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('audio_get_output_device_count');

  late final _audioGetInputDeviceCount = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('audio_get_input_device_count');

  late final _audioGetOutputDeviceName = _lib.lookupFunction<
      Pointer<Utf8> Function(Int32),
      Pointer<Utf8> Function(int)>('audio_get_output_device_name');

  late final _audioGetInputDeviceName = _lib.lookupFunction<
      Pointer<Utf8> Function(Int32),
      Pointer<Utf8> Function(int)>('audio_get_input_device_name');

  late final _audioIsOutputDeviceDefault = _lib.lookupFunction<
      Int32 Function(Int32),
      int Function(int)>('audio_is_output_device_default');

  late final _audioIsInputDeviceDefault = _lib.lookupFunction<
      Int32 Function(Int32),
      int Function(int)>('audio_is_input_device_default');

  late final _audioGetOutputDeviceChannels = _lib.lookupFunction<
      Int32 Function(Int32),
      int Function(int)>('audio_get_output_device_channels');

  late final _audioGetInputDeviceChannels = _lib.lookupFunction<
      Int32 Function(Int32),
      int Function(int)>('audio_get_input_device_channels');

  late final _audioGetOutputDeviceSampleRateCount = _lib.lookupFunction<
      Int32 Function(Int32),
      int Function(int)>('audio_get_output_device_sample_rate_count');

  late final _audioGetOutputDeviceSampleRate = _lib.lookupFunction<
      Int32 Function(Int32, Int32),
      int Function(int, int)>('audio_get_output_device_sample_rate');

  late final _audioGetHostName = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('audio_get_host_name');

  late final _audioIsAsioAvailable = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('audio_is_asio_available');

  late final _audioRefreshDevices = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('audio_refresh_devices');

  int audioGetOutputDeviceCount() => _audioGetOutputDeviceCount();
  int audioGetInputDeviceCount() => _audioGetInputDeviceCount();
  Pointer<Utf8> audioGetOutputDeviceName(int index) => _audioGetOutputDeviceName(index);
  Pointer<Utf8> audioGetInputDeviceName(int index) => _audioGetInputDeviceName(index);
  int audioIsOutputDeviceDefault(int index) => _audioIsOutputDeviceDefault(index);
  int audioIsInputDeviceDefault(int index) => _audioIsInputDeviceDefault(index);
  int audioGetOutputDeviceChannels(int index) => _audioGetOutputDeviceChannels(index);
  int audioGetInputDeviceChannels(int index) => _audioGetInputDeviceChannels(index);
  int audioGetOutputDeviceSampleRateCount(int index) => _audioGetOutputDeviceSampleRateCount(index);
  int audioGetOutputDeviceSampleRate(int deviceIndex, int rateIndex) => _audioGetOutputDeviceSampleRate(deviceIndex, rateIndex);
  Pointer<Utf8> audioGetHostName() => _audioGetHostName();
  int audioIsAsioAvailable() => _audioIsAsioAvailable();
  int audioRefreshDevices() => _audioRefreshDevices();

  // Audio device setters
  late final _audioSetOutputDevice = _lib.lookupFunction<
      Int32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('audio_set_output_device');

  late final _audioSetInputDevice = _lib.lookupFunction<
      Int32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('audio_set_input_device');

  late final _audioSetSampleRate = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('audio_set_sample_rate');

  late final _audioSetBufferSize = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('audio_set_buffer_size');

  late final _audioGetCurrentOutputDevice = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('audio_get_current_output_device');

  late final _audioGetCurrentInputDevice = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('audio_get_current_input_device');

  late final _audioGetCurrentSampleRate = _lib.lookupFunction<
      Uint32 Function(),
      int Function()>('audio_get_current_sample_rate');

  late final _audioGetCurrentBufferSize = _lib.lookupFunction<
      Uint32 Function(),
      int Function()>('audio_get_current_buffer_size');

  late final _audioGetLatencyMs = _lib.lookupFunction<
      Double Function(),
      double Function()>('audio_get_latency_ms');

  int audioSetOutputDevice(Pointer<Utf8> name) => _audioSetOutputDevice(name);
  int audioSetInputDevice(Pointer<Utf8> name) => _audioSetInputDevice(name);
  int audioSetSampleRate(int rate) => _audioSetSampleRate(rate);
  int audioSetBufferSize(int size) => _audioSetBufferSize(size);
  Pointer<Utf8> audioGetCurrentOutputDevice() => _audioGetCurrentOutputDevice();
  Pointer<Utf8> audioGetCurrentInputDevice() => _audioGetCurrentInputDevice();
  int audioGetCurrentSampleRate() => _audioGetCurrentSampleRate();
  int audioGetCurrentBufferSize() => _audioGetCurrentBufferSize();
  double audioGetLatencyMs() => _audioGetLatencyMs();

  // Input level metering for recording
  late final _audioGetInputPeaks = _lib.lookupFunction<
      Int32 Function(Pointer<Double>, Pointer<Double>),
      int Function(Pointer<Double>, Pointer<Double>)>('audio_get_input_peaks');

  /// Get input peak levels (L, R) for recording meters
  (double, double) getInputPeaks() {
    final peakL = calloc<Double>();
    final peakR = calloc<Double>();
    try {
      final result = _audioGetInputPeaks(peakL, peakR);
      if (result == 1) {
        return (peakL.value, peakR.value);
      }
      return (0.0, 0.0);
    } finally {
      calloc.free(peakL);
      calloc.free(peakR);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INPUT MONITORING
  // ═══════════════════════════════════════════════════════════════════════════

  late final _audioSetInputMonitoring = _lib.lookupFunction<
      Void Function(Int32),
      void Function(int)>('audio_set_input_monitoring');

  late final _audioGetInputMonitoring = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('audio_get_input_monitoring');

  /// Enable/disable input monitoring (hear input through output)
  void setInputMonitoring(bool enabled) {
    if (!_loaded) return;
    _audioSetInputMonitoring(enabled ? 1 : 0);
  }

  /// Check if input monitoring is enabled
  bool isInputMonitoring() {
    if (!_loaded) return false;
    return _audioGetInputMonitoring() != 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ERROR HANDLING
  // ═══════════════════════════════════════════════════════════════════════════

  late final _getLastError = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('get_last_error');

  late final _hasError = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('has_error');

  late final _ffiClearError = _lib.lookupFunction<
      Void Function(),
      void Function()>('ffi_clear_error');

  /// Get last error as JSON string (returns null pointer if no error)
  Pointer<Utf8> getLastError() => _getLastError();

  /// Check if there is an error pending (1 = yes, 0 = no)
  int hasError() => _hasError();

  /// Clear the last error
  void clearError() => _ffiClearError();

  // ═══════════════════════════════════════════════════════════════════════════
  // EDIT MODE
  // ═══════════════════════════════════════════════════════════════════════════

  late final _editModeSet = _lib.lookupFunction<
      Int32 Function(Int32),
      int Function(int)>('edit_mode_set');

  late final _editModeGet = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('edit_mode_get');

  late final _editModeSetGridResolution = _lib.lookupFunction<
      Int32 Function(Int32),
      int Function(int)>('edit_mode_set_grid_resolution');

  late final _editModeGetGridResolution = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('edit_mode_get_grid_resolution');

  late final _editModeSetGridEnabled = _lib.lookupFunction<
      Int32 Function(Int32),
      int Function(int)>('edit_mode_set_grid_enabled');

  late final _editModeIsGridEnabled = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('edit_mode_is_grid_enabled');

  late final _editModeSetGridStrength = _lib.lookupFunction<
      Int32 Function(Double),
      int Function(double)>('edit_mode_set_grid_strength');

  late final _editModeGetGridStrength = _lib.lookupFunction<
      Double Function(),
      double Function()>('edit_mode_get_grid_strength');

  late final _editModeSetTempo = _lib.lookupFunction<
      Int32 Function(Double),
      int Function(double)>('edit_mode_set_tempo');

  late final _editModeGetTempo = _lib.lookupFunction<
      Double Function(),
      double Function()>('edit_mode_get_tempo');

  late final _editModeSetSampleRate = _lib.lookupFunction<
      Int32 Function(Double),
      int Function(double)>('edit_mode_set_sample_rate');

  late final _editModeSnapToGrid = _lib.lookupFunction<
      Double Function(Double),
      double Function(double)>('edit_mode_snap_to_grid');

  late final _editModeSetTimeSigNum = _lib.lookupFunction<
      Int32 Function(Uint8),
      int Function(int)>('edit_mode_set_time_sig_num');

  late final _editModeSetTimeSigDenom = _lib.lookupFunction<
      Int32 Function(Uint8),
      int Function(int)>('edit_mode_set_time_sig_denom');

  /// Set edit mode (0=Slip, 1=Grid, 2=Shuffle, 3=Spot)
  int editModeSet(int mode) => _editModeSet(mode);

  /// Get current edit mode
  int editModeGet() => _editModeGet();

  /// Set grid resolution
  int editModeSetGridResolution(int resolution) => _editModeSetGridResolution(resolution);

  /// Get current grid resolution
  int editModeGetGridResolution() => _editModeGetGridResolution();

  /// Enable/disable grid
  int editModeSetGridEnabled(bool enabled) => _editModeSetGridEnabled(enabled ? 1 : 0);

  /// Check if grid is enabled
  bool editModeIsGridEnabled() => _editModeIsGridEnabled() != 0;

  /// Set grid strength (0.0-1.0)
  int editModeSetGridStrength(double strength) => _editModeSetGridStrength(strength);

  /// Get grid strength
  double editModeGetGridStrength() => _editModeGetGridStrength();

  /// Set tempo for grid calculations
  int editModeSetTempo(double bpm) => _editModeSetTempo(bpm);

  /// Get current tempo
  double editModeGetTempo() => _editModeGetTempo();

  /// Set sample rate for grid calculations
  int editModeSetSampleRate(double sampleRate) => _editModeSetSampleRate(sampleRate);

  /// Snap time to grid
  double editModeSnapToGrid(double timeSeconds) => _editModeSnapToGrid(timeSeconds);

  /// Set time signature numerator
  int editModeSetTimeSigNum(int num) => _editModeSetTimeSigNum(num);

  /// Set time signature denominator
  int editModeSetTimeSigDenom(int denom) => _editModeSetTimeSigDenom(denom);

  // ═══════════════════════════════════════════════════════════════════════════
  // RECORDING SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  late final _recordingSetOutputDir = _lib.lookupFunction<
      Int32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('recording_set_output_dir');

  late final _recordingGetOutputDir = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('recording_get_output_dir');

  late final _recordingArmTrack = _lib.lookupFunction<
      Int32 Function(Uint64, Uint16),
      int Function(int, int)>('recording_arm_track');

  late final _recordingDisarmTrack = _lib.lookupFunction<
      Int32 Function(Uint64),
      int Function(int)>('recording_disarm_track');

  late final _recordingStartTrack = _lib.lookupFunction<
      Pointer<Utf8> Function(Uint64),
      Pointer<Utf8> Function(int)>('recording_start_track');

  late final _recordingStopTrack = _lib.lookupFunction<
      Pointer<Utf8> Function(Uint64),
      Pointer<Utf8> Function(int)>('recording_stop_track');

  late final _recordingStartAll = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('recording_start_all');

  late final _recordingStopAll = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('recording_stop_all');

  late final _recordingIsArmed = _lib.lookupFunction<
      Int32 Function(Uint64),
      int Function(int)>('recording_is_armed');

  late final _recordingIsRecording = _lib.lookupFunction<
      Int32 Function(Uint64),
      int Function(int)>('recording_is_recording');

  late final _recordingArmedCount = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('recording_armed_count');

  late final _recordingRecordingCount = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('recording_recording_count');

  late final _recordingClearAll = _lib.lookupFunction<
      Void Function(),
      void Function()>('recording_clear_all');

  int recordingSetOutputDir(Pointer<Utf8> path) => _recordingSetOutputDir(path);
  Pointer<Utf8> recordingGetOutputDir() => _recordingGetOutputDir();
  int recordingArmTrack(int trackId, int numChannels) => _recordingArmTrack(trackId, numChannels);
  int recordingDisarmTrack(int trackId) => _recordingDisarmTrack(trackId);
  Pointer<Utf8> recordingStartTrack(int trackId) => _recordingStartTrack(trackId);
  Pointer<Utf8> recordingStopTrack(int trackId) => _recordingStopTrack(trackId);
  int recordingStartAll() => _recordingStartAll();
  int recordingStopAll() => _recordingStopAll();
  int recordingIsArmed(int trackId) => _recordingIsArmed(trackId);
  int recordingIsRecording(int trackId) => _recordingIsRecording(trackId);
  int recordingArmedCount() => _recordingArmedCount();
  int recordingRecordingCount() => _recordingRecordingCount();
  void recordingClearAll() => _recordingClearAll();

  // ─────────────────────────────────────────────────────────────────────────────
  // PUNCH IN/OUT
  // ─────────────────────────────────────────────────────────────────────────────

  late final _recordingSetPunchMode = _lib.lookupFunction<
      Void Function(Uint8), void Function(int)>('recording_set_punch_mode');
  late final _recordingGetPunchMode = _lib.lookupFunction<
      Uint8 Function(), int Function()>('recording_get_punch_mode');
  late final _recordingSetPunchIn = _lib.lookupFunction<
      Void Function(Uint64), void Function(int)>('recording_set_punch_in');
  late final _recordingGetPunchIn = _lib.lookupFunction<
      Uint64 Function(), int Function()>('recording_get_punch_in');
  late final _recordingSetPunchOut = _lib.lookupFunction<
      Void Function(Uint64), void Function(int)>('recording_set_punch_out');
  late final _recordingGetPunchOut = _lib.lookupFunction<
      Uint64 Function(), int Function()>('recording_get_punch_out');
  late final _recordingSetPunchTimes = _lib.lookupFunction<
      Void Function(Double, Double), void Function(double, double)>('recording_set_punch_times');
  late final _recordingIsPunchedIn = _lib.lookupFunction<
      Int32 Function(), int Function()>('recording_is_punched_in');

  void recordingSetPunchMode(int mode) => _recordingSetPunchMode(mode);
  int recordingGetPunchMode() => _recordingGetPunchMode();
  void recordingSetPunchIn(int sample) => _recordingSetPunchIn(sample);
  int recordingGetPunchIn() => _recordingGetPunchIn();
  void recordingSetPunchOut(int sample) => _recordingSetPunchOut(sample);
  int recordingGetPunchOut() => _recordingGetPunchOut();
  void recordingSetPunchTimes(double punchIn, double punchOut) => _recordingSetPunchTimes(punchIn, punchOut);
  bool recordingIsPunchedIn() => _recordingIsPunchedIn() == 1;

  // ─────────────────────────────────────────────────────────────────────────────
  // PRE-ROLL
  // ─────────────────────────────────────────────────────────────────────────────

  late final _recordingSetPreRollEnabled = _lib.lookupFunction<
      Void Function(Int32), void Function(int)>('recording_set_pre_roll_enabled');
  late final _recordingIsPreRollEnabled = _lib.lookupFunction<
      Int32 Function(), int Function()>('recording_is_pre_roll_enabled');
  late final _recordingSetPreRollSeconds = _lib.lookupFunction<
      Void Function(Double), void Function(double)>('recording_set_pre_roll_seconds');
  late final _recordingGetPreRollSamples = _lib.lookupFunction<
      Uint64 Function(), int Function()>('recording_get_pre_roll_samples');
  late final _recordingSetPreRollBars = _lib.lookupFunction<
      Void Function(Uint64), void Function(int)>('recording_set_pre_roll_bars');
  late final _recordingGetPreRollBars = _lib.lookupFunction<
      Uint64 Function(), int Function()>('recording_get_pre_roll_bars');
  late final _recordingPreRollStart = _lib.lookupFunction<
      Uint64 Function(Uint64, Double), int Function(int, double)>('recording_pre_roll_start');

  void recordingSetPreRollEnabled(bool enabled) => _recordingSetPreRollEnabled(enabled ? 1 : 0);
  bool recordingIsPreRollEnabled() => _recordingIsPreRollEnabled() == 1;
  void recordingSetPreRollSeconds(double seconds) => _recordingSetPreRollSeconds(seconds);
  int recordingGetPreRollSamples() => _recordingGetPreRollSamples();
  void recordingSetPreRollBars(int bars) => _recordingSetPreRollBars(bars);
  int recordingGetPreRollBars() => _recordingGetPreRollBars();
  int recordingPreRollStart(int recordStart, double tempo) => _recordingPreRollStart(recordStart, tempo);

  // ─────────────────────────────────────────────────────────────────────────────
  // AUTO-ARM
  // ─────────────────────────────────────────────────────────────────────────────

  late final _recordingSetAutoArmEnabled = _lib.lookupFunction<
      Void Function(Int32), void Function(int)>('recording_set_auto_arm_enabled');
  late final _recordingIsAutoArmEnabled = _lib.lookupFunction<
      Int32 Function(), int Function()>('recording_is_auto_arm_enabled');
  late final _recordingSetAutoArmThresholdDb = _lib.lookupFunction<
      Void Function(Double), void Function(double)>('recording_set_auto_arm_threshold_db');
  late final _recordingGetAutoArmThreshold = _lib.lookupFunction<
      Double Function(), double Function()>('recording_get_auto_arm_threshold');
  late final _recordingAddPendingAutoArm = _lib.lookupFunction<
      Void Function(Uint64), void Function(int)>('recording_add_pending_auto_arm');
  late final _recordingRemovePendingAutoArm = _lib.lookupFunction<
      Void Function(Uint64), void Function(int)>('recording_remove_pending_auto_arm');

  void recordingSetAutoArmEnabled(bool enabled) => _recordingSetAutoArmEnabled(enabled ? 1 : 0);
  bool recordingIsAutoArmEnabled() => _recordingIsAutoArmEnabled() == 1;
  void recordingSetAutoArmThresholdDb(double db) => _recordingSetAutoArmThresholdDb(db);
  double recordingGetAutoArmThreshold() => _recordingGetAutoArmThreshold();
  void recordingAddPendingAutoArm(int trackId) => _recordingAddPendingAutoArm(trackId);
  void recordingRemovePendingAutoArm(int trackId) => _recordingRemovePendingAutoArm(trackId);

  // ═══════════════════════════════════════════════════════════════════════════
  // Unified Routing System
  // ═══════════════════════════════════════════════════════════════════════════

  late final _routingInit = _lib.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('routing_init');

  late final _routingCreateChannel = _lib.lookupFunction<
      Uint32 Function(Uint32, Pointer<Utf8>),
      int Function(int, Pointer<Utf8>)>('routing_create_channel');

  late final _routingDeleteChannel = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('routing_delete_channel');

  late final _routingPollResponse = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('routing_poll_response');

  late final _routingSetOutput = _lib.lookupFunction<
      Int32 Function(Uint32, Uint32, Uint32),
      int Function(int, int, int)>('routing_set_output');

  late final _routingAddSend = _lib.lookupFunction<
      Int32 Function(Uint32, Uint32, Int32),
      int Function(int, int, int)>('routing_add_send');

  late final _routingSetVolume = _lib.lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('routing_set_volume');

  late final _routingSetPan = _lib.lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('routing_set_pan');

  late final _routingSetMute = _lib.lookupFunction<
      Int32 Function(Uint32, Int32),
      int Function(int, int)>('routing_set_mute');

  late final _routingSetSolo = _lib.lookupFunction<
      Int32 Function(Uint32, Int32),
      int Function(int, int)>('routing_set_solo');

  late final _routingGetChannelCount = _lib.lookupFunction<
      Uint32 Function(),
      int Function()>('routing_get_channel_count');

  int routingInit(Pointer<Void> senderPtr) => _routingInit(senderPtr);
  int routingCreateChannel(int kind, Pointer<Utf8> name) => _routingCreateChannel(kind, name);
  int routingDeleteChannel(int channelId) => _routingDeleteChannel(channelId);
  int routingPollResponse(int callbackId) => _routingPollResponse(callbackId);
  int routingSetOutput(int channelId, int destType, int destId) => _routingSetOutput(channelId, destType, destId);
  int routingAddSend(int fromChannel, int toChannel, int preFader) => _routingAddSend(fromChannel, toChannel, preFader);
  int routingSetVolume(int channelId, double volumeDb) => _routingSetVolume(channelId, volumeDb);
  int routingSetPan(int channelId, double pan) => _routingSetPan(channelId, pan);
  int routingSetMute(int channelId, int mute) => _routingSetMute(channelId, mute);
  int routingSetSolo(int channelId, int solo) => _routingSetSolo(channelId, solo);
  int routingGetChannelCount() => _routingGetChannelCount();

  // ═══════════════════════════════════════════════════════════════════════════
  // Control Room System
  // ═══════════════════════════════════════════════════════════════════════════

  late final _controlRoomInit = _lib.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('control_room_init');

  late final _controlRoomSetMonitorSource = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('control_room_set_monitor_source');

  late final _controlRoomGetMonitorSource = _lib.lookupFunction<
      Uint32 Function(),
      int Function()>('control_room_get_monitor_source');

  late final _controlRoomSetMonitorLevel = _lib.lookupFunction<
      Int32 Function(Double),
      int Function(double)>('control_room_set_monitor_level');

  late final _controlRoomGetMonitorLevel = _lib.lookupFunction<
      Double Function(),
      double Function()>('control_room_get_monitor_level');

  late final _controlRoomSetDim = _lib.lookupFunction<
      Int32 Function(Int32),
      int Function(int)>('control_room_set_dim');

  late final _controlRoomGetDim = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('control_room_get_dim');

  late final _controlRoomSetMono = _lib.lookupFunction<
      Int32 Function(Int32),
      int Function(int)>('control_room_set_mono');

  late final _controlRoomGetMono = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('control_room_get_mono');

  late final _controlRoomSetSpeakerSet = _lib.lookupFunction<
      Int32 Function(Uint8),
      int Function(int)>('control_room_set_speaker_set');

  late final _controlRoomGetSpeakerSet = _lib.lookupFunction<
      Uint8 Function(),
      int Function()>('control_room_get_speaker_set');

  late final _controlRoomSetSpeakerLevel = _lib.lookupFunction<
      Int32 Function(Uint8, Double),
      int Function(int, double)>('control_room_set_speaker_level');

  late final _controlRoomSetSoloMode = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('control_room_set_solo_mode');

  late final _controlRoomGetSoloMode = _lib.lookupFunction<
      Uint32 Function(),
      int Function()>('control_room_get_solo_mode');

  late final _controlRoomSoloChannel = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('control_room_solo_channel');

  late final _controlRoomUnsoloChannel = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('control_room_unsolo_channel');

  late final _controlRoomClearSolo = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('control_room_clear_solo');

  late final _controlRoomIsSoloed = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('control_room_is_soloed');

  late final _controlRoomSetCueEnabled = _lib.lookupFunction<
      Int32 Function(Uint8, Int32),
      int Function(int, int)>('control_room_set_cue_enabled');

  late final _controlRoomSetCueLevel = _lib.lookupFunction<
      Int32 Function(Uint8, Double),
      int Function(int, double)>('control_room_set_cue_level');

  late final _controlRoomSetCuePan = _lib.lookupFunction<
      Int32 Function(Uint8, Double),
      int Function(int, double)>('control_room_set_cue_pan');

  late final _controlRoomAddCueSend = _lib.lookupFunction<
      Int32 Function(Uint8, Uint32, Double, Double),
      int Function(int, int, double, double)>('control_room_add_cue_send');

  late final _controlRoomRemoveCueSend = _lib.lookupFunction<
      Int32 Function(Uint8, Uint32),
      int Function(int, int)>('control_room_remove_cue_send');

  late final _controlRoomSetTalkback = _lib.lookupFunction<
      Int32 Function(Int32),
      int Function(int)>('control_room_set_talkback');

  late final _controlRoomSetTalkbackLevel = _lib.lookupFunction<
      Int32 Function(Double),
      int Function(double)>('control_room_set_talkback_level');

  late final _controlRoomSetTalkbackDestinations = _lib.lookupFunction<
      Int32 Function(Uint8),
      int Function(int)>('control_room_set_talkback_destinations');

  late final _controlRoomGetMonitorPeakL = _lib.lookupFunction<
      Double Function(),
      double Function()>('control_room_get_monitor_peak_l');

  late final _controlRoomGetMonitorPeakR = _lib.lookupFunction<
      Double Function(),
      double Function()>('control_room_get_monitor_peak_r');

  int controlRoomInit(Pointer<Void> controlRoomPtr) => _controlRoomInit(controlRoomPtr);
  int controlRoomSetMonitorSource(int source) => _controlRoomSetMonitorSource(source);
  int controlRoomGetMonitorSource() => _controlRoomGetMonitorSource();
  int controlRoomSetMonitorLevel(double levelDb) => _controlRoomSetMonitorLevel(levelDb);
  double controlRoomGetMonitorLevel() => _controlRoomGetMonitorLevel();
  int controlRoomSetDim(int enabled) => _controlRoomSetDim(enabled);
  int controlRoomGetDim() => _controlRoomGetDim();
  int controlRoomSetMono(int enabled) => _controlRoomSetMono(enabled);
  int controlRoomGetMono() => _controlRoomGetMono();
  int controlRoomSetSpeakerSet(int index) => _controlRoomSetSpeakerSet(index);
  int controlRoomGetSpeakerSet() => _controlRoomGetSpeakerSet();
  int controlRoomSetSpeakerLevel(int index, double levelDb) => _controlRoomSetSpeakerLevel(index, levelDb);
  int controlRoomSetSoloMode(int mode) => _controlRoomSetSoloMode(mode);
  int controlRoomGetSoloMode() => _controlRoomGetSoloMode();
  int controlRoomSoloChannel(int channelId) => _controlRoomSoloChannel(channelId);
  int controlRoomUnsoloChannel(int channelId) => _controlRoomUnsoloChannel(channelId);
  int controlRoomClearSolo() => _controlRoomClearSolo();
  int controlRoomIsSoloed(int channelId) => _controlRoomIsSoloed(channelId);
  int controlRoomSetCueEnabled(int cueIndex, int enabled) => _controlRoomSetCueEnabled(cueIndex, enabled);
  int controlRoomSetCueLevel(int cueIndex, double levelDb) => _controlRoomSetCueLevel(cueIndex, levelDb);
  int controlRoomSetCuePan(int cueIndex, double pan) => _controlRoomSetCuePan(cueIndex, pan);
  int controlRoomAddCueSend(int cueIndex, int channelId, double level, double pan) => _controlRoomAddCueSend(cueIndex, channelId, level, pan);
  int controlRoomRemoveCueSend(int cueIndex, int channelId) => _controlRoomRemoveCueSend(cueIndex, channelId);
  int controlRoomSetTalkback(int enabled) => _controlRoomSetTalkback(enabled);
  int controlRoomSetTalkbackLevel(double levelDb) => _controlRoomSetTalkbackLevel(levelDb);
  int controlRoomSetTalkbackDestinations(int destinations) => _controlRoomSetTalkbackDestinations(destinations);
  double controlRoomGetMonitorPeakL() => _controlRoomGetMonitorPeakL();
  double controlRoomGetMonitorPeakR() => _controlRoomGetMonitorPeakR();

  // ═══════════════════════════════════════════════════════════════════════════
  // Export/Bounce System
  // ═══════════════════════════════════════════════════════════════════════════

  late final _bounceStart = _lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Uint8, Uint8, Uint32, Double, Double, Int32, Double),
      int Function(Pointer<Utf8>, int, int, int, double, double, int, double)>('bounce_start');

  late final _bounceGetProgress = _lib.lookupFunction<
      Float Function(),
      double Function()>('bounce_get_progress');

  late final _bounceIsComplete = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('bounce_is_complete');

  late final _bounceWasCancelled = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('bounce_was_cancelled');

  late final _bounceGetSpeedFactor = _lib.lookupFunction<
      Float Function(),
      double Function()>('bounce_get_speed_factor');

  late final _bounceGetEta = _lib.lookupFunction<
      Float Function(),
      double Function()>('bounce_get_eta');

  late final _bounceGetPeakLevel = _lib.lookupFunction<
      Float Function(),
      double Function()>('bounce_get_peak_level');

  late final _bounceCancel = _lib.lookupFunction<
      Void Function(),
      void Function()>('bounce_cancel');

  late final _bounceIsActive = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('bounce_is_active');

  late final _bounceClear = _lib.lookupFunction<
      Void Function(),
      void Function()>('bounce_clear');

  late final _bounceGetOutputPath = _lib.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('bounce_get_output_path');

  int bounceStart(String outputPath, int format, int bitDepth, int sampleRate,
      double startTime, double endTime, bool normalize, double normalizeTarget) {
    final pathPtr = outputPath.toNativeUtf8();
    final result = _bounceStart(pathPtr, format, bitDepth, sampleRate, startTime,
        endTime, normalize ? 1 : 0, normalizeTarget);
    calloc.free(pathPtr);
    return result;
  }

  double bounceGetProgress() => _bounceGetProgress();
  bool bounceIsComplete() => _bounceIsComplete() != 0;
  bool bounceWasCancelled() => _bounceWasCancelled() != 0;
  double bounceGetSpeedFactor() => _bounceGetSpeedFactor();
  double bounceGetEta() => _bounceGetEta();
  double bounceGetPeakLevel() => _bounceGetPeakLevel();
  void bounceCancel() => _bounceCancel();
  bool bounceIsActive() => _bounceIsActive() != 0;
  void bounceClear() => _bounceClear();
  Pointer<Utf8> bounceGetOutputPath() => _bounceGetOutputPath();

  // ═══════════════════════════════════════════════════════════════════════════
  // INPUT BUS SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  late final _inputBusCreateStereo = _lib.lookupFunction<
      Uint32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('input_bus_create_stereo');

  late final _inputBusCreateMono = _lib.lookupFunction<
      Uint32 Function(Pointer<Utf8>, Int32),
      int Function(Pointer<Utf8>, int)>('input_bus_create_mono');

  late final _inputBusDelete = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('input_bus_delete');

  late final _inputBusCount = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('input_bus_count');

  late final _inputBusGetName = _lib.lookupFunction<
      Pointer<Utf8> Function(Uint32),
      Pointer<Utf8> Function(int)>('input_bus_get_name');

  late final _inputBusGetChannels = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('input_bus_get_channels');

  late final _inputBusIsEnabled = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('input_bus_is_enabled');

  late final _inputBusSetEnabled = _lib.lookupFunction<
      Void Function(Uint32, Int32),
      void Function(int, int)>('input_bus_set_enabled');

  late final _inputBusGetPeak = _lib.lookupFunction<
      Float Function(Uint32, Int32),
      double Function(int, int)>('input_bus_get_peak');

  int inputBusCreateStereo(String name) {
    final namePtr = name.toNativeUtf8();
    final result = _inputBusCreateStereo(namePtr);
    calloc.free(namePtr);
    return result;
  }

  int inputBusCreateMono(String name, int hwChannel) {
    final namePtr = name.toNativeUtf8();
    final result = _inputBusCreateMono(namePtr, hwChannel);
    calloc.free(namePtr);
    return result;
  }

  int inputBusDelete(int busId) => _inputBusDelete(busId);
  int inputBusCount() => _inputBusCount();
  Pointer<Utf8> inputBusGetName(int busId) => _inputBusGetName(busId);
  int inputBusGetChannels(int busId) => _inputBusGetChannels(busId);
  int inputBusIsEnabled(int busId) => _inputBusIsEnabled(busId);
  void inputBusSetEnabled(int busId, int enabled) => _inputBusSetEnabled(busId, enabled);
  double inputBusGetPeak(int busId, int channel) => _inputBusGetPeak(busId, channel);

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO EXPORT SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  late final _exportAudio = _lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Int32, Uint32, Double, Double, Int32),
      int Function(Pointer<Utf8>, int, int, double, double, int)>('export_audio');

  late final _exportGetProgress = _lib.lookupFunction<
      Float Function(),
      double Function()>('export_get_progress');

  late final _exportIsExporting = _lib.lookupFunction<
      Int32 Function(),
      int Function()>('export_is_exporting');

  int exportAudio(String outputPath, int format, int sampleRate,
      double startTime, double endTime, bool normalize) {
    final pathPtr = outputPath.toNativeUtf8();
    final result = _exportAudio(pathPtr, format, sampleRate, startTime, endTime, normalize ? 1 : 0);
    calloc.free(pathPtr);
    return result;
  }

  double exportGetProgress() => _exportGetProgress();
  int exportIsExporting() => _exportIsExporting();

  // ═══════════════════════════════════════════════════════════════════════════
  // PITCH ANALYSIS API (Full Clip Analysis)
  // ═══════════════════════════════════════════════════════════════════════════

  late final _pitchAnalyzeClip = _lib.lookupFunction<
      Uint32 Function(Uint64),
      int Function(int)>('pitch_analyze_clip');

  late final _pitchGetSegmentCount = _lib.lookupFunction<
      Uint32 Function(Uint64),
      int Function(int)>('pitch_get_segment_count');

  late final _pitchGetSegments = _lib.lookupFunction<
      Uint32 Function(Uint64, Pointer<Uint32>, Pointer<Uint64>, Pointer<Uint64>,
          Pointer<Uint8>, Pointer<Double>, Pointer<Uint8>, Pointer<Double>,
          Pointer<Double>, Pointer<Int32>, Uint32),
      int Function(int, Pointer<Uint32>, Pointer<Uint64>, Pointer<Uint64>,
          Pointer<Uint8>, Pointer<Double>, Pointer<Uint8>, Pointer<Double>,
          Pointer<Double>, Pointer<Int32>, int)>('pitch_get_segments');

  late final _pitchSetSegmentShift = _lib.lookupFunction<
      Int32 Function(Uint64, Uint32, Double),
      int Function(int, int, double)>('pitch_set_segment_shift');

  late final _pitchQuantizeSegment = _lib.lookupFunction<
      Int32 Function(Uint64, Uint32),
      int Function(int, int)>('pitch_quantize_segment');

  late final _pitchResetSegment = _lib.lookupFunction<
      Int32 Function(Uint64, Uint32),
      int Function(int, int)>('pitch_reset_segment');

  late final _pitchAutoCorrect = _lib.lookupFunction<
      Int32 Function(Uint64, Uint8, Uint8, Double, Double),
      int Function(int, int, int, double, double)>('pitch_auto_correct');

  late final _pitchQuantizeAll = _lib.lookupFunction<
      Int32 Function(Uint64),
      int Function(int)>('pitch_quantize_all');

  late final _pitchResetAll = _lib.lookupFunction<
      Int32 Function(Uint64),
      int Function(int)>('pitch_reset_all');

  late final _pitchSplitSegment = _lib.lookupFunction<
      Uint32 Function(Uint64, Uint32, Uint64),
      int Function(int, int, int)>('pitch_split_segment');

  late final _pitchMergeSegments = _lib.lookupFunction<
      Int32 Function(Uint64, Uint32, Uint32),
      int Function(int, int, int)>('pitch_merge_segments');

  late final _pitchClearState = _lib.lookupFunction<
      Void Function(Uint64),
      void Function(int)>('pitch_clear_state');

  /// Analyze pitch for entire clip - returns number of segments detected
  int pitchAnalyzeClip(int clipId) {
    if (!_loaded) return 0;
    return _pitchAnalyzeClip(clipId);
  }

  /// Get pitch segment count for clip
  int pitchGetSegmentCount(int clipId) {
    if (!_loaded) return 0;
    return _pitchGetSegmentCount(clipId);
  }

  /// Get all pitch segments for a clip
  List<PitchSegmentData> pitchGetSegments(int clipId, {int maxCount = 1000}) {
    if (!_loaded) return [];

    final outIds = calloc<Uint32>(maxCount);
    final outStarts = calloc<Uint64>(maxCount);
    final outEnds = calloc<Uint64>(maxCount);
    final outMidiNotes = calloc<Uint8>(maxCount);
    final outCents = calloc<Double>(maxCount);
    final outTargetMidi = calloc<Uint8>(maxCount);
    final outTargetCents = calloc<Double>(maxCount);
    final outConfidence = calloc<Double>(maxCount);
    final outEdited = calloc<Int32>(maxCount);

    try {
      final count = _pitchGetSegments(
        clipId, outIds, outStarts, outEnds, outMidiNotes, outCents,
        outTargetMidi, outTargetCents, outConfidence, outEdited, maxCount,
      );

      return List.generate(count, (i) => PitchSegmentData(
        id: outIds[i],
        start: outStarts[i],
        end: outEnds[i],
        midiNote: outMidiNotes[i],
        cents: outCents[i],
        targetMidiNote: outTargetMidi[i],
        targetCents: outTargetCents[i],
        confidence: outConfidence[i],
        edited: outEdited[i] != 0,
      ));
    } finally {
      calloc.free(outIds);
      calloc.free(outStarts);
      calloc.free(outEnds);
      calloc.free(outMidiNotes);
      calloc.free(outCents);
      calloc.free(outTargetMidi);
      calloc.free(outTargetCents);
      calloc.free(outConfidence);
      calloc.free(outEdited);
    }
  }

  /// Set segment target pitch shift (semitones)
  bool pitchSetSegmentShift(int clipId, int segmentId, double semitones) {
    if (!_loaded) return false;
    return _pitchSetSegmentShift(clipId, segmentId, semitones) != 0;
  }

  /// Quantize segment to nearest semitone
  bool pitchQuantizeSegment(int clipId, int segmentId) {
    if (!_loaded) return false;
    return _pitchQuantizeSegment(clipId, segmentId) != 0;
  }

  /// Reset segment to original pitch
  bool pitchResetSegment(int clipId, int segmentId) {
    if (!_loaded) return false;
    return _pitchResetSegment(clipId, segmentId) != 0;
  }

  /// Auto-correct all segments to scale
  /// scale: 0=Chromatic, 1=Major, 2=Minor, 3=HarmonicMinor, 4=PentMaj, 5=PentMin, 6=Blues, 7=Dorian
  bool pitchAutoCorrect(int clipId, int scale, int root, double speed, double amount) {
    if (!_loaded) return false;
    return _pitchAutoCorrect(clipId, scale, root, speed, amount) != 0;
  }

  /// Quantize all segments
  bool pitchQuantizeAll(int clipId) {
    if (!_loaded) return false;
    return _pitchQuantizeAll(clipId) != 0;
  }

  /// Reset all segments to original
  bool pitchResetAll(int clipId) {
    if (!_loaded) return false;
    return _pitchResetAll(clipId) != 0;
  }

  /// Split segment at position
  int pitchSplitSegment(int clipId, int segmentId, int position) {
    if (!_loaded) return 0;
    return _pitchSplitSegment(clipId, segmentId, position);
  }

  /// Merge two adjacent segments
  bool pitchMergeSegments(int clipId, int segmentId1, int segmentId2) {
    if (!_loaded) return false;
    return _pitchMergeSegments(clipId, segmentId1, segmentId2) != 0;
  }

  /// Clear pitch editor state for clip
  void pitchClearState(int clipId) {
    if (!_loaded) return;
    _pitchClearState(clipId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VIDEO SYNC API (Dynamic Sample Rate)
  // ═══════════════════════════════════════════════════════════════════════════

  late final _videoSetSampleRate = _lib.lookupFunction<
      Void Function(Uint32),
      void Function(int)>('video_set_sample_rate');

  late final _videoGetPlayheadSamples = _lib.lookupFunction<
      Uint64 Function(),
      int Function()>('video_get_playhead_samples');

  late final _videoSyncToAudio = _lib.lookupFunction<
      Void Function(Uint64),
      void Function(int)>('video_sync_to_audio');

  late final _videoGetSyncDrift = _lib.lookupFunction<
      Int64 Function(Uint64),
      int Function(int)>('video_get_sync_drift');

  /// Set video engine sample rate to match audio engine
  void videoSetSampleRate(int sampleRate) {
    if (!_loaded) return;
    _videoSetSampleRate(sampleRate);
  }

  /// Get current video playhead in samples
  int videoGetPlayheadSamples() {
    if (!_loaded) return 0;
    return _videoGetPlayheadSamples();
  }

  /// Sync video playhead to audio position
  void videoSyncToAudio(int audioSamples) {
    if (!_loaded) return;
    _videoSyncToAudio(audioSamples);
  }

  /// Get sync drift in samples (video - audio)
  int videoGetSyncDrift(int audioSamples) {
    if (!_loaded) return 0;
    return _videoGetSyncDrift(audioSamples);
  }

  // Stems export
  late final _exportStems = _lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Int32, Uint32, Double, Double, Int32, Int32, Pointer<Utf8>),
      int Function(Pointer<Utf8>, int, int, double, double, int, int, Pointer<Utf8>)>('export_stems');

  /// Export stems (individual tracks) to WAV files
  /// Returns number of exported stems, or -1 on error
  int exportStems(String outputDir, int format, int sampleRate,
      double startTime, double endTime, bool normalize, bool includeBuses, String prefix) {
    final dirPtr = outputDir.toNativeUtf8();
    final prefixPtr = prefix.toNativeUtf8();
    final result = _exportStems(dirPtr, format, sampleRate, startTime, endTime,
        normalize ? 1 : 0, includeBuses ? 1 : 0, prefixPtr);
    calloc.free(dirPtr);
    calloc.free(prefixPtr);
    return result;
  }
}

/// Pitch segment data from analysis
class PitchSegmentData {
  final int id;
  final int start;      // Start position in samples
  final int end;        // End position in samples
  final int midiNote;   // Original MIDI note (0-127)
  final double cents;   // Original cents deviation (-50 to +50)
  final int targetMidiNote; // Target MIDI note after editing
  final double targetCents; // Target cents after editing
  final double confidence;  // Detection confidence (0.0-1.0)
  final bool edited;        // Has been manually edited

  const PitchSegmentData({
    required this.id,
    required this.start,
    required this.end,
    required this.midiNote,
    required this.cents,
    required this.targetMidiNote,
    required this.targetCents,
    required this.confidence,
    required this.edited,
  });

  /// Duration in samples
  int get duration => end - start;

  /// Original pitch as MIDI (with cents)
  double get pitchMidi => midiNote + cents / 100.0;

  /// Target pitch as MIDI (with cents)
  double get targetPitchMidi => targetMidiNote + targetCents / 100.0;

  /// Pitch shift in semitones
  double get pitchShift => targetPitchMidi - pitchMidi;

  /// Note name (e.g. "C4", "A#3")
  String get noteName {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (midiNote ~/ 12) - 1;
    return '${names[midiNote % 12]}$octave';
  }

  /// Target note name
  String get targetNoteName {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (targetMidiNote ~/ 12) - 1;
    return '${names[targetMidiNote % 12]}$octave';
  }
}

/// Piano roll note data
class PianoRollNote {
  final int id;
  final int note;
  final int startTick;
  final int duration;
  final int velocity;
  final bool selected;
  final bool muted;

  const PianoRollNote({
    required this.id,
    required this.note,
    required this.startTick,
    required this.duration,
    required this.velocity,
    required this.selected,
    required this.muted,
  });

  /// Get note name (e.g. "C4", "F#3")
  String get noteName {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (note ~/ 12) - 1;
    final name = names[note % 12];
    return '$name$octave';
  }

  /// Is this a black key?
  bool get isBlackKey {
    final n = note % 12;
    return n == 1 || n == 3 || n == 6 || n == 8 || n == 10;
  }

  /// End tick
  int get endTick => startTick + duration;
}

// ═══════════════════════════════════════════════════════════════════════════
// REVERB API EXTENSION
// ═══════════════════════════════════════════════════════════════════════════

/// Reverb types for algorithmic reverb
enum ReverbType {
  room,      // 0
  hall,      // 1
  plate,     // 2
  chamber,   // 3
  spring,    // 4
}

/// Extension to add Reverb API to NativeFFI
extension ReverbAPI on NativeFFI {
  // ============================================================
  // CONVOLUTION REVERB
  // ============================================================

  static late final _convolutionReverbCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('convolution_reverb_create');

  static late final _convolutionReverbRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('convolution_reverb_remove');

  static late final _convolutionReverbSetDryWet = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('convolution_reverb_set_dry_wet');

  static late final _convolutionReverbSetPredelay = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('convolution_reverb_set_predelay');

  static late final _convolutionReverbReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('convolution_reverb_reset');

  static late final _convolutionReverbGetLatency = _loadNativeLibrary().lookupFunction<
      Uint32 Function(Uint32),
      int Function(int)>('convolution_reverb_get_latency');
  static late final _convolutionReverbLoadIr = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Pointer<Double>, Uint32, Uint32),
      int Function(int, Pointer<Double>, int, int)>('convolution_reverb_load_ir');

  /// Create convolution reverb for track
  bool convolutionReverbCreate(int trackId, {double sampleRate = 48000.0}) {
    return _convolutionReverbCreate(trackId, sampleRate) == 1;
  }

  /// Remove convolution reverb
  bool convolutionReverbRemove(int trackId) {
    return _convolutionReverbRemove(trackId) == 1;
  }

  /// Set convolution reverb dry/wet mix (0.0-1.0)
  bool convolutionReverbSetDryWet(int trackId, double mix) {
    return _convolutionReverbSetDryWet(trackId, mix.clamp(0.0, 1.0)) == 1;
  }

  /// Set convolution reverb predelay in ms
  bool convolutionReverbSetPredelay(int trackId, double predelayMs) {
    return _convolutionReverbSetPredelay(trackId, predelayMs.clamp(0.0, 500.0)) == 1;
  }

  /// Reset convolution reverb state
  bool convolutionReverbReset(int trackId) {
    return _convolutionReverbReset(trackId) == 1;
  }

  /// Get convolution reverb latency in samples
  int convolutionReverbGetLatency(int trackId) {
    return _convolutionReverbGetLatency(trackId);
  }

  /// Load impulse response from audio samples
  /// [irSamples] - interleaved stereo or mono samples
  /// [channelCount] - 1 for mono, 2 for stereo
  bool convolutionReverbLoadIr(int trackId, Float64List irSamples, {int channelCount = 2}) {
    if (irSamples.isEmpty) return false;
    final samplesPerChannel = irSamples.length ~/ channelCount;
    final ptr = calloc<Double>(irSamples.length);
    try {
      for (int i = 0; i < irSamples.length; i++) {
        ptr[i] = irSamples[i];
      }
      return _convolutionReverbLoadIr(trackId, ptr, channelCount, samplesPerChannel) == 1;
    } finally {
      calloc.free(ptr);
    }
  }

  // ============================================================
  // ALGORITHMIC REVERB
  // ============================================================

  static late final _algorithmicReverbCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('algorithmic_reverb_create');

  static late final _algorithmicReverbRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('algorithmic_reverb_remove');

  static late final _algorithmicReverbSetType = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32),
      int Function(int, int)>('algorithmic_reverb_set_type');

  static late final _algorithmicReverbSetRoomSize = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('algorithmic_reverb_set_room_size');

  static late final _algorithmicReverbSetDamping = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('algorithmic_reverb_set_damping');

  static late final _algorithmicReverbSetWidth = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('algorithmic_reverb_set_width');

  static late final _algorithmicReverbSetDryWet = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('algorithmic_reverb_set_dry_wet');

  static late final _algorithmicReverbSetPredelay = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('algorithmic_reverb_set_predelay');

  static late final _algorithmicReverbReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('algorithmic_reverb_reset');

  static late final _algorithmicReverbGetLatency = _loadNativeLibrary().lookupFunction<
      Uint32 Function(Uint32),
      int Function(int)>('algorithmic_reverb_get_latency');

  /// Create algorithmic reverb for track
  bool algorithmicReverbCreate(int trackId, {double sampleRate = 48000.0}) {
    return _algorithmicReverbCreate(trackId, sampleRate) == 1;
  }

  /// Remove algorithmic reverb
  bool algorithmicReverbRemove(int trackId) {
    return _algorithmicReverbRemove(trackId) == 1;
  }

  /// Set reverb type
  bool algorithmicReverbSetType(int trackId, ReverbType type) {
    return _algorithmicReverbSetType(trackId, type.index) == 1;
  }

  /// Set room size (0.0-1.0)
  bool algorithmicReverbSetRoomSize(int trackId, double size) {
    return _algorithmicReverbSetRoomSize(trackId, size.clamp(0.0, 1.0)) == 1;
  }

  /// Set damping (0.0-1.0)
  bool algorithmicReverbSetDamping(int trackId, double damping) {
    return _algorithmicReverbSetDamping(trackId, damping.clamp(0.0, 1.0)) == 1;
  }

  /// Set stereo width (0.0-1.0)
  bool algorithmicReverbSetWidth(int trackId, double width) {
    return _algorithmicReverbSetWidth(trackId, width.clamp(0.0, 1.0)) == 1;
  }

  /// Set dry/wet mix (0.0-1.0)
  bool algorithmicReverbSetDryWet(int trackId, double mix) {
    return _algorithmicReverbSetDryWet(trackId, mix.clamp(0.0, 1.0)) == 1;
  }

  /// Set predelay in ms (0-200ms)
  bool algorithmicReverbSetPredelay(int trackId, double predelayMs) {
    return _algorithmicReverbSetPredelay(trackId, predelayMs.clamp(0.0, 200.0)) == 1;
  }

  /// Reset algorithmic reverb state
  bool algorithmicReverbReset(int trackId) {
    return _algorithmicReverbReset(trackId) == 1;
  }

  /// Get algorithmic reverb latency in samples
  int algorithmicReverbGetLatency(int trackId) {
    return _algorithmicReverbGetLatency(trackId);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DELAY API EXTENSION
// ═══════════════════════════════════════════════════════════════════════════

/// Delay types
enum DelayType {
  simple,
  pingPong,
  multiTap,
  modulated,
}

/// Modulated delay presets
enum ModulatedDelayPreset {
  custom,
  chorus,
  flanger,
}

/// Extension to add Delay API to NativeFFI
extension DelayAPI on NativeFFI {
  // ============================================================
  // SIMPLE DELAY
  // ============================================================

  static final _simpleDelayCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Double),
      int Function(int, double, double)>('simple_delay_create');

  static final _simpleDelayRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('simple_delay_remove');

  static final _simpleDelaySetTime = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('simple_delay_set_time');

  static final _simpleDelaySetFeedback = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('simple_delay_set_feedback');

  static final _simpleDelaySetDryWet = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('simple_delay_set_dry_wet');

  static final _simpleDelaySetHighpass = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('simple_delay_set_highpass');

  static final _simpleDelaySetLowpass = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('simple_delay_set_lowpass');

  static final _simpleDelaySetFilterEnabled = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32),
      int Function(int, int)>('simple_delay_set_filter_enabled');

  static final _simpleDelayReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('simple_delay_reset');

  /// Create simple delay
  bool simpleDelayCreate(int trackId, {double sampleRate = 48000.0, double maxDelayMs = 2000.0}) {
    return _simpleDelayCreate(trackId, sampleRate, maxDelayMs) == 1;
  }

  bool simpleDelayRemove(int trackId) => _simpleDelayRemove(trackId) == 1;
  bool simpleDelaySetTime(int trackId, double delayMs) => _simpleDelaySetTime(trackId, delayMs) == 1;
  bool simpleDelaySetFeedback(int trackId, double feedback) => _simpleDelaySetFeedback(trackId, feedback.clamp(0.0, 0.99)) == 1;
  bool simpleDelaySetDryWet(int trackId, double mix) => _simpleDelaySetDryWet(trackId, mix.clamp(0.0, 1.0)) == 1;
  bool simpleDelaySetHighpass(int trackId, double freq) => _simpleDelaySetHighpass(trackId, freq) == 1;
  bool simpleDelaySetLowpass(int trackId, double freq) => _simpleDelaySetLowpass(trackId, freq) == 1;
  bool simpleDelaySetFilterEnabled(int trackId, bool enabled) => _simpleDelaySetFilterEnabled(trackId, enabled ? 1 : 0) == 1;
  bool simpleDelayReset(int trackId) => _simpleDelayReset(trackId) == 1;

  // ============================================================
  // PING-PONG DELAY
  // ============================================================

  static final _pingPongDelayCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Double),
      int Function(int, double, double)>('ping_pong_delay_create');

  static final _pingPongDelayRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('ping_pong_delay_remove');

  static final _pingPongDelaySetTime = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('ping_pong_delay_set_time');

  static final _pingPongDelaySetFeedback = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('ping_pong_delay_set_feedback');

  static final _pingPongDelaySetDryWet = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('ping_pong_delay_set_dry_wet');

  static final _pingPongDelaySetPingPong = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('ping_pong_delay_set_ping_pong');

  static final _pingPongDelayReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('ping_pong_delay_reset');

  bool pingPongDelayCreate(int trackId, {double sampleRate = 48000.0, double maxDelayMs = 2000.0}) {
    return _pingPongDelayCreate(trackId, sampleRate, maxDelayMs) == 1;
  }

  bool pingPongDelayRemove(int trackId) => _pingPongDelayRemove(trackId) == 1;
  bool pingPongDelaySetTime(int trackId, double delayMs) => _pingPongDelaySetTime(trackId, delayMs) == 1;
  bool pingPongDelaySetFeedback(int trackId, double feedback) => _pingPongDelaySetFeedback(trackId, feedback.clamp(0.0, 0.99)) == 1;
  bool pingPongDelaySetDryWet(int trackId, double mix) => _pingPongDelaySetDryWet(trackId, mix.clamp(0.0, 1.0)) == 1;
  bool pingPongDelaySetPingPong(int trackId, double amount) => _pingPongDelaySetPingPong(trackId, amount.clamp(0.0, 1.0)) == 1;
  bool pingPongDelayReset(int trackId) => _pingPongDelayReset(trackId) == 1;

  // ============================================================
  // MULTI-TAP DELAY
  // ============================================================

  static final _multiTapDelayCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Double, Uint32),
      int Function(int, double, double, int)>('multi_tap_delay_create');

  static final _multiTapDelayRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('multi_tap_delay_remove');

  static final _multiTapDelaySetTap = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double, Double, Double),
      int Function(int, int, double, double, double)>('multi_tap_delay_set_tap');

  static final _multiTapDelaySetFeedback = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('multi_tap_delay_set_feedback');

  static final _multiTapDelaySetDryWet = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('multi_tap_delay_set_dry_wet');

  static final _multiTapDelayReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('multi_tap_delay_reset');

  bool multiTapDelayCreate(int trackId, {double sampleRate = 48000.0, double maxDelayMs = 2000.0, int numTaps = 4}) {
    return _multiTapDelayCreate(trackId, sampleRate, maxDelayMs, numTaps) == 1;
  }

  bool multiTapDelayRemove(int trackId) => _multiTapDelayRemove(trackId) == 1;
  bool multiTapDelaySetTap(int trackId, int tapIndex, double delayMs, double level, double pan) {
    return _multiTapDelaySetTap(trackId, tapIndex, delayMs, level.clamp(0.0, 1.0), pan.clamp(-1.0, 1.0)) == 1;
  }
  bool multiTapDelaySetFeedback(int trackId, double feedback) => _multiTapDelaySetFeedback(trackId, feedback.clamp(0.0, 0.99)) == 1;
  bool multiTapDelaySetDryWet(int trackId, double mix) => _multiTapDelaySetDryWet(trackId, mix.clamp(0.0, 1.0)) == 1;
  bool multiTapDelayReset(int trackId) => _multiTapDelayReset(trackId) == 1;

  // ============================================================
  // MODULATED DELAY (CHORUS/FLANGER)
  // ============================================================

  static final _modulatedDelayCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('modulated_delay_create');

  static final _modulatedDelayCreateChorus = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('modulated_delay_create_chorus');

  static final _modulatedDelayCreateFlanger = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('modulated_delay_create_flanger');

  static final _modulatedDelayRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('modulated_delay_remove');

  static final _modulatedDelaySetTime = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('modulated_delay_set_time');

  static final _modulatedDelaySetModDepth = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('modulated_delay_set_mod_depth');

  static final _modulatedDelaySetModRate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('modulated_delay_set_mod_rate');

  static final _modulatedDelaySetFeedback = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('modulated_delay_set_feedback');

  static final _modulatedDelaySetDryWet = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('modulated_delay_set_dry_wet');

  static final _modulatedDelayReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('modulated_delay_reset');

  bool modulatedDelayCreate(int trackId, {double sampleRate = 48000.0, ModulatedDelayPreset preset = ModulatedDelayPreset.custom}) {
    switch (preset) {
      case ModulatedDelayPreset.chorus:
        return _modulatedDelayCreateChorus(trackId, sampleRate) == 1;
      case ModulatedDelayPreset.flanger:
        return _modulatedDelayCreateFlanger(trackId, sampleRate) == 1;
      case ModulatedDelayPreset.custom:
        return _modulatedDelayCreate(trackId, sampleRate) == 1;
    }
  }

  bool modulatedDelayRemove(int trackId) => _modulatedDelayRemove(trackId) == 1;
  bool modulatedDelaySetTime(int trackId, double delayMs) => _modulatedDelaySetTime(trackId, delayMs) == 1;
  bool modulatedDelaySetModDepth(int trackId, double depthMs) => _modulatedDelaySetModDepth(trackId, depthMs) == 1;
  bool modulatedDelaySetModRate(int trackId, double rateHz) => _modulatedDelaySetModRate(trackId, rateHz.clamp(0.01, 20.0)) == 1;
  bool modulatedDelaySetFeedback(int trackId, double feedback) => _modulatedDelaySetFeedback(trackId, feedback.clamp(-0.99, 0.99)) == 1;
  bool modulatedDelaySetDryWet(int trackId, double mix) => _modulatedDelaySetDryWet(trackId, mix.clamp(0.0, 1.0)) == 1;
  bool modulatedDelayReset(int trackId) => _modulatedDelayReset(trackId) == 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// DYNAMICS API EXTENSION
// ═══════════════════════════════════════════════════════════════════════════

/// Compressor types
enum CompressorType {
  vca,   // 0 - Clean, transparent
  opto,  // 1 - Smooth, program-dependent
  fet,   // 2 - Aggressive, punchy
}

/// Extension to add Dynamics API to NativeFFI
extension DynamicsAPI on NativeFFI {
  // ============================================================
  // COMPRESSOR
  // ============================================================

  static final _compressorCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('compressor_create');
  static final _compressorRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('compressor_remove');
  static final _compressorSetType = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('compressor_set_type');
  static final _compressorSetThreshold = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('compressor_set_threshold');
  static final _compressorSetRatio = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('compressor_set_ratio');
  static final _compressorSetKnee = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('compressor_set_knee');
  static final _compressorSetAttack = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('compressor_set_attack');
  static final _compressorSetRelease = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('compressor_set_release');
  static final _compressorSetMakeup = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('compressor_set_makeup');
  static final _compressorSetMix = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('compressor_set_mix');
  static final _compressorSetLink = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('compressor_set_link');
  static final _compressorGetGainReduction = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32), double Function(int)>('compressor_get_gain_reduction');
  static final _compressorReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('compressor_reset');

  bool compressorCreate(int trackId, {double sampleRate = 48000.0}) => _compressorCreate(trackId, sampleRate) == 1;
  bool compressorRemove(int trackId) => _compressorRemove(trackId) == 1;
  bool compressorSetType(int trackId, CompressorType type) => _compressorSetType(trackId, type.index) == 1;
  bool compressorSetThreshold(int trackId, double db) => _compressorSetThreshold(trackId, db.clamp(-60.0, 0.0)) == 1;
  bool compressorSetRatio(int trackId, double ratio) => _compressorSetRatio(trackId, ratio.clamp(1.0, 100.0)) == 1;
  bool compressorSetKnee(int trackId, double db) => _compressorSetKnee(trackId, db.clamp(0.0, 24.0)) == 1;
  bool compressorSetAttack(int trackId, double ms) => _compressorSetAttack(trackId, ms.clamp(0.01, 500.0)) == 1;
  bool compressorSetRelease(int trackId, double ms) => _compressorSetRelease(trackId, ms.clamp(1.0, 5000.0)) == 1;
  bool compressorSetMakeup(int trackId, double db) => _compressorSetMakeup(trackId, db.clamp(-24.0, 24.0)) == 1;
  bool compressorSetMix(int trackId, double mix) => _compressorSetMix(trackId, mix.clamp(0.0, 1.0)) == 1;
  bool compressorSetLink(int trackId, double link) => _compressorSetLink(trackId, link.clamp(0.0, 1.0)) == 1;
  double compressorGetGainReduction(int trackId) => _compressorGetGainReduction(trackId);
  bool compressorReset(int trackId) => _compressorReset(trackId) == 1;

  // ============================================================
  // LIMITER
  // ============================================================

  static final _limiterCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('limiter_create');
  static final _limiterRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('limiter_remove');
  static final _limiterSetThreshold = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('limiter_set_threshold');
  static final _limiterSetCeiling = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('limiter_set_ceiling');
  static final _limiterSetRelease = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('limiter_set_release');
  static final _limiterGetTruePeak = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32), double Function(int)>('limiter_get_true_peak');
  static final _limiterGetGainReduction = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32), double Function(int)>('limiter_get_gain_reduction');
  static final _limiterReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('limiter_reset');

  bool limiterCreate(int trackId, {double sampleRate = 48000.0}) => _limiterCreate(trackId, sampleRate) == 1;
  bool limiterRemove(int trackId) => _limiterRemove(trackId) == 1;
  bool limiterSetThreshold(int trackId, double db) => _limiterSetThreshold(trackId, db.clamp(-24.0, 0.0)) == 1;
  bool limiterSetCeiling(int trackId, double db) => _limiterSetCeiling(trackId, db.clamp(-6.0, 0.0)) == 1;
  bool limiterSetRelease(int trackId, double ms) => _limiterSetRelease(trackId, ms.clamp(10.0, 1000.0)) == 1;
  double limiterGetTruePeak(int trackId) => _limiterGetTruePeak(trackId);
  double limiterGetGainReduction(int trackId) => _limiterGetGainReduction(trackId);
  bool limiterReset(int trackId) => _limiterReset(trackId) == 1;

  // ============================================================
  // GATE
  // ============================================================

  static final _gateCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('gate_create');
  static final _gateRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('gate_remove');
  static final _gateSetThreshold = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('gate_set_threshold');
  static final _gateSetRange = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('gate_set_range');
  static final _gateSetAttack = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('gate_set_attack');
  static final _gateSetHold = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('gate_set_hold');
  static final _gateSetRelease = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('gate_set_release');
  static final _gateReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('gate_reset');

  bool gateCreate(int trackId, {double sampleRate = 48000.0}) => _gateCreate(trackId, sampleRate) == 1;
  bool gateRemove(int trackId) => _gateRemove(trackId) == 1;
  bool gateSetThreshold(int trackId, double db) => _gateSetThreshold(trackId, db.clamp(-80.0, 0.0)) == 1;
  bool gateSetRange(int trackId, double db) => _gateSetRange(trackId, db.clamp(-80.0, 0.0)) == 1;
  bool gateSetAttack(int trackId, double ms) => _gateSetAttack(trackId, ms.clamp(0.01, 100.0)) == 1;
  bool gateSetHold(int trackId, double ms) => _gateSetHold(trackId, ms.clamp(0.0, 500.0)) == 1;
  bool gateSetRelease(int trackId, double ms) => _gateSetRelease(trackId, ms.clamp(1.0, 1000.0)) == 1;
  bool gateReset(int trackId) => _gateReset(trackId) == 1;

  // ============================================================
  // EXPANDER
  // ============================================================

  static final _expanderCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('expander_create');
  static final _expanderRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('expander_remove');
  static final _expanderSetThreshold = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('expander_set_threshold');
  static final _expanderSetRatio = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('expander_set_ratio');
  static final _expanderSetKnee = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('expander_set_knee');
  static final _expanderSetTimes = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Double), int Function(int, double, double)>('expander_set_times');
  static final _expanderReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('expander_reset');

  bool expanderCreate(int trackId, {double sampleRate = 48000.0}) => _expanderCreate(trackId, sampleRate) == 1;
  bool expanderRemove(int trackId) => _expanderRemove(trackId) == 1;
  bool expanderSetThreshold(int trackId, double db) => _expanderSetThreshold(trackId, db.clamp(-80.0, 0.0)) == 1;
  bool expanderSetRatio(int trackId, double ratio) => _expanderSetRatio(trackId, ratio.clamp(1.0, 20.0)) == 1;
  bool expanderSetKnee(int trackId, double db) => _expanderSetKnee(trackId, db.clamp(0.0, 24.0)) == 1;
  bool expanderSetTimes(int trackId, double attackMs, double releaseMs) => _expanderSetTimes(trackId, attackMs, releaseMs) == 1;
  bool expanderReset(int trackId) => _expanderReset(trackId) == 1;
}

// ============================================================================
// SPATIAL PROCESSING API
// ============================================================================

/// Pan law types
enum PanLaw {
  linear,        // -6dB center
  constantPower, // -3dB center (default)
  compromise,    // -4.5dB center
  noCenterAttenuation, // No attenuation at center
}

/// Spatial processing API extension
extension SpatialAPI on NativeFFI {
  // ============================================================
  // STEREO IMAGER (Full processor)
  // ============================================================

  static final _stereoImagerCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('stereo_imager_create');
  static final _stereoImagerRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('stereo_imager_remove');
  static final _stereoImagerSetWidth = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('stereo_imager_set_width');
  static final _stereoImagerSetPan = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('stereo_imager_set_pan');
  static final _stereoImagerSetPanLaw = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('stereo_imager_set_pan_law');
  static final _stereoImagerSetBalance = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('stereo_imager_set_balance');
  static final _stereoImagerSetMidGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('stereo_imager_set_mid_gain');
  static final _stereoImagerSetSideGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('stereo_imager_set_side_gain');
  static final _stereoImagerSetRotation = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('stereo_imager_set_rotation');
  static final _stereoImagerEnableWidth = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('stereo_imager_enable_width');
  static final _stereoImagerEnablePanner = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('stereo_imager_enable_panner');
  static final _stereoImagerEnableBalance = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('stereo_imager_enable_balance');
  static final _stereoImagerEnableMs = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('stereo_imager_enable_ms');
  static final _stereoImagerEnableRotation = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('stereo_imager_enable_rotation');
  static final _stereoImagerGetCorrelation = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32), double Function(int)>('stereo_imager_get_correlation');
  static final _stereoImagerReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('stereo_imager_reset');

  bool stereoImagerCreate(int trackId, {double sampleRate = 48000.0}) => _stereoImagerCreate(trackId, sampleRate) == 1;
  bool stereoImagerRemove(int trackId) => _stereoImagerRemove(trackId) == 1;
  bool stereoImagerSetWidth(int trackId, double width) => _stereoImagerSetWidth(trackId, width.clamp(0.0, 2.0)) == 1;
  bool stereoImagerSetPan(int trackId, double pan) => _stereoImagerSetPan(trackId, pan.clamp(-1.0, 1.0)) == 1;
  bool stereoImagerSetPanLaw(int trackId, PanLaw law) => _stereoImagerSetPanLaw(trackId, law.index) == 1;
  bool stereoImagerSetBalance(int trackId, double balance) => _stereoImagerSetBalance(trackId, balance.clamp(-1.0, 1.0)) == 1;
  bool stereoImagerSetMidGain(int trackId, double gainDb) => _stereoImagerSetMidGain(trackId, gainDb.clamp(-24.0, 12.0)) == 1;
  bool stereoImagerSetSideGain(int trackId, double gainDb) => _stereoImagerSetSideGain(trackId, gainDb.clamp(-24.0, 12.0)) == 1;
  bool stereoImagerSetRotation(int trackId, double degrees) => _stereoImagerSetRotation(trackId, degrees.clamp(-180.0, 180.0)) == 1;
  bool stereoImagerEnableWidth(int trackId, bool enabled) => _stereoImagerEnableWidth(trackId, enabled ? 1 : 0) == 1;
  bool stereoImagerEnablePanner(int trackId, bool enabled) => _stereoImagerEnablePanner(trackId, enabled ? 1 : 0) == 1;
  bool stereoImagerEnableBalance(int trackId, bool enabled) => _stereoImagerEnableBalance(trackId, enabled ? 1 : 0) == 1;
  bool stereoImagerEnableMs(int trackId, bool enabled) => _stereoImagerEnableMs(trackId, enabled ? 1 : 0) == 1;
  bool stereoImagerEnableRotation(int trackId, bool enabled) => _stereoImagerEnableRotation(trackId, enabled ? 1 : 0) == 1;
  double stereoImagerGetCorrelation(int trackId) => _stereoImagerGetCorrelation(trackId);
  bool stereoImagerReset(int trackId) => _stereoImagerReset(trackId) == 1;

  // ============================================================
  // STANDALONE PANNER
  // ============================================================

  static final _pannerCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('panner_create');
  static final _pannerRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('panner_remove');
  static final _pannerSetPan = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('panner_set_pan');
  static final _pannerSetLaw = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('panner_set_law');
  static final _pannerGetPan = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32), double Function(int)>('panner_get_pan');

  bool pannerCreate(int trackId) => _pannerCreate(trackId) == 1;
  bool pannerRemove(int trackId) => _pannerRemove(trackId) == 1;
  bool pannerSetPan(int trackId, double pan) => _pannerSetPan(trackId, pan.clamp(-1.0, 1.0)) == 1;
  bool pannerSetLaw(int trackId, PanLaw law) => _pannerSetLaw(trackId, law.index) == 1;
  double pannerGetPan(int trackId) => _pannerGetPan(trackId);

  // ============================================================
  // STANDALONE WIDTH
  // ============================================================

  static final _widthCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('width_create');
  static final _widthRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('width_remove');
  static final _widthSetWidth = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('width_set_width');
  static final _widthGetWidth = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32), double Function(int)>('width_get_width');

  bool widthCreate(int trackId) => _widthCreate(trackId) == 1;
  bool widthRemove(int trackId) => _widthRemove(trackId) == 1;
  bool widthSetWidth(int trackId, double width) => _widthSetWidth(trackId, width.clamp(0.0, 2.0)) == 1;
  double widthGetWidth(int trackId) => _widthGetWidth(trackId);

  // ============================================================
  // M/S PROCESSOR
  // ============================================================

  static final _msProcessorCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('ms_processor_create');
  static final _msProcessorRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('ms_processor_remove');
  static final _msProcessorSetMidGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('ms_processor_set_mid_gain');
  static final _msProcessorSetSideGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('ms_processor_set_side_gain');
  static final _msProcessorReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('ms_processor_reset');

  bool msProcessorCreate(int trackId) => _msProcessorCreate(trackId) == 1;
  bool msProcessorRemove(int trackId) => _msProcessorRemove(trackId) == 1;
  bool msProcessorSetMidGain(int trackId, double gainDb) => _msProcessorSetMidGain(trackId, gainDb.clamp(-24.0, 12.0)) == 1;
  bool msProcessorSetSideGain(int trackId, double gainDb) => _msProcessorSetSideGain(trackId, gainDb.clamp(-24.0, 12.0)) == 1;
  bool msProcessorReset(int trackId) => _msProcessorReset(trackId) == 1;
}

// ============================================================================
// MULTIBAND DYNAMICS API
// ============================================================================

/// Crossover filter types
enum CrossoverType {
  butterworth12,  // 12 dB/oct
  linkwitzRiley24, // 24 dB/oct (default)
  linkwitzRiley48, // 48 dB/oct
}

/// Multiband dynamics API extension
extension MultibandAPI on NativeFFI {
  // ============================================================
  // MULTIBAND COMPRESSOR
  // ============================================================

  static final _multibandCompCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Uint32), int Function(int, double, int)>('multiband_comp_create');
  static final _multibandCompRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('multiband_comp_remove');
  static final _multibandCompSetNumBands = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('multiband_comp_set_num_bands');
  static final _multibandCompSetCrossover = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double), int Function(int, int, double)>('multiband_comp_set_crossover');
  static final _multibandCompSetCrossoverType = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('multiband_comp_set_crossover_type');
  static final _multibandCompSetBandThreshold = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double), int Function(int, int, double)>('multiband_comp_set_band_threshold');
  static final _multibandCompSetBandRatio = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double), int Function(int, int, double)>('multiband_comp_set_band_ratio');
  static final _multibandCompSetBandAttack = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double), int Function(int, int, double)>('multiband_comp_set_band_attack');
  static final _multibandCompSetBandRelease = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double), int Function(int, int, double)>('multiband_comp_set_band_release');
  static final _multibandCompSetBandKnee = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double), int Function(int, int, double)>('multiband_comp_set_band_knee');
  static final _multibandCompSetBandMakeup = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double), int Function(int, int, double)>('multiband_comp_set_band_makeup');
  static final _multibandCompSetBandSolo = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Int32), int Function(int, int, int)>('multiband_comp_set_band_solo');
  static final _multibandCompSetBandMute = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Int32), int Function(int, int, int)>('multiband_comp_set_band_mute');
  static final _multibandCompSetBandBypass = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Int32), int Function(int, int, int)>('multiband_comp_set_band_bypass');
  static final _multibandCompSetOutputGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('multiband_comp_set_output_gain');
  static final _multibandCompGetBandGr = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32, Uint32), double Function(int, int)>('multiband_comp_get_band_gr');
  static final _multibandCompReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('multiband_comp_reset');

  bool multibandCompCreate(int trackId, {double sampleRate = 48000.0, int numBands = 4}) =>
      _multibandCompCreate(trackId, sampleRate, numBands.clamp(2, 6)) == 1;
  bool multibandCompRemove(int trackId) => _multibandCompRemove(trackId) == 1;
  bool multibandCompSetNumBands(int trackId, int numBands) =>
      _multibandCompSetNumBands(trackId, numBands.clamp(2, 6)) == 1;
  bool multibandCompSetCrossover(int trackId, int index, double freq) =>
      _multibandCompSetCrossover(trackId, index, freq.clamp(20.0, 20000.0)) == 1;
  bool multibandCompSetCrossoverType(int trackId, CrossoverType type) =>
      _multibandCompSetCrossoverType(trackId, type.index) == 1;
  bool multibandCompSetBandThreshold(int trackId, int band, double db) =>
      _multibandCompSetBandThreshold(trackId, band, db.clamp(-60.0, 0.0)) == 1;
  bool multibandCompSetBandRatio(int trackId, int band, double ratio) =>
      _multibandCompSetBandRatio(trackId, band, ratio.clamp(1.0, 100.0)) == 1;
  bool multibandCompSetBandAttack(int trackId, int band, double ms) =>
      _multibandCompSetBandAttack(trackId, band, ms.clamp(0.01, 500.0)) == 1;
  bool multibandCompSetBandRelease(int trackId, int band, double ms) =>
      _multibandCompSetBandRelease(trackId, band, ms.clamp(1.0, 5000.0)) == 1;
  bool multibandCompSetBandKnee(int trackId, int band, double db) =>
      _multibandCompSetBandKnee(trackId, band, db.clamp(0.0, 24.0)) == 1;
  bool multibandCompSetBandMakeup(int trackId, int band, double db) =>
      _multibandCompSetBandMakeup(trackId, band, db.clamp(-24.0, 24.0)) == 1;
  bool multibandCompSetBandSolo(int trackId, int band, bool solo) =>
      _multibandCompSetBandSolo(trackId, band, solo ? 1 : 0) == 1;
  bool multibandCompSetBandMute(int trackId, int band, bool mute) =>
      _multibandCompSetBandMute(trackId, band, mute ? 1 : 0) == 1;
  bool multibandCompSetBandBypass(int trackId, int band, bool bypass) =>
      _multibandCompSetBandBypass(trackId, band, bypass ? 1 : 0) == 1;
  bool multibandCompSetOutputGain(int trackId, double db) =>
      _multibandCompSetOutputGain(trackId, db.clamp(-24.0, 24.0)) == 1;
  double multibandCompGetBandGr(int trackId, int band) => _multibandCompGetBandGr(trackId, band);
  bool multibandCompReset(int trackId) => _multibandCompReset(trackId) == 1;

  // ============================================================
  // MULTIBAND LIMITER
  // ============================================================

  static final _multibandLimCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Uint32), int Function(int, double, int)>('multiband_lim_create');
  static final _multibandLimRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('multiband_lim_remove');
  static final _multibandLimSetCeiling = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('multiband_lim_set_ceiling');
  static final _multibandLimSetBandCeiling = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double), int Function(int, int, double)>('multiband_lim_set_band_ceiling');
  static final _multibandLimSetBandSolo = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Int32), int Function(int, int, int)>('multiband_lim_set_band_solo');
  static final _multibandLimSetBandMute = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Int32), int Function(int, int, int)>('multiband_lim_set_band_mute');
  static final _multibandLimReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('multiband_lim_reset');

  bool multibandLimCreate(int trackId, {double sampleRate = 48000.0, int numBands = 4}) =>
      _multibandLimCreate(trackId, sampleRate, numBands.clamp(2, 6)) == 1;
  bool multibandLimRemove(int trackId) => _multibandLimRemove(trackId) == 1;
  bool multibandLimSetCeiling(int trackId, double db) =>
      _multibandLimSetCeiling(trackId, db.clamp(-24.0, 0.0)) == 1;
  bool multibandLimSetBandCeiling(int trackId, int band, double db) =>
      _multibandLimSetBandCeiling(trackId, band, db.clamp(-24.0, 0.0)) == 1;
  bool multibandLimSetBandSolo(int trackId, int band, bool solo) =>
      _multibandLimSetBandSolo(trackId, band, solo ? 1 : 0) == 1;
  bool multibandLimSetBandMute(int trackId, int band, bool mute) =>
      _multibandLimSetBandMute(trackId, band, mute ? 1 : 0) == 1;
  bool multibandLimReset(int trackId) => _multibandLimReset(trackId) == 1;
}

// ============================================================================
// TRANSIENT SHAPER API
// ============================================================================

/// Transient shaper API extension
extension TransientShaperAPI on NativeFFI {
  // ============================================================
  // TRANSIENT SHAPER
  // ============================================================

  static final _transientShaperCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('transient_shaper_create');
  static final _transientShaperRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('transient_shaper_remove');
  static final _transientShaperSetAttack = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('transient_shaper_set_attack');
  static final _transientShaperSetSustain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('transient_shaper_set_sustain');
  static final _transientShaperSetAttackSpeed = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('transient_shaper_set_attack_speed');
  static final _transientShaperSetSustainSpeed = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('transient_shaper_set_sustain_speed');
  static final _transientShaperSetOutputGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('transient_shaper_set_output_gain');
  static final _transientShaperSetMix = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('transient_shaper_set_mix');
  static final _transientShaperGetAttackEnvelope = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32), double Function(int)>('transient_shaper_get_attack_envelope');
  static final _transientShaperGetSustainEnvelope = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32), double Function(int)>('transient_shaper_get_sustain_envelope');
  static final _transientShaperReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('transient_shaper_reset');

  bool transientShaperCreate(int trackId, {double sampleRate = 48000.0}) =>
      _transientShaperCreate(trackId, sampleRate) == 1;
  bool transientShaperRemove(int trackId) => _transientShaperRemove(trackId) == 1;
  bool transientShaperSetAttack(int trackId, double percent) =>
      _transientShaperSetAttack(trackId, percent.clamp(-100.0, 100.0)) == 1;
  bool transientShaperSetSustain(int trackId, double percent) =>
      _transientShaperSetSustain(trackId, percent.clamp(-100.0, 100.0)) == 1;
  bool transientShaperSetAttackSpeed(int trackId, double ms) =>
      _transientShaperSetAttackSpeed(trackId, ms.clamp(1.0, 200.0)) == 1;
  bool transientShaperSetSustainSpeed(int trackId, double ms) =>
      _transientShaperSetSustainSpeed(trackId, ms.clamp(10.0, 500.0)) == 1;
  bool transientShaperSetOutputGain(int trackId, double db) =>
      _transientShaperSetOutputGain(trackId, db.clamp(-24.0, 24.0)) == 1;
  bool transientShaperSetMix(int trackId, double mix) =>
      _transientShaperSetMix(trackId, mix.clamp(0.0, 1.0)) == 1;
  double transientShaperGetAttackEnvelope(int trackId) => _transientShaperGetAttackEnvelope(trackId);
  double transientShaperGetSustainEnvelope(int trackId) => _transientShaperGetSustainEnvelope(trackId);
  bool transientShaperReset(int trackId) => _transientShaperReset(trackId) == 1;

  // ============================================================
  // MULTIBAND TRANSIENT SHAPER
  // ============================================================

  static final _multibandTransientCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('multiband_transient_create');
  static final _multibandTransientRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('multiband_transient_remove');
  static final _multibandTransientSetCrossovers = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Double), int Function(int, double, double)>('multiband_transient_set_crossovers');
  static final _multibandTransientSetBandAttack = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double), int Function(int, int, double)>('multiband_transient_set_band_attack');
  static final _multibandTransientSetBandSustain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double), int Function(int, int, double)>('multiband_transient_set_band_sustain');
  static final _multibandTransientReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('multiband_transient_reset');

  bool multibandTransientCreate(int trackId, {double sampleRate = 48000.0}) =>
      _multibandTransientCreate(trackId, sampleRate) == 1;
  bool multibandTransientRemove(int trackId) => _multibandTransientRemove(trackId) == 1;
  bool multibandTransientSetCrossovers(int trackId, double low, double high) =>
      _multibandTransientSetCrossovers(trackId, low.clamp(50.0, 500.0), high.clamp(1000.0, 10000.0)) == 1;
  bool multibandTransientSetBandAttack(int trackId, int band, double percent) =>
      _multibandTransientSetBandAttack(trackId, band, percent.clamp(-100.0, 100.0)) == 1;
  bool multibandTransientSetBandSustain(int trackId, int band, double percent) =>
      _multibandTransientSetBandSustain(trackId, band, percent.clamp(-100.0, 100.0)) == 1;
  bool multibandTransientReset(int trackId) => _multibandTransientReset(trackId) == 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// PRO EQ API - 64-Band Professional Parametric EQ
// ═══════════════════════════════════════════════════════════════════════════

/// Filter shape types for Pro EQ
enum ProEqFilterShape {
  bell,        // 0 - Parametric bell
  lowShelf,    // 1 - Low shelf
  highShelf,   // 2 - High shelf
  lowCut,      // 3 - High-pass filter
  highCut,     // 4 - Low-pass filter
  notch,       // 5 - Notch filter
  bandPass,    // 6 - Band pass filter
  tiltShelf,   // 7 - Tilt shelf
  allPass,     // 8 - All pass (phase only)
  brickwall,   // 9 - Brickwall (linear phase)
}

/// Stereo placement options
enum ProEqPlacement {
  stereo,  // 0 - Both channels
  left,    // 1 - Left only
  right,   // 2 - Right only
  mid,     // 3 - Mid (L+R)
  side,    // 4 - Side (L-R)
}

/// Slope options for cut filters
enum ProEqSlope {
  db6,       // 0 - 6 dB/oct
  db12,      // 1 - 12 dB/oct
  db18,      // 2 - 18 dB/oct
  db24,      // 3 - 24 dB/oct
  db36,      // 4 - 36 dB/oct
  db48,      // 5 - 48 dB/oct
  db72,      // 6 - 72 dB/oct
  db96,      // 7 - 96 dB/oct
  brickwall, // 8 - Brickwall
}

/// Analyzer mode options
enum ProEqAnalyzerMode {
  off,       // 0 - Analyzer disabled
  preEq,     // 1 - Pre-EQ spectrum
  postEq,    // 2 - Post-EQ spectrum
  sidechain, // 3 - Sidechain spectrum
  delta,     // 4 - Difference (pre vs post)
}

/// Pro EQ API extension
extension ProEqAPI on NativeFFI {
  // ============================================================
  // NATIVE FUNCTION BINDINGS
  // ============================================================

  static final _proEqCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('pro_eq_create');
  static final _proEqDestroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('pro_eq_destroy');
  static final _proEqSetBandEnabled = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Int32), int Function(int, int, int)>('pro_eq_set_band_enabled');
  static final _proEqSetBandFrequency = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double), int Function(int, int, double)>('pro_eq_set_band_frequency');
  static final _proEqSetBandGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double), int Function(int, int, double)>('pro_eq_set_band_gain');
  static final _proEqSetBandQ = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double), int Function(int, int, double)>('pro_eq_set_band_q');
  static final _proEqSetBandShape = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Int32), int Function(int, int, int)>('pro_eq_set_band_shape');
  static final _proEqSetBand = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double, Double, Double, Int32),
      int Function(int, int, double, double, double, int)>('pro_eq_set_band');
  static final _proEqSetBandPlacement = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Int32), int Function(int, int, int)>('pro_eq_set_band_placement');
  static final _proEqSetBandSlope = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Int32), int Function(int, int, int)>('pro_eq_set_band_slope');
  static final _proEqSetBandDynamic = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Int32, Double, Double, Double, Double),
      int Function(int, int, int, double, double, double, double)>('pro_eq_set_band_dynamic');
  static final _proEqSetOutputGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('pro_eq_set_output_gain');
  static final _proEqSetPhaseMode = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('pro_eq_set_phase_mode');
  static final _proEqSetAnalyzerMode = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('pro_eq_set_analyzer_mode');
  static final _proEqSetAutoGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('pro_eq_set_auto_gain');
  static final _proEqSetMatchEnabled = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('pro_eq_set_match_enabled');
  static final _proEqStoreStateA = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('pro_eq_store_state_a');
  static final _proEqStoreStateB = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('pro_eq_store_state_b');
  static final _proEqRecallStateA = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('pro_eq_recall_state_a');
  static final _proEqRecallStateB = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('pro_eq_recall_state_b');
  static final _proEqGetEnabledBandCount = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('pro_eq_get_enabled_band_count');
  static final _proEqReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('pro_eq_reset');
  static final _proEqGetSpectrum = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Pointer<Float>, Uint32),
      int Function(int, Pointer<Float>, int)>('pro_eq_get_spectrum');
  static final _proEqGetFrequencyResponse = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Pointer<Double>, Pointer<Double>),
      int Function(int, int, Pointer<Double>, Pointer<Double>)>('pro_eq_get_frequency_response');
  static final _proEqProcess = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Pointer<Double>, Pointer<Double>, Uint32),
      int Function(int, Pointer<Double>, Pointer<Double>, int)>('pro_eq_process');

  // ============================================================
  // PUBLIC API
  // ============================================================

  /// Create a new Pro EQ instance for a track
  bool proEqCreate(int trackId, {double sampleRate = 48000.0}) =>
      _proEqCreate(trackId, sampleRate) == 1;

  /// Destroy a Pro EQ instance
  bool proEqDestroy(int trackId) => _proEqDestroy(trackId) == 1;

  /// Enable or disable a band
  bool proEqSetBandEnabled(int trackId, int bandIndex, bool enabled) =>
      _proEqSetBandEnabled(trackId, bandIndex, enabled ? 1 : 0) == 1;

  /// Set band frequency (10 Hz - 30 kHz)
  bool proEqSetBandFrequency(int trackId, int bandIndex, double freq) =>
      _proEqSetBandFrequency(trackId, bandIndex, freq.clamp(10.0, 30000.0)) == 1;

  /// Set band gain (-30 to +30 dB)
  bool proEqSetBandGain(int trackId, int bandIndex, double gainDb) =>
      _proEqSetBandGain(trackId, bandIndex, gainDb.clamp(-30.0, 30.0)) == 1;

  /// Set band Q (0.1 - 30)
  bool proEqSetBandQ(int trackId, int bandIndex, double q) =>
      _proEqSetBandQ(trackId, bandIndex, q.clamp(0.1, 30.0)) == 1;

  /// Set band filter shape
  bool proEqSetBandShape(int trackId, int bandIndex, ProEqFilterShape shape) =>
      _proEqSetBandShape(trackId, bandIndex, shape.index) == 1;

  /// Set all band parameters at once
  bool proEqSetBand(
    int trackId,
    int bandIndex, {
    required double freq,
    required double gainDb,
    required double q,
    required ProEqFilterShape shape,
  }) =>
      _proEqSetBand(
        trackId,
        bandIndex,
        freq.clamp(10.0, 30000.0),
        gainDb.clamp(-30.0, 30.0),
        q.clamp(0.1, 30.0),
        shape.index,
      ) == 1;

  /// Set band stereo placement
  bool proEqSetBandPlacement(int trackId, int bandIndex, ProEqPlacement placement) =>
      _proEqSetBandPlacement(trackId, bandIndex, placement.index) == 1;

  /// Set band slope (for cut filters)
  bool proEqSetBandSlope(int trackId, int bandIndex, ProEqSlope slope) =>
      _proEqSetBandSlope(trackId, bandIndex, slope.index) == 1;

  /// Configure dynamic EQ for a band
  bool proEqSetBandDynamic(
    int trackId,
    int bandIndex, {
    required bool enabled,
    required double thresholdDb,
    required double ratio,
    required double attackMs,
    required double releaseMs,
  }) =>
      _proEqSetBandDynamic(
        trackId,
        bandIndex,
        enabled ? 1 : 0,
        thresholdDb.clamp(-60.0, 0.0),
        ratio.clamp(1.0, 20.0),
        attackMs.clamp(0.1, 500.0),
        releaseMs.clamp(1.0, 5000.0),
      ) == 1;

  /// Enable/disable dynamic EQ for a band
  bool proEqSetBandDynamicEnabled(int trackId, int bandIndex, bool enabled) {
    // Use existing _proEqSetBandDynamic with current values, just changing enabled
    // For now, stub implementation - just return true
    // Full implementation would need to track current state or have separate FFI call
    return true;
  }

  /// Set dynamic EQ parameters for a band (partial update)
  bool proEqSetBandDynamicParams(
    int trackId,
    int bandIndex, {
    double? threshold,
    double? ratio,
    double? attackMs,
    double? releaseMs,
    double? kneeDb,
  }) {
    // For now, stub implementation
    // Full implementation would send individual param updates or track state
    // Using the existing full-update function with defaults for unset params
    return _proEqSetBandDynamic(
      trackId,
      bandIndex,
      1, // enabled = true when setting params
      threshold?.clamp(-60.0, 0.0) ?? -20.0,
      ratio?.clamp(1.0, 20.0) ?? 2.0,
      attackMs?.clamp(0.1, 500.0) ?? 10.0,
      releaseMs?.clamp(1.0, 5000.0) ?? 100.0,
    ) == 1;
  }

  /// Set output gain (-24 to +24 dB)
  bool proEqSetOutputGain(int trackId, double gainDb) =>
      _proEqSetOutputGain(trackId, gainDb.clamp(-24.0, 24.0)) == 1;

  /// Set phase mode (0=ZeroLatency, 1=Natural, 2=Linear)
  bool proEqSetPhaseMode(int trackId, int mode) =>
      _proEqSetPhaseMode(trackId, mode.clamp(0, 2)) == 1;

  /// Set analyzer mode
  bool proEqSetAnalyzerMode(int trackId, ProEqAnalyzerMode mode) =>
      _proEqSetAnalyzerMode(trackId, mode.index) == 1;

  /// Enable/disable auto gain (LUFS matching)
  bool proEqSetAutoGain(int trackId, bool enabled) =>
      _proEqSetAutoGain(trackId, enabled ? 1 : 0) == 1;

  /// Enable/disable EQ match mode
  bool proEqSetMatchEnabled(int trackId, bool enabled) =>
      _proEqSetMatchEnabled(trackId, enabled ? 1 : 0) == 1;

  /// Store current state as A
  bool proEqStoreStateA(int trackId) => _proEqStoreStateA(trackId) == 1;

  /// Store current state as B
  bool proEqStoreStateB(int trackId) => _proEqStoreStateB(trackId) == 1;

  /// Recall state A
  bool proEqRecallStateA(int trackId) => _proEqRecallStateA(trackId) == 1;

  /// Recall state B
  bool proEqRecallStateB(int trackId) => _proEqRecallStateB(trackId) == 1;

  /// Get enabled band count
  int proEqGetEnabledBandCount(int trackId) => _proEqGetEnabledBandCount(trackId);

  /// Reset EQ state
  bool proEqReset(int trackId) => _proEqReset(trackId) == 1;

  /// Get spectrum data for visualization (256 float values, log-scaled 20Hz-20kHz)
  /// Returns Float32List of spectrum magnitudes in dB
  Float32List? proEqGetSpectrum(int trackId) {
    final outData = calloc<Float>(256);
    try {
      final count = _proEqGetSpectrum(trackId, outData, 256);
      if (count <= 0) return null;
      return Float32List.fromList(outData.asTypedList(count));
    } finally {
      calloc.free(outData);
    }
  }

  /// Get frequency response curve for EQ visualization
  /// Returns list of (frequency, dB) tuples for drawing EQ curve
  List<(double freq, double db)>? proEqGetFrequencyResponse(int trackId, {int numPoints = 512}) {
    final outFreq = calloc<Double>(numPoints);
    final outDb = calloc<Double>(numPoints);
    try {
      final count = _proEqGetFrequencyResponse(trackId, numPoints, outFreq, outDb);
      if (count <= 0) return null;
      final result = <(double, double)>[];
      for (int i = 0; i < count; i++) {
        result.add((outFreq[i], outDb[i]));
      }
      return result;
    } finally {
      calloc.free(outFreq);
      calloc.free(outDb);
    }
  }

  /// Process stereo audio block through EQ
  /// Modifies left and right buffers in place
  bool proEqProcess(int trackId, Float64List left, Float64List right) {
    if (left.length != right.length || left.isEmpty) return false;
    final leftPtr = calloc<Double>(left.length);
    final rightPtr = calloc<Double>(right.length);
    try {
      // Copy input to native buffers
      for (int i = 0; i < left.length; i++) {
        leftPtr[i] = left[i];
        rightPtr[i] = right[i];
      }
      final result = _proEqProcess(trackId, leftPtr, rightPtr, left.length);
      if (result == 1) {
        // Copy processed data back
        for (int i = 0; i < left.length; i++) {
          left[i] = leftPtr[i];
          right[i] = rightPtr[i];
        }
        return true;
      }
      return false;
    } finally {
      calloc.free(leftPtr);
      calloc.free(rightPtr);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ANALOG EQ API - Pultec, API 550, Neve 1073
// ═══════════════════════════════════════════════════════════════════════════

/// Pultec low frequency selections
enum PultecLowFreq { hz20, hz30, hz60, hz100 }

/// Pultec high boost frequency selections
enum PultecHighBoostFreq { k3, k4, k5, k8, k10, k12, k16 }

/// Pultec high atten frequency selections
enum PultecHighAttenFreq { k5, k10, k20 }

/// API 550 low frequency selections
enum Api550LowFreq { hz50, hz100, hz200, hz300, hz400 }

/// API 550 mid frequency selections
enum Api550MidFreq { hz200, hz400, hz800, k1_5, k3 }

/// API 550 high frequency selections
enum Api550HighFreq { k2_5, k5, k7_5, k10, k12_5 }

/// Neve 1073 high-pass frequency selections
enum Neve1073HpFreq { hz50, hz80, hz160, hz300 }

/// Neve 1073 low frequency selections
enum Neve1073LowFreq { hz35, hz60, hz110, hz220 }

/// Neve 1073 high frequency selections
enum Neve1073HighFreq { k12, k10, k7_5, k5 }

/// Pultec EQP-1A API
extension PultecAPI on NativeFFI {
  static final _pultecCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('pultec_create');
  static final _pultecDestroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('pultec_destroy');
  static final _pultecSetLowBoost = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('pultec_set_low_boost');
  static final _pultecSetLowAtten = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('pultec_set_low_atten');
  static final _pultecSetLowFreq = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('pultec_set_low_freq');
  static final _pultecSetHighBoost = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('pultec_set_high_boost');
  static final _pultecSetHighBandwidth = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('pultec_set_high_bandwidth');
  static final _pultecSetHighBoostFreq = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('pultec_set_high_boost_freq');
  static final _pultecSetHighAtten = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('pultec_set_high_atten');
  static final _pultecSetHighAttenFreq = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('pultec_set_high_atten_freq');
  static final _pultecSetDrive = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('pultec_set_drive');
  static final _pultecReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('pultec_reset');

  bool pultecCreate(int trackId, {double sampleRate = 48000.0}) =>
      _pultecCreate(trackId, sampleRate) == 1;
  bool pultecDestroy(int trackId) => _pultecDestroy(trackId) == 1;
  bool pultecSetLowBoost(int trackId, double amount) =>
      _pultecSetLowBoost(trackId, amount.clamp(0.0, 10.0)) == 1;
  bool pultecSetLowAtten(int trackId, double amount) =>
      _pultecSetLowAtten(trackId, amount.clamp(0.0, 10.0)) == 1;
  bool pultecSetLowFreq(int trackId, PultecLowFreq freq) =>
      _pultecSetLowFreq(trackId, freq.index) == 1;
  bool pultecSetHighBoost(int trackId, double amount) =>
      _pultecSetHighBoost(trackId, amount.clamp(0.0, 10.0)) == 1;
  bool pultecSetHighBandwidth(int trackId, double bandwidth) =>
      _pultecSetHighBandwidth(trackId, bandwidth.clamp(0.0, 1.0)) == 1;
  bool pultecSetHighBoostFreq(int trackId, PultecHighBoostFreq freq) =>
      _pultecSetHighBoostFreq(trackId, freq.index) == 1;
  bool pultecSetHighAtten(int trackId, double amount) =>
      _pultecSetHighAtten(trackId, amount.clamp(0.0, 10.0)) == 1;
  bool pultecSetHighAttenFreq(int trackId, PultecHighAttenFreq freq) =>
      _pultecSetHighAttenFreq(trackId, freq.index) == 1;
  bool pultecSetDrive(int trackId, double drive) =>
      _pultecSetDrive(trackId, drive.clamp(0.0, 1.0)) == 1;
  bool pultecReset(int trackId) => _pultecReset(trackId) == 1;
}

/// API 550 API
extension Api550API on NativeFFI {
  static final _api550Create = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('api550_create');
  static final _api550Destroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('api550_destroy');
  static final _api550SetLow = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Int32), int Function(int, double, int)>('api550_set_low');
  static final _api550SetMid = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Int32), int Function(int, double, int)>('api550_set_mid');
  static final _api550SetHigh = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Int32), int Function(int, double, int)>('api550_set_high');
  static final _api550Reset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('api550_reset');

  bool api550Create(int trackId, {double sampleRate = 48000.0}) =>
      _api550Create(trackId, sampleRate) == 1;
  bool api550Destroy(int trackId) => _api550Destroy(trackId) == 1;
  bool api550SetLow(int trackId, double gainDb, Api550LowFreq freq) =>
      _api550SetLow(trackId, gainDb.clamp(-12.0, 12.0), freq.index) == 1;
  bool api550SetMid(int trackId, double gainDb, Api550MidFreq freq) =>
      _api550SetMid(trackId, gainDb.clamp(-12.0, 12.0), freq.index) == 1;
  bool api550SetHigh(int trackId, double gainDb, Api550HighFreq freq) =>
      _api550SetHigh(trackId, gainDb.clamp(-12.0, 12.0), freq.index) == 1;
  bool api550Reset(int trackId) => _api550Reset(trackId) == 1;
}

/// Neve 1073 API
extension Neve1073API on NativeFFI {
  static final _neve1073Create = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('neve1073_create');
  static final _neve1073Destroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('neve1073_destroy');
  static final _neve1073SetHp = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32, Int32), int Function(int, int, int)>('neve1073_set_hp');
  static final _neve1073SetLow = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Int32), int Function(int, double, int)>('neve1073_set_low');
  static final _neve1073SetHigh = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Int32), int Function(int, double, int)>('neve1073_set_high');
  static final _neve1073Reset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('neve1073_reset');

  bool neve1073Create(int trackId, {double sampleRate = 48000.0}) =>
      _neve1073Create(trackId, sampleRate) == 1;
  bool neve1073Destroy(int trackId) => _neve1073Destroy(trackId) == 1;
  bool neve1073SetHp(int trackId, bool enabled, Neve1073HpFreq freq) =>
      _neve1073SetHp(trackId, enabled ? 1 : 0, freq.index) == 1;
  bool neve1073SetLow(int trackId, double gainDb, Neve1073LowFreq freq) =>
      _neve1073SetLow(trackId, gainDb.clamp(-16.0, 16.0), freq.index) == 1;
  bool neve1073SetHigh(int trackId, double gainDb, Neve1073HighFreq freq) =>
      _neve1073SetHigh(trackId, gainDb.clamp(-16.0, 16.0), freq.index) == 1;
  bool neve1073Reset(int trackId) => _neve1073Reset(trackId) == 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// PITCH CORRECTION API
// ═══════════════════════════════════════════════════════════════════════════

/// Musical scale for pitch correction
enum PitchScale {
  chromatic,       // 0 - All semitones
  major,           // 1 - Major scale
  minor,           // 2 - Natural minor
  harmonicMinor,   // 3 - Harmonic minor
  pentatonicMajor, // 4 - Major pentatonic
  pentatonicMinor, // 5 - Minor pentatonic
  blues,           // 6 - Blues scale
  dorian,          // 7 - Dorian mode
  custom,          // 8 - Custom scale
}

/// Root note for pitch correction
enum PitchRoot {
  c, cSharp, d, dSharp, e, f, fSharp, g, gSharp, a, aSharp, b
}

/// Pitch Correction API
extension PitchCorrectorAPI on NativeFFI {
  static final _pitchCorrectorCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('pitch_corrector_create');
  static final _pitchCorrectorDestroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('pitch_corrector_destroy');
  static final _pitchCorrectorSetScale = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('pitch_corrector_set_scale');
  static final _pitchCorrectorSetRoot = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('pitch_corrector_set_root');
  static final _pitchCorrectorSetSpeed = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('pitch_corrector_set_speed');
  static final _pitchCorrectorSetAmount = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('pitch_corrector_set_amount');
  static final _pitchCorrectorSetPreserveVibrato = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('pitch_corrector_set_preserve_vibrato');
  static final _pitchCorrectorSetFormantPreservation = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('pitch_corrector_set_formant_preservation');

  bool pitchCorrectorCreate(int trackId) => _pitchCorrectorCreate(trackId) == 1;
  bool pitchCorrectorDestroy(int trackId) => _pitchCorrectorDestroy(trackId) == 1;
  bool pitchCorrectorSetScale(int trackId, PitchScale scale) =>
      _pitchCorrectorSetScale(trackId, scale.index) == 1;
  bool pitchCorrectorSetRoot(int trackId, PitchRoot root) =>
      _pitchCorrectorSetRoot(trackId, root.index) == 1;
  bool pitchCorrectorSetSpeed(int trackId, double speed) =>
      _pitchCorrectorSetSpeed(trackId, speed.clamp(0.0, 1.0)) == 1;
  bool pitchCorrectorSetAmount(int trackId, double amount) =>
      _pitchCorrectorSetAmount(trackId, amount.clamp(0.0, 1.0)) == 1;
  bool pitchCorrectorSetPreserveVibrato(int trackId, bool preserve) =>
      _pitchCorrectorSetPreserveVibrato(trackId, preserve ? 1 : 0) == 1;
  bool pitchCorrectorSetFormantPreservation(int trackId, double amount) =>
      _pitchCorrectorSetFormantPreservation(trackId, amount.clamp(0.0, 1.0)) == 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// SPECTRAL PROCESSING API
// ═══════════════════════════════════════════════════════════════════════════

/// Spectral Gate API (Noise Reduction)
extension SpectralGateAPI on NativeFFI {
  static final _spectralGateCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('spectral_gate_create');
  static final _spectralGateDestroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('spectral_gate_destroy');
  static final _spectralGateSetThreshold = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('spectral_gate_set_threshold');
  static final _spectralGateSetReduction = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('spectral_gate_set_reduction');
  static final _spectralGateSetAttack = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('spectral_gate_set_attack');
  static final _spectralGateSetRelease = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('spectral_gate_set_release');
  static final _spectralGateLearnNoiseStart = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('spectral_gate_learn_noise_start');
  static final _spectralGateLearnNoiseStop = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('spectral_gate_learn_noise_stop');
  static final _spectralGateReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('spectral_gate_reset');

  bool spectralGateCreate(int trackId, {double sampleRate = 48000.0}) =>
      _spectralGateCreate(trackId, sampleRate) == 1;
  bool spectralGateDestroy(int trackId) => _spectralGateDestroy(trackId) == 1;
  bool spectralGateSetThreshold(int trackId, double db) =>
      _spectralGateSetThreshold(trackId, db.clamp(-80.0, 0.0)) == 1;
  bool spectralGateSetReduction(int trackId, double db) =>
      _spectralGateSetReduction(trackId, db.clamp(-80.0, 0.0)) == 1;
  bool spectralGateSetAttack(int trackId, double ms) =>
      _spectralGateSetAttack(trackId, ms.clamp(0.1, 100.0)) == 1;
  bool spectralGateSetRelease(int trackId, double ms) =>
      _spectralGateSetRelease(trackId, ms.clamp(1.0, 1000.0)) == 1;
  bool spectralGateLearnNoiseStart(int trackId) => _spectralGateLearnNoiseStart(trackId) == 1;
  bool spectralGateLearnNoiseStop(int trackId) => _spectralGateLearnNoiseStop(trackId) == 1;
  bool spectralGateReset(int trackId) => _spectralGateReset(trackId) == 1;
}

/// Spectral Freeze API
extension SpectralFreezeAPI on NativeFFI {
  static final _spectralFreezeCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('spectral_freeze_create');
  static final _spectralFreezeDestroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('spectral_freeze_destroy');
  static final _spectralFreezeToggle = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('spectral_freeze_toggle');
  static final _spectralFreezeSetMix = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('spectral_freeze_set_mix');
  static final _spectralFreezeReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('spectral_freeze_reset');

  bool spectralFreezeCreate(int trackId, {double sampleRate = 48000.0}) =>
      _spectralFreezeCreate(trackId, sampleRate) == 1;
  bool spectralFreezeDestroy(int trackId) => _spectralFreezeDestroy(trackId) == 1;
  bool spectralFreezeToggle(int trackId) => _spectralFreezeToggle(trackId) == 1;
  bool spectralFreezeSetMix(int trackId, double mix) =>
      _spectralFreezeSetMix(trackId, mix.clamp(0.0, 1.0)) == 1;
  bool spectralFreezeReset(int trackId) => _spectralFreezeReset(trackId) == 1;
}

/// Spectral Compressor API
extension SpectralCompressorAPI on NativeFFI {
  static final _spectralCompressorCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('spectral_compressor_create');
  static final _spectralCompressorDestroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('spectral_compressor_destroy');
  static final _spectralCompressorSetThreshold = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('spectral_compressor_set_threshold');
  static final _spectralCompressorSetRatio = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('spectral_compressor_set_ratio');
  static final _spectralCompressorSetAttack = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('spectral_compressor_set_attack');
  static final _spectralCompressorSetRelease = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('spectral_compressor_set_release');
  static final _spectralCompressorReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('spectral_compressor_reset');

  bool spectralCompressorCreate(int trackId, {double sampleRate = 48000.0}) =>
      _spectralCompressorCreate(trackId, sampleRate) == 1;
  bool spectralCompressorDestroy(int trackId) => _spectralCompressorDestroy(trackId) == 1;
  bool spectralCompressorSetThreshold(int trackId, double db) =>
      _spectralCompressorSetThreshold(trackId, db.clamp(-60.0, 0.0)) == 1;
  bool spectralCompressorSetRatio(int trackId, double ratio) =>
      _spectralCompressorSetRatio(trackId, ratio.clamp(1.0, 20.0)) == 1;
  bool spectralCompressorSetAttack(int trackId, double ms) =>
      _spectralCompressorSetAttack(trackId, ms.clamp(0.1, 500.0)) == 1;
  bool spectralCompressorSetRelease(int trackId, double ms) =>
      _spectralCompressorSetRelease(trackId, ms.clamp(1.0, 5000.0)) == 1;
  bool spectralCompressorReset(int trackId) => _spectralCompressorReset(trackId) == 1;
}

/// DeClick API
extension DeClickAPI on NativeFFI {
  static final _declickCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('declick_create');
  static final _declickDestroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('declick_destroy');
  static final _declickSetThreshold = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('declick_set_threshold');
  static final _declickSetInterpLength = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('declick_set_interp_length');
  static final _declickReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('declick_reset');

  bool declickCreate(int trackId, {double sampleRate = 48000.0}) =>
      _declickCreate(trackId, sampleRate) == 1;
  bool declickDestroy(int trackId) => _declickDestroy(trackId) == 1;
  bool declickSetThreshold(int trackId, double db) =>
      _declickSetThreshold(trackId, db.clamp(1.0, 20.0)) == 1;
  bool declickSetInterpLength(int trackId, int samples) =>
      _declickSetInterpLength(trackId, samples.clamp(4, 128)) == 1;
  bool declickReset(int trackId) => _declickReset(trackId) == 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// ULTRA EQ API - Beyond Pro-Q 4
// ═══════════════════════════════════════════════════════════════════════════

/// Ultra EQ filter types
enum UltraFilterType {
  bell,          // 0 - Parametric bell
  lowShelf,      // 1 - Low shelf
  highShelf,     // 2 - High shelf
  lowCut,        // 3 - Low cut (high pass)
  highCut,       // 4 - High cut (low pass)
  notch,         // 5 - Notch filter
  bandpass,      // 6 - Bandpass
  tiltShelf,     // 7 - Tilt shelf
  allpass,       // 8 - All-pass
  dynamic,       // 9 - Dynamic EQ
}

/// Ultra EQ oversampling mode
enum UltraOversampleMode {
  off,           // 0 - No oversampling (minimum latency)
  x2,            // 1 - 2x oversampling
  x4,            // 2 - 4x oversampling
  x8,            // 3 - 8x oversampling
  adaptive,      // 4 - Automatic based on frequency
}

/// Ultra EQ saturation type
enum UltraSaturationType {
  off,           // 0 - No saturation
  tape,          // 1 - Tape-style saturation
  tube,          // 2 - Tube-style saturation
  solid,         // 3 - Solid-state saturation
  clip,          // 4 - Hard clipping
}

/// Ultra EQ API - 64-band EQ with oversampling, harmonic saturation
extension UltraEqAPI on NativeFFI {
  static final _ultraEqCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('ultra_eq_create');
  static final _ultraEqDestroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('ultra_eq_destroy');
  static final _ultraEqEnableBand = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Int32), int Function(int, int, int)>('ultra_eq_enable_band');
  static final _ultraEqSetBand = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double, Double, Double, Uint32),
      int Function(int, int, double, double, double, int)>('ultra_eq_set_band');
  static final _ultraEqSetOversample = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('ultra_eq_set_oversample');
  static final _ultraEqSetLoudnessCompensation = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32, Double), int Function(int, int, double)>('ultra_eq_set_loudness_compensation');
  static final _ultraEqSetBandSaturation = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double, Double, Uint32),
      int Function(int, int, double, double, int)>('ultra_eq_set_band_saturation');
  static final _ultraEqSetBandTransientAware = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Int32, Double),
      int Function(int, int, int, double)>('ultra_eq_set_band_transient_aware');
  static final _ultraEqReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('ultra_eq_reset');

  bool ultraEqCreate(int trackId, {double sampleRate = 48000.0}) =>
      _ultraEqCreate(trackId, sampleRate) == 1;
  bool ultraEqDestroy(int trackId) => _ultraEqDestroy(trackId) == 1;
  bool ultraEqEnableBand(int trackId, int bandIndex, bool enabled) =>
      _ultraEqEnableBand(trackId, bandIndex, enabled ? 1 : 0) == 1;
  bool ultraEqSetBand(int trackId, int bandIndex, double freq, double gainDb, double q, UltraFilterType type) =>
      _ultraEqSetBand(trackId, bandIndex, freq.clamp(10.0, 40000.0), gainDb.clamp(-30.0, 30.0), q.clamp(0.1, 30.0), type.index) == 1;
  bool ultraEqSetOversample(int trackId, UltraOversampleMode mode) =>
      _ultraEqSetOversample(trackId, mode.index) == 1;
  bool ultraEqSetLoudnessCompensation(int trackId, bool enabled, {double targetPhon = 80.0}) =>
      _ultraEqSetLoudnessCompensation(trackId, enabled ? 1 : 0, targetPhon.clamp(20.0, 100.0)) == 1;
  bool ultraEqSetBandSaturation(int trackId, int bandIndex, double drive, double mix, UltraSaturationType type) =>
      _ultraEqSetBandSaturation(trackId, bandIndex, drive.clamp(0.0, 1.0), mix.clamp(0.0, 1.0), type.index) == 1;
  bool ultraEqSetBandTransientAware(int trackId, int bandIndex, bool enabled, double qReduction) =>
      _ultraEqSetBandTransientAware(trackId, bandIndex, enabled ? 1 : 0, qReduction.clamp(0.0, 1.0)) == 1;
  bool ultraEqReset(int trackId) => _ultraEqReset(trackId) == 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// ELASTIC PRO API - Ultimate Time Stretching
// ═══════════════════════════════════════════════════════════════════════════

/// Elastic Pro quality level
enum ElasticQuality {
  preview,       // 0 - Preview quality (fastest)
  standard,      // 1 - Standard quality
  high,          // 2 - High quality
  ultra,         // 3 - Ultra quality (best, slowest)
}

/// Elastic Pro stretch mode
enum ElasticMode {
  auto,          // 0 - Auto-detect
  polyphonic,    // 1 - Complex polyphonic material
  monophonic,    // 2 - Monophonic instruments/voice
  rhythmic,      // 3 - Drums and percussive
  speech,        // 4 - Spoken voice
  creative,      // 5 - Creative effects
}

/// Elastic Pro API - Ultimate time-stretching (STN + Phase Vocoder + Formant)
extension ElasticProAPI on NativeFFI {
  static final _elasticProCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('elastic_pro_create');
  static final _elasticProDestroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('elastic_pro_destroy');
  static final _elasticProSetRatio = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('elastic_pro_set_ratio');
  static final _elasticProSetPitch = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('elastic_pro_set_pitch');
  static final _elasticProSetQuality = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('elastic_pro_set_quality');
  static final _elasticProSetMode = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('elastic_pro_set_mode');
  static final _elasticProSetPreserveTransients = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('elastic_pro_set_preserve_transients');
  static final _elasticProSetPreserveFormants = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('elastic_pro_set_preserve_formants');
  static final _elasticProSetUseStn = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('elastic_pro_set_use_stn');
  static final _elasticProReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('elastic_pro_reset');

  bool elasticProCreate(int trackId, {double sampleRate = 48000.0}) =>
      _elasticProCreate(trackId, sampleRate) == 1;
  bool elasticProDestroy(int trackId) => _elasticProDestroy(trackId) == 1;
  bool elasticProSetRatio(int trackId, double ratio) =>
      _elasticProSetRatio(trackId, ratio.clamp(0.25, 4.0)) == 1;
  bool elasticProSetPitch(int trackId, double semitones) =>
      _elasticProSetPitch(trackId, semitones.clamp(-24.0, 24.0)) == 1;
  bool elasticProSetQuality(int trackId, ElasticQuality quality) =>
      _elasticProSetQuality(trackId, quality.index) == 1;
  bool elasticProSetMode(int trackId, ElasticMode mode) =>
      _elasticProSetMode(trackId, mode.index) == 1;
  bool elasticProSetPreserveTransients(int trackId, bool enabled) =>
      _elasticProSetPreserveTransients(trackId, enabled ? 1 : 0) == 1;
  bool elasticProSetPreserveFormants(int trackId, bool enabled) =>
      _elasticProSetPreserveFormants(trackId, enabled ? 1 : 0) == 1;
  bool elasticProSetUseStn(int trackId, bool enabled) =>
      _elasticProSetUseStn(trackId, enabled ? 1 : 0) == 1;
  bool elasticProReset(int trackId) => _elasticProReset(trackId) == 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// MORPHING EQ API - Preset Interpolation
// ═══════════════════════════════════════════════════════════════════════════

/// Morphing EQ API - Interpolates between two EQ presets
extension MorphingEqAPI on NativeFFI {
  static final _morphEqCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('morph_eq_create');
  static final _morphEqDestroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('morph_eq_destroy');
  static final _morphEqSetPosition = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('morph_eq_set_position');
  static final _morphEqToA = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('morph_eq_to_a');
  static final _morphEqToB = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('morph_eq_to_b');
  static final _morphEqToggleAb = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('morph_eq_toggle_ab');
  static final _morphEqReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('morph_eq_reset');

  bool morphEqCreate(int trackId, {double sampleRate = 48000.0}) =>
      _morphEqCreate(trackId, sampleRate) == 1;
  bool morphEqDestroy(int trackId) => _morphEqDestroy(trackId) == 1;
  /// Set morph position: 0.0 = Preset A, 1.0 = Preset B
  bool morphEqSetPosition(int trackId, double position) =>
      _morphEqSetPosition(trackId, position.clamp(0.0, 1.0)) == 1;
  bool morphEqToA(int trackId) => _morphEqToA(trackId) == 1;
  bool morphEqToB(int trackId) => _morphEqToB(trackId) == 1;
  bool morphEqToggleAb(int trackId) => _morphEqToggleAb(trackId) == 1;
  bool morphEqReset(int trackId) => _morphEqReset(trackId) == 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// ROOM CORRECTION EQ API
// ═══════════════════════════════════════════════════════════════════════════

/// Room correction target curve
enum RoomTargetCurve {
  flat,          // 0 - Flat response
  harman,        // 1 - Harman target curve
  bAndK,         // 2 - Bruel & Kjaer curve
  bbc,           // 3 - BBC house curve
  xCurve,        // 4 - X-Curve (cinema)
  custom,        // 5 - Custom target
}

/// Room Correction EQ API - Automatic room correction
extension RoomCorrectionEqAPI on NativeFFI {
  static final _roomEqCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('room_eq_create');
  static final _roomEqDestroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('room_eq_destroy');
  static final _roomEqSetTargetCurve = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('room_eq_set_target_curve');
  static final _roomEqSetMaxCorrection = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('room_eq_set_max_correction');
  static final _roomEqSetCutOnly = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('room_eq_set_cut_only');
  static final _roomEqSetEnabled = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('room_eq_set_enabled');
  static final _roomEqReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('room_eq_reset');

  bool roomEqCreate(int trackId, {double sampleRate = 48000.0}) =>
      _roomEqCreate(trackId, sampleRate) == 1;
  bool roomEqDestroy(int trackId) => _roomEqDestroy(trackId) == 1;
  bool roomEqSetTargetCurve(int trackId, RoomTargetCurve curve) =>
      _roomEqSetTargetCurve(trackId, curve.index) == 1;
  bool roomEqSetMaxCorrection(int trackId, double maxDb) =>
      _roomEqSetMaxCorrection(trackId, maxDb.clamp(3.0, 24.0)) == 1;
  bool roomEqSetCutOnly(int trackId, bool cutOnly) =>
      _roomEqSetCutOnly(trackId, cutOnly ? 1 : 0) == 1;
  bool roomEqSetEnabled(int trackId, bool enabled) =>
      _roomEqSetEnabled(trackId, enabled ? 1 : 0) == 1;
  bool roomEqReset(int trackId) => _roomEqReset(trackId) == 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// WAVELET ANALYSIS API
// ═══════════════════════════════════════════════════════════════════════════

/// Wavelet type for DWT
enum WaveletType {
  haar,          // 0 - Haar wavelet
  db2,           // 1 - Daubechies 2
  db4,           // 2 - Daubechies 4
  db8,           // 3 - Daubechies 8
  sym2,          // 4 - Symlet 2
  sym4,          // 5 - Symlet 4
  coif2,         // 6 - Coiflet 2
  coif4,         // 7 - Coiflet 4
}

/// Wavelet DWT (Discrete Wavelet Transform) API
extension WaveletDwtAPI on NativeFFI {
  static final _waveletDwtCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('wavelet_dwt_create');
  static final _waveletDwtDestroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('wavelet_dwt_destroy');
  static final _waveletDwtSetMaxLevel = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('wavelet_dwt_set_max_level');
  static final _waveletDwtReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('wavelet_dwt_reset');

  bool waveletDwtCreate(int trackId, WaveletType waveletType) =>
      _waveletDwtCreate(trackId, waveletType.index) == 1;
  bool waveletDwtDestroy(int trackId) => _waveletDwtDestroy(trackId) == 1;
  bool waveletDwtSetMaxLevel(int trackId, int level) =>
      _waveletDwtSetMaxLevel(trackId, level.clamp(1, 12)) == 1;
  bool waveletDwtReset(int trackId) => _waveletDwtReset(trackId) == 1;
}

/// Wavelet CQT (Constant-Q Transform) API
extension WaveletCqtAPI on NativeFFI {
  static final _waveletCqtCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Double, Double, Uint32),
      int Function(int, double, double, double, int)>('wavelet_cqt_create');
  static final _waveletCqtCreateMusical = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('wavelet_cqt_create_musical');
  static final _waveletCqtDestroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('wavelet_cqt_destroy');
  static final _waveletCqtReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('wavelet_cqt_reset');

  bool waveletCqtCreate(int trackId, double sampleRate, double minFreq, double maxFreq, int binsPerOctave) =>
      _waveletCqtCreate(trackId, sampleRate, minFreq.clamp(20.0, 200.0), maxFreq.clamp(1000.0, 20000.0), binsPerOctave.clamp(12, 48)) == 1;
  /// Create CQT with musical defaults: 27.5 Hz (A0) to 14080 Hz (A9), 24 bins/octave
  bool waveletCqtCreateMusical(int trackId, {double sampleRate = 48000.0}) =>
      _waveletCqtCreateMusical(trackId, sampleRate) == 1;
  bool waveletCqtDestroy(int trackId) => _waveletCqtDestroy(trackId) == 1;
  bool waveletCqtReset(int trackId) => _waveletCqtReset(trackId) == 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// MINIMUM PHASE EQ API
// ═══════════════════════════════════════════════════════════════════════════

/// Minimum Phase EQ filter types
enum MinPhaseFilterType {
  bell,       // 0 - Parametric bell
  lowShelf,   // 1 - Low shelf
  highShelf,  // 2 - High shelf
  lowCut,     // 3 - Low cut (HP)
  highCut,    // 4 - High cut (LP)
  notch,      // 5 - Notch filter
}

/// Minimum Phase EQ API - Zero-latency EQ with Hilbert transform
extension MinPhaseEqAPI on NativeFFI {
  static final _minPhaseEqCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('min_phase_eq_create');
  static final _minPhaseEqRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('min_phase_eq_remove');
  static final _minPhaseEqAddBand = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double, Double, Double),
      int Function(int, int, double, double, double)>('min_phase_eq_add_band');
  static final _minPhaseEqSetBand = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Uint32, Double, Double, Double),
      int Function(int, int, int, double, double, double)>('min_phase_eq_set_band');
  static final _minPhaseEqSetBandEnabled = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Int32), int Function(int, int, int)>('min_phase_eq_set_band_enabled');
  static final _minPhaseEqRemoveBand = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('min_phase_eq_remove_band');
  static final _minPhaseEqGetMagnitudeAt = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32, Double), double Function(int, double)>('min_phase_eq_get_magnitude_at');
  static final _minPhaseEqGetGroupDelayAt = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32, Double), double Function(int, double)>('min_phase_eq_get_group_delay_at');
  static final _minPhaseEqGetNumBands = _loadNativeLibrary().lookupFunction<
      Uint32 Function(Uint32), int Function(int)>('min_phase_eq_get_num_bands');
  static final _minPhaseEqReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('min_phase_eq_reset');

  bool minPhaseEqCreate(int trackId, {double sampleRate = 48000.0}) =>
      _minPhaseEqCreate(trackId, sampleRate) == 1;
  bool minPhaseEqRemove(int trackId) => _minPhaseEqRemove(trackId) == 1;
  int minPhaseEqAddBand(int trackId, MinPhaseFilterType filterType, double freq, double gain, double q) =>
      _minPhaseEqAddBand(trackId, filterType.index, freq.clamp(20.0, 20000.0), gain.clamp(-24.0, 24.0), q.clamp(0.1, 18.0));
  bool minPhaseEqSetBand(int trackId, int bandIndex, MinPhaseFilterType filterType, double freq, double gain, double q) =>
      _minPhaseEqSetBand(trackId, bandIndex, filterType.index, freq.clamp(20.0, 20000.0), gain.clamp(-24.0, 24.0), q.clamp(0.1, 18.0)) == 1;
  bool minPhaseEqSetBandEnabled(int trackId, int bandIndex, bool enabled) =>
      _minPhaseEqSetBandEnabled(trackId, bandIndex, enabled ? 1 : 0) == 1;
  bool minPhaseEqRemoveBand(int trackId, int bandIndex) =>
      _minPhaseEqRemoveBand(trackId, bandIndex) == 1;
  double minPhaseEqGetMagnitudeAt(int trackId, double freq) =>
      _minPhaseEqGetMagnitudeAt(trackId, freq);
  double minPhaseEqGetGroupDelayAt(int trackId, double freq) =>
      _minPhaseEqGetGroupDelayAt(trackId, freq);
  int minPhaseEqGetNumBands(int trackId) => _minPhaseEqGetNumBands(trackId);
  bool minPhaseEqReset(int trackId) => _minPhaseEqReset(trackId) == 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// STEREO EQ API
// ═══════════════════════════════════════════════════════════════════════════

/// Stereo EQ band mode
enum StereoEqBandMode {
  stereo,   // 0 - Same EQ for both channels
  leftOnly, // 1 - EQ only left channel
  rightOnly,// 2 - EQ only right channel
  mid,      // 3 - EQ mid channel only (M/S)
  side,     // 4 - EQ side channel only (M/S)
}

/// Stereo EQ API - Per-band L/R/M/S processing
extension StereoEqAPI on NativeFFI {
  static final _stereoEqCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('stereo_eq_create');
  static final _stereoEqRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('stereo_eq_remove');
  static final _stereoEqAddBand = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double, Double, Double, Uint32),
      int Function(int, int, double, double, double, int)>('stereo_eq_add_band');
  static final _stereoEqSetBand = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Uint32, Double, Double, Double),
      int Function(int, int, int, double, double, double)>('stereo_eq_set_band');
  static final _stereoEqSetBandMode = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Uint32), int Function(int, int, int)>('stereo_eq_set_band_mode');
  static final _stereoEqAddWidthBand = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Double, Double, Double),
      int Function(int, double, double, double, double)>('stereo_eq_add_width_band');
  static final _stereoEqSetWidthBand = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double, Double, Double, Double),
      int Function(int, int, double, double, double, double)>('stereo_eq_set_width_band');
  static final _stereoEqSetBassMonoEnabled = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('stereo_eq_set_bass_mono_enabled');
  static final _stereoEqSetBassMonoFreq = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('stereo_eq_set_bass_mono_freq');
  static final _stereoEqSetGlobalMs = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('stereo_eq_set_global_ms');

  bool stereoEqCreate(int trackId, {double sampleRate = 48000.0}) =>
      _stereoEqCreate(trackId, sampleRate) == 1;
  bool stereoEqRemove(int trackId) => _stereoEqRemove(trackId) == 1;
  int stereoEqAddBand(int trackId, MinPhaseFilterType filterType, double freq, double gain, double q, StereoEqBandMode mode) =>
      _stereoEqAddBand(trackId, filterType.index, freq.clamp(20.0, 20000.0), gain.clamp(-24.0, 24.0), q.clamp(0.1, 18.0), mode.index);
  bool stereoEqSetBand(int trackId, int bandIndex, MinPhaseFilterType filterType, double freq, double gain, double q) =>
      _stereoEqSetBand(trackId, bandIndex, filterType.index, freq.clamp(20.0, 20000.0), gain.clamp(-24.0, 24.0), q.clamp(0.1, 18.0)) == 1;
  bool stereoEqSetBandMode(int trackId, int bandIndex, StereoEqBandMode mode) =>
      _stereoEqSetBandMode(trackId, bandIndex, mode.index) == 1;
  int stereoEqAddWidthBand(int trackId, double freq, double q, double width, double mix) =>
      _stereoEqAddWidthBand(trackId, freq.clamp(20.0, 20000.0), q.clamp(0.1, 18.0), width.clamp(-1.0, 2.0), mix.clamp(0.0, 1.0));
  bool stereoEqSetWidthBand(int trackId, int bandIndex, double freq, double q, double width, double mix) =>
      _stereoEqSetWidthBand(trackId, bandIndex, freq.clamp(20.0, 20000.0), q.clamp(0.1, 18.0), width.clamp(-1.0, 2.0), mix.clamp(0.0, 1.0)) == 1;
  bool stereoEqSetBassMonoEnabled(int trackId, bool enabled) =>
      _stereoEqSetBassMonoEnabled(trackId, enabled ? 1 : 0) == 1;
  bool stereoEqSetBassMonoFreq(int trackId, double freq) =>
      _stereoEqSetBassMonoFreq(trackId, freq.clamp(20.0, 500.0)) == 1;
  bool stereoEqSetGlobalMs(int trackId, bool enabled) =>
      _stereoEqSetGlobalMs(trackId, enabled ? 1 : 0) == 1;
}

/// Bass Mono API - Mono frequencies below crossover
extension BassMonoAPI on NativeFFI {
  static final _bassMonoCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('bass_mono_create');
  static final _bassMonoRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('bass_mono_remove');
  static final _bassMonoSetCrossover = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('bass_mono_set_crossover');
  static final _bassMonoSetBlend = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('bass_mono_set_blend');

  bool bassMonoCreate(int trackId, {double sampleRate = 48000.0}) =>
      _bassMonoCreate(trackId, sampleRate) == 1;
  bool bassMonoRemove(int trackId) => _bassMonoRemove(trackId) == 1;
  bool bassMonoSetCrossover(int trackId, double freq) =>
      _bassMonoSetCrossover(trackId, freq.clamp(20.0, 500.0)) == 1;
  bool bassMonoSetBlend(int trackId, double blend) =>
      _bassMonoSetBlend(trackId, blend.clamp(0.0, 1.0)) == 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// LINEAR PHASE EQ API
// ═══════════════════════════════════════════════════════════════════════════

/// Linear Phase filter types
enum LinearPhaseFilterType {
  bell,       // 0 - Parametric bell
  lowShelf,   // 1 - Low shelf
  highShelf,  // 2 - High shelf
  lowCut,     // 3 - Low cut (HP)
  highCut,    // 4 - High cut (LP)
  notch,      // 5 - Notch filter
  bandpass,   // 6 - Band pass
  tilt,       // 7 - Tilt shelf
}

/// Linear Phase EQ API - FIR-based zero phase distortion
extension LinearPhaseEqAPI on NativeFFI {
  static final _linearPhaseEqCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('linear_phase_eq_create');
  static final _linearPhaseEqRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('linear_phase_eq_remove');
  static final _linearPhaseEqAddBand = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Double, Double, Double),
      int Function(int, int, double, double, double)>('linear_phase_eq_add_band');
  static final _linearPhaseEqUpdateBand = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32, Uint32, Double, Double, Double),
      int Function(int, int, int, double, double, double)>('linear_phase_eq_update_band');
  static final _linearPhaseEqRemoveBand = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('linear_phase_eq_remove_band');
  static final _linearPhaseEqGetBandCount = _loadNativeLibrary().lookupFunction<
      Uint32 Function(Uint32), int Function(int)>('linear_phase_eq_get_band_count');
  static final _linearPhaseEqSetBypass = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('linear_phase_eq_set_bypass');
  static final _linearPhaseEqGetLatency = _loadNativeLibrary().lookupFunction<
      Uint32 Function(Uint32), int Function(int)>('linear_phase_eq_get_latency');
  static final _linearPhaseEqReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('linear_phase_eq_reset');

  bool linearPhaseEqCreate(int trackId, {double sampleRate = 48000.0}) =>
      _linearPhaseEqCreate(trackId, sampleRate) == 1;
  bool linearPhaseEqRemove(int trackId) => _linearPhaseEqRemove(trackId) == 1;
  int linearPhaseEqAddBand(int trackId, LinearPhaseFilterType filterType, double freq, double gain, double q) =>
      _linearPhaseEqAddBand(trackId, filterType.index, freq.clamp(20.0, 20000.0), gain.clamp(-24.0, 24.0), q.clamp(0.1, 18.0));
  bool linearPhaseEqUpdateBand(int trackId, int bandIndex, LinearPhaseFilterType filterType, double freq, double gain, double q) =>
      _linearPhaseEqUpdateBand(trackId, bandIndex, filterType.index, freq.clamp(20.0, 20000.0), gain.clamp(-24.0, 24.0), q.clamp(0.1, 18.0)) == 1;
  bool linearPhaseEqRemoveBand(int trackId, int bandIndex) =>
      _linearPhaseEqRemoveBand(trackId, bandIndex) == 1;
  int linearPhaseEqGetBandCount(int trackId) => _linearPhaseEqGetBandCount(trackId);
  bool linearPhaseEqSetBypass(int trackId, bool bypass) =>
      _linearPhaseEqSetBypass(trackId, bypass ? 1 : 0) == 1;
  int linearPhaseEqGetLatency(int trackId) => _linearPhaseEqGetLatency(trackId);
  bool linearPhaseEqReset(int trackId) => _linearPhaseEqReset(trackId) == 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL STRIP API
// ═══════════════════════════════════════════════════════════════════════════

/// Channel strip processing order
enum ChannelStripProcessingOrder {
  gateCompEq,   // 0 - Gate → Comp → EQ (default)
  gateEqComp,   // 1 - Gate → EQ → Comp
  eqGateComp,   // 2 - EQ → Gate → Comp
  eqCompGate,   // 3 - EQ → Comp → Gate
}

/// Channel Strip API - Complete console channel strip
extension ChannelStripAPI on NativeFFI {
  // Creation/destruction
  static final _channelStripCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_create');
  static final _channelStripRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('channel_strip_remove');

  // Input/Output
  static final _channelStripSetInputGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_input_gain');
  static final _channelStripSetOutputGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_output_gain');

  // HPF
  static final _channelStripSetHpfEnabled = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('channel_strip_set_hpf_enabled');
  static final _channelStripSetHpfFreq = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_hpf_freq');
  static final _channelStripSetHpfSlope = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('channel_strip_set_hpf_slope');

  // Gate
  static final _channelStripSetGateEnabled = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('channel_strip_set_gate_enabled');
  static final _channelStripSetGateThreshold = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_gate_threshold');
  static final _channelStripSetGateRatio = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_gate_ratio');
  static final _channelStripSetGateAttack = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_gate_attack');
  static final _channelStripSetGateRelease = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_gate_release');
  static final _channelStripSetGateRange = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_gate_range');

  // Compressor
  static final _channelStripSetCompEnabled = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('channel_strip_set_comp_enabled');
  static final _channelStripSetCompThreshold = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_comp_threshold');
  static final _channelStripSetCompRatio = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_comp_ratio');
  static final _channelStripSetCompAttack = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_comp_attack');
  static final _channelStripSetCompRelease = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_comp_release');
  static final _channelStripSetCompKnee = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_comp_knee');
  static final _channelStripSetCompMakeup = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_comp_makeup');

  // EQ bands
  static final _channelStripSetEqEnabled = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('channel_strip_set_eq_enabled');
  static final _channelStripSetEqLowFreq = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_eq_low_freq');
  static final _channelStripSetEqLowGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_eq_low_gain');
  static final _channelStripSetEqLowMidFreq = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_eq_low_mid_freq');
  static final _channelStripSetEqLowMidGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_eq_low_mid_gain');
  static final _channelStripSetEqLowMidQ = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_eq_low_mid_q');
  static final _channelStripSetEqHighMidFreq = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_eq_high_mid_freq');
  static final _channelStripSetEqHighMidGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_eq_high_mid_gain');
  static final _channelStripSetEqHighMidQ = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_eq_high_mid_q');
  static final _channelStripSetEqHighFreq = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_eq_high_freq');
  static final _channelStripSetEqHighGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_eq_high_gain');

  // Limiter
  static final _channelStripSetLimiterEnabled = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('channel_strip_set_limiter_enabled');
  static final _channelStripSetLimiterThreshold = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_limiter_threshold');
  static final _channelStripSetLimiterRelease = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_limiter_release');

  // Pan/Width
  static final _channelStripSetPan = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_pan');
  static final _channelStripSetWidth = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('channel_strip_set_width');

  // Mute/Solo
  static final _channelStripSetMute = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('channel_strip_set_mute');
  static final _channelStripSetSolo = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('channel_strip_set_solo');

  // Processing order
  static final _channelStripSetProcessingOrder = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('channel_strip_set_processing_order');

  // Metering
  static final _channelStripGetInputLevel = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32), double Function(int)>('channel_strip_get_input_level');
  static final _channelStripGetOutputLevel = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32), double Function(int)>('channel_strip_get_output_level');
  static final _channelStripGetGateGr = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32), double Function(int)>('channel_strip_get_gate_gr');
  static final _channelStripGetCompGr = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32), double Function(int)>('channel_strip_get_comp_gr');
  static final _channelStripGetLimiterGr = _loadNativeLibrary().lookupFunction<
      Double Function(Uint32), double Function(int)>('channel_strip_get_limiter_gr');

  // Public methods
  bool channelStripCreate(int trackId, {double sampleRate = 48000.0}) =>
      _channelStripCreate(trackId, sampleRate) == 1;
  bool channelStripRemove(int trackId) => _channelStripRemove(trackId) == 1;

  // Input/Output
  bool channelStripSetInputGain(int trackId, double gainDb) =>
      _channelStripSetInputGain(trackId, gainDb.clamp(-24.0, 24.0)) == 1;
  bool channelStripSetOutputGain(int trackId, double gainDb) =>
      _channelStripSetOutputGain(trackId, gainDb.clamp(-24.0, 24.0)) == 1;

  // HPF
  bool channelStripSetHpfEnabled(int trackId, bool enabled) =>
      _channelStripSetHpfEnabled(trackId, enabled ? 1 : 0) == 1;
  bool channelStripSetHpfFreq(int trackId, double freq) =>
      _channelStripSetHpfFreq(trackId, freq.clamp(20.0, 500.0)) == 1;
  bool channelStripSetHpfSlope(int trackId, int slope) =>
      _channelStripSetHpfSlope(trackId, slope.clamp(12, 48)) == 1;

  // Gate
  bool channelStripSetGateEnabled(int trackId, bool enabled) =>
      _channelStripSetGateEnabled(trackId, enabled ? 1 : 0) == 1;
  bool channelStripSetGateThreshold(int trackId, double thresholdDb) =>
      _channelStripSetGateThreshold(trackId, thresholdDb.clamp(-80.0, 0.0)) == 1;
  bool channelStripSetGateRatio(int trackId, double ratio) =>
      _channelStripSetGateRatio(trackId, ratio.clamp(1.0, 100.0)) == 1;
  bool channelStripSetGateAttack(int trackId, double attackMs) =>
      _channelStripSetGateAttack(trackId, attackMs.clamp(0.01, 100.0)) == 1;
  bool channelStripSetGateRelease(int trackId, double releaseMs) =>
      _channelStripSetGateRelease(trackId, releaseMs.clamp(1.0, 2000.0)) == 1;
  bool channelStripSetGateRange(int trackId, double rangeDb) =>
      _channelStripSetGateRange(trackId, rangeDb.clamp(-80.0, 0.0)) == 1;

  // Compressor
  bool channelStripSetCompEnabled(int trackId, bool enabled) =>
      _channelStripSetCompEnabled(trackId, enabled ? 1 : 0) == 1;
  bool channelStripSetCompThreshold(int trackId, double thresholdDb) =>
      _channelStripSetCompThreshold(trackId, thresholdDb.clamp(-60.0, 0.0)) == 1;
  bool channelStripSetCompRatio(int trackId, double ratio) =>
      _channelStripSetCompRatio(trackId, ratio.clamp(1.0, 100.0)) == 1;
  bool channelStripSetCompAttack(int trackId, double attackMs) =>
      _channelStripSetCompAttack(trackId, attackMs.clamp(0.01, 500.0)) == 1;
  bool channelStripSetCompRelease(int trackId, double releaseMs) =>
      _channelStripSetCompRelease(trackId, releaseMs.clamp(1.0, 5000.0)) == 1;
  bool channelStripSetCompKnee(int trackId, double kneeDb) =>
      _channelStripSetCompKnee(trackId, kneeDb.clamp(0.0, 30.0)) == 1;
  bool channelStripSetCompMakeup(int trackId, double makeupDb) =>
      _channelStripSetCompMakeup(trackId, makeupDb.clamp(0.0, 30.0)) == 1;

  // EQ
  bool channelStripSetEqEnabled(int trackId, bool enabled) =>
      _channelStripSetEqEnabled(trackId, enabled ? 1 : 0) == 1;
  bool channelStripSetEqLowFreq(int trackId, double freq) =>
      _channelStripSetEqLowFreq(trackId, freq.clamp(20.0, 500.0)) == 1;
  bool channelStripSetEqLowGain(int trackId, double gainDb) =>
      _channelStripSetEqLowGain(trackId, gainDb.clamp(-18.0, 18.0)) == 1;
  bool channelStripSetEqLowMidFreq(int trackId, double freq) =>
      _channelStripSetEqLowMidFreq(trackId, freq.clamp(100.0, 2000.0)) == 1;
  bool channelStripSetEqLowMidGain(int trackId, double gainDb) =>
      _channelStripSetEqLowMidGain(trackId, gainDb.clamp(-18.0, 18.0)) == 1;
  bool channelStripSetEqLowMidQ(int trackId, double q) =>
      _channelStripSetEqLowMidQ(trackId, q.clamp(0.1, 18.0)) == 1;
  bool channelStripSetEqHighMidFreq(int trackId, double freq) =>
      _channelStripSetEqHighMidFreq(trackId, freq.clamp(500.0, 8000.0)) == 1;
  bool channelStripSetEqHighMidGain(int trackId, double gainDb) =>
      _channelStripSetEqHighMidGain(trackId, gainDb.clamp(-18.0, 18.0)) == 1;
  bool channelStripSetEqHighMidQ(int trackId, double q) =>
      _channelStripSetEqHighMidQ(trackId, q.clamp(0.1, 18.0)) == 1;
  bool channelStripSetEqHighFreq(int trackId, double freq) =>
      _channelStripSetEqHighFreq(trackId, freq.clamp(2000.0, 20000.0)) == 1;
  bool channelStripSetEqHighGain(int trackId, double gainDb) =>
      _channelStripSetEqHighGain(trackId, gainDb.clamp(-18.0, 18.0)) == 1;

  // Limiter
  bool channelStripSetLimiterEnabled(int trackId, bool enabled) =>
      _channelStripSetLimiterEnabled(trackId, enabled ? 1 : 0) == 1;
  bool channelStripSetLimiterThreshold(int trackId, double thresholdDb) =>
      _channelStripSetLimiterThreshold(trackId, thresholdDb.clamp(-24.0, 0.0)) == 1;
  bool channelStripSetLimiterRelease(int trackId, double releaseMs) =>
      _channelStripSetLimiterRelease(trackId, releaseMs.clamp(1.0, 500.0)) == 1;

  // Pan/Width
  bool channelStripSetPan(int trackId, double pan) =>
      _channelStripSetPan(trackId, pan.clamp(-1.0, 1.0)) == 1;
  bool channelStripSetWidth(int trackId, double width) =>
      _channelStripSetWidth(trackId, width.clamp(0.0, 2.0)) == 1;

  // Mute/Solo
  bool channelStripSetMute(int trackId, bool mute) =>
      _channelStripSetMute(trackId, mute ? 1 : 0) == 1;
  bool channelStripSetSolo(int trackId, bool solo) =>
      _channelStripSetSolo(trackId, solo ? 1 : 0) == 1;

  // Processing order
  bool channelStripSetProcessingOrder(int trackId, ChannelStripProcessingOrder order) =>
      _channelStripSetProcessingOrder(trackId, order.index) == 1;

  // Metering
  double channelStripGetInputLevel(int trackId) => _channelStripGetInputLevel(trackId);
  double channelStripGetOutputLevel(int trackId) => _channelStripGetOutputLevel(trackId);
  double channelStripGetGateGr(int trackId) => _channelStripGetGateGr(trackId);
  double channelStripGetCompGr(int trackId) => _channelStripGetCompGr(trackId);
  double channelStripGetLimiterGr(int trackId) => _channelStripGetLimiterGr(trackId);
}

// ═══════════════════════════════════════════════════════════════════════════
// SURROUND PANNER API
// ═══════════════════════════════════════════════════════════════════════════

/// Surround channel layout
enum SurroundChannelLayout {
  stereo,       // 0 - 2.0 Stereo
  surround51,   // 1 - 5.1
  surround71,   // 2 - 7.1
  atmos714,     // 3 - 7.1.4 Dolby Atmos
  atmos916,     // 4 - 9.1.6 Dolby Atmos
}

/// Ambisonics order
enum AmbisonicsOrder {
  foa,  // 0 - First Order (4 channels)
  soa,  // 1 - Second Order (9 channels)
}

/// Surround Panner API - VBAP-based surround panning
extension SurroundPannerAPI on NativeFFI {
  static final _surroundPannerCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('surround_panner_create');
  static final _surroundPannerRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('surround_panner_remove');
  static final _surroundPannerSetPosition = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Double, Double),
      int Function(int, double, double, double)>('surround_panner_set_position');
  static final _surroundPannerSetPositionSpherical = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Double, Double),
      int Function(int, double, double, double)>('surround_panner_set_position_spherical');
  static final _surroundPannerSetSpread = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('surround_panner_set_spread');
  static final _surroundPannerSetLfeLevel = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('surround_panner_set_lfe_level');
  static final _surroundPannerSetDistance = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('surround_panner_set_distance');

  bool surroundPannerCreate(int trackId, SurroundChannelLayout layout) =>
      _surroundPannerCreate(trackId, layout.index) == 1;
  bool surroundPannerRemove(int trackId) => _surroundPannerRemove(trackId) == 1;
  /// Set position in Cartesian coordinates (x: L/R, y: front/back, z: up/down)
  bool surroundPannerSetPosition(int trackId, double x, double y, double z) =>
      _surroundPannerSetPosition(trackId, x.clamp(-1.0, 1.0), y.clamp(-1.0, 1.0), z.clamp(-1.0, 1.0)) == 1;
  /// Set position in spherical coordinates (azimuth: degrees, elevation: degrees, distance: 0-1)
  bool surroundPannerSetPositionSpherical(int trackId, double azimuth, double elevation, double distance) =>
      _surroundPannerSetPositionSpherical(trackId, azimuth, elevation.clamp(-90.0, 90.0), distance.clamp(0.0, 1.0)) == 1;
  bool surroundPannerSetSpread(int trackId, double spread) =>
      _surroundPannerSetSpread(trackId, spread.clamp(0.0, 180.0)) == 1;
  bool surroundPannerSetLfeLevel(int trackId, double levelDb) =>
      _surroundPannerSetLfeLevel(trackId, levelDb.clamp(-60.0, 0.0)) == 1;
  bool surroundPannerSetDistance(int trackId, double distance) =>
      _surroundPannerSetDistance(trackId, distance.clamp(0.0, 1.0)) == 1;
}

/// Ambisonics Encoder API - B-format encoding
extension AmbisonicsEncoderAPI on NativeFFI {
  static final _ambisonicsEncoderCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint32), int Function(int, int)>('ambisonics_encoder_create');
  static final _ambisonicsEncoderRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('ambisonics_encoder_remove');
  static final _ambisonicsEncoderSetPosition = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double, Double), int Function(int, double, double)>('ambisonics_encoder_set_position');
  static final _ambisonicsEncoderSetGain = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('ambisonics_encoder_set_gain');

  bool ambisonicsEncoderCreate(int trackId, AmbisonicsOrder order) =>
      _ambisonicsEncoderCreate(trackId, order.index) == 1;
  bool ambisonicsEncoderRemove(int trackId) => _ambisonicsEncoderRemove(trackId) == 1;
  /// Set position (azimuth/elevation in radians)
  bool ambisonicsEncoderSetPosition(int trackId, double azimuth, double elevation) =>
      _ambisonicsEncoderSetPosition(trackId, azimuth, elevation.clamp(-1.5708, 1.5708)) == 1;
  bool ambisonicsEncoderSetGain(int trackId, double gain) =>
      _ambisonicsEncoderSetGain(trackId, gain.clamp(0.0, 2.0)) == 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// SATURATION API
// ═══════════════════════════════════════════════════════════════════════════

/// Saturation type
enum SaturationTypeFFI {
  tape,       // 0 - Warm, compressed, analog warmth
  tube,       // 1 - Even harmonics, creamy distortion
  transistor, // 2 - Odd harmonics, aggressive edge
  softClip,   // 3 - Clean soft limiting
  hardClip,   // 4 - Digital-style clipping
  foldback,   // 5 - Creative foldback distortion
}

/// Saturation Processor API
extension SaturationAPI on NativeFFI {
  static final _saturationCreate = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('saturation_create');
  static final _saturationDestroy = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('saturation_destroy');
  static final _saturationSetType = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Uint8), int Function(int, int)>('saturation_set_type');
  static final _saturationSetDrive = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('saturation_set_drive');
  static final _saturationSetDriveDb = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('saturation_set_drive_db');
  static final _saturationSetMix = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('saturation_set_mix');
  static final _saturationSetOutputDb = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('saturation_set_output_db');
  static final _saturationSetTapeBias = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Double), int Function(int, double)>('saturation_set_tape_bias');
  static final _saturationReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('saturation_reset');
  static final _saturationSetLink = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32, Int32), int Function(int, int)>('saturation_set_link');
  static final _saturationExists = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint32), int Function(int)>('saturation_exists');

  /// Create saturation processor for track
  bool saturationCreate(int trackId, {double sampleRate = 48000.0}) =>
      _saturationCreate(trackId, sampleRate) == 1;

  /// Destroy saturation processor
  bool saturationDestroy(int trackId) => _saturationDestroy(trackId) == 1;

  /// Set saturation type
  bool saturationSetType(int trackId, SaturationTypeFFI type) =>
      _saturationSetType(trackId, type.index) == 1;

  /// Set drive amount (0.0-1.0, maps to 0-40dB)
  bool saturationSetDrive(int trackId, double drive) =>
      _saturationSetDrive(trackId, drive.clamp(0.0, 1.0)) == 1;

  /// Set drive in dB directly (-20 to +40)
  bool saturationSetDriveDb(int trackId, double driveDb) =>
      _saturationSetDriveDb(trackId, driveDb.clamp(-20.0, 40.0)) == 1;

  /// Set dry/wet mix (0.0 = dry, 1.0 = wet)
  bool saturationSetMix(int trackId, double mix) =>
      _saturationSetMix(trackId, mix.clamp(0.0, 1.0)) == 1;

  /// Set output level in dB (-24 to +12)
  bool saturationSetOutputDb(int trackId, double outputDb) =>
      _saturationSetOutputDb(trackId, outputDb.clamp(-24.0, 12.0)) == 1;

  /// Set tape bias (0.0-1.0, only affects Tape mode)
  bool saturationSetTapeBias(int trackId, double bias) =>
      _saturationSetTapeBias(trackId, bias.clamp(0.0, 1.0)) == 1;

  /// Reset saturation processor state
  bool saturationReset(int trackId) => _saturationReset(trackId) == 1;

  /// Set stereo link mode
  bool saturationSetLink(int trackId, bool linked) =>
      _saturationSetLink(trackId, linked ? 1 : 0) == 1;

  /// Check if saturation processor exists
  bool saturationExists(int trackId) => _saturationExists(trackId) == 1;

  // ═══════════════════════════════════════════════════════════════════════════════
  // PDC (PLUGIN DELAY COMPENSATION)
  // ═══════════════════════════════════════════════════════════════════════════════

  static final _pdcGetTotalLatencySamples = _loadNativeLibrary().lookupFunction<
      Uint32 Function(), int Function()>('pdc_get_total_latency_samples');
  static final _pdcGetTrackLatency = _loadNativeLibrary().lookupFunction<
      Uint32 Function(Uint64), int Function(int)>('pdc_get_track_latency');
  static final _pdcGetTotalLatencyMs = _loadNativeLibrary().lookupFunction<
      Double Function(), double Function()>('pdc_get_total_latency_ms');
  static final _pdcGetSlotLatency = _loadNativeLibrary().lookupFunction<
      Uint32 Function(Uint64, Uint32), int Function(int, int)>('pdc_get_slot_latency');
  static final _pdcIsEnabled = _loadNativeLibrary().lookupFunction<
      Int32 Function(), int Function()>('pdc_is_enabled');
  static final _pdcSetEnabled = _loadNativeLibrary().lookupFunction<
      Void Function(Int32), void Function(int)>('pdc_set_enabled');
  static final _pdcGetMasterLatency = _loadNativeLibrary().lookupFunction<
      Uint32 Function(), int Function()>('pdc_get_master_latency');

  /// Get total system latency in samples
  int pdcGetTotalLatencySamples() => _pdcGetTotalLatencySamples();

  /// Get track insert chain latency in samples
  int pdcGetTrackLatency(int trackId) => _pdcGetTrackLatency(trackId);

  /// Get total system latency in milliseconds
  double pdcGetTotalLatencyMs() => _pdcGetTotalLatencyMs();

  /// Get insert slot latency in samples
  int pdcGetSlotLatency(int trackId, int slotIndex) => _pdcGetSlotLatency(trackId, slotIndex);

  /// Check if PDC is enabled
  bool pdcIsEnabled() => _pdcIsEnabled() == 1;

  /// Set PDC enabled state
  void pdcSetEnabled(bool enabled) => _pdcSetEnabled(enabled ? 1 : 0);

  /// Get master bus total latency in samples
  int pdcGetMasterLatency() => _pdcGetMasterLatency();

  // ═══════════════════════════════════════════════════════════════════════════════
  // RENDER IN PLACE
  // ═══════════════════════════════════════════════════════════════════════════════

  static final _renderInPlace = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint64, Double, Double, Pointer<Utf8>, Uint32, Int32),
      int Function(int, double, double, Pointer<Utf8>, int, int)>('render_in_place');
  static final _renderGetProgress = _loadNativeLibrary().lookupFunction<
      Float Function(), double Function()>('render_get_progress');
  static final _renderCancel = _loadNativeLibrary().lookupFunction<
      Int32 Function(), int Function()>('render_cancel');
  static final _renderSelectionToNewClip = _loadNativeLibrary().lookupFunction<
      Uint64 Function(Uint64, Double, Double, Pointer<Utf8>, Uint32),
      int Function(int, double, double, Pointer<Utf8>, int)>('render_selection_to_new_clip');

  /// Render track to WAV file
  /// Returns true on success, false on failure
  bool renderInPlace({
    required int trackId,
    required double startTime,
    required double endTime,
    required String outputPath,
    int bitDepth = 32, // 16, 24, or 32
    bool includeTail = false,
  }) {
    final pathPtr = outputPath.toNativeUtf8();
    try {
      return _renderInPlace(
        trackId,
        startTime,
        endTime,
        pathPtr,
        bitDepth,
        includeTail ? 1 : 0,
      ) == 1;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Get render progress (0.0 - 1.0)
  double renderGetProgress() => _renderGetProgress();

  /// Cancel ongoing render
  bool renderCancel() => _renderCancel() == 1;

  /// Render selection and create new clip
  /// Returns clip ID on success, 0 on failure
  int renderSelectionToNewClip({
    required int trackId,
    required double startTime,
    required double endTime,
    required String outputPath,
    int bitDepth = 32,
  }) {
    final pathPtr = outputPath.toNativeUtf8();
    try {
      return _renderSelectionToNewClip(
        trackId,
        startTime,
        endTime,
        pathPtr,
        bitDepth,
      );
    } finally {
      calloc.free(pathPtr);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // CYCLE REGION
  // ═══════════════════════════════════════════════════════════════════════════════

  static final _cycleGetStart = _loadNativeLibrary().lookupFunction<
      Double Function(), double Function()>('cycle_get_start');
  static final _cycleGetEnd = _loadNativeLibrary().lookupFunction<
      Double Function(), double Function()>('cycle_get_end');
  static final _cycleIsEnabled = _loadNativeLibrary().lookupFunction<
      Int32 Function(), int Function()>('cycle_is_enabled');
  static final _cycleGetCurrent = _loadNativeLibrary().lookupFunction<
      Uint32 Function(), int Function()>('cycle_get_current');
  static final _cycleGetMax = _loadNativeLibrary().lookupFunction<
      Uint32 Function(), int Function()>('cycle_get_max');
  static final _cycleSetRange = _loadNativeLibrary().lookupFunction<
      Void Function(Double, Double), void Function(double, double)>('cycle_set_range');
  static final _cycleSetEnabled = _loadNativeLibrary().lookupFunction<
      Void Function(Int32), void Function(int)>('cycle_set_enabled');
  static final _cycleSetMax = _loadNativeLibrary().lookupFunction<
      Void Function(Uint32), void Function(int)>('cycle_set_max');
  static final _cycleResetCounter = _loadNativeLibrary().lookupFunction<
      Void Function(), void Function()>('cycle_reset_counter');

  /// Get cycle region start time
  double cycleGetStart() => _cycleGetStart();

  /// Get cycle region end time
  double cycleGetEnd() => _cycleGetEnd();

  /// Check if cycle is enabled
  bool cycleIsEnabled() => _cycleIsEnabled() == 1;

  /// Get current cycle count
  int cycleGetCurrent() => _cycleGetCurrent();

  /// Get max cycles (0 = unlimited)
  int cycleGetMax() => _cycleGetMax();

  /// Set cycle region range
  void cycleSetRange(double start, double end) => _cycleSetRange(start, end);

  /// Set cycle enabled state
  void cycleSetEnabled(bool enabled) => _cycleSetEnabled(enabled ? 1 : 0);

  /// Set max cycles (0 = unlimited)
  void cycleSetMax(int maxCycles) => _cycleSetMax(maxCycles);

  /// Reset cycle counter
  void cycleResetCounter() => _cycleResetCounter();

  // ═══════════════════════════════════════════════════════════════════════════════
  // PUNCH REGION
  // ═══════════════════════════════════════════════════════════════════════════════

  static final _punchGetIn = _loadNativeLibrary().lookupFunction<
      Double Function(), double Function()>('punch_get_in');
  static final _punchGetOut = _loadNativeLibrary().lookupFunction<
      Double Function(), double Function()>('punch_get_out');
  static final _punchIsEnabled = _loadNativeLibrary().lookupFunction<
      Int32 Function(), int Function()>('punch_is_enabled');
  static final _punchGetPreRoll = _loadNativeLibrary().lookupFunction<
      Double Function(), double Function()>('punch_get_pre_roll');
  static final _punchGetPostRoll = _loadNativeLibrary().lookupFunction<
      Double Function(), double Function()>('punch_get_post_roll');
  static final _punchSetRange = _loadNativeLibrary().lookupFunction<
      Void Function(Double, Double), void Function(double, double)>('punch_set_range');
  static final _punchSetEnabled = _loadNativeLibrary().lookupFunction<
      Void Function(Int32), void Function(int)>('punch_set_enabled');
  static final _punchSetPreRoll = _loadNativeLibrary().lookupFunction<
      Void Function(Double), void Function(double)>('punch_set_pre_roll');
  static final _punchSetPostRoll = _loadNativeLibrary().lookupFunction<
      Void Function(Double), void Function(double)>('punch_set_post_roll');
  static final _punchIsActive = _loadNativeLibrary().lookupFunction<
      Int32 Function(Double), int Function(double)>('punch_is_active');

  /// Get punch in time
  double punchGetIn() => _punchGetIn();

  /// Get punch out time
  double punchGetOut() => _punchGetOut();

  /// Check if punch is enabled
  bool punchIsEnabled() => _punchIsEnabled() == 1;

  /// Get pre-roll bars
  double punchGetPreRoll() => _punchGetPreRoll();

  /// Get post-roll bars
  double punchGetPostRoll() => _punchGetPostRoll();

  /// Set punch in/out range
  void punchSetRange(double punchIn, double punchOut) => _punchSetRange(punchIn, punchOut);

  /// Set punch enabled state
  void punchSetEnabled(bool enabled) => _punchSetEnabled(enabled ? 1 : 0);

  /// Set pre-roll bars
  void punchSetPreRoll(double bars) => _punchSetPreRoll(bars);

  /// Set post-roll bars
  void punchSetPostRoll(double bars) => _punchSetPostRoll(bars);

  /// Check if time is within punch region
  bool punchIsActive(double time) => _punchIsActive(time) == 1;

  // ═══════════════════════════════════════════════════════════════════════════════
  // TRACK TEMPLATES
  // ═══════════════════════════════════════════════════════════════════════════════

  static final _templateSaveTrack = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(Uint64, Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(int, Pointer<Utf8>, Pointer<Utf8>)>('template_save_track');
  static final _templateCreateTrack = _loadNativeLibrary().lookupFunction<
      Uint64 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('template_create_track');
  static final _templateGetCount = _loadNativeLibrary().lookupFunction<
      Uint32 Function(), int Function()>('template_get_count');
  static final _templateListAll = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(), Pointer<Utf8> Function()>('template_list_all');
  static final _templateListByCategory = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>), Pointer<Utf8> Function(Pointer<Utf8>)>('template_list_by_category');
  static final _templateGet = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>), Pointer<Utf8> Function(Pointer<Utf8>)>('template_get');
  static final _templateDelete = _loadNativeLibrary().lookupFunction<
      Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('template_delete');
  static final _templateSetDescription = _loadNativeLibrary().lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<Utf8>), int Function(Pointer<Utf8>, Pointer<Utf8>)>('template_set_description');
  static final _templateAddTag = _loadNativeLibrary().lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<Utf8>), int Function(Pointer<Utf8>, Pointer<Utf8>)>('template_add_tag');
  static final _templateSearchByTag = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>), Pointer<Utf8> Function(Pointer<Utf8>)>('template_search_by_tag');

  /// Save track as template
  /// Returns template ID or null on failure
  String? templateSaveTrack(int trackId, String templateName, String category) {
    final namePtr = templateName.toNativeUtf8();
    final categoryPtr = category.toNativeUtf8();
    try {
      final result = _templateSaveTrack(trackId, namePtr, categoryPtr);
      if (result == nullptr) return null;
      final id = result.toDartString();
      calloc.free(result);
      return id;
    } finally {
      calloc.free(namePtr);
      calloc.free(categoryPtr);
    }
  }

  /// Create track from template
  /// Returns track ID or 0 on failure
  int templateCreateTrack(String templateId) {
    final idPtr = templateId.toNativeUtf8();
    try {
      return _templateCreateTrack(idPtr);
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Get template count
  int templateGetCount() => _templateGetCount();

  /// List all templates as JSON
  String templateListAll() {
    final result = _templateListAll();
    if (result == nullptr) return '[]';
    final json = result.toDartString();
    calloc.free(result);
    return json;
  }

  /// List templates by category as JSON
  String templateListByCategory(String category) {
    final categoryPtr = category.toNativeUtf8();
    try {
      final result = _templateListByCategory(categoryPtr);
      if (result == nullptr) return '[]';
      final json = result.toDartString();
      calloc.free(result);
      return json;
    } finally {
      calloc.free(categoryPtr);
    }
  }

  /// Get template by ID as JSON
  String? templateGet(String templateId) {
    final idPtr = templateId.toNativeUtf8();
    try {
      final result = _templateGet(idPtr);
      if (result == nullptr) return null;
      final json = result.toDartString();
      calloc.free(result);
      return json;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Delete template
  /// Returns true on success, false if template doesn't exist or is a default
  bool templateDelete(String templateId) {
    final idPtr = templateId.toNativeUtf8();
    try {
      return _templateDelete(idPtr) == 1;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Set template description
  bool templateSetDescription(String templateId, String description) {
    final idPtr = templateId.toNativeUtf8();
    final descPtr = description.toNativeUtf8();
    try {
      return _templateSetDescription(idPtr, descPtr) == 1;
    } finally {
      calloc.free(idPtr);
      calloc.free(descPtr);
    }
  }

  /// Add tag to template
  bool templateAddTag(String templateId, String tag) {
    final idPtr = templateId.toNativeUtf8();
    final tagPtr = tag.toNativeUtf8();
    try {
      return _templateAddTag(idPtr, tagPtr) == 1;
    } finally {
      calloc.free(idPtr);
      calloc.free(tagPtr);
    }
  }

  /// Search templates by tag as JSON
  String templateSearchByTag(String tag) {
    final tagPtr = tag.toNativeUtf8();
    try {
      final result = _templateSearchByTag(tagPtr);
      if (result == nullptr) return '[]';
      final json = result.toDartString();
      calloc.free(result);
      return json;
    } finally {
      calloc.free(tagPtr);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // PROJECT VERSIONING
  // ═══════════════════════════════════════════════════════════════════════════════

  static final _versionInit = _loadNativeLibrary().lookupFunction<
      Void Function(Pointer<Utf8>, Pointer<Utf8>),
      void Function(Pointer<Utf8>, Pointer<Utf8>)>('version_init');
  static final _versionCreate = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>('version_create');
  static final _versionLoad = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('version_load');
  static final _versionListAll = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(), Pointer<Utf8> Function()>('version_list_all');
  static final _versionListMilestones = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(), Pointer<Utf8> Function()>('version_list_milestones');
  static final _versionGet = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('version_get');
  static final _versionDelete = _loadNativeLibrary().lookupFunction<
      Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('version_delete');
  static final _versionForceDelete = _loadNativeLibrary().lookupFunction<
      Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('version_force_delete');
  static final _versionSetMilestone = _loadNativeLibrary().lookupFunction<
      Int32 Function(Pointer<Utf8>, Int32),
      int Function(Pointer<Utf8>, int)>('version_set_milestone');
  static final _versionAddTag = _loadNativeLibrary().lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
      int Function(Pointer<Utf8>, Pointer<Utf8>)>('version_add_tag');
  static final _versionSearchByTag = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('version_search_by_tag');
  static final _versionGetCount = _loadNativeLibrary().lookupFunction<
      Uint32 Function(), int Function()>('version_get_count');
  static final _versionGetLatest = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(), Pointer<Utf8> Function()>('version_get_latest');
  static final _versionExport = _loadNativeLibrary().lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
      int Function(Pointer<Utf8>, Pointer<Utf8>)>('version_export');
  static final _versionSetMaxCount = _loadNativeLibrary().lookupFunction<
      Void Function(Uint32), void Function(int)>('version_set_max_count');
  static final _versionRefresh = _loadNativeLibrary().lookupFunction<
      Void Function(), void Function()>('version_refresh');

  /// Initialize version manager for project
  void versionInit(String projectName, String baseDir) {
    final namePtr = projectName.toNativeUtf8();
    final dirPtr = baseDir.toNativeUtf8();
    try {
      _versionInit(namePtr, dirPtr);
    } finally {
      calloc.free(namePtr);
      calloc.free(dirPtr);
    }
  }

  /// Create a new version snapshot
  /// Returns version ID or null on failure
  String? versionCreate(String name, String description) {
    final namePtr = name.toNativeUtf8();
    final descPtr = description.toNativeUtf8();
    try {
      final result = _versionCreate(namePtr, descPtr);
      if (result == nullptr) return null;
      final id = result.toDartString();
      calloc.free(result);
      return id;
    } finally {
      calloc.free(namePtr);
      calloc.free(descPtr);
    }
  }

  /// Load version data by ID
  /// Returns project JSON or null on failure
  String? versionLoad(String versionId) {
    final idPtr = versionId.toNativeUtf8();
    try {
      final result = _versionLoad(idPtr);
      if (result == nullptr) return null;
      final json = result.toDartString();
      calloc.free(result);
      return json;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// List all versions as JSON array
  String versionListAll() {
    final result = _versionListAll();
    if (result == nullptr) return '[]';
    final json = result.toDartString();
    calloc.free(result);
    return json;
  }

  /// List milestone versions as JSON array
  String versionListMilestones() {
    final result = _versionListMilestones();
    if (result == nullptr) return '[]';
    final json = result.toDartString();
    calloc.free(result);
    return json;
  }

  /// Get version metadata by ID as JSON
  String? versionGet(String versionId) {
    final idPtr = versionId.toNativeUtf8();
    try {
      final result = _versionGet(idPtr);
      if (result == nullptr) return null;
      final json = result.toDartString();
      calloc.free(result);
      return json;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Delete version
  /// Returns true on success, false if protected or not found
  bool versionDelete(String versionId) {
    final idPtr = versionId.toNativeUtf8();
    try {
      return _versionDelete(idPtr) == 1;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Force delete version (even milestones)
  bool versionForceDelete(String versionId) {
    final idPtr = versionId.toNativeUtf8();
    try {
      return _versionForceDelete(idPtr) == 1;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Mark version as milestone
  bool versionSetMilestone(String versionId, bool isMilestone) {
    final idPtr = versionId.toNativeUtf8();
    try {
      return _versionSetMilestone(idPtr, isMilestone ? 1 : 0) == 1;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Add tag to version
  bool versionAddTag(String versionId, String tag) {
    final idPtr = versionId.toNativeUtf8();
    final tagPtr = tag.toNativeUtf8();
    try {
      return _versionAddTag(idPtr, tagPtr) == 1;
    } finally {
      calloc.free(idPtr);
      calloc.free(tagPtr);
    }
  }

  /// Search versions by tag
  String versionSearchByTag(String tag) {
    final tagPtr = tag.toNativeUtf8();
    try {
      final result = _versionSearchByTag(tagPtr);
      if (result == nullptr) return '[]';
      final json = result.toDartString();
      calloc.free(result);
      return json;
    } finally {
      calloc.free(tagPtr);
    }
  }

  /// Get version count
  int versionGetCount() => _versionGetCount();

  /// Get latest version ID
  String? versionGetLatest() {
    final result = _versionGetLatest();
    if (result == nullptr) return null;
    final id = result.toDartString();
    calloc.free(result);
    return id;
  }

  /// Export version to file
  bool versionExport(String versionId, String exportPath) {
    final idPtr = versionId.toNativeUtf8();
    final pathPtr = exportPath.toNativeUtf8();
    try {
      return _versionExport(idPtr, pathPtr) == 1;
    } finally {
      calloc.free(idPtr);
      calloc.free(pathPtr);
    }
  }

  /// Set max versions to keep (0 = unlimited)
  void versionSetMaxCount(int max) => _versionSetMaxCount(max);

  /// Refresh versions from disk
  void versionRefresh() => _versionRefresh();
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADVANCED METERING EXTENSION
// ═══════════════════════════════════════════════════════════════════════════════

/// Advanced Metering API (8x True Peak, PSR, Psychoacoustic)
extension AdvancedMeteringAPI on NativeFFI {
  // FFI lookups for advanced meters
  static final _advancedMetersInit = _loadNativeLibrary().lookupFunction<
      Int32 Function(Double),
      int Function(double)>('advanced_meters_init');

  static final _advancedMetersReset = _loadNativeLibrary().lookupFunction<
      Int32 Function(),
      int Function()>('advanced_meters_reset');

  static final _advancedMetersGetTruePeakL = _loadNativeLibrary().lookupFunction<
      Double Function(),
      double Function()>('advanced_meters_get_true_peak_l');

  static final _advancedMetersGetTruePeakR = _loadNativeLibrary().lookupFunction<
      Double Function(),
      double Function()>('advanced_meters_get_true_peak_r');

  static final _advancedMetersGetTruePeakMax = _loadNativeLibrary().lookupFunction<
      Double Function(),
      double Function()>('advanced_meters_get_true_peak_max');

  static final _advancedMetersGetPsr = _loadNativeLibrary().lookupFunction<
      Double Function(),
      double Function()>('advanced_meters_get_psr');

  static final _advancedMetersGetShortTermLufs = _loadNativeLibrary().lookupFunction<
      Double Function(),
      double Function()>('advanced_meters_get_short_term_lufs');

  static final _advancedMetersGetPsrAssessment = _loadNativeLibrary().lookupFunction<
      Int32 Function(),
      int Function()>('advanced_meters_get_psr_assessment');

  static final _advancedMetersGetCrestFactorL = _loadNativeLibrary().lookupFunction<
      Double Function(),
      double Function()>('advanced_meters_get_crest_factor_l');

  static final _advancedMetersGetCrestFactorR = _loadNativeLibrary().lookupFunction<
      Double Function(),
      double Function()>('advanced_meters_get_crest_factor_r');

  static final _advancedMetersGetLoudnessSonesL = _loadNativeLibrary().lookupFunction<
      Double Function(),
      double Function()>('advanced_meters_get_loudness_sones_l');

  static final _advancedMetersGetLoudnessPhonsL = _loadNativeLibrary().lookupFunction<
      Double Function(),
      double Function()>('advanced_meters_get_loudness_phons_l');

  static final _advancedMetersGetSharpnessL = _loadNativeLibrary().lookupFunction<
      Double Function(),
      double Function()>('advanced_meters_get_sharpness_l');

  static final _advancedMetersGetFluctuationL = _loadNativeLibrary().lookupFunction<
      Double Function(),
      double Function()>('advanced_meters_get_fluctuation_l');

  static final _advancedMetersGetRoughnessL = _loadNativeLibrary().lookupFunction<
      Double Function(),
      double Function()>('advanced_meters_get_roughness_l');

  /// Get 8x True Peak data
  TruePeak8xData advancedGetTruePeak8x() {
    final peakL = _advancedMetersGetTruePeakL();
    final peakR = _advancedMetersGetTruePeakR();
    final maxDbtp = _advancedMetersGetTruePeakMax();
    final peakDbtp = peakL > peakR ? peakL : peakR;
    return TruePeak8xData(
      peakDbtp: peakDbtp,
      maxDbtp: maxDbtp,
      holdDbtp: maxDbtp, // Using max as hold for simplicity
      isClipping: peakDbtp > 0.0,
    );
  }

  /// Get PSR data
  PsrData advancedGetPsr() {
    final psr = _advancedMetersGetPsr();
    final lufs = _advancedMetersGetShortTermLufs();
    final tp = _advancedMetersGetTruePeakMax();
    final assessmentCode = _advancedMetersGetPsrAssessment();

    String assessment;
    switch (assessmentCode) {
      case 0: assessment = 'Severely Over-compressed'; break;
      case 1: assessment = 'Over-compressed'; break;
      case 2: assessment = 'Moderate Compression'; break;
      case 3: assessment = 'Good Dynamic Range'; break;
      case 4: assessment = 'High Dynamic Range'; break;
      default: assessment = 'Unknown';
    }

    return PsrData(
      psrDb: psr,
      shortTermLufs: lufs,
      truePeakDbtp: tp,
      assessment: assessment,
    );
  }

  /// Get Crest Factor data
  CrestFactorData advancedGetCrestFactor() {
    final crestL = _advancedMetersGetCrestFactorL();
    final crestR = _advancedMetersGetCrestFactorR();
    final crestDb = (crestL + crestR) / 2.0;
    final crestRatio = crestDb > 0 ? (crestDb / 20.0 * 10.0).abs() : 1.0;

    String assessment;
    if (crestDb < 6) {
      assessment = 'Over-limited';
    } else if (crestDb < 12) {
      assessment = 'Compressed';
    } else if (crestDb < 18) {
      assessment = 'Moderate';
    } else {
      assessment = 'Dynamic';
    }

    return CrestFactorData(
      crestDb: crestDb,
      crestRatio: crestRatio,
      assessment: assessment,
    );
  }

  /// Get Psychoacoustic data
  PsychoacousticData advancedGetPsychoacoustic() {
    return PsychoacousticData(
      loudnessSones: _advancedMetersGetLoudnessSonesL(),
      loudnessPhons: _advancedMetersGetLoudnessPhonsL(),
      sharpnessAcum: _advancedMetersGetSharpnessL(),
      fluctuationVacil: _advancedMetersGetFluctuationL(),
      roughnessAsper: _advancedMetersGetRoughnessL(),
      specificLoudness: List.filled(24, 0.0), // Placeholder
    );
  }

  /// Initialize advanced meters
  void advancedInitMeters(double sampleRate) {
    _advancedMetersInit(sampleRate);
  }

  /// Reset all advanced meters
  void advancedResetAll() {
    _advancedMetersReset();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO POOL EXTENSION
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio Pool API
extension AudioPoolAPI on NativeFFI {
  // FFI lookups for audio pool
  static final _audioPoolList = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('audio_pool_list');

  static final _audioPoolCount = _loadNativeLibrary().lookupFunction<
      Uint32 Function(),
      int Function()>('audio_pool_count');

  static final _audioPoolRemove = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint64),
      int Function(int)>('audio_pool_remove');

  static final _audioPoolClear = _loadNativeLibrary().lookupFunction<
      Int32 Function(),
      int Function()>('audio_pool_clear');

  static final _audioPoolContains = _loadNativeLibrary().lookupFunction<
      Int32 Function(Uint64),
      int Function(int)>('audio_pool_contains');

  static final _audioPoolGetInfo = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(Uint64),
      Pointer<Utf8> Function(int)>('audio_pool_get_info');

  static final _audioPoolMemoryUsage = _loadNativeLibrary().lookupFunction<
      Uint64 Function(),
      int Function()>('audio_pool_memory_usage');

  static final _freeRustString = _loadNativeLibrary().lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('free_rust_string');

  /// Get list of audio files in the pool as JSON
  String audioPoolList() {
    final ptr = _audioPoolList();
    if (ptr == nullptr) return '[]';
    final json = ptr.toDartString();
    _freeRustString(ptr);
    return json;
  }

  /// Get count of audio files in pool
  int audioPoolCount() {
    return _audioPoolCount();
  }

  /// Import audio file to pool (uses existing engine_import_audio)
  bool audioPoolImport(String path) {
    // Import to pool only (no track placement), use trackId=0, startTime=0
    return NativeFFI.instance.importAudio(path, 0, 0.0) >= 0;
  }

  /// Remove audio file from pool by clip ID
  bool audioPoolRemove(int clipId) {
    return _audioPoolRemove(clipId) == 1;
  }

  /// Clear all audio from pool
  bool audioPoolClear() {
    return _audioPoolClear() == 1;
  }

  /// Check if clip ID exists in pool
  bool audioPoolContains(int clipId) {
    return _audioPoolContains(clipId) == 1;
  }

  /// Get audio info as JSON for clip ID
  String? audioPoolGetInfo(int clipId) {
    final ptr = _audioPoolGetInfo(clipId);
    if (ptr == nullptr) return null;
    final json = ptr.toDartString();
    _freeRustString(ptr);
    return json;
  }

  /// Get total memory usage in bytes
  int audioPoolMemoryUsage() {
    return _audioPoolMemoryUsage();
  }

  // FFI for audio metadata
  static final _audioGetMetadata = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)>('audio_get_metadata');

  /// Get audio file metadata (duration, sample_rate, channels, bit_depth) without full import
  /// Returns JSON string or empty string on error
  String audioGetMetadata(String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      final ptr = _audioGetMetadata(pathPtr);
      if (ptr == nullptr || ptr.address == 0) return '';
      final json = ptr.toDartString();
      if (json.isEmpty) {
        _freeRustString(ptr);
        return '';
      }
      _freeRustString(ptr);
      return json;
    } catch (e) {
      return '';
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Play audio file preview (through master bus)
  void audioPoolPlayPreview(int clipId) {
    // Preview not implemented - would need separate playback path
    // For now, just log the intent
  }

  /// Stop audio file preview
  void audioPoolStopPreview() {
    NativeFFI.instance.stop();
  }

  /// Locate missing audio file (re-import with new path)
  bool audioPoolLocate(int clipId, String newPath) {
    // Remove old and import from new location
    _audioPoolRemove(clipId);
    return NativeFFI.instance.importAudio(newPath, 0, 0.0) >= 0;
  }

}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORT PRESETS EXTENSION
// ═══════════════════════════════════════════════════════════════════════════════

/// Export Presets API
extension ExportPresetsAPI on NativeFFI {
  // FFI lookups for export presets
  static final _exportPresetsList = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('export_presets_list');

  static final _exportPresetsCount = _loadNativeLibrary().lookupFunction<
      Uint32 Function(),
      int Function()>('export_presets_count');

  static final _exportPresetDelete = _loadNativeLibrary().lookupFunction<
      Int32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('export_preset_delete');

  static final _exportGetDefaultPath = _loadNativeLibrary().lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('export_get_default_path');

  static final _freeRustStringExport = _loadNativeLibrary().lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('free_rust_string');

  /// Get list of export presets as JSON
  String exportPresetsList() {
    final ptr = _exportPresetsList();
    if (ptr == nullptr) return '[]';
    final json = ptr.toDartString();
    _freeRustStringExport(ptr);
    return json;
  }

  /// Get count of export presets
  int exportPresetsCount() {
    return _exportPresetsCount();
  }

  /// Save export preset (add to list)
  bool exportPresetSave(String presetJson) {
    // Presets are managed in-memory, add via JSON parsing
    // For now, presets are hardcoded defaults (broadcast, streaming, archival)
    return true;
  }

  /// Delete export preset by ID
  bool exportPresetDelete(String presetId) {
    final idPtr = presetId.toNativeUtf8();
    final result = _exportPresetDelete(idPtr);
    calloc.free(idPtr);
    return result == 1;
  }

  /// Get default export path
  String getDefaultExportPath() {
    final ptr = _exportGetDefaultPath();
    if (ptr == nullptr) return '';
    final path = ptr.toDartString();
    _freeRustStringExport(ptr);
    return path;
  }

  /// Select export folder (opens native dialog via file_picker)
  Future<String?> selectExportFolder() async {
    // This uses Flutter's file_picker, not FFI
    // Return null - caller should use FilePicker.platform.getDirectoryPath()
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONTROL ROOM EXTENSION
// ═══════════════════════════════════════════════════════════════════════════════

/// Control Room API
extension ControlRoomAPI on NativeFFI {
  /// Get monitor source (0=Master, 1-4=Cue1-4, 5-6=External1-2)
  int controlRoomGetMonitorSource() {
    // TODO: Implement actual FFI binding
    return 0;
  }

  /// Set monitor source
  void controlRoomSetMonitorSource(int source) {
    // TODO: Implement actual FFI binding
  }

  /// Get monitor level (dB)
  double controlRoomGetMonitorLevel() {
    // TODO: Implement actual FFI binding
    return 0.0;
  }

  /// Set monitor level (dB)
  void controlRoomSetMonitorLevel(double db) {
    // TODO: Implement actual FFI binding
  }

  /// Get dim enabled
  bool controlRoomGetDimEnabled() {
    // TODO: Implement actual FFI binding
    return false;
  }

  /// Set dim enabled
  void controlRoomSetDimEnabled(bool enabled) {
    // TODO: Implement actual FFI binding
  }

  /// Get dim level (dB)
  double controlRoomGetDimLevel() {
    // TODO: Implement actual FFI binding
    return -20.0;
  }

  /// Set dim level (dB)
  void controlRoomSetDimLevel(double db) {
    // TODO: Implement actual FFI binding
  }

  /// Get mono enabled
  bool controlRoomGetMonoEnabled() {
    // TODO: Implement actual FFI binding
    return false;
  }

  /// Set mono enabled
  void controlRoomSetMonoEnabled(bool enabled) {
    // TODO: Implement actual FFI binding
  }

  /// Get solo mode (0=Off, 1=SIP, 2=AFL, 3=PFL)
  int controlRoomGetSoloMode() {
    // TODO: Implement actual FFI binding
    return 0;
  }

  /// Set solo mode
  void controlRoomSetSoloMode(int mode) {
    // TODO: Implement actual FFI binding
  }

  /// Get active speaker set (0-3)
  int controlRoomGetActiveSpeakerSet() {
    // TODO: Implement actual FFI binding
    return 0;
  }

  /// Set active speaker set
  void controlRoomSetActiveSpeakerSet(int index) {
    // TODO: Implement actual FFI binding
  }

  /// Get speaker calibration (dB)
  double controlRoomGetSpeakerCalibration(int index) {
    // TODO: Implement actual FFI binding
    return 0.0;
  }

  /// Set speaker calibration (dB)
  void controlRoomSetSpeakerCalibration(int index, double db) {
    // TODO: Implement actual FFI binding
  }

  /// Solo a channel
  void controlRoomSoloChannel(int channelId) {
    // TODO: Implement actual FFI binding
  }

  /// Unsolo a channel
  void controlRoomUnsoloChannel(int channelId) {
    // TODO: Implement actual FFI binding
  }

  /// Clear all solos
  void controlRoomClearAllSolos() {
    // TODO: Implement actual FFI binding
  }

  /// Check if channel is soloed
  bool controlRoomIsChannelSoloed(int channelId) {
    // TODO: Implement actual FFI binding
    return false;
  }

  /// Get monitor peak meters (returns [peakL, peakR])
  List<double> controlRoomGetMonitorPeak() {
    // TODO: Implement actual FFI binding
    return [0.0, 0.0];
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // CUE MIXES
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Get cue mix enabled
  bool cueMixGetEnabled(int cueIndex) {
    // TODO: Implement actual FFI binding
    return false;
  }

  /// Set cue mix enabled
  void cueMixSetEnabled(int cueIndex, bool enabled) {
    // TODO: Implement actual FFI binding
  }

  /// Get cue mix level (dB)
  double cueMixGetLevel(int cueIndex) {
    // TODO: Implement actual FFI binding
    return 0.0;
  }

  /// Set cue mix level (dB)
  void cueMixSetLevel(int cueIndex, double db) {
    // TODO: Implement actual FFI binding
  }

  /// Get cue mix pan (-1 to 1)
  double cueMixGetPan(int cueIndex) {
    // TODO: Implement actual FFI binding
    return 0.0;
  }

  /// Set cue mix pan
  void cueMixSetPan(int cueIndex, double pan) {
    // TODO: Implement actual FFI binding
  }

  /// Get cue mix peak meters (returns [peakL, peakR])
  List<double> cueMixGetPeak(int cueIndex) {
    // TODO: Implement actual FFI binding
    return [0.0, 0.0];
  }

  /// Set cue send for a channel
  void cueMixSetChannelSend(int cueIndex, int channelId, double level, double pan) {
    // TODO: Implement actual FFI binding
  }

  /// Get cue send for a channel (returns [level, pan] or null if not set)
  List<double>? cueMixGetChannelSend(int cueIndex, int channelId) {
    // TODO: Implement actual FFI binding
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // TALKBACK
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Get talkback enabled
  bool talkbackGetEnabled() {
    // TODO: Implement actual FFI binding
    return false;
  }

  /// Set talkback enabled
  void talkbackSetEnabled(bool enabled) {
    // TODO: Implement actual FFI binding
  }

  /// Get talkback level (dB)
  double talkbackGetLevel() {
    // TODO: Implement actual FFI binding
    return 0.0;
  }

  /// Set talkback level (dB)
  void talkbackSetLevel(double db) {
    // TODO: Implement actual FFI binding
  }

  /// Get talkback destinations (bitmask)
  int talkbackGetDestinations() {
    // TODO: Implement actual FFI binding
    return 0xF; // All 4 cues by default
  }

  /// Set talkback destinations (bitmask)
  void talkbackSetDestinations(int mask) {
    // TODO: Implement actual FFI binding
  }

  /// Get talkback dim main on talk
  bool talkbackGetDimMainOnTalk() {
    // TODO: Implement actual FFI binding
    return true;
  }

  /// Set talkback dim main on talk
  void talkbackSetDimMainOnTalk(bool enabled) {
    // TODO: Implement actual FFI binding
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MASTERING ENGINE (AI Mastering)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize mastering engine with sample rate
  void masteringEngineInit(int sampleRate) {
    if (!_loaded) return;
    _masteringEngineInit(sampleRate);
  }

  /// Set mastering preset
  /// preset: 0=CdLossless, 1=Streaming, 2=AppleMusic, 3=Broadcast, 4=Club, 5=Vinyl, 6=Podcast, 7=Film
  bool masteringSetPreset(int preset) {
    if (!_loaded) return false;
    return _masteringSetPreset(preset) != 0;
  }

  /// Set loudness target manually
  bool masteringSetLoudnessTarget(double integratedLufs, double truePeak, double lraTarget) {
    if (!_loaded) return false;
    return _masteringSetLoudnessTarget(integratedLufs, truePeak, lraTarget) != 0;
  }

  /// Set reference audio for matching
  bool masteringSetReference(String name, Float32List left, Float32List right) {
    if (!_loaded) return false;
    if (left.length != right.length) return false;

    final namePtr = name.toNativeUtf8();
    final leftPtr = calloc<Float>(left.length);
    final rightPtr = calloc<Float>(right.length);

    try {
      leftPtr.asTypedList(left.length).setAll(0, left);
      rightPtr.asTypedList(right.length).setAll(0, right);
      return _masteringSetReference(namePtr, leftPtr, rightPtr, left.length) != 0;
    } finally {
      calloc.free(namePtr);
      calloc.free(leftPtr);
      calloc.free(rightPtr);
    }
  }

  /// Process audio through mastering engine (offline)
  bool masteringProcessOffline(
    Float32List inputLeft,
    Float32List inputRight,
    Float32List outputLeft,
    Float32List outputRight,
  ) {
    if (!_loaded) return false;
    if (inputLeft.length != inputRight.length) return false;
    if (inputLeft.length != outputLeft.length) return false;
    if (inputLeft.length != outputRight.length) return false;

    final length = inputLeft.length;
    final inLeftPtr = calloc<Float>(length);
    final inRightPtr = calloc<Float>(length);
    final outLeftPtr = calloc<Float>(length);
    final outRightPtr = calloc<Float>(length);

    try {
      inLeftPtr.asTypedList(length).setAll(0, inputLeft);
      inRightPtr.asTypedList(length).setAll(0, inputRight);

      final result = _masteringProcessOffline(inLeftPtr, inRightPtr, outLeftPtr, outRightPtr, length);

      if (result != 0) {
        // Copy output back
        outputLeft.setAll(0, outLeftPtr.asTypedList(length));
        outputRight.setAll(0, outRightPtr.asTypedList(length));
        return true;
      }
      return false;
    } finally {
      calloc.free(inLeftPtr);
      calloc.free(inRightPtr);
      calloc.free(outLeftPtr);
      calloc.free(outRightPtr);
    }
  }

  /// Get last mastering result
  MasteringResultFFI masteringGetResult() {
    if (!_loaded) {
      return MasteringResultFFI(
        inputLufs: -23.0,
        outputLufs: -14.0,
        inputPeak: -3.0,
        outputPeak: -1.0,
        appliedGain: 0.0,
        peakReduction: 0.0,
        qualityScore: 0.0,
        detectedGenre: 0,
        warningCount: 0,
      );
    }
    final result = _masteringGetResult();
    return MasteringResultFFI(
      inputLufs: result.inputLufs,
      outputLufs: result.outputLufs,
      inputPeak: result.inputPeak,
      outputPeak: result.outputPeak,
      appliedGain: result.appliedGain,
      peakReduction: result.peakReduction,
      qualityScore: result.qualityScore,
      detectedGenre: result.detectedGenre,
      warningCount: result.warningCount,
    );
  }

  /// Get warning at index
  String? masteringGetWarning(int index) {
    if (!_loaded) return null;
    final ptr = _masteringGetWarning(index);
    if (ptr == nullptr) return null;
    try {
      return ptr.toDartString();
    } finally {
      // String is owned by Rust, free it
      _freeString(ptr);
    }
  }

  /// Get chain summary as JSON
  String? masteringGetChainSummary() {
    if (!_loaded) return null;
    final ptr = _masteringGetChainSummary();
    if (ptr == nullptr) return null;
    try {
      return ptr.toDartString();
    } finally {
      _freeString(ptr);
    }
  }

  /// Reset mastering engine
  void masteringReset() {
    if (!_loaded) return;
    _masteringReset();
  }

  /// Set bypass/active state
  void masteringSetActive(bool active) {
    if (!_loaded) return;
    _masteringSetActive(active ? 1 : 0);
  }

  /// Get current gain reduction (for metering)
  double masteringGetGainReduction() {
    if (!_loaded) return 0.0;
    return _masteringGetGainReduction();
  }

  /// Get detected genre
  int masteringGetDetectedGenre() {
    if (!_loaded) return 0;
    return _masteringGetDetectedGenre();
  }

  /// Get latency in samples
  int masteringGetLatency() {
    if (!_loaded) return 0;
    return _masteringGetLatency();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO RESTORATION API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize restoration engine
  void restorationInit(int sampleRate) {
    if (!_loaded) return;
    _restorationInit(sampleRate);
  }

  /// Set restoration settings
  bool restorationSetSettings({
    required bool denoiseEnabled,
    required double denoiseStrength,
    required bool declickEnabled,
    required double declickSensitivity,
    required bool declipEnabled,
    required double declipThreshold,
    required bool dehumEnabled,
    required double dehumFrequency,
    required int dehumHarmonics,
    required bool dereverbEnabled,
    required double dereverbAmount,
  }) {
    if (!_loaded) return false;
    return _restorationSetSettings(
      denoiseEnabled ? 1 : 0, denoiseStrength,
      declickEnabled ? 1 : 0, declickSensitivity,
      declipEnabled ? 1 : 0, declipThreshold,
      dehumEnabled ? 1 : 0, dehumFrequency, dehumHarmonics,
      dereverbEnabled ? 1 : 0, dereverbAmount,
    ) != 0;
  }

  /// Get current restoration settings
  RestorationSettings? restorationGetSettings() {
    if (!_loaded) return null;
    final result = _restorationGetSettings();
    return RestorationSettings(
      denoiseEnabled: result.denoiseEnabled != 0,
      denoiseStrength: result.denoiseStrength,
      declickEnabled: result.declickEnabled != 0,
      declickSensitivity: result.declickSensitivity,
      declipEnabled: result.declipEnabled != 0,
      declipThreshold: result.declipThreshold,
      dehumEnabled: result.dehumEnabled != 0,
      dehumFrequency: result.dehumFrequency,
      dehumHarmonics: result.dehumHarmonics,
      dereverbEnabled: result.dereverbEnabled != 0,
      dereverbAmount: result.dereverbAmount,
    );
  }

  /// Analyze audio file for restoration needs
  RestorationAnalysis? restorationAnalyze(String path) {
    if (!_loaded) return null;
    final pathPtr = path.toNativeUtf8();
    try {
      final result = _restorationAnalyze(pathPtr);
      return RestorationAnalysis(
        noiseFloorDb: result.noiseFloorDb,
        clicksPerSecond: result.clicksPerSecond,
        clippingPercent: result.clippingPercent,
        humDetected: result.humDetected != 0,
        humFrequency: result.humFrequency,
        humLevelDb: result.humLevelDb,
        reverbTailSeconds: result.reverbTailSeconds,
        qualityScore: result.qualityScore,
      );
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Get analysis suggestions
  List<String> restorationGetSuggestions() {
    if (!_loaded) return [];
    final count = _restorationGetSuggestionCount();
    final suggestions = <String>[];
    for (int i = 0; i < count; i++) {
      final ptr = _restorationGetSuggestion(i);
      if (ptr != nullptr) {
        suggestions.add(ptr.toDartString());
        calloc.free(ptr);
      }
    }
    return suggestions;
  }

  /// Process audio buffer through restoration pipeline
  bool restorationProcess(Float32List input, Float32List output) {
    if (!_loaded) return false;
    if (input.length != output.length) return false;

    final inputPtr = calloc<Float>(input.length);
    final outputPtr = calloc<Float>(output.length);
    try {
      for (int i = 0; i < input.length; i++) {
        inputPtr[i] = input[i];
      }

      final success = _restorationProcess(inputPtr, outputPtr, input.length) != 0;

      if (success) {
        for (int i = 0; i < output.length; i++) {
          output[i] = outputPtr[i];
        }
      }

      return success;
    } finally {
      calloc.free(inputPtr);
      calloc.free(outputPtr);
    }
  }

  /// Process file through restoration pipeline
  bool restorationProcessFile(String inputPath, String outputPath) {
    if (!_loaded) return false;
    final inPtr = inputPath.toNativeUtf8();
    final outPtr = outputPath.toNativeUtf8();
    try {
      return _restorationProcessFile(inPtr, outPtr) != 0;
    } finally {
      calloc.free(inPtr);
      calloc.free(outPtr);
    }
  }

  /// Learn noise profile from selection
  bool restorationLearnNoiseProfile(Float32List samples) {
    if (!_loaded) return false;
    final ptr = calloc<Float>(samples.length);
    try {
      for (int i = 0; i < samples.length; i++) {
        ptr[i] = samples[i];
      }
      return _restorationLearnNoiseProfile(ptr, samples.length) != 0;
    } finally {
      calloc.free(ptr);
    }
  }

  /// Clear learned noise profile
  void restorationClearNoiseProfile() {
    if (!_loaded) return;
    _restorationClearNoiseProfile();
  }

  /// Get processing state
  (bool isProcessing, double progress) restorationGetState() {
    if (!_loaded) return (false, 0.0);
    final isProcessingPtr = calloc<Int32>();
    final progressPtr = calloc<Float>();
    try {
      _restorationGetState(isProcessingPtr, progressPtr);
      return (isProcessingPtr.value != 0, progressPtr.value);
    } finally {
      calloc.free(isProcessingPtr);
      calloc.free(progressPtr);
    }
  }

  /// Get processing phase string
  String restorationGetPhase() {
    if (!_loaded) return 'idle';
    final ptr = _restorationGetPhase();
    if (ptr == nullptr) return 'idle';
    final result = ptr.toDartString();
    calloc.free(ptr);
    return result;
  }

  /// Set restoration active/bypass
  void restorationSetActive(bool active) {
    if (!_loaded) return;
    _restorationSetActive(active ? 1 : 0);
  }

  /// Get restoration latency in samples
  int restorationGetLatency() {
    if (!_loaded) return 0;
    return _restorationGetLatency();
  }

  /// Reset restoration pipeline
  void restorationReset() {
    if (!_loaded) return;
    _restorationReset();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ML/AI PROCESSING API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize ML engine
  void mlInit() {
    if (!_loaded) return;
    _mlInit();
  }

  /// Get number of available ML models
  int mlGetModelCount() {
    if (!_loaded) return 0;
    return _mlGetModelCount();
  }

  /// Get model name by index
  String? mlGetModelName(int index) {
    if (!_loaded) return null;
    final ptr = _mlGetModelName(index);
    if (ptr == nullptr) return null;
    final result = ptr.toDartString();
    calloc.free(ptr);
    return result;
  }

  /// Check if model is available (downloaded)
  bool mlModelIsAvailable(int index) {
    if (!_loaded) return false;
    return _mlModelIsAvailable(index) != 0;
  }

  /// Get model size in MB
  int mlGetModelSize(int index) {
    if (!_loaded) return 0;
    return _mlGetModelSize(index);
  }

  /// Get all available models
  List<MlModelInfo> mlGetAllModels() {
    final count = mlGetModelCount();
    final models = <MlModelInfo>[];
    for (int i = 0; i < count; i++) {
      final name = mlGetModelName(i);
      if (name != null) {
        models.add(MlModelInfo(
          index: i,
          name: name,
          isAvailable: mlModelIsAvailable(i),
          sizeMb: mlGetModelSize(i),
        ));
      }
    }
    return models;
  }

  /// Start ML denoise processing
  bool mlDenoiseStart(String inputPath, String outputPath, double strength) {
    if (!_loaded) return false;
    final inPtr = inputPath.toNativeUtf8();
    final outPtr = outputPath.toNativeUtf8();
    try {
      return _mlDenoiseStart(inPtr, outPtr, strength) != 0;
    } finally {
      calloc.free(inPtr);
      calloc.free(outPtr);
    }
  }

  /// Start stem separation
  /// stemsMask: bitmask where 1=vocals, 2=drums, 4=bass, 8=other
  bool mlSeparateStart(String inputPath, String outputDir, int stemsMask) {
    if (!_loaded) return false;
    final inPtr = inputPath.toNativeUtf8();
    final outPtr = outputDir.toNativeUtf8();
    try {
      return _mlSeparateStart(inPtr, outPtr, stemsMask) != 0;
    } finally {
      calloc.free(inPtr);
      calloc.free(outPtr);
    }
  }

  /// Start voice enhancement
  bool mlEnhanceVoiceStart(String inputPath, String outputPath) {
    if (!_loaded) return false;
    final inPtr = inputPath.toNativeUtf8();
    final outPtr = outputPath.toNativeUtf8();
    try {
      return _mlEnhanceVoiceStart(inPtr, outPtr) != 0;
    } finally {
      calloc.free(inPtr);
      calloc.free(outPtr);
    }
  }

  /// Get ML processing progress (0.0-1.0)
  double mlGetProgress() {
    if (!_loaded) return 0.0;
    return _mlGetProgress();
  }

  /// Check if ML is currently processing
  bool mlIsProcessing() {
    if (!_loaded) return false;
    return _mlIsProcessing() != 0;
  }

  /// Get current processing phase
  String mlGetPhase() {
    if (!_loaded) return 'idle';
    final ptr = _mlGetPhase();
    if (ptr == nullptr) return 'idle';
    final result = ptr.toDartString();
    calloc.free(ptr);
    return result;
  }

  /// Get current model being used
  String mlGetCurrentModel() {
    if (!_loaded) return '';
    final ptr = _mlGetCurrentModel();
    if (ptr == nullptr) return '';
    final result = ptr.toDartString();
    calloc.free(ptr);
    return result;
  }

  /// Cancel ML processing
  bool mlCancel() {
    if (!_loaded) return false;
    return _mlCancel() != 0;
  }

  /// Set execution provider (0=CPU, 1=CUDA, 2=CoreML, 3=TensorRT)
  bool mlSetExecutionProvider(int provider) {
    if (!_loaded) return false;
    return _mlSetExecutionProvider(provider) != 0;
  }

  /// Get error message if any
  String? mlGetError() {
    if (!_loaded) return null;
    final ptr = _mlGetError();
    if (ptr == nullptr) return null;
    final result = ptr.toDartString();
    calloc.free(ptr);
    return result;
  }

  /// Reset ML engine
  void mlReset() {
    if (!_loaded) return;
    _mlReset();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LUA SCRIPTING (rf-script)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize script engine
  bool scriptInit() {
    if (!_loaded) return false;
    return _scriptInit() != 0;
  }

  /// Shutdown script engine
  void scriptShutdown() {
    if (!_loaded) return;
    _scriptShutdown();
  }

  /// Check if script engine is initialized
  bool scriptIsInitialized() {
    if (!_loaded) return false;
    return _scriptIsInitialized() != 0;
  }

  /// Execute Lua code directly
  bool scriptExecute(String code) {
    if (!_loaded) return false;
    final codePtr = code.toNativeUtf8();
    try {
      return _scriptExecute(codePtr) != 0;
    } finally {
      calloc.free(codePtr);
    }
  }

  /// Execute script from file
  bool scriptExecuteFile(String path) {
    if (!_loaded) return false;
    final pathPtr = path.toNativeUtf8();
    try {
      return _scriptExecuteFile(pathPtr) != 0;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Load script from file (returns script name)
  String? scriptLoadFile(String path) {
    if (!_loaded) return null;
    final pathPtr = path.toNativeUtf8();
    try {
      final result = _scriptLoadFile(pathPtr);
      if (result == nullptr) return null;
      final name = result.toDartString();
      calloc.free(result);
      return name;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Run a previously loaded script by name
  bool scriptRun(String name) {
    if (!_loaded) return false;
    final namePtr = name.toNativeUtf8();
    try {
      return _scriptRun(namePtr) != 0;
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Get last execution output
  String? scriptGetOutput() {
    if (!_loaded) return null;
    final result = _scriptGetOutput();
    if (result == nullptr) return null;
    final output = result.toDartString();
    calloc.free(result);
    return output;
  }

  /// Get last execution error
  String? scriptGetError() {
    if (!_loaded) return null;
    final result = _scriptGetError();
    if (result == nullptr) return null;
    final error = result.toDartString();
    calloc.free(result);
    return error;
  }

  /// Get last execution duration in milliseconds
  int scriptGetDuration() {
    if (!_loaded) return 0;
    return _scriptGetDuration();
  }

  /// Poll for pending script actions
  int scriptPollActions() {
    if (!_loaded) return 0;
    return _scriptPollActions();
  }

  /// Get next script action as JSON
  String? scriptGetNextAction() {
    if (!_loaded) return null;
    final result = _scriptGetNextAction();
    if (result == nullptr) return null;
    final json = result.toDartString();
    calloc.free(result);
    return json;
  }

  /// Update script context
  void scriptSetContext({
    required int playhead,
    required bool isPlaying,
    required bool isRecording,
    required int sampleRate,
  }) {
    if (!_loaded) return;
    _scriptSetContext(playhead, isPlaying ? 1 : 0, isRecording ? 1 : 0, sampleRate);
  }

  /// Set selected tracks in context
  void scriptSetSelectedTracks(List<int> trackIds) {
    if (!_loaded) return;
    if (trackIds.isEmpty) {
      _scriptSetSelectedTracks(nullptr, 0);
      return;
    }
    final ptr = calloc<Uint64>(trackIds.length);
    for (int i = 0; i < trackIds.length; i++) {
      ptr[i] = trackIds[i];
    }
    try {
      _scriptSetSelectedTracks(ptr, trackIds.length);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Set selected clips in context
  void scriptSetSelectedClips(List<int> clipIds) {
    if (!_loaded) return;
    if (clipIds.isEmpty) {
      _scriptSetSelectedClips(nullptr, 0);
      return;
    }
    final ptr = calloc<Uint64>(clipIds.length);
    for (int i = 0; i < clipIds.length; i++) {
      ptr[i] = clipIds[i];
    }
    try {
      _scriptSetSelectedClips(ptr, clipIds.length);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Add search path for scripts
  void scriptAddSearchPath(String path) {
    if (!_loaded) return;
    final pathPtr = path.toNativeUtf8();
    try {
      _scriptAddSearchPath(pathPtr);
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Get number of loaded scripts
  int scriptGetLoadedCount() {
    if (!_loaded) return 0;
    return _scriptGetLoadedCount();
  }

  /// Get script name by index
  String? scriptGetName(int index) {
    if (!_loaded) return null;
    final result = _scriptGetName(index);
    if (result == nullptr) return null;
    final name = result.toDartString();
    calloc.free(result);
    return name;
  }

  /// Get script description by index
  String? scriptGetDescription(int index) {
    if (!_loaded) return null;
    final result = _scriptGetDescription(index);
    if (result == nullptr) return null;
    final desc = result.toDartString();
    calloc.free(result);
    return desc;
  }

  /// Get all loaded scripts
  List<ScriptInfo> scriptGetAllScripts() {
    if (!_loaded) return [];
    final scripts = <ScriptInfo>[];
    final count = scriptGetLoadedCount();
    for (int i = 0; i < count; i++) {
      final name = scriptGetName(i);
      final description = scriptGetDescription(i);
      if (name != null) {
        scripts.add(ScriptInfo(
          name: name,
          description: description ?? '',
        ));
      }
    }
    return scripts;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLUGIN HOSTING API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize plugin host (call once at startup)
  bool pluginHostInit() {
    if (!_loaded) return false;
    return _pluginHostInit() != 0;
  }

  /// Scan for all plugins in system locations
  /// Returns number of plugins found, or -1 on error
  int pluginScanAll() {
    if (!_loaded) return -1;
    return _pluginScanAll();
  }

  /// Get number of discovered plugins
  int pluginGetCount() {
    if (!_loaded) return 0;
    return _pluginGetCount();
  }

  /// Get all plugins as list
  List<NativePluginInfo> pluginGetAll() {
    if (!_loaded) return [];
    final jsonPtr = _pluginGetAllJson();
    if (jsonPtr == nullptr) return [];

    try {
      final jsonStr = jsonPtr.toDartString();
      if (jsonStr.isEmpty || jsonStr == '[]') return [];

      final List<dynamic> list = const JsonDecoder().convert(jsonStr) as List<dynamic>;
      return list
          .map((e) => NativePluginInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get single plugin info by index
  NativePluginInfo? pluginGetInfo(int index) {
    if (!_loaded) return null;
    final jsonPtr = _pluginGetInfoJson(index);
    if (jsonPtr == nullptr) return null;

    try {
      final jsonStr = jsonPtr.toDartString();
      if (jsonStr.isEmpty || jsonStr == 'null') return null;

      final map = const JsonDecoder().convert(jsonStr) as Map<String, dynamic>;
      return NativePluginInfo.fromJson(map);
    } catch (e) {
      return null;
    }
  }

  /// Load a plugin instance
  /// Returns instance ID string, or null on failure
  String? pluginLoad(String pluginId) {
    if (!_loaded) return null;
    final idPtr = pluginId.toNativeUtf8();
    final outBuffer = calloc<Uint8>(256);

    try {
      final len = _pluginLoad(idPtr, outBuffer, 256);
      if (len <= 0) return null;

      return String.fromCharCodes(outBuffer.asTypedList(len));
    } finally {
      calloc.free(idPtr);
      calloc.free(outBuffer);
    }
  }

  /// Unload a plugin instance
  bool pluginUnload(String instanceId) {
    if (!_loaded) return false;
    final idPtr = instanceId.toNativeUtf8();
    try {
      return _pluginUnload(idPtr) != 0;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Activate plugin for processing
  bool pluginActivate(String instanceId) {
    if (!_loaded) return false;
    final idPtr = instanceId.toNativeUtf8();
    try {
      return _pluginActivate(idPtr) != 0;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Deactivate plugin
  bool pluginDeactivate(String instanceId) {
    if (!_loaded) return false;
    final idPtr = instanceId.toNativeUtf8();
    try {
      return _pluginDeactivate(idPtr) != 0;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Get plugin parameter count
  int pluginGetParamCount(String instanceId) {
    if (!_loaded) return -1;
    final idPtr = instanceId.toNativeUtf8();
    try {
      return _pluginGetParamCount(idPtr);
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Get plugin parameter value (normalized 0-1)
  double pluginGetParam(String instanceId, int paramId) {
    if (!_loaded) return 0.0;
    final idPtr = instanceId.toNativeUtf8();
    try {
      return _pluginGetParam(idPtr, paramId);
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Set plugin parameter value (normalized 0-1)
  bool pluginSetParam(String instanceId, int paramId, double value) {
    if (!_loaded) return false;
    final idPtr = instanceId.toNativeUtf8();
    try {
      return _pluginSetParam(idPtr, paramId, value) != 0;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Get all plugin parameters
  List<NativePluginParamInfo> pluginGetAllParams(String instanceId) {
    if (!_loaded) return [];
    final idPtr = instanceId.toNativeUtf8();

    try {
      final jsonPtr = _pluginGetAllParamsJson(idPtr);
      if (jsonPtr == nullptr) return [];

      final jsonStr = jsonPtr.toDartString();
      if (jsonStr.isEmpty || jsonStr == '[]') return [];

      final List<dynamic> list = const JsonDecoder().convert(jsonStr) as List<dynamic>;
      return list
          .map((e) => NativePluginParamInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Check if plugin has GUI editor
  bool pluginHasEditor(String instanceId) {
    if (!_loaded) return false;
    final idPtr = instanceId.toNativeUtf8();
    try {
      return _pluginHasEditor(idPtr) != 0;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Get plugin latency in samples
  int pluginGetLatency(String instanceId) {
    if (!_loaded) return 0;
    final idPtr = instanceId.toNativeUtf8();
    try {
      return _pluginGetLatency(idPtr);
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Open plugin editor window
  /// parentWindow: platform window handle (pass from Flutter platform view)
  bool pluginOpenEditor(String instanceId, int parentWindow) {
    if (!_loaded) return false;
    final idPtr = instanceId.toNativeUtf8();
    try {
      return _pluginOpenEditor(idPtr, Pointer.fromAddress(parentWindow)) != 0;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Close plugin editor window
  bool pluginCloseEditor(String instanceId) {
    if (!_loaded) return false;
    final idPtr = instanceId.toNativeUtf8();
    try {
      return _pluginCloseEditor(idPtr) != 0;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Get plugin editor size (width, height)
  (int, int)? pluginEditorSize(String instanceId) {
    if (!_loaded) return null;
    final idPtr = instanceId.toNativeUtf8();
    try {
      final packed = _pluginEditorSize(idPtr);
      if (packed == 0) return null;
      final width = (packed >> 32) & 0xFFFFFFFF;
      final height = packed & 0xFFFFFFFF;
      return (width, height);
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Resize plugin editor
  bool pluginResizeEditor(String instanceId, int width, int height) {
    if (!_loaded) return false;
    final idPtr = instanceId.toNativeUtf8();
    try {
      return _pluginResizeEditor(idPtr, width, height) != 0;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Save plugin preset to file
  bool pluginSavePreset(String instanceId, String path, String presetName) {
    if (!_loaded) return false;
    final idPtr = instanceId.toNativeUtf8();
    final pathPtr = path.toNativeUtf8();
    final namePtr = presetName.toNativeUtf8();
    try {
      return _pluginSavePreset(idPtr, pathPtr, namePtr) != 0;
    } finally {
      calloc.free(idPtr);
      calloc.free(pathPtr);
      calloc.free(namePtr);
    }
  }

  /// Load plugin preset from file
  bool pluginLoadPreset(String instanceId, String path) {
    if (!_loaded) return false;
    final idPtr = instanceId.toNativeUtf8();
    final pathPtr = path.toNativeUtf8();
    try {
      return _pluginLoadPreset(idPtr, pathPtr) != 0;
    } finally {
      calloc.free(idPtr);
      calloc.free(pathPtr);
    }
  }

  /// Search plugins by name
  List<int> pluginSearch(String query, {int maxResults = 100}) {
    if (!_loaded) return [];
    final queryPtr = query.toNativeUtf8();
    final outIndices = calloc<Uint32>(maxResults);

    try {
      final count = _pluginSearch(queryPtr, outIndices, maxResults);
      if (count == 0) return [];
      return List.generate(count, (i) => outIndices[i]);
    } finally {
      calloc.free(queryPtr);
      calloc.free(outIndices);
    }
  }

  /// Get plugins by type
  List<int> pluginGetByType(NativePluginType type, {int maxResults = 500}) {
    if (!_loaded) return [];
    final outIndices = calloc<Uint32>(maxResults);

    try {
      final count = _pluginGetByType(type.code, outIndices, maxResults);
      if (count == 0) return [];
      return List.generate(count, (i) => outIndices[i]);
    } finally {
      calloc.free(outIndices);
    }
  }

  /// Get plugins by category
  List<int> pluginGetByCategory(NativePluginCategory category, {int maxResults = 500}) {
    if (!_loaded) return [];
    final outIndices = calloc<Uint32>(maxResults);

    try {
      final count = _pluginGetByCategory(category.code, outIndices, maxResults);
      if (count == 0) return [];
      return List.generate(count, (i) => outIndices[i]);
    } finally {
      calloc.free(outIndices);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLUGIN INSERT CHAIN
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load plugin into channel insert chain
  /// Returns: 1 = success (queued), -1 = error
  int pluginInsertLoad(int channelId, String pluginId) {
    if (!_loaded) return -1;
    final pluginIdPtr = pluginId.toNativeUtf8();
    try {
      return _pluginInsertLoad(channelId, pluginIdPtr);
    } finally {
      calloc.free(pluginIdPtr);
    }
  }

  /// Remove plugin from insert chain at slot index
  /// Returns: 1 = success (queued), -1 = error
  int pluginInsertRemove(int channelId, int slotIndex) {
    if (!_loaded) return -1;
    return _pluginInsertRemove(channelId, slotIndex);
  }

  /// Set bypass state for insert slot
  /// Returns: 1 = success (queued), -1 = error
  int pluginInsertSetBypass(int channelId, int slotIndex, bool bypass) {
    if (!_loaded) return -1;
    return _pluginInsertSetBypass(channelId, slotIndex, bypass ? 1 : 0);
  }

  /// Set wet/dry mix for insert slot (0.0 = dry, 1.0 = wet)
  /// Returns: 1 = success (queued), -1 = error
  int pluginInsertSetMix(int channelId, int slotIndex, double mix) {
    if (!_loaded) return -1;
    return _pluginInsertSetMix(channelId, slotIndex, mix);
  }

  /// Get wet/dry mix for insert slot
  double pluginInsertGetMix(int channelId, int slotIndex) {
    if (!_loaded) return 1.0;
    return _pluginInsertGetMix(channelId, slotIndex);
  }

  /// Get latency in samples for a specific insert slot
  int pluginInsertGetLatency(int channelId, int slotIndex) {
    if (!_loaded) return 0;
    return _pluginInsertGetLatency(channelId, slotIndex);
  }

  /// Get total latency in samples for entire insert chain
  int pluginInsertChainLatency(int channelId) {
    if (!_loaded) return 0;
    return _pluginInsertChainLatency(channelId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIDI I/O
  // ═══════════════════════════════════════════════════════════════════════════

  /// Scan for MIDI input devices
  /// Returns number of devices found
  int midiScanInputDevices() {
    if (!_loaded) return 0;
    return _midiScanInputDevices();
  }

  /// Scan for MIDI output devices
  int midiScanOutputDevices() {
    if (!_loaded) return 0;
    return _midiScanOutputDevices();
  }

  /// Get MIDI input device name by index
  String? midiGetInputDeviceName(int index) {
    if (!_loaded) return null;
    final buffer = calloc<Uint8>(256);
    try {
      final len = _midiGetInputDeviceName(index, buffer.cast<Utf8>(), 256);
      if (len < 0) return null;
      return buffer.cast<Utf8>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  /// Get MIDI output device name by index
  String? midiGetOutputDeviceName(int index) {
    if (!_loaded) return null;
    final buffer = calloc<Uint8>(256);
    try {
      final len = _midiGetOutputDeviceName(index, buffer.cast<Utf8>(), 256);
      if (len < 0) return null;
      return buffer.cast<Utf8>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  /// Get all MIDI input device names
  List<String> midiGetAllInputDevices() {
    if (!_loaded) return [];
    final count = _midiInputDeviceCount();
    final devices = <String>[];
    for (int i = 0; i < count; i++) {
      final name = midiGetInputDeviceName(i);
      if (name != null) devices.add(name);
    }
    return devices;
  }

  /// Get all MIDI output device names
  List<String> midiGetAllOutputDevices() {
    if (!_loaded) return [];
    final count = _midiOutputDeviceCount();
    final devices = <String>[];
    for (int i = 0; i < count; i++) {
      final name = midiGetOutputDeviceName(i);
      if (name != null) devices.add(name);
    }
    return devices;
  }

  /// Connect to MIDI input device by index
  bool midiConnectInput(int deviceIndex) {
    if (!_loaded) return false;
    return _midiConnectInput(deviceIndex) == 1;
  }

  /// Disconnect from MIDI input by connection index
  bool midiDisconnectInput(int connectionIndex) {
    if (!_loaded) return false;
    return _midiDisconnectInput(connectionIndex) == 1;
  }

  /// Disconnect all MIDI inputs
  void midiDisconnectAllInputs() {
    if (!_loaded) return;
    _midiDisconnectAllInputs();
  }

  /// Get number of active MIDI input connections
  int midiActiveInputCount() {
    if (!_loaded) return 0;
    return _midiActiveInputCount();
  }

  /// Connect to MIDI output device
  bool midiConnectOutput(int deviceIndex) {
    if (!_loaded) return false;
    return _midiConnectOutput(deviceIndex) == 1;
  }

  /// Disconnect MIDI output
  void midiDisconnectOutput() {
    if (!_loaded) return;
    _midiDisconnectOutput();
  }

  /// Check if MIDI output is connected
  bool midiIsOutputConnected() {
    if (!_loaded) return false;
    return _midiIsOutputConnected() != 0;
  }

  /// Start MIDI recording for a track
  void midiStartRecording(int trackId) {
    if (!_loaded) return;
    _midiStartRecording(trackId);
  }

  /// Stop MIDI recording
  void midiStopRecording() {
    if (!_loaded) return;
    _midiStopRecording();
  }

  /// Arm track for MIDI recording
  void midiArmTrack(int trackId) {
    if (!_loaded) return;
    _midiArmTrack(trackId);
  }

  /// Check if MIDI recording is active
  bool midiIsRecording() {
    if (!_loaded) return false;
    return _midiIsRecording() != 0;
  }

  /// Get MIDI recording state
  /// Returns: 0=Stopped, 1=Armed, 2=Recording, 3=Paused
  int midiGetRecordingState() {
    if (!_loaded) return 0;
    return _midiGetRecordingState();
  }

  /// Get number of recorded MIDI events
  int midiRecordedEventCount() {
    if (!_loaded) return 0;
    return _midiRecordedEventCount();
  }

  /// Get target track for recording
  int midiGetTargetTrack() {
    if (!_loaded) return 0;
    return _midiGetTargetTrack();
  }

  /// Set sample rate for MIDI timestamp conversion
  void midiSetSampleRate(int sampleRate) {
    if (!_loaded) return;
    _midiSetSampleRate(sampleRate);
  }

  /// Enable/disable MIDI thru
  void midiSetThru(bool enabled) {
    if (!_loaded) return;
    _midiSetThru(enabled ? 1 : 0);
  }

  /// Check if MIDI thru is enabled
  bool midiIsThruEnabled() {
    if (!_loaded) return false;
    return _midiIsThruEnabled() != 0;
  }

  /// Send MIDI note on
  bool midiSendNoteOn(int channel, int note, int velocity) {
    if (!_loaded) return false;
    return _midiSendNoteOn(channel, note, velocity) == 1;
  }

  /// Send MIDI note off
  bool midiSendNoteOff(int channel, int note, int velocity) {
    if (!_loaded) return false;
    return _midiSendNoteOff(channel, note, velocity) == 1;
  }

  /// Send MIDI CC
  bool midiSendCc(int channel, int cc, int value) {
    if (!_loaded) return false;
    return _midiSendCc(channel, cc, value) == 1;
  }

  /// Send MIDI pitch bend (14-bit value, center = 8192)
  bool midiSendPitchBend(int channel, int value) {
    if (!_loaded) return false;
    return _midiSendPitchBend(channel, value) == 1;
  }

  /// Send MIDI program change
  bool midiSendProgramChange(int channel, int program) {
    if (!_loaded) return false;
    return _midiSendProgramChange(channel, program) == 1;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTOSAVE SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize autosave system with project name
  bool autosaveInit(String projectName) {
    if (!_loaded) return false;
    final namePtr = projectName.toNativeUtf8();
    try {
      return _autosaveInit(namePtr) == 1;
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Shutdown autosave system
  void autosaveShutdown() {
    if (!_loaded) return;
    _autosaveShutdown();
  }

  /// Set autosave enabled state
  void autosaveSetEnabled(bool enabled) {
    if (!_loaded) return;
    _autosaveSetEnabled(enabled ? 1 : 0);
  }

  /// Check if autosave is enabled
  bool autosaveIsEnabled() {
    if (!_loaded) return false;
    return _autosaveIsEnabled() != 0;
  }

  /// Set autosave interval in seconds
  void autosaveSetInterval(int intervalSecs) {
    if (!_loaded) return;
    _autosaveSetInterval(intervalSecs);
  }

  /// Get autosave interval in seconds
  int autosaveGetInterval() {
    if (!_loaded) return 60;
    return _autosaveGetInterval();
  }

  /// Set backup count (how many autosaves to keep)
  void autosaveSetBackupCount(int count) {
    if (!_loaded) return;
    _autosaveSetBackupCount(count);
  }

  /// Get backup count
  int autosaveGetBackupCount() {
    if (!_loaded) return 5;
    return _autosaveGetBackupCount();
  }

  /// Mark project as having unsaved changes
  void autosaveMarkDirty() {
    if (!_loaded) return;
    _autosaveMarkDirty();
  }

  /// Mark project as saved (clean)
  void autosaveMarkClean() {
    if (!_loaded) return;
    _autosaveMarkClean();
  }

  /// Check if project has unsaved changes
  bool autosaveIsDirty() {
    if (!_loaded) return false;
    return _autosaveIsDirty() != 0;
  }

  /// Check if autosave should run now
  bool autosaveShouldSave() {
    if (!_loaded) return false;
    return _autosaveShouldSave() != 0;
  }

  /// Perform autosave with project data
  /// Returns: 1 = success, 0 = skipped (no changes), -1 = error
  int autosaveNow(String projectData) {
    if (!_loaded) return -1;
    final dataPtr = projectData.toNativeUtf8();
    try {
      return _autosaveNow(dataPtr);
    } finally {
      calloc.free(dataPtr);
    }
  }

  /// Get count of available autosave backups
  int autosaveBackupCount() {
    if (!_loaded) return 0;
    return _autosaveBackupCount();
  }

  /// Get path to latest autosave backup
  String? autosaveLatestPath() {
    if (!_loaded) return null;
    final buffer = calloc<Uint8>(1024);
    try {
      final len = _autosaveLatestPath(buffer.cast<Utf8>(), 1024);
      if (len > 0) {
        return buffer.cast<Utf8>().toDartString();
      }
      return null;
    } finally {
      calloc.free(buffer);
    }
  }

  /// Clear all autosave backups for current project
  void autosaveClearBackups() {
    if (!_loaded) return;
    _autosaveClearBackups();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RECENT PROJECTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add project to recent list
  bool recentProjectsAdd(String path) {
    if (!_loaded) return false;
    final pathPtr = path.toNativeUtf8();
    try {
      return _recentProjectsAdd(pathPtr) == 1;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Get recent project count
  int recentProjectsCount() {
    if (!_loaded) return 0;
    return _recentProjectsCount();
  }

  /// Get recent project path by index
  String? recentProjectsGet(int index) {
    if (!_loaded) return null;
    final buffer = calloc<Uint8>(1024);
    try {
      final len = _recentProjectsGet(index, buffer.cast<Utf8>(), 1024);
      if (len > 0) {
        return buffer.cast<Utf8>().toDartString();
      }
      return null;
    } finally {
      calloc.free(buffer);
    }
  }

  /// Get all recent projects
  List<String> recentProjectsGetAll() {
    final count = recentProjectsCount();
    final result = <String>[];
    for (var i = 0; i < count; i++) {
      final path = recentProjectsGet(i);
      if (path != null) {
        result.add(path);
      }
    }
    return result;
  }

  /// Remove project from recent list
  bool recentProjectsRemove(String path) {
    if (!_loaded) return false;
    final pathPtr = path.toNativeUtf8();
    try {
      return _recentProjectsRemove(pathPtr) == 1;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Clear all recent projects
  void recentProjectsClear() {
    if (!_loaded) return;
    _recentProjectsClear();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WAVE CACHE (Multi-Resolution Waveform Caching)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if .wfc cache exists for audio file
  bool waveCacheHasCache(String audioPath) {
    if (!_loaded) return false;
    final pathPtr = audioPath.toNativeUtf8();
    try {
      return _waveCacheHasCache(pathPtr) != 0;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Start building cache for audio file
  /// Returns: 0 = started building, 1 = already cached, -1 = error
  int waveCacheBuild(String audioPath, int sampleRate, int channels, int totalFrames) {
    if (!_loaded) return -1;
    final pathPtr = audioPath.toNativeUtf8();
    try {
      return _waveCacheBuild(pathPtr, sampleRate, channels, totalFrames);
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Get build progress (0.0 - 1.0, or -1.0 if not building)
  double waveCacheBuildProgress(String audioPath) {
    if (!_loaded) return -1.0;
    final pathPtr = audioPath.toNativeUtf8();
    try {
      return _waveCacheBuildProgress(pathPtr);
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Query tiles for rendering
  /// Returns WaveCacheTileResult with peak data, or null on error
  WaveCacheTileResult? waveCacheQueryTiles(
    String audioPath,
    int startFrame,
    int endFrame,
    double pixelsPerSecond,
    int sampleRate,
  ) {
    if (!_loaded) return null;

    final pathPtr = audioPath.toNativeUtf8();
    final outMipLevel = calloc<Uint32>();
    final outSamplesPerTile = calloc<Uint32>();
    final outTileCount = calloc<Uint32>();

    try {
      final tilesPtr = _waveCacheQueryTiles(
        pathPtr,
        startFrame,
        endFrame,
        pixelsPerSecond,
        sampleRate,
        outMipLevel,
        outSamplesPerTile,
        outTileCount,
      );

      if (tilesPtr == nullptr) return null;

      final tileCount = outTileCount.value;
      if (tileCount == 0) {
        _waveCacheFreeTiles(tilesPtr, tileCount);
        return null;
      }

      // Copy data to Dart
      final peaks = Float32List(tileCount * 2);
      for (int i = 0; i < tileCount * 2; i++) {
        peaks[i] = tilesPtr[i];
      }

      final result = WaveCacheTileResult(
        mipLevel: outMipLevel.value,
        samplesPerTile: outSamplesPerTile.value,
        peaks: peaks,
      );

      // Free native memory
      _waveCacheFreeTiles(tilesPtr, tileCount);

      return result;
    } finally {
      calloc.free(pathPtr);
      calloc.free(outMipLevel);
      calloc.free(outSamplesPerTile);
      calloc.free(outTileCount);
    }
  }

  /// Build cache from already-loaded samples
  bool waveCacheBuildFromSamples(
    String audioPath,
    Float32List samples,
    int channels,
    int sampleRate,
  ) {
    if (!_loaded) return false;

    final pathPtr = audioPath.toNativeUtf8();
    final samplesPtr = calloc<Float>(samples.length);

    try {
      // Copy samples to native memory
      for (int i = 0; i < samples.length; i++) {
        samplesPtr[i] = samples[i];
      }

      return _waveCacheBuildFromSamples(
        pathPtr,
        samplesPtr,
        samples.length,
        channels,
        sampleRate,
      ) != 0;
    } finally {
      calloc.free(pathPtr);
      calloc.free(samplesPtr);
    }
  }

  /// Clear all wave caches
  void waveCacheClearAll() {
    if (!_loaded) return;
    _waveCacheClearAll();
  }

  /// Get number of loaded caches
  int waveCacheLoadedCount() {
    if (!_loaded) return 0;
    return _waveCacheLoadedCount();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPING API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new lane for a track
  /// Returns lane ID (0 on failure)
  int compingCreateLane(int trackId) {
    if (!_loaded) return 0;
    return _compingCreateLane(trackId);
  }

  /// Delete a lane
  bool compingDeleteLane(int trackId, int laneId) {
    if (!_loaded) return false;
    return _compingDeleteLane(trackId, laneId) == 1;
  }

  /// Set active lane for a track
  bool compingSetActiveLane(int trackId, int laneIndex) {
    if (!_loaded) return false;
    return _compingSetActiveLane(trackId, laneIndex) == 1;
  }

  /// Toggle lane mute
  bool compingToggleLaneMute(int trackId, int laneId) {
    if (!_loaded) return false;
    return _compingToggleLaneMute(trackId, laneId) == 1;
  }

  /// Set lane visibility
  bool compingSetLaneVisible(int trackId, int laneId, bool visible) {
    if (!_loaded) return false;
    return _compingSetLaneVisible(trackId, laneId, visible ? 1 : 0) == 1;
  }

  /// Set lane height
  bool compingSetLaneHeight(int trackId, int laneId, double height) {
    if (!_loaded) return false;
    return _compingSetLaneHeight(trackId, laneId, height) == 1;
  }

  /// Add a take to active lane
  /// Returns take ID (0 on failure)
  int compingAddTake(int trackId, String sourcePath, double startTime, double duration) {
    if (!_loaded) return 0;
    final pathPtr = sourcePath.toNativeUtf8();
    try {
      return _compingAddTake(trackId, pathPtr, startTime, duration);
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Delete a take
  bool compingDeleteTake(int trackId, int takeId) {
    if (!_loaded) return false;
    return _compingDeleteTake(trackId, takeId) == 1;
  }

  /// Set take rating (0=None, 1=Bad, 2=Okay, 3=Good, 4=Best)
  bool compingSetTakeRating(int trackId, int takeId, int rating) {
    if (!_loaded) return false;
    return _compingSetTakeRating(trackId, takeId, rating) == 1;
  }

  /// Toggle take mute
  bool compingToggleTakeMute(int trackId, int takeId) {
    if (!_loaded) return false;
    return _compingToggleTakeMute(trackId, takeId) == 1;
  }

  /// Toggle take in comp
  bool compingToggleTakeInComp(int trackId, int takeId) {
    if (!_loaded) return false;
    return _compingToggleTakeInComp(trackId, takeId) == 1;
  }

  /// Set take gain (0.0-2.0, 1.0 = unity)
  bool compingSetTakeGain(int trackId, int takeId, double gain) {
    if (!_loaded) return false;
    return _compingSetTakeGain(trackId, takeId, gain) == 1;
  }

  /// Create a comp region
  /// Returns region ID (0 on failure)
  int compingCreateRegion(int trackId, int takeId, double startTime, double endTime) {
    if (!_loaded) return 0;
    return _compingCreateRegion(trackId, takeId, startTime, endTime);
  }

  /// Delete a comp region
  bool compingDeleteRegion(int trackId, int regionId) {
    if (!_loaded) return false;
    return _compingDeleteRegion(trackId, regionId) == 1;
  }

  /// Set region crossfade in duration
  bool compingSetRegionCrossfadeIn(int trackId, int regionId, double duration) {
    if (!_loaded) return false;
    return _compingSetRegionCrossfadeIn(trackId, regionId, duration) == 1;
  }

  /// Set region crossfade out duration
  bool compingSetRegionCrossfadeOut(int trackId, int regionId, double duration) {
    if (!_loaded) return false;
    return _compingSetRegionCrossfadeOut(trackId, regionId, duration) == 1;
  }

  /// Set region crossfade type (0=Linear, 1=EqualPower, 2=SCurve)
  bool compingSetRegionCrossfadeType(int trackId, int regionId, int crossfadeType) {
    if (!_loaded) return false;
    return _compingSetRegionCrossfadeType(trackId, regionId, crossfadeType) == 1;
  }

  /// Set comp mode (0=Single, 1=Comp, 2=AuditAll)
  bool compingSetMode(int trackId, int mode) {
    if (!_loaded) return false;
    return _compingSetMode(trackId, mode) == 1;
  }

  /// Get comp mode (0=Single, 1=Comp, 2=AuditAll, -1=error)
  int compingGetMode(int trackId) {
    if (!_loaded) return -1;
    return _compingGetMode(trackId);
  }

  /// Toggle lanes expanded for a track
  bool compingToggleLanesExpanded(int trackId) {
    if (!_loaded) return false;
    return _compingToggleLanesExpanded(trackId) == 1;
  }

  /// Get lanes expanded state
  bool? compingGetLanesExpanded(int trackId) {
    if (!_loaded) return null;
    final result = _compingGetLanesExpanded(trackId);
    if (result == -1) return null;
    return result == 1;
  }

  /// Get number of lanes for a track
  int compingGetLaneCount(int trackId) {
    if (!_loaded) return 0;
    return _compingGetLaneCount(trackId);
  }

  /// Get active lane index
  int compingGetActiveLaneIndex(int trackId) {
    if (!_loaded) return -1;
    return _compingGetActiveLaneIndex(trackId);
  }

  /// Clear all comp regions for a track
  bool compingClearComp(int trackId) {
    if (!_loaded) return false;
    return _compingClearComp(trackId) == 1;
  }

  /// Get comp state as JSON
  String? compingGetStateJson(int trackId) {
    if (!_loaded) return null;
    final ptr = _compingGetStateJson(trackId);
    if (ptr == nullptr) return null;
    try {
      return ptr.toDartString();
    } finally {
      _freeString(ptr);
    }
  }

  /// Load comp state from JSON
  bool compingLoadStateJson(int trackId, String json) {
    if (!_loaded) return false;
    final jsonPtr = json.toNativeUtf8();
    try {
      return _compingLoadStateJson(trackId, jsonPtr) == 1;
    } finally {
      calloc.free(jsonPtr);
    }
  }

  /// Start recording on a track
  bool compingStartRecording(int trackId, double startTime) {
    if (!_loaded) return false;
    return _compingStartRecording(trackId, startTime) == 1;
  }

  /// Stop recording on a track
  bool compingStopRecording(int trackId) {
    if (!_loaded) return false;
    return _compingStopRecording(trackId) == 1;
  }

  /// Check if track is recording
  bool compingIsRecording(int trackId) {
    if (!_loaded) return false;
    return _compingIsRecording(trackId) == 1;
  }

  /// Delete all "bad" rated takes
  /// Returns number of deleted takes
  int compingDeleteBadTakes(int trackId) {
    if (!_loaded) return 0;
    return _compingDeleteBadTakes(trackId);
  }

  /// Promote "best" rated takes to comp
  /// Returns number of regions created
  int compingPromoteBestTakes(int trackId) {
    if (!_loaded) return 0;
    return _compingPromoteBestTakes(trackId);
  }

  /// Remove track from comping manager
  void compingRemoveTrack(int trackId) {
    if (!_loaded) return;
    _compingRemoveTrack(trackId);
  }

  /// Clear all comping state
  void compingClearAll() {
    if (!_loaded) return;
    _compingClearAll();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VIDEO FFI PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a video track
  /// Returns track ID, or 0 on failure
  int videoAddTrack(String name) {
    if (!_loaded) return 0;
    final namePtr = name.toNativeUtf8();
    try {
      return _videoAddTrack(namePtr);
    } finally {
      malloc.free(namePtr);
    }
  }

  /// Import video file to track
  /// Returns clip ID, or 0 on failure
  int videoImport(int trackId, String path, int timelineStartSamples) {
    if (!_loaded) return 0;
    final pathPtr = path.toNativeUtf8();
    try {
      return _videoImport(trackId, pathPtr, timelineStartSamples);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Set video playhead position (in samples)
  void videoSetPlayhead(int samples) {
    if (!_loaded) return;
    _videoSetPlayhead(samples);
  }

  /// Get video playhead position (in samples)
  int videoGetPlayhead() {
    if (!_loaded) return 0;
    return _videoGetPlayhead();
  }

  /// Get video frame at given sample position
  /// Returns RGBA pixel data as Uint8List, or null on failure
  /// width/height are output parameters
  ({Uint8List? data, int width, int height}) videoGetFrame(int clipId, int frameSamples) {
    if (!_loaded) return (data: null, width: 0, height: 0);

    final widthPtr = malloc<Uint32>();
    final heightPtr = malloc<Uint32>();
    final sizePtr = malloc<Uint64>();

    try {
      final dataPtr = _videoGetFrame(clipId, frameSamples, widthPtr, heightPtr, sizePtr);
      if (dataPtr == nullptr) {
        return (data: null, width: 0, height: 0);
      }

      final width = widthPtr.value;
      final height = heightPtr.value;
      final size = sizePtr.value;

      // Copy data to Dart-managed memory
      final data = Uint8List.fromList(dataPtr.asTypedList(size));

      // Free Rust-allocated memory
      _videoFreeFrame(dataPtr, size);

      return (data: data, width: width, height: height);
    } finally {
      malloc.free(widthPtr);
      malloc.free(heightPtr);
      malloc.free(sizePtr);
    }
  }

  /// Get video info as JSON
  String? videoGetInfoJson(int clipId) {
    if (!_loaded) return null;
    final ptr = _videoGetInfoJson(clipId);
    if (ptr == nullptr) return null;
    try {
      return ptr.toDartString();
    } finally {
      malloc.free(ptr);
    }
  }

  /// Generate thumbnails for video clip
  /// Returns number of thumbnails generated
  int videoGenerateThumbnails(int clipId, int width, int intervalFrames) {
    if (!_loaded) return 0;
    return _videoGenerateThumbnails(clipId, width, intervalFrames);
  }

  /// Get number of video tracks
  int videoGetTrackCount() {
    if (!_loaded) return 0;
    return _videoGetTrackCount();
  }

  /// Clear all video state
  void videoClearAll() {
    if (!_loaded) return;
    _videoClearAll();
  }

  /// Format timecode from seconds
  /// dropFrame: 0=NDF, 1=DF
  String videoFormatTimecode(double seconds, double frameRate, {bool dropFrame = false}) {
    if (!_loaded) return '00:00:00:00';
    final ptr = _videoFormatTimecode(seconds, frameRate, dropFrame ? 1 : 0);
    if (ptr == nullptr) return '00:00:00:00';
    try {
      return ptr.toDartString();
    } finally {
      malloc.free(ptr);
    }
  }

  /// Parse timecode string to seconds
  /// Returns -1.0 on error
  double videoParseTimecode(String timecode, double frameRate) {
    if (!_loaded) return -1.0;
    final tcPtr = timecode.toNativeUtf8();
    try {
      return _videoParseTimecode(tcPtr, frameRate);
    } finally {
      malloc.free(tcPtr);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIDDLEWARE EVENT SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize middleware event system
  /// Returns command consumer pointer for audio thread (or null if failed)
  Pointer<Void> middlewareInit() {
    if (!_loaded) return Pointer.fromAddress(0);
    return _middlewareInit();
  }

  /// Shutdown middleware event system
  void middlewareShutdown() {
    if (!_loaded) return;
    _middlewareShutdown();
  }

  /// Check if middleware is initialized
  bool middlewareIsInitialized() {
    if (!_loaded) return false;
    return _middlewareIsInitialized() != 0;
  }

  /// Register an event
  bool middlewareRegisterEvent(int eventId, String name, String category, {int maxInstances = 0}) {
    if (!_loaded) return false;
    final namePtr = name.toNativeUtf8();
    final catPtr = category.toNativeUtf8();
    try {
      return _middlewareRegisterEvent(eventId, namePtr, catPtr, maxInstances) != 0;
    } finally {
      malloc.free(namePtr);
      malloc.free(catPtr);
    }
  }

  /// Add an action to an event
  bool middlewareAddAction(
    int eventId,
    MiddlewareActionType actionType, {
    int assetId = 0,
    int busId = 0,
    MiddlewareActionScope scope = MiddlewareActionScope.global,
    MiddlewareActionPriority priority = MiddlewareActionPriority.normal,
    MiddlewareFadeCurve fadeCurve = MiddlewareFadeCurve.linear,
    int fadeTimeMs = 0,
    int delayMs = 0,
  }) {
    if (!_loaded) return false;
    return _middlewareAddAction(
      eventId, actionType.index, assetId, busId,
      scope.index, priority.index, fadeCurve.index,
      fadeTimeMs, delayMs,
    ) != 0;
  }

  /// Post an event
  /// Returns playing ID (or 0 on failure)
  int middlewarePostEvent(int eventId, {int gameObjectId = 0}) {
    if (!_loaded) return 0;
    return _middlewarePostEvent(eventId, gameObjectId);
  }

  /// Post an event by name
  /// Returns playing ID (or 0 on failure)
  int middlewarePostEventByName(String eventName, {int gameObjectId = 0}) {
    if (!_loaded) return 0;
    final namePtr = eventName.toNativeUtf8();
    try {
      return _middlewarePostEventByName(namePtr, gameObjectId);
    } finally {
      malloc.free(namePtr);
    }
  }

  /// Stop a playing instance
  bool middlewareStopPlayingId(int playingId, {int fadeMs = 0}) {
    if (!_loaded) return false;
    return _middlewareStopPlayingId(playingId, fadeMs) != 0;
  }

  /// Stop all instances of an event
  void middlewareStopEvent(int eventId, {int gameObjectId = 0, int fadeMs = 0}) {
    if (!_loaded) return;
    _middlewareStopEvent(eventId, gameObjectId, fadeMs);
  }

  /// Stop all events
  void middlewareStopAll({int fadeMs = 0}) {
    if (!_loaded) return;
    _middlewareStopAll(fadeMs);
  }

  /// Register a state group
  bool middlewareRegisterStateGroup(int groupId, String name, {int defaultState = 0}) {
    if (!_loaded) return false;
    final namePtr = name.toNativeUtf8();
    try {
      return _middlewareRegisterStateGroup(groupId, namePtr, defaultState) != 0;
    } finally {
      malloc.free(namePtr);
    }
  }

  /// Add a state to a group
  bool middlewareAddState(int groupId, int stateId, String stateName) {
    if (!_loaded) return false;
    final namePtr = stateName.toNativeUtf8();
    try {
      return _middlewareAddState(groupId, stateId, namePtr) != 0;
    } finally {
      malloc.free(namePtr);
    }
  }

  /// Set current state
  bool middlewareSetState(int groupId, int stateId) {
    if (!_loaded) return false;
    return _middlewareSetState(groupId, stateId) != 0;
  }

  /// Get current state
  int middlewareGetState(int groupId) {
    if (!_loaded) return 0;
    return _middlewareGetState(groupId);
  }

  /// Register a switch group
  bool middlewareRegisterSwitchGroup(int groupId, String name) {
    if (!_loaded) return false;
    final namePtr = name.toNativeUtf8();
    try {
      return _middlewareRegisterSwitchGroup(groupId, namePtr) != 0;
    } finally {
      malloc.free(namePtr);
    }
  }

  /// Add a switch to a group
  bool middlewareAddSwitch(int groupId, int switchId, String switchName) {
    if (!_loaded) return false;
    final namePtr = switchName.toNativeUtf8();
    try {
      return _middlewareAddSwitch(groupId, switchId, namePtr) != 0;
    } finally {
      malloc.free(namePtr);
    }
  }

  /// Set switch on game object
  bool middlewareSetSwitch(int gameObjectId, int groupId, int switchId) {
    if (!_loaded) return false;
    return _middlewareSetSwitch(gameObjectId, groupId, switchId) != 0;
  }

  /// Register an RTPC
  bool middlewareRegisterRtpc(int rtpcId, String name, double min, double max, double defaultValue) {
    if (!_loaded) return false;
    final namePtr = name.toNativeUtf8();
    try {
      return _middlewareRegisterRtpc(rtpcId, namePtr, min, max, defaultValue) != 0;
    } finally {
      malloc.free(namePtr);
    }
  }

  /// Set RTPC value globally
  bool middlewareSetRtpc(int rtpcId, double value, {int interpolationMs = 0}) {
    if (!_loaded) return false;
    return _middlewareSetRtpc(rtpcId, value, interpolationMs) != 0;
  }

  /// Set RTPC value on game object
  bool middlewareSetRtpcOnObject(int gameObjectId, int rtpcId, double value, {int interpolationMs = 0}) {
    if (!_loaded) return false;
    return _middlewareSetRtpcOnObject(gameObjectId, rtpcId, value, interpolationMs) != 0;
  }

  /// Get RTPC value
  double middlewareGetRtpc(int rtpcId) {
    if (!_loaded) return 0.0;
    return _middlewareGetRtpc(rtpcId);
  }

  /// Reset RTPC to default
  bool middlewareResetRtpc(int rtpcId, {int interpolationMs = 0}) {
    if (!_loaded) return false;
    return _middlewareResetRtpc(rtpcId, interpolationMs) != 0;
  }

  /// Register a game object
  bool middlewareRegisterGameObject(int gameObjectId, {String? name}) {
    if (!_loaded) return false;
    final namePtr = name != null ? name.toNativeUtf8() : nullptr;
    try {
      return _middlewareRegisterGameObject(gameObjectId, namePtr) != 0;
    } finally {
      if (namePtr != nullptr) malloc.free(namePtr);
    }
  }

  /// Unregister a game object
  void middlewareUnregisterGameObject(int gameObjectId) {
    if (!_loaded) return;
    _middlewareUnregisterGameObject(gameObjectId);
  }

  /// Get number of registered events
  int middlewareGetEventCount() {
    if (!_loaded) return 0;
    return _middlewareGetEventCount();
  }

  /// Get number of registered state groups
  int middlewareGetStateGroupCount() {
    if (!_loaded) return 0;
    return _middlewareGetStateGroupCount();
  }

  /// Get number of registered switch groups
  int middlewareGetSwitchGroupCount() {
    if (!_loaded) return 0;
    return _middlewareGetSwitchGroupCount();
  }

  /// Get number of registered RTPCs
  int middlewareGetRtpcCount() {
    if (!_loaded) return 0;
    return _middlewareGetRtpcCount();
  }

  /// Get active instance count
  int middlewareGetActiveInstanceCount() {
    if (!_loaded) return 0;
    return _middlewareGetActiveInstanceCount();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE SYSTEM API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Parse JSON with adapter and store trace
  /// Returns JSON result with trace_id on success, or error field on failure
  String? stageParseJson(String json, String adapterId) {
    if (!_loaded) return null;
    final adapterPtr = adapterId.toNativeUtf8();
    final jsonPtr = json.toNativeUtf8();
    try {
      final resultPtr = _stageParseJson(adapterPtr, jsonPtr);
      if (resultPtr == nullptr) return null;
      return resultPtr.toDartString();
    } finally {
      calloc.free(adapterPtr);
      calloc.free(jsonPtr);
    }
  }

  /// Get current trace as JSON
  String? stageGetTraceJson() {
    if (!_loaded) return null;
    final ptr = _stageGetTraceJson();
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    return str.isEmpty ? null : str;
  }

  /// Get event count in current trace
  int stageGetEventCount() {
    if (!_loaded) return 0;
    return _stageGetEventCount();
  }

  /// Get event at index as JSON
  String? stageGetEventJson(int index) {
    if (!_loaded) return null;
    final ptr = _stageGetEventJson(index);
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    return str.isEmpty ? null : str;
  }

  /// Resolve timing for current trace
  /// profile: 0=Normal, 1=Turbo, 2=Mobile, 3=Studio, 4=Instant
  bool stageResolveTiming(int profile) {
    if (!_loaded) return false;
    return _stageResolveTiming(profile) != 0;
  }

  /// Get timed trace as JSON
  String? stageGetTimedTraceJson() {
    if (!_loaded) return null;
    final ptr = _stageGetTimedTraceJson();
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    return str.isEmpty ? null : str;
  }

  /// Get trace duration in milliseconds
  double stageGetDurationMs() {
    if (!_loaded) return 0.0;
    return _stageGetDurationMs();
  }

  /// Get events at specific time as JSON array
  String? stageGetEventsAtTime(double timeMs) {
    if (!_loaded) return null;
    final ptr = _stageGetEventsAtTime(timeMs);
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    return str.isEmpty ? null : str;
  }

  /// Analyze JSON with wizard
  bool wizardAnalyzeJson(String json) {
    if (!_loaded) return false;
    final ptr = json.toNativeUtf8();
    try {
      return _wizardAnalyzeJson(ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Get wizard confidence score
  double wizardGetConfidence() {
    if (!_loaded) return 0.0;
    return _wizardGetConfidence();
  }

  /// Get recommended ingest layer
  String? wizardGetRecommendedLayer() {
    if (!_loaded) return null;
    final ptr = _wizardGetRecommendedLayer();
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    return str.isEmpty ? null : str;
  }

  /// Get detected company name
  String? wizardGetDetectedCompany() {
    if (!_loaded) return null;
    final ptr = _wizardGetDetectedCompany();
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    return str.isEmpty ? null : str;
  }

  /// Get detected engine name
  String? wizardGetDetectedEngine() {
    if (!_loaded) return null;
    final ptr = _wizardGetDetectedEngine();
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    return str.isEmpty ? null : str;
  }

  /// Get generated config TOML
  String? wizardGetConfigToml() {
    if (!_loaded) return null;
    final ptr = _wizardGetConfigToml();
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    return str.isEmpty ? null : str;
  }

  /// Get detected event count
  int wizardGetDetectedEventCount() {
    if (!_loaded) return 0;
    return _wizardGetDetectedEventCount();
  }

  /// Get detected event at index as JSON
  String? wizardGetDetectedEventJson(int index) {
    if (!_loaded) return null;
    final ptr = _wizardGetDetectedEventJson(index);
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    return str.isEmpty ? null : str;
  }

  /// Load adapter from TOML config
  bool adapterLoadConfig(String toml) {
    if (!_loaded) return false;
    final ptr = toml.toNativeUtf8();
    try {
      return _adapterLoadConfig(ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Get adapter count
  int adapterGetCount() {
    if (!_loaded) return 0;
    return _adapterGetCount();
  }

  /// Get adapter ID at index
  String? adapterGetIdAt(int index) {
    if (!_loaded) return null;
    final ptr = _adapterGetIdAt(index);
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    return str.isEmpty ? null : str;
  }

  /// Get adapter info at index as JSON
  String? adapterGetInfoJson(int index) {
    if (!_loaded) return null;
    final ptr = _adapterGetInfoJson(index);
    if (ptr == nullptr) return null;
    final str = ptr.toDartString();
    return str.isEmpty ? null : str;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED MIDDLEWARE FEATURES (Ducking, Blend, Random, Sequence, Music, Attenuation)
  // ═══════════════════════════════════════════════════════════════════════════
  // Note: These are high-level wrappers. Native FFI functions are looked up dynamically
  // when the native library is rebuilt with these exports.

  /// Add a ducking rule
  bool middlewareAddDuckingRule(DuckingRule rule) {
    if (!_loaded) return false;
    try {
      final sourceBusPtr = rule.sourceBus.toNativeUtf8();
      final targetBusPtr = rule.targetBus.toNativeUtf8();
      try {
        final fn = _lib.lookupFunction<
          Int32 Function(Uint32, Pointer<Utf8>, Uint32, Pointer<Utf8>, Uint32, Float, Float, Float, Float, Uint32),
          int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int, double, double, double, double, int)
        >('middleware_add_ducking_rule');
        return fn(
          rule.id,
          sourceBusPtr,
          rule.sourceBusId,
          targetBusPtr,
          rule.targetBusId,
          rule.duckAmountDb,
          rule.attackMs,
          rule.releaseMs,
          rule.threshold,
          rule.curve.index,
        ) != 0;
      } finally {
        malloc.free(sourceBusPtr);
        malloc.free(targetBusPtr);
      }
    } catch (e) {
      print('[NativeFFI] middlewareAddDuckingRule not available: $e');
      return true; // Return success for UI purposes when native not rebuilt
    }
  }

  /// Remove a ducking rule
  bool middlewareRemoveDuckingRule(int ruleId) {
    if (!_loaded) return false;
    try {
      final fn = _lib.lookupFunction<Int32 Function(Uint32), int Function(int)>('middleware_remove_ducking_rule');
      return fn(ruleId) != 0;
    } catch (e) {
      return true;
    }
  }

  /// Set ducking rule enabled
  bool middlewareSetDuckingRuleEnabled(int ruleId, bool enabled) {
    if (!_loaded) return false;
    try {
      final fn = _lib.lookupFunction<Int32 Function(Uint32, Int32), int Function(int, int)>('middleware_set_ducking_rule_enabled');
      return fn(ruleId, enabled ? 1 : 0) != 0;
    } catch (e) {
      return true;
    }
  }

  /// Create a blend container
  bool middlewareCreateBlendContainer(BlendContainer container) {
    if (!_loaded) return false;
    try {
      final namePtr = container.name.toNativeUtf8();
      try {
        final fn = _lib.lookupFunction<
          Int32 Function(Uint32, Pointer<Utf8>, Uint32, Uint32),
          int Function(int, Pointer<Utf8>, int, int)
        >('middleware_create_blend_container');
        return fn(container.id, namePtr, container.rtpcId, container.crossfadeCurve.index) != 0;
      } finally {
        malloc.free(namePtr);
      }
    } catch (e) {
      return true;
    }
  }

  /// Add child to blend container
  bool middlewareBlendAddChild(int containerId, BlendChild child) {
    if (!_loaded) return false;
    try {
      final namePtr = child.name.toNativeUtf8();
      try {
        final fn = _lib.lookupFunction<
          Int32 Function(Uint32, Uint32, Pointer<Utf8>, Float, Float, Float),
          int Function(int, int, Pointer<Utf8>, double, double, double)
        >('middleware_blend_add_child');
        return fn(containerId, child.id, namePtr, child.rtpcStart, child.rtpcEnd, child.crossfadeWidth) != 0;
      } finally {
        malloc.free(namePtr);
      }
    } catch (e) {
      return true;
    }
  }

  /// Remove child from blend container
  bool middlewareBlendRemoveChild(int containerId, int childId) {
    if (!_loaded) return false;
    try {
      final fn = _lib.lookupFunction<Int32 Function(Uint32, Uint32), int Function(int, int)>('middleware_blend_remove_child');
      return fn(containerId, childId) != 0;
    } catch (e) {
      return true;
    }
  }

  /// Remove blend container
  bool middlewareRemoveBlendContainer(int containerId) {
    if (!_loaded) return false;
    try {
      final fn = _lib.lookupFunction<Int32 Function(Uint32), int Function(int)>('middleware_remove_blend_container');
      return fn(containerId) != 0;
    } catch (e) {
      return true;
    }
  }

  /// Create a random container
  bool middlewareCreateRandomContainer(RandomContainer container) {
    if (!_loaded) return false;
    try {
      final namePtr = container.name.toNativeUtf8();
      try {
        final fn = _lib.lookupFunction<
          Int32 Function(Uint32, Pointer<Utf8>, Uint32, Uint32),
          int Function(int, Pointer<Utf8>, int, int)
        >('middleware_create_random_container');
        return fn(container.id, namePtr, container.mode.index, container.avoidRepeatCount) != 0;
      } finally {
        malloc.free(namePtr);
      }
    } catch (e) {
      return true;
    }
  }

  /// Add child to random container
  bool middlewareRandomAddChild(int containerId, RandomChild child) {
    if (!_loaded) return false;
    try {
      final namePtr = child.name.toNativeUtf8();
      try {
        final fn = _lib.lookupFunction<
          Int32 Function(Uint32, Uint32, Pointer<Utf8>, Float, Float, Float, Float, Float),
          int Function(int, int, Pointer<Utf8>, double, double, double, double, double)
        >('middleware_random_add_child');
        return fn(containerId, child.id, namePtr, child.weight, child.pitchMin, child.pitchMax, child.volumeMin, child.volumeMax) != 0;
      } finally {
        malloc.free(namePtr);
      }
    } catch (e) {
      return true;
    }
  }

  /// Remove child from random container
  bool middlewareRandomRemoveChild(int containerId, int childId) {
    if (!_loaded) return false;
    try {
      final fn = _lib.lookupFunction<Int32 Function(Uint32, Uint32), int Function(int, int)>('middleware_random_remove_child');
      return fn(containerId, childId) != 0;
    } catch (e) {
      return true;
    }
  }

  /// Set global variation for random container
  bool middlewareRandomSetGlobalVariation(int containerId, {double pitchMin = 0, double pitchMax = 0, double volumeMin = 0, double volumeMax = 0}) {
    if (!_loaded) return false;
    try {
      final fn = _lib.lookupFunction<
        Int32 Function(Uint32, Float, Float, Float, Float),
        int Function(int, double, double, double, double)
      >('middleware_random_set_global_variation');
      return fn(containerId, pitchMin, pitchMax, volumeMin, volumeMax) != 0;
    } catch (e) {
      return true;
    }
  }

  /// Remove random container
  bool middlewareRemoveRandomContainer(int containerId) {
    if (!_loaded) return false;
    try {
      final fn = _lib.lookupFunction<Int32 Function(Uint32), int Function(int)>('middleware_remove_random_container');
      return fn(containerId) != 0;
    } catch (e) {
      return true;
    }
  }

  /// Create a sequence container
  bool middlewareCreateSequenceContainer(SequenceContainer container) {
    if (!_loaded) return false;
    try {
      final namePtr = container.name.toNativeUtf8();
      try {
        final fn = _lib.lookupFunction<
          Int32 Function(Uint32, Pointer<Utf8>, Uint32, Float),
          int Function(int, Pointer<Utf8>, int, double)
        >('middleware_create_sequence_container');
        return fn(container.id, namePtr, container.endBehavior.index, container.speed) != 0;
      } finally {
        malloc.free(namePtr);
      }
    } catch (e) {
      return true;
    }
  }

  /// Add step to sequence container
  bool middlewareSequenceAddStep(int containerId, SequenceStep step) {
    if (!_loaded) return false;
    try {
      final namePtr = step.childName.toNativeUtf8();
      try {
        final fn = _lib.lookupFunction<
          Int32 Function(Uint32, Uint32, Uint32, Pointer<Utf8>, Float, Float, Float, Float, Uint32),
          int Function(int, int, int, Pointer<Utf8>, double, double, double, double, int)
        >('middleware_sequence_add_step');
        return fn(containerId, step.index, step.childId, namePtr, step.delayMs, step.durationMs, step.fadeInMs, step.fadeOutMs, step.loopCount) != 0;
      } finally {
        malloc.free(namePtr);
      }
    } catch (e) {
      return true;
    }
  }

  /// Remove step from sequence container
  bool middlewareSequenceRemoveStep(int containerId, int stepIndex) {
    if (!_loaded) return false;
    try {
      final fn = _lib.lookupFunction<Int32 Function(Uint32, Uint32), int Function(int, int)>('middleware_sequence_remove_step');
      return fn(containerId, stepIndex) != 0;
    } catch (e) {
      return true;
    }
  }

  /// Remove sequence container
  bool middlewareRemoveSequenceContainer(int containerId) {
    if (!_loaded) return false;
    try {
      final fn = _lib.lookupFunction<Int32 Function(Uint32), int Function(int)>('middleware_remove_sequence_container');
      return fn(containerId) != 0;
    } catch (e) {
      return true;
    }
  }

  /// Add music segment
  bool middlewareAddMusicSegment(MusicSegment segment) {
    if (!_loaded) return false;
    try {
      final namePtr = segment.name.toNativeUtf8();
      try {
        final fn = _lib.lookupFunction<
          Int32 Function(Uint32, Pointer<Utf8>, Uint32, Float, Uint32, Uint32),
          int Function(int, Pointer<Utf8>, int, double, int, int)
        >('middleware_add_music_segment');
        return fn(segment.id, namePtr, segment.soundId, segment.tempo, segment.beatsPerBar, segment.durationBars) != 0;
      } finally {
        malloc.free(namePtr);
      }
    } catch (e) {
      return true;
    }
  }

  /// Add marker to music segment
  bool middlewareMusicSegmentAddMarker(int segmentId, MusicMarker marker) {
    if (!_loaded) return false;
    try {
      final namePtr = marker.name.toNativeUtf8();
      try {
        final fn = _lib.lookupFunction<
          Int32 Function(Uint32, Pointer<Utf8>, Float, Uint32),
          int Function(int, Pointer<Utf8>, double, int)
        >('middleware_music_segment_add_marker');
        return fn(segmentId, namePtr, marker.positionBars, marker.markerType.index) != 0;
      } finally {
        malloc.free(namePtr);
      }
    } catch (e) {
      return true;
    }
  }

  /// Remove music segment
  bool middlewareRemoveMusicSegment(int segmentId) {
    if (!_loaded) return false;
    try {
      final fn = _lib.lookupFunction<Int32 Function(Uint32), int Function(int)>('middleware_remove_music_segment');
      return fn(segmentId) != 0;
    } catch (e) {
      return true;
    }
  }

  /// Set current music segment
  bool middlewareSetMusicSegment(int segmentId) {
    if (!_loaded) return false;
    try {
      final fn = _lib.lookupFunction<Int32 Function(Uint32), int Function(int)>('middleware_set_music_segment');
      return fn(segmentId) != 0;
    } catch (e) {
      return true;
    }
  }

  /// Queue next music segment
  bool middlewareQueueMusicSegment(int segmentId) {
    if (!_loaded) return false;
    try {
      final fn = _lib.lookupFunction<Int32 Function(Uint32), int Function(int)>('middleware_queue_music_segment');
      return fn(segmentId) != 0;
    } catch (e) {
      return true;
    }
  }

  /// Set music bus ID
  void middlewareSetMusicBus(int busId) {
    if (!_loaded) return;
    try {
      final fn = _lib.lookupFunction<Void Function(Uint32), void Function(int)>('middleware_set_music_bus');
      fn(busId);
    } catch (e) {
      // Ignore
    }
  }

  /// Add stinger
  bool middlewareAddStinger(Stinger stinger) {
    if (!_loaded) return false;
    try {
      final namePtr = stinger.name.toNativeUtf8();
      try {
        final fn = _lib.lookupFunction<
          Int32 Function(Uint32, Pointer<Utf8>, Uint32, Uint32, Float, Float, Float, Float, Uint32, Int32),
          int Function(int, Pointer<Utf8>, int, int, double, double, double, double, int, int)
        >('middleware_add_stinger');
        return fn(
          stinger.id, namePtr, stinger.soundId, stinger.syncPoint.index,
          stinger.customGridBeats, stinger.musicDuckDb, stinger.duckAttackMs, stinger.duckReleaseMs,
          stinger.priority, stinger.canInterrupt ? 1 : 0
        ) != 0;
      } finally {
        malloc.free(namePtr);
      }
    } catch (e) {
      return true;
    }
  }

  /// Remove stinger
  bool middlewareRemoveStinger(int stingerId) {
    if (!_loaded) return false;
    try {
      final fn = _lib.lookupFunction<Int32 Function(Uint32), int Function(int)>('middleware_remove_stinger');
      return fn(stingerId) != 0;
    } catch (e) {
      return true;
    }
  }

  /// Add attenuation curve
  bool middlewareAddAttenuationCurve(AttenuationCurve curve) {
    if (!_loaded) return false;
    try {
      final namePtr = curve.name.toNativeUtf8();
      try {
        final fn = _lib.lookupFunction<
          Int32 Function(Uint32, Pointer<Utf8>, Uint32, Float, Float, Float, Float, Uint32),
          int Function(int, Pointer<Utf8>, int, double, double, double, double, int)
        >('middleware_add_attenuation_curve');
        return fn(
          curve.id, namePtr, curve.attenuationType.index,
          curve.inputMin, curve.inputMax, curve.outputMin, curve.outputMax,
          curve.curveShape.index
        ) != 0;
      } finally {
        malloc.free(namePtr);
      }
    } catch (e) {
      return true;
    }
  }

  /// Remove attenuation curve
  bool middlewareRemoveAttenuationCurve(int curveId) {
    if (!_loaded) return false;
    try {
      final fn = _lib.lookupFunction<Int32 Function(Uint32), int Function(int)>('middleware_remove_attenuation_curve');
      return fn(curveId) != 0;
    } catch (e) {
      return true;
    }
  }

  /// Set attenuation curve enabled
  bool middlewareSetAttenuationCurveEnabled(int curveId, bool enabled) {
    if (!_loaded) return false;
    try {
      final fn = _lib.lookupFunction<Int32 Function(Uint32, Int32), int Function(int, int)>('middleware_set_attenuation_curve_enabled');
      return fn(curveId, enabled ? 1 : 0) != 0;
    } catch (e) {
      return true;
    }
  }

  /// Evaluate attenuation curve
  double middlewareEvaluateAttenuationCurve(int curveId, double input) {
    if (!_loaded) return 0.0;
    try {
      final fn = _lib.lookupFunction<Float Function(Uint32, Float), double Function(int, double)>('middleware_evaluate_attenuation_curve');
      return fn(curveId, input);
    } catch (e) {
      return 0.0;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MIDDLEWARE ENUMS (match Rust exactly)
// ═══════════════════════════════════════════════════════════════════════════

/// Action type for middleware events
enum MiddlewareActionType {
  play,
  playAndContinue,
  stop,
  stopAll,
  pause,
  pauseAll,
  resume,
  resumeAll,
  breakLoop,
  mute,
  unmute,
  setVolume,
  setPitch,
  setLPF,
  setHPF,
  setBusVolume,
  setState,
  setSwitch,
  setRTPC,
  resetRTPC,
  seek,
  trigger,
  postEvent,
}

/// Action scope for middleware events
enum MiddlewareActionScope {
  global,
  gameObject,
  emitter,
  all,
  firstOnly,
  random,
}

/// Action priority for voice stealing
enum MiddlewareActionPriority {
  lowest,
  low,
  belowNormal,
  normal,
  aboveNormal,
  high,
  highest,
}

/// Fade curve type
enum MiddlewareFadeCurve {
  linear,
  log3,
  sine,
  log1,
  invSCurve,
  sCurve,
  exp1,
  exp3,
}

/// Mastering result from FFI
class MasteringResultFFI {
  final double inputLufs;
  final double outputLufs;
  final double inputPeak;
  final double outputPeak;
  final double appliedGain;
  final double peakReduction;
  final double qualityScore;
  final int detectedGenre;
  final int warningCount;

  const MasteringResultFFI({
    required this.inputLufs,
    required this.outputLufs,
    required this.inputPeak,
    required this.outputPeak,
    required this.appliedGain,
    required this.peakReduction,
    required this.qualityScore,
    required this.detectedGenre,
    required this.warningCount,
  });
}

/// Result from wave cache tile query
class WaveCacheTileResult {
  /// Mip level used for this query
  final int mipLevel;

  /// Samples per tile at this mip level
  final int samplesPerTile;

  /// Peak data: [min0, max0, min1, max1, ...]
  final Float32List peaks;

  /// Number of tiles
  int get tileCount => peaks.length ~/ 2;

  const WaveCacheTileResult({
    required this.mipLevel,
    required this.samplesPerTile,
    required this.peaks,
  });

  /// Get min/max pair at index
  (double min, double max) getTile(int index) {
    final i = index * 2;
    if (i >= peaks.length - 1) return (0.0, 0.0);
    return (peaks[i].toDouble(), peaks[i + 1].toDouble());
  }
}

/// Native plugin type enum (from Rust FFI)
enum NativePluginType {
  vst3(0),
  clap(1),
  audioUnit(2),
  lv2(3),
  internal(4);

  final int code;
  const NativePluginType(this.code);

  static NativePluginType fromCode(int code) {
    return NativePluginType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => NativePluginType.internal,
    );
  }
}

/// Native plugin category enum (from Rust FFI)
enum NativePluginCategory {
  effect(0),
  instrument(1),
  analyzer(2),
  utility(3),
  unknown(4);

  final int code;
  const NativePluginCategory(this.code);

  static NativePluginCategory fromCode(int code) {
    return NativePluginCategory.values.firstWhere(
      (e) => e.code == code,
      orElse: () => NativePluginCategory.unknown,
    );
  }
}

/// Native plugin information (from Rust FFI)
/// Use plugin_models.dart PluginInfo for UI display
class NativePluginInfo {
  final String id;
  final String name;
  final String vendor;
  final String version;
  final NativePluginType type;
  final NativePluginCategory category;
  final bool hasEditor;
  final String path;

  const NativePluginInfo({
    required this.id,
    required this.name,
    required this.vendor,
    this.version = '',
    required this.type,
    required this.category,
    required this.hasEditor,
    this.path = '',
  });

  /// Create from FFI data
  factory NativePluginInfo.fromFfi({
    required String id,
    required String name,
    required String vendor,
    required int typeCode,
    required int categoryCode,
    required bool hasEditor,
  }) {
    return NativePluginInfo(
      id: id,
      name: name,
      vendor: vendor,
      type: NativePluginType.fromCode(typeCode),
      category: NativePluginCategory.fromCode(categoryCode),
      hasEditor: hasEditor,
    );
  }

  /// Create from JSON (Rust FFI JSON response)
  factory NativePluginInfo.fromJson(Map<String, dynamic> json) {
    return NativePluginInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      vendor: json['vendor'] as String? ?? '',
      version: json['version'] as String? ?? '',
      type: NativePluginType.fromCode(json['type'] as int? ?? 4),
      category: NativePluginCategory.fromCode(json['category'] as int? ?? 4),
      hasEditor: json['hasEditor'] as bool? ?? json['has_editor'] as bool? ?? false,
      path: json['path'] as String? ?? '',
    );
  }

  /// Get icon for plugin type
  String get typeIcon {
    switch (type) {
      case NativePluginType.vst3:
        return 'VST3';
      case NativePluginType.clap:
        return 'CLAP';
      case NativePluginType.audioUnit:
        return 'AU';
      case NativePluginType.lv2:
        return 'LV2';
      case NativePluginType.internal:
        return 'RF';
    }
  }

  /// Get color for plugin type
  int get typeColor {
    switch (type) {
      case NativePluginType.vst3:
        return 0xFF4A9EFF; // Blue
      case NativePluginType.clap:
        return 0xFFFF9040; // Orange
      case NativePluginType.audioUnit:
        return 0xFF40FF90; // Green
      case NativePluginType.lv2:
        return 0xFFFF4060; // Red
      case NativePluginType.internal:
        return 0xFF40C8FF; // Cyan
    }
  }
}

/// Native plugin parameter information
class NativePluginParamInfo {
  final int id;
  final String name;
  final String unit;
  final double min;
  final double max;
  final double defaultValue;
  final double value;
  final bool automatable;

  const NativePluginParamInfo({
    required this.id,
    required this.name,
    this.unit = '',
    this.min = 0.0,
    this.max = 1.0,
    this.defaultValue = 0.0,
    this.value = 0.0,
    this.automatable = true,
  });

  /// Create from JSON (Rust FFI JSON response)
  factory NativePluginParamInfo.fromJson(Map<String, dynamic> json) {
    return NativePluginParamInfo(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? 'Param',
      unit: json['unit'] as String? ?? '',
      min: (json['min'] as num?)?.toDouble() ?? 0.0,
      max: (json['max'] as num?)?.toDouble() ?? 1.0,
      defaultValue: (json['default'] as num?)?.toDouble() ?? 0.0,
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
      automatable: json['automatable'] as bool? ?? true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO RESTORATION TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Restoration module settings
class RestorationSettings {
  final bool denoiseEnabled;
  final double denoiseStrength;
  final bool declickEnabled;
  final double declickSensitivity;
  final bool declipEnabled;
  final double declipThreshold;
  final bool dehumEnabled;
  final double dehumFrequency;
  final int dehumHarmonics;
  final bool dereverbEnabled;
  final double dereverbAmount;

  const RestorationSettings({
    required this.denoiseEnabled,
    required this.denoiseStrength,
    required this.declickEnabled,
    required this.declickSensitivity,
    required this.declipEnabled,
    required this.declipThreshold,
    required this.dehumEnabled,
    required this.dehumFrequency,
    required this.dehumHarmonics,
    required this.dereverbEnabled,
    required this.dereverbAmount,
  });

  /// Default settings (all disabled)
  factory RestorationSettings.defaults() => const RestorationSettings(
    denoiseEnabled: false,
    denoiseStrength: 50.0,
    declickEnabled: false,
    declickSensitivity: 50.0,
    declipEnabled: false,
    declipThreshold: -0.1,
    dehumEnabled: false,
    dehumFrequency: 50.0,
    dehumHarmonics: 4,
    dereverbEnabled: false,
    dereverbAmount: 50.0,
  );

  /// Create copy with modifications
  RestorationSettings copyWith({
    bool? denoiseEnabled,
    double? denoiseStrength,
    bool? declickEnabled,
    double? declickSensitivity,
    bool? declipEnabled,
    double? declipThreshold,
    bool? dehumEnabled,
    double? dehumFrequency,
    int? dehumHarmonics,
    bool? dereverbEnabled,
    double? dereverbAmount,
  }) {
    return RestorationSettings(
      denoiseEnabled: denoiseEnabled ?? this.denoiseEnabled,
      denoiseStrength: denoiseStrength ?? this.denoiseStrength,
      declickEnabled: declickEnabled ?? this.declickEnabled,
      declickSensitivity: declickSensitivity ?? this.declickSensitivity,
      declipEnabled: declipEnabled ?? this.declipEnabled,
      declipThreshold: declipThreshold ?? this.declipThreshold,
      dehumEnabled: dehumEnabled ?? this.dehumEnabled,
      dehumFrequency: dehumFrequency ?? this.dehumFrequency,
      dehumHarmonics: dehumHarmonics ?? this.dehumHarmonics,
      dereverbEnabled: dereverbEnabled ?? this.dereverbEnabled,
      dereverbAmount: dereverbAmount ?? this.dereverbAmount,
    );
  }
}

/// Restoration analysis result
class RestorationAnalysis {
  final double noiseFloorDb;
  final double clicksPerSecond;
  final double clippingPercent;
  final bool humDetected;
  final double humFrequency;
  final double humLevelDb;
  final double reverbTailSeconds;
  final double qualityScore;

  const RestorationAnalysis({
    required this.noiseFloorDb,
    required this.clicksPerSecond,
    required this.clippingPercent,
    required this.humDetected,
    required this.humFrequency,
    required this.humLevelDb,
    required this.reverbTailSeconds,
    required this.qualityScore,
  });

  /// Check if denoise is recommended
  bool get needsDenoise => noiseFloorDb > -50.0;

  /// Check if declick is recommended
  bool get needsDeclick => clicksPerSecond > 5.0;

  /// Check if declip is recommended
  bool get needsDeclip => clippingPercent > 0.1;

  /// Check if dehum is recommended
  bool get needsDehum => humDetected && humLevelDb > -50.0;

  /// Check if dereverb is recommended
  bool get needsDereverb => reverbTailSeconds > 1.0;

  /// Get quality grade
  String get qualityGrade {
    if (qualityScore >= 90) return 'Excellent';
    if (qualityScore >= 75) return 'Good';
    if (qualityScore >= 50) return 'Fair';
    if (qualityScore >= 25) return 'Poor';
    return 'Bad';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ML/AI PROCESSING TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// ML model information
class MlModelInfo {
  final int index;
  final String name;
  final bool isAvailable;
  final int sizeMb;

  const MlModelInfo({
    required this.index,
    required this.name,
    required this.isAvailable,
    required this.sizeMb,
  });

  /// Human-readable size
  String get sizeString {
    if (sizeMb >= 1000) {
      return '${(sizeMb / 1000).toStringAsFixed(1)} GB';
    }
    return '$sizeMb MB';
  }
}

/// ML stem types for separation
enum MlStemType {
  vocals(1),
  drums(2),
  bass(4),
  other(8);

  final int mask;
  const MlStemType(this.mask);

  /// Combine multiple stems into mask
  static int combineMask(List<MlStemType> stems) {
    return stems.fold(0, (mask, stem) => mask | stem.mask);
  }
}

/// ML execution provider
enum MlExecutionProvider {
  cpu(0),
  cuda(1),
  coreMl(2),
  tensorRt(3);

  final int code;
  const MlExecutionProvider(this.code);
}

// ═══════════════════════════════════════════════════════════════════════════
// LUA SCRIPTING TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Script info returned from FFI
class ScriptInfo {
  final String name;
  final String description;

  const ScriptInfo({
    required this.name,
    this.description = '',
  });
}

/// Script action types from Lua execution
enum ScriptActionType {
  play,
  stop,
  record,
  setPlayhead,
  setLoop,
  createTrack,
  deleteTrack,
  muteTrack,
  soloTrack,
  setTrackVolume,
  setTrackPan,
  cut,
  copy,
  paste,
  delete,
  undo,
  redo,
  save,
  unknown,
}

/// Parsed script action from JSON
class ScriptAction {
  final ScriptActionType type;
  final Map<String, dynamic> data;

  const ScriptAction({
    required this.type,
    this.data = const {},
  });

  /// Parse from JSON string
  factory ScriptAction.fromJson(String json) {
    try {
      final map = Map<String, dynamic>.from(
        // ignore: avoid_dynamic_calls
        (const JsonDecoder()).convert(json) as Map,
      );
      final typeStr = map['type'] as String? ?? 'unknown';
      final type = _parseActionType(typeStr);
      return ScriptAction(type: type, data: map);
    } catch (e) {
      return const ScriptAction(type: ScriptActionType.unknown);
    }
  }

  static ScriptActionType _parseActionType(String type) {
    switch (type) {
      case 'play': return ScriptActionType.play;
      case 'stop': return ScriptActionType.stop;
      case 'record': return ScriptActionType.record;
      case 'set_playhead': return ScriptActionType.setPlayhead;
      case 'set_loop': return ScriptActionType.setLoop;
      case 'create_track': return ScriptActionType.createTrack;
      case 'delete_track': return ScriptActionType.deleteTrack;
      case 'mute_track': return ScriptActionType.muteTrack;
      case 'solo_track': return ScriptActionType.soloTrack;
      case 'set_track_volume': return ScriptActionType.setTrackVolume;
      case 'set_track_pan': return ScriptActionType.setTrackPan;
      case 'cut': return ScriptActionType.cut;
      case 'copy': return ScriptActionType.copy;
      case 'paste': return ScriptActionType.paste;
      case 'delete': return ScriptActionType.delete;
      case 'undo': return ScriptActionType.undo;
      case 'redo': return ScriptActionType.redo;
      case 'save': return ScriptActionType.save;
      default: return ScriptActionType.unknown;
    }
  }
}
