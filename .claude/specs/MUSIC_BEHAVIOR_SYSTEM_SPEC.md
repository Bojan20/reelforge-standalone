# Music Behavior System Specification

**Date:** 2026-01-31
**Status:** ✅ IMPLEMENTED

---

## Overview

Implementiran je sistem za inteligentno ponašanje muzike u SlotLab-u koji osigurava:
1. **Bez preklapanja muzike** — Nikada ne sviraju dve muzičke teme istovremeno
2. **Auto-loop za muziku** — Muzika automatski loop-uje osim ako ima `_END` u imenu
3. **Crossfade tranzicije** — Glatke tranzicije između muzičkih tema

---

## 1. Model Changes

### SlotCompositeEvent (`slot_audio_events.dart`)

Nova polja:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `overlap` | `bool` | `true` | Kada je `false`, zaustavlja sve ostale zvukove na istom bus-u pre puštanja |
| `crossfadeMs` | `int` | `500` | Trajanje crossfade-a u milisekundama |

Novi helper-i:

```dart
/// Check if this event is a music event (targets music bus)
bool get isMusicEvent => targetBusId == SlotBusIds.music;

/// Check if this event should auto-loop (music without _END in name)
bool get shouldAutoLoop {
  if (!isMusicEvent) return false;
  final upperName = name.toUpperCase();
  // If name contains _END, don't loop
  if (upperName.contains('_END')) return false;
  // Music events loop by default
  return true;
}
```

### AudioEvent (`event_registry.dart`)

Nova polja:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `overlap` | `bool` | `true` | Kada je `false`, fade-out sve aktivne voices na istom bus-u |
| `crossfadeMs` | `int` | `0` | Trajanje crossfade-a |
| `targetBusId` | `int` | `0` | Target bus za overlap detekciju |

Novi helper:

```dart
/// Check if this is a music event (targets music bus)
bool get isMusicEvent => targetBusId == 1; // SlotBusIds.music
```

---

## 2. DropTargetWrapper Logic

Kada se audio fajl drop-uje na music bus target:

```dart
// MUSIC DEFAULT RULES:
// 1. overlap = FALSE for music (never overlap, fade out previous)
// 2. looping = TRUE for music UNLESS filename contains _END
// 3. crossfadeMs = 500ms default for smooth transitions

final isMusicBus = busId == SlotBusIds.music;
final isEndFile = _isMusicEndFile(audioPath);  // Checks for _END in filename

// Music defaults
final shouldOverlap = !isMusicBus;           // false for music, true for everything else
final shouldLoop = isMusicBus && !isEndFile; // loop music unless it's an _END file
final crossfadeDuration = isMusicBus ? 500 : 0; // 500ms crossfade for music

final event = SlotCompositeEvent(
  // ... other fields ...
  looping: shouldLoop,
  maxInstances: isMusicBus ? 1 : 4, // Music: only 1 instance, SFX: allow 4
  overlap: shouldOverlap,
  crossfadeMs: crossfadeDuration,
);
```

### `_isMusicEndFile()` Helper

```dart
/// Check if file name indicates a non-looping music (contains _END)
bool _isMusicEndFile(String audioPath) {
  final fileName = audioPath.split('/').last.toUpperCase();
  return fileName.contains('_END');
}
```

**Primeri:**
- `base_game_music.wav` → `looping: true`
- `freespin_music_END.wav` → `looping: false`
- `bigwin_music_end.mp3` → `looping: false`
- `bonus_loop.wav` → `looping: true`

---

## 3. EventRegistry Non-Overlap System

### Voice Tracking

```dart
/// Active voices per bus for non-overlapping events
/// Maps busId -> list of (voiceId, eventId, crossfadeMs)
final Map<int, List<({int voiceId, String eventId, int crossfadeMs})>> _activeBusVoices = {};
```

### Fade-Out Logic

Kada se trigeruje event sa `overlap=false`:

```dart
if (!event.overlap) {
  // Fade out all active voices on the same bus
  final busId = event.targetBusId;
  crossfadeInMs = _fadeOutBusVoices(busId, overrideFadeMs: event.crossfadeMs);

  if (crossfadeInMs > 0) {
    // Add fade-in to context for _playLayer
    context['crossfade_in_ms'] = crossfadeInMs;
  }
}
```

### `_fadeOutBusVoices()` Method

```dart
/// Fade out all active voices on a specific bus
/// Returns the crossfade duration to use for fade-in
int _fadeOutBusVoices(int busId, {int? overrideFadeMs}) {
  final activeVoices = _activeBusVoices[busId];
  if (activeVoices == null || activeVoices.isEmpty) return 0;

  int maxFadeMs = overrideFadeMs ?? 0;
  for (final voice in activeVoices) {
    final fadeMs = overrideFadeMs ?? voice.crossfadeMs;
    AudioPlaybackService.instance.fadeOutVoice(voice.voiceId, fadeMs: fadeMs);
  }

  _activeBusVoices[busId] = [];  // Clear tracking
  return maxFadeMs;
}
```

### Voice Tracking After Play

```dart
// Track for non-overlapping bus playback
if (!event.overlap) {
  Timer(const Duration(milliseconds: 50), () {
    for (final voiceId in voiceIds) {
      _trackBusVoice(event.targetBusId, voiceId, event.id, event.crossfadeMs);
    }
  });
}
```

---

## 4. Sync Flow

```
DropTargetWrapper._handleDrop()
    → Creates SlotCompositeEvent with overlap/crossfadeMs/looping
        → MiddlewareProvider.addCompositeEvent(event)
            → slot_lab_screen._onMiddlewareChanged()
                → _syncEventToRegistry(event)
                    → AudioEvent with overlap/crossfadeMs/targetBusId
                        → EventRegistry.registerEvent()

triggerStage('MUSIC_BASE')
    → _tryPlayEvent()
        → if (!event.overlap) _fadeOutBusVoices(busId)
            → Fade out all active music voices
        → _playLayer() with crossfade_in_ms context
            → Fade-in new music
        → _trackBusVoice() for future crossfade
```

---

## 5. API Reference

### EventRegistry Public Methods

```dart
/// Stop all music voices (e.g., when feature ends)
void stopAllMusicVoices({int fadeMs = 500});

/// Clear all bus voice tracking (call on stop/reset)
void clearBusVoiceTracking();
```

### SlotBusIds Constants

```dart
static const int master = 0;
static const int music = 1;
static const int sfx = 2;
static const int voice = 3;
static const int ui = 4;
static const int reels = 5;
static const int wins = 6;
```

---

## 6. Usage Examples

### Primer 1: Base Game → Free Spins Music Transition

1. Player triggers Free Spins
2. `FS_TRIGGER` stage fires
3. `FS_MUSIC` event (overlap=false, crossfadeMs=500) plays
4. Base game music fades out (500ms)
5. FS music fades in (500ms)
6. Only FS music is playing

### Primer 2: Free Spins → Base Game Return

1. Free Spins feature ends
2. `FS_EXIT` stage fires
3. `BASE_MUSIC` event (overlap=false, crossfadeMs=500) plays
4. FS music fades out (500ms)
5. Base game music fades in (500ms)

### Primer 3: Big Win Music End

1. Big Win starts: `BIGWIN_MUSIC` (overlap=false, looping=true)
2. Base music fades out, Big Win music loops
3. Big Win ends: `BIGWIN_MUSIC_END` (overlap=false, looping=false)
4. Big Win music plays _END file once (no loop)
5. Then: `BASE_MUSIC` plays with crossfade

---

## 7. Files Changed

| File | Changes |
|------|---------|
| `flutter_ui/lib/models/slot_audio_events.dart` | Added `overlap`, `crossfadeMs` fields + helpers |
| `flutter_ui/lib/widgets/slot_lab/auto_event_builder/drop_target_wrapper.dart` | Music-aware defaults in `_handleDrop()` |
| `flutter_ui/lib/services/event_registry.dart` | Added `overlap`, `crossfadeMs`, `targetBusId` to AudioEvent, bus voice tracking |
| `flutter_ui/lib/screens/slot_lab_screen.dart` | Pass new fields in `_syncEventToRegistry()` |

---

## 8. Backward Compatibility

- Default `overlap=true` maintains existing behavior for non-music events
- Default `crossfadeMs=0` means no crossfade for events that don't specify it
- Legacy stage-group crossfade system (P1.10/P1.13) still works alongside new per-event system

---

*Specification created: 2026-01-31*
*Implementation completed: 2026-01-31*
