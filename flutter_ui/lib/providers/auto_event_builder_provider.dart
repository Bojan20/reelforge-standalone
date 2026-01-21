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
  );
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

  // ==========================================================================
  // GETTERS
  // ==========================================================================

  /// Current draft being edited
  EventDraft? get currentDraft => _currentDraft;

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

    // Generate event ID
    var eventId = rule.generateEventId(asset, target);

    // Ensure unique (GAP 26 FIX)
    eventId = _ensureUniqueEventId(eventId);

    // Create draft
    _currentDraft = EventDraft(
      eventId: eventId,
      target: target,
      asset: asset,
      trigger: rule.defaultTrigger,
      bus: rule.defaultBus,
      presetId: rule.defaultPresetId,
      stageContext: target.stageContext,
    );

    notifyListeners();
    return _currentDraft!;
  }

  /// Update current draft
  void updateDraft({
    String? trigger,
    String? presetId,
    StageContext? stageContext,
    VariationPolicy? variationPolicy,
    List<String>? tags,
    Map<String, dynamic>? paramOverrides,
  }) {
    if (_currentDraft == null) return;

    if (trigger != null) _currentDraft!.trigger = trigger;
    if (presetId != null) _currentDraft!.presetId = presetId;
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
  // PRIVATE HELPERS
  // ==========================================================================

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
