// Middleware Models
//
// Data models for Wwise/FMOD-style middleware:
// - MiddlewareAction: Individual action in an event
// - MiddlewareEvent: Event with list of actions
// - All Wwise/FMOD action types, buses, scopes, etc.

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

/// All available asset IDs
const List<String> kAllAssetIds = [
  'music_main', 'music_bonus', 'music_freespins', 'music_bigwin',
  'sfx_spin', 'sfx_reel_land', 'sfx_win_small', 'sfx_win_medium', 'sfx_win_big',
  'sfx_click', 'sfx_hover', 'sfx_coins', 'sfx_jackpot',
  'amb_casino', 'amb_nature', 'amb_crowd',
  'vo_bigwin', 'vo_megawin', 'vo_jackpot', 'vo_freespins',
  '—',
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

/// Generate demo actions for an event
List<MiddlewareAction> generateDemoActions(String eventName) {
  switch (eventName) {
    case 'Play_Music':
      return [
        MiddlewareAction(
          id: '${eventName}_1',
          type: ActionType.play,
          assetId: 'music_main',
          bus: 'Music',
          fadeTime: 0.5,
          loop: true,
        ),
      ];
    case 'Stop_Music':
      return [
        MiddlewareAction(
          id: '${eventName}_1',
          type: ActionType.stop,
          assetId: 'music_main',
          bus: 'Music',
          fadeTime: 1.0,
        ),
      ];
    case 'BigWin_Start':
      return [
        MiddlewareAction(
          id: '${eventName}_1',
          type: ActionType.setVolume,
          bus: 'Music',
          gain: 0.3,
          fadeTime: 0.2,
        ),
        MiddlewareAction(
          id: '${eventName}_2',
          type: ActionType.play,
          assetId: 'sfx_jackpot',
          bus: 'Wins',
          priority: ActionPriority.high,
        ),
        MiddlewareAction(
          id: '${eventName}_3',
          type: ActionType.play,
          assetId: 'vo_bigwin',
          bus: 'VO',
          delay: 0.5,
        ),
      ];
    default:
      return [
        MiddlewareAction(
          id: '${eventName}_1',
          type: ActionType.play,
          assetId: 'sfx_click',
          bus: 'SFX',
        ),
      ];
  }
}
