// Mastering Provider
//
// State management for AI mastering engine:
// - Preset selection
// - Loudness targeting
// - Reference track matching
// - Processing progress
// - Results display

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// ============ Types ============

/// Mastering preset targets
enum MasteringPreset {
  cdLossless,     // -11 LUFS, -0.3 dBTP
  streaming,      // -14 LUFS, -1.0 dBTP
  appleMusic,     // -16 LUFS, -1.0 dBTP
  broadcast,      // -23 LUFS, -1.0 dBTP
  club,           // -8 LUFS, -0.5 dBTP
  vinyl,          // -12 LUFS, -1.0 dBTP
  podcast,        // -16 LUFS, -1.0 dBTP
  film,           // -24 LUFS, -2.0 dBTP
}

/// Detected genre from analysis
enum DetectedGenre {
  unknown,
  electronic,
  hipHop,
  rock,
  pop,
  classical,
  jazz,
  acoustic,
  rnb,
  speech,
}

/// Mastering result
class MasteringResult {
  final double inputLufs;
  final double outputLufs;
  final double inputPeak;
  final double outputPeak;
  final double appliedGain;
  final double peakReduction;
  final double qualityScore;
  final DetectedGenre detectedGenre;
  final List<String> warnings;
  final List<String> chainSummary;

  const MasteringResult({
    this.inputLufs = -23.0,
    this.outputLufs = -14.0,
    this.inputPeak = -3.0,
    this.outputPeak = -1.0,
    this.appliedGain = 0.0,
    this.peakReduction = 0.0,
    this.qualityScore = 100.0,
    this.detectedGenre = DetectedGenre.unknown,
    this.warnings = const [],
    this.chainSummary = const [],
  });

  /// Loudness correction applied (positive = louder)
  double get loudnessCorrection => outputLufs - inputLufs;

  /// Is result good quality (>80%)
  bool get isGoodQuality => qualityScore >= 80.0;

  /// Has warnings
  bool get hasWarnings => warnings.isNotEmpty;
}

/// Processing state
enum MasteringState {
  idle,
  analyzing,
  processing,
  complete,
  error,
}

// ============ Provider ============

/// Mastering engine provider
class MasteringProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // State
  MasteringState _state = MasteringState.idle;
  MasteringPreset _preset = MasteringPreset.streaming;
  double _targetLufs = -14.0;
  double _targetPeak = -1.0;
  double _progress = 0.0;
  String? _errorMessage;
  MasteringResult? _result;
  bool _isActive = true;

  // Reference
  String? _referenceName;
  bool _hasReference = false;

  // Realtime metering
  double _gainReduction = 0.0;
  double _inputLufs = -100.0;
  double _outputLufs = -100.0;

  // Getters
  MasteringState get state => _state;
  MasteringPreset get preset => _preset;
  double get targetLufs => _targetLufs;
  double get targetPeak => _targetPeak;
  double get progress => _progress;
  String? get errorMessage => _errorMessage;
  MasteringResult? get result => _result;
  bool get isActive => _isActive;
  String? get referenceName => _referenceName;
  bool get hasReference => _hasReference;
  double get gainReduction => _gainReduction;
  double get inputLufs => _inputLufs;
  double get outputLufs => _outputLufs;

  /// Is currently processing
  bool get isProcessing =>
      _state == MasteringState.analyzing || _state == MasteringState.processing;

  /// Is complete
  bool get isComplete => _state == MasteringState.complete;

  /// Has error
  bool get hasError => _state == MasteringState.error;

  MasteringProvider({NativeFFI? ffi}) : _ffi = ffi ?? NativeFFI.instance;

  /// Initialize mastering engine
  Future<void> initialize({int sampleRate = 48000}) async {
    if (!_ffi.isLoaded) return;
    _ffi.masteringEngineInit(sampleRate);
    _applyPreset(_preset);
    notifyListeners();
  }

  /// Set mastering preset
  void setPreset(MasteringPreset preset) {
    _preset = preset;
    _applyPreset(preset);
    notifyListeners();
  }

  void _applyPreset(MasteringPreset preset) {
    if (!_ffi.isLoaded) return;

    _ffi.masteringSetPreset(preset.index);

    // Update local targets based on preset
    switch (preset) {
      case MasteringPreset.cdLossless:
        _targetLufs = -11.0;
        _targetPeak = -0.3;
      case MasteringPreset.streaming:
        _targetLufs = -14.0;
        _targetPeak = -1.0;
      case MasteringPreset.appleMusic:
        _targetLufs = -16.0;
        _targetPeak = -1.0;
      case MasteringPreset.broadcast:
        _targetLufs = -23.0;
        _targetPeak = -1.0;
      case MasteringPreset.club:
        _targetLufs = -8.0;
        _targetPeak = -0.5;
      case MasteringPreset.vinyl:
        _targetLufs = -12.0;
        _targetPeak = -1.0;
      case MasteringPreset.podcast:
        _targetLufs = -16.0;
        _targetPeak = -1.0;
      case MasteringPreset.film:
        _targetLufs = -24.0;
        _targetPeak = -2.0;
    }
  }

  /// Set custom loudness target
  void setLoudnessTarget({double? lufs, double? peak, double? lra}) {
    if (lufs != null) _targetLufs = lufs;
    if (peak != null) _targetPeak = peak;

    if (_ffi.isLoaded) {
      _ffi.masteringSetLoudnessTarget(
        _targetLufs.toDouble(),
        _targetPeak.toDouble(),
        lra ?? 0.0,
      );
    }
    notifyListeners();
  }

  /// Set reference audio for matching
  Future<bool> setReference(String name, Float32List left, Float32List right) async {
    if (!_ffi.isLoaded) return false;

    final result = _ffi.masteringSetReference(name, left, right);
    if (result) {
      _referenceName = name;
      _hasReference = true;
      notifyListeners();
    }
    return result;
  }

  /// Clear reference
  void clearReference() {
    _referenceName = null;
    _hasReference = false;
    notifyListeners();
  }

  /// Process audio offline
  Future<MasteringResult?> processOffline(
    Float32List inputLeft,
    Float32List inputRight,
    Float32List outputLeft,
    Float32List outputRight,
  ) async {
    if (!_ffi.isLoaded) return null;

    _state = MasteringState.processing;
    _progress = 0.0;
    _errorMessage = null;
    notifyListeners();

    try {
      // Process via FFI
      final success = _ffi.masteringProcessOffline(
        inputLeft,
        inputRight,
        outputLeft,
        outputRight,
      );

      if (!success) {
        _state = MasteringState.error;
        _errorMessage = 'Mastering processing failed';
        notifyListeners();
        return null;
      }

      // Get result
      final ffiResult = _ffi.masteringGetResult();

      // Get warnings
      final warnings = <String>[];
      for (int i = 0; i < ffiResult.warningCount; i++) {
        final warning = _ffi.masteringGetWarning(i);
        if (warning != null) warnings.add(warning);
      }

      // Get chain summary
      final chainJson = _ffi.masteringGetChainSummary();
      final chainSummary = <String>[];
      // TODO: parse JSON chain summary

      _result = MasteringResult(
        inputLufs: ffiResult.inputLufs,
        outputLufs: ffiResult.outputLufs,
        inputPeak: ffiResult.inputPeak,
        outputPeak: ffiResult.outputPeak,
        appliedGain: ffiResult.appliedGain,
        peakReduction: ffiResult.peakReduction,
        qualityScore: ffiResult.qualityScore,
        detectedGenre: DetectedGenre.values[ffiResult.detectedGenre.clamp(0, 9)],
        warnings: warnings,
        chainSummary: chainSummary,
      );

      _state = MasteringState.complete;
      _progress = 1.0;
      notifyListeners();

      return _result;
    } catch (e) {
      _state = MasteringState.error;
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Reset state
  void reset() {
    _state = MasteringState.idle;
    _progress = 0.0;
    _errorMessage = null;
    _result = null;

    if (_ffi.isLoaded) {
      _ffi.masteringReset();
    }
    notifyListeners();
  }

  /// Set bypass/active state
  void setActive(bool active) {
    _isActive = active;
    if (_ffi.isLoaded) {
      _ffi.masteringSetActive(active);
    }
    notifyListeners();
  }

  /// Update metering (call from timer)
  void updateMetering() {
    if (!_ffi.isLoaded) return;
    _gainReduction = _ffi.masteringGetGainReduction();
    notifyListeners();
  }

  /// Get preset display name
  static String presetDisplayName(MasteringPreset preset) {
    switch (preset) {
      case MasteringPreset.cdLossless:
        return 'CD / Lossless';
      case MasteringPreset.streaming:
        return 'Streaming (-14 LUFS)';
      case MasteringPreset.appleMusic:
        return 'Apple Music (-16 LUFS)';
      case MasteringPreset.broadcast:
        return 'Broadcast (EBU R128)';
      case MasteringPreset.club:
        return 'Club / DJ';
      case MasteringPreset.vinyl:
        return 'Vinyl';
      case MasteringPreset.podcast:
        return 'Podcast / Voice';
      case MasteringPreset.film:
        return 'Film / Video';
    }
  }

  /// Get preset target info
  static String presetTargetInfo(MasteringPreset preset) {
    switch (preset) {
      case MasteringPreset.cdLossless:
        return '-11 LUFS, -0.3 dBTP';
      case MasteringPreset.streaming:
        return '-14 LUFS, -1.0 dBTP';
      case MasteringPreset.appleMusic:
        return '-16 LUFS, -1.0 dBTP';
      case MasteringPreset.broadcast:
        return '-23 LUFS, -1.0 dBTP';
      case MasteringPreset.club:
        return '-8 LUFS, -0.5 dBTP';
      case MasteringPreset.vinyl:
        return '-12 LUFS, -1.0 dBTP';
      case MasteringPreset.podcast:
        return '-16 LUFS, -1.0 dBTP';
      case MasteringPreset.film:
        return '-24 LUFS, -2.0 dBTP';
    }
  }

  /// Get genre display name
  static String genreDisplayName(DetectedGenre genre) {
    switch (genre) {
      case DetectedGenre.unknown:
        return 'Unknown';
      case DetectedGenre.electronic:
        return 'Electronic';
      case DetectedGenre.hipHop:
        return 'Hip Hop';
      case DetectedGenre.rock:
        return 'Rock';
      case DetectedGenre.pop:
        return 'Pop';
      case DetectedGenre.classical:
        return 'Classical';
      case DetectedGenre.jazz:
        return 'Jazz';
      case DetectedGenre.acoustic:
        return 'Acoustic';
      case DetectedGenre.rnb:
        return 'R&B';
      case DetectedGenre.speech:
        return 'Speech';
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
