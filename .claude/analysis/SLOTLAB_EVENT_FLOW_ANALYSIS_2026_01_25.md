# SLOTLAB EVENT FLOW ANALYSIS — Complete Stage→Event→Audio Chain
**Date:** 2026-01-25
**Scope:** Complete analysis of spin stage generation, playback, event triggering, and Event Log display

---

## EXECUTIVE SUMMARY

The SlotLab stage/event flow is a 6-stage pipeline:

```
1. RUST: Spin Result → Stage Generation
2. FFI: GetStages() → SlotLabProvider._lastStages
3. PROVIDER: Playback Timer → _triggerStage()
4. REGISTRY: Stage Event → Audio Playback
5. EVENT LOG: Timestamp-based Sorting → Display
6. VISUAL-SYNC: Animation Callback → REEL_STOP Override
```

**Key Finding:** Last REEL_STOP appears in wrong Event Log position due to **out-of-order animation callbacks** that fire before earlier reels complete.

---

## IGT INDUSTRY STANDARD FLOW

```
SPIN_START
    ↓
REEL_SPINNING (continuous loop audio)
    ↓
REEL_STOP_0 → wait → REEL_STOP_1 → wait → REEL_STOP_2 → wait → REEL_STOP_3 → wait → REEL_STOP_4
    ↓                                                                              ↓
    (SEQUENTIAL — each reel waits for previous)                                    (LAST)
    ↓
EVALUATE_WINS (only after ALL reels stopped)
    ↓
WIN_PRESENT / WIN_LINE_SHOW × N
    ↓
ROLLUP_START → ROLLUP_TICK × N → ROLLUP_END
    ↓
SPIN_END
```

**Critical Rule:** REEL_STOP events MUST fire in sequential order (0→1→2→3→4). Even if animation callbacks complete out of order, audio should play sequentially.

---

## ROOT CAUSE

Visual-sync mode animation callbacks may fire **out of order**:
- Reel 4 animation might complete before Reel 3
- This triggers REEL_STOP_4 before REEL_STOP_3
- Event Log shows entries in callback firing order (wrong)
- Audio plays at wrong time (out of sequence)

---

## SOLUTION: Sequential Reel Stop Buffer

Implement a buffer that:
1. Collects all reel stop callbacks as they fire
2. Only triggers audio when reels complete **in sequence**
3. If Reel 4 completes before Reel 3, buffer it
4. When Reel 3 completes, flush both Reel 3 and Reel 4

```dart
// Expected order tracking
int _nextExpectedReelIndex = 0;
Set<int> _pendingReelStops = {};

void onReelVisualStop(int reelIndex) {
    if (reelIndex == _nextExpectedReelIndex) {
        // This is the next expected reel — trigger immediately
        _triggerReelStopAudio(reelIndex);
        _nextExpectedReelIndex++;
        // Flush any buffered reels that are now in order
        _flushPendingReelStops();
    } else {
        // Out of order — buffer it
        _pendingReelStops.add(reelIndex);
    }
}

void _flushPendingReelStops() {
    while (_pendingReelStops.contains(_nextExpectedReelIndex)) {
        _pendingReelStops.remove(_nextExpectedReelIndex);
        _triggerReelStopAudio(_nextExpectedReelIndex);
        _nextExpectedReelIndex++;
    }
}
```

This guarantees sequential audio: REEL_STOP_0 → REEL_STOP_1 → REEL_STOP_2 → REEL_STOP_3 → REEL_STOP_4

---

## IMPLEMENTATION STATUS ✅ COMPLETE

**Implemented:** 2026-01-25

**File:** `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart`

**Changes:**

1. **New state variables** (line ~130):
   ```dart
   int _nextExpectedReelIndex = 0;
   final Set<int> _pendingReelStops = {};
   ```

2. **Modified `_onReelStopVisual()`** (line ~414):
   - Now checks if incoming reel is the expected one
   - If yes: triggers audio immediately, increments counter, flushes pending
   - If no: buffers for later

3. **New `_triggerReelStopAudio()`** (line ~460):
   - Extracts Rust timestamp for Event Log ordering
   - Calls `eventRegistry.triggerStage()`

4. **New `_flushPendingReelStops()`** (line ~475):
   - While loop processes buffered reels in sequence
   - Ensures strict 0→1→2→3→4 order

5. **Reset in `_startSpin()`** (line ~689):
   - `_nextExpectedReelIndex = 0;`
   - `_pendingReelStops.clear();`

**Result:** Audio and Event Log now show REEL_STOP events in correct sequential order, regardless of animation callback timing

---

## FIX: Voice Limit Reached After Multiple Spins

**Problem:** After 8+ rapid spins, debug panel shows "Voice limit reached".

**Root Cause:**
- Each spin triggers `REEL_SPIN` loop event
- Each trigger adds a `_PlayingInstance` to the list
- Cleanup only happens after 30 seconds
- After 8 spins within 30s → 8 instances → hits `_maxVoicesPerEvent = 8`

**Solution:** For looping events, stop existing instances before starting a new one.

**File:** `flutter_ui/lib/services/event_registry.dart`

**Changes (line ~1127):**
```dart
// FIX: For looping events, stop existing instances before starting new one
// This prevents voice accumulation (e.g., REEL_SPIN hitting limit after 8 spins)
if (event.loop) {
  final existingInstances = _playingInstances.where((i) => i.eventId == eventId).toList();
  if (existingInstances.isNotEmpty) {
    debugPrint('[EventRegistry] 🔄 Stopping ${existingInstances.length} existing loop instance(s) of "${event.name}"');
    for (final instance in existingInstances) {
      for (final voiceId in instance.voiceIds) {
        try {
          NativeFFI.instance.playbackStopOneShot(voiceId);
        } catch (_) {}
      }
    }
    _playingInstances.removeWhere((i) => i.eventId == eventId);
  }
}
```

**Result:** Looping events (REEL_SPIN, MUSIC_*, AMBIENT_*) now maintain only 1 active instance, preventing voice accumulation
