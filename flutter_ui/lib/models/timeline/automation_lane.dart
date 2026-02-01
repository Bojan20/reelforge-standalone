// Automation Lane Model — Timeline Parameter Automation
//
// Represents automation curves for volume, pan, RTPC parameters.
// Supports bezier interpolation, multiple curve types.

import 'dart:math' as math;

/// Interpolation curve type
enum CurveType {
  linear,      // Straight line
  bezier,      // Smooth curve
  step,        // Instant jump
  exponential, // Exponential curve
  logarithmic, // Logarithmic curve
}

/// Single automation point
class AutomationPoint {
  final String id;
  double time;              // Time in seconds
  double value;             // Normalized 0.0-1.0 (converted based on parameter)
  CurveType interpolation;

  AutomationPoint({
    required this.id,
    required this.time,
    required this.value,
    this.interpolation = CurveType.linear,
  });

  AutomationPoint copyWith({
    String? id,
    double? time,
    double? value,
    CurveType? interpolation,
  }) {
    return AutomationPoint(
      id: id ?? this.id,
      time: time ?? this.time,
      value: value ?? this.value,
      interpolation: interpolation ?? this.interpolation,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'time': time,
    'value': value,
    'interpolation': interpolation.name,
  };

  factory AutomationPoint.fromJson(Map<String, dynamic> json) {
    return AutomationPoint(
      id: json['id'] as String,
      time: (json['time'] as num).toDouble(),
      value: (json['value'] as num).toDouble(),
      interpolation: CurveType.values.firstWhere(
        (t) => t.name == json['interpolation'],
        orElse: () => CurveType.linear,
      ),
    );
  }
}

/// Parameter type for automation
enum AutomationParameterType {
  volume,   // 0.0-2.0 (−∞ to +6dB)
  pan,      // −1.0 to +1.0 (L/R)
  rtpc,     // Custom range per RTPC
  trigger,  // Boolean on/off
}

/// Automation lane for a single parameter
class AutomationLane {
  final String id;
  final String parameterId;           // 'volume', 'pan', 'rtpc_winAmount'
  final AutomationParameterType type;
  final List<AutomationPoint> points;
  final Color curveColor;
  final double minValue;
  final double maxValue;
  final bool isVisible;

  AutomationLane({
    required this.id,
    required this.parameterId,
    required this.type,
    List<AutomationPoint>? points,
    Color? curveColor,
    double? minValue,
    double? maxValue,
    this.isVisible = true,
  })  : points = points ?? [],
        curveColor = curveColor ?? _defaultColorForType(type),
        minValue = minValue ?? _defaultMinForType(type),
        maxValue = maxValue ?? _defaultMaxForType(type);

  /// Get interpolated value at specific time
  double getValueAt(double timeSeconds) {
    if (points.isEmpty) return minValue;
    if (points.length == 1) return _denormalize(points[0].value);

    // Sort points by time
    final sortedPoints = List<AutomationPoint>.from(points)
      ..sort((a, b) => a.time.compareTo(b.time));

    // Find surrounding points
    AutomationPoint? before;
    AutomationPoint? after;

    for (int i = 0; i < sortedPoints.length; i++) {
      final point = sortedPoints[i];
      if (point.time <= timeSeconds) {
        before = point;
      }
      if (point.time >= timeSeconds && after == null) {
        after = point;
        break;
      }
    }

    // Edge cases
    if (before == null) return _denormalize(sortedPoints.first.value);
    if (after == null) return _denormalize(sortedPoints.last.value);
    if (before.time == after.time) return _denormalize(before.value);

    // Interpolate based on curve type
    final t = (timeSeconds - before.time) / (after.time - before.time);
    final interpolatedNormalized = _interpolate(before, after, t);

    return _denormalize(interpolatedNormalized);
  }

  /// Interpolate between two points
  double _interpolate(AutomationPoint a, AutomationPoint b, double t) {
    switch (a.interpolation) {
      case CurveType.step:
        return a.value;

      case CurveType.linear:
        return a.value + (b.value - a.value) * t;

      case CurveType.bezier:
        // Simple bezier: control point at midpoint
        final cp = (a.value + b.value) / 2;
        final u = 1 - t;
        return u * u * a.value + 2 * u * t * cp + t * t * b.value;

      case CurveType.exponential:
        return a.value + (b.value - a.value) * (t * t);

      case CurveType.logarithmic:
        return a.value + (b.value - a.value) * math.sqrt(t);
    }
  }

  /// Convert normalized 0-1 to actual parameter value
  double _denormalize(double normalized) {
    return minValue + (maxValue - minValue) * normalized.clamp(0.0, 1.0);
  }

  /// Convert actual parameter value to normalized 0-1
  double normalize(double value) {
    if (maxValue == minValue) return 0.0;
    return ((value - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);
  }

  /// Add automation point
  AutomationLane addPoint(AutomationPoint point) {
    final updatedPoints = List<AutomationPoint>.from(points)..add(point);
    return copyWith(points: updatedPoints);
  }

  /// Remove point by ID
  AutomationLane removePoint(String pointId) {
    final updatedPoints = points.where((p) => p.id != pointId).toList();
    return copyWith(points: updatedPoints);
  }

  /// Update existing point
  AutomationLane updatePoint(String pointId, {double? time, double? value, CurveType? interpolation}) {
    final updatedPoints = points.map((p) {
      if (p.id == pointId) {
        return p.copyWith(time: time, value: value, interpolation: interpolation);
      }
      return p;
    }).toList();
    return copyWith(points: updatedPoints);
  }

  /// Smooth curve between two points (add intermediate points)
  AutomationLane smoothBetween(int startIndex, int endIndex) {
    if (startIndex >= endIndex || startIndex < 0 || endIndex >= points.length) {
      return this;
    }

    final sortedPoints = List<AutomationPoint>.from(points)
      ..sort((a, b) => a.time.compareTo(b.time));

    final start = sortedPoints[startIndex];
    final end = sortedPoints[endIndex];

    // Add 3 intermediate points with bezier curve
    final newPoints = List<AutomationPoint>.from(sortedPoints);
    final timeDelta = (end.time - start.time) / 4;

    for (int i = 1; i <= 3; i++) {
      final t = i / 4.0;
      final time = start.time + timeDelta * i;
      final value = _interpolate(start, end, t);

      newPoints.add(AutomationPoint(
        id: 'smooth_${start.id}_${end.id}_$i',
        time: time,
        value: value,
        interpolation: CurveType.bezier,
      ));
    }

    return copyWith(points: newPoints);
  }

  /// Copy with modifications
  AutomationLane copyWith({
    String? id,
    String? parameterId,
    AutomationParameterType? type,
    List<AutomationPoint>? points,
    Color? curveColor,
    double? minValue,
    double? maxValue,
    bool? isVisible,
  }) {
    return AutomationLane(
      id: id ?? this.id,
      parameterId: parameterId ?? this.parameterId,
      type: type ?? this.type,
      points: points ?? this.points,
      curveColor: curveColor ?? this.curveColor,
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
      isVisible: isVisible ?? this.isVisible,
    );
  }

  /// JSON serialization
  Map<String, dynamic> toJson() => {
    'id': id,
    'parameterId': parameterId,
    'type': type.name,
    'points': points.map((p) => p.toJson()).toList(),
    'curveColor': curveColor.value,
    'minValue': minValue,
    'maxValue': maxValue,
    'isVisible': isVisible,
  };

  factory AutomationLane.fromJson(Map<String, dynamic> json) {
    return AutomationLane(
      id: json['id'] as String,
      parameterId: json['parameterId'] as String,
      type: AutomationParameterType.values.firstWhere((t) => t.name == json['type']),
      points: (json['points'] as List).map((p) => AutomationPoint.fromJson(p)).toList(),
      curveColor: Color(json['curveColor'] as int),
      minValue: (json['minValue'] as num).toDouble(),
      maxValue: (json['maxValue'] as num).toDouble(),
      isVisible: json['isVisible'] as bool? ?? true,
    );
  }

  /// Default color for parameter type
  static Color _defaultColorForType(AutomationParameterType type) {
    switch (type) {
      case AutomationParameterType.volume:
        return const Color(0xFFFF9040); // Orange
      case AutomationParameterType.pan:
        return const Color(0xFF40C8FF); // Cyan
      case AutomationParameterType.rtpc:
        return const Color(0xFF9370DB); // Purple
      case AutomationParameterType.trigger:
        return const Color(0xFF40FF90); // Green
    }
  }

  /// Default min value for parameter type
  static double _defaultMinForType(AutomationParameterType type) {
    switch (type) {
      case AutomationParameterType.volume:
        return 0.0;
      case AutomationParameterType.pan:
        return -1.0;
      case AutomationParameterType.rtpc:
        return 0.0;
      case AutomationParameterType.trigger:
        return 0.0;
    }
  }

  /// Default max value for parameter type
  static double _defaultMaxForType(AutomationParameterType type) {
    switch (type) {
      case AutomationParameterType.volume:
        return 2.0; // +6dB
      case AutomationParameterType.pan:
        return 1.0;
      case AutomationParameterType.rtpc:
        return 1.0;
      case AutomationParameterType.trigger:
        return 1.0;
    }
  }
}
