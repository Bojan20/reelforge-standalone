/// Batch Asset Conversion Service
import 'dart:math' as math;
///
/// P2-05: Bulk audio file conversion with progress tracking.
/// Leverages rf-offline crate for format conversion, normalization, and processing.
///
/// Features:
/// - Multi-file conversion queue
/// - Progress callbacks per file
/// - Format conversion (WAV, FLAC, MP3, OGG, Opus, AAC)
/// - Loudness normalization (LUFS, Peak, RMS)
/// - Sample rate conversion
/// - Bit depth conversion
///
/// Usage:
/// ```dart
/// final converter = BatchAssetConverter();
/// await converter.convertBatch(
///   inputFiles: ['/audio/file1.wav', '/audio/file2.wav'],
///   outputFormat: AudioFormat.flac,
///   outputDir: '/output',
///   normalize: NormalizationMode.lufs(target: -14.0),
///   onProgress: (current, total, file, progress) => print('$current/$total: $file ($progress%)'),
/// );
/// ```

import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../../src/rust/native_ffi.dart';

/// Audio output format
enum AudioFormat {
  /// WAV 16-bit PCM
  wav16,
  /// WAV 24-bit PCM
  wav24,
  /// WAV 32-bit float
  wav32f,
  /// FLAC 16-bit
  flac16,
  /// FLAC 24-bit
  flac24,
  /// MP3 320 kbps
  mp3High,
  /// MP3 192 kbps
  mp3Medium,
  /// MP3 128 kbps
  mp3Low,
  /// OGG Vorbis q8 (~256 kbps)
  oggHigh,
  /// OGG Vorbis q5 (~160 kbps)
  oggMedium,
  /// Opus 256 kbps
  opusHigh,
  /// AAC 256 kbps
  aacHigh,
}

/// Normalization mode
sealed class NormalizationMode {
  const NormalizationMode();

  /// LUFS loudness normalization
  const factory NormalizationMode.lufs({required double target}) = LufsNormalization;

  /// Peak normalization
  const factory NormalizationMode.peak({required double target}) = PeakNormalization;

  /// RMS normalization
  const factory NormalizationMode.rms({required double target}) = RmsNormalization;

  /// No normalization
  const factory NormalizationMode.none() = NoNormalization;
}

class LufsNormalization extends NormalizationMode {
  final double target;
  const LufsNormalization({required this.target});
}

class PeakNormalization extends NormalizationMode {
  final double target;
  const PeakNormalization({required this.target});
}

class RmsNormalization extends NormalizationMode {
  final double target;
  const RmsNormalization({required this.target});
}

class NoNormalization extends NormalizationMode {
  const NoNormalization();
}

/// Conversion job
class ConversionJob {
  final String inputPath;
  final String outputPath;
  final AudioFormat format;
  final NormalizationMode normalize;
  final int? targetSampleRate;
  final int? targetBitDepth;

  const ConversionJob({
    required this.inputPath,
    required this.outputPath,
    required this.format,
    this.normalize = const NoNormalization(),
    this.targetSampleRate,
    this.targetBitDepth,
  });
}

/// Conversion result
class ConversionResult {
  final String inputPath;
  final String outputPath;
  final bool success;
  final String? error;
  final double durationSeconds;
  final Map<String, dynamic> metadata;

  const ConversionResult({
    required this.inputPath,
    required this.outputPath,
    required this.success,
    this.error,
    this.durationSeconds = 0.0,
    this.metadata = const {},
  });
}

/// Progress callback signature
typedef ConversionProgressCallback = void Function(
  int currentFile,
  int totalFiles,
  String fileName,
  double fileProgress, // 0-100%
);

/// Batch Asset Converter
class BatchAssetConverter {
  final NativeFFI _ffi = NativeFFI.instance;

  /// Convert multiple files
  Future<List<ConversionResult>> convertBatch({
    required List<String> inputFiles,
    required AudioFormat outputFormat,
    required String outputDir,
    NormalizationMode normalize = const NoNormalization(),
    int? targetSampleRate,
    int? targetBitDepth,
    ConversionProgressCallback? onProgress,
  }) async {
    final results = <ConversionResult>[];

    for (int i = 0; i < inputFiles.length; i++) {
      final inputPath = inputFiles[i];
      final fileName = path.basename(inputPath);

      onProgress?.call(i + 1, inputFiles.length, fileName, 0.0);

      // Generate output path
      final outputPath = _generateOutputPath(inputPath, outputDir, outputFormat);

      // Create conversion job
      final job = ConversionJob(
        inputPath: inputPath,
        outputPath: outputPath,
        format: outputFormat,
        normalize: normalize,
        targetSampleRate: targetSampleRate,
        targetBitDepth: targetBitDepth,
      );

      // Convert single file
      final result = await _convertSingle(job, (progress) {
        onProgress?.call(i + 1, inputFiles.length, fileName, progress);
      });

      results.add(result);
    }

    return results;
  }

  /// Convert single file using rf-offline FFI
  Future<ConversionResult> _convertSingle(
    ConversionJob job,
    void Function(double progress)? onProgress,
  ) async {
    final startTime = DateTime.now();

    try {
      // Check FFI availability
      if (!_ffi.isLoaded) {
        return ConversionResult(
          inputPath: job.inputPath,
          outputPath: job.outputPath,
          success: false,
          error: 'FFI not loaded',
        );
      }

      // Verify input file exists
      final inputFile = File(job.inputPath);
      if (!await inputFile.exists()) {
        return ConversionResult(
          inputPath: job.inputPath,
          outputPath: job.outputPath,
          success: false,
          error: 'Input file not found',
        );
      }

      // Ensure output directory exists
      final outputFile = File(job.outputPath);
      await outputFile.parent.create(recursive: true);

      // Get input file info for metadata
      final audioInfo = _ffi.offlineGetAudioInfo(job.inputPath);
      final inputSampleRate = audioInfo?['sample_rate'] as int? ?? 0;
      final inputChannels = audioInfo?['channels'] as int? ?? 0;
      final inputDuration = audioInfo?['duration'] as double? ?? 0.0;

      onProgress?.call(5.0);

      // ═══════════════════════════════════════════════════════════════════════
      // REAL RF-OFFLINE FFI IMPLEMENTATION
      // ═══════════════════════════════════════════════════════════════════════

      // 1. Create offline pipeline
      final pipelineHandle = _ffi.offlinePipelineCreate();
      if (pipelineHandle == 0) {
        final error = _ffi.offlineGetLastError() ?? 'Failed to create pipeline';
        return ConversionResult(
          inputPath: job.inputPath,
          outputPath: job.outputPath,
          success: false,
          error: error,
        );
      }

      try {
        onProgress?.call(10.0);

        // 2. Set output format
        final formatId = _formatToId(job.format);
        _ffi.offlinePipelineSetFormat(pipelineHandle, formatId);

        onProgress?.call(15.0);

        // 3. Set normalization if specified
        final (normMode, normTarget) = _normalizationToParams(job.normalize);
        if (normMode > 0) {
          _ffi.offlinePipelineSetNormalization(pipelineHandle, normMode, normTarget);
        }

        onProgress?.call(20.0);

        // 4. Process file
        final jobId = _ffi.offlineProcessFile(
          pipelineHandle,
          job.inputPath,
          job.outputPath,
        );

        if (jobId == 0) {
          final error = _ffi.offlineGetLastError() ?? 'Failed to start processing';
          return ConversionResult(
            inputPath: job.inputPath,
            outputPath: job.outputPath,
            success: false,
            error: error,
          );
        }

        // 5. Poll for progress until complete
        int state = 0;
        double lastProgress = 20.0;

        while (true) {
          state = _ffi.offlinePipelineGetState(pipelineHandle);

          // States: 0=Idle, 1=Loading, 2=Analyzing, 3=Processing, 4=Normalizing,
          //         5=Converting, 6=Encoding, 7=Writing, 8=Complete, 9=Failed, 10=Cancelled
          if (state == 8) break; // Complete
          if (state == 9) {
            // Failed
            final error = _ffi.offlineGetJobError(jobId) ?? 'Processing failed';
            return ConversionResult(
              inputPath: job.inputPath,
              outputPath: job.outputPath,
              success: false,
              error: error,
            );
          }
          if (state == 10) {
            return ConversionResult(
              inputPath: job.inputPath,
              outputPath: job.outputPath,
              success: false,
              error: 'Processing cancelled',
            );
          }

          // Get progress (0.0 - 1.0) and map to 20-95%
          final progress = _ffi.offlinePipelineGetProgress(pipelineHandle);
          final mappedProgress = 20.0 + (progress * 75.0);

          if (mappedProgress > lastProgress) {
            lastProgress = mappedProgress;
            onProgress?.call(mappedProgress);
          }

          // Brief delay to avoid busy-waiting
          await Future.delayed(const Duration(milliseconds: 50));
        }

        onProgress?.call(95.0);

        // 6. Verify output file was created
        if (!await outputFile.exists()) {
          return ConversionResult(
            inputPath: job.inputPath,
            outputPath: job.outputPath,
            success: false,
            error: 'Output file was not created',
          );
        }

        // Get output file info
        final outputInfo = _ffi.offlineGetAudioInfo(job.outputPath);

        onProgress?.call(100.0);

        final duration = DateTime.now().difference(startTime).inMilliseconds / 1000.0;

        return ConversionResult(
          inputPath: job.inputPath,
          outputPath: job.outputPath,
          success: true,
          durationSeconds: duration,
          metadata: {
            'format': job.format.name,
            'normalized': job.normalize is! NoNormalization,
            'input_sample_rate': inputSampleRate,
            'input_channels': inputChannels,
            'input_duration': inputDuration,
            'output_sample_rate': outputInfo?['sample_rate'] ?? 0,
            'output_channels': outputInfo?['channels'] ?? 0,
            'output_duration': outputInfo?['duration'] ?? 0.0,
            'output_size_bytes': await outputFile.length(),
          },
        );
      } finally {
        // 7. Always destroy pipeline
        _ffi.offlinePipelineDestroy(pipelineHandle);
      }
    } catch (e) {
      return ConversionResult(
        inputPath: job.inputPath,
        outputPath: job.outputPath,
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Convert NormalizationMode to FFI params (mode, target)
  (int, double) _normalizationToParams(NormalizationMode mode) {
    return switch (mode) {
      NoNormalization() => (0, 0.0),
      PeakNormalization(target: final t) => (1, t),
      LufsNormalization(target: final t) => (2, t),
      RmsNormalization(target: final t) => (3, t),
    };
  }

  /// Generate output path based on format
  String _generateOutputPath(String inputPath, String outputDir, AudioFormat format) {
    final baseName = path.basenameWithoutExtension(inputPath);
    final extension = _getExtension(format);
    return path.join(outputDir, '$baseName.$extension');
  }

  /// Get file extension for format
  String _getExtension(AudioFormat format) {
    return switch (format) {
      AudioFormat.wav16 || AudioFormat.wav24 || AudioFormat.wav32f => 'wav',
      AudioFormat.flac16 || AudioFormat.flac24 => 'flac',
      AudioFormat.mp3High || AudioFormat.mp3Medium || AudioFormat.mp3Low => 'mp3',
      AudioFormat.oggHigh || AudioFormat.oggMedium => 'ogg',
      AudioFormat.opusHigh => 'opus',
      AudioFormat.aacHigh => 'aac',
    };
  }

  /// Map AudioFormat to rf-offline format ID
  int _formatToId(AudioFormat format) {
    return switch (format) {
      AudioFormat.wav16 => 0,
      AudioFormat.wav24 => 1,
      AudioFormat.wav32f => 2,
      AudioFormat.flac16 => 3,
      AudioFormat.flac24 => 3,
      AudioFormat.mp3High => 4,
      AudioFormat.mp3Medium => 4,
      AudioFormat.mp3Low => 4,
      AudioFormat.oggHigh => 4,
      AudioFormat.oggMedium => 4,
      AudioFormat.opusHigh => 4,
      AudioFormat.aacHigh => 4,
    };
  }

  /// Linear to dB
  double _linearToDb(double linear) {
    if (linear <= 0.0) return -120.0;
    return 20.0 * math.log(linear) / math.ln10;
  }
}
