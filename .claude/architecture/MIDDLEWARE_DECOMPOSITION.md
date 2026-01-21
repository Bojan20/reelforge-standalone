# MiddlewareProvider Decomposition (P0.2)

**Date:** 2026-01-21
**Status:** Phase 1 Complete, Phase 2 Complete, Phase 3 Complete (Containers)
**Original Size:** ~5200 LOC
**Target:** ~400 LOC orchestrator + ~4800 LOC in subsystem providers

---

## Problem Statement

MiddlewareProvider was a "God Object" managing 17+ subsystems:
- State Groups, Switch Groups, RTPC
- Ducking, Blend, Random, Sequence containers
- Music System, Attenuation Curves
- VoicePool, BusHierarchy, AuxSendManager
- Memory Manager, Event Profiler, Auto Spatial
- Composite Events, Slot Mode State

**Issues:**
- 5200+ LOC in single file
- Tight coupling between unrelated subsystems
- Impossible to test in isolation
- Hard to maintain and understand

---

## Architecture

### Before (Monolith)

```
┌─────────────────────────────────────────────────────────────────┐
│ MiddlewareProvider (5200 LOC)                                   │
│ ├── _stateGroups, _switchGroups, _objectSwitches               │
│ ├── _rtpcDefs, _objectRtpcs, _rtpcBindings                     │
│ ├── _duckingRules, _blendContainers, _randomContainers         │
│ ├── _sequenceContainers, _musicSegments, _stingers             │
│ ├── _attenuationCurves, _voicePool, _busHierarchy              │
│ ├── _auxSendManager, _memoryManager, _eventProfiler            │
│ ├── _compositeEvents, _slotTracks, _slotMarkers                │
│ └── 200+ methods                                                │
└─────────────────────────────────────────────────────────────────┘
```

### After (Decomposed)

```
┌─────────────────────────────────────────────────────────────────┐
│ MiddlewareProvider (~400 LOC) — ORCHESTRATOR                    │
│ ├── Subsystem provider references                               │
│ ├── Listener forwarding (notifyListeners)                       │
│ ├── Delegation methods (thin wrappers)                          │
│ └── Cross-subsystem coordination                                │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│ StateGroups   │   │ SwitchGroups  │   │ RtpcSystem    │   │ DuckingSystem │
│ Provider      │   │ Provider      │   │ Provider      │   │ Provider      │
│ (~185 LOC)    │   │ (~210 LOC)    │   │ (~350 LOC)    │   │ (~190 LOC)    │
│ ✅ DONE       │   │ ✅ DONE       │   │ ✅ DONE       │   │ ✅ DONE       │
└───────────────┘   └───────────────┘   └───────────────┘   └───────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              ▼
                    ┌───────────────────┐
                    │ GetIt ServiceLocator │
                    │ (sl<Provider>)       │
                    └───────────────────────┘
```

---

## Phase 1 — ✅ COMPLETED

### StateGroupsProvider

**File:** `flutter_ui/lib/providers/subsystems/state_groups_provider.dart`
**LOC:** ~185

**Responsibilities:**
- Global state group management (Wwise/FMOD-style)
- State registration and changes
- FFI sync with Rust engine
- JSON serialization

**Key Methods:**
```dart
// Registration
registerStateGroupFromPreset(String name, List<String> stateNames)
registerStateGroup(StateGroup group)
unregisterStateGroup(int groupId)

// State changes
setState(int groupId, int stateId)
setStateByName(int groupId, String stateName)
resetState(int groupId)
resetAllStates()

// Queries
StateGroup? getStateGroup(int groupId)
StateGroup? getStateGroupByName(String name)
int? getCurrentState(int groupId)

// Serialization
List<Map<String, dynamic>> toJson()
void fromJson(List<dynamic> json)
void clear()
```

### SwitchGroupsProvider

**File:** `flutter_ui/lib/providers/subsystems/switch_groups_provider.dart`
**LOC:** ~210

**Responsibilities:**
- Per-object switch management
- Switch group registration
- Object switch tracking
- FFI sync with Rust engine

**Key Methods:**
```dart
// Registration
registerSwitchGroup(SwitchGroup group)
registerSwitchGroupFromPreset(String name, List<String> switchNames)
unregisterSwitchGroup(int groupId)

// Switch changes (per-object)
setSwitch(int gameObjectId, int groupId, int switchId)
setSwitchByName(int gameObjectId, int groupId, String switchName)
resetSwitch(int gameObjectId, int groupId)
clearObjectSwitches(int gameObjectId)
resetAllSwitches()

// Queries
SwitchGroup? getSwitchGroup(int groupId)
SwitchGroup? getSwitchGroupByName(String name)
int? getSwitch(int gameObjectId, int groupId)
Map<int, int>? getObjectSwitches(int gameObjectId)
int get objectSwitchesCount

// Serialization
List<Map<String, dynamic>> toJson()
Map<String, dynamic> objectSwitchesToJson()
void fromJson(List<dynamic> json)
void objectSwitchesFromJson(Map<String, dynamic> json)
void clear()
```

### Service Locator Registration

**File:** `flutter_ui/lib/services/service_locator.dart`

```dart
// LAYER 5: Middleware subsystem providers
sl.registerLazySingleton<StateGroupsProvider>(
  () => StateGroupsProvider(ffi: sl<NativeFFI>()),
);
sl.registerLazySingleton<SwitchGroupsProvider>(
  () => SwitchGroupsProvider(ffi: sl<NativeFFI>()),
);
```

### MiddlewareProvider Integration

```dart
class MiddlewareProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // Subsystem providers (from GetIt)
  late final StateGroupsProvider _stateGroupsProvider;
  late final SwitchGroupsProvider _switchGroupsProvider;

  MiddlewareProvider(this._ffi) {
    // Initialize from GetIt
    _stateGroupsProvider = sl<StateGroupsProvider>();
    _switchGroupsProvider = sl<SwitchGroupsProvider>();

    // Forward notifications
    _stateGroupsProvider.addListener(notifyListeners);
    _switchGroupsProvider.addListener(notifyListeners);

    _initializeDefaults();
    _initializeServices();
  }

  // Delegation methods
  List<StateGroup> get stateGroups =>
      _stateGroupsProvider.stateGroups.values.toList();

  void registerStateGroup(StateGroup group) =>
      _stateGroupsProvider.registerStateGroup(group);

  void setState(int groupId, int stateId) =>
      _stateGroupsProvider.setState(groupId, stateId);

  // ... etc
}
```

---

## Phase 2 — ✅ COMPLETED

### RtpcSystemProvider

**File:** `flutter_ui/lib/providers/subsystems/rtpc_system_provider.dart`
**LOC:** ~350

**Responsibilities:**
- RTPC definition registration and management
- Per-object RTPC value control
- RTPC binding creation (RTPC → target parameter)
- Curve evaluation for non-linear mappings
- FFI sync with Rust engine
- JSON serialization

**Key Methods:**
```dart
// Registration
void registerRtpc(RtpcDefinition rtpc)
void unregisterRtpc(int rtpcId)

// Value control
void setRtpc(int rtpcId, double value, {int interpolationMs = 0})
void setObjectRtpc(int gameObjectId, int rtpcId, double value)
double? getRtpc(int rtpcId)
double? getObjectRtpc(int gameObjectId, int rtpcId)

// Curves
void setRtpcCurve(int rtpcId, List<Point<double>> curvePoints)

// Bindings
RtpcBinding createBinding(int rtpcId, RtpcTargetParameter target, {...})
void removeBinding(int bindingId)
Map<(RtpcTargetParameter, int?), double> evaluateAllBindings()

// Serialization
List<Map<String, dynamic>> rtpcDefsToJson()
void rtpcDefsFromJson(List<dynamic> json)
void clear()
```

### DuckingSystemProvider

**File:** `flutter_ui/lib/providers/subsystems/ducking_system_provider.dart`
**LOC:** ~190

**Responsibilities:**
- Ducking rule management (source→target bus matrix)
- FFI sync with Rust engine
- DuckingService sync for Dart-side ducking
- JSON serialization

**Key Methods:**
```dart
// Rules
DuckingRule addRule({...})
void registerRule(DuckingRule rule)
void updateRule(int ruleId, DuckingRule rule)
void removeRule(int ruleId)
void setRuleEnabled(int ruleId, bool enabled)

// Queries
DuckingRule? getRule(int ruleId)
List<DuckingRule> getRulesForSourceBus(int sourceBusId)
List<DuckingRule> getRulesForTargetBus(int targetBusId)

// Serialization
List<Map<String, dynamic>> toJson()
void fromJson(List<dynamic> json)
void clear()
```

### Service Locator Registration (Phase 2)

```dart
sl.registerLazySingleton<RtpcSystemProvider>(
  () => RtpcSystemProvider(ffi: sl<NativeFFI>()),
);
sl.registerLazySingleton<DuckingSystemProvider>(
  () => DuckingSystemProvider(ffi: sl<NativeFFI>()),
);
```

### MiddlewareProvider Integration (Phase 2)

```dart
// Added provider fields
late final RtpcSystemProvider _rtpcSystemProvider;
late final DuckingSystemProvider _duckingSystemProvider;

// In constructor
_rtpcSystemProvider = sl<RtpcSystemProvider>();
_duckingSystemProvider = sl<DuckingSystemProvider>();
_rtpcSystemProvider.addListener(notifyListeners);
_duckingSystemProvider.addListener(notifyListeners);

// Delegation examples
List<RtpcDefinition> get rtpcDefinitions => _rtpcSystemProvider.rtpcDefinitions;
void registerRtpc(RtpcDefinition rtpc) => _rtpcSystemProvider.registerRtpc(rtpc);
DuckingRule addDuckingRule({...}) => _duckingSystemProvider.addRule(...);
```

---

## Phase 3 — ✅ COMPLETED

### BlendContainersProvider

**File:** `flutter_ui/lib/providers/subsystems/blend_containers_provider.dart`
**LOC:** ~350

**Responsibilities:**
- RTPC-based crossfade between sounds
- Container creation and management
- Range slider mappings
- Curve visualization data

**Key Methods:**
```dart
void add(BlendContainer container)
void update(String id, BlendContainer container)
void remove(String id)
BlendContainer? get(String id)
List<BlendContainer> get containers
```

### RandomContainersProvider

**File:** `flutter_ui/lib/providers/subsystems/random_containers_provider.dart`
**LOC:** ~300

**Responsibilities:**
- Weighted random selection (Random/Shuffle/Round Robin modes)
- Container management with weight editing
- Pitch/volume variation parameters
- Play history tracking

**Key Methods:**
```dart
void add(RandomContainer container)
void update(String id, RandomContainer container)
void remove(String id)
void setMode(String id, RandomMode mode)
void setItemWeight(String containerId, String itemId, double weight)
```

### SequenceContainersProvider

**File:** `flutter_ui/lib/providers/subsystems/sequence_containers_provider.dart`
**LOC:** ~400

**Responsibilities:**
- Timed sound sequences (timeline-based)
- Step editor with loop/hold/ping-pong modes
- Trigger timing per step
- Playback state management

**Key Methods:**
```dart
void add(SequenceContainer container)
void update(String id, SequenceContainer container)
void remove(String id)
void setLoopMode(String id, LoopMode mode)
void addStep(String id, SequenceStep step)
void removeStep(String id, int index)
```

### Service Locator Registration (Phase 3)

```dart
sl.registerLazySingleton<BlendContainersProvider>(
  () => BlendContainersProvider(ffi: sl<NativeFFI>()),
);
sl.registerLazySingleton<RandomContainersProvider>(
  () => RandomContainersProvider(ffi: sl<NativeFFI>()),
);
sl.registerLazySingleton<SequenceContainersProvider>(
  () => SequenceContainersProvider(ffi: sl<NativeFFI>()),
);
```

### MiddlewareProvider Integration (Phase 3)

```dart
// Added provider fields
late final BlendContainersProvider _blendContainersProvider;
late final RandomContainersProvider _randomContainersProvider;
late final SequenceContainersProvider _sequenceContainersProvider;

// In constructor
_blendContainersProvider = sl<BlendContainersProvider>();
_randomContainersProvider = sl<RandomContainersProvider>();
_sequenceContainersProvider = sl<SequenceContainersProvider>();
_blendContainersProvider.addListener(notifyListeners);
_randomContainersProvider.addListener(notifyListeners);
_sequenceContainersProvider.addListener(notifyListeners);

// Delegation examples
List<BlendContainer> get blendContainers => _blendContainersProvider.containers;
List<RandomContainer> get randomContainers => _randomContainersProvider.containers;
List<SequenceContainer> get sequenceContainers => _sequenceContainersProvider.containers;
```

---

## Phase 4 — PENDING (Future)

### Remaining Extractions

| Subsystem | Est. LOC | Priority | Dependencies |
|-----------|----------|----------|--------------|
| **MusicSystemProvider** | ~500 | P2 | NativeFFI |
| **AttenuationCurveProvider** | ~250 | P2 | NativeFFI |

---

## Benefits

| Metric | Before | After Phase 1 | After Phase 2 | After Phase 3 | After Full |
|--------|--------|---------------|---------------|---------------|------------|
| Main file LOC | 5200 | ~4800 | ~4250 | ~3200 | ~400 |
| Subsystem files | 0 | 2 | 4 | 7 | 9+ |
| Testability | Poor | Better | Good | Very Good | Excellent |
| Cognitive load | High | Medium | Medium-Low | Low | Minimal |

---

## Testing Strategy

Each subsystem provider can be tested in isolation:

```dart
// Unit test example
test('StateGroupsProvider sets state correctly', () {
  final mockFfi = MockNativeFFI();
  final provider = StateGroupsProvider(ffi: mockFfi);

  provider.registerStateGroupFromPreset('GameState', ['Playing', 'Paused']);
  provider.setState(100, 1);

  expect(provider.getCurrentState(100), 1);
  verify(mockFfi.middlewareSetState(100, 1)).called(1);
});
```

---

**Last Updated:** 2026-01-21
