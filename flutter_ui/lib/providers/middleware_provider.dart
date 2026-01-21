// Middleware Provider
//
// State management for Wwise/FMOD-style middleware system:
// - State Groups (global states affecting sound)
// - Switch Groups (per-object sound variants)
// - RTPC (Real-Time Parameter Control)
//
// Connects Dart UI to Rust rf-event system via FFI.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/middleware_models.dart';
import '../models/slot_audio_events.dart';
import '../models/advanced_middleware_models.dart';
import '../services/rtpc_modulation_service.dart';
import '../services/ducking_service.dart';
import '../services/container_service.dart';
import '../services/audio_asset_manager.dart';
import '../spatial/auto_spatial.dart';
import '../src/rust/native_ffi.dart';
import '../services/unified_playback_controller.dart';

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

  // State Groups
  final Map<int, StateGroup> _stateGroups = {};

  // Switch Groups
  final Map<int, SwitchGroup> _switchGroups = {};

  // Per-object switch values: gameObjectId -> (groupId -> switchId)
  final Map<int, Map<int, int>> _objectSwitches = {};

  // RTPC Definitions
  final Map<int, RtpcDefinition> _rtpcDefs = {};

  // Per-object RTPC values: gameObjectId -> (rtpcId -> value)
  final Map<int, Map<int, double>> _objectRtpcs = {};

  // RTPC Bindings (RTPC → parameter mappings)
  final Map<int, RtpcBinding> _rtpcBindings = {};

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED FEATURES
  // ═══════════════════════════════════════════════════════════════════════════

  // Ducking Rules
  final Map<int, DuckingRule> _duckingRules = {};

  // Blend Containers
  final Map<int, BlendContainer> _blendContainers = {};

  // Random Containers
  final Map<int, RandomContainer> _randomContainers = {};

  // Sequence Containers
  final Map<int, SequenceContainer> _sequenceContainers = {};

  // Music Segments
  final Map<int, MusicSegment> _musicSegments = {};

  // Stingers
  final Map<int, Stinger> _stingers = {};

  // Attenuation Curves
  final Map<int, AttenuationCurve> _attenuationCurves = {};

  // ═══════════════════════════════════════════════════════════════════════════
  // SLOT ELEMENT MAPPINGS (bidirectional sync with Slot Fullscreen)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Slot element to event mappings
  final Map<SlotElementType, SlotElementEventMapping> _slotElementMappings = {};

  /// Custom element mappings (for user-defined elements)
  final Map<String, SlotElementEventMapping> _customElementMappings = {};

  // Music system state
  int? _currentMusicSegmentId;
  int? _nextMusicSegmentId;
  int _musicBusId = 1; // Music bus

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Voice pool for polyphony management
  final VoicePool _voicePool = VoicePool(
    config: const VoicePoolConfig(
      maxVoices: 48,
      stealingMode: VoiceStealingMode.lowestPriority,
      enableVirtualVoices: true,
    ),
  );

  /// Bus hierarchy with effects
  final BusHierarchy _busHierarchy = BusHierarchy();

  /// Aux send routing manager
  final AuxSendManager _auxSendManager = AuxSendManager();

  /// Memory budget manager
  final MemoryBudgetManager _memoryManager = MemoryBudgetManager(
    config: const MemoryBudgetConfig(
      maxResidentBytes: 64 * 1024 * 1024, // 64MB
      maxStreamingBytes: 32 * 1024 * 1024, // 32MB
    ),
  );

  /// Event profiler
  final EventProfiler _eventProfiler = EventProfiler(maxEvents: 10000);

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
  // COMPOSITE EVENTS (Wwise/FMOD-style layered events)
  // ═══════════════════════════════════════════════════════════════════════════

  final Map<String, SlotCompositeEvent> _compositeEvents = {};
  String? _selectedCompositeEventId;
  int _nextLayerId = 1;

  // Undo/Redo stacks for composite events
  final List<Map<String, SlotCompositeEvent>> _undoStack = [];
  final List<Map<String, SlotCompositeEvent>> _redoStack = [];
  static const int _maxUndoHistory = 50;

  // Layer clipboard for copy/paste
  SlotEventLayer? _layerClipboard;
  String? _selectedLayerId;

  // Multi-select support for batch operations
  final Set<String> _selectedLayerIds = {};

  // Change listeners for bidirectional sync
  final List<void Function(String eventId, CompositeEventChangeType type)> _compositeChangeListeners = [];

  // ID counters for new groups
  int _nextStateGroupId = 100;
  int _nextSwitchGroupId = 100;
  int _nextRtpcId = 100;
  int _nextBindingId = 1;
  int _nextDuckingRuleId = 1;
  int _nextBlendContainerId = 1;
  int _nextRandomContainerId = 1;
  int _nextSequenceContainerId = 1;
  int _nextMusicSegmentIdCounter = 1;
  int _nextStingerId = 1;
  int _nextAttenuationCurveId = 1;

  MiddlewareProvider(this._ffi) {
    _initializeDefaults();
    _initializeServices();
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

  List<StateGroup> get stateGroups => _stateGroups.values.toList();
  List<SwitchGroup> get switchGroups => _switchGroups.values.toList();
  List<RtpcDefinition> get rtpcDefinitions => _rtpcDefs.values.toList();
  List<RtpcBinding> get rtpcBindings => _rtpcBindings.values.toList();

  // Advanced features getters
  List<DuckingRule> get duckingRules => _duckingRules.values.toList();
  List<BlendContainer> get blendContainers => _blendContainers.values.toList();
  List<RandomContainer> get randomContainers => _randomContainers.values.toList();
  List<SequenceContainer> get sequenceContainers => _sequenceContainers.values.toList();
  List<MusicSegment> get musicSegments => _musicSegments.values.toList();
  List<Stinger> get stingers => _stingers.values.toList();
  List<AttenuationCurve> get attenuationCurves => _attenuationCurves.values.toList();
  int? get currentMusicSegmentId => _currentMusicSegmentId;
  int? get nextMusicSegmentId => _nextMusicSegmentId;
  int get musicBusId => _musicBusId;

  // Advanced systems getters
  VoicePool get voicePool => _voicePool;
  BusHierarchy get busHierarchy => _busHierarchy;
  AuxSendManager get auxSendManager => _auxSendManager;
  MemoryBudgetManager get memoryManager => _memoryManager;
  EventProfiler get eventProfiler => _eventProfiler;
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

  // Composite Events getters
  List<SlotCompositeEvent> get compositeEvents => _compositeEvents.values.toList();
  SlotCompositeEvent? get selectedCompositeEvent =>
      _selectedCompositeEventId != null ? _compositeEvents[_selectedCompositeEventId] : null;
  String? get selectedCompositeEventId => _selectedCompositeEventId;

  // Undo/Redo getters
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoStackSize => _undoStack.length;
  int get redoStackSize => _redoStack.length;

  // Layer clipboard getters
  bool get hasLayerInClipboard => _layerClipboard != null;
  SlotEventLayer? get layerClipboard => _layerClipboard;
  String? get selectedLayerId => _selectedLayerId;

  // Multi-select getters
  Set<String> get selectedLayerIds => Set.unmodifiable(_selectedLayerIds);
  bool get hasMultipleLayersSelected => _selectedLayerIds.length > 1;
  int get selectedLayerCount => _selectedLayerIds.length;

  // ═══════════════════════════════════════════════════════════════════════════
  // CHANGE LISTENERS (Bidirectional Sync)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a listener for composite event changes
  void addCompositeChangeListener(void Function(String eventId, CompositeEventChangeType type) listener) {
    _compositeChangeListeners.add(listener);
  }

  /// Remove a composite event change listener
  void removeCompositeChangeListener(void Function(String eventId, CompositeEventChangeType type) listener) {
    _compositeChangeListeners.remove(listener);
  }

  /// Notify all listeners of a change
  void _notifyCompositeChange(String eventId, CompositeEventChangeType type) {
    for (final listener in _compositeChangeListeners) {
      listener(eventId, type);
    }
  }

  StateGroup? getStateGroup(int groupId) => _stateGroups[groupId];
  SwitchGroup? getSwitchGroup(int groupId) => _switchGroups[groupId];
  RtpcDefinition? getRtpc(int rtpcId) => _rtpcDefs[rtpcId];
  RtpcBinding? getRtpcBinding(int bindingId) => _rtpcBindings[bindingId];

  /// Get current state for a group
  int getCurrentState(int groupId) {
    return _stateGroups[groupId]?.currentStateId ?? 0;
  }

  /// Get current state name for a group
  String getCurrentStateName(int groupId) {
    return _stateGroups[groupId]?.currentStateName ?? 'None';
  }

  /// Get switch value for a game object
  int getSwitch(int gameObjectId, int groupId) {
    return _objectSwitches[gameObjectId]?[groupId] ??
        _switchGroups[groupId]?.defaultSwitchId ?? 0;
  }

  /// Get switch name for a game object
  String? getSwitchName(int gameObjectId, int groupId) {
    final switchId = getSwitch(gameObjectId, groupId);
    return _switchGroups[groupId]?.switchName(switchId);
  }

  /// Get RTPC value (global)
  double getRtpcValue(int rtpcId) {
    return _rtpcDefs[rtpcId]?.currentValue ?? 0.0;
  }

  /// Get RTPC value for specific object (falls back to global)
  double getRtpcValueForObject(int gameObjectId, int rtpcId) {
    return _objectRtpcs[gameObjectId]?[rtpcId] ?? getRtpcValue(rtpcId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE GROUPS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a state group from predefined constants
  void registerStateGroupFromPreset(String name, List<String> stateNames) {
    final groupId = _nextStateGroupId++;

    final states = <StateDefinition>[];
    for (int i = 0; i < stateNames.length; i++) {
      states.add(StateDefinition(id: i, name: stateNames[i]));
    }

    final group = StateGroup(
      id: groupId,
      name: name,
      states: states,
      currentStateId: 0,
      defaultStateId: 0,
    );

    _stateGroups[groupId] = group;

    // Register with Rust
    _ffi.middlewareRegisterStateGroup(groupId, name, defaultState: 0);
    for (final state in states) {
      _ffi.middlewareAddState(groupId, state.id, state.name);
    }

    notifyListeners();
  }

  /// Register a custom state group
  void registerStateGroup(StateGroup group) {
    _stateGroups[group.id] = group;

    // Register with Rust
    _ffi.middlewareRegisterStateGroup(group.id, group.name, defaultState: group.defaultStateId);
    for (final state in group.states) {
      _ffi.middlewareAddState(group.id, state.id, state.name);
    }

    notifyListeners();
  }

  /// Set current state (global)
  void setState(int groupId, int stateId) {
    final group = _stateGroups[groupId];
    if (group == null) return;

    _stateGroups[groupId] = group.copyWith(currentStateId: stateId);

    // Send to Rust
    _ffi.middlewareSetState(groupId, stateId);

    notifyListeners();
  }

  /// Set state by name
  void setStateByName(int groupId, String stateName) {
    final group = _stateGroups[groupId];
    if (group == null) return;

    final state = group.states.where((s) => s.name == stateName).firstOrNull;
    if (state != null) {
      setState(groupId, state.id);
    }
  }

  /// Reset state to default
  void resetState(int groupId) {
    final group = _stateGroups[groupId];
    if (group == null) return;

    setState(groupId, group.defaultStateId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SWITCH GROUPS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a switch group
  void registerSwitchGroup(SwitchGroup group) {
    _switchGroups[group.id] = group;

    // Register with Rust
    _ffi.middlewareRegisterSwitchGroup(group.id, group.name);
    for (final sw in group.switches) {
      _ffi.middlewareAddSwitch(group.id, sw.id, sw.name);
    }

    notifyListeners();
  }

  /// Register switch group from name and switch names
  void registerSwitchGroupFromPreset(String name, List<String> switchNames) {
    final groupId = _nextSwitchGroupId++;

    final switches = <SwitchDefinition>[];
    for (int i = 0; i < switchNames.length; i++) {
      switches.add(SwitchDefinition(id: i, name: switchNames[i]));
    }

    final group = SwitchGroup(
      id: groupId,
      name: name,
      switches: switches,
      defaultSwitchId: 0,
    );

    registerSwitchGroup(group);
  }

  /// Set switch for a game object
  void setSwitch(int gameObjectId, int groupId, int switchId) {
    _objectSwitches[gameObjectId] ??= {};
    _objectSwitches[gameObjectId]![groupId] = switchId;

    // Send to Rust
    _ffi.middlewareSetSwitch(gameObjectId, groupId, switchId);

    notifyListeners();
  }

  /// Set switch by name
  void setSwitchByName(int gameObjectId, int groupId, String switchName) {
    final group = _switchGroups[groupId];
    if (group == null) return;

    final sw = group.switches.where((s) => s.name == switchName).firstOrNull;
    if (sw != null) {
      setSwitch(gameObjectId, groupId, sw.id);
    }
  }

  /// Reset switch to default for a game object
  void resetSwitch(int gameObjectId, int groupId) {
    final group = _switchGroups[groupId];
    if (group == null) return;

    setSwitch(gameObjectId, groupId, group.defaultSwitchId);
  }

  /// Clear all switches for a game object
  void clearObjectSwitches(int gameObjectId) {
    _objectSwitches.remove(gameObjectId);
    notifyListeners();
  }

  /// Unregister a state group
  ///
  /// Note: Rust FFI currently doesn't support unregister - group remains
  /// in engine but is removed from UI tracking. IDs are never reused.
  void unregisterStateGroup(int groupId) {
    _stateGroups.remove(groupId);
    notifyListeners();
  }

  /// Unregister a switch group
  ///
  /// Note: Rust FFI currently doesn't support unregister - group remains
  /// in engine but is removed from UI tracking. IDs are never reused.
  void unregisterSwitchGroup(int groupId) {
    _switchGroups.remove(groupId);
    // Remove from all objects
    for (final objectSwitches in _objectSwitches.values) {
      objectSwitches.remove(groupId);
    }
    notifyListeners();
  }

  /// Unregister an RTPC
  ///
  /// Note: Rust FFI currently doesn't support unregister - RTPC remains
  /// in engine but is removed from UI tracking. IDs are never reused.
  void unregisterRtpc(int rtpcId) {
    _rtpcDefs.remove(rtpcId);
    // Remove from all objects
    for (final objectRtpcs in _objectRtpcs.values) {
      objectRtpcs.remove(rtpcId);
    }
    // Remove bindings that use this RTPC
    _rtpcBindings.removeWhere((_, binding) => binding.rtpcId == rtpcId);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RTPC
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register an RTPC parameter
  void registerRtpc(RtpcDefinition rtpc) {
    _rtpcDefs[rtpc.id] = rtpc;

    // Register with Rust
    _ffi.middlewareRegisterRtpc(
      rtpc.id,
      rtpc.name,
      rtpc.min,
      rtpc.max,
      rtpc.defaultValue,
    );

    notifyListeners();
  }

  /// Register RTPC from preset data
  void registerRtpcFromPreset(Map<String, dynamic> preset) {
    final rtpc = RtpcDefinition(
      id: preset['id'] as int,
      name: preset['name'] as String,
      min: (preset['min'] as num).toDouble(),
      max: (preset['max'] as num).toDouble(),
      defaultValue: (preset['default'] as num).toDouble(),
      currentValue: (preset['default'] as num).toDouble(),
    );

    registerRtpc(rtpc);
  }

  /// Set RTPC value globally
  void setRtpc(int rtpcId, double value, {int interpolationMs = 0}) {
    final rtpc = _rtpcDefs[rtpcId];
    if (rtpc == null) return;

    final clampedValue = rtpc.clamp(value);
    _rtpcDefs[rtpcId] = rtpc.copyWith(currentValue: clampedValue);

    // Send to Rust
    _ffi.middlewareSetRtpc(rtpcId, clampedValue, interpolationMs: interpolationMs);

    notifyListeners();
  }

  /// Set RTPC value for specific game object
  void setRtpcOnObject(int gameObjectId, int rtpcId, double value, {int interpolationMs = 0}) {
    final rtpc = _rtpcDefs[rtpcId];
    if (rtpc == null) return;

    final clampedValue = rtpc.clamp(value);
    _objectRtpcs[gameObjectId] ??= {};
    _objectRtpcs[gameObjectId]![rtpcId] = clampedValue;

    // Send to Rust
    _ffi.middlewareSetRtpcOnObject(gameObjectId, rtpcId, clampedValue, interpolationMs: interpolationMs);

    notifyListeners();
  }

  /// Reset RTPC to default value
  void resetRtpc(int rtpcId, {int interpolationMs = 100}) {
    final rtpc = _rtpcDefs[rtpcId];
    if (rtpc == null) return;

    setRtpc(rtpcId, rtpc.defaultValue, interpolationMs: interpolationMs);
  }

  /// Clear all RTPC overrides for a game object
  void clearObjectRtpcs(int gameObjectId) {
    _objectRtpcs.remove(gameObjectId);
    notifyListeners();
  }

  /// Update RTPC curve
  void updateRtpcCurve(int rtpcId, RtpcCurve curve) {
    final rtpc = _rtpcDefs[rtpcId];
    if (rtpc == null) return;

    _rtpcDefs[rtpcId] = rtpc.copyWith(curve: curve);
    notifyListeners();
  }

  /// Add point to RTPC curve
  void addRtpcCurvePoint(int rtpcId, RtpcCurvePoint point) {
    final rtpc = _rtpcDefs[rtpcId];
    if (rtpc == null) return;

    final currentPoints = rtpc.curve?.points.toList() ?? [];
    currentPoints.add(point);
    currentPoints.sort((a, b) => a.x.compareTo(b.x));

    _rtpcDefs[rtpcId] = rtpc.copyWith(curve: RtpcCurve(points: currentPoints));
    notifyListeners();
  }

  /// Remove point from RTPC curve
  void removeRtpcCurvePoint(int rtpcId, int pointIndex) {
    final rtpc = _rtpcDefs[rtpcId];
    if (rtpc == null || rtpc.curve == null) return;

    final currentPoints = rtpc.curve!.points.toList();
    if (pointIndex >= 0 && pointIndex < currentPoints.length) {
      currentPoints.removeAt(pointIndex);
      _rtpcDefs[rtpcId] = rtpc.copyWith(curve: RtpcCurve(points: currentPoints));
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RTPC BINDINGS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create an RTPC binding
  RtpcBinding createBinding(int rtpcId, RtpcTargetParameter target, {int? busId, int? eventId}) {
    final bindingId = _nextBindingId++;

    RtpcBinding binding;
    if (busId != null) {
      binding = RtpcBinding.forBus(bindingId, rtpcId, target, busId);
    } else {
      binding = RtpcBinding.linear(bindingId, rtpcId, target);
      if (eventId != null) {
        binding = binding.copyWith(targetEventId: eventId);
      }
    }

    _rtpcBindings[bindingId] = binding;
    notifyListeners();
    return binding;
  }

  /// Update a binding's curve
  void updateBindingCurve(int bindingId, RtpcCurve curve) {
    final binding = _rtpcBindings[bindingId];
    if (binding == null) return;

    _rtpcBindings[bindingId] = binding.copyWith(curve: curve);
    notifyListeners();
  }

  /// Enable/disable a binding
  void setBindingEnabled(int bindingId, bool enabled) {
    final binding = _rtpcBindings[bindingId];
    if (binding == null) return;

    _rtpcBindings[bindingId] = binding.copyWith(enabled: enabled);
    notifyListeners();
  }

  /// Delete a binding
  void deleteBinding(int bindingId) {
    _rtpcBindings.remove(bindingId);
    notifyListeners();
  }

  /// Get all bindings for an RTPC
  List<RtpcBinding> getBindingsForRtpc(int rtpcId) {
    return _rtpcBindings.values.where((b) => b.rtpcId == rtpcId).toList();
  }

  /// Get all bindings for a target parameter type
  List<RtpcBinding> getBindingsForTarget(RtpcTargetParameter target) {
    return _rtpcBindings.values.where((b) => b.target == target).toList();
  }

  /// Get all bindings for a bus
  List<RtpcBinding> getBindingsForBus(int busId) {
    return _rtpcBindings.values.where((b) => b.targetBusId == busId).toList();
  }

  /// Evaluate all bindings for current RTPC values
  /// Returns map of (target, busId?) -> evaluated value
  Map<(RtpcTargetParameter, int?), double> evaluateAllBindings() {
    final results = <(RtpcTargetParameter, int?), double>{};

    for (final binding in _rtpcBindings.values) {
      if (!binding.enabled) continue;

      final rtpcValue = getRtpcValue(binding.rtpcId);
      final rtpcDef = _rtpcDefs[binding.rtpcId];
      if (rtpcDef == null) continue;

      // Normalize RTPC value to 0-1 for curve evaluation
      final normalized = rtpcDef.normalizedValue;
      final outputValue = binding.curve.evaluate(normalized);

      results[(binding.target, binding.targetBusId)] = outputValue;
    }

    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DUCKING MATRIX
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a ducking rule
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
  }) {
    final id = _nextDuckingRuleId++;

    final rule = DuckingRule(
      id: id,
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

    _duckingRules[id] = rule;

    // Register with Rust
    _ffi.middlewareAddDuckingRule(rule);

    // Sync with DuckingService for Dart-side ducking
    DuckingService.instance.addRule(rule);

    notifyListeners();
    return rule;
  }

  /// Update a ducking rule
  void updateDuckingRule(int ruleId, DuckingRule rule) {
    if (!_duckingRules.containsKey(ruleId)) return;

    _duckingRules[ruleId] = rule;

    // Re-register (remove + add)
    _ffi.middlewareRemoveDuckingRule(ruleId);
    _ffi.middlewareAddDuckingRule(rule);

    // Sync with DuckingService
    DuckingService.instance.updateRule(rule);

    notifyListeners();
  }

  /// Remove a ducking rule
  void removeDuckingRule(int ruleId) {
    _duckingRules.remove(ruleId);
    _ffi.middlewareRemoveDuckingRule(ruleId);

    // Sync with DuckingService
    DuckingService.instance.removeRule(ruleId);

    notifyListeners();
  }

  /// Enable/disable a ducking rule
  void setDuckingRuleEnabled(int ruleId, bool enabled) {
    final rule = _duckingRules[ruleId];
    if (rule == null) return;

    final updatedRule = rule.copyWith(enabled: enabled);
    _duckingRules[ruleId] = updatedRule;
    _ffi.middlewareSetDuckingRuleEnabled(ruleId, enabled);

    // Sync with DuckingService
    DuckingService.instance.updateRule(updatedRule);

    notifyListeners();
  }

  /// Get ducking rule by ID
  DuckingRule? getDuckingRule(int ruleId) => _duckingRules[ruleId];

  // ═══════════════════════════════════════════════════════════════════════════
  // BLEND CONTAINERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a blend container
  BlendContainer createBlendContainer({
    required String name,
    required int rtpcId,
    CrossfadeCurve crossfadeCurve = CrossfadeCurve.equalPower,
  }) {
    final id = _nextBlendContainerId++;

    final container = BlendContainer(
      id: id,
      name: name,
      rtpcId: rtpcId,
      crossfadeCurve: crossfadeCurve,
    );

    _blendContainers[id] = container;
    _ffi.middlewareCreateBlendContainer(container);

    notifyListeners();
    return container;
  }

  /// Add child to blend container
  void blendContainerAddChild(int containerId, BlendChild child) {
    final container = _blendContainers[containerId];
    if (container == null) return;

    final updatedChildren = List<BlendChild>.from(container.children)..add(child);
    _blendContainers[containerId] = container.copyWith(children: updatedChildren);

    _ffi.middlewareBlendAddChild(containerId, child);
    notifyListeners();
  }

  /// Remove child from blend container
  void blendContainerRemoveChild(int containerId, int childId) {
    final container = _blendContainers[containerId];
    if (container == null) return;

    final updatedChildren = container.children.where((c) => c.id != childId).toList();
    _blendContainers[containerId] = container.copyWith(children: updatedChildren);

    _ffi.middlewareBlendRemoveChild(containerId, childId);
    notifyListeners();
  }

  /// Remove blend container
  void removeBlendContainer(int containerId) {
    _blendContainers.remove(containerId);
    _ffi.middlewareRemoveBlendContainer(containerId);
    notifyListeners();
  }

  /// Get blend container by ID
  BlendContainer? getBlendContainer(int containerId) => _blendContainers[containerId];

  // ═══════════════════════════════════════════════════════════════════════════
  // RANDOM CONTAINERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a random container
  RandomContainer createRandomContainer({
    required String name,
    RandomMode mode = RandomMode.random,
    int avoidRepeatCount = 2,
  }) {
    final id = _nextRandomContainerId++;

    final container = RandomContainer(
      id: id,
      name: name,
      mode: mode,
      avoidRepeatCount: avoidRepeatCount,
    );

    _randomContainers[id] = container;
    _ffi.middlewareCreateRandomContainer(container);

    notifyListeners();
    return container;
  }

  /// Add child to random container
  void randomContainerAddChild(int containerId, RandomChild child) {
    final container = _randomContainers[containerId];
    if (container == null) return;

    final updatedChildren = List<RandomChild>.from(container.children)..add(child);
    _randomContainers[containerId] = container.copyWith(children: updatedChildren);

    _ffi.middlewareRandomAddChild(containerId, child);
    notifyListeners();
  }

  /// Remove child from random container
  void randomContainerRemoveChild(int containerId, int childId) {
    final container = _randomContainers[containerId];
    if (container == null) return;

    final updatedChildren = container.children.where((c) => c.id != childId).toList();
    _randomContainers[containerId] = container.copyWith(children: updatedChildren);

    _ffi.middlewareRandomRemoveChild(containerId, childId);
    notifyListeners();
  }

  /// Update global variation for random container
  void randomContainerSetGlobalVariation(
    int containerId, {
    double pitchMin = 0.0,
    double pitchMax = 0.0,
    double volumeMin = 0.0,
    double volumeMax = 0.0,
  }) {
    final container = _randomContainers[containerId];
    if (container == null) return;

    _randomContainers[containerId] = container.copyWith(
      globalPitchMin: pitchMin,
      globalPitchMax: pitchMax,
      globalVolumeMin: volumeMin,
      globalVolumeMax: volumeMax,
    );

    _ffi.middlewareRandomSetGlobalVariation(
      containerId,
      pitchMin: pitchMin,
      pitchMax: pitchMax,
      volumeMin: volumeMin,
      volumeMax: volumeMax,
    );
    notifyListeners();
  }

  /// Remove random container
  void removeRandomContainer(int containerId) {
    _randomContainers.remove(containerId);
    _ffi.middlewareRemoveRandomContainer(containerId);
    notifyListeners();
  }

  /// Get random container by ID
  RandomContainer? getRandomContainer(int containerId) => _randomContainers[containerId];

  // ═══════════════════════════════════════════════════════════════════════════
  // SEQUENCE CONTAINERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a sequence container
  SequenceContainer createSequenceContainer({
    required String name,
    SequenceEndBehavior endBehavior = SequenceEndBehavior.stop,
    double speed = 1.0,
  }) {
    final id = _nextSequenceContainerId++;

    final container = SequenceContainer(
      id: id,
      name: name,
      endBehavior: endBehavior,
      speed: speed,
    );

    _sequenceContainers[id] = container;
    _ffi.middlewareCreateSequenceContainer(container);

    notifyListeners();
    return container;
  }

  /// Add step to sequence container
  void sequenceContainerAddStep(int containerId, SequenceStep step) {
    final container = _sequenceContainers[containerId];
    if (container == null) return;

    final updatedSteps = List<SequenceStep>.from(container.steps)..add(step);
    updatedSteps.sort((a, b) => a.index.compareTo(b.index));
    _sequenceContainers[containerId] = container.copyWith(steps: updatedSteps);

    _ffi.middlewareSequenceAddStep(containerId, step);
    notifyListeners();
  }

  /// Remove step from sequence container
  void sequenceContainerRemoveStep(int containerId, int stepIndex) {
    final container = _sequenceContainers[containerId];
    if (container == null) return;

    final updatedSteps = container.steps.where((s) => s.index != stepIndex).toList();
    _sequenceContainers[containerId] = container.copyWith(steps: updatedSteps);

    _ffi.middlewareSequenceRemoveStep(containerId, stepIndex);
    notifyListeners();
  }

  /// Remove sequence container
  void removeSequenceContainer(int containerId) {
    _sequenceContainers.remove(containerId);
    _ffi.middlewareRemoveSequenceContainer(containerId);
    notifyListeners();
  }

  /// Get sequence container by ID
  SequenceContainer? getSequenceContainer(int containerId) => _sequenceContainers[containerId];

  // ═══════════════════════════════════════════════════════════════════════════
  // MUSIC SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add music segment
  MusicSegment addMusicSegment({
    required String name,
    required int soundId,
    double tempo = 120.0,
    int beatsPerBar = 4,
    int durationBars = 4,
  }) {
    final id = _nextMusicSegmentIdCounter++;

    final segment = MusicSegment(
      id: id,
      name: name,
      soundId: soundId,
      tempo: tempo,
      beatsPerBar: beatsPerBar,
      durationBars: durationBars,
    );

    _musicSegments[id] = segment;
    _ffi.middlewareAddMusicSegment(segment);

    notifyListeners();
    return segment;
  }

  /// Add marker to music segment
  void musicSegmentAddMarker(int segmentId, MusicMarker marker) {
    final segment = _musicSegments[segmentId];
    if (segment == null) return;

    final updatedMarkers = List<MusicMarker>.from(segment.markers)..add(marker);
    updatedMarkers.sort((a, b) => a.positionBars.compareTo(b.positionBars));
    _musicSegments[segmentId] = segment.copyWith(markers: updatedMarkers);

    _ffi.middlewareMusicSegmentAddMarker(segmentId, marker);
    notifyListeners();
  }

  /// Remove music segment
  void removeMusicSegment(int segmentId) {
    _musicSegments.remove(segmentId);
    _ffi.middlewareRemoveMusicSegment(segmentId);
    notifyListeners();
  }

  /// Get music segment by ID
  MusicSegment? getMusicSegment(int segmentId) => _musicSegments[segmentId];

  /// Set current music segment
  void setCurrentMusicSegment(int segmentId) {
    _currentMusicSegmentId = segmentId;
    _ffi.middlewareSetMusicSegment(segmentId);
    notifyListeners();
  }

  /// Queue next music segment for transition
  void queueMusicSegment(int segmentId) {
    _nextMusicSegmentId = segmentId;
    _ffi.middlewareQueueMusicSegment(segmentId);
    notifyListeners();
  }

  /// Set music bus ID
  void setMusicBusId(int busId) {
    _musicBusId = busId;
    _ffi.middlewareSetMusicBus(busId);
    notifyListeners();
  }

  /// Add stinger
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
    final id = _nextStingerId++;

    final stinger = Stinger(
      id: id,
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

    _stingers[id] = stinger;
    _ffi.middlewareAddStinger(stinger);

    notifyListeners();
    return stinger;
  }

  /// Remove stinger
  void removeStinger(int stingerId) {
    _stingers.remove(stingerId);
    _ffi.middlewareRemoveStinger(stingerId);
    notifyListeners();
  }

  /// Get stinger by ID
  Stinger? getStinger(int stingerId) => _stingers[stingerId];

  // ═══════════════════════════════════════════════════════════════════════════
  // ATTENUATION SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add attenuation curve
  AttenuationCurve addAttenuationCurve({
    required String name,
    required AttenuationType attenuationType,
    double inputMin = 0.0,
    double inputMax = 1.0,
    double outputMin = 0.0,
    double outputMax = 1.0,
    RtpcCurveShape curveShape = RtpcCurveShape.linear,
  }) {
    final id = _nextAttenuationCurveId++;

    final curve = AttenuationCurve(
      id: id,
      name: name,
      attenuationType: attenuationType,
      inputMin: inputMin,
      inputMax: inputMax,
      outputMin: outputMin,
      outputMax: outputMax,
      curveShape: curveShape,
    );

    _attenuationCurves[id] = curve;
    _ffi.middlewareAddAttenuationCurve(curve);

    notifyListeners();
    return curve;
  }

  /// Update attenuation curve
  void updateAttenuationCurve(int curveId, AttenuationCurve curve) {
    if (!_attenuationCurves.containsKey(curveId)) return;

    _attenuationCurves[curveId] = curve;

    // Re-register
    _ffi.middlewareRemoveAttenuationCurve(curveId);
    _ffi.middlewareAddAttenuationCurve(curve);

    notifyListeners();
  }

  /// Remove attenuation curve
  void removeAttenuationCurve(int curveId) {
    _attenuationCurves.remove(curveId);
    _ffi.middlewareRemoveAttenuationCurve(curveId);
    notifyListeners();
  }

  /// Enable/disable attenuation curve
  void setAttenuationCurveEnabled(int curveId, bool enabled) {
    final curve = _attenuationCurves[curveId];
    if (curve == null) return;

    _attenuationCurves[curveId] = curve.copyWith(enabled: enabled);
    _ffi.middlewareSetAttenuationCurveEnabled(curveId, enabled);
    notifyListeners();
  }

  /// Evaluate attenuation curve
  double evaluateAttenuationCurve(int curveId, double input) {
    return _ffi.middlewareEvaluateAttenuationCurve(curveId, input);
  }

  /// Get attenuation curve by ID
  AttenuationCurve? getAttenuationCurve(int curveId) => _attenuationCurves[curveId];

  /// Get attenuation curves by type
  List<AttenuationCurve> getAttenuationCurvesByType(AttenuationType type) {
    return _attenuationCurves.values
        .where((c) => c.attenuationType == type && c.enabled)
        .toList();
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
    _objectSwitches.remove(gameObjectId);
    _objectRtpcs.remove(gameObjectId);
    _ffi.middlewareUnregisterGameObject(gameObjectId);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export all state to JSON
  Map<String, dynamic> toJson() => {
    'stateGroups': _stateGroups.values.map((g) => g.toJson()).toList(),
    'switchGroups': _switchGroups.values.map((g) => g.toJson()).toList(),
    'rtpcDefs': _rtpcDefs.values.map((r) => r.toJson()).toList(),
    'rtpcBindings': _rtpcBindings.values.map((b) => b.toJson()).toList(),
    'objectSwitches': _objectSwitches.map(
      (k, v) => MapEntry(k.toString(), v.map((gk, sv) => MapEntry(gk.toString(), sv))),
    ),
    'objectRtpcs': _objectRtpcs.map(
      (k, v) => MapEntry(k.toString(), v.map((rk, rv) => MapEntry(rk.toString(), rv))),
    ),
  };

  /// Load state from JSON
  void fromJson(Map<String, dynamic> json) {
    _stateGroups.clear();
    _switchGroups.clear();
    _rtpcDefs.clear();
    _rtpcBindings.clear();
    _objectSwitches.clear();
    _objectRtpcs.clear();

    // Load state groups
    final stateGroupsList = json['stateGroups'] as List<dynamic>?;
    if (stateGroupsList != null) {
      for (final g in stateGroupsList) {
        final group = StateGroup.fromJson(g as Map<String, dynamic>);
        registerStateGroup(group);
      }
    }

    // Load switch groups
    final switchGroupsList = json['switchGroups'] as List<dynamic>?;
    if (switchGroupsList != null) {
      for (final g in switchGroupsList) {
        final group = SwitchGroup.fromJson(g as Map<String, dynamic>);
        registerSwitchGroup(group);
      }
    }

    // Load RTPCs
    final rtpcList = json['rtpcDefs'] as List<dynamic>?;
    if (rtpcList != null) {
      for (final r in rtpcList) {
        final rtpc = RtpcDefinition.fromJson(r as Map<String, dynamic>);
        registerRtpc(rtpc);
      }
    }

    // Load RTPC bindings
    final bindingsList = json['rtpcBindings'] as List<dynamic>?;
    if (bindingsList != null) {
      for (final b in bindingsList) {
        final binding = RtpcBinding.fromJson(b as Map<String, dynamic>);
        _rtpcBindings[binding.id] = binding;
        if (binding.id >= _nextBindingId) {
          _nextBindingId = binding.id + 1;
        }
      }
    }

    notifyListeners();
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
      stateGroups: _stateGroups.length,
      switchGroups: _switchGroups.length,
      rtpcs: _rtpcDefs.length,
      objectsWithSwitches: _objectSwitches.length,
      objectsWithRtpcs: _objectRtpcs.length,
      duckingRules: _duckingRules.length,
      blendContainers: _blendContainers.length,
      randomContainers: _randomContainers.length,
      sequenceContainers: _sequenceContainers.length,
      musicSegments: _musicSegments.length,
      stingers: _stingers.length,
      attenuationCurves: _attenuationCurves.length,
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
  BlendContainer addBlendContainer({required String name, required int rtpcId}) {
    return createBlendContainer(name: name, rtpcId: rtpcId);
  }

  /// Update blend container
  void updateBlendContainer(BlendContainer container) {
    _blendContainers[container.id] = container;
    notifyListeners();
  }

  /// Add blend child
  void addBlendChild(int containerId, {required String name, required double rtpcStart, required double rtpcEnd}) {
    final nextId = (_blendContainers[containerId]?.children.length ?? 0) + 1;
    blendContainerAddChild(containerId, BlendChild(id: nextId, name: name, rtpcStart: rtpcStart, rtpcEnd: rtpcEnd));
  }

  /// Update blend child
  void updateBlendChild(int containerId, BlendChild child) {
    final container = _blendContainers[containerId];
    if (container == null) return;

    final updatedChildren = container.children.map((c) => c.id == child.id ? child : c).toList();
    _blendContainers[containerId] = container.copyWith(children: updatedChildren);
    notifyListeners();
  }

  /// Remove blend child
  void removeBlendChild(int containerId, int childId) {
    blendContainerRemoveChild(containerId, childId);
  }

  /// Add random container (convenience)
  RandomContainer addRandomContainer({required String name}) {
    return createRandomContainer(name: name);
  }

  /// Update random container
  void updateRandomContainer(RandomContainer container) {
    _randomContainers[container.id] = container;
    notifyListeners();
  }

  /// Add random child
  void addRandomChild(int containerId, {required String name, required double weight}) {
    final nextId = (_randomContainers[containerId]?.children.length ?? 0) + 1;
    randomContainerAddChild(containerId, RandomChild(id: nextId, name: name, weight: weight));
  }

  /// Update random child
  void updateRandomChild(int containerId, RandomChild child) {
    final container = _randomContainers[containerId];
    if (container == null) return;

    final updatedChildren = container.children.map((c) => c.id == child.id ? child : c).toList();
    _randomContainers[containerId] = container.copyWith(children: updatedChildren);
    notifyListeners();
  }

  /// Remove random child
  void removeRandomChild(int containerId, int childId) {
    randomContainerRemoveChild(containerId, childId);
  }

  /// Add sequence container (convenience)
  SequenceContainer addSequenceContainer({required String name}) {
    return createSequenceContainer(name: name);
  }

  /// Update sequence container
  void updateSequenceContainer(SequenceContainer container) {
    _sequenceContainers[container.id] = container;
    notifyListeners();
  }

  /// Add sequence step
  void addSequenceStep(int containerId, {required int childId, required String childName, required double delayMs, required double durationMs}) {
    final nextIndex = (_sequenceContainers[containerId]?.steps.length ?? 0);
    sequenceContainerAddStep(containerId, SequenceStep(index: nextIndex, childId: childId, childName: childName, delayMs: delayMs, durationMs: durationMs));
  }

  /// Update sequence step
  void updateSequenceStep(int containerId, int stepIndex, SequenceStep step) {
    final container = _sequenceContainers[containerId];
    if (container == null) return;

    final updatedSteps = container.steps.map((s) => s.index == stepIndex ? step : s).toList();
    _sequenceContainers[containerId] = container.copyWith(steps: updatedSteps);
    notifyListeners();
  }

  /// Remove sequence step
  void removeSequenceStep(int containerId, int stepIndex) {
    sequenceContainerRemoveStep(containerId, stepIndex);
  }

  /// Update music segment
  void updateMusicSegment(MusicSegment segment) {
    _musicSegments[segment.id] = segment;
    notifyListeners();
  }

  /// Add music marker (convenience)
  void addMusicMarker(int segmentId, {required String name, required double positionBars, required MarkerType markerType}) {
    musicSegmentAddMarker(segmentId, MusicMarker(name: name, positionBars: positionBars, markerType: markerType));
  }

  /// Update stinger
  void updateStinger(Stinger stinger) {
    _stingers[stinger.id] = stinger;
    notifyListeners();
  }

  /// Save attenuation curve using just the curve (extracts id from curve.id)
  void saveAttenuationCurve(AttenuationCurve curve) {
    updateAttenuationCurve(curve.id, curve);
  }

  /// Add attenuation curve (simplified version for UI)
  AttenuationCurve addSimpleAttenuationCurve({required String name, required AttenuationType type}) {
    final id = _nextAttenuationCurveId++;

    final curve = AttenuationCurve(
      id: id,
      name: name,
      attenuationType: type,
    );

    _attenuationCurves[id] = curve;
    _ffi.middlewareAddAttenuationCurve(curve);
    notifyListeners();
    return curve;
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

    notifyListeners();
  }

  /// Clear all middleware data
  void _clearAll() {
    _stateGroups.clear();
    _switchGroups.clear();
    _rtpcDefs.clear();
    _rtpcBindings.clear();
    _objectSwitches.clear();
    _objectRtpcs.clear();
    _duckingRules.clear();
    _blendContainers.clear();
    _randomContainers.clear();
    _sequenceContainers.clear();
    _musicSegments.clear();
    _stingers.clear();
    _attenuationCurves.clear();
    _currentMusicSegmentId = null;
    _nextMusicSegmentId = null;

    // Reset ID counters
    _nextStateGroupId = 100;
    _nextSwitchGroupId = 100;
    _nextRtpcId = 100;
    _nextBindingId = 1;
    _nextDuckingRuleId = 1;
    _nextBlendContainerId = 1;
    _nextRandomContainerId = 1;
    _nextSequenceContainerId = 1;
    _nextMusicSegmentIdCounter = 1;
    _nextStingerId = 1;
    _nextAttenuationCurveId = 1;
  }

  /// Clear all and reinitialize with defaults
  void resetToDefaults() {
    _clearAll();
    _initializeDefaults();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT MANAGEMENT (CRUD + FFI SYNC)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Registered middleware events
  final Map<String, MiddlewareEvent> _events = {};

  /// Event name to numeric ID mapping for FFI
  final Map<String, int> _eventNameToId = {};

  /// Asset name to numeric ID mapping for FFI
  final Map<String, int> _assetNameToId = {};

  /// Bus name to numeric ID mapping
  static const Map<String, int> _busNameToId = {
    'Master': 0,
    'Music': 1,
    'SFX': 2,
    'Voice': 3,
    'UI': 4,
    'Ambience': 5,
    'Reels': 2, // Maps to SFX bus
    'Wins': 2,  // Maps to SFX bus
    'VO': 3,    // Maps to Voice bus
  };

  /// Next event numeric ID
  int _nextEventNumericId = 1000;

  /// Next asset numeric ID
  int _nextAssetNumericId = 2000;

  /// Get all registered events
  List<MiddlewareEvent> get events => _events.values.toList();

  /// Get event by ID
  MiddlewareEvent? getEvent(String id) => _events[id];

  /// Get event by name
  MiddlewareEvent? getEventByName(String name) {
    return _events.values.where((e) => e.name == name).firstOrNull;
  }

  /// Register a new event
  void registerEvent(MiddlewareEvent event) {
    _events[event.id] = event;

    // Assign numeric ID for FFI
    final numericId = _nextEventNumericId++;
    _eventNameToId[event.name] = numericId;

    // Sync to Rust engine
    _syncEventToEngine(event, numericId);

    notifyListeners();
  }

  /// Update an existing event
  void updateEvent(MiddlewareEvent event) {
    if (!_events.containsKey(event.id)) return;

    _events[event.id] = event;

    // Re-sync to engine (need to re-register)
    final numericId = _eventNameToId[event.name];
    if (numericId != null) {
      _syncEventToEngine(event, numericId);
    }

    notifyListeners();
  }

  /// Delete an event
  void deleteEvent(String eventId) {
    final event = _events.remove(eventId);
    if (event != null) {
      _eventNameToId.remove(event.name);
      // Note: Rust side doesn't have unregister, but IDs won't be reused
    }
    notifyListeners();
  }

  /// Add action to an event
  void addActionToEvent(String eventId, MiddlewareAction action) {
    final event = _events[eventId];
    if (event == null) return;

    final updatedActions = [...event.actions, action];
    _events[eventId] = event.copyWith(actions: updatedActions);

    // Re-sync entire event
    final numericId = _eventNameToId[event.name];
    if (numericId != null) {
      _syncEventToEngine(_events[eventId]!, numericId);
    }

    notifyListeners();
  }

  /// Update action in an event
  void updateActionInEvent(String eventId, MiddlewareAction action) {
    final event = _events[eventId];
    if (event == null) return;

    final updatedActions = event.actions.map((a) {
      return a.id == action.id ? action : a;
    }).toList();

    _events[eventId] = event.copyWith(actions: updatedActions);

    // Re-sync entire event
    final numericId = _eventNameToId[event.name];
    if (numericId != null) {
      _syncEventToEngine(_events[eventId]!, numericId);
    }

    notifyListeners();
  }

  /// Remove action from an event
  void removeActionFromEvent(String eventId, String actionId) {
    final event = _events[eventId];
    if (event == null) return;

    final updatedActions = event.actions.where((a) => a.id != actionId).toList();
    _events[eventId] = event.copyWith(actions: updatedActions);

    // Re-sync entire event
    final numericId = _eventNameToId[event.name];
    if (numericId != null) {
      _syncEventToEngine(_events[eventId]!, numericId);
    }

    notifyListeners();
  }

  /// Reorder actions in an event
  void reorderActionsInEvent(String eventId, int oldIndex, int newIndex) {
    final event = _events[eventId];
    if (event == null) return;

    final actions = List<MiddlewareAction>.from(event.actions);
    if (oldIndex < 0 || oldIndex >= actions.length) return;
    if (newIndex < 0 || newIndex > actions.length) return;

    final action = actions.removeAt(oldIndex);
    final insertIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    actions.insert(insertIndex, action);

    _events[eventId] = event.copyWith(actions: actions);

    // Re-sync entire event
    final numericId = _eventNameToId[event.name];
    if (numericId != null) {
      _syncEventToEngine(_events[eventId]!, numericId);
    }

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FFI SYNC - Event to Rust Engine
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sync event to Rust engine via FFI
  void _syncEventToEngine(MiddlewareEvent event, int numericId) {
    // Register event
    _ffi.middlewareRegisterEvent(
      numericId,
      event.name,
      event.category,
      maxInstances: 8,
    );

    // Add all actions
    for (final action in event.actions) {
      _addActionToEngine(numericId, action);
    }
  }

  /// Add action to engine
  void _addActionToEngine(int eventId, MiddlewareAction action) {
    _ffi.middlewareAddAction(
      eventId,
      _mapActionType(action.type),
      assetId: _getOrCreateAssetId(action.assetId),
      busId: _busNameToId[action.bus] ?? 0,
      scope: _mapActionScope(action.scope),
      priority: _mapActionPriority(action.priority),
      fadeCurve: _mapFadeCurve(action.fadeCurve),
      fadeTimeMs: (action.fadeTime * 1000).round(),
      delayMs: (action.delay * 1000).round(),
    );
  }

  /// Map Dart ActionType to FFI MiddlewareActionType
  MiddlewareActionType _mapActionType(ActionType type) {
    return switch (type) {
      ActionType.play => MiddlewareActionType.play,
      ActionType.playAndContinue => MiddlewareActionType.playAndContinue,
      ActionType.stop => MiddlewareActionType.stop,
      ActionType.stopAll => MiddlewareActionType.stopAll,
      ActionType.pause => MiddlewareActionType.pause,
      ActionType.pauseAll => MiddlewareActionType.pauseAll,
      ActionType.resume => MiddlewareActionType.resume,
      ActionType.resumeAll => MiddlewareActionType.resumeAll,
      ActionType.break_ => MiddlewareActionType.breakLoop,
      ActionType.mute => MiddlewareActionType.mute,
      ActionType.unmute => MiddlewareActionType.unmute,
      ActionType.setVolume => MiddlewareActionType.setVolume,
      ActionType.setPitch => MiddlewareActionType.setPitch,
      ActionType.setLPF => MiddlewareActionType.setLPF,
      ActionType.setHPF => MiddlewareActionType.setHPF,
      ActionType.setBusVolume => MiddlewareActionType.setBusVolume,
      ActionType.setState => MiddlewareActionType.setState,
      ActionType.setSwitch => MiddlewareActionType.setSwitch,
      ActionType.setRTPC => MiddlewareActionType.setRTPC,
      ActionType.resetRTPC => MiddlewareActionType.resetRTPC,
      ActionType.seek => MiddlewareActionType.seek,
      ActionType.trigger => MiddlewareActionType.trigger,
      ActionType.postEvent => MiddlewareActionType.postEvent,
    };
  }

  /// Map Dart ActionScope to FFI MiddlewareActionScope
  MiddlewareActionScope _mapActionScope(ActionScope scope) {
    return switch (scope) {
      ActionScope.global => MiddlewareActionScope.global,
      ActionScope.gameObject => MiddlewareActionScope.gameObject,
      ActionScope.emitter => MiddlewareActionScope.emitter,
      ActionScope.all => MiddlewareActionScope.all,
      ActionScope.firstOnly => MiddlewareActionScope.firstOnly,
      ActionScope.random => MiddlewareActionScope.random,
    };
  }

  /// Map Dart ActionPriority to FFI MiddlewareActionPriority
  MiddlewareActionPriority _mapActionPriority(ActionPriority priority) {
    return switch (priority) {
      ActionPriority.lowest => MiddlewareActionPriority.lowest,
      ActionPriority.low => MiddlewareActionPriority.low,
      ActionPriority.belowNormal => MiddlewareActionPriority.belowNormal,
      ActionPriority.normal => MiddlewareActionPriority.normal,
      ActionPriority.aboveNormal => MiddlewareActionPriority.aboveNormal,
      ActionPriority.high => MiddlewareActionPriority.high,
      ActionPriority.highest => MiddlewareActionPriority.highest,
    };
  }

  /// Map Dart FadeCurve to FFI MiddlewareFadeCurve
  MiddlewareFadeCurve _mapFadeCurve(FadeCurve curve) {
    return switch (curve) {
      FadeCurve.linear => MiddlewareFadeCurve.linear,
      FadeCurve.log3 => MiddlewareFadeCurve.log3,
      FadeCurve.sine => MiddlewareFadeCurve.sine,
      FadeCurve.log1 => MiddlewareFadeCurve.log1,
      FadeCurve.invSCurve => MiddlewareFadeCurve.invSCurve,
      FadeCurve.sCurve => MiddlewareFadeCurve.sCurve,
      FadeCurve.exp1 => MiddlewareFadeCurve.exp1,
      FadeCurve.exp3 => MiddlewareFadeCurve.exp3,
    };
  }

  /// Get or create numeric asset ID
  int _getOrCreateAssetId(String assetName) {
    if (assetName.isEmpty || assetName == '—') return 0;

    var id = _assetNameToId[assetName];
    if (id == null) {
      id = _nextAssetNumericId++;
      _assetNameToId[assetName] = id;
    }
    return id;
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
  ///
  /// Returns playing ID (0 if failed)
  int postEvent(String eventId, {int gameObjectId = 0, Map<String, dynamic>? context}) {
    final event = _events[eventId];
    if (event == null) {
      debugPrint('[Middleware] Event not found: $eventId');
      return 0;
    }

    final numericId = _eventNameToId[event.name];
    if (numericId == null) {
      // Auto-register if not yet registered
      final newId = _nextEventNumericId++;
      _eventNameToId[event.name] = newId;
      _syncEventToEngine(event, newId);
      return postEvent(eventId, gameObjectId: gameObjectId, context: context);
    }

    // Acquire Middleware section before playback (blocks DAW/SlotLab)
    final controller = UnifiedPlaybackController.instance;
    if (!controller.acquireSection(PlaybackSection.middleware)) {
      debugPrint('[Middleware] Failed to acquire playback section');
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
      notifyListeners();
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
        final rtpc = _rtpcDefs[100];
        if (rtpc != null) {
          setRtpc(100, ratio.clamp(rtpc.min, rtpc.max));
        }
      }
    }

    // Cascade depth
    if (context.containsKey('cascade_depth')) {
      final depth = (context['cascade_depth'] as num).toDouble();
      final rtpc = _rtpcDefs[104]; // Cascade depth RTPC
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

  /// Stop a playing instance
  void stopPlayingId(int playingId, {int fadeMs = 100}) {
    _ffi.middlewareStopPlayingId(playingId, fadeMs: fadeMs);
    _playingInstances.remove(playingId);

    // Release Middleware section when no more playing instances
    if (_playingInstances.isEmpty) {
      UnifiedPlaybackController.instance.releaseSection(PlaybackSection.middleware);
    }

    notifyListeners();
  }

  /// Stop all instances of an event
  void stopEvent(String eventId, {int fadeMs = 100, int gameObjectId = 0}) {
    final event = _events[eventId];
    if (event == null) return;

    final numericId = _eventNameToId[event.name];
    if (numericId == null) return;

    _ffi.middlewareStopEvent(numericId, gameObjectId: gameObjectId, fadeMs: fadeMs);

    // Remove from playing instances
    _playingInstances.removeWhere((_, v) => v == eventId);

    // Release Middleware section when no more playing instances
    if (_playingInstances.isEmpty) {
      UnifiedPlaybackController.instance.releaseSection(PlaybackSection.middleware);
    }

    notifyListeners();
  }

  /// Stop all playing events
  void stopAllEvents({int fadeMs = 100}) {
    _ffi.middlewareStopAll(fadeMs: fadeMs);
    _playingInstances.clear();

    // Release Middleware section when all events stopped
    UnifiedPlaybackController.instance.releaseSection(PlaybackSection.middleware);

    notifyListeners();
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

    // Register temporarily
    final numericId = _nextEventNumericId++;
    _eventNameToId[tempEventId] = numericId;
    _syncEventToEngine(tempEvent, numericId);

    // Post event
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
      'events': _events.values.map((e) => e.toJson()).toList(),
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
  void syncAllEventsToEngine() {
    for (final event in _events.values) {
      final numericId = _eventNameToId[event.name];
      if (numericId != null) {
        _syncEventToEngine(event, numericId);
      }
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

    notifyListeners();
  }

  /// Ensure event exists for a mapping, create if not
  void _ensureEventForMapping(SlotElementEventMapping mapping) {
    final existingEvent = _events[mapping.eventId];
    if (existingEvent != null) return;

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

    notifyListeners();
  }

  /// Sync a slot layer to its corresponding middleware event
  void _syncSlotLayerToEvent(SlotElementEventMapping mapping, SlotAudioLayer layer) {
    final event = _events[mapping.eventId];
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

    notifyListeners();
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
    final event = _events[mapping.eventId];
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

    notifyListeners();
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

    notifyListeners();
  }

  /// Remove custom slot element mapping
  void removeCustomSlotElement(String customName) {
    final mapping = _customElementMappings.remove(customName);
    if (mapping != null) {
      // Optionally delete the event too
      deleteEvent(mapping.eventId);
    }
    notifyListeners();
  }

  /// Sync from Middleware Event to Slot Element
  /// Called when event is modified in Event Editor - updates slot element mapping
  void syncEventToSlotElement(String eventId) {
    final event = _events[eventId];
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

    notifyListeners();
  }

  /// Get event for a slot element
  MiddlewareEvent? getEventForSlotElement(SlotElementType element, [String? customName]) {
    final mapping = getSlotElementMapping(element, customName);
    if (mapping == null) return null;
    return _events[mapping.eventId];
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
      _duckingRules[rule.id] = rule;
      _ffi.middlewareAddDuckingRule(rule);
    }

    // Add music segments
    for (final segment in profile.musicSegments) {
      _musicSegments[segment.id] = segment;
      _ffi.middlewareAddMusicSegment(segment);
    }

    // Add stingers
    for (final stinger in profile.stingers) {
      _stingers[stinger.id] = stinger;
      _ffi.middlewareAddStinger(stinger);
    }

    // Set up element mappings
    for (final mapping in profile.elementMappings) {
      if (mapping.element == SlotElementType.custom && mapping.customName != null) {
        _customElementMappings[mapping.customName!] = mapping;
      } else {
        _slotElementMappings[mapping.element] = mapping;
      }
    }

    notifyListeners();
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

    notifyListeners();
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
    final voiceId = _voicePool.requestVoice(
      soundId: soundId,
      busId: busId,
      priority: priority,
      volume: volume,
      pitch: pitch,
      pan: pan,
      spatialDistance: spatialDistance,
    );

    if (voiceId != null) {
      _eventProfiler.record(
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
    _voicePool.releaseVoice(voiceId);
    _eventProfiler.record(
      type: ProfilerEventType.voiceStop,
      description: 'Voice $voiceId released',
      voiceId: voiceId,
    );
  }

  /// Get voice pool statistics
  VoicePoolStats getVoicePoolStats() => _voicePool.getStats();

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS - BUS HIERARCHY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get a bus by ID
  AudioBus? getBus(int busId) => _busHierarchy.getBus(busId);

  /// Get all buses
  List<AudioBus> getAllBuses() => _busHierarchy.allBuses;

  /// Get effective volume for a bus (considering parent chain)
  double getEffectiveBusVolume(int busId) => _busHierarchy.getEffectiveVolume(busId);

  /// Set bus volume
  void setBusVolume(int busId, double volume) {
    final bus = _busHierarchy.getBus(busId);
    if (bus != null) {
      bus.volume = volume.clamp(0.0, 1.0);
      notifyListeners();
    }
  }

  /// Set bus mute
  void setBusMute(int busId, bool mute) {
    final bus = _busHierarchy.getBus(busId);
    if (bus != null) {
      bus.mute = mute;
      notifyListeners();
    }
  }

  /// Set bus solo
  void setBusSolo(int busId, bool solo) {
    final bus = _busHierarchy.getBus(busId);
    if (bus != null) {
      bus.solo = solo;
      notifyListeners();
    }
  }

  /// Add effect to bus pre-insert chain
  void addBusPreInsert(int busId, EffectSlot effect) {
    final bus = _busHierarchy.getBus(busId);
    if (bus != null) {
      bus.addPreInsert(effect);
      notifyListeners();
    }
  }

  /// Add effect to bus post-insert chain
  void addBusPostInsert(int busId, EffectSlot effect) {
    final bus = _busHierarchy.getBus(busId);
    if (bus != null) {
      bus.addPostInsert(effect);
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS - AUX SEND ROUTING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all aux buses
  List<AuxBus> getAllAuxBuses() => _auxSendManager.allAuxBuses;

  /// Get all aux sends
  List<AuxSend> getAllAuxSends() => _auxSendManager.allSends;

  /// Get an aux bus by ID
  AuxBus? getAuxBus(int auxBusId) => _auxSendManager.getAuxBus(auxBusId);

  /// Get sends from a specific source bus
  List<AuxSend> getSendsFromBus(int sourceBusId) {
    return _auxSendManager.getSendsFromBus(sourceBusId);
  }

  /// Get sends to a specific aux bus
  List<AuxSend> getSendsToAux(int auxBusId) {
    return _auxSendManager.getSendsToAux(auxBusId);
  }

  /// Create a new aux send
  AuxSend createAuxSend({
    required int sourceBusId,
    required int auxBusId,
    double sendLevel = 0.0,
    SendPosition position = SendPosition.postFader,
  }) {
    final send = _auxSendManager.createSend(
      sourceBusId: sourceBusId,
      auxBusId: auxBusId,
      sendLevel: sendLevel,
      position: position,
    );
    _eventProfiler.record(
      type: ProfilerEventType.eventTrigger,
      description: 'Aux send created: ${send.sendId} (bus $sourceBusId → aux $auxBusId)',
    );
    notifyListeners();
    return send;
  }

  /// Set aux send level
  void setAuxSendLevel(int sendId, double level) {
    _auxSendManager.setSendLevel(sendId, level);
    notifyListeners();
  }

  /// Toggle aux send enabled
  void toggleAuxSendEnabled(int sendId) {
    _auxSendManager.toggleSendEnabled(sendId);
    notifyListeners();
  }

  /// Set aux send position (pre/post fader)
  void setAuxSendPosition(int sendId, SendPosition position) {
    _auxSendManager.setSendPosition(sendId, position);
    notifyListeners();
  }

  /// Remove an aux send
  void removeAuxSend(int sendId) {
    _auxSendManager.removeSend(sendId);
    notifyListeners();
  }

  /// Add a new aux bus
  AuxBus addAuxBus({
    required String name,
    required EffectType effectType,
  }) {
    final auxBus = _auxSendManager.addAuxBus(
      name: name,
      effectType: effectType,
    );
    _eventProfiler.record(
      type: ProfilerEventType.eventTrigger,
      description: 'Aux bus created: ${auxBus.auxBusId} ($name)',
    );
    notifyListeners();
    return auxBus;
  }

  /// Set aux bus return level
  void setAuxReturnLevel(int auxBusId, double level) {
    _auxSendManager.setAuxReturnLevel(auxBusId, level);
    notifyListeners();
  }

  /// Toggle aux bus mute
  void toggleAuxMute(int auxBusId) {
    _auxSendManager.toggleAuxMute(auxBusId);
    notifyListeners();
  }

  /// Toggle aux bus solo
  void toggleAuxSolo(int auxBusId) {
    _auxSendManager.toggleAuxSolo(auxBusId);
    notifyListeners();
  }

  /// Set aux effect parameter
  void setAuxEffectParam(int auxBusId, String param, double value) {
    _auxSendManager.setAuxEffectParam(auxBusId, param, value);
    notifyListeners();
  }

  /// Calculate total send contribution to an aux bus
  double calculateAuxInput(int auxBusId, Map<int, double> busLevels) {
    return _auxSendManager.calculateAuxInput(auxBusId, busLevels);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS - MEMORY MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a soundbank
  void registerSoundbank(SoundBank bank) {
    _memoryManager.registerBank(bank);
  }

  /// Load a soundbank
  bool loadSoundbank(String bankId) {
    final success = _memoryManager.loadBank(bankId);
    if (success) {
      _eventProfiler.record(
        type: ProfilerEventType.bankLoad,
        description: 'Bank loaded: $bankId',
      );
    }
    return success;
  }

  /// Unload a soundbank
  bool unloadSoundbank(String bankId) {
    final success = _memoryManager.unloadBank(bankId);
    if (success) {
      _eventProfiler.record(
        type: ProfilerEventType.bankUnload,
        description: 'Bank unloaded: $bankId',
      );
    }
    return success;
  }

  /// Get memory statistics
  MemoryStats getMemoryStats() => _memoryManager.getStats();

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS - SPATIAL AUDIO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update reel spatial config
  void updateReelSpatialConfig(ReelSpatialConfig config) {
    _reelSpatialConfig = config;
    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
  }

  /// Update HDR config
  void updateHdrConfig(HdrAudioConfig config) {
    _hdrConfig = config;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS - STREAMING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update streaming config
  void updateStreamingConfig(StreamingConfig config) {
    _streamingConfig = config;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED AUDIO SYSTEMS - PROFILER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Record a profiler event
  void recordProfilerEvent({
    required ProfilerEventType type,
    required String description,
    int? soundId,
    int? busId,
    int? voiceId,
    double? value,
    int latencyUs = 0,
  }) {
    _eventProfiler.record(
      type: type,
      description: description,
      soundId: soundId,
      busId: busId,
      voiceId: voiceId,
      value: value,
      latencyUs: latencyUs,
    );
  }

  /// Get profiler statistics
  ProfilerStats getProfilerStats() => _eventProfiler.getStats();

  /// Get recent profiler events
  List<ProfilerEvent> getRecentProfilerEvents({int count = 100}) {
    return _eventProfiler.getRecentEvents(count: count);
  }

  /// Clear profiler
  void clearProfiler() {
    _eventProfiler.clear();
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
    notifyListeners();
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
    notifyListeners();
  }

  /// Remove audio file from shared pool (now delegates to AudioAssetManager)
  void removeFromSharedPool(String fileId) {
    final manager = AudioAssetManager.instance;
    try {
      manager.removeById(fileId);
    } catch (_) {
      // Asset may not exist, ignore
    }
    notifyListeners();
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
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SLOT MODE STATE METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set slot tracks (replaces all)
  void setSlotTracks(List<SlotAudioTrack> tracks) {
    _slotTracks.clear();
    _slotTracks.addAll(tracks);
    notifyListeners();
  }

  /// Update a single slot track
  void updateSlotTrack(SlotAudioTrack track) {
    final index = _slotTracks.indexWhere((t) => t.id == track.id);
    if (index >= 0) {
      _slotTracks[index] = track;
      notifyListeners();
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
      notifyListeners();
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
      notifyListeners();
    }
  }

  /// Set slot stage markers
  void setSlotMarkers(List<SlotStageMarker> markers) {
    _slotMarkers.clear();
    _slotMarkers.addAll(markers);
    notifyListeners();
  }

  /// Set slot playhead position
  void setSlotPlayheadPosition(double position) {
    _slotPlayheadPosition = position.clamp(0.0, 1.0);
    // Don't notify - high frequency updates
  }

  /// Set slot timeline zoom
  void setSlotTimelineZoom(double zoom) {
    _slotTimelineZoom = zoom.clamp(0.25, 8.0);
    notifyListeners();
  }

  /// Set slot loop enabled
  void setSlotLoopEnabled(bool enabled) {
    _slotLoopEnabled = enabled;
    notifyListeners();
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

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPOSITE EVENT UNDO/REDO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Push current state to undo stack before making changes
  void _pushUndoState() {
    // Deep copy current state
    final snapshot = <String, SlotCompositeEvent>{};
    for (final entry in _compositeEvents.entries) {
      snapshot[entry.key] = entry.value.copyWith(
        layers: List<SlotEventLayer>.from(entry.value.layers),
      );
    }
    _undoStack.add(snapshot);

    // Limit stack size
    while (_undoStack.length > _maxUndoHistory) {
      _undoStack.removeAt(0);
    }

    // Clear redo stack on new action
    _redoStack.clear();
  }

  /// Undo last composite event change
  void undoCompositeEvents() {
    if (_undoStack.isEmpty) return;

    // Save current state to redo stack
    final currentSnapshot = <String, SlotCompositeEvent>{};
    for (final entry in _compositeEvents.entries) {
      currentSnapshot[entry.key] = entry.value.copyWith(
        layers: List<SlotEventLayer>.from(entry.value.layers),
      );
    }
    _redoStack.add(currentSnapshot);

    // Restore previous state
    final previousState = _undoStack.removeLast();
    _compositeEvents.clear();
    _compositeEvents.addAll(previousState);

    // Validate selected event still exists
    if (_selectedCompositeEventId != null &&
        !_compositeEvents.containsKey(_selectedCompositeEventId)) {
      _selectedCompositeEventId = _compositeEvents.keys.firstOrNull;
    }

    // Sync all events
    for (final event in _compositeEvents.values) {
      _syncCompositeToMiddleware(event);
    }

    notifyListeners();
    debugPrint('[Undo] Restored composite events state (undo: ${_undoStack.length}, redo: ${_redoStack.length})');
  }

  /// Redo previously undone change
  void redoCompositeEvents() {
    if (_redoStack.isEmpty) return;

    // Save current state to undo stack
    final currentSnapshot = <String, SlotCompositeEvent>{};
    for (final entry in _compositeEvents.entries) {
      currentSnapshot[entry.key] = entry.value.copyWith(
        layers: List<SlotEventLayer>.from(entry.value.layers),
      );
    }
    _undoStack.add(currentSnapshot);

    // Restore redo state
    final redoState = _redoStack.removeLast();
    _compositeEvents.clear();
    _compositeEvents.addAll(redoState);

    // Validate selected event still exists
    if (_selectedCompositeEventId != null &&
        !_compositeEvents.containsKey(_selectedCompositeEventId)) {
      _selectedCompositeEventId = _compositeEvents.keys.firstOrNull;
    }

    // Sync all events
    for (final event in _compositeEvents.values) {
      _syncCompositeToMiddleware(event);
    }

    notifyListeners();
    debugPrint('[Redo] Restored composite events state (undo: ${_undoStack.length}, redo: ${_redoStack.length})');
  }

  /// Clear undo/redo history
  void clearUndoHistory() {
    _undoStack.clear();
    _redoStack.clear();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LAYER SELECTION & CLIPBOARD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Select a layer for clipboard operations
  void selectLayer(String? layerId) {
    _selectedLayerId = layerId;
    // Clear multi-select when single select
    _selectedLayerIds.clear();
    if (layerId != null) {
      _selectedLayerIds.add(layerId);
    }
    notifyListeners();
  }

  /// Add layer to multi-selection (Cmd/Ctrl+click)
  void toggleLayerSelection(String layerId) {
    if (_selectedLayerIds.contains(layerId)) {
      _selectedLayerIds.remove(layerId);
      // Update primary selection
      _selectedLayerId = _selectedLayerIds.isNotEmpty ? _selectedLayerIds.last : null;
    } else {
      _selectedLayerIds.add(layerId);
      _selectedLayerId = layerId;
    }
    notifyListeners();
  }

  /// Range selection (Shift+click)
  void selectLayerRange(String eventId, String fromLayerId, String toLayerId) {
    final event = _compositeEvents[eventId];
    if (event == null) return;

    final layers = event.layers;
    final fromIndex = layers.indexWhere((l) => l.id == fromLayerId);
    final toIndex = layers.indexWhere((l) => l.id == toLayerId);

    if (fromIndex < 0 || toIndex < 0) return;

    final start = fromIndex < toIndex ? fromIndex : toIndex;
    final end = fromIndex < toIndex ? toIndex : fromIndex;

    for (int i = start; i <= end; i++) {
      _selectedLayerIds.add(layers[i].id);
    }
    _selectedLayerId = toLayerId;
    notifyListeners();
  }

  /// Select all layers in event
  void selectAllLayers(String eventId) {
    final event = _compositeEvents[eventId];
    if (event == null) return;

    _selectedLayerIds.clear();
    for (final layer in event.layers) {
      _selectedLayerIds.add(layer.id);
    }
    _selectedLayerId = event.layers.isNotEmpty ? event.layers.last.id : null;
    notifyListeners();
  }

  /// Clear multi-selection
  void clearLayerSelection() {
    _selectedLayerIds.clear();
    _selectedLayerId = null;
    notifyListeners();
  }

  /// Check if layer is selected
  bool isLayerSelected(String layerId) => _selectedLayerIds.contains(layerId);

  // ─────────────────────────────────────────────────────────────────────────
  // BATCH OPERATIONS FOR MULTI-SELECT
  // ─────────────────────────────────────────────────────────────────────────

  /// Delete all selected layers
  void deleteSelectedLayers(String eventId) {
    if (_selectedLayerIds.isEmpty) return;

    final event = _compositeEvents[eventId];
    if (event == null) return;

    _pushUndoState();

    final updatedLayers = event.layers
        .where((l) => !_selectedLayerIds.contains(l.id))
        .toList();

    final updated = event.copyWith(
      layers: updatedLayers,
      modifiedAt: DateTime.now(),
    );

    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    _selectedLayerIds.clear();
    _selectedLayerId = null;
    notifyListeners();
  }

  /// Mute/unmute all selected layers
  void muteSelectedLayers(String eventId, bool mute) {
    if (_selectedLayerIds.isEmpty) return;

    final event = _compositeEvents[eventId];
    if (event == null) return;

    _pushUndoState();

    final updatedLayers = event.layers.map((l) {
      if (_selectedLayerIds.contains(l.id)) {
        return l.copyWith(muted: mute);
      }
      return l;
    }).toList();

    final updated = event.copyWith(
      layers: updatedLayers,
      modifiedAt: DateTime.now(),
    );

    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    notifyListeners();
  }

  /// Solo selected layers (mute all others)
  void soloSelectedLayers(String eventId, bool solo) {
    if (_selectedLayerIds.isEmpty) return;

    final event = _compositeEvents[eventId];
    if (event == null) return;

    _pushUndoState();

    final updatedLayers = event.layers.map((l) {
      final isSelected = _selectedLayerIds.contains(l.id);
      if (solo) {
        // When soloing, mute non-selected layers
        return l.copyWith(muted: !isSelected);
      } else {
        // When un-soloing, unmute all
        return l.copyWith(muted: false);
      }
    }).toList();

    final updated = event.copyWith(
      layers: updatedLayers,
      modifiedAt: DateTime.now(),
    );

    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    notifyListeners();
  }

  /// Adjust volume for all selected layers
  void adjustSelectedLayersVolume(String eventId, double volumeDelta) {
    if (_selectedLayerIds.isEmpty) return;

    final event = _compositeEvents[eventId];
    if (event == null) return;

    _pushUndoState();

    final updatedLayers = event.layers.map((l) {
      if (_selectedLayerIds.contains(l.id)) {
        return l.copyWith(
          volume: (l.volume + volumeDelta).clamp(0.0, 2.0),
        );
      }
      return l;
    }).toList();

    final updated = event.copyWith(
      layers: updatedLayers,
      modifiedAt: DateTime.now(),
    );

    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    notifyListeners();
  }

  /// Move all selected layers by offset
  void moveSelectedLayers(String eventId, double offsetDeltaMs) {
    if (_selectedLayerIds.isEmpty) return;

    final event = _compositeEvents[eventId];
    if (event == null) return;

    _pushUndoState();

    final updatedLayers = event.layers.map((l) {
      if (_selectedLayerIds.contains(l.id)) {
        return l.copyWith(
          offsetMs: (l.offsetMs + offsetDeltaMs).clamp(0.0, double.infinity),
        );
      }
      return l;
    }).toList();

    final updated = event.copyWith(
      layers: updatedLayers,
      modifiedAt: DateTime.now(),
    );

    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    notifyListeners();
  }

  /// Duplicate all selected layers
  List<SlotEventLayer> duplicateSelectedLayers(String eventId) {
    if (_selectedLayerIds.isEmpty) return [];

    final event = _compositeEvents[eventId];
    if (event == null) return [];

    _pushUndoState();

    final newLayers = <SlotEventLayer>[];
    final layersToDuplicate = event.layers
        .where((l) => _selectedLayerIds.contains(l.id))
        .toList();

    for (final layer in layersToDuplicate) {
      final newId = 'layer_${_nextLayerId++}';
      final duplicated = layer.copyWith(
        id: newId,
        name: '${layer.name} (copy)',
        offsetMs: layer.offsetMs + 100,
      );
      newLayers.add(duplicated);
    }

    final updated = event.copyWith(
      layers: [...event.layers, ...newLayers],
      modifiedAt: DateTime.now(),
    );

    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    notifyListeners();

    return newLayers;
  }

  /// Copy selected layer to clipboard
  void copyLayer(String eventId, String layerId) {
    final event = _compositeEvents[eventId];
    if (event == null) return;

    try {
      final layer = event.layers.firstWhere((l) => l.id == layerId);
      _layerClipboard = layer;
      _selectedLayerId = layerId;
      notifyListeners();
      debugPrint('[Clipboard] Copied layer: ${layer.name}');
    } catch (e) {
      debugPrint('[Clipboard] Layer not found: $layerId');
    }
  }

  /// Paste layer from clipboard to event
  SlotEventLayer? pasteLayer(String eventId) {
    if (_layerClipboard == null) return null;
    final event = _compositeEvents[eventId];
    if (event == null) return null;

    _pushUndoState();

    final newId = 'layer_${_nextLayerId++}';
    final pastedLayer = _layerClipboard!.copyWith(
      id: newId,
      name: '${_layerClipboard!.name} (copy)',
    );

    final updated = event.copyWith(
      layers: [...event.layers, pastedLayer],
      modifiedAt: DateTime.now(),
    );
    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated);
    notifyListeners();

    debugPrint('[Clipboard] Pasted layer: ${pastedLayer.name}');
    return pastedLayer;
  }

  /// Duplicate a layer within the same event
  SlotEventLayer? duplicateLayer(String eventId, String layerId) {
    final event = _compositeEvents[eventId];
    if (event == null) return null;

    try {
      final layer = event.layers.firstWhere((l) => l.id == layerId);
      _pushUndoState();

      final newId = 'layer_${_nextLayerId++}';
      final duplicatedLayer = layer.copyWith(
        id: newId,
        name: '${layer.name} (copy)',
        offsetMs: layer.offsetMs + 100, // Slight offset so it's visible
      );

      final updated = event.copyWith(
        layers: [...event.layers, duplicatedLayer],
        modifiedAt: DateTime.now(),
      );
      _compositeEvents[eventId] = updated;
      _syncCompositeToMiddleware(updated);
      notifyListeners();

      debugPrint('[Duplicate] Created: ${duplicatedLayer.name}');
      return duplicatedLayer;
    } catch (e) {
      debugPrint('[Duplicate] Layer not found: $layerId');
      return null;
    }
  }

  /// Clear clipboard
  void clearClipboard() {
    _layerClipboard = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPOSITE EVENT METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new composite event
  SlotCompositeEvent createCompositeEvent({
    required String name,
    String category = 'general',
    Color? color,
  }) {
    _pushUndoState();
    final id = 'event_${DateTime.now().millisecondsSinceEpoch}';
    final event = SlotCompositeEvent(
      id: id,
      name: name,
      category: category,
      color: color ?? SlotEventCategory.values
          .firstWhere((c) => c.name == category, orElse: () => SlotEventCategory.ui)
          .color,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );
    _compositeEvents[id] = event;
    _selectedCompositeEventId = id;
    _syncCompositeToMiddleware(event); // Real-time sync
    _notifyCompositeChange(id, CompositeEventChangeType.created);
    notifyListeners();
    return event;
  }

  /// Create composite event from template
  SlotCompositeEvent createFromTemplate(SlotCompositeEvent template) {
    _pushUndoState();
    final id = 'event_${DateTime.now().millisecondsSinceEpoch}';
    final event = template.copyWith(
      id: id,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );
    _compositeEvents[id] = event;
    _selectedCompositeEventId = id;
    _syncCompositeToMiddleware(event); // Real-time sync
    notifyListeners();
    return event;
  }

  /// Delete a composite event
  void deleteCompositeEvent(String eventId) {
    _pushUndoState();
    _compositeEvents.remove(eventId);
    _removeMiddlewareEventForComposite(eventId); // Real-time sync
    if (_selectedCompositeEventId == eventId) {
      _selectedCompositeEventId = _compositeEvents.keys.firstOrNull;
    }
    notifyListeners();
  }

  /// Select a composite event
  void selectCompositeEvent(String? eventId) {
    _selectedCompositeEventId = eventId;
    notifyListeners();
  }

  /// Add existing composite event (for sync from external sources)
  void addCompositeEvent(SlotCompositeEvent event, {bool select = true}) {
    debugPrint('[Middleware] addCompositeEvent: ${event.name} (id: ${event.id})');
    _pushUndoState();
    _compositeEvents[event.id] = event;
    _syncCompositeToMiddleware(event);
    // Auto-select newly added event
    if (select) {
      _selectedCompositeEventId = event.id;
    }
    debugPrint('[Middleware] Total composite events: ${_compositeEvents.length}, selected: $_selectedCompositeEventId');
    notifyListeners();
  }

  /// Update composite event
  void updateCompositeEvent(SlotCompositeEvent event) {
    _pushUndoState();
    _compositeEvents[event.id] = event.copyWith(modifiedAt: DateTime.now());
    _syncCompositeToMiddleware(event); // Real-time sync
    notifyListeners();
  }

  /// Rename composite event
  void renameCompositeEvent(String eventId, String newName) {
    final event = _compositeEvents[eventId];
    if (event != null) {
      _pushUndoState();
      final updated = event.copyWith(
        name: newName,
        modifiedAt: DateTime.now(),
      );
      _compositeEvents[eventId] = updated;
      _syncCompositeToMiddleware(updated); // Real-time sync
      notifyListeners();
    }
  }

  /// Add layer to composite event
  /// If durationSeconds is not provided, auto-detects from audio file via FFI
  SlotEventLayer addLayerToEvent(String eventId, {
    required String audioPath,
    required String name,
    double? durationSeconds,
    List<double>? waveformData,
  }) {
    final event = _compositeEvents[eventId];
    if (event == null) throw Exception('Event not found: $eventId');

    _pushUndoState();

    // Auto-detect duration if not provided
    final actualDuration = durationSeconds ?? _ffi.getAudioFileDuration(audioPath);
    final validDuration = (actualDuration > 0) ? actualDuration : null;

    if (durationSeconds == null && validDuration != null) {
      debugPrint('[Middleware] Auto-detected duration for $name: ${validDuration.toStringAsFixed(2)}s');
    }

    final layerId = 'layer_${_nextLayerId++}';
    final layer = SlotEventLayer(
      id: layerId,
      name: name,
      audioPath: audioPath,
      durationSeconds: validDuration,
      waveformData: waveformData,
    );

    final updated = event.copyWith(
      layers: [...event.layers, layer],
      modifiedAt: DateTime.now(),
    );
    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated); // Real-time sync
    debugPrint('[Middleware] addLayerToEvent: "${updated.name}" now has ${updated.layers.length} layers');
    notifyListeners();
    return layer;
  }

  /// Remove layer from composite event
  void removeLayerFromEvent(String eventId, String layerId) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();

    final updated = event.copyWith(
      layers: event.layers.where((l) => l.id != layerId).toList(),
      modifiedAt: DateTime.now(),
    );
    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated); // Real-time sync
    notifyListeners();
  }

  /// Update layer in composite event (internal, no undo)
  void _updateEventLayerInternal(String eventId, SlotEventLayer layer) {
    final event = _compositeEvents[eventId];
    if (event == null) return;

    final updated = event.copyWith(
      layers: event.layers.map((l) => l.id == layer.id ? layer : l).toList(),
      modifiedAt: DateTime.now(),
    );
    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated); // Real-time sync
    notifyListeners();
  }

  /// Update layer in composite event (public, with undo)
  void updateEventLayer(String eventId, SlotEventLayer layer) {
    _pushUndoState();
    _updateEventLayerInternal(eventId, layer);
  }

  /// Toggle layer mute
  void toggleLayerMute(String eventId, String layerId) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();

    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(muted: !layer.muted));
  }

  /// Toggle layer solo
  void toggleLayerSolo(String eventId, String layerId) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();

    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(solo: !layer.solo));
  }

  /// Set layer volume (no undo - use for continuous slider updates)
  void setLayerVolumeContinuous(String eventId, String layerId, double volume) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(volume: volume.clamp(0.0, 1.0)));
  }

  /// Set layer volume (with undo - use for final value or discrete changes)
  void setLayerVolume(String eventId, String layerId, double volume) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();
    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(volume: volume.clamp(0.0, 1.0)));
  }

  /// Set layer pan (no undo - use for continuous slider updates)
  void setLayerPanContinuous(String eventId, String layerId, double pan) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(pan: pan.clamp(-1.0, 1.0)));
  }

  /// Set layer pan (with undo - use for final value)
  void setLayerPan(String eventId, String layerId, double pan) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();
    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(pan: pan.clamp(-1.0, 1.0)));
  }

  /// Set layer offset (no undo - use for continuous drag updates)
  void setLayerOffsetContinuous(String eventId, String layerId, double offsetMs) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(offsetMs: offsetMs.clamp(0, 10000)));
  }

  /// Set layer offset (with undo - use for final value)
  void setLayerOffset(String eventId, String layerId, double offsetMs) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();
    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(offsetMs: offsetMs.clamp(0, 10000)));
  }

  /// Set layer fade in/out times
  void setLayerFade(String eventId, String layerId, double fadeInMs, double fadeOutMs) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();
    final layer = event.layers.firstWhere((l) => l.id == layerId);
    _updateEventLayerInternal(eventId, layer.copyWith(
      fadeInMs: fadeInMs.clamp(0, 10000),
      fadeOutMs: fadeOutMs.clamp(0, 10000),
    ));
  }

  /// Reorder layers in event
  void reorderEventLayers(String eventId, int oldIndex, int newIndex) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();

    final layers = List<SlotEventLayer>.from(event.layers);
    if (oldIndex < newIndex) newIndex--;
    final layer = layers.removeAt(oldIndex);
    layers.insert(newIndex, layer);

    final updated = event.copyWith(
      layers: layers,
      modifiedAt: DateTime.now(),
    );
    _compositeEvents[eventId] = updated;
    _syncCompositeToMiddleware(updated); // Real-time sync
    notifyListeners();
  }

  /// Get composite event by ID
  SlotCompositeEvent? getCompositeEvent(String eventId) => _compositeEvents[eventId];

  /// Get events by category
  List<SlotCompositeEvent> getEventsByCategory(String category) =>
      _compositeEvents.values.where((e) => e.category == category).toList();

  /// Initialize default composite events from templates
  void initializeDefaultCompositeEvents() {
    if (_compositeEvents.isNotEmpty) return;

    for (final template in SlotEventTemplates.allTemplates()) {
      final id = 'event_${template.name.toLowerCase().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}';
      final event = template.copyWith(
        id: id,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );
      _compositeEvents[id] = event;
      _syncCompositeToMiddleware(event); // Real-time sync
    }
    _selectedCompositeEventId = _compositeEvents.keys.first;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REAL-TIME SYNC: SlotCompositeEvent ↔ MiddlewareEvent
  // ═══════════════════════════════════════════════════════════════════════════

  /// Convert composite event ID to middleware event ID
  String _compositeToMiddlewareId(String compositeId) => 'mw_$compositeId';

  /// Convert middleware event ID to composite event ID
  String? _middlewareToCompositeId(String middlewareId) {
    if (middlewareId.startsWith('mw_event_')) {
      return middlewareId.substring(3); // Remove 'mw_' prefix
    }
    return null;
  }

  /// Sync SlotCompositeEvent to MiddlewareEvent (real-time)
  void _syncCompositeToMiddleware(SlotCompositeEvent composite) {
    final middlewareId = _compositeToMiddlewareId(composite.id);

    // Generate MiddlewareActions from layers
    final actions = <MiddlewareAction>[];
    int actionIndex = 0;

    for (final layer in composite.layers) {
      // Skip muted layers, respect solo
      if (layer.muted) continue;
      if (composite.hasSoloedLayer && !layer.solo) continue;

      actions.add(MiddlewareAction(
        id: '${middlewareId}_action_${actionIndex++}',
        type: ActionType.play,
        assetId: layer.audioPath,
        bus: _getBusNameForCategory(composite.category),
        gain: layer.volume * composite.masterVolume,
        delay: layer.offsetMs / 1000.0, // Convert ms to seconds
        fadeTime: layer.fadeInMs / 1000.0,
        loop: composite.looping,
        priority: ActionPriority.normal,
      ));
    }

    // Create or update MiddlewareEvent
    final middlewareEvent = MiddlewareEvent(
      id: middlewareId,
      name: composite.name,
      category: 'Slot_${_capitalizeCategory(composite.category)}',
      actions: actions,
    );

    _events[middlewareId] = middlewareEvent;
    debugPrint('[Sync] Composite → Middleware: ${composite.name} (${actions.length} actions)');

    // Notify listeners of the change
    _notifyCompositeChange(composite.id, CompositeEventChangeType.updated);
  }

  /// Remove MiddlewareEvent when composite is deleted
  void _removeMiddlewareEventForComposite(String compositeId) {
    final middlewareId = _compositeToMiddlewareId(compositeId);
    _events.remove(middlewareId);
    debugPrint('[Sync] Removed middleware event: $middlewareId');

    // Notify listeners of deletion
    _notifyCompositeChange(compositeId, CompositeEventChangeType.deleted);
  }

  /// Sync MiddlewareEvent back to SlotCompositeEvent (bidirectional)
  void syncMiddlewareToComposite(String middlewareId) {
    final compositeId = _middlewareToCompositeId(middlewareId);
    if (compositeId == null) return;

    final middlewareEvent = _events[middlewareId];
    final composite = _compositeEvents[compositeId];
    if (middlewareEvent == null || composite == null) return;

    // Update composite from middleware changes
    // Note: This preserves layer structure, only updates playable properties
    final updatedLayers = <SlotEventLayer>[];

    for (int i = 0; i < composite.layers.length && i < middlewareEvent.actions.length; i++) {
      final action = middlewareEvent.actions[i];
      final layer = composite.layers[i];

      updatedLayers.add(layer.copyWith(
        volume: action.gain,
        offsetMs: action.delay * 1000.0,
        fadeInMs: action.fadeTime * 1000.0,
      ));
    }

    // Add any remaining layers that don't have corresponding actions
    if (composite.layers.length > middlewareEvent.actions.length) {
      updatedLayers.addAll(composite.layers.skip(middlewareEvent.actions.length));
    }

    _compositeEvents[compositeId] = composite.copyWith(
      name: middlewareEvent.name,
      layers: updatedLayers,
      modifiedAt: DateTime.now(),
    );

    debugPrint('[Sync] Middleware → Composite: ${middlewareEvent.name}');
    notifyListeners();
  }

  /// Get bus name for event category
  String _getBusNameForCategory(String category) {
    return switch (category.toLowerCase()) {
      'spin' => 'Reels',
      'reelstop' => 'Reels',
      'anticipation' => 'SFX',
      'win' => 'Wins',
      'bigwin' => 'Wins',
      'feature' => 'Music',
      'bonus' => 'Music',
      'ui' => 'UI',
      'ambient' => 'Ambience',
      'music' => 'Music',
      _ => 'SFX',
    };
  }

  /// Capitalize category for middleware naming
  String _capitalizeCategory(String category) {
    if (category.isEmpty) return 'General';
    return category[0].toUpperCase() + category.substring(1);
  }

  /// Check if a middleware event is linked to a composite event
  bool isLinkedToComposite(String middlewareId) {
    return middlewareId.startsWith('mw_event_');
  }

  /// Get composite event for a middleware event
  SlotCompositeEvent? getCompositeForMiddleware(String middlewareId) {
    final compositeId = _middlewareToCompositeId(middlewareId);
    if (compositeId == null) return null;
    return _compositeEvents[compositeId];
  }

  /// Expand composite event to timeline clips
  /// Returns list of clip data for each layer with absolute positions
  List<Map<String, dynamic>> expandEventToTimelineClips(
    String compositeEventId, {
    required double startPositionNormalized,
    required double timelineWidth,
  }) {
    final event = _compositeEvents[compositeEventId];
    if (event == null) return [];

    final clips = <Map<String, dynamic>>[];
    final totalDuration = event.totalDurationMs;
    if (totalDuration <= 0) return [];

    for (final layer in event.playableLayers) {
      final layerDuration = (layer.durationSeconds ?? 1.0) * 1000;
      final offsetRatio = layer.offsetMs / totalDuration;
      final durationRatio = layerDuration / totalDuration;

      // Calculate normalized positions on timeline
      final clipStart = startPositionNormalized + (offsetRatio * 0.2); // 0.2 = event block width
      final clipEnd = clipStart + (durationRatio * 0.2);

      clips.add({
        'layerId': layer.id,
        'name': layer.name,
        'path': layer.audioPath,
        'start': clipStart.clamp(0.0, 1.0),
        'end': clipEnd.clamp(0.0, 1.0),
        'volume': layer.volume,
        'pan': layer.pan,
        'offsetMs': layer.offsetMs,
        'durationSeconds': layer.durationSeconds,
        'waveformData': layer.waveformData,
        'eventId': compositeEventId,
        'eventName': event.name,
        'eventColor': event.color,
        'bus': _getBusNameForCategory(event.category),
      });
    }

    return clips;
  }

  // ===========================================================================
  // PROJECT SAVE/LOAD - Composite Events
  // ===========================================================================

  /// Export all composite events to JSON
  Map<String, dynamic> exportCompositeEventsToJson() {
    return {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'compositeEvents': _compositeEvents.values.map((e) => e.toJson()).toList(),
    };
  }

  /// Import composite events from JSON
  void importCompositeEventsFromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;
    if (version != 1) {
      debugPrint('[Middleware] Warning: Unknown composite events version: $version');
    }

    final events = json['compositeEvents'] as List<dynamic>?;
    if (events == null) return;

    _compositeEvents.clear();
    for (final eventJson in events) {
      final event = SlotCompositeEvent.fromJson(eventJson as Map<String, dynamic>);
      _compositeEvents[event.id] = event;
      _syncCompositeToMiddleware(event);
    }

    debugPrint('[Middleware] Imported ${_compositeEvents.length} composite events');
    notifyListeners();
  }

  /// Get all composite events as JSON string
  String exportCompositeEventsToJsonString() {
    final json = exportCompositeEventsToJson();
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  /// Import composite events from JSON string
  void importCompositeEventsFromJsonString(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      importCompositeEventsFromJson(json);
    } catch (e) {
      debugPrint('[Middleware] Failed to import composite events: $e');
    }
  }

  /// Clear all composite events
  void clearAllCompositeEvents() {
    for (final event in _compositeEvents.values) {
      _removeMiddlewareEventForComposite(event.id);
    }
    _compositeEvents.clear();
    notifyListeners();
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
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();
    _compositeEvents[eventId] = event.copyWith(
      triggerStages: stages,
      modifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Add a trigger stage to a composite event
  void addTriggerStage(String eventId, String stageType) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    if (event.triggerStages.contains(stageType)) return;
    _pushUndoState();
    _compositeEvents[eventId] = event.copyWith(
      triggerStages: [...event.triggerStages, stageType],
      modifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Remove a trigger stage from a composite event
  void removeTriggerStage(String eventId, String stageType) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    if (!event.triggerStages.contains(stageType)) return;
    _pushUndoState();
    _compositeEvents[eventId] = event.copyWith(
      triggerStages: event.triggerStages.where((s) => s != stageType).toList(),
      modifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Set trigger conditions for a composite event
  void setTriggerConditions(String eventId, Map<String, String> conditions) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();
    _compositeEvents[eventId] = event.copyWith(
      triggerConditions: conditions,
      modifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Add a trigger condition
  void addTriggerCondition(String eventId, String rtpcName, String condition) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    _pushUndoState();
    final newConditions = Map<String, String>.from(event.triggerConditions);
    newConditions[rtpcName] = condition;
    _compositeEvents[eventId] = event.copyWith(
      triggerConditions: newConditions,
      modifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Remove a trigger condition
  void removeTriggerCondition(String eventId, String rtpcName) {
    final event = _compositeEvents[eventId];
    if (event == null) return;
    if (!event.triggerConditions.containsKey(rtpcName)) return;
    _pushUndoState();
    final newConditions = Map<String, String>.from(event.triggerConditions);
    newConditions.remove(rtpcName);
    _compositeEvents[eventId] = event.copyWith(
      triggerConditions: newConditions,
      modifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Find all composite events that should trigger for a given stage type
  List<SlotCompositeEvent> getEventsForStage(String stageType) {
    return _compositeEvents.values
        .where((e) => e.triggerStages.contains(stageType))
        .toList();
  }

  /// Find all composite events that match stage + conditions
  List<SlotCompositeEvent> getEventsForStageWithConditions(
    String stageType,
    Map<String, double> rtpcValues,
  ) {
    return _compositeEvents.values.where((e) {
      // Must have this stage as trigger
      if (!e.triggerStages.contains(stageType)) return false;

      // Check all conditions
      for (final entry in e.triggerConditions.entries) {
        final rtpcName = entry.key;
        final condition = entry.value;
        final value = rtpcValues[rtpcName];
        if (value == null) return false;

        // Parse condition (e.g., ">= 10", "< 5", "== 1")
        if (!_evaluateCondition(value, condition)) return false;
      }

      return true;
    }).toList();
  }

  /// Evaluate a condition string against a value
  bool _evaluateCondition(double value, String condition) {
    final parts = condition.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return false;

    final op = parts[0];
    final target = double.tryParse(parts[1]);
    if (target == null) return false;

    return switch (op) {
      '>=' => value >= target,
      '>' => value > target,
      '<=' => value <= target,
      '<' => value < target,
      '==' => (value - target).abs() < 0.001,
      '!=' => (value - target).abs() >= 0.001,
      _ => false,
    };
  }

  /// Get all stages that have at least one event mapped
  List<String> get mappedStages {
    final stages = <String>{};
    for (final event in _compositeEvents.values) {
      stages.addAll(event.triggerStages);
    }
    return stages.toList()..sort();
  }

  /// Get event count per stage (for visualization)
  Map<String, int> get stageEventCounts {
    final counts = <String, int>{};
    for (final event in _compositeEvents.values) {
      for (final stage in event.triggerStages) {
        counts[stage] = (counts[stage] ?? 0) + 1;
      }
    }
    return counts;
  }
}
