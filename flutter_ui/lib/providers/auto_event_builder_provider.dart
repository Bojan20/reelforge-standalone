/// Auto Event Builder Provider — STUB (Deprecated)
///
/// This provider is deprecated and has been replaced by EventListPanel
/// which directly uses MiddlewareProvider for event management.
///
/// This stub remains to prevent breaking existing imports while the
/// migration to EventListPanel completes.
///
/// STATUS: Functionality moved to:
/// - Event management → MiddlewareProvider (SSoT)
/// - Event list UI → EventListPanel (lower_zone/)
/// - Audio assets → Local state in slot_lab_screen
library;

import 'package:flutter/foundation.dart';
import '../models/auto_event_builder_models.dart';
import '../models/middleware_models.dart' show ActionType;

/// Stub EventDraft class for quick_sheet compatibility
class EventDraft {
  final String targetId;
  final String stage;
  final String? eventId;
  final String? trigger;
  final String? presetId;
  final List<String>? availableTriggers;
  final AudioAsset? asset;
  final String? target;
  final String? bus;
  final ActionType? actionType;
  final String? stopTarget;
  final String? actionReason;

  const EventDraft({
    required this.targetId,
    required this.stage,
    this.eventId,
    this.trigger,
    this.presetId,
    this.availableTriggers,
    this.asset,
    this.target,
    this.bus,
    this.actionType,
    this.stopTarget,
    this.actionReason,
  });

  set eventId(String? value) {} // Stub setter
}

/// Stub CrossfadeConfig class for advanced_event_config compatibility
class CrossfadeConfig {
  final double fadeInMs;
  final double fadeOutMs;
  final String curve;
  final bool enabled;

  const CrossfadeConfig({
    this.fadeInMs = 100,
    this.fadeOutMs = 100,
    this.curve = 'linear',
    this.enabled = false,
  });
}

/// Stub ConditionalTrigger class for advanced_event_config compatibility
class ConditionalTrigger {
  final String id;
  final String name;
  final List<TriggerCondition> conditions;

  const ConditionalTrigger({
    required this.id,
    required this.name,
    this.conditions = const [],
  });
}

/// Stub TriggerCondition class
class TriggerCondition {
  final String field;
  final String operator;
  final dynamic value;

  const TriggerCondition({
    required this.field,
    required this.operator,
    required this.value,
  });
}

/// Stub RtpcBinding class
class RtpcBinding {
  final String id;
  final String rtpcId;
  final String parameter;
  final double minValue;
  final double maxValue;

  const RtpcBinding({
    required this.id,
    required this.rtpcId,
    required this.parameter,
    this.minValue = 0.0,
    this.maxValue = 1.0,
  });
}

/// Stub InheritanceResolver class
class InheritanceResolver {
  const InheritanceResolver();
  Map<String, dynamic> resolve(String presetId) => {};
}

/// Stub PresetTreeNode class
class PresetTreeNode {
  final String id;
  final String name;
  final List<PresetTreeNode> children;

  const PresetTreeNode({
    required this.id,
    required this.name,
    this.children = const [],
  });
}

/// Stub BindingGraph class
class BindingGraph {
  final List<BindingGraphNode> nodes;
  final List<BindingGraphEdge> edges;

  const BindingGraph({this.nodes = const [], this.edges = const []});
}

/// Stub BindingGraphNode class
class BindingGraphNode {
  final String id;
  final String label;
  double x;
  double y;

  BindingGraphNode({required this.id, required this.label, this.x = 0, this.y = 0});
}

/// Stub BindingGraphEdge class
class BindingGraphEdge {
  final String from;
  final String to;

  const BindingGraphEdge({required this.from, required this.to});
}

/// Stub CommittedEvent class - preserved for compatibility
class CommittedEvent {
  final String eventId;
  final String intent;
  final String assetPath;
  final String bus;
  final String presetId;
  final Map<String, dynamic> parameters;
  final ActionType actionType;
  final String? stopTarget;
  final double pan;
  final List<String> dependencies;
  final ConditionalTrigger? conditionalTrigger;
  final List<RtpcBinding> rtpcBindings;
  final CrossfadeConfig? crossfadeConfig;

  CommittedEvent({
    required this.eventId,
    required this.intent,
    required this.assetPath,
    required this.bus,
    required this.presetId,
    this.parameters = const {},
    this.actionType = ActionType.play,
    this.stopTarget,
    this.pan = 0.0,
    this.dependencies = const [],
    this.conditionalTrigger,
    this.rtpcBindings = const [],
    this.crossfadeConfig,
  });
}

/// Stub provider - no longer functional
class AutoEventBuilderProvider extends ChangeNotifier {
  // Empty audio assets
  List<AudioAsset> get audioAssets => const [];
  List<String> get allAssetTags => const [];
  bool get hasSelection => false;
  int get selectionCount => 0;
  List<AudioAsset> get selectedAssets => const [];
  List<AudioAsset> get recentAssets => const [];
  List<CommittedEvent> get events => const [];
  List<CommittedEvent> get committedEvents => const []; // Alias
  List<String> get presets => const []; // Stub for quick_sheet.dart

  EventDraft? createDraft(AudioAsset asset, DropTarget target) => null; // Stub
  void updateDraft({String? trigger, String? presetId, Map<String, dynamic>? parameters}) {} // Stub

  void clearAudioAssets() {}
  void addAudioAssets(List<AudioAsset> assets) {}
  void clearSelection() {}
  void selectAssets(Iterable<String> ids) {}
  void toggleAssetSelection(String id) {}
  bool isAssetSelected(String id) => false;
  int getEventCountForTarget(String targetId) => 0;
  void deleteEvent(String eventId) {}

  // Draft workflow stubs
  CommittedEvent? commitDraft() => null;
  void cancelDraft() {}

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.4: STUB METHODS FOR advanced_event_config.dart COMPATIBILITY
  // These methods do nothing but prevent compile errors.
  // The actual functionality has moved to MiddlewareProvider.
  // ═══════════════════════════════════════════════════════════════════════════

  // Dependency management stubs
  bool hasCircularDependency(String eventId) => false;
  void addEventDependency(String eventId, String dependencyId) {}
  void removeEventDependency(String eventId, String dependencyId) {}

  // Conditional trigger stubs
  void setConditionalTrigger(String eventId, ConditionalTrigger? trigger) {}
  void addTriggerCondition(String eventId, TriggerCondition condition) {}
  void removeTriggerCondition(String eventId, String conditionId) {}

  // RTPC binding stubs
  void addRtpcBinding(String eventId, RtpcBinding binding) {}
  void removeRtpcBinding(String eventId, String bindingId) {}

  // Crossfade config stubs
  void setMusicCrossfadeConfig(String eventId, CrossfadeConfig config) {}

  // Preset management stubs
  PresetTreeNode? getPresetTree() => null;
  void addPreset(String name, Map<String, dynamic> config) {}
  void removePreset(String presetId) {}
  void registerInheritablePreset(String presetId, Map<String, dynamic> config) {}

  // Inheritance resolver stub
  InheritanceResolver? get inheritanceResolver => null;

  // Batch operations stubs
  void executeBatchDrop(List<AudioAsset> assets, DropTarget target) {}

  // Graph operations stubs
  BindingGraph? getEventSubgraph(String eventId) => null;
  BindingGraph? getFilteredBindingGraph(String filter) => null;
  BindingGraph buildBindingGraph() => const BindingGraph();
  void applyGraphLayout(BindingGraph graph) {}
  String exportGraphToDot(BindingGraph graph) => '';
}
