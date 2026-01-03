/// Audio Export Provider
///
/// Offline rendering and export with:
/// - Render timeline to audio buffer
/// - WAV export (16/24/32-bit)
/// - True peak limiting
/// - Normalization
/// - Dithering
/// - Progress tracking

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

// ============ Types ============

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

  /// Export clips to WAV file
  Future<Uint8List?> exportMix({
    required List<ExportClip> clips,
    required double duration,
    required String fileName,
    ExportSettings settings = kDefaultExportSettings,
  }) async {
    if (_isExporting) {
      debugPrint('[AudioExport] Export already in progress');
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
