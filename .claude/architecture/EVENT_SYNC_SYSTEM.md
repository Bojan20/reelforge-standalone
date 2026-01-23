# Event Sync System — FluxForge Studio

## Overview

Real-time bidirectional synchronization of composite events between all three sections: SlotLab, Middleware, and DAW.

**Single Source of Truth:** `MiddlewareProvider.compositeEvents`

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         EVENT SYNC ARCHITECTURE                              │
│                                                                              │
│                    MiddlewareProvider.compositeEvents                        │
│                         (Single Source of Truth)                             │
│                                  │                                           │
│          ┌───────────────────────┼───────────────────────┐                  │
│          │                       │                       │                  │
│          ▼                       ▼                       ▼                  │
│   ┌─────────────┐        ┌─────────────┐        ┌─────────────┐            │
│   │   SLOT LAB  │        │  MIDDLEWARE │        │     DAW     │            │
│   ├─────────────┤        ├─────────────┤        ├─────────────┤            │
│   │ Consumer<>  │        │ Consumer<>  │        │context.watch│            │
│   │ Right Panel │        │Center Panel │        │ Left Panel  │            │
│   │ + Timeline  │        │LayersTable  │        │Events Folder│            │
│   └─────────────┘        └─────────────┘        └─────────────┘            │
│          │                       │                       │                  │
│          └───────────────────────┼───────────────────────┘                  │
│                                  │                                           │
│                    notifyListeners() triggers rebuild                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### Adding a Layer in SlotLab

```
1. User drops audio on event in right panel
   ↓
2. _addLayerToEvent(event, audioPath)
   ↓
3. _addLayerToMiddlewareEvent(eventId, audioPath, name)
   ↓
4. _middleware.addLayerToEvent(eventId, ...)
   ↓
5. MiddlewareProvider:
   - _compositeEvents[eventId] = updated
   - _syncCompositeToMiddleware(updated)
   - notifyListeners()
   ↓
6. PARALLEL UPDATES:
   ├─ SlotLab: _onMiddlewareChanged()
   │   → _rebuildRegionForEvent(event)
   │   → _syncEventToRegistry(event)
   │   → setState()
   │
   ├─ Middleware: Consumer rebuilds
   │   → _buildLayersAsActionsTable(selectedComposite)
   │
   └─ DAW: context.watch triggers
       → _buildProjectTree(compositeEvents)
       → Shows updated layer count
```

### Key Sync Points

| Action | SlotLab | Middleware | DAW |
|--------|---------|------------|-----|
| Add layer | _onMiddlewareChanged → rebuild region | Consumer → layers table | watch → left panel tree |
| Remove layer | _onMiddlewareChanged → rebuild region | Consumer → layers table | watch → left panel tree |
| Create event | setState + _syncEventToRegistry | Consumer → event list | watch → Events folder |
| Delete event | MiddlewareProvider removes | Consumer → event list | watch → Events folder |

---

## Provider Integration

### SlotLab Screen

```dart
// Getter for compositeEvents - reads from provider
List<SlotCompositeEvent> get _compositeEvents => _middleware.compositeEvents;

// Listener registered in initState
_middleware.addListener(_onMiddlewareChanged);

// Callback syncs EventRegistry and rebuilds regions
void _onMiddlewareChanged() {
  if (mounted) {
    for (final event in _compositeEvents) {
      _rebuildRegionForEvent(event);
      _syncEventToRegistry(event);  // For stage-based audio triggers
    }
    setState(() {});
  }
}
```

### Middleware Center Panel (engine_connected_layout.dart)

```dart
Widget _buildMiddlewareCenterContent() {
  return Consumer<MiddlewareProvider>(
    builder: (context, middleware, _) {
      final selectedCompositeId = middleware.selectedCompositeEventId;
      final compositeEvents = middleware.compositeEvents;

      final selectedComposite = selectedCompositeId != null
          ? compositeEvents.where((e) => e.id == selectedCompositeId).firstOrNull
          : null;

      // ... build layers table with selectedComposite.layers
    },
  );
}
```

### DAW Left Panel

```dart
@override
Widget build(BuildContext context) {
  // Watch triggers rebuild on any change
  final middlewareProvider = context.watch<MiddlewareProvider>();

  // Pass compositeEvents to tree builder
  projectTree: _buildProjectTree(middlewareProvider.compositeEvents),
}

List<ProjectTreeNode> _buildProjectTree(List<SlotCompositeEvent> compositeEvents) {
  // Events folder shows layer count from compositeEvents
  children: compositeEvents.map((event) => ProjectTreeNode(
    label: '${event.name} (${event.layers.length})',
  )).toList(),
}
```

---

## Critical Implementation Details

### Timing Issue Fix (2026-01-21)

**Problem:** When adding layers, `_syncEventToRegistry` was called immediately after `_middleware.addLayerToEvent`, but the provider hadn't notified listeners yet. This caused stale data to be synced.

**Solution:** Remove direct sync calls from mutation methods. Let `_onMiddlewareChanged` listener handle sync AFTER provider notifies.

```dart
// BEFORE (broken)
void _addLayerToMiddlewareEvent(String eventId, String audioPath, String name) {
  _middleware.addLayerToEvent(eventId, audioPath: audioPath, name: name);
  _syncEventToRegistry(_findEventById(eventId));  // ❌ Stale data!
}

// AFTER (fixed)
void _addLayerToMiddlewareEvent(String eventId, String audioPath, String name) {
  _middleware.addLayerToEvent(eventId, audioPath: audioPath, name: name);
  // ✅ _onMiddlewareChanged will sync with fresh data after notifyListeners()
}
```

### EventRegistry Sync

EventRegistry is a separate singleton that maps stages to audio events. It must be kept in sync for stage-based audio triggers during slot spins.

**CRITICAL (2026-01-21):** Events are now registered under ALL `triggerStages`, not just the first one. This allows one composite event to be triggered by multiple stages.

```dart
void _syncEventToRegistry(SlotCompositeEvent? event) {
  if (event == null) return;

  // Get ALL trigger stages (or derive from category if empty)
  final stages = event.triggerStages.isNotEmpty
      ? event.triggerStages
      : [_getEventStage(event)];

  final layers = event.layers.map((l) => AudioLayer(...)).toList();

  // Register under EACH trigger stage with unique ID
  for (int i = 0; i < stages.length; i++) {
    final stage = stages[i];
    final eventId = i == 0 ? event.id : '${event.id}_stage_$i';

    final audioEvent = AudioEvent(
      id: eventId,
      name: event.name,
      stage: stage,
      layers: layers,
    );
    eventRegistry.registerEvent(audioEvent);
  }
}
```

When deleting events, ALL stage variants must be unregistered:

```dart
void _deleteMiddlewareEvent(String eventId) {
  final event = _findEventById(eventId);
  final stageCount = event?.triggerStages.length ?? 1;

  // Unregister base event + all stage variants
  eventRegistry.unregisterEvent(eventId);
  for (int i = 1; i < stageCount; i++) {
    eventRegistry.unregisterEvent('${eventId}_stage_$i');
  }
  _middleware.deleteCompositeEvent(eventId);
}
```

---

## Files Involved

| File | Role |
|------|------|
| `lib/providers/middleware_provider.dart` | Single source of truth for compositeEvents |
| `lib/screens/slot_lab_screen.dart` | Right panel + timeline, listens to provider |
| `lib/screens/engine_connected_layout.dart` | Left panel (DAW) + center panel (Middleware) |
| `lib/services/event_registry.dart` | Stage→Event mapping for audio triggers |
| `lib/services/event_sync_service.dart` | Legacy bidirectional sync (partially deprecated) |

---

## Consumer vs context.watch vs addListener

| Method | Use Case | Rebuilds |
|--------|----------|----------|
| `Consumer<T>` | Widget subtree needs provider data | Only Consumer's builder |
| `context.watch<T>()` | Whole widget needs to rebuild | Entire widget |
| `addListener()` | Need callback for side effects | Manual via setState() |

### SlotLab uses addListener because:
- Needs to call `_rebuildRegionForEvent()` (side effect)
- Needs to call `_syncEventToRegistry()` (side effect)
- These aren't just UI rebuilds

### Middleware/DAW use Consumer/watch because:
- Just need UI to reflect current data
- No additional side effects needed

---

## Debugging

### Check if events are syncing:

```dart
// In MiddlewareProvider
debugPrint('[Middleware] addLayerToEvent: "${updated.name}" now has ${updated.layers.length} layers');

// In SlotLab
debugPrint('[SlotLab] Synced ${_compositeEvents.length} events from MiddlewareProvider');

// In engine_connected_layout build()
debugPrint('[DAW] Building tree with ${compositeEvents.length} events');
```

### Common issues:

1. **Layer not appearing:** Check if `notifyListeners()` is called in provider
2. **Stale data:** Ensure sync happens AFTER provider update, not before
3. **UI not updating:** Verify Consumer/watch is used correctly
4. **EventRegistry out of sync:** Check `_syncEventToRegistry` is called
5. **Stage not triggering audio:** Ensure event is registered under correct stage name (case-insensitive match via `.toUpperCase()`)
6. **Multiple stages not working:** Verify all stages are registered (check debug log for "Registered X under N stages")

---

## CRITICAL FIX: SlotLab Audio Not Playing (2026-01-21)

### Problem

When pressing Spin in SlotLab, no audio was heard even though stages were being triggered.

### Root Causes

1. **EventRegistry was empty on SlotLab mount**
   - `_syncAllEventsToRegistry()` was only called from `_restorePersistedState()`
   - If no persisted state existed, EventRegistry stayed empty
   - Stages triggered but found no matching events

2. **Case-sensitivity mismatch**
   - SlotLabProvider sent stages as uppercase: `"SPIN_START"`
   - EventRegistry lookup was case-sensitive
   - Minor case differences caused silent failures

### Solutions Implemented

#### Fix 1: Initial Sync on Mount (slot_lab_screen.dart)

```dart
// In initState postFrameCallback:
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted) {
    _middleware.addListener(_onMiddlewareChanged);

    // CRITICAL FIX: Sync existing events from MiddlewareProvider to EventRegistry
    // This ensures audio works immediately when SlotLab is opened
    if (_compositeEvents.isNotEmpty) {
      _syncAllEventsToRegistry();
      debugPrint('[SlotLab] Initial sync: ${_compositeEvents.length} events → EventRegistry');
    }
  }
});
```

#### Fix 2: Case-Insensitive Lookup (event_registry.dart)

```dart
Future<void> triggerStage(String stage, {Map<String, dynamic>? context}) async {
  final normalizedStage = stage.toUpperCase().trim();

  // Try exact match first, then normalized
  var event = _stageToEvent[stage];
  event ??= _stageToEvent[normalizedStage];

  // If still not found, try case-insensitive search through all keys
  if (event == null) {
    for (final key in _stageToEvent.keys) {
      if (key.toUpperCase() == normalizedStage) {
        event = _stageToEvent[key];
        break;
      }
    }
  }

  if (event == null) {
    // Detailed logging for debugging
    final registeredStages = _stageToEvent.keys.take(10).join(', ');
    debugPrint('[EventRegistry] ❌ No event for stage: "$stage"');
    debugPrint('[EventRegistry] 📋 Registered stages: $registeredStages');
    return;
  }
  await triggerEvent(event.id, context: context);
}
```

### Verification Checklist

When SlotLab audio doesn't play:

1. **Check EventRegistry has events:**
   ```
   Debug log should show:
   [SlotLab] Initial sync: X events → EventRegistry
   [SlotLab] ✅ Registered "Event Name" under N stage(s): STAGE1, STAGE2
   ```

2. **Check stage lookup succeeds:**
   ```
   Debug log should show:
   [EventRegistry] Triggering: Event Name (N layers)
   [EventRegistry] ✅ Playing: layer.wav (voice X, source: slotlab, bus: Y)

   NOT:
   [EventRegistry] ❌ No event for stage: "SPIN_START"
   ```

3. **Check FFI is loaded:**
   ```
   If you see "FAILED: FFI not loaded":
   → Rebuild Rust: cargo build --release
   → Copy dylibs to Frameworks AND App Bundle (see CLAUDE.md)
   ```

4. **Check playback section is acquired:**
   ```
   [UnifiedPlayback] Section acquired: slotLab
   ```

### Event Log Panel Improvements (2026-01-21)

Compact single-line format per trigger:

**With audio:**
```
12:34:56.789  🎵 Spin Sound → SPIN_START [spin.wav, whoosh.wav]
              voice=5, bus=2, section=slotLab
```

**Without audio (helps identify missing events):**
```
12:34:56.789  ⚠️ REEL_STOP_3 (no audio)
              Create event for this stage to hear audio
```

---

## CRITICAL FIX: Deleted Layers Still Playing on Playback (2026-01-21)

### Problem

When deleting a layer or entire event in SlotLab, the audio continued playing during timeline playback (but not during Spin).

### Root Cause

SlotLab uses TWO audio systems:
1. **Spin** → `EventRegistry.triggerStage()` → was syncing correctly
2. **Playback** → `SlotLabTrackBridge` + FFI TRACK_MANAGER → **was NOT syncing**

`_syncLayersToTrackManager()` only **added** clips but never **removed** orphaned clips that no longer existed in `_tracks`.

### Solution

1. **Added orphan detection in `_syncLayersToTrackManager()`:**
   ```dart
   // Step 1: Collect all current layer IDs from _tracks
   final currentLayerIds = <String>{};
   for (final track in _tracks) {
     for (final region in track.regions) {
       for (final layer in region.layers) {
         currentLayerIds.add(layer.id);
       }
     }
   }

   // Step 2: Find and remove orphaned clips
   final registeredIds = _trackBridge.registeredLayerIds;
   final orphanedIds = registeredIds.difference(currentLayerIds);
   for (final orphanId in orphanedIds) {
     _trackBridge.removeLayerClip(orphanId);
   }
   ```

2. **Added `registeredLayerIds` getter to `SlotLabTrackBridge`:**
   ```dart
   Set<String> get registeredLayerIds => _layerToClipId.keys.toSet();
   ```

3. **Added sync call in `_onMiddlewareChanged()`:**
   - Now calls `_syncLayersToTrackManager()` after rebuilding regions

4. **Added immediate sync in `_deleteCompositeEvent()`:**
   - Calls `_syncLayersToTrackManager()` right after deleting region

### Files Changed

- `flutter_ui/lib/services/slotlab_track_bridge.dart` — Added `registeredLayerIds` getter
- `flutter_ui/lib/screens/slot_lab_screen.dart`:
  - `_syncLayersToTrackManager()` — Added orphan detection/removal
  - `_onMiddlewareChanged()` — Added TrackManager sync
  - `_deleteCompositeEvent()` — Added immediate sync

---

## SLOTLAB TIMELINE LAYER DRAG (2026-01-21) ✅

### Problem: Layer Jumps to Start on Second Drag

**Simptomi:**
- Prvi drag radi normalno
- Drugi drag — layer skače na početak timeline-a

**Root Cause:**
Kompleksna relativna kalkulacija offseta:
- `layer.offset` = pozicija relativno na `region.start`
- `region.start` se dinamički menja (prati najraniji layer)
- Između drag-ova, `region.start` bi se promenio
- `freshRelativeOffset` bi se pogrešno izračunao

### Rešenje: Apsolutno Pozicioniranje

Controller sada koristi **apsolutnu poziciju** umesto relativne:

```dart
// BEFORE (broken)
void startLayerDrag({
  required double startOffsetSeconds,      // Relative to region
  required double regionStartSeconds,      // For absolute calculation
}) {
  _layerDragStartOffset = startOffsetSeconds;
  _regionStartSeconds = regionStartSeconds;
}

double getLayerCurrentPosition() {
  return _layerDragStartOffset + _layerDragDelta;
}

void endLayerDrag() {
  final newAbsolute = (_regionStartSeconds + _layerDragStartOffset + _layerDragDelta) * 1000;
  provider.setLayerOffset(eventId, layerId, newAbsolute);
}

// AFTER (fixed)
void startLayerDrag({
  required double absoluteOffsetSeconds,   // Direct from provider.offsetMs / 1000
}) {
  _absoluteStartSeconds = absoluteOffsetSeconds;
}

double getAbsolutePosition() {
  return (_absoluteStartSeconds + _layerDragDelta).clamp(0.0, infinity);
}

void endLayerDrag() {
  final newAbsolute = getAbsolutePosition() * 1000;
  provider.setLayerOffset(eventId, layerId, newAbsolute);
}
```

### Drag Start (slot_lab_screen.dart)

```dart
onHorizontalDragStart: (details) {
  // Get FRESH ABSOLUTE offset from provider
  final freshLayer = freshEvent?.layers.where((l) => l.id == layerId).firstOrNull;
  final freshAbsoluteOffsetSeconds = (freshLayer?.offsetMs ?? 0.0) / 1000.0;

  // Start drag with ABSOLUTE position - no relative calculations
  dragController.startLayerDrag(
    layerEventId: layerId,
    parentEventId: parentEventId,
    regionId: region.id,
    absoluteOffsetSeconds: freshAbsoluteOffsetSeconds,
    regionDuration: region.duration,
    layerDuration: realDuration,
  );
}
```

### Visual Position During Drag

```dart
double currentOffsetSeconds;
if (isDragging) {
  // Controller tracks absolute position
  currentOffsetSeconds = dragController.getAbsolutePosition() - region.start;
} else {
  // Read from provider, convert to relative for display
  final providerOffsetMs = eventLayer?.offsetMs ?? 0.0;
  currentOffsetSeconds = (providerOffsetMs / 1000.0) - region.start;
}
final offsetPixels = (currentOffsetSeconds * pixelsPerSecond).clamp(0.0, infinity);
```

### Commits

| Commit | Opis |
|--------|------|
| `e1820b0c` | Event log deduplication + captured values pattern |
| `97d8723f` | Absolute positioning za layer drag |

---

## CRITICAL FIX: QuickSheet Double Calls (2026-01-23)

### Problem

When dropping audio on slot element in Edit mode:
- QuickSheet popup appears correctly
- User clicks Commit
- Popup closes
- BUT event is NOT created in Events panel
- Spin produces no audio

### Root Cause #1: Double `commitDraft()`

`provider.commitDraft()` was called **TWICE**:

1. First call in `quick_sheet.dart` onCommit handler (line 63)
2. Second call in `drop_target_wrapper.dart` callback (line 130)

The first call consumed the draft and returned the `CommittedEvent`. The second call returned `null` because the draft was already consumed.

### Root Cause #2: Double `createDraft()`

`provider.createDraft()` was also called **TWICE**:

1. First call in `drop_target_wrapper.dart` _handleDrop() (line 119)
2. Second call in `quick_sheet.dart` showQuickSheet() (line 36)

The second call overwrote the first draft with a new one (different event ID), causing inconsistent state.

### Solution

**Fix #1:** Removed `commitDraft()` from QuickSheet — let DropTargetWrapper handle it exclusively:

```dart
// quick_sheet.dart - FIXED:
onCommit: () {
  // NOTE: Don't call commitDraft() here!
  // The onCommit callback (from DropTargetWrapper) handles commitDraft
  // to properly capture the returned CommittedEvent.
  Navigator.of(context).pop();
  onCommit?.call();
},
```

**Fix #2:** Removed `createDraft()` from DropTargetWrapper — let showQuickSheet handle it:

```dart
// drop_target_wrapper.dart - FIXED:
void _handleDrop(AudioAsset asset, Offset globalPosition, AutoEventBuilderProvider provider) {
  // NOTE: Don't call createDraft() here!
  // showQuickSheet() handles draft creation internally to avoid double-create issues.
  // The draft is created ONCE in showQuickSheet() and committed via onCommit callback.

  showQuickSheet(
    context: context,
    provider: provider,
    asset: asset,
    target: widget.target,
    position: globalPosition,
    onCommit: () {
      final event = provider.commitDraft();  // ← ONLY commitDraft call
      if (event != null) {
        _triggerPulse();
        widget.onEventCreated?.call(event);
      }
    },
    onCancel: provider.cancelDraft,
  );
}
```

### Complete Flow (Fixed)

```
1. User drops audio on slot element (Edit mode)
   ↓
2. DropTargetWrapper._handleDrop() called
   ↓
3. showQuickSheet() called (NO createDraft in _handleDrop!)
   ↓
4. showQuickSheet() internally calls provider.createDraft() ← ONLY call!
   ↓
5. QuickSheet popup displays with draft data
   ↓
6. User clicks "Commit" button
   ↓
7. QuickSheet onCommit:
   - Navigator.pop() closes popup
   - onCommit?.call() invokes DropTargetWrapper callback
   ↓
8. DropTargetWrapper onCommit callback:
   - final event = provider.commitDraft()  ← ONLY call!
   - event != null ✅
   - _triggerPulse() for visual feedback
   - widget.onEventCreated?.call(event)
   ↓
9. _onEventBuilderEventCreated(event, targetId)
   - Creates SlotCompositeEvent
   - _middleware.addCompositeEvent(compositeEvent)
   ↓
10. MiddlewareProvider.notifyListeners()
    ↓
11. _onMiddlewareChanged() listener fires
    - _syncEventToRegistry(event)
    - EventRegistry.registerEvent(audioEvent)
    ↓
12. User presses Spin (or any slot action)
    ↓
13. SlotLabProvider._triggerStage("SPIN_START")
    ↓
14. EventRegistry.triggerStage("SPIN_START")
    - Finds registered event ✅
    - AudioPlaybackService.playFileToBus()
    ↓
15. 🔊 Audio plays!
```

### Files Changed

| File | Change |
|------|--------|
| `flutter_ui/lib/widgets/slot_lab/auto_event_builder/quick_sheet.dart` | Removed `provider.commitDraft()` from onCommit handler |
| `flutter_ui/lib/widgets/slot_lab/auto_event_builder/drop_target_wrapper.dart` | Removed `provider.createDraft()` from _handleDrop() |

### Key Principle

**Single Responsibility:**
- `showQuickSheet()` → creates draft (line 36)
- `DropTargetWrapper.onCommit` → commits draft (line 130)

Each operation happens exactly ONCE in exactly ONE place.

### Verification Checklist

1. Drop audio on SPIN button in Edit mode
2. QuickSheet popup appears → Click "Commit"
3. ✅ Popup closes
4. ✅ Event appears in Events panel (right side)
5. ✅ Event has the dropped audio as a layer
6. Click Spin button
7. ✅ Audio plays
8. Repeat for other slot elements (reels, win overlays, etc.)

---

## VISUAL-SYNC CALLBACKS (2026-01-23) ✅

### Problem: Audio-Visual Desync

**Simptomi:**
- REEL_STOP stages fired at inconsistent times compared to visual reel stops
- Audio felt "late" or "early" relative to visual animation
- Different timing paths: SlotLabProvider vs EmbeddedSlotMockup animations

**Root Cause:**
EmbeddedSlotMockup had its own internal animation timing (`_scheduleReelStops()`) that was completely independent from SlotLabProvider's stage triggering system. Audio stages were triggered based on spin result data, not actual visual events.

### Solution: Visual-Sync Callback Pattern

Added callback hooks directly in visual animation widget that fire **exactly** when visual events occur:

```dart
// EmbeddedSlotMockup callbacks
class EmbeddedSlotMockup extends StatefulWidget {
  // VISUAL-SYNC CALLBACKS
  final VoidCallback? onSpinStart;
  final void Function(int reelIndex)? onReelStop;
  final VoidCallback? onAnticipation;
  final VoidCallback? onReveal;
  final void Function(WinType winType, double amount)? onWinStart;
  final VoidCallback? onWinEnd;
  // ...
}
```

### Implementation Details

**EmbeddedSlotMockup._scheduleReelStops():**
```dart
void _scheduleReelStops() {
  final baseDelay = _turbo ? 100 : 250;

  for (int i = 0; i < widget.reels; i++) {
    Future.delayed(Duration(milliseconds: baseDelay * (i + 1)), () {
      if (!mounted) return;
      setState(() {
        _reelStopped[i] = true;  // Visual update
      });

      // VISUAL-SYNC: Trigger REEL_STOP_i stage IMMEDIATELY when visual stops
      widget.onReelStop?.call(i);

      // Check for anticipation on second-to-last reel
      if (i == widget.reels - 2) {
        if (_rng.nextDouble() < 0.2) {
          setState(() => _gameState = GameState.anticipation);
          widget.onAnticipation?.call();
        }
      }
    });
  }
}
```

**SlotLabScreen helper methods:**
```dart
// VISUAL-SYNC helper - triggers stage directly to EventRegistry
void _triggerVisualStage(String stage, {Map<String, dynamic>? context}) {
  eventRegistry.triggerStage(stage, context: context);
  debugPrint('[SlotLab] VISUAL-SYNC: $stage ${context ?? ''}');
}

// Win stage helper - determines win tier and triggers appropriate stages
void _triggerWinStage(WinType winType, double amount) {
  final winStage = switch (winType) {
    WinType.noWin => null,
    WinType.smallWin => 'WIN_SMALL',
    WinType.mediumWin => 'WIN_MEDIUM',
    WinType.bigWin => 'WIN_BIG',
    WinType.megaWin => 'WIN_MEGA',
    WinType.epicWin => 'WIN_EPIC',
  };

  if (winStage != null) {
    final multiplier = _bet > 0 ? amount / _bet : 0.0;
    eventRegistry.triggerStage(winStage, context: {
      'win_amount': amount,
      'win_multiplier': multiplier,
      'win_type': winType.name,
    });
    eventRegistry.triggerStage('ROLLUP_START', context: {
      'win_amount': amount,
      'win_multiplier': multiplier,
    });
  }
}
```

**Widget connection:**
```dart
EmbeddedSlotMockup(
  provider: _slotLabProvider,
  reels: _reelCount,
  rows: _rowCount,
  onSpin: _handleSpin,
  onForcedSpin: (outcome) => _handleEngineSpin(forcedOutcome: outcome),
  // VISUAL-SYNC callbacks:
  onSpinStart: () => _triggerVisualStage('SPIN_START'),
  onReelStop: (reelIdx) => _triggerVisualStage('REEL_STOP_$reelIdx', context: {'reel_index': reelIdx}),
  onAnticipation: () => _triggerVisualStage('ANTICIPATION_ON'),
  onReveal: () => _triggerVisualStage('SPIN_END'),
  onWinStart: (winType, amount) => _triggerWinStage(winType, amount),
  onWinEnd: () => _triggerVisualStage('WIN_END'),
),
```

### Callback Flow

```
1. User presses Spin
   ↓
2. EmbeddedSlotMockup._spin() called
   ↓
3. setState: _gameState = GameState.spinning
   ↓
4. widget.onSpinStart?.call()  →  EventRegistry.triggerStage('SPIN_START')
   ↓
5. _scheduleReelStops() schedules Future.delayed for each reel
   ↓
6. [After 250ms] First reel stops visually
   ↓
7. widget.onReelStop?.call(0)  →  EventRegistry.triggerStage('REEL_STOP_0')
   ↓
8. [After 500ms] Second reel stops visually
   ↓
9. widget.onReelStop?.call(1)  →  EventRegistry.triggerStage('REEL_STOP_1')
   ↓
... (continues for all reels)
   ↓
N. All reels stopped → Win evaluation
   ↓
N+1. widget.onWinStart?.call(winType, amount)  →  EventRegistry.triggerStage('WIN_BIG')
```

### Key Benefits

| Benefit | Description |
|---------|-------------|
| **Perfect Sync** | Audio triggers exactly when visual event happens |
| **Decoupled** | Visual widget doesn't know about audio system |
| **Testable** | Can test visual animations without audio |
| **Flexible** | Can add more callbacks as needed |
| **Context Data** | Callbacks can pass relevant context (reel index, win amount) |

### Files Changed

| File | Change |
|------|--------|
| `flutter_ui/lib/widgets/slot_lab/embedded_slot_mockup.dart` | Added 6 callback parameters, call sites in animation methods |
| `flutter_ui/lib/screens/slot_lab_screen.dart` | Added `_triggerVisualStage()`, `_triggerWinStage()`, connected callbacks |

---

## QUICKSHEET DROPDOWN FALLBACK (2026-01-23) ✅

### Problem: Dropdown Assertion Error

**Error:**
```
flutter/src/material/dropdown.dart: failed assertion: line 1011 pos 10
items == null || items.isEmpty
```

**Root Cause:**
When dragging audio onto slot elements, `availableTriggers` list could be empty, causing DropdownButton to fail.

### Solution: Fallback Constants

```dart
// quick_sheet.dart
class _QuickSheetContentState extends State<_QuickSheetContent> {
  // Fallback values for empty lists
  static const _fallbackTriggers = ['press', 'release', 'hover'];
  static const _fallbackPresetId = 'ui_click_secondary';

  @override
  void initState() {
    super.initState();
    final triggers = _getAvailableTriggers();
    _selectedTrigger = triggers.contains(widget.draft.trigger)
        ? widget.draft.trigger
        : triggers.first;

    final presets = widget.provider.presets;
    _selectedPreset = presets.any((p) => p.presetId == widget.draft.presetId)
        ? widget.draft.presetId
        : (presets.isNotEmpty ? presets.first.presetId : _fallbackPresetId);
  }

  List<String> _getAvailableTriggers() {
    final triggers = widget.draft.availableTriggers;
    return triggers.isNotEmpty ? triggers : _fallbackTriggers;
  }
}
```

### Dropdown Build Safety

```dart
Widget _buildPresetDropdown() {
  final presets = widget.provider.presets;
  if (presets.isEmpty) {
    return Text('No presets available', style: TextStyle(color: Colors.grey));
  }
  return DropdownButton<String>(
    value: _selectedPreset,
    items: presets.map((p) => DropdownMenuItem(...)).toList(),
    onChanged: (val) => setState(() => _selectedPreset = val!),
  );
}
```

---

## AUDIO PREVIEW ON COMMIT (2026-01-23) ✅

### Problem: Sounds Feel "Cut Off"

When dropping audio on slot elements, sounds felt truncated because hover preview stopped when drag started.

### Solution: Play Confirmation Preview

Added audio preview playback when event is successfully committed:

```dart
// drop_target_wrapper.dart
onCommit: () {
  final event = provider.commitDraft();
  if (event != null) {
    _triggerPulse();

    // Play brief audio preview as confirmation feedback
    AudioPlaybackService.instance.previewFile(
      asset.path,
      volume: 0.7,
      source: PlaybackSource.browser, // Use browser for instant playback
    );

    widget.onEventCreated?.call(event);
  }
},
```

**Why PlaybackSource.browser?**
- Browser source bypasses section filtering
- Plays instantly regardless of active section
- Perfect for UI feedback sounds

---

## Related Documentation

- `.claude/architecture/UNIFIED_PLAYBACK_SYSTEM.md` — Playback section management
- `.claude/architecture/SLOT_LAB_SYSTEM.md` — SlotLab architecture
- `.claude/project/fluxforge-studio.md` — Full project spec
