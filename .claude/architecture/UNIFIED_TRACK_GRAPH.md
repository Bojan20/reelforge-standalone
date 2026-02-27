# Unified Track Graph — DAW ↔ SlotLab Shared Engine Architecture

**Created:** 2026-02-27
**Status:** APPROVED — Architecture Spec

---

## 1. CORE PRINCIPLE

DAW and SlotLab share the SAME rf-engine instance. One audio graph. Two UI views. Zero sync, zero export, zero duplication.

```
                    ┌─────────────────────────┐
                    │     rf-engine (Rust)      │
                    │                           │
                    │  Track[] ──→ InsertChain  │
                    │  Bus[] ──→ DSP            │
                    │  Master ──→ DSP           │
                    │                           │
                    └──────┬──────────┬─────────┘
                           │          │
                    ┌──────┴───┐ ┌────┴──────┐
                    │  DAW UI  │ │ SlotLab UI│
                    │          │ │           │
                    │ Timeline │ │ Event     │
                    │ Mixer    │ │ Mapper    │
                    │ Editor   │ │ Gameplay  │
                    └──────────┘ └───────────┘
```

**What DAW sees:** Tracks, waveforms, faders, inserts, sends — pure audio production.
**What SlotLab sees:** Same tracks, organized by events — gameplay logic + conditions.
**What rf-engine knows:** Tracks, buffers, DSP. It doesn't care who's looking.

---

## 2. OWNERSHIP RULES

### Structure (one-way: SlotLab → DAW)

SlotLab OWNS event/layer structure. DAW receives and displays.

| Operation | Who initiates | DAW effect |
|-----------|--------------|------------|
| Create event | SlotLab | Event folder appears in DAW left panel |
| Delete event | SlotLab | Event folder removed from DAW left panel |
| Add layer to event | SlotLab | Audio track appears inside event folder |
| Remove layer | SlotLab | Track removed from event folder |
| Reorder layers | SlotLab | Track order updated in folder |
| Rename event | SlotLab | Folder name updated |

**DAW CANNOT:** Create, delete, rename, or restructure event folders. They are read-only containers.

### Audio parameters (bidirectional: DAW ↔ SlotLab)

Both UIs can modify audio parameters. Changes are instant in both directions.

| Operation | DAW | SlotLab | Effect |
|-----------|-----|---------|--------|
| Volume change | ✅ fader | ✅ layer slider | rf-engine volume updates, both UIs reflect |
| Pan change | ✅ knob | ✅ slider | Same |
| Mute/Solo | ✅ buttons | ✅ buttons | Same |
| Add insert | ✅ slot click | ✅ slot click | Same |
| Insert params | ✅ FabFilter panel | ✅ FabFilter panel | Same |
| Send levels | ✅ knobs | ✅ sliders | Same |
| Output bus | ✅ dropdown | ✅ dropdown | Same |

---

## 3. EVENT FOLDER BEHAVIOR IN DAW

### Left Panel Display

Event folders appear in DAW's left panel, created from SlotLab:

```
┌─ EVENT FOLDERS ──────────────┐
│                               │
│ 📁 onSpinStart          🔒   │  ← read-only structure
│   ├─ 🎵 Base Loop            │  ← audio track (layer 0)
│   ├─ 🎵 Percussion           │  ← audio track (layer 1)
│   └─ 🎵 Transition           │  ← audio track (layer 2)
│                               │
│ 📁 onReelStop            🔒   │
│   ├─ 🎵 Stop Thud            │
│   └─ 🎵 Reel Click           │
│                               │
│ 📁 onWinEvaluate         🔒   │
│   ├─ 🎵 Win Sting            │
│   └─ 🎵 Coin FX              │
│                               │
└───────────────────────────────┘
```

🔒 = structure is read-only (managed by SlotLab)

### Timeline Placement — Manual Drag

Tracks from event folders are NOT in the timeline by default. Sound designer manually drags them in when they want to edit/mix:

```
LEFT PANEL:                        TIMELINE:
┌─ EVENT FOLDERS ─────┐            ┌──────────────────────────┐
│ 📁 onSpinStart      │            │                          │
│   ├─ 🎵 Base Loop ──│── drag ──→ │ 🎵 Base Loop ▓▓▓▓░░░░  │
│   ├─ 🎵 Percussion  │            │                          │
│   └─ 🎵 Transition  │            │                          │
└──────────────────────┘            └──────────────────────────┘
```

Once in timeline: full editing (trim, fade, crossfade, move clips, add automation).
All edits apply to the SAME track in rf-engine — SlotLab sees them instantly.

---

## 4. DATA MODEL

### SlotLab side — Event definition (gameplay logic owner)

```dart
class SlotEvent {
  final String id;              // "onSpinStart"
  final SlotEventType type;     // spin, reelStop, win, feature, cascade, jackpot
  final String linkedFolderId;  // maps to DAW folder for visual sync
  final List<LayerRef> layers;  // references to tracks
  final int priority;           // voice priority (critical/high/medium/low)
  final int maxPolyphony;       // max simultaneous layers
  final double crossfadeInMs;   // transition envelope
  final double crossfadeOutMs;
}

class LayerRef {
  final int trackId;            // points to rf-engine track
  final String? condition;      // "bet > 5", "win > 100x", null = always
  final double weight;          // random selection weight for variants
  final int layerIndex;         // order within event
}
```

### DAW side — Event folder (display-only container)

```dart
class EventFolder {
  final String id;              // "folder_onSpinStart"
  final String eventId;         // linked SlotEvent.id
  final String name;            // display name (from event)
  final Color color;            // from event type
  final List<int> childTrackIds; // ordered track IDs (from layers)
  final bool isCollapsed;       // UI state
  // NO gameplay logic here — just visual grouping
}
```

### Shared — Track (rf-engine owns, both UIs read/write)

```dart
// Existing TimelineTrack — NO CHANGES needed
// DAW sees it as audio track
// SlotLab sees it as event layer
// Same object, same provider, same engine
```

---

## 5. PROVIDER ARCHITECTURE

```
┌─────────────────────────────────────────────┐
│           TrackProvider (singleton)           │
│  - tracks: List<Track>                       │
│  - setVolume(trackId, dB)                    │
│  - setPan(trackId, pan)                      │
│  - setMute(trackId, bool)                    │
│  - addInsert(trackId, slotIndex, type)       │
│  - ...all track operations...                │
│                                              │
│  Both DAW and SlotLab call same methods      │
│  notifyListeners() updates BOTH UIs          │
└──────────────────────┬──────────────────────┘
                       │
         ┌─────────────┼─────────────┐
         │             │             │
┌────────┴───┐  ┌──────┴──────┐  ┌──┴──────────┐
│ DAW Widget │  │ SlotLab     │  │ EventFolder │
│ Tree       │  │ Widget Tree │  │ Provider    │
│            │  │             │  │ (new)       │
│ Timeline   │  │ Event List  │  │             │
│ Mixer      │  │ Layer View  │  │ Manages     │
│ Inspector  │  │ Conditions  │  │ folder↔event│
│            │  │ Preview     │  │ mapping     │
└────────────┘  └─────────────┘  └─────────────┘
```

### EventFolderProvider (NEW — GetIt singleton)

```dart
class EventFolderProvider extends ChangeNotifier {
  final Map<String, EventFolder> _folders = {};

  // Called by SlotLab when event is created
  void createFolderForEvent(SlotEvent event) {
    _folders[event.id] = EventFolder(
      id: 'folder_${event.id}',
      eventId: event.id,
      name: event.id,
      color: _colorForEventType(event.type),
      childTrackIds: event.layers.map((l) => l.trackId).toList(),
    );
    notifyListeners(); // DAW left panel rebuilds
  }

  // Called by SlotLab when event is deleted
  void removeFolderForEvent(String eventId) { ... }

  // Called by SlotLab when layers change
  void updateFolderLayers(String eventId, List<int> trackIds) { ... }

  // DAW reads this for left panel display
  List<EventFolder> get folders => _folders.values.toList();
}
```

---

## 6. TRACK REUSE ACROSS EVENTS

A single track can be a layer in MULTIPLE events:

```
SlotLab:
  Event "onSpinStart" → layers: [Track 0, Track 1, Track 2]
  Event "onWinEvaluate" → layers: [Track 3, Track 0]  ← Track 0 reused!

DAW Left Panel:
  📁 onSpinStart
    ├─ 🎵 Track 0 (Bass)     ← appears here
    ├─ 🎵 Track 1
    └─ 🎵 Track 2
  📁 onWinEvaluate
    ├─ 🎵 Track 3
    └─ 🎵 Track 0 (Bass)     ← AND here (same track, shown in both)
```

Editing Track 0 in DAW timeline affects BOTH events. One mix, everywhere.

---

## 7. ZERO DEGRADATION GUARANTEE

Because it's one engine:
- **No conversion** — audio never passes through export/import
- **No resampling** — same buffers, same sample rate
- **No float rounding** — same DSP chain
- **No latency difference** — same audio thread
- **Bit-perfect** — what you hear in DAW = what plays in SlotLab preview = what ships

---

## 8. WHAT THIS REPLACES

| Old Way (Industry Standard) | FluxForge Way |
|-----------------------------|---------------|
| Compose in DAW | Compose in DAW |
| Export stems | ~~Export stems~~ (not needed) |
| Import into Wwise/FMOD | ~~Import~~ (already there) |
| Re-configure volume/EQ/bus | ~~Re-configure~~ (already set) |
| Test → doesn't sound right → go back to DAW | Switch tab → instant |
| 5+ steps per iteration | 0 steps — just switch tabs |

---

## 9. IMPLEMENTATION PHASES

See MASTER_TODO.md for task breakdown.
