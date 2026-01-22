# Container System P1 UI Integration — Implementation Plan

## Status: ✅ COMPLETED

**Created:** 2026-01-22
**Completed:** 2026-01-22
**Depends on:** P0 (COMPLETED)
**Target:** UI for container audioPath and event→container binding

---

## Overview

P0 je implementirao backend integraciju. P1 dodaje UI elemente:
1. Audio file picker za container child elemente (BlendChild, RandomChild, SequenceStep)
2. Container selector u Event Editor panelu
3. Visual feedback za container-based evente u Event Log

---

## Task List

### Task 1: Container Child Audio Picker UI
**Files:**
- `flutter_ui/lib/widgets/middleware/blend_container_panel.dart`
- `flutter_ui/lib/widgets/middleware/random_container_panel.dart`
- `flutter_ui/lib/widgets/middleware/sequence_container_panel.dart`
**Status:** ✅ DONE

| Subtask | Description | Status |
|---------|-------------|--------|
| 1.1 | Add audioPath field display to BlendChild row | ✅ |
| 1.2 | Add file picker button for BlendChild | ✅ |
| 1.3 | Add audioPath field display to RandomChild row | ✅ |
| 1.4 | Add file picker button for RandomChild | ✅ |
| 1.5 | Add audioPath field display to SequenceStep row | ✅ |
| 1.6 | Add file picker button for SequenceStep | ✅ |
| 1.7 | Wire up file picker to update model via provider | ✅ |

**Implementation:**
- Added `_buildAudioPathRow()` widget to each panel
- Uses `file_picker` package for audio file selection
- Shows filename, green border when audio assigned
- Clear button to remove audio path
- Wired to provider `updateChildAudioPath()` / `updateStepAudioPath()` methods

---

### Task 2: Event Editor Container Selector
**File:** `flutter_ui/lib/screens/slot_lab_screen.dart` (in `_buildCompositeEventContent`)
**Status:** ✅ DONE

| Subtask | Description | Status |
|---------|-------------|--------|
| 2.1 | Add ContainerType dropdown selector | ✅ |
| 2.2 | Add Container ID dropdown (filtered by type) | ✅ |
| 2.3 | Show "Direct Layers" vs "Container" mode toggle | ✅ |
| 2.4 | Disable layers list when container mode active | ✅ |
| 2.5 | Wire up to SlotCompositeEvent.copyWith() | ✅ |

**Implementation:**
- Added `containerType` and `containerId` fields to `SlotCompositeEvent` model
- Added `_buildContainerSelector()` widget with radio toggle (Direct Layers / Use Container)
- Added container type dropdown and container ID dropdown (filtered by type)
- Added `_buildContainerInfo()` widget showing container name and child count
- Layers hidden when container mode active

---

### Task 3: Event Log Container Feedback
**File:** `flutter_ui/lib/widgets/slot_lab/event_log_panel.dart`
**Status:** ✅ DONE

| Subtask | Description | Status |
|---------|-------------|--------|
| 3.1 | Show container icon for container-based events | ✅ |
| 3.2 | Display container type in log entry | ✅ |
| 3.3 | Show child count for blend/random | ✅ |
| 3.4 | Show step count for sequence | ✅ |

**Implementation:**
- Added `containerType`, `containerName`, `containerChildCount` to `EventLogEntry`
- Added `_buildContainerBadge()` widget with color-coded badge (purple=Blend, amber=Random, teal=Sequence)
- EventRegistry tracks container info: `lastContainerType`, `lastContainerName`, `lastContainerChildCount`
- Container info passed to log entry when event uses container

---

### Task 4: Provider Updates for Child audioPath
**Files:**
- `flutter_ui/lib/providers/subsystems/blend_containers_provider.dart`
- `flutter_ui/lib/providers/subsystems/random_containers_provider.dart`
- `flutter_ui/lib/providers/subsystems/sequence_containers_provider.dart`
**Status:** ✅ DONE

| Subtask | Description | Status |
|---------|-------------|--------|
| 4.1 | Add `updateBlendChildAudioPath(containerId, childId, path)` | ✅ |
| 4.2 | Add `updateRandomChildAudioPath(containerId, childId, path)` | ✅ |
| 4.3 | Add `updateSequenceStepAudioPath(containerId, stepIndex, path)` | ✅ |
| 4.4 | Ensure JSON persistence includes audioPath | ✅ |

**Implementation:**
- All three providers have `updateChildAudioPath()` / `updateStepAudioPath()` methods
- Methods update model via `copyWith()`, sync to FFI, and `notifyListeners()`
- `audioPath` already included in model `toJson()`/`fromJson()` (from P0)

---

## Dependencies

```
P0 (COMPLETED) ──→ Task 4 (Providers) ──→ Task 1 (Child UI)
                         │
                         └──→ Task 2 (Event Editor)
                         │
                         └──→ Task 3 (Event Log)
```

**Order:** 4 → 1 → 2 → 3 ✅

---

## File Change Summary

| File | Changes | LOC |
|------|---------|-----|
| `blend_container_panel.dart` | Add audioPath row + picker | +70 |
| `random_container_panel.dart` | Add audioPath row + picker | +70 |
| `sequence_container_panel.dart` | Add audioPath row + picker | +70 |
| `slot_lab_screen.dart` | Container selector UI + container info | +200 |
| `event_log_panel.dart` | Container badge + container fields | +80 |
| `event_registry.dart` | Container tracking fields | +20 |
| `container_service.dart` | Getter methods for containers | +10 |
| `slot_audio_events.dart` | containerType/containerId fields | +30 |
| `blend_containers_provider.dart` | updateChildAudioPath | +15 |
| `random_containers_provider.dart` | updateChildAudioPath | +15 |
| `sequence_containers_provider.dart` | updateStepAudioPath | +15 |
| **TOTAL** | | **~595** |

---

## Completion Checklist

- [x] Task 4: Provider methods for audioPath updates
- [x] Task 1: Container child panels have audio picker
- [x] Task 2: Event editor has container selector
- [x] Task 3: Event log shows container info
- [x] `flutter analyze` passes
- [ ] Manual test: Set audioPath via UI, verify playback
