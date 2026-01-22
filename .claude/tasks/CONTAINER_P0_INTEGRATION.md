# Container System P0 Integration — Implementation Plan

## Status: ✅ COMPLETED

**Created:** 2026-01-22
**Target:** Full EventRegistry → Container integration

---

## Overview

Enable `AudioEvent` to use Blend/Random/Sequence containers instead of direct layers.

### Current Flow (❌ No container support)
```
Stage → EventRegistry.triggerStage() → AudioEvent → layers[] → playback
```

### Target Flow (✅ With container support)
```
Stage → EventRegistry.triggerStage() → AudioEvent
                                            ↓
                              ┌─────────────┴─────────────┐
                              ↓                           ↓
                     event.usesContainer?           layers (direct)
                              ↓
              ┌───────────────┼───────────────┐
              ↓               ↓               ↓
           Blend          Random          Sequence
              ↓               ↓               ↓
    evaluateBlend()   selectChild()   scheduleSteps()
              ↓               ↓               ↓
        Play multi      Play one         Play timed
       with volumes    with variation    sequence
```

---

## Task List

### Task 1: AudioEvent Model Extension
**File:** `flutter_ui/lib/services/event_registry.dart`
**Status:** ✅ DONE

| Subtask | Description | Status |
|---------|-------------|--------|
| 1.1 | Add `ContainerType` enum (none/blend/random/sequence) | ✅ |
| 1.2 | Add `containerType` field to AudioEvent | ✅ |
| 1.3 | Add `containerId` field to AudioEvent | ✅ |
| 1.4 | Add `usesContainer` getter helper | ✅ |
| 1.5 | Update `toJson()` for container fields | ✅ |
| 1.6 | Update `fromJson()` for container fields | ✅ |

**Code Changes:**
```dart
// Line ~75: Add enum
enum ContainerType { none, blend, random, sequence }

// Lines 83-100: Extend AudioEvent
class AudioEvent {
  // ... existing fields ...
  final ContainerType containerType;  // NEW
  final int? containerId;             // NEW

  bool get usesContainer => containerType != ContainerType.none && containerId != null;
}
```

---

### Task 2: triggerEvent() Container Delegation
**File:** `flutter_ui/lib/services/event_registry.dart`
**Status:** ✅ DONE

| Subtask | Description | Status |
|---------|-------------|--------|
| 2.1 | Check `event.usesContainer` in triggerEvent() | ✅ |
| 2.2 | Add `_triggerViaContainer()` dispatcher method | ✅ |
| 2.3 | Add `_triggerBlendContainer()` method | ✅ |
| 2.4 | Add `_triggerRandomContainer()` method | ✅ |
| 2.5 | Add `_triggerSequenceContainer()` method | ✅ |

**Code Changes:**
```dart
// In triggerEvent() around line 1000, add:
if (event.usesContainer) {
  await _triggerViaContainer(event, context);
  notifyListeners();
  return;
}

// New method:
Future<void> _triggerViaContainer(AudioEvent event, Map<String, dynamic>? context) async {
  switch (event.containerType) {
    case ContainerType.blend:
      await _triggerBlendContainer(event.containerId!, event, context);
      break;
    case ContainerType.random:
      await _triggerRandomContainer(event.containerId!, event, context);
      break;
    case ContainerType.sequence:
      await _triggerSequenceContainer(event.containerId!, event, context);
      break;
    case ContainerType.none:
      break;
  }
}
```

---

### Task 3: ContainerService Playback Methods
**File:** `flutter_ui/lib/services/container_service.dart`
**Status:** ✅ DONE

| Subtask | Description | Status |
|---------|-------------|--------|
| 3.1 | Add `triggerBlendContainer()` — play active blend children | ✅ |
| 3.2 | Add `triggerRandomContainer()` — play selected random child | ✅ |
| 3.3 | Add `triggerSequenceContainer()` — schedule sequence steps | ✅ |
| 3.4 | Add `_playAudio()` helper | ✅ (uses AudioPlaybackService) |
| 3.5 | Add `_SequenceInstance` class for tracking | ✅ |
| 3.6 | Add `_activeSequences` map | ✅ |
| 3.7 | Add `stopSequence()` method | ✅ |
| 3.8 | Add `_handleSequenceEnd()` for loop/hold/pingPong | ✅ |

**Key Signatures:**
```dart
Future<List<int>> triggerBlendContainer(int containerId, {required String busId, Map<String, dynamic>? context});
Future<int> triggerRandomContainer(int containerId, {required String busId, Map<String, dynamic>? context});
Future<int> triggerSequenceContainer(int containerId, {required String busId, Map<String, dynamic>? context});
void stopSequence(int instanceId);
```

---

### Task 4: EventRegistry Integration
**File:** `flutter_ui/lib/services/event_registry.dart`
**Status:** ✅ DONE

| Subtask | Description | Status |
|---------|-------------|--------|
| 4.1 | Import `container_service.dart` | ✅ |
| 4.2 | Implement `_triggerBlendContainer()` body | ✅ (via _triggerViaContainer) |
| 4.3 | Implement `_triggerRandomContainer()` body | ✅ (via _triggerViaContainer) |
| 4.4 | Implement `_triggerSequenceContainer()` body | ✅ (via _triggerViaContainer) |
| 4.5 | Update `_lastTriggeredLayers` for container info | ✅ |

---

### Task 5: Container Child Audio Linking (Prerequisite Fix)
**File:** `flutter_ui/lib/models/middleware_models.dart`
**Status:** ✅ DONE

**Problem:** BlendChild, RandomChild, SequenceStep nemaju `audioPath` polje — koriste samo `name`.

| Subtask | Description | Status |
|---------|-------------|--------|
| 5.1 | Add `audioPath` field to BlendChild | ✅ |
| 5.2 | Add `audioPath` field to RandomChild | ✅ |
| 5.3 | Add `audioPath` field to SequenceStep | ✅ |
| 5.4 | Update toJson/fromJson for all three | ✅ |
| 5.5 | Update UI panels to set audioPath | ⏳ (P1 task) |

---

## Dependencies

```
Task 5 (Audio Linking) ←─┐
                         │
Task 1 (Model) ──────────┼──→ Task 2 (Delegation) ──→ Task 4 (Integration)
                         │
Task 3 (Playback) ───────┘
```

**Order:** 5 → 1 → 3 → 2 → 4

---

## File Change Summary

| File | Changes | LOC Est. |
|------|---------|----------|
| `middleware_models.dart` | Add audioPath to 3 classes | +30 |
| `event_registry.dart` | ContainerType, AudioEvent ext, delegation | +150 |
| `container_service.dart` | 3 trigger methods, helpers, state | +200 |
| **TOTAL** | | **~380** |

---

## Test Plan

### Test 1: BlendContainer Integration
```dart
// Create blend container with 2 children
final container = BlendContainer(
  id: 1,
  name: 'Test Blend',
  rtpcId: 1, // WinAmount RTPC
  children: [
    BlendChild(id: 1, name: 'small_win', audioPath: '/audio/small_win.wav', rtpcStart: 0.0, rtpcEnd: 0.5),
    BlendChild(id: 2, name: 'big_win', audioPath: '/audio/big_win.wav', rtpcStart: 0.5, rtpcEnd: 1.0),
  ],
);

// Create event using container
final event = AudioEvent(
  id: 'win_sound',
  name: 'Win Sound',
  stage: 'WIN_PRESENT',
  layers: [], // Empty - uses container
  containerType: ContainerType.blend,
  containerId: 1,
);

// Test: RTPC at 0.25 → only small_win plays
// Test: RTPC at 0.75 → only big_win plays
// Test: RTPC at 0.5 → both play with crossfade volumes
```

### Test 2: RandomContainer Integration
```dart
// Create random container
final container = RandomContainer(
  id: 2,
  name: 'Footstep Variations',
  mode: RandomMode.shuffleWithHistory,
  avoidRepeatCount: 2,
  children: [
    RandomChild(id: 1, name: 'step1', audioPath: '/audio/step1.wav', weight: 1.0),
    RandomChild(id: 2, name: 'step2', audioPath: '/audio/step2.wav', weight: 1.0),
    RandomChild(id: 3, name: 'step3', audioPath: '/audio/step3.wav', weight: 1.0),
  ],
);

// Create event
final event = AudioEvent(
  id: 'footstep',
  name: 'Footstep',
  stage: 'PLAYER_STEP',
  layers: [],
  containerType: ContainerType.random,
  containerId: 2,
);

// Test: Trigger 10x → no immediate repeats (shuffleWithHistory)
```

### Test 3: SequenceContainer Integration
```dart
// Create sequence container
final container = SequenceContainer(
  id: 3,
  name: 'Jackpot Sequence',
  endBehavior: SequenceEndBehavior.stop,
  speed: 1.0,
  steps: [
    SequenceStep(index: 0, childId: 1, childName: 'fanfare', audioPath: '/audio/fanfare.wav', delayMs: 0),
    SequenceStep(index: 1, childId: 2, childName: 'coins', audioPath: '/audio/coins.wav', delayMs: 500),
    SequenceStep(index: 2, childId: 3, childName: 'voice', audioPath: '/audio/jackpot_vo.wav', delayMs: 1000),
  ],
);

// Create event
final event = AudioEvent(
  id: 'jackpot_win',
  name: 'Jackpot Win',
  stage: 'JACKPOT_GRAND',
  layers: [],
  containerType: ContainerType.sequence,
  containerId: 3,
);

// Test: Trigger → 3 sounds play at 0ms, 500ms, 1000ms
```

---

## Verification Commands

```bash
# After implementation:
cd flutter_ui && flutter analyze
# Must pass with 0 errors

# Runtime test:
# 1. Open SlotLab
# 2. Create container via Middleware panel
# 3. Create event with containerType set
# 4. Trigger stage → verify container playback
```

---

## Notes

- **Backwards Compatible:** Events with `containerType: none` (default) use existing layer playback
- **Container Priority:** Container playback ignores `layers[]` array completely
- **UI Update:** Event editor panel needs container type/ID fields (P1 task)
- **FFI Future:** Container logic is Dart-only; Rust FFI for P2 optimization

---

## Completion Checklist

- [x] Task 5: Audio path fields added to child classes
- [x] Task 1: AudioEvent extended with container fields
- [x] Task 3: ContainerService playback methods added
- [x] Task 2: triggerEvent() delegation added
- [x] Task 4: EventRegistry integration complete
- [x] `flutter analyze` passes
- [ ] Manual test: Blend container plays
- [ ] Manual test: Random container plays
- [ ] Manual test: Sequence container plays
