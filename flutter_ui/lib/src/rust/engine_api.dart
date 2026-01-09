/// ReelForge Engine API
///
/// High-level Dart API for the Rust audio engine.

import 'dart:async';
import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'native_ffi.dart';

/// Audio Engine API
///
/// Singleton wrapper for all engine functionality.
class EngineApi {
  static EngineApi? _instance;
  static EngineApi get instance => _instance ??= EngineApi._();

  bool _initialized = false;
  bool _audioStarted = false; // Track if real audio playback is running
  final NativeFFI _ffi = NativeFFI.instance;

  // State
  TransportState _transport = TransportState.empty();
  MeteringState _metering = MeteringState.empty();
  ProjectInfo _project = ProjectInfo.empty();

  // Active buses for metering (index -> activity level 0-1)
  // 0=Master, 1=Music, 2=SFX, 3=Voice, 4=Ambience, 5=UI
  final Map<int, double> _activeBuses = {};


  // Streams
  final _transportController = StreamController<TransportState>.broadcast();
  final _meteringController = StreamController<MeteringState>.broadcast();

  Timer? _updateTimer;
  int _meteringFrameCounter = 0; // For 30fps metering (every 2nd frame)

  EngineApi._();

  /// Initialize the engine
  Future<bool> init({
    int sampleRate = 48000,
    int blockSize = 256,
    int numBuses = 6,
  }) async {
    if (_initialized) return true;

    // Load native library
    if (!_ffi.tryLoad()) {
      throw Exception('[Engine] FATAL: Native library failed to load. Cannot continue.');
    }
    print('[Engine] Native FFI loaded successfully');

    _initialized = true;

    // Start real audio playback
    try {
      await startAudioPlayback();
    } catch (e) {
      print('[Engine] Audio playback init failed: $e');
      rethrow;
    }

    // Start update timer for metering/transport
    _startUpdateTimer();

    return true;
  }

  /// Start real audio playback engine
  Future<void> startAudioPlayback() async {
    if (_audioStarted) return;

    try {
        _ffi.startPlayback();
        print('[Engine] Audio playback started via FFI');
      } else {
        print('[Engine] Audio playback ready (mock mode)');
      _audioStarted = true;
    } catch (e) {
      print('[Engine] Audio playback failed: $e');
      rethrow;
    }
  }

  /// Stop real audio playback engine
  Future<void> stopAudioPlayback() async {
    if (!_audioStarted) return;

    try {
        _ffi.stopPlayback();
        print('[Engine] Audio playback stopped via FFI');
      _audioStarted = false;
    } catch (e) {
      print('[Engine] Audio stop failed: $e');
    }
  }

  /// Check if real audio is active
  bool get isAudioActive => _audioStarted;

  /// Shutdown the engine
  void shutdown() {
    stopAudioPlayback();
    _updateTimer?.cancel();
    _initialized = false;
    _transportController.close();
    _meteringController.close();
  }

  /// Check if engine is running
  bool get isRunning => _initialized;

  // ═══════════════════════════════════════════════════════════════════════════
  // BUS ROUTING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set active buses for metering based on which tracks have clips
  /// busIndex: 0=Master, 1=Music, 2=SFX, 3=Voice, 4=Ambience, 5=UI
  /// activity: 0.0-1.0 level of activity (0 = silent, 1 = full)
  void setActiveBuses(Map<int, double> buses) {
    _activeBuses.clear();
    _activeBuses.addAll(buses);
  }

  /// Set single bus activity
  void setBusActivity(int busIndex, double activity) {
    if (activity > 0) {
      _activeBuses[busIndex] = activity.clamp(0.0, 1.0);
    } else {
      _activeBuses.remove(busIndex);
    }
  }

  /// Clear all bus activity (silence)
  void clearActiveBuses() {
    _activeBuses.clear();
  }

  /// Get active buses
  Map<int, double> get activeBuses => Map.unmodifiable(_activeBuses);

  // ═══════════════════════════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set master volume (0.0 - 1.5, where 1.0 = 0dB)
  void setMasterVolume(double volume) {
      final db = volume <= 0.0001 ? -60.0 : 20.0 * log(volume) / ln10;
      _ffi.mixerSetMasterVolume(db);
  }

  /// Set track volume (0.0 - 1.5, where 1.0 = 0dB)
  void setTrackVolume(int trackId, double volume) {
      _ffi.setTrackVolume(trackId, volume);
  }

  /// Set track pan (-1.0 to 1.0, where 0.0 = center)
  void setTrackPan(int trackId, double pan) {
    final clampedPan = pan.clamp(-1.0, 1.0);
      _ffi.setTrackPan(trackId, clampedPan);
  }

  /// Set bus volume (0.0 - 1.5, where 1.0 = 0dB)
  void setBusVolume(int busIndex, double volume) {
      final db = volume <= 0.0001 ? -60.0 : 20.0 * log(volume) / ln10;
      _ffi.mixerSetBusVolume(busIndex, db);
  }

  /// Set bus pan (-1.0 to 1.0, where 0.0 = center)
  void setBusPan(int busIndex, double pan) {
    final clampedPan = pan.clamp(-1.0, 1.0);
      _ffi.mixerSetBusPan(busIndex, clampedPan);
  }

  /// Get current master volume

  // ═══════════════════════════════════════════════════════════════════════════
  // TRANSPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get current transport state
  TransportState get transport => _transport;

  /// Transport state stream
  Stream<TransportState> get transportStream => _transportController.stream;

  /// Start playback
  void play() {
      _ffi.play();
    _transport = TransportState(
      isPlaying: true,
      isRecording: _transport.isRecording,
      positionSamples: _transport.positionSamples,
      positionSeconds: _transport.positionSeconds,
      tempo: _transport.tempo,
      timeSigNum: _transport.timeSigNum,
      timeSigDenom: _transport.timeSigDenom,
      loopEnabled: _transport.loopEnabled,
      loopStart: _transport.loopStart,
      loopEnd: _transport.loopEnd,
    );
    _transportController.add(_transport);
  }

  /// Stop playback
  void stop() {
      _ffi.stop();
    _transport = TransportState(
      isPlaying: false,
      isRecording: false,
      positionSamples: 0,
      positionSeconds: 0.0,
      tempo: _transport.tempo,
      timeSigNum: _transport.timeSigNum,
      timeSigDenom: _transport.timeSigDenom,
      loopEnabled: _transport.loopEnabled,
      loopStart: _transport.loopStart,
      loopEnd: _transport.loopEnd,
    );
    _transportController.add(_transport);
  }

  /// Pause playback
  void pause() {
      _ffi.pause();
    _transport = TransportState(
      isPlaying: false,
      isRecording: _transport.isRecording,
      positionSamples: _transport.positionSamples,
      positionSeconds: _transport.positionSeconds,
      tempo: _transport.tempo,
      timeSigNum: _transport.timeSigNum,
      timeSigDenom: _transport.timeSigDenom,
      loopEnabled: _transport.loopEnabled,
      loopStart: _transport.loopStart,
      loopEnd: _transport.loopEnd,
    );
    _transportController.add(_transport);
  }

  /// Toggle record
  void toggleRecord() {
    _transport = TransportState(
      isPlaying: _transport.isPlaying,
      isRecording: !_transport.isRecording,
      positionSamples: _transport.positionSamples,
      positionSeconds: _transport.positionSeconds,
      tempo: _transport.tempo,
      timeSigNum: _transport.timeSigNum,
      timeSigDenom: _transport.timeSigDenom,
      loopEnabled: _transport.loopEnabled,
      loopStart: _transport.loopStart,
      loopEnd: _transport.loopEnd,
    );
    _transportController.add(_transport);
  }

  /// Set position in seconds
  void setPosition(double seconds) {
      _ffi.seek(seconds);
    final sampleRate = _project.sampleRate;
    _transport = TransportState(
      isPlaying: _transport.isPlaying,
      isRecording: _transport.isRecording,
      positionSamples: (seconds * sampleRate).toInt(),
      positionSeconds: seconds,
      tempo: _transport.tempo,
      timeSigNum: _transport.timeSigNum,
      timeSigDenom: _transport.timeSigDenom,
      loopEnabled: _transport.loopEnabled,
      loopStart: _transport.loopStart,
      loopEnd: _transport.loopEnd,
    );
    _transportController.add(_transport);
  }

  /// Set tempo
  void setTempo(double bpm) {
    _transport = TransportState(
      isPlaying: _transport.isPlaying,
      isRecording: _transport.isRecording,
      positionSamples: _transport.positionSamples,
      positionSeconds: _transport.positionSeconds,
      tempo: bpm.clamp(20.0, 999.0),
      timeSigNum: _transport.timeSigNum,
      timeSigDenom: _transport.timeSigDenom,
      loopEnabled: _transport.loopEnabled,
      loopStart: _transport.loopStart,
      loopEnd: _transport.loopEnd,
    );
    _transportController.add(_transport);
  }

  /// Toggle loop
  void toggleLoop() {
    final newLoopEnabled = !_transport.loopEnabled;
      _ffi.setLoopEnabled(newLoopEnabled);
      _ffi.syncLoopFromRegion();
    _transport = TransportState(
      isPlaying: _transport.isPlaying,
      isRecording: _transport.isRecording,
      positionSamples: _transport.positionSamples,
      positionSeconds: _transport.positionSeconds,
      tempo: _transport.tempo,
      timeSigNum: _transport.timeSigNum,
      timeSigDenom: _transport.timeSigDenom,
      loopEnabled: newLoopEnabled,
      loopStart: _transport.loopStart,
      loopEnd: _transport.loopEnd,
    );
    _transportController.add(_transport);
  }

  /// Set loop region
  void setLoopRegion(double start, double end) {
      _ffi.setLoopRegion(start, end);
      _ffi.syncLoopFromRegion();
    _transport = TransportState(
      isPlaying: _transport.isPlaying,
      isRecording: _transport.isRecording,
      positionSamples: _transport.positionSamples,
      positionSeconds: _transport.positionSeconds,
      tempo: _transport.tempo,
      timeSigNum: _transport.timeSigNum,
      timeSigDenom: _transport.timeSigDenom,
      loopEnabled: _transport.loopEnabled,
      loopStart: start,
      loopEnd: end,
    );
    _transportController.add(_transport);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // METERING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get current metering state
  MeteringState get metering => _metering;

  /// Metering state stream
  Stream<MeteringState> get meteringStream => _meteringController.stream;

  // ═══════════════════════════════════════════════════════════════════════════
  // PROJECT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get current project info
  ProjectInfo get project => _project;

  /// Create new project
  void newProject(String name) {
    _project = ProjectInfo(
      name: name,
      trackCount: 0,
      busCount: 6,
      sampleRate: 48000,
      tempo: 120.0,
      timeSigNum: 4,
      timeSigDenom: 4,
      durationSamples: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      modifiedAt: DateTime.now().millisecondsSinceEpoch,
    );
    stop();
  }

  /// Save project
  Future<bool> saveProject(String path) async {
    print('[Engine] Saving project to: $path');
      final result = _ffi.saveProject(path);
      if (result) {
        _project = ProjectInfo(
          name: _project.name,
          trackCount: _project.trackCount,
          busCount: _project.busCount,
          sampleRate: _project.sampleRate,
          tempo: _project.tempo,
          timeSigNum: _project.timeSigNum,
          timeSigDenom: _project.timeSigDenom,
          durationSamples: _project.durationSamples,
          createdAt: _project.createdAt,
          modifiedAt: DateTime.now().millisecondsSinceEpoch,
        );
        print('[Engine] Project saved via FFI');
        return true;
      }
      return false;
    await Future.delayed(const Duration(milliseconds: 100));
    return true;
  }

  /// Load project
  Future<bool> loadProject(String path) async {
    print('[Engine] Loading project from: $path');
      final result = _ffi.loadProject(path);
      if (result) {
        // Sync project info from engine
        _ffi.preloadAll();
        print('[Engine] Project loaded via FFI');
        return true;
      }
      return false;
    await Future.delayed(const Duration(milliseconds: 100));
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROJECT DIRTY STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if project has unsaved changes
  bool get isProjectModified {
      return _ffi.isProjectModified();
    return false; // Mock always clean
  }

  /// Mark project as dirty (has unsaved changes)
  void markProjectDirty() {
      _ffi.markProjectDirty();
  }

  /// Mark project as clean (just saved)
  void markProjectClean() {
      _ffi.markProjectClean();
  }

  /// Set project file path
  void setProjectFilePath(String? path) {
      _ffi.setProjectFilePath(path);
  }

  /// Get project file path
  String? get projectFilePath {
      return _ffi.getProjectFilePath();
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new track
  /// Returns track ID
  String createTrack({
    required String name,
    required int color,
    int busId = 0,
  }) {
      final nativeId = _ffi.createTrack(name, color, busId);
      if (nativeId != 0) {
        print('[Engine] Created track via FFI: $name (id: $nativeId)');
        return nativeId.toString();
      }
    final id = 'track-${DateTime.now().millisecondsSinceEpoch}';
    return id;
  }

  /// Delete a track
  void deleteTrack(String trackId) {
      final nativeId = int.tryParse(trackId);
      if (nativeId != null) {
        _ffi.deleteTrack(nativeId);
        print('[Engine] Deleted track via FFI: $trackId');
        return;
      }
  }

  /// Update track properties
  void updateTrack(String trackId, {
    String? name,
    int? color,
    bool? muted,
    bool? soloed,
    bool? armed,
    double? volume,
    double? pan,
    int? busId,
  }) {
      final nativeId = int.tryParse(trackId);
      if (nativeId != null) {
        if (name != null) _ffi.setTrackName(nativeId, name);
        if (muted != null) _ffi.setTrackMute(nativeId, muted);
        if (soloed != null) _ffi.setTrackSolo(nativeId, soloed);
        if (armed != null) _ffi.setTrackArmed(nativeId, armed);
        if (volume != null) _ffi.setTrackVolume(nativeId, volume);
        if (pan != null) _ffi.setTrackPan(nativeId, pan);
        if (busId != null) _ffi.setTrackBus(nativeId, busId);
        print('[Engine] Updated track via FFI: $trackId');
        return;
      }
  }

  /// Get track peak level for metering (0.0 - 1.0+)
  /// Returns max of L/R for backward compatibility
  double getTrackPeak(int trackId) {

  /// Get track stereo peak levels (L, R) by track ID
  /// Returns (peakL, peakR) tuple
  (double, double) getTrackPeakStereo(int trackId) {

  /// Get track stereo RMS levels (L, R) by track ID
  /// Returns (rmsL, rmsR) tuple
  (double, double) getTrackRmsStereo(int trackId) {

  /// Get track correlation by track ID (-1.0 to 1.0)
  double getTrackCorrelation(int trackId) {

  /// Get full track meter data (peakL, peakR, rmsL, rmsR, correlation)
  ({double peakL, double peakR, double rmsL, double rmsR, double correlation}) getTrackMeter(int trackId) {

  /// Get all track peak levels at once (more efficient for UI metering)
  /// Returns map of track_id -> peak value (max of L/R for backward compat)
  Map<int, double> getAllTrackPeaks(int maxTracks) {

  /// Get all track stereo meters at once (most efficient for UI)
  /// Returns map of track_id -> TrackMeterData
  Map<int, ({double peakL, double peakR, double rmsL, double rmsR, double correlation})> getAllTrackMeters(int maxTracks) {

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO IMPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Import audio file to a track
  /// Returns clip ID or null on failure
  Future<ImportedClipInfo?> importAudioFile({
    required String filePath,
    required String trackId,
    required double startTime,
  }) async {
    print('[Engine] Importing audio: $filePath to track $trackId at $startTime');

      final nativeTrackId = int.tryParse(trackId);
      if (nativeTrackId != null) {
        final clipId = _ffi.importAudio(filePath, nativeTrackId, startTime);
        if (clipId != 0) {
          final fileName = filePath.split('/').last;
          print('[Engine] Imported via FFI: $fileName (clip: $clipId)');
          // Preload audio for playback
          _ffi.preloadAll();

          // Get actual duration from engine
          final duration = _ffi.getClipDuration(clipId);
          final sourceDuration = _ffi.getClipSourceDuration(clipId);
          print('[Engine] Clip duration: $duration, source: $sourceDuration');

          return ImportedClipInfo(
            clipId: clipId.toString(),
            trackId: trackId,
            name: fileName,
            startTime: startTime,
            duration: duration > 0 ? duration : 5.0,
            sourceDuration: sourceDuration > 0 ? sourceDuration : duration > 0 ? duration : 5.0,
            sampleRate: 48000,
            channels: 2,
          );
        }
      }

    final fileName = filePath.split('/').last;
    final clipId = 'clip-${DateTime.now().millisecondsSinceEpoch}';
    await Future.delayed(const Duration(milliseconds: 100));

    return ImportedClipInfo(
      clipId: clipId,
      trackId: trackId,
      name: fileName,
      startTime: startTime,
      duration: 5.0,
      sourceDuration: 5.0,
      sampleRate: 48000,
      channels: 2,
    );
  }

  /// Get waveform peaks for a clip
  /// Returns list of (min, max) pairs
  Future<List<double>> getWaveformPeaks({
    required String clipId,
    int lodLevel = 0,
  }) async {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        final peaks = _ffi.getWaveformPeaks(nativeClipId, lodLevel: lodLevel);
        if (peaks.isNotEmpty) {
          return peaks;
        }
      }
    // Return empty list (UI will use demo waveform)
    return [];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLIP MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Move a clip to a new position (and optionally new track)
  void moveClip({
    required String clipId,
    required String targetTrackId,
    required double startTime,
  }) {
      final nativeClipId = int.tryParse(clipId);
      final nativeTrackId = int.tryParse(targetTrackId);
      if (nativeClipId != null && nativeTrackId != null) {
        _ffi.moveClip(nativeClipId, nativeTrackId, startTime);
        print('[Engine] Moved clip via FFI: $clipId');
        return;
      }
  }

  /// Resize a clip
  void resizeClip({
    required String clipId,
    required double startTime,
    required double duration,
    required double sourceOffset,
  }) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        _ffi.resizeClip(nativeClipId, startTime, duration, sourceOffset);
        print('[Engine] Resized clip via FFI: $clipId');
        return;
      }
  }

  /// Split a clip at playhead
  /// Returns new clip ID or null on failure
  String? splitClip({
    required String clipId,
    required double atTime,
  }) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        final newId = _ffi.splitClip(nativeClipId, atTime);
        if (newId != 0) {
          print('[Engine] Split clip via FFI: $clipId -> $newId');
          return newId.toString();
        }
      }
    return 'clip-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Duplicate a clip
  /// Returns new clip ID or null on failure
  String? duplicateClip(String clipId) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        final newId = _ffi.duplicateClip(nativeClipId);
        if (newId != 0) {
          print('[Engine] Duplicated clip via FFI: $clipId -> $newId');
          return newId.toString();
        }
      }
    return 'clip-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Delete a clip
  void deleteClip(String clipId) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        _ffi.deleteClip(nativeClipId);
        print('[Engine] Deleted clip via FFI: $clipId');
        return;
      }
  }

  /// Set clip gain
  void setClipGain(String clipId, double gain) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        _ffi.setClipGain(nativeClipId, gain);
        print('[Engine] Set clip gain via FFI: $clipId = $gain');
        return;
      }
  }

  /// Set clip mute state
  void setClipMuted(String clipId, bool muted) {
    print('[Engine] Set clip $clipId muted to $muted');
  }

  /// Normalize clip to target dB
  bool normalizeClip(String clipId, {double targetDb = -3.0}) {
    print('[Engine] Normalize clip $clipId to $targetDb dB');
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        return _ffi.clipNormalize(nativeClipId, targetDb);
      }
    return true;
  }

  /// Reverse clip audio
  bool reverseClip(String clipId) {
    print('[Engine] Reverse clip $clipId');
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        return _ffi.clipReverse(nativeClipId);
      }
    return true;
  }

  /// Apply fade in to clip
  /// curveType: 0=Linear, 1=EqualPower, 2=SCurve
  bool fadeInClip(String clipId, double durationSec, {int curveType = 1}) {
    print('[Engine] Fade in clip $clipId for $durationSec sec');
      final nativeClipId = _parseClipId(clipId);
      if (nativeClipId != null) {
        return _ffi.clipFadeIn(nativeClipId, durationSec, curveType);
      }
    return true;
  }

  /// Apply fade out to clip
  bool fadeOutClip(String clipId, double durationSec, {int curveType = 1}) {
    print('[Engine] Fade out clip $clipId for $durationSec sec');
      final nativeClipId = _parseClipId(clipId);
      if (nativeClipId != null) {
        return _ffi.clipFadeOut(nativeClipId, durationSec, curveType);
      }
    return true;
  }

  /// Parse clip ID - native engine clip IDs are integers
  ///
  /// converted to native engine IDs. Only clips imported via importAudioFile
  /// have valid native IDs that can be used for fade, gain, and other operations.
  int? _parseClipId(String clipId) {
    // Native clip IDs are simple integers returned from importAudioFile
    final direct = int.tryParse(clipId);
    if (direct != null) return direct;

    // "clip-TIMESTAMP-INDEX" format does NOT contain native engine IDs
    // The timestamp is NOT a valid clip ID - return null
    return null;
  }

  /// Apply gain adjustment to clip
  bool applyGainToClip(String clipId, double gainDb) {
    print('[Engine] Apply $gainDb dB gain to clip $clipId');
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        return _ffi.clipApplyGain(nativeClipId, gainDb);
      }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLIP FX
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add FX to a clip
  /// fxType: 0=Gain, 1=Compressor, 2=Limiter, 3=Gate, 4=Saturation, etc.
  String? addClipFx(String clipId, int fxType) {
    print('[Engine] Add FX type $fxType to clip $clipId');
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        final slotId = _ffi.addClipFx(nativeClipId, fxType);
        if (slotId != 0) {
          return slotId.toString();
        }
      }
    return 'fxslot-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Remove FX from a clip
  bool removeClipFx(String clipId, String slotId) {
    print('[Engine] Remove FX slot $slotId from clip $clipId');
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.removeClipFx(nativeClipId, nativeSlotId);
      }
    return true;
  }

  /// Bypass/enable a clip FX slot
  bool setClipFxBypass(String clipId, String slotId, bool bypass) {
    print('[Engine] Set FX slot $slotId bypass: $bypass');
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.setClipFxBypass(nativeClipId, nativeSlotId, bypass);
      }
    return true;
  }

  /// Bypass/enable entire clip FX chain
  bool setClipFxChainBypass(String clipId, bool bypass) {
    print('[Engine] Set clip $clipId FX chain bypass: $bypass');
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        return _ffi.setClipFxChainBypass(nativeClipId, bypass);
      }
    return true;
  }

  /// Set clip FX slot wet/dry mix (0.0-1.0)
  bool setClipFxWetDry(String clipId, String slotId, double wetDry) {
    print('[Engine] Set FX slot $slotId wet/dry: $wetDry');
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.setClipFxWetDry(nativeClipId, nativeSlotId, wetDry);
      }
    return true;
  }

  /// Set clip FX chain input gain (dB)
  bool setClipFxInputGain(String clipId, double gainDb) {
    print('[Engine] Set clip $clipId FX input gain: $gainDb dB');
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        return _ffi.setClipFxInputGain(nativeClipId, gainDb);
      }
    return true;
  }

  /// Set clip FX chain output gain (dB)
  bool setClipFxOutputGain(String clipId, double gainDb) {
    print('[Engine] Set clip $clipId FX output gain: $gainDb dB');
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        return _ffi.setClipFxOutputGain(nativeClipId, gainDb);
      }
    return true;
  }

  /// Set Gain FX parameters
  bool setClipFxGainParams(String clipId, String slotId, double db, double pan) {
    print('[Engine] Set Gain FX params: $db dB, pan $pan');
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.setClipFxGainParams(nativeClipId, nativeSlotId, db, pan);
      }
    return true;
  }

  /// Set Compressor FX parameters
  bool setClipFxCompressorParams(
    String clipId,
    String slotId, {
    required double ratio,
    required double thresholdDb,
    required double attackMs,
    required double releaseMs,
  }) {
    print('[Engine] Set Compressor FX params');
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.setClipFxCompressorParams(
          nativeClipId,
          nativeSlotId,
          ratio,
          thresholdDb,
          attackMs,
          releaseMs,
        );
      }
    return true;
  }

  /// Set Limiter FX parameters
  bool setClipFxLimiterParams(String clipId, String slotId, double ceilingDb) {
    print('[Engine] Set Limiter FX ceiling: $ceilingDb dB');
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.setClipFxLimiterParams(nativeClipId, nativeSlotId, ceilingDb);
      }
    return true;
  }

  /// Set Gate FX parameters
  bool setClipFxGateParams(
    String clipId,
    String slotId, {
    required double thresholdDb,
    required double attackMs,
    required double releaseMs,
  }) {
    print('[Engine] Set Gate FX params');
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.setClipFxGateParams(
          nativeClipId,
          nativeSlotId,
          thresholdDb,
          attackMs,
          releaseMs,
        );
      }
    return true;
  }

  /// Set Saturation FX parameters
  bool setClipFxSaturationParams(
    String clipId,
    String slotId, {
    required double drive,
    required double mix,
  }) {
    print('[Engine] Set Saturation FX params: drive $drive, mix $mix');
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.setClipFxSaturationParams(nativeClipId, nativeSlotId, drive, mix);
      }
    return true;
  }

  /// Move FX slot to new position in chain
  bool moveClipFx(String clipId, String slotId, int newIndex) {
    print('[Engine] Move FX slot $slotId to index $newIndex');
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.moveClipFx(nativeClipId, nativeSlotId, newIndex);
      }
    return true;
  }

  /// Copy FX chain from one clip to another
  bool copyClipFx(String sourceClipId, String targetClipId) {
    print('[Engine] Copy FX from clip $sourceClipId to $targetClipId');
      final nativeSourceId = int.tryParse(sourceClipId);
      final nativeTargetId = int.tryParse(targetClipId);
      if (nativeSourceId != null && nativeTargetId != null) {
        return _ffi.copyClipFx(nativeSourceId, nativeTargetId);
      }
    return true;
  }

  /// Clear all FX from a clip
  bool clearClipFx(String clipId) {
    print('[Engine] Clear all FX from clip $clipId');
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        return _ffi.clearClipFx(nativeClipId);
      }
    return true;
  }

  /// Rename a track
  bool renameTrack(String trackId, String name) {
    print('[Engine] Rename track $trackId to "$name"');
      final nativeTrackId = int.tryParse(trackId);
      if (nativeTrackId != null) {
        return _ffi.trackRename(nativeTrackId, name);
      }
    return true;
  }

  /// Duplicate a track and return new track ID
  String? duplicateTrack(String trackId) {
    print('[Engine] Duplicate track $trackId');
      final nativeTrackId = int.tryParse(trackId);
      if (nativeTrackId != null) {
        final newId = _ffi.trackDuplicate(nativeTrackId);
        if (newId != 0) {
          return newId.toString();
        }
      }
    return 'track-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Set track color
  bool setTrackColor(String trackId, int color) {
    print('[Engine] Set track $trackId color to $color');
      final nativeTrackId = int.tryParse(trackId);
      if (nativeTrackId != null) {
        return _ffi.trackSetColor(nativeTrackId, color);
      }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CROSSFADE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a crossfade between two clips
  /// curve: 0=Linear, 1=EqualPower, 2=SCurve
  String? createCrossfade({
    required String clipAId,
    required String clipBId,
    required double duration,
    int curve = 1, // EqualPower default
  }) {
    print('[Engine] Create crossfade between $clipAId and $clipBId');
      final nativeClipAId = int.tryParse(clipAId);
      final nativeClipBId = int.tryParse(clipBId);
      if (nativeClipAId != null && nativeClipBId != null) {
        final xfadeId = _ffi.createCrossfade(nativeClipAId, nativeClipBId, duration, curve);
        if (xfadeId != 0) {
          print('[Engine] Crossfade created via FFI: $xfadeId');
          return xfadeId.toString();
        }
      }
    return 'xfade-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Update crossfade
  void updateCrossfade(String crossfadeId, double duration, int curve) {
    print('[Engine] Update crossfade $crossfadeId');
    // Note: update requires delete + recreate (no update function in FFI)
  }

  /// Delete crossfade
  void deleteCrossfade(String crossfadeId) {
    print('[Engine] Delete crossfade $crossfadeId');
      final nativeId = int.tryParse(crossfadeId);
      if (nativeId != null) {
        _ffi.deleteCrossfade(nativeId);
        print('[Engine] Crossfade deleted via FFI');
        return;
      }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARKERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a marker
  String addMarker({
    required String name,
    required double time,
    required int color,
  }) {
    print('[Engine] Add marker $name at $time');
      final markerId = _ffi.addMarker(name, time, color);
      if (markerId != 0) {
        print('[Engine] Marker added via FFI: $markerId');
        return markerId.toString();
      }
    return 'marker-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Delete a marker
  void deleteMarker(String markerId) {
    print('[Engine] Delete marker $markerId');
      final nativeId = int.tryParse(markerId);
      if (nativeId != null) {
        _ffi.deleteMarker(nativeId);
        print('[Engine] Marker deleted via FFI');
        return;
      }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SNAP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Snap time to grid
  double snapToGrid(double time, double gridSize) {
    if (gridSize <= 0) return time;
    return (time / gridSize).round() * gridSize;
  }

  /// Snap time to nearest event (clip boundary)
  double snapToEvent(double time, double threshold) {
    // TODO: Call native engine_snap_to_event via FFI
    return time;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UNDO/REDO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if undo is available
  bool get canUndo {
      return _ffi.canUndo();
    return false;
  }

  /// Check if redo is available
  bool get canRedo {
      return _ffi.canRedo();
    return false;
  }

  /// Undo last action
  bool undo() {
    print('[Engine] Undo');
      final result = _ffi.undo();
      if (result) {
        print('[Engine] Undo successful via FFI');
      }
      return result;
    return false;
  }

  /// Redo last undone action
  bool redo() {
    print('[Engine] Redo');
      final result = _ffi.redo();
      if (result) {
        print('[Engine] Redo successful via FFI');
      }
      return result;
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MEMORY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get memory usage in MB
  double getMemoryUsage() {
      return _ffi.getMemoryUsage();
    return 0.0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EQ
  // ═══════════════════════════════════════════════════════════════════════════

  /// Convert track ID string to native int (master = 0, buses = 1-5, others parsed)
  int? _trackIdToNative(String trackId) {
    // Map bus names to native track IDs
    switch (trackId) {
      case 'master': return 0;
      case 'sfx': return 1;
      case 'music': return 2;
      case 'voice': return 3;
      case 'amb': return 4;
      case 'ui': return 5;
      default:
        // Handle channel IDs like 'ch_123'
        if (trackId.startsWith('ch_')) {
          return int.tryParse(trackId.substring(3));
        }
        if (trackId.startsWith('track-')) {
          return trackId.hashCode.abs() % 10000 + 100; // Offset to avoid bus collision
        }
        return int.tryParse(trackId);
    }
  }

  /// Set EQ band enabled state
  bool eqSetBandEnabled(String trackId, int bandIndex, bool enabled) {
    print('[Engine] EQ track $trackId band $bandIndex enabled: $enabled');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.eqSetBandEnabled(nativeTrackId, bandIndex, enabled);
      }
    return true;
  }

  /// Set EQ band frequency
  bool eqSetBandFrequency(String trackId, int bandIndex, double frequency) {
    print('[Engine] EQ track $trackId band $bandIndex freq: $frequency Hz');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.eqSetBandFrequency(nativeTrackId, bandIndex, frequency);
      }
    return true;
  }

  /// Set EQ band gain
  bool eqSetBandGain(String trackId, int bandIndex, double gain) {
    print('[Engine] EQ track $trackId band $bandIndex gain: $gain dB');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.eqSetBandGain(nativeTrackId, bandIndex, gain);
      }
    return true;
  }

  /// Set EQ band Q
  bool eqSetBandQ(String trackId, int bandIndex, double q) {
    print('[Engine] EQ track $trackId band $bandIndex Q: $q');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.eqSetBandQ(nativeTrackId, bandIndex, q);
      }
    return true;
  }

  /// Set EQ bypass
  bool eqSetBypass(String trackId, bool bypass) {
    print('[Engine] EQ track $trackId bypass: $bypass');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.eqSetBypass(nativeTrackId, bypass);
      }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEND/RETURN
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set send level (0.0 to 1.0)
  void setSendLevel(String trackId, int sendIndex, double level) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.sendSetLevel(nativeTrackId, sendIndex, level.clamp(0.0, 1.0));
      }
  }

  /// Set send level in dB
  void setSendLevelDb(String trackId, int sendIndex, double db) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.sendSetLevelDb(nativeTrackId, sendIndex, db.clamp(-96.0, 12.0));
      }
  }

  /// Set send muted state
  void setSendMuted(String trackId, int sendIndex, bool muted) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.sendSetMuted(nativeTrackId, sendIndex, muted);
      }
  }

  /// Set send pre/post fader (tap point)
  /// preFader: true = pre-fader (tap point 0), false = post-fader (tap point 1)
  void setSendPreFader(String trackId, int sendIndex, bool preFader) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        // TapPoint: 0=PreFader, 1=PostFader, 2=PostPan
        _ffi.sendSetTapPoint(nativeTrackId, sendIndex, preFader ? 0 : 1);
      }
  }

  /// Set send destination (FX bus index)
  /// destination: 0-3 for FX returns
  void setSendDestination(String trackId, int sendIndex, int destination) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.sendSetDestination(nativeTrackId, sendIndex, destination);
      }
  }

  /// Set send destination by bus ID string
  void setSendDestinationById(String trackId, int sendIndex, String? destinationId) {
    if (destinationId == null) {
      // Clear destination - set to invalid index
      setSendDestination(trackId, sendIndex, -1);
      return;
    }
    // Parse FX bus ID: "fx1" -> 0, "fx2" -> 1, etc.
    final match = RegExp(r'^fx(\d+)$').firstMatch(destinationId);
    if (match != null) {
      final fxIndex = int.parse(match.group(1)!) - 1; // fx1 = index 0
      setSendDestination(trackId, sendIndex, fxIndex);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INSERT EFFECTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create insert chain for a track
  void insertCreateChain(String trackId) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.insertCreateChain(nativeTrackId);
      }
  }

  /// Remove insert chain from a track
  void insertRemoveChain(String trackId) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.insertRemoveChain(nativeTrackId);
      }
  }

  /// Set insert slot bypass state
  void insertSetBypass(String trackId, int slotIndex, bool bypass) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.insertSetBypass(nativeTrackId, slotIndex, bypass);
      }
  }

  /// Set insert slot wet/dry mix (0.0 = dry, 1.0 = wet)
  void insertSetMix(String trackId, int slotIndex, double mix) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.insertSetMix(nativeTrackId, slotIndex, mix.clamp(0.0, 1.0));
      }
  }

  /// Bypass all inserts on a track
  void insertBypassAll(String trackId, bool bypass) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.insertBypassAll(nativeTrackId, bypass);
      }
  }

  /// Get total latency of insert chain (in samples)
  int insertGetTotalLatency(String trackId) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.insertGetTotalLatency(nativeTrackId);
      }
    return 0;
  }

  /// Load processor into insert slot
  /// Returns 1 on success, 0 on failure
  int insertLoadProcessor(String trackId, int slotIndex, String processorName) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.insertLoadProcessor(nativeTrackId, slotIndex, processorName);
      }
    return 0;
  }

  /// Unload processor from insert slot
  /// Returns 1 on success, 0 on failure
  int insertUnloadSlot(String trackId, int slotIndex) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.insertUnloadSlot(nativeTrackId, slotIndex);
      }
    return 0;
  }

  /// Set parameter on insert slot processor
  /// Returns 1 on success, 0 on failure
  int insertSetParam(String trackId, int slotIndex, int paramIndex, double value) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.insertSetParam(nativeTrackId, slotIndex, paramIndex, value);
      }
    return 0;
  }

  /// Get parameter from insert slot processor
  double insertGetParam(String trackId, int slotIndex, int paramIndex) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.insertGetParam(nativeTrackId, slotIndex, paramIndex);
      }
    return 0.0;
  }

  /// Check if insert slot has a processor loaded
  bool insertIsLoaded(String trackId, int slotIndex) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.insertIsLoaded(nativeTrackId, slotIndex);
      }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRO EQ - 64-Band Professional Parametric EQ
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create Pro EQ for a track
  bool proEqCreate(String trackId, {double sampleRate = 48000.0}) {
    print('[Engine] Pro EQ create: $trackId @ ${sampleRate}Hz');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqCreate(nativeTrackId, sampleRate: sampleRate);
      }
    return true;
  }

  /// Destroy Pro EQ for a track
  bool proEqDestroy(String trackId) {
    print('[Engine] Pro EQ destroy: $trackId');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqDestroy(nativeTrackId);
      }
    return true;
  }

  /// Set Pro EQ band enabled
  bool proEqSetBandEnabled(String trackId, int bandIndex, bool enabled) {
    print('[Engine] Pro EQ $trackId band $bandIndex enabled: $enabled');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandEnabled(nativeTrackId, bandIndex, enabled);
      }
    return true;
  }

  /// Set Pro EQ band frequency
  bool proEqSetBandFrequency(String trackId, int bandIndex, double freq) {
    print('[Engine] Pro EQ $trackId band $bandIndex freq: $freq Hz');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandFrequency(nativeTrackId, bandIndex, freq);
      }
    return true;
  }

  /// Set Pro EQ band gain
  bool proEqSetBandGain(String trackId, int bandIndex, double gainDb) {
    print('[Engine] Pro EQ $trackId band $bandIndex gain: $gainDb dB');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandGain(nativeTrackId, bandIndex, gainDb);
      }
    return true;
  }

  /// Set Pro EQ band Q
  bool proEqSetBandQ(String trackId, int bandIndex, double q) {
    print('[Engine] Pro EQ $trackId band $bandIndex Q: $q');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandQ(nativeTrackId, bandIndex, q);
      }
    return true;
  }

  /// Set Pro EQ band shape
  bool proEqSetBandShape(String trackId, int bandIndex, ProEqFilterShape shape) {
    print('[Engine] Pro EQ $trackId band $bandIndex shape: $shape');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandShape(nativeTrackId, bandIndex, shape);
      }
    return true;
  }

  /// Set all Pro EQ band parameters at once
  bool proEqSetBand(
    String trackId,
    int bandIndex, {
    required double freq,
    required double gainDb,
    required double q,
    required ProEqFilterShape shape,
  }) {
    print('[Engine] Pro EQ $trackId band $bandIndex: f=$freq g=$gainDb q=$q shape=$shape');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBand(nativeTrackId, bandIndex, freq: freq, gainDb: gainDb, q: q, shape: shape);
      }
    return true;
  }

  /// Set Pro EQ band stereo placement
  bool proEqSetBandPlacement(String trackId, int bandIndex, ProEqPlacement placement) {
    print('[Engine] Pro EQ $trackId band $bandIndex placement: $placement');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandPlacement(nativeTrackId, bandIndex, placement);
      }
    return true;
  }

  /// Set Pro EQ band slope
  bool proEqSetBandSlope(String trackId, int bandIndex, ProEqSlope slope) {
    print('[Engine] Pro EQ $trackId band $bandIndex slope: $slope');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandSlope(nativeTrackId, bandIndex, slope);
      }
    return true;
  }

  /// Enable/disable dynamic EQ for a band
  bool proEqSetBandDynamicEnabled(String trackId, int bandIndex, bool enabled) {
    print('[Engine] Pro EQ $trackId band $bandIndex dynamic enabled: $enabled');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandDynamicEnabled(nativeTrackId, bandIndex, enabled);
      }
    return true;
  }

  /// Set dynamic EQ parameters for a band (partial update)
  bool proEqSetBandDynamicParams(
    String trackId,
    int bandIndex, {
    double? threshold,
    double? ratio,
    double? attackMs,
    double? releaseMs,
    double? kneeDb,
  }) {
    print('[Engine] Pro EQ $trackId band $bandIndex dynamic params: thr=$threshold ratio=$ratio att=$attackMs rel=$releaseMs knee=$kneeDb');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandDynamicParams(
          nativeTrackId, bandIndex,
          threshold: threshold,
          ratio: ratio,
          attackMs: attackMs,
          releaseMs: releaseMs,
          kneeDb: kneeDb,
        );
      }
    return true;
  }

  /// Configure dynamic EQ for a band
  bool proEqSetBandDynamic(
    String trackId,
    int bandIndex, {
    required bool enabled,
    required double thresholdDb,
    required double ratio,
    required double attackMs,
    required double releaseMs,
  }) {
    print('[Engine] Pro EQ $trackId band $bandIndex dynamic: enabled=$enabled thr=$thresholdDb');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandDynamic(
          nativeTrackId, bandIndex,
          enabled: enabled,
          thresholdDb: thresholdDb,
          ratio: ratio,
          attackMs: attackMs,
          releaseMs: releaseMs,
        );
      }
    return true;
  }

  /// Set Pro EQ output gain
  bool proEqSetOutputGain(String trackId, double gainDb) {
    print('[Engine] Pro EQ $trackId output gain: $gainDb dB');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetOutputGain(nativeTrackId, gainDb);
      }
    return true;
  }

  /// Set Pro EQ phase mode (0=ZeroLatency, 1=Natural, 2=Linear)
  bool proEqSetPhaseMode(String trackId, int mode) {
    print('[Engine] Pro EQ $trackId phase mode: $mode');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetPhaseMode(nativeTrackId, mode);
      }
    return true;
  }

  /// Set Pro EQ analyzer mode
  bool proEqSetAnalyzerMode(String trackId, ProEqAnalyzerMode mode) {
    print('[Engine] Pro EQ $trackId analyzer: $mode');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetAnalyzerMode(nativeTrackId, mode);
      }
    return true;
  }

  /// Enable/disable Pro EQ auto gain
  bool proEqSetAutoGain(String trackId, bool enabled) {
    print('[Engine] Pro EQ $trackId auto gain: $enabled');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetAutoGain(nativeTrackId, enabled);
      }
    return true;
  }

  /// Enable/disable Pro EQ match mode
  bool proEqSetMatchEnabled(String trackId, bool enabled) {
    print('[Engine] Pro EQ $trackId match: $enabled');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetMatchEnabled(nativeTrackId, enabled);
      }
    return true;
  }

  /// Store Pro EQ state A
  bool proEqStoreStateA(String trackId) {
    print('[Engine] Pro EQ $trackId store state A');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqStoreStateA(nativeTrackId);
      }
    return true;
  }

  /// Store Pro EQ state B
  bool proEqStoreStateB(String trackId) {
    print('[Engine] Pro EQ $trackId store state B');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqStoreStateB(nativeTrackId);
      }
    return true;
  }

  /// Recall Pro EQ state A
  bool proEqRecallStateA(String trackId) {
    print('[Engine] Pro EQ $trackId recall state A');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqRecallStateA(nativeTrackId);
      }
    return true;
  }

  /// Recall Pro EQ state B
  bool proEqRecallStateB(String trackId) {
    print('[Engine] Pro EQ $trackId recall state B');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqRecallStateB(nativeTrackId);
      }
    return true;
  }

  /// Get Pro EQ enabled band count
  int proEqGetEnabledBandCount(String trackId) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqGetEnabledBandCount(nativeTrackId);
      }
    return 0;
  }

  /// Reset Pro EQ state
  bool proEqReset(String trackId) {
    print('[Engine] Pro EQ $trackId reset');
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqReset(nativeTrackId);
      }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIXER BUSES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set bus volume (in dB)
  bool mixerSetBusVolume(int busId, double volumeDb) {
    print('[Engine] Bus $busId volume: $volumeDb dB');
      return _ffi.mixerSetBusVolume(busId, volumeDb);
    return true;
  }

  /// Set bus mute
  bool mixerSetBusMute(int busId, bool muted) {
    print('[Engine] Bus $busId mute: $muted');
      return _ffi.mixerSetBusMute(busId, muted);
    return true;
  }

  /// Set bus solo
  bool mixerSetBusSolo(int busId, bool solo) {
    print('[Engine] Bus $busId solo: $solo');
      return _ffi.mixerSetBusSolo(busId, solo);
    return true;
  }

  /// Set bus pan
  bool mixerSetBusPan(int busId, double pan) {
    print('[Engine] Bus $busId pan: $pan');
      return _ffi.mixerSetBusPan(busId, pan);
    return true;
  }

  /// Set master volume
  bool mixerSetMasterVolume(double volumeDb) {
    print('[Engine] Master volume: $volumeDb dB');
      return _ffi.mixerSetMasterVolume(volumeDb);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VCA FADERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new VCA fader
  /// Returns VCA ID
  int vcaCreate(String name) {
    print('[Engine] Create VCA: $name');
      return _ffi.vcaCreate(name);
    return DateTime.now().millisecondsSinceEpoch;
  }

  /// Delete a VCA fader
  bool vcaDelete(int vcaId) {
    print('[Engine] Delete VCA: $vcaId');
      return _ffi.vcaDelete(vcaId);
    return true;
  }

  /// Set VCA level (0.0 - 1.5, where 1.0 = unity/0dB)
  bool vcaSetLevel(int vcaId, double level) {
    print('[Engine] VCA $vcaId level: $level');
      return _ffi.vcaSetLevel(vcaId, level);
    return true;
  }

  /// Get VCA level
  double vcaGetLevel(int vcaId) {
      return _ffi.vcaGetLevel(vcaId);
    return 1.0;
  }

  /// Set VCA mute state
  bool vcaSetMute(int vcaId, bool muted) {
    print('[Engine] VCA $vcaId mute: $muted');
      return _ffi.vcaSetMute(vcaId, muted);
    return true;
  }

  /// Assign track to VCA
  bool vcaAssignTrack(int vcaId, int trackId) {
    print('[Engine] Assign track $trackId to VCA $vcaId');
      return _ffi.vcaAssignTrack(vcaId, trackId);
    return true;
  }

  /// Remove track from VCA
  bool vcaRemoveTrack(int vcaId, int trackId) {
    print('[Engine] Remove track $trackId from VCA $vcaId');
      return _ffi.vcaRemoveTrack(vcaId, trackId);
    return true;
  }

  /// Get effective volume for track including VCA contribution
  double vcaGetTrackEffectiveVolume(int trackId, double baseVolume) {
      return _ffi.vcaGetTrackEffectiveVolume(trackId, baseVolume);
    return baseVolume;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK GROUPS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new track group
  /// Returns group ID
  int groupCreate(String name) {
    print('[Engine] Create group: $name');
      return _ffi.groupCreate(name);
    return DateTime.now().millisecondsSinceEpoch;
  }

  /// Delete a track group
  bool groupDelete(int groupId) {
    print('[Engine] Delete group: $groupId');
      return _ffi.groupDelete(groupId);
    return true;
  }

  /// Add track to group
  bool groupAddTrack(int groupId, int trackId) {
    print('[Engine] Add track $trackId to group $groupId');
      return _ffi.groupAddTrack(groupId, trackId);
    return true;
  }

  /// Remove track from group
  bool groupRemoveTrack(int groupId, int trackId) {
    print('[Engine] Remove track $trackId from group $groupId');
      return _ffi.groupRemoveTrack(groupId, trackId);
    return true;
  }

  /// Set group link mode
  /// linkMode: 0=Relative, 1=Absolute
  bool groupSetLinkMode(int groupId, int linkMode) {
    print('[Engine] Group $groupId link mode: $linkMode');
      return _ffi.groupSetLinkMode(groupId, linkMode);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIVATE
  // ═══════════════════════════════════════════════════════════════════════════

  void _startUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _updateState();
    });
  }

  void _updateState() {
    if (!_initialized) return;

    // Update transport position
    if (_transport.isPlaying) {
      double finalSeconds;
      final sampleRate = _project.sampleRate;

        // Read position from Rust engine
        finalSeconds = _ffi.getPosition();
      } else {
        // Mock position update
        final newSeconds = _transport.positionSeconds + 0.016; // ~60fps

        // Handle loop in mock mode
        finalSeconds = newSeconds;
        if (_transport.loopEnabled &&
            _transport.loopEnd > _transport.loopStart &&
            newSeconds >= _transport.loopEnd) {
          finalSeconds = _transport.loopStart;
        }

      _transport = TransportState(
        isPlaying: true,
        isRecording: _transport.isRecording,
        positionSamples: (finalSeconds * sampleRate).toInt(),
        positionSeconds: finalSeconds,
        tempo: _transport.tempo,
        timeSigNum: _transport.timeSigNum,
        timeSigDenom: _transport.timeSigDenom,
        loopEnabled: _transport.loopEnabled,
        loopStart: _transport.loopStart,
        loopEnd: _transport.loopEnd,
      );
      _transportController.add(_transport);
    }

    // Update metering at 30fps (every 2nd frame) to reduce UI thread load
    // Transport runs at 60fps for smooth playhead, metering at 30fps is visually sufficient
    _meteringFrameCounter++;
    if (_meteringFrameCounter % 2 != 0) {
      return; // Skip metering on odd frames
    }

  }
}

/// Global engine instance
final engine = EngineApi.instance;

// ═══════════════════════════════════════════════════════════════════════════
// STATE CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Transport state
class TransportState {
  final bool isPlaying;
  final bool isRecording;
  final int positionSamples;
  final double positionSeconds;
  final double tempo;
  final int timeSigNum;
  final int timeSigDenom;
  final bool loopEnabled;
  final double loopStart;
  final double loopEnd;

  const TransportState({
    required this.isPlaying,
    required this.isRecording,
    required this.positionSamples,
    required this.positionSeconds,
    required this.tempo,
    required this.timeSigNum,
    required this.timeSigDenom,
    required this.loopEnabled,
    required this.loopStart,
    required this.loopEnd,
  });

  factory TransportState.empty() => const TransportState(
    isPlaying: false,
    isRecording: false,
    positionSamples: 0,
    positionSeconds: 0.0,
    tempo: 120.0,
    timeSigNum: 4,
    timeSigDenom: 4,
    loopEnabled: false,
    loopStart: 0.0,
    loopEnd: 0.0,
  );
}

/// Metering state for a single bus
class BusMeteringState {
  final double peakL;
  final double peakR;
  final double rmsL;
  final double rmsR;
  final double heldPeakL;
  final double heldPeakR;

  const BusMeteringState({
    required this.peakL,
    required this.peakR,
    required this.rmsL,
    required this.rmsR,
    required this.heldPeakL,
    required this.heldPeakR,
  });

  factory BusMeteringState.empty() => const BusMeteringState(
    peakL: -60.0,
    peakR: -60.0,
    rmsL: -60.0,
    rmsR: -60.0,
    heldPeakL: -60.0,
    heldPeakR: -60.0,
  );

  /// Generate mock metering data for active playback
  /// activity: 0.0-1.0 controls meter level (1.0 = full level)
    if (activity <= 0) {
      return BusMeteringState.empty();
    }
    // Base level scaled by activity
    final base = -18.0 + random.nextDouble() * 6 * activity;
    return BusMeteringState(
      peakL: base + random.nextDouble() * 3,
      peakR: base + random.nextDouble() * 3,
      rmsL: base - 6 + random.nextDouble() * 2,
      rmsR: base - 6 + random.nextDouble() * 2,
      heldPeakL: base + 3,
      heldPeakR: base + 3,
    );
  }
}

/// Metering state
class MeteringState {
  final double masterPeakL;
  final double masterPeakR;
  final double masterRmsL;
  final double masterRmsR;
  final double masterLufsM;
  final double masterLufsS;
  final double masterLufsI;
  final double masterTruePeak;
  /// Stereo correlation (-1.0 = out of phase, 0.0 = uncorrelated, 1.0 = mono)
  final double correlation;
  /// Stereo balance (-1.0 = full left, 0.0 = center, 1.0 = full right)
  final double stereoBalance;
  /// Dynamic range (peak - RMS in dB)
  final double dynamicRange;
  /// Spectrum data (256 bins, normalized 0-1, log-scaled 20Hz-20kHz)
  final Float32List spectrum;
  final double cpuUsage;
  final int bufferUnderruns;
  final List<BusMeteringState> buses;

  MeteringState({
    required this.masterPeakL,
    required this.masterPeakR,
    required this.masterRmsL,
    required this.masterRmsR,
    required this.masterLufsM,
    required this.masterLufsS,
    required this.masterLufsI,
    required this.masterTruePeak,
    this.correlation = 1.0,
    this.stereoBalance = 0.0,
    this.dynamicRange = 0.0,
    Float32List? spectrum,
    required this.cpuUsage,
    required this.bufferUnderruns,
    this.buses = const [],
  }) : spectrum = spectrum ?? Float32List(256);

  factory MeteringState.empty() => MeteringState(
    masterPeakL: -60.0,
    masterPeakR: -60.0,
    masterRmsL: -60.0,
    masterRmsR: -60.0,
    masterLufsM: -60.0,
    masterLufsS: -60.0,
    masterLufsI: -60.0,
    masterTruePeak: -60.0,
    correlation: 1.0,
    stereoBalance: 0.0,
    dynamicRange: 0.0,
    spectrum: Float32List(256),
    cpuUsage: 0.0,
    bufferUnderruns: 0,
    buses: [],
  );

  /// Get metering for a specific bus
  BusMeteringState? getBus(int index) {
    if (index >= 0 && index < buses.length) {
      return buses[index];
    }
    return null;
  }

  // Compatibility getters for older code
  double get lufsMomentary => masterLufsM;
  double get lufsShortTerm => masterLufsS;
  double get lufsShort => masterLufsS;
  double get lufsIntegrated => masterLufsI;
}

/// Imported clip info (returned from importAudioFile)
class ImportedClipInfo {
  final String clipId;
  final String trackId;
  final String name;
  final double startTime;
  final double duration;
  final double sourceDuration;
  final int sampleRate;
  final int channels;

  const ImportedClipInfo({
    required this.clipId,
    required this.trackId,
    required this.name,
    required this.startTime,
    required this.duration,
    required this.sourceDuration,
    required this.sampleRate,
    required this.channels,
  });
}

/// Project info
class ProjectInfo {
  final String name;
  final int trackCount;
  final int busCount;
  final int sampleRate;
  final double tempo;
  final int timeSigNum;
  final int timeSigDenom;
  final int durationSamples;
  final int createdAt;
  final int modifiedAt;

  const ProjectInfo({
    required this.name,
    required this.trackCount,
    required this.busCount,
    required this.sampleRate,
    required this.tempo,
    required this.timeSigNum,
    required this.timeSigDenom,
    required this.durationSamples,
    required this.createdAt,
    required this.modifiedAt,
  });

  factory ProjectInfo.empty() => ProjectInfo(
    name: 'Untitled Project',
    trackCount: 0,
    busCount: 6,
    sampleRate: 48000,
    tempo: 120.0,
    timeSigNum: 4,
    timeSigDenom: 4,
    durationSamples: 0,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    modifiedAt: DateTime.now().millisecondsSinceEpoch,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADVANCED METERING DATA TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// 8x True Peak data (superior to ITU 4x)
class TruePeak8xData {
  final double peakDbtp;
  final double maxDbtp;
  final double holdDbtp;
  final bool isClipping;

  const TruePeak8xData({
    required this.peakDbtp,
    required this.maxDbtp,
    required this.holdDbtp,
    required this.isClipping,
  });

  factory TruePeak8xData.empty() => const TruePeak8xData(
    peakDbtp: -60.0,
    maxDbtp: -60.0,
    holdDbtp: -60.0,
    isClipping: false,
  );
}

/// PSR (Peak-to-Short-term Ratio) data
class PsrData {
  final double psrDb;
  final double shortTermLufs;
  final double truePeakDbtp;
  final String assessment;

  const PsrData({
    required this.psrDb,
    required this.shortTermLufs,
    required this.truePeakDbtp,
    required this.assessment,
  });

  factory PsrData.empty() => const PsrData(
    psrDb: 0.0,
    shortTermLufs: -23.0,
    truePeakDbtp: -60.0,
    assessment: 'No Signal',
  );
}

/// Crest Factor data
class CrestFactorData {
  final double crestDb;
  final double crestRatio;
  final String assessment;

  const CrestFactorData({
    required this.crestDb,
    required this.crestRatio,
    required this.assessment,
  });

  factory CrestFactorData.empty() => const CrestFactorData(
    crestDb: 0.0,
    crestRatio: 1.0,
    assessment: 'No Signal',
  );
}

/// Psychoacoustic data (Zwicker loudness model)
class PsychoacousticData {
  final double loudnessSones;
  final double loudnessPhons;
  final double sharpnessAcum;
  final double fluctuationVacil;
  final double roughnessAsper;
  final List<double> specificLoudness;

  const PsychoacousticData({
    required this.loudnessSones,
    required this.loudnessPhons,
    required this.sharpnessAcum,
    required this.fluctuationVacil,
    required this.roughnessAsper,
    required this.specificLoudness,
  });

  factory PsychoacousticData.empty() => PsychoacousticData(
    loudnessSones: 0.0,
    loudnessPhons: 0.0,
    sharpnessAcum: 0.0,
    fluctuationVacil: 0.0,
    roughnessAsper: 0.0,
    specificLoudness: List.filled(24, 0.0),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADVANCED METERING FFI FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get 8x True Peak data
TruePeak8xData advancedGetTruePeak8x() {
  try {
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      // Call FFI when available
      return ffi.advancedGetTruePeak8x();
    }
  } catch (e) {
    // FFI not available
  }
  return TruePeak8xData.empty();
}

/// Get PSR data
PsrData advancedGetPsr() {
  try {
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      return ffi.advancedGetPsr();
    }
  } catch (e) {
    // FFI not available
  }
  return PsrData.empty();
}

/// Get Crest Factor data
CrestFactorData advancedGetCrestFactor() {
  try {
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      return ffi.advancedGetCrestFactor();
    }
  } catch (e) {
    // FFI not available
  }
  return CrestFactorData.empty();
}

/// Get Psychoacoustic data
PsychoacousticData advancedGetPsychoacoustic() {
  try {
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      return ffi.advancedGetPsychoacoustic();
    }
  } catch (e) {
    // FFI not available
  }
  return PsychoacousticData.empty();
}

/// Initialize advanced meters
void advancedInitMeters(double sampleRate) {
  try {
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.advancedInitMeters(sampleRate);
    }
  } catch (e) {
    // FFI not available
  }
}

/// Reset all advanced meters
void advancedResetAll() {
  try {
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.advancedResetAll();
    }
  } catch (e) {
    // FFI not available
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO DEVICE ENUMERATION
// ═══════════════════════════════════════════════════════════════════════════

/// Audio device information
class AudioDeviceInfo {
  final String name;
  final bool isDefault;
  final int channels;
  final List<int> supportedSampleRates;

  AudioDeviceInfo({
    required this.name,
    required this.isDefault,
    required this.channels,
    required this.supportedSampleRates,
  });
}

/// Get list of available output devices
List<AudioDeviceInfo> audioGetOutputDevices() {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return [];

    final count = ffi.audioGetOutputDeviceCount();
    if (count <= 0) return [];

    final devices = <AudioDeviceInfo>[];
    for (int i = 0; i < count; i++) {
      final namePtr = ffi.audioGetOutputDeviceName(i);
      if (namePtr == nullptr) continue;

      final name = namePtr.cast<Utf8>().toDartString();
      calloc.free(namePtr);

      final isDefault = ffi.audioIsOutputDeviceDefault(i) != 0;
      final channels = ffi.audioGetOutputDeviceChannels(i);

      // Get supported sample rates
      final rateCount = ffi.audioGetOutputDeviceSampleRateCount(i);
      final rates = <int>[];
      for (int j = 0; j < rateCount; j++) {
        final rate = ffi.audioGetOutputDeviceSampleRate(i, j);
        if (rate > 0) rates.add(rate);
      }

      devices.add(AudioDeviceInfo(
        name: name,
        isDefault: isDefault,
        channels: channels,
        supportedSampleRates: rates,
      ));
    }

    return devices;
  } catch (e) {
    return [];
  }
}

/// Get list of available input devices
List<AudioDeviceInfo> audioGetInputDevices() {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return [];

    final count = ffi.audioGetInputDeviceCount();
    if (count <= 0) return [];

    final devices = <AudioDeviceInfo>[];
    for (int i = 0; i < count; i++) {
      final namePtr = ffi.audioGetInputDeviceName(i);
      if (namePtr == nullptr) continue;

      final name = namePtr.cast<Utf8>().toDartString();
      calloc.free(namePtr);

      final isDefault = ffi.audioIsInputDeviceDefault(i) != 0;
      final channels = ffi.audioGetInputDeviceChannels(i);

      devices.add(AudioDeviceInfo(
        name: name,
        isDefault: isDefault,
        channels: channels,
        supportedSampleRates: [], // Input devices use output device sample rate
      ));
    }

    return devices;
  } catch (e) {
    return [];
  }
}

/// Get current audio host name (ASIO, CoreAudio, JACK, WASAPI)
String audioGetHostName() {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return 'Unknown';

    final namePtr = ffi.audioGetHostName();
    if (namePtr == nullptr) return 'Unknown';

    final name = namePtr.cast<Utf8>().toDartString();
    calloc.free(namePtr);
    return name;
  } catch (e) {
    return 'Unknown';
  }
}

/// Check if ASIO is available (Windows only)
bool audioIsAsioAvailable() {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return false;
    return ffi.audioIsAsioAvailable() != 0;
  } catch (e) {
    return false;
  }
}

/// Refresh device lists (hot-plug support)
void audioRefreshDevices() {
  try {
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.audioRefreshDevices();
    }
  } catch (e) {
    // FFI not available
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING API
// ═══════════════════════════════════════════════════════════════════════════

/// Set recording output directory
bool recordingSetOutputDir(String path) {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return false;

    final pathPtr = path.toNativeUtf8();
    final result = ffi.recordingSetOutputDir(pathPtr);
    calloc.free(pathPtr);
    return result == 0;
  } catch (e) {
    return false;
  }
}

/// Get recording output directory
String recordingGetOutputDir() {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return '';

    final pathPtr = ffi.recordingGetOutputDir();
    if (pathPtr == nullptr) return '';

    final path = pathPtr.cast<Utf8>().toDartString();
    calloc.free(pathPtr);
    return path;
  } catch (e) {
    return '';
  }
}

/// Arm track for recording
bool recordingArmTrack(int trackId, {int numChannels = 2}) {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return false;
    return ffi.recordingArmTrack(trackId, numChannels) != 0;
  } catch (e) {
    return false;
  }
}

/// Disarm track
bool recordingDisarmTrack(int trackId) {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return false;
    return ffi.recordingDisarmTrack(trackId) != 0;
  } catch (e) {
    return false;
  }
}

/// Start recording on armed track
String? recordingStartTrack(int trackId) {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return null;

    final pathPtr = ffi.recordingStartTrack(trackId);
    if (pathPtr == nullptr) return null;

    final path = pathPtr.cast<Utf8>().toDartString();
    calloc.free(pathPtr);
    return path;
  } catch (e) {
    return null;
  }
}

/// Stop recording on track
String? recordingStopTrack(int trackId) {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return null;

    final pathPtr = ffi.recordingStopTrack(trackId);
    if (pathPtr == nullptr) return null;

    final path = pathPtr.cast<Utf8>().toDartString();
    calloc.free(pathPtr);
    return path;
  } catch (e) {
    return null;
  }
}

/// Start recording on all armed tracks
int recordingStartAll() {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return 0;
    return ffi.recordingStartAll();
  } catch (e) {
    return 0;
  }
}

/// Stop recording on all tracks
int recordingStopAll() {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return 0;
    return ffi.recordingStopAll();
  } catch (e) {
    return 0;
  }
}

/// Check if track is armed
bool recordingIsArmed(int trackId) {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return false;
    return ffi.recordingIsArmed(trackId) != 0;
  } catch (e) {
    return false;
  }
}

/// Check if track is recording
bool recordingIsRecording(int trackId) {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return false;
    return ffi.recordingIsRecording(trackId) != 0;
  } catch (e) {
    return false;
  }
}

/// Get number of armed tracks
int recordingArmedCount() {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return 0;
    return ffi.recordingArmedCount();
  } catch (e) {
    return 0;
  }
}

/// Get number of recording tracks
int recordingRecordingCount() {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return 0;
    return ffi.recordingRecordingCount();
  } catch (e) {
    return 0;
  }
}

/// Clear all recorders
void recordingClearAll() {
  try {
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.recordingClearAll();
    }
  } catch (e) {
    // FFI not available
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Export/Bounce System
// ═══════════════════════════════════════════════════════════════════════════

/// Audio export format
enum ExportFormat {
  wav(0),
  flac(1),
  mp3(2);

  final int value;
  const ExportFormat(this.value);
}

/// Audio bit depth
enum ExportBitDepth {
  int16(16),
  int24(24),
  float32(32);

  final int bits;
  const ExportBitDepth(this.bits);
}

/// Bounce progress information
class BounceProgress {
  final double percent;
  final double speedFactor;
  final double etaSecs;
  final double peakLevel;
  final bool isComplete;
  final bool wasCancelled;

  const BounceProgress({
    required this.percent,
    required this.speedFactor,
    required this.etaSecs,
    required this.peakLevel,
    required this.isComplete,
    required this.wasCancelled,
  });

  @override
  String toString() =>
      'BounceProgress(percent: ${percent.toStringAsFixed(1)}%, speed: ${speedFactor.toStringAsFixed(1)}x, eta: ${etaSecs.toStringAsFixed(1)}s, peak: ${peakLevel.toStringAsFixed(3)})';
}

/// Start export/bounce
/// Returns true on success
bool bounceStart({
  required String outputPath,
  ExportFormat format = ExportFormat.wav,
  ExportBitDepth bitDepth = ExportBitDepth.int24,
  int sampleRate = 0, // 0 = project rate
  required double startTime,
  required double endTime,
  bool normalize = false,
  double normalizeTarget = -0.1,
}) {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return false;

    final result = ffi.bounceStart(
      outputPath,
      format.value,
      bitDepth.bits,
      sampleRate,
      startTime,
      endTime,
      normalize,
      normalizeTarget,
    );

    return result != 0;
  } catch (e) {
    return false;
  }
}

/// Get current bounce progress
BounceProgress bounceGetProgress() {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) {
      return const BounceProgress(
        percent: 0,
        speedFactor: 1.0,
        etaSecs: 0,
        peakLevel: 0,
        isComplete: false,
        wasCancelled: false,
      );
    }

    return BounceProgress(
      percent: ffi.bounceGetProgress(),
      speedFactor: ffi.bounceGetSpeedFactor(),
      etaSecs: ffi.bounceGetEta(),
      peakLevel: ffi.bounceGetPeakLevel(),
      isComplete: ffi.bounceIsComplete(),
      wasCancelled: ffi.bounceWasCancelled(),
    );
  } catch (e) {
    return const BounceProgress(
      percent: 0,
      speedFactor: 1.0,
      etaSecs: 0,
      peakLevel: 0,
      isComplete: false,
      wasCancelled: false,
    );
  }
}

/// Check if bounce is complete
bool bounceIsComplete() {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return false;
    return ffi.bounceIsComplete();
  } catch (e) {
    return false;
  }
}

/// Check if bounce was cancelled
bool bounceWasCancelled() {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return false;
    return ffi.bounceWasCancelled();
  } catch (e) {
    return false;
  }
}

/// Cancel active bounce
void bounceCancel() {
  try {
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.bounceCancel();
    }
  } catch (e) {
    // FFI not available
  }
}

/// Check if bounce is active
bool bounceIsActive() {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return false;
    return ffi.bounceIsActive();
  } catch (e) {
    return false;
  }

  // Clip FX methods
  void setClipFxChainBypass(String clipId, bool bypass) => _ffi.setClipFxChainBypass(clipId, bypass);
  void clearClipFx(String clipId) => _ffi.clearClipFx(clipId);
  void setClipFxInputGain(String clipId, double db) => _ffi.setClipFxInputGain(clipId, db);
  void setClipFxOutputGain(String clipId, double db) => _ffi.setClipFxOutputGain(clipId, db);
  void setClipFxBypass(String clipId, String slotId, bool bypass) => _ffi.setClipFxBypass(clipId, slotId, bypass);
  void setClipFxGainParams(String clipId, String slotId, double db, double pan) => _ffi.setClipFxGainParams(clipId, slotId, db, pan);
  void setClipFxCompressorParams(String clipId, String slotId, {required double ratio, required double thresholdDb, required double attackMs, required double releaseMs, required double knee}) => _ffi.setClipFxCompressorParams(clipId, slotId, ratio, thresholdDb, attackMs, releaseMs, knee);
  void setClipFxLimiterParams(String clipId, String slotId, double ceilingDb) => _ffi.setClipFxLimiterParams(clipId, slotId, ceilingDb);
  void setClipFxGateParams(String clipId, String slotId, {required double thresholdDb, required double attackMs, required double releaseMs}) => _ffi.setClipFxGateParams(clipId, slotId, thresholdDb, attackMs, releaseMs);
  void setClipFxSaturationParams(String clipId, String slotId, {required double drive, required int type}) => _ffi.setClipFxSaturationParams(clipId, slotId, drive, type);
  void setClipFxWetDry(String clipId, String slotId, double wetDry) => _ffi.setClipFxWetDry(clipId, slotId, wetDry);
}

/// Clear bounce state (call after complete/cancelled)
void bounceClear() {
  try {
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.bounceClear();
    }
  } catch (e) {
    // FFI not available
  }
}

/// Get output path from last bounce
String? bounceGetOutputPath() {
  try {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return null;

    final pathPtr = ffi.bounceGetOutputPath();
    if (pathPtr == nullptr) return null;

    final path = pathPtr.cast<Utf8>().toDartString();
    calloc.free(pathPtr);
    return path;
  } catch (e) {
    return null;
  }
}
