# ALE Provider Ultra-Detailed Analysis

**Datum:** 2026-01-24
**Fajl:** `flutter_ui/lib/providers/ale_provider.dart`
**LOC:** ~837
**Status:** ANALYSIS + P1 COMPLETE

---

## Executive Summary

AleProvider je Dart state management za Adaptive Layer Engine (rf-ale Rust crate). Upravlja signal/context/rule sistemom za dinamičnu game muziku.

### Arhitektura

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ALE PROVIDER                                       │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ DATA MODELS (~460 LOC)                                                  ││
│  │ • AleSignalDefinition — Signal with normalization (linear/sigmoid)      ││
│  │ • AleLayer — Audio layer in context (index, assetId, volumes)          ││
│  │ • AleContext — Context with layers and current level                    ││
│  │ • AleRule — Rule with condition (16 ops) and action (6 types)          ││
│  │ • AleTransitionProfile — Sync modes (beat/bar/phrase) + fades          ││
│  │ • AleStabilityConfig — 7 stability mechanisms                          ││
│  │ • AleProfile — Complete profile (contexts, rules, transitions)          ││
│  │ • AleEngineState — Runtime state snapshot                               ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ PROVIDER (~335 LOC)                                                     ││
│  │ • initialize() / shutdown()                                             ││
│  │ • loadProfile() / exportProfile() / createNewProfile()                  ││
│  │ • enterContext() / exitContext()                                        ││
│  │ • updateSignal() / updateSignals() / getSignalNormalized()              ││
│  │ • setLevel() / stepUp() / stepDown()                                    ││
│  │ • setTempo() / setTimeSignature()                                       ││
│  │ • startTickLoop() / stopTickLoop() / tick()                             ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ FFI BRIDGE (NativeFFI)                                                  ││
│  │ • aleInit() / aleShutdown() / aleTick()                                 ││
│  │ • aleLoadProfile() / aleExportProfile()                                 ││
│  │ • aleEnterContext() / aleExitContext()                                  ││
│  │ • aleUpdateSignal() / aleGetSignalNormalized()                          ││
│  │ • aleSetLevel() / aleStepUp() / aleStepDown()                           ││
│  │ • aleGetState() / aleSetTempo() / aleSetTimeSignature()                 ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Analiza po Ulogama

---

### 1. Chief Audio Architect 🎵

**Ocena:** ⭐⭐⭐⭐⭐ (5/5)

#### Strengths ✅

| Feature | Lines | Assessment |
|---------|-------|------------|
| **Signal system** | 24-71 | 4 normalization modes (linear, sigmoid, asymptotic, none) |
| **Context system** | 108-146 | Layer-based contexts with level tracking |
| **Rule system** | 148-289 | 16 comparison ops, 6 action types |
| **Transition profiles** | 291-362 | 6 sync modes (immediate, beat, bar, phrase, nextDownbeat, custom) |
| **Stability config** | 364-413 | 7 mechanisms (cooldown, hold, hysteresis, inertia, decay, momentum, prediction) |
| **Tempo/sync** | 762-776 | BPM and time signature support |

#### Weaknesses ❌

| Issue | Impact | Priority |
|-------|--------|----------|
| None identified | — | — |

**Verdict:** Excellent adaptive music architecture matching Wwise/FMOD standards.

---

### 2. Lead DSP Engineer 🔧

**Ocena:** ⭐⭐⭐⭐ (4/5)

#### Strengths ✅

| Feature | Lines | Assessment |
|---------|-------|------------|
| **Tick loop** | 782-806 | Configurable interval (~60fps default) |
| **Signal caching** | 511, 686-712 | Local cache avoids FFI calls for reads |
| **Tempo control** | 762-768 | Direct BPM setting |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| **No level clamping** | 720-730 | setLevel() accepts any int, could be negative or > maxLevel | P2 |
| **Tick notifies every 16ms** | 800-806 | notifyListeners() 60 times/sec even if state unchanged | P2 |

---

### 3. Engine Architect ⚙️

**Ocena:** ⭐⭐⭐⭐ (4/5)

#### Strengths ✅

| Feature | Lines | Assessment |
|---------|-------|------------|
| **Timer disposal** | 830-835 | Proper cleanup in dispose() |
| **FFI error handling** | 556-567 | Graceful failure on init |
| **State separation** | 507-519 | Clear Dart/Rust boundary |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| **JSON parsing every tick** | 812-824 | _refreshState() parses JSON 60x/sec | P1 |
| **No state diff check** | 800-806 | notifyListeners() called even if state unchanged | P2 |

---

### 4. Technical Director 📐

**Ocena:** ⭐⭐⭐⭐⭐ (5/5)

#### Strengths ✅

| Feature | Assessment |
|---------|------------|
| **Complete models** | Full toJson/fromJson for all types |
| **Clean API** | Simple methods with clear semantics |
| **FFI abstraction** | Provider shields UI from FFI details |
| **Profile versioning** | Version field in AleProfile |

#### Weaknesses ❌

| Issue | Impact | Priority |
|-------|--------|----------|
| None identified | — | — |

---

### 5. UI/UX Expert 🎨

**Ocena:** ⭐⭐⭐⭐⭐ (5/5)

#### Strengths ✅

| Feature | Lines | Assessment |
|---------|-------|------------|
| **Convenience getters** | 521-543 | activeContext, layerCount, currentLevel, maxLevel, etc. |
| **Signal caching** | 686-707 | Fast reads without FFI |
| **Context helpers** | 671-679 | contextIds, getContext() |
| **Transition state** | 540 | inTransition flag for UI feedback |

#### Weaknesses ❌

| Issue | Impact | Priority |
|-------|--------|----------|
| None identified | — | — |

---

### 6. Graphics Engineer 🎮

**Ocena:** N/A

No direct rendering — handled by ALE UI widgets.

---

### 7. Security Expert 🔒

**Ocena:** ⭐⭐⭐ (3/5)

#### Strengths ✅

| Feature | Assessment |
|---------|------------|
| **FFI boundary** | Rust handles validation on its side |
| **No raw user input** | Profile JSON comes from files/system |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| **No profile JSON validation** | 588-608 | loadProfile() trusts JSON structure | P2 |
| **No assetId path validation** | 89-97 | AleLayer.assetId could contain malicious paths | P1 |
| **No context/rule ID validation** | 644-669 | IDs could contain special characters | P3 |

---

## Identified Issues Summary

### P1 — Critical (Fix Immediately)

| ID | Issue | Line | LOC Est |
|----|-------|------|---------|
| P1.1 | JSON parsing every tick (60fps) | 812-824 | ~15 |
| P1.2 | No assetId path validation in AleLayer | 89-97 | ~25 |

### P2 — High Priority

| ID | Issue | Line | Impact |
|----|-------|------|--------|
| P2.1 | No level clamping in setLevel() | 720-730 | Invalid level state |
| P2.2 | notifyListeners() called even if unchanged | 800-806 | UI jank |
| P2.3 | No profile JSON structure validation | 588-608 | Crash on malformed JSON |

### P3 — Lower Priority

| ID | Issue | Impact |
|----|-------|--------|
| P3.1 | No context/rule ID validation | Special char injection |

---

## P1 Implementation Plan

### P1.1 — State Diff Check (Performance)

**Problem:** `_refreshState()` parses JSON every tick (60x/sec), and `tick()` calls `notifyListeners()` every time.

**Fix:** Cache previous state and only notify on change.

```dart
// Add field
String? _lastStateJson;

void _refreshState() {
  if (!_initialized) return;

  final stateJson = _ffi.aleGetState();
  if (stateJson == null) return;

  // P1.1 FIX: Only parse and notify if state changed
  if (stateJson == _lastStateJson) return;
  _lastStateJson = stateJson;

  try {
    final data = jsonDecode(stateJson) as Map<String, dynamic>;
    _state = AleEngineState.fromJson(data);
  } catch (e) {
    debugPrint('[AleProvider] Failed to parse state: $e');
  }
}

void tick() {
  if (!_initialized) return;

  _ffi.aleTick();
  final hadChange = _refreshStateAndCheckChange();
  if (hadChange) {
    notifyListeners();
  }
}
```

### P1.2 — AssetId Path Validation

**Problem:** `AleLayer.assetId` is not validated and could contain path traversal attacks.

**Fix:** Add validation in `fromJson()` factory.

```dart
/// Allowed audio extensions (same as EventRegistry)
static const _allowedAudioExtensions = {'.wav', '.mp3', '.ogg', '.flac', '.aiff', '.aif'};

/// Validate asset path
static bool _validateAssetPath(String path) {
  if (path.isEmpty) return true; // Empty allowed
  if (path.contains('..')) return false; // Path traversal
  if (path.contains('\x00')) return false; // Null byte
  final lowerPath = path.toLowerCase();
  return _allowedAudioExtensions.any((ext) => lowerPath.endsWith(ext));
}

factory AleLayer.fromJson(Map<String, dynamic> json) {
  final assetId = json['asset_id'] as String;

  // P1.2 SECURITY: Validate asset path
  if (!_validateAssetPath(assetId)) {
    debugPrint('[AleLayer] ⛔ SECURITY: Invalid asset path blocked: $assetId');
    // Return layer with empty path (safe fallback)
    return AleLayer(
      index: json['index'] as int,
      assetId: '', // Sanitized
      baseVolume: (json['base_volume'] as num?)?.toDouble() ?? 1.0,
      currentVolume: 0.0,
      isActive: false,
    );
  }

  return AleLayer(
    index: json['index'] as int,
    assetId: assetId,
    baseVolume: (json['base_volume'] as num?)?.toDouble() ?? 1.0,
    currentVolume: (json['current_volume'] as num?)?.toDouble() ?? 0.0,
    isActive: json['is_active'] as bool? ?? false,
  );
}
```

---

## Stats & Metrics

| Metric | Value |
|--------|-------|
| Total LOC | ~837 |
| Data Models | 8 classes, 5 enums |
| Provider Methods | 20 |
| FFI Calls | 17 functions |
| Dependencies | NativeFFI |

---

## P1 Implementation Summary — ✅ DONE

| ID | Task | LOC | Status |
|----|------|-----|--------|
| P1.1 | State diff check (performance) | ~20 | ✅ DONE |
| P1.2 | AssetId path validation (security) | ~30 | ✅ DONE |

**Total:** ~50 LOC added to `ale_provider.dart`

### Implementation Details

**P1.1 — State Diff Check:**
- Added `_lastStateJson` field to cache previous state
- Created `_refreshStateAndCheckChange()` method that returns bool
- `tick()` now only calls `notifyListeners()` when state changes
- **Impact:** Avoids JSON parsing 60x/sec when state unchanged, reduces UI rebuilds

**P1.2 — AssetId Path Validation:**
- Added `_allowedAudioExtensions` constant to AleLayer
- Added `_validateAssetPath()` static method
- `fromJson()` validates and sanitizes paths
- Blocks path traversal (`..`), null bytes, invalid extensions
- Returns empty assetId for invalid paths (safe fallback)

**Verified:** `flutter analyze` — No errors (only 2 pre-existing warnings)

---

**Last Updated:** 2026-01-24 (Analysis + P1 Implementation COMPLETE)
