/// VCA Automation Service (P10.1.15)
///
/// Records VCA fader movements to automation lanes for playback.
/// Enables complex gain automation via VCA control.
///
/// Features:
/// - Record VCA level changes with timestamps
/// - Playback recorded automation
/// - Multiple automation lanes per VCA
/// - Import/export automation data

import 'dart:async';
import 'package:flutter/foundation.dart';

/// A single automation point with timestamp and value
class AutomationPoint {
  final int timestampMs;
  final double value; // 0.0 - 1.5 (VCA level)

  const AutomationPoint({
    required this.timestampMs,
    required this.value,
  });

  AutomationPoint copyWith({int? timestampMs, double? value}) {
    return AutomationPoint(
      timestampMs: timestampMs ?? this.timestampMs,
      value: value ?? this.value,
    );
  }

  Map<String, dynamic> toJson() => {
        'timestampMs': timestampMs,
        'value': value,
      };

  factory AutomationPoint.fromJson(Map<String, dynamic> json) {
    return AutomationPoint(
      timestampMs: json['timestampMs'] as int,
      value: (json['value'] as num).toDouble(),
    );
  }

  @override
  String toString() => 'AutomationPoint($timestampMs ms, $value)';
}

/// An automation lane containing recorded points
class AutomationLane {
  final String id;
  final String vcaId;
  final String name;
  final List<AutomationPoint> points;
  final bool enabled;

  const AutomationLane({
    required this.id,
    required this.vcaId,
    required this.name,
    this.points = const [],
    this.enabled = true,
  });

  AutomationLane copyWith({
    String? id,
    String? vcaId,
    String? name,
    List<AutomationPoint>? points,
    bool? enabled,
  }) {
    return AutomationLane(
      id: id ?? this.id,
      vcaId: vcaId ?? this.vcaId,
      name: name ?? this.name,
      points: points ?? this.points,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Get interpolated value at given timestamp
  double valueAt(int timestampMs) {
    if (points.isEmpty) return 1.0;
    if (points.length == 1) return points.first.value;

    // Find surrounding points
    AutomationPoint? before;
    AutomationPoint? after;

    for (int i = 0; i < points.length; i++) {
      if (points[i].timestampMs <= timestampMs) {
        before = points[i];
      }
      if (points[i].timestampMs >= timestampMs && after == null) {
        after = points[i];
      }
    }

    // Edge cases
    if (before == null) return points.first.value;
    if (after == null) return points.last.value;
    if (before.timestampMs == after.timestampMs) return before.value;

    // Linear interpolation
    final t = (timestampMs - before.timestampMs) /
        (after.timestampMs - before.timestampMs);
    return before.value + (after.value - before.value) * t;
  }

  /// Duration of automation lane in ms
  int get durationMs {
    if (points.isEmpty) return 0;
    return points.last.timestampMs - points.first.timestampMs;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'vcaId': vcaId,
        'name': name,
        'points': points.map((p) => p.toJson()).toList(),
        'enabled': enabled,
      };

  factory AutomationLane.fromJson(Map<String, dynamic> json) {
    return AutomationLane(
      id: json['id'] as String,
      vcaId: json['vcaId'] as String,
      name: json['name'] as String,
      points: (json['points'] as List)
          .map((p) => AutomationPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

/// Service for VCA automation recording and playback
class VcaAutomationService {
  static final VcaAutomationService _instance = VcaAutomationService._();
  static VcaAutomationService get instance => _instance;

  VcaAutomationService._();

  /// All automation lanes
  final Map<String, AutomationLane> _lanes = {};

  /// Currently recording VCA ID
  String? _recordingVcaId;
  String? get recordingVcaId => _recordingVcaId;

  /// Recording start time
  DateTime? _recordingStartTime;

  /// Points being recorded
  List<AutomationPoint> _recordingPoints = [];

  /// Whether recording is active
  bool get isRecording => _recordingVcaId != null;

  /// Currently playing
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  /// Playback timer
  Timer? _playbackTimer;

  /// Playback start time
  DateTime? _playbackStartTime;

  /// Current playback position in ms
  int _playbackPositionMs = 0;
  int get playbackPositionMs => _playbackPositionMs;

  /// Listeners for state changes
  final List<VoidCallback> _listeners = [];

  /// Callback for applying VCA level during playback
  void Function(String vcaId, double level)? onVcaLevelChange;

  /// Add listener
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Remove listener
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Get all lanes
  List<AutomationLane> get lanes => _lanes.values.toList();

  /// Get lanes for a specific VCA
  List<AutomationLane> getLanesForVca(String vcaId) {
    return _lanes.values.where((l) => l.vcaId == vcaId).toList();
  }

  /// Get lane by ID
  AutomationLane? getLane(String laneId) => _lanes[laneId];

  // ═══════════════════════════════════════════════════════════════════════════
  // RECORDING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start recording automation for a VCA
  void startRecording(String vcaId) {
    if (_recordingVcaId != null) {
      stopRecording();
    }

    _recordingVcaId = vcaId;
    _recordingStartTime = DateTime.now();
    _recordingPoints = [];

    _notifyListeners();
  }

  /// Capture an automation point during recording
  void captureAutomationPoint(double value) {
    if (_recordingVcaId == null || _recordingStartTime == null) return;

    final timestampMs =
        DateTime.now().difference(_recordingStartTime!).inMilliseconds;

    // Don't record duplicate values at same time
    if (_recordingPoints.isNotEmpty &&
        _recordingPoints.last.timestampMs == timestampMs) {
      _recordingPoints[_recordingPoints.length - 1] = AutomationPoint(
        timestampMs: timestampMs,
        value: value.clamp(0.0, 2.0),
      );
    } else {
      _recordingPoints.add(AutomationPoint(
        timestampMs: timestampMs,
        value: value.clamp(0.0, 2.0),
      ));
    }
  }

  /// Stop recording and create lane
  AutomationLane? stopRecording({String? name}) {
    if (_recordingVcaId == null) return null;

    final vcaId = _recordingVcaId!;
    final points = List<AutomationPoint>.from(_recordingPoints);

    _recordingVcaId = null;
    _recordingStartTime = null;
    _recordingPoints = [];

    if (points.isEmpty) {
      _notifyListeners();
      return null;
    }

    // Create new lane
    final laneId = 'lane_${DateTime.now().millisecondsSinceEpoch}';
    final lane = AutomationLane(
      id: laneId,
      vcaId: vcaId,
      name: name ?? 'Automation ${_lanes.length + 1}',
      points: points,
    );

    _lanes[laneId] = lane;

    _notifyListeners();

    return lane;
  }

  /// Cancel recording without saving
  void cancelRecording() {
    _recordingVcaId = null;
    _recordingStartTime = null;
    _recordingPoints = [];
    _notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYBACK
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start playback of automation for a VCA
  void startPlayback(String vcaId, {int startPositionMs = 0}) {
    if (_isPlaying) stopPlayback();

    final vcaLanes = getLanesForVca(vcaId).where((l) => l.enabled).toList();
    if (vcaLanes.isEmpty) {
      return;
    }

    _isPlaying = true;
    _playbackStartTime = DateTime.now();
    _playbackPositionMs = startPositionMs;

    // Start playback timer (60fps)
    _playbackTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (timer) => _updatePlayback(vcaId, vcaLanes),
    );

    _notifyListeners();
  }

  void _updatePlayback(String vcaId, List<AutomationLane> vcaLanes) {
    if (!_isPlaying || _playbackStartTime == null) {
      stopPlayback();
      return;
    }

    _playbackPositionMs =
        DateTime.now().difference(_playbackStartTime!).inMilliseconds;

    // Find max duration
    final maxDuration = vcaLanes.fold<int>(
        0, (max, lane) => lane.durationMs > max ? lane.durationMs : max);

    if (_playbackPositionMs > maxDuration) {
      stopPlayback();
      return;
    }

    // Get interpolated value from first enabled lane
    // (could be extended to blend multiple lanes)
    final lane = vcaLanes.first;
    final value = lane.valueAt(_playbackPositionMs);

    // Apply via callback
    onVcaLevelChange?.call(vcaId, value);

    _notifyListeners();
  }

  /// Stop playback
  void stopPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _isPlaying = false;
    _playbackPositionMs = 0;

    _notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LANE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Delete a lane
  void deleteLane(String laneId) {
    _lanes.remove(laneId);
    _notifyListeners();
  }

  /// Update lane enabled state
  void setLaneEnabled(String laneId, bool enabled) {
    final lane = _lanes[laneId];
    if (lane == null) return;

    _lanes[laneId] = lane.copyWith(enabled: enabled);
    _notifyListeners();
  }

  /// Rename lane
  void renameLane(String laneId, String name) {
    final lane = _lanes[laneId];
    if (lane == null) return;

    _lanes[laneId] = lane.copyWith(name: name);
    _notifyListeners();
  }

  /// Clear all lanes for a VCA
  void clearLanesForVca(String vcaId) {
    _lanes.removeWhere((id, lane) => lane.vcaId == vcaId);
    _notifyListeners();
  }

  /// Clear all lanes
  void clearAllLanes() {
    _lanes.clear();
    _notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export all lanes to JSON
  Map<String, dynamic> toJson() {
    return {
      'lanes': _lanes.values.map((l) => l.toJson()).toList(),
    };
  }

  /// Import lanes from JSON
  void fromJson(Map<String, dynamic> json) {
    _lanes.clear();
    final lanesList = json['lanes'] as List?;
    if (lanesList != null) {
      for (final laneJson in lanesList) {
        final lane = AutomationLane.fromJson(laneJson as Map<String, dynamic>);
        _lanes[lane.id] = lane;
      }
    }
    _notifyListeners();
  }

  /// Dispose resources
  void dispose() {
    stopPlayback();
    cancelRecording();
    _listeners.clear();
  }
}
