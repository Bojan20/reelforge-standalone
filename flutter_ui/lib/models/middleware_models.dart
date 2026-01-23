// Middleware Models
//
// Data models for Wwise/FMOD-style middleware:
// - MiddlewareAction: Individual action in an event
// - MiddlewareEvent: Event with list of actions
// - All Wwise/FMOD action types, buses, scopes, etc.

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Action Type enum (Wwise/FMOD standard actions)
enum ActionType {
  play,
  playAndContinue,
  stop,
  stopAll,
  pause,
  pauseAll,
  resume,
  resumeAll,
  break_,
  mute,
  unmute,
  setVolume,
  setPitch,
  setLPF,
  setHPF,
  setBusVolume,
  setState,
  setSwitch,
  setRTPC,
  resetRTPC,
  seek,
  trigger,
  postEvent,
}

extension ActionTypeExtension on ActionType {
  String get displayName {
    switch (this) {
      case ActionType.play: return 'Play';
      case ActionType.playAndContinue: return 'PlayAndContinue';
      case ActionType.stop: return 'Stop';
      case ActionType.stopAll: return 'StopAll';
      case ActionType.pause: return 'Pause';
      case ActionType.pauseAll: return 'PauseAll';
      case ActionType.resume: return 'Resume';
      case ActionType.resumeAll: return 'ResumeAll';
      case ActionType.break_: return 'Break';
      case ActionType.mute: return 'Mute';
      case ActionType.unmute: return 'Unmute';
      case ActionType.setVolume: return 'SetVolume';
      case ActionType.setPitch: return 'SetPitch';
      case ActionType.setLPF: return 'SetLPF';
      case ActionType.setHPF: return 'SetHPF';
      case ActionType.setBusVolume: return 'SetBusVolume';
      case ActionType.setState: return 'SetState';
      case ActionType.setSwitch: return 'SetSwitch';
      case ActionType.setRTPC: return 'SetRTPC';
      case ActionType.resetRTPC: return 'ResetRTPC';
      case ActionType.seek: return 'Seek';
      case ActionType.trigger: return 'Trigger';
      case ActionType.postEvent: return 'PostEvent';
    }
  }

  static ActionType fromString(String s) {
    switch (s) {
      case 'Play': return ActionType.play;
      case 'PlayAndContinue': return ActionType.playAndContinue;
      case 'Stop': return ActionType.stop;
      case 'StopAll': return ActionType.stopAll;
      case 'Pause': return ActionType.pause;
      case 'PauseAll': return ActionType.pauseAll;
      case 'Resume': return ActionType.resume;
      case 'ResumeAll': return ActionType.resumeAll;
      case 'Break': return ActionType.break_;
      case 'Mute': return ActionType.mute;
      case 'Unmute': return ActionType.unmute;
      case 'SetVolume': return ActionType.setVolume;
      case 'SetPitch': return ActionType.setPitch;
      case 'SetLPF': return ActionType.setLPF;
      case 'SetHPF': return ActionType.setHPF;
      case 'SetBusVolume': return ActionType.setBusVolume;
      case 'SetState': return ActionType.setState;
      case 'SetSwitch': return ActionType.setSwitch;
      case 'SetRTPC': return ActionType.setRTPC;
      case 'ResetRTPC': return ActionType.resetRTPC;
      case 'Seek': return ActionType.seek;
      case 'Trigger': return ActionType.trigger;
      case 'PostEvent': return ActionType.postEvent;
      default: return ActionType.play;
    }
  }
}

/// Scope enum
enum ActionScope {
  global,
  gameObject,
  emitter,
  all,
  firstOnly,
  random,
}

extension ActionScopeExtension on ActionScope {
  String get displayName {
    switch (this) {
      case ActionScope.global: return 'Global';
      case ActionScope.gameObject: return 'Game Object';
      case ActionScope.emitter: return 'Emitter';
      case ActionScope.all: return 'All';
      case ActionScope.firstOnly: return 'First Only';
      case ActionScope.random: return 'Random';
    }
  }

  static ActionScope fromString(String s) {
    switch (s) {
      case 'Global': return ActionScope.global;
      case 'Game Object': return ActionScope.gameObject;
      case 'Emitter': return ActionScope.emitter;
      case 'All': return ActionScope.all;
      case 'First Only': return ActionScope.firstOnly;
      case 'Random': return ActionScope.random;
      default: return ActionScope.global;
    }
  }
}

/// Priority enum
enum ActionPriority {
  highest,
  high,
  aboveNormal,
  normal,
  belowNormal,
  low,
  lowest,
}

extension ActionPriorityExtension on ActionPriority {
  String get displayName {
    switch (this) {
      case ActionPriority.highest: return 'Highest';
      case ActionPriority.high: return 'High';
      case ActionPriority.aboveNormal: return 'Above Normal';
      case ActionPriority.normal: return 'Normal';
      case ActionPriority.belowNormal: return 'Below Normal';
      case ActionPriority.low: return 'Low';
      case ActionPriority.lowest: return 'Lowest';
    }
  }

  static ActionPriority fromString(String s) {
    switch (s) {
      case 'Highest': return ActionPriority.highest;
      case 'High': return ActionPriority.high;
      case 'Above Normal': return ActionPriority.aboveNormal;
      case 'Normal': return ActionPriority.normal;
      case 'Below Normal': return ActionPriority.belowNormal;
      case 'Low': return ActionPriority.low;
      case 'Lowest': return ActionPriority.lowest;
      default: return ActionPriority.normal;
    }
  }
}

/// Fade curve type
enum FadeCurve {
  linear,
  log3,
  sine,
  log1,
  invSCurve,
  sCurve,
  exp1,
  exp3,
}

extension FadeCurveExtension on FadeCurve {
  String get displayName {
    switch (this) {
      case FadeCurve.linear: return 'Linear';
      case FadeCurve.log3: return 'Log3';
      case FadeCurve.sine: return 'Sine';
      case FadeCurve.log1: return 'Log1';
      case FadeCurve.invSCurve: return 'InvSCurve';
      case FadeCurve.sCurve: return 'SCurve';
      case FadeCurve.exp1: return 'Exp1';
      case FadeCurve.exp3: return 'Exp3';
    }
  }

  static FadeCurve fromString(String s) {
    switch (s) {
      case 'Linear': return FadeCurve.linear;
      case 'Log3': return FadeCurve.log3;
      case 'Sine': return FadeCurve.sine;
      case 'Log1': return FadeCurve.log1;
      case 'InvSCurve': return FadeCurve.invSCurve;
      case 'SCurve': return FadeCurve.sCurve;
      case 'Exp1': return FadeCurve.exp1;
      case 'Exp3': return FadeCurve.exp3;
      default: return FadeCurve.linear;
    }
  }
}

/// Individual middleware action
class MiddlewareAction {
  final String id;
  final ActionType type;
  final String assetId;
  final String bus;
  final ActionScope scope;
  final ActionPriority priority;
  final FadeCurve fadeCurve;
  final double fadeTime; // in seconds
  final double gain; // 0.0 - 1.0 (multiplier)
  final double delay; // in seconds
  final bool loop;
  final bool selected;

  const MiddlewareAction({
    required this.id,
    this.type = ActionType.play,
    this.assetId = '',
    this.bus = 'Master',
    this.scope = ActionScope.global,
    this.priority = ActionPriority.normal,
    this.fadeCurve = FadeCurve.linear,
    this.fadeTime = 0.1,
    this.gain = 1.0,
    this.delay = 0.0,
    this.loop = false,
    this.selected = false,
  });

  MiddlewareAction copyWith({
    String? id,
    ActionType? type,
    String? assetId,
    String? bus,
    ActionScope? scope,
    ActionPriority? priority,
    FadeCurve? fadeCurve,
    double? fadeTime,
    double? gain,
    double? delay,
    bool? loop,
    bool? selected,
  }) {
    return MiddlewareAction(
      id: id ?? this.id,
      type: type ?? this.type,
      assetId: assetId ?? this.assetId,
      bus: bus ?? this.bus,
      scope: scope ?? this.scope,
      priority: priority ?? this.priority,
      fadeCurve: fadeCurve ?? this.fadeCurve,
      fadeTime: fadeTime ?? this.fadeTime,
      gain: gain ?? this.gain,
      delay: delay ?? this.delay,
      loop: loop ?? this.loop,
      selected: selected ?? this.selected,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.displayName,
    'assetId': assetId,
    'bus': bus,
    'scope': scope.displayName,
    'priority': priority.displayName,
    'fadeCurve': fadeCurve.displayName,
    'fadeTime': fadeTime,
    'gain': gain,
    'delay': delay,
    'loop': loop,
  };

  factory MiddlewareAction.fromJson(Map<String, dynamic> json) {
    return MiddlewareAction(
      id: json['id'] as String? ?? UniqueKey().toString(),
      type: ActionTypeExtension.fromString(json['type'] as String? ?? 'Play'),
      assetId: json['assetId'] as String? ?? '',
      bus: json['bus'] as String? ?? 'Master',
      scope: ActionScopeExtension.fromString(json['scope'] as String? ?? 'Global'),
      priority: ActionPriorityExtension.fromString(json['priority'] as String? ?? 'Normal'),
      fadeCurve: FadeCurveExtension.fromString(json['fadeCurve'] as String? ?? 'Linear'),
      fadeTime: (json['fadeTime'] as num?)?.toDouble() ?? 0.1,
      gain: (json['gain'] as num?)?.toDouble() ?? 1.0,
      delay: (json['delay'] as num?)?.toDouble() ?? 0.0,
      loop: json['loop'] as bool? ?? false,
    );
  }
}

/// Middleware event containing actions
class MiddlewareEvent {
  final String id;
  final String name;
  final String category;
  final List<MiddlewareAction> actions;
  final bool expanded;

  const MiddlewareEvent({
    required this.id,
    required this.name,
    this.category = 'General',
    this.actions = const [],
    this.expanded = true,
  });

  MiddlewareEvent copyWith({
    String? id,
    String? name,
    String? category,
    List<MiddlewareAction>? actions,
    bool? expanded,
  }) {
    return MiddlewareEvent(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      actions: actions ?? this.actions,
      expanded: expanded ?? this.expanded,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'actions': actions.map((a) => a.toJson()).toList(),
  };

  factory MiddlewareEvent.fromJson(Map<String, dynamic> json) {
    return MiddlewareEvent(
      id: json['id'] as String? ?? UniqueKey().toString(),
      name: json['name'] as String? ?? 'Unnamed Event',
      category: json['category'] as String? ?? 'General',
      actions: (json['actions'] as List<dynamic>?)
          ?.map((a) => MiddlewareAction.fromJson(a as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
}

// ============ Static Constants ============

/// All available buses
const List<String> kAllBuses = [
  'Master', 'Music', 'SFX', 'Voice', 'UI', 'Ambience', 'Reels', 'Wins', 'VO',
];

/// All available asset IDs - empty by default, populated from actual imported sounds
/// User imports sounds via Slot Lab, they appear here automatically
const List<String> kAllAssetIds = [
  '—', // Empty placeholder - actual sounds come from events
];

/// All available events
const List<String> kAllEvents = [
  'Play_Music', 'Stop_Music', 'Play_SFX', 'Stop_All', 'Pause_All',
  'Set_State', 'Trigger_Win', 'Spin_Start', 'Spin_Stop', 'Reel_Land',
  'BigWin_Start', 'BigWin_Loop', 'BigWin_End', 'Bonus_Enter', 'Bonus_Exit',
  'UI_Click', 'UI_Hover', 'Ambient_Start', 'Ambient_Stop', 'VO_Play',
];

/// State groups (Wwise-style)
const Map<String, List<String>> kStateGroups = {
  'GameState': ['Menu', 'BaseGame', 'Bonus', 'FreeSpins', 'Paused'],
  'MusicState': ['Normal', 'Suspense', 'Action', 'Victory', 'Defeat'],
  'PlayerState': ['Idle', 'Spinning', 'Winning', 'Waiting'],
  'BonusState': ['None', 'Triggered', 'Active', 'Ending'],
  'Intensity': ['Low', 'Medium', 'High', 'Extreme'],
};

/// Switch groups
const List<String> kSwitchGroups = [
  'Surface', 'Footsteps', 'Material', 'Weapon', 'Environment',
];

// ============ State Group Model ============

/// RTPC Curve shape for interpolation
enum RtpcCurveShape {
  linear,
  log3,
  sine,
  log1,
  invSCurve,
  sCurve,
  exp1,
  exp3,
  constant,
}

extension RtpcCurveShapeExtension on RtpcCurveShape {
  String get displayName {
    switch (this) {
      case RtpcCurveShape.linear: return 'Linear';
      case RtpcCurveShape.log3: return 'Log3 (Fast→Slow)';
      case RtpcCurveShape.sine: return 'Sine (S-Ease)';
      case RtpcCurveShape.log1: return 'Log1 (Gentle)';
      case RtpcCurveShape.invSCurve: return 'Inv S-Curve';
      case RtpcCurveShape.sCurve: return 'S-Curve';
      case RtpcCurveShape.exp1: return 'Exp1 (Slow→Fast)';
      case RtpcCurveShape.exp3: return 'Exp3 (Sharp)';
      case RtpcCurveShape.constant: return 'Constant (Step)';
    }
  }

  int get index => RtpcCurveShape.values.indexOf(this);

  static RtpcCurveShape fromIndex(int idx) {
    if (idx < 0 || idx >= RtpcCurveShape.values.length) return RtpcCurveShape.linear;
    return RtpcCurveShape.values[idx];
  }
}

/// State within a StateGroup
class StateDefinition {
  final int id;
  final String name;

  const StateDefinition({required this.id, required this.name});

  StateDefinition copyWith({int? id, String? name}) {
    return StateDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory StateDefinition.fromJson(Map<String, dynamic> json) {
    return StateDefinition(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
    );
  }
}

/// State Group — Global state affecting sound behavior
/// Only one state can be active per group at a time
class StateGroup {
  final int id;
  final String name;
  final List<StateDefinition> states;
  final int currentStateId;
  final int defaultStateId;
  final double transitionTimeSecs;

  const StateGroup({
    required this.id,
    required this.name,
    this.states = const [],
    this.currentStateId = 0,
    this.defaultStateId = 0,
    this.transitionTimeSecs = 0.0,
  });

  /// Get current state name
  String get currentStateName {
    final state = states.where((s) => s.id == currentStateId).firstOrNull;
    return state?.name ?? 'None';
  }

  /// Get state name by ID
  String? stateName(int stateId) {
    return states.where((s) => s.id == stateId).firstOrNull?.name;
  }

  StateGroup copyWith({
    int? id,
    String? name,
    List<StateDefinition>? states,
    int? currentStateId,
    int? defaultStateId,
    double? transitionTimeSecs,
  }) {
    return StateGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      states: states ?? this.states,
      currentStateId: currentStateId ?? this.currentStateId,
      defaultStateId: defaultStateId ?? this.defaultStateId,
      transitionTimeSecs: transitionTimeSecs ?? this.transitionTimeSecs,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'states': states.map((s) => s.toJson()).toList(),
    'currentStateId': currentStateId,
    'defaultStateId': defaultStateId,
    'transitionTimeSecs': transitionTimeSecs,
  };

  factory StateGroup.fromJson(Map<String, dynamic> json) {
    return StateGroup(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      states: (json['states'] as List<dynamic>?)
          ?.map((s) => StateDefinition.fromJson(s as Map<String, dynamic>))
          .toList() ?? [],
      currentStateId: json['currentStateId'] as int? ?? 0,
      defaultStateId: json['defaultStateId'] as int? ?? 0,
      transitionTimeSecs: (json['transitionTimeSecs'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// ============ Switch Group Model ============

/// Switch within a SwitchGroup
class SwitchDefinition {
  final int id;
  final String name;

  const SwitchDefinition({required this.id, required this.name});

  SwitchDefinition copyWith({int? id, String? name}) {
    return SwitchDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory SwitchDefinition.fromJson(Map<String, dynamic> json) {
    return SwitchDefinition(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
    );
  }
}

/// Switch Group — Per-game-object value controlling sound variants
/// Each game object can have a different switch value
class SwitchGroup {
  final int id;
  final String name;
  final List<SwitchDefinition> switches;
  final int defaultSwitchId;

  const SwitchGroup({
    required this.id,
    required this.name,
    this.switches = const [],
    this.defaultSwitchId = 0,
  });

  /// Get switch name by ID
  String? switchName(int switchId) {
    return switches.where((s) => s.id == switchId).firstOrNull?.name;
  }

  SwitchGroup copyWith({
    int? id,
    String? name,
    List<SwitchDefinition>? switches,
    int? defaultSwitchId,
  }) {
    return SwitchGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      switches: switches ?? this.switches,
      defaultSwitchId: defaultSwitchId ?? this.defaultSwitchId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'switches': switches.map((s) => s.toJson()).toList(),
    'defaultSwitchId': defaultSwitchId,
  };

  factory SwitchGroup.fromJson(Map<String, dynamic> json) {
    return SwitchGroup(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      switches: (json['switches'] as List<dynamic>?)
          ?.map((s) => SwitchDefinition.fromJson(s as Map<String, dynamic>))
          .toList() ?? [],
      defaultSwitchId: json['defaultSwitchId'] as int? ?? 0,
    );
  }
}

// ============ RTPC Model ============

/// RTPC Curve Point
class RtpcCurvePoint {
  final double x; // Input value
  final double y; // Output value
  final RtpcCurveShape shape; // Interpolation to next point

  const RtpcCurvePoint({
    required this.x,
    required this.y,
    this.shape = RtpcCurveShape.linear,
  });

  RtpcCurvePoint copyWith({double? x, double? y, RtpcCurveShape? shape}) {
    return RtpcCurvePoint(
      x: x ?? this.x,
      y: y ?? this.y,
      shape: shape ?? this.shape,
    );
  }

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'shape': shape.index,
  };

  factory RtpcCurvePoint.fromJson(Map<String, dynamic> json) {
    return RtpcCurvePoint(
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      shape: RtpcCurveShapeExtension.fromIndex(json['shape'] as int? ?? 0),
    );
  }
}

/// RTPC Curve — Maps input to output with multi-point interpolation
class RtpcCurve {
  final List<RtpcCurvePoint> points;

  const RtpcCurve({this.points = const []});

  /// Evaluate curve at given x value
  double evaluate(double x) {
    if (points.isEmpty) return x;
    if (points.length == 1) return points.first.y;

    // Clamp to curve bounds
    if (x <= points.first.x) return points.first.y;
    if (x >= points.last.x) return points.last.y;

    // Find segment
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];

      if (x >= p0.x && x <= p1.x) {
        final t = (x - p0.x) / (p1.x - p0.x);
        return _interpolate(p0.y, p1.y, t, p0.shape);
      }
    }

    return points.last.y;
  }

  double _interpolate(double y0, double y1, double t, RtpcCurveShape shape) {
    final shaped = _applyShape(t, shape);
    return y0 + (y1 - y0) * shaped;
  }

  double _applyShape(double t, RtpcCurveShape shape) {
    switch (shape) {
      case RtpcCurveShape.linear:
        return t;
      case RtpcCurveShape.log3:
        return 1.0 - math.pow(1.0 - t, 3).toDouble();
      case RtpcCurveShape.sine:
        return 0.5 - 0.5 * math.cos(t * math.pi);
      case RtpcCurveShape.log1:
        return 1.0 - math.pow(1.0 - t, 2).toDouble();
      case RtpcCurveShape.invSCurve:
        return t < 0.5
            ? 0.5 * math.pow(2 * t, 2).toDouble()
            : 1.0 - 0.5 * math.pow(2 * (1 - t), 2).toDouble();
      case RtpcCurveShape.sCurve:
        return t < 0.5
            ? 2 * t * t
            : 1 - 2 * (1 - t) * (1 - t);
      case RtpcCurveShape.exp1:
        return t * t;
      case RtpcCurveShape.exp3:
        return t * t * t;
      case RtpcCurveShape.constant:
        return 0.0; // Jump at end
    }
  }

  RtpcCurve copyWith({List<RtpcCurvePoint>? points}) {
    return RtpcCurve(points: points ?? this.points);
  }

  Map<String, dynamic> toJson() => {
    'points': points.map((p) => p.toJson()).toList(),
  };

  factory RtpcCurve.fromJson(Map<String, dynamic> json) {
    return RtpcCurve(
      points: (json['points'] as List<dynamic>?)
          ?.map((p) => RtpcCurvePoint.fromJson(p as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  /// Create default linear curve
  factory RtpcCurve.linear(double minIn, double maxIn, double minOut, double maxOut) {
    return RtpcCurve(points: [
      RtpcCurvePoint(x: minIn, y: minOut),
      RtpcCurvePoint(x: maxIn, y: maxOut),
    ]);
  }
}

/// RTPC Interpolation mode
enum RtpcInterpolation {
  none,
  slewRate,
  filterCoeff,
}

/// RTPC Definition — Continuously variable parameter
class RtpcDefinition {
  final int id;
  final String name;
  final double min;
  final double max;
  final double defaultValue;
  final double currentValue;
  final RtpcInterpolation interpolation;
  final double slewRate; // Units per second
  final RtpcCurve? curve; // Optional mapping curve

  const RtpcDefinition({
    required this.id,
    required this.name,
    this.min = 0.0,
    this.max = 100.0,
    this.defaultValue = 0.0,
    this.currentValue = 0.0,
    this.interpolation = RtpcInterpolation.slewRate,
    this.slewRate = 100.0,
    this.curve,
  });

  /// Get normalized value (0-1)
  double get normalizedValue {
    if (max == min) return 0.0;
    return (currentValue - min) / (max - min);
  }

  /// Clamp value to range
  double clamp(double value) {
    return value.clamp(min, max);
  }

  RtpcDefinition copyWith({
    int? id,
    String? name,
    double? min,
    double? max,
    double? defaultValue,
    double? currentValue,
    RtpcInterpolation? interpolation,
    double? slewRate,
    RtpcCurve? curve,
  }) {
    return RtpcDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      min: min ?? this.min,
      max: max ?? this.max,
      defaultValue: defaultValue ?? this.defaultValue,
      currentValue: currentValue ?? this.currentValue,
      interpolation: interpolation ?? this.interpolation,
      slewRate: slewRate ?? this.slewRate,
      curve: curve ?? this.curve,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'min': min,
    'max': max,
    'defaultValue': defaultValue,
    'currentValue': currentValue,
    'interpolation': interpolation.index,
    'slewRate': slewRate,
    'curve': curve?.toJson(),
  };

  factory RtpcDefinition.fromJson(Map<String, dynamic> json) {
    return RtpcDefinition(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      min: (json['min'] as num?)?.toDouble() ?? 0.0,
      max: (json['max'] as num?)?.toDouble() ?? 100.0,
      defaultValue: (json['defaultValue'] as num?)?.toDouble() ?? 0.0,
      currentValue: (json['currentValue'] as num?)?.toDouble() ?? 0.0,
      interpolation: RtpcInterpolation.values[json['interpolation'] as int? ?? 0],
      slewRate: (json['slewRate'] as num?)?.toDouble() ?? 100.0,
      curve: json['curve'] != null
          ? RtpcCurve.fromJson(json['curve'] as Map<String, dynamic>)
          : null,
    );
  }
}

// ============ RTPC Parameter Binding ============

/// Target parameter type for RTPC binding
enum RtpcTargetParameter {
  volume,
  pitch,
  lowPassFilter,
  highPassFilter,
  pan,
  busVolume,
  reverbSend,
  delaySend,
  width,
  playbackRate,
}

extension RtpcTargetParameterExtension on RtpcTargetParameter {
  String get displayName {
    switch (this) {
      case RtpcTargetParameter.volume: return 'Volume';
      case RtpcTargetParameter.pitch: return 'Pitch';
      case RtpcTargetParameter.lowPassFilter: return 'Low-Pass Filter';
      case RtpcTargetParameter.highPassFilter: return 'High-Pass Filter';
      case RtpcTargetParameter.pan: return 'Pan';
      case RtpcTargetParameter.busVolume: return 'Bus Volume';
      case RtpcTargetParameter.reverbSend: return 'Reverb Send';
      case RtpcTargetParameter.delaySend: return 'Delay Send';
      case RtpcTargetParameter.width: return 'Width';
      case RtpcTargetParameter.playbackRate: return 'Playback Rate';
    }
  }

  /// Get default output range for this parameter type
  (double min, double max) get defaultRange {
    switch (this) {
      case RtpcTargetParameter.volume: return (0.0, 2.0);
      case RtpcTargetParameter.pitch: return (-24.0, 24.0);
      case RtpcTargetParameter.lowPassFilter: return (20.0, 20000.0);
      case RtpcTargetParameter.highPassFilter: return (20.0, 20000.0);
      case RtpcTargetParameter.pan: return (-1.0, 1.0);
      case RtpcTargetParameter.busVolume: return (0.0, 2.0);
      case RtpcTargetParameter.reverbSend: return (0.0, 1.0);
      case RtpcTargetParameter.delaySend: return (0.0, 1.0);
      case RtpcTargetParameter.width: return (0.0, 1.0);
      case RtpcTargetParameter.playbackRate: return (0.5, 2.0);
    }
  }

  int get index => RtpcTargetParameter.values.indexOf(this);

  static RtpcTargetParameter fromIndex(int idx) {
    if (idx < 0 || idx >= RtpcTargetParameter.values.length) return RtpcTargetParameter.volume;
    return RtpcTargetParameter.values[idx];
  }
}

/// RTPC binding - connects RTPC to a target parameter via curve
class RtpcBinding {
  final int id;
  final int rtpcId;
  final RtpcTargetParameter target;
  final int? targetBusId;
  final int? targetEventId;
  final RtpcCurve curve;
  final bool enabled;

  const RtpcBinding({
    required this.id,
    required this.rtpcId,
    required this.target,
    this.targetBusId,
    this.targetEventId,
    required this.curve,
    this.enabled = true,
  });

  /// Evaluate binding - get output parameter value for given RTPC value
  double evaluate(double rtpcValue) {
    if (!enabled) {
      final range = target.defaultRange;
      return (range.$1 + range.$2) / 2.0;
    }
    return curve.evaluate(rtpcValue);
  }

  RtpcBinding copyWith({
    int? id,
    int? rtpcId,
    RtpcTargetParameter? target,
    int? targetBusId,
    int? targetEventId,
    RtpcCurve? curve,
    bool? enabled,
  }) {
    return RtpcBinding(
      id: id ?? this.id,
      rtpcId: rtpcId ?? this.rtpcId,
      target: target ?? this.target,
      targetBusId: targetBusId ?? this.targetBusId,
      targetEventId: targetEventId ?? this.targetEventId,
      curve: curve ?? this.curve,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'rtpcId': rtpcId,
    'target': target.index,
    'targetBusId': targetBusId,
    'targetEventId': targetEventId,
    'curve': curve.toJson(),
    'enabled': enabled,
  };

  factory RtpcBinding.fromJson(Map<String, dynamic> json) {
    return RtpcBinding(
      id: json['id'] as int? ?? 0,
      rtpcId: json['rtpcId'] as int? ?? 0,
      target: RtpcTargetParameterExtension.fromIndex(json['target'] as int? ?? 0),
      targetBusId: json['targetBusId'] as int?,
      targetEventId: json['targetEventId'] as int?,
      curve: RtpcCurve.fromJson(json['curve'] as Map<String, dynamic>),
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  /// Create default binding with linear curve
  factory RtpcBinding.linear(int id, int rtpcId, RtpcTargetParameter target) {
    final range = target.defaultRange;
    return RtpcBinding(
      id: id,
      rtpcId: rtpcId,
      target: target,
      curve: RtpcCurve.linear(0.0, 1.0, range.$1, range.$2),
    );
  }

  /// Create binding for specific bus
  factory RtpcBinding.forBus(int id, int rtpcId, RtpcTargetParameter target, int busId) {
    final range = target.defaultRange;
    return RtpcBinding(
      id: id,
      rtpcId: rtpcId,
      target: target,
      targetBusId: busId,
      curve: RtpcCurve.linear(0.0, 1.0, range.$1, range.$2),
    );
  }
}

// ============ P3.10: RTPC Macro System ============

/// RTPC Macro - Groups multiple RTPC bindings under one control
/// P3.10: Allows designers to control multiple parameters with a single knob
class RtpcMacro {
  final int id;
  final String name;
  final String description;
  final double min;
  final double max;
  final double currentValue;

  /// Bindings controlled by this macro
  /// Each binding maps macro value → target parameter
  final List<RtpcMacroBinding> bindings;

  /// UI color for visual grouping
  final Color color;

  /// Enable/disable entire macro
  final bool enabled;

  const RtpcMacro({
    required this.id,
    required this.name,
    this.description = '',
    this.min = 0.0,
    this.max = 1.0,
    this.currentValue = 0.5,
    this.bindings = const [],
    this.color = const Color(0xFF4A9EFF),
    this.enabled = true,
  });

  /// Get normalized value (0-1)
  double get normalizedValue {
    if (max == min) return 0.0;
    return (currentValue - min) / (max - min);
  }

  /// Apply macro value to all bindings
  Map<RtpcTargetParameter, double> evaluate() {
    if (!enabled) return {};

    final normalized = normalizedValue;
    final results = <RtpcTargetParameter, double>{};

    for (final binding in bindings) {
      if (binding.enabled) {
        results[binding.target] = binding.evaluate(normalized);
      }
    }

    return results;
  }

  RtpcMacro copyWith({
    int? id,
    String? name,
    String? description,
    double? min,
    double? max,
    double? currentValue,
    List<RtpcMacroBinding>? bindings,
    Color? color,
    bool? enabled,
  }) {
    return RtpcMacro(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      min: min ?? this.min,
      max: max ?? this.max,
      currentValue: currentValue ?? this.currentValue,
      bindings: bindings ?? this.bindings,
      color: color ?? this.color,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'min': min,
        'max': max,
        'currentValue': currentValue,
        'bindings': bindings.map((b) => b.toJson()).toList(),
        'color': color.value,
        'enabled': enabled,
      };

  factory RtpcMacro.fromJson(Map<String, dynamic> json) {
    return RtpcMacro(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      min: (json['min'] as num?)?.toDouble() ?? 0.0,
      max: (json['max'] as num?)?.toDouble() ?? 1.0,
      currentValue: (json['currentValue'] as num?)?.toDouble() ?? 0.5,
      bindings: (json['bindings'] as List<dynamic>?)
              ?.map((b) => RtpcMacroBinding.fromJson(b as Map<String, dynamic>))
              .toList() ??
          [],
      color: Color(json['color'] as int? ?? 0xFF4A9EFF),
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

/// Single binding within an RTPC Macro
class RtpcMacroBinding {
  final int id;
  final RtpcTargetParameter target;
  final int? targetBusId;
  final int? targetEventId;

  /// Curve mapping: macro normalized value → target parameter value
  final RtpcCurve curve;

  /// Invert the curve
  final bool inverted;

  final bool enabled;

  const RtpcMacroBinding({
    required this.id,
    required this.target,
    this.targetBusId,
    this.targetEventId,
    required this.curve,
    this.inverted = false,
    this.enabled = true,
  });

  /// Evaluate binding - get output for normalized macro value (0-1)
  double evaluate(double normalizedMacroValue) {
    if (!enabled) {
      final range = target.defaultRange;
      return (range.$1 + range.$2) / 2.0;
    }

    final inputValue = inverted ? (1.0 - normalizedMacroValue) : normalizedMacroValue;
    return curve.evaluate(inputValue);
  }

  RtpcMacroBinding copyWith({
    int? id,
    RtpcTargetParameter? target,
    int? targetBusId,
    int? targetEventId,
    RtpcCurve? curve,
    bool? inverted,
    bool? enabled,
  }) {
    return RtpcMacroBinding(
      id: id ?? this.id,
      target: target ?? this.target,
      targetBusId: targetBusId ?? this.targetBusId,
      targetEventId: targetEventId ?? this.targetEventId,
      curve: curve ?? this.curve,
      inverted: inverted ?? this.inverted,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'target': target.index,
        'targetBusId': targetBusId,
        'targetEventId': targetEventId,
        'curve': curve.toJson(),
        'inverted': inverted,
        'enabled': enabled,
      };

  factory RtpcMacroBinding.fromJson(Map<String, dynamic> json) {
    return RtpcMacroBinding(
      id: json['id'] as int? ?? 0,
      target: RtpcTargetParameterExtension.fromIndex(json['target'] as int? ?? 0),
      targetBusId: json['targetBusId'] as int?,
      targetEventId: json['targetEventId'] as int?,
      curve: RtpcCurve.fromJson(json['curve'] as Map<String, dynamic>),
      inverted: json['inverted'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

/// Preset macros for common audio scenarios
const List<Map<String, dynamic>> kPresetMacros = [
  {
    'name': 'Big Win Intensity',
    'description': 'Controls celebration audio intensity (volume, reverb, pitch)',
    'bindings': [
      {'target': 'volume', 'range': [0.7, 1.0]},
      {'target': 'reverbSend', 'range': [0.1, 0.6]},
      {'target': 'pitch', 'range': [0.0, 0.5]},
    ],
  },
  {
    'name': 'Tension Builder',
    'description': 'Builds tension (LPF closes, pitch rises)',
    'bindings': [
      {'target': 'lowPassFilter', 'range': [20000, 2000], 'inverted': true},
      {'target': 'pitch', 'range': [0.0, 1.0]},
    ],
  },
  {
    'name': 'Distance Attenuation',
    'description': 'Simulates distance (volume, LPF, reverb)',
    'bindings': [
      {'target': 'volume', 'range': [1.0, 0.0], 'inverted': true},
      {'target': 'lowPassFilter', 'range': [20000, 500], 'inverted': true},
      {'target': 'reverbSend', 'range': [0.0, 0.8]},
    ],
  },
];

// ============ Predefined RTPC Definitions ============

/// Common game audio RTPCs
const List<Map<String, dynamic>> kDefaultRtpcDefinitions = [
  {'id': 1, 'name': 'PlayerHealth', 'min': 0.0, 'max': 100.0, 'default': 100.0},
  {'id': 2, 'name': 'PlayerSpeed', 'min': 0.0, 'max': 10.0, 'default': 0.0},
  {'id': 3, 'name': 'DistanceToPlayer', 'min': 0.0, 'max': 100.0, 'default': 0.0},
  {'id': 4, 'name': 'TimeOfDay', 'min': 0.0, 'max': 24.0, 'default': 12.0},
  {'id': 5, 'name': 'Intensity', 'min': 0.0, 'max': 100.0, 'default': 50.0},
  {'id': 6, 'name': 'MusicVolume', 'min': 0.0, 'max': 1.0, 'default': 1.0},
  {'id': 7, 'name': 'SFXVolume', 'min': 0.0, 'max': 1.0, 'default': 1.0},
  {'id': 8, 'name': 'VoiceVolume', 'min': 0.0, 'max': 1.0, 'default': 1.0},
  {'id': 9, 'name': 'AmbientLevel', 'min': 0.0, 'max': 1.0, 'default': 0.5},
  {'id': 10, 'name': 'TensionLevel', 'min': 0.0, 'max': 100.0, 'default': 0.0},
];

/// Generate actions for an event (no placeholder sounds)
List<MiddlewareAction> generateDemoActions(String eventName) {
  // Return empty actions - user adds real sounds via Slot Lab or manually
  return [];
}

// ═══════════════════════════════════════════════════════════════════════════════
// P3.11: PRESET MORPHING
// ═══════════════════════════════════════════════════════════════════════════════

/// Interpolation curve for morphing between presets
enum MorphCurve {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  exponential,
  logarithmic,
  sCurve,
  step,
}

extension MorphCurveExtension on MorphCurve {
  String get displayName {
    switch (this) {
      case MorphCurve.linear: return 'Linear';
      case MorphCurve.easeIn: return 'Ease In';
      case MorphCurve.easeOut: return 'Ease Out';
      case MorphCurve.easeInOut: return 'Ease In-Out';
      case MorphCurve.exponential: return 'Exponential';
      case MorphCurve.logarithmic: return 'Logarithmic';
      case MorphCurve.sCurve: return 'S-Curve';
      case MorphCurve.step: return 'Step';
    }
  }

  /// Apply curve to normalized input (0.0-1.0)
  double apply(double t) {
    t = t.clamp(0.0, 1.0);
    switch (this) {
      case MorphCurve.linear:
        return t;
      case MorphCurve.easeIn:
        return t * t;
      case MorphCurve.easeOut:
        return 1.0 - (1.0 - t) * (1.0 - t);
      case MorphCurve.easeInOut:
        return t < 0.5 ? 2.0 * t * t : 1.0 - math.pow(-2.0 * t + 2.0, 2) / 2.0;
      case MorphCurve.exponential:
        return t == 0 ? 0.0 : math.pow(2, 10 * t - 10).toDouble();
      case MorphCurve.logarithmic:
        return math.log(1.0 + t * (math.e - 1));
      case MorphCurve.sCurve:
        return (1.0 - math.cos(t * math.pi)) / 2.0;
      case MorphCurve.step:
        return t < 0.5 ? 0.0 : 1.0;
    }
  }

  static MorphCurve fromString(String s) {
    return MorphCurve.values.firstWhere(
      (c) => c.name == s || c.displayName == s,
      orElse: () => MorphCurve.linear,
    );
  }
}

/// P3.11: A morphable parameter with start and end values
class MorphParameter {
  final String name;
  final RtpcTargetParameter target;
  final int? targetBusId;
  final int? targetEventId;
  final double startValue;
  final double endValue;
  final MorphCurve curve;
  final bool enabled;

  const MorphParameter({
    required this.name,
    required this.target,
    this.targetBusId,
    this.targetEventId,
    required this.startValue,
    required this.endValue,
    this.curve = MorphCurve.linear,
    this.enabled = true,
  });

  /// Get interpolated value at position t (0.0-1.0)
  double valueAt(double t) {
    if (!enabled) return startValue;
    final curved = curve.apply(t);
    return startValue + (endValue - startValue) * curved;
  }

  MorphParameter copyWith({
    String? name,
    RtpcTargetParameter? target,
    int? targetBusId,
    int? targetEventId,
    double? startValue,
    double? endValue,
    MorphCurve? curve,
    bool? enabled,
  }) {
    return MorphParameter(
      name: name ?? this.name,
      target: target ?? this.target,
      targetBusId: targetBusId ?? this.targetBusId,
      targetEventId: targetEventId ?? this.targetEventId,
      startValue: startValue ?? this.startValue,
      endValue: endValue ?? this.endValue,
      curve: curve ?? this.curve,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'target': target.name,
    'targetBusId': targetBusId,
    'targetEventId': targetEventId,
    'startValue': startValue,
    'endValue': endValue,
    'curve': curve.name,
    'enabled': enabled,
  };

  factory MorphParameter.fromJson(Map<String, dynamic> json) {
    return MorphParameter(
      name: json['name'] as String,
      target: RtpcTargetParameter.values.firstWhere(
        (t) => t.name == json['target'],
        orElse: () => RtpcTargetParameter.volume,
      ),
      targetBusId: json['targetBusId'] as int?,
      targetEventId: json['targetEventId'] as int?,
      startValue: (json['startValue'] as num).toDouble(),
      endValue: (json['endValue'] as num).toDouble(),
      curve: MorphCurveExtension.fromString(json['curve'] as String? ?? 'linear'),
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

/// P3.11: Preset Morph configuration
/// Allows smooth interpolation between two audio presets with per-parameter curves
class PresetMorph {
  final int id;
  final String name;
  final String description;
  final String presetA;  // Source preset name
  final String presetB;  // Target preset name
  final List<MorphParameter> parameters;
  final double position;  // Current morph position (0.0 = A, 1.0 = B)
  final double durationMs;  // Auto-morph duration (0 = manual only)
  final MorphCurve globalCurve;
  final bool enabled;
  final Color color;

  const PresetMorph({
    required this.id,
    required this.name,
    this.description = '',
    required this.presetA,
    required this.presetB,
    this.parameters = const [],
    this.position = 0.0,
    this.durationMs = 0.0,
    this.globalCurve = MorphCurve.linear,
    this.enabled = true,
    this.color = const Color(0xFF9C27B0),
  });

  /// Evaluate all parameters at current position
  Map<RtpcTargetParameter, double> evaluate() {
    if (!enabled) return {};
    final results = <RtpcTargetParameter, double>{};
    for (final param in parameters) {
      if (param.enabled) {
        results[param.target] = param.valueAt(position);
      }
    }
    return results;
  }

  /// Evaluate at specific position
  Map<RtpcTargetParameter, double> evaluateAt(double t) {
    if (!enabled) return {};
    final effectiveT = globalCurve.apply(t.clamp(0.0, 1.0));
    final results = <RtpcTargetParameter, double>{};
    for (final param in parameters) {
      if (param.enabled) {
        results[param.target] = param.valueAt(effectiveT);
      }
    }
    return results;
  }

  /// Get progress towards preset B (0.0-1.0)
  double get normalizedPosition => position.clamp(0.0, 1.0);

  /// Is currently at preset A?
  bool get isAtPresetA => position <= 0.0;

  /// Is currently at preset B?
  bool get isAtPresetB => position >= 1.0;

  /// Is somewhere between presets?
  bool get isMorphing => position > 0.0 && position < 1.0;

  PresetMorph copyWith({
    int? id,
    String? name,
    String? description,
    String? presetA,
    String? presetB,
    List<MorphParameter>? parameters,
    double? position,
    double? durationMs,
    MorphCurve? globalCurve,
    bool? enabled,
    Color? color,
  }) {
    return PresetMorph(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      presetA: presetA ?? this.presetA,
      presetB: presetB ?? this.presetB,
      parameters: parameters ?? this.parameters,
      position: position ?? this.position,
      durationMs: durationMs ?? this.durationMs,
      globalCurve: globalCurve ?? this.globalCurve,
      enabled: enabled ?? this.enabled,
      color: color ?? this.color,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'presetA': presetA,
    'presetB': presetB,
    'parameters': parameters.map((p) => p.toJson()).toList(),
    'position': position,
    'durationMs': durationMs,
    'globalCurve': globalCurve.name,
    'enabled': enabled,
    'color': color.value,
  };

  factory PresetMorph.fromJson(Map<String, dynamic> json) {
    return PresetMorph(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      presetA: json['presetA'] as String,
      presetB: json['presetB'] as String,
      parameters: (json['parameters'] as List<dynamic>?)
          ?.map((p) => MorphParameter.fromJson(p as Map<String, dynamic>))
          .toList() ?? [],
      position: (json['position'] as num?)?.toDouble() ?? 0.0,
      durationMs: (json['durationMs'] as num?)?.toDouble() ?? 0.0,
      globalCurve: MorphCurveExtension.fromString(json['globalCurve'] as String? ?? 'linear'),
      enabled: json['enabled'] as bool? ?? true,
      color: Color(json['color'] as int? ?? 0xFF9C27B0),
    );
  }

  /// Create a volume crossfade morph between two sounds
  factory PresetMorph.volumeCrossfade(int id, String name, String soundA, String soundB) {
    return PresetMorph(
      id: id,
      name: name,
      presetA: soundA,
      presetB: soundB,
      parameters: [
        MorphParameter(
          name: 'Sound A Volume',
          target: RtpcTargetParameter.volume,
          startValue: 1.0,
          endValue: 0.0,
          curve: MorphCurve.sCurve,
        ),
        MorphParameter(
          name: 'Sound B Volume',
          target: RtpcTargetParameter.volume,
          startValue: 0.0,
          endValue: 1.0,
          curve: MorphCurve.sCurve,
        ),
      ],
    );
  }

  /// Create an EQ morph (filter sweep)
  factory PresetMorph.filterSweep(int id, String name, {double startHz = 200, double endHz = 8000}) {
    return PresetMorph(
      id: id,
      name: name,
      presetA: 'Dark',
      presetB: 'Bright',
      parameters: [
        MorphParameter(
          name: 'LPF Cutoff',
          target: RtpcTargetParameter.lowPassFilter,
          startValue: startHz,
          endValue: endHz,
          curve: MorphCurve.exponential,
        ),
      ],
    );
  }

  /// Create a tension builder morph
  factory PresetMorph.tensionBuilder(int id, String name) {
    return PresetMorph(
      id: id,
      name: name,
      presetA: 'Calm',
      presetB: 'Tense',
      parameters: [
        MorphParameter(
          name: 'Volume',
          target: RtpcTargetParameter.volume,
          startValue: 0.6,
          endValue: 1.0,
          curve: MorphCurve.easeIn,
        ),
        MorphParameter(
          name: 'LPF',
          target: RtpcTargetParameter.lowPassFilter,
          startValue: 2000,
          endValue: 12000,
          curve: MorphCurve.exponential,
        ),
        MorphParameter(
          name: 'Reverb',
          target: RtpcTargetParameter.reverbSend,
          startValue: 0.1,
          endValue: 0.5,
          curve: MorphCurve.linear,
        ),
      ],
    );
  }
}

/// Preset morph animation state
enum MorphAnimationState {
  idle,
  morphingToA,
  morphingToB,
  oscillating,
}

/// Preset morph templates
const List<Map<String, dynamic>> kPresetMorphTemplates = [
  {
    'name': 'Volume Crossfade',
    'description': 'Equal-power crossfade between two sounds',
    'type': 'crossfade',
  },
  {
    'name': 'Filter Sweep',
    'description': 'Sweep lowpass filter from dark to bright',
    'type': 'filter',
  },
  {
    'name': 'Tension Builder',
    'description': 'Build tension with volume, filter, and reverb',
    'type': 'tension',
  },
  {
    'name': 'Distance Fade',
    'description': 'Simulate approaching/receding sound source',
    'type': 'distance',
  },
  {
    'name': 'Day/Night Cycle',
    'description': 'Ambient transition for time of day',
    'type': 'ambient',
  },
];

// ═══════════════════════════════════════════════════════════════════════════════
// DUCKING MATRIX
// ═══════════════════════════════════════════════════════════════════════════════

/// Ducking curve shape
enum DuckingCurve {
  linear,
  exponential,
  logarithmic,
  sCurve,
}

extension DuckingCurveExtension on DuckingCurve {
  String get displayName {
    switch (this) {
      case DuckingCurve.linear: return 'Linear';
      case DuckingCurve.exponential: return 'Exponential';
      case DuckingCurve.logarithmic: return 'Logarithmic';
      case DuckingCurve.sCurve: return 'S-Curve';
    }
  }

  int get value => index;

  static DuckingCurve fromValue(int v) {
    if (v < 0 || v >= DuckingCurve.values.length) return DuckingCurve.linear;
    return DuckingCurve.values[v];
  }
}

/// Ducking rule - automatic volume reduction when source plays
class DuckingRule {
  final int id;
  final String sourceBus;
  final int sourceBusId;
  final String targetBus;
  final int targetBusId;
  final double duckAmountDb;
  final double attackMs;
  final double releaseMs;
  final double threshold;
  final DuckingCurve curve;
  final bool enabled;

  const DuckingRule({
    required this.id,
    required this.sourceBus,
    required this.sourceBusId,
    required this.targetBus,
    required this.targetBusId,
    this.duckAmountDb = -6.0,
    this.attackMs = 50.0,
    this.releaseMs = 500.0,
    this.threshold = 0.01,
    this.curve = DuckingCurve.linear,
    this.enabled = true,
  });

  DuckingRule copyWith({
    int? id,
    String? sourceBus,
    int? sourceBusId,
    String? targetBus,
    int? targetBusId,
    double? duckAmountDb,
    double? attackMs,
    double? releaseMs,
    double? threshold,
    DuckingCurve? curve,
    bool? enabled,
  }) {
    return DuckingRule(
      id: id ?? this.id,
      sourceBus: sourceBus ?? this.sourceBus,
      sourceBusId: sourceBusId ?? this.sourceBusId,
      targetBus: targetBus ?? this.targetBus,
      targetBusId: targetBusId ?? this.targetBusId,
      duckAmountDb: duckAmountDb ?? this.duckAmountDb,
      attackMs: attackMs ?? this.attackMs,
      releaseMs: releaseMs ?? this.releaseMs,
      threshold: threshold ?? this.threshold,
      curve: curve ?? this.curve,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceBus': sourceBus,
    'sourceBusId': sourceBusId,
    'targetBus': targetBus,
    'targetBusId': targetBusId,
    'duckAmountDb': duckAmountDb,
    'attackMs': attackMs,
    'releaseMs': releaseMs,
    'threshold': threshold,
    'curve': curve.value,
    'enabled': enabled,
  };

  factory DuckingRule.fromJson(Map<String, dynamic> json) {
    return DuckingRule(
      id: json['id'] as int? ?? 0,
      sourceBus: json['sourceBus'] as String? ?? '',
      sourceBusId: json['sourceBusId'] as int? ?? 0,
      targetBus: json['targetBus'] as String? ?? '',
      targetBusId: json['targetBusId'] as int? ?? 0,
      duckAmountDb: (json['duckAmountDb'] as num?)?.toDouble() ?? -6.0,
      attackMs: (json['attackMs'] as num?)?.toDouble() ?? 50.0,
      releaseMs: (json['releaseMs'] as num?)?.toDouble() ?? 500.0,
      threshold: (json['threshold'] as num?)?.toDouble() ?? 0.01,
      curve: DuckingCurveExtension.fromValue(json['curve'] as int? ?? 0),
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BLEND CONTAINER
// ═══════════════════════════════════════════════════════════════════════════════

/// Crossfade curve type
enum CrossfadeCurve {
  linear,
  equalPower,
  sCurve,
  sinCos,
}

extension CrossfadeCurveExtension on CrossfadeCurve {
  String get displayName {
    switch (this) {
      case CrossfadeCurve.linear: return 'Linear';
      case CrossfadeCurve.equalPower: return 'Equal Power';
      case CrossfadeCurve.sCurve: return 'S-Curve';
      case CrossfadeCurve.sinCos: return 'Sin/Cos';
    }
  }

  int get value => index;

  static CrossfadeCurve fromValue(int v) {
    if (v < 0 || v >= CrossfadeCurve.values.length) return CrossfadeCurve.equalPower;
    return CrossfadeCurve.values[v];
  }
}

/// Blend child with RTPC range
class BlendChild {
  final int id;
  final String name;
  final String? audioPath;  // Path to audio file for playback
  final double rtpcStart;
  final double rtpcEnd;
  final double crossfadeWidth;

  const BlendChild({
    required this.id,
    required this.name,
    this.audioPath,
    required this.rtpcStart,
    required this.rtpcEnd,
    this.crossfadeWidth = 0.1,
  });

  BlendChild copyWith({
    int? id,
    String? name,
    String? audioPath,
    double? rtpcStart,
    double? rtpcEnd,
    double? crossfadeWidth,
  }) {
    return BlendChild(
      id: id ?? this.id,
      name: name ?? this.name,
      audioPath: audioPath ?? this.audioPath,
      rtpcStart: rtpcStart ?? this.rtpcStart,
      rtpcEnd: rtpcEnd ?? this.rtpcEnd,
      crossfadeWidth: crossfadeWidth ?? this.crossfadeWidth,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'audioPath': audioPath,
    'rtpcStart': rtpcStart,
    'rtpcEnd': rtpcEnd,
    'crossfadeWidth': crossfadeWidth,
  };

  factory BlendChild.fromJson(Map<String, dynamic> json) {
    return BlendChild(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      audioPath: json['audioPath'] as String?,
      rtpcStart: (json['rtpcStart'] as num?)?.toDouble() ?? 0.0,
      rtpcEnd: (json['rtpcEnd'] as num?)?.toDouble() ?? 1.0,
      crossfadeWidth: (json['crossfadeWidth'] as num?)?.toDouble() ?? 0.1,
    );
  }
}

/// Blend container - crossfade between sounds based on RTPC
class BlendContainer {
  final int id;
  final String name;
  final int rtpcId;
  final List<BlendChild> children;
  final CrossfadeCurve crossfadeCurve;
  final bool enabled;

  const BlendContainer({
    required this.id,
    required this.name,
    required this.rtpcId,
    this.children = const [],
    this.crossfadeCurve = CrossfadeCurve.equalPower,
    this.enabled = true,
  });

  BlendContainer copyWith({
    int? id,
    String? name,
    int? rtpcId,
    List<BlendChild>? children,
    CrossfadeCurve? crossfadeCurve,
    bool? enabled,
  }) {
    return BlendContainer(
      id: id ?? this.id,
      name: name ?? this.name,
      rtpcId: rtpcId ?? this.rtpcId,
      children: children ?? this.children,
      crossfadeCurve: crossfadeCurve ?? this.crossfadeCurve,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'rtpcId': rtpcId,
    'children': children.map((c) => c.toJson()).toList(),
    'crossfadeCurve': crossfadeCurve.value,
    'enabled': enabled,
  };

  factory BlendContainer.fromJson(Map<String, dynamic> json) {
    return BlendContainer(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      rtpcId: json['rtpcId'] as int? ?? 0,
      children: (json['children'] as List<dynamic>?)
          ?.map((c) => BlendChild.fromJson(c as Map<String, dynamic>))
          .toList() ?? [],
      crossfadeCurve: CrossfadeCurveExtension.fromValue(json['crossfadeCurve'] as int? ?? 1),
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RANDOMIZATION CONTAINER
// ═══════════════════════════════════════════════════════════════════════════════

/// Random selection mode
enum RandomMode {
  random,
  shuffle,
  shuffleWithHistory,
  roundRobin,
}

extension RandomModeExtension on RandomMode {
  String get displayName {
    switch (this) {
      case RandomMode.random: return 'Random';
      case RandomMode.shuffle: return 'Shuffle';
      case RandomMode.shuffleWithHistory: return 'Shuffle (No Repeat)';
      case RandomMode.roundRobin: return 'Round Robin';
    }
  }

  int get value => index;

  static RandomMode fromValue(int v) {
    if (v < 0 || v >= RandomMode.values.length) return RandomMode.random;
    return RandomMode.values[v];
  }
}

/// Random child with weight and variation
class RandomChild {
  final int id;
  final String name;
  final String? audioPath;  // Path to audio file for playback
  final double weight;
  final double pitchMin;
  final double pitchMax;
  final double volumeMin;
  final double volumeMax;

  const RandomChild({
    required this.id,
    required this.name,
    this.audioPath,
    this.weight = 1.0,
    this.pitchMin = 0.0,
    this.pitchMax = 0.0,
    this.volumeMin = 0.0,
    this.volumeMax = 0.0,
  });

  RandomChild copyWith({
    int? id,
    String? name,
    String? audioPath,
    double? weight,
    double? pitchMin,
    double? pitchMax,
    double? volumeMin,
    double? volumeMax,
  }) {
    return RandomChild(
      id: id ?? this.id,
      name: name ?? this.name,
      audioPath: audioPath ?? this.audioPath,
      weight: weight ?? this.weight,
      pitchMin: pitchMin ?? this.pitchMin,
      pitchMax: pitchMax ?? this.pitchMax,
      volumeMin: volumeMin ?? this.volumeMin,
      volumeMax: volumeMax ?? this.volumeMax,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'audioPath': audioPath,
    'weight': weight,
    'pitchMin': pitchMin,
    'pitchMax': pitchMax,
    'volumeMin': volumeMin,
    'volumeMax': volumeMax,
  };

  factory RandomChild.fromJson(Map<String, dynamic> json) {
    return RandomChild(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      audioPath: json['audioPath'] as String?,
      weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
      pitchMin: (json['pitchMin'] as num?)?.toDouble() ?? 0.0,
      pitchMax: (json['pitchMax'] as num?)?.toDouble() ?? 0.0,
      volumeMin: (json['volumeMin'] as num?)?.toDouble() ?? 0.0,
      volumeMax: (json['volumeMax'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Random container - random sound selection with variation
class RandomContainer {
  final int id;
  final String name;
  final List<RandomChild> children;
  final RandomMode mode;
  final int avoidRepeatCount;
  final double globalPitchMin;
  final double globalPitchMax;
  final double globalVolumeMin;
  final double globalVolumeMax;
  final bool enabled;

  /// Seed for deterministic random selection (M4 Determinism Mode)
  /// When useDeterministicMode is true, this seed ensures reproducible results
  final int? seed;

  /// Enable deterministic mode for reproducible random selection (M4)
  /// When true, uses seed for all random operations
  final bool useDeterministicMode;

  const RandomContainer({
    required this.id,
    required this.name,
    this.children = const [],
    this.mode = RandomMode.random,
    this.avoidRepeatCount = 2,
    this.globalPitchMin = 0.0,
    this.globalPitchMax = 0.0,
    this.globalVolumeMin = 0.0,
    this.globalVolumeMax = 0.0,
    this.enabled = true,
    this.seed,
    this.useDeterministicMode = false,
  });

  RandomContainer copyWith({
    int? id,
    String? name,
    List<RandomChild>? children,
    RandomMode? mode,
    int? avoidRepeatCount,
    double? globalPitchMin,
    double? globalPitchMax,
    double? globalVolumeMin,
    double? globalVolumeMax,
    bool? enabled,
    int? seed,
    bool? useDeterministicMode,
  }) {
    return RandomContainer(
      id: id ?? this.id,
      name: name ?? this.name,
      children: children ?? this.children,
      mode: mode ?? this.mode,
      avoidRepeatCount: avoidRepeatCount ?? this.avoidRepeatCount,
      globalPitchMin: globalPitchMin ?? this.globalPitchMin,
      globalPitchMax: globalPitchMax ?? this.globalPitchMax,
      globalVolumeMin: globalVolumeMin ?? this.globalVolumeMin,
      globalVolumeMax: globalVolumeMax ?? this.globalVolumeMax,
      enabled: enabled ?? this.enabled,
      seed: seed ?? this.seed,
      useDeterministicMode: useDeterministicMode ?? this.useDeterministicMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'children': children.map((c) => c.toJson()).toList(),
    'mode': mode.value,
    'avoidRepeatCount': avoidRepeatCount,
    'globalPitchMin': globalPitchMin,
    'globalPitchMax': globalPitchMax,
    'globalVolumeMin': globalVolumeMin,
    'globalVolumeMax': globalVolumeMax,
    'enabled': enabled,
    'seed': seed,
    'useDeterministicMode': useDeterministicMode,
  };

  factory RandomContainer.fromJson(Map<String, dynamic> json) {
    return RandomContainer(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      children: (json['children'] as List<dynamic>?)
          ?.map((c) => RandomChild.fromJson(c as Map<String, dynamic>))
          .toList() ?? [],
      mode: RandomModeExtension.fromValue(json['mode'] as int? ?? 0),
      avoidRepeatCount: json['avoidRepeatCount'] as int? ?? 2,
      globalPitchMin: (json['globalPitchMin'] as num?)?.toDouble() ?? 0.0,
      globalPitchMax: (json['globalPitchMax'] as num?)?.toDouble() ?? 0.0,
      globalVolumeMin: (json['globalVolumeMin'] as num?)?.toDouble() ?? 0.0,
      globalVolumeMax: (json['globalVolumeMax'] as num?)?.toDouble() ?? 0.0,
      enabled: json['enabled'] as bool? ?? true,
      seed: json['seed'] as int?,
      useDeterministicMode: json['useDeterministicMode'] as bool? ?? false,
    );
  }

  /// Generate a new random seed
  static int generateSeed() => DateTime.now().microsecondsSinceEpoch;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEQUENCE CONTAINER
// ═══════════════════════════════════════════════════════════════════════════════

/// Sequence end behavior
enum SequenceEndBehavior {
  stop,
  loop,
  holdLast,
  pingPong,
}

extension SequenceEndBehaviorExtension on SequenceEndBehavior {
  String get displayName {
    switch (this) {
      case SequenceEndBehavior.stop: return 'Stop';
      case SequenceEndBehavior.loop: return 'Loop';
      case SequenceEndBehavior.holdLast: return 'Hold Last';
      case SequenceEndBehavior.pingPong: return 'Ping-Pong';
    }
  }

  int get value => index;

  static SequenceEndBehavior fromValue(int v) {
    if (v < 0 || v >= SequenceEndBehavior.values.length) return SequenceEndBehavior.stop;
    return SequenceEndBehavior.values[v];
  }
}

/// Sequence step
class SequenceStep {
  final int index;
  final int childId;
  final String childName;
  final String? audioPath;  // Path to audio file for playback
  final double delayMs;
  final double durationMs;
  final double fadeInMs;
  final double fadeOutMs;
  final int loopCount;
  final double volume;  // Volume for this step (0.0-1.0)

  const SequenceStep({
    required this.index,
    required this.childId,
    required this.childName,
    this.audioPath,
    this.delayMs = 0.0,
    this.durationMs = 0.0,
    this.fadeInMs = 0.0,
    this.fadeOutMs = 0.0,
    this.loopCount = 1,
    this.volume = 1.0,
  });

  SequenceStep copyWith({
    int? index,
    int? childId,
    String? childName,
    String? audioPath,
    double? delayMs,
    double? durationMs,
    double? fadeInMs,
    double? fadeOutMs,
    int? loopCount,
    double? volume,
  }) {
    return SequenceStep(
      index: index ?? this.index,
      childId: childId ?? this.childId,
      childName: childName ?? this.childName,
      audioPath: audioPath ?? this.audioPath,
      delayMs: delayMs ?? this.delayMs,
      durationMs: durationMs ?? this.durationMs,
      fadeInMs: fadeInMs ?? this.fadeInMs,
      fadeOutMs: fadeOutMs ?? this.fadeOutMs,
      loopCount: loopCount ?? this.loopCount,
      volume: volume ?? this.volume,
    );
  }

  Map<String, dynamic> toJson() => {
    'index': index,
    'childId': childId,
    'childName': childName,
    'audioPath': audioPath,
    'delayMs': delayMs,
    'durationMs': durationMs,
    'fadeInMs': fadeInMs,
    'fadeOutMs': fadeOutMs,
    'loopCount': loopCount,
    'volume': volume,
  };

  factory SequenceStep.fromJson(Map<String, dynamic> json) {
    return SequenceStep(
      index: json['index'] as int? ?? 0,
      childId: json['childId'] as int? ?? 0,
      childName: json['childName'] as String? ?? '',
      audioPath: json['audioPath'] as String?,
      delayMs: (json['delayMs'] as num?)?.toDouble() ?? 0.0,
      durationMs: (json['durationMs'] as num?)?.toDouble() ?? 0.0,
      fadeInMs: (json['fadeInMs'] as num?)?.toDouble() ?? 0.0,
      fadeOutMs: (json['fadeOutMs'] as num?)?.toDouble() ?? 0.0,
      loopCount: json['loopCount'] as int? ?? 1,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Sequence container - timed sequence of sounds
class SequenceContainer {
  final int id;
  final String name;
  final List<SequenceStep> steps;
  final SequenceEndBehavior endBehavior;
  final double speed;
  final bool enabled;

  const SequenceContainer({
    required this.id,
    required this.name,
    this.steps = const [],
    this.endBehavior = SequenceEndBehavior.stop,
    this.speed = 1.0,
    this.enabled = true,
  });

  SequenceContainer copyWith({
    int? id,
    String? name,
    List<SequenceStep>? steps,
    SequenceEndBehavior? endBehavior,
    double? speed,
    bool? enabled,
  }) {
    return SequenceContainer(
      id: id ?? this.id,
      name: name ?? this.name,
      steps: steps ?? this.steps,
      endBehavior: endBehavior ?? this.endBehavior,
      speed: speed ?? this.speed,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'steps': steps.map((s) => s.toJson()).toList(),
    'endBehavior': endBehavior.value,
    'speed': speed,
    'enabled': enabled,
  };

  factory SequenceContainer.fromJson(Map<String, dynamic> json) {
    return SequenceContainer(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      steps: (json['steps'] as List<dynamic>?)
          ?.map((s) => SequenceStep.fromJson(s as Map<String, dynamic>))
          .toList() ?? [],
      endBehavior: SequenceEndBehaviorExtension.fromValue(json['endBehavior'] as int? ?? 0),
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MUSIC SYSTEM
// ═══════════════════════════════════════════════════════════════════════════════

/// Music sync point type
enum MusicSyncPoint {
  immediate,
  beat,
  bar,
  marker,
  customGrid,
  segmentEnd,
}

extension MusicSyncPointExtension on MusicSyncPoint {
  String get displayName {
    switch (this) {
      case MusicSyncPoint.immediate: return 'Immediate';
      case MusicSyncPoint.beat: return 'Next Beat';
      case MusicSyncPoint.bar: return 'Next Bar';
      case MusicSyncPoint.marker: return 'Next Marker';
      case MusicSyncPoint.customGrid: return 'Custom Grid';
      case MusicSyncPoint.segmentEnd: return 'Segment End';
    }
  }

  int get value => index;

  static MusicSyncPoint fromValue(int v) {
    if (v < 0 || v >= MusicSyncPoint.values.length) return MusicSyncPoint.beat;
    return MusicSyncPoint.values[v];
  }
}

/// Marker type
enum MarkerType {
  generic,
  entry,
  exit,
  sync,
}

extension MarkerTypeExtension on MarkerType {
  String get displayName {
    switch (this) {
      case MarkerType.generic: return 'Generic';
      case MarkerType.entry: return 'Entry';
      case MarkerType.exit: return 'Exit';
      case MarkerType.sync: return 'Sync';
    }
  }

  int get value => index;

  static MarkerType fromValue(int v) {
    if (v < 0 || v >= MarkerType.values.length) return MarkerType.generic;
    return MarkerType.values[v];
  }
}

/// Music marker
class MusicMarker {
  final String name;
  final double positionBars;
  final MarkerType markerType;

  const MusicMarker({
    required this.name,
    required this.positionBars,
    this.markerType = MarkerType.generic,
  });

  MusicMarker copyWith({
    String? name,
    double? positionBars,
    MarkerType? markerType,
  }) {
    return MusicMarker(
      name: name ?? this.name,
      positionBars: positionBars ?? this.positionBars,
      markerType: markerType ?? this.markerType,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'positionBars': positionBars,
    'markerType': markerType.value,
  };

  factory MusicMarker.fromJson(Map<String, dynamic> json) {
    return MusicMarker(
      name: json['name'] as String? ?? '',
      positionBars: (json['positionBars'] as num?)?.toDouble() ?? 0.0,
      markerType: MarkerTypeExtension.fromValue(json['markerType'] as int? ?? 0),
    );
  }
}

/// Stinger definition
class Stinger {
  final int id;
  final String name;
  final int soundId;
  final MusicSyncPoint syncPoint;
  final double customGridBeats;
  final double musicDuckDb;
  final double duckAttackMs;
  final double duckReleaseMs;
  final int priority;
  final bool canInterrupt;

  const Stinger({
    required this.id,
    required this.name,
    required this.soundId,
    this.syncPoint = MusicSyncPoint.beat,
    this.customGridBeats = 4.0,
    this.musicDuckDb = 0.0,
    this.duckAttackMs = 10.0,
    this.duckReleaseMs = 100.0,
    this.priority = 50,
    this.canInterrupt = false,
  });

  Stinger copyWith({
    int? id,
    String? name,
    int? soundId,
    MusicSyncPoint? syncPoint,
    double? customGridBeats,
    double? musicDuckDb,
    double? duckAttackMs,
    double? duckReleaseMs,
    int? priority,
    bool? canInterrupt,
  }) {
    return Stinger(
      id: id ?? this.id,
      name: name ?? this.name,
      soundId: soundId ?? this.soundId,
      syncPoint: syncPoint ?? this.syncPoint,
      customGridBeats: customGridBeats ?? this.customGridBeats,
      musicDuckDb: musicDuckDb ?? this.musicDuckDb,
      duckAttackMs: duckAttackMs ?? this.duckAttackMs,
      duckReleaseMs: duckReleaseMs ?? this.duckReleaseMs,
      priority: priority ?? this.priority,
      canInterrupt: canInterrupt ?? this.canInterrupt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'soundId': soundId,
    'syncPoint': syncPoint.value,
    'customGridBeats': customGridBeats,
    'musicDuckDb': musicDuckDb,
    'duckAttackMs': duckAttackMs,
    'duckReleaseMs': duckReleaseMs,
    'priority': priority,
    'canInterrupt': canInterrupt,
  };

  factory Stinger.fromJson(Map<String, dynamic> json) {
    return Stinger(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      soundId: json['soundId'] as int? ?? 0,
      syncPoint: MusicSyncPointExtension.fromValue(json['syncPoint'] as int? ?? 1),
      customGridBeats: (json['customGridBeats'] as num?)?.toDouble() ?? 4.0,
      musicDuckDb: (json['musicDuckDb'] as num?)?.toDouble() ?? 0.0,
      duckAttackMs: (json['duckAttackMs'] as num?)?.toDouble() ?? 10.0,
      duckReleaseMs: (json['duckReleaseMs'] as num?)?.toDouble() ?? 100.0,
      priority: json['priority'] as int? ?? 50,
      canInterrupt: json['canInterrupt'] as bool? ?? false,
    );
  }
}

/// Music segment
class MusicSegment {
  final int id;
  final String name;
  final int soundId;
  final double tempo;
  final int beatsPerBar;
  final int durationBars;
  final double entryCueBars;
  final double exitCueBars;
  final double loopStartBars;
  final double loopEndBars;
  final List<MusicMarker> markers;

  const MusicSegment({
    required this.id,
    required this.name,
    required this.soundId,
    this.tempo = 120.0,
    this.beatsPerBar = 4,
    this.durationBars = 4,
    this.entryCueBars = 0.0,
    this.exitCueBars = 4.0,
    this.loopStartBars = 0.0,
    this.loopEndBars = 4.0,
    this.markers = const [],
  });

  /// Convert bars to seconds
  double barsToSecs(double bars) {
    final beatsPerSec = tempo / 60.0;
    return (bars * beatsPerBar) / beatsPerSec;
  }

  /// Convert seconds to bars
  double secsToBars(double secs) {
    final beatsPerSec = tempo / 60.0;
    return (secs * beatsPerSec) / beatsPerBar;
  }

  MusicSegment copyWith({
    int? id,
    String? name,
    int? soundId,
    double? tempo,
    int? beatsPerBar,
    int? durationBars,
    double? entryCueBars,
    double? exitCueBars,
    double? loopStartBars,
    double? loopEndBars,
    List<MusicMarker>? markers,
  }) {
    return MusicSegment(
      id: id ?? this.id,
      name: name ?? this.name,
      soundId: soundId ?? this.soundId,
      tempo: tempo ?? this.tempo,
      beatsPerBar: beatsPerBar ?? this.beatsPerBar,
      durationBars: durationBars ?? this.durationBars,
      entryCueBars: entryCueBars ?? this.entryCueBars,
      exitCueBars: exitCueBars ?? this.exitCueBars,
      loopStartBars: loopStartBars ?? this.loopStartBars,
      loopEndBars: loopEndBars ?? this.loopEndBars,
      markers: markers ?? this.markers,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'soundId': soundId,
    'tempo': tempo,
    'beatsPerBar': beatsPerBar,
    'durationBars': durationBars,
    'entryCueBars': entryCueBars,
    'exitCueBars': exitCueBars,
    'loopStartBars': loopStartBars,
    'loopEndBars': loopEndBars,
    'markers': markers.map((m) => m.toJson()).toList(),
  };

  factory MusicSegment.fromJson(Map<String, dynamic> json) {
    return MusicSegment(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      soundId: json['soundId'] as int? ?? 0,
      tempo: (json['tempo'] as num?)?.toDouble() ?? 120.0,
      beatsPerBar: json['beatsPerBar'] as int? ?? 4,
      durationBars: json['durationBars'] as int? ?? 4,
      entryCueBars: (json['entryCueBars'] as num?)?.toDouble() ?? 0.0,
      exitCueBars: (json['exitCueBars'] as num?)?.toDouble() ?? 4.0,
      loopStartBars: (json['loopStartBars'] as num?)?.toDouble() ?? 0.0,
      loopEndBars: (json['loopEndBars'] as num?)?.toDouble() ?? 4.0,
      markers: (json['markers'] as List<dynamic>?)
          ?.map((m) => MusicMarker.fromJson(m as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ATTENUATION SYSTEM
// ═══════════════════════════════════════════════════════════════════════════════

/// Attenuation curve type
enum AttenuationType {
  winAmount,
  nearWin,
  comboMultiplier,
  featureProgress,
  timeElapsed,
}

extension AttenuationTypeExtension on AttenuationType {
  String get displayName {
    switch (this) {
      case AttenuationType.winAmount: return 'Win Amount';
      case AttenuationType.nearWin: return 'Near Win';
      case AttenuationType.comboMultiplier: return 'Combo Multiplier';
      case AttenuationType.featureProgress: return 'Feature Progress';
      case AttenuationType.timeElapsed: return 'Time Elapsed';
    }
  }

  int get value => index;

  static AttenuationType fromValue(int v) {
    if (v < 0 || v >= AttenuationType.values.length) return AttenuationType.winAmount;
    return AttenuationType.values[v];
  }
}

/// Attenuation curve for slot-specific effects
class AttenuationCurve {
  final int id;
  final String name;
  final AttenuationType attenuationType;
  final double inputMin;
  final double inputMax;
  final double outputMin;
  final double outputMax;
  final RtpcCurveShape curveShape;
  final bool enabled;

  const AttenuationCurve({
    required this.id,
    required this.name,
    required this.attenuationType,
    this.inputMin = 0.0,
    this.inputMax = 1.0,
    this.outputMin = 0.0,
    this.outputMax = 1.0,
    this.curveShape = RtpcCurveShape.linear,
    this.enabled = true,
  });

  /// Evaluate curve at input value
  double evaluate(double input) {
    if (!enabled) return outputMin;

    final range = inputMax - inputMin;
    if (range.abs() < 0.0001) return outputMin;

    final t = ((input - inputMin) / range).clamp(0.0, 1.0);

    // Simple linear for now - full shape support in Rust
    return outputMin + t * (outputMax - outputMin);
  }

  AttenuationCurve copyWith({
    int? id,
    String? name,
    AttenuationType? attenuationType,
    double? inputMin,
    double? inputMax,
    double? outputMin,
    double? outputMax,
    RtpcCurveShape? curveShape,
    bool? enabled,
  }) {
    return AttenuationCurve(
      id: id ?? this.id,
      name: name ?? this.name,
      attenuationType: attenuationType ?? this.attenuationType,
      inputMin: inputMin ?? this.inputMin,
      inputMax: inputMax ?? this.inputMax,
      outputMin: outputMin ?? this.outputMin,
      outputMax: outputMax ?? this.outputMax,
      curveShape: curveShape ?? this.curveShape,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'attenuationType': attenuationType.value,
    'inputMin': inputMin,
    'inputMax': inputMax,
    'outputMin': outputMin,
    'outputMax': outputMax,
    'curveShape': curveShape.index,
    'enabled': enabled,
  };

  factory AttenuationCurve.fromJson(Map<String, dynamic> json) {
    return AttenuationCurve(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      attenuationType: AttenuationTypeExtension.fromValue(json['attenuationType'] as int? ?? 0),
      inputMin: (json['inputMin'] as num?)?.toDouble() ?? 0.0,
      inputMax: (json['inputMax'] as num?)?.toDouble() ?? 1.0,
      outputMin: (json['outputMin'] as num?)?.toDouble() ?? 0.0,
      outputMax: (json['outputMax'] as num?)?.toDouble() ?? 1.0,
      curveShape: RtpcCurveShapeExtension.fromIndex(json['curveShape'] as int? ?? 0),
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}
