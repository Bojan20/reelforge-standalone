/// FluxForge Studio ML/AI Provider
///
/// State management for ML/AI processing:
/// - Stem separation (HTDemucs)
/// - Neural denoise (DeepFilterNet)
/// - Voice enhancement (aTENNuate)
/// - Model management

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// ML processing mode
enum MlProcessingMode {
  denoise,
  stemSeparation,
  voiceEnhancement,
}

/// ML processing provider
class MlProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // Models
  List<MlModelInfo> _models = [];

  // Processing state
  bool _isProcessing = false;
  double _progress = 0.0;
  String _phase = 'idle';
  String _currentModel = '';
  String? _error;

  // Settings
  MlExecutionProvider _executionProvider = MlExecutionProvider.cpu;
  double _denoiseStrength = 0.7;
  Set<MlStemType> _selectedStems = {
    MlStemType.vocals,
    MlStemType.drums,
    MlStemType.bass,
    MlStemType.other,
  };

  // Polling timer
  Timer? _progressTimer;

  MlProvider(this._ffi) {
    _ffi.mlInit();
    _loadModels();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  // ============ Getters ============

  List<MlModelInfo> get models => _models;
  bool get isProcessing => _isProcessing;
  double get progress => _progress;
  String get phase => _phase;
  String get currentModel => _currentModel;
  String? get error => _error;
  MlExecutionProvider get executionProvider => _executionProvider;
  double get denoiseStrength => _denoiseStrength;
  Set<MlStemType> get selectedStems => _selectedStems;

  /// Check if there was an error
  bool get hasError => _error != null && _error!.isNotEmpty;

  /// Get error message
  String? get errorMessage => _error;

  /// Check if any model is available
  bool get hasAvailableModels => _models.any((m) => m.isAvailable);

  /// Get available models only
  List<MlModelInfo> get availableModels =>
      _models.where((m) => m.isAvailable).toList();

  // ============ Model Management ============

  void _loadModels() {
    _models = _ffi.mlGetAllModels();
    notifyListeners();
  }

  /// Refresh model list
  void refreshModels() {
    _loadModels();
  }

  /// Set execution provider
  void setExecutionProvider(MlExecutionProvider provider) {
    _executionProvider = provider;
    _ffi.mlSetExecutionProvider(provider.code);
    notifyListeners();
  }

  // ============ Denoise ============

  /// Set denoise strength (0.0-1.0)
  void setDenoiseStrength(double strength) {
    _denoiseStrength = strength.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Start neural denoise processing
  Future<bool> startDenoise(String inputPath, String outputPath) async {
    if (_isProcessing) return false;

    _isProcessing = true;
    _progress = 0.0;
    _phase = 'Starting denoise...';
    _currentModel = 'DeepFilterNet3';
    _error = null;
    notifyListeners();

    final success = _ffi.mlDenoiseStart(inputPath, outputPath, _denoiseStrength);

    if (success) {
      _startProgressPolling();
    } else {
      _isProcessing = false;
      _error = 'Failed to start denoise';
      notifyListeners();
    }

    return success;
  }

  // ============ Stem Separation ============

  /// Set selected stems for separation
  void setSelectedStems(Set<MlStemType> stems) {
    _selectedStems = stems;
    notifyListeners();
  }

  /// Toggle stem selection
  void toggleStem(MlStemType stem) {
    if (_selectedStems.contains(stem)) {
      _selectedStems.remove(stem);
    } else {
      _selectedStems.add(stem);
    }
    notifyListeners();
  }

  /// Start stem separation
  Future<bool> startStemSeparation(String inputPath, String outputDir) async {
    if (_isProcessing) return false;
    if (_selectedStems.isEmpty) return false;

    _isProcessing = true;
    _progress = 0.0;
    _phase = 'Starting separation...';
    _currentModel = 'HTDemucs v4';
    _error = null;
    notifyListeners();

    final mask = MlStemType.combineMask(_selectedStems.toList());
    final success = _ffi.mlSeparateStart(inputPath, outputDir, mask);

    if (success) {
      _startProgressPolling();
    } else {
      _isProcessing = false;
      _error = 'Failed to start separation';
      notifyListeners();
    }

    return success;
  }

  // ============ Voice Enhancement ============

  /// Start voice enhancement
  Future<bool> startVoiceEnhancement(String inputPath, String outputPath) async {
    if (_isProcessing) return false;

    _isProcessing = true;
    _progress = 0.0;
    _phase = 'Starting enhancement...';
    _currentModel = 'aTENNuate SSM';
    _error = null;
    notifyListeners();

    final success = _ffi.mlEnhanceVoiceStart(inputPath, outputPath);

    if (success) {
      _startProgressPolling();
    } else {
      _isProcessing = false;
      _error = 'Failed to start enhancement';
      notifyListeners();
    }

    return success;
  }

  // ============ Control ============

  /// Cancel current processing
  void cancel() {
    if (!_isProcessing) return;

    _ffi.mlCancel();
    _progressTimer?.cancel();
    _progressTimer = null;
    _isProcessing = false;
    _progress = 0.0;
    _phase = 'Cancelled';
    notifyListeners();
  }

  /// Reset ML engine
  void reset() {
    _progressTimer?.cancel();
    _progressTimer = null;
    _ffi.mlReset();
    _isProcessing = false;
    _progress = 0.0;
    _phase = 'idle';
    _currentModel = '';
    _error = null;
    notifyListeners();
  }

  // ============ Progress Polling ============

  void _startProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _pollProgress(),
    );
  }

  void _pollProgress() {
    _isProcessing = _ffi.mlIsProcessing();
    _progress = _ffi.mlGetProgress();
    _phase = _ffi.mlGetPhase();
    _currentModel = _ffi.mlGetCurrentModel();
    _error = _ffi.mlGetError();

    if (!_isProcessing) {
      _progressTimer?.cancel();
      _progressTimer = null;
    }

    notifyListeners();
  }
}
