/// FluxForge Studio Advanced Ducking Curves Service
///
/// P2-MW-3: Extended ducking curve shapes with visual editor support
/// - 5 curve shapes: linear, exponential, logarithmic, s-curve, custom
/// - Visual curve editor integration
/// - Per-curve parameter customization
library;

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/middleware_models.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ADVANCED CURVE TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Extended ducking curve with customizable parameters
enum AdvancedDuckingCurve {
  linear,
  exponential,
  logarithmic,
  sCurve,
  custom,
}

extension AdvancedDuckingCurveExtension on AdvancedDuckingCurve {
  String get displayName {
    switch (this) {
      case AdvancedDuckingCurve.linear:
        return 'Linear';
      case AdvancedDuckingCurve.exponential:
        return 'Exponential';
      case AdvancedDuckingCurve.logarithmic:
        return 'Logarithmic';
      case AdvancedDuckingCurve.sCurve:
        return 'S-Curve';
      case AdvancedDuckingCurve.custom:
        return 'Custom';
    }
  }

  String get description {
    switch (this) {
      case AdvancedDuckingCurve.linear:
        return 'Constant rate of change';
      case AdvancedDuckingCurve.exponential:
        return 'Fast start, slow finish';
      case AdvancedDuckingCurve.logarithmic:
        return 'Slow start, fast finish';
      case AdvancedDuckingCurve.sCurve:
        return 'Smooth ease in and out';
      case AdvancedDuckingCurve.custom:
        return 'User-defined control points';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CURVE PARAMETERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Parameters for custom curve control
class DuckingCurveParams {
  final AdvancedDuckingCurve type;

  /// Exponential/logarithmic curve strength (0.5 = gentle, 3.0 = extreme)
  final double power;

  /// S-curve tension (higher = steeper transition)
  final double tension;

  /// Custom bezier control points (normalized 0-1)
  final List<CurveControlPoint>? customPoints;

  const DuckingCurveParams({
    this.type = AdvancedDuckingCurve.linear,
    this.power = 2.0,
    this.tension = 1.5,
    this.customPoints,
  });

  DuckingCurveParams copyWith({
    AdvancedDuckingCurve? type,
    double? power,
    double? tension,
    List<CurveControlPoint>? customPoints,
  }) {
    return DuckingCurveParams(
      type: type ?? this.type,
      power: power ?? this.power,
      tension: tension ?? this.tension,
      customPoints: customPoints ?? this.customPoints,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.index,
        'power': power,
        'tension': tension,
        'customPoints': customPoints?.map((p) => p.toJson()).toList(),
      };

  factory DuckingCurveParams.fromJson(Map<String, dynamic> json) {
    return DuckingCurveParams(
      type: AdvancedDuckingCurve.values[json['type'] as int? ?? 0],
      power: (json['power'] as num?)?.toDouble() ?? 2.0,
      tension: (json['tension'] as num?)?.toDouble() ?? 1.5,
      customPoints: (json['customPoints'] as List<dynamic>?)
          ?.map((p) => CurveControlPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Control point for custom bezier curves
class CurveControlPoint {
  final double x;
  final double y;

  const CurveControlPoint({required this.x, required this.y});

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory CurveControlPoint.fromJson(Map<String, dynamic> json) {
    return CurveControlPoint(
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Service for advanced ducking curve evaluation
class AdvancedDuckingCurvesService {
  static final AdvancedDuckingCurvesService _instance =
      AdvancedDuckingCurvesService._();
  static AdvancedDuckingCurvesService get instance => _instance;

  AdvancedDuckingCurvesService._();

  /// Stored curve parameters per rule ID
  final Map<int, DuckingCurveParams> _ruleParams = {};

  /// Set curve parameters for a rule
  void setRuleParams(int ruleId, DuckingCurveParams params) {
    _ruleParams[ruleId] = params;
  }

  /// Get curve parameters for a rule
  DuckingCurveParams? getRuleParams(int ruleId) => _ruleParams[ruleId];

  /// Remove params for a rule
  void removeRuleParams(int ruleId) {
    _ruleParams.remove(ruleId);
  }

  /// Evaluate curve at normalized time t (0-1)
  /// Returns normalized value (0-1), where 1 = full duck
  double evaluate(double t, DuckingCurveParams params) {
    t = t.clamp(0.0, 1.0);

    switch (params.type) {
      case AdvancedDuckingCurve.linear:
        return t;

      case AdvancedDuckingCurve.exponential:
        // Fast start, slow finish
        return math.pow(t, params.power).toDouble();

      case AdvancedDuckingCurve.logarithmic:
        // Slow start, fast finish
        return 1.0 - math.pow(1.0 - t, params.power).toDouble();

      case AdvancedDuckingCurve.sCurve:
        // Smooth S-curve using sigmoid-like function
        return _sCurve(t, params.tension);

      case AdvancedDuckingCurve.custom:
        // Evaluate custom bezier curve
        return _evaluateCustomCurve(t, params.customPoints ?? []);
    }
  }

  /// Generate curve samples for visualization
  /// Returns list of (x, y) points normalized 0-1
  List<({double x, double y})> generateCurveSamples(
    DuckingCurveParams params, {
    int sampleCount = 50,
  }) {
    final samples = <({double x, double y})>[];
    for (int i = 0; i <= sampleCount; i++) {
      final t = i / sampleCount;
      samples.add((x: t, y: evaluate(t, params)));
    }
    return samples;
  }

  /// S-curve implementation using smoothstep variant
  double _sCurve(double t, double tension) {
    // Modified smoothstep with tension control
    final a = tension.clamp(0.5, 4.0);
    if (t < 0.5) {
      return math.pow(2 * t, a).toDouble() / 2;
    } else {
      return 1 - math.pow(2 * (1 - t), a).toDouble() / 2;
    }
  }

  /// Evaluate custom curve through control points
  double _evaluateCustomCurve(double t, List<CurveControlPoint> points) {
    if (points.isEmpty) return t;
    if (points.length == 1) return points.first.y;

    // Add implicit start and end points
    final allPoints = [
      const CurveControlPoint(x: 0, y: 0),
      ...points,
      const CurveControlPoint(x: 1, y: 1),
    ];

    // Find segment
    for (int i = 0; i < allPoints.length - 1; i++) {
      final p0 = allPoints[i];
      final p1 = allPoints[i + 1];

      if (t >= p0.x && t <= p1.x) {
        // Linear interpolation within segment
        final segmentT = (t - p0.x) / (p1.x - p0.x);
        return p0.y + (p1.y - p0.y) * segmentT;
      }
    }

    return t;
  }

  /// Convert legacy DuckingCurve to advanced params
  DuckingCurveParams fromLegacyCurve(DuckingCurve curve) {
    switch (curve) {
      case DuckingCurve.linear:
        return const DuckingCurveParams(type: AdvancedDuckingCurve.linear);
      case DuckingCurve.exponential:
        return const DuckingCurveParams(type: AdvancedDuckingCurve.exponential);
      case DuckingCurve.logarithmic:
        return const DuckingCurveParams(type: AdvancedDuckingCurve.logarithmic);
      case DuckingCurve.sCurve:
        return const DuckingCurveParams(type: AdvancedDuckingCurve.sCurve);
    }
  }

  /// Convert advanced params to legacy DuckingCurve (lossy)
  DuckingCurve toLegacyCurve(DuckingCurveParams params) {
    switch (params.type) {
      case AdvancedDuckingCurve.linear:
        return DuckingCurve.linear;
      case AdvancedDuckingCurve.exponential:
        return DuckingCurve.exponential;
      case AdvancedDuckingCurve.logarithmic:
        return DuckingCurve.logarithmic;
      case AdvancedDuckingCurve.sCurve:
      case AdvancedDuckingCurve.custom:
        return DuckingCurve.sCurve;
    }
  }

  /// Clear all stored params
  void clear() {
    _ruleParams.clear();
  }
}
