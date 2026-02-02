/// Audio Export Queue Service (P12.1.20)
///
/// Batch audio export with queue management.
/// Features:
/// - Queue multiple export jobs
/// - Format conversion
/// - Progress tracking per job and overall
/// - Cancel individual jobs or entire queue
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

// =============================================================================
// EXPORT JOB MODELS
// =============================================================================

/// Output audio format for export
enum AudioExportFormat {
  wav16('WAV 16-bit', 'wav', 16),
  wav24('WAV 24-bit', 'wav', 24),
  wav32f('WAV 32-bit float', 'wav', 32),
  flac('FLAC', 'flac', 24),
  mp3High('MP3 320kbps', 'mp3', 320),
  mp3Medium('MP3 192kbps', 'mp3', 192),
  mp3Low('MP3 128kbps', 'mp3', 128),
  ogg('OGG Vorbis', 'ogg', 0);

  final String displayName;
  final String extension;
  final int quality; // bitDepth for wav/flac, bitrate for mp3

  const AudioExportFormat(this.displayName, this.extension, this.quality);
}

/// Export job status
enum ExportJobStatus {
  pending,
  processing,
  completed,
  failed,
  cancelled,
}

/// A single export job
class AudioExportJob {
  final String id;
  final String inputPath;
  final String outputPath;
  final AudioExportFormat format;
  final double? normalizeToLufs; // null = no normalization
  final bool applyLimiter;
  final DateTime createdAt;
  ExportJobStatus status;
  double progress;
  String? errorMessage;
  DateTime? completedAt;

  AudioExportJob({
    required this.id,
    required this.inputPath,
    required this.outputPath,
    required this.format,
    this.normalizeToLufs,
    this.applyLimiter = false,
    DateTime? createdAt,
    this.status = ExportJobStatus.pending,
    this.progress = 0.0,
    this.errorMessage,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get inputFileName {
    final parts = inputPath.split('/');
    return parts.isNotEmpty ? parts.last : inputPath;
  }

  String get outputFileName {
    final parts = outputPath.split('/');
    return parts.isNotEmpty ? parts.last : outputPath;
  }

  AudioExportJob copyWith({
    ExportJobStatus? status,
    double? progress,
    String? errorMessage,
    DateTime? completedAt,
  }) {
    return AudioExportJob(
      id: id,
      inputPath: inputPath,
      outputPath: outputPath,
      format: format,
      normalizeToLufs: normalizeToLufs,
      applyLimiter: applyLimiter,
      createdAt: createdAt,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

// =============================================================================
// AUDIO EXPORT QUEUE SERVICE — Singleton
// =============================================================================

class AudioExportQueueService extends ChangeNotifier {
  static final AudioExportQueueService _instance = AudioExportQueueService._();
  static AudioExportQueueService get instance => _instance;

  AudioExportQueueService._();

  final List<AudioExportJob> _queue = [];
  bool _isProcessing = false;
  int _completedCount = 0;
  int _failedCount = 0;

  // ─── Getters ────────────────────────────────────────────────────────────────

  List<AudioExportJob> get queue => List.unmodifiable(_queue);

  List<AudioExportJob> get pendingJobs =>
      _queue.where((j) => j.status == ExportJobStatus.pending).toList();

  List<AudioExportJob> get completedJobs =>
      _queue.where((j) => j.status == ExportJobStatus.completed).toList();

  List<AudioExportJob> get failedJobs =>
      _queue.where((j) => j.status == ExportJobStatus.failed).toList();

  bool get isProcessing => _isProcessing;

  int get totalJobs => _queue.length;

  int get completedCount => _completedCount;

  int get failedCount => _failedCount;

  double get overallProgress {
    if (_queue.isEmpty) return 0.0;
    final total = _queue.fold<double>(0, (sum, job) => sum + job.progress);
    return total / _queue.length;
  }

  AudioExportJob? get currentJob {
    try {
      return _queue.firstWhere((j) => j.status == ExportJobStatus.processing);
    } catch (_) {
      return null;
    }
  }

  // ─── Queue Management ───────────────────────────────────────────────────────

  /// Add a job to the export queue
  String addJob({
    required String inputPath,
    required String outputPath,
    required AudioExportFormat format,
    double? normalizeToLufs,
    bool applyLimiter = false,
  }) {
    final id = 'export_${DateTime.now().millisecondsSinceEpoch}_${_queue.length}';

    final job = AudioExportJob(
      id: id,
      inputPath: inputPath,
      outputPath: outputPath,
      format: format,
      normalizeToLufs: normalizeToLufs,
      applyLimiter: applyLimiter,
    );

    _queue.add(job);
    notifyListeners();
    debugPrint('[AudioExportQueue] Added job: ${job.inputFileName} → ${format.displayName}');

    return id;
  }

  /// Remove a job from the queue
  void removeJob(String jobId) {
    final index = _queue.indexWhere((j) => j.id == jobId);
    if (index < 0) return;

    final job = _queue[index];
    if (job.status == ExportJobStatus.processing) {
      // Mark for cancellation, will be handled in processing loop
      _queue[index] = job.copyWith(status: ExportJobStatus.cancelled);
    } else {
      _queue.removeAt(index);
    }

    notifyListeners();
    debugPrint('[AudioExportQueue] Removed job: $jobId');
  }

  /// Clear all completed and failed jobs
  void clearFinishedJobs() {
    _queue.removeWhere((j) =>
        j.status == ExportJobStatus.completed ||
        j.status == ExportJobStatus.failed ||
        j.status == ExportJobStatus.cancelled);
    notifyListeners();
  }

  /// Clear entire queue (cancels processing)
  void clearAll() {
    _isProcessing = false;
    _queue.clear();
    _completedCount = 0;
    _failedCount = 0;
    notifyListeners();
  }

  // ─── Processing ─────────────────────────────────────────────────────────────

  /// Start processing the queue
  Future<void> startProcessing() async {
    if (_isProcessing) return;
    if (pendingJobs.isEmpty) return;

    _isProcessing = true;
    notifyListeners();

    while (_isProcessing && pendingJobs.isNotEmpty) {
      final job = pendingJobs.first;
      await _processJob(job);
    }

    _isProcessing = false;
    notifyListeners();
    debugPrint('[AudioExportQueue] Processing complete: $_completedCount succeeded, $_failedCount failed');
  }

  /// Stop processing (current job will complete)
  void stopProcessing() {
    _isProcessing = false;
    notifyListeners();
  }

  Future<void> _processJob(AudioExportJob job) async {
    final index = _queue.indexWhere((j) => j.id == job.id);
    if (index < 0) return;

    // Mark as processing
    _queue[index] = job.copyWith(status: ExportJobStatus.processing, progress: 0.0);
    notifyListeners();

    try {
      // Simulate export process (in real implementation, call FFI)
      await _simulateExport(job.id);

      // Check if cancelled during processing
      final currentJob = _queue.firstWhere((j) => j.id == job.id);
      if (currentJob.status == ExportJobStatus.cancelled) {
        debugPrint('[AudioExportQueue] Job cancelled: ${job.id}');
        return;
      }

      // Mark as completed
      _queue[index] = _queue[index].copyWith(
        status: ExportJobStatus.completed,
        progress: 1.0,
        completedAt: DateTime.now(),
      );
      _completedCount++;
      debugPrint('[AudioExportQueue] Job completed: ${job.inputFileName}');
    } catch (e) {
      // Mark as failed
      _queue[index] = _queue[index].copyWith(
        status: ExportJobStatus.failed,
        errorMessage: e.toString(),
      );
      _failedCount++;
      debugPrint('[AudioExportQueue] Job failed: ${job.inputFileName} - $e');
    }

    notifyListeners();
  }

  Future<void> _simulateExport(String jobId) async {
    // Simulate export progress (replace with actual FFI calls)
    const totalSteps = 20;
    for (var i = 1; i <= totalSteps; i++) {
      await Future.delayed(const Duration(milliseconds: 100));

      final index = _queue.indexWhere((j) => j.id == jobId);
      if (index < 0) return;

      final job = _queue[index];
      if (job.status == ExportJobStatus.cancelled) return;

      _queue[index] = job.copyWith(progress: i / totalSteps);
      notifyListeners();
    }
  }

  // ─── Batch Operations ───────────────────────────────────────────────────────

  /// Add multiple files to queue with same settings
  List<String> addBatch({
    required List<String> inputPaths,
    required String outputDirectory,
    required AudioExportFormat format,
    double? normalizeToLufs,
    bool applyLimiter = false,
  }) {
    final jobIds = <String>[];

    for (final inputPath in inputPaths) {
      final fileName = inputPath.split('/').last;
      final nameWithoutExt = fileName.contains('.')
          ? fileName.substring(0, fileName.lastIndexOf('.'))
          : fileName;
      final outputPath = '$outputDirectory/$nameWithoutExt.${format.extension}';

      final id = addJob(
        inputPath: inputPath,
        outputPath: outputPath,
        format: format,
        normalizeToLufs: normalizeToLufs,
        applyLimiter: applyLimiter,
      );
      jobIds.add(id);
    }

    return jobIds;
  }
}
