/// ReelForge Native FFI Bindings
///
/// Direct FFI bindings to Rust engine C API.
/// Uses dart:ffi for low-level native function calls.

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// NATIVE LIBRARY LOADING
// ═══════════════════════════════════════════════════════════════════════════

DynamicLibrary? _cachedLib;

/// Load the native library
DynamicLibrary _loadNativeLibrary() {
  if (_cachedLib != null) return _cachedLib!;

  String libName;
  if (Platform.isLinux) {
    libName = 'librf_engine.so';
  } else if (Platform.isMacOS) {
    libName = 'librf_engine.dylib';
  } else if (Platform.isWindows) {
    libName = 'rf_engine.dll';
  } else {
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  // Try multiple paths
  final paths = [
    libName,
    'lib/$libName',
    '../target/release/$libName',
    '../target/debug/$libName',
    '../../target/release/$libName',
    '../../target/debug/$libName',
  ];

  for (final path in paths) {
    try {
      _cachedLib = DynamicLibrary.open(path);
      return _cachedLib!;
    } catch (_) {
      continue;
    }
  }

  throw Exception('Could not load native library: $libName');
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

typedef EngineSetTrackVolumeNative = Int32 Function(Uint64 trackId, Double volume);
typedef EngineSetTrackVolumeDart = int Function(int trackId, double volume);

typedef EngineSetTrackPanNative = Int32 Function(Uint64 trackId, Double pan);
typedef EngineSetTrackPanDart = int Function(int trackId, double pan);

typedef EngineGetTrackCountNative = IntPtr Function();
typedef EngineGetTrackCountDart = int Function();

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

// Memory stats
typedef EngineGetMemoryUsageNative = Float Function();
typedef EngineGetMemoryUsageDart = double Function();

// Metering (real-time peak/RMS from audio thread)
typedef EngineGetPeakMetersNative = Void Function(Pointer<Double> outLeft, Pointer<Double> outRight);
typedef EngineGetPeakMetersDart = void Function(Pointer<Double> outLeft, Pointer<Double> outRight);

typedef EngineGetRmsMetersNative = Void Function(Pointer<Double> outLeft, Pointer<Double> outRight);
typedef EngineGetRmsMetersDart = void Function(Pointer<Double> outLeft, Pointer<Double> outRight);

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
  late final EngineSetTrackVolumeDart _setTrackVolume;
  late final EngineSetTrackPanDart _setTrackPan;
  late final EngineGetTrackCountDart _getTrackCount;

  late final EngineImportAudioDart _importAudio;

  late final EngineAddClipDart _addClip;
  late final EngineMoveClipDart _moveClip;
  late final EngineResizeClipDart _resizeClip;
  late final EngineSplitClipDart _splitClip;
  late final EngineDuplicateClipDart _duplicateClip;
  late final EngineDeleteClipDart _deleteClip;
  late final EngineSetClipGainDart _setClipGain;

  late final EngineGetWaveformPeaksDart _getWaveformPeaks;
  late final EngineGetWaveformLodLevelsDart _getWaveformLodLevels;

  late final EngineSetLoopRegionDart _setLoopRegion;
  late final EngineSetLoopEnabledDart _setLoopEnabled;

  late final EngineAddMarkerDart _addMarker;
  late final EngineDeleteMarkerDart _deleteMarker;

  late final EngineCreateCrossfadeDart _createCrossfade;
  late final EngineDeleteCrossfadeDart _deleteCrossfade;

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

  // Memory
  late final EngineGetMemoryUsageDart _getMemoryUsage;

  // Metering
  late final EngineGetPeakMetersDart _getPeakMeters;
  late final EngineGetRmsMetersDart _getRmsMeters;

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
    _setTrackVolume = _lib.lookupFunction<EngineSetTrackVolumeNative, EngineSetTrackVolumeDart>('engine_set_track_volume');
    _setTrackPan = _lib.lookupFunction<EngineSetTrackPanNative, EngineSetTrackPanDart>('engine_set_track_pan');
    _getTrackCount = _lib.lookupFunction<EngineGetTrackCountNative, EngineGetTrackCountDart>('engine_get_track_count');

    _importAudio = _lib.lookupFunction<EngineImportAudioNative, EngineImportAudioDart>('engine_import_audio');

    _addClip = _lib.lookupFunction<EngineAddClipNative, EngineAddClipDart>('engine_add_clip');
    _moveClip = _lib.lookupFunction<EngineMoveClipNative, EngineMoveClipDart>('engine_move_clip');
    _resizeClip = _lib.lookupFunction<EngineResizeClipNative, EngineResizeClipDart>('engine_resize_clip');
    _splitClip = _lib.lookupFunction<EngineSplitClipNative, EngineSplitClipDart>('engine_split_clip');
    _duplicateClip = _lib.lookupFunction<EngineDuplicateClipNative, EngineDuplicateClipDart>('engine_duplicate_clip');
    _deleteClip = _lib.lookupFunction<EngineDeleteClipNative, EngineDeleteClipDart>('engine_delete_clip');
    _setClipGain = _lib.lookupFunction<EngineSetClipGainNative, EngineSetClipGainDart>('engine_set_clip_gain');

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

    // Memory
    _getMemoryUsage = _lib.lookupFunction<EngineGetMemoryUsageNative, EngineGetMemoryUsageDart>('engine_get_memory_usage');

    // Metering
    _getPeakMeters = _lib.lookupFunction<EngineGetPeakMetersNative, EngineGetPeakMetersDart>('engine_get_peak_meters');
    _getRmsMeters = _lib.lookupFunction<EngineGetRmsMetersNative, EngineGetRmsMetersDart>('engine_get_rms_meters');

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

  /// Set track volume (0.0 - 1.5)
  bool setTrackVolume(int trackId, double volume) {
    if (!_loaded) return false;
    return _setTrackVolume(trackId, volume) != 0;
  }

  /// Set track pan (-1.0 to 1.0)
  bool setTrackPan(int trackId, double pan) {
    if (!_loaded) return false;
    return _setTrackPan(trackId, pan) != 0;
  }

  /// Get track count
  int getTrackCount() {
    if (!_loaded) return 0;
    return _getTrackCount();
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
}
