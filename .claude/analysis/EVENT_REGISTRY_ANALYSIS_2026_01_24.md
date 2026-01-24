# EventRegistry Ultra-Detailed Analysis

**Datum:** 2026-01-24
**Fajl:** `flutter_ui/lib/services/event_registry.dart`
**LOC:** ~1645 (after P1 fixes)
**Status:** ✅ ANALYSIS + P1 IMPLEMENTATION COMPLETE

## P1 Implementation Summary (2026-01-24)

| Fix | Description | Lines Added |
|-----|-------------|-------------|
| P1.1 | Path validation (security) | ~35 |
| P1.2 | Voice limit per event | ~20 |
| P1.3 | Instance cleanup timer | ~40 |
| P1.4 | Trigger history for UI | ~55 |
| **Total** | | **~150 LOC** |

**Verified:** `flutter analyze` — No errors

---

## Executive Summary

EventRegistry je **centralni hub** za sav SlotLab/Middleware audio. Mapira stage events na AudioEvent definicije i orkestrira playback kroz Rust engine.

### Arhitektura

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           EXTERNAL TRIGGERS                                  │
│  SlotLabProvider.spin() → stages[]  |  MiddlewareProvider.postEvent()       │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           EVENT REGISTRY                                     │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ INPUT VALIDATION (line 807-824)                                         ││
│  │ - Empty check, length limit (128), alphanumeric only                    ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ STAGE LOOKUP (line 826-854)                                             ││
│  │ 1. Exact match in _stageToEvent                                         ││
│  │ 2. Normalized (UPPERCASE) match                                         ││
│  │ 3. Case-insensitive search                                              ││
│  │ 4. Fallback pattern (REEL_STOP_0 → REEL_STOP)                          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ CONTAINER CHECK (line 905-909)                                          ││
│  │ if (event.usesContainer) → _triggerViaContainer()                       ││
│  │   └─→ ContainerService.triggerBlend/Random/Sequence()                   ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ LAYER PLAYBACK (line 955-964)                                           ││
│  │ for (layer in event.layers) → _playLayer()                              ││
│  │   ├─→ Delay handling (line 1088-1091)                                   ││
│  │   ├─→ RTPC modulation (line 1102-1104)                                  ││
│  │   ├─→ Spatial positioning (line 1117-1147)                              ││
│  │   ├─→ Ducking notification (line 1150)                                  ││
│  │   └─→ Audio routing decision (line 1174-1212)                           ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ AUDIO ROUTING (line 1174-1212)                                          ││
│  │ switch (source, usePool, loop):                                         ││
│  │   Browser    → previewFile()         (isolated preview)                 ││
│  │   Pool       → AudioPool.acquire()   (rapid-fire)                       ││
│  │   Loop       → playLoopingToBus()    (REEL_SPIN seamless)              ││
│  │   Standard   → playFileToBus()       (one-shot via Rust)               ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        RUST PLAYBACK ENGINE (FFI)                            │
│  NativeFFI.playbackTriggerOneShot() → Voice ID → _PlayingInstance           │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Analiza po Ulogama

---

### 1. Chief Audio Architect 🎵

**Ocena:** ⭐⭐⭐⭐ (4/5)

#### Strengths ✅

| Feature | Line | Assessment |
|---------|------|------------|
| **Stage→Event separation** | 115-193 | Wwise/FMOD-style pattern - events are definitions, stages are triggers |
| **Multi-layer playback** | 955-964 | Each event can have N layers with individual delay/offset |
| **Container delegation** | 905-909 | Blend/Random/Sequence containers properly integrated |
| **RTPC modulation** | 1102-1104 | Volume modulation through RtpcModulationService |
| **Ducking integration** | 1150 | DuckingService.notifyBusActive() called per layer |
| **Spatial audio** | 1117-1147 | AutoSpatialEngine integration with intent-based positioning |
| **Bus routing** | 368-382 | Stage→Bus mapping via StageConfigurationService |
| **Priority system** | 362-364 | StageConfigurationService.getPriority() |
| **Pooling for rapid events** | 1184-1193 | AudioPool for CASCADE_STEP, ROLLUP_TICK |
| **Seamless looping** | 1194-1202 | playLoopingToBus() for REEL_SPIN |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| **No voice limit per event** | 950-952 | Can spawn unlimited voices if event triggered rapidly | P1 |
| **No crossfade for loop stop** | 1194-1202 | Loop stop is abrupt, no fadeout | P2 |
| **Context pan override unclear** | 1113-1115 | context['pan'] overrides layer pan but not documented | P2 |
| **No per-layer RTPC** | 1102-1104 | RTPC checks eventId only, not layerId | P3 |
| **Fixed spatial lifetime** | 1129 | Hardcoded 500ms lifetime for spatial events | P3 |

#### Recommendations

```dart
// P1 FIX: Voice limit per event
class AudioEvent {
  final int maxVoices; // Default 8, prevent voice explosion
  // ...
}

// In _playLayer:
if (_getActiveVoiceCount(eventId) >= event.maxVoices) {
  _stopOldestVoice(eventId);
}

// P2 FIX: Crossfade loop stop
void stopLoopingEvent(String eventId, {double fadeOutMs = 100}) {
  // Apply fade envelope before stopping
}
```

---

### 2. Lead DSP Engineer 🔧

**Ocena:** ⭐⭐⭐⭐ (4/5)

#### Strengths ✅

| Feature | Line | Assessment |
|---------|------|------------|
| **Non-blocking async playback** | 1073-1232 | All audio ops are async, UI thread safe |
| **Pool hit = instant response** | 1184-1193 | Pre-allocated voices for rapid-fire |
| **Delay accumulation** | 1088-1091 | layer.delay + layer.offset properly combined |
| **Volume clamping** | 1198, 1207-1208 | Always clamp 0.0-1.0 before FFI |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| **Future.delayed blocking** | 1089-1091 | Dart timer, not sample-accurate | P1 |
| **No sample-accurate scheduling** | — | Can't sync to beat/bar grid | P1 |
| **Pan not smoothed** | 1110-1147 | Pan jumps, no slew rate | P2 |
| **Volume multiplier not smoothed** | 1096-1098 | Context volumeMultiplier applied instantly | P2 |

#### Recommendations

```dart
// P1 FIX: Sample-accurate scheduling
// Move delay handling to Rust engine
NativeFFI.instance.playbackScheduleOneShot(
  path: layer.audioPath,
  delaySamples: (layer.delay * sampleRate / 1000).round(),
  // ...
);

// P2 FIX: Pan smoothing (in Rust)
// Add slew_rate parameter to voice
NativeFFI.instance.playbackSetVoicePan(voiceId, pan, slewMs: 10);
```

---

### 3. Engine Architect 🏗️

**Ocena:** ⭐⭐⭐⭐ (4/5)

#### Strengths ✅

| Feature | Line | Assessment |
|---------|------|------------|
| **Clean separation from Rust** | 1174-1212 | All FFI calls go through AudioPlaybackService |
| **PlaybackSource enum** | 1165-1170 | Proper source tagging for voice filtering |
| **Instance tracking** | 946-952 | _PlayingInstance with voiceIds list |
| **Equivalent check** | 564-593 | _eventsAreEquivalent() prevents unnecessary audio cutoff |
| **Sync stop** | 537-560 | _stopEventSync() for immediate stop in registerEvent |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| **Global singleton pattern** | 1494 | `eventRegistry` global, hard to test | P2 |
| **_playingInstances unbounded** | 290 | List grows without cleanup | P1 |
| **No voice cleanup on dispose** | 1481-1486 | stopAll() may miss pooled voices | P2 |
| **Duplicate stage check** | 419-425 | Could race with concurrent registerEvent | P3 |

#### Recommendations

```dart
// P1 FIX: Auto-cleanup finished instances
void _cleanupFinishedInstances() {
  final now = DateTime.now();
  _playingInstances.removeWhere((i) {
    final event = _events[i.eventId];
    if (event == null) return true;
    final maxDuration = Duration(milliseconds: (event.duration * 1000).round() + 1000);
    return now.difference(i.startTime) > maxDuration;
  });
}

// Call periodically or after each trigger
Timer.periodic(Duration(seconds: 5), (_) => _cleanupFinishedInstances());

// P2 FIX: Remove global singleton
// Register via GetIt instead:
// sl.registerLazySingleton<EventRegistry>(() => EventRegistry());
```

---

### 4. Technical Director 📐

**Ocena:** ⭐⭐⭐⭐ (4/5)

#### Architecture Decisions

| Decision | Assessment |
|----------|------------|
| **Stage as string, not enum** | ✅ Flexible, but no compile-time safety |
| **Event = definition, Stage = trigger** | ✅ Wwise/FMOD pattern, industry standard |
| **Container delegation** | ✅ Clean separation of concerns |
| **Service delegation** | ✅ StageConfigurationService for centralized config |

#### Single Source of Truth

| Data | SSoT Location | Sync |
|------|---------------|------|
| Event definitions | `_events` Map | MiddlewareProvider sync via registerEvent |
| Stage→Event mapping | `_stageToEvent` Map | Auto-updated in registerEvent |
| Playing instances | `_playingInstances` List | Manual management |
| Pooled stages | `_pooledEventStages` const | StageConfigurationService |

#### Dependency Graph

```
EventRegistry
├── NativeFFI (FFI calls)
├── AudioPlaybackService (playback routing)
├── AudioPool (rapid-fire pooling)
├── ContainerService (Blend/Random/Sequence)
├── DuckingService (bus notification)
├── RtpcModulationService (volume modulation)
├── StageConfigurationService (stage config)
├── AutoSpatialEngine (spatial positioning)
├── UnifiedPlaybackController (section management)
└── RecentFavoritesService (history tracking)
```

**10 dependencies** — relatively high coupling but all are services, not providers.

---

### 5. UI/UX Expert 🎨

**Ocena:** ⭐⭐⭐ (3/5)

#### Strengths ✅

| Feature | Line | Assessment |
|---------|------|------------|
| **Last trigger tracking** | 325-342 | lastTriggeredEventName, lastTriggeredStage for Event Log |
| **Error tracking** | 329, 1226 | lastTriggerError with detailed info |
| **Container info** | 331-342 | lastContainerType, lastContainerName for UI |
| **notifyListeners** | 448, 969, 1257 | UI rebuilds on state changes |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| **debugPrint only** | Throughout | No UI-visible debug panel | P1 |
| **No trigger history** | — | Only last trigger stored | P2 |
| **No stage validation feedback** | 811-824 | Rejected stages not reported to UI | P2 |
| **Stats not exposed to UI** | 1458-1466 | statsString only, no structured data | P3 |

#### Recommendations

```dart
// P1 FIX: Expose trigger history
final List<TriggerRecord> _triggerHistory = [];
static const int _maxHistory = 100;

class TriggerRecord {
  final DateTime time;
  final String stage;
  final String eventName;
  final bool success;
  final String? error;
  final List<String> layers;
}

// Add to triggerEvent:
_triggerHistory.add(TriggerRecord(...));
if (_triggerHistory.length > _maxHistory) _triggerHistory.removeAt(0);

// P2 FIX: Validation callback for UI
VoidCallback? onStageValidationFailed;
// Call in triggerStage when validation fails
```

---

### 6. Graphics Engineer 🎮

**Ocena:** N/A

EventRegistry has no graphics/rendering concerns. The only visual aspect is:
- **Spatial visualization** (line 1117-1147) — But actual rendering is in AutoSpatialEngine

---

### 7. Security Expert 🔒

**Ocena:** ⭐⭐⭐⭐ (4/5)

#### Strengths ✅

| Feature | Line | Assessment |
|---------|------|------------|
| **Input validation** | 807-824 | Empty check, length limit, alphanumeric regex |
| **Path not executed** | — | audioPath is only passed to FFI, not executed |
| **eventId length check** | 889-892 | 256 char limit |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| **audioPath not validated** | 38-79 | Could contain path traversal | P1 |
| **No path sanitization** | 1081 | Directly used in FFI calls | P1 |
| **JSON deserialization trust** | 1442-1450 | fromJson() trusts all data | P2 |

#### Recommendations

```dart
// P1 FIX: Path validation in AudioLayer
factory AudioLayer.fromJson(Map<String, dynamic> json) {
  final path = json['audioPath'] as String;
  // Reject path traversal
  if (path.contains('..') || path.contains('\0')) {
    throw ArgumentError('Invalid audioPath: potential path traversal');
  }
  // Reject non-audio extensions
  final ext = path.split('.').last.toLowerCase();
  const allowedExtensions = {'wav', 'mp3', 'ogg', 'flac', 'aiff'};
  if (!allowedExtensions.contains(ext) && path.isNotEmpty) {
    throw ArgumentError('Invalid audioPath: unsupported extension $ext');
  }
  return AudioLayer(...);
}

// P2 FIX: Schema validation for JSON
void loadFromJson(Map<String, dynamic> json, {bool validate = true}) {
  if (validate) {
    _validateSchema(json);
  }
  // ... existing code
}
```

---

## Summary Tables

### Priority Matrix

| ID | Issue | Role | Priority | LOC Est | Risk |
|----|-------|------|----------|---------|------|
| P1.1 | Path validation | Security | P1 | ~30 | HIGH |
| P1.2 | Voice limit per event | Audio | P1 | ~25 | MED |
| P1.3 | Instance cleanup | Engine | P1 | ~20 | MED |
| P1.4 | Trigger history | UX | P1 | ~40 | LOW |
| P2.1 | Crossfade loop stop | Audio | P2 | ~30 | LOW |
| P2.2 | Pan smoothing | DSP | P2 | Rust | MED |
| P2.3 | Global singleton removal | Engine | P2 | ~15 | LOW |
| P2.4 | Validation feedback | UX | P2 | ~20 | LOW |

### Strength Summary

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Audio Architecture** | ⭐⭐⭐⭐ | Industry-standard patterns |
| **FFI Integration** | ⭐⭐⭐⭐⭐ | Clean separation |
| **Container Support** | ⭐⭐⭐⭐⭐ | Full Blend/Random/Sequence |
| **Pooling/Performance** | ⭐⭐⭐⭐ | Good for rapid-fire |
| **Security** | ⭐⭐⭐ | Input validation present, path validation missing |
| **UX Feedback** | ⭐⭐⭐ | Basic tracking, no history |
| **Testability** | ⭐⭐ | Global singleton, hard to mock |

---

## Proposed P1 Implementation Plan

### P1.1: Path Validation (~30 LOC)

```dart
// Add to AudioLayer class
static String _sanitizePath(String path) {
  if (path.isEmpty) return path;
  // Reject path traversal
  if (path.contains('..')) {
    throw ArgumentError('Path traversal not allowed');
  }
  // Normalize separators
  return path.replaceAll('\\', '/');
}

// Add to AudioLayer.fromJson
final sanitizedPath = _sanitizePath(json['audioPath'] as String);
```

### P1.2: Voice Limit (~25 LOC)

```dart
// Add to AudioEvent
final int maxVoices; // Default 8

// Add to triggerEvent
int _countActiveVoices(String eventId) {
  return _playingInstances
      .where((i) => i.eventId == eventId)
      .fold(0, (sum, i) => sum + i.voiceIds.length);
}
```

### P1.3: Instance Cleanup (~20 LOC)

```dart
// Add timer in constructor
EventRegistry() {
  Timer.periodic(Duration(seconds: 5), (_) => _cleanupFinishedInstances());
}

void _cleanupFinishedInstances() {
  // Remove instances older than event.duration + 1s buffer
}
```

### P1.4: Trigger History (~40 LOC)

```dart
class TriggerRecord {
  final DateTime time;
  final String stage;
  final String eventName;
  final bool success;
  final String? error;
}

final List<TriggerRecord> _triggerHistory = [];
List<TriggerRecord> get triggerHistory => List.unmodifiable(_triggerHistory);
```

---

**Analysis Complete:** 2026-01-24
**Next:** Implementation of P1 tasks
