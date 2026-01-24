// Middleware Provider
//
// State management for Wwise/FMOD-style middleware system:
// - State Groups (global states affecting sound)
// - Switch Groups (per-object sound variants)
// - RTPC (Real-Time Parameter Control)
//
// Connects Dart UI to Rust rf-event system via FFI.
//
// P1.1/P1.2 FIX: Batched notifications to prevent cascading rebuilds

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import '../models/middleware_models.dart';
import '../models/slot_audio_events.dart';
import '../models/advanced_middleware_models.dart';
import '../services/rtpc_modulation_service.dart';
import '../services/ducking_service.dart';
import '../services/container_service.dart';
import '../services/audio_asset_manager.dart';
import '../services/audio_playback_service.dart';
import '../services/service_locator.dart';
import '../spatial/auto_spatial.dart';
import '../src/rust/native_ffi.dart';
import '../services/unified_playback_controller.dart';
import 'subsystems/state_groups_provider.dart';
import 'subsystems/switch_groups_provider.dart';
import 'subsystems/rtpc_system_provider.dart';
import 'subsystems/ducking_system_provider.dart';
import 'subsystems/blend_containers_provider.dart';
import 'subsystems/random_containers_provider.dart';
import 'subsystems/sequence_containers_provider.dart';
import 'subsystems/music_system_provider.dart';
import 'subsystems/event_system_provider.dart';
import 'subsystems/composite_event_system_provider.dart' as composite_provider;
import 'subsystems/bus_hierarchy_provider.dart';
import 'subsystems/aux_send_provider.dart';
import 'subsystems/voice_pool_provider.dart';
import 'subsystems/attenuation_curve_provider.dart';
import 'subsystems/memory_manager_provider.dart';
import 'subsystems/event_profiler_provider.dart';

// ============ Type Definitions ============

/// Typedef for stats record (used in Selector)
typedef MiddlewareStats = ({
  int stateGroups,
  int switchGroups,
  int rtpcs,
  int objectsWithSwitches,
  int objectsWithRtpcs,
  int duckingRules,
  int blendContainers,
  int randomContainers,
  int sequenceContainers,
  int musicSegments,
  int stingers,
  int attenuationCurves,
});

/// Typedef for events folder panel (used in Selector)
typedef EventsFolderData = ({
  List<SlotCompositeEvent> events,
  SlotCompositeEvent? selectedEvent,
  Set<String> selectedLayerIds,
  int selectedLayerCount,
  bool hasLayerInClipboard,
});

/// Typedef for music system panel (used in Selector)
typedef MusicSystemData = ({
  List<MusicSegment> segments,
  List<Stinger> stingers,
});

/// Typedef for attenuation curve panel (used in Selector)
/// Note: Simple list type can be used directly in Selector

// ============ Container Limits (P2.7 FIX) ============

/// Maximum children per container to prevent memory exhaustion
const int kMaxContainerChildren = 32;
/// but typedef provides consistency and documentation

// ============ Change Types ============

/// Types of changes to composite events for bidirectional sync
enum CompositeEventChangeType {
  created,
  updated,
  deleted,
  layerAdded,
  layerRemoved,
  layerUpdated,
  selectionChanged,
}

// ============ Provider ============

class MiddlewareProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.1/P1.2 ULTIMATE FIX: GRANULAR CHANGE TRACKING + BATCHED NOTIFICATIONS
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Problem:
  // - 7 subsystem providers each call notifyListeners directly
  // - When multiple subsystems change, we get 7 rebuilds instead of 1
  // - No way to know WHAT changed, so widgets rebuild entirely
  //
  // Solution:
  // 1. Track exactly which domains changed (stateGroups, rtpc, ducking, etc.)
  // 2. Batch multiple changes into a single notification per frame
  // 3. Expose change flags so widgets can use Selector for granular rebuilds
  // 4. Auto-clear change flags after notification

  /// Change domains for granular tracking
  static const int changeNone = 0;
  static const int changeStateGroups = 1 << 0;      // 1
  static const int changeSwitchGroups = 1 << 1;     // 2
  static const int changeRtpc = 1 << 2;             // 4
  static const int changeDucking = 1 << 3;          // 8
  static const int changeBlendContainers = 1 << 4;  // 16
  static const int changeRandomContainers = 1 << 5; // 32
  static const int changeSequenceContainers = 1 << 6; // 64
  static const int changeCompositeEvents = 1 << 7;  // 128
  static const int changeMusicSystem = 1 << 8;      // 256
  static const int changeVoicePool = 1 << 9;        // 512
  static const int changeBusHierarchy = 1 << 10;    // 1024
  static const int changeAuxSends = 1 << 11;        // 2048
  static const int changeSlotElements = 1 << 12;    // 4096
  static const int changeAll = 0xFFFF;              // All flags

  /// Current pending change flags (reset after notification)
  int _pendingChanges = changeNone;

  /// Last notified change flags (for widgets to check what changed)
  int _lastChanges = changeNone;

  /// Whether a notification is already scheduled for this frame
  bool _notificationScheduled = false;

  /// Debounce timer for high-frequency updates (RTPC, etc.)
  Timer? _debounceTimer;

  /// Minimum time between notifications (prevents UI stutter from rapid changes)
  static const Duration _minNotifyInterval = Duration(milliseconds: 16); // ~60fps

  /// Last notification timestamp
  DateTime _lastNotifyTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Check if a specific domain changed in the last notification
  bool didChange(int domain) => (_lastChanges & domain) != 0;

  /// Mark a domain as changed and schedule notification
  void _markChanged(int domain) {
    _pendingChanges |= domain;
    _scheduleNotification();
  }

  /// Batch notifications from subsystem providers into a single notifyListeners call
  /// Uses frame-aligned scheduling + minimum interval throttling
  void _scheduleNotification() {
    if (_notificationScheduled) return;

    final now = DateTime.now();
    final elapsed = now.difference(_lastNotifyTime);

    if (elapsed < _minNotifyInterval) {
      // Throttle: schedule after remaining time
      _debounceTimer?.cancel();
      _debounceTimer = Timer(
        _minNotifyInterval - elapsed,
        _executeNotification,
      );
      _notificationScheduled = true;
    } else {
      // Can notify immediately, but still batch within frame
      _notificationScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _executeNotification();
      });
    }
  }

  /// Execute the batched notification
  void _executeNotification() {
    if (_pendingChanges == changeNone) {
      _notificationScheduled = false;
      return;
    }

    _lastChanges = _pendingChanges;
    _pendingChanges = changeNone;
    _notificationScheduled = false;
    _lastNotifyTime = DateTime.now();

    // Debug: log which domains changed
    if (kDebugMode) {
      final domains = <String>[];
      if ((_lastChanges & changeStateGroups) != 0) domains.add('StateGroups');
      if ((_lastChanges & changeSwitchGroups) != 0) domains.add('SwitchGroups');
      if ((_lastChanges & changeRtpc) != 0) domains.add('RTPC');
      if ((_lastChanges & changeDucking) != 0) domains.add('Ducking');
      if ((_lastChanges & changeBlendContainers) != 0) domains.add('Blend');
      if ((_lastChanges & changeRandomContainers) != 0) domains.add('Random');
      if ((_lastChanges & changeSequenceContainers) != 0) domains.add('Sequence');
      if ((_lastChanges & changeCompositeEvents) != 0) domains.add('Events');
      if ((_lastChanges & changeMusicSystem) != 0) domains.add('Music');
      if (domains.isNotEmpty) {
        debugPrint('[MiddlewareProvider] Batched notify: ${domains.join(", ")}');
      }
    }

    notifyListeners();
  }

  /// Force immediate notification (for critical updates that can't wait)
  void _notifyImmediate() {
    _debounceTimer?.cancel();
    _lastChanges = _pendingChanges | changeAll;
    _pendingChanges = changeNone;
    _notificationScheduled = false;
    _lastNotifyTime = DateTime.now();
    notifyListeners();
  }

  /// Subsystem listener that marks the appropriate domain as changed
  void _onStateGroupsChanged() => _markChanged(changeStateGroups);
  void _onSwitchGroupsChanged() => _markChanged(changeSwitchGroups);
  void _onRtpcChanged() => _markChanged(changeRtpc);
  void _onDuckingChanged() => _markChanged(changeDucking);
  void _onBlendContainersChanged() => _markChanged(changeBlendContainers);
  void _onRandomContainersChanged() => _markChanged(changeRandomContainers);
  void _onSequenceContainersChanged() => _markChanged(changeSequenceContainers);
  void _onMusicSystemChanged() => _markChanged(changeMusicSystem);
  void _onEventSystemChanged() => _markChanged(changeCompositeEvents);
  void _onCompositeEventsChanged() => _markChanged(changeCompositeEvents);

  // ═══════════════════════════════════════════════════════════════════════════
  // EXTRACTED SUBSYSTEM PROVIDERS (P0.2 decomposition)
  // ═══════════════════════════════════════════════════════════════════════════

  /// State Groups subsystem (extracted)
  late final StateGroupsProvider _stateGroupsProvider;

  /// Switch Groups subsystem (extracted)
  late final SwitchGroupsProvider _switchGroupsProvider;

  /// RTPC subsystem (extracted)
  late final RtpcSystemProvider _rtpcSystemProvider;

  /// Ducking subsystem (extracted)
  late final DuckingSystemProvider _duckingSystemProvider;

  /// Blend Containers subsystem (extracted Phase 3)
  late final BlendContainersProvider _blendContainersProvider;

  /// Random Containers subsystem (extracted Phase 3)
  late final RandomContainersProvider _randomContainersProvider;

  /// Sequence Containers subsystem (extracted Phase 3)
  late final SequenceContainersProvider _sequenceContainersProvider;

  /// Music System subsystem (extracted P1.7)
  late final MusicSystemProvider _musicSystemProvider;

  /// Event System subsystem (extracted P1.8)
  late final EventSystemProvider _eventSystemProvider;

  /// Composite Event System subsystem (extracted P1.5)
  late final composite_provider.CompositeEventSystemProvider _compositeEventSystemProvider;

  /// Bus Hierarchy subsystem (extracted Provider Decomposition)
  late final BusHierarchyProvider _busHierarchyProvider;

  /// Aux Send subsystem (extracted Provider Decomposition)
  late final AuxSendProvider _auxSendProvider;

  /// Voice Pool subsystem (extracted Phase 6)
  late final VoicePoolProvider _voicePoolProvider;

  /// Attenuation Curve subsystem (extracted Phase 6)
  late final AttenuationCurveProvider _attenuationCurveProvider;

  /// Memory Manager subsystem (extracted Phase 7)
  late final MemoryManagerProvider _memoryManagerProvider;

  /// Event Profiler subsystem (extracted Phase 7)
  late final EventProfilerProvider _eventProfilerProvider;

  // ═══════════════════════════════════════════════════════════════════════════
  // SLOT ELEMENT MAPPINGS (bidirectional sync with Slot Fullscreen)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Slot element to event mappings
  final Map<SlotElementType, SlotElementEventMapping> _slotElementMappings = {};

  /// Custom element mappings (for user-defined elements)
  final Map<String, SlotElementEventMapping> _customElementMappings = {};

  // Music system state (moved to MusicSystemProvider)

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS
  // ═══════════════════════════════════════════════════════════════════════════

  // NOTE: VoicePool, BusHierarchy, AuxSend, AttenuationCurve, MemoryManager, and
  // EventProfiler have been extracted to subsystem providers. Use the respective
  // providers instead (see _memoryManagerProvider, _eventProfilerProvider).

  /// Spatial audio config for reels
  ReelSpatialConfig _reelSpatialConfig = const ReelSpatialConfig(
    reelCount: 5,
    panSpread: 0.8,
  );

  /// Cascade audio config
  CascadeAudioConfig _cascadeConfig = defaultCascadeConfig;

  /// HDR audio config
  HdrAudioConfig _hdrConfig = HdrAudioConfig.fromProfile(HdrProfile.desktop);

  /// Streaming config
  StreamingConfig _streamingConfig = const StreamingConfig();

  /// AutoSpatial engine for UI-driven spatial positioning
  final AutoSpatialEngine _autoSpatialEngine = AutoSpatialEngine();

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED AUDIO POOL (accessible from DAW, Middleware, and Slot Mode)
  // Now delegates to AudioAssetManager (single source of truth)
  // ═══════════════════════════════════════════════════════════════════════════

  /// @deprecated Use AudioAssetManager.instance.assets instead
  /// Kept for backwards compatibility - converts from UnifiedAudioAsset
  List<SharedPoolAudioFile> get _sharedAudioPool {
    return AudioAssetManager.instance.assets.map((a) => SharedPoolAudioFile(
      id: a.id,
      path: a.path,
      name: a.name,
      duration: a.duration,
      sampleRate: a.sampleRate,
      channels: a.channels,
      format: a.format,
      waveform: a.waveform,
      importedAt: a.importedAt,
    )).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SLOT MODE STATE (persistent across mode switches)
  // ═══════════════════════════════════════════════════════════════════════════

  final List<SlotAudioTrack> _slotTracks = [];
  final List<SlotStageMarker> _slotMarkers = [];
  double _slotPlayheadPosition = 0.0;
  double _slotTimelineZoom = 1.0;
  bool _slotLoopEnabled = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPOSITE EVENTS (delegated to CompositeEventSystemProvider - P1.5)
  // ═══════════════════════════════════════════════════════════════════════════
  // All composite event state and logic moved to CompositeEventSystemProvider

  /// P1.15 FIX: Track whether listeners are registered to prevent duplicates
  bool _listenersRegistered = false;

  MiddlewareProvider(this._ffi) {
    // Initialize extracted subsystem providers via GetIt
    _stateGroupsProvider = sl<StateGroupsProvider>();
    _switchGroupsProvider = sl<SwitchGroupsProvider>();
    _rtpcSystemProvider = sl<RtpcSystemProvider>();
    _duckingSystemProvider = sl<DuckingSystemProvider>();
    _blendContainersProvider = sl<BlendContainersProvider>();
    _randomContainersProvider = sl<RandomContainersProvider>();
    _sequenceContainersProvider = sl<SequenceContainersProvider>();
    _musicSystemProvider = sl<MusicSystemProvider>();
    _eventSystemProvider = sl<EventSystemProvider>();
    _compositeEventSystemProvider = sl<composite_provider.CompositeEventSystemProvider>();
    _busHierarchyProvider = sl<BusHierarchyProvider>();
    _auxSendProvider = sl<AuxSendProvider>();
    _voicePoolProvider = sl<VoicePoolProvider>();
    _attenuationCurveProvider = sl<AttenuationCurveProvider>();
    _memoryManagerProvider = sl<MemoryManagerProvider>();
    _eventProfilerProvider = sl<EventProfilerProvider>();

    // P1.1 FIX: Forward notifications through granular change tracking
    // P1.15 FIX: Guard against duplicate listener registration (e.g., hot reload)
    _registerSubsystemListeners();

    _initializeDefaults();
    _initializeServices();
  }

  /// P1.15 FIX: Register subsystem listeners with deduplication guard
  /// Prevents memory accumulation from duplicate listeners during hot reload
  void _registerSubsystemListeners() {
    if (_listenersRegistered) {
      debugPrint('[MiddlewareProvider] Skipping duplicate listener registration');
      return;
    }

    _stateGroupsProvider.addListener(_onStateGroupsChanged);
    _switchGroupsProvider.addListener(_onSwitchGroupsChanged);
    _rtpcSystemProvider.addListener(_onRtpcChanged);
    _duckingSystemProvider.addListener(_onDuckingChanged);
    _blendContainersProvider.addListener(_onBlendContainersChanged);
    _randomContainersProvider.addListener(_onRandomContainersChanged);
    _sequenceContainersProvider.addListener(_onSequenceContainersChanged);
    _musicSystemProvider.addListener(_onMusicSystemChanged);
    _eventSystemProvider.addListener(_onEventSystemChanged);
    _compositeEventSystemProvider.addListener(_onCompositeEventsChanged);
    _busHierarchyProvider.addListener(_onBusHierarchyChanged);
    _auxSendProvider.addListener(_onAuxSendChanged);
    _voicePoolProvider.addListener(_onVoicePoolChanged);
    _attenuationCurveProvider.addListener(_onAttenuationCurveChanged);
    _memoryManagerProvider.addListener(_onMemoryManagerChanged);
    _eventProfilerProvider.addListener(_onEventProfilerChanged);

    _listenersRegistered = true;
  }

  /// Handle bus hierarchy changes
  void _onBusHierarchyChanged() {
    _markChanged(changeBusHierarchy);
    notifyListeners();
  }

  /// Handle aux send changes
  void _onAuxSendChanged() {
    _markChanged(changeBusHierarchy);  // Reuse bus hierarchy flag for routing changes
    notifyListeners();
  }

  /// Handle voice pool changes
  void _onVoicePoolChanged() {
    _markChanged(changeVoicePool);
    notifyListeners();
  }

  /// Handle attenuation curve changes
  void _onAttenuationCurveChanged() {
    _markChanged(changeSlotElements);  // Reuse slot elements flag for attenuation
    notifyListeners();
  }

  /// Handle memory manager changes
  void _onMemoryManagerChanged() {
    _markChanged(changeSlotElements);  // Reuse slot elements flag for memory changes
    notifyListeners();
  }

  /// Handle event profiler changes
  void _onEventProfilerChanged() {
    // Profiler is typically read-only, but notify for UI updates
    notifyListeners();
  }

  /// Initialize audio services with this provider reference
  void _initializeServices() {
    RtpcModulationService.instance.init(this);
    DuckingService.instance.init();
    ContainerService.instance.init(this);
    debugPrint('[MiddlewareProvider] Services initialized (RTPC, Ducking, Container)');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  List<StateGroup> get stateGroups => _stateGroupsProvider.stateGroups.values.toList();
  List<SwitchGroup> get switchGroups => _switchGroupsProvider.switchGroups.values.toList();
  List<RtpcDefinition> get rtpcDefinitions => _rtpcSystemProvider.rtpcDefinitions;
  List<RtpcBinding> get rtpcBindings => _rtpcSystemProvider.rtpcBindings;

  // Advanced features getters (delegating to extracted providers)
  List<DuckingRule> get duckingRules => _duckingSystemProvider.duckingRules;
  List<BlendContainer> get blendContainers => _blendContainersProvider.blendContainers;
  List<RandomContainer> get randomContainers => _randomContainersProvider.randomContainers;
  List<SequenceContainer> get sequenceContainers => _sequenceContainersProvider.sequenceContainers;
  List<MusicSegment> get musicSegments => _musicSystemProvider.musicSegments;
  List<Stinger> get stingers => _musicSystemProvider.stingers;
  List<AttenuationCurve> get attenuationCurves => _attenuationCurveProvider.curves;
  int? get currentMusicSegmentId => _musicSystemProvider.currentMusicSegmentId;
  int? get nextMusicSegmentId => _musicSystemProvider.nextMusicSegmentId;
  int get musicBusId => _musicSystemProvider.musicBusId;

  // Advanced systems getters (subsystem providers)
  VoicePoolProvider get voicePoolProvider => _voicePoolProvider;
  BusHierarchyProvider get busHierarchyProvider => _busHierarchyProvider;
  AuxSendProvider get auxSendProvider => _auxSendProvider;
  MemoryManagerProvider get memoryManagerProvider => _memoryManagerProvider;
  EventProfilerProvider get eventProfilerProvider => _eventProfilerProvider;
  ReelSpatialConfig get reelSpatialConfig => _reelSpatialConfig;
  CascadeAudioConfig get cascadeConfig => _cascadeConfig;
  HdrAudioConfig get hdrConfig => _hdrConfig;
  StreamingConfig get streamingConfig => _streamingConfig;
  AutoSpatialEngine get autoSpatialEngine => _autoSpatialEngine;
  AnchorRegistry get anchorRegistry => _autoSpatialEngine.anchorRegistry;

  // Shared Audio Pool getters
  List<SharedPoolAudioFile> get sharedAudioPool => List.unmodifiable(_sharedAudioPool);

  // Slot Mode state getters
  List<SlotAudioTrack> get slotTracks => List.unmodifiable(_slotTracks);
  List<SlotStageMarker> get slotMarkers => List.unmodifiable(_slotMarkers);
  double get slotPlayheadPosition => _slotPlayheadPosition;
  double get slotTimelineZoom => _slotTimelineZoom;
  bool get slotLoopEnabled => _slotLoopEnabled;

  // Composite Events getters (delegated to CompositeEventSystemProvider)
  List<SlotCompositeEvent> get compositeEvents => _compositeEventSystemProvider.compositeEvents;
  SlotCompositeEvent? get selectedCompositeEvent => _compositeEventSystemProvider.selectedCompositeEvent;
  String? get selectedCompositeEventId => _compositeEventSystemProvider.selectedCompositeEventId;

  // Undo/Redo getters (delegated)
  bool get canUndo => _compositeEventSystemProvider.canUndo;
  bool get canRedo => _compositeEventSystemProvider.canRedo;
  int get undoStackSize => _compositeEventSystemProvider.undoStackSize;
  int get redoStackSize => _compositeEventSystemProvider.redoStackSize;

  // Layer clipboard getters (delegated)
  bool get hasLayerInClipboard => _compositeEventSystemProvider.hasLayerInClipboard;
  SlotEventLayer? get layerClipboard => _compositeEventSystemProvider.layerClipboard;
  String? get selectedLayerId => _compositeEventSystemProvider.selectedLayerId;

  // Multi-select getters (delegated)
  Set<String> get selectedLayerIds => _compositeEventSystemProvider.selectedLayerIds;
  bool get hasMultipleLayersSelected => _compositeEventSystemProvider.hasMultipleLayersSelected;
  int get selectedLayerCount => _compositeEventSystemProvider.selectedLayerCount;

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANGE LISTENERS (delegated to CompositeEventSystemProvider)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a listener for composite event changes (delegated)
  void addCompositeChangeListener(
      void Function(String eventId, CompositeEventChangeType type) listener) {
    // Adapt MiddlewareProvider's enum to provider's enum
    _compositeEventSystemProvider.addCompositeChangeListener(
      (eventId, type) {
        final mappedType = switch (type) {
          composite_provider.CompositeEventChangeType.created =>
            CompositeEventChangeType.created,
          composite_provider.CompositeEventChangeType.updated =>
            CompositeEventChangeType.updated,
          composite_provider.CompositeEventChangeType.deleted =>
            CompositeEventChangeType.deleted,
        };
        listener(eventId, mappedType);
      },
    );
  }

  StateGroup? getStateGroup(int groupId) => _stateGroupsProvider.getStateGroup(groupId);
  SwitchGroup? getSwitchGroup(int groupId) => _switchGroupsProvider.getSwitchGroup(groupId);
  RtpcDefinition? getRtpc(int rtpcId) => _rtpcSystemProvider.getRtpc(rtpcId);
  RtpcBinding? getRtpcBinding(int bindingId) => _rtpcSystemProvider.getBinding(bindingId);

  /// Get current state for a group
  int getCurrentState(int groupId) {
    return _stateGroupsProvider.getCurrentState(groupId) ?? 0;
  }

  /// Get current state name for a group
  String getCurrentStateName(int groupId) {
    return _stateGroupsProvider.getStateGroup(groupId)?.currentStateName ?? 'None';
  }

  /// Get switch value for a game object
  int getSwitch(int gameObjectId, int groupId) {
    return _switchGroupsProvider.getSwitch(gameObjectId, groupId) ??
        _switchGroupsProvider.getSwitchGroup(groupId)?.defaultSwitchId ?? 0;
  }

  /// Get switch name for a game object
  String? getSwitchName(int gameObjectId, int groupId) {
    final switchId = getSwitch(gameObjectId, groupId);
    return _switchGroupsProvider.getSwitchGroup(groupId)?.switchName(switchId);
  }

  /// Get RTPC value (global)
  double getRtpcValue(int rtpcId) => _rtpcSystemProvider.getRtpcValue(rtpcId);

  /// Get RTPC value for specific object (falls back to global)
  double getRtpcValueForObject(int gameObjectId, int rtpcId) =>
      _rtpcSystemProvider.getRtpcValueForObject(gameObjectId, rtpcId);

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE GROUPS (delegated to StateGroupsProvider)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a state group from predefined constants
  void registerStateGroupFromPreset(String name, List<String> stateNames) =>
      _stateGroupsProvider.registerStateGroupFromPreset(name, stateNames);

  /// Register a custom state group
  void registerStateGroup(StateGroup group) =>
      _stateGroupsProvider.registerStateGroup(group);

  /// Set current state (global)
  void setState(int groupId, int stateId) =>
      _stateGroupsProvider.setState(groupId, stateId);

  /// Set state by name
  void setStateByName(int groupId, String stateName) =>
      _stateGroupsProvider.setStateByName(groupId, stateName);

  /// Reset state to default
  void resetState(int groupId) =>
      _stateGroupsProvider.resetState(groupId);

  /// Unregister a state group
  void unregisterStateGroup(int groupId) =>
      _stateGroupsProvider.unregisterStateGroup(groupId);

  // ═══════════════════════════════════════════════════════════════════════════
  // SWITCH GROUPS (delegated to SwitchGroupsProvider)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a switch group
  void registerSwitchGroup(SwitchGroup group) =>
      _switchGroupsProvider.registerSwitchGroup(group);

  /// Register switch group from name and switch names
  void registerSwitchGroupFromPreset(String name, List<String> switchNames) =>
      _switchGroupsProvider.registerSwitchGroupFromPreset(name, switchNames);

  /// Set switch for a game object
  void setSwitch(int gameObjectId, int groupId, int switchId) =>
      _switchGroupsProvider.setSwitch(gameObjectId, groupId, switchId);

  /// Set switch by name
  void setSwitchByName(int gameObjectId, int groupId, String switchName) =>
      _switchGroupsProvider.setSwitchByName(gameObjectId, groupId, switchName);

  /// Reset switch to default for a game object
  void resetSwitch(int gameObjectId, int groupId) =>
      _switchGroupsProvider.resetSwitch(gameObjectId, groupId);

  /// Clear all switches for a game object
  void clearObjectSwitches(int gameObjectId) =>
      _switchGroupsProvider.clearObjectSwitches(gameObjectId);

  /// Unregister a switch group
  void unregisterSwitchGroup(int groupId) =>
      _switchGroupsProvider.unregisterSwitchGroup(groupId);

  // ═══════════════════════════════════════════════════════════════════════════
  // RTPC (delegated to RtpcSystemProvider)
  // ═══════════════════════════════════════════════════════════════════════════

  void unregisterRtpc(int rtpcId) => _rtpcSystemProvider.unregisterRtpc(rtpcId);
  void registerRtpc(RtpcDefinition rtpc) => _rtpcSystemProvider.registerRtpc(rtpc);
  void registerRtpcFromPreset(Map<String, dynamic> preset) =>
      _rtpcSystemProvider.registerRtpcFromPreset(preset);
  void setRtpc(int rtpcId, double value, {int interpolationMs = 0}) =>
      _rtpcSystemProvider.setRtpc(rtpcId, value, interpolationMs: interpolationMs);
  void setRtpcOnObject(int gameObjectId, int rtpcId, double value, {int interpolationMs = 0}) =>
      _rtpcSystemProvider.setRtpcOnObject(gameObjectId, rtpcId, value, interpolationMs: interpolationMs);
  void resetRtpc(int rtpcId, {int interpolationMs = 100}) =>
      _rtpcSystemProvider.resetRtpc(rtpcId, interpolationMs: interpolationMs);
  void clearObjectRtpcs(int gameObjectId) =>
      _rtpcSystemProvider.clearObjectRtpcs(gameObjectId);
  void updateRtpcCurve(int rtpcId, RtpcCurve curve) =>
      _rtpcSystemProvider.updateRtpcCurve(rtpcId, curve);
  void addRtpcCurvePoint(int rtpcId, RtpcCurvePoint point) =>
      _rtpcSystemProvider.addRtpcCurvePoint(rtpcId, point);
  void removeRtpcCurvePoint(int rtpcId, int pointIndex) =>
      _rtpcSystemProvider.removeRtpcCurvePoint(rtpcId, pointIndex);

  // ═══════════════════════════════════════════════════════════════════════════
  // RTPC BINDINGS (delegated to RtpcSystemProvider)
  // ═══════════════════════════════════════════════════════════════════════════

  RtpcBinding createBinding(int rtpcId, RtpcTargetParameter target, {int? busId, int? eventId}) =>
      _rtpcSystemProvider.createBinding(rtpcId, target, busId: busId, eventId: eventId);
  void updateBindingCurve(int bindingId, RtpcCurve curve) =>
      _rtpcSystemProvider.updateBindingCurve(bindingId, curve);
  void setBindingEnabled(int bindingId, bool enabled) =>
      _rtpcSystemProvider.setBindingEnabled(bindingId, enabled);
  void deleteBinding(int bindingId) => _rtpcSystemProvider.deleteBinding(bindingId);
  List<RtpcBinding> getBindingsForRtpc(int rtpcId) =>
      _rtpcSystemProvider.getBindingsForRtpc(rtpcId);
  List<RtpcBinding> getBindingsForTarget(RtpcTargetParameter target) =>
      _rtpcSystemProvider.getBindingsForTarget(target);
  List<RtpcBinding> getBindingsForBus(int busId) =>
      _rtpcSystemProvider.getBindingsForBus(busId);
  Map<(RtpcTargetParameter, int?), double> evaluateAllBindings() =>
      _rtpcSystemProvider.evaluateAllBindings();

  // ═══════════════════════════════════════════════════════════════════════════
  // DUCKING MATRIX (delegated to DuckingSystemProvider)
  // ═══════════════════════════════════════════════════════════════════════════

  DuckingRule addDuckingRule({
    required String sourceBus,
    required int sourceBusId,
    required String targetBus,
    required int targetBusId,
    double duckAmountDb = -6.0,
    double attackMs = 50.0,
    double releaseMs = 500.0,
    double threshold = 0.01,
    DuckingCurve curve = DuckingCurve.linear,
  }) => _duckingSystemProvider.addRule(
    sourceBus: sourceBus,
    sourceBusId: sourceBusId,
    targetBus: targetBus,
    targetBusId: targetBusId,
    duckAmountDb: duckAmountDb,
    attackMs: attackMs,
    releaseMs: releaseMs,
    threshold: threshold,
    curve: curve,
  );

  void updateDuckingRule(int ruleId, DuckingRule rule) =>
      _duckingSystemProvider.updateRule(ruleId, rule);
  void removeDuckingRule(int ruleId) => _duckingSystemProvider.removeRule(ruleId);
  void setDuckingRuleEnabled(int ruleId, bool enabled) =>
      _duckingSystemProvider.setRuleEnabled(ruleId, enabled);
  DuckingRule? getDuckingRule(int ruleId) => _duckingSystemProvider.getRule(ruleId);

  // ═══════════════════════════════════════════════════════════════════════════
  // BLEND CONTAINERS (delegates to BlendContainersProvider)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a blend container
  BlendContainer createBlendContainer({
    required String name,
    required int rtpcId,
    CrossfadeCurve crossfadeCurve = CrossfadeCurve.equalPower,
  }) => _blendContainersProvider.createContainer(
    name: name,
    rtpcId: rtpcId,
    crossfadeCurve: crossfadeCurve,
  );

  /// Add child to blend container
  void blendContainerAddChild(int containerId, BlendChild child) =>
      _blendContainersProvider.addChild(containerId, child);

  /// Remove child from blend container
  void blendContainerRemoveChild(int containerId, int childId) =>
      _blendContainersProvider.removeChild(containerId, childId);

  /// Remove blend container
  void removeBlendContainer(int containerId) =>
      _blendContainersProvider.removeContainer(containerId);

  /// Get blend container by ID
  BlendContainer? getBlendContainer(int containerId) =>
      _blendContainersProvider.getContainer(containerId);

  /// Evaluate blend weights for RTPC value
  Map<int, double> evaluateBlend(int containerId, double rtpcValue) =>
      _blendContainersProvider.evaluateBlend(containerId, rtpcValue);

  // ═══════════════════════════════════════════════════════════════════════════
  // RANDOM CONTAINERS (delegates to RandomContainersProvider)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a random container
  RandomContainer createRandomContainer({
    required String name,
    RandomMode mode = RandomMode.random,
    int avoidRepeatCount = 2,
  }) => _randomContainersProvider.createContainer(
    name: name,
    mode: mode,
    avoidRepeatCount: avoidRepeatCount,
  );

  /// Add child to random container
  void randomContainerAddChild(int containerId, RandomChild child) =>
      _randomContainersProvider.addChild(containerId, child);

  /// Remove child from random container
  void randomContainerRemoveChild(int containerId, int childId) =>
      _randomContainersProvider.removeChild(containerId, childId);

  /// Update global variation for random container
  void randomContainerSetGlobalVariation(
    int containerId, {
    double pitchMin = 0.0,
    double pitchMax = 0.0,
    double volumeMin = 0.0,
    double volumeMax = 0.0,
  }) => _randomContainersProvider.setGlobalVariation(
    containerId,
    pitchMin: pitchMin,
    pitchMax: pitchMax,
    volumeMin: volumeMin,
    volumeMax: volumeMax,
  );

  /// Remove random container
  void removeRandomContainer(int containerId) =>
      _randomContainersProvider.removeContainer(containerId);

  /// Get random container by ID
  RandomContainer? getRandomContainer(int containerId) =>
      _randomContainersProvider.getContainer(containerId);

  /// Select random child with avoid-repeat logic
  RandomChildSelection? selectRandomChild(int containerId) =>
      _randomContainersProvider.selectChild(containerId);

  // ═══════════════════════════════════════════════════════════════════════════
  // SEQUENCE CONTAINERS (delegates to SequenceContainersProvider)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a sequence container
  SequenceContainer createSequenceContainer({
    required String name,
    SequenceEndBehavior endBehavior = SequenceEndBehavior.stop,
    double speed = 1.0,
  }) => _sequenceContainersProvider.createContainer(
    name: name,
    endBehavior: endBehavior,
    speed: speed,
  );

  /// Add step to sequence container
  void sequenceContainerAddStep(int containerId, SequenceStep step) =>
      _sequenceContainersProvider.addStep(containerId, step);

  /// Remove step from sequence container
  void sequenceContainerRemoveStep(int containerId, int stepIndex) =>
      _sequenceContainersProvider.removeStep(containerId, stepIndex);

  /// Remove sequence container
  void removeSequenceContainer(int containerId) =>
      _sequenceContainersProvider.removeContainer(containerId);

  /// Get sequence container by ID
  SequenceContainer? getSequenceContainer(int containerId) =>
      _sequenceContainersProvider.getContainer(containerId);

  /// Play sequence (with optional step callback)
  void playSequence(int containerId, {void Function(SequenceStep, int)? onStep}) =>
      _sequenceContainersProvider.play(containerId, onStep: onStep);

  /// Stop sequence
  void stopSequence(int containerId) =>
      _sequenceContainersProvider.stop(containerId);

  /// Check if sequence is playing
  bool isSequencePlaying(int containerId) =>
      _sequenceContainersProvider.isPlaying(containerId);

  // ═══════════════════════════════════════════════════════════════════════════
  // MUSIC SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add music segment (delegates to MusicSystemProvider)
  MusicSegment addMusicSegment({
    required String name,
    required int soundId,
    double tempo = 120.0,
    int beatsPerBar = 4,
    int durationBars = 4,
  }) {
    return _musicSystemProvider.addMusicSegment(
      name: name,
      soundId: soundId,
      tempo: tempo,
      beatsPerBar: beatsPerBar,
      durationBars: durationBars,
    );
  }

  /// Add marker to music segment (delegates to MusicSystemProvider)
  void musicSegmentAddMarker(int segmentId, MusicMarker marker) {
    _musicSystemProvider.addMusicMarker(
      segmentId,
      name: marker.name,
      positionBars: marker.positionBars,
      markerType: marker.markerType,
    );
  }

  /// Remove music segment (delegates to MusicSystemProvider)
  void removeMusicSegment(int segmentId) {
    _musicSystemProvider.removeMusicSegment(segmentId);
  }

  /// Get music segment by ID (delegates to MusicSystemProvider)
  MusicSegment? getMusicSegment(int segmentId) => _musicSystemProvider.getMusicSegment(segmentId);

  /// Set current music segment (delegates to MusicSystemProvider)
  void setCurrentMusicSegment(int segmentId) {
    _musicSystemProvider.setCurrentMusicSegment(segmentId);
  }

  /// Queue next music segment for transition (delegates to MusicSystemProvider)
  void queueMusicSegment(int segmentId) {
    _musicSystemProvider.queueMusicSegment(segmentId);
  }

  /// Set music bus ID (delegates to MusicSystemProvider)
  void setMusicBusId(int busId) {
    _musicSystemProvider.setMusicBusId(busId);
  }

  /// Add stinger (delegates to MusicSystemProvider)
  Stinger addStinger({
    required String name,
    required int soundId,
    MusicSyncPoint syncPoint = MusicSyncPoint.beat,
    double customGridBeats = 4.0,
    double musicDuckDb = 0.0,
    double duckAttackMs = 10.0,
    double duckReleaseMs = 100.0,
    int priority = 50,
    bool canInterrupt = false,
  }) {
    return _musicSystemProvider.addStinger(
      name: name,
      soundId: soundId,
      syncPoint: syncPoint,
      customGridBeats: customGridBeats,
      musicDuckDb: musicDuckDb,
      duckAttackMs: duckAttackMs,
      duckReleaseMs: duckReleaseMs,
      priority: priority,
      canInterrupt: canInterrupt,
    );
  }

  /// Remove stinger (delegates to MusicSystemProvider)
  void removeStinger(int stingerId) {
    _musicSystemProvider.removeStinger(stingerId);
  }

  /// Get stinger by ID (delegates to MusicSystemProvider)
  Stinger? getStinger(int stingerId) => _musicSystemProvider.getStinger(stingerId);

  // ═══════════════════════════════════════════════════════════════════════════
  // ATTENUATION SYSTEM (delegated to AttenuationCurveProvider)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add attenuation curve (delegates to AttenuationCurveProvider)
  AttenuationCurve addAttenuationCurve({
    required String name,
    required AttenuationType attenuationType,
    double inputMin = 0.0,
    double inputMax = 1.0,
    double outputMin = 0.0,
    double outputMax = 1.0,
    RtpcCurveShape curveShape = RtpcCurveShape.linear,
  }) {
    return _attenuationCurveProvider.addCurve(
      name: name,
      type: attenuationType,
      inputMin: inputMin,
      inputMax: inputMax,
      outputMin: outputMin,
      outputMax: outputMax,
      curveShape: curveShape,
    );
  }

  /// Update attenuation curve (delegates to AttenuationCurveProvider)
  void updateAttenuationCurve(int curveId, AttenuationCurve curve) {
    _attenuationCurveProvider.updateCurve(curveId, curve);
  }

  /// Remove attenuation curve (delegates to AttenuationCurveProvider)
  void removeAttenuationCurve(int curveId) {
    _attenuationCurveProvider.removeCurve(curveId);
  }

  /// Enable/disable attenuation curve (delegates to AttenuationCurveProvider)
  void setAttenuationCurveEnabled(int curveId, bool enabled) {
    _attenuationCurveProvider.setCurveEnabled(curveId, enabled);
  }

  /// Evaluate attenuation curve (delegates to AttenuationCurveProvider)
  double evaluateAttenuationCurve(int curveId, double input) {
    return _attenuationCurveProvider.evaluateCurve(curveId, input);
  }

  /// Get attenuation curve by ID (delegates to AttenuationCurveProvider)
  AttenuationCurve? getAttenuationCurve(int curveId) => _attenuationCurveProvider.getCurve(curveId);

  /// Get attenuation curves by type (delegates to AttenuationCurveProvider)
  List<AttenuationCurve> getAttenuationCurvesByType(AttenuationType type) {
    return _attenuationCurveProvider.getCurvesByType(type);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GAME OBJECT MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a game object
  void registerGameObject(int gameObjectId, {String? name}) {
    _ffi.middlewareRegisterGameObject(gameObjectId, name: name ?? 'Object_$gameObjectId');
  }

  /// Unregister a game object (clears all its switches/RTPCs)
  void unregisterGameObject(int gameObjectId) {
    _switchGroupsProvider.clearObjectSwitches(gameObjectId);
    _rtpcSystemProvider.clearObjectRtpcs(gameObjectId);
    _ffi.middlewareUnregisterGameObject(gameObjectId);
    _markChanged(changeAll);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export all state to JSON
  Map<String, dynamic> toJson() => {
    'stateGroups': _stateGroupsProvider.toJson(),
    'switchGroups': _switchGroupsProvider.toJson(),
    'rtpcDefs': _rtpcSystemProvider.rtpcDefsToJson(),
    'rtpcBindings': _rtpcSystemProvider.bindingsToJson(),
    'objectSwitches': _switchGroupsProvider.objectSwitchesToJson(),
    'objectRtpcs': _rtpcSystemProvider.objectRtpcsToJson(),
    'duckingRules': _duckingSystemProvider.toJson(),
  };

  /// Load state from JSON
  void fromJson(Map<String, dynamic> json) {
    _stateGroupsProvider.clear();
    _switchGroupsProvider.clear();
    _rtpcSystemProvider.clear();
    _duckingSystemProvider.clear();

    // Load state groups
    final stateGroupsList = json['stateGroups'] as List<dynamic>?;
    if (stateGroupsList != null) {
      _stateGroupsProvider.fromJson(stateGroupsList);
    }

    // Load switch groups
    final switchGroupsList = json['switchGroups'] as List<dynamic>?;
    if (switchGroupsList != null) {
      _switchGroupsProvider.fromJson(switchGroupsList);
    }

    // Load object switches
    final objectSwitchesJson = json['objectSwitches'] as Map<String, dynamic>?;
    if (objectSwitchesJson != null) {
      _switchGroupsProvider.objectSwitchesFromJson(objectSwitchesJson);
    }

    // Load RTPCs
    final rtpcList = json['rtpcDefs'] as List<dynamic>?;
    if (rtpcList != null) {
      _rtpcSystemProvider.rtpcDefsFromJson(rtpcList);
    }

    // Load RTPC bindings
    final bindingsList = json['rtpcBindings'] as List<dynamic>?;
    if (bindingsList != null) {
      _rtpcSystemProvider.bindingsFromJson(bindingsList);
    }

    // Load object RTPCs
    final objectRtpcsJson = json['objectRtpcs'] as Map<String, dynamic>?;
    if (objectRtpcsJson != null) {
      _rtpcSystemProvider.objectRtpcsFromJson(objectRtpcsJson);
    }

    // Load ducking rules
    final duckingRulesList = json['duckingRules'] as List<dynamic>?;
    if (duckingRulesList != null) {
      _duckingSystemProvider.fromJson(duckingRulesList);
    }

    _markChanged(changeAll);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  void _initializeDefaults() {
    // Register default state groups from constants
    kStateGroups.forEach((name, states) {
      registerStateGroupFromPreset(name, states);
    });

    // Register default switch groups
    for (final name in kSwitchGroups) {
      // Create some example switches for each group
      final switches = ['Default', 'Variant_A', 'Variant_B', 'Variant_C'];
      registerSwitchGroupFromPreset(name, switches);
    }

    // Register default RTPCs
    for (final preset in kDefaultRtpcDefinitions) {
      registerRtpcFromPreset(preset);
    }
  }

  /// Get stats for debugging
  ({
    int stateGroups,
    int switchGroups,
    int rtpcs,
    int objectsWithSwitches,
    int objectsWithRtpcs,
    int duckingRules,
    int blendContainers,
    int randomContainers,
    int sequenceContainers,
    int musicSegments,
    int stingers,
    int attenuationCurves,
  }) get stats {
    return (
      stateGroups: _stateGroupsProvider.stateGroups.length,
      switchGroups: _switchGroupsProvider.switchGroups.length,
      rtpcs: _rtpcSystemProvider.rtpcCount,
      objectsWithSwitches: _switchGroupsProvider.objectSwitchesCount,
      objectsWithRtpcs: _rtpcSystemProvider.objectsWithRtpcsCount,
      duckingRules: _duckingSystemProvider.ruleCount,
      blendContainers: _blendContainersProvider.containerCount,
      randomContainers: _randomContainersProvider.containerCount,
      sequenceContainers: _sequenceContainersProvider.containerCount,
      musicSegments: _musicSystemProvider.segmentCount,
      stingers: _musicSystemProvider.stingerCount,
      attenuationCurves: _attenuationCurveProvider.curveCount,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADDITIONAL UI CONVENIENCE METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update ducking rule using just the rule (extracts id from rule.id)
  void saveDuckingRule(DuckingRule rule) {
    updateDuckingRule(rule.id, rule);
  }

  /// Add blend container (convenience)
  BlendContainer addBlendContainer({required String name, required int rtpcId}) =>
      createBlendContainer(name: name, rtpcId: rtpcId);

  /// Update blend container
  void updateBlendContainer(BlendContainer container) =>
      _blendContainersProvider.updateContainer(container);

  /// Add blend child
  /// Add blend child (P2.7 FIX: enforces max child limit)
  void addBlendChild(int containerId, {required String name, required double rtpcStart, required double rtpcEnd}) {
    final currentCount = _blendContainersProvider.getContainer(containerId)?.children.length ?? 0;
    if (currentCount >= kMaxContainerChildren) {
      debugPrint('[MiddlewareProvider] Cannot add blend child: limit reached ($kMaxContainerChildren)');
      return;
    }
    final nextId = currentCount + 1;
    blendContainerAddChild(containerId, BlendChild(id: nextId, name: name, rtpcStart: rtpcStart, rtpcEnd: rtpcEnd));
  }

  /// Update blend child
  void updateBlendChild(int containerId, BlendChild child) =>
      _blendContainersProvider.updateChild(containerId, child);

  /// Remove blend child
  void removeBlendChild(int containerId, int childId) =>
      blendContainerRemoveChild(containerId, childId);

  /// Add random container (convenience)
  RandomContainer addRandomContainer({required String name}) =>
      createRandomContainer(name: name);

  /// Update random container
  void updateRandomContainer(RandomContainer container) =>
      _randomContainersProvider.updateContainer(container);

  /// Add random child (P2.7 FIX: enforces max child limit)
  void addRandomChild(int containerId, {required String name, required double weight}) {
    final currentCount = _randomContainersProvider.getContainer(containerId)?.children.length ?? 0;
    if (currentCount >= kMaxContainerChildren) {
      debugPrint('[MiddlewareProvider] Cannot add random child: limit reached ($kMaxContainerChildren)');
      return;
    }
    final nextId = currentCount + 1;
    randomContainerAddChild(containerId, RandomChild(id: nextId, name: name, weight: weight));
  }

  /// Update random child
  void updateRandomChild(int containerId, RandomChild child) =>
      _randomContainersProvider.updateChild(containerId, child);

  /// Remove random child
  void removeRandomChild(int containerId, int childId) =>
      randomContainerRemoveChild(containerId, childId);

  /// Add sequence container (convenience)
  SequenceContainer addSequenceContainer({required String name}) =>
      createSequenceContainer(name: name);

  /// Update sequence container
  void updateSequenceContainer(SequenceContainer container) =>
      _sequenceContainersProvider.updateContainer(container);

  /// Add sequence step (P2.7 FIX: enforces max child limit)
  void addSequenceStep(int containerId, {required int childId, required String childName, required double delayMs, required double durationMs}) {
    final currentCount = _sequenceContainersProvider.getContainer(containerId)?.steps.length ?? 0;
    if (currentCount >= kMaxContainerChildren) {
      debugPrint('[MiddlewareProvider] Cannot add sequence step: limit reached ($kMaxContainerChildren)');
      return;
    }
    final nextIndex = currentCount;
    sequenceContainerAddStep(containerId, SequenceStep(index: nextIndex, childId: childId, childName: childName, delayMs: delayMs, durationMs: durationMs));
  }

  /// Update sequence step
  void updateSequenceStep(int containerId, int stepIndex, SequenceStep step) =>
      _sequenceContainersProvider.updateStep(containerId, stepIndex, step);

  /// Remove sequence step
  void removeSequenceStep(int containerId, int stepIndex) =>
      sequenceContainerRemoveStep(containerId, stepIndex);

  /// Update music segment (delegates to MusicSystemProvider)
  void updateMusicSegment(MusicSegment segment) {
    _musicSystemProvider.updateMusicSegment(segment);
  }

  /// Add music marker (convenience, delegates to MusicSystemProvider)
  void addMusicMarker(int segmentId, {required String name, required double positionBars, required MarkerType markerType}) {
    _musicSystemProvider.addMusicMarker(segmentId, name: name, positionBars: positionBars, markerType: markerType);
  }

  /// Update stinger (delegates to MusicSystemProvider)
  void updateStinger(Stinger stinger) {
    _musicSystemProvider.updateStinger(stinger);
  }

  /// Save attenuation curve using just the curve (extracts id from curve.id)
  void saveAttenuationCurve(AttenuationCurve curve) {
    updateAttenuationCurve(curve.id, curve);
  }

  /// Add attenuation curve (simplified version for UI)
  /// Delegates to AttenuationCurveProvider
  AttenuationCurve addSimpleAttenuationCurve({required String name, required AttenuationType type}) {
    return _attenuationCurveProvider.addCurve(name: name, type: type);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SLOT MACHINE PRESET
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load complete slot machine audio preset
  /// This sets up all middleware components for a professional slot game
  void loadSlotMachinePreset() {
    // Clear existing data
    _clearAll();

    // ══════════════════════════════════════════════════════════════════════
    // 1. STATE GROUPS - Global game states
    // ══════════════════════════════════════════════════════════════════════
    registerStateGroupFromPreset('GamePhase', [
      'Idle',
      'Spinning',
      'Anticipation',
      'Win',
      'BigWin',
      'MegaWin',
      'Jackpot',
    ]);

    registerStateGroupFromPreset('BonusMode', [
      'None',
      'FreeSpins',
      'PickBonus',
      'WheelBonus',
      'CascadeBonus',
    ]);

    registerStateGroupFromPreset('MusicIntensity', [
      'Calm',
      'Medium',
      'High',
      'Extreme',
    ]);

    registerStateGroupFromPreset('WinTier', [
      'NoWin',
      'SmallWin',
      'MediumWin',
      'BigWin',
      'MegaWin',
      'UltraWin',
      'Jackpot',
    ]);

    registerStateGroupFromPreset('GameMode', [
      'BaseGame',
      'Bonus',
      'FreeSpins',
      'Gamble',
      'Paused',
    ]);

    // ══════════════════════════════════════════════════════════════════════
    // 2. SWITCH GROUPS - Per-object sound variants
    // ══════════════════════════════════════════════════════════════════════
    registerSwitchGroupFromPreset('ReelTheme', [
      'Classic',
      'Egyptian',
      'Asian',
      'SciFi',
      'Fantasy',
      'Vegas',
    ]);

    registerSwitchGroupFromPreset('SymbolType', [
      'Low_9',
      'Low_10',
      'Low_J',
      'Low_Q',
      'Low_K',
      'Low_A',
      'High_1',
      'High_2',
      'High_3',
      'Wild',
      'Scatter',
      'Bonus',
    ]);

    registerSwitchGroupFromPreset('WinLineStyle', [
      'Standard',
      'Cascade',
      'MegaWays',
      'ClusterPays',
      'AllWays',
    ]);

    registerSwitchGroupFromPreset('ReelPosition', [
      'Reel_1',
      'Reel_2',
      'Reel_3',
      'Reel_4',
      'Reel_5',
      'Reel_6',
    ]);

    registerSwitchGroupFromPreset('UIElement', [
      'Button_Spin',
      'Button_MaxBet',
      'Button_AutoPlay',
      'Button_Menu',
      'Toggle',
      'Slider',
    ]);

    // ══════════════════════════════════════════════════════════════════════
    // 3. RTPCs - Real-Time Parameter Controls
    // ══════════════════════════════════════════════════════════════════════
    registerRtpcFromPreset({
      'id': 1000,
      'name': 'WinAmount',
      'min': 0.0,
      'max': 100000.0,
      'default': 0.0,
    });

    registerRtpcFromPreset({
      'id': 1001,
      'name': 'WinMultiplier',
      'min': 1.0,
      'max': 1000.0,
      'default': 1.0,
    });

    registerRtpcFromPreset({
      'id': 1002,
      'name': 'SpinSpeed',
      'min': 0.5,
      'max': 3.0,
      'default': 1.0,
    });

    registerRtpcFromPreset({
      'id': 1003,
      'name': 'Anticipation',
      'min': 0.0,
      'max': 1.0,
      'default': 0.0,
    });

    registerRtpcFromPreset({
      'id': 1004,
      'name': 'NearWinIntensity',
      'min': 0.0,
      'max': 1.0,
      'default': 0.0,
    });

    registerRtpcFromPreset({
      'id': 1005,
      'name': 'BonusProgress',
      'min': 0.0,
      'max': 100.0,
      'default': 0.0,
    });

    registerRtpcFromPreset({
      'id': 1006,
      'name': 'ComboCount',
      'min': 0.0,
      'max': 50.0,
      'default': 0.0,
    });

    registerRtpcFromPreset({
      'id': 1007,
      'name': 'JackpotProgress',
      'min': 0.0,
      'max': 100.0,
      'default': 0.0,
    });

    registerRtpcFromPreset({
      'id': 1008,
      'name': 'TotalBet',
      'min': 0.1,
      'max': 1000.0,
      'default': 1.0,
    });

    registerRtpcFromPreset({
      'id': 1009,
      'name': 'FreeSpinsRemaining',
      'min': 0.0,
      'max': 100.0,
      'default': 0.0,
    });

    // ══════════════════════════════════════════════════════════════════════
    // 4. DUCKING RULES - Auto volume reduction
    // ══════════════════════════════════════════════════════════════════════
    addDuckingRule(
      sourceBus: 'VO',
      sourceBusId: 8,
      targetBus: 'Music',
      targetBusId: 1,
      duckAmountDb: -12.0,
      attackMs: 30.0,
      releaseMs: 500.0,
      threshold: 0.01,
      curve: DuckingCurve.exponential,
    );

    addDuckingRule(
      sourceBus: 'BigWin',
      sourceBusId: 7,
      targetBus: 'Ambience',
      targetBusId: 5,
      duckAmountDb: -18.0,
      attackMs: 20.0,
      releaseMs: 800.0,
      threshold: 0.01,
      curve: DuckingCurve.linear,
    );

    addDuckingRule(
      sourceBus: 'Jackpot',
      sourceBusId: 9,
      targetBus: 'Music',
      targetBusId: 1,
      duckAmountDb: -24.0,
      attackMs: 10.0,
      releaseMs: 1000.0,
      threshold: 0.01,
      curve: DuckingCurve.sCurve,
    );

    addDuckingRule(
      sourceBus: 'Anticipation',
      sourceBusId: 10,
      targetBus: 'Music',
      targetBusId: 1,
      duckAmountDb: -6.0,
      attackMs: 100.0,
      releaseMs: 300.0,
      threshold: 0.05,
      curve: DuckingCurve.linear,
    );

    // ══════════════════════════════════════════════════════════════════════
    // 5. BLEND CONTAINERS - RTPC-based crossfade
    // ══════════════════════════════════════════════════════════════════════
    final musicBlend = createBlendContainer(
      name: 'MusicIntensityBlend',
      rtpcId: 1003, // Anticipation
      crossfadeCurve: CrossfadeCurve.equalPower,
    );
    blendContainerAddChild(musicBlend.id, const BlendChild(
      id: 1,
      name: 'Music_Calm',
      rtpcStart: 0.0,
      rtpcEnd: 0.4,
    ));
    blendContainerAddChild(musicBlend.id, const BlendChild(
      id: 2,
      name: 'Music_Medium',
      rtpcStart: 0.3,
      rtpcEnd: 0.7,
    ));
    blendContainerAddChild(musicBlend.id, const BlendChild(
      id: 3,
      name: 'Music_Intense',
      rtpcStart: 0.6,
      rtpcEnd: 1.0,
    ));

    final winBlend = createBlendContainer(
      name: 'WinCelebrationBlend',
      rtpcId: 1000, // WinAmount
      crossfadeCurve: CrossfadeCurve.sCurve,
    );
    blendContainerAddChild(winBlend.id, const BlendChild(
      id: 1,
      name: 'Win_Small_Jingle',
      rtpcStart: 0.0,
      rtpcEnd: 1000.0,
    ));
    blendContainerAddChild(winBlend.id, const BlendChild(
      id: 2,
      name: 'Win_Medium_Fanfare',
      rtpcStart: 500.0,
      rtpcEnd: 10000.0,
    ));
    blendContainerAddChild(winBlend.id, const BlendChild(
      id: 3,
      name: 'Win_Big_Orchestra',
      rtpcStart: 5000.0,
      rtpcEnd: 100000.0,
    ));

    // ══════════════════════════════════════════════════════════════════════
    // 6. RANDOM CONTAINERS - Variation
    // ══════════════════════════════════════════════════════════════════════
    final reelStop = createRandomContainer(
      name: 'ReelStop_Variations',
      mode: RandomMode.shuffle,
      avoidRepeatCount: 3,
    );
    randomContainerAddChild(reelStop.id, const RandomChild(id: 1, name: 'ReelStop_01', weight: 1.0));
    randomContainerAddChild(reelStop.id, const RandomChild(id: 2, name: 'ReelStop_02', weight: 1.0));
    randomContainerAddChild(reelStop.id, const RandomChild(id: 3, name: 'ReelStop_03', weight: 1.0));
    randomContainerAddChild(reelStop.id, const RandomChild(id: 4, name: 'ReelStop_04', weight: 1.0));
    randomContainerAddChild(reelStop.id, const RandomChild(id: 5, name: 'ReelStop_05', weight: 1.0));
    randomContainerSetGlobalVariation(reelStop.id, pitchMin: -50.0, pitchMax: 50.0, volumeMin: -2.0, volumeMax: 2.0);

    final coinDrop = createRandomContainer(
      name: 'CoinDrop_Variations',
      mode: RandomMode.random,
      avoidRepeatCount: 2,
    );
    randomContainerAddChild(coinDrop.id, const RandomChild(id: 1, name: 'Coin_01', weight: 1.0));
    randomContainerAddChild(coinDrop.id, const RandomChild(id: 2, name: 'Coin_02', weight: 1.0));
    randomContainerAddChild(coinDrop.id, const RandomChild(id: 3, name: 'Coin_03', weight: 1.0));
    randomContainerAddChild(coinDrop.id, const RandomChild(id: 4, name: 'Coin_04', weight: 1.0));
    randomContainerAddChild(coinDrop.id, const RandomChild(id: 5, name: 'Coin_05', weight: 1.0));
    randomContainerAddChild(coinDrop.id, const RandomChild(id: 6, name: 'Coin_06', weight: 1.0));
    randomContainerAddChild(coinDrop.id, const RandomChild(id: 7, name: 'Coin_07', weight: 1.0));
    randomContainerAddChild(coinDrop.id, const RandomChild(id: 8, name: 'Coin_08', weight: 1.0));

    final uiClick = createRandomContainer(
      name: 'UI_Click_Variations',
      mode: RandomMode.roundRobin,
      avoidRepeatCount: 0,
    );
    randomContainerAddChild(uiClick.id, const RandomChild(id: 1, name: 'Click_01', weight: 1.0));
    randomContainerAddChild(uiClick.id, const RandomChild(id: 2, name: 'Click_02', weight: 1.0));
    randomContainerAddChild(uiClick.id, const RandomChild(id: 3, name: 'Click_03', weight: 1.0));

    final ambientHit = createRandomContainer(
      name: 'Ambient_Stingers',
      mode: RandomMode.random,
      avoidRepeatCount: 4,
    );
    randomContainerAddChild(ambientHit.id, const RandomChild(id: 1, name: 'Ambient_Rare_01', weight: 0.1));
    randomContainerAddChild(ambientHit.id, const RandomChild(id: 2, name: 'Ambient_Rare_02', weight: 0.1));
    randomContainerAddChild(ambientHit.id, const RandomChild(id: 3, name: 'Ambient_Common_01', weight: 0.4));
    randomContainerAddChild(ambientHit.id, const RandomChild(id: 4, name: 'Ambient_Common_02', weight: 0.4));

    // ══════════════════════════════════════════════════════════════════════
    // 7. SEQUENCE CONTAINERS - Timed sequences
    // ══════════════════════════════════════════════════════════════════════
    final spinCycle = createSequenceContainer(
      name: 'SpinCycle',
      endBehavior: SequenceEndBehavior.stop,
      speed: 1.0,
    );
    sequenceContainerAddStep(spinCycle.id, const SequenceStep(index: 0, childId: 400, childName: 'Button_Press', delayMs: 0, durationMs: 100));
    sequenceContainerAddStep(spinCycle.id, const SequenceStep(index: 1, childId: 401, childName: 'Reel_Start', delayMs: 50, durationMs: 200));
    sequenceContainerAddStep(spinCycle.id, const SequenceStep(index: 2, childId: 402, childName: 'Spinning_Loop', delayMs: 0, durationMs: 2000));
    sequenceContainerAddStep(spinCycle.id, const SequenceStep(index: 3, childId: 403, childName: 'Reel_Stop_1', delayMs: 0, durationMs: 150));
    sequenceContainerAddStep(spinCycle.id, const SequenceStep(index: 4, childId: 404, childName: 'Reel_Stop_2', delayMs: 300, durationMs: 150));
    sequenceContainerAddStep(spinCycle.id, const SequenceStep(index: 5, childId: 405, childName: 'Reel_Stop_3', delayMs: 300, durationMs: 150));
    sequenceContainerAddStep(spinCycle.id, const SequenceStep(index: 6, childId: 406, childName: 'Reel_Stop_4', delayMs: 300, durationMs: 150));
    sequenceContainerAddStep(spinCycle.id, const SequenceStep(index: 7, childId: 407, childName: 'Reel_Stop_5', delayMs: 300, durationMs: 150));
    sequenceContainerAddStep(spinCycle.id, const SequenceStep(index: 8, childId: 408, childName: 'Result_Reveal', delayMs: 200, durationMs: 300));

    final bigWinCelebration = createSequenceContainer(
      name: 'BigWinCelebration',
      endBehavior: SequenceEndBehavior.stop,
      speed: 1.0,
    );
    sequenceContainerAddStep(bigWinCelebration.id, const SequenceStep(index: 0, childId: 500, childName: 'Buildup', delayMs: 0, durationMs: 1000));
    sequenceContainerAddStep(bigWinCelebration.id, const SequenceStep(index: 1, childId: 501, childName: 'Impact_Hit', delayMs: 0, durationMs: 500));
    sequenceContainerAddStep(bigWinCelebration.id, const SequenceStep(index: 2, childId: 502, childName: 'Coin_Shower', delayMs: 200, durationMs: 3000));
    sequenceContainerAddStep(bigWinCelebration.id, const SequenceStep(index: 3, childId: 503, childName: 'Music_Swell', delayMs: 0, durationMs: 4000));
    sequenceContainerAddStep(bigWinCelebration.id, const SequenceStep(index: 4, childId: 504, childName: 'VO_BigWin', delayMs: 500, durationMs: 2000));

    final anticipationSequence = createSequenceContainer(
      name: 'Anticipation_NearWin',
      endBehavior: SequenceEndBehavior.stop,
      speed: 1.0,
    );
    sequenceContainerAddStep(anticipationSequence.id, const SequenceStep(index: 0, childId: 600, childName: 'Tick_1', delayMs: 0, durationMs: 200));
    sequenceContainerAddStep(anticipationSequence.id, const SequenceStep(index: 1, childId: 601, childName: 'Tick_2', delayMs: 150, durationMs: 200));
    sequenceContainerAddStep(anticipationSequence.id, const SequenceStep(index: 2, childId: 602, childName: 'Tick_3', delayMs: 150, durationMs: 200));
    sequenceContainerAddStep(anticipationSequence.id, const SequenceStep(index: 3, childId: 603, childName: 'Tension_Rise', delayMs: 100, durationMs: 1000));
    sequenceContainerAddStep(anticipationSequence.id, const SequenceStep(index: 4, childId: 604, childName: 'Release', delayMs: 0, durationMs: 500));

    final bonusIntro = createSequenceContainer(
      name: 'BonusIntro',
      endBehavior: SequenceEndBehavior.stop,
      speed: 1.0,
    );
    sequenceContainerAddStep(bonusIntro.id, const SequenceStep(index: 0, childId: 700, childName: 'Transition_Whoosh', delayMs: 0, durationMs: 300));
    sequenceContainerAddStep(bonusIntro.id, const SequenceStep(index: 1, childId: 701, childName: 'Door_Open', delayMs: 100, durationMs: 500));
    sequenceContainerAddStep(bonusIntro.id, const SequenceStep(index: 2, childId: 702, childName: 'Bonus_Music_Start', delayMs: 0, durationMs: 1000));
    sequenceContainerAddStep(bonusIntro.id, const SequenceStep(index: 3, childId: 703, childName: 'VO_Welcome_Bonus', delayMs: 500, durationMs: 2000));

    // ══════════════════════════════════════════════════════════════════════
    // 8. MUSIC SYSTEM - Segments & Stingers
    // ══════════════════════════════════════════════════════════════════════
    final baseGameIntro = addMusicSegment(
      name: 'BaseGame_Intro',
      soundId: 800,
      tempo: 120.0,
      beatsPerBar: 4,
      durationBars: 4,
    );
    musicSegmentAddMarker(baseGameIntro.id, const MusicMarker(name: 'Intro_Start', positionBars: 0.0, markerType: MarkerType.entry));
    musicSegmentAddMarker(baseGameIntro.id, const MusicMarker(name: 'Intro_End', positionBars: 4.0, markerType: MarkerType.exit));

    final baseGameLoop = addMusicSegment(
      name: 'BaseGame_Loop',
      soundId: 801,
      tempo: 120.0,
      beatsPerBar: 4,
      durationBars: 8,
    );
    musicSegmentAddMarker(baseGameLoop.id, const MusicMarker(name: 'Loop_A', positionBars: 0.0, markerType: MarkerType.sync));
    musicSegmentAddMarker(baseGameLoop.id, const MusicMarker(name: 'Loop_B', positionBars: 4.0, markerType: MarkerType.sync));

    final bonusLoop = addMusicSegment(
      name: 'Bonus_Loop',
      soundId: 802,
      tempo: 140.0,
      beatsPerBar: 4,
      durationBars: 8,
    );
    musicSegmentAddMarker(bonusLoop.id, const MusicMarker(name: 'Bonus_Drop', positionBars: 0.0, markerType: MarkerType.sync));

    final freeSpinsLoop = addMusicSegment(
      name: 'FreeSpins_Loop',
      soundId: 803,
      tempo: 130.0,
      beatsPerBar: 4,
      durationBars: 8,
    );

    final jackpotFanfare = addMusicSegment(
      name: 'Jackpot_Fanfare',
      soundId: 804,
      tempo: 120.0,
      beatsPerBar: 4,
      durationBars: 8,
    );

    // Stingers
    addStinger(
      name: 'WinHit_Small',
      soundId: 900,
      syncPoint: MusicSyncPoint.beat,
      musicDuckDb: -3.0,
      duckAttackMs: 10.0,
      duckReleaseMs: 200.0,
      priority: 30,
    );

    addStinger(
      name: 'WinHit_Medium',
      soundId: 901,
      syncPoint: MusicSyncPoint.beat,
      musicDuckDb: -6.0,
      duckAttackMs: 10.0,
      duckReleaseMs: 300.0,
      priority: 50,
    );

    addStinger(
      name: 'WinHit_Big',
      soundId: 902,
      syncPoint: MusicSyncPoint.bar,
      musicDuckDb: -12.0,
      duckAttackMs: 5.0,
      duckReleaseMs: 500.0,
      priority: 70,
      canInterrupt: true,
    );

    addStinger(
      name: 'ScatterLand',
      soundId: 903,
      syncPoint: MusicSyncPoint.immediate,
      musicDuckDb: -6.0,
      duckAttackMs: 5.0,
      duckReleaseMs: 200.0,
      priority: 60,
    );

    addStinger(
      name: 'BonusTrigger',
      soundId: 904,
      syncPoint: MusicSyncPoint.bar,
      musicDuckDb: -18.0,
      duckAttackMs: 5.0,
      duckReleaseMs: 1000.0,
      priority: 90,
      canInterrupt: true,
    );

    addStinger(
      name: 'JackpotHit',
      soundId: 905,
      syncPoint: MusicSyncPoint.immediate,
      musicDuckDb: -96.0, // Effectively mute
      duckAttackMs: 1.0,
      duckReleaseMs: 2000.0,
      priority: 100,
      canInterrupt: true,
    );

    addStinger(
      name: 'FreeSpinAwarded',
      soundId: 906,
      syncPoint: MusicSyncPoint.beat,
      musicDuckDb: -6.0,
      duckAttackMs: 10.0,
      duckReleaseMs: 300.0,
      priority: 40,
    );

    // ══════════════════════════════════════════════════════════════════════
    // 9. ATTENUATION CURVES - Slot-specific curves
    // ══════════════════════════════════════════════════════════════════════
    addAttenuationCurve(
      name: 'WinAmount_Volume',
      attenuationType: AttenuationType.winAmount,
      inputMin: 0.0,
      inputMax: 100000.0,
      outputMin: 0.3,
      outputMax: 1.0,
      curveShape: RtpcCurveShape.log3,
    );

    addAttenuationCurve(
      name: 'WinAmount_Duration',
      attenuationType: AttenuationType.timeElapsed,
      inputMin: 0.0,
      inputMax: 100000.0,
      outputMin: 1.0,
      outputMax: 15.0,
      curveShape: RtpcCurveShape.sCurve,
    );

    addAttenuationCurve(
      name: 'NearWin_Tension',
      attenuationType: AttenuationType.nearWin,
      inputMin: 0.0,
      inputMax: 5.0, // Symbols matching (0-5)
      outputMin: 0.0,
      outputMax: 1.0,
      curveShape: RtpcCurveShape.exp3,
    );

    addAttenuationCurve(
      name: 'Multiplier_Excitement',
      attenuationType: AttenuationType.comboMultiplier,
      inputMin: 1.0,
      inputMax: 100.0,
      outputMin: 0.0,
      outputMax: 1.0,
      curveShape: RtpcCurveShape.log3,
    );

    addAttenuationCurve(
      name: 'ComboCount_Intensity',
      attenuationType: AttenuationType.comboMultiplier,
      inputMin: 0.0,
      inputMax: 20.0,
      outputMin: 0.0,
      outputMax: 1.0,
      curveShape: RtpcCurveShape.linear,
    );

    addAttenuationCurve(
      name: 'BonusProgress_Music',
      attenuationType: AttenuationType.featureProgress,
      inputMin: 0.0,
      inputMax: 100.0,
      outputMin: 0.5,
      outputMax: 1.0,
      curveShape: RtpcCurveShape.sCurve,
    );

    _markChanged(changeAll);
  }

  /// Clear all middleware data
  void _clearAll() {
    _stateGroupsProvider.clear();
    _switchGroupsProvider.clear();
    _rtpcSystemProvider.clear();
    _duckingSystemProvider.clear();
    _blendContainersProvider.clear();
    _randomContainersProvider.clear();
    _sequenceContainersProvider.clear();
    _musicSystemProvider.clear();
    _attenuationCurveProvider.clear();
  }

  /// Clear all and reinitialize with defaults
  void resetToDefaults() {
    _clearAll();
    _initializeDefaults();
    _markChanged(changeAll);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT MANAGEMENT (delegates to EventSystemProvider - P1.8)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all registered events (delegates to EventSystemProvider)
  List<MiddlewareEvent> get events => _eventSystemProvider.events;

  /// Get event by ID (delegates to EventSystemProvider)
  MiddlewareEvent? getEvent(String id) => _eventSystemProvider.getEvent(id);

  /// Get event by name (delegates to EventSystemProvider)
  MiddlewareEvent? getEventByName(String name) => _eventSystemProvider.getEventByName(name);

  /// Register a new event (delegates to EventSystemProvider)
  void registerEvent(MiddlewareEvent event) {
    _eventSystemProvider.registerEvent(event);
  }

  /// Update an existing event (delegates to EventSystemProvider)
  /// Also syncs back to composite event for bidirectional consistency
  void updateEvent(MiddlewareEvent event) {
    _eventSystemProvider.updateEvent(event);
    // Bidirectional sync: MiddlewareEvent → SlotCompositeEvent
    _compositeEventSystemProvider.syncMiddlewareToComposite(event.id);
  }

  /// Delete an event (delegates to EventSystemProvider)
  void deleteEvent(String eventId) {
    _eventSystemProvider.deleteEvent(eventId);
  }

  /// Add action to an event (delegates to EventSystemProvider)
  void addActionToEvent(String eventId, MiddlewareAction action) {
    _eventSystemProvider.addActionToEvent(eventId, action);
    // Bidirectional sync: MiddlewareEvent → SlotCompositeEvent
    _compositeEventSystemProvider.syncMiddlewareToComposite(eventId);
  }

  /// Update action in an event (delegates to EventSystemProvider)
  /// Also syncs back to composite event for bidirectional consistency
  void updateActionInEvent(String eventId, MiddlewareAction action) {
    _eventSystemProvider.updateActionInEvent(eventId, action);
    // Bidirectional sync: MiddlewareEvent → SlotCompositeEvent
    _compositeEventSystemProvider.syncMiddlewareToComposite(eventId);
  }

  /// Remove action from an event (delegates to EventSystemProvider)
  void removeActionFromEvent(String eventId, String actionId) {
    _eventSystemProvider.removeActionFromEvent(eventId, actionId);
  }

  /// Reorder actions in an event (delegates to EventSystemProvider)
  void reorderActionsInEvent(String eventId, int oldIndex, int newIndex) {
    _eventSystemProvider.reorderActionsInEvent(eventId, oldIndex, newIndex);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT PLAYBACK - Post/Stop Events
  // ═══════════════════════════════════════════════════════════════════════════

  /// Currently playing event instances: playingId -> eventId
  final Map<int, String> _playingInstances = {};

  /// Get active playing instances
  Map<int, String> get playingInstances => Map.unmodifiable(_playingInstances);

  /// Post (trigger) an event
  ///
  /// [eventId] - The event identifier
  /// [gameObjectId] - Optional game object for scoped audio
  /// [context] - Optional context data for RTPC/switch evaluation
  /// [source] - Playback section source (defaults to middleware, use slotLab for SlotLab calls)
  ///
  /// Returns playing ID (0 if failed)
  int postEvent(String eventId, {
    int gameObjectId = 0,
    Map<String, dynamic>? context,
    PlaybackSection source = PlaybackSection.middleware,
  }) {
    final event = _eventSystemProvider.getEvent(eventId);
    if (event == null) {
      debugPrint('[Middleware] Event not found: $eventId');
      return 0;
    }

    final numericId = _eventSystemProvider.getNumericIdForEvent(event.name);
    if (numericId == null) {
      // Auto-register if not yet registered (shouldn't happen, but handle gracefully)
      _eventSystemProvider.registerEvent(event);
      return postEvent(eventId, gameObjectId: gameObjectId, context: context, source: source);
    }

    // Acquire the specified section before playback
    final controller = UnifiedPlaybackController.instance;
    if (!controller.acquireSection(source)) {
      debugPrint('[Middleware] Failed to acquire playback section: ${source.name}');
      return 0;
    }

    // Ensure audio stream is running WITHOUT starting transport
    // Middleware uses one-shot voices (playFileToBus), not timeline clips
    controller.ensureStreamRunning();

    // Apply context to RTPCs if provided
    if (context != null) {
      _applyContextToRtpcs(context);
    }

    final playingId = _ffi.middlewarePostEvent(numericId, gameObjectId: gameObjectId);

    if (playingId > 0) {
      _playingInstances[playingId] = eventId;
      _markChanged(changeCompositeEvents);
    }

    return playingId;
  }

  /// Apply context data to relevant RTPCs
  void _applyContextToRtpcs(Map<String, dynamic> context) {
    // Win multiplier from ratio
    if (context.containsKey('win_amount') && context.containsKey('bet_amount')) {
      final winAmount = (context['win_amount'] as num).toDouble();
      final betAmount = (context['bet_amount'] as num).toDouble();
      if (betAmount > 0) {
        final ratio = winAmount / betAmount;
        // Find win multiplier RTPC (ID 100 by convention)
        final rtpc = _rtpcSystemProvider.getRtpc(100);
        if (rtpc != null) {
          setRtpc(100, ratio.clamp(rtpc.min, rtpc.max));
        }
      }
    }

    // Cascade depth
    if (context.containsKey('cascade_depth')) {
      final depth = (context['cascade_depth'] as num).toDouble();
      final rtpc = _rtpcSystemProvider.getRtpc(104); // Cascade depth RTPC
      if (rtpc != null) {
        setRtpc(104, depth.clamp(rtpc.min, rtpc.max));
      }
    }

    // Multiplier
    if (context.containsKey('multiplier')) {
      final mult = (context['multiplier'] as num).toDouble();
      // Could be mapped to various RTPCs
    }
  }

  /// Post event by name
  int postEventByName(String eventName, {int gameObjectId = 0}) {
    final event = getEventByName(eventName);
    if (event == null) return 0;
    return postEvent(event.id, gameObjectId: gameObjectId);
  }

  /// Play a composite event by ID (triggers all layers with their audio files)
  ///
  /// This directly plays the audio layers in a composite event, bypassing
  /// the middleware event system. Used for stage-triggered user-defined events.
  ///
  /// [compositeEventId] - The composite event ID
  /// [source] - Playback section source (slotLab or middleware)
  ///
  /// Returns number of voices started
  int playCompositeEvent(String compositeEventId, {PlaybackSection source = PlaybackSection.slotLab}) {
    final event = _compositeEventSystemProvider.getCompositeEvent(compositeEventId);
    if (event == null) {
      debugPrint('[Middleware] playCompositeEvent: Event not found: $compositeEventId');
      return 0;
    }

    if (event.layers.isEmpty) {
      debugPrint('[Middleware] playCompositeEvent: Event "${event.name}" has no layers');
      return 0;
    }

    // Acquire the specified section before playback
    final controller = UnifiedPlaybackController.instance;
    if (!controller.acquireSection(source)) {
      debugPrint('[Middleware] playCompositeEvent: Failed to acquire playback section: ${source.name}');
      return 0;
    }

    // Ensure audio stream is running
    controller.ensureStreamRunning();

    // Play all layers via AudioPlaybackService
    final playbackService = AudioPlaybackService.instance;
    int voicesStarted = 0;

    for (final layer in event.layers) {
      if (layer.muted) continue;

      // Convert PlaybackSection to PlaybackSource
      final playbackSource = switch (source) {
        PlaybackSection.daw => PlaybackSource.daw,
        PlaybackSection.slotLab => PlaybackSource.slotlab,
        PlaybackSection.middleware => PlaybackSource.middleware,
        PlaybackSection.browser => PlaybackSource.browser,
      };

      final voiceId = playbackService.playFileToBus(
        layer.audioPath,
        volume: layer.volume * event.masterVolume,
        pan: layer.pan,
        busId: layer.busId ?? 0,
        source: playbackSource,
        eventId: compositeEventId,
        layerId: layer.id,
      );

      if (voiceId >= 0) {
        voicesStarted++;
      }
    }

    debugPrint('[Middleware] playCompositeEvent: "${event.name}" started $voicesStarted/${event.layers.length} voices');
    return voicesStarted;
  }

  /// Stop a playing instance
  void stopPlayingId(int playingId, {int fadeMs = 100}) {
    _ffi.middlewareStopPlayingId(playingId, fadeMs: fadeMs);
    _playingInstances.remove(playingId);

    // Release Middleware section when no more playing instances
    if (_playingInstances.isEmpty) {
      UnifiedPlaybackController.instance.releaseSection(PlaybackSection.middleware);
    }

    _markChanged(changeCompositeEvents);
  }

  /// Stop all instances of an event
  void stopEvent(String eventId, {int fadeMs = 100, int gameObjectId = 0}) {
    final event = _eventSystemProvider.getEvent(eventId);
    if (event == null) return;

    final numericId = _eventSystemProvider.getNumericIdForEvent(event.name);
    if (numericId == null) return;

    _ffi.middlewareStopEvent(numericId, gameObjectId: gameObjectId, fadeMs: fadeMs);

    // Remove from playing instances
    _playingInstances.removeWhere((_, v) => v == eventId);

    // Release Middleware section when no more playing instances
    if (_playingInstances.isEmpty) {
      UnifiedPlaybackController.instance.releaseSection(PlaybackSection.middleware);
    }

    _markChanged(changeCompositeEvents);
  }

  /// Stop all playing voices for a composite event
  void stopCompositeEvent(String eventId, {int fadeMs = 100}) {
    final event = compositeEvents.where((e) => e.id == eventId).firstOrNull;
    if (event == null) {
      debugPrint('[Middleware] stopCompositeEvent: Event not found: $eventId');
      return;
    }

    // Stop all playing instances associated with this event
    final toRemove = <int>[];
    for (final entry in _playingInstances.entries) {
      if (entry.value == eventId) {
        _ffi.middlewareStopPlayingId(entry.key, fadeMs: fadeMs);
        toRemove.add(entry.key);
      }
    }
    for (final id in toRemove) {
      _playingInstances.remove(id);
    }

    // Also stop via AudioPlaybackService if using bus routing
    AudioPlaybackService.instance.stopEvent(eventId);

    debugPrint('[Middleware] stopCompositeEvent: "${event.name}" stopped ${toRemove.length} instances');

    // Release section when no more playing instances
    if (_playingInstances.isEmpty) {
      UnifiedPlaybackController.instance.releaseSection(PlaybackSection.middleware);
    }

    _markChanged(changeCompositeEvents);
  }

  /// Stop event by name (used for MiddlewareEvent preview)
  void stopEventByName(String eventName, {int fadeMs = 100, int gameObjectId = 0}) {
    final event = _eventSystemProvider.events.where((e) => e.name == eventName).firstOrNull;
    if (event == null) {
      debugPrint('[Middleware] stopEventByName: Event not found: $eventName');
      return;
    }

    stopEvent(event.id, fadeMs: fadeMs, gameObjectId: gameObjectId);
    debugPrint('[Middleware] stopEventByName: "$eventName" stopped');
  }

  /// Stop all playing events
  void stopAllEvents({int fadeMs = 100}) {
    _ffi.middlewareStopAll(fadeMs: fadeMs);
    _playingInstances.clear();

    // Release Middleware section when all events stopped
    UnifiedPlaybackController.instance.releaseSection(PlaybackSection.middleware);

    _markChanged(changeCompositeEvents);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIVE PREVIEW / TESTING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Test event with specific scope
  ///
  /// Plays the event once for preview in the editor.
  int testEvent(String eventId, {int gameObjectId = 0}) {
    return postEvent(eventId, gameObjectId: gameObjectId);
  }

  /// Test single action (creates temporary event)
  int testAction(MiddlewareAction action, {int gameObjectId = 0}) {
    // Create temporary event with single action
    final tempEventId = '_test_${DateTime.now().millisecondsSinceEpoch}';
    final tempEvent = MiddlewareEvent(
      id: tempEventId,
      name: tempEventId,
      category: 'Test',
      actions: [action],
    );

    // Register temporarily via EventSystemProvider
    _eventSystemProvider.registerEvent(tempEvent);

    // Post event
    final numericId = _eventSystemProvider.getNumericIdForEvent(tempEventId);
    if (numericId == null) return 0;

    final playingId = _ffi.middlewarePostEvent(numericId, gameObjectId: gameObjectId);

    // Note: Temporary event stays registered (Rust has no unregister)
    // This is acceptable for testing purposes

    return playingId;
  }

  /// Get active instance count from engine
  int getActiveInstanceCount() {
    return _ffi.middlewareGetActiveInstanceCount();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IMPORT/EXPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export all events to JSON
  Map<String, dynamic> exportEventsToJson() {
    return {
      'version': '1.0',
      'exported_at': DateTime.now().toIso8601String(),
      'events': _eventSystemProvider.toJson(),
    };
  }

  /// Import events from JSON
  void importEventsFromJson(Map<String, dynamic> json) {
    final eventsList = json['events'] as List<dynamic>?;
    if (eventsList == null) return;

    for (final eventJson in eventsList) {
      final event = MiddlewareEvent.fromJson(eventJson as Map<String, dynamic>);
      registerEvent(event);
    }
  }

  /// Sync all events to engine (useful after load)
  /// Note: Events are auto-synced on registration, this re-syncs if needed
  void syncAllEventsToEngine() {
    for (final event in _eventSystemProvider.events) {
      // Re-register event (will sync to engine)
      _eventSystemProvider.updateEvent(event);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SLOT ELEMENT MAPPING - Bidirectional Sync
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all slot element mappings
  List<SlotElementEventMapping> get slotElementMappings =>
      [..._slotElementMappings.values, ..._customElementMappings.values];

  /// Get mapping for a specific element
  SlotElementEventMapping? getSlotElementMapping(SlotElementType element, [String? customName]) {
    if (element == SlotElementType.custom && customName != null) {
      return _customElementMappings[customName];
    }
    return _slotElementMappings[element];
  }

  /// Initialize default slot element mappings
  /// This creates all standard mappings and their corresponding events
  void initializeSlotElementMappings() {
    // Clear existing
    _slotElementMappings.clear();
    _customElementMappings.clear();

    // Create default mappings
    final defaults = SlotElementMappingFactory.createDefaultMappings();
    for (final mapping in defaults) {
      _slotElementMappings[mapping.element] = mapping;

      // Ensure corresponding event exists
      _ensureEventForMapping(mapping);
    }

    _markChanged(changeSlotElements);
  }

  /// Ensure event exists for a mapping, create if not
  void _ensureEventForMapping(SlotElementEventMapping mapping) {
    if (_eventSystemProvider.hasEvent(mapping.eventId)) return;

    // Create event from slot audio events factory
    final allSlotEvents = SlotAudioEventFactory.createAllEvents();
    final matchingEvent = allSlotEvents.where((e) => e.id == mapping.eventId).firstOrNull;

    if (matchingEvent != null) {
      registerEvent(matchingEvent);
    } else {
      // Create placeholder event for custom mappings
      final newEvent = MiddlewareEvent(
        id: mapping.eventId,
        name: mapping.displayName.replaceAll(' ', '_'),
        category: 'Slot_Custom',
        actions: [],
      );
      registerEvent(newEvent);
    }
  }

  /// Add audio layer to a slot element
  /// This is called when user drags audio onto a slot element in Slot Fullscreen mode
  void addAudioToSlotElement({
    required SlotElementType element,
    String? customName,
    required String assetPath,
    required String assetName,
    String bus = 'SFX',
    double volume = 1.0,
  }) {
    // Get or create mapping
    SlotElementEventMapping? mapping;
    if (element == SlotElementType.custom && customName != null) {
      mapping = _customElementMappings[customName];
      if (mapping == null) {
        // Create new custom mapping
        final eventId = 'slot_custom_${customName.toLowerCase().replaceAll(' ', '_')}';
        mapping = SlotElementEventMapping(
          element: element,
          customName: customName,
          eventId: eventId,
          audioLayers: [],
        );
        _customElementMappings[customName] = mapping;
        _ensureEventForMapping(mapping);
      }
    } else {
      mapping = _slotElementMappings[element];
      if (mapping == null) {
        // Create default mapping
        final defaultEventId = SlotElementMappingFactory.defaultMappings[element];
        if (defaultEventId == null) return;
        mapping = SlotElementEventMapping(
          element: element,
          eventId: defaultEventId,
          audioLayers: [],
        );
        _slotElementMappings[element] = mapping;
        _ensureEventForMapping(mapping);
      }
    }

    // Create audio layer
    final layerId = 'layer_${DateTime.now().millisecondsSinceEpoch}';
    final layer = SlotAudioLayer(
      id: layerId,
      assetPath: assetPath,
      assetName: assetName,
      bus: bus,
      volume: volume,
    );

    // Add layer to mapping
    final updatedMapping = mapping.addAudioLayer(layer);

    // Update mapping in appropriate collection
    if (element == SlotElementType.custom && customName != null) {
      _customElementMappings[customName] = updatedMapping;
    } else {
      _slotElementMappings[element] = updatedMapping;
    }

    // Sync to event - add Play action for this audio
    _syncSlotLayerToEvent(updatedMapping, layer);

    _markChanged(changeSlotElements);
  }

  /// Sync a slot layer to its corresponding middleware event
  void _syncSlotLayerToEvent(SlotElementEventMapping mapping, SlotAudioLayer layer) {
    final event = _eventSystemProvider.getEvent(mapping.eventId);
    if (event == null) return;

    // Create action for this layer
    final actionId = 'action_${layer.id}';
    final action = MiddlewareAction(
      id: actionId,
      type: ActionType.play,
      assetId: layer.assetName,
      bus: layer.bus,
      gain: layer.volume,
    );

    // Add action to event
    addActionToEvent(mapping.eventId, action);
  }

  /// Remove audio layer from slot element
  void removeAudioFromSlotElement({
    required SlotElementType element,
    String? customName,
    required String layerId,
  }) {
    SlotElementEventMapping? mapping;
    if (element == SlotElementType.custom && customName != null) {
      mapping = _customElementMappings[customName];
    } else {
      mapping = _slotElementMappings[element];
    }

    if (mapping == null) return;

    // Find and remove the layer
    final updatedLayers = mapping.audioLayers.where((l) => l.id != layerId).toList();
    final updatedMapping = mapping.copyWith(audioLayers: updatedLayers);

    // Update mapping
    if (element == SlotElementType.custom && customName != null) {
      _customElementMappings[customName] = updatedMapping;
    } else {
      _slotElementMappings[element] = updatedMapping;
    }

    // Remove corresponding action from event
    final actionId = 'action_$layerId';
    removeActionFromEvent(mapping.eventId, actionId);

    _markChanged(changeSlotElements);
  }

  /// Update audio layer properties
  void updateSlotAudioLayer({
    required SlotElementType element,
    String? customName,
    required SlotAudioLayer layer,
  }) {
    SlotElementEventMapping? mapping;
    if (element == SlotElementType.custom && customName != null) {
      mapping = _customElementMappings[customName];
    } else {
      mapping = _slotElementMappings[element];
    }

    if (mapping == null) return;

    // Update the layer
    final updatedLayers = mapping.audioLayers.map((l) {
      return l.id == layer.id ? layer : l;
    }).toList();

    final updatedMapping = mapping.copyWith(audioLayers: updatedLayers);

    // Update mapping
    if (element == SlotElementType.custom && customName != null) {
      _customElementMappings[customName] = updatedMapping;
    } else {
      _slotElementMappings[element] = updatedMapping;
    }

    // Update corresponding action in event
    final event = _eventSystemProvider.getEvent(mapping.eventId);
    if (event != null) {
      final actionId = 'action_${layer.id}';
      final existingAction = event.actions.where((a) => a.id == actionId).firstOrNull;
      if (existingAction != null) {
        final updatedAction = existingAction.copyWith(
          assetId: layer.assetName,
          bus: layer.bus,
          gain: layer.volume,
        );
        updateActionInEvent(mapping.eventId, updatedAction);
      }
    }

    _markChanged(changeSlotElements);
  }

  /// Create custom slot element mapping
  void createCustomSlotElement(String customName, {String? eventId}) {
    final resolvedEventId = eventId ?? 'slot_custom_${customName.toLowerCase().replaceAll(' ', '_')}';
    final mapping = SlotElementEventMapping(
      element: SlotElementType.custom,
      customName: customName,
      eventId: resolvedEventId,
      audioLayers: [],
    );

    _customElementMappings[customName] = mapping;
    _ensureEventForMapping(mapping);

    _markChanged(changeSlotElements);
  }

  /// Remove custom slot element mapping
  void removeCustomSlotElement(String customName) {
    final mapping = _customElementMappings.remove(customName);
    if (mapping != null) {
      // Optionally delete the event too
      deleteEvent(mapping.eventId);
    }
    _markChanged(changeSlotElements);
  }

  /// Sync from Middleware Event to Slot Element
  /// Called when event is modified in Event Editor - updates slot element mapping
  void syncEventToSlotElement(String eventId) {
    final event = _eventSystemProvider.getEvent(eventId);
    if (event == null) return;

    // Find mapping that uses this event
    SlotElementEventMapping? mapping;
    SlotElementType? elementType;
    String? customName;

    for (final entry in _slotElementMappings.entries) {
      if (entry.value.eventId == eventId) {
        mapping = entry.value;
        elementType = entry.key;
        break;
      }
    }

    if (mapping == null) {
      for (final entry in _customElementMappings.entries) {
        if (entry.value.eventId == eventId) {
          mapping = entry.value;
          elementType = SlotElementType.custom;
          customName = entry.key;
          break;
        }
      }
    }

    if (mapping == null || elementType == null) return;

    // Rebuild audio layers from event actions
    final newLayers = <SlotAudioLayer>[];
    for (final action in event.actions) {
      if (action.type == ActionType.play && action.assetId.isNotEmpty) {
        final layerId = action.id.startsWith('action_')
            ? action.id.substring(7)
            : 'layer_${action.id}';

        newLayers.add(SlotAudioLayer(
          id: layerId,
          assetPath: '', // Would need asset registry to resolve
          assetName: action.assetId,
          bus: action.bus,
          volume: action.gain,
          muted: false,
          solo: false,
          pan: 0.0,
        ));
      }
    }

    final updatedMapping = mapping.copyWith(audioLayers: newLayers);

    if (elementType == SlotElementType.custom && customName != null) {
      _customElementMappings[customName] = updatedMapping;
    } else {
      _slotElementMappings[elementType] = updatedMapping;
    }

    _markChanged(changeSlotElements);
  }

  /// Get event for a slot element
  MiddlewareEvent? getEventForSlotElement(SlotElementType element, [String? customName]) {
    final mapping = getSlotElementMapping(element, customName);
    if (mapping == null) return null;
    return _eventSystemProvider.getEvent(mapping.eventId);
  }

  /// Load slot audio profile (creates all events and mappings from factory)
  void loadSlotAudioProfile() {
    final profile = SlotAudioProfile.defaultProfile();

    // Register all events
    for (final event in profile.events) {
      registerEvent(event);
    }

    // Register RTPCs
    for (final rtpc in profile.rtpcs) {
      registerRtpc(rtpc);
    }

    // Register state groups
    for (final group in profile.stateGroups) {
      registerStateGroup(group);
    }

    // Add ducking rules
    for (final rule in profile.duckingRules) {
      _duckingSystemProvider.registerRule(rule);
    }

    // Add music segments (delegates to MusicSystemProvider)
    for (final segment in profile.musicSegments) {
      _musicSystemProvider.importSegment(segment);
    }

    // Add stingers (delegates to MusicSystemProvider)
    for (final stinger in profile.stingers) {
      _musicSystemProvider.importStinger(stinger);
    }

    // Set up element mappings
    for (final mapping in profile.elementMappings) {
      if (mapping.element == SlotElementType.custom && mapping.customName != null) {
        _customElementMappings[mapping.customName!] = mapping;
      } else {
        _slotElementMappings[mapping.element] = mapping;
      }
    }

    _markChanged(changeSlotElements);
  }

  /// Export slot mappings to JSON
  Map<String, dynamic> exportSlotMappingsToJson() {
    return {
      'version': '1.0',
      'exported_at': DateTime.now().toIso8601String(),
      'standard_mappings': _slotElementMappings.entries.map((e) => {
        'element': e.key.name,
        'eventId': e.value.eventId,
        'audioLayers': e.value.audioLayers.map((l) => l.toJson()).toList(),
      }).toList(),
      'custom_mappings': _customElementMappings.entries.map((e) => {
        'customName': e.key,
        'eventId': e.value.eventId,
        'audioLayers': e.value.audioLayers.map((l) => l.toJson()).toList(),
      }).toList(),
    };
  }

  /// Import slot mappings from JSON
  void importSlotMappingsFromJson(Map<String, dynamic> json) {
    // Standard mappings
    final standardList = json['standard_mappings'] as List<dynamic>?;
    if (standardList != null) {
      for (final m in standardList) {
        final elementName = m['element'] as String;
        final element = SlotElementType.values.where((e) => e.name == elementName).firstOrNull;
        if (element == null) continue;

        final audioLayers = (m['audioLayers'] as List<dynamic>?)
            ?.map((l) => SlotAudioLayer.fromJson(l as Map<String, dynamic>))
            .toList() ?? [];

        final mapping = SlotElementEventMapping(
          element: element,
          eventId: m['eventId'] as String,
          audioLayers: audioLayers,
        );

        _slotElementMappings[element] = mapping;
      }
    }

    // Custom mappings
    final customList = json['custom_mappings'] as List<dynamic>?;
    if (customList != null) {
      for (final m in customList) {
        final customName = m['customName'] as String;
        final audioLayers = (m['audioLayers'] as List<dynamic>?)
            ?.map((l) => SlotAudioLayer.fromJson(l as Map<String, dynamic>))
            .toList() ?? [];

        final mapping = SlotElementEventMapping(
          element: SlotElementType.custom,
          customName: customName,
          eventId: m['eventId'] as String,
          audioLayers: audioLayers,
        );

        _customElementMappings[customName] = mapping;
      }
    }

    _markChanged(changeSlotElements);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS - VOICE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Request a voice from the pool
  int? requestVoice({
    required int soundId,
    required int busId,
    int priority = 50,
    double volume = 1.0,
    double pitch = 1.0,
    double pan = 0.0,
    double? spatialDistance,
  }) {
    final voiceId = _voicePoolProvider.requestVoice(
      soundId: soundId,
      busId: busId,
      priority: priority,
      volume: volume,
      pitch: pitch,
      pan: pan,
      spatialDistance: spatialDistance,
    );

    if (voiceId != null) {
      _eventProfilerProvider.record(
        type: ProfilerEventType.voiceStart,
        description: 'Voice $voiceId started (sound: $soundId)',
        soundId: soundId,
        busId: busId,
        voiceId: voiceId,
      );
    }

    return voiceId;
  }

  /// Release a voice back to the pool
  void releaseVoice(int voiceId) {
    _voicePoolProvider.releaseVoice(voiceId);
    _eventProfilerProvider.record(
      type: ProfilerEventType.voiceStop,
      description: 'Voice $voiceId released',
      voiceId: voiceId,
    );
  }

  /// Get voice pool statistics
  VoicePoolStats getVoicePoolStats() => _voicePoolProvider.getStats();

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS - BUS HIERARCHY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get a bus by ID
  AudioBus? getBus(int busId) => _busHierarchyProvider.getBus(busId);

  /// Get all buses
  List<AudioBus> getAllBuses() => _busHierarchyProvider.allBuses;

  /// Get effective volume for a bus (considering parent chain)
  double getEffectiveBusVolume(int busId) => _busHierarchyProvider.getEffectiveVolume(busId);

  /// Set bus volume (delegates to provider)
  void setBusVolume(int busId, double volume) {
    _busHierarchyProvider.setBusVolume(busId, volume);
  }

  /// Set bus mute (delegates to provider)
  void setBusMute(int busId, bool mute) {
    final bus = _busHierarchyProvider.getBus(busId);
    if (bus != null && bus.mute != mute) {
      _busHierarchyProvider.toggleBusMute(busId);
    }
  }

  /// Set bus solo (delegates to provider)
  void setBusSolo(int busId, bool solo) {
    final bus = _busHierarchyProvider.getBus(busId);
    if (bus != null && bus.solo != solo) {
      _busHierarchyProvider.toggleBusSolo(busId);
    }
  }

  /// Add effect to bus pre-insert chain (delegates to provider)
  void addBusPreInsert(int busId, EffectSlot effect) {
    _busHierarchyProvider.addBusPreInsert(busId, effect);
  }

  /// Add effect to bus post-insert chain (delegates to provider)
  void addBusPostInsert(int busId, EffectSlot effect) {
    _busHierarchyProvider.addBusPostInsert(busId, effect);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS - AUX SEND ROUTING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all aux buses
  List<AuxBus> getAllAuxBuses() => _auxSendProvider.allAuxBuses;

  /// Get all aux sends
  List<AuxSend> getAllAuxSends() => _auxSendProvider.allSends;

  /// Get an aux bus by ID
  AuxBus? getAuxBus(int auxBusId) => _auxSendProvider.getAuxBus(auxBusId);

  /// Get sends from a specific source bus
  List<AuxSend> getSendsFromBus(int sourceBusId) {
    return _auxSendProvider.getSendsFromBus(sourceBusId);
  }

  /// Get sends to a specific aux bus
  List<AuxSend> getSendsToAux(int auxBusId) {
    return _auxSendProvider.getSendsToAux(auxBusId);
  }

  /// Create a new aux send (delegates to provider)
  AuxSend createAuxSend({
    required int sourceBusId,
    required int auxBusId,
    double sendLevel = 0.0,
    SendPosition position = SendPosition.postFader,
  }) {
    final send = _auxSendProvider.createSend(
      sourceBusId: sourceBusId,
      auxBusId: auxBusId,
      sendLevel: sendLevel,
      position: position,
    );
    _eventProfilerProvider.record(
      type: ProfilerEventType.eventTrigger,
      description: 'Aux send created: ${send.sendId} (bus $sourceBusId → aux $auxBusId)',
    );
    return send;
  }

  /// Set aux send level (delegates to provider)
  void setAuxSendLevel(int sendId, double level) {
    _auxSendProvider.setSendLevel(sendId, level);
  }

  /// Toggle aux send enabled (delegates to provider)
  void toggleAuxSendEnabled(int sendId) {
    _auxSendProvider.toggleSendEnabled(sendId);
  }

  /// Set aux send position (pre/post fader) (delegates to provider)
  void setAuxSendPosition(int sendId, SendPosition position) {
    _auxSendProvider.setSendPosition(sendId, position);
  }

  /// Remove an aux send (delegates to provider)
  void removeAuxSend(int sendId) {
    _auxSendProvider.removeSend(sendId);
  }

  /// Add a new aux bus (delegates to provider)
  AuxBus addAuxBus({
    required String name,
    required EffectType effectType,
  }) {
    final auxBus = _auxSendProvider.addAuxBus(
      name: name,
      effectType: effectType,
    );
    _eventProfilerProvider.record(
      type: ProfilerEventType.eventTrigger,
      description: 'Aux bus created: ${auxBus.auxBusId} ($name)',
    );
    return auxBus;
  }

  /// Set aux bus return level (delegates to provider)
  void setAuxReturnLevel(int auxBusId, double level) {
    _auxSendProvider.setAuxReturnLevel(auxBusId, level);
  }

  /// Toggle aux bus mute (delegates to provider)
  void toggleAuxMute(int auxBusId) {
    _auxSendProvider.toggleAuxMute(auxBusId);
  }

  /// Toggle aux bus solo (delegates to provider)
  void toggleAuxSolo(int auxBusId) {
    _auxSendProvider.toggleAuxSolo(auxBusId);
  }

  /// Set aux effect parameter (delegates to provider)
  void setAuxEffectParam(int auxBusId, String param, double value) {
    _auxSendProvider.setAuxEffectParam(auxBusId, param, value);
  }

  /// Calculate total send contribution to an aux bus
  double calculateAuxInput(int auxBusId, Map<int, double> busLevels) {
    return _auxSendProvider.calculateAuxInput(auxBusId, busLevels);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS - MEMORY MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a soundbank (delegated to MemoryManagerProvider)
  void registerSoundbank(SoundBank bank) {
    _memoryManagerProvider.registerSoundbank(bank);
  }

  /// Load a soundbank (delegated to MemoryManagerProvider)
  bool loadSoundbank(String bankId) {
    final success = _memoryManagerProvider.loadSoundbank(bankId);
    if (success) {
      _eventProfilerProvider.record(
        type: ProfilerEventType.bankLoad,
        description: 'Bank loaded: $bankId',
      );
    }
    return success;
  }

  /// Unload a soundbank (delegated to MemoryManagerProvider)
  bool unloadSoundbank(String bankId) {
    final success = _memoryManagerProvider.unloadSoundbank(bankId);
    if (success) {
      _eventProfilerProvider.record(
        type: ProfilerEventType.bankUnload,
        description: 'Bank unloaded: $bankId',
      );
    }
    return success;
  }

  /// Get memory statistics (delegated to MemoryManagerProvider)
  MemoryStats getMemoryStats() => _memoryManagerProvider.getStats();

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS - SPATIAL AUDIO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update reel spatial config
  void updateReelSpatialConfig(ReelSpatialConfig config) {
    _reelSpatialConfig = config;
    _markChanged(changeBusHierarchy);
  }

  /// Get audio position for a reel
  AudioPosition getReelPosition(int reelIndex, {int rowIndex = 1}) {
    return _reelSpatialConfig.getReelPosition(reelIndex, rowIndex: rowIndex);
  }

  /// Calculate attenuation for distance
  double calculateSpatialAttenuation(double distance) {
    return _reelSpatialConfig.calculateAttenuation(distance);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS - CASCADE AUDIO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update cascade config
  void updateCascadeConfig(CascadeAudioConfig config) {
    _cascadeConfig = config;
    _markChanged(changeBusHierarchy);
  }

  /// Get audio parameters for cascade step
  ({double pitch, double volume, double width, double reverbWet, double tension})
  getCascadeAudioParams(int cascadeStep) {
    return (
      pitch: _cascadeConfig.getPitchMultiplier(cascadeStep),
      volume: _cascadeConfig.getVolume(cascadeStep),
      width: _cascadeConfig.getWidth(cascadeStep),
      reverbWet: _cascadeConfig.getReverbWet(cascadeStep),
      tension: _cascadeConfig.getTensionValue(cascadeStep),
    );
  }

  /// Get active cascade layers for step
  List<CascadeLayer> getActiveCascadeLayers(int cascadeStep) {
    return _cascadeConfig.getActiveLayers(cascadeStep);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS - HDR AUDIO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set HDR profile
  void setHdrProfile(HdrProfile profile) {
    _hdrConfig = HdrAudioConfig.fromProfile(profile);
    _markChanged(changeBusHierarchy);
  }

  /// Update HDR config
  void updateHdrConfig(HdrAudioConfig config) {
    _hdrConfig = config;
    _markChanged(changeBusHierarchy);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS - STREAMING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update streaming config
  void updateStreamingConfig(StreamingConfig config) {
    _streamingConfig = config;
    _markChanged(changeBusHierarchy);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS - PROFILER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Record a profiler event (delegated to EventProfilerProvider)
  void recordProfilerEvent({
    required ProfilerEventType type,
    required String description,
    int? soundId,
    int? busId,
    int? voiceId,
    double? value,
    int latencyUs = 0,
  }) {
    _eventProfilerProvider.record(
      type: type,
      description: description,
      soundId: soundId,
      busId: busId,
      voiceId: voiceId,
      value: value,
      latencyUs: latencyUs,
    );
  }

  /// Get profiler statistics (delegated to EventProfilerProvider)
  ProfilerStats getProfilerStats() => _eventProfilerProvider.getStats();

  /// Get recent profiler events (delegated to EventProfilerProvider)
  List<ProfilerEvent> getRecentProfilerEvents({int count = 100}) {
    return _eventProfilerProvider.getRecentEvents(count: count);
  }

  /// Clear profiler (delegated to EventProfilerProvider)
  void clearProfiler() {
    _eventProfilerProvider.clear();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO SPATIAL ENGINE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a UI element anchor for spatial tracking
  ///
  /// Call this from widget build() or layout callbacks to track element positions.
  /// The engine will use these positions to automatically position sounds in the stereo field.
  void registerSpatialAnchor({
    required String id,
    required double xNorm,
    required double yNorm,
    double wNorm = 0.1,
    double hNorm = 0.1,
    bool visible = true,
  }) {
    _autoSpatialEngine.anchorRegistry.registerAnchor(
      id: id,
      xNorm: xNorm,
      yNorm: yNorm,
      wNorm: wNorm,
      hNorm: hNorm,
      visible: visible,
    );
  }

  /// Unregister a UI element anchor
  void unregisterSpatialAnchor(String id) {
    _autoSpatialEngine.anchorRegistry.unregisterAnchor(id);
  }

  /// Emit a spatial audio event
  ///
  /// The AutoSpatialEngine will automatically determine the spatial position
  /// based on registered anchors, motion, and intent rules.
  void emitSpatialEvent(SpatialEvent event) {
    _autoSpatialEngine.onEvent(event);

    // Record in profiler
    recordProfilerEvent(
      type: ProfilerEventType.eventTrigger,
      description: 'Spatial: ${event.intent}',
      value: event.importance,
    );
  }

  /// Stop a spatial event
  void stopSpatialEvent(String eventId) {
    _autoSpatialEngine.stopEvent(eventId);
  }

  /// Update all spatial events and get outputs
  ///
  /// Call this every frame (or at audio rate) to get updated spatial parameters.
  /// Returns a map of eventId -> SpatialOutput with pan, width, gains, etc.
  Map<String, SpatialOutput> updateSpatialEvents() {
    return _autoSpatialEngine.update();
  }

  /// Get spatial output for a specific event
  SpatialOutput? getSpatialOutput(String eventId) {
    return _autoSpatialEngine.getOutput(eventId);
  }

  /// Get AutoSpatial engine statistics
  AutoSpatialStats getSpatialStats() {
    return _autoSpatialEngine.getStats();
  }

  /// Configure the AutoSpatial engine
  void configureSpatialEngine(AutoSpatialConfig config) {
    _autoSpatialEngine.config = config;
    _markChanged(changeBusHierarchy);
  }

  /// Clear all spatial tracking
  void clearSpatialTracking() {
    _autoSpatialEngine.clear();
  }

  /// Helper: Register standard slot anchors
  ///
  /// Call this to set up default anchor positions for a standard slot layout.
  /// The positions are normalized (0-1) with (0,0) at top-left.
  void registerStandardSlotAnchors({
    int reelCount = 5,
    double reelSpacing = 0.15,
  }) {
    // Calculate reel positions (centered)
    final reelStartX = 0.5 - (reelCount - 1) * reelSpacing / 2;

    for (int i = 0; i < reelCount; i++) {
      registerSpatialAnchor(
        id: 'reel_${i + 1}',
        xNorm: reelStartX + i * reelSpacing,
        yNorm: 0.5, // Center vertically
        wNorm: 0.12,
        hNorm: 0.6,
      );
    }

    // Reels center
    registerSpatialAnchor(
      id: 'reels_center',
      xNorm: 0.5,
      yNorm: 0.5,
      wNorm: reelCount * reelSpacing,
      hNorm: 0.6,
    );

    // Balance/win display (top right)
    registerSpatialAnchor(
      id: 'balance_value',
      xNorm: 0.85,
      yNorm: 0.08,
      wNorm: 0.15,
      hNorm: 0.05,
    );

    // Win display (center top)
    registerSpatialAnchor(
      id: 'win_display',
      xNorm: 0.5,
      yNorm: 0.15,
      wNorm: 0.3,
      hNorm: 0.08,
    );

    // Spin button (center bottom)
    registerSpatialAnchor(
      id: 'spin_button',
      xNorm: 0.5,
      yNorm: 0.92,
      wNorm: 0.15,
      hNorm: 0.08,
    );

    // Bet controls (bottom left)
    registerSpatialAnchor(
      id: 'bet_controls',
      xNorm: 0.15,
      yNorm: 0.92,
      wNorm: 0.2,
      hNorm: 0.08,
    );
  }

  /// Helper: Create spatial event for reel stop
  SpatialEvent createReelStopEvent(int reelIndex) {
    return SpatialEvent(
      id: 'reel_stop_${reelIndex}_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Reel $reelIndex Stop',
      intent: 'REEL_STOP_$reelIndex',
      bus: SpatialBus.reels,
      timeMs: DateTime.now().millisecondsSinceEpoch,
      anchorId: 'reel_$reelIndex',
      importance: 0.7,
      lifetimeMs: 300,
    );
  }

  /// Helper: Create spatial event for coin fly animation
  SpatialEvent createCoinFlyEvent({
    required double progress01,
    String? startAnchor,
    String? endAnchor,
  }) {
    return SpatialEvent(
      id: 'coin_fly_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Coin Fly',
      intent: 'COIN_FLY_TO_BALANCE',
      bus: SpatialBus.sfx,
      timeMs: DateTime.now().millisecondsSinceEpoch,
      startAnchorId: startAnchor ?? 'reels_center',
      endAnchorId: endAnchor ?? 'balance_value',
      progress01: progress01,
      importance: 0.6,
      lifetimeMs: 1200,
    );
  }

  /// Helper: Create spatial event for big win
  SpatialEvent createBigWinEvent({
    required String tier, // 'BIG_WIN', 'MEGA_WIN', 'SUPER_WIN', 'EPIC_WIN'
  }) {
    final lifetimes = {
      'BIG_WIN': 3000,
      'MEGA_WIN': 4000,
      'SUPER_WIN': 5000,
      'EPIC_WIN': 6000,
    };

    return SpatialEvent(
      id: '${tier.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}',
      name: tier.replaceAll('_', ' '),
      intent: tier,
      bus: SpatialBus.sfx,
      timeMs: DateTime.now().millisecondsSinceEpoch,
      anchorId: 'reels_center',
      importance: 1.0,
      lifetimeMs: lifetimes[tier] ?? 3000,
    );
  }

  /// Helper: Create spatial event for UI click
  SpatialEvent createUIClickEvent({
    required String anchorId,
    required double xNorm,
    required double yNorm,
  }) {
    return SpatialEvent(
      id: 'ui_click_${DateTime.now().millisecondsSinceEpoch}',
      name: 'UI Click',
      intent: 'UI_CLICK',
      bus: SpatialBus.ui,
      timeMs: DateTime.now().millisecondsSinceEpoch,
      anchorId: anchorId,
      xNorm: xNorm,
      yNorm: yNorm,
      importance: 0.3,
      lifetimeMs: 150,
    );
  }

  /// Dispose AutoSpatial resources
  void disposeSpatialEngine() {
    _autoSpatialEngine.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED AUDIO POOL METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add audio file to shared pool (now delegates to AudioAssetManager)
  void addToSharedPool(SharedPoolAudioFile file) {
    final manager = AudioAssetManager.instance;
    // Avoid duplicates by path
    if (manager.hasAsset(file.path)) return;

    manager.addAssetFromPoolFile(
      id: file.id,
      path: file.path,
      name: file.name,
      duration: file.duration,
      sampleRate: file.sampleRate,
      channels: file.channels,
      format: file.format,
    );
    _markChanged(changeCompositeEvents);
  }

  /// Remove audio file from shared pool (now delegates to AudioAssetManager)
  void removeFromSharedPool(String fileId) {
    final manager = AudioAssetManager.instance;
    try {
      manager.removeById(fileId);
    } catch (_) {
      // Asset may not exist, ignore
    }
    _markChanged(changeCompositeEvents);
  }

  /// Get audio file from pool by path
  SharedPoolAudioFile? getPoolFileByPath(String path) {
    final asset = AudioAssetManager.instance.getByPath(path);
    if (asset == null) return null;

    return SharedPoolAudioFile(
      id: asset.id,
      path: asset.path,
      name: asset.name,
      duration: asset.duration,
      sampleRate: asset.sampleRate,
      channels: asset.channels,
      format: asset.format,
      waveform: asset.waveform,
      importedAt: asset.importedAt,
    );
  }

  /// Clear entire audio pool (now delegates to AudioAssetManager)
  void clearSharedPool() {
    AudioAssetManager.instance.clear();
    _markChanged(changeCompositeEvents);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SLOT MODE STATE METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set slot tracks (replaces all)
  void setSlotTracks(List<SlotAudioTrack> tracks) {
    _slotTracks.clear();
    _slotTracks.addAll(tracks);
    _markChanged(changeSlotElements);
  }

  /// Update a single slot track
  void updateSlotTrack(SlotAudioTrack track) {
    final index = _slotTracks.indexWhere((t) => t.id == track.id);
    if (index >= 0) {
      _slotTracks[index] = track;
      _markChanged(changeSlotElements);
    }
  }

  /// Add region to slot track
  void addSlotRegion(String trackId, SlotAudioRegion region) {
    final index = _slotTracks.indexWhere((t) => t.id == trackId);
    if (index >= 0) {
      final track = _slotTracks[index];
      _slotTracks[index] = track.copyWith(
        regions: [...track.regions, region],
      );
      _markChanged(changeSlotElements);
    }
  }

  /// Remove region from slot track
  void removeSlotRegion(String trackId, String regionId) {
    final index = _slotTracks.indexWhere((t) => t.id == trackId);
    if (index >= 0) {
      final track = _slotTracks[index];
      _slotTracks[index] = track.copyWith(
        regions: track.regions.where((r) => r.id != regionId).toList(),
      );
      _markChanged(changeSlotElements);
    }
  }

  /// Set slot stage markers
  void setSlotMarkers(List<SlotStageMarker> markers) {
    _slotMarkers.clear();
    _slotMarkers.addAll(markers);
    _markChanged(changeSlotElements);
  }

  /// Set slot playhead position
  void setSlotPlayheadPosition(double position) {
    _slotPlayheadPosition = position.clamp(0.0, 1.0);
    // Don't notify - high frequency updates
  }

  /// Set slot timeline zoom
  void setSlotTimelineZoom(double zoom) {
    _slotTimelineZoom = zoom.clamp(0.25, 8.0);
    _markChanged(changeSlotElements);
  }

  /// Set slot loop enabled
  void setSlotLoopEnabled(bool enabled) {
    _slotLoopEnabled = enabled;
    _markChanged(changeSlotElements);
  }

  /// Initialize default slot tracks if empty
  void initializeDefaultSlotTracks() {
    if (_slotTracks.isNotEmpty) return;

    _slotTracks.addAll([
      SlotAudioTrack(
        id: 'spin_loop',
        name: 'Spin Loop',
        color: const Color(0xFF4A9EFF),
      ),
      SlotAudioTrack(
        id: 'reel_stops',
        name: 'Reel Stops',
        color: const Color(0xFF9B59B6),
      ),
      SlotAudioTrack(
        id: 'anticipation',
        name: 'Anticipation',
        color: const Color(0xFFE74C3C),
      ),
      SlotAudioTrack(
        id: 'win_music',
        name: 'Win Music',
        color: const Color(0xFFF1C40F),
      ),
      SlotAudioTrack(
        id: 'rollup',
        name: 'Rollup',
        color: const Color(0xFF40FF90),
      ),
      SlotAudioTrack(
        id: 'big_win',
        name: 'Big Win Stinger',
        color: const Color(0xFFFF9040),
      ),
    ]);

    _slotMarkers.addAll([
      const SlotStageMarker(id: 'm1', position: 0.0, name: 'SPIN START', color: Color(0xFF4A9EFF)),
      const SlotStageMarker(id: 'm2', position: 0.12, name: 'REEL 1', color: Color(0xFF9B59B6)),
      const SlotStageMarker(id: 'm3', position: 0.22, name: 'ANTIC', color: Color(0xFFE74C3C)),
      const SlotStageMarker(id: 'm4', position: 0.35, name: 'WIN', color: Color(0xFFF1C40F)),
      const SlotStageMarker(id: 'm5', position: 0.40, name: 'ROLLUP', color: Color(0xFF40FF90)),
      const SlotStageMarker(id: 'm6', position: 0.65, name: 'BIG WIN', color: Color(0xFFFF9040)),
      const SlotStageMarker(id: 'm7', position: 1.0, name: 'END', color: Color(0xFF888888)),
    ]);

    _markChanged(changeSlotElements);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPOSITE EVENT UNDO/REDO (delegated to CompositeEventSystemProvider)
  // ═══════════════════════════════════════════════════════════════════════════

  void undoCompositeEvents() => _compositeEventSystemProvider.undoCompositeEvents();
  void redoCompositeEvents() => _compositeEventSystemProvider.redoCompositeEvents();
  void clearUndoHistory() => _compositeEventSystemProvider.clearUndoHistory();

  // ═══════════════════════════════════════════════════════════════════════════
  // LAYER SELECTION & CLIPBOARD (delegated to CompositeEventSystemProvider)
  // ═══════════════════════════════════════════════════════════════════════════

  void selectLayer(String? layerId) => _compositeEventSystemProvider.selectLayer(layerId);
  void toggleLayerSelection(String layerId) => _compositeEventSystemProvider.toggleLayerSelection(layerId);
  void selectLayerRange(String eventId, String fromLayerId, String toLayerId) =>
      _compositeEventSystemProvider.selectLayerRange(eventId, fromLayerId, toLayerId);
  void selectAllLayers(String eventId) => _compositeEventSystemProvider.selectAllLayers(eventId);
  void clearLayerSelection() => _compositeEventSystemProvider.clearLayerSelection();
  bool isLayerSelected(String layerId) => _compositeEventSystemProvider.isLayerSelected(layerId);

  // ─────────────────────────────────────────────────────────────────────────
  // BATCH OPERATIONS FOR MULTI-SELECT (delegated)
  // ─────────────────────────────────────────────────────────────────────────

  void deleteSelectedLayers(String eventId) => _compositeEventSystemProvider.deleteSelectedLayers(eventId);
  void muteSelectedLayers(String eventId, bool mute) => _compositeEventSystemProvider.muteSelectedLayers(eventId, mute);
  void soloSelectedLayers(String eventId, bool solo) => _compositeEventSystemProvider.soloSelectedLayers(eventId, solo);
  void adjustSelectedLayersVolume(String eventId, double volumeDelta) =>
      _compositeEventSystemProvider.adjustSelectedLayersVolume(eventId, volumeDelta);
  void moveSelectedLayers(String eventId, double offsetDeltaMs) =>
      _compositeEventSystemProvider.moveSelectedLayers(eventId, offsetDeltaMs);
  List<SlotEventLayer> duplicateSelectedLayers(String eventId) =>
      _compositeEventSystemProvider.duplicateSelectedLayers(eventId);
  void copyLayer(String eventId, String layerId) => _compositeEventSystemProvider.copyLayer(eventId, layerId);
  SlotEventLayer? pasteLayer(String eventId) => _compositeEventSystemProvider.pasteLayer(eventId);
  SlotEventLayer? duplicateLayer(String eventId, String layerId) =>
      _compositeEventSystemProvider.duplicateLayer(eventId, layerId);
  void clearClipboard() => _compositeEventSystemProvider.clearClipboard();

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPOSITE EVENT METHODS (delegated to CompositeEventSystemProvider - P1.5)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new composite event
  SlotCompositeEvent createCompositeEvent({
    required String name,
    String category = 'general',
    Color? color,
  }) {
    final event = _compositeEventSystemProvider.createCompositeEvent(
      name: name,
      category: category,
      color: color,
    );
    _markChanged(changeCompositeEvents);
    return event;
  }

  /// Create composite event from template
  SlotCompositeEvent createFromTemplate(SlotCompositeEvent template) {
    final event = _compositeEventSystemProvider.createFromTemplate(template);
    _markChanged(changeCompositeEvents);
    return event;
  }

  /// Delete a composite event
  void deleteCompositeEvent(String eventId) {
    _compositeEventSystemProvider.deleteCompositeEvent(eventId);
    _markChanged(changeCompositeEvents);
  }

  /// Select a composite event
  void selectCompositeEvent(String? eventId) {
    _compositeEventSystemProvider.selectCompositeEvent(eventId);
    _markChanged(changeCompositeEvents);
  }

  /// Duplicate a composite event
  void duplicateCompositeEvent(String eventId) {
    final source = compositeEvents.where((e) => e.id == eventId).firstOrNull;
    if (source == null) return;

    final newEvent = createCompositeEvent(
      name: '${source.name} (Copy)',
      category: source.category,
      color: source.color,
    );

    // Copy layers
    for (final layer in source.layers) {
      addLayerToEvent(
        newEvent.id,
        audioPath: layer.audioPath,
        name: layer.name,
        durationSeconds: layer.durationSeconds,
        waveformData: layer.waveformData,
      );
    }

    // Copy trigger stages
    for (final stage in source.triggerStages) {
      addTriggerStage(newEvent.id, stage);
    }

    selectCompositeEvent(newEvent.id);
    debugPrint('[MiddlewareProvider] Duplicated event "${source.name}" → "${newEvent.name}"');
  }

  /// Preview a composite event (play all layers)
  /// Uses playCompositeEvent internally for actual audio playback
  void previewCompositeEvent(String eventId) {
    final event = compositeEvents.where((e) => e.id == eventId).firstOrNull;
    if (event == null) {
      debugPrint('[MiddlewareProvider] previewCompositeEvent: Event not found: $eventId');
      return;
    }

    debugPrint('[MiddlewareProvider] Preview event "${event.name}" (${event.layers.length} layers)');

    // Use playCompositeEvent for actual audio playback
    final voicesStarted = playCompositeEvent(eventId);
    debugPrint('[MiddlewareProvider] Preview started $voicesStarted voices for "${event.name}"');
  }

  /// Add existing composite event (for sync from external sources)
  void addCompositeEvent(SlotCompositeEvent event, {bool select = true}) {
    _compositeEventSystemProvider.addCompositeEvent(event, select: select);
    _markChanged(changeCompositeEvents);
  }

  /// Update composite event
  void updateCompositeEvent(SlotCompositeEvent event) {
    _compositeEventSystemProvider.updateCompositeEvent(event);
    _markChanged(changeCompositeEvents);
  }

  /// Rename composite event
  void renameCompositeEvent(String eventId, String newName) {
    _compositeEventSystemProvider.renameCompositeEvent(eventId, newName);
    _markChanged(changeCompositeEvents);
  }

  /// Add layer to composite event
  SlotEventLayer addLayerToEvent(String eventId, {
    required String audioPath,
    required String name,
    double? durationSeconds,
    List<double>? waveformData,
  }) {
    final layer = _compositeEventSystemProvider.addLayerToEvent(
      eventId,
      audioPath: audioPath,
      name: name,
      durationSeconds: durationSeconds,
      waveformData: waveformData,
    );
    _markChanged(changeCompositeEvents);
    return layer;
  }

  /// Remove layer from composite event
  void removeLayerFromEvent(String eventId, String layerId) {
    _compositeEventSystemProvider.removeLayerFromEvent(eventId, layerId);
    _markChanged(changeCompositeEvents);
  }

  /// Update layer in composite event (public, with undo)
  void updateEventLayer(String eventId, SlotEventLayer layer) {
    _compositeEventSystemProvider.updateEventLayer(eventId, layer);
    _markChanged(changeCompositeEvents);
  }

  /// Toggle layer mute
  void toggleLayerMute(String eventId, String layerId) {
    _compositeEventSystemProvider.toggleLayerMute(eventId, layerId);
    _markChanged(changeCompositeEvents);
  }

  /// Toggle layer solo
  void toggleLayerSolo(String eventId, String layerId) {
    _compositeEventSystemProvider.toggleLayerSolo(eventId, layerId);
    _markChanged(changeCompositeEvents);
  }

  /// Set layer volume (no undo - use for continuous slider updates)
  void setLayerVolumeContinuous(String eventId, String layerId, double volume) {
    _compositeEventSystemProvider.setLayerVolumeContinuous(eventId, layerId, volume);
    _markChanged(changeCompositeEvents);
  }

  /// Set layer volume (with undo - use for final value or discrete changes)
  void setLayerVolume(String eventId, String layerId, double volume) {
    _compositeEventSystemProvider.setLayerVolume(eventId, layerId, volume);
    _markChanged(changeCompositeEvents);
  }

  /// Set layer pan (no undo - use for continuous slider updates)
  void setLayerPanContinuous(String eventId, String layerId, double pan) {
    _compositeEventSystemProvider.setLayerPanContinuous(eventId, layerId, pan);
    _markChanged(changeCompositeEvents);
  }

  /// Set layer pan (with undo - use for final value)
  void setLayerPan(String eventId, String layerId, double pan) {
    _compositeEventSystemProvider.setLayerPan(eventId, layerId, pan);
    _markChanged(changeCompositeEvents);
  }

  /// Set layer offset (no undo - use for continuous drag updates)
  void setLayerOffsetContinuous(String eventId, String layerId, double offsetMs) {
    _compositeEventSystemProvider.setLayerOffsetContinuous(eventId, layerId, offsetMs);
    _markChanged(changeCompositeEvents);
  }

  /// Set layer offset (with undo - use for final value)
  void setLayerOffset(String eventId, String layerId, double offsetMs) {
    _compositeEventSystemProvider.setLayerOffset(eventId, layerId, offsetMs);
    _markChanged(changeCompositeEvents);
  }

  /// Set layer fade in/out times
  void setLayerFade(String eventId, String layerId, double fadeInMs, double fadeOutMs) {
    _compositeEventSystemProvider.setLayerFade(eventId, layerId, fadeInMs, fadeOutMs);
    _markChanged(changeCompositeEvents);
  }

  /// Reorder layers in event
  void reorderEventLayers(String eventId, int oldIndex, int newIndex) {
    _compositeEventSystemProvider.reorderEventLayers(eventId, oldIndex, newIndex);
    _markChanged(changeCompositeEvents);
  }

  /// Get composite event by ID
  SlotCompositeEvent? getCompositeEvent(String eventId) =>
      _compositeEventSystemProvider.getCompositeEvent(eventId);

  /// Get events by category
  List<SlotCompositeEvent> getEventsByCategory(String category) =>
      _compositeEventSystemProvider.getEventsByCategory(category);

  /// Initialize default composite events from templates
  void initializeDefaultCompositeEvents() {
    _compositeEventSystemProvider.initializeDefaultCompositeEvents();
    _markChanged(changeCompositeEvents);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REAL-TIME SYNC (delegated to CompositeEventSystemProvider - P1.5)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sync MiddlewareEvent back to SlotCompositeEvent (bidirectional)
  void syncMiddlewareToComposite(String middlewareId) {
    _compositeEventSystemProvider.syncMiddlewareToComposite(middlewareId);
    _markChanged(changeCompositeEvents);
  }

  /// Check if a middleware event is linked to a composite event
  bool isLinkedToComposite(String middlewareId) =>
      _compositeEventSystemProvider.isLinkedToComposite(middlewareId);

  /// Get composite event for a middleware event
  SlotCompositeEvent? getCompositeForMiddleware(String middlewareId) =>
      _compositeEventSystemProvider.getCompositeForMiddleware(middlewareId);

  /// Expand composite event to timeline clips
  List<Map<String, dynamic>> expandEventToTimelineClips(
    String compositeEventId, {
    required double startPositionNormalized,
    required double timelineWidth,
  }) => _compositeEventSystemProvider.expandEventToTimelineClips(
      compositeEventId,
      startPositionNormalized: startPositionNormalized,
      timelineWidth: timelineWidth,
    );

  // ===========================================================================
  // PROJECT SAVE/LOAD - Composite Events (delegated - P1.5)
  // ===========================================================================

  /// Export all composite events to JSON
  Map<String, dynamic> exportCompositeEventsToJson() =>
      _compositeEventSystemProvider.exportCompositeEventsToJson();

  /// Import composite events from JSON
  void importCompositeEventsFromJson(Map<String, dynamic> json) {
    _compositeEventSystemProvider.importCompositeEventsFromJson(json);
    _markChanged(changeCompositeEvents);
  }

  /// Get all composite events as JSON string
  String exportCompositeEventsToJsonString() =>
      _compositeEventSystemProvider.exportCompositeEventsToJsonString();

  /// Import composite events from JSON string
  void importCompositeEventsFromJsonString(String jsonString) {
    _compositeEventSystemProvider.importCompositeEventsFromJsonString(jsonString);
    _markChanged(changeCompositeEvents);
  }

  /// Clear all composite events
  void clearAllCompositeEvents() {
    _compositeEventSystemProvider.clearAllCompositeEvents();
    _markChanged(changeCompositeEvents);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE TRIGGER MAPPING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all available stage type names (canonical STAGES)
  static const List<String> availableStageTypes = [
    // Spin Lifecycle
    'spin_start',
    'reel_spinning',
    'reel_stop',
    'evaluate_wins',
    'spin_end',
    // Anticipation
    'anticipation_on',
    'anticipation_off',
    // Win Lifecycle
    'win_present',
    'win_line_show',
    'rollup_start',
    'rollup_tick',
    'rollup_end',
    'bigwin_tier',
    // Feature Lifecycle
    'feature_enter',
    'feature_step',
    'feature_retrigger',
    'feature_exit',
    // Cascade
    'cascade_start',
    'cascade_step',
    'cascade_end',
    // Bonus
    'bonus_enter',
    'bonus_choice',
    'bonus_reveal',
    'bonus_exit',
    // Gamble
    'gamble_start',
    'gamble_choice',
    'gamble_result',
    'gamble_end',
    // Jackpot
    'jackpot_trigger',
    'jackpot_present',
    'jackpot_end',
    // UI/Idle
    'idle_start',
    'idle_loop',
    'menu_open',
    'menu_close',
    'autoplay_start',
    'autoplay_stop',
    // Special
    'symbol_transform',
    'wild_expand',
    'multiplier_change',
  ];

  /// Get stage display name
  static String getStageDisplayName(String stageType) {
    return switch (stageType) {
      'spin_start' => 'Spin Start',
      'reel_spinning' => 'Reel Spinning',
      'reel_stop' => 'Reel Stop',
      'evaluate_wins' => 'Evaluate Wins',
      'spin_end' => 'Spin End',
      'anticipation_on' => 'Anticipation ON',
      'anticipation_off' => 'Anticipation OFF',
      'win_present' => 'Win Present',
      'win_line_show' => 'Win Line Show',
      'rollup_start' => 'Rollup Start',
      'rollup_tick' => 'Rollup Tick',
      'rollup_end' => 'Rollup End',
      'bigwin_tier' => 'Big Win Tier',
      'feature_enter' => 'Feature Enter',
      'feature_step' => 'Feature Step',
      'feature_retrigger' => 'Feature Retrigger',
      'feature_exit' => 'Feature Exit',
      'cascade_start' => 'Cascade Start',
      'cascade_step' => 'Cascade Step',
      'cascade_end' => 'Cascade End',
      'bonus_enter' => 'Bonus Enter',
      'bonus_choice' => 'Bonus Choice',
      'bonus_reveal' => 'Bonus Reveal',
      'bonus_exit' => 'Bonus Exit',
      'gamble_start' => 'Gamble Start',
      'gamble_choice' => 'Gamble Choice',
      'gamble_result' => 'Gamble Result',
      'gamble_end' => 'Gamble End',
      'jackpot_trigger' => 'Jackpot Trigger',
      'jackpot_present' => 'Jackpot Present',
      'jackpot_end' => 'Jackpot End',
      'idle_start' => 'Idle Start',
      'idle_loop' => 'Idle Loop',
      'menu_open' => 'Menu Open',
      'menu_close' => 'Menu Close',
      'autoplay_start' => 'Autoplay Start',
      'autoplay_stop' => 'Autoplay Stop',
      'symbol_transform' => 'Symbol Transform',
      'wild_expand' => 'Wild Expand',
      'multiplier_change' => 'Multiplier Change',
      _ => stageType,
    };
  }

  /// Get stage category
  static String getStageCategory(String stageType) {
    return switch (stageType) {
      'spin_start' || 'reel_spinning' || 'reel_stop' || 'evaluate_wins' || 'spin_end' => 'Spin Lifecycle',
      'anticipation_on' || 'anticipation_off' => 'Anticipation',
      'win_present' || 'win_line_show' || 'rollup_start' || 'rollup_tick' || 'rollup_end' || 'bigwin_tier' => 'Win Lifecycle',
      'feature_enter' || 'feature_step' || 'feature_retrigger' || 'feature_exit' => 'Feature',
      'cascade_start' || 'cascade_step' || 'cascade_end' => 'Cascade',
      'bonus_enter' || 'bonus_choice' || 'bonus_reveal' || 'bonus_exit' => 'Bonus',
      'gamble_start' || 'gamble_choice' || 'gamble_result' || 'gamble_end' => 'Gamble',
      'jackpot_trigger' || 'jackpot_present' || 'jackpot_end' => 'Jackpot',
      'idle_start' || 'idle_loop' || 'menu_open' || 'menu_close' || 'autoplay_start' || 'autoplay_stop' => 'UI/Idle',
      'symbol_transform' || 'wild_expand' || 'multiplier_change' => 'Special',
      _ => 'Unknown',
    };
  }

  /// Set trigger stages for a composite event
  void setTriggerStages(String eventId, List<String> stages) {
    _compositeEventSystemProvider.setTriggerStages(eventId, stages);
    _markChanged(changeCompositeEvents);
  }

  /// Add a trigger stage to a composite event
  void addTriggerStage(String eventId, String stageType) {
    _compositeEventSystemProvider.addTriggerStage(eventId, stageType);
    _markChanged(changeCompositeEvents);
  }

  /// Remove a trigger stage from a composite event
  void removeTriggerStage(String eventId, String stageType) {
    _compositeEventSystemProvider.removeTriggerStage(eventId, stageType);
    _markChanged(changeCompositeEvents);
  }

  /// Set trigger conditions for a composite event
  void setTriggerConditions(String eventId, Map<String, String> conditions) {
    _compositeEventSystemProvider.setTriggerConditions(eventId, conditions);
    _markChanged(changeCompositeEvents);
  }

  /// Add a trigger condition
  void addTriggerCondition(String eventId, String rtpcName, String condition) {
    _compositeEventSystemProvider.addTriggerCondition(eventId, rtpcName, condition);
    _markChanged(changeCompositeEvents);
  }

  /// Remove a trigger condition
  void removeTriggerCondition(String eventId, String rtpcName) {
    _compositeEventSystemProvider.removeTriggerCondition(eventId, rtpcName);
    _markChanged(changeCompositeEvents);
  }

  /// Find all composite events that should trigger for a given stage type
  List<SlotCompositeEvent> getEventsForStage(String stageType) =>
      _compositeEventSystemProvider.getEventsForStage(stageType);

  /// Find all composite events that match stage + conditions
  List<SlotCompositeEvent> getEventsForStageWithConditions(
    String stageType,
    Map<String, double> rtpcValues,
  ) => _compositeEventSystemProvider.getEventsForStageWithConditions(stageType, rtpcValues);

  /// Get all stages that have at least one event mapped
  List<String> get mappedStages => _compositeEventSystemProvider.mappedStages;

  /// Get event count per stage (for visualization)
  Map<String, int> get stageEventCounts => _compositeEventSystemProvider.stageEventCounts;

  @override
  void dispose() {
    // ═══════════════════════════════════════════════════════════════════════════
    // P0.1 FIX: Proper resource cleanup to prevent 100-500 MB memory leak
    // ═══════════════════════════════════════════════════════════════════════════

    // 0. Cancel debounce timer (P1.1/P1.2)
    _debounceTimer?.cancel();

    // 1. Remove listeners from subsystem providers (P1.1 FIX: use granular listeners)
    // P1.15 FIX: Reset registration flag
    if (_listenersRegistered) {
      _stateGroupsProvider.removeListener(_onStateGroupsChanged);
      _switchGroupsProvider.removeListener(_onSwitchGroupsChanged);
      _rtpcSystemProvider.removeListener(_onRtpcChanged);
      _duckingSystemProvider.removeListener(_onDuckingChanged);
      _blendContainersProvider.removeListener(_onBlendContainersChanged);
      _randomContainersProvider.removeListener(_onRandomContainersChanged);
      _sequenceContainersProvider.removeListener(_onSequenceContainersChanged);
      _eventSystemProvider.removeListener(_onEventSystemChanged);
      _compositeEventSystemProvider.removeListener(_onCompositeEventsChanged);
      _listenersRegistered = false;
    }

    // 2. Clear composite events (P1.5: delegated to provider)
    _compositeEventSystemProvider.clear();

    // 3. Dispose AutoSpatial engine
    _autoSpatialEngine.dispose();

    // 4. Clear event profiler
    _eventProfilerProvider.clear();

    // 5. Clear music system data (delegates to MusicSystemProvider)
    _musicSystemProvider.clear();
    _attenuationCurveProvider.clear();

    // 6. Clear slot element mappings
    _slotElementMappings.clear();
    _customElementMappings.clear();

    // 7. Clear slot mode state
    _slotTracks.clear();
    _slotMarkers.clear();

    debugPrint('[MiddlewareProvider] dispose() complete - all resources released');

    super.dispose();
  }
}
