# MiddlewareProvider Decomposition (P0.2)

**Date:** 2026-01-21
**Status:** Phase 1 Complete, Phase 2 Complete (RTPC + Ducking)
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

## Phase 3 — PENDING

### Planned Extractions

| Subsystem | Est. LOC | Priority | Dependencies |
|-----------|----------|----------|--------------|
| **BlendContainerProvider** | ~350 | P1 | ContainerService |
| **RandomContainerProvider** | ~300 | P1 | ContainerService |
| **SequenceContainerProvider** | ~400 | P1 | ContainerService |
| **MusicSystemProvider** | ~500 | P1 | NativeFFI |
| **AttenuationCurveProvider** | ~250 | P2 | NativeFFI |

### Extraction Pattern

1. **Identify boundaries** — Which fields/methods belong together?
2. **Create provider** — New ChangeNotifier in `providers/subsystems/`
3. **Move code** — Fields, methods, serialization
4. **Register in GetIt** — Add to service_locator.dart
5. **Update orchestrator** — Add delegation in MiddlewareProvider
6. **Test** — flutter analyze + manual verification

---

## Benefits

| Metric | Before | After Phase 1 | After Phase 2 | After Full |
|--------|--------|---------------|---------------|------------|
| Main file LOC | 5200 | ~4800 | ~4250 | ~400 |
| Subsystem files | 0 | 2 | 4 | 9+ |
| Testability | Poor | Better | Good | Excellent |
| Cognitive load | High | Medium | Medium-Low | Low |

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
