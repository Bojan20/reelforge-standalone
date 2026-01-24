# P1.1: QuickSheet → Event Creation Flow Analysis

**Date:** 2026-01-24
**Status:** ✅ VERIFIED WORKING
**Priority:** P1 (High)

---

## Executive Summary

The QuickSheet drag-drop event creation system is **fully functional**. Audio files dropped on mockup elements correctly create composite events that trigger audio during gameplay.

---

## Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. USER DRAG-DROP                                                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   AudioBrowserPanel          DropTargetWrapper (mockup element)             │
│   ┌──────────────┐           ┌─────────────────────────────────┐            │
│   │ 🎵 audio.wav │ ──DRAG──▶ │ SPIN button / Reel zone / etc.  │            │
│   └──────────────┘           └─────────────────────────────────┘            │
│                                         │                                    │
│                                         ▼                                    │
│                          DragTarget.onAcceptWithDetails()                   │
│                                         │                                    │
│                                         ▼                                    │
│                    _handleDrop(asset, globalPosition, provider)             │
│                        [drop_target_wrapper.dart:118-149]                   │
│                                         │                                    │
│                                         │ (Does NOT call createDraft!)      │
│                                         │                                    │
└─────────────────────────────────────────┼───────────────────────────────────┘
                                          │
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 2. QUICKSHEET POPUP                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   showQuickSheet() [quick_sheet.dart:26-89]                                 │
│         │                                                                    │
│         ▼ (line 37 — ONLY place createDraft is called)                      │
│   AutoEventBuilderProvider.createDraft(asset, target)                       │
│         │ [auto_event_builder_provider.dart:712-748]                        │
│         │                                                                    │
│         ├── EventNamingService.generateEventName()  → "onUiPaSpinButton"    │
│         ├── AudioContextService.determineAutoAction() → Play/Stop           │
│         ├── _findMatchingRule() → DropRule for bus/trigger                  │
│         ├── _ensureUniqueEventId() → GAP 26 FIX                             │
│         └── Creates EventDraft                                              │
│                                                                              │
│   ┌──────────────────────────────────┐                                      │
│   │ QuickSheet Popup                 │                                      │
│   │ ┌────────────────────────────┐  │                                      │
│   │ │ Event: onUiPaSpinButton    │  │  ← Editable name (TextField)         │
│   │ │ Trigger: press             │  │  ← Dropdown                          │
│   │ │ Action: ▶ PLAY             │  │  ← Auto-detected (green/red badge)   │
│   │ │ Bus: SFX/UI                │  │  ← Readonly                          │
│   │ └────────────────────────────┘  │                                      │
│   │ [More... Tab] [Cancel Esc] [Commit ↵]                                  │
│   └──────────────────────────────────┘                                      │
│                  │                                                           │
│                  ▼ (Enter key or Commit button → onCommit callback)         │
│   DropTargetWrapper.onCommit callback [drop_target_wrapper.dart:131-145]    │
│         │                                                                    │
│         ▼ (line 132 — ONLY place commitDraft is called)                     │
│   AutoEventBuilderProvider.commitDraft()                                    │
│         │ [auto_event_builder_provider.dart:780-843]                        │
│         │                                                                    │
│         ├── Creates CommittedEvent (with pan, spatial mode)                 │
│         ├── Creates EventBinding (target→event link)                       │
│         ├── Adds to _events and _bindings lists                            │
│         ├── markAssetUsed() for recent assets                               │
│         └── Returns CommittedEvent                                          │
│                                                                              │
│   [Audio preview plays as confirmation feedback - line 138-142]            │
│                                                                              │
└─────────────────────────────────────────┼───────────────────────────────────┘
                                          │
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 3. BRIDGE TO MIDDLEWARE (SSoT)                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   DropTargetWrapper.onEventCreated(CommittedEvent)                          │
│         │                                                                    │
│         ▼                                                                    │
│   slot_lab_screen._onEventBuilderEventCreated(event, targetId)              │
│         │                                                                    │
│         ├── _targetIdToStage(targetId) → "SPIN_START"                       │
│         ├── _busNameToId(event.bus) → 0 (UI bus)                           │
│         ├── _calculatePanFromTarget(targetId) → per-reel pan               │
│         │                                                                    │
│         ├── Creates SlotEventLayer:                                         │
│         │     - audioPath, volume, pan, offsetMs                           │
│         │     - fadeInMs, fadeOutMs, busId                                 │
│         │                                                                    │
│         ├── Creates SlotCompositeEvent:                                     │
│         │     - id, name, category, color                                  │
│         │     - layers: [SlotEventLayer]                                   │
│         │     - looping: StageConfigurationService.isLooping(stage)        │
│         │     - triggerStages: [stage]                                     │
│         │                                                                    │
│         └── _middleware.addCompositeEvent(compositeEvent, select: true)    │
│                    │                                                         │
│                    ▼                                                         │
│              MiddlewareProvider (SINGLE SOURCE OF TRUTH)                    │
│                    │                                                         │
│                    └── notifyListeners()                                    │
│                                                                              │
└─────────────────────────────────────────┼───────────────────────────────────┘
                                          │
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 4. BIDIRECTIONAL SYNC                                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   slot_lab_screen._onMiddlewareChanged() [listener]                         │
│         │                                                                    │
│         ├── for each event in _compositeEvents:                             │
│         │     ├── _rebuildRegionForEvent(event) → Timeline UI              │
│         │     └── _syncEventToRegistry(event) → EventRegistry              │
│         │                                                                    │
│         └── _syncLayersToTrackManager() → DAW-style tracks                 │
│                                                                              │
└─────────────────────────────────────────┼───────────────────────────────────┘
                                          │
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 5. EVENT REGISTRY REGISTRATION                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   _syncEventToRegistry(SlotCompositeEvent event)                            │
│         │                                                                    │
│         ├── Normalize stages to UPPERCASE                                   │
│         ├── For each triggerStage:                                          │
│         │     ├── Create AudioEvent with AudioLayers                       │
│         │     └── eventRegistry.registerEvent(audioEvent)                  │
│         │                                                                    │
│         └── Debug: "✅ Registered 'Event Name' under N stage(s)"           │
│                                                                              │
└─────────────────────────────────────────┼───────────────────────────────────┘
                                          │
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 6. AUDIO PLAYBACK (when spin happens)                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   SlotLabProvider.spin()                                                    │
│         │                                                                    │
│         └── _triggerStage("SPIN_START")                                    │
│                    │                                                         │
│                    ▼                                                         │
│              EventRegistry.triggerStage("SPIN_START")                       │
│                    │                                                         │
│                    ├── Find AudioEvent for stage (case-insensitive)        │
│                    ├── triggerEvent(event)                                 │
│                    │     └── for each layer: _playLayer()                  │
│                    └── _playLayer(layer):                                  │
│                          ├── Apply delay                                   │
│                          ├── Apply RTPC modulation                         │
│                          ├── Notify DuckingService                         │
│                          └── AudioPlaybackService.playFileToBus()          │
│                                    │                                         │
│                                    ▼                                         │
│                              🔊 AUDIO OUTPUT                                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Components

### 1. AutoEventBuilderProvider

**File:** `flutter_ui/lib/providers/auto_event_builder_provider.dart` (~2548 LOC)

| Method | Line | Purpose |
|--------|------|---------|
| `createDraft(asset, target)` | 712-748 | Creates EventDraft with semantic naming, auto-action detection |
| `commitDraft()` | 780-843 | Creates CommittedEvent + EventBinding, adds to internal lists |
| `_findMatchingRule()` | 2160-2168 | Matches asset/target to DropRule for bus/trigger defaults |
| `_calculateSpatialParams()` | 2125-2150 | Per-reel stereo panning (reel 0=-0.8, reel 4=+0.8) |
| `_ensureUniqueEventId()` | 2171-2181 | GAP 26 FIX: Ensures unique event IDs |

### 2. DropTargetWrapper

**File:** `flutter_ui/lib/widgets/slot_lab/auto_event_builder/drop_target_wrapper.dart` (~604 LOC)

| Method/Callback | Line | Purpose |
|-----------------|------|---------|
| `_handleDrop()` | 118-149 | Shows QuickSheet popup, does NOT call createDraft (showQuickSheet does) |
| `onEventCreated` | 39 | Callback after commitDraft(), passes CommittedEvent to parent |
| `_pathToAudioAsset()` | 152-168 | Converts String path to AudioAsset for String drag data |

**CRITICAL Note (lines 119-121):**
```dart
// NOTE: Don't call createDraft() here!
// showQuickSheet() handles draft creation internally to avoid double-create issues.
// The draft is created ONCE in showQuickSheet() and committed via onCommit callback.
```

### 3. QuickSheet

**File:** `flutter_ui/lib/widgets/slot_lab/auto_event_builder/quick_sheet.dart` (~733 LOC)

| Feature | Line | Details |
|---------|------|---------|
| `showQuickSheet()` | 26-89 | Entry point, calls `provider.createDraft()` at line 37 |
| Event name | 288-336 | Editable TextField with semantic default (`_buildEventIdPreview`) |
| Action type | 401-457 | Auto-detected via AudioContextService (Play=green, Stop=red) |
| Trigger dropdown | 338-368 | Dropdown from target's available triggers |
| Keyboard | 163-185 | Enter=commit, Esc=cancel, Tab=expand to Command Builder |

**CRITICAL Note (lines 64-66):**
```dart
// NOTE: Don't call commitDraft() here!
// The onCommit callback (from DropTargetWrapper) handles commitDraft
// to properly capture the returned CommittedEvent.
```

### 4. Bridge Function

**File:** `flutter_ui/lib/screens/slot_lab_screen.dart:6835-6897`

```dart
void _onEventBuilderEventCreated(CommittedEvent event, String targetId) {
  // 1. Extract filename and generate event name
  final fileName = event.assetPath.split('/').last;
  final eventName = _generateEventNameFromTarget(targetId, fileName);

  // 2. Map targetId → stage
  final stage = _targetIdToStage(targetId);

  // 3. Map bus name to bus ID
  final busId = _busNameToId(event.bus);

  // 4. Calculate pan from target (per-reel spatial positioning)
  final pan = _calculatePanFromTarget(targetId, event.pan);

  // 5. Create SlotEventLayer
  final layer = SlotEventLayer(
    id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
    name: fileName,
    audioPath: event.assetPath,
    volume: (event.parameters['volume'] as double?) ?? 1.0,
    pan: pan,
    offsetMs: (event.parameters['delayMs'] as double?) ?? 0.0,
    fadeInMs: ..., fadeOutMs: ...,
    muted: false, solo: false,
    busId: busId,
  );

  // 6. Create SlotCompositeEvent
  final shouldLoop = StageConfigurationService.instance.isLooping(stage);
  final compositeEvent = SlotCompositeEvent(
    id: event.eventId,
    name: eventName,
    category: _categoryFromTargetId(targetId),
    color: _colorFromTargetId(targetId),
    layers: [layer],
    looping: shouldLoop,
    maxInstances: shouldLoop ? 1 : 4,
    triggerStages: [stage],
  );

  // 7. Add to SSoT (triggers _onMiddlewareChanged)
  _middleware.addCompositeEvent(compositeEvent, select: true);
}
```

### 5. EventRegistry Sync

**File:** `flutter_ui/lib/screens/slot_lab_screen.dart:9269-9342`

```dart
void _syncEventToRegistry(SlotCompositeEvent? event) {
  if (event == null) return;

  // CRITICAL: Normalize to UPPERCASE — SlotLabProvider triggers with .toUpperCase()
  final stages = event.triggerStages.isNotEmpty
      ? event.triggerStages.map((s) => s.toUpperCase()).toList()
      : [_getEventStage(event).toUpperCase()];

  // Skip if no layers (nothing to play)
  if (event.layers.isEmpty) return;

  // Build base layers list once
  final layers = event.layers.map((l) => AudioLayer(
    id: l.id,
    audioPath: l.audioPath,
    name: l.name,
    volume: l.volume,
    pan: l.pan,
    delay: l.offsetMs,
    busId: l.busId ?? 2,
  )).toList();

  // Register event under EACH trigger stage
  for (int i = 0; i < stages.length; i++) {
    final stage = stages[i];
    final eventId = i == 0 ? event.id : '${event.id}_stage_$i';
    // ... register AudioEvent with eventRegistry.registerEvent()
  }
}
```

---

## Important Design Decisions

### 1. Single Source of Truth

**MiddlewareProvider.compositeEvents** is the SSoT for all composite events.

```
AutoEventBuilderProvider → MiddlewareProvider ← Middleware Panel
        ↓                         ↓                    ↓
   (creates draft)           (stores events)     (edits events)
                                  ↓
                         _onMiddlewareChanged()
                                  ↓
    ┌─────────────────────────────┼─────────────────────────────┐
    ↓                             ↓                             ↓
Timeline UI              EventRegistry                   Events Panel
```

### 2. Per-Reel Spatial Panning

```dart
// In _calculateSpatialParams():
// Reel 0 → pan -0.8 (left)
// Reel 1 → pan -0.4
// Reel 2 → pan  0.0 (center)
// Reel 3 → pan +0.4
// Reel 4 → pan +0.8 (right)
final pan = (reelIndex - 2) * 0.4;
```

### 3. Auto-Action Detection

**AudioContextService** analyzes file name + stage to determine Play vs Stop:

| Audio Type | Stage Type | Action |
|------------|------------|--------|
| SFX/Voice | Any | PLAY |
| Music | Entry (_TRIGGER, _ENTER) + same context | PLAY |
| Music | Entry + different context | STOP (stop old music) |
| Music | Exit (_EXIT, _END) | STOP |

### 4. Looping Detection

**StageConfigurationService.isLooping()** determines if audio should loop:

```
REEL_SPIN_LOOP → true
MUSIC_BASE → true
SPIN_START → false
WIN_BIG → false
```

---

## Verification Checklist

- [x] Drop audio on SPIN button → QuickSheet appears
- [x] Event name is semantic (e.g., "onUiPaSpinButton")
- [x] Action type auto-detected (Play for SFX)
- [x] Commit creates event in MiddlewareProvider
- [x] Event appears in Events Panel (right side)
- [x] Event registered in EventRegistry
- [x] Spin triggers audio playback

---

## Known Issues (NONE)

The flow is complete and working as designed.

---

## Files Involved

| File | LOC | Role |
|------|-----|------|
| `auto_event_builder_provider.dart` | ~2548 | Draft/commit logic, rule matching, undo/redo |
| `drop_target_wrapper.dart` | ~604 | DragTarget wrapper with glow feedback, QuickSheet trigger |
| `quick_sheet.dart` | ~733 | Popup menu for event configuration, keyboard shortcuts |
| `slot_lab_screen.dart` | ~9500 | Bridge function (6835), EventRegistry sync (9269) |
| `middleware_provider.dart` | ~3800 | SSoT for composite events |
| `event_registry.dart` | ~1350 | Stage→Audio mapping for playback |
| `audio_playback_service.dart` | ~800 | FFI audio playback |
| `event_naming_service.dart` | ~650 | Semantic event name generation |
| `audio_context_service.dart` | ~310 | Auto-action (Play/Stop) detection |
| `stage_configuration_service.dart` | ~650 | Stage config (looping, priority, bus) |

---

## Recommendation

No fixes required. The system is functioning correctly as designed.

---

## Verification History

| Date | Status | Notes |
|------|--------|-------|
| 2026-01-24 | ✅ VERIFIED | Initial analysis — flow diagram matches code |
| 2026-01-24 | ✅ UPDATED | Line numbers verified against actual source files |

## Key Line Numbers Reference

| Component | Method | Line |
|-----------|--------|------|
| quick_sheet.dart | `showQuickSheet()` | 26-89 |
| quick_sheet.dart | `provider.createDraft()` call | 37 |
| drop_target_wrapper.dart | `_handleDrop()` | 118-149 |
| drop_target_wrapper.dart | `provider.commitDraft()` call | 132 |
| auto_event_builder_provider.dart | `createDraft()` | 712-748 |
| auto_event_builder_provider.dart | `commitDraft()` | 780-843 |
| auto_event_builder_provider.dart | `_findMatchingRule()` | 2160-2168 |
| auto_event_builder_provider.dart | `_calculateSpatialParams()` | 2125-2150 |
| slot_lab_screen.dart | `_onEventBuilderEventCreated()` | 6835-6897 |
| slot_lab_screen.dart | `_syncEventToRegistry()` | 9269-9342 |
| slot_lab_screen.dart | `_onMiddlewareChanged()` | 757-786 |
