/// ReelForge Native FFI Bindings
///
/// Direct FFI bindings to Rust engine C API.
/// Uses dart:ffi for low-level native function calls.

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'engine_api.dart' show TruePeak8xData, PsrData, CrestFactorData, PsychoacousticData;

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
    // Absolute paths for macOS development
    '/Users/vanvinklstudio/Desktop/reelforge-standalone/target/release/$libName',
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

typedef EngineSetTrackArmedNative = Int32 Function(Uint64 trackId, Int32 armed);
typedef EngineSetTrackArmedDart = int Function(int trackId, int armed);

typedef EngineSetTrackVolumeNative = Int32 Function(Uint64 trackId, Double volume);
typedef EngineSetTrackVolumeDart = int Function(int trackId, double volume);

typedef EngineSetTrackPanNative = Int32 Function(Uint64 trackId, Double pan);
typedef EngineSetTrackPanDart = int Function(int trackId, double pan);

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

// Insert Effects
typedef InsertCreateChainNative = Void Function(Uint64 trackId);
typedef InsertCreateChainDart = void Function(int trackId);

typedef InsertRemoveChainNative = Void Function(Uint64 trackId);
typedef InsertRemoveChainDart = void Function(int trackId);

typedef InsertSetBypassNative = Void Function(Uint64 trackId, Uint32 slot, Int32 bypass);
typedef InsertSetBypassDart = void Function(int trackId, int slot, int bypass);

typedef InsertSetMixNative = Void Function(Uint64 trackId, Uint32 slot, Double mix);
typedef InsertSetMixDart = void Function(int trackId, int slot, double mix);

typedef InsertBypassAllNative = Void Function(Uint64 trackId, Int32 bypass);
typedef InsertBypassAllDart = void Function(int trackId, int bypass);

typedef InsertGetTotalLatencyNative = Uint32 Function(Uint64 trackId);
typedef InsertGetTotalLatencyDart = int Function(int trackId);

// Transient Detection
typedef TransientDetectNative = Uint32 Function(Pointer<Double> samples, Uint32 length, Double sampleRate, Double sensitivity, Uint8 algorithm, Pointer<Uint64> outPositions, Uint32 outMaxCount);
typedef TransientDetectDart = int Function(Pointer<Double> samples, int length, double sampleRate, double sensitivity, int algorithm, Pointer<Uint64> outPositions, int outMaxCount);

// Pitch Detection
typedef PitchDetectNative = Double Function(Pointer<Double> samples, Uint32 length, Double sampleRate);
typedef PitchDetectDart = double Function(Pointer<Double> samples, int length, double sampleRate);

typedef PitchDetectMidiNative = Int32 Function(Pointer<Double> samples, Uint32 length, Double sampleRate);
typedef PitchDetectMidiDart = int Function(Pointer<Double> samples, int length, double sampleRate);

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
  late final EngineSetTrackArmedDart _setTrackArmed;
  late final EngineSetTrackVolumeDart _setTrackVolume;
  late final EngineSetTrackPanDart _setTrackPan;
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
  late final EngineGetClipDurationDart _getClipDuration;
  late final EngineGetClipSourceDurationDart _getClipSourceDuration;
  late final EngineGetAudioFileDurationDart _getAudioFileDuration;

  late final EngineGetWaveformPeaksDart _getWaveformPeaks;
  late final EngineGetWaveformLodLevelsDart _getWaveformLodLevels;

  late final EngineSetLoopRegionDart _setLoopRegion;
  late final EngineSetLoopEnabledDart _setLoopEnabled;

  late final EngineAddMarkerDart _addMarker;
  late final EngineDeleteMarkerDart _deleteMarker;

  late final EngineCreateCrossfadeDart _createCrossfade;
  late final EngineDeleteCrossfadeDart _deleteCrossfade;

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
  late final EngineGetPositionDart _getPosition;
  late final EngineGetPlaybackStateDart _getPlaybackState;
  late final EngineIsPlayingDart _isPlaying;
  late final EngineSetMasterVolumeDart _setMasterVolume;
  late final EngineGetMasterVolumeDart _getMasterVolume;
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

  // Insert Effects
  late final InsertCreateChainDart _insertCreateChain;
  late final InsertRemoveChainDart _insertRemoveChain;
  late final InsertSetBypassDart _insertSetBypass;
  late final InsertSetMixDart _insertSetMix;
  late final InsertBypassAllDart _insertBypassAll;
  late final InsertGetTotalLatencyDart _insertGetTotalLatency;

  // Transient Detection
  late final TransientDetectDart _transientDetect;

  // Pitch Detection
  late final PitchDetectDart _pitchDetect;
  late final PitchDetectMidiDart _pitchDetectMidi;

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
    _setTrackArmed = _lib.lookupFunction<EngineSetTrackArmedNative, EngineSetTrackArmedDart>('engine_set_track_armed');
    _setTrackVolume = _lib.lookupFunction<EngineSetTrackVolumeNative, EngineSetTrackVolumeDart>('engine_set_track_volume');
    _setTrackPan = _lib.lookupFunction<EngineSetTrackPanNative, EngineSetTrackPanDart>('engine_set_track_pan');
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
    _getClipDuration = _lib.lookupFunction<EngineGetClipDurationNative, EngineGetClipDurationDart>('engine_get_clip_duration');
    _getClipSourceDuration = _lib.lookupFunction<EngineGetClipSourceDurationNative, EngineGetClipSourceDurationDart>('engine_get_clip_source_duration');
    _getAudioFileDuration = _lib.lookupFunction<EngineGetAudioFileDurationNative, EngineGetAudioFileDurationDart>('engine_get_audio_file_duration');

    _getWaveformPeaks = _lib.lookupFunction<EngineGetWaveformPeaksNative, EngineGetWaveformPeaksDart>('engine_get_waveform_peaks');
    _getWaveformLodLevels = _lib.lookupFunction<EngineGetWaveformLodLevelsNative, EngineGetWaveformLodLevelsDart>('engine_get_waveform_lod_levels');

    _setLoopRegion = _lib.lookupFunction<EngineSetLoopRegionNative, EngineSetLoopRegionDart>('engine_set_loop_region');
    _setLoopEnabled = _lib.lookupFunction<EngineSetLoopEnabledNative, EngineSetLoopEnabledDart>('engine_set_loop_enabled');

    _addMarker = _lib.lookupFunction<EngineAddMarkerNative, EngineAddMarkerDart>('engine_add_marker');
    _deleteMarker = _lib.lookupFunction<EngineDeleteMarkerNative, EngineDeleteMarkerDart>('engine_delete_marker');

    _createCrossfade = _lib.lookupFunction<EngineCreateCrossfadeNative, EngineCreateCrossfadeDart>('engine_create_crossfade');
    _deleteCrossfade = _lib.lookupFunction<EngineDeleteCrossfadeNative, EngineDeleteCrossfadeDart>('engine_delete_crossfade');

    _freeString = _lib.lookupFunction<EngineFreeStringNative, EngineFreeStringDart>('engine_free_string');
    _clearAll = _lib.lookupFunction<EngineClearAllNative, EngineClearAllDart>('engine_clear_all');

    _snapToGrid = _lib.lookupFunction<EngineSnapToGridNative, EngineSnapToGridDart>('engine_snap_to_grid');
    _snapToEvent = _lib.lookupFunction<EngineSnapToEventNative, EngineSnapToEventDart>('engine_snap_to_event');

    // Transport
    _play = _lib.lookupFunction<EnginePlayNative, EnginePlayDart>('engine_play');
    _pause = _lib.lookupFunction<EnginePauseNative, EnginePauseDart>('engine_pause');
    _stop = _lib.lookupFunction<EngineStopNative, EngineStopDart>('engine_stop');
    _seek = _lib.lookupFunction<EngineSeekNative, EngineSeekDart>('engine_seek');
    _getPosition = _lib.lookupFunction<EngineGetPositionNative, EngineGetPositionDart>('engine_get_position');
    _getPlaybackState = _lib.lookupFunction<EngineGetPlaybackStateNative, EngineGetPlaybackStateDart>('engine_get_playback_state');
    _isPlaying = _lib.lookupFunction<EngineIsPlayingNative, EngineIsPlayingDart>('engine_is_playing');
    _setMasterVolume = _lib.lookupFunction<EngineSetMasterVolumeNative, EngineSetMasterVolumeDart>('engine_set_master_volume');
    _getMasterVolume = _lib.lookupFunction<EngineGetMasterVolumeNative, EngineGetMasterVolumeDart>('engine_get_master_volume');
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

    // Insert Effects
    _insertCreateChain = _lib.lookupFunction<InsertCreateChainNative, InsertCreateChainDart>('insert_create_chain');
    _insertRemoveChain = _lib.lookupFunction<InsertRemoveChainNative, InsertRemoveChainDart>('insert_remove_chain');
    _insertSetBypass = _lib.lookupFunction<InsertSetBypassNative, InsertSetBypassDart>('insert_set_bypass');
    _insertSetMix = _lib.lookupFunction<InsertSetMixNative, InsertSetMixDart>('insert_set_mix');
    _insertBypassAll = _lib.lookupFunction<InsertBypassAllNative, InsertBypassAllDart>('insert_bypass_all');
    _insertGetTotalLatency = _lib.lookupFunction<InsertGetTotalLatencyNative, InsertGetTotalLatencyDart>('insert_get_total_latency');

    // Transient Detection
    _transientDetect = _lib.lookupFunction<TransientDetectNative, TransientDetectDart>('transient_detect');

    // Pitch Detection
    _pitchDetect = _lib.lookupFunction<PitchDetectNative, PitchDetectDart>('pitch_detect');
    _pitchDetectMidi = _lib.lookupFunction<PitchDetectMidiNative, PitchDetectMidiDart>('pitch_detect_midi');
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

  /// Set track solo state
  bool setTrackSolo(int trackId, bool solo) {
    if (!_loaded) return false;
    return _setTrackSolo(trackId, solo ? 1 : 0) != 0;
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
  bool setTrackPan(int trackId, double pan) {
    if (!_loaded) return false;
    return _setTrackPan(trackId, pan) != 0;
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

  /// Clear all engine state
  void clearAll() {
    if (!_loaded) return;
    _clearAll();
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
  // ROUTING API
  // ============================================================

  late final _routingCreateBus = _lib.lookupFunction<
      Uint32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('routing_create_bus');

  late final _routingCreateAux = _lib.lookupFunction<
      Uint32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('routing_create_aux');

  late final _routingCreateAudio = _lib.lookupFunction<
      Uint32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('routing_create_audio');

  late final _routingDeleteChannel = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('routing_delete_channel');

  late final _routingSetOutputMaster = _lib.lookupFunction<
      Int32 Function(Uint32),
      int Function(int)>('routing_set_output_master');

  late final _routingSetOutputChannel = _lib.lookupFunction<
      Int32 Function(Uint32, Uint32),
      int Function(int, int)>('routing_set_output_channel');

  late final _routingAddSend = _lib.lookupFunction<
      Int32 Function(Uint32, Uint32, Int32),
      int Function(int, int, int)>('routing_add_send');

  late final _routingRemoveSend = _lib.lookupFunction<
      Int32 Function(Uint32, UnsignedLong),
      int Function(int, int)>('routing_remove_send');

  late final _routingSetFader = _lib.lookupFunction<
      Int32 Function(Uint32, Double),
      int Function(int, double)>('routing_set_fader');

  late final _routingGetFader = _lib.lookupFunction<
      Double Function(Uint32),
      double Function(int)>('routing_get_fader');

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
      UnsignedLong Function(),
      int Function()>('routing_get_channel_count');

  late final _routingGetAllChannels = _lib.lookupFunction<
      UnsignedLong Function(Pointer<Uint32>, UnsignedLong),
      int Function(Pointer<Uint32>, int)>('routing_get_all_channels');

  late final _routingGetChannelKind = _lib.lookupFunction<
      Uint8 Function(Uint32),
      int Function(int)>('routing_get_channel_kind');

  late final _routingSetName = _lib.lookupFunction<
      Int32 Function(Uint32, Pointer<Utf8>),
      int Function(int, Pointer<Utf8>)>('routing_set_name');

  late final _routingSetColor = _lib.lookupFunction<
      Int32 Function(Uint32, Uint32),
      int Function(int, int)>('routing_set_color');

  late final _routingProcess = _lib.lookupFunction<
      Void Function(),
      void Function()>('routing_process');

  /// Create a bus channel, returns channel ID
  int routingCreateBus(String name) {
    if (!_loaded) return 0;
    final namePtr = name.toNativeUtf8();
    try {
      return _routingCreateBus(namePtr);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Create an aux channel, returns channel ID
  int routingCreateAux(String name) {
    if (!_loaded) return 0;
    final namePtr = name.toNativeUtf8();
    try {
      return _routingCreateAux(namePtr);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Create an audio channel, returns channel ID
  int routingCreateAudio(String name) {
    if (!_loaded) return 0;
    final namePtr = name.toNativeUtf8();
    try {
      return _routingCreateAudio(namePtr);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Delete a channel
  bool routingDeleteChannel(int channelId) {
    if (!_loaded) return false;
    return _routingDeleteChannel(channelId) == 1;
  }

  /// Set channel output to master
  bool routingSetOutputMaster(int channelId) {
    if (!_loaded) return false;
    return _routingSetOutputMaster(channelId) == 1;
  }

  /// Set channel output to another channel
  bool routingSetOutputChannel(int fromId, int toId) {
    if (!_loaded) return false;
    return _routingSetOutputChannel(fromId, toId) == 1;
  }

  /// Add a send from one channel to another
  bool routingAddSend(int fromId, int toId, {bool preFader = false}) {
    if (!_loaded) return false;
    return _routingAddSend(fromId, toId, preFader ? 1 : 0) == 1;
  }

  /// Remove a send by index
  bool routingRemoveSend(int channelId, int sendIndex) {
    if (!_loaded) return false;
    return _routingRemoveSend(channelId, sendIndex) == 1;
  }

  /// Set channel fader level (dB)
  bool routingSetFader(int channelId, double db) {
    if (!_loaded) return false;
    return _routingSetFader(channelId, db) == 1;
  }

  /// Get channel fader level (dB)
  double routingGetFader(int channelId) {
    if (!_loaded) return 0.0;
    return _routingGetFader(channelId);
  }

  /// Set channel pan (-1.0 to 1.0)
  bool routingSetPan(int channelId, double pan) {
    if (!_loaded) return false;
    return _routingSetPan(channelId, pan) == 1;
  }

  /// Set channel mute
  bool routingSetMute(int channelId, bool muted) {
    if (!_loaded) return false;
    return _routingSetMute(channelId, muted ? 1 : 0) == 1;
  }

  /// Set channel solo
  bool routingSetSolo(int channelId, bool solo) {
    if (!_loaded) return false;
    return _routingSetSolo(channelId, solo ? 1 : 0) == 1;
  }

  /// Get total channel count
  int routingGetChannelCount() {
    if (!_loaded) return 0;
    return _routingGetChannelCount();
  }

  /// Get all channel IDs
  List<int> routingGetAllChannels({int maxCount = 128}) {
    if (!_loaded) return [];
    final outIds = calloc<Uint32>(maxCount);
    try {
      final count = _routingGetAllChannels(outIds, maxCount);
      return List.generate(count, (i) => outIds[i]);
    } finally {
      calloc.free(outIds);
    }
  }

  /// Get channel kind (0=Audio, 1=Bus, 2=Aux, 3=Master)
  int routingGetChannelKind(int channelId) {
    if (!_loaded) return 0;
    return _routingGetChannelKind(channelId);
  }

  /// Set channel name
  bool routingSetName(int channelId, String name) {
    if (!_loaded) return false;
    final namePtr = name.toNativeUtf8();
    try {
      return _routingSetName(channelId, namePtr) == 1;
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Set channel color
  bool routingSetColor(int channelId, int color) {
    if (!_loaded) return false;
    return _routingSetColor(channelId, color) == 1;
  }

  /// Process routing graph (called each audio cycle)
  void routingProcess() {
    if (!_loaded) return;
    _routingProcess();
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

  /// Set output gain (-24 to +24 dB)
  bool proEqSetOutputGain(int trackId, double gainDb) =>
      _proEqSetOutputGain(trackId, gainDb.clamp(-24.0, 24.0)) == 1;

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

  // ═══════════════════════════════════════════════════════════════════════════════
  // ADVANCED METERING (8x True Peak, PSR, Psychoacoustic)
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Get 8x True Peak data
  TruePeak8xData advancedGetTruePeak8x() {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
    // For now, return empty data
    return TruePeak8xData.empty();
  }

  /// Get PSR data
  PsrData advancedGetPsr() {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
    return PsrData.empty();
  }

  /// Get Crest Factor data
  CrestFactorData advancedGetCrestFactor() {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
    return CrestFactorData.empty();
  }

  /// Get Psychoacoustic data
  PsychoacousticData advancedGetPsychoacoustic() {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
    return PsychoacousticData.empty();
  }

  /// Initialize advanced meters
  void advancedInitMeters(double sampleRate) {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
  }

  /// Reset all advanced meters
  void advancedResetAll() {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // AUDIO POOL
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Get list of audio files in the pool
  String audioPoolList() {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
    return '[]';
  }

  /// Import audio file to pool
  bool audioPoolImport(String path) {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
    return true;
  }

  /// Remove audio file from pool
  bool audioPoolRemove(String fileId) {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
    return true;
  }

  /// Play audio file preview
  void audioPoolPlayPreview(String fileId) {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
  }

  /// Stop audio file preview
  void audioPoolStopPreview() {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
  }

  /// Locate missing audio file
  bool audioPoolLocate(String fileId, String newPath) {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // EXPORT PRESETS
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Get list of export presets
  String exportPresetsList() {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
    return '[]';
  }

  /// Save export preset
  bool exportPresetSave(String presetJson) {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
    return true;
  }

  /// Delete export preset
  bool exportPresetDelete(String presetId) {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
    return true;
  }

  /// Get default export path
  String getDefaultExportPath() {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
    return '';
  }

  /// Select export folder (opens native dialog)
  Future<String?> selectExportFolder() async {
    // TODO: Implement FFI binding when flutter_rust_bridge regenerates
    return null;
  }
}

