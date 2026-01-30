/// Video Export Service
///
/// MP4/WebM/GIF video recording and export for SlotLab:
/// - Frame capture from RenderRepaintBoundary
/// - Multi-format encoding (MP4, WebM, GIF)
/// - Quality presets (Low to Maximum)
/// - Progress callbacks
/// - Export history tracking
///
/// Created: 2026-01-30 (P4.15)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// VIDEO EXPORT ENUMS
// ═══════════════════════════════════════════════════════════════════════════

/// Video export format
enum VideoExportFormat {
  /// MP4 with H.264 codec (most compatible)
  mp4,

  /// WebM with VP9 codec (web-optimized)
  webm,

  /// Animated GIF (legacy, larger file size)
  gif,
}

extension VideoExportFormatExtension on VideoExportFormat {
  String get extension {
    switch (this) {
      case VideoExportFormat.mp4:
        return 'mp4';
      case VideoExportFormat.webm:
        return 'webm';
      case VideoExportFormat.gif:
        return 'gif';
    }
  }

  String get displayName {
    switch (this) {
      case VideoExportFormat.mp4:
        return 'MP4 (H.264)';
      case VideoExportFormat.webm:
        return 'WebM (VP9)';
      case VideoExportFormat.gif:
        return 'Animated GIF';
    }
  }

  String get mimeType {
    switch (this) {
      case VideoExportFormat.mp4:
        return 'video/mp4';
      case VideoExportFormat.webm:
        return 'video/webm';
      case VideoExportFormat.gif:
        return 'image/gif';
    }
  }
}

/// Video export quality preset
enum VideoExportQuality {
  /// 720p, 30fps, low bitrate
  low,

  /// 1080p, 30fps, medium bitrate
  medium,

  /// 1080p, 60fps, high bitrate
  high,

  /// 4K, 60fps, maximum bitrate
  maximum,
}

extension VideoExportQualityExtension on VideoExportQuality {
  String get displayName {
    switch (this) {
      case VideoExportQuality.low:
        return 'Low (720p)';
      case VideoExportQuality.medium:
        return 'Medium (1080p)';
      case VideoExportQuality.high:
        return 'High (1080p 60fps)';
      case VideoExportQuality.maximum:
        return 'Maximum (4K)';
    }
  }

  int get width {
    switch (this) {
      case VideoExportQuality.low:
        return 1280;
      case VideoExportQuality.medium:
      case VideoExportQuality.high:
        return 1920;
      case VideoExportQuality.maximum:
        return 3840;
    }
  }

  int get height {
    switch (this) {
      case VideoExportQuality.low:
        return 720;
      case VideoExportQuality.medium:
      case VideoExportQuality.high:
        return 1080;
      case VideoExportQuality.maximum:
        return 2160;
    }
  }

  int get frameRate {
    switch (this) {
      case VideoExportQuality.low:
      case VideoExportQuality.medium:
        return 30;
      case VideoExportQuality.high:
      case VideoExportQuality.maximum:
        return 60;
    }
  }

  /// Bitrate in kbps
  int get bitrate {
    switch (this) {
      case VideoExportQuality.low:
        return 2500;
      case VideoExportQuality.medium:
        return 5000;
      case VideoExportQuality.high:
        return 10000;
      case VideoExportQuality.maximum:
        return 25000;
    }
  }
}

/// Recording state
enum RecordingState {
  /// Not recording
  idle,

  /// Recording in progress
  recording,

  /// Encoding frames to video
  encoding,

  /// Paused
  paused,
}

// ═══════════════════════════════════════════════════════════════════════════
// VIDEO EXPORT CONFIG
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration for video export
class VideoExportConfig {
  final VideoExportFormat format;
  final VideoExportQuality quality;
  final String? outputDirectory;
  final String? fileNamePrefix;
  final bool includeTimestamp;
  final bool includeAudio;
  final int maxDurationSeconds;

  const VideoExportConfig({
    this.format = VideoExportFormat.mp4,
    this.quality = VideoExportQuality.high,
    this.outputDirectory,
    this.fileNamePrefix = 'slotlab_recording',
    this.includeTimestamp = true,
    this.includeAudio = true,
    this.maxDurationSeconds = 300, // 5 minutes max
  });

  VideoExportConfig copyWith({
    VideoExportFormat? format,
    VideoExportQuality? quality,
    String? outputDirectory,
    String? fileNamePrefix,
    bool? includeTimestamp,
    bool? includeAudio,
    int? maxDurationSeconds,
  }) {
    return VideoExportConfig(
      format: format ?? this.format,
      quality: quality ?? this.quality,
      outputDirectory: outputDirectory ?? this.outputDirectory,
      fileNamePrefix: fileNamePrefix ?? this.fileNamePrefix,
      includeTimestamp: includeTimestamp ?? this.includeTimestamp,
      includeAudio: includeAudio ?? this.includeAudio,
      maxDurationSeconds: maxDurationSeconds ?? this.maxDurationSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'format': format.name,
        'quality': quality.name,
        'outputDirectory': outputDirectory,
        'fileNamePrefix': fileNamePrefix,
        'includeTimestamp': includeTimestamp,
        'includeAudio': includeAudio,
        'maxDurationSeconds': maxDurationSeconds,
      };

  factory VideoExportConfig.fromJson(Map<String, dynamic> json) {
    return VideoExportConfig(
      format: VideoExportFormat.values.firstWhere(
        (f) => f.name == json['format'],
        orElse: () => VideoExportFormat.mp4,
      ),
      quality: VideoExportQuality.values.firstWhere(
        (q) => q.name == json['quality'],
        orElse: () => VideoExportQuality.high,
      ),
      outputDirectory: json['outputDirectory'] as String?,
      fileNamePrefix: json['fileNamePrefix'] as String? ?? 'slotlab_recording',
      includeTimestamp: json['includeTimestamp'] as bool? ?? true,
      includeAudio: json['includeAudio'] as bool? ?? true,
      maxDurationSeconds: json['maxDurationSeconds'] as int? ?? 300,
    );
  }

  /// Default configuration
  static const defaultConfig = VideoExportConfig();

  /// High quality MP4
  static const highQualityMp4 = VideoExportConfig(
    format: VideoExportFormat.mp4,
    quality: VideoExportQuality.high,
  );

  /// Web-optimized WebM
  static const webOptimized = VideoExportConfig(
    format: VideoExportFormat.webm,
    quality: VideoExportQuality.medium,
  );

  /// Quick GIF for sharing
  static const quickGif = VideoExportConfig(
    format: VideoExportFormat.gif,
    quality: VideoExportQuality.low,
    maxDurationSeconds: 30,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// VIDEO EXPORT RESULT
// ═══════════════════════════════════════════════════════════════════════════

/// Result of a video export operation
class VideoExportResult {
  final bool success;
  final String? filePath;
  final String? error;
  final int frameCount;
  final Duration duration;
  final int fileSizeBytes;
  final DateTime exportedAt;
  final VideoExportConfig config;

  const VideoExportResult({
    required this.success,
    this.filePath,
    this.error,
    this.frameCount = 0,
    this.duration = Duration.zero,
    this.fileSizeBytes = 0,
    required this.exportedAt,
    required this.config,
  });

  factory VideoExportResult.success({
    required String filePath,
    required int frameCount,
    required Duration duration,
    required int fileSizeBytes,
    required VideoExportConfig config,
  }) {
    return VideoExportResult(
      success: true,
      filePath: filePath,
      frameCount: frameCount,
      duration: duration,
      fileSizeBytes: fileSizeBytes,
      exportedAt: DateTime.now(),
      config: config,
    );
  }

  factory VideoExportResult.failure({
    required String error,
    required VideoExportConfig config,
  }) {
    return VideoExportResult(
      success: false,
      error: error,
      exportedAt: DateTime.now(),
      config: config,
    );
  }

  String get fileSizeFormatted {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get durationFormatted {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'filePath': filePath,
        'error': error,
        'frameCount': frameCount,
        'durationMs': duration.inMilliseconds,
        'fileSizeBytes': fileSizeBytes,
        'exportedAt': exportedAt.toIso8601String(),
        'config': config.toJson(),
      };

  factory VideoExportResult.fromJson(Map<String, dynamic> json) {
    return VideoExportResult(
      success: json['success'] as bool,
      filePath: json['filePath'] as String?,
      error: json['error'] as String?,
      frameCount: json['frameCount'] as int? ?? 0,
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
      exportedAt: DateTime.parse(json['exportedAt'] as String),
      config: VideoExportConfig.fromJson(
        json['config'] as Map<String, dynamic>,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CAPTURED FRAME
// ═══════════════════════════════════════════════════════════════════════════

/// A single captured frame
class CapturedFrame {
  final Uint8List imageData;
  final int width;
  final int height;
  final int frameNumber;
  final DateTime capturedAt;

  const CapturedFrame({
    required this.imageData,
    required this.width,
    required this.height,
    required this.frameNumber,
    required this.capturedAt,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// VIDEO EXPORT SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Progress callback type
typedef VideoExportProgressCallback = void Function(
  double progress,
  String status,
);

/// Service for video export operations
class VideoExportService extends ChangeNotifier {
  VideoExportService._();
  static final instance = VideoExportService._();

  // State
  RecordingState _state = RecordingState.idle;
  VideoExportConfig _config = VideoExportConfig.defaultConfig;
  final List<CapturedFrame> _frames = [];
  final List<VideoExportResult> _history = [];
  DateTime? _recordingStartTime;
  Timer? _frameTimer;
  Timer? _maxDurationTimer;
  RenderRepaintBoundary? _boundary;
  bool _initialized = false;

  static const int _maxHistorySize = 50;
  static const String _prefsKeyConfig = 'video_export_config';
  static const String _prefsKeyHistory = 'video_export_history';

  // Getters
  RecordingState get state => _state;
  VideoExportConfig get config => _config;
  bool get isRecording => _state == RecordingState.recording;
  bool get isEncoding => _state == RecordingState.encoding;
  bool get isPaused => _state == RecordingState.paused;
  bool get isIdle => _state == RecordingState.idle;
  int get frameCount => _frames.length;
  Duration get recordingDuration => _recordingStartTime != null
      ? DateTime.now().difference(_recordingStartTime!)
      : Duration.zero;
  List<VideoExportResult> get history => List.unmodifiable(_history);
  bool get initialized => _initialized;

  /// Initialize the service
  Future<void> init() async {
    if (_initialized) return;

    await _loadConfig();
    await _loadHistory();

    _initialized = true;
    debugPrint('[VideoExportService] Initialized');
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_prefsKeyConfig);
      if (configJson != null) {
        final json = Map<String, dynamic>.from(
          (await compute(_parseJson, configJson)) as Map,
        );
        _config = VideoExportConfig.fromJson(json);
      }
    } catch (e) {
      debugPrint('[VideoExportService] Error loading config: $e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getStringList(_prefsKeyHistory);
      if (historyJson != null) {
        _history.clear();
        for (final json in historyJson) {
          try {
            final map = Map<String, dynamic>.from(
              (await compute(_parseJson, json)) as Map,
            );
            _history.add(VideoExportResult.fromJson(map));
          } catch (e) {
            debugPrint('[VideoExportService] Error parsing history item: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[VideoExportService] Error loading history: $e');
    }
  }

  static dynamic _parseJson(String jsonStr) {
    return (jsonStr.isNotEmpty)
        ? (Map<String, dynamic>.from(jsonDecode(jsonStr) as Map))
        : <String, dynamic>{};
  }

  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_config.toJson());
      await prefs.setString(_prefsKeyConfig, jsonStr);
    } catch (e) {
      debugPrint('[VideoExportService] Error saving config: $e');
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = _history
          .map((r) => jsonEncode(r.toJson()))
          .toList();
      await prefs.setStringList(_prefsKeyHistory, historyJson);
    } catch (e) {
      debugPrint('[VideoExportService] Error saving history: $e');
    }
  }

  /// Update configuration
  void setConfig(VideoExportConfig config) {
    _config = config;
    _saveConfig();
    notifyListeners();
  }

  /// Set the render boundary to capture
  void setBoundary(RenderRepaintBoundary? boundary) {
    _boundary = boundary;
  }

  /// Start recording
  Future<bool> startRecording({
    RenderRepaintBoundary? boundary,
    VideoExportConfig? config,
  }) async {
    if (_state != RecordingState.idle) {
      debugPrint('[VideoExportService] Cannot start: already recording');
      return false;
    }

    if (boundary != null) {
      _boundary = boundary;
    }

    if (_boundary == null) {
      debugPrint('[VideoExportService] Cannot start: no boundary set');
      return false;
    }

    if (config != null) {
      _config = config;
    }

    _frames.clear();
    _recordingStartTime = DateTime.now();
    _state = RecordingState.recording;

    // Start frame capture timer
    final frameInterval = Duration(
      milliseconds: (1000 / _config.quality.frameRate).round(),
    );
    _frameTimer = Timer.periodic(frameInterval, (_) => _captureFrame());

    // Start max duration timer
    _maxDurationTimer = Timer(
      Duration(seconds: _config.maxDurationSeconds),
      () => stopRecording(),
    );

    notifyListeners();
    debugPrint('[VideoExportService] Recording started');
    return true;
  }

  /// Pause recording
  void pauseRecording() {
    if (_state != RecordingState.recording) return;

    _frameTimer?.cancel();
    _state = RecordingState.paused;
    notifyListeners();
    debugPrint('[VideoExportService] Recording paused');
  }

  /// Resume recording
  void resumeRecording() {
    if (_state != RecordingState.paused) return;

    final frameInterval = Duration(
      milliseconds: (1000 / _config.quality.frameRate).round(),
    );
    _frameTimer = Timer.periodic(frameInterval, (_) => _captureFrame());
    _state = RecordingState.recording;
    notifyListeners();
    debugPrint('[VideoExportService] Recording resumed');
  }

  /// Stop recording and encode video
  Future<VideoExportResult> stopRecording({
    VideoExportProgressCallback? onProgress,
  }) async {
    if (_state != RecordingState.recording && _state != RecordingState.paused) {
      return VideoExportResult.failure(
        error: 'Not recording',
        config: _config,
      );
    }

    _frameTimer?.cancel();
    _maxDurationTimer?.cancel();
    _state = RecordingState.encoding;
    notifyListeners();

    onProgress?.call(0.0, 'Preparing frames...');

    try {
      final result = await _encodeVideo(onProgress: onProgress);
      _addToHistory(result);
      return result;
    } catch (e) {
      final result = VideoExportResult.failure(
        error: e.toString(),
        config: _config,
      );
      _addToHistory(result);
      return result;
    } finally {
      _state = RecordingState.idle;
      _frames.clear();
      _recordingStartTime = null;
      notifyListeners();
    }
  }

  /// Cancel recording without saving
  void cancelRecording() {
    _frameTimer?.cancel();
    _maxDurationTimer?.cancel();
    _state = RecordingState.idle;
    _frames.clear();
    _recordingStartTime = null;
    notifyListeners();
    debugPrint('[VideoExportService] Recording cancelled');
  }

  Future<void> _captureFrame() async {
    if (_boundary == null || _state != RecordingState.recording) return;

    try {
      final image = await _boundary!.toImage(
        pixelRatio: _getPixelRatioForQuality(),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        _frames.add(CapturedFrame(
          imageData: byteData.buffer.asUint8List(),
          width: image.width,
          height: image.height,
          frameNumber: _frames.length,
          capturedAt: DateTime.now(),
        ));
      }
      image.dispose();
    } catch (e) {
      debugPrint('[VideoExportService] Error capturing frame: $e');
    }
  }

  double _getPixelRatioForQuality() {
    switch (_config.quality) {
      case VideoExportQuality.low:
        return 1.0;
      case VideoExportQuality.medium:
        return 1.5;
      case VideoExportQuality.high:
        return 2.0;
      case VideoExportQuality.maximum:
        return 3.0;
    }
  }

  Future<VideoExportResult> _encodeVideo({
    VideoExportProgressCallback? onProgress,
  }) async {
    if (_frames.isEmpty) {
      return VideoExportResult.failure(
        error: 'No frames captured',
        config: _config,
      );
    }

    onProgress?.call(0.1, 'Getting output directory...');

    final outputDir = await _getOutputDirectory();
    final fileName = _generateFileName();
    final outputPath = '$outputDir/$fileName';

    onProgress?.call(0.2, 'Writing frames...');

    // Write frames to temp directory
    final tempDir = Directory.systemTemp;
    final framesDir = Directory('${tempDir.path}/video_frames_${DateTime.now().millisecondsSinceEpoch}');
    await framesDir.create(recursive: true);

    for (int i = 0; i < _frames.length; i++) {
      final frame = _frames[i];
      final framePath = '${framesDir.path}/frame_${i.toString().padLeft(6, '0')}.png';
      await File(framePath).writeAsBytes(frame.imageData);

      if (i % 10 == 0) {
        final progress = 0.2 + (0.5 * i / _frames.length);
        onProgress?.call(progress, 'Writing frame ${i + 1}/${_frames.length}...');
      }
    }

    onProgress?.call(0.7, 'Encoding video...');

    // Use FFmpeg for encoding (requires ffmpeg in PATH)
    final ffmpegResult = await _runFFmpeg(
      framesDir: framesDir.path,
      outputPath: outputPath,
      onProgress: onProgress,
    );

    // Cleanup temp frames
    try {
      await framesDir.delete(recursive: true);
    } catch (e) {
      debugPrint('[VideoExportService] Error cleaning up temp frames: $e');
    }

    if (!ffmpegResult.success) {
      return VideoExportResult.failure(
        error: ffmpegResult.error ?? 'Encoding failed',
        config: _config,
      );
    }

    onProgress?.call(1.0, 'Complete!');

    final outputFile = File(outputPath);
    final fileSize = await outputFile.length();
    final duration = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!)
        : Duration(seconds: (_frames.length / _config.quality.frameRate).round());

    return VideoExportResult.success(
      filePath: outputPath,
      frameCount: _frames.length,
      duration: duration,
      fileSizeBytes: fileSize,
      config: _config,
    );
  }

  Future<({bool success, String? error})> _runFFmpeg({
    required String framesDir,
    required String outputPath,
    VideoExportProgressCallback? onProgress,
  }) async {
    try {
      final List<String> args;

      switch (_config.format) {
        case VideoExportFormat.mp4:
          args = [
            '-y',
            '-framerate', '${_config.quality.frameRate}',
            '-i', '$framesDir/frame_%06d.png',
            '-c:v', 'libx264',
            '-preset', 'medium',
            '-crf', '23',
            '-pix_fmt', 'yuv420p',
            '-b:v', '${_config.quality.bitrate}k',
            outputPath,
          ];
          break;

        case VideoExportFormat.webm:
          args = [
            '-y',
            '-framerate', '${_config.quality.frameRate}',
            '-i', '$framesDir/frame_%06d.png',
            '-c:v', 'libvpx-vp9',
            '-crf', '30',
            '-b:v', '${_config.quality.bitrate}k',
            outputPath,
          ];
          break;

        case VideoExportFormat.gif:
          // Generate palette first for better GIF quality
          final palettePath = '$framesDir/palette.png';
          await Process.run('ffmpeg', [
            '-y',
            '-framerate', '${_config.quality.frameRate}',
            '-i', '$framesDir/frame_%06d.png',
            '-vf', 'palettegen',
            palettePath,
          ]);

          args = [
            '-y',
            '-framerate', '${_config.quality.frameRate}',
            '-i', '$framesDir/frame_%06d.png',
            '-i', palettePath,
            '-filter_complex', 'paletteuse',
            outputPath,
          ];
          break;
      }

      onProgress?.call(0.8, 'Running FFmpeg...');

      final result = await Process.run('ffmpeg', args);

      if (result.exitCode != 0) {
        debugPrint('[VideoExportService] FFmpeg error: ${result.stderr}');
        return (success: false, error: 'FFmpeg failed: ${result.stderr}');
      }

      return (success: true, error: null);
    } catch (e) {
      debugPrint('[VideoExportService] FFmpeg exception: $e');
      return (success: false, error: 'FFmpeg not available: $e');
    }
  }

  Future<String> _getOutputDirectory() async {
    if (_config.outputDirectory != null) {
      final dir = Directory(_config.outputDirectory!);
      if (await dir.exists()) {
        return _config.outputDirectory!;
      }
    }

    // Platform-specific default directories
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      final dir = Directory('$home/Movies/FluxForge');
      await dir.create(recursive: true);
      return dir.path;
    } else if (Platform.isWindows) {
      final videos = Platform.environment['USERPROFILE'];
      final dir = Directory('$videos/Videos/FluxForge');
      await dir.create(recursive: true);
      return dir.path;
    } else {
      final home = Platform.environment['HOME'];
      final dir = Directory('$home/Videos/FluxForge');
      await dir.create(recursive: true);
      return dir.path;
    }
  }

  String _generateFileName() {
    final prefix = _config.fileNamePrefix ?? 'slotlab_recording';
    final extension = _config.format.extension;

    if (_config.includeTimestamp) {
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-')
          .substring(0, 19);
      return '${prefix}_$timestamp.$extension';
    }

    return '$prefix.$extension';
  }

  void _addToHistory(VideoExportResult result) {
    _history.insert(0, result);
    if (_history.length > _maxHistorySize) {
      _history.removeLast();
    }
    _saveHistory();
  }

  /// Clear export history
  void clearHistory() {
    _history.clear();
    _saveHistory();
    notifyListeners();
  }

  /// Remove a specific history item
  void removeFromHistory(int index) {
    if (index >= 0 && index < _history.length) {
      _history.removeAt(index);
      _saveHistory();
      notifyListeners();
    }
  }

  /// Get successful exports only
  List<VideoExportResult> get successfulExports =>
      _history.where((r) => r.success).toList();

  /// Get failed exports only
  List<VideoExportResult> get failedExports =>
      _history.where((r) => !r.success).toList();

  /// Open export in system file manager
  Future<void> openInFileManager(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final dir = file.parent.path;
        if (Platform.isMacOS) {
          await Process.run('open', [dir]);
        } else if (Platform.isWindows) {
          await Process.run('explorer', [dir]);
        } else {
          await Process.run('xdg-open', [dir]);
        }
      }
    } catch (e) {
      debugPrint('[VideoExportService] Error opening file manager: $e');
    }
  }

  /// Check if FFmpeg is available
  Future<bool> isFFmpegAvailable() async {
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// Get FFmpeg version
  Future<String?> getFFmpegVersion() async {
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final firstLine = output.split('\n').first;
        return firstLine;
      }
    } catch (e) {
      debugPrint('[VideoExportService] Error getting FFmpeg version: $e');
    }
    return null;
  }
}
