# MiddlewareProvider Decomposition (P0.2)

**Date:** 2026-01-23
**Status:** Phase 1-7 Complete (StateGroups, SwitchGroups, RTPC, Ducking, Containers, Events, Bus Routing, VoicePool, AttenuationCurves, MemoryManager, EventProfiler)
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

## Phase 4 — ✅ COMPLETED

### EventSystemProvider

**File:** `flutter_ui/lib/providers/subsystems/event_system_provider.dart`
**LOC:** ~330

**Responsibilities:**
- MiddlewareEvent CRUD operations
- FFI sync with Rust engine
- Event metadata management

### CompositeEventSystemProvider

**File:** `flutter_ui/lib/providers/subsystems/composite_event_system_provider.dart`
**LOC:** ~1280

**Responsibilities:**
- SlotCompositeEvent CRUD operations
- Undo/redo support
- Layer operations (add, remove, reorder)
- Stage trigger mapping

---

## Phase 5 — ✅ COMPLETED

### BusHierarchyProvider

**File:** `flutter_ui/lib/providers/subsystems/bus_hierarchy_provider.dart`
**LOC:** ~360

**Responsibilities:**
- Audio bus hierarchy (Wwise/FMOD-style routing)
- Master bus with child groups (Music, SFX, Voice, UI)
- Sub-buses for granular control
- Effect insert slots per bus
- Volume propagation through parent chain

**Key Methods:**
```dart
// Getters
AudioBus? getBus(int busId)
List<AudioBus> get allBuses
AudioBus get master
AudioBus? getBusByName(String name)

// Hierarchy traversal
List<AudioBus> getDescendants(int busId)
List<AudioBus> getParentChain(int busId)
double getEffectiveVolume(int busId)

// Bus management
void addBus(AudioBus bus)
AudioBus createBus({required String name, int? parentBusId})
void removeBus(int busId)

// Bus parameters
void setBusVolume(int busId, double volume)
void toggleBusMute(int busId)
void toggleBusSolo(int busId)
void setBusPan(int busId, double pan)

// Effect slots
void addBusPreInsert(int busId, EffectSlot effect)
void addBusPostInsert(int busId, EffectSlot effect)
void removeBusEffect(int busId, int slotIndex, bool isPreInsert)
void toggleBusEffectBypass(int busId, int slotIndex, bool isPreInsert)
void setBusEffectParam(int busId, int slotIndex, bool isPreInsert, String param, double value)

// Serialization
Map<String, dynamic> toJson()
void fromJson(Map<String, dynamic> json)
```

### AuxSendProvider

**File:** `flutter_ui/lib/providers/subsystems/aux_send_provider.dart`
**LOC:** ~390

**Responsibilities:**
- Aux send/return routing (Wwise/FMOD-style effects buses)
- Default aux buses: Reverb A (short/room), Reverb B (large/hall), Delay (rhythmic), Slapback
- Send routing from source buses to aux buses
- Pre/Post fader send positioning
- Effect parameters per aux bus

**Key Methods:**
```dart
// Getters
List<AuxBus> get allAuxBuses
List<AuxSend> get allSends
AuxBus? getAuxBus(int auxBusId)
AuxSend? getSend(int sendId)
AuxBus? getAuxBusByName(String name)

// Send queries
List<AuxSend> getSendsFromBus(int sourceBusId)
List<AuxSend> getSendsToAux(int auxBusId)
bool sendExists(int sourceBusId, int auxBusId)

// Send management
AuxSend createSend({required int sourceBusId, required int auxBusId, ...})
void setSendLevel(int sendId, double level)
void toggleSendEnabled(int sendId)
void setSendPosition(int sendId, SendPosition position)
void removeSend(int sendId)

// Aux bus management
AuxBus addAuxBus({required String name, required EffectType effectType, ...})
void removeAuxBus(int auxBusId)
void setAuxReturnLevel(int auxBusId, double level)
void toggleAuxMute(int auxBusId)
void toggleAuxSolo(int auxBusId)
void setAuxEffectParam(int auxBusId, String param, double value)

// Calculations
double calculateAuxInput(int auxBusId, Map<int, double> busLevels)
Map<int, double> calculateAllAuxOutputs(Map<int, double> busLevels)

// Serialization
Map<String, dynamic> toJson()
void fromJson(Map<String, dynamic> json)
```

### Service Locator Registration (Phase 5)

```dart
sl.registerLazySingleton<BusHierarchyProvider>(
  () => BusHierarchyProvider(ffi: sl<NativeFFI>()),
);
sl.registerLazySingleton<AuxSendProvider>(
  () => AuxSendProvider(ffi: sl<NativeFFI>()),
);
```

### MiddlewareProvider Integration (Phase 5)

```dart
// Added provider fields
late final BusHierarchyProvider _busHierarchyProvider;
late final AuxSendProvider _auxSendProvider;

// In constructor
_busHierarchyProvider = sl<BusHierarchyProvider>();
_auxSendProvider = sl<AuxSendProvider>();
_busHierarchyProvider.addListener(_onBusHierarchyChanged);
_auxSendProvider.addListener(_onAuxSendChanged);

// Delegation examples
BusHierarchyProvider get busHierarchyProvider => _busHierarchyProvider;
AuxSendProvider get auxSendProvider => _auxSendProvider;
List<AuxBus> get allAuxBuses => _auxSendProvider.allAuxBuses;
```

---

## Phase 6 — ✅ COMPLETED

### VoicePoolProvider

**File:** `flutter_ui/lib/providers/subsystems/voice_pool_provider.dart`
**LOC:** ~255

**Responsibilities:**
- Voice polyphony management with priority-based stealing
- Virtual voice tracking (inaudible voices)
- Voice parameter updates (volume, pitch, pan)
- Pool statistics for monitoring

**Note:** This is a Dart-only voice tracking system. Actual audio playback
is handled by AudioPlaybackService which communicates with the Rust engine.

**Key Methods:**
```dart
// Getters
VoicePoolConfig get config
int get activeCount
int get virtualCount
int get availableSlots
Iterable<int> get activeVoiceIds
int get peakVoices
int get stealCount

// Voice allocation
int? requestVoice({soundId, busId, priority, volume, pitch, pan, spatialDistance})
void releaseVoice(int voiceId)
void releaseAllVoices()

// Voice parameters
void setVoiceVolume(int voiceId, double volume)
void setVoicePitch(int voiceId, double pitch)
void setVoicePan(int voiceId, double pan)
void updateVoice(int voiceId, {volume, pitch, pan, spatialDistance})
ActiveVoice? getVoice(int voiceId)

// Configuration
void updateConfig(VoicePoolConfig config)
void setMaxVoices(int maxVoices)
void setStealingMode(VoiceStealingMode mode)

// Statistics
VoicePoolStats getStats()
void resetStats()

// Serialization
Map<String, dynamic> toJson()
void fromJson(Map<String, dynamic> json)
void clear()
```

### AttenuationCurveProvider

**File:** `flutter_ui/lib/providers/subsystems/attenuation_curve_provider.dart`
**LOC:** ~300

**Responsibilities:**
- Slot-specific attenuation curves (Win Amount, Near Win, Combo Multiplier, Feature Progress)
- Custom curve evaluation with various shapes
- FFI sync with Rust engine
- Factory methods for standard curve types

**Key Methods:**
```dart
// Getters
List<AttenuationCurve> get curves
int get curveCount
AttenuationCurve? getCurve(int curveId)
List<AttenuationCurve> getCurvesByType(AttenuationType type)

// Curve management
AttenuationCurve addCurve({name, type, inputMin, inputMax, outputMin, outputMax, curveShape})
void updateCurve(int curveId, AttenuationCurve curve)
void removeCurve(int curveId)
void setCurveEnabled(int curveId, bool enabled)

// Evaluation
double evaluateCurve(int curveId, double input)

// Factory methods (standard curves)
AttenuationCurve createWinAmountCurve({name, inputMax})
AttenuationCurve createNearWinCurve({name})
AttenuationCurve createComboMultiplierCurve({name, inputMax})
AttenuationCurve createFeatureProgressCurve({name})

// Serialization
Map<String, dynamic> toJson()
void fromJson(Map<String, dynamic> json)
void clear()
```

### Service Locator Registration (Phase 6)

```dart
sl.registerLazySingleton<VoicePoolProvider>(
  () => VoicePoolProvider(),  // No FFI dependency - pure Dart voice tracking
);
sl.registerLazySingleton<AttenuationCurveProvider>(
  () => AttenuationCurveProvider(ffi: sl<NativeFFI>()),
);
```

### MiddlewareProvider Integration (Phase 6)

```dart
// Added provider fields
late final VoicePoolProvider _voicePoolProvider;
late final AttenuationCurveProvider _attenuationCurveProvider;

// In constructor
_voicePoolProvider = sl<VoicePoolProvider>();
_attenuationCurveProvider = sl<AttenuationCurveProvider>();
_voicePoolProvider.addListener(_onVoicePoolChanged);
_attenuationCurveProvider.addListener(_onAttenuationCurveChanged);

// Delegation examples
VoicePoolProvider get voicePoolProvider => _voicePoolProvider;
List<AttenuationCurve> get attenuationCurves => _attenuationCurveProvider.curves;
VoicePoolStats getVoicePoolStats() => _voicePoolProvider.getStats();
```

---

## Phase 7 — ✅ COMPLETED

### MemoryManagerProvider

**File:** `flutter_ui/lib/providers/subsystems/memory_manager_provider.dart`
**LOC:** ~240

**Responsibilities:**
- Soundbank registration and management
- Memory budget tracking and enforcement
- LRU-based bank unloading
- Batch operations (load/unload all)
- Memory statistics

**Key Methods:**
```dart
void registerSoundbank(SoundBank bank)
bool loadSoundbank(String bankId)
bool unloadSoundbank(String bankId)
void loadAllSoundbanks()
void unloadAllSoundbanks()
MemoryStats getStats()
```

### EventProfilerProvider

**File:** `flutter_ui/lib/providers/subsystems/event_profiler_provider.dart`
**LOC:** ~280

**Responsibilities:**
- Audio event recording and tracking
- Latency measurement (avg, max, percentiles)
- Voice statistics (starts, stops, steals)
- Event export for analysis
- Convenience recording methods

**Key Methods:**
```dart
void record({type, description, soundId, busId, voiceId, value, latencyUs})
ProfilerStats getStats()
List<ProfilerEvent> getRecentEvents({int count = 100})
Map<String, double> getLatencyPercentiles({int count = 1000})
Map<String, dynamic> exportReportToJson({int eventCount = 1000})
void clear()
```

---

## All Extractions Complete

| Subsystem | LOC | Phase | Status |
|-----------|-----|-------|--------|
| StateGroupsProvider | ~185 | 1 | ✅ |
| SwitchGroupsProvider | ~210 | 1 | ✅ |
| RtpcSystemProvider | ~350 | 2 | ✅ |
| DuckingSystemProvider | ~190 | 2 | ✅ |
| BlendContainersProvider | ~280 | 3 | ✅ |
| RandomContainersProvider | ~260 | 3 | ✅ |
| SequenceContainersProvider | ~270 | 3 | ✅ |
| MusicSystemProvider | ~400 | 4 | ✅ |
| EventSystemProvider | ~330 | 4 | ✅ |
| CompositeEventSystemProvider | ~1280 | 4 | ✅ |
| BusHierarchyProvider | ~360 | 5 | ✅ |
| AuxSendProvider | ~300 | 5 | ✅ |
| VoicePoolProvider | ~255 | 6 | ✅ |
| AttenuationCurveProvider | ~300 | 6 | ✅ |
| **MemoryManagerProvider** | ~240 | 7 | ✅ |
| **EventProfilerProvider** | ~280 | 7 | ✅ |

**Total Subsystem LOC:** ~5,490 LOC across 16 providers

---

## Benefits

| Metric | Before | After Phase 1-6 | After Phase 7 |
|--------|--------|-----------------|---------------|
| Main file LOC | 5200 | ~2100 | ~1900 |
| Subsystem files | 0 | 14 | 16 |
| Testability | Poor | Excellent | Excellent |
| Cognitive load | High | Very Low | Very Low |

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

**Last Updated:** 2026-01-23 (Phase 7 Complete)
