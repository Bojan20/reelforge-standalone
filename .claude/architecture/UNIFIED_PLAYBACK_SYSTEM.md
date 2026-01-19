# Unified Playback System — FluxForge Studio

## Overview

Centralizovani sistem za upravljanje audio playback-om kroz sve sekcije aplikacije.

**Single Source of Truth:** `UnifiedPlaybackController`

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    UNIFIED PLAYBACK CONTROLLER                           │
│                    (Single Source of Truth)                              │
│  ┌──────────────┬──────────────┬──────────────┬──────────────┐          │
│  │     DAW      │   SlotLab    │  Middleware  │   Browser    │          │
│  │  Timeline    │   Timeline   │   Preview    │   Preview    │          │
│  │  (acquire)   │  (acquire)   │  (acquire)   │  (isolated)  │          │
│  └──────┬───────┴──────┬───────┴──────┬───────┴──────┬───────┘          │
│         │              │              │              │                   │
│         └──────────────┴──────┬───────┴──────────────┘                   │
│                               ▼                                          │
│              ┌────────────────────────────────┐                         │
│              │       PLAYBACK_ENGINE          │                         │
│              │   (play/pause/stop/seek)       │                         │
│              │   Timeline-driven, Multi-track │                         │
│              └────────────────────────────────┘                         │
│                                                                          │
│              ┌────────────────────────────────┐                         │
│              │       PREVIEW_ENGINE           │ ← Browser ONLY          │
│              │   (isolated one-shot)          │                         │
│              │   Ne ometa PLAYBACK_ENGINE     │                         │
│              └────────────────────────────────┘                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## SlotLab & Middleware Relationship (CRITICAL)

**SlotLab i Middleware su DVA POGLEDA na ISTE PODATKE.**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     SHARED DATA LAYER                                    │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  EventRegistry (singleton)                                       │    │
│  │  ├── CompositeEvents                                             │    │
│  │  ├── AudioLayers                                                 │    │
│  │  ├── Stage → Event mappings                                      │    │
│  │  └── Preloaded audio paths                                       │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                          ▲                    ▲                          │
│                          │                    │                          │
│              ┌───────────┴────────┐ ┌────────┴───────────┐              │
│              │    SLOT LAB UI     │ │   MIDDLEWARE UI    │              │
│              ├────────────────────┤ ├────────────────────┤              │
│              │ - Timeline View    │ │ - Event List       │              │
│              │ - Slot Machine     │ │ - Layer Editor     │              │
│              │ - Stage Trace      │ │ - RTPC Panels      │              │
│              │ - Waveforms        │ │ - Ducking Matrix   │              │
│              ├────────────────────┤ ├────────────────────┤              │
│              │ PLAYBACK_ENGINE    │ │ PREVIEW_ENGINE     │              │
│              │ (timeline play)    │ │ (event preview)    │              │
│              └────────────────────┘ └────────────────────┘              │
└─────────────────────────────────────────────────────────────────────────┘
```

### Bidirectional Sync

| Akcija u SlotLab | Efekat u Middleware |
|------------------|---------------------|
| Dodaj layer na event | Vidi se odmah u Layer Editor |
| Pomeri region | Timeline pozicija se ažurira |
| Promeni volume | Volume slider se ažurira |
| Obriši event | Event nestaje iz liste |

| Akcija u Middleware | Efekat u SlotLab |
|---------------------|------------------|
| Edituj layer | Waveform/region se ažurira |
| Promeni stage mapping | Stage trace prikazuje novi event |
| Dodaj novi event | Pojavljuje se na timeline |

### Playback Modes

| UI | Engine | Svrha |
|----|--------|-------|
| **SlotLab** | `PLAYBACK_ENGINE` | Timeline playback kroz stage sekvence |
| **Middleware** | `PREVIEW_ENGINE` | One-shot preview pojedinačnih eventa |

---

## PlaybackSection Enum

```dart
enum PlaybackSection {
  /// DAW timeline editing and playback
  daw,

  /// Slot Lab stage preview and spin playback
  slotLab,

  /// Middleware event testing (preview)
  middleware,

  /// Audio browser hover preview (uses PREVIEW_ENGINE, always isolated)
  browser,
}
```

---

## Section Acquisition Flow

```dart
// 1. Acquire section BEFORE playback
if (UnifiedPlaybackController.instance.acquireSection(PlaybackSection.daw)) {
  // 2. Now this section owns playback
  UnifiedPlaybackController.instance.play();
}

// 3. Release when done
UnifiedPlaybackController.instance.releaseSection(PlaybackSection.daw);
```

### Acquisition Rules

| Scenario | Behavior |
|----------|----------|
| No active section | Acquire succeeds |
| Same section active | Acquire succeeds (already owns) |
| Different section active | Previous section STOPS, new acquires |
| Browser section | Always succeeds (PREVIEW_ENGINE isolated) |
| Recording active | Only DAW can acquire |

---

## Cross-Section Behavior

### When one section starts playback:

| Section Starting | DAW UI | SlotLab UI | Middleware UI |
|------------------|--------|------------|---------------|
| **DAW** | ▶ Active | ⏸ "Paused by DAW" | ⏸ "Paused by DAW" |
| **SlotLab** | ⏸ "Paused by SlotLab" | ▶ Active | ⏸ "Paused by SlotLab" |
| **Middleware** | ⏸ "Paused by Middleware" | ⏸ "Paused by Middleware" | ▶ Active |
| **Browser** | No change | No change | No change |

### SectionInterruption Tracking

```dart
class SectionInterruption {
  final PlaybackSection interruptedSection;
  final PlaybackSection interruptingSection;
  final DateTime timestamp;
  final double positionAtInterrupt;
}
```

---

## Implementation Files

### Core Controller

| File | Purpose |
|------|---------|
| `lib/services/unified_playback_controller.dart` | **PRIMARY** — Single source of truth |

### Integrated Providers

| File | Integration |
|------|-------------|
| `lib/providers/timeline_playback_provider.dart` | Uses `acquireSection(PlaybackSection.daw)` |
| `lib/providers/slot_lab_provider.dart` | Uses `acquireSection(PlaybackSection.slotLab)` |
| `lib/services/event_registry.dart` | Reads active section, routes to correct source |
| `lib/services/audio_playback_service.dart` | Delegated mode, respects controller |

### UI Widgets

| File | Purpose |
|------|---------|
| `lib/widgets/common/playback_section_indicator.dart` | Status indicator + interruption banner |

---

## UnifiedPlaybackController API

### State Getters

```dart
PlaybackSection? get activeSection;        // Currently active section
bool get hasActiveSection;                  // Any section active?
bool get isPlaying;                         // From PLAYBACK_ENGINE
double get position;                        // Current playhead position
bool get isRecording;                       // Recording blocks non-DAW
SectionInterruption? get lastInterruption;  // Last interruption info
```

### Section Control

```dart
bool acquireSection(PlaybackSection section);  // Acquire control
void releaseSection(PlaybackSection section);  // Release control
void clearInterruption();                      // Dismiss interruption UI
```

### Transport Controls

```dart
void play();                              // Start playback
void pause();                             // Pause playback
void stop({bool releaseAfterStop});       // Stop (optionally release)
void seek(double seconds);                // Seek to position
void togglePlayPause();                   // Toggle play/pause
```

### Scrubbing

```dart
void startScrub(double seconds);          // Begin scrub
void updateScrub(double seconds, double velocity);  // Update with velocity
void stopScrub();                         // End scrub
```

---

## Engine Assignment

| Section | Engine | Reason |
|---------|--------|--------|
| DAW Timeline | `PLAYBACK_ENGINE` | Multi-track, effects, bus routing |
| SlotLab Timeline | `PLAYBACK_ENGINE` | One-shot voices through buses |
| Middleware Events | `PLAYBACK_ENGINE` | One-shot voices through buses |
| Audio Browser | `PREVIEW_ENGINE` | Isolated hover preview |

---

## Bus Routing for Middleware/SlotLab

Middleware i SlotLab koriste one-shot voice sistem u PlaybackEngine koji prolazi kroz DAW buseve.

### Standard Bus Configuration (6 buses + Master)

FluxForge koristi **6 audio buseva plus Master** za slot game audio.

| ID | Name | Const | Primary Usage | Slot Lab Usage |
|----|------|-------|---------------|----------------|
| 0 | **SFX** | `BUS_SFX` | Sound effects, UI clicks | Reel stops, button clicks |
| 1 | **MUSIC** | `BUS_MUSIC` | Background music, loops | BGM, win jingles |
| 2 | **VOICE** | `BUS_VOICE` | VO, announcer | Win callouts, feature announcements |
| 3 | **AMBIENCE** | `BUS_AMBIENCE` | Ambient sounds | Casino atmosphere, crowd |
| 4 | **AUX** | `BUS_AUX` | Auxiliary routing | Special effects, stingers |
| 5 | **MASTER** | `BUS_MASTER` | Direct to master (bypass routing) | Final mixdown |

### Bus Routing Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         BUS ROUTING ARCHITECTURE                         │
│                                                                          │
│   SOURCES                    BUSES                      OUTPUT           │
│   ┌──────────┐              ┌─────────┐                                 │
│   │ REEL_STOP│───────────▶ │ 0: SFX  │──┐                              │
│   │ UI_CLICK │───────────▶ │         │  │                              │
│   └──────────┘              └─────────┘  │                              │
│                                          │                              │
│   ┌──────────┐              ┌─────────┐  │                              │
│   │ BGM_LOOP │───────────▶ │ 1: MUSIC│──┤                              │
│   │ WIN_MUSIC│───────────▶ │         │  │                              │
│   └──────────┘              └─────────┘  │                              │
│                                          │       ┌──────────────┐       │
│   ┌──────────┐              ┌─────────┐  ├─────▶│    MASTER    │──────▶│
│   │ CALLOUT  │───────────▶ │ 2: VOICE│──┤       │    OUTPUT    │       │
│   │ ANNOUNCE │───────────▶ │         │  │       └──────────────┘       │
│   └──────────┘              └─────────┘  │                              │
│                                          │                              │
│   ┌──────────┐              ┌─────────┐  │                              │
│   │ CROWD    │───────────▶ │3:AMBIENCE──┤                              │
│   │ CASINO   │───────────▶ │         │  │                              │
│   └──────────┘              └─────────┘  │                              │
│                                          │                              │
│   ┌──────────┐              ┌─────────┐  │                              │
│   │ STINGER  │───────────▶ │ 4: AUX  │──┘                              │
│   │ SPECIAL  │───────────▶ │         │                                  │
│   └──────────┘              └─────────┘                                  │
│                                                                          │
│   ┌──────────┐              ┌─────────┐                                 │
│   │ DIRECT   │───────────▶ │5: MASTER│──────────────────────────────▶  │
│   │ OUTPUT   │              │(bypass) │                                 │
│   └──────────┘              └─────────┘                                  │
└─────────────────────────────────────────────────────────────────────────┘
```

### Ducking Matrix (Slot Lab Default)

| Source Bus | Ducks | Amount | Attack | Release |
|------------|-------|--------|--------|---------|
| VOICE | MUSIC | -12dB | 50ms | 300ms |
| SFX (BigWin) | MUSIC | -18dB | 30ms | 500ms |
| VOICE | AMBIENCE | -6dB | 100ms | 200ms |

### Dart Constants

```dart
/// Standard bus IDs for FluxForge audio routing
class AudioBus {
  static const int sfx = 0;
  static const int music = 1;
  static const int voice = 2;
  static const int ambience = 3;
  static const int aux = 4;
  static const int master = 5;

  static const int count = 6;

  static String name(int id) => switch (id) {
    0 => 'SFX',
    1 => 'Music',
    2 => 'Voice',
    3 => 'Ambience',
    4 => 'Aux',
    5 => 'Master',
    _ => 'Unknown',
  };
}
```

### Rust Constants

```rust
/// Standard bus IDs for FluxForge audio routing
pub const BUS_SFX: u32 = 0;
pub const BUS_MUSIC: u32 = 1;
pub const BUS_VOICE: u32 = 2;
pub const BUS_AMBIENCE: u32 = 3;
pub const BUS_AUX: u32 = 4;
pub const BUS_MASTER: u32 = 5;
pub const BUS_COUNT: u32 = 6;
```

### API

```dart
// Play through specific bus
AudioPlaybackService.instance.playFileToBus(
  '/path/to/sound.wav',
  volume: 0.8,
  busId: 0,  // Sfx bus
  source: PlaybackSource.middleware,
);

// Stop specific voice
AudioPlaybackService.instance.stopOneShotVoice(voiceId);

// Stop all one-shots
AudioPlaybackService.instance.stopAllOneShots();
```

### Rust FFI

```rust
// Play one-shot through bus
engine_playback_play_to_bus(path, volume, bus_id) -> voice_id

// Stop voice
engine_playback_stop_one_shot(voice_id)

// Stop all
engine_playback_stop_all_one_shots()
```

---

## Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| UnifiedPlaybackController | ✅ Complete | Singleton, all transport ops |
| TimelinePlaybackProvider integration | ✅ Complete | Uses acquireSection |
| SlotLabProvider integration | ✅ Complete | Uses acquireSection |
| EventRegistry source routing | ✅ Complete | Reads active section |
| AudioPlaybackService delegated mode | ✅ Complete | Respects controller |
| PlaybackSectionIndicator widget | ✅ Complete | Status + interruption UI |
| SlotLab/Middleware bidirectional sync | ✅ Existing | Via EventRegistry singleton |
| **One-shot bus routing** | ✅ Complete | Middleware/SlotLab through DAW buses |
| **playFileToBus API** | ✅ Complete | FFI + Dart bindings |
| **OneShotVoice in PlaybackEngine** | ✅ Complete | Lock-free voice system |

---

## Debug Entry Points

1. **Active Section**: `UnifiedPlaybackController.instance.activeSection`
2. **Is Playing**: `UnifiedPlaybackController.instance.isPlaying`
3. **Position**: `UnifiedPlaybackController.instance.position`
4. **Last Interruption**: `UnifiedPlaybackController.instance.lastInterruption`
5. **FFI Load**: `NativeFFI.instance.isLoaded`
6. **Audio Stream**: Check Rust `AUDIO_STREAM_RUNNING` atomic

---

## Usage Examples

### DAW Timeline Playback

```dart
class TimelinePlaybackProvider {
  Future<void> play() async {
    final controller = UnifiedPlaybackController.instance;
    if (!controller.acquireSection(PlaybackSection.daw)) {
      return; // Failed to acquire
    }
    controller.play();
    // ... start ticker for UI updates
  }

  void stop() {
    UnifiedPlaybackController.instance.stop(releaseAfterStop: true);
  }
}
```

### SlotLab Stage Playback

```dart
class SlotLabProvider {
  void _playStagesSequentially() {
    final controller = UnifiedPlaybackController.instance;
    if (!controller.acquireSection(PlaybackSection.slotLab)) {
      return; // DAW or Middleware is playing
    }
    // ... play stages via EventRegistry
  }

  void stopStagePlayback() {
    UnifiedPlaybackController.instance.releaseSection(PlaybackSection.slotLab);
  }
}
```

### EventRegistry Source Detection

```dart
Future<void> _playLayer(AudioLayer layer, ...) async {
  final activeSection = UnifiedPlaybackController.instance.activeSection;
  final source = switch (activeSection) {
    PlaybackSection.daw => PlaybackSource.daw,
    PlaybackSection.slotLab => PlaybackSource.slotlab,
    PlaybackSection.middleware => PlaybackSource.middleware,
    PlaybackSection.browser => PlaybackSource.browser,
    null => PlaybackSource.middleware, // Fallback
  };

  AudioPlaybackService.instance.previewFile(path, source: source);
}
```

---

## Related Documentation

- `.claude/architecture/SLOT_LAB_SYSTEM.md` — SlotLab architecture
- `.claude/architecture/ENGINE_INTEGRATION_SYSTEM.md` — Engine integration
- `.claude/project/fluxforge-studio.md` — Full project spec
