// Audio Export Provider
//
// Offline rendering and export with:
// - Render timeline to audio buffer
// - WAV export (16/24/32-bit)
// - True peak limiting
// - Normalization
// - Dithering
// - Progress tracking

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../src/rust/engine_api.dart' as engine_api;

// ============ Types ============

/// Export format with FFI code mapping
///
/// Maps directly to Rust ExportFormat enum:
/// - 0: Wav16 (16-bit PCM WAV)
/// - 1: Wav24 (24-bit PCM WAV) - Default
/// - 2: Wav32Float (32-bit Float WAV)
/// - 3: Flac16 (FLAC 16-bit)
/// - 4: Flac24 (FLAC 24-bit)
/// - 5: Mp3_320 (MP3 320kbps)
/// - 6: Mp3_256 (MP3 256kbps)
/// - 7: Mp3_192 (MP3 192kbps)
/// - 8: Mp3_128 (MP3 128kbps)
enum ExportFormatType {
  wav16(0, 'WAV 16-bit', 'wav'),
  wav24(1, 'WAV 24-bit', 'wav'),
  wav32float(2, 'WAV 32-bit Float', 'wav'),
  flac16(3, 'FLAC 16-bit', 'flac'),
  flac24(4, 'FLAC 24-bit', 'flac'),
  mp3_320(5, 'MP3 320kbps', 'mp3'),
  mp3_256(6, 'MP3 256kbps', 'mp3'),
  mp3_192(7, 'MP3 192kbps', 'mp3'),
  mp3_128(8, 'MP3 128kbps', 'mp3');

  final int code;
  final String label;
  final String extension;

  const ExportFormatType(this.code, this.label, this.extension);

  /// Get format by code
  static ExportFormatType fromCode(int code) {
    return ExportFormatType.values.firstWhere(
      (f) => f.code == code,
      orElse: () => ExportFormatType.wav24,
    );
  }

  /// Check if this is a lossless format
  bool get isLossless => code <= 4;

  /// Check if this is MP3
  bool get isMp3 => code >= 5;

  /// Check if this is FLAC
  bool get isFlac => code == 3 || code == 4;

  /// Check if this is WAV
  bool get isWav => code <= 2;
}

// Legacy enum for backwards compatibility
enum ExportFormat { wav, mp3 }

enum ExportQuality { low, medium, high, lossless }

class ExportSettings {
  final ExportFormat format;
  final ExportQuality quality;
  final int sampleRate;
  final int bitDepth; // 16, 24, or 32
  final int channels; // 1 or 2
  final bool normalize;
  final bool dither;
  final bool truePeakLimit;
  final double truePeakCeiling; // dBTP

  const ExportSettings({
    this.format = ExportFormat.wav,
    this.quality = ExportQuality.high,
    this.sampleRate = 48000,
    this.bitDepth = 24,
    this.channels = 2,
    this.normalize = true,
    this.dither = false,
    this.truePeakLimit = true,
    this.truePeakCeiling = -1.0,
  });

  ExportSettings copyWith({
    ExportFormat? format,
    ExportQuality? quality,
    int? sampleRate,
    int? bitDepth,
    int? channels,
    bool? normalize,
    bool? dither,
    bool? truePeakLimit,
    double? truePeakCeiling,
  }) {
    return ExportSettings(
      format: format ?? this.format,
      quality: quality ?? this.quality,
      sampleRate: sampleRate ?? this.sampleRate,
      bitDepth: bitDepth ?? this.bitDepth,
      channels: channels ?? this.channels,
      normalize: normalize ?? this.normalize,
      dither: dither ?? this.dither,
      truePeakLimit: truePeakLimit ?? this.truePeakLimit,
      truePeakCeiling: truePeakCeiling ?? this.truePeakCeiling,
    );
  }
}

class ExportClip {
  final String id;
  final String name;
  final double startTime;
  final double duration;
  final Float32List audioData;
  final int sampleRate;
  final double gainDb;
  final double pan;

  const ExportClip({
    required this.id,
    required this.name,
    required this.startTime,
    required this.duration,
    required this.audioData,
    required this.sampleRate,
    this.gainDb = 0,
    this.pan = 0,
  });
}

enum ExportStage { preparing, rendering, encoding, complete, error }

class ExportProgress {
  final ExportStage stage;
  final double progress; // 0-1
  final String message;

  const ExportProgress({
    this.stage = ExportStage.complete,
    this.progress = 0,
    this.message = '',
  });
}

// ============ Constants ============

const ExportSettings kDefaultExportSettings = ExportSettings();

// ============ Provider ============

class AudioExportProvider extends ChangeNotifier {
  ExportProgress _progress = const ExportProgress();
  bool _isExporting = false;
  bool _aborted = false;

  ExportProgress get progress => _progress;
  bool get isExporting => _isExporting;

  // ═══════════════════════════════════════════════════════════════════════════
  // FULL MIX EXPORT (via Rust engine)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export full project mix to file using Rust engine
  ///
  /// This is the professional offline bounce that renders through
  /// the entire engine (tracks + plugins + buses + master).
  ///
  /// [outputPath] - Full path to output file
  /// [format] - See ExportFormatType for codes:
  ///   0=WAV 16-bit, 1=WAV 24-bit, 2=WAV 32-bit float,
  ///   3=FLAC 16-bit, 4=FLAC 24-bit,
  ///   5=MP3 320kbps, 6=MP3 256kbps, 7=MP3 192kbps, 8=MP3 128kbps
  /// [sampleRate] - Output sample rate (0 = use project rate)
  /// [startTime] - Start time in seconds
  /// [endTime] - End time in seconds
  /// [normalize] - Normalize output to -0.1 dBFS
  ///
  /// Returns true on success
  Future<bool> exportFullMix({
    required String outputPath,
    int format = 1, // Default to WAV 24-bit (ExportFormatType.wav24.code)
    int sampleRate = 0, // 0 = use project rate
    double startTime = 0.0,
    double endTime = -1.0, // -1 = auto-detect from content
    bool normalize = false,
  }) async {
    if (_isExporting) {
      return false;
    }

    _isExporting = true;
    _aborted = false;
    notifyListeners();

    try {
      _updateProgress(ExportStage.preparing, 0, 'Preparing full mix export...');

      // Start export via FFI
      _updateProgress(ExportStage.rendering, 0.1, 'Rendering full mix...');

      // Call Rust engine for offline bounce
      final success = engine_api.exportAudio(
        outputPath,
        format,
        sampleRate,
        startTime,
        endTime,
        normalize: normalize,
      );

      if (!success) {
        throw Exception('Full mix export failed');
      }

      // Poll progress until complete
      while (engine_api.exportIsExporting()) {
        if (_aborted) {
          // TODO: Add abort FFI function
          throw Exception('Export aborted by user');
        }

        final progress = engine_api.exportGetProgress();
        _updateProgress(
          ExportStage.rendering,
          0.1 + (progress / 100.0) * 0.85,
          'Rendering... ${progress.toStringAsFixed(1)}%',
        );

        // Small delay to not spam updates
        await Future.delayed(const Duration(milliseconds: 100));
      }

      _updateProgress(
        ExportStage.complete,
        1.0,
        'Full mix exported to $outputPath',
      );

      return true;
    } catch (e) {
      _updateProgress(ExportStage.error, 0, 'Full mix export failed: $e');
      return false;
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  /// Export full project mix with typed format
  ///
  /// Convenience wrapper for exportFullMix that uses ExportFormatType enum.
  Future<bool> exportFullMixTyped({
    required String outputPath,
    ExportFormatType format = ExportFormatType.wav24,
    int sampleRate = 0,
    double startTime = 0.0,
    double endTime = -1.0,
    bool normalize = false,
  }) {
    return exportFullMix(
      outputPath: outputPath,
      format: format.code,
      sampleRate: sampleRate,
      startTime: startTime,
      endTime: endTime,
      normalize: normalize,
    );
  }

  /// Export stems with typed format
  ///
  /// Convenience wrapper for exportStems that uses ExportFormatType enum.
  Future<int> exportStemsTyped({
    required String outputDir,
    ExportFormatType format = ExportFormatType.wav24,
    int sampleRate = 48000,
    double startTime = 0,
    double endTime = -1,
    bool normalize = false,
    bool includeBuses = true,
    String prefix = '',
  }) {
    return exportStems(
      outputDir: outputDir,
      format: format.code,
      sampleRate: sampleRate,
      startTime: startTime,
      endTime: endTime,
      normalize: normalize,
      includeBuses: includeBuses,
      prefix: prefix,
    );
  }

  /// Get export progress from Rust engine (0.0-100.0)
  double getEngineExportProgress() {
    return engine_api.exportGetProgress();
  }

  /// Check if Rust engine is currently exporting
  bool isEngineExporting() {
    return engine_api.exportIsExporting();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLIP-BASED EXPORT (Dart implementation)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export clips to WAV file
  Future<Uint8List?> exportMix({
    required List<ExportClip> clips,
    required double duration,
    required String fileName,
    ExportSettings settings = kDefaultExportSettings,
  }) async {
    if (_isExporting) {
      return null;
    }

    _isExporting = true;
    _aborted = false;
    notifyListeners();

    try {
      // Prepare
      _updateProgress(ExportStage.preparing, 0, 'Preparing render...');

      if (clips.isEmpty) {
        throw Exception('No clips to export');
      }

      // Calculate total samples
      final totalSamples = (duration * settings.sampleRate).ceil();
      final numChannels = settings.channels;

      // Allocate output buffers
      final outputL = Float32List(totalSamples);
      final outputR = numChannels > 1 ? Float32List(totalSamples) : outputL;

      // Render
      _updateProgress(ExportStage.rendering, 0.1, 'Rendering clips...');

      for (int i = 0; i < clips.length; i++) {
        if (_aborted) return null;

        final clip = clips[i];
        await _renderClip(clip, outputL, outputR, settings.sampleRate);

        _updateProgress(
          ExportStage.rendering,
          0.1 + (i / clips.length) * 0.6,
          'Rendering clip ${i + 1}/${clips.length}...',
        );
      }

      if (_aborted) return null;

      // Apply processing
      _updateProgress(ExportStage.encoding, 0.75, 'Processing audio...');

      final samples = [outputL, if (numChannels > 1) outputR];

      // True peak limiting
      if (settings.truePeakLimit) {
        _applyTruePeakLimit(samples, settings.truePeakCeiling);
      }

      // Normalize
      if (settings.normalize) {
        _normalizeBuffer(samples, -1.0);

        // Re-apply limiter after normalization
        if (settings.truePeakLimit) {
          _applyTruePeakLimit(samples, settings.truePeakCeiling);
        }
      }

      // Dither
      if (settings.dither && settings.bitDepth < 32) {
        _applyDither(samples, settings.bitDepth);
      }

      _updateProgress(ExportStage.encoding, 0.85, 'Encoding WAV...');

      // Encode WAV
      final wavData = _encodeWav(
        samples,
        settings.sampleRate,
        settings.bitDepth,
      );

      _updateProgress(ExportStage.complete, 1.0, 'Export complete!');

      return wavData;
    } catch (e) {
      _updateProgress(ExportStage.error, 0, 'Export failed: $e');
      return null;
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  /// Abort current export
  void abort() {
    _aborted = true;
  }

  /// Export stems (individual tracks) to separate files
  ///
  /// [outputDir] - Directory to export stems to
  /// [format] - See ExportFormatType for codes (0-8)
  /// [sampleRate] - Output sample rate
  /// [startTime] - Start time in seconds
  /// [endTime] - End time in seconds
  /// [normalize] - Whether to normalize each stem
  /// [includeBuses] - Whether to include bus outputs
  /// [prefix] - Optional filename prefix
  ///
  /// Returns number of exported stems, or -1 on error
  Future<int> exportStems({
    required String outputDir,
    int format = 1, // Default to 24-bit
    int sampleRate = 48000,
    double startTime = 0,
    double endTime = -1, // -1 means auto-detect from content
    bool normalize = false,
    bool includeBuses = true,
    String prefix = '',
  }) async {
    if (_isExporting) {
      return -1;
    }

    _isExporting = true;
    _aborted = false;
    notifyListeners();

    try {
      _updateProgress(ExportStage.preparing, 0, 'Preparing stems export...');

      _updateProgress(ExportStage.rendering, 0.1, 'Exporting stems...');

      // Call Rust backend for stems export directly
      final result = engine_api.exportStems(
        outputDir,
        format,
        sampleRate,
        startTime,
        endTime,
        normalize: normalize,
        includeBuses: includeBuses,
        prefix: prefix,
      );

      if (result < 0) {
        throw Exception('Stems export failed');
      }

      _updateProgress(
        ExportStage.complete,
        1.0,
        'Exported $result stems to $outputDir',
      );

      return result;
    } catch (e) {
      _updateProgress(ExportStage.error, 0, 'Stems export failed: $e');
      return -1;
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  void _updateProgress(ExportStage stage, double progress, String message) {
    _progress = ExportProgress(
      stage: stage,
      progress: progress,
      message: message,
    );
    notifyListeners();
  }

  Future<void> _renderClip(
    ExportClip clip,
    Float32List outputL,
    Float32List outputR,
    int targetSampleRate,
  ) async {
    final startSample = (clip.startTime * targetSampleRate).floor();
    final clipSamples = clip.audioData.length;
    final gain = _dbToLinear(clip.gainDb);

    // Simple pan law
    final panL = clip.pan <= 0 ? 1.0 : 1.0 - clip.pan;
    final panR = clip.pan >= 0 ? 1.0 : 1.0 + clip.pan;

    for (int i = 0; i < clipSamples && startSample + i < outputL.length; i++) {
      final sample = clip.audioData[i] * gain;
      outputL[startSample + i] += sample * panL;
      outputR[startSample + i] += sample * panR;
    }

    // Yield to event loop
    await Future.delayed(Duration.zero);
  }

  void _normalizeBuffer(List<Float32List> samples, double targetPeakDb) {
    double maxPeak = 0;

    for (final channel in samples) {
      for (int i = 0; i < channel.length; i++) {
        final abs = channel[i].abs();
        if (abs > maxPeak) maxPeak = abs;
      }
    }

    if (maxPeak == 0) return;

    final targetLinear = _dbToLinear(targetPeakDb);
    final gain = targetLinear / maxPeak;

    for (final channel in samples) {
      for (int i = 0; i < channel.length; i++) {
        channel[i] *= gain;
      }
    }
  }

  void _applyTruePeakLimit(List<Float32List> samples, double ceiling) {
    final ceilingLinear = _dbToLinear(ceiling);

    for (final channel in samples) {
      for (int i = 0; i < channel.length; i++) {
        if (channel[i] > ceilingLinear) {
          channel[i] = ceilingLinear;
        } else if (channel[i] < -ceilingLinear) {
          channel[i] = -ceilingLinear;
        }
      }
    }
  }

  void _applyDither(List<Float32List> samples, int bitDepth) {
    final ditherAmount = 1.0 / (1 << (bitDepth - 1));
    final random = _SimpleRandom();

    for (final channel in samples) {
      for (int i = 0; i < channel.length; i++) {
        // TPDF dither
        final dither = (random.nextDouble() + random.nextDouble() - 1) * ditherAmount;
        channel[i] += dither;
      }
    }
  }

  Uint8List _encodeWav(List<Float32List> samples, int sampleRate, int bitDepth) {
    final numChannels = samples.length;
    final length = samples[0].length;
    final bytesPerSample = bitDepth ~/ 8;
    final blockAlign = numChannels * bytesPerSample;
    final byteRate = sampleRate * blockAlign;
    final dataSize = length * blockAlign;
    final bufferSize = 44 + dataSize;

    final buffer = Uint8List(bufferSize);
    final view = ByteData.view(buffer.buffer);

    // RIFF header
    _writeString(buffer, 0, 'RIFF');
    view.setUint32(4, 36 + dataSize, Endian.little);
    _writeString(buffer, 8, 'WAVE');

    // fmt chunk
    _writeString(buffer, 12, 'fmt ');
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, bitDepth == 32 ? 3 : 1, Endian.little); // 3 = float, 1 = PCM
    view.setUint16(22, numChannels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, byteRate, Endian.little);
    view.setUint16(32, blockAlign, Endian.little);
    view.setUint16(34, bitDepth, Endian.little);

    // data chunk
    _writeString(buffer, 36, 'data');
    view.setUint32(40, dataSize, Endian.little);

    // Interleaved samples
    int offset = 44;
    for (int i = 0; i < length; i++) {
      for (int ch = 0; ch < numChannels; ch++) {
        final sample = samples[ch][i].clamp(-1.0, 1.0);

        if (bitDepth == 32) {
          view.setFloat32(offset, sample, Endian.little);
        } else if (bitDepth == 24) {
          final intSample = (sample * 8388607).round();
          buffer[offset] = intSample & 0xFF;
          buffer[offset + 1] = (intSample >> 8) & 0xFF;
          buffer[offset + 2] = (intSample >> 16) & 0xFF;
        } else {
          final intSample = (sample * 32767).round();
          view.setInt16(offset, intSample, Endian.little);
        }
        offset += bytesPerSample;
      }
    }

    return buffer;
  }

  void _writeString(Uint8List buffer, int offset, String string) {
    for (int i = 0; i < string.length; i++) {
      buffer[offset + i] = string.codeUnitAt(i);
    }
  }

  double _dbToLinear(double db) {
    return _pow(10.0, db / 20.0);
  }
}

// Simple pseudo-random for dithering
class _SimpleRandom {
  int _seed = DateTime.now().microsecondsSinceEpoch;

  double nextDouble() {
    _seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF;
    return _seed / 0x7FFFFFFF;
  }
}

// Math utilities using dart:math
double _pow(double x, double y) => math.pow(x, y).toDouble();
