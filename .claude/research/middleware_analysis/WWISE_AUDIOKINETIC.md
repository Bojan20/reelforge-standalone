# Wwise (Audiokinetic) — Comprehensive Technical Analysis

**Version Analyzed:** Wwise 2025.1.4
**Analysis Date:** January 2026
**Analyst Role:** Chief Audio Architect / Lead DSP Engineer / Engine Architect

---

## 1. EXECUTIVE SUMMARY

Wwise (Wave Works Interactive Sound Engine) is Audiokinetic's flagship audio middleware solution, representing the industry standard for AAA game audio implementation. Used in over 5,000 commercial games including God of War, Assassin's Creed, and Cyberpunk 2077.

### Key Differentiators
- **Object-Based Audio Pipeline** — Full audio object support introduced in Wwise 2021.1
- **Behavioral Rewrite (2025.1)** — Optimized playback across multiple systems
- **Scalable Plugin Architecture** — Extensible DSP and source plugins
- **Cross-Platform Consistency** — Identical behavior on 25+ platforms

---

## 2. CORE ARCHITECTURE

### 2.1 High-Level System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     WWISE AUTHORING TOOL                                │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │ Project Manager │  │ Actor-Mixer     │  │ Interactive     │         │
│  │ & SoundBanks    │  │ Hierarchy       │  │ Music Hierarchy │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │ Profiler        │  │ Soundcaster     │  │ SoundBank       │         │
│  │ & Capture Log   │  │ (Mixing Desk)   │  │ Generator       │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     WWISE SOUND ENGINE (RUNTIME)                        │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    COMMAND BUFFER API (2025.1)                   │   │
│  │            Low-level control of audio execution order            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                    │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐       │
│  │ Voice      │  │ Streaming  │  │ Mixing     │  │ Spatial    │       │
│  │ Manager    │  │ Manager    │  │ Pipeline   │  │ Audio      │       │
│  └────────────┘  └────────────┘  └────────────┘  └────────────┘       │
│                                    │                                    │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐       │
│  │ RTPC       │  │ State      │  │ Plugin     │  │ Memory     │       │
│  │ System     │  │ Machine    │  │ Host       │  │ Manager    │       │
│  └────────────┘  └────────────┘  └────────────┘  └────────────┘       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     PLATFORM AUDIO LAYER                                │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐          │
│  │ Windows │ │ PlayStation│ │ Xbox   │ │ Switch │ │ Mobile │          │
│  │ WASAPI  │ │ Tempest  │ │ XAudio2│ │ AAC    │ │ AAudio │          │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Audio Thread Model

```
┌─────────────────────────────────────────────────────────────────┐
│                    AUDIO THREAD EXECUTION                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Frame Size: AkInitSettings::uNumSamplesPerFrame                │
│  Default: 1024 samples @ 48kHz = 21.333ms per frame             │
│                                                                  │
│  Refill Buffer: AkPlatformInitSettings::uNumRefillsInVoice      │
│  Default: 4 frames (safety buffer for timing variance)          │
│                                                                  │
│  Voice Starvation: Occurs when all refills depleted             │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Audio Thread Timeline (per frame):                             │
│                                                                  │
│  ├─── Process API Calls ─────────────────────────┤              │
│  │    - Event triggers                            │              │
│  │    - RTPC updates                              │              │
│  │    - State changes                             │              │
│  │                                                │              │
│  ├─── Voice Graph Execution ─────────────────────┤              │
│  │    - Decode audio (Vorbis/Opus/ADPCM)         │              │
│  │    - Apply voice DSP                          │              │
│  │    - Position/panning                         │              │
│  │                                                │              │
│  ├─── Bus Processing ────────────────────────────┤              │
│  │    - Effect chain execution                   │              │
│  │    - Bus mixing                               │              │
│  │    - Metering                                 │              │
│  │                                                │              │
│  ├─── Output ────────────────────────────────────┤              │
│  │    - Final mix to platform audio API          │              │
│  │                                                │              │
│  └───────────────────────────────────────────────┘              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 Job-Based Task Scheduler (AkJobMgr)

Introduced in Wwise 2022.1, replacing the old "Parallel-For" model:

```cpp
// Conceptual representation of AkJobMgr task graph
struct AkJobGraph {
    // Dependency modeling allows independent branches to execute concurrently
    std::vector<AkJob> jobs;
    std::vector<AkJobDependency> dependencies;

    // Key improvement: Bus processing can now be parallelized
    // Independent branches of Voice Graph processed concurrently
};

// Performance characteristics:
// - Greater concurrency than fork-and-join
// - Better utilization of multi-core CPUs
// - Optimized for Apple Silicon and ARM Cortex chips
```

---

## 3. VOICE MANAGEMENT SYSTEM

### 3.1 Voice Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                      VOICE PIPELINE                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  PHYSICAL VOICE (Full Processing):                              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                                                          │  │
│  │  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌──────┐ │  │
│  │  │ Source  │───▶│ Decode  │───▶│ Voice   │───▶│ Pan/ │ │  │
│  │  │ (File/  │    │ (Codec) │    │ DSP     │    │ Pos  │ │  │
│  │  │ Stream) │    │         │    │ Chain   │    │      │ │  │
│  │  └─────────┘    └─────────┘    └─────────┘    └──────┘ │  │
│  │       │              │              │              │     │  │
│  │       ▼              ▼              ▼              ▼     │  │
│  │  [I/O Cost]    [CPU Cost]    [CPU Cost]    [CPU Cost]  │  │
│  │                                                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  VIRTUAL VOICE (Minimal Processing):                            │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                                                          │  │
│  │  Only tracks:                                            │  │
│  │  - Position in source file                               │  │
│  │  - Current volume level                                  │  │
│  │  - Playback state                                        │  │
│  │                                                          │  │
│  │  NO: Decoding, DSP processing, streaming I/O             │  │
│  │                                                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Voice Limiting Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                   VOICE LIMITING HIERARCHY                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. GLOBAL VOICE LIMIT                                          │
│     └── AkInitSettings::uMaxNumPaths (platform dependent)       │
│                                                                  │
│  2. BUS VOICE LIMIT                                             │
│     └── Per-bus limit for category control                      │
│                                                                  │
│  3. SOUND OBJECT LIMIT                                          │
│     └── "Limit sound instances globally" setting                │
│         - Recommended: 1 for non-stacking sounds                │
│         - Action: "Kill voice" when limit reached               │
│         - Priority: "Discard newest instance"                   │
│                                                                  │
│  4. GAME OBJECT LIMIT                                           │
│     └── Per-emitter instance control                            │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  VIRTUAL VOICE BEHAVIOR OPTIONS:                                │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ "Kill if finite, else virtual" (RECOMMENDED DEFAULT)    │   │
│  │                                                         │   │
│  │ - Finite sounds (one-shots): Kill when inaudible       │   │
│  │ - Looping sounds: Go virtual, can resume               │   │
│  │ - Best CPU/memory efficiency                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ "Send to virtual voice"                                 │   │
│  │                                                         │   │
│  │ - All sounds go virtual when inaudible                 │   │
│  │ - Higher memory usage (tracks all)                     │   │
│  │ - Useful for seamless resume                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ "Kill voice"                                            │   │
│  │                                                         │   │
│  │ - Immediately kill inaudible voices                    │   │
│  │ - Lowest resource usage                                │   │
│  │ - May cause audible "pop-in" when resuming             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.3 Volume Threshold System

```cpp
// Volume Threshold Configuration
// Project Settings → General → Volume Threshold (per platform)

struct VolumeThresholdConfig {
    // Threshold below which voices become virtual
    float threshold_db = -96.0f;  // Very conservative
    // float threshold_db = -48.0f;  // Aggressive optimization

    // Hysteresis to prevent voice "pumping"
    float hysteresis_db = 3.0f;   // Voices become physical at threshold + 3dB
};

// Best Practices:
// - Start conservative (-96dB)
// - Gradually increase based on profiling
// - Platform-specific thresholds (mobile: -48dB, console: -60dB)
```

---

## 4. MEMORY MANAGEMENT

### 4.1 Memory Pool Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    WWISE MEMORY POOLS                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ DEFAULT POOL                                            │    │
│  │ - Sound structures                                      │    │
│  │ - Event data                                            │    │
│  │ - RTPC structures                                       │    │
│  │ - State machine data                                    │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ MEDIA POOL                                              │    │
│  │ - Decoded audio data                                    │    │
│  │ - In-memory SoundBank content                          │    │
│  │ - Prefetch buffers                                      │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ STREAMING POOL                                          │    │
│  │ - Stream buffers                                        │    │
│  │ - I/O cache                                             │    │
│  │ - Prefetch data                                         │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ LOWER ENGINE POOL                                       │    │
│  │ - Voice processing buffers                              │    │
│  │ - Effect processing buffers                             │    │
│  │ - Platform-specific allocations                         │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  MEMORY BUDGETS (Gen 8 Consoles):                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Total Audio Budget: ~250MB maximum                      │   │
│  │                                                         │   │
│  │ Breakdown:                                              │   │
│  │ - SoundBanks (loaded): 100-150MB                       │   │
│  │ - Streaming buffers: 30-50MB                           │   │
│  │ - Voice buffers: 20-30MB                               │   │
│  │ - Effect processing: 10-20MB                           │   │
│  │ - Overhead/structures: 10-20MB                         │   │
│  │                                                         │   │
│  │ Typical allocation: 10-20% of game runtime memory      │   │
│  │ Small games: ~5%                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 SoundBank Management

```
┌─────────────────────────────────────────────────────────────────┐
│                   SOUNDBANK ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  BANK TYPES:                                                    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ INIT BANK (Required)                                    │    │
│  │ - Bus hierarchy                                         │    │
│  │ - Global settings                                       │    │
│  │ - Plugin definitions                                    │    │
│  │ - Must be loaded first                                  │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ EVENT/STRUCTURE BANKS                                   │    │
│  │ - Event definitions                                     │    │
│  │ - Sound object hierarchy                                │    │
│  │ - No media (small size)                                 │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ MEDIA BANKS                                             │    │
│  │ - Audio data (.wem files)                               │    │
│  │ - Can be loaded/unloaded independently                  │    │
│  │ - Streaming media stored separately                     │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                  │
│  LOADING STRATEGIES:                                            │
│                                                                  │
│  1. Full Load: Load entire bank into memory                     │
│  2. Prepare Events: Load only required media for specific events│
│  3. Streaming: Load media on-demand during playback             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. CODEC SYSTEM

### 5.1 Software Codecs

```
┌─────────────────────────────────────────────────────────────────┐
│                      WWISE CODEC COMPARISON                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ PCM (Uncompressed)                                         ││
│  │                                                            ││
│  │ CPU Cost:    ★☆☆☆☆ (Lowest - no decoding)                ││
│  │ File Size:   ★★★★★ (Largest - 1:1)                        ││
│  │ Quality:     ★★★★★ (Perfect)                              ││
│  │                                                            ││
│  │ Use Cases:                                                 ││
│  │ - Critical UI sounds                                       ││
│  │ - Very short sounds (< 100ms)                             ││
│  │ - When CPU is the bottleneck                              ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ ADPCM (Adaptive Differential PCM)                          ││
│  │                                                            ││
│  │ CPU Cost:    ★★☆☆☆ (Very Low)                             ││
│  │ File Size:   ★★★☆☆ (4:1 compression)                      ││
│  │ Quality:     ★★★☆☆ (Acceptable for most)                  ││
│  │                                                            ││
│  │ Use Cases:                                                 ││
│  │ - Ambiences (noise masks artifacts)                       ││
│  │ - Explosions, impacts                                      ││
│  │ - Mobile platforms (CPU constrained)                      ││
│  │ - Large quantity sounds                                    ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ VORBIS (Ogg Vorbis)                                        ││
│  │                                                            ││
│  │ CPU Cost:    ★★★☆☆ (1.5x-3x ADPCM)                        ││
│  │ File Size:   ★★☆☆☆ (10:1 typical @ Q4)                    ││
│  │ Quality:     ★★★★☆ (Very Good)                            ││
│  │                                                            ││
│  │ Quality Settings: -2 to 10 (default: 4)                   ││
│  │ - Higher = better quality, more CPU                       ││
│  │ - Variable bitrate (content dependent)                    ││
│  │                                                            ││
│  │ Use Cases:                                                 ││
│  │ - Music                                                    ││
│  │ - Voice/dialogue                                           ││
│  │ - Default codec recommendation                             ││
│  │ - Streaming content                                        ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ OPUS                                                       ││
│  │                                                            ││
│  │ CPU Cost:    ★★★★★ (5x-10x ADPCM)                         ││
│  │ File Size:   ★☆☆☆☆ (Best compression)                     ││
│  │ Quality:     ★★★★★ (Excellent)                            ││
│  │                                                            ││
│  │ Limitations:                                               ││
│  │ - 80ms padding added (setup overhead)                     ││
│  │ - Not suitable for < 200ms sounds                         ││
│  │ - High CPU cost                                            ││
│  │                                                            ││
│  │ Use Cases:                                                 ││
│  │ - Long music tracks                                        ││
│  │ - Voice-over (when file size critical)                    ││
│  │ - When hardware decoding available                        ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  CODEC SELECTION MATRIX:                                        │
│                                                                  │
│  Content Type        │ Primary    │ Alternative │ Avoid         │
│  ────────────────────┼────────────┼─────────────┼───────────────│
│  UI/Menu             │ PCM        │ ADPCM       │ Opus          │
│  Footsteps           │ ADPCM      │ Vorbis Q2   │ PCM           │
│  Impacts             │ ADPCM      │ Vorbis Q2   │ -             │
│  Ambience            │ ADPCM      │ Vorbis Q4   │ -             │
│  Voice/Dialogue      │ Vorbis Q6  │ Opus        │ ADPCM         │
│  Music               │ Vorbis Q6  │ Opus        │ PCM/ADPCM     │
│  Cinematics          │ Opus       │ Vorbis Q8   │ ADPCM         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Platform-Specific Codecs

```
┌─────────────────────────────────────────────────────────────────┐
│              PLATFORM HARDWARE CODEC SUPPORT                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  PlayStation 5:                                                 │
│  - Hardware ATRAC9 decoder                                      │
│  - Tempest 3D Audio Unit (dedicated DSP)                       │
│  - Recommended: Leverage hardware when possible                 │
│                                                                  │
│  Xbox Series X/S:                                               │
│  - Hardware XMA2 decoder                                        │
│  - Spatial audio processing support                             │
│  - Windows Sonic / Dolby Atmos native                          │
│                                                                  │
│  Nintendo Switch:                                               │
│  - Hardware ADPCM decoder                                       │
│  - Limited CPU - prefer ADPCM                                   │
│  - Opus hardware support (v10.0.0+)                            │
│                                                                  │
│  Mobile (iOS/Android):                                          │
│  - AAC hardware decoder (iOS)                                   │
│  - Opus becoming standard                                       │
│  - ADPCM for CPU efficiency                                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. SPATIAL AUDIO SYSTEM

### 6.1 Spatial Audio Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                   WWISE SPATIAL AUDIO PIPELINE                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  INPUT SOURCES                                                  │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐            │
│  │ Mono    │  │ Stereo  │  │ 5.1/7.1 │  │Ambisonics│            │
│  │ Point   │  │ Spread  │  │ Bed     │  │ 1st-5th │            │
│  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘            │
│       │            │            │            │                   │
│       ▼            ▼            ▼            ▼                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              3D POSITIONING ENGINE                       │   │
│  │                                                         │   │
│  │  ┌─────────────────┐  ┌─────────────────┐              │   │
│  │  │ Distance        │  │ Cone            │              │   │
│  │  │ Attenuation     │  │ Attenuation     │              │   │
│  │  │ - Linear        │  │ - Inner/Outer   │              │   │
│  │  │ - Log           │  │ - LPF on cone   │              │   │
│  │  │ - Inverse       │  │                 │              │   │
│  │  │ - Custom curves │  │                 │              │   │
│  │  └─────────────────┘  └─────────────────┘              │   │
│  │                                                         │   │
│  │  ┌─────────────────┐  ┌─────────────────┐              │   │
│  │  │ Spread          │  │ Focus           │              │   │
│  │  │ - Point → Width │  │ - Narrow beam   │              │   │
│  │  │ - Distance-based│  │ - For close src │              │   │
│  │  └─────────────────┘  └─────────────────┘              │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            │                                    │
│                            ▼                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              ROOM & PORTAL SYSTEM                        │   │
│  │                                                         │   │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐ │   │
│  │  │ Room        │◄──▶│ Portal      │◄──▶│ Room        │ │   │
│  │  │ - Reverb    │    │ - Occlusion │    │ - Reverb    │ │   │
│  │  │ - Geometry  │    │ - Diffraction│   │ - Geometry  │ │   │
│  │  │ - Aux sends │    │ - Filtering │    │ - Aux sends │ │   │
│  │  └─────────────┘    └─────────────┘    └─────────────┘ │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            │                                    │
│                            ▼                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              WWISE REFLECT (Early Reflections)           │   │
│  │                                                         │   │
│  │  - Up to 4 reflections per wave path                   │   │
│  │  - Acoustic Textures for material simulation           │   │
│  │    - Absorption coefficients                           │   │
│  │    - Frequency-dependent damping                       │   │
│  │    - Roughness/scattering                              │   │
│  │  - Real-time ray tracing                               │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            │                                    │
│                            ▼                                    │
│  OUTPUT RENDERING                                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ Speakers    │  │ Headphones  │  │ Audio       │             │
│  │ 5.1/7.1/    │  │ + HRTF      │  │ Objects     │             │
│  │ Atmos       │  │ Binaural    │  │ (Atmos/DTS) │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Ambisonics Implementation

```
┌─────────────────────────────────────────────────────────────────┐
│                   AMBISONICS IN WWISE                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  SUPPORTED FORMATS:                                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ FuMa (Furse-Malham)    │ Up to 3rd Order (16 channels) │   │
│  │ AmbiX (ACN/SN3D)       │ Up to 5th Order (36 channels) │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ORDER / CHANNEL COUNT:                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 1st Order:  4 channels  (W, X, Y, Z)                   │   │
│  │ 2nd Order:  9 channels                                  │   │
│  │ 3rd Order: 16 channels                                  │   │
│  │ 4th Order: 25 channels                                  │   │
│  │ 5th Order: 36 channels                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  SPHERICAL HARMONICS (1st Order FuMa):                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ W = Omni (omnidirectional, direction-agnostic)         │   │
│  │ X = Front-Back axis                                     │   │
│  │ Y = Left-Right axis                                     │   │
│  │ Z = Up-Down axis                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  BUS CONFIGURATION:                                             │
│  - Set bus channel configuration to Ambisonics                  │
│  - Non-ambisonic → ambisonic bus: Auto-encode                  │
│  - Ambisonic → non-ambisonic bus: Auto-decode                  │
│                                                                  │
│  ROTATION:                                                      │
│  - Minimal CPU cost (matrix operations in ambisonic domain)    │
│  - Ideal for VR head tracking                                   │
│                                                                  │
│  TRADEOFFS vs AUDIO OBJECTS:                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 Ambisonics    │    Audio Objects        │   │
│  │ Spatial Res.   Fixed (order) │    Perfect              │   │
│  │ CPU Cost       Fixed         │    Per-object           │   │
│  │ Memory         Fixed         │    Per-object           │   │
│  │ Rotation       Cheap         │    Expensive            │   │
│  │ Best For       VR, Ambience  │    Precise Positioning  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.3 HRTF Processing

```
┌─────────────────────────────────────────────────────────────────┐
│                      HRTF IN WWISE                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  BUILT-IN HRTF:                                                 │
│  - Wwise default binaural spatialization                        │
│  - Configurable via Audio Device shareset                       │
│                                                                  │
│  THIRD-PARTY HRTF PLUGINS:                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Meta XR Audio SDK                                       │   │
│  │ - Proprietary HRTF model                               │   │
│  │ - Superior localization vs public datasets             │   │
│  │ - Spectral transparency                                 │   │
│  │ - Optimized for Quest/Rift                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Resonance Audio (Google)                                │   │
│  │ - Open source                                           │   │
│  │ - Ambisonics-based                                      │   │
│  │ - Room acoustics simulation                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ DearVR                                                  │   │
│  │ - High-quality HRTF                                     │   │
│  │ - Multiple HRTF profiles                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  CHANNEL VIRTUALIZATION:                                        │
│  - 7.1 → Binaural (virtual speakers around head)               │
│  - Standard distances and angles for channel positions         │
│  - HRTF applied per virtual speaker                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. INTERACTIVE MUSIC SYSTEM

### 7.1 Music Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                INTERACTIVE MUSIC HIERARCHY                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ MUSIC SWITCH CONTAINER                                   │   │
│  │ - State/Switch driven selection                         │   │
│  │ - Transition rules between children                     │   │
│  │                                                         │   │
│  │  ┌───────────────────────────────────────────────────┐ │   │
│  │  │ MUSIC PLAYLIST CONTAINER                          │ │   │
│  │  │ - Sequential/Random/Shuffle playback              │ │   │
│  │  │ - Weighted random                                  │ │   │
│  │  │                                                   │ │   │
│  │  │  ┌─────────────────────────────────────────────┐ │ │   │
│  │  │  │ MUSIC SEGMENT                               │ │ │   │
│  │  │  │ - Entry Cue (sync point for transitions)   │ │ │   │
│  │  │  │ - Exit Cue (allowed transition points)     │ │ │   │
│  │  │  │ - Pre-Entry / Post-Exit regions            │ │ │   │
│  │  │  │                                             │ │ │   │
│  │  │  │  ┌───────────────────────────────────────┐ │ │ │   │
│  │  │  │  │ MUSIC TRACK                           │ │ │ │   │
│  │  │  │  │ - Horizontal (timeline based)        │ │ │ │   │
│  │  │  │  │ - Sub-tracks for layering            │ │ │ │   │
│  │  │  │  │ - Clips with crossfades              │ │ │ │   │
│  │  │  │  └───────────────────────────────────────┘ │ │ │   │
│  │  │  │                                             │ │ │   │
│  │  │  └─────────────────────────────────────────────┘ │ │   │
│  │  │                                                   │ │   │
│  │  └───────────────────────────────────────────────────┘ │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Transition System

```
┌─────────────────────────────────────────────────────────────────┐
│                    TRANSITION RULES                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  SOURCE SYNC POINTS (When to leave):                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ - Immediate                                              │   │
│  │ - Next Grid (quantized to tempo grid)                   │   │
│  │ - Next Bar                                               │   │
│  │ - Next Beat                                              │   │
│  │ - Next Cue                                               │   │
│  │ - Exit Cue (designated exit point)                      │   │
│  │ - Same Time as Playing Segment                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  DESTINATION SYNC POINTS (Where to enter):                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ - Entry Cue (designated entry point)                    │   │
│  │ - Same Time as Playing Segment                          │   │
│  │ - Random Cue                                             │   │
│  │ - Random Position                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  FADE TYPES:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ None         - Hard cut                                  │   │
│  │ XFade (Amp)  - Linear amplitude crossfade               │   │
│  │ XFade (Power)- Equal-power crossfade                    │   │
│  │ Fade Out     - Source fades, destination starts full    │   │
│  │ Fade In      - Source cuts, destination fades in        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  TRANSITION SEGMENTS:                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ - Bridge between incompatible musical pieces            │   │
│  │ - Any segment can act as transition segment             │   │
│  │ - Composed specifically to connect sections             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 7.3 Stingers

```
┌─────────────────────────────────────────────────────────────────┐
│                       STINGERS                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  DEFINITION:                                                    │
│  Brief musical phrases superimposed over currently playing music│
│  Triggered by game events (Triggers)                            │
│                                                                  │
│  PROPERTIES:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ - Uses Music Segment (not Sound SFX)                    │   │
│  │ - Entry Cue defines sync point with playing music       │   │
│  │ - Inherits segment benefits (variation, etc.)           │   │
│  │ - Don't interrupt underlying music                      │   │
│  │ - Mixed on top of current playback                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  SYNC OPTIONS:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ - Immediate                                              │   │
│  │ - Next Grid                                              │   │
│  │ - Next Beat                                              │   │
│  │ - Next Bar                                               │   │
│  │ - Next Cue                                               │   │
│  │ - Entry Cue                                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  USE CASES:                                                     │
│  - Kill confirmations                                           │
│  - Collectible pickups                                          │
│  - Objective completions                                        │
│  - Combat hits                                                  │
│  - Dramatic reveals                                             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 7.4 MIDI Integration

```
┌─────────────────────────────────────────────────────────────────┐
│                     MIDI IN WWISE                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  MIDI FILE PLAYBACK:                                            │
│  - Import MIDI files into Music Tracks                          │
│  - Route to Synth One (built-in synthesizer)                   │
│  - Route to sampler instruments                                 │
│                                                                  │
│  SYNTH ONE:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ - Subtractive synthesis                                  │   │
│  │ - 2 oscillators (saw, square, triangle, sine, noise)   │   │
│  │ - Filter (LP, HP, BP)                                   │   │
│  │ - 2 ADSR envelopes                                      │   │
│  │ - LFO                                                    │   │
│  │ - Effects section                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  SAMPLER INSTRUMENTS:                                           │
│  - Create custom sample-based instruments                       │
│  - Multi-sample mapping                                         │
│  - Velocity layers                                              │
│  - Round-robin variation                                        │
│                                                                  │
│  MIDI CONTROLLERS:                                              │
│  - Hardware MIDI input in authoring tool                       │
│  - Map to RTPCs, States, Switches                              │
│  - Soundcaster integration                                      │
│  - Tempo-synchronized playback                                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. PLUGIN ARCHITECTURE

### 8.1 Plugin Types

```
┌─────────────────────────────────────────────────────────────────┐
│                    WWISE PLUGIN TYPES                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  SOURCE PLUGINS:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Generate audio (no input required)                      │   │
│  │                                                         │   │
│  │ Built-in:                                               │   │
│  │ - Silence                                                │   │
│  │ - Sine (Tone Generator)                                 │   │
│  │ - Synth One                                              │   │
│  │                                                         │   │
│  │ Appear in: Add Source menu                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  EFFECT PLUGINS:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Process existing audio                                  │   │
│  │                                                         │   │
│  │ Built-in:                                               │   │
│  │ - Wwise Compressor                                      │   │
│  │ - Wwise Delay                                           │   │
│  │ - Wwise Expander                                        │   │
│  │ - Wwise Flanger                                         │   │
│  │ - Wwise Gain                                            │   │
│  │ - Wwise Guitar Distortion                               │   │
│  │ - Wwise Harmonizer                                      │   │
│  │ - Wwise Matrix Reverb                                   │   │
│  │ - Wwise Meter                                           │   │
│  │ - Wwise Parametric EQ                                   │   │
│  │ - Wwise Peak Limiter                                    │   │
│  │ - Wwise Pitch Shifter                                   │   │
│  │ - Wwise Reflect (Early Reflections)                     │   │
│  │ - Wwise RoomVerb                                        │   │
│  │ - Wwise Stereo Delay                                    │   │
│  │ - Wwise Time Stretch                                    │   │
│  │ - Wwise Tremolo                                         │   │
│  │                                                         │   │
│  │ Appear in: Effect column of Object/Bus                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  SINK PLUGINS:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Output audio to external systems                        │   │
│  │                                                         │   │
│  │ Examples:                                                │   │
│  │ - System output                                         │   │
│  │ - Recording                                              │   │
│  │ - Network streaming                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  MIXER PLUGINS:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Custom mixing behavior                                  │   │
│  │                                                         │   │
│  │ Examples:                                                │   │
│  │ - Object-based panner                                   │   │
│  │ - Custom spatialization                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 Plugin Development

```cpp
// Plugin Project Structure (generated by wp.py)
//
// MyPlugin/
// ├── SoundEnginePlugin/
// │   ├── MyPluginFX.cpp        // DSP implementation
// │   ├── MyPluginFX.h          // DSP header
// │   ├── MyPluginFXParams.cpp  // Parameter handling
// │   ├── MyPluginFXParams.h    // Parameter definitions
// │   └── MyPluginFXFactory.h   // Factory for registration
// ├── WwisePlugin/
// │   ├── MyPlugin.cpp          // Authoring UI
// │   ├── MyPlugin.h
// │   └── MyPlugin.xml          // Plugin descriptor
// └── PremakePlugin.lua         // Build configuration

// Example Effect Plugin DSP
class MyPluginFX : public AK::IAkInPlaceEffectPlugin
{
public:
    // Initialize plugin instance
    AKRESULT Init(
        AK::IAkPluginMemAlloc* in_pAllocator,
        AK::IAkEffectPluginContext* in_pContext,
        AK::IAkPluginParam* in_pParams,
        AkAudioFormat& in_rFormat) override;

    // Process audio buffer
    void Execute(AkAudioBuffer* io_pBuffer) override
    {
        // Access parameters
        MyPluginFXParams* pParams =
            static_cast<MyPluginFXParams*>(m_pParams);

        // Get gain in linear (convert from dB)
        float fGain = AK_DBTOLIN(pParams->fGainDb);

        // Process each channel
        for (AkUInt32 ch = 0; ch < io_pBuffer->NumChannels(); ++ch)
        {
            AkSampleType* pBuf = io_pBuffer->GetChannel(ch);

            for (AkUInt32 i = 0; i < io_pBuffer->uValidFrames; ++i)
            {
                pBuf[i] *= fGain;
            }
        }
    }

    // Terminate and free resources
    AKRESULT Term(AK::IAkPluginMemAlloc* in_pAllocator) override;
};

// Plugin Registration
// Unique Company ID required (check AkTypes.h for used IDs)
// Company IDs in use: 0, 1, 256-264
AK_IMPLEMENT_PLUGIN_FACTORY(
    MyPluginFX,
    AkPluginTypeEffect,
    MyCompanyID,
    MyPluginID
)
```

### 8.3 Plugin Deployment

```
┌─────────────────────────────────────────────────────────────────┐
│                   PLUGIN DEPLOYMENT                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  AUTHORING PLUGIN (.dll):                                       │
│  └── %WWISESDK%/Authoring/x64/Release/bin/Plugins/             │
│                                                                  │
│  SOUND ENGINE PLUGIN:                                           │
│  └── Game Project/Assets/Wwise/Deployment/Plugin/              │
│      └── Windows/x86_64/DSP/MyPlugin.dll                       │
│                                                                  │
│  BUILD CONFIGURATIONS:                                          │
│  - Debug                                                        │
│  - Profile (with profiling symbols)                            │
│  - Release                                                      │
│                                                                  │
│  PLATFORM TARGETS:                                              │
│  - Windows (x64_vc160, x64_vc170)                              │
│  - PlayStation 5 (ps5)                                          │
│  - Xbox Series X|S (xboxseriesx)                               │
│  - Nintendo Switch (nx64)                                       │
│  - iOS (ios)                                                    │
│  - Android (android)                                            │
│  - Linux (linux_amd64)                                          │
│  - macOS (mac)                                                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9. RTPC SYSTEM (Real-Time Parameter Control)

### 9.1 RTPC Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      RTPC SYSTEM                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  GAME PARAMETER → RTPC → TARGET PROPERTIES                      │
│                                                                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐ │
│  │ Game Code   │───▶│ RTPC Curve  │───▶│ Volume              │ │
│  │ SetRTPCValue│    │ (mapping)   │    │ Pitch               │ │
│  │             │    │             │    │ LPF/HPF             │ │
│  │ Value: 0-100│    │ Transform   │    │ Bus Volume          │ │
│  │             │    │             │    │ Effect Parameters   │ │
│  └─────────────┘    └─────────────┘    │ Positioning         │ │
│                                         │ Playback Speed      │ │
│                                         │ Make-up Gain        │ │
│                                         │ Initial Delay       │ │
│                                         │ etc...              │ │
│                                         └─────────────────────┘ │
│                                                                  │
│  CURVE TYPES:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ - Linear                                                 │   │
│  │ - Logarithmic (Base 3)                                  │   │
│  │ - S-Curve                                                │   │
│  │ - Inverse S-Curve                                       │   │
│  │ - Exponential (Base 3)                                  │   │
│  │ - Constant                                               │   │
│  │ - Custom (user-defined points)                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  PERFORMANCE (Wwise 2022.1+):                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ - RTPC performance unaffected by loaded object count    │   │
│  │ - Only depends on:                                      │   │
│  │   - Number of registered game objects                   │   │
│  │   - Number of active sounds using the RTPC              │   │
│  │ - O(active_sounds) instead of O(all_sounds)            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 9.2 Built-in Game Parameters

```
┌─────────────────────────────────────────────────────────────────┐
│                 BUILT-IN GAME PARAMETERS                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  SPATIAL:                                                       │
│  - Distance (emitter to listener)                               │
│  - Azimuth (horizontal angle)                                   │
│  - Elevation (vertical angle)                                   │
│  - Spread                                                       │
│  - Focus                                                        │
│                                                                  │
│  OBSTRUCTION/OCCLUSION:                                         │
│  - Obstruction (direct path blocked)                            │
│  - Occlusion (full blockage)                                    │
│                                                                  │
│  CONE:                                                          │
│  - Cone attenuation angle                                       │
│                                                                  │
│  DIFFRACTION:                                                   │
│  - Diffraction amount                                           │
│  - Transmission loss                                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 10. PROFILER & OPTIMIZATION

### 10.1 Profiler Views

```
┌─────────────────────────────────────────────────────────────────┐
│                    PROFILER LAYOUT                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ CAPTURE LOG                                              │   │
│  │ - All sound engine activities                           │   │
│  │ - Event triggers                                         │   │
│  │ - State/Switch changes                                   │   │
│  │ - Errors and warnings                                    │   │
│  │ - Memory operations                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ PERFORMANCE MONITOR                                      │   │
│  │                                                         │   │
│  │ Key Metrics:                                            │   │
│  │ - Audio Thread CPU%                                     │   │
│  │ - Number of Voices (Physical)                           │   │
│  │ - Number of Voices (Virtual)                            │   │
│  │ - Number of Streams (Active)                            │   │
│  │ - Spatial Audio CPU                                     │   │
│  │ - Total Reserved Memory                                 │   │
│  │ - Total Media Memory                                    │   │
│  │ - SoundBank Memory                                      │   │
│  │ - Streaming Memory                                      │   │
│  │ - API Calls per Frame                                   │   │
│  │ - Transitions (active property changes)                 │   │
│  │                                                         │   │
│  │ Graph Settings:                                         │   │
│  │ - Set min/max values                                    │   │
│  │ - Values exceeding max shown as solid block             │   │
│  │ - Easy to spot budget violations                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ADVANCED PROFILER                                        │   │
│  │                                                         │   │
│  │ - Voice Inspector (per-voice details)                   │   │
│  │ - Bus Hierarchy (signal flow visualization)             │   │
│  │ - Game Object Explorer (per-emitter breakdown)          │   │
│  │ - Memory Tab (allocation details)                       │   │
│  │ - Streams Tab (I/O details)                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 10.2 Optimization Guidelines

```
┌─────────────────────────────────────────────────────────────────┐
│                 CPU OPTIMIZATION TARGETS                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  VOICE COUNT TARGETS (per platform):                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Platform          │ Physical │ Virtual │ Total Budget   │   │
│  │ ──────────────────┼──────────┼─────────┼────────────────│   │
│  │ High-end PC       │ 100-150  │ < 1000  │ 5% CPU         │   │
│  │ PS5 / Xbox Series │ 80-100   │ < 500   │ 5% CPU         │   │
│  │ PS4 / Xbox One    │ 50-70    │ < 300   │ 5% CPU         │   │
│  │ Nintendo Switch   │ 30-50    │ < 200   │ 7% CPU         │   │
│  │ Mobile (High)     │ 30-40    │ < 200   │ 10% CPU        │   │
│  │ Mobile (Low)      │ 15-25    │ < 100   │ 10% CPU        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  TRANSITION COUNT:                                              │
│  - Target: < 500 active transitions                             │
│  - Above 500: potential CPU spike culprit                       │
│                                                                  │
│  API CALLS PER FRAME:                                           │
│  - Minimize unnecessary calls                                    │
│  - Batch state changes when possible                            │
│  - Use AK::SoundEngine::StartProfilerCapture() for debugging    │
│                                                                  │
│  SAMPLE RATE:                                                   │
│  - 48kHz is cheaper than 44.1kHz (no SRC needed)               │
│  - 24kHz requires compensation, may cost more                   │
│  - Match system sample rate when possible                       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 10.3 Memory Optimization

```
┌─────────────────────────────────────────────────────────────────┐
│                 MEMORY OPTIMIZATION TARGETS                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  TOTAL AUDIO BUDGET:                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Platform          │ Target Budget │ % of Runtime Memory │   │
│  │ ──────────────────┼───────────────┼─────────────────────│   │
│  │ High-end PC       │ 400-500 MB    │ 5-10%               │   │
│  │ PS5 / Xbox Series │ 300-400 MB    │ 10-15%              │   │
│  │ PS4 / Xbox One    │ 200-250 MB    │ 15-20%              │   │
│  │ Nintendo Switch   │ 100-150 MB    │ 10-15%              │   │
│  │ Mobile            │ 50-100 MB     │ 5-10%               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  SOUNDBANK STRATEGIES:                                          │
│  1. Split by area/level (load/unload as needed)                │
│  2. Separate event banks from media banks                       │
│  3. Use streaming for long files (> 5 seconds)                 │
│  4. Prefetch frequently used sounds                             │
│  5. Use PrepareEvent for on-demand loading                     │
│                                                                  │
│  COMPRESSION IMPACT:                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Codec   │ Memory (loaded)  │ CPU Trade-off            │   │
│  │ ────────┼──────────────────┼──────────────────────────│   │
│  │ PCM     │ Largest          │ Lowest CPU               │   │
│  │ ADPCM   │ 4x smaller       │ Low CPU                  │   │
│  │ Vorbis  │ 10x smaller      │ Medium CPU               │   │
│  │ Opus    │ 15x smaller      │ High CPU                 │   │
│  │ Stream  │ Buffer only      │ I/O dependent            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11. SDK INTEGRATION

### 11.1 Initialization

```cpp
// Wwise SDK Initialization Flow

#include <AK/SoundEngine/Common/AkMemoryMgr.h>
#include <AK/SoundEngine/Common/AkModule.h>
#include <AK/SoundEngine/Common/IAkStreamMgr.h>
#include <AK/SoundEngine/Common/AkSoundEngine.h>
#include <AK/MusicEngine/Common/AkMusicEngine.h>
#include <AK/SpatialAudio/Common/AkSpatialAudio.h>

bool InitWwise()
{
    // 1. Memory Manager
    AkMemSettings memSettings;
    AK::MemoryMgr::GetDefaultSettings(memSettings);
    if (AK::MemoryMgr::Init(&memSettings) != AK_Success)
        return false;

    // 2. Streaming Manager
    AkStreamMgrSettings stmSettings;
    AK::StreamMgr::GetDefaultSettings(stmSettings);
    if (!AK::StreamMgr::Create(stmSettings))
        return false;

    // 3. Low-Level I/O
    AkDeviceSettings deviceSettings;
    AK::StreamMgr::GetDefaultDeviceSettings(deviceSettings);
    g_lowLevelIO.Init(deviceSettings);

    // 4. Sound Engine
    AkInitSettings initSettings;
    AkPlatformInitSettings platformInitSettings;
    AK::SoundEngine::GetDefaultInitSettings(initSettings);
    AK::SoundEngine::GetDefaultPlatformInitSettings(platformInitSettings);

    // Configure settings
    initSettings.uNumSamplesPerFrame = 1024;        // 21.33ms @ 48kHz
    platformInitSettings.uNumRefillsInVoice = 4;    // Safety buffer

    if (AK::SoundEngine::Init(&initSettings, &platformInitSettings) != AK_Success)
        return false;

    // 5. Music Engine
    AkMusicSettings musicInit;
    AK::MusicEngine::GetDefaultInitSettings(musicInit);
    if (AK::MusicEngine::Init(&musicInit) != AK_Success)
        return false;

    // 6. Spatial Audio
    AkSpatialAudioInitSettings spatialSettings;
    AK::SpatialAudio::GetDefaultInitSettings(spatialSettings);
    if (AK::SpatialAudio::Init(spatialSettings) != AK_Success)
        return false;

    return true;
}
```

### 11.2 Game Loop Integration

```cpp
// Per-Frame Update

void GameAudioUpdate()
{
    // 1. Update listener position
    AkListenerPosition listenerPos;
    // ... set from camera transform
    AK::SoundEngine::SetListenerPosition(listenerPos);

    // 2. Update emitter positions
    for (auto& emitter : activeEmitters)
    {
        AkSoundPosition soundPos;
        // ... set from game object transform
        AK::SoundEngine::SetPosition(emitter.gameObjectId, soundPos);
    }

    // 3. Update RTPCs
    AK::SoundEngine::SetRTPCValue("Health", playerHealth);
    AK::SoundEngine::SetRTPCValue("Speed", playerSpeed);

    // 4. Update States
    AK::SoundEngine::SetState("GameState", currentState);

    // 5. Process audio (CRITICAL - must be called every frame)
    AK::SoundEngine::RenderAudio();
}
```

### 11.3 Event API

```cpp
// Event Playback API

// Simple event posting
AK::SoundEngine::PostEvent("Play_Footstep", gameObjectId);

// With callback
AK::SoundEngine::PostEvent(
    "Play_Music",
    gameObjectId,
    AK_EndOfEvent | AK_MusicSyncBeat,
    &MusicCallback,
    pCookie
);

// With external sources
AkExternalSourceInfo externalSources[1];
externalSources[0].iExternalSrcCookie = hash("MyFile");
externalSources[0].szFile = "path/to/file.wem";
externalSources[0].idCodec = AKCODECID_VORBIS;

AK::SoundEngine::PostEvent(
    "Play_DynamicVO",
    gameObjectId,
    0, nullptr, nullptr,
    1, externalSources
);

// Stop event
AK::SoundEngine::ExecuteActionOnEvent(
    "Play_Music",
    AK::SoundEngine::AkActionOnEventType_Stop,
    gameObjectId,
    500,  // Fade out time (ms)
    AkCurveInterpolation_Linear
);
```

---

## 12. PLATFORM-SPECIFIC CONSIDERATIONS

### 12.1 Platform Matrix

```
┌─────────────────────────────────────────────────────────────────┐
│              WWISE PLATFORM SUPPORT MATRIX                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ Platform          │ Hardware │ Spatial      │ Notes        ││
│  │                   │ Codec    │ Audio        │              ││
│  │ ──────────────────┼──────────┼──────────────┼──────────────││
│  │ Windows           │ -        │ Atmos, Sonic │ WASAPI       ││
│  │ PlayStation 5     │ ATRAC9   │ Tempest 3D   │ Object audio ││
│  │ PlayStation 4     │ ATRAC9   │ 7.1 Virtual  │ PRX support  ││
│  │ Xbox Series X|S   │ XMA2     │ Atmos        │ Object audio ││
│  │ Xbox One          │ XMA2     │ Atmos        │ Shape audio  ││
│  │ Nintendo Switch   │ ADPCM HW │ -            │ Opus HW 10+  ││
│  │ iOS               │ AAC HW   │ -            │ AVAudioEngine││
│  │ Android           │ -        │ -            │ AAudio/OpenSL││
│  │ macOS             │ -        │ -            │ CoreAudio    ││
│  │ Linux             │ -        │ -            │ PulseAudio   ││
│  │ tvOS              │ AAC HW   │ -            │              ││
│  │ Stadia            │ -        │ -            │ Deprecated   ││
│  │ Magic Leap        │ -        │ Spatial      │              ││
│  │ Oculus            │ -        │ Meta XR      │              ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 12.2 Engine Integrations

```
┌─────────────────────────────────────────────────────────────────┐
│                 ENGINE INTEGRATIONS                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  UNREAL ENGINE:                                                 │
│  - Full Blueprint support                                       │
│  - Actor components (AkComponent)                               │
│  - AkAmbientSound, AkSplineComponent                           │
│  - Reverb volume integration                                    │
│  - Dynamic Dialogue workflow (2025.1)                          │
│  - Geometry for spatial audio                                   │
│                                                                  │
│  UNITY:                                                         │
│  - Wwise Unity Integration package                              │
│  - AkSoundEngine wrapper                                        │
│  - AkEvent, AkBank, AkTrigger components                       │
│  - Wwise Browser (2025.1)                                      │
│  - Timeline integration                                         │
│  - Addressables support                                         │
│                                                                  │
│  GODOT:                                                         │
│  - Community integration                                        │
│  - GDNative bindings                                            │
│                                                                  │
│  CUSTOM ENGINES:                                                │
│  - Direct SDK integration                                       │
│  - C++ / C# bindings                                            │
│  - Platform-specific implementations                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 13. WWISE 2025.1 NEW FEATURES

### 13.1 Command Buffer API

```cpp
// New low-level API for controlling audio execution order
// Expert-level feature for audio programmers

// Benefits:
// - Fine-grained control over operation timing
// - Deterministic execution order
// - Reduced latency for critical operations

// Use cases:
// - Time-critical sound triggers
// - Complex state synchronization
// - Custom audio scheduling
```

### 13.2 Behavioral Rewrite

```
┌─────────────────────────────────────────────────────────────────┐
│              WWISE 2025.1 BEHAVIORAL REWRITE                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  OPTIMIZATIONS:                                                 │
│  - Playback optimized across multiple systems                   │
│  - Improved job scheduling                                      │
│  - Better cache utilization                                     │
│  - Reduced memory fragmentation                                 │
│                                                                  │
│  STABILITY:                                                     │
│  - Stabilization of fundamentals                                │
│  - Dynamic sound playback improvements                          │
│  - Edge case handling                                           │
│                                                                  │
│  SDK IMPROVEMENTS:                                              │
│  - Plugin Unit Test framework                                   │
│  - Better documentation                                         │
│  - Improved debugging tools                                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 13.3 Media Pool & Similar Sound Search

```
┌─────────────────────────────────────────────────────────────────┐
│                    MEDIA POOL (2025.1)                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  - Centralized media management                                 │
│  - Asset deduplication                                          │
│  - Better organization                                          │
│  - Improved search capabilities                                 │
│                                                                  │
│  SIMILAR SOUND SEARCH:                                          │
│  - AI-powered similarity detection                              │
│  - Find similar sounds in library                               │
│  - Spectral analysis comparison                                 │
│  - Workflow acceleration                                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 14. BEST PRACTICES SUMMARY

### 14.1 Design Guidelines

```
┌─────────────────────────────────────────────────────────────────┐
│                 WWISE BEST PRACTICES                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  VOICE MANAGEMENT:                                              │
│  ✓ Set global voice limits per platform                        │
│  ✓ Use "Kill if finite, else virtual" as default               │
│  ✓ Configure volume thresholds per platform                    │
│  ✓ Set playback limits on sound objects                        │
│  ✓ Use priorities for importance-based culling                 │
│                                                                  │
│  MEMORY:                                                        │
│  ✓ Split SoundBanks by level/area                              │
│  ✓ Separate event and media banks                              │
│  ✓ Stream files > 5 seconds                                    │
│  ✓ Use PrepareEvent for on-demand loading                      │
│  ✓ Profile and set budgets early                               │
│                                                                  │
│  CODECS:                                                        │
│  ✓ Use Vorbis as default                                       │
│  ✓ ADPCM for noisy sounds / mobile                             │
│  ✓ PCM for critical short sounds                               │
│  ✓ Opus only for long files with hardware support              │
│  ✓ Match content type to compression level                     │
│                                                                  │
│  PERFORMANCE:                                                   │
│  ✓ Profile regularly during development                        │
│  ✓ Set Performance Monitor thresholds                          │
│  ✓ Minimize API calls per frame                                │
│  ✓ Use 48kHz to avoid sample rate conversion                   │
│  ✓ Batch state changes when possible                           │
│                                                                  │
│  SPATIAL AUDIO:                                                 │
│  ✓ Use Rooms & Portals for environment                         │
│  ✓ Configure acoustic textures appropriately                   │
│  ✓ Limit reflection count (max 4)                              │
│  ✓ Use ambisonics for VR/ambiences                             │
│  ✓ Audio Objects for critical positioned sounds                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 15. REFERENCES

### Official Documentation
- [Wwise Documentation (2025.1.4)](https://www.audiokinetic.com/en/public-library/2025.1.4_9062/?source=Help&id=welcome_to_wwise)
- [Wwise Fundamentals PDF](https://www.audiokinetic.com/download/documents/Wwise_Fundamentals.pdf)
- [Wwise Audio Lab](https://www.audiokinetic.com/en/public-library/wal/)

### Technical Resources
- [SDK Runtime Performance Improvements in Wwise 2022.1](https://blog.audiokinetic.com/en/sdk-runtime-performance-improvements-in-wwise-2022.1/)
- [Wwise CPU Optimizations: General Guidelines](https://blog.audiokinetic.com/wwise-cpu-optimizations-general-guidelines/)
- [A Guide for Choosing the Right Codec](https://www.audiokinetic.com/en/blog/a-guide-for-choosing-the-right-codec/)
- [Ambisonics in Wwise: Overview](https://www.audiokinetic.com/en/products/ambisonics-in-wwise/)

### Spatial Audio
- [A Wwise Approach to Spatial Audio - Part 1](https://www.audiokinetic.com/en/blog/a-wwise-approach-to-spatial-audio-part-1/)
- [How Audio Objects Improve Spatial Accuracy](https://www.audiokinetic.com/en/blog/how-audio-objects-improve-spatial-accuracy/)

### Music System
- [Making Interactive Music in Real Life with Wwise](https://www.audiokinetic.com/en/blog/making-interactive-music-in-real-life-with-wwise/)

### Plugin Development
- [Why Writing Plug-ins for Wwise is Important](https://blog.audiokinetic.com/why-writing-plug-ins-for-wwise-is-so-important-for-your-game-projects/)
- [How Sound Designers Use PureData + Heavy to Develop DSP Plugins](https://www.audiokinetic.com/en/blog/how-sound-designers-use-pd-heavy-to-develop-dsp-plugins-part2/)

---

**Document Version:** 1.0
**Last Updated:** January 2026
**Analyst:** Claude (Chief Audio Architect / Lead DSP Engineer / Engine Architect)
