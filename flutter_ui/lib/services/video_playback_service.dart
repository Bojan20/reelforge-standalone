/// Video Playback Service
///
/// Cross-platform video playback via media_kit (libmpv/FFmpeg).
/// Handles: file open, seek, play/pause, frame-accurate positioning,
/// and provides a Widget for embedding in the UI.

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoPlaybackService extends ChangeNotifier {
  Player? _player;
  VideoController? _controller;
  bool _initialized = false;

  // Playback state
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  String? _currentPath;

  // Getters
  bool get initialized => _initialized;
  bool get hasVideo => _currentPath != null;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  String? get currentPath => _currentPath;
  VideoController? get controller => _controller;

  /// Initialize the service (call once at app startup)
  void init() {
    if (_initialized) return;
    MediaKit.ensureInitialized();
    _initialized = true;
  }

  /// Get the video preview widget
  Widget previewWidget({double? width, double? height}) {
    if (_controller == null) {
      return Container(
        width: width,
        height: height,
        color: Colors.black,
        child: const Center(
          child: Text(
            'No video loaded',
            style: TextStyle(color: Color(0xFF555555), fontSize: 11),
          ),
        ),
      );
    }
    return Video(
      controller: _controller!,
      width: width,
      height: height,
      fit: BoxFit.contain,
    );
  }

  /// Open a video file for playback
  Future<void> open(String path) async {
    init();

    // Dispose previous player
    await _disposePlayer();

    _player = Player();
    _controller = VideoController(_player!);

    // Listen to state changes
    _player!.stream.position.listen((pos) {
      _position = pos;
      notifyListeners();
    });
    _player!.stream.duration.listen((dur) {
      _duration = dur;
      notifyListeners();
    });
    _player!.stream.playing.listen((playing) {
      _isPlaying = playing;
      notifyListeners();
    });
    _player!.stream.buffering.listen((buffering) {
      _isBuffering = buffering;
      notifyListeners();
    });

    await _player!.open(Media('file://$path'), play: false);
    _currentPath = path;
    notifyListeners();
  }

  /// Play
  Future<void> play() async {
    await _player?.play();
  }

  /// Pause
  Future<void> pause() async {
    await _player?.pause();
  }

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    await _player?.playOrPause();
  }

  /// Seek to duration
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
  }

  /// Seek to frame (given fps)
  Future<void> seekToFrame(int frame, double fps) async {
    final ms = (frame / fps * 1000).round();
    await _player?.seek(Duration(milliseconds: ms));
  }

  /// Seek to timecode seconds
  Future<void> seekToSeconds(double seconds) async {
    final ms = (seconds * 1000).round();
    await _player?.seek(Duration(milliseconds: ms));
  }

  /// Set playback rate
  Future<void> setRate(double rate) async {
    await _player?.setRate(rate);
  }

  /// Set volume (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    await _player?.setVolume(volume * 100.0);
  }

  /// Stop and close
  Future<void> close() async {
    await _disposePlayer();
    _currentPath = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> _disposePlayer() async {
    await _player?.dispose();
    _player = null;
    _controller = null;
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }
}
