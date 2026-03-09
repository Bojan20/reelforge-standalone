/// Stem Manager Service — Save/Recall Solo/Mute Configurations + Batch Render
///
/// Features:
/// - Named stem configurations (save/recall solo/mute states per track)
/// - Batch render: render all stem configs sequentially
/// - Render queue with progress tracking
/// - Multi-format output (WAV+OGG simultaneously)
///
/// A "stem config" is a snapshot of which tracks are soloed/muted,
/// used to render individual stems (e.g., "Drums Only", "No Vocals").
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'export_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// A single track's solo/mute state within a stem configuration
class StemTrackState {
  final String trackId;
  final String trackName;
  final bool muted;
  final bool soloed;

  const StemTrackState({
    required this.trackId,
    required this.trackName,
    this.muted = false,
    this.soloed = false,
  });

  StemTrackState copyWith({bool? muted, bool? soloed}) => StemTrackState(
        trackId: trackId,
        trackName: trackName,
        muted: muted ?? this.muted,
        soloed: soloed ?? this.soloed,
      );

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'trackName': trackName,
        'muted': muted,
        'soloed': soloed,
      };

  factory StemTrackState.fromJson(Map<String, dynamic> json) => StemTrackState(
        trackId: json['trackId'] as String,
        trackName: json['trackName'] as String? ?? '',
        muted: json['muted'] as bool? ?? false,
        soloed: json['soloed'] as bool? ?? false,
      );
}

/// A named stem configuration — a snapshot of solo/mute states for all tracks.
///
/// Examples:
/// - "Drums Only" — all drums soloed
/// - "No Vocals" — vocal tracks muted
/// - "Music Stem" — bass + melody + drums soloed
class StemConfig {
  final String id;
  final String name;
  final Map<String, StemTrackState> trackStates;
  final DateTime createdAt;

  StemConfig({
    required this.id,
    required this.name,
    required this.trackStates,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  StemConfig copyWith({String? name, Map<String, StemTrackState>? trackStates}) =>
      StemConfig(
        id: id,
        name: name ?? this.name,
        trackStates: trackStates ?? this.trackStates,
        createdAt: createdAt,
      );

  /// Count of soloed tracks
  int get soloCount => trackStates.values.where((t) => t.soloed).length;

  /// Count of muted tracks
  int get muteCount => trackStates.values.where((t) => t.muted).length;

  /// Summary string for display
  String get summary {
    final parts = <String>[];
    if (soloCount > 0) parts.add('$soloCount solo');
    if (muteCount > 0) parts.add('$muteCount mute');
    if (parts.isEmpty) return 'No changes';
    return parts.join(', ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackStates':
            trackStates.map((k, v) => MapEntry(k, v.toJson())),
        'createdAt': createdAt.toIso8601String(),
      };

  factory StemConfig.fromJson(Map<String, dynamic> json) {
    final statesMap = json['trackStates'] as Map<String, dynamic>? ?? {};
    return StemConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      trackStates: statesMap.map(
        (k, v) => MapEntry(k, StemTrackState.fromJson(v as Map<String, dynamic>)),
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Status of a single render job in the queue
enum RenderJobStatus { pending, rendering, complete, failed, cancelled }

/// A render job in the queue
class RenderJob {
  final String id;
  final StemConfig stemConfig;
  final ExportFormat format;
  final String outputPath;
  RenderJobStatus status;
  double progress;
  String? error;

  RenderJob({
    required this.id,
    required this.stemConfig,
    required this.format,
    required this.outputPath,
    this.status = RenderJobStatus.pending,
    this.progress = 0.0,
    this.error,
  });

  String get displayName => '${stemConfig.name} (${format.label})';

  String get statusLabel => switch (status) {
        RenderJobStatus.pending => 'PENDING',
        RenderJobStatus.rendering => '${(progress * 100).toStringAsFixed(0)}%',
        RenderJobStatus.complete => 'DONE',
        RenderJobStatus.failed => 'FAILED',
        RenderJobStatus.cancelled => 'CANCELLED',
      };
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Stem Manager service — manages stem configurations and render queue.
class StemManagerService extends ChangeNotifier {
  StemManagerService._();
  static final instance = StemManagerService._();

  // ─── Stem Configurations ────────────────────────────────────────────────

  final List<StemConfig> _configs = [];
  List<StemConfig> get configs => List.unmodifiable(_configs);

  int _selectedConfigIndex = -1;
  int get selectedConfigIndex => _selectedConfigIndex;
  StemConfig? get selectedConfig =>
      _selectedConfigIndex >= 0 && _selectedConfigIndex < _configs.length
          ? _configs[_selectedConfigIndex]
          : null;

  int _nextId = 1;

  /// Add a new stem configuration from current solo/mute states
  StemConfig addConfig(
      String name, Map<String, StemTrackState> trackStates) {
    final config = StemConfig(
      id: 'stem_${_nextId++}',
      name: name,
      trackStates: Map.from(trackStates),
    );
    _configs.add(config);
    _selectedConfigIndex = _configs.length - 1;
    notifyListeners();
    return config;
  }

  /// Remove a stem configuration
  void removeConfig(int index) {
    if (index < 0 || index >= _configs.length) return;
    _configs.removeAt(index);
    if (_selectedConfigIndex >= _configs.length) {
      _selectedConfigIndex = _configs.length - 1;
    }
    notifyListeners();
  }

  /// Select a stem configuration
  void selectConfig(int index) {
    if (index < -1 || index >= _configs.length) return;
    _selectedConfigIndex = index;
    notifyListeners();
  }

  /// Rename a stem configuration
  void renameConfig(int index, String newName) {
    if (index < 0 || index >= _configs.length) return;
    _configs[index] = _configs[index].copyWith(name: newName);
    notifyListeners();
  }

  /// Update track states in a configuration
  void updateConfigTrackStates(
      int index, Map<String, StemTrackState> trackStates) {
    if (index < 0 || index >= _configs.length) return;
    _configs[index] = _configs[index].copyWith(trackStates: trackStates);
    notifyListeners();
  }

  /// Duplicate a stem configuration
  void duplicateConfig(int index) {
    if (index < 0 || index >= _configs.length) return;
    final original = _configs[index];
    addConfig('${original.name} (copy)', Map.from(original.trackStates));
  }

  /// Move configuration up in list
  void moveConfigUp(int index) {
    if (index <= 0 || index >= _configs.length) return;
    final config = _configs.removeAt(index);
    _configs.insert(index - 1, config);
    _selectedConfigIndex = index - 1;
    notifyListeners();
  }

  /// Move configuration down in list
  void moveConfigDown(int index) {
    if (index < 0 || index >= _configs.length - 1) return;
    final config = _configs.removeAt(index);
    _configs.insert(index + 1, config);
    _selectedConfigIndex = index + 1;
    notifyListeners();
  }

  // ─── Render Queue ──────────────────────────────────────────────────────

  final List<RenderJob> _renderQueue = [];
  List<RenderJob> get renderQueue => List.unmodifiable(_renderQueue);

  bool _isRendering = false;
  bool get isRendering => _isRendering;

  int _currentJobIndex = -1;
  int get currentJobIndex => _currentJobIndex;

  // Multi-format output formats
  final Set<ExportFormat> _outputFormats = {ExportFormat.wav};
  Set<ExportFormat> get outputFormats => Set.unmodifiable(_outputFormats);

  ExportSampleRate _sampleRate = ExportSampleRate.rate48000;
  ExportSampleRate get sampleRate => _sampleRate;

  NormalizationMode _normalization = NormalizationMode.none;
  NormalizationMode get normalization => _normalization;

  double _normTarget = -1.0;
  double get normTarget => _normTarget;

  String _outputDirectory = '';
  String get outputDirectory => _outputDirectory;

  void toggleOutputFormat(ExportFormat format) {
    if (_outputFormats.contains(format)) {
      if (_outputFormats.length > 1) {
        _outputFormats.remove(format);
      }
    } else {
      _outputFormats.add(format);
    }
    notifyListeners();
  }

  void setSampleRate(ExportSampleRate rate) {
    _sampleRate = rate;
    notifyListeners();
  }

  void setNormalization(NormalizationMode mode) {
    _normalization = mode;
    notifyListeners();
  }

  void setNormTarget(double target) {
    _normTarget = target;
    notifyListeners();
  }

  void setOutputDirectory(String dir) {
    _outputDirectory = dir;
    notifyListeners();
  }

  /// Build render queue from all stem configurations × all output formats
  void buildRenderQueue() {
    _renderQueue.clear();
    int jobId = 1;

    for (final config in _configs) {
      for (final format in _outputFormats) {
        final safeName = config.name
            .replaceAll(RegExp(r'[^\w\-.]'), '_')
            .replaceAll(RegExp(r'_+'), '_');

        _renderQueue.add(RenderJob(
          id: 'job_${jobId++}',
          stemConfig: config,
          format: format,
          outputPath: '$_outputDirectory/$safeName${format.extension}',
        ));
      }
    }
    notifyListeners();
  }

  /// Start batch rendering the queue
  Future<void> startBatchRender({
    required Future<bool> Function(StemConfig config) applySoloMute,
    required Future<bool> Function(String outputPath, ExportFormat format,
            ExportSampleRate sampleRate)
        renderStem,
    required Future<void> Function() restoreSoloMute,
  }) async {
    if (_isRendering || _renderQueue.isEmpty) return;

    _isRendering = true;
    notifyListeners();

    for (int i = 0; i < _renderQueue.length; i++) {
      final job = _renderQueue[i];
      if (job.status == RenderJobStatus.cancelled) continue;

      _currentJobIndex = i;
      job.status = RenderJobStatus.rendering;
      job.progress = 0.0;
      notifyListeners();

      // Apply solo/mute config
      final applied = await applySoloMute(job.stemConfig);
      if (!applied) {
        job.status = RenderJobStatus.failed;
        job.error = 'Failed to apply solo/mute configuration';
        notifyListeners();
        continue;
      }

      // Render
      final success =
          await renderStem(job.outputPath, job.format, _sampleRate);

      if (success) {
        job.status = RenderJobStatus.complete;
        job.progress = 1.0;
      } else {
        job.status = RenderJobStatus.failed;
        job.error = 'Render failed';
      }
      notifyListeners();
    }

    // Restore original solo/mute state
    await restoreSoloMute();

    _isRendering = false;
    _currentJobIndex = -1;
    notifyListeners();
  }

  /// Cancel batch rendering
  void cancelBatchRender() {
    if (!_isRendering) return;

    for (final job in _renderQueue) {
      if (job.status == RenderJobStatus.pending) {
        job.status = RenderJobStatus.cancelled;
      }
    }
    _isRendering = false;
    _currentJobIndex = -1;
    notifyListeners();
  }

  /// Clear completed/failed/cancelled jobs from queue
  void clearCompletedJobs() {
    _renderQueue.removeWhere(
        (j) => j.status != RenderJobStatus.pending &&
               j.status != RenderJobStatus.rendering);
    notifyListeners();
  }

  /// Clear entire render queue
  void clearRenderQueue() {
    if (_isRendering) return;
    _renderQueue.clear();
    _currentJobIndex = -1;
    notifyListeners();
  }

  /// Get render queue stats
  ({int total, int complete, int failed, int pending}) get queueStats {
    int complete = 0, failed = 0, pending = 0;
    for (final job in _renderQueue) {
      switch (job.status) {
        case RenderJobStatus.complete:
          complete++;
        case RenderJobStatus.failed:
          failed++;
        case RenderJobStatus.pending:
        case RenderJobStatus.rendering:
          pending++;
        case RenderJobStatus.cancelled:
          break;
      }
    }
    return (
      total: _renderQueue.length,
      complete: complete,
      failed: failed,
      pending: pending,
    );
  }

  // ─── Serialization ─────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'configs': _configs.map((c) => c.toJson()).toList(),
        'outputFormats': _outputFormats.map((f) => f.name).toList(),
        'sampleRate': _sampleRate.name,
        'normalization': _normalization.name,
        'normTarget': _normTarget,
        'outputDirectory': _outputDirectory,
      };

  void fromJson(Map<String, dynamic> json) {
    _configs.clear();
    final configsList = json['configs'] as List<dynamic>?;
    if (configsList != null) {
      for (final c in configsList) {
        _configs.add(StemConfig.fromJson(c as Map<String, dynamic>));
      }
    }

    final formats = json['outputFormats'] as List<dynamic>?;
    if (formats != null) {
      _outputFormats.clear();
      for (final f in formats) {
        final format = ExportFormat.values
            .where((e) => e.name == f)
            .firstOrNull;
        if (format != null) _outputFormats.add(format);
      }
      if (_outputFormats.isEmpty) _outputFormats.add(ExportFormat.wav);
    }

    final sr = json['sampleRate'] as String?;
    if (sr != null) {
      _sampleRate = ExportSampleRate.values
              .where((e) => e.name == sr)
              .firstOrNull ??
          ExportSampleRate.rate48000;
    }

    final norm = json['normalization'] as String?;
    if (norm != null) {
      _normalization = NormalizationMode.values
              .where((e) => e.name == norm)
              .firstOrNull ??
          NormalizationMode.none;
    }

    _normTarget = (json['normTarget'] as num?)?.toDouble() ?? -1.0;
    _outputDirectory = json['outputDirectory'] as String? ?? '';

    notifyListeners();
  }
}
