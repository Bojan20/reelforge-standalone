/// Export Service — Unified Audio Export System
///
/// P2.1: Complete export functionality for DAW and SlotLab.
///
/// Features:
/// - WAV/FLAC/MP3/OGG format support
/// - Stems export (individual tracks/buses)
/// - Peak normalization options
/// - Progress tracking with ETA
/// - Cancellation support
/// - Batch export for SlotLab events

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../src/rust/native_ffi.dart';
import '../providers/subsystems/composite_event_system_provider.dart';
import 'service_locator.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ENUMS & DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio export format
enum ExportFormat {
  wav(0, 'WAV', '.wav', 'Uncompressed audio'),
  flac(1, 'FLAC', '.flac', 'Lossless compression'),
  mp3(2, 'MP3', '.mp3', 'Lossy compression (LAME)'),
  ogg(3, 'OGG', '.ogg', 'Lossy compression (Vorbis)');

  final int code;
  final String label;
  final String extension;
  final String description;

  const ExportFormat(this.code, this.label, this.extension, this.description);
}

/// Sample rate for export
enum ExportSampleRate {
  rate44100(44100, '44.1 kHz', 'CD quality'),
  rate48000(48000, '48 kHz', 'Video standard'),
  rate88200(88200, '88.2 kHz', 'High resolution'),
  rate96000(96000, '96 kHz', 'High resolution'),
  rate176400(176400, '176.4 kHz', 'Ultra high resolution'),
  rate192000(192000, '192 kHz', 'Ultra high resolution');

  final int value;
  final String label;
  final String description;

  const ExportSampleRate(this.value, this.label, this.description);
}

/// Bit depth for export
enum ExportBitDepth {
  bit16(16, '16-bit', 'CD quality'),
  bit24(24, '24-bit', 'Professional standard'),
  bit32(32, '32-bit float', 'Maximum headroom');

  final int value;
  final String label;
  final String description;

  const ExportBitDepth(this.value, this.label, this.description);
}

/// Normalization mode
enum NormalizationMode {
  none('None', 'No normalization'),
  peak('Peak', 'Normalize to peak level'),
  lufs('LUFS', 'Normalize to loudness standard');

  final String label;
  final String description;

  const NormalizationMode(this.label, this.description);
}

/// Export job configuration
class ExportConfig {
  final String outputPath;
  final ExportFormat format;
  final ExportSampleRate sampleRate;
  final ExportBitDepth bitDepth;
  final NormalizationMode normalization;
  final double normalizationTarget; // dB for peak, LUFS for loudness
  final double startTime;
  final double endTime;
  final bool includeTail; // Include reverb tail after end

  const ExportConfig({
    required this.outputPath,
    this.format = ExportFormat.wav,
    this.sampleRate = ExportSampleRate.rate48000,
    this.bitDepth = ExportBitDepth.bit24,
    this.normalization = NormalizationMode.none,
    this.normalizationTarget = -1.0,
    this.startTime = 0.0,
    this.endTime = -1.0, // -1 means end of project
    this.includeTail = true,
  });

  ExportConfig copyWith({
    String? outputPath,
    ExportFormat? format,
    ExportSampleRate? sampleRate,
    ExportBitDepth? bitDepth,
    NormalizationMode? normalization,
    double? normalizationTarget,
    double? startTime,
    double? endTime,
    bool? includeTail,
  }) {
    return ExportConfig(
      outputPath: outputPath ?? this.outputPath,
      format: format ?? this.format,
      sampleRate: sampleRate ?? this.sampleRate,
      bitDepth: bitDepth ?? this.bitDepth,
      normalization: normalization ?? this.normalization,
      normalizationTarget: normalizationTarget ?? this.normalizationTarget,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      includeTail: includeTail ?? this.includeTail,
    );
  }
}

/// Stems export configuration
class StemsExportConfig {
  final String outputDirectory;
  final String filePrefix;
  final ExportFormat format;
  final ExportSampleRate sampleRate;
  final NormalizationMode normalization;
  final double normalizationTarget;
  final double startTime;
  final double endTime;
  final bool exportTracks;
  final bool exportBuses;
  final List<int>? selectedTrackIds; // null = all tracks
  final List<int>? selectedBusIds;   // null = all buses

  const StemsExportConfig({
    required this.outputDirectory,
    this.filePrefix = 'stem',
    this.format = ExportFormat.wav,
    this.sampleRate = ExportSampleRate.rate48000,
    this.normalization = NormalizationMode.none,
    this.normalizationTarget = -1.0,
    this.startTime = 0.0,
    this.endTime = -1.0,
    this.exportTracks = true,
    this.exportBuses = true,
    this.selectedTrackIds,
    this.selectedBusIds,
  });
}

/// Export progress data
class ExportProgress {
  final double progress; // 0.0 - 1.0
  final double speedFactor; // x realtime
  final double etaSeconds;
  final double peakLevel; // dB
  final bool isComplete;
  final bool wasCancelled;
  final String? error;

  const ExportProgress({
    this.progress = 0.0,
    this.speedFactor = 0.0,
    this.etaSeconds = 0.0,
    this.peakLevel = -60.0,
    this.isComplete = false,
    this.wasCancelled = false,
    this.error,
  });

  String get progressPercent => '${(progress * 100).toStringAsFixed(1)}%';

  String get etaFormatted {
    if (etaSeconds <= 0 || etaSeconds.isInfinite) return '--:--';
    final minutes = (etaSeconds / 60).floor();
    final seconds = (etaSeconds % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get speedFormatted => '${speedFactor.toStringAsFixed(1)}x';
}

/// SlotLab batch export configuration
class SlotLabBatchExportConfig {
  final String outputDirectory;
  final ExportFormat format;
  final ExportSampleRate sampleRate;
  final NormalizationMode normalization;
  final double normalizationTarget;
  final List<String> eventIds; // Event IDs to export
  final bool includeVariations;
  final int variationCount;

  const SlotLabBatchExportConfig({
    required this.outputDirectory,
    this.format = ExportFormat.wav,
    this.sampleRate = ExportSampleRate.rate48000,
    this.normalization = NormalizationMode.peak,
    this.normalizationTarget = -1.0,
    required this.eventIds,
    this.includeVariations = false,
    this.variationCount = 4,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORT SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Unified export service singleton
class ExportService extends ChangeNotifier {
  static ExportService? _instance;
  static ExportService get instance => _instance ??= ExportService._();

  ExportService._();

  final NativeFFI _ffi = sl<NativeFFI>();

  // Current export state
  bool _isExporting = false;
  ExportConfig? _currentConfig;
  Timer? _progressTimer;
  ExportProgress _progress = const ExportProgress();

  // Stream for progress updates
  final _progressController = StreamController<ExportProgress>.broadcast();
  Stream<ExportProgress> get progressStream => _progressController.stream;

  // Getters
  bool get isExporting => _isExporting;
  ExportConfig? get currentConfig => _currentConfig;
  ExportProgress get progress => _progress;

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN EXPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start export with given configuration
  Future<bool> startExport(ExportConfig config) async {
    if (_isExporting) {
      return false;
    }

    // Ensure output directory exists
    final dir = Directory(path.dirname(config.outputPath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Add extension if missing
    String outputPath = config.outputPath;
    if (!outputPath.endsWith(config.format.extension)) {
      outputPath = '$outputPath${config.format.extension}';
    }

    _currentConfig = config.copyWith(outputPath: outputPath);
    _isExporting = true;
    _progress = const ExportProgress();
    notifyListeners();

    // Start FFI export
    final result = _ffi.bounceStart(
      outputPath,
      config.format.code,
      config.bitDepth.value,
      config.sampleRate.value,
      config.startTime,
      config.endTime,
      config.normalization != NormalizationMode.none,
      config.normalizationTarget,
    );

    if (result != 0) {
      _isExporting = false;
      _progress = const ExportProgress(error: 'Failed to start export');
      notifyListeners();
      return false;
    }

    // Start progress polling
    _startProgressPolling();

    return true;
  }

  /// Start export with simple parameters
  Future<bool> exportAudio({
    required String outputPath,
    ExportFormat format = ExportFormat.wav,
    ExportSampleRate sampleRate = ExportSampleRate.rate48000,
    double startTime = 0.0,
    double endTime = -1.0,
    bool normalize = false,
  }) async {
    final config = ExportConfig(
      outputPath: outputPath,
      format: format,
      sampleRate: sampleRate,
      startTime: startTime,
      endTime: endTime,
      normalization: normalize ? NormalizationMode.peak : NormalizationMode.none,
      normalizationTarget: -1.0,
    );

    return startExport(config);
  }

  /// Cancel current export
  void cancelExport() {
    if (!_isExporting) return;

    _ffi.bounceCancel();
    _stopProgressPolling();

    _isExporting = false;
    _progress = const ExportProgress(wasCancelled: true);
    _progressController.add(_progress);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEMS EXPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export stems (individual tracks and buses)
  Future<int> exportStems(StemsExportConfig config) async {
    if (_isExporting) {
      return -1;
    }

    // Ensure output directory exists
    final dir = Directory(config.outputDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    _isExporting = true;
    notifyListeners();

    final result = _ffi.exportStems(
      config.outputDirectory,
      config.format.code,
      config.sampleRate.value,
      config.startTime,
      config.endTime,
      config.normalization == NormalizationMode.peak,
      config.exportBuses,
      config.filePrefix,
    );

    _isExporting = false;
    notifyListeners();

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SLOTLAB BATCH EXPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export multiple SlotLab events via offline pipeline
  ///
  /// For each event, processes the primary audio layer through the
  /// rf-offline pipeline (format conversion + normalization).
  Future<Map<String, String>> exportSlotLabEvents(SlotLabBatchExportConfig config) async {
    final results = <String, String>{};

    // Ensure output directory exists
    final dir = Directory(config.outputDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final compositeProvider = sl<CompositeEventSystemProvider>();

    for (final eventId in config.eventIds) {
      final event = compositeProvider.getCompositeEvent(eventId);
      if (event == null) continue;

      // Find layers with valid audio paths
      final validLayers = event.layers.where((l) => l.audioPath.isNotEmpty).toList();
      if (validLayers.isEmpty) continue;

      // Use safe filename from event name
      final safeName = event.name
          .replaceAll(RegExp(r'[^\w\-.]'), '_')
          .replaceAll(RegExp(r'_+'), '_');

      if (config.includeVariations && config.variationCount > 1) {
        // Export multiple variations (each layer as a separate file)
        final layerCount = validLayers.length.clamp(1, config.variationCount);
        for (var i = 0; i < layerCount; i++) {
          final layer = validLayers[i];
          final outputPath = path.join(
            config.outputDirectory,
            '${safeName}_v${i + 1}${config.format.extension}',
          );

          final success = await _processLayerThroughPipeline(
            inputPath: layer.audioPath,
            outputPath: outputPath,
            formatCode: config.format.code,
            normalize: config.normalization != NormalizationMode.none,
            normTarget: config.normalizationTarget,
          );

          if (success) {
            results['${eventId}_v${i + 1}'] = outputPath;
          }
        }
      } else {
        // Export primary layer only
        final primaryLayer = validLayers.first;
        final outputPath = path.join(
          config.outputDirectory,
          '$safeName${config.format.extension}',
        );

        final success = await _processLayerThroughPipeline(
          inputPath: primaryLayer.audioPath,
          outputPath: outputPath,
          formatCode: config.format.code,
          normalize: config.normalization != NormalizationMode.none,
          normTarget: config.normalizationTarget,
        );

        if (success) {
          results[eventId] = outputPath;
        }
      }
    }

    return results;
  }

  /// Process a single audio layer through the offline DSP pipeline
  Future<bool> _processLayerThroughPipeline({
    required String inputPath,
    required String outputPath,
    required int formatCode,
    required bool normalize,
    required double normTarget,
  }) async {
    // Verify source file exists
    if (!await File(inputPath).exists()) return false;

    final handle = _ffi.offlinePipelineCreate();
    if (handle < 0) return false;

    try {
      _ffi.offlinePipelineSetFormat(handle, formatCode);

      final result = _ffi.offlineProcessFile(handle, inputPath, outputPath);
      return result == 0;
    } finally {
      _ffi.offlinePipelineDestroy(handle);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROGRESS POLLING
  // ═══════════════════════════════════════════════════════════════════════════

  void _startProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _updateProgress();
    });
  }

  void _stopProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _updateProgress() {
    if (!_isExporting) {
      _stopProgressPolling();
      return;
    }

    final isComplete = _ffi.bounceIsComplete();
    final wasCancelled = _ffi.bounceWasCancelled();

    _progress = ExportProgress(
      progress: _ffi.bounceGetProgress(),
      speedFactor: _ffi.bounceGetSpeedFactor(),
      etaSeconds: _ffi.bounceGetEta(),
      peakLevel: _ffi.bounceGetPeakLevel(),
      isComplete: isComplete,
      wasCancelled: wasCancelled,
    );

    _progressController.add(_progress);
    notifyListeners();

    if (isComplete || wasCancelled) {
      _stopProgressPolling();
      _isExporting = false;
      _ffi.bounceClear();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Estimate file size for given configuration
  int estimateFileSize(ExportConfig config, double durationSeconds) {
    final sampleRate = config.sampleRate.value;
    final bitDepth = config.bitDepth.value;
    const channels = 2;

    // Raw size
    final rawSize = (sampleRate * bitDepth * channels * durationSeconds / 8).round();

    // Apply compression estimate
    return switch (config.format) {
      ExportFormat.wav => rawSize,
      ExportFormat.flac => (rawSize * 0.5).round(), // ~50% compression
      ExportFormat.mp3 => (rawSize * 0.1).round(),  // ~10% of original
      ExportFormat.ogg => (rawSize * 0.08).round(), // ~8% of original
    };
  }

  /// Format file size for display
  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Get suggested filename based on project name and timestamp
  String suggestFilename(String projectName, ExportFormat format) {
    final timestamp = DateTime.now().toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('T', '_')
        .split('.')[0];
    return '${projectName}_$timestamp${format.extension}';
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _progressController.close();
    super.dispose();
  }
}
