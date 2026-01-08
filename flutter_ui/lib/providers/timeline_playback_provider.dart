// Timeline Playback Provider
//
// Connects timeline clips to audio playback with:
// - Seamless loop playback (Cubase-style)
// - Crossfade gain curves
// - Track mute/solo/volume/pan
// - Scrubbing with throttling

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

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
  final double currentTime;
  final double duration;
  final bool loopEnabled;
  final double loopStart;
  final double loopEnd;

  const TimelinePlaybackState({
    this.isPlaying = false,
    this.isPaused = false,
    this.currentTime = 0,
    this.duration = 60,
    this.loopEnabled = false,
    this.loopStart = 0,
    this.loopEnd = 60,
  });

  TimelinePlaybackState copyWith({
    bool? isPlaying,
    bool? isPaused,
    double? currentTime,
    double? duration,
    bool? loopEnabled,
    double? loopStart,
    double? loopEnd,
  }) {
    return TimelinePlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      isPaused: isPaused ?? this.isPaused,
      currentTime: currentTime ?? this.currentTime,
      duration: duration ?? this.duration,
      loopEnabled: loopEnabled ?? this.loopEnabled,
      loopStart: loopStart ?? this.loopStart,
      loopEnd: loopEnd ?? this.loopEnd,
    );
  }
}

// ============ Provider ============

class TimelinePlaybackProvider extends ChangeNotifier {
  TimelinePlaybackState _state = const TimelinePlaybackState();
  List<TimelineClipData> _clips = [];
  // ignore: unused_field
  List<PlaybackCrossfade> _crossfades = [];

  Timer? _updateTimer;
  DateTime? _playbackStartTime;
  double _playbackOffset = 0;

  // Scrub throttling
  DateTime _lastSeekTime = DateTime.now();
  static const Duration _seekThrottleDuration = Duration(milliseconds: 100);

  // Callbacks
  void Function(double time)? onTimeUpdate;
  void Function()? onPlaybackEnd;

  TimelinePlaybackState get state => _state;
  bool get isPlaying => _state.isPlaying;
  bool get isPaused => _state.isPaused;
  double get currentTime => _state.currentTime;
  double get duration => _state.duration;
  bool get loopEnabled => _state.loopEnabled;
  double get loopStart => _state.loopStart;
  double get loopEnd => _state.loopEnd;

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

    _playbackStartTime = DateTime.now();
    _playbackOffset = _state.currentTime;

    // Start update timer (50ms = 20 updates/sec)
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _updatePlayback(),
    );

    _state = _state.copyWith(isPlaying: true, isPaused: false);
    notifyListeners();

    // Initial update
    _updatePlayback();
  }

  void pause() {
    _updateTimer?.cancel();
    _updateTimer = null;

    _state = _state.copyWith(isPlaying: false, isPaused: true);
    notifyListeners();
  }

  void stop() {
    _updateTimer?.cancel();
    _updateTimer = null;

    _state = _state.copyWith(
      isPlaying: false,
      isPaused: false,
      currentTime: 0,
    );
    notifyListeners();
  }

  void seek(double time, {bool isScrubbing = false}) {
    final clampedTime = time.clamp(0.0, _state.duration);
    final now = DateTime.now();

    if (_state.isPlaying && isScrubbing) {
      // Throttle during scrubbing
      if (now.difference(_lastSeekTime) > _seekThrottleDuration) {
        _playbackStartTime = now;
        _playbackOffset = clampedTime;
        _lastSeekTime = now;
      }
    } else if (_state.isPlaying) {
      // Normal seek - immediate
      _playbackStartTime = now;
      _playbackOffset = clampedTime;
    }

    _state = _state.copyWith(currentTime: clampedTime);
    notifyListeners();
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

  void _updatePlayback() {
    if (_playbackStartTime == null) return;

    final elapsed = DateTime.now().difference(_playbackStartTime!).inMilliseconds / 1000.0;
    var currentTime = _playbackOffset + elapsed;

    // Loop handling
    if (_state.loopEnabled && currentTime >= _state.loopEnd) {
      final loopDuration = _state.loopEnd - _state.loopStart;
      final overshoot = currentTime - _state.loopEnd;

      currentTime = _state.loopStart + (overshoot % loopDuration);
      _playbackStartTime = DateTime.now();
      _playbackOffset = currentTime;
    }

    // End detection
    if (currentTime >= _state.duration && !_state.loopEnabled) {
      _updateTimer?.cancel();
      _updateTimer = null;

      _state = _state.copyWith(
        isPlaying: false,
        currentTime: _state.duration,
      );
      notifyListeners();
      onPlaybackEnd?.call();
      return;
    }

    _state = _state.copyWith(currentTime: currentTime);
    notifyListeners();
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
    _updateTimer?.cancel();
    super.dispose();
  }
}

// ============ Utility Extensions ============

extension DoubleExtensions on double {
  double cos() => math.cos(this);
  double sin() => math.sin(this);
}
