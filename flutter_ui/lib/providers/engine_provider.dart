// Engine Provider
//
// Central hub connecting Flutter providers to the Rust audio engine.
// Manages:
// - Engine lifecycle (init, shutdown)
// - State synchronization (transport, metering, project)
// - Stream subscriptions for real-time updates

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../src/rust/engine_api.dart';
import '../src/rust/native_ffi.dart' hide ProjectInfo;

// ============ Types ============

enum EngineStatus {
  uninitialized,
  initializing,
  running,
  error,
  shutdown,
}

// ============ Provider ============

class EngineProvider extends ChangeNotifier {
  EngineStatus _status = EngineStatus.uninitialized;
  String? _errorMessage;

  // Streams
  StreamSubscription<TransportState>? _transportSub;
  StreamSubscription<MeteringState>? _meteringSub;

  // Current states
  TransportState _transport = TransportState.empty();
  MeteringState _metering = MeteringState.empty();
  ProjectInfo _project = ProjectInfo.empty();

  // DAW-standard: remember where playback started so Stop returns there
  double _playbackStartPosition = 0;
  bool _returnedToStart = true; // true when already at start pos (next stop → 0)

  // PERFORMANCE: Throttle notifyListeners to prevent rebuild storm
  // Transport/metering streams fire at ~60fps, but UI only needs ~20fps
  DateTime _lastNotifyTime = DateTime.now();
  static const _notifyThrottleMs = 50; // 20fps max for UI updates

  // Getters
  EngineStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isRunning => _status == EngineStatus.running;

  TransportState get transport => _transport;
  MeteringState get metering => _metering;
  ProjectInfo get project => _project;
  double get playbackStartPosition => _playbackStartPosition;

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize the engine
  Future<bool> initialize({
    int sampleRate = 48000,
    int blockSize = 256,
    int numBuses = 6,
  }) async {
    if (_status == EngineStatus.running) return true;
    if (_status == EngineStatus.initializing) return false;

    _status = EngineStatus.initializing;
    _errorMessage = null;
    notifyListeners();

    try {
      final success = await engine.init(
        sampleRate: sampleRate,
        blockSize: blockSize,
        numBuses: numBuses,
      );

      if (success) {
        _subscribeToStreams();
        _syncState();

        _status = EngineStatus.running;
        notifyListeners();
        return true;
      } else {
        _status = EngineStatus.error;
        _errorMessage = 'Engine initialization failed';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = EngineStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Shutdown the engine
  void shutdown() {
    _transportSub?.cancel();
    _meteringSub?.cancel();
    engine.shutdown();

    _status = EngineStatus.shutdown;
    notifyListeners();
  }

  /// PERFORMANCE: Throttled notify - prevents 60fps rebuild storm
  void _throttledNotify() {
    final now = DateTime.now();
    if (now.difference(_lastNotifyTime).inMilliseconds >= _notifyThrottleMs) {
      _lastNotifyTime = now;
      notifyListeners();
    }
  }

  void _subscribeToStreams() {
    _transportSub?.cancel();
    _meteringSub?.cancel();

    _transportSub = engine.transportStream.listen((state) {
      _transport = state;
      // PERFORMANCE: Throttled to ~20fps to prevent rebuild storm
      _throttledNotify();
    });

    _meteringSub = engine.meteringStream.listen((state) {
      _metering = state;
      // PERFORMANCE: Metering updates don't need to notify at all
      // MeterProvider has its own stream subscription
      // Only notify on significant changes (not every frame)
    });
  }

  void _syncState() {
    _transport = engine.transport;
    _metering = engine.metering;
    _project = engine.project;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRANSPORT CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  void play() {
    if (!isRunning) return;
    // DAW-standard: remember cursor position before playback starts
    _playbackStartPosition = _transport.positionSeconds;
    _returnedToStart = false;
    engine.play();
    // INSTANT: Force immediate UI update - no throttle for play
    _transport = engine.transport;
    notifyListeners();
  }

  /// DAW-standard Stop behavior (Cubase / Logic Pro X):
  /// - 1st stop: return playhead to where playback started
  /// - 2nd stop: return playhead to absolute 0
  void stop() {
    if (!isRunning) return;
    final wasPlaying = _transport.isPlaying;
    engine.stop();

    if (wasPlaying) {
      // Was playing → return to playback start position
      engine.setPosition(_playbackStartPosition);
      _returnedToStart = false;
    } else if (!_returnedToStart) {
      // Already stopped, first extra stop → return to start position
      engine.setPosition(_playbackStartPosition);
      _returnedToStart = true;
    } else {
      // Already at start position → go to absolute 0
      engine.setPosition(0);
      _playbackStartPosition = 0;
    }

    // INSTANT: Force immediate UI update - no throttle for stop
    _transport = engine.transport;
    notifyListeners();
  }

  /// Go to absolute start (position 0) — resets playback start marker
  void goToStart() {
    if (!isRunning) return;
    engine.stop();
    engine.setPosition(0);
    _playbackStartPosition = 0;
    _returnedToStart = true;
    _transport = engine.transport;
    notifyListeners();
  }

  void pause() {
    if (!isRunning) return;
    engine.pause();
    // INSTANT: Force immediate UI update - no throttle for pause
    _transport = engine.transport;
    notifyListeners();
  }

  void toggleRecord() {
    if (!isRunning) return;
    engine.toggleRecord();
  }

  // Scrubbing state
  bool _isScrubbing = false;
  DateTime _lastScrubTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _scrubThrottleDuration = Duration(milliseconds: 50);

  bool get isScrubbing => _isScrubbing;

  void seek(double seconds, {bool isScrubbing = false}) {
    if (!isRunning) return;

    if (isScrubbing) {
      // Throttle scrub seeks to prevent overwhelming the audio engine
      final now = DateTime.now();
      if (now.difference(_lastScrubTime) < _scrubThrottleDuration) {
        return; // Skip this seek, too soon after last one
      }
      _lastScrubTime = now;
    }

    engine.setPosition(seconds);
    // INSTANT: Force immediate UI update — playhead must jump instantly on click
    _transport = engine.transport;
    notifyListeners();
  }

  /// Start scrubbing mode
  void startScrubbing() {
    _isScrubbing = true;
    notifyListeners();
  }

  /// End scrubbing mode
  void endScrubbing() {
    _isScrubbing = false;
    notifyListeners();
  }

  /// Scrub seek with throttling
  void scrubSeek(double seconds) {
    seek(seconds, isScrubbing: true);
  }

  /// Jog wheel / fine adjustment
  /// [delta] - scroll delta (positive = forward, negative = backward)
  /// [sensitivity] - seconds per scroll unit
  void jogSeek(double delta, {double sensitivity = 0.1}) {
    if (!isRunning) return;
    final currentPos = _transport.positionSeconds;
    final newPos = (currentPos + delta * sensitivity).clamp(0.0, double.infinity);
    seek(newPos, isScrubbing: true);
  }

  void setTempo(double bpm) {
    if (!isRunning) return;
    engine.setTempo(bpm);
    // Sync metronome click tempo via FFI
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.clickSetTempo(bpm);
    }
    // Force immediate UI update
    _transport = engine.transport;
    notifyListeners();
  }

  void setTimeSignature(int numerator, int denominator) {
    if (!isRunning) return;
    engine.setTimeSignature(numerator, denominator);
  }

  void toggleLoop() {
    if (!isRunning) return;
    engine.toggleLoop();
    // Force immediate UI update (stream may have slight delay)
    _transport = engine.transport;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROJECT MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  void newProject(String name) {
    if (!isRunning) return;
    engine.newProject(name);
    _project = engine.project;
    notifyListeners();
  }

  Future<bool> saveProject(String path) async {
    if (!isRunning) return false;
    final success = await engine.saveProject(path);
    if (success) notifyListeners();
    return success;
  }

  Future<bool> loadProject(String path) async {
    if (!isRunning) return false;
    final success = await engine.loadProject(path);
    if (success) {
      _project = engine.project;
      notifyListeners();
    }
    return success;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UNDO/REDO
  // ═══════════════════════════════════════════════════════════════════════════

  bool get canUndo => engine.canUndo;
  bool get canRedo => engine.canRedo;

  void undo() {
    if (!isRunning) return;
    engine.undo();
    notifyListeners();
  }

  void redo() {
    if (!isRunning) return;
    engine.redo();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLIP OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Normalize clip to target dB level
  bool normalizeClip(String clipId, {double targetDb = -3.0}) {
    if (!isRunning) return false;
    return engine.normalizeClip(clipId, targetDb: targetDb);
  }

  /// Reverse clip audio
  bool reverseClip(String clipId) {
    if (!isRunning) return false;
    return engine.reverseClip(clipId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _transportSub?.cancel();
    _meteringSub?.cancel();
    super.dispose();
  }
}
