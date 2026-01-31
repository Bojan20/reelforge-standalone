# SlotLab Stage→Audio Complete Verification

**Date:** 2026-01-31
**Status:** ✅ VERIFIED — System is CORRECTLY connected

---

## Executive Summary

**FINDING: The SlotLab audio system is PROPERLY CONNECTED per industry standards.**

The initial Gap Analysis identified that `SlotLabProvider._triggerStage()` skips many stages in Visual-Sync mode. This is **BY DESIGN** — the widget (`slot_preview_widget.dart`) handles these stages directly for audio-visual synchronization.

| Component | Stage Source | Audio Trigger | Status |
|-----------|--------------|---------------|--------|
| Provider | Rust engine timing | Provider skips visual-sync stages | ✅ Correct |
| Widget | Animation callbacks | Widget calls EventRegistry directly | ✅ Correct |
| EventRegistry | Receives triggers | Plays audio via FFI | ✅ Correct |

---

## 1. Complete Audio Flow

### 1.1 Provider-Triggered Stages (Direct Path)

Stages that Provider DOES trigger (not in visual-sync skip list):

```
SlotLabProvider._broadcastStages()
    ↓
_triggerStage(stage)
    ↓ (NOT skipped)
EventRegistry.triggerStage(stageType)
    ↓
_tryPlayEvent() → _playLayer() → AudioPlaybackService.playFileToBus()
    ↓
NativeFFI.playbackPlayToBus() → Rust engine_playback_play_to_bus()
    ↓
Audio output
```

**Provider-triggered stages:**
- SPIN_START, SPIN_END
- REEL_SPINNING_START_*, REEL_SPINNING_*
- ANTICIPATION_ON, ANTICIPATION_TENSION_*, ANTICIPATION_OFF
- EVALUATE_WINS
- CASCADE_START, CASCADE_STEP_*, CASCADE_END (P0.21 pitch escalation)
- Feature stages (FS_*, BONUS_*, HOLD_*)

### 1.2 Widget-Triggered Stages (Visual-Sync Path)

Stages that Widget handles for precise audio-visual sync:

```
slot_preview_widget.dart animation callback
    ↓
EventRegistry.triggerStage(stage, context: {...})
    ↓
_tryPlayEvent() → _playLayer() → AudioPlaybackService.playFileToBus()
    ↓
NativeFFI.playbackPlayToBus() → Rust engine_playback_play_to_bus()
    ↓
Audio output
```

---

## 2. Widget EventRegistry Calls — VERIFIED

### 2.1 REEL_STOP (Visual-Sync)

**Location:** `slot_preview_widget.dart:900`

```dart
// In _triggerReelStopAudio()
eventRegistry.triggerStage('REEL_STOP_$reelIndex', context: {'timestamp_ms': timestampMs});
```

**Sequential Buffer:** Lines 880-910 implement IGT-style sequential buffer:
- `_nextExpectedReelIndex` ensures audio triggers in order 0→1→2→3→4
- Prevents out-of-order audio when animations complete non-deterministically

### 2.2 WIN_SYMBOL_HIGHLIGHT (Visual-Sync)

**Locations:**
- `slot_preview_widget.dart:938` — Per-symbol highlight (WIN_SYMBOL_HIGHLIGHT_HP1, etc.)
- `slot_preview_widget.dart:942` — Generic fallback (WIN_SYMBOL_HIGHLIGHT)
- `slot_preview_widget.dart:1556, 1561` — Additional highlight triggers

```dart
// Line 938-942
eventRegistry.triggerStage(stage);  // WIN_SYMBOL_HIGHLIGHT_HP1, etc.
eventRegistry.triggerStage('WIN_SYMBOL_HIGHLIGHT');  // Generic fallback
```

### 2.3 WIN_PRESENT (Visual-Sync)

**Locations:**
- `slot_preview_widget.dart:1593` — Tiered win presentation
- `slot_preview_widget.dart:1631` — Additional tier triggers

```dart
// Line 1593
eventRegistry.triggerStage('WIN_PRESENT_$winPresentTier');
// Possible values: WIN_PRESENT_SMALL, WIN_PRESENT_BIG, WIN_PRESENT_SUPER, etc.
```

### 2.4 BIG_WIN Celebrations (Visual-Sync)

**Locations:**
- `slot_preview_widget.dart:1640-1641` — Big win loop + coins
- `slot_preview_widget.dart:2630` — BIG_WIN_INTRO
- `slot_preview_widget.dart:2725` — BIG_WIN_END

```dart
// Lines 1640-1641 (triggered when winRatio >= 20x)
eventRegistry.triggerStage('BIG_WIN_LOOP');   // Looping celebration music
eventRegistry.triggerStage('BIG_WIN_COINS');  // Coin particle SFX
```

### 2.5 WIN_LINE_SHOW (Visual-Sync)

**Locations:**
- `slot_preview_widget.dart:1821` — Win line cycling
- `slot_preview_widget.dart:1850` — Per-line show

```dart
// Phase 3: Win line presentation (STRICT SEQUENTIAL — after rollup)
eventRegistry.triggerStage('WIN_LINE_SHOW');
eventRegistry.triggerStage('WIN_LINE_SHOW_$lineIndex');
```

### 2.6 ROLLUP (Visual-Sync)

**Locations:**
- `slot_preview_widget.dart:2214` — ROLLUP_END
- `slot_preview_widget.dart:2223` — ROLLUP_TICK with progress
- `slot_preview_widget.dart:2397` — ROLLUP_START
- `slot_preview_widget.dart:2442, 2458, 2489, 2513, 2531` — Additional rollup stages

```dart
// Line 2648: ROLLUP_START at big win intro
eventRegistry.triggerStage('ROLLUP_START');

// Line 2223: ROLLUP_TICK with progress context for volume escalation
eventRegistry.triggerStage('ROLLUP_TICK', context: {'progress': progress});

// Line 2214: ROLLUP_END
eventRegistry.triggerStage('ROLLUP_END');
```

### 2.7 ANTICIPATION (Provider + Widget)

**Provider triggers:** ANTICIPATION_ON, ANTICIPATION_TENSION_R*_L*, ANTICIPATION_OFF

**Widget triggers:** (for visual speed reduction)
- `slot_preview_widget.dart:1002, 1039, 1106` — Anticipation start
- `slot_preview_widget.dart:2801, 2851` — Anticipation callbacks

### 2.8 NEAR_MISS (Visual-Sync)

**Locations:**
- `slot_preview_widget.dart:3053, 3064, 3071` — Near miss detection

```dart
// Near miss intensity modulation (per-reel)
eventRegistry.triggerStage('NEAR_MISS_REEL_$reelIndex', context: {'intensity': intensity});
```

---

## 3. EventRegistry Processing — VERIFIED

### 3.1 Stage Resolution (Multi-Level Fallback)

**Location:** `event_registry.dart:1750-1850`

```dart
// Level 1: Try exact match
var event = _events.values.firstWhere((e) => e.stage == stage);

// Level 2: Try normalized (uppercase)
final normalized = stage.toUpperCase().trim();
event = _events.values.firstWhere((e) => e.stage.toUpperCase() == normalized);

// Level 3: Try fallback stage (REEL_STOP_0 → REEL_STOP)
final fallback = _getFallbackStage(stage);
if (fallback != null) {
  event = _events.values.firstWhere((e) => e.stage == fallback);
}
```

**Fallback Patterns:**
| Specific | Generic |
|----------|---------|
| `REEL_STOP_0..4` | `REEL_STOP` |
| `CASCADE_STEP_0..N` | `CASCADE_STEP` |
| `WIN_LINE_SHOW_N` | `WIN_LINE_SHOW` |
| `SYMBOL_LAND_N` | `SYMBOL_LAND` |
| `ROLLUP_TICK_N` | `ROLLUP_TICK` |

### 3.2 Voice Limit & Pooling

**Location:** `event_registry.dart:1970-1986`

```dart
// Voice limit check
if (activeVoices >= _maxVoicesPerEvent) {
  _voiceLimitRejects++;
  return;  // Prevents audio spam
}

// Pooled events (rapid-fire)
if (usePool && eventKey != null) {
  voiceId = AudioPool.instance.acquire(eventKey: eventKey, ...);
}
```

**Pooled Stages:** REEL_STOP, CASCADE_STEP, ROLLUP_TICK, WIN_LINE_SHOW, etc.

### 3.3 Audio Playback Execution

**Location:** `event_registry.dart:2196-2430` (`_playLayer()`)

```dart
// Standard playback
voiceId = AudioPlaybackService.instance.playFileToBus(
  layer.audioPath,
  volume: volume.clamp(0.0, 1.0),
  pan: pan.clamp(-1.0, 1.0),
  busId: layer.busId,
  source: source,
);

// Looping playback (REEL_SPIN, BIG_WIN_LOOP)
voiceId = AudioPlaybackService.instance.playLoopingToBus(...);

// Extended playback (fade, trim)
voiceId = AudioPlaybackService.instance.playFileToBusEx(...);
```

---

## 4. FFI Chain — VERIFIED

### 4.1 AudioPlaybackService → NativeFFI

**Location:** `audio_playback_service.dart:204-230`

```dart
int playFileToBus(String path, {...}) {
  final sourceId = _sourceToEngineId(source);
  final voiceId = _ffi.playbackPlayToBus(path, volume: volume, pan: pan, busId: busId, source: sourceId);
  // Track active voice
  _activeVoices.add(VoiceInfo(voiceId: voiceId, audioPath: path, source: source, ...));
  return voiceId;
}
```

### 4.2 NativeFFI → Rust Engine

**Location:** `native_ffi.dart:4540-4570`

```dart
int playbackPlayToBus(String path, {double volume = 1.0, double pan = 0.0, int busId = 0, int source = 1}) {
  final pathPtr = path.toNativeUtf8();
  final resultPtr = _playbackPlayToBus(pathPtr, volume, pan, busId, source);
  // Parse JSON result {"voice_id": 123}
  final voiceId = int.parse(match.group(1)!);
  return voiceId;
}
```

### 4.3 Rust Engine

**Location:** `crates/rf-engine/src/ffi.rs` — `engine_playback_play_to_bus()`

- Loads audio file
- Creates voice in playback engine
- Routes to specified bus
- Returns voice_id

---

## 5. Special Audio Features — VERIFIED

### 5.1 Per-Reel Spin Loop Fade-Out (P0)

**Location:** `event_registry.dart:1050-1100`

```dart
// Per-reel spin loop tracking
final Map<int, int> _reelSpinLoopVoices = {};  // reelIndex → voiceId

// On REEL_STOP_X, fade out that reel's spin loop
void _fadeOutReelSpinLoop(int reelIndex) {
  final voiceId = _reelSpinLoopVoices.remove(reelIndex);
  if (voiceId != null) {
    AudioPlaybackService.instance.fadeOutVoice(voiceId, fadeMs: 50);
  }
}
```

### 5.2 Cascade Pitch Escalation (P0.21)

**Location:** `event_registry.dart:1820-1840`

```dart
// Extract step index from stage name (CASCADE_STEP_3 → 3)
final stepMatch = RegExp(r'CASCADE_STEP_(\d+)').firstMatch(stage);
if (stepMatch != null) {
  final stepIndex = int.parse(stepMatch.group(1)!);
  // Pitch: 1.0 + (stepIndex * 0.05) = 1.0, 1.05, 1.10, 1.15...
  // Volume: 0.9 + (stepIndex * 0.04) = 0.9, 0.94, 0.98, 1.02...
  context = {...context, 'cascade_pitch': 1.0 + stepIndex * 0.05, 'cascade_volume': 0.9 + stepIndex * 0.04};
}
```

### 5.3 Rollup Volume Dynamics (P1.2)

**Location:** `event_registry.dart:2248-2256`

```dart
if (eventKey != null && eventKey.contains('ROLLUP') && context != null) {
  final progress = context['progress'] as double?;
  if (progress != null) {
    // Volume escalation 0.85x → 1.15x during rollup
    final escalation = RtpcModulationService.instance.getRollupVolumeEscalation(progress);
    volume *= escalation;
  }
}
```

### 5.4 Crossfade Handling (P1.10)

**Location:** `event_registry.dart:1998-2022`

```dart
if (_shouldCrossfade(event.stage)) {
  // Fade out existing voices in crossfade group
  final existingVoices = _crossfadeGroupVoices[group];
  for (final voice in existingVoices) {
    AudioPlaybackService.instance.fadeOutVoice(voice.voiceId, fadeMs: voice.fadeOutMs);
  }
  // Add fade-in to new voices
  context['crossfade_in_ms'] = fadeMs;
}
```

---

## 6. Summary Table

| Stage Category | Provider Triggers | Widget Triggers | EventRegistry Receives | Status |
|----------------|-------------------|-----------------|------------------------|--------|
| SPIN_START/END | ✅ | — | ✅ | ✅ VERIFIED |
| REEL_SPINNING_* | ✅ | — | ✅ | ✅ VERIFIED |
| REEL_STOP_* | ❌ (visual-sync) | ✅ | ✅ | ✅ VERIFIED |
| ANTICIPATION_* | ✅ | ✅ (visual) | ✅ | ✅ VERIFIED |
| WIN_SYMBOL_HIGHLIGHT | ❌ (visual-sync) | ✅ | ✅ | ✅ VERIFIED |
| WIN_PRESENT_* | ❌ (visual-sync) | ✅ | ✅ | ✅ VERIFIED |
| WIN_LINE_SHOW | ❌ (visual-sync) | ✅ | ✅ | ✅ VERIFIED |
| ROLLUP_* | ❌ (visual-sync) | ✅ | ✅ | ✅ VERIFIED |
| BIG_WIN_* | ❌ (visual-sync) | ✅ | ✅ | ✅ VERIFIED |
| CASCADE_* | ✅ | — | ✅ | ✅ VERIFIED |
| NEAR_MISS_* | — | ✅ | ✅ | ✅ VERIFIED |

---

## 7. Conclusion

**The SlotLab Stage→Audio system is CORRECTLY CONNECTED.**

### Architecture Summary:

1. **Provider Path:** Handles non-visual-sync stages directly
2. **Widget Path:** Handles visual-sync stages for precise audio-visual alignment
3. **EventRegistry:** Central hub that processes ALL triggers uniformly
4. **FFI Chain:** Complete path from Dart → Rust → Audio output

### No Fixes Required

The initial Gap Analysis concern about "skipped stages" was a misunderstanding of the architecture:
- Visual-sync mode is **intentional design** for audio-visual synchronization
- Widget **compensates correctly** by calling EventRegistry directly
- All stage categories have complete coverage

### Industry Standard Compliance:

- ✅ Per-reel spin loops with independent fade-out
- ✅ Sequential reel stop buffer (IGT pattern)
- ✅ 3-phase win presentation (highlight → plaque → lines)
- ✅ Tiered win audio (SMALL → BIG → SUPER → MEGA → EPIC → ULTRA)
- ✅ Cascade pitch/volume escalation
- ✅ Rollup volume dynamics
- ✅ Crossfade handling for smooth transitions

---

*Verification completed: 2026-01-31*
*Analyzer: Claude Code*
