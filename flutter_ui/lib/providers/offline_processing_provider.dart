// ═══════════════════════════════════════════════════════════════════════════════
// OFFLINE PROCESSING PROVIDER — Direct Offline Processing (DOP)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Provides state management for offline DSP processing:
// - Bounce/mixdown operations
// - Batch processing
// - Normalization
// - Format conversion
//
// Uses rf-offline Rust crate via FFI.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

/// Output format for offline processing
enum OfflineOutputFormat {
  wav16,
  wav24,
  wav32f,
  flac,
  mp3_320,
}

extension OfflineOutputFormatExt on OfflineOutputFormat {
  int get value {
    switch (this) {
      case OfflineOutputFormat.wav16:
        return 0;
      case OfflineOutputFormat.wav24:
        return 1;
      case OfflineOutputFormat.wav32f:
        return 2;
      case OfflineOutputFormat.flac:
        return 3;
      case OfflineOutputFormat.mp3_320:
        return 4;
    }
  }

  String get displayName {
    switch (this) {
      case OfflineOutputFormat.wav16:
        return 'WAV 16-bit';
      case OfflineOutputFormat.wav24:
        return 'WAV 24-bit';
      case OfflineOutputFormat.wav32f:
        return 'WAV 32-bit float';
      case OfflineOutputFormat.flac:
        return 'FLAC';
      case OfflineOutputFormat.mp3_320:
        return 'MP3 320kbps';
    }
  }

  String get extension {
    switch (this) {
      case OfflineOutputFormat.wav16:
      case OfflineOutputFormat.wav24:
      case OfflineOutputFormat.wav32f:
        return 'wav';
      case OfflineOutputFormat.flac:
        return 'flac';
      case OfflineOutputFormat.mp3_320:
        return 'mp3';
    }
  }

  bool get isLossless {
    switch (this) {
      case OfflineOutputFormat.wav16:
      case OfflineOutputFormat.wav24:
      case OfflineOutputFormat.wav32f:
      case OfflineOutputFormat.flac:
        return true;
      case OfflineOutputFormat.mp3_320:
        return false;
    }
  }
}

/// Normalization mode
enum NormalizationMode {
  none,
  peak,
  lufs,
  truePeak,
  noClip,
}

extension NormalizationModeExt on NormalizationMode {
  int get value {
    switch (this) {
      case NormalizationMode.none:
        return 0;
      case NormalizationMode.peak:
        return 1;
      case NormalizationMode.lufs:
        return 2;
      case NormalizationMode.truePeak:
        return 3;
      case NormalizationMode.noClip:
        return 4;
    }
  }

  String get displayName {
    switch (this) {
      case NormalizationMode.none:
        return 'None';
      case NormalizationMode.peak:
        return 'Peak';
      case NormalizationMode.lufs:
        return 'Loudness (LUFS)';
      case NormalizationMode.truePeak:
        return 'True Peak';
      case NormalizationMode.noClip:
        return 'No Clip';
    }
  }

  String get unit {
    switch (this) {
      case NormalizationMode.none:
      case NormalizationMode.noClip:
        return '';
      case NormalizationMode.peak:
        return 'dBFS';
      case NormalizationMode.lufs:
        return 'LUFS';
      case NormalizationMode.truePeak:
        return 'dBTP';
    }
  }

  double get defaultTarget {
    switch (this) {
      case NormalizationMode.none:
      case NormalizationMode.noClip:
        return 0.0;
      case NormalizationMode.peak:
      case NormalizationMode.truePeak:
        return -1.0;
      case NormalizationMode.lufs:
        return -14.0;
    }
  }
}

/// Pipeline state
enum PipelineState {
  idle,
  loading,
  analyzing,
  processing,
  normalizing,
  converting,
  encoding,
  writing,
  complete,
  failed,
  cancelled,
}

// ═══════════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Job configuration
class OfflineJobConfig {
  final String inputPath;
  final String outputPath;
  final int? sampleRate;
  final NormalizationMode normalizationMode;
  final double normalizationTarget;
  final int? fadeInSamples;
  final int? fadeOutSamples;
  final OfflineOutputFormat format;

  const OfflineJobConfig({
    required this.inputPath,
    required this.outputPath,
    this.sampleRate,
    this.normalizationMode = NormalizationMode.none,
    this.normalizationTarget = 0.0,
    this.fadeInSamples,
    this.fadeOutSamples,
    this.format = OfflineOutputFormat.wav24,
  });

  Map<String, dynamic> toJson() => {
        'input_path': inputPath,
        'output_path': outputPath,
        if (sampleRate != null) 'sample_rate': sampleRate,
        if (normalizationMode != NormalizationMode.none)
          'normalize_mode': normalizationMode.value,
        if (normalizationMode != NormalizationMode.none)
          'normalize_target': normalizationTarget,
        if (fadeInSamples != null) 'fade_in_samples': fadeInSamples,
        if (fadeOutSamples != null) 'fade_out_samples': fadeOutSamples,
        'format': format.value,
      };
}

/// Job result
class OfflineJobResult {
  final int jobId;
  final bool success;
  final String? outputPath;
  final int outputSize;
  final Duration duration;
  final double peakLevel;
  final double truePeak;
  final double loudness;
  final String? error;

  const OfflineJobResult({
    required this.jobId,
    required this.success,
    this.outputPath,
    this.outputSize = 0,
    this.duration = Duration.zero,
    this.peakLevel = 0.0,
    this.truePeak = 0.0,
    this.loudness = 0.0,
    this.error,
  });

  factory OfflineJobResult.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String?;
    return OfflineJobResult(
      jobId: json['job_id'] as int? ?? 0,
      success: status == 'Completed',
      outputPath: json['output_path'] as String?,
      outputSize: json['output_size'] as int? ?? 0,
      duration: Duration(
        milliseconds: (json['duration']?['secs'] as int? ?? 0) * 1000 +
            ((json['duration']?['nanos'] as int? ?? 0) ~/ 1000000),
      ),
      peakLevel: (json['peak_level'] as num?)?.toDouble() ?? 0.0,
      truePeak: (json['true_peak'] as num?)?.toDouble() ?? 0.0,
      loudness: (json['loudness'] as num?)?.toDouble() ?? 0.0,
      error: json['error'] as String?,
    );
  }
}

/// Progress information
class OfflineProgress {
  final PipelineState state;
  final String stage;
  final double stageProgress;
  final double overallProgress;
  final int samplesProcessed;
  final int totalSamples;
  final Duration elapsed;
  final Duration? estimatedRemaining;

  const OfflineProgress({
    this.state = PipelineState.idle,
    this.stage = '',
    this.stageProgress = 0.0,
    this.overallProgress = 0.0,
    this.samplesProcessed = 0,
    this.totalSamples = 0,
    this.elapsed = Duration.zero,
    this.estimatedRemaining,
  });

  factory OfflineProgress.fromJson(Map<String, dynamic> json) {
    final stateStr = json['state'] as String? ?? 'Idle';
    PipelineState state;
    switch (stateStr) {
      case 'Idle':
        state = PipelineState.idle;
        break;
      case 'Loading':
        state = PipelineState.loading;
        break;
      case 'Analyzing':
        state = PipelineState.analyzing;
        break;
      case 'Processing':
        state = PipelineState.processing;
        break;
      case 'Normalizing':
        state = PipelineState.normalizing;
        break;
      case 'Converting':
        state = PipelineState.converting;
        break;
      case 'Encoding':
        state = PipelineState.encoding;
        break;
      case 'Writing':
        state = PipelineState.writing;
        break;
      case 'Complete':
        state = PipelineState.complete;
        break;
      case 'Failed':
        state = PipelineState.failed;
        break;
      case 'Cancelled':
        state = PipelineState.cancelled;
        break;
      default:
        state = PipelineState.idle;
    }

    return OfflineProgress(
      state: state,
      stage: json['stage'] as String? ?? '',
      stageProgress: (json['stage_progress'] as num?)?.toDouble() ?? 0.0,
      overallProgress: (json['overall_progress'] as num?)?.toDouble() ?? 0.0,
      samplesProcessed: json['samples_processed'] as int? ?? 0,
      totalSamples: json['total_samples'] as int? ?? 0,
      elapsed: Duration(milliseconds: json['elapsed_ms'] as int? ?? 0),
      estimatedRemaining: json['estimated_remaining_ms'] != null
          ? Duration(milliseconds: json['estimated_remaining_ms'] as int)
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider for offline DSP processing
class OfflineProcessingProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  int? _pipelineHandle;
  OfflineProgress _progress = const OfflineProgress();
  final List<OfflineJobResult> _completedJobs = [];
  Timer? _progressTimer;
  bool _isProcessing = false;

  OfflineProcessingProvider(this._ffi);

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get isProcessing => _isProcessing;
  OfflineProgress get progress => _progress;
  List<OfflineJobResult> get completedJobs => List.unmodifiable(_completedJobs);
  bool get hasPipeline => _pipelineHandle != null;

  // ═══════════════════════════════════════════════════════════════════════════
  // PIPELINE LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new processing pipeline
  void createPipeline() {
    if (_pipelineHandle != null) {
      destroyPipeline();
    }

    _pipelineHandle = _ffi.offlinePipelineCreate();
    if (_pipelineHandle == 0) {
      _pipelineHandle = null;
      throw Exception('Failed to create offline pipeline');
    }

    notifyListeners();
  }

  /// Destroy the current pipeline
  void destroyPipeline() {
    if (_pipelineHandle != null) {
      _stopProgressTimer();
      _ffi.offlinePipelineDestroy(_pipelineHandle!);
      _pipelineHandle = null;
      _isProcessing = false;
      _progress = const OfflineProgress();
      notifyListeners();
    }
  }

  /// Configure normalization
  void setNormalization(NormalizationMode mode, double target) {
    if (_pipelineHandle != null) {
      _ffi.offlinePipelineSetNormalization(_pipelineHandle!, mode.value, target);
    }
  }

  /// Configure output format
  void setOutputFormat(OfflineOutputFormat format) {
    if (_pipelineHandle != null) {
      _ffi.offlinePipelineSetFormat(_pipelineHandle!, format.value);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROCESSING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Process a single file
  Future<OfflineJobResult?> processFile({
    required String inputPath,
    required String outputPath,
  }) async {
    if (_pipelineHandle == null) {
      createPipeline();
    }

    _isProcessing = true;
    _startProgressTimer();
    notifyListeners();

    try {
      final jobId = _ffi.offlineProcessFile(
        _pipelineHandle!,
        inputPath,
        outputPath,
      );

      if (jobId == 0) {
        final error = _ffi.offlineGetLastError();
        throw Exception(error ?? 'Unknown error processing file');
      }

      // Wait for completion
      await _waitForCompletion();

      // Get result
      final resultJson = _ffi.offlineGetJobResult(jobId);
      if (resultJson != null) {
        final result = OfflineJobResult.fromJson(jsonDecode(resultJson));
        _completedJobs.add(result);
        _ffi.offlineClearJobResult(jobId);
        return result;
      }

      return null;
    } finally {
      _isProcessing = false;
      _stopProgressTimer();
      notifyListeners();
    }
  }

  /// Process a file with full options
  Future<OfflineJobResult?> processFileWithOptions(OfflineJobConfig config) async {
    if (_pipelineHandle == null) {
      createPipeline();
    }

    _isProcessing = true;
    _startProgressTimer();
    notifyListeners();

    try {
      final optionsJson = jsonEncode(config.toJson());
      final jobId = _ffi.offlineProcessFileWithOptions(
        _pipelineHandle!,
        optionsJson,
      );

      if (jobId == 0) {
        final error = _ffi.offlineGetLastError();
        throw Exception(error ?? 'Unknown error processing file');
      }

      // Wait for completion
      await _waitForCompletion();

      // Get result
      final resultJson = _ffi.offlineGetJobResult(jobId);
      if (resultJson != null) {
        final result = OfflineJobResult.fromJson(jsonDecode(resultJson));
        _completedJobs.add(result);
        _ffi.offlineClearJobResult(jobId);
        return result;
      }

      return null;
    } finally {
      _isProcessing = false;
      _stopProgressTimer();
      notifyListeners();
    }
  }

  /// Cancel current processing
  void cancel() {
    if (_pipelineHandle != null && _isProcessing) {
      _ffi.offlinePipelineCancel(_pipelineHandle!);
    }
  }

  /// Clear completed jobs list
  void clearCompletedJobs() {
    _completedJobs.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BATCH PROCESSING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Process multiple files in batch
  Future<List<OfflineJobResult>> batchProcess(List<OfflineJobConfig> configs) async {
    _isProcessing = true;
    notifyListeners();

    try {
      final jobs = configs.map((c) => {
            'input_path': c.inputPath,
            'output_path': c.outputPath,
            if (c.sampleRate != null) 'sample_rate': c.sampleRate,
          }).toList();

      final resultsJson = _ffi.offlineBatchProcess(jsonEncode(jobs));
      if (resultsJson == null) {
        final error = _ffi.offlineGetLastError();
        throw Exception(error ?? 'Unknown error in batch processing');
      }

      final List<dynamic> resultsList = jsonDecode(resultsJson);
      final results = resultsList
          .map((r) => OfflineJobResult.fromJson(r as Map<String, dynamic>))
          .toList();

      _completedJobs.addAll(results);
      notifyListeners();

      return results;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get supported output formats
  List<Map<String, dynamic>> getSupportedFormats() {
    final json = _ffi.offlineGetSupportedFormats();
    if (json != null) {
      return List<Map<String, dynamic>>.from(jsonDecode(json));
    }
    return [];
  }

  /// Get supported normalization modes
  List<Map<String, dynamic>> getNormalizationModes() {
    final json = _ffi.offlineGetNormalizationModes();
    if (json != null) {
      return List<Map<String, dynamic>>.from(jsonDecode(json));
    }
    return [];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIVATE METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _updateProgress();
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _updateProgress() {
    if (_pipelineHandle == null) return;

    final json = _ffi.offlinePipelineGetProgressJson(_pipelineHandle!);
    if (json != null) {
      _progress = OfflineProgress.fromJson(jsonDecode(json));
      notifyListeners();
    }
  }

  Future<void> _waitForCompletion() async {
    while (_isProcessing && _pipelineHandle != null) {
      final state = _ffi.offlinePipelineGetState(_pipelineHandle!);
      if (state >= 8) {
        // Complete, Failed, or Cancelled
        break;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  @override
  void dispose() {
    destroyPipeline();
    super.dispose();
  }
}
