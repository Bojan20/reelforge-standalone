# Miles Sound System — Complete Technical Analysis

> **Analysis Date:** January 2026
> **Version:** Miles 10+
> **Developer:** Epic Games Tools (formerly RAD Game Tools)
> **Analyst Role:** Chief Audio Architect / Lead DSP Engineer / Engine Architect

---

## Executive Summary

Miles Sound System (MSS), originally developed by John Miles as the Audio Interface Library (AIL) and acquired by RAD Game Tools in 1996, is one of the most widely deployed audio middleware solutions in gaming history. With over 7,200 games shipped across 18 platforms, Miles has been trusted by industry giants including Sony, Capcom, Epic, and Microsoft. The system is renowned for its CPU efficiency, cache-friendly architecture, and highly optimized codecs (particularly Bink Audio). Miles 10 represents the latest evolution, designed for AAA complexity (notably Apex Legends) with advanced voice management, streaming, and DSP capabilities.

**Key Characteristics:**
- **Industry veteran** — 7,200+ games, 18 platforms
- **CPU efficiency** — Cache-friendly architecture, optimized FFT kernels
- **Bink Audio** — Proprietary codec with minimal CPU overhead
- **Miles Studio** — Comprehensive authoring toolset
- **AAA scale** — Tens of thousands of audio events
- **Wide platform support** — PC, consoles, mobile

---

## Table of Contents

1. [History & Evolution](#1-history--evolution)
2. [Architecture Overview](#2-architecture-overview)
3. [Core API](#3-core-api)
4. [Voice Management](#4-voice-management)
5. [Streaming System](#5-streaming-system)
6. [Codec Support](#6-codec-support)
7. [DSP & Effects](#7-dsp--effects)
8. [3D Audio](#8-3d-audio)
9. [Bus System](#9-bus-system)
10. [Miles Studio](#10-miles-studio)
11. [Platform Support](#11-platform-support)
12. [Performance Optimization](#12-performance-optimization)
13. [Notable Games](#13-notable-games)
14. [Comparison with Competitors](#14-comparison-with-competitors)
15. [FluxForge Integration Points](#15-fluxforge-integration-points)

---

## 1. History & Evolution

### 1.1 Development Timeline

```
MILES SOUND SYSTEM HISTORY:

1991 — Audio Interface Library (AIL) created by John Miles
       - Original DOS-era audio library
       - Support for Sound Blaster, AdLib

1995 — Acquired by RAD Game Tools
       - Renamed to Miles Sound System
       - Expanded platform support

1998 — Miles 5.0
       - 32-bit Windows support
       - DirectSound integration

2002 — Miles 6.0
       - 3D audio support
       - Xbox support

2006 — Miles 7.0
       - PlayStation 3, Xbox 360 support
       - Enhanced streaming

2011 — Miles 9.0
       - PlayStation Vita, Wii U
       - Android, iOS support
       - PlayStation 4, Xbox One

2018 — Miles 10.0
       - Cache-friendly mixing architecture
       - Bink Audio optimization
       - Opus codec support
       - Designed for Apex Legends scale

2019 — RAD Game Tools acquired by Epic Games
       - Renamed to Epic Games Tools
       - Continued Miles development
```

### 1.2 Industry Impact

```
KEY STATISTICS:

- 7,200+ games licensed
- 18 platforms supported
- Major licensees: Sony, Capcom, Epic, Microsoft, EA
- Decades of continuous development
- Industry standard for many AAA studios
```

---

## 2. Architecture Overview

### 2.1 System Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                    GAME INTEGRATION LAYER                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │  Miles Events   │  │  Miles Banks    │  │   Miles API     │ │
│  │  (Triggers)     │  │  (Assets)       │  │   (C/C++)       │ │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘ │
│           │                    │                    │           │
│           └────────────────────┼────────────────────┘           │
│                                ▼                                 │
├─────────────────────────────────────────────────────────────────┤
│                    MILES RUNTIME ENGINE                          │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                Voice Manager                                 ││
│  │  ┌───────────────┐  ┌───────────────┐  ┌─────────────────┐ ││
│  │  │ Voice Pool    │  │   Priority    │  │   Virtualization│ ││
│  │  │ (Active)      │  │   System      │  │   (Inactive)    │ ││
│  │  └───────┬───────┘  └───────┬───────┘  └────────┬────────┘ ││
│  │          │                  │                   │           ││
│  │          └──────────────────┼───────────────────┘           ││
│  │                             ▼                               ││
│  │  ┌─────────────────────────────────────────────────────────┐││
│  │  │                   Bus System                            │││
│  │  │  ┌───────────┐  ┌───────────┐  ┌─────────────────────┐│││
│  │  │  │   Buses   │→│    DSP    │→│     Mixing          ││││
│  │  │  │ (Routing) │  │  (Effects)│  │ (Cache-friendly)   ││││
│  │  │  └───────────┘  └───────────┘  └─────────────────────┘│││
│  │  └─────────────────────────────────────────────────────────┘││
│  └─────────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│                    CODEC LAYER                                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ Bink Audio  │  │    Opus     │  │        ADPCM            │ │
│  │ (Optimized) │  │  (Quality)  │  │    (Compatibility)      │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                    PLATFORM AUDIO                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │  XAudio2    │  │   OpenAL    │  │  Console-Specific       │ │
│  │ DirectSound │  │  CoreAudio  │  │  (PS, Xbox, Switch)     │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Core Design Principles

```c
// Miles 10 Design Philosophy:

// 1. CPU Efficiency
// - Cache-friendly memory layout
// - Minimal allocations during runtime
// - Optimized mixing loops

// 2. Scalability
// - Handles tens of thousands of events
// - Hierarchical voice management
// - Bus-based resource control

// 3. Flexibility
// - Multiple codec support
// - Platform abstraction
// - DSP extensibility

// 4. Tooling
// - Miles Studio for authoring
// - Text-based project files
// - Team collaboration support
```

### 2.3 Memory Architecture

```c
// Cache-friendly mixing architecture (Miles 10)

// Sample interleaving for cache efficiency
typedef struct MILES_VOICE_CACHE {
    // Voice state packed for cache line alignment
    float position[4];      // 3D position + padding
    float velocity[4];      // 3D velocity + padding
    float volume;           // Current volume
    float target_volume;    // Target for smoothing
    uint32_t flags;         // State flags
    uint32_t priority;      // Voice priority
    // ... additional state
} MILES_VOICE_CACHE;

// Mixing processes voices in cache-friendly batches
// - Voices sorted by bus
// - Similar voices mixed together
// - Minimizes cache misses
```

---

## 3. Core API

### 3.1 Initialization

```c
// Miles initialization

#include "mss.h"

// Initialize Miles
MILES_RESULT result = AIL_startup();
if (result != MILES_SUCCESS) {
    // Handle error
}

// Configure audio output
MILES_PROVIDER* provider = AIL_open_digital_driver(
    44100,          // Sample rate
    16,             // Bits per sample
    2,              // Channels (stereo)
    0               // Flags
);

// Set up mixer
AIL_set_digital_master_volume(provider, 1.0f);
```

### 3.2 Sample/Voice Playback

```c
// Basic sample playback

// Load sample
HSAMPLE sample = AIL_allocate_sample_handle(provider);

// Load from file
AIL_load_sample_from_file(sample, "explosion.wav");

// Configure playback
AIL_set_sample_volume(sample, 0.8f);          // Volume 0-1
AIL_set_sample_pan(sample, 0.0f);             // -1 left, +1 right
AIL_set_sample_playback_rate(sample, 44100);  // Playback rate
AIL_set_sample_loop_count(sample, 1);         // 1 = play once

// Start playback
AIL_start_sample(sample);

// Check status
if (AIL_sample_status(sample) == SAMPLE_PLAYING) {
    // Sample is playing
}

// Stop and release
AIL_stop_sample(sample);
AIL_release_sample_handle(sample);
```

### 3.3 Streaming

```c
// Streaming audio playback

// Allocate stream handle
HSTREAM stream = AIL_allocate_stream_handle(provider);

// Open stream from file
AIL_open_stream_from_file(stream, "music.binka");

// Configure stream
AIL_set_stream_volume(stream, 0.6f);
AIL_set_stream_loop_count(stream, -1);  // -1 = infinite loop

// Start streaming
AIL_start_stream(stream);

// During playback, can adjust:
AIL_set_stream_position(stream, 30000);  // Seek to 30 sec (ms)

// Get playback info
uint32_t position = AIL_stream_position(stream);
uint32_t total = AIL_stream_total_time(stream);

// Stop and close
AIL_close_stream(stream);
```

### 3.4 Event System

```c
// Miles event system (Miles Studio integration)

// Load event bank
MILES_BANK* bank = Miles_load_bank("sfx.mbank");

// Trigger event
MILES_EVENT_INSTANCE* event = Miles_trigger_event(
    bank,
    "Weapon/Rifle/Fire"  // Event path
);

// Set event parameters
Miles_set_event_parameter(event, "Distance", 50.0f);
Miles_set_event_parameter(event, "Material", MATERIAL_METAL);

// Set 3D position
Miles_set_event_3D_position(event, &position, &velocity);

// Stop event
Miles_stop_event(event, MILES_STOP_IMMEDIATE);
// or
Miles_stop_event(event, MILES_STOP_ALLOWFADEOUT);
```

---

## 4. Voice Management

### 4.1 Voice Pool

```c
// Miles voice management

// Configure voice pool
typedef struct MILES_VOICE_CONFIG {
    uint32_t max_voices;           // Maximum concurrent voices
    uint32_t voice_steal_method;   // Steal strategy
    float    steal_volume_threshold;
    uint32_t virtual_voice_count;  // Virtualized voices
} MILES_VOICE_CONFIG;

MILES_VOICE_CONFIG config = {
    .max_voices = 64,
    .voice_steal_method = MILES_STEAL_LOWEST_PRIORITY,
    .steal_volume_threshold = 0.01f,  // -40 dB
    .virtual_voice_count = 256
};

Miles_configure_voices(&config);
```

### 4.2 Priority System

```c
// Voice priority

// Priority levels
typedef enum MILES_PRIORITY {
    MILES_PRIORITY_LOWEST  = 0,
    MILES_PRIORITY_LOW     = 64,
    MILES_PRIORITY_NORMAL  = 128,
    MILES_PRIORITY_HIGH    = 192,
    MILES_PRIORITY_HIGHEST = 255
} MILES_PRIORITY;

// Set sample priority
AIL_set_sample_priority(sample, MILES_PRIORITY_HIGH);

// Priority affects:
// 1. Voice stealing order (lowest priority stolen first)
// 2. Virtualization order
// 3. Bus voice limit enforcement
```

### 4.3 Voice Stealing

```c
// Voice stealing strategies

typedef enum MILES_STEAL_METHOD {
    MILES_STEAL_LOWEST_PRIORITY,     // Steal lowest priority first
    MILES_STEAL_OLDEST,              // Steal oldest voice
    MILES_STEAL_QUIETEST,            // Steal quietest voice
    MILES_STEAL_FARTHEST,            // Steal most distant (3D)
    MILES_STEAL_NONE                 // Don't steal, fail allocation
} MILES_STEAL_METHOD;

// Configure per-bus steal method
Miles_set_bus_steal_method(bus, MILES_STEAL_QUIETEST);

// Voice stealing process:
// 1. Check if voice pool has available voice
// 2. If not, find steal candidate based on method
// 3. Stop/virtualize candidate
// 4. Allocate to new sound
```

### 4.4 Virtualization

```c
// Voice virtualization (track without rendering)

// Configure virtualization
Miles_set_virtualization_enabled(true);
Miles_set_virtualization_threshold(-60.0f);  // dB

// Voices are virtualized when:
// - Volume below threshold
// - Distance beyond audible range
// - Occluded beyond threshold

// Virtualized voices:
// - Continue tracking playback position
// - Update 3D parameters
// - Consume minimal CPU
// - Can become real again when audible
```

---

## 5. Streaming System

### 5.1 Streaming Architecture

```c
// Miles streaming system

// Streaming uses double-buffered I/O
// - Background thread handles file reads
// - Decoding happens just-in-time
// - Minimal memory footprint

typedef struct MILES_STREAM_CONFIG {
    uint32_t buffer_size;          // Buffer size (bytes)
    uint32_t read_ahead_buffers;   // Number of read-ahead buffers
    uint32_t decode_threads;       // Decoder thread count
    bool     async_io;             // Use async I/O
} MILES_STREAM_CONFIG;

MILES_STREAM_CONFIG stream_config = {
    .buffer_size = 32768,          // 32 KB per buffer
    .read_ahead_buffers = 4,
    .decode_threads = 2,
    .async_io = true
};

Miles_configure_streaming(&stream_config);
```

### 5.2 Stream Types

```c
// Different streaming modes

// File streaming (most common)
HSTREAM stream = AIL_open_stream_from_file(provider, "music.binka");

// Memory streaming (pre-loaded)
HSTREAM stream = AIL_open_stream_from_memory(
    provider,
    audio_data,
    audio_size,
    MILES_FORMAT_BINK
);

// Custom I/O streaming
typedef struct MILES_IO_CALLBACKS {
    size_t (*read)(void* buffer, size_t size, void* user);
    int    (*seek)(size_t position, void* user);
    size_t (*tell)(void* user);
    void   (*close)(void* user);
} MILES_IO_CALLBACKS;

HSTREAM stream = AIL_open_stream_from_callbacks(
    provider,
    &callbacks,
    user_data,
    MILES_FORMAT_BINK
);
```

### 5.3 Streaming Best Practices

```c
// Streaming optimization tips

// 1. Use appropriate buffer sizes
// - Smaller = less latency, more I/O
// - Larger = more latency, less I/O
// - 32-64 KB typically optimal

// 2. Limit concurrent streams
// - Each stream requires I/O bandwidth
// - Typically 2-4 simultaneous streams max
// - More on SSD, fewer on HDD

// 3. Use Bink Audio for streaming
// - Lowest CPU decode cost
// - Good compression ratio
// - Designed for real-time

// 4. Pre-warm streams for critical audio
Miles_prewarm_stream(stream, 500);  // Pre-buffer 500ms
```

---

## 6. Codec Support

### 6.1 Bink Audio (Recommended)

```c
// Bink Audio - RAD's proprietary codec

// Characteristics:
// - Extremely fast decoding
// - ~10x faster than Opus
// - Good quality at reasonable bitrates
// - Optimized FFT kernels
// - Low memory footprint

// Usage
HSTREAM bink_stream = AIL_open_stream_from_file(
    provider,
    "audio.binka"  // Bink Audio extension
);

// Typical bitrates:
// - Speech: 32-48 kbps
// - Music: 96-128 kbps
// - SFX: 64-96 kbps

// Why Bink Audio?
// "Opus is around 10x slower than Bink Audio"
// "Can use compressed audio with ridiculously tiny CPU bump"
```

### 6.2 Opus

```c
// Opus codec support (Miles 10+)

// Opus characteristics:
// - Better compression than Bink (~2x)
// - Higher CPU usage (~10x Bink)
// - Excellent quality at low bitrates
// - Open standard

// When to use Opus:
// - Memory-constrained platforms
// - Quality-critical audio
// - When CPU budget allows

// Note: Opus distributed separately due to licensing
```

### 6.3 ADPCM

```c
// ADPCM (legacy support)

// ADPCM characteristics:
// - 4:1 compression ratio
// - Very low CPU decode
// - Lower quality than modern codecs
// - Wide compatibility

// Usage (legacy files)
HSAMPLE sample = AIL_allocate_sample_handle(provider);
AIL_load_sample_from_file(sample, "legacy.wav");  // IMA-ADPCM
```

### 6.4 Codec Comparison

```
CODEC COMPARISON:

| Codec      | CPU Usage  | Compression | Quality    | Use Case          |
|------------|------------|-------------|------------|-------------------|
| Bink Audio | Very Low   | Good        | Good       | Default choice    |
| Opus       | Medium     | Excellent   | Excellent  | Memory-critical   |
| ADPCM      | Very Low   | Moderate    | Fair       | Legacy/compat     |
| PCM        | None       | None        | Perfect    | Critical timing   |

Miles 10 removed:
- MP3 (obviated by Opus)
- Vorbis (memory performance issues)
```

---

## 7. DSP & Effects

### 7.1 Built-in Effects

```c
// Miles includes 18 DSP filters

typedef enum MILES_DSP_TYPE {
    // Filters
    MILES_DSP_LOWPASS,
    MILES_DSP_HIGHPASS,
    MILES_DSP_BANDPASS,
    MILES_DSP_NOTCH,

    // Dynamics
    MILES_DSP_COMPRESSOR,
    MILES_DSP_LIMITER,

    // EQ
    MILES_DSP_PARAMETRIC_EQ,
    MILES_DSP_GRAPHIC_EQ,

    // Modulation
    MILES_DSP_CHORUS,
    MILES_DSP_FLANGER,
    MILES_DSP_PHASER,

    // Distortion
    MILES_DSP_DISTORTION,
    MILES_DSP_OVERDRIVE,

    // Time-based
    MILES_DSP_ECHO,
    MILES_DSP_DELAY,

    // Pitch
    MILES_DSP_PITCH_SHIFT,

    // Spatial
    MILES_DSP_REVERB,
    MILES_DSP_CONVOLUTION
} MILES_DSP_TYPE;
```

### 7.2 DSP Application

```c
// Applying DSP effects

// Create effect
MILES_DSP* lowpass = Miles_create_dsp(MILES_DSP_LOWPASS);

// Configure parameters
Miles_set_dsp_parameter(lowpass, MILES_PARAM_CUTOFF, 2000.0f);
Miles_set_dsp_parameter(lowpass, MILES_PARAM_RESONANCE, 1.0f);

// Apply to sample
Miles_add_sample_dsp(sample, lowpass);

// Apply to bus
Miles_add_bus_dsp(bus, lowpass);

// Apply globally
Miles_add_master_dsp(lowpass);

// Bypass effect
Miles_set_dsp_bypass(lowpass, true);

// Remove effect
Miles_remove_sample_dsp(sample, lowpass);
Miles_destroy_dsp(lowpass);
```

### 7.3 Custom DSP

```c
// Creating custom DSP effects

typedef struct MILES_CUSTOM_DSP {
    // Callback for processing
    void (*process)(
        float* input,
        float* output,
        uint32_t samples,
        uint32_t channels,
        void* user_data
    );

    // Parameter info
    uint32_t param_count;
    MILES_DSP_PARAM* params;

    // User data
    void* user_data;
} MILES_CUSTOM_DSP;

// Example: Simple gain effect
void gain_process(float* input, float* output, uint32_t samples,
                  uint32_t channels, void* user_data) {
    float gain = *(float*)user_data;

    for (uint32_t i = 0; i < samples * channels; ++i) {
        output[i] = input[i] * gain;
    }
}

// Register custom DSP
MILES_DSP_PARAM gain_params[] = {
    { "Gain", 0.0f, 2.0f, 1.0f }
};

MILES_CUSTOM_DSP gain_dsp = {
    .process = gain_process,
    .param_count = 1,
    .params = gain_params,
    .user_data = &gain_value
};

MILES_DSP* custom = Miles_create_custom_dsp(&gain_dsp);
```

### 7.4 Reverb & Convolution

```c
// Reverb types

// Algorithmic reverb
MILES_DSP* reverb = Miles_create_dsp(MILES_DSP_REVERB);
Miles_set_dsp_parameter(reverb, MILES_PARAM_ROOM_SIZE, 0.8f);
Miles_set_dsp_parameter(reverb, MILES_PARAM_DAMPING, 0.5f);
Miles_set_dsp_parameter(reverb, MILES_PARAM_WET, 0.3f);
Miles_set_dsp_parameter(reverb, MILES_PARAM_DRY, 0.7f);

// Convolution reverb
MILES_DSP* conv = Miles_create_dsp(MILES_DSP_CONVOLUTION);
Miles_load_convolution_ir(conv, "impulse_response.wav");
Miles_set_dsp_parameter(conv, MILES_PARAM_WET, 0.4f);
```

---

## 8. 3D Audio

### 8.1 3D Positioning

```c
// 3D audio positioning

// Set listener position/orientation
typedef struct MILES_3D_LISTENER {
    float position[3];
    float velocity[3];
    float front[3];
    float top[3];
} MILES_3D_LISTENER;

MILES_3D_LISTENER listener = {
    .position = { 0, 0, 0 },
    .velocity = { 0, 0, 0 },
    .front = { 0, 0, 1 },
    .top = { 0, 1, 0 }
};

AIL_set_3D_listener(provider, &listener);

// Set sample 3D properties
typedef struct MILES_3D_SAMPLE {
    float position[3];
    float velocity[3];
    float min_distance;
    float max_distance;
    float cone_inner_angle;
    float cone_outer_angle;
    float cone_outer_volume;
} MILES_3D_SAMPLE;

MILES_3D_SAMPLE sample_3d = {
    .position = { 10, 0, 5 },
    .velocity = { 0, 0, 0 },
    .min_distance = 1.0f,
    .max_distance = 100.0f,
    .cone_inner_angle = 360.0f,  // Omnidirectional
    .cone_outer_angle = 360.0f,
    .cone_outer_volume = 1.0f
};

AIL_set_sample_3D_properties(sample, &sample_3d);
```

### 8.2 Distance Attenuation

```c
// Distance attenuation models

typedef enum MILES_ATTENUATION_MODEL {
    MILES_ATTEN_INVERSE,           // 1/distance
    MILES_ATTEN_INVERSE_SQUARED,   // 1/distance²
    MILES_ATTEN_LINEAR,            // Linear falloff
    MILES_ATTEN_NONE               // No attenuation
} MILES_ATTENUATION_MODEL;

AIL_set_sample_attenuation_model(sample, MILES_ATTEN_INVERSE_SQUARED);

// Custom attenuation curve
float attenuation_curve[] = {
    0.0f, 1.0f,      // At 0% distance = full volume
    0.25f, 0.8f,     // At 25% = 80%
    0.5f, 0.5f,      // At 50% = 50%
    0.75f, 0.2f,     // At 75% = 20%
    1.0f, 0.0f       // At 100% = silent
};

AIL_set_sample_attenuation_curve(sample, attenuation_curve, 5);
```

### 8.3 Doppler Effect

```c
// Doppler effect configuration

// Global doppler settings
Miles_set_doppler_factor(1.0f);       // 1.0 = realistic
Miles_set_speed_of_sound(343.0f);     // m/s

// Per-sample doppler
AIL_set_sample_doppler_factor(sample, 1.5f);  // Exaggerated

// Doppler is calculated from:
// - Listener velocity
// - Source velocity
// - Relative positions
```

### 8.4 Occlusion & Obstruction

```c
// Occlusion system

// Set occlusion amount (0-1)
// 0 = no occlusion, 1 = fully occluded
AIL_set_sample_occlusion(sample, 0.5f);

// Occlusion affects:
// - Volume attenuation
// - Low-pass filtering (muffled sound)

// Typical implementation:
void update_occlusion(HSAMPLE sample, float* listener_pos, float* source_pos) {
    // Raycast from listener to source
    float occlusion = raycast_occlusion(listener_pos, source_pos);

    // Apply to sample
    AIL_set_sample_occlusion(sample, occlusion);
}
```

### 8.5 Speaker Configurations

```c
// Supported speaker modes

typedef enum MILES_SPEAKER_MODE {
    MILES_SPEAKERS_MONO,          // 1 channel
    MILES_SPEAKERS_STEREO,        // 2 channels
    MILES_SPEAKERS_HEADPHONE,     // 2 channels (HRTF)
    MILES_SPEAKERS_3_0,           // 3 channels
    MILES_SPEAKERS_4_0,           // 4 channels
    MILES_SPEAKERS_5_1,           // 5.1 surround
    MILES_SPEAKERS_6_1,           // 6.1 surround
    MILES_SPEAKERS_7_1,           // 7.1 surround
    MILES_SPEAKERS_8_1,           // 8.1 surround
    MILES_SPEAKERS_ATMOS          // Dolby Atmos (object-based)
} MILES_SPEAKER_MODE;

AIL_set_speaker_configuration(provider, MILES_SPEAKERS_7_1);
```

---

## 9. Bus System

### 9.1 Bus Architecture

```c
// Miles bus system

// Buses provide:
// - Hierarchical voice management
// - Group volume control
// - Shared DSP effects
// - Voice limit enforcement

// Create bus
MILES_BUS* sfx_bus = Miles_create_bus("SFX");
MILES_BUS* music_bus = Miles_create_bus("Music");
MILES_BUS* voice_bus = Miles_create_bus("Voice");

// Set bus parent (routing)
Miles_set_bus_parent(sfx_bus, master_bus);
Miles_set_bus_parent(music_bus, master_bus);

// Bus hierarchy example:
// Master
// ├── SFX
// │   ├── Weapons
// │   ├── Footsteps
// │   └── Environment
// ├── Music
// │   ├── Combat
// │   └── Ambient
// └── Voice
//     ├── Dialog
//     └── VO
```

### 9.2 Bus Properties

```c
// Bus configuration

// Volume (dB)
Miles_set_bus_volume(sfx_bus, -6.0f);

// Mute/Solo
Miles_set_bus_mute(music_bus, true);
Miles_set_bus_solo(voice_bus, true);

// Voice limits
Miles_set_bus_voice_limit(sfx_bus, 32);
Miles_set_bus_voice_steal_method(sfx_bus, MILES_STEAL_QUIETEST);

// Duck (sidechain)
Miles_set_bus_duck_target(music_bus, voice_bus);
Miles_set_bus_duck_amount(music_bus, -10.0f);
Miles_set_bus_duck_attack(music_bus, 50.0f);   // ms
Miles_set_bus_duck_release(music_bus, 500.0f); // ms
```

### 9.3 Bus DSP

```c
// Applying DSP to buses

// Add reverb to SFX bus
MILES_DSP* reverb = Miles_create_dsp(MILES_DSP_REVERB);
Miles_add_bus_dsp(sfx_bus, reverb);

// Add compressor to master
MILES_DSP* comp = Miles_create_dsp(MILES_DSP_COMPRESSOR);
Miles_set_dsp_parameter(comp, MILES_PARAM_THRESHOLD, -12.0f);
Miles_set_dsp_parameter(comp, MILES_PARAM_RATIO, 4.0f);
Miles_add_bus_dsp(master_bus, comp);

// Add limiter to master (safety)
MILES_DSP* limiter = Miles_create_dsp(MILES_DSP_LIMITER);
Miles_set_dsp_parameter(limiter, MILES_PARAM_CEILING, -0.3f);
Miles_add_bus_dsp(master_bus, limiter);
```

---

## 10. Miles Studio

### 10.1 Overview

```
MILES STUDIO:

Comprehensive authoring toolset for Miles Sound System.

Features:
- Sound bank creation and management
- Event authoring
- DSP effect configuration
- Compression settings
- Bus routing visualization
- Game parameter integration
- Localization support
- Team collaboration

Project Structure:
- Text-based project files
- Easy diffs and version control
- Multiple designers can work simultaneously
- Conflict-free parallel workflows
```

### 10.2 Event Authoring

```
EVENT SYSTEM IN MILES STUDIO:

Events are the primary interface between game code and audio:

Event Types:
├── One-shot Events
│   └── Single sound trigger (gunshot, UI click)
├── Looping Events
│   └── Continuous sounds (engine, ambience)
├── Random Events
│   └── Random selection from pool
├── Sequential Events
│   └── Plays sounds in order
└── Parametric Events
    └── Sound varies with game parameters

Event Properties:
- Volume/pitch/pan
- Randomization ranges
- Priority
- Bus assignment
- 3D properties
- DSP effects
- Game parameters
```

### 10.3 Parameter System

```c
// Game parameters in Miles

// Define parameters in Miles Studio
// Access from game code:

// Set global parameter
Miles_set_global_parameter("HealthPercent", 0.25f);

// Set event-local parameter
Miles_set_event_parameter(event, "RPM", engine_rpm);
Miles_set_event_parameter(event, "Speed", vehicle_speed);

// Parameters can control:
// - Volume curves
// - Pitch curves
// - DSP effect parameters
// - Event selection
// - Crossfades between layers
```

### 10.4 Localization

```
LOCALIZATION IN MILES STUDIO:

Miles Studio supports multi-language audio:

1. Define language variants in project
2. Create localized versions of dialogue events
3. Runtime language switching
4. Fallback handling for missing variants

Code:
Miles_set_language("en-US");  // or "ja-JP", "de-DE", etc.
```

---

## 11. Platform Support

### 11.1 Supported Platforms

```
MILES PLATFORM SUPPORT:

Desktop:
├── Windows (32-bit, 64-bit)
├── macOS (Intel, Apple Silicon)
└── Linux (32-bit, 64-bit)

Console:
├── PlayStation 4
├── PlayStation 5
├── Xbox One
├── Xbox Series X|S
└── Nintendo Switch

Mobile:
├── iOS
└── Android

Legacy (historical):
├── PlayStation 2
├── PlayStation 3
├── PlayStation Portable
├── PlayStation Vita
├── Xbox 360
├── Wii
├── Wii U
└── 3DS
```

### 11.2 Platform-Specific Features

```c
// Platform-specific APIs

#ifdef PLATFORM_PLAYSTATION
    // PlayStation audio features
    Miles_enable_ps5_3d_audio(true);
    Miles_set_ps_audio_port(port_handle);
#endif

#ifdef PLATFORM_XBOX
    // Xbox audio features
    Miles_enable_spatial_audio(MILES_SPATIAL_ATMOS);
    Miles_set_xaudio_device(device_id);
#endif

#ifdef PLATFORM_SWITCH
    // Nintendo Switch features
    Miles_set_switch_audio_output(MILES_SWITCH_TV);
#endif
```

---

## 12. Performance Optimization

### 12.1 CPU Optimization

```c
// Miles 10 optimization strategies

// 1. Use Bink Audio for compressed content
// - 10x faster than Opus decoding
// - Minimal CPU impact even with many voices

// 2. Leverage voice limits
// - Set appropriate per-bus limits
// - Use virtualization for distant/quiet sounds

// 3. Cache-friendly processing
// - Miles 10 processes voices in batches
// - Minimizes cache misses
// - Sorts by bus for efficiency

// 4. Avoid per-frame allocations
// - Pre-allocate voice pools
// - Reuse event instances
// - Use streaming for large files
```

### 12.2 Memory Optimization

```c
// Memory management

// 1. Use streaming for music/ambient
// - Minimal memory footprint
// - Decode on-the-fly

// 2. Use appropriate compression
// - Bink Audio for most content
// - ADPCM for very short sounds

// 3. Bank management
// - Load only needed banks
// - Unload when leaving areas
// - Use async loading

// 4. Voice pool sizing
// - Don't over-allocate
// - Use virtualization instead
```

### 12.3 I/O Optimization

```c
// Streaming I/O optimization

// 1. Use async I/O
Miles_set_async_io(true);

// 2. Appropriate buffer sizes
Miles_set_stream_buffer_size(32 * 1024);  // 32 KB

// 3. Limit concurrent streams
// - HDD: 2-3 streams max
// - SSD: 4-6 streams

// 4. Pre-warm critical audio
Miles_prewarm_stream(stream, 500);  // 500ms buffer
```

---

## 13. Notable Games

### 13.1 Major Titles Using Miles

```
NOTABLE GAMES USING MILES SOUND SYSTEM:

AAA Titles:
- Apex Legends (EA/Respawn)
- Titanfall series (EA/Respawn)
- Call of Duty series (Activision)
- Battlefield series (EA/DICE)
- Mass Effect series (BioWare)
- Dragon Age series (BioWare)
- Star Wars: Knights of the Old Republic (BioWare)
- Halo series (Bungie/343)
- Forza series (Turn 10)

Classic Titles:
- Half-Life (Valve)
- Deus Ex (Ion Storm)
- System Shock 2 (Looking Glass)
- Thief series (Looking Glass)
- StarCraft (Blizzard)
- Diablo II (Blizzard)
- Baldur's Gate series (BioWare)
```

### 13.2 Apex Legends Case Study

```
APEX LEGENDS (Miles 10 Design Target):

Challenges:
- Tens of thousands of audio events
- 60 players in battle royale
- Complex weapon systems
- Dynamic environment audio
- Performance on multiple platforms

Miles Solutions:
- Scalable voice management
- Bus-based voice limits
- Efficient Bink Audio decoding
- Cache-friendly mixing
- Priority-based voice stealing
```

---

## 14. Comparison with Competitors

### 14.1 Miles vs Wwise

| Feature | Miles | Wwise |
|---------|-------|-------|
| **CPU Efficiency** | Excellent (Bink) | Good |
| **Authoring Tool** | Miles Studio | Wwise Authoring |
| **Event System** | Good | Excellent |
| **Interactive Music** | Basic | Advanced |
| **Learning Curve** | Medium | Steep |
| **Cost** | Licensed | Licensed |
| **Platform Support** | Excellent | Excellent |

### 14.2 Miles vs FMOD

| Feature | Miles | FMOD |
|---------|-------|------|
| **CPU Efficiency** | Excellent | Good |
| **Authoring Tool** | Miles Studio | FMOD Studio |
| **DSP System** | 18 built-in | More extensive |
| **Indie Friendly** | Licensed | Free tier |
| **Live Update** | Limited | Excellent |
| **Music System** | Basic | Good |

### 14.3 When to Choose Miles

```
CHOOSE MILES WHEN:

✓ CPU efficiency is critical
✓ Large voice counts needed
✓ Bink Video already in use (synergy)
✓ AAA scale requirements
✓ Historical familiarity (existing team expertise)
✓ Need for cache-friendly architecture

CONSIDER ALTERNATIVES WHEN:

✗ Complex interactive music required
✗ Indie budget constraints
✗ Live update/iteration focus
✗ Team unfamiliar with Miles
```

---

## 15. FluxForge Integration Points

### 15.1 Applicable Concepts

| Miles Concept | FluxForge Application |
|---------------|----------------------|
| **Voice management** | Pool and priority system |
| **Bus architecture** | Hierarchical routing |
| **Cache-friendly mixing** | Performance optimization |
| **Codec efficiency** | Format selection |
| **Streaming system** | Large file handling |
| **DSP chain** | Effect processing |

### 15.2 Technical Insights

```rust
// Key lessons from Miles for FluxForge:

// 1. Cache-friendly voice processing
pub struct VoiceCache {
    // Pack voice data for cache efficiency
    positions: Vec<[f32; 4]>,      // Position + padding
    volumes: Vec<f32>,
    priorities: Vec<u32>,
    states: Vec<VoiceState>,
}

impl VoiceCache {
    pub fn process_batch(&mut self, output: &mut [f32]) {
        // Process voices in cache-friendly order
        // - Group by bus
        // - Process similar voices together
        // - Minimize cache misses
    }
}

// 2. Voice stealing with priority
pub struct VoiceManager {
    active_voices: Vec<Voice>,
    virtual_voices: Vec<VirtualVoice>,
    max_active: usize,
    steal_method: StealMethod,
}

impl VoiceManager {
    pub fn allocate(&mut self, priority: u8) -> Option<&mut Voice> {
        if let Some(free) = self.find_free_voice() {
            return Some(free);
        }

        // Find steal candidate
        match self.steal_method {
            StealMethod::LowestPriority => self.steal_lowest_priority(priority),
            StealMethod::Quietest => self.steal_quietest(),
            StealMethod::Oldest => self.steal_oldest(),
        }
    }
}

// 3. Bus hierarchy with voice limits
pub struct AudioBus {
    name: String,
    parent: Option<BusId>,
    children: Vec<BusId>,
    voice_limit: Option<u32>,
    active_voice_count: u32,
    volume_db: f32,
    effects: Vec<Box<dyn Effect>>,
}

impl AudioBus {
    pub fn can_add_voice(&self) -> bool {
        match self.voice_limit {
            Some(limit) => self.active_voice_count < limit,
            None => true,
        }
    }
}

// 4. Efficient codec abstraction
pub trait AudioCodec: Send + Sync {
    fn decode(&mut self, input: &[u8], output: &mut [f32]) -> usize;
    fn cpu_cost(&self) -> CodecCost;  // Low, Medium, High
    fn compression_ratio(&self) -> f32;
}
```

### 15.3 Key Takeaways

1. **CPU efficiency matters** — Bink Audio shows codec choice impacts performance dramatically
2. **Cache-friendly design** — Memory layout affects mixing performance
3. **Voice management** — Priority + virtualization essential for scale
4. **Bus hierarchy** — Hierarchical limits simplify complex mixes
5. **Streaming architecture** — Double-buffered async I/O for large files
6. **Codec selection** — Balance between quality, size, and CPU
7. **Tool integration** — Miles Studio demonstrates authoring importance

---

## Appendix A: API Reference

```c
// Core Miles API (selected functions)

// Initialization
MILES_RESULT AIL_startup(void);
void AIL_shutdown(void);
MILES_PROVIDER* AIL_open_digital_driver(int rate, int bits, int channels, int flags);
void AIL_close_digital_driver(MILES_PROVIDER* provider);

// Sample playback
HSAMPLE AIL_allocate_sample_handle(MILES_PROVIDER* provider);
void AIL_release_sample_handle(HSAMPLE sample);
MILES_RESULT AIL_load_sample_from_file(HSAMPLE sample, const char* path);
void AIL_start_sample(HSAMPLE sample);
void AIL_stop_sample(HSAMPLE sample);
int AIL_sample_status(HSAMPLE sample);

// Sample properties
void AIL_set_sample_volume(HSAMPLE sample, float volume);
void AIL_set_sample_pan(HSAMPLE sample, float pan);
void AIL_set_sample_playback_rate(HSAMPLE sample, int rate);
void AIL_set_sample_loop_count(HSAMPLE sample, int count);

// Streaming
HSTREAM AIL_allocate_stream_handle(MILES_PROVIDER* provider);
MILES_RESULT AIL_open_stream_from_file(HSTREAM stream, const char* path);
void AIL_start_stream(HSTREAM stream);
void AIL_stop_stream(HSTREAM stream);
void AIL_close_stream(HSTREAM stream);

// 3D Audio
void AIL_set_3D_listener(MILES_PROVIDER* provider, MILES_3D_LISTENER* listener);
void AIL_set_sample_3D_properties(HSAMPLE sample, MILES_3D_SAMPLE* props);
```

---

## Appendix B: References

- [Miles Sound System Official](https://www.radgametools.com/miles.htm)
- [Miles Studio Features](https://www.radgametools.com/msssdk.htm)
- [Miles Development History](https://www.radgametools.com/msshist.htm)
- [Miles Sound System Wikipedia](https://en.wikipedia.org/wiki/Miles_Sound_System)
- [PCGamingWiki - Miles](https://www.pcgamingwiki.com/wiki/Miles_Sound_System)

---

*Analysis complete. Document serves as reference for FluxForge audio engine development.*
