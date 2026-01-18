# CRI ADX2 (CRIWARE) — Complete Technical Analysis

> **Analysis Date:** January 2026
> **Version:** CRI ADX / ADX2
> **Developer:** CRI Middleware Co., Ltd. (Japan)
> **Analyst Role:** Chief Audio Architect / Lead DSP Engineer / Engine Architect

---

## Executive Summary

CRI ADX2 is Japan's leading audio middleware, used in over 5,500 games across all major platforms. Part of the CRIWARE SDK (which also includes Sofdec2 video middleware), ADX2 is renowned for its highly efficient proprietary codecs (ADX, HCA, HCA-MX) that deliver exceptional performance on mobile and embedded systems. The system combines AtomCraft (DAW-like authoring tool) with a flexible runtime API, featuring comprehensive DSP effects, voice management, 3D audio, and tight integration with CRI's video technology.

**Key Characteristics:**
- **#1 in Japan** — 5,500+ games, industry standard in Japanese development
- **Proprietary codecs** — ADX, HCA, HCA-MX with exceptional efficiency
- **Mobile optimization** — HCA-MX enables tens of voices on mobile
- **AtomCraft** — DAW-like authoring with gentle learning curve
- **CRIWARE integration** — Synergy with Sofdec2 video middleware
- **Cross-platform** — PC, consoles, mobile, embedded systems

---

## Table of Contents

1. [Overview & History](#1-overview--history)
2. [Architecture](#2-architecture)
3. [AtomCraft Authoring](#3-atomcraft-authoring)
4. [Cue System](#4-cue-system)
5. [Codec Technology](#5-codec-technology)
6. [Voice Management](#6-voice-management)
7. [DSP Effects](#7-dsp-effects)
8. [Mixer & Buses](#8-mixer--buses)
9. [3D Audio](#9-3d-audio)
10. [AISAC System](#10-aisac-system)
11. [Streaming & Memory](#11-streaming--memory)
12. [Engine Integration](#12-engine-integration)
13. [Profiler & Debugging](#13-profiler--debugging)
14. [Platform Support](#14-platform-support)
15. [Comparison with Competitors](#15-comparison-with-competitors)
16. [FluxForge Integration Points](#16-fluxforge-integration-points)

---

## 1. Overview & History

### 1.1 Company Background

```
CRI MIDDLEWARE CO., LTD.

Founded: 1983 (as CSK Research Institute)
Headquarters: Tokyo, Japan
Primary Markets: Japan, Asia, expanding globally

CRIWARE Product Suite:
├── CRI ADX2 (Audio middleware)
├── Sofdec2 (Video middleware)
├── File Magic PRO (File system)
└── Mana (Full-motion video)

Market Position:
- #1 audio middleware in Japan
- 5,500+ games shipped
- Major Japanese publishers (Square Enix, Capcom, Bandai Namco, etc.)
```

### 1.2 Development Timeline

```
CRI ADX HISTORY:

1990s — Original ADX format developed
        - ADPCM-based lossy codec
        - Designed for Sega Saturn/Dreamcast

2000s — ADX becomes standard in Japanese games
        - PlayStation 2 era dominance
        - Streaming audio for RPGs

2010s — ADX2 released
        - HCA codec introduced
        - AtomCraft authoring tool
        - Mobile platform focus

2015 — HCA-MX codec
       - Ultra-efficient mobile decoding
       - Decode-after-mix architecture

2018+ — Global expansion
       - Unity/Unreal plugins
       - CryEngine support
       - Western market push
```

### 1.3 Notable Licensees

```
MAJOR CUSTOMERS:

Japanese Publishers:
- Square Enix (Final Fantasy series)
- Capcom (Resident Evil, Monster Hunter)
- Bandai Namco (Tales series, Tekken)
- Konami (Metal Gear, PES)
- Sega (Sonic, Yakuza)
- Koei Tecmo (Dynasty Warriors)

International:
- Various mobile game developers
- Unity developers via plugin
- Unreal developers via plugin
```

---

## 2. Architecture

### 2.1 System Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                    AUTHORING LAYER                               │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                     AtomCraft                                ││
│  │  ┌───────────────┐  ┌───────────────┐  ┌─────────────────┐ ││
│  │  │  Timeline     │  │    Mixer      │  │   AISAC         │ ││
│  │  │  Editing      │  │    View       │  │   Editor        │ ││
│  │  └───────┬───────┘  └───────┬───────┘  └────────┬────────┘ ││
│  │          │                  │                   │           ││
│  │          └──────────────────┼───────────────────┘           ││
│  │                             ▼                               ││
│  │  ┌─────────────────────────────────────────────────────────┐││
│  │  │                    Build System                         │││
│  │  │  ACF (Global) + ACB (Cue Sheet) + AWB (Streaming)      │││
│  │  └─────────────────────────────────────────────────────────┘││
│  └─────────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│                    RUNTIME LAYER                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                   CRI Atom Runtime                           ││
│  │  ┌───────────────┐  ┌───────────────┐  ┌─────────────────┐ ││
│  │  │ Cue Playback  │  │ Voice Manager │  │   DSP Chain     │ ││
│  │  │ (Player/Ex)   │  │ (Pool/Limit)  │  │   (Bus FX)      │ ││
│  │  └───────┬───────┘  └───────┬───────┘  └────────┬────────┘ ││
│  │          │                  │                   │           ││
│  │          └──────────────────┼───────────────────┘           ││
│  │                             ▼                               ││
│  │  ┌─────────────────────────────────────────────────────────┐││
│  │  │                   Decoder/Mixer                         │││
│  │  │  ┌───────────┐  ┌───────────┐  ┌─────────────────────┐│││
│  │  │  │ HCA/ADX   │→│  Mixer    │→│    Output           ││││
│  │  │  │ Decoder   │  │ (MX opt)  │  │    (Platform)      ││││
│  │  │  └───────────┘  └───────────┘  └─────────────────────┘│││
│  │  └─────────────────────────────────────────────────────────┘││
│  └─────────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│                    CODEC LAYER                                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │     ADX     │  │     HCA     │  │        HCA-MX           │ │
│  │  (4:1 ADPCM)│  │ (6-12:1)    │  │   (Decode-after-mix)    │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                    PLATFORM AUDIO                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │   Console   │  │   Mobile    │  │        PC/Web           │ │
│  │  (Native)   │  │  (iOS/And)  │  │   (Platform API)        │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Core Concepts

| Concept | Description |
|---------|-------------|
| **Cue** | Playable audio event (like FMOD Event) |
| **Cue Sheet** | Collection of Cues (like Sound Bank) |
| **Track** | Timeline layer within a Cue |
| **Waveform** | Audio data reference |
| **AISAC** | Interactive parameter system |
| **Category** | Grouping for volume/limiting |
| **Bus** | Mixing channel with effects |
| **Voice** | Raw audio playback unit |

### 2.3 File Structure

```
CRIWARE FILE TYPES:

ACF (Atom Configuration File):
- Global project settings
- AISAC definitions
- Category definitions
- Bus configurations
- One per project

ACB (Atom Cue sheet Binary):
- Cue definitions
- Track/waveform references
- In-memory audio data
- One per Cue Sheet

AWB (Atom Wave Bank):
- Streaming audio data
- Referenced by ACB
- Optional (for streaming Cue Sheets)

Header Files:
- C/C++ definitions
- Cue names/IDs
- AISAC control IDs
```

---

## 3. AtomCraft Authoring

### 3.1 Interface Overview

```
ATOMCRAFT INTERFACE:

┌─────────────────────────────────────────────────────────────────┐
│  Menu Bar | Toolbar                                              │
├─────────────┬───────────────────────────────────────────────────┤
│  Project   │                Timeline View                        │
│  Tree      │  ┌─────────────────────────────────────────────┐   │
│            │  │ Track 1: [▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░]   │   │
│  ▼ Project │  │ Track 2: [░░░░▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░]   │   │
│  ├─ Work   │  │ Track 3: [░░░░░░░░░░▓▓▓▓▓▓▓░░░░░░░░░░░░░]   │   │
│  │ Units   │  │          |─────|─────|─────|─────|─────|    │   │
│  ├─ Cue    │  │          0     1     2     3     4     5    │   │
│  │ Sheets  │  └─────────────────────────────────────────────┘   │
│  ├─ Global │                                                     │
│  │ Settings│  ┌─────────────────────────────────────────────┐   │
│  └─ Output │  │              Mixer View                      │   │
│            │  │  [Master]←[SFX]←[Voice]←[Music]←[Ambience]  │   │
│            │  │  Vol: 0dB  -3dB   -6dB    -9dB     -12dB    │   │
├────────────┴──┴─────────────────────────────────────────────────┤
│                        Inspector Panel                           │
│  Cue Properties | Track Settings | Waveform Info | AISAC       │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Timeline Workflow

```
TIMELINE EDITING:

AtomCraft uses a DAW-like timeline workflow:

1. Create Cue in Cue Sheet
2. Add Tracks to Cue
3. Place Waveforms on Timeline
4. Configure:
   - Start time
   - Loop points
   - Fade in/out
   - Volume envelope
   - Pitch/pan curves
5. Add Actions:
   - Play next track
   - Jump to marker
   - Trigger AISAC

Advantages:
- Familiar to audio designers
- Visual representation of complex events
- Easy timing adjustments
- Preview in tool
```

### 3.3 Project Organization

```
ATOMCRAFT PROJECT STRUCTURE:

Project
├── Work Units (folders for organization)
│   ├── Characters
│   │   ├── Player
│   │   │   ├── Footsteps
│   │   │   ├── Voice
│   │   │   └── Actions
│   │   └── Enemies
│   ├── Environment
│   │   ├── Ambient
│   │   └── Weather
│   └── UI
│       ├── Menus
│       └── Notifications
│
├── Cue Sheets
│   ├── SFX_Player.acb
│   ├── SFX_Enemies.acb
│   ├── Music_BGM.acb (+ .awb)
│   └── VO_Dialog.acb (+ .awb)
│
├── Global Settings
│   ├── AISAC (Global)
│   ├── Categories
│   └── Voice Limit Groups
│
└── Output
    ├── ACF
    ├── ACB files
    └── Header files
```

---

## 4. Cue System

### 4.1 Cue Types

```cpp
// Cue is the basic playable unit

// Simple Cue - single waveform
// Cue: "explosion_01"
// └── Track 1: explosion.wav

// Layered Cue - multiple simultaneous sounds
// Cue: "footstep"
// ├── Track 1: footstep_base.wav
// └── Track 2: footstep_detail.wav

// Sequential Cue - sounds in sequence
// Cue: "dialog_intro"
// └── Track 1: [hello.wav] → [how_are_you.wav]

// Random Cue - random selection
// Cue: "hit_impact"
// └── Track 1: [hit_01.wav OR hit_02.wav OR hit_03.wav]

// Switch Cue - selection based on parameter
// Cue: "weapon_fire"
// └── Track 1: [pistol.wav | rifle.wav | shotgun.wav]
//              (based on AISAC "WeaponType")
```

### 4.2 Cue Properties

```cpp
// Cue configuration in AtomCraft

struct CueProperties {
    // Basic
    const char* name;
    uint32_t id;
    float volume;      // dB
    float pitch;       // Semitones

    // Playback
    int loop_count;    // -1 = infinite
    float pan;         // -1.0 to 1.0

    // Voice behavior
    VoiceBehavior behavior;
    // - Normal: Continue even at volume 0
    // - VoiceStop: Stop when volume reaches 0
    // - VirtualVoice: Store state, resume when audible
    // - VirtualVoiceRetrigger: Restart from beginning

    // 3D Settings
    bool is_3d;
    float min_attenuation_distance;
    float max_attenuation_distance;

    // Priority
    int priority;      // Higher = less likely to be stolen

    // Category
    const char* category;
};
```

### 4.3 Cue Playback API

```cpp
// Runtime cue playback

// Load Cue Sheet
CriAtomExAcbHn acb = criAtomExAcb_LoadAcbFile(
    NULL,                    // Binder (NULL for default)
    "SFX_Player.acb",       // ACB file
    NULL,                    // Work area
    0                        // Work area size
);

// Create player
CriAtomExPlayerHn player = criAtomExPlayer_Create(NULL, NULL, 0);

// Set Cue to play
criAtomExPlayer_SetCueName(player, acb, "footstep");

// Start playback
CriAtomExPlaybackId playback_id = criAtomExPlayer_Start(player);

// Control during playback
criAtomExPlayback_Pause(playback_id, CRI_TRUE);   // Pause
criAtomExPlayback_Resume(playback_id);             // Resume
criAtomExPlayback_Stop(playback_id);               // Stop

// Get status
CriAtomExPlaybackStatus status = criAtomExPlayback_GetStatus(playback_id);
// - CRIATOMEXPLAYBACK_STATUS_PREP
// - CRIATOMEXPLAYBACK_STATUS_PLAYING
// - CRIATOMEXPLAYBACK_STATUS_PLAYEND
// - CRIATOMEXPLAYBACK_STATUS_REMOVED
```

---

## 5. Codec Technology

### 5.1 ADX Codec

```
ADX CODEC SPECIFICATIONS:

Type: ADPCM-based lossy compression
Compression Ratio: ~4:1
CPU Load: Very low
Quality: Good (suitable for SFX)

Features:
- Seamless looping
- Multi-stream capability
- Low memory footprint
- Fast decode

Best For:
- Sound effects
- Short sounds
- High polyphony requirements
- Legacy compatibility

Technical:
- 4-bit ADPCM samples
- Prediction coefficients
- Loop point encoding
- Header with metadata
```

### 5.2 HCA Codec

```
HCA (HIGH COMPRESSION AUDIO) SPECIFICATIONS:

Type: Transform-based lossy compression
Compression Ratio: 6:1 to 12:1
CPU Load: Low and stable
Quality: High (comparable to AAC/MP3)

Features:
- High fidelity at low bitrates
- Stable CPU cost (no decode spikes)
- All platforms supported
- Seamless looping

Best For:
- Music
- Voice/dialogue
- Long ambient sounds
- Quality-critical audio

Bitrate Guidelines:
- Speech: 48-64 kbps
- Music: 128-192 kbps
- High quality: 256+ kbps
```

### 5.3 HCA-MX Codec

```
HCA-MX (DECODE-AFTER-MIX) SPECIFICATIONS:

Type: HCA variant with post-mix decoding
Compression Ratio: Similar to HCA
CPU Load: Extremely low per voice
Quality: High

Revolutionary Feature:
"Decoding is done AFTER mixing"
- Play 16 voices for cost of decoding ~1-2
- Ideal for mobile games
- Massive polyphony improvement

Performance Example:
"Mono, 48kHz, HCA-MX compression:
16 simultaneous playbacks = ~9% CPU on iPhone 4S"

Best For:
- Mobile games
- High voice count scenarios
- CPU-constrained platforms
- Embedded systems

Limitation:
- All voices must use same sample rate
- Best for uniform audio content
```

### 5.4 Codec Comparison

```
CODEC COMPARISON TABLE:

| Codec  | Ratio | CPU    | Quality | Use Case               |
|--------|-------|--------|---------|------------------------|
| ADX    | 4:1   | Lowest | Good    | SFX, loops             |
| HCA    | 6-12:1| Low    | High    | Music, voice           |
| HCA-MX | 6-12:1| Ultra  | High    | Mobile high-polyphony  |
| PCM    | 1:1   | None   | Perfect | Critical timing        |

Platform Codecs (also supported):
- ATRAC9 (PlayStation)
- XMA (Xbox)
- DSP-ADPCM (Nintendo)
```

---

## 6. Voice Management

### 6.1 Voice Pool

```cpp
// Voice management in ADX2

// Configure voice pool
CriAtomExConfig config;
criAtomEx_SetDefaultConfig(&config);

config.max_virtual_voices = 32;      // Concurrent voices
config.max_voice_limit_groups = 16;  // Limit groups

criAtomEx_Initialize(&config, NULL, 0);

// Voice represents raw waveform playback
// Each active waveform = 1 voice
// Voice count affects CPU and memory
```

### 6.2 Voice Limit Groups

```cpp
// Voice limiting at various levels

// 1. Create Voice Limit Group in AtomCraft
// Project Tree → New Object → Create Voice Limit Group

// Voice Limit Group Properties:
struct VoiceLimitGroup {
    const char* name;
    int max_voices;           // Maximum concurrent voices
    VoicePriority priority;   // For stealing

    // Stealing behavior
    StealBehavior behavior;
    // - StopOldest: Stop oldest voice
    // - StopLowestPriority: Stop lowest priority
    // - PreventNew: Don't allow new playback
};

// 2. Assign Cues to Voice Limit Group
// In Inspector: Cue → Voice Limit Group

// Example groups:
// - "Footsteps" max 4 voices
// - "Gunshots" max 8 voices
// - "Ambience" max 2 voices
// - "Music" max 2 voices
```

### 6.3 Voice Behavior

```cpp
// Voice behavior when volume reaches 0

enum VoiceBehavior {
    // Normal - voice continues playing even at 0 volume
    // (wastes CPU but maintains sync)
    VOICE_BEHAVIOR_NORMAL,

    // Voice Stop - immediately stop when volume = 0
    // (saves CPU, loses sync)
    VOICE_BEHAVIOR_STOP,

    // Virtual Voice - pause and store state
    // Resume from same position when audible
    VOICE_BEHAVIOR_VIRTUAL,

    // Virtual Voice Retrigger - pause state
    // Restart from beginning when audible
    VOICE_BEHAVIOR_VIRTUAL_RETRIGGER
};

// Set per-Cue in AtomCraft Inspector
// Useful for 3D sounds that move in/out of range
```

---

## 7. DSP Effects

### 7.1 Built-in Effects

```
ATOMCRAFT DSP EFFECTS:

Filters:
├── High-Shelf Filter
├── Low-Shelf Filter
├── Peaking Filter (Parametric EQ)
├── Band-Pass Filter
└── Notch Filter

Dynamics:
├── Compressor
├── Limiter
└── Sidechain Compressor

EQ:
├── 3-Band EQ
└── 32-Band Graphic EQ

Modulation:
├── Chorus
├── Flanger
└── Phaser

Time-Based:
├── Delay
├── Multi-tap Delay
├── Echo
└── IR Reverb (Convolution)

Spatial:
├── Surrounder (upmix)
└── Matrix (channel routing)

Distortion:
└── Distortion / Overdrive

Pitch:
└── Pitch Shifter
```

### 7.2 Effect Application

```cpp
// Effects are applied at bus level

// In AtomCraft Mixer View:
// 1. Select bus
// 2. Click + in Effects section
// 3. Choose effect
// 4. Configure parameters in Inspector

// Effect routing strategy:
// Instead of:
//   Ambience Bus → Reverb
//   Voice Bus → Reverb
//   SFX Bus → Reverb

// Better:
//   Reverb Bus (with reverb effect)
//   ├── Send from Ambience Bus
//   ├── Send from Voice Bus
//   └── Send from SFX Bus
```

### 7.3 McDSP Effects (Add-on)

```
McDSP PROFESSIONAL EFFECTS:

Available as separate purchase:
- McDSP Compressor
- McDSP EQ
- McDSP Limiter
- McDSP Reverb

Benefits:
- Professional quality
- Industry-standard algorithms
- Advanced parameters
```

### 7.4 Custom Effect SDK

```cpp
// CRI ADX Audio Effect Plugin SDK

// Developers can create custom DSP effects

typedef struct CriAtomDspPlugin {
    // Initialize
    void* (*create)(int sample_rate, int channels);

    // Process audio
    void (*process)(
        void* instance,
        float** input,
        float** output,
        int frames
    );

    // Destroy
    void (*destroy)(void* instance);

    // Parameter access
    int (*get_param_count)(void* instance);
    void (*set_param)(void* instance, int id, float value);
    float (*get_param)(void* instance, int id);
} CriAtomDspPlugin;
```

---

## 8. Mixer & Buses

### 8.1 Bus Architecture

```
MIXER ARCHITECTURE:

┌─────────────────────────────────────────────────────────────────┐
│                         Master Bus                               │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Vol: 0dB | Effects: [Limiter]                               ││
│  └──────────────────────────▲──────────────────────────────────┘│
│                             │                                    │
│  ┌──────────────────────────┼──────────────────────────────────┐│
│  │          │               │              │                   ││
│  │ ┌────────┴────┐ ┌────────┴────┐ ┌───────┴─────┐ ┌─────────┐││
│  │ │    SFX     │ │   Music    │ │   Voice    │ │ Reverb  │││
│  │ │  Vol: -3dB │ │ Vol: -6dB  │ │  Vol: 0dB  │ │ (FX Bus)│││
│  │ │ [Comp]     │ │            │ │ [HPF]      │ │ [IR Rev]│││
│  │ └──────┬─────┘ └────────────┘ └──────┬─────┘ └────▲────┘││
│  │        │                             │            │      ││
│  │        │ Send ────────────────────────────────────┘      ││
│  │        │                             │                    ││
│  │ ┌──────┴─────┐              ┌────────┴────┐              ││
│  │ │  Weapons   │              │   Dialog    │              ││
│  │ │ Vol: -3dB  │              │  Vol: 0dB   │              ││
│  │ └────────────┘              └─────────────┘              ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 Bus Configuration

```cpp
// Bus properties in AtomCraft

struct BusConfig {
    const char* name;

    // Volume
    float volume_db;

    // Routing
    const char* output_bus;    // Parent bus

    // Sends
    struct {
        const char* target_bus;
        float send_level;
    } sends[MAX_SENDS];

    // Effects
    struct {
        const char* effect_type;
        // Effect-specific params
    } effects[MAX_EFFECTS];

    // Pan/Width
    float pan;
    float width;
};
```

### 8.3 Snapshots

```cpp
// Mixer snapshots for state changes

// Snapshots store:
// - Bus volumes
// - Send levels
// - Effect parameters

// Create snapshots in AtomCraft:
// Global Settings → Snapshots → New Snapshot

// Transition to snapshot at runtime:
criAtomExCategory_SetAisacControlById(
    CATEGORY_ID_MASTER,
    AISAC_CONTROL_SNAPSHOT,
    snapshot_value
);

// Common snapshot uses:
// - "Normal" → "Paused" (duck music/SFX)
// - "Gameplay" → "Cutscene" (emphasize dialogue)
// - "Outdoor" → "Indoor" (change reverb)
```

### 8.4 Categories

```cpp
// Categories group Cues for volume/limiting

// Category properties:
struct Category {
    const char* name;
    float volume_db;           // Category volume
    int cue_limit;             // Max concurrent cues
    bool exclusive;            // Only one cue at a time
};

// Categories in AtomCraft:
// - SFX (volume: 0dB, limit: 32)
// - Music (volume: -6dB, limit: 2, exclusive)
// - Voice (volume: 0dB, limit: 8)
// - UI (volume: -3dB, limit: 4)

// Runtime category control:
criAtomExCategory_SetVolumeById(CATEGORY_ID_MUSIC, 0.5f);
criAtomExCategory_MuteById(CATEGORY_ID_SFX, CRI_TRUE);
```

---

## 9. 3D Audio

### 9.1 3D Positioning

```cpp
// 3D audio in ADX2

// Set listener position
CriAtomEx3dListenerHn listener = criAtomEx3dListener_Create(NULL, NULL, 0);

CriAtomExVector position = { 0.0f, 0.0f, 0.0f };
CriAtomExVector front = { 0.0f, 0.0f, 1.0f };
CriAtomExVector up = { 0.0f, 1.0f, 0.0f };

criAtomEx3dListener_SetPosition(listener, &position);
criAtomEx3dListener_SetOrientation(listener, &front, &up);
criAtomEx3dListener_Update(listener);

// Set source position
CriAtomEx3dSourceHn source = criAtomEx3dSource_Create(NULL, NULL, 0);

CriAtomExVector source_pos = { 10.0f, 0.0f, 5.0f };
criAtomEx3dSource_SetPosition(source, &source_pos);
criAtomEx3dSource_Update(source);

// Attach source to player
criAtomExPlayer_Set3dSourceHn(player, source);
criAtomExPlayer_Set3dListenerHn(player, listener);
```

### 9.2 Distance Attenuation

```cpp
// Distance attenuation configuration

// In AtomCraft:
// - Min Attenuation Distance: Full volume within this range
// - Max Attenuation Distance: Silent beyond this range

// Attenuation curve options:
// - Linear
// - Logarithmic (realistic)
// - Inverse
// - Custom curve (via AISAC)

// Using Global AISAC for distance:
// Global Settings → GlobalAISACs → Distance Attenuation AISAC
// - Input: Distance (auto-calculated)
// - Output: Volume curve
```

### 9.3 Yamaha Sound xR

```
YAMAHA SOUND xR (3D AUDIO):

ADX2 supports Yamaha's Sound xR technology:

Features:
- Virtual 3D audio for headphones
- HRTF-based binaural rendering
- Accurate positioning without surround speakers

Use Cases:
- VR/AR applications
- Mobile games
- Headphone-focused experiences

Integration:
- Enable in project settings
- Automatic processing for 3D cues
- Optimized for various headphone types
```

---

## 10. AISAC System

### 10.1 AISAC Overview

```
AISAC (ADAPTIVE INTERACTIVE SOUND CONTROL):

AISAC is ADX2's parameter system for interactive audio.

Components:
├── AISAC Control (Input)
│   └── Numeric value (0.0 - 1.0)
├── AISAC Graph (Mapping)
│   └── Curve defining input → output
└── Target Parameter (Output)
    └── Volume, Pitch, Pan, Filter, etc.

Example:
Control: "PlayerHealth" (0.0 = dead, 1.0 = full)
Graph: Exponential curve
Target: Music low-pass filter cutoff
Result: Music becomes muffled as health decreases
```

### 10.2 AISAC Types

```cpp
// Local AISAC - per-Cue
// Applied only to specific Cue

// Global AISAC - project-wide
// Applied to all Cues (e.g., distance attenuation)

// Creating AISAC in AtomCraft:
// 1. Select Cue
// 2. Inspector → AISAC
// 3. Add AISAC Control
// 4. Define curve
// 5. Set target parameter

// AISAC targets:
enum AISACTarget {
    AISAC_TARGET_VOLUME,
    AISAC_TARGET_PITCH,
    AISAC_TARGET_PAN,
    AISAC_TARGET_PAN_SPREAD,
    AISAC_TARGET_FILTER_CUTOFF,
    AISAC_TARGET_FILTER_RESONANCE,
    AISAC_TARGET_BUS_SEND,
    AISAC_TARGET_PRIORITY,
    // ... more
};
```

### 10.3 AISAC at Runtime

```cpp
// Setting AISAC values at runtime

// Get AISAC control ID from header
#define AISAC_CONTROL_HEALTH 0

// Set global AISAC
criAtomExCategory_SetAisacControlById(
    CATEGORY_ALL,
    AISAC_CONTROL_HEALTH,
    0.5f  // 50% health
);

// Set per-player AISAC
criAtomExPlayer_SetAisacControlById(
    player,
    AISAC_CONTROL_SPEED,
    vehicle_speed / max_speed  // Normalized 0-1
);

// AISAC values automatically interpolate
// Smooth transitions without clicks/pops
```

---

## 11. Streaming & Memory

### 11.1 Memory Management

```cpp
// CRI Atom memory configuration

CriAtomExConfig config;
criAtomEx_SetDefaultConfig(&config);

// Voice pool memory
config.max_virtual_voices = 32;

// Streaming buffer
config.max_streams = 8;
config.max_stream_buffer = 32 * 1024;  // 32KB per stream

// In-memory pool
config.standard_voice_pool = 16;

criAtomEx_Initialize(&config, work_buffer, work_buffer_size);

// Memory modes:
// - In-memory: Entire audio loaded (fast, uses memory)
// - Streaming: Read from disk (slow start, low memory)
// - Memory + Streaming: Header in memory, data streamed
```

### 11.2 Streaming

```cpp
// Streaming configuration

// In AtomCraft:
// Material → Streaming settings

// Streaming Types:
// - Zero Latency: Preload first block
// - Normal: Stream from start
// - On-demand: Load only when needed

// For seamless loops:
// Enable "Seamless" in streaming settings

// AWB file contains streaming data
// ACB file contains cue definitions

// Runtime:
CriAtomExAcbHn acb = criAtomExAcb_LoadAcbFile(
    NULL,
    "Music.acb",    // Cue definitions
    "Music.awb",    // Streaming data
    NULL, 0
);
```

### 11.3 Memory Optimization

```cpp
// Memory optimization strategies

// 1. Use appropriate codec
// - HCA-MX for mobile (decode after mix)
// - HCA for quality-critical
// - ADX for high polyphony SFX

// 2. Stream large files
// - Music: Always stream
// - Dialogue: Stream if > 2 seconds
// - SFX: In-memory if < 1 second

// 3. Unload unused data
criAtomExAcb_Release(acb);  // Release cue sheet

// 4. Use voice limits
// - Prevent runaway voice counts
// - Category limits for groups

// 5. Monitor with profiler
// - Track memory usage
// - Identify peaks
```

---

## 12. Engine Integration

### 12.1 Unity Integration

```csharp
// CRI ADX2 Unity Plugin

using CriWare;

public class CriAudioExample : MonoBehaviour
{
    // Atom Source component (like AudioSource)
    public CriAtomSource atomSource;

    void Start()
    {
        // Play cue by name
        atomSource.Play("explosion");

        // Or by cue sheet and name
        atomSource.cueSheet = "SFX";
        atomSource.cueName = "footstep";
        atomSource.Play();
    }

    void Update()
    {
        // Set AISAC parameter
        atomSource.SetAisacControl("Speed", playerSpeed);
    }
}

// 3D Audio
[RequireComponent(typeof(CriAtomSource))]
public class Cri3DSound : MonoBehaviour
{
    private CriAtomSource source;
    private CriAtomEx3dSource source3d;

    void Start()
    {
        source = GetComponent<CriAtomSource>();
        source3d = source.source3D;
    }

    void Update()
    {
        // Position updates automatically from Transform
        // Or manually:
        source3d.SetPosition(transform.position);
        source3d.Update();
    }
}
```

### 12.2 Unreal Integration

```cpp
// CRI ADX2 Unreal Plugin

#include "CriWareRuntime.h"

// Blueprint-accessible component
UCLASS()
class UCriAtomComponent : public USceneComponent
{
    GENERATED_BODY()

public:
    // Play cue
    UFUNCTION(BlueprintCallable)
    void PlayCue(FString CueName);

    // Set AISAC
    UFUNCTION(BlueprintCallable)
    void SetAisacControl(FString ControlName, float Value);

    // 3D Settings
    UPROPERTY(EditAnywhere)
    bool bEnable3D;

    UPROPERTY(EditAnywhere)
    float MinAttenuationDistance;

    UPROPERTY(EditAnywhere)
    float MaxAttenuationDistance;
};
```

### 12.3 CryEngine Integration

```cpp
// CRI ADX2 CryEngine integration

// ADX2 is supported as audio middleware option
// in CryEngine's Audio Translation Layer (ATL)

// Setup:
// 1. Enable ADX2 in Audio Controls Editor
// 2. Console: s_ImplName CryAudioImplAdx2
// 3. Place ACF/ACB files in sounds/adx2/

// ACE shows ADX2-specific controls:
// - Triggers → Cue mapping
// - Parameters → AISAC mapping
// - Environments → Bus routing
```

---

## 13. Profiler & Debugging

### 13.1 Built-in Profiler

```
CRI ATOM PROFILER:

Features:
- Real-time connection to game
- Voice timeline visualization
- Memory usage tracking
- CPU load monitoring
- Bus level meters
- AISAC value display

Views:
├── Timeline: Voice start/stop events
├── Voices: Active voice list
├── Memory: Allocation tracking
├── CPU: Processing load
├── Buses: Level meters
└── AISAC: Parameter values

Connection:
- Network connection to running game
- Works with development builds
- Minimal performance impact
```

### 13.2 Debug Output

```cpp
// CRI debug logging

// Enable debug output
criAtomEx_SetDebugLogOutput(debug_callback);

void debug_callback(const char* message) {
    printf("[CRI] %s\n", message);
}

// Set debug level
criAtomEx_SetDebugLevel(CRIATOM_DEBUG_LEVEL_VERBOSE);

// Debug levels:
// - CRIATOM_DEBUG_LEVEL_OFF
// - CRIATOM_DEBUG_LEVEL_ERROR
// - CRIATOM_DEBUG_LEVEL_WARNING
// - CRIATOM_DEBUG_LEVEL_INFO
// - CRIATOM_DEBUG_LEVEL_VERBOSE
```

### 13.3 Performance Metrics

```cpp
// Runtime performance queries

// Voice count
int voice_count = criAtomExVoicePool_GetNumUsedVoices(voice_pool);

// CPU load (approximate)
float cpu_load = criAtomEx_GetCpuUsage();

// Memory usage
CriAtomExResourceUsage usage;
criAtomEx_GetResourceUsage(&usage);
// usage.work_size
// usage.cue_sheet_num
// usage.voice_pool_num
```

---

## 14. Platform Support

### 14.1 Supported Platforms

```
CRIWARE PLATFORM SUPPORT:

Desktop:
├── Windows (32-bit, 64-bit)
├── macOS
└── Linux

Console:
├── PlayStation 4
├── PlayStation 5
├── Xbox One
├── Xbox Series X|S
└── Nintendo Switch

Mobile:
├── iOS
├── Android
└── WebGL

Legacy:
├── PlayStation 3
├── PlayStation Vita
├── Xbox 360
├── Wii U
├── 3DS
└── PS Vita

Embedded:
└── Various embedded systems
```

### 14.2 Platform-Specific Features

```cpp
// Platform codec selection

// PlayStation
// - ATRAC9 support (native hardware decode)
// - HCA for cross-platform compatibility

// Xbox
// - XMA support (native)
// - HCA for cross-platform

// Nintendo Switch
// - DSP-ADPCM (native)
// - HCA for consistency

// Mobile
// - HCA-MX strongly recommended
// - Massive efficiency gains
```

---

## 15. Comparison with Competitors

### 15.1 ADX2 vs Wwise

| Feature | ADX2 | Wwise |
|---------|------|-------|
| **Learning Curve** | Gentle (DAW-like) | Steep |
| **Codec Efficiency** | Excellent (HCA-MX) | Good |
| **Mobile Focus** | Strong | Moderate |
| **Interactive Music** | Basic | Excellent |
| **Market** | Japan-dominant | Global |
| **Tooling** | AtomCraft | Wwise Authoring |

### 15.2 ADX2 vs FMOD

| Feature | ADX2 | FMOD |
|---------|------|------|
| **Authoring** | Timeline-based | Event-based |
| **Codec** | Proprietary (HCA) | Standard (Vorbis/etc) |
| **Mobile** | Excellent | Good |
| **Live Update** | Basic | Excellent |
| **Pricing** | Licensed | Free tier available |
| **Video Sync** | Sofdec2 integration | None built-in |

### 15.3 When to Choose ADX2

```
CHOOSE ADX2 WHEN:

✓ Mobile game development (HCA-MX efficiency)
✓ Japanese market focus
✓ Need video middleware (Sofdec2 synergy)
✓ Team prefers DAW-like workflow
✓ High polyphony requirements on mobile
✓ Existing CRIWARE investment

CONSIDER ALTERNATIVES WHEN:

✗ Complex interactive music required
✗ Western market primary
✗ Need extensive third-party plugin ecosystem
✗ Require free tier for indie development
```

---

## 16. FluxForge Integration Points

### 16.1 Applicable Concepts

| ADX2 Concept | FluxForge Application |
|--------------|----------------------|
| **HCA-MX decode-after-mix** | Mobile optimization strategy |
| **AISAC system** | Interactive parameter mapping |
| **Cue/Track model** | Event system design |
| **Category system** | Grouping and limiting |
| **Voice behavior** | Virtualization approach |
| **Timeline authoring** | Visual editing concept |

### 16.2 Technical Insights

```rust
// Key lessons from ADX2 for FluxForge:

// 1. Decode-after-mix architecture (HCA-MX inspired)
pub struct DecodeAfterMixVoice {
    // Store compressed data, not decoded
    compressed_data: Vec<u8>,
    playback_position: usize,
    volume: f32,
    pan: f32,
}

impl DecodeAfterMixPool {
    pub fn mix_and_decode(&mut self, output: &mut [f32]) {
        // 1. Mix compressed voices (fast, just metadata)
        let mixed_compressed = self.mix_compressed_voices();

        // 2. Decode only the final mix (one decode operation)
        self.decode_to_output(mixed_compressed, output);

        // Result: N voices for cost of ~1 decode
    }
}

// 2. AISAC-style parameter system
pub struct InteractiveParameter {
    name: String,
    value: f32,  // 0.0 - 1.0
    curve: InterpolationCurve,
    targets: Vec<ParameterTarget>,
}

impl InteractiveParameter {
    pub fn apply(&self, sound: &mut SoundInstance) {
        for target in &self.targets {
            let output_value = self.curve.evaluate(self.value);
            target.apply(sound, output_value);
        }
    }
}

// 3. Voice behavior modes
pub enum VoiceBehavior {
    Normal,           // Continue playing at zero volume
    StopAtZero,       // Stop immediately
    Virtual,          // Pause and resume
    VirtualRetrigger, // Pause and restart
}

// 4. Category-based limiting
pub struct AudioCategory {
    name: String,
    volume: f32,
    cue_limit: Option<u32>,
    active_cues: Vec<CueId>,
}

impl AudioCategory {
    pub fn can_play(&self) -> bool {
        match self.cue_limit {
            Some(limit) => self.active_cues.len() < limit as usize,
            None => true,
        }
    }
}
```

### 16.3 Key Takeaways

1. **Decode-after-mix is revolutionary** — HCA-MX shows massive gains possible
2. **AISAC provides flexibility** — Parameter curves enable rich interactivity
3. **Timeline authoring is intuitive** — DAW-like workflow aids adoption
4. **Mobile optimization matters** — Codec choice dramatically impacts performance
5. **Categories simplify management** — Group-based volume and limiting
6. **Voice behavior options** — Different virtualization strategies for different needs
7. **Profiler is essential** — Real-time debugging accelerates development

---

## Appendix A: API Reference

```cpp
// Core CRI Atom API (selected functions)

// Initialization
CriBool criAtomEx_Initialize(const CriAtomExConfig* config,
                             void* work, CriSint32 work_size);
void criAtomEx_Finalize(void);

// Cue Sheet loading
CriAtomExAcbHn criAtomExAcb_LoadAcbFile(CriAtomExAcbHn acb_hn,
                                        const CriChar8* acb_path,
                                        const CriChar8* awb_path,
                                        void* work, CriSint32 work_size);
void criAtomExAcb_Release(CriAtomExAcbHn acb_hn);

// Player
CriAtomExPlayerHn criAtomExPlayer_Create(const CriAtomExPlayerConfig* config,
                                         void* work, CriSint32 work_size);
void criAtomExPlayer_Destroy(CriAtomExPlayerHn player);
void criAtomExPlayer_SetCueName(CriAtomExPlayerHn player,
                                CriAtomExAcbHn acb_hn,
                                const CriChar8* cue_name);
CriAtomExPlaybackId criAtomExPlayer_Start(CriAtomExPlayerHn player);
void criAtomExPlayer_Stop(CriAtomExPlayerHn player);
void criAtomExPlayer_SetVolume(CriAtomExPlayerHn player, CriFloat32 volume);
void criAtomExPlayer_SetPitch(CriAtomExPlayerHn player, CriFloat32 pitch);

// AISAC
void criAtomExPlayer_SetAisacControlById(CriAtomExPlayerHn player,
                                         CriAtomExAisacControlId control_id,
                                         CriFloat32 control_value);

// 3D Audio
CriAtomEx3dSourceHn criAtomEx3dSource_Create(const CriAtomEx3dSourceConfig* config,
                                              void* work, CriSint32 work_size);
void criAtomEx3dSource_SetPosition(CriAtomEx3dSourceHn source,
                                   const CriAtomExVector* position);
void criAtomEx3dSource_Update(CriAtomEx3dSourceHn source);

// Categories
void criAtomExCategory_SetVolumeById(CriAtomExCategoryId id, CriFloat32 volume);
void criAtomExCategory_MuteById(CriAtomExCategoryId id, CriBool mute);
```

---

## Appendix B: References

- [CRI ADX Official](https://www.criware.com/en/products/adx2.html)
- [CRI Middleware Blog](https://blog.criware.com/)
- [ADX2 Manual](https://game.criware.jp/manual/adx2_tool_en/latest/)
- [CRIWARE SDK Documentation](https://game.criware.jp/manual/native/adx2_en/latest/)
- [CRI Middleware Wikipedia](https://en.wikipedia.org/wiki/CRI_Middleware)

---

*Analysis complete. Document serves as reference for FluxForge audio engine development.*
