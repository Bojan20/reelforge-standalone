// Middleware Provider
//
// State management for Wwise/FMOD-style middleware system:
// - State Groups (global states affecting sound)
// - Switch Groups (per-object sound variants)
// - RTPC (Real-Time Parameter Control)
//
// Connects Dart UI to Rust rf-event system via FFI.

import 'package:flutter/foundation.dart';
import '../models/middleware_models.dart';
import '../src/rust/native_ffi.dart';

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

  // Music system state
  int? _currentMusicSegmentId;
  int? _nextMusicSegmentId;
  int _musicBusId = 1; // Music bus

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
  void unregisterStateGroup(int groupId) {
    _stateGroups.remove(groupId);
    // TODO: Notify Rust to unregister
    notifyListeners();
  }

  /// Unregister a switch group
  void unregisterSwitchGroup(int groupId) {
    _switchGroups.remove(groupId);
    // Remove from all objects
    for (final objectSwitches in _objectSwitches.values) {
      objectSwitches.remove(groupId);
    }
    // TODO: Notify Rust to unregister
    notifyListeners();
  }

  /// Unregister an RTPC
  void unregisterRtpc(int rtpcId) {
    _rtpcDefs.remove(rtpcId);
    // Remove from all objects
    for (final objectRtpcs in _objectRtpcs.values) {
      objectRtpcs.remove(rtpcId);
    }
    // Remove bindings that use this RTPC
    _rtpcBindings.removeWhere((_, binding) => binding.rtpcId == rtpcId);
    // TODO: Notify Rust to unregister
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

    notifyListeners();
  }

  /// Remove a ducking rule
  void removeDuckingRule(int ruleId) {
    _duckingRules.remove(ruleId);
    _ffi.middlewareRemoveDuckingRule(ruleId);
    notifyListeners();
  }

  /// Enable/disable a ducking rule
  void setDuckingRuleEnabled(int ruleId, bool enabled) {
    final rule = _duckingRules[ruleId];
    if (rule == null) return;

    _duckingRules[ruleId] = rule.copyWith(enabled: enabled);
    _ffi.middlewareSetDuckingRuleEnabled(ruleId, enabled);
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
}
