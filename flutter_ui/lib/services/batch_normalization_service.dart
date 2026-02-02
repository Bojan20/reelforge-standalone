/// Batch Normalization Service
///
/// P12.1.10: Batch audio normalization for multiple files:
/// - LUFS target normalization (-14/-16/-23 LUFS)
/// - Peak normalization
/// - True Peak limiting (ISP-safe)
/// - Progress tracking with callbacks
/// - Uses rf-offline pipeline via FFI
///
/// Usage:
/// ```dart
/// final service = BatchNormalizationService.instance;
///
/// // Normalize to streaming target
/// final result = await service.normalizeFiles(
///   files: ['/audio/a.wav', '/audio/b.wav'],
///   mode: NormalizationMode.lufs,
///   targetLufs: -14.0,
///   onProgress: (progress, file) => print('$file: ${(progress * 100).toInt()}%'),
/// );
/// ```

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// Normalization mode
enum NormalizationMode {
  /// No normalization
  none,

  /// Peak normalization (0 dB ceiling)
  peak,

  /// LUFS integrated loudness (EBU R128)
  lufs,

  /// True Peak normalization (ISP-safe)
  truePeak,

  /// Auto-adjust to prevent clipping
  noClip,
}

extension NormalizationModeExtension on NormalizationMode {
  /// Display name
  String get displayName {
    switch (this) {
      case NormalizationMode.none: return 'None';
      case NormalizationMode.peak: return 'Peak';
      case NormalizationMode.lufs: return 'LUFS (EBU R128)';
      case NormalizationMode.truePeak: return 'True Peak';
      case NormalizationMode.noClip: return 'No Clip';
    }
  }

  /// FFI mode ID
  int get ffiId {
    switch (this) {
      case NormalizationMode.none: return 0;
      case NormalizationMode.peak: return 1;
      case NormalizationMode.lufs: return 2;
      case NormalizationMode.truePeak: return 3;
      case NormalizationMode.noClip: return 4;
    }
  }
}

/// Common LUFS target presets
class LufsPresets {
  static const double streaming = -14.0;       // Spotify, YouTube, Apple Music
  static const double broadcast = -23.0;       // EBU R128 broadcast standard
  static const double podcast = -16.0;         // Podcast standard
  static const double club = -8.0;             // Club/DJ mastering
  static const double cd = -12.0;              // CD mastering
}

/// Result of a single file normalization
class NormalizationResult {
  /// Input file path
  final String inputPath;

  /// Output file path
  final String outputPath;

  /// Whether normalization was successful
  final bool success;

  /// Error message if failed
  final String? error;

  /// Measured LUFS before normalization
  final double? measuredLufs;

  /// Applied gain in dB
  final double? appliedGainDb;

  /// Processing time in milliseconds
  final int processingTimeMs;

  const NormalizationResult({
    required this.inputPath,
    required this.outputPath,
    required this.success,
    this.error,
    this.measuredLufs,
    this.appliedGainDb,
    this.processingTimeMs = 0,
  });

  @override
  String toString() =>
      'NormalizationResult($inputPath: ${success ? "OK" : "FAILED"}, gain: ${appliedGainDb?.toStringAsFixed(1)}dB)';
}

/// Result of batch normalization
class BatchNormalizationResult {
  /// List of individual results
  final List<NormalizationResult> results;

  /// Total files processed
  final int totalFiles;

  /// Successfully normalized count
  final int successCount;

  /// Failed count
  final int failedCount;

  /// Total processing time in milliseconds
  final int totalTimeMs;

  const BatchNormalizationResult({
    required this.results,
    required this.totalFiles,
    required this.successCount,
    required this.failedCount,
    required this.totalTimeMs,
  });

  /// Overall success rate (0.0 - 1.0)
  double get successRate => totalFiles > 0 ? successCount / totalFiles : 0.0;

  /// All files succeeded
  bool get allSucceeded => failedCount == 0;

  /// Get failed results only
  List<NormalizationResult> get failedResults =>
      results.where((r) => !r.success).toList();

  @override
  String toString() =>
      'BatchNormalizationResult($successCount/$totalFiles succeeded, ${totalTimeMs}ms)';
}

/// Progress callback type
/// - progress: 0.0-1.0
/// - currentFile: path of file being processed
typedef NormalizationProgressCallback = void Function(
    double progress, String currentFile);

/// Batch Normalization Service — Singleton
class BatchNormalizationService extends ChangeNotifier {
  // ─── Singleton ───────────────────────────────────────────────────────────────
  static BatchNormalizationService? _instance;
  static BatchNormalizationService get instance =>
      _instance ??= BatchNormalizationService._();

  BatchNormalizationService._();

  // ─── State ───────────────────────────────────────────────────────────────────
  bool _isProcessing = false;
  double _currentProgress = 0.0;
  String? _currentFile;
  bool _cancelRequested = false;

  /// Whether batch processing is in progress
  bool get isProcessing => _isProcessing;

  /// Current progress (0.0 - 1.0)
  double get currentProgress => _currentProgress;

  /// Currently processing file
  String? get currentFile => _currentFile;

  // ─── FFI Reference ───────────────────────────────────────────────────────────
  final NativeFFI _ffi = NativeFFI.instance;

  // ═══════════════════════════════════════════════════════════════════════════
  // SINGLE FILE NORMALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Normalize a single file
  ///
  /// Returns null if FFI is not available
  Future<NormalizationResult?> normalizeFile({
    required String inputPath,
    required String outputPath,
    NormalizationMode mode = NormalizationMode.lufs,
    double targetLufs = LufsPresets.streaming,
    double peakCeilingDb = -1.0,
  }) async {
    if (!_ffi.loaded) {
      debugPrint('[BatchNorm] FFI not loaded');
      return null;
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Create pipeline
      final handle = _ffi.offlinePipelineCreate();
      if (handle <= 0) {
        return NormalizationResult(
          inputPath: inputPath,
          outputPath: outputPath,
          success: false,
          error: 'Failed to create processing pipeline',
        );
      }

      // Set normalization mode
      final target = mode == NormalizationMode.lufs ? targetLufs : peakCeilingDb;
      _ffi.offlinePipelineSetNormalization(handle, mode.ffiId, target);

      // Process file
      final success = _ffi.offlineProcessFile(handle, inputPath, outputPath);

      // Get result info
      final resultJson = _ffi.offlineGetJobResult(handle);
      double? measuredLufs;
      double? appliedGain;

      if (resultJson != null) {
        try {
          // Parse JSON result for measured values
          // Expected format: { "measured_lufs": -18.5, "applied_gain_db": 4.5 }
          if (resultJson.contains('measured_lufs')) {
            final lufsMatch =
                RegExp(r'"measured_lufs"\s*:\s*([-\d.]+)').firstMatch(resultJson);
            if (lufsMatch != null) {
              measuredLufs = double.tryParse(lufsMatch.group(1)!);
            }
          }
          if (resultJson.contains('applied_gain_db')) {
            final gainMatch = RegExp(r'"applied_gain_db"\s*:\s*([-\d.]+)')
                .firstMatch(resultJson);
            if (gainMatch != null) {
              appliedGain = double.tryParse(gainMatch.group(1)!);
            }
          }
        } catch (_) {
          // Ignore JSON parse errors
        }
      }

      // Cleanup
      _ffi.offlinePipelineDestroy(handle);

      stopwatch.stop();

      return NormalizationResult(
        inputPath: inputPath,
        outputPath: outputPath,
        success: success,
        error: success ? null : 'Processing failed',
        measuredLufs: measuredLufs,
        appliedGainDb: appliedGain,
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      return NormalizationResult(
        inputPath: inputPath,
        outputPath: outputPath,
        success: false,
        error: e.toString(),
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BATCH NORMALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Normalize multiple files
  ///
  /// [files] - List of input file paths
  /// [outputDir] - Directory for output files (null = overwrite in place with _norm suffix)
  /// [mode] - Normalization mode
  /// [targetLufs] - Target LUFS level (for LUFS mode)
  /// [peakCeilingDb] - Peak ceiling in dB (for Peak/TruePeak modes)
  /// [onProgress] - Progress callback
  Future<BatchNormalizationResult> normalizeFiles({
    required List<String> files,
    String? outputDir,
    NormalizationMode mode = NormalizationMode.lufs,
    double targetLufs = LufsPresets.streaming,
    double peakCeilingDb = -1.0,
    NormalizationProgressCallback? onProgress,
  }) async {
    if (files.isEmpty) {
      return const BatchNormalizationResult(
        results: [],
        totalFiles: 0,
        successCount: 0,
        failedCount: 0,
        totalTimeMs: 0,
      );
    }

    _isProcessing = true;
    _currentProgress = 0.0;
    _cancelRequested = false;
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    final results = <NormalizationResult>[];
    int successCount = 0;
    int failedCount = 0;

    for (int i = 0; i < files.length; i++) {
      if (_cancelRequested) {
        debugPrint('[BatchNorm] Cancelled by user');
        break;
      }

      final inputPath = files[i];
      _currentFile = inputPath;
      _currentProgress = i / files.length;
      notifyListeners();

      onProgress?.call(_currentProgress, inputPath);

      // Generate output path
      final outputPath = _generateOutputPath(inputPath, outputDir);

      // Process file
      final result = await normalizeFile(
        inputPath: inputPath,
        outputPath: outputPath,
        mode: mode,
        targetLufs: targetLufs,
        peakCeilingDb: peakCeilingDb,
      );

      if (result != null) {
        results.add(result);
        if (result.success) {
          successCount++;
        } else {
          failedCount++;
        }
      } else {
        results.add(NormalizationResult(
          inputPath: inputPath,
          outputPath: outputPath,
          success: false,
          error: 'FFI not available',
        ));
        failedCount++;
      }

      // Brief yield to allow UI updates
      await Future.delayed(const Duration(milliseconds: 1));
    }

    stopwatch.stop();

    _isProcessing = false;
    _currentProgress = 1.0;
    _currentFile = null;
    notifyListeners();

    onProgress?.call(1.0, 'Complete');

    final result = BatchNormalizationResult(
      results: results,
      totalFiles: files.length,
      successCount: successCount,
      failedCount: failedCount,
      totalTimeMs: stopwatch.elapsedMilliseconds,
    );

    debugPrint('[BatchNorm] Completed: $result');
    return result;
  }

  /// Cancel ongoing batch processing
  void cancel() {
    if (_isProcessing) {
      _cancelRequested = true;
      debugPrint('[BatchNorm] Cancel requested');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANALYSIS (Pre-normalization)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Analyze files without processing (get LUFS measurements)
  ///
  /// Returns map of path -> measured LUFS (or null if analysis failed)
  Future<Map<String, double?>> analyzeFiles(
    List<String> files, {
    NormalizationProgressCallback? onProgress,
  }) async {
    final results = <String, double?>{};

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      onProgress?.call(i / files.length, file);

      try {
        // Use FFI to get audio info/LUFS
        // For now, return null - actual implementation would call
        // _ffi.offlineMeasureLufs(file) when available
        results[file] = null;
      } catch (e) {
        results[file] = null;
      }
    }

    onProgress?.call(1.0, 'Complete');
    return results;
  }

  /// Calculate gain needed to reach target LUFS
  double calculateRequiredGain(double measuredLufs, double targetLufs) {
    return targetLufs - measuredLufs;
  }

  /// Check if gain will cause clipping (> 0 dB)
  bool willClip(double measuredLufs, double targetLufs, double headroomDb) {
    final requiredGain = calculateRequiredGain(measuredLufs, targetLufs);
    return requiredGain > headroomDb;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate output path for normalized file
  String _generateOutputPath(String inputPath, String? outputDir) {
    final fileName = inputPath.split('/').last;
    final baseName = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final ext = fileName.contains('.')
        ? fileName.substring(fileName.lastIndexOf('.'))
        : '.wav';

    if (outputDir != null) {
      return '$outputDir/${baseName}_norm$ext';
    } else {
      // Same directory with _norm suffix
      final dir = inputPath.substring(0, inputPath.lastIndexOf('/'));
      return '$dir/${baseName}_norm$ext';
    }
  }

  /// Get suggested LUFS target based on use case
  static double suggestTarget(String useCase) {
    switch (useCase.toLowerCase()) {
      case 'streaming':
      case 'spotify':
      case 'youtube':
      case 'apple music':
        return LufsPresets.streaming;
      case 'broadcast':
      case 'tv':
      case 'radio':
        return LufsPresets.broadcast;
      case 'podcast':
        return LufsPresets.podcast;
      case 'club':
      case 'dj':
        return LufsPresets.club;
      case 'cd':
      case 'album':
        return LufsPresets.cd;
      default:
        return LufsPresets.streaming;
    }
  }

  /// Format LUFS value for display
  static String formatLufs(double lufs) {
    return '${lufs.toStringAsFixed(1)} LUFS';
  }

  /// Format gain value for display
  static String formatGain(double gainDb) {
    final sign = gainDb >= 0 ? '+' : '';
    return '$sign${gainDb.toStringAsFixed(1)} dB';
  }
}
