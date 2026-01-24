# CompositeEventSystemProvider Ultra-Detailed Analysis

**Datum:** 2026-01-24
**Fajl:** `flutter_ui/lib/providers/subsystems/composite_event_system_provider.dart`
**LOC:** ~1448
**Status:** ANALYSIS IN PROGRESS

---

## Executive Summary

CompositeEventSystemProvider je **najkompleksniji subsystem provider** u projektu. Upravlja SlotCompositeEvent CRUD-om, undo/redo sistemom, layer operacijama, clipboard-om, multi-select-om i bidirekcionalnom sinhronizacijom sa EventSystemProvider-om.

### Arhitektura

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      COMPOSITE EVENT SYSTEM PROVIDER                         │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ STATE MANAGEMENT                                                        ││
│  │ • _compositeEvents: Map<String, SlotCompositeEvent>                     ││
│  │ • _selectedCompositeEventId: String?                                    ││
│  │ • _nextLayerId: int (auto-increment)                                    ││
│  │ • _undoStack/_redoStack: List<Map<String, SlotCompositeEvent>>          ││
│  │ • _layerClipboard: SlotEventLayer?                                      ││
│  │ • _selectedLayerIds: Set<String> (multi-select)                         ││
│  │ • _eventHistory: List<EventHistoryEntry> (ring buffer)                  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ CRUD OPERATIONS                                                         ││
│  │ • createCompositeEvent() — with undo push                               ││
│  │ • updateCompositeEvent() — with history recording                       ││
│  │ • deleteCompositeEvent() — stops voices, syncs middleware               ││
│  │ • addCompositeEvent() — enforces limit (500 max)                        ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ LAYER OPERATIONS                                                        ││
│  │ • addLayerToEvent() — auto-detect duration via FFI                      ││
│  │ • removeLayerFromEvent() — stops voices                                 ││
│  │ • updateEventLayer() — with undo                                        ││
│  │ • toggleLayerMute/Solo()                                                ││
│  │ • setLayerVolume/Pan/Offset() — continuous (no undo) + final (undo)    ││
│  │ • reorderEventLayers()                                                  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ SYNC TO MIDDLEWARE                                                      ││
│  │ • _syncCompositeToMiddleware() — converts to MiddlewareEvent            ││
│  │ • _removeMiddlewareEventForComposite()                                  ││
│  │ • syncMiddlewareToComposite() — bidirectional sync                      ││
│  │ • _compositeToMiddlewareId() / _middlewareToCompositeId()               ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ STAGE TRIGGER MAPPING                                                   ││
│  │ • setTriggerStages() / addTriggerStage() / removeTriggerStage()         ││
│  │ • setTriggerConditions() — RTPC-based conditions                        ││
│  │ • getEventsForStage() / getEventsForStageWithConditions()               ││
│  │ • _evaluateCondition() — runtime condition evaluation                   ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        EVENT SYSTEM PROVIDER                                 │
│                   (MiddlewareEvent CRUD + FFI sync)                          │
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
| **Multi-layer event model** | 78-79 | SlotCompositeEvent can have N layers with individual timing |
| **Mute/Solo per layer** | 502-519 | Standard DAW workflow for layer isolation |
| **Volume/Pan per layer** | 523-554 | Continuous (no undo) + Final (undo) variants |
| **Fade in/out support** | 574-585 | Per-layer fade times |
| **Loop support** | 1051 | Composite events can loop |
| **Bus routing by category** | 1127-1142 | Category → Bus mapping (Reels, Wins, Music, etc.) |
| **RTPC trigger conditions** | 1386-1407 | Conditional playback based on runtime values |
| **Master volume** | 1047 | Composite-level volume multiplier |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| **No layer crossfade** | 574 | Abrupt transitions when adjusting | P2 |
| **No velocity/expression layers** | — | No dynamics based on trigger velocity | P3 |
| **No random variation** | — | No pitch/volume randomization per trigger | P2 |

---

### 2. Lead DSP Engineer 🔧

**Ocena:** ⭐⭐⭐ (3/5)

#### Strengths ✅

| Feature | Line | Assessment |
|---------|------|------------|
| **Auto duration detection** | 408-414 | FFI call to get audio file duration |
| **Layer offset in ms** | 557-571 | Precise timing control |
| **Volume clamping** | 527, 536 | 0.0-1.0 range enforced |
| **Pan clamping** | 544, 553 | -1.0 to 1.0 range enforced |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| **No sample-accurate sync** | 1048-1049 | Delay in seconds, not samples | P2 |
| **No PDC compensation** | — | Plugin delay not accounted for | P3 |
| **Volume can go to 2.0** | 937 | adjustSelectedLayersVolume allows > 1.0 | P1 |
| **No gain staging** | — | No pre/post fader gain | P3 |

---

### 3. Engine Architect ⚙️

**Ocena:** ⭐⭐⭐⭐ (4/5)

#### Strengths ✅

| Feature | Line | Assessment |
|---------|------|------------|
| **Bounded history** | 90, 104 | _maxUndoHistory=50, _maxHistoryEntries=100 |
| **Bounded events** | 93 | _maxCompositeEvents=500 with LRU eviction |
| **Efficient snapshots** | 612-626 | Full state copy for undo |
| **Voice cleanup on delete** | 347, 459-460 | Stops playing voices before removal |
| **Change listeners** | 107-213 | Observer pattern for external sync |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| **Undo snapshot copies all events** | 613-618 | O(n) memory per undo push | P2 |
| **No incremental undo** | 612-626 | Could use command pattern instead | P3 |
| **syncMiddlewareToComposite overhead** | 1078-1124 | Called on every middleware change | P2 |

---

### 4. Technical Director 📐

**Ocena:** ⭐⭐⭐⭐⭐ (5/5)

#### Strengths ✅

| Feature | Line | Assessment |
|---------|------|------------|
| **Clear separation** | 70-114 | Constructor injection for FFI and EventSystemProvider |
| **Single source of truth** | 79 | _compositeEvents Map is SSoT |
| **Bidirectional sync** | 1016-1125 | Composite ↔ Middleware real-time sync |
| **ID mapping convention** | 1020-1028 | `mw_event_*` prefix for middleware IDs |
| **Comprehensive API** | 119-186 | Clean getters for all state |
| **Export/Import** | 1204-1251 | Full JSON serialization with versioning |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| **No schema validation** | 1218-1235 | Import trusts JSON structure | P2 |
| **No migration support** | 1219-1222 | Version check but no migration logic | P2 |

---

### 5. UI/UX Expert 🎨

**Ocena:** ⭐⭐⭐⭐⭐ (5/5)

#### Strengths ✅

| Feature | Line | Assessment |
|---------|------|------------|
| **Multi-select support** | 99-100, 706-758 | Cmd/Ctrl+click, Shift+range, Select All |
| **Clipboard operations** | 96-97, 764-842 | Copy, Paste, Duplicate with proper naming |
| **Batch operations** | 844-1013 | Delete, Mute, Solo, Volume, Move for multi-select |
| **Event history tracking** | 102-175 | Ring buffer with timestamps, icons, details |
| **Continuous vs Final updates** | 523-571 | Slider drag (no undo) vs release (undo) |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| **No redo limit display** | 137 | UI can show redo stack size but no max | P3 |
| **No selection bounds feedback** | 720-739 | No visual feedback if range is invalid | P3 |

---

### 6. Graphics Engineer 🎮

**Ocena:** N/A

No direct rendering — UI handled by widgets.

---

### 7. Security Expert 🔒

**Ocena:** ⭐⭐⭐ (3/5)

#### Strengths ✅

| Feature | Line | Assessment |
|---------|------|------------|
| **Event limit enforced** | 373-388 | LRU eviction prevents memory exhaustion |
| **History limits** | 90, 104 | Bounded undo and event history |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| **No audioPath validation** | 401-444 | addLayerToEvent doesn't validate path | P1 |
| **No name sanitization** | 220-244 | Event name can contain any characters | P2 |
| **JSON import trusts input** | 1217-1235 | No validation on imported events | P1 |
| **Condition injection risk** | 1410-1426 | _evaluateCondition parses user input | P2 |

---

## Identified Issues Summary

### P1 — Critical (Fix Immediately)

| ID | Issue | Line | Impact | LOC Est |
|----|-------|------|--------|---------|
| P1.1 | audioPath validation missing | 401-444 | Path traversal possible | ~20 |
| P1.2 | Volume range >1.0 in batch ops | 937 | Audio clipping/distortion | ~5 |
| P1.3 | JSON import no validation | 1217-1235 | Malformed data crashes | ~30 |

### P2 — High Priority

| ID | Issue | Line | Impact |
|----|-------|------|--------|
| P2.1 | No layer crossfade on transitions | 574 | Abrupt audio changes |
| P2.2 | Undo copies all events (memory) | 613-618 | Memory spike on large projects |
| P2.3 | No schema migration for imports | 1219 | Future version incompatibility |
| P2.4 | Name/category sanitization | 220-244 | XSS if displayed in web export |
| P2.5 | Condition parsing injection | 1410-1426 | Potential DoS via complex regex |
| P2.6 | No random pitch/volume variation | — | Repetitive audio |

### P3 — Lower Priority

| ID | Issue | Line | Impact |
|----|-------|------|--------|
| P3.1 | No velocity layers | — | Limited expression |
| P3.2 | No PDC compensation | — | Plugin timing issues |
| P3.3 | No incremental undo | 612-626 | Suboptimal memory |

---

## P1 Implementation Plan

### P1.1 — audioPath Validation

Add validation before using audioPath in addLayerToEvent:

```dart
// Add at class level (reuse from EventRegistry)
static const _allowedAudioExtensions = {'.wav', '.mp3', '.ogg', '.flac', '.aiff', '.aif'};

bool _validateAudioPath(String path) {
  if (path.isEmpty) return true; // Empty allowed (placeholder)
  if (path.contains('..')) return false; // Path traversal
  if (path.contains('\x00')) return false; // Null byte
  final lowerPath = path.toLowerCase();
  return _allowedAudioExtensions.any((ext) => lowerPath.endsWith(ext));
}
```

Call in `addLayerToEvent()` before creating layer.

### P1.2 — Volume Range Fix

```dart
// Line 937: Change clamp range
volume: (l.volume + volumeDelta).clamp(0.0, 1.0), // Was 2.0
```

### P1.3 — JSON Import Validation

```dart
void importCompositeEventsFromJson(Map<String, dynamic> json) {
  // Validate version
  final version = json['version'] as int?;
  if (version == null || version < 1) {
    debugPrint('[CompositeEvents] ERROR: Invalid or missing version');
    return;
  }

  // Validate events array
  final events = json['compositeEvents'];
  if (events == null || events is! List) {
    debugPrint('[CompositeEvents] ERROR: Missing or invalid compositeEvents array');
    return;
  }

  // Validate each event before importing
  final validEvents = <SlotCompositeEvent>[];
  for (final eventJson in events) {
    if (eventJson is! Map<String, dynamic>) continue;
    if (!_validateEventJson(eventJson)) continue;
    try {
      validEvents.add(SlotCompositeEvent.fromJson(eventJson));
    } catch (e) {
      debugPrint('[CompositeEvents] Skipped invalid event: $e');
    }
  }

  // Only apply if we have valid events
  if (validEvents.isEmpty && events.isNotEmpty) {
    debugPrint('[CompositeEvents] ERROR: No valid events found');
    return;
  }

  _compositeEvents.clear();
  for (final event in validEvents) {
    _compositeEvents[event.id] = event;
    _syncCompositeToMiddleware(event);
  }
  notifyListeners();
}

bool _validateEventJson(Map<String, dynamic> json) {
  // Required fields
  if (json['id'] is! String || (json['id'] as String).isEmpty) return false;
  if (json['name'] is! String) return false;

  // Validate layers if present
  final layers = json['layers'];
  if (layers != null && layers is! List) return false;

  return true;
}
```

---

## Stats & Metrics

| Metric | Value |
|--------|-------|
| Total LOC | ~1448 |
| Public Methods | 52 |
| Private Methods | 12 |
| State Fields | 11 |
| Dependencies | 2 (NativeFFI, EventSystemProvider) |
| Change Listeners | 1 pattern (Observer) |

---

---

## P1 Implementation Summary — ✅ ALL DONE

| ID | Task | LOC | Status |
|----|------|-----|--------|
| P1.1 | audioPath validation | ~45 | ✅ DONE |
| P1.2 | Volume clamp fix (2.0 → 1.0) | ~2 | ✅ DONE |
| P1.3 | JSON import validation | ~80 | ✅ DONE |

**Total:** ~127 LOC added to `composite_event_system_provider.dart`

### Implementation Details

**P1.1 — audioPath Validation:**
- Added `_allowedAudioExtensions` constant
- Added `_validateAudioPath()` method (blocks `..`, null bytes, invalid extensions, suspicious chars)
- Called in `addLayerToEvent()` before layer creation

**P1.2 — Volume Range Fix:**
- Line 937: Changed `clamp(0.0, 2.0)` → `clamp(0.0, 1.0)`
- Prevents audio clipping/distortion in batch volume operations

**P1.3 — JSON Import Validation:**
- Added `_validateEventJson()` for schema validation
- Added `_validateEventLayers()` to sanitize layers with invalid paths
- Comprehensive error handling with skip count reporting

**Verified:** `flutter analyze` — No errors

---

**Last Updated:** 2026-01-24 (Analysis + P1 Implementation COMPLETE)
