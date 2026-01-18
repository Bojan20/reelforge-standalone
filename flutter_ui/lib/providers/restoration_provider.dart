/// FluxForge Studio Audio Restoration Provider
///
/// State management for audio restoration:
/// - Denoise (spectral subtraction)
/// - Declick (transient removal)
/// - Declip (clipping reconstruction)
/// - Dehum (hum removal)
/// - Dereverb (reverb suppression)

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// Audio restoration state provider
class RestorationProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // Current settings
  RestorationSettings _settings = RestorationSettings.defaults();

  // Analysis result
  RestorationAnalysis? _analysis;
  List<String> _suggestions = [];

  // Processing state
  bool _isProcessing = false;
  double _progress = 0.0;
  String _phase = 'idle';

  // Active state
  bool _isActive = true;

  // Selected file for processing
  String? _selectedFile;
  String? _outputFile;

  RestorationProvider(this._ffi) {
    _ffi.restorationInit(48000);
  }

  // ============ Getters ============

  RestorationSettings get settings => _settings;
  RestorationAnalysis? get analysis => _analysis;
  List<String> get suggestions => _suggestions;
  bool get isProcessing => _isProcessing;
  double get progress => _progress;
  String get phase => _phase;
  bool get isActive => _isActive;
  String? get selectedFile => _selectedFile;
  String? get outputFile => _outputFile;

  /// Check if any module is enabled
  bool get hasEnabledModules =>
      _settings.denoiseEnabled ||
      _settings.declickEnabled ||
      _settings.declipEnabled ||
      _settings.dehumEnabled ||
      _settings.dereverbEnabled;

  /// Get latency in samples
  int get latencySamples => _ffi.restorationGetLatency();

  // ============ Convenience Getters for Individual Settings ============

  bool get denoiseEnabled => _settings.denoiseEnabled;
  double get denoiseStrength => _settings.denoiseStrength;
  bool get declickEnabled => _settings.declickEnabled;
  double get declickSensitivity => _settings.declickSensitivity;
  bool get declipEnabled => _settings.declipEnabled;
  double get declipThreshold => _settings.declipThreshold;
  bool get dehumEnabled => _settings.dehumEnabled;
  double get dehumFrequency => _settings.dehumFrequency;
  int get dehumHarmonics => _settings.dehumHarmonics;
  bool get dereverbEnabled => _settings.dereverbEnabled;
  double get dereverbAmount => _settings.dereverbAmount;

  // ============ Settings ============

  /// Update all settings at once
  void updateSettings(RestorationSettings settings) {
    _settings = settings;
    _applySettings();
    notifyListeners();
  }

  /// Enable/disable denoise
  void setDenoiseEnabled(bool enabled) {
    _settings = _settings.copyWith(denoiseEnabled: enabled);
    _applySettings();
    notifyListeners();
  }

  /// Set denoise strength (0-100)
  void setDenoiseStrength(double strength) {
    _settings = _settings.copyWith(denoiseStrength: strength.clamp(0, 100));
    _applySettings();
    notifyListeners();
  }

  /// Enable/disable declick
  void setDeclickEnabled(bool enabled) {
    _settings = _settings.copyWith(declickEnabled: enabled);
    _applySettings();
    notifyListeners();
  }

  /// Set declick sensitivity (0-100)
  void setDeclickSensitivity(double sensitivity) {
    _settings = _settings.copyWith(declickSensitivity: sensitivity.clamp(0, 100));
    _applySettings();
    notifyListeners();
  }

  /// Enable/disable declip
  void setDeclipEnabled(bool enabled) {
    _settings = _settings.copyWith(declipEnabled: enabled);
    _applySettings();
    notifyListeners();
  }

  /// Set declip threshold (dB, typically -3 to 0)
  void setDeclipThreshold(double threshold) {
    _settings = _settings.copyWith(declipThreshold: threshold.clamp(-6, 0));
    _applySettings();
    notifyListeners();
  }

  /// Enable/disable dehum
  void setDehumEnabled(bool enabled) {
    _settings = _settings.copyWith(dehumEnabled: enabled);
    _applySettings();
    notifyListeners();
  }

  /// Set dehum frequency (50 or 60 Hz)
  void setDehumFrequency(double frequency) {
    _settings = _settings.copyWith(dehumFrequency: frequency);
    _applySettings();
    notifyListeners();
  }

  /// Set dehum harmonics (2-8)
  void setDehumHarmonics(int harmonics) {
    _settings = _settings.copyWith(dehumHarmonics: harmonics.clamp(2, 8));
    _applySettings();
    notifyListeners();
  }

  /// Enable/disable dereverb
  void setDereverbEnabled(bool enabled) {
    _settings = _settings.copyWith(dereverbEnabled: enabled);
    _applySettings();
    notifyListeners();
  }

  /// Set dereverb amount (0-100)
  void setDereverbAmount(double amount) {
    _settings = _settings.copyWith(dereverbAmount: amount.clamp(0, 100));
    _applySettings();
    notifyListeners();
  }

  void _applySettings() {
    _ffi.restorationSetSettings(
      denoiseEnabled: _settings.denoiseEnabled,
      denoiseStrength: _settings.denoiseStrength,
      declickEnabled: _settings.declickEnabled,
      declickSensitivity: _settings.declickSensitivity,
      declipEnabled: _settings.declipEnabled,
      declipThreshold: _settings.declipThreshold,
      dehumEnabled: _settings.dehumEnabled,
      dehumFrequency: _settings.dehumFrequency,
      dehumHarmonics: _settings.dehumHarmonics,
      dereverbEnabled: _settings.dereverbEnabled,
      dereverbAmount: _settings.dereverbAmount,
    );
  }

  // ============ Analysis ============

  /// Analyze audio file for restoration needs
  Future<void> analyzeFile(String path) async {
    _selectedFile = path;
    _isProcessing = true;
    _phase = 'Analyzing...';
    _progress = 0.0;
    notifyListeners();

    // Run analysis in isolate to avoid blocking UI
    _analysis = await compute(_analyzeInIsolate, _AnalyzeParams(path, _ffi));
    _suggestions = _ffi.restorationGetSuggestions();

    _isProcessing = false;
    _phase = 'Analysis complete';
    _progress = 1.0;
    notifyListeners();
  }

  /// Auto-configure settings based on analysis
  void autoConfigureFromAnalysis() {
    if (_analysis == null) return;

    _settings = RestorationSettings(
      denoiseEnabled: _analysis!.needsDenoise,
      denoiseStrength: _analysis!.needsDenoise ? 60.0 : 50.0,
      declickEnabled: _analysis!.needsDeclick,
      declickSensitivity: _analysis!.needsDeclick ? 70.0 : 50.0,
      declipEnabled: _analysis!.needsDeclip,
      declipThreshold: -0.5,
      dehumEnabled: _analysis!.needsDehum,
      dehumFrequency: _analysis!.humFrequency > 0 ? _analysis!.humFrequency : 50.0,
      dehumHarmonics: 4,
      dereverbEnabled: _analysis!.needsDereverb,
      dereverbAmount: _analysis!.needsDereverb ? 60.0 : 50.0,
    );

    _applySettings();
    notifyListeners();
  }

  // ============ Processing ============

  /// Process file through restoration pipeline
  Future<bool> processFile(String inputPath, String outputPath) async {
    _selectedFile = inputPath;
    _outputFile = outputPath;
    _isProcessing = true;
    _phase = 'Processing...';
    _progress = 0.0;
    notifyListeners();

    // Start processing
    final result = _ffi.restorationProcessFile(inputPath, outputPath);

    // Poll for progress
    while (_isProcessing) {
      final state = _ffi.restorationGetState();
      _isProcessing = state.$1;
      _progress = state.$2;
      _phase = _ffi.restorationGetPhase();
      notifyListeners();

      if (!_isProcessing) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _isProcessing = false;
    _progress = result ? 1.0 : 0.0;
    _phase = result ? 'Complete' : 'Failed';
    notifyListeners();

    return result;
  }

  /// Process audio buffer in real-time
  bool processBuffer(Float32List input, Float32List output) {
    return _ffi.restorationProcess(input, output);
  }

  /// Learn noise profile from selection
  bool learnNoiseProfile(Float32List samples) {
    final success = _ffi.restorationLearnNoiseProfile(samples);
    notifyListeners();
    return success;
  }

  /// Clear learned noise profile
  void clearNoiseProfile() {
    _ffi.restorationClearNoiseProfile();
    notifyListeners();
  }

  // ============ Control ============

  /// Set active/bypass state
  void setActive(bool active) {
    _isActive = active;
    _ffi.restorationSetActive(active);
    notifyListeners();
  }

  /// Toggle active state
  void toggleActive() {
    setActive(!_isActive);
  }

  /// Reset pipeline state
  void reset() {
    _ffi.restorationReset();
    _analysis = null;
    _suggestions.clear();
    _selectedFile = null;
    _outputFile = null;
    _isProcessing = false;
    _progress = 0.0;
    _phase = 'idle';
    notifyListeners();
  }

  /// Reset to default settings
  void resetSettings() {
    _settings = RestorationSettings.defaults();
    _applySettings();
    notifyListeners();
  }
}

// Helper for isolate computation
class _AnalyzeParams {
  final String path;
  final NativeFFI ffi;
  _AnalyzeParams(this.path, this.ffi);
}

RestorationAnalysis? _analyzeInIsolate(_AnalyzeParams params) {
  return params.ffi.restorationAnalyze(params.path);
}
