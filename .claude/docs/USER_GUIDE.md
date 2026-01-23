# FluxForge Studio — User Guide

**Version:** 0.2.0 (Alpha)
**Platform:** macOS, Windows, Linux
**Date:** 2026-01-23

---

## Table of Contents

1. [Introduction](#introduction)
2. [Getting Started](#getting-started)
3. [DAW Section](#daw-section)
4. [Slot Lab](#slot-lab)
5. [Middleware](#middleware)
6. [Audio Routing](#audio-routing)
7. [Keyboard Shortcuts](#keyboard-shortcuts)
8. [Interactive Tutorials](#interactive-tutorials-m4)
9. [Troubleshooting](#troubleshooting)

---

## 1. Introduction

FluxForge Studio is a professional audio middleware and authoring tool designed for:

- **Slot Game Audio Design** — Create, preview, and export audio for slot machines
- **Dynamic Music Systems** — Build adaptive layer engines with context-aware transitions
- **DAW Workflows** — Full multi-track timeline with mixing, automation, and effects
- **Wwise/FMOD-Style Middleware** — State groups, RTPC, ducking, containers

### Key Features

| Feature | Description |
|---------|-------------|
| **Slot Lab** | Synthetic slot engine for testing audio against simulated game events |
| **Adaptive Layer Engine** | Data-driven music system with 18+ signals, 7 stability mechanisms |
| **Event Registry** | 490+ slot stage definitions with automatic bus routing |
| **FabFilter-Style DSP** | Premium compressor, limiter, gate, reverb panels |
| **Containers** | Blend, Random, Sequence containers for dynamic audio |
| **SIMD DSP** | AVX-512/AVX2/SSE4.2/NEON optimized processing |

---

## 2. Getting Started

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | macOS 11+, Windows 10+, Ubuntu 22.04+ | macOS 13+, Windows 11 |
| RAM | 8 GB | 16 GB |
| CPU | x86_64 or ARM64 | Apple Silicon M1+ or Intel i7+ |
| Storage | 2 GB | SSD with 10 GB free |

### First Launch

1. **Create Project** — File → New Project
2. **Choose Section** — Select DAW, Slot Lab, or Middleware from the mode selector
3. **Import Audio** — Drag audio files into the browser or use File → Import

### Project Structure

```
MyProject.ffxproj/
├── project.json        # Project metadata
├── audio/              # Imported audio files
├── events/             # Event definitions
├── presets/            # DSP presets
└── exports/            # Rendered exports
```

---

## 3. DAW Section

The DAW provides a full multi-track timeline for audio editing and mixing.

### Timeline View

| Element | Description |
|---------|-------------|
| **Tracks** | Vertical lanes for audio clips |
| **Clips** | Audio regions on tracks |
| **Regions** | Selected areas for looping/bouncing |
| **Automation** | Volume, pan, and parameter automation |

### Clip Operations

| Action | Shortcut | Description |
|--------|----------|-------------|
| Move | Drag | Move clip on timeline |
| Trim | Drag edges | Adjust start/end |
| Split | S | Split at playhead |
| Delete | Backspace | Remove clip |
| Duplicate | Cmd+D | Copy clip |

### Mixing

- **6 Buses** — SFX, Music, Voice, Ambience, Aux, Master
- **Track Routing** — Route any track to any bus
- **Bus Inserts** — Apply effects per bus
- **Sidechain** — Route any bus as sidechain source

### Lower Zone

Press number keys to switch tabs:

| Key | Tab | Description |
|-----|-----|-------------|
| 1 | Mixer | Full mixing console |
| 2 | Edit | Clip editor |
| 3 | Browser | Audio file browser |
| 4 | Inspector | Track/clip properties |
| 5 | Compressor | FabFilter Pro-C style |
| 6 | Limiter | FabFilter Pro-L style |
| 7 | Gate | FabFilter Pro-G style |
| 8 | Reverb | FabFilter Pro-R style |

---

## 4. Slot Lab

Slot Lab is a synthetic slot machine for testing audio against simulated game events.

### Main View

| Element | Description |
|---------|-------------|
| **Slot Preview** | 5-reel visual representation |
| **Stage Trace** | Timeline of game events |
| **Event Log** | Real-time audio event log |
| **Forced Outcomes** | Test specific scenarios |

### Forced Outcomes

Use number keys for quick testing:

| Key | Outcome | Description |
|-----|---------|-------------|
| 1 | Lose | No win |
| 2 | Small Win | 1-5x bet |
| 3 | Big Win | 10-25x bet |
| 4 | Mega Win | 25-50x bet |
| 5 | Epic Win | 50-100x bet |
| 6 | Free Spins | Feature trigger |
| 7 | Jackpot Grand | Top jackpot |
| 8 | Near Miss | Almost winner |
| 9 | Cascade | Cascading wins |
| 0 | Ultra Win | 100x+ bet |

### Stage Events

Stages represent game phases:

| Stage | Description |
|-------|-------------|
| `SPIN_START` | Spin button pressed |
| `REEL_SPIN` | Reels spinning |
| `REEL_STOP_0..4` | Individual reel stops |
| `ANTICIPATION_ON` | Near-win buildup |
| `WIN_PRESENT` | Win announcement |
| `BIGWIN_TIER` | Big win celebration |

### Event Creation

1. Click **Events Folder** in lower zone
2. Click **+ New Event**
3. Assign stage trigger (e.g., `SPIN_START`)
4. Add audio layers
5. Configure delay, volume, pan per layer

---

## 5. Middleware

Middleware provides Wwise/FMOD-style audio systems.

### State Groups

Global game states that affect audio:

```
GameState: [MainMenu, BaseGame, FreeSpins, BonusRound]
WinTier: [NoWin, SmallWin, BigWin, MegaWin, EpicWin]
PlayerMood: [Neutral, Excited, Frustrated]
```

### Switch Groups

Per-object sound variations:

```
ReelType: [Fruit, Gem, Egyptian, Fantasy]
MusicStyle: [Upbeat, Tension, Celebration]
```

### RTPC (Real-Time Parameter Control)

Continuous parameters that modulate audio:

| RTPC | Range | Usage |
|------|-------|-------|
| `WinAmount` | 0-1000 | Scale celebration intensity |
| `Momentum` | 0-100 | Affect music energy |
| `Balance` | -1..+1 | Player's profit trend |

### Containers

| Type | Description |
|------|-------------|
| **Blend** | RTPC-based crossfade between sounds |
| **Random** | Weighted random selection |
| **Sequence** | Timed sound sequences |

### Ducking

Automatic volume ducking when sources play:

- Voice → Music: -12dB, 100ms attack, 500ms release
- Big Win → All: -6dB, 50ms attack, 300ms release

---

## 6. Audio Routing

### Bus Architecture

```
Tracks → Track Routing → Buses → Master
                           ↓
                    Bus Inserts
                           ↓
                    Master Insert
                           ↓
                       Output
```

### Bus IDs

| ID | Name | Usage |
|----|------|-------|
| 0 | SFX | Sound effects |
| 1 | Music | Background music |
| 2 | Voice | Voiceovers |
| 3 | Ambience | Environmental sounds |
| 4 | Aux | Auxiliary/return |
| 5 | Master | Final output |

### Sidechain

Configure sidechain sources in the compressor/gate panels.

---

## 7. Keyboard Shortcuts

### Global

| Shortcut | Action |
|----------|--------|
| Space | Play/Pause |
| Enter | Stop and return to start |
| Cmd+S | Save project |
| Cmd+Z | Undo |
| Cmd+Shift+Z | Redo |
| Cmd+Q | Quit |

### Timeline

| Shortcut | Action |
|----------|--------|
| ←/→ | Move playhead |
| Home | Go to start |
| End | Go to end |
| [ / ] | Set loop start/end |
| L | Toggle loop |

### Slot Lab

| Shortcut | Action |
|----------|--------|
| Space | Spin |
| 1-0 | Forced outcomes |
| R | Reset |

---

## 8. Interactive Tutorials (M4)

FluxForge Studio includes built-in interactive tutorials to help you learn the software.

### Launching Tutorials

1. Go to **Help → Tutorials**
2. Select a tutorial from the list
3. Follow the spotlight-guided steps

### Available Tutorials

| Tutorial | Duration | Difficulty | Description |
|----------|----------|------------|-------------|
| **Creating Your First Event** | ~5 min | Beginner | Learn basics of audio events, layers, and stage triggers |
| **Setting Up RTPC** | ~7 min | Intermediate | Configure real-time parameter control for dynamic audio |

### Tutorial Features

- **Spotlight Highlighting** — Visual focus on target UI elements
- **Step Navigation** — Next/Previous/Skip controls
- **Progress Tracking** — Visual progress indicator
- **Category Organization** — Tutorials grouped by topic (Events, RTPC, Mixing, etc.)

### Creating Custom Tutorials

Tutorials are defined in `flutter_ui/lib/data/tutorials/`:

```dart
class MyTutorial {
  static Tutorial get tutorial => Tutorial(
    id: 'my_tutorial',
    name: 'My Custom Tutorial',
    description: 'Learn something new.',
    estimatedMinutes: 5,
    category: TutorialCategory.basics,
    difficulty: TutorialDifficulty.beginner,
    steps: [
      TutorialStep(
        id: 'step1',
        title: 'Welcome',
        content: 'This tutorial will guide you through...',
        icon: Icons.info,
        tooltipPosition: TutorialTooltipPosition.center,
        actions: [TutorialAction.skip, TutorialAction.next],
      ),
      // More steps...
    ],
  );
}
```

---

## 9. Troubleshooting

### Audio Not Playing

1. Check output device in Settings → Audio
2. Verify bus routing (track must route to a bus)
3. Check mute/solo states
4. Ensure FFI library is loaded (debug overlay shows "Lib: LOADED")

### FFI Not Loaded

Run full build:

```bash
cargo build --release
cp target/release/*.dylib flutter_ui/macos/Frameworks/
# Then rebuild via Xcode
```

### High CPU Usage

1. Reduce buffer size in Settings → Audio
2. Disable unused tracks
3. Freeze tracks with heavy processing

### Waveforms Not Showing

1. Wait for waveform cache build (progress shown in clip)
2. Check cache directory permissions
3. Clear cache: Settings → Cache → Clear Waveforms

---

## Support

- **GitHub Issues:** https://github.com/fluxforge/studio/issues
- **Documentation:** .claude/docs/ folder
- **Architecture:** .claude/architecture/ folder

---

*Generated by Claude Code — FluxForge Studio User Guide*
