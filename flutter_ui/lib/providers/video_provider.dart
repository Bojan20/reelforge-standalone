// Video Provider
//
// State management for video timeline:
// - Video clip management (load, remove, sync)
// - Thumbnail caching and loading
// - Timecode format selection
// - Frame-accurate seek
// - Video preview playback
// - A/V sync offset adjustment
//
// Integration with rf-video via FFI

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../widgets/timeline/video_track.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class VideoProvider extends ChangeNotifier {
  // Video clip (single video per project for now)
  VideoClip? _videoClip;

  // Settings
  TimecodeFormat _timecodeFormat = TimecodeFormat.smpte24;
  double _syncOffset = 0.0;
  bool _isExpanded = true;
  double _trackHeight = 100.0;

  // Playback state
  bool _isPlaying = false;
  double _currentTime = 0.0;

  // Preview state
  bool _showPreview = false;
  Uint8List? _currentFrame;

  // Loading state
  bool _isLoading = false;
  double _loadProgress = 0.0;
  String? _loadError;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  VideoClip? get videoClip => _videoClip;
  bool get hasVideo => _videoClip != null;
  TimecodeFormat get timecodeFormat => _timecodeFormat;
  double get syncOffset => _syncOffset;
  bool get isExpanded => _isExpanded;
  double get trackHeight => _trackHeight;
  bool get isPlaying => _isPlaying;
  double get currentTime => _currentTime;
  bool get showPreview => _showPreview;
  Uint8List? get currentFrame => _currentFrame;
  bool get isLoading => _isLoading;
  double get loadProgress => _loadProgress;
  String? get loadError => _loadError;

  /// Get video duration
  double get duration => _videoClip?.duration ?? 0.0;

  /// Get frame rate
  int get frameRate => _videoClip?.frameRate ?? 24;

  /// Get resolution as string
  String get resolution {
    if (_videoClip == null) return '';
    return '${_videoClip!.width} x ${_videoClip!.height}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VIDEO MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load video from path
  Future<void> loadVideo(String path) async {
    _isLoading = true;
    _loadProgress = 0.0;
    _loadError = null;
    notifyListeners();

    try {
      final ffi = NativeFFI.instance;
      if (!ffi.isLoaded) {
        throw Exception('Native library not loaded');
      }

      // Add video track if needed
      int trackId = ffi.videoGetTrackCount();
      if (trackId == 0) {
        trackId = ffi.videoAddTrack('Video');
      }
      _loadProgress = 0.2;
      notifyListeners();

      // Import video file
      final clipId = ffi.videoImport(trackId, path, 0);
      if (clipId == 0) {
        throw Exception('Failed to import video: $path');
      }
      _loadProgress = 0.5;
      notifyListeners();

      // Get video info from engine
      final infoJson = ffi.videoGetInfoJson(clipId);
      if (infoJson != null) {
        final info = jsonDecode(infoJson);
        _videoClip = VideoClip(
          id: 'video-$clipId',
          path: path,
          name: path.split('/').last,
          startTime: 0,
          duration: (info['duration_frames'] as int) / (info['frame_rate'] as num).toDouble(),
          sourceDuration: (info['duration_frames'] as int) / (info['frame_rate'] as num).toDouble(),
          frameRate: (info['frame_rate'] as num).toInt(),
          width: info['width'] as int,
          height: info['height'] as int,
          thumbnailInterval: 1.0,
        );
      } else {
        // Fallback if no info available
        _videoClip = VideoClip(
          id: 'video-$clipId',
          path: path,
          name: path.split('/').last,
          startTime: 0,
          duration: 60,
          sourceDuration: 60,
          frameRate: 24,
          width: 1920,
          height: 1080,
          thumbnailInterval: 1.0,
        );
      }
      _loadProgress = 0.8;
      notifyListeners();

      _isLoading = false;
      notifyListeners();

      // Generate thumbnails in background
      _generateThumbnails();
    } catch (e) {
      _isLoading = false;
      _loadError = e.toString();
      notifyListeners();
    }
  }

  /// Generate thumbnails for video clip
  Future<void> _generateThumbnails() async {
    if (_videoClip == null) return;

    try {
      final ffi = NativeFFI.instance;
      if (!ffi.isLoaded) return;

      // Parse clip ID from video clip id
      final clipIdStr = _videoClip!.id.replaceFirst('video-', '');
      final clipId = int.tryParse(clipIdStr) ?? 0;
      if (clipId == 0) return;

      // Generate thumbnails (160px wide, 1 frame per second)
      final count = ffi.videoGenerateThumbnails(
        clipId,
        160,
        _videoClip!.frameRate, // One thumbnail per second
      );

      debugPrint('Generated $count thumbnails for video clip $clipId');
    } catch (e) {
      debugPrint('Failed to generate thumbnails: $e');
    }
  }

  /// Remove video
  void removeVideo() {
    // Clear engine state
    try {
      final ffi = NativeFFI.instance;
      if (ffi.isLoaded) {
        ffi.videoClearAll();
      }
    } catch (e) {
      debugPrint('Failed to clear video engine: $e');
    }

    _videoClip = null;
    _currentFrame = null;
    notifyListeners();
  }

  /// Update video clip position
  void setVideoStartTime(double startTime) {
    if (_videoClip == null) return;
    _videoClip = _videoClip!.copyWith(startTime: startTime);
    notifyListeners();
  }

  /// Trim video (adjust source offset and duration)
  void trimVideo({
    double? sourceOffset,
    double? duration,
  }) {
    if (_videoClip == null) return;
    _videoClip = _videoClip!.copyWith(
      sourceOffset: sourceOffset ?? _videoClip!.sourceOffset,
      duration: duration ?? _videoClip!.duration,
    );
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC SETTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set A/V sync offset (positive = video ahead)
  void setSyncOffset(double offset) {
    _syncOffset = offset.clamp(-10.0, 10.0);
    notifyListeners();
  }

  /// Nudge sync offset
  void nudgeSyncOffset(double delta) {
    setSyncOffset(_syncOffset + delta);
  }

  /// Reset sync offset to zero
  void resetSyncOffset() {
    _syncOffset = 0.0;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMECODE FORMAT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set timecode display format
  void setTimecodeFormat(TimecodeFormat format) {
    _timecodeFormat = format;
    notifyListeners();
  }

  /// Cycle through timecode formats
  void cycleTimecodeFormat() {
    final formats = TimecodeFormat.values;
    final currentIndex = formats.indexOf(_timecodeFormat);
    _timecodeFormat = formats[(currentIndex + 1) % formats.length];
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK DISPLAY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Toggle track expanded/collapsed
  void toggleExpanded() {
    _isExpanded = !_isExpanded;
    notifyListeners();
  }

  /// Set track expanded state
  void setExpanded(bool expanded) {
    _isExpanded = expanded;
    notifyListeners();
  }

  /// Set track height
  void setTrackHeight(double height) {
    _trackHeight = height.clamp(60.0, 200.0);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYBACK CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set current playback time (synced from main transport)
  void setCurrentTime(double time) {
    _currentTime = time.clamp(0.0, duration);

    // Sync playhead to engine
    try {
      final ffi = NativeFFI.instance;
      if (ffi.isLoaded) {
        // Convert time to samples (assuming 48kHz sample rate)
        const sampleRate = 48000;
        final samples = ((_currentTime + _syncOffset) * sampleRate).toInt();
        ffi.videoSetPlayhead(samples);
      }
    } catch (e) {
      debugPrint('Failed to sync video playhead: $e');
    }

    notifyListeners();

    // Update preview frame if preview is shown
    if (_showPreview) {
      _updatePreviewFrame();
    }
  }

  /// Seek to specific frame
  void seekToFrame(int frame) {
    if (_videoClip == null) return;
    final time = frame / _videoClip!.frameRate;
    setCurrentTime(time);
  }

  /// Seek to timecode
  void seekToTimecode(String timecode) {
    // Parse timecode based on current format and seek
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return;

    double frameRate;
    switch (_timecodeFormat) {
      case TimecodeFormat.smpte24:
        frameRate = 24.0;
        break;
      case TimecodeFormat.smpte25:
        frameRate = 25.0;
        break;
      case TimecodeFormat.smpte2997df:
        frameRate = 29.97;
        break;
      case TimecodeFormat.smpte30:
        frameRate = 30.0;
        break;
      default:
        return; // Can't parse frames or seconds formats
    }

    final seconds = ffi.videoParseTimecode(timecode, frameRate);
    if (seconds >= 0) {
      setCurrentTime(seconds);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VIDEO PREVIEW
  // ═══════════════════════════════════════════════════════════════════════════

  /// Toggle video preview window
  void togglePreview() {
    _showPreview = !_showPreview;
    if (_showPreview) {
      _updatePreviewFrame();
    }
    notifyListeners();
  }

  /// Show/hide preview
  void setShowPreview(bool show) {
    _showPreview = show;
    if (show) {
      _updatePreviewFrame();
    }
    notifyListeners();
  }

  /// Update preview frame at current time
  Future<void> _updatePreviewFrame() async {
    if (_videoClip == null) return;

    try {
      final ffi = NativeFFI.instance;
      if (!ffi.isLoaded) return;

      // Parse clip ID
      final clipIdStr = _videoClip!.id.replaceFirst('video-', '');
      final clipId = int.tryParse(clipIdStr) ?? 0;
      if (clipId == 0) return;

      // Convert time to samples (assuming 48kHz sample rate)
      const sampleRate = 48000;
      final timeSamples = ((_currentTime + _syncOffset) * sampleRate).toInt();

      // Get frame data from engine
      final result = ffi.videoGetFrame(clipId, timeSamples);
      if (result.data != null) {
        _currentFrame = result.data;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to update preview frame: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FRAME UTILITIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Convert time to frame number
  int timeToFrame(double time) {
    return (time * frameRate).floor();
  }

  /// Convert frame to time
  double frameToTime(int frame) {
    return frame / frameRate;
  }

  /// Get frame number at current time
  int get currentFrameNumber => timeToFrame(_currentTime);

  /// Get total frames
  int get totalFrames => timeToFrame(duration);

  /// Format time as SMPTE timecode
  String formatTimecode(double time) {
    if (time < 0) time = 0;

    // Use FFI for SMPTE formats when available
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      switch (_timecodeFormat) {
        case TimecodeFormat.smpte24:
          return ffi.videoFormatTimecode(time, 24.0, dropFrame: false);
        case TimecodeFormat.smpte25:
          return ffi.videoFormatTimecode(time, 25.0, dropFrame: false);
        case TimecodeFormat.smpte2997df:
          return ffi.videoFormatTimecode(time, 29.97, dropFrame: true);
        case TimecodeFormat.smpte30:
          return ffi.videoFormatTimecode(time, 30.0, dropFrame: false);
        case TimecodeFormat.frames:
          return '${timeToFrame(time)} frames';
        case TimecodeFormat.seconds:
          return time.toStringAsFixed(3);
      }
    }

    // Fallback to local implementation if FFI not available
    switch (_timecodeFormat) {
      case TimecodeFormat.smpte24:
        return _formatSmpte(time, 24);
      case TimecodeFormat.smpte25:
        return _formatSmpte(time, 25);
      case TimecodeFormat.smpte2997df:
        return _formatSmpteDf(time);
      case TimecodeFormat.smpte30:
        return _formatSmpte(time, 30);
      case TimecodeFormat.frames:
        return '${timeToFrame(time)} frames';
      case TimecodeFormat.seconds:
        return time.toStringAsFixed(3);
    }
  }

  String _formatSmpte(double seconds, int fps) {
    final totalFrames = (seconds * fps).floor();
    final h = totalFrames ~/ (fps * 3600);
    final m = (totalFrames ~/ (fps * 60)) % 60;
    final s = (totalFrames ~/ fps) % 60;
    final f = totalFrames % fps;

    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}:${f.toString().padLeft(2, '0')}';
  }

  String _formatSmpteDf(double seconds) {
    // Drop-frame timecode for 29.97fps
    const fps = 30;
    const dropFrames = 2;
    const framesPerMinute = fps * 60 - dropFrames;
    const framesPerTenMinutes = framesPerMinute * 10 + dropFrames;

    var totalFrames = (seconds * 29.97).round();

    final tenMinuteChunks = totalFrames ~/ framesPerTenMinutes;
    var remaining = totalFrames % framesPerTenMinutes;

    if (remaining < dropFrames) {
      remaining = dropFrames;
    }

    final minuteChunks = (remaining - dropFrames) ~/ framesPerMinute;
    remaining = (remaining - dropFrames) % framesPerMinute + dropFrames;

    final h = tenMinuteChunks ~/ 6;
    final m = (tenMinuteChunks % 6) * 10 + minuteChunks;
    final s = remaining ~/ fps;
    final f = remaining % fps;

    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')};${f.toString().padLeft(2, '0')}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() {
    return {
      'videoPath': _videoClip?.path,
      'startTime': _videoClip?.startTime ?? 0,
      'sourceOffset': _videoClip?.sourceOffset ?? 0,
      'duration': _videoClip?.duration ?? 0,
      'syncOffset': _syncOffset,
      'timecodeFormat': _timecodeFormat.index,
      'isExpanded': _isExpanded,
      'trackHeight': _trackHeight,
    };
  }

  Future<void> loadFromJson(Map<String, dynamic> json) async {
    _syncOffset = (json['syncOffset'] ?? 0.0).toDouble();
    _timecodeFormat =
        TimecodeFormat.values[json['timecodeFormat'] ?? 0];
    _isExpanded = json['isExpanded'] ?? true;
    _trackHeight = (json['trackHeight'] ?? 100.0).toDouble();

    final videoPath = json['videoPath'] as String?;
    if (videoPath != null) {
      await loadVideo(videoPath);

      // Restore position and duration
      if (_videoClip != null) {
        _videoClip = _videoClip!.copyWith(
          startTime: (json['startTime'] ?? 0.0).toDouble(),
          sourceOffset: (json['sourceOffset'] ?? 0.0).toDouble(),
          duration: (json['duration'] ?? _videoClip!.duration).toDouble(),
        );
      }
    }

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET
  // ═══════════════════════════════════════════════════════════════════════════

  void reset() {
    _videoClip = null;
    _timecodeFormat = TimecodeFormat.smpte24;
    _syncOffset = 0.0;
    _isExpanded = true;
    _trackHeight = 100.0;
    _isPlaying = false;
    _currentTime = 0.0;
    _showPreview = false;
    _currentFrame = null;
    _isLoading = false;
    _loadProgress = 0.0;
    _loadError = null;
    notifyListeners();
  }

}
