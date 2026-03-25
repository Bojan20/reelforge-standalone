// Automation Provider
//
// State management for parameter automation:
// - Automation mode (Read/Touch/Latch/Write/Trim)
// - Recording state
// - Lane management per track/parameter
// - Real-time value updates

import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// ============ Types ============

/// Automation mode matching Rust AutomationMode enum
enum AutomationMode {
  /// Automation is read but not written
  read,
  /// Write automation while parameter is touched
  touch,
  /// Write automation from touch until stop
  latch,
  /// Continuously write automation
  write,
  /// Trim existing automation
  trim,
}

/// Curve type for automation points
enum AutomationCurveType {
  linear,
  bezier,
  exponential,
  logarithmic,
  step,
  sCurve,
}

/// Single automation point
class AutomationPoint {
  final int timeSamples;
  final double value;
  final AutomationCurveType curveType;

  const AutomationPoint({
    required this.timeSamples,
    required this.value,
    this.curveType = AutomationCurveType.linear,
  });

  AutomationPoint copyWith({
    int? timeSamples,
    double? value,
    AutomationCurveType? curveType,
  }) {
    return AutomationPoint(
      timeSamples: timeSamples ?? this.timeSamples,
      value: value ?? this.value,
      curveType: curveType ?? this.curveType,
    );
  }
}

/// Automation lane for a specific parameter
class AutomationLane {
  final int trackId;
  final String paramName;
  final List<AutomationPoint> points;
  final bool visible;
  final double height;

  const AutomationLane({
    required this.trackId,
    required this.paramName,
    this.points = const [],
    this.visible = true,
    this.height = 60.0,
  });

  AutomationLane copyWith({
    int? trackId,
    String? paramName,
    List<AutomationPoint>? points,
    bool? visible,
    double? height,
  }) {
    return AutomationLane(
      trackId: trackId ?? this.trackId,
      paramName: paramName ?? this.paramName,
      points: points ?? this.points,
      visible: visible ?? this.visible,
      height: height ?? this.height,
    );
  }
}

/// Currently touched parameter (for recording)
class TouchedParam {
  final int trackId;
  final String paramName;
  final double initialValue;
  final DateTime touchTime;

  const TouchedParam({
    required this.trackId,
    required this.paramName,
    required this.initialValue,
    required this.touchTime,
  });
}

/// Plugin parameter identifier for automation lanes
class PluginParamId {
  final int trackId;
  final int slot;
  final int paramIndex;
  final String? displayName;

  const PluginParamId({
    required this.trackId,
    required this.slot,
    required this.paramIndex,
    this.displayName,
  });

  /// Unique key for lane map
  String get laneKey => '$trackId:plugin_${slot}_$paramIndex';

  /// Human-readable param name for FFI (matches Rust ParamId format)
  String get paramName => 'param_$paramIndex';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PluginParamId &&
          trackId == other.trackId &&
          slot == other.slot &&
          paramIndex == other.paramIndex;

  @override
  int get hashCode => Object.hash(trackId, slot, paramIndex);
}

// ============ Provider ============

class AutomationProvider extends ChangeNotifier {
  final _ffi = NativeFFI.instance;

  // Current mode
  AutomationMode _mode = AutomationMode.read;

  // Recording state
  bool _isRecording = false;

  // Automation lanes per track
  // Key: "trackId:paramName"
  final Map<String, AutomationLane> _lanes = {};

  // Currently touched parameters (for Touch/Latch modes)
  final Map<String, TouchedParam> _touchedParams = {};

  // Selected lane for editing
  String? _selectedLaneKey;

  // Sample rate for time calculations
  double _sampleRate = 48000;

  // ============ Getters ============

  AutomationMode get mode => _mode;
  bool get isRecording => _isRecording;
  String? get selectedLaneKey => _selectedLaneKey;
  double get sampleRate => _sampleRate;

  /// Get all lanes for a track
  List<AutomationLane> getLanesForTrack(int trackId) {
    return _lanes.values
        .where((lane) => lane.trackId == trackId)
        .toList();
  }

  /// Get specific lane
  AutomationLane? getLane(int trackId, String paramName) {
    return _lanes[_laneKey(trackId, paramName)];
  }

  /// Get all visible lanes
  List<AutomationLane> get visibleLanes =>
      _lanes.values.where((l) => l.visible).toList();

  /// Check if a parameter is currently touched
  bool isParamTouched(int trackId, String paramName) {
    return _touchedParams.containsKey(_laneKey(trackId, paramName));
  }

  // ============ Mode Control ============

  /// Set automation mode
  void setMode(AutomationMode mode) {
    _mode = mode;
    _ffi.automationSetMode(mode.index);
    notifyListeners();
  }

  /// Cycle through modes
  void cycleMode() {
    final nextIndex = (_mode.index + 1) % AutomationMode.values.length;
    setMode(AutomationMode.values[nextIndex]);
  }

  // ============ Recording Control ============

  /// Enable/disable automation recording
  void setRecording(bool enabled) {
    _isRecording = enabled;
    _ffi.automationSetRecording(enabled);
    notifyListeners();
  }

  /// Toggle recording
  void toggleRecording() {
    setRecording(!_isRecording);
  }

  // ============ Parameter Touch (for Touch/Latch modes) ============

  /// Called when user starts adjusting a parameter
  void touchParam(int trackId, String paramName, double currentValue) {
    final key = _laneKey(trackId, paramName);

    _touchedParams[key] = TouchedParam(
      trackId: trackId,
      paramName: paramName,
      initialValue: currentValue,
      touchTime: DateTime.now(),
    );

    _ffi.automationTouchParam(trackId, paramName, currentValue);

    // Ensure lane exists
    _ensureLaneExists(trackId, paramName);

    notifyListeners();
  }

  /// Called when user releases a parameter
  void releaseParam(int trackId, String paramName) {
    final key = _laneKey(trackId, paramName);
    _touchedParams.remove(key);

    _ffi.automationReleaseParam(trackId, paramName);

    notifyListeners();
  }

  /// Record a parameter change (called during playback with recording enabled)
  void recordChange(int trackId, String paramName, double value) {
    if (!_isRecording) return;
    if (_mode == AutomationMode.read) return;

    _ffi.automationRecordChange(trackId, paramName, value);
  }

  // ============ Point Management ============

  /// Add automation point
  void addPoint(
    int trackId,
    String paramName,
    int timeSamples,
    double value, {
    AutomationCurveType curveType = AutomationCurveType.linear,
  }) {
    final key = _laneKey(trackId, paramName);
    _ensureLaneExists(trackId, paramName);

    final lane = _lanes[key]!;
    final newPoint = AutomationPoint(
      timeSamples: timeSamples,
      value: value.clamp(0.0, 1.0),
      curveType: curveType,
    );

    // Insert in sorted order
    final points = List<AutomationPoint>.from(lane.points);
    final insertIndex = points.indexWhere((p) => p.timeSamples > timeSamples);
    if (insertIndex == -1) {
      points.add(newPoint);
    } else {
      points.insert(insertIndex, newPoint);
    }

    _lanes[key] = lane.copyWith(points: points);

    // Sync to engine
    _ffi.automationAddPoint(
      trackId,
      paramName,
      timeSamples,
      value,
      curveType: curveType.index,
    );

    notifyListeners();
  }

  /// Remove automation point at index
  void removePoint(int trackId, String paramName, int pointIndex) {
    final key = _laneKey(trackId, paramName);
    final lane = _lanes[key];
    if (lane == null || pointIndex >= lane.points.length) return;

    final points = List<AutomationPoint>.from(lane.points);
    points.removeAt(pointIndex);
    _lanes[key] = lane.copyWith(points: points);

    // Re-sync entire lane to engine
    _syncLaneToEngine(trackId, paramName);

    notifyListeners();
  }

  /// Move automation point
  void movePoint(
    int trackId,
    String paramName,
    int pointIndex,
    int newTimeSamples,
    double newValue,
  ) {
    final key = _laneKey(trackId, paramName);
    final lane = _lanes[key];
    if (lane == null || pointIndex >= lane.points.length) return;

    final points = List<AutomationPoint>.from(lane.points);
    points[pointIndex] = points[pointIndex].copyWith(
      timeSamples: newTimeSamples,
      value: newValue.clamp(0.0, 1.0),
    );

    // Re-sort by time
    points.sort((a, b) => a.timeSamples.compareTo(b.timeSamples));

    _lanes[key] = lane.copyWith(points: points);

    // Re-sync entire lane to engine
    _syncLaneToEngine(trackId, paramName);

    notifyListeners();
  }

  /// Get automation value at position
  double getValueAt(int trackId, String paramName, int timeSamples) {
    return _ffi.automationGetValue(trackId, paramName, timeSamples);
  }

  // ============ Lane Management ============

  /// Create or show automation lane
  void showLane(int trackId, String paramName) {
    final key = _laneKey(trackId, paramName);
    _ensureLaneExists(trackId, paramName);
    _lanes[key] = _lanes[key]!.copyWith(visible: true);
    notifyListeners();
  }

  /// Hide automation lane
  void hideLane(int trackId, String paramName) {
    final key = _laneKey(trackId, paramName);
    final lane = _lanes[key];
    if (lane != null) {
      _lanes[key] = lane.copyWith(visible: false);
      notifyListeners();
    }
  }

  /// Toggle lane visibility
  void toggleLaneVisibility(int trackId, String paramName) {
    final key = _laneKey(trackId, paramName);
    final lane = _lanes[key];
    if (lane != null) {
      _lanes[key] = lane.copyWith(visible: !lane.visible);
      notifyListeners();
    }
  }

  /// Set lane height
  void setLaneHeight(int trackId, String paramName, double height) {
    final key = _laneKey(trackId, paramName);
    final lane = _lanes[key];
    if (lane != null) {
      _lanes[key] = lane.copyWith(height: height.clamp(30.0, 200.0));
      notifyListeners();
    }
  }

  /// Select lane for editing
  void selectLane(int trackId, String paramName) {
    _selectedLaneKey = _laneKey(trackId, paramName);
    notifyListeners();
  }

  /// Clear selection
  void clearSelection() {
    _selectedLaneKey = null;
    notifyListeners();
  }

  /// Clear all automation for a lane
  void clearLane(int trackId, String paramName) {
    final key = _laneKey(trackId, paramName);
    final lane = _lanes[key];
    if (lane != null) {
      _lanes[key] = lane.copyWith(points: []);
      _ffi.automationClearLane(trackId, paramName);
      notifyListeners();
    }
  }

  /// Delete lane entirely
  void deleteLane(int trackId, String paramName) {
    final key = _laneKey(trackId, paramName);
    _lanes.remove(key);
    _ffi.automationClearLane(trackId, paramName);
    if (_selectedLaneKey == key) {
      _selectedLaneKey = null;
    }
    notifyListeners();
  }

  // ============ Plugin Parameter Automation ============

  /// Touch plugin parameter (start automation recording for plugin knob)
  void touchPluginParam(PluginParamId param, double currentValue) {
    final key = param.laneKey;

    _touchedParams[key] = TouchedParam(
      trackId: param.trackId,
      paramName: param.paramName,
      initialValue: currentValue,
      touchTime: DateTime.now(),
    );

    _ffi.automationTouchPlugin(
      param.trackId,
      param.slot,
      param.paramIndex,
      currentValue,
    );

    // Ensure lane exists with plugin-specific key
    if (!_lanes.containsKey(key)) {
      _lanes[key] = AutomationLane(
        trackId: param.trackId,
        paramName: param.paramName,
      );
    }

    notifyListeners();
  }

  /// Release plugin parameter (stop recording)
  void releasePluginParam(PluginParamId param) {
    _touchedParams.remove(param.laneKey);
    _ffi.automationReleasePlugin(
      param.trackId,
      param.slot,
      param.paramIndex,
    );
    notifyListeners();
  }

  /// Record plugin parameter change during playback
  void recordPluginChange(PluginParamId param, double value) {
    if (!_isRecording) return;
    if (_mode == AutomationMode.read) return;

    // Use the plugin-specific FFI (bypasses string-based paramName)
    _ffi.automationTouchPlugin(
      param.trackId,
      param.slot,
      param.paramIndex,
      value,
    );
  }

  /// Add automation point for plugin parameter
  void addPluginPoint(
    PluginParamId param,
    int timeSamples,
    double value, {
    AutomationCurveType curveType = AutomationCurveType.linear,
  }) {
    final key = param.laneKey;

    // Ensure lane exists
    if (!_lanes.containsKey(key)) {
      _lanes[key] = AutomationLane(
        trackId: param.trackId,
        paramName: param.paramName,
      );
    }

    final lane = _lanes[key]!;
    final newPoint = AutomationPoint(
      timeSamples: timeSamples,
      value: value.clamp(0.0, 1.0),
      curveType: curveType,
    );

    // Insert in sorted order
    final points = List<AutomationPoint>.from(lane.points);
    final insertIndex = points.indexWhere((p) => p.timeSamples > timeSamples);
    if (insertIndex == -1) {
      points.add(newPoint);
    } else {
      points.insert(insertIndex, newPoint);
    }

    _lanes[key] = lane.copyWith(points: points);

    // Sync to engine via plugin-specific FFI
    _ffi.automationAddPluginPoint(
      param.trackId,
      param.slot,
      param.paramIndex,
      timeSamples,
      value,
      curveType.index,
    );

    notifyListeners();
  }

  /// Remove plugin automation point at index
  void removePluginPoint(PluginParamId param, int pointIndex) {
    final key = param.laneKey;
    final lane = _lanes[key];
    if (lane == null || pointIndex >= lane.points.length) return;

    final points = List<AutomationPoint>.from(lane.points);
    points.removeAt(pointIndex);
    _lanes[key] = lane.copyWith(points: points);

    // Re-sync: clear and re-add all points
    _syncPluginLaneToEngine(param);

    notifyListeners();
  }

  /// Move plugin automation point
  void movePluginPoint(
    PluginParamId param,
    int pointIndex,
    int newTimeSamples,
    double newValue,
  ) {
    final key = param.laneKey;
    final lane = _lanes[key];
    if (lane == null || pointIndex >= lane.points.length) return;

    final points = List<AutomationPoint>.from(lane.points);
    points[pointIndex] = points[pointIndex].copyWith(
      timeSamples: newTimeSamples,
      value: newValue.clamp(0.0, 1.0),
    );
    points.sort((a, b) => a.timeSamples.compareTo(b.timeSamples));

    _lanes[key] = lane.copyWith(points: points);

    // Re-sync
    _syncPluginLaneToEngine(param);

    notifyListeners();
  }

  /// Get automated plugin parameter value at position
  double getPluginValueAt(PluginParamId param, int timeSamples) {
    return _ffi.automationGetPluginValue(
      param.trackId,
      param.slot,
      param.paramIndex,
      timeSamples,
    );
  }

  /// Clear all plugin automation for a parameter
  void clearPluginLane(PluginParamId param) {
    final key = param.laneKey;
    final lane = _lanes[key];
    if (lane != null) {
      _lanes[key] = lane.copyWith(points: []);
      _ffi.automationClearPluginLane(
        param.trackId,
        param.slot,
        param.paramIndex,
      );
      notifyListeners();
    }
  }

  /// Delete plugin automation lane entirely
  void deletePluginLane(PluginParamId param) {
    final key = param.laneKey;
    _lanes.remove(key);
    _ffi.automationClearPluginLane(
      param.trackId,
      param.slot,
      param.paramIndex,
    );
    if (_selectedLaneKey == key) {
      _selectedLaneKey = null;
    }
    notifyListeners();
  }

  /// Get all plugin automation lanes for a track
  List<AutomationLane> getPluginLanesForTrack(int trackId) {
    return _lanes.values
        .where((lane) =>
            lane.trackId == trackId &&
            lane.paramName.startsWith('param_'))
        .toList();
  }

  /// Check if a plugin parameter is touched
  bool isPluginParamTouched(PluginParamId param) {
    return _touchedParams.containsKey(param.laneKey);
  }

  // ============ Utility ============

  /// Set sample rate
  void setSampleRate(double sampleRate) {
    _sampleRate = sampleRate;
  }

  /// Convert time in seconds to samples
  int secondsToSamples(double seconds) {
    return (seconds * _sampleRate).round();
  }

  /// Convert samples to seconds
  double samplesToSeconds(int samples) {
    return samples / _sampleRate;
  }

  /// Reset all state
  void reset() {
    _mode = AutomationMode.read;
    _isRecording = false;
    _lanes.clear();
    _touchedParams.clear();
    _selectedLaneKey = null;
    _ffi.automationSetMode(0);
    _ffi.automationSetRecording(false);
    notifyListeners();
  }

  // ============ Private Helpers ============

  String _laneKey(int trackId, String paramName) => '$trackId:$paramName';

  void _ensureLaneExists(int trackId, String paramName) {
    final key = _laneKey(trackId, paramName);
    if (!_lanes.containsKey(key)) {
      _lanes[key] = AutomationLane(
        trackId: trackId,
        paramName: paramName,
      );
    }
  }

  void _syncLaneToEngine(int trackId, String paramName) {
    final key = _laneKey(trackId, paramName);
    final lane = _lanes[key];
    if (lane == null) return;

    // Clear and re-add all points
    _ffi.automationClearLane(trackId, paramName);
    for (final point in lane.points) {
      _ffi.automationAddPoint(
        trackId,
        paramName,
        point.timeSamples,
        point.value,
        curveType: point.curveType.index,
      );
    }
  }

  void _syncPluginLaneToEngine(PluginParamId param) {
    final key = param.laneKey;
    final lane = _lanes[key];
    if (lane == null) return;

    // Clear and re-add all points via plugin-specific FFI
    _ffi.automationClearPluginLane(
      param.trackId,
      param.slot,
      param.paramIndex,
    );
    for (final point in lane.points) {
      _ffi.automationAddPluginPoint(
        param.trackId,
        param.slot,
        param.paramIndex,
        point.timeSamples,
        point.value,
        point.curveType.index,
      );
    }
  }

}
