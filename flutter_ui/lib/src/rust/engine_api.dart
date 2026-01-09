/// ReelForge Engine API
///
/// High-level Dart API for the Rust audio engine.
/// Uses mock data when native library is not available.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'native_ffi.dart';

/// Audio Engine API
///
/// Singleton wrapper for all engine functionality.
class EngineApi {
  static EngineApi? _instance;
  static EngineApi get instance => _instance ??= EngineApi._();

  bool _initialized = false;
  bool _useMock = false; // Native library mode - no mock
  bool _audioStarted = false; // Track if real audio playback is running
  final NativeFFI _ffi = NativeFFI.instance;

  // State
  TransportState _transport = TransportState.empty();
  MeteringState _metering = MeteringState.empty();
  ProjectInfo _project = ProjectInfo.empty();

  // Active buses for metering (index -> activity level 0-1)
  // 0=Master, 1=Music, 2=SFX, 3=Voice, 4=Ambience, 5=UI
  final Map<int, double> _activeBuses = {};

  // Mock volume state (used when native FFI not available)
  double _mockMasterVolume = 1.0; // 0-1.5 linear
  final Map<int, double> _mockTrackVolumes = {}; // trackId -> volume
  final Map<int, double> _mockBusVolumes = {}; // busIndex -> volume

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

    // Load native library - required, no fallback to mock
    if (!_ffi.tryLoad()) {
      throw Exception('[Engine] FATAL: Native library failed to load. Cannot continue.');
    }
    _useMock = false;
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
      if (!_useMock) {
        _ffi.startPlayback();
        print('[Engine] Audio playback started via FFI');
      } else {
        print('[Engine] Audio playback ready (mock mode)');
      }
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
      if (!_useMock) {
        _ffi.stopPlayback();
        print('[Engine] Audio playback stopped via FFI');
      }
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
  // VOLUME CONTROLS (for mock mode metering)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set master volume (0.0 - 1.5, where 1.0 = 0dB)
  void setMasterVolume(double volume) {
    _mockMasterVolume = volume.clamp(0.0, 1.5);
    if (!_useMock) {
      final db = volume <= 0.0001 ? -60.0 : 20.0 * log(volume) / ln10;
      _ffi.mixerSetMasterVolume(db);
    }
  }

  /// Set track volume (0.0 - 1.5, where 1.0 = 0dB)
  void setTrackVolume(int trackId, double volume) {
    _mockTrackVolumes[trackId] = volume.clamp(0.0, 1.5);
    if (!_useMock) {
      _ffi.setTrackVolume(trackId, volume);
    }
  }

  /// Set track pan (-1.0 to 1.0, where 0.0 = center)
  void setTrackPan(int trackId, double pan) {
    final clampedPan = pan.clamp(-1.0, 1.0);
    if (!_useMock) {
      _ffi.setTrackPan(trackId, clampedPan);
    }
  }

  /// Set bus volume (0.0 - 1.5, where 1.0 = 0dB)
  void setBusVolume(int busIndex, double volume) {
    _mockBusVolumes[busIndex] = volume.clamp(0.0, 1.5);
    if (!_useMock) {
      final db = volume <= 0.0001 ? -60.0 : 20.0 * log(volume) / ln10;
      _ffi.mixerSetBusVolume(busIndex, db);
    }
  }

  /// Set bus pan (-1.0 to 1.0, where 0.0 = center)
  void setBusPan(int busIndex, double pan) {
    final clampedPan = pan.clamp(-1.0, 1.0);
    if (!_useMock) {
      _ffi.mixerSetBusPan(busIndex, clampedPan);
    }
  }

  /// Get current master volume
  double get mockMasterVolume => _mockMasterVolume;

  // ═══════════════════════════════════════════════════════════════════════════
  // TRANSPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get current transport state
  TransportState get transport => _transport;

  /// Transport state stream
  Stream<TransportState> get transportStream => _transportController.stream;

  /// Start playback
  void play() {
    if (!_useMock) {
      _ffi.play();
    }
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
    if (!_useMock) {
      _ffi.stop();
    }
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
    if (!_useMock) {
      _ffi.pause();
    }
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
    if (!_useMock) {
      _ffi.seek(seconds);
    }
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
    if (!_useMock) {
      _ffi.setLoopEnabled(newLoopEnabled);
      _ffi.syncLoopFromRegion();
    }
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
    if (!_useMock) {
      _ffi.setLoopRegion(start, end);
      _ffi.syncLoopFromRegion();
    }
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
    if (!_useMock) {
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
    }
    // Mock save
    await Future.delayed(const Duration(milliseconds: 100));
    print('[Engine] Project saved (mock)');
    return true;
  }

  /// Load project
  Future<bool> loadProject(String path) async {
    print('[Engine] Loading project from: $path');
    if (!_useMock) {
      final result = _ffi.loadProject(path);
      if (result) {
        // Sync project info from engine
        _ffi.preloadAll();
        print('[Engine] Project loaded via FFI');
        return true;
      }
      return false;
    }
    // Mock load
    await Future.delayed(const Duration(milliseconds: 100));
    print('[Engine] Project loaded (mock)');
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROJECT DIRTY STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if project has unsaved changes
  bool get isProjectModified {
    if (!_useMock) {
      return _ffi.isProjectModified();
    }
    return false; // Mock always clean
  }

  /// Mark project as dirty (has unsaved changes)
  void markProjectDirty() {
    if (!_useMock) {
      _ffi.markProjectDirty();
    }
  }

  /// Mark project as clean (just saved)
  void markProjectClean() {
    if (!_useMock) {
      _ffi.markProjectClean();
    }
  }

  /// Set project file path
  void setProjectFilePath(String? path) {
    if (!_useMock) {
      _ffi.setProjectFilePath(path);
    }
  }

  /// Get project file path
  String? get projectFilePath {
    if (!_useMock) {
      return _ffi.getProjectFilePath();
    }
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
    if (!_useMock) {
      final nativeId = _ffi.createTrack(name, color, busId);
      if (nativeId != 0) {
        print('[Engine] Created track via FFI: $name (id: $nativeId)');
        return nativeId.toString();
      }
    }
    // Fallback to mock
    final id = 'track-${DateTime.now().millisecondsSinceEpoch}';
    print('[Engine] Created track (mock): $name (id: $id)');
    return id;
  }

  /// Delete a track
  void deleteTrack(String trackId) {
    if (!_useMock) {
      final nativeId = int.tryParse(trackId);
      if (nativeId != null) {
        _ffi.deleteTrack(nativeId);
        print('[Engine] Deleted track via FFI: $trackId');
        return;
      }
    }
    print('[Engine] Deleted track (mock): $trackId');
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
    if (!_useMock) {
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
    print('[Engine] Updated track (mock): $trackId');
  }

  /// Get track peak level for metering (0.0 - 1.0+)
  /// Returns max of L/R for backward compatibility
  double getTrackPeak(int trackId) {
    if (_useMock) return 0.0;
    return _ffi.getTrackPeak(trackId);
  }

  /// Get track stereo peak levels (L, R) by track ID
  /// Returns (peakL, peakR) tuple
  (double, double) getTrackPeakStereo(int trackId) {
    if (_useMock) return (0.0, 0.0);
    return _ffi.getTrackPeakStereo(trackId);
  }

  /// Get track stereo RMS levels (L, R) by track ID
  /// Returns (rmsL, rmsR) tuple
  (double, double) getTrackRmsStereo(int trackId) {
    if (_useMock) return (0.0, 0.0);
    return _ffi.getTrackRmsStereo(trackId);
  }

  /// Get track correlation by track ID (-1.0 to 1.0)
  double getTrackCorrelation(int trackId) {
    if (_useMock) return 1.0;
    return _ffi.getTrackCorrelation(trackId);
  }

  /// Get full track meter data (peakL, peakR, rmsL, rmsR, correlation)
  ({double peakL, double peakR, double rmsL, double rmsR, double correlation}) getTrackMeter(int trackId) {
    if (_useMock) return (peakL: 0.0, peakR: 0.0, rmsL: 0.0, rmsR: 0.0, correlation: 1.0);
    return _ffi.getTrackMeter(trackId);
  }

  /// Get all track peak levels at once (more efficient for UI metering)
  /// Returns map of track_id -> peak value (max of L/R for backward compat)
  Map<int, double> getAllTrackPeaks(int maxTracks) {
    if (_useMock) return {};
    return _ffi.getAllTrackPeaks(maxTracks);
  }

  /// Get all track stereo meters at once (most efficient for UI)
  /// Returns map of track_id -> TrackMeterData
  Map<int, ({double peakL, double peakR, double rmsL, double rmsR, double correlation})> getAllTrackMeters(int maxTracks) {
    if (_useMock) return {};
    return _ffi.getAllTrackMeters(maxTracks);
  }

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

    if (!_useMock) {
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
    }

    // Fallback to mock
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
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        final peaks = _ffi.getWaveformPeaks(nativeClipId, lodLevel: lodLevel);
        if (peaks.isNotEmpty) {
          return peaks;
        }
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
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      final nativeTrackId = int.tryParse(targetTrackId);
      if (nativeClipId != null && nativeTrackId != null) {
        _ffi.moveClip(nativeClipId, nativeTrackId, startTime);
        print('[Engine] Moved clip via FFI: $clipId');
        return;
      }
    }
    print('[Engine] Move clip (mock): $clipId to track $targetTrackId at $startTime');
  }

  /// Resize a clip
  void resizeClip({
    required String clipId,
    required double startTime,
    required double duration,
    required double sourceOffset,
  }) {
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        _ffi.resizeClip(nativeClipId, startTime, duration, sourceOffset);
        print('[Engine] Resized clip via FFI: $clipId');
        return;
      }
    }
    print('[Engine] Resize clip (mock): $clipId');
  }

  /// Split a clip at playhead
  /// Returns new clip ID or null on failure
  String? splitClip({
    required String clipId,
    required double atTime,
  }) {
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        final newId = _ffi.splitClip(nativeClipId, atTime);
        if (newId != 0) {
          print('[Engine] Split clip via FFI: $clipId -> $newId');
          return newId.toString();
        }
      }
    }
    print('[Engine] Split clip (mock): $clipId at $atTime');
    return 'clip-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Duplicate a clip
  /// Returns new clip ID or null on failure
  String? duplicateClip(String clipId) {
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        final newId = _ffi.duplicateClip(nativeClipId);
        if (newId != 0) {
          print('[Engine] Duplicated clip via FFI: $clipId -> $newId');
          return newId.toString();
        }
      }
    }
    print('[Engine] Duplicate clip (mock): $clipId');
    return 'clip-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Delete a clip
  void deleteClip(String clipId) {
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        _ffi.deleteClip(nativeClipId);
        print('[Engine] Deleted clip via FFI: $clipId');
        return;
      }
    }
    print('[Engine] Delete clip (mock): $clipId');
  }

  /// Set clip gain
  void setClipGain(String clipId, double gain) {
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        _ffi.setClipGain(nativeClipId, gain);
        print('[Engine] Set clip gain via FFI: $clipId = $gain');
        return;
      }
    }
    print('[Engine] Set clip gain (mock): $clipId = $gain');
  }

  /// Set clip mute state
  void setClipMuted(String clipId, bool muted) {
    print('[Engine] Set clip $clipId muted to $muted');
  }

  /// Normalize clip to target dB
  bool normalizeClip(String clipId, {double targetDb = -3.0}) {
    print('[Engine] Normalize clip $clipId to $targetDb dB');
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        return _ffi.clipNormalize(nativeClipId, targetDb);
      }
    }
    return true;
  }

  /// Reverse clip audio
  bool reverseClip(String clipId) {
    print('[Engine] Reverse clip $clipId');
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        return _ffi.clipReverse(nativeClipId);
      }
    }
    return true;
  }

  /// Apply fade in to clip
  /// curveType: 0=Linear, 1=EqualPower, 2=SCurve
  bool fadeInClip(String clipId, double durationSec, {int curveType = 1}) {
    print('[Engine] Fade in clip $clipId for $durationSec sec');
    if (!_useMock) {
      final nativeClipId = _parseClipId(clipId);
      if (nativeClipId != null) {
        return _ffi.clipFadeIn(nativeClipId, durationSec, curveType);
      }
    }
    return true;
  }

  /// Apply fade out to clip
  bool fadeOutClip(String clipId, double durationSec, {int curveType = 1}) {
    print('[Engine] Fade out clip $clipId for $durationSec sec');
    if (!_useMock) {
      final nativeClipId = _parseClipId(clipId);
      if (nativeClipId != null) {
        return _ffi.clipFadeOut(nativeClipId, durationSec, curveType);
      }
    }
    return true;
  }

  /// Parse clip ID - native engine clip IDs are integers
  ///
  /// NOTE: "clip-TIMESTAMP-INDEX" format IDs (from mock mode) cannot be
  /// converted to native engine IDs. Only clips imported via importAudioFile
  /// have valid native IDs that can be used for fade, gain, and other operations.
  int? _parseClipId(String clipId) {
    // Native clip IDs are simple integers returned from importAudioFile
    final direct = int.tryParse(clipId);
    if (direct != null) return direct;

    // "clip-TIMESTAMP-INDEX" format does NOT contain native engine IDs
    // The timestamp is NOT a valid clip ID - return null
    // This will cause the operation to fail gracefully in mock mode
    return null;
  }

  /// Apply gain adjustment to clip
  bool applyGainToClip(String clipId, double gainDb) {
    print('[Engine] Apply $gainDb dB gain to clip $clipId');
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        return _ffi.clipApplyGain(nativeClipId, gainDb);
      }
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
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        final slotId = _ffi.addClipFx(nativeClipId, fxType);
        if (slotId != 0) {
          return slotId.toString();
        }
      }
    }
    return 'fxslot-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Remove FX from a clip
  bool removeClipFx(String clipId, String slotId) {
    print('[Engine] Remove FX slot $slotId from clip $clipId');
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.removeClipFx(nativeClipId, nativeSlotId);
      }
    }
    return true;
  }

  /// Bypass/enable a clip FX slot
  bool setClipFxBypass(String clipId, String slotId, bool bypass) {
    print('[Engine] Set FX slot $slotId bypass: $bypass');
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.setClipFxBypass(nativeClipId, nativeSlotId, bypass);
      }
    }
    return true;
  }

  /// Bypass/enable entire clip FX chain
  bool setClipFxChainBypass(String clipId, bool bypass) {
    print('[Engine] Set clip $clipId FX chain bypass: $bypass');
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        return _ffi.setClipFxChainBypass(nativeClipId, bypass);
      }
    }
    return true;
  }

  /// Set clip FX slot wet/dry mix (0.0-1.0)
  bool setClipFxWetDry(String clipId, String slotId, double wetDry) {
    print('[Engine] Set FX slot $slotId wet/dry: $wetDry');
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.setClipFxWetDry(nativeClipId, nativeSlotId, wetDry);
      }
    }
    return true;
  }

  /// Set clip FX chain input gain (dB)
  bool setClipFxInputGain(String clipId, double gainDb) {
    print('[Engine] Set clip $clipId FX input gain: $gainDb dB');
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        return _ffi.setClipFxInputGain(nativeClipId, gainDb);
      }
    }
    return true;
  }

  /// Set clip FX chain output gain (dB)
  bool setClipFxOutputGain(String clipId, double gainDb) {
    print('[Engine] Set clip $clipId FX output gain: $gainDb dB');
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        return _ffi.setClipFxOutputGain(nativeClipId, gainDb);
      }
    }
    return true;
  }

  /// Set Gain FX parameters
  bool setClipFxGainParams(String clipId, String slotId, double db, double pan) {
    print('[Engine] Set Gain FX params: $db dB, pan $pan');
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.setClipFxGainParams(nativeClipId, nativeSlotId, db, pan);
      }
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
    if (!_useMock) {
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
    }
    return true;
  }

  /// Set Limiter FX parameters
  bool setClipFxLimiterParams(String clipId, String slotId, double ceilingDb) {
    print('[Engine] Set Limiter FX ceiling: $ceilingDb dB');
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.setClipFxLimiterParams(nativeClipId, nativeSlotId, ceilingDb);
      }
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
    if (!_useMock) {
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
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.setClipFxSaturationParams(nativeClipId, nativeSlotId, drive, mix);
      }
    }
    return true;
  }

  /// Move FX slot to new position in chain
  bool moveClipFx(String clipId, String slotId, int newIndex) {
    print('[Engine] Move FX slot $slotId to index $newIndex');
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      final nativeSlotId = int.tryParse(slotId);
      if (nativeClipId != null && nativeSlotId != null) {
        return _ffi.moveClipFx(nativeClipId, nativeSlotId, newIndex);
      }
    }
    return true;
  }

  /// Copy FX chain from one clip to another
  bool copyClipFx(String sourceClipId, String targetClipId) {
    print('[Engine] Copy FX from clip $sourceClipId to $targetClipId');
    if (!_useMock) {
      final nativeSourceId = int.tryParse(sourceClipId);
      final nativeTargetId = int.tryParse(targetClipId);
      if (nativeSourceId != null && nativeTargetId != null) {
        return _ffi.copyClipFx(nativeSourceId, nativeTargetId);
      }
    }
    return true;
  }

  /// Clear all FX from a clip
  bool clearClipFx(String clipId) {
    print('[Engine] Clear all FX from clip $clipId');
    if (!_useMock) {
      final nativeClipId = int.tryParse(clipId);
      if (nativeClipId != null) {
        return _ffi.clearClipFx(nativeClipId);
      }
    }
    return true;
  }

  /// Rename a track
  bool renameTrack(String trackId, String name) {
    print('[Engine] Rename track $trackId to "$name"');
    if (!_useMock) {
      final nativeTrackId = int.tryParse(trackId);
      if (nativeTrackId != null) {
        return _ffi.trackRename(nativeTrackId, name);
      }
    }
    return true;
  }

  /// Duplicate a track and return new track ID
  String? duplicateTrack(String trackId) {
    print('[Engine] Duplicate track $trackId');
    if (!_useMock) {
      final nativeTrackId = int.tryParse(trackId);
      if (nativeTrackId != null) {
        final newId = _ffi.trackDuplicate(nativeTrackId);
        if (newId != 0) {
          return newId.toString();
        }
      }
    }
    return 'track-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Set track color
  bool setTrackColor(String trackId, int color) {
    print('[Engine] Set track $trackId color to $color');
    if (!_useMock) {
      final nativeTrackId = int.tryParse(trackId);
      if (nativeTrackId != null) {
        return _ffi.trackSetColor(nativeTrackId, color);
      }
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
    if (!_useMock) {
      final nativeClipAId = int.tryParse(clipAId);
      final nativeClipBId = int.tryParse(clipBId);
      if (nativeClipAId != null && nativeClipBId != null) {
        final xfadeId = _ffi.createCrossfade(nativeClipAId, nativeClipBId, duration, curve);
        if (xfadeId != 0) {
          print('[Engine] Crossfade created via FFI: $xfadeId');
          return xfadeId.toString();
        }
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
    if (!_useMock) {
      final nativeId = int.tryParse(crossfadeId);
      if (nativeId != null) {
        _ffi.deleteCrossfade(nativeId);
        print('[Engine] Crossfade deleted via FFI');
        return;
      }
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
    if (!_useMock) {
      final markerId = _ffi.addMarker(name, time, color);
      if (markerId != 0) {
        print('[Engine] Marker added via FFI: $markerId');
        return markerId.toString();
      }
    }
    return 'marker-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Delete a marker
  void deleteMarker(String markerId) {
    print('[Engine] Delete marker $markerId');
    if (!_useMock) {
      final nativeId = int.tryParse(markerId);
      if (nativeId != null) {
        _ffi.deleteMarker(nativeId);
        print('[Engine] Marker deleted via FFI');
        return;
      }
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
    if (!_useMock) {
      return _ffi.canUndo();
    }
    return false;
  }

  /// Check if redo is available
  bool get canRedo {
    if (!_useMock) {
      return _ffi.canRedo();
    }
    return false;
  }

  /// Undo last action
  bool undo() {
    print('[Engine] Undo');
    if (!_useMock) {
      final result = _ffi.undo();
      if (result) {
        print('[Engine] Undo successful via FFI');
      }
      return result;
    }
    return false;
  }

  /// Redo last undone action
  bool redo() {
    print('[Engine] Redo');
    if (!_useMock) {
      final result = _ffi.redo();
      if (result) {
        print('[Engine] Redo successful via FFI');
      }
      return result;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MEMORY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get memory usage in MB
  double getMemoryUsage() {
    if (!_useMock) {
      return _ffi.getMemoryUsage();
    }
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
        // Handle mock track IDs like 'track-1234567890123'
        if (trackId.startsWith('track-')) {
          // Mock mode - return a stable hash-based ID
          return trackId.hashCode.abs() % 10000 + 100; // Offset to avoid bus collision
        }
        return int.tryParse(trackId);
    }
  }

  /// Set EQ band enabled state
  bool eqSetBandEnabled(String trackId, int bandIndex, bool enabled) {
    print('[Engine] EQ track $trackId band $bandIndex enabled: $enabled');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.eqSetBandEnabled(nativeTrackId, bandIndex, enabled);
      }
    }
    return true;
  }

  /// Set EQ band frequency
  bool eqSetBandFrequency(String trackId, int bandIndex, double frequency) {
    print('[Engine] EQ track $trackId band $bandIndex freq: $frequency Hz');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.eqSetBandFrequency(nativeTrackId, bandIndex, frequency);
      }
    }
    return true;
  }

  /// Set EQ band gain
  bool eqSetBandGain(String trackId, int bandIndex, double gain) {
    print('[Engine] EQ track $trackId band $bandIndex gain: $gain dB');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.eqSetBandGain(nativeTrackId, bandIndex, gain);
      }
    }
    return true;
  }

  /// Set EQ band Q
  bool eqSetBandQ(String trackId, int bandIndex, double q) {
    print('[Engine] EQ track $trackId band $bandIndex Q: $q');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.eqSetBandQ(nativeTrackId, bandIndex, q);
      }
    }
    return true;
  }

  /// Set EQ bypass
  bool eqSetBypass(String trackId, bool bypass) {
    print('[Engine] EQ track $trackId bypass: $bypass');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.eqSetBypass(nativeTrackId, bypass);
      }
    }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEND/RETURN
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set send level (0.0 to 1.0)
  void setSendLevel(String trackId, int sendIndex, double level) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.sendSetLevel(nativeTrackId, sendIndex, level.clamp(0.0, 1.0));
      }
    }
  }

  /// Set send level in dB
  void setSendLevelDb(String trackId, int sendIndex, double db) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.sendSetLevelDb(nativeTrackId, sendIndex, db.clamp(-96.0, 12.0));
      }
    }
  }

  /// Set send muted state
  void setSendMuted(String trackId, int sendIndex, bool muted) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.sendSetMuted(nativeTrackId, sendIndex, muted);
      }
    }
  }

  /// Set send pre/post fader (tap point)
  /// preFader: true = pre-fader (tap point 0), false = post-fader (tap point 1)
  void setSendPreFader(String trackId, int sendIndex, bool preFader) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        // TapPoint: 0=PreFader, 1=PostFader, 2=PostPan
        _ffi.sendSetTapPoint(nativeTrackId, sendIndex, preFader ? 0 : 1);
      }
    }
  }

  /// Set send destination (FX bus index)
  /// destination: 0-3 for FX returns
  void setSendDestination(String trackId, int sendIndex, int destination) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.sendSetDestination(nativeTrackId, sendIndex, destination);
      }
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
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.insertCreateChain(nativeTrackId);
      }
    }
  }

  /// Remove insert chain from a track
  void insertRemoveChain(String trackId) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.insertRemoveChain(nativeTrackId);
      }
    }
  }

  /// Set insert slot bypass state
  void insertSetBypass(String trackId, int slotIndex, bool bypass) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.insertSetBypass(nativeTrackId, slotIndex, bypass);
      }
    }
  }

  /// Set insert slot wet/dry mix (0.0 = dry, 1.0 = wet)
  void insertSetMix(String trackId, int slotIndex, double mix) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.insertSetMix(nativeTrackId, slotIndex, mix.clamp(0.0, 1.0));
      }
    }
  }

  /// Bypass all inserts on a track
  void insertBypassAll(String trackId, bool bypass) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        _ffi.insertBypassAll(nativeTrackId, bypass);
      }
    }
  }

  /// Get total latency of insert chain (in samples)
  int insertGetTotalLatency(String trackId) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.insertGetTotalLatency(nativeTrackId);
      }
    }
    return 0;
  }

  /// Load processor into insert slot
  /// Returns 1 on success, 0 on failure
  int insertLoadProcessor(String trackId, int slotIndex, String processorName) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.insertLoadProcessor(nativeTrackId, slotIndex, processorName);
      }
    }
    return 0;
  }

  /// Unload processor from insert slot
  /// Returns 1 on success, 0 on failure
  int insertUnloadSlot(String trackId, int slotIndex) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.insertUnloadSlot(nativeTrackId, slotIndex);
      }
    }
    return 0;
  }

  /// Set parameter on insert slot processor
  /// Returns 1 on success, 0 on failure
  int insertSetParam(String trackId, int slotIndex, int paramIndex, double value) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.insertSetParam(nativeTrackId, slotIndex, paramIndex, value);
      }
    }
    return 0;
  }

  /// Get parameter from insert slot processor
  double insertGetParam(String trackId, int slotIndex, int paramIndex) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.insertGetParam(nativeTrackId, slotIndex, paramIndex);
      }
    }
    return 0.0;
  }

  /// Check if insert slot has a processor loaded
  bool insertIsLoaded(String trackId, int slotIndex) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.insertIsLoaded(nativeTrackId, slotIndex);
      }
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRO EQ - 64-Band Professional Parametric EQ
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create Pro EQ for a track
  bool proEqCreate(String trackId, {double sampleRate = 48000.0}) {
    print('[Engine] Pro EQ create: $trackId @ ${sampleRate}Hz');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqCreate(nativeTrackId, sampleRate: sampleRate);
      }
    }
    return true;
  }

  /// Destroy Pro EQ for a track
  bool proEqDestroy(String trackId) {
    print('[Engine] Pro EQ destroy: $trackId');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqDestroy(nativeTrackId);
      }
    }
    return true;
  }

  /// Set Pro EQ band enabled
  bool proEqSetBandEnabled(String trackId, int bandIndex, bool enabled) {
    print('[Engine] Pro EQ $trackId band $bandIndex enabled: $enabled');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandEnabled(nativeTrackId, bandIndex, enabled);
      }
    }
    return true;
  }

  /// Set Pro EQ band frequency
  bool proEqSetBandFrequency(String trackId, int bandIndex, double freq) {
    print('[Engine] Pro EQ $trackId band $bandIndex freq: $freq Hz');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandFrequency(nativeTrackId, bandIndex, freq);
      }
    }
    return true;
  }

  /// Set Pro EQ band gain
  bool proEqSetBandGain(String trackId, int bandIndex, double gainDb) {
    print('[Engine] Pro EQ $trackId band $bandIndex gain: $gainDb dB');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandGain(nativeTrackId, bandIndex, gainDb);
      }
    }
    return true;
  }

  /// Set Pro EQ band Q
  bool proEqSetBandQ(String trackId, int bandIndex, double q) {
    print('[Engine] Pro EQ $trackId band $bandIndex Q: $q');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandQ(nativeTrackId, bandIndex, q);
      }
    }
    return true;
  }

  /// Set Pro EQ band shape
  bool proEqSetBandShape(String trackId, int bandIndex, ProEqFilterShape shape) {
    print('[Engine] Pro EQ $trackId band $bandIndex shape: $shape');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandShape(nativeTrackId, bandIndex, shape);
      }
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
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBand(nativeTrackId, bandIndex, freq: freq, gainDb: gainDb, q: q, shape: shape);
      }
    }
    return true;
  }

  /// Set Pro EQ band stereo placement
  bool proEqSetBandPlacement(String trackId, int bandIndex, ProEqPlacement placement) {
    print('[Engine] Pro EQ $trackId band $bandIndex placement: $placement');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandPlacement(nativeTrackId, bandIndex, placement);
      }
    }
    return true;
  }

  /// Set Pro EQ band slope
  bool proEqSetBandSlope(String trackId, int bandIndex, ProEqSlope slope) {
    print('[Engine] Pro EQ $trackId band $bandIndex slope: $slope');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandSlope(nativeTrackId, bandIndex, slope);
      }
    }
    return true;
  }

  /// Enable/disable dynamic EQ for a band
  bool proEqSetBandDynamicEnabled(String trackId, int bandIndex, bool enabled) {
    print('[Engine] Pro EQ $trackId band $bandIndex dynamic enabled: $enabled');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetBandDynamicEnabled(nativeTrackId, bandIndex, enabled);
      }
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
    if (!_useMock) {
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
    if (!_useMock) {
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
    }
    return true;
  }

  /// Set Pro EQ output gain
  bool proEqSetOutputGain(String trackId, double gainDb) {
    print('[Engine] Pro EQ $trackId output gain: $gainDb dB');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetOutputGain(nativeTrackId, gainDb);
      }
    }
    return true;
  }

  /// Set Pro EQ phase mode (0=ZeroLatency, 1=Natural, 2=Linear)
  bool proEqSetPhaseMode(String trackId, int mode) {
    print('[Engine] Pro EQ $trackId phase mode: $mode');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetPhaseMode(nativeTrackId, mode);
      }
    }
    return true;
  }

  /// Set Pro EQ analyzer mode
  bool proEqSetAnalyzerMode(String trackId, ProEqAnalyzerMode mode) {
    print('[Engine] Pro EQ $trackId analyzer: $mode');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetAnalyzerMode(nativeTrackId, mode);
      }
    }
    return true;
  }

  /// Enable/disable Pro EQ auto gain
  bool proEqSetAutoGain(String trackId, bool enabled) {
    print('[Engine] Pro EQ $trackId auto gain: $enabled');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetAutoGain(nativeTrackId, enabled);
      }
    }
    return true;
  }

  /// Enable/disable Pro EQ match mode
  bool proEqSetMatchEnabled(String trackId, bool enabled) {
    print('[Engine] Pro EQ $trackId match: $enabled');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqSetMatchEnabled(nativeTrackId, enabled);
      }
    }
    return true;
  }

  /// Store Pro EQ state A
  bool proEqStoreStateA(String trackId) {
    print('[Engine] Pro EQ $trackId store state A');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqStoreStateA(nativeTrackId);
      }
    }
    return true;
  }

  /// Store Pro EQ state B
  bool proEqStoreStateB(String trackId) {
    print('[Engine] Pro EQ $trackId store state B');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqStoreStateB(nativeTrackId);
      }
    }
    return true;
  }

  /// Recall Pro EQ state A
  bool proEqRecallStateA(String trackId) {
    print('[Engine] Pro EQ $trackId recall state A');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqRecallStateA(nativeTrackId);
      }
    }
    return true;
  }

  /// Recall Pro EQ state B
  bool proEqRecallStateB(String trackId) {
    print('[Engine] Pro EQ $trackId recall state B');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqRecallStateB(nativeTrackId);
      }
    }
    return true;
  }

  /// Get Pro EQ enabled band count
  int proEqGetEnabledBandCount(String trackId) {
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqGetEnabledBandCount(nativeTrackId);
      }
    }
    return 0;
  }

  /// Reset Pro EQ state
  bool proEqReset(String trackId) {
    print('[Engine] Pro EQ $trackId reset');
    if (!_useMock) {
      final nativeTrackId = _trackIdToNative(trackId);
      if (nativeTrackId != null) {
        return _ffi.proEqReset(nativeTrackId);
      }
    }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIXER BUSES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set bus volume (in dB)
  bool mixerSetBusVolume(int busId, double volumeDb) {
    print('[Engine] Bus $busId volume: $volumeDb dB');
    if (!_useMock) {
      return _ffi.mixerSetBusVolume(busId, volumeDb);
    }
    return true;
  }

  /// Set bus mute
  bool mixerSetBusMute(int busId, bool muted) {
    print('[Engine] Bus $busId mute: $muted');
    if (!_useMock) {
      return _ffi.mixerSetBusMute(busId, muted);
    }
    return true;
  }

  /// Set bus solo
  bool mixerSetBusSolo(int busId, bool solo) {
    print('[Engine] Bus $busId solo: $solo');
    if (!_useMock) {
      return _ffi.mixerSetBusSolo(busId, solo);
    }
    return true;
  }

  /// Set bus pan
  bool mixerSetBusPan(int busId, double pan) {
    print('[Engine] Bus $busId pan: $pan');
    if (!_useMock) {
      return _ffi.mixerSetBusPan(busId, pan);
    }
    return true;
  }

  /// Set master volume
  bool mixerSetMasterVolume(double volumeDb) {
    print('[Engine] Master volume: $volumeDb dB');
    if (!_useMock) {
      return _ffi.mixerSetMasterVolume(volumeDb);
    }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VCA FADERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new VCA fader
  /// Returns VCA ID
  int vcaCreate(String name) {
    print('[Engine] Create VCA: $name');
    if (!_useMock) {
      return _ffi.vcaCreate(name);
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  /// Delete a VCA fader
  bool vcaDelete(int vcaId) {
    print('[Engine] Delete VCA: $vcaId');
    if (!_useMock) {
      return _ffi.vcaDelete(vcaId);
    }
    return true;
  }

  /// Set VCA level (0.0 - 1.5, where 1.0 = unity/0dB)
  bool vcaSetLevel(int vcaId, double level) {
    print('[Engine] VCA $vcaId level: $level');
    if (!_useMock) {
      return _ffi.vcaSetLevel(vcaId, level);
    }
    return true;
  }

  /// Get VCA level
  double vcaGetLevel(int vcaId) {
    if (!_useMock) {
      return _ffi.vcaGetLevel(vcaId);
    }
    return 1.0;
  }

  /// Set VCA mute state
  bool vcaSetMute(int vcaId, bool muted) {
    print('[Engine] VCA $vcaId mute: $muted');
    if (!_useMock) {
      return _ffi.vcaSetMute(vcaId, muted);
    }
    return true;
  }

  /// Assign track to VCA
  bool vcaAssignTrack(int vcaId, int trackId) {
    print('[Engine] Assign track $trackId to VCA $vcaId');
    if (!_useMock) {
      return _ffi.vcaAssignTrack(vcaId, trackId);
    }
    return true;
  }

  /// Remove track from VCA
  bool vcaRemoveTrack(int vcaId, int trackId) {
    print('[Engine] Remove track $trackId from VCA $vcaId');
    if (!_useMock) {
      return _ffi.vcaRemoveTrack(vcaId, trackId);
    }
    return true;
  }

  /// Get effective volume for track including VCA contribution
  double vcaGetTrackEffectiveVolume(int trackId, double baseVolume) {
    if (!_useMock) {
      return _ffi.vcaGetTrackEffectiveVolume(trackId, baseVolume);
    }
    return baseVolume;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK GROUPS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new track group
  /// Returns group ID
  int groupCreate(String name) {
    print('[Engine] Create group: $name');
    if (!_useMock) {
      return _ffi.groupCreate(name);
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  /// Delete a track group
  bool groupDelete(int groupId) {
    print('[Engine] Delete group: $groupId');
    if (!_useMock) {
      return _ffi.groupDelete(groupId);
    }
    return true;
  }

  /// Add track to group
  bool groupAddTrack(int groupId, int trackId) {
    print('[Engine] Add track $trackId to group $groupId');
    if (!_useMock) {
      return _ffi.groupAddTrack(groupId, trackId);
    }
    return true;
  }

  /// Remove track from group
  bool groupRemoveTrack(int groupId, int trackId) {
    print('[Engine] Remove track $trackId from group $groupId');
    if (!_useMock) {
      return _ffi.groupRemoveTrack(groupId, trackId);
    }
    return true;
  }

  /// Set group link mode
  /// linkMode: 0=Relative, 1=Absolute
  bool groupSetLinkMode(int groupId, int linkMode) {
    print('[Engine] Group $groupId link mode: $linkMode');
    if (!_useMock) {
      return _ffi.groupSetLinkMode(groupId, linkMode);
    }
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

      if (!_useMock) {
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

    // Update metering with mock data
    if (_useMock) {
      // ONLY show meter activity when audio is playing
      // When stopped, meters should be completely silent (no noise floor)
      if (_transport.isPlaying) {
        final random = Random();

        // Generate bus metering based on active buses
        // Only show activity on buses that have routed audio
        final busMeters = List.generate(
          _project.busCount,
          (i) {
            final activity = _activeBuses[i] ?? 0.0;
            if (activity > 0) {
              return BusMeteringState.mock(random, activity);
            } else {
              return BusMeteringState.empty();
            }
          },
        );

        // Calculate master level from sum of active buses, scaled by master volume
        final hasAnyActivity = _activeBuses.isNotEmpty;
        final masterActivity = hasAnyActivity
            ? _activeBuses.values.reduce((a, b) => a + b).clamp(0.0, 1.0)
            : 0.0;

        // Apply master volume to metering (fader affects meter display)
        final volumeScale = _mockMasterVolume.clamp(0.0, 1.5);
        final volumeDb = volumeScale <= 0.0001 ? -60.0 : 20.0 * log(volumeScale) / ln10;

        if (masterActivity > 0 && volumeScale > 0.001) {
          // Base levels + volume adjustment
          final basePeak = -12.0 + random.nextDouble() * 6 * masterActivity;
          final baseRms = -18.0 + random.nextDouble() * 4 * masterActivity;

          // Stereo correlation: typical stereo content 0.3-0.9, mono = 1.0
          final mockCorrelation = 0.5 + random.nextDouble() * 0.4;
          // Stereo balance: slight L/R imbalance in typical mixes
          final mockBalance = (random.nextDouble() - 0.5) * 0.2;
          // Dynamic range: peak - RMS, typical 6-18dB for music
          final mockDynamicRange = (basePeak - baseRms).abs();

          _metering = MeteringState(
            masterPeakL: (basePeak + volumeDb).clamp(-60.0, 6.0),
            masterPeakR: (basePeak + volumeDb + random.nextDouble() * 0.5).clamp(-60.0, 6.0),
            masterRmsL: (baseRms + volumeDb).clamp(-60.0, 0.0),
            masterRmsR: (baseRms + volumeDb + random.nextDouble() * 0.3).clamp(-60.0, 0.0),
            masterLufsM: -14.0 + volumeDb * 0.5 + random.nextDouble() * 2,
            masterLufsS: -14.0 + volumeDb * 0.5 + random.nextDouble() * 1,
            masterLufsI: -14.0 + volumeDb * 0.5,
            masterTruePeak: (basePeak + volumeDb + 2.0).clamp(-60.0, 6.0),
            correlation: mockCorrelation,
            stereoBalance: mockBalance,
            dynamicRange: mockDynamicRange,
            cpuUsage: 5.0 + random.nextDouble() * 3,
            bufferUnderruns: 0,
            buses: busMeters,
          );
        } else {
          // Playing but no active buses - silence
          _metering = MeteringState(
            masterPeakL: -60.0,
            masterPeakR: -60.0,
            masterRmsL: -60.0,
            masterRmsR: -60.0,
            masterLufsM: -60.0,
            masterLufsS: -60.0,
            masterLufsI: -60.0,
            masterTruePeak: -60.0,
            correlation: 1.0, // Mono when silent
            stereoBalance: 0.0, // Center
            dynamicRange: 0.0,
            cpuUsage: 3.0 + random.nextDouble() * 2,
            bufferUnderruns: 0,
            buses: busMeters,
          );
        }
      } else {
        // Complete silence when not playing - meters at floor
        final busMeters = List.generate(
          _project.busCount,
          (i) => BusMeteringState.empty(),
        );

        _metering = MeteringState(
          masterPeakL: -60.0,
          masterPeakR: -60.0,
          masterRmsL: -60.0,
          masterRmsR: -60.0,
          masterLufsM: -60.0,
          masterLufsS: -60.0,
          masterLufsI: -60.0,
          masterTruePeak: -60.0,
          correlation: 1.0, // Mono when silent
          stereoBalance: 0.0, // Center
          dynamicRange: 0.0,
          cpuUsage: 2.0 + Random().nextDouble() * 2, // CPU still shows small activity
          bufferUnderruns: 0,
          buses: busMeters,
        );
      }
      _meteringController.add(_metering);
    } else {
      // Real metering from native engine
      final (peakL, peakR) = _ffi.getPeakMeters();
      final (rmsL, rmsR) = _ffi.getRmsMeters();
      final (lufsM, lufsS, lufsI) = _ffi.getLufsMeters();
      final (truePeakL, truePeakR) = _ffi.getTruePeakMeters();

      // Convert linear to dB (log10 = log(x) / ln(10))
      double linearToDb(double linear) {
        if (linear <= 0.000001) return -60.0;
        return 20.0 * log(linear.clamp(0.000001, 10.0)) / ln10;
      }

      final masterPeakLDb = linearToDb(peakL);
      final masterPeakRDb = linearToDb(peakR);
      final masterRmsLDb = linearToDb(rmsL);
      final masterRmsRDb = linearToDb(rmsR);

      // Generate bus meters (for now, use master for all buses with audio)
      final busMeters = List.generate(
        _project.busCount,
        (i) {
          final activity = _activeBuses[i] ?? 0.0;
          if (activity > 0) {
            // Scale master meters by bus activity
            return BusMeteringState(
              peakL: masterPeakLDb * activity,
              peakR: masterPeakRDb * activity,
              rmsL: masterRmsLDb * activity,
              rmsR: masterRmsRDb * activity,
              heldPeakL: masterPeakLDb * activity,
              heldPeakR: masterPeakRDb * activity,
            );
          } else {
            return BusMeteringState.empty();
          }
        },
      );

      // Get stereo analysis metering
      final correlation = _ffi.getCorrelation();
      final stereoBalance = _ffi.getStereoBalance();
      final dynamicRange = _ffi.getDynamicRange();
      final spectrum = _ffi.getMasterSpectrum();

      _metering = MeteringState(
        masterPeakL: masterPeakLDb,
        masterPeakR: masterPeakRDb,
        masterRmsL: masterRmsLDb,
        masterRmsR: masterRmsRDb,
        masterLufsM: lufsM, // Real ITU-R BS.1770-4 LUFS
        masterLufsS: lufsS,
        masterLufsI: lufsI,
        masterTruePeak: max(truePeakL, truePeakR), // Real 4x oversampled True Peak
        correlation: correlation,
        stereoBalance: stereoBalance,
        dynamicRange: dynamicRange,
        spectrum: spectrum,
        cpuUsage: 5.0,
        bufferUnderruns: 0,
        buses: busMeters,
      );
      _meteringController.add(_metering);
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
  factory BusMeteringState.mock(Random random, double activity) {
    // Clean mock data - only generate when activity > 0
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
