// Timeline Playback Provider
//
// Connects timeline clips to audio playback with:
// - Sample-accurate position sync from Rust audio engine
// - Seamless loop playback (Cubase-style)
// - Crossfade gain curves
// - Track mute/solo/volume/pan
// - Scrubbing with throttling

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../src/rust/engine_api.dart' as api;
import '../services/unified_playback_controller.dart';

// ============ Types ============

enum BusType { master, music, sfx, ambience, voice }

class TimelineClipData {
  final String id;
  final String trackId;
  final String name;
  final double startTime; // In seconds (position on timeline)
  final double duration; // In seconds (visible duration)
  final Float32List? audioData;
  final String? color;
  /// Offset into source audio where playback starts
  final double sourceOffset;
  /// Output bus for this clip's track
  final BusType outputBus;
  /// Track is muted
  final bool trackMuted;
  /// Track is soloed
  final bool trackSoloed;
  /// Track volume (0-1)
  final double trackVolume;
  /// Track pan (-1 to 1)
  final double trackPan;

  const TimelineClipData({
    required this.id,
    required this.trackId,
    required this.name,
    required this.startTime,
    required this.duration,
    this.audioData,
    this.color,
    this.sourceOffset = 0,
    this.outputBus = BusType.master,
    this.trackMuted = false,
    this.trackSoloed = false,
    this.trackVolume = 1,
    this.trackPan = 0,
  });

  double get endTime => startTime + duration;
}

class PlaybackCrossfade {
  final String id;
  final String clipAId;
  final String clipBId;
  final double startTime;
  final double duration;
  final CrossfadeCurveType curveType;

  const PlaybackCrossfade({
    required this.id,
    required this.clipAId,
    required this.clipBId,
    required this.startTime,
    required this.duration,
    this.curveType = CrossfadeCurveType.equalPower,
  });
}

enum CrossfadeCurveType { linear, equalPower, sCurve }

class TimelinePlaybackState {
  final bool isPlaying;
  final bool isPaused;
  final bool isScrubbing;
  final double currentTime;
  final double duration;
  final bool loopEnabled;
  final double loopStart;
  final double loopEnd;
  /// Scrub speed multiplier (-2.0 to 2.0, negative = reverse)
  final double scrubSpeed;

  const TimelinePlaybackState({
    this.isPlaying = false,
    this.isPaused = false,
    this.isScrubbing = false,
    this.currentTime = 0,
    this.duration = 60,
    this.loopEnabled = false,
    this.loopStart = 0,
    this.loopEnd = 60,
    this.scrubSpeed = 0,
  });

  TimelinePlaybackState copyWith({
    bool? isPlaying,
    bool? isPaused,
    bool? isScrubbing,
    double? currentTime,
    double? duration,
    bool? loopEnabled,
    double? loopStart,
    double? loopEnd,
    double? scrubSpeed,
  }) {
    return TimelinePlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      isPaused: isPaused ?? this.isPaused,
      isScrubbing: isScrubbing ?? this.isScrubbing,
      currentTime: currentTime ?? this.currentTime,
      duration: duration ?? this.duration,
      loopEnabled: loopEnabled ?? this.loopEnabled,
      loopStart: loopStart ?? this.loopStart,
      loopEnd: loopEnd ?? this.loopEnd,
      scrubSpeed: scrubSpeed ?? this.scrubSpeed,
    );
  }
}

// ============ Provider ============

class TimelinePlaybackProvider extends ChangeNotifier {
  TimelinePlaybackState _state = const TimelinePlaybackState();
  List<TimelineClipData> _clips = [];
  // ignore: unused_field
  List<PlaybackCrossfade> _crossfades = [];

  Ticker? _ticker;

  // Scrubbing throttling - limit seek calls to 50ms intervals for performance
  DateTime _lastScrubTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _scrubThrottleDuration = Duration(milliseconds: 50);

  // Scrub velocity tracking
  double _scrubStartTime = 0;
  double _scrubStartPosition = 0;

  // UI notify throttling - 8ms = 120fps for ultra-smooth playhead movement
  DateTime _lastNotifyTime = DateTime.now();
  static const Duration _notifyThrottleDuration = Duration(milliseconds: 8);

  // Callbacks
  void Function(double time)? onTimeUpdate;
  void Function()? onPlaybackEnd;

  TimelinePlaybackState get state => _state;
  bool get isPlaying => _state.isPlaying;
  bool get isPaused => _state.isPaused;
  bool get isScrubbing => _state.isScrubbing;
  double get currentTime => _state.currentTime;
  double get duration => _state.duration;
  bool get loopEnabled => _state.loopEnabled;
  double get loopStart => _state.loopStart;
  double get loopEnd => _state.loopEnd;
  double get scrubSpeed => _state.scrubSpeed;

  void setClips(List<TimelineClipData> clips) {
    _clips = clips;
    _updateDuration();
  }

  void setCrossfades(List<PlaybackCrossfade> crossfades) {
    _crossfades = crossfades;
  }

  void _updateDuration() {
    if (_clips.isEmpty) return;

    final maxEnd = _clips.fold<double>(
      0,
      (max, clip) => clip.endTime > max ? clip.endTime : max,
    );

    if (maxEnd != _state.duration) {
      _state = _state.copyWith(duration: maxEnd);
      notifyListeners();
    }
  }

  Future<void> play() async {
    if (_state.isPlaying) return;

    // Acquire DAW section in UnifiedPlaybackController
    final controller = UnifiedPlaybackController.instance;
    if (!controller.acquireSection(PlaybackSection.daw)) {
      return;
    }

    // Start audio playback via UnifiedPlaybackController (delegates to Rust)
    controller.play();

    // Start vsync ticker (60 FPS) for smooth UI updates
    _ticker?.dispose();
    _ticker = Ticker(_onTick)..start();

    _state = _state.copyWith(isPlaying: true, isPaused: false);
    notifyListeners();

    // Initial update
    _updatePlayback();
  }

  void pause() {
    // Pause audio via UnifiedPlaybackController
    UnifiedPlaybackController.instance.pause();

    _ticker?.stop();

    _state = _state.copyWith(isPlaying: false, isPaused: true);
    notifyListeners();
  }

  void stop() {
    // Stop audio via UnifiedPlaybackController and release section
    UnifiedPlaybackController.instance.stop(releaseAfterStop: true);

    _ticker?.dispose();
    _ticker = null;

    _state = _state.copyWith(
      isPlaying: false,
      isPaused: false,
      currentTime: 0,
    );
    notifyListeners();
  }

  void seek(double time, {bool isScrubbing = false}) {
    final clampedTime = time.clamp(0.0, _state.duration);

    if (isScrubbing) {
      // Throttle scrub seeks to prevent overwhelming the audio engine
      final now = DateTime.now();
      if (now.difference(_lastScrubTime) < _scrubThrottleDuration) {
        // Update UI immediately but don't send seek command
        _state = _state.copyWith(currentTime: clampedTime);
        notifyListeners();
        return;
      }
      _lastScrubTime = now;
    }

    // Send seek command via UnifiedPlaybackController
    UnifiedPlaybackController.instance.seek(clampedTime);

    _state = _state.copyWith(currentTime: clampedTime);
    notifyListeners();
  }

  /// Start scrubbing - call when drag begins
  void startScrubbing(double startTime) {
    _scrubStartTime = startTime.clamp(0.0, _state.duration);
    _scrubStartPosition = _scrubStartTime;
    _state = _state.copyWith(
      isScrubbing: true,
      scrubSpeed: 0,
    );

    // Start audio scrubbing via UnifiedPlaybackController
    UnifiedPlaybackController.instance.startScrub(_scrubStartTime);

    notifyListeners();
  }

  /// Update scrub position with velocity tracking
  /// [deltaPixels] - horizontal drag delta in pixels
  /// [pixelsPerSecond] - timeline zoom scale
  void updateScrub(double deltaPixels, double pixelsPerSecond) {
    if (!_state.isScrubbing) return;

    // Convert pixel delta to time delta
    final timeDelta = deltaPixels / pixelsPerSecond;

    // Calculate new position
    final newTime = (_scrubStartPosition + timeDelta).clamp(0.0, _state.duration);

    // Calculate scrub speed (for velocity-based audio preview)
    // Speed is normalized: 1.0 = normal speed, 0.5 = half speed, etc.
    final now = DateTime.now();
    final elapsed = now.difference(_lastScrubTime).inMilliseconds;
    double speed = 0;
    if (elapsed > 0) {
      // Time moved per second of real time
      speed = (newTime - _state.currentTime) / (elapsed / 1000.0);
      // Clamp speed to reasonable range
      speed = speed.clamp(-4.0, 4.0);
    }

    _state = _state.copyWith(scrubSpeed: speed);

    // Update scrub via UnifiedPlaybackController with velocity for audio preview
    UnifiedPlaybackController.instance.updateScrub(newTime, speed);

    seek(newTime, isScrubbing: true);
    _scrubStartPosition = newTime;
  }

  /// End scrubbing - call when drag ends
  void endScrubbing() {
    _state = _state.copyWith(
      isScrubbing: false,
      scrubSpeed: 0,
    );

    // Stop audio scrubbing via UnifiedPlaybackController
    UnifiedPlaybackController.instance.stopScrub();

    notifyListeners();
  }

  /// Jog wheel / scroll scrub - fine-grained position adjustment
  /// [scrollDelta] - scroll amount (positive = forward, negative = backward)
  /// [sensitivity] - seconds per scroll unit (default 0.1 = 100ms per unit)
  void jogScrub(double scrollDelta, {double sensitivity = 0.1}) {
    final timeDelta = scrollDelta * sensitivity;
    final newTime = (_state.currentTime + timeDelta).clamp(0.0, _state.duration);

    // For jog scrub, use momentary scrub - start, update, and immediately schedule stop
    final controller = UnifiedPlaybackController.instance;
    if (!_state.isScrubbing) {
      controller.startScrub(newTime);
    }
    controller.updateScrub(newTime, scrollDelta.sign * 0.5); // Half speed for jog

    seek(newTime, isScrubbing: true);
  }

  void toggleLoop() {
    _state = _state.copyWith(loopEnabled: !_state.loopEnabled);
    notifyListeners();
  }

  void setLoopRegion(double start, double end) {
    _state = _state.copyWith(
      loopStart: start.clamp(0, _state.duration),
      loopEnd: end.clamp(0, _state.duration),
    );
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    // Ticker callback — runs at 60 FPS synced with vsync
    _updatePlayback();
  }

  void _updatePlayback() {
    // Query sample-accurate position from Rust audio engine (lock-free atomic read)
    final currentTime = api.getPlaybackPositionSeconds();

    // End detection
    if (currentTime >= _state.duration && !_state.loopEnabled) {
      _ticker?.dispose();
      _ticker = null;

      _state = _state.copyWith(
        isPlaying: false,
        currentTime: _state.duration,
      );
      notifyListeners();
      onPlaybackEnd?.call();
      return;
    }

    // Update state (always)
    _state = _state.copyWith(currentTime: currentTime);

    // PERFORMANCE: Throttle UI rebuilds to 20fps (50ms) during playback
    // This prevents timeline from rebuilding 60x per second
    final now = DateTime.now();
    if (now.difference(_lastNotifyTime) >= _notifyThrottleDuration) {
      _lastNotifyTime = now;
      notifyListeners();
    }

    // Callback always fires (for audio sync)
    onTimeUpdate?.call(currentTime);
  }

  /// Calculate crossfade gains at current time
  ({double gainA, double gainB})? getCrossfadeGains(PlaybackCrossfade xfade) {
    final currentTime = _state.currentTime;
    final xfadeStart = xfade.startTime;
    final xfadeEnd = xfade.startTime + xfade.duration;

    if (currentTime < xfadeStart || currentTime >= xfadeEnd) {
      return null;
    }

    final progress = (currentTime - xfadeStart) / xfade.duration;

    double fadeOutGain;
    double fadeInGain;

    switch (xfade.curveType) {
      case CrossfadeCurveType.equalPower:
        fadeOutGain = (progress * 3.14159 / 2).cos();
        fadeInGain = (progress * 3.14159 / 2).sin();
      case CrossfadeCurveType.sCurve:
        final t = progress * progress * (3 - 2 * progress);
        fadeOutGain = 1 - t;
        fadeInGain = t;
      case CrossfadeCurveType.linear:
        fadeOutGain = 1 - progress;
        fadeInGain = progress;
    }

    return (gainA: fadeOutGain, gainB: fadeInGain);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }
}

// ============ Utility Extensions ============

extension DoubleExtensions on double {
  double cos() => math.cos(this);
  double sin() => math.sin(this);
}
