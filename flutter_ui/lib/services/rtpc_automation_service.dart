/// FluxForge Studio RTPC Automation Service
///
/// P2-MW-5: Record and playback RTPC value changes
/// - Record RTPC value changes with timestamps
/// - Playback recorded automation
/// - Loop and speed control
/// - Export/Import automation data
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AUTOMATION DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Single automation point
class AutomationPoint {
  final int timeMs;
  final double value;

  const AutomationPoint({required this.timeMs, required this.value});

  Map<String, dynamic> toJson() => {'timeMs': timeMs, 'value': value};

  factory AutomationPoint.fromJson(Map<String, dynamic> json) {
    return AutomationPoint(
      timeMs: json['timeMs'] as int? ?? 0,
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Recorded automation lane for a single RTPC
class AutomationLane {
  final int rtpcId;
  final String name;
  final List<AutomationPoint> points;
  final int durationMs;

  const AutomationLane({
    required this.rtpcId,
    required this.name,
    this.points = const [],
    this.durationMs = 0,
  });

  AutomationLane copyWith({
    int? rtpcId,
    String? name,
    List<AutomationPoint>? points,
    int? durationMs,
  }) {
    return AutomationLane(
      rtpcId: rtpcId ?? this.rtpcId,
      name: name ?? this.name,
      points: points ?? this.points,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'rtpcId': rtpcId,
        'name': name,
        'points': points.map((p) => p.toJson()).toList(),
        'durationMs': durationMs,
      };

  factory AutomationLane.fromJson(Map<String, dynamic> json) {
    return AutomationLane(
      rtpcId: json['rtpcId'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      points: (json['points'] as List<dynamic>?)
              ?.map((p) => AutomationPoint.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      durationMs: json['durationMs'] as int? ?? 0,
    );
  }

  /// Evaluate value at time (with linear interpolation)
  double evaluate(int timeMs) {
    if (points.isEmpty) return 0.0;
    if (timeMs <= points.first.timeMs) return points.first.value;
    if (timeMs >= points.last.timeMs) return points.last.value;

    // Find surrounding points
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];

      if (timeMs >= p0.timeMs && timeMs <= p1.timeMs) {
        final t = (timeMs - p0.timeMs) / (p1.timeMs - p0.timeMs);
        return p0.value + (p1.value - p0.value) * t;
      }
    }

    return points.last.value;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

enum AutomationState { idle, recording, playing }

/// Service for RTPC automation recording and playback
class RtpcAutomationService extends ChangeNotifier {
  static final RtpcAutomationService _instance = RtpcAutomationService._();
  static RtpcAutomationService get instance => _instance;

  RtpcAutomationService._();

  /// Current state
  AutomationState _state = AutomationState.idle;
  AutomationState get state => _state;

  /// Recorded lanes
  final Map<int, AutomationLane> _lanes = {};

  /// Recording state
  int? _recordingRtpcId;
  List<AutomationPoint> _recordingPoints = [];
  Stopwatch? _recordingStopwatch;

  /// Playback state
  Timer? _playbackTimer;
  Stopwatch? _playbackStopwatch;
  bool _looping = false;
  double _playbackSpeed = 1.0;
  int _playbackDurationMs = 0;

  /// Callback when RTPC value changes during playback
  void Function(int rtpcId, double value)? onValueChanged;

  /// Get all recorded lanes
  List<AutomationLane> get lanes => _lanes.values.toList();

  /// Get lane for RTPC
  AutomationLane? getLane(int rtpcId) => _lanes[rtpcId];

  /// Playback settings
  bool get looping => _looping;
  double get playbackSpeed => _playbackSpeed;

  /// Current playback position
  int get playbackPositionMs {
    if (_playbackStopwatch == null) return 0;
    return (_playbackStopwatch!.elapsedMilliseconds * _playbackSpeed).toInt();
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // RECORDING
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Start recording RTPC values
  void startRecording(int rtpcId, String name) {
    if (_state != AutomationState.idle) return;

    _recordingRtpcId = rtpcId;
    _recordingPoints = [];
    _recordingStopwatch = Stopwatch()..start();
    _state = AutomationState.recording;

    notifyListeners();
  }

  /// Record a value during recording
  void recordValue(double value) {
    if (_state != AutomationState.recording) return;
    if (_recordingStopwatch == null || _recordingRtpcId == null) return;

    final timeMs = _recordingStopwatch!.elapsedMilliseconds;
    _recordingPoints.add(AutomationPoint(timeMs: timeMs, value: value));
  }

  /// Stop recording and save lane
  AutomationLane? stopRecording() {
    if (_state != AutomationState.recording) return null;
    if (_recordingRtpcId == null) return null;

    _recordingStopwatch?.stop();
    final durationMs = _recordingStopwatch?.elapsedMilliseconds ?? 0;

    final lane = AutomationLane(
      rtpcId: _recordingRtpcId!,
      name: 'RTPC ${_recordingRtpcId!} Automation',
      points: List.from(_recordingPoints),
      durationMs: durationMs,
    );

    _lanes[_recordingRtpcId!] = lane;

    // Reset recording state
    _recordingRtpcId = null;
    _recordingPoints = [];
    _recordingStopwatch = null;
    _state = AutomationState.idle;

    notifyListeners();

    return lane;
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // PLAYBACK
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Start playback of recorded automation
  void startPlayback({bool loop = false, double speed = 1.0}) {
    if (_state != AutomationState.idle) return;
    if (_lanes.isEmpty) return;

    _looping = loop;
    _playbackSpeed = speed.clamp(0.1, 4.0);
    _playbackDurationMs = _lanes.values
        .map((l) => l.durationMs)
        .reduce((a, b) => a > b ? a : b);

    _playbackStopwatch = Stopwatch()..start();
    _state = AutomationState.playing;

    // Start playback timer (60fps)
    _playbackTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _onPlaybackTick(),
    );

    notifyListeners();
  }

  void _onPlaybackTick() {
    if (_state != AutomationState.playing) return;

    var timeMs = playbackPositionMs;

    // Handle looping
    if (timeMs >= _playbackDurationMs) {
      if (_looping) {
        _playbackStopwatch?.reset();
        _playbackStopwatch?.start();
        timeMs = 0;
      } else {
        stopPlayback();
        return;
      }
    }

    // Evaluate all lanes and emit values
    for (final lane in _lanes.values) {
      final value = lane.evaluate(timeMs);
      onValueChanged?.call(lane.rtpcId, value);
    }

    notifyListeners();
  }

  /// Stop playback
  void stopPlayback() {
    if (_state != AutomationState.playing) return;

    _playbackTimer?.cancel();
    _playbackTimer = null;
    _playbackStopwatch?.stop();
    _playbackStopwatch = null;
    _state = AutomationState.idle;

    notifyListeners();
  }

  /// Pause playback
  void pausePlayback() {
    if (_state != AutomationState.playing) return;

    _playbackTimer?.cancel();
    _playbackTimer = null;
    _playbackStopwatch?.stop();

    notifyListeners();
  }

  /// Resume playback
  void resumePlayback() {
    if (_state != AutomationState.playing) return;
    if (_playbackTimer != null) return;

    _playbackStopwatch?.start();
    _playbackTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _onPlaybackTick(),
    );

    notifyListeners();
  }

  /// Set looping
  void setLooping(bool loop) {
    _looping = loop;
    notifyListeners();
  }

  /// Set playback speed
  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed.clamp(0.1, 4.0);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // LANE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Delete a lane
  void deleteLane(int rtpcId) {
    _lanes.remove(rtpcId);
    notifyListeners();
  }

  /// Clear all lanes
  void clearAllLanes() {
    _lanes.clear();
    notifyListeners();
  }

  /// Import lane from JSON
  void importLane(Map<String, dynamic> json) {
    final lane = AutomationLane.fromJson(json);
    _lanes[lane.rtpcId] = lane;
    notifyListeners();
  }

  /// Export all lanes to JSON
  Map<String, dynamic> exportAll() {
    return {
      'lanes': _lanes.values.map((l) => l.toJson()).toList(),
    };
  }

  /// Import all lanes from JSON
  void importAll(Map<String, dynamic> json) {
    _lanes.clear();
    final list = json['lanes'] as List<dynamic>?;
    if (list != null) {
      for (final item in list) {
        final lane = AutomationLane.fromJson(item as Map<String, dynamic>);
        _lanes[lane.rtpcId] = lane;
      }
    }
    notifyListeners();
  }

  /// Clear all state
  void clear() {
    stopPlayback();
    if (_state == AutomationState.recording) {
      _recordingStopwatch?.stop();
      _state = AutomationState.idle;
    }
    _lanes.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }
}
