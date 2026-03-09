# Event Sync System — FluxForge Studio

## Overview

Real-time bidirectional synchronization of composite events between SlotLab, Middleware, and DAW.

**Single Source of Truth:** `MiddlewareProvider.compositeEvents`

## Architecture

```
MiddlewareProvider.compositeEvents (SSoT)
        │
   ┌────┼────┐
   ▼    ▼    ▼
SlotLab  Middleware  DAW
addListener Consumer  context.watch
```

All three sections read from `MiddlewareProvider`. Changes flow through `notifyListeners()`.

## Data Flow

### Adding a Layer

```
User drops audio → _addLayerToMiddlewareEvent(eventId, audioPath, name)
  → _middleware.addLayerToEvent(eventId, ...)
  → MiddlewareProvider updates + notifyListeners()
  → PARALLEL: SlotLab (_onMiddlewareChanged), Middleware (Consumer), DAW (context.watch)
```

### Key Sync Points

| Action | SlotLab | Middleware | DAW |
|--------|---------|------------|-----|
| Add/Remove layer | _onMiddlewareChanged → rebuild region | Consumer → layers table | watch → left panel tree |
| Create/Delete event | setState + _syncEventToRegistry | Consumer → event list | watch → Events folder |

## Provider Integration Patterns

| Method | Use Case | Rebuilds |
|--------|----------|----------|
| `Consumer<T>` | Widget subtree needs provider data | Only Consumer's builder |
| `context.watch<T>()` | Whole widget needs to rebuild | Entire widget |
| `addListener()` | Need callback for side effects | Manual via setState() |

**SlotLab** uses `addListener` because it needs side effects (`_rebuildRegionForEvent`, `_syncEventToRegistry`).
**Middleware/DAW** use `Consumer`/`watch` for pure UI rebuilds.

## Files Involved

| File | Role |
|------|------|
| `lib/providers/middleware_provider.dart` | Single source of truth for compositeEvents |
| `lib/screens/slot_lab_screen.dart` | Right panel + timeline, listens to provider |
| `lib/screens/engine_connected_layout.dart` | Left panel (DAW) + center panel (Middleware) |
| `lib/services/event_registry.dart` | Stage→Event mapping for audio triggers |

---

## EventRegistry Sync

EventRegistry is a singleton mapping stages to audio events for stage-based triggers during spins.

**CRITICAL:** Only `_syncEventToRegistry()` in `slot_lab_screen.dart` registers events. NEVER add registration elsewhere.

### Registration Rules

- Events registered under ALL `triggerStages`, not just the first
- ID format: `event.id` for first stage, `${event.id}_stage_$i` for subsequent
- Case-insensitive lookup via `.toUpperCase()`
- Sync happens AFTER provider notifies (in `_onMiddlewareChanged`), never directly after mutation

### _syncEventToRegistry Signature

```dart
void _syncEventToRegistry(SlotCompositeEvent? event)
// Converts SlotEventLayer → AudioLayer, registers under each triggerStage
```

### Deletion — Unregister All Stage Variants

```dart
void _deleteMiddlewareEvent(String eventId) {
  eventRegistry.unregisterEvent(eventId);
  for (int i = 1; i < stageCount; i++) {
    eventRegistry.unregisterEvent('${eventId}_stage_$i');
  }
  _middleware.deleteCompositeEvent(eventId);
}
```

---

## AudioLayer Model

```dart
class AudioLayer {
  final String id, audioPath, name;
  final double volume, pan, delay, offset;
  final int busId;
  final double fadeInMs, fadeOutMs, trimStartMs, trimEndMs;
}
```

**FFI paths:**
- If `hasFadeTrim`: `AudioPlaybackService.playFileToBusEx()` → `engine_playback_play_to_bus_ex()`
- Else: `AudioPlaybackService.playFileToBus()` (standard)

---

## Event Equivalence (Audio Cutoff Prevention)

`registerEvent()` compares new event with existing via `_eventsAreEquivalent()`. If identical, skips re-registration to prevent audio cutoff during unrelated UI updates. If changed, stops existing instances and updates.

---

## Fallback Stage Resolution

When a specific stage (e.g., `REEL_STOP_0`) has no event, EventRegistry falls back to generic (`REEL_STOP`).

**Priority:** Exact match → Case-insensitive → Generic fallback

**Numeric suffix patterns:** `REEL_STOP`, `CASCADE_STEP`, `WIN_LINE_SHOW/HIDE`, `SYMBOL_LAND`, `ROLLUP_TICK`, `WHEEL_TICK`, `TRAIL_MOVE_STEP`

**Symbol-specific patterns (prefix matching):** `WIN_SYMBOL_HIGHLIGHT`, `SYMBOL_WIN`, `SYMBOL_TRIGGER`, `SYMBOL_EXPAND`, `SYMBOL_TRANSFORM`

---

## Visual-Sync Callback Pattern

Audio stages trigger EXACTLY when visual events occur, via callbacks from `EmbeddedSlotMockup`:

```dart
EmbeddedSlotMockup(
  onSpinStart: () => _triggerVisualStage('SPIN_START'),
  onReelStop: (idx) => _triggerVisualStage('REEL_STOP_$idx', context: {'reel_index': idx}),
  onAnticipation: () => _triggerVisualStage('ANTICIPATION_TENSION'),
  onReveal: () => _triggerVisualStage('SPIN_END'),
  onWinStart: (winType, amount) => _triggerWinStage(winType, amount),
  onWinEnd: () => _triggerVisualStage('WIN_END'),
)
```

---

## Event Creation Flow (Current)

QuickSheet has been removed. `DropTargetWrapper` creates events directly via `MiddlewareProvider.addCompositeEvent()`.

```
Drop audio on slot element → DropTargetWrapper._handleDrop()
  → SlotCompositeEvent created directly → provider.addCompositeEvent(event)
  → notifyListeners() → _onMiddlewareChanged() → EventRegistry.registerEvent()
  → User spins → EventRegistry.triggerStage() → Audio plays
```

---

## Auto-Acquire SlotLab Section

If no playback section is active when `_playLayer()` is called, EventRegistry auto-acquires `PlaybackSection.slotLab` and ensures audio stream is running.

---

## Stage Name Mapping

### Critical Mappings

| targetId | Stage | Triggered By |
|----------|-------|-------------|
| `ui.spin` | `SPIN_START` | SlotLabProvider |
| symbol WIN context | `WIN_SYMBOL_HIGHLIGHT_*` | SlotPreviewWidget |
| per-reel | `REEL_STOP_0..4` | ProfessionalReelAnimation |

### Symbol Stage Format

`SymbolDefinition.stageName(context)` uses context-specific prefixes:
- `'win'` → `WIN_SYMBOL_HIGHLIGHT_HP1`
- `'land'` → `SYMBOL_LAND_HP1`
- `'expand'` → `SYMBOL_EXPAND_HP1`

---

## Symbol Audio Re-Registration on Mount

Symbol audio events are registered DIRECTLY to EventRegistry (not via MiddlewareProvider). On screen remount, `_syncSymbolAudioToRegistry()` iterates `SlotLabProjectProvider.symbolAudio` and re-registers all symbol events.

Called from `_initializeSlotEngine()`, runs regardless of engine init success.

---

## Pending Edit Protection Pattern

Prevents slider race condition in Middleware Inspector where provider→local sync overwrites local slider changes during debounce.

**Pattern:**
1. Set `_pendingEditEventId` when local slider change starts
2. Skip provider→local sync for that event in `_syncEventsFromProviderList()`
3. Clear flag after debounced local→provider sync completes

Applies to: Pan, Gain, Delay, Fade Time sliders.

---

## Middleware FFI Extended Chain

Two separate FFI paths for extended audio parameters:

| Section | FFI Function | Via |
|---------|-------------|-----|
| SlotLab (EventRegistry) | `playFileToBusEx()` | AudioLayer |
| Middleware (Inspector) | `middlewareAddActionEx()` | MiddlewareAction |

`middleware_add_action_ex()` accepts: gain, pan, fade_in_ms, fade_out_ms, trim_start_ms, trim_end_ms.

---

## Per-Reel Spin Loop System

| Stage Pattern | Purpose |
|---------------|---------|
| `REEL_SPINNING_START_0..4` | Start spin loop for specific reel |
| `REEL_SPINNING_STOP_0..4` | Early fade-out BEFORE visual reel stop |
| `REEL_SPINNING` / `REEL_SPIN_LOOP` | Generic shared loop (backwards compat) |

Flow: `REEL_SPINNING_START_N` → spinning → `REEL_SPINNING_STOP_N` (fade 50ms) → `REEL_STOP_N` (stop sound).

---

## CASCADE_STEP Escalation

Auto-applies pitch/volume escalation per step index:

| Step | Pitch | Volume |
|------|-------|--------|
| 0 | 1.00x | 0.90x |
| 3 | 1.15x | 1.02x |
| 5 | 1.25x | 1.10x |

Formula: pitch = 1.0 + (step * 0.05), volume = (0.9 + step * 0.04).clamp(0, 1.5)

---

## Anticipation Tension System

**Stage format:** `ANTICIPATION_TENSION_R{reelIndex}_L{tensionLevel}`

**Fallback chain:** Exact → Without level (`_R2`) → Level only (`_L3`) → Generic (`ANTICIPATION_TENSION`)

| Level | Trigger | Volume | Pitch |
|-------|---------|--------|-------|
| L1 | 2 scatters | 0.6x | +1 semitone |
| L2 | 3 scatters | 0.7x | +2 semitones |
| L3 | 4 scatters | 0.8x | +3 semitones |
| L4 | 5 scatters | 0.9x | +4 semitones |

Reference: `.claude/architecture/ANTICIPATION_SYSTEM.md`

---

## Auto Fade-Out for _END Stages

Any stage ending with `_END` (except `SPIN_END`) auto-fades all active sounds from the same prefix.

```dart
// e.g., BIG_WIN_END fades all BIG_WIN_* voices (100ms fade)
if (normalizedStage.endsWith('_END') && normalizedStage != 'SPIN_END') {
  final basePrefix = normalizedStage.substring(0, normalizedStage.length - 4);
  _autoFadeOutMatchingStages(basePrefix, fadeMs: 100);
}
```

Covers 40 of 41 `_END` stages (FREESPIN_END, CASCADE_END, BONUS_END, JACKPOT_END, etc.).

---

## Win Presentation Skip

On SKIP during win presentation:
1. STOP all active win audio (COIN_SHOWER, BIG_WIN_TICK, ROLLUP, WIN_SYMBOL_HIGHLIGHT, etc.)
2. TRIGGER END stages (ROLLUP_END, COIN_SHOWER_END, BIG_WIN_END, WIN_COLLECT, etc.)
3. FADE OUT win plaque (300ms)
4. RESET presentation state

Guard: `_winTier` set to `''` after skip. Three guard points prevent stale `.then()` callbacks.

---

## Centralized Bridge: _ensureCompositeEventForStage

All audio assignment paths (Quick Assign, Drag-drop, Mount sync) converge on one method:

```dart
void _ensureCompositeEventForStage(String stage, String audioPath)
// 1. projectProvider.setAudioAssignment() (persist)
// 2. EventRegistry.registerEvent() (runtime audio)
// 3. MiddlewareProvider.addCompositeEvent() (SSoT) — with durationSeconds from FFI
```

`durationSeconds` auto-detected via `NativeFFI.instance.getAudioFileDuration()`. Null duration = 0px timeline bars.

---

## Double-Spin Prevention

Two guard flags in `slot_preview_widget.dart`:

| Flag | Purpose |
|------|---------|
| `_spinFinalized` | Prevents re-trigger after finalize until provider finishes |
| `_lastProcessedSpinId` | Tracks which spinId was already processed |

---

## Layer Drag Fix: Absolute Positioning

Layer drag uses ABSOLUTE position (not relative to region). Controller tracks `_absoluteStartSeconds` directly from `provider.offsetMs / 1000`.

`DraggableLayerWidget.onDragStart` notifies `TimelineDragController` so `isDraggingLayer()` returns true, preventing `region.start` updates during drag (which would break the coordinate system).

---

## Event Naming Convention

`generateEventName(stage)` in `stage_group_service.dart`: 60+ custom mappings (e.g., `SPIN_START` → `onUiSpin`, `REEL_STOP_0` → `onReelLand1`).

Note: REEL_STOP uses 1-indexed event names (`onReelLand1-5`) while stages use 0-indexed (`REEL_STOP_0-4`).

---

## Batch Import — Dual-Index Number Matching

`StageGroupService` supports both 0-indexed and 1-indexed file names:
- `stop_1.wav` → REEL_STOP_0 (1-indexed first reel)
- `reel_stop_0.wav` → REEL_STOP_0 (0-indexed)

Generic REEL_STOP excludes files with reel numbers 0-5 near stop/land keywords.

---

## Stage Trigger Sources

| Stage | Source | File |
|-------|--------|------|
| `SPIN_START` | SlotLabProvider | slot_lab_provider.dart |
| `WIN_SYMBOL_HIGHLIGHT_*` | SlotPreviewWidget | slot_preview_widget.dart |
| `REEL_STOP_0..4` | ProfessionalReelAnimation | professional_reel_animation.dart |
| `WIN_PRESENT_*` | SlotPreviewWidget | slot_preview_widget.dart |
| `COIN_SHOWER_START/END` | SlotPreviewWidget | (win ratio >= 20x) |
| `BIG_WIN_TICK_START/END` | SlotPreviewWidget | (win ratio >= 20x) |

---

## Debugging Checklist

1. **EventRegistry empty?** Check for `[SlotLab] Initial sync: X events` in log
2. **Stage lookup fails?** Check for `No event for stage` — case mismatch or missing event
3. **FFI not loaded?** Rebuild Rust + copy dylibs to Frameworks AND App Bundle
4. **Playback section?** Check for `Section acquired: slotLab`
5. **Audio cutoff?** Event equivalence check should show `skipping re-registration`
6. **Slider snap-back?** Pending edit protection not working — check `_pendingEditEventId`

---

## Related Documentation

- `.claude/architecture/SLOT_LAB_SYSTEM.md` — SlotLab architecture
- `.claude/architecture/ANTICIPATION_SYSTEM.md` — Per-reel anticipation
- `.claude/architecture/UNIFIED_PLAYBACK_SYSTEM.md` — Playback section management
