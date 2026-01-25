# SlotLab Drop Zone System — Ultimate Specification

**Version:** 1.1.0
**Created:** 2026-01-23
**Updated:** 2026-01-25
**Author:** Claude Code (Principal Engineer Documentation)
**Status:** AUTHORITATIVE — Do Not Modify Without Review

---

## 1. EXECUTIVE SUMMARY

SlotLab Drop Zone System omogućava audio dizajnerima da direktno prevuku audio fajlove na vizuelne elemente slot mockup-a i automatski kreiraju audio evente. Sistem koristi **bidirekcionu sinhronizaciju** gde je `MiddlewareProvider.compositeEvents` jedini **Single Source of Truth (SSoT)**.

### 1.1 Ključni Principi

| Princip | Opis |
|---------|------|
| **Single Source of Truth** | `MiddlewareProvider.compositeEvents` je jedini izvor podataka za sve evente |
| **Bidirectional Sync** | Drop → MiddlewareProvider → EventRegistry → Timeline |
| **Visual Feedback** | Glow, pulse, badge na svakom drop target-u |
| **Auto Event Creation** | Event se automatski kreira na osnovu target tipa i asset tipa |
| **Timeline Integration** | Svaki kreirani event se automatski prikazuje na timeline-u sa svim layerima |

---

## 2. ARHITEKTURA

### 2.1 Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SLOT MOCKUP UI                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │ ui.spin  │  │ reel.0   │  │ reel.1   │  │ ...      │  │ reel.4   │       │
│  │ DropZone │  │ DropZone │  │ DropZone │  │ DropZone │  │ DropZone │       │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘       │
│       │             │             │             │             │              │
└───────┼─────────────┼─────────────┼─────────────┼─────────────┼──────────────┘
        │             │             │             │             │
        └─────────────┴─────────────┴──────┬──────┴─────────────┘
                                           │
                                           ▼
                              ┌─────────────────────────┐
                              │    DropTargetWrapper    │
                              │  (drop_target_wrapper)  │
                              │                         │
                              │  • Visual glow/pulse    │
                              │  • Badge count          │
                              │  • DragTarget widget    │
                              └───────────┬─────────────┘
                                          │
                                          ▼
                              ┌─────────────────────────┐
                              │  AutoEventBuilderProv   │
                              │                         │
                              │  • createDraft()        │
                              │  • commitDraft()        │
                              │  • CommittedEvent       │
                              └───────────┬─────────────┘
                                          │
                                          │  ◄── GAP: Need bridge
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      MIDDLEWARE PROVIDER (SSoT)                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  List<SlotCompositeEvent> compositeEvents                            │    │
│  │                                                                      │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │    │
│  │  │ Event: Spin  │  │ Event: Reel0 │  │ Event: Win   │  ...          │    │
│  │  │ layers: [    │  │ layers: [    │  │ layers: [    │               │    │
│  │  │   layer1,    │  │   layer1,    │  │   layer1,    │               │    │
│  │  │   layer2     │  │   layer2     │  │   layer2,    │               │    │
│  │  │ ]            │  │ ]            │  │   layer3     │               │    │
│  │  └──────────────┘  └──────────────┘  │ ]            │               │    │
│  │                                      └──────────────┘               │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                   │                                          │
│                                   │ notifyListeners()                        │
└───────────────────────────────────┼──────────────────────────────────────────┘
                                    │
           ┌────────────────────────┼────────────────────────┐
           │                        │                        │
           ▼                        ▼                        ▼
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│   EVENT REGISTRY    │  │  SLOTLAB TIMELINE   │  │  MIDDLEWARE PANEL   │
│                     │  │                     │  │                     │
│ AudioEvent {        │  │ _AudioRegion {      │  │ Events Folder:      │
│   stage → layers    │  │   layers: [         │  │   - Spin Sound      │
│ }                   │  │     _RegionLayer,   │  │   - Reel Stop 0     │
│                     │  │     _RegionLayer,   │  │   - Win Sound       │
│ triggerStage(s) →   │  │   ]                 │  │                     │
│   → playAudio()     │  │ }                   │  │ Edit layers, pan,   │
│                     │  │                     │  │ volume, offset...   │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘
```

### 2.2 Class Hierarchy

```
DropTargetWrapper (StatefulWidget)
├── target: DropTarget              // Target configuration
├── child: Widget                   // Wrapped UI element
├── onEventCreated: Function?       // Callback after commit
│
├── DragTarget<AudioAsset>          // Flutter drag-drop
│   ├── onWillAcceptWithDetails()   // Set _isDragOver = true
│   ├── onLeave()                   // Set _isDragOver = false
│   └── onAcceptWithDetails()       // Call _handleDrop()
│
└── _handleDrop(AudioAsset, Offset)
    ├── provider.createDraft(asset, target)
    └── showQuickSheet() → onCommit → provider.commitDraft()
                                    → _triggerPulse()
                                    → onEventCreated?.call(event)
```

---

## 3. DROP ZONE DEFINITIONS

### 3.0 Architecture Note: Reel-Level Only (v1.1)

**IMPORTANT:** As of v1.1.0 (2026-01-25), the drop zone system uses **REEL-LEVEL ONLY** drop zones.

```
┌─────────────────────────────────────────────────────────────────┐
│                        SLOT GRID                                 │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐│
│  │         │  │         │  │         │  │         │  │         ││
│  │  REEL 1 │  │  REEL 2 │  │  REEL 3 │  │  REEL 4 │  │  REEL 5 ││
│  │ (reel.0)│  │ (reel.1)│  │ (reel.2)│  │ (reel.3)│  │ (reel.4)││
│  │         │  │         │  │         │  │         │  │         ││
│  │ DROP    │  │ DROP    │  │ DROP    │  │ DROP    │  │ DROP    ││
│  │ ZONE    │  │ ZONE    │  │ ZONE    │  │ ZONE    │  │ ZONE    ││
│  │         │  │         │  │         │  │         │  │         ││
│  │ pan:-0.8│  │ pan:-0.4│  │ pan:0.0 │  │ pan:+0.4│  │ pan:+0.8││
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘│
│                                                                   │
│  ❌ NO INDIVIDUAL CELL DROP ZONES                                │
│  ✅ FULL REEL COLUMN DROP ZONES ONLY                             │
└─────────────────────────────────────────────────────────────────┘
```

**Design Decision:**
- Individual cell drop zones (per-symbol positions) were removed to reduce UI clutter
- Dropping audio on a reel creates REEL_STOP_N event for that entire reel column
- Reel dimensions remain UNCHANGED — same pixel size as before
- Symbol-specific audio should use Symbol Strip panel instead

**Implementation:**
- `_buildReelOuterDropZone()` creates full-reel drop zones
- `_buildCellDropZone()` method was REMOVED (2026-01-25)
- Inner cell drop zone loop was REMOVED from `_buildReelDropGrid()`

### 3.1 Complete Target ID Catalog

| Target ID | TargetType | Tags | Stage Mapping | Bus | Pan |
|-----------|------------|------|---------------|-----|-----|
| `ui.spin` | uiButton | primary, cta, spin | SPIN_START | SFX/UI | 0.0 |
| `ui.autospin` | uiToggle | secondary, autospin | AUTO_SPIN_ON/OFF | SFX/UI | 0.0 |
| `ui.turbo` | uiToggle | secondary, turbo | TURBO_ON/OFF | SFX/UI | 0.0 |
| `ui.maxbet` | uiButton | secondary, bet | MAX_BET_PRESS | SFX/UI | 0.0 |
| `ui.bet.up` | uiButton | secondary, bet, selector | BET_UP | SFX/UI | 0.0 |
| `ui.bet.down` | uiButton | secondary, bet, selector | BET_DOWN | SFX/UI | 0.0 |
| `reel.surface` | reelSurface | reels, main, spin | REEL_SPINNING | SFX/Reels | 0.0 |
| `reel.0` | reelStopZone | reels, column, reel_0 | REEL_STOP_0 | SFX/Reels | **-0.8** |
| `reel.1` | reelStopZone | reels, column, reel_1 | REEL_STOP_1 | SFX/Reels | **-0.4** |
| `reel.2` | reelStopZone | reels, column, reel_2 | REEL_STOP_2 | SFX/Reels | **0.0** |
| `reel.3` | reelStopZone | reels, column, reel_3 | REEL_STOP_3 | SFX/Reels | **+0.4** |
| `reel.4` | reelStopZone | reels, column, reel_4 | REEL_STOP_4 | SFX/Reels | **+0.8** |
| `overlay.win.small` | overlay | win, small, celebration | WIN_SMALL | SFX/Wins | 0.0 |
| `overlay.win.big` | overlay | win, big, celebration | WIN_BIG | SFX/Wins | 0.0 |
| `overlay.win.mega` | overlay | win, mega, celebration | WIN_MEGA | SFX/Wins | 0.0 |
| `overlay.win.epic` | overlay | win, epic, celebration | WIN_EPIC | SFX/Wins | 0.0 |
| `overlay.jackpot.mini` | overlay | jackpot, mini | JACKPOT_MINI | SFX/Wins | 0.0 |
| `overlay.jackpot.minor` | overlay | jackpot, minor | JACKPOT_MINOR | SFX/Wins | 0.0 |
| `overlay.jackpot.major` | overlay | jackpot, major | JACKPOT_MAJOR | SFX/Wins | 0.0 |
| `overlay.jackpot.grand` | overlay | jackpot, grand | JACKPOT_GRAND | SFX/Wins | 0.0 |
| `feature.freespins` | featureContainer | feature, freespins | FS_ENTER/EXIT | SFX/Features | 0.0 |
| `feature.bonus` | featureContainer | feature, bonus | BONUS_ENTER/EXIT | SFX/Features | 0.0 |
| `feature.cascade` | featureContainer | feature, cascade | CASCADE_START/END | SFX/Features | 0.0 |
| `hud.balance` | hudCounter | balance, counter | BALANCE_CHANGE | SFX/UI | 0.0 |
| `hud.win` | hudMeter | win, meter, rollup | ROLLUP_START/END | SFX/Wins | 0.0 |
| `symbol.wild` | symbolZone | symbol, wild | WILD_LAND | SFX/Symbols | varies |
| `symbol.scatter` | symbolZone | symbol, scatter | SCATTER_LAND | SFX/Symbols | varies |
| `symbol.bonus` | symbolZone | symbol, bonus | BONUS_SYMBOL_LAND | SFX/Symbols | varies |
| `symbol.hp1-4` | symbolZone | symbol, hp{n} | SYMBOL_LAND_HP{n} | SFX/Symbols | varies |
| `symbol.lp1-4` | symbolZone | symbol, lp{n} | SYMBOL_LAND_LP{n} | SFX/Symbols | varies |
| `music.base` | musicZone | music, background, base | MUSIC_BASE | MUSIC/Base | 0.0 |
| `music.freespins` | musicZone | music, background, freespins | MUSIC_FS | MUSIC/Feature | 0.0 |
| `music.bonus` | musicZone | music, background, bonus | MUSIC_BONUS | MUSIC/Feature | 0.0 |
| `music.bigwin` | musicZone | music, background, bigwin | MUSIC_BIGWIN | MUSIC/Feature | 0.0 |
| `music.anticipation` | musicZone | music, background, anticipation | ANTICIPATION_MUSIC | MUSIC/Feature | 0.0 |

### 3.2 Target Type Colors

| TargetType | Color | Hex |
|------------|-------|-----|
| uiButton | Blue | `FluxForgeTheme.accentBlue` |
| uiToggle | Blue | `FluxForgeTheme.accentBlue` |
| reelSurface | Orange | `FluxForgeTheme.accentOrange` |
| reelStopZone | Orange | `FluxForgeTheme.accentOrange` |
| symbolZone | Green | `FluxForgeTheme.accentGreen` |
| overlay | Cyan | `FluxForgeTheme.accentCyan` |
| featureContainer | Cyan | `FluxForgeTheme.accentCyan` |
| hudCounter | Gold | `#FFD700` |
| hudMeter | Gold | `#FFD700` |
| musicZone | Purple | `#9333EA` |
| screenZone | Gray | `FluxForgeTheme.textSecondary` |

---

## 4. DROP FLOW SPECIFICATION

### 4.1 Step-by-Step Flow

```
STEP 1: USER DRAGS AUDIO FILE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Location: Audio Browser Panel
Widget: DraggableAudioAsset
Data: AudioAsset { assetId, path, assetType, tags, durationMs }

STEP 2: DRAG OVER TARGET
━━━━━━━━━━━━━━━━━━━━━━━━
Widget: DropTargetWrapper (DragTarget<AudioAsset>)
Callback: onWillAcceptWithDetails() → return true
Effect: setState(() => _isDragOver = true)
Visual: Glow effect (2px border, 16px blur shadow)

STEP 3: DROP ON TARGET
━━━━━━━━━━━━━━━━━━━━━━
Callback: onAcceptWithDetails(DragTargetDetails<AudioAsset>)
Effect: setState(() => _isDragOver = false)
         _handleDrop(details.data, details.offset)

STEP 4: CREATE DRAFT
━━━━━━━━━━━━━━━━━━━━
Method: AutoEventBuilderProvider.createDraft(asset, target)
Logic:
  1. Find matching DropRule based on asset.tags + target.targetType
  2. Generate eventId from rule.eventIdTemplate
  3. Ensure unique ID (append suffix if collision)
  4. Create EventDraft {
       eventId, target, asset, trigger, bus, presetId,
       stageContext, variationPolicy, tags, paramOverrides
     }
  5. notifyListeners()

STEP 5: SHOW QUICKSHEET
━━━━━━━━━━━━━━━━━━━━━━━
Widget: QuickSheet popup at drop position
Content:
  - Event name (editable)
  - Trigger selector (from target.interactionSemantics)
  - Bus selector (auto-selected from rule)
  - Preset selector
  - Parameter overrides (volume, pan, etc.)
Actions:
  - [Cancel] → provider.cancelDraft()
  - [Commit] → onCommit callback

STEP 6: COMMIT EVENT
━━━━━━━━━━━━━━━━━━━━
Method: AutoEventBuilderProvider.commitDraft()
Logic:
  1. Get preset for parameters
  2. Calculate spatial params (per-reel auto-pan)
  3. Create CommittedEvent {
       eventId, intent, assetPath, bus, presetId,
       voiceLimitGroup, variationPolicy, tags, parameters,
       preloadPolicy, createdAt, pan, spatialMode,
       dependencies, conditionalTrigger, rtpcBindings
     }
  4. Create EventBinding { bindingId, eventId, targetId, stageId, trigger }
  5. Add to _events and _bindings lists
  6. Add to _undoStack
  7. Mark asset as recently used
  8. Clear draft
  9. notifyListeners()
  10. Return CommittedEvent

STEP 7: PULSE ANIMATION
━━━━━━━━━━━━━━━━━━━━━━━
Widget: DropTargetWrapper._triggerPulse()
Animation: Scale 1.0 → 1.15 → 1.0 over 300ms
Visual: Green glow during pulse

STEP 8: CALLBACK
━━━━━━━━━━━━━━━━
Callback: onEventCreated?.call(event)
Purpose: Allow parent widget to react to new event
         (e.g., sync to MiddlewareProvider)
```

### 4.2 Critical Integration Point: CommittedEvent → MiddlewareProvider

**STATUS: ✅ IMPLEMENTED** (2026-01-23)

The bridge is implemented in `slot_lab_screen.dart:_onEventBuilderEventCreated()`. When audio is dropped on a mockup element:

1. `CommittedEvent` is converted to `SlotCompositeEvent`
2. `SlotEventLayer` is created with proper:
   - Audio path
   - Volume, pan (per-reel auto-pan calculation)
   - Bus ID (mapped from bus name)
   - Offset, fade in/out
3. `SlotCompositeEvent` is added to `MiddlewareProvider` via `addCompositeEvent()`
4. `notifyListeners()` triggers `_onMiddlewareChanged()`
5. Timeline is automatically updated with event and all layers
6. `EventRegistry` is automatically synced via `_syncEventToRegistry()`

**Implementation Location:** `slot_lab_screen.dart:5824-6029`

**Key Methods:**
- `_onEventBuilderEventCreated()` — Main bridge function
- `_generateEventNameFromTarget()` — Human-readable event name
- `_targetIdToStage()` — Map targetId to canonical stage name
- `_busNameToId()` — Map bus name to SlotBusIds constant
- `_calculatePanFromTarget()` — Per-reel auto-pan (-0.8 to +0.8)
- `_categoryFromTargetId()` — Determine event category
- `_colorFromTargetId()` — Determine event color

**Track Creation for New Events:**
- `_rebuildRegionForEvent()` — Now auto-creates track if not exists
- `_createTrackForNewEvent()` — Creates FFI track for dropped event

---

## 5. BIDIRECTIONAL SYNC MECHANISM

### 5.1 Sync Chain

```
┌────────────────────────────────────────────────────────────────────┐
│                    SYNC CHAIN DIAGRAM                               │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────┐                                                │
│  │  DROP ON TARGET │                                                │
│  └────────┬────────┘                                                │
│           │                                                         │
│           ▼                                                         │
│  ┌─────────────────┐    ┌─────────────────────────────────────┐    │
│  │ AutoEventBuilder│    │ onEventCreated callback MUST:       │    │
│  │ .commitDraft()  │───►│ 1. Convert CommittedEvent →         │    │
│  │                 │    │    SlotCompositeEvent                │    │
│  │ CommittedEvent  │    │ 2. Call middleware.addCompositeEvent│    │
│  └─────────────────┘    └─────────────────────────────────────┘    │
│                                    │                                │
│                                    ▼                                │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              MIDDLEWARE PROVIDER (SSoT)                      │   │
│  │  compositeEvents.add(event)                                  │   │
│  │  notifyListeners() ─────────────────────────────────────────►│   │
│  └────────────────────────────────┬────────────────────────────┘   │
│                                   │                                 │
│           ┌───────────────────────┼───────────────────────┐        │
│           │                       │                       │        │
│           ▼                       ▼                       ▼        │
│  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐  │
│  │ SlotLabScreen   │   │ EventRegistry   │   │ MiddlewarePanel │  │
│  │                 │   │                 │   │                 │  │
│  │ _onMiddleware   │   │ registerEvent() │   │ Events Folder   │  │
│  │ Changed():      │   │                 │   │ updates UI      │  │
│  │                 │   │ AudioEvent {    │   │                 │  │
│  │ • _rebuildRegion│   │   stage,        │   │                 │  │
│  │   ForEvent()    │   │   layers        │   │                 │  │
│  │ • _syncEventTo  │   │ }               │   │                 │  │
│  │   Registry()    │   │                 │   │                 │  │
│  │ • _syncLayersTo │   │ Used for:       │   │                 │  │
│  │   TrackManager()│   │ triggerStage()  │   │                 │  │
│  └─────────────────┘   └─────────────────┘   └─────────────────┘  │
│           │                                                        │
│           ▼                                                        │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                    TIMELINE UI                               │  │
│  │  _AudioRegion appears with all layers from event             │  │
│  │  Each layer is draggable on timeline                         │  │
│  │  Layer offset changes → middleware.setLayerOffset()          │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### 5.2 Sync Methods in SlotLabScreen

| Method | Location | Purpose |
|--------|----------|---------|
| `_onMiddlewareChanged()` | slot_lab_screen.dart:754 | React to MiddlewareProvider changes |
| `_rebuildRegionForEvent()` | slot_lab_screen.dart | Rebuild _AudioRegion layers from event |
| `_syncEventToRegistry()` | slot_lab_screen.dart | Convert SlotCompositeEvent → AudioEvent |
| `_syncAllEventsToRegistry()` | slot_lab_screen.dart:7934 | Sync all events on init/mode switch |
| `_syncLayersToTrackManager()` | slot_lab_screen.dart | Update TrackManager for playback |

### 5.3 Critical Code Sections

**slot_lab_screen.dart:754-779** — Main sync handler:
```dart
void _onMiddlewareChanged() {
  if (_draggingLayerId != null) {
    // Don't trigger rebuild during drag
    for (final event in _compositeEvents) {
      _rebuildRegionForEvent(event);
      _syncEventToRegistry(event);
    }
    _syncLayersToTrackManager();
    return;
  }

  // Rebuild region layers to match updated events from MiddlewareProvider
  for (final event in _compositeEvents) {
    _rebuildRegionForEvent(event);
    _syncEventToRegistry(event);
  }

  _syncLayersToTrackManager();
  setState(() {});
}
```

---

## 6. VISUAL FEEDBACK SPECIFICATION

### 6.1 Drag Over State

```dart
// Border glow
Border.all(
  color: _targetColor.withOpacity(0.8),
  width: 2,
)

// Box shadow (outer glow)
BoxShadow(
  color: _targetColor.withOpacity(0.4),
  blurRadius: 16,
  spreadRadius: 2,
),
BoxShadow(
  color: _targetColor.withOpacity(0.2),
  blurRadius: 32,
  spreadRadius: 4,
),

// Overlay content
Icon(Icons.add_circle_outline, size: 32, color: _targetColor)
Text('Drop to create event')
```

### 6.2 Pulse Animation (On Commit)

```dart
// Scale animation
Tween<double>(begin: 1.0, end: 1.15)
Duration: 300ms
Curve: Curves.easeOutCubic

// Green glow during pulse
BoxShadow(
  color: FluxForgeTheme.accentGreen.withOpacity(0.5),
  blurRadius: 20,
  spreadRadius: 3,
)
```

### 6.3 Event Count Badge

```dart
// Positioned at badgeAlignment (default: topRight)
// Shows count of events bound to this target
// Color matches target type
Container(
  constraints: BoxConstraints(minWidth: 18, minHeight: 18),
  decoration: BoxDecoration(
    color: _targetColor,
    borderRadius: BorderRadius.circular(9),
    boxShadow: [
      BoxShadow(
        color: _targetColor.withOpacity(0.4),
        blurRadius: 4,
        spreadRadius: 1,
      ),
    ],
  ),
  child: Text(count > 99 ? '99+' : count.toString()),
)
```

---

## 7. PER-REEL SPATIAL POSITIONING

### 7.1 Auto-Pan Calculation

Za `TargetType.reelStopZone`, sistem automatski računa pan vrednost na osnovu indeksa reel-a:

```dart
// Parse reel index from targetId (e.g., "reel.2" → 2)
final reelIndex = _parseReelIndex(target.targetId);

// Map reel 0-4 to pan -0.8 to +0.8 (5 reels standard)
// Reel 0 → -0.8 (left)
// Reel 1 → -0.4
// Reel 2 → 0.0 (center)
// Reel 3 → +0.4
// Reel 4 → +0.8 (right)
final pan = (reelIndex - 2) * 0.4;  // Center at reel 2
return (pan.clamp(-1.0, 1.0), SpatialMode.autoPerReel);
```

### 7.2 Pan Values Table

| Target ID | Reel Index | Pan Value | Stereo Position |
|-----------|------------|-----------|-----------------|
| reel.0 | 0 | -0.8 | Hard Left |
| reel.1 | 1 | -0.4 | Left |
| reel.2 | 2 | 0.0 | Center |
| reel.3 | 3 | +0.4 | Right |
| reel.4 | 4 | +0.8 | Hard Right |

---

## 8. DROP RULES ENGINE

### 8.1 Standard Rules (Priority Order)

| Rule ID | Priority | Asset Match | Target Match | Event ID Template | Bus |
|---------|----------|-------------|--------------|-------------------|-----|
| `ui_primary_click` | 100 | tags: click, press | type: uiButton, tags: primary, cta | `{target}.click_primary` | SFX/UI |
| `reel_spin` | 100 | tags: spin, loop, reel | type: reelSurface | `reel.spin` | SFX/Reels |
| `reel_stop` | 100 | tags: stop, impact, reel | type: reelStopZone | `{target}.stop` | SFX/Reels |
| `anticipation` | 100 | tags: anticipation | any | `anticipation.{target}` | SFX/Features |
| `win_big` | 100 | tags: bigwin, fanfare | type: overlay | `win.big` | SFX/Wins |
| `music_base` | 100 | type: music, tags: loop | any | `music.base` | MUSIC/Base |
| `music_feature` | 100 | type: music, tags: feature | any | `music.feature` | MUSIC/Feature |
| `ui_secondary_click` | 90 | tags: click | type: uiButton | `{target}.click_secondary` | SFX/UI |
| `win_small` | 90 | tags: win | type: overlay, tags: win | `win.small` | SFX/Wins |
| `ui_hover` | 80 | tags: hover, whoosh | type: uiButton | `{target}.hover` | SFX/UI |
| `fallback_sfx` | 1 | type: sfx | any | `{target}.{asset}` | SFX |

### 8.2 Rule Matching Algorithm

```dart
for (final rule in _rules) {  // Sorted by priority descending
  // 1. Check asset type if specified
  if (rule.assetType != null && asset.assetType != rule.assetType) continue;

  // 2. Check target type if specified
  if (rule.targetType != null && target.targetType != rule.targetType) continue;

  // 3. Check asset tags (any match)
  if (rule.assetTags.isNotEmpty && !asset.hasAnyTag(rule.assetTags)) continue;

  // 4. Check target tags (any match)
  if (rule.targetTags.isNotEmpty && !target.hasAnyTag(rule.targetTags)) continue;

  return rule;  // First matching rule wins
}
return StandardDropRules.fallbackSfx;  // Default
```

---

## 9. EVENT PRESETS

### 9.1 Standard Presets

| Preset ID | Volume | Pitch | Pan | LPF | HPF | Delay | Cooldown | Polyphony | Bus |
|-----------|--------|-------|-----|-----|-----|-------|----------|-----------|-----|
| `ui_click_primary` | 0.85 | 1.0 | 0.0 | 20000 | 20 | 0 | 50 | 1 | SFX/UI |
| `ui_click_secondary` | 0.75 | 1.0 | 0.0 | 20000 | 20 | 0 | 50 | 1 | SFX/UI |
| `ui_hover` | 0.5 | 1.0 | 0.0 | 15000 | 20 | 0 | 100 | 1 | SFX/UI |
| `reel_spin` | 0.7 | 1.0 | 0.0 | 20000 | 20 | 0 | 0 | 1 | SFX/Reels |
| `reel_stop` | 0.9 | 1.0 | 0.0 | 20000 | 20 | 0 | 0 | 5 | SFX/Reels |
| `anticipation` | 0.8 | 1.0 | 0.0 | 20000 | 20 | 0 | 0 | 1 | SFX/Features |
| `win_small` | 0.8 | 1.0 | 0.0 | 20000 | 20 | 0 | 0 | 1 | SFX/Wins |
| `win_big` | 1.0 | 1.0 | 0.0 | 20000 | 20 | 0 | 0 | 1 | SFX/Wins |
| `music_base` | 0.6 | 1.0 | 0.0 | 20000 | 20 | 0 | 0 | 1 | MUSIC/Base |
| `music_feature` | 0.7 | 1.0 | 0.0 | 20000 | 20 | 0 | 0 | 1 | MUSIC/Feature |

---

## 10. FILE LOCATIONS

### 10.1 Core Files

| File | LOC | Purpose |
|------|-----|---------|
| `widgets/slot_lab/auto_event_builder/drop_target_wrapper.dart` | 558 | DropTargetWrapper, DraggableAudioAsset |
| `widgets/slot_lab/auto_event_builder/droppable_slot_preview.dart` | 1119 | SlotDropZones, Droppable* wrappers |
| `widgets/slot_lab/auto_event_builder/quick_sheet.dart` | ~400 | QuickSheet popup |
| `providers/auto_event_builder_provider.dart` | 2360 | AutoEventBuilderProvider, CommittedEvent |
| `models/auto_event_builder_models.dart` | ~800 | DropTarget, AudioAsset, EventPreset |
| `services/event_sync_service.dart` | 434 | EventSyncService (EventRegistry ↔ MiddlewareProvider) |
| `services/event_registry.dart` | 1350 | EventRegistry, AudioEvent, triggerStage() |
| `providers/middleware_provider.dart` | 3500+ | MiddlewareProvider (SSoT for compositeEvents) |
| `screens/slot_lab_screen.dart` | 8800+ | Main SlotLab screen, timeline integration |

### 10.2 Model Files

| File | Key Classes |
|------|-------------|
| `models/auto_event_builder_models.dart` | DropTarget, TargetType, AudioAsset, AssetType, EventPreset, StageContext |
| `models/slot_audio_events.dart` | SlotCompositeEvent, SlotEventLayer |
| `models/middleware_models.dart` | Broader middleware models |

---

## 11. VALIDATION CHECKLIST

Before any modification to the drop zone system, verify:

- [ ] `DropTargetWrapper` visual feedback matches spec (glow, pulse, badge)
- [ ] All target IDs in `SlotDropZones` match catalog (Section 3.1)
- [ ] Per-reel pan calculation uses formula: `(reelIndex - 2) * 0.4`
- [ ] Drop rules are sorted by priority (highest first)
- [ ] `onEventCreated` callback bridges to `MiddlewareProvider.addCompositeEvent()`
- [ ] Timeline shows event with all layers immediately after drop
- [ ] EventRegistry receives synced AudioEvent for stage triggering
- [ ] Undo/redo works for drop-created events

---

## 12. APPENDIX: DROPPABLE WIDGET CATALOG

### 12.1 Available Wrapper Widgets

| Widget | Target | Usage |
|--------|--------|-------|
| `DroppableSpinButton` | ui.spin | Wrap spin button |
| `DroppableControlButton` | configurable | Wrap any UI button |
| `DroppableReelFrame` | reel.0-4 (column only) | Wrap reel area with REEL-LEVEL zones only (no cell zones) |
| `DroppableWinOverlay` | overlay.win.{tier} | Wrap win display |
| `DroppableJackpotDisplay` | overlay.jackpot.{tier} | Wrap jackpot ticker |
| `DroppableFeatureIndicator` | feature.{name} | Wrap feature UI |
| `DroppableHudElement` | hud.{type} | Wrap HUD counters/meters |
| `DroppableSymbolZone` | symbol.{type} | Wrap symbol areas |
| `DroppableMusicZone` | music.{context} | Wrap music trigger zones |

### 12.2 Usage Example

```dart
// Wrap spin button
DroppableSpinButton(
  onEventCreated: (event) {
    // Bridge to MiddlewareProvider
    _addEventToMiddleware(event);
  },
  child: SpinButton(...),
)

// Wrap reel frame with per-reel zones
DroppableReelFrame(
  reelCount: 5,
  onReelEventCreated: (reelIndex, event) {
    // Event has per-reel pan already calculated
    _addEventToMiddleware(event);
  },
  onSurfaceEventCreated: (event) {
    _addEventToMiddleware(event);
  },
  child: ReelFrame(...),
)
```

---

## 13. IMPLEMENTATION STATUS

### 13.1 Implementation Changelog

| Date | Change | Status |
|------|--------|--------|
| 2026-01-23 | Initial specification document created | ✅ Done |
| 2026-01-23 | `_onEventBuilderEventCreated()` bridge implemented | ✅ Done |
| 2026-01-23 | `_targetIdToStage()` mapping (30+ stages) | ✅ Done |
| 2026-01-23 | `_busNameToId()` mapping (8 buses) | ✅ Done |
| 2026-01-23 | Per-reel auto-pan calculation | ✅ Done |
| 2026-01-23 | `_rebuildRegionForEvent()` auto-creates track | ✅ Done |
| 2026-01-23 | `_createTrackForNewEvent()` method added | ✅ Done |
| **2026-01-25** | **v1.1.0: Removed individual cell drop zones** | ✅ Done |
| 2026-01-25 | `_buildCellDropZone()` method removed | ✅ Done |
| 2026-01-25 | Reel-level only architecture (no per-cell targets) | ✅ Done |

### 13.2 Verified Bidirectional Sync Chain

```
Drop Audio on Mockup Element
        │
        ▼
DropTargetWrapper._handleDrop()
        │
        ▼
AutoEventBuilderProvider.commitDraft() → CommittedEvent
        │
        ▼
_onEventBuilderEventCreated() — BRIDGE (IMPLEMENTED ✅)
        │
        ├── Converts CommittedEvent → SlotCompositeEvent
        ├── Maps targetId → stage, bus, pan, category, color
        │
        ▼
MiddlewareProvider.addCompositeEvent() → notifyListeners()
        │
        ▼
SlotLabScreen._onMiddlewareChanged()
        │
        ├── _rebuildRegionForEvent() — Creates track if not exists (IMPLEMENTED ✅)
        │       └── _createTrackForNewEvent() — FFI track + UI track
        │
        ├── _syncEventToRegistry() — AudioEvent for stage triggering
        │
        └── _syncLayersToTrackManager() — Playback integration
                │
                ▼
        TIMELINE SHOWS EVENT WITH ALL LAYERS ✅
```

### 13.3 Test Verification Procedure

1. Open SlotLab in FluxForge Studio
2. Enable DROP mode (toggle button)
3. Drag audio file from Audio Browser
4. Drop on any mockup element (spin button, reel, etc.)
5. Verify:
   - QuickSheet popup appears
   - Click Commit
   - Event appears in Events Folder (right panel)
   - Track appears in timeline
   - Region shows on track with layer
   - Event Log shows triggered stage

---

**END OF SPECIFICATION**

*This document is the authoritative reference for the SlotLab Drop Zone System. Any changes to the system must update this specification first.*
