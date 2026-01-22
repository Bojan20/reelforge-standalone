# P0/P1 UX Integration — Search & Keyboard System

**Status:** ✅ COMPLETED (2026-01-22)
**Sprint:** UX Integration Fixes

---

## Overview

Fiksevi za kritične UX integracije koje su bile implementirane u UI ali nisu bile povezane sa backend servisima.

**Problem:** UI komponente su postojale ali:
- Search provideri nisu bili registrovani → pretraga nije vraćala rezultate
- Keyboard handlers nisu bili povezani → komande nisu radile
- Recent items nisu bili praćeni → quick access bio prazan

---

## P0: Critical Fixes

### P0.1: Search Provider Registration

**Problem:** `UnifiedSearchService` je imao `registerProvider()` metodu ali niko je nije pozivao.

**Rešenje:** Dodato u `service_locator.dart`:

```dart
// LAYER 6: UX Services
sl.registerLazySingleton<UnifiedSearchService>(
  () => UnifiedSearchService.instance,
);
sl.registerLazySingleton<RecentFavoritesService>(
  () => RecentFavoritesService.instance,
);

// Initialize search providers
_initializeSearchProviders();

static void _initializeSearchProviders() {
  final search = sl<UnifiedSearchService>();
  search.registerProvider(HelpSearchProvider());
  search.registerProvider(RecentSearchProvider());
}
```

**Fajlovi:**
- [service_locator.dart](../../../flutter_ui/lib/services/service_locator.dart#L143-L172)

---

### P0.2: Keyboard Handler Registration

**Problem:** `KeyboardFocusProvider` je imao 38 mapiranih komandi ali `_commandHandlers` mapa je bila prazna.

**Rešenje:** Dodato u `main.dart`:

```dart
// Phase 3.5: Register keyboard focus handlers
_registerKeyboardHandlers(context, engine, history);

void _registerKeyboardHandlers(
  BuildContext context,
  EngineProvider engine,
  ProjectHistoryProvider history,
) {
  final keyboard = context.read<KeyboardFocusProvider>();
  final timeline = context.read<TimelinePlaybackProvider>();

  keyboard.registerHandlers({
    // Clipboard operations
    KeyboardCommand.copy: () { ... },
    KeyboardCommand.cut: () { ... },
    KeyboardCommand.paste: () { ... },

    // Transport
    KeyboardCommand.play: () {
      if (engine.transport.isPlaying) {
        engine.pause();
      } else {
        engine.play();
      }
    },
    KeyboardCommand.stop: () => engine.stop(),
    KeyboardCommand.loopPlayback: () => timeline.toggleLoop(),

    // ... 38 total handlers
  });
}
```

**Registrovane komande (38):**

| Kategorija | Komande |
|------------|---------|
| Clipboard | copy, cut, paste |
| Edit | duplicate, separate, joinClips, muteClip |
| Undo/Redo | redo |
| Transport | play, stop, loopPlayback, record |
| Navigation | nextClip, previousClip, nudgeLeft/Right/Up/Down |
| Tools | editTool, trimTool, fadeTool, zoomTool |
| Grid | gridToggle, quantize |
| Other | fadeBoth, healSeparation, insertSilence, trimEndToCursor, stripSilence, renameClip |
| Automation | toggleAutomation |
| Plugin | openPlugin |
| Window | closeWindow |
| Track Selection | selectTrack1-10 |

**Fajlovi:**
- [main.dart](../../../flutter_ui/lib/main.dart#L281-L451)

---

## P1: Search Providers

### P1.1: EventSearchProvider

**Svrha:** Pretraga SlotLab composite events po imenu, stage-ovima i audio layer paths.

**Implementacija:**

```dart
class EventSearchProvider extends SearchProvider {
  List<Map<String, dynamic>> Function()? _getEventsCallback;

  void init({
    required List<Map<String, dynamic>> Function() getEvents,
    VoidCallback? onEventSelect,
  }) {
    _getEventsCallback = getEvents;
    _onEventSelectCallback = onEventSelect;
  }

  @override
  Set<SearchCategory> get categories => {
    SearchCategory.event,
    SearchCategory.stage,
  };

  @override
  Future<List<SearchResult>> search(String query, ...) async {
    final events = _getEventsCallback!();
    // Match against name, stages, layers
    // Return sorted by relevance
  }
}
```

**Registracija u `engine_connected_layout.dart`:**

```dart
void _registerEventSearchProvider() {
  final search = sl<UnifiedSearchService>();
  final middleware = context.read<MiddlewareProvider>();

  final eventProvider = EventSearchProvider();
  eventProvider.init(
    getEvents: () {
      return middleware.compositeEvents.map((event) => {
        'id': event.id,
        'name': event.name,
        'stages': event.triggerStages,
        'layers': event.layers.map((l) => {
          'audioPath': l.audioPath,
          'busId': l.busId,
        }).toList(),
        'containerType': event.containerType.name,
      }).toList();
    },
  );

  search.registerProvider(eventProvider);
}
```

**Fajlovi:**
- [unified_search_service.dart](../../../flutter_ui/lib/services/unified_search_service.dart#L544-L660)
- [engine_connected_layout.dart](../../../flutter_ui/lib/screens/engine_connected_layout.dart#L843-L881)

---

### P1.2: RecentSearchProvider

**Svrha:** Pretraga recent i favorite items iz `RecentFavoritesService`.

**Implementacija:**

```dart
class RecentSearchProvider extends SearchProvider {
  @override
  Set<SearchCategory> get categories => {
    SearchCategory.file,
    SearchCategory.event,
    SearchCategory.preset,
    SearchCategory.recent,
  };

  @override
  Future<List<SearchResult>> search(String query, ...) async {
    final service = RecentFavoritesService.instance;
    // Search all recent items by title/subtitle
    // Boost favorites (+0.2 relevance)
  }

  @override
  Future<List<SearchResult>> getSuggestions({int maxResults = 5}) async {
    // Return favorites first, then most used
  }
}
```

**Fajlovi:**
- [unified_search_service.dart](../../../flutter_ui/lib/services/unified_search_service.dart#L448-L542)

---

### P1.3: Recent → Event Integration

**Svrha:** Automatski dodavanje trigerovanih eventa u recent items.

**Implementacija u `event_registry.dart`:**

```dart
Future<void> triggerEvent(String eventId, ...) async {
  // ... existing trigger logic ...

  // P1.3: Add to recent items for quick access
  _addToRecent(event);

  notifyListeners();
}

void _addToRecent(AudioEvent event) {
  RecentFavoritesService.instance.addRecent(
    RecentItem.event(
      eventId: event.id,
      name: event.name,
      stageName: event.stage.isNotEmpty ? event.stage : null,
    ),
  );
}
```

**Fajlovi:**
- [event_registry.dart](../../../flutter_ui/lib/services/event_registry.dart#L1143-L1165)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    SERVICE LOCATOR (GetIt)                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────┐    ┌─────────────────────┐             │
│  │ UnifiedSearchService │    │ RecentFavoritesService│            │
│  └──────────┬──────────┘    └──────────┬──────────┘             │
│             │                          │                         │
│             │ registerProvider()       │ addRecent()             │
│             ▼                          ▼                         │
│  ┌──────────────────────────────────────────────────┐           │
│  │              Search Providers                     │           │
│  │  ┌──────────────┬───────────────┬──────────────┐ │           │
│  │  │HelpSearch    │RecentSearch   │EventSearch   │ │           │
│  │  │Provider      │Provider       │Provider      │ │           │
│  │  └──────────────┴───────────────┴──────────────┘ │           │
│  └──────────────────────────────────────────────────┘           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    KEYBOARD SYSTEM                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  main.dart::_initializeApp()                                    │
│       │                                                          │
│       └──► _registerKeyboardHandlers()                          │
│                    │                                             │
│                    ▼                                             │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │           KeyboardFocusProvider                          │    │
│  │  ┌─────────────────────────────────────────────────────┐│    │
│  │  │ _commandHandlers: Map<KeyboardCommand, VoidCallback>││    │
│  │  │                                                      ││    │
│  │  │  copy      → debugPrint (placeholder)               ││    │
│  │  │  play      → engine.play()/pause()                  ││    │
│  │  │  stop      → engine.stop()                          ││    │
│  │  │  redo      → engine.redo() + history.redo()         ││    │
│  │  │  loopPlay  → timeline.toggleLoop()                  ││    │
│  │  │  ...38 total handlers                               ││    │
│  │  └─────────────────────────────────────────────────────┘│    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                 RECENT TRACKING FLOW                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  SlotLabProvider.spin()                                         │
│       │                                                          │
│       └──► EventRegistry.triggerStage('SPIN_START')             │
│                    │                                             │
│                    └──► triggerEvent(eventId)                   │
│                              │                                   │
│                              ├──► _playLayer() (audio)          │
│                              │                                   │
│                              └──► _addToRecent(event)           │
│                                        │                         │
│                                        ▼                         │
│                              RecentFavoritesService              │
│                                   .addRecent()                   │
│                                        │                         │
│                                        ▼                         │
│                              SharedPreferences                   │
│                              (persistent storage)                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Testing

### Search System

```dart
// Test search providers
final search = sl<UnifiedSearchService>();

// Help search
final helpResults = await search.search('undo');
assert(helpResults.any((r) => r.category == SearchCategory.help));

// Recent search (after triggering events)
final recentResults = await search.search('spin');
assert(recentResults.any((r) => r.category == SearchCategory.recent));

// Event search (requires MiddlewareProvider)
final eventResults = await search.search('REEL_STOP');
assert(eventResults.any((r) => r.category == SearchCategory.event));
```

### Keyboard Commands

```dart
// Enable commands mode
final keyboard = context.read<KeyboardFocusProvider>();
keyboard.enableCommandsMode();

// Execute command
keyboard.executeCommand(KeyboardCommand.play);
// Verify: engine.transport.isPlaying == true

keyboard.executeCommand(KeyboardCommand.stop);
// Verify: engine.transport.isPlaying == false
```

### Recent Tracking

```dart
// Trigger event
await eventRegistry.triggerEvent('spin_start_event');

// Verify recent
final recent = RecentFavoritesService.instance.getRecent(RecentItemType.event);
assert(recent.any((r) => r.id == 'event:spin_start_event'));
```

---

## Files Modified

| File | Changes | LOC |
|------|---------|-----|
| `service_locator.dart` | Search service registration, `_initializeSearchProviders()` | +25 |
| `main.dart` | `_registerKeyboardHandlers()` method | +150 |
| `unified_search_service.dart` | `EventSearchProvider` class | +115 |
| `engine_connected_layout.dart` | `_registerEventSearchProvider()` method | +40 |
| `event_registry.dart` | `_addToRecent()` integration | +15 |

**Total:** ~345 LOC

---

## Future Improvements (P2)

- [ ] FileSearchProvider — pretraga audio pool fajlova
- [ ] TrackSearchProvider — pretraga timeline tracks
- [ ] PresetSearchProvider — pretraga DSP presets
- [ ] Fuzzy matching za tolerantnije pretrage
- [ ] Search history persistence
- [ ] Keyboard shortcut customization UI
