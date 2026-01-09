/// ReelForge Engine API - Native Mode Only
///
/// High-level Dart API for the Rust audio engine.

import 'dart:async';
import 'native_ffi.dart';

/// Audio Engine API
///
/// Singleton wrapper for all engine functionality.
class EngineApi {
  static EngineApi? _instance;
  static EngineApi get instance => _instance ??= EngineApi._();

  bool _initialized = false;
  bool _audioStarted = false;
  final NativeFFI _ffi = NativeFFI.instance;

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

    return true;
  }

  /// Start real audio playback engine
  Future<void> startAudioPlayback() async {
    if (_audioStarted) return;

    try {
      _ffi.startPlayback();
      print('[Engine] Audio playback started via FFI');
      _audioStarted = true;
    } catch (e) {
      print('[Engine] Audio playback failed: $e');
      rethrow;
    }
  }

  /// Play
  void play() => _ffi.play();

  /// Pause
  void pause() => _ffi.pause();

  /// Stop
  void stop() => _ffi.stop();

  /// Toggle record
  void toggleRecord() => _ffi.toggleRecord();

  /// Seek to position
  void seek(double seconds) => _ffi.seek(seconds);

  /// Set tempo
  void setTempo(double bpm) => _ffi.setTempo(bpm);
}
