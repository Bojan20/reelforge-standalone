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

```dart
void _syncEventToRegistry(SlotCompositeEvent? event) {
  if (event == null) return;

  final audioEvent = AudioEvent(
    id: event.id,
    name: event.name,
    stage: _getEventStage(event),
    layers: event.layers.map((l) => AudioLayer(
      id: l.id,
      audioPath: l.audioPath,
      name: l.name,
      volume: l.volume,
      pan: l.pan,
      delay: l.offsetMs,
      busId: l.busId ?? 2,
    )).toList(),
    // ...
  );

  EventRegistry.instance.registerEvent(audioEvent);
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

---

## Related Documentation

- `.claude/architecture/UNIFIED_PLAYBACK_SYSTEM.md` — Playback section management
- `.claude/architecture/SLOT_LAB_SYSTEM.md` — SlotLab architecture
- `.claude/project/fluxforge-studio.md` — Full project spec
