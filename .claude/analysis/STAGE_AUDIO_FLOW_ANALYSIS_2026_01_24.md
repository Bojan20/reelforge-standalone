# P0.2: Stage → Audio Complete Flow Analysis

**Date:** 2026-01-24
**Status:** ✅ VERIFIED
**Priority:** P0

---

## Executive Summary

Analiza je tracirala kompletan put od korisnikovog klika na Spin dugme do reprodukcije zvuka. Flow je dobro strukturiran sa jasnim odvajanjem odgovornosti.

---

## Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           USER CLICKS SPIN                                       │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 1. SlotPreviewWidget                                                             │
│    - Detects spin trigger (Space key or button click)                            │
│    - Calls: widget.provider.spin()                                               │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 2. SlotLabProvider.spin()                                                        │
│    - FFI call: _ffi.slotLabSpin() → Rust rf-slot-lab crate                       │
│    - Rust generates: SpinResult + StageEvents[]                                  │
│    - Gets results: slotLabGetSpinResult(), slotLabGetStages()                    │
│    - Calls: _playStagesSequentially()                                            │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 3. SlotLabProvider._playStagesSequentially()                                     │
│    - Acquires SlotLab section via UnifiedPlaybackController                      │
│    - Ensures audio stream is running                                             │
│    - Triggers stages based on Rust timestamps                                    │
│    - For REEL_STOP: SKIPS (visual-sync mode) → visual callback handles           │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    │                                   │
                    ▼                                   ▼
┌───────────────────────────────────────┐ ┌───────────────────────────────────────┐
│ 4a. Non-REEL_STOP Stages              │ │ 4b. REEL_STOP (Visual Sync)           │
│     - Provider calls:                 │ │     - Animation controller detects:   │
│       eventRegistry.triggerStage()    │ │       phase → bouncing (landing)      │
│                                       │ │     - Calls: onReelStop(reelIndex)    │
│                                       │ │     - Widget calls:                   │
│                                       │ │       triggerStage('REEL_STOP_$i')    │
└───────────────────────────────────────┘ └───────────────────────────────────────┘
                    │                                   │
                    └─────────────────┬─────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 5. EventRegistry.triggerStage(stage, context)                                    │
│    - Input validation (length, characters)                                       │
│    - Normalize stage name (uppercase)                                            │
│    - Look up AudioEvent by stage                                                 │
│    - Fallback: REEL_STOP_0 → REEL_STOP if specific not found                    │
│    - Calls: triggerEvent(event.id, context)                                      │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 6. EventRegistry.triggerEvent(eventId, context)                                  │
│    - Check container delegation (Blend/Random/Sequence)                          │
│    - Check if event has playable layers                                          │
│    - Check if pooled (rapid-fire events)                                         │
│    - For each layer: _playLayer(layer, voiceIds, context, ...)                   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 7. EventRegistry._playLayer(layer, ...)                                          │
│    ├─ Apply delay/offset (Future.delayed if needed)                              │
│    ├─ Apply volume from layer config                                             │
│    ├─ Apply RTPC modulation (RtpcModulationService)                              │
│    ├─ Apply spatial panning (AutoSpatialEngine)                                  │
│    ├─ Notify DuckingService                                                      │
│    └─ Route to correct playback method:                                          │
│       • AudioPool.acquire() — pooled events (CASCADE_STEP, ROLLUP_TICK)         │
│       • playLoopingToBus() — looping events (REEL_SPIN)                         │
│       • playFileToBus() — standard one-shot                                      │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 8. AudioPlaybackService.playFileToBus()                                          │
│    - Acquire playback section                                                    │
│    - Map PlaybackSource → engine source ID                                       │
│    - FFI call: _ffi.playbackPlayToBus(path, volume, pan, busId, source)         │
│    - Track voice in _activeVoices list                                           │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 9. Rust Engine (rf-engine)                                                       │
│    - playback_play_to_bus() in playback.rs                                       │
│    - Load audio file into new voice                                              │
│    - Apply volume, pan, source filtering                                         │
│    - Route to correct bus                                                        │
│    - Add to active voices for mixing                                             │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 10. Audio Output                                                                 │
│     - Rust mixes all active voices                                               │
│     - Applies bus processing (EQ, dynamics, etc.)                                │
│     - Routes to master bus                                                       │
│     - Output via cpal to system audio device                                     │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Components

### 1. SlotLabProvider (Provider)
- **Location:** `flutter_ui/lib/providers/slot_lab_provider.dart`
- **Responsibilities:**
  - FFI communication with Rust slot engine
  - Stage timing management
  - Visual-sync mode coordination

### 2. EventRegistry (Service)
- **Location:** `flutter_ui/lib/services/event_registry.dart`
- **Responsibilities:**
  - Stage → AudioEvent mapping
  - Layer playback orchestration
  - RTPC, spatial, ducking integration

### 3. AudioPlaybackService (Service)
- **Location:** `flutter_ui/lib/services/audio_playback_service.dart`
- **Responsibilities:**
  - FFI bridge to Rust playback engine
  - Voice management
  - Source filtering

### 4. UnifiedPlaybackController (Controller)
- **Location:** `flutter_ui/lib/services/unified_playback_controller.dart`
- **Responsibilities:**
  - Section isolation (DAW, SlotLab, Middleware)
  - Audio stream management
  - Playback state coordination

---

## Visual-Sync Mode

| Setting | Default | Effect |
|---------|---------|--------|
| `_useVisualSyncForReelStop` | `true` | REEL_STOP audio triggered by animation callback, not Rust timestamp |

**Purpose:** Ensures audio plays exactly when reel visually lands, regardless of Rust timestamp drift.

**Flow with Visual-Sync:**
1. Rust generates REEL_STOP stage at timestamp 1000ms
2. SlotLabProvider SKIPS triggering REEL_STOP (returns early)
3. Animation controller detects reel landing (phase → bouncing)
4. Widget calls `eventRegistry.triggerStage('REEL_STOP_0')`
5. Audio plays at exact visual landing moment

---

## Timing Points

| Event | Timestamp (Studio Mode) | Trigger Source |
|-------|-------------------------|----------------|
| SPIN_START | 0ms | Provider timer |
| REEL_SPINNING | 0ms | Provider timer |
| REEL_STOP_0 | 1000ms | Visual callback |
| REEL_STOP_1 | 1370ms | Visual callback |
| REEL_STOP_2 | 1740ms | Visual callback |
| REEL_STOP_3 | 2110ms | Visual callback |
| REEL_STOP_4 | 2480ms | Visual callback |
| EVALUATE_WINS | ~2530ms | Provider timer |
| WIN_PRESENT | ~2580ms | Provider timer |

---

## Audio Routing

| Playback Method | Use Case | Latency |
|-----------------|----------|---------|
| `AudioPool.acquire()` | Rapid-fire events (ROLLUP_TICK, CASCADE_STEP) | <1ms (pooled) |
| `playLoopingToBus()` | Continuous loops (REEL_SPIN) | ~3ms |
| `playFileToBus()` | Standard one-shot events | ~3ms |
| `previewFile()` | Browser preview | ~5ms |

---

## Verification Checklist

- [x] Spin button triggers SlotLabProvider.spin()
- [x] FFI calls generate correct StageEvents
- [x] Stages trigger in correct sequence with timing
- [x] Visual-sync mode correctly defers REEL_STOP
- [x] EventRegistry finds registered events
- [x] Layer playback applies RTPC, spatial, ducking
- [x] AudioPlaybackService routes to correct bus
- [x] Rust engine plays audio with correct parameters

---

## Potential Issues Identified

### 1. No Event Registered
**Symptom:** Stage triggers but no audio plays
**Solution:** Ensure AudioEvent exists with correct stage mapping

### 2. Section Not Active
**Symptom:** Audio doesn't play, "Section not acquired" error
**Solution:** EventRegistry now auto-acquires SlotLab section (fixed 2026-01-24)

### 3. Audio File Not Found
**Symptom:** Voice ID -1 returned
**Solution:** Verify audioPath exists on filesystem

---

## Files Involved

| File | Role |
|------|------|
| `slot_preview_widget.dart` | UI + visual animation callbacks |
| `slot_lab_provider.dart` | State management + FFI |
| `event_registry.dart` | Event lookup + layer playback |
| `audio_playback_service.dart` | FFI bridge to Rust |
| `unified_playback_controller.dart` | Section management |
| `crates/rf-slot-lab/` | Rust slot engine |
| `crates/rf-engine/src/playback.rs` | Rust audio playback |
