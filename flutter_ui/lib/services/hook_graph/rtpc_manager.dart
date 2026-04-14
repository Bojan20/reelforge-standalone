/// RTPCManager — Real-Time Parameter Control system for the Hook Graph.
///
/// Maps gameplay metrics (win multiplier, bet level, excitement, volatility)
/// to audio parameters (volume, filter cutoff, pitch, reverb send) via
/// configurable curves.
///
/// Wwise/FMOD parity: any game parameter can drive any audio parameter
/// through breakpoint curves with interpolation.

import 'dart:math' as math;

/// Interpolation type for RTPC curves
enum RTPCInterpolation {
  none,
  linear,
  logarithmic,
  sCurve,
  exponential,
}

/// A single breakpoint in an RTPC curve
class RTPCBreakpoint {
  final double x;
  final double y;
  const RTPCBreakpoint(this.x, this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory RTPCBreakpoint.fromJson(Map<String, dynamic> json) =>
      RTPCBreakpoint((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
}

/// An RTPC parameter definition
class RTPCParameter {
  final String id;
  final String displayName;
  final double minValue;
  final double maxValue;
  final double defaultValue;
  double _currentValue;
  double _targetValue;
  final double smoothingMs;

  RTPCParameter({
    required this.id,
    required this.displayName,
    this.minValue = 0.0,
    this.maxValue = 1.0,
    this.defaultValue = 0.0,
    this.smoothingMs = 50.0,
  })  : _currentValue = defaultValue,
        _targetValue = defaultValue;

  double get value => _currentValue;

  void setValue(double v) {
    _targetValue = v.clamp(minValue, maxValue);
  }

  void tick(double deltaMs) {
    if (smoothingMs <= 0 || (_currentValue - _targetValue).abs() < 0.0001) {
      _currentValue = _targetValue;
      return;
    }
    final alpha = (deltaMs / smoothingMs).clamp(0.0, 1.0);
    _currentValue += (_targetValue - _currentValue) * alpha;
  }

  double get normalized => maxValue > minValue
      ? (_currentValue - minValue) / (maxValue - minValue)
      : 0.0;
}

/// Binding: RTPC parameter → audio target via curve
class RTPCBinding {
  final String rtpcId;
  final String targetNodeId;
  final String targetParamName;
  final List<RTPCBreakpoint> curve;
  final RTPCInterpolation interpolation;

  const RTPCBinding({
    required this.rtpcId,
    required this.targetNodeId,
    required this.targetParamName,
    required this.curve,
    this.interpolation = RTPCInterpolation.linear,
  });

  double evaluate(double normalizedInput) {
    if (curve.isEmpty) return 0.0;
    if (curve.length == 1) return curve.first.y;

    final x = normalizedInput.clamp(curve.first.x, curve.last.x);

    // Find segment
    for (int i = 0; i < curve.length - 1; i++) {
      if (x >= curve[i].x && x <= curve[i + 1].x) {
        final t = (curve[i + 1].x - curve[i].x) > 0.0001
            ? (x - curve[i].x) / (curve[i + 1].x - curve[i].x)
            : 0.0;
        final y0 = curve[i].y;
        final y1 = curve[i + 1].y;

        return switch (interpolation) {
          RTPCInterpolation.none => y0,
          RTPCInterpolation.linear => y0 + (y1 - y0) * t,
          RTPCInterpolation.logarithmic => y0 + (y1 - y0) * math.log(1 + t * 9) / math.log(10),
          RTPCInterpolation.exponential => y0 + (y1 - y0) * (math.pow(10, t) - 1) / 9,
          RTPCInterpolation.sCurve => y0 + (y1 - y0) * (0.5 - 0.5 * math.cos(t * math.pi)),
        };
      }
    }
    return curve.last.y;
  }

  Map<String, dynamic> toJson() => {
        'rtpc': rtpcId,
        'target': targetNodeId,
        'param': targetParamName,
        'curve': curve.map((b) => b.toJson()).toList(),
        'interpolation': interpolation.name,
      };
}

/// The RTPC Manager — central parameter system
class RTPCManager {
  final Map<String, RTPCParameter> _parameters = {};
  final List<RTPCBinding> _bindings = [];
  DateTime _lastTick = DateTime.now();

  // ═══ BUILT-IN SLOT GAME PARAMETERS ═══
  static const slotGameParameters = [
    ('win_ratio', 'Win Ratio', 0.0, 100.0, 0.0),
    ('bet_level', 'Bet Level', 0.0, 1.0, 0.5),
    ('excitement', 'Excitement', 0.0, 1.0, 0.0),
    ('volatility', 'Volatility', 0.0, 1.0, 0.5),
    ('spin_speed', 'Spin Speed', 0.5, 3.0, 1.0),
    ('cascade_depth', 'Cascade Depth', 0.0, 20.0, 0.0),
    ('feature_proximity', 'Feature Proximity', 0.0, 1.0, 0.0),
    ('session_duration', 'Session Duration', 0.0, 3600.0, 0.0),
  ];

  RTPCManager() {
    _registerBuiltins();
  }

  void _registerBuiltins() {
    for (final (id, name, min, max, def) in slotGameParameters) {
      registerParameter(RTPCParameter(
        id: id,
        displayName: name,
        minValue: min,
        maxValue: max,
        defaultValue: def,
      ));
    }
  }

  void registerParameter(RTPCParameter param) {
    _parameters[param.id] = param;
  }

  void addBinding(RTPCBinding binding) {
    _bindings.add(binding);
  }

  void removeBindingsForNode(String nodeId) {
    _bindings.removeWhere((b) => b.targetNodeId == nodeId);
  }

  void setValue(String paramId, double value) {
    _parameters[paramId]?.setValue(value);
  }

  double getValue(String paramId) {
    return _parameters[paramId]?.value ?? 0.0;
  }

  double getNormalized(String paramId) {
    return _parameters[paramId]?.normalized ?? 0.0;
  }

  /// Tick all parameters and evaluate bindings.
  /// Returns list of (nodeId, paramName, value) changes to apply.
  List<(String, String, double)> tick() {
    final now = DateTime.now();
    final deltaMs = now.difference(_lastTick).inMicroseconds / 1000.0;
    _lastTick = now;

    for (final param in _parameters.values) {
      param.tick(deltaMs);
    }

    final changes = <(String, String, double)>[];
    for (final binding in _bindings) {
      final param = _parameters[binding.rtpcId];
      if (param == null) continue;

      final output = binding.evaluate(param.normalized);
      changes.add((binding.targetNodeId, binding.targetParamName, output));
    }
    return changes;
  }

  Map<String, double> get allValues =>
      Map.fromEntries(_parameters.entries.map((e) => MapEntry(e.key, e.value.value)));

  List<RTPCParameter> get parameters => _parameters.values.toList();

  int get bindingCount => _bindings.length;
}
