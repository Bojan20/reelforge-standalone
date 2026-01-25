/// Auto Event Builder Provider
///
/// State management for SlotLab Auto Event Builder:
/// - Draft management (create, edit, commit, cancel)
/// - Rule engine for asset→event matching
/// - Event/binding registry
/// - Undo/redo support
///
/// Based on SLOTLAB_AUTO_EVENT_BUILDER_FINAL.md specification.
library;

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/auto_event_builder_models.dart';
import '../models/middleware_models.dart' show ActionType;
import '../services/event_naming_service.dart';
import '../services/audio_context_service.dart';

// =============================================================================
// EVENT DRAFT
// =============================================================================

/// Uncommitted event being configured
class EventDraft {
  /// Generated event ID
  String eventId;

  /// Target being bound to
  final DropTarget target;

  /// Asset being assigned
  final AudioAsset asset;

  /// Selected trigger
  String trigger;

  /// Auto-selected bus
  String bus;

  /// Selected preset
  String presetId;

  /// Action type (Play, Stop, etc.) — auto-determined by AudioContextService
  ActionType actionType;

  /// Stop target (for Stop actions — which bus/event to stop)
  String? stopTarget;

  /// Auto-action reason (human-readable explanation)
  String actionReason;

  /// Stage context
  StageContext stageContext;

  /// Variation policy
  VariationPolicy variationPolicy;

  /// Additional tags
  List<String> tags;

  /// Parameter overrides from preset
  Map<String, dynamic> paramOverrides;

  /// Whether draft has been modified from defaults
  bool get isModified => _isModified;
  bool _isModified = false;

  EventDraft({
    required this.eventId,
    required this.target,
    required this.asset,
    required this.trigger,
    required this.bus,
    required this.presetId,
    this.actionType = ActionType.play,
    this.stopTarget,
    this.actionReason = 'Default → Play',
    this.stageContext = StageContext.global,
    this.variationPolicy = VariationPolicy.random,
    this.tags = const [],
    this.paramOverrides = const {},
  });

  /// Mark draft as modified
  void markModified() {
    _isModified = true;
  }

  /// Available triggers for this target
  List<String> get availableTriggers => target.availableTriggers;

  /// Copy with changes
  EventDraft copyWith({
    String? eventId,
    DropTarget? target,
    AudioAsset? asset,
    String? trigger,
    String? bus,
    String? presetId,
    ActionType? actionType,
    String? stopTarget,
    String? actionReason,
    StageContext? stageContext,
    VariationPolicy? variationPolicy,
    List<String>? tags,
    Map<String, dynamic>? paramOverrides,
  }) {
    return EventDraft(
      eventId: eventId ?? this.eventId,
      target: target ?? this.target,
      asset: asset ?? this.asset,
      trigger: trigger ?? this.trigger,
      bus: bus ?? this.bus,
      presetId: presetId ?? this.presetId,
      actionType: actionType ?? this.actionType,
      stopTarget: stopTarget ?? this.stopTarget,
      actionReason: actionReason ?? this.actionReason,
      stageContext: stageContext ?? this.stageContext,
      variationPolicy: variationPolicy ?? this.variationPolicy,
      tags: tags ?? this.tags,
      paramOverrides: paramOverrides ?? this.paramOverrides,
    );
  }
}

// =============================================================================
// COMMITTED EVENT
// =============================================================================

/// Committed event in the manifest
/// Spatial mode for auto-panning
enum SpatialMode {
  /// No spatial processing
  none,
  /// Fixed pan value
  fixed,
  /// Auto-pan based on target (D.8: per-reel spatial)
  autoPerReel,
  /// Follow UI element position
  followTarget,
}

class CommittedEvent {
  final String eventId;
  final String intent;
  final String assetPath;
  final String bus;
  final String presetId;
  final String voiceLimitGroup;
  final VariationPolicy variationPolicy;
  final List<String> tags;
  final Map<String, dynamic> parameters;
  final PreloadPolicy preloadPolicy;
  final DateTime createdAt;
  final DateTime? modifiedAt;

  /// Action type (Play, Stop, Pause, etc.)
  final ActionType actionType;

  /// Stop target (for Stop actions — which bus/event to stop)
  final String? stopTarget;

  /// Spatial panning (-1.0 = left, 0.0 = center, 1.0 = right)
  final double pan;

  /// Spatial mode (how pan is determined)
  final SpatialMode spatialMode;

  /// Event dependencies (D.1)
  final List<EventDependency> dependencies;

  /// Conditional trigger (D.2)
  final ConditionalTrigger? conditionalTrigger;

  /// RTPC bindings (D.3)
  final List<RtpcBinding> rtpcBindings;

  /// Music crossfade config (D.7) - for music events
  final MusicCrossfadeConfig? crossfadeConfig;

  const CommittedEvent({
    required this.eventId,
    required this.intent,
    required this.assetPath,
    required this.bus,
    required this.presetId,
    this.voiceLimitGroup = 'default',
    this.variationPolicy = VariationPolicy.random,
    this.tags = const [],
    this.parameters = const {},
    this.preloadPolicy = PreloadPolicy.onStageEnter,
    required this.createdAt,
    this.modifiedAt,
    this.actionType = ActionType.play,
    this.stopTarget,
    this.pan = 0.0,
    this.spatialMode = SpatialMode.none,
    this.dependencies = const [],
    this.conditionalTrigger,
    this.rtpcBindings = const [],
    this.crossfadeConfig,
  });

  CommittedEvent copyWith({
    String? eventId,
    String? intent,
    String? assetPath,
    String? bus,
    String? presetId,
    String? voiceLimitGroup,
    VariationPolicy? variationPolicy,
    List<String>? tags,
    Map<String, dynamic>? parameters,
    PreloadPolicy? preloadPolicy,
    DateTime? createdAt,
    DateTime? modifiedAt,
    ActionType? actionType,
    String? stopTarget,
    double? pan,
    SpatialMode? spatialMode,
    List<EventDependency>? dependencies,
    ConditionalTrigger? conditionalTrigger,
    List<RtpcBinding>? rtpcBindings,
    MusicCrossfadeConfig? crossfadeConfig,
  }) {
    return CommittedEvent(
      eventId: eventId ?? this.eventId,
      intent: intent ?? this.intent,
      assetPath: assetPath ?? this.assetPath,
      bus: bus ?? this.bus,
      presetId: presetId ?? this.presetId,
      voiceLimitGroup: voiceLimitGroup ?? this.voiceLimitGroup,
      variationPolicy: variationPolicy ?? this.variationPolicy,
      tags: tags ?? this.tags,
      parameters: parameters ?? this.parameters,
      preloadPolicy: preloadPolicy ?? this.preloadPolicy,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      actionType: actionType ?? this.actionType,
      stopTarget: stopTarget ?? this.stopTarget,
      pan: pan ?? this.pan,
      spatialMode: spatialMode ?? this.spatialMode,
      dependencies: dependencies ?? this.dependencies,
      conditionalTrigger: conditionalTrigger ?? this.conditionalTrigger,
      rtpcBindings: rtpcBindings ?? this.rtpcBindings,
      crossfadeConfig: crossfadeConfig ?? this.crossfadeConfig,
    );
  }

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'intent': intent,
    'assetPath': assetPath,
    'bus': bus,
    'presetId': presetId,
    'voiceLimitGroup': voiceLimitGroup,
    'variationPolicy': variationPolicy.name,
    'tags': tags,
    'parameters': parameters,
    'preloadPolicy': preloadPolicy.name,
    'createdAt': createdAt.toIso8601String(),
    if (modifiedAt != null) 'modifiedAt': modifiedAt!.toIso8601String(),
    'actionType': actionType.name,
    if (stopTarget != null) 'stopTarget': stopTarget,
    'pan': pan,
    'spatialMode': spatialMode.name,
    if (dependencies.isNotEmpty) 'dependencies': dependencies.map((d) => d.toJson()).toList(),
    if (conditionalTrigger != null) 'conditionalTrigger': conditionalTrigger!.toJson(),
    if (rtpcBindings.isNotEmpty) 'rtpcBindings': rtpcBindings.map((r) => r.toJson()).toList(),
    if (crossfadeConfig != null) 'crossfadeConfig': crossfadeConfig!.toJson(),
  };

  factory CommittedEvent.fromJson(Map<String, dynamic> json) => CommittedEvent(
    eventId: json['eventId'] as String,
    intent: json['intent'] as String,
    assetPath: json['assetPath'] as String,
    bus: json['bus'] as String,
    presetId: json['presetId'] as String,
    voiceLimitGroup: json['voiceLimitGroup'] as String? ?? 'default',
    variationPolicy: VariationPolicyExtension.fromString(json['variationPolicy'] as String? ?? 'random'),
    tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
    parameters: (json['parameters'] as Map<String, dynamic>?) ?? {},
    preloadPolicy: PreloadPolicyExtension.fromString(json['preloadPolicy'] as String? ?? 'on_stage_enter'),
    createdAt: DateTime.parse(json['createdAt'] as String),
    modifiedAt: json['modifiedAt'] != null ? DateTime.parse(json['modifiedAt'] as String) : null,
    actionType: _actionTypeFromString(json['actionType'] as String?),
    stopTarget: json['stopTarget'] as String?,
    pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
    spatialMode: _spatialModeFromString(json['spatialMode'] as String?),
    dependencies: (json['dependencies'] as List<dynamic>?)
        ?.map((d) => EventDependency.fromJson(d as Map<String, dynamic>))
        .toList() ?? [],
    conditionalTrigger: json['conditionalTrigger'] != null
        ? ConditionalTrigger.fromJson(json['conditionalTrigger'] as Map<String, dynamic>)
        : null,
    rtpcBindings: (json['rtpcBindings'] as List<dynamic>?)
        ?.map((r) => RtpcBinding.fromJson(r as Map<String, dynamic>))
        .toList() ?? [],
    crossfadeConfig: json['crossfadeConfig'] != null
        ? MusicCrossfadeConfig.fromJson(json['crossfadeConfig'] as Map<String, dynamic>)
        : null,
  );

  static SpatialMode _spatialModeFromString(String? s) {
    switch (s) {
      case 'fixed': return SpatialMode.fixed;
      case 'autoPerReel': return SpatialMode.autoPerReel;
      case 'followTarget': return SpatialMode.followTarget;
      default: return SpatialMode.none;
    }
  }

  static ActionType _actionTypeFromString(String? s) {
    if (s == null) return ActionType.play;
    try {
      return ActionType.values.firstWhere((e) => e.name == s);
    } catch (_) {
      return ActionType.play;
    }
  }
}

// =============================================================================
// EVENT BINDING
// =============================================================================

/// Binding between event and target
class EventBinding {
  final String bindingId;
  final String eventId;
  final String targetId;
  final String stageId;
  final String trigger;
  final Map<String, dynamic> paramOverrides;
  final bool enabled;

  const EventBinding({
    required this.bindingId,
    required this.eventId,
    required this.targetId,
    required this.stageId,
    required this.trigger,
    this.paramOverrides = const {},
    this.enabled = true,
  });

  EventBinding copyWith({
    String? bindingId,
    String? eventId,
    String? targetId,
    String? stageId,
    String? trigger,
    Map<String, dynamic>? paramOverrides,
    bool? enabled,
  }) {
    return EventBinding(
      bindingId: bindingId ?? this.bindingId,
      eventId: eventId ?? this.eventId,
      targetId: targetId ?? this.targetId,
      stageId: stageId ?? this.stageId,
      trigger: trigger ?? this.trigger,
      paramOverrides: paramOverrides ?? this.paramOverrides,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'bindingId': bindingId,
    'eventId': eventId,
    'targetId': targetId,
    'stageId': stageId,
    'trigger': trigger,
    'paramOverrides': paramOverrides,
    'enabled': enabled,
  };

  factory EventBinding.fromJson(Map<String, dynamic> json) => EventBinding(
    bindingId: json['bindingId'] as String,
    eventId: json['eventId'] as String,
    targetId: json['targetId'] as String,
    stageId: json['stageId'] as String,
    trigger: json['trigger'] as String,
    paramOverrides: (json['paramOverrides'] as Map<String, dynamic>?) ?? {},
    enabled: json['enabled'] as bool? ?? true,
  );
}

// =============================================================================
// DROP RULE
// =============================================================================

/// Rule for auto-matching assets to events
class DropRule {
  final String ruleId;
  final String name;
  final int priority;

  // Match conditions
  final List<String> assetTags;
  final List<String> targetTags;
  final AssetType? assetType;
  final TargetType? targetType;

  // Output template
  final String eventIdTemplate;
  final String intentTemplate;
  final String defaultPresetId;
  final String defaultBus;
  final String defaultTrigger;

  const DropRule({
    required this.ruleId,
    required this.name,
    this.priority = 50,
    this.assetTags = const [],
    this.targetTags = const [],
    this.assetType,
    this.targetType,
    required this.eventIdTemplate,
    required this.intentTemplate,
    required this.defaultPresetId,
    required this.defaultBus,
    required this.defaultTrigger,
  });

  /// Check if rule matches asset and target
  bool matches(AudioAsset asset, DropTarget target) {
    // Check asset type if specified
    if (assetType != null && asset.assetType != assetType) {
      return false;
    }

    // Check target type if specified
    if (targetType != null && target.targetType != targetType) {
      return false;
    }

    // Check asset tags (any match)
    if (assetTags.isNotEmpty && !asset.hasAnyTag(assetTags)) {
      return false;
    }

    // Check target tags (any match)
    if (targetTags.isNotEmpty && !target.hasAnyTag(targetTags)) {
      return false;
    }

    return true;
  }

  /// Generate event ID from template
  String generateEventId(AudioAsset asset, DropTarget target) {
    return eventIdTemplate
        .replaceAll('{target}', target.targetId)
        .replaceAll('{asset}', asset.displayName.toLowerCase())
        .replaceAll('{type}', asset.assetType.name);
  }

  /// Generate intent from template
  String generateIntent(AudioAsset asset, DropTarget target) {
    return intentTemplate
        .replaceAll('{target}', target.targetId)
        .replaceAll('{asset}', asset.displayName.toLowerCase())
        .replaceAll('{type}', asset.assetType.name);
  }
}

// =============================================================================
// STANDARD DROP RULES
// =============================================================================

/// Built-in drop rules for common scenarios
class StandardDropRules {
  static const uiPrimaryClick = DropRule(
    ruleId: 'ui_primary_click',
    name: 'UI Primary Click',
    priority: 100,
    assetTags: ['click', 'press'],
    targetTags: ['primary', 'cta'],
    targetType: TargetType.uiButton,
    eventIdTemplate: '{target}.click_primary',
    intentTemplate: '{target}.clicked',
    defaultPresetId: 'ui_click_primary',
    defaultBus: 'SFX/UI',
    defaultTrigger: 'press',
  );

  static const uiSecondaryClick = DropRule(
    ruleId: 'ui_secondary_click',
    name: 'UI Secondary Click',
    priority: 90,
    assetTags: ['click'],
    targetType: TargetType.uiButton,
    eventIdTemplate: '{target}.click_secondary',
    intentTemplate: '{target}.clicked',
    defaultPresetId: 'ui_click_secondary',
    defaultBus: 'SFX/UI',
    defaultTrigger: 'press',
  );

  static const uiHover = DropRule(
    ruleId: 'ui_hover',
    name: 'UI Hover',
    priority: 80,
    assetTags: ['hover', 'whoosh'],
    targetType: TargetType.uiButton,
    eventIdTemplate: '{target}.hover',
    intentTemplate: '{target}.hovered',
    defaultPresetId: 'ui_hover',
    defaultBus: 'SFX/UI',
    defaultTrigger: 'hover',
  );

  static const reelSpin = DropRule(
    ruleId: 'reel_spin',
    name: 'Reel Spin',
    priority: 100,
    assetTags: ['spin', 'loop', 'reel'],
    targetType: TargetType.reelSurface,
    eventIdTemplate: 'reel.spin',
    intentTemplate: 'reels.spinning',
    defaultPresetId: 'reel_spin',
    defaultBus: 'SFX/Reels',
    defaultTrigger: 'spin_start',
  );

  static const reelStop = DropRule(
    ruleId: 'reel_stop',
    name: 'Reel Stop',
    priority: 100,
    assetTags: ['stop', 'impact', 'reel'],
    targetType: TargetType.reelStopZone,
    eventIdTemplate: '{target}.stop',
    intentTemplate: 'reel.stopped',
    defaultPresetId: 'reel_stop',
    defaultBus: 'SFX/Reels',
    defaultTrigger: 'reel_stop',
  );

  static const anticipation = DropRule(
    ruleId: 'anticipation',
    name: 'Anticipation',
    priority: 100,
    assetTags: ['anticipation'],
    eventIdTemplate: 'anticipation.{target}',
    intentTemplate: 'anticipation.active',
    defaultPresetId: 'anticipation',
    defaultBus: 'SFX/Features',
    defaultTrigger: 'anticipation_on',
  );

  static const winSmall = DropRule(
    ruleId: 'win_small',
    name: 'Small Win',
    priority: 90,
    assetTags: ['win'],
    targetType: TargetType.overlay,
    targetTags: ['win'],
    eventIdTemplate: 'win.small',
    intentTemplate: 'win.presented',
    defaultPresetId: 'win_small',
    defaultBus: 'SFX/Wins',
    defaultTrigger: 'show',
  );

  static const winBig = DropRule(
    ruleId: 'win_big',
    name: 'Big Win',
    priority: 100,
    assetTags: ['bigwin', 'fanfare'],
    targetType: TargetType.overlay,
    eventIdTemplate: 'win.big',
    intentTemplate: 'bigwin.presented',
    defaultPresetId: 'win_big',
    defaultBus: 'SFX/Wins',
    defaultTrigger: 'show',
  );

  static const musicBase = DropRule(
    ruleId: 'music_base',
    name: 'Base Music',
    priority: 100,
    assetType: AssetType.music,
    assetTags: ['loop'],
    eventIdTemplate: 'music.base',
    intentTemplate: 'music.base.playing',
    defaultPresetId: 'music_base',
    defaultBus: 'MUSIC/Base',
    defaultTrigger: 'activate',
  );

  static const musicFeature = DropRule(
    ruleId: 'music_feature',
    name: 'Feature Music',
    priority: 100,
    assetType: AssetType.music,
    assetTags: ['feature', 'freespin', 'bonus'],
    eventIdTemplate: 'music.feature',
    intentTemplate: 'music.feature.playing',
    defaultPresetId: 'music_feature',
    defaultBus: 'MUSIC/Feature',
    defaultTrigger: 'enter',
  );

  static const fallbackSfx = DropRule(
    ruleId: 'fallback_sfx',
    name: 'Fallback SFX',
    priority: 1,
    assetType: AssetType.sfx,
    eventIdTemplate: '{target}.{asset}',
    intentTemplate: '{target}.triggered',
    defaultPresetId: 'ui_click_secondary',
    defaultBus: 'SFX',
    defaultTrigger: 'press',
  );

  // ==========================================================================
  // SYMBOL DROP RULES — V9: Audio for symbol lands and wins
  // ==========================================================================

  static const wildSymbol = DropRule(
    ruleId: 'wild_symbol',
    name: 'Wild Symbol Land',
    priority: 100,
    targetType: TargetType.symbolZone,
    targetTags: ['wild'],
    eventIdTemplate: 'symbol.wild.land',
    intentTemplate: 'wild.landed',
    defaultPresetId: 'symbol_land',
    defaultBus: 'SFX/Symbols',
    defaultTrigger: 'WILD_LAND',
  );

  static const scatterSymbol = DropRule(
    ruleId: 'scatter_symbol',
    name: 'Scatter Symbol Land',
    priority: 100,
    targetType: TargetType.symbolZone,
    targetTags: ['scatter'],
    eventIdTemplate: 'symbol.scatter.land',
    intentTemplate: 'scatter.landed',
    defaultPresetId: 'symbol_land',
    defaultBus: 'SFX/Symbols',
    defaultTrigger: 'SCATTER_LAND',
  );

  static const bonusSymbol = DropRule(
    ruleId: 'bonus_symbol',
    name: 'Bonus Symbol Land',
    priority: 100,
    targetType: TargetType.symbolZone,
    targetTags: ['bonus'],
    eventIdTemplate: 'symbol.bonus.land',
    intentTemplate: 'bonus.landed',
    defaultPresetId: 'symbol_land',
    defaultBus: 'SFX/Features',
    defaultTrigger: 'BONUS_TRIGGER',
  );

  static const symbolWin = DropRule(
    ruleId: 'symbol_win',
    name: 'Symbol Win Presentation',
    priority: 100,
    targetType: TargetType.symbolZone,
    targetTags: ['win'],
    eventIdTemplate: 'symbol.win.present',
    intentTemplate: 'symbol.win.presented',
    defaultPresetId: 'win_small',
    defaultBus: 'SFX/Wins',
    defaultTrigger: 'WIN_SYMBOL_HIGHLIGHT',
  );

  static const highPaySymbol = DropRule(
    ruleId: 'high_pay_symbol',
    name: 'High Pay Symbol Land',
    priority: 90,
    targetType: TargetType.symbolZone,
    targetTags: ['hp1', 'hp2', 'hp3', 'hp4', 'hp5'],
    eventIdTemplate: 'symbol.{target}.land',
    intentTemplate: 'symbol.high_pay.landed',
    defaultPresetId: 'symbol_land',
    defaultBus: 'SFX/Symbols',
    defaultTrigger: 'SYMBOL_LAND',
  );

  static const mediumPaySymbol = DropRule(
    ruleId: 'medium_pay_symbol',
    name: 'Medium Pay Symbol Land',
    priority: 85,
    targetType: TargetType.symbolZone,
    targetTags: ['mp1', 'mp2', 'mp3', 'mp4', 'mp5'],
    eventIdTemplate: 'symbol.{target}.land',
    intentTemplate: 'symbol.medium_pay.landed',
    defaultPresetId: 'symbol_land',
    defaultBus: 'SFX/Symbols',
    defaultTrigger: 'SYMBOL_LAND',
  );

  static const lowPaySymbol = DropRule(
    ruleId: 'low_pay_symbol',
    name: 'Low Pay Symbol Land',
    priority: 80,
    targetType: TargetType.symbolZone,
    targetTags: ['lp1', 'lp2', 'lp3', 'lp4', 'lp5'],
    eventIdTemplate: 'symbol.{target}.land',
    intentTemplate: 'symbol.low_pay.landed',
    defaultPresetId: 'symbol_land',
    defaultBus: 'SFX/Symbols',
    defaultTrigger: 'SYMBOL_LAND',
  );

  // ==========================================================================
  // WIN LINE DROP RULES — V9: Audio for win line presentation
  // ==========================================================================

  static const winLineShow = DropRule(
    ruleId: 'win_line_show',
    name: 'Win Line Show',
    priority: 100,
    targetType: TargetType.overlay,
    targetTags: ['line', 'win'],
    eventIdTemplate: 'winline.{target}.show',
    intentTemplate: 'winline.showed',
    defaultPresetId: 'win_line',
    defaultBus: 'SFX/Wins',
    defaultTrigger: 'WIN_LINE_SHOW',
  );

  // ==========================================================================
  // ROLLUP COUNTER DROP RULES — V9: Audio for win counter
  // ==========================================================================

  static const rollupTick = DropRule(
    ruleId: 'rollup_tick',
    name: 'Rollup Counter Tick',
    priority: 100,
    targetType: TargetType.hudMeter,
    targetTags: ['rollup', 'tick', 'counter'],
    eventIdTemplate: 'rollup.tick',
    intentTemplate: 'counter.ticked',
    defaultPresetId: 'ui_tick',
    defaultBus: 'SFX/Wins',
    defaultTrigger: 'ROLLUP_TICK',
  );

  static const rollupEnd = DropRule(
    ruleId: 'rollup_end',
    name: 'Rollup Counter End',
    priority: 100,
    targetType: TargetType.hudMeter,
    targetTags: ['rollup', 'end', 'counter'],
    eventIdTemplate: 'rollup.end',
    intentTemplate: 'counter.ended',
    defaultPresetId: 'win_small',
    defaultBus: 'SFX/Wins',
    defaultTrigger: 'ROLLUP_END',
  );

  /// All standard rules sorted by priority (highest first)
  static List<DropRule> get all => [
    uiPrimaryClick,
    uiSecondaryClick,
    uiHover,
    reelSpin,
    reelStop,
    anticipation,
    winSmall,
    winBig,
    musicBase,
    musicFeature,
    // V9: Symbol and win line rules
    wildSymbol,
    scatterSymbol,
    bonusSymbol,
    symbolWin,
    highPaySymbol,
    mediumPaySymbol,
    lowPaySymbol,
    winLineShow,
    // V9: Rollup counter rules
    rollupTick,
    rollupEnd,
    // Fallback last
    fallbackSfx,
  ]..sort((a, b) => b.priority.compareTo(a.priority));
}

// =============================================================================
// AUTO EVENT BUILDER PROVIDER
// =============================================================================

/// Main provider for Auto Event Builder
class AutoEventBuilderProvider extends ChangeNotifier {
  // Current draft
  EventDraft? _currentDraft;

  // Committed events and bindings
  final List<CommittedEvent> _events = [];
  final List<EventBinding> _bindings = [];

  // Available presets (standard + custom)
  final List<EventPreset> _presets = [...StandardPresets.all];

  // Drop rules (standard + custom)
  final List<DropRule> _rules = [...StandardDropRules.all];

  // Undo/redo stacks
  final List<_UndoAction> _undoStack = [];
  final List<_UndoAction> _redoStack = [];

  // ID generation
  int _eventCounter = 0;
  int _bindingCounter = 0;

  // Audio assets library (imported audio files available for drag-drop)
  final List<AudioAsset> _audioAssets = [];

  // Multi-select state (C.7)
  final Set<String> _selectedAssetIds = {};

  // Recent assets (C.8)
  final List<String> _recentAssetIds = [];
  static const int maxRecentAssets = 20;

  // ==========================================================================
  // GETTERS
  // ==========================================================================

  /// Current draft being edited
  EventDraft? get currentDraft => _currentDraft;

  /// All imported audio assets available for drag-drop
  List<AudioAsset> get audioAssets => List.unmodifiable(_audioAssets);

  /// All unique tags from audio assets
  List<String> get allAssetTags {
    final tags = <String>{};
    for (final asset in _audioAssets) {
      tags.addAll(asset.tags);
    }
    return tags.toList()..sort();
  }

  /// Whether there's an active draft
  bool get hasDraft => _currentDraft != null;

  /// All committed events
  List<CommittedEvent> get events => List.unmodifiable(_events);

  /// All bindings
  List<EventBinding> get bindings => List.unmodifiable(_bindings);

  /// Available presets
  List<EventPreset> get presets => List.unmodifiable(_presets);

  /// Can undo
  bool get canUndo => _undoStack.isNotEmpty;

  /// Can redo
  bool get canRedo => _redoStack.isNotEmpty;

  // ==========================================================================
  // DRAFT MANAGEMENT
  // ==========================================================================

  /// Create a new draft from asset drop on target
  EventDraft createDraft(AudioAsset asset, DropTarget target) {
    // Find matching rule
    final rule = _findMatchingRule(asset, target);

    // Generate semantic event name using EventNamingService (SL.5)
    // This creates names like "onUiPaSpinButton", "onReelStop0", "onFsTrigger"
    var eventId = EventNamingService.instance.generateEventName(
      target.targetId,
      rule.defaultTrigger,
    );

    // Ensure unique (GAP 26 FIX)
    eventId = _ensureUniqueEventId(eventId);

    // Auto-detect action type using AudioContextService
    // This analyzes the audio file name + stage to determine Play vs Stop
    final autoAction = AudioContextService.instance.determineAutoAction(
      audioPath: asset.path,
      stage: rule.defaultTrigger.toUpperCase(),
    );

    // Create draft
    _currentDraft = EventDraft(
      eventId: eventId,
      target: target,
      asset: asset,
      trigger: rule.defaultTrigger,
      bus: rule.defaultBus,
      presetId: rule.defaultPresetId,
      actionType: autoAction.actionType,
      stopTarget: autoAction.stopTarget,
      actionReason: autoAction.reason,
      stageContext: target.stageContext,
    );

    notifyListeners();
    return _currentDraft!;
  }

  /// Update current draft
  void updateDraft({
    String? trigger,
    String? presetId,
    ActionType? actionType,
    String? stopTarget,
    String? actionReason,
    StageContext? stageContext,
    VariationPolicy? variationPolicy,
    List<String>? tags,
    Map<String, dynamic>? paramOverrides,
  }) {
    if (_currentDraft == null) return;

    if (trigger != null) _currentDraft!.trigger = trigger;
    if (presetId != null) _currentDraft!.presetId = presetId;
    if (actionType != null) _currentDraft!.actionType = actionType;
    if (stopTarget != null) _currentDraft!.stopTarget = stopTarget;
    if (actionReason != null) _currentDraft!.actionReason = actionReason;
    if (stageContext != null) _currentDraft!.stageContext = stageContext;
    if (variationPolicy != null) _currentDraft!.variationPolicy = variationPolicy;
    if (tags != null) _currentDraft!.tags = tags;
    if (paramOverrides != null) _currentDraft!.paramOverrides = paramOverrides;

    _currentDraft!.markModified();
    notifyListeners();
  }

  /// Commit the current draft
  CommittedEvent? commitDraft() {
    if (_currentDraft == null) return null;

    final draft = _currentDraft!;

    // Get preset for parameters
    final preset = _presets.firstWhere(
      (p) => p.presetId == draft.presetId,
      orElse: () => StandardPresets.uiClickSecondary,
    );

    // Calculate spatial params (D.8: per-reel spatial auto)
    final (pan, spatialMode) = _calculateSpatialParams(draft.target);

    // Create committed event
    final event = CommittedEvent(
      eventId: draft.eventId,
      intent: '${draft.target.targetId}.${draft.trigger}',
      assetPath: draft.asset.path,
      bus: draft.bus,
      presetId: draft.presetId,
      voiceLimitGroup: preset.voiceLimitGroup,
      variationPolicy: draft.variationPolicy,
      tags: draft.tags,
      parameters: {...draft.paramOverrides},
      preloadPolicy: preset.preloadPolicy,
      createdAt: DateTime.now(),
      actionType: draft.actionType,
      stopTarget: draft.stopTarget,
      pan: pan,
      spatialMode: spatialMode,
    );

    // Create binding
    final binding = EventBinding(
      bindingId: 'bind_${++_bindingCounter}',
      eventId: draft.eventId,
      targetId: draft.target.targetId,
      stageId: draft.stageContext.name,
      trigger: draft.trigger,
      paramOverrides: draft.paramOverrides,
    );

    // Add to registry
    _events.add(event);
    _bindings.add(binding);

    // Add to undo stack
    _undoStack.add(_UndoAction(
      type: _UndoActionType.commit,
      event: event,
      binding: binding,
    ));
    _redoStack.clear();

    // Mark asset as recently used (C.8)
    markAssetUsed(draft.asset.assetId);

    // Clear draft
    _currentDraft = null;

    notifyListeners();
    return event;
  }

  /// Cancel the current draft
  void cancelDraft() {
    _currentDraft = null;
    notifyListeners();
  }

  // ==========================================================================
  // EVENT MANAGEMENT
  // ==========================================================================

  /// Delete an event and its bindings
  void deleteEvent(String eventId) {
    final event = _events.firstWhere((e) => e.eventId == eventId);
    final eventBindings = _bindings.where((b) => b.eventId == eventId).toList();

    _events.removeWhere((e) => e.eventId == eventId);
    _bindings.removeWhere((b) => b.eventId == eventId);

    // Add to undo stack
    _undoStack.add(_UndoAction(
      type: _UndoActionType.delete,
      event: event,
      bindings: eventBindings,
    ));
    _redoStack.clear();

    notifyListeners();
  }

  /// Get event count for a target
  int getEventCountForTarget(String targetId) {
    return _bindings.where((b) => b.targetId == targetId).length;
  }

  /// Get events for a target
  List<CommittedEvent> getEventsForTarget(String targetId) {
    final eventIds = _bindings
        .where((b) => b.targetId == targetId)
        .map((b) => b.eventId)
        .toSet();
    return _events.where((e) => eventIds.contains(e.eventId)).toList();
  }

  // ==========================================================================
  // UNDO/REDO
  // ==========================================================================

  /// Undo last action
  bool undo() {
    if (_undoStack.isEmpty) return false;

    final action = _undoStack.removeLast();

    switch (action.type) {
      case _UndoActionType.commit:
        // Remove the committed event and binding
        _events.removeWhere((e) => e.eventId == action.event!.eventId);
        _bindings.removeWhere((b) => b.bindingId == action.binding!.bindingId);
        break;

      case _UndoActionType.delete:
        // Restore the deleted event and bindings
        _events.add(action.event!);
        _bindings.addAll(action.bindings!);
        break;

      case _UndoActionType.update:
        // Swap current and previous state
        final currentEvent = _events.firstWhere((e) => e.eventId == action.event!.eventId);
        final index = _events.indexOf(currentEvent);
        _events[index] = action.previousEvent!;
        action.previousEvent = currentEvent;
        break;
    }

    _redoStack.add(action);
    notifyListeners();
    return true;
  }

  /// Redo last undone action
  bool redo() {
    if (_redoStack.isEmpty) return false;

    final action = _redoStack.removeLast();

    switch (action.type) {
      case _UndoActionType.commit:
        // Re-add the event and binding
        _events.add(action.event!);
        _bindings.add(action.binding!);
        break;

      case _UndoActionType.delete:
        // Re-delete the event and bindings
        _events.removeWhere((e) => e.eventId == action.event!.eventId);
        _bindings.removeWhere((b) => action.bindings!.any((ab) => ab.bindingId == b.bindingId));
        break;

      case _UndoActionType.update:
        // Swap current and previous state
        final currentEvent = _events.firstWhere((e) => e.eventId == action.event!.eventId);
        final index = _events.indexOf(currentEvent);
        _events[index] = action.previousEvent!;
        action.previousEvent = currentEvent;
        break;
    }

    _undoStack.add(action);
    notifyListeners();
    return true;
  }

  // ==========================================================================
  // PRESETS
  // ==========================================================================

  /// Add a custom preset
  void addPreset(EventPreset preset) {
    _presets.add(preset);
    notifyListeners();
  }

  /// Remove a custom preset
  void removePreset(String presetId) {
    _presets.removeWhere((p) => p.presetId == presetId);
    notifyListeners();
  }

  // ==========================================================================
  // RULES
  // ==========================================================================

  /// Add a custom rule
  void addRule(DropRule rule) {
    _rules.add(rule);
    _rules.sort((a, b) => b.priority.compareTo(a.priority));
    notifyListeners();
  }

  /// Remove a custom rule
  void removeRule(String ruleId) {
    _rules.removeWhere((r) => r.ruleId == ruleId);
    notifyListeners();
  }

  // ==========================================================================
  // AUDIO ASSET MANAGEMENT
  // ==========================================================================

  /// Add an audio asset to the library
  void addAudioAsset(AudioAsset asset) {
    // Avoid duplicates by path
    if (_audioAssets.any((a) => a.path == asset.path)) return;
    _audioAssets.add(asset);
    notifyListeners();
  }

  /// Add multiple audio assets
  void addAudioAssets(List<AudioAsset> assets) {
    for (final asset in assets) {
      if (!_audioAssets.any((a) => a.path == asset.path)) {
        _audioAssets.add(asset);
      }
    }
    notifyListeners();
  }

  /// Remove an audio asset from the library
  void removeAudioAsset(String assetId) {
    _audioAssets.removeWhere((a) => a.assetId == assetId);
    notifyListeners();
  }

  /// Clear all audio assets
  void clearAudioAssets() {
    _audioAssets.clear();
    notifyListeners();
  }

  /// Get audio asset by ID
  AudioAsset? getAudioAsset(String assetId) {
    try {
      return _audioAssets.firstWhere((a) => a.assetId == assetId);
    } catch (_) {
      return null;
    }
  }

  /// Get audio assets by type
  List<AudioAsset> getAssetsByType(AssetType type) {
    return _audioAssets.where((a) => a.assetType == type).toList();
  }

  /// Get audio assets by tag
  List<AudioAsset> getAssetsByTag(String tag) {
    return _audioAssets.where((a) => a.tags.contains(tag)).toList();
  }

  // ==========================================================================
  // MULTI-SELECT (C.7)
  // ==========================================================================

  /// IDs of currently selected assets
  Set<String> get selectedAssetIds => Set.unmodifiable(_selectedAssetIds);

  /// Whether any assets are selected
  bool get hasSelection => _selectedAssetIds.isNotEmpty;

  /// Number of selected assets
  int get selectionCount => _selectedAssetIds.length;

  /// Get selected assets as list
  List<AudioAsset> get selectedAssets {
    return _audioAssets
        .where((a) => _selectedAssetIds.contains(a.assetId))
        .toList();
  }

  /// Check if asset is selected
  bool isAssetSelected(String assetId) => _selectedAssetIds.contains(assetId);

  /// Toggle asset selection
  void toggleAssetSelection(String assetId) {
    if (_selectedAssetIds.contains(assetId)) {
      _selectedAssetIds.remove(assetId);
    } else {
      _selectedAssetIds.add(assetId);
    }
    notifyListeners();
  }

  /// Select asset (add to selection)
  void selectAsset(String assetId) {
    if (_selectedAssetIds.add(assetId)) {
      notifyListeners();
    }
  }

  /// Deselect asset
  void deselectAsset(String assetId) {
    if (_selectedAssetIds.remove(assetId)) {
      notifyListeners();
    }
  }

  /// Select multiple assets
  void selectAssets(Iterable<String> assetIds) {
    final before = _selectedAssetIds.length;
    _selectedAssetIds.addAll(assetIds);
    if (_selectedAssetIds.length != before) {
      notifyListeners();
    }
  }

  /// Clear selection
  void clearSelection() {
    if (_selectedAssetIds.isNotEmpty) {
      _selectedAssetIds.clear();
      notifyListeners();
    }
  }

  /// Select all assets
  void selectAllAssets() {
    _selectedAssetIds.clear();
    for (final asset in _audioAssets) {
      _selectedAssetIds.add(asset.assetId);
    }
    notifyListeners();
  }

  /// Select assets by type
  void selectAssetsByType(AssetType type) {
    for (final asset in _audioAssets) {
      if (asset.assetType == type) {
        _selectedAssetIds.add(asset.assetId);
      }
    }
    notifyListeners();
  }

  // ==========================================================================
  // RECENT ASSETS (C.8)
  // ==========================================================================

  /// Recently used asset IDs (most recent first)
  List<String> get recentAssetIds => List.unmodifiable(_recentAssetIds);

  /// Get recent assets as AudioAsset list
  List<AudioAsset> get recentAssets {
    return _recentAssetIds
        .map((id) => _audioAssets.firstWhere(
              (a) => a.assetId == id,
              orElse: () => const AudioAsset(
                assetId: '_invalid_',
                path: '',
                assetType: AssetType.sfx,
                tags: [],
                durationMs: 0,
              ),
            ))
        .where((a) => a.path.isNotEmpty)
        .toList();
  }

  /// Mark asset as recently used (called on drop/commit)
  void markAssetUsed(String assetId) {
    _recentAssetIds.remove(assetId);
    _recentAssetIds.insert(0, assetId);
    if (_recentAssetIds.length > maxRecentAssets) {
      _recentAssetIds.removeLast();
    }
    notifyListeners();
  }

  /// Clear recent assets
  void clearRecentAssets() {
    _recentAssetIds.clear();
    notifyListeners();
  }

  // ==========================================================================
  // EVENT DEPENDENCIES (D.1)
  // ==========================================================================

  /// Add a dependency to an event
  void addEventDependency(String eventId, EventDependency dependency) {
    final index = _events.indexWhere((e) => e.eventId == eventId);
    if (index < 0) return;

    final event = _events[index];
    final newDeps = [...event.dependencies, dependency];
    final updated = event.copyWith(
      dependencies: newDeps,
      modifiedAt: DateTime.now(),
    );

    // Save for undo
    _undoStack.add(_UndoAction(
      type: _UndoActionType.update,
      event: updated,
      previousEvent: event,
    ));
    _redoStack.clear();

    _events[index] = updated;
    notifyListeners();
  }

  /// Remove a dependency from an event
  void removeEventDependency(String eventId, String targetEventId) {
    final index = _events.indexWhere((e) => e.eventId == eventId);
    if (index < 0) return;

    final event = _events[index];
    final newDeps = event.dependencies
        .where((d) => d.targetEventId != targetEventId)
        .toList();

    if (newDeps.length == event.dependencies.length) return;

    final updated = event.copyWith(
      dependencies: newDeps,
      modifiedAt: DateTime.now(),
    );

    _undoStack.add(_UndoAction(
      type: _UndoActionType.update,
      event: updated,
      previousEvent: event,
    ));
    _redoStack.clear();

    _events[index] = updated;
    notifyListeners();
  }

  /// Update a dependency
  void updateEventDependency(
    String eventId,
    String targetEventId,
    EventDependency newDependency,
  ) {
    final index = _events.indexWhere((e) => e.eventId == eventId);
    if (index < 0) return;

    final event = _events[index];
    final depIndex = event.dependencies
        .indexWhere((d) => d.targetEventId == targetEventId);
    if (depIndex < 0) return;

    final newDeps = [...event.dependencies];
    newDeps[depIndex] = newDependency;

    final updated = event.copyWith(
      dependencies: newDeps,
      modifiedAt: DateTime.now(),
    );

    _undoStack.add(_UndoAction(
      type: _UndoActionType.update,
      event: updated,
      previousEvent: event,
    ));
    _redoStack.clear();

    _events[index] = updated;
    notifyListeners();
  }

  /// Get events that depend on a given event
  List<CommittedEvent> getDependentEvents(String eventId) {
    return _events.where((e) =>
      e.dependencies.any((d) => d.targetEventId == eventId)
    ).toList();
  }

  /// Get events that a given event depends on
  List<CommittedEvent> getEventDependencies(String eventId) {
    final event = _events.firstWhere(
      (e) => e.eventId == eventId,
      orElse: () => throw ArgumentError('Event not found: $eventId'),
    );
    return event.dependencies
        .map((d) => _events.firstWhere(
              (e) => e.eventId == d.targetEventId,
              orElse: () => throw ArgumentError('Dependency not found: ${d.targetEventId}'),
            ))
        .toList();
  }

  /// Check for circular dependencies
  bool hasCircularDependency(String eventId, String targetEventId) {
    final visited = <String>{};
    bool dfs(String current) {
      if (current == eventId) return true;
      if (visited.contains(current)) return false;
      visited.add(current);

      final event = _events.firstWhere(
        (e) => e.eventId == current,
        orElse: () => throw ArgumentError('Event not found'),
      );
      return event.dependencies.any((d) => dfs(d.targetEventId));
    }
    return dfs(targetEventId);
  }

  // ==========================================================================
  // CONDITIONAL TRIGGERS (D.2)
  // ==========================================================================

  /// Set conditional trigger for an event
  void setConditionalTrigger(String eventId, ConditionalTrigger? trigger) {
    final index = _events.indexWhere((e) => e.eventId == eventId);
    if (index < 0) return;

    final event = _events[index];
    final updated = event.copyWith(
      conditionalTrigger: trigger,
      modifiedAt: DateTime.now(),
    );

    _undoStack.add(_UndoAction(
      type: _UndoActionType.update,
      event: updated,
      previousEvent: event,
    ));
    _redoStack.clear();

    _events[index] = updated;
    notifyListeners();
  }

  /// Add condition to event's conditional trigger
  void addTriggerCondition(String eventId, TriggerCondition condition) {
    final index = _events.indexWhere((e) => e.eventId == eventId);
    if (index < 0) return;

    final event = _events[index];
    final existingTrigger = event.conditionalTrigger ?? ConditionalTrigger(
      triggerId: '${eventId}_cond',
      name: 'Condition for $eventId',
    );

    final newConditions = [...existingTrigger.conditions, condition];
    final updated = event.copyWith(
      conditionalTrigger: existingTrigger.copyWith(conditions: newConditions),
      modifiedAt: DateTime.now(),
    );

    _undoStack.add(_UndoAction(
      type: _UndoActionType.update,
      event: updated,
      previousEvent: event,
    ));
    _redoStack.clear();

    _events[index] = updated;
    notifyListeners();
  }

  /// Remove condition from event's conditional trigger
  void removeTriggerCondition(String eventId, int conditionIndex) {
    final index = _events.indexWhere((e) => e.eventId == eventId);
    if (index < 0) return;

    final event = _events[index];
    if (event.conditionalTrigger == null) return;

    final newConditions = [...event.conditionalTrigger!.conditions];
    if (conditionIndex >= newConditions.length) return;
    newConditions.removeAt(conditionIndex);

    final updated = event.copyWith(
      conditionalTrigger: event.conditionalTrigger!.copyWith(conditions: newConditions),
      modifiedAt: DateTime.now(),
    );

    _undoStack.add(_UndoAction(
      type: _UndoActionType.update,
      event: updated,
      previousEvent: event,
    ));
    _redoStack.clear();

    _events[index] = updated;
    notifyListeners();
  }

  /// Evaluate if event should trigger based on conditions
  bool evaluateEventConditions(String eventId, Map<String, dynamic> params) {
    final event = _events.firstWhere(
      (e) => e.eventId == eventId,
      orElse: () => throw ArgumentError('Event not found: $eventId'),
    );
    if (event.conditionalTrigger == null) return true;
    return event.conditionalTrigger!.evaluate(params);
  }

  // ==========================================================================
  // RTPC BINDINGS (D.3)
  // ==========================================================================

  /// Add RTPC binding to an event
  void addRtpcBinding(String eventId, RtpcBinding binding) {
    final index = _events.indexWhere((e) => e.eventId == eventId);
    if (index < 0) return;

    final event = _events[index];

    // Check for duplicate binding (same RTPC → same param)
    if (event.rtpcBindings.any((b) =>
        b.rtpcName == binding.rtpcName && b.eventParam == binding.eventParam)) {
      return;
    }

    final newBindings = [...event.rtpcBindings, binding];
    final updated = event.copyWith(
      rtpcBindings: newBindings,
      modifiedAt: DateTime.now(),
    );

    _undoStack.add(_UndoAction(
      type: _UndoActionType.update,
      event: updated,
      previousEvent: event,
    ));
    _redoStack.clear();

    _events[index] = updated;
    notifyListeners();
  }

  /// Remove RTPC binding from an event
  void removeRtpcBinding(String eventId, String rtpcName, String eventParam) {
    final index = _events.indexWhere((e) => e.eventId == eventId);
    if (index < 0) return;

    final event = _events[index];
    final newBindings = event.rtpcBindings
        .where((b) => !(b.rtpcName == rtpcName && b.eventParam == eventParam))
        .toList();

    if (newBindings.length == event.rtpcBindings.length) return;

    final updated = event.copyWith(
      rtpcBindings: newBindings,
      modifiedAt: DateTime.now(),
    );

    _undoStack.add(_UndoAction(
      type: _UndoActionType.update,
      event: updated,
      previousEvent: event,
    ));
    _redoStack.clear();

    _events[index] = updated;
    notifyListeners();
  }

  /// Update RTPC binding
  void updateRtpcBinding(
    String eventId,
    String rtpcName,
    String eventParam,
    RtpcBinding newBinding,
  ) {
    final index = _events.indexWhere((e) => e.eventId == eventId);
    if (index < 0) return;

    final event = _events[index];
    final bindingIndex = event.rtpcBindings.indexWhere(
      (b) => b.rtpcName == rtpcName && b.eventParam == eventParam,
    );
    if (bindingIndex < 0) return;

    final newBindings = [...event.rtpcBindings];
    newBindings[bindingIndex] = newBinding;

    final updated = event.copyWith(
      rtpcBindings: newBindings,
      modifiedAt: DateTime.now(),
    );

    _undoStack.add(_UndoAction(
      type: _UndoActionType.update,
      event: updated,
      previousEvent: event,
    ));
    _redoStack.clear();

    _events[index] = updated;
    notifyListeners();
  }

  /// Get modulated event parameters based on RTPC values
  Map<String, double> getModulatedParams(
    String eventId,
    Map<String, double> rtpcValues,
  ) {
    final event = _events.firstWhere(
      (e) => e.eventId == eventId,
      orElse: () => throw ArgumentError('Event not found: $eventId'),
    );

    final result = <String, double>{};
    for (final binding in event.rtpcBindings) {
      final rtpcValue = rtpcValues[binding.rtpcName];
      if (rtpcValue != null) {
        result[binding.eventParam] = binding.map(rtpcValue);
      }
    }
    return result;
  }

  // ==========================================================================
  // MUSIC CROSSFADE (D.7)
  // ==========================================================================

  /// Set crossfade config for a music event
  void setMusicCrossfadeConfig(String eventId, MusicCrossfadeConfig? config) {
    final index = _events.indexWhere((e) => e.eventId == eventId);
    if (index < 0) return;

    final event = _events[index];
    final updated = event.copyWith(
      crossfadeConfig: config,
      modifiedAt: DateTime.now(),
    );

    _undoStack.add(_UndoAction(
      type: _UndoActionType.update,
      event: updated,
      previousEvent: event,
    ));
    _redoStack.clear();

    _events[index] = updated;
    notifyListeners();
  }

  /// Get music events with crossfade configs
  List<CommittedEvent> getMusicEventsWithCrossfade() {
    return _events.where((e) => e.crossfadeConfig != null).toList();
  }

  // ==========================================================================
  // TEMPLATE INHERITANCE (D.4)
  // ==========================================================================

  /// Preset inheritance resolver
  final PresetInheritanceResolver _inheritanceResolver = PresetInheritanceResolver();

  /// Get inheritance resolver
  PresetInheritanceResolver get inheritanceResolver => _inheritanceResolver;

  /// Register an inheritable preset
  void registerInheritablePreset(InheritablePreset preset) {
    // Validate before registering
    if (preset.extendsPresetId != null) {
      if (_inheritanceResolver.hasCircularInheritance(preset.presetId, proposedParentId: preset.extendsPresetId)) {
        throw ArgumentError('Circular inheritance detected for ${preset.presetId}');
      }
      final parent = _inheritanceResolver.getPreset(preset.extendsPresetId!);
      if (parent == null) {
        throw ArgumentError('Parent preset not found: ${preset.extendsPresetId}');
      }
      if (parent.isSealed) {
        throw ArgumentError('Cannot extend sealed preset: ${preset.extendsPresetId}');
      }
    }

    _inheritanceResolver.register(preset);

    // Also add as legacy EventPreset for backward compatibility
    final eventPreset = preset.toEventPreset();
    if (!_presets.any((p) => p.presetId == eventPreset.presetId)) {
      _presets.add(eventPreset);
    }

    notifyListeners();
  }

  /// Unregister an inheritable preset
  void unregisterInheritablePreset(String presetId) {
    // Check for children first
    final children = _inheritanceResolver.getDirectChildren(presetId);
    if (children.isNotEmpty) {
      throw ArgumentError(
        'Cannot remove preset with children. '
        'Children: ${children.map((c) => c.presetId).join(", ")}'
      );
    }

    _inheritanceResolver.unregister(presetId);
    _presets.removeWhere((p) => p.presetId == presetId);
    notifyListeners();
  }

  /// Create inheritable preset from legacy preset
  InheritablePreset createInheritablePreset(EventPreset preset, {String? parentId}) {
    final inheritable = InheritablePreset.fromEventPreset(preset).copyWith(
      extendsPresetId: parentId,
    );
    registerInheritablePreset(inheritable);
    return inheritable;
  }

  /// Update inheritable preset
  void updateInheritablePreset(InheritablePreset preset) {
    // Remove old and add new
    _inheritanceResolver.unregister(preset.presetId);
    registerInheritablePreset(preset.copyWith(modifiedAt: DateTime.now()));
  }

  /// Get resolved parameters for preset (with inheritance)
  Map<String, dynamic> getResolvedPresetParameters(String presetId) {
    return _inheritanceResolver.resolveParameters(presetId);
  }

  /// Get inheritance chain for preset
  List<String> getPresetInheritanceChain(String presetId) {
    return _inheritanceResolver.resolveInheritanceChain(presetId);
  }

  /// Get preset children
  List<InheritablePreset> getPresetChildren(String presetId) {
    return _inheritanceResolver.getDirectChildren(presetId);
  }

  /// Get all preset descendants
  List<InheritablePreset> getPresetDescendants(String presetId) {
    return _inheritanceResolver.getAllDescendants(presetId);
  }

  /// Validate preset inheritance
  List<String> validatePresetInheritance(String presetId) {
    return _inheritanceResolver.validateInheritance(presetId);
  }

  /// Get presets by category
  List<InheritablePreset> getPresetsByCategory(String category) {
    return _inheritanceResolver.getPresetsByCategory(category);
  }

  /// Get all preset categories
  List<String> getAllPresetCategories() {
    return _inheritanceResolver.getAllCategories();
  }

  /// Get inheritance tree for UI display
  List<({InheritablePreset preset, int depth, bool hasChildren})> getPresetTree() {
    return _inheritanceResolver.toFlatTree();
  }

  /// Check if preset can be used directly (not abstract)
  bool canUsePresetDirectly(String presetId) {
    final preset = _inheritanceResolver.getPreset(presetId);
    return preset != null && !preset.isAbstract;
  }

  // ==========================================================================
  // BATCH DROP (D.5)
  // ==========================================================================

  /// Execute batch drop of asset to multiple targets
  BatchDropResult executeBatchDrop(
    AudioAsset asset,
    BatchDropConfig config, {
    int reelCount = 5,
  }) {
    final targetIds = config.getTargetIds(reelCount: reelCount);
    final events = <CommittedEvent>[];
    final newBindings = <EventBinding>[];
    final errors = <String>[];

    String? previousEventId;

    for (var i = 0; i < targetIds.length; i++) {
      final targetId = targetIds[i];

      try {
        // Calculate spatial pan
        final pan = config.spatialMode == SpatialDistributionMode.custom
            ? config.getPanForTarget(targetId) ?? 0.0
            : config.getPanForIndex(i, targetIds.length);

        // Create target
        final target = _createTargetFromId(targetId);

        // Find matching rule
        final rule = _findMatchingRule(asset, target);

        // Generate event ID
        var eventId = '${config.eventIdPrefix}_$i';
        eventId = _ensureUniqueEventId(eventId);

        // Get preset
        final presetId = config.presetId ?? rule.defaultPresetId;
        final preset = _presets.firstWhere(
          (p) => p.presetId == presetId,
          orElse: () => StandardPresets.uiClickSecondary,
        );

        // Calculate varied parameters
        final parameters = <String, dynamic>{};
        for (final range in config.variationRanges) {
          final baseValue = _getPresetParamValue(preset, range.paramName);
          if (baseValue != null) {
            parameters[range.paramName] = range.calculateVariation(
              baseValue,
              i,
              targetIds.length,
              config.variationMode,
            );
          }
        }

        // Add stagger delay
        final delay = config.staggerMs * i;
        if (delay > 0) {
          parameters['delayMs'] = (parameters['delayMs'] as int? ?? 0) + delay;
        }

        // Create dependencies
        final dependencies = <EventDependency>[];
        if (config.createDependencies && previousEventId != null) {
          dependencies.add(EventDependency(
            targetEventId: previousEventId,
            type: config.dependencyType,
            delayMs: config.staggerMs,
          ));
        }

        // Create event
        final event = CommittedEvent(
          eventId: eventId,
          intent: '${target.targetId}.${rule.defaultTrigger}',
          assetPath: asset.path,
          bus: rule.defaultBus,
          presetId: presetId,
          voiceLimitGroup: config.voiceLimitGroup,
          variationPolicy: VariationPolicy.random,
          tags: [config.eventIdPrefix, 'batch'],
          parameters: parameters,
          preloadPolicy: preset.preloadPolicy,
          createdAt: DateTime.now(),
          pan: pan,
          spatialMode: SpatialMode.fixed,
          dependencies: dependencies,
        );

        // Create binding
        final binding = EventBinding(
          bindingId: 'bind_${++_bindingCounter}',
          eventId: eventId,
          targetId: targetId,
          stageId: StageContext.global.name,
          trigger: rule.defaultTrigger,
        );

        events.add(event);
        newBindings.add(binding);
        previousEventId = eventId;
      } catch (e) {
        errors.add('Failed to create event for $targetId: $e');
      }
    }

    // Add all events and bindings
    _events.addAll(events);
    _bindings.addAll(newBindings);

    // Add to undo stack as single action
    if (events.isNotEmpty) {
      _undoStack.add(_UndoAction(
        type: _UndoActionType.commit,
        event: events.first,
        binding: newBindings.first,
        bindings: newBindings,
      ));
      _redoStack.clear();
    }

    // Mark asset as used
    markAssetUsed(asset.assetId);

    notifyListeners();

    return BatchDropResult(
      eventIds: events.map((e) => e.eventId).toList(),
      bindingIds: newBindings.map((b) => b.bindingId).toList(),
      errors: errors,
    );
  }

  /// Create target from ID
  DropTarget _createTargetFromId(String targetId) {
    final type = _inferTargetType(targetId);
    return DropTarget(
      targetId: targetId,
      targetType: type,
      stageContext: StageContext.global,
    );
  }

  /// Infer target type from ID
  TargetType _inferTargetType(String targetId) {
    if (targetId.startsWith('reel.')) {
      return targetId.contains('stop')
          ? TargetType.reelStopZone
          : TargetType.reelSurface;
    }
    if (targetId.startsWith('ui.')) return TargetType.uiButton;
    if (targetId.startsWith('symbol.')) return TargetType.symbolZone;
    if (targetId.startsWith('overlay.')) return TargetType.overlay;
    if (targetId.startsWith('feature.')) return TargetType.featureContainer;
    if (targetId.startsWith('hud.')) return TargetType.hudCounter;
    return TargetType.screenZone;
  }

  /// Get preset parameter value
  double? _getPresetParamValue(EventPreset preset, String paramName) {
    switch (paramName) {
      case 'volume': return preset.volume;
      case 'pitch': return preset.pitch;
      case 'pan': return preset.pan;
      case 'lpf': return preset.lpf;
      case 'hpf': return preset.hpf;
      case 'delayMs': return preset.delayMs.toDouble();
      case 'fadeInMs': return preset.fadeInMs.toDouble();
      case 'fadeOutMs': return preset.fadeOutMs.toDouble();
      case 'cooldownMs': return preset.cooldownMs.toDouble();
      case 'polyphony': return preset.polyphony.toDouble();
      case 'priority': return preset.priority.toDouble();
      default: return null;
    }
  }

  /// Delete batch by prefix
  void deleteBatchByPrefix(String prefix) {
    final batchEvents = _events.where((e) => e.eventId.startsWith(prefix)).toList();
    final batchEventIds = batchEvents.map((e) => e.eventId).toSet();
    final batchBindings = _bindings.where((b) => batchEventIds.contains(b.eventId)).toList();

    _events.removeWhere((e) => batchEventIds.contains(e.eventId));
    _bindings.removeWhere((b) => batchEventIds.contains(b.eventId));

    // Undo support for batch delete
    if (batchEvents.isNotEmpty) {
      _undoStack.add(_UndoAction(
        type: _UndoActionType.delete,
        event: batchEvents.first,
        bindings: batchBindings,
      ));
      _redoStack.clear();
    }

    notifyListeners();
  }

  // ==========================================================================
  // BINDING GRAPH (D.6)
  // ==========================================================================

  /// Build binding graph from current state
  BindingGraph buildBindingGraph({bool includePresetInheritance = true}) {
    final builder = BindingGraphBuilder();

    // Convert events to maps for graph builder
    final eventMaps = _events.map((e) => {
      'eventId': e.eventId,
      'intent': e.intent,
      'bus': e.bus,
      'presetId': e.presetId,
      'dependencies': e.dependencies.map((d) => {
        'targetEventId': d.targetEventId,
        'type': d.type.name,
        'delayMs': d.delayMs,
        'required': d.required,
      }).toList(),
      'rtpcBindings': e.rtpcBindings.map((r) => {
        'rtpcName': r.rtpcName,
        'eventParam': r.eventParam,
      }).toList(),
      if (e.conditionalTrigger != null) 'conditionalTrigger': {
        'name': e.conditionalTrigger!.name,
        'conditions': e.conditionalTrigger!.conditions.map((c) => c.toJson()).toList(),
        'logic': e.conditionalTrigger!.logic.name,
      },
    }).toList();

    // Convert bindings to maps for graph builder
    final bindingMaps = _bindings.map((b) => {
      'bindingId': b.bindingId,
      'eventId': b.eventId,
      'targetId': b.targetId,
      'stageId': b.stageId,
      'trigger': b.trigger,
      'enabled': b.enabled,
    }).toList();

    // Add events and bindings
    builder.addEventsFromMaps(eventMaps, bindingMaps);

    // Add preset inheritance
    if (includePresetInheritance) {
      builder.addPresetInheritance(_inheritanceResolver);
    }

    return builder.build();
  }

  /// Get filtered binding graph (by node types or search)
  BindingGraph getFilteredBindingGraph({
    Set<GraphNodeType>? includeNodeTypes,
    Set<GraphEdgeType>? includeEdgeTypes,
    String? searchQuery,
  }) {
    final fullGraph = buildBindingGraph();

    var filteredNodes = fullGraph.nodes.toList();
    var filteredEdges = fullGraph.edges.toList();

    // Filter by node types
    if (includeNodeTypes != null) {
      filteredNodes = filteredNodes
          .where((n) => includeNodeTypes.contains(n.nodeType))
          .toList();

      // Keep only edges between included nodes
      final nodeIds = filteredNodes.map((n) => n.nodeId).toSet();
      filteredEdges = filteredEdges
          .where((e) => nodeIds.contains(e.sourceId) && nodeIds.contains(e.targetId))
          .toList();
    }

    // Filter by edge types
    if (includeEdgeTypes != null) {
      filteredEdges = filteredEdges
          .where((e) => includeEdgeTypes.contains(e.edgeType))
          .toList();
    }

    // Apply search
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final matchingNodes = fullGraph.searchNodes(searchQuery);
      final matchingIds = matchingNodes.map((n) => n.nodeId).toSet();

      // Highlight matching nodes
      for (final node in filteredNodes) {
        node.isHighlighted = matchingIds.contains(node.nodeId);
      }
    }

    return BindingGraph(
      nodes: filteredNodes,
      edges: filteredEdges,
      metadata: {
        'filtered': true,
        'originalNodeCount': fullGraph.nodes.length,
        'originalEdgeCount': fullGraph.edges.length,
      },
    );
  }

  /// Get subgraph centered on a specific event
  BindingGraph getEventSubgraph(String eventId, {int depth = 2}) {
    final fullGraph = buildBindingGraph();
    final targetNodeId = 'event_$eventId';

    // BFS to find all connected nodes within depth
    final visited = <String>{targetNodeId};
    var frontier = <String>[targetNodeId];

    for (var d = 0; d < depth && frontier.isNotEmpty; d++) {
      final nextFrontier = <String>[];
      for (final nodeId in frontier) {
        // Get connected nodes
        for (final edge in fullGraph.edges) {
          if (edge.sourceId == nodeId && !visited.contains(edge.targetId)) {
            visited.add(edge.targetId);
            nextFrontier.add(edge.targetId);
          }
          if (edge.targetId == nodeId && !visited.contains(edge.sourceId)) {
            visited.add(edge.sourceId);
            nextFrontier.add(edge.sourceId);
          }
        }
      }
      frontier = nextFrontier;
    }

    // Filter nodes and edges
    final nodes = fullGraph.nodes.where((n) => visited.contains(n.nodeId)).toList();
    final edges = fullGraph.edges.where((e) =>
      visited.contains(e.sourceId) && visited.contains(e.targetId)
    ).toList();

    // Highlight center node
    for (final node in nodes) {
      node.isSelected = node.nodeId == targetNodeId;
    }

    return BindingGraph(
      nodes: nodes,
      edges: edges,
      metadata: {
        'subgraph': true,
        'centeredOn': eventId,
        'depth': depth,
      },
    );
  }

  /// Get dependency graph (events and their dependencies only)
  BindingGraph getDependencyGraph() {
    return getFilteredBindingGraph(
      includeNodeTypes: {GraphNodeType.event},
      includeEdgeTypes: {GraphEdgeType.dependency},
    );
  }

  /// Get routing graph (events to buses)
  BindingGraph getRoutingGraph() {
    return getFilteredBindingGraph(
      includeNodeTypes: {GraphNodeType.event, GraphNodeType.bus},
      includeEdgeTypes: {GraphEdgeType.routesToBus},
    );
  }

  /// Apply layout to graph
  void applyGraphLayout(
    BindingGraph graph, {
    GraphLayoutAlgorithm algorithm = GraphLayoutAlgorithm.hierarchical,
  }) {
    switch (algorithm) {
      case GraphLayoutAlgorithm.hierarchical:
        GraphLayoutCalculator.applyHierarchicalLayout(
          graph,
          const GraphLayoutOptions(),
        );
        break;
      case GraphLayoutAlgorithm.circular:
        GraphLayoutCalculator.applyCircularLayout(graph);
        break;
      case GraphLayoutAlgorithm.grid:
        GraphLayoutCalculator.applyGridLayout(graph);
        break;
      case GraphLayoutAlgorithm.forceDirected:
        // Use hierarchical as fallback (force directed needs iterative computation)
        GraphLayoutCalculator.applyHierarchicalLayout(
          graph,
          const GraphLayoutOptions(),
        );
        break;
    }
  }

  /// Export graph to DOT format (for Graphviz)
  String exportGraphToDot(BindingGraph graph) {
    final buffer = StringBuffer();
    buffer.writeln('digraph BindingGraph {');
    buffer.writeln('  rankdir=TB;');
    buffer.writeln('  node [shape=box, style=rounded];');
    buffer.writeln();

    // Node styles by type
    final nodeStyles = {
      GraphNodeType.event: 'fillcolor="#4A9EFF", style="rounded,filled"',
      GraphNodeType.target: 'fillcolor="#40FF90", style="rounded,filled"',
      GraphNodeType.preset: 'fillcolor="#FF9040", style="rounded,filled"',
      GraphNodeType.bus: 'fillcolor="#40C8FF", style="rounded,filled"',
      GraphNodeType.rtpc: 'fillcolor="#FFD700", style="rounded,filled"',
      GraphNodeType.condition: 'fillcolor="#FF4060", style="rounded,filled"',
    };

    // Add nodes
    for (final node in graph.nodes) {
      final style = nodeStyles[node.nodeType] ?? '';
      final label = node.subtitle != null
          ? '${node.label}\\n${node.subtitle}'
          : node.label;
      buffer.writeln('  "${node.nodeId}" [label="$label", $style];');
    }

    buffer.writeln();

    // Edge styles by type
    final edgeStyles = {
      GraphEdgeType.binding: 'color="#4A9EFF"',
      GraphEdgeType.dependency: 'color="#FF9040", style=dashed',
      GraphEdgeType.usesPreset: 'color="#888888", style=dotted',
      GraphEdgeType.routesToBus: 'color="#40C8FF"',
      GraphEdgeType.rtpcBinding: 'color="#FFD700", style=dashed',
      GraphEdgeType.conditionalTrigger: 'color="#FF4060", style=dotted',
      GraphEdgeType.inherits: 'color="#9333EA"',
    };

    // Add edges
    for (final edge in graph.edges) {
      final style = edgeStyles[edge.edgeType] ?? '';
      final label = edge.label != null ? ', label="${edge.label}"' : '';
      buffer.writeln('  "${edge.sourceId}" -> "${edge.targetId}" [$style$label];');
    }

    buffer.writeln('}');
    return buffer.toString();
  }

  /// Export graph to JSON
  String exportGraphToJson(BindingGraph graph) {
    return _jsonEncode(graph.toJson());
  }

  String _jsonEncode(Object? object) {
    // Simple JSON encoding (production would use dart:convert)
    if (object == null) return 'null';
    if (object is String) return '"${object.replaceAll('"', '\\"')}"';
    if (object is num || object is bool) return object.toString();
    if (object is List) {
      return '[${object.map(_jsonEncode).join(',')}]';
    }
    if (object is Map) {
      final entries = object.entries
          .map((e) => '${_jsonEncode(e.key)}:${_jsonEncode(e.value)}')
          .join(',');
      return '{$entries}';
    }
    return '"$object"';
  }

  // ==========================================================================
  // PRIVATE HELPERS
  // ==========================================================================

  /// Calculate spatial pan and mode based on target (D.8: per-reel spatial auto)
  (double, SpatialMode) _calculateSpatialParams(DropTarget target) {
    // Check if this is a reel target
    if (target.targetType == TargetType.reelStopZone) {
      // Parse reel index from target ID (e.g., "reel.0", "reel.1", etc.)
      final reelIndex = _parseReelIndex(target.targetId);
      if (reelIndex != null) {
        // Map reel 0-4 to pan -0.8 to +0.8 (5 reels standard)
        // Reel 0 → -0.8 (left)
        // Reel 1 → -0.4
        // Reel 2 → 0.0 (center)
        // Reel 3 → +0.4
        // Reel 4 → +0.8 (right)
        final pan = (reelIndex - 2) * 0.4; // Center at reel 2
        return (pan.clamp(-1.0, 1.0), SpatialMode.autoPerReel);
      }
    }

    // Check for symbol zones with reel context
    if (target.targetType == TargetType.symbolZone) {
      // Symbol zones don't have inherent position, use center
      return (0.0, SpatialMode.none);
    }

    // UI elements default to center
    return (0.0, SpatialMode.none);
  }

  /// Parse reel index from target ID (e.g., "reel.2" → 2)
  int? _parseReelIndex(String targetId) {
    if (!targetId.startsWith('reel.')) return null;
    final suffix = targetId.substring(5); // Remove "reel."
    return int.tryParse(suffix);
  }

  /// Find the best matching rule for asset/target
  DropRule _findMatchingRule(AudioAsset asset, DropTarget target) {
    for (final rule in _rules) {
      if (rule.matches(asset, target)) {
        return rule;
      }
    }
    // Fallback to generic rule
    return StandardDropRules.fallbackSfx;
  }

  /// Ensure event ID is unique (GAP 26 FIX)
  String _ensureUniqueEventId(String baseId) {
    if (!_events.any((e) => e.eventId == baseId)) {
      return baseId;
    }

    // Generate unique suffix
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = math.Random();
    final suffix = List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
    return '${baseId}_$suffix';
  }

  // ==========================================================================
  // SERIALIZATION
  // ==========================================================================

  /// Current schema version
  static const int _schemaVersion = 1;

  /// Export to JSON (basic - events and bindings only)
  Map<String, dynamic> toJson() => {
    'events': _events.map((e) => e.toJson()).toList(),
    'bindings': _bindings.map((b) => b.toJson()).toList(),
    'eventCounter': _eventCounter,
    'bindingCounter': _bindingCounter,
  };

  /// Import from JSON (basic)
  void fromJson(Map<String, dynamic> json) {
    _events.clear();
    _bindings.clear();

    final eventsJson = json['events'] as List<dynamic>?;
    if (eventsJson != null) {
      _events.addAll(eventsJson.map((e) => CommittedEvent.fromJson(e as Map<String, dynamic>)));
    }

    final bindingsJson = json['bindings'] as List<dynamic>?;
    if (bindingsJson != null) {
      _bindings.addAll(bindingsJson.map((b) => EventBinding.fromJson(b as Map<String, dynamic>)));
    }

    _eventCounter = json['eventCounter'] as int? ?? 0;
    _bindingCounter = json['bindingCounter'] as int? ?? 0;

    notifyListeners();
  }

  /// Export full manifest (events, bindings, custom presets, custom rules)
  Map<String, dynamic> exportManifest() {
    // Get only custom presets (not standard ones)
    final customPresets = _presets
        .where((p) => !StandardPresets.all.any((sp) => sp.presetId == p.presetId))
        .map((p) => p.toJson())
        .toList();

    // Get only custom rules (not standard ones)
    final customRules = _rules
        .where((r) => !StandardDropRules.all.any((sr) => sr.ruleId == r.ruleId))
        .map((r) => _ruleToJson(r))
        .toList();

    return {
      'version': _schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'events': _events.map((e) => e.toJson()).toList(),
      'bindings': _bindings.map((b) => b.toJson()).toList(),
      'customPresets': customPresets,
      'customRules': customRules,
      'counters': {
        'event': _eventCounter,
        'binding': _bindingCounter,
      },
    };
  }

  /// Import full manifest
  void importManifest(Map<String, dynamic> manifest, {bool merge = false}) {
    final version = manifest['version'] as int? ?? 1;
    if (version > _schemaVersion) {
      throw Exception('Manifest version $version is not supported. Max supported: $_schemaVersion');
    }

    if (!merge) {
      _events.clear();
      _bindings.clear();
      // Reset to standard presets/rules
      _presets.clear();
      _presets.addAll(StandardPresets.all);
      _rules.clear();
      _rules.addAll(StandardDropRules.all);
    }

    // Import events
    final eventsJson = manifest['events'] as List<dynamic>?;
    if (eventsJson != null) {
      for (final e in eventsJson) {
        final event = CommittedEvent.fromJson(e as Map<String, dynamic>);
        // Skip if already exists (when merging)
        if (!_events.any((existing) => existing.eventId == event.eventId)) {
          _events.add(event);
        }
      }
    }

    // Import bindings
    final bindingsJson = manifest['bindings'] as List<dynamic>?;
    if (bindingsJson != null) {
      for (final b in bindingsJson) {
        final binding = EventBinding.fromJson(b as Map<String, dynamic>);
        if (!_bindings.any((existing) => existing.bindingId == binding.bindingId)) {
          _bindings.add(binding);
        }
      }
    }

    // Import custom presets
    final presetsJson = manifest['customPresets'] as List<dynamic>?;
    if (presetsJson != null) {
      for (final p in presetsJson) {
        final preset = EventPreset.fromJson(p as Map<String, dynamic>);
        if (!_presets.any((existing) => existing.presetId == preset.presetId)) {
          _presets.add(preset);
        }
      }
    }

    // Import custom rules
    final rulesJson = manifest['customRules'] as List<dynamic>?;
    if (rulesJson != null) {
      for (final r in rulesJson) {
        final rule = _ruleFromJson(r as Map<String, dynamic>);
        if (!_rules.any((existing) => existing.ruleId == rule.ruleId)) {
          _rules.add(rule);
        }
      }
      // Re-sort by priority
      _rules.sort((a, b) => b.priority.compareTo(a.priority));
    }

    // Import counters
    final counters = manifest['counters'] as Map<String, dynamic>?;
    if (counters != null) {
      final eventCounter = counters['event'] as int? ?? 0;
      final bindingCounter = counters['binding'] as int? ?? 0;
      // Only update if larger (when merging)
      if (eventCounter > _eventCounter) _eventCounter = eventCounter;
      if (bindingCounter > _bindingCounter) _bindingCounter = bindingCounter;
    }

    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  /// Export events for a specific target
  Map<String, dynamic> exportEventsForTarget(String targetId) {
    final targetBindings = _bindings.where((b) => b.targetId == targetId).toList();
    final eventIds = targetBindings.map((b) => b.eventId).toSet();
    final targetEvents = _events.where((e) => eventIds.contains(e.eventId)).toList();

    return {
      'version': _schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'targetId': targetId,
      'events': targetEvents.map((e) => e.toJson()).toList(),
      'bindings': targetBindings.map((b) => b.toJson()).toList(),
    };
  }

  /// Get statistics
  Map<String, int> getStatistics() {
    return {
      'totalEvents': _events.length,
      'totalBindings': _bindings.length,
      'customPresets': _presets.length - StandardPresets.all.length,
      'customRules': _rules.length - StandardDropRules.all.length,
      'undoStackSize': _undoStack.length,
      'redoStackSize': _redoStack.length,
    };
  }

  // Helper to serialize DropRule
  Map<String, dynamic> _ruleToJson(DropRule rule) => {
    'ruleId': rule.ruleId,
    'name': rule.name,
    'priority': rule.priority,
    'assetTags': rule.assetTags,
    'targetTags': rule.targetTags,
    'assetType': rule.assetType?.name,
    'targetType': rule.targetType?.name,
    'eventIdTemplate': rule.eventIdTemplate,
    'intentTemplate': rule.intentTemplate,
    'defaultPresetId': rule.defaultPresetId,
    'defaultBus': rule.defaultBus,
    'defaultTrigger': rule.defaultTrigger,
  };

  // Helper to deserialize DropRule
  DropRule _ruleFromJson(Map<String, dynamic> json) => DropRule(
    ruleId: json['ruleId'] as String,
    name: json['name'] as String,
    priority: json['priority'] as int? ?? 50,
    assetTags: (json['assetTags'] as List<dynamic>?)?.cast<String>() ?? [],
    targetTags: (json['targetTags'] as List<dynamic>?)?.cast<String>() ?? [],
    assetType: json['assetType'] != null
        ? AssetTypeExtension.fromString(json['assetType'] as String)
        : null,
    targetType: json['targetType'] != null
        ? TargetTypeExtension.fromString(json['targetType'] as String)
        : null,
    eventIdTemplate: json['eventIdTemplate'] as String,
    intentTemplate: json['intentTemplate'] as String,
    defaultPresetId: json['defaultPresetId'] as String,
    defaultBus: json['defaultBus'] as String,
    defaultTrigger: json['defaultTrigger'] as String,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // BATCH OPERATIONS (for SlotAudioAutomationService integration)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Batch create events from automation specs
  /// Returns list of created event IDs
  List<String> batchCreateEvents(List<Map<String, dynamic>> specs) {
    final createdIds = <String>[];

    for (final spec in specs) {
      final eventId = spec['eventId'] as String? ?? 'event_${++_eventCounter}';
      final stage = spec['stage'] as String? ?? 'UNKNOWN';
      final bus = spec['bus'] as String? ?? 'sfx';
      final audioPath = spec['audioPath'] as String? ?? '';
      final volume = (spec['volume'] as num?)?.toDouble() ?? 1.0;
      final pan = (spec['pan'] as num?)?.toDouble() ?? 0.0;
      final actionTypeName = spec['actionType'] as String?;
      final actionType = actionTypeName != null
          ? ActionType.values.firstWhere(
              (e) => e.name == actionTypeName,
              orElse: () => ActionType.play,
            )
          : ActionType.play;
      final stopTarget = spec['stopTarget'] as String?;
      final loop = spec['loop'] as bool? ?? false;
      final priority = spec['priority'] as int? ?? 50;

      // Skip stop-only events with no audio
      if (audioPath.isEmpty && actionType == ActionType.stop) continue;

      // Create committed event
      final event = CommittedEvent(
        eventId: eventId,
        intent: stage,
        assetPath: audioPath,
        bus: bus,
        presetId: 'default',
        createdAt: DateTime.now(),
        actionType: actionType,
        stopTarget: stopTarget,
        pan: pan,
        parameters: {
          'volume': volume,
          'priority': priority,
          'loop': loop,
          ...spec['metadata'] as Map<String, dynamic>? ?? {},
        },
      );

      _events.add(event);
      createdIds.add(eventId);

      // Add undo action
      _undoStack.add(_UndoAction(
        type: _UndoActionType.commit,
        event: event,
      ));
    }

    _redoStack.clear();
    notifyListeners();
    return createdIds;
  }

  /// Batch delete events by IDs
  int batchDeleteEvents(List<String> eventIds) {
    int deletedCount = 0;

    for (final eventId in eventIds) {
      final eventIndex = _events.indexWhere((e) => e.eventId == eventId);
      if (eventIndex != -1) {
        final event = _events.removeAt(eventIndex);

        // Remove associated bindings
        final removedBindings = <EventBinding>[];
        _bindings.removeWhere((b) {
          if (b.eventId == eventId) {
            removedBindings.add(b);
            return true;
          }
          return false;
        });

        _undoStack.add(_UndoAction(
          type: _UndoActionType.delete,
          event: event,
          bindings: removedBindings,
        ));

        deletedCount++;
      }
    }

    if (deletedCount > 0) {
      _redoStack.clear();
      notifyListeners();
    }

    return deletedCount;
  }

  /// Get events by stage pattern (supports wildcards with *)
  List<CommittedEvent> getEventsByStagePattern(String pattern) {
    if (pattern.contains('*')) {
      final regex = RegExp(
        '^${pattern.replaceAll('*', '.*')}\$',
        caseSensitive: false,
      );
      return _events.where((e) {
        final stage = e.parameters['stage'] as String? ?? e.intent;
        return regex.hasMatch(stage);
      }).toList();
    } else {
      return _events.where((e) {
        final stage = e.parameters['stage'] as String? ?? e.intent;
        return stage.toUpperCase() == pattern.toUpperCase();
      }).toList();
    }
  }

  /// Clear all data
  void clear() {
    _currentDraft = null;
    _events.clear();
    _bindings.clear();
    _undoStack.clear();
    _redoStack.clear();
    _eventCounter = 0;
    _bindingCounter = 0;
    // Reset to standard presets/rules
    _presets.clear();
    _presets.addAll(StandardPresets.all);
    _rules.clear();
    _rules.addAll(StandardDropRules.all);
    notifyListeners();
  }
}

// =============================================================================
// UNDO ACTION
// =============================================================================

enum _UndoActionType { commit, delete, update }

class _UndoAction {
  final _UndoActionType type;
  final CommittedEvent? event;
  final EventBinding? binding;
  final List<EventBinding>? bindings;
  CommittedEvent? previousEvent;

  _UndoAction({
    required this.type,
    this.event,
    this.binding,
    this.bindings,
    this.previousEvent,
  });
}
