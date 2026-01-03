/// ReelForge Engine API
///
/// High-level Dart API for the Rust audio engine.
/// Uses mock data when native library is not available.

import 'dart:async';
import 'dart:math';

import 'bridge.dart';

/// Audio Engine API
///
/// Singleton wrapper for all engine functionality.
class EngineApi {
  static EngineApi? _instance;
  static EngineApi get instance => _instance ??= EngineApi._();

  bool _initialized = false;
  bool _useMock = true; // Use mock until native lib is ready

  // State
  TransportState _transport = TransportState.empty();
  MeteringState _metering = MeteringState.empty();
  ProjectInfo _project = ProjectInfo.empty();

  // Streams
  final _transportController = StreamController<TransportState>.broadcast();
  final _meteringController = StreamController<MeteringState>.broadcast();

  Timer? _updateTimer;

  EngineApi._();

  /// Initialize the engine
  Future<bool> init({
    int sampleRate = 48000,
    int blockSize = 256,
    int numBuses = 6,
  }) async {
    if (_initialized) return true;

    try {
      if (!_useMock) {
        await RustBridge.instance.init();
        // Call native engine_init
      }

      _initialized = true;

      // Start update timer for metering/transport
      _startUpdateTimer();

      return true;
    } catch (e) {
      print('Engine init failed: $e');
      // Fall back to mock mode
      _useMock = true;
      _initialized = true;
      _startUpdateTimer();
      return true;
    }
  }

  /// Shutdown the engine
  void shutdown() {
    _updateTimer?.cancel();
    _initialized = false;
    _transportController.close();
    _meteringController.close();
  }

  /// Check if engine is running
  bool get isRunning => _initialized;

  // ═══════════════════════════════════════════════════════════════════════════
  // TRANSPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get current transport state
  TransportState get transport => _transport;

  /// Transport state stream
  Stream<TransportState> get transportStream => _transportController.stream;

  /// Start playback
  void play() {
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
    _transport = TransportState(
      isPlaying: _transport.isPlaying,
      isRecording: _transport.isRecording,
      positionSamples: _transport.positionSamples,
      positionSeconds: _transport.positionSeconds,
      tempo: _transport.tempo,
      timeSigNum: _transport.timeSigNum,
      timeSigDenom: _transport.timeSigDenom,
      loopEnabled: !_transport.loopEnabled,
      loopStart: _transport.loopStart,
      loopEnd: _transport.loopEnd,
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
  Future<void> saveProject(String path) async {
    // TODO: Call native save
    print('Saving project to: $path');
  }

  /// Load project
  Future<void> loadProject(String path) async {
    // TODO: Call native load
    print('Loading project from: $path');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UNDO/REDO
  // ═══════════════════════════════════════════════════════════════════════════

  bool _canUndo = false;
  bool _canRedo = false;

  bool get canUndo => _canUndo;
  bool get canRedo => _canRedo;

  void undo() {
    // TODO: Call native undo
    print('Undo');
  }

  void redo() {
    // TODO: Call native redo
    print('Redo');
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

    // Update transport position if playing
    if (_transport.isPlaying) {
      final newSeconds = _transport.positionSeconds + 0.016; // ~60fps
      final sampleRate = _project.sampleRate;

      // Handle loop
      double finalSeconds = newSeconds;
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

    // Update metering with mock data
    if (_useMock) {
      final random = Random();
      final activity = _transport.isPlaying ? 1.0 : 0.1;

      _metering = MeteringState(
        masterPeakL: -12.0 + random.nextDouble() * 6 * activity - (1 - activity) * 30,
        masterPeakR: -12.0 + random.nextDouble() * 6 * activity - (1 - activity) * 30,
        masterRmsL: -18.0 + random.nextDouble() * 4 * activity - (1 - activity) * 30,
        masterRmsR: -18.0 + random.nextDouble() * 4 * activity - (1 - activity) * 30,
        masterLufsM: -14.0 + random.nextDouble() * 2 * activity - (1 - activity) * 30,
        masterLufsS: -14.0 + random.nextDouble() * 1 * activity - (1 - activity) * 30,
        masterLufsI: -14.0,
        masterTruePeak: -6.0 + random.nextDouble() * 3 * activity - (1 - activity) * 30,
        cpuUsage: 5.0 + random.nextDouble() * 3,
        bufferUnderruns: 0,
      );
      _meteringController.add(_metering);
    }
  }
}

/// Global engine instance
final engine = EngineApi.instance;
